extends SceneTree
## Checks the map editor's land shaping (plans/terrain-editing.md): runs the terrain generator as a
## dry run (it writes nothing) on a copy of the layout with a river drawn down into the lake, a
## pond dug on open ground, another drawn as an outline, and the lake deepened, then reads what it
## did:
##   - the river's bed is under the water all the way down its middle, about as deep as it asked
##   - each pond is dug about as deep as it asked, the lake too
##   - a patch of Frostpeak's flank smoothed comes out much less bumpy
##   godot --headless --path . -s res://tools/test_terrain_shapes.gd
## Takes about a minute (one terrain run). (No game class names: an -s script compiles before the
## autoloads exist.)

const LAYOUT := "res://data/layout/hearthvale.json"
const SHAPED := "user://test_terrain_shapes_layout.json"
const REPORT := "user://test_terrain_shapes_report.json"
## The shapes drawn: a river from the hills west of the lake into it, a pond and an outlined one.
const SHAPES := [
	{"id": "test_river", "type": "river", "points": [[-70, 262], [-40, 292], [-8, 318], [26, 336]], "width": 5.0, "depth": 0.9},
	{"id": "test_pond", "type": "pond", "shape": "circle", "center": [-30, 210], "radius": 9.0, "depth": 1.1},
	{"id": "test_outline", "type": "pond", "shape": "polygon", "points": [[176, 290], [204, 286], [214, 306], [196, 322], [174, 312]], "depth": 1.0},
	{"id": "test_smooth", "type": "smooth", "shape": "circle", "center": [-80, -42], "radius": 16.0, "strength": 6.0, "soft": 6.0},
]
## The lake, deepened to this.
const LAKE_DEPTH := 1.8

var failures := PackedStringArray()


func _initialize() -> void:
	var layout: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(LAYOUT))
	layout["terrain"].append_array(SHAPES.duplicate(true))
	for s in layout["terrain"]:
		if s["id"] == "lake":
			s["depth"] = LAKE_DEPTH
	var f := FileAccess.open(SHAPED, FileAccess.WRITE)
	f.store_string(JSON.stringify(layout))
	f.close()
	if FileAccess.file_exists(REPORT):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(REPORT))
	var out := []
	var code := OS.execute(OS.get_executable_path(), ["--headless", "--path", ProjectSettings.globalize_path("res://"),
			"-s", "res://tools/generate_test_terrain.gd", "--", "--dry-run",
			"--layout=" + ProjectSettings.globalize_path(SHAPED), "--report=" + ProjectSettings.globalize_path(REPORT)], out, true)
	_check(code == 0, "the terrain generator ran (exit %d)" % code)
	if code != 0:
		print(out[0] if not out.is_empty() else "")
	var report: Variant = JSON.parse_string(FileAccess.get_file_as_string(REPORT)) if FileAccess.file_exists(REPORT) else null
	_check(report is Dictionary, "it wrote its report")
	if report is Dictionary:
		_river(report)
		_pond(report)
		_smooth(report)
	if failures.is_empty():
		print("test_terrain_shapes: PASS")
		quit(0)
	else:
		for fl in failures:
			print("FAIL " + fl)
		print("test_terrain_shapes: %d FAILED" % failures.size())
		quit(1)


func _check(ok: bool, what: String) -> void:
	if not ok:
		failures.append(what)


func _river(report: Dictionary) -> void:
	var r: Dictionary = report.get("rivers", {}).get("test_river", {})
	_check(not r.is_empty(), "the river is reported")
	if r.is_empty():
		return
	print("river bed: %s" % r)
	_check(float(r["shallowest"]) > 0.9 * 0.8, "its bed is under the water all the way (shallowest %.2f m)" % r["shallowest"])
	_check(float(r["deepest"]) < 0.9 + 1.5, "...and no pit in it (deepest %.2f m; the lake's is about 1.35)" % r["deepest"])


func _pond(report: Dictionary) -> void:
	for want in [["test_pond", 1.1], ["test_outline", 1.0], ["lake", LAKE_DEPTH]]:
		var p: Dictionary = report.get("layout_ponds", {}).get(want[0], {})
		_check(not p.is_empty(), "pond %s is reported" % want[0])
		if p.is_empty():
			continue
		print("%s: %s" % [want[0], p])
		_check(absf(float(p["deepest"]) - want[1]) < 0.25, "%s is dug about as deep as it asked (%.2f m of %.2f)" % [want[0], p["deepest"], want[1]])


func _smooth(report: Dictionary) -> void:
	var sm: Dictionary = report.get("smoothed", {}).get("test_smooth", {})
	_check(not sm.is_empty(), "the smoothing is reported")
	if sm.is_empty():
		return
	print("smoothed: %s" % sm)
	_check(float(sm["after"]) < float(sm["before"]) * 0.5, "the smoothed ground is much less bumpy (%.3f -> %.3f)" % [sm["before"], sm["after"]])
