class_name LanternGift
extends Node3D
## The elder's gift at the first dusk (plans/lamps.md L8). The Lamps autoload starts it when the
## sun gets low and you have no lantern yet (a new world, or one saved before lanterns):
##   you're near the elder, out of doors: the elder walks over, holds the lantern out, hands it
##     to you and cheers;
##   you're far off (or it's already night, or you walk away): it waits glowing on the town hall
##     step, and walking up to it picks it up;
##   no village at all: it's simply yours.
## Either way a banner says so (and how to light it).

const MODEL := preload("res://models/lantern.glb")
## The elder walks over if you're within this of them.
const WALK_RANGE := 45.0
## ...stops this far in front of you, and holds it out for this long before you have it.
const STOP := 1.7
const HOLD_OUT := 1.4
## Gives up walking (and leaves it on the step) after this long, or if you get this far away.
const GIVE_UP_AFTER := 70.0
const GIVE_UP_RANGE := 70.0
## On the step: this far in front of the door; picked up within PICK_UP of it.
const STEP_OUT := 0.9
const PICK_UP := 2.0
const WARM := Color(1.0, 0.8, 0.5)

enum Step { WALK, HAND_OVER, DOORSTEP }

var _step := Step.WALK
var _elder: Villager
var _player: Node3D
var _mark: Marker3D  # where the elder walks: just in front of you
var _held: Node3D  # the lantern, in the elder's hand or on the step
var _timer := 0.0


func _ready() -> void:
	_player = get_tree().get_first_node_in_group("player") as Node3D
	_elder = _find_elder()
	if _elder == null:
		_give("You found a lantern")
		return
	var near := _flat(_elder.global_position).distance_to(_flat(_player.global_position)) < WALK_RANGE
	if near and not DayNight.is_night() and not _elder.get("_inside"):
		_walk_over()
	else:
		_leave_on_step()


func _physics_process(delta: float) -> void:
	_timer += delta
	match _step:
		Step.WALK:
			var far := _flat(_elder.global_position).distance_to(_flat(_player.global_position)) > GIVE_UP_RANGE
			if DayNight.is_night() or _timer > GIVE_UP_AFTER or far:
				_elder.set("_hurry", 1.0)
				_leave_on_step()
				return
			var away := _flat(_elder.global_position) - _flat(_player.global_position)
			var dir := away.normalized() if away.length() > 0.1 else Vector2(0, 1)
			var p := _player.global_position + Vector3(dir.x, 0, dir.y) * STOP
			_mark.global_position = p
			if _elder.state == Villager.State.TALK or away.length() < STOP + 0.6:
				_hand_over()
			elif _elder.state != Villager.State.WALK and _elder.state != Villager.State.CHEER:
				_elder.call("_walk_to", _mark)
		Step.HAND_OVER:
			_elder.script_place(_elder.global_position, _player.global_position)
			if _timer > HOLD_OUT:
				_elder.scripted = false
				_elder.set("_hurry", 1.0)
				_elder.cheer()
				_give("%s gave you a lantern" % _elder.display_name())
		Step.DOORSTEP:
			if _player.global_position.distance_to(_held.global_position) < PICK_UP:
				_give("You found a lantern on the %s step" % _elder.building.def.display_name.to_lower())


func _walk_over() -> void:
	_step = Step.WALK
	_timer = 0.0
	_mark = Marker3D.new()
	_mark.name = "ElderStop"
	add_child(_mark)
	_mark.top_level = true
	_mark.global_position = _player.global_position
	_elder.set("_hurry", 1.5)
	_elder.call("_walk_to", _mark)


func _hand_over() -> void:
	_step = Step.HAND_OVER
	_timer = 0.0
	_elder.scripted = true
	_elder.script_pose(&"ArmR", -1.35, 0.1)
	_elder.script_pose(&"Head", -0.1)
	_held = _make_lantern(1.3)
	var arm := _elder.find_child("ArmR", true, false) as Node3D
	if arm:
		arm.add_child(_held)
		_held.position = Vector3(0, -0.5, 0.06)
	else:
		_elder.add_child(_held)
		_held.position = Vector3(0.25, 1.0, 0.45)


func _leave_on_step() -> void:
	_step = Step.DOORSTEP
	if _mark:
		_mark.queue_free()
		_mark = null
	if _held:
		_held.queue_free()
	var door := _elder.building.spot("Door")
	var at := door.global_transform.origin + door.global_basis.z * STEP_OUT
	var terrain := get_tree().get_first_node_in_group("terrain") as Terrain3D
	var h: float = terrain.data.get_height(at) if terrain and terrain.data else NAN
	_held = _make_lantern(1.3)
	add_child(_held)
	_held.top_level = true
	_held.global_position = Vector3(at.x, (at.y if is_nan(h) else maxf(h, at.y)) + 0.34, at.z)
	var light := OmniLight3D.new()  # a small warm pool on the step, so it's seen from the square
	light.light_color = Lantern.LIGHT_COLOR
	light.omni_range = 4.0
	light.light_energy = 0.9
	_held.add_child(light)
	light.position = Lantern.FLAME


func _give(what: String) -> void:
	Lamps.give_lantern()
	var hud := get_tree().get_first_node_in_group("hud")
	if hud:
		hud.call("announce", what, "L to light it or put it out  ·  hold F to raise it", WARM, &"discovery")
	queue_free()


func _make_lantern(size: float) -> Node3D:
	var lantern := MODEL.instantiate() as Node3D
	lantern.scale = Vector3.ONE * size
	for m in lantern.find_children("*", "MeshInstance3D", true, false):
		var mesh := m as MeshInstance3D
		mesh.material_override = PaletteMaterial.for_mesh(mesh.mesh)
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if String(mesh.name).begins_with("Lamp"):  # the glass glows, not the iron
			mesh.set_instance_shader_parameter("glow", 0.7)
	return lantern


## The village elder: the town hall's villager (the one who speaks to the square).
func _find_elder() -> Villager:
	for b in get_tree().get_nodes_in_group("building"):
		for c in b.get_children():
			if c is Villager and (c as Villager).work == Villager.Work.ORATE and (b as Building).tier_shown > 0:
				return c
	return null


func _exit_tree() -> void:
	if _elder and is_instance_valid(_elder) and _step == Step.HAND_OVER:
		_elder.scripted = false


static func _flat(v: Vector3) -> Vector2:
	return Vector2(v.x, v.z)
