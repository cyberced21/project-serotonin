extends SceneTree
## Checks the carter's cart (plans/road-travel.md):
##   - no stops till the cart shed's project is done, and that waits for a packed road
##   - done, there's a stop at the cart shed and at the end of a packed road you've reached (not one
##     you haven't), and the cart can take you from one to the other
##   - rung, it rolls up, you're on its seat, it carries you along the road (quick: well past your
##     jog) and puts you down by the stop at the other end, on the ground
##   - moving on the way hops you off there, on the ground, and the cart goes
##   godot --headless --path . -s res://tools/test_cart.gd -- --save-root=user://tool_worlds

var _fails := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var worlds := root.get_node("Worlds")
	worlds.call("_ensure_classic")
	worlds.call("reset", worlds.get("CLASSIC"))
	worlds.call("play", worlds.get("CLASSIC"))
	while get_first_node_in_group("player") == null or get_first_node_in_group("cart_line") == null:
		await process_frame
	await _frames(10)
	var roads := root.get_node("Roads")
	var projects := root.get_node("Projects")
	var line := get_first_node_in_group("cart_line")
	var player := get_first_node_in_group("player") as Node3D

	_check(projects.call("get_project", &"carter").is_empty(), "no cart shed project before a road's packed")
	roads.call("set_level", &"main_street", 1)
	_check(not projects.call("get_project", &"carter").is_empty(), "packed, the cart shed's on the board")
	_check(get_nodes_in_group("cart_stop").is_empty(), "...but no stops till it's done")
	roads.get("reached")[&"main_street:0"] = true  # (been to its west end)
	projects.call("set_done", &"carter", true)
	await _frames(5)
	var stops: Dictionary = line.get("stops")
	print("  stops: ", stops.keys())
	_check(stops.has(&"shed") and stops.has(&"main_street:0"), "stops at the cart shed and at the street's far end you've been to")
	_check(get_nodes_in_group("cart_stop").size() == stops.size(), "each one a signpost (%d)" % get_nodes_in_group("cart_stop").size())
	var to: Array = line.call("destinations", &"shed")
	_check(to.any(func(d: Dictionary) -> bool: return d["id"] == &"main_street:0"), "from the shed it can take you down the street (%s)" % [to])
	_check(String(stops[&"main_street:0"]["name"]).begins_with("Hearthvale"), "the street's far end is named for the village (%s)" % stops[&"main_street:0"]["name"])

	var shed: Vector2 = stops[&"shed"]["at"]
	var far: Vector2 = stops[&"main_street:0"]["at"]
	player.call("teleport", Vector3(shed.x, _ground(shed) + 0.5, shed.y) + Vector3(2, 0, 0))
	await _frames(10)
	line.call("call_cart", &"shed", &"main_street:0")
	_check(line.call("riding"), "rung: the cart comes")
	var seated := await _until(func() -> bool: return player.get("seat") != null, 900)
	_check(seated, "it rolls up and you're on its seat")
	var seen := {"fastest": 0.0}  # (a lambda can't set the locals it sees)
	var arrived := await _until(func() -> bool:
		seen["fastest"] = maxf(seen["fastest"], float(line.get("_speed")))  # (the cart's own pace)
		return player.get("seat") == null, 3600)
	var fastest: float = seen["fastest"]
	var at := Vector2(player.global_position.x, player.global_position.z)
	print("  fastest %.1f m/s, put down %.1f m from the stop" % [fastest, at.distance_to(far)])
	_check(arrived and at.distance_to(far) < 10.0, "it takes you to the street's end and puts you down")
	_check(fastest > 10.0, "quick: well past your jog (%.1f m/s)" % fastest)
	_check(absf(player.global_position.y - _ground(at)) < 1.5, "on the ground")
	await _until(func() -> bool: return not line.call("riding"), 900)
	_check(not line.call("riding"), "and the cart goes on its way")

	line.call("call_cart", &"main_street:0", &"shed")
	await _until(func() -> bool: return player.get("seat") != null, 900)
	var start := player.global_position
	await _until(func() -> bool: return player.global_position.distance_to(start) > 25.0, 1200)
	Input.action_press("move_up")
	await _frames(5)
	Input.action_release("move_up")
	_check(player.get("seat") == null, "moving hops you off on the way")
	var off := Vector2(player.global_position.x, player.global_position.z)
	_check(off.distance_to(Vector2(start.x, start.z)) > 20.0 and off.distance_to(shed) > 20.0, "...part way along")
	_check(absf(player.global_position.y - _ground(off)) < 1.5, "...on the ground")
	await _until(func() -> bool: return not line.call("riding"), 900)
	_check(not line.call("riding"), "and the cart goes without you")

	if _fails == 0:
		print("test_cart: all passed")
		quit(0)
	else:
		print("test_cart: %d FAILED" % _fails)
		quit(1)


func _ground(p: Vector2) -> float:
	var terrain := get_first_node_in_group("terrain") as Terrain3D
	return terrain.data.get_height(Vector3(p.x, 0, p.y))


## Frames till `done` is true (at most `limit`): whether it came true.
func _until(done: Callable, limit: int) -> bool:
	for i in limit:
		if done.call():
			return true
		await process_frame
	return false


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		_fails += 1
