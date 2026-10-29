extends Node
## Which road stretches have lamps (plans/lamps.md L1), saved per world. The stretches themselves
## belong to the world: its PathLamps node lists them here and puts posts along the lit ones.
## A new world (or one saved before lamps) lights DEFAULT_LIT; chunk 5's projects will light the
## rest for a price, the debug menu's Village tab lights them for free.
## Also the lantern you carry (scripts/lantern.gd): whether you have it and whether it burns. It
## lights itself at dusk and goes out at dawn; L lights or puts it out, and whether it lights at
## the next dusk follows what you last chose.

signal changed
signal lantern_changed

## The path between where you start and the village: the walk everyone takes, lit from day one.
const DEFAULT_LIT: Array[StringName] = [&"village_path"]
## The lantern lights itself when it gets this dark (DayNight.darkness()), about when the
## village's first path lamps catch, and goes out when it's this light again.
const LANTERN_DARK := 0.3
## Without a lantern yet, the elder's gift (LanternGift) starts this long before sunset (a
## fraction of the day: about a minute of golden hour), or any time through the night.
const GIFT_BEFORE_SUNSET := 0.06

var _lit: Dictionary[StringName, bool] = {}
## The current world's stretches, in order: {id: StringName, title: String, closest: float m to
## the square} (set by PathLamps).
var stretches: Array[Dictionary] = []
var has_lantern := false
var lantern_lit := false
var _lantern_at_dusk := true
var _dark := false
var _gift: Node


func _ready() -> void:
	from_dict({})
	SaveGame.register(&"lamps", self)
	_dark = DayNight.darkness() > LANTERN_DARK


func _process(_delta: float) -> void:
	_start_gift()
	var dark := DayNight.darkness() > LANTERN_DARK
	if dark == _dark:
		return
	_dark = dark
	if dark and has_lantern and _lantern_at_dusk and not lantern_lit:
		_set_lantern(true)
	elif not dark and lantern_lit:
		_set_lantern(false)


func _start_gift() -> void:
	if has_lantern or is_instance_valid(_gift):
		return
	var t := DayNight.time
	if t > DayNight.SUNRISE and t < DayNight.SUNSET - GIFT_BEFORE_SUNSET:
		return
	var player := get_tree().get_first_node_in_group("player")
	if player == null or not player.can_process():
		return
	_gift = LanternGift.new()
	_gift.name = "LanternGift"
	get_tree().current_scene.add_child(_gift)


## Hands you the lantern (the elder's gift at the first dusk), lit if it's dark.
func give_lantern() -> void:
	has_lantern = true
	_lantern_at_dusk = true
	_set_lantern(DayNight.darkness() > LANTERN_DARK)
	SaveGame.save()  # a gift worth keeping right away


## L: light it or put it out (and light it at dusk from now on, or not).
func set_lantern_lit(on: bool) -> void:
	_lantern_at_dusk = on
	_set_lantern(on)


func _set_lantern(on: bool) -> void:
	lantern_lit = on and has_lantern
	SaveGame.mark_dirty()
	lantern_changed.emit()


func is_lit(id: StringName) -> bool:
	return _lit.has(id)


func set_lit(id: StringName, on: bool) -> void:
	if on == is_lit(id):
		return
	if on:
		_lit[id] = true
	else:
		_lit.erase(id)
	SaveGame.mark_dirty()
	changed.emit()


func light_all(on: bool) -> void:
	for s in stretches:
		if on:
			_lit[s["id"]] = true
		else:
			_lit.erase(s["id"])
	SaveGame.mark_dirty()
	changed.emit()


func to_dict() -> Dictionary:
	var ids: Array[String] = []
	for id in _lit:
		ids.append(String(id))
	return {"lit": ids, "lantern": {"has": has_lantern, "lit": lantern_lit, "at_dusk": _lantern_at_dusk}}


func from_dict(d: Dictionary) -> void:
	_lit.clear()
	for id in d.get("lit", DEFAULT_LIT):
		_lit[StringName(id)] = true
	var lantern: Dictionary = d.get("lantern", {})
	has_lantern = lantern.get("has", false)
	lantern_lit = has_lantern and lantern.get("lit", false)
	_lantern_at_dusk = lantern.get("at_dusk", true)
	_dark = DayNight.darkness() > LANTERN_DARK  # (no dusk or dawn just for loading)
	changed.emit()
	lantern_changed.emit()
