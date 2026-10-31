extends SceneTree
## Headless checks for logging in a fresh Hearthvale (plans/logging.md): each tree, set down in a
## clearing and chopped plainly from one side through ResourceNode.hit(), falls on its own swing
## count (15 / 20 / 25) because its wood gave out; layers break away when the axe is pulled out;
## it falls toward its notch but never onto you; chopping from both sides still brings it down.
##   godot --headless --path . -s res://tools/test_logging_world.gd -- --save-root=user://tmp
## (No game class names: an -s script compiles before the autoloads exist.)

const TREES := ["res://scenes/tree.tscn", "res://scenes/birch_tree.tscn", "res://scenes/oak_tree.tscn",
	"res://scenes/pine_tree.tscn"]

var _fails := 0
var _hit_info: GDScript = load("res://scripts/hit_info.gd")
var _spot := Vector3.ZERO
var _planted := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.get_node("Worlds").call("play_fresh")
	await process_frame
	while get_first_node_in_group("player") == null:
		await process_frame
	for i in 10:
		await physics_frame
	var player := get_first_node_in_group("player") as Node3D
	_spot = player.global_position
	for path in TREES:
		await _test_plain(path)
	await _test_both_sides("res://scenes/tree.tscn")
	await _test_knot("res://scenes/tree.tscn")
	_finish()


func _check(ok: bool, what: String) -> void:
	if not ok:
		_fails += 1
		print("  FAIL: ", what)


func _finish() -> void:
	print("test_logging_world: %s" % ("all passed" if _fails == 0 else "%d FAILED" % _fails))
	quit(1 if _fails > 0 else 0)


## A tree of `path` set down by the player, workable with a level-1 axe of its tier.
func _plant(path: String) -> Node3D:
	var tree := (load(path) as PackedScene).instantiate() as Node3D
	tree.set("required_level", 0)
	tree.name = "LoggingTest%d" % _planted  # (its own name: a node takes up a saved node's state by name)
	_planted += 1
	get_first_node_in_group("player").get_parent().add_child(tree)
	tree.global_position = _spot + Vector3(40, 0, 0)
	(root.get_node("Tools").get("tiers") as Dictionary)[&"axe"] = tree.get("tool_tier")  # (no better axe than it needs)
	await physics_frame
	return tree


## A planted tree with its knot out of the way (a plain chop that happens across it would crack it).
func _plant_plain(path: String) -> Node3D:
	var tree := await _plant(path)
	(tree.get("_knot") as Node3D).visible = false
	return tree


## A swing from `dir`: the first at the notch's height, the rest a little above its mouth (plain,
## not clean cuts: those are aimed into it).
func _swing(tree: Node3D, dir: Vector3) -> Object:
	var carve: RefCounted = tree.get("_carve")
	var at := tree.global_position + Vector3.UP * (1.3 if carve.is_started() else 1.0) + dir * 0.3
	var info: Object = _hit_info.new(at, dir, tree, at + dir * 1.4)
	tree.call("hit", info)
	return info


func _test_plain(path: String) -> void:
	var tree := await _plant_plain(path)
	var name := path.get_file().get_basename()
	var max_hits: int = tree.get("max_hits")
	var dir := Vector3(1, 0, 0.2).normalized()
	var parent := tree.get_parent()
	var swings := 0
	var slabs := 0
	var falls_at := -1
	while int(tree.get("hits_left")) > 0 and swings < 3 * max_hits:
		var info := _swing(tree, dir)
		swings += 1
		var popped := (tree.get("_popped") as PackedInt32Array).duplicate()
		if int(tree.get("hits_left")) > 0:
			var bodies := parent.get_children().filter(func(n: Node) -> bool: return n is RigidBody3D).size()
			tree.call("pull", info)
			var after := parent.get_children().filter(func(n: Node) -> bool: return n is RigidBody3D).size()
			if not popped.is_empty() and popped[popped.size() - 1] >= 2:
				slabs += 1
				_check(after > bodies, "%s: a layer coming off throws a slab" % name)
			_check((tree.get("_popped") as PackedInt32Array).is_empty(), "%s: the pull clears the popped layers" % name)
		else:
			falls_at = swings
			var fall: Vector3 = tree.call("_fall_direction", info)
			var toward_you := dir
			_check(fall.dot(toward_you) <= cos(deg_to_rad(59.0)), "%s: it never falls onto you (%.0f°)" % [name, rad_to_deg(fall.angle_to(toward_you))])
	var carve: RefCounted = tree.get("_carve")
	_check(falls_at == max_hits, "%s: a plain chop fells it on swing %d (%d)" % [name, max_hits, falls_at])
	_check(carve.stability() <= float(tree.get("_fall_at")), "%s: it fell because its wood gave out (%.2f)" % [name, carve.stability()])
	_check(slabs >= 3, "%s: wood layers came off as slabs (%d)" % [name, slabs])
	print("  %s: felled on swing %d of %d, stability %.2f (falls at %.2f)" % [name, falls_at, max_hits, carve.stability(), tree.get("_fall_at")])
	await _clear(tree)


## Notched from one side, then cut from the other (a back cut): it still comes down, and falls toward
## the notch, away from the second side.
func _test_both_sides(path: String) -> void:
	var tree := await _plant_plain(path)
	var max_hits: int = tree.get("max_hits")
	var dir := Vector3(0, 0, 1)
	for i in max_hits / 2:
		_swing(tree, dir)
	var swings := max_hits / 2
	var info: Object = null
	while int(tree.get("hits_left")) > 0 and swings < 4 * max_hits:
		info = _swing(tree, -dir)
		swings += 1
	_check(int(tree.get("hits_left")) == 0, "chopped from both sides, it still falls (%d swings)" % swings)
	if info:
		var fall: Vector3 = tree.call("_fall_direction", info)
		_check(fall.dot(dir) > 0.7, "a back-cut tree falls toward its notch (%s)" % fall)
	print("  both sides: felled in %d swings" % swings)
	await _clear(tree)


## Every tree grows a knot; struck, a crack takes several layers off at once and the knot's gone
## (and saved gone); on another tree, the bark stripped round a notch beside it takes it away.
func _test_knot(path: String) -> void:
	var tree := await _plant(path)
	var knot: Node3D = tree.get("_knot")
	_check(knot != null and knot.visible, "a fresh tree has a knot")
	if knot == null:
		return
	var out := knot.global_position - tree.global_position
	out.y = 0.0
	out = out.normalized()
	var info: Object = _hit_info.new(knot.global_position, out, tree, knot.global_position + out * 1.4)
	tree.call("hit", info)
	var popped: PackedInt32Array = (tree.get("_popped") as PackedInt32Array).duplicate()
	var carve: RefCounted = tree.get("_carve")
	_check(not knot.visible and carve.knot_gone, "the struck knot is gone")
	_check(popped.size() >= 3, "a struck knot cracks several layers off at once (%s)" % popped)
	var saved: Dictionary = carve.to_dict()
	_check(saved.has("knot") and saved["knot"][2] == true, "the knot's saved gone")
	print("  knot: one strike took layers %s, stability %.2f" % [popped, carve.stability()])
	await _clear(tree)

	tree = await _plant(path)
	knot = tree.get("_knot")
	carve = tree.get("_carve")
	out = knot.global_position - tree.global_position
	out.y = 0.0
	var beside := out.normalized().rotated(Vector3.UP, deg_to_rad(35.0))
	var y: float = carve.knot_y
	var swings := 0
	while knot.visible and swings < 6:
		var at := tree.global_position + Vector3.UP * y + beside * 0.3
		tree.call("hit", _hit_info.new(at, beside, tree, at + beside * 1.4 + Vector3.UP * 0.4))  # (aimed down past it)
		swings += 1
	_check(not knot.visible and carve.knot_gone, "a notch cut beside the knot strips it away (%d swings)" % swings)
	await _clear(tree)


func _clear(tree: Node3D) -> void:
	tree.queue_free()
	await physics_frame
