class_name ControlsScreen
extends PanelContainer
## Every binding, read from the input map, so it stays right if the keys change.

signal closed

## [label, action or "" for a fixed key, fixed key text]
const ROWS := [
	["Move", "move_up,move_left,move_down,move_right", ""],
	["Look", "", "Mouse"],
	["Jump", "jump", ""],
	["Jog", "sprint", ""],
	["Crouch", "crouch", ""],
	["Gather, swing; fish (thrust, or hold to cast)", "gather", ""],
	["Talk to a villager", "interact", ""],
	["Swap spear / rod", "swap_fishing", ""],
	["Skills: levels, XP, perks, talents", "skills", ""],
	["World map (wheel zoom, drag to pan)", "map", ""],
	["Light / put out the lantern", "lantern", ""],
	["Raise the lantern (hold)", "raise_lantern", ""],
	["Pause", "", "Esc"],
]
const DEBUG_ROWS := [
	["Debug menu", "debug_menu", ""],
	["Skip time · items · village tiers · XP", "debug_skip_time,debug_give_items,debug_village_tier,debug_give_xp", ""],
]


func _init() -> void:
	add_theme_stylebox_override("panel", MenuUI.box(MenuUI.BG, 22.0, MenuUI.BORDER))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	add_child(box)
	box.add_child(MenuUI.title("Controls", 34))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 28)
	grid.add_theme_constant_override("v_separation", 8)
	box.add_child(grid)
	for row in ROWS + (DEBUG_ROWS if OS.is_debug_build() or OS.has_feature("playtest") else []):
		grid.add_child(MenuUI.label(row[0], 19))
		var keys: String = row[2] if row[1] == "" else keys_text(row[1])
		grid.add_child(MenuUI.label(keys, 19, MenuUI.ACCENT))
	box.add_child(MenuUI.spacer(6))
	var back := MenuUI.button("Back", func() -> void: closed.emit(), 17)
	back.size_flags_horizontal = Control.SIZE_SHRINK_END
	back.custom_minimum_size = Vector2(110, 0)
	box.add_child(back)


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		closed.emit()
		get_viewport().set_input_as_handled()


## "W A S D", "E / Left mouse": every key bound to the actions (comma-separated), first ones first.
static func keys_text(actions: String) -> String:
	var per_action: Array[PackedStringArray] = []
	for action in actions.split(","):
		var names := PackedStringArray()
		for ev in InputMap.action_get_events(action):
			names.append(event_text(ev))
		per_action.append(names)
	if per_action.size() == 1:
		return " / ".join(per_action[0])
	var firsts := PackedStringArray()
	for names in per_action:
		if not names.is_empty():
			firsts.append(names[0])
	return " ".join(firsts)


static func event_text(ev: InputEvent) -> String:
	if ev is InputEventKey:
		var k := ev as InputEventKey
		var code := k.keycode
		if k.physical_keycode != KEY_NONE:  # the key in that spot on this keyboard's layout
			code = k.physical_keycode
			if DisplayServer.get_name() != "headless":
				code = DisplayServer.keyboard_get_keycode_from_physical(k.physical_keycode)
		return OS.get_keycode_string(code)
	if ev is InputEventMouseButton:
		match (ev as InputEventMouseButton).button_index:
			MOUSE_BUTTON_LEFT:
				return "Left mouse"
			MOUSE_BUTTON_RIGHT:
				return "Right mouse"
			MOUSE_BUTTON_MIDDLE:
				return "Middle mouse"
	return ev.as_text()
