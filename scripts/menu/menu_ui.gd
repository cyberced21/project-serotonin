class_name MenuUI
extends RefCounted
## The menus' shared look (main menu, worlds, pause, settings): warm dark panels, wood-brown
## buttons and a gold accent, like the debug menu and the upgrade panel. Static builders only.

const BG := Color(0.09, 0.075, 0.06, 0.92)
const CARD := Color(0.14, 0.11, 0.085, 0.95)
const CARD_SELECTED := Color(0.24, 0.17, 0.11, 0.98)
const BORDER := Color("8a6142")
const ACCENT := Color("ffd27a")
const GOOD := Color("9be27a")
const WARN := Color("ff8a7a")
const DIM := Color(1, 1, 1, 0.62)
const BUTTON := Color("5f4029")
const BUTTON_HOVER := Color("7a5536")
const BUTTON_PRESSED := Color("4a3220")
const BUTTON_DISABLED := Color(0.25, 0.2, 0.16, 0.6)


## Places `c` over `area`, a share of its parent (0..1 on each side: x, y, width, height), so it
## grows and shrinks with the window instead of sitting at a fixed size. With `fit_height`, only
## the top is placed and it's as tall as its content, centred on `area`'s middle.
static func place(c: Control, area: Rect2, fit_height := false) -> void:
	c.anchor_left = area.position.x
	c.anchor_right = area.end.x
	c.offset_left = 0.0
	c.offset_right = 0.0
	if fit_height:
		c.anchor_top = area.get_center().y
		c.anchor_bottom = area.get_center().y
		c.offset_top = 0.0
		c.offset_bottom = 0.0
		c.grow_vertical = Control.GROW_DIRECTION_BOTH
	else:
		c.anchor_top = area.position.y
		c.anchor_bottom = area.end.y
		c.offset_top = 0.0
		c.offset_bottom = 0.0


## A vertical scroll area that takes the room it's given (for a panel's list that can outgrow it).
static func scroll(content: Control) -> ScrollContainer:
	var s := ScrollContainer.new()
	s.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	s.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.add_child(content)
	return s


static func panel(padding := 18.0, color := BG) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", box(color, padding, BORDER))
	return p


static func box(color: Color, padding := 10.0, border := Color.TRANSPARENT, radius := 10) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.set_corner_radius_all(radius)
	s.set_content_margin_all(padding)
	if border.a > 0.0:
		s.border_color = border
		s.set_border_width_all(2)
	return s


static func label(text: String, font_size := 16, color := Color.WHITE) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 2)
	return l


static func title(text: String, font_size := 26) -> Label:
	return label(text, font_size, ACCENT)


## A menu button. `big` is the main menu's Continue: taller, gold text.
static func button(text: String, on_press: Callable, font_size := 18, big := false) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", font_size)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT if big else HORIZONTAL_ALIGNMENT_CENTER
	var pad := 14.0 if big else 8.0
	b.add_theme_stylebox_override("normal", box(BUTTON, pad, BORDER if big else Color.TRANSPARENT, 7))
	b.add_theme_stylebox_override("hover", box(BUTTON_HOVER, pad, ACCENT if big else Color.TRANSPARENT, 7))
	b.add_theme_stylebox_override("pressed", box(BUTTON_PRESSED, pad, Color.TRANSPARENT, 7))
	b.add_theme_stylebox_override("disabled", box(BUTTON_DISABLED, pad, Color.TRANSPARENT, 7))
	b.add_theme_stylebox_override("focus", box(Color.TRANSPARENT, pad, ACCENT, 7))
	if big:
		b.add_theme_color_override("font_color", ACCENT)
		b.add_theme_color_override("font_hover_color", ACCENT)
	b.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 0.35))
	b.pressed.connect(on_press)
	return b


## A check box that shows on the dark panels: a bordered square, gold-filled when on.
static func check_box(text: String, font_size := 17) -> CheckBox:
	var c := CheckBox.new()
	c.text = text
	c.add_theme_font_size_override("font_size", font_size)
	c.add_theme_icon_override("unchecked", _check_icon(false))
	c.add_theme_icon_override("checked", _check_icon(true))
	c.add_theme_icon_override("unchecked_disabled", _check_icon(false))
	c.add_theme_icon_override("checked_disabled", _check_icon(true))
	return c


static var _check_icons: Dictionary[bool, Texture2D] = {}


static func _check_icon(on: bool) -> Texture2D:
	if _check_icons.has(on):
		return _check_icons[on]
	const N := 20
	var img := Image.create_empty(N, N, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0.35))
	for i in N:
		for t in 2:
			for p in [Vector2i(i, t), Vector2i(i, N - 1 - t), Vector2i(t, i), Vector2i(N - 1 - t, i)]:
				img.set_pixelv(p, BORDER.lightened(0.2))
	if on:
		img.fill_rect(Rect2i(5, 5, N - 10, N - 10), ACCENT)
	_check_icons[on] = ImageTexture.create_from_image(img)
	return _check_icons[on]


static func line_edit(placeholder: String, font_size := 17) -> LineEdit:
	var e := LineEdit.new()
	e.placeholder_text = placeholder
	e.add_theme_font_size_override("font_size", font_size)
	e.add_theme_stylebox_override("normal", box(Color(0, 0, 0, 0.35), 8.0, BORDER, 6))
	e.add_theme_stylebox_override("focus", box(Color(0, 0, 0, 0.35), 8.0, ACCENT, 6))
	return e


static func spacer(height: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, height)
	return c


## "3 h 12 m", "14 m", "under a minute".
static func duration(seconds: float) -> String:
	var m := int(seconds / 60.0)
	if m < 1:
		return "under a minute"
	if m < 60:
		return "%d m" % m
	return "%d h %d m" % [m / 60, m % 60]


## "just now", "5 minutes ago", "yesterday", "12 Oct".
static func ago(unix: float) -> String:
	if unix <= 0.0:
		return "never"
	var s := Time.get_unix_time_from_system() - unix
	if s < 90.0:
		return "just now"
	if s < 3600.0:
		return "%d minutes ago" % int(s / 60.0)
	if s < 86400.0:
		var h := int(s / 3600.0)
		return "an hour ago" if h == 1 else "%d hours ago" % h
	if s < 2.0 * 86400.0:
		return "yesterday"
	if s < 7.0 * 86400.0:
		return "%d days ago" % int(s / 86400.0)
	var d := Time.get_datetime_dict_from_unix_time(int(unix))
	const MONTHS := ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
	return "%d %s" % [d["day"], MONTHS[int(d["month"]) - 1]]


## A world's one-line description.
static func world_kind(_m: Dictionary) -> String:
	return "The valley of Hearthvale"
