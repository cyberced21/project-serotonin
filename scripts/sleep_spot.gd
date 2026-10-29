class_name SleepSpot
extends StaticBody3D
## Your bed (plans/home.md): E sleeps till morning when it's late enough (Home.can_sleep); before
## that the prompt says why not.

var home: Home


static func make(at: Transform3D, h: Home) -> SleepSpot:
	var s := SleepSpot.new()
	s.home = h
	s.collision_layer = LookObject.LAYER
	s.collision_mask = 0
	s.transform = at
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.9, 0.5, 1.8)
	shape.shape = box
	shape.position = Vector3(0, 0, 0.9)  # along the mattress from its foot
	s.add_child(shape)
	return s


func prompt() -> String:
	return "E  Sleep till morning" if home.can_sleep() else home.not_yet()


func interact() -> void:
	home.sleep()


func set_highlighted(_on: bool) -> void:
	pass
