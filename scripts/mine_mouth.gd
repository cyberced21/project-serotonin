class_name MineMouth
extends Node3D
## The way into the mine (plans/mine.md): a timber frame in the quarry floor's wall, boarded up
## until the mine_shoring project is built, then open, a lamp either side and dark beyond.
## It finds the wall itself: it stands where the ground first rises a storey, walking out from
## the pit's middle at `angle` (degrees round the pit, as QuarryDressing counts them).

signal opened

const FRAME := preload("res://models/mine/frame_square.glb")
const BEAM := preload("res://models/mine/beam.glb")
const LAMP := preload("res://models/mine/lamp_hanging.glb")
const RUBBLE := preload("res://models/mine/rubble_pile.glb")
const PROJECT := &"mine_shoring"

@export var angle := 135.0

## The frame's height, and the beam model's length (the passage's timbers are stretched to fit).
const FRAME_HEIGHT := 2.85
const BEAM_LENGTH := 1.9

var is_open := false
var _depth := 1.0  # how far the timbered passage runs back to the rock
var _boards: Node3D
var _lamps: Array[Node3D] = []


func _ready() -> void:
	add_to_group("mine_mouth")
	_settle()
	_build()
	Projects.changed.connect(_refresh)
	_refresh()


## Puts the mouth at the foot of the floor's wall, facing the pit's middle: the frame stands
## out where the slope starts (clear of it, the wall leans back), and a timbered passage runs from
## it back into the rock (`_depth`), so the frame isn't half sunk in the wall.
func _settle() -> void:
	var terrain := get_tree().get_first_node_in_group("terrain") as Terrain3D
	var a := deg_to_rad(angle)
	var dir := Vector3(cos(a), 0.0, sin(a))
	var c := Vector3(WorldMap.QUARRY_CENTER.x, 0.0, WorldMap.QUARRY_CENTER.y)
	var floor_y := WorldMap.QUARRY_RIM_HEIGHT - WorldMap.QUARRY_LEVEL_DROP * WorldMap.QUARRY_WALLS.size()
	var r := WorldMap.QUARRY_WALLS[-1] - 4.0
	var foot := r
	var top := r
	if terrain and terrain.data:
		floor_y = terrain.data.get_height(c + dir * r)
		foot = -1.0
		while r < WorldMap.QUARRY_WALLS[-1] + 6.0:
			var h: float = terrain.data.get_height(c + dir * r)
			if not is_nan(h) and foot < 0.0 and h > floor_y + 0.15:
				foot = r  # where the wall starts to rise
			if not is_nan(h) and h > floor_y + FRAME_HEIGHT + 0.3:
				break  # high enough to roof the passage over
			r += 0.1
		top = r
		foot = top if foot < 0.0 else foot
	_depth = clampf(top - foot + 0.6, 0.6, 4.0)
	global_position = c + dir * (foot - 0.15) + Vector3.UP * floor_y
	look_at(c + Vector3.UP * floor_y, Vector3.UP)  # -Z toward the middle
	rotate_object_local(Vector3.UP, PI)  # its front (+Z here) out into the pit


func _build() -> void:
	var dark := MeshInstance3D.new()  # the tunnel going back into the rock
	var box := BoxMesh.new()
	box.size = Vector3(3.0, 2.85, _depth + 3.0)
	var black := StandardMaterial3D.new()
	black.albedo_color = Color(0.02, 0.018, 0.016)
	black.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	black.cull_mode = BaseMaterial3D.CULL_FRONT  # seen from inside: the far walls only
	box.material = black
	dark.mesh = box
	dark.position = Vector3(0, 1.42, -(_depth + 3.0) / 2.0 - 0.1)
	add_child(dark)
	var mouth := MeshInstance3D.new()  # (the quarry's wall stands in front of that box: a dark
	var quad := QuadMesh.new()  # face across the frame reads as the way in going back)
	quad.size = Vector2(2.9, 2.8)
	var shade := StandardMaterial3D.new()
	shade.albedo_color = Color(0.03, 0.025, 0.02)
	shade.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	quad.material = shade
	mouth.mesh = quad
	mouth.position = Vector3(0, 1.4, -0.05)
	add_child(mouth)
	_prop(FRAME, Vector3.ZERO, 0.0, false, true)
	# the passage back to the rock: timber sides and a roof of beams across
	var along := _depth / BEAM_LENGTH
	for side in [-1.0, 1.0]:
		for i in 6:
			var b := _prop(BEAM, Vector3(side * 1.45, 0.2 + i * 0.46, -_depth / 2.0), 90.0, true, true)
			b.scale = Vector3(along, 1.0, 1.0)
	for i in ceili(_depth / 0.4):
		var b := _prop(BEAM, Vector3(0.0, FRAME_HEIGHT, -0.25 - i * 0.4), 0.0, true, false)
		b.scale = Vector3(1.6, 1.0, 1.0)
	for side in [-1.0, 1.0]:
		_prop(RUBBLE, Vector3(side * 2.3, 0.0, 0.5), side * 40.0, false, false)
	_boards = Node3D.new()
	_boards.name = "Boards"
	add_child(_boards)
	for i in 4:  # planks nailed across, none quite level
		var b := _prop(BEAM, Vector3(0.0, 0.55 + i * 0.62, 0.18), 0.0, true, false, _boards)
		b.scale = Vector3(1.55, 1.0, 1.0)
		b.rotation.z = [0.06, -0.09, 0.04, -0.05][i]
	for side in [-1.0, 1.0]:
		var lamp := _prop(LAMP, Vector3(side * 1.25, 2.75, 0.35), 0.0, false, true)
		_lamps.append(lamp)
	var spot := MineSpot.make(Vector3(2.8, 2.8, 0.6), _prompt, _go_in)
	spot.position = Vector3(0.0, 0.0, 0.5)
	add_child(spot)


func _prompt() -> String:
	if is_open:
		return "E  Go down into the mine"
	return "Boarded up. Shore up the old mine first (the noticeboard)."


func _go_in() -> void:
	var mine := get_tree().get_first_node_in_group("mine") as Mine
	if is_open and mine:
		mine.enter()


func _prop(model: PackedScene, at: Vector3, turn_deg: float, own: bool, collide: bool, parent: Node = self) -> Prop:
	var p := Prop.new()
	p.model = model
	p.own_materials = own
	p.collide = collide
	p.position = at
	p.rotation.y = deg_to_rad(turn_deg)
	parent.add_child(p)
	return p


func _refresh() -> void:
	var was := is_open
	is_open = Projects.is_done(PROJECT)
	_boards.visible = not is_open
	for c in _boards.find_children("*", "CollisionShape3D", true, false):
		(c as CollisionShape3D).disabled = is_open
	for lamp in _lamps:
		lamp.visible = is_open
	if is_open and not was:
		opened.emit()


## Where you stand to go in (or come out): just in front of the frame.
func doorstep() -> Vector3:
	return global_transform * Vector3(0.0, 0.0, 1.6)
