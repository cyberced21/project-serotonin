shader_type spatial;
render_mode specular_disabled, cull_disabled;

// Palette-coloured plants drawn with MultiMesh (grass, flowers, bushes — see SceneryScatter).
// Like sway.gdshader, but per-instance data comes from the instance itself: the lean grows with
// height above the mesh's own origin (its base), and each plant's phase from where it stands,
// with a slow gust rolling across the world on top.

uniform sampler2D palette : source_color, filter_nearest, repeat_disable, hint_default_white;
#include "res://shaders/detail.gdshaderinc"

uniform float strength = 0.25;
uniform float speed = 1.3;

void vertex() {
	DETAIL_CAPTURE
	vec3 origin = MODEL_MATRIX[3].xyz;
	float phase = fract(sin(dot(origin.xz, vec2(12.9898, 78.233))) * 43758.5453) * 6.2831;
	float gust = 0.6 + 0.4 * sin(TIME * 0.35 + origin.x * 0.04 + origin.z * 0.03);
	float h = max(VERTEX.y, 0.0);
	float lean = h * h * strength * gust;
	float t = TIME * speed + phase;
	VERTEX.x += sin(t) * lean;
	VERTEX.z += sin(t * 0.8 + 1.7) * lean * 0.6;
}

void fragment() {
	ALBEDO = texture(palette, UV).rgb * DETAIL(UV);
	ROUGHNESS = 1.0;
}
