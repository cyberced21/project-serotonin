extends SceneTree
## Spear vs rod, measured (plans/fishing-parity.md P3): a bot fishes the same water for a few game
## minutes with each tool, at the same level and tier, and prints fish and XP per minute. Both
## play like a skilled player: the rod casts on the sweet spot, pulls a quarter second after the
## take and walks over to pick the fish up; the spear walks (crouched, through the real wading
## noise) into reach of the nearest fish it can take, aims at it and thrusts. Everything else is
## the real game: scattering, regrowth, dodges, sizes, Big and Huge counts. Each run starts from
## a fresh copy of the world.
##
##   godot --path . --screen 1 --resolution 1280x720 -s res://tools/fishing_bench.gd -- [--minutes=4] [--level=30] [--tier=3] [--tools=spear,rod] [--water=0,1] [--speed=3]
##
## `--water`: which waters (by size, biggest first; the list is printed). Windowed (the mouse has
## to be captured for the player to fish). A throwaway save; settings.cfg untouched.
## (Untyped on purpose: an -s script can't name the game's classes that use autoloads.)

const SAVE := "user://fishing_bench_save.json"
const FISH := ["perch", "trout", "pike", "char", "grayling", "salmon"]
# RodFishing.State / FishingLure.Bite / LandedFish.Phase, as ints
const WAITING := 3
const YANK := 5
const TAKE := 4
const FLY := 0
## Seconds from the take to the click: about a person's reaction.
const REACTION := 0.25

var minutes := 4.0
var level := 30
var tier := 3
var speed := 3.0
var tool_names: PackedStringArray = ["spear", "rod"]
var waters: PackedInt32Array = [0, 1]
var verbose := false
var player
var _clock := 0.0  # game seconds since the session started
var _timer: Node  # adds up game time (each physics step's delta)
var _clock0 := 0.0
var _end := 0.0
var _held := {}
var _results: PackedStringArray = []


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		var kv := arg.trim_prefix("--").split("=")
		if kv.size() != 2:
			continue
		match kv[0]:
			"minutes": minutes = kv[1].to_float()
			"level": level = kv[1].to_int()
			"tier": tier = kv[1].to_int()
			"speed": speed = kv[1].to_float()
			"verbose": verbose = kv[1] == "1"
			"tools": tool_names = kv[1].split(",")
			"water":
				waters = PackedInt32Array()
				for w in kv[1].split(","):
					waters.append(w.to_int())
	_run.call_deferred()


func _run() -> void:
	root.get_node("SaveGame").set("path", SAVE)  # (never save over the real file)
	for w in waters:
		for tool in tool_names:
			await _session(w, tool)
	print("\n=== fishing bench: level %d, tier %d, %.0f game minutes each ===" % [level, tier, minutes])
	for r in _results:
		print(r)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
	Engine.time_scale = 1.0
	quit()


## One tool on one water, from a fresh world.
func _session(water_index: int, tool: String) -> void:
	Engine.time_scale = 1.0
	change_scene_to_file("res://scenes/main.tscn")
	await _wait_real(3.0)
	var gfx := root.get_node_or_null("GraphicsSettings")
	if gfx:
		gfx.set("persist", false)
	player = get_first_node_in_group("player")
	var skills := root.get_node("Skills")
	skills.call("set_level", &"fishing", level)
	var tools := root.get_node("Tools")
	tools.call("set_tier", &"spear", tier)
	tools.call("set_tier", &"rod", tier)
	tools.set("fishing_style", StringName(tool))
	root.get_node("DayNight").set("time", 0.4)
	var list := _waters()
	if water_index >= list.size():
		_results.append("water %d: none" % water_index)
		return
	var water = list[water_index]
	if tool == tool_names[0]:
		var kinds := {}
		for s in _schools(water):
			kinds[String(s.species.id)] = kinds.get(String(s.species.id), 0) + s.fish.size()
		print("water %d: %s" % [water_index, kinds])
	var xp0: int = skills.get("xp").get(&"fishing", 0)
	var fish0 := _fish_count()
	_timer = Node.new()
	var counter := GDScript.new()
	counter.source_code = "extends Node
var t := 0.0
func _physics_process(d: float) -> void:
	t += d
"
	counter.reload()
	_timer.set_script(counter)
	_timer.process_mode = Node.PROCESS_MODE_ALWAYS
	current_scene.add_child(_timer)
	await physics_frame
	_clock0 = _timer.get("t")
	_clock = 0.0
	_end = minutes * 60.0
	var tries := 0
	await _stand_on_shore(water, _schools(water)[0] if not _schools(water).is_empty() else null, false)
	while _clock < _end:
		tries += 1
		if tool == "rod":
			await _rod_try(water)
		else:
			await _spear_try(water)
	_release_all()
	var xp: int = skills.get("xp").get(&"fishing", 0) - xp0
	var fish := _fish_count() - fish0
	var line := "water %d  %-5s  %3d fish  %5d XP  in %.1f min (%d tries)  ->  %.1f fish/min, %.0f XP/min" % [
		water_index, tool, fish, xp, _clock / 60.0, tries, fish / (_clock / 60.0), xp / (_clock / 60.0)]
	print(line)
	_results.append(line)


# --- the rod ------------------------------------------------------------------------------------

func _rod_try(water) -> void:
	var rod = player.get_node("RodFishing")
	var school = _nearest_school(water, "rod")
	if school == null:
		await _wait_game(2.0)
		return
	await _stand_on_shore(water, school, true)
	# cast a little short of the school (right on top of it spooks it)
	var c: Vector3 = _center(school)
	var me: Vector3 = player.global_position
	var to := Vector3(c.x - me.x, 0, c.z - me.z)
	var aim := c - to.normalized() * 1.5 if to.length() > 3.5 else c
	_look_at(Vector3(aim.x, water.surface_height, aim.z))
	await _wait_game(0.2)
	if not rod.call("can_cast"):
		_why("rod: can't cast at %s from %s (state %d)" % [aim, player.global_position, rod.get("state")])
		await _wait_game(1.0)
		return
	_press("gather")
	var sweet: float = rod.get("back_time") + rod.get("forward_time") * rod.get("sweet_spot")
	for k in 30:  # the back-cast starts on the player's next physics frame
		if rod.get("state") == 1:
			break
		await _step()
	while rod.get("state") == 1 and rod.get("_t") < sweet - 1.5 / 60.0:
		await _step()
	_release("gather")
	await _wait_game(1.2)
	if rod.get("state") != WAITING:
		_why("rod: not floating after the cast (state %d)" % rod.get("state"))
		return
	var lure = rod.get("lure")
	var waited := 0.0
	while waited < 30.0 and is_instance_valid(lure) and rod.get("state") == WAITING:
		if lure.get("bite") == TAKE:
			await _wait_game(REACTION)
			await _tap("gather")
			break
		var c0 := _clock
		await _step()
		waited += _clock - c0
	await _wait_game(0.15)
	if rod.get("state") == YANK:
		var caught = rod.get("caught")
		while is_instance_valid(caught) and caught.get("phase") == FLY:
			await _step()
		if is_instance_valid(caught):
			await _wait_game(0.5)
			await _walk_to(caught.global_position, 1.2, false)
			var t := 0.0
			while is_instance_valid(caught) and t < 3.0:
				var c0 := _clock
				await _step()
				t += _clock - c0
	elif rod.get("state") == WAITING:  # nothing took it: reel in
		await _tap("gather")
	while rod.get("state") != 0:
		await _step()


## On the bank nearest `school`, within casting reach of it (the walk there is charged as game
## time at walking speed, if `charge`).
func _stand_on_shore(water, school, charge: bool) -> void:
	if school == null:
		return
	var c: Vector3 = _center(school)
	var best := Vector3.INF
	for k in 16:
		var dir := Vector3(sin(k * TAU / 16.0), 0, cos(k * TAU / 16.0))
		for step in 120:
			var p := c + dir * (step * 0.25)
			if water.call("depth_here", p) <= 0.0:
				var at := p + dir * 0.8
				if best == Vector3.INF or _flat(at, player.global_position) < _flat(best, player.global_position):
					if _flat(at, c) < 11.0:
						best = at
				break
	if best == Vector3.INF:
		return
	var q := PhysicsRayQueryParameters3D.create(best + Vector3.UP * 30.0, best + Vector3.DOWN * 30.0, 1)
	q.exclude = [player.get_rid()]
	var hit: Dictionary = player.get_world_3d().direct_space_state.intersect_ray(q)
	if hit:
		best = hit["position"] + Vector3.UP * 0.1
	if charge and _flat(best, player.global_position) > 1.5:
		_clock += _flat(best, player.global_position) / player.get("walk_speed")
	if _flat(best, player.global_position) > 0.5:
		player.call("teleport", best, c)
		await _wait_game(0.3)


# --- the spear ----------------------------------------------------------------------------------

func _spear_try(water) -> void:
	var spear = player.get("spearfishing")
	var f = _nearest_fish(water)
	if f == null:
		await _wait_game(2.0)
		return
	# wade over, crouched, until it's in reach
	if not await _walk_to(f.global_position, 1.7, true, f):
		_why("spear: couldn't wade to the %s (at %.1f m)" % [f.species.id if is_instance_valid(f) else "?", _flat(f.global_position, player.global_position) if is_instance_valid(f) else -1.0])
		await _wait_game(0.5)
		return
	# aim at it and thrust (a skilled player tracks it through the wind-up)
	var t := 0.0
	while t < 2.5 and is_instance_valid(f):
		_look_at(f.global_position)
		if spear.get("fish_target") != null and not player.get("_swinging") and player.get("_cooldown") <= 0.0:
			_press("gather")
			await _step()
			await _step()
			_release("gather")
			while player.get("_swinging"):
				if is_instance_valid(f):
					_look_at(f.global_position)
				await _step()
			return
		var c0 := _clock
		await _step()
		t += _clock - c0
	_why("spear: no fish under the crosshair (water %s)" % spear.get("water"))


## The nearest fish your spear can take, by flat distance.
func _nearest_fish(water):
	var best = null
	for s in _schools(water):
		for f in s.fish:
			if f.lure != null or not f.call("tool_can_take", &"spear"):
				continue
			if best == null or _flat(f.global_position, player.global_position) < _flat(best.global_position, player.global_position):
				best = f
	return best


# --- moving and looking -------------------------------------------------------------------------

## Walks (really: held keys, the real speed and footsteps) until within `near` of `at` (or of
## `follow`, which moves). False if it couldn't get there in 20 s.
func _walk_to(at: Vector3, near: float, crouch: bool, follow = null) -> bool:
	if crouch:
		_set_held("crouch", true)
	var t := 0.0
	var ok := false
	while t < 20.0:
		if follow != null:
			if not is_instance_valid(follow):
				break
			at = follow.global_position
		if _flat(at, player.global_position) <= near:
			ok = true
			break
		var d: Vector3 = at - player.global_position
		player.rotation.y = atan2(-d.x, -d.z)
		_set_held("move_up", true)
		var c0 := _clock
		await _step()
		t += _clock - c0
	_set_held("move_up", false)
	_set_held("crouch", false)
	await _wait_game(0.1)
	return ok


func _look_at(p: Vector3) -> void:
	var eye: Vector3 = player.camera.global_position
	var d := p - eye
	player.rotation.y = atan2(-d.x, -d.z)
	player.set("_pitch", atan2(d.y, Vector2(d.x, d.z).length()))


# --- the world ----------------------------------------------------------------------------------

## Waters with fish in them, biggest first.
func _waters() -> Array:
	var out := []
	for w in get_nodes_in_group("water"):
		if not _schools(w).is_empty():
			out.append(w)
	out.sort_custom(func(a, b) -> bool:
		var sa: Vector3 = a.get_node("Volume").shape.size
		var sb: Vector3 = b.get_node("Volume").shape.size
		return sa.x * sa.z > sb.x * sb.z)
	return out


func _schools(water) -> Array:
	var out := []
	for s in get_nodes_in_group("fish_school"):
		if s.water == water:
			out.append(s)
	return out


## The nearest school with a fish `tool` can take.
func _nearest_school(water, tool: String):
	var best = null
	for s in _schools(water):
		if s.fish.is_empty() or not s.fish[0].call("tool_can_take", StringName(tool)):
			continue
		if best == null or _flat(_center(s), player.global_position) < _flat(_center(best), player.global_position):
			best = s
	return best


func _center(school) -> Vector3:
	var c := Vector3.ZERO
	for f in school.fish:
		c += f.global_position
	return c / maxf(school.fish.size(), 1)


func _fish_count() -> int:
	var n := 0
	for id in FISH:
		n += root.get_node("Inventory").call("count", StringName(id))
	return n


func _why(s: String) -> void:
	if verbose:
		print("  [%.0f s] %s" % [_clock, s])


func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


# --- time and input -----------------------------------------------------------------------------

## One physics frame (the game runs `speed` times faster; a hit-stop slows it). The clock is the
## game's own: the physics steps' deltas, added up.
func _step() -> void:
	if is_equal_approx(Engine.time_scale, 1.0):
		Engine.time_scale = speed
	await physics_frame
	if is_instance_valid(_timer):
		_clock += maxf(float(_timer.get("t")) - _clock0 - _clock, 0.0)


func _wait_game(seconds: float) -> void:
	var until := _clock + seconds
	while _clock < until:
		await _step()


func _wait_real(seconds: float) -> void:
	var end := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < end:
		await process_frame


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
	await _step()
	await _step()
	_release(action)


func _release_all() -> void:
	for a in _held.keys():
		Input.action_release(a)
	_held.clear()
