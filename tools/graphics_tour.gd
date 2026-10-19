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
## The game is played on a throwaway save, so the real one is never touched.

const VIEWS := [
	# name, where to stand, where to look, time of day (0..1, 0.5 = noon, sunset 0.85)
	["clearing", Vector3(4, 0, 10), Vector3(0, 0, -20), 0.42],
	["pinewood", Vector3(35, 0, -104), Vector3(18, 0, -124), 0.38],
	["quarry", Vector3(-122, 0, -41), Vector3(-175, 0, -15), 0.45],
	["goldmeadow", Vector3(170, 0, 112), Vector3(194, 0, 139), 0.33],
	["stillwater", Vector3(-16, 0, 96), Vector3(-16, 0, 70), 0.55],
	["hearthvale_dusk", Vector3(100, 0, 52), Vector3(113, 0, 40), 0.84],
	["clearing_night", Vector3(4, 0, 10), Vector3(0, 0, -20), 0.95],
]

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
	_run.call_deferred()


func _run() -> void:
	# Not use_file(): that saves to the current (real) file first.
	root.get_node("SaveGame").set("path", "user://graphics_tour_save.json")
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)  # real frame rates
	Engine.max_fps = 0
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	change_scene_to_file("res://scenes/main.tscn")
	await _wait(2.0)
	var gfx := root.get_node_or_null("GraphicsSettings")
	if gfx and preset != "":
		gfx.call("apply_preset", StringName(preset))
	var day_night := root.get_node("DayNight")
	var p := get_first_node_in_group("player") as Node3D
	for v in VIEWS:
		if not only.is_empty() and not only.has(v[0]):
			continue
		day_night.set("time", v[3])
		_go(p, v[1], v[2])
		await _wait(3.0)  # past the biome's 1.5 s hold and its card
		var fps := await _measure_fps(2.0)
		await _shot(v[0])
		print("VIEW %-16s %5.1f fps" % [v[0], fps])
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
		if layer.name != "Viewmodel" and layer.visible:
			layer.visible = false
			hidden.append(layer)
	await process_frame
	await process_frame
	root.get_texture().get_image().save_png("%s/%s.png" % [out_dir, name])
	for layer in hidden:
		layer.visible = true
