extends SceneTree
## Checks that the land follows the map editor's anchors (plans/map-editor-places.md, phase 4): runs
## the terrain generator as a dry run (it writes nothing) on a copy of the layout with the watermill
## moved 60 m east, off the creek, and turned a quarter, and the green turned a quarter, then reads
## what it did:
##   - the mill's pad is level where the mill now stands
##   - the path to the mill ends at the mill, where it stands now
##   - the mill's wheel is out of the water, and the run says so
##   - the village pond is dug where the turned green has it
##   - every other pad is level, or (a road laid across it) warned about
##   godot --headless --path . -s res://tools/test_terrain_follows.gd
## Takes about a minute (one terrain run). (No game class names: an -s script compiles before the
## autoloads exist.)

const WorldMapC := preload("res://scripts/world_map.gd")
const Anchors := preload("res://scripts/layout_anchors.gd")
const LAYOUT := "res://data/layout/hearthvale.json"
const MOVED := "user://test_terrain_follows_layout.json"
const REPORT := "user://test_terrain_follows_report.json"
const PAD_LEVEL := 0.15  # (m: the most the middle of a pad may be off its own height)

var failures := PackedStringArray()


func _initialize() -> void:
	var layout: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(LAYOUT))
	var mill_at := Vector2.ZERO
	for a in layout["anchors"]:
		if a["id"] == "watermill":
			a["at"] = [float(a["at"][0]) + 60.0, float(a["at"][1])]
			a["yaw"] = float(a["yaw"]) + 90.0
			mill_at = Vector2(a["at"][0], a["at"][1])
		elif a["id"] == "green":
			a["yaw"] = float(a["yaw"]) + 90.0
	var f := FileAccess.open(MOVED, FileAccess.WRITE)
	f.store_string(JSON.stringify(layout))
	f.close()
	if FileAccess.file_exists(REPORT):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(REPORT))
	var out := []
	var code := OS.execute(OS.get_executable_path(), ["--headless", "--path", ProjectSettings.globalize_path("res://"),
			"-s", "res://tools/generate_test_terrain.gd", "--", "--dry-run",
			"--layout=" + ProjectSettings.globalize_path(MOVED), "--report=" + ProjectSettings.globalize_path(REPORT)], out, true)
	_check(code == 0, "the terrain generator ran (exit %d)" % code)
	var report: Variant = JSON.parse_string(FileAccess.get_file_as_string(REPORT)) if FileAccess.file_exists(REPORT) else null
	_check(report is Dictionary, "it wrote its report")
	if report is Dictionary:
		Anchors.use_file(ProjectSettings.globalize_path(MOVED))  # (so WorldMap reads the moved places)
		_mill(report, mill_at)
		_pond(report)
		_pads(report)
		Anchors.use_file(LAYOUT)
	if failures.is_empty():
		print("test_terrain_follows: PASS")
		quit(0)
	else:
		for fl in failures:
			print("FAIL " + fl)
		print("test_terrain_follows: %d FAILED" % failures.size())
		quit(1)


func _check(ok: bool, what: String) -> void:
	if not ok:
		failures.append(what)


func _mill(report: Dictionary, mill_at: Vector2) -> void:
	var pad: Dictionary = report["pads"].get("watermill", {})
	_check(not pad.is_empty(), "the mill has a pad")
	if not pad.is_empty():
		_check(Vector2(pad["at"][0], pad["at"][1]).distance_to(mill_at) < 0.1, "...where it stands now")
		_check(float(pad["off"]) < PAD_LEVEL, "...and level (%.2f m off)" % pad["off"])
	var road: Array = report["roads"].get("mill_path", [])
	_check(road.size() == 2, "the path to the mill was laid")
	if road.size() == 2:
		var want := WorldMapC.in_frame(&"watermill", Vector2(5, -8))
		var end := Vector2(road[1][0], road[1][1])
		_check(end.distance_to(want) < 3.0, "...ending at the moved mill (%s, wants %s)" % [end, want])
	var warned := false
	for w in report.get("warnings", []):
		warned = warned or (String(w["msg"]).contains("mill's wheel") and w["ref"] == "watermill")
	_check(warned, "a mill off the creek is warned about (its wheel %s m from it)" % report.get("mill_wheel_from_creek", "?"))


func _pond(report: Dictionary) -> void:
	var ponds: Array = report.get("ponds", [])
	_check(ponds.size() >= 2, "the ponds are reported")
	if ponds.size() >= 2:
		var want := WorldMapC.in_frame(&"green", Vector2(-8, 4))  # (the pond's place on the green)
		var at := Vector2(ponds[1][0], ponds[1][1])
		_check(at.distance_to(want) < 0.1, "the village pond is dug where the turned green has it (%s, wants %s)" % [at, want])


## Every pad no road was laid across is level; one a road spoilt is warned about.
func _pads(report: Dictionary) -> void:
	var off := PackedStringArray()
	var unwarned := PackedStringArray()
	for id in report["pads"]:
		var pad: Dictionary = report["pads"][id]
		if float(pad["off"]) < PAD_LEVEL:
			continue
		if not pad.get("road", false):
			off.append("%s %.2f m" % [id, pad["off"]])
		elif not report.get("warnings", []).any(func(w: Dictionary) -> bool: return w["ref"] == id):
			unwarned.append(id)
	_check(off.is_empty(), "every pad no road crosses is level (off: %s)" % ", ".join(off))
	_check(unwarned.is_empty(), "a pad a road crosses is warned about (not: %s)" % ", ".join(unwarned))
