shader_type spatial;
render_mode unshaded, cull_front, depth_draw_never, shadows_disabled;
stencil_mode read, compare_not_equal, 1;

// Silhouette version of ghost_outline: the inflated back-face shell, drawn only where
// ghost_mask_stencil hasn't marked the stencil — i.e. outside every piece of the node.

uniform vec4 color : source_color = vec4(1.0, 1.0, 1.0, 0.5);
// Outline thickness (m).
uniform float width = 0.035;

void vertex() {
	// push out from the mesh centre, not along the (split, flat-shaded) normals — see ghost_outline
	VERTEX += normalize(VERTEX) * width;
}

void fragment() {
	ALBEDO = color.rgb;
	ALPHA = color.a;
}
