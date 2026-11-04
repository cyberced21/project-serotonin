extends SceneTree
## Screenshots of roads everywhere (plans/roads-everywhere.md) in a fresh Hearthvale, mid-morning:
## the village street building itself along (laid overnight, as you come to it), then the patches
## bettered: the market place cobbled, the lanes packed, the field tracks and the haul road packed.
##   godot --path . --audio-driver Dummy --screen 1 --resolution 1280x720 -s res://tools/roads_everywhere_shots.gd -- --save-root=user://road_shots
## Saves to docs/images/roads/everywhere_*. (No game class names: an -s script compiles before the autoloads.)

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
	var look := get_first_node_in_group("road_look")
	player.set_physics_process(false)
	await _run_to(10.5, 9.0)
	await _wait(2.0)

	# the street, laid overnight: watched from beside it as it builds itself along
	var street := _road(&"main_street")
	var k := street.size() / 2
	var a := street[k]
	var b := street[mini(k + 40, street.size() - 1)]
	var side := (b - a).normalized()
	side = Vector2(-side.y, side.x)
	_view(Vector3(a.x, 0, a.y) + Vector3(side.x, 0, side.y) * 5.0 + Vector3(0, 3.0, 0), Vector3(b.x, 0, b.y))
	await _wait(1.5)
	await _shot("everywhere_before")
	roads.call("set_level", &"main_street", 1, true)
	day_night.emit_signal("day_broke")
	while not look.call("laying"):
		await process_frame
	for i in 3:
		await _wait(0.45)
		await _shot("everywhere_building_%d" % (i + 1), 0.0)
	while look.call("laying"):
		await process_frame
	await _shot("everywhere_built", 0.3)
	_view(Vector3(a.x, 0, a.y) + Vector3(side.x, 0, side.y) * 4.0 + Vector3(0, 2.5, 0), Vector3(a.x, 0.01, a.y))
	await _shot("everywhere_built_close")

	# the patches, bettered at once (the debug menu's way)
	roads.call("set_level", &"market", 2)
	roads.call("set_level", &"lanes", 1)
	roads.call("set_level", &"field_tracks", 1)
	roads.call("set_level", &"haul_road", 1)
	await _wait(1.0)
	var green: Vector2 = load("res://scripts/world_map.gd").village_center()
	_view(Vector3(green.x - 6, 6.0, green.y + 24), Vector3(green.x, 0, green.y))
	await _shot("everywhere_market")
	_view(Vector3(green.x, 45.0, green.y + 60), Vector3(green.x, 0, green.y - 10))
	await _shot("everywhere_village_air")
	var field: Vector2 = load("res://scripts/world_map.gd").field_center()
	_view(Vector3(field.x - 50, 35.0, field.y + 50), Vector3(field.x, 0, field.y))
	await _shot("everywhere_fields")
	var pit: Vector2 = load("res://scripts/world_map.gd").quarry_center()
	_view(Vector3(pit.x + 50, 30.0, pit.y + 40), Vector3(pit.x, -15, pit.y))
	await _shot("everywhere_quarry")
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


func _shot(name: String, settle := 0.8) -> void:
	await _wait(settle)
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
