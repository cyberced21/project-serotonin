class_name RodFishing
extends Node
## Rod fishing, as a part of the Player (child node, like SpearFishing). Water beyond the spear's
## reach, out to cast_range, brings the rod out. Once cast, the rod stays in hand until the float is
## reeled in or the fish is out. Every beat is timing, read from the world:
##
## 1. Cast: hold to swing the rod back, release on the forward stroke. The whip is the sweet spot:
##    on it, the float lands on the aim point with a plip; off it, it scatters and sploshes (RodCast),
##    spooking fish near. Right on top of a school spooks it however soft.
## 2. Bite: the float (FishingLure) draws a real fish over; it nibbles (fake-outs: don't pull),
##    taps twice, then takes: the big moment. The float is dragged under with a plunge and a bell,
##    a splash, a "!", the rod bends hard. Pull (click) inside the window. Early spooks it; late,
##    it spits the hook and the float bobs back up for the next one.
## 3. Yank: pulled on time, the fish tears out of the water and sails over in an arc (LandedFish),
##    slaps down on the bank beside you and flops about. Walk up to it to pick it up. Its size was
##    there all along (FishSize): bigger pays more XP, and a Big one counts 2, a Huge one 3. A
##    perfect cast plus a quick pull is "Perfect!" (+50% XP).
## Under-levelled fish still bite, but the hook may slip as you pull: the same chance a spear's
## fish dodges (FishBite.catch_chance).

enum State { IDLE, BACKCAST, FLIGHT, WAITING, RETRIEVE, YANK, DONE }

const WORLD_MASK := 1
const ROD_MODEL := preload("res://models/rod.glb")
const TOOL_MATERIAL := preload("res://materials/node_palette.tres")
const HOOK_COLOR := Color("ffe36b")
const MISS_COLOR := Color("c9d3dc")
## Where the rod's tip ends, past the Tip section's base (tools/blender/make_models.py rod()).
const ROD_TIP_LENGTH := 0.45
## Rod tilt (radians up from straight ahead) at rest, wound back over the shoulder, at the end of
## the forward stroke, while waiting on the float, and swept up as the fish comes out.
const ROD_REST := 0.5
const ROD_BACK := 1.95
const ROD_FORWARD := 0.12
const ROD_WAIT := 0.42
const ROD_YANK := 1.4
## A fish this close (m) to where the float lands is cast right on top of: it bolts regardless.
const ON_TOP := 0.8
## How far from you (m) a yanked fish lands.
const LAND_DISTANCE := 2.6

## Cast range (m, along your aim), plus this every 10 Fishing levels.
@export var cast_range := 14.0
## The nearest water it casts to (m, flat from your feet).
@export var min_distance := 2.0
@export var range_per_10_levels := 1.0
## A rod catch pays this much more XP than the same fish speared: one fish at a time, so each one
## is worth more (tuned with tools/fishing_bench.gd against the spear).
@export var catch_xp := 1.8
## What each rod tier above the willow pole adds (Tools): cast range (m) and strike window.
@export var range_per_tier := 1.5
@export var window_per_tier := 0.08

@export_group("Cast timing")
## Seconds swinging back, then forward; the sweet spot is this far into the forward stroke.
@export var back_time := 0.3
@export var forward_time := 0.42
@export_range(0.0, 1.0) var sweet_spot := 0.5

@onready var player: CharacterBody3D = get_parent()

var state := State.IDLE
var aim_point := Vector3.INF
var aim_water: WaterBody
## The rod's viewmodel node (Player.tools[&"rod"]).
var rod: Node3D

var lure: FishingLure
## The fish in the air, on its way to the bank (YANK).
var caught: LandedFish

var _vm_cam: Camera3D
var _rod_pivot: Node3D
var _mid: Node3D
var _tip: Node3D
var _angle := ROD_REST
var _bend := 0.0
var _jerk := 0.0       # rod tip impulse (springs back)
var _jerk_vel := 0.0
var _rod_yaw := 0.0
var _line: MeshInstance3D
var _line_mesh := ArrayMesh.new()
var _line_tension := 0.0
var _rng := RandomNumberGenerator.new()

var _t := 0.0                 # time in the current state
var _cast_from := Vector3.ZERO
var _cast_aim := Vector3.ZERO
var _cast_water: WaterBody
var _verdict: Dictionary = {}
var _whipped := false
var _flight_from := Vector3.ZERO
var _flight_to := Vector3.ZERO
var _flight_time := 0.5
var _land_water: WaterBody
var _retrieve_from := Vector3.ZERO
var _done_wait := 0.0
# the catch, popped up once it lands
var _catch_text := ""
var _catch_gained := 0
var _catch_perfect := false
var _catch_size := ""
var _catch_bonus := false


func _ready() -> void:
	_rng.randomize()
	_vm_cam = player.get_node("Viewmodel/SubViewport/Camera3D")
	_build_rod()
	_build_line()
	Tools.changed.connect(func(t: StringName, _tier: int) -> void:
		if t == &"rod":
			_load_rod_model())


# --- the player asks ------------------------------------------------------------------------

## The rod is out and doing something: keep it in hand, don't target anything else.
func is_busy() -> bool:
	return state != State.IDLE


func can_cast() -> bool:
	return state == State.IDLE and aim_water != null


func clear_target() -> void:
	aim_water = null
	aim_point = Vector3.INF


## Called by the Player each physics frame when nothing else is targeted: water from
## min_distance out to cast range, in sight.
func update_target() -> void:
	clear_target()
	var cam: Camera3D = player.camera
	var from := cam.global_position
	var dir := -cam.global_basis.z
	if dir.y > -0.01:
		return
	var max_range := _range()
	for node in get_tree().get_nodes_in_group("water"):
		var wb := node as WaterBody
		var t := (wb.surface_height - from.y) / dir.y
		if t <= 0.0 or t > max_range:
			continue
		var p := from + dir * t
		if _flat(p, player.global_position) < min_distance:
			continue
		if wb.depth_here(p) < 0.15:
			continue
		var query := PhysicsRayQueryParameters3D.create(from, p, WORLD_MASK, [player.get_rid()])
		if not player.get_world_3d().direct_space_state.intersect_ray(query).is_empty():
			continue  # the bank, a rock or a tree is in the way
		aim_water = wb
		aim_point = p
		return


func _range() -> float:
	return cast_range + range_per_10_levels * floorf(Skills.level(&"fishing") / 10.0) + range_per_tier * Tools.tier(&"rod")


## Pressed with the rod out and water in range: start the back-cast.
func start_cast() -> void:
	if not can_cast():
		return
	state = State.BACKCAST
	_t = 0.0
	_whipped = false
	_cast_aim = aim_point
	_cast_water = aim_water
	_cast_from = player.global_position
	Sfx.play(load("res://audio/fishing/creak.tres"), 1.3, -14.0)


# --- every frame ---------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	_t += delta
	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	match state:
		State.BACKCAST:
			_update_cast()
		State.FLIGHT:
			if _t >= _flight_time:
				_splash_down()
		State.WAITING:
			if captured and Input.is_action_just_pressed("gather"):
				_strike()
			elif not is_instance_valid(lure) or _flat(player.global_position, lure.global_position) > _range() * 1.4 \
					or not player.is_on_floor() and player.velocity.y < -6.0:
				_retrieve()
		State.RETRIEVE:
			if _t >= 0.45:
				_finish_retrieve()
		State.YANK:
			if not is_instance_valid(caught) or caught.phase != LandedFish.Phase.FLY:
				_end_yank()
			else:
				_follow(caught.global_position, delta)
		State.DONE:
			if _t >= _done_wait:
				_clear_line()
				state = State.IDLE


func _process(delta: float) -> void:
	_animate_rod(delta)
	_draw_line()


# --- the cast ------------------------------------------------------------------------------

func _sweet_time() -> float:
	return back_time + forward_time * sweet_spot


func _update_cast() -> void:
	# the whip: timed so the swoosh peaks on the sweet spot (the clip peaks 0.13 s in)
	if not _whipped and _t >= _sweet_time() - 0.13:
		_whipped = true
		Sfx.play(load("res://audio/fishing/cast_whip.tres"), 1.0, -4.0)
	var released := not Input.is_action_pressed("gather")
	var total := back_time + forward_time
	if released or _t >= total:
		var error := _t - _sweet_time()
		if not released:
			error += 0.08  # held right through the stroke: it slaps down short
		_release(error)


func _release(error: float) -> void:
	var scale := 1.0 + Perks.bonus(&"fishing", &"cast")  # the level's smooth-cast perk
	_verdict = RodCast.judge(error, scale)
	var to := RodCast.landing(_cast_from, _cast_aim, _verdict, _rng)
	_land_water = _water_at(to)
	if _land_water == null:  # scattered onto the bank: it lands where the water starts
		for i in 12:
			to = to.lerp(_cast_aim, 0.25)
			_land_water = _water_at(to)
			if _land_water:
				break
		if _land_water == null:
			to = _cast_aim
			_land_water = _cast_water
	_flight_to = Vector3(to.x, _land_water.surface_height, to.z)
	_flight_from = _tip_world()
	_flight_time = 0.35 + _flat(_flight_from, _flight_to) * 0.035
	lure = FishingLure.new()
	lure.name = "Float"
	player.get_parent().add_child(lure)
	lure.global_position = _flight_from
	lure.water = null  # not floating yet
	lure.remove_from_group("lure")
	state = State.FLIGHT
	_t = 0.0


func _water_at(p: Vector3) -> WaterBody:
	var w := WaterBody.surface_at(get_tree(), p)
	return w if w and w.depth_here(p) > 0.1 else null


func _flight_pos(f: float) -> Vector3:
	var p := _flight_from.lerp(_flight_to, f)
	var arc := 1.2 + _flat(_flight_from, _flight_to) * 0.12
	return p + Vector3.UP * arc * 4.0 * f * (1.0 - f)


func _splash_down() -> void:
	var at := _flight_to
	lure.add_to_group("lure")
	lure.land(_land_water, at)
	lure.calm = Village.stat(&"fish_calm") + Village.stat(&"fish_calm_night") * DayNight.darkness()
	lure.window_bonus = Village.stat(&"strike_window") + window_per_tier * Tools.tier(&"rod")
	lure.tell.connect(_on_tell)
	var q: int = _verdict["quality"]
	var sounds := {RodCast.Quality.PERFECT: "plip", RodCast.Quality.GOOD: "plop", RodCast.Quality.BAD: "splosh"}
	_play_at("res://audio/fishing/%s.tres" % sounds[q], at, 1.0, -2.0 if q != RodCast.Quality.PERFECT else -6.0)
	WaterRipple.spawn(_land_water, at, [0.6, 1.2, 2.0][q], [0.5, 0.8, 1.1][q])
	FishPond.disturb(get_tree(), at, _verdict["loudness"])
	if _fish_near(at, ON_TOP):  # right on top of them: no cast is soft enough
		FishPond.disturb(get_tree(), at, 2.0)
	if q == RodCast.Quality.PERFECT:
		lure.curious = 6.0
	state = State.WAITING
	_t = 0.0


func _fish_near(at: Vector3, radius: float) -> bool:
	for node in get_tree().get_nodes_in_group("fish_school"):
		for f in (node as FishSchool).fish:
			if f.lure == null and _flat(f.global_position, at) < radius:
				return true
	return false


# --- the bite ------------------------------------------------------------------------------

func _on_tell(kind: StringName) -> void:
	if not is_instance_valid(lure):
		return
	var at := lure.global_position
	match kind:
		&"nibble":
			_play_at("res://audio/fishing/nibble.tres", at, 1.0, -4.0)
			_kick(0.05)
		&"tap":
			_play_at("res://audio/fishing/tap.tres", at, 1.0, -3.0)
			_kick(0.08)
		&"take":
			_hook_moment(at)
		&"spat":
			_play_at("res://audio/fishing/nibble.tres", at, 0.8, -6.0)
			_kick(-0.1)
			PopupText.spawn(player.get_parent(), at + Vector3.UP * 0.45, "Too slow", MISS_COLOR, 5)
		&"spooked":
			_play_at("res://audio/fishing/spook.tres", at, 1.0, -2.0)


## The take: the one moment that matters, so it's loud. The float is dragged under with a plunge
## and a bell, the water bursts, a "!" pops over it and the rod bends hard. Pull now.
func _hook_moment(at: Vector3) -> void:
	Sfx.play(load("res://audio/fishing/hooked.tres"), 1.0, 0.0)
	_play_at("res://audio/fishing/bloop.tres", at, 1.0, 0.0)
	splash(player.get_parent(), at, 1.3)
	_ripple(at, 2.8)
	# big enough to read at the far end of a cast
	var far: float = player.camera.global_position.distance_to(at)
	PopupText.spawn(player.get_parent(), at + Vector3.UP * (0.5 + far * 0.03), "!", HOOK_COLOR, roundi(14 + far * 3.0))
	_kick(0.4)


func _strike() -> void:
	var on := lure.fish
	var result := lure.strike()
	_kick(-0.35)  # the rod jerks back
	Sfx.play(load("res://audio/fishing/jerk.tres"), 1.0, -4.0)
	if result == &"hooked" and is_instance_valid(on):
		if not on.tool_can_take(&"rod"):
			_tear_free(on, on.needs_text(&"rod"), Color("ff8a7a"))
		elif randf() >= on.catch_chance():  # under its level: the hook slips
			_tear_free(on, "%s %d" % [Skills.display_name(&"fishing"), on.species.required_level], Color("ffc27a"))
		else:
			_yank(on, lure.strike_timing())
	else:
		_retrieve()


## The hook tears out as you pull and the fish bolts: too weak a rod for it ("Needs Iron-reel
## rod"), or you're under its level ("Fishing 30").
func _tear_free(f: Fish, why: String, color: Color) -> void:
	var at := _surface(f.global_position)
	f.lure = null
	f.state = Fish.State.FLEE
	f.flee_time = 0.8
	f.velocity = _flat_dir(player.global_position, f.global_position) * f.species.flee_speed
	FishPond.disturb(get_tree(), at, 1.5)
	_play_at("res://audio/fishing/snap.tres", at, 1.0, -2.0)
	splash(player.get_parent(), at, 0.9)
	_ripple(at, 2.0)
	_kick(-0.5)
	PopupText.spawn(player.get_parent(), at + Vector3.UP * 0.5, why, color, 7)
	_retrieve()


func _retrieve() -> void:
	if is_instance_valid(lure):
		lure.retire()
		_retrieve_from = lure.global_position
	state = State.RETRIEVE
	_t = 0.0


func _finish_retrieve() -> void:
	if is_instance_valid(lure):
		lure.queue_free()
	lure = null
	_clear_line()
	state = State.IDLE


# --- the yank ------------------------------------------------------------------------------

## Pulled on time: the fish tears out of the water and flies over to the bank beside you.
func _yank(f: Fish, timing: float) -> void:
	var s := f.species
	var at := f.global_position
	if is_instance_valid(f.school):
		f.school.remove_fish(f)
	FishPond.disturb(get_tree(), at, 1.5)  # the rest of them scatter
	# the payoff, worked out now (popped up when it lands)
	_catch_perfect = _verdict.get("quality", -1) == RodCast.Quality.PERFECT and timing < 0.5
	var under := Skills.level(&"fishing") < s.required_level
	var mult := catch_xp * (1.5 if _catch_perfect else 1.0) * f.xp_scale() * (1.5 if under else 1.0)
	_catch_gained = Skills.add_xp(&"fishing", roundi(s.xp * mult))
	_catch_text = "%s, %.1f kg" % [Items.display_name(s.id), f.weight()]
	_catch_size = FishSize.word(f.size)
	var count := FishSize.count_for(f.size)
	_catch_bonus = randf() < Village.stat(&"bonus_fish_chance")  # the fisher's dock
	if _catch_bonus:
		count *= 2
	# the big pull
	Juice.shake(1.0 if _catch_perfect else 0.8)
	_kick(-1.0)
	_bend = 0.0
	Sfx.play(load("res://audio/fishing/yank.tres"), 1.0, 0.0)
	var surface := _surface(at)
	splash(player.get_parent(), surface, 1.9)
	_ripple(surface, 2.6)
	var from := f.global_transform
	from.origin = surface + Vector3.UP * 0.1
	caught = LandedFish.spawn(player.get_parent(), f, from, _landing_spot(at), count)
	caught.landed.connect(_on_landed)
	f.queue_free()  # (already off its school's books)
	lure.retire()
	lure.water = null  # it rides out on the fish's lip
	state = State.YANK
	_t = 0.0


func _on_landed(at: Vector3) -> void:
	var color := Skills.color(&"fishing")
	var top := at + Vector3.UP * 0.7
	var words: PackedStringArray = []
	for w in ["Perfect!" if _catch_perfect else "", _catch_size, "Bonus!" if _catch_bonus else ""]:
		if w != "":
			words.append(w)
	if not words.is_empty():
		PopupText.spawn(player.get_parent(), top + Vector3.UP * 0.2, " ".join(words), color, 7)
	PopupText.spawn(player.get_parent(), top, _catch_text, Color.WHITE, 5, 0.08)
	if _catch_gained > 0:
		PopupText.spawn(player.get_parent(), top + Vector3.DOWN * 0.18, "+%d" % _catch_gained, color, 4, 0.16)


## The fish is down (or gone): off the hook, and the float comes back with the slack line.
func _end_yank() -> void:
	caught = null
	if is_instance_valid(lure):
		lure.queue_free()
	lure = null
	_line_tension = 0.0
	state = State.DONE
	_t = 0.0
	_done_wait = 0.35


## Eases your view round after the fish in the air, just enough to keep it on screen as it lands.
func _follow(at: Vector3, delta: float) -> void:
	var to: Vector3 = at - player.camera.global_position
	if Vector2(to.x, to.z).length() < 0.3:
		return
	var diff := angle_difference(player.rotation.y, atan2(-to.x, -to.z))
	if absf(diff) > 0.45:
		player.rotate_y(signf(diff) * minf(absf(diff) - 0.45, 4.0 * delta))


## On the ground beside you, out of the water, in plain sight: off to one side of the fish's line
## first (so it lands in view), further round toward behind you if that's water or a drop.
func _landing_spot(fish_at: Vector3) -> Vector3:
	var me := player.global_position
	var toward := _flat_dir(me, fish_at)
	var space := player.get_world_3d().direct_space_state
	var flip := 1.0 if _rng.randf() < 0.5 else -1.0
	for a in [0.8, 1.15, 1.55, 2.0, 2.5, PI]:
		for side in [flip, -flip]:
			var p: Vector3 = me + toward.rotated(Vector3.UP, a * side) * LAND_DISTANCE
			var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 2.5, p + Vector3.DOWN * 4.0, WORLD_MASK, [player.get_rid()])
			var hit := space.intersect_ray(q)
			if hit.is_empty() or absf(hit["position"].y - me.y) > 1.2 or WaterBody.depth_at(get_tree(), hit["position"]) > 0.02:
				continue
			var look := PhysicsRayQueryParameters3D.create(me + Vector3.UP * 0.8, hit["position"] + Vector3.UP * 0.3, WORLD_MASK, [player.get_rid()])
			if not space.intersect_ray(look).is_empty():
				continue  # a rock or a tree in the way
			return hit["position"]
	return me + toward.cross(Vector3.UP) * 0.8  # nowhere better: at your feet


## A burst of spray thrown up off the water (`strength` 1: the take; more for the yank).
static func splash(parent: Node, at: Vector3, strength: float) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 0.95
	p.amount = int(28 * strength) + 8
	p.lifetime = 0.6 + 0.25 * strength
	p.direction = Vector3.UP
	p.spread = 30.0
	p.initial_velocity_min = 2.0 * strength
	p.initial_velocity_max = 4.6 * strength
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.12 * strength
	p.mesh = droplet_mesh()
	p.scale_amount_min = 0.8 + 0.4 * strength
	p.scale_amount_max = 1.6 + 0.9 * strength
	var shrink := Curve.new()
	shrink.add_point(Vector2(0, 1))
	shrink.add_point(Vector2(1, 0.2))
	p.scale_amount_curve = shrink
	parent.add_child(p)
	p.global_position = at
	p.emitting = true
	p.finished.connect(p.queue_free)


static var _droplet: Mesh


## One water droplet: a tiny faceted bead, pale and a little see-through.
static func droplet_mesh() -> Mesh:
	if _droplet:
		return _droplet
	var mesh := SphereMesh.new()
	mesh.radial_segments = 4
	mesh.rings = 2
	mesh.radius = 0.022
	mesh.height = 0.044
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.86, 0.94, 1.0, 0.8)
	mesh.material = mat
	_droplet = mesh
	return mesh


# --- the rod and the line --------------------------------------------------------------------

func _build_rod() -> void:
	var grip := Node3D.new()
	grip.name = "RodGrip"
	grip.position = Vector3(0.27, -0.36, -0.34)
	grip.rotation = Vector3(0.0, 0.1, -0.06)
	_vm_cam.add_child(grip)
	rod = Node3D.new()
	rod.name = "Rod"
	rod.visible = false
	grip.add_child(rod)
	_rod_pivot = Node3D.new()
	_rod_pivot.name = "Pivot"
	rod.add_child(_rod_pivot)
	_load_rod_model()


## The rod you own (models/tools/rod_<tier>.glb, else the plain one), rigged to bend.
func _load_rod_model() -> void:
	for n in _rod_pivot.get_children():
		n.free()
	var path := "res://models/tools/rod_%d.glb" % Tools.tier(&"rod")
	var scene: PackedScene = load(path) if ResourceLoader.exists(path) else ROD_MODEL
	var model := scene.instantiate() as Node3D
	_rod_pivot.add_child(model)
	for m in model.find_children("*", "MeshInstance3D", true, false):
		var mesh := m as MeshInstance3D
		mesh.layers = 2
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mesh.material_override = TOOL_MATERIAL
	# chain the sections on pivots at their bases, so the rod can bend: Mid hangs off Butt's end,
	# Tip off Mid's; each guide rides the section it sits on
	var mid_mesh := model.find_child("Mid", true, false) as Node3D
	var tip_mesh := model.find_child("Tip", true, false) as Node3D
	_mid = Node3D.new()
	_mid.name = "MidBend"
	model.add_child(_mid)
	_mid.position = mid_mesh.position
	_tip = Node3D.new()
	_tip.name = "TipBend"
	_mid.add_child(_tip)
	_tip.position = tip_mesh.position - mid_mesh.position
	for n in model.get_children():
		if n is MeshInstance3D and String(n.name).begins_with("Guide"):
			var along := -(n as Node3D).position.z
			if along > -tip_mesh.position.z:
				n.reparent(_tip, true)
			elif along > -mid_mesh.position.z:
				n.reparent(_mid, true)
	mid_mesh.reparent(_mid, true)
	tip_mesh.reparent(_tip, true)


func _kick(amount: float) -> void:
	_jerk_vel += amount * 18.0


func _animate_rod(delta: float) -> void:
	var target := ROD_REST
	match state:
		State.BACKCAST:
			var t := _t
			if t < back_time:
				target = lerpf(ROD_REST, ROD_BACK, ease(t / back_time, 0.5))
			else:
				target = lerpf(ROD_BACK, ROD_FORWARD, ease(clampf((t - back_time) / forward_time, 0.0, 1.0), 2.2))
			_angle = target  # the stroke itself is exact
		State.FLIGHT:
			target = ROD_FORWARD
		State.WAITING:
			target = ROD_WAIT
		State.RETRIEVE:
			target = ROD_WAIT + 0.15
		State.YANK:
			target = ROD_YANK
	if state != State.BACKCAST:
		_angle = lerpf(_angle, target, 1.0 - exp(-(16.0 if state == State.YANK else 7.0) * delta))
	# the tip's impulse: a damped spring
	_jerk_vel += (-_jerk * 160.0 - _jerk_vel * 14.0) * delta
	_jerk += _jerk_vel * delta
	var hooked := state == State.WAITING and is_instance_valid(lure) and lure.bite == FishingLure.Bite.TAKE
	if hooked:  # bent hard, thrumming as the fish pulls
		_bend = 0.55 + sin(_t * 55.0) * 0.05
		_line_tension = 1.0
	else:
		_bend = lerpf(_bend, 0.08 if state == State.WAITING else 0.0, 1.0 - exp(-5.0 * delta))
		if state == State.WAITING:
			_line_tension = 0.0
	_rod_pivot.rotation.x = _angle + _jerk * 0.15 - (0.12 if hooked else 0.0)
	_mid.rotation.x = -_bend * 0.3 - _jerk * 0.25
	_tip.rotation.x = -_bend * 0.55 - _jerk * 0.55
	# point the rod at the fish in the air (or the float), within reason
	var yaw := 0.0
	var at := Vector3.INF
	if is_instance_valid(caught):
		at = caught.global_position
	elif is_instance_valid(lure) and state == State.WAITING:
		at = lure.global_position
	if at != Vector3.INF:
		var local: Vector3 = player.camera.global_transform.affine_inverse() * at
		if local.z < -0.1:
			yaw = clampf(atan2(-local.x, -local.z), -0.5, 0.5) * 0.7
	_rod_yaw = lerpf(_rod_yaw, yaw, 1.0 - exp(-6.0 * delta))
	_rod_pivot.rotation.y = _rod_yaw


## The rod tip in the world, as the main camera would have to draw it to line up with the
## viewmodel's (its own, narrower FOV): the same point in camera space, widened by the FOV ratio.
func _tip_world() -> Vector3:
	var tip := _tip.global_transform * Vector3(0, 0, -ROD_TIP_LENGTH)
	var cam: Camera3D = player.camera
	var local := _vm_cam.global_transform.affine_inverse() * tip
	if local.z > -0.05:  # behind the eye (wound back over the shoulder)
		return cam.global_position + cam.global_basis.y * 0.4 - cam.global_basis.z * 0.2
	var widen := tan(deg_to_rad(cam.fov) * 0.5) / tan(deg_to_rad(_vm_cam.fov) * 0.5)
	return cam.global_transform * Vector3(local.x * widen, local.y * widen, local.z)


## The line is one triangle strip whose vertices are rewritten in place every frame (no new GPU
## buffer per frame), so the mesh is made once with LINE_POINTS points.
const LINE_POINTS := 24


func _build_line() -> void:
	var verts := PackedVector3Array()
	verts.resize((LINE_POINTS + 1) * 2)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	_line_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLE_STRIP, arrays)
	_line_mesh.custom_aabb = AABB(Vector3.ONE * -2000.0, Vector3.ONE * 4000.0)  # never culled
	_line = MeshInstance3D.new()
	_line.name = "FishingLine"
	_line.mesh = _line_mesh
	_line.top_level = true
	_line.visible = false
	_line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = Color(0.92, 0.94, 0.97, 0.6)
	_line.material_override = mat
	add_child(_line)


func _clear_line() -> void:
	_line.visible = false


## From the rod tip to the float: a sagging curve while it's slack (lying on the water where it
## reaches it), straight when there's a fish on (pulling under, or flying out on the end of it).
func _draw_line() -> void:
	if state == State.IDLE or state == State.DONE or state == State.BACKCAST or not is_instance_valid(lure):
		_line.visible = false
		return
	var a := _tip_world()
	var b := lure.global_position
	match state:
		State.FLIGHT:
			b = _flight_pos(clampf(_t / _flight_time, 0.0, 1.0))
			lure.global_position = b
		State.RETRIEVE:
			b = _retrieve_from.lerp(a, ease(clampf(_t / 0.45, 0.0, 1.0), 0.6))
			lure.global_position = b
		State.YANK:
			if is_instance_valid(caught):
				b = caught.global_position
				lure.global_position = b
			_line_tension = 1.0
	var length := a.distance_to(b)
	var sag := (1.0 - _line_tension) * length * (0.02 if state == State.FLIGHT else 0.035)
	var water_y := -INF
	if state == State.WAITING and lure.water:
		water_y = lure.water.surface_height + 0.004
	var cam: Camera3D = player.camera
	var pts := PackedVector3Array()
	for i in LINE_POINTS + 1:
		var f := float(i) / LINE_POINTS
		var p := a.lerp(b, f) + Vector3.DOWN * sag * 4.0 * f * (1.0 - f)
		p.y = maxf(p.y, water_y)
		pts.append(p)
	var verts := PackedVector3Array()
	verts.resize((LINE_POINTS + 1) * 2)
	for i in pts.size():
		var p := pts[i]
		var along := pts[mini(i + 1, LINE_POINTS)] - pts[maxi(i - 1, 0)]
		var side := along.cross(cam.global_position - p)
		if side.length_squared() < 1e-10:
			side = cam.global_basis.x
		side = side.normalized() * maxf(0.0011 * cam.global_position.distance_to(p), 0.0008)
		verts[i * 2] = p - side
		verts[i * 2 + 1] = p + side
	RenderingServer.mesh_surface_update_vertex_region(_line_mesh.get_rid(), 0, 0, verts.to_byte_array())
	_line.visible = true


# --- helpers --------------------------------------------------------------------------------

func _play_at(path: String, at: Vector3, pitch: float, db: float) -> void:
	var p := AudioStreamPlayer3D.new()
	p.stream = load(path)
	p.pitch_scale = pitch
	p.volume_db = db
	p.unit_size = 6.0
	player.get_parent().add_child(p)
	p.global_position = at
	p.play()
	p.finished.connect(p.queue_free)


func _ripple(at: Vector3, size: float) -> void:
	var w := WaterBody.surface_at(get_tree(), at)
	if w:
		WaterRipple.spawn(w, Vector3(at.x, w.surface_height, at.z), size, 0.8)


func _surface(p: Vector3) -> Vector3:
	var w := WaterBody.surface_at(get_tree(), p)
	return Vector3(p.x, w.surface_height if w else p.y, p.z)


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


static func _flat_dir(from: Vector3, to: Vector3) -> Vector3:
	var d := Vector3(to.x - from.x, 0.0, to.z - from.z)
	return d.normalized() if d.length_squared() > 0.0001 else Vector3.FORWARD
