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

## True if every item in `cost` (item id -> amount) is held in that amount.
func has_all(cost: Dictionary) -> bool:
	for item in cost:
		if count(item) < int(cost[item]):
			return false
	return true

## Removes everything in `cost` (item id -> amount), or nothing at all if anything is short.
func spend(cost: Dictionary) -> bool:
	if not has_all(cost):
		return false
	for item in cost:
		var amount := int(cost[item])
		if amount <= 0:
			continue
		items[item] = count(item) - amount
		changed.emit(item, items[item])
	SaveGame.mark_dirty()
	return true

func to_dict() -> Dictionary:
	return items.duplicate()

func from_dict(d: Dictionary) -> void:
	items.clear()
	for key in d:
		items[StringName(key)] = int(d[key])  # JSON stores numbers as floats
