extends SceneTree
## Screenshots of the road east and the market (plans/market.md) in a fresh Hearthvale, on a
## throwaway save root:
##   godot --path . --audio-driver Dummy --screen 1 --resolution 1280x720 -s res://tools/market_shots.gd -- --save-root=user://market_shots
## The landslide on the road, the retaining wall once it's built, the market stall, the trader's
## cart parked by it, her decorations. Saves to docs/images/market/. (No game class names: an -s
## script compiles before the autoloads exist.)

const OUT := "res://docs/images/market"

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
	day_night.set("time", 0.4)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var projects := root.get_node("Projects")

	# the landslide, from down the road
	var slide := get_first_node_in_group("landslide") as Node3D
	var down := slide.global_position - slide.global_basis.x * 12.0 - slide.global_basis.z * 2.0
	_view(down, slide.global_position + Vector3.UP * 0.5)
	await _wait(1.5)
	await _shot("landslide")

	# the wall, built
	projects.call("set_done", &"retaining_wall", true)
	await _wait(1.0)
	_view(slide.global_position - slide.global_basis.x * 9.0 - slide.global_basis.z * 4.0, slide.global_position + slide.global_basis.z * 4.0)
	await _wait(1.0)
	await _shot("retaining_wall")

	# the stall, with the trader in and her decorations
	projects.call("set_done", &"market", true)
	for id in [&"deco_baskets", &"deco_weathervane", &"deco_cart"]:
		projects.call("set_done", id, true)
	var trader := get_first_node_in_group("trader")
	day_night.emit_signal("day_broke")  # (the road opened yesterday: she comes today)
	day_night.set("time", 0.5)
	await _wait(1.5)
	var stall := get_first_node_in_group("market_stall") as Node3D
	var front := stall.global_position + stall.global_basis.z * 5.0 + stall.global_basis.x * 1.0
	_view(front, stall.global_position + Vector3.UP * 1.0)
	await _wait(1.0)
	await _shot("stall")
	var cart := trader.find_child("Cart", false, false) as Node3D
	_view(cart.global_position + Vector3(8, 0, 5), cart.global_position + Vector3.UP * 1.0)
	await _wait(1.0)
	await _shot("trader")
	_view(Vector3(100, 0, 50), Vector3(92, 2, 34))
	await _wait(1.0)
	await _shot("square")
	quit()


## Stands the player at `at` looking at `look` (pitched down or up to it).
func _view(at: Vector3, look: Vector3) -> void:
	at.y = _h(at)
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
