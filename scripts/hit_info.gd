class_name HitInfo
extends RefCounted
## Where and how a swing landed — passed to ResourceNode.hit().
## Carries the exact point / surface normal / collider (not just "which node"), so nodes can
## later react to *where* they were struck (weak points, sweet spots).

var position: Vector3
var normal: Vector3
var collider: Object
## Where the swing came from (the player's eye).
var from: Vector3
## A fully charged swing (the Power swing talent).
var power := false


func _init(p_position: Vector3, p_normal: Vector3, p_collider: Object, p_from: Vector3) -> void:
	position = p_position
	normal = p_normal
	collider = p_collider
	from = p_from


## Horizontal direction from the swinger towards the hit point.
func away() -> Vector3:
	var d := position - from
	d.y = 0.0
	return d.normalized() if d.length_squared() > 0.0001 else Vector3.FORWARD
