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
