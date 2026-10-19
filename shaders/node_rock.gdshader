shader_type spatial;

// Rocks: node_surface, weathered outside and fresh inside. The outside multiplies in the shade
// baked into the vertex colour (darker crevices and foot, worn edges, moss); faces broken open
// (vertex alpha 0) show clean, slightly brighter stone; ore glints. Also hides broken-off pieces
// of a rock drawn as one mesh (pieces_gone). The code is in node_surface.gdshaderinc (ROCK).

// How the ore (the palette's ore row) catches the light.
uniform float ore_roughness = 0.42;
uniform float ore_metallic = 0.4;
// Fresh breaks against the weathered skin.
uniform float fresh_brightness = 1.1;

#define ROCK
#include "res://shaders/node_surface.gdshaderinc"
