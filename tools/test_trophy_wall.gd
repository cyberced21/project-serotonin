extends SceneTree
## Checks the trophy wall (plans/trophies.md, phases 4-5) in a fresh Hearthvale with a Cottage:
## hang a trophy from the panel (it shows, with its label), swap it (the first goes back in your
## pack), take it down; the Homestead keeps what's hung and adds the mantel (small ones only); a
## visitor remarks on a trophy they haven't seen; a full wall brings the mayor's note, framed by
## the door once read.
##   godot --headless --path . -s res://tools/test_trophy_wall.gd -- --save-root=user://tool_worlds
## (No game class names: an -s script compiles before the autoloads exist.)

var _fails := 0
var T: GDScript


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	T = load("res://scripts/trophies.gd")
	root.get_node("Worlds").call("play_fresh")
	await process_frame
	while get_first_node_in_group("player") == null:
		await process_frame
	var map := get_first_node_in_group("map_data")
	for i in 900:
		if map == null or map.get("is_built"):
			break
		await process_frame
	var player := get_first_node_in_group("player") as Node3D
	var home := get_first_node_in_group("home") as Node3D
	var village := root.get_node("Village")
	village.call("set_tier", &"home", 3)
	for i in 240:
		await physics_frame
	var plaques := _places(home, 3)
	_check(plaques.size() == 6, "the cottage has 6 plaques (%d)" % plaques.size())
	var log: Dictionary = T.call("found", &"log", Vector3(100, 0, 40))
	var pike: Dictionary = T.call("found", &"fish", Vector3(-16, 0, 74), &"pike")
	var plaque: Node = plaques[0] if not plaques.is_empty() else null
	var panel := get_first_node_in_group("trophy_panel")
	_check(panel != null, "there's a trophy panel")
	if plaque == null or panel == null:
		_finish()
		return

	# hang, swap, take down
	player.call("teleport", plaque.global_position + plaque.global_basis.z * 1.5)
	await physics_frame
	_check(String(plaque.call("prompt")).contains("Hang"), "an empty plaque: %s" % plaque.call("prompt"))
	panel.call("open", plaque)
	panel.call("hang", log)
	await process_frame
	_check(T.get("hung").get(plaque.get("place")) == log and plaque.get("_shown") != null,
			"the trophy log hangs there: %s" % plaque.call("prompt"))
	_check(not T.get("carried").has(log), "...out of your pack")
	await create_timer(0.3).timeout
	panel.call("open", plaque)
	panel.call("hang", pike)
	await process_frame
	_check(T.get("hung").get(plaque.get("place")) == pike and T.get("carried").has(log), "swap: the pike up, the log back in your pack")
	await create_timer(0.3).timeout
	panel.call("open", plaque)
	panel.call("take_down")
	await process_frame
	_check(not T.get("hung").has(plaque.get("place")) and T.get("carried").has(pike), "take it down: back in your pack")

	# a visitor remarks on it
	await create_timer(0.3).timeout  # (the panel ignores an E right after closing)
	panel.call("open", plaque)
	panel.call("hang", pike)
	var ollie: Node = null
	for b in get_nodes_in_group("building"):
		if b.get("def").get("id") == &"fisher":
			ollie = b.get_node("Villager")
	home.set("_seen", {"fisher": 3})  # (seen the cottage already: the trophy's what's new)
	ollie.global_position = player.global_position + Vector3(1, 0, 0)
	home.call("visited", ollie)
	var said := ollie.get("_said") as Label3D
	_check(said != null and String(said.text).contains("pike"), "Ollie on the pike: %s" % (said.text if said else "nothing"))

	# the homestead keeps it, and has a mantel for small things
	village.call("set_tier", &"home", 4)
	for i in 240:
		await physics_frame
	var up := _places(home, 4)
	_check(up.size() == 9, "the homestead: 6 plaques and 3 on the mantel (%d)" % up.size())
	var same: Node = null
	var mantel: Node = null
	for p in up:
		if p.get("place") == plaque.get("place"):
			same = p
		if String(p.get("place")).begins_with("Mantel"):
			mantel = p
	_check(same != null and same.get("_shown") != null, "...the pike still hangs in its place")
	T.call("found", &"log", Vector3(100, 0, 40))
	var shell: Dictionary = T.call("found", &"shell", Vector3(-16, 0, 74))
	var fits: Array = T.call("fitting", true)
	_check(fits.size() == 1 and fits[0] == shell, "the mantel takes the shell, not the log")

	# a full wall: the mayor's note, framed once read
	for p in up:
		if not T.get("hung").has(p.get("place")):
			T.call("hang", p.get("place"), {"kind": "shell" if String(p.get("place")).begins_with("Mantel") else "log",
					"species": "", "where": "Hearthvale", "day": 3})
	await process_frame
	var note: Node = home.get("_note_node")
	_check(note != null and bool(home.get("_note").get("framed", false)), "a full wall: the mayor's note on the desk")
	if note:
		note.call("interact")
		await process_frame
		_check(home.get("_framed") and home.get("_frame_node") != null, "...read, it's framed by the door")
	_finish()


## Your home's trophy places in tier `t`.
func _places(home: Node, t: int) -> Array:
	var out := []
	for c in home.get_node("Tier%d" % t).get_children():
		if c.get("place") != null and String(c.get("place")) != "":
			out.append(c)
	return out


func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		_fails += 1


func _finish() -> void:
	print("test_trophy_wall: %s" % ("PASS" if _fails == 0 else "%d FAILED" % _fails))
	quit(1 if _fails else 0)
