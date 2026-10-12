class_name WaterRipple
extends MeshInstance3D
## An expanding, fading ring on the water surface. Spawn with WaterRipple.spawn(parent, pos, size).

const SHADER := preload("res://shaders/water_ripple.gdshader")


## `pos` should be on the water surface; `size` is the final ring diameter (m).
static func spawn(parent: Node, pos: Vector3, size := 1.2, duration := 0.9) -> void:
	var r := WaterRipple.new()
	var quad := PlaneMesh.new()
	quad.size = Vector2.ONE * size
	r.mesh = quad
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	r.material_override = mat
	r.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(r)
	r.global_position = pos + Vector3.UP * 0.02  # just above the surface, no z-fighting
	var t := r.create_tween()
	t.tween_method(func(p: float) -> void: mat.set_shader_parameter("progress", p), 0.0, 1.0, duration) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_callback(r.queue_free)
