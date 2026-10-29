extends SceneTree
## Checks the mine's framework and first level (plans/mine.md, phase 3) in a fresh Hearthvale:
## the mouth stays boarded until the mine is shored up; through it you come down to level 1's way
## in, in the dark of the mine; its dig faces stand round the open cells; digging one through opens
## the cell behind (fresh till dawn, then shored), which brings new faces; seams regrow; it all
## survives a save; the roof fall puts its project on the board; the way out takes you back up.
##   godot --headless --path . -s res://tools/test_mine.gd -- --save-root=user://tmp
## (No game class names: an -s script compiles before the autoloads exist.)

var _fails := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.get_node("Worlds").call("play_fresh")
	while get_first_node_in_group("player") == null:
		await process_frame
	for i in 30:
		await physics_frame
	var player := get_first_node_in_group("player") as Node3D
	var mine := get_first_node_in_group("mine") as Node3D
	var mouth := get_first_node_in_group("mine_mouth") as Node3D
	var projects := root.get_node("Projects")
	var biome := root.get_node("Biome")
	_check(mine != null and mouth != null, "the mine and its mouth are in the world")
	if mine == null or mouth == null:
		_finish()
		return
	var l1: Node3D = mine.get("levels")[0]
	_check(mine.call("open_count", 0) == 1, "only the way in is open to start with")
	var faces: Array = l1.call("panels")
	print("level 1 starts with %d panels" % faces.size())
	_check(faces.size() >= 3, "dig faces stand round the way in")

	# the mouth: boarded, then shored and in
	var spot: Node = mouth.find_children("*", "StaticBody3D", false, false).filter(func(n: Node) -> bool: return n.has_method("prompt"))[0]
	_check(String(spot.call("prompt")).begins_with("Boarded"), "boarded: '%s'" % spot.call("prompt"))
	projects.call("set_done", &"mine_shoring", true)
	await process_frame
	_check(String(spot.call("prompt")).begins_with("E  Go down"), "shored: '%s'" % spot.call("prompt"))
	spot.call("interact")
	await _until(func() -> bool: return mine.get("here") == 0 and not mine.get("_travelling"), 8.0)
	print("in the mine at ", player.global_position)
	_check(mine.get("here") == 0, "down on level 1")
	_check(biome.get("current") == &"mine", "in the mine's light (%s)" % biome.get("current"))
	_check(root.get_node("Lamps").get("lantern_lit") or not root.get_node("Lamps").get("has_lantern"),
			"the lantern's lit down here (if you have it)")
	await _settle(10)
	_check(player.global_position.y > -41.0 and player.global_position.y < -38.0, "standing on the floor (y %.2f)" % player.global_position.y)
	_check(get_nodes_in_group("mine_lamp").size() > 0, "lamps are lit on the shored level")

	# dig through a face: the cell behind opens, fresh
	var face: Node = null
	for p: Node in l1.call("panels"):
		if p.get("give_way_at") > 0:
			face = p
			break
	_check(face != null, "a dig face to dig")
	var before: int = mine.call("open_count", 0)
	face.call("dig_layers", 2)
	await process_frame
	await process_frame
	var after: int = mine.call("open_count", 0)
	_check(after == before + 1, "digging two layers in, it gives way: %d -> %d cells open" % [before, after])
	_check(not is_instance_valid(face) or face.is_queued_for_deletion(), "the face that gave way is gone")
	var fresh := 0
	for c in _cells(0):
		if mine.call("is_fresh", 0, c):
			fresh += 1
	_check(fresh == 1, "the new cell is fresh till dawn")
	root.get_node("DayNight").emit_signal("day_broke")
	await process_frame
	fresh = 0
	for c in _cells(0):
		if mine.call("is_fresh", 0, c):
			fresh += 1
	_check(fresh == 0, "shored by the morning")

	# a seam: spent, then whole again
	var seam: Node = null
	for p: Node in l1.call("panels"):
		if p.get("spent_at") > 0:
			seam = p
			break
	if seam:
		seam.call("dig_layers", 4)
		_check(not seam.call("is_available"), "a seam dug four layers in is spent")
		seam.set("regrow_left", 0.01)
		seam.set("_near", false)
		await _settle(3)
		_check(seam.call("is_available") and seam.get("front") == 0, "and grows back")
	else:
		print("(no seam round the first cells: skipped)")

	# opening everything on level 1 (the way the player would, cell by cell)
	for c in _cells(0):
		mine.call("open_cell", 0, c)
	await process_frame
	await process_frame
	_check(mine.call("open_count", 0) == _cells(0).size(), "every cell of level 1 opens")
	var listed := (projects.call("all") as Array).map(func(p: Dictionary) -> StringName: return p["id"])
	_check(&"mine_supports" in listed, "the roof fall puts its supports on the board")
	_check(&"mine_lift" in listed, "the shaft dug into puts the lift on the board")
	_check(not (&"mine_pump" in listed), "the pump waits till you've seen the flood")

	# saves
	var saved: Dictionary = mine.call("to_dict")
	mine.call("from_dict", {})
	_check(mine.call("open_count", 0) == 1, "a fresh mine again from nothing")
	mine.call("from_dict", saved)
	_check(mine.call("open_count", 0) == _cells(0).size(), "and back from the save")

	# the lift, once built
	projects.call("set_done", &"mine_lift", true)
	await process_frame
	_check(mine.call("lift_reaches", 1) and mine.call("open_count", 1) >= 1, "the lift reaches level 2: its stop is open")
	mine.call("go_to", 1, Vector2i(4, 4))
	await _until(func() -> bool: return mine.get("here") == 1 and not mine.get("_travelling"), 8.0)
	_check(mine.get("here") == 1, "down on level 2")
	await _settle(10)
	_check(player.global_position.y > -61.0 and player.global_position.y < -58.0, "standing on level 2's floor (y %.2f)" % player.global_position.y)

	# out again
	mine.call("leave")
	await _until(func() -> bool: return mine.get("here") == -1 and not mine.get("_travelling"), 8.0)
	await _settle(10)
	print("out at ", player.global_position)
	_check(player.global_position.distance_to(mouth.global_position) < 4.0, "back up by the mouth")
	_check(biome.get("current") == &"quarry", "in the quarry's light again (%s)" % biome.get("current"))
	_finish()


func _cells(n: int) -> Array:
	var out := []
	var rows: Array = load("res://scripts/mine_layout.gd").LEVELS[n]["map"]
	for y in rows.size():
		for x in (rows[y] as String).length():
			if (rows[y] as String)[x] != "#":
				out.append(Vector2i(x, y))
	return out


func _settle(frames: int) -> void:
	for i in frames:
		await physics_frame


func _until(cond: Callable, seconds: float) -> void:
	var t0 := Time.get_ticks_msec()
	while not cond.call() and Time.get_ticks_msec() - t0 < seconds * 1000.0:
		await process_frame


func _check(ok: bool, what: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + what)
	if not ok:
		_fails += 1


func _finish() -> void:
	print("%d failed" % _fails if _fails else "all passed")
	quit(1 if _fails else 0)
