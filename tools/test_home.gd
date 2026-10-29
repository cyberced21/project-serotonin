extends SceneTree
## Checks your home (plans/home.md, phase 4) in a fresh Hearthvale: a new game starts by the tent;
## the tent's bedroll sleeps only after midnight, the cabin's bed from dusk, never by day; sleeping
## skips to first light, moves regrowth on by the same time, puts you by the bed and saves; the
## plans open the upgrade panel for the home.
##   godot --headless --path . -s res://tools/test_home.gd -- --save-root=user://tool_worlds
## (No game class names: an -s script compiles before the autoloads exist.)

var _fails := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.get_node("Worlds").call("play_fresh")
	await process_frame
	while get_first_node_in_group("player") == null:
		await process_frame
	for i in 10:
		await physics_frame
	var player := get_first_node_in_group("player") as Node3D
	var home := get_first_node_in_group("home") as Node3D
	var day := root.get_node("DayNight")
	var village := root.get_node("Village")
	_check(home != null, "there's a home in the world")
	if home == null:
		_finish()
		return
	_check(player.global_position.distance_to(home.global_position) < 12.0, "a new game starts by the tent (%.1f m)"
			% player.global_position.distance_to(home.global_position))
	_check(home.get("tier_shown") == 1, "it starts as a tent")
	_check(home.call("mark", "Bed") != null and home.call("mark", "DogBed") != null and home.call("mark", "Plans") != null,
			"the tent has a bedroll, the dog's patch and the plans")

	# the tent: the small hours only
	day.set("time", _at(15.0))
	_check(not home.call("can_sleep"), "15:00: not tired yet (%s)" % home.call("not_yet"))
	day.set("time", _at(22.0))
	_check(not home.call("can_sleep"), "22:00 in the tent: not before midnight (%s)" % home.call("not_yet"))
	day.set("time", _at(1.0))
	_check(home.call("can_sleep"), "01:00 in the tent: the bedroll will do")

	# a felled tree an hour from regrowing...
	var node: Node = null
	for n in get_nodes_in_group("gatherable"):
		if n.has_method("fast_forward") and n.get("skill") == &"woodcutting":
			node = n
			break
	var timer: SceneTreeTimer = null
	if node:
		node.set("_respawn_timer", create_timer(9999.0))
		timer = node.get("_respawn_timer")
	# ...sleep: wait for the fade, the skip and the fade back
	var slept := [false]
	home.connect("slept", func(_full: bool) -> void: slept[0] = true)
	home.call("sleep")
	var t0 := Time.get_ticks_msec()
	while home.get("sleeping") and Time.get_ticks_msec() - t0 < 15000:
		await process_frame
	_check(slept[0], "you slept")
	var h: float = _hours(day.get("time"))
	_check(absf(h - 6.0) < 0.1, "...and woke at first light (%.2f)" % h)
	if timer:  # (01:00 to 06:00 is five night hours: ~36 s each)
		_check(timer.time_left < 9999.0 - 150.0, "...with regrowth moved on by the night (%.0f s left)" % timer.time_left)
		node.set("_respawn_timer", null)
	var wake := home.call("mark", "Wake") as Node3D
	_check(player.global_position.distance_to(wake.global_position) < 1.0, "...standing by the bed")
	_check(not player.get("cutscene"), "...free to move again")
	_check(root.get_node("SaveGame").call("has", &"village"), "...and the game saved")

	# the cabin: the bed from dusk
	village.call("set_tier", &"home", 2)
	for i in 240:
		await physics_frame
	_check(home.get("tier_shown") == 2, "the plans build a cabin")
	day.set("time", _at(21.0))
	_check(home.call("can_sleep"), "21:00 in the cabin: the bed's ready from dusk")
	day.set("time", _at(13.0))
	_check(not home.call("can_sleep"), "13:00: never by day")
	player.call("teleport", home.to_global(Vector3(0, 0, 9)))
	await physics_frame
	_check(home.call("has_player") == false, "standing outside the cabin isn't indoors")
	player.call("teleport", home.to_global(Vector3(0.5, 0, 0.5)))
	await physics_frame
	_check(home.call("has_player") == true, "standing inside it is")

	# the plans open the upgrade panel for the home
	var plans: Node = null
	for c in home.get_node("Tier2").get_children():
		if c.has_method("prompt") and String(c.call("prompt")).contains("Plans"):
			plans = c
	_check(plans != null, "the cabin has its plans on the table")
	if plans:
		await create_timer(0.4).timeout  # (the panel ignores an E right after closing)
		plans.call("interact")
		var panel := get_first_node_in_group("upgrade_panel")
		_check(panel.call("is_open"), "E on the plans opens the home's upgrades")
		panel.call("close")
	_finish()


func _at(hour: float) -> float:
	return root.get_node("VillagerDay").call("time_at", hour) if root.has_node("VillagerDay") \
			else load("res://scripts/villager_day.gd").time_at(hour)


func _hours(t: float) -> float:
	return load("res://scripts/villager_day.gd").hours(t)


func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		_fails += 1


func _finish() -> void:
	print("test_home: %s" % ("PASS" if _fails == 0 else "FAIL (%d)" % _fails))
	quit(1 if _fails else 0)
