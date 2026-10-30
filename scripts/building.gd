class_name Building
extends Node3D
## A village building: a view of Village's tier for its BuildingDef. Shows that tier's pieces of
## the def's model (meshes named T1_*, T2_*, T3_* — see tools/blender/make_village.py), with
## collision, and when the tier changes plays the staged upgrade:
##   1. the old pieces squash and drop into a cloud of dust, top first
##   2. the new pieces pop up out of the ground one by one, bottom first, with a rising "tok"
##   3. a settle bounce, a burst, the tier's name, and the villager cheers (upgraded signal)
## Children: Spots (Marker3Ds the villager walks between — see Villager) and the Villager.
## Empties in the model named *Smoke* get chimney smoke while their tier is shown.
## With unlock_hall_tier set, the building (and its villager) isn't there at all until the town
## hall reaches that tier; then it builds itself piece by piece, like an upgrade.

signal upgraded(tier: int)

const TOK_SFX := preload("res://audio/ui/tok.wav")
const THUD_SFX := preload("res://audio/wood_break.tres")
const WORLD_LAYER := 1
## Pieces smaller than this (m³ of bounding box) get no collision: flowers, handles, notices.
const MIN_COLLIDER_VOLUME := 0.004
const MAX_TOKS := 14
const POPUP_COLOR := Color("ffd27a")
const CRYSTAL_GLOW := Color(0.7, 0.5, 1.0)
## Seconds for the windows to light up or go dark.
const WINDOW_FADE := 1.2
## A kit door leaf swings this far (radians, about its hinge) to stand open, over DOOR_SWING s.
const DOOR_OPEN_ANGLE := -1.7
const DOOR_SWING := 0.9
## How high a room reaches above its floor (two storeys and the roof space).
const ROOM_HEIGHT := 7.5

@export var def: BuildingDef
## Builds itself when the town hall reaches this tier (0 = always there).
@export var unlock_hall_tier := 0
@export_group("Upgrade feel")
## Seconds the old tier takes to collapse (all pieces), and the new one to build up.
@export var collapse_time := 0.45
@export var build_time := 1.3
## How long each piece's pop takes.
@export var piece_pop := 0.28
@export var shake_collapse := 0.8
@export var shake_done := 1.2

var tier_shown := 0
var _tiers: Dictionary[int, Node3D] = {}
var _bodies: Dictionary[int, StaticBody3D] = {}
var _smoke: Dictionary[int, Array] = {}
var _homes: Dictionary[Node3D, Transform3D] = {}  # every piece's resting transform
var _toks: Array[AudioStreamPlayer3D] = []
var _next_tok := 0
var _thud: AudioStreamPlayer3D
var _dust: CPUParticles3D
var _confetti: CPUParticles3D
var _run := 0  # bumped on every upgrade, so an interrupted animation stops
var _heading := 0  # the tier being shown, or being built (mid-animation)
## Window glass, and how lit it is (0..1): lit while the villager is home and awake after dark
## (Villager.lights_on()), fading on and off.
var _windows: Array[MeshInstance3D] = []
var _lit := 0.0
var _lit_shown := -1.0
## Walk-in interiors (plans/home.md): each tier's room (its kit floor, in the building's frame),
## its door leaves (swung open by day, shut while its villager sleeps) and its look-at objects.
var _rooms: Dictionary[int, AABB] = {}
var _doors: Dictionary[int, Array] = {}
var _door_shapes: Dictionary[MeshInstance3D, CollisionShape3D] = {}
var _looks: Dictionary[int, Array] = {}
var _door_open := 1.0  # 0 shut .. 1 open
## Add-ons (plans/home.md, AddonDef): each one's pieces in a node of their own, with their own
## collision, shown while it's built in its slot and the slot is open.
var _addon_nodes: Dictionary[StringName, Node3D] = {}
var _addon_bodies: Dictionary[StringName, StaticBody3D] = {}
var _upgrading := false


func _ready() -> void:
	assert(def, "Building needs a BuildingDef")
	add_to_group("building")
	Village.register_building(def)
	var bench := spot("Bench")
	if bench:  # anyone may sit there at dusk; its villager first (Villager._claim_seat)
		bench.add_to_group("seat")
		bench.set_meta(&"kind", &"bench")
		bench.set_meta(&"home", self)
	_build_tiers()
	_build_effects()
	if not _rooms.is_empty():
		add_to_group("interior")  # (Acoustics: indoors while has_player())
	_show_tier(Village.tier(def.id) if is_unlocked() else 0)
	Village.tier_changed.connect(_on_tier_changed)
	Village.addon_changed.connect(_on_addon_changed)
	_show_addons(false)


func _process(delta: float) -> void:
	if not _door_shapes.is_empty():
		_swing_doors(delta)
	if _windows.is_empty():
		return
	_lit = move_toward(_lit, 1.0 if _windows_on() else 0.0, delta / WINDOW_FADE)
	var glow := _lit * DayNightSky.glow_level
	if absf(glow - _lit_shown) > 0.005:
		_lit_shown = glow
		for w in _windows:
			w.set_instance_shader_parameter("glow", glow)


## Whether the windows should be lit: its villager is home and up.
func _windows_on() -> bool:
	var v := get_node_or_null("Villager")
	return v != null and v.call("lights_on")


## The markers of tier `t` (empties in the model other than smoke: Tavern's seats and so on).
func marks(t: int) -> Array[Marker3D]:
	var out: Array[Marker3D] = []
	if _tiers.has(t):
		for c in _tiers[t].get_children():
			if c is Marker3D:
				out.append(c)
	return out


## The tier on show's marker named `mark_name` (a Bed, a Hearth...), or null.
func mark(mark_name: String) -> Marker3D:
	for m in marks(tier_shown):
		if m.name == mark_name:
			return m
	return null


## Where its villager sleeps, in the tier on show (a walk-in house), or null.
func bed() -> Marker3D:
	return mark("Bed")


## The player is in the room of the tier on show (Acoustics; Tavern has its own rooms).
func has_player() -> bool:
	if not _rooms.has(tier_shown):
		return false
	var player := get_tree().get_first_node_in_group("player") as Node3D
	return player != null and inside(player.global_position)


## `p` (world) is within the room of the tier on show.
func inside(p: Vector3) -> bool:
	return _rooms.has(tier_shown) and _rooms[tier_shown].has_point(global_transform.affine_inverse() * p)


## The doors stand open unless its villager is asleep inside (Villager.door_shut).
func _doors_shut() -> bool:
	var v := get_node_or_null("Villager")
	return v != null and v.has_method("door_shut") and v.call("door_shut")


func _swing_doors(delta: float) -> void:
	_door_open = move_toward(_door_open, 0.0 if _doors_shut() else 1.0, delta / DOOR_SWING)
	var eased := smoothstep(0.0, 1.0, _door_open)
	for t in _doors:
		for d: MeshInstance3D in _doors[t]:
			if not _upgrading:
				d.transform = _homes[d] * Transform3D(Basis(Vector3.UP, DOOR_OPEN_ANGLE * eased), Vector3.ZERO)
			_door_shapes[d].set_deferred("disabled", t != tier_shown or _door_open > 0.05)


## Whether its windows are lit now (0..1, before the night's own fade-in).
func windows_lit() -> float:
	return _lit


func is_unlocked() -> bool:
	return unlock_hall_tier <= 0 or Village.tier(Village.TOWN_HALL) >= unlock_hall_tier


## The marker the villager uses for `spot` (Door, Bench, Work1..3), or null.
func spot(spot_name: String) -> Marker3D:
	return get_node_or_null("Spots/" + spot_name) as Marker3D


## The work spot for the current tier (Work3 at tier 3 if there is one, else the highest below).
func work_spot() -> Marker3D:
	for t in range(tier_shown, 0, -1):
		var m := spot("Work%d" % t)
		if m:
			return m
	return spot("Door")


# --- model ----------------------------------------------------------------------------------

## Whether a mesh is a piece of the Medieval Village kit (named TN_Kit*, with its own material).
static func _is_kit_piece(m: MeshInstance3D) -> bool:
	return String(m.name).substr(3).begins_with("Kit") and m.mesh.get_surface_count() > 0 \
			and m.mesh.surface_get_material(0) != null


## Sorts the model's meshes into one node per tier (by the TN_ name prefix), each with its own
## static body of convex shapes (exact ones for kit pieces), and finds the smoke empties.
func _build_tiers() -> void:
	var inst := def.model.instantiate()
	for t in range(1, def.max_tier() + 1):
		var group := Node3D.new()
		group.name = "Tier%d" % t
		group.visible = false
		add_child(group)
		_tiers[t] = group
		var body := StaticBody3D.new()
		body.name = "Tier%dBody" % t
		body.collision_layer = WORLD_LAYER
		body.collision_mask = 0
		add_child(body)
		_bodies[t] = body
		_smoke[t] = []

	for n in inst.find_children("*", "Node3D", true, false):
		if String(n.name).begins_with("AO-"):
			_add_addon_piece(n, inst)
			continue
		var t := _tier_of(n.name)
		if t == 0 or not _tiers.has(t):
			continue
		var xform := _model_transform(n, inst)
		if n is MeshInstance3D:
			var m := n as MeshInstance3D
			m.get_parent().remove_child(m)
			m.owner = null
			for c in m.get_children():  # glTF children are separate pieces, found on their own
				m.remove_child(c)
			_tiers[t].add_child(m)
			m.transform = xform
			var kit := _is_kit_piece(m)
			if not kit:  # kit pieces (tools/blender/kit_buildings.py) keep their own textured materials
				m.material_override = PaletteMaterial.for_mesh(m.mesh)  # (weathered stonework: the rock material)
			_homes[m] = xform
			var piece := String(m.name).substr(3)
			if kit and piece.begins_with("KitFloor"):
				var floor_box := xform * m.get_aabb()
				floor_box = AABB(Vector3(floor_box.position.x, floor_box.position.y - 0.5, floor_box.position.z),
						Vector3(floor_box.size.x, ROOM_HEIGHT, floor_box.size.z))
				_rooms[t] = _rooms[t].merge(floor_box) if _rooms.has(t) else floor_box
			if kit and piece.begins_with("KitDoor") and not piece.begins_with("KitDoorFrame"):
				_add_door(t, m)
				continue
			_mark_night_glow(m)
			if String(m.name).to_lower().contains("windowglass"):  # lit by who's home, not the sky
				m.remove_from_group("night_glow")
				_windows.append(m)
			var aabb := m.get_aabb()
			if aabb.size.x * aabb.size.y * aabb.size.z >= MIN_COLLIDER_VOLUME:
				var shape := CollisionShape3D.new()
				# a kit wall's hull would close its doorway and windows: kit pieces collide as they are,
				# but a stair's hull, a smooth ramp, is what you walk up (its steps are too tall to)
				shape.shape = m.mesh.create_trimesh_shape() if kit and not piece.begins_with("KitStair") \
						else m.mesh.create_convex_shape(true, false)  # simplify=true takes seconds per building
				shape.transform = xform
				_bodies[t].add_child(shape)
		elif n.name.to_lower().contains("smoke"):
			var smoke := _make_smoke()
			_tiers[t].add_child(smoke)
			smoke.transform = Transform3D(Basis.IDENTITY, xform.origin)
			_smoke[t].append(smoke)
		else:  # any other empty: a marker shown with its tier (the tavern's seats: Tavern)
			var mark := Marker3D.new()
			mark.name = String(n.name).substr(3)  # (without the TN_)
			_tiers[t].add_child(mark)
			mark.transform = xform
			_use_mark(t, mark)
	inst.free()
	_hang_door_glass()


## A kit door's little window is split off with the rest of the glass (it's lit at night): hung
## from its door, it swings open with it instead of staying in the doorway.
func _hang_door_glass() -> void:
	for t in _doors:
		for d: MeshInstance3D in _doors[t]:
			var leaf := (d.transform * d.get_aabb()).grow(0.02)
			for g in _windows:
				if g.get_parent() != _tiers[t] or not leaf.has_point((g.transform * g.get_aabb()).get_center()):
					continue
				var local := d.transform.affine_inverse() * g.transform
				_tiers[t].remove_child(g)
				d.add_child(g)
				g.transform = local
				_homes[g] = local


## A piece of an add-on ("AO-<id>_..."): into that add-on's node (a mesh, with collision) or a
## marker in it (TerraceSeat*/PorchSeat* seats; the rest found by name, addon_mark()).
func _add_addon_piece(n: Node, inst: Node) -> void:
	var id := StringName(String(n.name).substr(3).get_slice("_", 0))
	if not _addon_nodes.has(id):
		var group := Node3D.new()
		group.name = "Addon_%s" % id
		group.visible = false
		add_child(group)
		_addon_nodes[id] = group
		var body := StaticBody3D.new()
		body.collision_layer = WORLD_LAYER
		body.collision_mask = 0
		add_child(body)
		_addon_bodies[id] = body
	var xform := _model_transform(n, inst)
	if n is MeshInstance3D:
		var m := n as MeshInstance3D
		m.get_parent().remove_child(m)
		m.owner = null
		for c in m.get_children():
			m.remove_child(c)
		_addon_nodes[id].add_child(m)
		m.transform = xform
		if m.mesh.get_surface_count() > 0 and m.mesh.surface_get_material(0) == null:
			m.material_override = PaletteMaterial.for_mesh(m.mesh)
		_homes[m] = xform
		_mark_night_glow(m)
		var aabb := m.get_aabb()
		if aabb.size.x * aabb.size.y * aabb.size.z >= MIN_COLLIDER_VOLUME:
			var shape := CollisionShape3D.new()
			shape.shape = m.mesh.create_convex_shape(true, false)
			shape.transform = xform
			shape.disabled = true
			_addon_bodies[id].add_child(shape)
	elif n.name.to_lower().contains("smoke"):
		var smoke := _make_smoke()
		_addon_nodes[id].add_child(smoke)
		smoke.transform = Transform3D(Basis.IDENTITY, xform.origin)
	else:
		var mark := Marker3D.new()
		mark.name = String(n.name).substr(3).get_slice("_", 1)
		_addon_nodes[id].add_child(mark)
		mark.transform = xform
		if String(mark.name).begins_with("Stage"):  # (the tavern's bigger stage: a second musician)
			mark.add_to_group("stage")
		for kind in [&"terrace", &"porch", &"tavern", &"snug"]:  # (the beer garden, the fireside snug)
			if String(mark.name).to_lower().begins_with(String(kind) + "seat"):
				mark.add_to_group("seat")
				mark.set_meta(&"kind", kind)
				mark.set_meta(&"home", self)


## The marker `mark_name` in whichever built add-on has one (a swing seat, a harvest), or null.
func addon_mark(mark_name: String) -> Marker3D:
	for id in _addon_nodes:
		if _addon_nodes[id].visible:
			var m := _addon_nodes[id].get_node_or_null(mark_name) as Marker3D
			if m:
				return m
	return null


## Shows the built add-ons (in open slots), hides the rest; `pop` springs a new one up.
func _show_addons(pop: bool) -> void:
	for id in _addon_nodes:
		var a := def.get_addon(id)
		var on: bool = a != null and tier_shown > 0 and Village.slot_open(def.id, a.slot) and Village.addon(def.id, a.slot) == id
		var group := _addon_nodes[id]
		var was := group.visible
		group.visible = on
		for c in _addon_bodies[id].get_children():
			(c as CollisionShape3D).set_deferred("disabled", not on)
		if on and not was and pop:
			for c in group.get_children():
				var p := c as MeshInstance3D
				if p and _homes.has(p):
					p.scale = Vector3.ONE * 0.001
					p.create_tween().tween_property(p, "scale", _homes[p].basis.get_scale(), piece_pop * 1.4) \
						.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			_play(_thud, THUD_SFX, 1.1)


func _on_addon_changed(id: StringName, _slot: int, _addon: StringName) -> void:
	if id == def.id:
		_show_addons(true)


## A door leaf (hinged at its origin): it gets its own collision, on only while it's shut.
func _add_door(t: int, m: MeshInstance3D) -> void:
	if not _doors.has(t):
		_doors[t] = []
	_doors[t].append(m)
	var body := StaticBody3D.new()
	body.collision_layer = WORLD_LAYER
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	shape.shape = m.mesh.create_trimesh_shape()
	shape.disabled = true
	body.add_child(shape)
	m.add_child(body)
	_door_shapes[m] = shape


## What a walk-in house's markers are for: Seat* a chair anyone may sit on (its villager's first),
## PorchSeat* a seat on your porch where a villager sits some evenings (plans/home.md), Look*
## something to look at (BuildingDef.looks). Bed and the rest are found by name (mark()).
func _use_mark(t: int, mark: Marker3D) -> void:
	var n := String(mark.name)
	if (n.begins_with("Seat") or n.begins_with("PorchSeat")) and not mark.has_meta(&"kind"):
		mark.add_to_group("seat")
		mark.set_meta(&"kind", &"porch" if n.begins_with("PorchSeat") else &"home")
		mark.set_meta(&"home", self)
	elif n.begins_with("Look"):
		var words := def.look(n.get_slice(".", 0), t)
		if words.size() == 2:
			var look := LookObject.make(mark.transform, words[0], words[1])
			_tiers[t].add_child(look)
			if not _looks.has(t):
				_looks[t] = []
			_looks[t].append(look)


## Lamps and lanterns glow and light up after dark; window glass glows as if lit inside. Crystal
## pieces (the smithy's crystal forge) glow violet, and its crystal lanterns cast violet light.
static func _mark_night_glow(m: MeshInstance3D) -> void:
	var n := String(m.name).to_lower()
	if n.contains("post"):
		return
	if n.contains("lantern") or n.contains("_lamp"):
		DayNightSky.make_glow(m, true)
	elif n.contains("windowglass") or n.contains("crystal"):
		DayNightSky.make_glow(m)
	if n.contains("crystal"):
		m.set_instance_shader_parameter("glow_tint", CRYSTAL_GLOW)
		for light in m.get_children():
			if light is OmniLight3D:
				(light as OmniLight3D).light_color = CRYSTAL_GLOW


static func _tier_of(node_name: String) -> int:
	var s := node_name.to_lower()
	if s.length() > 2 and s[0] == "t" and s[1].is_valid_int() and s[2] == "_":
		return int(s[1])
	return 0


## `n`'s transform relative to the model root (it isn't in the tree yet).
static func _model_transform(n: Node, root: Node) -> Transform3D:
	var xform := Transform3D.IDENTITY
	while n != root:
		if n is Node3D:
			xform = (n as Node3D).transform * xform
		n = n.get_parent()
	return xform


func _show_tier(t: int) -> void:
	tier_shown = t
	_heading = t
	_upgrading = false
	if not _addon_nodes.is_empty():
		_show_addons.call_deferred(false)
	for k in _tiers:
		_tiers[k].visible = k == t
		_tiers[k].scale = Vector3.ONE
		_set_collision(k, k == t)
		for s in _smoke[k]:
			(s as CPUParticles3D).emitting = k == t
	for piece in _homes:
		piece.transform = _homes[piece]


func _set_collision(t: int, on: bool) -> void:
	for c in _bodies[t].get_children():
		(c as CollisionShape3D).set_deferred("disabled", not on)
	for look: StaticBody3D in _looks.get(t, []):  # (look-at things, and your home's trophy places)
		look.get_child(0).set_deferred("disabled", not on)


# --- the upgrade ----------------------------------------------------------------------------

func _on_tier_changed(id: StringName, t: int) -> void:
	if id == Village.TOWN_HALL and id != def.id and unlock_hall_tier > 0:
		if is_unlocked() and tier_shown == 0:
			_play_upgrade(0, Village.tier(def.id))  # the town hall grew: move in
		elif not is_unlocked() and tier_shown > 0:
			_show_tier(0)  # (debug: the hall went back down)
	elif id == def.id and t != _heading and is_unlocked():  # (heading: a change mid-animation counts)
		_play_upgrade(tier_shown, t)


func _play_upgrade(from: int, to: int) -> void:
	_run += 1
	var run := _run
	_show_tier(from)  # snap any half-played animation to a clean start
	_heading = to
	_upgrading = true  # (the doors leave their pieces to the animation)

	# 1. out with the old: top pieces first, squashing down into the dust
	var old: Array[Node3D] = []
	if from > 0:  # (from 0: a new building going up where there was nothing)
		old = _pieces(from)
	old.sort_custom(func(a: Node3D, b: Node3D) -> bool: return _bottom(a) > _bottom(b))
	_dust.restart()
	_play(_thud, THUD_SFX, 0.7)
	Juice.shake(shake_collapse * _falloff())
	var step := collapse_time / maxf(old.size(), 1)
	for i in old.size():
		var p := old[i]
		var t := p.create_tween()
		t.tween_interval(i * step)
		t.tween_property(p, "scale", Vector3(1.15, 0.05, 1.15), 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		t.parallel().tween_property(p, "position:y", p.position.y - 0.25, 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await get_tree().create_timer(collapse_time + 0.16).timeout
	if run != _run:
		return
	if from > 0:
		_set_collision(from, false)
		_tiers[from].visible = false
		for s in _smoke[from]:
			(s as CPUParticles3D).emitting = false
	for p in old:
		p.transform = _homes[p]

	# 2. in with the new: bottom pieces first, each springing up out of the ground
	tier_shown = to
	_show_addons(false)  # (a slot may open with this tier)
	_tiers[to].visible = true
	_set_collision(to, true)
	var fresh := _pieces(to)
	fresh.sort_custom(func(a: Node3D, b: Node3D) -> bool: return _bottom(a) < _bottom(b))
	for p in fresh:
		p.scale = Vector3.ONE * 0.001
	step = build_time / maxf(fresh.size(), 1)
	var tok_every := maxi(ceili(float(fresh.size()) / MAX_TOKS), 1)
	for i in fresh.size():
		var p := fresh[i]
		var home := _homes[p]
		p.position = home.origin + Vector3.DOWN * 0.3
		var t := p.create_tween()
		t.tween_interval(i * step)
		t.tween_property(p, "scale", home.basis.get_scale(), piece_pop).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		t.parallel().tween_property(p, "position", home.origin, piece_pop).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		if i % tok_every == 0:
			var pitch := lerpf(0.8, 1.6, float(i) / maxf(fresh.size() - 1, 1))
			t.parallel().tween_callback(_tok.bind(p.global_position, pitch))
	await get_tree().create_timer(build_time + piece_pop).timeout
	if run != _run:
		return
	_upgrading = false
	for s in _smoke[to]:
		(s as CPUParticles3D).emitting = true

	# 3. it's done: settle bounce (the visuals only — physics bodies can't squash), burst, name, fanfare
	var group := _tiers[to]
	group.scale = Vector3(1.04, 0.92, 1.04)
	create_tween().tween_property(group, "scale", Vector3.ONE, 0.5).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	_confetti.restart()
	Juice.shake(shake_done * _falloff())
	Music.play_cue(&"upgrade")
	var top := _top_of(fresh)
	var tier_res := def.get_tier(to)
	if tier_res:
		PopupText.spawn(get_parent(), Vector3(global_position.x, top + 0.8, global_position.z),
			"%s!" % tier_res.name, POPUP_COLOR, 18)
	upgraded.emit(to)


func _pieces(t: int) -> Array[Node3D]:
	var out: Array[Node3D] = []
	for c in _tiers[t].get_children():
		if c is MeshInstance3D:
			out.append(c)
	return out


## Local height of a piece's lowest point.
func _bottom(p: Node3D) -> float:
	var aabb := _homes[p] * (p as MeshInstance3D).get_aabb()
	return aabb.position.y


func _top_of(pieces: Array[Node3D]) -> float:
	var top := 3.0
	for p in pieces:
		var aabb := _homes[p] * (p as MeshInstance3D).get_aabb()
		top = maxf(top, aabb.end.y)
	return global_position.y + top


func _tok(at: Vector3, pitch: float) -> void:
	var player := _toks[_next_tok]
	_next_tok = (_next_tok + 1) % _toks.size()
	player.global_position = at
	_play(player, TOK_SFX, pitch)


func _play(player: AudioStreamPlayer3D, stream: AudioStream, pitch := 1.0) -> void:
	player.stream = stream
	player.pitch_scale = pitch
	player.play()


## 1 near the building, fading to 0 by 30 m from the player.
func _falloff() -> float:
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player == null:
		return 1.0
	return clampf(1.0 - player.global_position.distance_to(global_position) / 30.0, 0.0, 1.0)


# --- effects --------------------------------------------------------------------------------

func _build_effects() -> void:
	for i in 4:
		var a := AudioStreamPlayer3D.new()
		a.unit_size = 6.0
		a.max_distance = 60.0
		add_child(a)
		_toks.append(a)
	_thud = AudioStreamPlayer3D.new()
	_thud.unit_size = 8.0
	_thud.max_distance = 60.0
	add_child(_thud)

	var footprint := _footprint()
	_dust = _make_burst(36, 1.2, Color("8f7759"), 0.28)
	_dust.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_dust.emission_box_extents = Vector3(footprint.x * 0.5, 0.3, footprint.y * 0.5)
	_dust.position = Vector3(0, 0.4, 0)
	_dust.direction = Vector3.UP
	_dust.spread = 80.0
	_dust.initial_velocity_min = 1.0
	_dust.initial_velocity_max = 3.0
	_dust.gravity = Vector3(0, -1.5, 0)
	_dust.damping_min = 1.5
	_dust.damping_max = 2.5

	_confetti = _make_burst(48, 1.6, Color.WHITE, 0.12)
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.25, 0.5, 0.75, 1.0])
	ramp.colors = PackedColorArray([Color("f2cf4a"), Color("e66fa1"), Color("64b5e8"), Color("9be27a"), Color("e88a2c")])
	_confetti.color_initial_ramp = ramp
	_confetti.position = Vector3(0, 3.0, 0)
	_confetti.direction = Vector3.UP
	_confetti.spread = 50.0
	_confetti.initial_velocity_min = 5.0
	_confetti.initial_velocity_max = 8.0
	_confetti.angular_velocity_min = -360.0
	_confetti.angular_velocity_max = 360.0


## Half the diagonal of the largest tier's footprint: everything it ever builds is within this.
func footprint_radius() -> float:
	return _footprint().length() * 0.5


## Width (x) and depth (z) of the largest tier, for the dust cloud.
func _footprint() -> Vector2:
	var size := Vector2(4, 4)
	for piece in _homes:
		var aabb := _homes[piece] * (piece as MeshInstance3D).get_aabb()
		size.x = maxf(size.x, absf(aabb.position.x) * 2.0)
		size.x = maxf(size.x, absf(aabb.end.x) * 2.0)
		size.y = maxf(size.y, absf(aabb.position.z) * 2.0)
		size.y = maxf(size.y, absf(aabb.end.z) * 2.0)
	return size


func _make_burst(amount: int, lifetime: float, color: Color, size: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.emitting = false
	p.one_shot = true
	p.explosiveness = 0.9
	p.amount = amount
	p.lifetime = lifetime
	var mesh := SphereMesh.new()  # 4 x 2 segments: a little faceted diamond
	mesh.radial_segments = 4
	mesh.rings = 2
	mesh.radius = size * 0.6
	mesh.height = size
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 1.0
	mesh.material = mat
	p.mesh = mesh
	p.particle_flag_rotate_y = true
	p.angle_min = -180.0
	p.angle_max = 180.0
	p.color = color
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.4
	var shrink := Curve.new()
	shrink.add_point(Vector2(0, 1))
	shrink.add_point(Vector2(1, 0))
	p.scale_amount_curve = shrink
	add_child(p)
	return p


func _make_smoke() -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.name = "Smoke"
	p.amount = 14
	p.lifetime = 4.0
	p.local_coords = false
	var mesh := BoxMesh.new()
	mesh.size = Vector3.ONE * 0.35
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.material = mat
	p.mesh = mesh
	p.direction = Vector3.UP
	p.spread = 12.0
	p.initial_velocity_min = 0.5
	p.initial_velocity_max = 0.8
	p.gravity = Vector3(0.25, 0.15, 0.1)  # a little drift, as if there's a breeze
	p.angular_velocity_min = -40.0
	p.angular_velocity_max = 40.0
	var grow := Curve.new()
	grow.add_point(Vector2(0, 0.4))
	grow.add_point(Vector2(1, 1.0))
	p.scale_amount_curve = grow
	p.scale_amount_min = 0.8
	p.scale_amount_max = 1.6
	var fade := Gradient.new()
	fade.offsets = PackedFloat32Array([0.0, 0.15, 1.0])
	fade.colors = PackedColorArray([Color(0.75, 0.75, 0.75, 0.0), Color(0.72, 0.72, 0.72, 0.55), Color(0.85, 0.85, 0.85, 0.0)])
	p.color_ramp = fade
	return p
