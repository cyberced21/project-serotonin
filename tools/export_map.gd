extends SceneTree
## Draws the land for the map editor (plans/map-editor.md): a top-down picture of Hearthvale's
## terrain, a pixel a metre, coloured by surface and shaded by slope, and what the editor draws
## over it but doesn't edit: the roads and paths, the creek, the buildings, fixtures and props of
## the village and the places, and the places' names. Writes tools/map_editor/map.png and
## tools/map_editor/world.json (the folder has a .gdignore: Godot doesn't import them).
##   godot --headless --path . -s res://tools/export_map.gd -- --save-root=user://tool_worlds
## Run it again after the terrain changes (the editor's server does, after a terrain bake).
## (No game class names: an -s script compiles before the autoloads exist.)

const WorldMapC := preload("res://scripts/world_map.gd")
const OUT_DIR := "res://tools/map_editor/"
const WATER_LEVEL := -0.15
## The heights the editor reads back (under the cursor, for slopes) are on a grid this coarse (m).
const HEIGHT_STEP := 4
const CONTOUR := 5.0
const COLORS := {
	0: Color(0.40, 0.58, 0.32), 1: Color(0.66, 0.52, 0.38), 2: Color(0.85, 0.83, 0.78),
	3: Color(0.24, 0.42, 0.24), 4: Color(0.60, 0.70, 0.32), 5: Color(0.70, 0.66, 0.60),
	6: Color(0.88, 0.74, 0.36),
}
const PLACES := [
	["The Clearing", WorldMapC.CLEARING_CENTER],
	["Stillwater", WorldMapC.LAKE_CENTER], ["Frostpeak", WorldMapC.PEAK_CENTER],
	["Greystone Quarry", WorldMapC.QUARRY_CENTER], ["Goldmeadow", WorldMapC.FIELD_CENTER],
	["The Pinewood", WorldMapC.FOREST_CENTER],
]
## The places the map editor moves (their anchors): name, anchor id.
const ANCHORED_PLACES := [["Hearthvale", &"green"], ["The watermill", &"watermill"], ["The orchard", &"orchard"],
	["Shepherd's hill", &"shepherds_hill"], ["The haven", &"haven"]]


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.get_node("Worlds").call("play_fresh")
	while get_first_node_in_group("player") == null:
		await process_frame
	for i in 10:
		await process_frame
	var terrain := get_first_node_in_group("terrain")
	var size := int(WorldMapC.WORLD_SIZE)
	var origin := Vector2(WorldMapC.WORLD_MIN, WorldMapC.WORLD_MIN)
	var h := PackedFloat32Array()
	h.resize(size * size)
	var ids := PackedByteArray()
	ids.resize(size * size)
	for y in size:
		for x in size:
			var at := Vector3(origin.x + x + 0.5, 0, origin.y + y + 0.5)
			var v: float = terrain.data.get_height(at)
			h[y * size + x] = 0.0 if is_nan(v) else v
			ids[y * size + x] = terrain.data.get_control_base_id(at)
	var img := Image.create_empty(size, size, false, Image.FORMAT_RGB8)
	for y in size:
		for x in size:
			var i := y * size + x
			var c: Color = COLORS.get(ids[i], Color.MAGENTA)
			var hx := h[mini(i + 1, h.size() - 1)] - h[i]
			var hy := h[mini(i + size, h.size() - 1)] - h[i]
			var light := clampf(1.0 - (hx + hy) * 0.35, 0.4, 1.35)
			if h[i] < WATER_LEVEL:
				c = Color(0.30, 0.50, 0.68)
			elif absf(hx) > 1.2 or absf(hy) > 1.2:
				c = Color(0.36, 0.33, 0.30)  # cliffs
			elif floori(h[i] / CONTOUR) != floori(h[mini(i + 1, h.size() - 1)] / CONTOUR) \
					or floori(h[i] / CONTOUR) != floori(h[mini(i + size, h.size() - 1)] / CONTOUR):
				c = c.darkened(0.18)  # a contour line every CONTOUR m of height
			img.set_pixel(x, y, c * light)
	img.save_png(OUT_DIR + "map.png")

	var heights := []
	for y in range(0, size, HEIGHT_STEP):
		for x in range(0, size, HEIGHT_STEP):
			heights.append(snappedf(h[y * size + x], 0.1))
	var roads := []
	for r in WorldMapC.roads():
		var pts := []
		var line: PackedVector2Array = r["pts"]
		for k in range(0, line.size(), 2):
			pts.append([snappedf(line[k].x, 0.1), snappedf(line[k].y, 0.1)])
		roads.append({"id": r["id"], "title": r.get("title", ""), "kind": r["kind"], "half_width": r["half_width"], "pts": pts})
	var creek := []
	var cl := WorldMapC.creek()
	for k in range(0, cl.size(), 3):
		creek.append([snappedf(cl[k].x, 0.1), snappedf(cl[k].y, 0.1)])
	var things := []
	for g in ["building", "fixture", "prop"]:
		for n in get_nodes_in_group(g):
			if _in_layout(n):
				continue
			var p := (n as Node3D).global_position
			var r := float(n.call("footprint_radius")) if n.has_method("footprint_radius") else 1.0
			things.append([snappedf(p.x, 0.1), snappedf(p.z, 0.1), snappedf(r, 0.1), g, String(n.name)])
	var labels := []
	for p in PLACES:
		labels.append([p[1].x, p[1].y, p[0]])
	for p in ANCHORED_PLACES:
		var at: Vector2 = WorldMapC.site(p[1])
		labels.append([at.x, at.y, p[0]])
	var world := {
		"origin": [origin.x, origin.y], "size": size, "water_level": WATER_LEVEL,
		"height_step": HEIGHT_STEP, "heights": heights, "roads": roads, "creek": creek,
		"things": things, "labels": labels,
	}
	var f := FileAccess.open(OUT_DIR + "world.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(world))
	print("map: %dx%d, %d roads, %d things -> %s" % [size, size, roads.size(), things.size(), OUT_DIR])
	quit()


func _in_layout(n: Node) -> bool:
	while n:
		if n.name == &"Layout":
			return true
		n = n.get_parent()
	return false
