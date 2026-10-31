extends SceneTree
## A villager drawing water while the world goes away under them (Save & Quit to Menu) used to
## keep that scripted walk running against nodes no longer in the world: an error every frame,
## then a crash on the freed well. This starts one, takes the well out of the world mid-walk and
## then frees it; then starts another and quits to the menu mid-walk. The run's output must show no
## errors from village_decor.gd (the shell checks: grep it for "village_decor.gd").
##   godot --headless --path . -s res://tools/test_quit_midway.gd -- --save-root=user://tmp
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
	var decor := get_first_node_in_group("village_decor")
	var villager := _a_villager()
	_check(decor != null and villager != null, "the village has its decor and a villager")
	if decor == null or villager == null:
		_finish()
		return

	# the well leaves the world mid-walk, then is freed while they'd be cranking
	var well := _stand_in_well(decor, villager, 1.5)
	decor.call("_draw_water", villager, well)  # (not awaited: it runs on as the game does)
	for i in 5:
		await process_frame
	well.get_parent().remove_child(well)
	for i in 90:
		await process_frame
	well.free()
	for i in 90:
		await process_frame
	_check(decor.get("_drawing") == null, "the walk to a vanished well ends")

	# quit to the menu mid-walk
	decor.call("_draw_water", villager, _stand_in_well(decor, villager, 6.0))
	for i in 20:
		await process_frame
	root.get_node("Worlds").call("leave")
	for i in 240:
		await process_frame
	_check(get_first_node_in_group("village_decor") == null, "the village is gone with the world")
	_finish()


## A fresh village hasn't built its well yet: a stand-in `away` metres from the villager.
func _stand_in_well(decor: Node, villager: Node3D, away: float) -> Node3D:
	var well := Marker3D.new()
	decor.add_child(well)
	well.global_position = villager.global_position + Vector3(away, 0, 0)
	return well


func _a_villager() -> Node3D:
	var script := load("res://scripts/villager.gd")
	for n in root.find_children("*", "Node3D", true, false):
		if n.get_script() == script:
			return n
	return null


func _check(ok: bool, what: String) -> void:
	if not ok:
		_fails += 1
		print("  FAIL: ", what)


func _finish() -> void:
	print("test_quit_midway: %s" % ("all passed" if _fails == 0 else "%d FAILED" % _fails))
	quit(1 if _fails > 0 else 0)
