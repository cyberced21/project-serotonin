class_name TalentCards
extends CanvasLayer
## The talent choice (plans/levels.md, L7): the options as cards side by side, one per style. A
## milestone reached while gathering waits until the action is over (the swing done, the rod
## back) and you've been idle for SETTLE seconds, then pauses the game and shows. "Decide later"
## (or Esc) leaves it waiting on the Skills page, which can open it again (show_choice).
## At mastery (level 50) the cards are the option you didn't take at each milestone.

## Idle this long after a choice is reached before the cards come up (the tree finishes falling,
## the level-up banner has its moment).
const SETTLE := 2.2
## The narrowest a card gets (they widen to share the panel).
const CARD_WIDTH := 220.0

var _queue: Array[StringName] = []
var _idle := 0.0
var _skill: StringName = &""
var _milestone := 0  # 0 = mastery
var _chosen: TalentDef
var _paused_it := false
var _captured_mouse := false

var _shade: ColorRect
var _title: Label
var _cards: HBoxContainer
var _take: Button


func _ready() -> void:
	add_to_group("talent_cards")
	layer = 16  # over the pause menu, which can open it
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	_shade.visible = false
	Skills.talents.choice_ready.connect(func(skill: StringName) -> void:
		if not skill in _queue:
			_queue.append(skill))


func is_open() -> bool:
	return _shade.visible


## Opens `skill`'s next waiting choice now (the Skills page's Choose button).
func show_choice(skill: StringName) -> void:
	_queue.erase(skill)
	var waiting := Skills.talents.waiting(skill)
	if waiting.is_empty() and not Skills.talents.mastery_waiting(skill):
		return
	_skill = skill
	_milestone = waiting[0] if not waiting.is_empty() else 0
	var options := Skills.talents.pair(skill, _milestone) if _milestone > 0 else Skills.talents.mastery_options(skill)
	_title.text = "%s %d: choose a talent" % [Skills.display_name(skill), _milestone] if _milestone > 0 \
		else "%s mastery: take one more" % Skills.display_name(skill)
	_title.add_theme_color_override("font_color", Skills.color(skill))
	_chosen = null
	for c in _cards.get_children():
		c.queue_free()
	for def in options:
		_cards.add_child(_card(def))
	_refresh_take()
	_paused_it = not get_tree().paused
	get_tree().paused = true
	_captured_mouse = Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_shade.visible = true


func _close() -> void:
	_shade.visible = false
	_skill = &""
	if _paused_it:
		get_tree().paused = false
	if _captured_mouse:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_idle = 0.0


func _process(delta: float) -> void:
	if is_open() or _queue.is_empty():
		return
	if _player_busy():
		_idle = 0.0
		return
	_idle += delta
	if _idle >= SETTLE:
		var skill: StringName = _queue.pop_front()
		if Skills.talents.has_waiting(skill):
			show_choice(skill)


## Mid-action, or a menu (pause, a villager's panel, the forge moment) is up.
func _player_busy() -> bool:
	if get_tree().paused or Worlds.current.is_empty():
		return true
	var panel := get_tree().get_first_node_in_group("upgrade_panel") as UpgradePanel
	if panel and panel.is_open():
		return true
	var player := get_tree().get_first_node_in_group("player")
	return player == null or player.is_busy()


func _input(event: InputEvent) -> void:
	if is_open() and event.is_action_pressed("ui_cancel"):
		_close()  # decide later
		get_viewport().set_input_as_handled()


func _select(def: TalentDef) -> void:
	_chosen = def
	for c in _cards.get_children():
		var card := c as PanelContainer
		var on: bool = card.get_meta("def") == def
		card.add_theme_stylebox_override("panel", MenuUI.box(MenuUI.CARD_SELECTED if on else MenuUI.CARD, 16.0,
			MenuUI.ACCENT if on else MenuUI.BORDER))
	_refresh_take()


func _refresh_take() -> void:
	_take.disabled = _chosen == null
	_take.text = "Take %s" % _chosen.display_name if _chosen else "Pick one"


func _on_take() -> void:
	if _chosen == null:
		return
	var ok := Skills.talents.pick(_skill, _milestone, _chosen.id) if _milestone > 0 \
		else Skills.talents.pick_mastery(_skill, _chosen.id)
	if not ok:
		return
	var skill := _skill
	_close()
	if Skills.talents.has_waiting(skill):  # (levelled past two milestones at once: the next one)
		show_choice(skill)


func _card(def: TalentDef) -> PanelContainer:
	var card := PanelContainer.new()
	card.set_meta("def", def)
	card.add_theme_stylebox_override("panel", MenuUI.box(MenuUI.CARD, 16.0, MenuUI.BORDER))
	card.custom_minimum_size = Vector2(CARD_WIDTH, 0)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL  # the cards share the panel's width
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	card.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			_select(def))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(box)
	var style_line := def.style_name if _milestone > 0 else "%s · level %d" % [def.style_name, def.milestone]
	box.add_child(MenuUI.label(style_line, 17, MenuUI.DIM))
	box.add_child(MenuUI.label(def.display_name, 28, MenuUI.ACCENT))
	var text := MenuUI.label(def.text, 19)
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.custom_minimum_size = Vector2(CARD_WIDTH - 40, 0)
	box.add_child(text)
	for c in box.get_children():
		(c as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	return card


func _build() -> void:
	_shade = ColorRect.new()
	_shade.color = Color(0, 0, 0, 0.5)
	_shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_shade)
	var panel := MenuUI.panel(28.0)
	MenuUI.place(panel, Rect2(0.12, 0.1, 0.76, 0.8), true)  # (a share of the window: MenuUI.place)
	_shade.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	panel.add_child(box)
	_title = MenuUI.title("", 36)
	box.add_child(_title)
	_cards = HBoxContainer.new()
	_cards.add_theme_constant_override("separation", 14)
	box.add_child(_cards)
	box.add_child(MenuUI.label("Greta at the smithy can reset a skill's talents.", 16, MenuUI.DIM))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.alignment = BoxContainer.ALIGNMENT_END
	box.add_child(row)
	var later := MenuUI.button("Decide later", _close, 20)
	later.custom_minimum_size = Vector2(180, 0)
	row.add_child(later)
	_take = MenuUI.button("", _on_take, 20)
	_take.custom_minimum_size = Vector2(260, 0)
	row.add_child(_take)
