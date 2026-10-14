extends Node
## Gathering skills: skill id -> total XP. Levels are derived from XP via one shared curve.
## To add a skill: add a row to SKILLS, then set `skill` on the resource node scene.

signal xp_gained(skill: StringName, amount: int, total: int)
signal leveled_up(skill: StringName, level: int)

const MAX_LEVEL := 50
## Total XP needed for level L = CURVE_BASE * (L - 1) ^ CURVE_EXPONENT
const CURVE_BASE := 50.0
const CURVE_EXPONENT := 2.2
const DEBUG_XP := 500

const SKILLS := {
	&"woodcutting": {"name": "Woodcutting", "color": Color("9be27a")},
	&"mining": {"name": "Mining", "color": Color("a9c1e8")},
	&"fishing": {"name": "Fishing", "color": Color("6fd0d8")},
}

var xp: Dictionary[StringName, int] = {}
var last_trained: StringName = &"woodcutting"


func _ready() -> void:
	SaveGame.register(&"skills", self)


## Adds XP (clamped at the max level), plus the town hall's bonus. Returns how much was actually gained.
func add_xp(skill: StringName, amount: int) -> int:
	if not SKILLS.has(skill):
		push_warning("Skills: unknown skill '%s'" % skill)
		return 0
	amount = roundi(amount * (1.0 + Village.stat(&"xp_bonus")))
	var old: int = xp.get(skill, 0)
	var total := mini(old + amount, xp_for_level(MAX_LEVEL))
	if total == old:
		return 0
	var before := level(skill)
	xp[skill] = total
	last_trained = skill
	SaveGame.mark_dirty()
	xp_gained.emit(skill, total - old, total)
	var after := level(skill)
	if after > before:
		leveled_up.emit(skill, after)
		SaveGame.save()
	return total - old


## Debug: jump straight to the start of level `lvl` (up or down).
func set_level(skill: StringName, lvl: int) -> void:
	if not SKILLS.has(skill):
		return
	var before := level(skill)
	xp[skill] = xp_for_level(clampi(lvl, 1, MAX_LEVEL))
	SaveGame.mark_dirty()
	xp_gained.emit(skill, 0, xp[skill])
	if level(skill) > before:
		leveled_up.emit(skill, level(skill))


func xp_for_level(lvl: int) -> int:
	return int(CURVE_BASE * pow(lvl - 1, CURVE_EXPONENT))


func level(skill: StringName) -> int:
	var total: int = xp.get(skill, 0)
	var lvl := 1
	while lvl < MAX_LEVEL and total >= xp_for_level(lvl + 1):
		lvl += 1
	return lvl


## 0 -> 1 progress through the current level (1.0 at max level).
func progress(skill: StringName) -> float:
	var lvl := level(skill)
	if lvl >= MAX_LEVEL:
		return 1.0
	var start := xp_for_level(lvl)
	return float(xp.get(skill, 0) - start) / (xp_for_level(lvl + 1) - start)


func display_name(skill: StringName) -> String:
	return SKILLS[skill]["name"] if SKILLS.has(skill) else String(skill)


func color(skill: StringName) -> Color:
	return SKILLS[skill]["color"] if SKILLS.has(skill) else Color.WHITE


func to_dict() -> Dictionary:
	return xp.duplicate()


func from_dict(d: Dictionary) -> void:
	xp.clear()
	for key in d:
		xp[StringName(key)] = int(d[key])  # JSON stores numbers as floats


func _unhandled_input(event: InputEvent) -> void:
	if OS.is_debug_build() and event.is_action_pressed("debug_give_xp"):
		add_xp(last_trained, DEBUG_XP)
