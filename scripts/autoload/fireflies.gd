extends Node3D
## Fireflies (plans/cozy-sound.md, phase 9; cozy.md's night ambiance): soft blinking points from
## dusk to a little past midnight, round wherever you are. COUNT of them live in a ring RING_NEAR
## to RING_FAR m from you, settled low over the ground, more of them by water and in the forest.
## Each one wanders slowly, blinks on and off out of step with the rest, and drifts away if you
## come within SHY m. One that falls behind you (past RING_FAR) lights up again somewhere ahead.
## Drawn as a single MultiMesh of tiny glowing billboards (additive, unshaded), so they cost
## next to nothing.

const COUNT := 60
const RING_NEAR := 4.0
const RING_FAR := 26.0
const SHY := 3.0
## How high over the ground (m): [min, max].
const HEIGHT := Vector2(0.4, 2.2)
## Wandering speed (m/s) and how fast they slip away when you come close.
const DRIFT := 0.35
const FLEE := 1.4
## Blink: seconds per cycle [min, max], and how much of a cycle the light is on.
const BLINK := Vector2(2.2, 5.0)
const LIT := 0.35
const COLOR := Color(1.0, 0.86, 0.38)
const SIZE := 0.07
## How much likelier a spot by water (within WATER_PULL m of a pond's edge) or in the forest is.
const WATER_PULL := 12.0

var _mm: MultiMeshInstance3D
var _pos: PackedVector3Array = []
var _vel: PackedVector3Array = []
var _phase: PackedFloat32Array = []
var _period: PackedFloat32Array = []
var _seeded := false


func _ready() -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2(SIZE, SIZE)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = _dot()
	mat.no_depth_test = false
	quad.material = mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = quad
	mm.instance_count = COUNT
	_mm = MultiMeshInstance3D.new()
	_mm.multimesh = mm
	_mm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mm.extra_cull_margin = RING_FAR * 2.0
	add_child(_mm)
	_pos.resize(COUNT); _vel.resize(COUNT); _phase.resize(COUNT); _period.resize(COUNT)
	for i in COUNT:
		_phase[i] = randf()
		_period[i] = randf_range(BLINK.x, BLINK.y)


## 0..1: how many are out. Fades in through the evening, full in the first half of the night,
## gone by a little past midnight.
static func amount() -> float:
	var parts := Ambience.dayparts()
	var t := DayNight.time
	var before_midnight := t > 0.5
	var late := 0.0 if before_midnight else smoothstep(0.0, 0.05, t)  # fading out after midnight
	return clampf(parts["evening"] * 0.7 + parts["night"], 0.0, 1.0) * (1.0 - late)


func _process(delta: float) -> void:
	var player := get_tree().get_first_node_in_group("player") as Node3D
	var a := amount() if player else 0.0
	_mm.visible = a > 0.01
	if not _mm.visible:
		_seeded = false
		return
	var at := player.global_position
	if not _seeded:
		for i in COUNT:
			_respawn(i, at, false)
		_seeded = true
	var mm := _mm.multimesh
	var shown := int(round(a * COUNT))
	var now := Time.get_ticks_msec() / 1000.0
	for i in COUNT:
		var p := _pos[i]
		var to_player := Vector2(p.x - at.x, p.z - at.z)
		var d := to_player.length()
		if d > RING_FAR:
			_respawn(i, at, true)
			p = _pos[i]
			to_player = Vector2(p.x - at.x, p.z - at.z)
			d = to_player.length()
		# wander: a slow turning drift, a little bob, and away from you when you're close
		var v := _vel[i]
		var turn := sin(now * 0.7 + i * 1.3) * 0.8
		v = v.rotated(Vector3.UP, turn * delta)
		v.y = sin(now * 0.9 + i) * 0.08
		if d < SHY and d > 0.01:
			var away := Vector3(to_player.x, 0.0, to_player.y) / d
			v = v.lerp(away * FLEE, 1.0 - exp(-4.0 * delta))
		else:
			var flat := Vector2(v.x, v.z)
			if flat.length() > DRIFT:
				flat = flat.normalized() * lerpf(flat.length(), DRIFT, 1.0 - exp(-1.5 * delta))
			v = Vector3(flat.x, v.y, flat.y)
		_vel[i] = v
		p += v * delta
		var ground := _ground(p, at.y)
		p.y = clampf(p.y, ground + HEIGHT.x, ground + HEIGHT.y)
		_pos[i] = p
		# blink: a soft pulse once per period, each out of step
		var c := fposmod(now / _period[i] + _phase[i], 1.0)
		var glow := smoothstep(0.0, LIT * 0.5, c) * (1.0 - smoothstep(LIT * 0.5, LIT, c))
		if i >= shown:
			glow = 0.0
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, p))
		mm.set_instance_color(i, Color(COLOR.r * 3.0, COLOR.g * 3.0, COLOR.b * 3.0, glow))


## Puts firefly `i` somewhere in the ring round `at` (ahead of you when `ahead`: you won't see one
## pop in behind your back), preferring spots near still water and in the forest.
func _respawn(i: int, at: Vector3, ahead: bool) -> void:
	var best := Vector3.ZERO
	var best_score := -1.0
	var cam := get_viewport().get_camera_3d()
	var fwd := Vector2(0, -1)
	if cam:
		var f := -cam.global_basis.z
		fwd = Vector2(f.x, f.z).normalized()
	for attempt in 4:
		var ang := randf() * TAU
		if ahead:
			ang = fwd.angle() + randf_range(-1.1, 1.1)
		var r := randf_range(RING_NEAR, RING_FAR) if not ahead else randf_range(RING_FAR * 0.55, RING_FAR * 0.95)
		var cand := at + Vector3(cos(ang) * r, 0.0, sin(ang) * r)
		var score := randf() + _appeal(cand)
		if score > best_score:
			best_score = score
			best = cand
	best.y = _ground(best, at.y) + randf_range(HEIGHT.x, HEIGHT.y)
	_pos[i] = best
	var a := randf() * TAU
	_vel[i] = Vector3(cos(a), 0.0, sin(a)) * DRIFT


## How much a firefly likes a spot: near still water, or in the forest.
func _appeal(p: Vector3) -> float:
	var score := 0.0
	for w in get_tree().get_nodes_in_group("water"):
		var water := w as WaterBody
		if water.flow != Vector3.ZERO:
			continue
		var c := water.global_position
		var half := ((water.get_node("Volume") as CollisionShape3D).shape as BoxShape3D).size * 0.5
		if Vector2(p.x - c.x, p.z - c.z).length() < maxf(half.x, half.z) + WATER_PULL:
			score += 1.0
	if Biome.biome_at(p) == &"pinewood":
		score += 0.7
	return score


func _ground(p: Vector3, fallback: float) -> float:
	var terrain := get_tree().get_first_node_in_group("terrain") as Terrain3D
	if terrain and terrain.data:
		var h: float = terrain.data.get_height(p)
		if not is_nan(h):
			return h
	return fallback - 1.6


## A soft round dot, bright in the middle, for each firefly.
static func _dot() -> ImageTexture:
	var n := 32
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var d := Vector2(x + 0.5 - n * 0.5, y + 0.5 - n * 0.5).length() / (n * 0.5)
			var v := clampf(1.0 - d, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, v * v))
	return ImageTexture.create_from_image(img)
