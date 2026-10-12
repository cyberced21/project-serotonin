class_name PopupText
extends Label
## Small floating text that pops up, rises and fades ("+5", "Mining 15").
## Spawn with PopupText.spawn(parent, world_pos, text, color).

const RISE := 14.0
const LIFETIME := 0.7
const WIDTH := 80.0


static func spawn(parent: Node, pos: Vector2, text: String, color: Color, font_size := 8, delay := 0.0) -> void:
	var p := PopupText.new()
	p.text = text
	p.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	p.size = Vector2(WIDTH, 10)
	p.pivot_offset = Vector2(WIDTH / 2.0, 5)
	p.position = pos - Vector2(WIDTH / 2.0, 0)
	p.z_index = 100
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_theme_font_size_override("font_size", font_size)
	p.add_theme_color_override("font_color", color)
	p.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	p.add_theme_constant_override("shadow_offset_x", 1)
	p.add_theme_constant_override("shadow_offset_y", 1)
	p.visible = delay <= 0.0
	parent.add_child(p)
	p._animate(delay)


func _animate(delay: float) -> void:
	var t := create_tween()
	if delay > 0.0:
		t.tween_interval(delay)
		t.tween_callback(show)
	t.tween_property(self, "scale", Vector2.ONE, 0.15).from(Vector2(1.5, 1.5)) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(self, "position:y", position.y - RISE, LIFETIME) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(self, "modulate:a", 0.0, LIFETIME * 0.4).set_delay(LIFETIME * 0.6)
	t.tween_callback(queue_free)
