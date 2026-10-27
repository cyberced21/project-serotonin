extends SceneTree
## Spear vs rod, measured (plans/fishing-parity.md P3): a bot fishes the same water for a few game
## minutes with each tool, at the same level and tier, and prints fish and XP per minute. Both
## play like a skilled player (tools/bench_bot.gd). Everything else is the real game: scattering,
## regrowth, dodges, sizes, Big and Huge counts. Each run starts from a fresh copy of the world.
##
##   godot --path . --screen 1 --resolution 1280x720 -s res://tools/fishing_bench.gd -- [--minutes=4] [--level=30] [--tier=3] [--tools=spear,rod] [--water=0,1] [--speed=3]
##
## `--water`: which waters (by size, biggest first; the list is printed). Muted unless `--sound=1`. Windowed (the mouse has
## to be captured for the player to fish). A throwaway save; settings.cfg untouched.
## (Untyped on purpose: an -s script can't name the game's classes that use autoloads.)

const SAVE := "user://fishing_bench_save.json"
const FISH := ["perch", "trout", "pike", "char", "grayling", "salmon"]
const BenchBot := preload("res://tools/bench_bot.gd")

var minutes := 4.0
var level := 30
var tier := 3
var tool_names: PackedStringArray = ["spear", "rod"]
var waters: PackedInt32Array = [0, 1]
var bot: BenchBot
var _results: PackedStringArray = []


func _initialize() -> void:
	bot = BenchBot.new(self)
	for arg in OS.get_cmdline_user_args():
		var kv := arg.trim_prefix("--").split("=")
		if kv.size() != 2:
			continue
		match kv[0]:
			"minutes": minutes = kv[1].to_float()
			"level": level = kv[1].to_int()
			"tier": tier = kv[1].to_int()
			"speed": bot.speed = kv[1].to_float()
			"verbose": bot.verbose = kv[1] == "1"
			"tools": tool_names = kv[1].split(",")
			"water":
				waters = PackedInt32Array()
				for w in kv[1].split(","):
					waters.append(w.to_int())
	_run.call_deferred()


func _run() -> void:
	root.get_node("SaveGame").set("path", SAVE)  # (never save over the real file)
	for w in waters:
		for tool in tool_names:
			await _session(w, tool)
	print("\n=== fishing bench: level %d, tier %d, %.0f game minutes each ===" % [level, tier, minutes])
	for r in _results:
		print(r)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
	Engine.time_scale = 1.0
	quit()


## One tool on one water, from a fresh world.
func _session(water_index: int, tool: String) -> void:
	Engine.time_scale = 1.0
	change_scene_to_file("res://scenes/main.tscn")
	await bot.wait_real(3.0)
	var gfx := root.get_node_or_null("GraphicsSettings")
	if gfx:
		gfx.set("persist", false)
	var skills := root.get_node("Skills")
	skills.call("set_level", &"fishing", level)
	var tools := root.get_node("Tools")
	tools.call("set_tier", &"spear", tier)
	tools.call("set_tier", &"rod", tier)
	tools.set("fishing_style", StringName(tool))
	root.get_node("DayNight").set("time", 0.4)
	await bot.start_clock()
	var list := bot.waters()
	if water_index >= list.size():
		_results.append("water %d: none" % water_index)
		return
	var water = list[water_index]
	if tool == tool_names[0]:
		var kinds := {}
		for s in bot.schools(water):
			kinds[String(s.species.id)] = kinds.get(String(s.species.id), 0) + s.fish.size()
		print("water %d: %s" % [water_index, kinds])
	var xp0: int = skills.get("xp").get(&"fishing", 0)
	var fish0 := _fish_count()
	var tries := 0
	var first: Array = bot.schools(water)
	await bot.stand_on_shore(water, first[0] if not first.is_empty() else null, false)
	var start: float = bot.clock
	var end: float = start + minutes * 60.0
	while bot.clock < end:
		tries += 1
		if tool == "rod":
			await bot.rod_try(water)
		else:
			await bot.spear_try(water)
	bot.release_all()
	var mins: float = (bot.clock - start) / 60.0
	var xp: int = skills.get("xp").get(&"fishing", 0) - xp0
	var fish := _fish_count() - fish0
	var line := "water %d  %-5s  %3d fish  %5d XP  in %.1f min (%d tries)  ->  %.1f fish/min, %.0f XP/min" % [
		water_index, tool, fish, xp, mins, tries, fish / mins, xp / mins]
	print(line)
	_results.append(line)


func _fish_count() -> int:
	var n := 0
	for id in FISH:
		n += root.get_node("Inventory").call("count", StringName(id))
	return n
