class_name HomePlans
extends StaticBody3D
## The plans for your home (plans/home.md): pinned to a post by the tent, then on the table. E
## opens the usual upgrade panel for the home (UpgradePanel takes anything with a `building`).

var building: Building


static func make(at: Transform3D, home: Building) -> HomePlans:
	var p := HomePlans.new()
	p.building = home
	p.collision_layer = LookObject.LAYER
	p.collision_mask = 0
	p.transform = at
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.7, 0.6, 0.7)
	shape.shape = box
	p.add_child(shape)
	return p


func prompt() -> String:
	return "E  Plans for your home"


func interact() -> void:
	var panel := get_tree().get_first_node_in_group("upgrade_panel") as UpgradePanel
	if panel and not panel.just_closed():
		panel.open(self)


func set_highlighted(_on: bool) -> void:
	pass
