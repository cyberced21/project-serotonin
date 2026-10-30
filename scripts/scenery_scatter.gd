class_name SceneryScatter
extends Node3D
## Spreads scenery (grass, flowers, bushes, boulders: one ScatterLayer each) over the terrain inside
## `area`, seeded so it's the same every run. Each layer is drawn with MultiMeshes, one per
## CELL-metre square, so far-away cells can be culled by the layer's visible_distance.
## Keeps off: paths, roads, quarry stone and crop squares (BARE_TEXTURES, unless a layer's
## allowed_ids say otherwise), water and sand, ground too steep for the layer, snow (plants), and
## the space around gatherable nodes, buildings, props (the parkour ruins included) and the
## player's spawn.

## Painted surfaces nothing grows on (see WorldMap.TEX_*).
const BARE_TEXTURES: Array[int] = [WorldMap.TEX_PATH, WorldMap.TEX_ROAD, WorldMap.TEX_QUARRY, WorldMap.TEX_CROP]
const PALETTE := preload("res://materials/node_palette.tres")
const SWAY := preload("res://shaders/sway_instanced.gdshader")
const CELL := 32.0
## Ground lower than this is sand, pond bed or water (keep in sync with the terrain shader's sand_height).
const SAND_HEIGHT := -0.04
const SNOW_HEIGHT := 38.0
## The keep-out spots are filed in squares this size (m).
const KEEP_OUT_CELL := 16.0

signal finished

@export var layers: Array[ScatterLayer] = []
## World XZ rectangle to fill (x, z, width, depth).
@export var area := Rect2(-110, -80, 280, 200)
@export var seed := 1
## How the place dresses the boulders, bushes and trees (moss, snow…; see NodeTheme), a look per
## layer and cell; none = as made. The swaying plants (grass, flowers) are left as they are.
@export var theme: NodeTheme
@export_group("Keep clear (m)")
@export var node_radius := 1.8
@export var prop_radius := 1.0
@export var building_margin := 1.0
@export var spawn_radius := 3.0
## More open spots to keep clear, (x, z, radius): glades.
@export var clear_spots := PackedVector3Array()
## Thin out toward the rim of an ellipse (centre x, z, radius x, z): full density in the middle,
## a sparse fringe at the edge. Zero radii = off.
@export var edge_ellipse := Vector4.ZERO

var _keep_out: Array[Vector3] = []  # (x, z, radius)
var _keep_out_grid: Dictionary[Vector2i, Array] = {}
var _highest_water := -INF


## Milliseconds of scattering per frame before it waits for the next; 0 = all at once. The same
## scenery either way.
var frame_budget_ms := 0.0
var done := false


func _ready() -> void:
	_scatter.call_deferred()  # once the terrain, buildings and props are all in place


func _scatter() -> void:
	var terrain := get_tree().get_first_node_in_group("terrain") as Terrain3D
	if terrain == null or terrain.data == null:
		push_warning("SceneryScatter: no terrain to scatter on")
		_finish()
		return
	var frame_start := Time.get_ticks_usec()
	_collect_keep_out()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	for layer in layers:
		var mesh := _mesh_of(layer.model)
		if mesh == null:
			continue
		var cells: Dictionary[Vector2i, Array] = {}
		var shapes: Array[Transform3D] = []
		for i in int(area.get_area() / 100.0 * layer.density):
			if frame_budget_ms > 0.0 and i % 64 == 0 and Time.get_ticks_usec() - frame_start > frame_budget_ms * 1000.0:
				await get_tree().process_frame
				frame_start = Time.get_ticks_usec()
			var centre := Vector2(rng.randf_range(area.position.x, area.end.x), rng.randf_range(area.position.y, area.end.y))
			for j in rng.randi_range(layer.cluster.x, maxi(layer.cluster.x, layer.cluster.y)):
				# draw every random number before checking, so a rejected spot doesn't shift the rest
				var off := Vector2.from_angle(rng.randf() * TAU) * sqrt(rng.randf()) * layer.cluster_radius
				var p := centre + (off if layer.cluster.y > 1 else Vector2.ZERO)
				var s := rng.randf_range(layer.scale_range.x, layer.scale_range.y)
				var yaw := rng.randf() * TAU
				if _thinned(p, rng):
					continue
				var xform: Variant = _place(terrain, layer, p, s, yaw)
				if xform == null:
					continue
				var key := Vector2i(floori(p.x / CELL), floori(p.y / CELL))
				if not cells.has(key):
					cells[key] = []
				cells[key].append(xform)
				if layer.collide:
					shapes.append(xform)
		_build_cells(layer, mesh, cells)
		if layer.collide:
			_build_collision(mesh, shapes, layer.collision_size)
	_finish()


func _finish() -> void:
	done = true
	finished.emit()


## A layer's own allowed_ids win (wheat grows on crop squares); otherwise anything not bare.
static func _allowed(layer: ScatterLayer, id: int) -> bool:
	return id in layer.allowed_ids if not layer.allowed_ids.is_empty() else id not in BARE_TEXTURES


## Whether `edge_ellipse` drops this spot. Only draws a number when it's on, so turning it on for
## one scatter node doesn't reshuffle the others.
func _thinned(p: Vector2, rng: RandomNumberGenerator) -> bool:
	if edge_ellipse.z <= 0.0 or edge_ellipse.w <= 0.0:
		return false
	var e := ((p - Vector2(edge_ellipse.x, edge_ellipse.y)) / Vector2(edge_ellipse.z, edge_ellipse.w)).length()
	return rng.randf() < smoothstep(0.55, 1.05, e) * 0.85


## Where one of `layer` would stand at `p`, or null if it isn't allowed there.
func _place(terrain: Terrain3D, layer: ScatterLayer, p: Vector2, s: float, yaw: float) -> Variant:
	var at := Vector3(p.x, 0.0, p.y)
	var h: float = terrain.data.get_height(at)
	if is_nan(h) or h < SAND_HEIGHT:
		return null
	at.y = h
	if not layer.collide and h > SNOW_HEIGHT:
		return null
	var n: Vector3 = terrain.data.get_normal(at)
	if n.y < layer.min_normal_y:
		return null
	if not _allowed(layer, terrain.data.get_control_base_id(at)):
		return null
	if layer.clearance > 0.0:  # bigger things keep off the path's edges too
		for o in [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)]:
			if not _allowed(layer, terrain.data.get_control_base_id(at + o * layer.clearance)):
				return null
	if h < _highest_water and WaterBody.depth_at(get_tree(), at) > 0.0:  # (no water stands above its surface)
		return null
	for k in _keep_out_grid.get(Vector2i((p / KEEP_OUT_CELL).floor()), []):
		var r: float = k.z + layer.clearance
		if (p.x - k.x) * (p.x - k.x) + (p.y - k.y) * (p.y - k.y) < r * r:
			return null
	var basis := Basis(Vector3.UP, yaw)
	if layer.align_to_slope:
		basis = Basis(Quaternion(Vector3.UP, n)) * basis
	return Transform3D(basis.scaled(Vector3.ONE * s), at)


func _collect_keep_out() -> void:
	_keep_out = keep_out_spots(get_tree(), node_radius, prop_radius, building_margin)
	for c in clear_spots:
		_keep_out.append(c)
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player:
		_keep(player.global_position, spawn_radius)
	# each spot filed under every KEEP_OUT_CELL square it (plus any layer's clearance) reaches, so a
	# spot is only checked against the few near it
	var reach := 0.0
	for layer in layers:
		reach = maxf(reach, layer.clearance)
	_keep_out_grid.clear()
	for k in _keep_out:
		var r := k.z + reach
		var lo := Vector2i((Vector2(k.x - r, k.y - r) / KEEP_OUT_CELL).floor())
		var hi := Vector2i((Vector2(k.x + r, k.y + r) / KEEP_OUT_CELL).floor())
		for cy in range(lo.y, hi.y + 1):
			for cx in range(lo.x, hi.x + 1):
				var key := Vector2i(cx, cy)
				if not _keep_out_grid.has(key):
					_keep_out_grid[key] = []
				_keep_out_grid[key].append(k)
	_highest_water = -INF
	for w in get_tree().get_nodes_in_group("water"):
		_highest_water = maxf(_highest_water, (w as WaterBody).surface_height)


## The circles (x, z, radius) plants keep out of: round gatherable nodes, props and buildings.
## Also used by GrassField.
static func keep_out_spots(tree: SceneTree, node_r: float, prop_r: float, margin: float) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for n in tree.get_nodes_in_group("gatherable"):
		var at := (n as Node3D).global_position
		out.append(Vector3(at.x, at.z, node_r))
	# round an ore wall's block of rock (its middle is OreWall.DEPTH / 2 behind the face; not named:
	# OreWall needs the autoloads, which a tool script compiling this wouldn't have yet)
	for w in tree.get_nodes_in_group("ore_wall"):
		var at := (w as Node3D).global_transform * Vector3(0, 0, -2.0)
		out.append(Vector3(at.x, at.z, 3.2 + margin))
	for p in tree.get_nodes_in_group("prop"):
		var at := (p as Node3D).global_position
		out.append(Vector3(at.x, at.z, maxf((p as Prop).footprint_radius() + 0.5, prop_r)))
	for b in tree.get_nodes_in_group("building"):
		var at := (b as Node3D).global_position
		out.append(Vector3(at.x, at.z, (b as Building).footprint_radius() + margin))
	for f in tree.get_nodes_in_group("fixture"):  # (the barn, the chapel... Fixture)
		var at := (f as Node3D).global_position
		out.append(Vector3(at.x, at.z, float(f.call("footprint_radius")) + margin))
	return out


func _keep(at: Vector3, radius: float) -> void:
	_keep_out.append(Vector3(at.x, at.z, radius))


func _build_cells(layer: ScatterLayer, mesh: Mesh, cells: Dictionary[Vector2i, Array]) -> void:
	var material := PaletteMaterial.for_mesh(mesh)  # (weathered stones: the rock material)
	var dressed := theme != null
	if PaletteMaterial.has_cards(mesh):
		material = PaletteMaterial.FOLIAGE  # leaf cards: their own wind
	elif layer.sway > 0.0:
		dressed = false
		var sway := ShaderMaterial.new()
		sway.shader = SWAY
		sway.set_shader_parameter("palette", PALETTE.get_shader_parameter("palette"))
		sway.set_shader_parameter("strength", layer.sway)
		material = sway
	for key in cells:
		var xforms: Array = cells[key]
		var mmi := MultiMeshInstance3D.new()
		# centred on its cell, so the visibility range is measured from the middle of the cell
		var centre := Vector3((key.x + 0.5) * CELL, 0.0, (key.y + 0.5) * CELL)
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh
		mm.instance_count = xforms.size()
		for i in xforms.size():
			var t: Transform3D = xforms[i]
			mm.set_instance_transform(i, Transform3D(t.basis, t.origin - centre))
		mmi.multimesh = mm
		mmi.material_override = material
		if dressed:  # (instance uniforms are per MultiMesh: the cell's whole layer wears one look)
			NodeTheme.dress(mmi, theme.look(hash([seed, key.x, key.y]), hash([seed, key.x, key.y, layer.model.resource_path])))
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if layer.cast_shadow \
			else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if layer.visible_distance > 0.0:
			mmi.visibility_range_end = layer.visible_distance
			mmi.visibility_range_end_margin = 8.0
			mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		add_child(mmi)
		mmi.global_position = centre


## One static body with a box per placed instance (boulders), or a `size` box on each one's
## origin (tree trunks).
func _build_collision(mesh: Mesh, xforms: Array[Transform3D], size := Vector3.ZERO) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	add_child(body)
	var aabb := mesh.get_aabb()
	for t in xforms:
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		# size the box rather than scaling the shape (physics wants unscaled shapes)
		var s := t.basis.get_scale().x
		if size != Vector3.ZERO:
			box.size = size * s
			shape.shape = box
			body.add_child(shape)
			shape.global_transform = Transform3D(t.basis.orthonormalized(), t.origin + Vector3.UP * size.y * 0.5 * s)
			continue
		box.size = aabb.size * 0.85 * s  # a little inside the lumpy outline
		shape.shape = box
		body.add_child(shape)
		shape.global_transform = Transform3D(t.basis.orthonormalized(), t * aabb.get_center())


static func _mesh_of(model: PackedScene) -> Mesh:
	if model == null:
		return null
	var inst := model.instantiate()
	var found := inst.find_children("*", "MeshInstance3D", true, false)
	var mesh: Mesh = (found[0] as MeshInstance3D).mesh if not found.is_empty() else null
	inst.free()
	return mesh
