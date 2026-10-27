extends SceneTree
## Headless checks for the per-level perks (Perks, plans/levels.md): no scene, no save is touched.
##
##     godot --headless --path . -s res://tools/test_perks.gd

## Skills.MAX_LEVEL (the autoload's script doesn't compile under -s: it needs SaveGame).
const MAX_LEVEL := 50

var _failures := 0


func _init() -> void:
	_check(Perks.track_at(1) == -1, "level 1 gives no perk")
	_check(Perks.track_at(2) == 0 and Perks.track_at(3) == 1 and Perks.track_at(4) == 2 and Perks.track_at(5) == 0,
		"levels feed the tracks in turn")
	for skill in Perks.TRACKS:
		var tracks: Array = Perks.TRACKS[skill]
		_check(tracks.size() == 3, "%s: three tracks" % skill)
		for i in 3:
			_check(Perks.bonus_at(skill, tracks[i]["id"], 1) == 0.0, "%s %s: nothing at level 1" % [skill, tracks[i]["id"]])
			var top := Perks.bonus_at(skill, tracks[i]["id"], MAX_LEVEL)
			_check(top >= 0.3 and top <= 0.4, "%s %s: +%.0f%% at %d (want 30 to 40)" % [skill, tracks[i]["id"], top * 100.0, MAX_LEVEL])
		# every level from 2 on steps up exactly one track, and names it
		for lvl in range(2, MAX_LEVEL + 1):
			var grew := 0
			for i in 3:
				grew += Perks.steps(lvl, i) - Perks.steps(lvl - 1, i)
			_check(grew == 1, "%s %d: one step" % [skill, lvl])
			_check(not Perks.perk_at(skill, lvl).is_empty(), "%s %d: names its perk" % [skill, lvl])
	_check(Perks.bonus_at(&"woodcutting", &"nope", 30) == 0.0, "an unknown track gives nothing")
	print("test_perks: %s" % ("all passed" if _failures == 0 else "%d FAILED" % _failures))
	quit(1 if _failures > 0 else 0)


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failures += 1
		print("  FAIL: ", what)
