shader_type spatial;
render_mode unshaded, cull_back, depth_draw_never, shadows_disabled;
stencil_mode write, compare_always, 1;

// Silhouette version of ghost_mask: marks every pixel any piece of the ghost covers in the
// stencil buffer (drawing nothing), so ghost_outline_stencil only draws outside the union of
// all the pieces — one clean outline around the whole node instead of one per piece.

void fragment() {
	ALBEDO = vec3(0.0);
	ALPHA = 0.0;
}
