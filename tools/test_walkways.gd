extends SceneTree
## Checks how the map editor's walkway lines become the villagers' network (VillagePaths.graph,
## plans/map-editor-places.md, phase 2), on made-up lines and on the layout's own:
##   - corners within JOIN are one point; a line's end landing on another's leg splits it there
##   - a door far from every walkway gets a point on the nearest leg; one already reached doesn't
##   - the layout's walkways are one network (every point reaches every other), with a stroll ring
##   godot --headless --path . -s res://tools/test_walkways.gd
## (No game class names: an -s script compiles before the autoloads exist.)

const Paths := preload("res://scripts/village_paths.gd")

var failures := PackedStringArray()


func _initialize() -> void:
	_joins()
	_doors()
	_layout()
	if failures.is_empty():
		print("test_walkways: PASS")
		quit(0)
	else:
		for f in failures:
			print("FAIL " + f)
		print("test_walkways: %d FAILED" % failures.size())
		quit(1)


func _check(ok: bool, what: String) -> void:
	if not ok:
		failures.append(what)


func _line(pts: Array) -> Dictionary:
	return {"type": "walkway", "points": pts}


func _has(g: Dictionary, a: Vector2, b: Vector2) -> bool:
	var pts: PackedVector2Array = g["points"]
	for l in g["links"]:
		var p := pts[l[0]]
		var q := pts[l[1]]
		if (p.distance_to(a) < 0.01 and q.distance_to(b) < 0.01) or (p.distance_to(b) < 0.01 and q.distance_to(a) < 0.01):
			return true
	return false


func _joins() -> void:
	# two lines sharing a corner (0.3 m apart): one point
	var g := Paths.graph([_line([[0, 0], [10, 0]]), _line([[10.3, 0], [10, 10]])], PackedVector2Array())
	_check((g["points"] as PackedVector2Array).size() == 3, "corners 0.3 m apart are one point (%d points)" % (g["points"] as PackedVector2Array).size())
	# a T: a line ending 0.4 m off the middle of another's leg splits it
	g = Paths.graph([_line([[0, 0], [20, 0]]), _line([[10, 10], [10, 0.4]])], PackedVector2Array())
	_check(not _has(g, Vector2(0, 0), Vector2(20, 0)), "a T splits the leg it lands on")
	_check(_has(g, Vector2(0, 0), Vector2(10, 0.4)) and _has(g, Vector2(10, 0.4), Vector2(20, 0)), "...into two legs through the T's end")
	# lines that only cross aren't joined (no corner there)
	g = Paths.graph([_line([[0, 0], [20, 0]]), _line([[10, -10], [10, 10]])], PackedVector2Array())
	_check((g["links"] as Array).size() == 2, "lines that only cross stay apart (%d links)" % (g["links"] as Array).size())


func _doors() -> void:
	var lines := [_line([[0, 0], [20, 0]])]
	var g := Paths.graph(lines, PackedVector2Array([Vector2(8, 6)]))
	_check(_has(g, Vector2(0, 0), Vector2(8, 0)) and _has(g, Vector2(8, 0), Vector2(20, 0)),
			"a door 6 m off a walkway gets a point on it where it passes closest")
	g = Paths.graph(lines, PackedVector2Array([Vector2(22.0, 2.0)]))
	_check((g["points"] as PackedVector2Array).size() == 2, "a door 3 m from a walkway's end needs nothing more")


func _layout() -> void:
	var walks: Array = Paths.walkways()
	_check(walks.size() > 0, "the layout has walkways")
	var ring := false
	for l in walks:
		if l.get("stroll", false):
			ring = (l["points"] as Array).size() >= 4
	_check(ring, "one walkway is the stroll round the green")
	var g := Paths.graph(walks, PackedVector2Array())
	var pts: PackedVector2Array = g["points"]
	var astar := AStar2D.new()
	for i in pts.size():
		astar.add_point(i, pts[i])
	for l in g["links"]:
		astar.connect_points(l[0], l[1])
	var cut := 0
	for i in range(1, pts.size()):
		if astar.get_id_path(0, i).is_empty():
			cut += 1
	_check(cut == 0, "every walkway point reaches every other (%d cut off)" % cut)
