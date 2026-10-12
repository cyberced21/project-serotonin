extends CharacterBody2D
## Top-down player: walk with WASD / arrows, hold Space / E / left-click to gather.
## The node is hit on the *impact frame* of the swing, not when the button is pressed —
## lining sound + hit-stop up with the animation is what makes it feel solid.

@export var speed := 70.0
@export var reach := 24.0
@export var swing_sfx: AudioStream

@export_group("Swing timing")
@export var windup_time := 0.13
@export var strike_time := 0.05
@export var recover_time := 0.16
@export var swing_cooldown := 0.12
@export var move_slow_while_swinging := 0.3

const TOOLS := {
	&"axe": preload("res://art/axe.png"),
	&"pickaxe": preload("res://art/pickaxe.png"),
}
const REST_ANGLE := 0.35
const WINDUP_ANGLE := -1.5
const STRIKE_ANGLE := 1.35

@onready var body: Sprite2D = $Body
@onready var tool_pivot: Node2D = $ToolPivot
@onready var arm: Node2D = $ToolPivot/Arm
@onready var tool_sprite: Sprite2D = $ToolPivot/Arm/Tool
@onready var audio: AudioStreamPlayer2D = $Audio

var facing := 1.0
var _swinging := false
var _cooldown := 0.0
var _walk_t := 0.0


func _ready() -> void:
	add_to_group("player")
	arm.rotation = REST_ANGLE
	SaveGame.register(&"player", self)


func to_dict() -> Dictionary:
	return {"x": global_position.x, "y": global_position.y}


func from_dict(d: Dictionary) -> void:
	if d.has("x") and d.has("y"):
		global_position = Vector2(float(d["x"]), float(d["y"]))


func _physics_process(delta: float) -> void:
	var dir := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	velocity = dir * speed * (move_slow_while_swinging if _swinging else 1.0)
	move_and_slide()

	if dir.x != 0.0 and not _swinging:
		facing = signf(dir.x)
	body.flip_h = facing < 0.0
	tool_pivot.scale.x = facing

	# tiny walk bob (whole pixels only)
	if dir != Vector2.ZERO:
		_walk_t += delta * 12.0
		body.position.y = -8.0 - roundf(absf(sin(_walk_t)))
	else:
		_walk_t = 0.0
		body.position.y = -8.0

	_cooldown -= delta
	if Input.is_action_pressed("gather") and not _swinging and _cooldown <= 0.0:
		var target := _find_target()
		if target:
			_swing(target)


func _find_target() -> ResourceNode:
	var best: ResourceNode = null
	var best_d := reach
	for n in get_tree().get_nodes_in_group("gatherable"):
		var node := n as ResourceNode
		if node == null or not node.is_available():
			continue
		var d := node.global_position.distance_to(global_position)
		if d < best_d:
			best_d = d
			best = node
	return best


func _swing(target: ResourceNode) -> void:
	_swinging = true
	var dx := target.global_position.x - global_position.x
	if absf(dx) > 1.0:
		facing = signf(dx)
	tool_sprite.texture = TOOLS.get(target.tool_type, TOOLS[&"axe"])

	# 1. wind-up (anticipation)
	var t := create_tween()
	t.tween_property(arm, "rotation", WINDUP_ANGLE, windup_time).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	await t.finished

	# 2. strike — whoosh starts with the fast part of the motion
	if swing_sfx:
		audio.stream = swing_sfx
		audio.play()
	t = create_tween()
	t.tween_property(arm, "rotation", STRIKE_ANGLE, strike_time).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await t.finished

	# 3. impact frame
	if is_instance_valid(target) and target.is_available() \
			and target.global_position.distance_to(global_position) <= reach + 4.0:
		target.hit(global_position)
		body.scale = Vector2(1.1, 0.9)
		create_tween().tween_property(body, "scale", Vector2.ONE, 0.12)

	# 4. recover
	t = create_tween()
	t.tween_property(arm, "rotation", REST_ANGLE, recover_time).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	await t.finished
	_cooldown = swing_cooldown
	_swinging = false
