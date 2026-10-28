class_name Bunting
extends MeshInstance3D
## A string of little cloth flags (the bunting project) sagging between two points, built in
## code: a thin cord and a triangle every FLAG_GAP m, colours in turn, swaying a touch in the
## wind (the flags' tips, through a small vertex wobble in its shader).

const FLAG_GAP := 0.42
const FLAG_SIZE := Vector2(0.26, 0.34)  # width along the cord, drop
## How far the middle sags, as a share of the span.
const SAG := 0.07
const COLORS: Array[Color] = [Color("e9d9b8"), Color("d98c7a"), Color("8fae84"), Color("e2b85c"), Color("8cb2c9")]

var from := Vector3.ZERO
var to := Vector3.ZERO


func _ready() -> void:
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var span := from.distance_to(to)
	var n := maxi(2, int(span / FLAG_GAP))
	var side := (to - from).cross(Vector3.UP).normalized() * 0.008
	for i in n:
		var a := _at(float(i) / n, span)
		var b := _at(float(i + 1) / n, span)
		_quad(st, a - Vector3.UP * 0.008, b - Vector3.UP * 0.008, b + Vector3.UP * 0.008, a + Vector3.UP * 0.008, Color("5a4632"))
		var mid := a.lerp(b, 0.5)
		var along := (b - a).normalized()
		var c := COLORS[i % COLORS.size()]
		var left := mid - along * FLAG_SIZE.x * 0.5
		var right := mid + along * FLAG_SIZE.x * 0.5
		var tip := mid + Vector3.DOWN * FLAG_SIZE.y + side * 4.0
		for v in [left, right, tip]:
			st.set_color(c)
			st.set_uv(Vector2(0.0 if v == tip else 1.0, 0.0))  # u: 1 on the cord, 0 at the tip
			st.add_vertex(v - global_position)
	st.generate_normals()
	mesh = st.commit()
	var mat := ShaderMaterial.new()
	mat.shader = _shader()
	material_override = mat


## The cord's point a share `t` of the way along, sagging in the middle.
func _at(t: float, span: float) -> Vector3:
	return from.lerp(to, t) + Vector3.DOWN * (4.0 * t * (1.0 - t)) * SAG * span


func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color) -> void:
	for v in [a, b, c, a, c, d]:
		st.set_color(col)
		st.set_uv(Vector2(1, 0))
		st.add_vertex(v - global_position)


static var _cached: Shader


static func _shader() -> Shader:
	if _cached == null:
		_cached = Shader.new()
		_cached.code = """
shader_type spatial;
render_mode cull_disabled;
void vertex() {
	float tipness = 1.0 - UV.x;
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	VERTEX.x += sin(TIME * 2.1 + w.x * 1.7 + w.z * 0.9) * 0.05 * tipness;
	VERTEX.z += cos(TIME * 1.7 + w.z * 1.3) * 0.04 * tipness;
}
void fragment() {
	ALBEDO = pow(COLOR.rgb, vec3(2.2));  // (vertex colours come in sRGB)
	ROUGHNESS = 0.9;
}
"""
	return _cached
