extends SceneTree
## Checks that the village's spots go with what they belong to (plans/map-editor-places.md, phase 3),
## in a world where your home, the woodcutter's lodge and the green are turned a quarter and Rosa's
## bakery is moved 20 m (the layout's anchors, changed before the world loads):
##   - the kennel, its door (where the dog sleeps) and the dog's things stay by your home's door
##   - Rosa's terrace stays against her bakery
##   - the noticeboard and the market stall turn round the green's middle, as do the green's
##     benches, lamps and the spots villagers come to it for
##   - a building's Square and Bench spots are the green's (they don't move with the building),
##     its work spots turn with it
##   godot --headless --path . -s res://tools/test_green.gd -- --save-root=user://tool_worlds
## (No game class names: an -s script compiles before the autoloads exist.)

const Anchors := preload("res://scripts/layout_anchors.gd")
const EPS := 0.05

var _fails := 0
var _before := {}  # anchor id -> its anchor as the layout has it
var _k := {}  # VillageDecor's constants (read off the running one: its script needs the autoloads)


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var list: Array = Anchors.anchors().duplicate(true)
	for a in list:
		_before[a["id"]] = a.duplicate(true)
		match String(a["id"]):
			"home", "woodcutter", "green":
				a["yaw"] = float(a["yaw"]) + 90.0
			"baker":
				a["at"] = [float(a["at"][0]) + 20.0, float(a["at"][1])]
	Anchors._anchors = list
	root.get_node("Worlds").call("play_fresh")
	await process_frame
	while get_first_node_in_group("player") == null:
		await process_frame
	var projects := root.get_node("Projects")
	for id in [&"kennel", &"kennel_porch", &"terrace", &"benches"]:
		projects.call("set_done", id, true)
	for i in 10:
		await process_frame
	var decor := get_first_node_in_group("village_decor") as Node3D
	var green := root.get_node("Main/Village/Green") as Node3D if root.has_node("Main/Village/Green") else _find("Green")
	_check(decor != null and green != null, "the village has its decor and its green")
	if decor and green:
		_k = decor.get_script().get_script_constant_map()
		_green(decor, green)
		_owned(decor)
		_spots(green)
	print("test_green: %s" % ("PASS" if _fails == 0 else "%d FAILED" % _fails))
	quit(1 if _fails else 0)


func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		_fails += 1


func _find(n: String) -> Node:
	return root.find_child(n, true, false)


func _building(id: StringName) -> Node3D:
	for b in get_nodes_in_group("building"):
		if b.get("def").get("id") == id:
			return b
	return null


func _flat(p: Vector3) -> Vector2:
	return Vector2(p.x, p.z)


## Where green offset `o` lands with the green turned a quarter (a +Y turn, as LayoutAnchors does it).
func _turned(center: Vector2, o: Vector2) -> Vector2:
	var w := Vector3(o.x, 0.0, o.y).rotated(Vector3.UP, PI / 2.0)
	return center + Vector2(w.x, w.z)


func _green(decor: Node3D, green: Node3D) -> void:
	var c := _flat(green.global_position)
	_check(_flat(green.global_position).distance_to(Vector2(128, 128)) < EPS, "the green stays where it is (only turned)")
	_check(absf(wrapf(green.global_rotation.y - PI / 2.0, -PI, PI)) < 0.01, "...turned a quarter")
	var board := decor.get("board") as Node3D
	var want: Vector2 = _turned(c, _k["NOTICEBOARD"][0])
	_check(board and _flat(board.global_position).distance_to(want) < EPS, "the noticeboard turned round the green (%s, wants %s)" % [_flat(board.global_position) if board else null, want])
	var bench_a := green.get_node_or_null("BenchA") as Node3D
	_check(bench_a and _flat(bench_a.global_position).distance_to(_turned(c, Vector2(108, 134) - Vector2(128, 128))) < EPS, "the green's bench turned with it")
	var benches: Array = decor.call("props_of", &"benches")
	_check(benches.size() == 2 and _flat((benches[0] as Node3D).global_position).distance_to(_turned(c, _k["PROPS"][&"benches"][0][1])) < EPS,
			"the benches project's benches turned round it")


func _owned(decor: Node3D) -> void:
	var home := _building(&"home")
	var kennel: Array = decor.call("props_of", &"kennel")
	_check(kennel.size() == 1, "the kennel is built")
	if kennel.size() == 1:
		var local := home.global_transform.affine_inverse() * (kennel[0] as Node3D).global_position
		_check(Vector2(local.x, local.z).distance_to(_k["PROPS"][&"kennel"][0][1]) < EPS, "the kennel stays by your turned home's door (%s)" % Vector2(local.x, local.z))
		var face := wrapf((kennel[0] as Node3D).global_rotation.y - home.global_rotation.y, -PI, PI)
		_check(absf(face) < 0.01, "...facing out the way your home does")
	var door: Variant = decor.call("kennel_door")
	_check(door is Transform3D, "the dog has a kennel door")
	if door is Transform3D:
		var local := home.global_transform.affine_inverse() * (door as Transform3D).origin
		_check(Vector2(local.x, local.z).distance_to(_k["KENNEL_DOOR"][0]) < EPS, "...by your home")
	var bowl: Array = decor.call("props_of", &"kennel_porch")
	_check(bowl.size() == 3, "the dog's porch, bowl and blanket are out")
	var baker := _building(&"baker_cottage")
	var terrace: Array = decor.call("props_of", &"terrace")
	_check(terrace.size() == 1, "Rosa's terrace is built")
	if terrace.size() == 1:
		var local := baker.global_transform.affine_inverse() * (terrace[0] as Node3D).global_position
		_check(Vector2(local.x, local.z).distance_to(_k["PROPS"][&"terrace"][0][1]) < EPS, "...against her moved bakery (%s)" % Vector2(local.x, local.z))


func _spots(green: Node3D) -> void:
	var baker := _building(&"baker_cottage")
	var square := baker.call("spot", "Square") as Node3D
	_check(square != null and square.get_parent() == green, "Rosa's Square spot is the green's")
	var c := _flat(green.global_position)
	if square:
		var was := Vector2(136.85, 144.82) - Vector2(128, 128)
		_check(_flat(square.global_position).distance_to(_turned(c, was)) < EPS, "...on the green (turned with it), not 20 m off with her bakery")
	var wc := _building(&"woodcutter")
	var bench := wc.call("spot", "Bench") as Node3D
	_check(bench != null and bench.is_in_group("seat"), "the woodcutter's bench is the green's, and a seat")
	var work := wc.call("spot", "Work1") as Node3D
	var a: Dictionary = _before["woodcutter"]
	if work:
		var local := wc.global_transform.affine_inverse() * work.global_position
		var t := Transform3D(Basis(Vector3.UP, deg_to_rad(float(a["yaw"]))), Vector3(float(a["at"][0]), 0.0, float(a["at"][1])))
		var then := t * local  # where the work spot stood before the turn
		_check(_flat(then).distance_to(_flat(work.global_position)) > 0.5, "the woodcutter's work spot turned with his lodge")
