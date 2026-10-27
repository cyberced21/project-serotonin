shader_type spatial;

// An ore wall's layer (OreWall): node_rock, plus veins of ore threaded through it from the
// panel's own numbers (see WALL in node_surface.gdshaderinc), and the highlight and hit flash on
// the piece under the crosshair alone.

uniform float ore_roughness = 0.5;
uniform float ore_metallic = 0.35;
uniform float ore_glow = 0.15;
uniform float fresh_brightness = 1.1;

#define ROCK
#define WALL
#include "res://shaders/node_surface.gdshaderinc"
