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
## The current (m/s, world space, downstream): rivers carry a float down it and station-holding
## fish face up into it. Zero for ponds and lakes.
@export var flow := Vector3.ZERO

## The morning mist over the water: how high it reaches above the surface.
const MIST_HEIGHT := 1.6

static var _mist_material: FogMaterial

@onready var _box: CollisionShape3D = $Volume


func _ready() -> void:
	add_to_group("water")
	monitoring = false  # nothing tracks overlaps; queries go through contains()
	monitorable = false
	_add_mist()
	_add_sound()


## The wispy mist every body of water shares; DayNightSky sets its density (thick at dawn, gone
## by mid-morning). Volumetric: only shows with volumetric fog on.
static func mist_material() -> FogMaterial:
	if _mist_material == null:
		var noise := FastNoiseLite.new()
		noise.frequency = 0.08
		noise.fractal_octaves = 3
		var wisps := NoiseTexture3D.new()
		wisps.width = 48
		wisps.height = 16
		wisps.depth = 48
		wisps.seamless = true
		wisps.noise = noise
		_mist_material = FogMaterial.new()
		_mist_material.density = 0.0
		_mist_material.albedo = Color(0.96, 0.97, 1.0)
		_mist_material.height_falloff = 1.2
		_mist_material.edge_fade = 0.7
		_mist_material.density_texture = wisps
	return _mist_material


## A flat ellipsoid of mist lying on the water, as wide as the water's box.
func _add_mist() -> void:
	var size := (_box.shape as BoxShape3D).size
	var mist := FogVolume.new()
	mist.name = "Mist"
	mist.shape = RenderingServer.FOG_VOLUME_SHAPE_ELLIPSOID
	mist.size = Vector3(size.x, MIST_HEIGHT * 2.0, size.z)
	mist.material = mist_material()
	add_child(mist)
	mist.position = Vector3(_box.position.x, surface_height - global_position.y, _box.position.z)
	mist.rotation = _box.rotation



## The water's own sound: lapping at a pond or lake, babbling on a river stretch (Ambience's beds,
## loudest near the middle, carrying a little past the shore).
func _add_sound() -> void:
	var half := (_box.shape as BoxShape3D).size / 2.0
	var r := maxf(half.x, half.z)
	var bed := Ambience.water_bed(&"stream" if flow != Vector3.ZERO else &"lapping", maxf(r * 0.6, 3.0), r + 25.0)
	bed.name = "Sound"
	add_child(bed)
	bed.position = Vector3(_box.position.x, surface_height - global_position.y, _box.position.z)


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
