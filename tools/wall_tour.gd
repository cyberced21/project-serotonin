extends SceneTree
## Ore wall tour: opens the main world, reports how many ore wall panels Greystone Quarry's placer
## stood on each ring and how fast it draws, and saves screenshots from round the pit.
##
##   godot --path . --screen 1 --resolution 1280x720 -s res://tools/wall_tour.gd
##
## Options (after `--`):
##   --label=NAME  sub-folder of docs/images/walls/ to save into (default "tour")
##   --night       at night instead of mid-morning
## The game is played on a throwaway save, so the real one is never touched.

var out_dir := "res://docs/images/walls/tour"
var time := 0.42

## Viewpoints: [name, where to stand (world), what to look at].
const QUARRY := Vector3(-175, 0, -15)
var SPOTS := [
	["rim", QUARRY + Vector3(48, 0, 30), QUARRY],
	["floor", QUARRY + Vector3(-4, 0, 6), QUARRY + Vector3(6, 6, -14)],
	["level2", QUARRY + Vector3(0, 0, 37.5), QUARRY + Vector3(-14, 4, 46)],
	["level4", QUARRY + Vector3(-17, 0, -3), QUARRY + Vector3(-26, 3, 6)],
]


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--label="):
			out_dir = "res://docs/images/walls/" + arg.get_slice("=", 1)
		elif arg == "--night":
			time = 0.9
	_run.call_deferred()


func _run() -> void:
	root.get_node("SaveGame").set("path", "user://wall_tour_save.json")
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://wall_tour_save.json"))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	change_scene_to_file("res://scenes/main.tscn")
	await _wait(3.0)
	var gfx := root.get_node_or_null("GraphicsSettings")
	if gfx:
		gfx.set("persist", false)
	root.get_node("DayNight").set("time", time)
	var placer := current_scene.find_child("Walls", true, false)
	var walls := get_nodes_in_group("ore_wall")
	print("PLACED per ring %s, %d panels in all" % [placer.get("placed") if placer else "-", walls.size()])
	var p := get_first_node_in_group("player") as Node3D
	var terrain := get_first_node_in_group("terrain")
	for spot: Array in SPOTS:
		var at: Vector3 = spot[1]
		at.y = terrain.get("data").call("get_height", at) + 0.1
		var look: Vector3 = spot[2]
		look.y += terrain.get("data").call("get_height", Vector3(look.x, 0, look.z))
		for i in 2:
			p.call("teleport", at, look)
			await _wait(0.5)
		var cam := p.get("camera") as Camera3D
		var d := look - cam.global_position
		(cam.get_parent() as Node3D).rotation.x = atan2(d.y, Vector2(d.x, d.z).length())
		await _wait(2.0)
		var frames := Engine.get_frames_drawn()
		var t0 := Time.get_ticks_msec()
		await _wait(2.0)
		var fps := (Engine.get_frames_drawn() - frames) * 1000.0 / (Time.get_ticks_msec() - t0)
		print("SPOT %s  fps %.0f" % [spot[0], fps])
		await _shot(spot[0])
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://wall_tour_save.json"))
	quit()


func _wait(seconds: float) -> void:
	var end := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < end:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		await process_frame


func _shot(name: String) -> void:
	var hidden: Array[CanvasLayer] = []
	for layer in root.find_children("*", "CanvasLayer", true, false):
		if layer.visible:
			layer.visible = false
			hidden.append(layer)
	await process_frame
	await process_frame
	root.get_texture().get_image().save_png("%s/%s.png" % [out_dir, name])
	for layer in hidden:
		layer.visible = true
