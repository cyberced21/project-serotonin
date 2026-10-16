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
## a split) — more chips and dust.
static func spawn(scene: PackedScene, parent: Node, at: Vector3, normal: Vector3, swing: Vector3,
		stone: Color, ore: Color, strength := 1.0, spark_count := 0) -> void:
	var fx := scene.instantiate() as HitFx
	parent.add_child(fx)
	fx.global_transform = Transform3D(facing(normal), at + normal * 0.04)
	fx._play(normal, swing, stone, ore, strength, spark_count)


## A basis whose +Z points along `dir` (the emitters shoot along +Z).
static func facing(dir: Vector3) -> Basis:
	return Basis.looking_at(-dir, Vector3.UP if absf(dir.y) < 0.95 else Vector3.RIGHT)


func _play(normal: Vector3, swing: Vector3, stone: Color, ore: Color, strength: float, spark_count: int) -> void:
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
		var glance := swing.bounce(normal).normalized() * 0.7 + normal * 0.5
		sparks.global_basis = facing(glance.normalized())
		sparks.emitting = true
	var life := maxf(chips.lifetime, dust.lifetime) * 1.3
	get_tree().create_timer(life).timeout.connect(queue_free)


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
