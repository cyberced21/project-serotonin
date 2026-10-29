class_name MineMap
extends CanvasLayer
## M in the mine (plans/mine.md): the level you're on, drawn on a sheet of parchment: the cells
## you've opened inked in, the rest of the rock blank; the way out, the lift and the rail stop
## marked, the roof fall and the flood while they're in the way; an arrow for you. Pauses the
## game while it's open, like the world map (which stands aside down here); M or Esc closes it.
## With the prospector's survey board (an add-on), the cells next to what's open show their ore.

const PAPER := Color(0.93, 0.87, 0.73)
const INK := Color(0.32, 0.22, 0.13)
const FILL := Color(0.78, 0.68, 0.5)
const FRESH := Color(0.86, 0.77, 0.58)
const WOOD := Color(0.24, 0.15, 0.08, 0.98)
const MARK := {"E": "↑", "L": "≡", "R": "═", "X": "✕", "F": "≈", "S": "~", "K": "◆"}

var mine: Mine
var _shade: ColorRect
var _sheet: Control
var _title: Label


func _ready() -> void:
	layer = 14
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("mine_map")
	_shade = ColorRect.new()
	_shade.color = Color(0, 0, 0, 0.55)
	_shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_shade)
	var frame := PanelContainer.new()
	var box := StyleBoxFlat.new()
	box.bg_color = WOOD
	box.set_corner_radius_all(6)
	box.set_content_margin_all(14)
	frame.add_theme_stylebox_override("panel", box)
	frame.set_anchors_preset(Control.PRESET_CENTER)
	_shade.add_child(frame)
	var col := VBoxContainer.new()
	frame.add_child(col)
	_title = Label.new()
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", 26)
	_title.add_theme_color_override("font_color", Color(1.0, 0.86, 0.55))
	col.add_child(_title)
	_sheet = Control.new()
	_sheet.custom_minimum_size = Vector2(560, 480)
	_sheet.draw.connect(_draw_sheet)
	col.add_child(_sheet)
	var hint := Label.new()
	hint.text = "M or Esc to put it away"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_color_override("font_color", Color(0.85, 0.75, 0.6))
	col.add_child(hint)
	frame.resized.connect(func() -> void: frame.position = -frame.size / 2)
	_shade.visible = false


func is_open() -> bool:
	return _shade.visible


func open() -> void:
	if is_open() or get_tree().paused or mine.here < 0:
		return
	_title.text = "%s · %s" % [MineLayout.LEVELS[mine.here]["title"], "The Old Greystone Mine"]
	_shade.visible = true
	Sfx.play_ui(&"map")
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_sheet.queue_redraw()


func close() -> void:
	if not is_open():
		return
	_shade.visible = false
	Sfx.play_ui(&"map", 0.85)
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _input(event: InputEvent) -> void:
	if mine == null or (mine.here < 0 and not is_open()):
		return
	if event.is_action_pressed("map"):
		if is_open():
			close()
		elif not Worlds.current.is_empty():
			open()
		get_viewport().set_input_as_handled()
	elif is_open() and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


## The cell size and corner the level's drawn at, to fit the sheet.
func _layout() -> Array:
	var size := MineLayout.size(mine.here)
	var s := floorf(minf(_sheet.size.x / (size.x + 1), _sheet.size.y / (size.y + 1)))
	var corner := (_sheet.size - Vector2(size) * s) / 2
	return [s, corner]


func _draw_sheet() -> void:
	if mine == null or mine.here < 0:
		return
	var n := mine.here
	_sheet.draw_rect(Rect2(Vector2.ZERO, _sheet.size), PAPER)
	var l := _layout()
	var s: float = l[0]
	var corner: Vector2 = l[1]
	var font := ThemeDB.fallback_font
	var survey := Village.stat(&"mine_survey") > 0.0
	for c in MineLayout.cells(n):
		var r := Rect2(corner + Vector2(c) * s, Vector2(s, s))
		if mine.is_open(n, c):
			_sheet.draw_rect(r.grow(-1), FRESH if mine.is_fresh(n, c) else FILL)
			for d in MineLayout.DIRS:  # ink where it meets rock
				if not mine.is_open(n, c + d):
					var a := r.get_center() + Vector2(d) * s / 2 + Vector2(-d.y, d.x) * s / 2
					var b := r.get_center() + Vector2(d) * s / 2 - Vector2(-d.y, d.x) * s / 2
					_sheet.draw_line(a, b, INK, 2.0)
			var k := MineLayout.at(n, c)
			if MARK.has(k) and (k not in ["X", "F"] or not mine.is_passable(n, c)):
				_sheet.draw_string(font, r.get_center() + Vector2(-s * 0.2, s * 0.15), MARK[k],
					HORIZONTAL_ALIGNMENT_CENTER, s * 0.4, int(s * 0.45), INK)
		elif survey and _next_to_open(n, c):  # the survey board: what's behind the faces
			_sheet.draw_string(font, r.get_center() + Vector2(-s * 0.3, s * 0.1), mine.ore_hint(n, c),
				HORIZONTAL_ALIGNMENT_CENTER, s * 0.6, int(s * 0.22), INK.lerp(PAPER, 0.4))
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player:
		var local := mine.levels[n].to_local(player.global_position)
		var at := corner + Vector2(local.x, local.z) / MineLayout.CELL * s
		var fwd := -player.global_basis.z
		var ang := atan2(fwd.z, fwd.x)
		var pts := PackedVector2Array([at + Vector2.from_angle(ang) * s * 0.3,
			at + Vector2.from_angle(ang + 2.5) * s * 0.2, at + Vector2.from_angle(ang - 2.5) * s * 0.2])
		_sheet.draw_colored_polygon(pts, Color(0.7, 0.15, 0.1))


func _next_to_open(n: int, c: Vector2i) -> bool:
	for d in MineLayout.DIRS:
		if mine.is_passable(n, c + d):
			return true
	return false
