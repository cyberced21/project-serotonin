extends Node
## Registers input actions in code so the prototype works without editing the Input Map.
## Once you're happy with the bindings you can move them into Project Settings > Input Map.

const BINDINGS := {
	"move_left": [KEY_A, KEY_LEFT],
	"move_right": [KEY_D, KEY_RIGHT],
	"move_up": [KEY_W, KEY_UP],
	"move_down": [KEY_S, KEY_DOWN],
	"gather": [KEY_E],
	# also E: on a villager it talks instead of gathering (see player.gd)
	"interact": [KEY_E],
	"jump": [KEY_SPACE],
	"sprint": [KEY_SHIFT],
	"crouch": [KEY_CTRL, KEY_C],
	# swap the fishing tool: spear <-> rod
	"swap_fishing": [KEY_Q],
	# the Skills page (levels, XP, perks, talents), straight from play
	"skills": [KEY_K],
	# the world map (scripts/map)
	"map": [KEY_M],
	# debug builds only
	"debug_menu": [KEY_F1],
	"debug_skip_time": [KEY_F6],
	"debug_give_items": [KEY_F7],
	"debug_village_tier": [KEY_F8],
	"debug_give_xp": [KEY_F9],
	"debug_reset_save": [KEY_F10],
}

func _enter_tree() -> void:
	for action in BINDINGS:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for key in BINDINGS[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = key
			InputMap.action_add_event(action, ev)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	InputMap.action_add_event("gather", click)
