extends SceneTree
## Checks the walk-in houses in the village (plans/home.md, phases 3 and 5), every building at
## tier 3: each house (not the tavern) has a room you can stand in and something to look at; at
## dusk the ones staying in walk home through their door and sit by the fire; at 03:00 everyone
## with a bed is lying in it behind a shut door; by mid-morning they're all out again.
##   godot --headless --path . -s res://tools/test_interiors.gd -- --save-root=user://tool_worlds
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
	root.get_node("Worlds").call("play_fresh")
	await process_frame
	while get_first_node_in_group("player") == null:
		await process_frame
	var player := get_first_node_in_group("player") as Node3D
	player.process_mode = Node.PROCESS_MODE_DISABLED
	player.global_position = Vector3(60, 30, 0)  # out of the way: nobody stops to chat
	var village := root.get_node("Village")
	for b in get_nodes_in_group("building"):
		village.call("set_tier", b.get("def").get("id"), 3)
	village.call("set_tier", &"tavern", 1)  # no tavern: everyone home at dark
	await _run_until(12.0)

	# every house: a room, something to look at
	for b in _houses():
		var name: String = b.get("def").get("display_name")
		var tier: int = b.get("tier_shown")
		var looks := 0
		for c in b.get_node("Tier%d" % tier).get_children():
			if c.has_method("prompt") and String(c.call("prompt")).begins_with("E  Look at"):
				looks += 1
		_check(looks > 0, "%s: something to look at (%d)" % [name, looks])
		var bed := b.call("bed") as Node3D
		_check(bed != null, "%s: a bed" % name)
		if bed:
			player.global_position = bed.global_position + Vector3.UP * 0.1
			_check(b.call("has_player"), "%s: standing by the bed is indoors" % name)
	player.global_position = Vector3(60, 30, 0)

	# the small hours: in bed, lying down, the door shut
	await _run_until(3.0, 19.5)
	for b in _houses():
		var v: Node = b.get_node_or_null("Villager")
		var bed := b.call("bed") as Node3D
		if v == null or bed == null:
			continue
		var who: String = v.call("display_name")
		var d := Vector2(v.global_position.x - bed.global_position.x, v.global_position.z - bed.global_position.z).length()
		var model := v.get("_model") as Node3D
		_check(d < 0.4 and model.visible and absf(model.rotation.x) > 1.0,
				"03:00: %s's asleep in bed, in sight (%.1f m from it, %s)" % [who, d, v.global_position.snapped(Vector3.ONE * 0.1)])
		_check(v.call("door_shut"), "...and the door's shut")
		if absf(bed.global_position.y - b.global_position.y) > 2.0:
			_check(absf(v.global_position.y - bed.global_position.y) < 0.3, "...upstairs, %s went up the stair" % who)

	# mid-morning: all out, standing up again
	await _run_until(10.0)
	for b in _houses():
		var v: Node = b.get_node_or_null("Villager")
		if v == null or b.call("bed") == null:
			continue
		var model := v.get("_model") as Node3D
		_check(not v.get("_inside") and absf(model.rotation.x) < 0.01,
				"10:00: %s's up and out" % v.call("display_name"))
	_finish()


func _houses() -> Array:
	var out := []
	for b in get_nodes_in_group("building"):
		if not b.is_in_group("tavern") and not b.is_in_group("home"):
			out.append(b)
	return out


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


func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		_fails += 1


func _finish() -> void:
	print("test_interiors: %s" % ("PASS" if _fails == 0 else "%d FAILED" % _fails))
	quit(1 if _fails else 0)
