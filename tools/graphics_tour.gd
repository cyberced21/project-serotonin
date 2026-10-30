extends SceneTree
## Graphics tour: teleports round fixed views of the main world, saves a screenshot of each and
## prints the average FPS there, so each phase of the graphics overhaul can be compared.
##
##   godot --path . --screen 1 --resolution 1280x720 -s res://tools/graphics_tour.gd -- --label=before
##
## Options (after `--`):
##   --label=NAME     sub-folder of docs/images/graphics/ to save into (default "latest")
##   --preset=NAME    low / medium / high: graphics preset to apply first (default: the saved one)
##   --only=a,b       only these views (by name)
##   --set=mood       the mood pass's views instead (plans/mood-pass.md): one spot at sunrise,
##                    noon, sunset and night, facing the low sun, mist on the water at dawn
##   --set=lamps      the lamps' views (plans/lamps.md): every road stretch lit and the lantern
##                    given, at dusk and night, a dark trail by lantern alone, the lantern raised
##   --set=projects   the village projects' views (plans/projects.md): the square with none done
##                    and with all, at dusk, the noticeboard open, the footbridge over the creek
##   --set=world      the world revamp's views (plans/world.md): the creek, the valleys, the roads
##                    on the land, the quarry's slopes, the valley from the rim hills
##   --look=k=v,k=v   override SkyLook values for this run (numbers only), e.g. --look=water_mist=0.3
## The game is played on a throwaway save, so the real one is never touched.

const VIEWS := [
	# name, where to stand, where to look, time of day (0..1, 0.5 = noon, sunset 0.85)
	["clearing", Vector3(50, 0, 80), Vector3(46, 0, 50), 0.42],
	["pinewood", Vector3(140.5, 0, -80.5), Vector3(115, 0, -110.5), 0.38],
	["quarry", Vector3(-65, 0, 62), Vector3(-118, 0, 88), 0.45],
	["quarry_walls", Vector3(-118, 0, 125.5), Vector3(-132, 0, 134), 0.45],  # along level 2's ore wall
	["goldmeadow", Vector3(345.5, 0, 246), Vector3(381.5, 0, 286.5), 0.33],
	["stillwater", Vector3(38, 0, 360), Vector3(38, 0, 334), 0.55],
	["pond", Vector3(66, 0, 100), Vector3(66, 0, 84), 0.62],
	["hearthvale_dusk", Vector3(128, 0, 140), Vector3(141, 0, 128), 0.84],
	["clearing_night", Vector3(50, 0, 80), Vector3(46, 0, 50), 0.95],
	# looking into the low sun through the trees (Vector3.INF: face the sun)
	["pinewood_dawn", Vector3(103, 0, -104.5), Vector3.INF, 0.2],
]

const MOOD_VIEWS := [
	["clearing_sunrise", Vector3(50, 0, 80), Vector3(46, 0, 50), 0.16],
	["clearing_noon", Vector3(50, 0, 80), Vector3(46, 0, 50), 0.5],
	["clearing_sunset", Vector3(50, 0, 80), Vector3(46, 0, 50), 0.84],
	["clearing_night", Vector3(50, 0, 80), Vector3(46, 0, 50), 0.0],
	["sunrise_facing_sun", Vector3(50, 0, 80), Vector3.INF, 0.17],
	["sunset_facing_sun", Vector3(50, 0, 80), Vector3.INF, 0.83],
	["afternoon_facing_sun", Vector3(50, 0, 80), Vector3.INF, 0.65],
	["pond_dawn_mist", Vector3(66, 0, 100), Vector3(66, 0, 84), 0.19],
	["stillwater_dawn_mist", Vector3(38, 0, 360), Vector3(38, 0, 334), 0.2],
	["stillwater_noon", Vector3(38, 0, 360), Vector3(38, 0, 334), 0.5],
	["pinewood_noon", Vector3(140.5, 0, -80.5), Vector3(115, 0, -110.5), 0.45],
	["goldmeadow_noon", Vector3(345.5, 0, 246), Vector3(381.5, 0, 286.5), 0.5],
	["hearthvale_sunset", Vector3(128, 0, 140), Vector3(141, 0, 128), 0.85],
	["hearthvale_night", Vector3(128, 0, 140), Vector3(141, 0, 128), 0.02],
]

const LAMP_VIEWS := [
	["village_path_dusk", Vector3(98, 0, 82), Vector3(126, 0, 104), 0.872],
	["village_path_night", Vector3(98, 0, 82), Vector3(126, 0, 104), 0.0],
	["village_path_back", Vector3(114, 0, 124), Vector3(70, 0, 94), 0.0],
	["hearthvale_night", Vector3(128, 0, 140), Vector3(141, 0, 128), 0.02],
	["ring_road_night", Vector3(209, 0, 146), Vector3(188, 0, 170), 0.0],
	["lake_path_night", Vector3(42, 0, 92), Vector3(35, 0, 118), 0.95],
	["trail_by_lantern", Vector3(46, 0, 34), Vector3(44, 0, 18), 0.0],
	["lantern_raised", Vector3(46, 0, 34), Vector3(44, 0, 18), 0.0, "raise"],
	["clearing_night", Vector3(50, 0, 80), Vector3(46, 0, 50), 0.95],
]

## [name, stand, look, time, projects: "none" / "all", "board" to open the noticeboard]
const PROJECT_VIEWS := [
	["square_before", Vector3(128, 0, 141), Vector3(128, 0, 126), 0.4, "none"],
	["square_after", Vector3(128, 0, 141), Vector3(128, 0, 126), 0.4, "all"],
	["square_after_west", Vector3(114, 0, 120), Vector3(132, 0, 132), 0.45, "all"],
	["square_dusk", Vector3(128, 0, 141), Vector3(128, 0, 126), 0.865, "all"],
	["noticeboard", Vector3(135.2, 0, 122), Vector3(137, 0, 120), 0.4, "none", "board"],
	["footbridge", Vector3(68, 0, 79), Vector3(74, 0, 70), 0.42, "all"],
]

const WORLD_VIEWS := [
	["creek_spring", Vector3(151, 0, -47.5), Vector3(137.5, 0, -7), 0.4],
	["creek_clearing", Vector3(80, 0, 44), Vector3(72, 0, 76), 0.45],
	["creek_footbridge", Vector3(68, 0, 79), Vector3(74, 0, 70), 0.42],
	["creek_to_lake", Vector3(62, 0, 100), Vector3(46, 0, 126), 0.55],
	["valley_to_village", Vector3(76, 0, 72), Vector3(146, 0, 110), 0.4],
	["village_from_road", Vector3(178, 0, 48), Vector3(138, 0, 118), 0.6],
	["quarry_road", Vector3(15, 0, 300), Vector3(-61, 0, 274), 0.35],
	["quarry_slopes", Vector3(-41, 0, 294), Vector3(-106, 0, 254), 0.45],
	["lake_road", Vector3(-36, 0, 321), Vector3(24, 0, 338), 0.6],
	["goldmeadow_edge", Vector3(178, 0, 176), Vector3(208, 0, 238), 0.33],
	["pinewood_edge", Vector3(116, 0, 30), Vector3(86, 0, -30), 0.4],
	["from_the_rim", Vector3(388, 0, -179.5), Vector3(148, 0, 75.5), 0.38],
	["frostpeak", Vector3(24, 0, 56), Vector3(-46, 30, -22), 0.45],
	["frostpeak_shoulder", Vector3(-124, 0, -14), Vector3(-118, 38, -62), 0.4],
]
var views: Array = VIEWS
var lamps := false
var projects := false
var out_dir := "res://docs/images/graphics/latest"
var preset := ""
var only: PackedStringArray = PackedStringArray()


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--label="):
			out_dir = "res://docs/images/graphics/" + arg.trim_prefix("--label=")
		elif arg.begins_with("--preset="):
			preset = arg.trim_prefix("--preset=")
		elif arg.begins_with("--only="):
			only = arg.trim_prefix("--only=").split(",")
		elif arg.begins_with("--look="):
			for pair in arg.trim_prefix("--look=").split(","):
				var kv := pair.split("=")
				SkyLook.active().set(kv[0], float(kv[1]))
		elif arg == "--set=mood":
			views = MOOD_VIEWS
		elif arg == "--set=lamps":
			views = LAMP_VIEWS
			lamps = true
		elif arg == "--set=world":
			views = WORLD_VIEWS
		elif arg == "--set=projects":
			views = PROJECT_VIEWS
			projects = true
	_run.call_deferred()


func _run() -> void:
	# Not use_file(): that saves to the current (real) file first.
	root.get_node("SaveGame").set("path", "user://graphics_tour_save.json")
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://graphics_tour_save.json"))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)  # real frame rates
	Engine.max_fps = 0
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	change_scene_to_file("res://scenes/main.tscn")
	await _wait(2.0)
	var gfx := root.get_node_or_null("GraphicsSettings")
	if gfx:
		gfx.set("persist", false)  # never write the player's settings.cfg
	if gfx and preset != "":
		gfx.call("apply_preset", StringName(preset))
	var day_night := root.get_node("DayNight")
	day_night.set("frozen", true)  # each view at exactly its time
	var p := get_first_node_in_group("player") as Node3D
	if lamps:
		root.get_node("Lamps").call("light_all", true)
		root.get_node("Lamps").call("give_lantern")
	for v in views:
		if not only.is_empty() and not only.has(v[0]):
			continue
		day_night.set("time", v[3])
		if projects:
			for pr in root.get_node("Projects").call("all"):
				root.get_node("Projects").call("set_done", pr["id"], v[4] == "all")
			root.get_node("Village").call("set_tier", &"town_hall", 1)
			root.get_node("Inventory").call("add", &"wood", 12)  # a note or two payable
		if not projects and (v as Array).size() > 4 and v[4] == "raise":
			Input.action_press("raise_lantern")
		else:
			Input.action_release("raise_lantern")
		var look: Vector3 = v[2]
		if look == Vector3.INF:  # toward the sun, set for this time of day after a frame
			await process_frame
			var sun := get_first_node_in_group("sun") as Node3D
			if sun == null:
				sun = current_scene.find_child("Sun", true, false) as Node3D
			var back := sun.global_transform.basis.z
			look = v[1] + Vector3(back.x, 0.0, back.z).normalized() * 10.0
		_go(p, v[1], look)
		await _wait(0.5)
		_go(p, v[1], look)  # again, in case anything moved the player on arrival
		await _wait(2.5)  # past the biome's 1.5 s hold and its card
		if projects and (v as Array).size() > 5 and v[5] == "board":
			get_first_node_in_group("noticeboard").call("interact")
			await _wait(0.6)
		var fps := await _measure_fps(2.0)
		await _shot(v[0])
		var board_panel := get_first_node_in_group("noticeboard_panel")
		if board_panel:
			board_panel.call("close")
		print("VIEW %-16s %5.1f fps   at %s yaw %.2f" % [v[0], fps, p.global_position.snapped(Vector3.ONE * 0.1), p.rotation.y])
	quit()


func _wait(seconds: float) -> void:
	var end := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < end:
		await process_frame


func _measure_fps(seconds: float) -> float:
	var start := Time.get_ticks_usec()
	var frames := 0
	while Time.get_ticks_usec() - start < int(seconds * 1e6):
		await process_frame
		frames += 1
	return frames / ((Time.get_ticks_usec() - start) / 1e6)


func _go(p: Node3D, to: Vector3, look: Vector3) -> void:
	var q := PhysicsRayQueryParameters3D.create(to + Vector3.UP * 120.0, to + Vector3.DOWN * 120.0, 1)
	q.exclude = [(p as CollisionObject3D).get_rid()]
	var hit := p.get_world_3d().direct_space_state.intersect_ray(q)
	if hit:
		to = hit["position"] + Vector3.UP * 0.1
	p.call("teleport", to, look)


func _shot(name: String) -> void:
	# Text off (HUD, biome card, hints); the tool in hand (Viewmodel) stays.
	var hidden: Array[CanvasLayer] = []
	for layer in root.find_children("*", "CanvasLayer", true, false):
		if layer.name != "Viewmodel" and not layer.is_in_group("noticeboard_panel") and layer.visible:
			layer.visible = false
			hidden.append(layer)
	await process_frame
	await process_frame
	root.get_texture().get_image().save_png("%s/%s.png" % [out_dir, name])
	for layer in hidden:
		layer.visible = true
