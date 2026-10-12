class_name PopupText
extends Label3D
## Small floating text that pops up, rises and fades ("+5", "Mining 15").
## Faces the camera and draws on top of everything.
## Spawn with PopupText.spawn(parent, world_pos, text, color).

const RISE := 0.5
const LIFETIME := 0.7
## font_size is given in the old 2D pixel units and multiplied by this.
const FONT_SCALE := 6


static func spawn(parent: Node, pos: Vector3, text: String, color: Color, font_size := 8, delay := 0.0) -> void:
	var p := PopupText.new()
	p.text = text
	p.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	p.no_depth_test = true
	p.pixel_size = 0.005
	p.font_size = font_size * FONT_SCALE
	p.outline_size = 12
	p.modulate = color
	p.outline_modulate = Color(0, 0, 0, 0.7)
	p.render_priority = 10
	p.outline_render_priority = 9
	p.visible = delay <= 0.0
	parent.add_child(p)
	p.global_position = pos
	p._animate(delay)


func _animate(delay: float) -> void:
	var t := create_tween()
	if delay > 0.0:
		t.tween_interval(delay)
		t.tween_callback(show)
	t.tween_property(self, "scale", Vector3.ONE, 0.15).from(Vector3.ONE * 1.5) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(self, "position:y", position.y + RISE, LIFETIME) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(self, "modulate:a", 0.0, LIFETIME * 0.4).set_delay(LIFETIME * 0.6)
	t.parallel().tween_property(self, "outline_modulate:a", 0.0, LIFETIME * 0.4).set_delay(LIFETIME * 0.6)
	t.tween_callback(queue_free)
