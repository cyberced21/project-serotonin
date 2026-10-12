shader_type spatial;
render_mode unshaded, cull_back, depth_draw_always, shadows_disabled;

// Invisible, depth-only pass for the respawn ghost: hides the inside of the ghost_outline
// shell so only its rim (the outline) shows. Its next_pass is the outline material.

void fragment() {
	ALBEDO = vec3(0.0);
	ALPHA = 0.0;
}
