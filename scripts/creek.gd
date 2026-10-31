class_name Creek
extends Node3D
## Hearthvale's creek (plans/world.md), built along WorldMap.creek(): one water surface following
## its bends (a strip; the water shader works from world position), and a WaterBody every SEGMENT
## metres along it, its box turned along the creek, so wading, splashes and footsteps work in it
## like in a pond. Each stretch carries the current (WaterBody.flow, downstream) and some hold
## fish: grayling every few stretches, holding station in the current, and a salmon in each deep
## pool (WorldMap.CREEK_POOLS). Where it runs through the clearing's pond and into the lake their
## own water takes over. The terrain generator carves its bed along the same line.
## The map editor's rivers (River, plans/terrain-editing.md) are built the same way.

const WATER_SHADER := preload("res://shaders/water.gdshader")
const GRAYLING := preload("res://data/fish/grayling.tres")
const SALMON := preload("res://data/fish/salmon.tres")
## Keep in sync with tools/generate_test_terrain.gd's WATER_LEVEL.
const WATER_LEVEL := -0.15
const SEGMENT := 10
## Grayling in every GRAYLING_EVERY-th stretch.
const GRAYLING_EVERY := 3
## How fast the current runs (m/s): it carries a float down to the grayling.
const FLOW := 0.45
## The surface reaches this far past the channel's edge, under the soft banks.
const SURFACE_MARGIN := 1.5

## Half the channel's width (m) and whether its stretches hold fish.
var half_width := WorldMap.CREEK_HALF_WIDTH
var fish := true


func _ready() -> void:
	add_to_group("creek")
	_build(WorldMap.creek())


func _build(pts: PackedVector2Array) -> void:
	_build_surface(pts)
	_build_stretches(pts)
	_build_road_bridges.call_deferred(pts)


## The deep pools along it, where a salmon holds (none on a river).
func _pools() -> Array[Vector2]:
	return WorldMap.CREEK_POOLS


## Whether the water at `p` is some other water's (where this one's surface is left out).
func _covered(p: Vector2) -> bool:
	return in_other_water(p)


## A bridge wherever a road crosses (the village path's footbridge is a project: VillageDecor):
## the road's width, over the channel and its banks.
func _build_road_bridges(pts: PackedVector2Array) -> void:
	var reach := half_width + 3.0  # past the channel's middle, each side, along the road
	var terrain := get_tree().get_first_node_in_group("terrain") as Terrain3D
	for r in WorldMap.roads():
		if r["kind"] != &"road":
			continue
		var road: PackedVector2Array = r["pts"]
		var best := [-1, -1]
		var best_d := 4.0  # (within 2 m)
		for i in road.size():
			for k in range(0, pts.size(), 2):
				var d := road[i].distance_squared_to(pts[k])
				if d < best_d:
					best_d = d
					best = [i, k]
		if best[0] < 0:
			continue
		var along := (road[mini(best[0] + 3, road.size() - 1)] - road[maxi(best[0] - 3, 0)]).normalized()
		var mid: Vector2 = pts[best[1]]
		var bridge := Footbridge.new()
		bridge.width = Footbridge.ROAD_WIDTH
		for end: float in [-1.0, 1.0]:
			var at := mid + along * reach * end
			var h: float = terrain.data.get_height(Vector3(at.x, 0, at.y)) if terrain and terrain.data else 0.0
			var p := Vector3(at.x, 0.0 if is_nan(h) else h, at.y)
			if end < 0.0:
				bridge.from = p
			else:
				bridge.to = p
		bridge.name = "Bridge_%s" % r["id"]
		add_child(bridge)


## Whether `p` is in other water the creek runs into: the layout's ponds (the clearing's pond, the
## lake: LayoutWater).
static func in_other_water(p: Vector2) -> bool:
	return LayoutWater.in_pond(p, 1.0)


func _build_surface(pts: PackedVector2Array) -> void:
	var material := ShaderMaterial.new()
	material.shader = WATER_SHADER
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in pts.size() - 1:
		var a := pts[k]
		var b := pts[k + 1]
		if _covered(a) and _covered(b):
			continue
		var na := across(pts, k) * (half_width + SURFACE_MARGIN)
		var nb := across(pts, k + 1) * (half_width + SURFACE_MARGIN)
		var al := Vector3(a.x - na.x, WATER_LEVEL, a.y - na.y)
		var ar := Vector3(a.x + na.x, WATER_LEVEL, a.y + na.y)
		var bl := Vector3(b.x - nb.x, WATER_LEVEL, b.y - nb.y)
		var br := Vector3(b.x + nb.x, WATER_LEVEL, b.y + nb.y)
		for v in [al, bl, ar, ar, bl, br]:
			st.set_normal(Vector3.UP)
			st.add_vertex(v)
	var surface := MeshInstance3D.new()
	surface.name = "Surface"
	surface.mesh = st.commit()
	surface.material_override = material
	surface.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(surface)


func _build_stretches(pts: PackedVector2Array) -> void:
	var n := 0
	for k in range(0, pts.size() - 1, SEGMENT):
		var a := pts[k]
		var b := pts[mini(k + SEGMENT, pts.size() - 1)]
		if _covered(a) and _covered(b):
			continue
		n += 1
		var body := WaterBody.new()
		body.name = "Stretch%d" % n
		body.position = Vector3((a.x + b.x) * 0.5, 0.0, (a.y + b.y) * 0.5)
		body.rotation.y = atan2(b.x - a.x, b.y - a.y)  # its box's length (Z) along the creek
		body.collision_layer = 0
		body.collision_mask = 0
		body.surface_height = WATER_LEVEL
		var down := (b - a).normalized()
		body.flow = Vector3(down.x, 0.0, down.y) * FLOW
		var volume := CollisionShape3D.new()
		volume.name = "Volume"
		volume.position.y = -1.0
		var box := BoxShape3D.new()
		box.size = Vector3(half_width * 2.0 + 4.0, 3.0, a.distance_to(b) + 1.0)
		volume.shape = box
		body.add_child(volume)
		var schools: Array[FishSpecies] = []
		for pool in _pools():
			if Geometry2D.get_closest_point_to_segment(pool, a, b).distance_to(pool) < WorldMap.CREEK_POOL_RADIUS:
				schools.append(SALMON)
		if fish and n % GRAYLING_EVERY == 2:
			schools.append(GRAYLING)
		if not schools.is_empty():
			var fish := FishPond.new()
			fish.name = "Fish"
			fish.schools = schools
			body.add_child(fish)
		add_child(body)


## The unit vector across the creek at point k (to its right, looking downstream).
static func across(pts: PackedVector2Array, k: int) -> Vector2:
	var along := (pts[mini(k + 1, pts.size() - 1)] - pts[maxi(k - 1, 0)]).normalized()
	return Vector2(-along.y, along.x)
