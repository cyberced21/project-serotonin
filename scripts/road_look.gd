class_name RoadLook
extends Node3D
## What a better road looks like (plans/road-travel.md, picked on the road travel page): its cells
## repainted on the terrain's control map (WorldMap.TEX_PACKED, TEX_COBBLE: the terrain shader's
## packed earth and stone setts, the footsteps' packed and cobble), and its edging laid along both
## sides: timber boards along a packed road, kerb stones along a cobbled one. Done when the world
## loads and again each time a road's level changes (Roads.changed: the morning after it's paid
## for). The edging leaves a gap where another road comes in or the market place or a patch (a
## lane, the field tracks: Roads.patch_cells) opens off it, and stops over water. A bettered
## patch's cells are painted too, unedged (plans/roads-everywhere.md).
## Laid overnight (Roads.laid), a road builds itself along, as the buildings do: it keeps its old
## look till you come within REVEAL m of it, then the new surface spreads both ways along it from
## the point nearest you (a patch: out from the cell nearest you), its edging springing up as the
## front passes, with the packed earth's (or the setts') knocks and a trail of dust, and a cheer at
## the end. A loaded world's roads, and the debug menu's, are simply as they are.

## Edging: [length, width, height, gap between pieces (m), colour] for each level.
const EDGING := {
	1: [1.9, 0.12, 0.10, 0.12, Color(0.42, 0.29, 0.18)],  # timber boards
	2: [0.55, 0.22, 0.14, 0.06, Color(0.52, 0.52, 0.50)],  # kerb stones
}
## Painted out this far past the road's half width (m): the verge it was laid with.
const PAINT_MARGIN := 0.3
## A road's own cells: what it's laid on (or painted with already).
const PAINTABLE := [WorldMap.TEX_PATH, WorldMap.TEX_ROAD, WorldMap.TEX_PACKED, WorldMap.TEX_COBBLE]
const WATER := -0.1
## The build-along: it starts when you're within REVEAL m of the road and spreads at LAY_SPEED m/s,
## sped up or slowed so it takes LAY_SHORTEST to LAY_LONGEST s; each edging piece springs up over
## PIECE_POP s; a knock every KNOCK_EVERY s at the front; the control map's re-sent to the terrain
## at most every PAINT_EVERY s while it goes.
const REVEAL := 80.0
const LAY_SPEED := 25.0
const LAY_SHORTEST := 2.5
const LAY_LONGEST := 10.0
const PIECE_POP := 0.28
const KNOCK_EVERY := 0.11
const PAINT_EVERY := 0.08
const KNOCKS := {1: preload("res://audio/footsteps/packed.tres"), 2: preload("res://audio/footsteps/cobble.tres")}
const DONE_WORDS := {1: "packed", 2: "cobbled"}
const POPUP_COLOR := Color("ffd27a")  # (the buildings' upgrade popup)

var _terrain: Terrain3D
var _edging: Array[Node] = []
## Laid overnight, not seen yet: way id -> the level it still looks.
var _fresh: Dictionary[StringName, int] = {}
## Being built along: way id -> {lvl, cells: [[Vector2i, distance from the start]] nearest first,
## next (the first cell not painted yet), t, speed, at (where it started), knock_t, edging: {mm,
## d (each piece's distance from the start), home (its transform)}}.
var _laying := {}
var _look := 0.0
var _paint_due := 0.0
var _dirty := false
var _knocks: Array[AudioStreamPlayer3D] = []
var _next_knock := 0
var _dust: CPUParticles3D


func _ready() -> void:
	add_to_group("road_look")
	Roads.laid.connect(_on_laid)
	Roads.changed.connect(_refresh.call_deferred)
	for i in 3:
		var a := AudioStreamPlayer3D.new()
		a.unit_size = 8.0
		a.max_distance = 70.0
		add_child(a)
		_knocks.append(a)
	_dust = _make_dust()
	add_child(_dust)
	_refresh.call_deferred()


## Whether a road laid overnight is still to be built along (or being built along now).
func building() -> bool:
	return not _fresh.is_empty() or not _laying.is_empty()


func laying() -> bool:
	return not _laying.is_empty()


func _on_laid(was: Dictionary) -> void:
	for id in was:
		if not _fresh.has(id) and not _laying.has(id):
			_fresh[id] = was[id]


## The level way `id` looks now.
func _shown(id: StringName) -> int:
	if _laying.has(id):
		return _laying[id]["lvl"]
	return _fresh.get(id, Roads.level_of(id))


func _refresh() -> void:
	_terrain = get_tree().get_first_node_in_group("terrain") as Terrain3D
	if _terrain == null or _terrain.data == null:
		return
	var cells := Roads.patch_cells()  # (read before anything's painted)
	for n in _edging:
		remove_child(n)  # (now: the new edging takes its name)
		n.queue_free()
	_edging.clear()
	var better: Array = []
	for r in WorldMap.roads():
		var lvl := _shown(r["id"])
		if lvl > 0 and (r["pts"] as PackedVector2Array).size() >= 2:
			better.append([lvl, r])
	better.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])  # (the better one wins where they meet)
	var painted := 0
	for b in better:
		if not _laying.has(b[1]["id"]):  # (the build-along paints its own as it goes)
			painted += _paint(b[1], _tex(b[0]))
	for c in cells:
		var lvl := _shown(cells[c])
		if lvl > 0 and not _laying.has(cells[c]) and _set_cell(c, _tex(lvl)):
			painted += 1
	if painted > 0:
		_terrain.data.update_maps(Terrain3DRegion.TYPE_CONTROL, true, false)
	for b in better:
		_edge(b[1], b[0])


static func _tex(lvl: int) -> int:
	return WorldMap.TEX_PACKED if lvl == 1 else WorldMap.TEX_COBBLE


## Paints road `r`'s cells `id`. Returns how many it changed.
func _paint(r: Dictionary, id: int) -> int:
	var changed := 0
	for c in _road_cells(r):
		if _set_cell(c[0], id):
			changed += 1
	return changed


## Road `r`'s cells: [[Vector2i, how far along the road (m)]], from its first point.
func _road_cells(r: Dictionary) -> Array:
	var pts: PackedVector2Array = r["pts"]
	var half: float = r["half_width"] + PAINT_MARGIN
	var out: Array = []
	var done := {}
	var walked := 0.0
	for i in range(1, pts.size()):
		var a := pts[i - 1]
		var b := pts[i]
		var seg := a.distance_to(b)
		var along := (b - a).normalized()
		var across := Vector2(-along.y, along.x)
		for t in [0.0, 0.5]:
			var p := a.lerp(b, t)
			var off := -half
			while off <= half:
				var c := Vector2i((p + across * off).floor())
				off += 0.5
				if not done.has(c):
					done[c] = true
					out.append([c, walked + seg * t])
		walked += seg
	return out


## Paints cell `c` `id` if it's road ground and isn't already. Whether it changed it.
func _set_cell(c: Vector2i, id: int) -> bool:
	var at := Vector3(c.x + 0.5, 0, c.y + 0.5)
	var now := _terrain.data.get_control_base_id(at)
	if now in PAINTABLE and now != id:
		_terrain.data.set_control_base_id(at, id)
		return true
	return false


## Lays road `r`'s edging for level `lvl` along both its sides (being built along: each piece
## waiting to spring up as the front passes it).
func _edge(r: Dictionary, lvl: int) -> void:
	var spec: Array = EDGING[lvl]
	var step: float = spec[0] + spec[3]
	var pts: PackedVector2Array = r["pts"]
	var side: float = r["half_width"] + spec[1] * 0.5
	var others: Array = WorldMap.roads().filter(func(o: Dictionary) -> bool: return o["id"] != r["id"])
	var cells := Roads.patch_cells()
	var places: Array[Transform3D] = []
	var at_along := PackedFloat32Array()
	var walked := 0.0
	var next := step * 0.5
	for i in range(1, pts.size()):
		var a := pts[i - 1]
		var b := pts[i]
		var seg := a.distance_to(b)
		while next <= walked + seg:
			var p := a.lerp(b, (next - walked) / maxf(seg, 0.001))
			var along := (b - a).normalized()
			var across := Vector2(-along.y, along.x)
			for s in [-1.0, 1.0]:
				var q: Vector2 = p + across * side * s
				if _near_other_road(q, others) or WorldMap.in_market(q + across * s * 1.5) \
						or cells.has(Vector2i((q + across * s * 1.2).floor())):
					continue  # (a road comes in here, or the market place or a lane opens off it: leave it open)
				var h := _terrain.data.get_height(Vector3(q.x, 0, q.y))
				if is_nan(h) or h < WATER:
					continue
				var basis := Basis(Vector3.UP, atan2(along.x, along.y))
				places.append(Transform3D(basis, Vector3(q.x, h + spec[2] * 0.3, q.y)))
				at_along.append(next)
			next += step
		walked += seg
	if places.is_empty():
		return
	var mesh := BoxMesh.new()
	mesh.size = Vector3(spec[1], spec[2], spec[0])
	var mat := StandardMaterial3D.new()
	mat.albedo_color = spec[4]
	mat.roughness = 1.0
	mesh.material = mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = places.size()
	for k in places.size():
		mm.set_instance_transform(k, places[k])
	var inst := MultiMeshInstance3D.new()
	inst.name = "Edging_%s" % r["id"]
	inst.multimesh = mm
	add_child(inst)
	_edging.append(inst)
	if _laying.has(r["id"]):
		var e: Dictionary = _laying[r["id"]]
		var d := PackedFloat32Array()
		for s in at_along:
			d.append(absf(s - float(e["s0"])))
		e["edging"] = {"mm": mm, "d": d, "home": places}
		_pose_edging(e, true)


func _near_other_road(q: Vector2, others: Array) -> bool:
	for o in others:
		var pts: PackedVector2Array = o["pts"]
		var reach: float = o["half_width"] + 0.8
		for k in range(0, pts.size() - 1, 2):
			if pts[k].distance_squared_to(q) < 400.0 and Geometry2D.get_closest_point_to_segment(q, pts[k], pts[mini(k + 2, pts.size() - 1)]).distance_to(q) < reach:
				return true
	return false


# --- the build-along ----------------------------------------------------------------------------

func _process(delta: float) -> void:
	if not _laying.is_empty():
		_lay(delta)
	_look -= delta
	if _look > 0.0 or _fresh.is_empty() or _terrain == null:
		return
	_look = 0.5
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player == null:
		return
	var p := Vector2(player.global_position.x, player.global_position.z)
	for id in _fresh.keys():
		var near := _nearest(id, p)
		if near[0] < REVEAL:
			_start(id, near)


## Where way `id` comes nearest `p`: [how far (m), how far along it (a road's; 0 for a patch),
## the point (Vector2)].
func _nearest(id: StringName, p: Vector2) -> Array:
	var best := [INF, 0.0, p]
	var r := WorldMap.road(id)
	if r.is_empty():
		var cells := Roads.patch_cells()
		for c in cells:
			if cells[c] == id:
				var w := Vector2(c) + Vector2(0.5, 0.5)
				var d := w.distance_to(p)
				if d < best[0]:
					best = [d, 0.0, w]
		return best
	var pts: PackedVector2Array = r["pts"]
	var walked := 0.0
	for i in pts.size():
		if i > 0:
			walked += pts[i - 1].distance_to(pts[i])
		var d := pts[i].distance_to(p)
		if d < best[0]:
			best = [d, walked, pts[i]]
	return best


func _start(id: StringName, near: Array) -> void:
	var from: int = _fresh[id]
	_fresh.erase(id)
	var lvl := Roads.level_of(id)
	if lvl <= from:
		_refresh()
		return
	var r := WorldMap.road(id)
	var cells: Array = []
	if r.is_empty():
		var pc := Roads.patch_cells()
		var at: Vector2 = near[2]
		for c in pc:
			if pc[c] == id:
				cells.append([c, (Vector2(c) + Vector2(0.5, 0.5)).distance_to(at)])
	else:
		for c in _road_cells(r):
			cells.append([c[0], absf(float(c[1]) - float(near[1]))])
	cells.sort_custom(func(a: Array, b: Array) -> bool: return a[1] < b[1])
	var far: float = cells[-1][1] if not cells.is_empty() else 0.0
	var time := clampf(far / LAY_SPEED, LAY_SHORTEST, LAY_LONGEST)
	var w: Vector2 = near[2]
	_laying[id] = {"lvl": lvl, "cells": cells, "next": 0, "t": 0.0, "speed": maxf(far, 1.0) / time,
			"end": time + PIECE_POP, "s0": near[1], "knock_t": 0.0, "edging": {},
			"at": Vector3(w.x, _terrain.data.get_height(Vector3(w.x, 0, w.y)), w.y)}
	_dust.emitting = true
	_refresh()  # (its edging, at the new level, waiting to spring up)


func _lay(delta: float) -> void:
	for id in _laying.keys():
		var e: Dictionary = _laying[id]
		e["t"] += delta
		var front: float = e["t"] * e["speed"]
		var cells: Array = e["cells"]
		var last := -1
		while e["next"] < cells.size() and cells[e["next"]][1] <= front:
			if _set_cell(cells[e["next"]][0], _tex(e["lvl"])):
				_dirty = true
			last = e["next"]
			e["next"] += 1
		if last >= 0:
			_at_front(cells[last][0], e)
		_pose_edging(e)
		if e["t"] >= e["end"]:
			_laying.erase(id)
			_finish(id, e)
	_paint_due -= delta
	if _dirty and (_paint_due <= 0.0 or _laying.is_empty()):
		_terrain.data.update_maps(Terrain3DRegion.TYPE_CONTROL, true, false)
		_dirty = false
		_paint_due = PAINT_EVERY
	if _laying.is_empty():
		_dust.emitting = false


## The front's at cell `c`: the dust follows it, and now and then a knock.
func _at_front(c: Vector2i, e: Dictionary) -> void:
	var at := Vector3(c.x + 0.5, 0, c.y + 0.5)
	at.y = _terrain.data.get_height(at)
	if is_nan(at.y):
		return
	_dust.global_position = at + Vector3.UP * 0.1
	if e["t"] >= e["knock_t"]:
		e["knock_t"] = e["t"] + KNOCK_EVERY
		var a := _knocks[_next_knock]
		_next_knock = (_next_knock + 1) % _knocks.size()
		a.global_position = at
		a.stream = KNOCKS[e["lvl"]]
		a.pitch_scale = randf_range(0.9, 1.15)
		a.play()


## Each edging piece by how long since the front passed it: not yet (flat in the ground), springing
## up, or home. `all`: every piece, else just those springing up now.
func _pose_edging(e: Dictionary, all := false) -> void:
	var ed: Dictionary = e["edging"]
	if ed.is_empty():
		return
	var mm: MultiMesh = ed["mm"]
	var d: PackedFloat32Array = ed["d"]
	var home: Array[Transform3D] = ed["home"]
	for k in mm.instance_count:
		var age: float = e["t"] - d[k] / e["speed"]
		if not all and (age < 0.0 or age > PIECE_POP + 0.1):
			continue
		var s := _spring(clampf(age / PIECE_POP, 0.0, 1.0))
		var tr := home[k]
		mm.set_instance_transform(k, Transform3D(tr.basis * Basis.from_scale(Vector3.ONE * maxf(s, 0.001)),
				tr.origin + Vector3.DOWN * 0.15 * (1.0 - minf(s, 1.0))))


## 0 to 1 with a little overshoot (the buildings' pieces' TRANS_BACK, EASE_OUT).
static func _spring(x: float) -> float:
	const C1 := 1.70158
	if x <= 0.0:
		return 0.0
	return 1.0 + (C1 + 1.0) * pow(x - 1.0, 3.0) + C1 * pow(x - 1.0, 2.0)


func _finish(id: StringName, e: Dictionary) -> void:
	var ed: Dictionary = e["edging"]
	if not ed.is_empty():
		var mm: MultiMesh = ed["mm"]
		var home: Array[Transform3D] = ed["home"]
		for k in mm.instance_count:
			mm.set_instance_transform(k, home[k])
	Music.play_cue(&"upgrade")
	PopupText.spawn(get_parent(), e["at"] + Vector3.UP * 2.0, "%s, %s!" % [_title(id), DONE_WORDS[e["lvl"]]], POPUP_COLOR, 18)


func _title(id: StringName) -> String:
	for r in Roads.roads():
		if r["id"] == id:
			return r["title"]
	return String(id)


func _make_dust() -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.emitting = false
	p.amount = 40
	p.lifetime = 0.9
	var mesh := SphereMesh.new()  # (a little faceted diamond, as the buildings' dust)
	mesh.radial_segments = 4
	mesh.rings = 2
	mesh.radius = 0.12
	mesh.height = 0.2
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 1.0
	mesh.material = mat
	p.mesh = mesh
	p.color = Color("8f7759")
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(1.5, 0.1, 1.5)
	p.direction = Vector3.UP
	p.spread = 70.0
	p.initial_velocity_min = 0.8
	p.initial_velocity_max = 2.2
	p.gravity = Vector3(0, -2.0, 0)
	p.damping_min = 1.5
	p.damping_max = 2.5
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.4
	return p
