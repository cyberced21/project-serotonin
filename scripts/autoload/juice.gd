extends Node
## Global "game feel" helper: camera shake. Kept light (plans/calm-feel.md): no hit-stop freezes.


## Shakes every camera in the "camera" group.
func shake(amount: float) -> void:
	get_tree().call_group("camera", "shake", amount)
