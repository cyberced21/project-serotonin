class_name DayNightSky
extends Node
## Lights the world for the time of day (see the DayNight autoload): swings the sun across the
## sky (and a pale blue moon at night), blends the sky (shaders/sky.gdshader: gradient, sun or
## moon disc, stars), fog and ambient light between day, dusk and night palettes, and makes
## lamps, lanterns and windows glow after dark.
## Glowing things: meshes in the "night_glow" group get the palette shader's `glow` instance
## uniform; lights in the "night_light" group fade in (their energy at full night is stored as
## the "night_energy" meta).
## The biome you're in tints all this (see the Biome autoload): its fog, ambient and sun factors
## multiply the time of day's values, so the forest is dim and green at noon and dark at night.
## Every colour and number here comes from the SkyLook (data/sky_look.tres), tunable live in the
## debug menu's Sky tab.
## Also: distance haze that leaves the valley clear, a thin volumetric mist (with mist lying low
## over the water in the morning: WaterBody's Mist volumes) with light shafts strongest when the
## sun is low, the colour grade (ColorGrade: the biome's tints times the time of
## day's, cool blue nights, a golden sunrise and a pink sunset), and lamplight that flickers.

@export var sun: DirectionalLight3D
@export var environment: WorldEnvironment
## Compass direction (yaw, radians) the sun rises from; it sets opposite.
@export var sunrise_yaw := 1.2
## Highest the sun gets at noon (radians above the horizon).
@export var max_elevation := 1.15

var _sky: ShaderMaterial
var _glow := -1.0
var _grade: Array[Color] = [Color.WHITE, Color.WHITE]


func _ready() -> void:
	if environment and environment.environment.sky:
		_sky = environment.environment.sky.sky_material as ShaderMaterial
	_update()


func _process(_delta: float) -> void:
	_update()


func _update() -> void:
	var look := SkyLook.active()
	var h := DayNight.sun_height()          # -1..1
	var dusk := DayNight.sky_twilight(look.twilight_day_side, look.twilight_night_side)
	var day := smoothstep(-0.12, 0.15, h)   # 0 at night, 1 by day
	var night := 1.0 - day
	# sunrise and sunset each have their own palette (golden morning, pink evening)
	var morning := DayNight.is_morning()
	var tw_top := look.sunrise_top if morning else look.sunset_top
	var tw_horizon := look.sunrise_horizon if morning else look.sunset_horizon
	var tw_light := look.sunrise_light if morning else look.sunset_light
	var afterglow := dusk * night * look.afterglow  # twilight with the sun below the horizon

	# the sun by day, the moon by night: same light, swung across the sky east -> west
	if sun:
		var d := DayNight.day_progress()
		var across := d if d >= 0.0 else DayNight.night_progress()
		var elev := sin(PI * across) * max_elevation + 0.04
		var yaw := sunrise_yaw + PI * across
		sun.rotation = Vector3(-elev, yaw, 0.0)
		var sun_color := tw_light.lerp(look.noon_light, clampf(h * 2.0, 0.0, 1.0))
		sun.light_color = sun_color.lerp(look.moon_light, night).lerp(tw_light, afterglow) * Biome.sun_tint
		var energy := lerpf(look.low_energy, look.noon_energy, clampf(h * 1.5, 0.0, 1.0))
		sun.light_energy = lerpf(lerpf(look.moon_energy, look.low_energy, afterglow), energy, day)
		sun.shadow_opacity = lerpf(0.55, look.shadow_strength, day)
		# light shafts through the mist: strongest with the sun low
		var shafts := lerpf(0.4, lerpf(2.4, 0.9, clampf(h * 2.0, 0.0, 1.0)), day)
		sun.light_volumetric_fog_energy = shafts * look.shafts

	var top := look.night_top.lerp(look.day_top, day)
	var horizon := look.night_horizon.lerp(look.day_horizon, day)
	top = top.lerp(tw_top, dusk * look.twilight_top)
	horizon = horizon.lerp(tw_horizon, dusk * look.twilight_horizon)
	if _sky:
		_sky.set_shader_parameter("top_color", top)
		_sky.set_shader_parameter("horizon_color", horizon)
		_sky.set_shader_parameter("ground_color", horizon.darkened(0.5))
		_sky.set_shader_parameter("night", night)
		_sky.set_shader_parameter("cloud_tint", look.sunrise_clouds if morning else look.sunset_clouds)
		_sky.set_shader_parameter("cloud_tint_amount", dusk * 0.8)
		_sky.set_shader_parameter("sun_size", look.sun_size)
		_sky.set_shader_parameter("sun_brightness", look.sun_brightness)
		_sky.set_shader_parameter("sun_halo", look.sun_halo)
		_sky.set_shader_parameter("sun_halo_falloff", look.sun_halo_falloff)
		_sky.set_shader_parameter("sun_glow", look.sun_glow)
		_sky.set_shader_parameter("sun_glow_low", look.sun_glow_low)
	if environment:
		var env := environment.environment
		env.tonemap_exposure = look.exposure
		env.glow_hdr_threshold = look.glow_threshold
		env.glow_intensity = look.glow_intensity
		env.fog_light_color = horizon * Biome.fog_tint
		env.fog_mode = Environment.FOG_MODE_DEPTH
		env.fog_depth_begin = look.fog_begin
		env.fog_depth_end = look.fog_end
		env.fog_depth_curve = look.fog_curve
		env.fog_density = look.fog_haze * minf(Biome.fog_density, look.biome_cap)
		env.fog_aerial_perspective = look.fog_aerial
		var lit := maxf(day, afterglow)
		env.ambient_light_energy = lerpf(look.night_ambient, look.day_ambient, lit) * Biome.ambient
		env.background_energy_multiplier = lerpf(look.night_sky, 1.0, lit)
		var dawn := 1.0 - smoothstep(0.0, look.mist_width, absf(DayNight.time - look.mist_peak))
		var thicker := 1.0 + look.morning_mist * dawn + look.night_mist * night
		env.volumetric_fog_density = look.mist_density * minf(Biome.mist, look.biome_cap) * thicker
		WaterBody.mist_material().density = look.water_mist * dawn
		env.volumetric_fog_albedo = (horizon * Biome.fog_tint).lerp(Color.WHITE, 0.45)
		_update_grade(env, look, morning, dusk, day)

	# lamps, lanterns and windows
	var glow := smoothstep(0.15, 0.85, night)
	if absf(glow - _glow) > 0.01:
		_glow = glow
		for g in get_tree().get_nodes_in_group("night_glow"):
			(g as GeometryInstance3D).set_instance_shader_parameter("glow", glow)
		for l in get_tree().get_nodes_in_group("night_light"):
			(l as Light3D).visible = glow > 0.01
	if _glow > 0.01:  # firelight flickers, each lamp out of step
		var t := Time.get_ticks_msec() / 1000.0
		for l in get_tree().get_nodes_in_group("night_light"):
			var light := l as Light3D
			var ph := float(light.get_instance_id() % 997)
			var flicker := 1.0 + 0.1 * sin(t * 8.3 + ph) + 0.06 * sin(t * 21.7 + ph * 1.7)
			light.light_energy = _glow * float(light.get_meta("night_energy", 1.0)) * flicker


## Rebuilds the colour-grading table when the grade (biome tints times the time of day's) moves.
func _update_grade(env: Environment, look: SkyLook, morning: bool, dusk: float, day: float) -> void:
	var dark := look.sunrise_grade_dark if morning else look.sunset_grade_dark
	var bright := look.sunrise_grade_bright if morning else look.sunset_grade_bright
	# night's grade, or noon's by day, then the twilight's over either
	var shadows := look.night_grade_dark.lerp(look.noon_grade_dark, day).lerp(dark, dusk)
	var highlights := look.night_grade_bright.lerp(look.noon_grade_bright, day).lerp(bright, dusk)
	shadows *= Biome.shadow_tint
	highlights *= Biome.highlight_tint
	if env.adjustment_color_correction and _close(shadows, _grade[0]) and _close(highlights, _grade[1]):
		return
	_grade = [shadows, highlights]
	env.adjustment_enabled = true
	env.adjustment_color_correction = ColorGrade.make_lut(shadows, highlights)


static func _close(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) < 0.006 and absf(a.g - b.g) < 0.006 and absf(a.b - b.b) < 0.006


## Marks `mesh` as something that glows after dark; with `light`, also hangs a small warm lamp
## light on it. Used by buildings and props for lamps, lanterns and windows.
static func make_glow(mesh: MeshInstance3D, light := false) -> void:
	mesh.add_to_group("night_glow")
	if light:
		var omni := OmniLight3D.new()
		omni.light_color = Color(1.0, 0.72, 0.42)
		omni.omni_range = 9.0
		omni.omni_attenuation = 1.3
		omni.shadow_enabled = GraphicsSettings.get_value(&"light_shadows")
		omni.set_meta("night_energy", 2.4)
		omni.light_energy = 0.0
		omni.visible = false
		omni.add_to_group("night_light")
		mesh.add_child(omni)
		omni.position = mesh.get_aabb().get_center()
