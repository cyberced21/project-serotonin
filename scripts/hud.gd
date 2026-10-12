extends CanvasLayer
## Inventory counters (top-left) that pop when they change, a controls hint, a context XP bar
## (bottom-centre) for the skill you just trained, and a level-up banner.

const ITEMS := [
	[&"wood", preload("res://art/item_wood.png")],
	[&"ore", preload("res://art/item_ore.png")],
]
const LEVEL_UP_SFX := preload("res://audio/level_up.wav")

## Item icons are 8 px pixel art, drawn at this scale with nearest filtering.
const ICON_SCALE := 4.0
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


func _ready() -> void:
	var icon_size := 8.0 * ICON_SCALE
	var y := 16.0
	for entry in ITEMS:
		var id: StringName = entry[0]
		var row := Control.new()
		row.position = Vector2(16, y)
		row.size = Vector2(160, icon_size)
		row.pivot_offset = Vector2(icon_size / 2.0, icon_size / 2.0)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(row)
		var icon := TextureRect.new()
		icon.texture = entry[1]
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.size = Vector2(icon_size, icon_size)
		row.add_child(icon)
		var label := _make_label(28)
		label.position = Vector2(icon_size + 10, -4)
		label.text = str(Inventory.count(id))  # may be non-zero after loading a save
		row.add_child(label)
		_labels[id] = label
		_rows[id] = row
		y += icon_size + 10

	var hint := _make_label(16)
	hint.text = "WASD move  ·  SHIFT sprint  ·  SPACE jump / mantle  ·  CTRL crouch / slide  ·  hold E / click gather  ·  ESC free mouse"
	hint.modulate = Color(1, 1, 1, 0.7)
	add_child(hint)
	hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_KEEP_SIZE, 16)
	hint.grow_vertical = Control.GROW_DIRECTION_BEGIN  # grows upward from the bottom edge

	_build_xp_bar()
	_build_banner()

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


func _on_changed(item: StringName, count: int) -> void:
	if not _labels.has(item):
		return
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
