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
	print("test_projects: %s" % ("PASS" if _fails == 0 else "%d FAILED" % _fails))
	quit(1 if _fails else 0)


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		_fails += 1
