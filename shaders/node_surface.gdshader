shader_type spatial;
render_mode specular_disabled;

// Every model's surface: palette colour, detail texture, hit flash, highlight, night glow.
// The code is in node_surface.gdshaderinc; node_foliage.gdshader is the leaf-card version.
#include "res://shaders/node_surface.gdshaderinc"
