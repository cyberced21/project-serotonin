extends SceneTree
## Checks swimming (plans/water.md, phase 1) in the lake:
##   - the lake is deep in the middle and has a wadeable shelf round its shore
##   - walking in off the shore you wade the shelf, then swim once it drops away: floating with
##     your eye just above the water (not walking the bed), tools put away
##   - you swim across and walk out up the far shelf
##   - dropped in from above the middle you go under, then come back up to float
##   - crouch dives (the view under, sounds muffled, breath running down), let go and you drift up;
##     out of breath you float up and can't dive till it's back
##   godot --headless --path . -s res://tools/test_swim.gd -- --save-root=user://tool_worlds
## (No game class names: an -s script compiles before the autoloads exist.)

var _fails := 0


func _initialize() -> void:
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	if not ok:
		_fails += 1
		print("  FAIL " + what)


func _run() -> void:
	root.get_node("Worlds").call("play_fresh")
	await process_frame
	while get_first_node_in_group("player") == null:
		await process_frame
	for i in 5:
		await process_frame
	var water_script := load("res://scripts/water_body.gd")
	var layout_water := load("res://scripts/layout_water.gd")
	var player := get_first_node_in_group("player") as CharacterBody3D
	var lake: Dictionary = {}
	for p in layout_water.ponds():
		if p["id"] == "lake":
			lake = p
	_check(not lake.is_empty(), "the layout has the lake")
	if lake.is_empty():
		return _done()
	var c: Vector2 = lake["centre"]
	var body: Node = water_script.surface_at(self, Vector3(c.x, 0.0, c.y))
	_check(body != null, "the lake has its water")
	if body == null:
		return _done()
	var surface := float(body.get("surface_height"))
	var mid_depth: float = water_script.depth_at(self, Vector3(c.x, 0.0, c.y))
	print("lake: %.2f m deep in the middle" % mid_depth)
	_check(mid_depth > 4.0, "the lake is deep in the middle (%.2f m)" % mid_depth)

	# the shore to the east, and the shelf in from it
	var dir := Vector2(1, 0)
	var shore := c
	for step in range(4, 80):
		shore = c + dir * float(step)
		if water_script.depth_at(self, Vector3(shore.x, 0.0, shore.y)) <= 0.0:
			break
	var shelf_deep := 0.0
	for k in range(1, 4):
		var p := shore - dir * float(k)
		shelf_deep = maxf(shelf_deep, water_script.depth_at(self, Vector3(p.x, 0.0, p.y)))
	print("shore at (%.1f, %.1f); the first 3 m in: %.2f m deep at most" % [shore.x, shore.y, shelf_deep])
	_check(shelf_deep < 1.2, "a wadeable shelf round the shore (%.2f m)" % shelf_deep)

	var terrain := get_first_node_in_group("terrain")
	var start := shore + dir * 2.0
	var ground: float = terrain.get("data").call("get_height", Vector3(start.x, 0.0, start.y))
	player.call("teleport", Vector3(start.x, ground + 0.1, start.y), Vector3(c.x, ground + 1.6, c.y))
	for i in 10:
		await physics_frame

	# walk in: wading, then swimming
	Input.action_press("move_up")
	var waded := false
	var swam_at := -1.0
	for i in 60 * 20:
		await physics_frame
		var d: float = water_script.depth_at(self, player.global_position)
		if d > 0.3 and not player.get("swimming"):
			waded = true
		if player.get("swimming"):
			swam_at = surface - player.global_position.y  # (how deep your feet were: the bed's height is coarse on the drop)
			break
	_check(waded, "waded the shelf before swimming")
	_check(swam_at > 1.0, "swimming once it's deep (%.2f m)" % swam_at)
	for i in 60 * 3:  # out over the deep water
		await physics_frame
	var eye: float = (player.get_node("Head") as Node3D).global_position.y
	var feet := player.global_position.y
	var bed := surface - float(water_script.depth_at(self, player.global_position))
	print("floating: eye %.2f m above the water, feet %.2f m above the bed" % [eye - surface, feet - bed])
	_check(player.get("swimming"), "still swimming out over the lake")
	_check(absf(eye - surface - 0.14) < 0.2, "the eye rides just above the water (%.2f m)" % (eye - surface))
	# phase 3: the lake has waves, and you ride them (your eye keeps its height over the moving surface)
	var off := 0.0
	var lo := INF
	var hi := -INF
	for i in 60 * 3:
		await physics_frame
		var w: float = body.call("surface_y", player.global_position)
		lo = minf(lo, w)
		hi = maxf(hi, w)
		off = maxf(off, absf(player.global_position.y + 1.6 - w - 0.14))
	print("waves: the surface rose and fell %.2f m; the eye kept within %.3f m of its float height" % [hi - lo, off])
	_check(hi - lo > 0.08, "the lake has waves (%.2f m)" % (hi - lo))
	_check(off < 0.05, "you ride the waves (eye within %.3f m)" % off)
	_check(feet - bed > 1.0, "floating, not walking the bed (%.2f m up)" % (feet - bed))
	_check(player.get("_equipped") == &"", "tools put away while swimming")
	var speed := Vector2(player.velocity.x, player.velocity.z).length()
	_check(speed > 1.5 and speed < 3.0, "paddling at a calm pace (%.2f m/s)" % speed)

	# across and out the far side
	var out := false
	for i in 60 * 40:
		await physics_frame
		var d: float = water_script.depth_at(self, player.global_position)
		if not player.get("swimming") and player.global_position.x < c.x and d < 1.0:
			out = true
			break
	Input.action_release("move_up")
	_check(out, "swam across and walked out up the far shelf (at %.1f, %.1f)" % [player.global_position.x, player.global_position.z])

	# dropped in over the middle: under, then back up to float
	player.call("teleport", Vector3(c.x, surface + 3.0, c.y))
	var lowest := INF
	for i in 60 * 7:
		await physics_frame
		lowest = minf(lowest, player.global_position.y)
	var rest := surface - (1.6 - 0.14)
	print("dropped in: down to %.2f below floating, settled %.2f off it" % [rest - lowest, player.global_position.y - rest])
	_check(lowest < rest - 0.2, "a drop in goes under first")
	_check(absf(player.global_position.y - rest) < 0.1 and absf(player.velocity.y) < 0.2, "then floats, settled")
	await _dive(player, surface)
	_done()


## Phase 2: crouch dives, under you're muffled and your breath runs down, let go and you drift up;
## run out and you float up whatever you press, and can't dive again till it's back.
func _dive(player: CharacterBody3D, surface: float) -> void:
	var view: Node = player.get_node("Head/Camera3D/Underwater")
	Input.action_press("crouch")
	await _seconds(2.0)
	var eye := player.global_position.y + 1.6
	print("dived: eye %.2f m under, breath %.2f" % [surface - eye, player.get("breath")])
	_check(player.get("head_under") and surface - eye > 1.5, "crouch dives (eye %.2f m under)" % (surface - eye))
	_check(float(player.get("breath")) < 0.97, "breath runs down under water")
	_check(view.get("under") and view.get("visible"), "the view's under water")
	_check(_muffled(), "sounds are muffled under water")
	Input.action_release("crouch")
	var y := player.global_position.y
	await _seconds(1.5)
	_check(player.global_position.y > y + 0.2, "let go, you drift back up")
	Input.action_press("crouch")
	await _seconds(0.5)
	player.set("breath", 0.04)  # (as if you'd stayed down)
	var surfaced := -1.0
	for i in 60 * 8:
		await physics_frame
		if player.get("winded") and not player.get("head_under"):
			surfaced = i / 60.0
			break
	print("out of breath: back up in %.1f s" % surfaced)
	_check(surfaced > 0.0, "out of breath, you float up even holding crouch")
	await _seconds(1.0)
	_check(not player.get("head_under"), "...and can't dive again straight away")
	_check(not view.get("under") and not _muffled(), "back up: the view and the sound are clear again")
	await _seconds(3.5)
	_check(not player.get("winded"), "breath back after a few seconds")
	await _seconds(1.0)
	_check(player.get("head_under"), "...then crouch dives again")
	Input.action_release("crouch")


func _muffled() -> bool:
	var bus := AudioServer.get_bus_index(&"Effects")
	for k in AudioServer.get_bus_effect_count(bus):
		var e := AudioServer.get_bus_effect(bus, k)
		if e is AudioEffectLowPassFilter and e.resource_name == "Underwater":
			return AudioServer.is_bus_effect_enabled(bus, k) and (e as AudioEffectLowPassFilter).cutoff_hz < 2000.0
	return false


func _seconds(s: float) -> void:
	for i in int(s * 60.0):
		await physics_frame


func _done() -> void:
	print("test_swim: %s" % ("PASS" if _fails == 0 else "%d FAILED" % _fails))
	quit(1 if _fails else 0)
