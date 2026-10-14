extends Node
## The village's progress: which tier every building is at. Buildings in the world are views of
## this — they register their BuildingDef here, read their tier on load and animate when
## tier_changed fires. Later mechanics (upgrade effects) hook into tier_changed too.
## Rule: no house may be upgraded past the town hall's tier; the town hall is capped only by
## its own number of tiers.
## Saved by building id (BuildingDef.id), not by scene path, so moving buildings is safe.

signal tier_changed(id: StringName, tier: int)

const TOWN_HALL := &"town_hall"
## Debug (F7): how many of every item to hand out.
const DEBUG_ITEMS := 50

var _tiers: Dictionary[StringName, int] = {}
var _defs: Dictionary[StringName, BuildingDef] = {}


func _ready() -> void:
	SaveGame.register(&"village", self)


func register_building(def: BuildingDef) -> void:
	_defs[def.id] = def


func get_def(id: StringName) -> BuildingDef:
	return _defs.get(id)


## 1-based; every building starts at tier 1.
func tier(id: StringName) -> int:
	return _tiers.get(id, 1)


## The tier above the current one, or null at the top.
func next_tier(id: StringName) -> BuildingTier:
	var def := get_def(id)
	return def.get_tier(tier(id) + 1) if def else null


## True when the next tier exists but the town hall isn't high enough for it yet.
func is_capped(id: StringName) -> bool:
	return id != TOWN_HALL and next_tier(id) != null and tier(id) + 1 > tier(TOWN_HALL)


## The total of a perk (see TierEffect) over every building's current tier.
func stat(name: StringName) -> float:
	var total := 0.0
	for id in _defs:
		var t := _defs[id].get_tier(tier(id))
		if t:
			for e in t.effects:
				if e.stat == name:
					total += e.value
	return total


func can_upgrade(id: StringName) -> bool:
	var next := next_tier(id)
	return next != null and not is_capped(id) and Inventory.has_all(next.cost)


## Pays for and builds the next tier. False (and nothing spent) if it isn't allowed or affordable.
func upgrade(id: StringName) -> bool:
	if not can_upgrade(id) or not Inventory.spend(next_tier(id).cost):
		return false
	_set_tier(id, tier(id) + 1)
	SaveGame.save()  # progress worth keeping right away
	return true


func _set_tier(id: StringName, t: int) -> void:
	_tiers[id] = t
	SaveGame.mark_dirty()
	tier_changed.emit(id, t)


func to_dict() -> Dictionary:
	return _tiers.duplicate()


func from_dict(d: Dictionary) -> void:
	_tiers.clear()
	for key in d:
		_tiers[StringName(key)] = maxi(int(d[key]), 1)  # JSON stores numbers as floats


func _unhandled_input(event: InputEvent) -> void:
	if not OS.is_debug_build():
		return
	if event.is_action_pressed("debug_give_items"):
		for item in Items.DEFS:
			Inventory.add(item, DEBUG_ITEMS)
	elif event.is_action_pressed("debug_village_tier"):
		_debug_cycle_tiers()


## Debug (F8): every building up one tier for free (town hall first, so the cap allows it);
## once everything is at the top, back down to tier 1.
func _debug_cycle_tiers() -> void:
	var all_maxed := true
	for id in _defs:
		if tier(id) < _defs[id].max_tier():
			all_maxed = false
	var hall := get_def(TOWN_HALL)
	if all_maxed:
		for id in _defs:
			_set_tier(id, 1)
		return
	if hall and tier(TOWN_HALL) < hall.max_tier():
		_set_tier(TOWN_HALL, tier(TOWN_HALL) + 1)
	for id in _defs:
		if id != TOWN_HALL and tier(id) < mini(_defs[id].max_tier(), tier(TOWN_HALL)):
			_set_tier(id, tier(id) + 1)
