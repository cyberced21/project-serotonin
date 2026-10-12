shader_type spatial;
render_mode unshaded, cull_front, depth_draw_never, shadows_disabled;

// Outline-only "ghost" of a depleted node, showing where it will grow back.
// Drawn as an inflated back-face shell; the matching ghost_mask pass (same mesh, drawn first)
// writes depth for the inside, so only the rim around the silhouette shows.

uniform vec4 color : source_color = vec4(1.0, 1.0, 1.0, 0.5);
// Outline thickness (m).
uniform float width = 0.035;

void vertex() {
	// Push out from the mesh centre rather than along normals: flat-shaded boxes have split
	// normals, and pushing those apart would crack the outline open at every corner.
	VERTEX += normalize(VERTEX) * width;
}

void fragment() {
	ALBEDO = color.rgb;
	ALPHA = color.a;
}
