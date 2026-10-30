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
