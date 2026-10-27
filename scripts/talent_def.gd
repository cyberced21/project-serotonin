class_name TalentDef
extends Resource
## One talent (plans/levels.md, L2): a gameplay-changing mechanic offered at a milestone level,
## one of a pair, one from each of the skill's two styles. data/talents/<skill>_<id>.tres.
## The rules that don't need the game running (which milestones wait, what a respec costs) are
## static here, so tools/test_talents.gd can check them headless.

## The levels that offer a pair (L2); MASTERY offers the other option of one of them (L6).
const MILESTONES: Array[int] = [10, 20, 30, 40]
const MASTERY := 50
## Respec (L8): this many of the skill's base goods per milestone picked, doubled while there's
## no rare item to pay with instead. The first respec ever is free.
const RESPEC_GOODS_PER_PICK := 10
const BASE_GOODS := {&"woodcutting": &"wood", &"mining": &"ore", &"fishing": &"perch", &"farming": &"wheat"}

@export var id: StringName = &""
@export var skill: StringName = &"woodcutting"
## 10, 20, 30 or 40.
@export var milestone := 10
## The style it belongs to (L3): one option in each pair is from each.
@export var style: StringName = &""
@export var style_name := ""
@export var display_name := ""
@export_multiline var text := ""


## The milestones reached at `lvl` that have no pick in `picks` (milestone -> talent id), lowest first.
static func waiting(lvl: int, picks: Dictionary) -> Array[int]:
	var out: Array[int] = []
	for m in MILESTONES:
		if lvl >= m and not picks.has(m):
			out.append(m)
	return out


## Whether mastery is waiting: level 50, every milestone picked, no mastery pick yet.
static func mastery_waiting(lvl: int, picks: Dictionary, mastery: StringName) -> bool:
	return lvl >= MASTERY and mastery == &"" and waiting(lvl, picks).is_empty()


## What resetting a skill's picks costs: {} when free (the first respec) or nothing is picked.
static func respec_cost(skill: StringName, picked: int, free: bool) -> Dictionary:
	if free or picked == 0 or not BASE_GOODS.has(skill):
		return {}
	return {BASE_GOODS[skill]: RESPEC_GOODS_PER_PICK * picked * 2}
