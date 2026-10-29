extends SceneTree
## Screenshots of the mine and its leftovers (plans/mine.md) in a fresh Hearthvale, on a throwaway
## save root:
##   godot --path . --audio-driver Dummy --screen 1 --resolution 1280x720 -s res://tools/mine_shots.gd -- --save-root=user://mine_shots
## Greystone from the rim and from the floor; the mouth boarded and open; level 1's way in, a dig
## face, a chamber; level 2's stream and the drained flood; level 3's crystal caverns; the minecart
## ride; the mine map; the tavern's long hall outside and in; the prospector's and the town hall's
## add-ons. Saves to docs/images/mine/. (No game class names: an -s script compiles before the
## autoloads exist.)

const OUT := "res://docs/images/mine"

var player: CharacterBody3D
var terrain: Terrain3D
var day_night: Node
var day: GDScript
var mine: Node3D


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
	day_night.set("frozen", true)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var village := root.get_node("Village")
	var projects := root.get_node("Projects")
	var biome := root.get_node("Biome")
	mine = get_first_node_in_group("mine") as Node3D
	var mouth := get_first_node_in_group("mine_mouth") as Node3D
	var c := Vector3(-175, 0, -15)

	# Greystone by day: from the rim, then the floor with the boarded mouth
	_set_time(11.0)
	_view(_round(60.0, -26.0), c + Vector3(0, 6, 0))
	await _wait(3.0)
	await _shot("quarry_rim")
	_view(mouth.global_position + mouth.global_basis.z * 9.0 + mouth.global_basis.x * 2.5, mouth.global_position + Vector3.UP * 1.5)
	await _wait(2.0)
	await _shot("quarry_floor_boarded")
	_view(_round(5.0, 220.0), _round(50.0, 60.0) + Vector3(0, 14, 0))
	await _wait(2.0)
	await _shot("quarry_levels")
	projects.call("set_done", &"mine_shoring", true)
	_set_time(19.4)
	_view(mouth.global_position + mouth.global_basis.z * 7.0, mouth.global_position + Vector3.UP * 1.6)
	await _wait(2.0)
	await _shot("mine_mouth_open")

	# level 1: most of it open and shored, a few faces left
	for cell in _cells(0):
		if cell not in [Vector2i(1, 6), Vector2i(2, 6), Vector2i(1, 5), Vector2i(7, 3), Vector2i(7, 4)]:
			mine.call("open_cell", 0, cell)
	await process_frame
	root.get_node("DayNight").emit_signal("day_broke")  # (shored overnight)
	await process_frame
	await _in_mine(0, Vector2i(5, 4), Vector2i(5, 5) + Vector2i(0, 1))
	await _shot("l1_way_in")
	await _in_mine(0, Vector2i(7, 5), Vector2i(7, 3))  # looking at the face toward (7, 4)
	await _shot("l1_dig_face")
	await _in_mine(0, Vector2i(3, 2), Vector2i(1, 1))
	await _shot("l1_chamber")
	var sheet: Node = mine.get("map")
	sheet.call("open")
	await _wait(0.5)
	await _shot("mine_map", sheet)
	sheet.call("close")

	# level 2: the lift down, the flood drained, the stream
	for id in [&"mine_lift", &"mine_pump", &"mine_shoring_2", &"mine_supports"]:
		projects.call("set_done", id, true)
	for cell in _cells(1):
		mine.call("open_cell", 1, cell)
	await process_frame
	root.get_node("DayNight").emit_signal("day_broke")
	await process_frame
	await _in_mine(1, Vector2i(4, 2), Vector2i(4, 1))
	await _shot("l2_stream")
	await _in_mine(1, Vector2i(5, 3), Vector2i(3, 6))
	await _shot("l2_chamber")

	# level 3: the crystal caverns
	for id in [&"mine_lift_3", &"mine_shoring_3", &"mine_rails"]:
		projects.call("set_done", id, true)
	for cell in _cells(2):
		mine.call("open_cell", 2, cell)
	await process_frame
	root.get_node("DayNight").emit_signal("day_broke")
	await process_frame
	await _in_mine(2, Vector2i(3, 3), Vector2i(1, 1))
	await _shot("l3_crystals")
	await _in_mine(2, Vector2i(5, 1), Vector2i(7, 2))
	await _shot("l3_caverns")
	await _in_mine(0, Vector2i(5, 4), Vector2i(5, 3))
	await _shot("l1_rail_stop")

	# the ride, halfway down
	mine.call("ride", 0)
	while mine.get("riding") == null:
		await process_frame
	var trip: Node = mine.get("riding")
	await _wait(1.0)
	trip.set("_t", 9.0)
	await _wait(0.6)
	await _shot("ride")
	trip.set("_t", 999.0)
	while mine.get("_travelling"):
		await process_frame
	player.set_physics_process(false)

	# the tavern's long hall, and some add-ons, back up in the village at dusk
	for b in get_nodes_in_group("building"):
		var def: Resource = b.get("def")
		village.call("set_tier", def.get("id"), def.get("tiers").size())
	for pair in [[&"prospector_cottage", &"orecart"], [&"prospector_cottage", &"assay"], [&"town_hall", &"flagstones"],
			[&"town_hall", &"clocktower"], [&"tavern", &"beergarden"], [&"tavern", &"snug"], [&"smithy", &"toolrack"],
			[&"woodcutter", &"birdfeeder"]]:
		village.call("set_addon", pair[0], pair[1])
	await _wait(8.0)  # (the upgrades play out)
	_set_time(20.6)
	var tavern := get_first_node_in_group("tavern") as Node3D
	_view(tavern.to_global(Vector3(3.0, 0, 13.0)), tavern.global_position + Vector3.UP * 2.5)
	biome.call("settle", player.global_position)
	await _wait(2.0)
	await _shot("tavern_hall")
	_view(tavern.to_global(Vector3(0.0, 0.1, 3.0)), tavern.to_global(Vector3(0.0, 1.2, -6.0)))
	await _wait(1.5)
	await _shot("tavern_inside")
	_set_time(14.0)
	for b in get_nodes_in_group("building"):
		var id: StringName = b.get("def").get("id")
		if id == &"prospector_cottage":
			_view(b.to_global(Vector3(-2.0, 0, 9.0)), b.global_position + Vector3.UP * 1.2)
			await _wait(1.5)
			await _shot("addons_prospector")
		elif id == &"town_hall":
			_view(b.to_global(Vector3(4.0, 0, 14.0)), b.global_position + Vector3.UP * 3.0)
			await _wait(1.5)
			await _shot("addons_town_hall")
	print("DONE")
	quit()


## Standing in cell `at` of level n, looking at cell `toward`.
func _in_mine(n: int, at: Vector2i, toward: Vector2i) -> void:
	var p: Vector3 = mine.call("cell_position", n, at)
	var q: Vector3 = mine.call("cell_position", n, toward)
	player.global_position = p
	var d := q - p
	player.rotation.y = atan2(-d.x, -d.z)
	player.set("_pitch", -0.05)
	(player.get("head") as Node3D).rotation.x = -0.05
	player.call("reset_physics_interpolation")
	root.get_node("Biome").call("settle", p)
	await _wait(1.5)


func _round(r: float, deg: float) -> Vector3:
	var a := deg_to_rad(deg)
	return Vector3(-175 + cos(a) * r, 0, -15 + sin(a) * r)


func _cells(n: int) -> Array:
	var out := []
	var rows: Array = load("res://scripts/mine_layout.gd").LEVELS[n]["map"]
	for y in rows.size():
		for x in (rows[y] as String).length():
			if (rows[y] as String)[x] != "#":
				out.append(Vector2i(x, y))
	return out


func _set_time(h: float) -> void:
	day_night.set("time", day.time_at(h))


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
	root.get_node("Biome").call("settle", at)


func _h(p: Vector3) -> float:
	var h: float = terrain.data.get_height(p)
	return 0.0 if is_nan(h) else h


## A screenshot with the HUD hidden (but `keep`, a panel to show).
func _shot(name: String, keep: Node = null) -> void:
	var hidden: Array[CanvasLayer] = []
	for layer in root.find_children("*", "CanvasLayer", true, false):
		if layer.visible and layer != keep:
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
