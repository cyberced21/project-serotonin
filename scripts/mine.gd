class_name Mine
extends Node3D
## The old Greystone mine (plans/mine.md): three levels dug out of the rock far under the quarry,
## each a hand-drawn grid of cells (MineLayout) built by a MineLevel. You go in by the mouth on the
## quarry floor (MineMouth) once it's shored up, and dig your way through: break through a dig face
## and the cell behind opens, for good. Deeper levels wait for the lift (a noticeboard project),
## a flooded tunnel for the pump, a roof fall for timber supports.
## Keeps which cells are open (saved), which were opened since the last dawn (no frames and lamps
## yet: the prospector shores them overnight) and which obstacles you've seen (they put their
## projects on the board).

signal changed

## How far below the world each level's floor is.
const LEVEL_Y: Array[float] = [-40.0, -60.0, -80.0]
## The projects that shore each level (frames and lamps) and that bring the lift down to it.
const SHORING: Array[StringName] = [&"mine_shoring", &"mine_shoring_2", &"mine_shoring_3"]
const LIFT: Array[StringName] = [&"", &"mine_lift", &"mine_lift_3"]
const SUPPORTS := &"mine_supports"
const RAILS := &"mine_rails"
const PUMP := &"mine_pump"
## Chance a dig face that gives way has a trophy in it (a fossil higher up, a geode deeper),
## more with the prospector's assay table (mine_finds).
const FIND_CHANCE := 0.1
## What Edda writes when she hears what you found: a chamber's first on each level, the stream,
## the crystals, the obstacles, the lift reaching a level.
const NEWS := {
	"C": "You've opened a chamber on %s! The old miners only dug those where the rock was worth it. Have a good look round.",
	"S": "You found the stream! Mind your boots. The water's cold and clean down there; the old miners drank it.",
	"K": "Crystal caverns! I've only ever heard them talked about. If you can spare a little piece, I'd love to see it.",
	"X": "There's a roof fall on the first level, isn't there? Don't dig at it. Timber first, then we'll clear it.",
	"F": "Flooded? That'll be the old drainage gone. A pump will sort it, and you'll find the stream beyond.",
	"lift": "The lift goes down to %s now. Take a lamp, and ring the bell twice if you get stuck.",
}
const FADE_OUT := 0.6
const FADE_IN := 0.8

var levels: Array[MineLevel] = []
## The level you're on (-1: up in the world).
var here := -1
var _open: Array[Dictionary] = []
var _fresh: Array[Dictionary] = []
var _seen: Dictionary[StringName, bool] = {}
## What Edda hasn't written to you about yet (HomeNotes takes them, oldest first), and what she has.
var _news: Array[String] = []
var _told: Dictionary[String, bool] = {}
var map: MineMap
var _travelling := false
## The ride under way (tests and tools watch it), or null.
var riding: MineRide


func _ready() -> void:
	add_to_group("mine")
	for i in MineLayout.LEVELS.size():
		_open.append({})
		_fresh.append({})
		var level := MineLevel.new()
		level.name = "Level%d" % (i + 1)
		level.n = i
		level.mine = self
		var size := MineLayout.size(i)
		var c := WorldMap.QUARRY_CENTER
		level.position = Vector3(c.x - size.x * MineLayout.CELL / 2, LEVEL_Y[i], c.y - size.y * MineLayout.CELL / 2)
		level.visible = false
		add_child(level)
		levels.append(level)
	map = MineMap.new()
	map.mine = self
	add_child(map)
	_reset_open()
	SaveGame.register(&"mine", self)
	Projects.changed.connect(_refresh_all)
	DayNight.day_broke.connect(_shore_fresh)
	_refresh_all()


func _reset_open() -> void:
	for i in _open.size():
		_open[i].clear()
		_fresh[i].clear()
	for c in MineLayout.cells_of(0, "E"):
		_open[0][c] = true
	_seen.clear()
	_news.clear()
	_told.clear()


func _process(_delta: float) -> void:
	var player := get_tree().get_first_node_in_group("player") as Node3D
	var now := level_at(player.global_position) if player else -1
	if now != here:
		here = now
		for i in levels.size():
			levels[i].visible = i == here


## Which level a world position is on (-1: not in the mine).
func level_at(p: Vector3) -> int:
	for i in LEVEL_Y.size():
		if p.y > LEVEL_Y[i] - 2.0 and p.y < LEVEL_Y[i] + MineLayout.HEIGHT + 2.0:
			return i
	return -1


# --- the cells ---------------------------------------------------------------------------------

func is_open(n: int, c: Vector2i) -> bool:
	if not MineLayout.is_cell(n, c):
		return false
	if n > 0 and MineLayout.at(n, c) == "L":  # where the lift stops, once it reaches this far
		return lift_reaches(n)
	return _open[n].has(c)


## Open, and not a collapse or a flood still in the way.
func is_passable(n: int, c: Vector2i) -> bool:
	if not is_open(n, c):
		return false
	match MineLayout.at(n, c):
		"X":
			return Projects.is_done(SUPPORTS)
		"F":
			return Projects.is_done(PUMP)
	return true


func is_shored(n: int) -> bool:
	return Projects.is_done(SHORING[n])


func is_fresh(n: int, c: Vector2i) -> bool:
	return _fresh[n].has(c)


func lift_reaches(n: int) -> bool:
	return n == 0 or Projects.is_done(LIFT[n])


func open_count(n: int) -> int:
	var count := 0
	for c in MineLayout.cells(n):
		if is_open(n, c):
			count += 1
	return count


## How many layers a dig face gives way after.
func give_way_layers() -> int:
	return MineLevel.GIVE_WAY


## A dig face gave way: the cell behind it is open (fresh until dawn).
func on_broke_through(n: int, c: Vector2i, at: Vector3) -> void:
	open_cell(n, c)
	if randf() < FIND_CHANCE * (1.0 + Village.stat(&"mine_finds")):
		Trophies.found(&"geode" if randf() < 0.3 + 0.3 * n else &"fossil", at)
	var k := MineLayout.at(n, c)
	if k in ["C", "S", "K"]:
		_tell("%s%d" % [k, n], NEWS[k] % MineLayout.LEVELS[n]["title"].to_lower() if k == "C" else NEWS[k])


func open_cell(n: int, c: Vector2i) -> void:
	if _open[n].has(c):
		return
	_open[n][c] = true
	_fresh[n][c] = true
	SaveGame.mark_dirty()
	_refresh.call_deferred(n)  # (not while the panel that gave way is still in its hit)
	changed.emit()


## An obstacle came into view: its project goes up on the board.
func saw_obstacle(_n: int, kind: String) -> void:
	var need := &"mine:collapse" if kind == "X" else &"mine:flood"
	if not _seen.has(need):
		_seen[need] = true
		SaveGame.mark_dirty()
		Projects.changed.emit.call_deferred()
		_tell(kind, NEWS[kind])


## Something for Edda to write to you about, once.
func _tell(key: String, text: String) -> void:
	if _told.has(key):
		return
	_told[key] = true
	_news.append(text)
	SaveGame.mark_dirty()


## For HomeNotes: the oldest news Edda hasn't written about yet ("" for none).
func take_news() -> String:
	if _news.is_empty():
		return ""
	SaveGame.mark_dirty()
	return _news.pop_front()


## For the survey board (MineMap): the ores a hidden cell's rock runs to, from its level's depth.
func ore_hint(n: int, _c: Vector2i) -> String:
	var row: Array = OreWall.RICHNESS[mini(int(MineLayout.LEVELS[n]["richness"]) + 1, OreWall.RICHNESS.size() - 1)]
	var names: Array[String] = []
	for kind: int in row:
		var item: StringName = OreWall.ORES[kind]["item"]
		var nm := Items.display_name(item).to_lower().replace(" ore", "")
		if nm not in names:
			names.append(nm)
	return ", ".join(names)


## For Projects: whether a "mine:" need is met (the shaft dug into, an obstacle seen).
func need_met(need: StringName) -> bool:
	if need == &"mine:shaft":
		return not MineLayout.cells_of(0, "L").is_empty() and is_open(0, MineLayout.cells_of(0, "L")[0])
	return _seen.has(need)


func _shore_fresh() -> void:
	var any := false
	for f in _fresh:
		any = any or not f.is_empty()
		f.clear()
	if any:
		SaveGame.mark_dirty()
		_refresh_all()


func _refresh_all() -> void:
	for i in levels.size():
		_refresh(i)
		if i > 0 and lift_reaches(i):
			_tell("lift%d" % i, NEWS["lift"] % MineLayout.LEVELS[i]["title"].to_lower())


func _refresh(n: int) -> void:
	levels[n].refresh()
	_add_spots(n)


# --- getting about -------------------------------------------------------------------------------

## The world position of a cell's middle, on its floor.
func cell_position(n: int, c: Vector2i) -> Vector3:
	return levels[n].global_transform * MineLevel.centre(c)


## The things you press E at on level n: the way out, the lift.
func _add_spots(n: int) -> void:
	var dress := levels[n].dressing()
	if n == 0:
		for c in MineLayout.cells_of(0, "E"):
			var back := _wall_dir(0, c)
			var door_at := MineLevel.centre(c) + Vector3(back.x, 0, back.y) * (MineLayout.CELL / 2 - 0.3)
			var door := Prop.new()
			door.model = MineLevel.DOOR
			door.own_materials = true
			door.collide = false
			door.position = door_at
			door.rotation.y = atan2(back.x, back.y)
			dress.add_child(door)
			var spot := MineSpot.make(Vector3(1.6, 2.4, 0.8), func() -> String: return "E  Back up to the quarry", leave)
			spot.position = door_at - Vector3(back.x, 0, back.y) * 0.3
			dress.add_child(spot)
	if Projects.is_done(RAILS):
		for c in MineLayout.cells_of(n, "R"):
			if is_open(n, c):
				_add_rail_stop(n, c)
	for c in MineLayout.cells_of(n, "L"):
		if not is_open(n, c) or not Projects.is_done(LIFT[1]):
			continue
		for piece: Array in [[MineLevel.POSTS, Vector3.ZERO, false], [MineLevel.BOARDWALK, Vector3(0, 0.02, 0), false],
				[MineLevel.CHAIN, Vector3(0, MineLayout.HEIGHT, 0), true]]:  # the cage, its floor, the rope up
			var p := Prop.new()
			p.model = piece[0]
			p.own_materials = piece[2]
			p.collide = false
			p.position = MineLevel.centre(c) + piece[1]
			dress.add_child(p)
		var spot := MineSpot.make(Vector3(2.0, 2.4, 2.0), _lift_prompt.bind(n), _ride_lift.bind(n))
		spot.position = MineLevel.centre(c)
		spot.collision_layer = LookObject.LAYER  # (not solid: you stand in the cage)
		dress.add_child(spot)


## The rail stop on level n: the rails through it, the cart, and the ride.
func _add_rail_stop(n: int, c: Vector2i) -> void:
	var dress := levels[n].dressing()
	var axis := _rail_axis(n, c)
	var o := MineLevel.centre(c)
	for k in [-1.0, 0.0, 1.0]:
		var rail := Prop.new()
		rail.model = load("res://models/mine/rail.glb")
		rail.own_materials = true
		rail.collide = false
		rail.position = o + axis * k * 2.0 + Vector3.UP * 0.02
		rail.rotation.y = 0.0 if axis == Vector3.RIGHT else PI / 2
		dress.add_child(rail)
	var cart := Prop.new()
	cart.model = load("res://models/mine/cart_tall.glb")
	cart.own_materials = true
	cart.collide = false  # (E reaches the stop through it)
	cart.position = o
	cart.rotation.y = PI / 2 if axis == Vector3.RIGHT else 0.0
	dress.add_child(cart)
	var spot := MineSpot.make(Vector3(1.6, 1.6, 1.6), _ride_prompt.bind(n), ride.bind(n))
	spot.position = o
	dress.add_child(spot)


## The way the rails run through a rail stop: along x if the tunnel goes on that way, else z.
func _rail_axis(n: int, c: Vector2i) -> Vector3:
	return Vector3.RIGHT if MineLayout.is_cell(n, c + Vector2i(1, 0)) or MineLayout.is_cell(n, c + Vector2i(-1, 0)) else Vector3.BACK


## Where the cart goes from level n: from the top, down to the deepest level the lift reaches
## whose rail stop is dug out; from below, back up to the top. -1: nowhere yet.
func ride_to(n: int) -> int:
	if n != 0:
		return 0 if is_open(0, MineLayout.cells_of(0, "R")[0]) else -1
	for i in range(levels.size() - 1, 0, -1):
		var stop: Array[Vector2i] = MineLayout.cells_of(i, "R")
		if lift_reaches(i) and not stop.is_empty() and is_open(i, stop[0]):
			return i
	return -1


func _ride_prompt(n: int) -> String:
	var to := ride_to(n)
	if to < 0:
		return "The rails run on down. Dig out the rail stop on the level below first."
	return "E  Ride the minecart %s to %s" % ["down" if to > n else "up", MineLayout.LEVELS[to]["title"].to_lower()]


## The ride: the cart rattles off down its tunnel, and you climb out at the far stop.
func ride(n: int) -> void:
	var to := ride_to(n)
	if to < 0 or _travelling:
		return
	_travelling = true
	var player := get_tree().get_first_node_in_group("player") as Node3D
	player.call("set_cutscene", true)
	var fade := _fade()
	var rect := fade.get_child(0) as ColorRect
	await fade.create_tween().tween_property(rect, "modulate:a", 1.0, 0.4).finished
	var trip := MineRide.make(to < n)
	add_child(trip)
	riding = trip
	await fade.create_tween().tween_property(rect, "modulate:a", 0.0, 0.6).finished
	if not trip.done:  # (it may have been skipped while the fade was still clearing)
		await trip.finished
	await fade.create_tween().tween_property(rect, "modulate:a", 1.0, 0.5).finished
	var stop: Vector2i = MineLayout.cells_of(to, "R")[0]
	var beside := _rail_axis(to, stop).cross(Vector3.UP)  # (climbed out beside the cart)
	var at := cell_position(to, stop) + Vector3.UP * 0.1 + beside * 1.2
	player.call("teleport", at, at + beside * 3.0 + Vector3.UP * 1.5)
	var dog := get_tree().get_first_node_in_group("dog") as Node3D
	if dog:
		dog.global_position = at + Vector3(0.9, 0, 0)
		dog.reset_physics_interpolation()
	trip.queue_free()
	riding = null
	(player.get("camera") as Camera3D).make_current()
	Biome.settle(at)
	await get_tree().create_timer(0.3).timeout
	await fade.create_tween().tween_property(rect, "modulate:a", 0.0, FADE_IN).finished
	fade.queue_free()
	player.call("set_cutscene", false)
	_travelling = false


## The first direction from cell c into solid rock (where the way-out door goes).
func _wall_dir(n: int, c: Vector2i) -> Vector2i:
	for d in MineLayout.DIRS:
		if not MineLayout.is_cell(n, c + d):
			return d
	return Vector2i(0, 1)


## Where the lift goes from level n: the next level down it reaches, else back to the top.
func _lift_next(n: int) -> int:
	for i in range(n + 1, levels.size()):
		if lift_reaches(i):
			return i
	return 0 if n != 0 else -1


func _lift_prompt(n: int) -> String:
	var to := _lift_next(n)
	if to < 0:
		return "The lift: it only goes this far for now"
	return "E  Ride the lift %s to %s" % ["down" if to > n else "up", MineLayout.LEVELS[to]["title"].to_lower()]


func _ride_lift(n: int) -> void:
	var to := _lift_next(n)
	if to >= 0:
		go_to(to, MineLayout.cells_of(to, "L")[0])


## In from the quarry: down to the first level's way in.
func enter() -> void:
	var c: Vector2i = MineLayout.cells_of(0, "E")[0]
	go_to(0, c)


## Out to the quarry floor, in front of the mouth.
func leave() -> void:
	var mouth := get_tree().get_first_node_in_group("mine_mouth") as MineMouth
	if mouth == null:
		return
	var at := mouth.doorstep()
	_travel(at, at + (at - mouth.global_position).normalized() * 4.0)


## To cell c of level n, facing into the level.
func go_to(n: int, c: Vector2i) -> void:
	var at := cell_position(n, c) + Vector3.UP * 0.1
	var out := _wall_dir(n, c)
	var look := at - Vector3(out.x, 0, out.y) * 3.0 + Vector3.UP * 1.5
	_travel(at, look)


func _travel(at: Vector3, look_at_point: Vector3) -> void:
	if _travelling:
		return
	_travelling = true
	var player := get_tree().get_first_node_in_group("player") as Node3D
	player.call("set_cutscene", true)
	var fade := _fade()
	var rect := fade.get_child(0) as ColorRect
	await fade.create_tween().tween_property(rect, "modulate:a", 1.0, FADE_OUT).finished
	player.call("teleport", at, look_at_point)
	var dog := get_tree().get_first_node_in_group("dog") as Node3D
	if dog:
		dog.global_position = at + (player as Node3D).global_basis.x * 0.9
		dog.reset_physics_interpolation()
	Biome.settle(at)
	await get_tree().create_timer(0.35).timeout
	await fade.create_tween().tween_property(rect, "modulate:a", 0.0, FADE_IN).finished
	fade.queue_free()
	player.call("set_cutscene", false)
	_travelling = false


func _fade() -> CanvasLayer:
	var layer := CanvasLayer.new()
	layer.layer = 90
	var rect := ColorRect.new()
	rect.color = Color(0.02, 0.02, 0.03)
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.modulate.a = 0.0
	layer.add_child(rect)
	get_tree().root.add_child(layer)
	return layer


# --- saving --------------------------------------------------------------------------------------

func to_dict() -> Dictionary:
	var open := []
	var fresh := []
	for i in _open.size():
		open.append(_open[i].keys().map(func(c: Vector2i) -> Array: return [c.x, c.y]))
		fresh.append(_fresh[i].keys().map(func(c: Vector2i) -> Array: return [c.x, c.y]))
	return {"open": open, "fresh": fresh, "seen": _seen.keys(), "news": _news.duplicate(), "told": _told.keys()}


func from_dict(d: Dictionary) -> void:
	_reset_open()
	var open: Array = d.get("open", [])
	var fresh: Array = d.get("fresh", [])
	for i in mini(open.size(), _open.size()):
		for c: Array in open[i]:
			_open[i][Vector2i(int(c[0]), int(c[1]))] = true
	for i in mini(fresh.size(), _fresh.size()):
		for c: Array in fresh[i]:
			_fresh[i][Vector2i(int(c[0]), int(c[1]))] = true
	for k in d.get("seen", []):
		_seen[StringName(k)] = true
	for t in d.get("news", []):
		_news.append(String(t))
	for k in d.get("told", []):
		_told[String(k)] = true
	if is_inside_tree() and not levels.is_empty():
		_refresh_all()
