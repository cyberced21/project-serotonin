extends SceneTree
## Checks the dog (scripts/dog.gd, plans/dog.md): a new world has three strays by the clearing's
## pond by day (none at night); petting one asks his name and coat, he's yours and the others
## wander off. Then, walking the village path and sprinting over
## the hills he keeps up, stays on the ground and out of your way; he sits when you stop, lies
## down while you gather (never in front of you), and pops in behind you after a teleport.
## The player is moved by the test (its own physics off), as if walking. (No game class names: an
## -s script compiles before the autoloads exist.)
##   godot --headless --path . -s res://tools/test_dog.gd -- --save-root=user://tool_worlds

var _fails := 0
var player: CharacterBody3D
var dog: Node3D
var terrain: Terrain3D
var _shook := false


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.get_node("Worlds").call("play_fresh")
	await process_frame
	while get_first_node_in_group("player") == null:
		await process_frame
	await _frames(5)
	player = get_first_node_in_group("player") as CharacterBody3D
	terrain = get_first_node_in_group("terrain") as Terrain3D
	player.set_physics_process(false)
	await _meet()
	dog = get_first_node_in_group("dog") as Node3D
	_check(dog != null, "adopting puts a dog in the world")
	if dog == null:
		return _finish()

	# the village path, at a walk
	var path: PackedVector2Array = load("res://scripts/world_map.gd").roads()[0]["pts"]
	path.reverse()  # from the clearing
	await _walk(path, 3.8, "the village path")
	await _stop_and_sit()
	await _gather()
	# over the hills at a jog: the clearing west to the quarry's mountainside
	await _walk(PackedVector2Array([Vector2(-20, -6), Vector2(-60, 10), Vector2(-95, 20)]), 5.5, "over the hills")
	await _teleport()
	await _pet()
	await _water()
	await _carry_lantern()
	await _night_and_kennel()
	await _night_strays()
	_finish()


func _meet() -> void:
	await _frames(10)
	var strays := get_nodes_in_group("stray_dog")
	_check(strays.size() == 3, "a new world by day: three strays by the pond (%d)" % strays.size())
	if strays.size() < 3:
		return
	var shepherd: Node3D = strays.filter(func(d: Node) -> bool: return d.get("breed") == &"shepherd")[0]
	_place(shepherd.global_position + Vector3(2, 0, 0), Vector2(-1, 0))
	await _frames(30)
	_check(shepherd.get("state") == 1, "close by, a stray sits up and watches you")
	print("prompt: %s" % shepherd.call("prompt"))
	shepherd.call("interact")
	var panel := get_first_node_in_group("dog_name_panel")
	_check(panel != null and panel.call("is_open"), "petting a stray asks his name")
	if panel == null:
		return
	panel.call("confirm", &"brown", "Rex")
	await _frames(5)
	var companion := root.get_node("Companion")
	_check(companion.get("has_dog") and companion.get("breed") == &"shepherd" and companion.get("coat") == &"brown"
			and companion.get("dog_name") == "Rex", "he's yours: a brown shepherd mutt called Rex")
	_check(get_first_node_in_group("dog") == shepherd and get_nodes_in_group("dog").size() == 1, "the stray you petted is your dog")
	var others := strays.filter(func(d: Node) -> bool: return d != shepherd)
	var before: Array = others.map(func(d: Node3D) -> float: return d.global_position.distance_to(player.global_position))
	await _seconds(3.0)
	var after: Array = others.map(func(d: Node3D) -> float: return d.global_position.distance_to(player.global_position) if is_instance_valid(d) else 999.0)
	_check(after[0] > before[0] + 3.0 and after[1] > before[1] + 3.0, "the other two wander off")
	_check(not panel.call("is_open"), "the box is closed")


func _pet() -> void:
	await _seconds(2.0)
	dog.call("interact")
	await _frames(5)
	_check(dog.get("state") == 4, "E on him: a pat, he wiggles (state %s)" % dog.get("state"))  # State.PET
	await _seconds(2.5)
	_check(dog.get("state") != 4, "...then he settles again")


## The lake: wading depth near the shore, too deep for him in the middle.
func _water() -> void:
	var schools: Array = []
	for w in get_nodes_in_group("water"):
		if String(w.name) == "Lake":
			for c in w.get_children():
				for s in c.get_children():
					if s.get("fish") is Array:
						schools.append(s)
	_place(Vector3(-16, 0, 100), Vector2(0, -1))
	await _seconds(5.0)
	var max_depth := 0.0
	var got_wet := false
	var fled := 0
	for target: Vector2 in [Vector2(-16, 84), Vector2(-16, 74)]:
		var from := Vector2(player.global_position.x, player.global_position.z)
		await _walk_quiet(from, target, 2.0)
		for i in 60 * 6:
			await physics_frame
			var d: float = load("res://scripts/water_body.gd").depth_at(self, dog.global_position)
			max_depth = maxf(max_depth, d)
			got_wet = got_wet or d > 0.15
			for school in schools:
				for f in school.fish:
					if f.flee_time > 0.0:
						fled += 1
	print("water: deepest he went %.2f m" % max_depth)
	_check(got_wet, "he follows you into wading-depth water")
	_check(max_depth <= 0.95, "...but waits where it's too deep for him (deepest %.2f m)" % max_depth)
	_check(fled == 0, "fish don't flee from him (%d fleeing fish-frames)" % fled)
	_shook = false
	await _walk_quiet(Vector2(-16, 74), Vector2(-16, 104), 3.0)
	for i in 60 * 8:
		await physics_frame
		_shook = _shook or dog.get("state") == 5
	_check(_shook, "out of the water, he shakes himself dry")


## Night with the lantern lit: he carries it and walks ahead; holding it up takes it back.
func _carry_lantern() -> void:
	var lamps := root.get_node("Lamps")
	var day_night := root.get_node("DayNight")
	day_night.set("frozen", true)
	day_night.set("time", 0.95)
	lamps.set("has_lantern", true)
	lamps.call("set_lantern_lit", true)
	var held: Node3D = player.get("lantern")
	_place(Vector3(0, 0, 40), Vector2(0, -1))
	await _seconds(3.0)
	var in_mouth := dog.find_child("Lantern", true, false) as Node3D
	_check(dog.call("carrying") and in_mouth and in_mouth.visible, "at night he carries the lantern in his mouth")
	_check(not held.visible, "...and the one on your belt is gone")
	await _walk_quiet(Vector2(0, 40), Vector2(0, 10), 3.0)
	var ahead := dog.global_position - player.global_position
	_check(ahead.z < 0.0, "walking, he goes ahead of you to light the way (%.1f m ahead)" % -ahead.z)
	# (headless can't capture the mouse, so the raise key never reaches the lantern: hold it up by hand)
	held.set_process(false)
	held.set("_raise", 1.0)
	await _seconds(0.3)
	_check(not dog.call("carrying"), "holding it up: it's back in your hand")
	held.set("_raise", 0.0)
	held.set_process(true)
	await _seconds(2.5)
	_check(dog.call("carrying") and not held.visible, "let go, and he takes it again")
	lamps.call("set_lantern_lit", false)
	day_night.set("time", 0.4)
	await _frames(5)
	_check(not dog.call("carrying"), "put out, he doesn't carry it")
	day_night.set("frozen", false)


## Dozing at your feet at night; the doghouse projects, one after another; sleeping in its doorway,
## waiting there in the morning.
func _night_and_kennel() -> void:
	var day_night := root.get_node("DayNight")
	var projects := root.get_node("Projects")
	day_night.set("frozen", true)
	day_night.set("time", 0.95)
	_place(Vector3(-20, 0, 40), Vector2(0, -1))
	await _seconds(14.0)
	var gap := Vector2(dog.global_position.x - player.global_position.x, dog.global_position.z - player.global_position.z).length()
	_check(dog.get("state") == 2 and dog.get("_sleeping") and gap < 1.8, "at night, standing still: he dozes at your feet (%.1f m)" % gap)
	var ids: Array = (projects.call("all") as Array).map(func(p: Dictionary) -> StringName: return p["id"])
	_check(ids.has(&"kennel") and not ids.has(&"kennel_paint") and not ids.has(&"kennel_porch"), "with a dog, the kennel is on the board (and not the next steps yet)")
	projects.call("set_done", &"kennel", true)
	ids = (projects.call("all") as Array).map(func(p: Dictionary) -> StringName: return p["id"])
	_check(ids.has(&"kennel_paint") and not ids.has(&"kennel_porch"), "kennel built: painting it comes up")
	projects.call("set_done", &"kennel_paint", true)
	projects.call("set_done", &"kennel_porch", true)
	await _frames(5)
	var decor := get_first_node_in_group("village_decor")
	var sign := decor.find_child("Name", true, false) as Label3D
	_check(sign != null and sign.text == "Rex", "the painted doghouse has his name on the sign")
	var plain: Array = decor.call("props_of", &"kennel")
	_check(not plain.is_empty() and not (plain[0] as Node3D).visible, "the painted one takes the plain one's place")
	_check((decor.call("props_of", &"kennel_porch") as Array).size() == 3, "the porch, the bowl and the blanket")
	# night in the village: off to bed
	var door: Transform3D = decor.call("kennel_door")
	_place(Vector3(100, 0, 40), Vector2(0, 1))
	await _seconds(25.0)  # (he runs over from where you were)
	gap = Vector2(dog.global_position.x - door.origin.x, dog.global_position.z - door.origin.z).length()
	_check(gap < 1.0 and dog.get("state") == 2 and dog.get("_sleeping"), "night in the village: asleep in the kennel's doorway (%.1f m off)" % gap)
	day_night.set("time", 0.3)
	_place(Vector3(100, 0, 25), Vector2(0, -1))
	await _seconds(3.0)
	gap = Vector2(dog.global_position.x - door.origin.x, dog.global_position.z - door.origin.z).length()
	_check(gap < 1.0 and dog.get("state") == 1, "in the morning he waits there (%.1f m off)" % gap)
	_place(Vector3(door.origin.x + 4, 0, door.origin.z - 4), Vector2(0, -1))
	await _seconds(2.0)
	_check(not dog.get("_home"), "...until you come by")
	day_night.set("frozen", false)


func _walk_quiet(a: Vector2, b: Vector2, speed: float) -> void:
	var d := a.distance_to(b)
	var t := 0.0
	while t < d:
		t += speed / 60.0
		var p := a.lerp(b, minf(t / d, 1.0))
		_place(Vector3(p.x, 0, p.y), b - a)
		player.velocity = Vector3(b.x - a.x, 0, b.y - a.y).normalized() * speed
		await physics_frame
		_shook = _shook or dog.get("state") == 5  # State.SHAKE
	player.velocity = Vector3.ZERO


func _night_strays() -> void:
	var companion := root.get_node("Companion")
	var day_night := root.get_node("DayNight")
	companion.call("from_dict", {})
	dog.queue_free()
	var home := get_first_node_in_group("dog_home")
	day_night.set("frozen", true)
	day_night.set("time", 0.95)
	await _frames(10)
	_check(get_nodes_in_group("stray_dog").is_empty(), "no dog yet, at night: no strays yet")
	day_night.set("time", 0.2)
	await _frames(10)
	_check(get_nodes_in_group("stray_dog").size() == 3, "...and at dawn there they are")
	day_night.set("frozen", false)


func _walk(pts: PackedVector2Array, speed: float, what: String) -> void:
	_place(Vector3(pts[0].x, 0, pts[0].y), pts[1] - pts[0])
	await _seconds(4.0)  # (he comes over from wherever he was first)
	var far := 0.0
	var off_ground := 0.0
	var in_front := 0
	for i in pts.size() - 1:
		var a := pts[i]
		var b := pts[i + 1]
		var d := a.distance_to(b)
		var t := 0.0
		while t < d:
			var dt := 1.0 / 60.0
			t += speed * dt
			var p := a.lerp(b, minf(t / d, 1.0))
			_place(Vector3(p.x, 0, p.y), b - a)
			player.velocity = Vector3(b.x - a.x, 0, b.y - a.y).normalized() * speed
			await physics_frame
			var gap := Vector2(dog.global_position.x - p.x, dog.global_position.z - p.y).length()
			far = maxf(far, gap)
			if load("res://scripts/water_body.gd").depth_at(self, dog.global_position) == 0.0:  # (in the creek he floats)
				off_ground = maxf(off_ground, absf(dog.global_position.y - _h(dog.global_position)))
	player.velocity = Vector3.ZERO
	print("%s: farthest behind %.1f m, off the ground by up to %.2f m" % [what, far, off_ground])
	_check(far < 14.0, "%s: he keeps up (at most %.1f m away)" % [what, far])
	_check(off_ground < 0.05, "%s: he stays on the ground" % what)


func _stop_and_sit() -> void:
	await _seconds(4.0)
	_check(dog.get("state") == 1, "stopped: he sits (state %s)" % dog.get("state"))  # State.SIT
	var gap := Vector2(dog.global_position.x - player.global_position.x, dog.global_position.z - player.global_position.z).length()
	_check(gap > 1.0 and gap < 5.0, "...close by (%.1f m)" % gap)


func _gather() -> void:
	var look := -(player.get("camera") as Node3D).global_basis.z
	look.y = 0.0
	look = look.normalized()
	var front := 0
	for i in 60 * 8:
		player.set("_swinging", (i / 30) % 2 == 0)  # a swing every second
		await physics_frame
		var d := dog.global_position - player.global_position
		d.y = 0.0
		if i > 120 and d.length() < 6.0 and d.normalized().dot(look) > cos(deg_to_rad(40.0)):
			front += 1
	player.set("_swinging", false)
	_check(dog.get("state") == 2, "gathering a while: he lies down (state %s)" % dog.get("state"))  # State.LIE
	_check(front == 0, "...never in front of what you're hitting (%d frames)" % front)


func _teleport() -> void:
	_place(player.global_position, Vector2(1, 0))  # face east first, then jump
	await _frames(3)
	_place(player.global_position + Vector3(120, 0, 40), Vector2(1, 0))
	await _frames(3)
	var gap := Vector2(dog.global_position.x - player.global_position.x, dog.global_position.z - player.global_position.z).length()
	_check(gap < 12.0, "after a teleport he pops in nearby (%.1f m)" % gap)
	var look := -(player.get("camera") as Node3D).global_basis.z
	var to_dog := (dog.global_position - player.global_position)
	to_dog.y = 0.0
	look.y = 0.0
	_check(to_dog.normalized().dot(look.normalized()) < 0.0, "...behind you, out of view")


func _place(at: Vector3, dir: Vector2) -> void:
	at.y = _h(at)
	player.global_position = at
	if dir.length() > 0.01:
		player.rotation.y = atan2(-dir.x, -dir.y)


func _h(p: Vector3) -> float:
	var h: float = terrain.data.get_height(p)
	return 0.0 if is_nan(h) else h


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


func _seconds(s: float) -> void:
	for i in int(s * 60.0):
		await physics_frame


func _check(ok: bool, what: String) -> void:
	if not ok:
		_fails += 1
	print(("ok   " if ok else "FAIL ") + what)


func _finish() -> void:
	print("test_dog: %s" % ("PASS" if _fails == 0 else "%d FAILED" % _fails))
	quit(1 if _fails else 0)
