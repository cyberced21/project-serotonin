extends SceneTree
## Checks the fireflies (scripts/autoload/fireflies.gd) and the cricket spots (Ambience): none by
## day; in the evening and before midnight, a few small clusters tied to world spots (shores, tree
## edges) that stay put when you walk away; gone by small hours. Crickets sing from spots too,
## heard through a few positional voices rather than everywhere at once.
##   godot --headless --path . -s res://tools/test_fireflies.gd -- --save-root=user://tool_worlds

var _fails := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.get_node("Worlds").call("play_fresh")
	await process_frame
	while get_first_node_in_group("player") == null:
		await process_frame
	var day_night := root.get_node("DayNight")
	day_night.set("frozen", true)
	var flies := root.get_node("Fireflies")
	var ambience := root.get_node("Ambience")
	var mm := (flies.get_child(0) as MultiMeshInstance3D)
	var player := get_first_node_in_group("player") as Node3D
	var terrain := get_first_node_in_group("terrain") as Terrain3D
	var radius: float = flies.get("CLUSTER_RADIUS")
	var spots_before := PackedVector3Array()
	for t in [0.5, 0.86, 0.95, 0.02, 0.1]:
		day_night.set("time", t)
		for i in 30:
			await process_frame
		var amount: float = flies.call("amount")
		var spots: PackedVector3Array = flies.call("spots")
		var shown := mm.multimesh.visible_instance_count if mm.visible else 0
		var stray := 0
		var pos: PackedVector3Array = flies.get("_pos")
		var home: PackedVector3Array = flies.get("_home")
		for i in pos.size():
			var p := pos[i]
			var off := Vector2(p.x - home[i].x, p.z - home[i].z).length()
			var ground := terrain.data.get_height(p)
			if off > radius + 3.0 or (not is_nan(ground) and (p.y < ground + 0.35 or p.y > ground + 2.1)):
				stray += 1
		print("time %.2f: amount %.2f, %d clusters, %d shown, %d strays" % [t, amount, spots.size(), shown, stray])
		if t == 0.5 or t == 0.1:
			_check(not mm.visible, "none out at time %.2f" % t)
		else:
			_check(mm.visible and amount > 0.5, "out at time %.2f" % t)
			_check(spots.size() >= 10, "clusters at spots round the world (%d)" % spots.size())
			_check(stray == 0, "every firefly near its cluster's spot, over the ground (time %.2f)" % t)
			if spots_before.is_empty():
				spots_before = spots
	# walking away doesn't move them
	day_night.set("time", 0.95)
	player.global_position += Vector3(60, 0, 0)
	for i in 30:
		await process_frame
	_check(flies.call("spots") == spots_before, "the clusters stay where they are when you walk away")
	var near := 0
	for s in spots_before:
		if Vector2(s.x - player.global_position.x, s.z - player.global_position.z).length() < 70.0:
			near += 1
	print("clusters within 70 m: %d; shown %d" % [near, mm.multimesh.visible_instance_count])
	_check(mm.multimesh.visible_instance_count <= near * 7, "only the clusters near you are drawn")
	# crickets
	var crickets: PackedVector3Array = ambience.get("_crickets")
	for i in 120:
		await process_frame
	var singing: int = ambience.call("crickets_near", player.global_position)
	var voices: Array = ambience.get("_voices")
	var loud := 0
	for v in voices:
		if float(v.get("level")) > 0.05:
			loud += 1
	print("cricket spots %d, singing near you %d, voices playing %d" % [crickets.size(), singing, loud])
	_check(crickets.size() >= 10, "crickets have spots round the world")
	_check(loud <= voices.size() and (singing == 0 or loud > 0), "the nearest singing spots get a voice")
	print("test_fireflies: %s" % ("PASS" if _fails == 0 else "%d FAILED" % _fails))
	quit(1 if _fails else 0)


func _check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		_fails += 1
