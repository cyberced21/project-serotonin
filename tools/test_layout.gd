extends SceneTree
## Checks the map editor's layout and its bake (plans/map-editor.md):
##   - every scene and model in data/layout/catalog.json loads
##   - the layout's shapes are whole: unique ids, things the catalog has, enough corners, counts
##   - scenes/layout.tscn loads and is in step with the layout: each patch baked at least 90% of
##     its count and no more, every point and line there, a pond's water for each pond
##   - every gatherable's save id is unique (with main.tscn's), and the report has every one
##   godot --headless --path . -s res://tools/test_layout.gd -- --save-root=user://tool_worlds
## (No game class names: an -s script compiles before the autoloads exist.)

const LAYOUT := "res://data/layout/hearthvale.json"
const CATALOG := "res://data/layout/catalog.json"
const BAKED := "res://scenes/layout.tscn"
const REPORT := "res://data/layout/baked.json"

var failures := PackedStringArray()


func _initialize() -> void:
	var layout: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(LAYOUT))
	var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(CATALOG))
	var report: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(REPORT))
	_catalog_loads(catalog)
	_shapes_whole(layout, catalog)
	_baked_in_step(layout, catalog, report)
	if failures.is_empty():
		print("test_layout: PASS")
		quit(0)
	else:
		for f in failures:
			print("  FAIL ", f)
		print("test_layout: %d FAIL" % failures.size())
		quit(1)


func _check(ok: bool, what: String) -> void:
	if not ok:
		failures.append(what)


func _catalog_loads(catalog: Dictionary) -> void:
	for id in catalog["gatherables"]:
		var scene := load(catalog["gatherables"][id]["scene"]) as PackedScene
		_check(scene != null, "catalog gatherable %s's scene loads" % id)
		_check(int(catalog["gatherables"][id]["tier"]) in [0, 1, 2, 3], "catalog gatherable %s has a tier" % id)
	for sec in ["lines", "props", "fixtures"]:
		for id in catalog[sec]:
			_check(load(catalog[sec][id]["model"]) != null, "catalog %s %s's model loads" % [sec, id])
	for kind in catalog["tiers"]:
		for t in catalog["tiers"][kind]:
			for id in catalog["tiers"][kind][t]:
				_check(catalog["gatherables"].has(id), "tier mix %s %s's %s is a gatherable" % [kind, t, id])


func _shapes_whole(layout: Dictionary, catalog: Dictionary) -> void:
	var ids := {}
	for key in ["terrain", "patches", "lines", "points"]:
		for s in layout.get(key, []):
			var id: String = s.get("id", "")
			_check(id != "", "every %s shape has an id" % key)
			_check(not ids.has(id), "id %s is used once" % id)
			ids[id] = true
	for p in layout["patches"]:
		_check(int(p.get("count", 0)) > 0, "patch %s wants at least one" % p["id"])
		_check(not p.get("items", {}).is_empty(), "patch %s has a mix" % p["id"])
		for item in p.get("items", {}):
			_check(catalog["gatherables"].has(item), "patch %s's %s is in the catalog" % [p["id"], item])
		if p.get("shape", "polygon") == "circle":
			_check(float(p.get("radius", 0)) > float(p.get("inner", 0)), "patch %s's ring is wider than its hole" % p["id"])
		else:
			_check(p.get("points", []).size() >= 3, "patch %s has three corners" % p["id"])
		for g in p.get("ground", []):
			_check(catalog["grounds"].has(g), "patch %s's ground %s is known" % [p["id"], g])
	for l in layout["lines"]:
		_check(catalog["lines"].has(l["type"]), "line %s's %s is in the catalog" % [l["id"], l["type"]])
		_check(l.get("points", []).size() >= 2, "line %s has two points" % l["id"])
	for pt in layout["points"]:
		var t: String = pt["type"]
		_check(catalog["gatherables"].has(t) or catalog["props"].has(t) or catalog["fixtures"].has(t), "point %s's %s is in the catalog" % [pt["id"], t])
	for s in layout.get("terrain", []):
		_check(s.get("type", "") in ["flat", "raise", "pond", "river", "road", "path"], "terrain %s's type is known" % s["id"])


func _baked_in_step(layout: Dictionary, catalog: Dictionary, report: Dictionary) -> void:
	var scene := load(BAKED) as PackedScene
	_check(scene != null, "scenes/layout.tscn loads")
	if scene == null:
		return
	var baked := scene.instantiate()
	var save_ids := {}
	var gatherables := 0
	# the patches: as many as they asked for, or nearly
	var patches := baked.get_node("Patches")
	for p in layout["patches"]:
		var holder := patches.get_node_or_null(NodePath(String(p["id"]).to_pascal_case()))
		var n := holder.get_child_count() if holder else 0
		var want := int(p["count"])
		_check(n <= want and n >= int(floor(want * 0.9)) - 1 or (holder and n == want),
				"patch %s baked %d of %d (stale bake, or no room)" % [p["id"], n, want])
	for holder in patches.get_children():
		for n in holder.get_children():
			gatherables += 1
			var sid := String(n.get("save_id"))
			_check(sid != "" and not save_ids.has(sid), "save id %s is unique" % sid)
			save_ids[sid] = true
	# the points and lines
	var points := baked.get_node("Points")
	for pt in layout["points"]:
		_check(points.has_node(NodePath(String(pt["id"]).to_pascal_case())), "point %s is baked" % pt["id"])
		if catalog["gatherables"].has(pt["type"]):
			gatherables += 1
			var sid := String(pt.get("save_id", "pt_" + pt["id"]))
			_check(not save_ids.has(sid), "save id %s is unique" % sid)
			save_ids[sid] = true
	var lines := baked.get_node("Lines")
	for l in layout["lines"]:
		if catalog["lines"].get(l["type"], {}).get("walk", false):
			continue  # (walkways build nothing)
		var any := false
		for row in lines.get_children():
			if String(row.name).begins_with(String(l["id"]).to_pascal_case() + "_"):
				any = true
		_check(any, "line %s is baked (some of it)" % l["id"])
	var ponds := 0
	for s in layout.get("terrain", []):
		if s.get("type", "") == "pond":
			ponds += 1
	var water := baked.get_node_or_null("Water")
	_check((water.get_child_count() if water else 0) == ponds, "every pond has its water")
	_check(gatherables == report.get("nodes", []).size(), "the report lists every gatherable (%d vs %d)" % [gatherables, report.get("nodes", []).size()])
	baked.free()
	# none clash with main.tscn's own (the places' orchard trees, the haven's flower...)
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	var own := main.get_node("Layout")
	for n in main.find_children("*", "", true, false):
		if own.is_ancestor_of(n):
			continue
		if n.get("save_id") != null and String(n.get("save_id")) != "":
			_check(not save_ids.has(String(n.get("save_id"))), "main.tscn's %s doesn't share a save id with the layout" % n.get("save_id"))
	main.free()
