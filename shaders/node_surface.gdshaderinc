// The shared model surface (node_surface.gdshader, and node_foliage.gdshader with FOLIAGE defined).
// Hit flash, hover highlight and a colour tint are *instance* uniforms, so every node shares one
// material.
//   materials/node_surface.tres — greybox: no texture, colour from the `albedo` instance uniform
//                                  (Geometry > Instance Shader Parameters).
//   materials/node_palette.tres — models: colour from the palette atlas (art/palette.png) at the
//                                  mesh's UVs; `albedo` stays white (or tints, if you set it).

instance uniform vec4 albedo : source_color = vec4(1.0);
// Palette atlas; unset = white, so greybox meshes just show `albedo`. Nearest + no mipmaps so a
// face never bleeds into the swatch next to it.
uniform sampler2D palette : source_color, filter_nearest, repeat_disable, hint_default_white;
// 0 = normal, 1 = white. Tweened from code on each hit.
instance uniform float flash = 0.0;
// 1 while the crosshair is on this node.
instance uniform float highlight = 0.0;

// Detail slice for greybox meshes (no palette UVs): -1 = pick by palette row (models).
uniform int detail_layer = -1;

#include "res://shaders/detail.gdshaderinc"

#ifdef FOLIAGE
// Leaf cards (tools/blender/make_models.py leafy()): faces whose UV2.x >= 1 show a slice of the
// cut-out leaf texture (art/textures/leaves.png); UV2 is (1 + slice + u, v) on them, (0, 0) else.
global uniform sampler2DArray leaf_tex : filter_nearest_mipmap_anisotropic, repeat_disable;
// Shared wind (Project Settings > Shader Globals; the grass uses it too).
global uniform vec2 wind_direction;
global uniform float wind_strength;
// How far card tips flutter (m), and how much the whole crown leans with the gusts.
uniform float flutter = 0.05;
uniform float crown_sway = 0.012;
// How much light comes through backlit leaves.
uniform float translucency = 0.35;
varying float v_card;
#endif

uniform vec3 highlight_color : source_color = vec3(1.0, 0.92, 0.6);
// 0..1: lamps, lanterns and windows lit after dark (set by DayNightSky).
instance uniform float glow = 0.0;
uniform vec3 glow_color : source_color = vec3(1.0, 0.74, 0.4);
// Per-instance glow colour instead of the warm lamp one, used when its alpha is 1 (crystals).
instance uniform vec4 glow_tint : source_color = vec4(1.0, 1.0, 1.0, 0.0);

// The place's dressing (NodeTheme, set per node): theme_a = (moss, snow, wet, dust), each 0..1;
// theme_b = (hue shift in turns, value, saturation, vein glint); theme_c, the leaves instead of
// theme_b's colour = (autumn 0..1, value, saturation, shimmer: a rare look's glints, 0..1). The defaults leave the model as made.
instance uniform vec4 theme_a = vec4(0.0);
instance uniform vec4 theme_b = vec4(0.0, 1.0, 1.0, 1.0);
instance uniform vec4 theme_c = vec4(0.0, 1.0, 1.0, 0.0);
uniform vec3 moss_color : source_color = vec3(0.2, 0.32, 0.1);
uniform vec3 snow_color : source_color = vec3(0.9, 0.94, 1.0);
uniform vec3 dust_color : source_color = vec3(0.8, 0.74, 0.64);
#ifdef ROCK
// A rock's weathered skin pulled toward the ground's range, as the terrain's own rock is: the
// darkest stone lifted (linear) and the colour greyed a little, so it sits in the grass instead
// of standing out of it like a cut-out. Ore and fresh breaks stay as made.
uniform float skin_lift = 0.02;
uniform float skin_grey = 0.2;
#endif
varying vec3 v_world;         // world position and normal, for the dressing
varying vec3 v_world_normal;
varying float v_rise;         // height above the node's origin (m)
// Metres of damp soil and moss up a trunk's foot (set by ResourceNode on its trees; 0 = none), so
// it grows out of the ground instead of standing on it. By the mesh's own height, so the stump
// keeps it and the felled log doesn't. (Rocks have theirs baked: bake_weathering's soil.)
instance uniform float foot = 0.0;
uniform vec3 soil_color : source_color = vec3(0.36, 0.29, 0.2);
varying float v_local_y;

#ifdef ROCK
// A rock of many pieces is drawn as one mesh (ResourceNode merges them): UV2.x is the piece's
// index + 1 on every vertex (0 = not a piece), and these bits say which have broken off, 24 to a
// component (a float holds whole numbers that big exactly).
instance uniform vec4 pieces_gone = vec4(0.0);
// The fault (ResourceNode): a piece worked loose, centred at xyz (world) and w across; the fresh
// breaks round it, the walls of the gap it opened, go dark, so the gap reads as a deep crack
// rather than a pale line (w 0 = no fault).
instance uniform vec4 fault_shadow = vec4(0.0);
// The baked shade (tools/blender/make_models.py bake_weathering); alpha 0 on fresh cut faces.
varying vec4 v_shade;

bool piece_gone(int i) {
	int w = i / 24;
	float word = w == 0 ? pieces_gone.x : w == 1 ? pieces_gone.y : w == 2 ? pieces_gone.z : pieces_gone.w;
	return ((uint(word) >> uint(i - w * 24)) & 1u) == 1u;
}
#endif

#ifdef WALL
// An ore wall's layer (OreWall, node_wall.gdshader): the ore isn't in the mesh. Veins are sheets
// through the panel (its own space: x across, y up, z out of the face), each a plane (xyz normal,
// w its distance from the origin) bowed by two waves (vein_wave: xyz how tight and which way, w how
// far). piece_ore says which ore each piece carries (0 = none: the vein isn't drawn on it, so a
// piece shows ore exactly when it drops some); ore_uv is each ore's palette swatch.
// OreWall mirrors the vein maths (_vein_distance) to decide which pieces carry ore.
uniform int vein_count = 0;
uniform vec4 vein_plane[4];
uniform vec4 vein_wave[4];
uniform float vein_width[4];
uniform int piece_ore[96];
uniform vec2 ore_uv[8];
// The piece under the crosshair (its index; -1 none): the hover highlight and the hit flash light
// that piece alone, not the whole wall.
instance uniform float aim_piece = -1.0;
varying vec3 v_panel;
varying vec3 v_panel_normal;
varying flat int v_piece;

float vein_distance(int i, vec3 p) {
	vec4 pl = vein_plane[i];
	vec4 wv = vein_wave[i];
	float phase = pl.w * 3.1;
	float bow = sin(dot(p, wv.xyz) + phase) * 0.6 + sin(dot(p, wv.zxy * 1.7) + phase * 1.3) * 0.4;
	return dot(p, pl.xyz) - pl.w + bow * wv.w;
}

// 1 on a vein, easing off at its edges; `halo` 1 near one (where flecks of ore are scattered).
float vein_mask(vec3 p, out float halo) {
	float m = 0.0;
	halo = 0.0;
	for (int i = 0; i < vein_count; i++) {
		float w = vein_width[i];
		float d = abs(vein_distance(i, p));
		m = max(m, 1.0 - smoothstep(w * 0.55, w, d));
		halo = max(halo, 1.0 - smoothstep(w, w * 2.6, d));
	}
	return m;
}
#endif

void vertex() {
	DETAIL_CAPTURE
	v_local_y = VERTEX.y;
#ifdef ROCK
	v_shade = COLOR;
	int piece = int(UV2.x + 0.5) - 1;
#ifdef WALL
	v_panel = VERTEX;
	v_panel_normal = NORMAL;
	v_piece = piece;
#endif
	if (piece >= 0 && piece < 96 && piece_gone(piece)) {
		VERTEX = vec3(0.0);  // every corner on one point: the triangle draws nothing
	}
#endif
#ifdef FOLIAGE
	v_card = step(0.999, UV2.x);
	vec3 origin = MODEL_MATRIX[3].xyz;
	float phase = fract(sin(dot(origin.xz, vec2(12.9898, 78.233))) * 43758.5453) * 6.2831;
	float gust = 0.65 + 0.35 * sin(TIME * 0.4 + origin.x * 0.05 + origin.z * 0.04);
	float h = max(VERTEX.y, 0.0);
	// the crown leans with the wind (more the higher up), and each card flutters on its own
	vec2 lean = wind_direction * (sin(TIME * 0.9 + phase) * 0.5 + 0.6) * crown_sway * h * h * gust;
	float t = TIME * 3.1 + dot(VERTEX, vec3(3.7, 2.3, 4.1)) + phase;
	vec3 flap = vec3(sin(t), sin(t * 1.3 + 1.1) * 0.6, cos(t * 0.9)) * flutter * v_card * gust;
	VERTEX += (vec3(lean.x, 0.0, lean.y) + flap) * wind_strength;
#endif
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	v_rise = v_world.y - MODEL_MATRIX[3].y;
}

float theme_hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

// Smooth value noise, 0..1.
float theme_noise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(theme_hash(i), theme_hash(i + vec3(1, 0, 0)), f.x),
			mix(theme_hash(i + vec3(0, 1, 0)), theme_hash(i + vec3(1, 1, 0)), f.x), f.y),
			mix(mix(theme_hash(i + vec3(0, 0, 1)), theme_hash(i + vec3(1, 0, 1)), f.x),
			mix(theme_hash(i + vec3(0, 1, 1)), theme_hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

// How much of a field (0..1) an amount (0..1) covers: none at 0, the highest parts first, and at
// most about half of it (the stone always shows through).
float theme_cover(float field, float amount) {
	float edge = 1.0 - amount * 0.55;
	return amount <= 0.001 ? 0.0 : smoothstep(edge, edge + 0.12, field);
}

// `c` dressed by the place, as much as `skin` (0 = keep as made: ore, fresh breaks, cut wood);
// `leaf` (0..1) takes the leaves' colour (theme_c) instead of the bark and stone's (theme_b).
// `wet` comes back for the roughness.
vec3 theme_dress(vec3 c, float skin, float leaf, out float wet) {
	wet = 0.0;
	if (skin <= 0.0) {
		return c;
	}
	vec3 dressed = c;
	float up = v_world_normal.y;
	float n = theme_noise(v_world * 2.3) * 0.65 + theme_noise(v_world * 7.1) * 0.35;
	// wet: the foot darkens and shines
	wet = theme_cover(1.0 - smoothstep(0.0, 1.6, v_rise) * 0.8 + (n - 0.5) * 0.25, theme_a.z);
	dressed = mix(dressed, dressed * vec3(0.42, 0.46, 0.4), wet);  // dark, a touch of algae
	// moss: tops and hollows, broken up by the noise
	float moss = theme_cover((up * 0.5 + 0.5) * 0.55 + n * 0.45, theme_a.x);
	dressed = mix(dressed, moss_color * (0.75 + 0.5 * n), moss * 0.9);
	// dust: pale, over the tops, and a little everywhere
	float dust = theme_cover((up * 0.5 + 0.5) * 0.5 + n * 0.5, theme_a.w);
	dressed = mix(dressed, dust_color * (0.85 + 0.3 * n), dust * 0.75);
	dressed = mix(dressed, vec3(dot(dressed, vec3(0.333))), theme_a.w * 0.25);
	// colour (after the moss and dust, so they take the place's cast too): hue turned round the
	// grey axis, then saturation and value
	float angle = theme_b.x * (1.0 - leaf) * 6.2831853;
	vec3 k = vec3(0.57735);
	float cs = cos(angle);
	dressed = dressed * cs + cross(k, dressed) * sin(angle) + k * dot(k, dressed) * (1.0 - cs);
	float luma = dot(dressed, vec3(0.299, 0.587, 0.114));
	vec2 sat_value = mix(theme_b.zy, theme_c.zy, leaf);
	dressed = max(mix(vec3(luma), dressed, sat_value.x) * sat_value.y, vec3(0.0));
	// autumn: patches of the canopy turned gold
	float autumn = theme_cover(theme_noise(v_world * 0.9 + 7.0), theme_c.x) * leaf;
	dressed = mix(dressed, luma * vec3(1.75, 1.2, 0.4), autumn);
	// snow: on whatever faces up
	float snow = theme_cover(smoothstep(0.3, 0.95, up) * 0.8 + n * 0.2, theme_a.y);
	dressed = mix(dressed, snow_color * (0.92 + 0.08 * n), snow);
	wet *= 1.0 - snow;
	return mix(c, dressed, skin);
}

void fragment() {
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.0);
	vec3 base = texture(palette, UV).rgb * albedo.rgb;
#ifdef FOLIAGE
	if (v_card > 0.5) {
		float slice = floor(UV2.x - 1.0);
		vec2 cuv = vec2((UV2.x - 1.0 - slice) / 0.998, UV2.y);
		vec4 leaf = texture(leaf_tex, vec3(cuv, slice));
		base *= 0.45 + 0.75 * leaf.r;
		// mipmaps thin the cut-outs with distance: fatten them back up
		float a = leaf.a * (1.0 + clamp(length(VERTEX) / 25.0, 0.0, 1.5));
		// cards seen edge-on smear into streaks: fade them out (the true face, not the soft normal)
		vec3 face = normalize(cross(dFdx(VERTEX), dFdy(VERTEX)));
		a *= smoothstep(0.12, 0.35, abs(dot(face, VIEW)));
		ALPHA = clamp(a, 0.0, 1.0);
		if (!FRONT_FACING) {
			NORMAL = -NORMAL;  // both sides share the canopy's outward normal
		}
		BACKLIGHT = base * translucency;
		rim *= 0.25;  // (so many cards are seen edge-on that the highlight's rim would gild the crown)
	} else {
		base *= DETAIL(UV);
		ALPHA = 1.0;
	}
	ALPHA_SCISSOR_THRESHOLD = 0.5;
#else
	base *= detail_layer < 0 ? DETAIL(UV) : DETAIL_LAYER(detail_layer);
#endif
#ifdef ROCK
	// weathered outside (the baked shade), fresh breaks (alpha 0) clean and a touch brighter
	float fresh = 1.0 - step(0.5, v_shade.a);
	// (baked as seen, sRGB: brought into linear like any colour, or the shading barely shows.
	// Squared, near enough: pow(shade, 2.2) came out NaN on some pixels, which the glow smeared
	// into big white blobs)
	base *= mix(v_shade.rgb * v_shade.rgb, vec3(fresh_brightness), fresh);
	if (fault_shadow.w > 0.0) {
		float gap = 1.0 - smoothstep(fault_shadow.w * 0.5, fault_shadow.w, distance(v_world, fault_shadow.xyz));
#ifdef WALL
		// a wall's loose slab: only the walls of its gap, not the fresh face round it
		gap *= 1.0 - smoothstep(0.5, 0.9, abs(v_panel_normal.z));
#endif
		base *= mix(1.0, 0.1, fresh * gap);
	}
	int row = int(floor(UV.y * 8.0));
	float ore = float(row == 1 || row == 5);  // the palette's ore and metal rows glint
#ifdef WALL
	vec3 wall_glint = vec3(0.0);
	int kind = v_piece >= 0 && v_piece < 96 ? piece_ore[v_piece] : 0;
	if (kind > 0) {
		// ragged edges (the point looked up wanders a little), and flecks of ore scattered round it
		vec3 wander = vec3(theme_noise(v_panel * 5.0), theme_noise(v_panel * 5.0 + 11.0), theme_noise(v_panel * 5.0 + 23.0)) - 0.5;
		float halo;
		float vein = vein_mask(v_panel + wander * 0.12, halo);
		float fleck = step(0.8, theme_noise(v_panel * 16.0 + 4.0)) * halo;
		vein = max(vein, fleck);
		// on the weathered face the ore is dulled; a fresh break shows it bright; never one flat colour
		float grain = theme_noise(v_panel * 9.0 + 2.0);
		vec3 ore_c = texture(palette, ore_uv[kind]).rgb * mix(0.62, 1.12, fresh) * mix(0.72, 1.18, grain);
		base = mix(base, ore_c, vein);
		ore = max(ore, vein);
		// glints: points of the vein catching the light as you move past them, so a seam reads
		// even at the back of a dark alcove
		float spark = smoothstep(0.86, 0.97, theme_noise(v_panel * 26.0 + VIEW * 2.5));
		wall_glint = ore_c * spark * vein;
		row = vein > 0.5 ? 1 : row;  // (glows like the palette's ore row, below)
	}
#endif
	float skin = (1.0 - fresh) * (1.0 - ore);
	base = mix(base, mix(base, vec3(dot(base, vec3(0.299, 0.587, 0.114))), skin_grey) + skin_lift, skin);
	float wet;
	base = theme_dress(base, (1.0 - fresh) * (1.0 - ore), 0.0, wet);  // the skin, never the ore or a break
	base *= mix(1.0, theme_b.w, ore);
	ROUGHNESS = mix(mix(0.95, 0.4, wet), ore_roughness, ore);
	METALLIC = ore * ore_metallic * theme_b.w;
	SPECULAR = mix(mix(0.2, 0.45, wet), 0.5, ore);
#else
	// the palette's leaves row takes the leaves' colour; cut wood (the pale wood swatches the axe's
	// notch and the end grain use, see TrunkCarve) stays as made
	int row = int(floor(UV.y * 8.0));
	float cut_wood = float(row == 2 && UV.x >= 0.625);
	if (foot > 0.0) {  // a ragged line of soil, going over to moss here and there
		float n = theme_noise(v_world * 3.0);
		float band = 1.0 - smoothstep(0.0, 1.0, v_local_y / foot + (n - 0.5) * 0.8);
		vec3 grime = mix(soil_color, moss_color, smoothstep(0.35, 0.75, theme_noise(v_world * 1.7 + 3.0)));
		base = mix(base, grime * (0.8 + 0.4 * n), band * 0.7 * (1.0 - cut_wood));
	}
	float wet;
	base = theme_dress(base, 1.0 - cut_wood, float(row == 3), wet);
	ROUGHNESS = mix(1.0, 0.5, wet);
#endif
	vec3 lit = mix(glow_color, glow_tint.rgb, glow_tint.a);
	float lift = highlight;
	float white = flash;
#ifdef WALL
	float aimed = float(v_piece >= 0 && abs(float(v_piece) - aim_piece) < 0.5);
	lift *= aimed;
	white *= aimed;
#endif
	ALBEDO = mix(mix(base, lit, glow * 0.6), vec3(1.0), white);
	// highlight: the node lifted in its own colours, a thin warm rim round its edges (a flat yellow
	// wash swamped dark leaves and pale bark alike)
	EMISSION = vec3(white) * 0.6 + (base * 0.22 + highlight_color * rim * rim * 0.3) * lift + lit * glow * 2.0;
	// shimmer: a rare look's (NodeTheme) slow glints, so it's spotted from a way off
	float glint = smoothstep(0.78, 0.95, theme_noise(v_world * 5.0 + vec3(0.0, TIME * 0.6, 0.0)));
	EMISSION += base * glint * theme_c.w * 2.5;
#ifdef ROCK
	EMISSION += base * float(row == 1) * ore_glow * theme_b.w;  // ore still reads down in the shade of a hole
#endif
#ifdef WALL
	EMISSION += wall_glint;
#endif
}
