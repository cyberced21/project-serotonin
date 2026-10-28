extends SceneTree
## Generates the terrain into res://terrain_data. Run headless from the project folder:
##   godot --headless --path . -s res://tools/generate_test_terrain.gd
## Add `-- --preview=<file.png>` to also write a top-down map of the result (surface ids, shaded).
## WARNING: overwrites any sculpting you've done in res://terrain_data.
##
## Layout (plans/world.md): one rolling land, broad warped hills with soft crests, that eases
## down into the places instead of having them stamped on. The clearing (where the trees, rocks
## and ruins sit, at height 0), the village to the east and the lake basin to the south are
## flats whose edges wander outward, joined by shallow valleys along the dirt paths between them.
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

const SIZE := 512                       # heightmap pixels = metres (vertex spacing 1); 2x2 regions
const ORIGIN := Vector3(-256, 0, -256)  # world position of pixel (0, 0) — must sit on the region grid
const CLEARING_CENTER := Vector2(0, -4)
const CLEARING_RADIUS := 28.0
const HILL_RAMP := 55.0                 # metres over which the hills rise out of the clearing
## The flats' edges wander outward by up to this much (never inward: what's placed on them stays
## on flat ground).
const FLAT_GROW := 14.0
## The hills: broad, rounded, warped so nothing reads as a circle. Height = HILL_BASE + up to
## HILL_RANGE, eased down to the flats.
const HILL_BASE := 3.0
const HILL_RANGE := 17.0
const WARP := 38.0                      # how far (m) the hills' noise is pushed around
## Between the places the paths run along valleys: the hills keep this share of their height on
## the valley floor, easing back to full over VALLEY_RAMP.
const VALLEY_FLOOR := 0.22
const VALLEY_HALF := 5.0
const VALLEY_RAMP := 42.0
## The creek (WorldMap.CREEK) runs down a vale of its own: the hills keep this share of their
## height along it, easing back over CREEK_VALE. Its channel is CREEK_DEPTH deep under the water
## (CREEK_POOL_DEPTH in the pools), and its banks ease up over CREEK_BANK.
const CREEK_VALE_FLOOR := 0.05
const CREEK_VALE := 48.0
const CREEK_DEPTH := 0.55
const CREEK_POOL_DEPTH := 1.2
const CREEK_BANK := 8.0
## The world's edge rises into higher hills so the valley feels closed in, not cut off.
const RIM_WIDTH := 95.0
const RIM_HEIGHT := 24.0
## Frostpeak: one broad mountain, not a cone.
const PEAK_CENTER := Vector2(-92, -92)
const PEAK_RADIUS := 80.0
const PEAK_HEIGHT := 40.0
## Steepest rise per metre the relax pass leaves between neighbouring cells, along x or z (so
## diagonally at most ~0.64, about 32°). Not in the quarry pit; Frostpeak's top may be steeper by
## up to PEAK_SLOPE.
const MAX_SLOPE := 0.45
const PEAK_SLOPE := 0.6
const RELAX_PASSES := 80
const DATA_DIR := "res://terrain_data"
const WATER_LEVEL := -0.15     # keep in sync with the ponds' WaterBody nodes in main.tscn
## Ponds: centre, radius (roughly where the bed rises to the water line), deepest point below
## the water line (wading depth — no swimming). Keep in sync with the ponds in main.tscn.
const PONDS := [
	{"center": Vector2(20, 16), "radius": 9.0, "depth": 0.95},   # the clearing's pond
	{"center": Vector2(88, 64), "radius": 7.0, "depth": 0.75},   # the village pond
	{"center": Vector2(-16, 76), "radius": 14.0, "depth": 1.35},  # the lake
]
## The lake's flat basin (hills ease up beyond radius over the ramp).
const LAKE_BASIN := {"center": Vector2(-16, 74), "radius": 26.0, "ramp": 50.0}
## The path from the clearing south over the hills to the lake shore.
const LAKE_PATH := [Vector2(-3, 16), Vector2(-6, 32), Vector2(-11, 48), Vector2(-15, 59)]

const VILLAGE_CENTER := Vector2(100, 40)  # the middle of the village square
const VILLAGE_RADIUS := 36.0
const VILLAGE_RAMP := 50.0
## Control-map texture id that marks the path (see shaders/terrain.gdshader, footsteps.gd).
const PATH_TEXTURE := WorldMap.TEX_PATH
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

## The quarry's haul road: each ramp runs along the inside of a wall, this wide, climbing one
## level over RAMP_LENGTH metres; the next ramp down starts RAMP_GAP metres further round.
const RAMP_WIDTH := 4.5
const RAMP_LENGTH := 38.0
const RAMP_GAP := 4.0
## Mantle stairs: two places on every wall where it drops in three steps instead of one, each
## step LEDGE deep (5 m / 3 = 1.67 m high, within a mantle's reach), STAIR_WIDTH wide.
const LEDGE := 1.6
const STAIR_WIDTH := 6.0

## The ring road: steepest grade, and how far the outer edge is raised on the tightest bends.
const ROAD_GRADE := 0.08
const BANK := 0.5          # each edge moves this far (m) from the centre line
const BANK_RADIUS := 60.0  # bends tighter than this get banked, fully by half of it
## Where a road cuts this deep into a hill, its sides are sheer (wall-runnable) instead of sloped.
const WALL_CUT := 2.5
const GULLY_DEPTH := 4.0
const GULLY_GAP := 6.0     # length of the gap along the road
const GULLY_REACH := 30.0  # how far the gully runs out to either side before it's level again

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

	var ring := _make_route(WorldMap.RING, true, WorldMap.ROAD_HALF_WIDTH, ROAD_GRADE, 40.0, h)
	_bank(ring)
	var gully := _nearest_sample(ring, WorldMap.GULLY_NEAR)
	_widen(ring, gully)
	_apply_route(ring, h, ids, WorldMap.TEX_ROAD, 20.0, WALL_CUT, 6.0, true)
	_gully(ring, gully, h, ids)
	for spur in WorldMap.SPURS:
		var pts: Array = spur.duplicate()
		pts[0] = ring["pts"][_nearest_sample(ring, pts[0])]
		_apply_route(_make_route(pts, false, 2.0, 0.10, 20.0, h), h, ids, WorldMap.TEX_ROAD, 16.0, WALL_CUT, 6.0, true)
	var q := WorldMap.QUARRY_CENTER
	var rim := q + Vector2.from_angle(WorldMap.QUARRY_ROAD_ANGLE) * (WorldMap.QUARRY_WALLS[0] + 2.0)
	var to_quarry := [ring["pts"][_nearest_sample(ring, rim)], rim]
	_apply_route(_make_route(to_quarry, false, 2.0, 0.10, 6.0, h), h, ids, WorldMap.TEX_ROAD, 8.0, WALL_CUT, 4.0, false)
	var trail: Array = WorldMap.TRAIL.duplicate()
	trail[trail.size() - 1] = ring["pts"][_nearest_sample(ring, trail[trail.size() - 1])]
	_apply_route(_make_route(trail, false, 1.5, 0.15, 14.0, h), h, ids, PATH_TEXTURE, 8.0, 99.0, 5.0, true)

	var baked := _baked_points()

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
	_report_path_slope(terrain)
	_report_ring(ring)
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
	for path in [PATH, LAKE_PATH]:
		var v := smoothstep(VALLEY_HALF, VALLEY_HALF + VALLEY_RAMP, _polyline_distance(w, path))
		outside *= lerpf(VALLEY_FLOOR, 1.0, v)
	var c := smoothstep(WorldMap.CREEK_HALF_WIDTH, CREEK_VALE, _polyline_distance(w, WorldMap.CREEK))
	outside *= lerpf(CREEK_VALE_FLOOR, 1.0, c)
	var h := outside * _hills(w)
	for pond in PONDS:
		h = _pond(w, h, pond, _shore)
	return h


## 0 on a place's flat (its edge wandering out by up to FLAT_GROW), easing to 1 over `ramp`.
func _rise(w: Vector2, center: Vector2, radius: float, ramp: float) -> float:
	var grow := (_warp_x.get_noise_2dv(w * 2.5) * 0.5 + 0.5) * FLAT_GROW
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


## Frostpeak: a broad mountain whose flanks wander (a warped distance), steepest near the top.
func _peak(w: Vector2) -> float:
	var q := w + Vector2(_warp_y.get_noise_2dv(w * 1.7), _warp_x.get_noise_2dv(w * 1.7)) * 22.0
	var t := 1.0 - clampf(q.distance_to(PEAK_CENTER) / PEAK_RADIUS, 0.0, 1.0)
	return PEAK_HEIGHT * t * t * (3.0 - 2.0 * t) * (0.85 + 0.15 * _noise.get_noise_2dv(w * 3.0))


## The edge of the world rising into high hills (wandering, so it isn't a straight wall).
func _rim(w: Vector2) -> float:
	var half := SIZE * 0.5
	var inner := half - RIM_WIDTH
	var c := (w - Vector2(ORIGIN.x + half, ORIGIN.z + half)).abs()
	var past := Vector2(maxf(c.x - inner, 0.0), maxf(c.y - inner, 0.0)).length()  # rounded corners
	past += _warp_x.get_noise_2dv(w * 1.3) * 18.0
	var t := clampf(past / RIM_WIDTH, 0.0, 1.0)
	return RIM_HEIGHT * t * t


## Eases every slope steeper than MAX_SLOPE back toward it, a little at a time from both sides, so
## the hills keep their shape but lose their ledges. The flats stay put: nothing there is steep.
func _relax(h: PackedFloat32Array) -> void:
	var limit := PackedFloat32Array()  # per cell; 0 = leave it alone
	limit.resize(SIZE * SIZE)
	for y in SIZE:
		for x in SIZE:
			var w := _world(x, y)
			var crags := 1.0 - smoothstep(PEAK_RADIUS * 0.15, PEAK_RADIUS * 0.6, w.distance_to(PEAK_CENTER))
			limit[y * SIZE + x] = 0.0 if _in_pit(w) else MAX_SLOPE + crags * PEAK_SLOPE
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
	elif d < outer + WorldMap.QUARRY_SLOPE:
		h = lerpf(WorldMap.QUARRY_RIM_HEIGHT, h, smoothstep(outer, outer + WorldMap.QUARRY_SLOPE, d))
	var fd := w.distance_to(WorldMap.FIELD_CENTER) + _edge.get_noise_2dv(w) * 8.0
	var inside := 1.0 - smoothstep(WorldMap.FIELD_RADIUS, WorldMap.FIELD_RADIUS + WorldMap.FIELD_RAMP, fd)
	if inside > 0.0:
		h = lerpf(h, 0.8 + (_swell.get_noise_2dv(w) * 0.5 + 0.5) * 3.5, inside)
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


## 1 on the outer side of wall i, 0 on the inner side; in between on its ramp and stairs.
func _wall_step(i: int, dn: float, theta: float) -> float:
	var b: float = WorldMap.QUARRY_WALLS[i]
	var s := _sharp(dn - b)
	if dn > b - RAMP_WIDTH and dn <= b:
		var t := _ramp_t(i, theta)
		if t >= 0.0:
			return t
	for a in _stair_angles(i):
		if absf(angle_difference(theta, a)) * b < STAIR_WIDTH * 0.5:
			return (_sharp(dn - b + 2.0 * LEDGE) + _sharp(dn - b + LEDGE) + s) / 3.0
	return s


## A drop over a single vertex, so walls come out sheer enough to wall-run.
func _sharp(x: float) -> float:
	return smoothstep(-0.2, 0.2, x)


## How far up wall i's ramp `theta` is (0 bottom, 1 top), or -1 off the ramp.
func _ramp_t(i: int, theta: float) -> float:
	var a := fposmod(theta - (_ramp_top[i] - _ramp_span[i]), TAU)
	return a / _ramp_span[i] if a <= _ramp_span[i] else -1.0


## The two mantle stairs on wall i, spread round the part of the wall the ramp doesn't use.
func _stair_angles(i: int) -> Array[float]:
	var rest := TAU - _ramp_span[i]
	return [_ramp_top[i] + rest / 3.0, _ramp_top[i] + rest * 2.0 / 3.0]


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
	var ragged := _edge.get_noise_2dv(w)
	var qd := w.distance_to(WorldMap.QUARRY_CENTER)
	var pit: float = WorldMap.QUARRY_WALLS[0]
	if qd < pit + WorldMap.QUARRY_APRON + 4.0 + ragged * 4.0:
		return PATH_TEXTURE if qd < pit + 1.0 and _on_haul_road(w) else WorldMap.TEX_QUARRY
	var fd := w.distance_to(WorldMap.FIELD_CENTER) + ragged * 8.0
	if fd < WorldMap.FIELD_RADIUS - 4.0:
		return _crop_id(w)
	if fd < WorldMap.FIELD_RADIUS + 10.0:
		return WorldMap.TEX_FIELD
	var f := (w - WorldMap.FOREST_CENTER) / WorldMap.FOREST_RADII
	if f.length_squared() + ragged * 0.3 < 1.0 and qd > pit + WorldMap.QUARRY_APRON + WorldMap.QUARRY_SLOPE \
			and w.distance_to(Vector2(-92, -92)) > 35.0:
		return WorldMap.TEX_FOREST
	return WorldMap.TEX_DEFAULT


## The field's patchwork: a tilted grid of squares, most sown, split by dirt tracks.
func _crop_id(w: Vector2) -> int:
	const CELL := 22.0
	const TRACK := 3.0
	var local := (w - WorldMap.FIELD_CENTER).rotated(0.35)
	var fu := fposmod(local.x, CELL)
	var fv := fposmod(local.y, CELL)
	if fu < TRACK or fv < TRACK:
		return PATH_TEXTURE
	var square := Vector2(floorf(local.x / CELL), floorf(local.y / CELL))
	return WorldMap.TEX_CROP if _hash(square) < 0.7 else WorldMap.TEX_FIELD


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
	_limit_grade(heights, pts, grade, loop)
	heights = _smooth(heights, 4, loop)
	if not loop:  # meet the ground (or the road it starts from) exactly at both ends
		for i in n:
			var from_end := minf(i, n - 1 - i)
			heights[i] = lerpf(ground[i], heights[i], smoothstep(0.0, 8.0, from_end))
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


## Banks the tight bends: the outer edge up, the inner edge down.
func _bank(r: Dictionary) -> void:
	var dirs: PackedVector2Array = r["dirs"]
	var n := dirs.size()
	var bank: PackedFloat32Array = r["bank"]
	for i in n:
		var turn := angle_difference(dirs[posmod(i - 6, n)].angle(), dirs[(i + 6) % n].angle()) / 12.0
		var radius := 1.0 / absf(turn) if absf(turn) > 0.0001 else INF
		# lateral offsets are measured to the left; a left turn (turn > 0) raises the right edge
		bank[i] = -signf(turn) * clampf((BANK_RADIUS - radius) / (BANK_RADIUS * 0.5), 0.0, 1.0) * BANK
	r["bank"] = _smooth(bank, 10, true)


## Doubles the road's width around the gully, so there's room for both the bridge and the gap.
func _widen(r: Dictionary, at: int) -> void:
	var half: PackedFloat32Array = r["half"]
	var bank: PackedFloat32Array = r["bank"]
	var n := half.size()
	for i in n:
		var k := absi(i - at)
		k = mini(k, n - k)
		var t := 1.0 - smoothstep(8.0, 18.0, k)
		half[i] += WorldMap.ROAD_HALF_WIDTH * t
		bank[i] *= 1.0 - t


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
		if _in_pit(w):
			continue  # the quarry keeps its walls
		if v.x <= hw:
			h[i] = road
			if tex == WorldMap.TEX_ROAD or ids[i] != WorldMap.TEX_ROAD:
				ids[i] = tex
			continue
		var e := v.x - hw
		var diff := h[i] - road
		if diff < 0.0 and not fill:
			continue
		var width := (1.0 if diff > wall_cut else gentle) if diff > 0.0 else clampf(-diff * 1.5, 2.0, shoulder)
		h[i] = lerpf(road, h[i], smoothstep(0.0, width, e))


func _in_pit(w: Vector2) -> bool:
	return w.distance_to(WorldMap.QUARRY_CENTER) < WorldMap.QUARRY_WALLS[0] + 2.0


## A gully across the road: the left half of the road stays on an earth bridge, the right half
## is a sheer-sided gap to jump or dash. Fall in and the gully floor rises out at either end.
func _gully(r: Dictionary, at: int, h: PackedFloat32Array, ids: PackedByteArray) -> void:
	var p: Vector2 = r["pts"][at]
	var along_dir: Vector2 = r["dirs"][at]
	var left := Vector2(-along_dir.y, along_dir.x)
	var road: float = r["h"][at]
	var bridge: float = r["half"][at]
	_for_pixels_near(p, GULLY_REACH + 2.0, func(i: int, w: Vector2) -> void:
		var off := w - p
		var lat := off.dot(left)
		if absf(off.dot(along_dir)) > GULLY_GAP * 0.5 or (lat >= 0.0 and lat <= bridge + 0.2):
			return
		var depth := GULLY_DEPTH * (1.0 - smoothstep(GULLY_REACH * 0.5, GULLY_REACH, absf(lat)))
		if depth > 0.0 and h[i] > road - depth:
			h[i] = road - depth
			if ids[i] == WorldMap.TEX_ROAD:
				ids[i] = WorldMap.TEX_DEFAULT)


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
	for i in nearest:
		var d: float = nearest[i]
		var w := _world(i % SIZE, i / SIZE)
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
	if w.distance_to(VILLAGE_CENTER) < SQUARE_RADIUS:
		return true
	if _polyline_distance(w, PATH) < PATH_HALF_WIDTH or _polyline_distance(w, LAKE_PATH) < PATH_HALF_WIDTH:
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


func _report_ring(r: Dictionary) -> void:
	var pts: PackedVector2Array = r["pts"]
	var heights: PackedFloat32Array = r["h"]
	var bank: PackedFloat32Array = r["bank"]
	var length := 0.0
	var steepest := 0.0
	var banked := 0
	var n := pts.size()
	for i in n:
		var j := (i + 1) % n
		var d := pts[i].distance_to(pts[j])
		length += d
		steepest = maxf(steepest, absf(heights[j] - heights[i]) / maxf(d, 0.01))
		banked += 1 if absf(bank[i]) > 0.05 else 0
	print("Ring road: %.0f m long, %.1f to %.1f m high, steepest grade %.3f, %d m banked" % [
			length, Array(heights).min(), Array(heights).max(), steepest, banked])


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
