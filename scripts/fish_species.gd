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
## The shallowest water it swims in (m). Deep-water species (char) keep to the middle of a lake.
@export var min_depth := 0.3

@export_group("Hunting")
## A lurker that hunts: the species id it stalks (e.g. perch). Empty = doesn't hunt.
@export var hunts: StringName = &""
## Seconds it lurks between hunts (min, max).
@export var hunt_interval := Vector2(25.0, 45.0)
@export var stalk_speed := 0.45
@export var lunge_speed := 5.0
## Lunges once a prey fish is this close (m).
@export var lunge_range := 1.4
## Chance a lunge catches (and eats) the fish.
@export_range(0.0, 1.0) var catch_chance := 0.5

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
