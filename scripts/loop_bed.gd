class_name LoopBed
extends Node3D
## A recording looped without a seam: two players take turns, the next one starting XFADE seconds
## before the current one ends and fading in (equal power) while it fades out. Starts at a random
## point, so two beds of the same recording never line up. The owner sets `level` (0..1) every
## frame; `trim_db` matches the recording's loudness to the others (Ambience.TRIM).
## Positional beds (a lake's lapping, the smithy) pause while the listener is out of earshot, so a
## river of many stretches doesn't decode them all.

const XFADE := 4.0

var stream: AudioStream
var trim_db := 0.0
var bus := &"Ambience"
## 0..1: how loud it plays now.
var level := 0.0
var positional := false
var unit_size := 10.0
var max_distance := 60.0

var _players: Array[Node] = []
var _current := 0
var _length := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # beds go on under the paused map and menus
	_length = stream.get_length()
	for i in 2:
		var p: Node
		if positional:
			var p3 := AudioStreamPlayer3D.new()
			p3.unit_size = unit_size
			p3.max_distance = max_distance
			p3.max_db = 0.0
			p3.attenuation_filter_cutoff_hz = 9000.0
			p = p3
		else:
			p = AudioStreamPlayer.new()
		p.set("stream", stream)
		p.set("bus", bus)
		p.set("volume_db", -80.0)
		add_child(p)
		_players.append(p)
	_players[0].call("play", randf() * maxf(_length - 2.0 * XFADE, 0.0))


func _process(_delta: float) -> void:
	if positional:
		var cam := get_viewport().get_camera_3d()
		var far := cam != null and cam.global_position.distance_to(global_position) > max_distance + 5.0
		for p in _players:
			p.set("stream_paused", far)
		if far:
			return
	var cur := _players[_current]
	var nxt := _players[1 - _current]
	if not cur.get("playing") and not nxt.get("playing"):
		cur.call("play", 0.0)
	var left := _length - float(cur.call("get_playback_position"))
	if left <= XFADE and not nxt.get("playing"):
		nxt.call("play", 0.0)
	var t := clampf(1.0 - left / XFADE, 0.0, 1.0) if nxt.get("playing") else 0.0
	cur.set("volume_db", _db(cos(t * PI * 0.5)))
	nxt.set("volume_db", _db(sin(t * PI * 0.5)))
	if not cur.get("playing") and nxt.get("playing"):
		_current = 1 - _current


func _db(fade: float) -> float:
	return linear_to_db(maxf(level * fade, 0.0001)) + trim_db
