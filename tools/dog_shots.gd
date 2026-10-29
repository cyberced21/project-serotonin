extends SceneTree
## Screenshots of the dog (plans/dog.md) in a fresh Hearthvale, on a throwaway save root:
##   godot --path . --audio-driver Dummy --screen 1 --resolution 1280x720 -s res://tools/dog_shots.gd -- --save-root=user://dog_shots
## The strays napping by the pond; then, adopted, him sitting with you, trotting along the village
## path, carrying the lantern at night, and the finished doghouse with him at its door. Saves to
## docs/images/dog/. (No game class names: an -s script compiles before the autoloads exist.)

const OUT := "res://docs/images/dog"

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
	day_night.set("time", 0.38)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))

	# the strays by the pond
	await _wait(1.0)
	_view(Vector3(14, 0, 22), Vector3(9, 0, 17), 1.6)
	await _wait(2.0)
	await _shot("strays")

	# adopt the terrier, then each look
	var strays := get_nodes_in_group("stray_dog")
	var terrier: Node3D = strays.filter(func(d: Node) -> bool: return d.get("breed") == &"terrier")[0]
	var home := get_first_node_in_group("dog_home")
	home.call("adopt", terrier, &"wheaten", "Biscuit")
	var dog := terrier
	await _wait(1.0)
	dog.set("scripted", true)
	_view(Vector3(-4, 0, 6), Vector3(-3, 0, 3), 1.0)
	_put(dog, Vector3(-3.2, 0, 4.3), Vector3(-4, 0, 6), 1)  # sitting, looking up at you
	await _wait(1.5)
	await _shot("sitting")
	_put(dog, Vector3(-3.2, 0, 4.3), Vector3(-4, 0, 6), 4)  # being petted
	await _wait(0.4)
	await _shot("petted")

	# a big fluffy one trotting the village path
	(home.get("dog") as Node).free()  # (gone now, so the next adoption puts a new dog in)
	root.get_node("Companion").call("from_dict", {})
	root.get_node("Companion").call("adopt", &"fluffy", &"tricolour", "Bramble")
	await _wait(1.0)
	dog = get_first_node_in_group("dog") as Node3D
	dog.set("scripted", true)
	_view(Vector3(55, 0, 20), Vector3(50, 0, 15), 1.2)
	_put(dog, Vector3(51.5, 0, 16), Vector3(42, 0, 6), 0)
	dog.set("_speed", 2.5)
	await _wait(1.0)
	await _shot("trotting")

	# night: he carries the lantern
	day_night.set("time", 0.93)
	root.get_node("Lamps").set("has_lantern", true)
	root.get_node("Lamps").call("set_lantern_lit", true)
	dog.set("_player", player)
	_view(Vector3(30, 0, 30), Vector3(28, 0, 27), 1.3)
	_put(dog, Vector3(28.2, 0, 27.2), Vector3(30, 0, 30), 1)
	await _wait(2.0)
	await _shot("lantern")

	# the doghouse, all three projects done, him at its door in the morning
	root.get_node("Lamps").call("set_lantern_lit", false)
	day_night.set("time", 0.32)
	var projects := root.get_node("Projects")
	for id in [&"kennel", &"kennel_paint", &"kennel_porch"]:
		projects.call("set_done", id, true)
	await _wait(1.0)
	var decor := get_first_node_in_group("village_decor")
	var door: Transform3D = decor.call("kennel_door")
	var front := door.origin + door.basis.z * 3.2 + door.basis.x * 1.0
	_view(front, door.origin + Vector3.UP * 0.5, 1.4)
	_put(dog, door.origin, front, 1)
	await _wait(1.5)
	await _shot("doghouse")
	quit()


## Stands the player at `at` looking at `look`, eyes `eye` m up from the ground... (the camera
## rides the player's head).
func _view(at: Vector3, look: Vector3, _eye: float) -> void:
	at.y = _h(at)
	player.global_position = at
	var d := look - at
	player.rotation.y = atan2(-d.x, -d.z)
	# look down at it (the eye is about 1.6 m up)
	var pitch := -atan2(1.6 + _h(at) - look.y - _h(look) * (1.0 if look.y == 0.0 else 0.0), Vector2(d.x, d.z).length())
	player.set("_pitch", pitch)
	(player.get("head") as Node3D).rotation.x = pitch
	player.call("reset_physics_interpolation")


## Puts the dog at `at` facing `toward`, in `state` (0 follow, 1 sit, 2 lie, 4 petted).
func _put(dog: Node3D, at: Vector3, toward: Vector3, state: int) -> void:
	at.y = _h(at)
	var d := toward - at
	dog.set("_yaw", atan2(d.x, d.z))
	dog.global_transform = Transform3D(Basis(Vector3.UP, atan2(d.x, d.z)), at)
	dog.set("state", state)
	if state == 4:
		dog.set("_pet_left", 5.0)
	dog.call("reset_physics_interpolation")


func _h(p: Vector3) -> float:
	var h: float = terrain.data.get_height(p)
	return 0.0 if is_nan(h) else h


func _shot(name: String) -> void:
	var hidden: Array[CanvasLayer] = []
	for layer in root.find_children("*", "CanvasLayer", true, false):
		if layer.visible:  # (the tool in hand too: it covers the dog)
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
