class_name ProcgenMap
extends RefCounted
## Builds a 512 × 512 m world from a seed, as arrays: height per pixel (metres), terrain texture
## id per pixel (WorldMap.TEX_*) and which biome cell each pixel is in. Pure data, no nodes, so it
## runs headless and can be previewed as an image. ProcgenWorld hands the result to Terrain3D.
##
## Layout: a flat hub at the origin where you spawn (the Clearing), a ring of biome cells round it,
## and a mountain rim along the edge so you never reach the end of the world. The cells are
## Voronoi cells (every spot belongs to the nearest site) on domain-warped coordinates, so their
## borders wander. The inner ring (tier 1) holds the gentler biomes, the outer ring (tier 2) the
## harder ones. Each biome has its own height profile; neighbours' profiles blend over the border.

const SIZE := 512                       # pixels = metres (vertex spacing 1)
const ORIGIN := Vector3(-256, 0, -256)  # world position of pixel (0, 0); on Terrain3D's region grid
const HUB_CENTER := Vector2.ZERO
const HUB_RADIUS := 28.0
## Metres over which the ground rises out of the hub.
const HUB_RAMP := 45.0
const BUMP_HEIGHT := 1.2
## The rim starts this far from the centre (a rounded square, warped) and is RIM_HEIGHT tall at the edge.
const RIM_START := 172.0
const RIM_HEIGHT := 62.0
const RIM_WARP := 22.0

## Biome sites: the inner ring's and the outer ring's biomes (each ring is shuffled per seed;
## the inner ring gets one more, a random repeat of its own), and how far out each ring sits.
const INNER_BIOMES: Array[StringName] = [&"pinewood", &"goldmeadow"]
const INNER_COUNT := 3
const INNER_RADIUS := Vector2(68.0, 92.0)
const OUTER_BIOMES: Array[StringName] = [&"quarry", &"frostpeak", &"stillwater", &"pinewood"]
const OUTER_RADIUS := Vector2(128.0, 150.0)
const MIN_SITE_GAP := 62.0
## How far the cell borders wander (m), and over how many metres neighbouring ground blends.
const CELL_WARP := 30.0
const BIOME_BLEND := 24.0
## Painted ground per biome; the rest keep the default (grass / dirt / rock / snow by slope and height).
const BIOME_TEXTURE := {&"pinewood": WorldMap.TEX_FOREST, &"goldmeadow": WorldMap.TEX_FIELD}
## In `cells`, a pixel up on the rim (no biome).
const RIM_CELL := 255

var seed := 0
var heights := PackedFloat32Array()
var ids := PackedByteArray()
## Index into `sites` per pixel, or RIM_CELL.
var cells := PackedByteArray()
## The biome cells: {biome: StringName, pos: Vector2, tier: int}. Site 0 is the hub.
var sites: Array[Dictionary] = []

var _hills := FastNoiseLite.new()
var _swell := FastNoiseLite.new()
var _bumps := FastNoiseLite.new()
var _rough := FastNoiseLite.new()
var _rim_warp := FastNoiseLite.new()
var _ridges := FastNoiseLite.new()
var _warp_x := FastNoiseLite.new()
var _warp_y := FastNoiseLite.new()
var _rng := RandomNumberGenerator.new()


func _init(world_seed: int) -> void:
	seed = world_seed
	_hills.seed = sub_seed(&"hills")
	_hills.frequency = 0.009
	_hills.fractal_octaves = 4
	_swell.seed = sub_seed(&"swell")
	_swell.frequency = 0.016
	_swell.fractal_octaves = 2
	_bumps.seed = sub_seed(&"bumps")
	_bumps.frequency = 0.07
	_rough.seed = sub_seed(&"rough")
	_rough.frequency = 0.035
	_rough.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	_rough.fractal_octaves = 3
	_rim_warp.seed = sub_seed(&"rim_warp")
	_rim_warp.frequency = 0.012
	_ridges.seed = sub_seed(&"ridges")
	_ridges.frequency = 0.02
	_ridges.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	_ridges.fractal_octaves = 3
	_warp_x.seed = sub_seed(&"warp_x")
	_warp_x.frequency = 0.01
	_warp_x.fractal_octaves = 2
	_warp_y.seed = sub_seed(&"warp_y")
	_warp_y.frequency = 0.01
	_warp_y.fractal_octaves = 2
	_rng.seed = sub_seed(&"sites")


## A seed for one part of the generator, so tuning one part doesn't reshuffle the others.
func sub_seed(part: StringName) -> int:
	return hash([seed, part]) & 0x7fffffff


func generate() -> void:
	_place_sites()
	heights.resize(SIZE * SIZE)
	ids.resize(SIZE * SIZE)
	cells.resize(SIZE * SIZE)
	for y in SIZE:
		for x in SIZE:
			var i := y * SIZE + x
			_pixel(world(x, y), i)


static func world(x: int, y: int) -> Vector2:
	return Vector2(x + ORIGIN.x, y + ORIGIN.z)


static func pixel_index(w: Vector2) -> int:
	var x := clampi(floori(w.x - ORIGIN.x), 0, SIZE - 1)
	var y := clampi(floori(w.y - ORIGIN.z), 0, SIZE - 1)
	return y * SIZE + x


## The generated height under a world XZ position (bilinear between pixels).
func height_at(w: Vector2) -> float:
	var p := w - Vector2(ORIGIN.x, ORIGIN.z)
	var x0 := clampi(floori(p.x), 0, SIZE - 2)
	var y0 := clampi(floori(p.y), 0, SIZE - 2)
	var fx := clampf(p.x - x0, 0.0, 1.0)
	var fy := clampf(p.y - y0, 0.0, 1.0)
	var top := lerpf(heights[y0 * SIZE + x0], heights[y0 * SIZE + x0 + 1], fx)
	var bottom := lerpf(heights[(y0 + 1) * SIZE + x0], heights[(y0 + 1) * SIZE + x0 + 1], fx)
	return lerpf(top, bottom, fy)


## The biome at a world XZ position (&"" up on the rim).
func biome_at(w: Vector2) -> StringName:
	var c := cells[pixel_index(w)]
	return &"" if c == RIM_CELL else sites[c]["biome"]


func height_image() -> Image:
	return Image.create_from_data(SIZE, SIZE, false, Image.FORMAT_RF, heights.to_byte_array())


# --- sites ------------------------------------------------------------------------------------

func _place_sites() -> void:
	sites = [{"biome": &"clearing", "pos": HUB_CENTER, "tier": 0}]
	var inner := INNER_BIOMES.duplicate()
	while inner.size() < INNER_COUNT:
		inner.append(INNER_BIOMES[_rng.randi_range(0, INNER_BIOMES.size() - 1)])
	_shuffle(inner)
	var outer := OUTER_BIOMES.duplicate()
	_shuffle(outer)
	_ring(inner, INNER_RADIUS, 1)
	_ring(outer, OUTER_RADIUS, 2)


## Spreads `biomes` round the hub, evenly but jittered, keeping MIN_SITE_GAP between sites
## (as far as it can: after a few tries it takes what it has).
func _ring(biomes: Array, radius: Vector2, tier: int) -> void:
	var start := _rng.randf() * TAU
	var step := TAU / biomes.size()
	for i in biomes.size():
		var best := Vector2.ZERO
		var best_gap := -1.0
		for attempt in 24:
			var a := start + i * step + _rng.randf_range(-0.3, 0.3) * step
			var p := HUB_CENTER + Vector2.from_angle(a) * _rng.randf_range(radius.x, radius.y)
			var gap := INF
			for s in sites:
				gap = minf(gap, p.distance_to(s["pos"]))
			if gap > best_gap:
				best = p
				best_gap = gap
			if gap >= MIN_SITE_GAP:
				break
		sites.append({"biome": biomes[i], "pos": best, "tier": tier})


func _shuffle(a: Array) -> void:
	for i in range(a.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var t: Variant = a[i]
		a[i] = a[j]
		a[j] = t


# --- one pixel --------------------------------------------------------------------------------

func _pixel(w: Vector2, i: int) -> void:
	var warped := w + Vector2(_warp_x.get_noise_2dv(w), _warp_y.get_noise_2dv(w)) * CELL_WARP
	var dist := PackedFloat32Array()
	dist.resize(sites.size())
	var nearest := 0
	for s in sites.size():
		dist[s] = warped.distance_to(sites[s]["pos"])
		if dist[s] < dist[nearest]:
			nearest = s
	# each site's ground, weighted by how close it is next to the nearest (a soft minimum), so
	# the profiles blend over the borders instead of stepping
	var h := 0.0
	var total := 0.0
	for s in sites.size():
		var weight := exp(-(dist[s] - dist[nearest]) * 3.0 / BIOME_BLEND)
		if weight < 0.01:
			continue
		h += _profile(sites[s], w) * weight
		total += weight
	h /= total
	h *= smoothstep(HUB_RADIUS, HUB_RADIUS + HUB_RAMP, w.distance_to(HUB_CENTER))
	var rim := _rim(w)
	h += rim * rim * RIM_HEIGHT + rim * (_ridges.get_noise_2dv(w) * 0.5 + 0.5) * RIM_HEIGHT * 0.35
	heights[i] = h
	var biome: StringName = sites[nearest]["biome"]
	cells[i] = RIM_CELL if rim > 0.5 else nearest
	ids[i] = BIOME_TEXTURE.get(biome, WorldMap.TEX_DEFAULT) if rim < 0.3 else WorldMap.TEX_DEFAULT


## How far up the rim a spot is, 0 (not on it) to 1 (the edge of the map). The rim follows a
## rounded square (a superellipse, so the corners don't crease), bent so it doesn't run straight.
func _rim(w: Vector2) -> float:
	var r := pow(pow(absf(w.x), 4.0) + pow(absf(w.y), 4.0), 0.25) + _rim_warp.get_noise_2dv(w) * RIM_WARP
	return smoothstep(RIM_START, SIZE * 0.5 + 8.0, r)


## A biome's own ground at `w` (before the hub flattens it and the rim raises it).
func _profile(site: Dictionary, w: Vector2) -> float:
	var hills := _hills.get_noise_2dv(w) * 0.5 + 0.5
	var swell := _swell.get_noise_2dv(w) * 0.5 + 0.5
	var bumps := _bumps.get_noise_2dv(w) * BUMP_HEIGHT
	match site["biome"]:
		&"clearing":    # a gentle lawn
			return 0.5 + swell * 2.0 + bumps * 0.3
		&"pinewood":    # rolling forested hills
			return 2.0 + hills * 18.0 + bumps
		&"goldmeadow":  # long, low swells for the fields
			return 1.0 + swell * 5.0 + bumps * 0.3
		&"stillwater":  # low, wet ground (the lake comes with the water stamps)
			return 0.4 + swell * 2.5 + bumps * 0.4
		&"quarry":      # a broken stone plateau
			return 8.0 + _rough.get_noise_2dv(w) * 4.0 + hills * 6.0 + bumps
		&"frostpeak":   # a mountain on the site, snowy above the shader's snow line
			var d: float = w.distance_to(site["pos"])
			var cone := pow(1.0 - smoothstep(0.0, 80.0, d), 1.6)
			return 6.0 + cone * 50.0 + (_ridges.get_noise_2dv(w) * 0.5 + 0.5) * 10.0 * (0.4 + cone) + hills * 6.0
	return hills * 10.0


# --- preview ----------------------------------------------------------------------------------

const PREVIEW_TINT := {
	&"clearing": Color(0.45, 0.62, 0.33), &"pinewood": Color(0.20, 0.38, 0.22),
	&"goldmeadow": Color(0.74, 0.70, 0.36), &"stillwater": Color(0.38, 0.55, 0.52),
	&"quarry": Color(0.62, 0.58, 0.52), &"frostpeak": Color(0.70, 0.74, 0.80),
}


## A top-down picture of the map: each biome tinted, shaded by height and lit from the
## north-west, snow above the snow line, the sites marked. For checking a seed at a glance.
func write_preview(path: String) -> Error:
	var img := Image.create_empty(SIZE, SIZE, false, Image.FORMAT_RGB8)
	for y in SIZE:
		for x in SIZE:
			var i := y * SIZE + x
			var h := heights[i]
			var c: Color = Color(0.47, 0.46, 0.45) if cells[i] == RIM_CELL else PREVIEW_TINT.get(sites[cells[i]]["biome"], Color.MAGENTA)
			c = c.lerp(Color(0.47, 0.46, 0.45), clampf((h - 20.0) / 18.0, 0.0, 0.6))
			if h > 38.0:
				c = Color(0.92, 0.94, 0.96)
			if ids[i] == WorldMap.TEX_PATH:
				c = Color(0.63, 0.52, 0.40)
			var east := heights[y * SIZE + mini(x + 1, SIZE - 1)] - h
			var south := heights[mini(y + 1, SIZE - 1) * SIZE + x] - h
			var light := clampf(1.0 + (east + south) * 0.25, 0.6, 1.3)  # rising to the south-east = facing the light
			img.set_pixel(x, y, c * light)
	for s in sites:
		var p := Vector2i((s["pos"] as Vector2) - Vector2(ORIGIN.x, ORIGIN.z))
		for k in range(-3, 4):
			img.set_pixelv((p + Vector2i(k, 0)).clamp(Vector2i.ZERO, Vector2i(SIZE - 1, SIZE - 1)), Color.RED)
			img.set_pixelv((p + Vector2i(0, k)).clamp(Vector2i.ZERO, Vector2i(SIZE - 1, SIZE - 1)), Color.RED)
	return img.save_png(path)
