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
## Also: volumetric mist (thick at dawn, thinner by day, the biome's own on top) with light shafts
## strongest when the sun is low, the colour grade (ColorGrade: the biome's tints times the time of
## day's, cool blue nights and a warm dusk), and lamplight that flickers.

@export var sun: DirectionalLight3D
@export var environment: WorldEnvironment
## Compass direction (yaw, radians) the sun rises from; it sets opposite.
@export var sunrise_yaw := 1.2
## Highest the sun gets at noon (radians above the horizon).
@export var max_elevation := 1.15

const DAY_TOP := Color(0.36, 0.47, 0.62)
const DAY_HORIZON := Color(0.66, 0.74, 0.78)
const DUSK_TOP := Color(0.33, 0.35, 0.55)
const DUSK_HORIZON := Color(0.95, 0.63, 0.45)
const NIGHT_TOP := Color(0.03, 0.05, 0.11)
const NIGHT_HORIZON := Color(0.11, 0.15, 0.25)
const SUN_NOON := Color(1.0, 0.97, 0.9)
const SUN_LOW := Color(1.0, 0.68, 0.42)
const MOON := Color(0.58, 0.68, 1.0)
## The time of day's grade: (darks, brights) tints at dusk and at night (by day: none).
const DUSK_GRADE := [Color(0.94, 0.9, 1.05), Color(1.07, 0.97, 0.85)]
const NIGHT_GRADE := [Color(0.84, 0.92, 1.14), Color(0.92, 0.98, 1.08)]
## When the morning mist is thickest (DayNight time), and how much thicker than by day.
const MIST_PEAK := 0.19
const MORNING_MIST := 2.2

var _sky: ShaderMaterial
var _glow := -1.0
var _fog_density := 0.0  # the scene's own, before the biome's factor
var _mist_density := 0.0  # the scene's own volumetric fog density
var _grade: Array[Color] = [Color.WHITE, Color.WHITE]


func _ready() -> void:
	if environment and environment.environment.sky:
		_sky = environment.environment.sky.sky_material as ShaderMaterial
	if environment:
		_fog_density = environment.environment.fog_density
		_mist_density = environment.environment.volumetric_fog_density
	_update()


func _process(_delta: float) -> void:
	_update()


func _update() -> void:
	var h := DayNight.sun_height()          # -1..1
	var dusk := DayNight.twilight()         # 1 at sunrise / sunset
	var day := smoothstep(-0.12, 0.15, h)   # 0 at night, 1 by day
	var night := 1.0 - day

	# the sun by day, the moon by night: same light, swung across the sky east -> west
	if sun:
		var d := DayNight.day_progress()
		var across := d if d >= 0.0 else DayNight.night_progress()
		var elev := sin(PI * across) * max_elevation + 0.04
		var yaw := sunrise_yaw + PI * across
		sun.rotation = Vector3(-elev, yaw, 0.0)
		var sun_color := SUN_LOW.lerp(SUN_NOON, clampf(h * 2.0, 0.0, 1.0))
		sun.light_color = sun_color.lerp(MOON, night) * Biome.sun_tint
		sun.light_energy = lerpf(0.24, lerpf(0.55, 1.0, clampf(h * 1.5, 0.0, 1.0)), day)
		sun.shadow_opacity = lerpf(0.55, 1.0, day)
		# light shafts through the mist: strongest with the sun low
		sun.light_volumetric_fog_energy = lerpf(0.4, lerpf(2.4, 0.9, clampf(h * 2.0, 0.0, 1.0)), day)

	var top := NIGHT_TOP.lerp(DAY_TOP, day)
	var horizon := NIGHT_HORIZON.lerp(DAY_HORIZON, day)
	top = top.lerp(DUSK_TOP, dusk * 0.7)
	horizon = horizon.lerp(DUSK_HORIZON, dusk * 0.8)
	if _sky:
		_sky.set_shader_parameter("top_color", top)
		_sky.set_shader_parameter("horizon_color", horizon)
		_sky.set_shader_parameter("ground_color", horizon.darkened(0.5))
		_sky.set_shader_parameter("night", night)
	if environment:
		var env := environment.environment
		env.fog_light_color = horizon * Biome.fog_tint
		env.fog_density = _fog_density * Biome.fog_density
		env.ambient_light_energy = lerpf(0.32, 1.0, day) * Biome.ambient
		env.background_energy_multiplier = lerpf(0.45, 1.0, day)
		var morning := 1.0 - smoothstep(0.0, 0.07, absf(DayNight.time - MIST_PEAK))
		env.volumetric_fog_density = _mist_density * Biome.mist * (1.0 + MORNING_MIST * morning + 0.6 * night)
		env.volumetric_fog_albedo = (horizon * Biome.fog_tint).lerp(Color.WHITE, 0.45)
		_update_grade(env, dusk, night)

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
func _update_grade(env: Environment, dusk: float, night: float) -> void:
	var shadows := Biome.shadow_tint * Color.WHITE.lerp(DUSK_GRADE[0], dusk).lerp(NIGHT_GRADE[0], night)
	var highlights := Biome.highlight_tint * Color.WHITE.lerp(DUSK_GRADE[1], dusk).lerp(NIGHT_GRADE[1], night)
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
