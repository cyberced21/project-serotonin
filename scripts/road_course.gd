class_name RoadCourse
extends Node3D
## The ring road's obstacle course: lays the set pieces in COURSE along the road (the same
## centre line the terrain generator graded it on, WorldMap.ring()), measured in metres from the
## time trial's gate, and answers "how far round, and how far off the road" for TimeTrial.
## Each piece covers only part of the road's width, so a fumbled move costs time, never a stop.
## Along the road is the direction you run the trial (the order of WorldMap.RING).

## Where the gate stands: this far past the spot where the forest trail meets the ring, so the
## trail comes out just behind it.
const GATE_PAST_TRAIL := 12.0
const MODELS := {
	&"log_pile": preload("res://models/road/log_pile.glb"),
	&"low_wall": preload("res://models/road/low_wall.glb"),
	&"crate_low": preload("res://models/road/crate_low.glb"),
	&"crate_high": preload("res://models/road/crate_high.glb"),
	&"wallrun_panel": preload("res://models/road/wallrun_panel.glb"),
	&"kicker": preload("res://models/road/kicker.glb"),
	&"low_beam": preload("res://models/road/low_beam.glb"),
	&"bridge": preload("res://models/road/bridge.glb"),
	&"gate": preload("res://models/road/gate.glb"),
	&"checkpoint": preload("res://models/road/checkpoint.glb"),
}
## These collide by their own shape (a ramp to run up, arches to pass under), the rest by a box.
const MESH_COLLISION: Array[StringName] = [&"kicker", &"low_beam", &"bridge", &"gate", &"checkpoint"]
## The set pieces: [metres from the gate, model, sideways offset (m, + = left of the way you run)].
## The road is 6 m wide; wall-run panels stand just inside its edges (±3.4), 11 m long.
const COURSE := [
	# a warm-up: hop the logs, clear the wall
	[30.0, &"log_pile", 1.0], [55.0, &"log_pile", -1.0], [80.0, &"low_wall", 1.0],
	# wall-run alley: kick from side to side
	[120.0, &"wallrun_panel", 3.4], [131.0, &"wallrun_panel", -3.4], [142.0, &"wallrun_panel", 3.4],
	# crates to climb, then a kicker over a log pile
	[172.0, &"crate_low", 1.2], [174.0, &"crate_high", 1.2],
	[200.0, &"kicker", -1.0], [207.0, &"log_pile", -1.0],
	# (the gully and its bridge, ~240 m, are placed by _place_bridge)
	[310.0, &"low_beam", 1.0], [350.0, &"wallrun_panel", -3.4],
	# bunny-hop rhythm
	[420.0, &"log_pile", 1.0], [434.0, &"log_pile", -1.0], [448.0, &"log_pile", 1.0], [462.0, &"log_pile", -1.0],
	[500.0, &"kicker", 0.0], [507.0, &"crate_low", 0.0],
	# the long alley
	[590.0, &"wallrun_panel", -3.4], [601.0, &"wallrun_panel", 3.4], [612.0, &"wallrun_panel", -3.4],
	[623.0, &"wallrun_panel", 3.4],
	[650.0, &"low_beam", -1.0], [668.0, &"low_wall", 1.0],
	[710.0, &"crate_low", -1.2], [712.0, &"crate_high", -1.2], [745.0, &"log_pile", 1.0],
	[830.0, &"wallrun_panel", 3.4], [870.0, &"kicker", 1.0], [878.0, &"low_wall", 1.0],
	# the run home
	[930.0, &"log_pile", -1.0], [960.0, &"log_pile", 1.0], [990.0, &"low_wall", -1.0], [1015.0, &"low_beam", 1.0],
]
## Middle of the gully's earth bridge, sideways from the road's centre (see the generator's _gully).
const BRIDGE_SIDE := 3.1

var length := 0.0
var _pts := PackedVector2Array()     # ring samples, starting at the gate
var _dist := PackedFloat32Array()    # metres from the gate to each sample
var _terrain: Terrain3D


func _ready() -> void:
	_terrain = get_tree().get_first_node_in_group("terrain") as Terrain3D
	_measure()
	for piece in COURSE:
		place(piece[1], piece[0], piece[2])
	_place_bridge()


## Puts a piece of the kit `at` metres from the gate, `side` metres left of the centre line.
func place(model: StringName, at: float, side := 0.0) -> Prop:
	var prop := Prop.new()
	prop.model = MODELS[model]
	prop.collision_from_mesh = model in MESH_COLLISION
	prop.name = "%s_%d" % [model, roundi(at)]
	prop.transform = frame_at(at, side)
	add_child(prop)
	return prop


## A frame on the road `at` metres from the gate and `side` metres to the left, on the ground:
## X across the road (to the left), Y up, -Z the way you run.
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


## (metres round from the gate, metres off the centre line) for a world position.
func locate(world: Vector3) -> Vector2:
	var q := Vector2(world.x, world.z)
	var best := 0
	for i in _pts.size():
		if _pts[i].distance_squared_to(q) < _pts[best].distance_squared_to(q):
			best = i
	return Vector2(_dist[best], _pts[best].distance_to(q))


## The ring's samples re-ordered to start at the gate, with the distance to each.
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
