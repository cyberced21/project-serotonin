extends SceneTree
## Loads a generated world all at once and again spread over frames, and checks both place the
## same nodes in the same spots (saves are keyed by those spots' ids). Prints the load times.
##   godot --headless --path . -s res://tools/test_loading.gd -- --save-root=user://test_loading [--seed=N]

var _fails := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var s := 42
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seed="):
			s = arg.trim_prefix("--seed=").to_int()
	var world_script: GDScript = load("res://scripts/procgen/procgen_world.gd")
	var results: Array[Dictionary] = []
	for budget in [0.0, 12.0]:
		world_script.set("frame_budget_ms", budget)
		var started := Time.get_ticks_msec()
		root.get_node("Worlds").call("play_scratch", s)
		await process_frame
		while get_first_node_in_group("loading_screen") != null or get_first_node_in_group("player") == null:
			await process_frame
		var ms := Time.get_ticks_msec() - started
		var nodes := {}
		for n in get_nodes_in_group("gatherable"):
			nodes[String(n.get("save_id"))] = (n as Node3D).global_position.snapped(Vector3.ONE * 0.01)
		print("budget %4.1f ms: %d nodes, loaded in %d ms" % [budget, nodes.size(), ms])
		results.append(nodes)
	_check(results[0].size() > 50, "a world full of nodes (%d)" % results[0].size())
	_check(results[0] == results[1], "the same nodes in the same spots either way")
	print("test_loading: %s" % ("PASS" if _fails == 0 else "%d FAILED" % _fails))
	quit(1 if _fails else 0)


func _check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		_fails += 1
