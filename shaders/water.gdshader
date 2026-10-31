shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_lambert, specular_schlick_ggx;

// Water (Valheim-style): a smooth surface rippled by layers of small moving waves, nearly clear
// in the shallows and teal with depth, broken foam where it meets the shore, the sky reflected
// at grazing angles and the sun glinting off the ripples. Depth is read from the depth buffer,
// so anything under the surface (the bed, fish, your legs) is tinted by how much water is in
// front of it. Fish are drawn where they really are (no refraction offset), so what you aim at is
// what you hit.
// From below (diving, plans/water.md) it's the surface seen from under the water: a bright, rippling
// window straight up onto the sky (Snell's window: everything above the water squeezed into a cone
// about 49° round the vertical), and outside it a dark mirror of the water itself.
// Use on a subdivided PlaneMesh (≈1 m per quad) or strip at the water level.

uniform vec3 shallow_color : source_color = vec3(0.22, 0.52, 0.52);
uniform vec3 deep_color : source_color = vec3(0.04, 0.20, 0.26);
// Metres of water before the colour is fully `deep_color`.
uniform float clarity_depth = 1.1;
uniform float shallow_alpha : hint_range(0.0, 1.0) = 0.12;
uniform float deep_alpha : hint_range(0.0, 1.0) = 0.6;

uniform vec3 foam_color : source_color = vec3(0.95, 0.98, 1.0);
// Water thinner than this (m) foams up along the shore, in a broken, drifting band.
uniform float foam_depth = 0.05;

// The big, slow swell (moves the surface) and the small ripples (only bend the light).
uniform float wave_height = 0.025;
uniform float wave_speed = 0.8;
uniform float wave_scale = 0.35;
uniform float ripple_strength = 0.22;
uniform float ripple_scale = 2.2;
// How mirror-like the surface is at grazing angles (0 = never).
uniform float reflectivity : hint_range(0.0, 1.0) = 0.75;

// Seen from below: the window's edge (cosine of its half-angle, ~49°) and its colour; daylight
// under the water (UnderwaterView sets it).
uniform float window_cos = 0.66;
uniform vec3 window_tint : source_color = vec3(0.55, 0.78, 0.8);
// Outside the window the surface mirrors the water below it: the underwater murk's colour
// (keep near underwater.gdshaderinc's murk_color).
uniform vec3 mirror_color : source_color = vec3(0.18, 0.46, 0.48);
global uniform float under_light;

uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
// Debug: show water thickness as greyscale (white = clarity_depth or more).
uniform bool debug_thickness = false;

varying vec3 v_world;

float waves(vec2 p, float t) {
	return sin(p.x * wave_scale * 2.1 + t) * 0.5
		+ sin(p.y * wave_scale * 1.7 - t * 1.3) * 0.35
		+ sin((p.x + p.y) * wave_scale * 3.3 + t * 0.7) * 0.15;
}

// Slope (d/dx, d/dz) of a sum of small sine ripples running in different directions.
vec2 ripples(vec2 p, float t) {
	vec2 g = vec2(0.0);
	const int N = 6;
	for (int i = 0; i < N; i++) {
		float a = float(i) * 2.399;  // golden angle: directions spread round the circle
		vec2 dir = vec2(cos(a), sin(a));
		float k = ripple_scale * (1.0 + float(i) * 0.37);
		float w = 1.0 / (1.0 + float(i) * 0.6);
		g += dir * k * w * cos(dot(p, dir) * k + t * (1.3 + float(i) * 0.21));
	}
	return g / float(N);
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
			mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	VERTEX.y += waves(v_world.xz, TIME * wave_speed) * wave_height;
}

void fragment() {
	// smooth normal: the swell's slope plus the ripples
	float t = TIME * wave_speed;
	float e = 0.1;
	vec2 swell = vec2(waves(v_world.xz + vec2(e, 0.0), t) - waves(v_world.xz - vec2(e, 0.0), t),
			waves(v_world.xz + vec2(0.0, e), t) - waves(v_world.xz - vec2(0.0, e), t)) / (2.0 * e) * wave_height;
	vec2 slope = swell + ripples(v_world.xz, TIME) * ripple_strength * 0.1;
	vec3 n = normalize(vec3(-slope.x, 1.0, -slope.y));
	if (!FRONT_FACING) {
		// how near straight up you're looking at this bit of surface (bent a little by the ripples)
		vec3 up_ray = normalize((INV_VIEW_MATRIX * vec4(-VIEW, 0.0)).xyz);
		float c = dot(up_ray, n);
		float window = smoothstep(window_cos - 0.04, window_cos + 0.03, c);
		float rim = window * (1.0 - smoothstep(window_cos + 0.03, window_cos + 0.14, c));
		NORMAL = normalize((VIEW_MATRIX * vec4(-n, 0.0)).xyz);
		ALBEDO = vec3(0.0);
		EMISSION = mix(mirror_color, window_tint * (1.0 + rim * 0.8), window) * under_light;
		ALPHA = mix(1.0, 0.35, window);  // (the sky and the trees show through the window)
		ROUGHNESS = 0.3;
		SPECULAR = 0.0;
	} else {
		NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);

		// how much water is in front of whatever is behind this pixel
		float raw_depth = texture(depth_tex, SCREEN_UV).r;
		vec4 behind = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, raw_depth, 1.0);
		behind.xyz /= behind.w;
		float behind_y = (INV_VIEW_MATRIX * vec4(behind.xyz, 1.0)).y;
		float surface_y = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).y;
		float thickness = max(surface_y - behind_y, 0.0);

		float k = clamp(thickness / clarity_depth, 0.0, 1.0);
		vec3 color = mix(shallow_color, deep_color, k);
		float alpha = mix(shallow_alpha, deep_alpha, k);

		// shore foam: a band that breaks up and drifts
		float broken = vnoise(v_world.xz * 1.6 + vec2(TIME * 0.15, -TIME * 0.11));
		float edge = foam_depth * (0.5 + broken);
		float foam = 1.0 - smoothstep(edge * 0.55, edge, thickness);
		foam *= step(0.45, vnoise(v_world.xz * 3.0 - TIME * 0.08) + foam * 0.4);
		color = mix(color, foam_color, foam * 0.85);

		// more of the sky at grazing angles (Fresnel), less see-through there too
		float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0) * reflectivity;
		alpha = max(mix(alpha, 0.92, fresnel), foam * 0.7);

		ALBEDO = color;
		ALPHA = alpha;
		ROUGHNESS = mix(0.06, 0.6, foam);  // a crisp mirror for the sky, sharp sun glints off the ripples
		SPECULAR = 0.5;
		if (debug_thickness) {
			ALBEDO = vec3(0.0);
			EMISSION = vec3(k);  // unlit, so it reads true (note: screenshots are sRGB-encoded)
			ALPHA = 1.0;
		}
	}
}
