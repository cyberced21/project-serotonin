class_name Lantern
extends Node3D
## The lantern you carry (plans/lamps.md L6, L7, L9): it hangs at your left hip and swings as you
## move; hold F to raise it in front of you (a tool swing lowers it again). It lights itself at
## dusk and goes out at dawn, L lights or puts it out (the Lamps autoload keeps whether you have
## it and whether it burns, per world). No fuel.
## A child of the viewmodel camera, so it's drawn over the world like the tools (layer 2, no
## shadow of its own); its light is a real light in the world, the one lamp that casts moving
## shadows whatever the graphics setting.

const MODEL := preload("res://models/lantern.glb")
## Where it hangs, from the eye, in a frame that turns with you but only partly follows your
## looking up and down (BELT_PITCH): level, only its top and glow peek in at the bottom left.
const BELT := Vector3(-0.36, -0.25, -0.5)
const BELT_PITCH := 0.55
## Raised: held up on the left, in front of you, following the view.
const RAISED := Vector3(-0.3, -0.12, -0.72)
const RAISE_RATE := 7.0
## The swing: a pendulum this stiff and this damped, pushed by how its hang point accelerates.
const SWING_STIFFNESS := 40.0
const SWING_DAMPING := 3.2
const SWING_PUSH := 0.12
const SWING_MAX := 0.55
const LIGHT_COLOR := Color(1.0, 0.7, 0.42)
const LIGHT_ENERGY := 1.6
const LIGHT_RANGE := 12.0
## Where the flame sits, below the hang point.
const FLAME := Vector3(0, -0.19, 0)
## The light sits a little nearer you than the flame, so the iron facing you catches it
## (lit from right inside, the lantern's own frame showed black).
const LIGHT_AT := FLAME + Vector3(0, 0, 0.14)

## The player (set before it enters the tree; untyped: player.gd makes the lantern).
var player: Node3D
var _model: Node3D
var _light: OmniLight3D
var _meshes: Array[MeshInstance3D] = []
var _raise := 0.0
var _level := 0.0  # how brightly it burns, 0..1
var _swing := Vector2.ZERO  # tilt about the frame's X (forward) and Z (sideways)
var _swing_speed := Vector2.ZERO
var _last_pos := Vector3.ZERO
var _last_vel := Vector3.ZERO


func _ready() -> void:
	process_priority = 101  # after the viewmodel camera (100) has followed the eye this frame
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_model = MODEL.instantiate() as Node3D
	add_child(_model)
	for m in _model.find_children("*", "MeshInstance3D", true, false):
		var mesh := m as MeshInstance3D
		mesh.material_override = PaletteMaterial.for_mesh(mesh.mesh)
		mesh.layers = 2
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if String(mesh.name).begins_with("Lamp"):  # the glass glows, not the iron
			_meshes.append(mesh)
	_light = OmniLight3D.new()
	_light.light_color = LIGHT_COLOR
	_light.omni_range = LIGHT_RANGE
	_light.omni_attenuation = 1.2
	_light.shadow_enabled = true
	_light.shadow_bias = 0.08
	_light.light_energy = 0.0
	_light.visible = false
	_model.add_child(_light)
	_light.position = LIGHT_AT
	_level = 1.0 if Lamps.lantern_lit else 0.0
	_place(0.0)
	_last_pos = global_position


func _process(delta: float) -> void:
	var playing := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and not get_tree().paused
	if playing and Lamps.has_lantern and Input.is_action_just_pressed("lantern"):
		Lamps.set_lantern_lit(not Lamps.lantern_lit)
	var raise: bool = playing and Input.is_action_pressed("raise_lantern") and not player.get("_swinging")
	_raise = move_toward(_raise, 1.0 if raise else 0.0, RAISE_RATE * delta)
	visible = Lamps.has_lantern
	_level = move_toward(_level, 1.0 if Lamps.lantern_lit else 0.0, delta * (3.0 if Lamps.lantern_lit else 1.5))
	_place(delta)
	var t := Time.get_ticks_msec() / 1000.0
	var flicker := 1.0 + 0.07 * sin(t * 7.3) + 0.04 * sin(t * 19.1 + 1.3)
	_light.visible = visible and _level > 0.01
	_light.light_energy = LIGHT_ENERGY * _level * flicker
	for m in _meshes:
		m.set_instance_shader_parameter("glow", _level * (0.6 + 0.1 * flicker))


## Hangs it from the eye (belt or raised) and swings it like a pendulum from there.
func _place(delta: float) -> void:
	var cam := player.get("camera") as Camera3D
	var fwd := -cam.global_basis.z
	var yaw := atan2(-fwd.x, -fwd.z)
	var pitch := asin(clampf(fwd.y, -1.0, 1.0))
	var e := smoothstep(0.0, 1.0, _raise)
	var frame := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch * lerpf(BELT_PITCH, 1.0, e))
	var hang := cam.global_position + frame * BELT.lerp(RAISED, e)
	if delta > 0.0:
		var vel := (hang - _last_pos) / delta
		var accel := (vel - _last_vel) / delta
		_last_pos = hang
		_last_vel = vel
		var push := Vector2(accel.dot(frame * Vector3.FORWARD), -accel.dot(frame * Vector3.RIGHT))
		push = push.limit_length(40.0) * SWING_PUSH
		_swing_speed += (-SWING_STIFFNESS * _swing - SWING_DAMPING * _swing_speed - push) * delta
		_swing = (_swing + _swing_speed * delta).limit_length(SWING_MAX)
	var tilt := Basis(Vector3.RIGHT, _swing.x) * Basis(Vector3.BACK, _swing.y)
	global_transform = Transform3D(frame * tilt, hang)
