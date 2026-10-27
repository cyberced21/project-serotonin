extends SceneTree
## The talent balance bench (plans/levels.md, "Keeping it balanced"): for each milestone of a
## skill, a bot (tools/bench_bot.gd) plays a few game minutes with no talent, then with each option
## of the pair, at that milestone's level and the best tools, in a fresh copy of the same world.
## It prints yield and XP per minute, each option against the baseline, and whether the pair is
## within ±15% of each other (L4). Gathering is judged on items per minute; fishing on XP per
## minute (a rod fish pays more than a speared one by design: plans/fishing-parity.md). Fishing's
## pairs are one rod talent (angler) and one spear talent (spearman): each is played with its tool,
## against that tool's own baseline.
## Only the talent under test is picked (the milestones below it stay empty), so each is measured
## on its own. Each option runs `--repeats` times; when its runs disagree by more than the band,
## the verdict says so instead of judging. Rare finds (heartwood, gems...) aren't counted yet: they come with phase 6.
##
##   godot --path . --screen 1 --resolution 1280x720 -s res://tools/talent_bench.gd -- --save-root=user://talent_bench [--skill=woodcutting] [--milestones=10,20,30,40] [--minutes=3] [--speed=3] [--seed=42] [--repeats=2] [--verbose=1]
##
## Muted unless `--sound=1`. Windowed (the mouse has to be captured for the player to swing). A scratch world under its own
## save root; the real saves are never touched.
## (Untyped on purpose: an -s script can't name the game's classes that use autoloads.)

const BenchBot := preload("res://tools/bench_bot.gd")
## L4: the two options of a pair should land within this of each other.
const PAIR_TOLERANCE := 0.15
const STYLE_TOOL := {&"angler": "rod", &"spearman": "spear"}
const FISH_SAVE := "user://talent_bench_fishing_save.json"

var skill: StringName = &"woodcutting"
var milestones: PackedInt32Array = [10, 20, 30, 40]
var minutes := 3.0
var world_seed := 42
## Runs per option, averaged: the bot isn't frame-exact, so one run of 3 minutes can land 20% off
## an identical one (rocks especially: one more or less breaks in the time).
var repeats := 2
var bot: BenchBot
var _report: PackedStringArray = []


func _initialize() -> void:
	bot = BenchBot.new(self)
	for arg in OS.get_cmdline_user_args():
		var kv := arg.trim_prefix("--").split("=")
		if kv.size() != 2:
			continue
		match kv[0]:
			"skill": skill = StringName(kv[1])
			"minutes": minutes = kv[1].to_float()
			"speed": bot.speed = kv[1].to_float()
			"seed": world_seed = kv[1].to_int()
			"repeats": repeats = maxi(kv[1].to_int(), 1)
			"verbose": bot.verbose = kv[1] == "1"
			"milestones":
				milestones = PackedInt32Array()
				for m in kv[1].split(","):
					milestones.append(m.to_int())
	_run.call_deferred()


func _run() -> void:
	# a throwaway first run: the first world in a process plays worse (shaders compiling, caches
	# filling), which once put a no-talent baseline 35% under two identical runs after it
	var real := minutes
	minutes = 0.5
	await _session(milestones[0], null, "rod" if skill == &"fishing" else "")
	minutes = real
	_report.append("=== talent bench: %s, %.0f game minutes a run, seed %d ===" % [skill, minutes, world_seed])
	for m in milestones:
		await _milestone(m)
	print("\n" + "\n".join(_report))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(FISH_SAVE))
	Engine.time_scale = 1.0
	quit()


## The baseline(s), then each option of the pair at `m`, then the verdict.
func _milestone(m: int) -> void:
	var pair: Array = root.get_node("Skills").get("talents").call("pair", skill, m)
	if pair.size() != 2:
		_report.append("%d: no pair" % m)
		return
	var tools := ["rod", "spear"] if skill == &"fishing" else [""]
	var base := {}
	var noise := 0.0
	for tool in tools:
		base[tool] = await _repeated(m, null, tool)
		noise = maxf(noise, base[tool]["spread"])
		_report.append("%2d  %-18s %s" % [m, "(none%s)" % (", " + tool if tool != "" else ""), _line(base[tool], {})])
	var scores: Array[float] = []
	for def in pair:
		var tool: String = STYLE_TOOL.get(def.style, "")
		var r := await _repeated(m, def, tool)
		noise = maxf(noise, r["spread"])
		_report.append("%2d  %-18s %s" % [m, def.display_name, _line(r, base[tool])])
		scores.append(_score(r))
	var gap := absf(scores[0] - scores[1]) / maxf((scores[0] + scores[1]) * 0.5, 0.001)
	var verdict := "ok" if gap <= PAIR_TOLERANCE else "OFF (want within %.0f%%)" % (PAIR_TOLERANCE * 100.0)
	if noise > PAIR_TOLERANCE:  # runs of one option disagree by more than the band: no verdict
		verdict = "too noisy to judge (runs differ by up to %.0f%%: longer --minutes or more --repeats)" % (noise * 100.0)
	_report.append("    pair gap %.0f%%  %s" % [gap * 100.0, verdict])


## `repeats` sessions of one option, averaged; "spread" is how far apart their scores were,
## as a share of the mean (the bench's own noise).
func _repeated(m: int, def, tool: String) -> Dictionary:
	var items := 0.0
	var xp := 0.0
	var lo := INF
	var hi := 0.0
	for i in repeats:
		var r := await _session(m, def, tool)
		items += r["items_min"]
		xp += r["xp_min"]
		lo = minf(lo, _score(r))
		hi = maxf(hi, _score(r))
	var out := {"items_min": items / repeats, "xp_min": xp / repeats}
	out["spread"] = (hi - lo) / maxf(_score(out), 0.001)
	return out


## What a pair is judged on: items per minute, or XP per minute for fishing.
func _score(r: Dictionary) -> float:
	return r["xp_min"] if skill == &"fishing" else r["items_min"]


func _line(r: Dictionary, base: Dictionary) -> String:
	var s := "%6.1f items/min  %6.0f XP/min" % [r["items_min"], r["xp_min"]]
	if r.has("spread") and repeats > 1:
		s += "  runs ±%.0f%%" % (r["spread"] * 50.0)
	if not base.is_empty() and _score(base) > 0.0:
		s += "  (%+.0f%% vs none)" % ((_score(r) / _score(base) - 1.0) * 100.0)
	return s


## A fresh copy of the bench's world, the HUD's talent cards out of the way. Fishing plays the
## pond in main.tscn, as tools/fishing_bench.gd does: shallow enough for the spear (a generated
## world's biggest water can be too deep to wade).
func _load_world() -> void:
	Engine.time_scale = 1.0
	bot.release_all()
	if skill == &"fishing":
		root.get_node("SaveGame").set("path", FISH_SAVE)  # (never save over a real file)
		change_scene_to_file("res://scenes/main.tscn")
		await bot.wait_real(3.0)
	else:
		root.get_node("Worlds").call("play_scratch", world_seed)
		await process_frame
		while get_first_node_in_group("loading_screen") != null or get_first_node_in_group("player") == null:
			await process_frame
		await bot.wait_real(1.0)
	var gfx := root.get_node_or_null("GraphicsSettings")
	if gfx:
		gfx.set("persist", false)
	var cards := get_first_node_in_group("talent_cards")
	if cards:
		cards.queue_free()  # (setting the level opens choices; the bench picks for itself)


## `minutes` of play at level `m` with talent `def` (or none) and `tool` for fishing.
func _session(m: int, def, tool: String) -> Dictionary:
	await _load_world()
	var skills := root.get_node("Skills")
	skills.call("set_level", skill, m)
	var talents = skills.get("talents")
	talents.get("picks").clear()
	talents.get("mastery").clear()
	if def != null:
		talents.get("picks")[skill] = {m: def.id}
	var tools := root.get_node("Tools")
	for t in tools.get("LADDER"):
		tools.call("set_tier", t, tools.call("max_tier", t))
	# gathering: the best nodes the level allows, with the tool that just opens them (as
	# tools/talent_model.gd plays it; the best tool would fell anything in a swing or two)
	bot.only_tier = -1
	if skill != &"fishing":
		var best := 0
		for n in get_nodes_in_group("gatherable"):
			if n.get("skill") == skill and int(n.get("required_level")) <= m:
				best = maxi(best, int(n.get("tool_tier")))
		var swung: StringName = _tool_of(skill)
		if swung != &"":
			tools.call("set_tier", swung, best)
		bot.only_tier = best
	if tool != "":
		tools.set("fishing_style", StringName(tool))
	root.get_node("DayNight").set("time", 0.4)
	seed(world_seed)  # the same drops and bites each run: the difference is the talent, not the dice
	await bot.start_clock()
	var water = null
	if skill == &"fishing":
		var list: Array = bot.waters()
		if list.is_empty():
			return {"items_min": 0.0, "xp_min": 0.0}
		water = list[0]
		var first: Array = bot.schools(water)
		await bot.stand_on_shore(water, first[0] if not first.is_empty() else null, false)
	var xp0: int = skills.get("xp").get(skill, 0)
	var items0 := _items()
	var start: float = bot.clock
	var end: float = start + minutes * 60.0
	while bot.clock < end:
		if skill != &"fishing":
			await bot.gather_try(skill)
		elif tool == "rod":
			await bot.rod_try(water)
		else:
			await bot.spear_try(water)
	bot.release_all()
	await bot.wait_game(5.0)  # the last drops land and fly in (left lying, they pull in after 4 s)
	var mins: float = (bot.clock - start) / 60.0
	var r := {"items_min": (_items() - items0) / mins, "xp_min": (skills.get("xp").get(skill, 0) - xp0) / mins}
	print("  %d %s%s: %s" % [m, def.display_name if def else "none", " (%s)" % tool if tool != "" else "", _line(r, {})])
	return r


func _items() -> int:
	var inv := root.get_node("Inventory")
	var n := 0
	for id in inv.get("items"):
		n += inv.call("count", id)
	return n


## The tool a gathering skill swings.
func _tool_of(s: StringName) -> StringName:
	return {&"woodcutting": &"axe", &"mining": &"pickaxe", &"farming": &"sickle"}.get(s, &"")
