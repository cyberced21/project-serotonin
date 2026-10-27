class_name WorldMapScreen
extends CanvasLayer
## M: the whole world on a sheet of parchment in a wooden frame (MapView with burnt edges and the
## biomes' names), the world's name across the top and the name of the place under the mouse
## along the bottom. Wheel zooms (toward the mouse), dragging pans, Space finds you again. Pauses
## the game while it's open; M or Esc closes it. Built by the HUD.

const ZOOM_STEP := 1.2
## Closest it zooms in (metres a pixel); the farthest shows the whole world.
const MIN_MPP := 0.25
const WOOD := Color(0.24, 0.15, 0.08, 0.98)
const BRONZE := Color(0.7, 0.52, 0.27)
const GOLD := Color(1.0, 0.86, 0.55)

var view: MapView
var _shade: ColorRect
var _frame: PanelContainer
var _title: Label
var _hover: Label
var _dragging := false
var _fitted := false  # zoomed to the whole world once the map was built


func _ready() -> void:
	layer = 14  # under the pause menu
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("world_map")
	_build()
	_shade.visible = false


func is_open() -> bool:
	return _shade.visible


func open() -> void:
	if is_open() or get_tree().paused:
		return
	_title.text = Worlds.current_meta.get("name", "The World") if not Worlds.current.is_empty() else "The World"
	_shade.visible = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_fitted = false
	await get_tree().process_frame  # (the frame's laid out: fit to its size)
	_fit()


func close() -> void:
	if not is_open():
		return
	_shade.visible = false
	_dragging = false
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("map"):
		if is_open():
			close()
		elif _can_open():
			open()
		get_viewport().set_input_as_handled()
	elif is_open() and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()
	elif is_open() and event is InputEventKey and event.pressed and (event as InputEventKey).keycode == KEY_SPACE:
		_center_on_player()
		get_viewport().set_input_as_handled()


func _can_open() -> bool:
	var tree := get_tree()
	if Worlds.current.is_empty() or tree.paused or tree.get_first_node_in_group("loading_screen") != null:
		return false
	var panel := tree.get_first_node_in_group("upgrade_panel") as UpgradePanel
	return not (panel and panel.is_open())


func _process(_delta: float) -> void:
	if not is_open():
		return
	if not _fitted and view.data and view.data.is_built:
		_fit()
	var mouse := view.get_local_mouse_position()
	_hover.text = _place_at(view.px_to_world(mouse)) if Rect2(Vector2.ZERO, view.size).has_point(mouse) else ""


## The whole world in the frame.
func _fit() -> void:
	var d := view.data
	if d == null or not d.is_built or view.size.x <= 0.0:
		return
	view.center = d.rect.get_center()
	view.metres_per_px = maxf(d.rect.size.x / view.size.x, d.rect.size.y / view.size.y) * 1.02
	view.label_size = clampi(roundi(view.size.y / 34.0), 14, 30)
	_fitted = true


func _max_mpp() -> float:
	var d := view.data
	if d == null or not d.is_built or view.size.x <= 0.0:
		return 4.0
	return maxf(d.rect.size.x / view.size.x, d.rect.size.y / view.size.y) * 1.3


func _center_on_player() -> void:
	var p := get_tree().get_first_node_in_group("player") as Node3D
	if p:
		view.center = Vector2(p.global_position.x, p.global_position.z)


## The name of the biome at a world point, for the line under the map.
func _place_at(p: Vector2) -> String:
	var d := view.data
	if d == null or not d.is_built:
		return ""
	var uv := d.uv_of(p)
	if uv.x < 0.0 or uv.y < 0.0 or uv.x >= 1.0 or uv.y >= 1.0:
		return ""
	var px := Vector2i(uv * Vector2(d.kinds.get_size()))
	var b := d.kinds.get_pixelv(px).g8
	return MapData.biome_name(d.biomes[b - 1]) if b > 0 and b <= d.biomes.size() else "The Wilds"


func _on_view_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and (mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN):
			var before := view.px_to_world(mb.position)
			var f := 1.0 / ZOOM_STEP if mb.button_index == MOUSE_BUTTON_WHEEL_UP else ZOOM_STEP
			view.metres_per_px = clampf(view.metres_per_px * f, MIN_MPP, _max_mpp())
			view.center += before - view.px_to_world(mb.position)  # zoom toward the mouse
			view.label_size = clampi(roundi(view.size.y / 34.0), 14, 30)
		elif mb.button_index == MOUSE_BUTTON_LEFT or mb.button_index == MOUSE_BUTTON_RIGHT:
			_dragging = mb.pressed
		view.accept_event()
	elif event is InputEventMouseMotion and _dragging:
		view.center -= (event as InputEventMouseMotion).relative * view.metres_per_px
		view.accept_event()


func _build() -> void:
	_shade = ColorRect.new()
	_shade.color = Color(0, 0, 0, 0.55)
	_shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_shade)

	_frame = PanelContainer.new()
	var wood := StyleBoxFlat.new()
	wood.bg_color = WOOD
	wood.border_color = BRONZE
	wood.set_border_width_all(3)
	wood.set_corner_radius_all(6)
	wood.set_content_margin_all(14)
	wood.shadow_color = Color(0, 0, 0, 0.6)
	wood.shadow_size = 18
	_frame.add_theme_stylebox_override("panel", wood)
	MenuUI.place(_frame, Rect2(0.04, 0.04, 0.92, 0.92))
	_shade.add_child(_frame)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	_frame.add_child(box)
	_title = _label(30)
	box.add_child(_title)

	var inner := PanelContainer.new()  # a thin bronze rule round the parchment
	var rule := StyleBoxFlat.new()
	rule.bg_color = Color(0, 0, 0, 0)
	rule.border_color = Color(BRONZE, 0.8)
	rule.set_border_width_all(2)
	rule.set_content_margin_all(2)
	inner.add_theme_stylebox_override("panel", rule)
	inner.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(inner)
	view = MapView.new()
	view.vignette = 1.0
	view.mouse_filter = Control.MOUSE_FILTER_STOP
	view.mouse_default_cursor_shape = Control.CURSOR_DRAG
	view.gui_input.connect(_on_view_input)
	inner.add_child(view)

	var foot := HBoxContainer.new()
	box.add_child(foot)
	_hover = _label(20)
	_hover.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_hover.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(_hover)
	var hint := MenuUI.label("Wheel zoom  ·  drag to pan  ·  Space: find me  ·  M / Esc close", 15, Color(GOLD, 0.7))
	foot.add_child(hint)


func _label(font_size: int) -> Label:
	var l := Label.new()
	l.add_theme_font_override("font", MapView.map_font(true))
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", GOLD)
	l.add_theme_color_override("font_outline_color", Color(0.1, 0.06, 0.02))
	l.add_theme_constant_override("outline_size", 6)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l
