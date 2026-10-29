extends SceneTree
## Checks add-ons (plans/home.md, phase 8) in a fresh Hearthvale: a slot opens with its tier; you
## build one of its two add-ons (its pieces show, its effect counts in Village.stat), swap to the
## other (the first comes down, the effects follow), and it saves; the upgrade panel's Add-ons
## tab offers them; your home's garden leaves a harvest in the morning and its porch swing makes
## the day go by faster while you sit on it.
##   godot --headless --path . -s res://tools/test_addons.gd -- --save-root=user://tool_worlds
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
	var village := root.get_node("Village")
	var inv := root.get_node("Inventory")
	var lodge: Node3D = null
	for b in get_nodes_in_group("building"):
		if b.get("def").get("id") == &"woodcutter":
			lodge = b
	_check(not village.call("slot_open", &"woodcutter", 1), "the lean-to has no add-on slot yet")
	village.call("set_tier", &"woodcutter", 2)
	for i in 200:
		await physics_frame
	_check(village.call("slot_open", &"woodcutter", 1), "the cabin opens slot 1")

	# build the drying rack
	for item in [&"wood", &"birch", &"ore"]:
		inv.call("add", item, 50)
	var logs_before: float = village.call("stat", &"extra_logs")
	_check(village.call("build_addon", &"woodcutter", &"dryingrack"), "you build the drying rack")
	await process_frame
	_check(lodge.get_node("Addon_dryingrack").visible and not lodge.get_node("Addon_whetbench").visible,
			"...it's there, the bench isn't")
	_check(is_equal_approx(village.call("stat", &"extra_logs"), logs_before + 1.0), "...and trees give a log more")

	# swap to the sharpening bench
	var hits_before: float = village.call("stat", &"double_hit_chance")
	_check(village.call("build_addon", &"woodcutter", &"whetbench"), "you swap to the sharpening bench")
	await process_frame
	_check(not lodge.get_node("Addon_dryingrack").visible and lodge.get_node("Addon_whetbench").visible,
			"...the rack comes down, the bench goes up")
	_check(is_equal_approx(village.call("stat", &"extra_logs"), logs_before)
			and is_equal_approx(village.call("stat", &"double_hit_chance"), hits_before + 0.05), "...and the effects follow")
	_check(not village.call("can_build_addon", &"woodcutter", &"whetbench"), "...it can't be built twice")

	# it saves
	var saved: Dictionary = village.call("to_dict")
	village.call("from_dict", JSON.parse_string(JSON.stringify(saved)))
	_check(village.call("addon", &"woodcutter", 1) == &"whetbench" and village.call("tier", &"woodcutter") == 2,
			"the add-on saves and loads (with the tiers)")

	# the panel's Add-ons tab
	var panel := get_first_node_in_group("upgrade_panel")
	lodge.get_node("Villager").call("interact")
	panel.call("_show_tab", 3)
	await process_frame
	var buttons := 0
	for c in (panel.get("_addons_box") as Node).find_children("*", "Button", true, false):
		buttons += 1
	# (headless, the mouse never frees, so the panel shuts itself the next frame: count its buttons)
	_check(buttons == 1, "the Add-ons tab offers the other one (%d button)" % buttons)
	panel.call("close")

	# your home: the garden's harvest, the porch swing
	var home := get_first_node_in_group("home") as Node3D
	village.call("set_tier", &"home", 4)
	for i in 240:
		await physics_frame
	village.call("set_addon", &"home", &"garden")
	await process_frame
	home.call("_on_morning")
	await process_frame
	var crate: Node = home.get("_harvest_node")
	_check(crate != null and String(crate.call("prompt")).contains("garden"), "the garden has something ready in the morning")
	if crate:
		var wheat: int = inv.call("count", &"wheat")
		crate.call("interact")
		await process_frame
		_check(inv.call("count", &"wheat") == wheat + 3, "...you pick it: wheat and barley")
	village.call("set_addon", &"home", &"swing")
	await process_frame
	var swing := home.call("addon_mark", "PorchSeatSwing") as Node3D
	_check(swing != null and swing.is_in_group("seat"), "the porch swing is a seat")
	if swing:
		player.call("sit", swing)
		for i in 5:
			await process_frame
		_check(is_equal_approx(root.get_node("DayNight").get("speed"), 4.0), "sitting on it, the day goes by faster")
		player.call("stand")
		for i in 5:
			await process_frame
		_check(is_equal_approx(root.get_node("DayNight").get("speed"), 1.0), "...and back to usual when you get up")
	_finish()


func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		_fails += 1


func _finish() -> void:
	print("test_addons: %s" % ("PASS" if _fails == 0 else "%d FAILED" % _fails))
	quit(1 if _fails else 0)
