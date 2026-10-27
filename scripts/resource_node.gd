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
## How far up a tree's trunk the soil and moss at its foot reach (m; see _dress).
const TRUNK_FOOT := 0.45
const GHOST_OUTLINE := preload("res://shaders/ghost_outline.gdshader")
const GHOST_MASK := preload("res://shaders/ghost_mask.gdshader")
const GHOST_OUTLINE_STENCIL := preload("res://shaders/ghost_outline_stencil.gdshader")
const GHOST_MASK_STENCIL := preload("res://shaders/ghost_mask_stencil.gdshader")
const DEFLECT_SFX := preload("res://audio/stone_hit.tres")
const DEFLECT_COLOR := Color("ff8a7a")
## The tool's ring per tier above stone (_tool_ring), from tools/synth_forge.py.
const TOOL_RINGS: Array[AudioStream] = [preload("res://audio/forge/ring_copper.wav"),
	preload("res://audio/forge/ring_iron.wav"), preload("res://audio/forge/ring_crystal.wav")]
## The sparks' colour per tool tier: stone and copper the usual hot orange (blank), iron white-hot,
## crystal violet.
const SPARK_TINTS: Array[Color] = [Color(0, 0, 0, 0), Color(0, 0, 0, 0), Color(1.0, 0.95, 0.82), Color(0.82, 0.6, 1.0)]
## A pause longer than this between hits ends a streak (Village stat streak_double).
const STREAK_GAP_MSEC := 3000
## The skill rating popup on an under-levelled hit that barely bit.
const UNDER_COLOR := Color("ffc27a")
const SHARP_COLOR := Color("ffd27a")
## The impact star's tint: a plain hit, a crack tip (and splits).
const STAR_HIT := Color(1.0, 0.97, 0.9)
const STAR_TIP := Color(1.0, 0.78, 0.42)
const WORLD_LAYER := 1
## Physics layer 4: debris collides with the world but not the player (layer 2) or pickups.
const DEBRIS_LAYER := 1 << 3
const DEBRIS_LIFETIME := 1.6
## The felled piece counts as landed once it leans past this (dot of its up axis with world up).
const LANDED_TILT := 0.35
const FELLED_LINGER := 2.5
const FELLED_SHAPE_SCALE := 0.6
## A piece split off along a crack moves at this times debris_speed (gently: it's big).
const SPLIT_SPEED := 0.7
## How much quieter the plain hit plays under a crack tip splitting, and under a piece splitting
## off (or the break), so big moments stand out instead of piling up (dB).
const HIT_DUCK_TIP := -6.0
const HIT_DUCK_SPLIT := -9.0
## A crack creaking on (a hit on the cracked piece, not on a tip) plays this much quieter (dB).
const CRACK_CREAK_DB := -12.0
## What the crack did on this hit, for _hit_sounds.
enum { CRACK_NONE, CRACK_CREAK, CRACK_TIP }
## Render layer 11: a piece being cracked, with seam_crack_on_piece_only (its decals draw only there).
const CRACKING_LAYER := 1 << 10

@export_group("Gathering")
@export var item: StringName = &"wood"
## Leave empty to use the item's icon from art/icons/ (see Items).
@export var item_icon: Texture2D
@export var tool_type: StringName = &"axe"
## The tool tier that bites this node (Tools.LADDER: 0 stone, 1 copper, 2 iron, 3 crystal).
## Below it, hits bounce off.
@export_range(0, 3) var tool_tier := 0
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
## How hard the node is: below this level you still gather, but with less power per hit and
## tighter clean-cut / crack-tip / weak-point windows (Skills.UNDER_*), and more XP when it breaks.
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

@export_group("Notch")
## Trees: the axe carves a notch into the trunk's own mesh (Body_Trunk, a ringed trunk from
## make_models.py) instead of leaving bite marks, and the tree falls from the notch, sideways to
## the swinger, leaving the cut stump behind. Replaces the weak point. See TrunkCarve.
@export var carve_notch := false
## How deep the notch is by the time the tree falls, as a share of the trunk's radius.
@export_range(0.3, 0.85) var notch_depth := 0.65
## The heights (m, up the trunk) the notch can sit at: the first hit's height, clamped to this.
@export var notch_band := Vector2(0.6, 1.4)
## A swing aimed into the notch's mouth is a clean cut: it counts this many extra hits, doubles
## the XP and throws a big chip. How close to the middle of the mouth it must aim (m, across the
## line of the swing), and how deep the notch must be first (share of the fall depth).
@export_range(0, 5) var clean_cut_extra_hits := 1
@export var clean_cut_radius := 0.13
@export_range(0.0, 1.0) var clean_cut_after := 0.25
@export var clean_cut_color := Color("f3d9a4")
## Flakes of bark peel off round the notch's rim as it grows, in this colour (chips are chip_color,
## the cut wood).
@export var bark_color := Color("5f4029")
## How thick the trunk's bark is (m): a hit strips a blaze of it before the axe cuts into the wood
## beneath (see TrunkCarve), and the slabs that fly off are this thick.
@export var bark_thickness := 0.025
## Every hit shakes the canopy (m it swings out at first) and shakes a few leaves loose.
@export var canopy_shake := 0.08
@export_range(0, 32) var leaves_per_hit := 6
## Once this share of the hits is done the tree sways and creaks on every hit; the last hit's
## crack holds it leaning on the hinge for `fell_pause` (s) before it goes.
@export_range(0.0, 1.0) var sway_after := 0.6
@export var sway_degrees := 1.6
@export var fell_pause := 0.4
@export var fell_lean_degrees := 4.0
## The trunk creaking as it sways and leans (and, quieter, as the notch nears the limit), and the
## whoosh of it falling.
@export var creak_layers: SoundLayers
@export var fall_layers: SoundLayers
## A clean cut's snap (also, pitched down, the trunk giving way on the last hit), and the felled
## tree landing (instead of land_sfx).
@export var clean_layers: SoundLayers
@export var land_layers: SoundLayers

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
## Seam cracks draw only on the piece being cracked, not on what's round it (a crystal's crack
## stays on the crystal instead of spilling onto the stone it grows from). Boulders leave it off,
## so the crack shows on both sides of the seam.
@export var seam_crack_on_piece_only := false
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
## How white the whole node flashes on a hit (0..1). Keep it low on big nodes: on a boulder a
## full flash whites out the screen and drowns the impact star.
@export_range(0.0, 1.0) var flash_strength := 0.7
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
## How big the last hit was, for the swinger's camera kick and tool quiver: 1 for a plain hit,
## more for a crack tip / weak spot / sharp hit (1.5), a split (2) or the break (2.5).
var last_impact := 1.0
var _crack_sound := 0  # CRACK_* : what this hit's crack did, for _hit_sounds
var _crack_step := 0  # ... and how far along it is (each step a little higher)
var _cut := 0.0  # the fraction of a hit (under-levelled) carried over to the next one
var _ring: AudioStreamPlayer3D  # the tool's ring (_tool_ring), made on first use
var _streak := 0  # biting hits in a row on this node (the Crystal Forge's streak_double)
var _last_hit_msec := -100000
var _surfaces: Array[GeometryInstance3D] = []
## The place's dressing (NodeTheme.look()): set by the spawner before the node enters the tree.
var look: Array[Vector4] = []
## A rare look (ProcgenMap.rares), if this is the one: its bonus drops and XP.
var rare: NodeTheme
var _flash_tween: Tween
var _nudge_tween: Tween
var _burst_home := Vector3.ZERO
var _break_audio_home := Vector3.ZERO
var _respawn_timer: SceneTreeTimer
var _timer_label: Label3D
var _ghost: Node3D
var _ghost_outline: ShaderMaterial
var _carve: TrunkCarve  # carve_notch: the notch in the trunk
var _trunk: MeshInstance3D  # ... the trunk it's carved into
var _trunk_rest := Transform3D.IDENTITY  # ... where the trunk sits in the node, at rest
var _stump: MeshInstance3D  # ... and what's left of it once the tree is down
var _clean := false  # the last hit was a clean cut (its chip comes out big)
var _canopy := {}  # canopy mesh -> its rest position (carve_notch trees shake it on a hit)
var _leaves: CPUParticles3D
var _shake_tween: Tween
var _sway_tween: Tween


func _ready() -> void:
	add_to_group("gatherable")
	_apply_model()
	_setup_carve()
	_burst_home = burst.position
	_break_audio_home = break_audio.position
	_collect_surfaces(visual)
	_dress(self)
	_fit_collision()
	if not _links.is_empty():
		_ground_rock()
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
	var seam_lines := {}  # chunk name -> its outline, in node space
	for m in inst.find_children("*", "MeshInstance3D", true, false):
		var xform := Transform3D.IDENTITY  # relative to the model root (it isn't in the tree)
		var n: Node = m
		while n != inst:
			xform = (n as Node3D).transform * xform if n is Node3D else xform
			n = n.get_parent()
		if m.name.to_lower().begins_with("seam_"):
			seam_lines["Chunk_" + m.name.substr(5)] = _seam_loop(m.mesh, xform)
			continue
		var dest := ""
		for prefix in MODEL_PARTS:
			if m.name.to_lower().begins_with(prefix):
				dest = MODEL_PARTS[prefix]
		if dest.is_empty():
			continue
		m.get_parent().remove_child(m)
		m.owner = null
		get_node(dest).add_child(m)
		m.transform = xform
		m.material_override = PaletteMaterial.for_mesh(m.mesh)
	inst.free()
	for c in chunks.get_children():
		var loops: Array = seam_lines.get(String(c.name), [])
		if not loops.is_empty():
			_seams[c] = loops
	_load_links()


## A Seam_* line mesh (pairs of points) as ordered closed loops, in node space. Usually one; a
## piece walled in by others on all sides (a column in the middle) has one round its top and
## another round its foot.
static func _seam_loop(mesh: Mesh, xform: Transform3D) -> Array[PackedVector3Array]:
	var arrays := mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] else PackedInt32Array(range(verts.size()))
	var links := {}  # vertex -> the vertices it joins
	for i in range(0, idx.size() - 1, 2):
		links.get_or_add(idx[i], []).append(idx[i + 1])
		links.get_or_add(idx[i + 1], []).append(idx[i])
	var loops: Array[PackedVector3Array] = []
	var seen := {}
	for start in links:
		if seen.has(start):
			continue
		var loop := PackedVector3Array()
		var prev := -1
		var at: int = start
		while not seen.has(at):  # round this loop
			seen[at] = true
			loop.append(xform * verts[at])
			var next := -1
			for v in links[at]:
				if v != prev and not seen.has(v):
					next = v
					break
			if next == -1:
				break
			prev = at
			at = next
		if loop.size() >= 3:
			loops.append(loop)
	return loops


func _setup_carve() -> void:
	if not carve_notch:
		return
	_trunk = visual.get_node_or_null("Body/Body_Trunk") as MeshInstance3D
	if _trunk == null or not _trunk.mesh is ArrayMesh:
		push_warning("%s: carve_notch needs a Body_Trunk mesh" % name)
		return
	_carve = TrunkCarve.new(_trunk.mesh, notch_band, bark_thickness)
	_trunk_rest = global_transform.affine_inverse() * _trunk.global_transform
	for m in _trunk.get_parent().get_children():
		if m is MeshInstance3D and m != _trunk:
			_canopy[m] = (m as Node3D).position
	_leaves = _make_leaves()


func _make_notches() -> Node3D:
	var n := Node3D.new()
	n.name = "Notches"
	$Visual.add_child(n)
	return n


func is_available() -> bool:
	return hits_left > 0


## False when the player's tool is too weak for this node — hits will bounce off.
func can_gather() -> bool:
	return Tools.can_work(tool_type, tool_tier)


## "Needs Iron pick": shown on a deflect and when the crosshair is on a node you can't work yet.
func needs_text() -> String:
	return "Needs %s" % Tools.display_name(tool_type, tool_tier)


## Your skill is below the node's rating: it can be gathered, just slowly.
func is_under_levelled() -> bool:
	return Skills.levels_under(skill, required_level) > 0


## "Mining 15": the node's rating, shown when you're under it.
func under_text() -> String:
	return "%s %d" % [Skills.display_name(skill), required_level]


## Hit power left after the under-level penalty (1.0 at or above the rating).
func _power_scale() -> float:
	return Skills.under_scale(skill, required_level, Skills.UNDER_POWER_PER_LEVEL, Skills.UNDER_POWER_FLOOR)


## How wide the technique windows are after the under-level penalty (1.0 at or above the rating).
func _window_scale() -> float:
	return Skills.under_scale(skill, required_level, Skills.UNDER_WINDOW_PER_LEVEL, Skills.UNDER_WINDOW_FLOOR)


## Called by the player while the crosshair is on this node.
func set_highlighted(on: bool) -> void:
	for s in _surfaces:
		s.set_instance_shader_parameter("highlight", 1.0 if on else 0.0)
	if on and _weak and not _weak.visible and can_gather():  # got a better tool since it was hidden
		_place_weak_point()


## Called by the player on the impact frame of a swing. Returns true if the tool bit in
## (the player then holds it there and calls pull()), false if it bounced off.
func hit(info: HitInfo) -> bool:
	if hits_left <= 0:
		return false
	if not can_gather():
		_deflect(info)
		return false
	var before := hits_left
	# a better tool than the node needs bites deeper (+1 cut per tier above); under-levelled, every
	# hit bites less (the fraction carries over to the next hit)
	_cut += (1.0 + Tools.tiers_above(tool_type, tool_tier)) * _power_scale()
	var cuts := int(_cut)
	_cut -= cuts
	# the smithy's sharper tools: sometimes a hit counts twice; at the Crystal Forge, so does every
	# Nth biting hit in a row on this node. The weak point, crack tips and clean cuts add more.
	var now := Time.get_ticks_msec()
	if cuts == 0 or now - _last_hit_msec > STREAK_GAP_MSEC:
		_streak = 0
	_streak += 1 if cuts > 0 else 0
	_last_hit_msec = now
	var every := int(Village.stat(&"streak_double"))
	var streak_hit := every > 0 and _streak > 0 and _streak % every == 0
	var double := cuts > 0 and (streak_hit or randf() < Village.stat(&"double_hit_chance"))
	var weak := _is_weak_hit(info)
	var tip := cracks and _is_tip_hit(info)
	_clean = _carve != null and _is_clean_cut(info)
	hits_left = maxi(hits_left - cuts - (1 if double else 0) - (weak_point_extra_hits if weak else 0)
		- (crack_tip_extra_hits if tip else 0) - (clean_cut_extra_hits if _clean else 0), 0)
	# under-levelled, a plain hit can fall short of a whole cut: it marks the node but takes nothing
	var bit := hits_left < before
	var fresh := bit and Tools.take_fresh(tool_type)  # the first bite of a just-forged tool
	if weak:
		_weak_hit_feedback(info)
	if _carve:
		_carve_hit(info, before - hits_left)
		_tree_reacts(info, 1.0 - float(hits_left) / max_hits)
	SaveGame.mark_dirty()
	var collapsed := 0
	if not _links.is_empty() and bit:
		collapsed = _knock_out(info, maxi(cuts, 1) + (1 if double else 0))  # (sets hits_left)
	var stress := 1.0 - float(hits_left) / max_hits  # 0 -> 1 as it depletes

	var pitch := 1.0 + stress * stress_pitch - (0.12 if double else 0.0)
	_crack_sound = 0  # (set by the crack code below; the sounds are played together at the end)
	_flash()
	_nudge(info.away() * (1.6 if double else 1.0))
	_hit_effects(info, 2.0 if fresh else 1.5 if tip or _clean else 1.0)
	if bit:
		_tool_ring(info)
	if fresh:
		ForgeCutscene.first_swing(get_parent(), info.position, info.normal, ForgeCutscene.tier_color(Tools.tier(tool_type)))
	Juice.shake(shake_hit + stress * 1.5 + (1.5 if double else 0.0))
	Juice.hitstop(hitstop_hit + (0.035 if double else 0.0))
	if double:
		PopupText.spawn(get_parent(), _popup_pos() + Vector3(0, 0.35, 0), "Sharp!", SHARP_COLOR, 9)
	if _clean:
		PopupText.spawn(get_parent(), _popup_pos() + Vector3(0, 0.6, 0), "Clean cut!", clean_cut_color, 10)
	elif not bit:  # under-levelled, and this one didn't bite: say why
		PopupText.spawn(get_parent(), _popup_pos(), under_text(), UNDER_COLOR, 7)
	_award_xp(xp_per_hit * (2 if double else 1) * (2 if weak or tip or _clean else 1))

	var split := hits_left > 0 and cracks and _links.is_empty() and _grow_crack(info, tip)
	if split:
		_split(info)  # the crack ran all the way across
	if collapsed > 0 and hits_left > 0:
		_collapse_feedback(info, collapsed)
	last_impact = 2.5 if hits_left == 0 else 2.0 if split or collapsed > 0 else 1.5 if tip or weak or double or _clean else 1.0
	if fresh:
		last_impact = 3.0
	_hit_sounds(info, pitch, double, split)
	if _clean and hits_left > 0:  # a sharper crack on top of the thunk
		if clean_layers:
			Sfx.play_at(clean_layers, info.position)
		else:
			_play(break_audio, hit_sfx, 1.35)

	if hits_left == 0:
		_break(info)
	else:
		if not _carve and _links.is_empty():  # (a rock of pieces shows the hit by losing them)
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
	if _carve:
		_throw_chip(info, tear, _clean)
	else:
		_spawn_fragment(info, tear)
	if _seams.is_empty() and _links.is_empty():  # (a boulder of pieces only loses them along cracks / where struck)
		_shed_chunks(stress, info, tear)


## This hit's sounds, chosen together so they don't pile up: the plain hit (ducked under a crack
## tip's split, further under a piece splitting off or the break), then the crack creaking on
## quietly, its tip splitting, or the piece splitting off. (tools/measure_mix.py mirrors this.)
func _hit_sounds(info: HitInfo, pitch: float, double: bool, split: bool) -> void:
	var duck := HIT_DUCK_SPLIT if split or hits_left == 0 else HIT_DUCK_TIP if _crack_sound == CRACK_TIP or _clean else 0.0
	if hit_layers:
		Sfx.play_at(hit_layers, info.position, pitch, duck + (2.0 if double else 0.0))
	else:
		_play(audio, hit_sfx, pitch)
	if split:
		Sfx.play_at(split_layers, info.position)
	elif _crack_sound == CRACK_TIP:
		Sfx.play_at(crack_layers, info.position, 1.0 + 0.12 * _crack_step)
	elif _crack_sound == CRACK_CREAK:
		Sfx.play_at(crack_layers, info.position, 1.0 + 0.12 * _crack_step, CRACK_CREAK_DB)
	_crack_sound = 0


## Too weak a tool: it bounces off — clank, small nudge, no damage, no XP.
func _deflect(info: HitInfo) -> void:
	_play(audio, DEFLECT_SFX, 1.8)
	_nudge(info.away())
	Juice.shake(0.5)
	PopupText.spawn(get_parent(), _popup_pos(), needs_text(), DEFLECT_COLOR)


## The tool's own ring under a biting hit: copper dull, iron bright, crystal a glassy chime.
func _tool_ring(info: HitInfo) -> void:
	var tier := Tools.tier(tool_type) if Tools.LADDER.has(tool_type) else 0
	if tier < 1 or tier > TOOL_RINGS.size():
		return
	if _ring == null:
		_ring = AudioStreamPlayer3D.new()
		_ring.bus = &"SFX"
		_ring.unit_size = 4.0
		add_child(_ring)
	_ring.global_position = info.position
	_ring.stream = TOOL_RINGS[tier - 1]
	_ring.volume_db = -10.0
	_ring.pitch_scale = randf_range(0.95, 1.05)
	_ring.play()


func _award_xp(amount: int, big := false) -> void:
	if amount <= 0:
		return
	if rare:
		amount = roundi(amount * rare.xp_scale)
	var gained := Skills.add_xp(skill, amount)
	if gained > 0:
		PopupText.spawn(get_parent(), _popup_pos() + Vector3(randf_range(-0.2, 0.2), 0.25 if big else 0.0, 0.0),
			"+%d" % gained, Skills.color(skill), 10 if big else 8, 0.08 if big else 0.0)


func _popup_pos() -> Vector3:
	return global_position + Vector3(0, popup_height, 0)


func _break(info: HitInfo) -> void:
	_clear_fault()
	_award_xp(roundi(xp_on_break * (1.0 + (Skills.UNDER_XP_BONUS if is_under_levelled() else 0.0))), true)
	if rare:
		PopupText.spawn(get_parent(), _popup_pos() + Vector3.UP * 0.55, "Rare find: %s!" % rare.title,
			Color(1.0, 0.85, 0.45), 9, 0.15)
	if _carve and clean_layers:  # the hinge giving way: a deep snap of the last fibres
		Sfx.play_at(clean_layers, info.position, 0.6, 3.0)
	else:
		_play(break_audio, break_sfx)
	for c in _intact_chunks():
		_pop_chunk(c, info.away(), debris_speed * 0.7)
	_show_depleted()
	Juice.shake(shake_break)
	Juice.hitstop(hitstop_break)
	if topple:
		var log_mesh: Mesh = null
		if _carve and _carve.is_started():
			var parts := _carve.split()
			_make_stump(parts["stump"])
			log_mesh = parts["log"]
		_topple(info, log_mesh)  # not awaited: the fall plays out while the respawn timer runs
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
	var d := {"respawn_left": _respawn_timer.time_left} if _respawn_timer else {"hits_left": hits_left}
	if not _links.is_empty() and not _respawn_timer:  # exactly which pieces are gone
		var gone := []
		for i in _pieces.size():
			if not _pieces[i].visible:
				gone.append(i)
		d["gone"] = gone
		d["spilled"] = _spilled
	if _carve and _carve.is_started():  # (a felled tree keeps its notch until it regrows: the stump)
		d["notch"] = _carve.to_dict()
	return d


func from_dict(d: Dictionary) -> void:
	if _carve and d.has("notch"):
		_carve.from_dict(d["notch"])
	if d.has("respawn_left"):
		hits_left = 0
		_show_depleted()
		if _carve and _carve.is_started():
			_make_stump(_carve.split()["stump"])
		_respawn_after(maxf(float(d["respawn_left"]), 0.1))
	elif d.has("hits_left"):
		hits_left = clampi(int(d["hits_left"]), 1, max_hits)
		if _carve and _carve.is_started():
			_trunk.mesh = _carve.carved()
		if d.has("gone") and not _links.is_empty():
			for i in d["gone"]:
				if int(i) < _pieces.size():
					_pieces[int(i)].visible = false
			_spilled = int(d.get("spilled", 0))
			_queue_refit()
			return
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
	for t: Tween in _loosen_tweens.values():
		t.kill()
	_loosen_tweens.clear()
	for c in _rest:
		c.transform = _rest[c]
	_rest.clear()
	for c in chunks.get_children():
		c.visible = true
		if c is VisualInstance3D:
			(c as VisualInstance3D).layers &= ~CRACKING_LAYER
	for n in notches.get_children():
		n.queue_free()  # (cracks too)
	_crack.clear()
	_crack_normals.clear()
	_crack_tip = null
	_clear_seam_crack()
	_seam_progress.clear()
	_queue_refit()
	if not _links.is_empty():
		_drops_owed = _drop_count()
		_spilled = 0
		_tough.clear()
		for piece in _tough_pieces:
			_tough[piece] = 1
		_place_fault.call_deferred()  # (after a saved rock's missing pieces are hidden)
		for k in 5:  # pebbles round its foot from the start
			_add_rubble(to_global(Vector3(randf_range(-1, 1), 0.3, randf_range(-1, 1))), 1)
	if _rubble_mm:
		_rubble_mm.multimesh.visible_instance_count = 0
	if _carve:
		_carve.reset()
		_trunk.mesh = _carve.original
		if _stump:
			rubble.remove_child(_stump)
			_stump.queue_free()
			_stump = null
		for c in rubble.get_children():
			c.visible = true
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
	if rare:
		extra += rare.bonus_drops
	return randi_range(drops_min, maxi(drops_min, drops_max)) + extra


func _spawn_drops(info: HitInfo) -> void:
	var toward_player := -info.away()
	var count := _drop_count() if _links.is_empty() else maxi(_drops_owed - _spilled, 1)
	for i in count:
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
## With `log_mesh` (a carved tree), that's the trunk from the notch up: it hinges over at the notch
## and falls sideways to the player.
func _topple(info: HitInfo, log_mesh: Mesh = null) -> void:
	var away := info.away() if log_mesh == null else _fall_direction(info)
	var hinge := 0.0 if log_mesh == null else (_trunk_rest * Vector3(0.0, _carve.ring, 0.0)).y
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
		if mesh == _trunk and log_mesh:
			piece.mesh = log_mesh
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
	# the node's own collision shape (the trunk) at full size; a carved tree's from the notch up
	var trunk := CollisionShape3D.new()
	trunk.shape = collision.shape
	trunk.transform = collision.transform
	if log_mesh and collision.shape is BoxShape3D:
		var box := collision.shape.duplicate() as BoxShape3D
		var top := collision.position.y + box.size.y * 0.5
		box.size.y = maxf(top - hinge, 0.2)
		trunk.shape = box
		trunk.position.y = (top + hinge) * 0.5
	felled.add_child(trunk)
	# top-heavy on purpose (canopy), so once it starts leaning it keeps going
	felled.center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	felled.center_of_mass = Vector3(0, height * 0.65, 0)
	felled.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_ON
	get_parent().add_child(felled)
	felled.global_transform = global_transform.orthonormalized()
	felled.reset_physics_interpolation()
	if log_mesh and fell_pause > 0.0:
		await _lean_on_hinge(felled, away, hinge)
		if not is_instance_valid(felled):
			return
	Sfx.play_at(fall_layers, global_position + Vector3.UP * (hinge + 1.5))
	# start it rotating around its *base* (the hinge on the stump), not its centre of mass —
	# otherwise the base skids along the ground and the fall loses all its energy
	var spin := Vector3.UP.cross(away).normalized() * topple_push
	felled.angular_velocity = spin
	felled.linear_velocity = spin.cross(Vector3.UP * (felled.center_of_mass.y - hinge))

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
	if land_layers:
		Sfx.play_at(land_layers, top)
	else:
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


## The cut tree holds for a moment, creaking over a few degrees on the hinge, before it goes.
func _lean_on_hinge(felled: RigidBody3D, away: Vector3, hinge: float) -> void:
	felled.freeze = true
	var pivot := global_transform * Vector3(0.0, hinge, 0.0)
	var start := felled.global_transform
	var axis := Vector3.UP.cross(away).normalized()
	Sfx.play_at(creak_layers, pivot, 0.8)
	var lean := func(angle: float) -> void:
		var turn := Transform3D(Basis(axis, angle), pivot) * Transform3D(Basis.IDENTITY, -pivot)
		felled.global_transform = turn * start
	var t := felled.create_tween().set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	t.tween_method(lean, 0.0, deg_to_rad(fell_lean_degrees), fell_pause).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await t.finished
	if is_instance_valid(felled):
		felled.freeze = false


## The tree reacts to a hit: the canopy shakes and drops a few leaves, and late in the chop
## (`stress` past sway_after) the whole tree sways away and back, creaking.
func _tree_reacts(info: HitInfo, stress: float) -> void:
	var away := info.away()
	if _shake_tween:
		_shake_tween.kill()
	var amp := canopy_shake * (1.0 + stress)
	_shake_tween = create_tween()
	_shake_tween.tween_method(func(t: float) -> void:
		var off := away * amp * sin(t * 28.0) * exp(-t * 6.0)
		for m: Node3D in _canopy:
			m.position = _canopy[m] + off * (0.6 + 0.4 * (m.get_index() % 3) / 2.0), 0.0, 0.8, 0.8)
	_shake_tween.tween_callback(func() -> void:
		for m: Node3D in _canopy:
			m.position = _canopy[m])
	if _leaves and leaves_per_hit > 0:
		_leaves.amount = maxi(leaves_per_hit + roundi(stress * leaves_per_hit), 1)
		_leaves.restart()
	if stress >= sway_after and hits_left > 0:
		var axis := Vector3.UP.cross(away).normalized()
		var big := deg_to_rad(sway_degrees) * (0.6 + stress)
		if _sway_tween:
			_sway_tween.kill()
		_sway_tween = create_tween()
		var local_axis := (global_basis.inverse() * axis).normalized()
		_sway_tween.tween_method(func(t: float) -> void:  # (the rotation alone: the hit's squash stays)
			visual.quaternion = Quaternion(local_axis, big * sin(t * 7.0) * exp(-t * 2.2)), 0.0, 1.6, 1.6)
		_sway_tween.tween_callback(func() -> void: visual.quaternion = Quaternion.IDENTITY)
		Sfx.play_at(creak_layers, global_position + Vector3.UP * 2.0, 0.9 + randf() * 0.2, -3.0 + 6.0 * (stress - sway_after))


## Leaves shaken loose from the canopy: a few at a time, fluttering down.
func _make_leaves() -> CPUParticles3D:
	if _canopy.is_empty():
		return null
	var box := AABB()
	var first := true
	for m: MeshInstance3D in _canopy:
		var b := _trunk_rest * _trunk.transform.affine_inverse() * m.transform * m.get_aabb()
		box = b if first else box.merge(b)
		first = false
	var p := CPUParticles3D.new()
	p.name = "Leaves"
	p.emitting = false
	p.one_shot = true
	p.explosiveness = 0.7
	p.lifetime = 2.6
	p.local_coords = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = box.size * Vector3(0.4, 0.25, 0.4)
	p.position = box.get_center() - Vector3.UP * box.size.y * 0.2
	p.direction = Vector3.DOWN
	p.spread = 70.0
	p.gravity = Vector3(0, -1.1, 0)
	p.initial_velocity_min = 0.2
	p.initial_velocity_max = 0.7
	p.damping_min = 0.4
	p.damping_max = 1.0
	p.angular_velocity_min = -240.0
	p.angular_velocity_max = 240.0
	p.particle_flag_rotate_y = true
	var leaf := BoxMesh.new()
	leaf.size = Vector3(0.09, 0.012, 0.06)
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 1.0
	leaf.material = mat
	p.mesh = leaf
	p.color = burst_color
	p.scale_amount_min = 0.7
	p.scale_amount_max = 1.3
	add_child(p)  # (not under Visual: it isn't one of the surfaces that flash)
	return p


## Which way a notched tree falls: sideways to the swinger and a little away, never onto them.
## Whichever side is clear of other trees, else either.
func _fall_direction(info: HitInfo) -> Vector3:
	var away := info.away()
	var sides: Array[Vector3] = [away.cross(Vector3.UP), -away.cross(Vector3.UP)]
	sides.shuffle()
	var space := get_world_3d().direct_space_state
	var from := global_position + Vector3.UP * 2.0
	for side in sides:
		var dir := (side + away * 0.35).normalized()
		var query := PhysicsRayQueryParameters3D.create(from, from + dir * 3.5, WORLD_LAYER, [get_rid()])
		if space.intersect_ray(query).is_empty():
			return dir
	return (sides[0] + away * 0.35).normalized()


# --- notch ----------------------------------------------------------------------------------

## The notch deepens toward the swinger (`cuts`: how many hits this one counted for), and the hit
## moves onto the notch's surface, where the axe really bites and the chips fly from, instead of
## the trunk's collision box.
func _carve_hit(info: HitInfo, cuts: int) -> void:
	var to_trunk := _trunk.global_transform.affine_inverse()
	var dir := to_trunk.basis * (info.from - info.position)
	dir.y = 0.0
	var y := (to_trunk * info.position).y
	var stripped := _blaze_area()
	_carve.hit(y, dir, notch_depth * cuts / max_hits)
	_trunk.mesh = _carve.carved()
	info.position = _trunk.global_transform * _carve.bite_point(dir)
	info.normal = (_trunk.global_basis * dir).normalized()
	# the bark that came away flies off in slabs, more the more of it went; then a flake or two
	# off the rim per hit as the notch grows
	var slabs := clampi(roundi((_blaze_area() - stripped) * 40.0), 0, 6)
	for i in slabs + cuts:
		_peel_bark(dir, i < slabs)


## How much bark the blaze has stripped so far (m of height, summed round the trunk's bins).
func _blaze_area() -> float:
	var total := 0.0
	for b in _carve.blaze:
		total += b
	return total / TrunkCarve.BINS


## A flake of bark breaking off the rim of the notch, a little to one side of `dir` (trunk space);
## with `slab`, a bigger piece of the bark the hit stripped, from anywhere on the blaze.
func _peel_bark(dir: Vector3, slab := false) -> void:
	var side := dir.normalized().rotated(Vector3.UP, randf_range(-0.9, 0.9) if slab else randf_range(-0.6, 0.6))
	var deep := _carve.depth_toward(side)
	var reach := _carve.blaze_toward(side)
	var y := _carve.ring + (randf_range(-reach, reach) if slab else randf_range(-0.04, deep / TrunkCarve.SLOPE_UP + 0.06))
	var at := Vector3(0.0, y, 0.0) + side * _carve.radius_at(_carve.ring, side)
	var flake := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(randf_range(0.06, 0.11), randf_range(0.07, 0.13), maxf(bark_thickness * 0.8, 0.012))
	if slab:
		box.size = Vector3(randf_range(0.09, 0.17), randf_range(0.1, 0.2), maxf(bark_thickness, 0.012))
	flake.mesh = box
	flake.material_override = NODE_SURFACE
	flake.set_instance_shader_parameter("albedo", bark_color.darkened(randf_range(0.0, 0.2)))
	var out := (_trunk.global_basis * side).normalized()
	_throw(flake, Transform3D(Basis.looking_at(-out), _trunk.global_transform * at + out * 0.02),
		out + Vector3.UP * 0.3, debris_speed * randf_range(0.4, 0.7))


## A clean cut: the swing is aimed into the mouth of a notch that's already well started, from
## (about) the side it was cut from.
func _is_clean_cut(info: HitInfo) -> bool:
	if not _carve.is_started():
		return false
	var to_trunk := _trunk.global_transform.affine_inverse()
	var dir := to_trunk.basis * (info.from - info.position)
	dir.y = 0.0
	var full := _carve.radius_at(_carve.ring, dir) * notch_depth
	var deep := _carve.depth_toward(dir)
	if deep < full * clean_cut_after:
		return false
	var mouth := _trunk.global_transform * (_carve.bite_point(dir) + dir.normalized() * deep * 0.5)
	return _aimed_near(info, mouth, clean_cut_radius * _window_scale())


## A wood chip flying out of the notch as the axe comes free: a flat wedge of cut wood, a big
## one off a clean cut.
func _throw_chip(info: HitInfo, push: Vector3, big: bool) -> void:
	var chip := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.11, 0.025, 0.07) * (1.8 if big else 1.0)
	chip.mesh = box
	chip.material_override = NODE_SURFACE
	chip.set_instance_shader_parameter("albedo", chip_color)
	var rot := Basis.from_euler(Vector3(randf_range(-0.4, 0.4), randf() * TAU, randf_range(-0.4, 0.4)))
	_throw(chip, Transform3D(rot, info.position + info.normal * 0.06), push, debris_speed * (1.0 if big else 0.8))


## The bottom of the carved trunk stays standing while the tree regrows.
func _make_stump(mesh: Mesh) -> void:
	for c in rubble.get_children():
		c.visible = false
	_stump = MeshInstance3D.new()
	_stump.name = "CutStump"
	_stump.mesh = mesh
	_stump.material_override = NODE_PALETTE
	rubble.add_child(_stump)
	_stump.transform = rubble.transform.affine_inverse() * _trunk_rest
	_dress(_stump)
	_limit_drawing(rubble)


# --- chunks ---------------------------------------------------------------------------------

## Pops chunks off until the visible amount matches how worn down the node is.
## The last chunk always stays on until the node actually breaks.
func _shed_chunks(stress: float, info: HitInfo, push: Vector3) -> void:
	var total := chunks.get_child_count()
	var should_be_gone := mini(floori(stress * total), total - 1)
	var intact := _intact_chunks()
	while total - intact.size() < should_be_gone and not intact.is_empty():
		# the piece being cracked comes off when its crack is done, not before
		var others := intact.filter(func(c: MeshInstance3D) -> bool: return c != _seam_piece)
		var nearest := _nearest(others if not others.is_empty() else intact, info.position)
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
	if chunk == _seam_piece:
		_clear_seam_crack()
	_seam_progress.erase(chunk)
	if chunk == _fault_piece:  # knocked out some other way: the fault opens up elsewhere
		_clear_fault()
		create_tween().tween_callback(_place_fault).set_delay(FAULT_DELAY)
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
	if _merged:
		piece.layers = _merged.layers  # (a stand-in for a piece of the merged mesh: drawn on its own now)
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
	_update_piece_mask()  # (now: the stand-ins' visibility has just changed)
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
			if not mesh.visible or mesh.mesh == null or mesh == _merged:
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


# --- breaking where struck ------------------------------------------------------------------
# A rock made of many small pieces (its model has a <name>.pieces.json saying which touch): every
# hit knocks out the piece struck and a few neighbours, anything left with no chain of pieces
# down to the ground falls (a collapse: undercut a ledge and it all comes down), and once
# SHATTER_AT of it is gone the rest breaks apart. Pieces with a good share of vein spill an ore
# as they come out; the shatter pays what's left.
# It's drawn as one mesh (Visual/Pieces, shaders/node_rock.gdshader), the pieces merged with
# their index in UV2 and a bit mask hiding the broken ones: one draw call however many pieces.
# The Chunk_* nodes stay as invisible stand-ins (render layers 0), for aiming, the collision
# hull and the copies thrown when they break off.

const ROCK_MATERIAL := preload("res://materials/node_rock.tres")
## The share of the pieces gone at which the rest shatters.
const SHATTER_AT := 0.35
## A piece reaching this low (node space, m) rests on the ground.
const PIECE_GROUND := 0.12

## Piece (MeshInstance3D) -> the pieces it touches. Empty for any other node.
var _links := {}
var _grounded := {}  # pieces resting on the ground -> true
var _ore_pieces := {}  # pieces carrying ore -> true
## The ore's own rules, from its .pieces.json: pieces rest only on pieces under them (columns,
## strata) rather than on any neighbour; the share gone at which it shatters; how many
## neighbours a hit takes besides the piece struck; and tough pieces that take two hits.
var _support_below := false
var _shatter_at := SHATTER_AT
var _knock := 1
var _tough_pieces: Array[MeshInstance3D] = []
var _tough := {}  # tough piece -> hits it still takes before it comes out
var _rest_y := {}  # piece -> the height of its middle at rest (node space)
## The pieces in the merged mesh's order (the shader's piece index), and that mesh.
var _pieces: Array[MeshInstance3D] = []
var _merged: MeshInstance3D
## How much ore this rock gives in all (rolled when it grows back), and how much it has spilled.
var _drops_owed := 0
var _spilled := 0
static var _merged_cache := {}  # model path -> ArrayMesh


func _load_links() -> void:
	_links.clear()
	_grounded.clear()
	_ore_pieces.clear()
	_tough_pieces.clear()
	var path := model.resource_path.get_basename() + ".pieces.json"
	if not FileAccess.file_exists(path):
		return
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not data is Dictionary or not data.has("links"):
		return
	var links: Dictionary = data["links"]
	for piece_name: String in links:
		var piece := chunks.get_node_or_null(piece_name) as MeshInstance3D
		if piece == null:
			continue
		var touching: Array[MeshInstance3D] = []
		for other: String in links[piece_name]:
			var o := chunks.get_node_or_null(other) as MeshInstance3D
			if o:
				touching.append(o)
		_links[piece] = touching
		if (chunks.transform * piece.transform * piece.get_aabb()).position.y < PIECE_GROUND:
			_grounded[piece] = true
	for piece_name: String in data.get("ore", []):
		var piece := chunks.get_node_or_null(piece_name) as MeshInstance3D
		if piece:
			_ore_pieces[piece] = true
	for piece_name: String in data.get("grounded", []):  # (resting on the part that never breaks)
		var piece := chunks.get_node_or_null(piece_name) as MeshInstance3D
		if piece:
			_grounded[piece] = true
	for piece_name: String in data.get("tough", []):
		var piece := chunks.get_node_or_null(piece_name) as MeshInstance3D
		if piece:
			_tough_pieces.append(piece)
	_support_below = data.get("support", "") == "below"
	_shatter_at = float(data.get("shatter_at", SHATTER_AT))
	_knock = int(data.get("knock", 1))
	for piece in _links:
		_rest_y[piece] = (chunks.transform * piece.transform * piece.get_aabb().get_center()).y
	_merge_pieces()


## Builds (or takes from the cache) the one mesh all the pieces are drawn as, and turns the pieces
## themselves into invisible stand-ins.
func _merge_pieces() -> void:
	_pieces.clear()
	for c in chunks.get_children():
		if _links.has(c):
			_pieces.append(c)
	_pieces.sort_custom(func(a: Node, b: Node) -> bool: return String(a.name) < String(b.name))
	var key := model.resource_path
	var mesh: ArrayMesh = _merged_cache.get(key)
	if mesh == null:
		var verts := PackedVector3Array()
		var normals := PackedVector3Array()
		var uvs := PackedVector2Array()
		var uv2s := PackedVector2Array()
		var colours := PackedColorArray()
		var indices := PackedInt32Array()
		for i in _pieces.size():
			var piece := _pieces[i]
			var xf := piece.transform
			for s in piece.mesh.get_surface_count():
				var arrays := piece.mesh.surface_get_arrays(s)
				var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				var n: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
				var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV] if arrays[Mesh.ARRAY_TEX_UV] else PackedVector2Array()
				var col: PackedColorArray = arrays[Mesh.ARRAY_COLOR] if arrays[Mesh.ARRAY_COLOR] else PackedColorArray()
				var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] else PackedInt32Array(range(v.size()))
				var base := verts.size()
				for k in v.size():
					verts.append(xf * v[k])
					normals.append((xf.basis * n[k]).normalized())
					uvs.append(uv[k] if not uv.is_empty() else Vector2.ZERO)
					uv2s.append(Vector2(i + 1, 0))
					colours.append(col[k] if not col.is_empty() else Color.WHITE)
				for k in idx:
					indices.append(base + k)
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_TEX_UV] = uvs
		arrays[Mesh.ARRAY_TEX_UV2] = uv2s
		arrays[Mesh.ARRAY_COLOR] = colours
		arrays[Mesh.ARRAY_INDEX] = indices
		mesh = ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		_merged_cache[key] = mesh
	if _merged == null:
		_merged = MeshInstance3D.new()
		_merged.name = "Pieces"
		visual.add_child(_merged)
	_merged.mesh = mesh
	_merged.transform = chunks.transform
	_merged.material_override = ROCK_MATERIAL
	for piece in _pieces:
		piece.layers = 0  # (still there for aiming and the hull; the merged mesh draws it)
		piece.material_override = ROCK_MATERIAL
	for b in get_node("Visual/Body").get_children():  # a part that never breaks (crystal's stone)
		if b is MeshInstance3D:
			(b as MeshInstance3D).material_override = ROCK_MATERIAL


## Sits the rock in the ground: a patch of trodden dirt projected round its foot (a decal, so it
## follows the terrain), wider than the rock by this much (m).
const DIRT_MARGIN := 0.7
const DIRT_COLOR := Color(0.3, 0.24, 0.18, 0.45)  # (faint: on pale quarry sand it reads as a scorch)
static var _dirt_tex: ImageTexture


func _ground_rock() -> void:
	var dirt := Decal.new()
	dirt.name = "Dirt"
	dirt.texture_albedo = _dirt_texture()
	dirt.modulate = DIRT_COLOR
	var r := _footprint + DIRT_MARGIN
	dirt.size = Vector3(r * 2.0, 0.9, r * 2.0)
	dirt.upper_fade = 0.6  # (only a little way up the rock's own foot)
	dirt.lower_fade = 0.3
	dirt.normal_fade = 0.4
	add_child(dirt)
	dirt.position = Vector3(_shape_centre.x, 0.05, _shape_centre.z)
	dirt.rotation.y = randf() * TAU


## A ragged round blot: opaque in the middle, fraying out to nothing (made once, shared).
static func _dirt_texture() -> ImageTexture:
	if _dirt_tex:
		return _dirt_tex
	var size := 64
	var noise := FastNoiseLite.new()
	noise.frequency = 0.09
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y in size:
		for x in size:
			var p := Vector2(x, y) / (size - 1) * 2.0 - Vector2.ONE
			var edge := 0.75 + 0.25 * noise.get_noise_2d(x, y)
			var a := clampf((edge - p.length()) / 0.35, 0.0, 1.0)
			var speck := 0.85 + 0.15 * noise.get_noise_2d(x * 3.0 + 100.0, y * 3.0)
			img.set_pixel(x, y, Color(speck, speck, speck, a * a))
	_dirt_tex = ImageTexture.create_from_image(img)
	return _dirt_tex


## Hides the broken-off pieces in the merged mesh (24 to a component of pieces_gone).
func _update_piece_mask() -> void:
	if _merged == null:
		return
	var words := [0, 0, 0, 0]
	for i in mini(_pieces.size(), 96):
		if not _pieces[i].visible:
			words[i / 24] |= 1 << (i % 24)
	_merged.set_instance_shader_parameter("pieces_gone", Vector4(words[0], words[1], words[2], words[3]))


## An ore spilling out of a piece as it comes away, while the rock still owes more than one.
func _spill_ore(piece: MeshInstance3D, info: HitInfo) -> void:
	if not _ore_pieces.has(piece) or _spilled >= _drops_owed - 1:
		return
	_spilled += 1
	var toward_player := -info.away()
	var vel := toward_player * randf_range(1.0, 2.0) + Vector3.UP * randf_range(2.5, 3.5) \
		+ Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)) * 0.6
	_launch_drop(_piece_centre(piece), vel, 0.05)


## Knocks out the piece struck and up to `count` of its neighbours near the hit, then drops
## whatever that left hanging, and sets hits_left from how much is gone. The pieces that fell.
func _knock_out(info: HitInfo, count: int) -> int:
	var intact := _intact_chunks()
	var struck := _piece_struck(info)
	if struck == null:
		struck = _nearest(intact, info.position)
	if struck == null:
		hits_left = 0
		return 0
	var fault := _fault_piece != null and (struck == _fault_piece 		or to_local(info.position).distance_to(_fault_point) < FAULT_RADIUS)
	if _tough.get(struck, 0) > 0 and not fault:  # a tough piece: this hit only cracks it
		_tough[struck] -= 1
		if hit_fx:
			HitFx.spawn(hit_fx, get_parent(), info.position, info.normal, -info.normal, chip_color, ore_color, 1.2)
		_hits_from_pieces()
		return 0
	var at := info.position
	var reach := FAULT_REACH if fault else INF  # (a plain hit: whichever touching pieces are nearest)
	var near: Array = (_links[struck] as Array).filter(func(c: MeshInstance3D) -> bool:
		return c.visible and _piece_centre(c).distance_to(at) < reach)
	if fault:  # the whole cluster round it, neighbours of neighbours too
		for c: MeshInstance3D in near.duplicate():
			for o: MeshInstance3D in _links[c]:
				if o != struck and o.visible and not near.has(o) and _piece_centre(o).distance_to(at) < reach:
					near.append(o)
	near.sort_custom(func(a: MeshInstance3D, b: MeshInstance3D) -> bool:
		return _piece_centre(a).distance_squared_to(at) < _piece_centre(b).distance_squared_to(at))
	var extra := _knock + count - 1
	var out: Array = [struck] + near.filter(func(c: MeshInstance3D) -> bool: return fault or _tough.get(c, 0) == 0) 		.slice(0, FAULT_BREAK - 1 if fault else randi_range(extra, extra + 1))
	if fault:
		_fault_feedback(info)
	for c: MeshInstance3D in out:
		var away := (global_basis * (to_local(_piece_centre(c)) - _shape_centre)).normalized()
		if hit_fx:
			HitFx.spawn(hit_fx, get_parent(), _piece_centre(c), info.normal, -info.normal, chip_color, ore_color, 0.8)
		_pop_chunk(c, _split_push(away, info), debris_speed * 0.6)
		_spill_ore(c, info)
	var falling := _unsupported()
	for c in falling:
		var away := (global_basis * (to_local(_piece_centre(c)) - _shape_centre)).normalized()
		_pop_chunk(c, away * 0.3, debris_speed * 0.25)
		_spill_ore(c, info)
	_hits_from_pieces()
	return falling.size()


## hits_left from how much of the rock is gone (0 once it's time to shatter).
func _hits_from_pieces() -> void:
	var gone := 1.0 - float(_intact_chunks().size()) / _links.size()
	hits_left = 0 if gone >= _shatter_at else maxi(1, ceili((_shatter_at - gone) / _shatter_at * max_hits))


func _piece_centre(piece: MeshInstance3D) -> Vector3:
	return piece.global_transform * piece.get_aabb().get_center()


## The pieces still there with no chain of pieces still there down to the ground.
func _unsupported() -> Array[MeshInstance3D]:
	var held := {}
	var queue: Array[MeshInstance3D] = []
	for c: MeshInstance3D in _grounded:
		if c.visible:
			held[c] = true
			queue.append(c)
	while not queue.is_empty():
		var c: MeshInstance3D = queue.pop_back()
		for o: MeshInstance3D in _links[c]:
			if _support_below and _rest_y[c] > _rest_y[o] - 0.05:
				continue  # (o doesn't rest on c: c isn't under it)
			if o.visible and not held.has(o):
				held[o] = true
				queue.append(o)
	var out: Array[MeshInstance3D] = []
	for c: MeshInstance3D in _links:
		if c.visible and not held.has(c):
			out.append(c)
	return out


## The fault: one spot on an ore rock where it's ready to give, a hairline crack with grit
## trickling out of it. Find it and hit it and a whole cluster breaks out (FAULT_BREAK pieces,
## tough ones too) with a deep crunch; then it opens up somewhere else a moment later.
const FAULT_RADIUS := 0.35
const FAULT_REACH := 1.1
const FAULT_BREAK := 6
const FAULT_DELAY := 0.8
var _fault_piece: MeshInstance3D
var _fault_point := Vector3.ZERO  # node space
var _fault_marks: Array[Node] = []


func _place_fault() -> void:
	_clear_fault()
	if _links.is_empty() or hits_left <= 0:
		return
	var spots := []  # [piece, point, normal], node space: outside faces on the sides, off the ground
	for piece in _pieces:
		if not piece.visible:
			continue
		var tris := _piece_tris(piece)
		var centres: PackedVector3Array = tris[0]
		var normals: PackedVector3Array = tris[1]
		var xf := chunks.transform * piece.transform  # (stand-ins never move)
		for i in centres.size():
			var n := (xf.basis * normals[i]).normalized()
			var p := xf * centres[i]
			if n.y > -0.1 and n.y < 0.8 and p.y > 0.3:
				spots.append([piece, p, n])
	if spots.is_empty():
		return
	var spot: Array = spots.pick_random()
	_fault_piece = spot[0]
	_fault_point = spot[1]
	var n: Vector3 = spot[2]
	var side := n.cross(Vector3.UP)
	side = (side if side.length() > 0.1 else Vector3.RIGHT).normalized().rotated(n, randf_range(-0.7, 0.7))
	var crack := _crack_decal(_fault_point - side * 0.3, _fault_point + side * 0.3, n, 0.3)
	if crack:
		_fault_marks.append(crack)
	var dust := _tip_dust(_fault_point, n)
	dust.amount = 16
	dust.lifetime = 1.2
	dust.scale_amount_max = 0.7
	_fault_marks.append(dust)


func _clear_fault() -> void:
	for m in _fault_marks:
		if is_instance_valid(m):
			m.queue_free()
	_fault_marks.clear()
	_fault_piece = null


func _fault_feedback(info: HitInfo) -> void:
	_clear_fault()
	create_tween().tween_callback(_place_fault).set_delay(FAULT_DELAY)
	PopupText.spawn(get_parent(), _popup_pos() + Vector3(0, 0.85, 0), "Fault!", ore_color, 13)
	_award_xp(xp_per_hit * 3, true)
	Juice.shake(3.5)
	Juice.hitstop(0.09)
	HitFx.star(get_parent(), info.position + info.normal * 0.1, STAR_TIP, 2.5)
	if split_layers:
		Sfx.play_at(split_layers, info.position, 0.75)  # a deep crunch ...
	_play(break_audio, break_sfx, 1.25)  # ... and the stone giving way
	_add_rubble(info.position, 4)


func _collapse_feedback(info: HitInfo, pieces: int) -> void:
	PopupText.spawn(get_parent(), _popup_pos() + Vector3(0, 0.85, 0), "Collapse!", ore_color, 12)
	_award_xp(xp_per_hit * mini(pieces, 4), true)
	Juice.shake(2.5)
	Juice.hitstop(0.06)
	if split_layers:
		Sfx.play_at(split_layers, info.position)
	_add_rubble(info.position, mini(pieces, 4))


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
	for p in crack_tips():
		if _aimed_near(info, p, crack_tip_radius * _window_scale()):
			return true
	return false


## Where the open crack's tips are (world space): both ends of a seam crack, the end of a
## free one. Empty when there's no crack.
func crack_tips() -> Array[Vector3]:
	var out: Array[Vector3] = []
	if _seam_piece:
		for p in _seam_tip_points:
			out.append(to_global(p))
	elif not _crack.is_empty() and _crack_tip != null:
		out.append(to_global(_crack[-1]))
	return out


## Grows the crack if a tip was hit, or starts one where this hit landed: along the seam of the
## piece that was struck if it has one, else freely across the surface (the bare core, or a
## model without seams). One left behind stays as a scar. True when the crack is complete.
func _grow_crack(info: HitInfo, tip: bool) -> bool:
	if not _seams.is_empty():
		# a boulder made of pieces: every hit on a piece cracks it a step further round its seam
		# (a tip hit, two), so pieces only ever come off along a crack
		if tip and _seam_piece:
			return _seam_advance(info, 2, true)
		var piece := _piece_struck(info)
		if piece and _seams.has(piece):
			if piece == _seam_piece:
				return _seam_advance(info, 1, false)
			_retire_tip()
			_crack.clear()
			if _start_seam_crack(piece, info):  # back to a piece cracked before: carry on
				return _seam_advance(info, 1, false)
			_crack_sound = CRACK_CREAK  # a crack opening
			_crack_step = _seam_step
			if _seam_piece and _seam_step < crack_segments:
				_loosen(_seam_piece, false)
			return _seam_step >= crack_segments
		# the bare core: a free crack, below
	if tip:
		_extend_crack()
		var seg := _crack.size() - 1
		_tip_feedback(info, seg)
		return seg >= crack_segments
	var n := (global_basis.inverse() * info.normal).normalized()
	if _crack.is_empty() or n.dot(_crack_normal) < 0.5:
		_clear_seam_crack(true)
		_retire_tip()
		_crack_normal = n
		_crack.assign([to_local(info.position)])
		_crack_normals.assign([n])
		_crack_dir = _first_crack_direction(n)
		_extend_crack()
	return false


## A full crack: a seam crack splits off the piece it outlined; a free one, everything it
## crossed. On the bare core, the node breaks.
func _split(info: HitInfo) -> void:
	if _seam_piece:
		var piece := _seam_piece
		_clear_seam_crack()
		_split_feedback(info)
		var centre := to_local(piece.global_transform * piece.get_aabb().get_center())
		var out := (global_basis * (centre - _shape_centre)).normalized()
		if hit_fx:
			HitFx.spawn(hit_fx, get_parent(), to_global(centre), out, -out, chip_color, ore_color, 2.2)
		HitFx.star(get_parent(), info.position + info.normal * 0.1, STAR_TIP, 2.0)
		_add_rubble(info.position, 4)
		_pop_chunk(piece, _split_push(out, info), debris_speed * SPLIT_SPEED)
		hits_left = maxi(hits_left - crack_split_hits, 0)
		SaveGame.mark_dirty()
		return
	var path := _crack.duplicate()
	var normals := _crack_normals.duplicate()
	_crack.clear()
	_crack_normals.clear()
	_retire_tip()
	_split_feedback(info)
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
		_pop_chunk(c, _split_push(out, info), debris_speed * SPLIT_SPEED)
	hits_left = maxi(hits_left - crack_split_hits, 0)
	SaveGame.mark_dirty()


## Which way a split-off piece goes: out from the rock along the ground, but never toward the
## swinger, and leaning away from them. A boulder's piece is big; it tips off, not into your face.
func _split_push(out: Vector3, info: HitInfo) -> Vector3:
	var flat := Vector3(out.x, 0.0, out.z)
	var toward := -info.away()
	if flat.dot(toward) > 0.0:
		flat -= toward * flat.dot(toward)
	return flat * 0.5 + info.away() * 0.6


func _split_feedback(info: HitInfo) -> void:
	PopupText.spawn(get_parent(), _popup_pos() + Vector3(0, 0.85, 0), "Split!", ore_color, 12)
	Juice.shake(3.0)
	Juice.hitstop(0.07)


func _tip_feedback(info: HitInfo, segment: int) -> void:
	_crack_sound = CRACK_TIP
	_crack_step = segment
	PopupText.spawn(get_parent(), _popup_pos() + Vector3(0, 0.6, 0), "Crack!", ore_color, 10)
	Juice.shake(1.5)
	Juice.hitstop(0.03)


# --- seam cracks ----------------------------------------------------------------------------
# A boulder made of pieces (the model's Seam_* lines) cracks along the outline of the piece you
# strike: from the point of the seam nearest the hit, both ways at once, a step per hit on that
# piece (two for a hit on a tip), until it's gone all the way round the visible outline. Then
# exactly that piece comes off: pieces only ever leave along a crack (no wear-down shedding).
# Leave a piece half-cracked for another and its crack stays, to carry on from later.

## Below this height (node space) a seam runs along the ground, where a crack can't be seen.
const SEAM_GROUND := 0.15
## How far a piece has come away just before it splits off: slid out (m) and tilted (degrees).
const LOOSEN_GAP := 0.06
const LOOSEN_TILT := 8.0

## Each chunk's outline on the surface: MeshInstance3D -> closed loop of points (node space).
var _seams := {}
## The piece being cracked, and its outline above ground (arc points, distance along it at each).
var _seam_piece: MeshInstance3D
var _seam_arc := PackedVector3Array()
var _seam_dist := PackedFloat32Array()
var _seam_closed := false
## Where on the arc the crack started, how far it will reach back and forward when complete, and
## how many steps of crack_segments it has made.
var _seam_start := 0.0
var _seam_reach := Vector2.ZERO
var _seam_step := 0
var _seam_tip_points: Array[Vector3] = []
var _seam_tip_dust: Array[CPUParticles3D] = []
## Pieces cracked part of the way and left for another: piece -> its crack (arc, reach, step...).
var _seam_progress := {}
var _face_cache := {}  # mesh -> its triangles, for _piece_struck


## The chunk the swing actually hit (by its triangles, not the collision hull), or null if it hit
## the core or nothing.
func _piece_struck(info: HitInfo) -> MeshInstance3D:
	var dir := (info.position - info.from).normalized()
	var best: MeshInstance3D = null
	var best_d := INF
	for m in visual.find_children("*", "MeshInstance3D", true, false):
		var mesh := m as MeshInstance3D
		if not mesh.visible or mesh.mesh == null or not (mesh.get_parent() == chunks or mesh.get_parent().name == "Body"):
			continue
		var faces: PackedVector3Array = _face_cache.get(mesh.mesh, PackedVector3Array())
		if faces.is_empty():
			faces = mesh.mesh.get_faces()
			_face_cache[mesh.mesh] = faces
		var xf := mesh.global_transform
		for i in range(0, faces.size() - 2, 3):
			var hit_point = Geometry3D.ray_intersects_triangle(info.from, dir, xf * faces[i], xf * faces[i + 1], xf * faces[i + 2])
			if hit_point != null:
				var d := info.from.distance_to(hit_point)
				if d < best_d:
					best_d = d
					best = mesh
	return best if best and best.get_parent() == chunks else null


## Makes `piece` the one being cracked: picks up its crack where it was left if it has one (true),
## else starts one at the point of its seam nearest the hit, a first step already made.
func _start_seam_crack(piece: MeshInstance3D, info: HitInfo) -> bool:
	_clear_seam_crack(true)
	if _seam_progress.has(piece):
		var saved: Dictionary = _seam_progress[piece]
		_seam_progress.erase(piece)
		_seam_arc = saved["arc"]
		_seam_dist = saved["dist"]
		_seam_closed = saved["closed"]
		_seam_start = saved["start"]
		_seam_reach = saved["reach"]
		_seam_step = saved["step"]
		_seam_piece = piece
		_mark_cracking(piece)
		_place_seam_tips()
		return true
	if not _build_seam_arc(_seams[piece], to_local(info.position)):
		return false
	_seam_piece = piece
	_mark_cracking(piece)
	_seam_start = _arc_param(to_local(info.position))
	var total := _seam_dist[-1]
	_seam_reach = Vector2(total * 0.5, total * 0.5) if _seam_closed else Vector2(_seam_start, total - _seam_start)
	_seam_step = 0
	_seam_grow()
	return false


## `steps` more steps each way (a tip hit makes two). True when it's gone all the way round.
func _seam_advance(info: HitInfo, steps: int, tip: bool) -> bool:
	for i in steps:
		if _seam_step < crack_segments:
			_seam_grow()
	if _seam_step < crack_segments:
		_loosen(_seam_piece, tip)
	if tip:
		_tip_feedback(info, _seam_step)
	else:
		_crack_sound = CRACK_CREAK  # (played quieter, with the hit: _hit_sounds)
		_crack_step = _seam_step
	return _seam_step >= crack_segments


func _seam_grow() -> void:
	var n := float(crack_segments)
	var back := Vector2(_seam_reach.x * _seam_step / n, _seam_reach.x * (_seam_step + 1) / n)
	var fwd := Vector2(_seam_reach.y * _seam_step / n, _seam_reach.y * (_seam_step + 1) / n)
	_seam_step += 1
	_place_seam_tips()


## The pieces' poses before any loosening (Visual/Chunks space): MeshInstance3D -> Transform3D.
var _rest := {}
var _loosen_tweens := {}  # piece -> its jolt Tween


## Sets `piece` loose as far as its crack has gone: no crack is drawn; the piece itself comes away
## from the rock along its seam. It slides out and tilts on the stretch of seam still holding it,
## so the gap opens widest over the cracked stretch. Each hit jolts it past that and lets it settle
## back; a tip hit rattles it.
func _loosen(piece: MeshInstance3D, tip: bool) -> void:
	if not _rest.has(piece):
		_rest[piece] = piece.transform
	var f := float(_seam_step) / crack_segments
	if _loosen_tweens.has(piece):
		(_loosen_tweens[piece] as Tween).kill()
	var target := _loose_pose(piece, f)
	var t := piece.create_tween()
	_loosen_tweens[piece] = t
	if tip:
		for k in 3:  # a rattle: out past it, back short, smaller each time
			var a := 1.0 / (k + 1)
			t.tween_property(piece, "transform", _loose_pose(piece, f + 0.5 * a), 0.035)
			t.tween_property(piece, "transform", _loose_pose(piece, f - 0.2 * a), 0.035)
	else:
		t.tween_property(piece, "transform", _loose_pose(piece, f + 0.35), 0.05).set_ease(Tween.EASE_OUT)
	t.tween_property(piece, "transform", target, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## `piece` loosened by `f` (0 at rest, 1 about to come off), in Visual/Chunks space.
func _loose_pose(piece: MeshInstance3D, f: float) -> Transform3D:
	var rest: Transform3D = _rest[piece]
	f = maxf(f, 0.0)
	var to_node := chunks.transform  # (Visual at rest is the node's own space)
	var c := to_node * (rest * piece.get_aabb().get_center())
	var out := (c - _shape_centre).normalized()
	# the middle of the cracked stretch: that side lifts, the far side stays as the hinge
	var n := float(crack_segments)
	var mid := _arc_point(_seam_start + (_seam_reach.y - _seam_reach.x) * _seam_step / n * 0.5)
	var v := mid - c
	v -= out * v.dot(out)
	var turn := Basis.IDENTITY
	if v.length() > 0.05:
		turn = Basis(v.cross(out).normalized(), deg_to_rad(LOOSEN_TILT) * f)
	var pose := Transform3D(turn, c - turn * c + out * LOOSEN_GAP * f) * (to_node * rest)
	return to_node.affine_inverse() * pose


## The tips: each end that still has further to go, trickling dust.
func _place_seam_tips() -> void:
	for d in _seam_tip_dust:
		if is_instance_valid(d):
			d.emitting = false
			d.get_tree().create_timer(1.5).timeout.connect(d.queue_free)
	_seam_tip_dust.clear()
	_seam_tip_points.clear()
	if _seam_step >= crack_segments:
		return
	var n := float(crack_segments)
	var back := _seam_reach.x * _seam_step / n
	var fwd := _seam_reach.y * _seam_step / n
	for end in [[_seam_start - back, -1.0], [_seam_start + fwd, 1.0]]:
		var s: float = end[0]
		var p := _arc_point(s)
		_seam_tip_dust.append(_tip_dust(p, _seam_up(p)))
		_seam_tip_points.append(p)


## Grit trickling out of the seam at a tip: a thin, steady spill of the rock's broken stone.
func _tip_dust(p: Vector3, up: Vector3) -> CPUParticles3D:
	var dust := chips.duplicate() as CPUParticles3D
	dust.one_shot = false
	dust.explosiveness = 0.0
	dust.amount = 10
	dust.lifetime = 0.9
	dust.direction = Vector3(0, 0, 1)
	dust.spread = 25.0
	dust.initial_velocity_min = 0.3
	dust.initial_velocity_max = 0.7
	dust.scale_amount_min = 0.25
	dust.scale_amount_max = 0.5
	dust.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	dust.emission_sphere_radius = 0.04
	dust.color = chip_color.lightened(0.15)
	notches.add_child(dust)
	var side := up.cross(Vector3.UP)
	if side.length() < 0.1:
		side = Vector3.RIGHT
	dust.transform = Transform3D(Basis.looking_at(-up, side.cross(up)), p + up * 0.03)
	dust.emitting = true
	return dust


## The surface's normal at a point on a seam, for the decal drawn there: that of the outside face
## of the piece being cracked nearest the point (not one of its cut faces, against its neighbours:
## the model marks those, see _piece_tris). Out from the middle would do for a boulder, but not
## round the foot of a crystal, where it would point along the stone, not at the crystal.
func _seam_up(p: Vector3) -> Vector3:
	var out := (p - _shape_centre).normalized()
	if _seam_piece:
		var tris := _piece_tris(_seam_piece)
		var centres: PackedVector3Array = tris[0]
		var normals: PackedVector3Array = tris[1]
		var to_node := visual.global_transform.affine_inverse() * _seam_piece.global_transform  # (Visual at rest)
		var best := -1
		var best_d := INF
		for i in centres.size():
			var c := to_node * centres[i]
			var d := c.distance_squared_to(p)
			if d < best_d:
				best_d = d
				best = i
		if best != -1:
			return (to_node.basis * normals[best]).normalized()
	var s := _surface_at(p, out)
	return s["normal"] if not s.is_empty() else out


## Each outside triangle of a piece's mesh: [centres, normals], in the piece's own space. Its cut
## faces are left out: the generator marks them red in the vertex colour (models without one
## count every face as outside). Cached per mesh.
var _tri_cache := {}

func _piece_tris(piece: MeshInstance3D) -> Array:
	if _tri_cache.has(piece.mesh):
		return _tri_cache[piece.mesh]
	var centres := PackedVector3Array()
	var normals := PackedVector3Array()
	for s in piece.mesh.get_surface_count():
		var arrays := piece.mesh.surface_get_arrays(s)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var marks: PackedColorArray = arrays[Mesh.ARRAY_COLOR] if arrays[Mesh.ARRAY_COLOR] else PackedColorArray()
		var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] else PackedInt32Array(range(verts.size()))
		for i in range(0, idx.size() - 2, 3):
			if not marks.is_empty() and (marks[idx[i]].a < 0.5 or (marks[idx[i]].r > 0.5 and marks[idx[i]].g < 0.1)):
				continue  # a cut face (alpha 0 on a weathered rock; red on an older one)
			var a := verts[idx[i]]
			var b := verts[idx[i + 1]]
			var c := verts[idx[i + 2]]
			centres.append((a + b + c) / 3.0)
			# Godot's front faces wind clockwise, so this points out of the mesh
			normals.append((c - a).cross(b - a).normalized())
	_tri_cache[piece.mesh] = [centres, normals]
	return _tri_cache[piece.mesh]


## The part of a piece's outline above the ground nearest `near`: a whole loop if it never dips
## under (closed), else the run of one between two dips, cut off right at ground height (so a
## seam running straight up from the ground keeps its upright part). False if there's nothing.
func _build_seam_arc(loops: Array, near: Vector3) -> bool:
	var arc := PackedVector3Array()
	var closed := false
	var best_d := INF
	for loop: PackedVector3Array in loops:
		var n := loop.size()
		var low := -1
		for i in n:
			if loop[i].y < SEAM_GROUND:
				low = i
				break
		var runs: Array[PackedVector3Array] = []
		if low == -1:
			var whole := loop.duplicate()
			whole.append(loop[0])
			runs.append(whole)
		else:
			var run := PackedVector3Array()
			var prev := loop[low]
			for k in n:
				var p := loop[(low + 1 + k) % n]
				var under := p.y < SEAM_GROUND
				if under != (prev.y < SEAM_GROUND):  # crossing the ground line: end or start there
					run.append(prev.lerp(p, (SEAM_GROUND - prev.y) / (p.y - prev.y)))
				if under:
					if run.size() >= 2:
						runs.append(run)
					run = PackedVector3Array()
				else:
					run.append(p)
				prev = p
		for r in runs:
			for p in r:
				if p.distance_squared_to(near) < best_d:
					best_d = p.distance_squared_to(near)
					arc = r
					closed = low == -1
	_seam_closed = closed
	if arc.size() < 2:
		return false
	_seam_arc = arc
	_seam_dist = PackedFloat32Array([0.0])
	for i in range(1, arc.size()):
		_seam_dist.append(_seam_dist[-1] + arc[i - 1].distance_to(arc[i]))
	return _seam_dist[-1] > 0.1


## The point `s` along the arc (wrapping round a closed one).
func _arc_point(s: float) -> Vector3:
	var total := _seam_dist[-1]
	s = fposmod(s, total) if _seam_closed else clampf(s, 0.0, total)
	for i in _seam_arc.size() - 1:
		if s <= _seam_dist[i + 1]:
			var t := (s - _seam_dist[i]) / maxf(_seam_dist[i + 1] - _seam_dist[i], 0.0001)
			return _seam_arc[i].lerp(_seam_arc[i + 1], t)
	return _seam_arc[-1]


## How far along the arc its nearest point to `p` is.
func _arc_param(p: Vector3) -> float:
	var best := 0.0
	var best_d := INF
	for i in _seam_arc.size() - 1:
		var c := Geometry3D.get_closest_point_to_segment(p, _seam_arc[i], _seam_arc[i + 1])
		var d := c.distance_squared_to(p)
		if d < best_d:
			best_d = d
			best = _seam_dist[i] + _seam_arc[i].distance_to(c)
	return best


## The render layers a seam crack's decals draw on: just the piece being cracked, or everything.
func _seam_mask() -> int:
	return CRACKING_LAYER if seam_crack_on_piece_only else WORLD_LAYER


## With seam_crack_on_piece_only, puts `piece` on the cracking layer (it stays there, scars and
## all, until the node grows back).
func _mark_cracking(piece: MeshInstance3D) -> void:
	if seam_crack_on_piece_only:
		piece.layers |= CRACKING_LAYER


## Drops the seam crack (its tips go out; the cracks drawn so far stay). With `keep`, its progress
## is remembered, to carry on if that piece is struck again.
func _clear_seam_crack(keep := false) -> void:
	if _seam_piece:
		if keep and _seam_piece.visible and _seam_step < crack_segments:
			_seam_progress[_seam_piece] = {"arc": _seam_arc, "dist": _seam_dist, "closed": _seam_closed,
				"start": _seam_start, "reach": _seam_reach, "step": _seam_step}
		else:
			_seam_progress.erase(_seam_piece)
	for d in _seam_tip_dust:
		if is_instance_valid(d):
			d.queue_free()
	_seam_tip_dust.clear()
	_seam_tip_points.clear()
	_seam_piece = null
	_seam_step = 0


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


## A stretch of crack from `a` to `b` on a surface facing `up`. `depth`: how far it projects either
## way. A free crack lies on the collision hull, so it must reach down into the hollows the hull
## spans; a seam lies on the mesh itself, so a shallow one keeps it off the stone round a crystal.
## `mask`: the render layers it draws on.
func _crack_decal(a: Vector3, b: Vector3, up: Vector3, depth := 0.9, mask := WORLD_LAYER) -> Decal:
	if a.distance_to(b) < 0.01:
		return null
	var d := Decal.new()
	d.texture_albedo = _crack_textures(chip_color).pick_random()
	d.size = Vector3(0.32, depth, a.distance_to(b) * 1.25)  # a little longer, so neighbours overlap
	# a seam's decals face the piece's own surface exactly: fade hard off anything turned away
	# (the stone a crystal stands on)
	d.normal_fade = 0.3 if depth > 0.5 else 0.65
	d.cull_mask = mask  # (never the held tool, render layer 2)
	notches.add_child(d)
	d.transform = Transform3D(_face_basis(b - a, up), (a + b) * 0.5)
	return d


## The crack's tip: a pale spot of freshly broken stone (the rock's own colour, lighter), gently
## pulsing so it's easy to find.
func _place_tip() -> void:
	if _crack_tip == null:
		_crack_tip = _tip_decal()
	_crack_tip.transform = Transform3D(_face_basis(_crack_dir, _crack_normals[-1]), _crack[-1])


func _tip_decal() -> Decal:
	var tip := Decal.new()
	tip.texture_albedo = _notch_texture()
	tip.texture_emission = _notch_texture()
	tip.modulate = chip_color.lightened(0.3)
	tip.size = Vector3(0.22, 0.9, 0.22)
	tip.normal_fade = 0.3
	tip.cull_mask = WORLD_LAYER
	notches.add_child(tip)
	var pulse := tip.create_tween().set_loops()
	pulse.tween_property(tip, "emission_energy", 0.35, 0.5).set_trans(Tween.TRANS_SINE)
	pulse.tween_property(tip, "emission_energy", 0.05, 0.5).set_trans(Tween.TRANS_SINE)
	return tip


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
			x = clampf(x + drift, W * 0.5 - 3.5, W * 0.5 + 3.5)  # a few cm either way: the seam gives the shape
			# back to the middle at both ends, so a crack of several decals joins up without steps
			path.append(lerpf(W * 0.5, x, sin(PI * y / (H - 1))))
		var branches := []  # [start row, x per row]
		for start in [44 + v * 10]:
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
	if not weak_point or cracks or carve_notch:
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
	return _aimed_near(info, _weak.global_position, weak_point_radius * _window_scale())


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
	# a better tool throws more sparks, and iron and crystal throw them in their own colour
	var tier := Tools.tier(tool_type) if Tools.LADDER.has(tool_type) else 1
	var sparks := roundi(spark_amount * (2.0 if strength > 1.2 else 1.0) * (0.6 + 0.4 * tier))
	var second := ore_color if cracks else bark_color if _carve else Color(0, 0, 0, 0)
	HitFx.spawn(hit_fx, get_parent(), info.position, info.normal, swing, chip_color, second, strength, sparks,
		SPARK_TINTS[tier] if tier < SPARK_TINTS.size() else Color(0, 0, 0, 0))
	HitFx.star(get_parent(), info.position + info.normal * 0.08, STAR_TIP if strength > 1.2 else STAR_HIT, 0.8 * strength)
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
	for c: Node in chunks.get_children() + ([_merged] if _merged else []):
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
		if c is GeometryInstance3D and not chunk_shadows and _links.is_empty() and c.get_parent() == chunks:
			(c as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_limit_drawing(c)


func _collect_surfaces(n: Node) -> void:
	for c in n.get_children():
		if c is GeometryInstance3D:
			_surfaces.append(c)
		_collect_surfaces(c)


## Dresses every mesh under `n` with this node's theme (the pieces and parts that fly off or fall
## keep it: they're the same meshes, or copies of them).
func _dress(n: Node) -> void:
	if carve_notch:  # a tree: soil and moss up the foot of its trunk (node_surface.gdshaderinc)
		for g in ([n] if n is MeshInstance3D else []) + n.find_children("*", "MeshInstance3D", true, false):
			(g as MeshInstance3D).set_instance_shader_parameter("foot", TRUNK_FOOT)
	if look.is_empty():
		return
	if n is MeshInstance3D:
		NodeTheme.dress(n, look)
	for g in n.find_children("*", "MeshInstance3D", true, false):
		NodeTheme.dress(g, look)


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
			s.set_instance_shader_parameter("flash", v), flash_strength, 0.0, 0.09)


## "Impact": shove the visual away from the player and squash it slightly, then spring back.
func _nudge(away: Vector3) -> void:
	if _nudge_tween:
		_nudge_tween.kill()
	visual.position = away * 0.06
	visual.scale = Vector3(1.04, 0.95, 1.04)
	_nudge_tween = create_tween().set_parallel()
	_nudge_tween.tween_property(visual, "position", Vector3.ZERO, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_nudge_tween.tween_property(visual, "scale", Vector3.ONE, 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
