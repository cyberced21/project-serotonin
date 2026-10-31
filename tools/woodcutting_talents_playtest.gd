extends SceneTree
## Checks the woodcutting talents (plans/levels.md) in a real world, headless: it strikes trees
## directly (ResourceNode.hit with a HitInfo from a spot beside the trunk), each talent alone,
## and checks what it should do: chain cut's growing extra hits, a back cut's four, a power
## swing's four, heartwood's knot and log, dominoes' crush, grove keeper's quick fine regrowth,
## momentum's count, old growth's shimmer and toughness.
##   godot --headless --path . -s res://tools/woodcutting_talents_playtest.gd -- --save-root=user://wc_talents
## (No game class names here: an -s script compiles before the autoloads exist.)

const HitInfo := preload("res://scripts/hit_info.gd")

var _fails := 0
var skills: Node
var talents: Object
var _used := {}  # trees already struck (each check takes a fresh one)


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.get_node("Worlds").call("play_fresh")
	await process_frame
	while get_first_node_in_group("player") == null:
		await process_frame
	var cards := get_first_node_in_group("talent_cards")
	if cards:
		cards.queue_free()
	var kinds := {}
	for n in get_nodes_in_group("gatherable"):
		if n.get("skill") == &"woodcutting":
			var k := "tier %d, %d hits, carve %s, req %d" % [n.get("tool_tier"), n.get("max_hits"), n.get("_carve") != null, n.get("required_level")]
			kinds[k] = kinds.get(k, 0) + 1
	print("  trees: %s" % kinds)
	skills = root.get_node("Skills")
	talents = skills.get("talents")
	skills.call("set_level", &"woodcutting", 40)
	var tools := root.get_node("Tools")
	tools.call("set_tier", &"axe", 2)  # (iron on iron trees: one cut a hit, so the counts below are exact)
	await _chain_cut()
	await _back_cut()
	await _power_swing()
	await _heartwood()
	await _dominoes()
	await _grove_keeper()
	_momentum()
	_old_growth()
	print("woodcutting_talents_playtest: %s" % ("PASS" if _fails == 0 else "%d FAILED" % _fails))
	quit(1 if _fails else 0)


func _only(id: StringName) -> void:
	talents.get("picks").clear()
	if id != &"":
		talents.get("picks")[&"woodcutting"] = {talents.get("defs")[id].milestone: id}


## A fresh iron-axe tree that's not old growth, with plenty of hits.
func _tree():
	for n in get_nodes_in_group("gatherable"):
		if n.get("skill") == &"woodcutting" and n.call("is_available") and n.call("can_gather") \
				and n.get("_carve") != null and not _used.has(n) and n.get("tool_tier") == 2 \
				and not n.call("_old_growth_active") and n.get("max_hits") >= 8:
			_used[n] = true
			return n
	return null


## Strikes `tree` from the side `side` (world, horizontal), aimed into the notch's mouth if
## there's one that way (a clean cut once it's deep), else at the trunk. Returns hits taken.
func _strike(tree, side: Vector3, power := false, at := Vector3.INF) -> int:
	var trunk: Node3D = tree.get("_trunk")
	var carve = tree.get("_carve")
	var from: Vector3 = trunk.global_position + Vector3.UP * 1.5 + side * 1.6
	var point := at
	if point == Vector3.INF:
		var dir: Vector3 = trunk.global_transform.affine_inverse().basis * (from - trunk.global_position)
		dir.y = 0.0
		if carve.call("is_started"):
			point = trunk.global_transform * (carve.call("bite_point", dir) + dir.normalized() * carve.call("depth_toward", dir) * 0.5)
		else:
			point = trunk.global_position + Vector3.UP * 1.1 + side * 0.25
	var info = HitInfo.new(point, side, tree, from)
	info.power = power
	var before: int = tree.get("hits_left")
	tree.set("_last_hit_msec", 0)
	tree.call("hit", info)
	await process_frame
	return before - int(tree.get("hits_left"))


func _chain_cut() -> void:
	_only(&"chain_cut")
	var tree = _tree()
	var took: Array[int] = []
	for i in 12:
		took.append(await _strike(tree, Vector3.RIGHT))
	print("  chain cut: hits taken per swing %s" % [took])
	var first_clean := took.find(2)  # (a clean cut alone takes 2; the run then adds +1, +2, +3)
	_check(first_clean >= 0 and took[first_clean + 1] == 3 and took[first_clean + 2] == 4,
		"chain cut: a run of clean cuts takes more and more")


func _back_cut() -> void:
	_only(&"back_cut")
	var tree = _tree()
	for i in 8:  # (the notch has to be a quarter deep first)
		await _strike(tree, Vector3.RIGHT)
	var plain := await _strike(tree, Vector3.FORWARD)  # round the side: not a back cut
	var back := await _strike(tree, Vector3.LEFT)
	print("  back cut: from the side %d, from the back %d" % [plain, back])
	_check(back >= plain * 4, "back cut: a hit opposite the notch counts four times")


func _power_swing() -> void:
	_only(&"power_swing")
	var tree = _tree()
	var plain := await _strike(tree, Vector3.RIGHT)
	var power := await _strike(tree, Vector3.FORWARD, true)
	print("  power swing: plain %d, charged %d" % [plain, power])
	_check(power >= 4, "power swing: a charged swing counts four")
	_only(&"")
	var tree2 = _tree()
	_check(await _strike(tree2, Vector3.RIGHT, true) == 1, "power swing: without the talent a charge is just a swing")


func _heartwood() -> void:
	_only(&"heartwood")
	var tree = _tree()
	var knot: Node3D = tree.get("_knot")
	var glow: Node3D = tree.get("_knot_glow")
	_check(knot != null and knot.visible, "heartwood: the tree has its knot")
	_check(glow != null and glow.visible, "heartwood: the knot glows")
	if knot:
		var took := await _strike(tree, Vector3.RIGHT, false, knot.global_position)
		var bonus: Array = tree.get("_bonus_items")
		print("  heartwood: the knot took %d" % took)
		_check(&"heartwood" in bonus and not knot.visible, "heartwood: hitting the knot gives a heartwood log")


func _dominoes() -> void:
	_only(&"dominoes")
	var tree = _tree()
	var before: int = tree.get("hits_left")
	tree.call("crush", Vector3.RIGHT, tree.global_position)
	var took: int = before - int(tree.get("hits_left"))
	print("  dominoes: a trunk landing took %d of %d" % [took, tree.get("max_hits")])
	_check(took >= int(tree.get("max_hits") * 0.55), "dominoes: a landing trunk takes most of a tree's hits")


func _grove_keeper() -> void:
	_only(&"grove_keeper")
	var tree = _tree()
	var full: float = tree.get("respawn_time") * maxf(1.0 - root.get_node("Village").call("stat", &"rock_regrow") * 0.0, 0.1)
	var guard := 0
	while tree.get("hits_left") > 0 and guard < 80:
		await _strike(tree, Vector3.RIGHT)
		guard += 1
	var timer = tree.get("_respawn_timer")
	_check(timer != null and timer.time_left <= full / 1.3 + 0.5, "grove keeper: regrows faster")
	_check(tree.get("_fine_next"), "grove keeper: and grows back fine-grained")


func _momentum() -> void:
	_only(&"momentum")
	var player := get_first_node_in_group("player")
	player.set("_momentum", 0)
	player.set("_since_felled", INF)
	player.call("note_felled")
	player.call("note_felled")
	player.call("note_felled")
	_check(player.get("_momentum") == 2, "momentum: three trees in a quick run make two stacks")


func _old_growth() -> void:
	var ancient = null
	var trees := 0
	for n in get_nodes_in_group("gatherable"):
		if n.get("skill") == &"woodcutting":
			trees += 1
			if ancient == null and absi(hash(String(n.get("save_id")))) % 30 == 0:
				ancient = n
	print("  old growth: %s among %d trees" % ["one" if ancient else "none", trees])
	_check(ancient != null, "old growth: an ancient tree in the world")
	if ancient == null:
		return
	_only(&"")
	_check(not ancient.call("_old_growth_active"), "old growth: an ordinary tree without the talent")
	_only(&"old_growth")
	ancient.call("_refresh_old_growth")  # (picking it in play does this: Talents.changed)
	_check(ancient.call("_old_growth_active"), "old growth: ancient with it")
	var surfaces: Array = ancient.get("_surfaces")
	var c = surfaces[0].get_instance_shader_parameter("theme_c") if not surfaces.is_empty() else null
	_check(c is Vector4 and c.w >= 0.79, "old growth: it shimmers (%s)" % [c])


func _check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		_fails += 1
