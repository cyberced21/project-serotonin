class_name VillagePaths
extends Node3D
## The village's walking network (plans/tavern.md): points round the square and along the lanes to
## each door, linked into a graph. Villagers going anywhere further than a few steps follow the
## shortest chain of points (route()), so they keep to the paths instead of cutting through houses,
## props and the pond. Points are world XZ (Hearthvale's village isn't turned); heights come from
## the ground where they walk. tools/village_layout.gd + tools/plot_village.py draw it from above.

## The points (plans/world-pass.md, the pond green): a ring round the green and its pond, then a
## short lane in to each door; the path from the clearing joins the ring at the north-west, past
## your home.
const POINTS := {
	&"sq_n": Vector2(131.5, 102.7), &"sq_nne": Vector2(140.8, 105.9), &"sq_ne": Vector2(150.1, 115.2),
	&"sq_e": Vector2(153.5, 128.0), &"sq_ese": Vector2(150.1, 140.8), &"sq_se": Vector2(140.8, 150.1),
	&"sq_s": Vector2(128.0, 153.5), &"sq_ssw": Vector2(115.2, 150.1), &"sq_sw": Vector2(105.9, 140.8),
	&"sq_w": Vector2(102.5, 128.0), &"sq_wnw": Vector2(105.9, 115.2), &"sq_nw": Vector2(115.2, 105.9),
	&"th_front": Vector2(128.8, 102.8), &"wc_front": Vector2(109.9, 93.8), &"sm_front": Vector2(161.0, 97.9),
	&"bk_front": Vector2(145.4, 161.0), &"pr_front": Vector2(102.6, 166.2),
	&"nb_front": Vector2(122.4, 102.3),
	# the fisher's hut on the pond's north bank (its dock in front): round to its side door
	&"fi_side": Vector2(124.6, 123.0),
	# the market stall, its counter facing the middle: in front of it, by way of the green
	&"mk_way": Vector2(144.0, 131.0), &"market": Vector2(146.4, 136.3),
	# a footpath across the green east of the pond, north to south (so nobody walks all round)
	&"gr_n": Vector2(134.0, 113.0), &"gr_mid": Vector2(134.0, 124.0), &"gr_s": Vector2(133.0, 141.0),
	# Rosa's terrace, beside the bakery
	&"terrace": Vector2(153.9, 161.3), &"tr_east": Vector2(152.0, 158.2),
	# the tavern (plans/tavern.md): its front, in at its door, the middle of the room
	&"tv_front": Vector2(155.2, 114.5), &"tv_in": Vector2(158.2, 113.2), &"tv_mid": Vector2(161.1, 112.7),
	# out to your home (plans/home.md) along the path from the clearing
	&"path_in": Vector2(104.0, 104.0), &"hm_lane": Vector2(94.0, 101.0), &"hm_front": Vector2(86.4, 107.2),
}
const LINKS := [
	[&"sq_n", &"sq_nne"], [&"sq_nne", &"sq_ne"], [&"sq_ne", &"sq_e"], [&"sq_e", &"sq_ese"],
	[&"sq_ese", &"sq_se"], [&"sq_se", &"sq_s"], [&"sq_s", &"sq_ssw"], [&"sq_ssw", &"sq_sw"],
	[&"sq_sw", &"sq_w"], [&"sq_w", &"sq_wnw"], [&"sq_wnw", &"sq_nw"], [&"sq_nw", &"sq_n"],
	[&"sq_n", &"th_front"], [&"sq_nw", &"wc_front"], [&"sq_ne", &"sm_front"], [&"sq_nne", &"sm_front"], [&"sq_n", &"fi_side"],
	[&"sq_se", &"bk_front"], [&"sq_ssw", &"pr_front"], [&"sq_n", &"nb_front"], [&"sq_nw", &"nb_front"],
	[&"sq_e", &"mk_way"], [&"mk_way", &"market"],
	[&"sq_n", &"gr_n"], [&"sq_nne", &"gr_n"], [&"gr_n", &"gr_mid"], [&"gr_mid", &"gr_s"], [&"gr_mid", &"mk_way"],
	[&"gr_mid", &"fi_side"], [&"gr_s", &"sq_s"], [&"gr_s", &"sq_se"],
	[&"terrace", &"tr_east"], [&"tr_east", &"bk_front"],
	[&"sq_ne", &"tv_front"], [&"tv_front", &"tv_in"], [&"tv_in", &"tv_mid"],
	[&"sq_nw", &"path_in"], [&"path_in", &"hm_lane"], [&"hm_lane", &"hm_front"],
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
