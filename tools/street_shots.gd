extends SceneTree
## Screenshots of the village street (plans/village-street.md) in a fresh Hearthvale, every building
## at its top tier (all the yards' stations open) and every project done, mid-morning with everyone
## at work, on a throwaway save root:
##   godot --path . --audio-driver Dummy --screen 1 --resolution 1280x720 -s res://tools/street_shots.gd -- --save-root=user://street_shots
## Add `--only=market,jetty` for just those views. Saves to docs/images/street/. (No game class
## names: an -s script compiles before the autoloads exist.)

const OUT := "res://docs/images/street"
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
		# the street end to end, the market from both sides, the air
		["street_west_end", Vector3(62, 0, 134), Vector3(150, 1.5, 125)],
		["street_east_end", Vector3(206, 0, 126), Vector3(110, 1.5, 128)],
		["market_from_south", Vector3(137, 0, 139), Vector3(137, 2, 104)],
		["market_from_hall", Vector3(137, 0, 111), Vector3(137, 0.5, 138)],
		["village_air", Vector3(137, 60, 235), Vector3(137, 0, 122)],
		["village_air_west", Vector3(15, 50, 125), Vector3(145, 0, 125)],
		# the work yards, everyone at it
		["smith_yard", Vector3(84, 0, 132), Vector3(80, 1, 119)],
		["woodcutter_yard", Vector3(106, 0, 131), Vector3(101, 0.8, 117)],
		["jetty", Vector3(57, 0, 140), Vector3(45, 0.5, 148)],
		["jetty_close", Vector3(50, 1.5, 152), Vector3(44, 0, 148)],
		["sorting_yard", Vector3(92, 0, 129), Vector3(93, 0.8, 141)],
		["baker_yard", Vector3(143, 0, 134), Vector3(142, 0.8, 148)],
		["tavern_front", Vector3(154, 0, 123), Vector3(156, 1.2, 110)],
		["mayor", Vector3(130, 0, 124), Vector3(126, 1.2, 114)],
		# behind the houses: the plots, your garden, the farmyard
		["plots_north_air", Vector3(100, 22, 70), Vector3(115, 0, 108)],
		["plots_south_air", Vector3(150, 22, 185), Vector3(140, 0, 150)],
		["home_garden", Vector3(120, 6, 72), Vector3(120, 0, 96)],
		["farmyard", Vector3(190, 0, 150), Vector3(210, 1.5, 160)],
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
