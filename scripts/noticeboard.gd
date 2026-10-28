class_name Noticeboard
extends Prop
## The village noticeboard in the square (plans/projects.md P1): look at it and press E to read
## the projects pinned on it (NoticeboardPanel) and pay for one.

const MODEL := preload("res://models/village/props/noticeboard.glb")

var _surfaces: Array[GeometryInstance3D] = []


func _init() -> void:
	model = MODEL
	snap_to_ground = true


func _ready() -> void:
	super()
	add_to_group("noticeboard")
	for m in find_children("*", "MeshInstance3D", true, false):
		_surfaces.append(m as GeometryInstance3D)


## Shown under the crosshair (player.gd treats anything with interact() like a villager).
func prompt() -> String:
	var open := 0
	for p in Projects.all():
		if not p["done"] and not Projects.is_locked(p["id"]):
			open += 1
	return "E  Read the noticeboard (%d %s)" % [open, "project" if open == 1 else "projects"]


func interact() -> void:
	NoticeboardPanel.open_for(self)


func set_highlighted(on: bool) -> void:
	for s in _surfaces:
		s.set_instance_shader_parameter("highlight", 1.0 if on else 0.0)
