class_name RoadCourse
extends Node3D
## The ring road (the same centre line the terrain generator graded it on, WorldMap.ring()): lays
## the earth bridge over the gully, and measures positions along the road. It used to carry a
## parkour time trial; that went with the calm feel (plans/calm-feel.md).

## Where distances along the road start: this far past the spot where the forest trail meets the
## ring.
const GATE_PAST_TRAIL := 12.0
const MODELS := {
	&"bridge": preload("res://models/road/bridge.glb"),
}
## These collide by their own shape (a ramp to walk over), the rest by a box.
const MESH_COLLISION: Array[StringName] = [&"bridge"]
## Middle of the gully's earth bridge, sideways from the road's centre (see the generator's _gully).
const BRIDGE_SIDE := 3.1

var length := 0.0
var _pts := PackedVector2Array()     # ring samples, starting at the start (GATE_PAST_TRAIL)
var _dist := PackedFloat32Array()    # metres from the start to each sample
var _terrain: Terrain3D


func _ready() -> void:
	_terrain = get_tree().get_first_node_in_group("terrain") as Terrain3D
	_measure()
	_place_bridge()


## Puts a piece `at` metres along the road, `side` metres left of the centre line.
func place(model: StringName, at: float, side := 0.0) -> Prop:
	var prop := Prop.new()
	prop.model = MODELS[model]
	prop.collision_from_mesh = model in MESH_COLLISION
	prop.name = "%s_%d" % [model, roundi(at)]
	prop.transform = frame_at(at, side)
	add_child(prop)
	return prop


## A frame on the road `at` metres along and `side` metres to the left, on the ground:
## X across the road (to the left), Y up, -Z along it.
func frame_at(at: float, side := 0.0) -> Transform3D:
	at = fposmod(at, length)
	var i := clampi(_dist.bsearch(at, false) - 1, 0, _pts.size() - 1)
	var j := (i + 1) % _pts.size()
	var span := _pts[i].distance_to(_pts[j])
	var p := _pts[i].lerp(_pts[j], clampf((at - _dist[i]) / maxf(span, 0.001), 0.0, 1.0))
	var along := (_pts[j] - _pts[i]).normalized()
	var left := Vector2(-along.y, along.x)
	p += left * side
	var h: float = _terrain.data.get_height(Vector3(p.x, 0, p.y)) if _terrain and _terrain.data else 0.0
	var x := Vector3(left.x, 0, left.y)
	return Transform3D(Basis(x, Vector3.UP, x.cross(Vector3.UP)), Vector3(p.x, 0.0 if is_nan(h) else h, p.y))


## (metres round from the start, metres off the centre line) for a world position.
func locate(world: Vector3) -> Vector2:
	var q := Vector2(world.x, world.z)
	var best := 0
	for i in _pts.size():
		if _pts[i].distance_squared_to(q) < _pts[best].distance_squared_to(q):
			best = i
	return Vector2(_dist[best], _pts[best].distance_to(q))


## The ring's samples re-ordered to start past the forest trail, with the distance to each.
func _measure() -> void:
	var ring := WorldMap.ring()
	var n := ring.size()
	var trail := _nearest(ring, WorldMap.TRAIL[-1])
	var start := trail
	var walked := 0.0
	while walked < GATE_PAST_TRAIL:
		walked += ring[start].distance_to(ring[(start + 1) % n])
		start = (start + 1) % n
	_pts.resize(n)
	_dist.resize(n)
	for k in n:
		_pts[k] = ring[(start + k) % n]
		_dist[k] = length
		length += _pts[k].distance_to(ring[(start + k + 1) % n])


func _place_bridge() -> void:
	var at := locate(Vector3(WorldMap.GULLY_NEAR.x, 0, WorldMap.GULLY_NEAR.y)).x
	var bridge := place(&"bridge", at, BRIDGE_SIDE)
	bridge.position.y += 0.02  # just on top of the earth


static func _nearest(pts: PackedVector2Array, to: Vector2) -> int:
	var best := 0
	for i in pts.size():
		if pts[i].distance_squared_to(to) < pts[best].distance_squared_to(to):
			best = i
	return best
