class_name SkillsScreen
extends PanelContainer
## Every skill's level, its three perk tracks (Perks): how far each has come and what the next
## level brings, and its talents (Talents): what you picked at each milestone, and a Choose button
## when a choice is waiting. Rebuilt each time it opens or a pick changes, so it's always current.

signal closed

var _list: VBoxContainer


func _init() -> void:
	add_theme_stylebox_override("panel", MenuUI.box(MenuUI.BG, 22.0, MenuUI.BORDER))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	add_child(box)
	box.add_child(MenuUI.title("Skills", 30))
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 14)
	box.add_child(_list)
	box.add_child(MenuUI.spacer(4))
	var back := MenuUI.button("Back", func() -> void: closed.emit(), 17)
	back.size_flags_horizontal = Control.SIZE_SHRINK_END
	back.custom_minimum_size = Vector2(110, 0)
	box.add_child(back)
	visibility_changed.connect(func() -> void:
		if visible:
			_refresh())
	Skills.talents.changed.connect(func(_s: StringName) -> void:
		if visible:
			_refresh())


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		closed.emit()
		get_viewport().set_input_as_handled()


func _refresh() -> void:
	for c in _list.get_children():
		c.queue_free()
	for skill in Skills.SKILLS:
		_list.add_child(_skill_card(skill))


func _skill_card(skill: StringName) -> Control:
	var lvl := Skills.level(skill)
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", MenuUI.box(MenuUI.CARD, 12.0))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	card.add_child(box)

	var head := HBoxContainer.new()
	head.add_child(MenuUI.label(Skills.display_name(skill), 20, Skills.color(skill)))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(spacer)
	var lvl_text := "Level %d (max)" % lvl if lvl >= Skills.MAX_LEVEL else "Level %d" % lvl
	head.add_child(MenuUI.label(lvl_text, 18, MenuUI.ACCENT))
	box.add_child(head)
	box.add_child(_xp_bar(skill, lvl))

	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 2)
	box.add_child(grid)
	var tracks: Array = Perks.TRACKS[skill]
	for i in tracks.size():
		var b := Perks.bonus_at(skill, tracks[i]["id"], lvl)
		grid.add_child(MenuUI.label(tracks[i]["name"], 16))
		grid.add_child(MenuUI.label("+%d%%" % roundi(b * 100.0), 16, MenuUI.GOOD if b > 0.0 else MenuUI.DIM))
		grid.add_child(MenuUI.label(tracks[i]["text"], 15, MenuUI.DIM))
	if lvl < Skills.MAX_LEVEL:
		var next := Perks.perk_at(skill, lvl + 1)
		box.add_child(MenuUI.label("Next, at %d: %s" % [lvl + 1, next["name"].to_lower()], 15, MenuUI.DIM))
	box.add_child(_talent_row(skill, lvl))
	return card


## The XP bar: how far through the level, the XP in hand and needed, and what's left to go.
func _xp_bar(skill: StringName, lvl: int) -> Control:
	var have: int = Skills.xp.get(skill, 0)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var bar := ColorRect.new()
	bar.color = Color(1, 1, 1, 0.1)
	bar.custom_minimum_size = Vector2(220, 10)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var fill := ColorRect.new()
	fill.color = Skills.color(skill)
	fill.size = Vector2(220.0 * Skills.progress(skill), 10)
	bar.add_child(fill)
	row.add_child(bar)
	if lvl >= Skills.MAX_LEVEL:
		row.add_child(MenuUI.label("%s XP" % _thousands(have), 15, MenuUI.DIM))
		return row
	var need := Skills.xp_for_level(lvl + 1)
	row.add_child(MenuUI.label("%s / %s XP" % [_thousands(have), _thousands(need)], 15))
	row.add_child(MenuUI.label("%s to level %d" % [_thousands(need - have), lvl + 1], 15, MenuUI.DIM))
	return row


## 12345 -> "12,345".
static func _thousands(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.right(3) + out
		s = s.left(s.length() - 3)
	return ("-" if n < 0 else "") + s + out


## One chip per milestone: the talent picked there, "waiting", or the level still to reach; then
## mastery once it's taken, and a Choose button while a choice waits.
func _talent_row(skill: StringName, lvl: int) -> Control:
	var talents := Skills.talents
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 14)
	row.add_child(MenuUI.label("Talents", 16))
	for m in TalentDef.MILESTONES:
		var def := talents.picked(skill, m)
		var chip: Label
		if def:
			chip = MenuUI.label("%d %s" % [m, def.display_name], 15, MenuUI.ACCENT)
			chip.tooltip_text = "%s: %s" % [def.style_name, def.text]
			chip.mouse_filter = Control.MOUSE_FILTER_PASS
		elif lvl >= m:
			chip = MenuUI.label("%d waiting" % m, 15, MenuUI.GOOD)
		else:
			chip = MenuUI.label("%d —" % m, 15, MenuUI.DIM)
		row.add_child(chip)
	var mastered: TalentDef = talents.defs.get(talents.mastery.get(skill, &""))
	if mastered:
		var chip := MenuUI.label("50 %s" % mastered.display_name, 15, MenuUI.ACCENT)
		chip.tooltip_text = "Mastery (%s): %s" % [mastered.style_name, mastered.text]
		chip.mouse_filter = Control.MOUSE_FILTER_PASS
		row.add_child(chip)
	if talents.has_waiting(skill):
		row.add_child(MenuUI.button("Choose", _choose.bind(skill), 15))
	return row


func _choose(skill: StringName) -> void:
	var cards := get_tree().get_first_node_in_group("talent_cards") as TalentCards
	if cards:
		cards.show_choice(skill)
