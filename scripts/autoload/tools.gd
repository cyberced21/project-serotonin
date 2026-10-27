extends Node
## The gathering tools you own: tool type -> tier (0 = the stone tool you start with). A node's
## `tool_tier` says which tier bites it; below that, hits bounce off (ResourceNode.can_gather).
## Each tool is forged from what the tier below could gather (plans/tool-progression.md).

signal changed(tool: StringName, tier: int)

## Tool type -> its tiers' names, lowest first. The spear and the rod climb together: each tier
## opens the same fish for both (FishSpecies.tool_tier), so neither way of fishing gets one first.
const LADDER := {
	&"pickaxe": ["Stone pick", "Copper pick", "Iron pick", "Crystal pick"],
	&"axe": ["Stone axe", "Copper axe", "Iron axe", "Crystal axe"],
	&"sickle": ["Stone sickle", "Copper sickle"],
	&"spear": ["Sharpened stick", "Copper spear", "Iron spear", "Crystal spear"],
	&"rod": ["Willow pole", "Copper-reel rod", "Iron-reel rod", "Crystal rod"],
}
## What Greta needs to forge each tier above the first (index = tier - 1), and what it opens.
## Each is made from what the tier below can gather. Tier t needs the smithy at tier t + 1.
const RECIPES := {
	&"pickaxe": [
		{"cost": {&"ore": 15, &"wood": 10}, "opens": "Opens iron and coal"},
		{"cost": {&"iron": 15, &"coal": 10, &"oak": 10}, "opens": "Opens gold and crystal"},
		{"cost": {&"crystal": 8, &"gold": 8, &"pine": 10}, "opens": "The finest pick: hits hardest"},
	],
	&"axe": [
		{"cost": {&"ore": 12, &"birch": 10}, "opens": "Opens oak"},
		{"cost": {&"iron": 12, &"coal": 8}, "opens": "Opens pine"},
		{"cost": {&"crystal": 6, &"gold": 6, &"pine": 12}, "opens": "The finest axe: hits hardest"},
	],
	&"sickle": [
		{"cost": {&"ore": 8, &"wood": 8}, "opens": "Opens barley"},
	],
	# the fishing tools also take a few of the fish the tier below can catch
	&"spear": [
		{"cost": {&"ore": 8, &"wood": 8, &"perch": 6}, "opens": "Opens trout and grayling"},
		{"cost": {&"iron": 10, &"coal": 6, &"oak": 8, &"trout": 6}, "opens": "Opens pike and char"},
		{"cost": {&"crystal": 6, &"gold": 6, &"oak": 10, &"pike": 3}, "opens": "Opens salmon: the finest spear"},
	],
	&"rod": [
		{"cost": {&"ore": 8, &"birch": 8, &"perch": 6}, "opens": "Opens trout and grayling"},
		{"cost": {&"iron": 10, &"coal": 6, &"birch": 10, &"trout": 6}, "opens": "Opens pike and char"},
		{"cost": {&"crystal": 6, &"gold": 6, &"pine": 10, &"pike": 3}, "opens": "Opens salmon: the finest rod"},
	],
}
## The building whose tier caps the tools Greta can forge.
const SMITHY := &"smithy"

var tiers: Dictionary[StringName, int] = {}
## How you fish: &"spear" or &"rod" (Q swaps). Either takes any water it can reach.
var fishing_style := &"spear"
## Tools just forged whose first biting hit hasn't landed yet (it gets an oversized impact).
## Not saved: the moment is right after the forge.
var fresh: Dictionary[StringName, bool] = {}


func _ready() -> void:
	SaveGame.register(&"tools", self)


func tier(tool: StringName) -> int:
	return tiers.get(tool, 0)


func max_tier(tool: StringName) -> int:
	return LADDER[tool].size() - 1 if LADDER.has(tool) else 0


## True if the tool you own of this type bites a node of tier `needed`. Untiered tools always do.
func can_work(tool: StringName, needed: int) -> bool:
	return not LADDER.has(tool) or tier(tool) >= needed


## How many tiers your tool is above a node of tier `needed` (each one is +1 hit power).
func tiers_above(tool: StringName, needed: int) -> int:
	return maxi(tier(tool) - needed, 0) if LADDER.has(tool) else 0


## The next tier's recipe ({cost, opens}), or {} once the best is forged.
func next_recipe(tool: StringName) -> Dictionary:
	var t := tier(tool) + 1
	if not RECIPES.has(tool) or t > max_tier(tool):
		return {}
	return RECIPES[tool][t - 1]


## The smithy tier Greta needs to forge `tool` at tier `t`.
func smithy_needed(t: int) -> int:
	return t + 1


## The forge is hot enough for the next tier (the smithy's own tier allows it).
func forge_unlocked(tool: StringName) -> bool:
	return Village.tier(SMITHY) >= smithy_needed(tier(tool) + 1)


func can_forge(tool: StringName) -> bool:
	var r := next_recipe(tool)
	return not r.is_empty() and forge_unlocked(tool) and Inventory.has_all(r["cost"])


## Pays for and hands over the next tier of `tool`. False (and nothing spent) if it can't.
func forge(tool: StringName) -> bool:
	if not can_forge(tool) or not Inventory.spend(next_recipe(tool)["cost"]):
		return false
	set_tier(tool, tier(tool) + 1)
	fresh[tool] = true
	return true


## True once, on the first biting hit with a freshly forged `tool`.
func take_fresh(tool: StringName) -> bool:
	return fresh.erase(tool)


## "Iron pick": the name of `tool` at tier `t`.
func display_name(tool: StringName, t: int) -> String:
	if not LADDER.has(tool):
		return String(tool).capitalize()
	return LADDER[tool][clampi(t, 0, max_tier(tool))]


func set_tier(tool: StringName, t: int) -> void:
	if not LADDER.has(tool):
		return
	tiers[tool] = clampi(t, 0, max_tier(tool))
	SaveGame.mark_dirty()
	changed.emit(tool, tiers[tool])


## Q: the spear for the rod, or back.
func swap_fishing_style() -> void:
	fishing_style = &"rod" if fishing_style == &"spear" else &"spear"
	SaveGame.mark_dirty()


func to_dict() -> Dictionary:
	var d := {"fishing_style": String(fishing_style)}
	for key in tiers:
		d[key] = tiers[key]
	return d


func from_dict(d: Dictionary) -> void:
	tiers.clear()
	fishing_style = &"rod" if d.get("fishing_style", "") == "rod" else &"spear"
	for key in d:
		if key != "fishing_style":
			tiers[StringName(key)] = int(d[key])  # JSON stores numbers as floats
