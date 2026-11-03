class_name CartLine
extends Node3D
## The carter's cart (plans/road-travel.md): once the cart shed's project is done, there's a stop
## (CartStop) at the cart shed and at each end of a packed or cobbled road you've been to. Ring at
## one, pick where to (CartPanel), and the cart rolls up from round the bend, you climb on and it
## takes you along the better roads (their laid lines, joined where they meet) to that stop, at up
## to RIDE_SPEED: you sit on its seat, free to look round, and moving hops you off on the way.
## It only runs on roads at level 1 or more (Roads), so better roads grow its network. Free to ride.
## (A stand-in cart for now: the hay cart, no pony yet.)

const CART := preload("res://models/field/cart.glb")
## Fastest it goes (m/s, ~3x your jog), how quickly it gets there and slows, and how it comes up to
## the stop you rang at: from this far back along the road, at this pace.
const RIDE_SPEED := 16.0
const ACCEL := 3.0
const ARRIVE_FROM := 28.0
const ARRIVE_SPEED := 5.0
## Waiting at the stop this long for you to get on (s), then it goes.
const WAIT := 20.0
## The network: a point every STEP m along each road; points of two roads this close are joined;
## the cart shed's stop joins the nearest road point within SHED_REACH; stops this close are one.
const STEP := 3
const JOIN := 5.0
const SHED_REACH := 90.0
const SAME_STOP := 30.0
## A road end's stop is named after the area or place nearest it, within this (m); in the
## village (this near its green), after the village and which side of it.
const NAME_REACH := 120.0
const IN_VILLAGE := 95.0
const PLACE_NAMES := {&"watermill": "The watermill", &"orchard": "The orchard", &"shepherds_hill": "Shepherd's hill", &"haven": "The haven"}

## The stops: id -> {name, at (Vector2), point (on the network)}.
var stops := {}
var _astar := AStar2D.new()
var _stop_nodes: Array[CartStop] = []
var _cart: Node3D
var _seat: Marker3D
var _path := PackedVector2Array()
var _along := PackedFloat32Array()  # distance along the path at each of its points
var _s := 0.0  # how far along it the cart is
var _speed := 0.0
var _phase := &""  # &"coming", &"waiting", &"riding", &"leaving"
var _wait := 0.0
var _to: StringName


func _ready() -> void:
	add_to_group("cart_line")
	process_physics_priority = -10  # (moved before the player, who sits on it, follows)
	Projects.changed.connect(_rebuild.call_deferred)
	_rebuild.call_deferred()


func riding() -> bool:
	return _cart != null


## The network and the stops afresh (the cart shed's project, a road built, an end reached).
func _rebuild() -> void:
	if riding():
		return
	for s in _stop_nodes:
		s.queue_free()
	_stop_nodes.clear()
	stops.clear()
	_astar.clear()
	if not Projects.is_done(&"carter"):
		return
	var ends: Array = []  # [road id, end, point id]
	var next := 0
	var by_road := {}
	for r in WorldMap.roads():
		if Roads.level_of(r["id"]) < 1:
			continue
		var pts: PackedVector2Array = r["pts"]
		if pts.size() < 2:
			continue
		var ids: Array[int] = []
		for k in range(0, pts.size(), STEP) + ([pts.size() - 1] if (pts.size() - 1) % STEP != 0 else []):
			_astar.add_point(next, pts[k])
			if not ids.is_empty():
				_astar.connect_points(ids[-1], next)
			ids.append(next)
			next += 1
		by_road[r["id"]] = ids
		ends.append([r, 0, ids[0]])
		ends.append([r, 1, ids[-1]])
	var keys := by_road.keys()
	for a in keys.size():  # where two roads meet
		for b in range(a + 1, keys.size()):
			for i in by_road[keys[a]]:
				for j in by_road[keys[b]]:
					if _astar.get_point_position(i).distance_to(_astar.get_point_position(j)) < JOIN:
						_astar.connect_points(i, j)
	if _astar.get_point_count() == 0:
		return
	var shed := LayoutAnchors.find(&"cart_shed")
	if not shed.is_empty() and shed.get("placed", true):
		var at := Vector2(float(shed["at"][0]), float(shed["at"][1]))
		var near := _astar.get_closest_point(at)
		if _astar.get_point_position(near).distance_to(at) < SHED_REACH:
			_add_stop(&"shed", "The cart shed", _astar.get_point_position(near).lerp(at, 0.35), near)
	for e in ends:
		if Roads.has_reached(e[0]["id"], e[1]):
			var at := _astar.get_point_position(e[2])
			_add_stop(StringName("%s:%d" % [e[0]["id"], e[1]]), _name_for(at, e[0]), at, e[2])


func _add_stop(id: StringName, stop_name: String, at: Vector2, point: int) -> void:
	for s in stops.values():
		if (s["at"] as Vector2).distance_to(at) < SAME_STOP:
			return  # (one stop serves both)
	stops[id] = {"name": stop_name, "at": at, "point": point}
	var n := CartStop.new()
	n.line = self
	n.stop_id = id
	n.stop_name = stop_name
	add_child(n)
	var side := _side(point) * 3.5  # (beside the road, not on it)
	n.global_position = Vector3(at.x + side.x, _ground(at + side), at.y + side.y)
	_stop_nodes.append(n)


## Off to one side of the road at network point `point` (a unit vector across it).
func _side(point: int) -> Vector2:
	var p := _astar.get_point_position(point)
	var links := _astar.get_point_connections(point)
	if links.is_empty():
		return Vector2.RIGHT
	var along := (_astar.get_point_position(links[0]) - p).normalized()
	return Vector2(-along.y, along.x)


## A road end's stop's name: the area or place nearest it, else the road's own.
func _name_for(at: Vector2, road: Dictionary) -> String:
	if WorldMap.has_area(&"village") and WorldMap.village_center().distance_to(at) < IN_VILLAGE:
		var d := at - WorldMap.village_center()
		var side := ("east" if d.x > 0 else "west") if absf(d.x) > absf(d.y) else ("south" if d.y > 0 else "north")
		return "%s, %s end" % [WorldMap.area(&"village").get("name", "Hearthvale"), side]
	var best := NAME_REACH
	var out := "End of %s" % String(road.get("title", road["id"])).to_lower()
	for a in WorldMap.areas():
		var type := StringName(a["type"])
		if not WorldMap.AREAS.has(type):
			continue
		var d := WorldMap.area_at(type).distance_to(at)
		if d < best:
			best = d
			out = a.get("name", WorldMap.AREAS[type]["name"])
	for id in PLACE_NAMES:
		var p := LayoutAnchors.find(id)
		if not p.is_empty() and p.get("placed", true) and WorldMap.site(id).distance_to(at) < best:
			best = WorldMap.site(id).distance_to(at)
			out = PLACE_NAMES[id]
	return out


## Where the cart can go from stop `from`: [{id, name, length}], nearest first.
func destinations(from: StringName) -> Array:
	var out := []
	if not stops.has(from):
		return out
	for id in stops:
		if id == from:
			continue
		var path := _astar.get_point_path(stops[from]["point"], stops[id]["point"])
		if path.size() < 2:
			continue
		out.append({"id": id, "name": stops[id]["name"], "length": _length(path)})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["length"] < b["length"])
	return out


static func _length(path: PackedVector2Array) -> float:
	var l := 0.0
	for i in range(1, path.size()):
		l += path[i - 1].distance_to(path[i])
	return l


## Rung at stop `from` for stop `to`: the cart comes up the road, waits for you, then goes.
func call_cart(from: StringName, to: StringName) -> void:
	if riding() or not stops.has(from) or not stops.has(to):
		return
	var path := _astar.get_point_path(stops[from]["point"], stops[to]["point"])
	if path.size() < 2:
		return
	var lead := (path[0] - path[1]).normalized()  # (it comes from behind, the way it'll set off)
	var start := path[0] + lead * ARRIVE_FROM
	_path = PackedVector2Array([start]) + path
	_along = PackedFloat32Array([0.0])
	for i in range(1, _path.size()):
		_along.append(_along[-1] + _path[i - 1].distance_to(_path[i]))
	_to = to
	_s = 0.0
	_speed = ARRIVE_SPEED
	_phase = &"coming"
	_make_cart()
	_place()
	Sfx.play_ui(&"open")  # (the bell: a stand-in)


func _make_cart() -> void:
	_cart = Node3D.new()
	_cart.name = "Cart"
	add_child(_cart)
	var model := CART.instantiate() as Node3D
	_cart.add_child(model)
	var box := AABB()
	var any := false
	for m in model.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		var b := mi.transform * mi.get_aabb()
		box = b if not any else box.merge(b)
		any = true
	_seat = Marker3D.new()
	_seat.name = "Seat"
	_seat.set_meta(&"cart", true)
	# on the cart's bed, at the back, facing out to one side (the land going by)
	_seat.position = Vector3(box.get_center().x, box.position.y + box.size.y * 0.45, box.get_center().z) if any else Vector3(0, 0.9, 0)
	_seat.rotation.y = PI * 0.5
	_cart.add_child(_seat)


func _physics_process(delta: float) -> void:
	if _cart == null:
		return
	var player := get_tree().get_first_node_in_group("player")
	var total := _along[-1]
	match _phase:
		&"coming":
			_s = minf(_s + ARRIVE_SPEED * delta, ARRIVE_FROM)
			if _s >= ARRIVE_FROM - 0.01:
				_phase = &"waiting"
				_wait = WAIT
				if player and (player as Node3D).global_position.distance_to(_seat.global_position) < 12.0:
					player.call("sit", _seat)
		&"waiting":
			_wait -= delta
			if player and player.get("seat") == _seat:
				_wait = minf(_wait, 0.0)  # (on board: off we go once they're settled)
				if _wait < -0.7:
					_phase = &"riding"
					_speed = 0.0
			elif _wait <= 0.0:
				_phase = &"leaving"
		&"riding":
			if not player or player.get("seat") != _seat:
				_phase = &"leaving"  # (hopped off)
			else:
				var left := total - _s
				var want := minf(RIDE_SPEED, sqrt(maxf(2.0 * ACCEL * left, 0.0)) + 0.4)
				_speed = move_toward(_speed, want, ACCEL * delta)
				_s = minf(_s + _speed * delta, total)
				if _s >= total - 0.05:
					player.call("stand")  # (there: down beside the cart)
					_phase = &"leaving"
		&"leaving":
			_speed = move_toward(_speed, ARRIVE_SPEED, ACCEL * delta)
			_s += _speed * delta
			_wait -= delta
			if _wait < -8.0 or _s > total + 30.0:
				_cart.queue_free()
				_cart = null
				_seat = null
				_rebuild.call_deferred()
				return
	_place()


## The cart where it is along its path, on the ground, facing the way it goes.
func _place() -> void:
	var s := _s
	var k := 1
	while k < _path.size() - 1 and _along[k] < s:
		k += 1
	var a := _path[k - 1]
	var b := _path[k]
	var dir := (b - a).normalized()
	var p := a.lerp(b, clampf((s - _along[k - 1]) / maxf(_along[k] - _along[k - 1], 0.001), 0.0, 1.25))
	if s > _along[-1]:  # (driving off past the end)
		p = _path[-1] + dir * (s - _along[-1])
	_cart.global_position = Vector3(p.x, _ground(p), p.y)
	var look := Vector3(dir.x, 0, dir.y)
	if look.length_squared() > 0.001:
		_cart.global_basis = _cart.global_basis.slerp(Basis.looking_at(look), 0.2)


func _ground(p: Vector2) -> float:
	var terrain := get_tree().get_first_node_in_group("terrain") as Terrain3D
	var h: float = terrain.data.get_height(Vector3(p.x, 0, p.y)) if terrain and terrain.data else NAN
	return 0.0 if is_nan(h) else h
