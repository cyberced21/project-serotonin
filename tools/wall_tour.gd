extends SceneTree
## Ore wall tour: opens the main world, reports how many ore wall panels the
## quarry's placer (OreWallPlacer) stood on each ring and how fast it draws, and saves screenshots
## from the rim and from each level, looking along its wall.
##
##   godot --path . --screen 1 --resolution 1280x720 -s res://tools/wall_tour.gd
##
## Options (after `--`):
##   --label=NAME    sub-folder of docs/images/walls/ to save into (default "tour")
##   --night         at night instead of mid-morning
## The game is played on a throwaway save, so the real one is never touched.

var out_dir := "res://docs/images/walls/tour"
var time := 0.42


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
	var placer: Node3D = null
	for n in current_scene.find_children("*", "Node3D", true, false):
		if n.get_script() and n.get_script().resource_path.ends_with("ore_wall_placer.gd"):
			placer = n
	if placer == null:
		push_error("no OreWallPlacer in this world")
		quit(1)
		return
	print("PLACED per ring %s, %d panels in all" % [placer.get("placed"), get_nodes_in_group("ore_wall").size()])
	# the rim looking in, then each level looking along the foot of its wall
	var c2: Vector2 = placer.get("center")
	var c := Vector3(c2.x, 0, c2.y)
	var radii: Array = placer.get("walls")
	var spots := [["rim", c + Vector3(1, 0, 0.6).normalized() * (float(radii[0]) + 6.0), c]]
	for k in radii.size():
		var a := 0.7 + k * 1.3
		var out := Vector3(cos(a), 0, sin(a))
		var side := Vector3(-out.z, 0, out.x)
		var stand: Vector3 = c + out * (float(radii[k]) - 7.5)
		spots.append(["level%d" % (k + 1), stand, stand + side * 8.0 + out * 3.5 + Vector3.UP * 2.0])
	var p := get_first_node_in_group("player") as Node3D
	var terrain := get_first_node_in_group("terrain")
	for spot: Array in spots:
		var at: Vector3 = spot[1]
		at.y = terrain.get("data").call("get_height", at) + 0.1
		var look: Vector3 = spot[2]
		look.y += at.y
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
