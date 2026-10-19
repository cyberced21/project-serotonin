extends SceneTree
## Ore close-up: stands in front of an ore rock in the main world, strikes the same spot until a
## piece splits off (a tip hit when there is one, with --tips) and saves a screenshot after every
## hit, plus one mid-jolt, to judge how pieces loosen and come away.
##
##   godot --path . --screen 1 --resolution 1280x720 -s res://tools/ore_closeup.gd -- --ore=rock
##
## Options (after `--`):
##   --ore=NAME     the rock's scene: rock (copper), iron_rock, coal_rock, gold_rock, crystal_rock
##   --distance=M  how far from the rock to stand (default 4)
##   --angle=DEG   watch from this far round the rock (the hits still come from the front)
##   --tips         aim the hits after the first at the nearest crack tip
##   --label=NAME   sub-folder of docs/images/ores/ to save into (default "latest")
## The game is played on a throwaway save, so the real one is never touched.

var ore := "rock"
var tips := false
var out_dir := "res://docs/images/ores/latest"
var distance := 4.0
var angle := 0.0


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--ore="):
			ore = arg.trim_prefix("--ore=")
		elif arg.begins_with("--distance="):
			distance = arg.trim_prefix("--distance=").to_float()
		elif arg.begins_with("--angle="):
			angle = arg.trim_prefix("--angle=").to_float()
		elif arg == "--tips":
			tips = true
		elif arg.begins_with("--label="):
			out_dir = "res://docs/images/ores/" + arg.trim_prefix("--label=")
	_run.call_deferred()


func _run() -> void:
	root.get_node("SaveGame").set("path", "user://ore_closeup_save.json")
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://ore_closeup_save.json"))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	change_scene_to_file("res://scenes/main.tscn")
	await _wait(2.0)
	var gfx := root.get_node_or_null("GraphicsSettings")
	if gfx:
		gfx.set("persist", false)
	root.get_node("DayNight").set("time", 0.42)
	var node := _find_rock()
	if node == null:
		push_error("no %s.tscn in the world" % ore)
		quit(1)
		return
	var p := get_first_node_in_group("player") as Node3D
	var at := node.global_position
	var back := Vector3(-at.x, 0.0, -at.z).normalized()  # stand on the side toward the world's middle
	var watch := back.rotated(Vector3.UP, deg_to_rad(angle))
	for i in 2:
		p.call("teleport", at + watch * distance, at)
		await _wait(0.5)
	var cam := p.get("camera") as Camera3D
	(cam.get_parent() as Node3D).rotation.x = -0.25  # look down at it
	await _wait(2.5)
	node.call("set_highlighted", false)
	await _shot("%s_0" % ore)
	var aim := at + Vector3.UP * 0.6
	var eye := at + back * distance + Vector3.UP * (cam.global_position.y - p.global_position.y)
	eye.y += p.global_position.y - at.y
	for i in 12:
		if not node.call("is_available"):
			break
		var target := aim
		var tip_points: Array = node.call("crack_tips")
		if tips and not tip_points.is_empty():
			target = tip_points[0]
		var hit := _cast(eye, target)
		if hit.is_empty():
			push_error("missed the rock")
			break
		var info := HitInfo.new(hit["position"], hit["normal"], hit["collider"], eye)
		var chunks_before := _visible_chunks(node)
		node.call("hit", info)
		node.call("set_highlighted", false)  # (the aim outline would wash the rock out)
		await _wait(0.06)
		await _shot("%s_%d_jolt" % [ore, i + 1])
		await _wait(0.6)
		await _shot("%s_%d" % [ore, i + 1])
		print("HIT %d  tip=%s  chunks %d -> %d" % [i + 1, not tip_points.is_empty() and tips, chunks_before, _visible_chunks(node)])
		if _visible_chunks(node) < chunks_before:
			break
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://ore_closeup_save.json"))
	quit()


func _find_rock() -> Node3D:
	var path := "res://scenes/%s.tscn" % ore
	var best: Node3D = null
	for n in current_scene.find_children("*", "Node3D", true, false):
		if n.scene_file_path == path and (best == null or n.global_position.length() < best.global_position.length()):
			best = n
	return best


func _cast(from: Vector3, to: Vector3) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(from, from + (to - from) * 2.0)
	var p := get_first_node_in_group("player") as CollisionObject3D
	q.exclude = [p.get_rid()]
	return p.get_world_3d().direct_space_state.intersect_ray(q)


func _visible_chunks(node: Node) -> int:
	var count := 0
	for c in node.get_node("Visual/Chunks").get_children():
		if c.visible:
			count += 1
	return count


func _wait(seconds: float) -> void:
	var end := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < end:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE  # (captured, a stray held button swings the pick)
		await process_frame


func _shot(name: String) -> void:
	var hidden: Array[CanvasLayer] = []
	for layer in root.find_children("*", "CanvasLayer", true, false):
		if layer.visible:  # (the tool in hand too: it covers the rock)
			layer.visible = false
			hidden.append(layer)
	await process_frame
	await process_frame
	root.get_texture().get_image().save_png("%s/%s.png" % [out_dir, name])
	for layer in hidden:
		layer.visible = true
