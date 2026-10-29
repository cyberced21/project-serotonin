class_name VillagePaths
extends Node3D
## The village's walking network (plans/tavern.md): points round the square and along the lanes to
## each door, linked into a graph. Villagers going anywhere further than a few steps follow the
## shortest chain of points (route()), so they keep to the paths instead of cutting through houses,
## props and the pond. Points are world XZ (Hearthvale's village isn't turned); heights come from
## the ground where they walk. tools/village_layout.gd + tools/plot_village.py draw it from above.

## The points. Round the square at about 4.6 m (clear of the fountain, the well and the benches),
## then out along each lane.
const POINTS := {
	&"sq_n": Vector2(100.0, 35.2), &"sq_ne": Vector2(103.6, 36.6), &"sq_e": Vector2(104.8, 40.5),
	&"sq_se": Vector2(103.4, 43.8), &"sq_s": Vector2(100.0, 45.0), &"sq_sw": Vector2(97.8, 44.2),
	&"sq_nw": Vector2(96.6, 36.4),
	# west, through the gap between the benches where the path from the clearing comes in
	&"w_gap": Vector2(93.3, 38.85), &"market": Vector2(90.8, 38.6),
	&"th_door": Vector2(107.6, 40.8),
	&"wc_lane": Vector2(98.8, 32.0),
	&"bk_bend": Vector2(93.2, 35.0), &"bk_lane": Vector2(92.6, 31.2), &"bk_front": Vector2(90.6, 27.4),
	&"fi_lane": Vector2(94.2, 47.2), &"fi_side": Vector2(92.8, 52.0), &"fi_corner": Vector2(92.6, 57.0),
	&"sm_lane": Vector2(105.4, 48.6), &"sm_front": Vector2(107.0, 52.8),
	&"pr_lane": Vector2(102.4, 51.8), &"pr_front": Vector2(104.8, 57.4),
	&"nb_front": Vector2(108.0, 35.4),
	# Rosa's terrace, in front of it and round toward the lane to the bakery
	&"terrace": Vector2(87.4, 34.4), &"tr_east": Vector2(91.0, 34.2),
	# the tavern (plans/tavern.md): across from the benches, in at its door, the middle of the room
	&"tv_east": Vector2(91.4, 45.6), &"tv_front": Vector2(85.6, 46.0), &"tv_in": Vector2(83.6, 46.0),
	&"tv_mid": Vector2(80.8, 45.2),
	# out to your home on the west rim (plans/home.md): between the terrace and the tavern, round
	# the north of the tavern, along your home's north side, to its front (it faces west)
	&"hm_east": Vector2(80.0, 38.6), &"hm_bend": Vector2(74.0, 37.0), &"hm_north": Vector2(64.0, 36.0), &"hm_front": Vector2(55.5, 40.0),
}
const LINKS := [
	[&"sq_n", &"sq_ne"], [&"sq_ne", &"sq_e"], [&"sq_e", &"sq_se"], [&"sq_se", &"sq_s"],
	[&"sq_s", &"sq_sw"], [&"sq_sw", &"sq_nw"], [&"sq_nw", &"sq_n"],
	[&"sq_nw", &"w_gap"], [&"w_gap", &"market"],
	[&"sq_e", &"th_door"],
	[&"sq_n", &"wc_lane"],
	[&"sq_nw", &"bk_bend"], [&"bk_bend", &"bk_lane"], [&"bk_lane", &"bk_front"],
	[&"sq_sw", &"fi_lane"], [&"fi_lane", &"fi_side"], [&"fi_side", &"fi_corner"],
	[&"sq_se", &"sm_lane"], [&"sm_lane", &"sm_front"],
	[&"sq_s", &"pr_lane"], [&"pr_lane", &"pr_front"],
	[&"sq_ne", &"nb_front"],
	[&"sq_sw", &"tv_east"], [&"fi_lane", &"tv_east"], [&"tv_east", &"tv_front"], [&"tv_front", &"tv_in"],
	[&"tv_in", &"tv_mid"], [&"tv_front", &"terrace"],
	[&"terrace", &"tr_east"], [&"tr_east", &"bk_bend"], [&"tr_east", &"bk_lane"],
	[&"terrace", &"hm_east"], [&"hm_east", &"hm_bend"], [&"hm_bend", &"hm_north"], [&"hm_north", &"hm_front"],
]
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


func _ready() -> void:
	add_to_group("village_paths")
	for n: StringName in POINTS:
		_astar.add_point(_names.size(), POINTS[n])
		_names.append(n)
	for l in LINKS:
		_astar.connect_points(_names.find(l[0]), _names.find(l[1]))


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
	for n in _names:
		pts[String(n)] = [POINTS[n].x, POINTS[n].y]
	var links := []
	for l in LINKS:
		links.append([String(l[0]), String(l[1])])
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
