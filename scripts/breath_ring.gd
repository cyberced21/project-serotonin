class_name BreathRing
extends Control
## Your breath under water (plans/water.md): a thin ring round the crosshair that empties as it runs
## down, a soft blue going pale as it gets low. It shows only while your head's under or your
## breath is coming back, and fades out once it's full.

const RADIUS := 15.0
const WIDTH := 2.5
const FULL_COLOR := Color(0.78, 0.9, 1.0)
const LOW_COLOR := Color(1.0, 0.82, 0.72)
## Breath left (0..1) below which it starts going pale.
const LOW := 0.3

var player: Node
var _shown := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_CENTER)


func _process(delta: float) -> void:
	var breath := float(player.get("breath"))
	var want := 1.0 if player.get("head_under") or breath < 1.0 else 0.0
	_shown = move_toward(_shown, want, delta * (4.0 if want > 0.0 else 1.5))
	queue_redraw()


func _draw() -> void:
	if _shown <= 0.0:
		return
	var breath := float(player.get("breath"))
	var color := LOW_COLOR.lerp(FULL_COLOR, clampf(breath / LOW, 0.0, 1.0))
	draw_arc(Vector2.ZERO, RADIUS, 0.0, TAU, 48, Color(0, 0, 0, 0.25 * _shown), WIDTH + 2.0, true)
	if breath > 0.0:  # (from the top, emptying anticlockwise)
		draw_arc(Vector2.ZERO, RADIUS, -PI / 2.0, -PI / 2.0 + TAU * breath, 48, Color(color, 0.85 * _shown), WIDTH, true)
