extends SceneTree
## Screenshots of road travel (plans/road-travel.md) in a fresh Hearthvale, mid-morning: the road to
## the Pinewood packed, the village street cobbled, the carter's cart at a stop and from its seat.
##   godot --path . --audio-driver Dummy --screen 1 --resolution 1280x720 -s res://tools/road_shots.gd -- --save-root=user://road_shots
## Saves to docs/images/roads/. (No game class names: an -s script compiles before the autoloads.)

const OUT := "res://docs/images/roads"
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
	day_night = root.get_node("DayNight")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var roads := root.get_node("Roads")
	roads.call("set_level", &"village_road", 1)
	roads.call("set_level", &"lake_road", 1)
	roads.call("set_level", &"main_street", 2)
	roads.get("reached")[&"main_street:0"] = true
	root.get_node("Projects").call("set_done", &"carter", true)
	player.set_physics_process(false)
	await _run_to(10.5, 9.0)
	await _wait(2.0)

	var road := _road(&"village_road")
	var k := road.size() / 3
	var a := road[k]
	var b := road[mini(k + 25, road.size() - 1)]
	_view(Vector3(a.x, 0, a.y), Vector3(b.x, 0.8, b.y))
	await _shot("packed_along")
	var side := (b - a).normalized()
	side = Vector2(-side.y, side.x)
	_view(Vector3(a.x, 0, a.y) + Vector3(side.x, 0, side.y) * 6.0 + Vector3(0, 3.5, 0), Vector3(a.x, 0.01, a.y))
	await _shot("packed_close")
	_view(Vector3(62, 0, 134), Vector3(150, 1.5, 125))
	await _shot("cobbled_street")
	_view(Vector3(96, 3.0, 133), Vector3(96, 0.01, 128.5))
	await _shot("cobbled_close")
	_view(Vector3(137, 40, 175), Vector3(120, 0, 120))
	await _shot("roads_air")

	# the cart: rung at the cart shed, watched from across the road, then ridden
	var line := get_first_node_in_group("cart_line")
	var stops: Dictionary = line.get("stops")
	var shed: Vector2 = stops[&"shed"]["at"]
	_view(Vector3(shed.x, 0, shed.y) + Vector3(-14, 1.0, 10), Vector3(shed.x, 1.0, shed.y))
	line.call("call_cart", &"shed", &"main_street:0")
	await _wait(3.0)
	await _shot("cart_coming")
	await _wait(3.5)
	await _shot("cart_at_stop")
	await _wait(10.0)  # (it gives up waiting and goes)
	while line.call("riding"):
		await process_frame
	player.set_physics_process(true)
	player.call("teleport", Vector3(shed.x + 2.0, _h(Vector3(shed.x, 0, shed.y)) + 0.3, shed.y))
	line.call("call_cart", &"shed", &"main_street:0")
	while player.get("seat") == null:
		await process_frame
	await _wait(7.0)
	await _shot("riding")
	await _wait(4.0)
	await _shot("riding_2")
	quit()


func _road(id: StringName) -> PackedVector2Array:
	for r in load("res://scripts/world_map.gd").roads():
		if r["id"] == id:
			return r["pts"]
	return PackedVector2Array()


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
	at.y = _h(at) + maxf(at.y, 0.0)
	player.global_position = at
	var d := look - at
	player.rotation.y = atan2(-d.x, -d.z)
	var target_y := _h(look) + look.y
	var pitch := atan2(target_y - (at.y + 1.6), Vector2(d.x, d.z).length())
	player.set("_pitch", pitch)
	(player.get("head") as Node3D).rotation.x = pitch
	player.call("reset_physics_interpolation")


func _h(p: Vector3) -> float:
	var h: float = terrain.data.get_height(p)
	return 0.0 if is_nan(h) else h


func _shot(name: String) -> void:
	await _wait(0.8)
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
