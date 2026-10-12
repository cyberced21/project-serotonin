extends Camera2D
## Camera with whole-pixel screen shake. Uses real time so it keeps shaking
## during hit-stop (the world freezes, the screen still rattles).

@export var decay := 12.0
@export var max_offset := 6.0

var _strength := 0.0
var _last_us := 0


func _ready() -> void:
	add_to_group("camera")
	_last_us = Time.get_ticks_usec()


func shake(amount: float) -> void:
	_strength = minf(maxf(_strength, amount), max_offset)


func _process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	var real_delta := (now - _last_us) / 1_000_000.0
	_last_us = now
	if _strength > 0.25:
		offset = (Vector2(randf_range(-1, 1), randf_range(-1, 1)) * _strength).round()
		_strength *= exp(-decay * real_delta)
	else:
		_strength = 0.0
		offset = Vector2.ZERO
