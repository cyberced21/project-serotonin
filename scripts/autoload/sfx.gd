extends Node
## Sound players everything can share. Non-positional sounds (UI, pickups — with a rising-pitch
## "combo" when pickups happen in quick succession, a classic satisfying trick, and the player's
## own tool sounds) and a pool of positional ones for layered world sounds (SoundLayers), so a
## node doesn't need a player per layer.
## Interface sounds (wood and paper, CC0 recordings: audio/ui/SOURCES.md) go through play_ui(id):
## every button clicks and every tab bar turns a page by itself (see _on_node_added); panels and
## the map play their own open / close.

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
## Interface sounds by id, and how loud each plays (dB): quiet, under everything else.
const UI := {
	&"click": [preload("res://audio/ui/click.wav"), -12.0],
	&"open": [preload("res://audio/ui/open.wav"), -8.0],
	&"close": [preload("res://audio/ui/close.wav"), -10.0],
	&"page": [preload("res://audio/ui/page.wav"), -9.0],
	&"map": [preload("res://audio/ui/map.wav"), -7.0],
}

var _players: Array[AudioStreamPlayer] = []
var _players_3d: Array[AudioStreamPlayer3D] = []
var _next := 0
var _next_3d := 0
var _combo := 0
var _last_pickup_ms := -100000
var _debris_times: Array[int] = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().node_added.connect(_on_node_added)
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

func play(stream: AudioStream, pitch := 1.0, volume_db := 0.0, bus := &"Effects") -> void:
	var p := _players[_next]
	_next = (_next + 1) % VOICES
	p.stream = stream
	p.pitch_scale = pitch
	p.volume_db = volume_db
	p.bus = bus
	p.play()

## Players left on Master go to Effects, so the Effects volume reaches every sound effect;
## ambience and movement sounds pick their own buses (Ambience, Movement), as does a SoundLayers.
## Also: every button clicks when pressed, and every tab bar turns a page when a tab is clicked
## (not the debug menu's).
func _on_node_added(n: Node) -> void:
	if n is BaseButton or n is TabContainer:
		var debug := get_node_or_null("/root/DebugMenu")
		if debug and debug.is_ancestor_of(n):
			return
		if n is BaseButton:
			(n as BaseButton).pressed.connect(play_ui.bind(&"click"))
		else:
			(n as TabContainer).tab_clicked.connect(func(_t: int) -> void: play_ui(&"page"))
	elif n is AudioStreamPlayer and (n as AudioStreamPlayer).bus == &"Master":
		(n as AudioStreamPlayer).bus = &"Effects"
	elif n is AudioStreamPlayer3D and (n as AudioStreamPlayer3D).bus == &"Master":
		(n as AudioStreamPlayer3D).bus = &"Effects"

## Plays an interface sound by id (&"click", &"open", &"close", &"page", &"map"), with a hair of
## pitch variation so repeats don't sound stamped out.
func play_ui(id: StringName, pitch := 1.0) -> void:
	var entry: Array = UI[id]
	play(entry[0], pitch * randf_range(0.97, 1.03), entry[1])

func play_pickup() -> void:
	var now := Time.get_ticks_msec()
	_combo = _combo + 1 if now - _last_pickup_ms < COMBO_WINDOW_MS else 0
	_last_pickup_ms = now
	play(pickup_stream, 1.0 + minf(_combo * COMBO_STEP, COMBO_MAX), -6.0)

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

## Runs `f` now, or `delay` real seconds from now.
func _after(delay: float, f: Callable) -> void:
	if delay <= 0.0:
		f.call()
	else:
		get_tree().create_timer(delay, true, false, true).timeout.connect(f)
