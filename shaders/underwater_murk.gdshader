shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_test_disabled, depth_draw_never, fog_disabled, shadows_disabled;

// The underwater view, second pass: the water's own murk (light scattered in it) filling in with
// distance, as bright as the daylight getting in. See underwater.gdshader.

#include "res://shaders/underwater.gdshaderinc"

void fragment() {
	float d = water_between(SCREEN_UV, INV_PROJECTION_MATRIX, INV_VIEW_MATRIX);
	ALBEDO = murk_color * under_light * (1.0 - exp(-scatter * d));
}
