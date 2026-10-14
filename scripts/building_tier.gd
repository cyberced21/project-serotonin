class_name BuildingTier
extends Resource
## One tier of a building (see BuildingDef): what it's called, what it costs to build, and what
## its villager says while the building is at this tier.

@export var name := "Lean-to"
## Item id -> amount, paid to upgrade *to* this tier (tier 1 is there from the start: no cost).
@export var cost: Dictionary[StringName, int] = {}
## The villager picks one of these when you talk to them at this tier.
@export_multiline var lines: PackedStringArray = []
## What this tier does for the player. Empty for now: upgrades are only visual. Later systems
## read these (or listen to Village.tier_changed) to unlock things.
@export var effects: Array[Resource] = []
