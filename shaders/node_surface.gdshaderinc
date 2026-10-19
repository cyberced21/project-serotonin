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

#ifdef ROCK
// A rock of many pieces is drawn as one mesh (ResourceNode merges them): UV2.x is the piece's
// index + 1 on every vertex (0 = not a piece), and these bits say which have broken off, 24 to a
// component (a float holds whole numbers that big exactly).
instance uniform vec4 pieces_gone = vec4(0.0);
// The baked shade (tools/blender/make_models.py bake_weathering); alpha 0 on fresh cut faces.
varying vec4 v_shade;

bool piece_gone(int i) {
	int w = i / 24;
	float word = w == 0 ? pieces_gone.x : w == 1 ? pieces_gone.y : w == 2 ? pieces_gone.z : pieces_gone.w;
	return ((uint(word) >> uint(i - w * 24)) & 1u) == 1u;
}
#endif

void vertex() {
	DETAIL_CAPTURE
#ifdef ROCK
	v_shade = COLOR;
	int piece = int(UV2.x + 0.5) - 1;
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
	int row = int(floor(UV.y * 8.0));
	float ore = float(row == 1 || row == 5);  // the palette's ore and metal rows glint
	ROUGHNESS = mix(0.95, ore_roughness, ore);
	METALLIC = ore * ore_metallic;
	SPECULAR = mix(0.2, 0.5, ore);
#else
	ROUGHNESS = 1.0;
#endif
	vec3 lit = mix(glow_color, glow_tint.rgb, glow_tint.a);
	ALBEDO = mix(mix(base, lit, glow * 0.6), vec3(1.0), flash);
	EMISSION = vec3(flash) * 0.6 + highlight_color * (0.08 + rim * 0.5) * highlight + lit * glow * 2.0;
#ifdef ROCK
	EMISSION += base * float(row == 1) * ore_glow;  // ore still reads down in the shade of a hole
#endif
}
