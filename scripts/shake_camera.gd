class_name ShakeCamera
extends Camera3D
## First-person camera shake: rotation only (pitch / yaw / roll), never position — moving the
## eye feels like being shoved and makes people motion sick. Uses "trauma": each shake adds
## trauma, the visible shake is trauma², so small hits stay subtle and big breaks really kick.
## Uses real time so it keeps shaking during hit-stop (the world freezes, the screen still rattles).
## Also a directional kick (kick()): the view snaps a little up and away from an impact and springs
## back, while the FOV narrows for a moment — the player adds fov_offset to the FOV it sets.

## Juice.shake() amounts are the old 2D pixel values; this amount = full trauma.
@export var max_amount := 4.0
## Rotation at full trauma, in degrees: pitch, yaw, roll.
@export var max_angle_deg := Vector3(2.0, 2.0, 3.0)
## Trauma lost per second.
@export var decay := 1.8
## How fast the shake wobbles.
@export var frequency := 18.0
## How stiff the spring pulling a kick back is (higher = shorter kick).
@export var kick_stiffness := 260.0

## The FOV before kicks: the player sets this (speed and slide widen it); every frame the camera's
## FOV is this plus fov_offset, degrees added by kicks (negative: narrower).
var base_fov := 75.0
var fov_offset := 0.0

var _trauma := 0.0
var _t := 0.0
var _noise := FastNoiseLite.new()
var _last_us := 0
var _kick := Vector2.ZERO  # pitch, yaw (rad)
var _kick_vel := Vector2.ZERO
var _fov_vel := 0.0


func _ready() -> void:
	add_to_group("camera")
	base_fov = fov
	_noise.frequency = 1.0
	_last_us = Time.get_ticks_usec()


func shake(amount: float) -> void:
	_trauma = minf(maxf(_trauma, amount * Settings.camera_motion() / max_amount), 1.0)


## Snaps the view `pitch_deg` up and `yaw_deg` round (positive: left), and the FOV `fov_deg`
## narrower; all spring back over a fraction of a second.
func kick(pitch_deg: float, yaw_deg: float, fov_deg: float) -> void:
	var m := Settings.camera_motion()  # the comfort setting
	_kick += Vector2(deg_to_rad(pitch_deg), deg_to_rad(yaw_deg)) * m
	fov_offset -= fov_deg * m


func _process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	var real_delta := minf((now - _last_us) / 1_000_000.0, 0.05)
	_last_us = now
	# kick and FOV punch: critically damped springs back to rest, in small steps so a long frame
	# (the first hit compiling its effects) doesn't flatten the kick
	var k := kick_stiffness
	var damping := 2.0 * sqrt(k)
	var steps := ceili(real_delta / (1.0 / 240.0))
	var dt := real_delta / maxf(steps, 1)
	for i in steps:
		_kick_vel += (-k * _kick - damping * _kick_vel) * dt
		_kick += _kick_vel * dt
		_fov_vel += (-k * fov_offset - damping * _fov_vel) * dt
		fov_offset += _fov_vel * dt
	fov = base_fov + fov_offset
	var kick := Vector3(_kick.x, _kick.y, 0.0)
	if _trauma <= 0.0:
		rotation = kick
		return
	_trauma = maxf(_trauma - decay * real_delta, 0.0)
	_t += real_delta * frequency
	var s := _trauma * _trauma
	rotation = kick + Vector3(
		deg_to_rad(max_angle_deg.x) * s * _noise.get_noise_2d(_t, 0.0),
		deg_to_rad(max_angle_deg.y) * s * _noise.get_noise_2d(_t, 100.0),
		deg_to_rad(max_angle_deg.z) * s * _noise.get_noise_2d(_t, 200.0))
