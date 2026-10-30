extends SceneTree
## A polish audit of the whole world: a fresh Hearthvale with every building, tier, add-on and
## project built and every mine cell dug, looked over for things out of place. One line a finding:
##   WALK     a doorway or stair the player (real physics, holding forward) can't get through
##   FACE     a villager at work facing away from what they work at
##   SEAT     a seat with nothing to sit on, or sat in facing its back
##   FLOAT    meshes touching nothing that reaches the ground (hanging in the air), 10 cm or more clear
##   BURIED   a mesh mostly under the ground
##   CLIP     a prop, tree or rock out in the world poking into a building
##   GHOST    a collider with nothing visible in it (an invisible wall)
##   LOOSE    a collider reaching well past what you can see
##   SOLID?   something solid-looking you walk straight through
##   godot --headless --fixed-fps 60 --audio-driver Dummy --path . -s res://tools/audit_world.gd -- --save-root=user://tool_worlds [--only=walk,face,place]
## (A few minutes. The expected leftovers: the boarded-up tavern's door, the fisher's door seen from
## the water under its dock, and a villager standing in a doorway.)
## (MultiMesh scatter isn't checked: headless, its instance transforms don't read back.)
## (No game class names: an -s script compiles before the autoloads exist.)

## The audit's own copy of every visible mesh, as trimesh bodies on a layer nothing else uses.
const VIS_LAYER := 1 << 24
const WORLD_MASK := 1
## Never part of the world: the player's own view and the UI.
const NOT_WORLD := ["Viewmodel", "Player", "HUD", "Canvas", "Life/Critters"]  # (the butterflies, bees and birds fly)
## Names (a node's or its parent's) that are meant to hang, fly, flutter or float on the water:
## they still hold things up, but aren't reported.
const SKIP := ["Smoke", "Firefl", "Grass", "Water", "Surface", "Ripple", "Fish", "Ghost", "Villager",
	"Dog", "Bunting", "Pennant", "Flag", "Bird", "Cloud", "Moon", "Spark", "Dust", "Leaf", "Leaves",
	"Popup", "Outline", "Highlight", "Lure", "Bobber", "Halo", "lily", "Pad", "Petal", "Heart"]
## Soft things you're meant to walk through.
const SOFT := ["Bush", "Flower", "Fern", "Reed", "Grass", "Crop", "Wheat", "Barley", "Shrub", "Plant",
	"Herb", "Rug", "Carpet", "Mat", "Moss", "Petal", "Weed", "Ivy", "Vine", "Clover", "Mushroom",
	"Cloth", "Banner", "Curtain", "Puddle", "Path", "Road", "Decal", "Shadow", "Patch", "Pebble"]

var _findings := {}  # kind -> [lines]
var _only: PackedStringArray = []
var _player: CharacterBody3D
var _terrain: Terrain3D
var _vis := {}  # body RID -> MeshInstance3D
var _vis_of := {}  # MeshInstance3D -> StaticBody3D


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			_only = a.substr(7).split(",")
	_run.call_deferred()


func _wants(what: String) -> bool:
	return _only.is_empty() or _only.has(what)


func _run() -> void:
	for autoload in ["GraphicsSettings", "Settings"]:
		root.get_node(autoload).set("persist", false)
	root.get_node("Worlds").call("play_fresh")
	await process_frame
	while get_first_node_in_group("player") == null:
		await process_frame
	_player = get_first_node_in_group("player") as CharacterBody3D
	_terrain = get_first_node_in_group("terrain") as Terrain3D
	var village := root.get_node("Village")
	var projects := root.get_node("Projects")
	for p: Dictionary in projects.call("all"):
		projects.call("set_done", p["id"], true)
	await _settle(2.0)

	var buildings := get_nodes_in_group("building")
	var top := 1
	for b in buildings:
		top = maxi(top, b.get("def").call("max_tier"))
	for t in range(1, top + 1):
		for b in buildings:
			village.call("set_tier", b.get("def").get("id"), mini(t, b.get("def").call("max_tier")))
		await _settle(4.0)
		var label := "tier %d" % t
		if _wants("walk"):
			for b in buildings:
				if b.get("tier_shown") == t or (t == top and b.get("tier_shown") > 0):
					await _walk_building(b, label)
		if _wants("place") or _wants("face"):
			await _audit_placement(label, t == 1)
	# every add-on in turn (each building's slots), at the top tier
	if _wants("place"):
		for b in buildings:
			var def: Resource = b.get("def")
			for a: Resource in def.get("addons"):
				village.call("set_addon", def.get("id"), a.get("id"), a.get("slot"))
			await _settle(1.5)
			await _audit_placement("%s add-ons" % def.get("id"), false, b)
	# the mine: every level on show, every cell dug open (they're hidden until you go down)
	var mine := get_first_node_in_group("mine")
	if mine and _wants("place"):
		var layout: GDScript = load("res://scripts/mine_layout.gd")
		var levels: Array = mine.get("levels")
		for n in levels.size():
			for c in layout.call("cells", n):
				mine.call("open_cell", n, c)
			(levels[n] as Node3D).visible = true
		await _settle(2.0)
		await _audit_placement("mine", false, mine)
	_report()


func _settle(seconds: float) -> void:
	for i in int(seconds * 60.0):
		await physics_frame


func _add(kind: String, line: String) -> void:
	if not _findings.has(kind):
		_findings[kind] = []
	if not (_findings[kind] as Array).has(line):
		_findings[kind].append(line)


func _report() -> void:
	var total := 0
	for kind in ["WALK", "FACE", "SEAT", "FLOAT", "CLIP", "BURIED", "GHOST", "LOOSE", "SOLID?"]:
		if not _findings.has(kind):
			continue
		print("== %s (%d)" % [kind, _findings[kind].size()])
		for line in _findings[kind]:
			print("%-8s %s" % [kind, line])
		total += _findings[kind].size()
	print("audit_world: %d findings" % total)
	quit(0)


func _where(n: Node) -> String:
	var s := String(n.get_path()).replace("/root/", "")
	for cut in ["Main/", "Game/"]:
		s = s.trim_prefix(cut)
	return s


static func _v(p: Vector3) -> String:
	return "(%.1f, %.1f, %.1f)" % [p.x, p.y, p.z]


func _ground(p: Vector3) -> float:
	if _terrain and _terrain.data:
		var h: float = _terrain.data.get_height(p)
		if not is_nan(h):
			return h
	return -INF


# --- walking --------------------------------------------------------------------------------

## In through the front door, then up the stair and back down if there is one.
func _walk_building(b: Node3D, label: String) -> void:
	var t: int = b.get("tier_shown")
	if t <= 0:
		return
	var tier := b.get_node_or_null("Tier%d" % t)
	if tier == null:
		return
	var name: String = b.get("def").get("display_name")
	for m in tier.get_children():
		if not m is Marker3D:
			continue
		var mk := m as Marker3D
		if String(mk.name).begins_with("Doorway"):
			var inward := mk.global_basis.z
			inward.y = 0.0
			inward = inward.normalized()
			var out := mk.global_position - inward * 3.4
			out.y = maxf(_ground(out), mk.global_position.y - 2.0) + 0.05
			var got := await _walk(out, mk.global_position, 6.0)
			if got != "":
				_add("WALK", "%s %s: can't get in at %s from outside: %s" % [name, label, mk.name, got])
			var back := await _walk(mk.global_position + Vector3.UP * 0.05, out, 6.0)
			if back != "":
				_add("WALK", "%s %s: can't get back out of %s: %s" % [name, label, mk.name, back])
	var foot := tier.get_node_or_null("Stair0") as Marker3D
	var head := tier.get_node_or_null("Stair1") as Marker3D
	if foot and head:
		var up := await _walk(foot.global_position + Vector3.UP * 0.05, head.global_position, 10.0)
		if up != "":
			_add("WALK", "%s %s: can't walk up the stair: %s" % [name, label, up])
		var space := _player.get_world_3d().direct_space_state
		var top := head.global_position + Vector3.UP * 1.0
		var floor_hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(top, top + Vector3.DOWN * 2.0, WORLD_MASK, [_player.get_rid()]))
		if floor_hit.is_empty():
			_add("WALK", "%s %s: no floor under the stair's head at %s (a drop into the stairwell)" % [name, label, _v(head.global_position)])
		var down := await _walk(head.global_position + Vector3.UP * 0.05, foot.global_position, 10.0)
		if down != "":
			_add("WALK", "%s %s: can't walk down the stair: %s" % [name, label, down])


## Holds forward from `from`, steering at `to`. "" if it gets there, else where it got stuck.
func _walk(from: Vector3, to: Vector3, limit: float) -> String:
	_player.call("teleport", from, to)
	_player.velocity = Vector3.ZERO
	await physics_frame
	Input.action_press("move_up")
	var best := INF
	var best_at := from
	var still := 0.0
	var last := from
	var frames := int(limit * 60.0)
	var result := ""
	for i in frames:
		var d := to - _player.global_position
		_player.rotation.y = atan2(-d.x, -d.z)
		await physics_frame
		var p := _player.global_position
		var flat := Vector2(to.x - p.x, to.z - p.z).length()
		if flat < best:
			best = flat
			best_at = p
		if flat < 0.45 and absf(p.y - to.y) < 0.5:
			break
		still = still + 1.0 / 60.0 if p.distance_to(last) < 0.004 else 0.0
		last = p
		if p.y < from.y - 4.0 and p.y < to.y - 4.0:
			result = "fell through to %s" % _v(p)
			break
		if still > 1.0:
			var into := PackedStringArray()
			for c in _player.get_slide_collision_count():
				var col := _player.get_slide_collision(c)
				if col.get_normal().y < 0.7:
					var o := col.get_collider() as Node
					var hit := _where(o) if o else "?"
					# a building's tier body: name the piece (the shape's mesh) it bumped
					var shape := o.shape_owner_get_owner(o.shape_find_owner(col.get_collider_shape_index())) as Node3D \
							if o is CollisionObject3D else null
					if shape and shape.get_parent() == o and o.get_child_count() > 1:
						hit += "#" + _piece_at(o.get_parent(), shape.global_position, col.get_position())
					if not into.has(hit):
						into.append(hit)
			result = "stuck at %s, %.1f m short (%.2f m below), against %s" % [_v(p), flat, to.y - p.y, ", ".join(into)]
			break
		if i == frames - 1:
			result = "didn't arrive: closest %.1f m at %s" % [best, _v(best_at)]
	Input.action_release("move_up")
	await physics_frame
	return result


## The visible piece of building `b` nearest `at` (the one whose box holds it, smallest first).
func _piece_at(b: Node, _origin: Vector3, at: Vector3) -> String:
	var best := ""
	var best_size := INF
	for n in b.find_children("*", "MeshInstance3D", true, false):
		var m := n as MeshInstance3D
		if not m.is_visible_in_tree():
			continue
		var box: AABB = (m.global_transform * m.get_aabb()).grow(0.05)
		if box.has_point(at) and box.get_volume() < best_size:
			best_size = box.get_volume()
			best = String(m.name)
	return best




# --- villagers ------------------------------------------------------------------------------

## Everyone at their work spot for the tier on show: is what they work at in front of them?
func _audit_villagers(space: PhysicsDirectSpaceState3D, label: String) -> void:
	var water: GDScript = load("res://scripts/water_body.gd")
	for b in get_nodes_in_group("building"):
		var v := b.get_node_or_null("Villager")
		if v == null or b.get("tier_shown") == 0:
			continue
		var spot := b.call("work_spot") as Marker3D
		if spot == null:
			continue
		var f := spot.global_basis.z
		f.y = 0.0
		f = f.normalized()
		var at := spot.global_position
		var work := int(v.get("work"))  # Villager.Work: CHOP, HAMMER, FISH, ORATE, TEND, WIPE
		var who: String = v.call("display_name")
		var ahead := _probe(space, at, f)
		var behind := _probe(space, at, -f)
		var line := "%s [%s] at %s (%s) faces %s: ahead %s; behind %s" % [who, label, _v(at), spot.name,
				_v(f), ahead, behind]
		var bad := false
		match work:
			2:  # fishing: water out in front
				var wet := false
				for r in [1.0, 2.0, 3.0]:
					if float(water.call("depth_at", self, at + f * r)) > 0.05:
						wet = true
				bad = not wet
				if bad:
					var dirs := PackedStringArray()
					for i in 16:
						var d := Vector3(sin(i * TAU / 16.0), 0.0, cos(i * TAU / 16.0))
						for r in [1.0, 2.0, 3.0, 4.0, 6.0]:
							if float(water.call("depth_at", self, at + d * r)) > 0.05:
								dirs.append("%s at %.0f m" % [_v(d), r])
								break
					line += " (no water ahead; water: %s)" % (", ".join(dirs) if dirs else "none within 6 m")
			3:
				bad = ahead.begins_with("wall")  # orating at a wall
			_:
				bad = ahead == "nothing" or ahead.begins_with("wall")
		if bad:
			_add("FACE", line)
		else:
			print("face ok  " + line)


## Every seat on show (chairs, benches, stools): something to sit on under it, and its back (if it
## has one) behind the sitter, not in front.
func _audit_seats(space: PhysicsDirectSpaceState3D, label: String) -> void:
	for n in get_nodes_in_group("seat"):
		var m := n as Marker3D
		if m == null or not m.is_visible_in_tree():
			continue
		var f := m.global_basis.z
		f.y = 0.0
		f = f.normalized()
		var at := m.global_position
		var top := at + Vector3.UP * 1.0
		var r := space.intersect_ray(PhysicsRayQueryParameters3D.create(top, at + Vector3.DOWN * 0.3, VIS_LAYER))
		var seat_h := (r["position"] as Vector3).y - at.y if not r.is_empty() else -1.0
		var under: String = String((_vis.get(r["rid"]) as Node).name) if not r.is_empty() and _vis.has(r["rid"]) else "nothing"
		var back := _reach(space, at + Vector3.UP * 0.85, -f, 0.5)
		var front := _reach(space, at + Vector3.UP * 0.85, f, 0.35)
		var b := _building_of(m)
		var where := "%s %s [%s] at %s faces %s: seat %.2f m up (%s), back %s, front %s" % [
				b.get("def").get("display_name") if b else _where(m.get_parent()), m.name, label, _v(at), _v(f),
				seat_h, under, back, front]
		if seat_h < 0.2 or seat_h > 0.75:
			_add("SEAT", where + " (nothing to sit on)")
		elif front != "" and back == "":
			_add("SEAT", where + " (its back is in front)")
		else:
			print("seat ok  " + where)


## The name of the nearest mesh along `dir` from `from` within `dist`, or "".
func _reach(space: PhysicsDirectSpaceState3D, from: Vector3, dir: Vector3, dist: float) -> String:
	var r := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, from + dir * dist, VIS_LAYER))
	if r.is_empty() or not _vis.has(r["rid"]):
		return ""
	return String((_vis[r["rid"]] as Node).name)


## What's in front of `at` along `dir`, at a working height, within 1.6 m (or low, just in front).
func _probe(space: PhysicsDirectSpaceState3D, at: Vector3, dir: Vector3) -> String:
	for h in [0.9, 0.5, 1.3]:
		var from: Vector3 = at + Vector3.UP * h
		var r := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, from + dir * 1.6, VIS_LAYER))
		if not r.is_empty():
			var m: MeshInstance3D = _vis.get(r["rid"])
			var wall := m != null and absf((r["normal"] as Vector3).y) < 0.3 and (m.global_transform * m.get_aabb()).size.y > 2.5
			return "%s%s at %.1f m" % ["wall " if wall else "", String(m.name) if m else "?", from.distance_to(r["position"])]
	for d in [0.6, 1.0]:  # a low thing (a garden bed, a chopping block): look down onto it
		var top: Vector3 = at + dir * d + Vector3.UP * 1.2
		var r := space.intersect_ray(PhysicsRayQueryParameters3D.create(top, top + Vector3.DOWN * 1.4, VIS_LAYER))
		if not r.is_empty() and (r["position"] as Vector3).y > at.y + 0.12:
			var m: MeshInstance3D = _vis.get(r["rid"])
			return "%s (low) at %.1f m" % [String(m.name) if m else "?", d]
	return "nothing"


# --- placement ------------------------------------------------------------------------------

var _hulls := {}  # Mesh -> its convex hull (for contacts)
var _uf := {}  # union-find over meshes in contact


func _skipped(n: Node) -> bool:
	var p := String(n.get_path())
	for s in NOT_WORLD:
		if p.contains(s):
			return true
	return false


## Meant to hang, fly or float (not reported, see SKIP).
func _airy(n: Node) -> bool:
	var p := String(n.name) + "/" + String(n.get_parent().name)
	for s in SKIP:
		if p.containsn(s):
			return true
	return false


func _soft(n: Node) -> bool:
	var p := String(n.name) + " " + String(n.get_parent().name)
	for s in SOFT:
		if p.containsn(s):
			return true
	return false


func _meshes(under: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	for n in under.find_children("*", "MeshInstance3D", true, false):
		var m := n as MeshInstance3D
		if m.mesh == null or not m.is_visible_in_tree() or _skipped(m):
			continue
		if m.transparency >= 0.99 or m.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY:
			continue
		out.append(m)
	return out


func _building_of(n: Node) -> Node:
	var p := n.get_parent()
	while p:
		if p.is_in_group("building"):
			return p
		p = p.get_parent()
	return null


## The audit's trimesh copy of every visible mesh, so rays and shapes can find what's there.
func _build_vis() -> void:
	_free_vis()
	for m in _meshes(root):
		var faces := m.mesh.get_faces()
		if faces.is_empty():
			continue
		var body := StaticBody3D.new()
		body.collision_layer = VIS_LAYER
		body.collision_mask = 0
		var shape := CollisionShape3D.new()
		var tri := ConcavePolygonShape3D.new()
		tri.set_faces(faces)
		tri.backface_collision = true
		shape.shape = tri
		body.add_child(shape)
		m.add_child(body)
		_vis[body.get_rid()] = m
		_vis_of[m] = body


func _free_vis() -> void:
	for m in _vis_of:
		if is_instance_valid(_vis_of[m]):
			_vis_of[m].free()
	_vis.clear()
	_vis_of.clear()


## A scatter layer's body (SceneryScatter: boxes on trunks and boulders drawn by MultiMeshes).
func _scatter_body(body: Node) -> bool:
	return not body.get_parent().find_children("*", "MultiMeshInstance3D", false, false).is_empty()


func _audit_placement(label: String, with_world: bool, only_under: Node = null) -> void:
	_build_vis()
	await physics_frame
	await physics_frame
	var space := _player.get_world_3d().direct_space_state
	if _wants("face") and only_under == null:
		_audit_villagers(space, label)
		_audit_seats(space, label)
	if _wants("place"):
		var scope: Array[MeshInstance3D] = []
		for m: MeshInstance3D in _vis_of:
			var b := _building_of(m)
			if only_under != null and b != only_under and not only_under.is_ancestor_of(m):
				continue
			if only_under == null and not with_world and b == null:
				continue  # the world outside the buildings: once, at tier 1
			scope.append(m)
		_check_floating(space, scope, label)
		_check_clipping(space, scope, label)
		if only_under == null:
			_check_colliders(space, label, with_world)
	_free_vis()


## `m`'s transform grown by `gap` on every side of its box (Jolt ignores a query's margin).
static func _inflated(m: MeshInstance3D, gap: float) -> Transform3D:
	var box := m.get_aabb()
	var scale := Vector3.ONE
	for i in 3:
		scale[i] = (box.size[i] + 2.0 * gap) / maxf(box.size[i], 0.01)
	var c := box.get_center()
	return m.global_transform * Transform3D(Basis.from_scale(scale), c - Basis.from_scale(scale) * c)


func _find(m: Object) -> Object:
	while _uf[m] != m:
		_uf[m] = _uf[_uf[m]]
		m = _uf[m]
	return m


## Floating: a group of meshes touching each other where none reaches the ground (or a floor, a
## wall, a post that does). Buried: a mesh wholly under the ground.
func _check_floating(space: PhysicsDirectSpaceState3D, scope: Array[MeshInstance3D], label: String) -> void:
	_uf.clear()
	var grounded := {}
	for m: MeshInstance3D in _vis_of:
		_uf[m] = m
	for m: MeshInstance3D in _vis_of:
		var box: AABB = m.global_transform * m.get_aabb()
		for c in [Vector2(0.5, 0.5), Vector2(0.15, 0.15), Vector2(0.85, 0.85), Vector2(0.15, 0.85), Vector2(0.85, 0.15)]:
			var g := _ground(Vector3(box.position.x + box.size.x * c.x, 0.0, box.position.z + box.size.z * c.y))
			if g > -INF and box.position.y <= g + 0.1 and box.end.y > g - 2.0:
				grounded[m] = true
				break
		if String(m.get_parent().name) == "Rock":
			grounded[m] = true  # a mine level's rock: the ground down there
		if not _hulls.has(m.mesh):
			_hulls[m.mesh] = m.mesh.create_convex_shape(true, false)
		var q := PhysicsShapeQueryParameters3D.new()
		q.shape = _hulls[m.mesh]
		q.transform = _inflated(m, 0.03)
		q.collision_mask = VIS_LAYER
		q.exclude = [_vis_of[m].get_rid()]
		for h in space.intersect_shape(q, 64):
			var o: MeshInstance3D = _vis.get(h["rid"])
			if o:
				var a := _find(m)
				var b := _find(o)
				if a != b:
					_uf[a] = b
	var down := {}  # component root -> true when any member's grounded
	for m in grounded:
		down[_find(m)] = true
	var seen := {}
	for m in scope:
		var box: AABB = m.global_transform * m.get_aabb()
		var g := _ground(box.get_center())
		if g > -INF and box.end.y < g - 0.02 and box.end.y > g - 3.0 and box.size.y > 0.1 and not _building_of(m):
			_add("BURIED", "%s [%s] wholly under the ground at %s (top %.2f, ground %.2f)" % [_where(m), label, _v(box.get_center()), box.end.y, g])
		var r := _find(m)
		if down.has(r) or seen.has(r) or _airy(m):
			continue
		seen[r] = true
		var members: Array[MeshInstance3D] = []
		var all := AABB()
		for o: MeshInstance3D in _vis_of:
			if _find(o) == r:
				var ob: AABB = o.global_transform * o.get_aabb()
				all = ob if members.is_empty() else all.merge(ob)
				members.append(o)
		if all.size.length() < 0.05:
			continue
		# how far it hangs over whatever's under it
		var excl: Array[RID] = []
		for o in members:
			excl.append(_vis_of[o].get_rid())
		var from := Vector3(all.get_center().x, all.position.y + 0.02, all.get_center().z)
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 8.0, VIS_LAYER, excl))
		var under := "ground"
		var h := _ground(from)
		if not hit.is_empty() and (hit["position"] as Vector3).y > h:
			h = (hit["position"] as Vector3).y
			var o: MeshInstance3D = _vis.get(hit["rid"])
			under = String(o.name) if o else "?"
		# and how far it is from touching anything at all
		var near := "nothing within 1 m"
		for gap in [0.06, 0.1, 0.15, 0.3, 0.6, 1.0]:
			var hit_any := ""
			for o in members:
				var q := PhysicsShapeQueryParameters3D.new()
				q.shape = _hulls[o.mesh]
				q.transform = _inflated(o, gap)
				q.collision_mask = VIS_LAYER
				q.exclude = excl
				for hh in space.intersect_shape(q, 4):
					var n: MeshInstance3D = _vis.get(hh["rid"])
					if n:
						hit_any = String(n.name)
						break
				if hit_any != "":
					break
			if hit_any != "":
				near = "%s within %.2f m" % [hit_any, gap]
				break
		if near.ends_with("0.06 m") or near.ends_with("0.10 m"):
			continue  # all but touching: closer than this audit can tell
		var names := PackedStringArray()
		for o in members.slice(0, 3):
			names.append(_where(o))
		_add("FLOAT", "%s%s [%s] %.2f m over %s at %s (size %s); nearest: %s" % [", ".join(names),
				" +%d more" % (members.size() - 3) if members.size() > 3 else "", label,
				all.position.y - h, under, _v(all.get_center()), _v(all.size), near])


## Clipping: something out in the world (a prop, a tree, a rock, the decor) whose core is inside
## a building's walls, floor or roof.
func _check_clipping(space: PhysicsDirectSpaceState3D, scope: Array[MeshInstance3D], label: String) -> void:
	for m in scope:
		if _building_of(m) != null or _soft(m) or _airy(m):
			continue
		var box: AABB = m.global_transform * m.get_aabb()
		if box.size.x < 0.3 or box.size.y < 0.3 or box.size.z < 0.3 or box.size.length() > 14.0:
			continue  # (small bits, and the big things: terrain dressing, the mine's rock)
		var q := PhysicsShapeQueryParameters3D.new()
		q.shape = _hulls[m.mesh]
		q.transform = _inflated(m, -0.12)  # its core
		q.collision_mask = VIS_LAYER
		for h in space.intersect_shape(q, 8):
			var o: MeshInstance3D = _vis.get(h["rid"])
			if o == null or _building_of(o) == null or _soft(o) or String(o.name).containsn("Floor"):
				continue
			_add("CLIP", "%s [%s] at %s size %s pokes into %s" % [_where(m), label, _v(box.get_center()), _v(box.size), _where(o)])
			break


func _check_colliders(space: PhysicsDirectSpaceState3D, label: String, with_world: bool) -> void:
	var bodies := {}  # StaticBody3D -> [CollisionShape3D]
	for n in root.find_children("*", "CollisionShape3D", true, false):
		var cs := n as CollisionShape3D
		var body := cs.get_parent() as StaticBody3D
		if body == null or cs.disabled or cs.shape == null or body.collision_layer & WORLD_MASK == 0:
			continue
		if body.get_parent() is Terrain3D or cs.shape is HeightMapShape3D or cs.shape is WorldBoundaryShape3D \
				or _skipped(body) or not body.is_inside_tree():
			continue
		if _building_of(body) == null and not with_world:
			continue
		if not bodies.has(body):
			bodies[body] = []
		bodies[body].append(cs)
	for body: StaticBody3D in bodies:
		var in_building := _building_of(body) != null
		# a prop's own meshes: under the body, else beside it under its parent (a tier's body has none)
		var own := AABB()
		var any_own := false
		if not (in_building and String(body.name).ends_with("Body")):
			var owner_node: Node = body if not _meshes(body).is_empty() else body.get_parent()
			for m in _meshes(owner_node):
				var mb: AABB = m.global_transform * m.get_aabb()
				own = mb if not any_own else own.merge(mb)
				any_own = true
		for cs: CollisionShape3D in bodies[body]:
			var dbg := cs.shape.get_debug_mesh()
			if dbg == null:
				continue
			var box: AABB = cs.global_transform * dbg.get_aabb()
			if box.size.y < 0.05:
				continue
			var where := "%s [%s] at %s size %s" % [_where(cs), label if in_building else "world", _v(box.get_center()), _v(box.size)]
			# anything visible in it at all?
			if not cs.shape is ConcavePolygonShape3D:
				var q := PhysicsShapeQueryParameters3D.new()
				q.shape = cs.shape
				q.transform = cs.global_transform
				q.collision_mask = VIS_LAYER
				q.margin = 0.02
				if space.intersect_shape(q, 1).is_empty() and not _scatter_body(body):
					if box.end.y > _ground(box.get_center()) + 0.3:
						_add("GHOST", where)
					continue
			if not any_own:
				continue
			var over := maxf(maxf(own.position.x - box.position.x, box.end.x - own.end.x),
					maxf(own.position.z - box.position.z, box.end.z - own.end.z))
			var up := box.end.y - own.end.y
			if over > 0.3 or up > 0.4:
				_add("LOOSE", "%s reaches %.2f m past its meshes sideways, %.2f m above (meshes %s at %s)" % [where, over, up, _v(own.size), _v(own.get_center())])
	# solid-looking things you walk through: big, near the ground, nothing on the world layer in them
	for m: MeshInstance3D in _vis_of:
		var box: AABB = m.global_transform * m.get_aabb()
		if box.size.y < 0.6 or box.size.x < 0.25 or box.size.z < 0.25 or _soft(m) or String(m.name).contains("DoorFrame"):
			continue
		var in_building := _building_of(m) != null
		if not in_building and not with_world:
			continue
		var g := _ground(box.get_center())
		if g > -INF and box.position.y > g + 1.2:
			continue  # overhead: roofs, branches
		if not _hulls.has(m.mesh):
			_hulls[m.mesh] = m.mesh.create_convex_shape(true, false)
		var q := PhysicsShapeQueryParameters3D.new()
		q.shape = _hulls[m.mesh]
		q.transform = m.global_transform
		q.collision_mask = WORLD_MASK | (1 << 6)
		var solid := false
		for h in space.intersect_shape(q, 16):
			var c := h["collider"] as Node
			if c and not c.get_parent() is Terrain3D:
				solid = true
				break
		if not solid:
			_add("SOLID?", "%s [%s] at %s size %s has nothing to bump into" % [_where(m), label if in_building else "world", _v(box.get_center()), _v(box.size)])
