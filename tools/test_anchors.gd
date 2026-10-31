extends SceneTree
## Checks the map editor's anchors (plans/map-editor-places.md): the buildings, fixtures and places
## the layout stands where it wants them.
##   - every anchor has a unique id and names a node in main.tscn; LayoutAnchors is Main's first child
##   - applied, each anchored node stands at its anchor, turned to its yaw; applying twice changes nothing
##   - a place carries its own along: moving and turning the mill and the haven moves the mill's
##     wheel sound and the haven's pool, deer track and deer with them, and WorldMap follows
##   godot --headless --path . -s res://tools/test_anchors.gd -- --save-root=user://tool_worlds
## (No game class names: an -s script compiles before the autoloads exist.)

const Anchors := preload("res://scripts/layout_anchors.gd")
const WorldMapC := preload("res://scripts/world_map.gd")
const EPS := 0.01

var failures := PackedStringArray()


func _initialize() -> void:
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	_anchors_whole(main)
	_applied(main)
	main.free()
	_places_carry()
	if failures.is_empty():
		print("test_anchors: PASS")
		quit(0)
	else:
		for f in failures:
			print("FAIL " + f)
		print("test_anchors: %d FAILED" % failures.size())
		quit(1)


func _check(ok: bool, what: String) -> void:
	if not ok:
		failures.append(what)


func _anchors_whole(main: Node) -> void:
	var list: Array = Anchors.anchors()
	_check(list.size() >= 27, "the layout has the 8 buildings, 15 fixtures and 4 places (%d anchors)" % list.size())
	var ids := {}
	for a in list:
		_check(not ids.has(a["id"]), "anchor id %s is unique" % a["id"])
		ids[a["id"]] = true
		_check(main.get_node_or_null(NodePath(String(a["node"]))) is Node3D, "anchor %s's node %s is in main.tscn" % [a["id"], a["node"]])
	_check(main.get_child(0).get_script() == Anchors, "LayoutAnchors is Main's first child (it moves the rest before they're ready)")


func _applied(main: Node) -> void:
	Anchors.apply(main)
	var first := {}
	for a in Anchors.anchors():
		var n := main.get_node(NodePath(String(a["node"]))) as Node3D
		var at := Vector2(n.position.x, n.position.z)
		var want := Vector2(float(a["at"][0]), float(a["at"][1]))
		_check(at.distance_to(want) < EPS, "%s stands at its anchor (%s, wants %s)" % [a["id"], at, want])
		var yaw := rad_to_deg(atan2(n.basis.z.x, n.basis.z.z))
		_check(absf(wrapf(yaw - float(a.get("yaw", 0.0)), -180.0, 180.0)) < 0.05, "%s is turned to its yaw (%.2f, wants %s)" % [a["id"], yaw, a.get("yaw", 0.0)])
		first[a["id"]] = n.transform
	Anchors.apply(main)
	for a in Anchors.anchors():
		var n := main.get_node(NodePath(String(a["node"]))) as Node3D
		_check(n.transform.is_equal_approx(first[a["id"]]), "applying %s again changes nothing" % a["id"])


## Moves the mill 60 m and turns it a quarter, turns the haven half round, and checks their own come along.
func _places_carry() -> void:
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	Anchors.apply(main)
	var mill := main.get_node("Places/Watermill") as Node3D
	var wheel := main.get_node("Places/Watermill/MillWheel") as Node3D
	var haven := main.get_node("Places/Haven") as Node3D
	var pool := main.get_node("Places/Haven/HavenPool") as Node3D
	var deer := main.get_node("Places/Haven/Deer4") as Node3D
	var stone := main.get_node("Places/Haven/DeerTrack/Stone1") as Node3D
	var off_mill := _global(wheel) - _global(mill)
	var off_pool := _global(pool) - _global(haven)
	var off_deer := _global(deer) - _global(haven)
	var off_stone := _global(stone) - _global(haven)
	_check(Vector2(off_pool.x, off_pool.z).distance_to(WorldMapC.haven_pool_center() - WorldMapC.haven_center()) < EPS,
			"WorldMap's haven pool is the scene's (%s)" % off_pool)
	var saved: Array = Anchors._anchors.duplicate(true)
	var moved: Array = Anchors._anchors.duplicate(true)
	var mill_at := Vector2.ZERO
	for a in moved:
		if a["id"] == "watermill":
			a["at"] = [float(a["at"][0]) + 60.0, float(a["at"][1])]
			a["yaw"] = float(a["yaw"]) + 90.0
			mill_at = Vector2(a["at"][0], a["at"][1])
		elif a["id"] == "haven":
			a["yaw"] = float(a["yaw"]) + 180.0
	Anchors._anchors = moved
	Anchors.apply(main)
	_check(Vector2(mill.position.x, mill.position.z).distance_to(mill_at) < EPS, "the mill moved 60 m")
	_check((_global(wheel) - _global(mill)).is_equal_approx(off_mill.rotated(Vector3.UP, PI / 2.0)), "the mill's wheel sound turned with it")
	_check((_global(pool) - _global(haven)).is_equal_approx(off_pool.rotated(Vector3.UP, PI)), "the haven's pool turned with it")
	_check((_global(deer) - _global(haven)).is_equal_approx(off_deer.rotated(Vector3.UP, PI)), "the haven's deer turned with it")
	_check((_global(stone) - _global(haven)).is_equal_approx(off_stone.rotated(Vector3.UP, PI)), "the deer track turned with it")
	var p := _global(pool)
	_check(Vector2(p.x, p.z).distance_to(WorldMapC.haven_pool_center()) < EPS, "WorldMap's haven pool follows the turn (%s vs %s)" % [Vector2(p.x, p.z), WorldMapC.haven_pool_center()])
	_check(WorldMapC.site(&"watermill").distance_to(mill_at) < EPS, "WorldMap's mill follows the move")
	Anchors._anchors = saved
	main.free()


## A node's place on the map, from the root down (the scene isn't in a tree).
func _global(n: Node3D) -> Vector3:
	var t := n.transform
	var p := n.get_parent()
	while p is Node3D:
		t = (p as Node3D).transform * t
		p = p.get_parent()
	return t.origin
