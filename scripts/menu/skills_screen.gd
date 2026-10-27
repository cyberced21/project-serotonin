class_name SkillsScreen
extends PanelContainer
## Every skill's level and its three perk tracks (Perks): how far each has come, and what the next
## level brings. Rebuilt each time it opens, so it's always current.

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
	var lvl_text := "Level %d (max)" % lvl if lvl >= Skills.MAX_LEVEL \
		else "Level %d · %d%%" % [lvl, roundi(Skills.progress(skill) * 100.0)]
	head.add_child(MenuUI.label(lvl_text, 17, MenuUI.ACCENT))
	box.add_child(head)

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
	return card
