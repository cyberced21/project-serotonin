extends SceneTree
## Headless checks for the ore walls (OreWall, OreWallRun): what's dug survives a save and reload,
## a panel's veins come out the same from the same seed, and a vein needs its own pick.
## Played on a throwaway save, so the real one is never touched.
##
##     godot --headless --path . -s res://tools/test_ore_wall.gd

const SAVE := "user://test_ore_wall_save.json"

var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var save_game := root.get_node("SaveGame")
	save_game.set("path", SAVE)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
	var world := Node3D.new()
	root.add_child(world)

	# dig some, save, throw the walls away, build them again: the same pieces are gone
	var run := _make_run(world, "a", 11)
	var wall: Node = run.get_node("Panel0")
	wall.call("dig_layers", 2)
	var gone: Array = wall.get("_gone")
	for i in [3, 4, 10]:
		gone[2][i] = true
	var before: Dictionary = wall.call("to_dict")
	_check(int(wall.get("front")) == 2, "two layers dug: the face is layer 3")
	save_game.call("save")
	run.free()
	run = _make_run(world, "a", 11)
	wall = run.get_node("Panel0")
	_check(int(wall.get("front")) == 2, "reloaded: still at layer 3 (got %d)" % wall.get("front"))
	_check(_same(wall.call("to_dict"), before), "reloaded: the same pieces gone")
	_check(run.get_node("Panel1").call("to_dict")["gone"].all(func(l: Array) -> bool: return l.is_empty()),
		"the panel beside it untouched")

	# all the way back: bedrock, and nothing left to swing at
	wall.call("dig_layers", 8)
	_check(not wall.call("is_available"), "dug to bedrock: nothing left to mine")

	# veins: the same seed, the same ore; another seed, other ore
	var twin := _make_run(world, "b", 11)
	var other := _make_run(world, "c", 12)
	var counts := []
	for r in [run, twin, other]:
		var layers := []
		for k in 8:
			layers.append(r.get_node("Panel0").call("ore_count", k))
		counts.append(layers)
	_check(counts[0] == counts[1], "the same seed threads the same veins")
	_check(counts[0] != counts[2], "another seed threads other veins")
	var shallow: Dictionary = counts[0][0]
	_check(shallow.keys().all(func(k: int) -> bool: return k <= 2), "the face holds only copper or coal: %s" % shallow)

	# a vein needs its own pick: find a gold or crystal piece and try it with each
	var tools := root.get_node("Tools")
	var deep: Node = other.get_node("Panel0")
	var found := []
	for k in range(7, -1, -1):
		var kinds: PackedInt32Array = deep.call("_layer_ore", k)
		for i in kinds.size():
			if kinds[i] >= 4:
				found = [k, i]
				break
		if not found.is_empty():
			break
	_check(not found.is_empty(), "a deep layer holds gold or crystal")
	if not found.is_empty():
		deep.call("_rate", found)
		tools.call("set_tier", &"pickaxe", 1)
		_check(not deep.call("can_gather"), "a copper pick can't take gold")
		tools.call("set_tier", &"pickaxe", 2)
		_check(deep.call("can_gather"), "an iron pick can")
		deep.call("_rate", [found[0], kinds_stone(deep, found[0])])
		tools.call("set_tier", &"pickaxe", 0)
		_check(deep.call("can_gather"), "a stone pick takes plain stone")

	world.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
	print("test_ore_wall: %s" % ("all passed" if _failures == 0 else "%d FAILED" % _failures))
	quit(1 if _failures > 0 else 0)


func kinds_stone(wall: Node, k: int) -> int:
	var kinds: PackedInt32Array = wall.call("_layer_ore", k)
	for i in kinds.size():
		if kinds[i] == 0:
			return i
	return 0


## A run of two panels (loaded, not named: a -s script compiles before the autoloads exist).
func _make_run(world: Node3D, id: String, vein_seed: int) -> Node3D:
	var run: Node3D = load("res://scripts/ore_wall_run.gd").new()
	run.name = "Run_" + id
	for i in 2:
		run.get("panels").append(Transform3D(Basis.IDENTITY, Vector3(i * 4.0, 0, 0)))
		run.get("templates").append(i)
		run.get("seeds").append(vein_seed + i)
		run.get("save_ids").append("test_%s_%d" % [id, i])
	run.set("ring", 3)
	run.set("rings", 5)
	world.add_child(run)
	run.call("build")
	return run


## Two to_dict()s alike, whatever order their lists are in (and ints vs floats from JSON).
func _same(a: Dictionary, b: Dictionary) -> bool:
	var norm := func(d: Dictionary) -> Array:
		return d["gone"].map(func(l: Array) -> Array:
			var s := l.map(func(x: Variant) -> int: return int(x))
			s.sort()
			return s)
	return norm.call(a) == norm.call(b)


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failures += 1
		print("  FAIL: ", what)
