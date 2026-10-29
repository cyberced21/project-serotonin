extends SceneTree
## Checks the villagers' day (scripts/villager_day.gd, plans/tavern.md), with every building at
## tier 3 and every decoration built. The timetable on its own first (with and without a tavern),
## then the village fast-forwarded through a day, checking where everyone is: in bed in the small
## hours, the early risers out at dawn, all at work at noon, on the benches (and the mayor on his
## round) at dusk, home again after dark.
##   godot --headless --path . -s res://tools/test_day.gd -- --save-root=user://tool_worlds
## (No game class names: an -s script compiles before the autoloads exist.)

const SPEED := 10.0

var _fails := 0
var _day: GDScript
var _dn: Node


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_day = load("res://scripts/villager_day.gd")
	_dn = root.get_node("DayNight")
	_timetable()
	root.get_node("Worlds").call("play_fresh")
	await process_frame
	while get_first_node_in_group("player") == null:
		await process_frame
	var player := get_first_node_in_group("player") as Node3D
	player.process_mode = Node.PROCESS_MODE_DISABLED
	player.global_position = Vector3(60, 30, 0)  # out of the way: nobody stops to chat
	var projects := root.get_node("Projects")
	for p in projects.call("all"):
		projects.call("set_done", p["id"], true)
	var village := root.get_node("Village")
	for b in get_nodes_in_group("building"):
		village.call("set_tier", b.get("def").get("id"), 3)
	village.call("set_tier", &"tavern", 1)  # the ruin, for the first day: no tavern to go to
	await _run_until(12.0)  # (the upgrades play out meanwhile)

	await _run_until(19.6, 18.0)
	_check(_lit() == _windowless(), "19:36: everyone's out, the windows are dark")
	await _run_until(21.5)
	_check(_all(func(v: Node) -> bool: return v.get("_inside")), "21:30, no tavern: everyone's home")
	_check(_lit() == _houses(), "...with the lamps lit (%d of %d)" % [_lit(), _houses()])
	await _run_until(22.4)
	var early := _lit()
	await _run_until(23.4)
	print("  windows lit: %d at 22:24, %d at 23:24" % [early, _lit()])
	_check(early > _lit() and early < _houses(), "going dark one by one")
	var windowless := []
	for b in get_nodes_in_group("building"):
		if (b.get("_windows") as Array).is_empty():
			windowless.append(b.get("def").get("id"))
	print("  (no windows: %s)" % [windowless])
	await _run_until(3.0)
	_check(_all(func(v: Node) -> bool: return v.get("_inside")), "03:00: everyone's in bed")
	_check(_lit() == _windowless(), "...all dark")
	await _run_until(6.0, 4.5)
	var ollie := _villager(&"fisher")
	var rosa := _villager(&"baker_cottage")
	var bram := _villager(&"woodcutter")
	_check(not ollie.get("_inside") and not rosa.get("_inside"), "06:00: Ollie and Rosa are up")
	_check(bram.get("_inside"), "...Bram isn't yet")
	await _run_until(7.4)
	var at_terrace := 0
	for v in _villagers():
		var seat: Node = v.get("_seat")
		if seat and seat.get_meta(&"kind") == &"terrace" and v.call("_seated"):
			at_terrace += 1
	var rosa_at: Node = rosa.get("_target")
	print("  07:24: %d at breakfast on the terrace; Rosa's at %s" % [at_terrace, rosa_at.name if rosa_at else "-"])
	_check(at_terrace >= 3, "07:24: breakfast on the terrace")
	_check(rosa_at != null and rosa_at.is_in_group("terrace_serve"), "...with Rosa serving")
	await _run_until(12.0, 11.0)
	_check(_all(func(v: Node) -> bool: return not v.get("_inside") and v.get("_seat") == null), "12:00: everyone's out, nobody sitting")
	await _run_until(19.8, 18.0)
	var seated := 0
	for v in _villagers():
		if v.call("_seated"):
			seated += 1
	var mayor := _villager(&"town_hall")
	print("  19:48: %d sitting; the mayor's going to %s" % [seated, mayor.get("_target").name])
	_check(seated >= 3, "19:48: three or more on the benches")
	_check(mayor.get("_target").name == "Stroll", "...and the mayor on his round of the square")
	await _run_until(21.5)
	_check(_all(func(v: Node) -> bool: return v.get("_inside")), "21:30: home again")
	await _tavern_night(village)
	_finish()


## The tavern restored (tier 3): an evening there.
func _tavern_night(village: Node) -> void:
	village.call("set_tier", &"tavern", 3)
	var tavern := get_first_node_in_group("tavern") as Node3D
	await _run_until(21.8, 18.0)
	_check(tavern.call("is_open"), "the tavern's open at 21:48")
	var there := 0
	var settled := 0
	for v in _villagers():
		if v.get_parent() == tavern:
			continue
		var local: Vector3 = tavern.global_transform.affine_inverse() * v.global_position
		if v.get("_part") == 4 and absf(local.x) < 4.0 and absf(local.z) < 3.5:  # Part.TAVERN, in the room
			there += 1
			if v.get("_seat") != null and v.get("_target") == v.get("_seat") and v.get("state") == 0:
				settled += 1
	var maud := tavern.get_node("Villager")
	print("  21:48: %d in the tavern, %d settled; Maud's at %s" % [there, settled, maud.get("_target").name])
	_check(there >= 4 and settled >= 4, "21:48: the village is at the tavern, sat down")
	_check(maud.get("_target").name == "Work2" and not maud.get("_inside"), "...Maud behind the bar")
	_check(tavern.call("windows_lit") > 0.5, "...the windows lit")
	await _run_until(0.7)
	var rosa := _villager(&"baker_cottage")
	var bram := _villager(&"woodcutter")
	print("  Rosa at 00:42: %s, part %d, state %d, going to %s" % [rosa.global_position.snapped(Vector3.ONE * 0.1), rosa.get("_part"), rosa.get("state"), rosa.get("_target").name])
	_check(rosa.get("_inside"), "00:42: Rosa's gone home")
	_check(bram.get("_part") == 4 and not bram.get("_inside"), "...Bram's still there")
	await _run_until(2.2)
	_check(not tavern.call("is_open"), "02:12: closed")
	_check(_all(func(v: Node) -> bool: return v.get("_inside")), "...everyone's home")
	_check(tavern.call("windows_lit") < 0.5, "...its windows dark")


## The timetable on its own.
func _timetable() -> void:
	var P = _day.Part
	_check(_day.call("part", &"woodcutter", 3.0, false) == P.SLEEP, "Bram at 03:00: asleep")
	_check(_day.call("part", &"fisher", 5.5, false) == P.WORK, "Ollie at 05:30: fishing at dawn")
	_check(_day.call("part", &"fisher", 7.2, false) == P.BREAKFAST, "...07:12: breakfast")
	_check(_day.call("part", &"baker_cottage", 7.0, false) == P.BREAKFAST, "Rosa at 07:00: breakfast")
	_check(_day.call("part", &"smithy", 12.0, false) == P.WORK, "Greta at noon: at work")
	_check(_day.call("part", &"smithy", 19.5, false) == P.DUSK, "...19:30: dusk")
	_check(_day.call("part", &"smithy", 21.0, false) == P.SLEEP, "...21:00, no tavern: home")
	_check(_day.call("part", &"smithy", 21.0, true) == P.TAVERN, "...21:00 with a tavern: there")
	_check(_day.call("part", &"smithy", 21.0, true, true) == P.SLEEP, "...unless she's skipping it")
	_check(_day.call("part", &"woodcutter", 0.6, true) == P.TAVERN, "Bram at 00:36: still at the tavern")
	_check(_day.call("part", &"baker_cottage", 0.0, true) == P.SLEEP, "Rosa at midnight: gone to bed")
	for h in [0.0, 3.0, 6.0, 12.5, 19.0, 20.0, 23.0]:
		var back: float = _day.call("hours", _day.call("time_at", h))
		if absf(back - h) > 0.001:
			_check(false, "clock round trip at %.1f gave %.3f" % [h, back])


## Fast-forwards the day to clock hour `h` (starting from `from` if given, else from now).
func _run_until(h: float, from := -1.0) -> void:
	if from >= 0.0:
		_dn.set("time", _day.call("time_at", from))
	Engine.time_scale = SPEED
	var target: float = _day.call("time_at", h)
	var guard := 0
	while absf(wrapf(float(_dn.get("time")) - target, -0.5, 0.5)) > 0.002 and guard < 20000:
		await physics_frame
		guard += 1
	Engine.time_scale = 1.0
	await physics_frame


## How many houses (not the tavern) have their windows lit.
func _lit() -> int:
	var n := 0
	for b in get_nodes_in_group("building"):
		if b.is_in_group("tavern"):
			continue
		if (b.get("_windows") as Array).is_empty():
			n += 1  # (no windows: counts as lit, so the count is always of all houses)
		elif b.call("windows_lit") > 0.5:
			n += 1
	return n


func _houses() -> int:
	return get_nodes_in_group("building").size() - get_nodes_in_group("tavern").size()


func _windowless() -> int:
	var n := 0
	for b in get_nodes_in_group("building"):
		if (b.get("_windows") as Array).is_empty() and not b.is_in_group("tavern"):
			n += 1
	return n


func _villagers() -> Array:
	var out := []
	for b in get_nodes_in_group("building"):
		var v := b.get_node_or_null("Villager")
		if v:
			out.append(v)
	return out


func _villager(id: StringName) -> Node:
	for b in get_nodes_in_group("building"):
		if b.get("def").get("id") == id:
			return b.get_node("Villager")
	return null


func _all(f: Callable) -> bool:
	var ok := true
	for v in _villagers():
		if not f.call(v):
			print("    not %s (%s, part %d, state %d)" % [v.call("display_name"), v.global_position.snapped(Vector3.ONE * 0.1), v.get("_part"), v.get("state")])
			ok = false
	return ok


func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		_fails += 1


func _finish() -> void:
	print("test_day: %s" % ("PASS" if _fails == 0 else "%d FAILED" % _fails))
	quit(1 if _fails else 0)
