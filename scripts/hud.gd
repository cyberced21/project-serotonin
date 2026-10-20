extends CanvasLayer
## Inventory counters (top-left, one row per item you hold, in Items order) that pop when they
## change, a controls hint, a context XP bar (bottom-centre) for the skill you just trained, and
## a level-up banner, and the time of day (top-right).

const LEVEL_UP_SFX := preload("res://audio/level_up.wav")

const ICON_SIZE := 40.0
const ROW_GAP := 6.0
const BAR_WIDTH := 320.0
## Distance from the bottom of the screen to the XP bar.
const BAR_BOTTOM := 90.0
const BAR_LINGER := 3.0

var _labels: Dictionary[StringName, Label] = {}
var _rows: Dictionary[StringName, Control] = {}

var _xp_panel: Control
var _xp_label: Label
var _xp_fill: ColorRect
var _xp_skill: StringName = &""
var _xp_level := 0
var _xp_fade_tween: Tween
var _xp_fill_tween: Tween

var _banner: Label
var _banner_tween: Tween

var _clock: Label


func _ready() -> void:
	for id in Inventory.items:  # rows for anything already held after loading a save
		if Inventory.count(id) > 0:
			_add_row(id)

	var hint := _make_label(16)
	hint.text = "WASD move  ·  SHIFT sprint  ·  SPACE jump / mantle  ·  CTRL crouch / slide  ·  hold E / click gather, spear or cast  ·  RMB bow  ·  E talk  ·  ESC free mouse"
	hint.modulate = Color(1, 1, 1, 0.7)
	add_child(hint)
	hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_KEEP_SIZE, 16)
	hint.grow_vertical = Control.GROW_DIRECTION_BEGIN  # grows upward from the bottom edge

	_build_xp_bar()
	_build_banner()
	_build_clock()

	Inventory.changed.connect(_on_changed)
	Skills.xp_gained.connect(_on_xp_gained)
	Skills.leveled_up.connect(_on_leveled_up)


func _make_label(font_size: int) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	label.add_theme_constant_override("shadow_offset_x", 2)
	label.add_theme_constant_override("shadow_offset_y", 2)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _build_xp_bar() -> void:
	_xp_panel = Control.new()
	_xp_panel.anchor_left = 0.5
	_xp_panel.anchor_right = 0.5
	_xp_panel.anchor_top = 1.0
	_xp_panel.anchor_bottom = 1.0
	_xp_panel.offset_left = -BAR_WIDTH / 2.0
	_xp_panel.offset_right = BAR_WIDTH / 2.0
	_xp_panel.offset_top = -BAR_BOTTOM
	_xp_panel.offset_bottom = -BAR_BOTTOM + 44
	_xp_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_xp_panel.modulate.a = 0.0
	add_child(_xp_panel)

	_xp_label = _make_label(22)
	_xp_label.size = Vector2(BAR_WIDTH, 30)
	_xp_label.position = Vector2(0, -4)
	_xp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_xp_panel.add_child(_xp_label)

	var back := ColorRect.new()
	back.color = Color(0, 0, 0, 0.55)
	back.position = Vector2(0, 30)
	back.size = Vector2(BAR_WIDTH, 12)
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_xp_panel.add_child(back)

	_xp_fill = ColorRect.new()
	_xp_fill.position = Vector2(2, 32)
	_xp_fill.size = Vector2(0, 8)
	_xp_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_xp_panel.add_child(_xp_fill)


func _build_clock() -> void:
	_clock = _make_label(22)
	_clock.modulate = Color(1, 1, 1, 0.85)
	_clock.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(_clock)
	_clock.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_KEEP_SIZE, 16)
	_clock.grow_horizontal = Control.GROW_DIRECTION_BEGIN


func _process(_delta: float) -> void:
	var text := "%s  %s" % [DayNight.part_of_day(), DayNight.clock_text()]
	if _clock.text != text:
		_clock.text = text


func _build_banner() -> void:
	_banner = _make_label(56)
	_banner.anchor_right = 1.0
	_banner.anchor_top = 0.25
	_banner.anchor_bottom = 0.25
	_banner.offset_bottom = 80
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.resized.connect(func() -> void: _banner.pivot_offset = _banner.size / 2.0)
	_banner.add_theme_constant_override("shadow_offset_x", 3)
	_banner.add_theme_constant_override("shadow_offset_y", 4)
	_banner.modulate.a = 0.0
	add_child(_banner)


func _add_row(id: StringName) -> void:
	var row := Control.new()
	row.size = Vector2(200, ICON_SIZE)
	row.pivot_offset = Vector2(ICON_SIZE / 2.0, ICON_SIZE / 2.0)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(row)
	var icon := TextureRect.new()
	icon.texture = Items.icon(id)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.size = Vector2(ICON_SIZE, ICON_SIZE)
	icon.tooltip_text = Items.display_name(id)
	row.add_child(icon)
	var label := _make_label(28)
	label.position = Vector2(ICON_SIZE + 10, 0)
	label.text = str(Inventory.count(id))
	row.add_child(label)
	_labels[id] = label
	_rows[id] = row
	_layout_rows()


## Stack the rows top-left in Items order.
func _layout_rows() -> void:
	var ids := _rows.keys()
	ids.sort_custom(func(a: StringName, b: StringName) -> bool: return Items.order(a) < Items.order(b))
	var y := 16.0
	for id in ids:
		_rows[id].position = Vector2(16, y)
		y += ICON_SIZE + ROW_GAP


func _on_changed(item: StringName, count: int) -> void:
	if not _labels.has(item):
		_add_row(item)
	_labels[item].text = str(count)
	var row := _rows[item]
	row.scale = Vector2(1.4, 1.4)
	create_tween().tween_property(row, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _on_xp_gained(skill: StringName, _amount: int, _total: int) -> void:
	var lvl := Skills.level(skill)
	var lvl_text := "max" if lvl >= Skills.MAX_LEVEL else str(lvl)
	_xp_label.text = "%s %s" % [Skills.display_name(skill), lvl_text]
	_xp_fill.color = Skills.color(skill)

	var width := roundf((BAR_WIDTH - 4) * Skills.progress(skill))
	if _xp_fill_tween:
		_xp_fill_tween.kill()
	if skill != _xp_skill or lvl != _xp_level:
		_xp_fill.size.x = width  # new skill or new level: snap instead of animating backwards
	else:
		_xp_fill_tween = create_tween()
		_xp_fill_tween.tween_property(_xp_fill, "size:x", width, 0.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_xp_skill = skill
	_xp_level = lvl

	# show, then fade out after a few seconds without XP
	if _xp_fade_tween:
		_xp_fade_tween.kill()
	_xp_panel.modulate.a = 1.0
	_xp_fade_tween = create_tween()
	_xp_fade_tween.tween_interval(BAR_LINGER)
	_xp_fade_tween.tween_property(_xp_panel, "modulate:a", 0.0, 0.4)


func _on_leveled_up(skill: StringName, lvl: int) -> void:
	_banner.text = "%s %d!" % [Skills.display_name(skill), lvl]
	_banner.add_theme_color_override("font_color", Skills.color(skill))
	if _banner_tween:
		_banner_tween.kill()
	_banner.modulate.a = 1.0
	_banner.scale = Vector2(0.3, 0.3)
	_banner_tween = create_tween()
	_banner_tween.tween_property(_banner, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_banner_tween.tween_interval(1.5)
	_banner_tween.tween_property(_banner, "modulate:a", 0.0, 0.4)
	Sfx.play(LEVEL_UP_SFX, 1.0, -3.0)
	Juice.shake(2.0)  # no hitstop: it would stack with the break hitstop and feel laggy
