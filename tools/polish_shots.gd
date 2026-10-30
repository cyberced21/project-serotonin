extends SceneTree
## Screenshots of the polish pass's fixes (docs/TODO.md "Polish pass") in a fresh Hearthvale, every
## building at its top tier, on a throwaway save root:
##   godot --path . --audio-driver Dummy --screen 1 --resolution 1280x720 -s res://tools/polish_shots.gd -- --save-root=user://polish_shots
## The stairs, the chairs, the chandeliers' beams, the crane, the well, the noticeboard, the market
## awning, a door standing open, the desks, the oven's flue, the signs, Bram and Edda at work, the
## lamplighter's ladder and the lookout. Saves to docs/images/polish/. (No game class names: an -s
## script compiles before the autoloads exist.)

const OUT := "res://docs/images/polish"
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

	var hall := _building("town_hall")
	var rosa := _building("baker_cottage")
	var edda := _building("prospector_cottage")
	var home := _building("home")
	var lodge := _building("woodcutter")
	var smithy := _building("smithy")
	var fisher := _building("fisher")

	# the stairs, from behind the foot, and down from the head
	for pair in [["hall", hall], ["rosa", rosa], ["edda", edda], ["home", home]]:
		var b: Node3D = pair[1]
		var foot := b.call("mark", "Stair0") as Marker3D
		var head := b.call("mark", "Stair1") as Marker3D
		if foot and head:
			var along := head.global_position - foot.global_position
			along.y = 0.0
			along = along.normalized()
			_view(foot.global_position - along * 0.4 + Vector3.UP * 0.05, head.global_position + Vector3.UP * 1.2)
			await _shot("stair_%s_up" % pair[0])
			_view(head.global_position + along * 0.3 + Vector3.UP * 0.05, foot.global_position)
			await _shot("stair_%s_down" % pair[0])
	# chairs: a seat seen from the side, so the back shows which way it faces
	for pair in [["home", home, "Seat3"], ["rosa", rosa, "Seat1"], ["lodge", lodge, "Seat1"]]:
		var seat := (pair[1] as Node3D).call("mark", pair[2]) as Marker3D
		if seat:
			var f := seat.global_basis.z
			var side := f.cross(Vector3.UP).normalized()
			_view(seat.global_position + side * 1.8 + f * 0.8, seat.global_position + Vector3.UP * 0.5)
			await _shot("chair_%s" % pair[0])
	# chandeliers on their tie beams: looking up from the door
	for pair in [["lodge", lodge], ["home", home], ["hall", hall]]:
		var door := (pair[1] as Node3D).call("mark", "Doorway") as Marker3D
		if door:
			var c := (pair[1] as Node3D).global_position
			_view(door.global_position, Vector3(c.x, door.global_position.y + 2.8, c.z))
			await _shot("chandelier_%s" % pair[0])
	# the desks (the workbench under the drawers)
	for pair in [["home", home], ["edda", edda]]:
		var desk := (pair[1] as Node3D).call("mark", "Desk") as Marker3D
		if desk == null:
			desk = (pair[1] as Node3D).call("mark", "LookLedger") as Marker3D
		if desk:
			var c := (pair[1] as Node3D).global_position
			var to_c := Vector3(c.x - desk.global_position.x, 0, c.z - desk.global_position.z).normalized()
			_view(desk.global_position + to_c * 2.2 + Vector3(0, -desk.global_position.y + 0.0, 0), desk.global_position)
			await _shot("desk_%s" % pair[0])
	# doors standing open, their glass with them
	for pair in [["home", home], ["lodge", lodge], ["rosa", rosa]]:
		var door := (pair[1] as Node3D).call("mark", "Doorway") as Marker3D
		if door:
			var inward := door.global_basis.z
			inward.y = 0
			_view(door.global_position - inward.normalized() * 4.5 + Vector3(1.5, 0, 0), door.global_position + Vector3.UP * 1.2)
			await _shot("door_%s" % pair[0])
	# the village square's props
	_view(Vector3(99, 0, 37), Vector3(95.8, 1.6, 41.8))
	await _shot("well")
	_view(Vector3(109, 0, 28.5), Vector3(109, 1.8, 32))
	await _shot("noticeboard")
	_view(Vector3(89.9, 0, 34.0), Vector3(89.9, 1.8, 38))
	await _shot("market_stall")
	# the bakery's oven and sign, the lodge's lantern, the smithy, the hall's ladder, the lookout
	_view(rosa.global_position + rosa.global_basis * Vector3(1.0, 0, 6.5), rosa.global_position + rosa.global_basis * Vector3(-2.0, 2.4, 4.1))
	await _shot("rosa_front")
	_view(lodge.global_position + lodge.global_basis * Vector3(2.5, 0, 6.0), lodge.global_position + lodge.global_basis * Vector3(0.9, 1.6, 2.3))
	await _shot("lodge_front")
	_view(Vector3(118.5, 0, 47.5), Vector3(115.0, 1.6, 44.4))
	await _shot("lamplighter")
	_view(hall.global_position + hall.global_basis * Vector3(1.5, 0, 12.0), hall.global_position + Vector3.UP * 2.0)
	await _shot("hall_front")
	_view(Vector3(96.5, 0, 50.5), Vector3(91.7, 2.6, 51.3))
	await _shot("lookout")
	_view(smithy.global_position + smithy.global_basis * Vector3(0, 0, 6.5), smithy.global_position + Vector3.UP * 1.0)
	await _shot("smithy")
	# Bram and Edda at work
	for pair in [["bram", lodge], ["edda", edda]]:
		var v := (pair[1] as Node3D).get_node_or_null("Villager") as Node3D
		if v:
			var f := v.global_basis.z
			var side := f.cross(Vector3.UP).normalized()
			_view(v.global_position + side * 1.6 + f * 1.2 + Vector3.UP * 0.05, v.global_position + Vector3.UP * 1.0)
			await _shot("work_%s" % pair[0])
	# the crane in the quarry
	_view(Vector3(-104.0, 0, 6.0), Vector3(-118.0, 24.0, 2.7))
	await _wait(1.5)
	await _shot("crane")
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
