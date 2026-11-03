extends SceneTree
## Checks better roads (plans/road-travel.md):
##   - stone is an item the market knows, and a broken rock drops some
##   - every road has a card on the noticeboard for its next level, priced by its length, packing
##     open at once and cobbles waiting for the town hall's second tier
##   - paid for, a road is laid overnight: no quicker till morning, then quicker on its line only
##     (+15%, then +30% cobbled), the best where two meet; saved and loaded
##   - you go faster along a packed road than beside it
##   godot --headless --path . -s res://tools/test_roads.gd -- --save-root=user://tool_worlds

var _fails := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var worlds := root.get_node("Worlds")
	worlds.call("_ensure_classic")
	worlds.call("reset", worlds.get("CLASSIC"))
	worlds.call("play", worlds.get("CLASSIC"))
	while get_first_node_in_group("player") == null:
		await process_frame
	await _frames(10)
	var roads := root.get_node("Roads")
	var projects := root.get_node("Projects")
	var inventory := root.get_node("Inventory")
	var village := root.get_node("Village")

	var market: GDScript = load("res://scripts/market.gd")  # (it needs the autoloads: loaded, not named)
	_check(Items.DEFS.has(&"stone") and market.tradeable(&"stone"), "stone is an item and the market takes it")
	_check(market.price(&"stone", &"ore") >= 2, "stone is worth less than ore (%d stones an ore)" % market.price(&"stone", &"ore"))
	await _rock_drops_stone()

	var list: Array = roads.call("roads")
	_check(list.size() >= 10, "every road is listed (%d)" % list.size())
	var cards: Array = (projects.call("all") as Array).filter(func(p: Dictionary) -> bool: return p.get("better", &"") != &"")
	_check(cards.size() == list.size(), "a card per road (%d for %d)" % [cards.size(), list.size()])
	var street: Dictionary = list.filter(func(r: Dictionary) -> bool: return r["id"] == &"main_street")[0]
	var pack := StringName("road:main_street:1")
	var card: Dictionary = projects.call("get_project", pack)
	print("  %s: %s (hall %d), %d m" % [card.get("title"), card.get("cost"), card.get("hall", -1), street["length"]])
	_check(not card.is_empty() and card["hall"] == 1 and card["title"].begins_with("Pack and edge"), "packing the street is open at once")
	_check(int(card["cost"][&"stone"]) >= roundi(street["length"] * 0.3), "it costs stone by its length (%s)" % card["cost"])

	var on_street := _on_road(&"main_street")
	var off := on_street + Vector3(0, 0, 30)
	_check(is_equal_approx(roads.call("bonus_at", on_street), 1.0), "an unbuilt road is no quicker")
	inventory.call("add", &"stone", 500)
	inventory.call("add", &"wood", 100)
	_check(projects.call("pay", pack), "paid for")
	_check(projects.call("is_done", pack) and is_equal_approx(roads.call("bonus_at", on_street), 1.0), "...it's laid tonight: done on the board, no quicker yet")
	root.get_node("DayNight").emit_signal("day_broke")
	_check(is_equal_approx(roads.call("bonus_at", on_street), 1.15), "next morning, +15%% on it (%.2f)" % roads.call("bonus_at", on_street))
	_check(is_equal_approx(roads.call("bonus_at", off), 1.0), "...and nothing off it")
	await _frames(3)
	await _looks(on_street, WorldMap.TEX_PACKED, &"packed", "packed earth")
	var cobble := StringName("road:main_street:2")
	_check(not projects.call("get_project", cobble).is_empty() and projects.call("is_locked", cobble), "cobbles are next, waiting for the town hall")
	village.call("set_tier", &"town_hall", 2)
	_check(projects.call("pay", cobble), "with the hall at tier 2, cobbles")
	root.get_node("DayNight").emit_signal("day_broke")
	_check(is_equal_approx(roads.call("bonus_at", on_street), 1.30), "cobbled, +30%% (%.2f)" % roads.call("bonus_at", on_street))
	await _frames(3)
	await _looks(on_street, WorldMap.TEX_COBBLE, &"cobble", "stone setts")

	var saved: Dictionary = roads.call("to_dict")
	roads.call("from_dict", {})
	_check(is_equal_approx(roads.call("bonus_at", on_street), 1.0), "a fresh world's roads are as laid")
	roads.call("from_dict", saved)
	_check(int(roads.call("level_of", &"main_street")) == 2, "and a loaded one's as built")

	await _walks_faster(on_street)

	if _fails == 0:
		print("test_roads: all passed")
		quit(0)
	else:
		print("test_roads: %d FAILED" % _fails)
		quit(1)


## Built, the street's cells are painted `id`, its edging's laid, and standing on it sounds `surface`.
func _looks(at: Vector3, id: int, surface: StringName, what: String) -> void:
	var terrain := get_first_node_in_group("terrain") as Terrain3D
	_check(terrain.data.get_control_base_id(at) == id, "the street is %s now (id %d)" % [what, terrain.data.get_control_base_id(at)])
	var look := get_first_node_in_group("road_look")
	_check(look != null and look.find_child("Edging_main_street", false, false) != null, "...edged along both sides")
	var player := get_first_node_in_group("player") as Node3D
	player.call("teleport", at + Vector3.UP * 0.05)
	await _frames(10)
	var heard: StringName = player.get("footsteps").call("surface")
	_check(heard == surface, "...and it sounds %s underfoot (%s)" % [surface, heard])


## The middle of road `id` as laid, on the ground.
func _on_road(id: StringName) -> Vector3:
	var pts: PackedVector2Array = WorldMap.road(id)["pts"]
	var p := pts[pts.size() / 2]
	var terrain := get_first_node_in_group("terrain") as Terrain3D
	return Vector3(p.x, terrain.data.get_height(Vector3(p.x, 0, p.y)), p.y)


func _rock_drops_stone() -> void:
	var before := _pickups(&"stone")
	var rock := (load("res://scenes/rock.tscn") as PackedScene).instantiate()
	current_scene.add_child(rock)
	rock.global_position = get_first_node_in_group("player").global_position + Vector3(4, 0, 0)
	await _frames(3)
	var info := HitInfo.new(rock.global_position + Vector3.UP, Vector3.LEFT, rock, rock.global_position + Vector3(-2, 1.6, 0))
	rock.call("_spawn_drops", info)
	await _frames(3)
	_check(_pickups(&"stone") > before, "a broken rock drops plain stone too (%d)" % (_pickups(&"stone") - before))
	rock.queue_free()


func _pickups(item: StringName) -> int:
	var n := 0
	for p in current_scene.get_children():
		if p is RigidBody3D and p.get("item") == item:
			n += 1
	return n


## Holding forward along the cobbled street, then beside it: quicker on it.
func _walks_faster(on: Vector3) -> void:
	var player := get_first_node_in_group("player") as CharacterBody3D
	var pts: PackedVector2Array = WorldMap.road(&"main_street")["pts"]
	var k := pts.size() / 2
	var along := (pts[k + 3] - pts[k - 3]).normalized()
	var speeds := []
	for at in [on, on + Vector3(-along.y, 0, along.x) * 25.0]:
		player.call("teleport", at + Vector3.UP * 0.5, at + Vector3(along.x, 0, along.y) * 10.0 + Vector3.UP * 0.5)
		Input.action_press("move_up")
		await _frames(90)
		speeds.append(Vector2(player.velocity.x, player.velocity.z).length())
		Input.action_release("move_up")
		await _frames(20)
	print("  walking on the cobbles %.2f m/s, beside them %.2f m/s" % speeds)
	_check(speeds[0] > speeds[1] * 1.2, "you walk quicker on the cobbled street (%.2f vs %.2f m/s)" % speeds)


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		_fails += 1
