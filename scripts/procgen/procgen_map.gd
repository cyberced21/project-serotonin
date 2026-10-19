class_name ProcgenMap
extends RefCounted
## Builds a 512 × 512 m world from a seed, as arrays: height per pixel (metres), terrain texture
## id per pixel (WorldMap.TEX_*) and which biome cell each pixel is in. Pure data, no nodes, so it
## runs headless and can be previewed as an image. ProcgenWorld hands the result to Terrain3D.
##
## Layout: a flat hub where you spawn (the Clearing, a little off the map's centre), a ring of biome cells round it,
## and a mountain rim along the edge so you never reach the end of the world. The cells are
## Voronoi cells (every spot belongs to the nearest site) on domain-warped coordinates, so their
## borders wander. The inner ring (tier 1) holds the gentler biomes, the outer ring (tier 2) the
## harder ones. Each biome has its own height profile; neighbours' profiles blend over the border.
## Then stamps are pressed in: the quarry's stepped pit in its cell, and water basins (a pond by
## the hub, ponds on low ground further out, the deep lake in Stillwater).
## Every biome is one of a few kinds (KINDS), rolled per seed: a Birch Grove or an Old Growth
## Pinewood, Twin Peaks, an Island Lake... A kind changes the ground here, and the nodes and scenery
## in ProcgenPopulation.

## Bump whenever the same seed and settings would build different land: a world made by an older
## generator says so on its card (Worlds.outdated), since its saved nodes may no longer match.
const GENERATOR_VERSION := 1

## The normal world's size (metres) and the world position of its corner; other sizes scale from
## these (`metres`, `origin`), and every distance tuned on the normal map stays as it was there.
const SIZE := 512
const ORIGIN := Vector3(-256, 0, -256)
const HUB_CENTER := Vector2.ZERO
## How far off the map's centre the hub may sit (m); the ring round it is kept inside the rim.
const HUB_OFFSET := Vector2(18.0, 48.0)
## No site goes further than this from the map's centre (the rim starts at RIM_START).
const SITE_MAX_DISTANCE := 150.0
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
## Hearthvale (the village) is always one of them; the extra one repeats a forest or the fields.
const INNER_BIOMES: Array[StringName] = [&"pinewood", &"goldmeadow", &"hearthvale"]
const INNER_REPEATS: Array[StringName] = [&"pinewood", &"goldmeadow"]
const INNER_COUNT := 4
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

## Each biome's kinds, [id, name on the arrival card]; the seed rolls one per biome.
const KINDS := {
	&"clearing": [[&"meadow", "Meadow"], [&"hollow", "Hollow"]],
	&"pinewood": [[&"pine_forest", "Pine Forest"], [&"birch_grove", "Birch Grove"], [&"old_growth", "Old Growth"]],
	&"goldmeadow": [[&"grainfields", "Grainfields"], [&"orchard_downs", "Orchard Downs"],
			[&"rolling_downs", "Rolling Downs"]],
	&"stillwater": [[&"great_lake", "Great Lake"], [&"marsh", "Marsh"], [&"island_lake", "Island Lake"]],
	&"quarry": [[&"terraced_pit", "Terraced Pit"], [&"deep_pit", "Deep Pit"], [&"broken_pit", "Broken Pit"]],
	&"frostpeak": [[&"lone_peak", "Lone Peak"], [&"twin_peaks", "Twin Peaks"], [&"ridge", "The Ridge"]],
	&"hearthvale": [[&"valley_village", "Valley Village"], [&"lakeside_village", "Lakeside Village"]],
}
## Hearthvale: flat ground VILLAGE_RADIUS round the square (easing into the land over VILLAGE_RAMP),
## a dirt square, and lanes to each door. The layout is the hand-built village's, round its square
## (building id, offset in metres, facing in radians: its +Z points that way), turned to a random
## angle per seed.
const VILLAGE_RADIUS := 34.0
const VILLAGE_RAMP := 28.0
const VILLAGE_SQUARE := 7.5
const VILLAGE_LANE := 1.0
const VILLAGE_BUILDINGS := [
	[&"town_hall", Vector2(14, 0), -1.5708],
	[&"woodcutter", Vector2(-2, -15), 0.0],
	[&"smithy", Vector2(13, 15), -2.4],
	[&"fisher", Vector2(-12, 14), 0.0],
	[&"baker_cottage", Vector2(-14, -13), 1.5708],
	[&"prospector_cottage", Vector2(6, 23), 3.1416],
]
## Each lane stops this far in front of its building.
const VILLAGE_LANE_STOP := 6.5
const VILLAGE_PROPS := [  # [model, offset, facing]
	[&"bench", Vector2(-6.5, -3), 1.5708], [&"bench", Vector2(-6.5, 3.5), 1.5708],
	[&"lamp_post", Vector2(-5.5, -6.5), 2.4], [&"lamp_post", Vector2(6.5, -5.5), 0.8],
	[&"lamp_post", Vector2(2, 7.5), -1.6], [&"barrel", Vector2(17.5, 19.5), 0.0],
	[&"barrel", Vector2(18.2, 18.6), 1.0], [&"crates", Vector2(-15.5, 11.5), 0.5],
	[&"crates", Vector2(8.5, -8.5), -0.4],
]
## A Lakeside Village's pond, behind the fisher's (as in the hand-built village).
const VILLAGE_POND := {"offset": Vector2(-12, 24), "radius": 7.0, "depth": 0.75}

## Every seed is rich in one resource (twice as much of it) and lean on another (half as much);
## nothing is ever taken away. The starter wood and copper ore are never the lean one.
const RICH_ITEMS: Array[StringName] = [&"birch", &"oak", &"pine", &"iron", &"coal", &"gold", &"crystal", &"wheat", &"barley", &"wood", &"ore"]
const LEAN_ITEMS: Array[StringName] = [&"birch", &"oak", &"pine", &"iron", &"coal", &"gold", &"wheat", &"barley"]

## The quarry's walls per kind (outermost first): one level below each, the last is the floor.
const QUARRY_KIND_WALLS := {
	&"terraced_pit": [32.0, 22.0, 12.0],
	&"deep_pit": [34.0, 26.0, 18.0, 10.0],
	&"broken_pit": [30.0, 20.0, 11.0],
}

## Water: every surface sits at WATER_LEVEL, as in the hand-built world, so the terrain shader's sand
## and pond-bed colours and the scatter's "keep off water" (both by height) work unchanged; the
## basins are carved down to it. Radius is roughly where the bed rises to the water line, depth
## the deepest point below it (wading depth: no swimming; char need 0.95).
const WATER_LEVEL := -0.15
const HUB_POND := {"distance": 17.0, "radius": 8.0, "depth": 0.95}
const POND_COUNT := 2
const POND_RADIUS := Vector2(6.5, 9.0)
const POND_DEPTH := Vector2(0.75, 0.95)
const LAKE_RADIUS := 15.0
const LAKE_DEPTH := 1.35
const ISLAND_RADIUS := 7.0
const MARSH_POOLS := 3

## The quarry pit: walls at these radii (outermost first), each a QUARRY_LEVEL_DROP step down from
## the rim, on a flat apron that blends back into the land over QUARRY_BLEND. Built like the
## hand-made Greystone Quarry, with three levels instead of five.
const QUARRY_WALLS: Array[float] = [32.0, 22.0, 12.0]
## The rim stands at least this high, and always high enough that the floor is 3 m above the water.
const QUARRY_RIM_HEIGHT := 18.0
const QUARRY_LEVEL_DROP := 5.0
const QUARRY_APRON := 8.0
const QUARRY_BLEND := 24.0
## The quarry site is pulled at least this close to the hub, so the pit only bites into the rim
## (like the hand-built quarry on its mountain shoulder) and keeps clear of the inner ring.
const QUARRY_MAX_DISTANCE := 126.0
## The haul road: each ramp runs along the inside of a wall, this wide, climbing one level over
## RAMP_LENGTH metres; the next ramp down starts RAMP_GAP metres further round.
const RAMP_WIDTH := 4.5
const RAMP_LENGTH := 30.0
const RAMP_GAP := 4.0
## Mantle stairs: two on every wall where it drops in three steps instead of one, each LEDGE deep.
const LEDGE := 1.6
const STAIR_WIDTH := 6.0

## Trails: A* on a grid of TRAIL_CELL-metre squares, from the hub to every biome and to the shore
## of every pond and lake past the hub. Steep squares cost more (so trails wind round hills), water
## and the rim can't be crossed. Each route is smoothed, painted as dirt TRAIL_HALF_WIDTH either
## side of its line, and graded: the ground across it is levelled to a smoothed height along it,
## easing back to the land over TRAIL_SHOULDER.
const TRAIL_CELL := 4.0
## A trail square on a river (its channel and banks) costs this much: trails ford rivers, straight across.
const RIVER_FORD_COST := 40.0
const TRAIL_SLOPE_COST := 90.0
const TRAIL_MAX_SLOPE := 0.5  # steeper squares are impassable
## Steepest the graded trail may climb (rise per metre); steeper ground is cut into.
const TRAIL_MAX_GRADE := 0.3
const TRAIL_HALF_WIDTH := 1.6
const TRAIL_SHOULDER := 3.5
## Metres either side over which the height along a trail is averaged before it's graded to it.
const TRAIL_SMOOTH := 8.0
## A trail to Frostpeak stops where its slopes begin, below this height.
const TRAIL_MAX_HEIGHT := 22.0

var seed := 0
## The map's width in metres (WorldSettings size), metres per pixel (1 for a real world, which
## Terrain3D takes at vertex spacing 1; more for a quick preview), pixels per side, and the world
## XZ of pixel (0, 0).
var metres := float(SIZE)
var step := 1.0
var size := SIZE
var origin := Vector2(ORIGIN.x, ORIGIN.z)
## The world's settings (WorldSettings.normalized): picked kinds, water, terrain, size...
var settings: Dictionary = WorldSettings.defaults()
var heights := PackedFloat32Array()
var ids := PackedByteArray()
## Index into `sites` per pixel, or RIM_CELL.
var cells := PackedByteArray()
## The biome cells: {biome: StringName, kind: StringName, pos: Vector2, tier: int}. Site 0 is the hub.
var sites: Array[Dictionary] = []
## The kind rolled for each biome, biome -> kind id.
var kinds: Dictionary[StringName, StringName] = {}
## The resource this seed has twice as much of, and the one it has half as much of (item ids).
var rich: StringName = &""
var lean: StringName = &""
## Where the hub is, and how wide its ground eases up into the land (a Hollow's rises close).
var hub := HUB_CENTER
var hub_ramp := HUB_RAMP
## The quarry's walls, from its kind.
var quarry_walls: Array[float] = [32.0, 22.0, 12.0]
## Frostpeak's summits (a Lone Peak has one, Twin Peaks two) and, for a Ridge, the spine's ends.
var peaks: Array[Vector2] = []
## The water bodies: {name: String, center: Vector2, radius: float, depth: float, lake: bool}.
var waters: Array[Dictionary] = []
## The quarry pit, if there is one: {center: Vector2, rim_height: float, depth: float, walls: Array[float]}.
var quarry: Dictionary = {}
## Hearthvale's village, if there is one: {center: Vector2, height: float, angle: float, lakeside: bool,
## buildings: [[id, pos: Vector2, facing]], props: [[model, pos, facing]]}, positions in world XZ.
var village: Dictionary = {}
## The trails' centre lines, world XZ, one point a metre, each starting at the hub.
var trails: Array[PackedVector2Array] = []
## The rivers: {points: PackedVector2Array (source to mouth, a metre apart), widths: PackedFloat32Array
## (half the channel's width at each point)}.
var rivers: Array[Dictionary] = []
## 1 on a river's channel and banks (trails may ford there), per pixel.
var river_mask := PackedByteArray()
## Places out in the wilds: {type: &"ruins" | &"camp" | &"rare", kind: StringName, name: String,
## pos: Vector2, angle: float, height: float (its levelled pad, for ruins and camps)}.
var landmarks: Array[Dictionary] = []
## How far generate() has got, 0..1, and which stage it's on (STAGES); generate() runs on a worker
## thread behind the loading screen, which reads these.
var progress := 0.0
var stage := 0
const STAGES: Array[String] = ["Shaping the land", "Flattening the village", "Filling the ponds",
		"Cutting the rivers", "Treading the trails", "Raising the ruins"]

var _hills := FastNoiseLite.new()
var _swell := FastNoiseLite.new()
var _bumps := FastNoiseLite.new()
var _rough := FastNoiseLite.new()
var _rim_warp := FastNoiseLite.new()
var _ridges := FastNoiseLite.new()
var _warp_x := FastNoiseLite.new()
var _warp_y := FastNoiseLite.new()
var _shore := FastNoiseLite.new()  # ragged pond outlines
var _rings := FastNoiseLite.new()  # wandering quarry walls
var _meander := FastNoiseLite.new()  # rivers swinging from side to side
var _rng := RandomNumberGenerator.new()
var _kind_rng := RandomNumberGenerator.new()  # its own, so rolling kinds doesn't move the sites
var _ramp_top: Array[float] = []   # per quarry wall: angle of its ramp's top end
var _ramp_span: Array[float] = []  # per quarry wall: angle its ramp covers
var _relief := 1.0  # biome heights × this (WorldSettings terrain)


## `metres_per_pixel` > 1: a coarser map for a preview (the same land, less detail).
func _init(world_seed: int, world_settings := {}, metres_per_pixel := 1.0) -> void:
	seed = world_seed
	settings = WorldSettings.normalized(world_settings)
	settings["seed"] = world_seed
	_relief = WorldSettings.RELIEF[settings["terrain"]]
	metres = float(WorldSettings.SIZE_METRES[settings["size"]])
	step = metres_per_pixel
	size = int(metres / step)
	origin = Vector2.ONE * -metres * 0.5
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
	_shore.seed = sub_seed(&"shore")
	_shore.frequency = 0.15
	_rings.seed = sub_seed(&"rings")
	_rings.frequency = 0.05
	_meander.seed = sub_seed(&"meander")
	_meander.frequency = 0.025
	_meander.fractal_octaves = 2
	_rng.seed = sub_seed(&"sites")
	_kind_rng.seed = sub_seed(&"kinds")


static func random_seed() -> int:
	return randi_range(1, 999_999)


## A seed for one part of the generator, so tuning one part doesn't reshuffle the others.
func sub_seed(part: StringName) -> int:
	return hash([seed, part]) & 0x7fffffff


func generate() -> void:
	_roll_kinds()
	_place_sites()
	heights.resize(size * size)
	ids.resize(size * size)
	cells.resize(size * size)
	for y in size:
		for x in size:
			var i := y * size + x
			_pixel(world(x, y), i)
		progress = 0.6 * (y + 1) / size
	stage = 1
	_stamp_village()
	_stamp_quarry()
	progress = 0.65
	stage = 2
	_place_water()
	progress = 0.7
	stage = 3
	_carve_rivers()
	progress = 0.8
	stage = 4
	_lay_trails()
	progress = 0.95
	stage = 5
	_place_landmarks()
	progress = 1.0


## The world XZ of pixel (x, y).
func world(x: int, y: int) -> Vector2:
	return Vector2(x * step + origin.x, y * step + origin.y)


func pixel_index(w: Vector2) -> int:
	var x := clampi(floori((w.x - origin.x) / step), 0, size - 1)
	var y := clampi(floori((w.y - origin.y) / step), 0, size - 1)
	return y * size + x


## A distance from the normal map's centre (tuned at 512 m) moved out with this map's edge.
func _far(d: float) -> float:
	return d + (metres - SIZE) * 0.5


## The generated height under a world XZ position (bilinear between pixels).
func height_at(w: Vector2) -> float:
	var p := (w - origin) / step
	var x0 := clampi(floori(p.x), 0, size - 2)
	var y0 := clampi(floori(p.y), 0, size - 2)
	var fx := clampf(p.x - x0, 0.0, 1.0)
	var fy := clampf(p.y - y0, 0.0, 1.0)
	var top := lerpf(heights[y0 * size + x0], heights[y0 * size + x0 + 1], fx)
	var bottom := lerpf(heights[(y0 + 1) * size + x0], heights[(y0 + 1) * size + x0 + 1], fx)
	return lerpf(top, bottom, fy)


## The name of a biome's kind this seed ("Birch Grove"), or "" if it has none.
func kind_name(biome: StringName) -> String:
	for k in KINDS.get(biome, []):
		if k[0] == kinds.get(biome):
			return k[1]
	return ""


## The biome at a world XZ position (&"" up on the rim).
func biome_at(w: Vector2) -> StringName:
	var c := cells[pixel_index(w)]
	return &"" if c == RIM_CELL else sites[c]["biome"]


func height_image() -> Image:
	return Image.create_from_data(size, size, false, Image.FORMAT_RF, heights.to_byte_array())


# --- sites ------------------------------------------------------------------------------------

func _roll_kinds() -> void:
	kinds.clear()
	for biome in KINDS:
		var options: Array = KINDS[biome]
		var rolled: StringName = options[_kind_rng.randi_range(0, options.size() - 1)][0]  # rolled even when
		kinds[biome] = settings["kinds"].get(biome, rolled)  # picked, so the rolls after it stay the same
	hub_ramp = HUB_RAMP * (0.55 if kinds[&"clearing"] == &"hollow" else 1.0)
	quarry_walls.assign(QUARRY_KIND_WALLS[kinds[&"quarry"]])
	hub = Vector2.from_angle(_kind_rng.randf() * TAU) * _kind_rng.randf_range(HUB_OFFSET.x, HUB_OFFSET.y)
	var wealth := RandomNumberGenerator.new()
	wealth.seed = sub_seed(&"wealth")
	rich = RICH_ITEMS[wealth.randi_range(0, RICH_ITEMS.size() - 1)]
	lean = rich
	while lean == rich:
		lean = LEAN_ITEMS[wealth.randi_range(0, LEAN_ITEMS.size() - 1)]


func _place_sites() -> void:
	sites = [{"biome": &"clearing", "kind": kinds[&"clearing"], "pos": hub, "tier": 0}]
	var inner := INNER_BIOMES.duplicate()
	while inner.size() < INNER_COUNT:
		inner.append(INNER_REPEATS[_rng.randi_range(0, INNER_REPEATS.size() - 1)])
	_shuffle(inner)
	var outer := OUTER_BIOMES.duplicate()
	_shuffle(outer)
	_ring(inner, INNER_RADIUS, 1)
	_ring(outer, OUTER_RADIUS, 2)
	for s in sites:
		if s["biome"] == &"quarry":
			s["pos"] = (s["pos"] as Vector2).limit_length(QUARRY_MAX_DISTANCE)
	_place_peaks()


## Frostpeak's summits, by kind: one on the site; two either side of it with a saddle between;
## or the two ends of a ridge running across the way to the hub.
func _place_peaks() -> void:
	peaks.clear()
	var fi := _site_index(&"frostpeak")
	if fi < 0:
		return
	var at: Vector2 = sites[fi]["pos"]
	var across := (at - hub).normalized().orthogonal()
	match kinds[&"frostpeak"]:
		&"twin_peaks":
			peaks = [at + across * 26.0, at - across * 26.0]
		&"ridge":
			peaks = [at + across * 42.0, at - across * 42.0]
		_:
			peaks = [at]


func _site_index(biome: StringName) -> int:
	for i in sites.size():
		if sites[i]["biome"] == biome:
			return i
	return -1


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
			var p := (hub + Vector2.from_angle(a) * _rng.randf_range(radius.x, radius.y)).limit_length(SITE_MAX_DISTANCE)
			var gap := INF
			for s in sites:
				gap = minf(gap, p.distance_to(s["pos"]))
			if gap > best_gap:
				best = p
				best_gap = gap
			if gap >= MIN_SITE_GAP:
				break
		sites.append({"biome": biomes[i], "kind": kinds.get(biomes[i], &""), "pos": best, "tier": tier})


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
	h = h / total * _relief
	h *= smoothstep(HUB_RADIUS, HUB_RADIUS + hub_ramp, w.distance_to(hub))
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
	return smoothstep(_far(RIM_START), metres * 0.5 + 8.0, r)


## A biome's own ground at `w` (before the hub flattens it and the rim raises it).
func _profile(site: Dictionary, w: Vector2) -> float:
	var hills := _hills.get_noise_2dv(w) * 0.5 + 0.5
	var swell := _swell.get_noise_2dv(w) * 0.5 + 0.5
	var bumps := _bumps.get_noise_2dv(w) * BUMP_HEIGHT
	var kind: StringName = site.get("kind", &"")
	match site["biome"]:
		&"clearing":    # a gentle lawn (a Hollow's hills rise close round it)
			return 0.5 + swell * 2.0 + bumps * 0.3
		&"pinewood":    # forested hills: a Birch Grove's gentle, Old Growth's steep and high
			match kind:
				&"birch_grove":
					return 1.5 + hills * 10.0 + bumps * 0.8
				&"old_growth":
					return 3.0 + hills * 26.0 + (_ridges.get_noise_2dv(w) * 0.5 + 0.5) * 5.0 + bumps
			return 2.0 + hills * 18.0 + bumps
		&"goldmeadow":  # swells for the fields: long and low, steeper on the downs
			match kind:
				&"orchard_downs":
					return 1.5 + swell * 7.0 + bumps * 0.4
				&"rolling_downs":
					return 1.0 + swell * 12.0 + hills * 3.0 + bumps * 0.4
			return 1.0 + swell * 5.0 + bumps * 0.3
		&"stillwater":  # low, wet ground (the lake comes with the water stamps; a marsh lies flatter)
			if kind == &"marsh":
				return 0.25 + swell * 1.2 + bumps * 0.3
			return 0.4 + swell * 2.5 + bumps * 0.4
		&"quarry":      # a broken stone plateau, rougher round a Broken Pit
			var rough := 7.0 if kind == &"broken_pit" else 4.0
			return 8.0 + _rough.get_noise_2dv(w) * rough + hills * 6.0 + bumps
		&"frostpeak":   # mountains on the site, snowy above the shader's snow line
			return _mountain(w) + hills * 6.0
		&"hearthvale":  # round the village's flat: hills for a valley, low ground by a lake
			if kind == &"lakeside_village":
				return 0.5 + swell * 2.0 + bumps * 0.3
			return 1.0 + hills * 9.0 + bumps * 0.5
	return hills * 10.0


## Frostpeak's height at `w`: a cone round each summit, or for a Ridge a spine between its two
## ends; ridged noise roughens it more the higher up.
func _mountain(w: Vector2) -> float:
	var cone := 0.0
	if kinds.get(&"frostpeak") == &"ridge" and peaks.size() == 2:
		var d := w.distance_to(Geometry2D.get_closest_point_to_segment(w, peaks[0], peaks[1]))
		cone = pow(1.0 - smoothstep(0.0, 55.0, d), 1.4) * 0.8
	else:
		var tall := 1.0 if peaks.size() == 1 else 0.85
		for p in peaks:
			var c := pow(1.0 - smoothstep(0.0, 70.0 if peaks.size() > 1 else 80.0, w.distance_to(p)), 1.6) * tall
			cone = maxf(cone, c) + minf(cone, c) * 0.25  # the saddle between two summits
	return 6.0 + cone * 50.0 + (_ridges.get_noise_2dv(w) * 0.5 + 0.5) * 10.0 * (0.4 + cone)


# --- stamps -----------------------------------------------------------------------------------

## Flattens Hearthvale's middle for the village, paints its square and lanes, and lays out its
## buildings and props (see VILLAGE_*). The flat sits at the ground's own height there, kept out
## of the water and off the hilltops; a Lakeside Village sits just above its pond.
func _stamp_village() -> void:
	village = {}
	var vi := _site_index(&"hearthvale")
	if vi < 0:
		return
	var c: Vector2 = sites[vi]["pos"]
	var angle := _rng.randf() * TAU
	var h := clampf(height_at(c), 0.6, 5.0)
	if kinds.get(&"hearthvale") == &"lakeside_village":
		h = 0.15  # just above the pond, as in the hand-built village, so the fisher's jetty meets it
	var turn := func(offset: Vector2) -> Vector2: return c + offset.rotated(angle)
	village = {"center": c, "height": h, "angle": angle, "lakeside": kinds.get(&"hearthvale") == &"lakeside_village",
			"buildings": [], "props": []}
	var lanes: Array = []
	for b in VILLAGE_BUILDINGS:
		var at: Vector2 = turn.call(b[1])
		var facing: float = b[2] - angle  # a +Z facing turns the other way round Y
		village["buildings"].append([b[0], at, facing])
		lanes.append([c, at + Vector2(sin(facing), cos(facing)) * VILLAGE_LANE_STOP])
	for p in VILLAGE_PROPS:
		village["props"].append([p[0], turn.call(p[1]), p[2] - angle])
	_for_pixels_near(c, VILLAGE_RADIUS + VILLAGE_RAMP, func(i: int, w: Vector2) -> void:
		var d := w.distance_to(c) + _shore.get_noise_2dv(w) * 3.0
		heights[i] = lerpf(h, heights[i], smoothstep(VILLAGE_RADIUS, VILLAGE_RADIUS + VILLAGE_RAMP, d))
		if d < VILLAGE_RADIUS + 4.0:
			cells[i] = vi
		if w.distance_to(c) < VILLAGE_SQUARE:
			ids[i] = WorldMap.TEX_PATH
		else:
			ids[i] = WorldMap.TEX_DEFAULT if d < VILLAGE_RADIUS else ids[i]
			for lane in lanes:
				var q := Geometry2D.get_closest_point_to_segment(w, lane[0], lane[1])
				if w.distance_to(q) < VILLAGE_LANE:
					ids[i] = WorldMap.TEX_PATH)


## Calls fn(i, w) for every pixel within `radius` of world XZ `at`.
func _for_pixels_near(at: Vector2, radius: float, fn: Callable) -> void:
	var lo := ((at - Vector2.ONE * radius - origin) / step).floor()
	var hi := ((at + Vector2.ONE * radius - origin) / step).ceil()
	for y in range(maxi(int(lo.y), 0), mini(int(hi.y), size - 1) + 1):
		for x in range(maxi(int(lo.x), 0), mini(int(hi.x), size - 1) + 1):
			var w := world(x, y)
			if w.distance_to(at) <= radius:
				fn.call(y * size + x, w)


func _stamp_quarry() -> void:
	var qi := _site_index(&"quarry")
	if qi < 0:
		return
	var c: Vector2 = sites[qi]["pos"]
	_ramp_top.clear()
	_ramp_span.clear()
	var top := _rng.randf() * TAU  # where the haul road comes over the rim
	for b in quarry_walls:
		var r := b - RAMP_WIDTH * 0.5
		var span := RAMP_LENGTH / r
		_ramp_top.append(top)
		_ramp_span.append(span)
		top = top - span - RAMP_GAP / r
	quarry = {"center": c, "rim_height": _quarry_rim(), "walls": quarry_walls,
			"depth": QUARRY_LEVEL_DROP * quarry_walls.size()}
	var flat := quarry_walls[0] + QUARRY_APRON
	_for_pixels_near(c, flat + QUARRY_BLEND, func(i: int, w: Vector2) -> void:
		var d := w.distance_to(c) + _rings.get_noise_2dv(w) * 1.5
		var theta := (w - c).angle()
		heights[i] = lerpf(_quarry_height(d, theta), heights[i], smoothstep(flat, flat + QUARRY_BLEND, d))
		if d < flat:
			cells[i] = qi
		if d < quarry_walls[0] + 3.0:
			ids[i] = WorldMap.TEX_QUARRY
		if _on_haul_road(d, theta):
			ids[i] = WorldMap.TEX_PATH)


func _quarry_height(d: float, theta: float) -> float:
	var above := 0.0  # how many walls this spot is on the outer (higher) side of
	for i in quarry_walls.size():
		above += _wall_step(i, d, theta)
	return _quarry_rim() - QUARRY_LEVEL_DROP * (quarry_walls.size() - above)


func _quarry_rim() -> float:
	return maxf(QUARRY_RIM_HEIGHT, QUARRY_LEVEL_DROP * quarry_walls.size() + 3.0)


## 1 on the outer side of wall i, 0 on the inner side; in between on its ramp and stairs.
func _wall_step(i: int, d: float, theta: float) -> float:
	var b := quarry_walls[i]
	var s := _sharp(d - b)
	if d > b - RAMP_WIDTH and d <= b:
		var t := _ramp_t(i, theta)
		if t >= 0.0:
			return t
	for a in _stair_angles(i):
		if absf(angle_difference(theta, a)) * b < STAIR_WIDTH * 0.5:
			return (_sharp(d - b + 2.0 * LEDGE) + _sharp(d - b + LEDGE) + s) / 3.0
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


func _on_haul_road(d: float, theta: float) -> bool:
	for i in quarry_walls.size():
		var b := quarry_walls[i]
		if d > b - RAMP_WIDTH and d <= b and _ramp_t(i, theta) >= 0.0:
			return true
	return false


func _place_water() -> void:
	waters.clear()
	var a := _rng.randf() * TAU
	_basin("HubPond", hub + Vector2.from_angle(a) * float(HUB_POND["distance"]),
			HUB_POND["radius"], HUB_POND["depth"], false)
	if not village.is_empty() and village["lakeside"]:
		var vp: Vector2 = village["center"] + (VILLAGE_POND["offset"] as Vector2).rotated(village["angle"])
		_basin("VillagePond", vp, VILLAGE_POND["radius"], VILLAGE_POND["depth"], false, false, 3.5)
	var si := _site_index(&"stillwater")
	if si >= 0:
		var at: Vector2 = (sites[si]["pos"] as Vector2).move_toward(hub, 10.0)
		if not quarry.is_empty():  # keep the lake's banks out of the quarry's apron
			var qc: Vector2 = quarry["center"]
			var need := quarry_walls[0] + QUARRY_APRON + QUARRY_BLEND + LAKE_RADIUS + 10.0
			if at.distance_to(qc) < need:
				at = qc + (at - qc).normalized() * need
		at = at.limit_length(_far(140.0))
		match kinds[&"stillwater"]:
			&"island_lake":  # a wider lake, an island in its middle
				_basin("Lake", at, LAKE_RADIUS + 7.0, LAKE_DEPTH, true)
				_island(at, ISLAND_RADIUS)
			&"marsh":  # a smaller deep pond for the char, shallow pools scattered round it
				_basin("Lake", at, LAKE_RADIUS - 4.0, LAKE_DEPTH, true)
				var a0 := _rng.randf() * TAU
				for k in MARSH_POOLS:
					var p := at + Vector2.from_angle(a0 + k * TAU / MARSH_POOLS + _rng.randf_range(-0.4, 0.4)) \
							* _rng.randf_range(20.0, 26.0)
					_basin("Marsh%d" % (k + 1), p, _rng.randf_range(4.0, 6.0), _rng.randf_range(0.5, 0.7), false, false)
			_:
				_basin("Lake", at, LAKE_RADIUS + 4.0, LAKE_DEPTH, true)
	for n in WorldSettings.PONDS[settings["water"]]:
		var r := _rng.randf_range(POND_RADIUS.x, POND_RADIUS.y)
		var best := Vector2.INF
		var best_score := INF
		for k in 240:  # the lowest of a few hundred allowed spots, so ponds sit in hollows
			var p := Vector2(_rng.randf_range(-_far(170.0), _far(170.0)), _rng.randf_range(-_far(170.0), _far(170.0)))
			if not _pond_spot_ok(p, r):
				continue
			var score := height_at(p) + _rng.randf() * 2.0
			if score < best_score:
				best = p
				best_score = score
		if best != Vector2.INF:
			_basin("Pond%d" % (n + 1), best, r, _rng.randf_range(POND_DEPTH.x, POND_DEPTH.y), false)


func _pond_spot_ok(p: Vector2, r: float) -> bool:
	if p.distance_to(hub) < HUB_RADIUS + hub_ramp or p.length() > _far(150.0) or _rim(p) > 0.0:
		return false
	var biome := biome_at(p)
	if biome == &"quarry" or biome == &"frostpeak" or biome == &"":
		return false
	if not village.is_empty() and p.distance_to(village["center"]) < VILLAGE_RADIUS + VILLAGE_RAMP + r:
		return false
	if not quarry.is_empty() and p.distance_to(quarry["center"]) < quarry_walls[0] + QUARRY_APRON + QUARRY_BLEND + r + 10.0:
		return false
	for w in waters:
		if p.distance_to(w["center"]) < float(w["radius"]) + r + 30.0:
			return false
	return true


## Carves a basin round `at` down below WATER_LEVEL, the land easing down to the shore over a ramp
## that's longer the higher the ground stands (or `ramp` m: a dug pond's short bank), and records it
## in `waters`.
func _basin(water_name: String, at: Vector2, r: float, depth: float, lake: bool, trail := true, ramp := -1.0) -> void:
	if ramp < 0.0:
		ramp = clampf(6.0 + height_at(at) * 2.5, 8.0, 40.0)
	_for_pixels_near(at, r + ramp + 3.0, func(i: int, w: Vector2) -> void:
		var pd := w.distance_to(at) + _shore.get_noise_2dv(w) * 2.0
		var h := heights[i] * smoothstep(r + 2.0, r + ramp, pd)
		var bowl := 1.0 - smoothstep(r * 0.3, r + 1.5, pd)  # 1 mid-pond, 0 past the shore
		if bowl > 0.0:
			h = minf(h, (WATER_LEVEL - depth) * bowl)
		heights[i] = h
		if pd < r + 3.0:
			ids[i] = WorldMap.TEX_DEFAULT)  # the shader's sand and bed, not forest floor or field
	waters.append({"name": water_name, "center": at, "radius": r, "depth": depth, "lake": lake, "trail": trail})


## Raises an island out of the water round `at`: a low grassy mound, ragged at the shore.
func _island(at: Vector2, r: float) -> void:
	_for_pixels_near(at, r + 3.0, func(i: int, w: Vector2) -> void:
		var d := w.distance_to(at) + _shore.get_noise_2dv(w) * 1.5
		var mound := 1.0 - smoothstep(r * 0.4, r, d)
		heights[i] = maxf(heights[i], lerpf(heights[i], 1.4 + _bumps.get_noise_2dv(w) * 0.4, mound)))

# --- rivers -----------------------------------------------------------------------------------

## A river runs from the mountains of the rim down into the lake: A* over the trail grid that
## prefers low ground (so it finds the valleys) and keeps clear of the hub, the village and the
## quarry, then carved down to the water line, its banks rising beside it (a gorge where it cuts
## through a hill). It widens toward its mouth. Some seeds get a second, from another direction.
const RIVER_WIDTH := Vector2(1.6, 3.0)  # half the channel's width at the source and at the mouth
const RIVER_DEPTH := 0.55               # below the water line, mid-channel: wadeable
const RIVER_BANK := 0.7                 # rise per metre beside the channel
const RIVER_REACH := 16.0               # how far beside it the banks are shaped
const RIVER_SECOND_CHANCE := 0.5
const RIVER_MEANDER := 9.0               # how far (m) it swings to either side of its route


func _carve_rivers() -> void:
	rivers.clear()
	river_mask.resize(size * size)
	river_mask.fill(0)
	var lake := {}
	for w in waters:
		if w["name"] == "Lake":
			lake = w
	if lake.is_empty() or settings["water"] == &"dry":
		return
	var mouth: Vector2 = lake["center"]
	var away := (mouth - hub).normalized()
	var turns := [_rng.randf_range(-0.4, 0.4)]
	if _rng.randf() < RIVER_SECOND_CHANCE or settings["water"] == &"wet":
		turns.append(_rng.randf_range(1.1, 1.7) * (1.0 if _rng.randf() < 0.5 else -1.0))
	var astar := _river_grid()
	for turn in turns:
		var source := mouth
		var dir := away.rotated(turn)
		while _rim(source) < 0.2 and source.length() < metres * 0.5:
			source += dir * TRAIL_CELL
		var cells_path := astar.get_id_path(_trail_cell(source), _trail_cell(mouth))
		if cells_path.size() < 4:
			continue
		var pts := PackedVector2Array()
		for c in cells_path:
			pts.append(_trail_world(c))
		pts = _meandered(_resample(_chaikin(_chaikin(_chaikin(pts))), 1.0), rivers.size())
		var r: float = lake["radius"]
		var keep := pts.size()
		while keep > 2 and pts[keep - 1].distance_to(mouth) < r - 2.0:  # stops where it meets the lake
			keep -= 1
		pts = pts.slice(0, keep)
		var widths := PackedFloat32Array()
		for k in pts.size():
			widths.append(lerpf(RIVER_WIDTH.x, RIVER_WIDTH.y, float(k) / maxf(pts.size() - 1, 1)))
		rivers.append({"points": pts, "widths": widths})
		_carve_river(pts, widths)


func _river_grid() -> AStarGrid2D:
	var n := int(metres / TRAIL_CELL)
	var astar := AStarGrid2D.new()
	astar.region = Rect2i(0, 0, n, n)
	astar.cell_size = Vector2.ONE * TRAIL_CELL
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	astar.update()
	for y in n:
		for x in n:
			var c := Vector2i(x, y)
			var w := _trail_world(c)
			var kept_clear := w.distance_to(hub) < HUB_RADIUS + hub_ramp * 0.6 or _in_pit(w) \
					or (not quarry.is_empty() and w.distance_to(quarry["center"]) < quarry_walls[0] + QUARRY_APRON + 6.0) \
					or (not village.is_empty() and w.distance_to(village["center"]) < VILLAGE_RADIUS + 8.0)
			if kept_clear:
				astar.set_point_solid(c, true)
			else:
				var wander := (_meander.get_noise_2dv(w * 2.0) * 0.5 + 0.5) * 3.0
				astar.set_point_weight_scale(c, 1.0 + clampf(height_at(w), 0.0, 60.0) * 0.5 + wander)
	return astar


## `pts` pushed side to side by smooth noise along its length, full swing in the middle, none at
## either end (it still leaves the mountains and meets the lake where its route does).
func _meandered(pts: PackedVector2Array, salt: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	var n := pts.size()
	for k in n:
		var along := (pts[mini(k + 3, n - 1)] - pts[maxi(k - 3, 0)]).normalized()
		var ends := smoothstep(0.0, 25.0, float(k)) * smoothstep(0.0, 25.0, float(n - 1 - k))
		var swing := _meander.get_noise_2d(float(k), 300.0 * salt) * RIVER_MEANDER * 1.6 * ends
		out.append(pts[k] + along.orthogonal() * swing)
	return _resample(_chaikin(out), 1.0)


func _carve_river(pts: PackedVector2Array, widths: PackedFloat32Array) -> void:
	for k in range(0, pts.size(), 2):
		var at := pts[k]
		var hw := widths[k]
		_for_pixels_near(at, hw + RIVER_REACH, func(i: int, w: Vector2) -> void:
			var d := w.distance_to(at)
			var bed := WATER_LEVEL + (d - hw) * RIVER_BANK
			if d < hw:
				bed = WATER_LEVEL - RIVER_DEPTH * (1.0 - (d / hw) * (d / hw))
			heights[i] = minf(heights[i], bed)
			if d < hw + 1.5:
				ids[i] = WorldMap.TEX_DEFAULT  # the shader's sand and bed
			if d < hw + 6.0:
				river_mask[i] = 1)


# --- trails -----------------------------------------------------------------------------------

func _lay_trails() -> void:
	trails.clear()
	var astar := _trail_grid()
	var start := _trail_cell(hub)
	astar.set_point_solid(start, false)
	for t in _trail_targets():
		# a target on ground a trail can't reach (steep, wet) moves back toward the hub until it can
		# a target a trail can't reach (steep, wet or walled in) moves back toward the hub until it can
		var target := t
		var cells_path: Array[Vector2i] = []
		for k in 60:
			var goal := _trail_cell(target)
			if not astar.is_point_solid(goal):
				cells_path = astar.get_id_path(start, goal)
				if cells_path.size() >= 2:
					break
			if target.distance_to(hub) < HUB_RADIUS:
				break
			target = target.move_toward(hub, TRAIL_CELL)
		if cells_path.size() < 2:
			continue
		var pts := PackedVector2Array()
		for c in cells_path:
			pts.append(_trail_world(c))
		pts[pts.size() - 1] = target
		trails.append(_resample(_chaikin(_chaikin(_chaikin(pts))), 1.0))
	_grade_and_paint()


## Where trails go: each biome (Frostpeak's foot, the quarry's haul road at the rim; Stillwater by
## way of its lake) and the shore of each water past the hub, on the side facing the hub.
func _trail_targets() -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in range(1, sites.size()):
		var p: Vector2 = sites[i]["pos"]
		match sites[i]["biome"]:
			&"hearthvale":  # the edge of its square
				p += (hub - p).normalized() * (VILLAGE_SQUARE + 1.0)
			&"stillwater":
				continue  # its site is under the lake, which gets a trail of its own
			&"quarry":
				var b := quarry_walls[0]
				p += Vector2.from_angle(_ramp_top[0]) * (b + 2.0) if not _ramp_top.is_empty() else Vector2.ZERO
			&"frostpeak":
				while height_at(p) > TRAIL_MAX_HEIGHT and p.distance_to(hub) > 4.0:
					p = p.move_toward(hub, 2.0)
		out.append(p)
	for w in waters:
		var c: Vector2 = w["center"]
		if c.distance_to(hub) < HUB_RADIUS + 10.0 or not w.get("trail", true):
			continue  # the hub's own pond is in sight of the spawn; a marsh's pools are by its lake
		out.append(c + (hub - c).normalized() * (float(w["radius"]) + 3.0))
	return out


## The coarse cost grid: a square's weight grows with the steepest drop to its neighbours.
func _trail_grid() -> AStarGrid2D:
	var n := int(metres / TRAIL_CELL)
	var astar := AStarGrid2D.new()
	astar.region = Rect2i(0, 0, n, n)
	astar.cell_size = Vector2.ONE * TRAIL_CELL
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	astar.update()
	for y in n:
		for x in n:
			var c := Vector2i(x, y)
			var w := _trail_world(c)
			var h := height_at(w)
			var slope := 0.0
			for d in [Vector2(TRAIL_CELL, 0), Vector2(0, TRAIL_CELL), Vector2(-TRAIL_CELL, 0), Vector2(0, -TRAIL_CELL)]:
				slope = maxf(slope, absf(height_at(w + d) - h) / TRAIL_CELL)
			var wet := h < WATER_LEVEL + 0.05
			if river_mask[pixel_index(w)] and _rim(w) < 0.3:  # a ford: wade across, but not along
				astar.set_point_weight_scale(c, RIVER_FORD_COST)
			elif wet or slope > TRAIL_MAX_SLOPE or _rim(w) > 0.3 or _in_pit(w):
				astar.set_point_solid(c, true)
			else:
				astar.set_point_weight_scale(c, 1.0 + TRAIL_SLOPE_COST * slope * slope)
	return astar


func _in_pit(w: Vector2) -> bool:
	return not quarry.is_empty() and w.distance_to(quarry["center"]) < quarry_walls[0] + 1.0


func _trail_cell(w: Vector2) -> Vector2i:
	var p := (w - origin) / TRAIL_CELL
	var n := int(metres / TRAIL_CELL)
	return Vector2i(clampi(int(p.x), 0, n - 1), clampi(int(p.y), 0, n - 1))


func _trail_world(c: Vector2i) -> Vector2:
	return origin + (Vector2(c) + Vector2(0.5, 0.5)) * TRAIL_CELL


## One round of corner cutting: the grid's staircase becomes a curve after a few.
static func _chaikin(pts: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array([pts[0]])
	for i in pts.size() - 1:
		out.append(pts[i].lerp(pts[i + 1], 0.25))
		out.append(pts[i].lerp(pts[i + 1], 0.75))
	out.append(pts[pts.size() - 1])
	return out


## Points every `step` metres along a polyline.
static func _resample(pts: PackedVector2Array, step: float) -> PackedVector2Array:
	var out := PackedVector2Array([pts[0]])
	var carry := 0.0
	for i in pts.size() - 1:
		var a := pts[i]
		var b := pts[i + 1]
		var length := a.distance_to(b)
		var t := step - carry
		while t <= length:
			out.append(a.lerp(b, t / length))
			t += step
		carry = length - (t - step)
	if out[out.size() - 1].distance_to(pts[pts.size() - 1]) > 0.1:
		out.append(pts[pts.size() - 1])
	return out


## Keeps neighbouring heights within `grade` of each other (a metre apart), lowering the high side:
## sweeping forward then back leaves no step steeper than that, cutting into rises.
static func _limit_grade(a: PackedFloat32Array, grade: float) -> void:
	for k in range(1, a.size()):
		a[k] = minf(a[k], a[k - 1] + grade)
	for k in range(a.size() - 2, -1, -1):
		a[k] = minf(a[k], a[k + 1] + grade)


## Grades every trail into the ground and paints it as dirt. Each pixel near a trail takes the
## nearest trail point's smoothed height, fully within the trail's width, easing off over the
## shoulder. Water, the quarry pit and the hub (already flat) are left alone.
func _grade_and_paint() -> void:
	var best := {}  # pixel index -> [distance to the nearest trail point, that point's graded height]
	var reach := TRAIL_HALF_WIDTH + TRAIL_SHOULDER
	var window := int(TRAIL_SMOOTH)
	for line in trails:
		var raw := PackedFloat32Array()
		for p in line:
			raw.append(height_at(p))
		var profile := PackedFloat32Array()
		for k in line.size():
			var sum := 0.0
			var count := 0
			for j in range(maxi(k - window, 0), mini(k + window, line.size() - 1) + 1):
				sum += raw[j]
				count += 1
			profile.append(maxf(sum / count, WATER_LEVEL + 0.25))
		_limit_grade(profile, TRAIL_MAX_GRADE)  # points are a metre apart
		for k in line.size():
			var graded := profile[k]
			var at := line[k]
			_for_pixels_near(at, reach, func(i: int, w: Vector2) -> void:
				var d := w.distance_to(at)
				if not best.has(i) or d < best[i][0]:
					best[i] = [d, graded])
	for i in best:
		var w := world(i % size, i / size)
		if heights[i] < WATER_LEVEL + 0.1 or _in_pit(w) or w.distance_to(hub) < HUB_RADIUS:
			continue
		var d: float = best[i][0]
		var t := 1.0 - smoothstep(TRAIL_HALF_WIDTH, reach, d)
		heights[i] = lerpf(heights[i], best[i][1], t)
		if d < TRAIL_HALF_WIDTH:
			ids[i] = WorldMap.TEX_PATH


# --- landmarks --------------------------------------------------------------------------------

## Out in the wilds, away from trails, water, the hub, the village and the quarry, and from each
## other: ruins (one, sometimes two), an abandoned camp (one, sometimes two) and one to three rare
## spots of different kinds. Ruins and camps stand on a levelled pad. ProcgenWorld builds them.
const RUIN_KINDS := [[&"broken_tower", "Broken Tower"], [&"old_colonnade", "Old Colonnade"]]
const RARE_KINDS := [
	# [kind, name, biomes it may be in (empty = any but Frostpeak and the quarry)]
	[&"crystal_outcrop", "Crystal Outcrop", [&"frostpeak", &"quarry"]],
	[&"gold_vein", "Gold Vein", [&"frostpeak", &"quarry", &"pinewood"]],
	[&"ancient_oaks", "Ancient Oaks", []],
	[&"pike_pond", "Pike Pond", []],
	[&"flower_meadow", "Flower Meadow", []],
]
const LANDMARK_GAP := 55.0
const PAD_RADIUS := 8.0
const PAD_BLEND := 6.0
## How steep the ground under a landmark may be (rise over PAD_RADIUS).
const LANDMARK_MAX_RISE := 2.5
const PIKE_POND := {"radius": 6.0, "depth": 0.95}


func _place_landmarks() -> void:
	landmarks.clear()
	var lrng := RandomNumberGenerator.new()
	lrng.seed = sub_seed(&"landmarks")
	var ruins := 1 + int(lrng.randf() < 0.4)
	for k in ruins:
		var kind: Array = RUIN_KINDS[lrng.randi_range(0, RUIN_KINDS.size() - 1)]
		_add_landmark(lrng, &"ruins", kind[0], kind[1], [], true)
	var camps := 1 + int(lrng.randf() < 0.5)
	for k in camps:
		_add_landmark(lrng, &"camp", &"abandoned_camp", "Abandoned Camp", [], true)
	var rares := RARE_KINDS.duplicate()
	for i in range(rares.size() - 1, 0, -1):  # shuffled, then the first one to three
		var j := lrng.randi_range(0, i)
		var t: Variant = rares[i]
		rares[i] = rares[j]
		rares[j] = t
	for k in lrng.randi_range(1, 3):
		_add_landmark(lrng, &"rare", rares[k][0], rares[k][1], rares[k][2], rares[k][0] == &"pike_pond")


## Finds a spot for one landmark (in `biomes` if given) and records it; a pad levels the ground.
func _add_landmark(lrng: RandomNumberGenerator, type: StringName, kind: StringName, title: String,
		biomes: Array, pad: bool) -> void:
	for attempt in 400:
		var p := Vector2(lrng.randf_range(-_far(165.0), _far(165.0)), lrng.randf_range(-_far(165.0), _far(165.0)))
		var angle := lrng.randf() * TAU
		if not _landmark_spot_ok(p, biomes):
			continue
		var h := height_at(p)
		var landmark := {"type": type, "kind": kind, "name": title, "pos": p, "angle": angle, "height": h}
		if kind == &"pike_pond":
			_basin("PikePond", p, PIKE_POND["radius"], PIKE_POND["depth"], false, false, 6.0)
			waters[-1]["schools"] = &"pike"
		elif pad:
			_level_pad(p, h)
		landmarks.append(landmark)
		return


func _landmark_spot_ok(p: Vector2, biomes: Array) -> bool:
	if _rim(p) > 0.0 or p.distance_to(hub) < HUB_RADIUS + hub_ramp + 10.0:
		return false
	var biome := biome_at(p)
	if biomes.is_empty():
		if biome in [&"frostpeak", &"quarry", &""]:
			return false
	elif not biome in biomes:
		return false
	if not village.is_empty() and p.distance_to(village["center"]) < VILLAGE_RADIUS + VILLAGE_RAMP + 10.0:
		return false
	if not quarry.is_empty() and p.distance_to(quarry["center"]) < quarry_walls[0] + QUARRY_APRON + 8.0:
		return false
	for w in waters:
		if p.distance_to(w["center"]) < float(w["radius"]) + PAD_RADIUS + 12.0:
			return false
	for l in landmarks:
		if p.distance_to(l["pos"]) < LANDMARK_GAP:
			return false
	# clear of trails and rivers, and on fairly even ground
	var h := height_at(p)
	for k in 12:
		for r in [PAD_RADIUS * 0.5, PAD_RADIUS + PAD_BLEND]:
			var q: Vector2 = p + Vector2.from_angle(k * TAU / 12.0) * r
			var i := pixel_index(q)
			if ids[i] == WorldMap.TEX_PATH or river_mask[i] or heights[i] < WATER_LEVEL + 0.3:
				return false
			if r < PAD_RADIUS and absf(height_at(q) - h) > LANDMARK_MAX_RISE:
				return false
	return true


func _level_pad(at: Vector2, h: float) -> void:
	_for_pixels_near(at, PAD_RADIUS + PAD_BLEND, func(i: int, w: Vector2) -> void:
		var d := w.distance_to(at) + _shore.get_noise_2dv(w) * 1.0
		heights[i] = lerpf(h, heights[i], smoothstep(PAD_RADIUS, PAD_RADIUS + PAD_BLEND, d)))


# --- preview ----------------------------------------------------------------------------------

const PREVIEW_TINT := {
	&"clearing": Color(0.45, 0.62, 0.33), &"pinewood": Color(0.20, 0.38, 0.22),
	&"goldmeadow": Color(0.74, 0.70, 0.36), &"stillwater": Color(0.38, 0.55, 0.52),
	&"quarry": Color(0.62, 0.58, 0.52), &"frostpeak": Color(0.70, 0.74, 0.80),
	&"hearthvale": Color(0.62, 0.56, 0.40),
}


## A top-down picture of the map, a pixel per map pixel: each biome tinted, shaded by height and
## lit from the north-west, snow above the snow line, water, paths and quarry stone. `marks`: the
## sites (red crosses) and landmarks (squares) too, for checking a seed at a glance.
func preview_image(marks := true) -> Image:
	var img := Image.create_empty(size, size, false, Image.FORMAT_RGB8)
	var rise := 0.25 / step  # the shading reads a slope, whatever the pixel size
	for y in size:
		for x in size:
			var i := y * size + x
			var h := heights[i]
			var c: Color = Color(0.47, 0.46, 0.45) if cells[i] == RIM_CELL else PREVIEW_TINT.get(sites[cells[i]]["biome"], Color.MAGENTA)
			c = c.lerp(Color(0.47, 0.46, 0.45), clampf((h - 20.0) / 18.0, 0.0, 0.6))
			if h > 38.0:
				c = Color(0.92, 0.94, 0.96)
			if ids[i] == WorldMap.TEX_PATH:
				c = Color(0.63, 0.52, 0.40)
			elif ids[i] == WorldMap.TEX_QUARRY:
				c = Color(0.72, 0.69, 0.62)
			if h < WATER_LEVEL:
				c = Color(0.25, 0.45, 0.62).darkened(clampf((WATER_LEVEL - h) * 0.3, 0.0, 0.5))
			var east := heights[y * size + mini(x + 1, size - 1)] - h
			var south := heights[mini(y + 1, size - 1) * size + x] - h
			var light := clampf(1.0 + (east + south) * rise, 0.6, 1.3)  # rising to the south-east = facing the light
			img.set_pixel(x, y, c * light)
	if not marks:
		return img
	var last := Vector2i(size - 1, size - 1)
	for site in sites:
		var p := Vector2i(((site["pos"] as Vector2) - origin) / step)
		for k in range(-3, 4):
			img.set_pixelv((p + Vector2i(k, 0)).clamp(Vector2i.ZERO, last), Color.RED)
			img.set_pixelv((p + Vector2i(0, k)).clamp(Vector2i.ZERO, last), Color.RED)
	var colours := {&"ruins": Color.MAGENTA, &"camp": Color.ORANGE, &"rare": Color.YELLOW}
	for l in landmarks:  # a little square each
		var p := Vector2i(((l["pos"] as Vector2) - origin) / step)
		for dy in range(-2, 3):
			for dx in range(-2, 3):
				img.set_pixelv((p + Vector2i(dx, dy)).clamp(Vector2i.ZERO, last), colours[l["type"]])
	return img


func write_preview(path: String) -> Error:
	return preview_image().save_png(path)
