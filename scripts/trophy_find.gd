class_name TrophyFind
extends StaticBody3D
## A trophy lying out in the world for you to find (plans/trophies.md): the eagle's feather in
## Frostpeak's snow, the big shell on Stillwater's shore. A small glinting thing; E picks it up
## (Trophies.found). Home puts them out and remembers them.

signal picked

const GLINT := Color("fff3c4")

var kind: StringName


static func make(at: Vector3, what: StringName) -> TrophyFind:
	var f := TrophyFind.new()
	f.kind = what
	f.collision_layer = LookObject.LAYER
	f.collision_mask = 0
	f.position = at
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.8, 0.6, 0.8)
	shape.shape = box
	f.add_child(shape)
	var mesh := MeshInstance3D.new()
	if what == &"feather":
		var quad := BoxMesh.new()
		quad.size = Vector3(0.08, 0.02, 0.42)
		mesh.mesh = quad
		mesh.rotation = Vector3(0.0, randf() * TAU, 0.15)
	else:
		var shell := SphereMesh.new()
		shell.radius = 0.14
		shell.height = 0.16
		mesh.mesh = shell
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("f2efe6") if what == &"feather" else Color("e9c9a8")
	mat.emission_enabled = true  # (a faint glint, so it can be spotted)
	mat.emission = GLINT
	mat.emission_energy_multiplier = 0.35
	mesh.material_override = mat
	mesh.position.y = 0.06
	f.add_child(mesh)
	return f


func prompt() -> String:
	return "E  Pick up the %s" % ("feather" if kind == &"feather" else "shell")


func interact() -> void:
	Trophies.found(kind, global_position)
	picked.emit()
	queue_free()


func set_highlighted(_on: bool) -> void:
	pass
