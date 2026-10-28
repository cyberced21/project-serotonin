extends SceneTree
## Checks the village projects (scripts/autoload/projects.gd): the board lists the decorations and
## a road-lamps project per stretch not lit from the start; nothing is paid without the goods or
## before the town hall allows it; paying spends the goods, marks it done and saves it; a road
## project lights its road.
##   godot --headless --path . -s res://tools/test_projects.gd -- --save-root=user://tool_worlds

var _fails := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var worlds := root.get_node("Worlds")
	worlds.call("_ensure_classic")
	worlds.call("reset", worlds.get("CLASSIC"))
	worlds.call("play", worlds.get("CLASSIC"))
	for i in 3:
		await process_frame
	while get_first_node_in_group("path_lamps") == null:
		await process_frame
	await _frames(5)
	var projects := root.get_node("Projects")
	var inventory := root.get_node("Inventory")
	var village := root.get_node("Village")
	var lamps := root.get_node("Lamps")
	var all: Array = projects.call("all")
	var roads := all.filter(func(p: Dictionary) -> bool: return p["road"] != &"")
	print("%d projects, %d of them road lamps" % [all.size(), roads.size()])
	for p in all:
		print("  %-48s hall %d  %s" % [p["title"], p["hall"], p["cost"]])
	_check(all.size() == 6 + roads.size() and roads.size() >= 5, "six decorations and a road project per unlit stretch")
	_check(not projects.call("can_pay", &"benches"), "no goods, no benches")
	inventory.call("add", &"wood", 40)
	_check(projects.call("pay", &"benches") and projects.call("is_done", &"benches"), "paid for, the benches are done")
	_check(inventory.call("count", &"wood") == 30, "they cost their logs (%d left)" % inventory.call("count", &"wood"))
	_check(not projects.call("pay", &"benches"), "nor can they be bought twice")
	inventory.call("add", &"ore", 40)
	_check(projects.call("is_locked", &"well") and not projects.call("pay", &"well"), "the well waits for the town hall")
	village.call("set_tier", &"town_hall", 2)
	_check(not projects.call("is_locked", &"well") and projects.call("pay", &"well"), "with the hall at tier 2, the well")
	var near: Array = roads.filter(func(p: Dictionary) -> bool: return p["hall"] == 1)
	_check(not near.is_empty(), "some road near the village is cheaper and open at once")
	inventory.call("add", &"coal", 10)
	var road: Dictionary = near[0]
	_check(projects.call("pay", road["id"]) and lamps.call("is_lit", road["road"]), "a road project lights its road")
	var saved: Dictionary = projects.call("to_dict")
	_check(saved["done"].has("benches") and saved["done"].has("well"), "done projects save")
	projects.call("from_dict", {})
	_check(not projects.call("is_done", &"benches"), "a fresh save has none")
	# the noticeboard, in Hearthvale and in a generated village
	await _check_board("Hearthvale", projects)
	worlds.call("play_scratch", 42)
	for i in 3:
		await process_frame
	while get_first_node_in_group("loading_screen") != null or get_first_node_in_group("player") == null:
		await process_frame
	await _frames(5)
	await _check_board("seed 42", projects)
	print("test_projects: %s" % ("PASS" if _fails == 0 else "%d FAILED" % _fails))
	quit(1 if _fails else 0)


func _check_board(world: String, projects: Node) -> void:
	var board := get_first_node_in_group("noticeboard") as Node3D
	var decor := get_first_node_in_group("village_decor") as Node3D
	_check(board != null, "%s has a noticeboard" % world)
	if board == null:
		return
	var center: Vector2 = decor.get("center")
	var off := Vector2(board.global_position.x, board.global_position.z).distance_to(center)
	print("%s: the board stands %.1f m from the middle of the square, prompt: %s" % [world, off, board.call("prompt")])
	_check(off > 7.0 and off < 16.0, "%s: by the square, not on it" % world)
	var player := get_first_node_in_group("player") as Node3D
	player.global_position = board.global_position + board.global_basis.z * 2.0 + Vector3.UP
	await _frames(3)
	board.call("interact")
	await _frames(3)
	var panel := get_first_node_in_group("noticeboard_panel")
	var notes: int = (panel.get("_grid") as Node).get_child_count() if panel else 0
	_check(panel != null and panel.call("is_open") and notes == (projects.call("all") as Array).size(),
			"%s: E opens it, a note per project (%d)" % [world, notes])
	if panel:
		panel.call("close")
	# every decoration, done: its props stand on the ground, clear of the buildings; undone, gone
	var buildings := get_nodes_in_group("building")
	var terrain := get_first_node_in_group("terrain") as Terrain3D
	for id in [&"benches", &"flower_boxes", &"well", &"bunting", &"fountain"]:
		projects.call("set_done", id, true)
		await _frames(2)
		var props: Array = decor.call("props_of", id)
		var bad := 0
		for p in props:
			var n := p as Node3D
			var h := terrain.data.get_height(n.global_position)
			if id != &"bunting" and (is_nan(h) or absf(n.global_position.y - h) > 0.2):
				bad += 1
			for b in buildings:
				if id != &"bunting" and Vector2(n.global_position.x - b.global_position.x, n.global_position.z - b.global_position.z).length() < 4.5:
					bad += 1
		_check(props.size() > 0 and bad == 0, "%s: %s stands (%d pieces, %d misplaced)" % [world, id, props.size(), bad])
		projects.call("set_done", id, false)
		await _frames(2)
		_check((decor.call("props_of", id) as Array).is_empty(), "%s: undone, %s is gone" % [world, id])


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		_fails += 1
