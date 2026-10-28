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

signal built(id: StringName, props: Array[Node3D])

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

## Middle of the square (world XZ) and how far the village is turned (radians).
var center := HEARTHVALE_CENTER
var angle := 0.0
var board: Noticeboard
var _built: Dictionary[StringName, Array] = {}  # project -> its props
var _paid: Dictionary[StringName, bool] = {}  # paid for this session: build it in view


func _ready() -> void:
	add_to_group("village_decor")
	board = Noticeboard.new()
	board.name = "Noticeboard"
	board.transform = frame(NOTICEBOARD[0], NOTICEBOARD[1])
	add_child(board)
	Projects.completed.connect(func(id: StringName) -> void: _paid[id] = true)
	Projects.changed.connect(_sync)
	_sync()


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
	for id in PROPS.keys() + [&"bunting"]:
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
		mark.queue_free()
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


func _ground(offset: Vector2) -> Vector3:
	var at := center + offset.rotated(angle)
	var terrain := get_tree().get_first_node_in_group("terrain") as Terrain3D
	var h: float = terrain.data.get_height(Vector3(at.x, 0, at.y)) if terrain and terrain.data else NAN
	return Vector3(at.x, 0.0 if is_nan(h) else h, at.y)
