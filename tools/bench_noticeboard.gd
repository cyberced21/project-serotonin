extends SceneTree
## Noticeboard CPU bench (plans/noticeboard.md): on a fresh Hearthvale, times what looking at the
## board costs each frame (its hover prompt) and what opening the board's panel costs.
##
##   godot --headless --path . -s res://tools/bench_noticeboard.gd -- --save-root=user://tmp

const RUNS := 200


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.get_node("SaveGame").set("path", "user://bench_noticeboard_save.json")
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://bench_noticeboard_save.json"))
	root.get_node("Worlds").call("play_fresh")
	while get_first_node_in_group("player") == null or get_first_node_in_group("noticeboard") == null:
		await process_frame
	for i in 30:
		await process_frame
	var board := get_first_node_in_group("noticeboard")
	var projects := root.get_node("Projects")
	print("BENCH projects on the board: %d" % (projects.call("all") as Array).size())
	var t := Time.get_ticks_usec()
	for i in RUNS:
		projects.call("all")
	print("BENCH Projects.all()      %8.3f ms" % ((Time.get_ticks_usec() - t) / 1000.0 / RUNS))
	if projects.has_method("_build"):
		t = Time.get_ticks_usec()
		for i in RUNS:
			projects.call("_build")
		print("BENCH   (rebuilt)         %8.3f ms" % ((Time.get_ticks_usec() - t) / 1000.0 / RUNS))
	t = Time.get_ticks_usec()
	for i in RUNS:
		board.call("prompt")
	print("BENCH board.prompt()      %8.3f ms (each frame you look at it)" % ((Time.get_ticks_usec() - t) / 1000.0 / RUNS))
	var panel_class: GDScript = load("res://scripts/noticeboard_panel.gd")
	t = Time.get_ticks_usec()
	panel_class.call("open_for", board)
	var opened := (Time.get_ticks_usec() - t) / 1000.0
	var panel := get_first_node_in_group("noticeboard_panel")
	t = Time.get_ticks_usec()
	for i in 10:
		panel.call("_refresh")
	print("BENCH panel open %.2f ms, refresh %.2f ms" % [opened, (Time.get_ticks_usec() - t) / 1000.0 / 10])
	panel.call("close")
	quit()
