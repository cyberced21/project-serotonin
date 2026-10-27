extends SceneTree
## Headless checks for rod fishing's pure logic (RodCast, FishBite): no scene, no save is touched.
##
##     godot --headless --path . -s res://tools/test_fishing.gd

const SPECIES := ["perch", "trout", "pike", "char", "grayling", "salmon"]
## The shortest strike window a fish may have at its own level (s): a human sees the take and
## clicks in about 0.25 s, so this leaves room to spare.
const MIN_WINDOW := 0.4

var _failures := 0


func _init() -> void:
	_test_cast()
	_test_scales()
	for id in SPECIES:
		var s: FishSpecies = load("res://data/fish/%s.tres" % id)
		_test_window(s)
		_test_tells(s)
	print("test_fishing: %s" % ("all passed" if _failures == 0 else "%d FAILED" % _failures))
	quit(1 if _failures > 0 else 0)


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failures += 1
		print("  FAIL: ", what)


func _test_cast() -> void:
	_check(RodCast.judge(0.0)["quality"] == RodCast.Quality.PERFECT, "on the sweet spot is perfect")
	_check(RodCast.judge(0.0)["scatter"] == 0.0, "perfect lands on the aim point")
	_check(RodCast.judge(0.08)["quality"] == RodCast.Quality.GOOD, "80 ms late is good")
	var bad := RodCast.judge(-0.25)
	_check(bad["quality"] == RodCast.Quality.BAD and bad["early"], "250 ms early is bad and early")
	_check(bad["scatter"] > 2.0, "a bad cast scatters far")
	_check(RodCast.judge(0.08, 2.0)["quality"] == RodCast.Quality.PERFECT, "level widens the window")
	_check(RodCast.judge(0.5)["scatter"] == RodCast.MAX_SCATTER, "scatter tops out")


func _test_scales() -> void:
	_check(FishBite.window_scale(30, 30) == 1.0, "at level: no change")
	_check(is_equal_approx(FishBite.window_scale(50, 30), 1.2), "20 above: +20%")
	var five := FishBite.window_scale(25, 30)
	_check(five > 0.65 and five < 0.8, "5 under: hard but possible (%.2f)" % five)
	_check(FishBite.window_scale(10, 30) <= 0.21, "20 under: near-impossible")


func _test_window(s: FishSpecies) -> void:
	_check(s.strike_window >= MIN_WINDOW, "%s: %.2f s to pull at its level (want %.2f+)" % [s.id, s.strike_window, MIN_WINDOW])
	print("  %s: %.0f ms to pull at its level, %.0f ms five under" % [s.id, s.strike_window * 1000.0,
		s.strike_window * FishBite.window_scale(s.required_level - 5, s.required_level) * 1000.0])


func _test_tells(s: FishSpecies) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for k in 10:
		var tells := FishBite.tells(s, rng, 0.0)
		_check(not tells.is_empty() and tells.back()["kind"] == &"take", "%s: tells end on the take" % s.id)
		var nibbles := tells.filter(func(t: Dictionary) -> bool: return t["kind"] == &"nibble").size()
		if s.ambush:
			_check(nibbles == 0, "%s: an ambusher doesn't nibble" % s.id)
		else:
			_check(nibbles >= s.nibbles.x and nibbles <= s.nibbles.y, "%s: %d nibbles in range" % [s.id, nibbles])
		var last := -1.0
		for t in tells:
			_check(t["t"] > last, "%s: tells in order" % s.id)
			last = t["t"]
	# calmer fish (the fisher's hut) nibble less
	var calm := FishBite.tells(s, rng, 1.0).filter(func(t: Dictionary) -> bool: return t["kind"] == &"nibble").size()
	_check(calm <= maxi(s.nibbles.y - 2, 0), "%s: calm fish nibble less" % s.id)
