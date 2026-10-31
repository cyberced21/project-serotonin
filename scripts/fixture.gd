class_name Fixture
extends Node3D
## One of the village's fixtures (plans/world-pass.md, phase 5): a barn, a store, the chapel, an
## empty cottage... built from the kit like the houses (tools/blender/kit_fixtures.py) but with no
## villager and no tiers of its own. Its model's T1_* pieces are how you find it; T2_* (if any)
## how it is once its noticeboard `project` is done, swapped in with a little pop when you pay.
## Pieces collide as Building's do (kit pieces exactly, the rest as hulls); kit door leaves stand
## open in a walk-in one (doors_open) and shut, solid, in one you can't go into. Seat* markers are
## seats anyone may take ("seat" group, kind &"pew"); *Smoke* empties smoke while shown.
## Pieces named *Wheel* (the watermill's) turn about their X while shown, once it's put right (or
## always, with no project). `variant` > 0 shows that state whatever the project (the orchard's
## trees: T1 an apple, T2 a pear). It sits on the ground where it stands.

const WORLD_LAYER := 1
const POP_TIME := 0.5

@export var model: PackedScene
## The project that restores it (Projects.SPOTS), or none.
@export var project: StringName = &""
## Walk-in: its kit doors stand open.
@export var doors_open := true
## Always show this state (0: by the project).
@export var variant := 0
## How fast its wheels turn (radians a second).
@export var wheel_speed := 0.9

var _states: Dictionary[int, Node3D] = {}
var _bodies: Dictionary[int, StaticBody3D] = {}
var _shown := 0
var _wheels: Dictionary[int, Array] = {}  # state -> its Wheel pieces


func _ready() -> void:
	add_to_group("fixture")
	_build()
	_settle.call_deferred()
	_show(_wanted(), false)
	Projects.changed.connect(func() -> void: _show(_wanted(), false))
	Projects.completed.connect(func(id: StringName) -> void:
		if id == project:
			_show(2, true))


## The state on show: 2 restored, 1 as found.
func state() -> int:
	return _shown


## Half the diagonal of its biggest state's footprint, for keeping scenery clear of it.
func footprint_radius() -> float:
	var r := 1.0
	for t in _states:
		for m in _states[t].get_children():
			if m is MeshInstance3D:
				var box := (m as MeshInstance3D).transform * (m as MeshInstance3D).get_aabb()
				for corner in [box.position, box.end]:
					r = maxf(r, Vector2(corner.x, corner.z).length())
	return r


func _wanted() -> int:
	if variant > 0:
		return variant
	return 2 if project != &"" and _states.has(2) and Projects.is_done(project) else 1


func _process(delta: float) -> void:
	if not _wheels.has(_shown) or (project != &"" and not Projects.is_done(project)):
		return
	for w: MeshInstance3D in _wheels[_shown]:
		w.rotate_object_local(Vector3.RIGHT, wheel_speed * delta)


## Onto the ground below its middle (the village's flat is level; out in the yards it may not be).
func _settle() -> void:
	var terrain := get_tree().get_first_node_in_group("terrain") as Terrain3D
	if terrain and terrain.data:
		var h: float = terrain.data.get_height(global_position)
		if not is_nan(h):
			global_position.y = h


func _build() -> void:
	var inst := model.instantiate()
	var swung: Array = []  # [state, the leaf's box shut, the turn that opened it] for its glass
	for n in inst.find_children("*", "Node3D", true, false):
		var t := Building._tier_of(n.name)
		if t == 0:
			continue
		if not _states.has(t):
			var group := Node3D.new()
			group.name = "State%d" % t
			add_child(group)
			_states[t] = group
			var body := StaticBody3D.new()
			body.name = "State%dBody" % t
			body.collision_layer = WORLD_LAYER
			body.collision_mask = 0
			add_child(body)
			_bodies[t] = body
		var xform := Building._model_transform(n, inst)
		if n is MeshInstance3D:
			var m := n as MeshInstance3D
			m.get_parent().remove_child(m)
			m.owner = null
			for c in m.get_children():
				m.remove_child(c)
			_states[t].add_child(m)
			var kit := Building._is_kit_piece(m)
			if not kit:
				m.material_override = PaletteMaterial.for_mesh(m.mesh)
			var piece := String(m.name).substr(3)
			var door := kit and piece.begins_with("KitDoor") and not piece.begins_with("KitDoorFrame")
			if door and doors_open:  # swung open about its hinge (its origin), no collision
				var shut := xform
				xform = xform * Transform3D(Basis(Vector3.UP, Building.DOOR_OPEN_ANGLE), Vector3.ZERO)
				swung.append([t, (shut * m.get_aabb()).grow(0.02), xform * shut.affine_inverse()])
			m.transform = xform
			Building._mark_night_glow(m)
			if piece.begins_with("Wheel"):
				if not _wheels.has(t):
					_wheels[t] = []
				_wheels[t].append(m)
				continue  # (no collision: it turns)
			if door and doors_open:
				continue
			var aabb := m.get_aabb()
			if aabb.size.x * aabb.size.y * aabb.size.z >= Building.MIN_COLLIDER_VOLUME:
				var shape := CollisionShape3D.new()
				shape.shape = m.mesh.create_trimesh_shape() if kit and not piece.begins_with("KitStair") \
						else m.mesh.create_convex_shape(true, false)
				shape.transform = xform
				_bodies[t].add_child(shape)
		elif String(n.name).to_lower().contains("smoke"):
			var smoke := Building._make_smoke()
			_states[t].add_child(smoke)
			smoke.transform = Transform3D(Basis.IDENTITY, xform.origin)
		else:
			var mark := Marker3D.new()
			mark.name = String(n.name).substr(3)
			_states[t].add_child(mark)
			mark.transform = xform
			if String(mark.name).begins_with("Seat"):
				mark.add_to_group("seat")
				mark.set_meta(&"kind", &"pew")
	inst.free()
	for s in swung:  # a kit door's little window (split off with the glass) goes with its leaf
		for g in _states[s[0]].get_children():
			if g is MeshInstance3D and String(g.name).to_lower().contains("windowglass") \
					and (s[1] as AABB).has_point((g.transform * (g as MeshInstance3D).get_aabb()).get_center()):
				g.transform = (s[2] as Transform3D) * g.transform
	for t: int in _states:  # the pieces that never change drawn as one mesh (StaticMerge)
		var turning: Array = _wheels.get(t, [])
		StaticMerge.merge(_states[t], "%s:%d:%s" % [model.resource_path, t, doors_open],
			func(m: MeshInstance3D) -> bool: return m.is_in_group("night_glow") or turning.has(m))


func _show(t: int, pop: bool) -> void:
	if t == _shown or not _states.has(t):
		return
	_shown = t
	for k in _states:
		_states[k].visible = k == t
		for s in _bodies[k].get_children():
			(s as CollisionShape3D).disabled = k != t
	if pop:
		var g := _states[t]
		g.scale = Vector3(1.0, 0.01, 1.0)
		create_tween().tween_property(g, "scale", Vector3.ONE, POP_TIME).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
