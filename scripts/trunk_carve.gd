class_name TrunkCarve
extends RefCounted
## The notch an axe cuts into a tree's trunk, carved into the trunk's own mesh.
##
## The trunk is a ringed column standing on its origin along +Y (make_models.py ringed_trunk), with
## dense rings through the chopping band. The first hit picks the notch's ring; every hit then
## pushes the vertices round that ring in toward the middle, deepest where the hit came from and
## less to either side, in a V: a steep upper face and a flatter lower one, like a felling notch.
## Hits from other sides deepen the notch round there instead, so walking round the tree widens it.
## When the tree falls, split() cuts the trunk at the notch's ring into a stump and the log.

## How deep the notch is, per direction round the trunk (bins over a full turn).
const BINS := 32
## How much shallower the notch gets per metre above / below its ring: the upper face slopes
## (about 45 degrees), the lower one is nearly flat.
const SLOPE_UP := 1.1
const SLOPE_DOWN := 3.0
## How far round the trunk one hit carves: the weight is cos(angle off the hit)^SPREAD.
const SPREAD := 1.6
## The core is never carved thinner than this share of the trunk's radius.
const CORE := 0.12
## A face this far off its original direction is cut wood rather than bark (dot of normals).
const CUT_FACE := 0.97
## Palette swatches (art/palette.json "uv", same space as the model's UVs): the notch's cut faces
## are pale wood; the end grain where the trunk is cut through is growth rings, from the outline in
## (share of the way out, swatch): a darker band of sapwood under the bark, then pale and mid
## rings round to the heart.
const CUT_UV := Vector2(0.9375, 0.3125)  # wood.7
const GRAIN := [
	[1.0, Vector2(0.6875, 0.3125)],  # wood.5
	[0.86, Vector2(0.9375, 0.3125)],  # wood.7
	[0.62, Vector2(0.8125, 0.3125)],  # wood.6
	[0.42, Vector2(0.9375, 0.3125)],  # wood.7
	[0.22, Vector2(0.8125, 0.3125)],  # wood.6
]

var original: ArrayMesh
## The notch's ring height (mesh space), or NAN before the first hit.
var ring := NAN
var depth := PackedFloat32Array()

var _arrays: Array
var _verts: PackedVector3Array
var _normals: PackedVector3Array
var _uvs: PackedVector2Array
var _index: PackedInt32Array
var _ring_heights: PackedFloat32Array
var _winding := 1.0  # which way round the triangles go (sign of cross vs the outward normal)


func _init(mesh: ArrayMesh, band: Vector2) -> void:
	original = mesh
	_arrays = mesh.surface_get_arrays(0)
	_verts = _arrays[Mesh.ARRAY_VERTEX]
	_normals = _arrays[Mesh.ARRAY_NORMAL]
	_uvs = _arrays[Mesh.ARRAY_TEX_UV]
	_index = _arrays[Mesh.ARRAY_INDEX] if _arrays[Mesh.ARRAY_INDEX] else PackedInt32Array(range(_verts.size()))
	depth.resize(BINS)
	var heights := {}
	for v in _verts:
		if v.y >= band.x and v.y <= band.y:
			heights[snappedf(v.y, 0.001)] = true
	_ring_heights = PackedFloat32Array(heights.keys())
	_ring_heights.sort()
	for i in range(0, _index.size(), 3):
		var n := _face_normal(_verts[_index[i]], _verts[_index[i + 1]], _verts[_index[i + 2]])
		if n.length_squared() > 0.0:
			_winding = signf(n.dot(_normals[_index[i]]))
			break


func is_started() -> bool:
	return not is_nan(ring)


func reset() -> void:
	ring = NAN
	depth.fill(0.0)


## The trunk's radius at height `y`, toward `dir` (mesh space, horizontal).
func radius_at(y: float, dir: Vector3) -> float:
	var best := 0.0
	var best_dot := -INF
	for v in _verts:
		if absf(v.y - y) < 0.03:
			var flat := Vector2(v.x, v.z)
			var d := flat.normalized().dot(Vector2(dir.x, dir.z))
			if d > best_dot:
				best_dot = d
				best = flat.length()
	return best


## A hit from direction `dir` (mesh space, from the trunk toward the swinger) at height `y`. The
## first one picks the notch's ring (the nearest one in the band); it then gets `share` of the
## trunk's radius deeper straight in from there, less round the sides.
func hit(y: float, dir: Vector3, share: float) -> void:
	if not is_started():
		ring = _nearest_ring(y)
	var at := atan2(dir.z, dir.x)
	var radius := radius_at(ring, dir)
	var amount := radius * share
	var limit := radius * (1.0 - CORE)
	for b in BINS:
		var off := angle_difference(at, _bin_angle(b))
		var w := pow(maxf(cos(off), 0.0), SPREAD)
		depth[b] = minf(depth[b] + amount * w, limit)


func to_dict() -> Dictionary:
	return {"ring": snappedf(ring, 0.001), "depth": Array(depth).map(func(v: float) -> float: return snappedf(v, 0.001))}


func from_dict(d: Dictionary) -> void:
	reset()
	if not d.has("ring") or not d.has("depth"):
		return
	ring = _nearest_ring(float(d["ring"]))  # (snapped back onto a ring, in case the model changed)
	var saved: Array = d["depth"]
	for b in mini(saved.size(), BINS):
		depth[b] = float(saved[b])


## How deep the notch is toward `dir` (interpolated between bins).
func depth_toward(dir: Vector3) -> float:
	var f := fposmod(atan2(dir.z, dir.x), TAU) / TAU * BINS
	var b := int(f) % BINS
	return lerpf(depth[b], depth[(b + 1) % BINS], f - floorf(f))


## Where the notch's surface is toward `dir` at its ring (mesh space): where the axe bites.
func bite_point(dir: Vector3) -> Vector3:
	var flat := Vector3(dir.x, 0.0, dir.z).normalized()
	return Vector3(0.0, ring, 0.0) + flat * maxf(radius_at(ring, flat) - depth_toward(flat), 0.02)


## The trunk with the notch carved in.
func carved() -> ArrayMesh:
	var verts := _carved_verts()
	return _build(verts, _index)


## The carved trunk cut through at the notch's ring: {"stump": ArrayMesh, "log": ArrayMesh}, each
## with the cut face capped in end grain.
func split() -> Dictionary:
	var verts := _carved_verts()
	var below := PackedInt32Array()
	var above := PackedInt32Array()
	for i in range(0, _index.size(), 3):
		var top := maxf(verts[_index[i]].y, maxf(verts[_index[i + 1]].y, verts[_index[i + 2]].y))
		var tri := PackedInt32Array([_index[i], _index[i + 1], _index[i + 2]])
		if top <= ring + 0.001:  # (packed arrays are values: append to each by name)
			below.append_array(tri)
		else:
			above.append_array(tri)
	var cap := _cap_loop(verts)
	return {"stump": _build(verts, below, cap, Vector3.UP), "log": _build(verts, above, cap, Vector3.DOWN)}


# --- internals ------------------------------------------------------------------------------

func _bin_angle(b: int) -> float:
	return float(b) / BINS * TAU


func _nearest_ring(y: float) -> float:
	var best := y
	var gap := INF
	for h in _ring_heights:
		if absf(h - y) < gap:
			gap = absf(h - y)
			best = h
	return best


func _carved_verts() -> PackedVector3Array:
	var verts := _verts.duplicate()
	if not is_started():
		return verts
	for i in verts.size():
		var v := verts[i]
		var dy := v.y - ring
		var flat := Vector3(v.x, 0.0, v.z)
		var r := flat.length()
		if r < 0.001:
			continue
		var push := depth_toward(flat) - (dy * SLOPE_UP if dy > 0.0 else -dy * SLOPE_DOWN)
		if push <= 0.0:
			continue
		var scale := maxf(r - push, r * CORE) / r
		verts[i] = Vector3(v.x * scale, v.y, v.z * scale)
	return verts


## The ring's carved outline, round the trunk in order (one point per corner).
func _cap_loop(verts: PackedVector3Array) -> PackedVector3Array:
	var by_angle := {}
	for v in verts:
		if absf(v.y - ring) < 0.001:
			by_angle[snappedf(atan2(v.z, v.x), 0.01)] = v
	var angles := by_angle.keys()
	angles.sort()
	var loop := PackedVector3Array()
	for a in angles:
		loop.append(by_angle[a])
	return loop


## An ArrayMesh of `index`'s triangles over `verts`, notch faces flat-shaded in cut wood; with a
## `cap` loop, also the cut across it facing `cap_up`, in growth rings (GRAIN).
func _build(verts: PackedVector3Array, index: PackedInt32Array, cap := PackedVector3Array(),
		cap_up := Vector3.ZERO) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(0, index.size(), 3):
		var a := verts[index[i]]
		var b := verts[index[i + 1]]
		var c := verts[index[i + 2]]
		var n := _face_normal(a, b, c) * _winding
		# turned away from the face it was (not from the smoothed normal at a corner, which a
		# lumpy, ridged trunk's own faces stray from without being cut)
		var was := _face_normal(_verts[index[i]], _verts[index[i + 1]], _verts[index[i + 2]]) * _winding
		var cut := n.dot(was) < CUT_FACE
		for k in 3:
			# the bark keeps the model's smooth normals (flat ones would facet the whole trunk on
			# the first hit); only the notch's fresh faces are flat, so the cut reads crisp
			st.set_normal(n if cut else _normals[index[i + k]])
			st.set_uv(CUT_UV if cut else _uvs[index[i + k]])
			st.add_vertex(verts[index[i + k]])
	if cap.size() >= 3:
		var centre := Vector3.ZERO
		for p in cap:
			centre += p
		centre /= cap.size()
		st.set_normal(cap_up)
		for g in GRAIN.size():  # each ring: a band between its outline and the next one in
			var outer: float = GRAIN[g][0]
			var inner: float = GRAIN[g + 1][0] if g + 1 < GRAIN.size() else 0.0
			st.set_uv(GRAIN[g][1])
			for k in cap.size():
				var p := cap[k]
				var q := cap[(k + 1) % cap.size()]
				var a := centre.lerp(p, outer)
				var b := centre.lerp(q, outer)
				var c := centre.lerp(q, inner)
				var d := centre.lerp(p, inner)
				_up_tri(st, a, b, c, cap_up)
				if inner > 0.0:
					_up_tri(st, a, c, d, cap_up)
	return st.commit()


## A triangle wound to face `up`, whichever way round the points come.
func _up_tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, up: Vector3) -> void:
	if signf(_face_normal(a, b, c).dot(up)) * _winding < 0.0:
		var t := b
		b = c
		c = t
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)


static func _face_normal(a: Vector3, b: Vector3, c: Vector3) -> Vector3:
	return (b - a).cross(c - a).normalized()
