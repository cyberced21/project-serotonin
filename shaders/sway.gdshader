shader_type spatial;
render_mode specular_disabled, cull_disabled;

// Palette-coloured plants (reeds) that sway in a gentle breeze: the higher a vertex is above the
// plant's base (`base_y`, world height, set per mesh by PondDressing), the further it leans;
// each clump sways out of step with its neighbours.

uniform sampler2D palette : source_color, filter_nearest, repeat_disable, hint_default_white;
uniform float strength = 0.05;
uniform float speed = 1.3;
instance uniform float base_y = 0.0;
// Per-clump offset so neighbours sway out of step (set by PondDressing).
instance uniform float sway_phase = 0.0;

void vertex() {
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float h = max(world.y - base_y, 0.0);
	float lean = h * h * strength;
	float t = TIME * speed + sway_phase;
	world.x += sin(t) * lean;
	world.z += sin(t * 0.8 + 1.7) * lean * 0.6;
	VERTEX = (inverse(MODEL_MATRIX) * vec4(world, 1.0)).xyz;
}

void fragment() {
	ALBEDO = texture(palette, UV).rgb;
	ROUGHNESS = 1.0;
}
