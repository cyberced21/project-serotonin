extends SceneTree
## Checks the villagers coming to you (plans/home.md, phase 7) in a fresh Hearthvale: with a
## cabin, a villager walks over by day; with you there they say something (about the new cabin,
## the first time); with you away they leave a gift on the doorstep, which you can pick up. With
## a homestead, an evening on your porch.
##   godot --headless --path . -s res://tools/test_visits.gd -- --save-root=user://tool_worlds
## (No game class names: an -s script compiles before the autoloads exist.)

const SPEED := 6.0

var _fails := 0
var _day: GDScript
var _dn: Node


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_day = load("res://scripts/villager_day.gd")
	_dn = root.get_node("DayNight")
	root.get_node("Worlds").call("play_fresh")
	await process_frame
	while get_first_node_in_group("player") == null:
		await process_frame
	var player := get_first_node_in_group("player") as Node3D
	var home := get_first_node_in_group("home") as Node3D
	var village := root.get_node("Village")
	for b in get_nodes_in_group("building"):  # everyone moved in
		village.call("set_tier", b.get("def").get("id"), 3)
	village.call("set_tier", &"home", 2)
	_dn.set("time", _day.call("time_at", 10.0))
	for i in 240:
		await physics_frame
	player.process_mode = Node.PROCESS_MODE_DISABLED  # (it stays where it's put)
	var visit := home.call("mark", "Visit") as Node3D
	_check(visit != null, "the cabin has a place for visitors to stand")

	# you're home: a visitor comes and says something about the cabin
	player.global_position = visit.global_position + visit.global_basis.z * 3.0
	_check(home.call("send_visitor"), "a villager sets off to see you")
	var v := await _visitor_arrives()
	_check(v != null, "...and gets to your door")
	if v:
		await create_timer(0.5).timeout
		var said := v.get("_said") as Label3D
		_check(said != null and is_instance_valid(said) and String(said.text).contains("cabin"),
				"...and says so: %s" % (said.text if said and is_instance_valid(said) else "nothing"))
		_check(int(home.get("_seen").get(String(v.get("building").get("def").get("id")), 0)) == 2, "...they've seen the cabin now")
		await _visit_ends(v)

	# you're out: they leave something on the step
	player.global_position = Vector3(140, 0, 60)
	_check(home.call("send_visitor"), "another sets off while you're away")
	v = await _visitor_arrives()
	await create_timer(0.5).timeout
	var gift := home.get("_doorstep_node") as Node
	_check(gift != null and is_instance_valid(gift), "...and leaves a gift on the doorstep")
	if gift and is_instance_valid(gift):
		var g: Dictionary = gift.get("note").get("gift")
		var item: StringName = g.keys()[0]
		var inv := root.get_node("Inventory")
		var had: int = inv.call("count", item)
		gift.call("interact")
		await process_frame
		_check(inv.call("count", item) == had + int(g[item]), "...you pick it up: %d %s" % [int(g[item]), item])
	if v:
		await _visit_ends(v)

	# the homestead: an evening on the porch
	village.call("set_tier", &"home", 4)
	for i in 240:
		await physics_frame
	_dn.set("time", _day.call("time_at", 18.0))
	_check(home.call("ask_to_porch"), "someone's asked to the porch this evening")
	var porcher: Node = null
	for b in get_nodes_in_group("building"):
		var vv: Node = b.get_node_or_null("Villager")
		if vv and vv.get("porch_tonight"):
			porcher = vv
	var on_porch := false
	Engine.time_scale = SPEED
	var t0 := Time.get_ticks_msec()
	while porcher and Time.get_ticks_msec() - t0 < 90000:
		await physics_frame
		var seat: Node3D = porcher.get("_seat")
		if seat and String(seat.name).begins_with("PorchSeat") \
				and porcher.global_position.distance_to(seat.global_position) < 0.4:
			on_porch = true
			break
	Engine.time_scale = 1.0
	_check(on_porch, "...and %s sits on your porch at dusk" % (porcher.call("display_name") if porcher else "nobody"))
	_finish()


## The villager on their way to see you, once they're at the door (or null after a while).
func _visitor_arrives() -> Node:
	Engine.time_scale = SPEED
	var t0 := Time.get_ticks_msec()
	var found: Node = null
	var frames := 0
	while Time.get_ticks_msec() - t0 < 90000 and found == null:
		await physics_frame
		frames += 1
		for b in get_nodes_in_group("building"):
			var v: Node = b.get_node_or_null("Villager")
			if v and v.get("_home_visit") and float(v.get("_visit_left")) > 0.0:
				found = v
			elif v and v.get("_home_visit") and frames % 300 == 0:
				print("    %s: state %d at %s, going to %s, %d points left" % [v.call("display_name"), v.get("state"),
						v.global_position.snapped(Vector3.ONE * 0.1), v.get("_target").name, (v.get("_route") as PackedVector3Array).size()])
	Engine.time_scale = 1.0
	return found


## The visit's over and they're heading back.
func _visit_ends(v: Node) -> void:
	Engine.time_scale = SPEED
	var t0 := Time.get_ticks_msec()
	while v.get("_home_visit") and Time.get_ticks_msec() - t0 < 30000:
		await physics_frame
	Engine.time_scale = 1.0
	_check(v.get("_home_visit") == null, "...then %s heads back to work" % v.call("display_name"))


func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		_fails += 1


func _finish() -> void:
	print("test_visits: %s" % ("PASS" if _fails == 0 else "%d FAILED" % _fails))
	quit(1 if _fails else 0)
