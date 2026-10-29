class_name MineSpot
extends StaticBody3D
## Something in the mine you press E at (plans/mine.md): the way out, the lift, the rail stop, a
## collapse or a flooded tunnel to look at. What it says and does are callables, so the mine
## decides both as things change (the lift's next stop, the pump not built yet).

var say: Callable
var act: Callable


static func make(size: Vector3, say_fn: Callable, act_fn := Callable()) -> MineSpot:
	var s := MineSpot.new()
	s.say = say_fn
	s.act = act_fn
	s.collision_layer = LookObject.LAYER
	s.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	shape.position = Vector3(0, size.y * 0.5, 0)
	s.add_child(shape)
	return s


func prompt() -> String:
	return say.call() if say.is_valid() else ""


func interact() -> void:
	if act.is_valid():
		act.call()


func set_highlighted(_on: bool) -> void:
	pass
