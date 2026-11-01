// Shared by the two passes of the underwater view (UnderwaterView, plans/water.md): how many
// metres of water lie between the eye and what this pixel shows. That's the depth buffer, except
// that the water's own surface isn't in it (it's see-through), so a ray going up stops where it
// meets the surface: what's above the water (sky, trees) is only dimmed by the water in between.

uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
// World height of the water's surface over the eye.
uniform float surface_height = -0.15;
// Past this much water (m) everything's murk.
uniform float max_distance = 40.0;
// Light lost per metre of water, per colour: red goes first, then green, so the far side of the
// lake goes teal, then deep blue.
uniform vec3 absorb = vec3(0.2, 0.055, 0.04);
// How quickly the water's own murk (scattered light, `murk_color`) fills in the distance.
uniform float scatter = 0.065;
uniform vec3 murk_color : source_color = vec3(0.2, 0.5, 0.52);
// Daylight under the water (1 by day, low at night; UnderwaterView sets it): the murk is only as
// bright as the light getting in.
global uniform float under_light;

// The world direction the eye looks along through this pixel.
vec3 view_ray(vec2 screen_uv, mat4 inv_projection, mat4 inv_view) {
	vec4 near = inv_projection * vec4(screen_uv * 2.0 - 1.0, 1.0, 1.0);  // (reversed Z: 1 is the near plane)
	return normalize((inv_view * vec4(near.xyz / near.w, 0.0)).xyz);
}

float water_between(vec2 screen_uv, mat4 inv_projection, mat4 inv_view) {
	vec2 ndc = screen_uv * 2.0 - 1.0;
	float raw = texture(depth_tex, screen_uv).r;
	float dist = max_distance;
	if (raw > 0.0) {
		vec4 at = inv_projection * vec4(ndc, raw, 1.0);
		dist = min(length(at.xyz / at.w), max_distance);
	}
	vec3 dir = view_ray(screen_uv, inv_projection, inv_view);
	float eye_y = inv_view[3].y;
	if (dir.y > 0.0001) {
		dist = min(dist, max((surface_height - eye_y) / dir.y, 0.0));
	}
	return dist;
}

void vertex() {
	POSITION = vec4(VERTEX.xy * 2.0, 1.0, 1.0);  // the whole screen, whatever the camera does
}
