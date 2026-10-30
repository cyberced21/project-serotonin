class_name SoundSpot
extends AudioStreamPlayer3D
## A place's own sound (plans/world-pass.md, phase 8), from audio/country/: a loop playing while
## its hours are on and you're near (the farmyard by day, the wind up on the shepherd's hill, the
## washhouse in the morning, the mill's wheel once it turns), or a call now and then (birdsong
## by the groves, ducks on the pond), or a bell struck at set hours (the chapel). Hours are the
## clock (DayNight), wrapping past midnight.

@export var sound := ""
@export var looping := true
## One-shots: seconds between them [min, max], and how many seconds of the recording each plays
## (from somewhere in it: the long birdsong takes), or 0 for all of it.
@export var gap := Vector2(20.0, 60.0)
@export var take := 0.0
## Plays between these hours of the clock (from > to wraps past midnight).
@export var from_hour := 0.0
@export var to_hour := 24.0
## Struck once at each of these hours (the chapel bell); overrides looping and gap.
@export var strike_hours := PackedInt32Array()
## Only once this project's done (the mill's wheel), or always.
@export var project: StringName = &""
@export var hear := 60.0

var _wait := 0.0
var _left := 0.0
var _last_strike := -1


func _ready() -> void:
	if bus == &"Master":
		bus = &"Ambience"
	var s := load("res://audio/country/%s.mp3" % sound) as AudioStreamMP3
	if looping and strike_hours.is_empty():
		s = s.duplicate() as AudioStreamMP3
		s.loop = true
	stream = s
	if max_distance == 0.0:
		max_distance = hear
	_wait = randf_range(0.0, gap.y)


func _process(delta: float) -> void:
	var player := get_tree().get_first_node_in_group("player") as Node3D
	var near := player != null and player.global_position.distance_to(global_position) < hear
	var hour := DayNight.time * 24.0
	var on := near and _in_hours(hour) and (project == &"" or Projects.is_done(project))
	if not strike_hours.is_empty():
		var h := int(hour)
		if h in strike_hours and h != _last_strike and hour - h < 0.1:
			_last_strike = h
			if near:
				play()
		return
	if looping:
		if on and not playing:
			play(randf() * maxf(stream.get_length() - 1.0, 0.0))
		elif not on and playing:
			stop()
		return
	if playing and take > 0.0:
		_left -= delta
		if _left <= 0.0:
			stop()
	if not on:
		return
	_wait -= delta
	if _wait <= 0.0 and not playing:
		_wait = randf_range(gap.x, gap.y)
		pitch_scale = randf_range(0.95, 1.05)
		var length := stream.get_length()
		play(randf_range(0.0, maxf(length - take, 0.0)) if take > 0.0 else 0.0)
		_left = take


func _in_hours(h: float) -> bool:
	return h >= from_hour and h < to_hour if from_hour <= to_hour else (h >= from_hour or h < to_hour)
