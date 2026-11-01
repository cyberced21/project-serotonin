class_name River
extends Creek
## A river drawn in the map editor (plans/terrain-editing.md): the layout bake puts one under
## Layout/Water for each of the layout's rivers. Its water is built like the creek's (a surface
## along its bends, a WaterBody every few metres carrying the current, grayling in some stretches,
## a bridge where a road crosses), along `points` smoothed as the terrain generator carved it.
## Where it runs into a pond, the lake or the creek, their water takes over.

## Its points, as drawn (from its source down).
@export var points := PackedVector2Array()
@export var width := 4.0
@export var has_fish := true


func _ready() -> void:
	add_to_group("river")
	half_width = maxf(width * 0.5, 0.5)
	fish = has_fish
	if points.size() >= 2:
		_build(WorldMap.spline(Array(points), false))


func _pools() -> Array[Vector2]:
	return []


## In a pond or the lake, or in the creek's channel (its surface is already there).
func _covered(p: Vector2) -> bool:
	if in_other_water(p):
		return true
	var creek := WorldMap.creek()
	for k in range(0, creek.size(), 2):
		if creek[k].distance_squared_to(p) < WorldMap.CREEK_HALF_WIDTH * WorldMap.CREEK_HALF_WIDTH:
			return true
	return false
