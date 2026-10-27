extends SceneTree
## Headless checks for talents (TalentDef data in data/talents/, Talents picks, mastery, respec and
## save): no scene, no save is touched.
##
##     godot --headless --path . -s res://tools/test_talents.gd

## A stand-in for the Inventory autoload (Talents.respec only calls spend()).
class FakeInventory extends Node:
	var wood := 0

	func spend(cost: Dictionary) -> bool:
		if wood < cost.get(&"wood", 0):
			return false
		wood -= cost.get(&"wood", 0)
		return true


var _failures := 0
var _level := 1


func _init() -> void:
	var t := Talents.new(func(_skill: StringName) -> int: return _level)
	_test_data(t)
	_test_picks(t)
	_test_respec(t)
	_test_save(t)
	print("test_talents: %s" % ("all passed" if _failures == 0 else "%d FAILED" % _failures))
	quit(1 if _failures > 0 else 0)


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failures += 1
		print("  FAIL: ", what)


func _test_data(t: Talents) -> void:
	_check(t.defs.size() == 32, "32 talents (%d)" % t.defs.size())
	for skill in Perks.TRACKS:
		var columns: Array[StringName] = []
		for m in TalentDef.MILESTONES:
			var pair := t.pair(skill, m)
			_check(pair.size() == 2, "%s %d: a pair" % [skill, m])
			if pair.size() != 2:
				continue
			_check(pair[0].style != pair[1].style, "%s %d: one option per style" % [skill, m])
			if columns.is_empty():
				columns = [pair[0].style, pair[1].style]
			_check(pair[0].style == columns[0] and pair[1].style == columns[1], "%s %d: styles stay in their columns" % [skill, m])
			for def in pair:
				_check(not def.display_name.is_empty() and not def.text.is_empty() and not def.style_name.is_empty(),
					"%s: named and described" % def.id)


func _test_picks(t: Talents) -> void:
	var w := &"woodcutting"
	_level = 9
	_check(t.waiting(w).is_empty(), "nothing waits before 10")
	_level = 25
	_check(Array(t.waiting(w)) == [10, 20], "10 and 20 wait at 25")
	_check(not t.pick(w, 30, &"power_swing"), "can't pick a milestone not reached")
	_check(not t.pick(w, 10, &"dominoes"), "can't pick a talent from another milestone")
	_check(not t.pick(w, 10, &"shatter"), "can't pick another skill's talent")
	_check(t.pick(w, 10, &"chain_cut") and t.has(&"chain_cut") and not t.has(&"back_cut"), "picks chain cut")
	_check(not t.pick(w, 10, &"back_cut"), "a milestone is picked once")
	_check(t.pick(w, 20, &"heartwood"), "mixing styles is allowed")
	_level = 50
	_check(not t.mastery_waiting(w), "no mastery while milestones wait")
	t.pick(w, 30, &"power_swing")
	t.pick(w, 40, &"old_growth")
	_check(t.mastery_waiting(w), "mastery waits once all four are picked at 50")
	var options := t.mastery_options(w).map(func(d: TalentDef) -> StringName: return d.id)
	_check(options == [&"back_cut", &"dominoes", &"grove_keeper", &"momentum"], "mastery offers the four not taken: %s" % [options])
	_check(not t.pick_mastery(w, &"chain_cut"), "mastery can't retake a pick")
	_check(t.pick_mastery(w, &"dominoes") and t.has(&"dominoes") and not t.mastery_waiting(w), "mastery takes dominoes")
	_check(not t.has_waiting(w), "nothing left to choose")


func _test_respec(t: Talents) -> void:
	var w := &"woodcutting"
	var inv := FakeInventory.new()
	_check(t.respec_cost(w).is_empty(), "the first respec is free")
	var readied := [false]
	t.choice_ready.connect(func(_s: StringName) -> void: readied[0] = true)
	_check(t.respec(w, inv) and t.picked_count(w) == 0 and not t.has(&"chain_cut"), "respec clears the picks")
	_check(readied[0] and t.waiting(w).size() == 4, "and every milestone waits again")
	for m in TalentDef.MILESTONES:
		t.pick(w, m, t.pair(w, m)[0].id)
	_check(t.respec_cost(w) == {&"wood": 80}, "then 10 logs per pick, doubled: %s" % [t.respec_cost(w)])
	_check(not t.respec(w, inv) and t.picked_count(w) == 4, "can't pay: nothing changes")
	inv.wood = 100
	_check(t.respec(w, inv) and inv.wood == 20, "pays 80 logs")
	_check(not t.respec(w, inv), "nothing to reset")
	inv.free()


func _test_save(t: Talents) -> void:
	_level = 30
	t.pick(&"mining", 10, &"feel_the_grain")
	t.pick(&"mining", 20, &"split_shot")
	var copy := Talents.new(func(_skill: StringName) -> int: return _level)
	copy.from_dict(JSON.parse_string(JSON.stringify(t.to_dict())))
	_check(copy.has(&"feel_the_grain") and copy.has(&"split_shot") and not copy.has(&"shatter"), "picks survive a save")
	_check(Array(copy.waiting(&"mining")) == [30], "and what's waiting does too")
	_check(not copy.free_respec, "the free respec stays spent")
	copy.from_dict({})
	_check(copy.picks.is_empty() and copy.free_respec, "a new world starts clean")
