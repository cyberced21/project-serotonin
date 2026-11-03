extends Node
## Better roads (plans/road-travel.md): every road and path the map has (WorldMap.roads()) is at a
## level, 0 as it was laid, 1 packed and edged, 2 cobbled, bought on the noticeboard (Projects,
## "road:<id>:<level>") and laid overnight: paid for, it's pending till the next morning. On a
## road's line (within its half width, and a little) you go faster by its level (bonus_at), where
## two meet by the better one; your dog keeps pace with you on his own. Which road ends you've
## been to (reached: where the carter's cart can take you, CartLine) is kept too. Saved, per world.
## Besides the drawn roads, the patches (plans/roads-everywhere.md): ways that aren't a line but the
## path ground of an area (the village lanes, the market place, the haul road, the field tracks),
## each bettered as one, and quicker on any of its cells (patch_cells).

signal changed

## How much quicker each level is underfoot (a share of your speed), and what's done to get it.
const BONUS := [0.0, 0.15, 0.30]
const MAX_LEVEL := 2
## Past a road's edge this far (m) still counts as on it (its verge: no stutter at the edge).
const MARGIN := 0.6
## A level's cost by the road's length: stones a metre, and a log every so many metres. Never
## less than the minimum (a short path still takes a cartload).
const STONE_PER_M := [0.0, 0.4, 0.8]
const LOG_EVERY := 10.0
const MIN_STONE := 12
const MIN_LOGS := 4
## The town hall's tier each level waits for (cobbles: its second, as the far roads' lamps).
const HALL := [0, 1, 2]
## The grid the roads' segments are filed in, for bonus_at (m a cell).
const CELL := 8.0
## Within this of a road's end (m), you've reached it.
const REACH_END := 25.0
## The patches, in the order they claim a cell: [id, title, priced as a road this long (m) a
## square metre of it]. The field tracks are a lot of ground (7000 m²): cheaper by the metre, or
## they'd be 800 stones. Where each lies is _area's.
const PATCHES := [
	[&"market", "The market place", 0.3], [&"lanes", "The village lanes", 0.3],
	[&"haul_road", "The quarry's haul road", 0.3], [&"field_tracks", "The tracks through Goldmeadow", 0.06]]
## What a patch's cells are painted (or are already, bettered).
const PATCH_GROUND := [WorldMap.TEX_PATH, WorldMap.TEX_PACKED, WorldMap.TEX_COBBLE]

var level: Dictionary[StringName, int] = {}
## Paid for, laid tonight: road id -> the level it'll be in the morning.
var pending: Dictionary[StringName, int] = {}
## The road ends you've been to: "<road id>:0" (its first point) or ":1" (its last).
var reached: Dictionary[StringName, bool] = {}
var _grid := {}  # Vector2i -> [[road id, a, b, reach]]
var _built := false
var _cells := {}  # Vector2i (a 1 m cell of the map) -> the patch it's in
var _patch_area := {}  # patch id -> its cells
var _scanned_for := 0  # the terrain the patches were read from (its instance id)
var _look := 0.0


func _ready() -> void:
	SaveGame.register(&"roads", self)
	DayNight.day_broke.connect(_lay_pending)


## Every second or so: a road end you're near is one you've reached.
func _process(delta: float) -> void:
	_look -= delta
	if _look > 0.0:
		return
	_look = 1.0
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player == null:
		return
	var p := Vector2(player.global_position.x, player.global_position.z)
	for r in WorldMap.roads():
		var pts: PackedVector2Array = r["pts"]
		if pts.size() < 2:
			continue
		for k in 2:
			var key := StringName("%s:%d" % [r["id"], k])
			if not reached.has(key) and p.distance_to(pts[0] if k == 0 else pts[-1]) < REACH_END:
				reached[key] = true
				SaveGame.mark_dirty()
				changed.emit()


func has_reached(id: StringName, end: int) -> bool:
	return reached.has(StringName("%s:%d" % [id, end]))


## The roads of this map: [{id, title, kind, length}], in their laying order.
func roads() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for r in WorldMap.roads():
		var pts: PackedVector2Array = r["pts"]
		if pts.size() < 2:
			continue
		var length := 0.0
		for i in range(1, pts.size()):
			length += pts[i - 1].distance_to(pts[i])
		out.append({"id": r["id"], "title": r.get("title", String(r["id"])), "kind": r["kind"], "length": length})
	patch_cells()
	for p in PATCHES:
		var n: int = _patch_area.get(p[0], 0)
		if n > 0:
			out.append({"id": p[0], "title": p[1], "kind": &"patch", "length": n * float(p[2])})
	return out


## Whether the carter's cart runs on road `r` (better): the gravel roads only, not the footpaths
## or the patches (plans/roads-everywhere.md).
static func carts_on(r: Dictionary) -> bool:
	return r["kind"] == &"road"


func level_of(id: StringName) -> int:
	return level.get(id, 0)


## Its level, or the one it'll be tomorrow if it's being laid tonight.
func planned_level(id: StringName) -> int:
	return maxi(level_of(id), pending.get(id, 0))


## What level `lvl` of a road `length` m long costs.
static func cost(length: float, lvl: int) -> Dictionary:
	return {&"stone": maxi(MIN_STONE, roundi(length * STONE_PER_M[lvl])), &"wood": maxi(MIN_LOGS, roundi(length / LOG_EVERY))}


## Road `id` goes to level `lvl`: tonight (paid for: it's laid overnight), or at once.
func set_level(id: StringName, lvl: int, overnight := false) -> void:
	lvl = clampi(lvl, 0, MAX_LEVEL)
	if overnight and lvl > level_of(id):
		pending[id] = lvl
	else:
		pending.erase(id)
		if lvl == 0:
			level.erase(id)
		else:
			level[id] = lvl
	SaveGame.mark_dirty()
	changed.emit()


## Morning: what was paid for yesterday is laid.
func _lay_pending() -> void:
	if pending.is_empty():
		return
	for id in pending:
		level[id] = pending[id]
	pending.clear()
	SaveGame.mark_dirty()
	changed.emit()


## How much faster you go at `p` (1 off the roads; 1 + the best level's bonus on one).
func bonus_at(p: Vector3) -> float:
	if level.is_empty():
		return 1.0
	if not _built:
		_build_grid()
	var w := Vector2(p.x, p.z)
	var best := 0.0
	var on: StringName = patch_cells().get(Vector2i(w.floor()), &"")
	if on != &"":
		best = BONUS[level_of(on)]
	for seg in _grid.get(Vector2i((w / CELL).floor()), []):
		var lvl := level_of(seg[0])
		if lvl == 0 or BONUS[lvl] <= best:
			continue
		if Geometry2D.get_closest_point_to_segment(w, seg[1], seg[2]).distance_to(w) <= seg[3]:
			best = BONUS[lvl]
	return 1.0 + best


## The patches' cells: Vector2i (a 1 m cell) -> patch id. Read from the terrain's control map the
## first time it's there (RoadLook asks before it paints anything): the path ground in each patch's
## area that no drawn road reaches over.
func patch_cells() -> Dictionary:
	if _scanned_for != 0 and is_instance_id_valid(_scanned_for):
		return _cells
	var terrain := get_tree().get_first_node_in_group("terrain") as Terrain3D
	if terrain == null or terrain.data == null:
		return _cells
	_scanned_for = terrain.get_instance_id()
	_cells.clear()
	_patch_area.clear()
	if not _built:
		_build_grid()
	for p in PATCHES:
		var a := _area(p[0])
		if a.is_empty():
			continue
		var c: Vector2 = a[0]
		var r: float = a[1]
		var inside: Callable = a[2]
		for y in range(floori(c.y - r), ceili(c.y + r)):
			for x in range(floori(c.x - r), ceili(c.x + r)):
				var cell := Vector2i(x, y)
				var w := Vector2(x + 0.5, y + 0.5)
				if _cells.has(cell) or w.distance_squared_to(c) > r * r or (inside.is_valid() and not inside.call(w)):
					continue
				if terrain.data.get_control_base_id(Vector3(w.x, 0, w.y)) not in PATCH_GROUND or _on_line(w):
					continue
				_cells[cell] = p[0]
				_patch_area[p[0]] = _patch_area.get(p[0], 0) + 1
	return _cells


## Where patch `id` can be: [centre, radius, and a Callable it must pass (or an empty one)], or []
## on a map without its place.
func _area(id: StringName) -> Array:
	var none := Callable()
	match id:
		&"market":
			if WorldMap.area_at(&"village") == WorldMap.NOWHERE:
				return []
			return [WorldMap.village_center(), WorldMap.MARKET_LENGTH / 2.0 + 1.0, WorldMap.in_market]
		&"lanes":
			if WorldMap.area_at(&"village") == WorldMap.NOWHERE:
				return []
			return [WorldMap.village_center(), WorldMap.VILLAGE_RADIUS + 15.0, none]
		&"haul_road":
			if WorldMap.quarry_center() == WorldMap.NOWHERE:
				return []
			return [WorldMap.quarry_center(), WorldMap.QUARRY_WALLS[0] + 1.0, none]
		&"field_tracks":
			if WorldMap.field_center() == WorldMap.NOWHERE:
				return []
			return [WorldMap.field_center(), WorldMap.field_radius() + 35.0, none]  # (the biomes' warp moves its edge)
	return []


## Whether `w` is within a drawn road's reach.
func _on_line(w: Vector2) -> bool:
	for seg in _grid.get(Vector2i((w / CELL).floor()), []):
		if Geometry2D.get_closest_point_to_segment(w, seg[1], seg[2]).distance_to(w) <= seg[3]:
			return true
	return false


## Each road's segments filed in the cells they pass near (their reach round them).
func _build_grid() -> void:
	_built = true
	_grid.clear()
	for r in WorldMap.roads():
		var pts: PackedVector2Array = r["pts"]
		var reach := float(r["half_width"]) + MARGIN
		for i in range(1, pts.size()):
			var a := pts[i - 1]
			var b := pts[i]
			var lo := Vector2i(((a.min(b) - Vector2(reach, reach)) / CELL).floor())
			var hi := Vector2i(((a.max(b) + Vector2(reach, reach)) / CELL).floor())
			for cy in range(lo.y, hi.y + 1):
				for cx in range(lo.x, hi.x + 1):
					var c := Vector2i(cx, cy)
					if not _grid.has(c):
						_grid[c] = []
					_grid[c].append([r["id"], a, b, reach])


func to_dict() -> Dictionary:
	var lv := {}
	for id in level:
		lv[String(id)] = level[id]
	var pd := {}
	for id in pending:
		pd[String(id)] = pending[id]
	var seen: Array[String] = []
	for k in reached:
		seen.append(String(k))
	return {"level": lv, "pending": pd, "reached": seen}


func from_dict(d: Dictionary) -> void:
	level.clear()
	pending.clear()
	reached.clear()
	for k in d.get("reached", []):
		reached[StringName(k)] = true
	for id in d.get("level", {}):
		level[StringName(id)] = int(d["level"][id])
	for id in d.get("pending", {}):
		pending[StringName(id)] = int(d["pending"][id])
	changed.emit()
