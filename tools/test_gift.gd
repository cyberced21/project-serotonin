extends SceneTree
## Checks the elder's lantern gift (scripts/lantern_gift.gd): near the square at golden hour the
## elder walks over and hands it to you; far away, it waits on the town hall step until you walk
## up to it. Runs the clock fast (Engine.time_scale).
##   godot --headless --path . -s res://tools/test_gift.gd -- --save-root=user://tool_worlds

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
	while get_first_node_in_group("player") == null:
		await process_frame
	await _frames(10)
	var lamps := root.get_node("Lamps")
	var day_night := root.get_node("DayNight")
	var player := get_first_node_in_group("player") as Node3D
	day_night.set("frozen", true)
	day_night.set("time", 0.5)
	await _frames(10)
	_check(not lamps.get("has_lantern") and get_first_node_in_group("hud") != null, "no lantern at noon")

	# 1. in the square: the elder walks over
	var elder := _elder()
	_check(elder != null, "the village has an elder")
	var hall := elder.get_parent() as Node3D
	var door := hall.call("spot", "Door") as Node3D
	var stand := door.global_position + door.global_basis.z * 9.0
	player.global_position = stand + Vector3.UP
	await _frames(20)
	var start := _flat(elder.global_position).distance_to(_flat(player.global_position))
	day_night.set("time", float(day_night.get("SUNSET")) - 0.04)
	Engine.time_scale = 3.0
	var waited := 0.0
	var held := false
	while not lamps.get("has_lantern") and waited < 60.0:
		await physics_frame
		waited += 1.0 / 60.0 * Engine.time_scale
		held = held or bool(elder.get("scripted"))
	Engine.time_scale = 1.0
	var end := _flat(elder.global_position).distance_to(_flat(player.global_position))
	print("the elder came from %.1f m to %.1f m in %.1f s" % [start, end, waited])
	_check(lamps.get("has_lantern"), "handed over at golden hour")
	_check(end < 3.5 and end < start, "the elder walked over to you")
	_check(held, "held it out first")
	await _frames(10)
	_check(not elder.get("scripted"), "the elder goes back to their evening")
	_check(get_first_node_in_group("hud").get("_banner").modulate.a > 0.0, "a banner says so")
	await _frames(240)

	# 2. far off (a fresh save): it waits on the step
	lamps.call("from_dict", {})
	day_night.set("time", 0.5)
	await _frames(10)
	player.global_position = Vector3(0, 2, 2)
	await _frames(10)
	day_night.set("time", float(day_night.get("SUNSET")) - 0.04)
	await _frames(30)
	var gift := current_scene.get_node_or_null("LanternGift")
	_check(gift != null and not lamps.get("has_lantern"), "far off, it's left for you")
	var on_step := gift.get("_held") as Node3D if gift else null
	_check(on_step != null and on_step.global_position.distance_to(door.global_position) < 2.5,
			"on the town hall step")
	await _frames(120)
	_check(not lamps.get("has_lantern"), "still waiting while you're away")
	if on_step:
		player.global_position = on_step.global_position + Vector3(0.6, 0.2, 0.6)
	await _frames(30)
	_check(lamps.get("has_lantern"), "walking up to it picks it up")
	day_night.set("frozen", false)
	print("test_gift: %s" % ("PASS" if _fails == 0 else "%d FAILED" % _fails))
	quit(1 if _fails else 0)


func _elder() -> Node3D:
	for b in get_nodes_in_group("building"):
		for c in b.get_children():
			if c.get("work") == 3:  # Villager.Work.ORATE
				return c
	return null


func _frames(n: int) -> void:
	for i in n:
		await process_frame


static func _flat(v: Vector3) -> Vector2:
	return Vector2(v.x, v.z)


func _check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		_fails += 1
