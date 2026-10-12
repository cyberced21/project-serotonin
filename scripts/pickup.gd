extends Node2D
## Loot that pops out of a node in an arc, settles, then gets magnetised to the player.

@export var arc_time := 0.38
@export var arc_height := 16.0
@export var magnet_radius := 40.0
@export var magnet_accel := 900.0

var item: StringName = &"wood"
var icon: Texture2D

@onready var sprite: Sprite2D = $Sprite2D

enum State { WAIT, ARC, IDLE, MAGNET }
var _state := State.WAIT
var _t := 0.0
var _delay := 0.0
var _from := Vector2.ZERO
var _to := Vector2.ZERO
var _vel := Vector2.ZERO
var _bob := 0.0


func _ready() -> void:
	sprite.texture = icon
	sprite.visible = false


func launch(from: Vector2, to: Vector2, delay := 0.0) -> void:
	_from = from
	_to = to
	_delay = delay
	global_position = from
	_bob = randf() * TAU


func _process(delta: float) -> void:
	match _state:
		State.WAIT:
			_delay -= delta
			if _delay <= 0.0:
				_state = State.ARC
				sprite.visible = true
		State.ARC:
			_t += delta / arc_time
			var k := minf(_t, 1.0)
			global_position = _from.lerp(_to, k)
			sprite.position.y = -sin(k * PI) * arc_height
			if k >= 1.0:
				_state = State.IDLE
				_t = 0.0
				sprite.scale = Vector2(1.3, 0.7)
				create_tween().tween_property(sprite, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		State.IDLE:
			_t += delta
			_bob += delta * 4.0
			sprite.position.y = roundf(-1.0 - sin(_bob) * 1.0)
			if _t > 0.25 and _player_in_range():
				_state = State.MAGNET
		State.MAGNET:
			var player := _player()
			if player == null:
				_state = State.IDLE
				return
			var target := player.global_position + Vector2(0, -6)
			var dir := (target - global_position)
			if dir.length() < 5.0:
				_collect()
				return
			_vel += dir.normalized() * magnet_accel * delta
			_vel = _vel.limit_length(260.0)
			global_position += _vel * delta


func _player() -> Node2D:
	return get_tree().get_first_node_in_group("player") as Node2D


func _player_in_range() -> bool:
	var p := _player()
	return p != null and p.global_position.distance_to(global_position) < magnet_radius


func _collect() -> void:
	Inventory.add(item)
	Sfx.play_pickup()
	queue_free()
