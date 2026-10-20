extends SceneTree
## Rod fishing, played end to end in the real main world by a bot: stands on the lake shore, casts
## (releasing on the sweet spot), waits for a real fish to take, strikes, answers every move of
## the fight, lands it on a flash, and saves screenshots along the way. Prints what happened.
##
##   godot --path . --screen 1 --resolution 1280x720 -s res://tools/fishing_playtest.gd [-- --casts=3 --level=30]
##
## `--procgen=SEED`: a generated world's river instead: casts upstream of grayling holding station
## (letting the float drift down to them) and into the salmon pools. That world's save is thrown
## away afterwards.
##
## Windowed (the mouse has to be captured for the player to fish). Played on a throwaway save and
## without touching settings.cfg. Screenshots: user://fishing_playtest/*.png.
## (Untyped on purpose: an -s script can't name the game's classes that use autoloads.)

const OUT := "user://fishing_playtest"
const SAVE := "user://fishing_playtest_save.json"
# RodFishing.State / FishingLure.Bite / FishFight.Move / FishFight.Phase, as ints
const WAITING := 3
const FIGHT := 5
const TAKE := 4
const PULL := 0
const RUN := 1
const HEADSHAKE := 2
const JUMP := 3
const TELEGRAPH := 1
const ACTIVE := 2
const LANDING := 3

var casts := 3
var level := 30
var procgen_seed := -1
var player
var rod
var _held := {}
var _shots := {}
var _log: PackedStringArray = []
var _throwaway: Array[String] = []


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--casts="):
			casts = arg.trim_prefix("--casts=").to_int()
		elif arg.begins_with("--level="):
			level = arg.trim_prefix("--level=").to_int()
		elif arg.begins_with("--procgen="):
			procgen_seed = arg.trim_prefix("--procgen=").to_int()
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
	if procgen_seed >= 0:
		var existed := FileAccess.file_exists("user://procgen_%d.json" % procgen_seed)
		load("res://scripts/procgen/procgen_world.gd").enter(self, procgen_seed)
		await _wait(1.0)
		var t := 0.0
		while t < 90.0:
			var p = get_first_node_in_group("player")
			if p and p.process_mode != Node.PROCESS_MODE_DISABLED:
				break
			await _wait(0.5)
			t += 0.5
		await _wait(1.0)
		if not existed:
			_throwaway.append("user://procgen_%d.json" % procgen_seed)
		root.get_node("Skills").call("set_level", &"fishing", level)
	player = get_first_node_in_group("player")
	rod = player.get_node("RodFishing")
	var lake = _lake()
	if lake == null and procgen_seed < 0:
		_say("no lake found")
		return _finish()
	var landed := 0
	for i in casts:
		_say("--- cast %d" % (i + 1))
		if procgen_seed >= 0:
			if not await _stand_by_river(i):
				continue
		else:
			await _stand_at(lake, i)
		if not rod.call("can_cast"):
			_say("can't cast from here (aim %s)" % rod.get("aim_point"))
			continue
		await _shot("aim")
		if await _cast():
			var result: String = await _bite_and_fight()
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
	root.get_node("SaveGame").set("path", SAVE)  # (a procgen world's file is thrown away below)
	for path in [SAVE] + _throwaway:
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


## Beside a river stretch, aiming a little upstream of a grayling (even casts) or into a salmon's
## pool (odd ones), far enough out that it's the rod's water, not the spear's.
func _stand_by_river(i: int) -> bool:
	var want := "salmon" if i % 2 == 1 else "grayling"
	var target = null
	for school in get_nodes_in_group("fish_school"):
		if String(school.species.id) == want and not school.fish.is_empty():
			target = school
			if randi() % 3 == 0:
				break
	if target == null:
		_say("no %s in this world" % want)
		return false
	var water = target.water
	var f = target.fish[0]
	var down: Vector3 = water.flow.normalized()
	var spot: Vector3 = f.global_position - down * (2.5 if want == "grayling" else 1.5)
	spot.y = water.surface_height
	var side := down.cross(Vector3.UP).normalized()
	var stand := spot
	for k in 80:  # out across the bank until it's dry, then a few metres more
		var p := spot + side * (k * 0.25)
		if _water_at(p) == null:
			stand = p + side * 3.0
			break
	var q := PhysicsRayQueryParameters3D.create(stand + Vector3.UP * 80.0, stand + Vector3.DOWN * 80.0, 1)
	q.exclude = [player.get_rid()]
	var hit: Dictionary = player.get_world_3d().direct_space_state.intersect_ray(q)
	if hit:
		stand = hit["position"] + Vector3.UP * 0.1
	player.call("teleport", stand, spot)
	await _wait(0.4)
	var eye: Vector3 = player.camera.global_position
	var flat := Vector2(spot.x - eye.x, spot.z - eye.z).length()
	player.set("_pitch", -atan2(eye.y - spot.y, flat))
	await _wait(0.3)
	_say("by the river: %s at %.1f m (flow %s)" % [want, flat, water.flow])
	return true


func _water_at(p: Vector3):
	for w in get_nodes_in_group("water"):
		if w.call("depth_here", p) > 0.0:
			return w
	return null


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


func _bite_and_fight() -> String:
	var lure = rod.get("lure")
	var waited := 0.0
	var seen := {}
	while waited < 45.0:
		await physics_frame
		waited += 1.0 / 60.0
		if not is_instance_valid(lure):
			return "float gone"
		var bite: int = lure.get("bite")
		if not seen.has(bite):
			seen[bite] = true
			_say("  bite state %d at %.1f s%s" % [bite, waited, (" (%s)" % lure.get("fish").species.id) if lure.get("fish") else ""])
		if bite == TAKE:
			await _wait(0.12)  # a human-ish reaction
			_tap("gather")
			break
	if rod.get("state") != WAITING and rod.get("state") != FIGHT:
		await _wait(0.1)
	await _wait(0.1)
	if rod.get("state") != FIGHT:
		_release_all()
		_tap("gather")  # reel in
		await _wait(0.6)
		return "no bite in time" if waited >= 45.0 else "missed the strike (state %d)" % rod.get("state")
	var fish = rod.get("fish")
	_say("  hooked a %s, %.1f m out" % [fish.species.id, rod.get("fight").distance])
	return await _fight()


## Answers the fight like test_fishing's bot: reel on pulls, let go otherwise, click each jerk, bow
## on the splash, grab on the flash.
func _fight() -> String:
	var fight = rod.get("fight")
	var last = fight
	var clicked_jerks := {}
	var bowed := false
	var shot_fight := false
	var t := 0.0
	while rod.get("state") == FIGHT and t < 120.0:
		await physics_frame
		t += 1.0 / 60.0
		fight = rod.get("fight")
		if fight == null:
			break
		last = fight
		var phase: int = fight.phase
		var move: int = fight.move
		if not shot_fight and t > 1.0:
			shot_fight = true
			await _shot("fight")
		if phase == LANDING:
			_set_held("gather", false)
			if rod.get("_flash"):
				_tap("gather")
				await _shot("landing")
			continue
		if move == PULL and phase == ACTIVE:
			_set_held("gather", true)
			bowed = false
			continue
		_set_held("gather", false)
		if move == HEADSHAKE and phase == ACTIVE:
			var jerks: Array = fight.get("_jerks")
			for j in jerks.size():
				if not clicked_jerks.has(j) and fight.get("_t") >= jerks[j] + 0.04:
					clicked_jerks[j] = true
					_tap("gather")
		elif move != HEADSHAKE:
			clicked_jerks.clear()
		if move == JUMP and phase == ACTIVE and not bowed:
			bowed = true
			_tap("bow")
			await _shot("jump")
	_release_all()
	var r: String = String(last.result) if last else "?"
	_say("  %s after %.1f s, %d of %d notches left, ended on move %d phase %d" % [r, t, last.notches, last.max_notches, last.move, last.phase])
	await _wait(0.3)
	return r if r != "" else "timeout"


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
