class_name DiceGame
extends Node3D
## Dice at the tavern (plans/tavern.md): sit down at the dice table (its DiceSeat1) while the
## tavern's open, and a villager who's free comes over to play you (DiceSeat2) at Hound's Luck
## (DiceRules), with real dice (Die) thrown into a felt-lined tray. Played for fun: the chalkboard
## on the wall keeps the tally of wins against each villager (saved, "dice").
## The panel frees the mouse: Roll, Stop and bank, Leave. Standing up (a movement key) leaves too.
## The Tavern makes one and keeps it on the dice table of whichever tier is showing.

signal chose(what: String)

## The tray on the table: inside size, rim height; the table top above the seats' markers.
const TRAY := 0.6
const RIM := 0.05
const TABLE_TOP := 0.735
## Seconds: a throw is read once everything's settled; cocked dice get a nudge after SETTLE_WAIT,
## and after SETTLE_GIVE_UP whatever's nearest up counts. A villager thinks THINK before choosing.
const SETTLE_WAIT := 3.0
const SETTLE_GIVE_UP := 7.0
const THINK := 1.1
## How long you wait for someone to come and play before giving up on it.
const COME_OVER := 15.0
## Dice landing in the tray (audio/tavern/SOURCES.md).
const DICE_SOUND := preload("res://audio/tavern/dice.wav")
const DICE_DB := -8.0
const FELT := Color("2f5a3c")
const RIM_WOOD := Color("7a5236")
const CHALK := Color(0.93, 0.92, 0.86)
## What they say when you win, and when they do.
const LINES_YOU_WIN := ["Best of three, then!", "Beginner's luck. Again?", "Well rolled. I'll have you next time."]
const LINES_THEY_WIN := ["Ha! The hound smiles on me tonight.", "Another? I'm feeling lucky.", "Don't look so glum, it's only dice."]

var playing := false
var opponent: Villager
## Tests: no throws and no waiting (the dice are rolled as numbers), and your choices made by
## `you_play` (a DiceRules style) instead of the buttons.
var fast := false
var you_play: Dictionary = {}
var rng := RandomNumberGenerator.new()
var scores: Array[int] = [0, 0]  # you, them
var _tally: Dictionary = {}  # opponent's building id -> [your wins, theirs]
var _turn_points := 0
var _left := DiceRules.DICE
var _dice: Array[Die] = []
var _kept: Array[Die] = []
var _seat1: Marker3D
var _seat2: Marker3D
var _tray: StaticBody3D
var _clatter: AudioStreamPlayer3D
var _was_sat := false
var _board: Label3D
var _game := 0  # bumped by every start and leave, so a game left half-way stops
var _waiting := false  # sat down: looking for someone to play

# the panel
var _layer: CanvasLayer
var _title: Label
var _score_line: Label
var _turn_line: Label
var _say: Label
var _roll_button: Button
var _bank_button: Button
var _again_button: Button
var _closed_msec := -100000


func _ready() -> void:
	add_to_group("dice_game")
	add_to_group("modal_panel")
	rng.randomize()
	_build_tray()
	for i in DiceRules.DICE:
		var d := Die.new()
		d.name = "Die%d" % (i + 1)
		add_child(d)
		d.freeze = true
		d.position = _row_spot(0, i)
		_dice.append(d)
	_build_panel()
	_clatter = AudioStreamPlayer3D.new()
	_clatter.stream = DICE_SOUND
	_clatter.bus = &"SFX"
	_clatter.volume_db = DICE_DB
	_clatter.unit_size = 2.0
	add_child(_clatter)
	SaveGame.register(&"dice", self)


## Sets the table: the two dice seats of the tier on show (the tray goes between them, the
## chalkboard at the Tally marker).
func place(seat1: Marker3D, seat2: Marker3D, tally: Marker3D) -> void:
	_seat1 = seat1
	_seat2 = seat2
	var across := seat2.global_position - seat1.global_position
	across.y = 0.0
	var mid := (seat1.global_position + seat2.global_position) * 0.5
	global_transform = Transform3D(Basis(across.normalized(), Vector3.UP, across.normalized().cross(Vector3.UP)),
		mid + Vector3.UP * TABLE_TOP)
	if tally:
		if _board == null:
			_board = Label3D.new()
			_board.name = "Tally"
			_board.pixel_size = 0.0016
			_board.font_size = 40
			_board.outline_size = 0
			_board.modulate = CHALK
			_board.double_sided = false
			_board.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
			add_child(_board)
		_board.top_level = true
		_board.global_transform = tally.global_transform
		_refresh_board()


func is_open() -> bool:
	return _layer.visible


func just_closed() -> bool:
	return Time.get_ticks_msec() - _closed_msec < 250


## The tally against villager `id`: [your wins, theirs].
func tally(id: StringName) -> Array:
	return _tally.get(id, [0, 0])


func _process(_delta: float) -> void:
	if _seat1 == null:
		return
	var player := get_tree().get_first_node_in_group("player")
	var sat: bool = player != null and player.get("seat") == _seat1
	if (playing or _waiting or _layer.visible) and not sat:  # stood up: that's the game (or the panel)
		leave()
	elif playing and is_instance_valid(opponent) and opponent.get("_seat") != _seat2:
		var who := opponent.display_name()
		leave()  # (their bedtime, say)
		_open_panel()
		_title.text = "Hound's Luck"
		_turn_line.text = ""
		_say.text = "%s has to get home. Another night." % who
		_set_buttons(false, false, false)
	elif sat and not _was_sat and not playing and not _waiting:  # just sat down
		_sit_down(player)
	_was_sat = sat


## You've sat down at the table: find someone to play.
func _sit_down(player: Node) -> void:
	_waiting = true
	_open_panel()
	_title.text = "Hound's Luck"
	_score_line.text = ""
	_turn_line.text = "First to %d. Ones are 100, fives 50, three of a kind the face times 100." % DiceRules.TARGET
	_set_buttons(false, false, false)
	if player.has_method("face_point"):
		player.face_point(global_position, 0.6)
	var tavern := get_tree().get_first_node_in_group("tavern")
	if tavern == null or not tavern.call("is_open"):
		_say.text = "Nobody about to play with. Come back of an evening."
		_waiting = false
		return
	var v := _free_villager()
	if v == null:
		_say.text = "Nobody's free to play just now."
		_waiting = false
		return
	_say.text = "%s's coming over..." % v.display_name()
	v.join_dice(_seat2)
	var game := _game
	var t := 0.0
	while t < COME_OVER and not v.at_seat():
		await get_tree().process_frame
		t += get_process_delta_time()
		if game != _game:
			return
	_waiting = false
	if not v.at_seat():
		v.leave_dice()
		_say.text = "%s's been waylaid. Another time." % v.display_name()
		return
	start(v)


## Plays a game against `v` (already sat across the table, or not: tests).
func start(v: Villager) -> void:
	_game += 1
	var game := _game
	opponent = v
	playing = true
	scores = [0, 0]
	_open_panel()
	_title.text = "Hound's Luck with %s" % v.display_name()
	_say.text = "You go first."
	var who := 0
	while playing and game == _game:
		await _play_turn(who)
		if game != _game:
			return
		if scores[who] >= DiceRules.TARGET:
			_finish(who == 0)
			return
		who = 1 - who


func leave() -> void:
	_game += 1
	_waiting = false
	if is_instance_valid(opponent):
		opponent.leave_dice()
	opponent = null
	playing = false
	_gather_dice()
	if _layer.visible:
		_layer.visible = false
		_closed_msec = Time.get_ticks_msec()
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _finish(you_won: bool) -> void:
	playing = false
	var id := opponent.building.def.id
	var t: Array = tally(id).duplicate()
	t[0 if you_won else 1] += 1
	_tally[id] = t
	SaveGame.mark_dirty()
	_refresh_board()
	_refresh_scores()
	if you_won:
		_say.text = "You win! %s: \"%s\"" % [opponent.display_name(), LINES_YOU_WIN[rng.randi() % LINES_YOU_WIN.size()]]
	else:
		_say.text = "%s wins. \"%s\"" % [opponent.display_name(), LINES_THEY_WIN[rng.randi() % LINES_THEY_WIN.size()]]
		opponent.cheer()
	_turn_line.text = ""
	_set_buttons(false, false, true)


func _play_turn(who: int) -> void:
	var game := _game
	_turn_points = 0
	_left = DiceRules.DICE
	_kept.clear()
	var name := "You" if who == 0 else opponent.display_name()
	while game == _game:
		_refresh_scores()
		_turn_line.text = "%s: %d this turn" % [name, _turn_points] if who == 1 else "Your turn: %d so far" % _turn_points
		var roll_now := true
		if _turn_points > 0:  # roll on, or stop?
			roll_now = await _decide(who)
			if game != _game:
				return
		if not roll_now:
			scores[who] += _turn_points
			_say.text = ("You bank %d." if who == 0 else name + " stops and banks %d.") % _turn_points
			await _pause(1.0)
			break
		var roll := await _throw(who)
		if game != _game:
			return
		var s := DiceRules.score(roll)
		if s["points"] == 0:
			_say.text = ("Bust! You lose %d." if who == 0 else "Bust! " + name + " loses %d.") % _turn_points
			_turn_points = 0
			await _pause(1.4)
			break
		_turn_points += s["points"]
		var keep: Array[Die] = []
		var rolled := _rolled_dice()
		for i: int in s["keep"]:
			keep.append(rolled[i])
		_left -= keep.size()
		_say.text = "%s %d." % ["Scores" if who == 1 else "That's", s["points"]]
		_set_aside(keep, who)
		if _left == 0:  # hot dice: all five back
			_left = DiceRules.DICE
			_kept.clear()
			_say.text += " All five score: roll them all again!"
		await _pause(0.6)
	_refresh_scores()
	_gather_dice()


## Roll on (true) or bank (false).
func _decide(who: int) -> bool:
	if who == 1:
		_set_buttons(false, false, false)
		await _pause(THINK)
		var mine: int = scores[1]
		return DiceRules.wants_roll(DiceRules.style_of(opponent.building.def.id), _turn_points, _left, mine, scores[0])
	if fast and not you_play.is_empty():
		return DiceRules.wants_roll(you_play, _turn_points, _left, scores[0], scores[1])
	_set_buttons(true, true, false)
	_roll_button.text = "Roll %d" % _left if _left < DiceRules.DICE else "Roll all five"
	var game := _game
	var what: String = await chose
	_set_buttons(false, false, false)
	return what == "roll" and game == _game


## Throws the dice not set aside and reads them.
func _throw(who: int) -> Array[int]:
	var game := _game
	var dice := _rolled_dice()
	if fast:
		var roll := DiceRules.random_roll(dice.size(), rng)
		for i in dice.size():
			dice[i].position = Vector3(rng.randf_range(-0.2, 0.2), 0.04, rng.randf_range(-0.2, 0.2))
			dice[i].basis = Die.basis_showing(roll[i], rng.randf() * TAU)
		return roll
	if who == 0 and _turn_points == 0:
		await _first_roll_wait()
	if who == 1 and is_instance_valid(opponent):
		opponent.gesture_throw()
		await _pause(0.3)
	if game != _game:  # left the table meanwhile
		return []
	var side := -1.0 if who == 0 else 1.0
	for i in dice.size():
		var d := dice[i]
		d.freeze = false
		d.position = Vector3(side * (TRAY * 0.5 - 0.08), 0.16 + i * 0.03, rng.randf_range(-0.14, 0.14))
		d.basis = Basis.from_euler(Vector3(rng.randf() * TAU, rng.randf() * TAU, rng.randf() * TAU))
		d.throw(global_basis * Vector3(-side * rng.randf_range(0.9, 1.3), rng.randf_range(0.1, 0.4), rng.randf_range(-0.35, 0.35)),
			Vector3(rng.randf_range(-18, 18), rng.randf_range(-18, 18), rng.randf_range(-18, 18)))
	_clatter.pitch_scale = rng.randf_range(0.92, 1.08)
	_clatter.play()
	var t := 0.0
	var nudged := false
	while t < SETTLE_GIVE_UP:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		var all_still := dice.all(func(d: Die) -> bool: return d.settled())
		if all_still and dice.all(func(d: Die) -> bool: return d.face_up() != 0):
			break
		if all_still and t > SETTLE_WAIT * 0.5 and not nudged or t > SETTLE_WAIT and not nudged:
			nudged = true
			for d in dice:
				if d.face_up() == 0:
					d.nudge()
	var out: Array[int] = []
	for d in dice:
		out.append(_nearest_face(d))
		d.freeze = true
	return out


## The very first roll of your turn waits for the Roll button too.
func _first_roll_wait() -> void:
	if fast:
		return
	_set_buttons(true, false, false)
	_roll_button.text = "Roll all five"
	var game := _game
	while (await chose) != "roll" and game == _game:
		pass
	_set_buttons(false, false, false)


func _rolled_dice() -> Array[Die]:
	var out: Array[Die] = []
	for d in _dice:
		if not d in _kept:
			out.append(d)
	return out


func _nearest_face(d: Die) -> int:
	var best := -2.0
	var face := 1
	for normal: Vector3 in Die.FACES:
		var dot := (d.global_basis * normal).normalized().dot(Vector3.UP)
		if dot > best:
			best = dot
			face = Die.FACES[normal]
	return face


## Sets scoring dice aside in a row on the thrower's edge of the table, face up.
func _set_aside(keep: Array[Die], who: int) -> void:
	for d in keep:
		var face := _nearest_face(d)
		d.freeze = true
		var i := _kept.size()
		_kept.append(d)
		var to := Transform3D(Die.basis_showing(face), _row_spot(who, i))
		if fast:
			d.transform = to
		else:
			create_tween().tween_property(d, "transform", to, 0.35).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


## Where die `i` of the row on `who`'s edge of the table goes (outside the tray).
func _row_spot(who: int, i: int) -> Vector3:
	var side := -1.0 if who == 0 else 1.0
	return Vector3(side * (TRAY * 0.5 + 0.055), Die.SIZE * 0.5, -0.18 + i * 0.09)


func _gather_dice() -> void:
	_kept.clear()
	for i in _dice.size():
		_dice[i].freeze = true
		_dice[i].transform = Transform3D(Die.basis_showing(1 + i % 6, i * 0.7), Vector3(-0.1 + (i % 3) * 0.1, Die.SIZE * 0.5, -0.06 + (i / 3) * 0.12))


func _free_villager() -> Villager:
	var best: Villager = null
	var best_d := INF
	for b in get_tree().get_nodes_in_group("building"):
		var v := b.get_node_or_null("Villager") as Villager
		if v == null or b is Tavern or not v.free_for_dice():
			continue
		var d := v.global_position.distance_to(global_position)
		if d < best_d:
			best_d = d
			best = v
	return best


func _pause(seconds: float) -> void:
	if fast:
		return
	await get_tree().create_timer(seconds).timeout


# --- the tray and the board --------------------------------------------------------------

func _build_tray() -> void:
	_tray = StaticBody3D.new()
	_tray.name = "Tray"
	_tray.collision_layer = Die.LAYER
	_tray.collision_mask = 0
	add_child(_tray)
	var felt := StandardMaterial3D.new()
	felt.albedo_color = FELT
	felt.roughness = 1.0
	var wood := StandardMaterial3D.new()
	wood.albedo_color = RIM_WOOD
	wood.roughness = 0.8
	_tray_piece(Vector3(TRAY, 0.012, TRAY), Vector3(0, 0.006, 0), felt)
	var t := 0.025
	for sx in [-1.0, 1.0]:
		_tray_piece(Vector3(t, RIM, TRAY + 2.0 * t), Vector3(sx * (TRAY + t) * 0.5, RIM * 0.5, 0), wood)
		_tray_piece(Vector3(TRAY, RIM, t), Vector3(0, RIM * 0.5, sx * (TRAY + t) * 0.5), wood)
	# an invisible lid, high up, so nothing flies out
	var lid := CollisionShape3D.new()
	lid.shape = BoxShape3D.new()
	(lid.shape as BoxShape3D).size = Vector3(TRAY + 0.1, 0.02, TRAY + 0.1)
	lid.position = Vector3(0, 0.5, 0)
	_tray.add_child(lid)
	for sx in [-1.0, 1.0]:  # and invisible walls up to it
		for along_x in [true, false]:
			var wall := CollisionShape3D.new()
			wall.shape = BoxShape3D.new()
			(wall.shape as BoxShape3D).size = Vector3(0.02, 0.5, TRAY + 0.1) if along_x else Vector3(TRAY + 0.1, 0.5, 0.02)
			wall.position = Vector3(sx * (TRAY * 0.5 + 0.01), 0.25, 0) if along_x else Vector3(0, 0.25, sx * (TRAY * 0.5 + 0.01))
			_tray.add_child(wall)


func _tray_piece(size: Vector3, at: Vector3, mat: Material) -> void:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	box.material = mat
	mesh.mesh = box
	mesh.position = at
	_tray.add_child(mesh)
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	(shape.shape as BoxShape3D).size = size
	shape.position = at
	_tray.add_child(shape)


func _refresh_board() -> void:
	if _board == null:
		return
	var lines := ["Hound's Luck", ""]
	var any := false
	for b in get_tree().get_nodes_in_group("building"):
		var id: StringName = b.def.id
		if _tally.has(id):
			var t: Array = _tally[id]
			lines.append("%s  %d - %d" % [b.def.villager_name, t[0], t[1]])
			any = true
	if not any:
		lines.append("No games yet")
	_board.text = "\n".join(lines)


func to_dict() -> Dictionary:
	var d := {}
	for id in _tally:
		d[String(id)] = _tally[id]
	return {"tally": d}


func from_dict(d: Dictionary) -> void:
	_tally.clear()
	var t: Dictionary = d.get("tally", {})
	for id in t:
		_tally[StringName(id)] = [int(t[id][0]), int(t[id][1])]
	_refresh_board()


# --- the panel ---------------------------------------------------------------------------

func _build_panel() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 3
	_layer.visible = false
	add_child(_layer)
	var catcher := Control.new()  # clicks off the panel don't recapture the mouse mid-game
	catcher.set_anchors_preset(Control.PRESET_FULL_RECT)
	catcher.mouse_filter = Control.MOUSE_FILTER_STOP
	_layer.add_child(catcher)
	var frame := PanelContainer.new()
	var wood := StyleBoxFlat.new()
	wood.bg_color = NoticeboardPanel.WOOD
	wood.border_color = NoticeboardPanel.BRONZE
	wood.set_border_width_all(3)
	wood.set_corner_radius_all(6)
	wood.set_content_margin_all(12)
	wood.shadow_color = Color(0, 0, 0, 0.5)
	wood.shadow_size = 12
	frame.add_theme_stylebox_override("panel", wood)
	MenuUI.place(frame, Rect2(0.28, 0.7, 0.44, 0.27))
	_layer.add_child(frame)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	frame.add_child(box)
	_title = _label("", 22, NoticeboardPanel.GOLD, true)
	box.add_child(_title)
	_score_line = _label("", 18, NoticeboardPanel.GOLD)
	box.add_child(_score_line)
	_turn_line = _label("", 16, Color(NoticeboardPanel.GOLD, 0.8))
	box.add_child(_turn_line)
	_say = _label("", 16, Color(NoticeboardPanel.GOLD, 0.9))
	box.add_child(_say)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	box.add_child(row)
	_roll_button = MenuUI.button("Roll", func() -> void: chose.emit("roll"), 18)
	_bank_button = MenuUI.button("Stop and bank", func() -> void: chose.emit("bank"), 18)
	_again_button = MenuUI.button("Play again", func() -> void:
		if is_instance_valid(opponent):
			start(opponent), 18)
	var leave_button := MenuUI.button("Leave the table", func() -> void: leave(), 18)
	for b in [_roll_button, _bank_button, _again_button, leave_button]:
		row.add_child(b)


func _open_panel() -> void:
	if not _layer.visible:
		_layer.visible = true
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_refresh_scores()


func _refresh_scores() -> void:
	if opponent:
		_score_line.text = "You %d   %s %d" % [scores[0], opponent.display_name(), scores[1]]


func _set_buttons(roll: bool, bank: bool, again: bool) -> void:
	_roll_button.visible = roll
	_bank_button.visible = bank
	_again_button.visible = again


func _input(event: InputEvent) -> void:
	if _layer.visible and event.is_action_pressed("ui_cancel"):
		leave()
		get_viewport().set_input_as_handled()


func _label(text: String, size: int, color: Color, bold := false) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_override("font", MapView.map_font(bold))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l
