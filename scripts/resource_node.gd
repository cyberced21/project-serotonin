class_name ResourceNode
extends StaticBody3D
## A gatherable node (tree, rock, ore vein...). Everything is tweakable from the inspector.
## To make a new resource type: right-click scenes/resource_node.tscn > New Inherited Scene, then add
## MeshInstance3Ds under:
##   Visual/Body   — the part that stays until the node breaks (core, trunk, canopy)
##   Visual/Chunks — pieces that break off as it wears down (the one nearest the hit pops off)
##   Rubble        — what's left while it respawns (stump, rubble)
## Give meshes materials/node_surface.tres as Material Override and set their colour under
## Geometry > Instance Shader Parameters > albedo. Then set the item, sounds and colors here.

signal depleted(node: ResourceNode)
signal respawned(node: ResourceNode)

const PICKUP_SCENE := preload("res://scenes/pickup.tscn")
const DEFLECT_SFX := preload("res://audio/stone_hit.tres")
const DEFLECT_COLOR := Color("ff8a7a")
const WORLD_LAYER := 1
## Physics layer 4: debris collides with the world but not the player (layer 2) or pickups.
const DEBRIS_LAYER := 1 << 3
const DEBRIS_LIFETIME := 1.6

@export_group("Gathering")
@export var item: StringName = &"wood"
@export var item_icon: Texture2D
@export var tool_type: StringName = &"axe"
@export_range(1, 20) var max_hits := 5
@export_range(0, 10) var drops_min := 2
@export_range(0, 10) var drops_max := 4
@export var respawn_time := 15.0

@export_group("Skill")
## Skill id from Skills.SKILLS (e.g. woodcutting, mining).
@export var skill: StringName = &"woodcutting"
@export_range(1, 50) var required_level := 1
@export_range(0, 100) var xp_per_hit := 5
@export_range(0, 500) var xp_on_break := 15

@export_group("Visuals")
@export var chip_color := Color("dea876")
@export var burst_color := Color("38804c")
## Height above the node's origin where XP / level popups appear.
@export var popup_height := 1.6
## How hard broken-off chunks fly away (m/s).
@export var debris_speed := 3.0

@export_group("Audio")
@export var hit_sfx: AudioStream
@export var break_sfx: AudioStream
## How much higher-pitched each hit gets as the node weakens (escalation).
@export_range(0.0, 0.5) var stress_pitch := 0.15

@export_group("Feel")
@export var hitstop_hit := 0.045
@export var hitstop_break := 0.11
@export var shake_hit := 1.5
@export var shake_break := 4.0

@onready var visual: Node3D = $Visual
@onready var chunks: Node3D = $Visual/Chunks
@onready var rubble: Node3D = $Rubble
@onready var collision: CollisionShape3D = $CollisionShape3D
@onready var chips: CPUParticles3D = $Chips
@onready var burst: CPUParticles3D = $Burst
@onready var audio: AudioStreamPlayer3D = $Audio
@onready var break_audio: AudioStreamPlayer3D = $BreakAudio

var hits_left := 0
var _surfaces: Array[GeometryInstance3D] = []
var _flash_tween: Tween
var _nudge_tween: Tween


func _ready() -> void:
	add_to_group("gatherable")
	_collect_surfaces(visual)
	chips.color = chip_color
	burst.color = burst_color
	hits_left = max_hits
	_reset_visuals()


func is_available() -> bool:
	return hits_left > 0


## False when the player's skill level is too low — hits will bounce off.
func can_gather() -> bool:
	return Skills.level(skill) >= required_level


## Called by the player while the crosshair is on this node.
func set_highlighted(on: bool) -> void:
	for s in _surfaces:
		s.set_instance_shader_parameter("highlight", 1.0 if on else 0.0)


## Called by the player on the impact frame of a swing.
func hit(info: HitInfo) -> void:
	if hits_left <= 0:
		return
	if not can_gather():
		_deflect(info)
		return
	hits_left -= 1
	var stress := 1.0 - float(hits_left) / max_hits  # 0 -> 1 as it depletes

	_play(audio, hit_sfx, 1.0 + stress * stress_pitch)
	_flash()
	_nudge(info.away())
	_chips_at(info)
	Juice.shake(shake_hit + stress * 1.5)
	Juice.hitstop(hitstop_hit)
	_award_xp(xp_per_hit)

	if hits_left == 0:
		_break(info)
	else:
		_shed_chunks(stress, info)


## Under-levelled: the tool bounces off — clank, small nudge, no damage, no XP.
func _deflect(info: HitInfo) -> void:
	_play(audio, DEFLECT_SFX, 1.8)
	_nudge(info.away())
	Juice.shake(0.5)
	PopupText.spawn(get_parent(), _popup_pos(), "%s %d" % [Skills.display_name(skill), required_level], DEFLECT_COLOR)


func _award_xp(amount: int, big := false) -> void:
	if amount <= 0:
		return
	var gained := Skills.add_xp(skill, amount)
	if gained > 0:
		PopupText.spawn(get_parent(), _popup_pos() + Vector3(randf_range(-0.2, 0.2), 0.25 if big else 0.0, 0.0),
			"+%d" % gained, Skills.color(skill), 10 if big else 8, 0.08 if big else 0.0)


func _popup_pos() -> Vector3:
	return global_position + Vector3(0, popup_height, 0)


func _break(info: HitInfo) -> void:
	_award_xp(xp_on_break, true)
	_play(break_audio, break_sfx)
	for c in _intact_chunks():
		_pop_chunk(c, info.away(), debris_speed * 0.7)
	set_highlighted(false)
	visual.visible = false
	rubble.visible = true
	collision.set_deferred("disabled", true)
	burst.restart()
	Juice.shake(shake_break)
	Juice.hitstop(hitstop_break)
	_spawn_drops(info)
	depleted.emit(self)

	await get_tree().create_timer(respawn_time).timeout
	hits_left = max_hits
	_reset_visuals()
	visual.scale = Vector3.ONE * 0.4
	create_tween().tween_property(visual, "scale", Vector3.ONE, 0.35) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	respawned.emit(self)


func _reset_visuals() -> void:
	for c in chunks.get_children():
		c.visible = true
	visual.visible = true
	rubble.visible = false
	collision.set_deferred("disabled", false)


func _spawn_drops(info: HitInfo) -> void:
	var count := randi_range(drops_min, maxi(drops_min, drops_max))
	var toward_player := -info.away()
	for i in count:
		var p := PICKUP_SCENE.instantiate()
		p.item = item
		p.icon = item_icon
		get_parent().add_child(p)
		var spread := Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)) * 1.2
		var vel := toward_player * randf_range(1.0, 2.0) + spread + Vector3.UP * randf_range(3.0, 4.5)
		p.launch(global_position + Vector3(0, popup_height * 0.5, 0) + toward_player * 0.4, vel, i * 0.04)


# --- chunks ---------------------------------------------------------------------------------

## Pops chunks off until the visible amount matches how worn down the node is.
## The last chunk always stays on until the node actually breaks.
func _shed_chunks(stress: float, info: HitInfo) -> void:
	var total := chunks.get_child_count()
	var should_be_gone := mini(floori(stress * total), total - 1)
	var intact := _intact_chunks()
	while total - intact.size() < should_be_gone and not intact.is_empty():
		var nearest := _nearest(intact, info.position)
		intact.erase(nearest)
		_pop_chunk(nearest, (info.normal + info.away() * 0.5).normalized(), debris_speed)


func _intact_chunks() -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	for c in chunks.get_children():
		if c is MeshInstance3D and c.visible:
			out.append(c)
	return out


func _nearest(list: Array[MeshInstance3D], point: Vector3) -> MeshInstance3D:
	var best: MeshInstance3D = list[0]
	var best_d := INF
	for c in list:
		var d := (c.global_transform * c.get_aabb().get_center()).distance_squared_to(point)
		if d < best_d:
			best_d = d
			best = c
	return best


## Hides the chunk and throws a physics copy of it, which shrinks away after a moment.
func _pop_chunk(chunk: MeshInstance3D, push: Vector3, speed: float) -> void:
	chunk.visible = false
	var body := RigidBody3D.new()
	body.collision_layer = DEBRIS_LAYER
	body.collision_mask = WORLD_LAYER
	var piece := chunk.duplicate() as MeshInstance3D
	piece.transform = Transform3D.IDENTITY
	piece.visible = true
	piece.set_instance_shader_parameter("flash", 0.0)
	piece.set_instance_shader_parameter("highlight", 0.0)
	body.add_child(piece)
	var aabb := chunk.get_aabb()
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	(shape.shape as BoxShape3D).size = aabb.size
	shape.position = aabb.get_center()
	body.add_child(shape)
	get_parent().add_child(body)
	body.global_transform = chunk.global_transform.orthonormalized()
	var jitter := Vector3(randf_range(-1, 1), randf_range(0, 1), randf_range(-1, 1)) * 0.4
	body.linear_velocity = (push + Vector3.UP * 0.8 + jitter).normalized() * speed
	body.angular_velocity = Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * 6.0

	var t := body.create_tween()
	t.tween_interval(DEBRIS_LIFETIME)
	t.tween_property(piece, "scale", Vector3.ONE * 0.01, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	t.tween_callback(body.queue_free)


# --- feedback -------------------------------------------------------------------------------

func _chips_at(info: HitInfo) -> void:
	chips.global_position = info.position + info.normal * 0.05
	chips.direction = chips.global_basis.inverse() * (info.normal + Vector3.UP * 0.6).normalized()
	chips.restart()


func _collect_surfaces(n: Node) -> void:
	for c in n.get_children():
		if c is GeometryInstance3D:
			_surfaces.append(c)
		_collect_surfaces(c)


func _play(player: AudioStreamPlayer3D, stream: AudioStream, pitch := 1.0) -> void:
	if stream == null:
		return
	player.stream = stream
	player.pitch_scale = pitch
	player.play()


func _flash() -> void:
	if _flash_tween:
		_flash_tween.kill()
	_flash_tween = create_tween()
	_flash_tween.tween_method(func(v: float) -> void:
		for s in _surfaces:
			s.set_instance_shader_parameter("flash", v), 0.7, 0.0, 0.09)


## "Impact": shove the visual away from the player and squash it slightly, then spring back.
func _nudge(away: Vector3) -> void:
	if _nudge_tween:
		_nudge_tween.kill()
	visual.position = away * 0.06
	visual.scale = Vector3(1.04, 0.95, 1.04)
	_nudge_tween = create_tween().set_parallel()
	_nudge_tween.tween_property(visual, "position", Vector3.ZERO, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_nudge_tween.tween_property(visual, "scale", Vector3.ONE, 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
