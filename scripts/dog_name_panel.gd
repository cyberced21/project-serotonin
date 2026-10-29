class_name DogNamePanel
extends CanvasLayer
## Meeting your dog (plans/dog.md): the stray you petted wags at you and this asks his name (a
## suggested one already filled in: just accept it) and his coat. "Come along!" (or Enter) makes
## him yours; Esc, E or walking away leaves him napping. In the noticeboard's wood-and-parchment
## look. Frees the mouse while open.

signal chosen(coat: StringName, dog_name: String)

const CLOSE_DISTANCE := 6.0

var stray: Dog
var _closed_msec := -100000
var _shade: ColorRect
var _title: Label
var _name: LineEdit
var _coats: HBoxContainer
var _coat: StringName = &""


static func open_for(d: Dog) -> DogNamePanel:
	var tree := d.get_tree()
	var panel := tree.get_first_node_in_group("dog_name_panel") as DogNamePanel
	if panel == null:
		panel = DogNamePanel.new()
		tree.current_scene.add_child(panel)
	panel.open(d)
	return panel


func _ready() -> void:
	add_to_group("dog_name_panel")
	add_to_group("modal_panel")
	layer = 3
	_build()
	_shade.visible = false


func is_open() -> bool:
	return stray != null


func just_closed() -> bool:
	return Time.get_ticks_msec() - _closed_msec < 250


func open(d: Dog) -> void:
	stray = d
	_title.text = "The %s wags at you" % Companion.BREED_NAMES.get(d.breed, "dog")
	_name.text = Companion.NAMES[randi() % Companion.NAMES.size()]
	for c in _coats.get_children():
		c.queue_free()
	var coats: Array = Companion.COATS[d.breed]
	for coat: StringName in coats:
		var b := Button.new()
		b.text = Companion.COAT_NAMES.get(coat, String(coat))
		b.toggle_mode = true
		b.add_theme_font_override("font", MapView.map_font(false))
		b.add_theme_font_size_override("font_size", 18)
		b.pressed.connect(_pick_coat.bind(coat))
		b.set_meta("coat", coat)
		_coats.add_child(b)
	_pick_coat.call_deferred(d.coat)
	_shade.visible = true
	_shade.modulate.a = 0.0
	create_tween().tween_property(_shade, "modulate:a", 1.0, 0.2)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Sfx.play_ui(&"open")
	_name.grab_focus.call_deferred()
	_name.select_all.call_deferred()


func close() -> void:
	if stray == null:
		return
	stray = null
	_closed_msec = Time.get_ticks_msec()
	_shade.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## He's yours: `coat` (or the one picked) and the name typed.
func confirm(coat := &"", dog_name := "") -> void:
	if stray == null:
		return
	var c := coat if coat != &"" else _coat
	var n := dog_name if not dog_name.is_empty() else _name.text.strip_edges()
	if n.is_empty():
		n = Companion.NAMES[0]
	close()
	Sfx.play_ui(&"close")
	chosen.emit(c, n)


func _pick_coat(coat: StringName) -> void:
	_coat = coat
	for b in _coats.get_children():
		(b as Button).button_pressed = b.get_meta("coat") == coat


func _input(event: InputEvent) -> void:
	if stray == null:
		return
	if event.is_action_pressed("ui_cancel") or (event.is_action_pressed("interact") and not _name.has_focus()):
		close()
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if stray == null:
		return
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if not is_instance_valid(stray) or (player and player.global_position.distance_to(stray.global_position) > CLOSE_DISTANCE):
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
	MenuUI.place(frame, Rect2(0.3, 0.28, 0.4, 0.44))
	_shade.add_child(frame)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	frame.add_child(box)
	_title = _label("", 28, NoticeboardPanel.GOLD, true)
	box.add_child(_title)
	box.add_child(_label("He's been waiting for someone. What's his name?", 17, Color(NoticeboardPanel.GOLD, 0.8)))
	_name = LineEdit.new()
	_name.max_length = 18
	_name.add_theme_font_override("font", MapView.map_font(true))
	_name.add_theme_font_size_override("font_size", 24)
	_name.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name.text_submitted.connect(func(_t: String) -> void: confirm())
	box.add_child(_name)
	box.add_child(_label("His coat", 17, Color(NoticeboardPanel.GOLD, 0.8)))
	_coats = HBoxContainer.new()
	_coats.alignment = BoxContainer.ALIGNMENT_CENTER
	_coats.add_theme_constant_override("separation", 8)
	box.add_child(_coats)
	var go := Button.new()
	go.text = "Come along!"
	go.add_theme_font_override("font", MapView.map_font(true))
	go.add_theme_font_size_override("font_size", 22)
	go.pressed.connect(func() -> void: confirm())
	box.add_child(go)


func _label(text: String, size: int, color: Color, bold := false) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_override("font", MapView.map_font(bold))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l
