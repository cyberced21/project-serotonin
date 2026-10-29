extends SceneTree
## Checks the tavern's dice (plans/tavern.md): the rules (scripts/dice_rules.gd) on their own; then,
## with the tavern restored, full games against Bram and Greta played fast (you play a style too)
## all reach a winner and land on the chalkboard; a real throw of the five dice settles in the
## tray and reads 1..6 each; the tally comes back from a save; and you can sit down at the table
## and stand up again.
##   godot --headless --path . -s res://tools/test_dice.gd -- --save-root=user://tool_worlds
## (No game class names: an -s script compiles before the autoloads exist.)

var _fails := 0
var _rules: GDScript


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_rules = load("res://scripts/dice_rules.gd")
	_rules_check()
	root.get_node("Worlds").call("play_fresh")
	await process_frame
	while get_first_node_in_group("player") == null:
		await process_frame
	root.get_node("Village").call("set_tier", &"tavern", 3)
	var tavern := get_first_node_in_group("tavern") as Node3D
	Engine.time_scale = 4.0
	while tavern.get("tier_shown") != 3 or tavern.get("dice").get("_seat1") == null:
		await process_frame
	for i in 30:
		await process_frame
	Engine.time_scale = 1.0
	var dice: Node3D = tavern.get("dice")
	_check(dice.visible, "the dice table's set at tier 3")
	await _games(dice)
	await _real_throw(dice)
	_save(dice)
	await _sitting(dice)
	_finish()


func _rules_check() -> void:
	var cases := [
		[[1, 1, 1, 5, 2], 1050, 4],
		[[2, 3, 4, 6, 6], 0, 0],
		[[5, 5, 5, 1, 3], 600, 4],
		[[1, 1, 1, 1, 1], 1200, 5],
		[[2, 2, 2, 2, 3], 200, 3],
		[[6, 6, 6, 5, 5], 700, 5],
		[[3, 4], 0, 0],
		[[5], 50, 1],
	]
	var bad := 0
	for c in cases:
		var roll: Array[int] = []
		roll.assign(c[0])
		var s: Dictionary = _rules.call("score", roll)
		if s["points"] != c[1] or (s["keep"] as Array).size() != c[2]:
			print("  %s scored %d keeping %s (want %d, %d dice)" % [c[0], s["points"], s["keep"], c[1], c[2]])
			bad += 1
	_check(bad == 0, "scoring: %d rolls" % cases.size())
	var safe: Dictionary = _rules.call("style_of", &"woodcutter")
	var bold: Dictionary = _rules.call("style_of", &"smithy")
	_check(not _rules.call("wants_roll", safe, 350, 2, 0, 0), "Bram stops at 350 with two dice")
	_check(_rules.call("wants_roll", bold, 350, 2, 0, 0), "Greta rolls on")
	_check(_rules.call("wants_roll", safe, 350, 5, 0, 0), "...anyone rolls five fresh dice")
	_check(not _rules.call("wants_roll", bold, 300, 4, 1800, 0), "...nobody rolls past the winning line")
	_check(_rules.call("wants_roll", safe, 400, 1, 0, 1800), "...or holds back when the other's about to win")


func _games(dice: Node3D) -> void:
	dice.set("fast", true)
	dice.set("you_play", _rules.call("style_of", &""))
	var seat2: Marker3D = dice.get("_seat2")
	var played := {}
	for id in [&"woodcutter", &"smithy"]:
		var v := _villager(id)
		v.set("_seat", seat2)  # (sat across the table: no walking over in a fast game)
		for g in 10:
			dice.call("start", v)
			var s: Array = dice.get("scores")
			if not (s[0] >= 2000 or s[1] >= 2000) or dice.get("playing"):
				print("  a game against %s didn't finish: %s" % [id, s])
				_check(false, "games finish")
				return
		var t: Array = dice.call("tally", id)
		played[id] = t
		v.set("_seat", null)
	print("  tallies (you - them): Bram %s, Greta %s" % [played[&"woodcutter"], played[&"smithy"]])
	_check(played[&"woodcutter"][0] + played[&"woodcutter"][1] == 10 and played[&"smithy"][0] + played[&"smithy"][1] == 10,
		"20 fast games, each won by someone and chalked up")
	var board: Label3D = dice.get("_board")
	_check(board != null and board.text.contains("Bram") and board.text.contains("Greta"), "the chalkboard lists them")
	dice.call("leave")


func _real_throw(dice: Node3D) -> void:
	dice.set("fast", false)
	var v := _villager(&"woodcutter")
	dice.set("opponent", v)
	var started := Time.get_ticks_msec()
	var roll: Array = await dice.call("_throw", 1)
	var secs := (Time.get_ticks_msec() - started) / 1000.0
	var inside := true
	for d in dice.get("_dice"):
		var p: Vector3 = (d as Node3D).position
		if absf(p.x) > 0.31 or absf(p.z) > 0.31 or p.y < 0.0 or p.y > 0.16:  # (0.16: one may rest on another)
			inside = false
			print("  a die ended up at %s" % p.snapped(Vector3.ONE * 0.01))
	print("  thrown: %s in %.1f s" % [roll, secs])
	_check(roll.size() == 5 and roll.all(func(f: int) -> bool: return f >= 1 and f <= 6), "a real throw reads five faces")
	_check(inside, "...all in the tray")
	_check(secs < 7.5, "...and settled in good time")
	dice.set("opponent", null)
	dice.call("leave")


func _save(dice: Node3D) -> void:
	var before: Array = dice.call("tally", &"smithy")
	var d: Dictionary = dice.call("to_dict")
	dice.call("from_dict", {})
	dice.call("from_dict", JSON.parse_string(JSON.stringify(d)))
	_check(dice.call("tally", &"smithy") == before, "the tally comes back from a save")


func _sitting(dice: Node3D) -> void:
	var player := get_first_node_in_group("player") as Node3D
	var seat1: Marker3D = dice.get("_seat1")
	var stood := player.global_position
	player.call("sit", seat1)
	for i in 40:
		await physics_frame
	_check(player.get("seat") == seat1 and player.global_position.distance_to(seat1.global_position) < 0.05, "you sit down at the dice table")
	_check(seat1.get_meta(&"taken_by") == player, "...and nobody else can take the seat")
	_check(dice.call("is_open"), "...the dice panel opens")
	var missing := []
	for panel in get_nodes_in_group("modal_panel"):  # (every menu closes them when it opens)
		for m in ["is_open", "just_closed", "close"]:
			if not panel.has_method(m):
				missing.append("%s.%s" % [panel.name, m])
	_check(missing.is_empty(), "every modal panel can be closed by another menu %s" % [missing])
	var debug := root.get_node("DebugMenu")
	debug.call("open")
	_check(not dice.call("is_open"), "the debug menu (F1) opens over it and the dice panel closes")
	debug.call("close")
	player.call("stand")
	for i in 3:  # (process_frame comes before the nodes' _process)
		await process_frame
	_check(player.get("seat") == null and player.global_position.distance_to(stood) < 0.05, "you stand up where you were")
	_check(not dice.call("is_open"), "...and the panel's gone")


func _villager(id: StringName) -> Node:
	for b in get_nodes_in_group("building"):
		if b.get("def").get("id") == id:
			return b.get_node("Villager")
	return null


func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		_fails += 1


func _finish() -> void:
	print("test_dice: %s" % ("PASS" if _fails == 0 else "%d FAILED" % _fails))
	quit(1 if _fails else 0)
