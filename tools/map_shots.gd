extends SceneTree
## Screenshots of the maps (scripts/map) in Hearthvale: the HUD with
## the minimap, the world map fitted, and zoomed in on you. Prints how long the map data took.
##   godot --path . --audio-driver Dummy --screen 1 --resolution 1280x720 -s res://tools/map_shots.gd -- --save-root=user://map_shots [--out=dir]
## (No game class names here: an -s script compiles before the autoloads exist.)

var out_dir := "res://docs/images/map"


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out_dir = arg.trim_prefix("--out=")
	_run.call_deferred()


func _run() -> void:
	for autoload in ["GraphicsSettings", "Settings"]:
		root.get_node(autoload).set("persist", false)  # never write the player's settings.cfg
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir) if out_dir.begins_with("res://") else out_dir)
	var worlds := root.get_node("Worlds")
	worlds.call("play", "classic")
	await _world("classic")
	quit()


func _world(tag: String) -> void:
	await process_frame
	while get_first_node_in_group("player") == null:
		await process_frame
	var started := Time.get_ticks_msec()
	var data: Node = null
	while data == null or not data.get("is_built"):
		await process_frame
		data = get_first_node_in_group("map_data")
		if Time.get_ticks_msec() - started > 60000:
			print("FAIL %s: the map data never finished" % tag)
			return
	print("%s: map data in %d ms, %s samples, %d m a sample, %d names: %s" % [tag, Time.get_ticks_msec() - started,
		data.get("heights").get_size(), data.get("step"), data.get("labels").size(),
		data.get("labels").map(func(l: Dictionary) -> String: return l["text"])])
	await _wait(1.0)
	await _shot("%s_hud" % tag)
	var map := get_first_node_in_group("world_map")
	map.call("open")
	await _wait(0.6)
	await _shot("%s_map" % tag)
	var view: Control = map.get("view")
	map.call("_center_on_player")
	view.set("metres_per_px", 0.45)
	await _wait(0.4)
	await _shot("%s_map_zoomed" % tag)
	map.call("close")


func _shot(name: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var path := out_dir.path_join(name + ".png")
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path(path) if path.begins_with("res://") else path)
	print("SHOT ", path)


func _wait(seconds: float) -> void:
	var end := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < end:
		await process_frame
