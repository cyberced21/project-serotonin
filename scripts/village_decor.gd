class_name VillageDecor
extends Node3D
## The village's projects in the world (plans/projects.md): the noticeboard in the square, and each
## decoration's props at their set spots once it's done. Spots are offsets from the middle of the
## square (`center`), turned with the village (`angle`, as a generated village is), so Hearthvale
## and every generated village share one layout. Facings are in the same village frame (a prop's
## front, +Z, toward the square). The spots keep off the lanes to the houses.

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

## Middle of the square (world XZ) and how far the village is turned (radians).
var center := HEARTHVALE_CENTER
var angle := 0.0
var board: Noticeboard
var _built: Dictionary[StringName, Array] = {}  # project -> its props


func _ready() -> void:
	add_to_group("village_decor")
	board = Noticeboard.new()
	board.name = "Noticeboard"
	board.transform = frame(NOTICEBOARD[0], NOTICEBOARD[1])
	add_child(board)
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
		elif not done and _built.has(id):
			for n in _built[id]:
				(n as Node).queue_free()
			_built.erase(id)


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
