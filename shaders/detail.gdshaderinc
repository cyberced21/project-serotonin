// Surface detail over the palette colours (art/textures/detail.png, made by tools/make_textures.py):
// a small greyscale texture per palette row (stone, ore, wood, leaves, terrain, metal, accent,
// neutral), projected from three sides in the mesh's own space (triplanar), so models need no
// UVs for it and the pattern stays stuck to things that move (felled trees, chips, the tool).
// Nearest filtering keeps the texels chunky up close; mipmaps fade it to flat colour far away.
//
// Use: in vertex(), DETAIL_CAPTURE BEFORE moving VERTEX; in fragment(),
//   base *= DETAIL(UV);  (or DETAIL_LAYER(layer) for a fixed slice)
// (Macros, since shader functions can't touch varyings.)

// Global (Project Settings > Shader Globals), so every material gets it without wiring.
global uniform sampler2DArray detail_tex : filter_nearest_mipmap, repeat_enable;
// Texture repeats per metre (128 px a tile: 0.5 = 64 texels a metre).
uniform float detail_scale = 0.5;
// Overall strength; each palette row also has its own (DETAIL_ROW_STRENGTH).
uniform float detail_strength = 1.0;

// stone, ore, wood, leaves, terrain, metal, accent, neutral
const float DETAIL_ROW_STRENGTH[8] = float[](0.55, 0.45, 0.6, 0.55, 0.45, 0.35, 0.3, 0.25);

varying vec3 v_detail_pos;
varying vec3 v_detail_nrm;

#define DETAIL_CAPTURE v_detail_pos = VERTEX; v_detail_nrm = NORMAL;
#define DETAIL(uv) detail_factor(uv, v_detail_pos, v_detail_nrm)
#define DETAIL_LAYER(layer) detail_factor_layer(layer, v_detail_pos, v_detail_nrm)

float detail_sample(float layer, vec3 pos, vec3 nrm) {
	vec3 w = pow(abs(normalize(nrm)), vec3(8.0));
	w /= (w.x + w.y + w.z);
	vec3 p = pos * detail_scale;
	float x = texture(detail_tex, vec3(p.zy, layer)).r;
	float y = texture(detail_tex, vec3(p.xz, layer)).r;
	float z = texture(detail_tex, vec3(p.xy, layer)).r;
	return x * w.x + y * w.y + z * w.z;
}

// Multiplier for a fixed slice (0..7).
float detail_factor_layer(int layer, vec3 pos, vec3 nrm) {
	float d = detail_sample(float(layer), pos, nrm);
	return 1.0 + (d - 0.5) * 2.0 * DETAIL_ROW_STRENGTH[layer] * detail_strength;
}

// Multiplier for a palette face: the palette row its UV sits in picks the slice.
float detail_factor(vec2 uv, vec3 pos, vec3 nrm) {
	return detail_factor_layer(clamp(int(floor(uv.y * 8.0)), 0, 7), pos, nrm);
}
