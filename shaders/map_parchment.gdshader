shader_type canvas_item;
// The maps' look (MapView): the world inked on old parchment. Reads MapData's two textures:
// height_tex (R ground height, G water depth) and kind_tex (R ground texture id, G biome, B road,
// A forest). The view is a window onto the world: `view_center` (world XZ) at the middle,
// `metres_per_px` across, `view_px` the control's size in pixels.
//
// Paper: warm fibres and stains, fixed to the world so they pan with it. Land: a pale wash per
// kind of ground (forest green, fields straw, rock grey-brown, snow near white), shaded from the
// north-west by the slope, with brown contour lines every CONTOUR metres (a darker one every fifth).
// Forest: little tree marks, one per cell. Water: a blue-green wash, deeper darker, an ink shore
// line and a couple of ripple lines along it. Roads: dark ink, paths fainter. `circular`: clipped to
// a circle (the minimap). `vignette`: darkened, burnt edges (the big map).

uniform sampler2D height_tex : filter_linear, repeat_disable;
uniform sampler2D kind_tex : filter_nearest, repeat_disable;
uniform sampler2D kind_smooth : filter_linear, repeat_disable;  // (the same texture, smoothed)
uniform vec4 world_rect = vec4(-256.0, -256.0, 512.0, 512.0);  // origin xz, size
uniform vec2 height_range = vec2(0.0, 60.0);
uniform vec2 view_center = vec2(0.0);
uniform float metres_per_px = 1.0;
uniform vec2 view_px = vec2(400.0);
uniform bool circular = false;
uniform float vignette = 0.0;
uniform float ink_scale = 1.0;  // line widths, in screen pixels

const float CONTOUR = 4.0;
const vec3 PAPER = vec3(0.90, 0.81, 0.62);
const vec3 PAPER_DARK = vec3(0.74, 0.60, 0.40);
const vec3 INK = vec3(0.30, 0.20, 0.12);
const vec3 WATER = vec3(0.47, 0.62, 0.60);
const vec3 WATER_DEEP = vec3(0.30, 0.45, 0.48);
const vec3 FOREST = vec3(0.58, 0.64, 0.42);
const vec3 FIELD = vec3(0.92, 0.80, 0.50);
const vec3 ROCK = vec3(0.72, 0.64, 0.52);
const vec3 SNOW = vec3(0.95, 0.93, 0.88);
const vec3 DIRT = vec3(0.80, 0.68, 0.50);
const vec3 TABLE = vec3(0.16, 0.10, 0.06);
const float PLAZA_REACH = 4.0;  // texels

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		v += a * noise(p);
		p *= 2.03;
		a *= 0.5;
	}
	return v;
}

// A line `width_px` screen pixels wide where `v` crosses whole multiples of `every`.
// None on flat ground (a plateau that sits exactly on a multiple would be all line).
float iso_line(float v, float every, float width_px) {
	float d = abs(fract(v / every + 0.5) - 0.5) * every;
	float fw = fwidth(v);
	float w = max(fw, 1e-6) * width_px;
	return (1.0 - smoothstep(w * 0.5, w, d)) * smoothstep(0.0005, 0.003, fw);
}

void fragment() {
	vec2 px = (UV - 0.5) * view_px;
	if (circular && length(px) > min(view_px.x, view_px.y) * 0.5) {
		discard;
	}
	vec2 world = view_center + px * metres_per_px;
	vec2 uv = (world - world_rect.xy) / world_rect.zw;

	// the paper, fixed to the world
	float fibres = fbm(world * 0.35) * 0.6 + fbm(world * 0.04) * 0.4;
	float stain = smoothstep(0.55, 0.8, fbm(world * 0.012 + 7.0));
	vec3 col = mix(PAPER, PAPER_DARK, fibres * 0.35 + stain * 0.35);

	bool inside = uv.x >= 0.0 && uv.y >= 0.0 && uv.x <= 1.0 && uv.y <= 1.0;
	vec2 hd = texture(height_tex, uv).rg;
	if (inside && hd.r > -999.0) {
		float h = hd.r;
		float depth = hd.g;
		vec4 kind = texture(kind_tex, uv);
		vec4 smooth_kind = texture(kind_smooth, uv);
		int tex = int(round(kind.r * 255.0));
		float h01 = clamp((h - height_range.x) / max(height_range.y - height_range.x, 1.0), 0.0, 1.0);

		// slope shading from the north-west
		vec2 e = 1.0 / vec2(textureSize(height_tex, 0));
		float hx = texture(height_tex, uv + vec2(e.x, 0.0)).r - texture(height_tex, uv - vec2(e.x, 0.0)).r;
		float hz = texture(height_tex, uv + vec2(0.0, e.y)).r - texture(height_tex, uv - vec2(0.0, e.y)).r;
		float step_m = world_rect.z * e.x * 2.0;
		vec2 grad = vec2(hx, hz) / step_m;
		float shade = clamp(dot(normalize(vec3(-grad.x, 1.0, -grad.y)), normalize(vec3(-0.6, 0.9, -0.6))), 0.0, 1.0);

		// the ground's wash
		vec3 wash = PAPER;
		float amount = 0.0;
		if (tex == 4 || tex == 6) { wash = FIELD; amount = 0.45; }       // meadow, crops
		if (tex == 5) { wash = ROCK; amount = 0.5; }                      // quarry stone
		if (smooth_kind.a > 0.5) { wash = FOREST; amount = 0.55; }        // forest
		float high = smoothstep(0.62, 0.85, h01);
		wash = mix(wash, ROCK, high * 0.6 * (1.0 - smooth_kind.a));
		amount = max(amount, high * 0.45);
		float snow = smoothstep(0.8, 0.95, h01);
		wash = mix(wash, SNOW, snow);
		amount = max(amount, snow * 0.7);
		col = mix(col, wash * (0.85 + 0.15 * fibres), amount);
		col *= mix(0.72, 1.06, shade);

		// contours
		float c = iso_line(h, CONTOUR, 1.1 * ink_scale) * 0.28 + iso_line(h, CONTOUR * 5.0, 1.6 * ink_scale) * 0.3;
		col = mix(col, INK, c * (1.0 - smoothstep(0.0, 0.05, depth)));

		// forest: a tree mark in each cell (a dot with a little stem)
		if (smooth_kind.a > 0.5) {
			vec2 cell_size = vec2(6.0);
			vec2 cell = floor(world / cell_size);
			vec2 jitter = vec2(hash(cell), hash(cell + 3.1)) * 0.5 + 0.25;
			vec2 local = (fract(world / cell_size) - jitter) * cell_size;
			float r = 1.15 + hash(cell + 9.0) * 0.6;
			float crown = 1.0 - smoothstep(r - 0.35, r, length(local + vec2(0.0, 0.5)));
			float stem = (1.0 - smoothstep(0.15, 0.35, abs(local.x))) * step(-0.2, local.y) * step(local.y, 1.4);
			float tree = max(crown, stem) * step(0.3, hash(cell + 5.0));
			col = mix(col, mix(vec3(0.33, 0.40, 0.22), INK, 0.3), tree * 0.75);
		}

		// water
		if (depth > 0.0) {
			float d = smoothstep(0.0, 1.4, depth);
			vec3 w = mix(WATER, WATER_DEEP, d) * (0.9 + 0.1 * fibres);
			float ripple = iso_line(depth, 0.35, 0.9 * ink_scale) * (1.0 - smoothstep(0.3, 0.9, depth));
			col = mix(w, INK, ripple * 0.35);
		}
		float shore = iso_line(depth - 0.02, 1000.0, 1.6 * ink_scale);
		col = mix(col, INK, shore * 0.8 * step(0.0005, fwidth(depth)));

		// roads and paths; a broad patch of path ground (the Clearing, a village square) is a plaza:
		// a pale dirt wash, not a blot of ink. It's a plaza if the path goes on PLAZA_REACH out
		// every way.
		float road = smooth_kind.b;
		vec2 o = e * PLAZA_REACH;
		float around = min(min(texture(kind_smooth, uv + vec2(o.x, 0.0)).b, texture(kind_smooth, uv - vec2(o.x, 0.0)).b),
				min(texture(kind_smooth, uv + vec2(0.0, o.y)).b, texture(kind_smooth, uv - vec2(0.0, o.y)).b));
		float plaza = smoothstep(0.3, 0.45, around) * smoothstep(0.3, 0.45, road);
		col = mix(col, DIRT * (0.9 + 0.1 * fibres), plaza * 0.5);
		road *= 1.0 - plaza;
		col = mix(col, INK * 0.9, smoothstep(0.6, 0.85, road) * 0.85);
		col = mix(col, INK * 1.3, smoothstep(0.32, 0.48, road) * (1.0 - smoothstep(0.6, 0.85, road)) * 0.45);
	}

	// past the edge of the world: the dark table under the map, the sheet's edge burnt
	vec2 ow = max(world_rect.xy - world, world - (world_rect.xy + world_rect.zw));
	float out_m = max(ow.x, ow.y) + (fbm(world * 0.08) - 0.5) * 10.0;
	if (!(hd.r > -999.0) && out_m < 0.0) {
		out_m = 0.0;  // (inside the rectangle but no ground: count as the edge)
	}
	col = mix(col, vec3(0.32, 0.2, 0.1), smoothstep(-6.0, 0.0, out_m) * 0.7);
	col = mix(col, TABLE * (0.85 + 0.3 * fbm(world * 0.02)), smoothstep(0.0, 3.0, out_m));

	// the big map's burnt edges
	if (vignette > 0.0) {
		vec2 q = abs(UV - 0.5) * 2.0;
		float edge = max(q.x, q.y) + (fbm(UV * 9.0) - 0.5) * 0.08;
		col *= 1.0 - vignette * smoothstep(0.75, 1.0, edge) * 0.6;
		col = mix(col, vec3(0.25, 0.15, 0.08), vignette * smoothstep(0.96, 1.02, edge));
	}
	COLOR = vec4(col, 1.0);
}
