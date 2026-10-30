extends SceneTree
## Checks the path lamps (scripts/path_lamps.gd, scripts/autoload/lamps.gd) in Hearthvale: a new
## world lights only the village path; lighting every stretch puts posts
## along each, none in water, on steep ground or crowding each other; the lit list saves.
##   godot --headless --path . -s res://tools/test_lamps.gd -- --save-root=user://tool_worlds

var _fails := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var worlds := root.get_node("Worlds")
	worlds.call("_ensure_classic")
	worlds.call("reset", worlds.get("CLASSIC"))
	worlds.call("play", worlds.get("CLASSIC"))
	await _world_ready()
	await _check_world("Hearthvale")
	print("test_lamps: %s" % ("PASS" if _fails == 0 else "%d FAILED" % _fails))
	quit(1 if _fails else 0)


func _world_ready() -> void:
	for i in 3:
		await process_frame
	while get_first_node_in_group("path_lamps") == null:
		await process_frame
	for i in 3:
		await process_frame


func _check_world(world: String) -> void:
	var lamps_auto := root.get_node("Lamps")
	var path_lamps := get_first_node_in_group("path_lamps")
	var stretches: Array = lamps_auto.get("stretches")
	print("%s: %d stretches" % [world, stretches.size()])
	_check(stretches.size() >= 2, "%s lists its stretches" % world)
	var lit: Dictionary = {}
	for p in path_lamps.call("posts"):
		lit[p.get_meta("stretch")] = true
	_check(lit.keys() == [&"village_path"], "%s: a new world lights only the village path (%s)" % [world, lit.keys()])
	lamps_auto.call("light_all", true)
	var counts: Dictionary = {}
	var posts: Array = path_lamps.call("posts")
	var terrain := get_first_node_in_group("terrain") as Terrain3D
	var wet := 0
	var crowded := 0
	for p in posts:
		var s: StringName = p.get_meta("stretch")
		counts[s] = int(counts.get(s, 0)) + 1
		var ground := terrain.data.get_height(p.global_position)
		if _in_water(p.global_position + Vector3.UP * 0.1):
			wet += 1
			print("  in water: %s" % p.global_position)
		elif is_nan(ground) or absf(p.global_position.y - (ground - 0.05)) > 0.05:
			wet += 1
			print("  off the ground: %s (ground %.2f)" % [p.global_position, ground])
		for q in posts:
			if q != p and q.global_position.distance_to(p.global_position) < float(path_lamps.get("MIN_GAP")) - 0.5:
				crowded += 1
	for s in stretches:
		print("  %-40s %d posts" % [s["title"], counts.get(s["id"], 0)])
	print("%s: %d posts in all" % [world, posts.size()])
	_check(posts.size() > stretches.size(), "%s: every stretch lit puts up posts" % world)
	_check(wet == 0, "%s: no post in water or off the ground (%d)" % [world, wet])
	_check(crowded == 0, "%s: no two posts crowd each other (%d)" % [world, crowded])
	await _check_wave(world, path_lamps)
	var saved: Dictionary = lamps_auto.call("to_dict")
	_check((saved["lit"] as Array).size() == stretches.size(), "%s: the lit list saves" % world)
	lamps_auto.call("from_dict", {})
	var left := _count(path_lamps, &"village_path")
	_check(left > 0 and (path_lamps.call("posts") as Array).size() == left, "%s: back to the village path on a fresh save (%d posts)" % [world, left])


## Dark by day; at dusk the lamps near the village catch before the far ones, each once; all
## burning by full night.
func _check_wave(world: String, path_lamps: Node) -> void:
	var day_night := root.get_node("DayNight")
	day_night.set("frozen", true)
	day_night.set("time", 0.5)
	for i in 5:
		await process_frame
	var lamps: Array = path_lamps.get("_lamps")
	# (a new road's posts go up one after another: a long road's last ones take seconds)
	while lamps.any(func(l: Dictionary) -> bool: return float(l["delay"]) > 0.0):
		await process_frame
	var lit_by_day := 0
	for l in lamps:
		if float(l["level"]) > 0.0:
			lit_by_day += 1
	_check(lit_by_day == 0, "%s: no lamp burns at noon (%d)" % [world, lit_by_day])
	var caught := [0]
	var count := func(_at: Vector3) -> void: caught[0] += 1
	path_lamps.connect("lamp_caught", count)
	var first: Dictionary = {}  # lamp index -> frame it caught
	var frame := 0
	var t := 0.78
	while t < 0.92:
		day_night.set("time", t)
		await process_frame
		for i in lamps.size():
			if not first.has(i) and float(lamps[i]["level"]) > 0.0:
				first[i] = frame
		frame += 1
		t += 0.0004
	for i in 60:
		await process_frame
	path_lamps.disconnect("lamp_caught", count)
	var near_last := -1
	var far_first := 1 << 30
	var full := 0
	for i in lamps.size():
		var w: float = lamps[i]["wave"]
		if w < 0.3:
			near_last = maxi(near_last, first.get(i, 1 << 30))
		elif w > 0.7:
			far_first = mini(far_first, first.get(i, 1 << 30))
		if float(lamps[i]["level"]) >= 1.0:
			full += 1
	print("%s: near lamps all lit by frame %d, far ones start at %d" % [world, near_last, far_first])
	_check(near_last < far_first, "%s: the wave runs out from the village" % world)
	_check(caught[0] == lamps.size(), "%s: each lamp catches once (%d of %d)" % [world, caught[0], lamps.size()])
	_check(full == lamps.size(), "%s: all burning by full night (%d of %d)" % [world, full, lamps.size()])
	day_night.set("frozen", false)


func _count(path_lamps: Node, stretch: StringName) -> int:
	var n := 0
	for p in path_lamps.call("posts"):
		if p.get_meta("stretch") == stretch:
			n += 1
	return n


func _in_water(at: Vector3) -> bool:
	for w in get_nodes_in_group("water"):
		if float(w.call("depth_here", at)) > 0.0:
			return true
	return false


func _check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		_fails += 1
