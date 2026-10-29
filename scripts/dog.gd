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
## At night, once you have the lantern and it's lit, he carries it in his mouth and walks a little
## ahead of you to light the way (your belt lantern hides: Lantern asks carrying()). Hold the raise
## key and it's back in your hand; let go and he takes it again after a moment.
## At night: standing still, he lies down at your feet and dozes. With a kennel built and you in
## the village he goes to sleep in its doorway (VillageDecor.kennel_door()), and in the morning he's
## waiting there until you come by.
## Hints, never needed (plans/dog.md): now and then he trots over to a nearby rare-look node or
## an ore fault and sniffs at it, wagging, with a soft woof; he stops to stare at a fish school; a
## Big or Huge fish landing gets a happy wiggle and a woof; a far-off wolf howl at night pricks
## his ears and gets a small woof back.
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
## Carrying the lantern: this far ahead of you while you walk; after you've held it up yourself,
## he takes it back this long after you let go; and he only carries it this close to you.
const LIGHT_AHEAD := 3.2
const RETAKE := 1.2
const CARRY_RANGE := 20.0
const LANTERN_MODEL := preload("res://models/lantern.glb")
## His sounds (audio/dog/SOURCES.md, picked by ear 2026-10-29), per id; level per id (dB), and the
## breeds' pitch (the terrier higher, the big fluffy one lower). Panting comes every PANT_GAP
## seconds while he trots (quietly), sniffs every SNIFF_GAP while he's nosing about.
const SOUNDS := {
	&"pant": [preload("res://audio/dog/pant.wav")],
	&"sniff": [preload("res://audio/dog/sniff.wav")],
	&"whine": [preload("res://audio/dog/whine.wav")],
	&"woof": [preload("res://audio/dog/woof.wav")],
	&"shake": [preload("res://audio/dog/shake.wav")],
}
const SOUND_DB := {&"pant": -20.0, &"sniff": -16.0, &"whine": -12.0, &"woof": -9.0, &"shake": -12.0}
const PANT_GAP := Vector2(2.5, 5.0)
const SNIFF_GAP := Vector2(1.6, 3.0)
const BREED_PITCH := {&"terrier": 1.25, &"shepherd": 1.0, &"fluffy": 0.82}
## At night he dozes this close to your feet once you've stood still DOZE_AFTER seconds.
const AT_FEET := 0.9
const DOZE_AFTER := 2.5
## In the village (this close to the square) at night, he sleeps in the kennel; in the morning he
## waits by it until you come this close.
const VILLAGE_RANGE := 65.0
const GREET := 9.0
## Hints: how near something must be (m), at most one this often (s), and how long he lingers.
const HINT_RANGE := 9.0
const HINT_GAP := 40.0
const HINT_TIME := 3.5
## A fish this many counts or more (Big 2, Huge 3: LandedFish.count) is worth a woof.
const BIG_FISH := 2

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
var _lantern: Node3D       # in his mouth (built with the model)
var _lantern_light: OmniLight3D
var _lantern_glass: Array[MeshInstance3D] = []
var _lantern_level := 0.0
var _retake := 0.0
var _home := false      # sleeping in (or, by day, waiting at) the kennel
var _sleeping := false  # dozing: head right down, slow breaths
var _face := INF        # a yaw to settle to where he stops (the kennel door), else he faces you
var _hint_at := Vector3.INF  # the node he's showing you, or (fish) where he stares from
var _hint_look := Vector3.INF
var _hint_left := 0.0
var _hint_wait := 15.0
var _hint_scan := 0.0
var _hinted: Dictionary[int, bool] = {}
var _listen := Vector3.INF  # a wolf howled from there
var _listen_left := 0.0
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
	get_tree().node_added.connect(_on_node_added)
	Ambience.howled.connect(_on_howl)


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
	_build_lantern(inst)
	var box := AABB()
	var first := true
	for g in inst.find_children("*", "GeometryInstance3D", true, false):
		var gi := g as GeometryInstance3D
		if gi is MeshInstance3D:  # the palette's colours (as Prop does)
			(gi as MeshInstance3D).material_override = PaletteMaterial.for_mesh((gi as MeshInstance3D).mesh)
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
	say(&"whine")


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
		_lantern_glass.clear()
		_lantern = null
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


## The lantern, hung from the socket in his jaw, with a light like the one you carry.
func _build_lantern(model: Node3D) -> void:
	var socket := model.find_child("LanternSocket", true, false) as Node3D
	if socket == null:
		return
	_lantern = LANTERN_MODEL.instantiate() as Node3D
	_lantern.name = "Lantern"
	socket.add_child(_lantern)
	for m in _lantern.find_children("*", "MeshInstance3D", true, false):
		var mesh := m as MeshInstance3D
		mesh.material_override = PaletteMaterial.for_mesh(mesh.mesh)
		if String(mesh.name).begins_with("Lamp"):
			_lantern_glass.append(mesh)
	_lantern_light = OmniLight3D.new()
	_lantern_light.light_color = Lantern.LIGHT_COLOR
	_lantern_light.omni_range = Lantern.LIGHT_RANGE
	_lantern_light.omni_attenuation = 1.2
	_lantern_light.shadow_enabled = true
	_lantern_light.shadow_bias = 0.08
	_lantern_light.position = Lantern.FLAME + Vector3(0, 0.05, 0)
	_lantern.add_child(_lantern_light)
	_lantern.visible = false


## Whether he has the lantern now: yours, lit, you not holding it up (or only just let go), him
## near you and not a stray.
func carrying() -> bool:
	return not stray and _leaving == Vector3.INF and Lamps.has_lantern and Lamps.lantern_lit 			and _retake <= 0.0 and _player != null and _flat(_player.global_position - global_position) < CARRY_RANGE


func _lantern_tick(delta: float) -> void:
	var raising := false
	if _player:
		var held: Node = _player.get("lantern")
		raising = held != null and float(held.get("_raise")) > 0.05
	if raising:
		_retake = RETAKE
	else:
		_retake = maxf(_retake - delta, 0.0)
	if _lantern == null:
		return
	var on := carrying()
	_lantern_level = move_toward(_lantern_level, 1.0 if on else 0.0, delta * (3.0 if on else 6.0))
	_lantern.visible = _lantern_level > 0.01
	var flicker := 1.0 + 0.07 * sin(_t * 7.3) + 0.04 * sin(_t * 19.1 + 1.3)
	_lantern_light.light_energy = Lantern.LIGHT_ENERGY * _lantern_level * flicker
	for m in _lantern_glass:
		m.set_instance_shader_parameter("glow", _lantern_level * (0.6 + 0.1 * flicker))
	_lantern.rotation = Vector3(sin(_phase) * 0.15 * clampf(_speed / 3.0, 0.0, 1.0), 0.0, sin(_phase * 0.5) * 0.1)


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
	_lantern_tick(delta)
	_listen_left = maxf(_listen_left - delta, 0.0)
	_idle_sounds(delta)
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
	_face = INF
	_sleeping = false
	if _kennel(pp):
		return
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
		if carrying() and _flat(global_position - pp) < FOLLOW_DIST * 3.0:  # lighting the way
			_goal = pp + dir * LIGHT_AHEAD + Vector3(-dir.z, 0.0, dir.x) * _side * 0.4
		elif _on_road(pp) and _flat(global_position - pp) < FOLLOW_DIST * 3.0:
			_goal = pp + dir * AHEAD + Vector3(-dir.z, 0.0, dir.x) * _side * 0.6
		else:
			_goal = pp - dir * FOLLOW_DIST + Vector3(-dir.z, 0.0, dir.x) * _side * SIDE
	elif _busy > 0.0:  # out to the side of what you're hitting, a little behind
		_goal = pp + right * _side * GATHER_SIDE - look * 0.8
	elif DayNight.is_night() and _still > DOZE_AFTER:  # at your feet, dozing (no sniffing about)
		_goal = pp + right * _side * AT_FEET - look * 0.3
		_sniff_at = Vector3.INF
	else:
		_goal = pp - look * FOLLOW_DIST * 0.6 + right * _side * SIDE * 1.4
		_sniff(delta, pp)
	if _sniff_at != Vector3.INF:
		_goal = _sniff_at
	_hints(delta, moving)
	if _hint_at != Vector3.INF:
		_goal = _hint_at
	# never in front of you while you're at work
	if _busy > 0.0 and _in_front(_goal, pp, look):
		_goal = pp + right * _side * GATHER_SIDE
	_goal = _shore(global_position, _goal)
	var to_goal := _flat(_goal - global_position)
	if to_goal > ARRIVE * (1.0 if state == State.FOLLOW else 2.2):
		state = State.FOLLOW
	elif _hint_at != Vector3.INF:
		state = State.SIT if _hint_look != Vector3.INF and _is_fish_hint else State.SNIFF
	elif _sniff_at != Vector3.INF:
		state = State.SNIFF
	elif _gathering > LIE_AFTER or _still > SNIFF_AFTER * 3.0 or (DayNight.is_night() and _still > DOZE_AFTER):
		state = State.LIE
		_sleeping = DayNight.is_night() and _busy <= 0.0
	elif _still > SIT_AFTER or _busy > 0.0:
		state = State.SIT


## Night in the village with a kennel: off to bed in its doorway; by day, still there until you
## come close. True while that's where he is (or is going).
func _kennel(pp: Vector3) -> bool:
	var night := DayNight.is_night()
	var decor := get_tree().get_first_node_in_group("village_decor")
	var door: Variant = decor.call("kennel_door") if decor else null
	var in_village := _flat(pp - Vector3(WorldMap.VILLAGE_CENTER.x, 0.0, WorldMap.VILLAGE_CENTER.y)) < VILLAGE_RANGE
	if door == null or (night and not in_village):
		_home = false
	elif night:
		_home = true
	elif _home and _flat(pp - global_position) < GREET:
		_home = false  # good morning
	if not _home:
		return false
	var t := door as Transform3D
	_goal = t.origin
	_face = atan2(t.basis.z.x, t.basis.z.z)
	if _flat(_goal - global_position) > ARRIVE:
		state = State.FOLLOW
	else:
		state = State.LIE if night else State.SIT
		_sleeping = night
	return true


var _is_fish_hint := false


## Now and then: over to a rare-look node or an ore fault near him, or a stare at a fish school.
## Never while you walk on, gather or fish, never at night.
func _hints(delta: float, moving: bool) -> void:
	_hint_wait -= delta
	if _hint_at != Vector3.INF:
		var arrived := _flat(_hint_at - global_position) < ARRIVE * 1.5
		if arrived:
			if _hint_left == HINT_TIME:
				say(&"woof")
			_hint_left -= delta
		if _hint_left <= 0.0 or moving or _busy > 0.0 or _flat(_hint_at - _player.global_position) > HINT_RANGE * 2.5:
			_hint_at = Vector3.INF
			_hint_look = Vector3.INF
			_hint_wait = HINT_GAP
		return
	_hint_scan -= delta
	if moving or _busy > 0.0 or _watch != Vector3.INF or DayNight.is_night() or _hint_wait > 0.0 or _hint_scan > 0.0:
		return
	_hint_scan = 1.0
	for n in get_tree().get_nodes_in_group("gatherable"):
		var node := n as Node3D
		if node == null or _hinted.has(node.get_instance_id()) or _flat(node.global_position - global_position) > HINT_RANGE:
			continue
		if node.get("rare") != null or node.get("_fault_piece") != null:
			_hinted[node.get_instance_id()] = true
			var off := global_position - node.global_position
			off.y = 0.0
			_hint_at = node.global_position + (off.normalized() if off.length() > 0.1 else Vector3.BACK) * 1.3
			_hint_look = node.global_position
			_hint_left = HINT_TIME
			_is_fish_hint = false
			return
	for sc in get_tree().get_nodes_in_group("fish_school"):
		var fish: Array = sc.get("fish")
		if fish.is_empty() or _hinted.has(sc.get_instance_id()):
			continue
		var at := (fish[0] as Node3D).global_position
		if _flat(at - global_position) < HINT_RANGE:
			_hinted[sc.get_instance_id()] = true
			_hint_at = _shore(global_position, at)
			_hint_look = at
			_hint_left = HINT_TIME
			_is_fish_hint = true
			return


## A fish landing: Big or Huge, he's delighted.
func _on_node_added(n: Node) -> void:
	if n is LandedFish and not stray:
		(n as LandedFish).landed.connect(func(_at: Vector3) -> void:
			if is_instance_valid(self) and (n as LandedFish).count >= BIG_FISH:
				_pet_left = maxf(_pet_left, 1.2)
				say(&"woof"))


## A wolf far off at night: ears up, a look that way, then one small woof back.
func _on_howl(at: Vector3) -> void:
	if stray or not is_inside_tree():
		return
	_listen = at
	_listen_left = 2.5
	get_tree().create_timer(1.3).timeout.connect(func() -> void:
		if is_instance_valid(self):
			say(&"woof", 0.6))


var _pant_in := 3.0
var _sniff_in := 0.0


## Panting while he trots along with you, sniffs while he's nosing about.
func _idle_sounds(delta: float) -> void:
	if stray or _leaving != Vector3.INF:
		return
	_pant_in -= delta
	_sniff_in -= delta
	if state == State.FOLLOW and _speed > WALK * 1.3 and not _paddling and _pant_in <= 0.0:
		_pant_in = randf_range(PANT_GAP.x, PANT_GAP.y)
		say(&"pant")
	if state == State.SNIFF and _speed < 0.2 and _sniff_in <= 0.0:
		_sniff_in = randf_range(SNIFF_GAP.x, SNIFF_GAP.y)
		say(&"sniff")


## Plays one of his sounds (scripts/dog.gd SOUNDS), positional, from his head.
func say(id: StringName, loud := 1.0) -> void:
	var streams: Array = SOUNDS.get(id, [])
	if streams.is_empty():
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = streams.pick_random()
	p.bus = &"Effects"
	p.unit_size = 4.0
	p.max_distance = 40.0
	p.volume_db = float(SOUND_DB.get(id, -10.0)) + linear_to_db(loud)
	p.pitch_scale = randf_range(0.95, 1.05) * BREED_PITCH.get(breed, 1.0)
	add_child(p)
	p.position = Vector3(0, _leg + 0.3, 0.3)
	p.play()
	p.finished.connect(p.queue_free)


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
	say(&"shake")
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
	elif _face != INF:
		_turn_to(_face, delta, 4.0)
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
			_pose(&"LegFL", -1.45)
			_pose(&"LegFR", -1.45)
			_pose(&"LegBL", -1.25, 0.35)
			_pose(&"LegBR", -1.25, -0.35)
			var breath := sin(_t * (1.6 if _sleeping else 2.6)) * 0.008
			_pose(&"Body", 0.0, 0.0, 0.0, Vector3(0, -_leg * 0.82 + breath, 0))
			if _sleeping:  # chin on his paws
				_pose(&"Head", 0.55, 0.0, 0.0, Vector3(0, -0.07, 0.02))
			else:
				_pose(&"Head", 0.3, 0.0, sin(_t * 0.3) * 0.2, Vector3(0, -0.03, 0))
			_pose(&"Jaw", 0.0)
			if _sleeping:
				wag = sin(_t * 0.8) * 0.05
	if _hint_at != Vector3.INF and _hint_look != Vector3.INF:  # showing you something: wagging, looking at it
		wag = sin(_t * 14.0) * 0.6
		if state == State.SIT:
			_pose(&"Head", 0.15, 0.0, _turn_toward(_hint_look))
	_pose(&"Tail", 0.0, 0.0, wag)
	var ear := sin(_phase * 2.0) * 0.08 * gait
	if _listen_left > 0.0:  # pricked up, listening that way
		ear = -0.35
		_pose(&"Head", -0.25, 0.0, _turn_toward(_listen))
	_pose(&"EarL", ear)
	_pose(&"EarR", -ear if _listen_left <= 0.0 else ear)


## Head yaw toward `at`, within what his neck allows.
func _turn_toward(at: Vector3) -> float:
	var local := to_local(at)
	return clampf(atan2(local.x, local.z), -0.9, 0.9)


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
