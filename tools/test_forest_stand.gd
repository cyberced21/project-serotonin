extends SceneTree
## Headless checks for the Pinewood's stand of trees (plans/pinewood-stand.md): walking through it,
## the trees near you wake (a real tree in place of each copy) and go back to sleep behind you; a
## tree is never both a copy and awake, nor neither.
##   godot --headless --path . -s res://tools/test_forest_stand.gd -- --save-root=user://tmp
## (No game class names: an -s script compiles before the autoloads exist.)

const WAKE_RANGE := 14.0
const SLEEP_RANGE := 20.0
const MAX_AWAKE := 40

var _fails := 0
var player: Node3D
var terrain: Node
var stand: Node3D
var _spawn := Vector3.ZERO


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.get_node("Worlds").call("play_fresh")
	await process_frame
	while get_first_node_in_group("player") == null:
		await process_frame
	player = get_first_node_in_group("player") as Node3D
	terrain = get_first_node_in_group("terrain")
	_spawn = player.global_position
	while get_first_node_in_group("forest_stand") == null:
		await process_frame
	stand = get_first_node_in_group("forest_stand") as Node3D
	while not stand.get("done"):
		await process_frame
	await _frames(10)
	_check(stand.call("size") > 500, "the Pinewood is a stand of hundreds of trees (%d)" % stand.call("size"))
	await _test_walk()
	await _test_remember()
	_finish()


func _check(ok: bool, what: String) -> void:
	if not ok:
		_fails += 1
		print("  FAIL: ", what)


func _finish() -> void:
	print("test_forest_stand: %s" % ("all passed" if _fails == 0 else "%d FAILED" % _fails))
	quit(1 if _fails > 0 else 0)


## Through the middle of the stand and out the other side, a metre at a time.
func _test_walk() -> void:
	var mid := _middle_tree()
	var at: Vector3 = (stand.get("spots") as PackedVector3Array)[mid]
	var bad := 0
	var far_awake := 0
	var most := 0
	for step in range(-60, 61):
		_place(at + Vector3(step, 0, 0))
		await _frames(8)  # (7.5 m/s: a jog)
		bad += _both_or_neither()
		far_awake += _awake_too_far()
		most = maxi(most, stand.call("awake_count"))
		if step == 0:
			await _frames(30)  # (all caught up)
			var missing := 0
			var spots: PackedVector3Array = stand.get("spots")
			for i in spots.size():
				if _flat(spots[i], player.global_position) < WAKE_RANGE - 1.0 and stand.call("awake_tree", i) == null:
					missing += 1
			_check(missing == 0, "standing in the forest, every tree within %d m is awake (%d aren't)" % [WAKE_RANGE, missing])
			var tree: Node3D = stand.call("awake_tree", mid)
			_check(tree != null and tree.is_in_group("gatherable"), "the tree beside you is a real one")
			if tree:
				_check(String(tree.get("save_id")) == String(stand.call("key_of", mid)), "...saved under its key")
				_check(tree.global_position.distance_to(at) < 0.01, "...standing on its spot")
	_check(bad == 0, "no tree was ever both a copy and awake, or neither (%d times)" % bad)
	_check(far_awake == 0, "no idle tree stayed awake past %d m (%d times)" % [SLEEP_RANGE, far_awake])
	_check(most > 0 and most <= MAX_AWAKE, "trees woke, never more than %d at once (%d)" % [MAX_AWAKE, most])
	_place(_spawn)
	await _frames(30)
	_check(_both_or_neither() == 0, "back at the spawn, still no tree both or neither")
	_check(stand.call("awake_count") == 0, "out of the forest, every tree is asleep (%d awake)" % stand.call("awake_count"))


## Fell one tree and half-cut its neighbour, walk away (a stump; the cut saved), save and reload,
## walk back (both as they were), then sleep through to regrowth.
func _test_remember() -> void:
	var felled := _middle_tree()
	var spots: PackedVector3Array = stand.get("spots")
	var cut := _nearest_to(spots[felled], felled)
	var save_game := root.get_node("SaveGame")
	_place(spots[felled] + Vector3(-3, 0, 0))
	await _frames(40)
	var a: Node3D = stand.call("awake_tree", felled)
	var b: Node3D = stand.call("awake_tree", cut)
	_check(a != null and b != null, "both trees woke beside you")
	if a == null or b == null:
		return
	for k in 80:
		if not a.call("is_available"):
			break
		_swing(a)
		await _frames(2)
	_check(not a.call("is_available"), "the tree came down")
	a.call("fast_forward", -600.0)  # (kept felled through the test: a birch regrows in 20 s)
	for k in 3:
		_swing(b)
		await _frames(2)
	var cut_hits: int = b.get("hits_left")
	_check(cut_hits < int(b.get("max_hits")), "the neighbour is half cut (%d hits left)" % cut_hits)
	for k in 1200:  # (the fall plays out)
		if not a.call("is_busy") and not b.call("is_busy"):
			break
		await _frames(1)

	_place(_spawn)
	await _frames(30)
	_check(stand.call("awake_tree", felled) == null and stand.call("is_felled", felled), "walked away, the felled tree sleeps as felled")
	_check(not stand.call("copy_shown", felled), "...its copy not drawn")
	print("  (stump drawn: %s)" % stand.call("has_stump", felled))
	var saved: Dictionary = save_game.call("saved_data", stand.call("node_key", felled))
	_check(saved.has("respawn_left"), "...and saved as felled")
	saved = save_game.call("saved_data", stand.call("node_key", cut))
	_check(int(saved.get("hits_left", -1)) == cut_hits and saved.has("notch"), "the half-cut one saved with its notch")
	var untouched := 0
	for i in stand.call("size"):
		if i != felled and i != cut and save_game.call("has", stand.call("node_key", i)):
			untouched += 1
	_check(untouched == 0, "trees that woke and slept untouched aren't saved (%d are)" % untouched)

	# save, leave the world, come back to it
	save_game.call("save")
	var worlds := root.get_node("Worlds")
	var id: String = worlds.get("current")
	save_game.call("use_file", "")
	worlds.call("play", id)
	await process_frame
	while get_first_node_in_group("player") == null or get_first_node_in_group("forest_stand") == null \
			or not get_first_node_in_group("forest_stand").get("done"):
		await process_frame
	player = get_first_node_in_group("player") as Node3D
	terrain = get_first_node_in_group("terrain")
	stand = get_first_node_in_group("forest_stand") as Node3D
	await _frames(10)
	_check(stand.call("is_felled", felled) and not stand.call("copy_shown", felled), "reloaded, the felled tree is still down")
	_check(stand.call("copy_shown", cut), "...the half-cut one a copy till you come near")

	_place(spots[felled] + Vector3(-3, 0, 0))
	await _frames(40)
	a = stand.call("awake_tree", felled)
	b = stand.call("awake_tree", cut)
	_check(a != null and not a.call("is_available"), "back again, the felled tree wakes felled")
	_check(b != null and int(b.get("hits_left")) == cut_hits and (b.get("_carve") as RefCounted).call("is_started"),
		"...the half-cut one with its notch")
	_check(not stand.call("is_felled", felled) and not stand.call("has_stump", felled), "...and no stump copy left behind")

	_place(_spawn)
	await _frames(30)
	stand.call("fast_forward", 100000.0)  # (a long sleep)
	await _frames(5)
	_check(not stand.call("is_felled", felled) and stand.call("copy_shown", felled), "slept through, it grew back")
	_check(save_game.call("saved_data", stand.call("node_key", felled)).is_empty(), "...and is forgotten by the save")


## The other tree nearest tree `i`.
func _nearest_to(at: Vector3, i: int) -> int:
	var spots: PackedVector3Array = stand.get("spots")
	var best := -1
	for j in spots.size():
		if j != i and (best < 0 or _flat(spots[j], at) < _flat(spots[best], at)):
			best = j
	return best


## A swing at a tree with an axe of its tier (as test_logging_world).
func _swing(tree: Node3D) -> void:
	(root.get_node("Tools").get("tiers") as Dictionary)[&"axe"] = tree.get("tool_tier")
	var dir := (tree.global_position - player.global_position)
	dir.y = 0.0
	dir = -dir.normalized()
	var carve: RefCounted = tree.get("_carve")
	var at := tree.global_position + Vector3.UP * (1.3 if carve.call("is_started") else 1.0) + dir * 0.3
	tree.call("hit", load("res://scripts/hit_info.gd").new(at, dir, tree, at + dir * 1.4))


## The tree nearest the middle of the stand.
func _middle_tree() -> int:
	var spots: PackedVector3Array = stand.get("spots")
	var centre := Vector3.ZERO
	for p in spots:
		centre += p
	centre /= spots.size()
	var best := 0
	for i in spots.size():
		if _flat(spots[i], centre) < _flat(spots[best], centre):
			best = i
	return best


func _both_or_neither() -> int:
	var n := 0
	for i in stand.call("size"):
		if (stand.call("awake_tree", i) != null) == stand.call("copy_shown", i):
			n += 1
	return n


func _awake_too_far() -> int:
	var n := 0
	var spots: PackedVector3Array = stand.get("spots")
	for i in spots.size():
		var tree: Object = stand.call("awake_tree", i)
		# (the stand looks round every 0.25 s: at a jog that's up to 2 m behind, plus the step)
		if tree and not tree.call("is_busy") and _flat(spots[i], player.global_position) > SLEEP_RANGE + 3.0:
			n += 1
	return n


func _place(at: Vector3) -> void:
	var h: float = terrain.get("data").get_height(at)
	at.y = (0.0 if is_nan(h) else h) + 0.1
	player.global_position = at
	player.set("velocity", Vector3.ZERO)


func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _frames(n: int) -> void:
	for i in n:
		await physics_frame
