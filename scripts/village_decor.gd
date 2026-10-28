class_name VillageDecor
extends Node3D
## The village's projects in the world (plans/projects.md): the noticeboard in the square, and each
## decoration's props at their set spots once it's done. Spots are offsets from the middle of the
## square (`center`), turned with the village (`angle`, as a generated village is), so Hearthvale
## and every generated village share one layout. Facings are in the same village frame.

## The noticeboard: [offset, facing].
const NOTICEBOARD := [Vector2(9.0, -8.0), -0.84]
## Hearthvale's square (its village isn't turned).
const HEARTHVALE_CENTER := Vector2(100, 40)

## Middle of the square (world XZ) and how far the village is turned (radians).
var center := HEARTHVALE_CENTER
var angle := 0.0
var board: Noticeboard


func _ready() -> void:
	add_to_group("village_decor")
	board = Noticeboard.new()
	board.name = "Noticeboard"
	board.transform = frame(NOTICEBOARD[0], NOTICEBOARD[1])
	add_child(board)


## A transform at village offset `offset`, facing `facing` (village frame), on the ground below
## (a Prop with snap_to_ground settles it).
func frame(offset: Vector2, facing: float) -> Transform3D:
	var at := center + offset.rotated(angle)
	return Transform3D(Basis(Vector3.UP, facing - angle), Vector3(at.x, 0.0, at.y))
