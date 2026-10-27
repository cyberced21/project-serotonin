extends RefCounted
## A bot that plays like a skilled player, for the benches (tools/fishing_bench.gd,
## tools/talent_bench.gd). It holds the real input actions and looks the real way; only walking
## between spots is a teleport, charged as game time at walking speed so it costs what a walk would.
##
##   fishing: the rod casts on the sweet spot and pulls a quarter second after the take; the spear
##            wades (crouched, the real wading noise) into reach of the nearest fish and thrusts.
##   gathering: stands at a tree, rock or sheaf and holds the swing, aiming where a skilled player
##            would: into the notch's mouth (a clean cut), at the nearest crack tip.
##
## Time is the game's own (the physics steps' deltas added up), run `speed` times faster.
## (Untyped on purpose: an -s script can't name the game's classes that use autoloads.)

# RodFishing.State / FishingLure.Bite / LandedFish.Phase, as ints
const WAITING := 3
const YANK := 5
const TAKE := 4
const FLY := 0
## Seconds from the take to the click: about a person's reaction.
const REACTION := 0.25
## How far from a node's centre the gatherer stands (m; the swing reaches 2.4 from the eye).
const STAND_OFF := 1.5
## Give up on a node after this long (game s): stuck, or out of reach.
const NODE_TIMEOUT := 40.0

var tree: SceneTree
## Gather only nodes of this tool tier (-1: any); an old-growth tree you can see always counts.
var only_tier := -1
var player
var speed := 3.0
var verbose := false
var clock := 0.0  # game seconds since start_clock(), walks charged included
var _timer: Node
var _clock0 := 0.0
var _charged := 0.0  # game seconds charged for walks the bot skipped (charge())
var _held := {}


func _init(scene_tree: SceneTree) -> void:
	tree = scene_tree
	mute()


## Silences the game (the master bus) unless `--sound=1`: benches run for minutes, sped up.
## start_clock() mutes again, as the settings can unmute it when they're applied.
func mute() -> void:
	if not "--sound=1" in OS.get_cmdline_user_args():
		AudioServer.set_bus_mute(0, true)


## Starts the game clock in the current scene, with `player` the scene's player.
func start_clock() -> void:
	mute()
	player = tree.get_first_node_in_group("player")
	_timer = Node.new()
	var counter := GDScript.new()
	counter.source_code = "extends Node
var t := 0.0
func _physics_process(d: float) -> void:
	t += d
"
	counter.reload()
	_timer.set_script(counter)
	_timer.process_mode = Node.PROCESS_MODE_ALWAYS
	tree.current_scene.add_child(_timer)
	await tree.physics_frame
	_clock0 = _timer.get("t")
	_charged = 0.0
	clock = 0.0


## Counts `seconds` of game time the bot didn't really play (a walk it skipped by teleporting).
## (The fishing bench used to add these to its clock, where the next steps swallowed them.)
func charge(seconds: float) -> void:
	_charged += seconds
	clock += seconds


# --- gathering ----------------------------------------------------------------------------------

## The nearest node of `skill` you can gather at your level and tools, or null. An old-growth
## tree you can see (the talent) is worth a walk: it counts as a quarter as far.
func nearest_node(skill: StringName):
	var best = null
	var best_d := INF
	for n in tree.get_nodes_in_group("gatherable"):
		if n.get("skill") != skill or not n.call("is_available") or not n.call("can_gather") or n.call("is_under_levelled"):
			continue
		var ancient: bool = skill == &"woodcutting" and n.call("_old_growth_active")
		if only_tier >= 0 and int(n.get("tool_tier")) != only_tier and not ancient:
			continue
		var d := flat(n.global_position, player.global_position)
		if ancient:
			d *= 0.25
		if d < best_d:
			best_d = d
			best = n
	return best


## Walks to the nearest node of `skill` and works it until it's gone (or NODE_TIMEOUT). With
## woodcutting talents it plays them as a player would: Power swing charges every swing, Back cut
## walks round to the far side once the notch is started.
func gather_try(skill: StringName) -> void:
	var node = nearest_node(skill)
	if node == null:
		why("gather: no %s node left" % skill)
		await wait_game(2.0)
		return
	await _stand_by(node)
	var talents = tree.root.get_node("Skills").get("talents")
	var power: bool = skill == &"woodcutting" and talents.call("has", &"power_swing")
	var back: bool = skill == &"woodcutting" and talents.call("has", &"back_cut")
	var went_round := false
	var t := 0.0
	while t < NODE_TIMEOUT and is_instance_valid(node) and node.call("is_available"):
		var c0 := clock
		if back and not went_round and int(node.get("_bites")) >= 3:
			went_round = true
			await _stand_by(node, true)
		look_at(_aim_point(node))
		if power:
			await _power_swing(node)
		else:
			set_held("gather", true)
			await step()
		t += clock - c0
	set_held("gather", false)
	if t >= NODE_TIMEOUT:
		why("gather: gave up on %s" % node.name)
	await wait_game(1.0)  # the drops land and fly over


## Power swing: hold until it's fully charged (tracking the aim), let go, wait out the swing.
func _power_swing(node) -> void:
	press("gather")
	var held := 0.0
	while held < float(player.get("power_charge_time")) + 0.1 and is_instance_valid(node) and node.call("is_available"):
		look_at(_aim_point(node))
		var c0 := clock
		await step()
		held += clock - c0
	release("gather")
	await step()
	while player.get("_swinging"):
		if is_instance_valid(node):
			look_at(_aim_point(node))
		await step()


## Where a skilled player aims at `node` for this swing.
func _aim_point(node) -> Vector3:
	var eye: Vector3 = player.camera.global_position
	var center: Vector3 = node.global_position
	match node.get("skill"):
		&"woodcutting":
			var knot = node.get("_knot")
			if knot != null and knot.visible:  # Heartwood's knot: hit it
				return knot.global_position
			var trunk = node.get("_trunk")
			var carve = node.get("_carve")
			if trunk != null and carve != null and carve.call("is_started"):
				# into the notch's mouth from this side, as ResourceNode._is_clean_cut checks
				var dir: Vector3 = trunk.global_transform.affine_inverse().basis * (eye - trunk.global_position)
				dir.y = 0.0
				var deep: float = carve.call("depth_toward", dir)
				return trunk.global_transform * (carve.call("bite_point", dir) + dir.normalized() * deep * 0.5)
			var base: Vector3 = trunk.global_position if trunk != null else center
			return Vector3(base.x, eye.y - 0.35, base.z)
		&"mining":
			var best := Vector3.INF
			for p in node.call("crack_tips"):
				if best == Vector3.INF or p.distance_to(eye) < best.distance_to(eye):
					best = p
			if best != Vector3.INF:
				return best
			return center + Vector3.UP * float(node.get("popup_height")) * 0.4
	return center + Vector3.UP * 0.4  # a sheaf


## Teleports to STAND_OFF from `node` on the side you're coming from (or the far side, for a back
## cut), charging the walk.
func _stand_by(node, far_side := false) -> void:
	var c: Vector3 = node.global_position
	var from := Vector3(player.global_position.x - c.x, 0, player.global_position.z - c.z)
	if from.length() < 0.1:
		from = Vector3.FORWARD
	if far_side:
		from = -from
	var at := c + from.normalized() * STAND_OFF
	var q := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 30.0, at + Vector3.DOWN * 30.0, 1)
	q.exclude = [player.get_rid()]
	var hit: Dictionary = player.get_world_3d().direct_space_state.intersect_ray(q)
	if hit:
		at = hit["position"] + Vector3.UP * 0.1
	charge(flat(at, player.global_position) / player.get("walk_speed"))
	player.call("teleport", at, c)
	await wait_game(0.3)


# --- the rod ------------------------------------------------------------------------------------

func rod_try(water) -> void:
	var rod = player.get_node("RodFishing")
	var school = nearest_school(water, "rod")
	if school == null:
		await wait_game(2.0)
		return
	await stand_on_shore(water, school, true)
	# cast a little short of the school (right on top of it spooks it)
	var c: Vector3 = center(school)
	var me: Vector3 = player.global_position
	var to := Vector3(c.x - me.x, 0, c.z - me.z)
	var aim := c - to.normalized() * 1.5 if to.length() > 3.5 else c
	look_at(Vector3(aim.x, water.surface_height, aim.z))
	await wait_game(0.2)
	if not rod.call("can_cast"):
		why("rod: can't cast at %s from %s (state %d)" % [aim, player.global_position, rod.get("state")])
		await wait_game(1.0)
		return
	press("gather")
	var sweet: float = rod.get("back_time") + rod.get("forward_time") * rod.get("sweet_spot")
	for k in 30:  # the back-cast starts on the player's next physics frame
		if rod.get("state") == 1:
			break
		await step()
	while rod.get("state") == 1 and rod.get("_t") < sweet - 1.5 / 60.0:
		await step()
	release("gather")
	await wait_game(1.2)
	if rod.get("state") != WAITING:
		why("rod: not floating after the cast (state %d)" % rod.get("state"))
		return
	var lure = rod.get("lure")
	var waited := 0.0
	while waited < 30.0 and is_instance_valid(lure) and rod.get("state") == WAITING:
		if lure.get("bite") == TAKE:
			await wait_game(REACTION)
			await tap("gather")
			break
		var c0 := clock
		await step()
		waited += clock - c0
	await wait_game(0.15)
	if rod.get("state") == YANK:
		var caught = rod.get("caught")
		while is_instance_valid(caught) and caught.get("phase") == FLY:
			await step()
		if is_instance_valid(caught):
			await wait_game(0.5)
			await walk_to(caught.global_position, 1.2, false)
			var t := 0.0
			while is_instance_valid(caught) and t < 3.0:
				var c0 := clock
				await step()
				t += clock - c0
	elif rod.get("state") == WAITING:  # nothing took it: reel in
		await tap("gather")
	while rod.get("state") != 0:
		await step()


## On the bank nearest `school`, within casting reach of it (the walk there is charged as game
## time at walking speed, if `charge`).
func stand_on_shore(water, school, charge: bool) -> void:
	if school == null:
		return
	var c: Vector3 = center(school)
	var best := Vector3.INF
	for k in 16:
		var dir := Vector3(sin(k * TAU / 16.0), 0, cos(k * TAU / 16.0))
		for s in 120:
			var p := c + dir * (s * 0.25)
			if water.call("depth_here", p) <= 0.0:
				var at := p + dir * 0.8
				if best == Vector3.INF or flat(at, player.global_position) < flat(best, player.global_position):
					if flat(at, c) < 11.0:
						best = at
				break
	if best == Vector3.INF:
		return
	var q := PhysicsRayQueryParameters3D.create(best + Vector3.UP * 30.0, best + Vector3.DOWN * 30.0, 1)
	q.exclude = [player.get_rid()]
	var hit: Dictionary = player.get_world_3d().direct_space_state.intersect_ray(q)
	if hit:
		best = hit["position"] + Vector3.UP * 0.1
	if charge and flat(best, player.global_position) > 1.5:
		charge(flat(best, player.global_position) / player.get("walk_speed"))
	if flat(best, player.global_position) > 0.5:
		player.call("teleport", best, c)
		await wait_game(0.3)


# --- the spear ----------------------------------------------------------------------------------

func spear_try(water) -> void:
	var spear = player.get("spearfishing")
	var f = nearest_fish(water)
	if f == null:
		await wait_game(2.0)
		return
	# wade over, crouched, until it's in reach
	if not await walk_to(f.global_position, 1.7, true, f):
		why("spear: couldn't wade to the %s (at %.1f m)" % [f.species.id if is_instance_valid(f) else "?", flat(f.global_position, player.global_position) if is_instance_valid(f) else -1.0])
		await wait_game(0.5)
		return
	# aim at it and thrust (a skilled player tracks it through the wind-up)
	var t := 0.0
	while t < 2.5 and is_instance_valid(f):
		look_at(f.global_position)
		if spear.get("fish_target") != null and not player.get("_swinging") and player.get("_cooldown") <= 0.0:
			press("gather")
			await step()
			await step()
			release("gather")
			while player.get("_swinging"):
				if is_instance_valid(f):
					look_at(f.global_position)
				await step()
			return
		var c0 := clock
		await step()
		t += clock - c0
	why("spear: no fish under the crosshair (water %s)" % spear.get("water"))


## The nearest fish your spear can take, by flat distance: one shallow enough for the spear's
## length (a player sees "Too deep" on the others).
func nearest_fish(water):
	var best = null
	var reach: float = player.get("spearfishing").call("_length") * 0.85  # (the thrust comes in at a slant)
	for s in schools(water):
		for f in s.fish:
			if f.lure != null or not f.call("tool_can_take", &"spear"):
				continue
			if water.surface_height - f.global_position.y > reach:
				continue
			if best == null or flat(f.global_position, player.global_position) < flat(best.global_position, player.global_position):
				best = f
	return best


# --- the water ----------------------------------------------------------------------------------

## Waters with fish in them, biggest first.
func waters() -> Array:
	var out := []
	for w in tree.get_nodes_in_group("water"):
		if not schools(w).is_empty():
			out.append(w)
	out.sort_custom(func(a, b) -> bool:
		var sa: Vector3 = a.get_node("Volume").shape.size
		var sb: Vector3 = b.get_node("Volume").shape.size
		return sa.x * sa.z > sb.x * sb.z)
	return out


func schools(water) -> Array:
	var out := []
	for s in tree.get_nodes_in_group("fish_school"):
		if s.water == water:
			out.append(s)
	return out


## The nearest school with a fish `tool` can take.
func nearest_school(water, tool: String):
	var best = null
	for s in schools(water):
		if s.fish.is_empty() or not s.fish[0].call("tool_can_take", StringName(tool)):
			continue
		if best == null or flat(center(s), player.global_position) < flat(center(best), player.global_position):
			best = s
	return best


func center(school) -> Vector3:
	var c := Vector3.ZERO
	for f in school.fish:
		c += f.global_position
	return c / maxf(school.fish.size(), 1)


# --- moving and looking -------------------------------------------------------------------------

## Walks (really: held keys, the real speed and footsteps) until within `near` of `at` (or of
## `follow`, which moves). False if it couldn't get there in 20 s.
func walk_to(at: Vector3, near: float, crouch: bool, follow = null) -> bool:
	if crouch:
		set_held("crouch", true)
	var t := 0.0
	var ok := false
	while t < 20.0:
		if follow != null:
			if not is_instance_valid(follow):
				break
			at = follow.global_position
		if flat(at, player.global_position) <= near:
			ok = true
			break
		var d: Vector3 = at - player.global_position
		player.rotation.y = atan2(-d.x, -d.z)
		set_held("move_up", true)
		var c0 := clock
		await step()
		t += clock - c0
	set_held("move_up", false)
	set_held("crouch", false)
	await wait_game(0.1)
	return ok


func look_at(p: Vector3) -> void:
	var eye: Vector3 = player.camera.global_position
	var d := p - eye
	player.rotation.y = atan2(-d.x, -d.z)
	player.set("_pitch", atan2(d.y, Vector2(d.x, d.z).length()))


func why(s: String) -> void:
	if verbose:
		print("  [%.0f s] %s" % [clock, s])


func flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


# --- time and input -----------------------------------------------------------------------------

## One physics frame (the game runs `speed` times faster; a hit-stop slows it).
func step() -> void:
	if is_equal_approx(Engine.time_scale, 1.0):
		Engine.time_scale = speed
	await tree.physics_frame
	if is_instance_valid(_timer):
		clock = float(_timer.get("t")) - _clock0 + _charged


func wait_game(seconds: float) -> void:
	var until := clock + seconds
	while clock < until:
		await step()


func wait_real(seconds: float) -> void:
	var end := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < end:
		await tree.process_frame


func press(action: String) -> void:
	Input.action_press(action)
	_held[action] = true


func release(action: String) -> void:
	Input.action_release(action)
	_held.erase(action)


func set_held(action: String, on: bool) -> void:
	if on and not _held.has(action):
		press(action)
	elif not on and _held.has(action):
		release(action)


func tap(action: String) -> void:
	press(action)
	await step()
	await step()
	release(action)


func release_all() -> void:
	for a in _held.keys():
		Input.action_release(a)
	_held.clear()
