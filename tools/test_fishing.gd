extends SceneTree
## Headless checks for rod fishing's pure logic (RodCast, FishFight, FishBite.tells): no scene,
## no save is touched.
##
##     godot --headless --path . -s res://tools/test_fishing.gd
##
## Bots play whole fights at 60 fps: one that answers every move a frame after its cue must land
## every species without losing a notch; one that only holds the reel must always snap.

const SPECIES := ["perch", "trout", "pike", "char", "grayling", "salmon"]
const DT := 1.0 / 60.0

var _failures := 0
var _last_time := 0.0


func _init() -> void:
	_test_cast()
	_test_scales()
	for id in SPECIES:
		var s: FishSpecies = load("res://data/fish/%s.tres" % id)
		_test_bots(s)
		_test_tells(s)
	_test_early_bow()
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
	_check(FishFight.level_scales(30, 30) == Vector2(1, 1), "at level: no change")
	_check(is_equal_approx(FishFight.level_scales(50, 30).x, 1.2), "20 above: +20%")
	var five := FishFight.level_scales(25, 30)
	_check(five.x > 0.65 and five.x < 0.8 and five.y < 1.0, "5 under: hard but possible (%s)" % five)
	_check(FishFight.level_scales(10, 30).x <= 0.21, "20 under: near-impossible")


## Plays a fight: `answers` true = a bot reacting a frame after each cue; false = holds the reel.
func _play(s: FishSpecies, seed_: int, answers: bool, size := 0.5, scales := Vector2.ONE) -> FishFight:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_
	var fight := FishFight.new(s, 9.0, size, scales.x, scales.y, 3, rng)
	var reel := true
	var click := false
	var bow := false
	_last_time = 0.0
	for i in 60 * 240:
		var ev := fight.step(DT, reel, click, bow)
		_last_time += DT
		click = false
		bow = false
		if fight.is_over():
			break
		if not answers:
			continue
		for e in ev:
			match e["type"]:
				"telegraph":
					reel = false  # anything but a pull: let go
				"move":
					reel = e["move"] == FishFight.Move.PULL
				"jerk", "flash":
					click = true
				"splash":
					bow = true
				"landing":
					reel = false
	return fight


func _test_bots(s: FishSpecies) -> void:
	var landed := 0
	var clean := 0
	var time := 0.0
	for k in 20:
		var f := _play(s, 100 + k, true)
		landed += 1 if f.result == &"landed" else 0
		clean += 1 if f.result == &"landed" and not f.damaged else 0
		time += _last_time
	_check(landed == 20, "%s: the answering bot lands every fight (%d/20)" % [s.id, landed])
	_check(clean == 20, "%s: ...and cleanly (%d/20)" % [s.id, clean])
	var snapped := 0
	var hurt := 0
	for k in 20:
		var f := _play(s, 200 + k, false)
		snapped += 1 if f.result == &"snapped" else 0
		hurt += 1 if f.damaged else 0
	_check(hurt == 20, "%s: holding the reel through everything costs notches (%d/20)" % [s.id, hurt])
	print("  %s: a 9 m fight takes the bot %.1f s on average; the lazy bot snaps %d/20" % [s.id, time / 20.0, snapped])
	# far under level, even a frame-perfect answer to a tiny window mostly fails
	var under := 0
	for k in 20:
		var f := _play(s, 300 + k, true, 1.0, FishFight.level_scales(s.required_level - 20, s.required_level))
		under += 1 if f.damaged else 0
	print("  %s: 20 under, the bot loses notches in %d/20 fights" % [s.id, under])


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


func _test_early_bow() -> void:
	var s: FishSpecies = load("res://data/fish/salmon.tres")
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var fight := FishFight.new(s, 9.0, 0.5, 1.0, 1.0, 3, rng)
	var tested := false
	for i in 60 * 120:
		var bow := false
		if fight.move == FishFight.Move.JUMP and fight.phase == FishFight.Phase.TELEGRAPH and fight._t < 0.05:
			bow = true  # way before the splash
		var ev := fight.step(DT, false, false, bow)
		for e in ev:
			if e["type"] == "damage" and e["reason"] == "jump":
				tested = true
		if tested or fight.is_over():
			break
	_check(tested, "bowing long before the splash costs a notch")
