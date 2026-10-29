extends SceneTree
## Checks the village's walking network (scripts/village_paths.gd, plans/tavern.md), with every
## decoration built: each link is clear of buildings and props; the route from every building's
## door to every other's runs on clear legs; and a villager really walks one such route, staying
## on it (never further than a step from its legs).
##   godot --headless --path . -s res://tools/test_paths.gd -- --save-root=user://tool_worlds
## (No game class names: an -s script compiles before the autoloads exist.)

var _fails := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.get_node("Worlds").call("play_fresh")
	await process_frame
	while get_first_node_in_group("player") == null:
		await process_frame
	var projects := root.get_node("Projects")
	for p in projects.call("all"):
		projects.call("set_done", p["id"], true)
	for b in get_nodes_in_group("building"):  # the biggest tier of everything
		root.get_node("Village").call("set_tier", b.get("def").get("id"), 3)
	Engine.time_scale = 4.0  # let the upgrades (and their cheers) play out
	for i in 120:
		await physics_frame
	Engine.time_scale = 1.0
	var paths := get_first_node_in_group("village_paths") as Node3D
	_check(paths != null, "the village has its paths")
	if paths == null:
		_finish()
		return
	_links(paths)
	_doors(paths)
	await _walk(paths)
	_finish()


func _links(paths: Node3D) -> void:
	var g: Dictionary = paths.call("dump")
	var bad := 0
	for l in g["links"]:
		if not paths.call("is_clear", paths.call("named", StringName(l[0])), paths.call("named", StringName(l[1]))):
			print("  blocked link %s - %s" % l)
			bad += 1
	_check(bad == 0, "all %d links clear" % g["links"].size())


func _doors(paths: Node3D) -> void:
	var doors := _doors_of()
	var bad := 0
	var count := 0
	for a in doors:
		for b in doors:
			if a == b:
				continue
			count += 1
			var pts: PackedVector3Array = paths.call("route", doors[a], doors[b])
			var prev: Vector3 = doors[a]
			for i in pts.size():
				# (the very last step onto a door spot may be on a porch: not checked)
				if i < pts.size() - 1 and not paths.call("is_clear", prev, pts[i]):
					print("  %s -> %s: leg %d blocked (%s -> %s)" % [a, b, i, prev.snapped(Vector3.ONE * 0.1), pts[i].snapped(Vector3.ONE * 0.1)])
					bad += 1
				prev = pts[i]
	_check(bad == 0, "%d door-to-door routes, every leg clear" % count)


func _walk(paths: Node3D) -> void:
	var v: Node3D = null
	for b in get_nodes_in_group("building"):
		if b.get("def").get("id") == &"fisher":
			v = b.get_node("Villager")
	var smithy: Node3D = null
	for b in get_nodes_in_group("building"):
		if b.get("def").get("id") == &"smithy":
			smithy = b
	var door: Marker3D = smithy.call("spot", "Door")
	DayNight_freeze(12.0 / 24.0)
	v.global_position = v.get_parent().call("spot", "Door").global_position
	v.set("_watching", true)  # busy: not to be sent off to the well on the way (VillageDecor)
	v.call("_walk_to", door)
	var legs: PackedVector3Array = PackedVector3Array([v.global_position])
	legs.append_array(v.get("_route"))
	Engine.time_scale = 8.0
	var worst := 0.0
	var t := 0.0
	while v.get("_target") == door and v.get("state") == 1 and t < 60.0:  # State.WALK
		await physics_frame
		t += 1.0 / 60.0 * Engine.time_scale
		worst = maxf(worst, _off(v.global_position, legs))
	Engine.time_scale = 1.0
	print("  stopped: state %d, target %s, at %s" % [v.get("state"), v.get("_target").name, v.global_position.snapped(Vector3.ONE * 0.1)])
	print("fisher to the smithy: %d legs, %.1f s, at most %.2f m off them" % [legs.size() - 1, t, worst])
	_check(v.global_position.distance_to(door.global_position) < 0.3, "the fisher got to the smithy's door")
	_check(worst < 0.7, "and kept to the route")


func DayNight_freeze(at: float) -> void:
	var dn := root.get_node("DayNight")
	dn.set("time", at)
	dn.set("frozen", true)


## How far `p` is from the walked polyline.
func _off(p: Vector3, legs: PackedVector3Array) -> float:
	var q := Vector2(p.x, p.z)
	var best := INF
	for i in legs.size() - 1:
		var a := Vector2(legs[i].x, legs[i].z)
		var b := Vector2(legs[i + 1].x, legs[i + 1].z)
		best = minf(best, q.distance_to(Geometry2D.get_closest_point_to_segment(q, a, b)))
	return best


func _doors_of() -> Dictionary:
	var out := {}
	for b in get_nodes_in_group("building"):
		var m: Marker3D = b.call("spot", "Door")
		if m:
			out[b.get("def").get("id")] = m.global_position
	return out


func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		_fails += 1


func _finish() -> void:
	print("test_paths: %s" % ("PASS" if _fails == 0 else "%d FAILED" % _fails))
	quit(1 if _fails else 0)
