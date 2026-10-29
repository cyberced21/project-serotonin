extends SceneTree
## (No game class names here: an -s script compiles before the autoloads exist.)
## Plays the talent flow in a real world, headless: reach Woodcutting 10, wait for the cards to
## come up on their own, take a talent, open the Skills page, reset at Greta's, and see the
## choice come back.
##   godot --headless --path . -s res://tools/talent_playtest.gd -- --save-root=user://talent_playtest

var _fails := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.get_node("Worlds").call("play_fresh")
	await process_frame
	while get_first_node_in_group("player") == null:
		await process_frame
	var skills := root.get_node("Skills")
	var talents: Object = skills.get("talents")
	var cards: Node = get_first_node_in_group("talent_cards")
	_check(cards != null, "the HUD has talent cards")

	skills.call("set_level", &"woodcutting", 10)
	_check(not cards.is_open(), "the cards wait a moment after the level-up")
	await _wait_for(func() -> bool: return cards.is_open(), 6.0)
	_check(cards.is_open() and paused, "then come up and pause the game")
	var options: Array = cards.get("_cards").get_children()
	_check(options.size() == 2, "two cards")
	cards.call("_select", options[0].get_meta("def"))
	cards.call("_on_take")
	_check(not cards.is_open() and not paused, "taking one closes them and resumes")
	_check(talents.has(options[0].get_meta("def").id), "the talent is yours")

	var pause := root.get_node("PauseMenu")
	var k := InputEventAction.new()
	k.action = &"skills"
	k.pressed = true
	Input.parse_input_event(k)
	await process_frame
	await process_frame
	var screen: Control = pause.get("_skills")
	_check(screen.visible and paused, "K opens the Skills page, paused")
	_check(screen.get("_list").get_child_count() == 4, "the Skills page lists four skills")
	var texts := screen.find_children("*", "Label", true, false).map(func(l: Label) -> String: return l.text)
	_check(texts.any(func(t: String) -> bool: return t.ends_with("to level 11")), "it shows the XP left to the next level")
	Input.parse_input_event(k)
	await process_frame
	await process_frame
	_check(not screen.visible and not paused, "K again goes back to play")

	var panel: Node = get_first_node_in_group("upgrade_panel")
	var greta: Node = null
	for b in get_nodes_in_group("building"):
		if b.get("def").id == &"smithy":
			greta = b.get_node_or_null("Villager")
	_check(greta != null, "Greta is in the village")
	if greta:
		var player: Node3D = get_first_node_in_group("player")
		player.global_position = greta.global_position + Vector3(1.5, 0.5, 0)  # (the panel closes if you're far)
		panel.open(greta)
		panel.call("_show_tab", 2)  # Tab.TALENTS
		await process_frame
		_check(panel.get("_talents_box").visible, "Greta's Talents tab opens")
		panel.call("_on_respec_pressed", &"woodcutting")
		_check(talents.picked_count(&"woodcutting") == 0 and not panel.is_open(), "the free reset clears the pick and closes")
		await _wait_for(func() -> bool: return cards.is_open(), 6.0)
		_check(cards.is_open(), "and the choice comes back")
		cards.call("_close")
		_check(talents.has_waiting(&"woodcutting"), "decide later leaves it waiting")
	print("talent_playtest: %s" % ("PASS" if _fails == 0 else "%d FAILED" % _fails))
	quit(1 if _fails else 0)


func _wait_for(done: Callable, seconds: float) -> void:
	var until := Time.get_ticks_msec() + int(seconds * 1000.0)
	while not done.call() and Time.get_ticks_msec() < until:
		await process_frame


func _check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		_fails += 1
