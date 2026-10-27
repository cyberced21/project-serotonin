extends SceneTree
## Checks the Worlds autoload on a throwaway save root (never the player's worlds):
##   godot --headless --path . -s res://tools/test_worlds.gd -- --save-root=user://test_worlds
## Migration from old flat saves, create / rename / duplicate / reset / delete, the list order.

const ROOT := "user://test_worlds"
const LEGACY := "user://test_worlds_legacy"

var _fails := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var worlds := root.get_node("Worlds")
	if worlds.get("root") != ROOT:
		push_error("run with -- --save-root=%s" % ROOT)
		quit(1)
		return
	_check(worlds.call("exists", "classic"), "classic exists from the start")

	# migration: an old save.json and two procgen saves
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(LEGACY))
	_write(LEGACY.path_join("save.json"), '{"version": 1, "data": {"skills": {"xp": {"mining": 42}}}}')
	_write(LEGACY.path_join("procgen_123.json"), '{"version": 1, "data": {}}')
	_write(LEGACY.path_join("procgen_77.json"), '{"version": 1, "data": {}}')
	worlds.call("migrate", LEGACY)
	_check(worlds.call("has_save", "classic"), "old save.json became classic's")
	_check(not FileAccess.file_exists(LEGACY.path_join("save.json")), "old save.json moved, not copied")
	var names: Array = (worlds.call("list") as Array).map(func(m: Dictionary) -> String: return m["name"])
	_check(names.has("Seed 123") and names.has("Seed 77"), "procgen saves became worlds: %s" % [names])
	var seed_123 := ""
	for m: Dictionary in worlds.call("list"):
		if m["name"] == "Seed 123":
			seed_123 = m["id"]
			_check(int(m["settings"]["seed"]) == 123, "imported world keeps its seed")
	_check(worlds.call("has_save", seed_123), "imported world has its save")

	# create, rename, duplicate
	var id: String = worlds.call("create", "Testland", {"seed": 5})
	_check(worlds.call("exists", id), "created")
	worlds.call("rename", id, "  Renamed  ")
	_check((worlds.call("meta", id) as Dictionary)["name"] == "Renamed", "renamed and trimmed")
	var copy: String = worlds.call("duplicate_world", id)
	_check(copy != "" and copy != id, "duplicated")
	_check(int((worlds.call("meta", copy) as Dictionary)["settings"]["seed"]) == 5, "copy keeps the seed")
	_check(worlds.call("duplicate_world", "classic") == "", "classic can't be duplicated")

	# reset and delete
	_write(worlds.call("save_path", id), '{"version": 1, "data": {}}')
	worlds.call("reset", id)
	_check(not worlds.call("has_save", id), "reset wipes the save")
	_check(worlds.call("exists", id), "reset keeps the world")
	worlds.call("delete", "classic")
	_check(worlds.call("exists", "classic"), "classic can't be deleted")
	worlds.call("delete", copy)
	_check(not worlds.call("exists", copy), "deleted")

	# outdated
	var m: Dictionary = worlds.call("meta", id)
	m["generator"] = 0
	_check(worlds.call("outdated", m), "an older generator is outdated")
	_check(not worlds.call("outdated", worlds.call("meta", "classic")), "classic is never outdated")

	_remove_tree(ProjectSettings.globalize_path(ROOT))
	_remove_tree(ProjectSettings.globalize_path(LEGACY))
	print("test_worlds: %s" % ("PASS" if _fails == 0 else "%d FAILED" % _fails))
	quit(1 if _fails else 0)


func _check(ok: bool, what: String) -> void:
	if not ok:
		_fails += 1
		printerr("FAIL: " + what)


func _write(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)


func _remove_tree(dir: String) -> void:
	for sub in DirAccess.get_directories_at(dir):
		_remove_tree(dir.path_join(sub))
	for file in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(file))
	DirAccess.remove_absolute(dir)
