class_name Wake
extends Node
## The water's answer to something moving through it (plans/water.md): rings trailing behind a
## body pushing through deep-enough water (spaced along its path, so as they spread they open
## into a V), a splash when it drops in, and drips when it climbs out. A child of the mover (the
## player, the dog); it watches the parent's position, so it needs nothing from it.

## The mover's height (m, its origin at the feet): the water has to be between its feet and this.
@export var height := 1.8
## Water at least this deep (m) round the body makes a wake (shallower, the footsteps' rings do).
@export var min_depth := 0.45
## A ring every this many metres moved, and how big (m across) at a walk and at full speed.
@export var spacing := 0.55
@export var ring_size := Vector2(1.3, 2.6)
@export var full_speed := 3.2
## Falling into the water faster than this (m/s) splashes.
@export var splash_speed := 2.2
## Moving through the water faster than this (m/s: a swimmer's sprint, a running dog) spooks the
## fish near it, every RUSH_EVERY seconds.
@export var rush_speed := 2.6
const RUSH_EVERY := 0.5

var _body: Node3D
var _last := Vector3.INF
var _travel := 0.0
var _was_in := false
var _was_deep := false
var _was_under := false  # all of it under the surface
var _wet_water: WaterBody  # the water it was last in, and where
var _wet_at := Vector3.ZERO
var _fall := 0.0  # how fast it was falling last tick (m/s)
var _rush_left := 0.0


func _ready() -> void:
	_body = get_parent() as Node3D


func _physics_process(delta: float) -> void:
	if _body == null or delta <= 0.0:
		return
	var p := _body.global_position
	var moved := Vector3.ZERO if _last == Vector3.INF else p - _last
	_last = p
	var water := WaterBody.surface_at(get_tree(), p)
	var surface := water.surface_y(p) if water else -INF
	var into := surface - p.y  # how far the feet are under the surface
	var is_in := water != null and into > 0.05
	var deep := is_in and water.depth_here(p) >= min_depth and into < height
	if is_in and not _was_in and _fall > splash_speed:
		var strength := inverse_lerp(splash_speed, 9.0, _fall)
		WaterRipple.splash(water, p, strength)
		FishPond.disturb(get_tree(), p, 1.0 + 2.0 * strength)  # (a plunge scatters the fish)
	elif _was_deep and not is_in and is_instance_valid(_wet_water):
		WaterRipple.splash(_wet_water, _wet_at, 0.15)  # (climbed out: drips where you came up)
	elif _was_under and into < height and is_in:
		WaterRipple.spawn(water, Vector3(p.x, surface, p.z), 1.8, 1.2)  # (came up from under)
	_was_in = is_in
	_was_deep = (_was_deep and is_in) or (deep and into > min_depth)
	_was_under = is_in and into >= height
	if is_in:
		_wet_water = water
		_wet_at = p
	_fall = maxf(-moved.y / delta, 0.0)
	# rushing through the water (over or under it) spooks the fish round you; easing up on them doesn't
	_rush_left -= delta
	# (the player only once swimming: wading, the spear's stalk is the footsteps' business)
	var swims: bool = _body.get("swimming") if "swimming" in _body else true
	if is_in and swims and moved.length() / delta > rush_speed and _rush_left <= 0.0:
		_rush_left = RUSH_EVERY
		FishPond.disturb(get_tree(), p, 1.3)
	if not deep:
		_travel = 0.0
		return
	var flat := Vector2(moved.x, moved.z).length()
	var speed := flat / delta
	if speed < 0.3:
		return
	_travel += flat
	if _travel >= spacing:
		_travel = 0.0
		var t := clampf(speed / full_speed, 0.0, 1.0)
		var back := Vector3(moved.x, 0.0, moved.z).normalized() * -0.25
		WaterRipple.spawn(water, Vector3(p.x, surface, p.z) + back, lerpf(ring_size.x, ring_size.y, t), lerpf(1.1, 1.6, t))
