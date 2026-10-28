extends SceneTree
## Checks Hearthvale's creek (scripts/creek.gd, plans/world.md): water you can wade the whole way
## from the spring to the lake, carrying a current downstream; banks with no ledge, rising out of
## the water; grayling and salmon stocked in it.
##   godot --headless --path . -s res://tools/test_creek.gd -- --save-root=user://tool_worlds

var _fails := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.get_node("Worlds").call("play_fresh")
	await process_frame
	while get_first_node_in_group("player") == null:
		await process_frame
	for i in 5:
		await process_frame
	var terrain := get_first_node_in_group("terrain") as Terrain3D
	var pts: PackedVector2Array = load("res://scripts/world_map.gd").creek()
	var creek_script := load("res://scripts/creek.gd")
	var water_body := load("res://scripts/water_body.gd")
	var dry := 0
	var deep := 0
	var still := 0
	var ledges := 0
	var low_banks := 0
	var checked := 0
	for k in range(0, pts.size(), 2):
		var p := pts[k]
		if creek_script.in_other_water(p):
			continue
		checked += 1
		var at := Vector3(p.x, 0.0, p.y)
		var depth: float = water_body.depth_at(self, at)
		if depth < 0.2:
			dry += 1
		elif depth > 1.6:
			deep += 1
		var body: Node = water_body.surface_at(self, at)
		var in_creek: bool = body != null and body.get_parent() == get_first_node_in_group("creek")
		if body == null or (in_creek and (body.get("flow") as Vector3).length() < 0.1):  # (or the pond's)
			still += 1
		var side: Vector2 = creek_script.across(pts, k)
		for dir in [-1.0, 1.0]:
			var last: float = terrain.data.get_height(at)
			for s in range(1, 21):  # out to 10 m from the middle, half a metre at a time
				var q: Vector2 = p + side * dir * s * 0.5
				var g: float = terrain.data.get_height(Vector3(q.x, 0.0, q.y))
				if absf(g - last) > 0.45 and maxf(g, last) > -0.15:  # (the pools' beds may dip)
					ledges += 1
					print("  a ledge of %.2f m at (%.1f, %.1f)" % [g - last, q.x, q.y])
				last = g
			var out: Vector2 = p + side * dir * 6.0
			if terrain.data.get_height(Vector3(out.x, 0.0, out.y)) < -0.1:
				low_banks += 1
	print("creek: %d points checked" % checked)
	_check(checked > 50, "the creek has open water of its own (%d points)" % checked)
	_check(dry == 0, "wet all the way (%d dry points)" % dry)
	_check(deep == 0, "wadeable all the way (%d too deep)" % deep)
	_check(still == 0, "the current runs all the way (%d still points)" % still)
	_check(ledges == 0, "no ledge on its banks (%d)" % ledges)
	_check(low_banks == 0, "its banks rise out of the water (%d sunk)" % low_banks)
	var species := {}
	for pond in _fish_ponds(get_first_node_in_group("creek")):
		for s in pond.get("schools"):
			species[s.get("id")] = species.get(s.get("id"), 0) + 1
	print("creek fish: %s" % species)
	_check(species.has(&"grayling") and species.has(&"salmon"), "grayling and salmon live in it")
	print("test_creek: %s" % ("PASS" if _fails == 0 else "%d FAILED" % _fails))
	quit(1 if _fails else 0)


func _fish_ponds(creek: Node) -> Array:
	var out := []
	if creek == null:
		return out
	for stretch in creek.get_children():
		var fish := stretch.get_node_or_null("Fish")
		if fish:
			out.append(fish)
	return out


func _check(ok: bool, what: String) -> void:
	if not ok:
		_fails += 1
	print(("ok   " if ok else "FAIL ") + what)
