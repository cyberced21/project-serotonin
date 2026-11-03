extends SceneTree
## Checks the maps (plans/map-maker.md): data/maps.json and where each map's files are.
##   - the registry lists Hearthvale and plays a map it lists; Hearthvale's files are where they were
##   - another map's files are under data/maps/<id>/ (its editor pictures under tools/map_editor/maps/)
##   - Main on Hearthvale is left as it is; on another map its terrain reads that map's land and its
##     Layout holds that map's baked layout (none yet: empty), and the layout read is that map's
##   godot --headless --path . -s res://tools/test_maps.gd -- --save-root=user://tool_worlds
## (No game class names: an -s script compiles before the autoloads exist.)

const MapsC := preload("res://scripts/maps.gd")
const Anchors := preload("res://scripts/layout_anchors.gd")

var failures := PackedStringArray()


func _initialize() -> void:
	_registry()
	_paths()
	_main_on_maps()
	if failures.is_empty():
		print("test_maps: PASS")
		quit(0)
	else:
		for f in failures:
			print("FAIL " + f)
		print("test_maps: %d FAILED" % failures.size())
		quit(1)


func _check(ok: bool, what: String) -> void:
	if not ok:
		failures.append(what)


func _registry() -> void:
	var ids := MapsC.ids()
	_check(ids.has(MapsC.DEFAULT), "data/maps.json lists Hearthvale (%s)" % [ids])
	_check(ids.has(MapsC.active()), "the map played (%s) is one it lists" % MapsC.active())
	for id in ids:
		_check(FileAccess.file_exists(MapsC.path("layout", id)), "map %s has its layout (%s)" % [id, MapsC.path("layout", id)])


func _paths() -> void:
	var want := {"layout": "res://data/layout/hearthvale.json", "baked": "res://data/layout/baked.json",
			"applied": "res://data/layout/terrain_applied.json", "scene": "res://scenes/layout.tscn",
			"terrain": "res://terrain_data", "roads": "res://scripts/world_roads.gd", "editor": "res://tools/map_editor/"}
	for what in want:
		_check(MapsC.path(what, MapsC.DEFAULT) == want[what], "Hearthvale's %s is still %s (%s)" % [what, want[what], MapsC.path(what, MapsC.DEFAULT)])
	_check(MapsC.path("layout", &"moor") == "res://data/maps/moor/layout.json", "another map's layout is in its folder")
	_check(MapsC.path("terrain", &"moor") == "res://data/maps/moor/terrain", "another map's land is in its folder")
	_check(MapsC.path("editor", &"moor") == "res://tools/map_editor/maps/moor/", "another map's pictures are with the editor")


func _main_on_maps() -> void:
	var scene := load("res://scenes/main.tscn") as PackedScene
	MapsC.use(MapsC.DEFAULT)
	var main := scene.instantiate()
	var before := main.get_node("Layout").get_child_count()
	Anchors.use_map(main)
	_check(main.get_node("Layout").get_child_count() == before and before > 0, "on Hearthvale, Main's Layout is left as baked (%d groups)" % before)
	_check(String(main.get_node("Terrain3D").get("data_directory")) == "res://terrain_data", "on Hearthvale, the terrain reads Hearthvale's land")
	main.free()

	MapsC.use(&"not_made_yet")
	main = scene.instantiate()
	Anchors.use_map(main)
	_check(String(main.get_node("Terrain3D").get("data_directory")) == "res://data/maps/not_made_yet/terrain", "on another map, the terrain reads that map's land")
	_check(main.get_node("Layout").get_child_count() == 0, "on a map not baked yet, Main's Layout holds nothing of Hearthvale's")
	_check(MapsC.layout() == "res://data/maps/not_made_yet/layout.json", "the layout read is that map's")
	main.free()
	MapsC.use(MapsC.DEFAULT)
