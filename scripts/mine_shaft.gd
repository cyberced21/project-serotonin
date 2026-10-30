class_name MineShaft
extends Node3D
## The way up out of the mine (plans/mine.md): a cage on a rope in a shaft through the first
## level's roof, over the way-in cell. It waits up in the shaft; E calls it down (it comes down
## out of the roof, rope rattling), E again in the cage rides it up to the quarry. You come down
## in it too, and once you've stepped off it goes back up out of the way.

## How far up the shaft the cage waits (its floor above the level's floor), and how long the way
## down takes.
const PARKED := MineLayout.HEIGHT + 0.4
const DROP_TIME := 3.2
const RISE_TIME := 1.4
## Stepped this far from the cage, a little while after arriving, it goes back up.
const CLEAR := 2.6
const CLEAR_TIME := 4.0

var mine: Node  # Mine
var _cage: Node3D
var _moving := false
var _down := false
var _clear_for := 0.0


func _ready() -> void:
	_cage = Node3D.new()
	_cage.name = "Cage"
	add_child(_cage)
	for piece: Array in [[MineLevel.POSTS, Vector3.ZERO, false], [MineLevel.BOARDWALK, Vector3(0, 0.02, 0), false]]:
		var p := Prop.new()
		p.model = piece[0]
		p.own_materials = piece[2]
		p.collide = false
		p.position = piece[1]
		_cage.add_child(p)
	for y in [MineLayout.HEIGHT, MineLayout.HEIGHT * 2.0]:  # the rope, all the way up the shaft
		var rope := Prop.new()
		rope.model = MineLevel.CHAIN
		rope.own_materials = true
		rope.collide = false
		rope.position = Vector3(0, y, 0)
		_cage.add_child(rope)
	var spot := MineSpot.make(Vector3(2.0, 2.4, 2.0), _prompt, _act)
	spot.collision_layer = LookObject.LAYER  # (not solid: you stand in the cage)
	add_child(spot)
	# down if you're standing here (just arrived, or the level rebuilt round you), else up the shaft
	_down = _player_near(CLEAR)
	_cage.position.y = 0.0 if _down else PARKED


func _process(delta: float) -> void:
	if not _down or _moving:
		return
	_clear_for = _clear_for + delta if not _player_near(CLEAR) else 0.0
	if _clear_for > CLEAR_TIME:
		_clear_for = 0.0
		_move(PARKED, DROP_TIME * 0.8)
		_down = false


## You came down in it: it's at the bottom (and goes back up once you've stepped off).
func arrive() -> void:
	_down = true
	_clear_for = 0.0
	_cage.position.y = 0.0


func is_down() -> bool:
	return _down and not _moving


func _prompt() -> String:
	if _moving:
		return ""
	return "E  Ride the cage up to the quarry" if _down else "E  Ring for the cage"


func _act() -> void:
	if _moving:
		return
	if not _down:
		_down = true
		_clear_for = 0.0
		_move(0.0, DROP_TIME)
		return
	_ride_up()


## Stand in the cage, rise into the shaft as it all goes dark, and step out at the quarry.
func _ride_up() -> void:
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player == null:
		return
	player.call("set_cutscene", true)
	var stand := global_position + Vector3.UP * 0.1
	player.call("teleport", stand, stand - global_basis.z * 3.0 + Vector3.UP * 1.6)
	_moving = true
	_play()
	var tween := create_tween().set_parallel()
	tween.tween_property(_cage, "position:y", 1.6, RISE_TIME).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tween.tween_property(player, "global_position:y", stand.y + 1.6, RISE_TIME).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	await tween.finished
	mine.call("leave")  # (fades out, out at the mouth; it lets go of you there)
	await get_tree().create_timer(1.0).timeout
	_moving = false
	_down = false
	_cage.position.y = PARKED


func _move(to: float, time: float) -> void:
	_moving = true
	_play()
	var tween := create_tween()
	tween.tween_property(_cage, "position:y", to, time).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await tween.finished
	_moving = false


func _play() -> void:
	var creak := AudioStreamPlayer3D.new()  # the rope and the winch somewhere up above
	creak.stream = Mine.LIFT_SOUND
	creak.bus = &"Effects"
	creak.volume_db = -4.0
	add_child(creak)
	creak.position = Vector3.UP * MineLayout.HEIGHT
	creak.play()
	creak.finished.connect(creak.queue_free)


func _player_near(r: float) -> bool:
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player == null:
		return false
	var d := player.global_position - global_position
	return Vector2(d.x, d.z).length() < r and absf(d.y) < MineLayout.HEIGHT
