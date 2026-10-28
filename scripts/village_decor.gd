class_name VillageDecor
extends Node3D
## The village's projects in the world (plans/projects.md): the noticeboard in the square, and each
## decoration's props at their set spots once it's done. Spots are offsets from the middle of the
## square (`center`), turned with the village (`angle`, as a generated village is), so Hearthvale
## and every generated village share one layout. Facings are in the same village frame (a prop's
## front, +Z, toward the square). The spots keep off the lanes to the houses.
## A project paid for just now is built where you can see it (P7): the nearest villager walks
## over and hammers, and each piece pops up out of the ground with a wooden tok, then a cheer.
## (Loading a world, or ticking one in the debug menu, just puts it there.)
## A little life (P4): at dusk villagers come and sit on the new benches until it's dark, and by
## day someone now and then draws water at the well.

signal built(id: StringName, props: Array[Node3D])
## A bucket going down the well (for its sound): where.
signal water_drawn(at: Vector3)

## The noticeboard: [offset, facing].
const NOTICEBOARD := [Vector2(9.0, -8.0), -0.84]
## Hearthvale's square (its village isn't turned).
const HEARTHVALE_CENTER := Vector2(100, 40)
## Each decoration's props: [model (models/village/props/<name>.glb), offset, facing].
const PROPS := {
	&"benches": [[&"bench", Vector2(4.0, -6.8), -0.53], [&"bench", Vector2(7.0, 4.0), -2.09]],
	&"flower_boxes": [[&"planter", Vector2(-7.2, 0.3), 1.57], [&"planter", Vector2(-4.5, -7.5), 0.55],
		[&"planter", Vector2(8.6, 3.4), -1.2], [&"planter", Vector2(-3.5, 7.6), 2.7]],
	&"well": [[&"well", Vector2(-4.2, 1.8), 0.9]],
	&"fountain": [[&"fountain", Vector2(0.0, 0.0), 0.0]],
}
## Bunting: strings between the square's three lamp posts (their offsets, as the village has
## them), hung from just under the lamps.
const BUNTING := [[Vector2(-5.5, -6.5), Vector2(6.5, -5.5)], [Vector2(6.5, -5.5), Vector2(2.0, 7.5)],
	[Vector2(2.0, 7.5), Vector2(-5.5, -6.5)]]
const BUNTING_HEIGHT := 2.3
const TOK := preload("res://audio/ui/tok.wav")
## The builder: a villager within BUILDER_RANGE of the spot walks over and stands this far off
## it; one blow every BLOW seconds, a piece popping in on each, a cheer at the end. Without
## anyone near (or if they don't get there within BUILDER_PATIENCE), the pieces pop in alone.
const BUILDER_RANGE := 60.0
const BUILDER_STAND := 1.6
const BUILDER_PATIENCE := 20.0
const BLOW := 0.55
const POP := 0.3
## Dusk on the benches: from this long before sunset (a fraction of the day) until dark, a
## villager within LIFE_RANGE comes to sit on each. The well: someone every WELL_GAP seconds
## [min, max] by day, cranking for WELL_TIME.
const BENCH_FROM := 0.07
const LIFE_RANGE := 45.0
const WELL_GAP := Vector2(40.0, 90.0)
const WELL_TIME := 4.0

## Middle of the square (world XZ) and how far the village is turned (radians).
var center := HEARTHVALE_CENTER
var angle := 0.0
## Where the footbridge goes: [from, to] (world XZ), or [] for none. Hearthvale's spans the gully's
## open gap (found in _ready); a generated world passes its ford (Footbridge.find_ford).
var footbridge_site: Array = []
var hearthvale := true
var board: Noticeboard
var _built: Dictionary[StringName, Array] = {}  # project -> its props
var _paid: Dictionary[StringName, bool] = {}  # paid for this session: build it in view
var _sitters: Dictionary = {}  # bench prop -> [villager, its Bench marker]
var _well_in := 0.0
var _drawing: Villager  # the one at the well now


func _ready() -> void:
	add_to_group("village_decor")
	board = Noticeboard.new()
	board.name = "Noticeboard"
	board.transform = frame(NOTICEBOARD[0], NOTICEBOARD[1])
	add_child(board)
	if hearthvale and footbridge_site.is_empty():
		footbridge_site = _gully_gap()
	Projects.footbridge_here = not footbridge_site.is_empty()
	Projects.completed.connect(func(id: StringName) -> void: _paid[id] = true)
	Projects.changed.connect(_sync)
	_sync()
	_well_in = randf_range(WELL_GAP.x * 0.3, WELL_GAP.y * 0.5)


func _process(delta: float) -> void:
	_bench_life()
	_well_life(delta)


## At dusk, someone comes to sit on each new bench; they stay till dark, then go home.
func _bench_life() -> void:
	var t := DayNight.time
	var dusk := t > DayNight.SUNSET - BENCH_FROM and not DayNight.is_night()
	for bench in _sitters.keys():
		var v: Villager = _sitters[bench][0]
		var mark: Marker3D = _sitters[bench][1]
		var left: bool = not is_instance_valid(v) or not is_instance_valid(bench) or v.get("_target") != mark
		if not dusk or left:
			_release(v, mark)
			_sitters.erase(bench)
		elif v.state == Villager.State.IDLE:
			v.set("_timer", 5.0)  # sat down: stay
	if not dusk:
		return
	for bench in props_of(&"benches"):
		if _sitters.has(bench) or not (bench as Node3D).visible:
			continue
		var v := _free_villager((bench as Node3D).global_position)
		if v == null:
			return
		var mark := Marker3D.new()
		mark.name = "Bench"  # (the name a villager sits down at: one per bench, so on the bench)
		(bench as Node3D).add_child(mark)
		_sitters[bench] = [v, mark]
		v.call("_walk_to", mark)


## Now and then by day, someone walks to the well and draws a bucket.
func _well_life(delta: float) -> void:
	var wells := props_of(&"well")
	if wells.is_empty() or _drawing:
		return
	_well_in -= delta
	if _well_in > 0.0:
		return
	_well_in = randf_range(WELL_GAP.x, WELL_GAP.y)
	if DayNight.is_night() or DayNight.time > DayNight.SUNSET - BENCH_FROM:
		return
	var well := wells[0] as Node3D
	var v := _free_villager(well.global_position)
	if v:
		_draw_water(v, well)


func _draw_water(v: Villager, well: Node3D) -> void:
	_drawing = v
	var mark := Marker3D.new()
	mark.name = "Well"
	add_child(mark)
	mark.global_position = well.global_position + well.global_basis.x * 1.05  # by the crank
	mark.global_basis = Basis(Vector3.UP, well.global_rotation.y - PI / 2.0)
	v.set("_watching", true)  # busy
	v.call("_walk_to", mark)
	var waited := 0.0
	while is_instance_valid(v) and waited < BUILDER_PATIENCE and _flat_gap(v, mark) > 0.3:
		if v.state != Villager.State.WALK:
			v.call("_walk_to", mark)
		waited += get_process_delta_time()
		await get_tree().process_frame
	if is_instance_valid(v) and waited < BUILDER_PATIENCE:
		v.scripted = true
		v.script_place(v.global_position, well.global_position)
		water_drawn.emit(well.global_position)
		var turns := int(WELL_TIME / 0.8)
		for i in turns:  # cranking: both hands on the handle, round and round
			v.script_pose(&"ArmR", -1.5, 0.1, Vector3(0, 0.08, 0))
			v.script_pose(&"ArmL", -1.1, -0.1)
			await get_tree().create_timer(0.4).timeout
			v.script_pose(&"ArmR", -0.9, 0.1, Vector3(0, -0.04, 0))
			v.script_pose(&"ArmL", -0.9, -0.1)
			await get_tree().create_timer(0.4).timeout
		v.scripted = false
	if is_instance_valid(v):
		v.set("_watching", false)
	_release(v, mark)
	_drawing = null


## Frees `mark`, first sending `v` about its day if it was going there (or standing on it).
func _release(v: Villager, mark: Marker3D, idle := true) -> void:
	if is_instance_valid(v) and v.get("_target") == mark:
		v.set("_target", null)
		if idle and not v.scripted:
			v.call("_enter", Villager.State.IDLE)
			v.set("_timer", 0.0)  # off back to work
	if is_instance_valid(mark):
		mark.queue_free()


## A villager out of doors near `at` with nothing else on (not building, sitting, drawing water).
func _free_villager(at: Vector3) -> Villager:
	var busy: Array = [_drawing]
	for s in _sitters.values():
		busy.append(s[0])
	var best: Villager = null
	var best_d := LIFE_RANGE
	for b in get_tree().get_nodes_in_group("building"):
		for c in b.get_children():
			var v := c as Villager
			if v == null or v in busy or v.scripted or v.get("_inside") or v.get("_away") or v.get("_watching"):
				continue
			var d := v.global_position.distance_to(at)
			if d < best_d:
				best_d = d
				best = v
	return best


## The props of project `id` standing now (empty if it isn't done or has none here).
func props_of(id: StringName) -> Array:
	return _built.get(id, [])


## A transform at village offset `offset`, facing `facing` (village frame), on the ground below
## (a Prop with snap_to_ground settles it).
func frame(offset: Vector2, facing: float) -> Transform3D:
	var at := center + offset.rotated(angle)
	return Transform3D(Basis(Vector3.UP, facing - angle), Vector3(at.x, 0.0, at.y))


## Puts up what's done and isn't standing yet; takes down what isn't done (the debug menu).
func _sync() -> void:
	for id in PROPS.keys() + [&"bunting", &"footbridge"]:
		var done := Projects.is_done(id)
		if done and not _built.has(id):
			var made: Array[Node3D] = _make(id)
			_built[id] = made
			built.emit(id, made)
			if _paid.has(id):
				_paid.erase(id)
				_build_in_view(made)
		elif not done and _built.has(id):
			for n in _built[id]:
				(n as Node).queue_free()
			_built.erase(id)


## Hides the pieces, fetches a builder, and pops them in on the blows.
func _build_in_view(pieces: Array[Node3D]) -> void:
	var homes: Array[Vector3] = []
	for p in pieces:
		homes.append(p.scale)
		p.scale = Vector3.ONE * 0.01
		p.visible = false
	var spot := pieces[0].global_position
	var builder := _nearest_villager(spot)
	if builder:
		var mark := Marker3D.new()
		add_child(mark)
		mark.top_level = true
		var away := Vector2(builder.global_position.x - spot.x, builder.global_position.z - spot.z)
		var dir := away.normalized() if away.length() > 0.1 else Vector2(0, 1)
		mark.global_position = spot + Vector3(dir.x, 0.0, dir.y) * BUILDER_STAND
		builder.set("_hurry", 1.6)
		builder.set("_watching", true)  # busy: no stopping to chat on the way (cheer() clears it)
		builder.call("_walk_to", mark)
		var waited := 0.0
		while is_instance_valid(builder) and waited < BUILDER_PATIENCE and _flat_gap(builder, mark) > 0.4:
			if builder.state != Villager.State.WALK and builder.state != Villager.State.CHEER:
				builder.call("_walk_to", mark)  # (talking to you, or it finished a walk elsewhere)
			waited += get_process_delta_time()
			await get_tree().process_frame
		_release(builder, mark, false)
		if is_instance_valid(builder):
			builder.set("_hurry", 1.0)
			builder.scripted = true
			builder.script_place(builder.global_position, spot)
	for i in pieces.size():
		if is_instance_valid(builder) and builder.scripted:
			builder.script_pose(&"ArmR", -2.3, 0.05)  # raise...
			await get_tree().create_timer(BLOW * 0.55).timeout
			builder.script_pose(&"ArmR", -0.6, 0.05)  # ...and down
			await get_tree().create_timer(BLOW * 0.15).timeout
		else:
			await get_tree().create_timer(BLOW * 0.7).timeout
		var p := pieces[i]
		if not is_instance_valid(p):
			continue
		p.visible = true
		var t := create_tween()
		t.tween_property(p, "scale", homes[i], POP).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		_tok(p.global_position, 1.0 + 0.08 * i)
		await get_tree().create_timer(BLOW * 0.3).timeout
	if is_instance_valid(builder) and builder.scripted:
		builder.scripted = false
		builder.cheer()


static func _flat_gap(a: Node3D, b: Node3D) -> float:
	return Vector2(a.global_position.x - b.global_position.x, a.global_position.z - b.global_position.z).length()


func _nearest_villager(at: Vector3) -> Villager:
	var best: Villager = null
	var best_d := BUILDER_RANGE
	for b in get_tree().get_nodes_in_group("building"):
		for c in b.get_children():
			var v := c as Villager
			if v == null or v.scripted or v.get("_inside") or v.get("_away"):
				continue
			var d := v.global_position.distance_to(at)
			if d < best_d:
				best_d = d
				best = v
	return best


func _tok(at: Vector3, pitch: float) -> void:
	var p := AudioStreamPlayer3D.new()
	p.stream = TOK
	p.bus = &"SFX"
	p.pitch_scale = pitch
	p.unit_size = 6.0
	p.max_distance = 50.0
	add_child(p)
	p.global_position = at
	p.finished.connect(p.queue_free)
	p.play()


func _make(id: StringName) -> Array[Node3D]:
	var out: Array[Node3D] = []
	if id == &"footbridge":
		if footbridge_site.is_empty():
			return out
		var bridge := Footbridge.new()
		bridge.name = "Footbridge"
		bridge.from = _ground_at(footbridge_site[0])
		bridge.to = _ground_at(footbridge_site[1])
		add_child(bridge)
		out.append(bridge)
		return out
	if id == &"bunting":
		for pair in BUNTING:
			var b := Bunting.new()
			b.from = _ground(pair[0]) + Vector3.UP * BUNTING_HEIGHT
			b.to = _ground(pair[1]) + Vector3.UP * BUNTING_HEIGHT
			add_child(b)
			out.append(b)
		return out
	for p in PROPS[id]:
		var prop := Prop.new()
		prop.model = load("res://models/village/props/%s.glb" % p[0])
		prop.snap_to_ground = true
		prop.name = "%s_%d" % [p[0], out.size()]
		prop.transform = frame(p[1], p[2])
		add_child(prop)
		out.append(prop)
	return out


## Hearthvale's gully: the half of the ring road with no earth under it, GAP m along the road
## (tools/generate_test_terrain.gd _gully: the earth bridge is on the road's left).
func _gully_gap() -> Array:
	const GAP := 6.0
	var ring := WorldMap.ring()
	var at := 0
	for i in ring.size():
		if ring[i].distance_squared_to(WorldMap.GULLY_NEAR) < ring[at].distance_squared_to(WorldMap.GULLY_NEAR):
			at = i
	var along := (ring[(at + 1) % ring.size()] - ring[at]).normalized()
	var left := Vector2(-along.y, along.x)
	var mid := ring[at] - left * WorldMap.ROAD_HALF_WIDTH * 0.5
	return [mid - along * (GAP * 0.5 + 1.5), mid + along * (GAP * 0.5 + 1.5)]


func _ground_at(p: Vector2) -> Vector3:
	var terrain := get_tree().get_first_node_in_group("terrain") as Terrain3D
	var h: float = terrain.data.get_height(Vector3(p.x, 0, p.y)) if terrain and terrain.data else NAN
	return Vector3(p.x, 0.0 if is_nan(h) else h, p.y)


func _ground(offset: Vector2) -> Vector3:
	var at := center + offset.rotated(angle)
	var terrain := get_tree().get_first_node_in_group("terrain") as Terrain3D
	var h: float = terrain.data.get_height(Vector3(at.x, 0, at.y)) if terrain and terrain.data else NAN
	return Vector3(at.x, 0.0 if is_nan(h) else h, at.y)
