class_name VillageDecor
extends Node3D
## The village's projects in the world (plans/projects.md): the noticeboard in the square, and each
## decoration's props at their set spots once it's done. Spots are offsets from the middle of the
## square (`center`), turned with the village (`angle`). Facings are in the same village frame (a prop's
## front, +Z, toward the square). The spots keep off the lanes to the houses.
## A project paid for just now is built where you can see it (P7): the nearest villager walks
## over and hammers, and each piece pops up out of the ground with a wooden tok, then a cheer.
## (Loading a world, or ticking one in the debug menu, just puts it there.)
## A little life (P4): each new bench has a seat villagers take at dusk (their day, VillagerDay),
## and by day someone now and then draws water at the well.

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
	# the doghouse (plans/dog.md), south of the square facing it: plain, then painted (it takes the
	# plain one's place, his name on the sign), then a porch, a bowl and a blanket in front
	&"kennel": [[&"doghouse", Vector2(-1.0, 13.0), 3.06]],
	&"kennel_paint": [[&"doghouse_painted", Vector2(-1.0, 13.0), 3.06]],
	# the trader's decorations (plans/market.md): baskets on the square's three lamp posts, a
	# weathervane, a painted cart by the market stall
	&"deco_baskets": [[&"flower_basket", Vector2(-5.5, -6.5), 0.7], [&"flower_basket", Vector2(6.5, -5.5), -0.8],
		[&"flower_basket", Vector2(2.0, 7.5), 3.0]],
	&"deco_weathervane": [[&"weathervane", Vector2(-8.0, -6.0), 0.0]],
	&"deco_cart": [[&"painted_cart", Vector2(-11.2, 3.6), 2.2]],
	# Rosa's terrace (plans/tavern.md), against her bakery's south wall, facing the path
	&"terrace": [[&"terrace", Vector2(-13.2, -7.4), 0.0]],
	&"kennel_porch": [[&"doghouse_porch", Vector2(-0.96, 11.95), 3.06], [&"dog_bowl", Vector2(0.4, 11.5), 0.0],
		[&"dog_blanket", Vector2(-1.9, 11.6), 2.6]],
}
## The market stall (plans/market.md): west of the square, its counter facing it.
const MARKET := [Vector2(-11.0, -2.0), 1.57]
## Where your dog sleeps at night (Dog asks kennel_door()): in the doghouse's doorway, facing out.
const KENNEL_DOOR := [Vector2(-0.98, 12.55), 3.06]
## Bunting: strings between the square's three lamp posts (their offsets, as the village has
## them), hung from just under the lamps.
const BUNTING := [[Vector2(-5.5, -6.5), Vector2(6.5, -5.5)], [Vector2(6.5, -5.5), Vector2(2.0, 7.5)],
	[Vector2(2.0, 7.5), Vector2(-5.5, -6.5)]]
const BUNTING_HEIGHT := 2.3
const TOK := preload("res://audio/ui/tok.wav")
## Sounds (audio/projects/SOURCES.md): a hammer on each blow, the well's crank and bucket, the
## fountain's splash, looping, heard close by.
const HAMMERS: Array[AudioStream] = [preload("res://audio/projects/hammer_1.wav"),
	preload("res://audio/projects/hammer_2.wav"), preload("res://audio/projects/hammer_3.wav")]
const WELL_SOUND := preload("res://audio/projects/well.wav")
const FOUNTAIN_SOUND := preload("res://audio/projects/fountain.wav")
const HAMMER_DB := -6.0
const WELL_DB := -10.0
const FOUNTAIN_DB := -14.0
## The builder: a villager within BUILDER_RANGE of the spot walks over and stands this far off
## it; one blow every BLOW seconds, a piece popping in on each, a cheer at the end. Without
## anyone near (or if they don't get there within BUILDER_PATIENCE), the pieces pop in alone.
const BUILDER_RANGE := 60.0
const BUILDER_STAND := 1.6
const BUILDER_PATIENCE := 20.0
const BLOW := 0.55
const POP := 0.3
## The well: a villager within LIFE_RANGE every WELL_GAP seconds [min, max] by day (not from this
## long before sunset, a fraction of the day), cranking for WELL_TIME.
const BENCH_FROM := 0.07
const LIFE_RANGE := 45.0
const WELL_GAP := Vector2(40.0, 90.0)
const WELL_TIME := 4.0

## Middle of the square (world XZ) and how far the village is turned (radians).
var center := HEARTHVALE_CENTER
var angle := 0.0
## Where the footbridge goes: [from, to] (world XZ), or [] for none: where the village path
## crosses the creek (found in _ready).
var footbridge_site: Array = []
var board: Noticeboard
var _built: Dictionary[StringName, Array] = {}  # project -> its props
var _paid: Dictionary[StringName, bool] = {}  # paid for this session: build it in view
var _well_in := 0.0
var _drawing: Villager  # the one at the well now


func _ready() -> void:
	add_to_group("village_decor")
	board = Noticeboard.new()
	board.name = "Noticeboard"
	board.transform = frame(NOTICEBOARD[0], NOTICEBOARD[1])
	add_child(board)
	if footbridge_site.is_empty():
		footbridge_site = _creek_crossing()
	Projects.footbridge_here = not footbridge_site.is_empty()
	Projects.completed.connect(func(id: StringName) -> void: _paid[id] = true)
	Projects.changed.connect(_sync)
	_sync()
	_well_in = randf_range(WELL_GAP.x * 0.3, WELL_GAP.y * 0.5)


func _process(delta: float) -> void:
	for p in _built.get(&"deco_weathervane", []):  # the rooster swings slowly with the wind
		var vane := (p as Node).find_child("Vane", true, false) as Node3D
		if vane:
			var t := Time.get_ticks_msec() / 1000.0
			vane.rotation.y = 0.8 + sin(t * 0.13) * 0.9 + sin(t * 0.47) * 0.25
	_well_life(delta)


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
		_sound(WELL_SOUND, well.global_position + Vector3.UP, WELL_DB)
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
	var best: Villager = null
	var best_d := LIFE_RANGE
	for b in get_tree().get_nodes_in_group("building"):
		for c in b.get_children():
			var v := c as Villager
			if v == null or v == _drawing or v.busy() or v.scripted or v.get("_inside") or v.get("_away") or v.get("_watching"):
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


## Your dog's bed for the night: the kennel's doorway, facing out (+Z), or null with no kennel.
func kennel_door() -> Variant:
	if not _built.has(&"kennel"):
		return null
	var t := frame(KENNEL_DOOR[0], KENNEL_DOOR[1])
	t.origin = _ground(KENNEL_DOOR[0])
	return t


## Puts up what's done and isn't standing yet; takes down what isn't done (the debug menu).
func _sync() -> void:
	for id in PROPS.keys() + [&"bunting", &"footbridge", &"market"]:
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
	# the painted doghouse takes the plain one's place
	for n in _built.get(&"kennel", []):
		(n as Node3D).visible = not _built.has(&"kennel_paint")


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
			_sound(HAMMERS.pick_random(), builder.global_position + Vector3.UP, HAMMER_DB, randf_range(0.94, 1.06))
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
	_sound(TOK, at, 0.0, pitch)


## A one-shot at `at`, gone when it's played.
func _sound(stream: AudioStream, at: Vector3, db: float, pitch := 1.0) -> void:
	var p := AudioStreamPlayer3D.new()
	p.stream = stream
	p.bus = &"SFX"
	p.volume_db = db
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
	if id == &"market":  # the stall, with its keeper (MarketStall)
		var stall := MarketStall.new()
		stall.name = "MarketStall"
		stall.transform = frame(MARKET[0], MARKET[1])
		add_child(stall)
		out.append(stall)
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
		prop.collision_from_mesh = p[0] == &"terrace"  # (you can walk in among the tables)
		add_child(prop)
		out.append(prop)
		if p[0] == &"terrace":
			_terrace_marks(prop)
		if p[0] == &"doghouse_painted":  # his name on the sign
			_name_sign.call_deferred(prop)
		if p[0] == &"bench":  # a seat for the villagers' dusk (Villager._claim_seat)
			var seat := Marker3D.new()
			seat.name = "Bench"
			seat.add_to_group("seat")
			seat.set_meta(&"kind", &"bench")
			prop.add_child(seat)
		if id == &"fountain":  # its splash, close by
			var bed := LoopBed.new()
			bed.stream = FOUNTAIN_SOUND
			bed.bus = &"Ambience"
			bed.positional = true
			bed.unit_size = 3.0
			bed.max_distance = 28.0
			bed.trim_db = FOUNTAIN_DB
			bed.level = 1.0
			prop.add_child(bed)
			bed.position = Vector3.UP * 1.0
	return out


## The terrace's empties as markers villagers walk to: Seat1..4 (seats for breakfast,
## Villager._claim_seat) and Serve, Table1..2 (Rosa's rounds: the "terrace_serve" group).
func _terrace_marks(prop: Node3D) -> void:
	for n in prop.find_children("*", "Node3D", true, false):
		var nm := String(n.name)
		if n is MeshInstance3D or not (nm.begins_with("Seat") or nm.begins_with("Table") or nm == "Serve"):
			continue
		var m := Marker3D.new()
		m.name = nm
		prop.add_child(m)
		m.global_transform = (n as Node3D).global_transform
		if nm.begins_with("Seat"):
			m.add_to_group("seat")
			m.set_meta(&"kind", &"terrace")
		else:
			m.add_to_group("terrace_serve")


## Writes your dog's name on the painted doghouse's sign (the model's SignText marker).
func _name_sign(prop: Node3D) -> void:
	var mark := prop.find_child("SignText", true, false) as Node3D
	if mark == null:
		return
	var label := Label3D.new()
	label.name = "Name"
	label.text = Companion.dog_name
	label.pixel_size = 0.0022
	label.font_size = 48
	label.modulate = Color(0.24, 0.15, 0.08)
	label.outline_size = 0
	label.double_sided = false
	mark.add_child(label)


## Where the village path crosses the creek: [from, to], reaching past its banks each side.
func _creek_crossing() -> Array:
	const REACH := 3.6  # past the channel's middle, each side
	var path := WorldMap.spline(WorldMap.VILLAGE_PATH, false)
	var creek := WorldMap.creek()
	var best := [0, 0]
	var best_d := INF
	for i in path.size():
		for k in creek.size():
			var d := path[i].distance_squared_to(creek[k])
			if d < best_d:
				best_d = d
				best = [i, k]
	var along := (path[mini(best[0] + 1, path.size() - 1)] - path[maxi(best[0] - 1, 0)]).normalized()
	var mid: Vector2 = creek[best[1]]
	return [mid - along * REACH, mid + along * REACH]


func _ground_at(p: Vector2) -> Vector3:
	var terrain := get_tree().get_first_node_in_group("terrain") as Terrain3D
	var h: float = terrain.data.get_height(Vector3(p.x, 0, p.y)) if terrain and terrain.data else NAN
	return Vector3(p.x, 0.0 if is_nan(h) else h, p.y)


func _ground(offset: Vector2) -> Vector3:
	var at := center + offset.rotated(angle)
	var terrain := get_tree().get_first_node_in_group("terrain") as Terrain3D
	var h: float = terrain.data.get_height(Vector3(at.x, 0, at.y)) if terrain and terrain.data else NAN
	return Vector3(at.x, 0.0 if is_nan(h) else h, at.y)
