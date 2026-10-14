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
## How hard broken-off chunks fly away (m/s).
@export var debris_speed := 3.0

@export_group("Audio")
@export var hit_sfx: AudioStream
@export var break_sfx: AudioStream
## How much higher-pitched each hit gets as the node weakens (escalation).
@export_range(0.0, 0.5) var stress_pitch := 0.15

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
## The timer is hidden beyond this distance from the camera, to avoid clutter.
@export var respawn_display_range := 30.0

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
	chips.color = chip_color
	burst.color = burst_color
	hits_left = max_hits
	_reset_visuals()
	_build_respawn_display()
	set_process(false)
	# applies any saved state now; older saves keyed nodes by scene path, so carry those over
	var path_key := StringName("node:%s" % get_path())
	if save_id.is_empty():
		SaveGame.register(path_key, self)
	else:
		SaveGame.register(StringName("node:" + save_id), self, path_key)


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


## Called by the player on the impact frame of a swing. Returns true if the tool bit in
## (the player then holds it there and calls pull()), false if it bounced off.
func hit(info: HitInfo) -> bool:
	if hits_left <= 0:
		return false
	if not can_gather():
		_deflect(info)
		return false
	# the smithy's sharper tools: sometimes a hit counts twice
	var double := randf() < Village.stat(&"double_hit_chance")
	hits_left = maxi(hits_left - (2 if double else 1), 0)
	SaveGame.mark_dirty()
	var stress := 1.0 - float(hits_left) / max_hits  # 0 -> 1 as it depletes

	_play(audio, hit_sfx, 1.0 + stress * stress_pitch - (0.12 if double else 0.0))
	_flash()
	_nudge(info.away() * (1.6 if double else 1.0))
	_chips_at(info)
	Juice.shake(shake_hit + stress * 1.5 + (1.5 if double else 0.0))
	Juice.hitstop(hitstop_hit + (0.035 if double else 0.0))
	if double:
		PopupText.spawn(get_parent(), _popup_pos() + Vector3(0, 0.35, 0), "Sharp!", SHARP_COLOR, 9)
	_award_xp(xp_per_hit * (2 if double else 1))

	if hits_left == 0:
		_break(info)
	else:
		_notch_at(info)
	return true


## Called by the player when the tool is yanked back out after biting in: the node tugs
## toward the player and the piece the tool bit into tears out, flying toward the camera.
func pull(info: HitInfo) -> void:
	if hits_left <= 0:
		return  # broke on this hit — the break already threw everything
	var stress := 1.0 - float(hits_left) / max_hits
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
	_respawn_after(respawn_time)


## The depleted look (rubble / stump, no collision) without any of the break effects.
func _show_depleted() -> void:
	set_highlighted(false)
	visual.visible = false
	rubble.visible = true
	collision.set_deferred("disabled", true)


func _respawn_after(seconds: float) -> void:
	_respawn_timer = get_tree().create_timer(seconds)
	_set_respawn_display(true)
	await _respawn_timer.timeout
	_respawn_timer = null
	_set_respawn_display(false)
	hits_left = max_hits
	_reset_visuals()
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


func _reset_visuals() -> void:
	for c in chunks.get_children():
		c.visible = true
	for n in notches.get_children():
		n.queue_free()
	visual.visible = true
	rubble.visible = false
	collision.set_deferred("disabled", false)
	burst.position = _burst_home
	break_audio.position = _break_audio_home


func _drop_count() -> int:
	var extra := int(Village.stat(&"extra_logs")) if skill == &"woodcutting" else 0  # the woodcutter's lodge
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
	get_parent().add_child(felled)
	felled.global_transform = global_transform.orthonormalized()
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
	var t := felled.create_tween()
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
	get_parent().add_child(body)
	body.global_transform = xform
	var jitter := Vector3(randf_range(-1, 1), randf_range(0, 1), randf_range(-1, 1)) * 0.4
	body.linear_velocity = (push + Vector3.UP * 0.8 + jitter).normalized() * speed
	body.angular_velocity = Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * 6.0

	var t := body.create_tween()
	t.tween_interval(DEBRIS_LIFETIME)
	t.tween_property(piece, "scale", Vector3.ONE * 0.01, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	t.tween_callback(body.queue_free)


# --- respawn display ------------------------------------------------------------------------

func _process(_delta: float) -> void:
	if _respawn_timer == null:
		return
	var left := _respawn_timer.time_left
	var secs := ceili(left)
	_timer_label.text = "%d:%02d" % [secs / 60, secs % 60]
	var progress := 1.0 - left / respawn_time
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
	_ghost_outline.shader = GHOST_OUTLINE
	var mask := ShaderMaterial.new()
	mask.shader = GHOST_MASK
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
	decal.global_transform = Transform3D(rot, info.position)


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


func _chips_at(info: HitInfo) -> void:
	chips.global_position = info.position + info.normal * 0.05
	chips.direction = chips.global_basis.inverse() * (info.normal + Vector3.UP * 0.6).normalized()
	chips.restart()


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
