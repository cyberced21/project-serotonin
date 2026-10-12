class_name FishSpecies
extends Resource
## One kind of fish: what it gives, who can catch it, and how it behaves.
## Instances live in data/fish/*.tres; ponds list which species they hold.

@export var id: StringName = &"perch"  ## item id given when caught (see Items)
@export var model: PackedScene
@export_range(1, 50) var required_level := 1
@export_range(0, 500) var xp := 10

@export_group("School")
@export_range(1, 20) var school_min := 6
@export_range(1, 20) var school_max := 8
## How tightly the school keeps together (metres between neighbours it aims for).
@export var spacing := 0.35
## Solitary lurkers (pike) sit still near cover instead of cruising.
@export var lurker := false

@export_group("Movement")
@export var cruise_speed := 0.35
@export var flee_speed := 3.0
## How fast it can turn (radians per second) while cruising.
@export var turn_rate := 2.5

@export_group("Wariness")
## Disturbances within this distance alert the fish.
@export var scare_radius := 2.5
## Seconds after a scare before it settles back to calm.
@export var calm_down := 3.0
## 0..1: how much noise it takes to spook it (1 = only a strike right next to it).
@export_range(0.0, 1.0) var nerve := 0.5
