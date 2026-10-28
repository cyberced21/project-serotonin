extends Node
## Which road stretches have lamps (plans/lamps.md L1), saved per world. The stretches themselves
## belong to the world: its PathLamps node lists them here and puts posts along the lit ones.
## A new world (or one saved before lamps) lights DEFAULT_LIT; chunk 5's projects will light the
## rest for a price, the debug menu's Village tab lights them for free.

signal changed

## The path between where you start and the village: the walk everyone takes, lit from day one.
const DEFAULT_LIT: Array[StringName] = [&"village_path"]

var _lit: Dictionary[StringName, bool] = {}
## The current world's stretches, in order: {id: StringName, title: String} (set by PathLamps).
var stretches: Array[Dictionary] = []


func _ready() -> void:
	from_dict({})
	SaveGame.register(&"lamps", self)


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
	return {"lit": ids}


func from_dict(d: Dictionary) -> void:
	_lit.clear()
	for id in d.get("lit", DEFAULT_LIT):
		_lit[StringName(id)] = true
	changed.emit()
