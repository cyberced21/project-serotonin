class_name Prop
extends StaticBody3D
## A piece of set dressing from a .glb (benches, lamps, barrels...): instances the model with the
## shared palette material and, unless turned off, one box collider around the whole thing.

const PALETTE := preload("res://materials/node_palette.tres")

@export var model: PackedScene
@export var collide := true
## Exact collision box, centred on the prop's origin, instead of one fitted around the model
## (the parkour blocks: mantle and step heights depend on it).
@export var collision_size := Vector3.ZERO


func _ready() -> void:
	add_to_group("prop")
	var inst := model.instantiate() as Node3D
	add_child(inst)
	var bounds := AABB()
	var first := true
	for m in inst.find_children("*", "MeshInstance3D", true, false):
		var mesh := m as MeshInstance3D
		mesh.material_override = PALETTE
		if String(mesh.name).begins_with("Lamp"):  # lamp posts light up after dark
			DayNightSky.make_glow(mesh, true)
		var box := global_transform.affine_inverse() * mesh.global_transform * mesh.get_aabb()
		bounds = box if first else bounds.merge(box)
		first = false
	if collide and not first:
		var shape := CollisionShape3D.new()
		shape.shape = BoxShape3D.new()
		var exact := collision_size != Vector3.ZERO
		(shape.shape as BoxShape3D).size = collision_size if exact else bounds.size
		shape.position = Vector3.ZERO if exact else bounds.get_center()
		add_child(shape)


## Half the widest side of its footprint, for keeping scenery clear of it.
func footprint_radius() -> float:
	for c in get_children():
		var box := (c as CollisionShape3D).shape as BoxShape3D if c is CollisionShape3D else null
		if box:
			return maxf(box.size.x, box.size.z) * 0.5
	return 0.5
