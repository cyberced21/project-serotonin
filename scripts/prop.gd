class_name Prop
extends StaticBody3D
## A piece of set dressing from a .glb (benches, lamps, barrels...): instances the model with the
## shared palette material and, unless turned off, one box collider around the whole thing.

const PALETTE := preload("res://materials/node_palette.tres")

@export var model: PackedScene
@export var collide := true


func _ready() -> void:
	var inst := model.instantiate() as Node3D
	add_child(inst)
	var bounds := AABB()
	var first := true
	for m in inst.find_children("*", "MeshInstance3D", true, false):
		var mesh := m as MeshInstance3D
		mesh.material_override = PALETTE
		var box := global_transform.affine_inverse() * mesh.global_transform * mesh.get_aabb()
		bounds = box if first else bounds.merge(box)
		first = false
	if collide and not first:
		var shape := CollisionShape3D.new()
		shape.shape = BoxShape3D.new()
		(shape.shape as BoxShape3D).size = bounds.size
		shape.position = bounds.get_center()
		add_child(shape)
