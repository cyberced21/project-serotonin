extends SceneTree
## Noticeboard shots (plans/noticeboard.md): on a fresh Hearthvale, stands in front of the board
## and measures the frame looking away and looking at it (CPU and GPU), then opens it and saves a
## screenshot of each category to plans/noticeboard-<category>.png. Windowed (ask first):
##
##   godot --path . --screen 1 --resolution 1920x1080 --audio-driver Dummy -s res://tools/noticeboard_shots.gd -- --save-root=user://tmp
## (--look-only: just the two frame measurements.)


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.get_node("SaveGame").set("path", "user://noticeboard_shots_save.json")
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://noticeboard_shots_save.json"))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
	root.get_node("Worlds").call("play_fresh")
	while get_first_node_in_group("player") == null or get_first_node_in_group("noticeboard") == null:
		await process_frame
	await _wait(3.0)
	root.get_node("DayNight").set("time", 0.45)
	var board := get_first_node_in_group("noticeboard") as Node3D
	var player := get_first_node_in_group("player") as Node3D
	var front := board.global_position + board.global_basis.z * 2.2 + Vector3.UP * 0.1
	player.call("teleport", front, board.global_position + board.global_basis.z * 8.0)  # (looking away)
	await _wait(2.0)
	await _measure("looking away")
	player.call("teleport", front, board.global_position + Vector3.UP * 1.2)
	await _wait(1.0)
	await _measure("looking at it")
	if "--look-only" in OS.get_cmdline_user_args():
		quit()
		return
	var inv := root.get_node("Inventory")
	for item in [&"wood", &"birch", &"wheat", &"ore", &"stone"]:
		inv.call("add", item, 30)
	board.call("interact")
	await _wait(0.6)
	var panel := get_first_node_in_group("noticeboard_panel")
	for c: Dictionary in root.get_node("Projects").call("categories"):
		if (c["projects"] as Array).is_empty():
			continue
		panel.call("show_category", c["id"])
		await _wait(0.4)
		var img := root.get_texture().get_image()
		img.save_png(ProjectSettings.globalize_path("res://plans/noticeboard-%s.png" % c["id"]))
		print("SHOT plans/noticeboard-%s.png" % c["id"])
	await _measure("board open")
	panel.call("close")
	quit()


func _measure(what: String) -> void:
	var vp := root.get_viewport_rid()
	var n := 0
	var gpu := 0.0
	var cpu := 0.0
	var start := Time.get_ticks_usec()
	var last := start
	var total := 0.0
	while Time.get_ticks_usec() - start < 3_000_000:
		await process_frame
		var now := Time.get_ticks_usec()
		total += (now - last) / 1000.0
		last = now
		n += 1
		gpu += RenderingServer.viewport_get_measured_render_time_gpu(vp)
		cpu += RenderingServer.viewport_get_measured_render_time_cpu(vp) + RenderingServer.get_frame_setup_time_cpu()
	print("FRAME %-14s %6.1f fps  frame %6.2f ms  render cpu %5.2f  gpu %5.2f  process %5.2f" % [what, 1000.0 * n / total, total / n, cpu / n, gpu / n,
		Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0])


func _wait(s: float) -> void:
	var end := Time.get_ticks_msec() + int(s * 1000.0)
	while Time.get_ticks_msec() < end:
		await process_frame
