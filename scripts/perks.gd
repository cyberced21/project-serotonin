class_name Perks
extends RefCounted
## The small perk every level brings (plans/levels.md, L1): each skill has three minor tracks,
## and each level from 2 on adds one step to the next track in turn, so every level names
## something real ("Woodcutting 13: steadier aim"). Perks sharpen technique (windows, recovery,
## reach), never raw output: the village owns the percentages (TierEffect).

## How much better a track gets per step: 16 or 17 steps by level 50, about +35 to 37%.
const STEP := 0.022

## Skill -> its three tracks, in the order levels feed them: {id, name, what one step does}.
const TRACKS := {
	&"woodcutting": [
		{"id": &"aim", "name": "Steadier aim", "text": "a wider clean-cut window into the notch"},
		{"id": &"recovery", "name": "Quicker recovery", "text": "less time between swings"},
		{"id": &"reach", "name": "Long reach", "text": "logs fly to you from further away"},
	],
	&"mining": [
		{"id": &"aim", "name": "Keen eye", "text": "more leeway on a crack tip"},
		{"id": &"recovery", "name": "Quicker recovery", "text": "less time between swings"},
		{"id": &"reach", "name": "Long reach", "text": "ore flies to you from further away"},
	],
	&"fishing": [
		{"id": &"hands", "name": "Quick hands", "text": "a wider strike window, a thicker thrust"},
		{"id": &"patience", "name": "Patience", "text": "bites come sooner, scattered fish settle sooner"},
		{"id": &"cast", "name": "Smooth cast", "text": "a wider sweet spot on the release"},
	],
	&"farming": [
		{"id": &"blade", "name": "Wide blade", "text": "the sickle catches sheaves a little off the crosshair"},
		{"id": &"recovery", "name": "Quicker recovery", "text": "less time between swings"},
		{"id": &"reach", "name": "Long reach", "text": "grain flies to you from further away"},
	],
}

## The swinging tools' skills (the quicker-recovery track follows the tool in hand).
const TOOL_SKILL := {&"axe": &"woodcutting", &"pickaxe": &"mining", &"sickle": &"farming"}


## Which track (0..2) level `lvl` steps up; -1 for level 1, which gives nothing.
static func track_at(lvl: int) -> int:
	return (lvl - 2) % 3 if lvl >= 2 else -1


## How many steps track `index` has at level `lvl`.
static func steps(lvl: int, index: int) -> int:
	if lvl < 2 + index:
		return 0
	@warning_ignore("integer_division")
	return (lvl - 2 - index) / 3 + 1


## The bonus (0 at level 1, about +0.36 at 50) track `id` of `skill` gives at level `lvl`.
static func bonus_at(skill: StringName, id: StringName, lvl: int) -> float:
	var tracks: Array = TRACKS.get(skill, [])
	for i in tracks.size():
		if tracks[i]["id"] == id:
			return STEP * steps(lvl, i)
	return 0.0


## The track `id` of `skill` at your current level: 1.0 + this is the multiplier to use.
static func bonus(skill: StringName, id: StringName) -> float:
	var skills := (Engine.get_main_loop() as SceneTree).root.get_node_or_null("Skills")
	return bonus_at(skill, id, skills.level(skill)) if skills else 0.0


## The track level `lvl` of `skill` stepped up ({id, name, text}), or {} for level 1.
static func perk_at(skill: StringName, lvl: int) -> Dictionary:
	var i := track_at(lvl)
	return TRACKS[skill][i] if i >= 0 and TRACKS.has(skill) else {}
