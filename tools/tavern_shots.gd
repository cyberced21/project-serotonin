extends SceneTree
## Screenshots of the villagers' day and the tavern (plans/tavern.md) in a fresh Hearthvale, on a
## throwaway save root:
##   godot --path . --audio-driver Dummy --screen 1 --resolution 1280x720 -s res://tools/tavern_shots.gd -- --save-root=user://tavern_shots
## The boarded-up tavern by day; breakfast on Rosa's terrace; the restored tavern from the square at
## night, the windows of the houses; inside at the third tier (the bar, the fire, Ollie fiddling);
## the top tier's annex and dancing; a game of dice. Saves to docs/images/tavern/. (No game class
## names: an -s script compiles before the autoloads exist.)

const OUT := "res://docs/images/tavern"
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
	for b in get_nodes_in_group("building"):
		village.call("set_tier", b.get("def").get("id"), 3)
	village.call("set_tier", &"tavern", 1)
	for id in [&"benches", &"flower_boxes", &"well", &"bunting", &"terrace", &"market"]:
		projects.call("set_done", id, true)
	var tavern := get_first_node_in_group("tavern") as Node3D

	# the ruin, by day, from across the square
	_view(Vector3(97, 0, 47), tavern.global_position + Vector3.UP * 2.0)
	await _run_to(11.0)
	await _shot("ruin")

	# breakfast on the terrace
	await _run_to(7.3, 6.0)
	_view(Vector3(91.0, 0, 35.8), Vector3(86.6, 0.8, 32.6))
	await _wait(1.0)
	await _shot("terrace")

	# restored (tier 3), at night: from the square, then inside
	village.call("set_tier", &"tavern", 3)
	await _run_to(21.6, 19.0)
	_view(Vector3(97, 0, 47.5), tavern.global_position + Vector3.UP * 1.8)
	await _wait(1.0)
	await _shot("tavern_night")
	_view(tavern.to_global(Vector3(3.1, 0.08, 2.9)), tavern.to_global(Vector3(-2.4, 1.0, -2.0)))
	await _wait(1.0)
	await _shot("inside")
	_view(tavern.to_global(Vector3(-2.6, 0.08, 1.2)), tavern.to_global(Vector3(3.1, 1.0, -1.6)))
	await _wait(1.0)
	await _shot("stage_and_fire")
	# the houses' windows from the square, lit and going dark
	await _run_to(22.5)
	_view(Vector3(101, 0, 41), Vector3(91, 1.5, 28))
	await _wait(1.0)
	await _shot("windows")

	# the top tier: the annex, dancing
	village.call("set_tier", &"tavern", 4)
	await _run_to(21.4, 20.5)
	var dancing := 0
	var guard := 0
	Engine.time_scale = 4.0
	day_night.set("frozen", true)
	while dancing == 0 and guard < 60 * 90:
		await physics_frame
		guard += 1
		for b in get_nodes_in_group("building"):
			var v := b.get_node_or_null("Villager")
			var s: Node = v.get("_seat") if v else null
			if s and s.is_in_group("dance_spot") and v.get("state") == 0:
				dancing += 1
	Engine.time_scale = 1.0
	print("dancers: %d" % dancing)
	_view(tavern.to_global(Vector3(3.2, 0.08, 2.6)), tavern.to_global(Vector3(-3.0, 1.0, -0.5)))
	await _wait(1.0)
	await _shot("dancing")
	_view(tavern.to_global(Vector3(2.0, 0.08, 1.0)), tavern.to_global(Vector3(-5.6, 1.0, 0.5)))
	await _wait(0.5)
	await _shot("annex")

	# a game of dice: sit down at the table, someone comes over, roll
	var dice: Node3D = tavern.get("dice")
	player.set_physics_process(true)  # (sitting runs on the player's own tick)
	player.call("sit", dice.get("_seat1"))
	guard = 0
	while not dice.get("playing") and guard < 60 * 60:
		await process_frame
		guard += 1
	await _wait(0.8)
	dice.emit_signal("chose", "roll")
	await _wait(3.0)
	await _shot("dice", true)
	quit()


## Runs the day on to clock hour `h` (from hour `from` if given), sped up, then holds it there.
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


## Stands the player at `at` looking at `look` (pitched down or up to it).
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


func _shot(name: String, keep_ui := false) -> void:
	var hidden: Array[CanvasLayer] = []
	for layer in root.find_children("*", "CanvasLayer", true, false):
		if layer.visible and not (keep_ui and layer.get_parent() is Node3D and layer.get_parent().is_in_group("dice_game")):
			layer.visible = false
			hidden.append(layer)
	await process_frame
	await process_frame
	root.get_texture().get_image().save_png("%s/%s.png" % [OUT, name])
	print("SHOT ", name)
	for layer in hidden:
		layer.visible = true


func _wait(seconds: float) -> void:
	var end := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < end:
		await process_frame
