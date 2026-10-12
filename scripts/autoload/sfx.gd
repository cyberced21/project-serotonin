extends Node
## Non-positional sound player (UI / pickups) with a rising-pitch "combo"
## when pickups happen in quick succession — a classic satisfying trick.

const VOICES := 8
const COMBO_WINDOW_MS := 450
const COMBO_STEP := 0.06
const COMBO_MAX := 0.6

var pickup_stream: AudioStream = preload("res://audio/pickup.tres")

var _players: Array[AudioStreamPlayer] = []
var _next := 0
var _combo := 0
var _last_pickup_ms := -100000

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in VOICES:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)

func play(stream: AudioStream, pitch := 1.0, volume_db := 0.0) -> void:
	var p := _players[_next]
	_next = (_next + 1) % VOICES
	p.stream = stream
	p.pitch_scale = pitch
	p.volume_db = volume_db
	p.play()

func play_pickup() -> void:
	var now := Time.get_ticks_msec()
	_combo = _combo + 1 if now - _last_pickup_ms < COMBO_WINDOW_MS else 0
	_last_pickup_ms = now
	play(pickup_stream, 1.0 + minf(_combo * COMBO_STEP, COMBO_MAX), -4.0)
