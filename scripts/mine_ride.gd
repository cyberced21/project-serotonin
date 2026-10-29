class_name MineRide
extends Node3D
## The minecart ride (plans/mine.md): a calm, rattling run down a long tunnel of its own, lanterns
## going by, about RIDE_TIME seconds. Built where nothing else is (far under the mine), ridden by
## its own camera from a seat in the cart, then freed. Up or down, it's the same tunnel: going up
## it's ridden the other way. Any key past the first second skips to the end.

signal finished

const LENGTH := 110.0
const DROP := 9.0
const WIDTH := 3.0
const HEIGHT := 3.4
const RIDE_TIME := 20.0
const LAMP_EVERY := 9.0
const RAIL_EVERY := 2.0
const CART := preload("res://models/mine/cart_tall.glb")
const RAIL := preload("res://models/mine/rail.glb")
const FRAME := preload("res://models/mine/frame_braced.glb")
const LAMP := preload("res://models/mine/lamp_hanging.glb")
const ROCK_MATERIAL := preload("res://materials/node_rock.tres")
const ROCK_UV := Vector2(0.4375, 0.0625)
const FLOOR_UV := Vector2(0.3125, 0.5625)
## Where it's built.
const ORIGIN := Vector3(-175, -130, -70)

var up := false
var done := false
var _cam: Camera3D
var _cart: Node3D
var _t := 0.0
var _noise := FastNoiseLite.new()
var _skippable := false
var rattle: AudioStreamPlayer


static func make(going_up: bool) -> MineRide:
	var r := MineRide.new()
	r.up = going_up
	r.position = ORIGIN
	return r


## The track: x along the tunnel, y falling.
static func track(s: float) -> Vector3:
	var f := clampf(s / LENGTH, 0.0, 1.0)
	return Vector3(s, -DROP * (f * f * (3.0 - 2.0 * f)), sin(f * PI * 2.0) * 3.0)


func _ready() -> void:
	_noise.seed = 77
	_noise.frequency = 0.6
	_build()
	_cart = Node3D.new()
	add_child(_cart)
	var model := CART.instantiate() as Node3D  # (its length is along its Z: the way it faces)
	_cart.add_child(model)
	_cam = Camera3D.new()
	_cam.position = Vector3(0, 1.45, 0)
	_cam.fov = 70.0
	_cart.add_child(_cam)
	_cam.make_current()
	_place(0.0)
	get_tree().create_timer(1.0).timeout.connect(func() -> void: _skippable = true)


func _process(delta: float) -> void:
	_t += delta
	var f := clampf(_t / RIDE_TIME, 0.0, 1.0)
	var eased := f * f * (3.0 - 2.0 * f)  # (eases off at the start and the end)
	_place(eased * LENGTH)
	if rattle:
		rattle.volume_db = lerpf(-30.0, -10.0, sin(f * PI))
	if f >= 1.0:
		_end()


func _unhandled_input(event: InputEvent) -> void:
	if _skippable and (event is InputEventKey or event is InputEventMouseButton) and event.is_pressed():
		_t = RIDE_TIME


func _place(s: float) -> void:
	var at := s if not up else LENGTH - s
	var p := track(at)
	var ahead := track(at + (1.0 if not up else -1.0))
	var bob := sin(_t * 9.0) * 0.015 + sin(_t * 23.0) * 0.006  # the rattle
	_cart.position = p + Vector3.UP * bob
	_cart.look_at(to_global(ahead) + Vector3.UP * bob, Vector3.UP)


func _end() -> void:
	set_process(false)
	done = true
	finished.emit()


func _build() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var steps := int(LENGTH / 1.0)
	for i in steps:
		var a := track(i)
		var b := track(i + 1.0)
		var along := (b - a).normalized()
		var side := along.cross(Vector3.UP).normalized()
		var w := WIDTH / 2
		var a0 := a - side * w
		var a1 := a + side * w
		var b0 := b - side * w
		var b1 := b + side * w
		var up3 := Vector3.UP * HEIGHT
		_quad(st, [a0, a1, b1, b0], FLOOR_UV, 0.8)  # floor (seen from above)
		_quad(st, [a1 + up3, a0 + up3, b0 + up3, b1 + up3], ROCK_UV, 0.55)  # roof
		_quad(st, [a0, b0, b0 + up3, a0 + up3], ROCK_UV, 0.85)  # one wall
		_quad(st, [b1, a1, a1 + up3, b1 + up3], ROCK_UV, 0.85)  # the other
	st.index()
	st.generate_normals()
	var mesh := MeshInstance3D.new()
	mesh.mesh = st.commit()
	mesh.material_override = ROCK_MATERIAL
	add_child(mesh)
	var s := 0.0
	while s < LENGTH:
		var p := track(s)
		var ahead := track(s + 0.5)
		_piece(RAIL, p + Vector3.UP * 0.02, ahead, true, PI / 2)
		s += RAIL_EVERY
	s = 4.0
	while s < LENGTH - 2.0:
		var p := track(s)
		_piece(FRAME, p, track(s + 0.5), false, 0.0)
		_piece(LAMP, p + Vector3.UP * (HEIGHT - 0.4), track(s + 0.5) + Vector3.UP * (HEIGHT - 0.4), false, 0.0)
		var light := OmniLight3D.new()
		light.light_color = Color(1.0, 0.72, 0.44)
		light.light_energy = 1.6
		light.omni_range = 8.0
		light.position = p + Vector3.UP * (HEIGHT - 1.0)
		add_child(light)
		s += LAMP_EVERY


## A quad of four corners (clockwise seen from inside the tunnel), gently wandered, with a shade.
func _quad(st: SurfaceTool, q: Array, uv: Vector2, shade: float) -> void:
	var p: Array = q.map(func(v: Vector3) -> Vector3: return v + Vector3(_noise.get_noise_3dv(v), _noise.get_noise_3dv(v + Vector3(9, 0, 0)), _noise.get_noise_3dv(v + Vector3(0, 0, 9))) * 0.12)
	for v: Vector3 in [p[0], p[2], p[1], p[0], p[3], p[2]]:
		var s := shade * (0.88 + 0.12 * _noise.get_noise_3dv(v * 2.0))
		st.set_uv(uv)
		st.set_color(Color(s, s, s, 1.0))
		st.add_vertex(v)


func _piece(model: PackedScene, at: Vector3, toward: Vector3, own: bool, turn: float) -> void:
	var p := Prop.new()
	p.model = model
	p.own_materials = own
	p.collide = false
	add_child(p)
	p.position = at
	var d := toward - at
	p.rotation.y = atan2(-d.x, -d.z) + turn
