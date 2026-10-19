class_name PaletteMaterial
## Picks the shared material for a palette-coloured model mesh: the leaf-card foliage material
## (shaders/node_foliage.gdshader) for meshes with leaf cards, marked by a UV2 layer (see
## tools/blender/make_models.py leafy()); the rock material (shaders/node_rock.gdshader) for
## meshes with a baked shade in their vertex colour (bake_weathering: rocks, ore, stonework);
## the plain palette one for everything else.

const PALETTE := preload("res://materials/node_palette.tres")
const FOLIAGE := preload("res://materials/node_foliage.tres")
const ROCK := preload("res://materials/node_rock.tres")


static func has_cards(mesh: Mesh) -> bool:
	return mesh != null and mesh.get_surface_count() > 0 \
			and (mesh.surface_get_format(0) & Mesh.ARRAY_FORMAT_TEX_UV2) != 0


static func has_shade(mesh: Mesh) -> bool:
	return mesh != null and mesh.get_surface_count() > 0 \
			and (mesh.surface_get_format(0) & Mesh.ARRAY_FORMAT_COLOR) != 0


static func for_mesh(mesh: Mesh) -> Material:
	return FOLIAGE if has_cards(mesh) else ROCK if has_shade(mesh) else PALETTE
