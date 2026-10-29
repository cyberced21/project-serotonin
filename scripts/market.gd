class_name Market
extends RefCounted
## The market's barter rates (plans/market.md): no money, goods for goods. Every good has a worth
## (VALUES, in "logs"); getting one of something costs enough of what you give to be worth RATE
## times as much (a lossy swap, so gathering stays the main way), within the same family (logs,
## ore, crops, fish), ACROSS times across families. The trader's days are kinder (TRADER_RATE).

## What one of each good is worth.
const VALUES := {
	&"wood": 1.0, &"birch": 1.5, &"pine": 2.0, &"oak": 2.5,
	&"ore": 1.0, &"coal": 1.5, &"iron": 2.5, &"gold": 5.0, &"crystal": 8.0,
	&"wheat": 1.0, &"barley": 1.5,
	&"perch": 1.0, &"trout": 1.5, &"pike": 2.5, &"char": 3.0, &"grayling": 3.0, &"salmon": 4.0,
}
const FAMILIES := {
	&"logs": [&"wood", &"birch", &"pine", &"oak"],
	&"ore": [&"ore", &"coal", &"iron", &"gold", &"crystal"],
	&"crops": [&"wheat", &"barley"],
	&"fish": [&"perch", &"trout", &"pike", &"char", &"grayling", &"salmon"],
}
const RATE := 3.0
const ACROSS := 1.5
const TRADER_RATE := 2.0


static func family(item: StringName) -> StringName:
	for f in FAMILIES:
		if (FAMILIES[f] as Array).has(item):
			return f
	return &""


static func tradeable(item: StringName) -> bool:
	return VALUES.has(item)


## How many of `give` buy one `get` (never fewer than 1; 0 if they can't be swapped).
static func price(give: StringName, get_item: StringName, trader_in := false) -> int:
	if give == get_item or not VALUES.has(give) or not VALUES.has(get_item):
		return 0
	var rate := TRADER_RATE if trader_in else RATE
	if family(give) != family(get_item):
		rate *= ACROSS
	return maxi(1, ceili(rate * float(VALUES[get_item]) / float(VALUES[give]) - 0.001))


## Gives `price` of `give` for one `get`. False (nothing changes) if you're short.
static func trade(give: StringName, get_item: StringName, trader_in := false) -> bool:
	var n := price(give, get_item, trader_in)
	if n <= 0 or not Inventory.spend({give: n}):
		return false
	Inventory.add(get_item, 1)
	SaveGame.mark_dirty()
	return true
