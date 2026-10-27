class_name FishSize
extends RefCounted
## A fish's size, as pure logic: rolled once when it spawns (Fish.size, 0..1, big ones rare),
## then it sets how big the fish is drawn and how many it counts for when caught.

## Sizes past these count as more than one fish: Big x2, Huge x3. With sizes rolled as
## randf()^SKEW, about 12% are Big and 4% Huge.
const BIG := 0.75
const HUGE := 0.93
const SKEW := 1.6


## A size from a uniform 0..1 roll: skewed small, so big ones are rare.
static func roll(r: float) -> float:
	return pow(r, SKEW)


## How much bigger than the model it's drawn.
static func scale_for(s: float) -> float:
	return lerpf(0.8, 1.35, s)


## How many fish it counts for in the inventory: 1, Big 2, Huge 3.
static func count_for(s: float) -> int:
	return 3 if s >= HUGE else (2 if s >= BIG else 1)


## "Big!" / "Huge!", or "".
static func word(s: float) -> String:
	return "Huge!" if s >= HUGE else ("Big!" if s >= BIG else "")
