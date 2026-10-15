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

var _sky: ShaderMaterial
var _glow := -1.0
var _fog_density := 0.0  # the scene's own, before the biome's factor


func _ready() -> void:
	if environment and environment.environment.sky:
		_sky = environment.environment.sky.sky_material as ShaderMaterial
	if environment:
		_fog_density = environment.environment.fog_density
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
		sun.light_energy = lerpf(0.25, lerpf(0.55, 1.0, clampf(h * 1.5, 0.0, 1.0)), day)
		sun.shadow_opacity = lerpf(0.55, 1.0, day)

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
		env.ambient_light_energy = lerpf(0.45, 1.0, day) * Biome.ambient
		env.background_energy_multiplier = lerpf(0.6, 1.0, day)

	# lamps, lanterns and windows
	var glow := smoothstep(0.15, 0.85, night)
	if absf(glow - _glow) > 0.01:
		_glow = glow
		for g in get_tree().get_nodes_in_group("night_glow"):
			(g as GeometryInstance3D).set_instance_shader_parameter("glow", glow)
		for l in get_tree().get_nodes_in_group("night_light"):
			var light := l as Light3D
			light.light_energy = glow * float(light.get_meta("night_energy", 1.0))
			light.visible = glow > 0.01


## Marks `mesh` as something that glows after dark; with `light`, also hangs a small warm lamp
## light on it. Used by buildings and props for lamps, lanterns and windows.
static func make_glow(mesh: MeshInstance3D, light := false) -> void:
	mesh.add_to_group("night_glow")
	if light:
		var omni := OmniLight3D.new()
		omni.light_color = Color(1.0, 0.75, 0.45)
		omni.omni_range = 7.0
		omni.omni_attenuation = 1.4
		omni.shadow_enabled = false
		omni.set_meta("night_energy", 1.6)
		omni.light_energy = 0.0
		omni.visible = false
		omni.add_to_group("night_light")
		mesh.add_child(omni)
		omni.position = mesh.get_aabb().get_center()
