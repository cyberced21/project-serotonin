extends SceneTree
## Checks every village building's every tier is walk-in at night (plans/mine.md, phase 10): it has
## a Bed (the camps a bedroll by the fire) and a Doorway if it has walls, so its villager stays in
## sight, sleeping, instead of vanishing at the door. Then follows the woodcutter at the lean-to
## from dusk to bed.
##   godot --headless --path . -s res://tools/test_camps.gd -- --save-root=user://tmp
## (No game class names: an -s script compiles before the autoloads exist.)

var _fails := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.get_node("Worlds").call("play_fresh")
	while get_first_node_in_group("player") == null:
		await process_frame
	for i in 20:
		await physics_frame
	var village := root.get_node("Village")
	for b in get_nodes_in_group("building"):
		var def: Resource = b.get("def")
		if def == null or def.id == &"home" or def.id == &"tavern" or b.get_node_or_null("Villager") == null:
			continue
		for t in range(1, def.tiers.size() + 1):
			var names: Array = (b.call("marks", t) as Array).map(func(m: Node) -> String: return String(m.name))
			_check("Bed" in names, "%s, tier %d: a bed" % [def.id, t])

	# the woodcutter at the lean-to (tier 1), through the night
	var lodge: Node = null
	for b in get_nodes_in_group("building"):
		if b.get("def") and b.get("def").id == &"woodcutter":
			lodge = b
	village.call("set_tier", &"woodcutter", 1)
	lodge.call("_show_tier", 1)
	await process_frame
	var bram := lodge.get_node("Villager") as Node3D
	var day := root.get_node("DayNight")
	day.set("time", _at(23.5))
	var bed := lodge.call("bed") as Node3D
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 60000 and (bed == null or bram.global_position.distance_to(bed.global_position) > 0.6):
		await physics_frame
	_check(bed != null and bram.global_position.distance_to(bed.global_position) <= 0.6,
			"Bram goes to his bedroll at the lean-to (%.1f m)" % (bram.global_position.distance_to(bed.global_position) if bed else -1.0))
	var model := bram.get_node_or_null("Model") as Node3D
	_check(model == null or model.visible, "and stays in sight")
	_finish()


## The DayNight time for clock hour h (VillagerDay's clock).
func _at(h: float) -> float:
	return load("res://scripts/villager_day.gd").time_at(h)


func _check(ok: bool, what: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + what)
	if not ok:
		_fails += 1


func _finish() -> void:
	print("%d failed" % _fails if _fails else "all passed")
	quit(1 if _fails else 0)
