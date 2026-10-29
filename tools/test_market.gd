extends SceneTree
## Checks the road east (plans/market.md): the landslide's boulders break and stay broken through a
## save; the retaining wall comes up on the board only once they're all gone; built, the mud goes,
## the wall stands and the road is open. Fast: no walking, no waiting on the clock.
##   godot --headless --path . -s res://tools/test_market.gd -- --save-root=user://tool_worlds
## (No game class names: an -s script compiles before the autoloads exist.)

var _fails := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.get_node("Worlds").call("play_fresh")
	await process_frame
	while get_first_node_in_group("player") == null:
		await process_frame
	for i in 5:
		await process_frame
	await _slide()
	await _stall()
	await _trader()
	print("test_market: %s" % ("PASS" if _fails == 0 else "%d FAILED" % _fails))
	quit(1 if _fails else 0)


func _slide() -> void:
	var slide := get_first_node_in_group("landslide") as Node3D
	var projects := root.get_node("Projects")
	_check(slide != null, "the landslide is on the road east")
	if slide == null:
		return
	var boulders: Array = slide.get("boulders")
	print("slide at %s, %d boulders" % [slide.global_position.snapped(Vector3.ONE * 0.1), boulders.size()])
	_check(boulders.size() == 12 and not slide.call("cleared"), "a dozen boulders, not cleared")
	_check(not _on_board(projects, &"retaining_wall"), "the wall isn't on the board yet")
	var hit_info := load("res://scripts/hit_info.gd")
	for b in boulders:
		b.set("hits_left", 0)
		b.call("_break", hit_info.new(b.global_position + Vector3.UP, Vector3.UP, b, b.global_position + Vector3(2, 1, 0)))
	await process_frame
	_check(slide.call("cleared"), "all broken: cleared")
	_check(_on_board(projects, &"retaining_wall"), "...and the wall is on the board")
	# through a save and back
	var save := root.get_node("SaveGame")
	save.call("save")
	root.get_node("Worlds").call("play", "classic")
	await process_frame
	while get_first_node_in_group("player") == null or get_first_node_in_group("landslide") == null:
		await process_frame
	for i in 5:
		await process_frame
	slide = get_first_node_in_group("landslide") as Node3D
	_check(slide.call("cleared"), "reloaded: still cleared, nothing grew back")
	projects.call("set_done", &"retaining_wall", true)
	await process_frame
	var wall := slide.find_child("RetainingWall", true, false) as Node3D
	var mud := slide.find_child("Mud", true, false) as Node3D
	_check(wall != null and wall.visible and not mud.visible, "built: the wall stands, the mud is gone")
	_check(slide.call("open"), "the road east is open")


func _stall() -> void:
	var projects := root.get_node("Projects")
	var inv := root.get_node("Inventory")
	_check(_on_board(projects, &"market"), "the market stall is on the board")
	projects.call("set_done", &"market", true)
	await process_frame
	var stall := get_first_node_in_group("market_stall") as Node3D
	_check(stall != null and stall.find_child("Keeper", true, false) != null, "built: the stall stands, its keeper behind it")
	var market := load("res://scripts/market.gd")
	print("prices: 1 iron = %d ore, %d birch; 1 salmon = %d perch; trader in: %d ore" % [
			market.price(&"ore", &"iron"), market.price(&"birch", &"iron"), market.price(&"perch", &"salmon"),
			market.price(&"ore", &"iron", true)])
	_check(market.price(&"ore", &"iron") > market.price(&"ore", &"iron", true), "the trader's rates are kinder")
	_check(market.price(&"ore", &"iron") < market.price(&"wood", &"iron"), "swaps within a family are cheaper")
	inv.call("add", &"ore", 20)
	var iron_before: int = inv.call("count", &"iron")
	var ore_before: int = inv.call("count", &"ore")
	_check(market.trade(&"ore", &"iron"), "trading ore for iron works")
	_check(inv.call("count", &"iron") == iron_before + 1 and inv.call("count", &"ore") == ore_before - market.price(&"ore", &"iron"),
			"...one iron in, the price in ore out")
	_check(not market.trade(&"crystal", &"iron"), "you can't pay with what you don't have")
	stall.call("interact")
	var panel := get_first_node_in_group("market_panel")
	_check(panel != null and panel.call("is_open"), "E at the stall opens the market")
	if panel:
		panel.call("close")


## The trader: not before the road opens; the morning after, she drives in, parks, the rates are
## kinder, she has her specials, and she's gone by night; she skips the next day.
func _trader() -> void:
	var trader := get_first_node_in_group("trader") as Node3D
	var day_night := root.get_node("DayNight")
	var inv := root.get_node("Inventory")
	_check(trader != null, "the trader is in the world")
	day_night.set("frozen", true)
	# (the road was opened in _slide: she comes the morning after)
	day_night.set("time", 0.5)
	await process_frame
	_check(not trader.call("visiting"), "not on the day the road opens")
	day_night.emit_signal("day_broke")
	day_night.set("time", 0.27)
	await process_frame
	var cart := trader.find_child("Cart", false, false) as Node3D
	var p1 := cart.global_position
	day_night.set("time", 0.29)
	await process_frame
	var p2 := cart.global_position
	_check(cart.visible and p2.distance_to(p1) > 5.0, "the next morning her cart comes down the road (%.0f m in a moment)" % p2.distance_to(p1))
	day_night.set("time", 0.5)
	await process_frame
	var stall := get_first_node_in_group("market_stall") as Node3D
	var d := Vector2(cart.global_position.x - stall.global_position.x, cart.global_position.z - stall.global_position.z).length()
	_check(trader.call("is_in") and d < 12.0, "midday: parked by the stall (%.1f m)" % d)
	var specials: Array = trader.call("specials")
	_check(specials.size() == 3, "she has three specials (%s)" % [specials.map(func(s: Array) -> String: return s[2])])
	for s in specials:
		for item in s[4]:
			inv.call("add", item, int(s[4][item]))
		_check(trader.call("buy", s[0]), "bought: %s" % s[2])
	await process_frame
	var dog_ok: bool = root.get_node("Companion").get("collar") != &""
	var glass_ok: bool = root.get_node("Lamps").get("glass") != &"glass_amber" or specials.any(func(s: Array) -> bool: return s[0] == &"glass_amber")
	var deco_ok: bool = specials.any(func(s: Array) -> bool: return s[1] == &"decoration" and root.get_node("Projects").call("is_done", s[0]))
	_check(dog_ok and glass_ok and deco_ok, "each special takes effect (collar %s, glass %s, decoration %s)" % [dog_ok, glass_ok, deco_ok])
	_check((trader.call("specials") as Array).is_empty(), "...and they're gone from her cart")
	day_night.set("time", 0.95)
	await process_frame
	_check(not cart.visible and not trader.call("is_in"), "night: she's gone")
	day_night.emit_signal("day_broke")
	day_night.set("time", 0.5)
	await process_frame
	_check(not trader.call("visiting"), "she skips the next day")
	day_night.emit_signal("day_broke")
	await process_frame
	_check(trader.call("visiting"), "...and comes the day after")
	day_night.set("frozen", false)


func _on_board(projects: Node, id: StringName) -> bool:
	return (projects.call("all") as Array).any(func(p: Dictionary) -> bool: return p["id"] == id)


func _check(ok: bool, what: String) -> void:
	if not ok:
		_fails += 1
	print(("ok   " if ok else "FAIL ") + what)
