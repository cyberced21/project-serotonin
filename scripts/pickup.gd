extends RigidBody3D
## Loot that pops out of a node, bounces and settles, then gets magnetised to the player.
## Shows the item's model (Items.model) tumbling as it bounces, or its icon if it has none.
## Drops sitting around for a while get pulled from much further away, so loot that rolled
## behind a rock isn't lost (and the world doesn't fill up with drops).

@export var settle_time := 0.35
## Width of the floating icon in the world (m).
@export var icon_size := 0.32
@export var magnet_radius := 3.0
## After this many seconds, drops are pulled from auto_pull_radius instead.
@export var auto_pull_time := 4.0
@export var auto_pull_radius := 15.0
## How quickly a magnetised drop turns toward the player (higher = snappier).
@export var magnet_steer := 8.0
@export var magnet_max_speed := 14.0
## Drops fly to this height on the player (chest), not into the camera.
@export var collect_height := 1.0

## Scale of the item's model (models/items/*.glb are roughly hand-sized already).
@export var model_scale := 0.9

const PALETTE := preload("res://materials/node_palette.tres")

var item: StringName = &"wood"
var icon: Texture2D
var _model: Node3D

@onready var sprite: Sprite3D = $Sprite3D

var _delay := 0.0
var _age := 0.0
var _launch_velocity := Vector3.ZERO
var _magnet := false
var _vel := Vector3.ZERO


func _ready() -> void:
	var scene := Items.model(item)
	if scene:
		# the item itself, tumbling as the body bounces (rigid body rotation does the rest)
		_model = scene.instantiate() as Node3D
		add_child(_model)
		_model.scale = Vector3.ONE * model_scale
		var bounds := AABB()
		var first := true
		for m in _model.find_children("*", "MeshInstance3D", true, false):
			var mesh := m as MeshInstance3D
			mesh.material_override = PALETTE
			var box := global_transform.affine_inverse() * mesh.global_transform * mesh.get_aabb()
			bounds = box if first else bounds.merge(box)
			first = false
		# a box the shape of the item, so it tumbles and comes to rest lying flat
		var shape := $CollisionShape3D as CollisionShape3D
		var fitted := BoxShape3D.new()
		fitted.size = bounds.size.max(Vector3.ONE * 0.08)
		shape.shape = fitted
		shape.position = bounds.get_center()
		sprite.visible = false
		return
	sprite.texture = icon
	if icon:
		sprite.pixel_size = icon_size / icon.get_width()  # same size in the world whatever the icon resolution


## Call after adding to the tree.
func launch(from: Vector3, velocity: Vector3, delay := 0.0) -> void:
	global_position = from
	_launch_velocity = velocity
	_delay = delay
	if delay > 0.0:
		visible = false
		freeze = true
	else:
		linear_velocity = velocity


func _physics_process(delta: float) -> void:
	if _delay > 0.0:
		_delay -= delta
		if _delay <= 0.0:
			visible = true
			freeze = false
			linear_velocity = _launch_velocity
		return

	_age += delta
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player == null:
		return
	var target := player.global_position + Vector3(0, collect_height, 0)

	if not _magnet:
		var d := global_position.distance_to(target)
		if _age > settle_time and (d < magnet_radius or (_age > auto_pull_time and d < auto_pull_radius)):
			_magnet = true
			freeze = true  # kinematic: we move it ourselves from here on
			_vel = Vector3.UP * 2.0  # small hop before it zips over
		return

	var to_target := target - global_position
	if to_target.length() < 0.35:
		_collect()
		return
	# steer (blend toward the desired velocity) rather than accelerate, so fast drops home in
	# instead of orbiting the player
	var desired := to_target.normalized() * magnet_max_speed
	_vel = _vel.lerp(desired, 1.0 - exp(-magnet_steer * delta))
	global_position += _vel * delta
	if _model:  # spin and shrink a little on the way in
		rotate_y(9.0 * delta)
		_model.scale = _model.scale.move_toward(Vector3.ONE * model_scale * 0.6, delta)


func _collect() -> void:
	Inventory.add(item)
	Sfx.play_pickup()
	queue_free()
