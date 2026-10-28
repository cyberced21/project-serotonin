extends Node3D
## Fireflies (plans/cozy-sound.md, phase 9; cozy.md's night ambiance): soft blinking points from
## dusk to a little past midnight, in small clusters tied to the world where they'd be for real:
## round the shores of still water (most of them) and at the edges of trees and crops
## (NatureSpots, found once per world). Each cluster is a few fireflies wandering slowly within
## CLUSTER_RADIUS of its spot, blinking out of step, slipping away if you come within SHY m.
## Only the clusters within ACTIVE_RANGE of you are moved and drawn: one MultiMesh of tiny glowing
## billboards (additive, unshaded), so they cost next to nothing.

## Clusters in a world, at least CLUSTER_SPACING m apart, and how many of them are at the water.
const CLUSTERS := 60
const CLUSTER_SPACING := 24.0
const WATER_SHARE := 0.5
## Fireflies in a cluster [min, max], and how far from its spot they wander.
const PER_CLUSTER := Vector2i(3, 7)
const CLUSTER_RADIUS := 4.0
const ACTIVE_RANGE := 70.0
const MAX_SHOWN := 160
const SHY := 3.0
## How high over the ground (m): [min, max].
const HEIGHT := Vector2(0.4, 2.0)
## Wandering speed (m/s) and how fast they slip away when you come close.
const DRIFT := 0.3
const FLEE := 1.4
## Blink: seconds per cycle [min, max], and how much of a cycle the light is on.
const BLINK := Vector2(2.2, 5.0)
const LIT := 0.5
const COLOR := Color(1.0, 0.86, 0.38)
## The glowing quad (m): a bright core of about a fifth of it in a soft halo.
const SIZE := 0.28
## How far past white the core shines (so it blooms).
const BRIGHT := 5.0

var _mm: MultiMeshInstance3D
## One per firefly: where it is, how it's moving, its blink, its cluster's spot, and how far into
## the evening it comes out (0..1, against amount()).
var _pos: PackedVector3Array = []
var _vel: PackedVector3Array = []
var _phase: PackedFloat32Array = []
var _period: PackedFloat32Array = []
var _home: PackedVector3Array = []
var _wake: PackedFloat32Array = []
## Clusters: [spot, first firefly, how many].
var _clusters: Array = []
var _world: int = 0  # the scene the clusters were found in


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
	mat.disable_fog = true  # lights in the dark, not lost in the evening haze
	quad.material = mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = quad
	mm.instance_count = MAX_SHOWN
	mm.visible_instance_count = 0
	_mm = MultiMeshInstance3D.new()
	_mm.multimesh = mm
	_mm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mm.extra_cull_margin = ACTIVE_RANGE * 2.0
	add_child(_mm)


## 0..1: how many are out. Fades in through the evening, full in the first half of the night,
## gone by a little past midnight.
static func amount() -> float:
	var parts := Ambience.dayparts()
	var t := DayNight.time
	var before_midnight := t > 0.5
	var late := 0.0 if before_midnight else smoothstep(0.0, 0.05, t)  # fading out after midnight
	return clampf(parts["evening"] * 0.7 + parts["night"], 0.0, 1.0) * (1.0 - late)


## The clusters' spots in this world (for tests and the debug menu).
func spots() -> PackedVector3Array:
	var out := PackedVector3Array()
	for c in _clusters:
		out.append(c[0])
	return out


func _process(delta: float) -> void:
	var player := get_tree().get_first_node_in_group("player") as Node3D
	var a := amount() if player else 0.0
	_mm.visible = a > 0.01
	if not _mm.visible:
		return
	var scene := get_tree().current_scene
	if scene and scene.get_instance_id() != _world:
		_world = scene.get_instance_id()
		_find_clusters()
	var at := player.global_position
	var mm := _mm.multimesh
	var now := Time.get_ticks_msec() / 1000.0
	var shown := 0
	for c in _clusters:
		var spot: Vector3 = c[0]
		if Vector2(spot.x - at.x, spot.z - at.z).length() > ACTIVE_RANGE:
			continue
		for i in range(c[1], c[1] + c[2]):
			if shown >= MAX_SHOWN:
				break
			_move(i, at, delta, now)
			var cyc := fposmod(now / _period[i] + _phase[i], 1.0)
			var glow := smoothstep(0.0, LIT * 0.5, cyc) * (1.0 - smoothstep(LIT * 0.5, LIT, cyc))
			if _wake[i] > a:
				glow = 0.0
			mm.set_instance_transform(shown, Transform3D(Basis.IDENTITY, _pos[i]))
			mm.set_instance_color(shown, Color(COLOR.r * BRIGHT, COLOR.g * BRIGHT, COLOR.b * BRIGHT, glow))
			shown += 1
	mm.visible_instance_count = shown


## Wanders firefly `i` round its cluster's spot: a slow turning drift, a little bob, back toward
## the spot when it strays, and away from you when you're close.
func _move(i: int, at: Vector3, delta: float, now: float) -> void:
	var p := _pos[i]
	var v := _vel[i]
	var turn := sin(now * 0.7 + i * 1.3) * 0.8
	v = v.rotated(Vector3.UP, turn * delta)
	v.y = sin(now * 0.9 + i) * 0.08
	var to_player := Vector2(p.x - at.x, p.z - at.z)
	var d := to_player.length()
	var home := Vector2(_home[i].x - p.x, _home[i].z - p.z)
	if d < SHY and d > 0.01:
		var away := Vector3(to_player.x, 0.0, to_player.y) / d
		v = v.lerp(away * FLEE, 1.0 - exp(-4.0 * delta))
	elif home.length() > CLUSTER_RADIUS:
		var back := Vector3(home.x, 0.0, home.y).normalized() * DRIFT
		v = v.lerp(Vector3(back.x, v.y, back.z), 1.0 - exp(-1.5 * delta))
	else:
		var flat := Vector2(v.x, v.z)
		if flat.length() > DRIFT:
			flat = flat.normalized() * lerpf(flat.length(), DRIFT, 1.0 - exp(-1.5 * delta))
		v = Vector3(flat.x, v.y, flat.y)
	_vel[i] = v
	p += v * delta
	var ground := _ground(p, _home[i].y)
	p.y = clampf(p.y, ground + HEIGHT.x, ground + HEIGHT.y)
	_pos[i] = p


func _find_clusters() -> void:
	_clusters.clear()
	_pos.clear(); _vel.clear(); _phase.clear(); _period.clear(); _home.clear(); _wake.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = _world
	for spot in NatureSpots.find(get_tree(), CLUSTER_SPACING, CLUSTERS, WATER_SHARE, 1):
		var n := rng.randi_range(PER_CLUSTER.x, PER_CLUSTER.y)
		_clusters.append([spot, _pos.size(), n])
		for k in n:
			var a := rng.randf() * TAU
			var r := rng.randf() * CLUSTER_RADIUS
			var p := spot + Vector3(cos(a) * r, 0.0, sin(a) * r)
			p.y = _ground(p, spot.y) + rng.randf_range(HEIGHT.x, HEIGHT.y)
			_pos.append(p)
			var va := rng.randf() * TAU
			_vel.append(Vector3(cos(va), 0.0, sin(va)) * DRIFT)
			_phase.append(rng.randf())
			_period.append(rng.randf_range(BLINK.x, BLINK.y))
			_home.append(spot)
			_wake.append(rng.randf() * 0.9)


func _ground(p: Vector3, fallback: float) -> float:
	var terrain := get_tree().get_first_node_in_group("terrain") as Terrain3D
	if terrain and terrain.data:
		var h: float = terrain.data.get_height(p)
		if not is_nan(h):
			return h
	return fallback


## A soft round dot for each firefly: a small hot core in a wide faint halo.
static func _dot() -> ImageTexture:
	var n := 64
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var d := Vector2(x + 0.5 - n * 0.5, y + 0.5 - n * 0.5).length() / (n * 0.5)
			var v := exp(-d * d * 40.0) + 0.35 * exp(-d * d * 5.0) * clampf(1.0 - d, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, clampf(v, 0.0, 1.0)))
	return ImageTexture.create_from_image(img)
