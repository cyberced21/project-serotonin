class_name Die
extends RigidBody3D
## One of the tavern's dice (plans/tavern.md): a little bone-coloured cube with dark pips, thrown
## and tumbling for real in the dice tray (DiceGame). Faces: +Y 1, -Y 6, +X 2, -X 5, +Z 3, -Z 4
## (opposites add up to 7).

const SIZE := 0.07
## Its own physics layer: dice knock into each other and the tray, and nothing else notices them.
const LAYER := 1 << 9
const FACES := {Vector3.UP: 1, Vector3.DOWN: 6, Vector3.RIGHT: 2, Vector3.LEFT: 5, Vector3.BACK: 3, Vector3.FORWARD: 4}
## Where the pips go on a face, in a 3x3 grid (-1..1 on the face's two axes).
const PIPS := {
	1: [Vector2(0, 0)],
	2: [Vector2(-1, -1), Vector2(1, 1)],
	3: [Vector2(-1, -1), Vector2(0, 0), Vector2(1, 1)],
	4: [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)],
	5: [Vector2(-1, -1), Vector2(1, -1), Vector2(0, 0), Vector2(-1, 1), Vector2(1, 1)],
	6: [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 0), Vector2(1, 0), Vector2(-1, 1), Vector2(1, 1)],
}
const BODY_COLOR := Color("eadfc4")
const PIP_COLOR := Color("2a1d14")
## Settled: this still for this long.
const STILL_SPEED := 0.03
const STILL_SPIN := 0.2
const STILL_TIME := 0.25

static var _box_mesh: BoxMesh
static var _pip_mesh: CylinderMesh

var _still := 0.0


func _ready() -> void:
	collision_layer = LAYER
	collision_mask = LAYER
	mass = 0.02
	continuous_cd = true
	var mat := PhysicsMaterial.new()
	mat.bounce = 0.25
	mat.friction = 0.7
	physics_material_override = mat
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3.ONE * SIZE
	shape.shape = box
	add_child(shape)
	var body := MeshInstance3D.new()
	body.mesh = _body_mesh()
	add_child(body)
	for normal: Vector3 in FACES:
		_add_pips(normal, FACES[normal])


## The face showing on top, or 0 when it's cocked against something (no face near enough up).
func face_up() -> int:
	var best := 0.0
	var face := 0
	for normal: Vector3 in FACES:
		var d := (global_basis * normal).normalized().dot(Vector3.UP)
		if d > best:
			best = d
			face = FACES[normal]
	return face if best > 0.9 else 0


## The rotation that shows `face` on top (turned `yaw` about the vertical).
static func basis_showing(face: int, yaw := 0.0) -> Basis:
	for normal: Vector3 in FACES:
		if FACES[normal] == face:
			var b := Basis(Quaternion(normal, Vector3.UP))
			return Basis(Vector3.UP, yaw) * b
	return Basis.IDENTITY


## Come to rest (or near enough, for long enough).
func settled() -> bool:
	return freeze or sleeping or _still >= STILL_TIME


func _physics_process(delta: float) -> void:
	if linear_velocity.length() < STILL_SPEED and angular_velocity.length() < STILL_SPIN:
		_still += delta
	else:
		_still = 0.0


## Thrown: from where it is, with this velocity and spin.
func throw(velocity: Vector3, spin: Vector3) -> void:
	freeze = false
	sleeping = false
	_still = 0.0
	linear_velocity = velocity
	angular_velocity = spin


## A nudge for a die resting cocked against the tray's wall or another die.
func nudge() -> void:
	sleeping = false
	_still = 0.0
	apply_central_impulse(Vector3.UP * mass * 0.9 + Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)) * mass * 0.3)
	angular_velocity = Vector3(randf_range(-8, 8), randf_range(-8, 8), randf_range(-8, 8))


static func _body_mesh() -> BoxMesh:
	if _box_mesh == null:
		_box_mesh = BoxMesh.new()
		_box_mesh.size = Vector3.ONE * SIZE
		var mat := StandardMaterial3D.new()
		mat.albedo_color = BODY_COLOR
		mat.roughness = 0.55
		_box_mesh.material = mat
	return _box_mesh


func _add_pips(normal: Vector3, value: int) -> void:
	if _pip_mesh == null:
		_pip_mesh = CylinderMesh.new()
		_pip_mesh.top_radius = SIZE * 0.085
		_pip_mesh.bottom_radius = SIZE * 0.085
		_pip_mesh.height = SIZE * 0.04
		_pip_mesh.radial_segments = 8
		_pip_mesh.rings = 1
		var mat := StandardMaterial3D.new()
		mat.albedo_color = PIP_COLOR
		mat.roughness = 0.8
		_pip_mesh.material = mat
	# the face's two axes
	var u := Vector3.RIGHT if absf(normal.x) < 0.5 else Vector3.BACK
	var v := normal.cross(u)
	var up_to_normal := Basis(Quaternion(Vector3.UP, normal))
	for p: Vector2 in PIPS[value]:
		var pip := MeshInstance3D.new()
		pip.mesh = _pip_mesh
		pip.basis = up_to_normal
		pip.position = normal * SIZE * 0.5 + (u * p.x + v * p.y) * SIZE * 0.26
		add_child(pip)
