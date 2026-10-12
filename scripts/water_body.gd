class_name WaterBody
extends Area3D
## A body of water: its surface height plus a volume (this Area3D's box CollisionShape3D) that
## covers it. Other systems ask it questions rather than tracking overlaps:
##   WaterBody.depth_at(pos)   — how deep the water is at a point (0 when not in any water)
##   WaterBody.surface_at(pos) — the WaterBody at a point, or null
## Used for wading speed, water footsteps / ripples, and (later) fish bounds and the spear.

## World height of the water surface. Keep the Surface mesh and terrain (WATER_LEVEL in
## tools/generate_test_terrain.gd) in sync with this.
@export var surface_height := -0.15

@onready var _box: CollisionShape3D = $Volume


func _ready() -> void:
	add_to_group("water")
	monitoring = false  # nothing tracks overlaps; queries go through contains()
	monitorable = false


## True if `pos` (XZ) is over this water's volume.
func contains(pos: Vector3) -> bool:
	var local := _box.global_transform.affine_inverse() * pos
	var half := (_box.shape as BoxShape3D).size / 2.0
	return absf(local.x) <= half.x and absf(local.z) <= half.z


## Water depth at `pos`: surface height minus the terrain height there (0 if dry or outside).
func depth_here(pos: Vector3) -> float:
	if not contains(pos):
		return 0.0
	var terrain := get_tree().get_first_node_in_group("terrain") as Terrain3D
	var ground := pos.y
	if terrain and terrain.data:
		var h: float = terrain.data.get_height(pos)
		if not is_nan(h):
			ground = h
	return maxf(surface_height - ground, 0.0)


static func surface_at(tree: SceneTree, pos: Vector3) -> WaterBody:
	for w in tree.get_nodes_in_group("water"):
		var body := w as WaterBody
		if body and body.depth_here(pos) > 0.0:
			return body
	return null


static func depth_at(tree: SceneTree, pos: Vector3) -> float:
	var body := surface_at(tree, pos)
	return body.depth_here(pos) if body else 0.0
