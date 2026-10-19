class_name WorldSettings
extends RefCounted
## What a generated world is made from, as a plain dictionary (it lives in the world's world.json):
##   seed      the generator's seed


static func defaults() -> Dictionary:
	return {"seed": 1}


## `d` with anything missing filled in from the defaults, and numbers back to ints (JSON reads
## every number as a float).
static func normalized(d: Dictionary) -> Dictionary:
	var out := defaults()
	out.merge(d, true)
	out["seed"] = int(out["seed"])
	return out
