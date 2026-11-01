class_name SwimSounds
extends Node
## The swimmer's sounds (plans/water.md; recordings in audio/swim/, see SOURCES.md): strokes while
## you paddle, a plunge as your head goes under, the hush of the water while it's under, a gasp as
## you come up from a long dive, and the splash and drips of climbing out. A child of the player;
## it watches the player's `swimming` and `head_under`.

const STROKES := preload("res://audio/swim/strokes.mp3")
const UNDERWATER := preload("res://audio/swim/underwater.mp3")
const DIVE := preload("res://audio/swim/dive.wav")
const GASP := preload("res://audio/swim/gasp.wav")
const CLIMB_OUT := preload("res://audio/swim/climb_out.wav")
## Levels (dB): the strokes at full speed, the underwater bed, the one-shots.
const STROKES_DB := -9.0
const UNDERWATER_DB := -12.0
const DIVE_DB := -6.0
const GASP_DB := -8.0
const CLIMB_OUT_DB := -7.0
## A gasp only after this long under (s); a short duck just comes up.
const GASP_AFTER := 4.0
const SILENT := -60.0

var player: CharacterBody3D  # (player.gd has no class_name: its fields by get())
var _strokes: AudioStreamPlayer
var _under: AudioStreamPlayer
var _shot: AudioStreamPlayer
var _was_swimming := false
var _was_under := false
var _under_for := 0.0


func _ready() -> void:
	_strokes = _loop(STROKES, &"Movement")
	_under = _loop(UNDERWATER, &"Master")  # (already the sound under water: not muffled again)
	_shot = AudioStreamPlayer.new()
	_shot.bus = &"Movement"
	add_child(_shot)


func _loop(stream: AudioStreamMP3, bus: StringName) -> AudioStreamPlayer:
	var s := stream.duplicate() as AudioStreamMP3
	s.loop = true
	var p := AudioStreamPlayer.new()
	p.stream = s
	p.bus = bus
	p.volume_db = SILENT
	add_child(p)
	return p


func _process(delta: float) -> void:
	if player == null:
		return
	var swimming: bool = player.get("swimming")
	var under: bool = player.get("head_under")
	# strokes: as loud as you're moving (still, you just tread water quietly)
	var speed := Vector2(player.velocity.x, player.velocity.z).length() if swimming else 0.0
	var want := lerpf(SILENT, STROKES_DB, clampf(speed / 2.2, 0.0, 1.0) ** 0.5) if speed > 0.15 else SILENT
	_fade(_strokes, want - (8.0 if under else 0.0), delta)
	# the water's hush while your head's under (on Master: follow the Ambience slider by hand)
	var ambience := AudioServer.get_bus_volume_db(AudioServer.get_bus_index(&"Ambience"))
	_fade(_under, UNDERWATER_DB + ambience if under else SILENT, delta * (3.0 if under else 1.5))
	if under and not _was_under:
		_play(DIVE, DIVE_DB, randf_range(0.95, 1.05))
	elif _was_under and not under and _under_for >= GASP_AFTER:
		_play(GASP, GASP_DB + (3.0 if player.get("winded") else 0.0), randf_range(0.95, 1.05))
	elif _was_swimming and not swimming and not under:
		_play(CLIMB_OUT, CLIMB_OUT_DB, randf_range(0.95, 1.05))
	_under_for = _under_for + delta if under else 0.0
	_was_under = under
	_was_swimming = swimming


func _fade(p: AudioStreamPlayer, db: float, delta: float) -> void:
	p.volume_db = move_toward(p.volume_db, db, delta * 40.0)
	if p.volume_db > SILENT + 1.0 and not p.playing:
		p.play(randf() * maxf(p.stream.get_length() - 1.0, 0.0))
	elif p.volume_db <= SILENT + 1.0 and p.playing:
		p.stop()


func _play(stream: AudioStream, db: float, pitch: float) -> void:
	_shot.stream = stream
	_shot.volume_db = db
	_shot.pitch_scale = pitch
	_shot.play()
