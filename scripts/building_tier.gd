class_name BuildingTier
extends Resource
## One tier of a building (see BuildingDef): what it's called, what it costs to build, and what
## its villager says while the building is at this tier.

@export var name := "Lean-to"
## Item id -> amount, paid to upgrade *to* this tier (tier 1 is there from the start: no cost).
@export var cost: Dictionary[StringName, int] = {}
## Town hall tier needed before this tier can be built. 0 = this tier's own number (the usual
## rule: no house above the hall). The smithy's crystal tier sets 3, so it needs no fourth hall.
@export_range(0, 9) var hall_tier := 0
## The villager picks one of these when you talk to them at this tier.
@export_multiline var lines: PackedStringArray = []
## What this tier does for the player while the building is at it (not on top of lower tiers:
## list the full perk). Summed across buildings by Village.stat().
@export var effects: Array[TierEffect] = []
