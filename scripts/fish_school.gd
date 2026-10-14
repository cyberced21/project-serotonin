class_name FishSchool
extends Node3D
## A group of fish of one species, steered together (simple boids: cohesion, separation,
## alignment, plus a wandering goal), kept inside water deep enough to swim in.
##
## Calm: cruise toward a goal that moves around the pond every few seconds.
## Disturbed (disturb()): every fish bolts away from the noise with some random spread, so the
## school breaks up; while alert they keep their distance from each other, then they settle and
## drift back together. Lurkers (pike) hold still at a lurk spot instead of cruising.
## Caught fish are replaced one at a time (regrow); a wiped-out school is respawned by FishPond.
## Hunters (a lurker whose species `hunts` another): every so often the pike leaves its cover,
## stalks the nearest school of its prey, lunges when it's close — the school scatters, and
## sometimes one is eaten — then glides back to cover. Spooking the pike calls the hunt off.

enum Hunt { LURK, STALK, LUNGE, RETURN }
const SPLASH := preload("res://audio/movement/splash.tres")
const STALK_GIVE_UP := 20.0
const LUNGE_TIME := 0.35

const MIN_DEPTH := 0.3  # fish never swim into water shallower than this
## Fraction off the scare radius right at dawn and dusk (DayNight.twilight), when fish are dozy.
const DUSK_CALM := 0.35

var species: FishSpecies
var water: WaterBody
var fish: Array[Fish] = []
var target_size := 0

var _goal := Vector3.ZERO
var _goal_timer := 0.0
var _alert := 0.0  # seconds of alertness left
var _regrow_timer := 0.0
var _hunt := Hunt.LURK
var _hunt_timer := 0.0
var _prey: Fish
var _lurk_spot := Vector3.ZERO
var _will_catch := false  # decided as the lunge starts


func setup(p_species: FishSpecies, p_water: WaterBody, at: Vector3) -> void:
	species = p_species
	water = p_water
	add_to_group("fish_school")
	target_size = randi_range(species.school_min, species.school_max)
	_goal = at
	for i in target_size:
		_spawn_fish(at + Vector3(randf_range(-0.6, 0.6), 0, randf_range(-0.6, 0.6)))


func _spawn_fish(at: Vector3) -> Fish:
	var f := Fish.new()
	f.name = "%s%d" % [species.id, fish.size()]
	add_child(f)
	f.setup(species, self)
	f.global_position = _clamp_to_water(at, f)
	f.velocity = Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized() * species.cruise_speed
	fish.append(f)
	return f


## Something made noise at `pos`. loudness ~0.15 (crouch step) .. 1 (sprint) .. 2 (a strike).
func disturb(pos: Vector3, loudness: float) -> void:
	var spooked := false
	# calmer with the fisher's hut upgraded, and dozy around dawn and dusk
	var calm := Village.stat(&"fish_calm") + DUSK_CALM * DayNight.twilight()
	var radius := species.scare_radius * maxf(1.0 - calm, 0.1)
	for f in fish:
		var d := f.global_position.distance_to(pos)
		if d < radius and loudness * (1.0 - d / radius) > species.nerve * 0.5:
			spooked = true
	if not spooked:
		return
	_alert = species.calm_down
	for f in fish:  # the whole school bolts once any of it is spooked
		var away := f.global_position - pos
		away.y = 0.0
		if away.length_squared() < 0.0001:
			away = Vector3(randf_range(-1, 1), 0, randf_range(-1, 1))
		away = away.normalized().rotated(Vector3.UP, randf_range(-0.7, 0.7))  # spread -> the school splits
		f.velocity = away * species.flee_speed * randf_range(0.8, 1.2)
		f.state = Fish.State.FLEE
		f.flee_time = randf_range(0.4, 0.8)


## Removes a fish (caught) and starts regrowing the school.
func remove_fish(f: Fish) -> void:
	fish.erase(f)
	if _regrow_timer <= 0.0:
		_regrow_timer = randf_range(15.0, 25.0)


func _physics_process(delta: float) -> void:
	if fish.is_empty():
		return
	_alert = maxf(_alert - delta, 0.0)
	_update_goal(delta)
	_regrow(delta)
	if species.lurker and species.hunts != &"":
		_update_hunt(delta)

	var center := Vector3.ZERO
	var heading := Vector3.ZERO
	for f in fish:
		center += f.global_position
		heading += f.velocity
	center /= fish.size()

	for f in fish:
		_steer(f, center, heading, delta)


func _steer(f: Fish, center: Vector3, heading: Vector3, delta: float) -> void:
	var pos := f.global_position
	if f.state == Fish.State.FLEE:
		f.flee_time -= delta
		f.velocity = f.velocity.move_toward(f.velocity.normalized() * species.cruise_speed * 2.0, 4.0 * delta)
		if f.flee_time <= 0.0:
			f.state = Fish.State.ALERT if _alert > 0.0 else Fish.State.CALM
	else:
		f.state = Fish.State.ALERT if _alert > 0.0 else Fish.State.CALM
		var desired := Vector3.ZERO
		if species.lurker and _alert <= 0.0 and _hunt == Hunt.LUNGE:
			f.velocity.y = 0.0  # the lunge sets the velocity outright (see _start_lunge)
			desired = f.velocity
		elif species.lurker and _alert <= 0.0 and _hunt == Hunt.STALK and is_instance_valid(_prey):
			var to_prey := _prey.global_position - pos
			to_prey.y = 0.0
			desired = to_prey.normalized() * species.stalk_speed
		elif species.lurker and _alert <= 0.0:
			# hold near the lurk spot, barely moving (or glide back to it after a hunt)
			var to_spot := _goal - pos
			to_spot.y = 0.0
			var speed := species.cruise_speed * (2.0 if _hunt == Hunt.RETURN else 1.0)
			desired = to_spot.limit_length(1.0) * speed
		else:
			var to_goal := _goal - pos
			to_goal.y = 0.0
			var cohesion := (center - pos) * (0.2 if _alert > 0.0 else 1.0)  # alert fish keep apart
			var separation := Vector3.ZERO
			for o in fish:
				if o == f:
					continue
				var off := pos - o.global_position
				var d := off.length()
				if d < species.spacing and d > 0.001:
					separation += off / d * (species.spacing - d) / species.spacing
			var align := heading.normalized() if heading.length_squared() > 0.0001 else Vector3.ZERO
			desired = to_goal.normalized() * 0.6 + cohesion * 0.5 + separation * 2.0 + align * 0.4
			desired.y = 0.0
			desired = desired.normalized() * species.cruise_speed * (1.3 if _alert > 0.0 else 1.0)
		# turn gradually toward the desired direction
		var cur := f.velocity
		if _hunt == Hunt.LUNGE:
			cur = desired  # no gradual turn mid-lunge
		var angle := cur.signed_angle_to(desired, Vector3.UP) if cur.length_squared() > 0.0001 and desired.length_squared() > 0.0001 else 0.0
		var turned := cur.rotated(Vector3.UP, clampf(angle, -species.turn_rate * delta, species.turn_rate * delta))
		f.velocity = turned.normalized() * move_toward(cur.length(), desired.length(), 2.0 * delta) if turned.length_squared() > 0.0001 else desired

	# stay in water deep enough: if heading into the shallows, bend back toward the pond centre
	var ahead := pos + f.velocity.normalized() * 0.5
	if water.depth_here(ahead) < MIN_DEPTH:
		var to_center := water.global_position - pos
		to_center.y = 0.0
		f.velocity = f.velocity.lerp(to_center.normalized() * f.velocity.length(), clampf(8.0 * delta, 0.0, 1.0))
		if f.state != Fish.State.FLEE:
			_pick_goal()

	f.global_position = _clamp_to_water(pos + f.velocity * delta, f)
	if f.velocity.length_squared() > 0.0004:
		f.global_basis = f.global_basis.slerp(Basis.looking_at(f.velocity.normalized(), Vector3.UP), clampf(10.0 * delta, 0.0, 1.0))
	var still := species.lurker and _alert <= 0.0 and _hunt == Hunt.LURK
	var swim := 0.05 if still else clampf(f.velocity.length() / species.flee_speed, 0.15, 1.0)
	f.set_swim(swim)


## Keeps a position in the water column: between bed and surface at the fish's preferred depth.
func _clamp_to_water(p: Vector3, f: Fish) -> Vector3:
	var depth := water.depth_here(p)
	if depth < MIN_DEPTH * 0.7:
		p = p.lerp(Vector3(water.global_position.x, p.y, water.global_position.z), 0.02)
		depth = water.depth_here(p)
	var bed := water.surface_height - depth
	var y := bed + clampf(depth * f.depth_pref, 0.08, maxf(depth - 0.1, 0.08))
	p.y = lerpf(p.y, y, 0.1) if absf(p.y - y) < 1.0 else y
	return p


func _update_goal(delta: float) -> void:
	_goal_timer -= delta
	if species.lurker:
		return  # lurkers keep their spot (set by FishPond)
	var c := Vector3.ZERO
	for f in fish:
		c += f.global_position
	c /= fish.size()
	if _goal_timer <= 0.0 or Vector2(c.x - _goal.x, c.z - _goal.z).length() < 0.6:
		_pick_goal()


func _pick_goal() -> void:
	_goal_timer = randf_range(5.0, 9.0)
	var p := FishPond.random_point(water, MIN_DEPTH + 0.15)
	if p != Vector3.INF:
		_goal = p


func set_lurk_spot(p: Vector3) -> void:
	_goal = p
	_lurk_spot = p
	_hunt_timer = randf_range(species.hunt_interval.x, species.hunt_interval.y)


# --- hunting --------------------------------------------------------------------------------

func _update_hunt(delta: float) -> void:
	var hunter := fish[0]
	if _alert > 0.0 and _hunt != Hunt.LURK and _hunt != Hunt.RETURN:
		_back_to_cover()  # spooked: the hunt's off
	match _hunt:
		Hunt.LURK:
			_hunt_timer -= delta
			if _hunt_timer <= 0.0 and _alert <= 0.0:
				_prey = _nearest_prey(hunter.global_position)
				if _prey:
					_hunt = Hunt.STALK
					_hunt_timer = STALK_GIVE_UP
				else:
					_hunt_timer = randf_range(species.hunt_interval.x, species.hunt_interval.y) * 0.5
		Hunt.STALK:
			_hunt_timer -= delta
			if not is_instance_valid(_prey) or _prey.school._alert > 0.0 or _hunt_timer <= 0.0:
				_back_to_cover()
			elif hunter.global_position.distance_to(_prey.global_position) < species.lunge_range:
				_start_lunge(hunter)
		Hunt.LUNGE:
			_hunt_timer -= delta
			if _hunt_timer <= 0.0:
				_finish_lunge(hunter)
		Hunt.RETURN:
			var off := _lurk_spot - hunter.global_position
			off.y = 0.0
			if off.length() < 0.4:
				_hunt = Hunt.LURK
				_hunt_timer = randf_range(species.hunt_interval.x, species.hunt_interval.y)


func _nearest_prey(from: Vector3) -> Fish:
	var best: Fish = null
	var best_d := INF
	for s in get_tree().get_nodes_in_group("fish_school"):
		var school := s as FishSchool
		if school == self or school.water != water or school.species.id != species.hunts:
			continue
		for f in school.fish:
			var d := f.global_position.distance_squared_to(from)
			if d < best_d:
				best_d = d
				best = f
	return best


func _start_lunge(hunter: Fish) -> void:
	_hunt = Hunt.LUNGE
	_hunt_timer = LUNGE_TIME
	var dir := _prey.global_position - hunter.global_position
	dir.y = 0.0
	hunter.velocity = dir.normalized() * species.lunge_speed
	var at := Vector3(hunter.global_position.x, water.surface_height, hunter.global_position.z)
	WaterRipple.spawn(water, at, 1.6)
	_will_catch = randf() < species.catch_chance
	var target := _prey
	_prey.school.disturb(hunter.global_position, 2.0)  # the school scatters...
	if _will_catch:  # ...but this one's caught: it freezes rather than bolting
		target.velocity = Vector3.ZERO
		target.state = Fish.State.ALERT


func _finish_lunge(hunter: Fish) -> void:
	if is_instance_valid(_prey) and _will_catch:
		var at := Vector3(_prey.global_position.x, water.surface_height, _prey.global_position.z)
		WaterRipple.spawn(water, at, 2.2)
		_play_splash(at)
		_prey.school.remove_fish(_prey)
		_prey.queue_free()
	_back_to_cover()


func _back_to_cover() -> void:
	_hunt = Hunt.RETURN
	_prey = null
	_goal = _lurk_spot


func _play_splash(at: Vector3) -> void:
	var p := AudioStreamPlayer3D.new()
	p.stream = SPLASH
	p.pitch_scale = randf_range(1.2, 1.4)
	p.volume_db = -6.0
	p.unit_size = 4.0
	add_child(p)
	p.global_position = at
	p.play()
	p.finished.connect(p.queue_free)


func _regrow(delta: float) -> void:
	if _regrow_timer <= 0.0:
		return
	_regrow_timer -= delta
	if _regrow_timer > 0.0:
		return
	if fish.size() < target_size:
		var from := FishPond.random_point(water, 0.6)  # swims in from deeper water
		_spawn_fish(from if from != Vector3.INF else _goal)
	if fish.size() < target_size:
		_regrow_timer = randf_range(15.0, 25.0)
