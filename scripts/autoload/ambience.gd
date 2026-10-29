extends Node
## The world's sound bed and the life in it (plans/cozy-sound.md, phase 8). CC0 field recordings,
## audio/ambience/SOURCES.md.
##   Beds, looped without a seam (LoopBed), crossfaded with the time of day and where you are:
##   the biome's own by day (its BiomeMood.ambience; the meadow's in the wild hills between
##   biomes), the evening bed around sunset, a faint far night bed after dark. Weather beds (the peak's
##   wind, the quarry's air: BiomeMood.ambience_always) carry on at night under the night bed.
##   Spot sounds: an owl now and then at night, very rarely a wolf far off (never near the
##   village), a dog from the village by day, the village's chatter and the smithy's hammer by
##   day, the forge fire always, frogs at the water from dusk.
##   Crickets: at night they sing from spots in the world (NatureSpots: shores, tree edges,
##   meadow grass), each one starting and stopping on its own; the few nearest you that are
##   singing get a positional voice, so you hear them louder as you walk up and fade behind you.
##   Water's lapping and streams are WaterBody's own (it asks for a bed with water_bed()).
## Everything plays on the Ambience bus; Biome.ambience_duck hushes it (the forge cutscene).

const DIR := "res://audio/ambience/"
## Each recording's level fix (dB), so they play at one loudness before mixing
## (tools/measure_music.gd -- --dir=res://audio/ambience/).
const TRIM := {&"meadow": 34.1, &"forest": 12.8, &"lake": 14.2, &"peak": 19.9, &"mine": 0.3,
	&"evening": 33.8, &"night": 12.5, &"owl": -7.2, &"wolf": 13.7, &"frogs": 2.9, &"lapping": -0.6,
	&"stream": 16.5, &"smithy": -0.8, &"chatter": 1.1, &"dog": 8.7, &"fire": -0.3}
## How loud each part plays (dB, after its trim): beds low under everything, spots a little up.
const MIX := {&"bed": -16.0, &"evening": -17.0, &"night": -17.0, &"owl": -16.0, &"wolf": -20.0,
	&"dog": -22.0, &"frogs": -16.0, &"chatter": -18.0, &"smithy": -14.0, &"fire": -12.0,
	&"lapping": -12.0, &"stream": -12.0}
## Seconds to settle into a new place or time of day.
const BLEND := 3.0
## Seconds between one-shots: [min, max].
const OWL_GAP := Vector2(35.0, 100.0)
const WOLF_GAP := Vector2(240.0, 600.0)
const DOG_GAP := Vector2(50.0, 150.0)
const FROG_GAP := Vector2(3.0, 9.0)
## The wolf keeps this far from the village (m from its centre) and calls from this far off.
const WOLF_CLEAR := 140.0
const WOLF_DISTANCE := 90.0
## The village's dog, chatter and hammer carry this far (m).
const VILLAGE_EARSHOT := 110.0
## The night bed (crickets everywhere) plays this quietly, a far wash under the cricket spots.
const NIGHT_WASH := 0.25
## Cricket spots in a world, at least this far apart; how many sing at once near you (voices),
## full volume within CRICKET_UNIT m, gone by CRICKET_REACH; seconds each one sings and rests
## [min, max], and how long it takes to start or stop.
const CRICKET_SPOTS := 130
const CRICKET_SPACING := 13.0
const CRICKET_VOICES := 4
const CRICKET_UNIT := 3.0
const CRICKET_REACH := 38.0
const CRICKET_SONG := Vector2(15.0, 50.0)
const CRICKET_REST := Vector2(8.0, 35.0)
const CRICKET_FADE := 4.0

var _beds: Dictionary[StringName, LoopBed] = {}
var _chatter: LoopBed
var _smithy: LoopBed
var _fire: LoopBed
var _shots: Array[AudioStreamPlayer3D] = []
var _next_shot := 0
var _owl_in := 0.0
var _wolf_in := 0.0
var _dog_in := 0.0
var _frog_in := 0.0
## The village found in the current world: its centre and its smithy (Vector3.INF: none).
var _village := Vector3.INF
var _smithy_at := Vector3.INF
var _village_from: Node = null  # a building of the world it was found in (to notice a new world)
## Cricket spots: where, singing or resting, seconds left of that, how loud now (0..1).
var _crickets := PackedVector3Array()
var _singing: Array[bool] = []
var _song_left := PackedFloat32Array()
var _song := PackedFloat32Array()
var _cricket_world := 0
var _voices: Array[LoopBed] = []
var _voice_spot := PackedInt32Array()  # which spot each voice sings for (-1: none)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for id in Biome.MOODS:
		var mood: BiomeMood = Biome.MOODS[id]
		if mood.ambience and not _beds.has(_key(mood.ambience)):
			_beds[_key(mood.ambience)] = _bed(mood.ambience, false)
	for id in [&"evening", &"night"]:
		_beds[id] = _bed(load(DIR + id + ".mp3"), false)
	_chatter = _bed(load(DIR + "chatter.mp3"), true, 14.0, VILLAGE_EARSHOT)
	_smithy = _bed(load(DIR + "smithy.mp3"), true, 6.0, 70.0)
	_fire = _bed(load(DIR + "fire.mp3"), true, 2.5, 18.0)
	for i in CRICKET_VOICES:
		var v := _bed(load(DIR + "night.mp3"), true, CRICKET_UNIT, CRICKET_REACH)
		v.top_level = true
		_voices.append(v)
		_voice_spot.append(-1)
	for i in 4:
		var p := AudioStreamPlayer3D.new()
		p.bus = &"Ambience"
		p.max_db = 0.0
		add_child(p)
		_shots.append(p)
	_owl_in = randf_range(OWL_GAP.x, OWL_GAP.y)
	_wolf_in = randf_range(WOLF_GAP.x, WOLF_GAP.y)
	_dog_in = randf_range(DOG_GAP.x, DOG_GAP.y)


## A bed for one recording (by file name, which keys TRIM), as WaterBody asks for its lapping or
## stream: positional, at `unit` m full volume, gone by `reach` m.
func water_bed(id: StringName, unit: float, reach: float) -> LoopBed:
	var b := LoopBed.new()
	b.stream = load(DIR + id + ".mp3")
	b.trim_db = TRIM.get(id, 0.0) + MIX.get(id, -12.0)
	b.positional = true
	b.unit_size = unit
	b.max_distance = reach
	b.level = 1.0
	return b


## How far through day, evening and night it is: {day, evening, night}, summing to 1. Dawn's
## in-between goes to the day bed (birds), dusk's to the evening bed (birds settling, crickets).
static func dayparts() -> Dictionary:
	var h := DayNight.sun_height()
	var day := smoothstep(-0.05, 0.18, h)
	var night := 1.0 - smoothstep(-0.3, -0.06, h)
	var between := clampf(1.0 - day - night, 0.0, 1.0)
	if DayNight.time < 0.5:
		return {"day": day + between, "evening": 0.0, "night": night}
	return {"day": day, "evening": between, "night": night}


func _process(delta: float) -> void:
	var player := get_tree().get_first_node_in_group("player") as Node3D
	var k := 1.0 - exp(-delta * 3.0 / BLEND)
	var duck := Biome.ambience_duck if player else 0.0  # silent in the menus
	var parts := dayparts()
	# beds
	var mood: BiomeMood = Biome.MOODS.get(Biome.current, Biome.MOODS[&"clearing"])
	var here := _key(mood.ambience) if mood.ambience else &""
	var weather := mood.ambience_always
	var targets := {}
	for id in _beds:
		targets[id] = 0.0
	if here != &"":
		targets[here] = 1.0 if weather else parts["day"]
		if Biome.current == &"":
			targets[here] *= 0.6  # the open hills: a thinner meadow
	targets[&"evening"] = parts["evening"] * (0.5 if weather else 1.0)
	targets[&"night"] = parts["night"] * NIGHT_WASH * (0.5 if weather else 1.0)
	for id in _beds:
		_beds[id].level = lerpf(_beds[id].level, targets[id] * duck, k)
	if player == null:
		_chatter.level = 0.0; _smithy.level = 0.0; _fire.level = 0.0
		for v in _voices:
			v.level = 0.0
		return
	_crickets_sing(delta, player.global_position, (parts["night"] + parts["evening"] * 0.6) * duck)
	# the village
	_find_village()
	var day: float = parts["day"] + parts["evening"] * 0.5
	var has_village := _village != Vector3.INF
	_chatter.level = lerpf(_chatter.level, (day if has_village else 0.0) * duck, k)
	_smithy.level = lerpf(_smithy.level, (day if _smithy_at != Vector3.INF else 0.0) * duck, k)
	_fire.level = lerpf(_fire.level, (1.0 if _smithy_at != Vector3.INF else 0.0) * duck, k)
	# one-shots
	var at := player.global_position
	var near_village := has_village and Vector2(at.x - _village.x, at.z - _village.z).length() < VILLAGE_EARSHOT
	_owl_in -= delta
	if _owl_in <= 0.0:
		_owl_in = randf_range(OWL_GAP.x, OWL_GAP.y)
		if parts["night"] > 0.7 and duck > 0.5:
			_shot(&"owl", at + _around(25.0, 45.0, 6.0), 10.0, 80.0)
	_wolf_in -= delta
	if _wolf_in <= 0.0:
		_wolf_in = randf_range(WOLF_GAP.x, WOLF_GAP.y)
		var far_from_village := not has_village or Vector2(at.x - _village.x, at.z - _village.z).length() > WOLF_CLEAR
		if parts["night"] > 0.8 and far_from_village and duck > 0.5:
			_shot(&"wolf", at + _around(WOLF_DISTANCE, WOLF_DISTANCE + 20.0, 10.0), 30.0, 220.0)
	_dog_in -= delta
	if _dog_in <= 0.0:
		_dog_in = randf_range(DOG_GAP.x, DOG_GAP.y)
		if near_village and parts["day"] > 0.5 and duck > 0.5:
			_shot(&"dog", _village + _around(8.0, 25.0, 1.0), 12.0, VILLAGE_EARSHOT)
	_frog_in -= delta
	if _frog_in <= 0.0:
		_frog_in = randf_range(FROG_GAP.x, FROG_GAP.y)
		if parts["night"] + parts["evening"] > 0.5 and duck > 0.5:
			var spot := _frog_spot(at)
			if spot != Vector3.INF:
				_shot(&"frogs", spot, 4.0, 40.0)


## The cricket spots start and stop singing on their own; the nearest few that sing get a voice.
## A voice keeps its spot while that one is still among the nearest, fades out before it moves
## to another, so nothing jumps.
func _crickets_sing(delta: float, at: Vector3, night: float) -> void:
	var scene := get_tree().current_scene
	if scene and scene.get_instance_id() != _cricket_world:
		_cricket_world = scene.get_instance_id()
		_crickets = NatureSpots.find(get_tree(), CRICKET_SPACING, CRICKET_SPOTS, 0.3, 2)
		_singing.clear(); _song_left.clear(); _song.clear()
		for i in _crickets.size():
			_singing.append(randf() < 0.5)
			_song_left.append(randf_range(0.0, CRICKET_SONG.y))
			_song.append(0.0)
		for k in _voices.size():
			_voice_spot[k] = -1
			_voices[k].level = 0.0
	var near: Array[int] = []
	var dist: Array[float] = []
	for i in _crickets.size():
		_song_left[i] -= delta
		if _song_left[i] <= 0.0:
			_singing[i] = not _singing[i]
			var span := CRICKET_SONG if _singing[i] else CRICKET_REST
			_song_left[i] = randf_range(span.x, span.y)
		_song[i] = move_toward(_song[i], 1.0 if _singing[i] else 0.0, delta / CRICKET_FADE)
		var d := _crickets[i].distance_to(at)
		if _song[i] > 0.01 and d < CRICKET_REACH:
			var j := 0
			while j < dist.size() and dist[j] < d:
				j += 1
			near.insert(j, i)
			dist.insert(j, d)
	near = near.slice(0, CRICKET_VOICES)
	var k := 1.0 - exp(-delta * 2.0)
	for v in _voices.size():
		var spot := _voice_spot[v]
		if spot >= 0 and not near.has(spot):
			_voices[v].level = lerpf(_voices[v].level, 0.0, k)
			if _voices[v].level < 0.01:
				_voice_spot[v] = -1  # free for another spot
		elif spot >= 0:
			_voices[v].level = lerpf(_voices[v].level, _song[spot] * night, k)
	for i in near:
		if _voice_spot.has(i):
			continue
		for v in _voices.size():
			if _voice_spot[v] == -1:
				_voice_spot[v] = i
				_voices[v].level = 0.0
				_voices[v].global_position = _crickets[i] + Vector3.UP * 0.3
				break


## How many cricket spots are singing near `at` right now, and which voices play (tests).
func crickets_near(at: Vector3) -> int:
	var n := 0
	for i in _crickets.size():
		if _song[i] > 0.01 and _crickets[i].distance_to(at) < CRICKET_REACH:
			n += 1
	return n


## A one-shot at `pos`, round-robin over a few positional players.
func _shot(id: StringName, pos: Vector3, unit: float, reach: float) -> void:
	var p := _shots[_next_shot]
	_next_shot = (_next_shot + 1) % _shots.size()
	p.stream = load(DIR + id + ".mp3")
	p.volume_db = TRIM.get(id, 0.0) + MIX.get(id, -16.0)
	p.unit_size = unit
	p.max_distance = reach
	p.pitch_scale = randf_range(0.95, 1.05)
	p.global_position = pos
	p.play()


## A point on the shore of a pond or lake within earshot, or Vector3.INF.
func _frog_spot(at: Vector3) -> Vector3:
	var choices: Array[Vector3] = []
	for w in get_tree().get_nodes_in_group("water"):
		var water := w as WaterBody
		if water.flow != Vector3.ZERO:
			continue  # frogs keep to still water
		var c := water.global_position
		if Vector2(c.x - at.x, c.z - at.z).length() < 70.0:
			var box := water.get_node("Volume") as CollisionShape3D
			var half := (box.shape as BoxShape3D).size * 0.5
			var a := randf() * TAU
			var edge := Vector3(cos(a) * half.x, 0.0, sin(a) * half.z) * 0.8
			choices.append(box.global_transform * Vector3(edge.x, 1.0, edge.z))
	return choices.pick_random() if not choices.is_empty() else Vector3.INF


## Finds the village (the centre of its buildings) and the smithy in the current world, once
## per world.
func _find_village() -> void:
	if is_instance_valid(_village_from):
		return
	var buildings := get_tree().get_nodes_in_group("building")
	_village = Vector3.INF
	_smithy_at = Vector3.INF
	_village_from = null
	if buildings.is_empty():
		return
	var sum := Vector3.ZERO
	for b in buildings:
		var n := b as Node3D
		sum += n.global_position
		var def: Variant = n.get("def")
		if def and def.get("id") == &"smithy":
			_smithy_at = n.global_position
	_village = sum / buildings.size()
	_village_from = buildings[0]
	_chatter.global_position = _village + Vector3.UP * 2.0
	if _smithy_at != Vector3.INF:
		_smithy.global_position = _smithy_at + Vector3.UP * 1.5
		_fire.global_position = _smithy_at + Vector3.UP * 1.0


func _bed(stream: AudioStream, positional: bool, unit := 10.0, reach := 60.0) -> LoopBed:
	var b := LoopBed.new()
	b.stream = stream
	var id := _key(stream)
	b.trim_db = TRIM.get(id, 0.0) + MIX.get(id, MIX[&"bed"])
	b.positional = positional
	b.unit_size = unit
	b.max_distance = reach
	add_child(b)
	return b


static func _key(stream: AudioStream) -> StringName:
	return StringName(stream.resource_path.get_file().get_basename())


## A random offset round the listener: `near` to `far` m away, up to `up` m higher.
static func _around(near: float, far: float, up: float) -> Vector3:
	var a := randf() * TAU
	var r := randf_range(near, far)
	return Vector3(cos(a) * r, randf() * up, sin(a) * r)
