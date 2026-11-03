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

## The places (plans/world-pass.md, map C; plans/map-maker.md): the map's areas, each placed in
## the map editor (its layout's "areas": {id, type, at: [x, z], yaw (degrees), name?, and its
## sizes}), one of each type at most. In Hearthvale: the village low in the middle of a wide bowl,
## the others on the hills round its rim, each up its own road. AREAS has each type's name, its
## biome (the Biome autoload's mood) and its sizes unless the area says, and where it stands in
## Hearthvale (`home`: what's built for it there, like the Frostpeak's ridges and the Pinewood's
## glades, moves and turns from there with it). A map without an area has none of it: area_at()
## is NOWHERE, far off the map, so nothing measured from it is ever near.
const AREAS := {
	&"village": {"name": "Hearthvale", "biome": &"hearthvale", "home": Vector2(137, 125)},
	&"clearing": {"name": "The Clearing", "biome": &"clearing", "home": Vector2(46, 66), "radius": 28.0},
	&"lake": {"name": "Stillwater", "biome": &"stillwater", "home": Vector2(38, 338), "radius": 34.0},
	&"frostpeak": {"name": "Frostpeak", "biome": &"frostpeak", "home": Vector2(-98, -54), "radius": 76.0},
	&"quarry": {"name": "Greystone Quarry", "biome": &"quarry", "home": Vector2(-118, 88)},
	&"goldmeadow": {"name": "Goldmeadow", "biome": &"goldmeadow", "home": Vector2(338, 318), "radius": 97.0},
	&"pinewood": {"name": "The Pinewood", "biome": &"pinewood", "home": Vector2(118, -112), "radii": Vector2(172, 108)},
}
const NOWHERE := Vector2(1e7, 1e7)
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

## Greystone Quarry: a stepped pit on the west rim, past the peak's foot (quarry_center()).
const QUARRY_RIM_HEIGHT := 26.0
const QUARRY_LEVEL_DROP := 5.0
## Radii of the walls between levels, outermost first: rim | 1 | 2 | 3 | 4 | floor.
const QUARRY_WALLS: Array[float] = [55.0, 45.0, 35.0, 25.0, 15.0]
const QUARRY_APRON := 10.0  # flat ground round the rim
const QUARRY_SLOPE := 120.0  # then the hillside falls away over about this (gently: the road climbs it)
## Direction (radians, from the centre) of the haul road's top, where the road from the village
## arrives (the quarry turned: plus its yaw, quarry_road_angle()).
const QUARRY_ROAD_ANGLE := -0.4636

## Goldmeadow: a broad plain of gentle swells, crop squares and dirt tracks, on the south-east rim
## (field_center(), field_radius()).
const FIELD_RAMP := 45.0

## The Pinewood: an ellipse over the northern rim hills (forest_center(), forest_radii()), with
## flattened glades along the trail (glades(): Hearthvale's at GLADES).
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


## The creek (plans/world.md): Hearthvale's runs from a spring under the north rim, through the
## clearing's pond, down the bowl's west side past the village and out through a gap in the rim
## into the lake. The layout's terrain line of type "creek" (one at most: {points, pools: [[x, z]...]}
## where deep pools are scoured out at bends, salmon lying in them): creek_points(), creek_pools().
## Its water is level the whole way (at the ponds' height), built by scripts/creek.gd; the terrain
## generator carves its bed along the same spline.
const CREEK_HALF_WIDTH := 2.4
const CREEK_POOL_RADIUS := 3.2

## Debug-menu teleports in Hearthvale: name -> [area, where, look at], each in that area's frame
## from its home (landmarks()).
const _LANDMARKS := {
	"Hearthvale": [&"village", Vector3(128, 0, 150), Vector3(128, 0, 128)],
	"The clearing": [&"clearing", Vector3(56, 0, 76), Vector3(46, 0, 66)],
	"The Pinewood": [&"pinewood", Vector3(118, 0, -83.5), Vector3(130, 0, -92.5)],
	"Quarry rim": [&"quarry", Vector3(-65, 0, 62), Vector3(-118, 0, 88)],
	"Quarry floor": [&"quarry", Vector3(-118, 0, 95), Vector3(-118, 0, 88)],
	"Goldmeadow": [&"goldmeadow", Vector3(315.5, 0, 288), Vector3(338, 0, 318)],
	"Stillwater": [&"lake", Vector3(66, 0, 316), Vector3(38, 0, 338)],
	"The spring": [&"", Vector3(96, 0, -44), Vector3(90, 0, -36)],
	"The footbridge": [&"", Vector3(60, 0, 72), Vector3(66, 0, 64)],
	"Frostpeak": [&"frostpeak", Vector3(-86, 0, -42), Vector3(-98, 0, -54)],
}


## The map's areas (its layout's "areas", read once a map; the file LayoutAnchors reads).
static func areas() -> Array:
	if _areas_of != LayoutAnchors.layout_path:
		_areas_of = LayoutAnchors.layout_path
		var layout := Maps.read_layout(_areas_of)
		_areas = layout.get("areas", [])
		_labels = []
		for l in layout.get("labels", []):
			_labels.append({"id": StringName(l["id"]), "name": l.get("name", ""), "at": Vector2(float(l["at"][0]), float(l["at"][1]))})
		_creek_line = {}
		for s in layout.get("terrain", []):
			if s.get("type", "") == "creek" and s.get("points", []).size() >= 2:
				_creek_line = s
		_creek = PackedVector2Array()
		_roads = []
	return _areas


## The map's area of `type`, or {} if it has none.
static func area(type: StringName) -> Dictionary:
	for a in areas():
		if StringName(a.get("type", "")) == type:
			return a
	return {}


static func has_area(type: StringName) -> bool:
	return not area(type).is_empty()


## Where the area of `type` stands (NOWHERE without one).
static func area_at(type: StringName) -> Vector2:
	var a := area(type)
	if a.is_empty():
		return NOWHERE
	return Vector2(float(a["at"][0]), float(a["at"][1]))


## The area's turn about the vertical (radians), as anchors turn (Godot's: +Y).
static func area_yaw(type: StringName) -> float:
	return deg_to_rad(float(area(type).get("yaw", 0.0)))


## The area's size `key` (its own, else its type's).
static func area_size(type: StringName, key: String) -> Variant:
	var a := area(type)
	if a.has(key):
		var v: Variant = a[key]
		return Vector2(float(v[0]), float(v[1])) if v is Array else float(v)
	return AREAS[type].get(key)


## Point `p`, placed for the area's Hearthvale home, where it is now: moved and turned with the
## area (as an anchor turns its things: plans/map-editor-places.md).
static func from_home(type: StringName, p: Vector2) -> Vector2:
	var d := p - (AREAS[type]["home"] as Vector2)
	var yaw := area_yaw(type)
	if yaw != 0.0:
		var w := Vector3(d.x, 0.0, d.y).rotated(Vector3.UP, yaw)
		d = Vector2(w.x, w.z)
	return area_at(type) + d


static func clearing_center() -> Vector2:
	return area_at(&"clearing")


static func lake_center() -> Vector2:
	return area_at(&"lake")


static func peak_center() -> Vector2:
	return area_at(&"frostpeak")


static func quarry_center() -> Vector2:
	return area_at(&"quarry")


static func quarry_center_3() -> Vector3:
	var c := quarry_center()
	return Vector3(c.x, 0.0, c.y)


## Where the haul road's top is, from the pit's middle (radians): the quarry turned turns it.
## (A turn about +Y by `yaw` takes the map angle a to a - yaw.)
static func quarry_road_angle() -> float:
	return QUARRY_ROAD_ANGLE - area_yaw(&"quarry")


static func field_center() -> Vector2:
	return area_at(&"goldmeadow")


static func field_radius() -> float:
	return area_size(&"goldmeadow", "radius")


static func forest_center() -> Vector2:
	return area_at(&"pinewood")


static func forest_radii() -> Vector2:
	return area_size(&"pinewood", "radii")


## The Pinewood's glades, where it stands (none without it).
static func glades() -> Array[Vector2]:
	var out: Array[Vector2] = []
	if has_area(&"pinewood"):
		for g in GLADES:
			out.append(from_home(&"pinewood", g))
	return out


## The creek's line as drawn (its control points: none on a map without one).
static func creek_points() -> Array[Vector2]:
	areas()
	var out: Array[Vector2] = []
	for q in _creek_line.get("points", []):
		out.append(Vector2(float(q[0]), float(q[1])))
	return out


## Where the creek's deep pools are.
static func creek_pools() -> Array[Vector2]:
	areas()
	var out: Array[Vector2] = []
	for q in _creek_line.get("pools", []):
		out.append(Vector2(float(q[0]), float(q[1])))
	return out


## The names written on the map where nothing else is (the layout's "labels", placed in the map
## editor: {id, name, at}): [{id, name, at: Vector2}].
static func labels() -> Array:
	areas()
	return _labels


## Debug-menu teleports: name -> [where, look at], for the areas the map has.
static func landmarks() -> Dictionary:
	var out := {}
	for name in _LANDMARKS:
		var l: Array = _LANDMARKS[name]
		var type: StringName = l[0]
		if type == &"":
			if Maps.current() != Maps.DEFAULT:
				continue
			out[name] = [l[1], l[2]]
			continue
		if not has_area(type):
			continue
		var at := from_home(type, Vector2(l[1].x, l[1].z))
		var look := from_home(type, Vector2(l[2].x, l[2].z))
		out[name] = [Vector3(at.x, 0, at.y), Vector3(look.x, 0, look.y)]
	return out


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
static var _areas: Array = []
static var _areas_of := ""
static var _creek_line: Dictionary = {}
static var _labels: Array = []
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
	var ctrl := creek_points()
	if _creek.is_empty() and ctrl.size() >= 2:
		_creek = spline(ctrl, false)
	return _creek
