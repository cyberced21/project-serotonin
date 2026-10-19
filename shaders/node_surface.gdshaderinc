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

void vertex() {
	DETAIL_CAPTURE
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
	vec3 lit = mix(glow_color, glow_tint.rgb, glow_tint.a);
	ALBEDO = mix(mix(base, lit, glow * 0.6), vec3(1.0), flash);
	ROUGHNESS = 1.0;
	EMISSION = vec3(flash) * 0.6 + highlight_color * (0.08 + rim * 0.5) * highlight + lit * glow * 2.0;
}
