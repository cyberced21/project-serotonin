class_name Footbridge
extends StaticBody3D
## The mended footbridge (plans/projects.md P10): a plank deck on two stringers between `from`
## and `to` (points on the ground at either end), a gentle arch, a rail each side on posts. Built
## in code so it fits whatever it spans: the creek where the village path crosses it.
## You walk on it (one box collider along the deck); standing on it you're out of the water
## (on_bridge(): player.gd's wading and Footsteps ask).

const WIDTH := 2.2
const ARCH := 0.35  # how much higher the middle is than the ends
const LIFT := 0.12  # the ends' deck over the ground
const PLANK := 0.24
const RAIL_HEIGHT := 0.95
const WOOD := Color(0.55, 0.38, 0.22)
const WOOD_DARK := Color(0.36, 0.24, 0.14)

var from := Vector3.ZERO
var to := Vector3.ZERO


func _ready() -> void:
	add_to_group("footbridge")
	var span := Vector2(to.x - from.x, to.z - from.z).length()
	var along := Vector3(to.x - from.x, 0.0, to.z - from.z).normalized()
	var across := along.cross(Vector3.UP).normalized()
	var light := _material(WOOD)
	var dark := _material(WOOD_DARK)
	var n := maxi(4, int(span / (PLANK + 0.03)))
	for i in n:  # planks across, each a hair different, following the arch
		var t := (i + 0.5) / n
		var p := deck_at(t)
		var plank := _box(Vector3(WIDTH * randf_range(0.96, 1.0), 0.06, PLANK), light)
		plank.transform = Transform3D(_basis(along, across, _slope(t)).rotated(Vector3.UP, randf_range(-0.03, 0.03)), p)
	for side: float in [-1.0, 1.0]:
		for i in 9:  # a stringer under each edge, in short straight bits along the curve
			var a := deck_at(i / 9.0)
			var b := deck_at((i + 1) / 9.0)
			var mid := (a + b) * 0.5 + across * side * (WIDTH * 0.5 - 0.08) + Vector3.DOWN * 0.1
			var beam := _box(Vector3(0.12, 0.14, a.distance_to(b) + 0.02), dark)
			beam.transform = Transform3D(_basis(along, across, (b.y - a.y) / maxf(Vector2(b.x - a.x, b.z - a.z).length(), 0.01)), mid)
		var posts := maxi(2, int(span / 2.0) + 1)
		for i in posts:
			var t := float(i) / (posts - 1)
			var base := deck_at(t) + across * side * (WIDTH * 0.5 - 0.05)
			var post := _box(Vector3(0.09, RAIL_HEIGHT, 0.09), dark)
			post.position = base + Vector3.UP * RAIL_HEIGHT * 0.5
		for i in 9:
			var a := deck_at(i / 9.0) + across * side * (WIDTH * 0.5 - 0.05) + Vector3.UP * RAIL_HEIGHT
			var b := deck_at((i + 1) / 9.0) + across * side * (WIDTH * 0.5 - 0.05) + Vector3.UP * RAIL_HEIGHT
			var rail := _box(Vector3(0.07, 0.07, a.distance_to(b) + 0.02), light)
			rail.transform = Transform3D(_basis(along, across, (b.y - a.y) / maxf(Vector2(b.x - a.x, b.z - a.z).length(), 0.01)), (a + b) * 0.5)
	# walk on it: a box per half (up the arch and down), and rails you can't fall through
	for half: float in [0.25, 0.75]:
		var c := deck_at(half)
		var a := deck_at(half - 0.25)
		var b := deck_at(half + 0.25)
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(WIDTH, 0.2, a.distance_to(b) + 0.3)
		shape.shape = box
		shape.transform = Transform3D(_basis(along, across, (b.y - a.y) / maxf(Vector2(b.x - a.x, b.z - a.z).length(), 0.01)), c + Vector3.DOWN * 0.08)
		add_child(shape)
	for side: float in [-1.0, 1.0]:
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(0.1, RAIL_HEIGHT, span)
		shape.shape = box
		shape.transform = Transform3D(_basis(along, across, 0.0), deck_at(0.5) + across * side * (WIDTH * 0.5) + Vector3.UP * RAIL_HEIGHT * 0.5)
		add_child(shape)


## The deck's middle a share `t` of the way across: the ends' heights, arched.
func deck_at(t: float) -> Vector3:
	var p := from.lerp(to, t)
	p.y += LIFT + ARCH * 4.0 * t * (1.0 - t)
	return p


## True if `pos` is on (or just over) a footbridge's deck: out of the water.
static func on_bridge(tree: SceneTree, pos: Vector3) -> bool:
	for n in tree.get_nodes_in_group("footbridge"):
		var b := n as Footbridge
		var flat := Vector2(b.to.x - b.from.x, b.to.z - b.from.z)
		var rel := Vector2(pos.x - b.from.x, pos.z - b.from.z)
		var t := rel.dot(flat) / maxf(flat.length_squared(), 0.01)
		if t < -0.05 or t > 1.05:
			continue
		var side := absf(rel.cross(flat.normalized()))
		var deck := b.deck_at(clampf(t, 0.0, 1.0)).y
		if side < WIDTH * 0.5 + 0.2 and pos.y > deck - 0.4 and pos.y < deck + 1.0:
			return true
	return false


func _slope(t: float) -> float:
	var flat := Vector2(to.x - from.x, to.z - from.z).length()
	return (to.y - from.y) / maxf(flat, 0.01) + ARCH * 4.0 * (1.0 - 2.0 * t) / maxf(flat, 0.01)


## A basis with +Z along the bridge, tilted up by `slope` (rise over run), Y up off the deck.
static func _basis(along: Vector3, across: Vector3, slope: float) -> Basis:
	var z := (along + Vector3.UP * slope).normalized()
	var y := z.cross(across).normalized() * -1.0
	if y.y < 0.0:
		y = -y
	var x := y.cross(z).normalized()
	return Basis(x, y, z)


func _box(size: Vector3, mat: Material) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	m.mesh = mesh
	m.material_override = mat
	add_child(m)
	return m


static var _mats: Dictionary = {}


static func _material(c: Color) -> StandardMaterial3D:
	if not _mats.has(c):
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.roughness = 0.9
		_mats[c] = m
	return _mats[c]
