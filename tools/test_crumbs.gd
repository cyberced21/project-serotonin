extends SceneTree
## Headless checks for crumbs (plans/crumbs.md): a swing on an ore rock digs a small dent rather
## than knocking out whole pieces (an undercut column may still come down), nothing mined is
## thrown as a physics body (only ore pickups are), and a dug rock comes back from a save with the
## same crumbs gone.
## Played on a throwaway save, so the real one is never touched.
##
##     godot --headless --path . -s res://tools/test_crumbs.gd -- --save-root=user://tmp

const ORES := ["rock", "iron_rock", "coal_rock", "gold_rock"]

var _failures := 0
var _world: Node3D


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.get_node("Skills").call("set_level", &"mining", 99)
	seed(7)
	_world = Node3D.new()
	root.add_child(_world)
	var cam := Camera3D.new()
	_world.add_child(cam)
	cam.make_current()

	for ore in ORES:
		var node := await _rock(ore)
		var crumbs: Array = node.get("_crumbs")
		_check(crumbs.size() > 300, "%s: baked into crumbs (%d)" % [ore, crumbs.size()])
		var blocks_before: int = node.call("_intact_chunks").size()
		var dented := false
		for attempt in 6:  # (a swing landing on a tough piece only cracks it)
			await _swing(node)
			if not (node.get("_crumb_gone") as Dictionary).is_empty():
				dented = true
				break
		var gone: Dictionary = node.get("_crumb_gone")
		_check(dented, "%s: a swing digs crumbs out" % ore)
		var pieces: Array = node.get("_pieces")
		var dent := gone.keys().filter(func(i: int) -> bool: return pieces[crumbs[i]["block"]].visible).size()
		_check(dent <= 8, "%s: ... a dent in what's standing, not a chunk of it (%d crumbs)" % [ore, dent])
		_check(blocks_before - node.call("_intact_chunks").size() <= 8, "%s: ... most pieces still there" % ore)
		for k in 3:
			await _swing(node)
		await physics_frame
		_check(_thrown() == 0, "%s: nothing thrown as a physics body" % ore)

		# save and load: the same crumbs and pieces gone
		var saved: Dictionary = node.call("to_dict")
		var copy := await _rock(ore)
		copy.call("from_dict", saved)
		_check((copy.call("to_dict") as Dictionary).get("crumbs", []).size() == saved.get("crumbs", []).size()
			and copy.call("to_dict")["gone"] == saved["gone"], "%s: a dug rock reloads the same" % ore)
		node.free()
		copy.free()
		_clear()

	# an ore wall: up close its layers are drawn as crumbs; a swing digs a dent, and the dent and
	# the pieces dug are saved; an older save (pieces only) still loads
	root.get_node("Tools").call("set_tier", &"pickaxe", 4)
	var run := _wall_run("a")
	var wall: Node3D = run.get_node("Panel0")
	cam.global_position = wall.global_transform * Vector3(0, 2.0, 3.0)
	var started := Time.get_ticks_msec()
	for f in 30:
		await process_frame
	print("  wall: crumbs drawn up close after %d ms" % (Time.get_ticks_msec() - started))
	_check(wall.get("_crumb_meshes")[0] != null, "wall: the face is drawn as crumbs up close")
	var out: Dictionary = wall.get("_crumbs_out")[0]
	var gone: Dictionary = wall.get("_gone")[0]
	var dug := 0
	for attempt in 20:  # (until a swing lands off the loose slabs, which come down whole)
		var from: Vector3 = wall.global_transform * Vector3(randf_range(-1.0, 1.0), randf_range(0.5, 3.5), 2.0)
		var hit := root.world_3d.direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(from, from + wall.global_basis * Vector3(0, 0, -6), 1))
		var before := gone.size()
		if not hit.is_empty():
			wall.call("hit", load("res://scripts/hit_info.gd").new(hit["position"], hit["normal"], hit["collider"], from))
		await physics_frame
		if not out.is_empty():
			dug = gone.size() - before
			break
	_check(not out.is_empty(), "wall: a swing digs crumbs out")
	_check(dug <= 2, "wall: ... a dent, not pieces (%d pieces gone)" % dug)
	await physics_frame
	_check(_thrown() == 0, "wall: nothing thrown as a physics body")
	var saved: Dictionary = wall.call("to_dict")
	run.free()
	run = _wall_run("b")
	wall = run.get_node("Panel0")
	wall.call("from_dict", saved)
	_check(wall.call("to_dict").get("crumbs", []) == saved.get("crumbs", []), "wall: the dent reloads the same")
	wall.call("from_dict", {"gone": [[0, 1, 2], [], [], [], [], [], [], []]})
	_check((wall.get("_gone")[0] as Dictionary).size() == 3, "wall: an older save, pieces only, loads")
	run.free()

	_world.free()
	print("test_crumbs: %s" % ("all passed" if _failures == 0 else "%d FAILED" % _failures))
	quit(1 if _failures > 0 else 0)


func _rock(ore: String) -> Node3D:
	var node: Node3D = (load("res://scenes/%s.tscn" % ore) as PackedScene).instantiate()
	_world.add_child(node)
	root.get_node("Tools").call("set_tier", node.get("tool_type"), maxi(int(node.get("tool_tier")), 0))
	await physics_frame
	await physics_frame
	return node


## A swing at the rock from a random side.
func _swing(node: Node3D) -> void:
	for attempt in 20:
		var centre: Vector3 = node.to_global(node.get("_shape_centre"))
		var a := randf() * TAU
		var from := centre + Vector3(cos(a) * 2.5, randf_range(0.0, 0.5), sin(a) * 2.5)
		var hit := root.world_3d.direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(from, centre, 1))
		if not hit.is_empty() and hit["collider"] == node and node.call("is_available"):
			node.call("hit", load("res://scripts/hit_info.gd").new(hit["position"], hit["normal"], node, from))
			await physics_frame
			return


## One ore wall panel (a run of one: loaded, not named, as an -s script compiles before the
## autoloads exist).
func _wall_run(id: String) -> Node3D:
	var run: Node3D = load("res://scripts/ore_wall_run.gd").new()
	run.name = "Run_" + id
	run.get("panels").append(Transform3D.IDENTITY)
	run.get("templates").append(0)
	run.get("seeds").append(5)
	run.get("save_ids").append("test_crumbs_" + id)
	_world.add_child(run)
	run.call("build")
	return run


## Rigid bodies other than ore pickups anywhere in the world.
func _thrown() -> int:
	return _world.find_children("*", "RigidBody3D", true, false) \
		.filter(func(b: Node) -> bool: return not b.has_method("launch")).size()


func _clear() -> void:
	for c in _world.get_children():
		if not c is Camera3D:
			c.free()


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failures += 1
		print("  FAIL: ", what)
