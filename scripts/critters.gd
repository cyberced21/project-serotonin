class_name Critters
extends Node3D
## Small wildlife round a spot (plans/world-pass.md, phase 8): butterflies over the meadow and the
## flowers, bees round the orchard's trees and the allotments, dragonflies darting over the water,
## birds pecking about under the trees that flutter off when you come near and drift back later.
## Each is a few meshes moved in code; only the swarms near you (ACTIVE) are moved, by day (or
## whenever, with `day_only` off). A swarm can carry a quiet looping sound of its own (the bees).

const ACTIVE := 70.0
const KINDS := {
	&"butterfly": {"speed": 1.2, "height": Vector2(0.4, 1.8), "wander": 1.0},
	&"bee": {"speed": 2.2, "height": Vector2(0.4, 2.2), "wander": 3.0},
	&"dragonfly": {"speed": 4.0, "height": Vector2(0.3, 1.0), "wander": 0.4},
	&"bird": {"speed": 5.0, "height": Vector2(0.0, 0.0), "wander": 0.2},
}
const WING_COLORS: Array[Color] = [Color("f2b84b"), Color("e86f4f"), Color("f4f0e6"), Color("8fb8e6"), Color("c98fd6")]
const BIRD_SHY := 6.0

@export var kind: StringName = &"butterfly"
@export var count := 6
@export var radius := 8.0
@export var day_only := true
## A looping sound for the whole swarm (audio/country/<name>.mp3), or none.
@export var sound := ""
@export var sound_db := -18.0

var _bugs: Array[Dictionary] = []  # {node, goal, phase, wings, flown}
var _terrain: Terrain3D
var _rng := RandomNumberGenerator.new()
var _hum: AudioStreamPlayer3D


func _ready() -> void:
	add_to_group("critters")
	_rng.seed = hash(str(global_position)) + count
	for i in count:
		var n := _make()
		add_child(n)
		n.position = Vector3(_rng.randf_range(-radius, radius), 1.0, _rng.randf_range(-radius, radius))
		_bugs.append({"node": n, "goal": n.position, "phase": _rng.randf() * TAU, "rest": 0.0, "flown": 0.0})
	if sound != "":
		_hum = AudioStreamPlayer3D.new()
		var stream := load("res://audio/country/%s.mp3" % sound) as AudioStreamMP3
		stream.loop = true
		_hum.stream = stream
		_hum.bus = &"Ambience"
		_hum.volume_db = sound_db
		_hum.max_distance = radius + 10.0
		add_child(_hum)


func _process(delta: float) -> void:
	var player := get_tree().get_first_node_in_group("player") as Node3D
	var awake := (not day_only or not DayNight.is_night()) and player != null \
			and player.global_position.distance_to(global_position) < ACTIVE
	visible = awake
	if _hum:
		if awake and not _hum.playing:
			_hum.play(_rng.randf() * 10.0)
		elif not awake and _hum.playing:
			_hum.stop()
	if not awake:
		return
	if _terrain == null:
		_terrain = get_tree().get_first_node_in_group("terrain") as Terrain3D
	var def: Dictionary = KINDS[kind]
	for b in _bugs:
		var n: Node3D = b["node"]
		b["phase"] += delta
		if kind == &"bird":
			_bird(b, n, player, delta)
			continue
		if n.position.distance_to(b["goal"]) < 0.3 or _rng.randf() < delta * 0.2:
			b["goal"] = _new_goal(def)
			if kind == &"dragonfly":  # dart, then hover
				b["rest"] = _rng.randf_range(0.3, 1.5)
		if b["rest"] > 0.0:
			b["rest"] -= delta
		else:
			var to: Vector3 = b["goal"] - n.position
			var wobble := Vector3(sin(b["phase"] * 7.0), sin(b["phase"] * 5.3) * 0.6, cos(b["phase"] * 6.1)) * float(def["wander"]) * 0.15
			n.position += (to.normalized() * float(def["speed"]) + wobble) * delta
			if to.length() > 0.05:
				n.rotation.y = lerp_angle(n.rotation.y, atan2(to.x, to.z), 1.0 - exp(-8.0 * delta))
		if kind == &"butterfly":  # flapping
			var flap := sin(b["phase"] * 18.0) * 0.9
			(n.get_child(0) as Node3D).rotation.z = flap
			(n.get_child(1) as Node3D).rotation.z = -flap


func _new_goal(def: Dictionary) -> Vector3:
	var p := Vector3(_rng.randf_range(-radius, radius), 0.0, _rng.randf_range(-radius, radius))
	var h := _ground_local(p)
	p.y = h + _rng.randf_range(def["height"].x, def["height"].y)
	return p


## Birds peck about on the ground; you coming near and they fly up and off, back a while later.
func _bird(b: Dictionary, n: Node3D, player: Node3D, delta: float) -> void:
	if b["flown"] > 0.0:
		b["flown"] -= delta
		n.position += Vector3(sin(n.rotation.y), 0.9, cos(n.rotation.y)) * KINDS[kind]["speed"] * delta
		if b["flown"] <= 0.0:
			n.position = Vector3(_rng.randf_range(-radius, radius), 0.0, _rng.randf_range(-radius, radius))
		return
	n.position.y = _ground_local(n.position) + absf(sin(b["phase"] * 9.0)) * 0.03  # a little hop
	if _rng.randf() < delta * 0.6:  # a few hops somewhere else, a peck
		n.position += Vector3(_rng.randf_range(-0.4, 0.4), 0.0, _rng.randf_range(-0.4, 0.4))
		n.rotation.y = _rng.randf() * TAU
	if player.global_position.distance_to(n.global_position) < BIRD_SHY:
		b["flown"] = _rng.randf_range(20.0, 40.0)
		var away := n.global_position - player.global_position
		n.rotation.y = atan2(away.x, away.z)


func _ground_local(p: Vector3) -> float:
	var w := global_transform * p
	if _terrain and _terrain.data:
		var h: float = _terrain.data.get_height(w)
		if not is_nan(h):
			return h - global_position.y
	return 0.0


func _make() -> Node3D:
	var n := Node3D.new()
	match kind:
		&"butterfly":
			var c := WING_COLORS[_rng.randi() % WING_COLORS.size()]
			for side in [-1.0, 1.0]:
				var hinge := Node3D.new()
				n.add_child(hinge)
				var wing := MeshInstance3D.new()
				var q := QuadMesh.new()
				q.size = Vector2(0.06, 0.05)
				wing.mesh = q
				wing.position = Vector3(side * 0.03, 0, 0)
				wing.rotation.x = -PI / 2.0
				var mat := StandardMaterial3D.new()
				mat.albedo_color = c
				mat.cull_mode = BaseMaterial3D.CULL_DISABLED
				wing.material_override = mat
				hinge.add_child(wing)
		&"bee":
			var m := MeshInstance3D.new()
			var s := SphereMesh.new()
			s.radius = 0.018
			s.height = 0.03
			m.mesh = s
			m.scale = Vector3(1, 1, 1.5)
			var mat := StandardMaterial3D.new()
			mat.albedo_color = Color("e8b938")
			m.material_override = mat
			n.add_child(m)
		&"dragonfly":
			var model := (load("res://models/animals/%s.glb" % ("red_dragonfly" if _rng.randf() < 0.4 else "dragonfly")) as PackedScene).instantiate() as Node3D
			model.scale = Vector3.ONE * 0.4
			n.add_child(model)
		&"bird":
			var model := (load("res://models/animals/bird.glb") as PackedScene).instantiate() as Node3D
			model.scale = Vector3.ONE * 0.2
			n.add_child(model)
	return n
