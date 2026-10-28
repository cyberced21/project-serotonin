class_name NatureSpots
extends RefCounted
## Spots in the current world where night life gathers, the way it would for real: round the
## shores of ponds and lakes, at the edges of trees, in meadow grass by the crops. Fireflies
## cluster at them and crickets sing from them, tied to the world rather than to you. Seeded, so a
## world has the same spots every time it loads (and the same as long as its trees stand).

## Ground that's no place for them: paths, roads, quarry stone.
const BARE: Array[int] = [WorldMap.TEX_PATH, WorldMap.TEX_ROAD, WorldMap.TEX_QUARRY]
## Nor up the snowy peak or down the quarry.
const SKIP_BIOMES: Array[StringName] = [&"frostpeak", &"quarry"]
## Steeper ground than this (height change over a metre) is skipped.
const MAX_SLOPE := 0.45


## Up to `limit` spots at least `spacing` m apart. `water_share` (0..1) of the candidates come from
## shores, the rest from beside trees and crops; shores go first, so they're never crowded out.
static func find(tree: SceneTree, spacing: float, limit: int, water_share: float, seed_salt: int) -> PackedVector3Array:
	var terrain := tree.get_first_node_in_group("terrain") as Terrain3D
	if terrain == null or terrain.data == null:
		return PackedVector3Array()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([tree.current_scene.scene_file_path, Worlds.current, seed_salt])
	var shore: Array[Vector3] = []
	for w in tree.get_nodes_in_group("water"):
		var water := w as WaterBody
		if water == null or water.flow != Vector3.ZERO:
			continue  # still water only
		var box := water.get_node("Volume") as CollisionShape3D
		var half := (box.shape as BoxShape3D).size * 0.5
		var around := maxi(3, int((half.x + half.z) * 0.5))
		for k in around:
			var a := rng.randf() * TAU
			var out := rng.randf_range(1.5, 5.0)
			var edge := Vector3(cos(a) * (half.x + out), 0.0, sin(a) * (half.z + out))
			shore.append(box.global_transform * edge)
	var green: Array[Vector3] = []
	for n in tree.get_nodes_in_group("gatherable"):
		var tool: Variant = n.get("tool_type")
		if tool != &"axe" and tool != &"sickle":
			continue
		var a := rng.randf() * TAU
		var r := rng.randf_range(3.0, 7.0)
		green.append((n as Node3D).global_position + Vector3(cos(a) * r, 0.0, sin(a) * r))
	_shuffle(shore, rng)
	_shuffle(green, rng)
	var want_shore := int(limit * water_share)
	var out := PackedVector3Array()
	for pool in [shore, green]:
		for p in pool:
			if out.size() >= limit or (pool == shore and out.size() >= want_shore):
				break
			var spot := _ground(terrain, tree, p)
			if spot == Vector3.INF:
				continue
			var crowded := false
			for q in out:
				if Vector2(q.x - spot.x, q.z - spot.z).length() < spacing:
					crowded = true
					break
			if not crowded:
				out.append(spot)
	return out


## `p` on the ground, or Vector3.INF where it's no place for them (water, bare ground, steep).
static func _ground(terrain: Terrain3D, tree: SceneTree, p: Vector3) -> Vector3:
	var h := terrain.data.get_height(p)
	if is_nan(h):
		return Vector3.INF
	for d in [Vector3(1, 0, 0), Vector3(0, 0, 1)]:
		var hd := terrain.data.get_height(p + d)
		if is_nan(hd) or absf(hd - h) > MAX_SLOPE:
			return Vector3.INF
	var at := Vector3(p.x, h, p.z)
	if WaterBody.depth_at(tree, at + Vector3.UP * 0.05) > 0.0:
		return Vector3.INF
	if terrain.data.get_control_base_id(at) in BARE or Biome.biome_at(at) in SKIP_BIOMES:
		return Vector3.INF
	return at


static func _shuffle(a: Array[Vector3], rng: RandomNumberGenerator) -> void:
	for i in range(a.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t := a[i]
		a[i] = a[j]
		a[j] = t
