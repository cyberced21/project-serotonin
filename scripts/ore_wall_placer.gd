class_name OreWallPlacer
extends Node3D
## Lines a quarry's walls with ore wall (plans/ore-walls.md): walks round each ring wall of a
## stepped pit, feeling for the wall in the terrain, and stands runs of OreWall panels against it
## (OreWallRun: panels, pillars, a cap rock), each block of rock in front of the wall on the level
## below, its cap flush with the level above. Wherever the wall isn't a clean step (the haul road's
## ramps, the mantle stairs) or a prop stands against it (ladders, scaffolds), the run breaks.
## Works on any stepped pit: Greystone (scenes/biomes/quarry.tscn) and a procgen world's quarry.

## The pit's middle (world XZ) and its walls' radii, outermost first.
@export var center := Vector2.ZERO
@export var walls: Array[float] = []
## How far each level is below the one above (m).
@export var level_drop := 5.0
## Walls tighter than this (m, radius) are left bare: a block of rock round a small pit's last
## wall would leave no floor.
@export var min_radius := 12.0
## Saves go under "wall:<save_prefix>_r<ring>_<n>"; veins come from `seed`.
@export var save_prefix := "quarry_wall"
@export var seed := 0

## The gap between a block's back and the wall it stands against (m): the bedrock slab fills it,
## clear of the terrain's own slope.
const BACK_GAP := 0.6
## A panel and a pillar (m along the face).
const STEP := OreWall.WIDTH + 1.0
## How far either side of the wall's radius to feel for it (m), and how finely.
const SEARCH := 4.0
const PROBE := 0.1
## How flat the level below must be under a block (m either way), and the level above behind it.
const FLAT := 0.4
## Room left round a prop (m, past its footprint).
const PROP_ROOM := 1.0

var _terrain: Terrain3D
var _props: Array[Vector3] = []  # (x, z, radius)
## How many panels it stood, per ring (for tools and the debug readout).
var placed: PackedInt32Array = PackedInt32Array()


func _ready() -> void:
	_place.call_deferred()  # once the terrain and the props are in place


func _place() -> void:
	_terrain = get_tree().get_first_node_in_group("terrain") as Terrain3D
	if _terrain == null or _terrain.data == null:
		push_warning("OreWallPlacer %s: no terrain" % name)
		return
	for p in get_tree().get_nodes_in_group("prop"):
		var at := (p as Node3D).global_position
		_props.append(Vector3(at.x, at.z, (p as Prop).footprint_radius()))
	placed.resize(walls.size())
	for w in walls.size():
		placed[w] = _line_wall(w) if walls[w] >= min_radius else 0


## Stands runs of panels round wall w. How many panels.
func _line_wall(w: int) -> int:
	var face_r := walls[w] - OreWall.DEPTH - BACK_GAP
	var steps := floori(TAU * face_r / STEP)
	var dtheta := TAU / steps
	# start where the wall is broken (a ramp or stairs), so no run is split across angle 0
	var start := 0
	for i in steps:
		if _panel_at(w, i * dtheta).is_empty():
			start = i
			break
	var run: Array = []
	var count := 0
	var n := 0
	for k in steps + 1:
		var spot := {} if k == steps else _panel_at(w, (start + k) * dtheta)
		if spot.is_empty():
			if not run.is_empty():
				_build_run(w, n, run)
				count += run.size()
				n += 1
				run = []
			continue
		run.append(spot)
	return count


## The panel that would stand at angle theta on wall w: {"xform", "floor", "top"} (world), or
## empty when the wall there isn't a clean step with level ground either side.
func _panel_at(w: int, theta: float) -> Dictionary:
	var r := walls[w]
	var face_r := r - OreWall.DEPTH - BACK_GAP
	var half := (OreWall.WIDTH * 0.5 + 1.0) / face_r  # (the pillars either side too)
	var left := _wall_point(w, theta - half)
	var mid := _wall_point(w, theta)
	var right := _wall_point(w, theta + half)
	if left.is_empty() or mid.is_empty() or right.is_empty():
		return {}
	var floor_y: float = mid["floor"]
	for p in [left, right]:
		if absf(p["floor"] - floor_y) > FLAT or absf(p["top"] - mid["top"]) > FLAT:
			return {}
	# the panel faces the pit's middle, its back along the wall where it runs
	var a: Vector3 = left["at"]
	var b: Vector3 = right["at"]
	var x := (a - b).normalized()  # (looking at the face from the pit, +x is to the right)
	x.y = 0.0
	x = x.normalized()
	var z := x.cross(Vector3.UP)
	var toward := Vector3(center.x, 0, center.y) - (mid["at"] as Vector3)
	if z.dot(toward) < 0.0:
		x = -x
		z = -z
	var deepest := INF  # how far the block can reach back before it meets the wall
	for p: Dictionary in [left, mid, right]:
		deepest = minf(deepest, ((p["at"] as Vector3) - (mid["at"] as Vector3)).dot(-z))
	var back := (mid["at"] as Vector3) + (-z) * (deepest - BACK_GAP)
	var origin := back + z * OreWall.DEPTH
	origin.y = floor_y - 0.05
	# level ground under the whole block, and no prop in the way
	for u: float in [-0.5, 0.0, 0.5]:
		for d: float in [0.3, 0.5, 0.8]:
			var p := origin + x * (u * (OreWall.WIDTH + 2.0)) - z * (d * OreWall.DEPTH)
			var h: float = _terrain.data.get_height(p)
			if is_nan(h) or absf(h - floor_y) > FLAT:
				return {}
	var centre := origin - z * OreWall.DEPTH * 0.5
	for prop in _props:
		if Vector2(centre.x - prop.x, centre.z - prop.y).length() < prop.z + OreWall.DEPTH * 0.5 + 1.0 + PROP_ROOM:
			return {}
	return {"xform": Transform3D(Basis(x, Vector3.UP, z), origin), "floor": floor_y, "top": mid["top"]}


## Where wall w is at angle theta: {"at" (world, on the step), "floor", "top"}, or empty if
## there's no clean drop of about a level there.
func _wall_point(w: int, theta: float) -> Dictionary:
	var dir := Vector3(cos(theta), 0, sin(theta))
	var c := Vector3(center.x, 0, center.y)
	var r := walls[w]
	var inner: float = _terrain.data.get_height(c + dir * (r - SEARCH))
	var outer: float = _terrain.data.get_height(c + dir * (r + SEARCH))
	if is_nan(inner) or is_nan(outer) or absf(outer - inner - level_drop) > FLAT * 2.0:
		return {}
	var mid := inner + level_drop * 0.5
	var d := r - SEARCH
	while d < r + SEARCH:
		var h: float = _terrain.data.get_height(c + dir * d)
		if h > mid:
			var at := c + dir * d
			at.y = mid
			return {"at": at, "floor": inner, "top": outer}
		d += PROBE
	return {}


func _build_run(w: int, n: int, spots: Array) -> void:
	var run := OreWallRun.new()
	run.name = "Ring%d_Run%d" % [w, n]
	var floor_y: float = spots[spots.size() / 2]["floor"]
	var tops := []
	for s: Dictionary in spots:
		tops.append(s["top"] - s["floor"])
	tops.sort()
	run.height = tops[tops.size() / 2]
	run.ring = w
	run.rings = walls.size()
	var origin := Vector3(0, floor_y, 0)
	for i in spots.size():
		var id := "%s_r%d_%d_%02d" % [save_prefix, w, n, i]
		var xf: Transform3D = spots[i]["xform"]
		xf.origin -= origin
		run.panels.append(xf)
		run.templates.append(absi(hash([seed, id])) % OreWall.TEMPLATES)
		run.seeds.append(hash([seed, id, "veins"]))
		run.save_ids.append(id)
	add_child(run)
	run.global_transform = Transform3D(Basis.IDENTITY, origin)  # (the panels are placed in world space)
	run.build()
