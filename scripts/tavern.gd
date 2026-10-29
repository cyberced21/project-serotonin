class_name Tavern
extends Building
## The tavern on the square (plans/tavern.md): a Building (tier 1 is the boarded-up ruin) you can
## walk into once it's restored. Open from dark until about one in the morning; the villagers'
## day (VillagerDay) brings them here then, the keeper behind the bar.
## The model's markers (Building.marks) are its places, shown with their tier:
##   Seat*        stools round the tables and at the bar ("seat" group, kind &"tavern")
##   Stand*       a place to stand at the bar ("stand_spot" group, kind &"tavern")
##   DiceSeat1/2  the dice table: you, and whoever plays you ("dice_seat" group; DiceGame)
##   Tally        where the chalkboard's writing goes (DiceGame)
##   Stage        where the musician plays ("stage" group)
##   Dance*       where the dancers go ("dance_spot" group)
## Its lanterns and fire are lit while it's open (not just because it's dark), and so are its
## windows. Inside, the world's reverb is a small warm room (Acoustics, the "interior" group).
## The band (tier 3 up): while the musician's on the stage, tavern tunes (the music library's
## "tavern" slot) play from there, heard through the walls and muffled further off, with a pause
## between tunes; the background music holds off near it (Music.band). At the top tier, during a
## tune, a couple of villagers at a time get up and dance.

## Open hours, on VillagerDay's evening clock (25.0 = one in the morning).
const OPEN_FROM := 20.0
const CLOSE := 25.0
## Seconds for the lamps to come up or go out.
const LAMP_FADE := 2.0
## The band: how far it carries (m), the background music held off out to BAND_NEAR and fading
## back by BAND_FAR, the quiet between tunes (s), and its fades.
const BAND_DB := -6.0
const BAND_NEAR := 14.0
const BAND_FAR := 34.0
const BETWEEN_TUNES := Vector2(8.0, 18.0)
const BAND_FADE := 2.5
## Dancing (top tier): every so often during a tune, this many get up for this long.
const DANCERS := 2
const DANCE_EVERY := Vector2(15.0, 35.0)
const DANCE_TIME := 25.0
## The room, in the tavern's own frame (x across, z front to back, +Z the front), for "are you
## inside": the main hall, and the annex at the top tier.
const HALL := AABB(Vector3(-4.0, -0.5, -3.5), Vector3(8.0, 4.0, 7.0))
const ANNEX := AABB(Vector3(-7.0, -0.5, -3.5), Vector3(3.0, 4.0, 6.0))

var dice: DiceGame
var band: AudioStreamPlayer3D
var _band_level := 0.0
var _between := 0.0
var _dance_in := 0.0
var _dancers: Dictionary = {}  # villager -> seconds left
var _lamps: Array[GeometryInstance3D] = []
var _lights: Array[Light3D] = []
var _lamp_level := 0.0
var _lamp_shown := -1.0


func _ready() -> void:
	super()
	add_to_group("tavern")
	add_to_group("interior")
	for t in _tiers:
		for m in marks(t):
			_sort_mark(m)
		for g in _tiers[t].find_children("*", "GeometryInstance3D", true, false):
			if g.is_in_group("night_glow"):  # lit by opening hours, not by the dark (_process)
				g.remove_from_group("night_glow")
				_lamps.append(g)
		for l in _tiers[t].find_children("*", "Light3D", true, false):
			if l.is_in_group("night_light"):
				l.remove_from_group("night_light")
				_lights.append(l)
				(l as Light3D).visible = false
	dice = DiceGame.new()
	dice.name = "Dice"
	add_child(dice)
	_place_dice()
	upgraded.connect(func(_t: int) -> void:
		_place_dice()
		_place_band()
		_reseat())
	band = AudioStreamPlayer3D.new()
	band.name = "Band"
	band.bus = &"Music"
	band.unit_size = 5.0
	band.max_distance = 60.0
	band.attenuation_filter_cutoff_hz = 2500.0  # (muffled further off: through the walls)
	band.attenuation_filter_db = -18.0
	band.volume_db = -80.0
	add_child(band)
	band.finished.connect(func() -> void: _between = randf_range(BETWEEN_TUNES.x, BETWEEN_TUNES.y))
	_place_band()


func _process(delta: float) -> void:
	super(delta)
	_lamp_level = move_toward(_lamp_level, 1.0 if is_open() else 0.0, delta / LAMP_FADE)
	var level := _lamp_level * maxf(DayNightSky.glow_level, 0.35)
	if absf(level - _lamp_shown) > 0.005:
		_lamp_shown = level
		for g in _lamps:
			g.set_instance_shader_parameter("glow", level)
		for l in _lights:
			l.visible = level > 0.01
	_band(delta)
	_dance(delta)
	if level > 0.01:  # firelight flickers, each lamp out of step
		var t := Time.get_ticks_msec() / 1000.0
		for l in _lights:
			var ph := float(l.get_instance_id() % 997)
			var flicker := 1.0 + 0.1 * sin(t * 8.3 + ph) + 0.06 * sin(t * 21.7 + ph * 1.7)
			l.light_energy = level * float(l.get_meta("night_energy", 1.0)) * flicker


## The dice game goes on the dice table of the tier on show (none in the ruin).
func _place_dice() -> void:
	var at: Dictionary = {}
	for m in marks(tier_shown):
		at[String(m.name)] = m
	var on: bool = at.has("DiceSeat1") and at.has("DiceSeat2")
	dice.visible = on
	dice.process_mode = Node.PROCESS_MODE_INHERIT if on else Node.PROCESS_MODE_DISABLED
	if on:
		dice.place(at["DiceSeat1"], at["DiceSeat2"], at.get("Tally"))


## The band plays from the stage of the tier on show.
func _place_band() -> void:
	for m in marks(tier_shown):
		if m.name == "Stage":
			band.global_position = m.global_position + Vector3.UP * 1.2
			return


## After an upgrade: anyone on a seat (or the stage) of the tier that's gone finds a new one.
func _reseat() -> void:
	for b in get_tree().get_nodes_in_group("building"):
		var v := b.get_node_or_null("Villager") as Villager
		if v:
			v.reseat()


## Whoever's on the stage, playing (or null).
func musician() -> Villager:
	for m in marks(tier_shown):
		if m.name == "Stage" and m.has_meta(&"taken_by"):
			var v := m.get_meta(&"taken_by") as Villager
			if is_instance_valid(v) and v.playing_music():
				return v
	return null


## Tunes while the musician plays: one, a pause, another; fading in and out.
func _band(delta: float) -> void:
	var on := is_open() and musician() != null
	if on and not band.playing:
		_between -= delta
		if _between <= 0.0:
			var tunes := _tunes()
			if not tunes.is_empty():
				band.stream = tunes.pick_random()
				band.play()
	_band_level = move_toward(_band_level, 1.0 if on else 0.0, delta / BAND_FADE)
	if band.playing and _band_level <= 0.0:
		band.stop()
		_between = 0.0
	var trim: float = Music.LIBRARY.trim_db.get(band.stream.resource_path, 0.0) if band.stream else 0.0
	band.volume_db = BAND_DB + trim + linear_to_db(maxf(_band_level, 0.0001))
	var player := get_tree().get_first_node_in_group("player") as Node3D
	var near := 0.0
	if player and band.playing:
		near = 1.0 - smoothstep(BAND_NEAR, BAND_FAR, player.global_position.distance_to(band.global_position))
	Music.band = near * _band_level


## The tunes it plays: the music library's "tavern" slot.
func _tunes() -> Array[AudioStream]:
	return Music.LIBRARY.pieces(&"tavern")


## At the top tier, during a tune: a couple get up and dance, then sit back down.
func _dance(delta: float) -> void:
	for v in _dancers.keys():
		_dancers[v] -= delta
		if not is_instance_valid(v) or _dancers[v] <= 0.0 or not band.playing:
			if is_instance_valid(v):
				v.stop_dancing()
			_dancers.erase(v)
	if tier_shown < 4 or not band.playing or not _dancers.is_empty():
		return
	_dance_in -= delta
	if _dance_in > 0.0:
		return
	_dance_in = randf_range(DANCE_EVERY.x, DANCE_EVERY.y)
	var free: Array[Villager] = []
	for b in get_tree().get_nodes_in_group("building"):
		var v := b.get_node_or_null("Villager") as Villager
		if v and v.free_for_dice():  # (sat at a table, nothing else on)
			free.append(v)
	free.shuffle()
	var spots: Array[Marker3D] = []
	for m in marks(tier_shown):
		if m.is_in_group("dance_spot") and not m.has_meta(&"taken_by"):
			spots.append(m)
	for i in mini(DANCERS, mini(free.size(), spots.size())):
		free[i].dance(spots[i])
		_dancers[free[i]] = DANCE_TIME


## Open for the evening: restored (past the ruin) and within opening hours.
func is_open() -> bool:
	if tier_shown < 2:
		return false
	var h := VillagerDay.evening_hours(DayNight.time)
	return h >= OPEN_FROM and h < CLOSE


## The player is in the room (for the reverb, Acoustics).
func has_player() -> bool:
	if tier_shown < 2:
		return false
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player == null:
		return false
	var p := global_transform.affine_inverse() * player.global_position
	return HALL.has_point(p) or (tier_shown >= 4 and ANNEX.has_point(p))


## The windows glow while it's open.
func _windows_on() -> bool:
	return is_open()


func _sort_mark(m: Marker3D) -> void:
	var n := String(m.name)
	if n.begins_with("DiceSeat"):
		m.add_to_group("dice_seat")
	elif n.begins_with("Seat"):
		m.add_to_group("seat")
		m.set_meta(&"kind", &"tavern")
	elif n.begins_with("Stand"):
		m.add_to_group("stand_spot")
		m.set_meta(&"kind", &"tavern")
	elif n == "Stage":
		m.add_to_group("stage")
	elif n.begins_with("Dance"):
		m.add_to_group("dance_spot")
