class_name AddonDef
extends Resource
## An add-on for a building (plans/home.md): an optional piece bolted on, separate from its tier.
## A building's slots open with its tiers (BuildingDef.addon_slots); each slot is a fork of two
## add-ons, you build one, and you can swap to the other later for its cost. Built ones are
## saved by Village; their effects add up with the tiers' (Village.stat). The model's pieces for
## it are named "AO-<id>_..." (tools/blender/kit_buildings.py) and shown by Building.

## Stable save key (no underscores: the model's piece names are split on the first one).
@export var id: StringName = &""
## Which slot it goes in (1 or 2).
@export var slot := 1
@export var name := ""
## A line about it for the upgrade panel.
@export var blurb := ""
@export var cost: Dictionary[StringName, int] = {}
@export var effects: Array[TierEffect] = []
