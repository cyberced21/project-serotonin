class_name ForestStand
extends SceneryScatter
## A whole wood of choppable trees, drawn cheaply (plans/pinewood-stand.md): a map editor patch
## with "Stand" ticked. The bake (tools/bake_layout.gd) calls place(), which picks every tree's
## spot the way NodeSpawner would (seeded; spacing; off paths, water, steep ground; clear of what's
## already there), and writes the result into layout.tscn: where each tree stands, its kind and its
## look (the model or a variant). The game only draws them: each tree as a copy, at size 1, so a
## real tree can stand in for it without it showing. The copies are the trees' own Body_* meshes,
## a MultiMesh per look per STAND_CELL square, one surface per material.
## Each tree's key, `<save_prefix>_<n>`, is its draw number: moving something in the map editor
## drops only the trees it now covers, the rest keep theirs.
## In the game the trees near you wake: a real ResourceNode (saved under `node:<key>`) stands in
## for the copy, which is hidden. Walk away and it goes back to sleep, a copy again.

## The copies are filed in squares this size (m): bigger than SceneryScatter.CELL, as each look
## is its own MultiMesh in a square.
const STAND_CELL := 64.0
## A tree this near the player (m) wakes...
const WAKE_RANGE := 14.0
## ... and goes back to sleep past this (the gap stops it flickering at the edge), unless it's busy.
const SLEEP_RANGE := 20.0
## How often the stand looks round the player (s).
const CHECK_EVERY := 0.25
## Trees made in one frame, at most (a jog into the forest mustn't hitch).
const WAKE_PER_FRAME := 2
## A safety net: never more than this many awake.
const MAX_AWAKE := 40
## The trees are filed in squares this size (m) to find the ones near the player.
const NEAR_CELL := 16.0
## How far a tree's foot sinks into the ground (NodeSpawner.sink), so it doesn't float on slopes.
const SINK := 0.15
const MAX_TRIES_PER_TREE := 20
## A surface format's custom-channel bits (CUSTOM0-3: the leaf cards' wind data).
const _CUSTOM_FORMATS := (Mesh.ARRAY_FORMAT_CUSTOM_MASK << Mesh.ARRAY_FORMAT_CUSTOM_BASE) \
	| (Mesh.ARRAY_FORMAT_CUSTOM_MASK << (Mesh.ARRAY_FORMAT_CUSTOM_BASE + Mesh.ARRAY_FORMAT_CUSTOM_BITS)) \
	| (Mesh.ARRAY_FORMAT_CUSTOM_MASK << (Mesh.ARRAY_FORMAT_CUSTOM_BASE + 2 * Mesh.ARRAY_FORMAT_CUSTOM_BITS)) \
	| (Mesh.ARRAY_FORMAT_CUSTOM_MASK << (Mesh.ARRAY_FORMAT_CUSTOM_BASE + 3 * Mesh.ARRAY_FORMAT_CUSTOM_BITS))

## The kinds of tree (ResourceNode scenes), each with its variants.
@export var entries: Array[SpawnEntry] = []
@export var save_prefix := "stand"
@export_group("Baked")
## Every tree, by index: its draw number (its key), where its foot is, its turn, which entry,
## which look (0 = the entry's model, v = variant v).
@export var ids := PackedInt32Array()
@export var spots := PackedVector3Array()
@export var yaws := PackedFloat32Array()
@export var kinds := PackedInt32Array()
@export var looks := PackedInt32Array()

var _copy_of: Array[MultiMesh] = []  # tree -> the MultiMesh its copy is in
var _copy_at := PackedInt32Array()  # ... which instance it is
var _copy_centre := PackedVector3Array()  # ... and where that MultiMesh stands
var _shown := PackedByteArray()  # tree -> 1 while its copy is drawn
var _trunk_of: Array[CollisionShape3D] = []  # tree -> its trunk box (or null)
var _near: Dictionary[Vector2i, PackedInt32Array] = {}  # NEAR_CELL square -> its trees
var _awake: Dictionary[int, ResourceNode] = {}
var _waking: Array[int] = []  # the trees to wake, nearest first
var _check_in := 0.0
var _player: Node3D


func _scatter() -> void:
	add_to_group("forest_stand")
	if not spots.is_empty():
		_build_copies()
		_build_trunks()
		for i in spots.size():
			_near.get_or_add(_near_cell(spots[i]), PackedInt32Array()).append(i)
	set_process(not spots.is_empty())
	_finish()


func size() -> int:
	return spots.size()


func key_of(i: int) -> StringName:
	return StringName("%s_%04d" % [save_prefix, ids[i]])


func xform_of(i: int) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, yaws[i]), spots[i])


## Tree `i`'s real tree while it's awake, else null.
func awake_tree(i: int) -> ResourceNode:
	return _awake.get(i)


func awake_count() -> int:
	return _awake.size()


## Whether tree `i`'s copy is drawn (asleep) or hidden (awake).
## (Its own record: a headless MultiMesh doesn't keep instance transforms to read back.)
func copy_shown(i: int) -> bool:
	return _copy_of[i] != null and _shown[i] == 1


# --- waking and sleeping ------------------------------------------------------------------------

func _process(delta: float) -> void:
	_check_in -= delta
	if _check_in <= 0.0:
		_check_in = CHECK_EVERY
		_check()
	for k in WAKE_PER_FRAME:
		if _waking.is_empty():
			break
		_wake(_waking.pop_front())


## Sends the far trees to sleep and lines up the near ones to wake.
func _check() -> void:
	if not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node3D
		if _player == null:
			return
	var at := _player.global_position
	for i in _awake.keys():
		if _flat_distance(i, at) > SLEEP_RANGE and not _awake[i].is_busy():
			_sleep(i)
	var want: Array[int] = []
	var c := _near_cell(at)
	var reach := ceili(WAKE_RANGE / NEAR_CELL)
	for y in range(c.y - reach, c.y + reach + 1):
		for x in range(c.x - reach, c.x + reach + 1):
			for i in _near.get(Vector2i(x, y), PackedInt32Array()):
				if not _awake.has(i) and _flat_distance(i, at) < WAKE_RANGE:
					want.append(i)
	want.sort_custom(func(a: int, b: int) -> bool: return _flat_distance(a, at) < _flat_distance(b, at))
	_waking = want.slice(0, maxi(MAX_AWAKE - _awake.size(), 0))


## A real tree in place of tree `i`'s copy.
func _wake(i: int) -> void:
	if _awake.has(i) or _awake.size() >= MAX_AWAKE:
		return
	var e := entries[kinds[i]]
	var tree := e.scene.instantiate() as ResourceNode
	tree.save_id = key_of(i)
	tree.name = String(key_of(i))
	if looks[i] > 0:
		tree.model = e.variants[looks[i] - 1]
	tree.transform = global_transform.affine_inverse() * xform_of(i)
	add_child(tree)
	_awake[i] = tree
	_show_copy(i, false)


## Tree `i` back to a copy.
func _sleep(i: int) -> void:
	var tree: ResourceNode = _awake[i]
	_awake.erase(i)
	tree.queue_free()
	_show_copy(i, true)


## Tree `i`'s copy drawn or hidden (a zero-sized instance), its trunk box with it (an awake tree
## has its own).
func _show_copy(i: int, on: bool) -> void:
	_shown[i] = 1 if on else 0
	if _copy_of[i]:
		var t := xform_of(i)
		_copy_of[i].set_instance_transform(_copy_at[i], Transform3D(t.basis, t.origin - _copy_centre[i])
			if on else Transform3D(Basis.from_scale(Vector3.ZERO), Vector3.ZERO))
	if _trunk_of[i]:
		_trunk_of[i].disabled = not on


func _flat_distance(i: int, at: Vector3) -> float:
	return Vector2(spots[i].x - at.x, spots[i].z - at.z).length()


static func _near_cell(p: Vector3) -> Vector2i:
	return Vector2i(floori(p.x / NEAR_CELL), floori(p.z / NEAR_CELL))


# --- placing (the bake) -----------------------------------------------------------------------------

## Picks the trees' spots: up to `count`, inside `polygon` (world XZ) or `ring` (centre x, z, inner
## and outer radius), `spacing` apart, on `allowed` ground ids (empty = anything not bare), thinning
## out over the last `fringe` metres to the edge. Run in the world it'll stand in, after
## everything it must keep clear of.
func place(polygon: PackedVector2Array, ring: Vector4, count: int, spacing: float, rng_seed: int,
		allowed: Array[int], fringe: float) -> void:
	var terrain := get_tree().get_first_node_in_group("terrain") as Terrain3D
	ids.clear()
	spots.clear()
	yaws.clear()
	kinds.clear()
	looks.clear()
	if terrain == null or terrain.data == null or entries.is_empty():
		return
	var box := Rect2(Vector2(ring.x - ring.w, ring.y - ring.w), Vector2(ring.w, ring.w) * 2.0)
	if ring.w <= 0.0:
		box = Rect2(polygon[0], Vector2.ZERO)
		for p in polygon:
			box = box.expand(p)
	_collect_keep_out()
	var ground := ScatterLayer.new()
	ground.allowed_ids = allowed
	ground.min_normal_y = 0.75
	ground.clearance = 1.0  # (off the path's edges)
	ground.collide = true  # (trees grow above the snow line too)
	var taken: Dictionary[Vector2i, PackedVector2Array] = {}
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed
	for i in count * MAX_TRIES_PER_TREE:
		if spots.size() >= count:
			break
		# draw every random number before checking, so a rejected spot doesn't shift the rest
		var p := Vector2(rng.randf_range(box.position.x, box.end.x), rng.randf_range(box.position.y, box.end.y))
		if ring.w > 0.0:  # spread evenly over the ring's area (as NodeSpawner)
			var r := sqrt(lerpf(ring.z * ring.z, ring.w * ring.w, (p.x - box.position.x) / box.size.x))
			p = Vector2(ring.x, ring.y) + Vector2.from_angle((p.y - box.position.y) / box.size.y * TAU) * r
		var pick := rng.randf()
		var yaw := rng.randf() * TAU
		var thin := rng.randf()
		var edge := _to_edge(p, polygon, ring)
		if edge < 0.0 or (fringe > 0.0 and thin < (1.0 - smoothstep(0.0, fringe, edge)) * 0.85):
			continue
		if _crowded(taken, p, spacing):
			continue
		var at: Variant = _place(terrain, ground, p, 1.0, yaw)
		if at == null:
			continue
		var kind := _pick_kind(pick)
		if kind < 0:
			continue
		var cluster := hash([rng_seed, floori(p.x / NodeSpawner.CLUSTER_SIZE), floori(p.y / NodeSpawner.CLUSTER_SIZE)])
		ids.append(i)
		spots.append((at as Transform3D).origin - Vector3.UP * SINK)
		yaws.append(yaw)
		kinds.append(kind)
		looks.append(NodeSpawner._pick_look(entries[kind].variants.size(), cluster, hash(String(key_of(ids.size() - 1)))))
		taken.get_or_add(Vector2i((p / spacing).floor()), PackedVector2Array()).append(p)
		if frame_budget_ms > 0.0 and i % 64 == 0:
			await get_tree().process_frame


## How far inside the shape `p` is (m), or -1 outside it.
static func _to_edge(p: Vector2, polygon: PackedVector2Array, ring: Vector4) -> float:
	if ring.w > 0.0:
		var r := p.distance_to(Vector2(ring.x, ring.y))
		return -1.0 if r > ring.w or r < ring.z else minf(ring.w - r, r - ring.z if ring.z > 0.0 else INF)
	if not Geometry2D.is_point_in_polygon(p, polygon):
		return -1.0
	var best := INF
	for k in polygon.size():
		var q := Geometry2D.get_closest_point_to_segment(p, polygon[k], polygon[(k + 1) % polygon.size()])
		best = minf(best, p.distance_to(q))
	return best


static func _crowded(taken: Dictionary[Vector2i, PackedVector2Array], p: Vector2, spacing: float) -> bool:
	var c := Vector2i((p / spacing).floor())
	for y in range(c.y - 1, c.y + 2):
		for x in range(c.x - 1, c.x + 2):
			for q in taken.get(Vector2i(x, y), PackedVector2Array()):
				if p.distance_squared_to(q) < spacing * spacing:
					return true
	return false


## Which entry a `pick` (0-1) lands on, by weight, or -1.
func _pick_kind(pick: float) -> int:
	var total := 0.0
	for e in entries:
		total += e.weight
	if total <= 0.0:
		return -1
	var x := pick * total
	for k in entries.size():
		x -= entries[k].weight
		if x <= 0.0:
			return k
	return entries.size() - 1


## A tree scene's model variants (models/variants/<model>_v1.glb...), for the bake to fill an
## entry's `variants`.
static func variants_of(scene: PackedScene) -> Array[PackedScene]:
	var out: Array[PackedScene] = []
	var model := model_of_scene(scene)
	if model == null:
		return out
	var base := model.resource_path.get_file().get_basename()
	for v in range(1, 100):
		var path := "res://models/variants/%s_v%d.glb" % [base, v]
		if not ResourceLoader.exists(path):
			break
		out.append(load(path))
	return out


## The model a ResourceNode scene wears (its `model`, from it or the scene it inherits).
static func model_of_scene(scene: PackedScene) -> PackedScene:
	var inst := scene.instantiate()
	var model: PackedScene = inst.get("model")
	inst.free()
	return model


# --- drawing ------------------------------------------------------------------------------------

## The model tree `i` wears.
func model_of(i: int) -> PackedScene:
	var e := entries[kinds[i]]
	return e.variants[looks[i] - 1] if looks[i] > 0 else model_of_scene(e.scene)


func _build_copies() -> void:
	_copy_of.resize(spots.size())
	_copy_at.resize(spots.size())
	_copy_centre.resize(spots.size())
	_shown.resize(spots.size())
	_shown.fill(1)
	var cells: Dictionary[Vector3i, Array] = {}  # (kind * 1000 + look, cell x, cell z) -> its trees
	for i in spots.size():
		var o := spots[i]
		cells.get_or_add(Vector3i(kinds[i] * 1000 + looks[i], floori(o.x / STAND_CELL), floori(o.z / STAND_CELL)), []).append(i)
	var meshes := {}  # kind * 1000 + look -> its copy
	for key in cells:
		var trees: Array = cells[key]
		if not meshes.has(key.x):
			meshes[key.x] = copy_mesh(model_of(trees[0]))
		var mesh: ArrayMesh = meshes[key.x]
		if mesh == null:
			continue
		var centre := Vector3((key.y + 0.5) * STAND_CELL, 0.0, (key.z + 0.5) * STAND_CELL)
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh
		mm.instance_count = trees.size()
		for j in trees.size():
			var t := xform_of(trees[j])
			mm.set_instance_transform(j, Transform3D(t.basis, t.origin - centre))
			_copy_of[trees[j]] = mm
			_copy_at[trees[j]] = j
			_copy_centre[trees[j]] = centre
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Copies_%d_%d_%d" % [key.x, key.y, key.z]
		mmi.multimesh = mm
		mmi.set_instance_shader_parameter("foot", ResourceNode.TRUNK_FOOT)  # (as ResourceNode._dress)
		add_child(mmi)
		mmi.global_position = centre


## One mesh of a tree model's Body_* parts as they stand (no stump), a surface per material: what
## ResourceNode._apply_model would build, merged.
static func copy_mesh(model: PackedScene) -> ArrayMesh:
	if model == null:
		return null
	var inst := model.instantiate()
	var groups := {}  # [material, format] -> [arrays...]
	for m in inst.find_children("*", "MeshInstance3D", true, false):
		if not m.name.to_lower().begins_with("body_"):
			continue
		var xform := Transform3D.IDENTITY  # relative to the model root (it isn't in the tree)
		var n: Node = m
		while n != inst:
			xform = (n as Node3D).transform * xform if n is Node3D else xform
			n = n.get_parent()
		var mesh: Mesh = (m as MeshInstance3D).mesh
		var material := PaletteMaterial.for_mesh(mesh)
		for s in mesh.get_surface_count():
			groups.get_or_add([material, mesh.surface_get_format(s)], []).append(_moved(mesh.surface_get_arrays(s), xform))
	inst.free()
	var out := ArrayMesh.new()
	for group in groups:
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _joined(groups[group]), [], {}, group[1] & _CUSTOM_FORMATS)
		out.surface_set_material(out.get_surface_count() - 1, group[0])
	return out


## A surface's arrays moved by `xform` (positions, normals, tangents).
static func _moved(arrays: Array, xform: Transform3D) -> Array:
	var out := arrays.duplicate()
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var moved := PackedVector3Array()
	moved.resize(verts.size())
	for v in verts.size():
		moved[v] = xform * verts[v]
	out[Mesh.ARRAY_VERTEX] = moved
	var turn := xform.basis.inverse().transposed()
	if arrays[Mesh.ARRAY_NORMAL] != null:
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var turned := PackedVector3Array()
		turned.resize(normals.size())
		for v in normals.size():
			turned[v] = (turn * normals[v]).normalized()
		out[Mesh.ARRAY_NORMAL] = turned
	if arrays[Mesh.ARRAY_TANGENT] != null:
		var tangents: PackedFloat32Array = (arrays[Mesh.ARRAY_TANGENT] as PackedFloat32Array).duplicate()
		for v in range(0, tangents.size(), 4):
			var t := (xform.basis * Vector3(tangents[v], tangents[v + 1], tangents[v + 2])).normalized()
			tangents[v] = t.x
			tangents[v + 1] = t.y
			tangents[v + 2] = t.z
		out[Mesh.ARRAY_TANGENT] = tangents
	if arrays[Mesh.ARRAY_INDEX] == null:  # (so it can be joined with indexed ones)
		out[Mesh.ARRAY_INDEX] = PackedInt32Array(range(verts.size()))
	return out


## Surfaces of one format end to end, their indices shifted.
static func _joined(parts: Array) -> Array:
	var out: Array = parts[0].duplicate()
	for k in range(1, parts.size()):
		var part: Array = parts[k]
		var base: int = (out[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
		for a in Mesh.ARRAY_MAX:
			if out[a] == null or part[a] == null:
				continue
			if a == Mesh.ARRAY_INDEX:
				var idx: PackedInt32Array = part[a]
				var shifted := PackedInt32Array()
				shifted.resize(idx.size())
				for v in idx.size():
					shifted[v] = idx[v] + base
				out[a] = (out[a] as PackedInt32Array) + shifted
			else:
				out[a] = out[a] + part[a]
	return out


## A box per trunk, the size of its kind's own collision shape.
func _build_trunks() -> void:
	var shapes: Array[CollisionShape3D] = []
	for e in entries:
		var inst := e.scene.instantiate()
		var found := inst.find_children("*", "CollisionShape3D", true, false)
		shapes.append((found[0] as CollisionShape3D).duplicate() if not found.is_empty() else null)
		inst.free()
	var body := StaticBody3D.new()
	body.name = "Trunks"
	body.collision_layer = 1
	body.collision_mask = 0
	add_child(body)
	_trunk_of.resize(spots.size())
	for i in spots.size():
		var proto := shapes[kinds[i]]
		if proto == null:
			continue
		var shape := CollisionShape3D.new()
		shape.shape = proto.shape
		body.add_child(shape)
		shape.global_transform = xform_of(i) * proto.transform
		_trunk_of[i] = shape
	for s in shapes:
		if s:
			s.free()
