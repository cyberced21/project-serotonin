// Low-poly terrain shader for Project Serotonin.
// Based on Terrain3D's extras/shaders/minimum.gdshader (MIT, © 2023-2026 Cory Petkovsek,
// Roope Palmroos, and Contributors) — the vertex / geomorph code below is theirs, unchanged.
//
// The look: every triangle is flat-shaded (faceted normals) and gets ONE flat colour picked
// from a small palette by its slope and height — grass on flats, dirt on slopes, rock on
// cliffs, sand low down, snow up high, and dirt paths where the control map marks them.
// A little per-cell tint variation breaks up big areas.
// Terrain3D's Color tool still works: painted colour multiplies the palette colour.
// Vertex spacing (on the Terrain3D node) sets how big the facets are.

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
//uniform highp sampler2DArray _texture_array_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;

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

void fragment() {
	// Terrain3D injects editor code (brush preview, region grid…) that expects these names.
	vec2 uv = UV;
	vec3 base_ddx = dFdxCoarse(v_vertex);
	vec3 base_ddy = dFdyCoarse(v_vertex);

	// Faceted normal: the true plane of this triangle, constant across it.
	vec3 w_vertex = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 w_normal = normalize(cross(dFdyCoarse(w_vertex), dFdxCoarse(w_vertex)));
	NORMAL = mat3(VIEW_MATRIX) * w_normal;
	TANGENT = normalize(cross(NORMAL, VIEW_MATRIX[2].xyz));
	BINORMAL = normalize(cross(NORMAL, TANGENT));

	// One colour per facet from slope + height. Banding uses the facet's centre-ish height
	// (snapped to the cell) so a facet never gets split between two colours.
	vec2 cell = floor(UV);
	float slope = w_normal.y;
	float h = texelFetch(_height_maps, get_index_coord(cell, FRAGMENT_PASS), 0).r;
	// two grasses in irregular patches a few metres across (not per cell — that reads as a quilt)
	vec2 patch = floor((cell + vec2(hash(floor(cell / patch_size)) * patch_size)) / patch_size);
	vec3 albedo = mix(grass_color, grass_color_2, step(0.55, hash(patch)));
	albedo = h < sand_height ? sand_color : albedo;
	albedo = h < bed_height ? bed_color : albedo;
	albedo = slope < dirt_slope ? dirt_color : albedo;
	albedo = slope < rock_slope ? rock_color : albedo;
	albedo = h > snow_height && slope >= rock_slope ? snow_color : albedo;

	ivec3 c = get_index_coord(cell, FRAGMENT_PASS);
	if (c.z >= 0) {
		// Path: cells painted with texture id path_texture (base id = bits 27-31 of the control map).
		uint control = floatBitsToUint(texelFetch(_control_maps, c, 0)).r;
		if ((control >> 27u & 0x1Fu) == uint(path_texture) && slope >= rock_slope) {
			albedo = path_color;
		}
	}
	albedo *= 1.0 + (hash(cell) - 0.5) * 2.0 * variation;

	// Painted colour from Terrain3D's Color tool (white = unpainted).
	if (c.z >= 0) {
		albedo *= texelFetch(_color_maps, c, 0).rgb;
	}

	ALBEDO = albedo;
	ROUGHNESS = 1.0;
}
