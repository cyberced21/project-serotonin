shader_type canvas_item;

// Faint streaks rushing outward at the edges of the screen when moving fast (player.gd sets
// `intensity` from your speed). Full-screen overlay; the middle stays clear so you can aim.

uniform float intensity : hint_range(0.0, 1.0) = 0.0;
uniform vec4 color : source_color = vec4(1.0, 1.0, 1.0, 0.35);
// How many lanes the streaks run in around the screen.
uniform float lanes = 150.0;

float hash(float n) {
	return fract(sin(n * 127.1) * 43758.5453);
}

void fragment() {
	vec2 uv = UV - 0.5;
	uv.x *= SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;  // round, not stretched with the screen
	float r = length(uv);
	float lane_f = (atan(uv.y, uv.x) / 6.2831853 + 0.5) * lanes;
	float id = floor(lane_f);
	float rnd = hash(id);
	// one streak per lane, flying outward, each lane at its own pace
	float t = fract(TIME * (1.2 + rnd * 1.8) + rnd * 7.0);
	float head = mix(0.3, 1.0, t);
	float streak = smoothstep(head - 0.22, head, r) * (1.0 - smoothstep(head, head + 0.015, r));
	float thin = 1.0 - smoothstep(0.0, 0.5, abs(fract(lane_f) - 0.5) * 2.0);
	float edges = smoothstep(0.3, 0.62, r);  // clear in the middle
	float some = step(0.6, rnd);  // only some lanes have a streak
	COLOR = vec4(color.rgb, color.a * streak * thin * edges * some * intensity);
}
