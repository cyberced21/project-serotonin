extends Node
## The gathering tools you own: tool type -> tier (0 = the stone tool you start with). A node's
## `tool_tier` says which tier bites it; below that, hits bounce off (ResourceNode.can_gather).
## Each tool is forged from what the tier below could gather (plans/tool-progression.md).

signal changed(tool: StringName, tier: int)

## Tool type -> its tiers' names, lowest first. The fishing spear and rod have no tiers.
const LADDER := {
	&"pickaxe": ["Stone pick", "Copper pick", "Iron pick", "Crystal pick"],
	&"axe": ["Stone axe", "Copper axe", "Iron axe", "Crystal axe"],
	&"sickle": ["Stone sickle", "Copper sickle"],
}

var tiers: Dictionary[StringName, int] = {}


func _ready() -> void:
	SaveGame.register(&"tools", self)


func tier(tool: StringName) -> int:
	return tiers.get(tool, 0)


func max_tier(tool: StringName) -> int:
	return LADDER[tool].size() - 1 if LADDER.has(tool) else 0


## True if the tool you own of this type bites a node of tier `needed`. Untiered tools always do.
func can_work(tool: StringName, needed: int) -> bool:
	return not LADDER.has(tool) or tier(tool) >= needed


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


func to_dict() -> Dictionary:
	return tiers.duplicate()


func from_dict(d: Dictionary) -> void:
	tiers.clear()
	for key in d:
		tiers[StringName(key)] = int(d[key])  # JSON stores numbers as floats
