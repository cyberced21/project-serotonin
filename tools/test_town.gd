extends SceneTree
## Checks the town designer (plans/town-designer.md) where the game sees it:
##   - every building type in the catalog has its model
##   - an added building (an anchor with a `type`) is made under Village where its anchor says,
##     turned to its yaw, with its door a Spots/Door marker; applying twice makes it once
##   - one not placed is kept out; one of an unknown type is skipped
##   godot --headless --path . -s res://tools/test_town.gd -- --save-root=user://tmp
## (No game class names: an -s script compiles before the autoloads exist.)

const Anchors := preload("res://scripts/layout_anchors.gd")
const TMP := "user://tmp/test_town_layout.json"
const EPS := 0.01

var failures := PackedStringArray()


func _initialize() -> void:
	_catalog()
	_added()
	if failures.is_empty():
		print("test_town: PASS")
		quit(0)
	else:
		for f in failures:
			print("FAIL " + f)
		print("test_town: %d FAILED" % failures.size())
		quit(1)


func _check(ok: bool, what: String) -> void:
	if not ok:
		failures.append(what)


func _catalog() -> void:
	var c: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/layout/catalog.json"))
	_check(c.has("buildings") and c["buildings"].size() >= 6, "the catalog lists buildings to add")
	for k in c.get("buildings", {}):
		var t: Dictionary = c["buildings"][k]
		_check(ResourceLoader.exists(String(t["model"])), "building type %s's model %s exists" % [k, t["model"]])
		_check((t["box"] as Array).size() == 4 and float(t.get("pad", 0)) > 0.0, "building type %s has a box and a pad" % k)


## A layout like Hearthvale's with three added buildings: a cottage, a barn not placed, a nonsense type.
func _layout() -> String:
	var layout: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/layout/hearthvale.json"))
	layout["anchors"].append({"id": "cottage_t1", "type": "cottage", "at": [150.0, 160.0], "yaw": 90.0, "pad": 7, "area": "village"})
	layout["anchors"].append({"id": "barn_t1", "type": "barn", "at": [170.0, 170.0], "yaw": 0.0, "placed": false})
	layout["anchors"].append({"id": "odd_t1", "type": "no_such_thing", "at": [180.0, 170.0]})
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://tmp"))
	var f := FileAccess.open(TMP, FileAccess.WRITE)
	f.store_string(JSON.stringify(layout))
	f.close()
	return TMP


func _added() -> void:
	Anchors.use_file(_layout())
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	Anchors.apply(main)
	var n := main.get_node_or_null("Village/cottage_t1") as Node3D
	_check(n != null, "the added cottage is made under Village")
	if n:
		_check(Vector2(n.position.x, n.position.z).distance_to(Vector2(150, 160)) < EPS, "it stands at its anchor (%s)" % n.position)
		var yaw := rad_to_deg(atan2(n.basis.z.x, n.basis.z.z))
		_check(absf(wrapf(yaw - 90.0, -180.0, 180.0)) < 0.05, "it's turned to its yaw (%.2f)" % yaw)
		_check(n.get("model") != null and n.get("doors_open") == false, "it has its model, its doors shut")
		var door := n.call("door_point") as Node3D
		_check(door != null, "it has a door for the walkways")
		if door:
			var p := n.transform * door.position  # (its door: 4.6 m in front, and in front is +X when turned 90°)
			_check(Vector2(p.x, p.z).distance_to(Vector2(154.6, 160)) < 0.05, "its door is at its front (%s)" % p)
		_check(String(n.get_meta(&"display_name", "")) == "Cottage", "it's called by its type's name")
		_check(n.is_in_group("fixture"), "it's a fixture (its door is found before it's ready)")
	var count := main.get_node("Village").get_child_count()
	Anchors.apply(main)
	_check(main.get_node("Village").get_child_count() == count, "applying twice makes it once")
	var barn := main.get_node_or_null("Village/barn_t1") as Node3D
	_check(barn != null and not barn.visible and barn.has_meta(&"kept_out"), "a building not placed is kept out")
	_check(main.get_node_or_null("Village/odd_t1") == null, "a building of no known type isn't made")
	_check(Anchors.find(&"cottage_t1").get("node", "") == "Village/cottage_t1", "its anchor names the node made for it")
	main.free()
	Anchors.use_file("res://data/layout/hearthvale.json")
