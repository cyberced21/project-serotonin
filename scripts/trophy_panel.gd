class_name TrophyPanel
extends CanvasLayer
## The little panel for a place on your wall (plans/trophies.md, TrophyPlaque): what's hung there
## with its label and Take down, then the trophies you're carrying that fit, each with Hang (or
## Swap). Frees the mouse while open; closes on E, Esc, clicking outside it, or walking away.

const CLOSE_DISTANCE := 4.0

var plaque: TrophyPlaque
var _panel: PanelContainer
var _box: VBoxContainer
var _closed_msec := -100000


func _ready() -> void:
	layer = 12
	add_to_group("trophy_panel")
	add_to_group("modal_panel")
	_panel = MenuUI.panel(18.0)
	MenuUI.place(_panel, Rect2(0.6, 0.18, 0.34, 0.64))
	add_child(_panel)
	var scroll_box := VBoxContainer.new()
	_panel.add_child(MenuUI.scroll(scroll_box))
	_box = scroll_box
	_box.add_theme_constant_override("separation", 8)
	_panel.visible = false


func is_open() -> bool:
	return plaque != null


func just_closed() -> bool:
	return Time.get_ticks_msec() - _closed_msec < 250


func open(p: TrophyPlaque) -> void:
	if just_closed():
		return
	plaque = p
	_refresh()
	_panel.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Sfx.play_ui(&"open")


func close() -> void:
	if plaque == null:
		return
	plaque = null
	_closed_msec = Time.get_ticks_msec()
	_panel.visible = false
	Sfx.play_ui(&"close")
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _input(event: InputEvent) -> void:
	if plaque and (event.is_action_pressed("ui_cancel") or event.is_action_pressed("interact")):
		close()
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if plaque == null:
		return
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED or not is_instance_valid(plaque) \
			or (player and player.global_position.distance_to(plaque.global_position) > CLOSE_DISTANCE):
		close()


func _refresh() -> void:
	for c in _box.get_children():
		c.queue_free()
	var here := plaque.hung()
	_box.add_child(MenuUI.title("The mantel" if plaque.small_only else "Your trophy wall", 24))
	if not here.is_empty():
		_box.add_child(MenuUI.label(Trophies.label(here), 18, Trophies.FOUND_COLOR))
		_box.add_child(MenuUI.button("Take it down", take_down, 17))
		_box.add_child(HSeparator.new())
	var fits := Trophies.fitting(plaque.small_only)
	if fits.is_empty():
		_box.add_child(MenuUI.label("Nothing else to hang here yet." if not here.is_empty()
				else "Nothing to hang yet: trophies turn up out in the world.", 16))
		return
	_box.add_child(MenuUI.label("Carried home:", 16))
	for r in fits:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var l := MenuUI.label(Trophies.label(r), 16)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.add_child(l)
		row.add_child(MenuUI.button("Swap" if not here.is_empty() else "Hang", hang.bind(r), 16))
		_box.add_child(row)


## Hang `r` here (whatever was here goes back in your pack).
func hang(r: Dictionary) -> void:
	var was := plaque.hung()
	Trophies.take(r)
	if not was.is_empty():
		Trophies.give_back(was)
	Trophies.hang(plaque.place, r)
	Sfx.play_ui(&"click", 0.7)  # (a little wooden knock)
	close()


func take_down() -> void:
	var was := plaque.hung()
	Trophies.hang(plaque.place, {})
	Trophies.give_back(was)
	close()
