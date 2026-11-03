class_name CartStop
extends Prop
## A stop for the carter's cart (plans/road-travel.md): a signpost with a bell, at the cart shed or
## at the end of a better road you've been to (CartLine puts them up). Look at it and press E to
## ring for the cart and say where to (CartPanel).

const MODEL := preload("res://models/village/props/signpost.glb")

var line: CartLine
## Its place on the cart's network (CartLine) and its name on the route card.
var stop_id: StringName
var stop_name := ""
var _surfaces: Array[GeometryInstance3D] = []


func _init() -> void:
	model = MODEL
	snap_to_ground = true


func _ready() -> void:
	super()
	add_to_group("cart_stop")
	for m in find_children("*", "MeshInstance3D", true, false):
		_surfaces.append(m as GeometryInstance3D)


## Shown under the crosshair (player.gd treats anything with interact() like a villager).
func prompt() -> String:
	return "E  Ring for the cart (%s)" % stop_name


func interact() -> void:
	if line and not line.riding():
		CartPanel.open_for(self)


func set_highlighted(on: bool) -> void:
	for s in _surfaces:
		s.set_instance_shader_parameter("highlight", 1.0 if on else 0.0)
