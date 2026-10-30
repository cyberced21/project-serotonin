class_name WorldMap
extends RefCounted
## Where the biomes, the ring road and their landmarks sit. Shared by the terrain generator
## (tools/generate_test_terrain.gd) and the debug menu's teleports.
## Changing a shape here means regenerating the terrain; hand-placed nodes keep their ground
## (the generator protects them), but spawned things follow the new shape.

## Control-map base texture ids. The terrain shader colours them, footsteps.gd picks the sound
## and SceneryScatter keeps plants off the bare ones.
const TEX_DEFAULT := 0   # grass / dirt / rock / sand / snow by slope and height
const TEX_PATH := 1      # dirt paths, lanes, the forest trail, field tracks, the quarry haul road
const TEX_ROAD := 2      # the gravel ring road and its spurs
const TEX_FOREST := 3    # forest floor
const TEX_FIELD := 4     # meadow
const TEX_QUARRY := 5    # quarry stone
const TEX_CROP := 6      # crop squares in the field

## The places (plans/world-pass.md, map C): Hearthvale low in the middle of a wide bowl, the
## others on the hills round its rim, each up its own road. The world spans -256..512 on both axes
## (3 x 3 Terrain3D regions of 256 m), so the middle is (128, 128). Keep in sync with
## tools/generate_test_terrain.gd; the Biome autoload tells them apart.
const WORLD_MIN := -256.0
const WORLD_SIZE := 768.0
const VILLAGE_CENTER := Vector2(128, 128)
## The village's flat (the green, the lanes, the yards round them) and the bowl round it: flat
## floor out to BOWL_FLOOR, rising to BOWL_RIM_HEIGHT by BOWL_RIM.
const VILLAGE_RADIUS := 72.0
const BOWL_FLOOR := 115.0
const BOWL_RIM := 250.0
const BOWL_RIM_HEIGHT := 22.0
const CLEARING_CENTER := Vector2(46, 66)
const LAKE_CENTER := Vector2(38, 338)
const PEAK_CENTER := Vector2(-98, -54)

## Greystone Quarry: a stepped pit on the west rim, past the peak's foot.
const QUARRY_CENTER := Vector2(-118, 88)
const QUARRY_RIM_HEIGHT := 26.0
const QUARRY_LEVEL_DROP := 5.0
## Radii of the walls between levels, outermost first: rim | 1 | 2 | 3 | 4 | floor.
const QUARRY_WALLS: Array[float] = [55.0, 45.0, 35.0, 25.0, 15.0]
const QUARRY_APRON := 10.0  # flat ground round the rim
const QUARRY_SLOPE := 120.0  # then the hillside falls away over about this (gently: the road climbs it)
## Direction (radians, from the centre) of the haul road's top, where the road from the village arrives.
const QUARRY_ROAD_ANGLE := -0.4636

## Goldmeadow: a broad plain of gentle swells, crop squares and dirt tracks, on the south-east rim.
const FIELD_CENTER := Vector2(338, 318)
const FIELD_RADIUS := 97.0
const FIELD_RAMP := 45.0

## The Pinewood: an ellipse over the northern rim hills, with flattened glades along the trail.
const FOREST_CENTER := Vector2(118, -112)
const FOREST_RADII := Vector2(172, 108)
const GLADES: Array[Vector2] = [Vector2(61, -62.5), Vector2(130, -92.5), Vector2(76, -131.5)]
const GLADE_RADIUS := 13.5

## The roads and paths (plans/world.md): the terrain generator lays each one along the land (a
## least-cost route over the slopes from `from` through any `via` points to `to`, unless `ctrl`
## fixes its line), and
## writes the lines it laid to scripts/world_roads.gd; roads() reads them back. `join` starts a
## road on another one, at its point nearest `from`. `lamps`: a stretch the Lamps can light, its
## points running out from the village end. Order matters: a road can only join one laid before it.
## In the bowl every road is a spoke out from the green's edge to its place on the rim.
const ROAD_HALF_WIDTH := 2.5
const PATH_HALF_WIDTH := 1.6
const QUARRY_RIM_POINT := Vector2(-65, 61)  # on the apron where the haul road leaves the rim (QUARRY_ROAD_ANGLE)
const ROADS: Array[Dictionary] = [
	{"id": &"village_path", "title": "The path from the clearing", "kind": &"path", "village": true, "reverse": true,
		"ctrl": VILLAGE_PATH},
	{"id": &"village_road", "title": "The road to the Pinewood", "kind": &"road", "village": true,
		"from": Vector2(128, 58), "to": Vector2(124, -6)},
	{"id": &"forest_trail", "title": "The forest trail", "kind": &"path",
		"from": Vector2(124, -6), "via": [Vector2(76, -131.5)],  # (on from the road's end, up past the spring)
		"to": Vector2(61, -62.5)},
	{"id": &"quarry_road", "title": "The road to the quarry", "kind": &"road",
		"from": Vector2(58, 132), "to": QUARRY_RIM_POINT},  # (over the creek: the router keeps off its banks)
	{"id": &"lake_road", "title": "The road to the lake", "kind": &"road",
		"from": Vector2(118, 198), "to": Vector2(66, 316)},
	{"id": &"peak_path", "title": "The path up Frostpeak", "kind": &"path",
		"from": Vector2(-20, 80), "join": &"quarry_road", "to": Vector2(-76, -14)},
	{"id": &"field_road", "title": "The road to Goldmeadow", "kind": &"road",
		"from": Vector2(178, 178), "to": Vector2(268, 252)},
	{"id": &"east_road", "title": "The road east", "kind": &"road", "village": true, "ctrl": EAST_ROAD},
]
## The road east (plans/market.md): from the green's east edge up through a pass in the eastern
## rim hills to the world's edge, the way traders come. The terrain generator cuts the pass along it.
const EAST_ROAD: Array[Vector2] = [Vector2(200, 126), Vector2(238, 120), Vector2(278, 126), Vector2(318, 134),
	Vector2(358, 132), Vector2(398, 124), Vector2(438, 122), Vector2(478, 128), Vector2(512, 130)]

## The dirt path from the clearing to the green, as the terrain generator's valley follows it
## (ROADS has the line it was laid on). It crosses the creek just below the clearing's pond (the
## footbridge project).
const VILLAGE_PATH: Array[Vector2] = [Vector2(56, 62), Vector2(72, 70), Vector2(88, 84), Vector2(102, 98),
	Vector2(116, 114), Vector2(128, 128)]

## The creek (plans/world.md): from a spring under the north rim, through the clearing's pond, down
## the bowl's west side past the village and out through a gap in the rim into the lake. Its water
## is level the whole way (at the ponds' height), built by scripts/creek.gd; the terrain generator
## carves its bed along the same spline.
const CREEK: Array[Vector2] = [
	Vector2(90, -36), Vector2(94, -12), Vector2(86, 16), Vector2(72, 44), Vector2(66, 70), Vector2(66, 86),
	Vector2(62, 108), Vector2(46, 138), Vector2(36, 178), Vector2(38, 223), Vector2(42, 268), Vector2(40, 308),
	Vector2(38, 333),
]
const CREEK_HALF_WIDTH := 1.8
## Deep pools scoured out at bends (salmon lie in them), near these points.
const CREEK_POOLS: Array[Vector2] = [Vector2(86, 16), Vector2(38, 223)]
const CREEK_POOL_RADIUS := 3.2

const QUARRY_CENTER_3 := Vector3(-118, 0, 88)
## Debug-menu teleports: name -> [where, look at].
const LANDMARKS := {
	"Hearthvale": [Vector3(128, 0, 150), Vector3(128, 0, 128)],
	"The clearing": [Vector3(56, 0, 76), Vector3(46, 0, 66)],
	"The Pinewood": [Vector3(118, 0, -83.5), Vector3(130, 0, -92.5)],
	"Quarry rim": [Vector3(-65, 0, 62), QUARRY_CENTER_3],
	"Quarry floor": [Vector3(-118, 0, 95), QUARRY_CENTER_3],
	"Goldmeadow": [Vector3(315.5, 0, 288), Vector3(338, 0, 318)],
	"Stillwater": [Vector3(66, 0, 316), Vector3(38, 0, 338)],
	"The spring": [Vector3(96, 0, -44), Vector3(90, 0, -36)],
	"The footbridge": [Vector3(60, 0, 72), Vector3(66, 0, 64)],
	"Frostpeak": [Vector3(-86, 0, -42), Vector3(-98, 0, -54)],
}


static var _roads: Array[Dictionary] = []
static var _creek: PackedVector2Array
static var _warp: Array[FastNoiseLite] = []


## Where the biomes' outlines are measured from: pushed around by two sizes of noise, so no border
## is an ellipse or a circle. The terrain generator paints the ground by it and the Biome autoload
## tells the places apart by it, so a place's card comes where its ground does.
static func biome_warp(w: Vector2) -> Vector2:
	if _warp.is_empty():
		for spec in [[31, 0.004], [32, 0.004], [17, 0.03]]:  # (the generator's warp and edge noise)
			var n := FastNoiseLite.new()
			n.seed = spec[0]
			n.frequency = spec[1]
			_warp.append(n)
	return w + Vector2(_warp[0].get_noise_2dv(w * 2.0), _warp[1].get_noise_2dv(w * 2.0)) * 24.0 			+ Vector2(_warp[2].get_noise_2dv(w), _warp[2].get_noise_2dv(w + Vector2(91, 37))) * 6.0


## Points about 1 m apart along a Catmull-Rom spline through `ctrl` (closed if `loop`). The
## terrain generator lays the roads along these, so anything placed by them lines up.
static func spline(ctrl: Array, loop: bool) -> PackedVector2Array:
	var out := PackedVector2Array()
	var m := ctrl.size()
	for s in (m if loop else m - 1):
		var p0: Vector2 = ctrl[(s - 1 + m) % m] if loop else ctrl[maxi(s - 1, 0)]
		var p1: Vector2 = ctrl[s]
		var p2: Vector2 = ctrl[(s + 1) % m]
		var p3: Vector2 = ctrl[(s + 2) % m] if loop else ctrl[mini(s + 2, m - 1)]
		var steps := maxi(1, ceili(p1.distance_to(p2)))
		for k in steps:
			var t := float(k) / steps
			out.append(0.5 * (2.0 * p1 + (p2 - p0) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t * t
					+ (3.0 * p1 - p0 - 3.0 * p2 + p3) * t * t * t))
	if not loop:
		out.append(ctrl[m - 1])
	return out


## The roads as laid (scripts/world_roads.gd, written by the terrain generator): each ROADS entry
## with its line, `pts` (about 1 m apart, from the village end for lamp stretches), and its
## `half_width`.
static func roads() -> Array[Dictionary]:
	if _roads.is_empty():
		var laid: Dictionary = load("res://scripts/world_roads.gd").LINES
		for spec in ROADS:
			var r := spec.duplicate()
			r["pts"] = PackedVector2Array(laid.get(spec["id"], []))
			r["half_width"] = ROAD_HALF_WIDTH if spec["kind"] == &"road" else PATH_HALF_WIDTH
			_roads.append(r)
	return _roads


## The creek's centre line (cached), source to mouth, about 1 m a sample.
static func creek() -> PackedVector2Array:
	if _creek.is_empty():
		_creek = spline(CREEK, false)
	return _creek
