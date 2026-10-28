extends SceneTree
## Checks the Worlds autoload on a throwaway save root (never the player's worlds):
##   godot --headless --path . -s res://tools/test_worlds.gd -- --save-root=user://test_worlds
## Migration from the old flat save, the list (Hearthvale only), rename / reset / delete.

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

	# migration: an old save.json (and an old procgen save, which stays where it is)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(LEGACY))
	_write(LEGACY.path_join("save.json"), '{"version": 1, "data": {"skills": {"xp": {"mining": 42}}}}')
	_write(LEGACY.path_join("procgen_123.json"), '{"version": 1, "data": {}}')
	worlds.call("migrate", LEGACY)
	_check(worlds.call("has_save", "classic"), "old save.json became classic's")
	_check(not FileAccess.file_exists(LEGACY.path_join("save.json")), "old save.json moved, not copied")
	_check(FileAccess.file_exists(LEGACY.path_join("procgen_123.json")), "an old procgen save is left alone")

	# an old generated world's folder is deleted
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(ROOT.path_join("123_4567")))
	_write(ROOT.path_join("123_4567/world.json"), '{"version": 1, "name": "Seed 5", "kind": "generated"}')
	worlds.call("_remove_generated")
	_check(not worlds.call("exists", "123_4567"), "a generated world is deleted")
	var names: Array = (worlds.call("list") as Array).map(func(m: Dictionary) -> String: return m["name"])
	_check(names == ["Hearthvale"], "only Hearthvale is listed: %s" % [names])

	# rename, reset, delete
	worlds.call("rename", "classic", "  Renamed  ")
	_check((worlds.call("meta", "classic") as Dictionary)["name"] == "Renamed", "renamed and trimmed")
	worlds.call("reset", "classic")
	_check(not worlds.call("has_save", "classic"), "reset wipes the save")
	_check(worlds.call("exists", "classic"), "reset keeps the world")
	worlds.call("delete", "classic")
	_check(worlds.call("exists", "classic"), "classic can't be deleted")

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
