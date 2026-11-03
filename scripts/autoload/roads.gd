extends Node
## Better roads (plans/road-travel.md): every road and path the map has (WorldMap.roads()) is at a
## level, 0 as it was laid, 1 packed and edged, 2 cobbled, bought on the noticeboard (Projects,
## "road:<id>:<level>") and laid overnight: paid for, it's pending till the next morning. On a
## road's line (within its half width, and a little) you go faster by its level (bonus_at), where
## two meet by the better one; your dog keeps pace with you on his own. Which road ends you've
## been to (reached: where the carter's cart can take you, CartLine) is kept too. Saved, per world.

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

var level: Dictionary[StringName, int] = {}
## Paid for, laid tonight: road id -> the level it'll be in the morning.
var pending: Dictionary[StringName, int] = {}
## The road ends you've been to: "<road id>:0" (its first point) or ":1" (its last).
var reached: Dictionary[StringName, bool] = {}
var _grid := {}  # Vector2i -> [[road id, a, b, reach]]
var _built := false
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
	return out


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
	for seg in _grid.get(Vector2i((w / CELL).floor()), []):
		var lvl := level_of(seg[0])
		if lvl == 0 or BONUS[lvl] <= best:
			continue
		if Geometry2D.get_closest_point_to_segment(w, seg[1], seg[2]).distance_to(w) <= seg[3]:
			best = BONUS[lvl]
	return 1.0 + best


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
