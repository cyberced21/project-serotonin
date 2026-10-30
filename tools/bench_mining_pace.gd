extends SceneTree
## Mining pace bench (plans/crumbs.md): how many swings each ore rock takes to break, and how many
## a wall layer takes to dig out, with the pick each needs and at a high Mining level. Swings land
## where a ray from a random spot round the rock (or in front of the wall) meets it, so the number
## follows whatever the breaking rules are. Played on a throwaway save.
##
##     godot --headless --path . -s res://tools/bench_mining_pace.gd -- --save-root=user://tmp
##
## Options (after `--`): --trials=N rocks of each ore (default 12), --walls=N panels (default 4).

const ORES := ["rock", "iron_rock", "coal_rock", "gold_rock", "crystal_rock"]
const SAVE := "user://bench_mining_pace_save.json"

var trials := 12
var walls := 4


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--trials="):
			trials = arg.trim_prefix("--trials=").to_int()
		elif arg.begins_with("--walls="):
			walls = arg.trim_prefix("--walls=").to_int()
	_run.call_deferred()


func _run() -> void:
	root.get_node("SaveGame").set("path", SAVE)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
	root.get_node("Skills").call("set_level", &"mining", 99)
	seed(1234)
	var world := Node3D.new()
	root.add_child(world)
	var ground := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	(shape.shape as BoxShape3D).size = Vector3(40, 1, 40)
	shape.position = Vector3(0, -0.5, 0)
	ground.add_child(shape)
	world.add_child(ground)
	var cam := Camera3D.new()
	world.add_child(cam)
	cam.make_current()

	for ore in ORES:
		var swings := []
		var dents := []
		for t in trials:
			var node: Node3D = (load("res://scenes/%s.tscn" % ore) as PackedScene).instantiate()
			world.add_child(node)
			root.get_node("Tools").call("set_tier", node.get("tool_type"), maxi(int(node.get("tool_tier")), 0))
			await physics_frame
			await physics_frame
			var n := 0
			var misses := 0
			while node.call("is_available") and n < 200 and misses < 50:
				var hit: Variant = await _swing_at_rock(node)
				if hit == null:
					misses += 1
					continue
				node.call("hit", hit)
				n += 1
				await physics_frame
			swings.append(n)
			dents.append(misses)
			node.free()
			for d in world.get_children():  # (debris, pickups, effects)
				if d != ground and d != cam:
					d.free()
		print("%-13s swings: mean %.1f  min %d  max %d  (misses %d)" % [ore, _mean(swings), swings.min(), swings.max(), dents.reduce(func(a: int, b: int) -> int: return a + b, 0)])

	var tools := root.get_node("Tools")
	tools.call("set_tier", &"pickaxe", 0)
	var layer_swings := []
	for w in walls:
		var run: Node3D = load("res://scripts/ore_wall_run.gd").new()
		run.name = "Run%d" % w
		run.get("panels").append(Transform3D(Basis.IDENTITY, Vector3(0, 0, 0)))
		run.get("templates").append(w % 4)
		run.get("seeds").append(77 + w)
		run.get("save_ids").append("bench_%d" % w)
		world.add_child(run)
		run.call("build")
		var wall: Node3D = run.get_node("Panel0")
		cam.global_position = wall.global_transform * Vector3(0, 2.0, 3.0)
		await _frames(30)  # (the wall sees the camera near and makes its hulls)
		var n := 0
		var misses := 0
		while int(wall.get("front")) == 0 and n < 400 and misses < 200:
			var from: Vector3 = wall.global_transform * Vector3(randf_range(-1.3, 1.3), randf_range(0.2, 3.8), 2.0)
			var to: Vector3 = from + wall.global_basis * Vector3(randf_range(-0.2, 0.2), randf_range(-0.2, 0.2), -6.0)
			var hit := _ray(from, to)
			if hit.is_empty():
				misses += 1
				await physics_frame
				continue
			var info: RefCounted = load("res://scripts/hit_info.gd").new(hit["position"], hit["normal"], hit["collider"], from)
			tools.call("set_tier", &"pickaxe", 4)  # (any vein: the pace of digging, not the gating)
			wall.call("hit", info)
			n += 1
			await physics_frame
		layer_swings.append(n)
		run.free()
	print("wall layer    swings: mean %.1f  min %d  max %d" % [_mean(layer_swings), layer_swings.min(), layer_swings.max()])

	world.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
	quit(0)


## A swing from a random spot round the rock at its own height, aimed at its middle.
func _swing_at_rock(node: Node3D) -> Variant:
	var centre: Vector3 = node.to_global(node.get("_shape_centre"))
	var a := randf() * TAU
	var from := centre + Vector3(cos(a) * 2.5, randf_range(0.0, 0.6), sin(a) * 2.5)
	var to := centre + Vector3(randf_range(-0.25, 0.25), randf_range(-0.2, 0.3), randf_range(-0.25, 0.25))
	var hit := _ray(from, from + (to - from) * 2.0)
	await physics_frame
	if hit.is_empty() or not (hit["collider"] == node or node.is_ancestor_of(hit["collider"])):
		return null
	return load("res://scripts/hit_info.gd").new(hit["position"], hit["normal"], hit["collider"], from)


func _ray(from: Vector3, to: Vector3) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(from, to, 1)
	return root.world_3d.direct_space_state.intersect_ray(q)


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _mean(a: Array) -> float:
	return float(a.reduce(func(x: int, y: int) -> int: return x + y, 0)) / maxf(a.size(), 1)
