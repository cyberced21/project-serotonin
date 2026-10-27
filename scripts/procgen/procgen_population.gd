class_name ProcgenPopulation
extends RefCounted
## Fills a generated world (ProcgenMap) with what you gather and what you walk through:
## - a NodeSpawner per biome cell, kept to its own cell, with that biome's trees, rocks or grain;
##   the inner ring gets the gentler mix, the outer ring the harder one (birch near the hub, pine
##   far out; copper and iron by the hub, coal and gold on Frostpeak's foothills);
## - in the quarry pit, ore walls along every wall (OreWallPlacer: richer the deeper you go), and
##   crystal on the floor;
## - a SceneryScatter per biome cell, over just that cell's bounding box and with just its biome's
##   layers (so no layer samples ground it can't grow on): grass, flowers, bushes and boulders on
##   open ground, canopies and ferns on forest floor, meadow grass on the field, rubble in the
##   quarry. The rim is left bare.
## Models with baked variants (models/variants/) are mixed in: nodes wear one picked by their save
## id, scenery layers are split across the looks.
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
	&"clearing": {0: {"count": 12, "spacing": 6.0, "entries": [[TREE, 3.0], [ROCK, 2.0]]}},
	&"pinewood": {
		1: {"count": 22, "spacing": 4.5, "entries": [[BIRCH, 3.0], [TREE, 1.5], [PINE, 0.3]]},
		2: {"count": 26, "spacing": 4.5, "entries": [[PINE, 3.0], [BIRCH, 1.0]]},
	},
	&"goldmeadow": {1: {"count": 24, "spacing": 4.0, "entries": [[WHEAT, 3.0], [BARLEY, 1.5], [OAK, 1.2]]}},
	&"stillwater": {2: {"count": 12, "spacing": 7.0, "entries": [[OAK, 2.0], [TREE, 1.0], [IRON, 1.0]]}},
	&"frostpeak": {2: {"count": 14, "spacing": 5.5, "entries": [[COAL, 2.0], [GOLD, 1.5], [IRON, 1.0]],
			"min_normal_y": 0.8}},
	&"quarry": {2: {"count": 6, "spacing": 5.0, "entries": [[ROCK, 2.0], [IRON, 1.0]]}},  # the apron
	&"hearthvale": {1: {"count": 9, "spacing": 6.5, "entries": [[TREE, 2.0], [OAK, 1.5], [ROCK, 1.0]]}},  # round the flat
}
## How a biome's kind changes its nodes: weights multiplied per scene, and "count" the number.
const KIND_NODES := {
	&"birch_grove": {BIRCH: 2.5, PINE: 0.4, TREE: 1.3},
	&"old_growth": {PINE: 2.2, BIRCH: 0.5, "count": 1.2},
	&"orchard_downs": {OAK: 3.0, WHEAT: 0.5, BARLEY: 0.5},
	&"rolling_downs": {BARLEY: 1.6, "count": 0.85},
	&"marsh": {OAK: 0.5, TREE: 2.0},
	&"twin_peaks": {GOLD: 1.5, "count": 1.2},
	&"ridge": {COAL: 1.5, IRON: 1.4},
	&"broken_pit": {"count": 1.5},
}
## How a biome's kind changes its scenery: each layer's density multiplied, by model name.
const KIND_SCENERY := {
	&"birch_grove": {"canopy_birch": 5.0, "canopy_pine": 0.3, "canopy_pine_young": 0.6, "fern": 0.7},
	&"old_growth": {"canopy_pine": 1.4, "canopy_pine_young": 0.4, "fern": 1.5, "mushrooms": 2.0},
	&"orchard_downs": {"flowers_warm": 3.0, "flowers_cool": 3.0, "wheat_clump": 0.3},
	&"rolling_downs": {"wheat_clump": 1.8},
	&"marsh": {"grass_tuft": 1.6, "bush_low": 2.5, "flowers_cool": 2.0},
	&"hollow": {"boulder_big": 2.0, "bush_round": 1.5},
	&"broken_pit": {"boulder_big": 6.0, "boulder_flat": 6.0, "quarry_rubble": 2.0},
}
## And their size, by model name (Old Growth's trees stand taller).
const KIND_SCALE := {
	&"old_growth": {"canopy_pine": 1.3, "canopy_birch": 1.2},
}
## Crystals on the quarry's floor (its levels have ore walls instead: _quarry_levels).
const CRYSTALS := 4
## How many baked variants each model may have (tools/blender/make_models.py's VARIANTS).
const VARIANTS := 8
## Scenery fills this square (the valley inside the rim).
const SCENERY_AREA := Rect2(-185, -185, 370, 370)


## Every spawner, then every scatter, one at a time, each spread over frames by `budget_ms` (0: all
## in this frame, as before). `on_progress` gets 0..1 as they finish. Await it when budgeted.
static func populate(parent: Node3D, map: ProcgenMap, budget_ms := 0.0, on_progress := Callable()) -> void:
	var by_site := {}  # site -> its spawner
	for i in map.sites.size():
		var site: Dictionary = map.sites[i]
		var tiers: Dictionary = NODES.get(site["biome"], {})
		var spec: Dictionary = tiers.get(site["tier"], tiers.get(2, tiers.get(1, {})))  # a large world's repeats
		if spec.is_empty():
			continue
		spec = _with_kind(spec, site.get("kind", &""))
		var cell := i
		var spawner := _spawner(map, "Nodes_%d_%s" % [i, site["biome"]], spec)
		spawner.theme = theme_for(site["biome"], site.get("kind", &""))
		var at: Vector2 = site["pos"]
		spawner.area = Rect2(at - Vector2.ONE * 110.0, Vector2.ONE * 220.0)
		spawner.hotspots = PackedVector3Array([Vector3(at.x, at.y, 30.0)])
		spawner.hotspot_share = 0.4
		var in_pit := func(p: Vector2) -> bool: return false
		if site["biome"] == &"quarry" and not map.quarry.is_empty():
			var qc: Vector2 = map.quarry["center"]
			var walls: Array = map.quarry["walls"]
			in_pit = func(p: Vector2) -> bool: return p.distance_to(qc) < float(walls[0]) + 1.5
		if site["biome"] == &"hearthvale" and not map.village.is_empty():  # round the village, not in it
			var vc: Vector2 = map.village["center"]
			in_pit = func(p: Vector2) -> bool: return p.distance_to(vc) < ProcgenMap.VILLAGE_RADIUS
		spawner.accept = func(p: Vector2) -> bool:
			return map.cells[map.pixel_index(p)] == cell and not in_pit.call(p)
		by_site[i] = spawner
	_place_rares(map, by_site)
	var spawners: Array[NodeSpawner] = []
	for i in by_site:
		spawners.append(by_site[i])
	spawners.append_array(_quarry_levels(parent, map))
	var scatters: Array[SceneryScatter] = []
	var boxes := _cell_boxes(map)
	for i in map.sites.size():
		var box: Rect2 = boxes[i].intersection(SCENERY_AREA.grow((map.metres - ProcgenMap.SIZE) * 0.5))
		if box.has_area():
			scatters.append(_scenery(map, i, box))
	# the nodes first and one spawner at a time (each keeps clear of the ones before it), then
	# the scenery round them
	var all: Array[Node3D] = []
	all.append_array(spawners)
	all.append_array(scatters)
	var slow := PackedStringArray()
	for k in all.size():
		var t := Time.get_ticks_msec()
		all[k].set("frame_budget_ms", budget_ms)
		parent.add_child(all[k])
		if budget_ms > 0.0:
			if not all[k].get("done"):
				await all[k].finished
			if Time.get_ticks_msec() - t > 1000:
				slow.append("%s %d" % [all[k].name, Time.get_ticks_msec() - t])
			if on_progress.is_valid():
				on_progress.call(float(k + 1) / all.size())
	if not slow.is_empty():
		print("ProcgenPopulation: slow: ", ", ".join(slow))


## Hands each of the seed's rare looks (ProcgenMap.rares) to its site's spawner, or, for a site
## with no nodes, the nearest site's that has some.
static func _place_rares(map: ProcgenMap, spawners: Dictionary) -> void:
	for r: Dictionary in map.rares:
		var at: Vector2 = map.sites[r["site"]]["pos"]
		var best: NodeSpawner = null
		var best_d := INF
		for i in spawners:
			var d: float = (map.sites[i]["pos"] as Vector2).distance_to(at)
			if d < best_d and (spawners[i] as NodeSpawner).rare == null:
				best_d = d
				best = spawners[i]
		if best:
			best.rare = load("res://data/themes/rare/%s.tres" % r["theme"])


## How a biome kind dresses its nodes (data/themes/<kind>.tres), else its biome
## (data/themes/<biome>.tres), else nothing.
static func theme_for(biome: StringName, kind: StringName) -> NodeTheme:
	for id in [kind, biome]:
		var path := "res://data/themes/%s.tres" % id
		if not String(id).is_empty() and ResourceLoader.exists(path):
			return load(path)
	return null


## `spec` with its kind's weights and count applied (see KIND_NODES).
static func _with_kind(spec: Dictionary, kind: StringName) -> Dictionary:
	var mods: Dictionary = KIND_NODES.get(kind, {})
	if mods.is_empty():
		return spec
	var out := spec.duplicate()
	out["count"] = roundi(spec["count"] * float(mods.get("count", 1.0)))
	var entries := []
	for pair in spec["entries"]:
		entries.append([pair[0], pair[1] * float(mods.get(pair[0], 1.0))])
	out["entries"] = entries
	return out


static func _spawner(map: ProcgenMap, node_name: String, spec: Dictionary) -> NodeSpawner:
	var spawner := NodeSpawner.new()
	spawner.name = node_name
	spawner.save_prefix = node_name.to_lower()
	spawner.seed = map.sub_seed(StringName(node_name))
	spawner.count = spec["count"]
	spawner.spacing = spec.get("spacing", 5.0)
	spawner.min_normal_y = spec.get("min_normal_y", 0.85)
	var entries: Array[SpawnEntry] = []
	var before := 0.0  # total weight as given
	var after := 0.0   # ... and with the seed's rich resource doubled and its lean one halved
	for pair in spec["entries"]:
		var e := SpawnEntry.new()
		e.scene = pair[0]
		var probe := (pair[0] as PackedScene).instantiate()  # only to read its item and model
		var wealth := 2.0 if probe.get("item") == map.rich else (0.5 if probe.get("item") == map.lean else 1.0)
		before += pair[1]
		e.weight = pair[1] * wealth
		after += e.weight
		e.variants = _variants_of(probe.get("model"))
		probe.free()
		entries.append(e)
	spawner.entries = entries
	# more (or fewer) nodes by as much as the rich (or lean) one's share changed, so every other
	# resource keeps its usual number and only that one doubles (or halves); then the world's
	# resources setting, for every node alike
	var scale: float = WorldSettings.RESOURCE_SCALE[map.settings["resources"]]
	spawner.count = maxi(1, roundi(spawner.count * after / before * scale))
	return spawner


## The pit's walls lined with ore wall (OreWallPlacer, as in Greystone Quarry, added to `parent`
## now), and a spawner of crystal on the floor (returned, not yet added), on quarry stone only,
## clear of the innermost wall's blocks of rock.
static func _quarry_levels(parent: Node3D, map: ProcgenMap) -> Array[NodeSpawner]:
	var out: Array[NodeSpawner] = []
	if map.quarry.is_empty():
		return out
	var qc: Vector2 = map.quarry["center"]
	var walls: Array = map.quarry["walls"]
	var placer := OreWallPlacer.new()
	placer.name = "QuarryWalls"
	placer.center = qc
	for w in walls:
		placer.walls.append(float(w))
	placer.level_drop = ProcgenMap.QUARRY_LEVEL_DROP
	placer.save_prefix = "quarry_wall"
	placer.seed = map.seed
	parent.add_child(placer)
	var last := float(walls[-1])
	var outer := last - (OreWall.DEPTH + OreWallPlacer.BACK_GAP if last >= placer.min_radius else 0.0) - 1.5
	var spec := _with_kind({"count": CRYSTALS, "entries": [[CRYSTAL, 1.0]]}, map.kinds.get(&"quarry", &""))
	spec["spacing"] = 4.5
	var spawner := _spawner(map, "QuarryFloor", spec)
	spawner.theme = theme_for(&"quarry", map.kinds.get(&"quarry", &""))
	spawner.ring = Vector4(qc.x, qc.y, 0.0, outer)
	spawner.area = Rect2(qc - Vector2.ONE * outer, Vector2.ONE * outer * 2.0)
	var ids: Array[int] = [WorldMap.TEX_QUARRY]
	spawner.allowed_ids = ids
	spawner.hotspot_share = 0.0
	spawner.path_clearance = 1.0
	out.append(spawner)
	return out


## Each cell's bounding box (world XZ), from the cells map.
static func _cell_boxes(map: ProcgenMap) -> Array[Rect2]:
	var lo: Array[Vector2i] = []
	var hi: Array[Vector2i] = []
	for i in map.sites.size():
		lo.append(Vector2i(map.size, map.size))
		hi.append(Vector2i(-1, -1))
	for y in map.size:
		for x in map.size:
			var c := map.cells[y * map.size + x]
			if c != ProcgenMap.RIM_CELL:
				lo[c] = lo[c].min(Vector2i(x, y))
				hi[c] = hi[c].max(Vector2i(x, y))
	var out: Array[Rect2] = []
	for i in map.sites.size():
		out.append(Rect2(map.origin + Vector2(lo[i]) * map.step, Vector2(hi[i] - lo[i] + Vector2i.ONE) * map.step)
				if hi[i].x >= 0 else Rect2())
	return out


## The scenery for site `i`'s cell: the layers that grow on its biome's ground, over `box`.
static func _scenery(map: ProcgenMap, i: int, box: Rect2) -> SceneryScatter:
	var biome: StringName = map.sites[i]["biome"]
	var scatter := SceneryScatter.new()
	scatter.name = "Scenery_%d_%s" % [i, biome]
	scatter.area = box
	if map.settings["size"] == &"large":  # big cells' boxes overlap a lot: keep to its own cell
		scatter.accept = func(p: Vector2) -> bool: return map.cells[map.pixel_index(p)] == i
	scatter.seed = map.sub_seed(StringName(scatter.name))
	scatter.theme = theme_for(biome, map.sites[i].get("kind", &""))
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
		_layer("scenery/canopy_pine", 2.0, [forest], {"scale_range": Vector2(1.45, 2.2), "min_normal_y": 0.75,
				"sway": 0.05, "collide": true, "collision_size": Vector3(0.5, 4, 0.5), "clearance": 1.0}),
		_layer("scenery/canopy_pine_young", 0.9, [forest], {"scale_range": Vector2(1.2, 1.8), "min_normal_y": 0.75,
				"sway": 0.08, "collide": true, "collision_size": Vector3(0.35, 2.5, 0.35), "clearance": 0.8}),
		_layer("scenery/canopy_birch", 0.4, [forest], {"scale_range": Vector2(1.45, 2.0), "min_normal_y": 0.75,
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
	var kind: StringName = map.sites[i].get("kind", &"")
	var density: Dictionary = KIND_SCENERY.get(kind, {})
	var size: Dictionary = KIND_SCALE.get(kind, {})
	var picked: Array[ScatterLayer] = []
	for l in layers:
		if l.allowed_ids.any(func(id: int) -> bool: return id in ground):
			var look := l.model.resource_path.get_file().get_basename()
			l.density *= float(density.get(look, 1.0))
			l.scale_range *= float(size.get(look, 1.0))
			picked.append_array(_with_variants(l))
	scatter.layers = picked
	return scatter


## The baked variants of a model (models/variants/<name>_v<n>.glb), if any.
static func _variants_of(model: PackedScene) -> Array[PackedScene]:
	var out: Array[PackedScene] = []
	if model == null:
		return out
	var base := model.resource_path.get_file().get_basename()
	for v in range(1, VARIANTS + 1):
		var path := "res://models/variants/%s_v%d.glb" % [base, v]
		if ResourceLoader.exists(path):
			out.append(load(path))
	return out


## A layer per look (the model and each of its variants), sharing the density between them.
static func _with_variants(layer: ScatterLayer) -> Array[ScatterLayer]:
	var looks := _variants_of(layer.model)
	var out: Array[ScatterLayer] = [layer]
	if looks.is_empty():
		return out
	layer.density /= looks.size() + 1
	for look in looks:
		var copy := layer.duplicate() as ScatterLayer
		copy.model = look
		out.append(copy)
	return out


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
