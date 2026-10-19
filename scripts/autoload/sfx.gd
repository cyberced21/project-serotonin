extends Node
## Sound players everything can share. Non-positional sounds (UI, pickups — with a rising-pitch
## "combo" when pickups happen in quick succession, a classic satisfying trick, and the player's
## own tool sounds) and a pool of positional ones for layered world sounds (SoundLayers), so a
## node doesn't need a player per layer.

const VOICES := 12
const VOICES_3D := 32  # the gathering sounds ring and boom on for a second or two
const COMBO_WINDOW_MS := 450
const COMBO_STEP := 0.06
const COMBO_MAX := 0.6
## Debris clatter: at most this many in any DEBRIS_WINDOW_MS, so a rock breaking into a dozen
## pieces doesn't turn into a wall of ticks.
const DEBRIS_MAX := 3
const DEBRIS_WINDOW_MS := 120

var pickup_stream: AudioStream = preload("res://audio/pickup.tres")

var _players: Array[AudioStreamPlayer] = []
var _players_3d: Array[AudioStreamPlayer3D] = []
var _next := 0
var _next_3d := 0
var _combo := 0
var _last_pickup_ms := -100000
var _debris_times: Array[int] = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in VOICES:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)
	for i in VOICES_3D:
		var p := AudioStreamPlayer3D.new()
		p.attenuation_filter_cutoff_hz = 8000.0  # far-off hits lose their crack
		p.max_db = 0.0  # no boost up close: the stacks already peak near full scale
		add_child(p)
		_players_3d.append(p)

func play(stream: AudioStream, pitch := 1.0, volume_db := 0.0, bus := &"Master") -> void:
	var p := _players[_next]
	_next = (_next + 1) % VOICES
	p.stream = stream
	p.pitch_scale = pitch
	p.volume_db = volume_db
	p.bus = bus
	p.play()

func play_pickup() -> void:
	var now := Time.get_ticks_msec()
	_combo = _combo + 1 if now - _last_pickup_ms < COMBO_WINDOW_MS else 0
	_last_pickup_ms = now
	play(pickup_stream, 1.0 + minf(_combo * COMBO_STEP, COMBO_MAX), -4.0)

## Every layer of `sound`, non-positional (sounds the player makes with their own hands).
func play_layers(sound: SoundLayers, pitch := 1.0, volume_db := 0.0) -> void:
	if sound == null:
		return
	for layer in sound.layers:
		if layer and layer.stream:
			_after(layer.delay, func() -> void:
				play(layer.stream, _layer_pitch(layer, pitch), layer.volume_db + volume_db, sound.bus))

## Every layer of `sound` at `position` in the world.
func play_at(sound: SoundLayers, position: Vector3, pitch := 1.0, volume_db := 0.0) -> void:
	if sound == null:
		return
	for layer in sound.layers:
		if layer and layer.stream:
			_after(layer.delay, func() -> void:
				var p := _free_3d()
				p.global_position = position
				p.stream = layer.stream
				p.pitch_scale = _layer_pitch(layer, pitch)
				p.volume_db = layer.volume_db + volume_db
				p.unit_size = sound.unit_size
				p.max_distance = sound.max_distance
				p.bus = sound.bus
				p.play())

## A piece of debris landing: like play_at, but quieter the softer it lands (`strength` 0..1)
## and dropped when too many have just played.
func play_debris(sound: SoundLayers, position: Vector3, strength: float) -> void:
	var now := Time.get_ticks_msec()
	while not _debris_times.is_empty() and now - _debris_times[0] > DEBRIS_WINDOW_MS:
		_debris_times.pop_front()
	if _debris_times.size() >= DEBRIS_MAX:
		return
	_debris_times.append(now)
	var s := clampf(strength, 0.0, 1.0)
	play_at(sound, position, lerpf(1.15, 0.9, s), lerpf(-14.0, 0.0, s))

func _layer_pitch(layer: SoundLayer, pitch: float) -> float:
	var p := layer.pitch * (pitch if layer.follows_pitch else 1.0)
	return maxf(p * (1.0 + randf_range(-layer.pitch_jitter, layer.pitch_jitter)), 0.05)

## A player that isn't busy, or else the one that started longest ago.
func _free_3d() -> AudioStreamPlayer3D:
	for i in VOICES_3D:
		var p := _players_3d[(_next_3d + i) % VOICES_3D]
		if not p.playing:
			_next_3d = (_next_3d + i + 1) % VOICES_3D
			return p
	var p := _players_3d[_next_3d]
	_next_3d = (_next_3d + 1) % VOICES_3D
	return p

## Runs `f` now, or `delay` real seconds from now (hit-stop doesn't stretch it).
func _after(delay: float, f: Callable) -> void:
	if delay <= 0.0:
		f.call()
	else:
		get_tree().create_timer(delay, true, false, true).timeout.connect(f)
