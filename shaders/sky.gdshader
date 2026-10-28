shader_type sky;

// The game's sky, driven by DayNightSky: a gradient from the horizon up to the top colour (and
// down to the ground colour below it), the light's disc — the sun by day, the moon by night
// (the same DirectionalLight swings round as the moon after sunset) — with a wide glow round a
// low sun, painterly clouds drifting across (lit from the sun's side, in soft bands), and
// twinkling stars that fade in with `night`.

uniform vec3 top_color : source_color = vec3(0.36, 0.47, 0.62);
uniform vec3 horizon_color : source_color = vec3(0.66, 0.74, 0.78);
uniform vec3 ground_color : source_color = vec3(0.33, 0.37, 0.39);
// 0 by day, 1 at full night (stars, moon instead of sun).
uniform float night : hint_range(0.0, 1.0) = 0.0;
// Angular radius of the sun / moon discs (radians).
uniform float sun_size = 0.035;
uniform float moon_size = 0.045;
// The sun disc's brightness, its tight halo, and the wide warm glow round it (always / extra when low).
uniform float sun_brightness = 3.0;
uniform float sun_halo = 0.25;
uniform float sun_halo_falloff = 9.0;
uniform float sun_glow = 0.08;
uniform float sun_glow_low = 0.22;
// Fraction of sky cells holding a star (lower = fewer).
uniform float star_amount = 0.004;
// Clouds: how much of the sky they cover, how big they are, and how fast they drift (and where).
uniform float cloud_coverage : hint_range(0.0, 1.0) = 0.45;
uniform float cloud_scale = 0.9;
uniform vec2 cloud_wind = vec2(0.006, 0.0025);
// The clouds' lit side at sunrise / sunset (golden / pink), and how much of it.
uniform vec3 cloud_tint : source_color = vec3(1.0, 0.8, 0.6);
uniform float cloud_tint_amount : hint_range(0.0, 1.0) = 0.0;

float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float noise2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash(vec3(i, 1.0));
	float b = hash(vec3(i + vec2(1.0, 0.0), 1.0));
	float c = hash(vec3(i + vec2(0.0, 1.0), 1.0));
	float e = hash(vec3(i + vec2(1.0, 1.0), 1.0));
	return mix(mix(a, b, f.x), mix(c, e, f.x), f.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 5; i++) {
		v += noise2(p) * amp;
		p = p * 2.03 + vec2(17.1, 3.7);
		amp *= 0.5;
	}
	return v;
}

void sky() {
	vec3 d = EYEDIR;
	vec3 col = d.y >= 0.0
		? mix(horizon_color, top_color, smoothstep(0.0, 0.55, d.y))
		: mix(horizon_color, ground_color, smoothstep(0.0, -0.25, d.y));

	// a wide warm glow round the sun, strongest when it's low (dawn, dusk)
	if (LIGHT0_ENABLED) {
		float a0 = acos(clamp(dot(d, LIGHT0_DIRECTION), -1.0, 1.0));
		float low = 1.0 - clamp(LIGHT0_DIRECTION.y * 2.5, 0.0, 1.0);
		col += LIGHT0_COLOR * exp(-a0 * 2.2) * (sun_glow + sun_glow_low * low) * (1.0 - night);
	}

	// clouds, on a dome over the world
	if (d.y > 0.0) {
		vec2 uv = d.xz / (d.y + 0.12) * cloud_scale + cloud_wind * TIME;
		float f = fbm(uv);
		float density = smoothstep(1.0 - cloud_coverage - 0.05, 1.0 - cloud_coverage + 0.2, f);
		density = floor(density * 3.0 + 0.5) / 3.0 * 0.6 + density * 0.4;  // soft painterly bands
		// lit from the sun's side: thinner toward the light means brighter
		vec2 toward = LIGHT0_ENABLED ? normalize(LIGHT0_DIRECTION.xz + vec2(1e-4)) * 0.12 : vec2(0.0);
		float lit = clamp((f - fbm(uv + toward)) * 4.0 + 0.6, 0.0, 1.0);
		vec3 sun_col = LIGHT0_ENABLED ? LIGHT0_COLOR : vec3(1.0);
		vec3 bright = mix(mix(vec3(1.0, 0.98, 0.95), sun_col, 0.35), cloud_tint, cloud_tint_amount);
		bright *= mix(1.0, 0.16, night * (1.0 - cloud_tint_amount));
		vec3 shade = mix(top_color, horizon_color, 0.6) * mix(0.85, 0.6, night);
		vec3 cloud = mix(shade, bright, lit);
		col = mix(col, cloud, density * smoothstep(0.0, 0.18, d.y) * 0.92);
	}

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
			float halo = exp(-a * sun_halo_falloff);
			col += (1.0 - night) * (vec3(1.0, 0.95, 0.85) * sun * sun_brightness + LIGHT0_COLOR * halo * sun_halo);
			col = mix(col, vec3(0.92, 0.94, 1.0), moon * night);
			col += vec3(0.5, 0.6, 0.9) * halo * 0.15 * night;
		}
	}
	COLOR = col;
}
