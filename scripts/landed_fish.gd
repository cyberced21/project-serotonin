class_name LandedFish
extends Node3D
## A fish the rod yanked out of the water (RodFishing): it sails over in a high, tumbling arc
## trailing drips, slaps down on the bank beside you, flops about, then lies there glinting until
## you walk up to it, which puts it in the inventory (`count` of it: a Big one counts 2, a Huge 3).
## Left lying, it comes to you like any drop.

enum Phase { FLY, FLOP, REST, PULL }

const SHADER := preload("res://shaders/fish.gdshader")
const PALETTE := preload("res://art/palette.png")
const FLOP := preload("res://audio/fishing/flop.tres")
const WORLD_MASK := 1
const GRAVITY := 16.0
## The flops after it lands: each hop's height (m).
const HOPS: Array[float] = [0.42, 0.26, 0.15, 0.07]

## Fired as it first hits the ground (RodFishing puts up the popups there).
signal landed(at: Vector3)

@export var flight_time := 0.75
## Walk within this (m) to pick it up (once it has hit the ground).
@export var pickup_radius := 2.0
## Left lying this long, it flies to you wherever you are.
@export var auto_pull_time := 7.0
@export var collect_height := 1.0

var item: StringName
var count := 1
var phase := Phase.FLY

var _surfaces: Array[GeometryInstance3D] = []
var _half_height := 0.04
var _from := Vector3.ZERO
var _to := Vector3.ZERO
var _arc := 2.0
var _t := 0.0
var _age_down := 0.0
var _hop := 0
var _hop_from := Vector3.ZERO
var _hop_to := Vector3.ZERO
var _hop_time := 0.3
var _yaw := 0.0
var _side := 1.0   # which flank it's lying on (+1 / -1)
var _roll_from := 0.0
var _twitch_in := 1.5
var _glint_in := 0.6
var _vel := Vector3.ZERO
var _drips: CPUParticles3D
var _rng := RandomNumberGenerator.new()


## Starts it flying from `from` (where the fish was in the water) to the ground at `to`.
static func spawn(parent: Node, fish: Fish, from: Transform3D, to: Vector3, p_count: int) -> LandedFish:
	var f := LandedFish.new()
	f.name = "LandedFish"
	f.item = fish.species.id
	f.count = p_count
	parent.add_child(f)
	f._build(fish.species, fish.length, FishSize.scale_for(fish.size))
	f._from = from.origin
	f._to = to
	f._arc = 1.8 + RodFishing._flat(from.origin, to) * 0.14
	f.global_transform = from
	f.reset_physics_interpolation()
	return f


func _build(species: FishSpecies, body_length: float, model_scale: float) -> void:
	_rng.randomize()
	var model := species.model.instantiate() as Node3D
	add_child(model)
	model.scale = Vector3.ONE * model_scale
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	mat.set_shader_parameter("palette", PALETTE)
	var aabb := AABB()
	for m in model.find_children("*", "MeshInstance3D", true, false):
		var mesh := m as MeshInstance3D
		mesh.material_override = mat
		mesh.set_instance_shader_parameter("body_length", body_length)
		mesh.set_instance_shader_parameter("swim", 1.0)
		mesh.set_instance_shader_parameter("phase", _rng.randf() * TAU)
		_surfaces.append(mesh)
		aabb = mesh.get_aabb() if aabb.size == Vector3.ZERO else aabb.merge(mesh.get_aabb())
	_half_height = maxf(aabb.size.x * model_scale, 0.03) * 0.5  # lying on its flank, its width is its height
	_yaw = _rng.randf() * TAU
	_side = 1.0 if _rng.randf() < 0.5 else -1.0
	# drips shaken off on the way over
	_drips = CPUParticles3D.new()
	_drips.amount = 18
	_drips.lifetime = 0.5
	_drips.local_coords = false
	_drips.direction = Vector3.DOWN
	_drips.spread = 60.0
	_drips.initial_velocity_min = 0.3
	_drips.initial_velocity_max = 1.2
	_drips.mesh = RodFishing.droplet_mesh()
	_drips.scale_amount_min = 0.5
	_drips.scale_amount_max = 1.0
	add_child(_drips)


func _physics_process(delta: float) -> void:
	match phase:
		Phase.FLY:
			_fly(delta)
		Phase.FLOP:
			_flop(delta)
			_try_pickup(delta)
		Phase.REST:
			_rest(delta)
			_try_pickup(delta)
		Phase.PULL:
			_pull(delta)


func _fly(delta: float) -> void:
	_t += delta
	var k := clampf(_t / flight_time, 0.0, 1.0)
	var p := _from.lerp(_to, k) + Vector3.UP * _arc * 4.0 * k * (1.0 - k)
	var ahead := _from.lerp(_to, minf(k + 0.05, 1.0)) + Vector3.UP * _arc * 4.0 * minf(k + 0.05, 1.0) * (1.0 - minf(k + 0.05, 1.0))
	global_position = p
	var flat := Vector3(_to.x - _from.x, 0.0, _to.z - _from.z)
	if flat.length_squared() > 0.0001:
		# nose along the arc, spinning end over end and rolling as it goes
		var b := Basis.looking_at((ahead - p).normalized() if ahead.distance_squared_to(p) > 1e-6 else flat.normalized(), Vector3.UP)
		b = b.rotated(b.x, -k * TAU * 1.25)
		b = b.rotated(b.z, k * PI * 1.5 * _side)
		global_basis = b
	if k >= 1.0:
		_touch_down(true)


## Hits the ground (the first slap is the big one), then hops on to the next flop.
func _touch_down(first: bool) -> void:
	var at := _ground(global_position)
	global_position = at
	_play_flop(1.0 if first else 0.7 - 0.12 * _hop, at)
	if first:
		_drips.emitting = false
		RodFishing.splash(get_parent(), at + Vector3.UP * 0.05, 0.6)
		landed.emit(at)
	if _hop >= HOPS.size():
		phase = Phase.REST
		_set_swim(0.15)
		_lie(at)
		return
	phase = Phase.FLOP
	var h := HOPS[_hop]
	_hop += 1
	_hop_time = 2.0 * sqrt(2.0 * h / GRAVITY)
	_hop_from = at
	var jitter := Vector3(_rng.randf_range(-1, 1), 0.0, _rng.randf_range(-1, 1)).limit_length(1.0) * h * 0.5
	_hop_to = _ground(at + jitter)
	_yaw += _rng.randf_range(-1.4, 1.4)
	_roll_from = _side * PI * 0.5 if not first else 0.0
	_side = -_side  # it flips over each time
	_t = 0.0
	_set_swim(1.0)


func _flop(delta: float) -> void:
	_t += delta
	_age_down += delta
	var k := clampf(_t / _hop_time, 0.0, 1.0)
	var h := HOPS[_hop - 1]
	var p := _hop_from.lerp(_hop_to, k) + Vector3.UP * (h * 4.0 * k * (1.0 - k) + _half_height)
	global_position = p
	# arching its back on the way up, flipping onto the other flank
	var b := Basis(Vector3.UP, _yaw)
	b = b.rotated(b.z, lerpf(_roll_from, _side * PI * 0.5, ease(k, -1.8)))
	b = b.rotated(b.x, sin(k * PI) * 0.6)
	global_basis = b
	if k >= 1.0:
		_touch_down(false)


func _lie(at: Vector3) -> void:
	global_position = at + Vector3.UP * _half_height
	var b := Basis(Vector3.UP, _yaw)
	global_basis = b.rotated(b.z, _side * PI * 0.5)


## Lying there: now and then a feeble twitch, and a glint so you notice it.
func _rest(delta: float) -> void:
	_age_down += delta
	_twitch_in -= delta
	_glint_in -= delta
	if _twitch_in <= 0.0:
		_twitch_in = _rng.randf_range(1.2, 2.4)
		_set_swim(0.9)
		var t := create_tween()
		t.tween_interval(0.25)
		t.tween_callback(_set_swim.bind(0.15))
		_play_flop(0.35, global_position)
	if _glint_in <= 0.0:
		_glint_in = 1.6
		var t := create_tween()
		t.tween_method(_set_flash, 0.7, 0.0, 0.35)
	if _age_down > auto_pull_time:
		_start_pull()


func _try_pickup(_delta: float) -> void:
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player and _flat_to(player) < pickup_radius and absf(player.global_position.y - global_position.y) < 2.0:
		_start_pull()


func _start_pull() -> void:
	phase = Phase.PULL
	_vel = Vector3.UP * 3.0  # a little hop up into your hands
	_set_swim(1.0)


func _pull(delta: float) -> void:
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player == null:
		return
	var target := player.global_position + Vector3.UP * collect_height
	var to := target - global_position
	if to.length() < 0.35:
		Inventory.add(item, count)
		Sfx.play_pickup()
		queue_free()
		return
	_vel = _vel.lerp(to.normalized() * 12.0, 1.0 - exp(-9.0 * delta))
	global_position += _vel * delta
	rotate_y(10.0 * delta)
	scale = scale.move_toward(Vector3.ONE * 0.6, delta * 1.5)


func _ground(p: Vector3) -> Vector3:
	var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 2.0, p + Vector3.DOWN * 6.0, WORLD_MASK)
	var player := get_tree().get_first_node_in_group("player") as CollisionObject3D
	if player:
		q.exclude = [player.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	return hit["position"] if hit else p


func _play_flop(strength: float, at: Vector3) -> void:
	var s := AudioStreamPlayer3D.new()
	s.stream = FLOP
	s.pitch_scale = _rng.randf_range(0.92, 1.1) * (1.0 + (1.0 - strength) * 0.25)
	s.volume_db = linear_to_db(strength) + 2.0
	s.unit_size = 5.0
	get_parent().add_child(s)
	s.global_position = at
	s.play()
	s.finished.connect(s.queue_free)


func _set_swim(v: float) -> void:
	for s in _surfaces:
		s.set_instance_shader_parameter("swim", v)


func _set_flash(v: float) -> void:
	for s in _surfaces:
		s.set_instance_shader_parameter("flash", v)


func _flat_to(n: Node3D) -> float:
	return Vector2(n.global_position.x - global_position.x, n.global_position.z - global_position.z).length()
