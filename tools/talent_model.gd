extends SceneTree
## The talent model: woodcutting worked out in code instead of played (plans/levels.md, "Keeping it
## balanced"). An event simulation on a real world's trees: a gatherer goes to the nearest tree it
## should chop, walks there at walking speed, swings until it falls, and moves on, as
## tools/bench_bot.gd plays; trees regrow on their own timers. Every number comes from the game
## itself, read when it runs: swing timing from player.gd, each tree's hits, drops, XP and regrowth
## from its scene, perks from Perks, the talents' numbers from ResourceNode. Only where the trees
## stand comes from a measured world (tools/model_data/, made by --measure), since generating
## one takes a running game.
##
## Thousands of game minutes take well under a second, with no run-to-run noise. It can't see
## physics (a trunk rolling off a neighbour) or bugs in the real code: check it against
## tools/talent_bench.gd now and then (the bench plays the real game).
##
##   godot --headless --path . -s res://tools/talent_model.gd -- [--level=10,20,30,40] [--minutes=60] [--axe=N] [--talents=all|none|chain_cut,...] [--human=0.8]
##   godot --headless --path . -s res://tools/talent_model.gd -- --measure [--seed=42] --save-root=user://talent_model
##
## Per level it plays: no talent, then each option of that milestone's pair alone (the milestones
## below stay empty, as the bench does), and says whether the pair is within ±15%. The gatherer
## chops the best trees its level allows (the highest tool tier among trees at or under its level)
## with the axe that just opens them (one cut a hit), as a player who's kept up would; --axe
## overrides. --human: how often a swing that could be a clean cut is one (1 = the bot, which
## never misses). Rare finds count as logs at RARE_LOGS each (an assumption: tune it).
## (Untyped where it touches the game: an -s script can't name its classes until it runs.)

const DATA_DIR := "res://tools/model_data/"
## A rare find, in logs, for the score (plans/levels.md R4 sizes them as XP; this is a stand-in).
const RARE_LOGS := {&"heartwood": 8.0, &"trophy_log": 25.0}
## The bot waits this long after a tree falls before moving on (BenchBot.gather_try), and stands
## this far from a trunk (BenchBot.STAND_OFF).
const AFTER_FELL := 1.0
const STAND_OFF := 1.5
## How close a falling trunk passes for Dominoes to crush a tree (ResourceNode._crush_along).
const CRUSH_REACH := 0.9
const PAIR_TOLERANCE := 0.15
## Real swings take longer than player.gd's timings add up to (the frame a swing waits to start,
## the hit-stop stretching the bite, the tool settling): this many times as long. Calibrated
## against tools/talent_bench.gd (--swing-scale tries others).
const SWING_SCALE := 1.5
const MILESTONES := [10, 20, 30, 40]

var levels: Array[int] = [10, 20, 30, 40]
var minutes := 60.0
var axe_override := -1
var human := 1.0
var swing_scale := SWING_SCALE
var only: Array = []  # talent ids to run, empty = each milestone's pair
var world_seed := 42

var RN  # ResourceNode (the script)
var player  # a player.gd instance (never in the tree): swing timing
var perks  # Perks
var talent_defs := {}  # id -> TalentDef
var trees: Array[Dictionary] = []  # measured: pos (Vector2), scene, save_id, height
var _stats := {}  # scene path -> that tree's numbers


func _initialize() -> void:
	var measure := false
	for arg in OS.get_cmdline_user_args():
		var kv := arg.trim_prefix("--").split("=")
		match kv[0]:
			"measure": measure = true
			"seed": world_seed = kv[1].to_int()
			"minutes": minutes = kv[1].to_float()
			"axe": axe_override = kv[1].to_int()
			"human": human = kv[1].to_float()
			"swing-scale": swing_scale = kv[1].to_float()
			"level":
				levels.clear()
				for l in kv[1].split(","):
					levels.append(l.to_int())
			"talents":
				if kv[1] != "all":  # ("none": no talent)
					only = Array(kv[1].split(",")).map(func(s: String) -> StringName: return &"" if s == "none" else StringName(s))
	if measure:
		_measure.call_deferred()
	else:
		_run.call_deferred()


# --- measuring a world ----------------------------------------------------------------------

## Loads Hearthvale and writes where its trees stand (scene, save id, height).
func _measure() -> void:
	root.get_node("Worlds").call("play_fresh")
	await process_frame
	while get_first_node_in_group("player") == null:
		await process_frame
	var out := []
	for n in get_nodes_in_group("gatherable"):
		if n.get("skill") != &"woodcutting":
			continue
		var top := 0.0
		for m in n.find_children("*", "MeshInstance3D", true, false):
			var box: AABB = (m as MeshInstance3D).global_transform * (m as MeshInstance3D).get_aabb()
			top = maxf(top, box.end.y - n.global_position.y)
		out.append({"x": snappedf(n.global_position.x, 0.01), "z": snappedf(n.global_position.z, 0.01),
			"scene": n.scene_file_path, "save_id": String(n.get("save_id")), "height": snappedf(top, 0.01)})
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DATA_DIR))
	var path := DATA_DIR + "woodcutting_seed%d.json" % world_seed
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify({"seed": world_seed, "trees": out}, "\t"))
	f.close()
	print("talent_model: %d trees -> %s" % [out.size(), path])
	quit()


# --- the run --------------------------------------------------------------------------------

func _run() -> void:
	if not _load():
		quit(1)
		return
	for lvl in levels:
		_level(lvl)
	player.free()
	quit()


func _load() -> bool:
	var path := DATA_DIR + "woodcutting_seed%d.json" % world_seed
	if not FileAccess.file_exists(path):
		print("talent_model: no %s yet: run with --measure first" % path)
		return false
	for t in JSON.parse_string(FileAccess.get_file_as_string(path))["trees"]:
		trees.append({"pos": Vector2(t["x"], t["z"]), "scene": t["scene"], "save_id": StringName(t["save_id"]),
			"height": float(t["height"])})
	RN = load("res://scripts/resource_node.gd")
	perks = load("res://scripts/perks.gd")
	player = load("res://scripts/player.gd").new()
	for d in root.get_node("Skills").get("talents").get("defs").values():
		talent_defs[d.id] = d
	for t in trees:
		if not _stats.has(t["scene"]):
			var node = (load(t["scene"]) as PackedScene).instantiate()
			_stats[t["scene"]] = {"max_hits": node.max_hits, "tier": node.tool_tier, "req": node.required_level,
				"respawn": node.respawn_time, "drops": (node.drops_min + maxi(node.drops_min, node.drops_max)) * 0.5,
				"xp_hit": node.xp_per_hit, "xp_break": node.xp_on_break, "clean_after": node.clean_cut_after,
				"clean_extra": node.clean_cut_extra_hits, "name": t["scene"].get_file().get_basename()}
			node.free()
	return true


## No talent, then each option at `lvl`'s milestone (or --talents), and the verdict.
func _level(lvl: int) -> void:
	var tier := _best_tier(lvl)
	var axe := axe_override if axe_override >= 0 else tier
	var kinds := {}
	for t in trees:
		var s: Dictionary = _stats[t["scene"]]
		if s["tier"] == tier and s["req"] <= lvl:
			kinds[s["name"]] = kinds.get(s["name"], 0) + 1
	print("\n=== woodcutting %d: %s, axe tier %d, %.0f game minutes, human %.2f ===" % [lvl, kinds, axe, minutes, human])
	var options: Array = only.duplicate()
	if options.is_empty():
		options = [&""]
		var m := _milestone_at(lvl)
		if m > 0:
			for d in _pair(m):
				options.append(d.id)
	var base := {}
	var scores := []
	for id in options:
		var r := _simulate(lvl, tier, axe, id)
		if id == &"":
			base = r
		print("  %-14s %6.1f logs/min  %5.2f rare/min  %5.0f XP/min  score %6.1f%s   (%.1f s a tree, %.1f swings, %.0f%% clean)" % [
			talent_defs[id].display_name if id != &"" else "(none)", r["logs"], r["rare"], r["xp"], r["score"],
			"  %+.0f%%" % ((r["score"] / base["score"] - 1.0) * 100.0) if not base.is_empty() and id != &"" else "",
			r["tree_s"], r["swings"], r["clean"] * 100.0])
		if r["crushes"] > 0 or id == &"":
			print("                 works %d of the trees; %d crushed by a falling trunk" % [r["visited"], r["crushes"]])
		if id != &"":
			scores.append(r["score"])
	if scores.size() == 2:
		var gap: float = absf(scores[0] - scores[1]) / ((scores[0] + scores[1]) * 0.5)
		print("  pair gap %.0f%%  %s" % [gap * 100.0, "ok" if gap <= PAIR_TOLERANCE else "OFF (want within %.0f%%)" % (PAIR_TOLERANCE * 100.0)])


func _best_tier(lvl: int) -> int:
	var best := 0
	for s in _stats.values():
		if s["req"] <= lvl:
			best = maxi(best, s["tier"])
	return best


func _milestone_at(lvl: int) -> int:
	var m := 0
	for x in MILESTONES:
		if lvl >= x:
			m = x
	return m


func _pair(m: int) -> Array:
	var out := talent_defs.values().filter(func(d) -> bool: return d.skill == &"woodcutting" and d.milestone == m)
	out.sort_custom(func(a, b) -> bool: return String(a.style) < String(b.style))
	return out


# --- one session ------------------------------------------------------------------------------

## `minutes` of chopping at `lvl` with talent `id` (or none): logs, rare finds and XP per minute.
func _simulate(lvl: int, tier: int, axe: int, id: StringName) -> Dictionary:
	var has := func(t: StringName) -> bool: return t == id
	var state := []  # per tree: {ready_at, hits_left, fine}
	var eligible: Array[int] = []  # the trees it goes for
	var choppable: Array[int] = []  # every tree the axe cuts (what a Dominoes trunk can bring down)
	var no_pool: Array[int] = []
	for i in trees.size():
		var s: Dictionary = _stats[trees[i]["scene"]]
		state.append({"ready_at": 0.0, "hits_left": s["max_hits"], "fine": false})
		if (s["tier"] == tier and s["req"] <= lvl) or (s["tier"] <= axe and _old_growth(i, id)):
			eligible.append(i)
		if s["tier"] <= axe:
			choppable.append(i)
	if eligible.is_empty():
		return {"logs": 0.0, "rare": 0.0, "xp": 0.0, "score": 0.0, "tree_s": 0.0, "swings": 0.0, "clean": 0.0}
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var walk: float = player.walk_speed
	var pos: Vector2 = trees[eligible[0]]["pos"]
	var t := 0.0
	var end := minutes * 60.0
	var logs := 0.0
	var rare := {}
	var xp := 0.0
	var felled := 0
	var crushes := 0
	var visited := {}
	var swings := 0
	var cleans := 0
	var momentum := 0
	var last_fell := -INF
	var chop_time := 0.0
	while t < end:
		var i := _next_tree(eligible, state, pos, t, has.call(&"old_growth"), choppable if has.call(&"dominoes") else no_pool)
		if i < 0:  # nothing grown back: wait for the first
			var soonest := INF
			for j in eligible:
				soonest = minf(soonest, state[j]["ready_at"])
			t = soonest
			continue
		var tp: Vector2 = trees[i]["pos"]
		var dist := maxf(pos.distance_to(tp) - STAND_OFF, 0.0)
		var came_from := (pos - tp).normalized() if pos.distance_to(tp) > 0.01 else Vector2(0, 1)
		if has.call(&"dominoes"):  # stand on the side of a neighbour it can reach: it falls toward you
			var aim := _domino_target(i, choppable, state, t)
			if aim >= 0:
				came_from = (trees[aim]["pos"] - tp).normalized()
		t += dist / walk
		pos = tp + came_from * STAND_OFF
		if t - last_fell > player.momentum_window:
			momentum = 0
		visited[i] = true
		var r := _chop(i, state[i], lvl, axe, id, momentum, rng)
		t += r["time"] + AFTER_FELL
		chop_time += r["time"]
		swings += r["swings"]
		cleans += r["cleans"]
		xp += r["xp"]
		logs += r["logs"]
		for k in r["rare"]:
			rare[k] = rare.get(k, 0) + 1
		felled += 1
		if has.call(&"momentum") and t - (AFTER_FELL + r["time"]) - last_fell <= player.momentum_window:
			momentum = mini(momentum + 1, player.momentum_max)
		last_fell = t - AFTER_FELL
		_fell(i, state, t, has.call(&"grove_keeper"), _old_growth(i, id))
		if has.call(&"dominoes"):  # it falls toward its notch, swung aside of you (ResourceNode.FALL_ASIDE)
			var fall := came_from.rotated(deg_to_rad(RN.FALL_ASIDE) * (1.0 if rng.randf() < 0.5 else -1.0))
			for j in _crushed(i, fall, choppable, state, t):
				crushes += 1
				var s: Dictionary = _stats[trees[j]["scene"]]
				state[j]["hits_left"] = maxi(state[j]["hits_left"] - ceili(s["max_hits"] * RN.CRUSH_SHARE), 0)
				xp += s["xp_hit"] * 2
				if state[j]["hits_left"] == 0:  # down too: its logs, and it regrows
					logs += s["drops"] * RN.DOMINOES_LOGS
					xp += s["xp_break"]
					_fell(j, state, t, false)
	var mins := t / 60.0
	var rare_total := 0.0
	var rare_logs := 0.0
	for k in rare:
		rare_total += rare[k]
		rare_logs += rare[k] * RARE_LOGS.get(k, 0.0)
	return {"logs": logs / mins, "rare": rare_total / mins, "xp": xp / mins, "score": (logs + rare_logs) / mins,
		"tree_s": chop_time / maxf(felled, 1), "swings": float(swings) / maxf(felled, 1), "clean": float(cleans) / maxf(swings, 1),
		"crushes": crushes, "visited": visited.size()}


## The nearest grown tree (an old-growth one you can see counts as a quarter as far, as the bot
## goes for them), or -1.
## With Dominoes (`domino_pool`, the trees a trunk can bring down) a tree with one in reach counts
## as half as far: a player looks for them.
func _next_tree(eligible: Array[int], state: Array, pos: Vector2, t: float, old_growth: bool, domino_pool: Array[int]) -> int:
	var best := -1
	var best_d := INF
	for i in eligible:
		if state[i]["ready_at"] > t:
			continue
		var d := pos.distance_to(trees[i]["pos"])
		if old_growth and _old_growth(i, &"old_growth"):
			d *= 0.25
		if not domino_pool.is_empty() and _domino_target(i, domino_pool, state, t) >= 0:
			d *= 0.5
		if d < best_d:
			best_d = d
			best = i
	return best


func _old_growth(i: int, id: StringName) -> bool:
	return id == &"old_growth" and absi(hash(String(trees[i]["save_id"]))) % RN.OLD_GROWTH_ONE_IN == 0


## Down: it grows back after its time (halved by Grove keeper, and fine-grained then).
func _fell(i: int, state: Array, t: float, grove: bool, ancient := false) -> void:
	var s: Dictionary = _stats[trees[i]["scene"]]
	state[i]["ready_at"] = t + s["respawn"] * (RN.OLD_GROWTH_REGROW if ancient else 1.0) / (RN.GROVE_REGROW if grove else 1.0)
	state[i]["hits_left"] = s["max_hits"]
	state[i]["fine"] = grove


## Dominoes: the nearest standing tree within tree `i`'s height (where you'd make it fall), or -1.
func _domino_target(i: int, eligible: Array[int], state: Array, t: float) -> int:
	var best := -1
	var best_d: float = trees[i]["height"] * 0.9
	for j in eligible:
		if j == i or state[j]["ready_at"] > t:
			continue
		var d: float = trees[i]["pos"].distance_to(trees[j]["pos"])
		if d < best_d:
			best_d = d
			best = j
	return best


## The trees a trunk falling from tree `i` toward `dir` lands on (Dominoes).
func _crushed(i: int, dir: Vector2, eligible: Array[int], state: Array, t: float) -> Array[int]:
	var base: Vector2 = trees[i]["pos"]
	var tip: Vector2 = base + dir * float(trees[i]["height"])
	var out: Array[int] = []
	for j in eligible:
		if j == i or state[j]["ready_at"] > t:
			continue
		var p: Vector2 = trees[j]["pos"]
		var on := Geometry2D.get_closest_point_to_segment(p, base, tip)
		if on.distance_to(p) < CRUSH_REACH:
			out.append(j)
	return out


## Chopping one tree down, swing by swing, as ResourceNode.hit counts it. The notch deepens by
## each swing's hits over the tree's max; a swing into a notch that's clean_cut_after deep is a
## clean cut (for a `human` share of them). Every tree has a knot (plans/logging.md): the bot spots
## it a `human` share of the time (always when Heartwood makes it glow) and strikes it second swing.
func _chop(i: int, st: Dictionary, lvl: int, axe: int, id: StringName, momentum: int, rng: RandomNumberGenerator) -> Dictionary:
	var s: Dictionary = _stats[trees[i]["scene"]]
	var max_hits: int = s["max_hits"]
	var hits: int = st["hits_left"]
	var tough: float = RN.OLD_GROWTH_TOUGH if _old_growth(i, id) else 1.0
	var per_hit := (1.0 + maxi(axe - s["tier"], 0)) / tough
	var front := 0.0  # notch depth (share of a full notch) on your side, and on the far side
	var back := 0.0
	var on_back := false
	var went_round := false
	var cut := 0.0
	var chain := 0
	var knot := rng.randf() < (1.0 if id == &"heartwood" else human)
	var fine_cut := false
	var time := 0.0
	var xp := 0.0
	var swings := 0
	var cleans := 0
	var rare: Array[StringName] = []
	var cycle := _swing_time(lvl, momentum)
	var charge: float = player.power_charge_time + 0.1 if id == &"power_swing" else 0.0
	while hits > 0 and swings < 500:
		if id == &"back_cut" and not went_round and front >= RN.BACK_CUT_AFTER:
			went_round = true  # walk round to the far side (straight across, as the bot charges it)
			on_back = true
			time += 2.0 * STAND_OFF / player.walk_speed
		swings += 1
		time += cycle + charge
		cut += per_hit
		var cuts := int(cut)
		cut -= cuts
		var at_knot := knot and swings == 2  # (aimed at the knot, not the notch: no clean cut)
		var depth := back if on_back else front
		var clean: bool = not at_knot and not on_back and depth >= s["clean_after"] and rng.randf() < human
		var extra: int = s["clean_extra"] if clean else 0
		if cuts > 0:
			if id == &"chain_cut":
				chain = chain + 1 if clean else 0
				if chain >= 2:
					extra += mini(chain - 1, RN.CHAIN_MAX)
			if id == &"back_cut" and on_back and front >= RN.BACK_CUT_AFTER:
				extra += cuts * (RN.BACK_CUT_TIMES - 1)
			if id == &"power_swing":
				extra += maxi((RN.POWER_CLEAN_HITS if clean else RN.POWER_HITS) - (cuts + (s["clean_extra"] if clean else 0)), 0)
			if at_knot:
				extra += RN.KNOT_EXTRA
				if id == &"heartwood" and rng.randf() < RN.HEARTWOOD_CHANCE:
					rare.append(&"heartwood")
				knot = false
			if st["fine"] and clean and not fine_cut:
				fine_cut = true
		var took := mini(hits, cuts + extra)
		hits -= took
		cleans += 1 if clean else 0
		xp += s["xp_hit"] * (2 if clean else 1)
		if took > 0:
			var share := float(took) / max_hits
			if on_back:
				back += share
			else:
				front += share
	var logs: float = s["drops"] * (RN.FINE_GRAIN_DROPS if fine_cut else 1.0) \
		* (RN.OLD_GROWTH_DROPS if _old_growth(i, id) else 1) * (RN.DOMINOES_LOGS if id == &"dominoes" else 1.0)
	if _old_growth(i, id):
		rare.append(&"trophy_log")
	xp += s["xp_break"]
	return {"time": time, "logs": logs, "xp": xp, "rare": rare, "swings": swings, "cleans": cleans}


## One swing's game time with the axe (player.gd: wind-up, strike, the bite, the yank, recovery,
## cooldown); the recovery perk and Momentum shorten it. (Hit-stops freeze real time, not game time.)
func _swing_time(lvl: int, momentum: int) -> float:
	var pose: Dictionary = player.SWINGS[&"axe"]
	var pace: float = pose["pace"] * (1.0 + player.momentum_step * momentum)
	var quick: float = 1.0 + perks.bonus_at(&"woodcutting", &"recovery", lvl)
	return swing_scale * (player.windup_time / pace * pose.get("windup_scale", 1.0) + player.strike_time / pace
		+ player.bite_hold + player.yank_time
		+ (player.recover_time / pace * pose.get("recover_scale", 1.0) + player.swing_cooldown) / quick)
