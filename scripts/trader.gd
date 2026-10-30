class_name Trader
extends Node3D
## The travelling trader (plans/market.md). Once the road east is open (the landslide's wall
## built), she drives her horse and cart over the pass the next morning and every second morning
## after: down the road east into the village, parked by the market stall for the day (the stall's
## rates are kinder while she's in: Market.TRADER_RATE), and back up the road at dusk. Where she is
## comes from the time of day alone (DayNight.time), so a save, a skipped night or a debug jump
## never leaves her stranded. She brings one of each kind of special per visit (SPECIALS, in
## turn): something for your dog, a decoration, a lantern glass; the market panel shows them.

## The day she sets off down the road, parks, packs up, and is gone (DayNight.time).
const SET_OFF := 0.24
const PARKED := 0.31
const PACK_UP := 0.80
const GONE := 0.87
## Where she parks: behind the market stall, off the green's ring, and how she gets there from
## the end of the road east (world XZ).
const PARK := Vector2(157, 143)
const TOWN_WAY: Array[Vector2] = [Vector2(178, 127), Vector2(163, 136)]
const CART := preload("res://models/village/props/trader_cart.glb")
## Sounds (audio/trader/SOURCES.md): hooves and wheels while she drives (looped from the cart), the
## horse snorting now and then while parked.
const CART_SOUND := preload("res://audio/trader/cart.wav")
const SNORT := preload("res://audio/trader/snort.wav")
const CART_DB := -6.0
const SNORT_DB := -8.0
const SNORT_GAP := Vector2(9.0, 20.0)
const PERSON := preload("res://models/village/villager_trader.glb")
## What she brings: [id, kind (dog / decoration / lantern), title, blurb, cost]. One of each kind
## per visit, in turn.
const SPECIALS := [
	[&"collar_red", &"dog", "A red collar", "A soft leather collar with a little brass tag.", {&"gold": 2, &"birch": 8}],
	[&"collar_blue", &"dog", "A blue bandana", "A neckerchief, knotted at the side.", {&"wheat": 12, &"trout": 3}],
	[&"collar_green", &"dog", "A green collar", "Moss-green with a bell that jingles.", {&"iron": 4, &"barley": 8}],
	[&"deco_baskets", &"decoration", "Hanging flower baskets", "Baskets of flowers on the square's lamp posts.", {&"wheat": 10, &"barley": 10, &"birch": 6}],
	[&"deco_weathervane", &"decoration", "A weathervane", "A copper rooster on a tall pole in the square, turning with the wind.", {&"ore": 25, &"oak": 8}],
	[&"deco_cart", &"decoration", "A painted cart", "A little flower-painted handcart by the market, full of pumpkins.", {&"oak": 12, &"pine": 10}],
	[&"glass_green", &"lantern", "Green lantern glass", "Your lantern glows a soft forest green.", {&"crystal": 1, &"pine": 10}],
	[&"glass_rose", &"lantern", "Rose lantern glass", "Your lantern glows a warm rose.", {&"gold": 2, &"salmon": 1}],
	[&"glass_amber", &"lantern", "Amber lantern glass", "The old warm glow, if you miss it.", {&"wood": 6}],
]

var _day := 0        # mornings since the world began (counted at each sunrise)
var _open_day := -1  # the morning the road east opened, or -1
var _owned: Dictionary[StringName, bool] = {}
var _cart: Node3D
var _person: Node3D
var _path := PackedVector2Array()  # the road east's end down to the parking spot
var _parts: Dictionary[StringName, Node3D] = {}
var _rest: Dictionary[StringName, Transform3D] = {}
var _was_moving := 0.0
var _rolling: AudioStreamPlayer3D
var _snort: AudioStreamPlayer3D
var _snort_in := 5.0


func _ready() -> void:
	add_to_group("trader")
	SaveGame.register(&"trader", self)
	DayNight.day_broke.connect(func() -> void:
		_day += 1
		SaveGame.mark_dirty())
	Projects.changed.connect(_check_open)
	_cart = CART.instantiate() as Node3D
	_cart.name = "Cart"
	add_child(_cart)
	_person = PERSON.instantiate() as Node3D
	_person.name = "Person"
	add_child(_person)
	for n in [_cart, _person]:
		for m in (n as Node).find_children("*", "MeshInstance3D", true, false):
			(m as MeshInstance3D).material_override = PaletteMaterial.for_mesh((m as MeshInstance3D).mesh)
	for part: StringName in [&"WheelL", &"WheelR", &"Horse", &"Head", &"LegFL", &"LegFR", &"LegBL", &"LegBR"]:
		var n := _cart.find_child(String(part), true, false) as Node3D
		if n:
			_parts[part] = n
			_rest[part] = n.transform
	_rolling = _player(CART_SOUND, CART_DB, 50.0)
	_rolling.finished.connect(func() -> void:
		if _was_moving > 0.5 and _cart.visible:
			_rolling.play())  # (a loop while she drives)
	_snort = _player(SNORT, SNORT_DB, 30.0)
	_check_open.call_deferred()


func _player(stream: AudioStream, db: float, reach: float) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.stream = stream
	p.volume_db = db
	p.unit_size = 5.0
	p.max_distance = reach
	p.bus = &"Effects"
	_cart.add_child(p)
	p.position = Vector3(0, 1.2, -2.0)  # (by the horse)
	return p


## A visit today: the road's open, and it's the morning after it opened or every second one after.
func visiting() -> bool:
	if _open_day < 0:
		return false
	var since := _day - _open_day + (1 if Village.stat(&"trader_sooner") > 0.0 else 0)  # (the flagstones)
	if Village.stat(&"trader_daily") > 0.0:  # (she stays at the inn's guest room)
		return since >= 1
	return since >= 1 and since % 2 == 1


## Parked by the stall: the market's kinder rates and her specials.
func is_in() -> bool:
	return visiting() and DayNight.time >= PARKED and DayNight.time < PACK_UP


## Which visit this is (1, 2, ...): picks her specials.
func visit_number() -> int:
	return maxi((_day - _open_day + 1) / 2, 1)


## The specials on her cart this visit (one of each kind), not yet bought.
func specials() -> Array:
	var out := []
	for kind: StringName in [&"dog", &"decoration", &"lantern"]:
		var of_kind := SPECIALS.filter(func(s: Array) -> bool: return s[1] == kind)
		var s: Array = of_kind[visit_number() % of_kind.size()]
		if not _owned.has(s[0]):
			out.append(s)
	return out


func owns(id: StringName) -> bool:
	return _owned.has(id)


## Buys special `id` (if she has it today and you can pay) and puts it to use.
func buy(id: StringName) -> bool:
	for s in specials():
		if s[0] == id and Inventory.spend(s[4]):
			_owned[id] = true
			_apply(s)
			SaveGame.mark_dirty()
			return true
	return false


## Fills the market panel's specials row (MarketPanel calls it while she's in).
func fill_specials(box: Control) -> void:
	var title := Label.new()
	title.text = "On the trader's cart today"
	title.add_theme_font_override("font", MapView.map_font(true))
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", NoticeboardPanel.GOLD)
	box.add_child(title)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	box.add_child(row)
	var list := specials()
	if list.is_empty():
		var none := Label.new()
		none.text = "You've bought everything she has this time. Come back on her next visit."
		none.add_theme_color_override("font_color", Color(NoticeboardPanel.GOLD, 0.75))
		row.add_child(none)
	for s in list:
		var b := Button.new()
		var cost := PackedStringArray()
		for item in s[4]:
			cost.append("%d %s" % [s[4][item], Items.display_name(item)])
		b.text = "%s\n%s\n%s" % [s[2], s[3], ", ".join(cost)]
		b.tooltip_text = s[3]
		b.disabled = not Inventory.has_all(s[4])
		b.add_theme_font_override("font", MapView.map_font(false))
		b.add_theme_font_size_override("font_size", 14)
		b.custom_minimum_size = Vector2(220, 0)
		b.pressed.connect(func() -> void:
			if buy(s[0]):
				Sfx.play(MarketPanel.TRADE_SOUND, randf_range(0.95, 1.05), MarketPanel.TRADE_DB)
				var panel := get_tree().get_first_node_in_group("market_panel")
				if panel:
					panel.call("_refresh"))
		row.add_child(b)


func _apply(s: Array) -> void:
	match s[1]:
		&"dog":
			Companion.set_collar(s[0])
		&"lantern":
			Lamps.set_glass(s[0])
		&"decoration":
			Projects.set_done(s[0], true)


func _check_open() -> void:
	if _open_day < 0 and Projects.is_done(&"retaining_wall"):
		_open_day = _day
		SaveGame.mark_dirty()


func _process(delta: float) -> void:
	if _path.is_empty():
		_build_path()
	var t := DayNight.time
	var show := visiting() and t >= SET_OFF and t < GONE and not _path.is_empty()
	_cart.visible = show
	_person.visible = show
	if not show:
		if _rolling.playing:
			_rolling.stop()
		return
	var k := 1.0  # along the path: 0 the road's end, 1 parked
	if t < PARKED:
		k = (t - SET_OFF) / (PARKED - SET_OFF)
	elif t >= PACK_UP:
		k = 1.0 - (t - PACK_UP) / (GONE - PACK_UP)
	k = smoothstep(0.0, 1.0, clampf(k, 0.0, 1.0))
	var leaving := t >= PACK_UP
	var moving := t < PARKED or leaving
	var at := _along(k)
	var ahead := _along(clampf(k + (-0.01 if leaving else 0.01), 0.0, 1.0))
	var dir := (ahead - at).normalized() if ahead.distance_to(at) > 0.001 else Vector2(0, 1)
	var pos := Vector3(at.x, _ground(at), at.y)
	# the models face -Z (Blender -Y): the horse leads along `dir`
	var yaw := atan2(-dir.x, -dir.y)
	_cart.global_transform = Transform3D(Basis(Vector3.UP, yaw), pos)
	if moving:  # she rides on the cart's front
		_person.global_transform = Transform3D(Basis(Vector3.UP, yaw), pos + Basis(Vector3.UP, yaw) * Vector3(0.3, 0.75, -0.8))
	else:  # parked: standing beside it, facing the square
		var side := Basis(Vector3.UP, yaw) * Vector3(1.4, 0.0, -1.2)
		var spot := pos + side
		spot.y = _ground(Vector2(spot.x, spot.z))
		_person.global_transform = Transform3D(Basis(Vector3.UP, yaw + PI * 0.5), spot)
	_animate(delta, moving)
	if moving and not _rolling.playing:
		_rolling.play()
	elif not moving and _rolling.playing:
		_rolling.stop()
	_snort_in -= delta
	if not moving and _snort_in <= 0.0:
		_snort_in = randf_range(SNORT_GAP.x, SNORT_GAP.y)
		_snort.pitch_scale = randf_range(0.93, 1.05)
		_snort.play()


func _animate(delta: float, moving: bool) -> void:
	_was_moving = move_toward(_was_moving, 1.0 if moving else 0.0, delta * 2.0)
	var phase := Time.get_ticks_msec() / 1000.0 * 6.0
	var swing := sin(phase) * 0.5 * _was_moving
	for leg in [&"LegFL", &"LegBR"]:
		_pose_part(leg, Basis.from_euler(Vector3(swing, 0, 0)))
	for leg in [&"LegFR", &"LegBL"]:
		_pose_part(leg, Basis.from_euler(Vector3(-swing, 0, 0)))
	_pose_part(&"Head", Basis.from_euler(Vector3(sin(phase * 0.5) * 0.08 * _was_moving + (1.0 - _was_moving) * 0.35 * (0.5 + 0.5 * sin(phase * 0.1)), 0, 0)))
	var roll := phase * 0.6 * _was_moving
	for w in [&"WheelL", &"WheelR"]:
		_pose_part(w, Basis.from_euler(Vector3(roll, 0, 0)))


func _pose_part(part: StringName, turn: Basis) -> void:
	if _parts.has(part):
		_parts[part].transform = Transform3D(_rest[part].basis * turn, _rest[part].origin)


## The road east from its far end, then through the village to the parking spot.
func _build_path() -> void:
	for r in WorldMap.roads():
		if r["id"] == &"east_road":
			var road: PackedVector2Array = (r["pts"] as PackedVector2Array).duplicate()
			if road.is_empty():
				return
			if road[0].distance_to(WorldMap.VILLAGE_CENTER) < road[road.size() - 1].distance_to(WorldMap.VILLAGE_CENTER):
				road.reverse()  # (from the far end)
			_path = road
			for p in TOWN_WAY:
				_path.append(p)
			_path.append(PARK)


## The point a share `k` of the way along the path (by length).
func _along(k: float) -> Vector2:
	var total := 0.0
	for i in range(1, _path.size()):
		total += _path[i].distance_to(_path[i - 1])
	var want := total * k
	for i in range(1, _path.size()):
		var d := _path[i].distance_to(_path[i - 1])
		if want <= d:
			return _path[i - 1].lerp(_path[i], want / maxf(d, 0.001))
		want -= d
	return _path[_path.size() - 1]


func _ground(at: Vector2) -> float:
	var terrain := get_tree().get_first_node_in_group("terrain") as Terrain3D
	var h: float = terrain.data.get_height(Vector3(at.x, 0, at.y)) if terrain and terrain.data else NAN
	return 0.0 if is_nan(h) else h


func to_dict() -> Dictionary:
	var owned: Array[String] = []
	for id in _owned:
		owned.append(String(id))
	return {"day": _day, "open_day": _open_day, "owned": owned}


func from_dict(d: Dictionary) -> void:
	_day = int(d.get("day", 0))
	_open_day = int(d.get("open_day", -1))
	_owned.clear()
	for id in d.get("owned", []):
		_owned[StringName(id)] = true
