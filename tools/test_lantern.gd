extends SceneTree
## Checks the lantern you carry (scripts/lantern.gd, the Lamps autoload's lantern state): none on
## a new world; given by day it waits dark, lights itself at dusk and goes out at dawn; put out by
## hand it stays out at the next dusk; it hangs low on the left; it saves.
##   godot --headless --path . -s res://tools/test_lantern.gd -- --save-root=user://tool_worlds

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
	await _frames(5)
	var lamps := root.get_node("Lamps")
	var day_night := root.get_node("DayNight")
	var player := get_first_node_in_group("player")
	var lantern := player.get("lantern") as Node3D
	var light := lantern.find_children("*", "OmniLight3D", true, false)[0] as OmniLight3D
	_check(not lamps.get("has_lantern") and not lantern.visible, "a new world has no lantern")
	day_night.set("time", 0.4)
	await _frames(3)
	lamps.call("give_lantern")
	await _frames(30)
	_check(lantern.visible and not lamps.get("lantern_lit") and not light.visible,
			"given by day, it hangs on the belt, dark")
	var cam := player.get("camera") as Camera3D
	var off := cam.global_transform.affine_inverse() * lantern.global_position
	print("hangs at %s from the eye" % off)
	_check(off.x < -0.1 and off.y < -0.15 and off.z < 0.0, "low on the left, in front of the eye")
	day_night.set("time", 0.86)
	await _frames(90)
	_check(lamps.get("lantern_lit") and light.visible and light.light_energy > 1.0,
			"lights itself at dusk (energy %.2f)" % light.light_energy)
	_check(light.shadow_enabled, "casts shadows")
	var saved: Dictionary = lamps.call("to_dict")
	_check(saved["lantern"]["has"] and saved["lantern"]["lit"], "saves that you have it, burning")
	day_night.set("time", 0.3)
	await _frames(120)
	_check(not lamps.get("lantern_lit") and not light.visible, "goes out at dawn")
	lamps.call("set_lantern_lit", true)
	await _frames(30)
	_check(light.visible, "lit by hand by day")
	day_night.set("time", 0.86)
	await _frames(10)
	lamps.call("set_lantern_lit", false)
	day_night.set("time", 0.3)
	await _frames(10)
	day_night.set("time", 0.86)
	await _frames(90)
	_check(not lamps.get("lantern_lit") and not light.visible, "put out by hand, it stays out at the next dusk")
	var swing: Vector2 = lantern.get("_swing")
	_check(is_finite(swing.x) and is_finite(swing.y) and swing.length() <= 0.56, "its swing stays in bounds (%s)" % swing)
	# walking: it swings, fast enough now and then to creak
	Input.action_press("move_up")
	var from: Vector3 = player.global_position
	var fastest := 0.0
	for i in 240:
		await process_frame
		var speed: float = (lantern.get("_swing_speed") as Vector2).length()
		fastest = maxf(fastest, speed)
		player.rotation.y += 0.004
	Input.action_release("move_up")
	print("walking %.1f m: fastest swing %.2f rad/s" % [player.global_position.distance_to(from), fastest])
	_check(fastest > float(lantern.get("CREAK_SPEED")) and fastest < 8.0, "walking swings it enough to creak, not wildly")
	lamps.call("from_dict", {})
	await _frames(3)
	_check(not lantern.visible, "a fresh save takes it back")
	print("test_lantern: %s" % ("PASS" if _fails == 0 else "%d FAILED" % _fails))
	quit(1 if _fails else 0)


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		_fails += 1
