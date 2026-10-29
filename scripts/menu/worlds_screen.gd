class_name WorldsScreen
extends PanelContainer
## The Worlds screen: every world as a card (picture, name, what it is, when it was last played and
## for how long), the most recent first. Pick one, then Play, Rename or Reset. Today that's just
## Hearthvale: generated worlds went with plans/world.md.

signal closed

const THUMB := Vector2(160, 90)

var _list: VBoxContainer
var _cards: Dictionary[String, PanelContainer] = {}
var _selected := ""
var _play: Button
var _rename: Button
var _delete: Button
var _delete_armed := false
var _rename_row: HBoxContainer
var _rename_edit: LineEdit


func _init() -> void:
	add_theme_stylebox_override("panel", MenuUI.box(MenuUI.BG, 20.0, MenuUI.BORDER))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	add_child(box)

	var head := HBoxContainer.new()
	var t := MenuUI.title("Worlds", 30)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	box.add_child(head)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 8)
	scroll.add_child(_list)

	_rename_row = HBoxContainer.new()
	_rename_edit = MenuUI.line_edit("World name")
	_rename_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rename_edit.text_submitted.connect(func(_t: String) -> void: _finish_rename(true))
	_rename_row.add_child(_rename_edit)
	_rename_row.add_child(MenuUI.button("Save", _finish_rename.bind(true), 16))
	_rename_row.add_child(MenuUI.button("Cancel", _finish_rename.bind(false), 16))
	_rename_row.visible = false
	box.add_child(_rename_row)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_play = MenuUI.button("Play", _on_play, 18)
	_play.custom_minimum_size = Vector2(120, 0)
	row.add_child(_play)
	_rename = MenuUI.button("Rename", _start_rename, 16)
	row.add_child(_rename)
	_delete = MenuUI.button("Delete", _on_delete, 16)
	row.add_child(_delete)
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(gap)
	row.add_child(MenuUI.button("Back", func() -> void: closed.emit(), 16))
	box.add_child(row)


func _ready() -> void:
	Worlds.list_changed.connect(refresh)
	refresh()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		if _rename_row.visible:
			_finish_rename(false)
		else:
			closed.emit()
		get_viewport().set_input_as_handled()


## Rebuilds the cards, keeping the selection if that world is still there.
func refresh(select := "") -> void:
	for c in _list.get_children():
		c.queue_free()
	_cards.clear()
	var worlds := Worlds.list()
	for m in worlds:
		var card := _card(m)
		_cards[m["id"]] = card
		_list.add_child(card)
	if not select.is_empty():
		_selected = select
	if not _cards.has(_selected):
		_selected = worlds[0]["id"] if not worlds.is_empty() else ""
	_select(_selected)


func _card(m: Dictionary) -> PanelContainer:
	var id: String = m["id"]
	var card := PanelContainer.new()
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			_select(id)
			if e.double_click:
				_on_play())
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(row)
	row.add_child(_thumb(m))
	var text := VBoxContainer.new()
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(text)
	text.add_child(MenuUI.label(m.get("name", id), 20, MenuUI.ACCENT))
	text.add_child(MenuUI.label(MenuUI.world_kind(m), 15))
	var played := float(m.get("last_played", 0.0))
	var when := "Not played yet" if played <= 0.0 else "Played %s · %s in all" % [MenuUI.ago(played),
			MenuUI.duration(float(m.get("playtime", 0.0)))]
	text.add_child(MenuUI.label(when, 14, MenuUI.DIM))
	for c in text.get_children():
		(c as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	return card


func _thumb(m: Dictionary) -> Control:
	var frame := PanelContainer.new()
	frame.custom_minimum_size = THUMB
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_theme_stylebox_override("panel", MenuUI.box(Color(0.2, 0.25, 0.18), 0.0, Color.TRANSPARENT, 6))
	var path := Worlds.thumb_path(m["id"])
	if FileAccess.file_exists(path):
		var img := Image.load_from_file(path)
		if img:
			var tex := TextureRect.new()
			tex.texture = ImageTexture.create_from_image(img)
			tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
			tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
			frame.add_child(tex)
			return frame
	var initial := MenuUI.label(String(m.get("name", "?")).left(1).to_upper(), 40, Color(1, 1, 1, 0.5))
	initial.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	initial.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	initial.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(initial)
	return frame


func _select(id: String) -> void:
	_selected = id
	_disarm_delete()
	_finish_rename(false)
	for k in _cards:
		_cards[k].add_theme_stylebox_override("panel", MenuUI.box(
				MenuUI.CARD_SELECTED if k == id else MenuUI.CARD, 10.0,
				MenuUI.ACCENT if k == id else Color.TRANSPARENT, 8))
	var m := Worlds.meta(id) if not id.is_empty() else {}
	var classic: bool = m.get("kind") == "classic"
	_play.disabled = m.is_empty()
	_rename.disabled = m.is_empty()
	_delete.disabled = m.is_empty() or (classic and not Worlds.has_save(id))
	_delete.text = "Reset" if classic else "Delete"
	_delete.tooltip_text = "Start Hearthvale over" if classic else ""


func _on_play() -> void:
	if not _selected.is_empty():
		Worlds.play(_selected)


func _on_delete() -> void:
	var classic: bool = _selected == Worlds.CLASSIC
	if not _delete_armed:
		_delete_armed = true
		_delete.text = "Really reset? Click again" if classic else "Really delete? Click again"
		_delete.add_theme_color_override("font_color", MenuUI.WARN)
		return
	_disarm_delete()
	if classic:
		Worlds.reset(_selected)
	else:
		Worlds.delete(_selected)


func _disarm_delete() -> void:
	_delete_armed = false
	_delete.text = "Reset" if _selected == Worlds.CLASSIC else "Delete"
	_delete.remove_theme_color_override("font_color")


func _start_rename() -> void:
	if _selected.is_empty():
		return
	_rename_edit.text = Worlds.meta(_selected).get("name", "")
	_rename_row.visible = true
	_rename_edit.grab_focus()
	_rename_edit.select_all()


func _finish_rename(keep: bool) -> void:
	if not _rename_row.visible:
		return
	_rename_row.visible = false
	if keep:
		Worlds.rename(_selected, _rename_edit.text)
