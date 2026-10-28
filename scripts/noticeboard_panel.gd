class_name NoticeboardPanel
extends CanvasLayer
## The noticeboard up close (plans/projects.md P9): paper notes pinned on cork, one per project
## open to you, in the map's wood-and-parchment look. Each note says what the project adds, what
## it costs (have / need), and has Pay; one waiting for the town hall says so; done ones are
## ticked, at the end. Paying closes the board so you can watch it being built.
## Frees the mouse while open; closes on E, Esc, clicking off the board, or walking away.

const CLOSE_DISTANCE := 4.5
const WOOD := Color(0.24, 0.15, 0.08, 0.98)
const BRONZE := Color(0.7, 0.52, 0.27)
const GOLD := Color(1.0, 0.86, 0.55)
const CORK := Color(0.52, 0.36, 0.22)
const PAPER := Color(0.93, 0.86, 0.69)
const PAPER_DONE := Color(0.84, 0.82, 0.74)
const INK := Color(0.24, 0.15, 0.08)
const HAVE := Color(0.18, 0.45, 0.16)
const NEED := Color(0.62, 0.17, 0.12)
const NOTE_WIDTH := 270.0

var board: Node3D
var _closed_msec := -100000
var _shade: ColorRect
var _grid: GridContainer


## Opens the board's panel (made the first time, in the current scene).
static func open_for(b: Node3D) -> void:
	var tree := b.get_tree()
	var panel := tree.get_first_node_in_group("noticeboard_panel") as NoticeboardPanel
	if panel == null:
		panel = NoticeboardPanel.new()
		tree.current_scene.add_child(panel)
	panel.open(b)


func _ready() -> void:
	add_to_group("noticeboard_panel")
	add_to_group("modal_panel")
	layer = 3
	_build()
	_shade.visible = false
	Inventory.changed.connect(func(_i: StringName, _c: int) -> void: _refresh())
	Projects.changed.connect(_refresh)
	Village.tier_changed.connect(func(_id: StringName, _t: int) -> void: _refresh())


func is_open() -> bool:
	return board != null


## True for a moment after closing, so the same E press doesn't reopen it.
func just_closed() -> bool:
	return Time.get_ticks_msec() - _closed_msec < 250


func open(b: Node3D) -> void:
	board = b
	_refresh()
	_shade.visible = true
	_shade.modulate.a = 0.0
	create_tween().tween_property(_shade, "modulate:a", 1.0, 0.2)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Sfx.play_ui(&"open")


func close() -> void:
	if board == null:
		return
	board = null
	_closed_msec = Time.get_ticks_msec()
	_shade.visible = false
	Sfx.play_ui(&"close")
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _input(event: InputEvent) -> void:
	if board == null:
		return
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("interact"):
		close()
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if board == null:
		return
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if not is_instance_valid(board) or (player and player.global_position.distance_to(board.global_position) > CLOSE_DISTANCE):
		close()


func _build() -> void:
	_shade = ColorRect.new()
	_shade.color = Color(0, 0, 0, 0.5)
	_shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_shade.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and (e as InputEventMouseButton).pressed:
			close())  # a click off the board: done
	add_child(_shade)
	var frame := PanelContainer.new()
	var wood := StyleBoxFlat.new()
	wood.bg_color = WOOD
	wood.border_color = BRONZE
	wood.set_border_width_all(3)
	wood.set_corner_radius_all(6)
	wood.set_content_margin_all(14)
	wood.shadow_color = Color(0, 0, 0, 0.6)
	wood.shadow_size = 18
	frame.add_theme_stylebox_override("panel", wood)
	MenuUI.place(frame, Rect2(0.1, 0.07, 0.8, 0.86))
	_shade.add_child(frame)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	frame.add_child(box)
	var title := _label("Village noticeboard", 30, GOLD, true)
	box.add_child(title)
	box.add_child(_label("What the village would love. Pay for one here and a villager will build it.", 16, Color(GOLD, 0.75)))
	var cork := PanelContainer.new()
	var cs := StyleBoxFlat.new()
	cs.bg_color = CORK
	cs.border_color = Color(BRONZE, 0.8)
	cs.set_border_width_all(2)
	cs.set_content_margin_all(16)
	cork.add_theme_stylebox_override("panel", cs)
	cork.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(cork)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	cork.add_child(scroll)
	_grid = GridContainer.new()
	_grid.columns = 3
	_grid.add_theme_constant_override("h_separation", 18)
	_grid.add_theme_constant_override("v_separation", 18)
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_grid)
	box.add_child(_label("E / Esc close", 15, Color(GOLD, 0.6)))


func _refresh() -> void:
	if _grid == null or board == null:
		return
	for c in _grid.get_children():
		c.queue_free()
	var open: Array[Dictionary] = []
	var done: Array[Dictionary] = []
	for p in Projects.all():
		(done if p["done"] else open).append(p)
	for p in open + done:
		_grid.add_child(_note(p))


## One pinned note.
func _note(p: Dictionary) -> Control:
	var note := PanelContainer.new()
	var ps := StyleBoxFlat.new()
	ps.bg_color = PAPER_DONE if p["done"] else PAPER
	ps.border_color = Color(INK, 0.25)
	ps.set_border_width_all(1)
	ps.set_content_margin_all(12)
	ps.shadow_color = Color(0, 0, 0, 0.35)
	ps.shadow_size = 4
	ps.shadow_offset = Vector2(2, 3)
	note.add_theme_stylebox_override("panel", ps)
	note.custom_minimum_size = Vector2(NOTE_WIDTH, 0)
	note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	note.add_child(col)
	var head := _label(("✓  " if p["done"] else "") + String(p["title"]), 19, INK, true)
	head.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(head)
	var blurb := _label(p["blurb"], 15, Color(INK, 0.85))
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(blurb)
	if p["done"]:
		col.add_child(_label("Done. Thank you!", 15, HAVE))
		note.modulate.a = 0.8
		return note
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 10)
	for item in p["cost"]:
		var need: int = p["cost"][item]
		var have := Inventory.count(item)
		var cell := HBoxContainer.new()
		var icon := TextureRect.new()
		icon.texture = Items.icon(item)
		icon.custom_minimum_size = Vector2(24, 24)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.tooltip_text = Items.display_name(item)
		cell.add_child(icon)
		cell.add_child(_label("%d/%d" % [mini(have, need), need], 15, HAVE if have >= need else NEED))
		row.add_child(cell)
	col.add_child(row)
	if Projects.is_locked(p["id"]):
		col.add_child(_label("Waits for the town hall at tier %d" % p["hall"], 15, Color(INK, 0.6)))
	else:
		var id: StringName = p["id"]
		var pay := Button.new()
		pay.text = "Pay"
		pay.focus_mode = Control.FOCUS_NONE
		pay.disabled = not Projects.can_pay(id)
		pay.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		pay.custom_minimum_size = Vector2(90, 0)
		pay.pressed.connect(func() -> void:
			if Projects.pay(id):
				close())
		col.add_child(pay)
	return note


func _label(text: String, size: int, color: Color, bold := false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", MapView.map_font(bold))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l
