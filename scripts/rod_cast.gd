class_name RodCast
extends RefCounted
## Judges a cast: how far the release was from the forward stroke's sweet spot decides where the
## float lands and how loudly. Pure logic (RodFishing plays it out), so it can be tested headless.
##   perfect  within PERFECT_WINDOW: on the aim point, a soft plip that scares nothing
##   good     within GOOD_WINDOW: a little off, a plop that spooks fish close by
##   bad      past it: off by up to MAX_SCATTER metres, a splosh that spooks everything near

enum Quality { PERFECT, GOOD, BAD }

const PERFECT_WINDOW := 0.05
const GOOD_WINDOW := 0.12
## Error (s) at which the scatter tops out.
const WORST := 0.3
const MAX_SCATTER := 3.5
## FishPond.disturb loudness for each quality (crouch step 0.15 .. sprint 1 .. strike 2).
const LOUDNESS := {Quality.PERFECT: 0.08, Quality.GOOD: 0.6, Quality.BAD: 1.6}


## `error`: release time minus the sweet spot (s; negative = early). `window_scale` widens the
## windows (Fishing level). Returns {quality, scatter (m off the aim point), loudness, early}.
static func judge(error: float, window_scale := 1.0) -> Dictionary:
	var e := absf(error)
	var quality := Quality.BAD
	if e <= PERFECT_WINDOW * window_scale:
		quality = Quality.PERFECT
	elif e <= GOOD_WINDOW * window_scale:
		quality = Quality.GOOD
	var scatter := 0.0
	if quality != Quality.PERFECT:
		scatter = MAX_SCATTER * clampf((e - PERFECT_WINDOW * window_scale) / (WORST - PERFECT_WINDOW * window_scale), 0.0, 1.0)
	return {"quality": quality, "scatter": scatter, "loudness": LOUDNESS[quality], "early": error < 0.0}


## Where the float lands: the aim point, pushed off by the scatter. Early releases fly long and
## high (beyond the aim), late ones slap down short; both drift sideways a little.
static func landing(from: Vector3, aim: Vector3, verdict: Dictionary, rng: RandomNumberGenerator) -> Vector3:
	var scatter: float = verdict["scatter"]
	if scatter <= 0.0:
		return aim
	var flat := Vector3(aim.x - from.x, 0.0, aim.z - from.z)
	var along := flat.normalized() if flat.length_squared() > 0.0001 else Vector3.FORWARD
	var side := along.cross(Vector3.UP)
	var push := along * scatter * (0.8 if verdict["early"] else -0.8) + side * scatter * rng.randf_range(-0.6, 0.6)
	return aim + push
