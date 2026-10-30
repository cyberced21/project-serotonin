extends SceneTree
## Turns the world as it was before the map editor (plans/map-editor.md, phase 1) into its layout,
## data/layout/hearthvale.json: the biomes' NodeSpawners become patches, scenes/country.tscn's
## groves and outcrops become patches, its hedge rows and walls lines, its lone oaks, props and
## ruin points, and main.tscn's hand-placed gatherables (under "Nodes") points that keep their save
## ids. Run once; from then on the layout is the source and the editor changes it.
##   godot --headless --path . -s res://tools/import_layout.gd -- --save-root=user://tool_worlds
## (No game class names: an -s script compiles before the autoloads exist.)

const OUT := "res://data/layout/hearthvale.json"
const CATALOG := "res://data/layout/catalog.json"
const BIOMES := ["res://scenes/biomes/pinewood.tscn", "res://scenes/biomes/goldmeadow.tscn", "res://scenes/biomes/quarry.tscn"]
const COUNTRY := "res://scenes/country.tscn"
const MAIN := "res://scenes/main.tscn"
const SPAWNER := "res://scripts/node_spawner.gd"
const HEDGE_ROW := "res://scripts/hedge_row.gd"

var catalog: Dictionary
var scene_ids := {}  # scene path -> gatherable id
var grounds := {}  # texture id -> ground name
var patches: Array = []
var lines: Array = []
var points: Array = []


func _initialize() -> void:
	catalog = JSON.parse_string(FileAccess.get_file_as_string(CATALOG))
	for id in catalog["gatherables"]:
		scene_ids[catalog["gatherables"][id]["scene"]] = id
	for g in catalog["grounds"]:
		grounds[int(catalog["grounds"][g])] = g
	for path in BIOMES:
		var scene := (load(path) as PackedScene).instantiate()
		for n in scene.find_children("*", "Node3D", true, false):
			if n.get_script() and n.get_script().resource_path == SPAWNER:
				_spawner(n, path.get_file().get_basename())
		scene.free()
	_country()
	_main_nodes()
	_write()
	quit()


static func _r(v: float) -> float:
	return snappedf(v, 0.1)


static func _xy(p: Vector2) -> Array:
	return [_r(p.x), _r(p.y)]


static func _poly(pts: PackedVector2Array) -> Array:
	var out := []
	for p in pts:
		out.append(_xy(p))
	return out


# --- the biomes' spawners --------------------------------------------------------------------------

func _items(sp: Node) -> Dictionary:
	var items := {}
	for e in sp.get("entries"):
		var id: String = scene_ids.get(e.scene.resource_path, "")
		if id == "":
			push_warning("import: %s isn't in the catalog" % e.scene.resource_path)
			continue
		# (a spawner's core-to-edge slide becomes its average)
		var w: float = e.weight if e.edge_weight < 0.0 else (e.weight + e.edge_weight) * 0.5
		items[id] = items.get(id, 0.0) + _r(w)
	return items


func _ground(sp: Node) -> Array:
	var out := []
	for id in sp.get("allowed_ids"):
		out.append(grounds.get(id, "grass"))
	return out


func _spawner(sp: Node, biome: String) -> void:
	var base := {
		"items": _items(sp), "seed": sp.get("seed"), "spacing": sp.get("spacing"), "ground": _ground(sp),
		"biome": biome,
	}
	var count: int = sp.get("count")
	var ring: Vector4 = sp.get("ring")
	var area: Rect2 = sp.get("area")
	var ellipse: Vector4 = sp.get("ellipse")
	var hotspots: PackedVector3Array = sp.get("hotspots")
	var prefix: String = sp.get("save_prefix")
	if ring.w > 0.0:
		patches.append(_with(base, {"id": prefix, "name": "%s %s" % [biome.capitalize(), sp.name],
				"shape": "circle", "center": [_r(ring.x), _r(ring.y)], "radius": _r(ring.w), "inner": _r(ring.z), "count": count}))
		return
	var outline := PackedVector2Array([area.position, Vector2(area.end.x, area.position.y), area.end, Vector2(area.position.x, area.end.y)])
	if ellipse.z > 0.0:  # the ellipse, inside the area
		var e := PackedVector2Array()
		for k in 40:
			var a := TAU * k / 40.0
			e.append(Vector2(ellipse.x + cos(a) * ellipse.z, ellipse.y + sin(a) * ellipse.w))
		var cut := Geometry2D.intersect_polygons(e, outline)
		if not cut.is_empty():
			outline = cut[0]
	# the hotspots (glades, the trail) become patches of their own, as full as they'll hold
	var rest := count
	if not hotspots.is_empty():
		var share: float = sp.get("hotspot_share")
		var each := int(round(count * share / hotspots.size()))
		var spacing: float = sp.get("spacing")
		for i in hotspots.size():
			var h := hotspots[i]
			var room := int(PI * h.z * h.z / (spacing * spacing * 1.6))
			var n := mini(each, room)
			rest -= n
			patches.append(_with(base, {"id": "%s_spot%d" % [prefix, i + 1], "name": "%s %s, spot %d" % [biome.capitalize(), sp.name, i + 1],
					"shape": "circle", "center": [h.x, h.y], "radius": h.z, "inner": 0.0, "count": n, "seed": int(sp.get("seed")) * 100 + i}))
	patches.append(_with(base, {"id": prefix, "name": "%s %s" % [biome.capitalize(), sp.name],
			"shape": "polygon", "points": _poly(outline), "count": rest}))


static func _with(a: Dictionary, b: Dictionary) -> Dictionary:
	var out := a.duplicate(true)
	out.merge(b, true)
	return out


# --- the country -------------------------------------------------------------------------------

func _country() -> void:
	var scene := (load(COUNTRY) as PackedScene).instantiate()
	var groves: Array = []  # [Vector2, id]
	var outcrops: Array = []
	var oaks := 0
	for n in scene.get_children():
		var nm := String(n.name)
		var at := Vector2((n as Node3D).position.x, (n as Node3D).position.z)
		var yaw := _r(rad_to_deg((n as Node3D).rotation.y))
		if n.get_script() and n.get_script().resource_path == HEDGE_ROW:
			var m: Resource = n.get("model")
			var s: Vector3 = n.get("model_scale")
			var type := "hedge"
			if m.resource_path.ends_with("wall.glb"):
				type = "low_wall" if s.y < 0.5 else "wall"
			lines.append({"id": nm.to_snake_case(), "type": type, "points": _poly(_simplify(n.get("points"), 0.3)), "clip": false})
		elif nm.begins_with("GroveTree"):
			groves.append([at, scene_ids.get(n.scene_file_path, "tree")])
		elif nm.begins_with("OutcropRock"):
			outcrops.append([at, scene_ids.get(n.scene_file_path, "rock")])
		elif nm.begins_with("LoneOak"):
			oaks += 1
			points.append({"id": "lone_oak_%d" % oaks, "type": "oak", "at": _xy(at), "yaw": yaw, "save_id": String(n.get("save_id"))})
		elif nm == "RuinedFarmstead":
			points.append({"id": "ruined_farmstead", "type": "ruined_farmstead", "at": _xy(at), "yaw": yaw})
		else:
			var type := _prop_type(n)
			if type == "":
				push_warning("import: don't know what country's %s is" % nm)
				continue
			points.append({"id": nm.to_snake_case(), "type": type, "at": _xy(at), "yaw": yaw})
	_clusters(groves, 30.0, "grove", "Grove", 4.0, 3.0)
	_clusters(outcrops, 14.0, "outcrop", "Outcrop", 2.5, 2.0)
	scene.free()


func _prop_type(n: Node) -> String:
	var m: Resource = n.get("model")
	if m == null:
		return ""
	var path := m.resource_path
	var scale: Vector3 = n.get("model_scale") if n.get("model_scale") != null else Vector3.ONE
	for id in catalog["props"]:
		var c: Dictionary = catalog["props"][id]
		if c["model"] != path:
			continue
		var cs: Array = c.get("scale", [1, 1, 1])
		if is_equal_approx(float(cs[1]), scale.y):
			return id
	return ""


## Nodes closer than `gap` to one another make one circle patch, round them with `margin` to spare.
func _clusters(nodes: Array, gap: float, prefix: String, title: String, spacing: float, margin: float) -> void:
	var left := nodes.duplicate()
	var k := 0
	while not left.is_empty():
		var group := [left.pop_back()]
		var grew := true
		while grew:
			grew = false
			for i in range(left.size() - 1, -1, -1):
				if group.any(func(g: Array) -> bool: return (g[0] as Vector2).distance_to(left[i][0]) < gap):
					group.append(left[i])
					left.remove_at(i)
					grew = true
		k += 1
		var c := Vector2.ZERO
		var items := {}
		for g in group:
			c += g[0] / group.size()
			items[g[1]] = items.get(g[1], 0) + 1
		var r := 0.0
		for g in group:
			r = maxf(r, c.distance_to(g[0]))
		patches.append({"id": "%s_%d" % [prefix, k], "name": "%s %d" % [title, k], "shape": "circle",
				"center": _xy(c), "radius": _r(r + margin), "inner": 0.0, "items": items, "count": group.size(),
				"seed": 20261030 + k, "spacing": spacing, "ground": [], "biome": "country"})


# --- main.tscn's hand-placed gatherables -----------------------------------------------------------

func _main_nodes() -> void:
	var scene := (load(MAIN) as PackedScene).instantiate()
	var nodes := scene.get_node_or_null("Nodes")
	if nodes:
		for n in nodes.get_children():
			var at := Vector2((n as Node3D).position.x, (n as Node3D).position.z)
			points.append({"id": String(n.name).to_snake_case(), "type": scene_ids.get(n.scene_file_path, "tree"),
					"at": _xy(at), "yaw": _r(rad_to_deg((n as Node3D).rotation.y)), "save_id": String(n.get("save_id"))})
	scene.free()


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


# --- writing -------------------------------------------------------------------------------------

## One shape per line, so the file diffs well in git.
func _write() -> void:
	var parts := PackedStringArray()
	parts.append("{\n\t\"version\": 1,\n\t\"terrain\": [],")
	for key in ["patches", "lines", "points"]:
		var list: Array = {"patches": patches, "lines": lines, "points": points}[key]
		var rows := PackedStringArray()
		for item in list:
			rows.append("\t\t" + JSON.stringify(item))
		parts.append("\t\"%s\": [\n%s\n\t]%s" % [key, ",\n".join(rows), "," if key != "points" else ""])
	parts.append("}\n")
	var f := FileAccess.open(OUT, FileAccess.WRITE)
	f.store_string("\n".join(parts))
	print("import: %d patches, %d lines, %d points -> %s" % [patches.size(), lines.size(), points.size(), OUT])
