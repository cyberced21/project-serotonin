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
enum Work { CHOP, HAMMER, FISH, ORATE, TEND, WIPE }

const PALETTE := preload("res://materials/node_palette.tres")
const CHOP_SFX := preload("res://audio/wood_hit.tres")
const CLANK_SFX := preload("res://audio/stone_hit.tres")
## At the tavern (audio/tavern/SOURCES.md): a laugh, a mug raised (now and then a clink).
const LAUGH_SFX := preload("res://audio/tavern/laugh.wav")
const CLINK_SFX := preload("res://audio/tavern/clink.wav")
## Physics layer 7: the player bumps into villagers and aims at them, but they're not "world"
## (no mantling onto heads, debris and pickups pass through). (Layer 6 is the fish hit volumes.)
const NPC_LAYER := 1 << 6
## A point on the way somewhere counts as passed this close (so they round corners smoothly).
const WAYPOINT_REACH := 0.6
## A walk longer than this (m, along the paths) is taken briskly, this much faster.
const BRISK_FROM := 20.0
const BRISK := 1.9
## Seats further than this are too far to bother with.
const SEAT_RANGE := 45.0
## Breakfast on Rosa's terrace and a night at the tavern are worth a longer walk (each is across
## the green from most houses).
const OUTING_RANGE := 90.0
## Your porch is further out than that, on the west rim (plans/home.md).
const PORCH_RANGE := 120.0
## A stroll round the green goes through these of the network's points, in order.
const SQUARE_ROUND: Array[StringName] = [&"sq_n", &"sq_nne", &"sq_ne", &"sq_e", &"sq_ese", &"sq_se",
	&"sq_s", &"sq_ssw", &"sq_sw", &"sq_w", &"sq_wnw", &"sq_nw"]

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
var _paths: VillagePaths
## The points still to pass on the way to _target (the last one is the target itself).
var _route := PackedVector3Array()
## Their day (VillagerDay): what they're at now, the seat they've taken (a bench at dusk...),
## and whether they're giving the tavern a miss tonight.
var _part := VillagerDay.Part.WORK
var _seat: Marker3D
var _skip_tonight := false
var _stroll: Marker3D  # where they're strolling to next
var _stroll_i := 0
var _mug: MeshInstance3D  # carried at the tavern
var _throw_at := -10.0  # (_phase) when they last threw the dice
var _laughing := false  # (for a laugh's sound at its start)
var _drinking := false
var _fiddle: MeshInstance3D  # on the stage (its bow is the "bow" meta)
var _lights_out := 0.0  # evening hour (VillagerDay.evening_hours) their lamp goes out
var _indoor_walk := false  # walking inside their house (_walk_inside): heights from the route
var _home_visit: Marker3D  # walking over to your home to see how it's coming on (Home.send_visitor)
## This evening's dusk is on your porch (Home.ask_to_porch), not a bench on the square.
var porch_tonight := false
var _visit_left := -1.0  # seconds left at your door, once there
var _said: Label3D
## A cutscene is posing this villager (script_pose): no walking, working or talking of its own.
var scripted := false


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


## A cutscene's pose for one part (see _pose); the part eases to it every frame.
func script_pose(part: StringName, x: float, z := 0.0, offset := Vector3.ZERO) -> void:
	_pose(part, x, z, 0.0, offset)


## A cutscene puts the villager at `at` (on the ground), facing `toward`.
func script_place(at: Vector3, toward: Vector3) -> void:
	global_position = _ground(at)
	var d := toward - global_position
	_yaw = atan2(d.x, d.z)
	rotation.y = _yaw
	reset_physics_interpolation()


## The world position of a part (e.g. the hammer hand), or the villager's own.
func part_position(part: StringName) -> Vector3:
	return _parts[part].global_position if _parts.has(part) else global_position


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
	_part = _day_part()
	var m := building.work_spot()
	if m:
		global_position = _ground(m.global_position)
		_face_marker(m)
		_target = m
	reset_physics_interpolation()
	_enter(State.WORK if m and m.name.begins_with("Work") else State.IDLE)
	var door := building.spot("Door")
	if _part == VillagerDay.Part.SLEEP and door:  # a world loaded at night: already in bed
		global_position = _ground(door.global_position)
		_target = door
		_inside = true
		if VillagerDay.hours(DayNight.time) >= 12.0:  # (an evening: still up for a while)
			_lights_out = VillagerDay.lights_out(building.def.id, VillagerDay.evening_hours(DayNight.time))
		var bed := building.bed()
		if bed:  # a walk-in house: there, in bed (or by the fire)
			var at := _home_seat() if lights_on() else bed
			global_position = _ground(at.global_position)
			_face_marker(at)
			_target = at
		else:
			_model.visible = false
			_shape.set_deferred("disabled", true)
	elif _part != VillagerDay.Part.WORK:
		_walk_to.call_deferred(_next_spot())


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
	if not _away and (not _inside or _model.visible):
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
	# (with a seat of their own, at a table or the dice, sat in it or on the way: they don't stop
	# for you coming near, only when you talk to them, E)
	var settled := _settled()
	var talking := (panel != null and panel.villager == self) or (to_player < talk_radius and _seat == null)

	# not moved in yet (a cottage the town hall hasn't unlocked)
	var away := building.tier_shown == 0
	if away != _away:
		_away = away
		_model.visible = not away and not _inside
		_shape.set_deferred("disabled", away or _inside)
	if away:
		return
	if scripted:
		return
	var part := _day_part()
	if part != _part:
		_change_part(part, talking)
	var on_stage := _seat != null and _seat.is_in_group("stage") and _part == VillagerDay.Part.TAVERN
	_show_mug(_part == VillagerDay.Part.TAVERN and not building is Tavern and not on_stage)
	_show_fiddle(on_stage)

	if state == State.CHEER:
		_cheer_time += delta
		_animate_cheer()
		if _cheer_time > 1.6:
			_enter(State.TALK if talking else State.IDLE)
		_look(delta)
		return

	if _night_routine(delta, talking):
		return
	if _home_visit and _at_visit(delta, talking):
		_look(delta)
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
			var seated := _seated()
			settled = _settled()  # (got to their seat: they stay put)
			if seated or settled:
				_turn_to_yaw(_marker_yaw(_target), delta, 6.0)
			if settled and _seat.is_in_group("stage"):
				_animate_fiddle()
			elif settled and _seat.is_in_group("dance_spot"):
				_animate_dance()
			elif settled and _part == VillagerDay.Part.TAVERN:
				_animate_chat(seated)
			elif seated:
				_animate_sit()
			else:
				_animate_idle()
			if _watching:
				_turn_toward(building.global_position, delta, 5.0)
			elif not settled:
				_timer -= delta
				if _timer <= 0.0:
					_walk_to(_next_spot())
		State.WORK:
			if _target:
				_turn_to_yaw(_marker_yaw(_target), delta, 4.0)
			_animate_work()
			_timer -= delta
			if _timer <= 0.0:
				_walk_to(_next_spot())
		State.WALK:
			_walk(delta)
	_look(delta)


## What their day has them doing now (VillagerDay).
func _day_part() -> VillagerDay.Part:
	if _skip_tonight and DayNight.time > VillagerDay.time_at(12.0) and DayNight.time < VillagerDay.time_at(VillagerDay.DUSK_FROM):
		_skip_tonight = false  # a new day
	return VillagerDay.part(building.def.id, VillagerDay.hours(DayNight.time), _tavern_open(), _skip_tonight)


## There's a tavern to go to tonight (plans/tavern.md P5).
func _tavern_open() -> bool:
	var tavern := get_tree().get_first_node_in_group("tavern")
	return tavern != null and tavern.call("is_open")


## Off to the next part of the day: give up a seat, decide about tonight, and head off (going to
## bed is the night routine's).
func _change_part(part: VillagerDay.Part, talking: bool) -> void:
	var was := _part
	_part = part
	_home_visit = null  # (a visit lasts no longer than the part of the day it began in)
	if was == VillagerDay.Part.DUSK:
		porch_tonight = false
	if part == VillagerDay.Part.DUSK and was != VillagerDay.Part.DUSK:
		_skip_tonight = randf() < float(VillagerDay.person(building.def.id).get("skips_tavern", 0.0))
		_part = _day_part()
	_leave_seat()
	if _part == VillagerDay.Part.SLEEP or _inside or _watching or talking or state == State.CHEER:
		return
	_walk_to(_next_spot())


## After dark: walk to the door and go inside. Step back out when the player comes to the door
## (and stay out while they're near), and for good in the morning. True when it handled the frame.
func _night_routine(delta: float, talking: bool) -> bool:
	var door := building.spot("Door")
	if door == null:
		return false
	var night := _part == VillagerDay.Part.SLEEP
	var at_door := _player != null and _player.global_position.distance_to(door.global_position) < door_call_radius
	if _inside:
		if building.bed():  # a walk-in house: up by the fire, then in bed; a knock wakes them
			if not night or lights_on() or not at_door:
				if _indoors(delta, night):
					return true
				_inside = false  # back at the door in the morning: out for the day
				_set_lying(false)
				_enter(State.IDLE)
				return false
		elif night and not at_door:
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


## Their house's windows are lit: home after dark and not asleep yet, or up to answer the door.
func lights_on() -> bool:
	return _visiting or (_inside and VillagerDay.evening_hours(DayNight.time) < _lights_out)


## Asleep at home: their door is shut (Building).
func door_shut() -> bool:
	return _inside and not lights_on()


func _go_inside() -> void:
	_inside = true
	_lights_out = VillagerDay.lights_out(building.def.id, VillagerDay.evening_hours(DayNight.time))
	if building.bed():  # a walk-in house: they stay in sight, and in their room (_indoors)
		return
	_shape.set_deferred("disabled", true)
	set_highlighted(false)
	var t := create_tween().set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)  # interpolated body
	t.tween_property(_model, "scale", Vector3(0.6, 0.05, 0.6), 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	t.tween_callback(func() -> void: _model.visible = false)


## An evening at home in a walk-in house (plans/home.md): by the fire (their own seat) while the
## lamp's lit, then to bed; in the morning back to the door. False once they're at the door to
## go out (morning).
func _indoors(delta: float, night: bool) -> bool:
	var goal: Marker3D = building.spot("Door")
	if night:
		goal = _home_seat() if lights_on() else building.bed()
	if state == State.WALK:
		if _target != goal:
			_walk_inside(goal)
		_set_lying(false)
		_walk(delta)
		return true
	if global_position.distance_to(_ground(goal.global_position)) > 0.3:
		_walk_inside(goal)
		return true
	if not night:
		return false
	_turn_to_yaw(_marker_yaw(goal), delta, 6.0)
	if goal == building.bed():
		_set_lying(true)
		_animate_sleep()
	elif _seated():
		_animate_sit()
	else:
		_animate_idle()
	_look(delta)
	return true


## Their seat at home (a Seat* in their house), else the bed.
func _home_seat() -> Marker3D:
	if _seat == null or not is_instance_valid(_seat) or _seat.get_meta(&"home", null) != building:
		_leave_seat()
		_claim_seat(&"home")
		if _seat and _seat.get_meta(&"home", null) != building:  # (someone else's house's)
			_leave_seat()
	return _seat if _seat else building.bed()


## Straight across the room (no village paths indoors), by the stair (Stair0 at its foot, Stair1
## at its head) when `m` is on another floor; heights follow the line between the points.
func _walk_inside(m: Marker3D) -> void:
	_target = m
	_route = PackedVector3Array([m.global_position])
	var foot := building.mark("Stair0")
	var head := building.mark("Stair1")
	if foot and head and absf(m.global_position.y - global_position.y) > 1.5:
		var up := m.global_position.y > global_position.y
		_route = PackedVector3Array([(foot if up else head).global_position, (head if up else foot).global_position,
				m.global_position])
	var doorway := building.mark("Doorway")
	if doorway and building.inside(global_position) != building.inside(m.global_position):
		_route.insert(0, doorway.global_position)  # in (or out) by the door, not through the wall
	_walk_from = global_position
	_speed = 0.0
	_indoor_walk = true
	state = State.WALK


## Lying in bed: the whole model tipped back along the bed (its marker sits at the foot of the
## mattress, +Z toward the pillow).
func _set_lying(on: bool) -> void:
	_model.rotation.x = PI / 2 if on else 0.0
	_model.position.y = 0.12 if on else 0.0


func _animate_sleep() -> void:
	var breathe := sin(_phase * 1.1)
	_pose(&"Body", 0.0, 0.0, 0.0, Vector3(0, breathe * 0.01, 0))
	_pose(&"ArmL", 0.0, -0.05)
	_pose(&"ArmR", 0.0, 0.05)
	_pose(&"LegL", 0.0)
	_pose(&"LegR", 0.0)


func _come_out(door: Marker3D) -> void:
	_inside = false
	_set_lying(false)
	global_position = _ground(door.global_position)
	_face_marker(door)
	_target = door
	_route.clear()
	reset_physics_interpolation()
	_shape.set_deferred("disabled", false)
	_model.visible = true
	_model.scale = Vector3(0.6, 0.05, 0.6)
	create_tween().set_process_mode(Tween.TWEEN_PROCESS_PHYSICS).tween_property(_model, "scale", Vector3.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Where to go next for this part of the day.
func _next_spot() -> Marker3D:
	match _part:
		VillagerDay.Part.BREAKFAST:
			if VillagerDay.has_quirk(building.def.id, "serves"):  # Rosa, doing the rounds
				var rounds: Array[Marker3D] = []
				for m in get_tree().get_nodes_in_group("terrace_serve"):
					if m != _target and (m as Marker3D).is_visible_in_tree():
						rounds.append(m)
				if not rounds.is_empty():
					return rounds.pick_random()
			else:
				if _seat == null:
					_claim_seat(&"terrace", "seat", OUTING_RANGE)
				if _seat:
					return _seat
		VillagerDay.Part.TAVERN:
			if building is Tavern:  # the keeper, behind the bar
				return building.work_spot()
			if VillagerDay.has_quirk(building.def.id, "plays"):  # Ollie, on the stage if there is one
				if _seat and _seat.is_in_group("stage"):
					return _seat
				var old := _seat
				_seat = null
				if _claim_seat(&"", "stage", OUTING_RANGE):
					if old and is_instance_valid(old) and old.has_meta(&"taken_by") and old.get_meta(&"taken_by") == self:
						old.remove_meta(&"taken_by")
					return _seat
				_seat = old
			if _seat == null and _claim_seat(&"tavern", "seat", OUTING_RANGE) == null:
				_claim_seat(&"tavern", "stand_spot", OUTING_RANGE)
			if _seat:
				return _seat
			var tavern := get_tree().get_first_node_in_group("tavern") as Building
			if tavern:  # full: a drink on the step
				return tavern.spot("Door")
		VillagerDay.Part.DUSK:
			if porch_tonight and (_seat or _claim_seat(&"porch", "seat", PORCH_RANGE)):
				return _seat
			if not VillagerDay.has_quirk(building.def.id, "strolls"):
				if _seat == null:
					_claim_seat(&"bench")
				if _seat:
					return _seat
				if building.spot("Square") and _target != building.spot("Square"):
					return building.spot("Square")
			return _stroll_spot()
	return _pick_spot()


## Next place to go by day: mostly back to work, sometimes the door or the bench. Never where it
## is, and not a seat someone else has.
func _pick_spot() -> Marker3D:
	var options: Array[Marker3D] = []
	var work_m := building.work_spot()
	for m in [work_m, work_m, work_m, building.spot("Door"), building.spot("Bench"), building.spot("Square")]:
		if m and m != _target and not _taken(m):
			options.append(m)
	return options.pick_random() if not options.is_empty() else _target


## Busy with their own day (sitting somewhere, out for the evening, asleep, visiting you): not
## free to be sent to the well and the like.
func busy() -> bool:
	return _seat != null or _part != VillagerDay.Part.WORK or _home_visit != null


## Off to see your home (plans/home.md, Home.send_visitor): walk over to `spot` by its door.
func visit_home(spot: Marker3D) -> void:
	_home_visit = spot
	_visit_left = -1.0
	_leave_seat()
	_walk_to(spot)


## At your door: a chat if you're there (and something to say about what's new), else a little
## gift left on the step; then back to work. True while the visit has the frame.
func _at_visit(delta: float, talking: bool) -> bool:
	if _target != _home_visit or global_position.distance_to(_ground(_home_visit.global_position)) > 0.4:
		return false
	state = State.IDLE
	var home := get_tree().get_first_node_in_group("home") as Home
	if _visit_left < 0.0:  # just got here
		_visit_left = Home.VISIT_TIME
		if home:
			home.visited(self)
	_visit_left -= delta
	if talking and _player:  # (you're there: they face you)
		_turn_toward(_player.global_position, delta, 5.0)
	else:
		_turn_to_yaw(_marker_yaw(_home_visit), delta, 4.0)
	_animate_idle()
	if _visit_left <= 0.0:
		_home_visit = null
		_walk_to(_next_spot())
	return true


## A few words above their head for a while (a visit's greeting).
func say(text: String) -> void:
	if is_instance_valid(_said):
		_said.queue_free()
	var l := Label3D.new()
	l.text = text
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.pixel_size = 0.004
	l.font_size = 40
	l.outline_size = 12
	l.width = 900.0
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.modulate = LookObject.LINE_COLOR
	l.outline_modulate = Color(0, 0, 0, 0.55)
	add_child(l)
	l.position = Vector3.UP * 2.3
	_said = l
	var t := l.create_tween()
	t.tween_property(l, "modulate:a", 1.0, 0.25).from(0.0)
	t.tween_interval(LookObject.HOLD + 1.0)
	t.tween_property(l, "modulate:a", 0.0, 0.6)
	t.tween_callback(l.queue_free)


## Free to come and play dice (DiceGame): out at the tavern and settled in, nothing else on.
func free_for_dice() -> bool:
	return _part == VillagerDay.Part.TAVERN and not _inside and not scripted and not _watching 		and _seat != null and _target == _seat and state == State.IDLE and _seat.is_in_group("seat")


## Comes over to the dice table and sits at `seat`.
func join_dice(seat: Marker3D) -> void:
	_leave_seat()
	_seat = seat
	seat.set_meta(&"taken_by", self)
	_walk_to(seat)


## At the seat (or stage, or dance spot) they've claimed, not just on the way to it.
func _settled() -> bool:
	return _seat != null and _target == _seat and state != State.WALK 		and Vector2(global_position.x - _seat.global_position.x, global_position.z - _seat.global_position.z).length() < 0.25


## Sat at the seat they were going to.
func at_seat() -> bool:
	return _seat != null and _target == _seat and state == State.IDLE 		and Vector2(global_position.x - _seat.global_position.x, global_position.z - _seat.global_position.z).length() < 0.2


## The game's over: back to a seat of their own.
func leave_dice() -> void:
	if _seat and _seat.is_in_group("dice_seat"):
		_leave_seat()
		if not _inside and not scripted:
			_walk_to(_next_spot())


## Their seat has gone (the tavern was rebuilt round them): find another.
func reseat() -> void:
	if _seat and is_instance_valid(_seat) and not _seat.is_visible_in_tree():
		_leave_seat()
		if not _inside and not scripted and not _watching:
			_walk_to(_next_spot())


## On the stage, playing: the band's going (Tavern).
func playing_music() -> bool:
	return _seat != null and _seat.is_in_group("stage") and _target == _seat and state == State.IDLE 		and _part == VillagerDay.Part.TAVERN


## Up for a dance at `spot` (Tavern, at the top tier).
func dance(spot: Marker3D) -> void:
	_leave_seat()
	_seat = spot
	spot.set_meta(&"taken_by", self)
	_walk_to(spot)


## The tune's over: back to a seat.
func stop_dancing() -> void:
	if _seat and _seat.is_in_group("dance_spot"):
		_leave_seat()
		if not _inside and not scripted:
			_walk_to(_next_spot())


## A throw of the dice: the right arm swings forward over the table.
func gesture_throw() -> void:
	_throw_at = _phase


## A round of the square: the next of the network's square points, facing the middle.
func _stroll_spot() -> Marker3D:
	if _paths == null:
		_paths = get_tree().get_first_node_in_group("village_paths") as VillagePaths
	if _paths == null:
		return _pick_spot()
	if _stroll == null:
		_stroll = Marker3D.new()
		_stroll.name = "Stroll"
		_stroll.top_level = true
		add_child(_stroll)
		_stroll_i = randi() % SQUARE_ROUND.size()
	_stroll_i = (_stroll_i + 1) % SQUARE_ROUND.size()
	var p := _paths.named(SQUARE_ROUND[_stroll_i])
	var middle := VillageDecor.HEARTHVALE_CENTER
	_stroll.global_transform = Transform3D(Basis(Vector3.UP, atan2(middle.x - p.x, middle.y - p.z)), p)
	return _stroll


## Takes the nearest free seat of `kind` (markers in the "seat" group: benches, terrace, tavern;
## or another `group`'s, like the tavern's places to stand), preferring their own building's.
func _claim_seat(kind: StringName, group := "seat", reach := SEAT_RANGE) -> Marker3D:
	var best: Marker3D = null
	var best_d := reach
	for s in get_tree().get_nodes_in_group(group):
		var m := s as Marker3D
		if m == null or m.get_meta(&"kind", &"") != kind or not m.is_visible_in_tree() or _taken(m):
			continue
		var d := m.global_position.distance_to(global_position)
		if m.has_meta(&"home") and m.get_meta(&"home") == building:
			d -= 20.0
		if d < best_d:
			best_d = d
			best = m
	if best:
		best.set_meta(&"taken_by", self)
		_seat = best
	return best


func _leave_seat() -> void:
	if _seat and is_instance_valid(_seat) and _seat.has_meta(&"taken_by") and _seat.get_meta(&"taken_by") == self:
		_seat.remove_meta(&"taken_by")
	_seat = null


## Someone else is sitting there (or on their way).
func _taken(m: Marker3D) -> bool:
	if not m.has_meta(&"taken_by"):
		return false
	var by: Variant = m.get_meta(&"taken_by")
	return is_instance_valid(by) and by != self


func _walk_to(m: Marker3D) -> void:
	if m == null or m == _target and global_position.distance_to(_ground(m.global_position)) < 0.3:
		_enter(State.IDLE)
		return
	_indoor_walk = false
	_target = m
	_route = _route_to(m.global_position)
	_walk_from = global_position
	_speed = 0.0
	if not _watching:  # a long way across the village (the green is wide): they step out
		_hurry = BRISK if _route_length() > BRISK_FROM else 1.0
	state = State.WALK


## How far the walk ahead is, along its route.
func _route_length() -> float:
	var total := 0.0
	var at := global_position
	for p in _route:
		total += Vector2(p.x - at.x, p.z - at.z).length()
		at = p
	return total


## The way to `to`: along the village's paths (VillagePaths) when there are some, else straight.
## In or out of their own walk-in house, by its door (the Doorway marker just inside it, and the
## Door spot just outside). The last point is always `to`.
func _route_to(to: Vector3) -> PackedVector3Array:
	if _paths == null:
		_paths = get_tree().get_first_node_in_group("village_paths") as VillagePaths
	var doorway := building.mark("Doorway")
	var door := building.spot("Door")
	if doorway and door and building.inside(to) != building.inside(global_position):
		if building.inside(to):  # going in: to the door, through it, across the room
			var way := _paths.route(global_position, door.global_position) if _paths \
					else PackedVector3Array([door.global_position])
			way.append(doorway.global_position)
			way.append(to)
			return way
		var out := PackedVector3Array([doorway.global_position, door.global_position])  # coming out
		out.append_array(_paths.route(door.global_position, to) if _paths else PackedVector3Array([to]))
		return out
	if _paths:
		return _paths.route(global_position, to)
	return PackedVector3Array([to])


func _walk(delta: float) -> void:
	var goal := _target.global_position
	var last := _route.size() <= 1
	if not last:
		goal = _route[0]
	var flat := Vector3(goal.x - global_position.x, 0, goal.z - global_position.z)
	var dist := flat.length()
	if not last and dist < WAYPOINT_REACH:  # round the corner without stopping
		_route.remove_at(0)
		_walk_from = global_position
		return
	if dist < 0.08:
		global_position = _ground(goal)
		_route.clear()
		_enter(State.WORK if _target.name.begins_with("Work") else State.IDLE)
		return
	# speed up from a standstill, slow into the stop (not at the points on the way)
	var cruise := walk_speed * _hurry * (clampf(dist / 0.7, 0.3, 1.0) if last else 1.0)
	_speed = move_toward(_speed, cruise, 3.0 * _hurry * delta)
	var step := minf(_speed * delta, dist)
	var next := global_position + flat / dist * step
	# height: the ground, but on the last stretch never below the straight line between spots
	# (docks, porches); indoors, the line between the points (floors, the stair)
	next.y = _ground_height(next)
	if _indoor_walk:
		var leg := Vector2(goal.x - _walk_from.x, goal.z - _walk_from.z).length()
		next.y = lerpf(_walk_from.y, goal.y, clampf(1.0 - (dist - step) / maxf(leg, 0.001), 0.0, 1.0))
	elif last:
		var total := Vector2(goal.x - _walk_from.x, goal.z - _walk_from.z).length()
		var t := 1.0 - (dist - step) / maxf(total, 0.001)
		next.y = maxf(next.y, lerpf(_walk_from.y, goal.y, clampf(t, 0.0, 1.0)))
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


## Idling on a seat (a Bench spot, or one from the "seat" group): sitting on it.
func _seated() -> bool:
	return _target != null and (_target.name == "Bench" or _target.is_in_group("seat"))		and Vector2(global_position.x - _target.global_position.x, global_position.z - _target.global_position.z).length() < 0.2


func _animate_sit() -> void:
	var sway := sin(_phase * 0.8)
	_pose(&"Body", -0.08, sway * 0.02, 0.0, Vector3(0, 0.02, -0.05))  # sat back a little
	_pose(&"LegL", -1.45, -0.06)  # legs out in front over the edge of the seat
	_pose(&"LegR", -1.45, 0.06)
	_pose(&"ArmL", -0.55, -0.12)  # hands on knees
	_pose(&"ArmR", -0.55, 0.12)


## At the tavern, settled in (sitting, or standing at the bar): chatting with their hands, a
## drink now and then, and the odd laugh. Each villager out of step with the others.
func _animate_chat(seated: bool) -> void:
	var me := float(get_instance_id() % 97)
	if seated:
		_animate_sit()
	else:
		_animate_idle()
	var talk := maxf(sin(_phase * 0.55 + me), 0.0)  # in a spell of talking: hands about
	var drink := maxf(sin(_phase * 0.31 + me * 1.7) - 0.7, 0.0) / 0.3  # the mug up to the mouth
	var laugh := maxf(sin(_phase * 0.19 + me * 0.6) - 0.88, 0.0) / 0.12
	_pose(&"ArmR", lerpf(-0.6, -2.3, drink) + sin(_phase * 3.1) * 0.15 * talk, 0.12)
	_pose(&"ArmL", -0.55 - talk * (0.45 + sin(_phase * 2.3 + 1.0) * 0.3), -0.12 - talk * 0.2)
	var since_throw := _phase - _throw_at
	if since_throw < 0.7:  # throwing the dice: back, then a flick forward over the table
		var k := since_throw / 0.7
		_pose(&"ArmR", lerpf(-0.7, -1.9, sin(k * PI * 0.5)) if k < 0.6 else lerpf(-1.9, -1.1, (k - 0.6) / 0.4), 0.1)
	if laugh > 0.3 and not _laughing:
		_play(LAUGH_SFX, randf_range(0.9, 1.12))
	_laughing = laugh > 0.3
	if drink > 0.4 and not _drinking and randf() < 0.5:
		_play(CLINK_SFX, randf_range(0.92, 1.08))
	_drinking = drink > 0.4
	var bounce := absf(sin(_phase * 14.0)) * 0.03 * laugh
	if seated:
		_pose(&"Body", -0.08 - laugh * 0.15, 0.0, 0.0, Vector3(0, 0.02 + bounce, -0.05))
	else:
		_pose(&"Body", -laugh * 0.12, 0.0, 0.0, Vector3(0, bounce, 0))


## On the stage: a fiddle under the chin, the bow sawing away, a foot tapping.
func _animate_fiddle() -> void:
	var beat := _phase * 7.0
	_pose(&"ArmL", -1.5, -0.55)  # holding the neck out to the left
	_pose(&"ArmR", -1.25 + sin(beat * 0.5) * 0.28, 0.35 + cos(beat * 0.5) * 0.12)  # the bow
	_pose(&"Body", 0.0, sin(_phase * 1.6) * 0.06, 0.0, Vector3(0, absf(sin(beat * 0.5)) * 0.015, 0))
	_pose(&"LegL", 0.0)
	_pose(&"LegR", -maxf(sin(beat), 0.0) * 0.25)  # tapping


## Dancing: hopping from foot to foot, arms up and swinging, a little sway.
func _animate_dance() -> void:
	var beat := _phase * 6.5
	var hop := absf(sin(beat * 0.5))
	_pose(&"Body", 0.0, sin(beat * 0.25) * 0.15, 0.0, Vector3(0, hop * 0.07, 0))
	_pose(&"LegL", -maxf(sin(beat * 0.5), 0.0) * 0.6)
	_pose(&"LegR", -maxf(-sin(beat * 0.5), 0.0) * 0.6)
	_pose(&"ArmL", -2.4 + sin(beat * 0.5) * 0.4, -0.5)
	_pose(&"ArmR", -2.4 - sin(beat * 0.5) * 0.4, 0.5)


## A fiddle and bow in hand while they're playing on the stage.
func _show_fiddle(on: bool) -> void:
	if not on and _fiddle == null:
		return
	if _fiddle == null:
		if not _parts.has(&"ArmL") or not _parts.has(&"ArmR"):
			return
		var wood := StandardMaterial3D.new()
		wood.albedo_color = Color("8a4a24")
		wood.roughness = 0.5
		var body := BoxMesh.new()
		body.size = Vector3(0.14, 0.05, 0.36)
		body.material = wood
		_fiddle = MeshInstance3D.new()
		_fiddle.name = "Fiddle"
		_fiddle.mesh = body
		_parts[&"ArmL"].add_child(_fiddle)
		_fiddle.position = Vector3(0.0, -0.48, 0.12)
		var bow_mesh := BoxMesh.new()
		bow_mesh.size = Vector3(0.015, 0.015, 0.5)
		var pale := StandardMaterial3D.new()
		pale.albedo_color = Color("d8c8a0")
		bow_mesh.material = pale
		var bow := MeshInstance3D.new()
		bow.name = "Bow"
		bow.mesh = bow_mesh
		_parts[&"ArmR"].add_child(bow)
		bow.position = Vector3(0.0, -0.5, 0.1)
		_fiddle.set_meta(&"bow", bow)
	_fiddle.visible = on
	(_fiddle.get_meta(&"bow") as Node3D).visible = on


## A mug in the right hand while they're out at the tavern.
func _show_mug(on: bool) -> void:
	if not on and _mug == null:
		return
	if _mug == null:
		if not _parts.has(&"ArmR"):
			return
		var mesh := CylinderMesh.new()
		mesh.top_radius = 0.055
		mesh.bottom_radius = 0.05
		mesh.height = 0.13
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color("a37a55")
		mat.roughness = 0.85
		mesh.material = mat
		_mug = MeshInstance3D.new()
		_mug.name = "Mug"
		_mug.mesh = mesh
		_parts[&"ArmR"].add_child(_mug)
		_mug.position = Vector3(0.0, -0.5, 0.08)  # (in the hand, a little forward)
	_mug.visible = on


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
		Work.WIPE:
			# behind the bar: polishing a mug, round and round, now and then holding it up to look
			var c := _phase * 3.2
			var look := maxf(sin(_phase * 0.37), 0.0)
			look = look * look * look
			_pose(&"ArmL", lerpf(-1.0, -1.6, look), -0.15)
			_pose(&"ArmR", -1.05 + sin(c) * 0.12, 0.12 + cos(c) * 0.1)
			_pose(&"Body", -0.05, 0.0, 0.0, Vector3(0, sin(_phase * 1.7) * 0.006, 0))
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
