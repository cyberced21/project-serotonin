shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_lambert, specular_schlick_ggx;

// Low-poly water, to match the terrain: a gently swelling, flat-shaded (faceted) surface that is
// nearly clear in the shallows and turns teal with depth, with a foam line where it meets the
// shore. Depth is read from the depth buffer, so anything under the surface — the bed, fish,
// your legs — is tinted by how much water is in front of it. Fish are drawn where they really
// are (no refraction offset), so what you aim at is what you hit.
// Use on a subdivided PlaneMesh (≈1 m per quad) at the water level.

uniform vec3 shallow_color : source_color = vec3(0.22, 0.52, 0.52);
uniform vec3 deep_color : source_color = vec3(0.04, 0.20, 0.26);
// Metres of water before the colour is fully `deep_color`.
uniform float clarity_depth = 1.1;
uniform float shallow_alpha : hint_range(0.0, 1.0) = 0.12;
uniform float deep_alpha : hint_range(0.0, 1.0) = 0.6;

uniform vec3 foam_color : source_color = vec3(0.95, 0.98, 1.0);
// Water thinner than this (m) foams up along the shore.
uniform float foam_depth = 0.1;

uniform float wave_height = 0.025;
uniform float wave_speed = 0.8;
uniform float wave_scale = 0.35;

uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
// Debug: show water thickness as greyscale (white = clarity_depth or more).
uniform bool debug_thickness = false;

float waves(vec2 p, float t) {
	return sin(p.x * wave_scale * 2.1 + t) * 0.5
		+ sin(p.y * wave_scale * 1.7 - t * 1.3) * 0.35
		+ sin((p.x + p.y) * wave_scale * 3.3 + t * 0.7) * 0.15;
}

void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	VERTEX.y += waves(w.xz, TIME * wave_speed) * wave_height;
}

void fragment() {
	// faceted normal: the true plane of each triangle
	NORMAL = normalize(cross(dFdy(VERTEX), dFdx(VERTEX)));

	// how much water is in front of whatever is behind this pixel
	float raw_depth = texture(depth_tex, SCREEN_UV).r;
	vec4 behind = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, raw_depth, 1.0);
	behind.xyz /= behind.w;
	float behind_y = (INV_VIEW_MATRIX * vec4(behind.xyz, 1.0)).y;
	float surface_y = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).y;
	float thickness = max(surface_y - behind_y, 0.0);

	float t = clamp(thickness / clarity_depth, 0.0, 1.0);
	vec3 color = mix(shallow_color, deep_color, t);
	float alpha = mix(shallow_alpha, deep_alpha, t);

	float foam = 1.0 - smoothstep(0.0, foam_depth, thickness);
	color = mix(color, foam_color, foam);
	alpha = max(alpha, foam * 0.85);

	ALBEDO = color;
	ALPHA = alpha;
	if (debug_thickness) {
		ALBEDO = vec3(0.0);
		EMISSION = vec3(t);  // unlit, so it reads true (note: screenshots are sRGB-encoded)
		ALPHA = 1.0;
	}
	ROUGHNESS = 0.38;  // soft sun glints, not a blinding hot spot
	SPECULAR = 0.25;
}
