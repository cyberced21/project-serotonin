extends SceneTree
## Checks the map editor's water in the game (plans/terrain-editing.md), whatever the layout has:
##   - every pond (the clearing's, the lake, any drawn) has its water, about as deep as it asked at
##     its deepest, and the fish it asked for
##   - every river has its water: wet all the way down its middle (wadeable), the current running
##     downstream wherever it's the river's own water (not a pond's it runs into)
##   godot --headless --path . -s res://tools/test_water.gd -- --save-root=user://tool_worlds
## (No game class names: an -s script compiles before the autoloads exist.)

var _fails := 0


func _initialize() -> void:
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	if not ok:
		_fails += 1
		print("  FAIL " + what)


func _run() -> void:
	root.get_node("Worlds").call("play_fresh")
	await process_frame
	while get_first_node_in_group("player") == null:
		await process_frame
	for i in 5:
		await process_frame
	var water_script := load("res://scripts/water_body.gd")
	var layout_water := load("res://scripts/layout_water.gd")
	var holder := current_scene.get_node_or_null("Layout/Water")
	_check(holder != null, "the layout's water is in the world")
	var ponds: Array = layout_water.ponds()
	var rivers: Array = layout_water.rivers()
	_check(ponds.any(func(p: Dictionary) -> bool: return p["id"] == "lake"), "the lake is the layout's")
	for p in ponds:
		var id := String(p["id"])
		var body := holder.get_node_or_null(NodePath(id.to_pascal_case())) if holder else null
		_check(body != null, "pond %s has its water" % id)
		if body == null:
			continue
		var deepest := 0.0
		var c: Vector2 = p["centre"]
		var reach := float(p["reach"])
		for x in range(-int(reach), int(reach) + 1):
			for z in range(-int(reach), int(reach) + 1):
				deepest = maxf(deepest, water_script.depth_at(self, Vector3(c.x + x, 0.0, c.y + z)))
		print("pond %s: deepest %.2f m (asked %.2f)" % [id, deepest, float(p.get("depth", 1.0))])
		_check(absf(deepest - float(p.get("depth", 1.0))) < 0.3, "pond %s is about as deep as it asked (%.2f m)" % [id, deepest])
		var want: Variant = p.get("fish", true)
		var fish := body.get_node_or_null("Fish")
		if want is Array:
			_check(fish != null and (fish.get("schools") as Array).size() == (want as Array).size(), "pond %s has the fish it asked for" % id)
	for r in rivers:
		var id := String(r["id"])
		var node := holder.get_node_or_null(NodePath(id.to_pascal_case())) if holder else null
		_check(node != null, "river %s has its water" % id)
		if node == null:
			continue
		var pts: PackedVector2Array = r["pts"]
		var dry := 0
		var deep := 0
		var still := 0
		for k in range(0, pts.size(), 2):
			var at := Vector3(pts[k].x, 0.0, pts[k].y)
			var depth: float = water_script.depth_at(self, at)
			if depth < 0.2:
				dry += 1
				print("  dry at (%.1f, %.1f)" % [at.x, at.z])
			elif depth > 1.9:
				deep += 1
			var body: Node = water_script.surface_at(self, at)
			if body and body.get_parent() == node and (body.get("flow") as Vector3).length() < 0.1:
				still += 1
		print("river %s: %d points, %d dry, %d too deep, %d still, %d stretches" % [id, pts.size() / 2, dry, deep, still, node.get_child_count()])
		_check(dry == 0, "river %s is wet all the way (%d dry)" % [id, dry])
		_check(deep == 0, "river %s is wadeable (%d too deep)" % [id, deep])
		_check(still == 0, "river %s's current runs (%d still)" % [id, still])
	print("water: %d ponds, %d rivers" % [ponds.size(), rivers.size()])
	print("test_water: %s" % ("PASS" if _fails == 0 else "%d FAILED" % _fails))
	quit(1 if _fails else 0)
