class_name TrophyFind
extends StaticBody3D
## A trophy lying out in the world for you to find (plans/trophies.md): the eagle's feather in
## Frostpeak's snow, the big shell on Stillwater's shore. A small glinting thing; E picks it up
## (Trophies.found). Home puts them out and remembers them.
## It tells you it's near (plans/mine.md): a soft glint of sound the first time you come within
## HINT_RANGE, and the dog goes over and sniffs at it (Dog's hints, the "trophy_find" group).

signal picked

const GLINT := Color("fff3c4")
const GLINT_SOUND := preload("res://audio/forge/glint.wav")
const HINT_RANGE := 18.0

var kind: StringName
var _heard := false


static func make(at: Vector3, what: StringName) -> TrophyFind:
	var f := TrophyFind.new()
	f.kind = what
	f.add_to_group("trophy_find")
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


func _process(_delta: float) -> void:
	if _heard:
		return
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player and player.global_position.distance_to(global_position) < HINT_RANGE:
		_heard = true
		var sound := AudioStreamPlayer3D.new()
		sound.stream = GLINT_SOUND
		sound.volume_db = -12.0
		sound.pitch_scale = 1.35
		sound.max_distance = 30.0
		sound.bus = &"Effects"
		add_child(sound)
		sound.play()


func prompt() -> String:
	return "E  Pick up the %s" % ("feather" if kind == &"feather" else "shell")


func interact() -> void:
	Trophies.found(kind, global_position)
	picked.emit()
	queue_free()


func set_highlighted(_on: bool) -> void:
	pass
