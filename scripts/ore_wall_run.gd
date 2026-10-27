class_name OreWallRun
extends Node3D
## A run of ore wall (plans/ore-walls.md): OreWall panels side by side along a quarry wall, with the
## rock that never breaks round them. Between every two panels stands a pillar (room and pillar:
## each panel digs back into its own alcove), a cap rock lies over the lot (the terrace above
## stays walkable over the alcoves; underneath, it's their ceiling), and once a panel's dug right
## back there's bedrock. The run's two ends get a pillar too.
## Give it `panels` (each panel's transform, in the run's space, in order along the wall) and
## build() it; it makes the panels and the rock. The rock is built here rather than baked, since
## a pillar has to fill whatever wedge two panels on a curve leave between them.

const PANEL_SCENE := preload("res://scenes/ore_wall.tscn")
const ROCK_MATERIAL := preload("res://materials/node_rock.tres")
## The pillars at the ends of a run (m across).
const END_PILLAR := 1.0
## The cap rock: how thick (m, over the panels' tops), how far it reaches back past the panels'
## backs (over the quarry wall's own slope), and how far it juts out over the face.
const CAP := 1.0
const CAP_BACK := 1.4
const CAP_LIP := 0.2
## How far the pillars and cap overlap the panels (so their rough faces never open a gap).
const OVERLAP := 0.12
## The rock's roughness: how far its surface wanders (m), and how finely it's gridded to wander.
const ROUGH := 0.11
const GRID := 0.35
## Palette swatches (art/palette.json): the pillars and cap, and the darker bedrock.
const STONE_UV := Vector2(0.5625, 0.0625)
const BEDROCK_UV := Vector2(0.3125, 0.0625)
## Which faces of a block are drawn (see _block): the rest are against the ground, the panels or
## the quarry wall.
const FRONT := 1
const PILLAR_FACES := 0b001101  # front, left, right
const CAP_FACES := 0b111101  # all but the back

## Each panel's transform in this node's space, in order along the wall.
var panels: Array[Transform3D] = []
## Per panel: its template, vein seed and save id (same length as panels).
var templates: PackedInt32Array = PackedInt32Array()
var seeds: PackedInt32Array = PackedInt32Array()
var save_ids: PackedStringArray = PackedStringArray()
## The quarry ring the run is on, of how many (richer further down).
var ring := 0
var rings := 1
## How tall the wall is (m, the panels plus the cap: one level of the quarry).
var height := OreWall.HEIGHT + CAP

var _noise := FastNoiseLite.new()


func build() -> void:
	_noise.seed = hash(save_ids[0] if not save_ids.is_empty() else name)
	_noise.frequency = 0.9
	for i in panels.size():
		var p := PANEL_SCENE.instantiate() as OreWall
		p.name = "Panel%d" % i
		p.template = templates[i] if i < templates.size() else i % OreWall.TEMPLATES
		p.vein_seed = seeds[i] if i < seeds.size() else i
		p.save_id = StringName(save_ids[i]) if i < save_ids.size() else &""
		p.ring = ring
		p.rings = rings
		p.transform = panels[i]
		add_child(p)
	_build_rock()


## The corners of panel i's side (+1 right, -1 left), front and back, at its foot (run space).
func _side(i: int, side: int) -> Array[Vector3]:
	var x := side * OreWall.WIDTH * 0.5
	var t := panels[i]
	return [t * Vector3(x, 0, 0), t * Vector3(x, 0, -OreWall.DEPTH)]


func _build_rock() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var body := StaticBody3D.new()
	body.name = "Rock"
	var top := height
	var cap_under := OreWall.HEIGHT
	for i in panels.size():
		var t := panels[i]
		var right := t.basis.x.normalized()
		var out := t.basis.z.normalized()
		# the pillar on its left (an end pillar for the first), and the last one's right
		var l := _side(i, -1)
		var lf: Vector3 = l[0] + right * OVERLAP
		var lb: Vector3 = l[1] + right * OVERLAP
		var pf: Vector3
		var pb: Vector3
		if i == 0:
			pf = lf - right * (END_PILLAR + OVERLAP)
			pb = lb - right * (END_PILLAR + OVERLAP)
		else:
			var r := _side(i - 1, 1)
			pf = r[0] - panels[i - 1].basis.x.normalized() * OVERLAP
			pb = r[1] - panels[i - 1].basis.x.normalized() * OVERLAP
		_block(st, body, [pf, lf, lb, pb], 0.0, cap_under + 0.05, STONE_UV, PILLAR_FACES)
		if i == panels.size() - 1:
			var r := _side(i, 1)
			var rf: Vector3 = r[0] - right * OVERLAP
			var rb: Vector3 = r[1] - right * OVERLAP
			_block(st, body, [rf, rf + right * (END_PILLAR + OVERLAP), rb + right * (END_PILLAR + OVERLAP), rb],
				0.0, cap_under + 0.05, STONE_UV, PILLAR_FACES)
		# the cap over the panel and the pillar on its left (and the right end pillar)
		var end := right * END_PILLAR if i == panels.size() - 1 else Vector3.ZERO
		var c1: Vector3 = _side(i, 1)[0] + end
		var cb0 := pb + (pb - pf).normalized() * CAP_BACK
		var cb1: Vector3 = _side(i, 1)[1] + end - out * CAP_BACK
		var lip := out * CAP_LIP
		_block(st, body, [pf + lip, c1 + lip, cb1, cb0], cap_under, top, STONE_UV, CAP_FACES)
		# bedrock: a slab behind the panel, its face where the panel's back was
		var bf0 := t * Vector3(-OreWall.WIDTH * 0.5 - OVERLAP, 0, -OreWall.DEPTH)
		var bf1 := t * Vector3(OreWall.WIDTH * 0.5 + OVERLAP, 0, -OreWall.DEPTH)
		_block(st, body, [bf0, bf1, bf1 - out * 0.6, bf0 - out * 0.6], 0.0, cap_under + 0.05, BEDROCK_UV, FRONT)
	st.index()
	st.generate_normals()
	var mesh := MeshInstance3D.new()
	mesh.name = "RockMesh"
	mesh.mesh = st.commit()
	mesh.material_override = ROCK_MATERIAL
	mesh.visibility_range_end = 160.0
	mesh.visibility_range_end_margin = 12.0
	mesh.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	add_child(mesh)
	add_child(body)


## One block of rock: the quad `base` (front-left, front-right, back-right, back-left, at y = 0
## of the run, each lifted by its own `y0`..`y1`), its faces gridded and wandered by a smooth field
## (the same field for every block, so where blocks meet they wander alike). `faces` says which
## faces to draw (bits: front, back, left, right, top, bottom); hidden ones are skipped. Also a
## hull for it in `body`.
func _block(st: SurfaceTool, body: StaticBody3D, base: Array, y0: float, y1: float, uv: Vector2, faces: int) -> void:
	var c := []  # 0..3 bottom, 4..7 top
	for p: Vector3 in base:
		c.append(Vector3(p.x, p.y + y0, p.z))
	for p: Vector3 in base:
		c.append(Vector3(p.x, p.y + y1, p.z))
	var quads := [[c[0], c[1], c[5], c[4]], [c[2], c[3], c[7], c[6]], [c[3], c[0], c[4], c[7]],
		[c[1], c[2], c[6], c[5]], [c[4], c[5], c[6], c[7]], [c[3], c[2], c[1], c[0]]]
	for f in 6:
		if faces & (1 << f):
			_face(st, quads[f], uv, f)
	var hull := CollisionShape3D.new()
	var shape := ConvexPolygonShape3D.new()
	shape.points = PackedVector3Array(c)
	hull.shape = shape
	body.add_child(hull)


## A quad (corners anticlockwise seen from outside) as a grid of wandered triangles.
func _face(st: SurfaceTool, q: Array, uv: Vector2, which: int) -> void:
	var a: Vector3 = q[0]
	var b: Vector3 = q[1]
	var d: Vector3 = q[3]
	var nu := maxi(ceili(a.distance_to(b) / GRID), 1)
	var nv := maxi(ceili(a.distance_to(d) / GRID), 1)
	var grid := []
	for j in nv + 1:
		var row := []
		for i in nu + 1:
			var s := float(i) / nu
			var t := float(j) / nv
			var p: Vector3 = (q[0] as Vector3).lerp(q[1], s).lerp((q[3] as Vector3).lerp(q[2], s), t)
			row.append(_wander(p))
		grid.append(row)
	st.set_smooth_group(which)
	for j in nv:
		for i in nu:
			var p00: Vector3 = grid[j][i]
			var p10: Vector3 = grid[j][i + 1]
			var p11: Vector3 = grid[j + 1][i + 1]
			var p01: Vector3 = grid[j + 1][i]
			for p in [p00, p11, p10, p00, p01, p11]:  # (clockwise seen from outside: Godot's front)
				st.set_uv(uv)
				st.set_color(_shade(p, which))
				st.add_vertex(p)


func _wander(p: Vector3) -> Vector3:
	return p + Vector3(_noise.get_noise_3dv(p), _noise.get_noise_3dv(p + Vector3(31, 0, 0)),
		_noise.get_noise_3dv(p + Vector3(0, 0, 57))) * ROUGH


## The baked shade the rock shader multiplies in (alpha 1: weathered skin): undersides (the
## alcoves' ceilings) and the foot darker, a little mottling.
func _shade(p: Vector3, which: int) -> Color:
	var s := 0.85 + 0.12 * _noise.get_noise_3dv(p * 2.3)
	if which == 5:
		s *= 0.62
	s *= lerpf(0.75, 1.0, clampf(p.y / 1.2, 0.0, 1.0))
	return Color(s, s, s, 1.0)
