shader_type spatial;
render_mode specular_disabled;

// Shared surface for gatherable nodes. Colour, hit flash and hover highlight are *instance*
// uniforms, so every node can use the same material (materials/node_surface.tres).
// Set `albedo` per mesh under Geometry > Instance Shader Parameters.
// When the palette atlas arrives, `albedo` gets replaced by a palette texture lookup.

instance uniform vec4 albedo : source_color = vec4(1.0);
// 0 = normal, 1 = white. Tweened from code on each hit.
instance uniform float flash = 0.0;
// 1 while the crosshair is on this node.
instance uniform float highlight = 0.0;

uniform vec3 highlight_color : source_color = vec3(1.0, 0.92, 0.6);

void fragment() {
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.0);
	ALBEDO = mix(albedo.rgb, vec3(1.0), flash);
	ROUGHNESS = 1.0;
	EMISSION = vec3(flash) * 0.6 + highlight_color * (0.08 + rim * 0.5) * highlight;
}
