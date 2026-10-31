class_name VillagePaths
extends Node3D
## The village's walking network (plans/tavern.md): the map editor's walkway lines
## (data/layout/hearthvale.json, type "walkway": plans/map-editor-places.md) linked into a graph.
## Villagers going anywhere further than a few steps follow the shortest chain of points (route()),
## so they keep to the paths instead of cutting through houses, props and the pond. Lines join
## where a corner of one lands on (or next to) another; a building's door that no walkway comes
## near is linked to the nearest one, so a moved building still has a way in. Heights come from
## the ground where they walk. tools/village_layout.gd + tools/plot_village.py draw it from above.

## Corners closer than this are one point; a line's end this close to another line joins it there.
const JOIN := 0.75
## A door with a network point this close is reached already (its own short lane in); else the
## nearest walkway gets a point where it passes closest, for the last step in.
const DOOR_REACH := 4.0
## Somewhere closer than this is walked to straight, when nothing's in the way.
const DIRECT := 8.0
## How wide a villager is, and how high the check for things in the way runs (above the ground,
## clear of its little bumps).
const CLEARANCE := 0.3
const CHECK_HEIGHT := 0.7
const WORLD_LAYER := 1

var _astar := AStar2D.new()
var _names: Array[StringName] = []
var _terrain: Terrain3D


var _ring: PackedVector2Array  # the walkway villagers stroll round the green by (its "stroll" line)


func _ready() -> void:
	add_to_group("village_paths")
	var walks := walkways()
	for l in walks:
		if l.get("stroll", false):
			_ring = _pts(l)
	var doors := PackedVector2Array()
	for b in get_tree().get_nodes_in_group("building"):
		var door := b.call("spot", "Door") as Node3D if b.has_method("spot") else null
		if door:
			doors.append(_flat(door.global_position))
	var g := graph(walks, doors)
	var pts: PackedVector2Array = g["points"]
	for i in pts.size():
		_astar.add_point(i, pts[i])
		_names.append(StringName("w%d" % i))
	for l in g["links"]:
		_astar.connect_points(l[0], l[1])


## The layout's walkway lines (from `path`, else the file LayoutAnchors reads).
static func walkways(path := "") -> Array:
	if path == "":
		path = LayoutAnchors.layout_path
	var layout: Variant = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
	var out := []
	if layout is Dictionary:
		for l in layout.get("lines", []):
			if l.get("type", "") == "walkway" and l.get("points", []).size() >= 2:
				out.append(l)
	return out


## The network from walkway `lines` and the `doors` it must reach: {points: PackedVector2Array,
## links: [[i, j], ...]}. Corners within JOIN are one point; an end of a line within JOIN of another
## line's leg splits that leg there; a door with no point within DOOR_REACH gets one on the nearest
## leg, where it passes closest (the step from there onto the door isn't part of the network, as
## for every door).
static func graph(lines: Array, doors: PackedVector2Array) -> Dictionary:
	var pts: Array[Vector2] = []  # (an Array: the lambdas below add to it, and they'd copy a packed one)
	var links := {}  # Vector2i(lo, hi) -> true
	var ends: Array[int] = []
	var at := func(p: Vector2) -> int:
		for i in pts.size():
			if pts[i].distance_to(p) < JOIN:
				return i
		pts.append(p)
		return pts.size() - 1
	var link := func(a: int, b: int) -> void:
		if a != b:
			links[Vector2i(mini(a, b), maxi(a, b))] = true
	for l in lines:
		var line := _pts(l)
		var prev: int = at.call(line[0])
		ends.append(prev)
		for k in range(1, line.size()):
			var here: int = at.call(line[k])
			link.call(prev, here)
			prev = here
		ends.append(prev)
	# ends landing on another line's leg (a T): split the leg there
	for e in ends:
		var best := _nearest_leg(pts, links, pts[e], [e])
		if not best.is_empty() and float(best["d"]) < JOIN:
			_split(pts, links, best, e)
	for door in doors:
		var near := false
		for p in pts:
			if p.distance_to(door) < DOOR_REACH:
				near = true
				break
		if near or links.is_empty():
			continue
		var best := _nearest_leg(pts, links, door, [])
		var spot := pts.size()
		pts.append(best["at"])
		_split(pts, links, best, spot)
	var out := []
	for k: Vector2i in links:
		out.append([k.x, k.y])
	return {"points": PackedVector2Array(pts), "links": out}


## The leg (a link) nearest `p`, leaving out legs touching `skip`: {leg: Vector2i, at: the spot on it, d: how far}.
static func _nearest_leg(pts: Array[Vector2], links: Dictionary, p: Vector2, skip: Array) -> Dictionary:
	var best := {}
	for k: Vector2i in links:
		if k.x in skip or k.y in skip:
			continue
		var q := Geometry2D.get_closest_point_to_segment(p, pts[k.x], pts[k.y])
		var d := q.distance_to(p)
		if best.is_empty() or d < float(best["d"]):
			best = {"leg": k, "at": q, "d": d}
	return best


## Splits leg `best` at point `i` (which joins it): a-i-b instead of a-b, or i linked to the leg's
## end when the spot is right at one.
static func _split(pts: Array[Vector2], links: Dictionary, best: Dictionary, i: int) -> void:
	var k: Vector2i = best["leg"]
	var q: Vector2 = best["at"]
	for e in [k.x, k.y]:
		if pts[e].distance_to(q) < JOIN:
			links[Vector2i(mini(e, i), maxi(e, i))] = true
			return
	links.erase(k)
	for e in [k.x, k.y]:
		links[Vector2i(mini(e, i), maxi(e, i))] = true


static func _pts(l: Dictionary) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in l.get("points", []):
		out.append(Vector2(float(p[0]), float(p[1])))
	return out


## The stroll round the green (the walkway marked "stroll"), its corners on the ground.
func ring() -> PackedVector3Array:
	var out := PackedVector3Array()
	var n := _ring.size()
	if n > 1 and _ring[0].distance_to(_ring[n - 1]) < JOIN:
		n -= 1  # (closed: its last corner is its first)
	for i in n:
		out.append(Vector3(_ring[i].x, _height(Vector3(_ring[i].x, 0.0, _ring[i].y)), _ring[i].y))
	return out


## Where to walk, in order, to get from `from` to `to` (world positions): the network's points on
## the way, then `to` itself. Straight there when it's close and nothing's in the way. Needs the
## physics space (call it on a physics tick).
func route(from: Vector3, to: Vector3) -> PackedVector3Array:
	var out := PackedVector3Array()
	if _flat(from).distance_to(_flat(to)) < DIRECT and is_clear(from, to):
		out.append(to)
		return out
	var a := _entry(from)
	var b := _entry(to)
	var ids := _astar.get_id_path(a, b)
	# no doubling back: skip the first point if the second can be walked to straight, and the
	# last if the place itself can be seen from the one before
	if ids.size() >= 2 and is_clear(from, point(ids[1])):
		ids.remove_at(0)
	if ids.size() >= 2 and is_clear(point(ids[ids.size() - 2]), to):
		ids.remove_at(ids.size() - 1)
	for id in ids:
		out.append(point(id))
	out.append(to)
	return out


## A network point on the ground.
func point(id: int) -> Vector3:
	var p := _astar.get_point_position(id)
	return Vector3(p.x, _height(Vector3(p.x, 0.0, p.y)), p.y)


## The point called `n`, on the ground.
func named(n: StringName) -> Vector3:
	return point(_names.find(n))


## True when a villager could walk straight from `a` to `b` without bumping into anything
## (buildings and props: the world layer).
func is_clear(a: Vector3, b: Vector3) -> bool:
	var space := get_world_3d().direct_space_state
	var from := Vector3(a.x, _height(a) + CHECK_HEIGHT, a.z)
	var to := Vector3(b.x, _height(b) + CHECK_HEIGHT, b.z)
	if from.distance_to(to) < 0.01:
		return true
	var q := PhysicsShapeQueryParameters3D.new()
	var ball := SphereShape3D.new()
	ball.radius = CLEARANCE
	q.shape = ball
	q.transform = Transform3D(Basis.IDENTITY, from)
	q.motion = to - from
	q.collision_mask = WORLD_LAYER
	q.exclude = _terrain_rids()
	var hit := space.cast_motion(q)
	return hit[0] >= 1.0


## Everything as plain data, for tools/village_layout.gd.
func dump() -> Dictionary:
	var pts := {}
	var links := []
	for id in _names.size():
		var p := _astar.get_point_position(id)
		pts[String(_names[id])] = [p.x, p.y]
		for other in _astar.get_point_connections(id):
			if other > id:
				links.append([String(_names[id]), String(_names[other])])
	return {"points": pts, "links": links}


## The network point to start from (or finish at) for `p`: the nearest one it can walk to
## straight, else simply the nearest.
func _entry(p: Vector3) -> int:
	var order: Array[int] = []
	for id in _names.size():
		order.append(id)
	var here := _flat(p)
	order.sort_custom(func(x: int, y: int) -> bool:
		return _astar.get_point_position(x).distance_squared_to(here) < _astar.get_point_position(y).distance_squared_to(here))
	for id in order.slice(0, 4):
		if is_clear(p, point(id)):
			return id
	return order[0]


func _flat(p: Vector3) -> Vector2:
	return Vector2(p.x, p.z)


func _height(p: Vector3) -> float:
	if _terrain == null:
		_terrain = get_tree().get_first_node_in_group("terrain") as Terrain3D
	if _terrain and _terrain.data:
		var h: float = _terrain.data.get_height(p)
		if not is_nan(h):
			return h
	return p.y


func _terrain_rids() -> Array[RID]:
	var out: Array[RID] = []
	if _terrain == null:
		_terrain = get_tree().get_first_node_in_group("terrain") as Terrain3D
	if _terrain and _terrain.collision and _terrain.collision.has_method("get_rid"):
		var rid: RID = _terrain.collision.call("get_rid")
		if rid.is_valid():
			out.append(rid)
	return out
