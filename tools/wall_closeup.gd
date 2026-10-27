extends SceneTree
## Ore wall close-up: stands a panel of ore wall (OreWall) on Greystone Quarry's floor, works
## its face with the pick, and saves screenshots along the way, to judge how it digs.
##
##   godot --path . --screen 1 --resolution 1280x720 -s res://tools/wall_closeup.gd
##
## Options (after `--`):
##   --hits=N      swings in all (default 40)
##   --every=N     a screenshot every N swings (default 10)
##   --template=N  which baked panel (0..3)
##   --seed=N      the panel's vein seed
##   --ring=N/M    the panel stands on ring N of M (richer further down)
##   --dig=N       dig out the first N layers straight away (to look deeper in)
##   --tier=N      the pickaxe's tier (default 3: every ore can be mined)
##   --angle=DEG   look from this far round (the swings still come from the front)
##   --label=NAME  sub-folder of docs/images/walls/ to save into (default "latest")
## The game is played on a throwaway save, so the real one is never touched.

var hits := 40
var every := 10
var template := 0
var vein_seed := 1
var ring := Vector2i(0, 1)
var dig := 0
var tier := 3
var angle := 0.0
var out_dir := "res://docs/images/walls/latest"


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		var v := arg.get_slice("=", 1)
		if arg.begins_with("--hits="):
			hits = v.to_int()
		elif arg.begins_with("--every="):
			every = maxi(v.to_int(), 1)
		elif arg.begins_with("--template="):
			template = v.to_int()
		elif arg.begins_with("--seed="):
			vein_seed = v.to_int()
		elif arg.begins_with("--ring="):
			ring = Vector2i(v.get_slice("/", 0).to_int(), v.get_slice("/", 1).to_int())
		elif arg.begins_with("--dig="):
			dig = v.to_int()
		elif arg.begins_with("--tier="):
			tier = v.to_int()
		elif arg.begins_with("--angle="):
			angle = v.to_float()
		elif arg.begins_with("--label="):
			out_dir = "res://docs/images/walls/" + v
	_run.call_deferred()


func _run() -> void:
	root.get_node("SaveGame").set("path", "user://wall_closeup_save.json")
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://wall_closeup_save.json"))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	change_scene_to_file("res://scenes/main.tscn")
	await _wait(2.0)
	var gfx := root.get_node_or_null("GraphicsSettings")
	if gfx:
		gfx.set("persist", false)
	root.get_node("DayNight").set("time", 0.42)
	root.get_node("Skills").call("set_level", &"mining", 50)
	root.get_node("Tools").call("set_tier", &"pickaxe", tier)
	var p := get_first_node_in_group("player") as Node3D
	var spot := WorldMap.QUARRY_CENTER_3 + Vector3(0, 0, -11.0)  # (the pit floor, facing its middle)
	var ground := _cast(spot + Vector3.UP * 50.0, spot + Vector3.DOWN * 50.0)
	spot.y = ground["position"].y - 0.1 if not ground.is_empty() else 0.0
	var wall := (load("res://scenes/ore_wall.tscn") as PackedScene).instantiate()
	wall.set("template", template)
	wall.set("save_id", &"closeup")
	for prop in ["vein_seed", "ring", "rings"]:
		if prop in wall:
			wall.set(prop, vein_seed if prop == "vein_seed" else ring.x if prop == "ring" else ring.y)
	current_scene.add_child(wall)
	wall.global_position = spot
	if dig > 0 and wall.has_method("dig_layers"):
		wall.call("dig_layers", dig)
	var face := spot + Vector3(0, 0, -float(dig) * 0.5)
	var watch := Vector3.BACK.rotated(Vector3.UP, deg_to_rad(angle))
	for i in 2:
		p.call("teleport", face + watch * 3.2, face + Vector3.UP * 1.6)
		await _wait(0.5)
	var cam := p.get("camera") as Camera3D
	(cam.get_parent() as Node3D).rotation.x = 0.0
	await _wait(2.5)
	await _shot("wall_0")
	var eye := face + Vector3.BACK * 2.2 + Vector3.UP * 1.6
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var dug := 0
	for i in hits:
		# work across the face, low first, the way you'd dig in
		var target := face + Vector3(rng.randf_range(-1.1, 1.1), rng.randf_range(0.4, 3.4), 0.0)
		var hit := _cast(eye, target + (target - eye).normalized() * 2.0)
		if not hit.is_empty() and hit["collider"] == wall:
			dug += 1 if _swing(wall, hit, eye) else 0
		await _wait(0.12)
		if (i + 1) % every == 0:
			wall.call("set_highlighted", false)
			await _wait(0.8)
			await _shot("wall_%d" % (i + 1))
	for k in 8:
		print("LAYER %d ore %s" % [k, wall.call("ore_count", k)])
	print("WALL front %d  bit %d of %d  gone %s" % [wall.get("front"), dug, hits, wall.call("to_dict")["gone"].map(func(a: Array) -> int: return a.size())])
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://wall_closeup_save.json"))
	quit()


func _swing(wall: Node, hit: Dictionary, eye: Vector3) -> bool:
	var info := HitInfo.new(hit["position"], hit["normal"], hit["collider"], eye)
	wall.call("aim_at", hit["position"], hit["normal"])
	return wall.call("hit", info)


func _cast(from: Vector3, to: Vector3) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(from, to, 1)  # (the world: not debris or drops)
	var p := get_first_node_in_group("player") as CollisionObject3D
	q.exclude = [p.get_rid()]
	return p.get_world_3d().direct_space_state.intersect_ray(q)


func _wait(seconds: float) -> void:
	var end := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < end:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE  # (captured, a stray held button swings the pick)
		await process_frame


func _shot(name: String) -> void:
	var hidden: Array[CanvasLayer] = []
	for layer in root.find_children("*", "CanvasLayer", true, false):
		if layer.visible:
			layer.visible = false
			hidden.append(layer)
	await process_frame
	await process_frame
	root.get_texture().get_image().save_png("%s/%s.png" % [out_dir, name])
	for layer in hidden:
		layer.visible = true
