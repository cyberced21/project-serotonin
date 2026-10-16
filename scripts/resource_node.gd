class_name ResourceNode
extends StaticBody3D
## A gatherable node (tree, rock, ore vein...). Everything is tweakable from the inspector.
## To make a new resource type: right-click scenes/resource_node.tscn > New Inherited Scene, then add
## MeshInstance3Ds under:
##   Visual/Body   — the part that stays until the node breaks (core, trunk, canopy)
##   Visual/Chunks — pieces that break off as it wears down (the one nearest the hit pops off)
##   Rubble        — what's left while it respawns (stump, rubble)
## Give meshes materials/node_surface.tres as Material Override and set their colour under
## Geometry > Instance Shader Parameters > albedo. Then set the item, sounds and colors here.
##
## Or set `model` to a .glb from Blender instead: its meshes are sorted into those three places
## by object name — Body_*, Chunk_*, Rubble_* — and given the palette material automatically.

signal depleted(node: ResourceNode)
signal respawned(node: ResourceNode)

const PICKUP_SCENE := preload("res://scenes/pickup.tscn")
const NODE_SURFACE := preload("res://materials/node_surface.tres")
const NODE_PALETTE := preload("res://materials/node_palette.tres")
## Object-name prefixes in a model (.glb) and where those meshes go.
const MODEL_PARTS := {"body_": "Visual/Body", "chunk_": "Visual/Chunks", "rubble_": "Rubble"}
const NOTCH_COLOR := Color(0.08, 0.06, 0.05, 0.85)
const GHOST_OUTLINE := preload("res://shaders/ghost_outline.gdshader")
const GHOST_MASK := preload("res://shaders/ghost_mask.gdshader")
const GHOST_OUTLINE_STENCIL := preload("res://shaders/ghost_outline_stencil.gdshader")
const GHOST_MASK_STENCIL := preload("res://shaders/ghost_mask_stencil.gdshader")
const DEFLECT_SFX := preload("res://audio/stone_hit.tres")
const DEFLECT_COLOR := Color("ff8a7a")
const SHARP_COLOR := Color("ffd27a")
const WORLD_LAYER := 1
## Physics layer 4: debris collides with the world but not the player (layer 2) or pickups.
const DEBRIS_LAYER := 1 << 3
const DEBRIS_LIFETIME := 1.6
## The felled piece counts as landed once it leans past this (dot of its up axis with world up).
const LANDED_TILT := 0.35
const FELLED_LINGER := 2.5
const FELLED_SHAPE_SCALE := 0.6

@export_group("Gathering")
@export var item: StringName = &"wood"
## Leave empty to use the item's icon from art/icons/ (see Items).
@export var item_icon: Texture2D
@export var tool_type: StringName = &"axe"
@export_range(1, 20) var max_hits := 5
@export_range(0, 10) var drops_min := 2
@export_range(0, 10) var drops_max := 4
@export var respawn_time := 15.0
## Rocks: the collision is fitted to the model (a convex hull of the body and the chunks still
## on, refitted as they break off), so swings and cracks land on the rock itself rather than on
## the box in the scene. Trees keep their trunk shape (topple uses it).
@export var fit_collision := false
## Unique key this node's state (hits left, respawn timer) is saved under. Give every placed
## node its own. If empty, its scene path is used, which resets it when renamed or moved.
@export var save_id: StringName

@export_group("Skill")
## Skill id from Skills.SKILLS (e.g. woodcutting, mining).
@export var skill: StringName = &"woodcutting"
@export_range(1, 50) var required_level := 1
@export_range(0, 100) var xp_per_hit := 5
@export_range(0, 500) var xp_on_break := 15

@export_group("Visuals")
## Optional model (.glb) replacing the greybox meshes — see the top of this script.
@export var model: PackedScene
@export var chip_color := Color("dea876")
@export var burst_color := Color("38804c")
## Height above the node's origin where XP / level popups appear.
@export var popup_height := 1.6
## Chunks glow after dark (crystal), and a small light in `glow_color` hangs over the node.
@export var glow_at_night := false
@export var glow_color := Color(0.7, 0.5, 1.0)
## How hard broken-off chunks fly away (m/s).
@export var debris_speed := 3.0
## Chips, shards, dust and sparks per hit (scenes/fx/hit_fx.tscn), instead of the Chips particles.
## Chips are chip_color with some ore_color (the ore) when the node has cracks.
@export var hit_fx: PackedScene
## Sparks off the tool per hit (doubled on a crack tip). Harder rock, more sparks.
@export_range(0, 32) var spark_amount := 0
## Pebbles that pile up around the base as it's worn down, until it grows back (0 = none).
@export_range(0, 64) var lingering_rubble := 0

@export_group("Audio")
@export var hit_sfx: AudioStream
@export var break_sfx: AudioStream
## How much higher-pitched each hit gets as the node weakens (escalation).
@export_range(0.0, 0.5) var stress_pitch := 0.15
## Layered hit (audio/mining/): played instead of hit_sfx when set.
@export var hit_layers: SoundLayers
## The tool tearing back out of the node.
@export var pull_layers: SoundLayers
## Each broken-off piece clattering on the ground (its first couple of bounces).
@export var debris_layers: SoundLayers

@export_group("Topple")
## Trees: on break, Visual/Body falls over as one physics piece instead of vanishing.
## Drops spill along the trunk when it lands.
@export var topple := false
## Heavy thud when the felled piece hits the ground (positional).
@export var land_sfx: AudioStream
@export_range(0.3, 1.5) var land_pitch := 0.55
## Shake when it lands, faded out over 20 m from the player.
@export var shake_land := 3.5
## Tipping speed at the start of the fall (rad/s).
@export var topple_push := 0.8

@export_group("Respawn display")
## Countdown above the spot while the node is depleted.
@export var show_respawn_timer := true
## Outline (in the skill's colour) of where the node will grow back. Fades in as it nears.
@export var show_respawn_ghost := true
@export_range(0.0, 1.0) var ghost_alpha := 0.6
## One outline around the whole node's silhouette (stencil), instead of one around every piece.
@export var ghost_silhouette := true
## The timer is hidden beyond this distance from the camera, to avoid clutter.
@export var respawn_display_range := 30.0

@export_group("Weak point")
## A glowing spot on one of the chunks. Hitting near it counts as extra hits and doubles the XP;
## then it jumps to another chunk.
@export var weak_point := true
## How close to the spot the swing must aim (m, measured across the line of the swing).
@export var weak_point_radius := 0.28
@export_range(0, 5) var weak_point_extra_hits := 1
@export var weak_point_color := Color(1.0, 0.93, 0.55)

@export_group("Cracks")
## Rocks: hits open a crack across the struck face, with a glowing tip. Hitting near the tip
## extends it (counts extra hits, doubles the XP); a full crack splits off every chunk it crossed,
## and on the bare core it breaks the node. Replaces the weak point.
@export var cracks := false
@export_range(2, 6) var crack_segments := 3
## How far the tip jumps per segment (m) — far enough that you have to re-aim to follow it.
@export var crack_segment_length := 0.3
## How close to the tip the swing must aim (m, measured across the line of the swing).
@export var crack_tip_radius := 0.25
@export_range(0, 5) var crack_tip_extra_hits := 1
## Extra hits a completed crack does on top of the chunks it splits off.
@export_range(0, 5) var crack_split_hits := 0
## The ore's colour: a share of the chips and pebbles, and the Crack!/Split! popups. (Cracks
## themselves are drawn in shades of chip_color, the rock's own stone.)
@export var ore_color := Color(1.0, 0.6, 0.3)
## Tip hit (pitched up per segment) and a completed crack splitting.
@export var crack_layers: SoundLayers
@export var split_layers: SoundLayers

@export_group("Performance")
## Beyond this distance (m) the node fades out and isn't drawn at all (0 = always drawn). The
## forest's scenery trees stand in for far-away ones.
@export var draw_distance := 110.0
## Chunks are small: drawing their shadows costs a pass each for little to see.
@export var chunk_shadows := false
@export_group("Feel")
@export var hitstop_hit := 0.045
@export var hitstop_break := 0.11
@export var shake_hit := 1.5
@export var shake_break := 4.0

@onready var visual: Node3D = $Visual
@onready var chunks: Node3D = $Visual/Chunks
@onready var notches: Node3D = _make_notches()
@onready var rubble: Node3D = $Rubble
@onready var collision: CollisionShape3D = $CollisionShape3D
@onready var chips: CPUParticles3D = $Chips
@onready var burst: CPUParticles3D = $Burst
@onready var audio: AudioStreamPlayer3D = $Audio
@onready var break_audio: AudioStreamPlayer3D = $BreakAudio

var hits_left := 0
var _cut := 0.0  # hit_power's fraction of a hit, carried over to the next one
var _surfaces: Array[GeometryInstance3D] = []
var _flash_tween: Tween
var _nudge_tween: Tween
var _burst_home := Vector3.ZERO
var _break_audio_home := Vector3.ZERO
var _respawn_timer: SceneTreeTimer
var _timer_label: Label3D
var _ghost: Node3D
var _ghost_outline: ShaderMaterial


func _ready() -> void:
	add_to_group("gatherable")
	_apply_model()
	_burst_home = burst.position
	_break_audio_home = break_audio.position
	_collect_surfaces(visual)
	_fit_collision()
	chips.color = chip_color
	burst.color = burst_color
	hits_left = max_hits
	_build_rubble()
	_reset_visuals()
	_build_respawn_display()
	set_process(false)
	# applies any saved state now; older saves keyed nodes by scene path, so carry those over
	var path_key := StringName("node:%s" % get_path())
	if save_id.is_empty():
		SaveGame.register(path_key, self)
	else:
		SaveGame.register(StringName("node:" + save_id), self, path_key)
	_build_weak_point()  # after loading, so it lands on a chunk that's still there
	_limit_drawing(self)
	if glow_at_night:
		_setup_glow()


## Moves the model's meshes into Visual/Body, Visual/Chunks and Rubble by name prefix, replacing
## whatever greybox meshes were there. Meshes with other names are ignored.
func _apply_model() -> void:
	if model == null:
		return
	var inst := model.instantiate()
	for path in MODEL_PARTS.values():
		for old in get_node(path).get_children():
			old.get_parent().remove_child(old)
			old.queue_free()
	for m in inst.find_children("*", "MeshInstance3D", true, false):
		var dest := ""
		for prefix in MODEL_PARTS:
			if m.name.to_lower().begins_with(prefix):
				dest = MODEL_PARTS[prefix]
		if dest.is_empty():
			continue
		var xform := Transform3D.IDENTITY  # relative to the model root (it isn't in the tree)
		var n: Node = m
		while n != inst:
			xform = (n as Node3D).transform * xform if n is Node3D else xform
			n = n.get_parent()
		m.get_parent().remove_child(m)
		m.owner = null
		get_node(dest).add_child(m)
		m.transform = xform
		m.material_override = NODE_PALETTE
	inst.free()


func _make_notches() -> Node3D:
	var n := Node3D.new()
	n.name = "Notches"
	$Visual.add_child(n)
	return n


func is_available() -> bool:
	return hits_left > 0


## False when the player's skill level is too low — hits will bounce off.
func can_gather() -> bool:
	return Skills.level(skill) >= required_level


## Called by the player while the crosshair is on this node.
func set_highlighted(on: bool) -> void:
	for s in _surfaces:
		s.set_instance_shader_parameter("highlight", 1.0 if on else 0.0)
	if on and _weak and not _weak.visible and can_gather():  # levelled up since it was hidden
		_place_weak_point()


## Called by the player on the impact frame of a swing. Returns true if the tool bit in
## (the player then holds it there and calls pull()), false if it bounced off.
func hit(info: HitInfo) -> bool:
	if hits_left <= 0:
		return false
	if not can_gather():
		_deflect(info)
		return false
	# the smithy's sharper tools: sometimes a hit counts twice, and crystal edges cut deeper every
	# time (the fraction carries over, so +0.5 means every other hit counts twice); the weak point
	# always adds more
	_cut += 1.0 + Village.stat(&"hit_power")
	var cuts := int(_cut)
	_cut -= cuts
	var double := randf() < Village.stat(&"double_hit_chance") or cuts > 1
	var weak := _is_weak_hit(info)
	var tip := cracks and _is_tip_hit(info)
	hits_left = maxi(hits_left - cuts - (1 if double and cuts == 1 else 0) - (weak_point_extra_hits if weak else 0)
		- (crack_tip_extra_hits if tip else 0), 0)
	if weak:
		_weak_hit_feedback(info)
	SaveGame.mark_dirty()
	var stress := 1.0 - float(hits_left) / max_hits  # 0 -> 1 as it depletes

	var pitch := 1.0 + stress * stress_pitch - (0.12 if double else 0.0)
	if hit_layers:
		Sfx.play_at(hit_layers, info.position, pitch, 2.0 if double else 0.0)
	else:
		_play(audio, hit_sfx, pitch)
	_flash()
	_nudge(info.away() * (1.6 if double else 1.0))
	_hit_effects(info, 1.5 if tip else 1.0)
	Juice.shake(shake_hit + stress * 1.5 + (1.5 if double else 0.0))
	Juice.hitstop(hitstop_hit + (0.035 if double else 0.0))
	if double:
		PopupText.spawn(get_parent(), _popup_pos() + Vector3(0, 0.35, 0), "Sharp!", SHARP_COLOR, 9)
	_award_xp(xp_per_hit * (2 if double else 1) * (2 if weak or tip else 1))

	if hits_left > 0 and cracks and _grow_crack(info, tip):
		_split(info)  # the crack ran all the way across

	if hits_left == 0:
		_break(info)
	else:
		_notch_at(info)
		if weak:
			_place_weak_point.call_deferred()  # after this hit's chunks have popped
	return true


## Called by the player when the tool is yanked back out after biting in: the node tugs
## toward the player and the piece the tool bit into tears out, flying toward the camera.
func pull(info: HitInfo) -> void:
	if hits_left <= 0:
		return  # broke on this hit — the break already threw everything
	var stress := 1.0 - float(hits_left) / max_hits
	Sfx.play_at(pull_layers, info.position, 1.0 + stress * stress_pitch * 0.5)
	var toward := -info.away()
	_nudge(toward * 0.6)
	var tear := (info.normal * 0.6 + toward * 0.6).normalized()
	_spawn_fragment(info, tear)
	_shed_chunks(stress, info, tear)


## Under-levelled: the tool bounces off — clank, small nudge, no damage, no XP.
func _deflect(info: HitInfo) -> void:
	_play(audio, DEFLECT_SFX, 1.8)
	_nudge(info.away())
	Juice.shake(0.5)
	PopupText.spawn(get_parent(), _popup_pos(), "%s %d" % [Skills.display_name(skill), required_level], DEFLECT_COLOR)


func _award_xp(amount: int, big := false) -> void:
	if amount <= 0:
		return
	var gained := Skills.add_xp(skill, amount)
	if gained > 0:
		PopupText.spawn(get_parent(), _popup_pos() + Vector3(randf_range(-0.2, 0.2), 0.25 if big else 0.0, 0.0),
			"+%d" % gained, Skills.color(skill), 10 if big else 8, 0.08 if big else 0.0)


func _popup_pos() -> Vector3:
	return global_position + Vector3(0, popup_height, 0)


func _break(info: HitInfo) -> void:
	_award_xp(xp_on_break, true)
	_play(break_audio, break_sfx)
	for c in _intact_chunks():
		_pop_chunk(c, info.away(), debris_speed * 0.7)
	_show_depleted()
	Juice.shake(shake_break)
	Juice.hitstop(hitstop_break)
	if topple:
		_topple(info)  # not awaited: the fall plays out while the respawn timer runs
	else:
		burst.restart()
		_spawn_drops(info)
	depleted.emit(self)
	SaveGame.mark_dirty()
	_respawn_after(_regrow_time())


## The depleted look (rubble / stump, no collision) without any of the break effects.
func _show_depleted() -> void:
	set_highlighted(false)
	visual.visible = false
	rubble.visible = true
	collision.set_deferred("disabled", true)


## Debug: if depleted, grow back now.
func respawn_now() -> void:
	if _respawn_timer:
		_respawn_timer.time_left = 0.01


## respawn_time, shortened for rocks by Edda's assay office.
func _regrow_time() -> float:
	var regrow := Village.stat(&"rock_regrow") if skill == &"mining" else 0.0
	return respawn_time * maxf(1.0 - regrow, 0.1)


func _respawn_after(seconds: float) -> void:
	_respawn_timer = get_tree().create_timer(seconds)
	_set_respawn_display(true)
	await _respawn_timer.timeout
	_respawn_timer = null
	_set_respawn_display(false)
	hits_left = max_hits
	_reset_visuals()
	_place_weak_point()
	visual.scale = Vector3.ONE * 0.4
	create_tween().tween_property(visual, "scale", Vector3.ONE, 0.35) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	SaveGame.mark_dirty()
	respawned.emit(self)


# --- saving ---------------------------------------------------------------------------------
# Each node saves under its path in the scene, so renaming / moving a node in the editor just
# makes it start fresh. Respawn timers count game time: they pause while the game is closed.

func to_dict() -> Dictionary:
	if _respawn_timer:
		return {"respawn_left": _respawn_timer.time_left}
	return {"hits_left": hits_left}


func from_dict(d: Dictionary) -> void:
	if d.has("respawn_left"):
		hits_left = 0
		_show_depleted()
		_respawn_after(maxf(float(d["respawn_left"]), 0.1))
	elif d.has("hits_left"):
		hits_left = clampi(int(d["hits_left"]), 1, max_hits)
		# hide the chunks that would already have broken off
		var total := chunks.get_child_count()
		var stress := 1.0 - float(hits_left) / max_hits
		var gone := mini(floori(stress * total), total - 1)
		for k in gone:
			chunks.get_child(k).visible = false
		# and the pebbles those hits would have knocked down
		for k in max_hits - hits_left:
			_add_rubble(to_global(Vector3(randf_range(-1, 1), 0.5, randf_range(-1, 1))), 1)


func _reset_visuals() -> void:
	for c in chunks.get_children():
		c.visible = true
	for n in notches.get_children():
		n.queue_free()  # (cracks too)
	_crack.clear()
	_crack_normals.clear()
	_crack_tip = null
	_queue_refit()
	if _rubble_mm:
		_rubble_mm.multimesh.visible_instance_count = 0
	visual.visible = true
	rubble.visible = false
	collision.set_deferred("disabled", false)
	burst.position = _burst_home
	break_audio.position = _break_audio_home


func _drop_count() -> int:
	var extra := 0
	if skill == &"woodcutting":
		extra = int(Village.stat(&"extra_logs"))  # the woodcutter's lodge
	elif skill == &"mining":
		extra = int(Village.stat(&"extra_ore"))  # Edda's assay shed
	return randi_range(drops_min, maxi(drops_min, drops_max)) + extra


func _spawn_drops(info: HitInfo) -> void:
	var toward_player := -info.away()
	for i in _drop_count():
		var spread := Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)) * 1.2
		var vel := toward_player * randf_range(1.0, 2.0) + spread + Vector3.UP * randf_range(3.0, 4.5)
		_launch_drop(global_position + Vector3(0, popup_height * 0.5, 0) + toward_player * 0.4, vel, i * 0.04)


func _launch_drop(from: Vector3, velocity: Vector3, delay: float) -> void:
	var p := PICKUP_SCENE.instantiate()
	p.item = item
	p.icon = item_icon if item_icon else Items.icon(item)
	get_parent().add_child(p)
	p.launch(from, velocity, delay)


# --- topple ---------------------------------------------------------------------------------

## Copies Visual/Body into one rigid body standing where the tree was and tips it away from
## the player. Gravity does the rest; when it has fallen over: thud, leaf burst, logs along the trunk.
func _topple(info: HitInfo) -> void:
	var away := info.away()
	var felled := RigidBody3D.new()
	felled.collision_layer = DEBRIS_LAYER
	felled.collision_mask = WORLD_LAYER
	felled.mass = 200.0
	felled.physics_material_override = PhysicsMaterial.new()
	felled.physics_material_override.friction = 1.0
	var height := 0.0
	for mesh in visual.get_node("Body").get_children():
		if not mesh is MeshInstance3D:
			continue
		var piece := mesh.duplicate() as MeshInstance3D
		piece.set_instance_shader_parameter("flash", 0.0)
		piece.set_instance_shader_parameter("highlight", 0.0)
		felled.add_child(piece)
		var aabb: AABB = mesh.get_aabb()
		var shape := CollisionShape3D.new()
		shape.shape = BoxShape3D.new()
		# shrunk, so a wide canopy lands softly instead of see-sawing the base up into the air
		(shape.shape as BoxShape3D).size = aabb.size * FELLED_SHAPE_SCALE
		shape.transform = mesh.transform * Transform3D(Basis.IDENTITY, aabb.get_center())
		felled.add_child(shape)
		height = maxf(height, mesh.position.y + aabb.end.y)
	# the node's own collision shape (the trunk) at full size
	var trunk := CollisionShape3D.new()
	trunk.shape = collision.shape
	trunk.transform = collision.transform
	felled.add_child(trunk)
	# top-heavy on purpose (canopy), so once it starts leaning it keeps going
	felled.center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	felled.center_of_mass = Vector3(0, height * 0.65, 0)
	felled.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_ON
	get_parent().add_child(felled)
	felled.global_transform = global_transform.orthonormalized()
	felled.reset_physics_interpolation()
	# start it rotating around its *base* (the hinge on the stump), not its centre of mass —
	# otherwise the base skids along the ground and the fall loses all its energy
	var spin := Vector3.UP.cross(away).normalized() * topple_push
	felled.angular_velocity = spin
	felled.linear_velocity = spin.cross(Vector3.UP * felled.center_of_mass.y)

	# wait for it to lean over far enough (or give up after a few seconds)
	var start := Time.get_ticks_msec()
	while is_instance_valid(felled) and felled.global_basis.y.dot(Vector3.UP) > LANDED_TILT \
			and Time.get_ticks_msec() - start < 4000:
		await get_tree().physics_frame
	if not is_instance_valid(felled):
		return

	felled.angular_damp = 6.0  # settle where it lands rather than rolling around
	felled.linear_damp = 1.5
	var top := felled.global_transform * Vector3(0, height * 0.75, 0)
	break_audio.global_position = top
	_play(break_audio, land_sfx, land_pitch)
	burst.global_position = top
	burst.restart()
	var player := get_tree().get_first_node_in_group("player") as Node3D
	var falloff := 1.0
	if player:
		falloff = clampf(1.0 - player.global_position.distance_to(top) / 20.0, 0.0, 1.0)
	Juice.shake(shake_land * falloff)

	# logs spill out along the trunk
	for i in _drop_count():
		var along := felled.global_transform * Vector3(0, randf_range(0.25, 0.85) * height, 0)
		var vel := Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)) * 1.5 + Vector3.UP * randf_range(2.5, 4.0)
		_launch_drop(along + Vector3.UP * 0.3, vel, i * 0.05)

	# settle, then sink into the ground and disappear
	await get_tree().create_timer(FELLED_LINGER).timeout
	if not is_instance_valid(felled):
		return
	felled.freeze = true
	var t := felled.create_tween().set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)  # interpolated body
	t.tween_property(felled, "global_position", felled.global_position + Vector3.DOWN * 1.2, 1.0) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	t.tween_callback(felled.queue_free)


# --- chunks ---------------------------------------------------------------------------------

## Pops chunks off until the visible amount matches how worn down the node is.
## The last chunk always stays on until the node actually breaks.
func _shed_chunks(stress: float, info: HitInfo, push: Vector3) -> void:
	var total := chunks.get_child_count()
	var should_be_gone := mini(floori(stress * total), total - 1)
	var intact := _intact_chunks()
	while total - intact.size() < should_be_gone and not intact.is_empty():
		var nearest := _nearest(intact, info.position)
		intact.erase(nearest)
		_pop_chunk(nearest, push, debris_speed)


func _intact_chunks() -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	for c in chunks.get_children():
		if c is MeshInstance3D and c.visible:
			out.append(c)
	return out


func _nearest(list: Array[MeshInstance3D], point: Vector3) -> MeshInstance3D:
	var best: MeshInstance3D = list[0]
	var best_d := INF
	for c in list:
		var d := (c.global_transform * c.get_aabb().get_center()).distance_squared_to(point)
		if d < best_d:
			best_d = d
			best = c
	return best


## Hides the chunk and throws a physics copy of it, which shrinks away after a moment.
func _pop_chunk(chunk: MeshInstance3D, push: Vector3, speed: float) -> void:
	chunk.visible = false
	_queue_refit()
	var piece := chunk.duplicate() as MeshInstance3D
	_throw(piece, chunk.global_transform.orthonormalized(), push, speed)


## A small piece of whatever was struck, torn out at the hit point on every hit.
## A miniature copy of the chunk nearest the hit, so it has that surface's real colours (palette
## or greybox alike). Falls back to a chip-coloured box when no chunks are left.
func _spawn_fragment(info: HitInfo, push: Vector3) -> void:
	var intact := _intact_chunks()
	var piece: MeshInstance3D
	var size := 0.3
	if intact.is_empty():
		piece = MeshInstance3D.new()
		piece.mesh = BoxMesh.new()
		piece.material_override = NODE_SURFACE
		piece.set_instance_shader_parameter("albedo", chip_color)
		size = 0.12
	else:
		piece = _nearest(intact, info.position).duplicate() as MeshInstance3D
	var rot := Basis.from_euler(Vector3(randf(), randf(), randf()) * TAU)
	_throw(piece, Transform3D(rot, info.position + info.normal * 0.06), push, debris_speed * 0.8, size)


## Puts `piece` (scaled by `piece_scale`) in a debris rigid body at `xform` and flings it.
func _throw(piece: MeshInstance3D, xform: Transform3D, push: Vector3, speed: float, piece_scale := 1.0) -> void:
	var body := RigidBody3D.new()
	body.collision_layer = DEBRIS_LAYER
	body.collision_mask = WORLD_LAYER
	piece.transform = Transform3D(Basis.from_scale(Vector3.ONE * piece_scale), Vector3.ZERO)
	piece.visible = true
	piece.set_instance_shader_parameter("flash", 0.0)
	piece.set_instance_shader_parameter("highlight", 0.0)
	body.add_child(piece)
	var aabb := piece.get_aabb()
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	(shape.shape as BoxShape3D).size = aabb.size * piece_scale
	shape.position = aabb.get_center() * piece_scale
	body.add_child(shape)
	body.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_ON
	get_parent().add_child(body)
	body.global_transform = xform
	body.reset_physics_interpolation()
	var jitter := Vector3(randf_range(-1, 1), randf_range(0, 1), randf_range(-1, 1)) * 0.4
	body.linear_velocity = (push + Vector3.UP * 0.8 + jitter).normalized() * speed
	body.angular_velocity = Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * 6.0
	if debris_layers:
		_clatter(body, piece_scale)

	var t := body.create_tween().set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)  # interpolated body
	t.tween_interval(DEBRIS_LIFETIME)
	t.tween_property(piece, "scale", Vector3.ONE * 0.01, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	t.tween_callback(body.queue_free)


## A piece of debris ticks when it lands, and again on its next bounce: louder the faster it was
## going and the bigger it is (a torn-out fragment is a fraction of a chunk).
func _clatter(body: RigidBody3D, piece_scale: float) -> void:
	body.contact_monitor = true
	body.max_contacts_reported = 1
	var bounces := [0]  # (an array so the lambda can change it)
	body.body_entered.connect(func(_other: Node) -> void:
		if bounces[0] >= 2:
			return
		bounces[0] += 1
		var strength := body.linear_velocity.length() / maxf(debris_speed, 0.1) * lerpf(0.6, 1.0, piece_scale)
		Sfx.play_debris(debris_layers, body.global_position, strength * (0.6 if bounces[0] > 1 else 1.0)))


# --- fitted collision -----------------------------------------------------------------------

## Middle of the collision shape and its widest half-width on the ground (node space).
var _shape_centre := Vector3(0, 0.5, 0)
var _footprint := 0.6
var _refit_queued := false


func _queue_refit() -> void:
	if fit_collision and not _refit_queued:
		_refit_queued = true
		_fit_collision.call_deferred()


## A convex hull around every visible piece in Visual. (Visual at rest is the node's own space;
## measured relative to it, so a nudge in progress doesn't skew the shape.)
func _fit_collision() -> void:
	_refit_queued = false
	if fit_collision:
		var seen := {}
		var points := PackedVector3Array()
		var to_visual := visual.global_transform.affine_inverse()
		for m in visual.find_children("*", "MeshInstance3D", true, false):
			var mesh := m as MeshInstance3D
			if not mesh.visible or mesh.mesh == null:
				continue
			var xform := to_visual * mesh.global_transform
			for s in mesh.mesh.get_surface_count():
				var verts: PackedVector3Array = mesh.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]
				for v in verts:
					var p := (xform * v).snappedf(0.005)  # flat-shaded meshes repeat every corner
					if not seen.has(p):
						seen[p] = true
						points.append(p)
		if points.size() >= 4:
			var hull := ConvexPolygonShape3D.new()
			hull.points = points
			collision.shape = hull
			collision.transform = Transform3D.IDENTITY
	var box := AABB()
	if collision.shape is ConvexPolygonShape3D:
		var pts := (collision.shape as ConvexPolygonShape3D).points
		box = AABB(pts[0], Vector3.ZERO)
		for p in pts:
			box = box.expand(p)
	elif collision.shape is BoxShape3D:
		box = AABB(-(collision.shape as BoxShape3D).size * 0.5, (collision.shape as BoxShape3D).size)
		box.position += collision.position
	else:
		return
	_shape_centre = box.get_center()
	_footprint = maxf(box.size.x, box.size.z) * 0.5


# --- cracks ---------------------------------------------------------------------------------
# A crack runs over the node's collision surface (fit_collision makes that the real shape), each
# new point found by casting back onto it, so it bends with the rock; its decals project onto the
# mesh. Points are in node space and decals are placed relative to Visual at rest, so the hit's
# nudge doesn't knock them off the spot.

## The crack being worked on, from where it started to the tip, and the surface normal at each
## point (node space). Empty when there isn't one.
var _crack: Array[Vector3] = []
var _crack_normals: Array[Vector3] = []
## The side it started on, and which way it's heading.
var _crack_normal := Vector3.UP
var _crack_dir := Vector3.RIGHT
var _crack_tip: Decal


func _is_tip_hit(info: HitInfo) -> bool:
	return not _crack.is_empty() and _crack_tip != null and _aimed_near(info, to_global(_crack[-1]), crack_tip_radius)


## Grows the crack if the tip was hit, or starts one where this hit landed if there isn't one on
## this side (one left on another side stays as a scar). True when the crack is complete.
func _grow_crack(info: HitInfo, tip: bool) -> bool:
	if tip:
		_extend_crack()
		var seg := _crack.size() - 1
		Sfx.play_at(crack_layers, info.position, 1.0 + 0.12 * seg)
		PopupText.spawn(get_parent(), _popup_pos() + Vector3(0, 0.6, 0), "Crack!", ore_color, 10)
		Juice.shake(1.5)
		Juice.hitstop(0.03)
		return seg >= crack_segments
	var n := (global_basis.inverse() * info.normal).normalized()
	if _crack.is_empty() or n.dot(_crack_normal) < 0.5:
		_retire_tip()
		_crack_normal = n
		_crack.assign([to_local(info.position)])
		_crack_normals.assign([n])
		_crack_dir = _first_crack_direction(n)
		_extend_crack()
	return false


## A full crack: everything it crossed splits off. On the bare core, the node breaks.
func _split(info: HitInfo) -> void:
	var path := _crack.duplicate()
	var normals := _crack_normals.duplicate()
	_crack.clear()
	_crack_normals.clear()
	_retire_tip()
	Sfx.play_at(split_layers, info.position)
	PopupText.spawn(get_parent(), _popup_pos() + Vector3(0, 0.85, 0), "Split!", ore_color, 12)
	Juice.shake(3.0)
	Juice.hitstop(0.07)
	var intact := _intact_chunks()
	if intact.is_empty():
		hits_left = 0
		return
	var crossed := intact.filter(func(c: MeshInstance3D) -> bool: return _crack_crosses(c, path, normals))
	if crossed.is_empty():
		crossed = [_nearest(intact, to_global(path[path.size() / 2]))]
	var out := (global_basis * _crack_normal).normalized()
	if hit_fx:
		var mid := to_global(path[path.size() / 2])
		HitFx.spawn(hit_fx, get_parent(), mid, out, -out, chip_color, ore_color, 2.2)
	_add_rubble(info.position, 4)
	for c in crossed:
		_pop_chunk(c, out + info.away() * 0.4, debris_speed * 1.2)
	hits_left = maxi(hits_left - crack_split_hits, 0)
	SaveGame.mark_dirty()


## The first way a new crack heads: sideways and a little down (anywhere across the top).
func _first_crack_direction(n: Vector3) -> Vector3:
	if absf(n.y) > 0.7:
		var a := randf() * TAU
		var flat := Vector3(cos(a), 0.0, sin(a))
		return (flat - n * flat.dot(n)).normalized()
	var d := n.cross(Vector3.UP).normalized() * (1.0 if randf() < 0.5 else -1.0)
	d += Vector3.DOWN * randf_range(0.0, 0.7)
	return (d - n * d.dot(n)).normalized()


## Adds a segment, wandering a little: of a few headings, the one that gets furthest over the
## surface without wrapping round to the far side.
func _extend_crack() -> void:
	var from := _crack[-1]
	var up := _crack_normals[-1]
	var best := {}
	var best_len := 0.0
	for turn in [randf_range(-0.5, 0.5), randf_range(-0.5, 0.5), 1.2, -1.2]:
		var s := _surface_at(from + _crack_dir.rotated(up, turn) * crack_segment_length, up)
		if s.is_empty() or (s["normal"] as Vector3).dot(_crack_normal) < 0.3:
			continue
		var length := from.distance_to(s["position"])
		if length > best_len + 0.02:
			best = s
			best_len = length
	if best.is_empty():  # nowhere to go: a short step on the spot's own plane, so it still grows
		best = {"position": from + _crack_dir * crack_segment_length * 0.4, "normal": up}
	var to: Vector3 = best["position"]
	var n: Vector3 = best["normal"]
	var step := to - from
	if step.length_squared() > 0.0001:
		_crack_dir = (step - n * step.dot(n)).normalized()
	_crack.append(to)
	_crack_normals.append(n)
	_crack_decal(from, to, (up + n).normalized())
	_place_tip()


## The node's own surface under `p` (casting in along -`n` from outside it): its position and
## normal, in node space. Empty if the cast misses it.
func _surface_at(p: Vector3, n: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(to_global(p + n * 0.6), to_global(p - n * 0.6), collision_layer)
	var hit_result := get_world_3d().direct_space_state.intersect_ray(query)
	if hit_result.is_empty() or hit_result["collider"] != self:
		return {}
	return {"position": to_local(hit_result["position"]),
		"normal": (global_basis.inverse() * (hit_result["normal"] as Vector3)).normalized()}


## Whether a chunk lies under the crack: near it seen face-on, and on the struck side.
func _crack_crosses(chunk: MeshInstance3D, path: Array, normals: Array) -> bool:
	var aabb := chunk.get_aabb()
	var centre := to_local(chunk.global_transform * aabb.get_center())
	if (centre - _shape_centre).dot(_crack_normal) < -0.1:
		return false
	var radius := aabb.size[aabb.get_longest_axis_index()] * 0.5
	for i in path.size() - 1:
		var up: Vector3 = ((normals[i] as Vector3) + (normals[i + 1] as Vector3)).normalized()
		var d: Vector3 = centre - Geometry3D.get_closest_point_to_segment(centre, path[i], path[i + 1])
		if (d - up * d.dot(up)).length() < radius:
			return true
	return false


## A basis whose Y is `up` (decals project along Y) and Z runs along `along`.
func _face_basis(along: Vector3, up: Vector3) -> Basis:
	var x := up.cross(along).normalized()
	if x.length_squared() < 0.5:
		x = up.cross(Vector3.FORWARD if absf(up.z) < 0.9 else Vector3.RIGHT).normalized()
	return Basis(x, up, x.cross(up))


func _crack_decal(a: Vector3, b: Vector3, up: Vector3) -> void:
	if a.distance_to(b) < 0.01:
		return
	var d := Decal.new()
	d.texture_albedo = _crack_textures(chip_color).pick_random()
	# deep enough to reach the mesh in the hollows the collision spans; a little longer than the
	# segment so neighbours overlap
	d.size = Vector3(0.32, 0.9, a.distance_to(b) * 1.25)
	d.normal_fade = 0.3
	d.cull_mask = WORLD_LAYER  # not the held tool (render layer 2)
	notches.add_child(d)
	d.transform = Transform3D(_face_basis(b - a, up), (a + b) * 0.5)


## The crack's tip: a pale spot of freshly broken stone (the rock's own colour, lighter), gently
## pulsing so it's easy to find.
func _place_tip() -> void:
	if _crack_tip == null:
		_crack_tip = Decal.new()
		_crack_tip.texture_albedo = _notch_texture()
		_crack_tip.texture_emission = _notch_texture()
		_crack_tip.modulate = chip_color.lightened(0.3)
		_crack_tip.size = Vector3(0.22, 0.9, 0.22)
		_crack_tip.normal_fade = 0.3
		_crack_tip.cull_mask = WORLD_LAYER
		notches.add_child(_crack_tip)
		var pulse := _crack_tip.create_tween().set_loops()
		pulse.tween_property(_crack_tip, "emission_energy", 0.35, 0.5).set_trans(Tween.TRANS_SINE)
		pulse.tween_property(_crack_tip, "emission_energy", 0.05, 0.5).set_trans(Tween.TRANS_SINE)
	_crack_tip.transform = Transform3D(_face_basis(_crack_dir, _crack_normals[-1]), _crack[-1])


## The tip goes out; the crack's decals stay as a scar until the node respawns.
func _retire_tip() -> void:
	if _crack_tip:
		_crack_tip.queue_free()
		_crack_tip = null


## Stone colour (html) -> four crack textures in shades of it: a deep, dark jagged line along the
## texture's length (with a couple of short branches), edged with a pale rim of chipped stone so
## it reads as cut into the rock rather than drawn on it.
static var _crack_tex := {}

static func _crack_textures(stone: Color) -> Array:
	var key := stone.to_html()
	if _crack_tex.has(key):
		return _crack_tex[key]
	# the chipped rim is what makes it read on dark stone, so the darker the stone, the paler it
	var rim := stone.lightened(0.25 + (1.0 - stone.get_luminance()) * 0.25)
	var shades := [rim, stone.darkened(0.7), stone.darkened(0.9)]  # rim, crack, its deepest middle
	var widths := [5.4, 3.4, 1.4]  # px of 32 across the decal's 0.32 m
	var alphas := [0.6, 0.97, 1.0]
	var out := []
	const W := 32
	const H := 128
	for v in 4:
		var albedo := Image.create_empty(W, H, false, Image.FORMAT_RGBA8)
		# a wandering line: it drifts and changes direction smoothly, with the odd sharp kink
		var x := W * 0.5
		var drift := 0.0
		var path := PackedFloat32Array()
		for y in H:
			drift = clampf(drift * 0.88 + randf_range(-0.5, 0.5) + (randf_range(-2.0, 2.0) if randf() < 0.05 else 0.0), -1.4, 1.4)
			x = clampf(x + drift, 9.0, W - 9.0)
			path.append(x)
		var branches := []  # [start row, x per row]
		for start in [36 + v * 9, 82 - v * 5]:
			var bx := path[start]
			var side := 1.0 if randf() < 0.5 else -1.0
			var row := PackedFloat32Array()
			for by in range(start, mini(start + randi_range(12, 22), H - 6)):
				bx = clampf(bx + side * randf_range(0.4, 1.2), 4.0, W - 4.0)
				row.append(bx)
			branches.append([start, row])
		for pass_ in 3:  # rim, then the crack over it, then its deepest middle
			var colour: Color = shades[pass_]
			for y in H:
				var fade := clampf(minf(y, H - 1 - y) / 10.0, 0.0, 1.0)  # soft ends where segments overlap
				_crack_dot(albedo, path[y], y, widths[pass_], Color(colour, alphas[pass_] * fade))
			for b in branches:  # thinner, tapering away
				var row: PackedFloat32Array = b[1]
				for i in row.size():
					var y: int = b[0] + i
					var taper := 1.0 - float(i) / row.size() * 0.7
					var fade := clampf(minf(y, H - 1 - y) / 10.0, 0.0, 1.0)
					_crack_dot(albedo, row[i], y, widths[pass_] * 0.5 * taper, Color(colour, alphas[pass_] * fade))
		albedo.generate_mipmaps()
		out.append(ImageTexture.create_from_image(albedo))
	_crack_tex[key] = out
	return out


## One row of a line `radius` px wide around `cx`, antialiased, never lightening what's there.
static func _crack_dot(img: Image, cx: float, y: int, radius: float, color: Color) -> void:
	for px in range(floori(cx - radius - 1.0), ceili(cx + radius + 1.0)):
		if px < 0 or px >= img.get_width():
			continue
		var cover := clampf(radius + 0.5 - absf(px + 0.5 - cx), 0.0, 1.0)
		var a := color.a * cover
		if a > img.get_pixel(px, y).a:
			img.set_pixel(px, y, Color(color, a))


# --- weak point -----------------------------------------------------------------------------

var _weak: MeshInstance3D


func _build_weak_point() -> void:
	if not weak_point or cracks:
		return
	_weak = MeshInstance3D.new()
	_weak.name = "WeakPoint"
	var gem := SphereMesh.new()  # 4 segments x 2 rings = a little diamond
	gem.radial_segments = 4
	gem.rings = 2
	gem.radius = 0.055
	gem.height = 0.11
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = weak_point_color
	gem.material = mat
	_weak.mesh = gem
	_weak.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	visual.add_child(_weak)
	var pulse := _weak.create_tween().set_loops()
	pulse.tween_property(_weak, "scale", Vector3.ONE * 1.35, 0.45).set_trans(Tween.TRANS_SINE)
	pulse.tween_property(_weak, "scale", Vector3.ONE * 0.85, 0.45).set_trans(Tween.TRANS_SINE)
	_place_weak_point()


## Puts the spot on a random outward-facing side face of a random intact chunk.
func _place_weak_point() -> void:
	if _weak == null:
		return
	var spots: Array[Transform3D] = []
	for c in _intact_chunks():
		var arrays := c.mesh.surface_get_arrays(0)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] else PackedInt32Array()
		var count := idx.size() if not idx.is_empty() else verts.size()
		var to_node := visual.global_transform.affine_inverse() * c.global_transform  # chunk -> Visual space
		for i in range(0, count, 3):
			var a := to_node * verts[idx[i] if not idx.is_empty() else i]
			var b := to_node * verts[idx[i + 1] if not idx.is_empty() else i + 1]
			var d := to_node * verts[idx[i + 2] if not idx.is_empty() else i + 2]
			var n := (b - a).cross(d - a).normalized()
			var centre := (a + b + d) / 3.0
			var out := Vector3(centre.x, 0.0, centre.z).normalized()
			if absf(n.y) < 0.6 and n.dot(out) > 0.3:  # a side face, facing out from the middle
				spots.append(Transform3D(Basis.looking_at(-n, Vector3.UP if absf(n.y) < 0.95 else Vector3.FORWARD), centre + n * 0.03))
	if spots.is_empty():
		_weak.visible = false
		return
	var t: Transform3D = spots.pick_random()
	_weak.transform = Transform3D(t.basis, t.origin)
	_weak.visible = can_gather()


## A swing is on the weak point if its line passes close to the spot.
func _is_weak_hit(info: HitInfo) -> bool:
	if _weak == null or not _weak.visible:
		return false
	return _aimed_near(info, _weak.global_position, weak_point_radius)


## Whether the swing's line passes within `radius` of `point`.
func _aimed_near(info: HitInfo, point: Vector3, radius: float) -> bool:
	var dir := (info.position - info.from).normalized()
	var closest := info.from + dir * (point - info.from).dot(dir)
	return closest.distance_to(point) < radius


func _weak_hit_feedback(info: HitInfo) -> void:
	PopupText.spawn(get_parent(), _popup_pos() + Vector3(0, 0.6, 0), "Weak spot!", weak_point_color, 10)
	Juice.shake(2.0)
	Juice.hitstop(0.05)
	var spark := chips.duplicate() as CPUParticles3D
	get_parent().add_child(spark)
	spark.global_position = _weak.global_position
	spark.color = weak_point_color
	spark.amount = 18
	spark.initial_velocity_max = 5.0
	spark.restart()
	get_tree().create_timer(1.0).timeout.connect(spark.queue_free)
	_play(break_audio, hit_sfx, 1.45)


# --- respawn display ------------------------------------------------------------------------

func _process(_delta: float) -> void:
	if _respawn_timer == null:
		return
	var left := _respawn_timer.time_left
	var secs := ceili(left)
	_timer_label.text = "%d:%02d" % [secs / 60, secs % 60]
	var progress := clampf(1.0 - left / _regrow_time(), 0.0, 1.0)
	var c := Skills.color(skill)
	_ghost_outline.set_shader_parameter("color", Color(c, lerpf(0.2, ghost_alpha, progress)))


## Built once, while the node is intact: a countdown label and an outline-only copy of every
## mesh in Visual (see shaders/ghost_*.gdshader), both hidden until the node is depleted.
func _build_respawn_display() -> void:
	_timer_label = Label3D.new()
	_timer_label.name = "RespawnTimer"
	_timer_label.position = Vector3(0, popup_height + 0.35, 0)
	_timer_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_timer_label.no_depth_test = true
	_timer_label.pixel_size = 0.004
	_timer_label.font_size = 64
	_timer_label.outline_size = 16
	_timer_label.outline_modulate = Color(0, 0, 0, 0.85)
	_timer_label.visibility_range_end = respawn_display_range
	_timer_label.visible = false
	add_child(_timer_label)

	_ghost_outline = ShaderMaterial.new()
	_ghost_outline.shader = GHOST_OUTLINE_STENCIL if ghost_silhouette else GHOST_OUTLINE
	var mask := ShaderMaterial.new()
	mask.shader = GHOST_MASK_STENCIL if ghost_silhouette else GHOST_MASK
	mask.render_priority = -1  # every ghost's mask before any outline, so insides stay hidden
	mask.next_pass = _ghost_outline
	_ghost = Node3D.new()
	_ghost.name = "RespawnGhost"
	_ghost.visible = false
	add_child(_ghost)
	for s in _surfaces:
		if not s is MeshInstance3D:
			continue
		var g := MeshInstance3D.new()
		g.mesh = (s as MeshInstance3D).mesh
		g.material_override = mask
		g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_ghost.add_child(g)
		g.transform = global_transform.affine_inverse() * s.global_transform


func _set_respawn_display(on: bool) -> void:
	_timer_label.visible = on and show_respawn_timer
	_ghost.visible = on and show_respawn_ghost
	set_process(on)
	if on:
		_process(0.0)


# --- feedback -------------------------------------------------------------------------------

## A dark bite mark projected onto the surface where the tool went in. Cleared on respawn.
func _notch_at(info: HitInfo) -> void:
	var decal := Decal.new()
	decal.texture_albedo = _notch_texture()
	decal.modulate = NOTCH_COLOR
	decal.size = Vector3(0.24, 0.3, 0.24)
	decal.normal_fade = 0.4
	decal.cull_mask = WORLD_LAYER  # not the held tool (render layer 2)
	notches.add_child(decal)
	var up := info.normal
	var side := up.cross(Vector3.FORWARD if absf(up.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
	var rot := Basis(side, up, side.cross(up)).rotated(up, randf() * TAU)
	# relative to Visual at rest: the hit has just nudged it, and it springs back
	decal.transform = global_transform.affine_inverse() * Transform3D(rot, info.position)


static var _notch_tex: Texture2D

static func _notch_texture() -> Texture2D:
	if _notch_tex == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		g.add_point(0.55, Color(1, 1, 1, 0.9))
		var tex := GradientTexture2D.new()
		tex.gradient = g
		tex.fill = GradientTexture2D.FILL_RADIAL
		tex.fill_from = Vector2(0.5, 0.5)
		tex.fill_to = Vector2(1.0, 0.5)
		tex.width = 64
		tex.height = 64
		_notch_tex = tex
	return _notch_tex


## Chips and dust (and sparks) where the tool went in, and a pebble or two on the ground.
## `strength` above 1 for bigger hits.
func _hit_effects(info: HitInfo, strength: float) -> void:
	if hit_fx == null:
		_chips_at(info)
		return
	var swing := (info.position - info.from).normalized()
	var sparks := roundi(spark_amount * (2.0 if strength > 1.2 else 1.0))
	HitFx.spawn(hit_fx, get_parent(), info.position, info.normal, swing, chip_color,
		ore_color if cracks else Color(0, 0, 0, 0), strength, sparks)
	_add_rubble(info.position, 1 if strength <= 1.0 else 2)


# --- lingering rubble -----------------------------------------------------------------------

var _rubble_mm: MultiMeshInstance3D


func _build_rubble() -> void:
	if lingering_rubble <= 0:
		return
	var pebble := SphereMesh.new()  # 6 x 3 = a low-poly lump
	pebble.radius = 0.06
	pebble.height = 0.08
	pebble.radial_segments = 6
	pebble.rings = 3
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 1.0
	pebble.material = mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = pebble
	mm.instance_count = lingering_rubble
	mm.visible_instance_count = 0
	_rubble_mm = MultiMeshInstance3D.new()
	_rubble_mm.name = "LingeringRubble"
	_rubble_mm.multimesh = mm
	_rubble_mm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_rubble_mm)


## Drops `count` pebbles on the ground around the base, on the side `near` is on (mostly stone,
## some ore). Stops once the pile is full.
func _add_rubble(near: Vector3, count: int) -> void:
	if _rubble_mm == null:
		return
	var mm := _rubble_mm.multimesh
	var footprint := _footprint * 0.85  # the hull's widest; pebbles tuck in against the base
	var side := to_local(near) - _shape_centre
	side.y = 0.0
	if side.length_squared() < 0.001:
		side = Vector3(randf_range(-1, 1), 0, randf_range(-1, 1))
	var space := get_world_3d().direct_space_state
	for i in count:
		var n := mm.visible_instance_count
		if n >= mm.instance_count:
			return
		var p := side.normalized().rotated(Vector3.UP, randf_range(-0.9, 0.9)) * (footprint + randf_range(0.0, 0.45))
		var query := PhysicsRayQueryParameters3D.create(to_global(p + Vector3.UP * 1.5), to_global(p + Vector3.DOWN * 1.5), WORLD_LAYER, [get_rid()])
		var ground := space.intersect_ray(query)
		if ground:
			p = to_local(ground["position"])
		var s := randf_range(0.5, 1.6)
		var basis := Basis.from_euler(Vector3(randf(), randf(), randf()) * TAU).scaled(Vector3(s, s * 0.6, s))
		mm.set_instance_transform(n, Transform3D(basis, p + Vector3.UP * 0.02 * s))
		var tint := ore_color if cracks and randf() < 0.25 else chip_color
		mm.set_instance_color(n, tint.darkened(randf_range(0.0, 0.3)))
		mm.visible_instance_count = n + 1


func _chips_at(info: HitInfo) -> void:
	chips.global_position = info.position + info.normal * 0.05
	chips.direction = chips.global_basis.inverse() * (info.normal + Vector3.UP * 0.6).normalized()
	chips.restart()


func _setup_glow() -> void:
	for c in chunks.get_children():
		if c is MeshInstance3D:
			DayNightSky.make_glow(c)
			(c as MeshInstance3D).set_instance_shader_parameter("glow_tint", Color(glow_color, 1.0))
	var light := OmniLight3D.new()
	light.light_color = glow_color
	light.omni_range = 6.0
	light.omni_attenuation = 1.6
	light.shadow_enabled = false
	light.set_meta("night_energy", 1.4)
	light.light_energy = 0.0
	light.visible = false
	light.add_to_group("night_light")
	visual.add_child(light)  # goes when the node breaks, with the rest of Visual
	light.position = Vector3.UP * 0.9


## Applies draw_distance to every mesh and particle system in the node, and chunk_shadows to the
## chunks. The felled trunk and broken-off pieces are copies, so they inherit it.
func _limit_drawing(n: Node) -> void:
	for c in n.get_children():
		if c is GeometryInstance3D and draw_distance > 0.0:
			var g := c as GeometryInstance3D
			g.visibility_range_end = draw_distance
			g.visibility_range_end_margin = 12.0
			g.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		if c is GeometryInstance3D and not chunk_shadows and c.get_parent() == chunks:
			(c as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_limit_drawing(c)


func _collect_surfaces(n: Node) -> void:
	for c in n.get_children():
		if c is GeometryInstance3D:
			_surfaces.append(c)
		_collect_surfaces(c)


func _play(player: AudioStreamPlayer3D, stream: AudioStream, pitch := 1.0) -> void:
	if stream == null:
		return
	player.stream = stream
	player.pitch_scale = pitch
	player.play()


func _flash() -> void:
	if _flash_tween:
		_flash_tween.kill()
	_flash_tween = create_tween()
	_flash_tween.tween_method(func(v: float) -> void:
		for s in _surfaces:
			s.set_instance_shader_parameter("flash", v), 0.7, 0.0, 0.09)


## "Impact": shove the visual away from the player and squash it slightly, then spring back.
func _nudge(away: Vector3) -> void:
	if _nudge_tween:
		_nudge_tween.kill()
	visual.position = away * 0.06
	visual.scale = Vector3(1.04, 0.95, 1.04)
	_nudge_tween = create_tween().set_parallel()
	_nudge_tween.tween_property(visual, "position", Vector3.ZERO, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_nudge_tween.tween_property(visual, "scale", Vector3.ONE, 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
