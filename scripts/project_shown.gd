class_name ProjectShown
extends Node3D
## Shows its children only while a noticeboard project is done (or, with `when_done` off, only
## until it is): the orchard's broken wall gives way to the mended one (plans/world-pass.md,
## phase 7). Hidden, its children's bodies collide with nothing.

@export var project: StringName
@export var when_done := true

var _layers: Dictionary[CollisionObject3D, int] = {}


func _ready() -> void:
	for b in find_children("*", "CollisionObject3D", true, false):
		_layers[b as CollisionObject3D] = (b as CollisionObject3D).collision_layer
	child_entered_tree.connect(func(_n: Node) -> void: _apply.call_deferred())  # (a HedgeRow adds its body later)
	Projects.changed.connect(_apply)
	_apply.call_deferred()


func _apply() -> void:
	var on := Projects.is_done(project) == when_done
	visible = on
	for b in find_children("*", "CollisionObject3D", true, false):
		var body := b as CollisionObject3D
		if not _layers.has(body):
			_layers[body] = body.collision_layer
		body.collision_layer = _layers[body] if on else 0
