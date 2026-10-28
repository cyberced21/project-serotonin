extends SceneTree
## Checks the fireflies (scripts/autoload/fireflies.gd): none by day, a full swarm in the evening
## and before midnight, gone by small hours; lit ones hover over the ground round the player.
##   godot --headless --path . -s res://tools/test_fireflies.gd -- --save-root=user://tool_worlds

var _fails := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.get_node("Worlds").call("play_scratch", 42)
	await process_frame
	while get_first_node_in_group("loading_screen") != null or get_first_node_in_group("player") == null:
		await process_frame
	var day_night := root.get_node("DayNight")
	var flies := root.get_node("Fireflies")
	var mm := (flies.get_child(0) as MultiMeshInstance3D)
	var player := get_first_node_in_group("player") as Node3D
	var terrain := get_first_node_in_group("terrain") as Terrain3D
	for t in [0.5, 0.86, 0.95, 0.02, 0.1]:
		day_night.set("time", t)
		for i in 30:
			await process_frame
		var amount: float = flies.call("amount")
		var bad := 0
		var spots: PackedVector3Array = flies.get("_pos")  # (the headless renderer keeps no MultiMesh data)
		for p in spots:
			var ground := terrain.data.get_height(p)
			var off := Vector2(p.x - player.global_position.x, p.z - player.global_position.z).length()
			if mm.visible and (off > 27.0 or (not is_nan(ground) and (p.y < ground + 0.35 or p.y > ground + 2.3))):
				bad += 1
		print("time %.2f: amount %.2f, visible %s, %d misplaced" % [t, amount, mm.visible, bad])
		if t == 0.5 or t == 0.1:
			_check(not mm.visible, "none out at time %.2f" % t)
		else:
			_check(mm.visible and amount > 0.5, "a swarm out at time %.2f" % t)
			_check(bad == 0, "all over the ground near the player at time %.2f" % t)
	print("test_fireflies: %s" % ("PASS" if _fails == 0 else "%d FAILED" % _fails))
	quit(1 if _fails else 0)


func _check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		_fails += 1
