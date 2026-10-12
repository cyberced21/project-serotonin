shader_type spatial;
render_mode specular_disabled;

// Shared surface for gatherable nodes. Hit flash, hover highlight and a colour tint are
// *instance* uniforms, so every node shares one material.
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

uniform vec3 highlight_color : source_color = vec3(1.0, 0.92, 0.6);

void fragment() {
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.0);
	vec3 base = texture(palette, UV).rgb * albedo.rgb;
	ALBEDO = mix(base, vec3(1.0), flash);
	ROUGHNESS = 1.0;
	EMISSION = vec3(flash) * 0.6 + highlight_color * (0.08 + rim * 0.5) * highlight;
}
