class_name Building
extends Node3D
## A village building: a view of Village's tier for its BuildingDef. Shows that tier's pieces of
## the def's model (meshes named T1_*, T2_*, T3_* — see tools/blender/make_village.py), with
## collision, and when the tier changes plays the staged upgrade:
##   1. the old pieces squash and drop into a cloud of dust, top first
##   2. the new pieces pop up out of the ground one by one, bottom first, with a rising "tok"
##   3. a settle bounce, a burst, the tier's name, and the villager cheers (upgraded signal)
## Children: Spots (Marker3Ds the villager walks between — see Villager) and the Villager.
## Empties in the model named *Smoke* get chimney smoke while their tier is shown.
## With unlock_hall_tier set, the building (and its villager) isn't there at all until the town
## hall reaches that tier; then it builds itself piece by piece, like an upgrade.

signal upgraded(tier: int)

const TOK_SFX := preload("res://audio/ui/tok.wav")
const THUD_SFX := preload("res://audio/wood_break.tres")
const WORLD_LAYER := 1
## Pieces smaller than this (m³ of bounding box) get no collision: flowers, handles, notices.
const MIN_COLLIDER_VOLUME := 0.004
const MAX_TOKS := 14
const POPUP_COLOR := Color("ffd27a")
const CRYSTAL_GLOW := Color(0.7, 0.5, 1.0)

@export var def: BuildingDef
## Builds itself when the town hall reaches this tier (0 = always there).
@export var unlock_hall_tier := 0
@export_group("Upgrade feel")
## Seconds the old tier takes to collapse (all pieces), and the new one to build up.
@export var collapse_time := 0.45
@export var build_time := 1.3
## How long each piece's pop takes.
@export var piece_pop := 0.28
@export var shake_collapse := 0.8
@export var shake_done := 1.2

var tier_shown := 0
var _tiers: Dictionary[int, Node3D] = {}
var _bodies: Dictionary[int, StaticBody3D] = {}
var _smoke: Dictionary[int, Array] = {}
var _homes: Dictionary[Node3D, Transform3D] = {}  # every piece's resting transform
var _toks: Array[AudioStreamPlayer3D] = []
var _next_tok := 0
var _thud: AudioStreamPlayer3D
var _dust: CPUParticles3D
var _confetti: CPUParticles3D
var _run := 0  # bumped on every upgrade, so an interrupted animation stops


func _ready() -> void:
	assert(def, "Building needs a BuildingDef")
	add_to_group("building")
	Village.register_building(def)
	_build_tiers()
	_build_effects()
	_show_tier(Village.tier(def.id) if is_unlocked() else 0)
	Village.tier_changed.connect(_on_tier_changed)


func is_unlocked() -> bool:
	return unlock_hall_tier <= 0 or Village.tier(Village.TOWN_HALL) >= unlock_hall_tier


## The marker the villager uses for `spot` (Door, Bench, Work1..3), or null.
func spot(spot_name: String) -> Marker3D:
	return get_node_or_null("Spots/" + spot_name) as Marker3D


## The work spot for the current tier (Work3 at tier 3 if there is one, else the highest below).
func work_spot() -> Marker3D:
	for t in range(tier_shown, 0, -1):
		var m := spot("Work%d" % t)
		if m:
			return m
	return spot("Door")


# --- model ----------------------------------------------------------------------------------

## Sorts the model's meshes into one node per tier (by the TN_ name prefix), each with its own
## static body of convex shapes, and finds the smoke empties.
func _build_tiers() -> void:
	var inst := def.model.instantiate()
	for t in range(1, def.max_tier() + 1):
		var group := Node3D.new()
		group.name = "Tier%d" % t
		group.visible = false
		add_child(group)
		_tiers[t] = group
		var body := StaticBody3D.new()
		body.name = "Tier%dBody" % t
		body.collision_layer = WORLD_LAYER
		body.collision_mask = 0
		add_child(body)
		_bodies[t] = body
		_smoke[t] = []

	for n in inst.find_children("*", "Node3D", true, false):
		var t := _tier_of(n.name)
		if t == 0 or not _tiers.has(t):
			continue
		var xform := _model_transform(n, inst)
		if n is MeshInstance3D:
			var m := n as MeshInstance3D
			m.get_parent().remove_child(m)
			m.owner = null
			for c in m.get_children():  # glTF children are separate pieces, found on their own
				m.remove_child(c)
			_tiers[t].add_child(m)
			m.transform = xform
			m.material_override = PaletteMaterial.for_mesh(m.mesh)  # (weathered stonework: the rock material)
			_homes[m] = xform
			_mark_night_glow(m)
			var aabb := m.get_aabb()
			if aabb.size.x * aabb.size.y * aabb.size.z >= MIN_COLLIDER_VOLUME:
				var shape := CollisionShape3D.new()
				shape.shape = m.mesh.create_convex_shape(true, false)  # simplify=true takes seconds per building
				shape.transform = xform
				_bodies[t].add_child(shape)
		elif n.name.to_lower().contains("smoke"):
			var smoke := _make_smoke()
			_tiers[t].add_child(smoke)
			smoke.transform = Transform3D(Basis.IDENTITY, xform.origin)
			_smoke[t].append(smoke)
	inst.free()


## Lamps and lanterns glow and light up after dark; window glass glows as if lit inside. Crystal
## pieces (the smithy's crystal forge) glow violet, and its crystal lanterns cast violet light.
static func _mark_night_glow(m: MeshInstance3D) -> void:
	var n := String(m.name).to_lower()
	if n.contains("post"):
		return
	if n.contains("lantern") or n.contains("_lamp"):
		DayNightSky.make_glow(m, true)
	elif n.contains("windowglass") or n.contains("crystal"):
		DayNightSky.make_glow(m)
	if n.contains("crystal"):
		m.set_instance_shader_parameter("glow_tint", CRYSTAL_GLOW)
		for light in m.get_children():
			if light is OmniLight3D:
				(light as OmniLight3D).light_color = CRYSTAL_GLOW


static func _tier_of(node_name: String) -> int:
	var s := node_name.to_lower()
	if s.length() > 2 and s[0] == "t" and s[1].is_valid_int() and s[2] == "_":
		return int(s[1])
	return 0


## `n`'s transform relative to the model root (it isn't in the tree yet).
static func _model_transform(n: Node, root: Node) -> Transform3D:
	var xform := Transform3D.IDENTITY
	while n != root:
		if n is Node3D:
			xform = (n as Node3D).transform * xform
		n = n.get_parent()
	return xform


func _show_tier(t: int) -> void:
	tier_shown = t
	for k in _tiers:
		_tiers[k].visible = k == t
		_tiers[k].scale = Vector3.ONE
		_set_collision(k, k == t)
		for s in _smoke[k]:
			(s as CPUParticles3D).emitting = k == t
	for piece in _homes:
		piece.transform = _homes[piece]


func _set_collision(t: int, on: bool) -> void:
	for c in _bodies[t].get_children():
		(c as CollisionShape3D).set_deferred("disabled", not on)


# --- the upgrade ----------------------------------------------------------------------------

func _on_tier_changed(id: StringName, t: int) -> void:
	if id == Village.TOWN_HALL and id != def.id and unlock_hall_tier > 0:
		if is_unlocked() and tier_shown == 0:
			_play_upgrade(0, Village.tier(def.id))  # the town hall grew: move in
		elif not is_unlocked() and tier_shown > 0:
			_show_tier(0)  # (debug: the hall went back down)
	elif id == def.id and t != tier_shown and is_unlocked():
		_play_upgrade(tier_shown, t)


func _play_upgrade(from: int, to: int) -> void:
	_run += 1
	var run := _run
	_show_tier(from)  # snap any half-played animation to a clean start

	# 1. out with the old: top pieces first, squashing down into the dust
	var old: Array[Node3D] = []
	if from > 0:  # (from 0: a new building going up where there was nothing)
		old = _pieces(from)
	old.sort_custom(func(a: Node3D, b: Node3D) -> bool: return _bottom(a) > _bottom(b))
	_dust.restart()
	_play(_thud, THUD_SFX, 0.7)
	Juice.shake(shake_collapse * _falloff())
	var step := collapse_time / maxf(old.size(), 1)
	for i in old.size():
		var p := old[i]
		var t := p.create_tween()
		t.tween_interval(i * step)
		t.tween_property(p, "scale", Vector3(1.15, 0.05, 1.15), 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		t.parallel().tween_property(p, "position:y", p.position.y - 0.25, 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await get_tree().create_timer(collapse_time + 0.16).timeout
	if run != _run:
		return
	if from > 0:
		_set_collision(from, false)
		_tiers[from].visible = false
		for s in _smoke[from]:
			(s as CPUParticles3D).emitting = false
	for p in old:
		p.transform = _homes[p]

	# 2. in with the new: bottom pieces first, each springing up out of the ground
	tier_shown = to
	_tiers[to].visible = true
	_set_collision(to, true)
	var fresh := _pieces(to)
	fresh.sort_custom(func(a: Node3D, b: Node3D) -> bool: return _bottom(a) < _bottom(b))
	for p in fresh:
		p.scale = Vector3.ONE * 0.001
	step = build_time / maxf(fresh.size(), 1)
	var tok_every := maxi(ceili(float(fresh.size()) / MAX_TOKS), 1)
	for i in fresh.size():
		var p := fresh[i]
		var home := _homes[p]
		p.position = home.origin + Vector3.DOWN * 0.3
		var t := p.create_tween()
		t.tween_interval(i * step)
		t.tween_property(p, "scale", home.basis.get_scale(), piece_pop).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		t.parallel().tween_property(p, "position", home.origin, piece_pop).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		if i % tok_every == 0:
			var pitch := lerpf(0.8, 1.6, float(i) / maxf(fresh.size() - 1, 1))
			t.parallel().tween_callback(_tok.bind(p.global_position, pitch))
	await get_tree().create_timer(build_time + piece_pop).timeout
	if run != _run:
		return
	for s in _smoke[to]:
		(s as CPUParticles3D).emitting = true

	# 3. it's done: settle bounce (the visuals only — physics bodies can't squash), burst, name, fanfare
	var group := _tiers[to]
	group.scale = Vector3(1.04, 0.92, 1.04)
	create_tween().tween_property(group, "scale", Vector3.ONE, 0.5).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	_confetti.restart()
	Juice.shake(shake_done * _falloff())
	Music.play_cue(&"upgrade")
	var top := _top_of(fresh)
	var tier_res := def.get_tier(to)
	if tier_res:
		PopupText.spawn(get_parent(), Vector3(global_position.x, top + 0.8, global_position.z),
			"%s!" % tier_res.name, POPUP_COLOR, 18)
	upgraded.emit(to)


func _pieces(t: int) -> Array[Node3D]:
	var out: Array[Node3D] = []
	for c in _tiers[t].get_children():
		if c is MeshInstance3D:
			out.append(c)
	return out


## Local height of a piece's lowest point.
func _bottom(p: Node3D) -> float:
	var aabb := _homes[p] * (p as MeshInstance3D).get_aabb()
	return aabb.position.y


func _top_of(pieces: Array[Node3D]) -> float:
	var top := 3.0
	for p in pieces:
		var aabb := _homes[p] * (p as MeshInstance3D).get_aabb()
		top = maxf(top, aabb.end.y)
	return global_position.y + top


func _tok(at: Vector3, pitch: float) -> void:
	var player := _toks[_next_tok]
	_next_tok = (_next_tok + 1) % _toks.size()
	player.global_position = at
	_play(player, TOK_SFX, pitch)


func _play(player: AudioStreamPlayer3D, stream: AudioStream, pitch := 1.0) -> void:
	player.stream = stream
	player.pitch_scale = pitch
	player.play()


## 1 near the building, fading to 0 by 30 m from the player.
func _falloff() -> float:
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player == null:
		return 1.0
	return clampf(1.0 - player.global_position.distance_to(global_position) / 30.0, 0.0, 1.0)


# --- effects --------------------------------------------------------------------------------

func _build_effects() -> void:
	for i in 4:
		var a := AudioStreamPlayer3D.new()
		a.unit_size = 6.0
		a.max_distance = 60.0
		add_child(a)
		_toks.append(a)
	_thud = AudioStreamPlayer3D.new()
	_thud.unit_size = 8.0
	_thud.max_distance = 60.0
	add_child(_thud)

	var footprint := _footprint()
	_dust = _make_burst(36, 1.2, Color("8f7759"), 0.28)
	_dust.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_dust.emission_box_extents = Vector3(footprint.x * 0.5, 0.3, footprint.y * 0.5)
	_dust.position = Vector3(0, 0.4, 0)
	_dust.direction = Vector3.UP
	_dust.spread = 80.0
	_dust.initial_velocity_min = 1.0
	_dust.initial_velocity_max = 3.0
	_dust.gravity = Vector3(0, -1.5, 0)
	_dust.damping_min = 1.5
	_dust.damping_max = 2.5

	_confetti = _make_burst(48, 1.6, Color.WHITE, 0.12)
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.25, 0.5, 0.75, 1.0])
	ramp.colors = PackedColorArray([Color("f2cf4a"), Color("e66fa1"), Color("64b5e8"), Color("9be27a"), Color("e88a2c")])
	_confetti.color_initial_ramp = ramp
	_confetti.position = Vector3(0, 3.0, 0)
	_confetti.direction = Vector3.UP
	_confetti.spread = 50.0
	_confetti.initial_velocity_min = 5.0
	_confetti.initial_velocity_max = 8.0
	_confetti.angular_velocity_min = -360.0
	_confetti.angular_velocity_max = 360.0


## Half the diagonal of the largest tier's footprint: everything it ever builds is within this.
func footprint_radius() -> float:
	return _footprint().length() * 0.5


## Width (x) and depth (z) of the largest tier, for the dust cloud.
func _footprint() -> Vector2:
	var size := Vector2(4, 4)
	for piece in _homes:
		var aabb := _homes[piece] * (piece as MeshInstance3D).get_aabb()
		size.x = maxf(size.x, absf(aabb.position.x) * 2.0)
		size.x = maxf(size.x, absf(aabb.end.x) * 2.0)
		size.y = maxf(size.y, absf(aabb.position.z) * 2.0)
		size.y = maxf(size.y, absf(aabb.end.z) * 2.0)
	return size


func _make_burst(amount: int, lifetime: float, color: Color, size: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.emitting = false
	p.one_shot = true
	p.explosiveness = 0.9
	p.amount = amount
	p.lifetime = lifetime
	var mesh := SphereMesh.new()  # 4 x 2 segments: a little faceted diamond
	mesh.radial_segments = 4
	mesh.rings = 2
	mesh.radius = size * 0.6
	mesh.height = size
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 1.0
	mesh.material = mat
	p.mesh = mesh
	p.particle_flag_rotate_y = true
	p.angle_min = -180.0
	p.angle_max = 180.0
	p.color = color
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.4
	var shrink := Curve.new()
	shrink.add_point(Vector2(0, 1))
	shrink.add_point(Vector2(1, 0))
	p.scale_amount_curve = shrink
	add_child(p)
	return p


func _make_smoke() -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.name = "Smoke"
	p.amount = 14
	p.lifetime = 4.0
	p.local_coords = false
	var mesh := BoxMesh.new()
	mesh.size = Vector3.ONE * 0.35
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.material = mat
	p.mesh = mesh
	p.direction = Vector3.UP
	p.spread = 12.0
	p.initial_velocity_min = 0.5
	p.initial_velocity_max = 0.8
	p.gravity = Vector3(0.25, 0.15, 0.1)  # a little drift, as if there's a breeze
	p.angular_velocity_min = -40.0
	p.angular_velocity_max = 40.0
	var grow := Curve.new()
	grow.add_point(Vector2(0, 0.4))
	grow.add_point(Vector2(1, 1.0))
	p.scale_amount_curve = grow
	p.scale_amount_min = 0.8
	p.scale_amount_max = 1.6
	var fade := Gradient.new()
	fade.offsets = PackedFloat32Array([0.0, 0.15, 1.0])
	fade.colors = PackedColorArray([Color(0.75, 0.75, 0.75, 0.0), Color(0.72, 0.72, 0.72, 0.55), Color(0.85, 0.85, 0.85, 0.0)])
	p.color_ramp = fade
	return p
