class_name SeatPrompt
extends Node
## What E sits you down on (plans/tavern.md): a free seat under the crosshair (a bench, a stool on
## the terrace or in the tavern, the dice table's). Seats are markers with nothing to hit, so the
## player finds one (Player._seat_under_crosshair) and puts it here; this stands in for it as the
## thing E talks to (prompt / interact / set_highlighted, like a villager).

var seat: Marker3D


func prompt() -> String:
	if seat and seat.is_in_group("dice_seat"):
		return "E  Sit down at the dice table"
	return "E  Sit down"


func interact() -> void:
	var player := get_parent()
	if seat and player.has_method("sit"):
		player.sit(seat)


func set_highlighted(_on: bool) -> void:
	pass
