shader_type spatial;
render_mode blend_mul, unshaded, cull_disabled, depth_test_disabled, depth_draw_never, fog_disabled, shadows_disabled;

// The underwater view, first pass (UnderwaterView, plans/water.md): what's behind the water loses
// its light colour by colour with every metre of water in front of it. The next pass
// (underwater_murk.gdshader) adds the water's own murk back in.

#include "res://shaders/underwater.gdshaderinc"

void fragment() {
	float d = water_between(SCREEN_UV, INV_PROJECTION_MATRIX, INV_VIEW_MATRIX);
	ALBEDO = exp(-(absorb + scatter) * d);
}
