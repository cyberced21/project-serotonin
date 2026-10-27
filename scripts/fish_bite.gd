class_name FishBite
extends RefCounted
## The tell rhythm a fish plays under the float, as pure logic (FishingLure plays it out).

const TAP_GAP := 0.14
const TAKE_AFTER_TAPS := Vector2(0.3, 0.36)


## How much wider (or tighter) the strike window is for your level against the fish's: +10% per
## 10 levels above, shrinking sharply below (5 under: about 0.72; 15 or more under: 0.2).
static func window_scale(level: int, required: int) -> float:
	var gap := level - required
	if gap >= 0:
		return 1.0 + 0.1 * floorf(gap / 10.0)
	return clampf(1.0 + 0.055 * gap, 0.2, 1.0)


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
