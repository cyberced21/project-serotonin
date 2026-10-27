class_name OreWall
extends ResourceNode
## One panel of a quarry's ore wall (plans/ore-walls.md): a block of rock WIDTH across, HEIGHT
## tall and DEPTH deep, dug back over many visits. It's cut into LAYERS layers front to back, each
## a few dozen pieces (models/walls/panel_<n>.glb, from make_models.py's ore_walls). A hit knocks
## out the piece struck and a neighbour or two; what's dug stays dug (saved). Once a layer is gone
## the next one is the face, and after the last there's only bedrock.
##
## It's a ResourceNode so the player aims and swings at it like any rock, but it works its own
## way: it never breaks or grows back, and the piece struck decides what the hit needs.
## Panel space: x across (-WIDTH/2..WIDTH/2), y up from the foot, z out of the face (the face at
## 0, the back at -DEPTH).

const TEMPLATES := 4
const LAYERS := 8
const WIDTH := 3.0
const HEIGHT := 4.0
const DEPTH := 4.0
const LAYER_DEPTH := DEPTH / LAYERS
const WALL_MATERIAL := preload("res://materials/node_wall.tres")
## The pieces get their own collision (a hull each) while the player is this close (m); further
## off one box stands in for the whole panel.
const NEAR := 14.0
## How far into the wall (m) from the hit point to look for the piece struck.
const AIM_DEPTH := 0.08

## Which of the baked panels (models/walls/panel_<n>) this one is cut like.
@export_range(0, 3) var template := 0

## Layer -> {piece index: true} for the pieces dug out.
var _gone: Array[Dictionary] = []
## The first layer with anything left (LAYERS: down to bedrock).
var front := 0
## Layer -> its MeshInstance3D, made once it's needed (drawn from the face back to just past the
## deepest layer dug into).
var _layer_mesh: Array[MeshInstance3D] = []
## The piece under the crosshair: [layer, index], or [] for none.
var _aimed: Array = []
var _near := false
var _piece_shapes := {}  # layer * 1000 + index -> its CollisionShape3D, while near
var _check_in := 0.0

static var _cache := {}  # template -> its pieces (see _template)


func _ready() -> void:
	add_to_group("ore_wall")
	visual.visible = true
	rubble.visible = false
	chips.color = chip_color
	_gone.resize(LAYERS)
	for k in LAYERS:
		_gone[k] = {}
	_layer_mesh.resize(LAYERS)
	hits_left = 1
	_fit_box()
	_refresh_layers()
	SaveGame.register(StringName("wall:" + String(save_id)) if not save_id.is_empty() else StringName("wall:%s" % get_path()), self)
	set_process(true)


func _process(delta: float) -> void:
	_check_in -= delta
	if _check_in > 0.0:
		return
	_check_in = 0.4
	var cam := get_viewport().get_camera_3d()
	var near := cam != null and cam.global_position.distance_to(global_transform * Vector3(0, HEIGHT * 0.5, -DEPTH * 0.5)) < NEAR
	if near != _near:
		_near = near
		_rebuild_shapes()


# --- the template ----------------------------------------------------------------------------

## The baked panel's pieces, loaded once: per layer, {"mesh": the layer merged into one ArrayMesh
## (piece index + 1 in UV2.x), "pieces": [{"name", "mesh" (centred), "xform", "seed", "centre",
## "points" (hull, panel space), "links": [indices]}]}.
static func _template(n: int) -> Array:
	if _cache.has(n):
		return _cache[n]
	var base := "res://models/walls/panel_%d" % n
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(base + ".pieces.json"))
	var inst := (load(base + ".glb") as PackedScene).instantiate()
	var by_name := {}
	for m in inst.find_children("*", "MeshInstance3D", true, false):
		var xform := Transform3D.IDENTITY
		var node: Node = m
		while node != inst:
			xform = (node as Node3D).transform * xform if node is Node3D else xform
			node = node.get_parent()
		by_name[String(m.name)] = [(m as MeshInstance3D).mesh, xform]
	var layers := []
	for names: Array in data["layers"]:
		var index := {}
		var pieces := []
		for nm: String in names:
			if not by_name.has(nm):
				continue
			index[nm] = pieces.size()
			var s: Array = data["seeds"][nm]
			var mesh: Mesh = by_name[nm][0]
			var xf: Transform3D = by_name[nm][1]
			var seen := {}
			var points := PackedVector3Array()
			for surf in mesh.get_surface_count():
				for v: Vector3 in mesh.surface_get_arrays(surf)[Mesh.ARRAY_VERTEX]:
					var p := (xf * v).snappedf(0.005)
					if not seen.has(p):
						seen[p] = true
						points.append(p)
			pieces.append({"name": nm, "mesh": mesh, "xform": xf, "seed": Vector3(s[0], s[1], s[2]),
				"centre": xf * mesh.get_aabb().get_center(), "points": points, "links": PackedInt32Array()})
		for nm: String in index:
			var links := PackedInt32Array()
			for o: String in data["links"].get(nm, []):
				if index.has(o):
					links.append(index[o])
			pieces[index[nm]]["links"] = links
		layers.append({"mesh": _merge(pieces), "pieces": pieces})
	inst.free()
	_cache[n] = layers
	return layers


## One mesh of all a layer's pieces, each vertex carrying its piece's index + 1 in UV2.x (the
## shader hides broken pieces by it, and finds each piece's ore).
static func _merge(pieces: Array) -> ArrayMesh:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var uv2s := PackedVector2Array()
	var colours := PackedColorArray()
	var indices := PackedInt32Array()
	for i in pieces.size():
		var mesh: Mesh = pieces[i]["mesh"]
		var xf: Transform3D = pieces[i]["xform"]
		for s in mesh.get_surface_count():
			var arrays := mesh.surface_get_arrays(s)
			var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var n: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV] if arrays[Mesh.ARRAY_TEX_UV] else PackedVector2Array()
			var col: PackedColorArray = arrays[Mesh.ARRAY_COLOR] if arrays[Mesh.ARRAY_COLOR] else PackedColorArray()
			var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] else PackedInt32Array(range(v.size()))
			var at := verts.size()
			for k in v.size():
				verts.append(xf * v[k])
				normals.append((xf.basis * n[k]).normalized())
				uvs.append(uv[k] if not uv.is_empty() else Vector2.ZERO)
				uv2s.append(Vector2(i + 1, 0))
				colours.append(col[k] if not col.is_empty() else Color.WHITE)
			for k in idx:
				indices.append(at + k)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_TEX_UV2] = uv2s
	arrays[Mesh.ARRAY_COLOR] = colours
	arrays[Mesh.ARRAY_INDEX] = indices
	var out := ArrayMesh.new()
	out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return out


func _layer_pieces(layer: int) -> Array:
	return _template(template)[layer]["pieces"]


func _piece(layer: int, i: int) -> Dictionary:
	return _layer_pieces(layer)[i]


func _is_gone(layer: int, i: int) -> bool:
	return _gone[layer].has(i)


# --- drawing ---------------------------------------------------------------------------------

## The layers drawn: the face back to one past the deepest layer dug into (a gap shows what's
## behind it), capped at the last.
func _drawn_layers() -> Vector2i:
	var last := mini(front + 1, LAYERS - 1)
	for k in range(front, LAYERS):
		if not _gone[k].is_empty():
			last = maxi(last, mini(k + 1, LAYERS - 1))
	return Vector2i(front, last)


func _refresh_layers() -> void:
	var drawn := _drawn_layers()
	for k in LAYERS:
		var want := k >= drawn.x and k <= drawn.y and front < LAYERS
		if want and _layer_mesh[k] == null:
			_layer_mesh[k] = _make_layer(k)
		if _layer_mesh[k]:
			_layer_mesh[k].visible = want
			if want:
				_update_mask(k)


func _make_layer(k: int) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.name = "Layer%d" % k
	m.mesh = _template(template)[k]["mesh"]
	m.material_override = _layer_material(k)
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if k == front else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if draw_distance > 0.0:
		m.visibility_range_end = draw_distance
		m.visibility_range_end_margin = 12.0
		m.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	visual.add_child(m)
	_surfaces.append(m)
	_dress(m)
	return m


func _layer_material(_k: int) -> ShaderMaterial:
	return WALL_MATERIAL


func _update_mask(k: int) -> void:
	var words := [0, 0, 0, 0]
	for i: int in _gone[k]:
		if i < 96:
			words[i / 24] |= 1 << (i % 24)
	_layer_mesh[k].set_instance_shader_parameter("pieces_gone", Vector4(words[0], words[1], words[2], words[3]))


# --- collision -------------------------------------------------------------------------------

## One box over what's left of the panel (the base scene's CollisionShape3D): all of it while the
## player is far off; behind the drawn layers while near, where the pieces have their own hulls.
func _fit_box() -> void:
	var from := front
	if _near:
		from = _drawn_layers().y + 1
	if from >= LAYERS:
		collision.set_deferred("disabled", true)
		return
	collision.set_deferred("disabled", false)
	var box := BoxShape3D.new()
	var front_z := -from * LAYER_DEPTH - (0.15 if _near else 0.0)  # (near: clear of the hulls in front)
	box.size = Vector3(WIDTH, HEIGHT, DEPTH + front_z)
	collision.shape = box
	collision.position = Vector3(0, HEIGHT * 0.5, (front_z - DEPTH) * 0.5)


func _rebuild_shapes() -> void:
	for s: Node in _piece_shapes.values():
		s.queue_free()
	_piece_shapes.clear()
	if _near:
		var drawn := _drawn_layers()
		for k in range(drawn.x, drawn.y + 1):
			for i in _layer_pieces(k).size():
				if not _is_gone(k, i):
					_add_shape(k, i)
	_fit_box()


func _add_shape(k: int, i: int) -> void:
	var shape := CollisionShape3D.new()
	var hull := ConvexPolygonShape3D.new()
	hull.points = _piece(k, i)["points"]
	shape.shape = hull
	add_child(shape)
	_piece_shapes[k * 1000 + i] = shape


func _drop_shape(k: int, i: int) -> void:
	var s: Node = _piece_shapes.get(k * 1000 + i)
	if s:
		s.queue_free()
		_piece_shapes.erase(k * 1000 + i)


# --- aiming ----------------------------------------------------------------------------------

## The piece a point on the wall's surface belongs to (pieces are Voronoi cells: the one whose
## seed is nearest a point just inside the surface), among those still there in the drawn layers.
func _piece_at(point: Vector3, normal: Vector3) -> Array:
	var p := to_local(point - normal * AIM_DEPTH)
	var drawn := _drawn_layers()
	var best: Array = []
	var best_d := INF
	for k in range(drawn.x, drawn.y + 1):
		var pieces := _layer_pieces(k)
		for i in pieces.size():
			if _is_gone(k, i):
				continue
			var d := (pieces[i]["seed"] as Vector3).distance_squared_to(p)
			if d < best_d:
				best_d = d
				best = [k, i]
	return best


## Called by the player while the crosshair is on the wall: lights the piece it's on.
func aim_at(point: Vector3, normal: Vector3) -> void:
	var aimed := _piece_at(point, normal)
	if aimed == _aimed:
		return
	_aimed = aimed
	_show_aim()


func _show_aim() -> void:
	for k in LAYERS:
		if _layer_mesh[k]:
			_layer_mesh[k].set_instance_shader_parameter("aim_piece", float(_aimed[1]) if not _aimed.is_empty() and _aimed[0] == k else -1.0)


func is_available() -> bool:
	return front < LAYERS


func set_highlighted(on: bool) -> void:
	for s in _surfaces:
		s.set_instance_shader_parameter("highlight", 1.0 if on else 0.0)
	if not on:
		_aimed = []
		_show_aim()


# --- digging ---------------------------------------------------------------------------------

func hit(info: HitInfo) -> bool:
	if front >= LAYERS:
		return false
	var struck := _piece_at(info.position, info.normal)
	if struck.is_empty():
		return false
	if not can_gather():
		_deflect(info)
		return false
	_cut += (1.0 + Tools.tiers_above(tool_type, tool_tier)) * _power_scale()
	var cuts := int(_cut)
	_cut -= cuts
	var double := cuts > 0 and randf() < Village.stat(&"double_hit_chance")
	_hit_effects(info, 1.0)
	Juice.shake(shake_hit)
	Juice.hitstop(hitstop_hit)
	last_impact = 1.0
	if cuts == 0:  # under-levelled: a hit that falls short of knocking anything out
		PopupText.spawn(get_parent(), info.position + Vector3.UP * 0.4, under_text(), UNDER_COLOR, 7)
		Sfx.play_at(hit_layers, info.position)
		return true
	_tool_ring(info)
	if double:
		PopupText.spawn(get_parent(), info.position + Vector3.UP * 0.5, "Sharp!", SHARP_COLOR, 9)
	# a piece and maybe a neighbour; a better pick takes a neighbour or two more
	var out := _knock_out_from(struck, info, randi_range(0, 1) + mini(cuts - 1, 2) + (1 if double else 0))
	Sfx.play_at(hit_layers, info.position, randf_range(0.95, 1.05), 2.0 if out.size() > 2 else 0.0)
	_award_xp(xp_per_hit * out.size())
	last_impact = 1.5 if out.size() > 2 else 1.0
	_dug(out)
	return true


## Knocks out the piece struck and up to `extra` of its neighbours nearest the hit. The pieces
## that came out, as [layer, index].
func _knock_out_from(struck: Array, info: HitInfo, extra: int) -> Array:
	var k: int = struck[0]
	var at := to_local(info.position)
	var near: Array = []
	for o in _piece(k, struck[1])["links"]:
		if not _is_gone(k, o):
			near.append(o)
	near.sort_custom(func(a: int, b: int) -> bool:
		return (_piece(k, a)["centre"] as Vector3).distance_squared_to(at) < (_piece(k, b)["centre"] as Vector3).distance_squared_to(at))
	var out: Array = [struck]
	for o in near.slice(0, maxi(extra, 0)):
		out.append([k, o])
	for p in out:
		_pop_piece(p[0], p[1], info)
	return out


## Takes a piece out of the wall and throws a copy of it.
func _pop_piece(k: int, i: int, info: HitInfo) -> void:
	_gone[k][i] = true
	_drop_shape(k, i)
	var piece := MeshInstance3D.new()
	piece.mesh = _piece(k, i)["mesh"]
	piece.material_override = ROCK_MATERIAL
	var xf: Transform3D = global_transform * (_piece(k, i)["xform"] as Transform3D)
	var out := (global_basis * Vector3(0, 0.3, 1)).normalized()
	_throw(piece, xf.orthonormalized(), (out + (info.from - info.position).normalized() * 0.3).normalized(), debris_speed * 0.6)
	if hit_fx:
		var c := global_transform * (_piece(k, i)["centre"] as Vector3)
		HitFx.spawn(hit_fx, get_parent(), c, info.normal, -info.normal, chip_color, Color(0, 0, 0, 0), 0.6)


## After pieces come out: the layers drawn, the face moving back once a layer's gone, the hulls
## and box, the save.
func _dug(out: Array) -> void:
	var layers := {}
	for p in out:
		layers[p[0]] = true
	while front < LAYERS and _gone[front].size() >= _layer_pieces(front).size():
		front += 1
		_layer_cleared()
	_aimed = []
	_refresh_layers()
	if _near:
		_rebuild_shapes()
	else:
		_fit_box()
	SaveGame.mark_dirty()


func _layer_cleared() -> void:
	if _layer_mesh[front - 1]:
		_layer_mesh[front - 1].visible = false
	var at := global_transform * Vector3(0, HEIGHT * 0.6, -front * LAYER_DEPTH)
	if front >= LAYERS:
		PopupText.spawn(get_parent(), at, "Bedrock!", ore_color, 12)
		_award_xp(xp_on_break * 2, true)
	else:
		PopupText.spawn(get_parent(), at, "Layer %d of %d" % [front + 1, LAYERS], ore_color, 11)
		_award_xp(xp_on_break, true)
	Juice.shake(shake_break * 0.5)


func pull(info: HitInfo) -> void:
	Sfx.play_at(pull_layers, info.position)
	var piece := MeshInstance3D.new()
	piece.mesh = BoxMesh.new()
	piece.material_override = NODE_SURFACE
	piece.set_instance_shader_parameter("albedo", chip_color)
	var rot := Basis.from_euler(Vector3(randf(), randf(), randf()) * TAU)
	_throw(piece, Transform3D(rot, info.position + info.normal * 0.06), (info.normal - info.away() * 0.6).normalized(), debris_speed * 0.8, 0.12)


# --- saving ----------------------------------------------------------------------------------

func to_dict() -> Dictionary:
	var gone := []
	for k in LAYERS:
		gone.append(_gone[k].keys())
	return {"gone": gone}


func from_dict(d: Dictionary) -> void:
	var gone: Array = d.get("gone", [])
	for k in mini(gone.size(), LAYERS):
		_gone[k].clear()
		for i in gone[k]:
			if int(i) < _layer_pieces(k).size():
				_gone[k][int(i)] = true
	front = 0
	while front < LAYERS and _gone[front].size() >= _layer_pieces(front).size():
		front += 1
	_refresh_layers()
	_rebuild_shapes()
