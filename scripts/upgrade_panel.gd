class_name UpgradePanel
extends CanvasLayer
## The panel a villager opens when you talk to them (E): their name and a line of chatter, the
## building's next tier with its cost (have / need per item, red or green), and an Upgrade
## button that's live only when you can afford it and the town hall allows it.
## Frees the mouse while open. Closes on E, Esc, clicking outside it, or walking away.
## Upgrading closes it so you can watch the building go up.
## Greta's panel has a second tab, Forge: the next pick, axe, sickle, spear and rod (Tools.RECIPES), each with
## its cost and what it opens, greyed out until the smithy's tier allows it. Forging plays the
## forge moment (ForgeCutscene). A third tab, Talents, resets one skill's talent picks (respec,
## plans/levels.md L8): the first ever is free, after that it costs that skill's goods.

const WIDTH := 460.0
const ICON_SIZE := 34.0
## Walk further than this from the villager and the panel closes.
const CLOSE_DISTANCE := 4.5
const HAVE_COLOR := Color("9be27a")
const NEED_COLOR := Color("ff8a7a")
const DIM := Color(1, 1, 1, 0.6)
const ACCENT := Color("ffd27a")
const PERK_COLOR := Color("a9d8ff")

enum Tab { UPGRADE, FORGE, TALENTS }

## Who opened it: a Villager, or your home's plans (HomePlans). Anything with a `building`.
var villager: Node3D
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
var _tabs: HBoxContainer
var _tab_buttons: Array[Button] = []
var _upgrade_box: VBoxContainer
var _forge_box: VBoxContainer
var _talents_box: VBoxContainer
var _tab := Tab.UPGRADE


func _ready() -> void:
	add_to_group("upgrade_panel")
	add_to_group("modal_panel")
	layer = 3
	_build()
	_panel.visible = false
	Inventory.changed.connect(func(_i: StringName, _c: int) -> void: _refresh())
	Village.tier_changed.connect(func(_id: StringName, _t: int) -> void: _refresh())
	Tools.changed.connect(func(_t: StringName, _tier: int) -> void: _refresh())
	Skills.talents.changed.connect(func(_s: StringName) -> void: _refresh())


func is_open() -> bool:
	return villager != null


## True for a moment after closing, so the same E press doesn't reopen it.
func just_closed() -> bool:
	return Time.get_ticks_msec() - _closed_msec < 250


func open(v: Node3D) -> void:
	villager = v
	var def := _building().def
	_name.text = def.villager_name
	_line.text = "“%s”" % _pick_line()
	_tab = Tab.UPGRADE
	_refresh()
	_panel.visible = true
	_panel.pivot_offset = _panel.size / 2.0
	_panel.scale = Vector2(0.97, 0.97)
	_panel.modulate.a = 0.0
	var t := create_tween().set_parallel()
	t.tween_property(_panel, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	t.tween_property(_panel, "modulate:a", 1.0, 0.2)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Sfx.play_ui(&"open")


## The building whose upgrades this shows.
func _building() -> Building:
	return villager.get("building") as Building


func close() -> void:
	if villager == null:
		return
	villager = null
	_closed_msec = Time.get_ticks_msec()
	_panel.visible = false
	Sfx.play_ui(&"close")
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
	var def := _building().def
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
	var def := _building().def
	_tabs.visible = def.id == Tools.SMITHY
	if not _tabs.visible:
		_tab = Tab.UPGRADE
	for i in _tab_buttons.size():
		_tab_buttons[i].button_pressed = i == _tab
	_upgrade_box.visible = _tab == Tab.UPGRADE
	_forge_box.visible = _tab == Tab.FORGE
	_talents_box.visible = _tab == Tab.TALENTS
	if _tab == Tab.FORGE:
		_refresh_forge()
	elif _tab == Tab.TALENTS:
		_refresh_talents()
	var tier_now := Village.tier(def.id)
	var current := def.get_tier(tier_now)
	_role.text = "%s  ·  %s  ·  %s" % [def.villager_role, def.display_name, current.name if current else "?"]
	_perks_now.text = _perk_lines(current, "Now: ")
	_perks_now.visible = not _perks_now.text.is_empty()
	for c in _costs.get_children():
		c.queue_free()
	var next := Village.next_tier(def.id)
	_next.visible = def.max_tier() > 1  # homes with a single tier: just a chat
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
	_add_costs(_costs, next.cost)
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


## One row per item in `cost`: its icon, then have / need (green once there's enough).
func _add_costs(grid: GridContainer, cost: Dictionary) -> void:
	for item in _sorted(cost):
		var need: int = cost[item]
		var have := Inventory.count(item)
		grid.add_child(_icon(item, ICON_SIZE))
		var label := _label(20)
		label.text = "%d / %d  %s" % [mini(have, need), need, Items.display_name(item)]
		label.add_theme_color_override("font_color", HAVE_COLOR if have >= need else NEED_COLOR)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(label)


## The same on one line, compact (the Forge tab): icon, have/need, icon, have/need ...
func _add_cost_row(row: HBoxContainer, cost: Dictionary) -> void:
	for item in _sorted(cost):
		var need: int = cost[item]
		var have := Inventory.count(item)
		row.add_child(_icon(item, 26.0))
		var label := _label(16)
		label.text = "%d/%d" % [mini(have, need), need]
		label.add_theme_color_override("font_color", HAVE_COLOR if have >= need else NEED_COLOR)
		row.add_child(label)


func _sorted(cost: Dictionary) -> Array:
	var ids := cost.keys()
	ids.sort_custom(func(a: StringName, b: StringName) -> bool: return Items.order(a) < Items.order(b))
	return ids


func _icon(item: StringName, size: float) -> TextureRect:
	var icon := TextureRect.new()
	icon.texture = Items.icon(item)
	icon.custom_minimum_size = Vector2(size, size)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.tooltip_text = Items.display_name(item)
	return icon


## The Forge tab: for each tiered tool, the next one Greta can make (or that you have the best).
func _refresh_forge() -> void:
	for c in _forge_box.get_children():
		c.queue_free()
	# per tool: the next one and what it opens, then its costs in a row with the Forge button
	for tool in Tools.LADDER:
		var t := Tools.tier(tool)
		var recipe := Tools.next_recipe(tool)
		var head := HBoxContainer.new()  # the tool's icon (the next one, or yours once it's the best)
		head.add_theme_constant_override("separation", 8)
		_forge_box.add_child(head)
		head.add_child(_icon(StringName("tool_%s_%d" % [tool, mini(t + 1, Tools.max_tier(tool))]), 30.0))
		var title := _label(19)
		head.add_child(title)
		if recipe.is_empty():
			title.text = "%s: the finest there is" % Tools.display_name(tool, t)
			title.add_theme_color_override("font_color", HAVE_COLOR)
			_forge_box.add_child(HSeparator.new())
			continue
		title.text = "%s  ·  %s" % [Tools.display_name(tool, t + 1), recipe["opens"]]
		title.add_theme_color_override("font_color", ACCENT)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		_forge_box.add_child(row)
		if Tools.forge_unlocked(tool):
			_add_cost_row(row, recipe["cost"])
			var button := _make_button("Forge")
			button.custom_minimum_size = Vector2(96, 34)
			button.size_flags_horizontal = Control.SIZE_SHRINK_END | Control.SIZE_EXPAND
			button.add_theme_font_size_override("font_size", 17)
			button.disabled = not Tools.can_forge(tool)
			button.tooltip_text = "Forge the %s (yours: %s)" % [Tools.display_name(tool, t + 1), Tools.display_name(tool, t)]
			button.pressed.connect(_on_forge_pressed.bind(tool))
			row.add_child(button)
		else:
			var needs := Village.get_def(Tools.SMITHY).get_tier(Tools.smithy_needed(t + 1))
			var locked := _label(16)
			locked.text = "Needs the %s first" % (needs.name if needs else "next smithy")
			locked.add_theme_color_override("font_color", NEED_COLOR)
			row.add_child(locked)
		_forge_box.add_child(HSeparator.new())


func _on_forge_pressed(tool: StringName) -> void:
	if villager == null:
		return
	var greta := villager as Villager
	if Tools.forge(tool):
		close()
		ForgeCutscene.play(greta, tool)  # Greta makes it, then hands it over


## The Talents tab: per skill with picks, what you took, and the reset with its price.
func _refresh_talents() -> void:
	for c in _talents_box.get_children():
		c.queue_free()
	var talents := Skills.talents
	var any := false
	for skill in Skills.SKILLS:
		if talents.picked_count(skill) == 0:
			continue
		any = true
		var title := _label(19)
		title.text = Skills.display_name(skill)
		title.add_theme_color_override("font_color", Skills.color(skill))
		_talents_box.add_child(title)
		var names := PackedStringArray()
		for m in TalentDef.MILESTONES:
			var def := talents.picked(skill, m)
			if def:
				names.append(def.display_name)
		if talents.mastery.has(skill):
			names.append(talents.defs[talents.mastery[skill]].display_name)
		var picked := _label(16)
		picked.text = ", ".join(names)
		picked.modulate = DIM
		picked.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		picked.custom_minimum_size = Vector2(WIDTH - 40, 0)
		_talents_box.add_child(picked)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		_talents_box.add_child(row)
		var cost := talents.respec_cost(skill)
		if cost.is_empty():
			var free := _label(16)
			free.text = "Free, this once"
			free.add_theme_color_override("font_color", HAVE_COLOR)
			row.add_child(free)
		else:
			_add_cost_row(row, cost)
		var button := _make_button("Reset")
		button.custom_minimum_size = Vector2(96, 34)
		button.size_flags_horizontal = Control.SIZE_SHRINK_END | Control.SIZE_EXPAND
		button.add_theme_font_size_override("font_size", 17)
		button.disabled = not cost.is_empty() and not Inventory.has_all(cost)
		button.tooltip_text = "Forget %s's talents and choose again" % Skills.display_name(skill)
		button.pressed.connect(_on_respec_pressed.bind(skill))
		row.add_child(button)
		_talents_box.add_child(HSeparator.new())
	if not any:
		var none := _label(17)
		none.text = "No talents to reset yet: they come at level 10."
		none.modulate = DIM
		_talents_box.add_child(none)


func _on_respec_pressed(skill: StringName) -> void:
	if villager and Skills.talents.respec(skill, Inventory):
		close()  # the choices come up again once you're back on your feet (TalentCards)


func _show_tab(tab: Tab) -> void:
	_tab = tab
	_refresh()


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
	var id := _building().def.id
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
	# the right of the screen, a share of the window (MenuUI.place): the villager stays in view on
	# the left, and the longer tabs scroll instead of running off the bottom
	_panel.custom_minimum_size = Vector2(WIDTH, 0)
	MenuUI.place(_panel, Rect2(0.52, 0.06, 0.44, 0.88))
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

	_tabs = HBoxContainer.new()
	_tabs.add_theme_constant_override("separation", 8)
	_make_tab("Upgrade", Tab.UPGRADE)
	_make_tab("Forge", Tab.FORGE)
	_make_tab("Talents", Tab.TALENTS)
	box.add_child(_tabs)

	var tabs := VBoxContainer.new()  # whichever tab is open, in one scroll area
	box.add_child(MenuUI.scroll(tabs))
	_upgrade_box = VBoxContainer.new()
	_upgrade_box.add_theme_constant_override("separation", 10)
	tabs.add_child(_upgrade_box)
	_forge_box = VBoxContainer.new()
	_forge_box.add_theme_constant_override("separation", 6)
	tabs.add_child(_forge_box)
	_talents_box = VBoxContainer.new()
	_talents_box.add_theme_constant_override("separation", 6)
	tabs.add_child(_talents_box)

	_perks_now = _label(16)
	_perks_now.add_theme_color_override("font_color", HAVE_COLOR)
	_upgrade_box.add_child(_perks_now)

	_upgrade_box.add_child(HSeparator.new())
	_next = _label(21)
	_upgrade_box.add_child(_next)
	_perks_next = _label(17)
	_perks_next.add_theme_color_override("font_color", PERK_COLOR)
	_upgrade_box.add_child(_perks_next)
	_costs = _grid()
	_upgrade_box.add_child(_costs)

	_button = _make_button("")
	_button.pressed.connect(_on_upgrade_pressed)
	_upgrade_box.add_child(_button)
	_status = _label(16)
	_status.add_theme_color_override("font_color", NEED_COLOR)
	_upgrade_box.add_child(_status)

	var hint := _label(14)
	hint.text = "E / Esc  close"
	hint.modulate = DIM
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	box.add_child(hint)


func _grid() -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 6)
	return grid


## A green action button (Upgrade, Forge), greyed out when disabled.
func _make_button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.add_theme_font_size_override("font_size", 20)
	button.custom_minimum_size = Vector2(0, 44)
	button.focus_mode = Control.FOCUS_NONE
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color("3f7f45")
	normal.set_corner_radius_all(6)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color("4f9452")
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Color("356a3b")
	var disabled := normal.duplicate() as StyleBoxFlat
	disabled.bg_color = Color(0.3, 0.3, 0.3, 0.6)
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_stylebox_override("disabled", disabled)
	return button


## A tab toggle (Upgrade / Forge / Talents) on Greta's panel: lit when it's the open one.
func _make_tab(text: String, tab_id: Tab) -> Button:
	var tab := Button.new()
	tab.text = text
	tab.toggle_mode = true
	tab.focus_mode = Control.FOCUS_NONE
	tab.add_theme_font_size_override("font_size", 17)
	tab.custom_minimum_size = Vector2(110, 34)
	tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var off := StyleBoxFlat.new()
	off.bg_color = Color(1, 1, 1, 0.06)
	off.set_corner_radius_all(6)
	var on := off.duplicate() as StyleBoxFlat
	on.bg_color = Color("8a6142")
	tab.add_theme_stylebox_override("normal", off)
	tab.add_theme_stylebox_override("hover", off)
	tab.add_theme_stylebox_override("pressed", on)
	tab.add_theme_stylebox_override("hover_pressed", on)
	tab.pressed.connect(_show_tab.bind(tab_id))
	_tabs.add_child(tab)
	_tab_buttons.append(tab)
	return tab


func _label(font_size: int) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 2)
	return label
