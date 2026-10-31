class_name LayoutWater
extends RefCounted
## The map editor's water (plans/terrain-editing.md): data/layout/hearthvale.json's "terrain" ponds
## and rivers, read once for everything that needs them: the terrain generator digs them, the
## layout bake gives them their water, the creek leaves its surface out where it runs into one.
## Every water sits at LEVEL, like the creek's.
##   pond   {id, shape: "circle", center, radius | shape: "polygon", points; depth, shelf?, fish?}
##   river  {id, points (a line, smoothed: WorldMap.spline), width, depth, vale?, fish?}

const LAYOUT := "res://data/layout/hearthvale.json"
## Keep in sync with tools/generate_test_terrain.gd's WATER_LEVEL and Creek.WATER_LEVEL.
const LEVEL := -0.15
## How far (m) in from a polygon pond's shore it reaches its full depth, unless it says.
const SHELF := 6.0
## A river's land eases down to its banks over this much (m) each side, unless it says.
const VALE := 30.0

## The layout file read (tools can point it at another: use_file()).
static var layout_path := LAYOUT
static var _ponds: Array[Dictionary] = []
static var _rivers: Array[Dictionary] = []
static var _loaded := false


## Reads the water from `path` instead (the terrain generator's --layout, for a test).
static func use_file(path: String) -> void:
	layout_path = path
	_loaded = false


## The layout's ponds: each its shape as written, plus `outline` (a PackedVector2Array, empty for a
## circle), `centre` (Vector2) and `reach` (the farthest its water goes from the centre, m).
static func ponds() -> Array[Dictionary]:
	_load()
	return _ponds


## The layout's rivers: each its shape as written, plus `ctrl` (its points, Vector2s), `pts` (the
## smoothed line, about 1 m apart) and `half` (half its width, m).
static func rivers() -> Array[Dictionary]:
	_load()
	return _rivers


## How far `w` is from pond `p`'s shore: negative inside, positive outside (m).
static func shore_distance(p: Dictionary, w: Vector2) -> float:
	var outline: PackedVector2Array = p["outline"]
	if outline.is_empty():
		return w.distance_to(p["centre"]) - float(p["radius"])
	var d := INF
	for i in outline.size():
		d = minf(d, w.distance_to(Geometry2D.get_closest_point_to_segment(w, outline[i], outline[(i + 1) % outline.size()])))
	return -d if Geometry2D.is_point_in_polygon(w, outline) else d


## Whether `w` is in one of the layout's ponds, or within `margin` m of its shore.
static func in_pond(w: Vector2, margin := 0.0) -> bool:
	for p in ponds():
		if w.distance_to(p["centre"]) <= float(p["reach"]) + margin and shore_distance(p, w) <= margin:
			return true
	return false


## How far `w` is from river `r`'s middle (m).
static func river_distance(r: Dictionary, w: Vector2) -> float:
	var pts: PackedVector2Array = r["pts"]
	var best := INF
	for i in pts.size() - 1:
		best = minf(best, w.distance_squared_to(Geometry2D.get_closest_point_to_segment(w, pts[i], pts[i + 1])))
	return sqrt(best)


static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	_ponds.clear()
	_rivers.clear()
	var layout: Variant = JSON.parse_string(FileAccess.get_file_as_string(layout_path)) if FileAccess.file_exists(layout_path) else null
	if not layout is Dictionary:
		return
	for s: Dictionary in layout.get("terrain", []):
		match s.get("type", ""):
			"pond":
				var p := s.duplicate()
				p["outline"] = PackedVector2Array()
				if s.get("shape", "circle") == "circle":
					if not s.has("center"):
						continue
					p["centre"] = _v2(s["center"])
					p["reach"] = float(s.get("radius", 1.0))
				else:
					var outline := PackedVector2Array()
					for q in s.get("points", []):
						outline.append(_v2(q))
					if outline.size() < 3:
						continue
					p["outline"] = outline
					var c := Vector2.ZERO
					for q in outline:
						c += q / outline.size()
					p["centre"] = c
					var reach := 0.0
					for q in outline:
						reach = maxf(reach, q.distance_to(c))
					p["reach"] = reach
				_ponds.append(p)
			"river":
				if s.get("points", []).size() < 2:
					continue
				var r := s.duplicate()
				var ctrl: Array[Vector2] = []
				for q in s["points"]:
					ctrl.append(_v2(q))
				r["ctrl"] = ctrl
				r["pts"] = WorldMap.spline(ctrl, false)
				r["half"] = maxf(float(s.get("width", 4.0)) * 0.5, 0.5)
				_rivers.append(r)


static func _v2(a: Array) -> Vector2:
	return Vector2(float(a[0]), float(a[1]))
