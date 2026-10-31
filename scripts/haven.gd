class_name Haven
extends Node3D
## The hidden haven deep in the Pinewood (plans/world-pass.md, phase 7): a secret glade behind a
## thicket, a spring-fed pool, a mossy ruin, old trees, a log to sit on (its dressing is in the
## scene). It keeps the forest's own trees and scenery out ("keep_clear", `radius`), and the first
## time you find it a pressed-flower trophy lies by the pool (TrophyFind, kind &"flower"): once per
## world, remembered here.

@export var radius := 18.0
## Its spring pool (a WaterBody): up here, its water sits at the glade's height (the terrain
## generator digs it there), so it's lifted to match before it sets itself up.
@export var pool_path := NodePath("HavenPool")
## Where the flower lies, in the haven's frame.
@export var flower_at := Vector3(2.5, 0.0, -1.0)

var _found := false
var _flower: TrophyFind


func _ready() -> void:
	add_to_group("keep_clear")
	_lift_pool()
	SaveGame.register(&"haven", self)
	_put_flower.call_deferred()


func _lift_pool() -> void:
	var pool := get_node_or_null(pool_path) as Node3D
	var terrain := get_tree().get_first_node_in_group("terrain") as Terrain3D
	if pool == null or terrain == null or terrain.data == null:
		return
	var top: float = terrain.data.get_height(global_position)  # (the glade's level middle)
	if is_nan(top):
		return
	pool.global_position.y = top
	pool.set("surface_height", top - 0.12)
	var surface := pool.get_node_or_null("Surface") as Node3D
	if surface:
		surface.position.y = -0.12


## The circle it keeps clear, (x, z, radius).
func keep_clear() -> Vector3:
	return Vector3(global_position.x, global_position.z, radius)


func _put_flower() -> void:
	if _found or _flower:
		return
	var at := global_transform * flower_at
	var terrain := get_tree().get_first_node_in_group("terrain") as Terrain3D
	if terrain and terrain.data:
		var h: float = terrain.data.get_height(at)
		if not is_nan(h):
			at.y = h
	_flower = TrophyFind.make(at, &"flower")
	_flower.picked.connect(func() -> void:
		_found = true
		_flower = null
		SaveGame.mark_dirty())
	get_tree().current_scene.add_child.call_deferred(_flower)


func to_dict() -> Dictionary:
	return {"found": _found}


func from_dict(d: Dictionary) -> void:
	_found = bool(d.get("found", false))
	if _found and _flower:
		_flower.queue_free()
		_flower = null
