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

@export_group("River")
## Holds station in the current (grayling): each fish keeps its own spot, facing upstream into
## WaterBody.flow, instead of schooling. It only notices a lure in front of it (drifting down).
@export var holds_station := false

@export_group("Rod")
## How far from the float a calm fish notices it (m), and the chance per second that it does.
@export var notice_radius := 2.5
@export var notice_rate := 0.35
## How fast it swims over to the float (m/s).
@export var approach_speed := 0.4
## Fake-out nibbles before the take (min, max), and the pause between them (s, min max).
@export var nibbles := Vector2i(2, 4)
@export var nibble_gap := Vector2(0.5, 1.2)
## The two quick twitches right before the take.
@export var tap_tap := true
## Seconds to strike (yank it out) once the float dunks under, before the fish spits the hook.
@export var strike_window := 0.25
## Pike: no nibbles and no tap-tap; it sits under the float for a while, then slams it.
@export var ambush := false

@export_group("Size")
## Weight range (kg): each catch rolls one. Bigger give more XP (up to +50%).
@export var weight := Vector2(0.1, 0.4)
