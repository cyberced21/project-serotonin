shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

// One expanding ring on the water surface (footsteps, strikes, fleeing fish). Drawn on a flat
// quad; `progress` 0 -> 1 grows the ring and fades it. Driven by scripts/water_ripple.gd.

uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform vec4 color : source_color = vec4(1.0, 1.0, 1.0, 0.6);
// Ring thickness as a fraction of the quad's radius.
uniform float thickness = 0.08;

void fragment() {
	float r = length(UV - 0.5) * 2.0;           // 0 at centre, 1 at the quad edge
	float ring_r = mix(0.1, 0.95, progress);
	float ring = 1.0 - smoothstep(0.0, thickness, abs(r - ring_r));
	ALBEDO = color.rgb;
	ALPHA = ring * color.a * (1.0 - progress);
}
