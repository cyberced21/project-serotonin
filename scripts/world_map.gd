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
const QUARRY_SLOPE := 40.0  # then the mountainside falls away over this
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

## The ring road: a closed loop through these points (Catmull-Rom), clockwise from the north.
const RING: Array[Vector2] = [
	Vector2(-40, -165), Vector2(40, -152), Vector2(120, -125), Vector2(175, -60), Vector2(192, 20),
	Vector2(160, 80), Vector2(95, 112), Vector2(30, 150), Vector2(-50, 150), Vector2(-95, 95),
	Vector2(-105, 25), Vector2(-110, -45), Vector2(-140, -110), Vector2(-100, -160),
]
const ROAD_HALF_WIDTH := 3.0
## The gully the road jumps: half of it is bridged by earth, the other half is a 6 m gap.
const GULLY_NEAR := Vector2(184, -20)

## The forest trail, from the clearing's north edge past the glades to the ring road.
const TRAIL: Array[Vector2] = [
	Vector2(1, -26), Vector2(-2, -52), Vector2(3, -67), Vector2(-12, -80), Vector2(-18, -92),
	Vector2(5, -104), Vector2(28, -112), Vector2(14, -128), Vector2(-8, -138), Vector2(-2, -150),
	Vector2(2, -160),
]
## Spurs from the ring road (each starts on the road; the first point snaps to it).
const SPURS: Array = [
	[Vector2(-14, 151), Vector2(-15, 120), Vector2(-15, 96)],  # down to the lake's south shore
	[Vector2(192, 20), Vector2(165, 26), Vector2(140, 30)],    # into the village from the east
	[Vector2(128, 96), Vector2(145, 125), Vector2(160, 150)],  # into the field
]

const QUARRY_CENTER_3 := Vector3(-175, 0, -15)
## Debug-menu teleports: name -> [where, look at].
const LANDMARKS := {
	"The Pinewood": [Vector3(20, 0, -106), Vector3(28, 0, -112)],
	"Quarry rim": [Vector3(-122, 0, -41), QUARRY_CENTER_3],
	"Quarry floor": [Vector3(-175, 0, -8), QUARRY_CENTER_3],
	"Goldmeadow": [Vector3(150, 0, 140), Vector3(165, 0, 160)],
	"Ring road": [Vector3(2, 0, -158), Vector3(40, 0, -152)],
	"The gully": [Vector3(186, 0, -45), Vector3(184, 0, -20)],
	"Frostpeak": [Vector3(-80, 0, -80), Vector3(-92, 0, -92)],
}


static var _ring: PackedVector2Array


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


## The ring road's centre line (cached): the samples the terrain generator graded it along.
static func ring() -> PackedVector2Array:
	if _ring.is_empty():
		_ring = spline(RING, true)
	return _ring

