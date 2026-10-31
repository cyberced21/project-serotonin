class_name UnderwaterView
extends MeshInstance3D
## What it's like with your eye under the water (plans/water.md): the world tinted and fading into
## murk with distance (shaders/underwater.gdshader, two passes over the whole screen), the surface
## seen from below (the water shader's back face), and every sound muffled (a low-pass on the
## world's buses). A child of the player's camera; it switches itself on while the camera's under.

const VIEW_SHADER := preload("res://shaders/underwater.gdshader")
const MURK_SHADER := preload("res://shaders/underwater_murk.gdshader")
## The buses muffled under water: everything you hear in the world, and the music too (softer).
const BUSES := {&"Effects": 1.0, &"Ambience": 1.0, &"Movement": 1.0, &"Music": 0.5}
## Cutoff (Hz) of the low-pass under water, and how quickly (s) it closes in and opens out again.
const MUFFLED_HZ := 650.0
const OPEN_HZ := 20500.0
const MUFFLE_TIME := 0.25

var player: Node
var under := false
var _view: ShaderMaterial
var _murk: ShaderMaterial
var _filters: Dictionary[StringName, AudioEffectLowPassFilter] = {}
var _muffle := 0.0  # 0 open .. 1 fully muffled


func _ready() -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	mesh = quad
	_view = ShaderMaterial.new()
	_view.shader = VIEW_SHADER
	_view.render_priority = 100  # (after the water's surface: it's see-through, so it goes first)
	_murk = ShaderMaterial.new()
	_murk.shader = MURK_SHADER
	_murk.render_priority = 101
	_view.next_pass = _murk
	material_override = _view
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	extra_cull_margin = 16384.0  # (drawn over the whole screen, wherever its box is)
	visible = false
	for bus in BUSES:
		var i := AudioServer.get_bus_index(bus)
		if i < 0:
			continue
		var f := AudioEffectLowPassFilter.new()
		f.resource_name = "Underwater"
		f.cutoff_hz = OPEN_HZ
		AudioServer.add_bus_effect(i, f)
		AudioServer.set_bus_effect_enabled(i, AudioServer.get_bus_effect_count(i) - 1, false)
		_filters[bus] = f


func _exit_tree() -> void:
	for bus in _filters:  # (the bus layout outlives the world)
		var i := AudioServer.get_bus_index(bus)
		for k in range(AudioServer.get_bus_effect_count(i) - 1, -1, -1):
			if AudioServer.get_bus_effect(i, k) == _filters[bus]:
				AudioServer.remove_bus_effect(i, k)
	_filters.clear()


func _process(delta: float) -> void:
	var eye := global_position
	var water := WaterBody.surface_at(get_tree(), eye) if player and player.get("swimming") else null
	under = water != null and eye.y < water.surface_height
	visible = under
	RenderingServer.global_shader_parameter_set(&"under_light", lerpf(1.0, 0.06, DayNight.darkness()))
	if under:
		for m in [_view, _murk]:
			m.set_shader_parameter("surface_height", water.surface_height)
	_muffle = move_toward(_muffle, 1.0 if under else 0.0, delta / MUFFLE_TIME)
	for bus in _filters:
		var i := AudioServer.get_bus_index(bus)
		var k := _effect_index(i, _filters[bus])
		if k < 0:
			continue
		var amount: float = _muffle * BUSES[bus]
		AudioServer.set_bus_effect_enabled(i, k, amount > 0.0)
		# (closing in on a log scale, so it sounds even)
		_filters[bus].cutoff_hz = exp(lerpf(log(OPEN_HZ), log(MUFFLED_HZ), amount))


func _effect_index(bus: int, effect: AudioEffect) -> int:
	for k in AudioServer.get_bus_effect_count(bus):
		if AudioServer.get_bus_effect(bus, k) == effect:
			return k
	return -1
