class_name FishBite
extends RefCounted
## The tell rhythm a fish plays under the float, as pure logic (FishingLure plays it out).

const TAP_GAP := 0.14
const TAKE_AFTER_TAPS := Vector2(0.3, 0.36)


## How much wider the strike window is for your level against the fish's: +10% per 10 levels
## above. Below its level the window stays as it is: catch_chance is the penalty there.
static func window_scale(level: int, required: int) -> float:
	return 1.0 + 0.1 * floorf(maxi(level - required, 0) / 10.0)


## The chance a fish you've got (speared, or pulled on time) is really yours: certain at or
## above its level, 10% less per level under, never below 10%. The same for both tools: under,
## the spear's fish dodges and the rod's hook slips.
static func catch_chance(level: int, required: int) -> float:
	return maxf(1.0 - 0.1 * maxi(required - level, 0), 0.1)


## [{t (s after it arrives under the float), kind}], ending on the take: nibbles (fake-outs), the
## tap-tap (it's about to commit), then the take. Ambushers (pike) sit still a long while, then
## take with no warning. `calm` (0..1, the fisher's hut) takes nibbles off.
static func tells(s: FishSpecies, rng: RandomNumberGenerator, calm: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var t := rng.randf_range(0.3, 0.8)
	if s.ambush:
		out.append({"t": t + rng.randf_range(1.5, 3.5), "kind": &"take"})
		return out
	var n := maxi(rng.randi_range(s.nibbles.x, s.nibbles.y) - roundi(calm * 2.0), 0)
	for i in n:
		out.append({"t": t, "kind": &"nibble"})
		t += rng.randf_range(s.nibble_gap.x, s.nibble_gap.y)
	if s.tap_tap:
		out.append({"t": t, "kind": &"tap"})
		t += TAP_GAP
		out.append({"t": t, "kind": &"tap"})
		t += rng.randf_range(TAKE_AFTER_TAPS.x, TAKE_AFTER_TAPS.y)  # tap-tap... take: a beat you can learn
	out.append({"t": t, "kind": &"take"})
	return out
