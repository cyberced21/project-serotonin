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
	var sheet: Node = mine.get("map")
	_check(not get_first_node_in_group("world_map").call("_can_open"), "the world map stands aside down here")
	_press_map()
	await process_frame
	await process_frame
	_check(sheet.call("is_open") and paused, "M shows the level's map (and pauses)")
	_check(not get_first_node_in_group("world_map").call("is_open"), "not the world map")
	_press_map()
	await process_frame
	await process_frame
	_check(not sheet.call("is_open") and not paused, "M again puts it away")
	var chalk := 0
	for p: Node in l1.call("panels"):
		for c in p.get_children():
			if c is Label3D and String(c.text) == "dig here":
				chalk += 1
	_check(chalk >= 3, "the way in's faces say dig here (%d)" % chalk)

	# dig through a face: the cell behind opens, fresh
	var face: Node = null
	for p: Node in l1.call("panels"):
		if p.get("give_way_at") > 0:
			face = p
			break
	_check(face != null, "a dig face to dig")
	var before: int = mine.call("open_count", 0)
	_dig_hole(face, 2, 0.3)
	await process_frame
	_check(mine.call("open_count", 0) == before, "a small hole in a face isn't through yet")
	_dig_hole(face, 2, 0.45)
	var whole_layers: int = face.get("front")
	await process_frame
	await process_frame
	var after: int = mine.call("open_count", 0)
	_check(after == before + 1 and whole_layers == 0,
			"a hole dug into it (no layer cleared whole), it gives way: %d -> %d cells open" % [before, after])
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
		_dig_hole(seam, 4, 0.3)
		_check(not seam.call("is_available"), "a seam dug well into is spent")
		seam.set("regrow_left", 0.01)
		seam.set("_near", false)
		await _settle(3)
		_check(seam.call("is_available") and seam.get("front") == 0, "and grows back")
	else:
		print("(no seam round the first cells: skipped)")

	# one cell left hidden with tunnel dug up to it on every side: each face into it still takes a
	# swing (the alcoves dug into it from the other sides, and the far face's own box, used to stand
	# flush with it and catch every swing)
	var hidden := Vector2i(-1, -1)
	for c: Vector2i in _cells(0):
		var sides := 0
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			if _cells(0).has(c + d):
				sides += 1
		if sides >= 3 and not mine.call("is_open", 0, c) and String(load("res://scripts/mine_layout.gd").call("at", 0, c)) == ".":
			hidden = c
			break
	if hidden.x >= 0:
		for c in _cells(0):
			if c != hidden:
				mine.call("open_cell", 0, c)
		await process_frame
		await process_frame
		await _settle(3)
		var facing := 0
		var reached := 0
		var space := player.get_world_3d().direct_space_state
		for p: Node3D in l1.call("panels"):
			if p.get("give_way_at") <= 0:
				continue
			facing += 1
			player.global_position = p.global_transform * Vector3(0, 0.1, 2.0)  # (stood at it: hulls per piece)
			await _settle(2)
			var ok := true
			for aim in [Vector3(0, 1.4, 0), Vector3(-1.0, 0.6, 0), Vector3(1.0, 2.4, 0)]:
				var from: Vector3 = p.global_transform * (aim + Vector3(0, 0, 1.6))
				var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, p.global_transform * (aim - Vector3(0, 0, 0.5)), 1))
				ok = ok and not hit.is_empty() and (hit["collider"] == p or p.is_ancestor_of(hit["collider"]))
			reached += 1 if ok else 0
		_check(facing >= 3 and reached == facing, "a cell dug up to from %d sides: a swing reaches every face into it (%d of %d)" % [facing, reached, facing])
	else:
		print("(no cell to leave hidden: skipped)")

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
	var note: Dictionary = load("res://scripts/home_notes.gd").write(self)
	_check(note.get("from") == "Edda" and String(note.get("text", "")).length() > 20, "Edda writes about what you found: '%s'" % note.get("text", ""))
	_check(String(load("res://scripts/trophies.gd").title({"kind": "fossil"})) == "Fossil", "a fossil is a trophy")

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

	# the flood: seen, pumped dry, dug on past
	var flood := Vector2i(4, 2)
	mine.call("open_cell", 1, Vector2i(4, 3))
	mine.call("open_cell", 1, flood)
	await process_frame
	await process_frame
	listed = (projects.call("all") as Array).map(func(p: Dictionary) -> StringName: return p["id"])
	_check(&"mine_pump" in listed, "the flooded tunnel puts the pump on the board")
	_check(not mine.call("is_passable", 1, flood), "flooded: no way through")
	var l2: Node3D = mine.get("levels")[1]
	_check(l2.call("panel_at", flood, 3) == null, "no dig face beyond the water while it's flooded")
	projects.call("set_done", &"mine_pump", true)
	await process_frame
	_check(mine.call("is_passable", 1, flood), "pumped dry: through")
	_check(l2.call("panel_at", flood, 3) != null, "and a dig face on toward the stream")
	# the roof fall
	projects.call("set_done", &"mine_supports", true)
	await process_frame
	_check(mine.call("is_passable", 0, Vector2i(1, 4)), "the roof fall propped up: through")
	# the lift on down to level 3
	_check(not mine.call("lift_reaches", 2), "the lift stops at level 2 for now")
	projects.call("set_done", &"mine_lift_3", true)
	await process_frame
	_check(mine.call("lift_reaches", 2), "lengthened, it reaches level 3")
	mine.call("go_to", 2, Vector2i(5, 3))
	await _until(func() -> bool: return mine.get("here") == 2 and not mine.get("_travelling"), 8.0)
	_check(mine.get("here") == 2, "down on level 3")

	# the minecart: down from the top to the deepest stop that's dug out
	projects.call("set_done", &"mine_rails", true)
	mine.call("open_cell", 1, Vector2i(6, 4))
	await process_frame
	_check(mine.call("ride_to", 0) == 1, "the cart runs down to level 2's stop (level 3's isn't dug out)")
	mine.call("go_to", 0, Vector2i(5, 3))
	await _until(func() -> bool: return mine.get("here") == 0 and not mine.get("_travelling"), 8.0)
	mine.call("ride", 0)
	await _until(func() -> bool: return mine.get("riding") != null, 5.0)
	var trip: Node = mine.get("riding")
	_check(trip != null, "the ride starts")
	if trip:
		await _settle(30)
		var cam := root.get_viewport().get_camera_3d()
		_check(cam != null and trip.is_ancestor_of(cam), "riding in the cart's seat")
		trip.set("_t", 999.0)
	await _until(func() -> bool: return mine.get("here") == 1 and not mine.get("_travelling"), 10.0)
	_check(mine.get("here") == 1, "climbed out on level 2")
	_check(root.get_viewport().get_camera_3d() == player.get("camera"), "back in your own eyes")

	# out again, by the cage in the shaft over the way in: ring for it, it comes down, ride it up
	mine.call("go_to", 0, load("res://scripts/mine_layout.gd").call("cells_of", 0, "E")[0])
	await _until(func() -> bool: return mine.get("here") == 0 and not mine.get("_travelling"), 8.0)
	var shafts: Array = (mine.get("levels")[0] as Node).find_children("*", "MineShaft", true, false)
	_check(shafts.size() == 1, "a shaft with its cage over the way in")
	if shafts.size() == 1:
		var shaft: Node3D = shafts[0]
		var cage := shaft.get("_cage") as Node3D
		shaft.call("arrive")
		var stood := player.global_position
		player.global_position = shaft.global_position + Vector3.UP * 6.0  # (well away from the cage)
		await _until(func() -> bool: return cage.position.y > 3.0 and not shaft.get("_moving"), 12.0)
		_check(cage.position.y > 3.0, "stepped off, the cage goes back up the shaft (%.1f m)" % cage.position.y)
		_check(String(shaft.call("_prompt")).begins_with("E  Ring"), "...and you ring for it: '%s'" % shaft.call("_prompt"))
		player.global_position = stood
		shaft.call("_act")
		await _until(func() -> bool: return shaft.call("is_down"), 6.0)
		_check(cage.position.y < 0.05, "it comes down out of the roof")
		_check(String(shaft.call("_prompt")).begins_with("E  Ride"), "...and takes you up: '%s'" % shaft.call("_prompt"))
		shaft.call("_act")
	else:
		mine.call("leave")
	await _until(func() -> bool: return mine.get("here") == -1 and not mine.get("_travelling"), 8.0)
	await _settle(10)
	print("out at ", player.global_position)
	_check(player.global_position.distance_to(mouth.global_position) < 4.0, "back up by the mouth")
	_check(biome.get("current") == &"quarry", "in the quarry's light again (%s)" % biome.get("current"))
	_finish()


## Digs out `share` of the pieces of a panel's first `layers` layers, nearest its middle first
## (a hole, the way a pick goes in), then lets it check how far in it is.
func _dig_hole(panel: Node, layers: int, share: float) -> void:
	var gone: Array = panel.get("_gone")
	for k in layers:
		var pieces: Array = panel.call("_layer_pieces", k)
		var order := range(pieces.size())
		order.sort_custom(func(a: int, b: int) -> bool:
			var ca: Vector3 = pieces[a]["centre"]
			var cb: Vector3 = pieces[b]["centre"]
			return Vector2(ca.x, ca.y - 2.0).length() < Vector2(cb.x, cb.y - 2.0).length())
		for i in order.slice(0, int(pieces.size() * share)):
			(gone[k] as Dictionary)[i] = true
	panel.call("_check_depth")


func _press_map() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	var ev := InputEventAction.new()
	ev.action = &"map"
	ev.pressed = true
	Input.parse_input_event(ev)
	var up := InputEventAction.new()
	up.action = &"map"
	Input.parse_input_event(up)


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
