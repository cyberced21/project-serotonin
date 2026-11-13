class_name GrainOverlay
extends CanvasLayer
## The grainy look over the 3D view (shaders/grain.gdshader, "soft chunky": 2×2 blocks, colour
## steps with a dot pattern between them, a little still grain in the shadows). Sits in the player
## scene after the Viewmodel (same layer, drawn after it, so the tool in hand gets it too) and
## under the HUD and menus. Settings → Display → "Grainy look" turns it off.

const LOOK := {
	&"pixel_size": 2.0, &"levels": 24.0, &"dither": 1.0, &"grain": 0.03, &"shadow_weight": 0.5,
}

var _rect: ColorRect


func _ready() -> void:
	layer = -1
	_rect = ColorRect.new()
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/grain.gdshader")
	for key in LOOK:
		mat.set_shader_parameter(key, LOOK[key])
	_rect.material = mat
	add_child(_rect)
	Settings.changed.connect(_refresh)
	_refresh()


func _refresh() -> void:
	visible = bool(Settings.get_value("display", "grain"))
