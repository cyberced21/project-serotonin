extends SceneTree
## Places the country round Hearthvale (plans/world-pass.md, phase 6) from the land, once, and saves
## it as res://scenes/country.tscn (main.tscn instances it): so it never moves between runs.
##   godot --headless --path . -s res://tools/place_country.gd -- --save-root=user://tool_worlds
## What goes where:
##   fields   hedges along both sides of the roads out of the village, between FIELD_IN and
##            FIELD_OUT m from the green, stone walls on an arc at FIELD_MID and hedges on one at
##            FIELD_OUT: the field edges, with a gate (a gap) every GATE_EVERY m
##   groves   a copse of gatherable trees in each wedge between the roads, out on the bowl's slopes
##   oaks     a lone old oak on each of the highest knolls round the rim
##   outcrops rocks (and a little iron and coal) where the hillside steepens
##   creek    thickets and wildflowers along the creek's banks
##   old      a standing stone, a wayside shrine, a bench at a view, a ruined farmstead
## Everything keeps off the roads, the creek, the water, the village's buildings, fixtures and props,
## steep ground, and the other places (only the unnamed country and the village's edge).
## (No game class names: an -s script compiles before the autoloads exist.)

const OUT := "res://scenes/country.tscn"
const WorldMapC := preload("res://scripts/world_map.gd")
const SEED := 20261030
const C := Vector2(128, 128)
const FIELD_IN := 84.0
const FIELD_MID := 115.0
const FIELD_OUT := 150.0
const GATE_EVERY := 42.0
const GATE := 4.0
const STEP := 1.6
const ROAD_HEDGE := 2.8  # off the road's edge
const STEEP := 0.45  # rise per metre: no hedge, no tree
const WATER := -0.1

const HEDGE := preload("res://models/country/hedge.glb")
const WALL := preload("res://models/country/wall.glb")
const TREES := ["res://scenes/tree.tscn", "res://scenes/oak_tree.tscn", "res://scenes/birch_tree.tscn"]
const ROCK := "res://scenes/rock.tscn"
const ORES := ["res://scenes/iron_rock.tscn", "res://scenes/coal_rock.tscn"]

var rng := RandomNumberGenerator.new()
var terrain: Node
var biome: Node
var keep_out: Array[Vector3] = []  # (x, z, radius)
var roads: Array = []
var creek := PackedVector2Array()
var out_root: Node3D
var placed: Array[Vector3] = []  # this run's own things, kept apart too
var counts := {}


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	rng.seed = SEED
	root.get_node("Worlds").call("play_fresh")
	while get_first_node_in_group("player") == null:
		await process_frame
	for i in 10:
		await process_frame
	terrain = get_first_node_in_group("terrain")
	biome = root.get_node("Biome")
	var wm: GDScript = load("res://scripts/world_map.gd")
	roads = wm.call("roads")
	creek = wm.call("creek")
	_collect_keep_out()
	out_root = Node3D.new()
	out_root.name = "Country"
	_fields()
	_groves()
	_oaks()
	_outcrops()
	_creek_banks()
	_old_things()
	for n in out_root.get_children():
		_own(n)
	var scene := PackedScene.new()
	scene.pack(out_root)
	ResourceSaver.save(scene, OUT)
	print("country: ", counts, " -> ", OUT)
	out_root.free()
	quit()


func _own(n: Node) -> void:
	n.owner = out_root
	if n.scene_file_path != "":
		return  # (an instanced scene keeps its own insides)
	for c in n.get_children():
		_own(c)


# --- what the land's like -------------------------------------------------------------------

func _h(p: Vector2) -> float:
	var h: float = terrain.data.get_height(Vector3(p.x, 0, p.y))
	return 0.0 if is_nan(h) else h


func _slope(p: Vector2) -> float:
	var dx := _h(p + Vector2(1, 0)) - _h(p - Vector2(1, 0))
	var dz := _h(p + Vector2(0, 1)) - _h(p - Vector2(0, 1))
	return Vector2(dx, dz).length() * 0.5


func _country(p: Vector2) -> bool:
	var b: StringName = biome.call("biome_at", Vector3(p.x, _h(p), p.y))
	return b == &"" or b == &"hearthvale"


func _road_gap(p: Vector2, skip := -1) -> float:
	var best := INF
	for i in roads.size():
		if i == skip:
			continue
		var r: Dictionary = roads[i]
		var pts: PackedVector2Array = r["pts"]
		for k in range(0, pts.size() - 1, 2):
			var q := Geometry2D.get_closest_point_to_segment(p, pts[k], pts[mini(k + 2, pts.size() - 1)])
			best = minf(best, p.distance_to(q) - float(r["half_width"]))
	return best


func _creek_gap(p: Vector2) -> float:
	var best := INF
	for k in range(0, creek.size() - 1, 3):
		best = minf(best, p.distance_to(Geometry2D.get_closest_point_to_segment(p, creek[k], creek[mini(k + 3, creek.size() - 1)])))
	return best


func _clear(p: Vector2, r: float) -> bool:
	for k in keep_out:
		if p.distance_to(Vector2(k.x, k.y)) < k.z + r:
			return false
	for k in placed:
		if p.distance_to(Vector2(k.x, k.y)) < k.z + r:
			return false
	return true


## Fine for something of radius `r`: the country, dry, not steep, off roads and the creek, clear.
func _ok(p: Vector2, r: float, road_margin := 2.0, skip_road := -1) -> bool:
	return _country(p) and _h(p) > WATER and _slope(p) < STEEP and _road_gap(p, skip_road) > r + road_margin \
			and _creek_gap(p) > r + 4.0 and _clear(p, r)


func _collect_keep_out() -> void:
	for b in get_nodes_in_group("building"):
		var g := (b as Node3D).global_position
		keep_out.append(Vector3(g.x, g.z, float(b.call("footprint_radius")) + 3.0))
	for f in get_nodes_in_group("fixture"):
		if _in_country_scene(f):
			continue
		var g := (f as Node3D).global_position
		keep_out.append(Vector3(g.x, g.z, float(f.call("footprint_radius")) + 3.0))
	for p in get_nodes_in_group("prop"):
		if _in_country_scene(p):
			continue
		var g := (p as Node3D).global_position
		keep_out.append(Vector3(g.x, g.z, float(p.call("footprint_radius")) + 1.5))
	for n in get_nodes_in_group("gatherable"):
		if _in_country_scene(n):
			continue
		var g := (n as Node3D).global_position
		keep_out.append(Vector3(g.x, g.z, 3.0))
	keep_out.append(Vector3(46, 66, 42))  # the clearing
	for site in [[WorldMapC.MILL_SITE, 16.0], [WorldMapC.ORCHARD_SITE, 26.0], [WorldMapC.SHEPHERD_SITE, 24.0]]:  # the new places
		keep_out.append(Vector3(site[0].x, site[0].y, site[1]))
	keep_out.append(Vector3(C.x, C.y, 74))  # the village's flat


func _in_country_scene(n: Node) -> bool:
	while n:
		if n.name == &"Country":
			return true
		n = n.get_parent()
	return false


# --- fields: hedges and walls ------------------------------------------------------------------

func _fields() -> void:
	# along both sides of each road out of the village, between FIELD_IN and FIELD_OUT
	for i in roads.size():
		var r: Dictionary = roads[i]
		var pts: PackedVector2Array = r["pts"]
		if pts.size() < 4 or pts[0].distance_to(C) > FIELD_IN + 10.0:
			continue
		for side in [-1.0, 1.0]:
			var line := PackedVector2Array()
			for k in range(0, pts.size() - 1, 2):
				var d := C.distance_to(pts[k])
				if d < FIELD_IN or d > FIELD_OUT:
					continue
				var along := (pts[mini(k + 1, pts.size() - 1)] - pts[k]).normalized()
				line.append(pts[k] + Vector2(-along.y, along.x) * side * (float(r["half_width"]) + ROAD_HEDGE))
			_runs(line, HEDGE, Vector3.ONE, 1.7, "hedge", i)
	# the arcs: stone walls at FIELD_MID, hedges at FIELD_OUT
	for arc in [[FIELD_MID, WALL, Vector3(1.0, 0.55, 1.0), 1.95, "wall"], [FIELD_OUT, HEDGE, Vector3.ONE, 1.7, "hedge"]]:
		var radius: float = arc[0]
		var line := PackedVector2Array()
		var n := int(TAU * radius / STEP)
		for k in n + 1:
			var a := TAU * k / n
			line.append(C + Vector2(sin(a), -cos(a)) * radius)
		_runs(line, arc[1], arc[2], arc[3], arc[4], -1)


## Splits `line` into runs where every point is fine, with a gate every GATE_EVERY m, and adds a
## HedgeRow for each run long enough.
func _runs(line: PackedVector2Array, model: PackedScene, scale: Vector3, spacing: float, kind: String, road: int) -> void:
	var run := PackedVector2Array()
	var since_gate := rng.randf_range(10.0, GATE_EVERY)
	var k := 0
	while k < line.size():
		var p := line[k]
		var ok := _country(p) and _h(p) > WATER and _slope(p) < STEEP and _creek_gap(p) > 5.0 and _clear(p, 0.8) \
				and _road_gap(p, road) > 1.6
		if ok and k > 0:
			since_gate -= p.distance_to(line[k - 1])
		if ok and since_gate < 0.0:  # a gate: a gap in the run, GATE wide
			since_gate = GATE_EVERY + rng.randf_range(-8.0, 8.0)
			_flush(run, model, scale, spacing, kind)
			run = PackedVector2Array()
			var skipped := 0.0
			while k + 1 < line.size() and skipped < GATE:
				skipped += line[k + 1].distance_to(line[k])
				k += 1
		elif ok:
			run.append(p)
		else:
			_flush(run, model, scale, spacing, kind)
			run = PackedVector2Array()
		k += 1
	_flush(run, model, scale, spacing, kind)


func _flush(run: PackedVector2Array, model: PackedScene, scale: Vector3, spacing: float, kind: String) -> void:
	if run.size() < 4:
		return
	var row := Node3D.new()
	row.set_script(load("res://scripts/hedge_row.gd"))
	row.name = "%s%d" % [kind.to_pascal_case(), counts.get(kind, 0) + 1]
	row.set("model", model)
	row.set("points", run)
	row.set("model_scale", scale)
	row.set("spacing", spacing)
	out_root.add_child(row)
	counts[kind] = counts.get(kind, 0) + 1
	for k in range(0, run.size(), 2):
		placed.append(Vector3(run[k].x, run[k].y, 1.0))


# --- groves, oaks, outcrops ---------------------------------------------------------------------

func _gatherable(path: String, p: Vector2, kind: String, yaw := 0.0) -> void:
	var n := (load(path) as PackedScene).instantiate() as Node3D
	counts[kind] = counts.get(kind, 0) + 1
	n.name = "%s%d" % [kind.to_pascal_case(), counts[kind]]
	n.set("save_id", StringName("country_%s_%d" % [kind, counts[kind]]))
	n.position = Vector3(p.x, _h(p), p.y)
	n.rotation.y = yaw
	out_root.add_child(n)
	placed.append(Vector3(p.x, p.y, 2.5))


## A sector between two roads' bearings (degrees from north): a spot out on the slopes in it.
func _groves() -> void:
	for a in [45.0, 112.0, 160.0, 230.0, 292.0, 336.0, 20.0, 250.0]:
		for attempt in 30:
			var r := rng.randf_range(160.0, 230.0)
			var ang := deg_to_rad(a + rng.randf_range(-12.0, 12.0))
			var centre := C + Vector2(sin(ang), -cos(ang)) * r
			if not _ok(centre, 12.0, 4.0):
				continue
			var n := 0
			for tries in 60:
				if n >= 7:
					break
				var p := centre + Vector2.from_angle(rng.randf() * TAU) * sqrt(rng.randf()) * 13.0
				if _ok(p, 2.2, 2.0):
					_gatherable(TREES[rng.randi() % TREES.size()], p, "grove_tree", rng.randf() * TAU)
					n += 1
			break


func _oaks() -> void:
	var tops: Array[Vector2] = []
	for k in 400:  # the highest knolls round the rim, well apart
		var ang := rng.randf() * TAU
		var p := C + Vector2(sin(ang), -cos(ang)) * rng.randf_range(170.0, 245.0)
		if not _ok(p, 3.0, 4.0):
			continue
		var is_top := true
		for d in [Vector2(6, 0), Vector2(-6, 0), Vector2(0, 6), Vector2(0, -6)]:
			if _h(p + d) > _h(p):
				is_top = false
		if not is_top:
			continue
		if tops.any(func(t: Vector2) -> bool: return t.distance_to(p) < 90.0):
			continue
		tops.append(p)
		if tops.size() == 4:
			break
	for p in tops:
		_gatherable("res://scenes/oak_tree.tscn", p, "lone_oak", rng.randf() * TAU)


func _outcrops() -> void:
	var sites := 0
	for k in 600:
		if sites >= 5:
			break
		var ang := rng.randf() * TAU
		var p := C + Vector2(sin(ang), -cos(ang)) * rng.randf_range(150.0, 240.0)
		var s := _slope(p)
		if s < 0.18 or s > 0.5 or not _country(p) or _road_gap(p) < 10.0 or _creek_gap(p) < 10.0 or not _clear(p, 8.0):
			continue
		sites += 1
		var n := 0
		for tries in 40:
			if n >= 5:
				break
			var q := p + Vector2.from_angle(rng.randf() * TAU) * sqrt(rng.randf()) * 7.0
			if _country(q) and _slope(q) < 0.6 and _clear(q, 1.6) and _road_gap(q) > 3.0:
				_gatherable(ORES[sites % 2] if n == 0 else ROCK, q, "outcrop_rock", rng.randf() * TAU)
				n += 1


# --- the creek's banks ----------------------------------------------------------------------------

func _prop(model: String, p: Vector2, yaw: float, kind: String, scale := Vector3.ONE, collide := false, own := true) -> void:
	var prop := StaticBody3D.new()
	prop.set_script(load("res://scripts/prop.gd"))
	counts[kind] = counts.get(kind, 0) + 1
	prop.name = "%s%d" % [kind.to_pascal_case(), counts[kind]]
	prop.set("model", load(model))
	prop.set("snap_to_ground", true)
	prop.set("collide", collide)
	prop.set("own_materials", own)
	prop.set("model_scale", scale)
	prop.position = Vector3(p.x, 0, p.y)
	prop.rotation.y = yaw
	out_root.add_child(prop)
	placed.append(Vector3(p.x, p.y, 1.2))


func _creek_banks() -> void:
	# (not bushes.glb nor flower_bushes.glb: their meshes draw far from where they're put)
	var picks := ["res://models/country/bush_with_flowers.glb", "res://models/country/flowers.glb",
		"res://models/country/bush_with_berries.glb", "res://models/country/flower_group.glb"]
	var k := 0
	var i := 30
	while i < creek.size() - 3:
		var p := creek[i]
		var along := (creek[i + 2] - p).normalized()
		var side := 1.0 if rng.randf() < 0.5 else -1.0
		var q := p + Vector2(-along.y, along.x) * side * rng.randf_range(4.5, 6.5)
		var b: StringName = biome.call("biome_at", Vector3(q.x, _h(q), q.y))
		if (b == &"" or b == &"hearthvale" or b == &"stillwater") and _h(q) > WATER and _road_gap(q) > 3.0 and _clear(q, 1.2):
			_prop(picks[k % picks.size()], q, atan2(along.x, along.y), "bank_plant")
			k += 1
		i += rng.randi_range(14, 24)


# --- the old things on a walk ------------------------------------------------------------------------

func _near_ok(around: Vector2, r: float, reach: float, level := INF) -> Vector2:
	for tries in 300:
		var p := around + Vector2.from_angle(rng.randf() * TAU) * rng.randf() * reach
		if _ok(p, r, 3.0) and _rise(p, r) < level:
			return p
	return Vector2.INF


## How far the ground rises and falls over a circle of radius `r` round `p` (m).
func _rise(p: Vector2, r: float) -> float:
	var lo := INF
	var hi := -INF
	for a in 12:
		for rr in [0.0, r * 0.5, r]:
			var h := _h(p + Vector2.from_angle(a * TAU / 12.0) * rr)
			lo = minf(lo, h)
			hi = maxf(hi, h)
	return hi - lo


func _old_things() -> void:
	# a standing stone on the north-east rim, a shrine where the lake road leaves the bowl, a bench
	# looking back over the bowl from the south rim, a ruined farmstead out to the north-east
	var stone := _near_ok(C + Vector2(150, -120), 2.0, 40.0)
	if stone != Vector2.INF:
		_prop("res://models/scenery/boulder_big.glb", stone, rng.randf() * TAU, "standing_stone", Vector3(0.7, 2.6, 0.6), true, false)
	var lake_road: PackedVector2Array = []
	for r in roads:
		if r["id"] == &"lake_road":
			lake_road = r["pts"]
	if lake_road.size() > 60:
		var at := lake_road[60]
		var along := (lake_road[62] - at).normalized()
		var side := at + Vector2(-along.y, along.x) * 4.5
		if _clear(side, 1.0):
			_prop("res://models/country/shrine.glb", side, atan2(-along.y, along.x), "shrine", Vector3.ONE, true)
	var view := _near_ok(C + Vector2(0, 205), 1.5, 30.0)
	if view != Vector2.INF:
		var to_green := C - view
		_prop("res://models/country/bench_2.glb", view, atan2(to_green.x, to_green.y) + PI, "view_bench", Vector3.ONE, true)
	var farm := _near_ok(C + Vector2(120, -60), 8.0, 70.0, 0.8)  # (on level ground: a ruin on a slope floats)
	if farm != Vector2.INF:
		var fx := Node3D.new()
		fx.set_script(load("res://scripts/fixture.gd"))
		fx.name = "RuinedFarmstead"
		fx.set("model", load("res://models/village/fx_ruined_cottage.gltf"))
		fx.position = Vector3(farm.x, 0, farm.y)
		fx.rotation.y = rng.randf() * TAU
		out_root.add_child(fx)
		placed.append(Vector3(farm.x, farm.y, 8.0))
		counts["farmstead"] = 1
		var yard := PackedVector2Array()  # its tumbledown yard wall
		for k in 9:
			var a := fx.rotation.y + PI * 0.6 + k * 0.22
			yard.append(farm + Vector2(sin(a), cos(a)) * 9.0)
		_flush(yard, WALL, Vector3(1.0, 0.4, 1.0), 2.1, "farm_wall")
