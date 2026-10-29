extends Node
## The village's progress: which tier every building is at. Buildings in the world are views of
## this — they register their BuildingDef here, read their tier on load and animate when
## tier_changed fires. Later mechanics (upgrade effects) hook into tier_changed too.
## Rule: no house may be upgraded past the town hall's tier (unless the tier says otherwise, see
## BuildingTier.hall_tier); the town hall is capped only by its own number of tiers.
## Saved by building id (BuildingDef.id), not by scene path, so moving buildings is safe.

signal tier_changed(id: StringName, tier: int)
## An add-on was built (or swapped) in a slot (plans/home.md, AddonDef); `addon` is &"" if cleared.
signal addon_changed(id: StringName, slot: int, addon: StringName)

const TOWN_HALL := &"town_hall"
## Debug (F7): how many of every item to hand out.
const DEBUG_ITEMS := 50

var _tiers: Dictionary[StringName, int] = {}
## Built add-ons: building id -> {slot -> add-on id} (saved under "addons", beside the tiers).
var _addons: Dictionary[StringName, Dictionary] = {}
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
	var next := next_tier(id)
	if id == TOWN_HALL or next == null:
		return false
	return (next.hall_tier if next.hall_tier > 0 else tier(id) + 1) > tier(TOWN_HALL)


## The total of a perk (see TierEffect) over every building's current tier.
func stat(name: StringName) -> float:
	var total := 0.0
	for id in _defs:
		var t := _defs[id].get_tier(tier(id))
		if t:
			for e in t.effects:
				if e.stat == name:
					total += e.value
		for slot in _addons.get(id, {}):
			var a := _defs[id].get_addon(_addons[id][slot])
			if a and slot_open(id, int(slot)):
				for e in a.effects:
					if e.stat == name:
						total += e.value
	return total


# --- add-ons (plans/home.md) -----------------------------------------------------------------

## The add-on built in a building's slot, or &"".
func addon(id: StringName, slot: int) -> StringName:
	return StringName(_addons.get(id, {}).get(slot, &""))


## Whether a building's slot is open yet (its tier has reached the one the slot opens at).
func slot_open(id: StringName, slot: int) -> bool:
	var def: BuildingDef = _defs.get(id)
	if def == null or slot < 1 or slot > def.addon_slots.size():
		return false
	return tier(id) >= def.addon_slots[slot - 1]


## Whether `addon` can be built (or swapped to) now: its slot's open, it isn't already there, and
## you can pay for it.
func can_build_addon(id: StringName, addon_id: StringName) -> bool:
	var def: BuildingDef = _defs.get(id)
	var a := def.get_addon(addon_id) if def else null
	return a != null and slot_open(id, a.slot) and addon(id, a.slot) != addon_id and Inventory.has_all(a.cost)


## Pays for and builds `addon` in its slot (the other one there comes down). False if not allowed.
func build_addon(id: StringName, addon_id: StringName) -> bool:
	if not can_build_addon(id, addon_id) or not Inventory.spend(_defs[id].get_addon(addon_id).cost):
		return false
	set_addon(id, addon_id)
	return true


## Puts `addon` in its slot for free (debug, tests), or clears `slot` with &"".
func set_addon(id: StringName, addon_id: StringName, slot := 0) -> void:
	var def: BuildingDef = _defs.get(id)
	var a := def.get_addon(addon_id) if def else null
	var s := a.slot if a else slot
	if not _addons.has(id):
		_addons[id] = {}
	if addon_id == &"":
		_addons[id].erase(s)
	else:
		_addons[id][s] = addon_id
	SaveGame.mark_dirty()
	addon_changed.emit(id, s, addon_id)


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


## Debug: put a building at tier `t` for free, ignoring the town hall's cap.
func set_tier(id: StringName, t: int) -> void:
	var def := get_def(id)
	if def and t != tier(id):
		_set_tier(id, clampi(t, 1, def.max_tier()))


## Every registered building id, town hall first.
func building_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	ids.assign(_defs.keys())
	ids.sort_custom(func(a: StringName, b: StringName) -> bool: return a == TOWN_HALL or (b != TOWN_HALL and a < b))
	return ids


func _set_tier(id: StringName, t: int) -> void:
	_tiers[id] = t
	SaveGame.mark_dirty()
	tier_changed.emit(id, t)


func to_dict() -> Dictionary:
	var d := {}  # (untyped: the tiers by id, and the add-ons beside them)
	for id in _tiers:
		d[id] = _tiers[id]
	var built := {}
	for id in _addons:
		built[String(id)] = {}
		for slot in _addons[id]:
			built[String(id)][str(slot)] = String(_addons[id][slot])
	d["addons"] = built  # (no building has that id)
	return d


func from_dict(d: Dictionary) -> void:
	_tiers.clear()
	_addons.clear()
	for key in d:
		if key == "addons":
			for id in d[key]:
				_addons[StringName(id)] = {}
				for slot in d[key][id]:
					_addons[StringName(id)][int(slot)] = StringName(d[key][id][slot])
		else:
			_tiers[StringName(key)] = maxi(int(d[key]), 1)  # JSON stores numbers as floats


func _unhandled_input(event: InputEvent) -> void:
	if not (OS.is_debug_build() or OS.has_feature("playtest")):
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
		if id != TOWN_HALL and next_tier(id) != null and not is_capped(id):
			_set_tier(id, tier(id) + 1)
