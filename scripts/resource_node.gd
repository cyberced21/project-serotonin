class_name ResourceNode
extends StaticBody2D
## A gatherable node (tree, rock, ore vein...). Everything is tweakable from the inspector.
## To make a new resource type: right-click scenes/resource_node.tscn > New Inherited Scene,
## then set the texture, item, sounds and colors.

signal depleted(node: ResourceNode)
signal respawned(node: ResourceNode)

const PICKUP_SCENE := preload("res://scenes/pickup.tscn")
const DEFLECT_SFX := preload("res://audio/stone_hit.tres")
const DEFLECT_COLOR := Color("ff8a7a")

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
## Horizontal strip: N depletion frames followed by 1 final "stump / rubble" frame.
@export var texture: Texture2D
@export_range(2, 16) var frames := 5
@export var chip_color := Color("dea876")
@export var burst_color := Color("38804c")

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

@onready var sprite: Sprite2D = $Sprite2D
@onready var chips: CPUParticles2D = $Chips
@onready var burst: CPUParticles2D = $Burst
@onready var audio: AudioStreamPlayer2D = $Audio
@onready var break_audio: AudioStreamPlayer2D = $BreakAudio

var hits_left := 0
var _flash_tween: Tween
var _nudge_tween: Tween


func _ready() -> void:
	add_to_group("gatherable")
	sprite.texture = texture
	sprite.hframes = frames
	if texture:
		sprite.offset.y = -texture.get_height() / 2.0 + 2.0  # origin at the base, for y-sorting
	sprite.material = sprite.material.duplicate()  # per-instance flash
	chips.color = chip_color
	burst.color = burst_color
	hits_left = max_hits
	_show_stage()


func is_available() -> bool:
	return hits_left > 0


## Called by the player on the impact frame of a swing.
func hit(from: Vector2) -> void:
	if hits_left <= 0:
		return
	if Skills.level(skill) < required_level:
		_deflect(from)
		return
	hits_left -= 1
	var stress := 1.0 - float(hits_left) / max_hits  # 0 -> 1 as it depletes
	var away := signf(global_position.x - from.x)
	if away == 0.0:
		away = 1.0

	_play(audio, hit_sfx, 1.0 + stress * stress_pitch)
	_show_stage()
	_flash()
	_nudge(away)
	chips.position = Vector2(-away * 5.0, -8.0)
	chips.direction = Vector2(-away, -0.8)
	chips.restart()
	Juice.shake(shake_hit + stress * 1.5)
	Juice.hitstop(hitstop_hit)
	_award_xp(xp_per_hit)

	if hits_left == 0:
		_break(away)


## Under-levelled: the tool bounces off — clank, small nudge, no damage, no XP.
func _deflect(from: Vector2) -> void:
	var away := signf(global_position.x - from.x)
	if away == 0.0:
		away = 1.0
	_play(audio, DEFLECT_SFX, 1.8)
	_nudge(away)
	Juice.shake(0.5)
	PopupText.spawn(get_parent(), _popup_pos(), "%s %d" % [Skills.display_name(skill), required_level], DEFLECT_COLOR)


func _award_xp(amount: int, big := false) -> void:
	if amount <= 0:
		return
	var gained := Skills.add_xp(skill, amount)
	if gained > 0:
		PopupText.spawn(get_parent(), _popup_pos() + Vector2(randf_range(-4, 4), -6.0 if big else 0.0),
			"+%d" % gained, Skills.color(skill), 10 if big else 8, 0.08 if big else 0.0)


func _popup_pos() -> Vector2:
	return global_position + Vector2(0, -(texture.get_height() if texture else 16) - 2)


func _break(away: float) -> void:
	_award_xp(xp_on_break, true)
	_play(break_audio, break_sfx)
	sprite.frame = frames - 1
	burst.restart()
	Juice.shake(shake_break)
	Juice.hitstop(hitstop_break)
	_spawn_drops(away)
	depleted.emit(self)

	await get_tree().create_timer(respawn_time).timeout
	hits_left = max_hits
	_show_stage()
	sprite.scale = Vector2(0.4, 0.4)
	create_tween().tween_property(sprite, "scale", Vector2.ONE, 0.35) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	respawned.emit(self)


func _spawn_drops(away: float) -> void:
	var count := randi_range(drops_min, maxi(drops_min, drops_max))
	for i in count:
		var p := PICKUP_SCENE.instantiate()
		p.item = item
		p.icon = item_icon
		get_parent().add_child(p)
		var start := global_position + Vector2(0, -6)
		var land := global_position + Vector2(randf_range(-18, 18) + away * 10.0, randf_range(4, 14))
		p.launch(start, land, i * 0.04)


func _show_stage() -> void:
	var stress := 1.0 - float(hits_left) / max_hits
	sprite.frame = mini(ceili(stress * (frames - 1)), frames - 2) if hits_left > 0 else frames - 1


func _play(player: AudioStreamPlayer2D, stream: AudioStream, pitch := 1.0) -> void:
	if stream == null:
		return
	player.stream = stream
	player.pitch_scale = pitch
	player.play()


func _flash() -> void:
	if _flash_tween:
		_flash_tween.kill()
	var mat := sprite.material as ShaderMaterial
	mat.set_shader_parameter("flash", 1.0)
	_flash_tween = create_tween()
	_flash_tween.tween_method(func(v: float) -> void: mat.set_shader_parameter("flash", v), 1.0, 0.0, 0.09)


## Pixel-friendly "impact": push the sprite away and squash it slightly, then spring back.
func _nudge(away: float) -> void:
	if _nudge_tween:
		_nudge_tween.kill()
	sprite.position.x = away * 2.0
	sprite.scale = Vector2(1.1, 0.92)
	_nudge_tween = create_tween().set_parallel()
	_nudge_tween.tween_property(sprite, "position:x", 0.0, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_nudge_tween.tween_property(sprite, "scale", Vector2.ONE, 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
