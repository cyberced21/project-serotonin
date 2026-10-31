class_name Crumble
extends RefCounted
## Rock coming away without physics (plans/crumbs.md). Thrown physics pieces were born overlapping
## the terrain or the rock round them and got shoved through the world, so nothing here is
## simulated: a bit pops out of its dent and falls on a worked-out arc to the ground below it
## (found by one ray, so it never goes through), shrinking, and breaks into dust there. A big
## piece sags out of place for a beat and collapses into a cloud where it stood.

const GRAVITY := 9.8
## How fast a bit hops out of its dent before it falls (m/s, up), and how far out it lands, per
## metre it falls (m).
const HOP := 0.6
const DRIFT := 0.35
## A piece this big (m, longest side) or bigger slumps rather than falling as a bit.
const SLUMP_SIZE := 0.45
const WORLD := 1


## A bit of rock: `mesh` (not yet in the tree) at `xform` (world) pops out along `push`, falls to
## the ground below and puffs into dust (`fx`, a HitFx scene, at `puff` strength: 0, no puff).
## `exclude`: bodies the ground ray passes through (the rock it came out of).
static func bit(parent: Node, mesh: MeshInstance3D, xform: Transform3D, push: Vector3, fx: PackedScene,
		stone: Color, ore := Color(0, 0, 0, 0), puff := 0.6, exclude: Array[RID] = [], glitter := false) -> void:
	var size := _size(mesh, xform)
	if size >= SLUMP_SIZE:
		slump(parent, mesh, xform, push, fx, stone, ore, exclude, glitter)
		return
	var pivot := _pivot(parent, mesh, xform)
	var start := pivot.global_position
	var out := Vector3(push.x, 0.0, push.z)
	out = out.normalized() if out.length_squared() > 0.0001 else Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized()
	var ground := _ground(parent, start + out * 0.25, exclude, start.y - 3.0)
	var land_y := minf(ground + size * 0.2, start.y)
	var drop := start.y - land_y
	var t_land := (HOP + sqrt(HOP * HOP + 2.0 * GRAVITY * drop)) / GRAVITY
	var land := Vector3(start.x, land_y, start.z) + out * (0.1 + DRIFT * minf(drop, 2.0)) * randf_range(0.7, 1.2)
	land.y = minf(_ground(parent, land, exclude, land_y) + size * 0.2, start.y)
	var spin := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).normalized()
	var spin_rate := randf_range(6.0, 12.0)
	var t := pivot.create_tween()
	t.tween_method(func(s: float) -> void:
		var time := s * t_land
		var p := start.lerp(land, s)
		p.y = maxf(start.y + HOP * time - 0.5 * GRAVITY * time * time, land.y)
		pivot.global_position = p
		pivot.basis = Basis(spin, spin_rate * time).scaled(Vector3.ONE * lerpf(1.0, 0.45, s * s)),
		0.0, 1.0, t_land)
	t.tween_callback(func() -> void:
		if puff > 0.0 and fx:
			HitFx.spawn(fx, parent, land, Vector3.UP, out, stone, ore, puff)
		if glitter:
			HitFx.star(parent, land + Vector3.UP * 0.05, ore if ore.a > 0.0 else stone, 0.25)
		pivot.queue_free())


## A big piece (or a cluster drawn as one mesh): it sags out along `push` and tips for a beat,
## then collapses where it stood into a cloud of dust, sinking a little as it goes.
static func slump(parent: Node, mesh: MeshInstance3D, xform: Transform3D, push: Vector3, fx: PackedScene,
		stone: Color, ore := Color(0, 0, 0, 0), exclude: Array[RID] = [], glitter := false, sag := 0.2) -> void:
	var pivot := _pivot(parent, mesh, xform)
	var size := _size(mesh, xform)
	var start := pivot.global_position
	var out := Vector3(push.x, 0.0, push.z)
	out = out.normalized() if out.length_squared() > 0.0001 else Vector3.FORWARD
	var ground := _ground(parent, start, exclude, start.y - 3.0)
	var sink := minf(size * 0.35, maxf(start.y - ground, 0.0))
	var axis := out.cross(Vector3.UP).normalized()
	var t := pivot.create_tween()
	t.tween_method(func(s: float) -> void:
		pivot.global_position = start + out * 0.06 * s + Vector3.DOWN * 0.03 * s
		pivot.basis = Basis(axis, -0.12 * s),
		0.0, 1.0, sag).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_callback(func() -> void:
		if fx:
			var puffs := clampi(roundi(size * 4.0), 1, 6)
			for i in puffs:
				var at := start + Vector3(randf_range(-0.5, 0.5), randf_range(-0.4, 0.3), randf_range(-0.5, 0.5)) * size
				HitFx.spawn(fx, parent, at, Vector3.UP, out, stone, ore, clampf(size * 2.5, 1.0, 2.5))
		if glitter:
			HitFx.star(parent, start, ore if ore.a > 0.0 else stone, 0.5))
	var from := start + out * 0.06 + Vector3.DOWN * 0.03
	t.tween_method(func(s: float) -> void:
		pivot.global_position = from + Vector3.DOWN * sink * s
		pivot.basis = Basis(axis, -0.12 - 0.15 * s).scaled(Vector3(1.0, 1.0, 1.0) * lerpf(1.0, 0.12, s)),
		0.0, 1.0, 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	t.tween_callback(pivot.queue_free)


## `mesh` hung under a pivot at its middle (so it turns and shrinks about that), placed at `xform`.
static func _pivot(parent: Node, mesh: MeshInstance3D, xform: Transform3D) -> Node3D:
	var pivot := Node3D.new()
	pivot.name = "Crumble"
	parent.add_child(pivot)
	var centre := xform * mesh.get_aabb().get_center()
	pivot.global_transform = Transform3D(Basis.IDENTITY, centre)
	mesh.visible = true
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh.set_instance_shader_parameter("flash", 0.0)
	mesh.set_instance_shader_parameter("highlight", 0.0)
	pivot.add_child(mesh)
	mesh.transform = Transform3D(xform.basis, xform.origin - centre)
	return pivot


static func _size(mesh: MeshInstance3D, xform: Transform3D) -> float:
	return mesh.get_aabb().get_longest_axis_size() * xform.basis.get_scale().x


## The ground's height under `at` (world), through `exclude`; `fallback` when there's none.
static func _ground(parent: Node, at: Vector3, exclude: Array[RID], fallback: float) -> float:
	var world := (parent as Node3D).get_world_3d() if parent is Node3D else null
	if world == null:
		return fallback
	var q := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 0.3, at + Vector3.DOWN * 4.0, WORLD, exclude)
	var hit := world.direct_space_state.intersect_ray(q)
	return (hit["position"] as Vector3).y if hit else fallback


## Gravel at the foot of what's being dug: a few specks per bit that settle and, after LIFE
## seconds, shrink away. One MultiMesh a node (one draw call), the oldest specks reused first.
class Gravel extends MultiMeshInstance3D:
	const COUNT := 48
	const LIFE := 20.0
	const FADE := 1.5
	var _born := PackedFloat32Array()
	var _rest: Array[Transform3D] = []
	var _next := 0
	var _check := 0.0

	func _init() -> void:
		name = "Gravel"
		cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var pebble := SphereMesh.new()  # 6 x 3 = a low-poly lump
		pebble.radius = 0.045
		pebble.height = 0.06
		pebble.radial_segments = 6
		pebble.rings = 3
		var mat := StandardMaterial3D.new()
		mat.vertex_color_use_as_albedo = true
		mat.roughness = 1.0
		pebble.material = mat
		multimesh = MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.use_colors = true
		multimesh.mesh = pebble
		multimesh.instance_count = COUNT
		_born.resize(COUNT)
		_born.fill(-1.0)
		_rest.resize(COUNT)
		for i in COUNT:
			multimesh.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ZERO), Vector3.ZERO))
		set_process(false)

	## `count` specks round `at` (world), on the ground under it.
	func add(at: Vector3, count: int, color: Color, exclude: Array[RID] = []) -> void:
		var now := Time.get_ticks_msec() / 1000.0
		for k in count:
			var p := at + Vector3(randf_range(-0.25, 0.25), 0.0, randf_range(-0.25, 0.25))
			p.y = Crumble._ground(self, p, exclude, at.y)
			var s := randf_range(0.5, 1.4)
			var xf := Transform3D(Basis.from_euler(Vector3(randf(), randf(), randf()) * TAU).scaled(Vector3(s, s * 0.6, s)),
				to_local(p + Vector3.UP * 0.015 * s))
			_rest[_next] = xf
			_born[_next] = now
			multimesh.set_instance_transform(_next, xf)
			multimesh.set_instance_color(_next, color.darkened(randf_range(0.0, 0.3)))
			_next = (_next + 1) % COUNT
		set_process(true)

	func _process(delta: float) -> void:
		_check -= delta
		if _check > 0.0:
			return
		_check = 0.1
		var now := Time.get_ticks_msec() / 1000.0
		var alive := false
		for i in COUNT:
			if _born[i] < 0.0:
				continue
			var age := now - _born[i]
			if age < LIFE:
				alive = true
				continue
			var f := clampf(1.0 - (age - LIFE) / FADE, 0.0, 1.0)
			var xf := _rest[i]
			multimesh.set_instance_transform(i, Transform3D(xf.basis * Basis.from_scale(Vector3.ONE * f), xf.origin + Vector3.DOWN * 0.02 * (1.0 - f)))
			if f <= 0.0:
				_born[i] = -1.0
			else:
				alive = true
		set_process(alive)
