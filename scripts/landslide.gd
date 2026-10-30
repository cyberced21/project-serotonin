class_name Landslide
extends Node3D
## The landslide over the road east (plans/market.md): a fan of mud across the road with a dozen
## boulders in it. The boulders are ordinary rocks you break with any pick, set never to grow back
## (each saves as broken under its own id). Once they're all gone, the retaining wall comes up on
## the noticeboard (Projects &"retaining_wall", which needs `cleared()`); built, the mud goes, the
## wall holds the slope above the road, and the road east is open (open()).
## It places itself: on the road east nearest NEAR, its X along the road, +Z toward the uphill side.

signal changed

const BOULDER := preload("res://scenes/rock.tscn")
const MUD := preload("res://models/village/props/landslide_mud.glb")
const WALL := preload("res://models/village/props/retaining_wall.glb")
## Where the boulders sit in the fan (local XZ, m: X along the road, Z across it, uphill +) and
## how big each is: right across the road, a few spilling up the slope.
const BOULDERS := [
	[Vector2(-2.6, -2.4), 1.4], [Vector2(-0.6, -2.8), 1.2], [Vector2(1.6, -2.2), 1.5],
	[Vector2(-1.8, -0.4), 1.6], [Vector2(0.6, 0.0), 1.8], [Vector2(2.8, -0.6), 1.4],
	[Vector2(-3.4, 1.0), 1.2], [Vector2(-0.8, 1.8), 1.5], [Vector2(1.8, 1.6), 1.3],
	[Vector2(-2.2, 3.2), 1.1], [Vector2(0.4, 3.6), 1.2], [Vector2(3.2, 2.8), 1.0],
]
## About where on the road east the slide came down.
const NEAR := Vector2(300, 128)
## The wall stands this far uphill of the road's middle.
const WALL_OFFSET := 4.6

var boulders: Array[ResourceNode] = []
var _mud: Node3D
var _wall: Node3D


func _ready() -> void:
	add_to_group("landslide")
	_place()
	_mud = _prop(MUD, Vector3.ZERO)
	_mud.rotation.y = PI * 1.5  # (the mud's long side across the road)
	_mud.name = "Mud"
	for i in BOULDERS.size():
		var b := BOULDER.instantiate() as ResourceNode
		b.save_id = StringName("slide_%02d" % i)
		b.name = String(b.save_id)
		b.respawn_time = 1.0e9  # never grows back
		b.show_respawn_timer = false
		var at: Vector2 = BOULDERS[i][0]
		b.position = Vector3(at.x, 0.0, at.y)
		b.rotation.y = float(i) * 1.7
		b.scale = Vector3.ONE * float(BOULDERS[i][1])
		add_child(b)
		b.global_position.y = _ground(b.global_position) - 0.15
		b.depleted.connect(func(_n: ResourceNode) -> void: _on_broken())
		boulders.append(b)
	Projects.changed.connect(_sync)
	_sync.call_deferred()


## Every boulder broken.
func cleared() -> bool:
	for b in boulders:
		if is_instance_valid(b) and b.get("_respawn_timer") == null:  # (broken = waiting to grow back: never)
			return false
	return true


## The wall's built: the road east is open (traders can come).
func open() -> bool:
	return Projects.is_done(&"retaining_wall")


func _on_broken() -> void:
	changed.emit()
	if cleared():
		Projects.changed.emit()  # (the wall goes up on the board)


func _sync() -> void:
	var done := open()
	_mud.visible = not done
	for b in boulders:
		if is_instance_valid(b):
			b.visible = not done
	if done and _wall == null:
		_wall = _prop(WALL, Vector3(0.0, 0.0, WALL_OFFSET))
		_wall.name = "RetainingWall"
	elif not done and _wall:
		_wall.queue_free()
		_wall = null


## On the road east's laid line nearest NEAR, turned along it, +Z uphill.
func _place() -> void:
	var pts := PackedVector2Array()
	for r in WorldMap.roads():
		if r["id"] == &"east_road":
			pts = r["pts"]
	if pts.size() < 3:
		return
	var k := 0
	for i in pts.size():
		if pts[i].distance_to(NEAR) < pts[k].distance_to(NEAR):
			k = i
	var a := pts[maxi(k - 2, 0)]
	var b := pts[mini(k + 2, pts.size() - 1)]
	var along := (b - a).normalized()
	var side := Vector2(-along.y, along.x)
	var at := Vector3(pts[k].x, 0.0, pts[k].y)
	var left := at + Vector3(side.x, 0.0, side.y) * 8.0
	var right := at - Vector3(side.x, 0.0, side.y) * 8.0
	if _ground(right) > _ground(left):
		side = -side
	var z := Vector3(side.x, 0.0, side.y)
	var x := Vector3.UP.cross(z)  # (right-handed: never mirrored)
	global_transform = Transform3D(Basis(x, Vector3.UP, z).orthonormalized(), Vector3(at.x, _ground(at), at.z))


func _prop(scene: PackedScene, local: Vector3) -> Node3D:
	var p := Prop.new()
	p.model = scene
	p.snap_to_ground = true
	p.rotation.y = PI  # (the models' uphill side is their -Z)
	add_child(p)
	p.position = local
	return p


func _ground(at: Vector3) -> float:
	var terrain := get_tree().get_first_node_in_group("terrain") as Terrain3D
	var h: float = terrain.data.get_height(at) if terrain and terrain.data else NAN
	return at.y if is_nan(h) else h
