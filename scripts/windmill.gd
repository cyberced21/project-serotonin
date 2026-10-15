extends Prop
## Goldmeadow's windmill: a Prop whose model has a "Sails" mesh (origin on the hub, axle along Z;
## see make_models.py windmill()) that keeps turning. Its collision is the tower only (a
## CollisionShape3D in the scene), so the sails don't make a giant invisible box.

## Turns per second; a lazy breeze.
@export var speed := 0.12

var _sails: Node3D


func _ready() -> void:
	super()
	_sails = find_child("Sails", true, false) as Node3D


func _process(delta: float) -> void:
	if _sails:
		_sails.rotate_object_local(Vector3.FORWARD, speed * TAU * delta)
