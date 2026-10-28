extends Node
## The time of day. `time` runs 0 -> 1 over DAY_LENGTH seconds of play: 0 is midnight, the sun
## rises at SUNRISE and sets at SUNSET (14 minutes of day, 6 of night). Other systems ask:
##   is_night()     villagers go home
##   twilight()     1 around sunrise / sunset (fish are calmer)
##   sun_height()   -1..1, how high the sun is (negative: below the horizon, the moon is up)
## The lighting itself is done by the Sky node in main.tscn (day_night_sky.gd). Saved.

signal night_fell
signal day_broke

const DAY_LENGTH := 1200.0
const SUNRISE := 0.15
const SUNSET := 0.85
## Fraction of a day either side of sunrise / sunset that counts as twilight.
const TWILIGHT := 0.05
const START_TIME := 0.3  # a new game starts mid-morning
## Debug (F6): how far to skip.
const DEBUG_SKIP := 0.125

var time := START_TIME
## Debug: holds the time of day still (the Sky tab, while tuning the look).
var frozen := false
var _was_night := false


func _ready() -> void:
	SaveGame.register(&"day_night", self)
	_was_night = is_night()


func _process(delta: float) -> void:
	if frozen:
		return
	time = fmod(time + delta / DAY_LENGTH, 1.0)
	var night := is_night()
	if night != _was_night:
		_was_night = night
		if night:
			night_fell.emit()
		else:
			day_broke.emit()


## True from a little after sunset until a little before sunrise.
func is_night() -> bool:
	return time > SUNSET + TWILIGHT * 0.3 or time < SUNRISE - TWILIGHT * 0.3


## 0..1 through the day (sunrise -> sunset), or -1 at night.
func day_progress() -> float:
	if time < SUNRISE or time > SUNSET:
		return -1.0
	return (time - SUNRISE) / (SUNSET - SUNRISE)


## 0..1 through the night (sunset -> sunrise), or -1 by day.
func night_progress() -> float:
	if time >= SUNRISE and time <= SUNSET:
		return -1.0
	return fmod(time - SUNSET + 1.0, 1.0) / (1.0 - (SUNSET - SUNRISE))


## How high the sun is: 1 at noon, 0 on the horizon, negative below it (-1 at midnight).
func sun_height() -> float:
	var d := day_progress()
	return sin(PI * d) if d >= 0.0 else -sin(PI * night_progress())


## 1 right at sunrise / sunset, fading to 0 TWILIGHT either side.
func twilight() -> float:
	var d := minf(absf(time - SUNRISE), absf(time - SUNSET))
	return 1.0 - smoothstep(0.0, TWILIGHT, d)


## Like twilight(), for the sky's colours: wider, and lopsided. `day_side` and `night_side` are how
## far it reaches into the day and into the night (fractions of a day). 1 at sunrise / sunset.
func sky_twilight(day_side: float, night_side: float) -> float:
	var rise := wrapf(time - SUNRISE, -0.5, 0.5)  # > 0: after sunrise, the day side
	var fall := wrapf(time - SUNSET, -0.5, 0.5)   # > 0: after sunset, the night side
	var a := 1.0 - smoothstep(0.0, day_side if rise > 0.0 else night_side, absf(rise))
	var b := 1.0 - smoothstep(0.0, night_side if fall > 0.0 else day_side, absf(fall))
	return maxf(a, b)


## True from midnight to noon: the sunrise half of the day.
func is_morning() -> bool:
	return time < 0.5


## A wall clock where the sun rises at 06:00 and sets at 20:00.
func clock_text() -> String:
	var hours: float
	var d := day_progress()
	if d >= 0.0:
		hours = 6.0 + d * 14.0
	else:
		hours = fmod(20.0 + night_progress() * 10.0, 24.0)
	var m := int(hours * 60.0)
	return "%02d:%02d" % [m / 60, m % 60]


## Dawn, Day, Dusk or Night.
func part_of_day() -> String:
	if twilight() > 0.3:
		return "Dawn" if absf(time - SUNRISE) < absf(time - SUNSET) else "Dusk"
	return "Night" if is_night() else "Day"


func to_dict() -> Dictionary:
	return {"time": time}


func from_dict(d: Dictionary) -> void:
	time = fposmod(float(d.get("time", START_TIME)), 1.0)
	_was_night = is_night()


func _unhandled_input(event: InputEvent) -> void:
	if (OS.is_debug_build() or OS.has_feature("playtest")) and event.is_action_pressed("debug_skip_time"):
		time = fmod(time + DEBUG_SKIP, 1.0)
