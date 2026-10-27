class_name SpearFishing
extends Node
## Spearfishing, as a part of the Player (child node). When no gatherable node is under the
## crosshair, it looks for water: aiming at a WaterBody's surface within reach (and not at your
## own feet) brings the spear out and allows a strike. Fish along the spear line are highlighted.
##
## A strike: wind-up -> thrust -> on the impact frame a thin capsule is swept from where the
## spear enters the water, along your aim. Every fish inside is skewered (multi-spears are
## physical: line up a school). Fish your spear's tier can't take glance off it ("Needs Iron
## spear"), and fish you're under-levelled for usually dodge. Caught fish appear
## on the held spear, wriggling; the hit escalates with each extra fish (hit-stop, shake, rising pitch,
## "Double!"); on the yank they flip off into the inventory. Misses splash and scatter fish.

const WORLD_MASK := 1
const SPEAR_HIT := preload("res://audio/fishing/spear_hit.tres")
const SPLASH := preload("res://audio/movement/splash.tres")
const FISH_SHADER := preload("res://shaders/fish.gdshader")
const PALETTE := preload("res://art/palette.png")
const COMBO_WORDS := {2: "Double!", 3: "Triple!", 4: "Quadruple!"}
const DODGE_COLOR := Color("ff8a7a")

@export var reach := 2.8
## Minimum horizontal distance to the aim point — no stabbing your own feet.
@export var min_distance := 0.8
## The swept capsule: how far into the water the spear goes, and how thick it counts as.
@export var skewer_length := 0.8
@export var skewer_radius := 0.06
## Skewer length grows by this fraction every 10 Fishing levels.
@export var reach_bonus_per_10_levels := 0.1
## What each spear tier above the stick adds (Tools): reach (m) and skewer length (fraction).
@export var reach_per_tier := 0.15
@export var length_per_tier := 0.1
## Extra XP per additional fish on the same thrust (0.5 = +50% each).
@export var multi_xp_bonus := 0.5

@export_group("Thrust timing")
@export var windup_time := 0.14
@export var thrust_time := 0.06
@export var hold_time := 0.14
@export var yank_time := 0.12
@export var recover_time := 0.2
@export var cooldown := 0.15

@onready var player: CharacterBody3D = get_parent()
@onready var spear: Node3D = player.get_node("%Spear")

var water: WaterBody
var water_point := Vector3.INF
var fish_target: Fish

var _rest_pos := Vector3.ZERO
var _rest_rot := Vector3.ZERO
var _on_spear: Array[Node3D] = []


func _ready() -> void:
	_rest_pos = spear.position
	_rest_rot = spear.rotation


func can_thrust() -> bool:
	return water != null


func clear_target() -> void:
	water = null
	water_point = Vector3.INF
	_set_fish_target(null)


## Called by the Player each physics frame when no gatherable node is targeted.
func update_target() -> void:
	clear_target()
	var cam: Camera3D = player.camera
	var from := cam.global_position
	var dir := -cam.global_basis.z
	if dir.y > -0.05:
		return  # looking level or up: can't hit the water
	for node in get_tree().get_nodes_in_group("water"):
		var wb := node as WaterBody
		var t := (wb.surface_height - from.y) / dir.y
		if t <= 0.0 or t > _reach():
			continue
		var p := from + dir * t
		var flat := Vector2(p.x - player.global_position.x, p.z - player.global_position.z).length()
		if flat < min_distance or wb.depth_here(p) < 0.05:
			continue
		var query := PhysicsRayQueryParameters3D.create(from, p, WORLD_MASK, [player.get_rid()])
		if not player.get_world_3d().direct_space_state.intersect_ray(query).is_empty():
			continue  # the bank or a rock is in the way
		water = wb
		water_point = p
		_set_fish_target(_fish_along(p, dir))
		return


func _set_fish_target(f: Fish) -> void:
	if f == fish_target:
		return
	if is_instance_valid(fish_target):
		fish_target.set_highlighted(false)
	fish_target = f
	if f:
		f.set_highlighted(true)


func _reach() -> float:
	return reach + reach_per_tier * Tools.tier(&"spear")


func _length() -> float:
	var level: int = Skills.level(&"fishing")
	return skewer_length * (1.0 + reach_bonus_per_10_levels * floorf(level / 10.0) + length_per_tier * Tools.tier(&"spear"))


## The first fish along the spear line from the surface point, if any.
func _fish_along(p: Vector3, dir: Vector3) -> Fish:
	var query := PhysicsRayQueryParameters3D.create(p - dir * 0.05, p + dir * _length(), Fish.FISH_LAYER)
	query.collide_with_areas = true
	query.collide_with_bodies = false
	var hit := player.get_world_3d().direct_space_state.intersect_ray(query)
	return (hit["collider"] as Node).get_parent() as Fish if not hit.is_empty() else null


## Every fish inside the thrust capsule, nearest the entry point first.
func _skewer(entry: Vector3, dir: Vector3) -> Array[Fish]:
	var length := _length()
	var capsule := CapsuleShape3D.new()
	capsule.radius = skewer_radius * (1.0 + Village.stat(&"strike_window"))  # the hut's sharper eyes
	capsule.height = length
	var y := dir.normalized()
	var x := y.cross(Vector3.UP).normalized() if absf(y.y) < 0.99 else Vector3.RIGHT
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = capsule
	query.transform = Transform3D(Basis(x, y, x.cross(y)), entry + y * (length / 2.0 - 0.05))
	query.collision_mask = Fish.FISH_LAYER
	query.collide_with_areas = true
	query.collide_with_bodies = false
	var out: Array[Fish] = []
	for r in player.get_world_3d().direct_space_state.intersect_shape(query, 16):
		var f := (r["collider"] as Node).get_parent() as Fish
		if f and not out.has(f):
			out.append(f)
	out.sort_custom(func(a: Fish, b: Fish) -> bool:
		return a.global_position.distance_squared_to(entry) < b.global_position.distance_squared_to(entry))
	return out


func thrust() -> void:
	player._swinging = true
	# 1. wind-up: draw the spear back
	var t := create_tween()
	t.tween_property(spear, "position", _rest_pos + Vector3(0, 0.04, 0.22), windup_time) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	await t.finished

	# 2. thrust
	if player.swing_sfx:
		player.audio.stream = player.swing_sfx
		player.audio.play()
	t = create_tween()
	t.tween_property(spear, "position", _rest_pos + Vector3(0, -0.02, -0.5), thrust_time) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await t.finished

	# 3. impact frame — wherever you're aiming *now*
	update_target()
	if water:
		var entry := water_point
		var dir := -(player.camera as Camera3D).global_basis.z
		var hits := _skewer(entry, dir)
		var caught: Array[Fish] = []
		var dodgers: Array[Fish] = []
		var glanced: Array[Fish] = []
		for f in hits:  # too weak a spear glances off; under-levelled fish usually dodge
			if not f.tool_can_take(&"spear"):
				glanced.append(f)
			else:
				(caught if randf() < f.catch_chance() else dodgers).append(f)
		_splash(entry, 1.0 if caught.is_empty() else 0.7)
		if not glanced.is_empty() and caught.is_empty():
			_play_at(load("res://audio/fishing/jerk.tres"), entry, 1.6, -2.0)
			PopupText.spawn(player.get_parent(), entry + Vector3.UP * 0.3, glanced[0].needs_text(&"spear"), DODGE_COLOR, 5)
		elif not dodgers.is_empty() and caught.is_empty():
			var sp := dodgers[0].species
			PopupText.spawn(player.get_parent(), entry + Vector3.UP * 0.3,
				"%s %d" % [Skills.display_name(&"fishing"), sp.required_level], DODGE_COLOR, 5)
		if caught.is_empty():
			FishPond.disturb(get_tree(), entry, 2.0)  # the miss scatters everything nearby
			t = create_tween()
			t.tween_interval(0.06)
			await t.finished
		else:
			var xp := 0.0
			for f in caught:
				xp += f.species.xp * f.xp_scale() * (1.5 if f.is_under_levelled() else 1.0)  # (reaching up pays)
			var n := caught.size()
			_put_on_spear(caught)
			FishPond.disturb(get_tree(), entry, 2.0)  # the rest of the school bolts
			_impact(n, xp, entry)
			# hold: the fish wriggle on the spear (hit-stop stretches this)
			t = create_tween()
			t.tween_interval(hold_time)
			await t.finished
			# yank the spear up and out of the water
			t = create_tween().set_parallel()
			t.tween_property(spear, "position", _rest_pos + Vector3(0, 0.14, 0.12), yank_time) \
				.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			t.tween_property(spear, "rotation:x", _rest_rot.x + 0.5, yank_time) \
				.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			await t.finished
			_fling_to_inventory()

	# 4. recover
	t = create_tween().set_parallel()
	t.tween_property(spear, "position", _rest_pos, recover_time).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(spear, "rotation", _rest_rot, recover_time).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	await t.finished
	player._cooldown = cooldown
	player._swinging = false


## Takes the fish out of the pond and shows copies of them on the held spear (viewmodel layer).
func _put_on_spear(caught: Array[Fish]) -> void:
	for i in caught.size():
		var f := caught[i]
		var copy := f.species.model.instantiate() as Node3D
		copy.set_meta("item", f.species.id)
		# a Big one counts 2, a Huge one 3; and the fisher's dock sometimes doubles it
		var bonus := randf() < Village.stat(&"bonus_fish_chance")
		copy.set_meta("count", FishSize.count_for(f.size) * (2 if bonus else 1))
		var word := " ".join(PackedStringArray([FishSize.word(f.size), "Bonus!" if bonus else ""])).strip_edges()
		if word != "":
			PopupText.spawn(player.get_parent(), f.global_position + Vector3.UP * (0.6 + i * 0.12), word, Skills.color(&"fishing"), 5, 0.1)
		var mat := ShaderMaterial.new()
		mat.shader = FISH_SHADER
		mat.set_shader_parameter("palette", PALETTE)
		for m in copy.find_children("*", "MeshInstance3D", true, false):
			var mesh := m as MeshInstance3D
			mesh.layers = 2
			mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mesh.material_override = mat
			mesh.set_instance_shader_parameter("body_length", f.length)
			mesh.set_instance_shader_parameter("swim", 1.0)  # frantic wriggling
			mesh.set_instance_shader_parameter("phase", randf() * TAU)
		spear.add_child(copy)
		# across the shaft near the tip, stacked back along it for multi-spears (scaled down: the
		# viewmodel camera is close, full-size fish would fill the screen)
		copy.scale = Vector3.ONE * 0.6 * FishSize.scale_for(f.size)
		copy.position = Vector3(0, 0, -1.1 + i * 0.16)
		copy.rotation = Vector3(randf_range(-0.4, 0.4), PI / 2 + randf_range(-0.3, 0.3), randf_range(-0.3, 0.3))
		_on_spear.append(copy)
		f.school.remove_fish(f)
		f.queue_free()


## Escalating feedback + XP (`xp`: the fish's own, summed) for n fish on one thrust.
func _impact(n: int, xp: float, at: Vector3) -> void:
	var gained := Skills.add_xp(&"fishing", roundi(xp * (1.0 + multi_xp_bonus * (n - 1))))
	Juice.hitstop(0.05 + 0.03 * (n - 1))
	Juice.shake(2.0 + 1.2 * (n - 1))
	for i in n:  # one wet thwack per fish, each a little higher (real time, so hit-stop can't delay them)
		get_tree().create_timer(i * 0.05, true, false, true).timeout.connect(
			_play_at.bind(SPEAR_HIT, at, 1.0 + 0.12 * i, 0.0))
	var color := Skills.color(&"fishing")
	# popups are small: spearfishing happens at arm's length, not across a clearing
	if n >= 2:
		PopupText.spawn(player.get_parent(), at + Vector3.UP * 0.42, COMBO_WORDS.get(n, "x%d!" % n), color, 6)
	if gained > 0:
		PopupText.spawn(player.get_parent(), at + Vector3.UP * 0.25, "+%d" % gained, color, 4 if n < 2 else 5, 0.06)


## The fish flip off the spear one after another, into the inventory.
func _fling_to_inventory() -> void:
	var cam := spear.get_viewport().get_camera_3d()
	for i in _on_spear.size():
		var fish := _on_spear[i]
		fish.reparent(cam)
		var t := fish.create_tween().set_parallel()
		t.tween_property(fish, "position", Vector3(0.3, -0.55, -0.35), 0.2).set_delay(i * 0.08) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
		t.tween_property(fish, "scale", Vector3.ONE * 0.1, 0.2).set_delay(i * 0.08)
		t.chain().tween_callback(func() -> void:
			Inventory.add(fish.get_meta("item"), fish.get_meta("count", 1))
			Sfx.play_pickup()
			fish.queue_free())
	_on_spear.clear()


func _splash(at: Vector3, volume: float) -> void:
	_play_at(SPLASH, at, randf_range(1.15, 1.35), linear_to_db(volume) - 2.0)
	WaterRipple.spawn(water, Vector3(at.x, water.surface_height, at.z), 2.2, 1.1)


func _play_at(stream: AudioStream, at: Vector3, pitch: float, db: float) -> void:
	var p := AudioStreamPlayer3D.new()
	p.stream = stream
	p.pitch_scale = pitch
	p.volume_db = db
	p.unit_size = 4.0
	player.get_parent().add_child(p)
	p.global_position = at
	p.play()
	p.finished.connect(p.queue_free)
