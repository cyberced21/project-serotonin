shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_test_disabled, depth_draw_never, fog_disabled, shadows_disabled;

// The underwater view, second pass: the water's own murk (light scattered in it) filling in with
// distance, as bright as the daylight getting in, and the sun's shafts: beams slanting down from
// the surface toward the sun, where the waves above happen to focus the light (marched along the
// view through the first SHAFT_REACH metres of water). See underwater.gdshader.

#include "res://shaders/underwater.gdshaderinc"

// Towards the sun (UnderwaterView sets it from the scene's sun), and the waves' clock (Waves).
global uniform vec3 sun_direction;
global uniform float water_time;
uniform vec3 shaft_color : source_color = vec3(0.78, 0.96, 0.94);
uniform float shaft_strength = 0.5;
// How far along the view (m) the shafts are looked for, and how wide (m) a beam is.
const float SHAFT_REACH = 14.0;
uniform float shaft_size = 2.2;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

// Where the waves focus the light, at `q` on the surface (in beam widths): a round patch in each
// cell of a grid, wandering about its cell and swelling in and out on its own clock, so the
// beams under it drift, come and go.
float beams(vec2 q) {
	vec2 c = floor(q);
	float best = 0.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 cell = c + vec2(float(x), float(y));
			float a = hash(cell);
			float b = hash(cell + 17.3);
			float k = hash(cell + 41.7);
			vec2 centre = cell + 0.5 + 0.3 * vec2(sin(water_time * (0.15 + 0.2 * a) + b * 6.283),
					cos(water_time * (0.12 + 0.2 * b) + a * 6.283));
			float life = smoothstep(0.3, 0.85, 0.5 + 0.5 * sin(water_time * (0.2 + 0.3 * k) + a * 6.283));
			float r = (0.22 + 0.16 * b) * (0.6 + 0.4 * life);
			float spot = 1.0 - smoothstep(r * 0.3, r, length(q - centre));
			best = max(best, spot * life);
		}
	}
	return best;
}

// (12 samples along the view, each pixel's started at its own offset so the steps don't show as
// flat slabs: the dither reads as a little grain instead)
const int SHAFT_STEPS = 12;

float shafts(vec3 eye, vec3 dir, float dist, vec2 pixel) {
	if (sun_direction.y < 0.05) {
		return 0.0;
	}
	vec2 slant = sun_direction.xz / sun_direction.y;
	float reach = min(dist, SHAFT_REACH);
	float total = 0.0;
	float jitter = hash(pixel);  // (still, not changing every frame: a steady grain, no shimmer)
	for (int i = 0; i < SHAFT_STEPS; i++) {
		float s = reach * (float(i) + jitter) / float(SHAFT_STEPS);
		vec3 p = eye + dir * s;
		float below = surface_height - p.y;
		if (below < 0.0) {
			continue;
		}
		// where this bit of water's sunlight came in through the surface
		vec2 q = (p.xz + slant * below) / shaft_size;
		float beam = beams(q + vec2(water_time * 0.04, -water_time * 0.03));
		total += beam * exp(-below * 0.22) * exp(-s * 0.1);
	}
	return total / float(SHAFT_STEPS);
}

void fragment() {
	float d = water_between(SCREEN_UV, INV_PROJECTION_MATRIX, INV_VIEW_MATRIX);
	vec3 dir = view_ray(SCREEN_UV, INV_PROJECTION_MATRIX, INV_VIEW_MATRIX);
	float sun = clamp(sun_direction.y * 2.0, 0.0, 1.0);
	ALBEDO = murk_color * under_light * (1.0 - exp(-scatter * d))
			+ shaft_color * shafts(INV_VIEW_MATRIX[3].xyz, dir, d, FRAGCOORD.xy) * shaft_strength * sun * under_light;
}
