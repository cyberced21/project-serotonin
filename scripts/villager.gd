class_name Villager
extends AnimatableBody3D
## A toy villager living in the Building it's a child of. No rig and no navmesh: the model is
## separate parts (Body, Head, ArmL/R, LegL/R — see tools/blender/make_village.py) posed in code,
## and it walks in straight lines between its building's spots:
##   Spots/Door, Spots/Work1..3 (the work spot moves up with the tier), and optionally
##   Spots/Bench (on a bench seat: they sit there) and Spots/Square (somewhere to stand about).
## A spot's +Z is the way the villager faces while standing (or sitting) there.
## When the player comes close it stops and turns to face them; E (see player.gd) opens the
## upgrade panel. When its building is upgraded, it cheers.
## Animations set target poses (_pose); the parts ease toward them every tick — quickly while
## working (so blows stay snappy), slowly for a moment after the state changes (so switching
## between working, walking and idling blends instead of snapping). Walking speeds up from a
## standstill and slows into each stop.

enum State { IDLE, WALK, WORK, TALK, CHEER }
enum Work { CHOP, HAMMER, FISH, ORATE, TEND }

const PALETTE := preload("res://materials/node_palette.tres")
const CHOP_SFX := preload("res://audio/wood_hit.tres")
const CLANK_SFX := preload("res://audio/stone_hit.tres")
## Physics layer 7: the player bumps into villagers and aims at them, but they're not "world"
## (no mantling onto heads, debris and pickups pass through). (Layer 6 is the fish hit volumes.)
const NPC_LAYER := 1 << 6

@export var model: PackedScene
@export var work := Work.CHOP
@export var walk_speed := 1.3
## The player within this distance makes the villager stop and face them.
@export var talk_radius := 3.2
## Head tracking range.
@export var look_radius := 7.0
## At night, the player this close to the door brings the villager back out to talk.
@export var door_call_radius := 4.0
@export var work_time := Vector2(12.0, 22.0)
@export var idle_time := Vector2(3.0, 7.0)

var building: Building
var state := State.IDLE
var _parts: Dictionary[StringName, Node3D] = {}
var _rest: Dictionary[StringName, Transform3D] = {}
var _surfaces: Array[GeometryInstance3D] = []
var _target: Marker3D
var _walk_from := Vector3.ZERO
var _timer := 0.0
var _phase := 0.0  # animation clock
var _walk_cycle := 0.0
var _cheer_time := 0.0
var _anim_hit := false  # one sound per work swing
var _yaw := 0.0
var _hurry := 1.0  # walk speed multiplier
var _inside := false  # gone home for the night
var _away := false  # the building isn't there yet
var _targets: Dictionary[StringName, Transform3D] = {}  # target pose per part (see _pose)
var _blend := 0.0  # seconds of slow blending left after a state change
var _last_state := State.IDLE
var _speed := 0.0  # current walking speed
var _visiting := false  # stepped out at night because the player came to the door
var _model: Node3D
var _shape: CollisionShape3D
var _watching := false  # standing back while the building is upgraded
var _audio: AudioStreamPlayer3D
var _player: Node3D
var _terrain: Terrain3D


func _ready() -> void:
	building = get_parent() as Building
	assert(building, "A Villager must be a child of a Building")
	collision_layer = NPC_LAYER
	collision_mask = 0
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_ON  # moved and posed on physics ticks
	sync_to_physics = false
	_build_model()
	_shape = CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.3
	capsule.height = 1.5
	_shape.shape = capsule
	_shape.position.y = 0.75
	add_child(_shape)
	_audio = AudioStreamPlayer3D.new()
	_audio.unit_size = 3.0
	_audio.max_distance = 30.0
	_audio.volume_db = -8.0
	add_child(_audio)
	building.upgraded.connect(func(_t: int) -> void: cheer())
	Village.tier_changed.connect(func(id: StringName, _t: int) -> void:
		if id == building.def.id:
			_watch_upgrade())
	_phase = randf() * 10.0
	_start.call_deferred()  # once the building knows its tier and the terrain has loaded


func display_name() -> String:
	return building.def.villager_name


func role() -> String:
	return building.def.villager_role


## Shown under the crosshair while the player looks at this villager.
func prompt() -> String:
	return "E  Talk to %s (%s)" % [display_name(), role()]


func interact() -> void:
	var panel := get_tree().get_first_node_in_group("upgrade_panel") as UpgradePanel
	if panel:
		panel.open(self)


func set_highlighted(on: bool) -> void:
	for s in _surfaces:
		s.set_instance_shader_parameter("highlight", 1.0 if on else 0.0)


func cheer() -> void:
	state = State.CHEER
	_cheer_time = 0.0
	_hurry = 1.0
	if _target == null or _watching:
		_target = building.spot("Door")
	_watching = false


## The building is being rebuilt around (maybe on top of) us: hurry out to the door spot and
## watch from there. The cheer comes when it's finished (Building.upgraded).
func _watch_upgrade() -> void:
	_watching = true
	_hurry = 2.6
	var door := building.spot("Door")
	if door:
		_walk_to(door)


# --- model ----------------------------------------------------------------------------------

func _build_model() -> void:
	var inst := model.instantiate() as Node3D
	inst.name = "Model"
	add_child(inst)
	_model = inst
	for m in inst.find_children("*", "MeshInstance3D", true, false):
		(m as MeshInstance3D).material_override = PALETTE
		_surfaces.append(m)
	for part in [&"Body", &"Head", &"ArmL", &"ArmR", &"LegL", &"LegR"]:
		var n := inst.find_child(String(part), true, false) as Node3D
		if n:
			_parts[part] = n
			_rest[part] = n.transform


## Sets a part's target pose, relative to its rest pose: x = swing forward/back (negative =
## forward / up in front), z = out to the side. Position offset is in the part's parent space.
## The part eases toward it in _apply_poses.
func _pose(part: StringName, x: float, z := 0.0, y := 0.0, offset := Vector3.ZERO) -> void:
	if not _parts.has(part):
		return
	var rest := _rest[part]
	_targets[part] = Transform3D(rest.basis * Basis.from_euler(Vector3(x, y, z)), rest.origin + offset)


func _apply_poses(delta: float) -> void:
	if state != _last_state:
		_last_state = state
		_blend = 0.3
	_blend = maxf(_blend - delta, 0.0)
	var rate := 7.0 if _blend > 0.0 else 30.0
	var k := 1.0 - exp(-rate * delta)
	for part in _targets:
		var n := _parts[part]
		n.transform = n.transform.interpolate_with(_targets[part], k)


# --- behaviour ------------------------------------------------------------------------------

func _start() -> void:
	_terrain = get_tree().get_first_node_in_group("terrain") as Terrain3D
	var m := building.work_spot()
	if m:
		global_position = _ground(m.global_position)
		_face_marker(m)
		_target = m
	reset_physics_interpolation()
	_enter(State.WORK if m and m.name.begins_with("Work") else State.IDLE)


func _enter(s: State) -> void:
	state = s
	_anim_hit = false
	match s:
		State.IDLE:
			_timer = randf_range(idle_time.x, idle_time.y)
		State.WORK:
			_timer = randf_range(work_time.x, work_time.y)


func _physics_process(delta: float) -> void:
	_tick(delta)
	if not _away and not _inside:
		_apply_poses(delta)


func _tick(delta: float) -> void:
	_phase += delta
	if _player == null:
		_player = get_tree().get_first_node_in_group("player") as Node3D
	var to_player := INF
	if _player:
		to_player = Vector2(_player.global_position.x - global_position.x,
			_player.global_position.z - global_position.z).length()
	var panel := get_tree().get_first_node_in_group("upgrade_panel") as UpgradePanel
	var talking := (panel != null and panel.villager == self) or to_player < talk_radius

	# not moved in yet (a cottage the town hall hasn't unlocked)
	var away := building.tier_shown == 0
	if away != _away:
		_away = away
		_model.visible = not away and not _inside
		_shape.set_deferred("disabled", away or _inside)
	if away:
		return

	if state == State.CHEER:
		_cheer_time += delta
		_animate_cheer()
		if _cheer_time > 1.6:
			_enter(State.TALK if talking else State.IDLE)
		_look(delta)
		return

	if _night_routine(delta, talking):
		return
	if talking and state != State.TALK and not _watching:
		state = State.TALK
	match state:
		State.TALK:
			_turn_toward(_player.global_position, delta, 6.0)
			_animate_idle()
			if not talking:
				_enter(State.IDLE)
		State.IDLE:
			if _seated():
				_turn_to_yaw(_marker_yaw(_target), delta, 6.0)
				_animate_sit()
			else:
				_animate_idle()
			if _watching:
				_turn_toward(building.global_position, delta, 5.0)
			else:
				_timer -= delta
				if _timer <= 0.0:
					_walk_to(_pick_spot())
		State.WORK:
			if _target:
				_turn_to_yaw(_marker_yaw(_target), delta, 4.0)
			_animate_work()
			_timer -= delta
			if _timer <= 0.0:
				_walk_to(_pick_spot())
		State.WALK:
			_walk(delta)
	_look(delta)


## After dark: walk to the door and go inside. Step back out when the player comes to the door
## (and stay out while they're near), and for good at daybreak. True when it handled the frame.
func _night_routine(delta: float, talking: bool) -> bool:
	var door := building.spot("Door")
	if door == null:
		return false
	var night := DayNight.is_night()
	var at_door := _player != null and _player.global_position.distance_to(door.global_position) < door_call_radius
	if _inside:
		if night and not at_door:
			return true  # asleep
		_come_out(door)
		_visiting = night
		_enter(State.IDLE)
		return false
	if _visiting:
		var near := _player != null and _player.global_position.distance_to(door.global_position) < door_call_radius + 2.0
		if night and (near or talking):
			if _player:
				_turn_toward(_player.global_position, delta, 6.0)
			_animate_idle()
			_look(delta)
			return true
		_visiting = false
	if not night or _watching or talking:
		return false
	if state == State.WALK and _target == door:
		return false  # on the way home
	if global_position.distance_to(_ground(door.global_position)) < 0.3:
		_go_inside()
		return true
	_walk_to(door)
	return false


func _go_inside() -> void:
	_inside = true
	_shape.set_deferred("disabled", true)
	set_highlighted(false)
	var t := create_tween().set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)  # interpolated body
	t.tween_property(_model, "scale", Vector3(0.6, 0.05, 0.6), 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	t.tween_callback(func() -> void: _model.visible = false)


func _come_out(door: Marker3D) -> void:
	_inside = false
	global_position = _ground(door.global_position)
	_face_marker(door)
	_target = door
	reset_physics_interpolation()
	_shape.set_deferred("disabled", false)
	_model.visible = true
	_model.scale = Vector3(0.6, 0.05, 0.6)
	create_tween().set_process_mode(Tween.TWEEN_PROCESS_PHYSICS).tween_property(_model, "scale", Vector3.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Next place to go: mostly back to work, sometimes the door or the bench. Never where it is.
func _pick_spot() -> Marker3D:
	var options: Array[Marker3D] = []
	var work_m := building.work_spot()
	for m in [work_m, work_m, work_m, building.spot("Door"), building.spot("Bench"), building.spot("Square")]:
		if m and m != _target:
			options.append(m)
	return options.pick_random() if not options.is_empty() else _target


func _walk_to(m: Marker3D) -> void:
	if m == null or m == _target and global_position.distance_to(_ground(m.global_position)) < 0.3:
		_enter(State.IDLE)
		return
	_target = m
	_walk_from = global_position
	_speed = 0.0
	state = State.WALK


func _walk(delta: float) -> void:
	var goal := _target.global_position
	var flat := Vector3(goal.x - global_position.x, 0, goal.z - global_position.z)
	var dist := flat.length()
	if dist < 0.08:
		global_position = _ground(goal)
		_enter(State.WORK if _target.name.begins_with("Work") else State.IDLE)
		return
	# speed up from a standstill, slow into the stop
	var cruise := walk_speed * _hurry * clampf(dist / 0.7, 0.3, 1.0)
	_speed = move_toward(_speed, cruise, 3.0 * _hurry * delta)
	var step := minf(_speed * delta, dist)
	var next := global_position + flat / dist * step
	# height: the ground, but never below the straight line between spots (docks, porches)
	var total := Vector2(goal.x - _walk_from.x, goal.z - _walk_from.z).length()
	var t := 1.0 - (dist - step) / maxf(total, 0.001)
	var line_y := lerpf(_walk_from.y, goal.y, clampf(t, 0.0, 1.0))
	next.y = maxf(_ground_height(next), line_y)
	global_position = next
	_turn_toward(goal, delta, 8.0)
	_walk_cycle += delta * _speed * 4.2
	_animate_walk()


func _ground(p: Vector3) -> Vector3:
	return Vector3(p.x, maxf(_ground_height(p), p.y), p.z)


func _ground_height(p: Vector3) -> float:
	if _terrain and _terrain.data:
		var h: float = _terrain.data.get_height(p)
		if not is_nan(h):
			return h
	return p.y


func _marker_yaw(m: Marker3D) -> float:
	var f := m.global_basis.z
	return atan2(f.x, f.z)


func _face_marker(m: Marker3D) -> void:
	_yaw = _marker_yaw(m)
	rotation.y = _yaw


func _turn_toward(p: Vector3, delta: float, rate: float) -> void:
	var d := p - global_position
	if Vector2(d.x, d.z).length() > 0.01:
		_turn_to_yaw(atan2(d.x, d.z), delta, rate)


func _turn_to_yaw(yaw: float, delta: float, rate: float) -> void:
	_yaw = lerp_angle(_yaw, yaw, 1.0 - exp(-rate * delta))
	rotation.y = _yaw


## Head follows the player when they're near and roughly in front.
func _look(delta: float) -> void:
	if not _parts.has(&"Head"):
		return
	var yaw := 0.0
	var pitch := 0.0
	if _player and global_position.distance_to(_player.global_position) < look_radius:
		var eye := _parts[&"Head"].global_position + Vector3.UP * 0.2
		var target := _player.global_position + Vector3.UP * 1.5
		var local := global_basis.inverse() * (target - eye)
		var want := atan2(local.x, local.z)
		if absf(want) < 2.0:
			yaw = clampf(want, -1.1, 1.1)
			pitch = clampf(-atan2(local.y, Vector2(local.x, local.z).length()), -0.5, 0.4)
	var head := _parts[&"Head"]
	var current := (_rest[&"Head"].basis.inverse() * head.transform.basis).get_euler()
	var k := 1.0 - exp(-8.0 * delta)
	var e := Vector3(lerp_angle(current.x, pitch, k), lerp_angle(current.y, yaw, k), 0.0)
	head.transform = Transform3D(_rest[&"Head"].basis * Basis.from_euler(e), _rest[&"Head"].origin)


# --- animation ------------------------------------------------------------------------------

func _animate_idle() -> void:
	var breathe := sin(_phase * 2.2)
	_pose(&"Body", 0.0, 0.0, 0.0, Vector3(0, breathe * 0.008, 0))
	_pose(&"ArmL", 0.04 * breathe, -0.08)
	_pose(&"ArmR", -0.04 * breathe, 0.08)
	_pose(&"LegL", 0.0)
	_pose(&"LegR", 0.0)


## Idling on the Bench spot: sitting on the seat.
func _seated() -> bool:
	return _target != null and _target.name == "Bench" 		and Vector2(global_position.x - _target.global_position.x, global_position.z - _target.global_position.z).length() < 0.2


func _animate_sit() -> void:
	var sway := sin(_phase * 0.8)
	_pose(&"Body", -0.08, sway * 0.02, 0.0, Vector3(0, 0.02, -0.05))  # sat back a little
	_pose(&"LegL", -1.45, -0.06)  # legs out in front over the edge of the seat
	_pose(&"LegR", -1.45, 0.06)
	_pose(&"ArmL", -0.55, -0.12)  # hands on knees
	_pose(&"ArmR", -0.55, 0.12)


func _animate_walk() -> void:
	var s := sin(_walk_cycle)
	var a := clampf(_speed / walk_speed, 0.25, 1.3)  # small steps when slow, big when hurrying
	_pose(&"LegL", s * 0.6 * a)
	_pose(&"LegR", -s * 0.6 * a)
	_pose(&"ArmL", -s * 0.5 * a, -0.08)
	_pose(&"ArmR", s * 0.5 * a, 0.08)
	_pose(&"Body", 0.04 * a, s * 0.04 * a, 0.0, Vector3(0, absf(cos(_walk_cycle)) * 0.05 * a, 0))


func _animate_cheer() -> void:
	var t := _cheer_time
	var hop := absf(sin(t * TAU / 0.8)) * 0.3 if t < 1.6 else 0.0
	_pose(&"Body", 0.0, 0.0, 0.0, Vector3(0, hop, 0))
	_pose(&"LegL", -hop * 0.8)
	_pose(&"LegR", -hop * 0.8)
	var wave := sin(t * 14.0) * 0.25
	_pose(&"ArmL", -2.7, -0.35 + wave)
	_pose(&"ArmR", -2.7, 0.35 - wave)


func _animate_work() -> void:
	_pose(&"LegL", 0.0)
	_pose(&"LegR", 0.0)
	match work:
		Work.CHOP:
			# raise the axe overhead slowly, bring it down hard, hold, repeat
			var t := fmod(_phase, 1.6) / 1.6
			var arm := 0.0
			if t < 0.55:
				arm = lerpf(-0.6, -2.9, ease(t / 0.55, 0.5))
				_anim_hit = false
			elif t < 0.65:
				arm = lerpf(-2.9, -0.7, (t - 0.55) / 0.1)
			else:
				arm = -0.7
				if not _anim_hit:
					_anim_hit = true
					_play(CHOP_SFX, randf_range(0.9, 1.1))
			_pose(&"ArmR", arm, 0.15)
			_pose(&"ArmL", arm, -0.15)
			_pose(&"Body", -0.1 if t >= 0.6 else 0.05, 0.0)
		Work.HAMMER:
			var t := fmod(_phase, 0.75) / 0.75
			var arm := 0.0
			if t < 0.6:
				arm = lerpf(-0.9, -2.1, ease(t / 0.6, 0.6))
				_anim_hit = false
			elif t < 0.72:
				arm = lerpf(-2.1, -0.85, (t - 0.6) / 0.12)
			else:
				arm = -0.85
				if not _anim_hit:
					_anim_hit = true
					_play(CLANK_SFX, randf_range(1.8, 2.1))
			_pose(&"ArmR", arm, 0.05)
			_pose(&"ArmL", -0.8, -0.1)
			_pose(&"Body", -0.06, 0.0)
		Work.FISH:
			# holding the rod out, with the odd twitch when something nibbles
			var twitch := maxf(sin(_phase * 1.3) * sin(_phase * 3.7), 0.0)
			twitch = twitch * twitch * 0.5
			_pose(&"ArmR", -0.95 - twitch, 0.05)
			_pose(&"ArmL", -0.9 - twitch * 0.5, -0.15)
			_pose(&"Body", 0.0, 0.0, 0.0, Vector3(0, sin(_phase * 1.5) * 0.01, 0))
		Work.TEND:
			# bent over the garden: hands working in turn
			var a := sin(_phase * 2.6)
			_pose(&"ArmR", -1.1 + a * 0.35, 0.1)
			_pose(&"ArmL", -1.1 - a * 0.35, -0.1)
			_pose(&"Body", -0.35, 0.0, 0.0, Vector3(0, -0.03, 0))
		Work.ORATE:
			# hands behind the back, now and then a grand gesture
			var g := maxf(sin(_phase * 0.9), 0.0)
			g = g * g
			_pose(&"ArmR", lerpf(0.35, -1.9, g), lerpf(0.1, 0.5, g))
			_pose(&"ArmL", 0.35, -0.1)
			_pose(&"Body", -0.05 * g, 0.0, 0.0, Vector3(0, sin(_phase * 2.0) * 0.008, 0))


func _play(stream: AudioStream, pitch: float) -> void:
	_audio.stream = stream
	_audio.pitch_scale = pitch
	_audio.play()
