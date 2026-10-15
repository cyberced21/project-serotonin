class_name SpawnEntry
extends Resource
## One kind of node a NodeSpawner places, and how often.

## A ResourceNode scene (scenes/pine_tree.tscn, scenes/rock.tscn...).
@export var scene: PackedScene
## Relative chance, in the middle of the spawner's ellipse (or everywhere, if it has none).
@export var weight := 1.0
## Relative chance at the ellipse's rim; in between it slides from `weight`. Negative = same as
## `weight`.
@export var edge_weight := -1.0
