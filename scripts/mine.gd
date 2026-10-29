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
const PUMP := &"mine_pump"
const FADE_OUT := 0.6
const FADE_IN := 0.8

var levels: Array[MineLevel] = []
## The level you're on (-1: up in the world).
var here := -1
var _open: Array[Dictionary] = []
var _fresh: Array[Dictionary] = []
var _seen: Dictionary[StringName, bool] = {}
var _travelling := false


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
func on_broke_through(n: int, c: Vector2i, _at: Vector3) -> void:
	open_cell(n, c)


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
	for c in MineLayout.cells_of(n, "L"):
		if not is_open(n, c) or not Projects.is_done(LIFT[1]):
			continue
		var cage := Prop.new()
		cage.model = MineLevel.POSTS
		cage.collide = false
		cage.position = MineLevel.centre(c)
		dress.add_child(cage)
		var spot := MineSpot.make(Vector3(2.0, 2.4, 2.0), _lift_prompt.bind(n), _ride_lift.bind(n))
		spot.position = MineLevel.centre(c)
		spot.collision_layer = LookObject.LAYER  # (not solid: you stand in the cage)
		dress.add_child(spot)


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
	return {"open": open, "fresh": fresh, "seen": _seen.keys()}


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
	if is_inside_tree() and not levels.is_empty():
		_refresh_all()
