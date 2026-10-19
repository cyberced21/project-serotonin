extends SceneTree
## Screenshots of the menus, on a throwaway save root (never the player's worlds):
##   godot --path . --screen 1 --resolution 1280x720 -s res://tools/menu_shots.gd -- --save-root=user://menu_shots [--out=dir] [--only=a,b]
## Seeds a few worlds, then shoots: main (the main menu), worlds (the Worlds screen).

const ROOT := "user://menu_shots"

var out_dir := "res://docs/images/menus"
var only := PackedStringArray()


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out_dir = arg.trim_prefix("--out=")
		elif arg.begins_with("--only="):
			only = arg.trim_prefix("--only=").split(",")
	_run.call_deferred()


func _run() -> void:
	var worlds := root.get_node("Worlds")
	if worlds.get("root") != ROOT:
		push_error("run with -- --save-root=%s" % ROOT)
		quit(1)
		return
	var gfx := root.get_node_or_null("GraphicsSettings")
	if gfx:
		gfx.set("persist", false)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	_seed_worlds(worlds)
	change_scene_to_file("res://scenes/menu/main_menu.tscn")
	await _wait(4.0)
	await _shot("main")
	var menu := current_scene
	menu.call("_open", &"worlds")
	await _wait(1.0)
	await _shot("worlds")
	menu.call("_open", &"controls")
	await _wait(0.5)
	await _shot("controls")

	# into the classic world, pause, Save & Quit: the card gets its picture and the save is written
	worlds.call("play", "classic")
	await _wait(6.0)
	var pause := root.get_node("PauseMenu")
	pause.call("open")
	await _wait(0.5)
	await _shot("pause")
	_check(root.get_node("SaveGame").get_tree().paused, "the pause menu pauses the tree")
	await pause.call("_save_and_quit", false)
	await _wait(3.0)
	_check(FileAccess.file_exists(worlds.call("thumb_path", "classic")), "Save & Quit took a picture")
	_check(worlds.call("has_save", "classic"), "Save & Quit wrote the save")
	_check(float((worlds.call("meta", "classic") as Dictionary)["playtime"]) > 3600.0 * 5.4, "playtime grew")
	_check(current_scene.scene_file_path == "res://scenes/menu/main_menu.tscn", "back on the main menu")
	current_scene.call("_open", &"worlds")
	await _wait(1.0)
	await _shot("worlds_after")
	_remove_tree(ProjectSettings.globalize_path(ROOT))
	quit()


func _check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)


## A played classic world and two generated ones, so the cards have something to show.
func _seed_worlds(worlds: Node) -> void:
	var now := Time.get_unix_time_from_system()
	var classic: Dictionary = worlds.call("meta", "classic")
	classic["last_played"] = now - 3600.0 * 3
	classic["playtime"] = 3600.0 * 5.4
	worlds.call("_write_meta", "classic", classic)
	for spec in [["Mossy Hollow", 4821, 900.0, 7800.0], ["Frostbite Ridge", 77, 86400.0 * 3, 1500.0]]:
		var id: String = worlds.call("create", spec[0], {"seed": spec[1]})
		var m: Dictionary = worlds.call("meta", id)
		m["last_played"] = now - spec[2]
		m["playtime"] = spec[3]
		worlds.call("_write_meta", id, m)


func _shot(name: String) -> void:
	if not only.is_empty() and not only.has(name):
		return
	await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	var path := out_dir.path_join(name + ".png")
	img.save_png(ProjectSettings.globalize_path(path) if path.begins_with("res://") else path)
	print("SHOT ", path)


func _wait(seconds: float) -> void:
	var end := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < end:
		await process_frame


func _remove_tree(dir: String) -> void:
	for sub in DirAccess.get_directories_at(dir):
		_remove_tree(dir.path_join(sub))
	for file in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(file))
	DirAccess.remove_absolute(dir)
