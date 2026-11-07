extends RefCounted
## A plot's shape worked out (plans/town-designer.md, phase 4): the house's back garden the town
## designer draws, {id, owner?, points, edge, gate: [edge index, width], fill, seed}. Static, no
## game classes, so tools/bake_layout.gd and the tests can use it before the autoloads exist.
##   edge_runs():  its edge as open runs, the gate a gap in the middle of edge `gate[0]`
##   fill_spots(): where its garden's things go: [type, Vector2, yaw (degrees)], seeded
##   inside_grid(): spots inside it every `step` m (for keeping scattered trees and rocks out)


static func _pts(a: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in a:
		out.append(Vector2(float(p[0]), float(p[1])))
	return out


## The plot's edge, round it once, as open runs with the gate left out (one run with a gate; the whole
## loop, closed, without). A gate wider than its edge leaves that edge out.
static func edge_runs(plot: Dictionary) -> Array[PackedVector2Array]:
	var pts := _pts(plot.get("points", []))
	var n := pts.size()
	var out: Array[PackedVector2Array] = []
	if n < 3:
		return out
	var gate: Variant = plot.get("gate")
	if not (gate is Array) or (gate as Array).size() < 2:
		var loop := pts.duplicate()
		loop.append(pts[0])
		out.append(loop)
		return out
	var i := posmod(int(gate[0]), n)
	var a := pts[i]
	var b := pts[(i + 1) % n]
	var len := a.distance_to(b)
	var half := minf(float(gate[1]), len) / 2.0
	var mid := a.lerp(b, 0.5)
	var dir := (b - a).normalized() if len > 0.0 else Vector2.ZERO
	var run := PackedVector2Array()
	run.append(mid + dir * half)
	for k in range(1, n + 1):  # from the gate's far side round to its near side
		run.append(pts[(i + k) % n])
	run.append(mid - dir * half)
	out.append(run)
	return out


## Whether `p` is inside polygon `poly`.
static func inside(p: Vector2, poly: PackedVector2Array) -> bool:
	return Geometry2D.is_point_in_polygon(p, poly)


## How far `p` is from the polygon's edge (m).
static func edge_distance(p: Vector2, poly: PackedVector2Array) -> float:
	var best := INF
	for i in poly.size():
		var q := Geometry2D.get_closest_point_to_segment(p, poly[i], poly[(i + 1) % poly.size()])
		best = minf(best, p.distance_to(q))
	return best


## The direction (radians, of a 2D vector's angle) of the plot's longest edge: its rows run that way.
static func grain(poly: PackedVector2Array) -> float:
	var best := 0.0
	var ang := 0.0
	for i in poly.size():
		var d := poly[(i + 1) % poly.size()] - poly[i]
		if d.length() > best:
			best = d.length()
			ang = d.angle()
	return ang


## Spots `step` m apart inside the plot, on a grid along its grain.
static func inside_grid(plot: Dictionary, step: float, margin := 0.0) -> PackedVector2Array:
	var poly := _pts(plot.get("points", []))
	var out := PackedVector2Array()
	if poly.size() < 3 or step <= 0.0:
		return out
	var ang := grain(poly)
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for p in poly:
		var l := p.rotated(-ang)
		lo = lo.min(l)
		hi = hi.max(l)
	var y := lo.y + step / 2.0
	while y < hi.y:
		var x := lo.x + step / 2.0
		while x < hi.x:
			var p := Vector2(x, y).rotated(ang)
			if inside(p, poly) and edge_distance(p, poly) >= margin:
				out.append(p)
			x += step
		y += step
	return out


## Where garden `garden` ({items: {type: weight}, spacing, margin, fill (0-1), rows}) puts its things
## in the plot: [[type, Vector2, yaw degrees]...], the same every time for the plot's seed.
static func fill_spots(plot: Dictionary, garden: Dictionary) -> Array:
	var out := []
	var items: Dictionary = garden.get("items", {})
	if items.is_empty():
		return out
	var total := 0.0
	for k in items:
		total += float(items[k])
	var rng := RandomNumberGenerator.new()
	rng.seed = int(plot.get("seed", 1))
	var poly := _pts(plot.get("points", []))
	var spacing := float(garden.get("spacing", 3.0))
	var rows: bool = garden.get("rows", false)
	var along := rad_to_deg(grain(poly)) if poly.size() >= 3 else 0.0
	for p in inside_grid(plot, spacing, float(garden.get("margin", 1.2))):
		if rng.randf() > float(garden.get("fill", 1.0)):
			continue
		var pick := rng.randf() * total
		var type := ""
		for k in items:
			type = k
			pick -= float(items[k])
			if pick <= 0.0:
				break
		var jitter := spacing * (0.12 if rows else 0.3)
		var at := p + Vector2(rng.randf_range(-jitter, jitter), rng.randf_range(-jitter, jitter))
		if not inside(at, poly):
			at = p
		# (a yaw turns +Z toward the vector's angle a: 90 - a; rows face along the grain)
		var yaw := 90.0 - along + (rng.randf_range(-6.0, 6.0) if rows else rng.randf_range(0.0, 360.0))
		out.append([type, at, wrapf(yaw, -180.0, 180.0)])
	return out
