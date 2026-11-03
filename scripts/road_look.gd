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

var _terrain: Terrain3D
var _edging: Array[Node] = []


func _ready() -> void:
	add_to_group("road_look")
	Roads.changed.connect(_refresh.call_deferred)
	_refresh.call_deferred()


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
		var lvl := Roads.level_of(r["id"])
		if lvl > 0 and (r["pts"] as PackedVector2Array).size() >= 2:
			better.append([lvl, r])
	better.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])  # (the better one wins where they meet)
	var painted := 0
	for b in better:
		painted += _paint(b[1], WorldMap.TEX_PACKED if b[0] == 1 else WorldMap.TEX_COBBLE)
	for c in cells:
		var lvl := Roads.level_of(cells[c])
		var id := WorldMap.TEX_PACKED if lvl == 1 else WorldMap.TEX_COBBLE
		var at := Vector3(c.x + 0.5, 0, c.y + 0.5)
		if lvl > 0 and _terrain.data.get_control_base_id(at) != id:
			_terrain.data.set_control_base_id(at, id)
			painted += 1
	if painted > 0:
		_terrain.data.update_maps(Terrain3DRegion.TYPE_CONTROL, true, false)
	for b in better:
		_edge(b[1], b[0])


## Paints road `r`'s cells `id`. Returns how many it changed.
func _paint(r: Dictionary, id: int) -> int:
	var pts: PackedVector2Array = r["pts"]
	var half: float = r["half_width"] + PAINT_MARGIN
	var changed := 0
	var done := {}
	for i in range(1, pts.size()):
		var a := pts[i - 1]
		var b := pts[i]
		var along := (b - a).normalized()
		var across := Vector2(-along.y, along.x)
		for t in [0.0, 0.5]:
			var p := a.lerp(b, t)
			var off := -half
			while off <= half:
				var c := (p + across * off).floor()
				off += 0.5
				if done.has(c):
					continue
				done[c] = true
				var at := Vector3(c.x + 0.5, 0, c.y + 0.5)
				var now := _terrain.data.get_control_base_id(at)
				if now in PAINTABLE and now != id:
					_terrain.data.set_control_base_id(at, id)
					changed += 1
	return changed


## Lays road `r`'s edging for level `lvl` along both its sides.
func _edge(r: Dictionary, lvl: int) -> void:
	var spec: Array = EDGING[lvl]
	var step: float = spec[0] + spec[3]
	var pts: PackedVector2Array = r["pts"]
	var side: float = r["half_width"] + spec[1] * 0.5
	var others: Array = WorldMap.roads().filter(func(o: Dictionary) -> bool: return o["id"] != r["id"])
	var cells := Roads.patch_cells()
	var places: Array[Transform3D] = []
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
				if _near_other_road(q, others) or WorldMap.in_market(q + across * s * 1.5) 						or cells.has(Vector2i((q + across * s * 1.2).floor())):
					continue  # (a road comes in here, or the market place or a lane opens off it: leave it open)
				var h := _terrain.data.get_height(Vector3(q.x, 0, q.y))
				if is_nan(h) or h < WATER:
					continue
				var basis := Basis(Vector3.UP, atan2(along.x, along.y))
				places.append(Transform3D(basis, Vector3(q.x, h + spec[2] * 0.3, q.y)))
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


func _near_other_road(q: Vector2, others: Array) -> bool:
	for o in others:
		var pts: PackedVector2Array = o["pts"]
		var reach: float = o["half_width"] + 0.8
		for k in range(0, pts.size() - 1, 2):
			if pts[k].distance_squared_to(q) < 400.0 and Geometry2D.get_closest_point_to_segment(q, pts[k], pts[mini(k + 2, pts.size() - 1)]).distance_to(q) < reach:
				return true
	return false
