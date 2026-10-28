extends CanvasLayer
## Esc in a world pauses the game (the whole tree: day and night, fish, villagers, a falling tree
## all hold) and opens this: Resume, Skills, Settings, Controls, Save & Quit to Menu, Quit to Desktop.
## Esc again resumes. The upgrade panel and the debug menu take Esc first while they're open.
## Leaving takes a picture for the world's card (thumb.png) without the menus in it, then shows a
## "Saved" toast that stays up over the main menu.

const THUMB_SIZE := Vector2i(320, 180)

var _shade: ColorRect
var _panel: PanelContainer
var _column: VBoxContainer
var _world_label: Label
var _controls: ControlsScreen
var _skills: SkillsScreen
var _skills_button: Button
var _settings: SettingsScreen
var _toast: Label
var _busy := false


func _ready() -> void:
	layer = 15
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	_hide_all()


func is_open() -> bool:
	return _shade.visible


func open() -> void:
	if is_open() or Worlds.current.is_empty():
		return
	get_tree().paused = true
	_world_label.text = Worlds.current_meta.get("name", "")
	_skills_button.text = "Skills  · a talent to choose" if Skills.talents.any_waiting() else "Skills"
	_shade.visible = true
	_show_panel()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	(_column.get_child(0) as Button).grab_focus()


func resume() -> void:
	if not is_open() or _busy:
		return
	_hide_all()
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("skills") and not _busy:
		_toggle_skills()
		return
	if not event.is_action_pressed("ui_cancel") or _busy:
		return
	if is_open():
		if _controls.visible or _settings.visible or _skills.visible:
			_show_panel()
		else:
			resume()
		get_viewport().set_input_as_handled()
	elif not Worlds.current.is_empty() and not _other_menu_open():
		open()
		get_viewport().set_input_as_handled()


## K: the Skills page straight from play (paused, like the menu), and K again back to play.
func _toggle_skills() -> void:
	if is_open():
		if _skills.visible:
			resume()
			get_viewport().set_input_as_handled()
		return
	if Worlds.current.is_empty() or _other_menu_open():
		return
	var cards := get_tree().get_first_node_in_group("talent_cards") as TalentCards
	if cards and cards.is_open():
		return
	open()
	_show_skills()
	get_viewport().set_input_as_handled()


## The upgrade panel and debug menu close on Esc themselves (their _input runs before this one).
func _other_menu_open() -> bool:
	for panel in get_tree().get_nodes_in_group("modal_panel"):  # a villager's panel, the noticeboard
		if panel.is_open():
			return true
	return false


func _show_panel() -> void:
	_controls.visible = false
	_skills.visible = false
	_settings.visible = false
	_panel.visible = true
	(_column.get_child(0) as Button).grab_focus()


func _show_controls() -> void:
	_panel.visible = false
	_controls.visible = true


func _show_skills() -> void:
	_panel.visible = false
	_skills.visible = true


func _show_settings() -> void:
	_panel.visible = false
	_settings.visible = true


func _save_and_quit(to_desktop: bool) -> void:
	if _busy:
		return
	_busy = true
	_hide_all()
	await _take_thumbnail()
	if to_desktop:
		SaveGame.save()
		get_tree().quit()
		return
	Worlds.leave()
	_busy = false
	show_toast("Saved")


## The world's card picture: the next frame drawn without any menus or the HUD, scaled down.
func _take_thumbnail() -> void:
	var hidden: Array[CanvasLayer] = []
	for node in get_tree().root.find_children("*", "CanvasLayer", true, false):
		var cl := node as CanvasLayer
		if cl.visible and cl != self:
			cl.visible = false
			hidden.append(cl)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	for cl in hidden:
		if is_instance_valid(cl):
			cl.visible = true
	if img == null or Worlds.current.is_empty():
		return
	var aspect := float(THUMB_SIZE.x) / THUMB_SIZE.y
	var w := img.get_width()
	var h := img.get_height()
	if float(w) / h > aspect:  # crop the sides to 16:9
		var cw := int(h * aspect)
		img = img.get_region(Rect2i((w - cw) / 2, 0, cw, h))
	else:
		var ch := int(w / aspect)
		img = img.get_region(Rect2i(0, (h - ch) / 2, w, ch))
	img.resize(THUMB_SIZE.x, THUMB_SIZE.y, Image.INTERPOLATE_LANCZOS)
	img.save_png(ProjectSettings.globalize_path(Worlds.thumb_path(Worlds.current)))


## A short message at the top of the screen that fades out (it outlives a change of scene).
func show_toast(text: String) -> void:
	_toast.text = text
	_toast.visible = true
	_toast.modulate.a = 1.0
	var t := create_tween()
	t.tween_interval(1.4)
	t.tween_property(_toast, "modulate:a", 0.0, 0.6)
	t.tween_callback(func() -> void: _toast.visible = false)


func _hide_all() -> void:
	_shade.visible = false
	_panel.visible = false
	_controls.visible = false
	_skills.visible = false
	_settings.visible = false


func _build() -> void:
	_shade = ColorRect.new()
	_shade.color = Color(0, 0, 0, 0.45)
	_shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_shade)

	# every screen here is a share of the window (MenuUI.place), so none runs off it
	_panel = MenuUI.panel(30.0)
	MenuUI.place(_panel, Rect2(0.34, 0.1, 0.32, 0.8), true)
	_shade.add_child(_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	_panel.add_child(box)
	box.add_child(MenuUI.title("Paused", 40))
	_world_label = MenuUI.label("", 17, MenuUI.DIM)
	box.add_child(_world_label)
	box.add_child(MenuUI.spacer(6))
	_column = VBoxContainer.new()
	_column.add_theme_constant_override("separation", 10)
	box.add_child(_column)
	_column.add_child(MenuUI.button("Resume", resume, 24))
	_skills_button = MenuUI.button("Skills", _show_skills, 24)
	_column.add_child(_skills_button)
	_column.add_child(MenuUI.button("Settings", _show_settings, 24))
	_column.add_child(MenuUI.button("Controls", _show_controls, 24))
	_column.add_child(MenuUI.spacer(4))
	_column.add_child(MenuUI.button("Save & Quit to Menu", _save_and_quit.bind(false), 24))
	_column.add_child(MenuUI.button("Quit to Desktop", _save_and_quit.bind(true), 24))

	_controls = ControlsScreen.new()
	MenuUI.place(_controls, Rect2(0.2, 0.06, 0.6, 0.88), true)
	_controls.closed.connect(_show_panel)
	_shade.add_child(_controls)

	_skills = SkillsScreen.new()
	MenuUI.place(_skills, Rect2(0.05, 0.05, 0.9, 0.9))
	_skills.closed.connect(_show_panel)
	_shade.add_child(_skills)

	_settings = SettingsScreen.new()
	MenuUI.place(_settings, Rect2(0.15, 0.06, 0.7, 0.88))
	_settings.closed.connect(_show_panel)
	_shade.add_child(_settings)

	_toast = MenuUI.label("", 22, MenuUI.GOOD)
	_toast.anchor_left = 0.5
	_toast.anchor_right = 0.5
	_toast.offset_top = 28
	_toast.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.visible = false
	add_child(_toast)
