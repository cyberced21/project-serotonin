class_name BuildingDef
extends Resource
## An upgradable village building and the villager who lives there.
## Instances live in data/buildings/*.tres; a Building in the world points at one.
## The model (.glb) holds every tier's pieces, named T1_*, T2_*, T3_* (see tools/blender/).

## Stable save key — don't change it once players have saves.
@export var id: StringName = &"woodcutter"
@export var display_name := "Woodcutter's Lodge"
@export var model: PackedScene
## Tier 1 first. Every building starts at tier 1.
@export var tiers: Array[BuildingTier] = []

@export_group("Villager")
@export var villager_name := "Bram"
@export var villager_role := "Woodcutter"
## Said when the next upgrade is held back by the town hall's tier.
@export_multiline var capped_line := "The mayor hasn't let us build any bigger yet."
## Said when you knock at night (the villager steps out of the door to talk).
## (A PackedStringArray(...) default, not a bare [...]: in the editor, where this script isn't
## @tool, a bare array default makes the stand-in object drop the saved lines on load, and the
## next save from the editor writes the file back without them.)
@export_multiline var night_lines := PackedStringArray([
	"You're up late! Well, the lamps are lit. What can I do for you?",
	"Couldn't sleep either? Come in out of the dark a moment.",
])


func max_tier() -> int:
	return tiers.size()


## The tier resource for `tier` (1-based), or null.
func get_tier(tier: int) -> BuildingTier:
	return tiers[tier - 1] if tier >= 1 and tier <= tiers.size() else null
