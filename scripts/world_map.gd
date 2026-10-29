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

## The original places (keep in sync with tools/generate_test_terrain.gd): the Biome autoload
## tells them apart by distance.
const CLEARING_CENTER := Vector2(0, -4)
const VILLAGE_CENTER := Vector2(100, 40)
const LAKE_CENTER := Vector2(-16, 74)
const PEAK_CENTER := Vector2(-92, -92)

## Greystone Quarry: a stepped pit on a mountain shoulder west of the peak.
const QUARRY_CENTER := Vector2(-175, -15)
const QUARRY_RIM_HEIGHT := 26.0
const QUARRY_LEVEL_DROP := 5.0
## Radii of the walls between levels, outermost first: rim | 1 | 2 | 3 | 4 | floor.
const QUARRY_WALLS: Array[float] = [55.0, 45.0, 35.0, 25.0, 15.0]
const QUARRY_APRON := 10.0  # flat ground round the rim
const QUARRY_SLOPE := 75.0  # then the mountainside falls away over about this
## Direction (radians, from the centre) of the haul road's top, where the spur from the ring arrives.
const QUARRY_ROAD_ANGLE := -0.4636

## Goldmeadow: a broad plain of gentle swells, crop squares and dirt tracks.
const FIELD_CENTER := Vector2(165, 160)
const FIELD_RADIUS := 65.0
const FIELD_RAMP := 30.0

## The Pinewood: an ellipse over the northern hills, with flattened glades along the trail.
const FOREST_CENTER := Vector2(20, -125)
const FOREST_RADII := Vector2(115, 72)
const GLADES: Array[Vector2] = [Vector2(-18, -92), Vector2(28, -112), Vector2(-8, -138)]
const GLADE_RADIUS := 9.0

## The roads and paths (plans/world.md): the terrain generator lays each one along the land (a
## least-cost route over the slopes from `from` through any `via` points to `to`, unless `ctrl`
## fixes its line), and
## writes the lines it laid to scripts/world_roads.gd; roads() reads them back. `join` starts a
## road on another one, at its point nearest `from`. `lamps`: a stretch the Lamps can light, its
## points running out from the village end. Order matters: a road can only join one laid before it.
const ROAD_HALF_WIDTH := 2.5
const PATH_HALF_WIDTH := 1.6
const QUARRY_RIM_POINT := Vector2(-122, -42)  # on the apron where the haul road leaves the rim (QUARRY_ROAD_ANGLE)
const ROADS: Array[Dictionary] = [
	{"id": &"village_path", "title": "The path from the clearing", "kind": &"path", "village": true, "reverse": true,
		"ctrl": [Vector2(22, -2), Vector2(42, 6), Vector2(62, 20), Vector2(80, 34), Vector2(100, 40)]},
	{"id": &"lake_path", "title": "The path to the lake", "kind": &"path",
		"ctrl": [Vector2(-3, 16), Vector2(-6, 32), Vector2(-11, 48), Vector2(-15, 59)]},
	{"id": &"forest_trail", "title": "The forest trail", "kind": &"path",
		"ctrl": [Vector2(1, -26), Vector2(-2, -52), Vector2(3, -67), Vector2(-12, -80), Vector2(-18, -92),
			Vector2(5, -104), Vector2(28, -112), Vector2(14, -128), Vector2(-8, -138), Vector2(-2, -150)]},
	{"id": &"quarry_road", "title": "The road to the quarry", "kind": &"road",
		"from": Vector2(-30, -8), "via": [Vector2(-92, 28)], "to": QUARRY_RIM_POINT},
	{"id": &"lake_road", "title": "The road round the lake", "kind": &"road",
		"from": Vector2(-42, 84), "to": Vector2(-80, -22), "join_end": &"quarry_road"},
	{"id": &"peak_path", "title": "The path up Frostpeak", "kind": &"path",
		"from": Vector2(-98, -32), "join": &"quarry_road", "to": Vector2(-80, -62)},
	{"id": &"field_road", "title": "The road to Goldmeadow", "kind": &"road",
		"from": Vector2(128, 62), "to": Vector2(150, 130)},
	{"id": &"village_road", "title": "The village road", "kind": &"road", "village": true,
		"from": Vector2(112, 10), "to": Vector2(74, -86)},
	{"id": &"east_road", "title": "The road east", "kind": &"road", "village": true, "ctrl": EAST_ROAD},
]
## The road east (plans/market.md): from the village up through a pass in the eastern rim hills to
## the world's edge, the way traders come. The terrain generator cuts the pass along it.
const EAST_ROAD: Array[Vector2] = [Vector2(126, 34), Vector2(150, 30), Vector2(176, 22), Vector2(202, 18),
	Vector2(226, 16), Vector2(252, 14)]

## The dirt paths from the clearing, as the terrain generator's valleys follow them (ROADS has
## the lines they were laid on): over to the village square, and south to the lake shore.
const VILLAGE_PATH: Array[Vector2] = [Vector2(22, -2), Vector2(42, 6), Vector2(62, 20), Vector2(80, 34), Vector2(100, 40)]
const LAKE_PATH: Array[Vector2] = [Vector2(-3, 16), Vector2(-6, 32), Vector2(-11, 48), Vector2(-15, 59)]

## The creek (plans/world.md): from a spring at the foot of the Pinewood hills, down its own
## shallow vale past the clearing, through the clearing's pond and on into the lake. Its water is
## level the whole way (at the ponds' height), built by scripts/creek.gd; the terrain generator
## carves its bed along the same spline.
const CREEK: Array[Vector2] = [
	Vector2(36, -70), Vector2(31, -50), Vector2(35, -30), Vector2(31, -10), Vector2(26, 4),
	Vector2(20, 16), Vector2(18, 26), Vector2(11, 39), Vector2(3, 51), Vector2(-5, 61),
]
const CREEK_HALF_WIDTH := 1.8
## Deep pools scoured out at bends (salmon lie in them), near these points.
const CREEK_POOLS: Array[Vector2] = [Vector2(33, -40), Vector2(13, 36)]
const CREEK_POOL_RADIUS := 3.2

const QUARRY_CENTER_3 := Vector3(-175, 0, -15)
## Debug-menu teleports: name -> [where, look at].
const LANDMARKS := {
	"The Pinewood": [Vector3(20, 0, -106), Vector3(28, 0, -112)],
	"Quarry rim": [Vector3(-122, 0, -41), QUARRY_CENTER_3],
	"Quarry floor": [Vector3(-175, 0, -8), QUARRY_CENTER_3],
	"Goldmeadow": [Vector3(150, 0, 140), Vector3(165, 0, 160)],
	"The spring": [Vector3(40, 0, -78), Vector3(36, 0, -70)],
	"The footbridge": [Vector3(26, 0, 10), Vector3(28, 0, 0)],
	"Frostpeak": [Vector3(-80, 0, -80), Vector3(-92, 0, -92)],
}


static var _roads: Array[Dictionary] = []
static var _creek: PackedVector2Array


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
