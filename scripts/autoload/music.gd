extends Node
## Background music, in waves (plans/cozy-sound.md): a piece plays, then a few minutes of just the
## world's ambience, then another. Which piece depends on where you are (the village, the forest,
## the lake, the mine: Biome's areas) and the time of day (morning, day, evening, night), from
## data/music/library.tres. A piece always plays to its end; moving somewhere else only changes the
## next one. The main menu plays its own slot without gaps.
## Plays on the Music bus (its own volume slider in Settings), under ambience and effects.
## Moment cues (level-up, discovery, return to a biome, a building upgrade) go through play_cue(),
## which ducks the music under them; cutscenes duck it with `duck`.

const LIBRARY := preload("res://data/music/library.tres")
## Silence between pieces (seconds), at random; the first piece of a session comes sooner.
const GAP_MIN := 120.0
const GAP_MAX := 300.0
const FIRST_GAP_MIN := 25.0
const FIRST_GAP_MAX := 60.0
## Fades: a piece eases in, and out when it has to stop early (leaving to the menu).
const FADE_IN := 4.0
const FADE_OUT := 2.5
## Cues sit this much above the music (both are trimmed to the same loudness first).
const CUE_LIFT_DB := 6.0
## How far the music dips under a moment cue, and how long it takes to come back.
const CUE_DUCK_DB := -12.0
const CUE_RECOVER := 1.5
## Music sits under ambience and effects (Settings' slider sets the Music bus itself).
const MIX_DB := -8.0
## An area's own pieces get this share of the picks there; the rest follow the time of day.
const AREA_SHARE := 0.6
## Where an empty time-of-day slot borrows from, nearest in mood first.
const FALLBACKS := {&"morning": [&"day", &"evening", &"night"], &"day": [&"morning", &"evening", &"night"],
	&"evening": [&"night", &"day", &"morning"], &"night": [&"evening", &"morning", &"day"]}
const AREAS := {&"hearthvale": &"village", &"pinewood": &"forest", &"stillwater": &"lake", &"quarry": &"mine"}

## 0..1: how loud the music plays (a cutscene lowers it).
var duck := 1.0
## Debug readout: what's happening now.
var status := ""

var _player: AudioStreamPlayer
var _cue_player: AudioStreamPlayer
var _gap := 0.0
var _last: AudioStream
var _level_db := 0.0  # the playing piece's trim
var _plays_left := 0  # more times the playing piece repeats
var _fade := 0.0  # 0..1, the playing piece's fade
var _fading_out := false
var _cue_duck := 0.0  # dB, back to 0 after a cue
var _in_menu := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # keeps playing, softly, in the pause menu
	_player = _make_player()
	_cue_player = _make_player()
	_player.finished.connect(_on_finished)
	_gap = randf_range(FIRST_GAP_MIN, FIRST_GAP_MAX)


func _make_player() -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = &"Music"
	add_child(p)
	return p


func _process(delta: float) -> void:
	var menu := get_tree().get_first_node_in_group("player") == null
	if menu != _in_menu:
		_switch(menu)
	if _fading_out:
		_fade = move_toward(_fade, 0.0, delta / FADE_OUT)
		if _fade <= 0.0:
			_player.stop()
			_fading_out = false
	elif _player.playing:
		_fade = move_toward(_fade, 1.0, delta / FADE_IN)
	_cue_duck = move_toward(_cue_duck, 0.0, -CUE_DUCK_DB / CUE_RECOVER * delta)
	_player.volume_db = MIX_DB + _level_db + linear_to_db(maxf(_fade * duck, 0.0001)) + _cue_duck
	if _player.playing or _fading_out:
		status = "playing %s" % _player.stream.resource_path.get_file()
		return
	if _in_menu:
		status = "menu"
		if not LIBRARY.pieces(&"menu").is_empty():
			play_next()
		return
	_gap -= delta
	status = "quiet, next piece in %d s (%s)" % [maxi(int(_gap), 0), _slot()]
	if _gap <= 0.0:
		play_next()


## Between the main menu and a world: fade out what was playing, and start the right thing.
func _switch(menu: bool) -> void:
	_in_menu = menu
	if _player.playing:
		_fading_out = true
	if not menu:
		_gap = randf_range(FIRST_GAP_MIN, FIRST_GAP_MAX)


## Starts a piece for where you are now (or the menu's), if there is one; else waits another gap.
func play_next() -> void:
	var slot := &"menu" if _in_menu else _slot()
	var choices := LIBRARY.pieces(slot)
	if not _in_menu:  # an empty slot borrows from the time of day, then its neighbours
		for fallback in [_time_slot()] + FALLBACKS.get(_time_slot(), []):
			if not choices.is_empty():
				break
			choices = LIBRARY.pieces(fallback)
	if choices.is_empty():
		_after_piece()
		return
	var pick: AudioStream = choices.pick_random()
	if choices.size() > 1:
		while pick == _last:
			pick = choices.pick_random()
	_last = pick
	_level_db = LIBRARY.trim_db.get(pick.resource_path, 0.0)
	_plays_left = LIBRARY.repeats.get(pick.resource_path, 1) - 1
	_fade = 0.0
	_fading_out = false
	_player.stream = pick
	_player.play()


## Debug: stop the piece now and go quiet for a gap.
func skip() -> void:
	_player.stop()
	_fading_out = false
	_after_piece()


## Plays one of the library's moment cues by id (&"level_up", &"discovery", &"return", &"upgrade").
func play_cue(id: StringName) -> void:
	var stream: AudioStream = LIBRARY.cues.get(id)
	if stream:
		cue(stream, LIBRARY.trim_db.get(stream.resource_path, 0.0) + CUE_LIFT_DB)


## Plays a short cue on the Music bus, dipping the music under it.
func cue(stream: AudioStream, volume_db := 0.0) -> void:
	_cue_player.stream = stream
	_cue_player.volume_db = MIX_DB + volume_db
	_cue_player.play()
	_cue_duck = CUE_DUCK_DB


func _on_finished() -> void:
	if _fading_out:
		return
	if _plays_left > 0:  # a short piece goes round again
		_plays_left -= 1
		_player.play()
	else:
		_after_piece()


func _after_piece() -> void:
	_gap = randf_range(GAP_MIN, GAP_MAX)


## Which slot to pick from here: the area's own sometimes, otherwise the time of day's.
func _slot() -> StringName:
	var area: StringName = AREAS.get(Biome.current, &"")
	if area != &"" and not LIBRARY.pieces(area).is_empty() and randf() < AREA_SHARE:
		return area
	return _time_slot()


func _time_slot() -> StringName:
	var t := DayNight.time
	if t >= DayNight.SUNRISE - 0.03 and t < 0.35:
		return &"morning"
	if t >= 0.35 and t < DayNight.SUNSET - 0.08:
		return &"day"
	if t >= DayNight.SUNSET - 0.08 and t < DayNight.SUNSET + 0.08:
		return &"evening"
	return &"night"
