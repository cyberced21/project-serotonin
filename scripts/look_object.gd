class_name LookObject
extends StaticBody3D
## Something in a villager's house worth a look (plans/home.md): E shows a short line in their
## voice above it. Made by Building from the model's Look* markers, its words from the building's
## BuildingDef.looks. No collision with you (the furniture under it has its own); it's only there
## for the crosshair, on the NPC layer like a villager.

const LAYER := 1 << 6
const LINE_COLOR := Color("fff1d6")
## Seconds the line stays up.
const HOLD := 4.5

var label := ""
var line := ""
var _shown: Label3D


static func make(at: Transform3D, look_label: String, look_line: String, size := 0.5) -> LookObject:
	var o := LookObject.new()
	o.label = look_label
	o.line = look_line
	o.collision_layer = LAYER
	o.collision_mask = 0
	o.transform = at
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3.ONE * size
	shape.shape = box
	o.add_child(shape)
	return o


func prompt() -> String:
	return "E  Look at %s" % label


func interact() -> void:
	if is_instance_valid(_shown):
		_shown.queue_free()
	var l := Label3D.new()
	l.text = line
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.pixel_size = 0.004
	l.font_size = 40
	l.outline_size = 12
	l.width = 900.0
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.modulate = LINE_COLOR
	l.outline_modulate = Color(0, 0, 0, 0.55)
	l.render_priority = 10
	l.outline_render_priority = 9
	add_child(l)
	l.position = Vector3.UP * 0.6
	_shown = l
	var t := l.create_tween()
	t.tween_property(l, "modulate:a", LINE_COLOR.a, 0.25).from(0.0)
	t.tween_interval(HOLD)
	t.tween_property(l, "modulate:a", 0.0, 0.6)
	t.tween_callback(l.queue_free)


func set_highlighted(_on: bool) -> void:
	pass
