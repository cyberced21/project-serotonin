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

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
			mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

float shafts(vec3 eye, vec3 dir, float dist) {
	if (sun_direction.y < 0.05) {
		return 0.0;
	}
	vec2 slant = sun_direction.xz / sun_direction.y;
	float reach = min(dist, SHAFT_REACH);
	float total = 0.0;
	for (int i = 0; i < 8; i++) {
		float s = reach * (float(i) + 0.5) / 8.0;
		vec3 p = eye + dir * s;
		float below = surface_height - p.y;
		if (below < 0.0) {
			continue;
		}
		// where this bit of water's sunlight came in through the surface
		vec2 q = (p.xz + slant * below) / shaft_size;
		float beam = smoothstep(0.55, 0.85, vnoise(q + vec2(water_time * 0.07, -water_time * 0.05)));
		total += beam * exp(-below * 0.22) * exp(-s * 0.1);
	}
	return total / 8.0;
}

void fragment() {
	float d = water_between(SCREEN_UV, INV_PROJECTION_MATRIX, INV_VIEW_MATRIX);
	vec3 dir = view_ray(SCREEN_UV, INV_PROJECTION_MATRIX, INV_VIEW_MATRIX);
	float sun = clamp(sun_direction.y * 2.0, 0.0, 1.0);
	ALBEDO = murk_color * under_light * (1.0 - exp(-scatter * d))
			+ shaft_color * shafts(INV_VIEW_MATRIX[3].xyz, dir, d) * shaft_strength * sun * under_light;
}
