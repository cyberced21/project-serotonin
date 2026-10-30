extends SceneTree
## Generates the terrain into res://terrain_data. Run headless from the project folder:
##   godot --headless --path . -s res://tools/generate_test_terrain.gd
## Add `-- --preview=<file.png>` to also write a top-down map of the result (surface ids, shaded).
## WARNING: overwrites any sculpting you've done in res://terrain_data.
##
## Layout (plans/world.md, plans/world-pass.md map C): a wide shallow bowl with Hearthvale low in
## its middle, rising to rim hills where the other places sit, each up its own road through a
## notch in the rim. Broad warped hills with soft crests roll over it all, gentler on the bowl's
## floor. The village, the clearing just outside it (where the trees, rocks and ruins sit) and the
## lake basin beyond the south rim are flats at height 0 whose edges wander outward.
## The clearing and village have wading ponds, the lake is wider and deeper (still wadeable);
## their water surfaces live in main.tscn at WATER_LEVEL. Frostpeak is one broad mountain in the
## north-west, and the world's edge rises into high hills all round so the valley feels closed in.
## A relax pass eases anything steeper than about 30° (the peak's top may be steeper).
## The path (and the village square and the lanes to each house) is painted as texture id
## PATH_TEXTURE in the control map; the terrain shader colours it and the footsteps sound like
## dirt on it.
##
## Around all that sit the biomes (shapes in scripts/world_map.gd): the Pinewood over the northern
## hills, Greystone Quarry (a five-level pit) on a mountain shoulder to the west, Goldmeadow's
## swells and crop squares in the south-east, and a graded gravel ring road joining them, with
## spurs into each area. Each biome paints its own control-map texture id (WorldMap.TEX_*).
##
## Hand-placed buildings, props and ruins in main.tscn stand on the flats (the run lists any whose
## ground isn't at 0); the resource nodes under "Nodes" get their Y rewritten to the new ground.

const WorldMap := preload("res://scripts/world_map.gd")

const SIZE := 768                       # heightmap pixels = metres (vertex spacing 1); 3x3 regions
const ORIGIN := Vector3(-256, 0, -256)  # world position of pixel (0, 0) — must sit on the region grid
const CLEARING_CENTER := WorldMap.CLEARING_CENTER
const CLEARING_RADIUS := 28.0
const HILL_RAMP := 55.0                 # metres over which the hills rise out of the clearing
## The flats' edges wander outward by up to this much (never inward: what's placed on them stays
## on flat ground).
const FLAT_GROW := 24.0
## The hills: broad, rounded, warped so nothing reads as a circle. Height = HILL_BASE + up to
## HILL_RANGE, eased down to the flats.
const HILL_BASE := 3.0
const HILL_RANGE := 12.0  # (the bowl's rim already lifts them: gentler on top of it)
const WARP := 38.0                      # how far (m) the hills' noise is pushed around
## Between the places the paths run along valleys: the hills keep this share of their height on
## the valley floor, easing back to full over VALLEY_RAMP.
const VALLEY_FLOOR := 0.22
const VALLEY_HALF := 5.0
const VALLEY_RAMP := 42.0
## The roads out of the bowl climb through notches in its rim: along a spoke from the village to
## each place the land keeps this share of its height, easing back over VALLEY_RAMP.
const SPOKE_FLOOR := 0.5
## How much of the hills' roll the bowl's floor keeps (the rim keeps it all), and how far the rim
## wanders in and out (m).
const BOWL_HILLS := 0.3
const BOWL_WANDER := 28.0
## The creek (WorldMap.CREEK) runs down a vale of its own: the hills keep this share of their
## height along it, easing back over CREEK_VALE. Its channel is CREEK_DEPTH deep under the water
## (CREEK_POOL_DEPTH in the pools), and its banks ease up over CREEK_BANK.
const CREEK_VALE_FLOOR := 0.05
const CREEK_VALE := 70.0  # (wide: it cuts through the bowl's rim to the lake)
const CREEK_DEPTH := 0.55
const CREEK_POOL_DEPTH := 1.2
const CREEK_BANK := 12.0
## Biome borders: each biome's ground thins out into the plain grass over this wide a belt.
const BORDER_BELT := 22.0
## Goldmeadow's swells ease into the hills over this much.
const FIELD_RAMP := 60.0
## The world's edge rises into higher hills so the valley feels closed in, not cut off.
const RIM_WIDTH := 95.0
const RIM_HEIGHT := 24.0
## Frostpeak: a summit with spurs running down from it and a high shoulder to the west, each a
## ridge with a rounded crest and steep flanks (rock where steeper than ~47°, snow on the gentler
## high ground: shaders/terrain.gdshader), gullies cut down its sides.
const PEAK_CENTER := WorldMap.PEAK_CENTER
const PEAK_RADIUS := 76.0
const PEAK_HEIGHT := 66.0
## [from, to, crest height at each end, flank steepness at each end (rise per metre)]
const PEAK_RIDGES := [
	[Vector2(-98, -54), Vector2(-98, -54), 66.0, 66.0, 1.0, 1.0],     # the summit
	[Vector2(-98, -54), Vector2(-56, -26), 64.0, 10.0, 1.3, 0.55],    # the north-east spur
	[Vector2(-98, -54), Vector2(-104, -4), 62.0, 12.0, 1.25, 0.55],   # the south spur
	[Vector2(-98, -54), Vector2(-90, -112), 62.0, 8.0, 1.2, 0.5],     # the north spur
	[Vector2(-98, -54), Vector2(-132, -66), 60.0, 44.0, 1.4, 0.9],   # up to the shoulder
	[Vector2(-132, -66), Vector2(-158, -94), 44.0, 10.0, 0.9, 0.5], # and down off it
]
const PEAK_CREST := 5.0  # how rounded the crests are (m)
## Steepest rise per metre the relax pass leaves between neighbouring cells, along x or z (so
## diagonally at most ~0.64, about 32°). Not in the quarry pit; Frostpeak may be steeper by up to
## PEAK_SLOPE (its rock faces).
const MAX_SLOPE := 0.45
const PEAK_SLOPE := 1.2
const RELAX_PASSES := 80
const DATA_DIR := "res://terrain_data"
const WATER_LEVEL := -0.15     # keep in sync with the ponds' WaterBody nodes in main.tscn
## Ponds: centre, radius (roughly where the bed rises to the water line), deepest point below
## the water line (wading depth — no swimming). Keep in sync with the ponds in main.tscn.
const PONDS := [
	{"center": Vector2(66, 86), "radius": 9.0, "depth": 0.95},   # the clearing's pond
	{"center": Vector2(120, 132), "radius": 9.0, "depth": 0.75},  # the village pond, on the green
	{"center": Vector2(38, 340), "radius": 14.0, "depth": 1.35},  # the lake
]
## The lake's flat basin beyond the south rim (hills ease up beyond radius over the ramp).
const LAKE_BASIN := {"center": WorldMap.LAKE_CENTER, "radius": 26.0, "ramp": 85.0}

const VILLAGE_CENTER := WorldMap.VILLAGE_CENTER  # the middle of the village green
const VILLAGE_RADIUS := WorldMap.VILLAGE_RADIUS
const VILLAGE_RAMP := 50.0
## Goldmeadow's plain sits up on the rim: its swells ride on this height.
const FIELD_BASE := WorldMap.BOWL_RIM_HEIGHT * 0.85
## Control-map texture id that marks the path (see shaders/terrain.gdshader, footsteps.gd).
const PATH_TEXTURE := WorldMap.TEX_PATH
## The path from the clearing over the pass to the green's ring.
const PATH := WorldMap.VILLAGE_PATH
## The ring round the village green (plans/world-pass.md, the pond green) and its lanes: out to
## where each road starts, and in to each door (as scripts/village_paths.gd walks them).
const RING_RADIUS := 25.5
const RING_HALF_WIDTH := 1.3
const LANES := [
	[Vector2(138, 104), Vector2(134, 80), Vector2(128, 58)],   # north, the road to the Pinewood
	[Vector2(153, 127), Vector2(176, 127), Vector2(200, 126)], # east, the road east
	[Vector2(146, 146), Vector2(162, 162), Vector2(178, 178)], # south-east, the road to Goldmeadow
	[Vector2(127, 153), Vector2(122, 176), Vector2(118, 198)], # south, the road to the lake
	[Vector2(103, 131), Vector2(80, 132), Vector2(58, 132)],   # west, the road to the quarry
	[Vector2(131.5, 102.7), Vector2(128.8, 102.8)],           # town hall
	[Vector2(115.2, 105.9), Vector2(109.9, 93.8)],            # woodcutter
	[Vector2(150.1, 115.2), Vector2(161.0, 97.9)],            # smithy
	[Vector2(150.1, 115.2), Vector2(155.2, 114.5)],           # tavern
	[Vector2(131.5, 102.7), Vector2(124.6, 123.0)],           # the fisher's, on the pond's north bank
	[Vector2(131.5, 102.7), Vector2(134.0, 113.0), Vector2(134.0, 124.0), Vector2(133.0, 141.0), Vector2(128.0, 153.5)], # across the green
	[Vector2(140.8, 150.1), Vector2(145.4, 161.0), Vector2(152.0, 158.2), Vector2(153.9, 161.3)], # bakery, terrace
	[Vector2(115.2, 150.1), Vector2(102.6, 166.2)],           # Edda's
	[Vector2(104.0, 104.0), Vector2(94.0, 101.0), Vector2(86.4, 107.2)], # your home
]
const PATH_HALF_WIDTH := 1.6
const LANE_HALF_WIDTH := 1.0

## The quarry's haul road: each ramp runs along the inside of a wall, this wide, climbing one
## level over RAMP_LENGTH metres; the next ramp down starts RAMP_GAP metres further round.
const RAMP_WIDTH := 4.5
const RAMP_LENGTH := 38.0
const RAMP_GAP := 4.0

## Roads and paths: steepest grade, how far their shoulders reach and over how much they ease
## into the ground. No sheer cuttings: a road that cuts into a hill gets sloped sides.
const ROAD_GRADE := 0.10
const PATH_GRADE := 0.14
const ROAD_SHOULDER := 26.0
const PATH_SHOULDER := 16.0
## Where the road router (a least-cost path over a ROUTE_CELL m grid) prefers to go: cost grows
## with the slope squared; water, the quarry pit and hand-placed things are all but walls.
const ROUTE_CELL := 4
const ROUTE_SLOPE_COST := 160.0
const ROUTE_WATER_COST := 300.0
const ROUTE_CREEK_COST := 25.0
const ROUTE_BANK_COST := 8.0  # (on its banks: a road there leaves a ledge above the water)
## The lines the roads were laid on, for the game (WorldMap.roads()).
const ROADS_OUT := "res://scripts/world_roads.gd"

## Hand-placed things other than the resource nodes (buildings, props, ruins) stand on the flats
## at height 0; the run lists any whose ground is off by more than this.
const MOVED_TOLERANCE := 0.05
## Scenes placed on the terrain at runtime (quarry props, spawners...): not checked.
const BIOME_SCENES := "res://scenes/biomes/"
## main.tscn's resource nodes (children of "Nodes"): their Y is rewritten to the new ground.
const MAIN_SCENE := "res://scenes/main.tscn"

var _noise := FastNoiseLite.new()
var _warp_x := FastNoiseLite.new()  # push the hills' noise around, so ridges wander
var _warp_y := FastNoiseLite.new()
var _fine := FastNoiseLite.new()    # a gentle swell, nothing like lumps
var _shore := FastNoiseLite.new()  # makes the pond outlines irregular
var _rings := FastNoiseLite.new()  # makes the quarry's walls wander
var _swell := FastNoiseLite.new()  # the field's rolling swells
var _edge := FastNoiseLite.new()   # ragged biome borders
var _creek_mask := PackedByteArray()  # 1 on the creek's channel and inner banks
var _ramp_top: Array[float] = []   # per quarry wall: angle of its ramp's top end
var _ramp_span: Array[float] = []  # per quarry wall: angle its ramp covers


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var terrain := Terrain3D.new()
	root.add_child(terrain)
	await process_frame
	_setup()

	var base := PackedFloat32Array()
	base.resize(SIZE * SIZE)
	var h := PackedFloat32Array()
	h.resize(SIZE * SIZE)
	var ids := PackedByteArray()
	ids.resize(SIZE * SIZE)
	for y in SIZE:
		for x in SIZE:
			var w := _world(x, y)
			var i := y * SIZE + x
			base[i] = _height(w)
			ids[i] = _biome_id(w + Vector2(0.5, 0.5))  # the cell's centre
			if _on_path(w + Vector2(0.5, 0.5)):
				ids[i] = PATH_TEXTURE
	for y in SIZE:
		for x in SIZE:
			var w := _world(x, y)
			h[y * SIZE + x] = _biomes(w, base[y * SIZE + x]) + (_peak(w) + _rim(w)) * _off_quarry(w)
	_glades(h)
	_relax(h)
	_carve_creek(h)

	var baked := _baked_points()
	var laid := _lay_roads(h, ids, baked)
	_relax(h)  # again: smooths any seam where two roads' banks (or a hairpin's legs) meet

	var img := Image.create_empty(SIZE, SIZE, false, Image.FORMAT_RF)
	for y in SIZE:
		for x in SIZE:
			img.set_pixel(x, y, Color(h[y * SIZE + x], 0, 0))
	var images: Array[Image] = []
	images.resize(Terrain3DRegion.TYPE_MAX)
	images[Terrain3DRegion.TYPE_HEIGHT] = img
	terrain.data.import_images(images, ORIGIN, 0.0, 1.0)

	var painted := 0
	for y in SIZE:
		for x in SIZE:
			var id := ids[y * SIZE + x]
			if id != WorldMap.TEX_DEFAULT:
				var w := _world(x, y)
				terrain.data.set_control_base_id(Vector3(w.x, 0, w.y), id)
				painted += 1
	_write_roads(laid)
	_report_moved(baked, h)
	_report_slopes(h, ids)
	_rebake_nodes(h)

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DATA_DIR))
	terrain.data.save_directory(DATA_DIR)
	print("Saved terrain to ", DATA_DIR, " (", painted, " painted cells)")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--preview="):
			_write_preview(arg.trim_prefix("--preview="), h, ids)
	quit()


func _setup() -> void:
	_noise.seed = 7
	_noise.frequency = 0.0065
	_noise.fractal_octaves = 3
	_noise.fractal_gain = 0.42
	_warp_x.seed = 31
	_warp_x.frequency = 0.004
	_warp_y.seed = 32
	_warp_y.frequency = 0.004
	_fine.seed = 21
	_fine.frequency = 0.02
	_fine.fractal_octaves = 1
	_shore.seed = 5
	_shore.frequency = 0.15
	_rings.seed = 11
	_rings.frequency = 0.05
	_swell.seed = 3
	_swell.frequency = 0.018
	_swell.fractal_octaves = 2
	_edge.seed = 17
	_edge.frequency = 0.03
	# the haul road spirals down: each ramp's top starts just past where the one above ended
	var top := WorldMap.QUARRY_ROAD_ANGLE
	for b in WorldMap.QUARRY_WALLS:
		var r := b - RAMP_WIDTH * 0.5
		var span := RAMP_LENGTH / r
		_ramp_top.append(top)
		_ramp_span.append(span)
		top = top - span - RAMP_GAP / r


func _world(x: int, y: int) -> Vector2:
	return Vector2(x + ORIGIN.x, y + ORIGIN.z)


## The land before the biomes (Frostpeak and the rim go on after them): rolling hills that ease
## down to the clearing, the village and the lake basin, valleys along the paths between them,
## and the ponds.
func _height(w: Vector2) -> float:
	# a product, not a min: where two places' rims meet there's no crease
	var outside := _rise(w, CLEARING_CENTER, CLEARING_RADIUS, HILL_RAMP) 			* _rise(w, VILLAGE_CENTER, VILLAGE_RADIUS, VILLAGE_RAMP) 			* _rise(w, LAKE_BASIN["center"], LAKE_BASIN["radius"], LAKE_BASIN["ramp"])
	for path in [PATH, WorldMap.EAST_ROAD]:
		var v := smoothstep(VALLEY_HALF, VALLEY_HALF + VALLEY_RAMP, _polyline_distance(w, path))
		outside *= lerpf(VALLEY_FLOOR, 1.0, v)
	for to in SPOKES:
		var v := smoothstep(VALLEY_HALF, VALLEY_HALF + VALLEY_RAMP, _polyline_distance(w, [VILLAGE_CENTER, to]))
		outside *= lerpf(SPOKE_FLOOR, 1.0, v)
	var c := smoothstep(WorldMap.CREEK_HALF_WIDTH, CREEK_VALE, _polyline_distance(w, WorldMap.CREEK))
	outside *= lerpf(CREEK_VALE_FLOOR, 1.0, c)
	var rim := _bowl(w)
	var h := outside * (rim * WorldMap.BOWL_RIM_HEIGHT + _hills(w) * lerpf(BOWL_HILLS, 1.0, rim))
	for pond in PONDS:
		h = _pond(w, h, pond, _shore)
	return h


## Where the roads climb out of the bowl: a notch along the line from the village to each.
const SPOKES: Array[Vector2] = [WorldMap.QUARRY_RIM_POINT, Vector2(124, -6), Vector2(66, 316), Vector2(268, 252)]


## The bowl: 0 on its floor out to WorldMap.BOWL_FLOOR, rising smoothly to 1 on its rim by
## WorldMap.BOWL_RIM, the rim wandering in and out so it isn't a circle.
func _bowl(w: Vector2) -> float:
	var r := w.distance_to(VILLAGE_CENTER) + _warp_y.get_noise_2dv(w * 1.7) * BOWL_WANDER
	var t := clampf((r - WorldMap.BOWL_FLOOR) / (WorldMap.BOWL_RIM - WorldMap.BOWL_FLOOR), 0.0, 1.0)
	return t * t * t * (t * (t * 6.0 - 15.0) + 10.0)


## 0 on a place's flat (its edge wandering out by up to FLAT_GROW), easing to 1 over `ramp`.
func _rise(w: Vector2, center: Vector2, radius: float, ramp: float) -> float:
	var lobes := _warp_x.get_noise_2dv(w * 6.0) * 0.6 + _warp_y.get_noise_2dv(w * 2.5) * 0.4  # big lobes and smaller ones
	var grow := clampf(lobes * 0.5 + 0.5, 0.0, 1.0) * FLAT_GROW
	var t := clampf((w.distance_to(center) - radius - grow) / ramp, 0.0, 1.0)
	return t * t * t * (t * (t * 6.0 - 15.0) + 10.0)  # smootherstep: no crease at either end


## The open hills: warped low-frequency noise with soft crests and hollows.
func _hills(w: Vector2) -> float:
	var q := w + Vector2(_warp_x.get_noise_2dv(w), _warp_y.get_noise_2dv(w)) * WARP
	var n := clampf(_noise.get_noise_2dv(q) * 0.5 + 0.5, 0.0, 1.0)
	n = n * n * (3.0 - 2.0 * n)
	return HILL_BASE + n * HILL_RANGE + _fine.get_noise_2dv(w) * 0.6


## 0 in the quarry and on its apron, easing to 1 down its mountainside: the peak and the rim
## don't tilt the pit.
func _off_quarry(w: Vector2) -> float:
	var outer: float = WorldMap.QUARRY_WALLS[0] + WorldMap.QUARRY_APRON
	return smoothstep(outer, outer + WorldMap.QUARRY_SLOPE, w.distance_to(WorldMap.QUARRY_CENTER))


## Frostpeak: its ridges (PEAK_RIDGES) melted together, over a broad base so the valleys between
## the spurs don't fall to nothing, with gullies down the flanks; faded out at its foot.
func _peak(w: Vector2) -> float:
	var d0 := w.distance_to(PEAK_CENTER)
	if d0 > PEAK_RADIUS * 1.3:
		return 0.0
	var h := 26.0 * (1.0 - smoothstep(0.0, PEAK_RADIUS, d0))  # the massif under it all
	for r in PEAK_RIDGES:
		var a: Vector2 = r[0]
		var b: Vector2 = r[1]
		var ab := b - a
		var t := 0.0 if ab.length_squared() < 0.01 else clampf((w - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
		var d := w.distance_to(a + ab * t)
		var crest := lerpf(r[2], r[3], t)
		var side := lerpf(r[4], r[5], t)
		var ridge := crest - side * (sqrt(d * d + PEAK_CREST * PEAK_CREST) - PEAK_CREST)
		h = h + log(1.0 + exp(0.35 * (ridge - h))) / 0.35  # a soft max: ridges merge without creases
	# gullies running down the flanks, deepest high up
	var dir := (w - PEAK_CENTER) / maxf(d0, 0.001)  # (by direction, not angle: no seam where it wraps)
	var down := _noise.get_noise_3d(dir.x * 900.0, dir.y * 900.0, d0 * 1.5)
	h -= absf(down) * 6.0 * clampf(h / PEAK_HEIGHT, 0.0, 1.0)
	return maxf(h, 0.0) * (1.0 - smoothstep(PEAK_RADIUS * 0.85, PEAK_RADIUS * 1.3, d0))


## The edge of the world rising into high hills (wandering, so it isn't a straight wall).
func _rim(w: Vector2) -> float:
	var half := SIZE * 0.5
	var inner := half - RIM_WIDTH
	var c := (w - Vector2(ORIGIN.x + half, ORIGIN.z + half)).abs()
	var past := Vector2(maxf(c.x - inner, 0.0), maxf(c.y - inner, 0.0)).length()  # rounded corners
	past += _warp_x.get_noise_2dv(w * 1.3) * 18.0
	var t := clampf(past / RIM_WIDTH, 0.0, 1.0)
	# the pass the road east climbs through: the rim dips to a saddle along it
	var saddle := 1.0 - smoothstep(6.0, 45.0, _polyline_distance(w, WorldMap.EAST_ROAD))
	return RIM_HEIGHT * t * t * (1.0 - 0.6 * saddle)


## Eases every slope steeper than MAX_SLOPE back toward it, a little at a time from both sides, so
## the hills keep their shape but lose their ledges. The flats stay put: nothing there is steep.
func _relax(h: PackedFloat32Array) -> void:
	var limit := PackedFloat32Array()  # per cell; 0 = leave it alone
	limit.resize(SIZE * SIZE)
	for y in SIZE:
		for x in SIZE:
			var w := _world(x, y)
			var crags := 1.0 - smoothstep(PEAK_RADIUS * 0.6, PEAK_RADIUS * 1.0, w.distance_to(PEAK_CENTER))
			var keep := _in_pit(w) or (not _creek_mask.is_empty() and _creek_mask[y * SIZE + x] == 1)
			limit[y * SIZE + x] = 0.0 if keep else MAX_SLOPE + crags * PEAK_SLOPE
	for pass_i in RELAX_PASSES:
		var changed := 0
		for y in SIZE - 1:
			for x in SIZE - 1:
				var i := y * SIZE + x
				if limit[i] == 0.0:
					continue
				for j in [i + 1, i + SIZE]:
					var d: float = h[j] - h[i]
					var excess := absf(d) - limit[i]
					if excess > 0.0:
						var move := signf(d) * excess * 0.5
						h[i] += move
						h[j] -= move
						changed += 1
		if changed == 0:
			break


## No hills right next to the water, then a shallow bowl with a gently sloping shore.
func _pond(w: Vector2, h: float, pond: Dictionary, shore: FastNoiseLite) -> float:
	var r: float = pond["radius"]
	var pd: float = w.distance_to(pond["center"]) + shore.get_noise_2dv(w) * 2.0
	h *= smoothstep(r + 2.0, r + 8.0, pd)
	var bowl := 1.0 - smoothstep(r * 0.3, r + 1.5, pd)  # 1 mid-pond, 0 past the shore
	if bowl > 0.0:
		h = minf(h, (WATER_LEVEL - float(pond["depth"])) * bowl)
	return h


# --- biomes -----------------------------------------------------------------------------------

## The quarry's mountain shoulder and pit, and the field's swells, on top of the base height.
func _biomes(w: Vector2, h: float) -> float:
	var q := WorldMap.QUARRY_CENTER
	h += _bump(w, q, 120.0) * 8.0  # the shoulder the quarry is cut into
	var outer: float = WorldMap.QUARRY_WALLS[0] + WorldMap.QUARRY_APRON
	var d := w.distance_to(q)
	if d < outer:
		h = _quarry_height(w, d)
	elif d < outer + WorldMap.QUARRY_SLOPE + 30.0:
		# the mountainside falls away from the apron over a wandering distance, not a ring
		var dw := d + (_biome_warp(w).distance_to(q) - d) * smoothstep(outer, outer + 15.0, d)
		var lifted := lerpf(WorldMap.QUARRY_RIM_HEIGHT, h, smoothstep(outer, outer + WorldMap.QUARRY_SLOPE, dw))
		# (its long hillside never lifts the flats: the clearing's ruins and the village stay at 0)
		h += (lifted - h) * _rise(w, CLEARING_CENTER, CLEARING_RADIUS, HILL_RAMP) * _rise(w, VILLAGE_CENTER, VILLAGE_RADIUS, VILLAGE_RAMP)
	var fd := _biome_warp(w).distance_to(WorldMap.FIELD_CENTER)
	var inside := 1.0 - smoothstep(WorldMap.FIELD_RADIUS - 10.0, WorldMap.FIELD_RADIUS + FIELD_RAMP, fd)
	inside *= smoothstep(VILLAGE_RADIUS + FLAT_GROW, VILLAGE_RADIUS + FLAT_GROW + 25.0, w.distance_to(VILLAGE_CENTER))  # (not on the village's flat)
	if inside > 0.0:
		h = lerpf(h, FIELD_BASE + 0.8 + (_swell.get_noise_2dv(w) * 0.5 + 0.5) * 3.5, inside)
	return h


## Rim height, minus one level for every wall this spot is inside.
func _quarry_height(w: Vector2, d: float) -> float:
	var dn := d + _rings.get_noise_2dv(w) * 1.5
	var theta := (w - WorldMap.QUARRY_CENTER).angle()
	var walls := WorldMap.QUARRY_WALLS
	var above := 0.0  # how many walls this spot is on the outer (higher) side of
	for i in walls.size():
		above += _wall_step(i, dn, theta)
	return WorldMap.QUARRY_RIM_HEIGHT - WorldMap.QUARRY_LEVEL_DROP * (walls.size() - above)


## 1 on the outer side of wall i, 0 on the inner side; in between on its ramp.
func _wall_step(i: int, dn: float, theta: float) -> float:
	var b: float = WorldMap.QUARRY_WALLS[i]
	var s := _sharp(dn - b)
	if dn > b - RAMP_WIDTH and dn <= b:
		var t := _ramp_t(i, theta)
		if t >= 0.0:
			return t
	return s


## A drop over a single vertex: the pit's walls are cut stone faces (the ore walls stand on them).
func _sharp(x: float) -> float:
	return smoothstep(-0.2, 0.2, x)


## How far up wall i's ramp `theta` is (0 bottom, 1 top), or -1 off the ramp.
func _ramp_t(i: int, theta: float) -> float:
	var a := fposmod(theta - (_ramp_top[i] - _ramp_span[i]), TAU)
	return a / _ramp_span[i] if a <= _ramp_span[i] else -1.0


func _on_haul_road(w: Vector2) -> bool:
	var d := w.distance_to(WorldMap.QUARRY_CENTER) + _rings.get_noise_2dv(w) * 1.5
	var theta := (w - WorldMap.QUARRY_CENTER).angle()
	for i in WorldMap.QUARRY_WALLS.size():
		var b: float = WorldMap.QUARRY_WALLS[i]
		if d > b - RAMP_WIDTH and d <= b and _ramp_t(i, theta) >= 0.0:
			return true
	return false


## Which surface a cell gets from the biome it's in (roads and paths are painted on top later).
func _biome_id(w: Vector2) -> int:
	var q := _biome_warp(w)
	var pit: float = WorldMap.QUARRY_WALLS[0]
	var qd := q.distance_to(WorldMap.QUARRY_CENTER)
	var apron := pit + WorldMap.QUARRY_APRON
	if w.distance_to(WorldMap.QUARRY_CENTER) < pit + 1.0:
		return PATH_TEXTURE if _on_haul_road(w) else WorldMap.TEX_QUARRY
	if _dither(w, qd, apron, apron + BORDER_BELT):
		return WorldMap.TEX_QUARRY
	var fd := q.distance_to(WorldMap.FIELD_CENTER)
	if fd < WorldMap.FIELD_RADIUS - 6.0:
		return _crop_id(w, q)
	if _dither(w, fd, WorldMap.FIELD_RADIUS + 6.0, WorldMap.FIELD_RADIUS + 6.0 + BORDER_BELT):
		return WorldMap.TEX_FIELD
	var f := ((q - WorldMap.FOREST_CENTER) / WorldMap.FOREST_RADII).length() * WorldMap.FOREST_RADII.y
	var r := WorldMap.FOREST_RADII.y
	if _dither(w, f, r - BORDER_BELT * 0.6, r + BORDER_BELT * 0.4) and qd > apron + WorldMap.QUARRY_SLOPE \
			and w.distance_to(PEAK_CENTER) > 35.0:
		return WorldMap.TEX_FOREST
	return WorldMap.TEX_DEFAULT


## Where the biomes' outlines are measured from: pushed around by two sizes of noise, so no border
## is an ellipse or a circle.
func _biome_warp(w: Vector2) -> Vector2:
	return WorldMap.biome_warp(w)  # (shared with the Biome autoload, so its cards follow the ground)


## True inside `inner`, false past `outer`, and in between a scatter of cells that thins out
## (clumped a little, so the edge breaks into patches rather than noise).
func _dither(w: Vector2, d: float, inner: float, outer: float) -> bool:
	if d <= inner:
		return true
	if d >= outer:
		return false
	var t := (d - inner) / (outer - inner)
	var clump := _edge.get_noise_2dv(w * 2.3) * 0.35 + _hash(w.floor()) * 0.65
	return clump > t * 0.9 + 0.05


## The field's patchwork: squares on a gently curving grid (the tracks bend with the land), most
## sown, some left to meadow; the outer ring of squares only partly sown.
func _crop_id(w: Vector2, q: Vector2) -> int:
	const CELL := 22.0
	const TRACK := 3.0
	var local := (w - WorldMap.FIELD_CENTER).rotated(0.35)
	local += Vector2(_swell.get_noise_2dv(w * 0.4), _swell.get_noise_2dv(w * 0.4 + Vector2(40, 0))) * 7.0
	var fu := fposmod(local.x, CELL)
	var fv := fposmod(local.y, CELL)
	if fu < TRACK or fv < TRACK:
		return PATH_TEXTURE
	var square := Vector2(floorf(local.x / CELL), floorf(local.y / CELL))
	var edge := smoothstep(WorldMap.FIELD_RADIUS - 30.0, WorldMap.FIELD_RADIUS - 6.0, q.distance_to(WorldMap.FIELD_CENTER))
	return WorldMap.TEX_CROP if _hash(square) < 0.75 - edge * 0.5 else WorldMap.TEX_FIELD


func _hash(p: Vector2) -> float:
	return fposmod(sin(p.dot(Vector2(127.1, 311.7))) * 43758.5453, 1.0)


## Flattens each forest glade to the height of its middle.
func _glades(h: PackedFloat32Array) -> void:
	for g in WorldMap.GLADES:
		var gh := _sample(h, g)
		var r := WorldMap.GLADE_RADIUS
		_for_pixels_near(g, r + 7.0, func(i: int, w: Vector2) -> void:
			h[i] = lerpf(gh, h[i], smoothstep(r, r + 7.0, w.distance_to(g))))


# --- routes -----------------------------------------------------------------------------------

## A graded route: samples about 1 m apart along a Catmull-Rom spline through `ctrl`, each with a
## road height (the ground along it, smoothed, then cut down wherever it would climb or fall
## faster than `grade`), a half width and a bank.
func _make_route(ctrl: Array, loop: bool, half: float, grade: float, smooth_m: float, h: PackedFloat32Array) -> Dictionary:
	var pts := WorldMap.spline(ctrl, loop)
	var n := pts.size()
	var dirs := PackedVector2Array()
	dirs.resize(n)
	for i in n:
		var a := pts[(i - 1 + n) % n] if loop else pts[maxi(i - 1, 0)]
		var b := pts[(i + 1) % n] if loop else pts[mini(i + 1, n - 1)]
		dirs[i] = (b - a).normalized()
	var ground := PackedFloat32Array()
	ground.resize(n)
	for i in n:
		var side := Vector2(-dirs[i].y, dirs[i].x) * half
		ground[i] = (_sample(h, pts[i]) + _sample(h, pts[i] + side) + _sample(h, pts[i] - side)) / 3.0
	var heights := _smooth(ground, int(smooth_m), loop)
	var g := grade
	if loop:
		_limit_grade(heights, pts, grade, loop)
	else:
		# both ends on the ground; a road that must climb further than its grade allows climbs
		# evenly a little steeper, instead of meeting the ground in a step
		var length := 0.0
		for i in range(1, n):
			length += pts[i].distance_to(pts[i - 1])
		g = maxf(grade, absf(ground[n - 1] - ground[0]) / maxf(length, 1.0) * 1.25)
		heights[0] = ground[0]
		heights[n - 1] = ground[n - 1]
		_clamp_grade(heights, pts, g)
	heights = _smooth(heights, 4, loop)
	if not loop:  # meet the ground (or the road it starts from) exactly at both ends
		heights[0] = ground[0]
		heights[n - 1] = ground[n - 1]
		_clamp_grade(heights, pts, g * 1.1)
	var halfs := PackedFloat32Array()
	halfs.resize(n)
	halfs.fill(half)
	var bank := PackedFloat32Array()
	bank.resize(n)
	return {"pts": pts, "dirs": dirs, "h": heights, "half": halfs, "bank": bank, "loop": loop}


func _smooth(a: PackedFloat32Array, radius: int, loop: bool) -> PackedFloat32Array:
	var n := a.size()
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var sum := 0.0
		var count := 0
		for k in range(-radius, radius + 1):
			var j := i + k
			if loop:
				j = posmod(j, n)
			elif j < 0 or j >= n:
				continue
			sum += a[j]
			count += 1
		out[i] = sum / count
	return out


## Keeps every step along an open route within `grade`, up or down, from its two pinned ends
## inward: hills are cut and hollows filled about evenly.
func _clamp_grade(a: PackedFloat32Array, pts: PackedVector2Array, grade: float) -> void:
	var n := a.size()
	for _pass in 64:
		var changed := false
		for dir in [1, -1]:
			for k in range(1, n - 1):
				var i: int = k if dir == 1 else n - 1 - k
				var prev: int = i - dir
				var d := grade * pts[i].distance_to(pts[prev])
				var v := clampf(a[i], a[prev] - d, a[prev] + d)
				if absf(v - a[i]) > 0.001:
					a[i] = v
					changed = true
		if not changed:
			return


## Lowers the route wherever it climbs faster than `grade` in either direction: hills become
## cuttings, and valleys keep their depth with the road easing down into them.
func _limit_grade(a: PackedFloat32Array, pts: PackedVector2Array, grade: float, loop: bool) -> void:
	var n := a.size()
	for _pass in 64:
		var changed := false
		for dir in [1, -1]:
			for k in range(1, n + (n if loop else 0)):
				var i: int = posmod(k * dir, n) if loop else (k if dir == 1 else n - 1 - k)
				var prev: int = posmod(i - dir, n) if loop else i - dir
				if prev < 0 or prev >= n:
					continue
				var limit := a[prev] + grade * pts[i].distance_to(pts[prev])
				if a[i] > limit + 0.001:
					a[i] = limit
					changed = true
		if not changed:
			return


## Lays the route into the terrain: flat (or banked) across its width, with shoulders that ease
## into the ground over `gentle` m, sheer walls where it cuts deeper than `wall_cut`, and
## embankments where it runs above the ground (only if `fill`). Paints `tex` across its width.
func _apply_route(r: Dictionary, h: PackedFloat32Array, ids: PackedByteArray, tex: int,
		shoulder: float, wall_cut: float, gentle: float, fill: bool) -> void:
	var pts: PackedVector2Array = r["pts"]
	var dirs: PackedVector2Array = r["dirs"]
	var half: PackedFloat32Array = r["half"]
	var nearest: Dictionary[int, Vector3] = {}  # pixel -> (distance, sample, lateral offset)
	for s in pts.size():
		var p := pts[s]
		var left := Vector2(-dirs[s].y, dirs[s].x)
		_for_pixels_near(p, half[s] + shoulder, func(i: int, w: Vector2) -> void:
			var off := w - p
			var d := off.length()
			if not nearest.has(i) or d < nearest[i].x:
				nearest[i] = Vector3(d, s, off.dot(left)))
	var heights: PackedFloat32Array = r["h"]
	var bank: PackedFloat32Array = r["bank"]
	for i in nearest:
		var v := nearest[i]
		var s := int(v.y)
		var hw := half[s]
		var road := heights[s] + bank[s] * clampf(v.z / hw, -1.0, 1.0)
		var w := _world(i % SIZE, i / SIZE)
		if _in_pit(w) or _creek_mask[i] == 1:
			continue  # the quarry keeps its walls; the creek runs on under a path (a ford)
		if v.x <= hw:
			h[i] = road
			if tex == WorldMap.TEX_ROAD or ids[i] != WorldMap.TEX_ROAD:
				ids[i] = tex
			continue
		var e := v.x - hw
		var diff := h[i] - road
		if diff < 0.0 and not fill:
			continue
		var width := (1.0 if diff > wall_cut else clampf(diff * 2.4, gentle, shoulder)) if diff > 0.0 				else clampf(-diff * 1.5, 2.0, shoulder)
		h[i] = lerpf(road, h[i], smoothstep(0.0, width, e))


func _in_pit(w: Vector2) -> bool:
	return w.distance_to(WorldMap.QUARRY_CENTER) < WorldMap.QUARRY_WALLS[0] + 2.0


func _nearest_sample(r: Dictionary, to: Vector2) -> int:
	var pts: PackedVector2Array = r["pts"]
	var best := 0
	for i in pts.size():
		if pts[i].distance_squared_to(to) < pts[best].distance_squared_to(to):
			best = i
	return best


# --- protecting hand-placed nodes -------------------------------------------------------------

## Where everything placed by hand in main.tscn stands (ruins, buildings, props, water), leaving
## out the biome scenes and the resource nodes.
func _baked_points() -> Array[Vector2]:
	var scene := load("res://scenes/main.tscn") as PackedScene
	var main := scene.instantiate()
	var out: Array[Vector2] = []
	_collect(main, Transform3D.IDENTITY, 0, out)
	main.free()
	return out


func _collect(node: Node, xform: Transform3D, depth: int, out: Array[Vector2]) -> void:
	for child in node.get_children():
		if not child is Node3D or child is Terrain3D or child is Light3D or child.name == "Scenery":
			continue
		if child.scene_file_path.begins_with(BIOME_SCENES) or child.name == "Nodes":
			continue  # built on the new ground at runtime / moved onto it by _rebake_nodes
		var t := xform * (child as Node3D).transform
		out.append(Vector2(t.origin.x, t.origin.z))
		if depth < 2:
			_collect(child, t, depth + 1, out)


## The creek's channel along its vale: a rounded bed under the water (deeper in the pools), soft
## banks easing up to the ground. Level water the whole way, so the bed only ever goes down.
func _carve_creek(h: PackedFloat32Array) -> void:
	var pts := WorldMap.creek()
	var half := WorldMap.CREEK_HALF_WIDTH
	var nearest: Dictionary[int, float] = {}
	for p in pts:
		_for_pixels_near(p, half + CREEK_BANK, func(i: int, w: Vector2) -> void:
			var d := w.distance_to(p)
			if d < nearest.get(i, INF):
				nearest[i] = d)
	_creek_mask.resize(SIZE * SIZE)
	for i in nearest:
		var d: float = nearest[i]
		var w := _world(i % SIZE, i / SIZE)
		if d < half + 2.5:
			_creek_mask[i] = 1
		if d < half:
			var depth := CREEK_DEPTH
			for pool in WorldMap.CREEK_POOLS:
				depth = lerpf(depth, CREEK_POOL_DEPTH, 1.0 - smoothstep(0.0, WorldMap.CREEK_POOL_RADIUS, w.distance_to(pool)))
			var u := d / half
			h[i] = minf(h[i], WATER_LEVEL - depth * (1.0 - u * u))
		else:
			var t := smoothstep(half, half + CREEK_BANK, d)
			var bank := WATER_LEVEL + 0.1 + (d - half) * 0.15
			h[i] = minf(h[i], lerpf(bank, h[i], t))


## Lays WorldMap.ROADS in order: each along its fixed line or a least-cost route over the land,
## graded, then pressed into the ground with sloped shoulders. Returns {id: laid route}.
func _lay_roads(h: PackedFloat32Array, ids: PackedByteArray, baked: Array[Vector2]) -> Dictionary:
	var grid := _road_grid(h, baked)
	var laid := {}
	for spec in WorldMap.ROADS:
		var ctrl: Array = spec.get("ctrl", [])
		if ctrl.is_empty():
			var from: Vector2 = spec["from"]
			var to: Vector2 = spec["to"]
			if spec.has("join"):
				from = _nearest_on(laid[spec["join"]], from)
			if spec.has("join_end"):
				to = _nearest_on(laid[spec["join_end"]], to)
			var stops: Array = [from] + spec.get("via", []) + [to]
			ctrl = []
			for k in stops.size() - 1:
				var leg := _route(grid, stops[k], stops[k + 1])
				ctrl.append_array(leg if k == 0 else leg.slice(1))
		var road: bool = spec["kind"] == &"road"
		var half := WorldMap.ROAD_HALF_WIDTH if road else WorldMap.PATH_HALF_WIDTH
		var before := h.duplicate()
		var r := _make_route(ctrl, false, half, ROAD_GRADE if road else PATH_GRADE, 24.0 if road else 10.0, h)
		_apply_route(r, h, ids, WorldMap.TEX_ROAD if road else PATH_TEXTURE,
				ROAD_SHOULDER if road else PATH_SHOULDER, 99.0, 10.0 if road else 6.0, true)
		laid[spec["id"]] = r
		_report_road(spec, r, before)
	return laid


## The router's grid: one cell per ROUTE_CELL m, weighted by how hard the ground is to build on.
func _road_grid(h: PackedFloat32Array, baked: Array[Vector2]) -> AStarGrid2D:
	var n := SIZE / ROUTE_CELL
	var grid := AStarGrid2D.new()
	grid.region = Rect2i(0, 0, n, n)
	grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	grid.update()
	for cy in n:
		for cx in n:
			var w := _cell_world(Vector2i(cx, cy))
			var r := ROUTE_CELL * 0.5
			var g := Vector2(_sample(h, w + Vector2(r, 0)) - _sample(h, w - Vector2(r, 0)),
					_sample(h, w + Vector2(0, r)) - _sample(h, w - Vector2(0, r))).length() / ROUTE_CELL
			var cost := 1.0 + ROUTE_SLOPE_COST * g * g
			# (under the water line: the bowl's floor and the flats sit at 0, just above it)
			if _sample(h, w) < WATER_LEVEL - 0.05 and _creek_mask[_pixel(w)] == 0:
				cost += ROUTE_WATER_COST
			elif _creek_mask[_pixel(w)] == 1:
				cost += ROUTE_CREEK_COST  # (crossing it is fine: a bridge or a ford; running along it isn't)
			elif _polyline_distance(w, WorldMap.CREEK) < WorldMap.CREEK_HALF_WIDTH + CREEK_BANK:
				cost += ROUTE_BANK_COST
			if w.distance_to(WorldMap.QUARRY_CENTER) < WorldMap.QUARRY_WALLS[0] + 1.0:
				cost += ROUTE_WATER_COST
			cost += _rim(w) * 4.0
			grid.set_point_weight_scale(Vector2i(cx, cy), cost)
	for p in baked:
		var c := _world_cell(p)
		if grid.is_in_boundsv(c):
			grid.set_point_weight_scale(c, grid.get_point_weight_scale(c) + ROUTE_WATER_COST)
	return grid


## The cheapest way from `from` to `to`, as spline control points about three cells apart, with
## both ends exact.
func _route(grid: AStarGrid2D, from: Vector2, to: Vector2) -> Array:
	var cells := grid.get_id_path(_world_cell(from), _world_cell(to))
	var ctrl: Array = [from]
	for k in range(3, cells.size() - 2, 3):
		ctrl.append(_cell_world(cells[k]))
	ctrl.append(to)
	return ctrl


func _cell_world(c: Vector2i) -> Vector2:
	return Vector2(ORIGIN.x + (c.x + 0.5) * ROUTE_CELL, ORIGIN.z + (c.y + 0.5) * ROUTE_CELL)


func _world_cell(w: Vector2) -> Vector2i:
	return Vector2i(floori((w.x - ORIGIN.x) / ROUTE_CELL), floori((w.y - ORIGIN.z) / ROUTE_CELL))


func _pixel(w: Vector2) -> int:
	return clampi(int(w.y - ORIGIN.z), 0, SIZE - 1) * SIZE + clampi(int(w.x - ORIGIN.x), 0, SIZE - 1)


func _nearest_on(r: Dictionary, to: Vector2) -> Vector2:
	return r["pts"][_nearest_sample(r, to)]


## The roads' lines as laid, for the game: a GDScript file of constants (exports leave out plain
## data files), WorldMap.roads() reads it.
func _write_roads(laid: Dictionary) -> void:
	var lines := PackedStringArray()
	lines.append("extends RefCounted")
	lines.append("## Written by tools/generate_test_terrain.gd: the lines the roads were laid on (WorldMap.roads()).")
	lines.append("## Don't edit by hand; change WorldMap.ROADS and regenerate.")
	lines.append("")
	lines.append("const LINES := {")
	for spec in WorldMap.ROADS:
		var pts: PackedVector2Array = laid[spec["id"]]["pts"].duplicate()
		if spec.get("reverse", false):
			pts.reverse()
		var nums := PackedStringArray()
		for p in pts:
			nums.append("Vector2(%.2f, %.2f)" % [p.x, p.y])
		lines.append("\t&\"%s\": [%s]," % [spec["id"], ", ".join(nums)])
	lines.append("}")
	lines.append("")
	var f := FileAccess.open(ROADS_OUT, FileAccess.WRITE)
	f.store_string("\n".join(lines))
	f.close()


## Rewrites the Y of main.tscn's resource nodes (children of "Nodes") to the new ground: a text
## edit of their `position` lines only, so nothing else in the scene is touched.
func _rebake_nodes(h: PackedFloat32Array) -> void:
	const KEY := "\nposition = Vector3("
	var blocks := FileAccess.get_file_as_string(MAIN_SCENE).split("\n[node ")
	var moved := 0
	for b in range(1, blocks.size()):
		var block := blocks[b]
		var at := block.find(KEY)
		if not block.contains("parent=\"Nodes\"") or at < 0:
			continue
		var start := at + KEY.length()
		var end := block.find(")", start)
		var xyz := block.substr(start, end - start).split(",")
		var x := xyz[0].strip_edges()
		var z := xyz[2].strip_edges()
		var y := snappedf(_sample(h, Vector2(x.to_float(), z.to_float())), 0.01)
		if absf(y - xyz[1].strip_edges().to_float()) < 0.005:
			continue
		moved += 1
		var ys := str(int(y)) if y == roundf(y) else str(y)
		blocks[b] = block.substr(0, start) + "%s, %s, %s" % [x, ys, z] + block.substr(end)
	var f := FileAccess.open(MAIN_SCENE, FileAccess.WRITE)
	f.store_string("\n[node ".join(blocks))
	f.close()
	print("Resource nodes in main.tscn: %d moved onto the new ground" % moved)


# --- helpers ----------------------------------------------------------------------------------

## Calls fn(pixel index, pixel world position) for every pixel within `radius` of `at`.
func _for_pixels_near(at: Vector2, radius: float, fn: Callable) -> void:
	var cx := at.x - ORIGIN.x
	var cy := at.y - ORIGIN.z
	for y in range(maxi(0, floori(cy - radius)), mini(SIZE, ceili(cy + radius) + 1)):
		for x in range(maxi(0, floori(cx - radius)), mini(SIZE, ceili(cx + radius) + 1)):
			var w := _world(x, y)
			if w.distance_to(at) <= radius:
				fn.call(y * SIZE + x, w)


## Bilinear height from the buffer at a world position.
func _sample(h: PackedFloat32Array, w: Vector2) -> float:
	var fx := clampf(w.x - ORIGIN.x, 0.0, SIZE - 1.001)
	var fy := clampf(w.y - ORIGIN.z, 0.0, SIZE - 1.001)
	var x := int(fx)
	var y := int(fy)
	var tx := fx - x
	var ty := fy - y
	var top := lerpf(h[y * SIZE + x], h[y * SIZE + x + 1], tx)
	var bottom := lerpf(h[(y + 1) * SIZE + x], h[(y + 1) * SIZE + x + 1], tx)
	return lerpf(top, bottom, ty)


func _on_path(w: Vector2) -> bool:
	if absf(w.distance_to(VILLAGE_CENTER) - RING_RADIUS) < RING_HALF_WIDTH:
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


## 1 at `center`, smoothly 0 at `radius`.
func _bump(w: Vector2, center: Vector2, radius: float) -> float:
	return 1.0 - smoothstep(0.0, radius, w.distance_to(center))


# --- reports ----------------------------------------------------------------------------------

## A road's length, steepest grade and deepest cutting (how far below the old ground it runs).
func _report_road(spec: Dictionary, r: Dictionary, before: PackedFloat32Array) -> void:
	var pts: PackedVector2Array = r["pts"]
	var heights: PackedFloat32Array = r["h"]
	var length := 0.0
	var steepest := 0.0
	var cut := 0.0
	var cut_at := Vector2.ZERO
	for i in pts.size():
		if _sample(before, pts[i]) - heights[i] > cut:
			cut = _sample(before, pts[i]) - heights[i]
			cut_at = pts[i]
		if i > 0:
			var d := pts[i].distance_to(pts[i - 1])
			length += d
			steepest = maxf(steepest, absf(heights[i] - heights[i - 1]) / maxf(d, 0.01))
	print("%-14s %4.0f m, steepest grade %.3f, deepest cut %.1f m (at %s)" % [spec["id"], length, steepest, cut, cut_at.round()])


## Lists hand-placed things (not the resource nodes: _rebake_nodes moves those) whose ground isn't
## at height 0: they were placed on the flats.
func _report_moved(points: Array[Vector2], h: PackedFloat32Array) -> void:
	var moved := 0
	for p in points:
		var g := _sample(h, p)
		if absf(g) > MOVED_TOLERANCE and not _in_water(p):
			moved += 1
			print("  ground at %.2f m under the thing at (%.1f, %.1f)" % [g, p.x, p.y])
	print("Hand-placed things: %d checked, %d off the flats" % [points.size(), moved])


func _in_water(p: Vector2) -> bool:
	for pond in PONDS:
		if p.distance_to(pond["center"]) < float(pond["radius"]) + 2.0:
			return true
	return false


## How steep the land is, leaving out the peak and the rim: shares of the cells by slope, and
## the sheer ones off the roads and the quarry pit.
func _report_slopes(h: PackedFloat32Array, ids: PackedByteArray) -> void:
	var counts := [0, 0, 0, 0]  # < 15°, < 30°, < 45°, steeper
	var sheer := 0
	var total := 0
	for y in SIZE - 1:
		for x in SIZE - 1:
			var w := _world(x, y)
			if w.distance_to(PEAK_CENTER) < PEAK_RADIUS or _rim(w) > 2.0:
				continue
			var i := y * SIZE + x
			var g := Vector2(h[i + 1] - h[i], h[i + SIZE] - h[i]).length()
			counts[0 if g < 0.268 else 1 if g < 0.577 else 2 if g < 1.0 else 3] += 1
			total += 1
			if g > 2.0 and ids[i] != WorldMap.TEX_ROAD and not _in_pit(w):
				sheer += 1
	print("Slopes (outside peak and rim): %.1f%% under 15°, %.1f%% 15-30°, %.1f%% 30-45°, %.1f%% steeper; %d sheer cells off the roads and the pit" % [
			100.0 * counts[0] / total, 100.0 * counts[1] / total, 100.0 * counts[2] / total,
			100.0 * counts[3] / total, sheer])


## A top-down picture of the result: one colour per surface id, shaded by slope.
func _write_preview(path: String, h: PackedFloat32Array, ids: PackedByteArray) -> void:
	var colors := {
		WorldMap.TEX_DEFAULT: Color(0.40, 0.58, 0.32), PATH_TEXTURE: Color(0.66, 0.52, 0.38),
		WorldMap.TEX_ROAD: Color(0.85, 0.83, 0.78), WorldMap.TEX_FOREST: Color(0.18, 0.36, 0.20),
		WorldMap.TEX_FIELD: Color(0.60, 0.70, 0.32), WorldMap.TEX_QUARRY: Color(0.70, 0.66, 0.60),
		WorldMap.TEX_CROP: Color(0.88, 0.74, 0.36),
	}
	var img := Image.create_empty(SIZE, SIZE, false, Image.FORMAT_RGB8)
	for y in SIZE:
		for x in SIZE:
			var i := y * SIZE + x
			var c: Color = colors.get(ids[i], Color.MAGENTA)
			var hx := h[mini(i + 1, h.size() - 1)] - h[i]
			var hy := h[mini(i + SIZE, h.size() - 1)] - h[i]
			var light := clampf(1.0 - (hx + hy) * 0.35, 0.35, 1.4)
			if h[i] < WATER_LEVEL:
				c = Color(0.25, 0.45, 0.65)
			if absf(hx) > 2.0 or absf(hy) > 2.0:
				c = Color(0.25, 0.22, 0.2)  # sheer drops
			img.set_pixel(x, y, c * light)
	img.save_png(path)
	print("Preview written to ", path)
