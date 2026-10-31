extends SceneTree
## Bakes the map editor's layout (data/layout/hearthvale.json, plans/map-editor.md) into
## res://scenes/layout.tscn, which main.tscn instances: the gatherables, hedges and walls, props and
## the odd fixture, stood on the land, the same every run.
##   godot --headless --path . -s res://tools/bake_layout.gd -- --save-root=user://tool_worlds
## Options: --layout=<json> --out=<tscn> --report=<json> (tests bake elsewhere).
## Order: points, then lines, then patches (each patch keeps clear of everything before it, so a
## patch never smothers a point you placed). Patches scatter with NodeSpawner's rules: spacing, off
## paths, roads, water, steep ground, buildings, props.
## Also writes data/layout/baked.json for the editor: where every gatherable ended up and the
## warnings (a patch that found room for fewer than it wanted, a line cut by a road...).
## (No game class names: an -s script compiles before the autoloads exist.)

const LAYOUT := "res://data/layout/hearthvale.json"
const CATALOG := "res://data/layout/catalog.json"
const OUT := "res://scenes/layout.tscn"
const REPORT := "res://data/layout/baked.json"
const WorldMapC := preload("res://scripts/world_map.gd")
## Lines are cut where they'd stand in water, on ground this steep (rise per metre), or this close
## to a road's edge (m).
const WATER := -0.1
const STEEP := 0.6
const ROAD_GAP := 1.2
## A cut line's pieces shorter than this (m) are dropped.
const MIN_RUN := 3.0
## A line keeps patches this far off it (m).
const LINE_CLEAR := 1.6
## A gatherable point sinks this far, like NodeSpawner's.
const SINK := 0.15

var layout: Dictionary
var catalog: Dictionary
var out_path := OUT
var report_path := REPORT
var terrain: Node
var roads: Array = []
## The scene being written: built fresh, out of the tree, so nothing a node makes for itself once
## it's running (a prop's model, a hedge's meshes) gets saved with it.
var out_root: Node3D
## What the patches scatter round, in the running world: the points, and markers along the lines.
var world: Node3D
var keep: Node3D  # keep-clear markers along the lines (not saved)
var SPAWNER: GDScript
var HEDGE_ROW: GDScript
var PROP: GDScript
var FIXTURE: GDScript
var warnings: Array = []
var baked: Array = []  # [x, z, gatherable id]
var scene_ids := {}  # scene path -> gatherable id


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var layout_path := LAYOUT
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--layout="):
			layout_path = arg.trim_prefix("--layout=")
		elif arg.begins_with("--out="):
			out_path = arg.trim_prefix("--out=")
		elif arg.begins_with("--report="):
			report_path = arg.trim_prefix("--report=")
	layout = _read_json(layout_path)
	catalog = _read_json(CATALOG)
	if layout.is_empty() or catalog.is_empty():
		push_error("bake_layout: can't read %s or %s" % [layout_path, CATALOG])
		quit(1)
		return
	for id in catalog["gatherables"]:
		scene_ids[catalog["gatherables"][id]["scene"]] = id

	# (loaded, not preloaded: they name autoloads, which an -s script compiles before)
	SPAWNER = load("res://scripts/node_spawner.gd")
	HEDGE_ROW = load("res://scripts/hedge_row.gd")
	PROP = load("res://scripts/prop.gd")
	FIXTURE = load("res://scripts/fixture.gd")
	root.get_node("Worlds").call("play_fresh")
	while get_first_node_in_group("player") == null:
		await process_frame
	for i in 10:
		await process_frame
	terrain = get_first_node_in_group("terrain")
	roads = WorldMapC.roads()
	var main := current_scene
	var old := main.get_node_or_null("Layout")
	if old:  # (last bake's: everything is placed afresh)
		main.remove_child(old)
		old.free()
		await process_frame

	out_root = Node3D.new()
	out_root.name = "Layout"
	world = Node3D.new()
	world.name = "_Baking"
	main.add_child(world)
	keep = Node3D.new()
	keep.name = "_Keep"
	world.add_child(keep)
	var groups := {}
	for g in ["Points", "Lines", "Patches"]:
		var n := Node3D.new()
		n.name = g
		out_root.add_child(n)
		groups[g] = n

	for p in layout.get("points", []):
		var made := _point(p)
		if made:
			groups["Points"].add_child(made)
			world.add_child(_point(p, false))
	for l in layout.get("lines", []):
		_line(l, groups["Lines"])
	await process_frame  # (props join their groups as they enter the tree)
	for p in layout.get("patches", []):
		await _patch(p, groups["Patches"])
	await physics_frame
	await _check_walkways()
	var water := Node3D.new()
	water.name = "Water"
	out_root.add_child(water)
	for s in layout.get("terrain", []):
		if s.get("type", "") == "pond" and s.has("center"):
			water.add_child(_pond(s))

	main.remove_child(world)
	world.free()
	_own(out_root)
	var scene := PackedScene.new()
	scene.pack(out_root)
	var err := ResourceSaver.save(scene, out_path)
	if err == OK:
		_trim(out_path)
	_write_report()
	print("layout: %d points, %d lines, %d patches, %d gatherables, %d warnings -> %s" % [
		layout.get("points", []).size(), layout.get("lines", []).size(), layout.get("patches", []).size(),
		baked.size(), warnings.size(), out_path])
	for w in warnings:
		print("  ! ", w["msg"])
	out_root.free()
	quit(0 if err == OK else 1)


## Packing an instance of an inherited scene (pine_tree.tscn over tree.tscn) writes every one of its
## properties into the instance, freezing the gatherable's tuning (hits, drops, respawn) into the
## layout. This keeps only where each stands and its save id, so the scenes stay in charge.
func _trim(path: String) -> void:
	var lines := FileAccess.get_file_as_string(path).split("\n")
	var out := PackedStringArray()
	var trimming := false
	for line in lines:
		if line.begins_with("["):
			trimming = line.begins_with("[node") and line.contains(" instance=")
			# (and no unique_ids: they're new every bake, which would make every bake's diff the whole file)
			var cut := line.find(" unique_id=")
			if cut >= 0:
				var end := line.find(" ", cut + 1)
				line = line.substr(0, cut) + (line.substr(end) if end >= 0 else "]")
			out.append(line)
		elif not trimming or line == "" or line.begins_with("transform =") or line.begins_with("save_id ="):
			out.append(line)
	var text := "\n".join(out)
	# then drop the resources nothing uses any more
	var kept := PackedStringArray()
	for line in text.split("\n"):
		if line.begins_with("[ext_resource"):
			var id := line.get_slice("id=\"", 1).get_slice("\"", 0)
			if not text.contains("ExtResource(\"%s\")" % id):
				continue
		kept.append(line)
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("\n".join(kept))


func _own(n: Node) -> void:
	for c in n.get_children():
		c.owner = out_root
		if c.scene_file_path == "":  # (an instanced scene keeps its own insides)
			_own(c)


func _read_json(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var d: Variant = JSON.parse_string(f.get_as_text())
	return d if d is Dictionary else {}


## Each leg of the villagers' walkways (VillagePaths, built from the layout's walkway lines) clear of
## everything a finished village has standing: props, the lamps along the roads, what was just placed
## (a building's own tiers aren't counted: see _only_buildings_in). A blocked one is warned about, at its middle, naming the walkway line nearest it.
func _check_walkways() -> void:
	var paths := get_first_node_in_group("village_paths")
	if paths == null:
		return
	# everything a finished village has standing: every project done (the lamps along the roads, the
	# green's decorations), as tools/test_paths.gd checks it (this world's thrown away, never saved)
	var projects := root.get_node("Projects")
	for p in projects.call("all"):
		projects.call("set_done", p["id"], true)
	for i in 30:
		await physics_frame
	var walks := []
	for l in layout.get("lines", []):
		if catalog["lines"].get(l.get("type", ""), {}).get("walk", false):
			walks.append(l)
	var doors := PackedVector2Array()  # (the network as this layout makes it: VillagePaths.graph)
	for bd in get_nodes_in_group("building"):
		var door := bd.call("door_point") as Node3D if bd.has_method("door_point") else null
		if door:
			doors.append(Vector2(door.global_position.x, door.global_position.z))
	var g: Dictionary = load("res://scripts/village_paths.gd").graph(walks, doors)
	var gp: PackedVector2Array = g["points"]
	for link in g["links"]:
		var a := _ground3(gp[link[0]])
		var b := _ground3(gp[link[1]])
		if paths.call("is_clear", a, b) or _only_buildings_in(a, b):
			continue
		var mid := Vector2((a.x + b.x) * 0.5, (a.z + b.z) * 0.5)
		var ref := ""
		var best := INF
		for l in walks:
			var pts := _pts(l["points"])
			for i in pts.size() - 1:
				var d := Geometry2D.get_closest_point_to_segment(mid, pts[i], pts[i + 1]).distance_to(mid)
				if d < best:
					best = d
					ref = String(l["id"])
		_warn("walkway %s is blocked near (%.0f, %.0f): something stands in it" % [ref, mid.x, mid.y], mid, ref)


## Whether all that stands in the leg a-b belongs to a building (its tiers change: a ruin's boarded
## door opens when it's built, and tools/test_paths.gd walks every top tier), so it isn't a blockage.
func _only_buildings_in(a: Vector3, b: Vector3) -> bool:
	var space := (world as Node3D).get_world_3d().direct_space_state
	var q := PhysicsShapeQueryParameters3D.new()
	var ball := SphereShape3D.new()
	ball.radius = 0.3
	q.shape = ball
	q.collision_mask = 1
	var any := false
	for k in 21:
		var p := a.lerp(b, k / 20.0)
		q.transform = Transform3D(Basis.IDENTITY, Vector3(p.x, terrain.data.get_height(p) + 0.7, p.z))
		for r in space.intersect_shape(q, 8):
			var c: Node = r["collider"]
			if c is Terrain3D or c.get_class() == "Terrain3D":
				continue
			var n := c
			while n and not n.is_in_group("building"):
				n = n.get_parent()
			if n == null:
				return false
			any = true
	return any


func _ground3(p: Vector2) -> Vector3:
	return Vector3(p.x, terrain.data.get_height(Vector3(p.x, 0, p.y)), p.y)


func _warn(msg: String, at: Vector2, ref := "") -> void:
	warnings.append({"msg": msg, "at": [snappedf(at.x, 0.1), snappedf(at.y, 0.1)], "ref": ref})


# --- the land ------------------------------------------------------------------------------------

func _h(p: Vector2) -> float:
	var h: float = terrain.data.get_height(Vector3(p.x, 0, p.y))
	return 0.0 if is_nan(h) else h


func _slope(p: Vector2) -> float:
	var dx := _h(p + Vector2(1, 0)) - _h(p - Vector2(1, 0))
	var dz := _h(p + Vector2(0, 1)) - _h(p - Vector2(0, 1))
	return Vector2(dx, dz).length() * 0.5


func _road_gap(p: Vector2) -> float:
	var best := INF
	for r in roads:
		var pts: PackedVector2Array = r["pts"]
		for k in range(0, pts.size() - 1, 2):
			var q := Geometry2D.get_closest_point_to_segment(p, pts[k], pts[mini(k + 2, pts.size() - 1)])
			best = minf(best, p.distance_to(q) - float(r["half_width"]))
	return best


static func _v2(a: Array) -> Vector2:
	return Vector2(float(a[0]), float(a[1]))


static func _pts(a: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for q in a:
		out.append(_v2(q))
	return out


static func _vec3(a: Variant, fallback := Vector3.ONE) -> Vector3:
	return Vector3(float(a[0]), float(a[1]), float(a[2])) if a is Array and a.size() == 3 else fallback


# --- points ----------------------------------------------------------------------------------------

## The point's node, or null (with a warning) if the catalog has no such thing. `report`: this is
## the copy that's saved, so it goes in the report (the other stands in the world while baking).
func _point(p: Dictionary, report := true) -> Node3D:
	var type: String = p.get("type", "")
	var at := _v2(p["at"])
	var yaw := deg_to_rad(float(p.get("yaw", 0.0)))
	var id: String = p.get("id", type)
	var node: Node3D
	if catalog["gatherables"].has(type):
		node = (load(catalog["gatherables"][type]["scene"]) as PackedScene).instantiate()
		node.set("save_id", StringName(p.get("save_id", "pt_" + id)))
		node.position = Vector3(at.x, _h(at) - SINK, at.y)
		if report:
			baked.append([snappedf(at.x, 0.01), snappedf(at.y, 0.01), type])
	elif catalog["props"].has(type):
		var c: Dictionary = catalog["props"][type]
		node = StaticBody3D.new()
		node.set_script(PROP)
		node.set("model", load(c["model"]))
		node.set("snap_to_ground", true)
		node.set("collide", c.get("collide", true))
		node.set("own_materials", c.get("own_materials", true))
		node.set("model_scale", _vec3(p.get("scale", c.get("scale")), Vector3.ONE))
		node.position = Vector3(at.x, 0, at.y)
	elif catalog["fixtures"].has(type):
		node = Node3D.new()
		node.set_script(FIXTURE)
		node.set("model", load(catalog["fixtures"][type]["model"]))
		node.position = Vector3(at.x, 0, at.y)
	else:
		if report:
			_warn("point %s: no %s in the catalog" % [id, type], at, id)
		return null
	node.name = id.to_pascal_case()
	node.rotation.y = yaw
	if not report:
		return node
	if _h(at) < WATER:
		_warn("point %s stands in water" % id, at, id)
	elif _slope(at) > STEEP:
		_warn("point %s stands on steep ground" % id, at, id)
	elif _road_gap(at) < 0.5:
		_warn("point %s stands on a road" % id, at, id)
	return node


# --- lines -----------------------------------------------------------------------------------------

func _line(l: Dictionary, parent: Node3D) -> void:
	var type: String = l.get("type", "hedge")
	var id: String = l.get("id", type)
	var pts := _pts(l.get("points", []))
	if not catalog["lines"].has(type) or pts.size() < 2:
		_warn("line %s: no %s in the catalog, or under two points" % [id, type], pts[0] if pts.size() > 0 else Vector2.ZERO, id)
		return
	var c: Dictionary = catalog["lines"][type]
	if c.get("walk", false):
		return  # a walkway: nothing to build, the villagers read it (VillagePaths)
	var gate_every := float(l.get("gate_every", 0.0))
	var gate := float(l.get("gate", 4.0))
	# walk it a metre at a time, cutting it where it can't stand and at the gates
	var walk := PackedVector2Array()
	for i in pts.size() - 1:
		var n := maxi(int(ceil(pts[i].distance_to(pts[i + 1]))), 1)
		for k in n:
			walk.append(pts[i].lerp(pts[i + 1], float(k) / n))
	walk.append(pts[-1])
	var runs: Array[PackedVector2Array] = []
	var run := PackedVector2Array()
	var walked := 0.0
	var cut := 0
	for i in walk.size():
		var q := walk[i]
		if i > 0:
			walked += q.distance_to(walk[i - 1])
		var ok: bool = not l.get("clip", true) or (_h(q) > WATER and _slope(q) < STEEP and _road_gap(q) > ROAD_GAP)
		if not ok:
			cut += 1
		# a gate: a `gate`-wide gap after every `gate_every` m of line
		var in_gate := gate_every > 0.0 and fmod(walked, gate_every + gate) >= gate_every
		if ok and not in_gate:
			run.append(q)
		elif not run.is_empty():
			runs.append(run)
			run = PackedVector2Array()
	runs.append(run)
	var made := 0
	for r in runs:
		if r.size() < 2 or _length(r) < MIN_RUN:
			continue
		made += 1
		var row := Node3D.new()
		row.set_script(HEDGE_ROW)
		row.name = "%s_%d" % [id.to_pascal_case(), made]
		row.set("model", load(c["model"]))
		row.set("points", _simplify(r, 0.15))
		row.set("model_scale", _vec3(c.get("scale")))
		row.set("spacing", float(c.get("spacing", 1.7)))
		parent.add_child(row)
		for k in range(0, r.size(), 2):
			_keep_clear(r[k], LINE_CLEAR)
	if cut > 0:
		_warn("line %s is cut where it crosses a road, water or a steep bank" % id, pts[0], id)
	if made == 0:
		_warn("line %s found nowhere to stand" % id, pts[0], id)


static func _length(r: PackedVector2Array) -> float:
	var s := 0.0
	for i in r.size() - 1:
		s += r[i].distance_to(r[i + 1])
	return s


## Drops points that sit within `tol` m of the straight line between their neighbours.
static func _simplify(r: PackedVector2Array, tol: float) -> PackedVector2Array:
	if r.size() < 3:
		return r
	var out := PackedVector2Array([r[0]])
	var anchor := 0
	for i in range(2, r.size()):
		for k in range(anchor + 1, i):
			if Geometry2D.get_closest_point_to_segment(r[k], r[anchor], r[i]).distance_to(r[k]) > tol:
				out.append(r[i - 1])
				anchor = i - 1
				break
	out.append(r[-1])
	return out


func _keep_clear(p: Vector2, radius: float) -> void:
	var m := Node3D.new()
	m.set_script(_keep_script())
	m.set_meta("spot", Vector3(p.x, p.y, radius))
	keep.add_child(m)


var _ks: GDScript
func _keep_script() -> GDScript:
	if _ks == null:
		_ks = GDScript.new()
		_ks.source_code = "extends Node3D\nfunc _ready() -> void:\n\tadd_to_group(&\"keep_clear\")\nfunc keep_clear() -> Vector3:\n\treturn get_meta(\"spot\")\n"
		_ks.reload()
	return _ks


# --- patches ---------------------------------------------------------------------------------------

func _patch(p: Dictionary, parent: Node3D) -> void:
	var id: String = p.get("id", "patch")
	var count := int(p.get("count", 0))
	var items: Dictionary = p.get("items", {})
	var sp := Node3D.new()
	sp.set_script(SPAWNER)
	sp.name = "_" + id
	sp.set("count", count)
	sp.set("seed", int(p.get("seed", hash(id))))
	sp.set("save_prefix", id)
	sp.set("spacing", float(p.get("spacing", 4.5)))
	var centre := Vector2.ZERO
	if p.get("shape", "polygon") == "circle":
		centre = _v2(p["center"])
		sp.set("ring", Vector4(centre.x, centre.y, float(p.get("inner", 0.0)), float(p["radius"])))
		var r := float(p["radius"])
		sp.set("area", Rect2(centre - Vector2(r, r), Vector2(r, r) * 2.0))  # (the ring's draw maps over it)
	else:
		var poly := _pts(p.get("points", []))
		if poly.size() < 3:
			_warn("patch %s has under three corners" % id, Vector2.ZERO, id)
			sp.free()
			return
		sp.set("polygon", poly)
		for q in poly:
			centre += q / poly.size()
	for g in p.get("ground", []):
		if catalog["grounds"].has(g):
			sp.allowed_ids.append(int(catalog["grounds"][g]))
	for item in items:
		if not catalog["gatherables"].has(item):
			_warn("patch %s: no %s in the catalog" % [id, item], centre, id)
			continue
		sp.call("add_entry", load(catalog["gatherables"][item]["scene"]), float(items[item]))
	if count <= 0 or sp.entries.is_empty():
		sp.free()
		return
	world.add_child(sp)  # (it stays: the next patches keep clear of its nodes)
	if not sp.get("done"):
		await sp.finished
		await process_frame  # (out of its signal before anything's freed)
	var holder := Node3D.new()
	holder.name = id.to_pascal_case()
	parent.add_child(holder)
	var placed := 0
	for n in sp.get_children():
		var copy := (load(n.scene_file_path) as PackedScene).instantiate() as Node3D
		copy.name = n.name
		copy.set("save_id", n.get("save_id"))
		copy.set("model", n.get("model"))  # (a variant, if it wore one)
		copy.transform = (n as Node3D).global_transform
		holder.add_child(copy)
		placed += 1
		var g := copy.position
		baked.append([snappedf(g.x, 0.01), snappedf(g.z, 0.01), scene_ids.get(n.scene_file_path, "?")])
	if placed < count:
		_warn("patch %s found room for %d of %d" % [id, placed, count], centre, id)


# --- ponds ---------------------------------------------------------------------------------------------

## The water in a terrain pond (the generator digs its bowl): built like the ponds in main.tscn, a
## WaterBody with its volume, surface, reeds and lilies, and fish if it says so.
func _pond(s: Dictionary) -> Node3D:
	var c := _v2(s["center"])
	var span := float(s["radius"]) * 2.0 + 4.0
	var body := Area3D.new()
	body.name = String(s.get("id", "pond")).to_pascal_case()
	body.set_script(load("res://scripts/water_body.gd"))
	body.position = Vector3(c.x, 0, c.y)
	body.collision_layer = 0
	body.collision_mask = 0
	var vol := CollisionShape3D.new()
	vol.name = "Volume"
	vol.position = Vector3(0, -1, 0)
	var box := BoxShape3D.new()
	box.size = Vector3(span, 3, span)
	vol.shape = box
	body.add_child(vol)
	var dressing := Node3D.new()
	dressing.name = "Dressing"
	dressing.set_script(load("res://scripts/pond_dressing.gd"))
	dressing.set("seed", hash(s.get("id", "pond")) % 1000)
	dressing.set("reed_clumps", int(span * 0.35))
	dressing.set("lily_pads", int(span * 0.45))
	dressing.set("stones", int(span * 0.4))
	body.add_child(dressing)
	if s.get("fish", true):
		var fish := Node3D.new()
		fish.name = "Fish"
		fish.set_script(load("res://scripts/fish_pond.gd"))
		var perch: Resource = load("res://data/fish/perch.tres")
		var schools: Array = fish.get("schools")  # (a typed array: filled, not replaced)
		for school in [perch, perch, load("res://data/fish/trout.tres")]:
			schools.append(school)
		body.add_child(fish)
	var surface := MeshInstance3D.new()
	surface.name = "Surface"
	surface.position = Vector3(0, -0.15, 0)
	surface.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var plane := PlaneMesh.new()
	plane.size = Vector2(span, span)
	plane.subdivide_width = int(span) - 1
	plane.subdivide_depth = int(span) - 1
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/water.gdshader")
	plane.material = mat
	surface.mesh = plane
	body.add_child(surface)
	return body


# --- the report --------------------------------------------------------------------------------------

func _write_report() -> void:
	var f := FileAccess.open(report_path, FileAccess.WRITE)
	if f == null:
		push_error("bake_layout: can't write %s" % report_path)
		return
	f.store_string(JSON.stringify({"baked": Time.get_datetime_string_from_system(), "nodes": baked, "warnings": warnings}, "\t"))
