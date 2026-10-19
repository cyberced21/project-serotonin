// Terrain shader for Project Serotonin: smooth, textured ground (Valheim-style).
// Based on Terrain3D's extras/shaders/minimum.gdshader (MIT, © 2023-2026 Cory Petkovsek,
// Roope Palmroos, and Contributors) — the vertex / geomorph code below is theirs, unchanged.
//
// The look: smooth normals from the heightmap; each vertex is covered by one surface (grass on
// flats, dirt on slopes, rock on cliffs, sand low down, snow up high, and the biome surfaces and
// paths the control map marks), coloured from the palette below and textured with a chunky,
// nearest-filtered slice of art/textures/ground.png (global `ground_tex`, made by
// tools/make_textures.py). Neighbouring surfaces meet in ragged, height-blended borders.
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
uniform vec3 grass_color : source_color = vec3(0.36, 0.55, 0.30);
uniform vec3 grass_color_2 : source_color = vec3(0.42, 0.60, 0.31);
uniform vec3 dirt_color : source_color = vec3(0.52, 0.42, 0.30);
uniform vec3 rock_color : source_color = vec3(0.47, 0.46, 0.45);
uniform vec3 sand_color : source_color = vec3(0.80, 0.74, 0.55);
uniform vec3 snow_color : source_color = vec3(0.92, 0.94, 0.96);
// Pond / lake bed below `bed_height` — dark and muddy so fish stand out against it.
uniform vec3 bed_color : source_color = vec3(0.36, 0.34, 0.24);
// Dirt paths: cells painted with this texture id (control map base texture; see
// tools/generate_test_terrain.gd, or Terrain3D's texture paint tool) on walkable slopes.
uniform vec3 path_color : source_color = vec3(0.63, 0.52, 0.40);
uniform int path_texture = 1;
group_uniforms;
// Biome surfaces, by control-map texture id (scripts/world_map.gd TEX_*). Cliffs stay rock.
group_uniforms biomes;
uniform vec3 road_color : source_color = vec3(0.66, 0.63, 0.57);
uniform int road_texture = 2;
uniform vec3 forest_color : source_color = vec3(0.23, 0.39, 0.22);
uniform vec3 forest_color_2 : source_color = vec3(0.27, 0.43, 0.24);
// Needle litter: patches on the forest floor, and its slopes.
uniform vec3 needle_color : source_color = vec3(0.42, 0.33, 0.22);
uniform int forest_texture = 3;
uniform vec3 field_color : source_color = vec3(0.50, 0.62, 0.29);
uniform vec3 field_color_2 : source_color = vec3(0.56, 0.66, 0.31);
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
uniform vec3 shadow_tint = vec3(0.70, 0.76, 0.86);
// How sharply neighbouring surfaces' textures cut into each other.
uniform float blend_sharpness = 4.0;
// How far slope borders wander with the texture.
uniform float edge_jitter = 0.1;
// Large light/dark patches against visible tiling, 0 = none.
uniform float macro_variation : hint_range(0.0, 0.5) = 0.14;
group_uniforms;

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

float height_at(vec2 cell) {
	ivec3 c = get_index_coord(cell, FRAGMENT_PASS);
	return c.z >= 0 ? texelFetch(_height_maps, c, 0).r : 0.0;
}

// Bilinear height between the four vertices round `uv` (vertex units).
float height_smooth(vec2 uv) {
	vec2 b = floor(uv);
	vec2 f = uv - b;
	return mix(mix(height_at(b), height_at(b + vec2(1.0, 0.0)), f.x),
			mix(height_at(b + vec2(0.0, 1.0)), height_at(b + vec2(1.0, 1.0)), f.x), f.y);
}

float ground(vec2 world_xz, float layer) {
	return texture(ground_tex, vec3(world_xz * ground_scale, layer)).r;
}

// What one terrain vertex is covered with, for the slope at this pixel: its colour, and the
// ground_tex slice to texture it with (LAYER_*).
void surface_at(vec2 cell, float slope, float wy, out vec3 col, out float layer) {
	ivec3 c = get_index_coord(cell, FRAGMENT_PASS);
	float h = c.z >= 0 ? texelFetch(_height_maps, c, 0).r : 0.0;
	// two grasses in soft patches a few metres across
	vec2 world = cell * _vertex_spacing;
	float pick = smoothstep(0.42, 0.58, vnoise(world / patch_size));
	col = mix(grass_color, grass_color_2, pick);
	layer = LAYER_GRASS;
	if (h < sand_height) { col = sand_color; layer = LAYER_SAND; }
	if (h < bed_height) { col = bed_color; layer = LAYER_DIRT; }
	if (slope < dirt_slope) { col = dirt_color; layer = LAYER_DIRT; }
	if (slope < rock_slope) { col = rock_color; layer = LAYER_ROCK; }
	if (h > snow_height && slope >= rock_slope) { col = snow_color; layer = LAYER_SNOW; }

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
			col = level ? quarry_color : mix(quarry_rock, quarry_rock_2, band);
			layer = level ? LAYER_PATH : LAYER_ROCK;
		}
		// Painted colour from Terrain3D's Color tool (white = unpainted).
		col *= texelFetch(_color_maps, c, 0).rgb;
	}
	col *= 1.0 + (hash(cell) - 0.5) * 2.0 * variation;
}

void fragment() {
	// Terrain3D injects editor code (brush preview, region grid…) that expects these names.
	vec2 uv = UV;
	vec3 base_ddx = dFdxCoarse(v_vertex);
	vec3 base_ddy = dFdyCoarse(v_vertex);
	vec3 w_vertex = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;

	// Smooth normal from the heightmap (central differences of the bilinear height).
	float hl = height_smooth(uv - vec2(1.0, 0.0));
	float hr = height_smooth(uv + vec2(1.0, 0.0));
	float hd = height_smooth(uv - vec2(0.0, 1.0));
	float hu = height_smooth(uv + vec2(0.0, 1.0));
	vec3 w_normal = normalize(vec3(hl - hr, 2.0 * _vertex_spacing, hd - hu));
	NORMAL = mat3(VIEW_MATRIX) * w_normal;
	TANGENT = normalize(cross(NORMAL, VIEW_MATRIX[2].xyz));
	BINORMAL = normalize(cross(NORMAL, TANGENT));

	// Rock projected from three sides, so cliffs aren't smeared.
	vec3 tw = pow(abs(w_normal), vec3(6.0));
	tw /= tw.x + tw.y + tw.z;
	float rock_t = ground(w_vertex.zy, LAYER_ROCK) * tw.x + ground(w_vertex.xz, LAYER_ROCK) * tw.y
			+ ground(w_vertex.xy, LAYER_ROCK) * tw.z;

	// Ragged borders: the slope bands and surface edges wander with the texture.
	float jitter = ground(w_vertex.xz * 0.37, LAYER_DIRT) - 0.5;
	float slope = w_normal.y + jitter * edge_jitter;

	// Blend the four surrounding vertices' surfaces, each weighted by how far up its own texture
	// pokes (height blending): crisp, painterly borders instead of a soft fade.
	vec2 b = floor(uv);
	vec2 f = uv - b;
	vec3 albedo = vec3(0.0);
	float total = 0.0;
	for (int i = 0; i < 4; i++) {
		vec2 o = vec2(float(i & 1), float(i >> 1));
		vec3 col;
		float layer;
		surface_at(b + o, slope, w_vertex.y, col, layer);
		float t = layer == LAYER_ROCK ? rock_t : ground(w_vertex.xz, layer);
		vec2 bw = mix(1.0 - f, f, o);
		float w = pow(bw.x * bw.y * (0.25 + t), blend_sharpness);
		// dark texels shift cool, light ones warm, around the surface's own colour
		float k = clamp(0.5 + (t - 0.5) * 2.0 * texture_strength, 0.0, 1.0);
		albedo += col * mix(shadow_tint, vec3(2.0) - shadow_tint, k) * w;
		total += w;
	}
	albedo /= max(total, 1e-5);

	// Big, slow light and dark patches so the tiling doesn't show from afar.
	albedo *= 1.0 + (vnoise(w_vertex.xz / 28.0) - 0.5) * macro_variation;

	ALBEDO = albedo;
	ROUGHNESS = 1.0;
}
