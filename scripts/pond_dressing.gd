class_name PondDressing
extends Node3D
## Scatters reeds, lily pads and shore stones around the WaterBody it sits under, by water depth:
##   reeds:      in the shallow margin (depth reed_depth.x .. .y), planted on the bed
##   lily pads:  floating over mid-depth water (pad_depth), some with a flower
##   stones:     on the dry shore just outside the water
## Placement is random but seeded, so the pond looks the same every run; change `seed` for a
## different arrangement. Nothing here has collision. FishPond asks for reed_spots (pike cover).

@export var seed := 7
@export var reed_clumps := 9
@export var lily_pads := 14
@export_range(0.0, 1.0) var flower_chance := 0.25
@export var stones := 12
@export var reed_depth := Vector2(0.08, 0.4)
@export var pad_depth := Vector2(0.45, 0.9)

@export_group("Models")
@export var reed_model: PackedScene = preload("res://models/scenery/reeds.glb")
@export var pad_model: PackedScene = preload("res://models/scenery/lily_pad.glb")
@export var flower_model: PackedScene = preload("res://models/scenery/lily_flower.glb")
@export var stone_model: PackedScene = preload("res://models/scenery/shore_stone.glb")

const PALETTE_MATERIAL := preload("res://materials/node_palette.tres")
const SWAY := preload("res://shaders/sway.gdshader")

## World positions of the reed clumps (on the water surface), for lurking fish.
var reed_spots: Array[Vector3] = []
var water: WaterBody
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	water = get_parent() as WaterBody
	assert(water, "PondDressing must be a child of a WaterBody")
	_dress.call_deferred()  # after the terrain has loaded


func _dress() -> void:
	_rng.seed = seed
	var sway := ShaderMaterial.new()
	sway.shader = SWAY
	sway.set_shader_parameter("palette", PALETTE_MATERIAL.get_shader_parameter("palette"))
	var terrain := get_tree().get_first_node_in_group("terrain") as Terrain3D

	for i in reed_clumps:
		var p := _find(func(d: float) -> bool: return d >= reed_depth.x and d <= reed_depth.y)
		if p == Vector3.INF:
			continue
		var bed := water.surface_height - water.depth_here(p)
		var clump := _place(reed_model, Vector3(p.x, bed, p.z), _rng.randf_range(0.8, 1.25), sway)
		var phase := _rng.randf() * TAU
		for m in clump.find_children("*", "MeshInstance3D", true, false):
			(m as MeshInstance3D).set_instance_shader_parameter("base_y", bed)
			(m as MeshInstance3D).set_instance_shader_parameter("sway_phase", phase)
		reed_spots.append(Vector3(p.x, water.surface_height, p.z))

	for i in lily_pads:
		var p := _find(func(d: float) -> bool: return d >= pad_depth.x and d <= pad_depth.y)
		if p == Vector3.INF:
			continue
		var model := flower_model if _rng.randf() < flower_chance else pad_model
		_place(model, Vector3(p.x, water.surface_height + 0.015, p.z), _rng.randf_range(0.7, 1.3), PALETTE_MATERIAL)

	for i in stones:
		# dry ground in a ring just beyond the shoreline
		var p := _find(func(d: float) -> bool: return d == 0.0, true)
		if p == Vector3.INF or terrain == null:
			continue
		var ground: float = terrain.data.get_height(p)
		_place(stone_model, Vector3(p.x, ground - 0.04, p.z), _rng.randf_range(0.6, 1.5), PALETTE_MATERIAL)


## A random point over this water's volume whose depth passes `accept`. With `near_shore`,
## only points that have water within 1.5 m (so stones hug the shoreline).
func _find(accept: Callable, near_shore := false) -> Vector3:
	var box := water.get_node("Volume") as CollisionShape3D
	var half := (box.shape as BoxShape3D).size / 2.0
	for attempt in 80:
		var p := box.global_transform * Vector3(_rng.randf_range(-half.x, half.x), 0.0, _rng.randf_range(-half.z, half.z))
		if not accept.call(water.depth_here(p)):
			continue
		if near_shore:
			var wet := false
			for k in 8:
				var a := k * TAU / 8.0
				if water.depth_here(p + Vector3(cos(a), 0, sin(a)) * 1.5) > 0.0:
					wet = true
					break
			if not wet:
				continue
		return p
	return Vector3.INF


func _place(scene: PackedScene, at: Vector3, size: float, material: Material) -> Node3D:
	var inst := scene.instantiate() as Node3D
	add_child(inst)
	inst.global_position = at
	inst.rotation.y = _rng.randf() * TAU
	inst.scale = Vector3.ONE * size
	for m in inst.find_children("*", "MeshInstance3D", true, false):
		(m as MeshInstance3D).material_override = material
	return inst
