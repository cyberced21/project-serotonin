class_name RodFishing
extends Node
## Rod fishing, as a part of the Player (child node, like SpearFishing). Water beyond the spear's
## reach, out to cast_range, brings the rod out. Once cast, the rod stays in hand until the float is
## reeled in, the fish is landed or the line snaps. Every beat is timing, read from the world:
##
## 1. Cast: hold to swing the rod back, release on the forward stroke. The whip is the sweet spot:
##    on it, the float lands on the aim point with a plip; off it, it scatters and sploshes (RodCast),
##    spooking fish near. Right on top of a school spooks it however soft.
## 2. Bite: the float (FishingLure) draws a real fish over; it nibbles (fake-outs: don't strike),
##    taps twice, then takes (the float dunks): strike (click) inside the window. Early spooks it.
## 3. Fight (FishFight): the fish pulls (hold to reel), runs (let go), shakes its head (click on the
##    jerks), jumps (bow: RMB on the splash). Wrong answers cost line notches. You're rooted (a
##    slow shuffle) and the rod tugs your aim toward the fish.
## 4. Land: at your feet it flashes side-on on a rhythm: click on a flash to hoist it out.
##    Clean (no notch lost) and Perfect (clean + perfect cast + early strike) pay extra XP; every
##    fish rolls a size.
## A small fish on the line can be taken by a pike lurking in the same water: then you're fighting
## the pike. Under-levelled fish still bite, but every window is far tighter (FishFight.level_scales).

enum State { IDLE, BACKCAST, FLIGHT, WAITING, RETRIEVE, FIGHT, DONE }

const WORLD_MASK := 1
const ROD_MODEL := preload("res://models/rod.glb")
const TOOL_MATERIAL := preload("res://materials/node_palette.tres")
const FISH_SHADER := preload("res://shaders/fish.gdshader")
const PALETTE := preload("res://art/palette.png")
const SETTINGS_PATH := "user://settings.cfg"
const DODGE_COLOR := Color("ff8a7a")
## Where the rod's tip ends, past the Tip section's base (tools/blender/make_models.py rod()).
const ROD_TIP_LENGTH := 0.45
## Rod tilt (radians up from straight ahead) at rest, wound back over the shoulder, at the end of
## the forward stroke, and while waiting on the float.
const ROD_REST := 0.5
const ROD_BACK := 1.95
const ROD_FORWARD := 0.12
const ROD_WAIT := 0.42
const ROD_FIGHT := 0.75
## A fish this close (m) to where the float lands is cast right on top of: it bolts regardless.
const ON_TOP := 0.8
## Small fish a pike may take off the line (kg, by the species' heaviest).
const STEALABLE_UNDER := 2.0
const STEAL_RATE := 0.035

## Optional (settings.cfg [gameplay] fishing_prompts; debug menu, Player tab): a small hint for
## each move. Off by default: the cues are meant to be read from the world.
static var prompt_assist := false
static var _settings_loaded := false

## Cast range (m, along your aim), plus this every 10 Fishing levels.
@export var cast_range := 14.0
@export var range_per_10_levels := 1.0
@export var line_notches := 3

@export_group("Cast timing")
## Seconds swinging back, then forward; the sweet spot is this far into the forward stroke.
@export var back_time := 0.3
@export var forward_time := 0.42
@export_range(0.0, 1.0) var sweet_spot := 0.5

@onready var player: CharacterBody3D = get_parent()

var state := State.IDLE
var aim_point := Vector3.INF
var aim_water: WaterBody
## The rod's viewmodel node (Player.tools[&"rod"]).
var rod: Node3D

var lure: FishingLure
var fish: Fish  # on the line
var fight: FishFight

var _vm_cam: Camera3D
var _rod_pivot: Node3D
var _mid: Node3D
var _tip: Node3D
var _angle := ROD_REST
var _bend := 0.0
var _jerk := 0.0       # rod tip impulse (springs back)
var _jerk_vel := 0.0
var _rod_yaw := 0.0
var _line: MeshInstance3D
var _line_mesh := ArrayMesh.new()
var _line_tension := 0.0
var _rng := RandomNumberGenerator.new()

var _t := 0.0                 # time in the current state
var _cast_from := Vector3.ZERO
var _cast_aim := Vector3.ZERO
var _cast_water: WaterBody
var _verdict: Dictionary = {}
var _whipped := false
var _flight_from := Vector3.ZERO
var _flight_to := Vector3.ZERO
var _flight_time := 0.5
var _land_water: WaterBody
var _retrieve_from := Vector3.ZERO
var _reeled := 0.0

# the fight
var _size := 0.0
var _perfect_strike := false
var _dir := Vector3.FORWARD    # from the player to the fish (flat)
var _run_dir := Vector3.FORWARD
var _jump_t := -1.0
var _tug_kick := 0.0
var _landing := false
var _flash := false
var _thief: Fish
var _steal_tried := false
var _done_wait := 0.0

# HUD
var _hud: CanvasLayer
var _notch_box: HBoxContainer
var _notches: Array[ColorRect] = []
var _prompt: Label
var _prompt_time := 0.0


func _ready() -> void:
	_load_settings()
	_rng.randomize()
	_vm_cam = player.get_node("Viewmodel/SubViewport/Camera3D")
	_build_rod()
	_build_line()
	_build_hud()


# --- settings ------------------------------------------------------------------------------

static func _load_settings() -> void:
	if _settings_loaded:
		return
	_settings_loaded = true
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		prompt_assist = bool(cfg.get_value("gameplay", "fishing_prompts", false))


static func set_prompt_assist(on: bool) -> void:
	prompt_assist = on
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)  # keep the graphics section
	cfg.set_value("gameplay", "fishing_prompts", on)
	cfg.save(SETTINGS_PATH)


# --- the player asks ------------------------------------------------------------------------

## The rod is out and doing something: keep it in hand, don't target anything else.
func is_busy() -> bool:
	return state != State.IDLE


func can_cast() -> bool:
	return state == State.IDLE and aim_water != null


## Rooted while a fish is on: a slow shuffle, no jumping (Player._move).
func is_fighting() -> bool:
	return state == State.FIGHT


func move_scale() -> float:
	return 0.18 if state == State.FIGHT else 1.0


func clear_target() -> void:
	aim_water = null
	aim_point = Vector3.INF


## Called by the Player each physics frame when nothing else is targeted (and the spear can't
## reach): water beyond the spear's reach and within cast range, in sight.
func update_target() -> void:
	clear_target()
	var cam: Camera3D = player.camera
	var from := cam.global_position
	var dir := -cam.global_basis.z
	if dir.y > -0.01:
		return
	var spear_reach: float = player.spearfishing.reach
	var max_range := _range()
	for node in get_tree().get_nodes_in_group("water"):
		var wb := node as WaterBody
		var t := (wb.surface_height - from.y) / dir.y
		if t <= spear_reach or t > max_range:
			continue
		var p := from + dir * t
		if wb.depth_here(p) < 0.15:
			continue
		var query := PhysicsRayQueryParameters3D.create(from, p, WORLD_MASK, [player.get_rid()])
		if not player.get_world_3d().direct_space_state.intersect_ray(query).is_empty():
			continue  # the bank, a rock or a tree is in the way
		aim_water = wb
		aim_point = p
		return


func _range() -> float:
	return cast_range + range_per_10_levels * floorf(Skills.level(&"fishing") / 10.0)


## Pressed with the rod out and water in range: start the back-cast.
func start_cast() -> void:
	if not can_cast():
		return
	state = State.BACKCAST
	_t = 0.0
	_whipped = false
	_cast_aim = aim_point
	_cast_water = aim_water
	_cast_from = player.global_position
	Sfx.play(load("res://audio/fishing/creak.tres"), 1.3, -14.0)


# --- every frame ---------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	_t += delta
	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	match state:
		State.BACKCAST:
			_update_cast()
		State.FLIGHT:
			if _t >= _flight_time:
				_splash_down()
		State.WAITING:
			if captured and Input.is_action_just_pressed("gather"):
				_strike()
			elif not is_instance_valid(lure) or _flat(player.global_position, lure.global_position) > _range() * 1.4 \
					or not player.is_on_floor() and player.velocity.y < -6.0:
				_retrieve()
		State.RETRIEVE:
			if _t >= 0.45:
				_finish_retrieve()
		State.FIGHT:
			_update_fight(delta, captured)
		State.DONE:
			if _t >= _done_wait:
				_clear_line()
				state = State.IDLE
	_update_prompt(delta)


func _process(delta: float) -> void:
	_animate_rod(delta)
	_draw_line()


# --- the cast ------------------------------------------------------------------------------

func _sweet_time() -> float:
	return back_time + forward_time * sweet_spot


func _update_cast() -> void:
	# the whip: timed so the swoosh peaks on the sweet spot (the clip peaks 0.13 s in)
	if not _whipped and _t >= _sweet_time() - 0.13:
		_whipped = true
		Sfx.play(load("res://audio/fishing/cast_whip.tres"), 1.0, -4.0)
	var released := not Input.is_action_pressed("gather")
	var total := back_time + forward_time
	if released or _t >= total:
		var error := _t - _sweet_time()
		if not released:
			error += 0.08  # held right through the stroke: it slaps down short
		_release(error)


func _release(error: float) -> void:
	var scale := FishFight.level_scales(Skills.level(&"fishing"), 1).x
	_verdict = RodCast.judge(error, scale)
	var to := RodCast.landing(_cast_from, _cast_aim, _verdict, _rng)
	_land_water = _water_at(to)
	if _land_water == null:  # scattered onto the bank: it lands where the water starts
		for i in 12:
			to = to.lerp(_cast_aim, 0.25)
			_land_water = _water_at(to)
			if _land_water:
				break
		if _land_water == null:
			to = _cast_aim
			_land_water = _cast_water
	_flight_to = Vector3(to.x, _land_water.surface_height, to.z)
	_flight_from = _tip_world()
	_flight_time = 0.35 + _flat(_flight_from, _flight_to) * 0.035
	lure = FishingLure.new()
	lure.name = "Float"
	player.get_parent().add_child(lure)
	lure.global_position = _flight_from
	lure.water = null  # not floating yet
	lure.remove_from_group("lure")
	state = State.FLIGHT
	_t = 0.0


func _water_at(p: Vector3) -> WaterBody:
	var w := WaterBody.surface_at(get_tree(), p)
	return w if w and w.depth_here(p) > 0.1 else null


func _flight_pos(f: float) -> Vector3:
	var p := _flight_from.lerp(_flight_to, f)
	var arc := 1.2 + _flat(_flight_from, _flight_to) * 0.12
	return p + Vector3.UP * arc * 4.0 * f * (1.0 - f)


func _splash_down() -> void:
	var at := _flight_to
	lure.add_to_group("lure")
	lure.land(_land_water, at)
	lure.calm = Village.stat(&"fish_calm")
	lure.tell.connect(_on_tell)
	var q: int = _verdict["quality"]
	var sounds := {RodCast.Quality.PERFECT: "plip", RodCast.Quality.GOOD: "plop", RodCast.Quality.BAD: "splosh"}
	_play_at("res://audio/fishing/%s.tres" % sounds[q], at, 1.0, -2.0 if q != RodCast.Quality.PERFECT else -6.0)
	WaterRipple.spawn(_land_water, at, [0.6, 1.2, 2.0][q], [0.5, 0.8, 1.1][q])
	FishPond.disturb(get_tree(), at, _verdict["loudness"])
	if _fish_near(at, ON_TOP):  # right on top of them: no cast is soft enough
		FishPond.disturb(get_tree(), at, 2.0)
	if q == RodCast.Quality.PERFECT:
		lure.curious = 6.0
	state = State.WAITING
	_t = 0.0


func _fish_near(at: Vector3, radius: float) -> bool:
	for node in get_tree().get_nodes_in_group("fish_school"):
		for f in (node as FishSchool).fish:
			if f.lure == null and _flat(f.global_position, at) < radius:
				return true
	return false


# --- the bite ------------------------------------------------------------------------------

func _on_tell(kind: StringName) -> void:
	if not is_instance_valid(lure):
		return
	var at := lure.global_position
	match kind:
		&"nibble":
			_play_at("res://audio/fishing/nibble.tres", at, 1.0, -4.0)
			_kick(0.05)
		&"tap":
			_play_at("res://audio/fishing/tap.tres", at, 1.0, -3.0)
			_kick(0.08)
		&"take":
			_play_at("res://audio/fishing/bloop.tres", at, 1.0, 0.0)
			_kick(0.22)
			_show_prompt("strike!")
		&"spat":
			_play_at("res://audio/fishing/nibble.tres", at, 0.8, -6.0)
		&"spooked":
			_play_at("res://audio/fishing/spook.tres", at, 1.0, -2.0)


func _strike() -> void:
	var on := lure.fish
	var result := lure.strike()
	_kick(-0.35)  # the rod jerks back
	Sfx.play(load("res://audio/fishing/jerk.tres"), 1.0, -4.0)
	match result:
		&"hooked":
			_start_fight(on, lure.strike_timing())
		_:
			_retrieve()


func _retrieve() -> void:
	if is_instance_valid(lure):
		lure.retire()
		_retrieve_from = lure.global_position
	state = State.RETRIEVE
	_t = 0.0
	_reeled = 0.0


func _finish_retrieve() -> void:
	if is_instance_valid(lure):
		lure.queue_free()
	lure = null
	_clear_line()
	state = State.IDLE


# --- the fight -----------------------------------------------------------------------------

func _start_fight(f: Fish, timing: float) -> void:
	fish = f
	if is_instance_valid(f.school):
		f.school.remove_fish(f)
		FishPond.disturb(get_tree(), f.global_position, 1.5)  # the rest of them scatter
	f.lure = lure
	_size = pow(_rng.randf(), 1.6)  # big ones are rare
	_perfect_strike = timing < 0.5
	var scales := FishFight.level_scales(Skills.level(&"fishing"), f.species.required_level)
	var notches := line_notches + int(Village.stat(&"line_notches"))
	fight = FishFight.new(f.species, _flat(player.global_position, f.global_position), _size, scales.x, scales.y, notches, _rng)
	_dir = _flat_dir(player.global_position, f.global_position)
	_run_dir = _dir
	_jump_t = -1.0
	_landing = false
	_flash = false
	_thief = null
	_steal_tried = false
	lure.sink = 1.0
	state = State.FIGHT
	_t = 0.0
	Juice.shake(1.2)
	_bend = 1.0
	_refresh_notches()
	_notch_box.visible = true


func _update_fight(delta: float, captured: bool) -> void:
	if not is_instance_valid(fish):
		_end_fight(false)
		return
	var reel := captured and Input.is_action_pressed("gather")
	var click := captured and Input.is_action_just_pressed("gather")
	var bow := captured and Input.is_action_just_pressed("bow")
	for e in fight.step(delta, reel, click, bow):
		_on_fight_event(e)
		if state != State.FIGHT:
			return
	_try_steal(delta)
	_place_fish(delta)
	_tug(delta)
	# the rod loads up while you reel against it, and under a run
	var target := 0.25
	if fight.phase == FishFight.Phase.ACTIVE and fight.move == FishFight.Move.RUN:
		target = 1.0
	elif reel:
		target = 0.7
	_bend = lerpf(_bend, target, 1.0 - exp(-6.0 * delta))
	_line_tension = 1.0


func _on_fight_event(e: Dictionary) -> void:
	var at := fish.global_position
	match e["type"]:
		"move":
			if e["move"] == FishFight.Move.PULL:
				Sfx.play(load("res://audio/fishing/creak.tres"), 1.0, -8.0)
		"telegraph":
			match e["move"]:
				FishFight.Move.RUN:
					Sfx.play(load("res://audio/fishing/hiss.tres"), 1.0, -6.0)
					_run_dir = _dir.rotated(Vector3.UP, _rng.randf_range(-0.8, 0.8))
					_show_prompt("let go")
				FishFight.Move.HEADSHAKE:
					Sfx.play(load("res://audio/fishing/creak.tres"), 1.15, -4.0)
					_kick(0.06)
					_show_prompt("click on the jerks")
				FishFight.Move.JUMP:
					_play_at("res://audio/fishing/bulge.tres", at, 1.0, -2.0)
					_ripple(at, 1.4)
					_show_prompt("bow (RMB) on the splash")
		"count":
			_kick(0.06)
			Sfx.play(load("res://audio/fishing/creak.tres"), 1.25, -8.0)
		"bolt":
			_kick(0.25)
			_ripple(at, 1.0)
		"jerk":
			_kick(0.4)
			Sfx.play(load("res://audio/fishing/jerk.tres"), _rng.randf_range(0.95, 1.05), -2.0)
			_ripple(at, 0.6)
		"jerk_hit":
			Sfx.play(load("res://audio/fishing/reel.tres"), 1.3, -2.0)
		"splash":
			_jump_t = 0.0
			_tug_kick = 0.45
			_play_at("res://audio/fishing/jump.tres", at, 1.0, 0.0)
			_ripple(at, 1.6)
		"bowed":
			_kick(-0.3)
		"reel":
			_reeled += e["amount"]
			if _reeled >= 0.16:
				_reeled = 0.0
				Sfx.play(load("res://audio/fishing/reel.tres"), _rng.randf_range(0.95, 1.05), -6.0)
		"damage":
			Sfx.play(load("res://audio/fishing/strain.tres"), 1.0, -3.0)
			Juice.shake(1.6)
			_kick(0.3)
			_refresh_notches(true)
		"snap":
			_play_at("res://audio/fishing/snap.tres", player.global_position + Vector3.UP, 1.0, 0.0)
			if Skills.level(&"fishing") < fish.species.required_level:
				PopupText.spawn(player.get_parent(), _surface(at) + Vector3.UP * 0.4,
					"%s %d" % [Skills.display_name(&"fishing"), fish.species.required_level], DODGE_COLOR, 5)
			_end_fight(false)
		"landing":
			_landing = true
			_show_prompt("grab on the flash")
		"flash":
			_flash = true
			fish.flash()
			Sfx.play(load("res://audio/fishing/tap.tres"), 0.8, -10.0)
		"flash_end":
			_flash = false
		"thrash":
			_play_at("res://audio/fishing/thrash.tres", at, 1.0, -1.0)
			_ripple(at, 0.8)
		"landed":
			_land_fish()


## Where the fish is: along `_dir` from you at the fight's distance, in the water (pushed out to
## where the water starts if that's on the bank), mid-depth; jumping, it arcs out of the water.
func _place_fish(delta: float) -> void:
	var me := player.global_position
	if fight.phase == FishFight.Phase.ACTIVE and fight.move == FishFight.Move.RUN:
		_dir = _turn(_dir, _run_dir, 1.8 * delta)
	else:  # dragged in, it swings about a little
		_dir = _dir.rotated(Vector3.UP, sin(_t * 1.3) * 0.25 * delta)
	var want := maxf(fight.distance, 0.8)
	var target := Vector3.INF
	for k in 24:  # walk out until it's water
		var d := want + k * 0.5
		var p := Vector3(me.x, 0.0, me.z) + _dir * d
		var w := WaterBody.surface_at(get_tree(), p)
		if w and w.depth_here(p) > 0.08:
			var depth := w.depth_here(p)
			target = Vector3(p.x, w.surface_height - clampf(depth * 0.4, 0.06, 0.45), p.z)
			if _landing:
				target.y = w.surface_height - 0.05
			break
	if target == Vector3.INF:  # no water that way: turn back toward where it is
		_dir = _flat_dir(me, fish.global_position)
		target = fish.global_position
	if _jump_t >= 0.0:
		_jump_t += delta
		var k := _jump_t / 0.55
		if k >= 1.0:
			_jump_t = -1.0
			_ripple(fish.global_position, 1.4)
		else:
			target.y = _surface(target).y + sin(PI * k) * 0.65
	var prev := fish.global_position
	fish.global_position = prev.lerp(target, 1.0 - exp(-(14.0 if _jump_t >= 0.0 else 5.0) * delta))
	# facing: away on a run, side-on when it flashes at your feet, otherwise thrashing toward you
	var face := -_dir if not (fight.move == FishFight.Move.RUN and fight.phase == FishFight.Phase.ACTIVE) else _dir
	if _landing:
		face = _dir.cross(Vector3.UP) if _flash else -_dir.rotated(Vector3.UP, sin(_t * 9.0) * 0.6)
	var basis := Basis.looking_at(face, Vector3.UP)
	if _jump_t >= 0.0:
		basis = basis.rotated(basis.x, sin(PI * _jump_t / 0.55) * 0.9 - 0.45)
	fish.global_basis = fish.global_basis.orthonormalized().slerp(basis, clampf(10.0 * delta, 0.0, 1.0))
	fish.set_swim(1.0 if _landing or fight.move == FishFight.Move.RUN else 0.65)
	lure.global_position = _surface(fish.global_position)


## The rod pulls your aim toward the fish: a gentle drift, harder on a run, a jolt on a jump.
func _tug(delta: float) -> void:
	var to: Vector3 = fish.global_position - player.camera.global_position
	var flat := Vector3(to.x, 0.0, to.z)
	if flat.length() < 0.3:
		return
	var want_yaw := atan2(-flat.x, -flat.z)
	var diff := angle_difference(player.rotation.y, want_yaw)
	var rate := 0.3
	if fight.move == FishFight.Move.RUN and fight.phase == FishFight.Phase.ACTIVE:
		rate = 1.1
	var turn := 0.0
	if absf(diff) > 0.15:
		turn = signf(diff) * minf(absf(diff) - 0.15, rate * delta)
	if _tug_kick > 0.0:
		turn += diff * minf(_tug_kick * 6.0 * delta, 1.0)
		_tug_kick = maxf(_tug_kick - delta, 0.0)
	player.rotate_y(turn)
	var want_pitch := atan2(to.y, flat.length())
	var pitch_diff: float = want_pitch - player._pitch
	if absf(pitch_diff) > 0.2:
		player._pitch += signf(pitch_diff) * minf(absf(pitch_diff) - 0.2, rate * 0.5 * delta)


## A pike in the same water may take a small fish off your line.
func _try_steal(delta: float) -> void:
	if _thief:
		if not is_instance_valid(_thief):
			_thief = null
			return
		var off := fish.global_position - _thief.global_position
		if off.length() < 0.35:
			_steal()
			return
		_thief.velocity = off.normalized() * _thief.species.lunge_speed * 0.7
		_thief.global_position += _thief.velocity * delta
		_thief.global_basis = Basis.looking_at(off.normalized(), Vector3.UP)
		_thief.set_swim(1.0)
		return
	if _steal_tried or _landing or fish.species.weight.y > STEALABLE_UNDER:
		return
	if _rng.randf() >= STEAL_RATE * delta:
		return
	_steal_tried = true
	for node in get_tree().get_nodes_in_group("fish_school"):
		var school := node as FishSchool
		if school.species.hunts == &"" or school.fish.is_empty() or school.water == null \
				or not school.water.contains(fish.global_position):
			continue
		var pike := school.fish[0]
		if pike.lure != null or pike.state != Fish.State.CALM or pike.global_position.distance_to(fish.global_position) > 9.0:
			continue
		_thief = pike
		pike.lure = lure
		school.remove_fish(pike)
		WaterRipple.spawn(school.water, _surface(pike.global_position), 1.6)
		return


func _steal() -> void:
	var at := fish.global_position
	_play_at("res://audio/fishing/jump.tres", at, 0.85, 0.0)
	_ripple(at, 2.0)
	PopupText.spawn(player.get_parent(), _surface(at) + Vector3.UP * 0.5, "Pike!", DODGE_COLOR, 6)
	fish.queue_free()  # eaten
	fish = _thief
	_thief = null
	var size := pow(_rng.randf(), 1.6)
	_size = size
	var scales := FishFight.level_scales(Skills.level(&"fishing"), fish.species.required_level)
	fight.switch_species(fish.species, size, scales.x, scales.y)
	Juice.shake(2.0)
	_kick(0.5)


func _land_fish() -> void:
	var s := fish.species
	var at := fish.global_position
	var clean := not fight.damaged
	var perfect: bool = clean and _verdict.get("quality", -1) == RodCast.Quality.PERFECT and _perfect_strike
	var under := Skills.level(&"fishing") < s.required_level
	var mult := (1.5 if perfect else (1.25 if clean else 1.0)) * (1.0 + 0.5 * _size) * (1.5 if under else 1.0)
	var gained := Skills.add_xp(&"fishing", roundi(s.xp * mult))
	var kg := lerpf(s.weight.x, s.weight.y, _size)
	Juice.hitstop(0.12 if perfect else 0.08)
	Juice.shake(3.0 if perfect else 2.2)
	_kick(-0.6)
	_play_at("res://audio/fishing/hoist.tres", at, 1.0, 0.0)
	_ripple(at, 1.4)
	var color := Skills.color(&"fishing")
	var top := _surface(at) + Vector3.UP * 0.7
	if perfect or clean:
		PopupText.spawn(player.get_parent(), top + Vector3.UP * 0.2, "Perfect!" if perfect else "Clean!", color, 7 if perfect else 6)
	PopupText.spawn(player.get_parent(), top, "%s, %.1f kg" % [Items.display_name(s.id), kg], Color.WHITE, 5, 0.08)
	if gained > 0:
		PopupText.spawn(player.get_parent(), top + Vector3.DOWN * 0.18, "+%d" % gained, color, 4, 0.16)
	_hoist(fish)
	fish = null
	_end_fight(true)


## The landed fish swings up out of the water toward you, wriggling, then into the inventory.
func _hoist(f: Fish) -> void:
	var copy := f.species.model.instantiate() as Node3D
	var mat := ShaderMaterial.new()
	mat.shader = FISH_SHADER
	mat.set_shader_parameter("palette", PALETTE)
	for m in copy.find_children("*", "MeshInstance3D", true, false):
		var mesh := m as MeshInstance3D
		mesh.material_override = mat
		mesh.set_instance_shader_parameter("body_length", f.length)
		mesh.set_instance_shader_parameter("swim", 1.0)
		mesh.set_instance_shader_parameter("phase", _rng.randf() * TAU)
	player.get_parent().add_child(copy)
	copy.global_transform = f.global_transform
	var id := f.species.id
	f.queue_free()  # (already off its school's books since the hook was set)
	var cam: Camera3D = player.camera
	var up := cam.global_position + (-cam.global_basis.z) * 0.9 + Vector3.DOWN * 0.15
	var t := copy.create_tween().set_ignore_time_scale(true)
	t.tween_property(copy, "global_position", up, 0.32).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(copy, "rotation:z", copy.rotation.z + PI * 0.5, 0.32)
	t.tween_interval(0.22)
	t.tween_property(copy, "scale", Vector3.ONE * 0.05, 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	t.parallel().tween_property(copy, "global_position", up + cam.global_basis.x * 0.3 + Vector3.DOWN * 0.4, 0.16)
	t.tween_callback(func() -> void:
		Inventory.add(id)  # (no double catches on a rod: the hut's perk there is a line notch)
		Sfx.play_pickup()
		copy.queue_free())


func _end_fight(landed: bool) -> void:
	if is_instance_valid(_thief):
		_give_back(_thief)
	_thief = null
	if not landed and is_instance_valid(fish):
		_give_back(fish)
	fish = null
	fight = null
	_landing = false
	_notch_box.visible = false
	if is_instance_valid(lure):
		lure.queue_free()  # the float comes back with the fish, or on the slack line
	lure = null
	_bend = 0.0
	_line_tension = 0.0
	state = State.DONE
	_t = 0.0
	_done_wait = 0.5


## A fish that got away swims back to its school (or just off, if its school is gone).
func _give_back(f: Fish) -> void:
	if is_instance_valid(f.school) and f.school.is_inside_tree():
		f.school.adopt(f)
		f.velocity = _flat_dir(player.global_position, f.global_position) * f.species.flee_speed
	else:
		f.queue_free()


# --- the rod and the line --------------------------------------------------------------------

func _build_rod() -> void:
	var grip := Node3D.new()
	grip.name = "RodGrip"
	grip.position = Vector3(0.27, -0.36, -0.34)
	grip.rotation = Vector3(0.0, 0.1, -0.06)
	_vm_cam.add_child(grip)
	rod = Node3D.new()
	rod.name = "Rod"
	rod.visible = false
	grip.add_child(rod)
	_rod_pivot = Node3D.new()
	_rod_pivot.name = "Pivot"
	rod.add_child(_rod_pivot)
	var model := ROD_MODEL.instantiate() as Node3D
	_rod_pivot.add_child(model)
	for m in model.find_children("*", "MeshInstance3D", true, false):
		var mesh := m as MeshInstance3D
		mesh.layers = 2
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mesh.material_override = TOOL_MATERIAL
	# chain the sections on pivots at their bases, so the rod can bend: Mid hangs off Butt's end,
	# Tip off Mid's; each guide rides the section it sits on
	var mid_mesh := model.find_child("Mid", true, false) as Node3D
	var tip_mesh := model.find_child("Tip", true, false) as Node3D
	_mid = Node3D.new()
	_mid.name = "MidBend"
	model.add_child(_mid)
	_mid.position = mid_mesh.position
	_tip = Node3D.new()
	_tip.name = "TipBend"
	_mid.add_child(_tip)
	_tip.position = tip_mesh.position - mid_mesh.position
	for n in model.get_children():
		if n is MeshInstance3D and String(n.name).begins_with("Guide"):
			var along := -(n as Node3D).position.z
			if along > -tip_mesh.position.z:
				n.reparent(_tip, true)
			elif along > -mid_mesh.position.z:
				n.reparent(_mid, true)
	mid_mesh.reparent(_mid, true)
	tip_mesh.reparent(_tip, true)


func _kick(amount: float) -> void:
	_jerk_vel += amount * 18.0


func _animate_rod(delta: float) -> void:
	var target := ROD_REST
	match state:
		State.BACKCAST:
			var t := _t
			if t < back_time:
				target = lerpf(ROD_REST, ROD_BACK, ease(t / back_time, 0.5))
			else:
				target = lerpf(ROD_BACK, ROD_FORWARD, ease(clampf((t - back_time) / forward_time, 0.0, 1.0), 2.2))
			_angle = target  # the stroke itself is exact
		State.FLIGHT:
			target = ROD_FORWARD
		State.WAITING:
			target = ROD_WAIT
		State.RETRIEVE:
			target = ROD_WAIT + 0.15
		State.FIGHT:
			target = ROD_FIGHT
	if state != State.BACKCAST:
		_angle = lerpf(_angle, target, 1.0 - exp(-7.0 * delta))
	# the tip's impulse: a damped spring
	_jerk_vel += (-_jerk * 160.0 - _jerk_vel * 14.0) * delta
	_jerk += _jerk_vel * delta
	if state != State.FIGHT:
		_bend = lerpf(_bend, 0.08 if state == State.WAITING else 0.0, 1.0 - exp(-5.0 * delta))
	_rod_pivot.rotation.x = _angle + _jerk * 0.15
	_mid.rotation.x = -_bend * 0.3 - _jerk * 0.25
	_tip.rotation.x = -_bend * 0.55 - _jerk * 0.55
	# point the rod at the fish (or the float), within reason
	var yaw := 0.0
	var at := Vector3.INF
	if is_instance_valid(fish):
		at = fish.global_position
	elif is_instance_valid(lure) and state in [State.WAITING, State.FIGHT]:
		at = lure.global_position
	if at != Vector3.INF:
		var local: Vector3 = player.camera.global_transform.affine_inverse() * at
		if local.z < -0.1:
			yaw = clampf(atan2(-local.x, -local.z), -0.5, 0.5) * 0.7
	_rod_yaw = lerpf(_rod_yaw, yaw, 1.0 - exp(-6.0 * delta))
	_rod_pivot.rotation.y = _rod_yaw


## The rod tip in the world, as the main camera would have to draw it to line up with the
## viewmodel's (its own, narrower FOV): the same point in camera space, widened by the FOV ratio.
func _tip_world() -> Vector3:
	var tip := _tip.global_transform * Vector3(0, 0, -ROD_TIP_LENGTH)
	var cam: Camera3D = player.camera
	var local := _vm_cam.global_transform.affine_inverse() * tip
	if local.z > -0.05:  # behind the eye (wound back over the shoulder)
		return cam.global_position + cam.global_basis.y * 0.4 - cam.global_basis.z * 0.2
	var widen := tan(deg_to_rad(cam.fov) * 0.5) / tan(deg_to_rad(_vm_cam.fov) * 0.5)
	return cam.global_transform * Vector3(local.x * widen, local.y * widen, local.z)


## The line is one triangle strip whose vertices are rewritten in place every frame (no new GPU
## buffer per frame), so the mesh is made once with LINE_POINTS points.
const LINE_POINTS := 24


func _build_line() -> void:
	var verts := PackedVector3Array()
	verts.resize((LINE_POINTS + 1) * 2)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	_line_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLE_STRIP, arrays)
	_line_mesh.custom_aabb = AABB(Vector3.ONE * -2000.0, Vector3.ONE * 4000.0)  # never culled
	_line = MeshInstance3D.new()
	_line.name = "FishingLine"
	_line.mesh = _line_mesh
	_line.top_level = true
	_line.visible = false
	_line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = Color(0.92, 0.94, 0.97, 0.6)
	_line.material_override = mat
	add_child(_line)


func _clear_line() -> void:
	_line.visible = false


## From the rod tip to the float: a sagging curve while it's slack (lying on the water where it
## reaches it), straight when there's a fish on.
func _draw_line() -> void:
	if state == State.IDLE or state == State.DONE or state == State.BACKCAST or not is_instance_valid(lure):
		_line.visible = false
		return
	var a := _tip_world()
	var b := lure.global_position
	match state:
		State.FLIGHT:
			b = _flight_pos(clampf(_t / _flight_time, 0.0, 1.0))
			lure.global_position = b
		State.RETRIEVE:
			b = _retrieve_from.lerp(a, ease(clampf(_t / 0.45, 0.0, 1.0), 0.6))
			lure.global_position = b
	var length := a.distance_to(b)
	var sag := (1.0 - _line_tension) * length * (0.02 if state == State.FLIGHT else 0.035)
	var water_y := -INF
	if state == State.WAITING and lure.water:
		water_y = lure.water.surface_height + 0.004
	var cam: Camera3D = player.camera
	var pts := PackedVector3Array()
	for i in LINE_POINTS + 1:
		var f := float(i) / LINE_POINTS
		var p := a.lerp(b, f) + Vector3.DOWN * sag * 4.0 * f * (1.0 - f)
		p.y = maxf(p.y, water_y)
		pts.append(p)
	var verts := PackedVector3Array()
	verts.resize((LINE_POINTS + 1) * 2)
	for i in pts.size():
		var p := pts[i]
		var along := pts[mini(i + 1, LINE_POINTS)] - pts[maxi(i - 1, 0)]
		var side := along.cross(cam.global_position - p)
		if side.length_squared() < 1e-10:
			side = cam.global_basis.x
		side = side.normalized() * maxf(0.0011 * cam.global_position.distance_to(p), 0.0008)
		verts[i * 2] = p - side
		verts[i * 2 + 1] = p + side
	RenderingServer.mesh_surface_update_vertex_region(_line_mesh.get_rid(), 0, 0, verts.to_byte_array())
	_line.visible = true


# --- HUD ------------------------------------------------------------------------------------

func _build_hud() -> void:
	_hud = CanvasLayer.new()
	_hud.name = "FishingHud"
	_hud.layer = 2
	add_child(_hud)
	var center := Control.new()
	center.set_anchors_preset(Control.PRESET_CENTER)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(center)
	_notch_box = HBoxContainer.new()
	_notch_box.add_theme_constant_override("separation", 5)
	_notch_box.position = Vector2(-24, 22)
	_notch_box.visible = false
	_notch_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(_notch_box)
	_prompt = Label.new()
	_prompt.position = Vector2(-150, 34)
	_prompt.size = Vector2(300, 24)
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.add_theme_font_size_override("font_size", 15)
	_prompt.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_prompt.add_theme_constant_override("outline_size", 5)
	_prompt.modulate = Color(1, 1, 1, 0)
	_prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(_prompt)


## The line notches under the crosshair: one short bar each, frayed red when lost.
func _refresh_notches(flash := false) -> void:
	var total := fight.max_notches if fight else line_notches
	while _notches.size() < total:
		var bar := ColorRect.new()
		bar.custom_minimum_size = Vector2(10, 3)
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_notch_box.add_child(bar)
		_notches.append(bar)
	for i in _notches.size():
		var bar := _notches[i]
		bar.visible = i < total
		var alive := fight != null and i < fight.notches
		bar.color = Color(0.92, 0.96, 1.0, 0.85) if alive else Color(1.0, 0.45, 0.4, 0.55)
		bar.custom_minimum_size = Vector2(10, 3) if alive else Vector2(6, 2)
	_notch_box.position.x = -(total * 15 - 5) * 0.5
	if flash:
		var t := _notch_box.create_tween()
		_notch_box.modulate = Color(1.6, 0.6, 0.5)
		t.tween_property(_notch_box, "modulate", Color.WHITE, 0.35)


func _show_prompt(text: String) -> void:
	if not prompt_assist:
		return
	_prompt.text = text
	_prompt.modulate.a = 1.0
	_prompt_time = 0.9


func _update_prompt(delta: float) -> void:
	_prompt_time -= delta
	if _prompt_time <= 0.0 and _prompt.modulate.a > 0.0:
		_prompt.modulate.a = move_toward(_prompt.modulate.a, 0.0, delta * 4.0)


# --- helpers --------------------------------------------------------------------------------

func _play_at(path: String, at: Vector3, pitch: float, db: float) -> void:
	var p := AudioStreamPlayer3D.new()
	p.stream = load(path)
	p.pitch_scale = pitch
	p.volume_db = db
	p.unit_size = 6.0
	player.get_parent().add_child(p)
	p.global_position = at
	p.play()
	p.finished.connect(p.queue_free)


func _ripple(at: Vector3, size: float) -> void:
	var w := WaterBody.surface_at(get_tree(), at)
	if w:
		WaterRipple.spawn(w, Vector3(at.x, w.surface_height, at.z), size, 0.8)


func _surface(p: Vector3) -> Vector3:
	var w := WaterBody.surface_at(get_tree(), p)
	return Vector3(p.x, w.surface_height if w else p.y, p.z)


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


static func _flat_dir(from: Vector3, to: Vector3) -> Vector3:
	var d := Vector3(to.x - from.x, 0.0, to.z - from.z)
	return d.normalized() if d.length_squared() > 0.0001 else Vector3.FORWARD


static func _turn(dir: Vector3, to: Vector3, max_angle: float) -> Vector3:
	var a := dir.signed_angle_to(to, Vector3.UP)
	return dir.rotated(Vector3.UP, clampf(a, -max_angle, max_angle))
