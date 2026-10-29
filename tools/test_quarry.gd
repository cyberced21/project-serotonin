extends SceneTree
## Checks Greystone as a working quarry (plans/mine.md, phase 2) in a fresh Hearthvale: no ore
## walls left; copper, coal and iron rocks on its levels (no gold or crystal: those are the mine's);
## the dressing set out; the mine mouth on the floor, boarded until the shoring project is done.
##   godot --headless --path . -s res://tools/test_quarry.gd -- --save-root=user://tmp
## (No game class names: an -s script compiles before the autoloads exist.)

const CENTER := Vector2(-175, -15)

var _fails := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.get_node("Worlds").call("play_fresh")
	while get_first_node_in_group("player") == null:
		await process_frame
	for i in 30:
		await physics_frame
	var quarry: Node = root.find_child("Quarry", true, false)
	_check(quarry != null, "Greystone is in the world")
	var walls := 0
	for n in root.find_children("*", "", true, false):
		var s: Script = n.get_script()
		if s and (s.resource_path.ends_with("ore_wall.gd") or s.resource_path.ends_with("ore_wall_placer.gd")):
			walls += 1
	_check(walls == 0, "no ore walls in the quarry (%d)" % walls)

	var by_item := {}
	var by_level := {}
	for n in get_nodes_in_group("gatherable"):
		var p := (n as Node3D).global_position
		var d := Vector2(p.x, p.z).distance_to(CENTER)
		if d > 66.0:
			continue
		var item := String(n.get("item"))
		by_item[item] = by_item.get(item, 0) + 1
		var level := int(round((26.0 - p.y) / 5.0))
		by_level[level] = by_level.get(level, 0) + 1
	print("rocks by ore: ", by_item, "  by level (0 = rim): ", by_level)
	_check(by_item.get("ore", 0) >= 8, "copper rocks up top (%d)" % by_item.get("ore", 0))
	_check(by_item.get("coal", 0) >= 5 and by_item.get("iron", 0) >= 5, "coal and iron lower down")
	_check(not by_item.has("gold") and not by_item.has("crystal"), "no gold or crystal in the quarry")
	_check(by_level.size() >= 5, "rocks on at least five of the six levels (%d)" % by_level.size())

	var dressing: Node = quarry.find_child("Dressing", false, false) if quarry else null
	var props := dressing.get_child_count() if dressing else 0
	_check(props >= 40, "the quarry's dressing is set out (%d pieces)" % props)

	var mouth := get_first_node_in_group("mine_mouth") as Node3D
	_check(mouth != null, "the mine mouth is on the quarry floor")
	if mouth:
		var p := mouth.global_position
		var d := Vector2(p.x, p.z).distance_to(CENTER)
		print("mouth at %.1f m from the middle, height %.1f" % [d, p.y])
		_check(d > 12.0 and d < 19.0 and p.y < 4.0, "it stands at the foot of the floor's wall")
		var boards := mouth.find_child("Boards", false, false) as Node3D
		_check(not mouth.get("is_open") and boards.visible, "boarded up to start with")
		root.get_node("Projects").call("set_done", &"mine_shoring", true)
		await process_frame
		_check(mouth.get("is_open") and not boards.visible, "open once the mine is shored up")
	_finish()


func _check(ok: bool, what: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + what)
	if not ok:
		_fails += 1


func _finish() -> void:
	print("%d failed" % _fails if _fails else "all passed")
	quit(1 if _fails else 0)
