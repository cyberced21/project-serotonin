shader_type spatial;
render_mode specular_disabled, cull_disabled;

// node_surface for meshes with leaf cards (tree canopies, bushes): the cards are cut out of the
// leaf texture, flutter in the wind and let light through. Picked automatically for any mesh with
// a UV2 layer (see PaletteMaterial).
#define FOLIAGE
#include "res://shaders/node_surface.gdshaderinc"
