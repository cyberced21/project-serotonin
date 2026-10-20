class_name FishFight
extends RefCounted
## A hooked fish's fight, as pure logic: RodFishing feeds it time and the player's input each
## frame and plays out the events it returns (sounds, the rod, the fish in the water). No balance
## bar: the fish does one telegraphed move after another, and each has its own answer.
##   PULL       steady tug (rod creak): hold the reel to bring it in
##   RUN        line hiss, the fish streaks off: have the reel released when it bolts, keep it so
##   HEADSHAKE  the rod tip jerks 2–3 times on a beat: click on each jerk
##   JUMP       the water bulges, then a splash: bow (RMB) on the splash, and not reeling
## A wrong or late answer costs a line notch (one per move at most); out of notches, it snaps.
## Progress is the fish's distance; at land_distance the landing starts: the fish flashes
## side-on on a rhythm, click on a flash to hoist it out. A click off the flash costs a notch.
##
## Every window is multiplied by `window_scale` and every warning by `telegraph_scale`
## (level_scales: wider above the fish's level, much tighter below).

enum Move { PULL, RUN, HEADSHAKE, JUMP }
enum Phase { GAP, TELEGRAPH, ACTIVE, LANDING, OVER }
const MOVES: Array[Move] = [Move.PULL, Move.RUN, Move.HEADSHAKE, Move.JUMP]

## Seconds after the bolt you still have to let go of the reel.
const RUN_GRACE := 0.12
## Half-width of the window round each headshake jerk, and round the jump's splash (s).
const JERK_WINDOW := 0.1
const BOW_WINDOW := 0.16
## Landing: a flash every FLASH_PERIOD, each FLASH_TIME long; after LANDING_PATIENCE the fish
## makes one more run.
const FLASH_PERIOD := 0.75
const FLASH_TIME := 0.22
const LANDING_PATIENCE := 5.0
const LAND_DISTANCE := 1.6
## Bonus progress for a clean headshake and a good bow (m).
const SHAKE_BONUS := 0.45
const BOW_BONUS := 0.35
const PULL_TIME := Vector2(0.9, 1.8)
## Fraction of a run's speed that turns into line taken (the rest is the drag braking it).
const RUN_GIVE := 0.3
const GAP_TIME := Vector2(0.25, 0.5)

var species: FishSpecies
var distance := 8.0
## How far it can run before the line runs out (snaps).
var max_distance := 22.0
var notches := 3
var max_notches := 3
var damaged := false  # any notch lost: not a clean catch
var size := 0.0  # 0..1 within the species' weight range
var window_scale := 1.0
var telegraph_scale := 1.0
var result: StringName = &""  # &"landed" or &"snapped" once over

var move := Move.PULL
var phase := Phase.GAP
var _t := 0.0          # time in the current phase
var _len := 0.3        # length of the current phase
var _hurt := false     # this move already cost a notch
var _jerks: Array[float] = []  # headshake: jerk times (from the start of ACTIVE)
var _jerk_hit: Array[bool] = []
var _jerk_next := 0    # next jerk to announce
var _beat := 0.3
var _counted := false
var _shake_miss := false
var _bowed := false
var _bow_early := false
var _splashed := false
var _flash_on := false
var _rng: RandomNumberGenerator
var _first := true


func _init(p_species: FishSpecies, start_distance: float, p_size: float, p_window := 1.0,
		p_telegraph := 1.0, p_notches := 3, rng: RandomNumberGenerator = null) -> void:
	species = p_species
	distance = start_distance
	max_distance = maxf(start_distance + 10.0, 18.0)
	size = p_size
	window_scale = p_window
	telegraph_scale = p_telegraph
	notches = p_notches
	max_notches = p_notches
	_rng = rng if rng else RandomNumberGenerator.new()
	_enter(Phase.GAP, 0.3)


## How the level gap scales the fight (and the strike window): [window_scale, telegraph_scale].
## Each 10 levels above the fish's widens windows by 10%. Below, they shrink 5.5% a level (5
## under: ~0.72, hard but possible; 15 under: 0.2, near-impossible) and warnings get shorter.
static func level_scales(level: int, required: int) -> Vector2:
	var gap := level - required
	if gap >= 0:
		return Vector2(1.0 + 0.1 * floorf(gap / 10.0), 1.0)
	var under := clampf(-gap / 15.0, 0.0, 1.0)
	return Vector2(clampf(1.0 + 0.055 * gap, 0.2, 1.0), lerpf(1.0, 0.55, under))


func is_over() -> bool:
	return phase == Phase.OVER


## The reel speed now: slower for a bigger fish.
func reel_rate() -> float:
	return species.reel_speed * (1.0 - species.size_drag * size)


## A pike takes the fish on the line: the fight goes on as the pike's.
func switch_species(s: FishSpecies, p_size: float, p_window: float, p_telegraph: float) -> void:
	species = s
	size = p_size
	window_scale = p_window
	telegraph_scale = p_telegraph
	if phase != Phase.LANDING:
		_next_move()


## Advances `dt` seconds. `reel`: LMB held; `click`: LMB pressed this frame; `bow`: RMB pressed
## this frame. Returns the events that happened, as dictionaries with a "type":
##   move (move), telegraph (move), count, bolt, run_end, jerk (index), jerk_hit, splash, bowed,
##   shake_clean, damage (reason), snap, landing, flash, flash_end, thrash, landed, reel (amount)
func step(dt: float, reel: bool, click: bool, bow: bool) -> Array[Dictionary]:
	var ev: Array[Dictionary] = []
	if phase == Phase.OVER:
		return ev
	_t += dt
	match phase:
		Phase.GAP:
			if _t >= _len:
				_next_move(ev)
		Phase.TELEGRAPH:
			if move == Move.JUMP:
				_jump_input(click, bow, reel, ev)
			elif move == Move.HEADSHAKE and not _counted and _t >= _beat:
				_counted = true
				ev.append({"type": "count"})  # the second beat of the count-in
			if phase == Phase.TELEGRAPH and _t >= _len:
				_enter(Phase.ACTIVE, _active_length())
				if move == Move.RUN:
					ev.append({"type": "bolt"})
		Phase.ACTIVE:
			_active(dt, reel, click, bow, ev)
		Phase.LANDING:
			_landing(click, ev)
	if phase != Phase.OVER and phase != Phase.LANDING and distance > max_distance:
		_snap(ev, "spooled")
	return ev


func _active_length() -> float:
	match move:
		Move.PULL:
			return _rng.randf_range(PULL_TIME.x, PULL_TIME.y) * (1.0 + 0.5 * size)
		Move.RUN:
			return _rng.randf_range(species.run_time.x, species.run_time.y) * (1.0 + 0.4 * size)
		Move.HEADSHAKE:
			return _jerks.back() + JERK_WINDOW * window_scale + 0.05
		_:
			return BOW_WINDOW * window_scale  # the jump: the window after the splash


func _active(dt: float, reel: bool, click: bool, bow: bool, ev: Array[Dictionary]) -> void:
	match move:
		Move.PULL:
			if reel:
				var amount := reel_rate() * dt
				distance -= amount
				ev.append({"type": "reel", "amount": amount})
			if distance <= LAND_DISTANCE:
				_start_landing(ev)
				return
		Move.RUN:
			# the reel's drag gives line grudgingly: a run handled well only costs a little
			distance += species.run_speed * RUN_GIVE * dt * (1.0 + 0.3 * size)
			# the bolt: let go in time and stay let go
			if reel and (_t > RUN_GRACE * window_scale or click):
				_hurt_once(ev, "tight")
		Move.HEADSHAKE:
			while _jerk_next < _jerks.size() and _t >= _jerks[_jerk_next]:
				ev.append({"type": "jerk", "index": _jerk_next})
				_jerk_next += 1
			if click:
				var hit := false
				for i in _jerks.size():
					if not _jerk_hit[i] and absf(_t - _jerks[i]) <= JERK_WINDOW * window_scale:
						_jerk_hit[i] = true
						hit = true
						ev.append({"type": "jerk_hit", "index": i})
						break
				if not hit:
					_shake_miss = true
		Move.JUMP:
			_jump_input(click, bow, reel, ev)
	if _t >= _len:
		_end_move(ev)


## The jump: the splash comes at the end of the telegraph; bow inside BOW_WINDOW of it.
func _jump_input(_click: bool, bow: bool, reel: bool, ev: Array[Dictionary]) -> void:
	var to_splash := _t - _len if phase == Phase.TELEGRAPH else _t  # negative before it
	if phase == Phase.ACTIVE and not _splashed:
		_splashed = true
		ev.append({"type": "splash"})
		if reel:
			_hurt_once(ev, "tight")
	if bow and not _bowed and not _bow_early:
		if absf(to_splash) <= BOW_WINDOW * window_scale or (phase == Phase.ACTIVE):
			_bowed = true
			ev.append({"type": "bowed"})
		else:
			_bow_early = true  # dropped the tip too soon: it comes up tight on the splash


func _end_move(ev: Array[Dictionary]) -> void:
	match move:
		Move.RUN:
			ev.append({"type": "run_end"})
		Move.HEADSHAKE:
			if _shake_miss or _jerk_hit.has(false):
				_hurt_once(ev, "shake")
			else:
				distance -= SHAKE_BONUS
				ev.append({"type": "shake_clean"})
		Move.JUMP:
			if not _splashed:
				_splashed = true
				ev.append({"type": "splash"})
			if _bowed and not _hurt:
				distance -= BOW_BONUS
			elif not _bowed:
				_hurt_once(ev, "jump")
	if phase == Phase.OVER:
		return
	if distance <= LAND_DISTANCE:
		_start_landing(ev)
	else:
		_enter(Phase.GAP, _rng.randf_range(GAP_TIME.x, GAP_TIME.y))


func _next_move(ev: Array[Dictionary] = []) -> void:
	_hurt = false
	if _first:
		_first = false
		move = Move.PULL  # always a pull first: feel the weight before it starts throwing moves
	else:
		var w := species.move_weights
		if distance < LAND_DISTANCE + 1.2:
			w.w = 0.0  # no room to jump right at your feet
		move = _pick(w)
	ev.append({"type": "move", "move": move})
	match move:
		Move.PULL:
			_enter(Phase.ACTIVE, _active_length())
		Move.RUN:
			_enter(Phase.TELEGRAPH, _telegraph())
			ev.append({"type": "telegraph", "move": move})
		Move.HEADSHAKE:
			_jerks.clear()
			_jerk_hit.clear()
			_jerk_next = 0
			_shake_miss = false
			# a count-in on the beat (creak, tremble), then a jerk on every beat: learnable, not a
			# reaction test you can't win
			var n := _rng.randi_range(species.shake_jerks.x, species.shake_jerks.y)
			_beat = species.shake_beat * lerpf(1.0, 0.8, 1.0 - telegraph_scale)
			for i in n:
				_jerks.append(i * _beat)
				_jerk_hit.append(false)
			_counted = false
			_enter(Phase.TELEGRAPH, _beat * 2.0)
			ev.append({"type": "telegraph", "move": move})
		Move.JUMP:
			_bowed = false
			_bow_early = false
			_splashed = false
			_enter(Phase.TELEGRAPH, _telegraph())
			ev.append({"type": "telegraph", "move": move})


func _telegraph() -> float:
	return _rng.randf_range(species.telegraph.x, species.telegraph.y) * telegraph_scale


func _pick(w: Vector4) -> Move:
	var total := w.x + w.y + w.z + w.w
	if total <= 0.0:
		return Move.PULL
	var r := _rng.randf() * total
	for i in 4:
		r -= w[i]
		if r < 0.0:
			return MOVES[i]
	return Move.PULL


func _start_landing(ev: Array[Dictionary]) -> void:
	distance = minf(distance, LAND_DISTANCE)
	_enter(Phase.LANDING, LANDING_PATIENCE)
	_flash_on = false
	ev.append({"type": "landing"})


func _landing(click: bool, ev: Array[Dictionary]) -> void:
	var cycle := fmod(_t, FLASH_PERIOD)
	var flash_len := maxf(FLASH_TIME * window_scale, 0.08)
	var start := FLASH_PERIOD - flash_len  # each period ends on its flash
	var on := cycle >= start and _t > FLASH_PERIOD * 0.5
	if on != _flash_on:
		_flash_on = on
		ev.append({"type": "flash" if on else "flash_end"})
	if click:
		if on:
			result = &"landed"
			phase = Phase.OVER
			ev.append({"type": "landed"})
			return
		ev.append({"type": "thrash"})
		_damage(ev, "thrash")
		if phase == Phase.OVER:
			return
	if _t >= _len:  # took too long: one more run
		distance = LAND_DISTANCE + 2.5
		_first = false
		_hurt = false
		move = Move.RUN
		_enter(Phase.TELEGRAPH, _telegraph())
		ev.append({"type": "move", "move": move})
		ev.append({"type": "telegraph", "move": move})


func _hurt_once(ev: Array[Dictionary], reason: String) -> void:
	if _hurt:
		return
	_hurt = true
	_damage(ev, reason)


func _damage(ev: Array[Dictionary], reason: String) -> void:
	notches -= 1
	damaged = true
	ev.append({"type": "damage", "reason": reason})
	if notches <= 0:
		_snap(ev, reason)


func _snap(ev: Array[Dictionary], reason: String) -> void:
	notches = 0
	result = &"snapped"
	phase = Phase.OVER
	ev.append({"type": "snap", "reason": reason})


func _enter(p: Phase, length: float) -> void:
	phase = p
	_t = 0.0
	_len = length
