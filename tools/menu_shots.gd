extends SceneTree
## Screenshots of the menus, on a throwaway save root (never the player's worlds):
##   godot --path . --screen 1 --resolution 1280x720 -s res://tools/menu_shots.gd -- --save-root=user://menu_shots [--out=dir] [--only=a,b]
## Seeds a few worlds, then shoots the main menu, the Worlds, Controls and Settings screens, the
## pause menu, the Worlds screen with a picture taken, and a generated world loading and loaded.

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
	for autoload in ["GraphicsSettings", "Settings"]:
		root.get_node(autoload).set("persist", false)  # never write the player's settings.cfg
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
	menu.call("_open", &"new_world")
	var nw: Control = menu.get("_new_world_screen")
	(nw.get("_seed") as LineEdit).text = "4821"
	(nw.get("_name") as LineEdit).text = "Mossy Hollow"
	nw.call("_changed")
	await _wait(3.0)
	await _shot("new_world")
	var settings: Control = menu.get("_settings")
	menu.call("_open", &"settings")
	for tab in 4:
		(settings.get("_tabs") as TabContainer).current_tab = tab
		await _wait(0.3)
		await _shot("settings_%d" % tab)

	# into the classic world, pause, Save & Quit: the card gets its picture and the save is written
	worlds.call("play", "classic")
	await _wait(6.0)
	var pause := root.get_node("PauseMenu")
	pause.call("open")
	await _wait(0.5)
	await _shot("pause")
	_check(root.get_node("SaveGame").get_tree().paused, "the pause menu pauses the tree")
	await _in_game_shots(pause)
	await pause.call("_save_and_quit", false)
	await _wait(3.0)
	_check(FileAccess.file_exists(worlds.call("thumb_path", "classic")), "Save & Quit took a picture")
	_check(worlds.call("has_save", "classic"), "Save & Quit wrote the save")
	_check(float((worlds.call("meta", "classic") as Dictionary)["playtime"]) > 3600.0 * 5.4, "playtime grew")
	_check(current_scene.scene_file_path == "res://scenes/menu/main_menu.tscn", "back on the main menu")
	current_scene.call("_open", &"worlds")
	await _wait(1.0)
	await _shot("worlds_after")

	# a generated world: its loading screen, then in and out again
	var mossy := ""
	for m: Dictionary in worlds.call("list"):
		if m["name"] == "Mossy Hollow":
			mossy = m["id"]
	worlds.call("play", mossy)
	await _wait(1.5)
	await _shot("loading")
	_check(get_first_node_in_group("loading_screen") != null, "a generated world shows its loading screen")
	while get_first_node_in_group("loading_screen") != null:
		await process_frame
	await _wait(1.0)
	await _shot("generated")
	worlds.call("leave")
	await _wait(1.0)
	_remove_tree(ProjectSettings.globalize_path(ROOT))
	quit()


## The panels you meet while playing: the Skills page (with talents picked and waiting), the
## talent cards, Greta's three tabs, the debug menu. Leaves the pause menu open, as it found it.
func _in_game_shots(pause: Node) -> void:
	var skills := root.get_node("Skills")
	for s in ["woodcutting", "mining", "fishing", "farming"]:
		skills.call("set_level", StringName(s), 23)
	var talents = skills.get("talents")
	talents.call("pick", &"woodcutting", 10, &"chain_cut")
	talents.call("pick", &"woodcutting", 20, &"heartwood")
	pause.call("_show_skills")
	await _wait(0.5)
	await _shot("skills")
	var cards := get_first_node_in_group("talent_cards")
	if cards:
		cards.call("show_choice", &"mining")
		await _wait(0.5)
		await _shot("talent_cards")
		cards.call("_close")
	pause.call("resume")
	var panel := get_first_node_in_group("upgrade_panel")
	var greta: Node3D = null
	for b in get_nodes_in_group("building"):
		if b.get("def").id == &"smithy":
			greta = b.get_node_or_null("Villager")
	if greta and panel:
		var player: Node3D = get_first_node_in_group("player")
		player.global_position = greta.global_position + Vector3(1.5, 0.5, 0)  # (it closes if you're far)
		for tab in 3:
			panel.call("open", greta)
			panel.call("_show_tab", tab)
			await _wait(0.4)
			await _shot("greta_%s" % ["upgrade", "forge", "talents"][tab])
		panel.call("close")
	var debug := root.get_node_or_null("DebugMenu")
	if debug:
		debug.call("open")
		await _wait(0.4)
		await _shot("debug_menu")
		debug.call("close")
	pause.call("open")
	await _wait(0.3)


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
