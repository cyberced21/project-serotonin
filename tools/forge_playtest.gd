extends SceneTree
## The forge moment, played in the real main world: stands you by Greta's anvil with the smithy at
## the right tier and the ingredients in hand, presses Forge, and saves screenshots through every
## beat (and the first swing on a rock after). Prints what happened.
##
##   godot --path . --screen 1 --resolution 1280x720 -s res://tools/forge_playtest.gd -- [--tier=1] [--tool=pickaxe] [--skip]
##
## `--tier`: the tier forged (1 copper, 2 iron, 3 crystal: the escalations). `--skip`: press E
## during the build-up, to check the skip lands on the reveal.
## Played on a throwaway save, without touching settings.cfg. Screenshots: user://forge_playtest/.
## (Untyped on purpose: an -s script can't name the game's classes that use autoloads.)

const OUT := "user://forge_playtest"
const SAVE := "user://forge_playtest_save.json"
const SHOTS := [["1_breath", 0.9], ["2_blow1", 1.53], ["3_blow3", 3.36], ["4_quench", 4.55],
	["5_reveal", 5.9], ["6_title", 7.0], ["7_handover", 8.1], ["8_after", 9.2]]

var tier := 1
var tool := &"pickaxe"
var skip := false


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--tier="):
			tier = clampi(arg.trim_prefix("--tier=").to_int(), 1, 3)
		elif arg.begins_with("--tool="):
			tool = StringName(arg.trim_prefix("--tool="))
		elif arg == "--skip":
			skip = true
	_run.call_deferred()


func _run() -> void:
	root.get_node("SaveGame").set("path", SAVE)  # (never save over the real file)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	change_scene_to_file("res://scenes/main.tscn")
	await _wait(2.5)
	var gfx := root.get_node_or_null("GraphicsSettings")
	if gfx:
		gfx.set("persist", false)
	root.get_node("DayNight").set("time", 0.45)
	var tools := root.get_node("Tools")
	var village := root.get_node("Village")
	village.call("set_tier", &"smithy", tier + 1)
	tools.call("set_tier", tool, tier - 1)
	for item in ["ore", "wood", "birch", "iron", "coal", "oak", "gold", "crystal", "pine"]:
		root.get_node("Inventory").call("set_count", StringName(item), 99)
	await _wait(5.0)  # the smithy rebuilds, the biome card fades

	var greta = null
	for v in current_scene.find_children("*", "Villager", true, false):
		if v.building.def.id == &"smithy":
			greta = v
	var player = get_first_node_in_group("player")
	var spot = greta.building.work_spot()
	var anvil = _anvil(greta.building)
	var away: Vector3 = spot.global_position - anvil
	away.y = 0.0
	player.global_position = anvil + away.normalized() * 1.9 + Vector3(0, -0.6, 0)
	player.reset_physics_interpolation()
	greta.call("script_place", spot.global_position, anvil)  # (she may have wandered off)
	await _wait(1.0)

	var panel = get_first_node_in_group("upgrade_panel")
	panel.call("open", greta)
	panel.call("_show_tab", true)
	await _wait(0.6)
	_shot("0_panel")
	print("forging %s tier %d: can %s, panel open %s, greta %.1f m away, mouse %d" % [tool, tier, tools.call("can_forge", tool),
		panel.call("is_open"), player.global_position.distance_to(greta.global_position), Input.mouse_mode])
	panel.call("_on_forge_pressed", tool)
	var start := Time.get_ticks_msec()
	var cut = current_scene.find_children("*", "ForgeCutscene", true, false)
	print("cutscene running: ", not cut.is_empty())
	for s in SHOTS:
		if skip and s[0] == "2_blow1":
			var e := InputEventAction.new()
			e.action = &"interact"
			e.pressed = true
			Input.parse_input_event(e)
			print("pressed E to skip at %.2f s" % ((Time.get_ticks_msec() - start) / 1000.0))
		while (Time.get_ticks_msec() - start) / 1000.0 < s[1] - (3.3 if skip and s[1] > 2.0 else 0.0):
			await process_frame
		_shot(s[0])
	while not current_scene.find_children("*", "ForgeCutscene", true, false).is_empty():
		await process_frame
	print("cutscene over after %.2f s (real time); player frozen: %s  tier now: %d  fresh: %s" % [
		(Time.get_ticks_msec() - start) / 1000.0, player.get("cutscene"), tools.call("tier", tool), tools.get("fresh").has(tool)])

	# the first swing: on a copper rock nearby
	var rock = null
	for n in current_scene.find_children("*", "ResourceNode", true, false):
		if n.tool_type == tool and n.is_available() and n.can_gather():
			if rock == null or n.global_position.distance_to(player.global_position) < rock.global_position.distance_to(player.global_position):
				rock = n
	if rock:
		player.global_position = rock.global_position + Vector3(0, 0, 1.6)
		player.reset_physics_interpolation()
		await _wait(0.4)
		var d: Vector3 = rock.global_position + Vector3.UP * 0.4 - player.camera.global_position
		player.rotation.y = atan2(-d.x, -d.z)
		player.set("_pitch", atan2(d.y, Vector2(d.x, d.z).length()))
		await _wait(0.4)
		var eye: Vector3 = player.camera.global_position
		var q := PhysicsRayQueryParameters3D.create(eye, rock.global_position + Vector3.UP * 0.4)
		q.exclude = [player.get_rid()]
		var hit: Dictionary = player.get_world_3d().direct_space_state.intersect_ray(q)
		var at: Vector3 = hit.get("position", rock.global_position + Vector3.UP * 0.4)
		var normal: Vector3 = hit.get("normal", (eye - at).normalized())
		rock.hit(load("res://scripts/hit_info.gd").new(at, normal, rock, eye))  # on the surface facing us
		for i in 6:
			await _wait(0.1)
			_shot("9_first_swing_%d" % i)
		print("first swing landed; fresh left: ", tools.get("fresh").has(tool))
	await _wait(0.5)
	root.get_node("SaveGame").set("_dirty", false)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
	print("screenshots in ", ProjectSettings.globalize_path(OUT))
	quit()


func _anvil(building) -> Vector3:
	for m in building.find_children("*AnvilTop*", "MeshInstance3D", true, false):
		if m.is_visible_in_tree():
			return m.global_position
	return building.global_position


func _shot(name: String) -> void:
	root.get_texture().get_image().save_png("%s/%s.png" % [OUT, name])


func _wait(seconds: float) -> void:
	var t := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < t:
		await process_frame
