class_name StaticMerge
extends RefCounted
## Draws many still meshes as one (plans/crumbs.md, phase 7): a fixture is a few hundred kit and
## palette pieces, each its own draw call in every pass (and again in each shadow cascade). The
## pieces under a node that never move are merged into one mesh, a surface per material, and the
## pieces themselves freed. Cached by `key`, so every copy of a model shares one mesh.

static var _cache := {}  # key -> ArrayMesh


## Merges the MeshInstance3Ds directly under `parent` that `keep` doesn't hold back (it's given
## each one: true leaves it as it is). Returns the merged MeshInstance3D, or null when there were
## fewer than two to merge.
static func merge(parent: Node3D, key: String, keep: Callable) -> MeshInstance3D:
	var pieces: Array[MeshInstance3D] = []
	for c in parent.get_children():
		if c is MeshInstance3D and (c as MeshInstance3D).mesh and c.get_child_count() == 0 and not keep.call(c):
			pieces.append(c)
	if pieces.size() < 2:
		return null
	var mesh: ArrayMesh = _cache.get(key)
	if mesh == null:
		mesh = _merged(pieces)
		_cache[key] = mesh
	var out := MeshInstance3D.new()
	out.name = "Merged"
	out.mesh = mesh
	out.layers = pieces[0].layers
	out.cast_shadow = pieces[0].cast_shadow
	parent.add_child(out)
	for p in pieces:
		parent.remove_child(p)
		p.queue_free()
	return out


## One mesh of the pieces (in their parent's space), a surface for each material they use.
static func _merged(pieces: Array[MeshInstance3D]) -> ArrayMesh:
	var groups := {}  # material -> [pieces' surfaces as [arrays, transform]]
	var order: Array[Material] = []
	for p in pieces:
		for s in p.mesh.get_surface_count():
			var mat: Material = p.material_override if p.material_override else p.get_active_material(s)
			if not groups.has(mat):
				groups[mat] = []
				order.append(mat)
			(groups[mat] as Array).append([p.mesh.surface_get_arrays(s), p.transform])
	var out := ArrayMesh.new()
	for mat in order:
		var parts: Array = groups[mat]
		var has := {}
		for kind in [Mesh.ARRAY_TANGENT, Mesh.ARRAY_COLOR, Mesh.ARRAY_TEX_UV, Mesh.ARRAY_TEX_UV2]:
			has[kind] = parts.any(func(part: Array) -> bool: return part[0][kind] != null)
		var verts := PackedVector3Array()
		var normals := PackedVector3Array()
		var tangents := PackedFloat32Array()
		var colours := PackedColorArray()
		var uvs := PackedVector2Array()
		var uv2s := PackedVector2Array()
		var indices := PackedInt32Array()
		for part: Array in parts:
			var a: Array = part[0]
			var xf: Transform3D = part[1]
			var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
			var n: PackedVector3Array = a[Mesh.ARRAY_NORMAL] if a[Mesh.ARRAY_NORMAL] != null else PackedVector3Array()
			var t: PackedFloat32Array = a[Mesh.ARRAY_TANGENT] if a[Mesh.ARRAY_TANGENT] != null else PackedFloat32Array()
			var col: PackedColorArray = a[Mesh.ARRAY_COLOR] if a[Mesh.ARRAY_COLOR] != null else PackedColorArray()
			var uv: PackedVector2Array = a[Mesh.ARRAY_TEX_UV] if a[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array()
			var uv2: PackedVector2Array = a[Mesh.ARRAY_TEX_UV2] if a[Mesh.ARRAY_TEX_UV2] != null else PackedVector2Array()
			var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX] if a[Mesh.ARRAY_INDEX] != null else PackedInt32Array(range(v.size()))
			var normal_basis := xf.basis.inverse().transposed()
			var at := verts.size()
			for k in v.size():
				verts.append(xf * v[k])
				normals.append((normal_basis * n[k]).normalized() if not n.is_empty() else Vector3.UP)
				if has[Mesh.ARRAY_TANGENT]:
					if t.is_empty():
						tangents.append_array(PackedFloat32Array([1, 0, 0, 1]))
					else:
						var tv := (xf.basis * Vector3(t[k * 4], t[k * 4 + 1], t[k * 4 + 2])).normalized()
						tangents.append_array(PackedFloat32Array([tv.x, tv.y, tv.z, t[k * 4 + 3]]))
				if has[Mesh.ARRAY_COLOR]:
					colours.append(col[k] if not col.is_empty() else Color.WHITE)
				if has[Mesh.ARRAY_TEX_UV]:
					uvs.append(uv[k] if not uv.is_empty() else Vector2.ZERO)
				if has[Mesh.ARRAY_TEX_UV2]:
					uv2s.append(uv2[k] if not uv2.is_empty() else Vector2.ZERO)
			for k in idx:
				indices.append(at + k)
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_NORMAL] = normals
		if has[Mesh.ARRAY_TANGENT]:
			arrays[Mesh.ARRAY_TANGENT] = tangents
		if has[Mesh.ARRAY_COLOR]:
			arrays[Mesh.ARRAY_COLOR] = colours
		if has[Mesh.ARRAY_TEX_UV]:
			arrays[Mesh.ARRAY_TEX_UV] = uvs
		if has[Mesh.ARRAY_TEX_UV2]:
			arrays[Mesh.ARRAY_TEX_UV2] = uv2s
		arrays[Mesh.ARRAY_INDEX] = indices
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		out.surface_set_material(out.get_surface_count() - 1, mat)
	return out
