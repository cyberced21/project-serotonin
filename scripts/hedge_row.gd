class_name HedgeRow
extends Node3D
## A run of hedge or dry-stone wall along the field edges (plans/world-pass.md, phase 6): one model
## repeated along `points` (world XZ), each piece turned along its stretch and stood on the ground,
## drawn as one MultiMesh per mesh of the model. Each piece gets a box collider (the run follows the
## ground's ups and downs, so one long box wouldn't). Written by tools/bake_layout.gd (a map editor line).

const WORLD_LAYER := 1

@export var model: PackedScene
@export var points := PackedVector2Array()
## The model's size (the picked wall is 2 m high: a field wall wants about 1.1).
@export var model_scale := Vector3.ONE
## How far apart pieces stand along the run (their length, with a little overlap).
@export var spacing := 1.7
## Sunk this far into the ground, so it doesn't stand on its toes on a slope.
@export var sink := 0.12


func _ready() -> void:
	add_to_group("hedge_row")
	_build.call_deferred()  # (the terrain's data is in by then)


func _build() -> void:
	var terrain := get_tree().get_first_node_in_group("terrain") as Terrain3D
	var places: Array[Transform3D] = []
	for i in points.size() - 1:
		var a := points[i]
		var b := points[i + 1]
		var along := b - a
		var n := maxi(int(round(along.length() / spacing)), 1)
		var yaw := atan2(along.x, along.y) + PI / 2.0  # (the models run along their X)
		for k in n:
			var p := a + along * ((k + 0.5) / n)
			var y := 0.0
			if terrain and terrain.data:
				var h: float = terrain.data.get_height(Vector3(p.x, 0.0, p.y))
				y = 0.0 if is_nan(h) else h
			places.append(Transform3D(Basis(Vector3.UP, yaw).scaled(model_scale), Vector3(p.x, y - sink, p.y)))
	var inst := model.instantiate()
	var box := AABB()
	var first := true
	for m in inst.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		var x := Building._model_transform(mi, inst)
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mi.mesh
		mm.instance_count = places.size()
		for i in places.size():
			mm.set_instance_transform(i, global_transform.affine_inverse() * places[i] * x)
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		add_child(mmi)
		var b := x * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	inst.free()
	if first:
		return
	var body := StaticBody3D.new()
	body.collision_layer = WORLD_LAYER
	body.collision_mask = 0
	add_child(body)
	var size := box.size * model_scale.abs()
	for t in places:
		var shape := CollisionShape3D.new()
		var s := BoxShape3D.new()
		s.size = Vector3(size.x * 0.95, size.y, size.z)
		shape.shape = s
		var local := global_transform.affine_inverse() * Transform3D(t.basis.orthonormalized(), t.origin)
		shape.transform = local.translated_local(box.get_center() * model_scale)
		body.add_child(shape)


## The run's line, for keeping scenery out of it.
func line() -> PackedVector2Array:
	return points
