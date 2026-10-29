class_name DeskNote
extends StaticBody3D
## A note on your desk (plans/home.md, HomeNotes): E reads it (its words above it a while, and a
## little gift if it came with one into your pack), then it's gone.

signal read

const PAPER := Color("efe3c6")
const GIFT_COLOR := Color("ffe08a")

var note: Dictionary = {}


static func make(at: Vector3, n: Dictionary) -> DeskNote:
	var d := DeskNote.new()
	d.note = n
	d.collision_layer = LookObject.LAYER
	d.collision_mask = 0
	d.position = at
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.5, 0.3, 0.5)
	shape.shape = box
	d.add_child(shape)
	var paper := MeshInstance3D.new()
	var quad := BoxMesh.new()
	quad.size = Vector3(0.28, 0.01, 0.36)
	paper.mesh = quad
	var mat := StandardMaterial3D.new()
	mat.albedo_color = PAPER
	paper.material_override = mat
	paper.rotation.y = 0.25
	d.add_child(paper)
	return d


func prompt() -> String:
	return note.get("prompt", "E  Read the note from %s" % note.get("from", "someone"))


func interact() -> void:
	var gift: Dictionary = note.get("gift", {})
	var line := "“%s”\n— %s" % [note.get("text", ""), note.get("from", "")]
	var parent := get_parent()
	var at := global_position
	var l := Label3D.new()
	l.text = line
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.pixel_size = 0.004
	l.font_size = 40
	l.outline_size = 12
	l.width = 1000.0
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.modulate = LookObject.LINE_COLOR
	l.outline_modulate = Color(0, 0, 0, 0.55)
	l.render_priority = 10
	l.outline_render_priority = 9
	parent.add_child(l)
	l.global_position = at + Vector3.UP * 0.7
	var t := l.create_tween()
	t.tween_property(l, "modulate:a", 1.0, 0.25).from(0.0)
	t.tween_interval(LookObject.HOLD + 2.0)
	t.tween_property(l, "modulate:a", 0.0, 0.6)
	t.tween_callback(l.queue_free)
	var delay := 0.6
	for item: StringName in gift:
		Inventory.add(item, int(gift[item]))
		PopupText.spawn(parent, at + Vector3.UP * 0.3, "+%d %s" % [int(gift[item]), Items.display_name(item)],
				GIFT_COLOR, 9, delay)
		delay += 0.3
	read.emit()
	queue_free()


func set_highlighted(_on: bool) -> void:
	pass
