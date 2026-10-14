extends CharacterBody3D
## First-person player: WASD to move, mouse to look, Shift to sprint, Space to jump,
## Ctrl / C to crouch (slide while sprinting), jump at a ledge while moving forward to mantle,
## hold E / left-click to gather whatever the crosshair is on. E on a villager talks to them
## instead (left-click never swings at villagers).
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

@export_group("Water")
## Speed multiplier when wading at full depth (scales in with depth).
@export var wade_slow := 0.5
## Depth (m) at which wading is at its slowest.
@export var wade_full_depth := 0.9
## Slides stop in water deeper than this.
@export var slide_max_water := 0.3

@export_group("Crouch / slide")
@export var crouch_speed := 2.5
## Seconds to go fully down / up.
@export var crouch_transition := 0.12
## Extra speed when a slide starts (only once per slide_boost_cooldown, so it can't be spammed).
@export var slide_boost := 2.5
@export var slide_boost_cooldown := 0.8
## Speed lost per second on flat ground.
@export var slide_friction := 4.0
## How strongly slopes speed you up (downhill) or slow you down (uphill).
@export var slide_gravity := 1.0
@export var slide_steer := 4.0
## The slide ends below this speed.
@export var slide_min_speed := 3.0
@export var slide_fov_kick := 10.0
@export var slide_roll_deg := 3.0

@export_group("Mantle")
## How far ahead a wall is detected.
@export var mantle_reach := 0.8
## Ledges lower than this (above the feet) are just stepped/jumped onto.
@export var mantle_min_height := 0.45
@export var mantle_max_height := 2.2
## Pull-up time per metre of height.
@export var mantle_time_per_m := 0.18

@export_group("Gathering")
## How far the crosshair reaches (m).
@export var reach := 2.4
## How far away you can talk to a villager (m).
@export var interact_reach := 3.2
@export var swing_sfx: AudioStream
## Tool models (.glb, handle from the origin up +Y). Replace the greybox tools when set.
@export var pickaxe_model: PackedScene
@export var axe_model: PackedScene
@export var spear_model: PackedScene

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
## Villagers (see Villager.NPC_LAYER): the crosshair ray stops on them, mantling ignores them.
const NPC_MASK := 1 << 5
const STAND_HEIGHT := 1.8
const CROUCH_HEIGHT := 1.0
const STAND_EYE := 1.6
const CROUCH_EYE := 0.9

enum State { NORMAL, SLIDE, MANTLE }

## Slide scrape pitch per surface (see footsteps.gd): sand is dull, rock is sharp.
const SLIDE_PITCH := {&"grass": 1.1, &"dirt": 0.9, &"rock": 1.3, &"sand": 0.75, &"snow": 1.0}
const DEFLECT_COLOR := Color("ff8a7a")
const TOOL_MATERIAL := preload("res://materials/node_palette.tres")

@onready var head: Node3D = $Head
@onready var body_collision: CollisionShape3D = $CollisionShape3D
@onready var body_shape: CapsuleShape3D = body_collision.shape
@onready var camera: Camera3D = $Head/Camera3D
@onready var tool_pivot: Node3D = %ToolPivot
@onready var tools: Dictionary[StringName, Node3D] = {&"axe": %Axe, &"pickaxe": %Pickaxe, &"spear": %Spear}
@onready var spearfishing: SpearFishing = $SpearFishing
@onready var dot: Control = $Reticle/Dot
@onready var hover_label: Label = $Reticle/Hover
@onready var audio: AudioStreamPlayer = $Audio
@onready var footsteps: Node = $Footsteps
@onready var slide_audio: AudioStreamPlayer3D = $SlideAudio
@onready var mantle_audio: AudioStreamPlayer3D = $MantleAudio

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _base_fov := 75.0
var _coyote := 0.0
var _jump_buffer := 0.0
var _state := State.NORMAL
var _crouch := 0.0  # 0 = standing, 1 = fully crouched
var _slide_boost_cooldown := 0.0
var _stand_probe := CapsuleShape3D.new()

var _target: ResourceNode
var _talk_target: Villager
var _swinging := false
var _cooldown := 0.0
var _tool_rest := Vector3.ZERO


func _ready() -> void:
	add_to_group("player")
	_base_fov = camera.fov
	_tool_rest = tool_pivot.position
	_stand_probe.radius = body_shape.radius - 0.01
	_stand_probe.height = STAND_HEIGHT
	var scrape := slide_audio.stream as AudioStreamWAV
	if scrape:  # the scrape is a seamless loop; make it loop without needing import settings
		scrape.loop_mode = AudioStreamWAV.LOOP_FORWARD
		scrape.loop_begin = 0
		scrape.loop_end = int(scrape.get_length() * scrape.mix_rate)  # in frames; works for any import compression
	tool_pivot.rotation.x = REST_ANGLE
	_use_tool_model(tools[&"pickaxe"], pickaxe_model)
	_use_tool_model(tools[&"axe"], axe_model)
	_use_tool_model(tools[&"spear"], spear_model)
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
	if _state != State.MANTLE:
		_move(delta)
	_update_crouch(delta)

	_cooldown -= delta
	_update_target()
	if _talk_target:
		if Input.is_action_just_pressed("interact") and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED \
				and not _swinging and not _panel_just_closed():
			_talk_target.interact()
	elif Input.is_action_pressed("gather") and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED \
			and is_on_floor() and _state == State.NORMAL and not _swinging and _cooldown <= 0.0:
		if _target:
			_swing(_target.tool_type)
		elif spearfishing.can_thrust():
			spearfishing.thrust()


func _move(delta: float) -> void:
	var input := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var wish_dir := transform.basis * Vector3(input.x, 0.0, input.y)
	var water_depth := WaterBody.depth_at(get_tree(), global_position)
	var wading := lerpf(1.0, wade_slow, clampf(water_depth / wade_full_depth, 0.0, 1.0))
	if _state == State.SLIDE and water_depth > slide_max_water:
		_state = State.NORMAL  # the water stops you

	# gravity + coyote time
	if is_on_floor():
		_coyote = coyote_time
	else:
		_coyote -= delta
		velocity.y -= _gravity * (fall_gravity_mult if velocity.y < 0.0 else 1.0) * delta

	# mantle: jump at a ledge while pushing forward (on the ground or in the air)
	_jump_buffer -= delta
	if Input.is_action_just_pressed("jump"):
		_jump_buffer = jump_buffer
	var wants_mantle := input.y < -0.3 and not _swinging \
		and (_jump_buffer > 0.0 or (not is_on_floor() and Input.is_action_pressed("jump")))
	if wants_mantle and _try_mantle():
		return

	# jump (also out of a slide, keeping its speed)
	if _jump_buffer > 0.0 and _coyote > 0.0 and not _swinging and _can_stand():
		velocity.y = jump_velocity
		_jump_buffer = 0.0
		_coyote = 0.0
		_state = State.NORMAL
	if Input.is_action_just_released("jump") and velocity.y > 0.0:
		velocity.y *= jump_cut

	# start a slide: crouch while sprinting fast on the ground
	var crouch_pressed := Input.is_action_just_pressed("crouch")
	var horizontal := Vector2(velocity.x, velocity.z)
	if _state == State.NORMAL and crouch_pressed and is_on_floor() and not _swinging \
			and horizontal.length() > walk_speed + 0.5:
		_state = State.SLIDE
		if _slide_boost_cooldown <= 0.0:
			horizontal += horizontal.normalized() * slide_boost
			_slide_boost_cooldown = slide_boost_cooldown
	_slide_boost_cooldown -= delta

	if _state == State.SLIDE:
		horizontal = _slide(delta, horizontal, Vector2(wish_dir.x, wish_dir.z))
	else:
		# walk / sprint / crouch-walk, relative to where the body faces (yaw only — the head pitches)
		var crouched := Input.is_action_pressed("crouch") or not _can_stand()
		var sprinting := Input.is_action_pressed("sprint") and input.y < 0.0 and not _swinging and not crouched
		var speed := crouch_speed if crouched else (sprint_speed if sprinting else walk_speed)
		speed *= move_slow_while_swinging if _swinging else 1.0
		speed *= wading
		var target := Vector2(wish_dir.x, wish_dir.z) * speed
		var rate := air_accel
		if is_on_floor():
			rate = ground_friction if target == Vector2.ZERO else ground_accel
		horizontal = horizontal.move_toward(target, rate * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.y
	var was_on_floor := is_on_floor()
	var fall_speed := -velocity.y
	move_and_slide()

	if is_on_floor() and not was_on_floor:
		footsteps.land(fall_speed)
	var stepping_speed := horizontal.length() if _state == State.NORMAL else 0.0  # no steps mid-slide
	footsteps.tick(delta, stepping_speed, is_on_floor(), _crouch > 0.5, walk_speed, sprint_speed)
	_update_slide_audio(delta, horizontal.length())

	var fast := horizontal.length() > walk_speed + 0.5
	var kick := slide_fov_kick if _state == State.SLIDE else (sprint_fov_kick if fast else 0.0)
	camera.fov = lerpf(camera.fov, _base_fov + kick, 1.0 - exp(-10.0 * delta))


# --- slide ----------------------------------------------------------------------------------

## Low friction, speeds up going downhill, a little steering. Ends when it's too slow, when
## crouch is released, or on a jump (which keeps the momentum).
func _slide(delta: float, horizontal: Vector2, wish: Vector2) -> Vector2:
	if is_on_floor():
		var n := get_floor_normal()
		# the downhill part of gravity: (n.x, n.z) points down the slope, longer on steeper ground
		horizontal += Vector2(n.x, n.z) * _gravity * slide_gravity * delta
		horizontal = horizontal.move_toward(Vector2.ZERO, slide_friction * delta)
	# steering only bends the slide sideways — holding forward can't keep it going forever
	if horizontal.length() > 0.01:
		var along := horizontal.normalized()
		horizontal += (wish - along * wish.dot(along)) * slide_steer * delta
	if horizontal.length() < slide_min_speed or not Input.is_action_pressed("crouch"):
		_state = State.NORMAL
	return horizontal


## Scrape loop while sliding on the ground: louder and higher the faster you go, pitched by
## surface; fades out (rather than cutting) when the slide ends or you leave the ground.
func _update_slide_audio(delta: float, speed: float) -> void:
	if _state == State.SLIDE and is_on_floor():
		if not slide_audio.playing:
			slide_audio.volume_db = -20.0
			slide_audio.play(randf() * 1.0)  # random start so repeated slides don't sound identical
		var t := clampf(speed / (sprint_speed + slide_boost), 0.0, 1.0)
		slide_audio.pitch_scale = SLIDE_PITCH.get(footsteps.surface(), 1.0) * lerpf(0.85, 1.15, t)
		slide_audio.volume_db = move_toward(slide_audio.volume_db, lerpf(-14.0, -2.0, t), 120.0 * delta)
	elif slide_audio.playing:
		slide_audio.volume_db = move_toward(slide_audio.volume_db, -40.0, 120.0 * delta)
		if slide_audio.volume_db <= -39.0:
			slide_audio.stop()


## Smoothly lowers the eye and shrinks the capsule while sliding / crouching.
func _update_crouch(delta: float) -> void:
	var want := 1.0 if (_state == State.SLIDE or Input.is_action_pressed("crouch") or not _can_stand()) \
		and _state != State.MANTLE else 0.0
	_crouch = move_toward(_crouch, want, delta / crouch_transition)
	var height := lerpf(STAND_HEIGHT, CROUCH_HEIGHT, _crouch)
	body_shape.height = height
	body_collision.position.y = height / 2.0
	head.position.y = lerpf(STAND_EYE, CROUCH_EYE, _crouch)
	# slight camera roll while sliding
	var roll := slide_roll_deg if _state == State.SLIDE else 0.0
	head.rotation.z = lerp_angle(head.rotation.z, deg_to_rad(roll), 1.0 - exp(-8.0 * delta))


## True if there's nothing overhead stopping the player standing up.
func _can_stand() -> bool:
	return _fits(global_position)


## True if a standing capsule fits with its feet at `at`.
func _fits(at: Vector3) -> bool:
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _stand_probe
	query.transform = Transform3D(Basis.IDENTITY, at + Vector3.UP * (STAND_HEIGHT / 2.0 + 0.02))
	query.collision_mask = WORLD_MASK
	query.exclude = [get_rid()]
	return get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()


# --- mantle ---------------------------------------------------------------------------------

## Looks for a ledge in front: a steep face within reach, a walkable top no higher than
## mantle_max_height above the feet, and room to stand up there. Starts the climb if found.
func _try_mantle() -> bool:
	var space := get_world_3d().direct_space_state
	var fwd := -global_basis.z
	var feet := global_position
	# 1. a wall in front, probing knee → chest → head height
	var wall := {}
	for h in [0.4, 1.0, 1.6]:
		var from: Vector3 = feet + Vector3.UP * h
		var q := PhysicsRayQueryParameters3D.create(from, from + fwd * mantle_reach, WORLD_MASK, [get_rid()])
		wall = space.intersect_ray(q)
		if not wall.is_empty():
			break
	if wall.is_empty() or wall["normal"].y > 0.3:
		return false
	# 2. its top: cast down from above the max height, a little way past the face
	var probe: Vector3 = wall["position"] - wall["normal"] * 0.3
	var q2 := PhysicsRayQueryParameters3D.create(
		Vector3(probe.x, feet.y + mantle_max_height + 0.1, probe.z),
		Vector3(probe.x, feet.y + mantle_min_height, probe.z), WORLD_MASK, [get_rid()])
	var top := space.intersect_ray(q2)
	if top.is_empty() or top["normal"].y < 0.7:
		return false
	# 3. room to stand on it
	var land: Vector3 = top["position"] + fwd * 0.15
	if not _fits(land + Vector3.UP * 0.02):
		return false
	_mantle(land)
	return true


## Pull up (fast, then slower as you crest), then step forward onto the ledge.
func _mantle(land: Vector3) -> void:
	_state = State.MANTLE
	_jump_buffer = 0.0
	mantle_audio.play()  # hands slap onto the ledge, clothes rustle on the way up
	velocity = Vector3.ZERO
	var start := global_position
	var rise := land.y - start.y
	var up_time := clampf(rise * mantle_time_per_m, 0.12, 0.4)
	var crest := Vector3(start.x, land.y + 0.05, start.z)
	var t := create_tween()
	t.tween_property(self, "global_position", crest, up_time).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_property(self, "global_position", land + Vector3.UP * 0.05, 0.12).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	# hands busy: tool dips out of view and comes back; head nods with the effort
	var tool_t := create_tween()
	tool_t.tween_property(tool_pivot, "position", _tool_rest + Vector3(0, -0.25, 0.05), up_time * 0.5)
	tool_t.tween_property(tool_pivot, "position", _tool_rest, 0.2).set_delay(up_time * 0.5)
	var nod := create_tween()
	nod.tween_property(camera, "position:y", -0.06, up_time).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	nod.tween_property(camera, "position:y", 0.0, 0.15).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await t.finished
	velocity = -global_basis.z * walk_speed * 0.5  # carry on moving instead of stopping dead
	footsteps.land(footsteps.land_min_speed + 1.0)  # feet planting on the ledge
	_state = State.NORMAL


# --- gathering ------------------------------------------------------------------------------

## Swaps a tool's greybox meshes for a model. Viewmodel meshes must be on render layer 2 (only
## the viewmodel camera sees it) and cast no shadows into the world.
func _use_tool_model(slot: Node3D, model: PackedScene) -> void:
	if model == null:
		return
	for old in slot.get_children():
		old.queue_free()
	var inst := model.instantiate()
	slot.add_child(inst)
	for m in inst.find_children("*", "MeshInstance3D", true, false):
		m.layers = 2
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		m.material_override = TOOL_MATERIAL


## Ray from the centre of the screen. Only the world and villagers, so debris and drops don't
## block it.
func _aim(length := reach) -> Dictionary:
	var from := camera.global_position
	var to := from - camera.global_basis.z * length
	var query := PhysicsRayQueryParameters3D.create(from, to, WORLD_MASK | NPC_MASK, [get_rid()])
	return get_world_3d().direct_space_state.intersect_ray(query)


func _node_under_crosshair(hit: Dictionary) -> ResourceNode:
	var node := hit.get("collider") as ResourceNode
	return node if node and node.is_available() else null


func _update_target() -> void:
	# one ray out to the further reach: villagers can be talked to a bit further than you can swing
	var hit := _aim(maxf(reach, interact_reach))
	var talk := hit.get("collider") as Villager
	var node: ResourceNode = null
	if talk == null and not hit.is_empty() and camera.global_position.distance_to(hit["position"]) <= reach:
		node = _node_under_crosshair(hit)
	if talk != _talk_target:
		if is_instance_valid(_talk_target):
			_talk_target.set_highlighted(false)
		_talk_target = talk
		if _talk_target:
			_talk_target.set_highlighted(true)
	if node != _target:
		if is_instance_valid(_target):
			_target.set_highlighted(false)
		_target = node
		if _target:
			_target.set_highlighted(true)
	if _target or _talk_target:
		spearfishing.clear_target()
	elif not _swinging:  # mid-thrust, SpearFishing re-aims on its own impact frame
		spearfishing.update_target()

	# bring out the right tool for whatever you're looking at
	if not _swinging:
		if _target:
			_equip(_target.tool_type)
		elif spearfishing.can_thrust():
			_equip(&"spear")

	var fish := spearfishing.fish_target
	dot.scale = Vector2.ONE * (1.75 if _target or fish or _talk_target else (1.3 if spearfishing.can_thrust() else 1.0))
	if _talk_target:
		hover_label.text = _talk_target.prompt() if not _panel_open() else ""
		hover_label.modulate = Color.WHITE
	elif _target and not _target.can_gather():
		hover_label.text = "%s %d" % [Skills.display_name(_target.skill), _target.required_level]
		hover_label.modulate = DEFLECT_COLOR
	elif fish and not fish.can_catch():
		hover_label.text = "%s %d" % [Skills.display_name(&"fishing"), fish.species.required_level]
		hover_label.modulate = DEFLECT_COLOR
	else:
		hover_label.text = ""


func _panel_open() -> bool:
	var panel := get_tree().get_first_node_in_group("upgrade_panel") as UpgradePanel
	return panel != null and panel.is_open()


## The E that closed the upgrade panel mustn't open it again straight away.
func _panel_just_closed() -> bool:
	var panel := get_tree().get_first_node_in_group("upgrade_panel") as UpgradePanel
	return panel != null and panel.just_closed()


func _equip(tool: StringName) -> void:
	for id in tools:
		tools[id].visible = id == tool


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
