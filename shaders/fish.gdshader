shader_type spatial;
render_mode specular_disabled;

// Swimming fish: palette colours (like node_palette), a side-to-side wiggle that grows toward
// the tail and speeds up when fleeing, plus the shared hit flash and hover highlight.
// Models face -Z (head) with their origin at the body centre; see tools/blender/make_models.py.

uniform sampler2D palette : source_color, filter_nearest, repeat_disable, hint_default_white;
uniform vec3 highlight_color : source_color = vec3(1.0, 0.92, 0.6);

// 0 = idling, 1 = flat-out fleeing. Set by scripts/fish_school.gd.
instance uniform float swim = 0.3;
// Per-fish offset so a school doesn't wiggle in lockstep.
instance uniform float phase = 0.0;
// Body length (m), so the wave fits any size of fish.
instance uniform float body_length = 0.3;
instance uniform float flash = 0.0;
instance uniform float highlight = 0.0;

void vertex() {
	float t = clamp(VERTEX.z / body_length + 0.5, 0.0, 1.2);  // 0 at the head .. 1 at the tail
	float amp = mix(0.03, 0.1, swim) * body_length * t * t;
	float freq = mix(5.0, 22.0, swim);
	VERTEX.x += sin(TIME * freq - t * 5.0 + phase) * amp;
}

void fragment() {
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.0);
	vec3 base = texture(palette, UV).rgb;
	ALBEDO = mix(base, vec3(1.0), flash);
	ROUGHNESS = 0.6;
	EMISSION = vec3(flash) * 0.6 + highlight_color * (0.12 + rim * 0.6) * highlight;
}
