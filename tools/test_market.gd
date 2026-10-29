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


func _on_board(projects: Node, id: StringName) -> bool:
	return (projects.call("all") as Array).any(func(p: Dictionary) -> bool: return p["id"] == id)


func _check(ok: bool, what: String) -> void:
	if not ok:
		_fails += 1
	print(("ok   " if ok else "FAIL ") + what)
