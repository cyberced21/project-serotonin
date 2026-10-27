class_name FishingLure
extends Node3D
## The float, out on the water. RodFishing casts it (fly_to), and it takes over from there:
## it bobs, drifts down a river's current (WaterBody.flow), and draws fish. A calm fish within its
## species' notice radius may notice it (front-only for station-holders: the float has to drift
## down to them), break from its school and swim over. Under the float it plays its species' tell
## rhythm (FishBite.tells): nibbles (a twitch: a fake-out), the tap-tap (it's about to commit), then the
## take (the float is dragged right under) and a short window to strike before it spits the hook.
## RodFishing calls strike() when the player yanks the rod and gets back what happened.

signal tell(kind: StringName)  # &"nibble", &"tap", &"take", &"spat", &"approach", &"spooked"

enum Bite { NONE, APPROACH, WAIT, TELLS, TAKE }

const FLOAT_MODEL := preload("res://models/fishing_float.glb")
const PALETTE_MATERIAL := preload("res://materials/node_palette.tres")
## Seconds after landing before anything will look at it (the splash has to settle).
const SETTLE := 0.8
## Nothing takes an interest for this long after a fish has spat it or been spooked off it.
const COOLDOWN := 1.5
## How far below the float the fish holds while it tells (m).
const UNDER := 0.16
const FLOAT_SCALE := 1.8

var water: WaterBody
var bite := Bite.NONE
var fish: Fish
## Real seconds since the take started (for timing the strike), and the window it had.
var take_age := 0.0
var take_window := 0.25
## A perfect cast: fish are curious for a while (notice faster).
var curious := 0.0
## The fisher's hut: calmer fish notice from further and nibble less (Village fish_calm).
var calm := 0.0
## The fisher's hut: a longer window to strike (Village strike_window, +0.25 = 25% longer).
var window_bonus := 0.0

var _model: Node3D
var _settle := SETTLE
var _cooldown := 0.0
var _tells: Array[Dictionary] = []
var _tell_i := 0
var _t := 0.0
var _twitch := 0.0  # current dip (m), springs back
var _bob := 0.0
var _rng := RandomNumberGenerator.new()
var _approach_from := Vector3.ZERO


func _ready() -> void:
	add_to_group("lure")
	_model = FLOAT_MODEL.instantiate() as Node3D
	_model.scale = Vector3.ONE * FLOAT_SCALE  # bigger than life: it has to read at 10 m
	for m in _model.find_children("*", "MeshInstance3D", true, false):
		(m as MeshInstance3D).material_override = PALETTE_MATERIAL
		(m as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_model)
	_rng.randomize()
	_bob = _rng.randf() * TAU


## Sets it floating at `at` on `w` (after the cast lands).
func land(w: WaterBody, at: Vector3) -> void:
	water = w
	global_position = Vector3(at.x, w.surface_height, at.z)
	_settle = SETTLE
	bite = Bite.NONE


## The player jerked the rod. Returns &"hooked" (the take was on: the fish is on the line; see
## strike_timing), &"spooked" (too early: the fish bolts) or &"nothing" (no fish on it).
func strike() -> StringName:
	match bite:
		Bite.TAKE:
			bite = Bite.NONE  # the fish is RodFishing's now; no more drawing fish in
			fish = null
			remove_from_group("lure")
			return &"hooked"
		Bite.TELLS, Bite.WAIT:
			_spook_fish()
			return &"spooked"
		Bite.APPROACH:
			if is_instance_valid(fish) and _flat_distance(fish.global_position) < 1.2:
				_spook_fish()
				return &"spooked"
			_release_fish(false)
	return &"nothing"


## How early in the take window the strike came (0 = the instant it dunked, 1 = the last moment).
func strike_timing() -> float:
	return clampf(take_age / maxf(take_window, 0.01), 0.0, 1.0)


## A noise scared the engaged fish off (FishSchool.disturb).
func fish_spooked(f: Fish) -> void:
	if f == fish and bite != Bite.NONE:
		_release_fish(true)
		tell.emit(&"spooked")


## Lets go of whatever fish it has, and stops drawing more (reeling in).
func retire() -> void:
	if is_instance_valid(fish) and bite != Bite.NONE:
		_release_fish(false)
	remove_from_group("lure")
	bite = Bite.NONE


func _physics_process(delta: float) -> void:
	if water == null:
		return
	_settle -= delta
	_cooldown -= delta
	curious = maxf(curious - delta, 0.0)
	if bite != Bite.NONE and not is_instance_valid(fish):  # eaten by a pike mid-bite
		fish = null
		bite = Bite.NONE
	_drift(delta)
	match bite:
		Bite.NONE:
			if _settle <= 0.0 and _cooldown <= 0.0 and is_in_group("lure"):
				_look_for_fish(delta)
		Bite.APPROACH:
			_approach(delta)
		Bite.WAIT, Bite.TELLS:
			_hold_fish(delta)
			_play_tells(delta)
		Bite.TAKE:
			_hold_fish(delta)
			take_age += delta
			if take_age > take_window:
				_release_fish(false)
				_cooldown = COOLDOWN
				tell.emit(&"spat")


## Down the current (rivers), stopping where it runs aground on a bank.
func _drift(delta: float) -> void:
	if water.flow == Vector3.ZERO or bite == Bite.TAKE:
		return
	var next := global_position + water.flow * delta
	var w := WaterBody.surface_at(get_tree(), next)
	if w and w.depth_here(next) > 0.12:
		water = w
		global_position = Vector3(next.x, w.surface_height, next.z)


func _process(delta: float) -> void:
	if not _model:
		return
	_bob += delta * 2.3
	_twitch = move_toward(_twitch, 0.0, delta * 0.25)
	var under := 0.0
	if bite == Bite.TAKE:  # dragged right under, jittering as the fish pulls
		under = 0.17 + sin(take_age * 70.0) * 0.012
	var y := (sin(_bob) * 0.006 - _twitch - under) * FLOAT_SCALE * 0.8
	_model.position.y = lerpf(_model.position.y, y, 1.0 - exp(-(60.0 if bite == Bite.TAKE else 30.0) * delta))
	var lean := sin(_bob * 0.7) * 0.06 + (0.6 if bite == Bite.TAKE else 0.0)
	_model.rotation.x = lerpf(_model.rotation.x, lean, 1.0 - exp(-12.0 * delta))


# --- drawing fish in ------------------------------------------------------------------------

func _look_for_fish(delta: float) -> void:
	var here := global_position
	for node in get_tree().get_nodes_in_group("fish_school"):
		var school := node as FishSchool
		if school.water == null or not school.water.contains(here):
			continue
		var s := school.species
		var radius := s.notice_radius * (1.0 + calm)
		for f in school.fish:
			if f.lure != null or f.state != Fish.State.CALM:
				continue
			var to := here - f.global_position
			to.y = 0.0
			var d := to.length()
			if d > radius:
				continue
			if s.holds_station:  # it only sees what comes down the current toward its nose
				var facing := -f.global_basis.z
				facing.y = 0.0
				if d > 0.3 and facing.normalized().dot(to / d) < 0.35:
					continue
			var rate := s.notice_rate * (1.6 if curious > 0.0 else 1.0) * (1.0 - 0.5 * d / radius) \
				* (1.0 + Perks.bonus(&"fishing", &"patience"))  # the level's patience perk: bites come sooner
			if not f.tool_can_take(&"rod"):
				rate *= 0.3  # too strong for your rod: it bites now and then (and tears free)
			if _rng.randf() < rate * delta:
				_engage(f)
				return


func _engage(f: Fish) -> void:
	fish = f
	f.lure = self
	f.state = Fish.State.CALM
	bite = Bite.APPROACH
	_approach_from = f.global_position
	tell.emit(&"approach")


func _approach(delta: float) -> void:
	var target := _hold_point()
	var off := target - fish.global_position
	var d := off.length()
	var s := fish.species
	var speed := s.approach_speed * (1.0 + 0.5 * smoothstep(1.0, 0.3, d))  # a little dart at the end
	if s.ambush and d < 1.4:
		speed = s.lunge_speed * 0.5  # the pike slides in under it
	fish.velocity = off.normalized() * minf(speed, d / maxf(delta, 0.001))
	fish.global_position += fish.velocity * delta
	_face(fish.velocity, delta)
	fish.set_swim(clampf(speed / s.flee_speed, 0.2, 1.0))
	if d < 0.12:
		_tells = FishBite.tells(s, _rng, calm)
		_tell_i = 0
		_t = 0.0
		bite = Bite.WAIT if s.ambush else Bite.TELLS
	elif _flat_distance(_approach_from) > s.notice_radius * 2.5 + 2.0:
		_release_fish(false)  # the float drifted off and it lost interest


## The fish sits just under the float, nose to it, fins working.
func _hold_fish(delta: float) -> void:
	var target := _hold_point()
	fish.global_position = fish.global_position.lerp(target, 1.0 - exp(-8.0 * delta))
	var to := global_position - fish.global_position
	to.y = 0.0
	if to.length() > 0.02:
		_face(to, delta)
	fish.velocity = Vector3.ZERO
	fish.set_swim(0.12 if bite == Bite.WAIT else 0.25)


func _play_tells(delta: float) -> void:
	_t += delta
	while _tell_i < _tells.size() and _t >= _tells[_tell_i]["t"]:
		var kind: StringName = _tells[_tell_i]["kind"]
		_tell_i += 1
		match kind:
			&"nibble":
				_twitch = 0.014
				_nudge_fish(0.06)
			&"tap":
				_twitch = 0.024
				_nudge_fish(0.08)
			&"take":
				bite = Bite.TAKE
				take_age = 0.0
				take_window = fish.species.strike_window * (1.0 + Perks.bonus(&"fishing", &"hands")) * (1.0 + window_bonus)
				_nudge_fish(0.12)
				WaterRipple.spawn(water, global_position, 1.8, 0.7)
		tell.emit(kind)


## Pushes the fish up into the float for a tell (it mouths it).
func _nudge_fish(amount: float) -> void:
	if is_instance_valid(fish):
		fish.global_position += Vector3.UP * amount * 0.5 + (global_position - fish.global_position).normalized() * amount * 0.3


func _hold_point() -> Vector3:
	var depth := water.depth_here(global_position)
	return global_position + Vector3.DOWN * minf(UNDER, maxf(depth * 0.5, 0.06))


func _face(dir: Vector3, delta: float) -> void:
	dir.y = 0.0
	if dir.length_squared() < 0.0001:
		return
	fish.global_basis = fish.global_basis.orthonormalized().slerp(Basis.looking_at(dir.normalized(), Vector3.UP), clampf(8.0 * delta, 0.0, 1.0))


func _spook_fish() -> void:
	var f := fish
	_release_fish(true)
	if is_instance_valid(f):
		FishPond.disturb(get_tree(), global_position, 1.2)  # it bolts, and the noise carries
	_cooldown = COOLDOWN
	tell.emit(&"spooked")


## The fish goes back to its school: bolting (`flee`) or just swimming off.
func _release_fish(flee: bool) -> void:
	var f := fish
	fish = null
	bite = Bite.NONE
	if not is_instance_valid(f):
		return
	f.lure = null
	var away := f.global_position - global_position
	away.y = 0.0
	if away.length_squared() < 0.0001:
		away = Vector3(_rng.randf_range(-1, 1), 0, _rng.randf_range(-1, 1))
	if flee:
		f.state = Fish.State.FLEE
		f.flee_time = _rng.randf_range(0.5, 0.9)
		f.velocity = away.normalized() * f.species.flee_speed
	else:
		f.velocity = away.normalized() * f.species.cruise_speed


func _flat_distance(p: Vector3) -> float:
	return Vector2(p.x - global_position.x, p.z - global_position.z).length()
