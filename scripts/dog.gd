class_name Dog
extends AnimatableBody3D
## Your dog (plans/dog.md). Like the villagers, no rig and no navmesh: the model is separate parts
## (Body, Head, Jaw, EarL/R, Tail, LegFL/FR/BL/BR: tools/blender/make_village.py dog()) posed in
## code, easing toward target poses, and he walks in straight lines over the ground.
## He follows you at a relaxed distance, off to one side (never in front of what you're hitting),
## trots ahead of you along roads and paths, sits when you stop, lies down while you gather, and
## now and then sniffs about while you stand still. Fall more than CATCH_UP behind and he pops in
## trotting up behind you, out of view.
## Pet him (E): a happy wiggle. He paddles after you into wading-depth water, waits on the bank
## where it's deeper than DEEP, and shakes himself dry with a spray when he comes out. While you
## fish he sits beside you and watches the float. (Fish only flee from noise, FishPond.disturb,
## and he makes none.)
## Before you have a dog, three strays nap by the clearing's pond (DogHome): a stray lifts his head
## and wags when you come close; pet one (E) and DogHome asks his name; the others wander off.
## Physics layer 9 only: you walk through him (the player's mask leaves it out), only the
## crosshair finds him (player.gd PET_MASK).

enum State { FOLLOW, SIT, LIE, SNIFF, PET, SHAKE }

const PET_LAYER := 1 << 8
## Where he keeps to: this far behind you and this far off to the side.
const FOLLOW_DIST := 2.4
const SIDE := 1.3
## While you gather, out to the side of you this far (and a little behind).
const GATHER_SIDE := 3.0
## On a road or path, this far ahead of you.
const AHEAD := 4.5
## Close enough to his spot to stop.
const ARRIVE := 0.7
## Farther than this behind and he pops in POP_BEHIND behind you, where you aren't looking.
const CATCH_UP := 50.0
const POP_BEHIND := 8.0
## Speeds (m/s): his slowest walk, and how much faster than you he may go to keep up.
const WALK := 1.4
const KEEP_UP := 1.25
const RUN := 7.5
const ACCEL := 7.0
## Stand still this long and he sits; gather this long (seconds) and he lies down.
const SIT_AFTER := 0.8
const LIE_AFTER := 4.0
## Standing still a while, now and then he wanders off a few metres to sniff.
const SNIFF_AFTER := 14.0
const SNIFF_RANGE := 3.5
## He won't go into water deeper than this (m); he floats, paddling, once it's past his legs.
const DEEP := 0.9
## How long a pat makes him wiggle, and how long a shake takes.
const PET_TIME := 1.8
const SHAKE_TIME := 1.3
## In water (deeper than WET_DEPTH) this long, and he shakes when he's out.
const WET_DEPTH := 0.12
const WET_AFTER := 0.6

var breed: StringName = &"shepherd"
var coat: StringName = &"saddle"
var dog_name := ""
var state := State.FOLLOW
## A cutscene, the meeting or a test drives him: no following of his own.
var scripted := false
## One of the strays: naps where he is until you pet him (or leave() sends him off).
var stray := false
## A stray who wasn't picked, on his way off over the hills.
var _leaving := Vector3.INF

var _player: CharacterBody3D  # (player.gd has no class_name)
var _terrain: Terrain3D
var _parts: Dictionary[StringName, Node3D] = {}
var _rest: Dictionary[StringName, Transform3D] = {}
var _targets: Dictionary[StringName, Transform3D] = {}
var _surfaces: Array[GeometryInstance3D] = []
var _leg := 0.3   # leg length (m), from the model: scales the sit and lie poses
var _speed := 0.0
var _yaw := 0.0
var _goal := Vector3.ZERO
var _still := 0.0    # how long you've stood still
var _busy := 0.0     # seconds left of "you're gathering" after your last swing
var _gathering := 0.0  # how long you've been at it
var _side := 1.0     # which side of you he keeps to
var _sniff_at := Vector3.INF
var _sniff_left := 0.0
var _next_sniff := SNIFF_AFTER
var _pet_left := 0.0
var _shake_left := 0.0
var _wet := 0.0      # how long he's been in the water
var _paddling := false
var _watch := Vector3.INF  # the float, while you fish
var _phase := 0.0    # gait
var _t := 0.0
var _last_state := State.FOLLOW
var _blend := 0.0


## Which dog he is; call before adding him to the tree.
func setup(b: StringName, c: StringName, n: String) -> void:
	breed = b
	coat = c
	dog_name = n


func _ready() -> void:
	add_to_group("stray_dog" if stray else "dog")
	collision_layer = PET_LAYER
	collision_mask = 0
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_ON
	sync_to_physics = false
	_build_model()
	_side = 1.0 if randf() < 0.5 else -1.0
	_yaw = rotation.y


func _build_model() -> void:
	var scene := load(Companion.model_path(breed, coat)) as PackedScene
	if scene == null:
		push_warning("Dog: no model for %s %s" % [breed, coat])
		return
	var inst := scene.instantiate() as Node3D
	inst.name = "Model"
	add_child(inst)
	for part: StringName in [&"Body", &"Head", &"Jaw", &"EarL", &"EarR", &"Tail", &"LegFL", &"LegFR", &"LegBL", &"LegBR"]:
		var n := inst.find_child(String(part), true, false) as Node3D
		if n:
			_parts[part] = n
			_rest[part] = n.transform
	if _parts.has(&"LegFL"):
		_leg = maxf(to_local(_parts[&"LegFL"].global_position).y, 0.1)
	var box := AABB()
	var first := true
	for g in inst.find_children("*", "GeometryInstance3D", true, false):
		var gi := g as GeometryInstance3D
		_surfaces.append(gi)
		var b := (global_transform.affine_inverse() * gi.global_transform) * gi.get_aabb()  # (in our own space)
		box = b if first else box.merge(b)
		first = false
	var shape := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = box.size
	shape.shape = bs
	shape.position = box.get_center()
	add_child(shape)


## Shown under the crosshair.
func prompt() -> String:
	if stray:
		return "E  Pet the %s" % Companion.BREED_NAMES.get(breed, "dog")
	return "E  Pet %s" % dog_name


func interact() -> void:
	if stray:
		var home := get_tree().get_first_node_in_group("dog_home") as DogHome
		if home:
			home.meet(self)
	else:
		pet()


## A pat: he wiggles, wags hard and looks up at you.
func pet() -> void:
	_pet_left = PET_TIME
	_speed = 0.0


## The stray you picked becomes your dog: his coat (the model swapped if it changed) and name.
func adopt_as(c: StringName, n: String) -> void:
	remove_from_group("stray_dog")
	add_to_group("dog")
	stray = false
	dog_name = n
	if c != coat:
		coat = c
		for child in get_children():
			if child.name == "Model" or child is CollisionShape3D:
				remove_child(child)
				child.queue_free()
		_parts.clear()
		_rest.clear()
		_targets.clear()
		_surfaces.clear()
		_build_model()
	state = State.SIT


## A stray who wasn't picked trots off over the hills, `away` from you, and is gone once far off.
func leave(away: Vector3) -> void:
	remove_from_group("stray_dog")
	_leaving = global_position + away.normalized() * 200.0


func _wander_off(delta: float) -> void:
	_goal = _leaving
	state = State.FOLLOW
	var to := _goal - global_position
	to.y = 0.0
	_speed = move_toward(_speed, WALK * 1.8, ACCEL * delta)
	var pos := global_position + to.normalized() * _speed * delta
	_turn_to(atan2(to.x, to.z), delta, 6.0)
	pos.y = _ground(pos)
	global_transform = Transform3D(Basis(Vector3.UP, _yaw), pos)
	if _flat(pos - _player.global_position) > 70.0:
		queue_free()


## Napping by the pond; with you near he sits up, watches you and wags.
func _nap(delta: float) -> void:
	var near := _flat(_player.global_position - global_position) < 7.0
	state = State.SIT if near else State.LIE
	if near:
		var face := _player.global_position - global_position
		_turn_to(atan2(face.x, face.z), delta, 2.0)
		global_transform = Transform3D(Basis(Vector3.UP, _yaw), global_position)


func set_highlighted(on: bool) -> void:
	for s in _surfaces:
		s.set_instance_shader_parameter("highlight", 1.0 if on else 0.0)


func _physics_process(delta: float) -> void:
	_t += delta
	if _player == null:
		_player = get_tree().get_first_node_in_group("player") as CharacterBody3D
	if _terrain == null:
		_terrain = get_tree().get_first_node_in_group("terrain") as Terrain3D
	if _player and _leaving != Vector3.INF:
		_wander_off(delta)
	elif _player and stray:
		_nap(delta)
	elif _player and not scripted:
		_think(delta)
		_move(delta)
	_animate(delta)
	_apply_poses(delta)


# --- following ----------------------------------------------------------------------------------

func _think(delta: float) -> void:
	_water(delta)
	if _pet_left > 0.0 or _shake_left > 0.0:
		_pet_left = maxf(_pet_left - delta, 0.0)
		_shake_left = maxf(_shake_left - delta, 0.0)
		state = State.PET if _pet_left > 0.0 else State.SHAKE
		_goal = global_position
		var face := _player.global_position - global_position
		if state == State.PET and face.length() > 0.3:
			_turn_to(atan2(face.x, face.z), delta, 6.0)
		if _pet_left > 0.0 or _shake_left > 0.0:
			return
	var pp := _player.global_position
	var vel := Vector3(_player.velocity.x, 0.0, _player.velocity.z)
	var moving := vel.length() > 0.6
	_still = 0.0 if moving else _still + delta
	var rod: Node = _player.get("rodfishing")
	var lure: Node3D = rod.get("lure") if rod else null
	_watch = lure.global_position if rod and rod.call("is_busy") and is_instance_valid(lure) else Vector3.INF
	if _player.call("is_busy"):
		_busy = 2.5
	_busy = maxf(_busy - delta, 0.0)
	_gathering = _gathering + delta if _busy > 0.0 else 0.0
	if _flat(global_position - pp) > CATCH_UP:
		_pop_in()
		return
	var look := _look_dir()
	var right := Vector3(-look.z, 0.0, look.x)
	if moving:
		var dir := vel.normalized()
		_sniff_at = Vector3.INF
		if _on_road(pp) and _flat(global_position - pp) < FOLLOW_DIST * 3.0:
			_goal = pp + dir * AHEAD + Vector3(-dir.z, 0.0, dir.x) * _side * 0.6
		else:
			_goal = pp - dir * FOLLOW_DIST + Vector3(-dir.z, 0.0, dir.x) * _side * SIDE
	elif _busy > 0.0:  # out to the side of what you're hitting, a little behind
		_goal = pp + right * _side * GATHER_SIDE - look * 0.8
	else:
		_goal = pp - look * FOLLOW_DIST * 0.6 + right * _side * SIDE * 1.4
		_sniff(delta, pp)
	if _sniff_at != Vector3.INF:
		_goal = _sniff_at
	# never in front of you while you're at work
	if _busy > 0.0 and _in_front(_goal, pp, look):
		_goal = pp + right * _side * GATHER_SIDE
	_goal = _shore(global_position, _goal)
	var to_goal := _flat(_goal - global_position)
	if to_goal > ARRIVE * (1.0 if state == State.FOLLOW else 2.2):
		state = State.FOLLOW
	elif _sniff_at != Vector3.INF:
		state = State.SNIFF
	elif _gathering > LIE_AFTER or _still > SNIFF_AFTER * 3.0:
		state = State.LIE
	elif _still > SIT_AFTER or _busy > 0.0:
		state = State.SIT


## Wet: counts time in the water; out of it after a while, he shakes himself dry.
func _water(delta: float) -> void:
	var d := WaterBody.depth_at(get_tree(), global_position)
	if d > WET_DEPTH:
		_wet += delta
	elif _wet > WET_AFTER and _shake_left <= 0.0 and _pet_left <= 0.0:
		_wet = 0.0
		_shake_left = SHAKE_TIME
		_speed = 0.0
		_spray()
	elif d <= 0.0:
		_wet = 0.0


func _spray() -> void:
	var at := global_position + Vector3.UP * (_leg + 0.15)
	RodFishing.splash(get_parent(), at, 0.45)
	get_tree().create_timer(0.35).timeout.connect(func() -> void:
		if is_inside_tree():
			RodFishing.splash(get_parent(), global_position + Vector3.UP * (_leg + 0.15), 0.35))


## `to`, unless the way there runs into water deeper than DEEP: then the last spot before it (he
## waits on the bank). From deep water (popped in, or the water rose) he may always head out.
func _shore(from: Vector3, to: Vector3) -> Vector3:
	var tree := get_tree()
	if WaterBody.depth_at(tree, from) > DEEP:
		return to
	var flat := Vector3(to.x - from.x, 0.0, to.z - from.z)
	var n := int(flat.length() / 0.5)
	var last := from
	for i in range(1, n + 1):
		var p := from + flat * (float(i) / n)
		if WaterBody.depth_at(tree, p) > DEEP:
			return last
		last = p
	return to


## Standing about a while: now and then off a few metres to sniff, then back.
func _sniff(delta: float, pp: Vector3) -> void:
	if _sniff_at != Vector3.INF:
		if _flat(_sniff_at - global_position) < ARRIVE * 1.5:
			_sniff_left -= delta
			if _sniff_left <= 0.0:
				_sniff_at = Vector3.INF
				_next_sniff = _still + randf_range(SNIFF_AFTER * 0.6, SNIFF_AFTER * 1.4)
		return
	if _still > _next_sniff:
		var a := randf() * TAU
		_sniff_at = pp + Vector3(cos(a), 0.0, sin(a)) * randf_range(2.0, SNIFF_RANGE)
		_sniff_left = randf_range(2.0, 4.0)


func _move(delta: float) -> void:
	var pos := global_position
	var to := _goal - pos
	to.y = 0.0
	var dist := to.length()
	var player_speed := _flat(_player.velocity)
	var want := 0.0
	if state == State.FOLLOW or (state == State.SNIFF and dist > ARRIVE):
		want = clampf(dist * 1.3, WALK, maxf(player_speed * KEEP_UP, WALK * 1.6))
		if _flat(pos - _player.global_position) > 12.0:
			want = RUN
	_speed = move_toward(_speed, want, ACCEL * delta)
	if dist > 0.01 and _speed > 0.0:
		var step := minf(_speed * delta, dist)
		pos += to / dist * step
		_turn_to(atan2(to.x, to.z), delta, 8.0)
	elif state == State.SIT or state == State.LIE:
		var face := _player.global_position - pos
		if face.length() > 0.5 and state == State.SIT:
			_turn_to(atan2(face.x, face.z), delta, 3.0)
	pos.y = _float_or_ground(pos)
	global_transform = Transform3D(Basis(Vector3.UP, _yaw), pos)


## The ground, or in water past his legs, floating with his back at the surface.
func _float_or_ground(pos: Vector3) -> float:
	var g := _ground(pos)
	var d := WaterBody.depth_at(get_tree(), pos)
	_paddling = d > _leg * 0.9
	return g + d - _leg * 0.9 if _paddling else g


## Pops in behind you, out of view: POP_BEHIND behind where you're looking (or to a side if
## that's water or off the world).
func _pop_in() -> void:
	var pp := _player.global_position
	var look := _look_dir()
	for turn in [0.0, 0.6, -0.6, 1.2, -1.2]:
		var back := (-look).rotated(Vector3.UP, turn)
		var at := pp + back * POP_BEHIND
		var g := _ground_or_nan(at)
		if not is_nan(g) and WaterBody.depth_at(get_tree(), Vector3(at.x, g, at.z)) == 0.0:
			at.y = g
			_yaw = atan2(-back.x, -back.z)  # facing you, trotting up
			global_transform = Transform3D(Basis(Vector3.UP, _yaw), at)
			reset_physics_interpolation()
			_speed = WALK * 2.0
			state = State.FOLLOW
			return


func _look_dir() -> Vector3:
	var f := -(_player.get("camera") as Node3D).global_basis.z
	f.y = 0.0
	return f.normalized() if f.length() > 0.01 else Vector3.FORWARD


func _in_front(p: Vector3, pp: Vector3, look: Vector3) -> bool:
	var d := Vector3(p.x - pp.x, 0.0, p.z - pp.z)
	return d.length() < 6.0 and d.normalized().dot(look) > cos(deg_to_rad(40.0))


func _on_road(p: Vector3) -> bool:
	if _terrain == null or _terrain.data == null:
		return false
	var id: int = _terrain.data.get_control_base_id(p)
	return id == WorldMap.TEX_ROAD or id == WorldMap.TEX_PATH


func _ground(p: Vector3) -> float:
	var g := _ground_or_nan(p)
	return p.y if is_nan(g) else g


func _ground_or_nan(p: Vector3) -> float:
	if _terrain and _terrain.data:
		return _terrain.data.get_height(p)
	return NAN


func _turn_to(yaw: float, delta: float, rate: float) -> void:
	_yaw = lerp_angle(_yaw, yaw, 1.0 - exp(-rate * delta))


static func _flat(v: Vector3) -> float:
	return Vector2(v.x, v.z).length()


# --- posing -------------------------------------------------------------------------------------

## Target pose for a part, relative to its rest: x swings it forward/back (negative = the far end
## forward, for legs; nose up, for the body), z out to the side, y round its own axis; offset in
## its parent's space. It eases there in _apply_poses.
func _pose(part: StringName, x: float, z := 0.0, y := 0.0, offset := Vector3.ZERO) -> void:
	if not _parts.has(part):
		return
	var rest := _rest[part]
	_targets[part] = Transform3D(rest.basis * Basis.from_euler(Vector3(x, y, z)), rest.origin + offset)


func _animate(delta: float) -> void:
	var gait := clampf(_speed / 3.0, 0.0, 1.0)
	_phase += delta * (4.0 + _speed * 2.2 + (5.0 if _paddling else 0.0))
	var s := sin(_phase)
	var wag_speed := 9.0 if state == State.FOLLOW or state == State.SNIFF else 5.0
	var wag := sin(_t * wag_speed) * (0.5 if state != State.LIE else 0.25)
	match state:
		State.PET:
			var w := sin(_t * 14.0)
			_pose(&"Body", 0.0, w * 0.12, 0.0, Vector3(0, absf(sin(_t * 7.0)) * 0.03, 0))
			for leg in [&"LegFL", &"LegFR", &"LegBL", &"LegBR"]:
				_pose(leg, 0.0)
			_pose(&"Head", -0.3, -w * 0.15)
			_pose(&"Jaw", 0.2)
			wag = sin(_t * 18.0) * 0.75
		State.SHAKE:
			var w := sin(_t * 30.0) * (0.25 + 0.15 * clampf(_shake_left / SHAKE_TIME, 0.0, 1.0))
			_pose(&"Body", 0.0, w, 0.0, Vector3(0, 0.02, 0))
			for leg in [&"LegFL", &"LegFR", &"LegBL", &"LegBR"]:
				_pose(leg, 0.0, -w * 0.4)
			_pose(&"Head", 0.0, -w * 1.6)
			_pose(&"Jaw", 0.05)
		State.FOLLOW, State.SNIFF:
			var swing := 0.55 * gait if not _paddling else 0.8  # paddling: all four going, even standing
			_pose(&"LegFL", s * swing)
			_pose(&"LegBR", s * swing)
			_pose(&"LegFR", -s * swing)
			_pose(&"LegBL", -s * swing)
			_pose(&"Body", 0.0, 0.0, 0.0, Vector3(0, -absf(cos(_phase)) * 0.025 * gait, 0))
			var sniffing := state == State.SNIFF and _speed < 0.1
			_pose(&"Head", 0.55 if sniffing else 0.08 * gait, 0.0, sin(_t * 3.0) * (0.35 if sniffing else 0.05),
					Vector3(0, -0.04 if sniffing else 0.0, 0))
			_pose(&"Jaw", 0.12 * gait)  # panting while he trots
		State.SIT:
			var tilt := -0.45
			_pose(&"Body", tilt, 0.0, 0.0, Vector3(0, -_leg * 0.38, -_leg * 0.15))
			_pose(&"LegFL", -tilt)
			_pose(&"LegFR", -tilt)
			_pose(&"LegBL", -0.95, 0.12)
			_pose(&"LegBR", -0.95, -0.12)
			_pose(&"Head", -tilt * 0.8 + sin(_t * 0.7) * 0.05, 0.0, _head_turn(sin(_t * 0.4) * 0.25))
			_pose(&"Jaw", 0.08 + sin(_t * 6.0) * 0.04)
		State.LIE:
			_pose(&"Body", 0.0, 0.0, 0.0, Vector3(0, -_leg * 0.82, 0))
			_pose(&"LegFL", -1.45)
			_pose(&"LegFR", -1.45)
			_pose(&"LegBL", -1.25, 0.35)
			_pose(&"LegBR", -1.25, -0.35)
			_pose(&"Head", 0.3, 0.0, sin(_t * 0.3) * 0.2, Vector3(0, -0.03, 0))
			_pose(&"Jaw", 0.0)
	_pose(&"Tail", 0.0, 0.0, wag)
	var ear := sin(_phase * 2.0) * 0.08 * gait
	_pose(&"EarL", ear)
	_pose(&"EarR", -ear)


## Head yaw: toward the float while you fish (within what his neck allows), else `idle`.
func _head_turn(idle: float) -> float:
	if _watch == Vector3.INF:
		return idle
	var local := to_local(_watch)
	return clampf(atan2(local.x, local.z), -0.9, 0.9)


func _apply_poses(delta: float) -> void:
	if state != _last_state:
		_last_state = state
		_blend = 0.35
	_blend = maxf(_blend - delta, 0.0)
	var k := 1.0 - exp(-(6.0 if _blend > 0.0 else 20.0) * delta)
	for part in _targets:
		var n := _parts[part]
		n.transform = n.transform.interpolate_with(_targets[part], k)
