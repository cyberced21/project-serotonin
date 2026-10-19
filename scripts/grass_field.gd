class_name GrassField
extends Node3D
## Dense grass round the player, Valheim-style: thousands of small clumps of blades in a ring
## round the camera, built in CHUNK-metre squares as you move and dropped behind you. Each clump
## is coloured like the ground it grows on (the terrain shader's grass, forest or meadow colour),
## sways in the shared wind and parts round the player (shaders/grass.gdshader).
## Grows where SceneryScatter's plants would: not on paths, roads, quarry stone, crops, sand,
## water, snow or steep ground, and clear of nodes, buildings and props.
## Density and reach follow GraphicsSettings (grass_density, foliage_distance).

const SHADER := preload("res://shaders/grass.gdshader")
const CHUNK := 8.0
## Chunks built per frame at most (keeps walking smooth).
const BUILD_PER_FRAME := 3
const FOREST_IDS: Array[int] = [WorldMap.TEX_FOREST]
const FIELD_IDS: Array[int] = [WorldMap.TEX_FIELD]
## Terrain shader colours used when its material doesn't override them.
const DEFAULT_COLORS := {
	&"grass_color": Color(0.36, 0.55, 0.30), &"grass_color_2": Color(0.42, 0.60, 0.31),
	&"forest_color": Color(0.23, 0.39, 0.22), &"forest_color_2": Color(0.27, 0.43, 0.24),
	&"field_color": Color(0.50, 0.62, 0.29), &"field_color_2": Color(0.56, 0.66, 0.31),
}

## Ring radius (m) at full foliage distance.
@export var radius := 38.0
## Clumps per m² at full grass density.
@export var density := 7.0
@export var min_normal_y := 0.82
@export var clump_scale := Vector2(0.7, 1.25)

var _terrain: Terrain3D
var _mesh: ArrayMesh
var _material: ShaderMaterial
var _chunks: Dictionary[Vector2i, MultiMeshInstance3D] = {}
var _keep_out: Dictionary[Vector2i, Array] = {}  # chunk -> [(x, z, r), ...] touching it
var _colors := {}
var _radius := 0.0
var _density := 0.0


func _ready() -> void:
	_mesh = _make_clump()
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	GraphicsSettings.changed.connect(_on_settings)
	_setup.call_deferred()  # once the terrain, buildings and props are in place


func _setup() -> void:
	_terrain = get_tree().get_first_node_in_group("terrain") as Terrain3D
	if _terrain == null or _terrain.data == null:
		push_warning("GrassField: no terrain")
		return
	for key in DEFAULT_COLORS:
		var c: Variant = _terrain.material.get_shader_param(key) if _terrain.material else null
		_colors[key] = Color(c.x, c.y, c.z) if c is Vector3 else (c if c is Color else DEFAULT_COLORS[key])
	_index_keep_out(SceneryScatter.keep_out_spots(get_tree(), 1.2, 0.8, 0.6))
	_on_settings()


func _on_settings() -> void:
	_radius = radius * float(GraphicsSettings.get_value(&"foliage_distance"))
	_density = density * float(GraphicsSettings.get_value(&"grass_density"))
	_material.set_shader_parameter("fade_end", _radius - 1.0)
	_material.set_shader_parameter("fade_start", _radius - 9.0)
	for c in _chunks.values():
		c.queue_free()
	_chunks.clear()


func _process(_delta: float) -> void:
	if _terrain == null:
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var player := get_tree().get_first_node_in_group("player") as Node3D
	RenderingServer.global_shader_parameter_set(&"grass_pusher",
			player.global_position if player else Vector3(0, -1000, 0))
	var at := cam.global_position
	var centre := Vector2i(floori(at.x / CHUNK), floori(at.z / CHUNK))
	var reach := ceili(_radius / CHUNK)
	# drop chunks that fell out of the ring
	for key in _chunks.keys():
		if _chunk_dist(key, at) > _radius + CHUNK:
			_chunks[key].queue_free()
			_chunks.erase(key)
	if _density <= 0.0:
		return
	# build the nearest missing ones first
	var missing: Array[Vector2i] = []
	for x in range(centre.x - reach, centre.x + reach + 1):
		for z in range(centre.y - reach, centre.y + reach + 1):
			var key := Vector2i(x, z)
			if not _chunks.has(key) and _chunk_dist(key, at) < _radius:
				missing.append(key)
	missing.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return _chunk_dist(a, at) < _chunk_dist(b, at))
	for i in mini(BUILD_PER_FRAME, missing.size()):
		_chunks[missing[i]] = _build(missing[i])


## Distance from `at` to the nearest point of chunk `key` (XZ).
static func _chunk_dist(key: Vector2i, at: Vector3) -> float:
	var lo := Vector2(key) * CHUNK
	var p := Vector2(at.x, at.z)
	return p.distance_to(p.clamp(lo, lo + Vector2.ONE * CHUNK))


func _build(key: Vector2i) -> MultiMeshInstance3D:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(key)  # the same grass every time you come back
	var xforms: Array[Transform3D] = []
	var colors: PackedColorArray = PackedColorArray()
	var keep: Array = _keep_out.get(key, [])
	var origin := Vector3(key.x * CHUNK, 0.0, key.y * CHUNK)
	for i in int(CHUNK * CHUNK * _density):
		var p := Vector3(origin.x + rng.randf() * CHUNK, 0.0, origin.z + rng.randf() * CHUNK)
		var yaw := rng.randf() * TAU
		var s := rng.randf_range(clump_scale.x, clump_scale.y)
		var tint := rng.randf()
		var h: float = _terrain.data.get_height(p)
		if is_nan(h) or h < SceneryScatter.SAND_HEIGHT or h > SceneryScatter.SNOW_HEIGHT:
			continue
		p.y = h
		var n: Vector3 = _terrain.data.get_normal(p)
		if n.y < min_normal_y:
			continue
		var id: int = _terrain.data.get_control_base_id(p)
		if id in SceneryScatter.BARE_TEXTURES:
			continue
		var blocked := false
		for k: Vector3 in keep:
			if (p.x - k.x) * (p.x - k.x) + (p.z - k.y) * (p.z - k.y) < k.z * k.z:
				blocked = true
				break
		if blocked or WaterBody.depth_at(get_tree(), p) > 0.0:
			continue
		var basis := Basis(Quaternion(Vector3.UP, n)) * Basis(Vector3.UP, yaw)
		xforms.append(Transform3D(basis.scaled(Vector3(s, s * rng.randf_range(0.8, 1.2), s)), p - origin))
		colors.append(_color_for(id, tint))
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = _mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
		mm.set_instance_color(i, colors[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = _material
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)
	mmi.global_position = origin
	return mmi


func _color_for(id: int, tint: float) -> Color:
	var a: Color
	var b: Color
	if id in FOREST_IDS:
		a = _colors[&"forest_color"]
		b = _colors[&"forest_color_2"]
	elif id in FIELD_IDS:
		a = _colors[&"field_color"]
		b = _colors[&"field_color_2"]
	else:
		a = _colors[&"grass_color"]
		b = _colors[&"grass_color_2"]
	# instance colours reach the shader as they are: convert, like a source_color uniform would be
	return (a.lerp(b, tint) * (0.9 + tint * 0.16)).srgb_to_linear()


## Files each keep-out circle under every chunk it touches.
func _index_keep_out(spots: Array[Vector3]) -> void:
	_keep_out.clear()
	for k in spots:
		var lo := Vector2i(floori((k.x - k.z) / CHUNK), floori((k.y - k.z) / CHUNK))
		var hi := Vector2i(floori((k.x + k.z) / CHUNK), floori((k.y + k.z) / CHUNK))
		for x in range(lo.x, hi.x + 1):
			for z in range(lo.y, hi.y + 1):
				var key := Vector2i(x, z)
				if not _keep_out.has(key):
					_keep_out[key] = []
				_keep_out[key].append(k)


## One clump: a few tapered blades leaning out from the middle, each a 3-segment strip.
## UV.y = 0 at the root, 1 at the tip.
static func _make_clump() -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for b in 9:
		var yaw := rng.randf() * TAU
		var dir := Vector3(cos(yaw), 0.0, sin(yaw))
		var side := Vector3(-dir.z, 0.0, dir.x)
		var base := dir * rng.randf_range(0.0, 0.08)
		var height := rng.randf_range(0.22, 0.46)
		var width := rng.randf_range(0.018, 0.03)
		var lean := rng.randf_range(0.06, 0.2)
		var rows: Array[Vector3] = []
		for i in 4:
			var t := i / 3.0
			var c := base + dir * lean * t * t + Vector3.UP * height * t
			var w := width * (1.0 - t * 0.85)
			rows.append(c - side * w)
			rows.append(c + side * w)
		var n := dir.cross(side).normalized() * -1.0
		for i in 3:
			var t0 := i / 3.0
			var t1 := (i + 1) / 3.0
			var quad := [[rows[i * 2], t0], [rows[i * 2 + 1], t0], [rows[i * 2 + 3], t1], [rows[i * 2 + 2], t1]]
			for idx in [0, 1, 2, 0, 2, 3]:
				st.set_normal(n)
				st.set_uv(Vector2(0.0, quad[idx][1]))
				st.add_vertex(quad[idx][0])
	return st.commit()
