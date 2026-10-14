class_name UpgradePanel
extends CanvasLayer
## The panel a villager opens when you talk to them (E): their name and a line of chatter, the
## building's next tier with its cost (have / need per item, red or green), and an Upgrade
## button that's live only when you can afford it and the town hall allows it.
## Frees the mouse while open. Closes on E, Esc, clicking outside it, or walking away.
## Upgrading closes it so you can watch the building go up.

const OPEN_SFX := preload("res://audio/pickup.tres")
const WIDTH := 460.0
const ICON_SIZE := 34.0
## Walk further than this from the villager and the panel closes.
const CLOSE_DISTANCE := 4.5
const HAVE_COLOR := Color("9be27a")
const NEED_COLOR := Color("ff8a7a")
const DIM := Color(1, 1, 1, 0.6)
const ACCENT := Color("ffd27a")
const PERK_COLOR := Color("a9d8ff")

var villager: Villager
var _closed_msec := -100000

var _panel: PanelContainer
var _name: Label
var _role: Label
var _line: Label
var _next: Label
var _perks_now: Label
var _perks_next: Label
var _costs: GridContainer
var _button: Button
var _status: Label


func _ready() -> void:
	add_to_group("upgrade_panel")
	layer = 3
	_build()
	_panel.visible = false
	Inventory.changed.connect(func(_i: StringName, _c: int) -> void: _refresh())
	Village.tier_changed.connect(func(_id: StringName, _t: int) -> void: _refresh())


func is_open() -> bool:
	return villager != null


## True for a moment after closing, so the same E press doesn't reopen it.
func just_closed() -> bool:
	return Time.get_ticks_msec() - _closed_msec < 250


func open(v: Villager) -> void:
	villager = v
	var def := v.building.def
	_name.text = def.villager_name
	_line.text = "“%s”" % _pick_line()
	_refresh()
	_panel.visible = true
	_panel.pivot_offset = _panel.size / 2.0
	_panel.scale = Vector2(0.85, 0.85)
	_panel.modulate.a = 0.0
	var t := create_tween().set_parallel()
	t.tween_property(_panel, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(_panel, "modulate:a", 1.0, 0.12)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Sfx.play(OPEN_SFX, 0.75, -8.0)


func close() -> void:
	if villager == null:
		return
	villager = null
	_closed_msec = Time.get_ticks_msec()
	_panel.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _input(event: InputEvent) -> void:
	if villager == null:
		return
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("interact"):
		close()
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if villager == null:
		return
	# clicking outside the panel recaptures the mouse (player.gd) — that means "done"
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		close()
		return
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if not is_instance_valid(villager) or (player and player.global_position.distance_to(villager.global_position) > CLOSE_DISTANCE):
		close()


func _pick_line() -> String:
	var def := villager.building.def
	if Village.is_capped(def.id):
		return def.capped_line
	if DayNight.is_night() and not def.night_lines.is_empty():
		return def.night_lines[randi() % def.night_lines.size()]
	var tier := def.get_tier(Village.tier(def.id))
	if tier and not tier.lines.is_empty():
		return tier.lines[randi() % tier.lines.size()]
	return "..."


func _refresh() -> void:
	if villager == null:
		return
	var def := villager.building.def
	var tier_now := Village.tier(def.id)
	var current := def.get_tier(tier_now)
	_role.text = "%s  ·  %s  ·  %s" % [def.villager_role, def.display_name, current.name if current else "?"]
	_perks_now.text = _perk_lines(current, "Now: ")
	_perks_now.visible = not _perks_now.text.is_empty()
	for c in _costs.get_children():
		c.queue_free()
	var next := Village.next_tier(def.id)
	if next == null:
		_next.text = "Fully upgraded!"
		_next.add_theme_color_override("font_color", HAVE_COLOR)
		_perks_next.visible = false
		_costs.visible = false
		_button.visible = false
		_status.text = ""
		return
	_next.text = "Next: %s  (tier %d of %d)" % [next.name, tier_now + 1, def.max_tier()]
	_next.add_theme_color_override("font_color", ACCENT)
	_perks_next.text = _perk_lines(next, "+ ", current)
	_perks_next.visible = not _perks_next.text.is_empty()
	_costs.visible = true
	_button.visible = true
	var ids := next.cost.keys()
	ids.sort_custom(func(a: StringName, b: StringName) -> bool: return Items.order(a) < Items.order(b))
	for item in ids:
		var need: int = next.cost[item]
		var have := Inventory.count(item)
		var icon := TextureRect.new()
		icon.texture = Items.icon(item)
		icon.custom_minimum_size = Vector2(ICON_SIZE, ICON_SIZE)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.tooltip_text = Items.display_name(item)
		_costs.add_child(icon)
		var label := _label(20)
		label.text = "%d / %d  %s" % [mini(have, need), need, Items.display_name(item)]
		label.add_theme_color_override("font_color", HAVE_COLOR if have >= need else NEED_COLOR)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_costs.add_child(label)
	var capped := Village.is_capped(def.id)
	_button.disabled = not Village.can_upgrade(def.id)
	_button.text = "Upgrade to %s" % next.name
	if capped:
		var hall := Village.get_def(Village.TOWN_HALL)
		_status.text = "Upgrade the %s first." % (hall.display_name if hall else "Town Hall")
	elif not Inventory.has_all(next.cost):
		_status.text = "Not enough resources yet."
	else:
		_status.text = ""


## The tier's perks, one per line; with `except`, only the ones that tier doesn't already give.
func _perk_lines(tier: BuildingTier, prefix: String, except: BuildingTier = null) -> String:
	if tier == null:
		return ""
	var have := PackedStringArray()
	if except:
		for e in except.effects:
			have.append(e.text)
	var lines := PackedStringArray()
	for e in tier.effects:
		if not e.text.is_empty() and not e.text in have:
			lines.append("%s%s" % [prefix, e.text])
	return "\n".join(lines)


func _on_upgrade_pressed() -> void:
	if villager == null:
		return
	var id := villager.building.def.id
	if Village.upgrade(id):
		close()  # step back and watch it go up


# --- layout ---------------------------------------------------------------------------------

func _build() -> void:
	_panel = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.09, 0.075, 0.06, 0.92)
	style.border_color = Color("8a6142")
	style.set_border_width_all(2)
	style.set_corner_radius_all(10)
	style.set_content_margin_all(20)
	_panel.add_theme_stylebox_override("panel", style)
	_panel.custom_minimum_size = Vector2(WIDTH, 0)
	_panel.anchor_left = 0.5
	_panel.anchor_right = 0.5
	_panel.anchor_top = 0.5
	_panel.anchor_bottom = 0.5
	_panel.offset_left = 60
	_panel.offset_right = 60 + WIDTH
	_panel.offset_top = -170
	_panel.grow_vertical = Control.GROW_DIRECTION_END
	add_child(_panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	_panel.add_child(box)

	_name = _label(30)
	_name.add_theme_color_override("font_color", ACCENT)
	box.add_child(_name)
	_role = _label(15)
	_role.modulate = DIM
	box.add_child(_role)
	_line = _label(19)
	_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_line.custom_minimum_size = Vector2(WIDTH - 40, 0)
	box.add_child(_line)

	_perks_now = _label(16)
	_perks_now.add_theme_color_override("font_color", HAVE_COLOR)
	box.add_child(_perks_now)

	box.add_child(HSeparator.new())
	_next = _label(21)
	box.add_child(_next)
	_perks_next = _label(17)
	_perks_next.add_theme_color_override("font_color", PERK_COLOR)
	box.add_child(_perks_next)
	_costs = GridContainer.new()
	_costs.columns = 2
	_costs.add_theme_constant_override("h_separation", 12)
	_costs.add_theme_constant_override("v_separation", 6)
	box.add_child(_costs)

	_button = Button.new()
	_button.add_theme_font_size_override("font_size", 20)
	_button.custom_minimum_size = Vector2(0, 44)
	_button.focus_mode = Control.FOCUS_NONE
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color("3f7f45")
	normal.set_corner_radius_all(6)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color("4f9452")
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Color("356a3b")
	var disabled := normal.duplicate() as StyleBoxFlat
	disabled.bg_color = Color(0.3, 0.3, 0.3, 0.6)
	_button.add_theme_stylebox_override("normal", normal)
	_button.add_theme_stylebox_override("hover", hover)
	_button.add_theme_stylebox_override("pressed", pressed)
	_button.add_theme_stylebox_override("disabled", disabled)
	_button.pressed.connect(_on_upgrade_pressed)
	box.add_child(_button)
	_status = _label(16)
	_status.add_theme_color_override("font_color", NEED_COLOR)
	box.add_child(_status)

	var hint := _label(14)
	hint.text = "E / Esc  close"
	hint.modulate = DIM
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	box.add_child(hint)


func _label(font_size: int) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 2)
	return label
