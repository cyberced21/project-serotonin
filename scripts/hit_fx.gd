class_name HitFx
extends Node3D
## One mining hit's chips, shards, dust and sparks (scenes/fx/hit_fx.tscn). A fresh one per hit,
## freed once it has all landed, so quick hits don't cut each other's particles short. Chips
## bounce off the ground through the player's heightfield (GroundCollision in player.tscn).
## Particle look is tweakable in the scene; colours and amounts come from the node that was hit.

## The chips' colours: mostly stone, some ore. Cached per colour pair, shared by every hit.
const ORE_SHARE := 0.3

static var _materials := {}

@onready var chips: GPUParticles3D = $Chips
@onready var shards: GPUParticles3D = $Shards
@onready var dust: GPUParticles3D = $Dust
@onready var sparks: GPUParticles3D = $Sparks


## Plays at `at` on a surface facing `normal`. `swing` is the direction the tool was travelling
## (sparks glance off along it). `strength`: 1 for a hit, more for bigger moments (a crack tip,
## a split) — more chips and dust. `spark_tint`: the sparks' colour instead of the hot orange
## (a better tool's: white-hot iron, violet crystal); blank keeps the orange.
static func spawn(scene: PackedScene, parent: Node, at: Vector3, normal: Vector3, swing: Vector3,
		stone: Color, ore: Color, strength := 1.0, spark_count := 0, spark_tint := Color(0, 0, 0, 0)) -> void:
	var fx := scene.instantiate() as HitFx
	parent.add_child(fx)
	fx.global_transform = Transform3D(facing(normal), at + normal * 0.04)
	fx._play(normal, swing, stone, ore, strength, spark_count, spark_tint)


## The impact star: a bright flash at the point of contact for two or three frames, popping out
## and shrinking away, drawn over everything. Real time, so it shows during the hit-stop.
## `size` is its width (m) at the peak.
static func star(parent: Node, at: Vector3, color: Color, size := 0.5) -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	var flash := MeshInstance3D.new()
	flash.mesh = quad
	flash.material_override = _star_material(color)
	flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(flash)
	flash.global_position = at
	flash.scale = Vector3.ONE * size * 0.5
	var t := flash.create_tween().set_ignore_time_scale(true)
	t.tween_property(flash, "scale", Vector3.ONE * size, 0.035).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_property(flash, "scale", Vector3.ONE * size * 0.2, 0.035).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	t.tween_callback(flash.queue_free)


static var _star_tex: Texture2D
static var _star_materials := {}

## Additive, unshaded, facing the camera, over everything; one per colour.
static func _star_material(color: Color) -> Material:
	var key := color.to_html()
	if _star_materials.has(key):
		return _star_materials[key]
	if _star_tex == null:
		_star_tex = _make_star_texture()
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.billboard_keep_scale = true
	m.no_depth_test = true
	m.render_priority = 10
	m.albedo_texture = _star_tex
	m.albedo_color = color
	_star_materials[key] = m
	return m


## Four long spikes, four short diagonal ones and a hot core.
static func _make_star_texture() -> Texture2D:
	const S := 64
	var img := Image.create_empty(S, S, false, Image.FORMAT_RGBA8)
	var c := (S - 1) * 0.5
	for y in S:
		for x in S:
			var d := Vector2(x - c, y - c) / c  # -1..1
			var r := d.length()
			var a := atan2(d.y, d.x)
			var long := pow(absf(cos(a * 2.0)), 40.0) * clampf(1.0 - r, 0.0, 1.0)
			var short := pow(absf(sin(a * 2.0)), 60.0) * clampf(1.0 - r * 1.8, 0.0, 1.0) * 0.7
			var core := clampf(1.0 - r * 3.5, 0.0, 1.0)
			var v := clampf(long + short + core * core, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, v))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


## A basis whose +Z points along `dir` (the emitters shoot along +Z).
static func facing(dir: Vector3) -> Basis:
	return Basis.looking_at(-dir, Vector3.UP if absf(dir.y) < 0.95 else Vector3.RIGHT)


func _play(normal: Vector3, swing: Vector3, stone: Color, ore: Color, strength: float, spark_count: int,
		spark_tint: Color) -> void:
	chips.process_material = _tinted(chips.process_material, stone, ore)
	shards.process_material = _tinted(shards.process_material, stone, ore)
	dust.process_material = _tinted(dust.process_material, stone.lightened(0.3), Color())
	chips.amount_ratio = clampf(0.55 * strength, 0.1, 1.0)
	shards.amount_ratio = clampf(0.4 * strength, 0.1, 1.0)
	dust.amount_ratio = clampf(0.45 * strength, 0.1, 1.0)
	for p in [chips, shards, dust]:
		p.emitting = true
	if spark_count > 0:
		sparks.amount = spark_count
		if spark_tint.a > 0.0:
			sparks.material_override = _spark_material(sparks.draw_pass_1.surface_get_material(0), spark_tint)
		var glance := swing.bounce(normal).normalized() * 0.7 + normal * 0.5
		sparks.global_basis = facing(glance.normalized())
		sparks.emitting = true
	var life := maxf(chips.lifetime, dust.lifetime) * 1.3
	get_tree().create_timer(life).timeout.connect(queue_free)


static var _spark_materials := {}


## The spark material in `tint` (one per colour, so it compiles once).
static func _spark_material(base: Material, tint: Color) -> Material:
	if not _spark_materials.has(tint):
		var m := base.duplicate() as StandardMaterial3D
		m.albedo_color = tint
		_spark_materials[tint] = m
	return _spark_materials[tint]


## A copy of `base` in these colours: `ore` (unless it's blank) on ORE_SHARE of the particles.
static func _tinted(base: Material, stone: Color, ore: Color) -> Material:
	var key := "%d|%s|%s" % [base.get_instance_id(), stone.to_html(), ore.to_html()]
	if _materials.has(key):
		return _materials[key]
	var m := base.duplicate() as ParticleProcessMaterial
	if ore.a > 0.0:
		var g := Gradient.new()
		g.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT
		g.set_color(0, stone)
		g.set_color(1, ore)
		g.set_offset(1, 1.0 - ORE_SHARE)
		var tex := GradientTexture1D.new()
		tex.gradient = g
		m.color_initial_ramp = tex
	else:
		m.color = stone
	_materials[key] = m
	return m
