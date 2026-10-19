shader_type spatial;
render_mode specular_disabled, cull_disabled;

// Dense grass round the player (scripts/grass_field.gd): clumps of blades drawn with MultiMesh,
// each coloured to match the ground it grows on (the instance colour). UV.y runs 0 at a blade's
// root to 1 at its tip: the tip bends in the shared wind and away from the player, the root is
// darker, and clumps shrink into the ground toward the edge of the ring so it never pops.

global uniform vec2 wind_direction;
global uniform float wind_strength;
// Where the player stands (set by GrassField each frame), and how far round them grass parts.
global uniform vec3 grass_pusher;
uniform float push_radius = 1.1;
// The ring: full size inside fade_start, gone at fade_end (metres from the camera, set by GrassField).
uniform float fade_start = 30.0;
uniform float fade_end = 38.0;
uniform float sway = 0.12;
uniform vec3 tip_tint : source_color = vec3(1.1, 1.08, 0.8);
uniform float root_dark = 0.72;

void vertex() {
	vec3 world_root = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float t = UV.y;
	float bend = t * t;
	// shrink toward the ring's edge
	float d = length(world_root.xz - CAMERA_POSITION_WORLD.xz);
	float fade = 1.0 - smoothstep(fade_start, fade_end, d);
	VERTEX *= fade;
	// wind: a slow gust rolling across the world plus a quick flutter
	float phase = dot(world_root.xz, vec2(0.21, 0.17));
	float gust = 0.6 + 0.4 * sin(TIME * 0.7 - dot(world_root.xz, wind_direction) * 0.08);
	float w = (sin(TIME * 1.9 + phase) * 0.35 + 0.65) * gust * wind_strength * sway;
	vec3 offset = vec3(wind_direction.x, 0.0, wind_direction.y) * w;
	offset += vec3(sin(TIME * 4.3 + phase * 3.0), 0.0, cos(TIME * 3.7 + phase * 2.0)) * 0.02 * wind_strength;
	// parted by the player
	vec3 away = world_root - grass_pusher;
	float near = 1.0 - smoothstep(0.0, push_radius, length(away.xz));
	near *= 1.0 - smoothstep(0.5, 1.6, abs(away.y));
	offset += normalize(vec3(away.x, 0.0, away.z) + vec3(0.001, 0.0, 0.0)) * near * 0.45;
	vec3 local_offset = (inverse(mat3(MODEL_MATRIX)) * offset) * bend;
	VERTEX += local_offset;
	VERTEX.y -= length(local_offset) * 0.35 * bend;  // a bent blade is shorter
	// light it like the ground under it, not like a flat card
	NORMAL = normalize(inverse(mat3(MODEL_MATRIX)) * vec3(0.0, 1.0, 0.0));
}

void fragment() {
	vec3 c = COLOR.rgb * mix(root_dark, 1.0, UV.y);
	c = mix(c, c * tip_tint, smoothstep(0.6, 1.0, UV.y));
	ALBEDO = c;
	// straight up on both sides (a double-sided face's back would otherwise point down, dark)
	NORMAL = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
	ROUGHNESS = 1.0;
	BACKLIGHT = c * 0.1;
}
