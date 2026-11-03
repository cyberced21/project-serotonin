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
## The middle of the village green is the map editor's (its anchor, "green": village_center()).
## The village's flat (the green, the lanes, the yards round them) and the bowl round it: flat
## floor out to BOWL_FLOOR, rising to BOWL_RIM_HEIGHT by BOWL_RIM.
const VILLAGE_RADIUS := 72.0
## The market place (plans/village-street.md): where the village street widens round the green's
## anchor, along the green's X. MARKET_LENGTH end to end, MARKET_HALF_WIDTH either side at the
## middle (market_half_width(), in_market()).
const MARKET_LENGTH := 52.0
const MARKET_HALF_WIDTH := 14.0
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
## The new places (plans/world-pass.md, phase 7): the watermill on the creek below the village, the
## orchard on the slope north-east of it, the shepherd's hill up on the rim north of the road east,
## and the hidden haven deep in the Pinewood's south, its spring pool. Where they stand is the map
## editor's (their anchors in data/layout/hearthvale.json: plans/map-editor-places.md), so they're
## read, not constants: site(&"watermill"), site(&"orchard"), site(&"shepherds_hill"), haven_center().
const HAVEN_RADIUS := 16.0
## The haven's spring pool, in the haven's frame (it turns with the haven).
const HAVEN_POOL := {"offset": Vector2(3, 2), "radius": 3.5, "depth": 0.5}

## The roads and paths (plans/world.md, plans/map-maker.md): the layout's terrain lines of type
## "road" and "path", drawn in the map editor. The terrain generator lays each one along the land,
## in the layout's order, and writes the lines it laid to the map's roads file (Hearthvale's
## scripts/world_roads.gd); roads() reads them back. Each line is (road_spec turns it into the
## generator's spec):
##   {id, type: road | path, name, points: [[x, z]...]}  its line, fixed (Catmull-Rom through them)
##   route: true      the points are stops instead: a least-cost route over the slopes from the first
##                    through the others to the last
##   join / join_end  start (end) on that road, at its point nearest the first (last) point; a road
##                    can only join one laid before it
##   place, place_to, drawn_at  the path ends in that place's own frame (place_to), wherever the place
##                    stands; moved away from drawn_at, it leaves the road nearest it instead
##   village          a stretch the Lamps can light, its points running out from the village end
##   reverse          its laid line runs last point to first (for the lamps)
##   valley           the land is eased down along it (a valley through the hills)
##   pass             the world's edge dips to a saddle where it climbs out (the way traders come)
##   spoke            a notch through the village's bowl, along the line from the village to its end
const ROAD_HALF_WIDTH := 2.5
const PATH_HALF_WIDTH := 1.6
const QUARRY_RIM_POINT := Vector2(-65, 61)  # on the apron where the haul road leaves the rim (QUARRY_ROAD_ANGLE)
const _ROAD_FLAGS := ["village", "reverse", "valley", "pass", "spoke"]


## Layout line `s` (a road or path) as the terrain generator lays it: {id, kind, title, points,
## and ctrl (a fixed line) or from, via, to (a route), with join, join_end, place, drawn_at and the
## flags it has}.
static func road_spec(s: Dictionary) -> Dictionary:
	var pts: Array[Vector2] = []
	for q in s.get("points", []):
		pts.append(Vector2(float(q[0]), float(q[1])))
	var spec := {"id": StringName(s["id"]), "kind": StringName(s.get("type", "road")), "title": s.get("name", s["id"]), "points": pts}
	if s.get("route", false):
		spec["from"] = pts[0]
		spec["to"] = pts[-1]
		if pts.size() > 2:
			spec["via"] = pts.slice(1, -1)
	else:
		spec["ctrl"] = pts
	for k in ["join", "join_end"]:
		if s.get(k, "") != "":
			spec[k] = StringName(s[k])
	if s.get("place", "") != "":
		spec["place"] = StringName(s["place"])
		var local: Array = s.get("place_to", [0, 0])
		spec["to"] = Vector2(float(local[0]), float(local[1]))
		var drawn: Array = s.get("drawn_at", [])
		if drawn.size() == 2:
			spec["drawn_at"] = Vector2(float(drawn[0]), float(drawn[1]))
	for k in _ROAD_FLAGS:
		if s.get(k, false):
			spec[k] = true
	return spec


## The creek (plans/world.md): from a spring under the north rim, through the clearing's pond, down
## the bowl's west side past the village and out through a gap in the rim into the lake. Its water
## is level the whole way (at the ponds' height), built by scripts/creek.gd; the terrain generator
## carves its bed along the same spline.
const CREEK: Array[Vector2] = [
	Vector2(90, -36), Vector2(94, -12), Vector2(86, 16), Vector2(72, 44), Vector2(66, 70), Vector2(66, 86),
	Vector2(62, 108), Vector2(46, 138), Vector2(36, 178), Vector2(38, 223), Vector2(42, 268), Vector2(40, 308),
	Vector2(38, 333),
]
const CREEK_HALF_WIDTH := 2.4
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


## Where anchored place `id` stands (LayoutAnchors; the origin if the layout has no such anchor).
static func site(id: StringName) -> Vector2:
	return LayoutAnchors.at(id, Vector2.ZERO)


## Offset `local` in anchored place `id`'s frame (turned with it), on the map.
static func in_frame(id: StringName, local: Vector2) -> Vector2:
	var w := Vector3(local.x, 0.0, local.y).rotated(Vector3.UP, LayoutAnchors.yaw(id))
	return site(id) + Vector2(w.x, w.z)


## The middle of the village green (its anchor; the bowl and the village's flat are round it).
static func village_center() -> Vector2:
	return LayoutAnchors.at(&"green", Vector2(128, 128))


## Half the market place's width (m) `along` metres from its middle, in the green's frame (0 past
## its ends): a lens, widest in the middle.
static func market_half_width(along: float) -> float:
	if absf(along) >= MARKET_LENGTH / 2.0:
		return 0.0
	return MARKET_HALF_WIDTH * sin(PI * (along + MARKET_LENGTH / 2.0) / MARKET_LENGTH)


## Whether `p` (world XZ) is on the market place's paving.
static func in_market(p: Vector2) -> bool:
	var d := p - village_center()
	var l := Vector3(d.x, 0.0, d.y).rotated(Vector3.UP, -LayoutAnchors.yaw(&"green"))
	return absf(l.z) < market_half_width(l.x)


static func haven_center() -> Vector2:
	return site(&"haven")


## The middle of the haven's spring pool on the map.
static func haven_pool_center() -> Vector2:
	return in_frame(&"haven", HAVEN_POOL["offset"])


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


## The roads as laid (the map's roads file, Maps.path("roads"): scripts/world_roads.gd for
## Hearthvale, written by the terrain generator): each road's spec (road_spec) with its laid line,
## `pts` (about 1 m apart, from the village end for lamp stretches), and its `half_width`.
static func roads() -> Array[Dictionary]:
	if _roads.is_empty():
		var file := Maps.path("roads")
		if not ResourceLoader.exists(file):
			return _roads  # (a map whose land isn't made yet: no roads)
		var written: GDScript = load(file)
		var laid: Dictionary = written.LINES
		for spec in written.get_script_constant_map().get("EXTRA", []):
			var r: Dictionary = spec.duplicate()
			r["pts"] = PackedVector2Array(laid.get(spec["id"], []))
			r["half_width"] = ROAD_HALF_WIDTH if spec["kind"] == &"road" else PATH_HALF_WIDTH
			_roads.append(r)
	return _roads


## Road `id` as roads() has it, or {} if the map has none such.
static func road(id: StringName) -> Dictionary:
	for r in roads():
		if r["id"] == id:
			return r
	return {}


## The creek's centre line (cached), source to mouth, about 1 m a sample.
static func creek() -> PackedVector2Array:
	if _creek.is_empty():
		_creek = spline(CREEK, false)
	return _creek
