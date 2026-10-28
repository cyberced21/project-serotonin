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
	await _check_build(projects, inventory)
	await _check_life(projects)
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
	await _check_bridge(world, projects, decor)
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


## Paid for at the board (by day, villagers out): pieces hidden at first, a villager walks over
## and hammers, every piece up by the end, the builder free again; a paid road's posts rise one
## by one.
func _check_build(projects: Node, inventory: Node) -> void:
	var day_night := root.get_node("DayNight")
	day_night.set("frozen", true)
	day_night.set("time", 0.4)
	await _frames(20)
	var decor := get_first_node_in_group("village_decor")
	inventory.call("add", &"wood", 20)
	_check(projects.call("pay", &"benches"), "build: paid for the benches")
	await _frames(1)
	var pieces: Array = decor.call("props_of", &"benches")
	_check(not pieces.is_empty() and not (pieces[0] as Node3D).visible, "build: the benches aren't there yet")
	Engine.time_scale = 3.0
	var builder: Node = null
	var t := 0.0
	while t < 40.0:
		await physics_frame
		t += 1.0 / 60.0  # (a physics tick is 1/60 of game time, whatever the time scale)
		for b in get_nodes_in_group("building"):
			for c in b.get_children():
				if c.get("scripted") == true:
					builder = c
		var up := pieces.all(func(p: Node3D) -> bool: return p.visible and p.scale.x > 0.95)
		if up and builder and builder.get("scripted") == false:
			break
	Engine.time_scale = 1.0
	print("build: done in %.1f s, builder %s" % [t, builder.name if builder else "none"])
	_check(builder != null, "build: a villager came to build them")
	_check(pieces.all(func(p: Node3D) -> bool: return p.visible and p.scale.x > 0.95), "build: both benches up")
	_check(builder == null or builder.get("scripted") == false, "build: the builder goes back to work")
	# a road
	var roads: Array = (projects.call("all") as Array).filter(func(p: Dictionary) -> bool: return p["road"] != &"" and not p["done"] and p["hall"] == 1)
	inventory.call("add", &"wood", 20); inventory.call("add", &"ore", 10); inventory.call("add", &"coal", 10)
	_check(not roads.is_empty() and projects.call("pay", roads[0]["id"]), "build: paid for a road's lamps")
	await _frames(2)
	var lamps: Array = get_first_node_in_group("path_lamps").get("_lamps")
	var new := lamps.filter(func(l: Dictionary) -> bool: return (l["prop"] as Node).get_meta("stretch") == roads[0]["road"])
	var hidden := new.filter(func(l: Dictionary) -> bool: return (l["prop"] as Node3D).scale.x < 0.1).size()
	_check(new.size() > 0 and hidden == new.size(), "build: its posts start down (%d of %d)" % [hidden, new.size()])
	for i in 60 * (2 + int(new.size() * 0.35) + 1):
		await process_frame
	var up := new.filter(func(l: Dictionary) -> bool: return (l["prop"] as Node3D).scale.x > 0.95).size()
	_check(up == new.size(), "build: and rise one by one along it (%d up)" % up)
	day_night.set("frozen", false)


## At dusk someone sits on each new bench; by day someone draws water at the well.
func _check_life(projects: Node) -> void:
	var day_night := root.get_node("DayNight")
	var decor := get_first_node_in_group("village_decor")
	projects.call("set_done", &"benches", true)
	projects.call("set_done", &"well", true)
	day_night.set("frozen", true)
	day_night.set("time", float(day_night.get("SUNSET")) - 0.05)
	var player := get_first_node_in_group("player") as Node3D
	player.global_position += Vector3(0, 0, 40)  # out of the way (villagers stop to chat)
	Engine.time_scale = 3.0
	var seated := 0
	for i in 60 * 30:
		await physics_frame
		seated = 0
		for bench in decor.call("props_of", &"benches"):
			for b in get_nodes_in_group("building"):
				for c in b.get_children():
					if c.has_method("_seated") and c.call("_seated") and (c as Node3D).global_position.distance_to((bench as Node3D).global_position) < 0.5:
						seated += 1
		if seated == 2:
			break
	print("life: %d on the benches at dusk" % seated)
	_check(seated == 2, "life: someone sits on each new bench at dusk")
	day_night.set("time", 0.4)
	await _frames(10)
	var drawn := [0]
	decor.connect("water_drawn", func(_at: Vector3) -> void: drawn[0] += 1)
	decor.set("_well_in", 0.1)
	for i in 60 * 25:
		await physics_frame
		if drawn[0] > 0 and decor.get("_drawing") == null:
			break
	Engine.time_scale = 1.0
	_check(drawn[0] == 1 and decor.get("_drawing") == null, "life: someone draws water at the well, then gets on")
	day_night.set("frozen", false)


## The footbridge: on the board where there's somewhere for it; done, it spans the gap or the
## ford, you can stand on it, and you're out of the water on it.
func _check_bridge(world: String, projects: Node, decor: Node) -> void:
	var site: Array = decor.get("footbridge_site")
	var listed := (projects.call("all") as Array).any(func(p: Dictionary) -> bool: return p["id"] == &"footbridge")
	print("%s: footbridge site %s" % [world, site])
	_check(listed == not site.is_empty(), "%s: the footbridge is on the board only if there's a place for it" % world)
	if site.is_empty():
		return
	projects.call("set_done", &"footbridge", true)
	await _frames(2)
	var bridge := get_first_node_in_group("footbridge") as Node3D
	_check(bridge != null, "%s: done, the footbridge stands" % world)
	if bridge == null:
		return
	var mid: Vector3 = bridge.call("deck_at", 0.5)
	var terrain := get_first_node_in_group("terrain") as Terrain3D
	var below := mid.y - terrain.data.get_height(mid)
	print("%s: deck %.1f m above the ground at its middle" % [world, below])
	var player := get_first_node_in_group("player") as Node3D
	player.global_position = mid + Vector3.UP * 1.0
	for i in 60:
		await physics_frame
	var stood := absf(player.global_position.y - mid.y) < 0.5
	_check(stood, "%s: you can stand on it (feet %.2f, deck %.2f)" % [world, player.global_position.y, mid.y])
	_check(bridge.get_script().call("on_bridge", self, player.global_position), "%s: and you're out of the water on it" % world)
	projects.call("set_done", &"footbridge", false)
	await _frames(2)


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		_fails += 1
