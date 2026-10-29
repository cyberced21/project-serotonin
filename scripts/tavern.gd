class_name Tavern
extends Building
## The tavern on the square (plans/tavern.md): a Building (tier 1 is the boarded-up ruin) you can
## walk into once it's restored. Open from dark until about one in the morning; the villagers'
## day (VillagerDay) brings them here then, the keeper behind the bar.
## The model's markers (Building.marks) are its places, shown with their tier:
##   Seat*        stools round the tables and at the bar ("seat" group, kind &"tavern")
##   Stand*       a place to stand at the bar ("stand_spot" group, kind &"tavern")
##   DiceSeat1/2  the dice table: you, and whoever plays you ("dice_seat" group)
##   Stage        where the musician plays ("stage" group)
##   Dance*       where the dancers go ("dance_spot" group)
## Its lanterns and fire are lit while it's open (not just because it's dark), and so are its
## windows. Inside, the world's reverb is a small warm room (Acoustics, the "interior" group).

## Open hours, on VillagerDay's evening clock (25.0 = one in the morning).
const OPEN_FROM := 20.0
const CLOSE := 25.0
## Seconds for the lamps to come up or go out.
const LAMP_FADE := 2.0
## The room, in the tavern's own frame (x across, z front to back, +Z the front), for "are you
## inside": the main hall, and the annex at the top tier.
const HALL := AABB(Vector3(-4.0, -0.5, -3.5), Vector3(8.0, 4.0, 7.0))
const ANNEX := AABB(Vector3(-7.0, -0.5, -3.5), Vector3(3.0, 4.0, 6.0))

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
	if level > 0.01:  # firelight flickers, each lamp out of step
		var t := Time.get_ticks_msec() / 1000.0
		for l in _lights:
			var ph := float(l.get_instance_id() % 997)
			var flicker := 1.0 + 0.1 * sin(t * 8.3 + ph) + 0.06 * sin(t * 21.7 + ph * 1.7)
			l.light_energy = level * float(l.get_meta("night_energy", 1.0)) * flicker


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
