extends Camera3D
## First-person camera shake: rotation only (pitch / yaw / roll), never position — moving the
## eye feels like being shoved and makes people motion sick. Uses "trauma": each shake adds
## trauma, the visible shake is trauma², so small hits stay subtle and big breaks really kick.
## Uses real time so it keeps shaking during hit-stop (the world freezes, the screen still rattles).

## Juice.shake() amounts are the old 2D pixel values; this amount = full trauma.
@export var max_amount := 4.0
## Rotation at full trauma, in degrees: pitch, yaw, roll.
@export var max_angle_deg := Vector3(2.0, 2.0, 3.0)
## Trauma lost per second.
@export var decay := 1.8
## How fast the shake wobbles.
@export var frequency := 18.0

var _trauma := 0.0
var _t := 0.0
var _noise := FastNoiseLite.new()
var _last_us := 0


func _ready() -> void:
	add_to_group("camera")
	_noise.frequency = 1.0
	_last_us = Time.get_ticks_usec()


func shake(amount: float) -> void:
	_trauma = minf(maxf(_trauma, amount / max_amount), 1.0)


func _process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	var real_delta := (now - _last_us) / 1_000_000.0
	_last_us = now
	if _trauma <= 0.0:
		rotation = Vector3.ZERO
		return
	_trauma = maxf(_trauma - decay * real_delta, 0.0)
	_t += real_delta * frequency
	var s := _trauma * _trauma
	rotation = Vector3(
		deg_to_rad(max_angle_deg.x) * s * _noise.get_noise_2d(_t, 0.0),
		deg_to_rad(max_angle_deg.y) * s * _noise.get_noise_2d(_t, 100.0),
		deg_to_rad(max_angle_deg.z) * s * _noise.get_noise_2d(_t, 200.0))
