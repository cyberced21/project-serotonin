extends Node
## Global "game feel" helpers: hit-stop and camera shake.

const FREEZE_SCALE := 0.02   # near-zero instead of 0 so physics stays happy

var _freeze_until_ms := 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

## Briefly freezes the game. Overlapping calls extend the freeze instead of stacking.
func hitstop(duration: float) -> void:
	_freeze_until_ms = maxi(_freeze_until_ms, Time.get_ticks_msec() + int(duration * 1000.0))
	Engine.time_scale = FREEZE_SCALE

func _process(_delta: float) -> void:
	if Engine.time_scale < 1.0 and Time.get_ticks_msec() >= _freeze_until_ms:
		Engine.time_scale = 1.0

## Shakes every camera in the "camera" group.
func shake(amount: float) -> void:
	get_tree().call_group("camera", "shake", amount)
