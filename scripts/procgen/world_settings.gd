class_name WorldSettings
extends RefCounted
## What a generated world is made from, as a plain dictionary (it lives in the world's world.json):
##   seed       the generator's seed
##   size       &"small" 256 m, &"normal" 512 m, &"large" 1024 m (more biomes, not bigger ones)
##   kinds      biome -> kind id, for the biomes whose kind is picked (the rest roll per seed)
##   resources  &"lean" / &"normal" / &"rich": how many gatherable nodes, overall
##   water      &"dry" (only the hub pond and the lake) / &"normal" / &"wet" (more ponds, two rivers)
##   terrain    &"gentle" / &"normal" / &"rugged": how high the hills and mountains stand
## Everything on "normal" (and no kinds picked) builds exactly what the seed always built.

const SIZES: Array[StringName] = [&"small", &"normal", &"large"]
const SIZE_METRES := {&"small": 256, &"normal": 512, &"large": 1024}
const RESOURCES: Array[StringName] = [&"lean", &"normal", &"rich"]
const WATER: Array[StringName] = [&"dry", &"normal", &"wet"]
const TERRAIN: Array[StringName] = [&"gentle", &"normal", &"rugged"]
## Node counts per resources setting.
const RESOURCE_SCALE := {&"lean": 0.6, &"normal": 1.0, &"rich": 1.6}
## Biome relief per terrain setting (the rim stays as it is).
const RELIEF := {&"gentle": 0.6, &"normal": 1.0, &"rugged": 1.45}
## Extra ponds per water setting (normal is ProcgenMap.POND_COUNT).
const PONDS := {&"dry": 0, &"normal": 2, &"wet": 5}


static func defaults() -> Dictionary:
	return {"seed": 1, "size": "normal", "kinds": {}, "resources": "normal", "water": "normal", "terrain": "normal"}


## `d` with anything missing or unknown back to the defaults, numbers back to ints (JSON reads every
## number as a float) and choices as StringNames.
static func normalized(d: Dictionary) -> Dictionary:
	var out := defaults()
	out["seed"] = int(d.get("seed", out["seed"]))
	out["size"] = _pick(d.get("size"), SIZES, &"normal")
	out["resources"] = _pick(d.get("resources"), RESOURCES, &"normal")
	out["water"] = _pick(d.get("water"), WATER, &"normal")
	out["terrain"] = _pick(d.get("terrain"), TERRAIN, &"normal")
	var kinds: Dictionary = {}
	var given: Variant = d.get("kinds", {})
	if given is Dictionary:
		for biome in given:
			var b := StringName(biome)
			var k := StringName(str(given[biome]))
			for option in ProcgenMap.KINDS.get(b, []):
				if option[0] == k:
					kinds[b] = k
	out["kinds"] = kinds
	return out


## Fit for world.json: StringNames as plain strings.
static func to_json(d: Dictionary) -> Dictionary:
	var n := normalized(d)
	var kinds := {}
	for b in n["kinds"]:
		kinds[String(b)] = String(n["kinds"][b])
	return {"seed": n["seed"], "size": String(n["size"]), "kinds": kinds, "resources": String(n["resources"]),
			"water": String(n["water"]), "terrain": String(n["terrain"])}


## "Small · rich · wet · rugged · Old Growth" (only what isn't the default), or "".
static func summary(d: Dictionary) -> String:
	var n := normalized(d)
	var parts := PackedStringArray()
	if n["size"] != &"normal":
		parts.append(String(n["size"]).capitalize())
	for key in ["resources", "water", "terrain"]:
		if n[key] != &"normal":
			parts.append(String(n[key]))
	for b in n["kinds"]:
		for option in ProcgenMap.KINDS[b]:
			if option[0] == n["kinds"][b]:
				parts.append(option[1])
	return " · ".join(parts)


static func _pick(v: Variant, options: Array[StringName], fallback: StringName) -> StringName:
	var s := StringName(str(v)) if v != null else fallback
	return s if options.has(s) else fallback
