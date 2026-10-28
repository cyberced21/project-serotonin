extends SceneTree
## Rod fishing, played end to end in the real main world by a bot: stands on the lake shore, casts
## (releasing on the sweet spot), waits for a real fish to take, pulls a human-ish beat later,
## watches the fish fly out and land beside it, walks over to pick it up, and saves screenshots
## along the way. Prints what happened.
##
##   godot --path . --screen 1 --resolution 1280x720 -s res://tools/fishing_playtest.gd [-- --casts=3 --level=30]
##
## Windowed (the mouse has to be captured for the player to fish). Played on a throwaway save and
## without touching settings.cfg. Screenshots: user://fishing_playtest/*.png.
## (Untyped on purpose: an -s script can't name the game's classes that use autoloads.)

const OUT := "user://fishing_playtest"
const SAVE := "user://fishing_playtest_save.json"
# RodFishing.State / FishingLure.Bite, as ints
const WAITING := 3
const YANK := 5
const TAKE := 4
## Seconds from the take to the click: about a person's reaction.
const REACTION := 0.25

var casts := 3
var level := 30
## The rod's tier (Tools): 3 opens every fish; lower, and better fish tear the hook out.
var rod_tier := 3
var player
var rod
var _held := {}
var _shots := {}
var _log: PackedStringArray = []


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--casts="):
			casts = arg.trim_prefix("--casts=").to_int()
		elif arg.begins_with("--level="):
			level = arg.trim_prefix("--level=").to_int()
		elif arg.begins_with("--rod-tier="):
			rod_tier = arg.trim_prefix("--rod-tier=").to_int()
	_run.call_deferred()


func _run() -> void:
	root.get_node("SaveGame").set("path", SAVE)  # (never save over the real file)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	change_scene_to_file("res://scenes/main.tscn")
	await _wait(2.5)
	var gfx := root.get_node_or_null("GraphicsSettings")
	if gfx:
		gfx.set("persist", false)
	root.get_node("Skills").call("set_level", &"fishing", level)
	root.get_node("DayNight").set("time", 0.4)
	player = get_first_node_in_group("player")
	rod = player.get_node("RodFishing")
	root.get_node("Tools").set("fishing_style", &"rod")
	root.get_node("Tools").call("set_tier", &"rod", rod_tier)
	var lake = _lake()
	if lake == null:
		_say("no lake found")
		return _finish()
	var landed := 0
	for i in casts:
		_say("--- cast %d" % (i + 1))
		await _stand_at(lake, i)
		if not rod.call("can_cast"):
			_say("can't cast from here (aim %s, rod state %d)" % [rod.get("aim_point"), rod.get("state")])
			continue
		await _shot("aim")
		if await _cast():
			var result: String = await _bite_and_yank()
			_say("result: " + result)
			if result == "landed":
				landed += 1
		await _wait(1.0)
	var bag := []
	for id in ["perch", "trout", "pike", "char", "grayling", "salmon"]:
		var n: int = root.get_node("Inventory").call("count", StringName(id))
		if n > 0:
			bag.append("%s %d" % [id, n])
	_say("landed %d of %d; Fishing level %d; in the bag: %s" % [landed, casts,
		root.get_node("Skills").call("level", &"fishing"), ", ".join(bag)])
	_finish()


func _finish() -> void:
	for path in [SAVE]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	quit()


func _say(s: String) -> void:
	_log.append(s)
	print(s)


func _lake():
	var best = null
	var best_size := 0.0
	for w in get_nodes_in_group("water"):
		var box = w.get_node("Volume").shape.size
		if box.x * box.z > best_size:
			best_size = box.x * box.z
			best = w
	return best


## On the shore, facing the middle, aiming about 9 m out (a different side each cast).
func _stand_at(lake, i: int) -> void:
	var c: Vector3 = lake.global_position
	var dir := Vector3(sin(i * 2.1), 0, cos(i * 2.1))
	var shore := c
	for k in 200:
		var p := c + dir * (k * 0.25)
		if lake.call("depth_here", p) <= 0.0:
			shore = p
			break
	var at := shore + dir * 1.0
	var q := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 60.0, at + Vector3.DOWN * 60.0, 1)
	q.exclude = [player.get_rid()]
	var hit: Dictionary = player.get_world_3d().direct_space_state.intersect_ray(q)
	if hit:
		at = hit["position"] + Vector3.UP * 0.1
	player.call("teleport", at, c)
	await _wait(0.4)
	# pitch down so the crosshair meets the water ~9 m out
	var eye: Vector3 = player.camera.global_position
	var drop: float = eye.y - lake.surface_height
	player.set("_pitch", -atan2(drop, 9.0))
	await _wait(0.3)


func _cast() -> bool:
	_press("gather")
	var sweet: float = rod.get("back_time") + rod.get("forward_time") * rod.get("sweet_spot")
	await _wait(sweet * 0.45)
	await _shot("backcast")
	# release so the rod sees it on the frame nearest the sweet spot (it reads input a frame later)
	while rod.get("state") == 1 and rod.get("_t") < sweet - 1.5 / 60.0:
		await physics_frame
	_release("gather")
	await _wait(1.2)
	await _shot("float")
	var ok: bool = rod.get("state") == WAITING
	_say("cast: %s, verdict %s" % ["floating" if ok else "state %d" % rod.get("state"), rod.get("_verdict")])
	return ok


func _bite_and_yank() -> String:
	var lure = rod.get("lure")
	var waited := 0.0
	var seen := {}
	while waited < 45.0:
		await physics_frame
		waited += 1.0 / 60.0
		if not is_instance_valid(lure):
			return "float gone (rod state %d, on floor %s, vy %.1f)" % [rod.get("state"), player.is_on_floor(), player.velocity.y]
		var bite: int = lure.get("bite")
		if not seen.has(bite):
			seen[bite] = true
			_say("  bite state %d at %.1f s%s" % [bite, waited, (" (%s)" % lure.get("fish").species.id) if lure.get("fish") else ""])
		if bite == TAKE:
			await _wait(0.06)
			await _shot("take")
			await _wait(REACTION - 0.06)
			_tap("gather")
			break
	await _wait(0.1)
	if rod.get("state") != YANK:
		_release_all()
		_tap("gather")  # reel in
		await _wait(0.6)
		return "no bite in time" if waited >= 45.0 else "missed the pull (state %d)" % rod.get("state")
	var caught = rod.get("caught")
	var id: StringName = caught.get("item")
	var before: int = root.get_node("Inventory").call("count", id)
	_say("  yanked a %s out" % id)
	await _wait(0.25)
	await _shot("yank")
	var t := 0.0
	while is_instance_valid(caught) and caught.get("phase") == 0 and t < 3.0:  # LandedFish.Phase.FLY
		await physics_frame
		t += 1.0 / 60.0
	if not is_instance_valid(caught):
		return "the fish vanished in the air"
	var down: Vector3 = caught.global_position
	_say("  landed %.1f m away after %.2f s" % [_flat(down, player.global_position), t])
	await _wait(0.3)
	await _shot("landed")
	await _wait(1.2)
	await _shot("flopping")
	# walk up to it (the bot just steps next to it)
	var me: Vector3 = player.global_position
	player.global_position = me.lerp(down, 0.6)
	t = 0.0
	while is_instance_valid(caught) and t < 3.0:
		await physics_frame
		t += 1.0 / 60.0
	var after: int = root.get_node("Inventory").call("count", id)
	return "landed" if after == before + 1 else "not picked up (%d -> %d)" % [before, after]


func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


# --- input ---------------------------------------------------------------------------------

func _press(action: String) -> void:
	Input.action_press(action)
	_held[action] = true


func _release(action: String) -> void:
	Input.action_release(action)
	_held.erase(action)


func _set_held(action: String, on: bool) -> void:
	if on and not _held.has(action):
		_press(action)
	elif not on and _held.has(action):
		_release(action)


func _tap(action: String) -> void:
	_press(action)
	await physics_frame
	await physics_frame
	_release(action)


func _release_all() -> void:
	for a in _held.keys():
		Input.action_release(a)
	_held.clear()


func _wait(seconds: float) -> void:
	var end := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < end:
		await process_frame


func _shot(name: String) -> void:
	_shots[name] = _shots.get(name, 0) + 1
	await process_frame
	root.get_texture().get_image().save_png("%s/%s_%d.png" % [OUT, name, _shots[name]])
