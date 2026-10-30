class_name Animal
extends Node3D
## An animal about the country (plans/world-pass.md, phase 8): ambient only, nothing to hunt. It
## grazes (or pecks, or sits) a while, then ambles to somewhere else within `home_radius` of where
## it started, over the ground, never into water. A skittish one bolts from you and the dog when
## you come within its BOLT range, then settles again further off. Now and then it calls: a few
## seconds out of its kind's recording (audio/country/), heard near.
## Its model is one of the picked CC0 animals (models/animals/, Quaternius: rigged, with an
## AnimationPlayer), scaled from their big size to life; KINDS says which clips are which.

## Each kind: model, scale, walk and run speed (m/s), its clips (prefix-free names, first found
## wins), its call (audio/country/<call>.mp3, a few seconds of it) and the gap between calls.
const KINDS := {
	&"sheep": {"model": "sheep", "scale": 0.55, "walk": 0.6, "run": 3.0, "graze": ["Idle_Eating", "Eating"],
		"idle": ["Idle"], "walk_clip": ["Walk"], "run_clip": ["Run", "Gallop"], "call": "sheep", "gap": [14.0, 40.0], "db": -10.0},
	&"lamb": {"model": "sheep", "scale": 0.36, "walk": 0.7, "run": 3.0, "graze": ["Idle_Eating"], "idle": ["Idle"],
		"walk_clip": ["Walk"], "run_clip": ["Run"], "call": "lambs", "gap": [18.0, 50.0], "db": -12.0},
	&"cow": {"model": "cow", "scale": 0.34, "walk": 0.6, "run": 2.4, "graze": ["Eating", "Idle_Headlow"], "idle": ["Idle", "Idle_2"],
		"walk_clip": ["Walk"], "run_clip": ["Gallop"], "call": "cow", "gap": [25.0, 70.0], "db": -9.0},
	&"hen": {"model": "chicken", "scale": 0.32, "walk": 0.5, "run": 2.2, "graze": ["Idle_Peck"], "idle": ["Idle"],
		"walk_clip": ["Run"], "run_clip": ["Run"], "call": "hens", "gap": [10.0, 30.0], "db": -14.0, "walk_rate": 0.45},
	&"chick": {"model": "chick", "scale": 0.16, "walk": 0.4, "run": 1.6, "graze": ["Idle_Peck"], "idle": ["Idle"],
		"walk_clip": ["Run"], "run_clip": ["Run"], "call": "", "gap": [0.0, 0.0], "db": 0.0, "walk_rate": 0.5},
	&"pig": {"model": "pig", "scale": 0.45, "walk": 0.5, "run": 2.0, "graze": ["Idle_Eating"], "idle": ["Idle"],
		"walk_clip": ["Walk"], "run_clip": ["Run"], "call": "", "gap": [0.0, 0.0], "db": 0.0},
	&"horse": {"model": "horse", "scale": 0.36, "walk": 0.9, "run": 4.0, "graze": ["Eating"], "idle": ["Idle", "Idle_2"],
		"walk_clip": ["Walk"], "run_clip": ["Gallop"], "call": "horse", "gap": [30.0, 90.0], "db": -11.0},
	&"white_horse": {"model": "white_horse", "scale": 0.36, "walk": 0.9, "run": 4.0, "graze": ["Eating"], "idle": ["Idle"],
		"walk_clip": ["Walk"], "run_clip": ["Gallop"], "call": "horse", "gap": [30.0, 90.0], "db": -11.0},
	&"donkey": {"model": "donkey", "scale": 0.33, "walk": 0.7, "run": 3.0, "graze": ["Eating"], "idle": ["Idle", "Idle_2"],
		"walk_clip": ["Walk"], "run_clip": ["Gallop"], "call": "", "gap": [0.0, 0.0], "db": 0.0},
	&"deer": {"model": "deer", "scale": 0.3, "walk": 0.8, "run": 6.0, "graze": ["Eating", "Idle_Headlow"], "idle": ["Idle", "Idle_2"],
		"walk_clip": ["Walk"], "run_clip": ["Gallop"], "call": "deer_bark", "gap": [60.0, 180.0], "db": -14.0, "bolt_call": true},
	&"stag": {"model": "stag", "scale": 0.3, "walk": 0.8, "run": 6.0, "graze": ["Eating", "Idle_Headlow"], "idle": ["Idle", "Idle_2"],
		"walk_clip": ["Walk"], "run_clip": ["Gallop"], "call": "deer_bark", "gap": [60.0, 180.0], "db": -12.0, "bolt_call": true},
	# our own (tools/blender/make_critters.py): palette-painted, no rig, they hop
	&"rabbit": {"model": "rabbit_ours", "scale": 1.0, "walk": 0.9, "run": 5.5, "graze": [], "idle": [],
		"walk_clip": [], "run_clip": [], "call": "rabbit_thump", "gap": [0.0, 0.0], "db": -12.0, "bolt_call": true,
		"palette": true, "hop": 0.14},
	&"squirrel": {"model": "squirrel_ours", "scale": 1.0, "walk": 0.8, "run": 3.5, "graze": [], "idle": [],
		"walk_clip": [], "run_clip": [], "call": "squirrel", "gap": [25.0, 70.0], "db": -15.0, "palette": true, "hop": 0.09},
	&"frog": {"model": "frog_2", "scale": 0.09, "walk": 0.5, "run": 1.5, "graze": ["Frog_Idle"], "idle": ["Frog_Idle"],
		"walk_clip": ["Frog_Jump"], "run_clip": ["Frog_Jump"], "call": "", "gap": [0.0, 0.0], "db": 0.0},
}
## You (or the dog) this close and a skittish one bolts; it runs this far before settling.
const BOLT := 9.0
const BOLT_RUN := 18.0
## Calls are only played with you this near (m), heard out to CALL_RANGE.
const HEAR := 45.0
const CALL_RANGE := 30.0
const CALL_LENGTH := Vector2(1.8, 3.5)
## Seconds grazing or idling between ambles: [min, max].
const DWELL := Vector2(5.0, 16.0)
const WATER := -0.05
## Further than this from you it rests: no thinking, its animation paused (there are dozens).
const AWAKE := 120.0

@export var kind: StringName = &"sheep"
@export var home_radius := 12.0
@export var skittish := false

var _def: Dictionary
var _home: Vector3
var _model: Node3D
var _anim: AnimationPlayer
var _clips := {}  # role -> clip name
var _goal := Vector3.INF
var _speed := 0.0
var _dwell := 0.0
var _bolting := false
var _call_in := 0.0
var _voice: AudioStreamPlayer3D
var _voice_left := 0.0
var _terrain: Terrain3D
var _rng := RandomNumberGenerator.new()
var _hop := 0.0  # how far through a hop (our rigless ones bob along)


func _ready() -> void:
	add_to_group("animal")
	_def = KINDS[kind]
	_rng.seed = hash(str(global_position))
	_home = global_position
	_model = (load("res://models/animals/%s.glb" % _def["model"]) as PackedScene).instantiate() as Node3D
	_model.scale *= float(_def["scale"])
	add_child(_model)
	if _def.get("palette", false):
		for m in _model.find_children("*", "MeshInstance3D", true, false):
			(m as MeshInstance3D).material_override = PaletteMaterial.for_mesh((m as MeshInstance3D).mesh)
	var players := _model.find_children("*", "AnimationPlayer", true, false)
	_anim = players[0] as AnimationPlayer if not players.is_empty() else null
	for role in ["graze", "idle", "walk_clip", "run_clip"]:
		_clips[role] = _find_clip(_def[role])
	if String(_def["call"]) != "":
		_voice = AudioStreamPlayer3D.new()
		_voice.stream = load("res://audio/country/%s.mp3" % _def["call"])
		_voice.bus = &"Ambience"
		_voice.volume_db = float(_def["db"])
		_voice.max_distance = CALL_RANGE
		_voice.unit_size = 6.0
		add_child(_voice)
	_call_in = _rng.randf_range(2.0, float(_def["gap"][1]))
	_dwell = _rng.randf_range(0.0, DWELL.y)
	rotation.y = _rng.randf() * TAU
	_play("graze")
	_settle.call_deferred()


## Onto the ground where it starts (a resting one far from you doesn't move until you're near).
func _settle() -> void:
	_terrain = get_tree().get_first_node_in_group("terrain") as Terrain3D
	global_position.y = _ground(global_position)


func _physics_process(delta: float) -> void:
	if _terrain == null:
		_terrain = get_tree().get_first_node_in_group("terrain") as Terrain3D
	var player := get_tree().get_first_node_in_group("player") as Node3D
	var awake := player == null or player.global_position.distance_to(global_position) < AWAKE
	if _anim and _anim.active != awake:
		_anim.active = awake
	if not awake:
		return
	var threat := _threat()
	if skittish and threat != Vector3.INF and not _bolting:
		_bolt(threat)
	if _goal != Vector3.INF:
		_move(delta)
	else:
		_dwell -= delta
		if _dwell <= 0.0:
			_amble()
	_calls(delta)


## The nearest of you and the dog, if within BOLT; else INF.
func _threat() -> Vector3:
	var best := Vector3.INF
	for g in ["player", "dog"]:
		var n := get_tree().get_first_node_in_group(g) as Node3D
		if n and n.global_position.distance_to(global_position) < BOLT \
				and (best == Vector3.INF or n.global_position.distance_to(global_position) < best.distance_to(global_position)):
			best = n.global_position
	return best


func _bolt(from: Vector3) -> void:
	var away := Vector2(global_position.x - from.x, global_position.z - from.z).normalized()
	for tries in 8:
		var dir := away.rotated(_rng.randf_range(-0.6, 0.6))
		var p := global_position + Vector3(dir.x, 0, dir.y) * BOLT_RUN
		if _ground(p) > WATER:
			_goal = p
			_speed = float(_def["run"])
			_bolting = true
			_play("run_clip")
			if _def.get("bolt_call", false):
				_call()
			return


func _amble() -> void:
	for tries in 8:
		var a := _rng.randf() * TAU
		var r := sqrt(_rng.randf()) * home_radius
		var p := _home + Vector3(cos(a), 0, sin(a)) * r
		if _ground(p) > WATER and Vector2(p.x - global_position.x, p.z - global_position.z).length() > 1.5:
			_goal = p
			_speed = float(_def["walk"])
			_play("walk_clip")
			return
	_dwell = DWELL.x


func _move(delta: float) -> void:
	var to := Vector2(_goal.x - global_position.x, _goal.z - global_position.z)
	var d := to.length()
	if d < 0.25:
		_goal = Vector3.INF
		_model.position.y = 0.0
		if _bolting:  # settle where it ran to: home is here now, for a while
			_bolting = false
			_home = global_position
		_dwell = _rng.randf_range(DWELL.x, DWELL.y)
		_play("graze" if _rng.randf() < 0.65 else "idle")
		return
	var step := minf(_speed * delta, d)
	if _def.has("hop"):  # bounding along: a hop every ~0.4 m
		_hop += step / 0.4
		_model.position.y = absf(sin(_hop * PI)) * float(_def["hop"]) * (1.6 if _bolting else 1.0)
	var p := global_position + Vector3(to.x, 0, to.y) / d * step
	p.y = _ground(p)
	global_position = p
	var yaw := atan2(to.x, to.y)
	rotation.y = lerp_angle(rotation.y, yaw, 1.0 - exp(-6.0 * delta))


func _calls(delta: float) -> void:
	if _voice == null:
		return
	if _voice.playing:
		_voice_left -= delta
		if _voice_left <= 0.0:
			_voice.stop()
		return
	if float(_def["gap"][1]) <= 0.0:
		return  # (it only calls when it bolts)
	_call_in -= delta
	if _call_in <= 0.0:
		_call_in = _rng.randf_range(_def["gap"][0], _def["gap"][1])
		var player := get_tree().get_first_node_in_group("player") as Node3D
		if player and player.global_position.distance_to(global_position) < HEAR:
			_call()


## A few seconds out of its recording, from somewhere in it.
func _call() -> void:
	if _voice == null:
		return
	var length: float = _voice.stream.get_length()
	var take := _rng.randf_range(CALL_LENGTH.x, CALL_LENGTH.y)
	_voice.pitch_scale = _rng.randf_range(0.94, 1.06)
	_voice.play(_rng.randf_range(0.0, maxf(length - take, 0.0)))
	_voice_left = take


func _play(role: String) -> void:
	if _anim == null or _clips.get(role, "") == "":
		return
	var clip: String = _clips[role]
	var anim := _anim.get_animation(clip)
	if anim:
		anim.loop_mode = Animation.LOOP_LINEAR
	_anim.play(clip, 0.25)
	if role == "walk_clip":
		_anim.speed_scale = float(_def.get("walk_rate", 1.0))
	else:
		_anim.speed_scale = 1.0


## The first clip whose name ends in one of `names` ("AnimalArmature|Walk"...).
func _find_clip(names: Array) -> String:
	if _anim == null:
		return ""
	for n in names:
		for c in _anim.get_animation_list():
			if String(c).ends_with("|" + n) or String(c) == n:
				return c
	return ""


func _ground(p: Vector3) -> float:
	if _terrain and _terrain.data:
		var h: float = _terrain.data.get_height(p)
		if not is_nan(h):
			return h
	return p.y
