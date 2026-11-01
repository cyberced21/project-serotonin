extends SceneTree
## Screenshots of the water (plans/water.md) in a fresh Hearthvale, on a throwaway save root:
##   godot --path . --audio-driver Dummy --screen 1 --resolution 1280x720 -s res://tools/water_shots.gd -- --save-root=user://water_shots
## Stillwater from its shore and floating out on it; then under the water looking across, up at
## the surface and down at the bed, at night, and in the clearing pond. Saves to
## docs/images/water/. (No game class names: an -s script compiles before the autoloads exist.)

const OUT := "res://docs/images/water"
const LAKE := Vector2(38, 340)
const POND := Vector2(66, 86)
const SURFACE := -0.15
const EYE := 1.6

var player: CharacterBody3D
var terrain: Terrain3D


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for autoload in ["GraphicsSettings", "Settings"]:
		root.get_node(autoload).set("persist", false)  # never write the player's settings.cfg
	root.get_node("Worlds").call("play_fresh")
	await process_frame
	while get_first_node_in_group("player") == null:
		await process_frame
	await _wait(2.0)
	player = get_first_node_in_group("player") as CharacterBody3D
	terrain = get_first_node_in_group("terrain") as Terrain3D
	player.set_physics_process(false)
	var day_night := root.get_node("DayNight")
	day_night.set("frozen", true)
	day_night.set("time", 0.42)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))

	# from the east shore, looking out over the lake
	var shore := LAKE + Vector2(25, 4)
	_eye(Vector3(shore.x, _h(Vector3(shore.x, 0, shore.y)) + EYE, shore.y), Vector3(LAKE.x - 10, SURFACE, LAKE.y), false)
	await _wait(2.0)
	await _shot("lake_shore")
	# low over the lake, the waves running across it, and the creek's current from its bank
	_eye(Vector3(shore.x - 4, SURFACE + 0.6, shore.y), Vector3(LAKE.x - 6, SURFACE, LAKE.y + 2), false)
	await _wait(1.0)
	await _shot("lake_waves")
	var creek: PackedVector2Array = load("res://scripts/world_map.gd").creek()
	var k := int(creek.size() * 0.35)
	var along := (creek[k + 6] - creek[k]).normalized()
	var bank := creek[k] + Vector2(-along.y, along.x) * 4.0
	_eye(Vector3(bank.x, _h(Vector3(bank.x, 0, bank.y)) + EYE, bank.y), Vector3(creek[k + 14].x, SURFACE, creek[k + 14].y), false)
	await _wait(1.5)
	await _shot("creek")
	# floating out in the middle
	_eye(Vector3(LAKE.x + 6, SURFACE + 0.14, LAKE.y), Vector3(LAKE.x - 20, SURFACE + 0.3, LAKE.y + 6), true)
	await _wait(1.5)
	await _shot("floating")
	# under: across towards the shelf, up at the surface, down at the bed
	_eye(Vector3(LAKE.x + 4, SURFACE - 1.6, LAKE.y), Vector3(LAKE.x + 20, SURFACE - 2.0, LAKE.y), true)
	await _wait(1.5)
	await _shot("under_across")
	_eye(Vector3(LAKE.x + 2, SURFACE - 2.0, LAKE.y), Vector3(LAKE.x + 3.5, SURFACE + 2.0, LAKE.y + 0.5), true)
	await _wait(1.0)
	await _shot("under_up")
	_eye(Vector3(LAKE.x + 8, SURFACE - 1.2, LAKE.y), Vector3(LAKE.x + 11, SURFACE - 4.5, LAKE.y + 1), true)
	await _wait(1.0)
	await _shot("under_bed")
	# the shelf's edge from below, looking back at the shore
	_eye(Vector3(LAKE.x + 12, SURFACE - 1.0, LAKE.y), Vector3(LAKE.x + 24, SURFACE - 0.6, LAKE.y), true)
	await _wait(1.0)
	await _shot("under_shelf")
	# dusk, then night, under
	day_night.set("time", 0.78)
	_eye(Vector3(LAKE.x + 4, SURFACE - 1.6, LAKE.y), Vector3(LAKE.x + 20, SURFACE - 1.0, LAKE.y + 4), true)
	await _wait(2.0)
	await _shot("under_dusk")
	day_night.set("time", 0.95)
	await _wait(2.0)
	await _shot("under_night")
	# the clearing pond, under, by day
	day_night.set("time", 0.42)
	_eye(Vector3(POND.x, SURFACE - 1.2, POND.y), Vector3(POND.x - 8, SURFACE - 1.0, POND.y + 2), true)
	await _wait(2.0)
	await _shot("pond_under")
	print("water shots done")
	quit()


## Puts the player's eye at `eye` looking at `at` (swimming, if `swim`: the underwater view goes by it).
func _eye(eye: Vector3, at: Vector3, swim: bool) -> void:
	player.global_position = eye - Vector3.UP * EYE
	var d := at - eye
	player.rotation.y = atan2(-d.x, -d.z)
	player.set("_pitch", atan2(d.y, Vector2(d.x, d.z).length()))
	player.set("swimming", swim)
	player.call("reset_physics_interpolation")


func _h(p: Vector3) -> float:
	var h: float = terrain.data.get_height(p)
	return 0.0 if is_nan(h) else h


func _shot(name: String) -> void:
	var hidden: Array[CanvasLayer] = []
	for layer in root.find_children("*", "CanvasLayer", true, false):
		if layer.visible:
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
