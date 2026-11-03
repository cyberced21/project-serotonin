class_name CartPanel
extends CanvasLayer
## Where to? (plans/road-travel.md): rung at a cart stop, the stops the cart can take you to from
## there along the better roads, nearest first, each with how far. Pick one and the cart comes;
## Esc, E or walking away puts the card away. In the noticeboard's wood-and-parchment look.

const CLOSE_DISTANCE := 6.0

var stop: CartStop
var _closed_msec := -100000
var _shade: ColorRect
var _title: Label
var _list: VBoxContainer


static func open_for(s: CartStop) -> CartPanel:
	var tree := s.get_tree()
	var panel := tree.get_first_node_in_group("cart_panel") as CartPanel
	if panel == null:
		panel = CartPanel.new()
		tree.current_scene.add_child(panel)
	panel.open(s)
	return panel


func _ready() -> void:
	add_to_group("cart_panel")
	add_to_group("modal_panel")
	layer = 3
	_build()
	_shade.visible = false


func is_open() -> bool:
	return stop != null


func just_closed() -> bool:
	return Time.get_ticks_msec() - _closed_msec < 250


func open(s: CartStop) -> void:
	stop = s
	_title.text = "Where to? (%s)" % s.stop_name
	for c in _list.get_children():
		c.queue_free()
	var to: Array = s.line.destinations(s.stop_id)
	if to.is_empty():
		_list.add_child(_label("Nowhere yet: the cart only runs on packed and cobbled roads, to the stops at their ends you've been to.", 17, Color(NoticeboardPanel.GOLD, 0.8)))
	for d in to:
		var b := Button.new()
		b.text = "%s  ·  %d m" % [d["name"], roundi(d["length"])]
		b.add_theme_font_override("font", MapView.map_font(false))
		b.add_theme_font_size_override("font_size", 20)
		b.pressed.connect(_go.bind(d["id"]))
		_list.add_child(b)
	_shade.visible = true
	_shade.modulate.a = 0.0
	create_tween().tween_property(_shade, "modulate:a", 1.0, 0.2)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Sfx.play_ui(&"open")


func close() -> void:
	if stop == null:
		return
	stop = null
	_closed_msec = Time.get_ticks_msec()
	_shade.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _go(to: StringName) -> void:
	var s := stop
	close()
	Sfx.play_ui(&"close")
	s.line.call_cart(s.stop_id, to)


func _input(event: InputEvent) -> void:
	if stop == null:
		return
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("interact"):
		close()
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if stop == null:
		return
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if not is_instance_valid(stop) or (player and player.global_position.distance_to(stop.global_position) > CLOSE_DISTANCE):
		close()


func _build() -> void:
	_shade = ColorRect.new()
	_shade.color = Color(0, 0, 0, 0.4)
	_shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_shade)
	var frame := PanelContainer.new()
	var wood := StyleBoxFlat.new()
	wood.bg_color = NoticeboardPanel.WOOD
	wood.border_color = NoticeboardPanel.BRONZE
	wood.set_border_width_all(3)
	wood.set_corner_radius_all(6)
	wood.set_content_margin_all(18)
	wood.shadow_color = Color(0, 0, 0, 0.6)
	wood.shadow_size = 18
	frame.add_theme_stylebox_override("panel", wood)
	MenuUI.place(frame, Rect2(0.32, 0.24, 0.36, 0.52))
	_shade.add_child(frame)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	frame.add_child(box)
	_title = _label("", 28, NoticeboardPanel.GOLD, true)
	box.add_child(_title)
	box.add_child(_label("The carter's pony knows the way. Move to hop off whenever you like.", 16, Color(NoticeboardPanel.GOLD, 0.7)))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 6)
	scroll.add_child(_list)


func _label(text: String, size: int, color: Color, bold := false) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_override("font", MapView.map_font(bold))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l
