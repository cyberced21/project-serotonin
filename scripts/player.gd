extends CharacterBody3D
## First-person player: WASD to move, mouse to look, Shift to sprint, Space to jump,
## hold E / left-click to gather whatever the crosshair is on.
## Esc frees the mouse; clicking the game captures it again.
## Mouse-look runs in _unhandled_input (raw events), so it stays smooth during hit-stop.
## The node is hit on the *impact frame* of the swing, not when the button is pressed —
## lining sound + hit-stop up with the animation is what makes it feel solid.

@export_group("Look")
@export var mouse_sensitivity := 0.0025
@export_range(1.0, 89.0) var max_pitch_deg := 88.0
## Extra FOV while sprinting, for a sense of speed.
@export var sprint_fov_kick := 6.0

@export_group("Ground")
@export var walk_speed := 4.5
@export var sprint_speed := 7.0
@export var ground_accel := 45.0
@export var ground_friction := 55.0

@export_group("Air")
@export var air_accel := 12.0
@export var jump_velocity := 5.2
## Gravity is multiplied by this while falling, for a snappier arc.
@export var fall_gravity_mult := 1.6
## Releasing jump early multiplies upward speed by this (short hop vs. full jump).
@export_range(0.0, 1.0) var jump_cut := 0.5
## Jump still works this long after walking off a ledge.
@export var coyote_time := 0.1
## A jump pressed this long before landing still fires on landing.
@export var jump_buffer := 0.12

@export_group("Gathering")
## How far the crosshair reaches (m).
@export var reach := 2.4
@export var swing_sfx: AudioStream

@export_group("Swing timing")
@export var windup_time := 0.13
@export var strike_time := 0.05
@export var recover_time := 0.16
@export var swing_cooldown := 0.12
@export var move_slow_while_swinging := 0.3

@export_group("Bite")
## How far the tool sinks into the node on impact (m, viewmodel space).
@export var bite_depth := 0.07
## How long the tool stays stuck in the node after the hit-stop.
@export var bite_hold := 0.06
## How long the yank back out takes. The chunk tears out at the end of it.
@export var yank_time := 0.07

## Tool pivot rotation around X (radians): positive tilts the head back toward the camera.
const REST_ANGLE := -0.3
const WINDUP_ANGLE := 0.7
const STRIKE_ANGLE := -1.3
const WORLD_MASK := 1
const DEFLECT_COLOR := Color("ff8a7a")

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var tool_pivot: Node3D = %ToolPivot
@onready var tools: Dictionary[StringName, Node3D] = {&"axe": %Axe, &"pickaxe": %Pickaxe}
@onready var dot: Control = $Reticle/Dot
@onready var hover_label: Label = $Reticle/Hover
@onready var audio: AudioStreamPlayer = $Audio

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _base_fov := 75.0
var _coyote := 0.0
var _jump_buffer := 0.0

var _target: ResourceNode
var _swinging := false
var _cooldown := 0.0
var _tool_rest := Vector3.ZERO


func _ready() -> void:
	add_to_group("player")
	_base_fov = camera.fov
	_tool_rest = tool_pivot.position
	tool_pivot.rotation.x = REST_ANGLE
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	SaveGame.register(&"player", self)


func to_dict() -> Dictionary:
	return {
		"x": global_position.x, "y": global_position.y, "z": global_position.z,
		"yaw": rotation.y, "pitch": head.rotation.x,
	}


func from_dict(d: Dictionary) -> void:
	if not d.has("z"):
		return  # save from the 2D version — spawn at the default position instead
	global_position = Vector3(float(d["x"]), float(d["y"]), float(d["z"]))
	rotation.y = float(d.get("yaw", 0.0))
	head.rotation.x = float(d.get("pitch", 0.0))


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var motion := event as InputEventMouseMotion
		rotate_y(-motion.relative.x * mouse_sensitivity)
		var limit := deg_to_rad(max_pitch_deg)
		head.rotation.x = clampf(head.rotation.x - motion.relative.y * mouse_sensitivity, -limit, limit)
	elif event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		get_viewport().set_input_as_handled()


func _physics_process(delta: float) -> void:
	_move(delta)

	_cooldown -= delta
	_update_target()
	if Input.is_action_pressed("gather") and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED \
			and _target and is_on_floor() and not _swinging and _cooldown <= 0.0:
		_swing(_target.tool_type)


func _move(delta: float) -> void:
	# gravity + coyote time
	if is_on_floor():
		_coyote = coyote_time
	else:
		_coyote -= delta
		velocity.y -= _gravity * (fall_gravity_mult if velocity.y < 0.0 else 1.0) * delta

	# buffered jump
	_jump_buffer -= delta
	if Input.is_action_just_pressed("jump"):
		_jump_buffer = jump_buffer
	if _jump_buffer > 0.0 and _coyote > 0.0 and not _swinging:
		velocity.y = jump_velocity
		_jump_buffer = 0.0
		_coyote = 0.0
	if Input.is_action_just_released("jump") and velocity.y > 0.0:
		velocity.y *= jump_cut

	# horizontal movement, relative to where the body faces (yaw only — the head pitches)
	var input := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var sprinting := Input.is_action_pressed("sprint") and input.y < 0.0 and not _swinging
	var speed := (sprint_speed if sprinting else walk_speed) * (move_slow_while_swinging if _swinging else 1.0)
	var wish := transform.basis * Vector3(input.x, 0.0, input.y) * speed
	var horizontal := Vector2(velocity.x, velocity.z)
	var target := Vector2(wish.x, wish.z)
	var rate := air_accel
	if is_on_floor():
		rate = ground_friction if target == Vector2.ZERO else ground_accel
	horizontal = horizontal.move_toward(target, rate * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.y
	move_and_slide()

	var fast := sprinting and horizontal.length() > walk_speed + 0.5
	camera.fov = lerpf(camera.fov, _base_fov + (sprint_fov_kick if fast else 0.0), 1.0 - exp(-10.0 * delta))


# --- gathering ------------------------------------------------------------------------------

## Ray from the centre of the screen. Only the world layer, so debris and drops don't block it.
func _aim() -> Dictionary:
	var from := camera.global_position
	var to := from - camera.global_basis.z * reach
	var query := PhysicsRayQueryParameters3D.create(from, to, WORLD_MASK, [get_rid()])
	return get_world_3d().direct_space_state.intersect_ray(query)


func _node_under_crosshair(hit: Dictionary) -> ResourceNode:
	var node := hit.get("collider") as ResourceNode
	return node if node and node.is_available() else null


func _update_target() -> void:
	var node := _node_under_crosshair(_aim())
	if node != _target:
		if is_instance_valid(_target):
			_target.set_highlighted(false)
		_target = node
		if _target:
			_target.set_highlighted(true)
	dot.scale = Vector2.ONE * (1.75 if _target else 1.0)
	if _target and not _target.can_gather():
		hover_label.text = "%s %d" % [Skills.display_name(_target.skill), _target.required_level]
		hover_label.modulate = DEFLECT_COLOR
	else:
		hover_label.text = ""


func _swing(tool: StringName) -> void:
	_swinging = true
	for id in tools:
		tools[id].visible = id == tool

	# 1. wind-up (anticipation)
	var t := create_tween()
	t.tween_property(tool_pivot, "rotation:x", WINDUP_ANGLE, windup_time).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	await t.finished

	# 2. strike — whoosh starts with the fast part of the motion
	if swing_sfx:
		audio.stream = swing_sfx
		audio.play()
	t = create_tween()
	t.tween_property(tool_pivot, "rotation:x", STRIKE_ANGLE, strike_time).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await t.finished

	# 3. impact frame — hits whatever the crosshair is on *now*; looked away = whiff
	var hit := _aim()
	var node := _node_under_crosshair(hit)
	if node:
		var info := HitInfo.new(hit["position"], hit["normal"], node, camera.global_position)
		if node.hit(info):
			await _bite()
			if is_instance_valid(node):
				node.pull(info)  # the chunk tears out as the tool comes free
		else:
			_bounce()

	# 4. recover
	t = create_tween().set_parallel()
	t.tween_property(tool_pivot, "rotation:x", REST_ANGLE, recover_time).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(tool_pivot, "position", _tool_rest, recover_time).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	await t.finished
	_cooldown = swing_cooldown
	_swinging = false


## The tool sinks into the node and sticks (the hit-stop freezes it there), then gets yanked
## back out with a jerk — the moment the chunk comes free.
func _bite() -> void:
	tool_pivot.position = _tool_rest + Vector3(0, -bite_depth * 0.4, -bite_depth)
	var t := create_tween()
	t.tween_interval(bite_hold)
	# yank: back toward the camera, head tipping up as it comes free
	t.tween_property(tool_pivot, "position", _tool_rest + Vector3(0, 0.03, 0.09), yank_time) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(tool_pivot, "rotation:x", STRIKE_ANGLE + 0.45, yank_time) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	await t.finished


## Deflected (level too low): the tool rebounds off the surface instead of biting in.
func _bounce() -> void:
	tool_pivot.position = _tool_rest + Vector3(0, 0.02, 0.08)
	tool_pivot.rotation.x = STRIKE_ANGLE + 0.7
