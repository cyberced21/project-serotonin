class_name Talents
extends RefCounted
## The talents you've picked (plans/levels.md): per skill, one of a pair at each milestone
## (TalentDef.MILESTONES), plus at level 50 the other option of one milestone (mastery, L6).
## Skills owns one (Skills.talents) and saves it under its own key. Gameplay asks has(id).
## A choice reached while gathering waits for the action to end (TalentCards); "decide later"
## leaves it waiting on the Skills page. Greta resets one skill's picks (respec, L8).

## A skill's picks or mastery changed (picked, or reset).
signal changed(skill: StringName)
## A new choice is waiting in `skill`: a milestone (or mastery) was just reached, or a respec
## opened them all again.
signal choice_ready(skill: StringName)

const DIR := "res://data/talents/"

var defs: Dictionary[StringName, TalentDef] = {}
## Skill -> {milestone (int) -> talent id}.
var picks: Dictionary[StringName, Dictionary] = {}
## Skill -> the talent id taken at mastery.
var mastery: Dictionary[StringName, StringName] = {}
## The first respec ever is free (forgives a newcomer's pick at 10).
var free_respec := true

var _level: Callable  # skill -> level (Skills.level)


func _init(level: Callable) -> void:
	_level = level
	for file in ResourceLoader.list_directory(DIR):
		if file.ends_with(".tres") or file.ends_with(".res"):
			var def := load(DIR + file) as TalentDef
			if def:
				defs[def.id] = def


## Whether you have talent `id` (picked at its milestone, or at mastery).
func has(id: StringName) -> bool:
	var def: TalentDef = defs.get(id)
	if def == null:
		return false
	return picks.get(def.skill, {}).get(def.milestone, &"") == id or mastery.get(def.skill, &"") == id


## The two options at `milestone`, in style order (each skill's styles always in the same columns).
func pair(skill: StringName, milestone: int) -> Array[TalentDef]:
	var out: Array[TalentDef] = []
	for def in defs.values():
		if def.skill == skill and def.milestone == milestone:
			out.append(def)
	out.sort_custom(func(a: TalentDef, b: TalentDef) -> bool: return String(a.style) < String(b.style))
	return out


## The talent picked at `milestone`, or null.
func picked(skill: StringName, milestone: int) -> TalentDef:
	return defs.get(picks.get(skill, {}).get(milestone, &""))


func waiting(skill: StringName) -> Array[int]:
	return TalentDef.waiting(_level.call(skill), picks.get(skill, {}))


func mastery_waiting(skill: StringName) -> bool:
	return TalentDef.mastery_waiting(_level.call(skill), picks.get(skill, {}), mastery.get(skill, &""))


## Whether `skill` has any choice waiting (a milestone or mastery).
func has_waiting(skill: StringName) -> bool:
	return not waiting(skill).is_empty() or mastery_waiting(skill)


func any_waiting() -> bool:
	for skill in Perks.TRACKS:
		if has_waiting(skill):
			return true
	return false


## At mastery: the option you didn't pick at each milestone.
func mastery_options(skill: StringName) -> Array[TalentDef]:
	var out: Array[TalentDef] = []
	for m in TalentDef.MILESTONES:
		for def in pair(skill, m):
			if not has(def.id):
				out.append(def)
	return out


func pick(skill: StringName, milestone: int, id: StringName) -> bool:
	var def: TalentDef = defs.get(id)
	if def == null or def.skill != skill or def.milestone != milestone or not milestone in waiting(skill):
		return false
	if not picks.has(skill):
		picks[skill] = {}
	picks[skill][milestone] = id
	changed.emit(skill)
	return true


func pick_mastery(skill: StringName, id: StringName) -> bool:
	var def: TalentDef = defs.get(id)
	if def == null or not mastery_waiting(skill) or not def in mastery_options(skill):
		return false
	mastery[skill] = id
	changed.emit(skill)
	return true


## How many picks a respec of `skill` would undo (mastery counts as one).
func picked_count(skill: StringName) -> int:
	return picks.get(skill, {}).size() + (1 if mastery.has(skill) else 0)


## What Greta asks to reset `skill`'s picks: {} when it's free.
func respec_cost(skill: StringName) -> Dictionary:
	return TalentDef.respec_cost(skill, picked_count(skill), free_respec)


## Pays and clears `skill`'s picks; every milestone reached waits to be chosen again.
func respec(skill: StringName, inventory: Node) -> bool:
	if picked_count(skill) == 0:
		return false
	var cost := respec_cost(skill)
	if not cost.is_empty() and not inventory.spend(cost):
		return false
	picks.erase(skill)
	mastery.erase(skill)
	free_respec = false
	changed.emit(skill)
	choice_ready.emit(skill)
	return true


## Skills calls this when `skill` goes from level `before` to `after`.
func on_level(skill: StringName, before: int, after: int) -> void:
	for m in TalentDef.MILESTONES + [TalentDef.MASTERY]:
		if before < m and after >= m and has_waiting(skill):
			choice_ready.emit(skill)
			return


func to_dict() -> Dictionary:
	var p := {}
	for skill in picks:
		var by_level := {}
		for m in picks[skill]:
			by_level[str(m)] = String(picks[skill][m])
		p[String(skill)] = by_level
	var ms := {}
	for skill in mastery:
		ms[String(skill)] = String(mastery[skill])
	return {"picks": p, "mastery": ms, "free_respec": free_respec}


func from_dict(d: Dictionary) -> void:
	picks.clear()
	mastery.clear()
	var p: Dictionary = d.get("picks", {})
	for skill in p:
		var by_level := {}
		for m in p[skill]:
			if defs.has(StringName(p[skill][m])):  # (a talent since removed is just forgotten)
				by_level[int(m)] = StringName(p[skill][m])  # JSON keys are strings
		picks[StringName(skill)] = by_level
	var ms: Dictionary = d.get("mastery", {})
	for skill in ms:
		if defs.has(StringName(ms[skill])):
			mastery[StringName(skill)] = StringName(ms[skill])
	free_respec = d.get("free_respec", true)
