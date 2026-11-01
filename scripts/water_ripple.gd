class_name WaterRipple
extends MeshInstance3D
## An expanding, fading ring on the water surface. Spawn with WaterRipple.spawn(parent, pos, size).
## Spawned on a WaterBody, it rides that water's waves (plans/water.md). WaterRipple.splash adds a
## burst of spray for something going in (a dive, a jump) or coming out.

const SHADER := preload("res://shaders/water_ripple.gdshader")

static var _drop_mesh: QuadMesh
static var _fade: Gradient

var _water: WaterBody


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
	r._water = parent as WaterBody
	parent.add_child(r)
	r.global_position = pos + Vector3.UP * 0.02  # just above the surface, no z-fighting
	r._ride()
	var t := r.create_tween()
	t.tween_method(func(p: float) -> void: mat.set_shader_parameter("progress", p), 0.0, 1.0, duration) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_callback(r.queue_free)


## Something going into (or climbing out of) `water` at `pos`: two rings, the big one slower, and
## a burst of droplets thrown up and falling back. `strength` 0..1 (a step out .. a running jump).
static func splash(water: WaterBody, pos: Vector3, strength := 0.6) -> void:
	strength = clampf(strength, 0.1, 1.0)
	var at := Vector3(pos.x, water.surface_height, pos.z)
	spawn(water, at, lerpf(1.4, 3.6, strength), lerpf(0.8, 1.5, strength))
	spawn(water, at, lerpf(0.7, 1.8, strength), lerpf(0.5, 0.9, strength))
	if _drop_mesh == null:
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		mat.vertex_color_use_as_albedo = true
		mat.albedo_color = Color(0.92, 0.97, 1.0, 0.8)
		mat.disable_receive_shadows = true
		_drop_mesh = QuadMesh.new()
		_drop_mesh.size = Vector2.ONE * 0.06
		_drop_mesh.material = mat
		_fade = Gradient.new()
		_fade.set_color(0, Color.WHITE)
		_fade.set_color(1, Color(1, 1, 1, 0))
	var spray := CPUParticles3D.new()
	spray.mesh = _drop_mesh
	spray.color_ramp = _fade
	spray.one_shot = true
	spray.explosiveness = 0.9
	spray.amount = int(lerpf(10.0, 48.0, strength))
	spray.lifetime = lerpf(0.5, 0.9, strength)
	spray.direction = Vector3.UP
	spray.spread = 35.0
	spray.initial_velocity_min = lerpf(1.0, 2.2, strength)
	spray.initial_velocity_max = lerpf(1.8, 4.2, strength)
	spray.gravity = Vector3(0.0, -9.8, 0.0)
	spray.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	spray.emission_ring_axis = Vector3.UP
	spray.emission_ring_radius = lerpf(0.15, 0.4, strength)
	spray.emission_ring_inner_radius = 0.0
	spray.emission_ring_height = 0.0
	spray.scale_amount_min = 0.6
	spray.scale_amount_max = 1.4
	spray.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	water.add_child(spray)
	spray.global_position = at
	spray.emitting = true
	spray.finished.connect(spray.queue_free)


func _process(_delta: float) -> void:
	_ride()


func _ride() -> void:
	if is_instance_valid(_water):
		global_position.y = _water.surface_y(global_position) + 0.02
