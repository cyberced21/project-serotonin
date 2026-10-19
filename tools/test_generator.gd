extends SceneTree
## Checks that default world settings still build exactly the land the generator built before
## world settings existed (so existing worlds don't change), and that each knob does something:
##   godot --headless --path . -s res://tools/test_generator.gd [-- --print]
## --print: just print each seed's fingerprint (to record new EXPECTED values after a deliberate
## generator change; bump ProcgenMap.GENERATOR_VERSION then).

const SEEDS: Array[int] = [1, 42, 371656]
## Fingerprints of heights, texture ids, cells, waters and rivers per seed, from before world settings.
const EXPECTED := {
	1: "957033808/850245363/442511555/9/2/6/meadow,birch_grove,rolling_downs,marsh,broken_pit,lone_peak,lakeside_village",
	42: "701640295/354351670/2597091015/8/1/3/meadow,old_growth,orchard_downs,marsh,terraced_pit,twin_peaks,lakeside_village",
	371656: "140021298/993065462/3402003314/8/2/4/meadow,pine_forest,grainfields,marsh,broken_pit,ridge,lakeside_village",
}

var _fails := 0


func _initialize() -> void:
	var print_only := OS.get_cmdline_user_args().has("--print")
	for s in SEEDS:
		var map := ProcgenMap.new(s)
		map.generate()
		var fp := fingerprint(map)
		if print_only:
			print("	%d: \"%s\"," % [s, fp])
		else:
			_check(EXPECTED.get(s) == fp, "seed %d unchanged on default settings (%s)" % [s, fp])
	if not print_only:
		_knobs()
		print("test_generator: %s" % ("PASS" if _fails == 0 else "%d FAILED" % _fails))
	quit(1 if _fails else 0)


static func fingerprint(map: ProcgenMap) -> String:
	var parts := PackedStringArray([
		str(hash(map.heights)), str(hash(map.ids)), str(hash(map.cells)),
		str(map.waters.size()), str(map.rivers.size()), str(map.landmarks.size()), ",".join(map.kinds.values()),
	])
	return "/".join(parts)


func _knobs() -> void:
	var base := _map({})
	var picked := _map({"kinds": {"pinewood": "old_growth", "quarry": "deep_pit"}})
	_check(picked.kinds[&"pinewood"] == &"old_growth" and picked.kinds[&"quarry"] == &"deep_pit", "picked kinds are used")
	var others_same := true
	for b in base.kinds:
		if b != &"pinewood" and b != &"quarry" and base.kinds[b] != picked.kinds[b]:
			others_same = false
	_check(others_same, "picking kinds leaves the other biomes' rolls alone")
	_check(base.hub == picked.hub, "picking kinds doesn't move the hub")

	var dry := _map({"water": "dry"})
	var wet := _map({"water": "wet"})
	_check(dry.rivers.is_empty(), "dry: no rivers")
	_check(dry.waters.size() < base.waters.size(), "dry: fewer waters (%d < %d)" % [dry.waters.size(), base.waters.size()])
	_check(wet.rivers.size() == 2, "wet: two rivers (%d)" % wet.rivers.size())
	_check(wet.waters.size() > base.waters.size(), "wet: more waters (%d > %d)" % [wet.waters.size(), base.waters.size()])

	var gentle := _map({"terrain": "gentle"})
	var rugged := _map({"terrain": "rugged"})
	var hb := _inner_height(base)
	_check(_inner_height(gentle) < hb and hb < _inner_height(rugged), "terrain: gentle < normal < rugged (%.1f, %.1f, %.1f)"
			% [_inner_height(gentle), hb, _inner_height(rugged)])

	for mpp in [4.0, 2.0]:
		var started := Time.get_ticks_msec()
		var preview := ProcgenMap.new(SEEDS[0], {}, mpp)
		preview.generate()
		var ms := Time.get_ticks_msec() - started
		var same_sites := preview.sites.size() == base.sites.size()
		for k in mini(preview.sites.size(), base.sites.size()):
			same_sites = same_sites and preview.sites[k]["pos"] == base.sites[k]["pos"]
		_check(same_sites and preview.kinds == base.kinds, "a %d m/pixel preview has the same sites and kinds (%d ms, %d px)"
				% [mpp, ms, preview.size])
		_check(preview.preview_image().get_size() == Vector2i(preview.size, preview.size), "its picture is %d px" % preview.size)

	var n := WorldSettings.normalized({"seed": 5.0, "size": "huge", "water": "wet", "kinds": {"pinewood": "nope"}})
	_check(n["seed"] is int and n["size"] == &"normal" and n["water"] == &"wet" and n["kinds"].is_empty(),
			"normalized: ints, unknown choices back to normal")


func _map(settings: Dictionary) -> ProcgenMap:
	var map := ProcgenMap.new(SEEDS[0], settings)
	map.generate()
	return map


## The highest ground inside the rim, roughly (every 8th pixel).
func _inner_height(map: ProcgenMap) -> float:
	var top := -INF
	for y in range(0, map.size, 8):
		for x in range(0, map.size, 8):
			var i := y * map.size + x
			if map.cells[i] != ProcgenMap.RIM_CELL:
				top = maxf(top, map.heights[i])
	return top


func _check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		_fails += 1
