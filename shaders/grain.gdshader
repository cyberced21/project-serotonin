shader_type canvas_item;
// A full-screen grain overlay, drawn on a ColorRect over the 3D view (under the HUD; GrainOverlay
// holds the game's look, tools/grain_shots.gd shoots other looks to compare). It can:
//   - draw the picture in chunky pixels (pixel_size > 1), like a low-resolution render blown up,
//   - cut each colour to a few steps (levels) with a fixed 4x4 dot pattern between steps (dither),
//   - lay noise over it (grain), still or new every frame, stronger in the shadows (shadow_weight).
// Everything at 0 (pixel_size 1) leaves the picture as it is.

uniform sampler2D screen_tex : hint_screen_texture, filter_nearest, repeat_disable;
uniform float pixel_size : hint_range(1.0, 8.0, 1.0) = 1.0;  // screen pixels per chunky pixel
uniform float levels : hint_range(0.0, 64.0, 1.0) = 0.0;    // colour steps per channel; 0 = smooth
uniform float dither : hint_range(0.0, 1.0) = 0.0;          // strength of the fixed dot pattern
uniform float grain : hint_range(0.0, 0.3) = 0.0;           // strength of the noise
uniform float grain_size : hint_range(1.0, 4.0) = 1.0;      // screen pixels per grain
uniform float grain_speed = 0.0;                            // new noise patterns per second; 0 = still
uniform float seed = 0.0;                                   // picks the noise pattern
uniform float shadow_weight : hint_range(0.0, 1.0) = 0.0;   // 0 = even everywhere, 1 = mostly in darks
uniform bool colour_grain = false;                          // grain per channel instead of grey

const float BAYER[16] = float[16](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0,
		3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

void fragment() {
	vec2 px = FRAGCOORD.xy;
	vec2 cell = floor(px / pixel_size);
	vec2 uv = (cell + 0.5) * pixel_size * SCREEN_PIXEL_SIZE;
	vec3 c = textureLod(screen_tex, uv, 0.0).rgb;

	float lum = dot(c, vec3(0.299, 0.587, 0.114));
	// heavier in the shadows, but not on pure black
	float w = mix(1.0, (1.0 - lum) * 1.4, shadow_weight) * smoothstep(0.0, 0.06, lum);

	if (grain > 0.0) {
		float frame = seed + floor(TIME * grain_speed);
		vec2 g = floor(px / grain_size) + frame * vec2(17.13, 31.71);
		vec3 n = vec3(hash(g) - 0.5);
		if (colour_grain) {
			n = vec3(hash(g), hash(g + 3.7), hash(g + 7.9)) - 0.5;
		}
		c += n * 2.0 * grain * w;
	}

	int bx = int(mod(cell.x, 4.0));
	int by = int(mod(cell.y, 4.0));
	float d = (BAYER[bx + by * 4] + 0.5) / 16.0 - 0.5;
	if (levels > 0.0) {
		c = floor(c * levels + 0.5 + d * dither) / levels;
	} else if (dither > 0.0) {
		c += d * dither * 0.05 * w;
	}
	COLOR = vec4(clamp(c, 0.0, 1.0), 1.0);
}
