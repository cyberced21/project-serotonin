extends SceneTree
## Screenshots of the world (plans/world-pass.md): the bowl from the air, the green, the clearing,
## the rim and each place, in a fresh Hearthvale with every building at its top tier, on a
## throwaway save root:
##   godot --path . --audio-driver Dummy --screen 1 --resolution 1280x720 -s res://tools/world_shots.gd -- --save-root=user://world_shots
## Add `--only=green,farm_yard` for just those views. Saves to docs/images/world/. (No game class names: an -s script compiles before the autoloads exist.)

const OUT := "res://docs/images/world"
const SPEED := 10.0

var player: CharacterBody3D
var terrain: Terrain3D
var day_night: Node
var day: GDScript


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for autoload in ["GraphicsSettings", "Settings"]:
		root.get_node(autoload).set("persist", false)  # never write the player's settings.cfg
	day = load("res://scripts/villager_day.gd")
	root.get_node("Worlds").call("play_fresh")
	await process_frame
	while get_first_node_in_group("player") == null:
		await process_frame
	await _wait(2.0)
	player = get_first_node_in_group("player") as CharacterBody3D
	terrain = get_first_node_in_group("terrain") as Terrain3D
	player.set_physics_process(false)
	day_night = root.get_node("DayNight")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var village := root.get_node("Village")
	var projects := root.get_node("Projects")
	for p: Dictionary in projects.call("all"):
		projects.call("set_done", p["id"], true)
	for b in get_nodes_in_group("building"):
		village.call("set_tier", b.get("def").get("id"), b.get("def").call("max_tier"))
	village.call("set_addon", &"town_hall", &"lamplighter", 1)
	village.call("set_addon", &"fisher", &"lookout", 1)
	await _run_to(10.5, 9.0)
	await _wait(3.0)

	var views := [
		["aerial_south", Vector3(128, 95, 360), Vector3(128, 0, 110)],
		["aerial_west", Vector3(-150, 110, 130), Vector3(140, 0, 128)],
		["green", Vector3(128, 0, 150), Vector3(128, 1.5, 120)],
		["clearing", Vector3(60, 0, 80), Vector3(46, 1.0, 62)],
		["north_rim_down", Vector3(124, 0, -6), Vector3(128, 0, 128)],
		["quarry_rim_to_village", Vector3(-62, 0, 64), Vector3(128, 0, 128)],
		["quarry_floor", Vector3(-118, 0, 100), Vector3(-118, 8, 60)],
		["quarry_bridge", Vector3(80, 0, 40), Vector3(69, 0.5, 50)],
		["footbridge_site", Vector3(76, 0, 74), Vector3(66, 0.5, 66)],
		["pinewood_glade", Vector3(56, 0, -108), Vector3(76, 0, -131.5)],
		["frostpeak", Vector3(-30, 0, 40), Vector3(-98, 40, -54)],
		["goldmeadow", Vector3(300, 0, 270), Vector3(338, 0, 318)],
		["stillwater", Vector3(70, 0, 312), Vector3(38, 0, 338)],
		["east_road", Vector3(212, 0, 128), Vector3(320, 4, 130)],
		["rim_east_down", Vector3(330, 0, 128), Vector3(128, 0, 128)],
		# the village round its green (phases 4-5): the green from the town hall's door, the air,
		# the farm yard, the chapel, the stores, the allotments
		["green_from_hall", Vector3(129, 0, 104), Vector3(122, 0.5, 140)],
		["village_air", Vector3(128, 70, 230), Vector3(130, 0, 140)],
		["farm_yard", Vector3(158, 0, 176), Vector3(146, 1.5, 205)],
		["chapel", Vector3(166, 0, 140), Vector3(180, 3, 150)],
		["stores", Vector3(140, 0, 96), Vector3(160, 2, 82)],
		["allotments", Vector3(98, 0, 182), Vector3(82, 0.5, 192)],
		["washhouse", Vector3(92, 0, 140), Vector3(82, 1.5, 151)],
		# the country (phase 6): fields with their hedges and walls, a grove, the creek's banks,
		# the old things
		["fields_east", Vector3(216, 0, 136), Vector3(160, 1, 112)],
		["fields_south", Vector3(140, 0, 262), Vector3(128, 0, 170)],
		["fields_air", Vector3(60, 90, 300), Vector3(140, 0, 140)],
		["grove", Vector3(276, 0, 52), Vector3(299, 0, 24)],
		["creek_banks", Vector3(44, 0, 168), Vector3(30, 0.5, 190)],
		["farmstead", Vector3(210, 0, 62), Vector3(226, 1, 50)],
		["shrine", Vector3(80, 0, 230), Vector3(72, 1, 237)],
		["view_bench", Vector3(152, 0, 342), Vector3(128, 0, 180)],
		# the new places (phase 7)
		["watermill", Vector3(58, 0, 186), Vector3(41, 1.5, 201)],
		["orchard", Vector3(184, 0, 80), Vector3(202, 0, 58)],
		["shepherds_hill", Vector3(340, 0, 40), Vector3(360, 0, 12)],
		["haven_gap", Vector3(106, 0, -146), Vector3(111, 0, -163)],
		["haven", Vector3(102, 0, -158), Vector3(118, 0, -167)],
		["haven_air", Vector3(111, 45, -131), Vector3(111, 0, -163)],
		["shepherds_air", Vector3(330, 60, 60), Vector3(358, 0, 14)],
	]
	var only := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			only = a.trim_prefix("--only=")
	if only != "":
		views = views.filter(func(v: Array) -> bool: return v[0] in only.split(","))
	for v in views:
		_view(v[1], v[2])
		await _wait(1.2)
		await _shot(v[0])
	quit()


func _building(id: String) -> Node3D:
	for b in get_nodes_in_group("building"):
		if String(b.get("def").get("id")) == id:
			return b
	return null


func _run_to(h: float, from := -1.0) -> void:
	if from >= 0.0:
		day_night.set("time", day.call("time_at", from))
	day_night.set("frozen", false)
	Engine.time_scale = SPEED
	var target: float = day.call("time_at", h)
	var guard := 0
	while absf(wrapf(float(day_night.get("time")) - target, -0.5, 0.5)) > 0.002 and guard < 60 * 300:
		await process_frame
		guard += 1
	Engine.time_scale = 1.0
	day_night.set("frozen", true)
	await _wait(0.5)


func _view(at: Vector3, look: Vector3) -> void:
	at.y = maxf(_h(at), at.y)
	player.global_position = at
	var d := look - at
	player.rotation.y = atan2(-d.x, -d.z)
	var target_y := look.y if look.y != 0.0 else _h(look)
	var pitch := atan2(target_y - (at.y + 1.6), Vector2(d.x, d.z).length())
	player.set("_pitch", pitch)
	(player.get("head") as Node3D).rotation.x = pitch
	player.call("reset_physics_interpolation")


func _h(p: Vector3) -> float:
	var h: float = terrain.data.get_height(p)
	return 0.0 if is_nan(h) else h


func _shot(name: String) -> void:
	await _wait(0.6)
	var hidden: Array[CanvasLayer] = []
	for layer in root.find_children("*", "CanvasLayer", true, false):
		if layer.visible:
			layer.visible = false
			hidden.append(layer)
	await process_frame
	await process_frame
	root.get_texture().get_image().save_jpg("%s/%s.jpg" % [OUT, name], 0.85)
	print("SHOT ", name)
	for layer in hidden:
		layer.visible = true


func _wait(seconds: float) -> void:
	var end := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < end:
		await process_frame
