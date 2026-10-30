extends SceneTree
## Checks trophies (plans/trophies.md, phases 1-2) in a fresh Hearthvale: records with labels,
## the rare rolls when nodes break, a Huge fish (and not a Big one), saving, old trophy-log items
## becoming records, the feather at the peak and the shell on the lake's shore (the shell gone by
## noon), and the dog's stick a few days after he's yours.
##   godot --headless --path . -s res://tools/test_trophies.gd -- --save-root=user://tool_worlds
## (No game class names: an -s script compiles before the autoloads exist.)

var _fails := 0
var T: GDScript


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	T = load("res://scripts/trophies.gd")
	root.get_node("Worlds").call("play_fresh")
	await process_frame
	while get_first_node_in_group("player") == null:
		await process_frame
	for i in 10:
		await physics_frame
	var player := get_first_node_in_group("player") as Node3D
	var home := get_first_node_in_group("home") as Node3D
	_check(T.get("carried").is_empty(), "a new world: no trophies yet")
	var map := get_first_node_in_group("map_data")
	for i in 900:  # (labels name the place from the map, built over the first frames)
		if map == null or map.get("is_built"):
			break
		await process_frame

	# a record with its label
	var r: Dictionary = T.call("found", &"log", Vector3(128, 0, 128))
	_check(String(T.call("label", r)).begins_with("Trophy log, ") and String(T.call("label", r)).contains("day "),
			"a trophy log, labelled: %s" % T.call("label", r))

	# the rolls when nodes break: about 1 in 150 trees
	var tree_node: Node = null
	for n in get_nodes_in_group("gatherable"):
		if n.get("skill") == &"woodcutting":
			tree_node = n
			break
	var before: int = T.get("carried").size()
	for i in 3000:
		T.call("roll", tree_node)
	var logs: int = T.get("carried").size() - before
	_check(logs >= 6 and logs <= 45, "3000 trees felled: %d trophy logs (about 20 expected)" % logs)
	T.get("carried").clear()

	# fish: Huge yes, Big no
	T.call("fish", &"perch", 2, Vector3(38, 0, 338))
	_check(T.get("carried").is_empty(), "a Big fish isn't a trophy")
	T.call("fish", &"pike", 3, Vector3(38, 0, 338))
	var fish: Dictionary = T.get("carried")[0] if not T.get("carried").is_empty() else {}
	_check(not fish.is_empty() and T.call("title", fish) == "Huge pike" and String(T.call("label", fish)).contains("Stillwater"),
			"a Huge pike from the lake: %s" % T.call("label", fish))

	# it saves with your home, and old trophy-log items become records
	var saved: Dictionary = home.call("to_dict")
	T.call("clear")
	home.call("from_dict", JSON.parse_string(JSON.stringify(saved)))
	_check(T.get("carried").size() == 1 and T.call("title", T.get("carried")[0]) == "Huge pike", "trophies save and load")
	var inv := root.get_node("Inventory")
	inv.call("add", &"trophy_log", 2)
	T.call("adopt_old_logs")
	_check(inv.call("count", &"trophy_log") == 0 and T.get("carried").size() == 3, "two old trophy logs became records")

	# the feather and the shell, out in the world
	home.set("_next_find", {"feather": 0, "shell": 0})
	home.call("_on_morning")
	await process_frame
	var finds: Dictionary = home.get("_finds")
	_check(finds.has("feather") and finds.has("shell"), "a feather at the peak and a shell on the shore")
	if finds.has("feather"):
		var p: Array = finds["feather"]
		_check(Vector2(p[0], p[2]).distance_to(Vector2(-98, -54)) < 35.0, "...the feather near the summit")
		var node: Node = home.get("_find_nodes")["feather"]
		var had: int = T.get("carried").size()
		node.call("interact")
		await process_frame
		_check(T.get("carried").size() == had + 1 and not home.get("_finds").has("feather"), "...you pick it up")
	if finds.has("shell"):
		var p: Array = finds["shell"]
		var depth: float = load("res://scripts/water_body.gd").depth_at(self, Vector3(p[0], p[1] + 0.05, p[2]))
		_check(depth <= 0.0 and Vector2(p[0], p[2]).distance_to(Vector2(38, 338)) < 90.0, "...the shell on dry ground by the lake")
		root.get_node("DayNight").set("time", load("res://scripts/villager_day.gd").time_at(13.0))
		for i in 3:
			await process_frame
		_check(not home.get("_finds").has("shell"), "...gone by the afternoon")

	# the dog's stick
	root.get_node("Companion").call("adopt", &"terrier", &"wheaten", "Biscuit")
	for i in 30:
		await physics_frame
	var dog := get_first_node_in_group("dog") as Node3D
	if dog:
		root.get_node("DayNight").set("time", load("res://scripts/villager_day.gd").time_at(10.0))
		await process_frame
		home.set("_day", int(home.get("_dog_day")) + 6)
		player.call("teleport", dog.global_position + Vector3(2, 0, 0))
		var had: int = T.get("carried").size()
		for i in 10:
			await physics_frame
		var got: bool = T.get("carried").size() == had + 1 and T.get("carried")[-1]["kind"] == "stick"
		_check(got, "a few days after he's yours, the dog brings you his stick")
	else:
		print("  (no dog appeared after adopting: the stick isn't checked)")
	_finish()


func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		_fails += 1


func _finish() -> void:
	print("test_trophies: %s" % ("PASS" if _fails == 0 else "%d FAILED" % _fails))
	quit(1 if _fails else 0)
