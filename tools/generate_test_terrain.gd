extends SceneTree
## Generates the starter terrain into res://terrain_data. Run headless from the project folder:
##   godot --headless --path . -s res://tools/generate_test_terrain.gd
## WARNING: overwrites any sculpting you've done in res://terrain_data.
##
## Layout: a flat clearing around the gathering area (where the trees, rocks and greybox
## blocks sit, all at height 0), hills rising outside it, a shallow wading pond just off the
## clearing (its water surface lives in main.tscn at WATER_LEVEL), and one tall peak in a
## corner so every colour band of the low-poly shader shows up.
## Over the hills to the east lies the village: a second flat valley with its own pond, joined
## to the clearing by a dirt path that cuts a pass through the hills. The path (and the village
## square and the lanes to each house) is painted as texture id PATH_TEXTURE in the control map;
## the terrain shader colours it and the footsteps sound like dirt on it.

const SIZE := 512                       # heightmap pixels = metres (vertex spacing 1); 2x2 regions
const ORIGIN := Vector3(-256, 0, -256)  # world position of pixel (0, 0) — must sit on the region grid
const CLEARING_CENTER := Vector2(0, -4)
const CLEARING_RADIUS := 28.0
const HILL_RAMP := 40.0                 # metres over which the hills rise out of the clearing
const DATA_DIR := "res://terrain_data"
const WATER_LEVEL := -0.15     # keep in sync with the ponds' WaterBody nodes in main.tscn
## Ponds: centre, radius (roughly where the bed rises to the water line), deepest point below
## the water line (wading depth — no swimming). Keep in sync with the ponds in main.tscn.
const PONDS := [
	{"center": Vector2(20, 16), "radius": 9.0, "depth": 0.95},   # the clearing's pond
	{"center": Vector2(88, 64), "radius": 7.0, "depth": 0.75},   # the village pond
]

const VILLAGE_CENTER := Vector2(100, 40)  # the middle of the village square
const VILLAGE_RADIUS := 36.0
const VILLAGE_RAMP := 30.0
## Control-map texture id that marks the path (see shaders/terrain_lowpoly.gdshader, footsteps.gd).
const PATH_TEXTURE := 1
## The path from the clearing over the pass into the village square.
const PATH := [Vector2(22, -2), Vector2(42, 6), Vector2(62, 20), Vector2(80, 34), Vector2(100, 40)]
## Lanes from the square to each building's door (see the scenes in scenes/village/).
const LANES := [
	[Vector2(100, 40), Vector2(107, 40)],                   # town hall
	[Vector2(100, 40), Vector2(98, 31)],                    # woodcutter
	[Vector2(100, 40), Vector2(105, 46), Vector2(108, 49)], # smithy
	[Vector2(100, 40), Vector2(94, 46), Vector2(90, 50)],   # fisher
]
const SQUARE_RADIUS := 7.5
const PATH_HALF_WIDTH := 1.6
const LANE_HALF_WIDTH := 1.0
## Where the path crosses the hills it's cut down to at most this height, with sloping
## shoulders either side: the pass you crest before seeing the village below.
const PASS_HEIGHT := 6.0
const PASS_SHOULDER := 9.0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var terrain := Terrain3D.new()
	root.add_child(terrain)
	await process_frame

	var noise := FastNoiseLite.new()
	noise.seed = 7
	noise.frequency = 0.012
	noise.fractal_octaves = 4
	var bumps := FastNoiseLite.new()
	bumps.seed = 21
	bumps.frequency = 0.06
	var shore := FastNoiseLite.new()  # makes the pond outlines irregular
	shore.seed = 5
	shore.frequency = 0.15

	var img := Image.create_empty(SIZE, SIZE, false, Image.FORMAT_RF)
	for y in SIZE:
		for x in SIZE:
			var w := Vector2(x + ORIGIN.x, y + ORIGIN.z)
			img.set_pixel(x, y, Color(_height(w, noise, bumps, shore), 0, 0))

	var images: Array[Image] = []
	images.resize(Terrain3DRegion.TYPE_MAX)
	images[Terrain3DRegion.TYPE_HEIGHT] = img
	terrain.data.import_images(images, ORIGIN, 0.0, 1.0)

	# paint the path, the square and the lanes
	var painted := 0
	for y in SIZE:
		for x in SIZE:
			var w := Vector2(x + ORIGIN.x, y + ORIGIN.z)
			if _on_path(w + Vector2(0.5, 0.5)):  # the cell's centre
				terrain.data.set_control_base_id(Vector3(w.x, 0, w.y), PATH_TEXTURE)
				painted += 1
	_report_path_slope(terrain)

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DATA_DIR))
	terrain.data.save_directory(DATA_DIR)
	print("Saved terrain to ", DATA_DIR, " (", painted, " path cells)")
	quit()


func _height(w: Vector2, noise: FastNoiseLite, bumps: FastNoiseLite, shore: FastNoiseLite) -> float:
	# 0 inside the clearing and the village, easing up to 1 over the ramps
	var outside := minf(
		smoothstep(CLEARING_RADIUS, CLEARING_RADIUS + HILL_RAMP, w.distance_to(CLEARING_CENTER)),
		smoothstep(VILLAGE_RADIUS, VILLAGE_RADIUS + VILLAGE_RAMP, w.distance_to(VILLAGE_CENTER)))
	var hills := outside * ((noise.get_noise_2dv(w) * 0.5 + 0.5) * 18.0 + 4.0)
	var h := hills + outside * bumps.get_noise_2dv(w) * 1.5  # small lumps, not on the flats
	# the pass: the path cuts the hills down to PASS_HEIGHT (and smooths the lumps away)
	var cut := 1.0 - smoothstep(PATH_HALF_WIDTH, PATH_HALF_WIDTH + PASS_SHOULDER, _polyline_distance(w, PATH))
	h = lerpf(h, minf(hills, PASS_HEIGHT), cut)
	for pond in PONDS:
		h = _pond(w, h, pond, shore)
	h += _bump(w, Vector2(-92, -92), 30.0) * 38.0        # the snowy peak
	return h


## No hills right next to the water, then a shallow bowl with a gently sloping shore.
func _pond(w: Vector2, h: float, pond: Dictionary, shore: FastNoiseLite) -> float:
	var r: float = pond["radius"]
	var pd: float = w.distance_to(pond["center"]) + shore.get_noise_2dv(w) * 2.0
	h *= smoothstep(r + 2.0, r + 8.0, pd)
	var bowl := 1.0 - smoothstep(r * 0.3, r + 1.5, pd)  # 1 mid-pond, 0 past the shore
	if bowl > 0.0:
		h = minf(h, (WATER_LEVEL - float(pond["depth"])) * bowl)
	return h


func _on_path(w: Vector2) -> bool:
	if w.distance_to(VILLAGE_CENTER) < SQUARE_RADIUS:
		return true
	if _polyline_distance(w, PATH) < PATH_HALF_WIDTH:
		return true
	for lane in LANES:
		if _polyline_distance(w, lane) < LANE_HALF_WIDTH:
			return true
	return false


func _polyline_distance(w: Vector2, points: Array) -> float:
	var best := INF
	for i in points.size() - 1:
		var p := Geometry2D.get_closest_point_to_segment(w, points[i], points[i + 1])
		best = minf(best, w.distance_to(p))
	return best


## Prints the steepest stretch along the path, to check it stays walkable.
func _report_path_slope(terrain: Terrain3D) -> void:
	var steepest := 0.0
	var top := -INF
	for i in PATH.size() - 1:
		var a: Vector2 = PATH[i]
		var b: Vector2 = PATH[i + 1]
		var steps := int(a.distance_to(b))
		for s in steps:
			var p := a.lerp(b, float(s) / steps)
			var q := a.lerp(b, float(s + 1) / steps)
			var hp: float = terrain.data.get_height(Vector3(p.x, 0, p.y))
			var hq: float = terrain.data.get_height(Vector3(q.x, 0, q.y))
			steepest = maxf(steepest, absf(hq - hp) / p.distance_to(q))
			top = maxf(top, hp)
	print("Path: highest point %.1f m, steepest grade %.2f" % [top, steepest])


## 1 at `center`, smoothly 0 at `radius`.
func _bump(w: Vector2, center: Vector2, radius: float) -> float:
	return 1.0 - smoothstep(0.0, radius, w.distance_to(center))
