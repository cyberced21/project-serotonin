shader_type sky;

// The game's sky, driven by DayNightSky: a gradient from the horizon up to the top colour (and
// down to the ground colour below it), the light's disc — the sun by day, the moon by night
// (the same DirectionalLight swings round as the moon after sunset) — and twinkling stars
// that fade in with `night`.

uniform vec3 top_color : source_color = vec3(0.36, 0.47, 0.62);
uniform vec3 horizon_color : source_color = vec3(0.66, 0.74, 0.78);
uniform vec3 ground_color : source_color = vec3(0.33, 0.37, 0.39);
// 0 by day, 1 at full night (stars, moon instead of sun).
uniform float night : hint_range(0.0, 1.0) = 0.0;
// Angular radius of the sun / moon discs (radians).
uniform float sun_size = 0.035;
uniform float moon_size = 0.045;
// Fraction of sky cells holding a star (lower = fewer).
uniform float star_amount = 0.004;

float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

void sky() {
	vec3 d = EYEDIR;
	vec3 col = d.y >= 0.0
		? mix(horizon_color, top_color, smoothstep(0.0, 0.55, d.y))
		: mix(horizon_color, ground_color, smoothstep(0.0, -0.25, d.y));

	if (!AT_CUBEMAP_PASS) {
		// stars: one maybe-star per cell of a grid over the sky dome, round, twinkling
		if (d.y > 0.0 && night > 0.0) {
			vec3 p = d * 180.0;
			vec3 cell = floor(p);
			float r = hash(cell);
			if (r > 1.0 - star_amount) {
				vec3 f = fract(p) - 0.5;
				float star = smoothstep(0.32, 0.05, length(f));
				float twinkle = 0.65 + 0.35 * sin(TIME * (1.5 + r * 4.0) + r * 60.0);
				col += vec3(0.85, 0.9, 1.0) * star * twinkle * night * smoothstep(0.0, 0.2, d.y);
			}
		}
		// the sun by day, the moon by night
		if (LIGHT0_ENABLED) {
			float a = acos(clamp(dot(d, LIGHT0_DIRECTION), -1.0, 1.0));
			float sun = 1.0 - smoothstep(sun_size * 0.8, sun_size, a);
			float moon = 1.0 - smoothstep(moon_size * 0.9, moon_size, a);
			float halo = exp(-a * 9.0);
			col += (1.0 - night) * (vec3(1.0, 0.95, 0.85) * sun * 3.0 + LIGHT0_COLOR * halo * 0.25);
			col = mix(col, vec3(0.92, 0.94, 1.0), moon * night);
			col += vec3(0.5, 0.6, 0.9) * halo * 0.15 * night;
		}
	}
	COLOR = col;
}
