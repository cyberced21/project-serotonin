// Terrain shader for Project Serotonin: smooth, textured ground (Valheim-style).
// Based on Terrain3D's extras/shaders/minimum.gdshader (MIT, © 2023-2026 Cory Petkovsek,
// Roope Palmroos, and Contributors) — the vertex / geomorph code below is theirs, unchanged.
//
// The look: smooth normals from the heightmap; each vertex is covered by one surface (grass on
// flats, dirt on slopes, rock on cliffs, sand low down, snow up high, and the biome surfaces and
// paths the control map marks), coloured from the palette below and textured with a chunky,
// nearest-filtered slice of art/textures/ground.png (global `ground_tex`, made by
// tools/make_textures.py). Neighbouring surfaces meet in ragged, height-blended borders.
// Depth (plans/ground-depth.md): each slice's height (which also marks its second material) and
// per-texel normals light tufts and pebbles and shade their gaps up close; a
// coarser layer, colour patches, shaded hollows, rock ledges and a wandering snow line on top.
// Terrain3D's Color tool still works: painted colour multiplies the surface colour.

shader_type spatial;
render_mode blend_mix,depth_draw_opaque,cull_back,diffuse_lambert,specular_disabled,skip_vertex_transform;

// Defined Constants
#define SKIP_PASS 0
#define VERTEX_PASS 1
#define FRAGMENT_PASS 2

#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
    #define fma(a, b, c) ((a) * (b) + (c))
    #define dFdxCoarse(a) dFdx(a)
    #define dFdyCoarse(a) dFdy(a)
#endif

// Private uniforms
// Commented uniforms aren't needed for this shader, but are available for your own needs.
uniform vec3 _camera_pos = vec3(0.f);
uniform float _mesh_size = 48.f;
uniform uint _background_mode = 1u; // NONE = 0, FLAT = 1, NOISE = 2
uniform uint _mouse_layer = 0x80000000u; // Layer 32
uniform float _vertex_spacing = 1.0;
uniform float _vertex_density = 1.0; // = 1/_vertex_spacing
uniform float _region_size = 1024.0;
uniform float _region_texel_size = 0.0009765625; // = 1/1024
uniform int _region_map_size = 32;
uniform int _region_map[1024];
//uniform vec2 _region_locations[1024];
//uniform float _texture_uv_scale_array[32];
//uniform float _texture_detile_array[32];
//uniform vec4 _texture_color_array[32];
uniform highp sampler2DArray _height_maps : repeat_disable;
uniform highp sampler2DArray _control_maps : repeat_disable;
uniform highp sampler2DArray _color_maps : source_color, filter_nearest, repeat_disable;
//uniform highp sampler2DArray _texture_array_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;

// Public Uniforms
group_uniforms palette;
uniform vec3 grass_color : source_color = vec3(0.29, 0.55, 0.21);
uniform vec3 grass_color_2 : source_color = vec3(0.40, 0.63, 0.23);
uniform vec3 dirt_color : source_color = vec3(0.52, 0.39, 0.27);
uniform vec3 rock_color : source_color = vec3(0.50, 0.48, 0.46);
uniform vec3 sand_color : source_color = vec3(0.80, 0.74, 0.55);
uniform vec3 snow_color : source_color = vec3(0.95, 0.97, 1.0);
// Pond / lake bed below `bed_height` — dark and muddy so fish stand out against it. Under the water
// (plans/water.md) it's silt: sandy on the shallow shelves, going to this mud in the deep, whatever
// the ground above it was painted (a road or a biome that ran there before the lake grew).
uniform vec3 bed_color : source_color = vec3(0.36, 0.34, 0.24);
uniform vec3 silt_color : source_color = vec3(0.62, 0.57, 0.42);
// Below this much water (m) the bed is all mud.
uniform float silt_depth = 2.5;
// Dirt paths: cells painted with this texture id (control map base texture; see
// tools/generate_test_terrain.gd, or Terrain3D's texture paint tool) on walkable slopes.
uniform vec3 path_color : source_color = vec3(0.66, 0.50, 0.34);
uniform int path_texture = 1;
group_uniforms;
// Biome surfaces, by control-map texture id (scripts/world_map.gd TEX_*). Cliffs stay rock.
group_uniforms biomes;
uniform vec3 road_color : source_color = vec3(0.66, 0.63, 0.57);
uniform int road_texture = 2;
// Better roads (plans/road-travel.md: the Roads autoload paints them over a road's cells): packed
// earth, then cobbles (stone setts). Packed earth is paler and sandier than a dirt path, so a
// packed lane reads as bettered (plans/roads-everywhere.md).
uniform vec3 packed_color : source_color = vec3(0.76, 0.65, 0.47);
uniform int packed_texture = 7;
uniform vec3 cobble_color : source_color = vec3(0.60, 0.60, 0.58);
uniform int cobble_texture = 8;
uniform vec3 forest_color : source_color = vec3(0.17, 0.37, 0.18);
uniform vec3 forest_color_2 : source_color = vec3(0.23, 0.43, 0.20);
// Needle litter: patches on the forest floor, and its slopes.
uniform vec3 needle_color : source_color = vec3(0.48, 0.32, 0.19);
uniform int forest_texture = 3;
uniform vec3 field_color : source_color = vec3(0.49, 0.66, 0.24);
uniform vec3 field_color_2 : source_color = vec3(0.58, 0.70, 0.26);
uniform int field_texture = 4;
uniform vec3 quarry_color : source_color = vec3(0.71, 0.67, 0.59);
// Quarry walls alternate two rock colours in bands this many metres tall.
uniform vec3 quarry_rock : source_color = vec3(0.56, 0.53, 0.49);
uniform vec3 quarry_rock_2 : source_color = vec3(0.47, 0.44, 0.41);
uniform float quarry_band = 1.25;
uniform int quarry_texture = 5;
uniform vec3 crop_color : source_color = vec3(0.84, 0.70, 0.36);
uniform vec3 crop_color_2 : source_color = vec3(0.79, 0.64, 0.31);
uniform int crop_texture = 6;
group_uniforms;
group_uniforms bands;
// Slope is the facet normal's Y: 1 = flat, 0 = vertical wall.
uniform float dirt_slope : hint_range(0.0, 1.0) = 0.86;
uniform float rock_slope : hint_range(0.0, 1.0) = 0.68;
// World heights (m).
uniform float sand_height = -2.0;
uniform float bed_height = -0.4;
uniform float snow_height = 40.0;
// Size (m) of the patches the two grass colours alternate in.
uniform float patch_size = 7.0;
// Random tint per terrain cell, 0 = none.
uniform float variation : hint_range(0.0, 0.3) = 0.035;
group_uniforms;

group_uniforms texture;
// Ground texture repeats per metre (128 px a tile: 0.3 = about 38 texels a metre).
uniform float ground_scale = 0.3;
// How much the texture lightens and darkens the colour (0 = flat colour).
uniform float texture_strength : hint_range(0.0, 1.0) = 0.75;
// Colour the darkest texels shift toward (times the surface colour); the lightest go the other way.
uniform vec3 shadow_tint = vec3(0.62, 0.72, 0.90);
// How sharply neighbouring surfaces' textures cut into each other.
uniform float blend_sharpness = 4.0;
// How far slope borders wander with the texture.
uniform float edge_jitter = 0.1;
// Large light/dark patches against visible tiling, 0 = none.
uniform float macro_variation : hint_range(0.0, 0.5) = 0.14;
group_uniforms;

// Depth (plans/ground-depth.md): every slice carries a height and per-texel normals, so tufts,
// clods, pebbles and setts catch the sun and their gaps shade over; the top height level is the
// slice's second material (sunlit blade tips, pebbles, lichen, moss; on cobbles the bottom: the
// joints).
group_uniforms depth;
// How strongly the per-texel normals tilt the light (0 = flat).
uniform float normal_strength : hint_range(0.0, 3.0) = 1.0;
// How dark the gaps between tufts and pebbles go, and the colour they shade toward.
uniform float crevice_strength : hint_range(0.0, 1.0) = 0.45;
uniform vec3 crevice_tint : source_color = vec3(0.42, 0.48, 0.62);
// The fine normals and crevices fade out between these distances (m): beyond, texels are smaller
// than a pixel anyway.
uniform float detail_near = 20.0;
uniform float detail_far = 55.0;
// A coarser copy of the main surface's slice laid over it (clumps of clumps), 0 = none.
uniform float coarse_strength : hint_range(0.0, 1.0) = 0.3;
uniform float coarse_scale = 0.23;
// Colour, not just brightness, wanders over the land: patches drift toward these two tints.
uniform vec3 lush_tint : source_color = vec3(0.94, 1.02, 0.96);
uniform vec3 dry_tint : source_color = vec3(1.08, 1.04, 0.84);
uniform float hue_patch_size = 34.0;
// Hollows in the land shade darker and ridges lighter (terrain-scale crevices).
uniform float hollow_strength : hint_range(0.0, 3.0) = 1.2;
// 1 = the palette as is; above 1 pushes colours away from grey.
uniform float saturation : hint_range(0.0, 2.0) = 1.1;
// Second materials, by the slices' masks: colour multipliers over the surface colour.
uniform vec3 tip_tint : source_color = vec3(1.10, 1.08, 0.82);
uniform vec3 pebble_tint : source_color = vec3(1.05, 1.08, 1.15);
uniform vec3 lichen_tint : source_color = vec3(0.92, 1.06, 0.62);
uniform vec3 moss_tint : source_color = vec3(0.62, 1.05, 0.48);
uniform vec3 joint_tint : source_color = vec3(0.82, 0.78, 0.68);
uniform float second_strength : hint_range(0.0, 1.0) = 0.7;
group_uniforms;

// Slopes and peaks break up (plans/ground-depth.md): band edges wander with big noise, rock shows
// ledges, snow lies on the flatter ground of the heights.
group_uniforms breakup;
uniform float slope_breakup : hint_range(0.0, 0.3) = 0.05;
uniform float breakup_size = 9.0;
// Rock strata: ledges this many metres apart, the top of each lighter.
uniform float rock_band = 1.6;
uniform float rock_band_strength : hint_range(0.0, 0.6) = 0.22;
// The snow line wanders this far (m) up and down, and snow clings to slopes this much steeper.
uniform float snow_wander = 8.0;
uniform float snow_cling = 0.12;
group_uniforms;

// The water's surface height (all of Hearthvale's water: LayoutWater.LEVEL), the waves' clock
// (Waves), and the caustics on the bed under it: their size (m a cell), brightness, and the depth
// (m) they've faded out by.
const float WATER_LEVEL = -0.15;
global uniform float water_time;
uniform float caustic_size = 1.6;
uniform float caustic_strength = 0.28;
uniform float caustic_depth = 4.5;

global uniform sampler2DArray ground_tex : filter_nearest_mipmap_anisotropic, repeat_enable;

// ground_tex slices (tools/make_textures.py GROUND)
const float LAYER_GRASS = 0.0;
const float LAYER_DIRT = 1.0;
const float LAYER_ROCK = 2.0;
const float LAYER_SAND = 3.0;
const float LAYER_SNOW = 4.0;
const float LAYER_FOREST = 5.0;
const float LAYER_PATH = 6.0;
const float LAYER_FIELD = 7.0;
const float LAYER_PACKED = 8.0;
const float LAYER_SETTS = 9.0;
// Varyings & Types
// Some are required for editor functions
varying float v_vertex_xz_dist;
varying vec3 v_vertex;

////////////////////////
// Vertex
////////////////////////

// Takes in world space XZ (UV) coordinates & search depth (only applicable for background mode none)
// Returns ivec3 with:
// XY: (0 to _region_size - 1) coordinates within a region
// Z: layer index used for texturearrays, -1 if not in a region
ivec3 get_index_coord(const vec2 uv, const int search) {
	vec2 r_uv = round(uv);
	vec2 o_uv = mod(r_uv,_region_size);
	ivec2 pos;
	int bounds, layer_index = -1;
	for (int i = -1; i < clamp(search, SKIP_PASS, FRAGMENT_PASS); i++) {
		if ((layer_index == -1 && _background_mode == 0u ) || i < 0) {
			r_uv -= i == -1 ? vec2(0.0) : vec2(float(o_uv.x <= o_uv.y), float(o_uv.y <= o_uv.x));
			pos = ivec2(floor((r_uv) * _region_texel_size)) + (_region_map_size / 2);
			bounds = int(uint(pos.x | pos.y) < uint(_region_map_size));
			layer_index = (_region_map[ pos.y * _region_map_size + pos.x ] * bounds - 1);
		}
	}
	return ivec3(ivec2(mod(r_uv,_region_size)), layer_index);
}

void vertex() {
	// Get vertex of flat plane in world coordinates and set world UV
	v_vertex = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;

	// Camera distance to vertex on flat plane
	v_vertex_xz_dist = length(v_vertex.xz - _camera_pos.xz);

	// Geomorph vertex, set end and start for linear height interpolate
	float scale = MODEL_MATRIX[0][0];
	float vertex_lerp = smoothstep(0.55, 0.95, (v_vertex_xz_dist / scale - _mesh_size - 4.0) / (_mesh_size - 2.0));
	vec2 v_fract = fract(VERTEX.xz * 0.5) * 2.0;
	// For LOD0 morph from a regular grid to an alternating grid to align with LOD1+
	vec2 shift = (scale < _vertex_spacing + 1e-6) ? // LOD0 or not
		// Shift from regular to symetric
		mix(v_fract, vec2(v_fract.x, -v_fract.y),
			round(fract(round(mod(v_vertex.z * _vertex_density, 4.0)) *
			round(mod(v_vertex.x * _vertex_density, 4.0)) * 0.25))
			) :
		// Symetric shift
		v_fract * round((fract(v_vertex.xz * 0.25 / scale) - 0.5) * 4.0);
	vec2 start_pos = v_vertex.xz * _vertex_density;
	vec2 end_pos = (v_vertex.xz - shift * scale) * _vertex_density;
	v_vertex.xz -= shift * scale * vertex_lerp;

	// UV coordinates in world space. Values are 0 to _region_size within regions
	UV = v_vertex.xz * _vertex_density;

	// UV coordinates in region space + texel offset. Values are 0 to 1 within regions
	UV2 = fma(UV, vec2(_region_texel_size), vec2(0.5 * _region_texel_size));

	// Discard vertices for Holes. 1 lookup
	ivec3 v_region = get_index_coord(start_pos, VERTEX_PASS);
	uint control = floatBitsToUint(texelFetch(_control_maps, v_region, 0)).r;
	bool hole = bool(control >>2u & 0x1u);

	// Show holes to all cameras except mouse camera (on exactly 1 layer)
	if ( !(CAMERA_VISIBLE_LAYERS == _mouse_layer) &&
			(hole || (_background_mode == 0u && v_region.z < 0))) {
		v_vertex.x = 0. / 0.;
	} else {
		// Interpolate Geomorph Start & End, set height. 2 Lookups.
		ivec3 uv_a = get_index_coord(start_pos, VERTEX_PASS);
		ivec3 uv_b = get_index_coord(end_pos, VERTEX_PASS);
		float h = mix(texelFetch(_height_maps, uv_a, 0).r, texelFetch(_height_maps, uv_b, 0).r, vertex_lerp);
		v_vertex.y = h;
	}

	// Convert model space to view space w/ skip_vertex_transform render mode
	VERTEX = (VIEW_MATRIX * vec4(v_vertex, 1.0)).xyz;
	NORMAL = normalize((MODELVIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	BINORMAL = normalize((MODELVIEW_MATRIX * vec4(BINORMAL, 0.0)).xyz);
	TANGENT = normalize((MODELVIEW_MATRIX * vec4(TANGENT, 0.0)).xyz);
}

////////////////////////
// Fragment
////////////////////////

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

// Smooth value noise, 0..1.
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
			mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

// The map coordinate of the vertex `o` away from `b`: when the cell is well inside its region
// (`inner`), straight from b's own coordinate `c0`, without looking the region up again.
ivec3 index_near(vec2 b, ivec3 c0, bool inner, ivec2 o) {
	if (inner) {
		return ivec3(c0.xy + o, c0.z);
	}
	return get_index_coord(b + vec2(o), FRAGMENT_PASS);
}

float height_near(vec2 b, ivec3 c0, bool inner, ivec2 o) {
	ivec3 c = index_near(b, c0, inner, o);
	return c.z >= 0 ? texelFetch(_height_maps, c, 0).r : 0.0;
}

// Caustics: a few layers of light lines drifting over each other, sharpened (0..~1.5).
float caustic(vec2 p, float t) {
	vec2 q = p * 6.28318;
	vec2 i = q;
	float c = 0.0;
	for (int n = 0; n < 4; n++) {
		float tn = t * 0.45 * (1.0 - 3.0 / float(n + 2));
		i = q + vec2(cos(tn - i.x) + sin(tn + i.y), sin(tn - i.y) + cos(tn + i.x));
		c += 1.0 / length(vec2(q.x / (sin(i.x + tn) / 0.006), q.y / (cos(i.y + tn) / 0.006)));
	}
	c = 1.2 - pow(c / 4.0, 1.4);
	return clamp(pow(abs(c), 7.0), 0.0, 1.5);
}

float ground(vec2 world_xz, float layer) {
	return texture(ground_tex, vec3(world_xz * ground_scale, layer)).r;
}

// One slice texel: tone, height, and its normal's tilt (X and Z along the slice's columns and
// rows, 0.5 = flat).
vec4 ground_texel(vec2 p, float layer) {
	return texture(ground_tex, vec3(p, layer));
}

// The second material a slice's mask marks, as a multiplier on the surface colour.
vec3 second_tint(float layer) {
	if (layer == LAYER_GRASS || layer == LAYER_FIELD) return tip_tint;
	if (layer == LAYER_ROCK) return lichen_tint;
	if (layer == LAYER_FOREST) return moss_tint;
	if (layer == LAYER_SETTS) return joint_tint;
	if (layer == LAYER_SAND) return vec3(0.82, 0.80, 0.78);
	if (layer == LAYER_SNOW) return vec3(1.1, 1.12, 1.16);
	return pebble_tint;
}

// What one terrain vertex is covered with, for the slope at this pixel: its colour, and the
// ground_tex slice to texture it with (LAYER_*).
void surface_at(vec2 cell, ivec3 c, float h, float slope, float wy, float snow_line, out vec3 col, out float layer) {
	// two grasses in soft patches a few metres across
	vec2 world = cell * _vertex_spacing;
	float pick = smoothstep(0.42, 0.58, vnoise(world / patch_size));
	col = mix(grass_color, grass_color_2, pick);
	layer = LAYER_GRASS;
	if (h < sand_height) { col = sand_color; layer = LAYER_SAND; }
	if (h < bed_height) { col = bed_color; layer = LAYER_DIRT; }
	if (slope < dirt_slope) { col = dirt_color; layer = LAYER_DIRT; }
	if (slope < rock_slope) { col = rock_color; layer = LAYER_ROCK; }
	// higher up, snow clings to steeper ledges
	float cling = snow_cling * smoothstep(snow_line, snow_line + 10.0, h);
	if (h > snow_line && slope >= rock_slope - cling) { col = snow_color; layer = LAYER_SNOW; }

	bool quarry = false;
	if (c.z >= 0) {
		// Surfaces by texture id (base id = bits 27-31 of the control map). Paths and roads only
		// on walkable ground; the biomes swap the grass and dirt for their own.
		uint control = floatBitsToUint(texelFetch(_control_maps, c, 0)).r;
		int id = int(control >> 27u & 0x1Fu);
		bool level = slope >= dirt_slope;
		if (id == path_texture && slope >= rock_slope) {
			col = path_color; layer = LAYER_PATH;
		} else if (id == road_texture && slope >= rock_slope) {
			col = road_color; layer = LAYER_PATH;
		} else if (id == packed_texture && slope >= rock_slope) {
			col = packed_color; layer = LAYER_PACKED;
		} else if (id == cobble_texture && slope >= rock_slope) {
			col = cobble_color; layer = LAYER_SETTS;
		} else if (id == forest_texture && slope >= rock_slope) {
			bool litter = !level || vnoise(world / (patch_size * 0.5) + 17.0) < 0.22;
			col = litter ? needle_color : mix(forest_color, forest_color_2, pick);
			layer = LAYER_FOREST;
		} else if (id == field_texture && slope >= rock_slope) {
			col = level ? mix(field_color, field_color_2, pick) : dirt_color;
			layer = level ? LAYER_GRASS : LAYER_DIRT;
		} else if (id == crop_texture && slope >= rock_slope) {
			col = mix(crop_color, crop_color_2, step(0.5, hash(cell)));
			layer = LAYER_FIELD;
		} else if (id == quarry_texture) {
			// strata: banded by the pixel's own height, so a wall shows stripes
			float band = mod(floor(wy / quarry_band), 2.0);
			quarry = true;
			col = level ? quarry_color : mix(quarry_rock, quarry_rock_2, band);
			layer = level ? LAYER_PATH : LAYER_ROCK;
		}
		// under the water: silt over the shelves, mud in the deep (not the quarry's pit)
		if (h < bed_height && id != quarry_texture && slope >= rock_slope) {
			float deep = smoothstep(0.6, silt_depth, WATER_LEVEL - h);
			col = mix(mix(silt_color, bed_color, 0.35 + 0.4 * vnoise(world * 0.31)), bed_color, deep);
			layer = deep > 0.5 ? LAYER_DIRT : LAYER_SAND;
		}
		// Painted colour from Terrain3D's Color tool (white = unpainted).
		col *= texelFetch(_color_maps, c, 0).rgb;
	}
	// rock shows ledges: the top of each band lighter, its foot darker (the quarry has its own)
	if (layer == LAYER_ROCK && !quarry) {
		float ledge = fract((wy + vnoise(world / 6.0) * 1.5) / rock_band);
		col *= 1.0 + (ledge - 0.5) * 2.0 * rock_band_strength;
	}
	col *= 1.0 + (hash(cell) - 0.5) * 2.0 * variation;
}

void fragment() {
	// Terrain3D injects editor code (brush preview, region grid…) that expects these names.
	vec2 uv = UV;
	vec3 base_ddx = dFdxCoarse(v_vertex);
	vec3 base_ddy = dFdyCoarse(v_vertex);
	vec3 w_vertex = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;

	// Smooth normal from the heightmap: central differences of the bilinear height, from the 12
	// vertices round this pixel's cell (b: its corner, f: how far across). The middle four are
	// the cell's own corners, whose surfaces are blended below.
	vec2 b = floor(uv);
	vec2 f = uv - b;
	ivec3 c0 = get_index_coord(b, FRAGMENT_PASS);
	bool inner = c0.z >= 0 && all(greaterThanEqual(c0.xy, ivec2(1)))
			&& all(lessThan(c0.xy, ivec2(int(_region_size) - 2)));
	float h00 = height_near(b, c0, inner, ivec2(0, 0)), h10 = height_near(b, c0, inner, ivec2(1, 0));
	float h01 = height_near(b, c0, inner, ivec2(0, 1)), h11 = height_near(b, c0, inner, ivec2(1, 1));
	float hx0 = height_near(b, c0, inner, ivec2(-1, 0)), hx1 = height_near(b, c0, inner, ivec2(-1, 1));
	float hy0 = height_near(b, c0, inner, ivec2(2, 0)), hy1 = height_near(b, c0, inner, ivec2(2, 1));
	float hz0 = height_near(b, c0, inner, ivec2(0, -1)), hz1 = height_near(b, c0, inner, ivec2(1, -1));
	float hw0 = height_near(b, c0, inner, ivec2(0, 2)), hw1 = height_near(b, c0, inner, ivec2(1, 2));
	float hl = mix(mix(hx0, h00, f.x), mix(hx1, h01, f.x), f.y);
	float hr = mix(mix(h10, hy0, f.x), mix(h11, hy1, f.x), f.y);
	float hd = mix(mix(hz0, hz1, f.x), mix(h00, h10, f.x), f.y);
	float hu = mix(mix(h01, h11, f.x), mix(hw0, hw1, f.x), f.y);
	vec3 w_normal = normalize(vec3(hl - hr, 2.0 * _vertex_spacing, hd - hu));

	// The fine detail (normals, crevices) fades out with distance.
	float near = 1.0 - smoothstep(detail_near, detail_far, length(VERTEX));

	// Ragged borders: the slope bands and surface edges wander with the texture, and with big
	// patches of noise, so grass climbs some slopes and dirt and rock break through on others.
	float jitter = ground(w_vertex.xz * 0.37, LAYER_DIRT) - 0.5;
	float slope = w_normal.y + jitter * edge_jitter
			+ (vnoise(w_vertex.xz / breakup_size) - 0.5) * 2.0 * slope_breakup;

	// The four surrounding vertices' surfaces.
	// the snow line wanders
	float snow_line = snow_height + (vnoise(w_vertex.xz / 23.0) - 0.5) * snow_wander;

	vec2 p_top = w_vertex.xz * ground_scale;

	// Rock projected from three sides, so cliffs aren't smeared.
	vec3 tw = pow(abs(w_normal), vec3(6.0));
	tw /= tw.x + tw.y + tw.z;
	vec4 tx = ground_texel(w_vertex.zy * ground_scale, LAYER_ROCK);
	vec4 ty = ground_texel(p_top, LAYER_ROCK);
	vec4 tz = ground_texel(w_vertex.xy * ground_scale, LAYER_ROCK);
	// (its tilt kept as the world X and Z tilt, like the flat slices': each side tilts along the
	// world axes it lies across)
	vec4 rock_t = vec4((tx.rg * tw.x + ty.rg * tw.y + tz.rg * tw.z),
			0.5 * tw.x + ty.b * tw.y + tz.b * tw.z, tx.b * tw.x + ty.a * tw.y + 0.5 * tw.z);
	float around = (hl + hr + hd + hu) * 0.25;  // (for the hollows, below)

	// Blend them, each weighted by how far up its own texture pokes (height blending): tufts,
	// clods and pebbles win at the borders, crisp and painterly instead of a soft fade.
	vec3 albedo = vec3(0.0);
	vec2 tilt = vec2(0.0);
	float crevice = 0.0;
	float green = 0.0;  // how much of it is growing (grass, forest floor, meadow)
	float total = 0.0;
	float centre = 0.0;  // the land's height here, from the four vertices
	float best = -1.0;
	float main_layer = LAYER_GRASS;
	for (int i = 0; i < 4; i++) {
		vec2 o = vec2(float(i & 1), float(i >> 1));
		vec3 surface;
		float layer;
		float h = i == 0 ? h00 : i == 1 ? h10 : i == 2 ? h01 : h11;
		surface_at(b + o, index_near(b, c0, inner, ivec2(i & 1, i >> 1)), h, slope, w_vertex.y, snow_line,
				surface, layer);
		vec4 t = layer == LAYER_ROCK ? rock_t : ground_texel(p_top, layer);
		// the second material: the top height level (on cobbles, the bottom: the joints)
		bool setts = layer == LAYER_SETTS;
		float second = setts ? step(t.g, 0.03) : step(0.97, t.g);
		// gaps shade over: the lower the texel, the darker (cobbles' joints are dark already)
		float shade = 0.35 + 0.65 * smoothstep(0.0, 0.6, t.g);
		vec2 bw = mix(1.0 - f, f, o);
		centre += h * bw.x * bw.y;
		float w = pow(bw.x * bw.y * (0.25 + t.g), blend_sharpness);
		// dark texels shift cool, light ones warm, around the surface's own colour; the mask
		// paints in the second material
		float k = clamp(0.5 + (t.r - 0.5) * 2.0 * texture_strength, 0.0, 1.0);
		vec3 col = surface * mix(vec3(1.0), second_tint(layer), second * second_strength);
		albedo += col * mix(shadow_tint, vec3(2.0) - shadow_tint, k) * w;
		crevice += (setts ? max(shade, 0.6) : shade) * w;
		tilt += t.ba * w;
		green += float(layer == LAYER_GRASS || layer == LAYER_FOREST) * w;
		total += w;
		if (w > best) { best = w; main_layer = layer; }
	}
	albedo /= max(total, 1e-5);
	crevice /= max(total, 1e-5);
	tilt = tilt / max(total, 1e-5) * 2.0 - 1.0;
	green /= max(total, 1e-5);

	// Hollows in the land (lower than the four round them) shade darker, ridges lighter.
	float hollow = clamp((around - centre) / _vertex_spacing, -0.5, 0.5);

	// A coarser copy of the main surface's slice over it: clumps of clumps.
	float coarse = texture(ground_tex, vec3(p_top * coarse_scale, main_layer)).r;
	albedo *= 1.0 + (coarse - 0.5) * coarse_strength;

	// Crevices: the gaps between tufts and pebbles shade cool and dark, up close.
	albedo *= mix(vec3(1.0), mix(crevice_tint, vec3(1.0), crevice), crevice_strength * near);
	// Hollows darker, ridges lighter.
	albedo *= 1.0 - hollow * hollow_strength;

	// Big, slow light and dark patches so the tiling doesn't show from afar, and on growing
	// ground patches of colour: lusher here, drier there. Growing ground and earth get richer
	// colour (snow, sand and stone keep theirs).
	albedo *= 1.0 + (vnoise(w_vertex.xz / 28.0) - 0.5) * macro_variation;
	vec3 hue = mix(lush_tint, dry_tint, smoothstep(0.3, 0.7, vnoise(w_vertex.xz / hue_patch_size + 41.0)));
	albedo *= mix(vec3(1.0), hue, green);
	float luma = dot(albedo, vec3(0.299, 0.587, 0.114));
	float rich = main_layer == LAYER_SNOW || main_layer == LAYER_SAND || main_layer == LAYER_ROCK
			|| main_layer == LAYER_SETTS ? 1.0 : saturation;
	albedo = max(mix(vec3(luma), albedo, rich), vec3(0.0));

	// Per-texel normals: the sun lights the tops of tufts and pebbles and shades their sides.
	vec3 n = normalize(w_normal + vec3(tilt.x, 0.0, tilt.y) * normal_strength * near);
	NORMAL = mat3(VIEW_MATRIX) * n;
	TANGENT = normalize(cross(NORMAL, VIEW_MATRIX[2].xyz));
	BINORMAL = normalize(cross(NORMAL, TANGENT));

	// caustics: the light the waves focus, dancing on the bed under shallow water (plans/water.md)
	float under = WATER_LEVEL - w_vertex.y;
	if (under > 0.0) {
		float fade = smoothstep(0.03, 0.25, under) * (1.0 - smoothstep(1.2, caustic_depth, under));
		albedo *= 1.0 + caustic(w_vertex.xz / caustic_size, water_time) * caustic_strength * fade;
	}

	ALBEDO = albedo;
	ROUGHNESS = 1.0;
}
