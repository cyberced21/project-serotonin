class_name Fish
extends Node3D
## One fish: its model (with the swim shader) and a small hit capsule the spear can find.
## It doesn't move itself — its FishSchool steers every fish in the school each frame.

## Physics layer 6: fish hit volumes. Only the spear looks at this layer.
const FISH_LAYER := 1 << 5
const SHADER := preload("res://shaders/fish.gdshader")
const PALETTE := preload("res://art/palette.png")

enum State { CALM, ALERT, FLEE }

var species: FishSpecies
var school: FishSchool
var state := State.CALM
var velocity := Vector3.ZERO
## Fraction of the water depth this fish likes to swim at (0 = bed, 1 = surface).
var depth_pref := 0.5
var flee_time := 0.0
var length := 0.3
## 0..1, rolled at spawn (big ones are rare): how big it looks, its weight, XP, and how many it
## counts for (FishSize).
var size := 0.0
## A FishingLure that has this fish's attention (approaching, nibbling, on the line): it steers the
## fish then, not the school.
var lure: Node = null
## Station-holding species (grayling): the spot in the current this fish keeps to.
var station := Vector3.INF

var _surfaces: Array[GeometryInstance3D] = []
var _flash_tween: Tween


func setup(p_species: FishSpecies, p_school: FishSchool) -> void:
	species = p_species
	school = p_school
	depth_pref = randf_range(0.3, 0.65)
	size = FishSize.roll(randf())
	var model := species.model.instantiate() as Node3D
	add_child(model)
	model.scale = Vector3.ONE * FishSize.scale_for(size)
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	mat.set_shader_parameter("palette", PALETTE)
	var aabb := AABB()
	for m in model.find_children("*", "MeshInstance3D", true, false):
		var mesh := m as MeshInstance3D
		mesh.material_override = mat
		mesh.set_instance_shader_parameter("phase", randf() * TAU)
		_surfaces.append(mesh)
		aabb = mesh.get_aabb() if aabb.size == Vector3.ZERO else aabb.merge(mesh.get_aabb())
	length = aabb.size.z
	for s in _surfaces:
		s.set_instance_shader_parameter("body_length", length)

	# hit capsule along the body
	var hit := Area3D.new()
	hit.name = "Hit"
	hit.collision_layer = FISH_LAYER
	hit.collision_mask = 0
	hit.monitoring = false
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	var k := FishSize.scale_for(size)
	capsule.radius = maxf(aabb.size.x, aabb.size.y) * 0.5 * k + 0.03  # a little generous
	capsule.height = maxf(length * k, capsule.radius * 2.0)
	shape.shape = capsule
	shape.rotation.x = PI / 2  # capsule axis along Z
	shape.position = aabb.get_center() * k
	hit.add_child(shape)
	add_child(hit)


## Its weight (kg), in its species' range.
func weight() -> float:
	return lerpf(species.weight.x, species.weight.y, size)


## The XP for catching it: bigger pays up to +50%.
func xp_scale() -> float:
	return 1.0 + 0.5 * size


func set_swim(amount: float) -> void:
	for s in _surfaces:
		s.set_instance_shader_parameter("swim", amount)


func set_highlighted(on: bool) -> void:
	for s in _surfaces:
		s.set_instance_shader_parameter("highlight", 1.0 if on else 0.0)


func flash() -> void:
	if _flash_tween:
		_flash_tween.kill()
	_flash_tween = create_tween()
	_flash_tween.tween_method(func(v: float) -> void:
		for s in _surfaces:
			s.set_instance_shader_parameter("flash", v), 0.8, 0.0, 0.12)


## True if your `tool` (&"spear" or &"rod") is good enough for this species.
func tool_can_take(tool: StringName) -> bool:
	return Tools.can_work(tool, species.tool_tier)


## "Needs Iron spear": your `tool` is too weak for it.
func needs_text(tool: StringName) -> String:
	return "Needs %s" % Tools.display_name(tool, species.tool_tier)


## Under-levelled for this species: the spear only sometimes takes it (it usually dodges).
func is_under_levelled() -> bool:
	return Skills.levels_under(&"fishing", species.required_level) > 0


## The chance a spear thrust through this fish takes it: certain at or above its level, 10% less
## per level under, never below 10%.
func catch_chance() -> float:
	return Skills.under_scale(&"fishing", species.required_level, 0.1, 0.1)
