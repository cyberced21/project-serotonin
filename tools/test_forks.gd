extends SceneTree
## Checks the add-on forks of the mine plan (plans/mine.md, phase 9) in a fresh Hearthvale: every
## building's second slot opens at its top tier; each new add-on has its pieces in the building's
## model and its effect read by Village.stat(); a few effects where they land (project costs, the
## trader's days, a seam's regrowth, the pasty).
##   godot --headless --path . -s res://tools/test_forks.gd -- --save-root=user://tmp
## (No game class names: an -s script compiles before the autoloads exist.)

const NEW := {
	&"woodcutter": [&"timberslide", &"birdfeeder"], &"fisher": [&"eeltraps", &"jettylantern"],
	&"smithy": [&"oresorter", &"toolrack"], &"baker_cottage": [&"piewindow", &"pasty"],
	&"home": [&"nook", &"hearth"], &"town_hall": [&"noticeroof", &"flagstones", &"clocktower", &"lamplighter"],
	&"prospector_cottage": [&"orecart", &"lamproom", &"assay", &"survey"],
}

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
	var projects := root.get_node("Projects")
	var base_cost: Dictionary = projects.call("get_project", &"mine_shoring")["cost"]
	for id: StringName in NEW:
		var building: Node = null
		for b in get_nodes_in_group("building"):
			if b.get("def") and b.get("def").id == id:
				building = b
		var def: Resource = building.get("def") if building else null
		_check(def != null, "%s is in the world" % id)
		if def == null:
			continue
		village.call("set_tier", id, def.tiers.size())
		await process_frame
		_check(village.call("slot_open", id, 2), "%s: slot 2 is open at its top tier" % id)
		for a: StringName in NEW[id]:
			var addon: Resource = def.call("get_addon", a)
			_check(addon != null and addon.effects.size() == 1, "%s has the %s" % [id, a])
			if addon == null:
				continue
			village.call("set_addon", id, a)
			await process_frame
			var stat: StringName = addon.effects[0].stat
			_check(is_equal_approx(village.call("stat", stat), addon.effects[0].value),
					"  built, %s = %s" % [stat, village.call("stat", stat)])
			var nodes: Dictionary = building.get("_addon_nodes")
			_check(nodes.has(a) and (nodes[a] as Node).get_child_count() > 0, "  and its pieces stand in the model")

	# where some of them land (the last of each fork built above is the one standing)
	village.call("set_addon", &"town_hall", &"noticeroof")
	village.call("set_addon", &"woodcutter", &"timberslide")
	await process_frame
	var cost: Dictionary = projects.call("get_project", &"mine_shoring")["cost"]
	print("the shoring: %s -> %s" % [base_cost, cost])
	_check(cost[&"wood"] < base_cost[&"wood"] and cost[&"ore"] < base_cost[&"ore"],
			"the notice-board lamp and the timber slide make the shoring cheaper")
	village.call("set_addon", &"baker_cottage", &"pasty")
	await process_frame
	var mine := get_first_node_in_group("mine")
	_check(mine.call("pasty_ready"), "a pasty in your pocket for the first dig face")
	mine.call("on_broke_through", 0, Vector2i(5, 3), Vector3.ZERO)
	_check(not mine.call("pasty_ready"), "eaten by the first face")
	root.get_node("DayNight").emit_signal("day_broke")
	await process_frame
	_check(mine.call("pasty_ready"), "another the next day")
	_finish()


func _check(ok: bool, what: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + what)
	if not ok:
		_fails += 1


func _finish() -> void:
	print("%d failed" % _fails if _fails else "all passed")
	quit(1 if _fails else 0)
