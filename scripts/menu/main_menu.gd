extends Node
## The main menu (the game's first scene): the backdrop behind, the title and buttons on the left.
## Continue goes back into the world played last; on a first launch it's Play, into the classic
## world. Worlds opens the Worlds screen on the right.

const SCENE := "res://scenes/menu/main_menu.tscn"
const BACKDROP := preload("res://scenes/menu/backdrop.tscn")

var _ui: Control
var _column: VBoxContainer
var _continue: Button
var _continue_title: Label
var _continue_sub: Label
var _worlds: WorldsScreen
var _controls: ControlsScreen
var _settings: SettingsScreen


func _ready() -> void:
	if Worlds.skip_menu:
		Worlds.skip_menu = false  # coming back later shows the menu as usual
		return
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	add_child(BACKDROP.instantiate())
	var layer := CanvasLayer.new()
	add_child(layer)
	_ui = Control.new()
	_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(_ui)
	_build()
	Worlds.list_changed.connect(_refresh_continue)
	_refresh_continue()
	_continue.grab_focus.call_deferred()


func _build() -> void:
	# a soft dark band behind the buttons, fading out to the right
	var shade := TextureRect.new()
	var grad := GradientTexture2D.new()
	grad.gradient = Gradient.new()
	grad.gradient.set_color(0, Color(0, 0, 0, 0.6))
	grad.gradient.set_color(1, Color(0, 0, 0, 0))
	grad.fill_to = Vector2(1, 0)
	shade.texture = grad
	shade.anchor_bottom = 1.0
	shade.offset_right = 620
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(shade)

	_column = VBoxContainer.new()
	_column.anchor_top = 0.5
	_column.anchor_bottom = 0.5
	_column.offset_left = 64
	_column.offset_right = 64 + 380
	_column.grow_vertical = Control.GROW_DIRECTION_BOTH
	_column.add_theme_constant_override("separation", 10)
	_ui.add_child(_column)

	_column.add_child(MenuUI.label("Project", 28, Color(1, 1, 1, 0.8)))
	_column.add_child(MenuUI.title("Serotonin", 64))
	_column.add_child(MenuUI.spacer(24))
	_continue = MenuUI.button("", _on_continue, 24, true)
	_continue.custom_minimum_size = Vector2(0, 78)
	var lines := VBoxContainer.new()
	lines.set_anchors_preset(Control.PRESET_FULL_RECT)
	lines.offset_left = 18
	lines.alignment = BoxContainer.ALIGNMENT_CENTER
	lines.add_theme_constant_override("separation", 0)
	lines.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_continue_title = MenuUI.label("Continue", 28, MenuUI.ACCENT)
	_continue_sub = MenuUI.label("", 15, MenuUI.DIM)
	for l in [_continue_title, _continue_sub]:
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lines.add_child(l)
	_continue.add_child(lines)
	_column.add_child(_continue)
	_column.add_child(MenuUI.spacer(4))
	_column.add_child(MenuUI.button("Worlds", _open.bind(&"worlds"), 20))
	_column.add_child(MenuUI.button("Settings", _open.bind(&"settings"), 20))
	_column.add_child(MenuUI.button("Controls", _open.bind(&"controls"), 20))
	_column.add_child(MenuUI.button("Quit", func() -> void: get_tree().quit(), 20))

	_worlds = WorldsScreen.new()
	_worlds.anchor_left = 1.0
	_worlds.anchor_right = 1.0
	_worlds.anchor_bottom = 1.0
	_worlds.offset_left = -680
	_worlds.offset_right = -40
	_worlds.offset_top = 40
	_worlds.offset_bottom = -40
	_worlds.new_world_requested.connect(_new_world)
	_controls = ControlsScreen.new()
	_controls.anchor_left = 1.0
	_controls.anchor_right = 1.0
	_controls.offset_left = -680
	_controls.offset_right = -40
	_controls.offset_top = 40
	_settings = SettingsScreen.new()
	_settings.anchor_left = 1.0
	_settings.anchor_right = 1.0
	_settings.anchor_bottom = 1.0
	_settings.offset_left = -680
	_settings.offset_right = -40
	_settings.offset_top = 40
	_settings.offset_bottom = -40
	for screen: Control in [_worlds, _controls, _settings]:
		screen.visible = false
		screen.closed.connect(_close_screens)
		_ui.add_child(screen)


## Continue: the world played last, its name and playtime underneath; Play on a first launch.
func _refresh_continue() -> void:
	var id := Worlds.last_played()
	if id.is_empty():
		_continue_title.text = "Play"
		_continue_sub.text = "Hearthvale, the hand-built valley"
		return
	var m := Worlds.meta(id)
	_continue_title.text = "Continue"
	_continue_sub.text = "%s · %s played" % [m.get("name", id), MenuUI.duration(float(m.get("playtime", 0.0)))]


func _on_continue() -> void:
	var id := Worlds.last_played()
	Worlds.play(id if not id.is_empty() else Worlds.CLASSIC)


## One screen on the right at a time: &"worlds", &"settings" or &"controls".
func _open(screen: StringName) -> void:
	if screen == &"worlds":
		_worlds.refresh()
	_worlds.visible = screen == &"worlds"
	_controls.visible = screen == &"controls"
	_settings.visible = screen == &"settings"


func _close_screens() -> void:
	_worlds.visible = false
	_controls.visible = false
	_settings.visible = false
	_continue.grab_focus()


## Until the New World screen: a world on a random seed, picked in the list.
func _new_world() -> void:
	var settings := WorldSettings.defaults()
	settings["seed"] = ProcgenMap.random_seed()
	var id := Worlds.create("World %d" % settings["seed"], settings)
	_worlds.refresh(id)
