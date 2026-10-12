extends Node
## Minimal inventory: item id -> count.

signal changed(item: StringName, count: int)

var items: Dictionary[StringName, int] = {}

func _ready() -> void:
	SaveGame.register(&"inventory", self)

func add(item: StringName, amount := 1) -> void:
	items[item] = items.get(item, 0) + amount
	SaveGame.mark_dirty()
	changed.emit(item, items[item])

func count(item: StringName) -> int:
	return items.get(item, 0)

func to_dict() -> Dictionary:
	return items.duplicate()

func from_dict(d: Dictionary) -> void:
	items.clear()
	for key in d:
		items[StringName(key)] = int(d[key])  # JSON stores numbers as floats
