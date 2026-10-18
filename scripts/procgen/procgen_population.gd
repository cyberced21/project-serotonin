class_name ProcgenPopulation
extends RefCounted
## Fills a generated world (ProcgenMap) with what you gather and what you walk through:
## - a NodeSpawner per biome cell, kept to its own cell, with that biome's trees, rocks or grain;
##   the inner ring gets the gentler mix, the outer ring the harder one (birch near the hub, pine
##   far out; copper and iron by the hub, coal and gold on Frostpeak's foothills);
## - in the quarry pit, one spawner per level, harder ore the deeper you go, crystal on the floor;
## - a SceneryScatter per biome cell, over just that cell's bounding box and with just its biome's
##   layers (so no layer samples ground it can't grow on): grass, flowers, bushes and boulders on
##   open ground, canopies and ferns on forest floor, meadow grass on the field, rubble in the
##   quarry. The rim is left bare.
## Spawners come first in the tree so the scenery keeps off their nodes.

const TREE := preload("res://scenes/tree.tscn")
const BIRCH := preload("res://scenes/birch_tree.tscn")
const OAK := preload("res://scenes/oak_tree.tscn")
const PINE := preload("res://scenes/pine_tree.tscn")
const ROCK := preload("res://scenes/rock.tscn")
const IRON := preload("res://scenes/iron_rock.tscn")
const COAL := preload("res://scenes/coal_rock.tscn")
const GOLD := preload("res://scenes/gold_rock.tscn")
const CRYSTAL := preload("res://scenes/crystal_rock.tscn")
const WHEAT := preload("res://scenes/wheat_sheaf.tscn")
const BARLEY := preload("res://scenes/barley_sheaf.tscn")

## Per biome and tier (0 hub, 1 inner ring, 2 outer ring): how many nodes, and [scene, weight] pairs.
const NODES := {
	&"clearing": {0: {"count": 12, "spacing": 5.0, "entries": [[TREE, 3.0], [ROCK, 2.0]]}},
	&"pinewood": {
		1: {"count": 22, "spacing": 4.5, "entries": [[BIRCH, 3.0], [TREE, 1.5], [PINE, 0.3]]},
		2: {"count": 26, "spacing": 4.5, "entries": [[PINE, 3.0], [BIRCH, 1.0]]},
	},
	&"goldmeadow": {1: {"count": 24, "spacing": 4.0, "entries": [[WHEAT, 3.0], [BARLEY, 1.5], [OAK, 1.2]]}},
	&"stillwater": {2: {"count": 12, "spacing": 5.0, "entries": [[OAK, 2.0], [TREE, 1.0], [IRON, 1.0]]}},
	&"frostpeak": {2: {"count": 14, "spacing": 5.5, "entries": [[COAL, 2.0], [GOLD, 1.5], [IRON, 1.0]],
			"min_normal_y": 0.8}},
	&"quarry": {2: {"count": 6, "spacing": 5.0, "entries": [[ROCK, 2.0], [IRON, 1.0]]}},  # the apron
}
## The quarry pit's levels below the rim, from the top down: a count and [scene, weight] pairs.
## Below the last of them is the floor, where the crystal grows.
const QUARRY_LEVELS := [
	{"count": 6, "entries": [[IRON, 2.0], [ROCK, 1.0]]},
	{"count": 6, "entries": [[COAL, 3.0], [GOLD, 1.5]]},
]
const CRYSTALS := 4
## Scenery fills this square (the valley inside the rim).
const SCENERY_AREA := Rect2(-185, -185, 370, 370)


static func populate(parent: Node3D, map: ProcgenMap) -> void:
	for i in map.sites.size():
		var site: Dictionary = map.sites[i]
		var spec: Dictionary = NODES.get(site["biome"], {}).get(site["tier"], {})
		if spec.is_empty():
			continue
		var cell := i
		var spawner := _spawner(map, "Nodes_%d_%s" % [i, site["biome"]], spec)
		var at: Vector2 = site["pos"]
		spawner.area = Rect2(at - Vector2.ONE * 110.0, Vector2.ONE * 220.0)
		spawner.hotspots = PackedVector3Array([Vector3(at.x, at.y, 30.0)])
		spawner.hotspot_share = 0.4
		var in_pit := func(p: Vector2) -> bool: return false
		if site["biome"] == &"quarry" and not map.quarry.is_empty():
			var qc: Vector2 = map.quarry["center"]
			var walls: Array = map.quarry["walls"]
			in_pit = func(p: Vector2) -> bool: return p.distance_to(qc) < float(walls[0]) + 1.5
		spawner.accept = func(p: Vector2) -> bool:
			return map.cells[ProcgenMap.pixel_index(p)] == cell and not in_pit.call(p)
		parent.add_child(spawner)
	_quarry_levels(parent, map)
	var boxes := _cell_boxes(map)
	for i in map.sites.size():
		var box: Rect2 = boxes[i].intersection(SCENERY_AREA)
		if box.has_area():
			parent.add_child(_scenery(map, i, box))


static func _spawner(map: ProcgenMap, node_name: String, spec: Dictionary) -> NodeSpawner:
	var spawner := NodeSpawner.new()
	spawner.name = node_name
	spawner.save_prefix = node_name.to_lower()
	spawner.seed = map.sub_seed(StringName(node_name))
	spawner.count = spec["count"]
	spawner.spacing = spec.get("spacing", 5.0)
	spawner.min_normal_y = spec.get("min_normal_y", 0.85)
	var entries: Array[SpawnEntry] = []
	for pair in spec["entries"]:
		var e := SpawnEntry.new()
		e.scene = pair[0]
		e.weight = pair[1]
		entries.append(e)
	spawner.entries = entries
	return spawner


## A spawner per pit level, each a ring between its wall and the next one in (clear of both),
## on quarry stone only, so nothing lands on the haul road; crystal on the floor.
static func _quarry_levels(parent: Node3D, map: ProcgenMap) -> void:
	if map.quarry.is_empty():
		return
	var qc: Vector2 = map.quarry["center"]
	var walls: Array = map.quarry["walls"]
	for k in walls.size():
		var outer := float(walls[k]) - 1.5
		var inner := float(walls[k + 1]) + 1.5 if k + 1 < walls.size() else 0.0
		var spec: Dictionary = {"count": CRYSTALS, "entries": [[CRYSTAL, 1.0]]}  # the floor
		if k < QUARRY_LEVELS.size():
			spec = QUARRY_LEVELS[k].duplicate()
		spec["spacing"] = 4.5
		var spawner := _spawner(map, "QuarryLevel%d" % (k + 1), spec)
		spawner.ring = Vector4(qc.x, qc.y, inner, outer)
		spawner.area = Rect2(qc - Vector2.ONE * outer, Vector2.ONE * outer * 2.0)
		var ids: Array[int] = [WorldMap.TEX_QUARRY]
		spawner.allowed_ids = ids
		spawner.hotspot_share = 0.0
		spawner.path_clearance = 1.0
		parent.add_child(spawner)


## Each cell's bounding box (world XZ), from the cells map.
static func _cell_boxes(map: ProcgenMap) -> Array[Rect2]:
	var lo: Array[Vector2i] = []
	var hi: Array[Vector2i] = []
	for i in map.sites.size():
		lo.append(Vector2i(ProcgenMap.SIZE, ProcgenMap.SIZE))
		hi.append(Vector2i(-1, -1))
	for y in ProcgenMap.SIZE:
		for x in ProcgenMap.SIZE:
			var c := map.cells[y * ProcgenMap.SIZE + x]
			if c != ProcgenMap.RIM_CELL:
				lo[c] = lo[c].min(Vector2i(x, y))
				hi[c] = hi[c].max(Vector2i(x, y))
	var out: Array[Rect2] = []
	for i in map.sites.size():
		var origin := Vector2(ProcgenMap.ORIGIN.x, ProcgenMap.ORIGIN.z)
		out.append(Rect2(origin + Vector2(lo[i]), Vector2(hi[i] - lo[i] + Vector2i.ONE)) if hi[i].x >= 0 else Rect2())
	return out


## The scenery for site `i`'s cell: the layers that grow on its biome's ground, over `box`.
static func _scenery(map: ProcgenMap, i: int, box: Rect2) -> SceneryScatter:
	var biome: StringName = map.sites[i]["biome"]
	var scatter := SceneryScatter.new()
	scatter.name = "Scenery_%d_%s" % [i, biome]
	scatter.area = box
	scatter.seed = map.sub_seed(StringName(scatter.name))
	var ground: Array[int] = [WorldMap.TEX_DEFAULT]
	match biome:
		&"pinewood":
			ground = [WorldMap.TEX_FOREST]
		&"goldmeadow":
			ground = [WorldMap.TEX_FIELD]
		&"quarry":
			ground = [WorldMap.TEX_DEFAULT, WorldMap.TEX_QUARRY]
	var d := WorldMap.TEX_DEFAULT
	var forest := WorldMap.TEX_FOREST
	var field := WorldMap.TEX_FIELD
	var layers: Array[ScatterLayer] = [
		# open ground, as round the hand-built clearing
		_layer("scenery/grass_tuft", 4.0, [d], {"scale_range": Vector2(0.8, 1.4), "min_normal_y": 0.8, "sway": 0.6,
				"cast_shadow": false, "visible_distance": 70.0, "cluster": Vector2i(3, 7), "cluster_radius": 0.9}),
		_layer("scenery/flowers_warm", 0.5, [d, field], {"scale_range": Vector2(1.3, 1.8), "sway": 0.8,
				"cast_shadow": false, "visible_distance": 60.0, "cluster": Vector2i(3, 6), "cluster_radius": 0.7}),
		_layer("scenery/flowers_cool", 0.4, [d, field], {"scale_range": Vector2(1.3, 1.8), "sway": 0.8,
				"cast_shadow": false, "visible_distance": 60.0, "cluster": Vector2i(3, 6), "cluster_radius": 0.7}),
		_layer("scenery/bush_round", 0.3, [d], {"scale_range": Vector2(0.8, 1.4), "min_normal_y": 0.8, "sway": 0.04,
				"visible_distance": 160.0, "clearance": 1.0, "cluster": Vector2i(1, 3), "cluster_radius": 1.2}),
		_layer("scenery/bush_low", 0.3, [d], {"scale_range": Vector2(0.8, 1.3), "min_normal_y": 0.8, "sway": 0.04,
				"visible_distance": 160.0, "clearance": 1.0}),
		_layer("scenery/boulder_big", 0.1, [d], {"scale_range": Vector2(0.7, 1.6), "min_normal_y": 0.5,
				"align_to_slope": true, "collide": true, "clearance": 1.5}),
		_layer("scenery/boulder_flat", 0.1, [d], {"scale_range": Vector2(0.7, 1.5), "min_normal_y": 0.5,
				"align_to_slope": true, "collide": true, "clearance": 1.5}),
		# forest floor, as in the Pinewood
		_layer("scenery/canopy_pine", 2.0, [forest], {"scale_range": Vector2(0.85, 1.35), "min_normal_y": 0.75,
				"sway": 0.05, "collide": true, "collision_size": Vector3(0.5, 4, 0.5), "clearance": 1.0}),
		_layer("scenery/canopy_pine_young", 0.9, [forest], {"scale_range": Vector2(0.8, 1.25), "min_normal_y": 0.75,
				"sway": 0.08, "collide": true, "collision_size": Vector3(0.35, 2.5, 0.35), "clearance": 0.8}),
		_layer("scenery/canopy_birch", 0.4, [forest], {"scale_range": Vector2(0.85, 1.2), "min_normal_y": 0.75,
				"sway": 0.08, "collide": true, "collision_size": Vector3(0.3, 4, 0.3), "clearance": 1.0}),
		_layer("scenery/fern", 2.5, [forest], {"scale_range": Vector2(0.7, 1.4), "cluster": Vector2i(2, 5),
				"cluster_radius": 1.6, "min_normal_y": 0.75, "sway": 0.4, "cast_shadow": false, "visible_distance": 60.0}),
		_layer("scenery/mushrooms", 0.5, [forest], {"scale_range": Vector2(0.8, 1.5), "cluster": Vector2i(1, 3),
				"cluster_radius": 2.0, "cast_shadow": false, "visible_distance": 35.0}),
		_layer("scenery/grass_tuft", 1.5, [forest], {"scale_range": Vector2(0.8, 1.3), "cluster": Vector2i(2, 5),
				"min_normal_y": 0.8, "sway": 0.6, "cast_shadow": false, "visible_distance": 60.0}),
		# meadow, as in Goldmeadow
		_layer("scenery/grass_tuft", 4.0, [field], {"scale_range": Vector2(0.8, 1.4), "cluster": Vector2i(3, 7),
				"cluster_radius": 0.9, "min_normal_y": 0.8, "sway": 0.6, "cast_shadow": false, "visible_distance": 70.0}),
		_layer("scenery/wheat_clump", 0.6, [field], {"scale_range": Vector2(0.9, 1.3), "cluster": Vector2i(4, 9),
				"cluster_radius": 1.5, "sway": 0.5, "cast_shadow": false, "visible_distance": 90.0}),
		# quarry stone, as in Greystone Quarry
		_layer("scenery/quarry_rubble", 1.5, [WorldMap.TEX_QUARRY], {"scale_range": Vector2(0.7, 1.6),
				"min_normal_y": 0.8, "align_to_slope": true, "cast_shadow": false, "visible_distance": 60.0}),
	]
	scatter.layers = layers.filter(func(l: ScatterLayer) -> bool:
		return l.allowed_ids.any(func(id: int) -> bool: return id in ground))
	return scatter


static func _layer(model: String, density: float, ids: Array, props: Dictionary) -> ScatterLayer:
	var layer := ScatterLayer.new()
	layer.model = load("res://models/%s.glb" % model)
	layer.density = density
	var allowed: Array[int] = []
	allowed.assign(ids)
	layer.allowed_ids = allowed
	for key in props:
		layer.set(key, props[key])
	return layer
