class_name NodeSpawner
extends Node3D
## Places gatherable nodes (ResourceNode scenes, from `entries`) over the terrain at start-up,
## seeded so the layout is the same every run. Each gets a stable save id, <save_prefix>_<n>, so
## its state (depleted, respawn timer) saves like a hand-placed node's. Changing the seed, count,
## area or entries reshuffles them; their old save entries are then simply unused.
## Keeps off bare surfaces (paths, roads, quarry stone, crops — unless allowed), water and steep
## ground, keeps `spacing` between nodes, and keeps clear of buildings, props and the spawn.
## Put it at the scene's origin, above SceneryScatter in the tree, so the scenery keeps off its
## nodes too.
## With a frame_budget_ms it spreads the spawning over frames (so a big spawn doesn't hitch),
## the same nodes in the same places; `finished` says when it's done.

signal finished

const BARE_TEXTURES: Array[int] = [WorldMap.TEX_PATH, WorldMap.TEX_ROAD, WorldMap.TEX_QUARRY, WorldMap.TEX_CROP]
const SAND_HEIGHT := -0.04
const MAX_TRIES_PER_NODE := 40
## Nodes in the same square this size (m) are one cluster (see cluster_at).
const CLUSTER_SIZE := 14.0
## The shape families the baked variants are spread over (tools/blender/make_models.py FAMILIES).
const FAMILIES := 4

@export var entries: Array[SpawnEntry] = []
@export var count := 20
@export var seed := 1
@export var save_prefix := "spawned"
## World XZ rectangle to place in (x, z, width, depth).
@export var area := Rect2(-20, -20, 40, 40)
## Or a ring instead (centre x, z, inner radius, outer radius): one level of the quarry. An outer
## radius of 0 = use `area`.
@export var ring := Vector4.ZERO
## Only on these terrain texture ids (WorldMap.TEX_*). Empty = anywhere that isn't bare.
@export var allowed_ids: Array[int] = []
## Minimum distance between nodes (this spawner's and any already in the world).
@export var spacing := 4.5
## How far from bare ground (a path's edge) a node stands, so it's beside the trail, not on it.
@export var path_clearance := 1.5
@export_range(0.0, 1.0) var min_normal_y := 0.8
## How far each node's base sinks into the ground, so it doesn't float on slopes.
@export var sink := 0.15
## How the place dresses its nodes (moss, snow…); none = as made.
@export var theme: NodeTheme
## A rare look (data/themes/rare/) for the first tree or rock placed, with its bonus.
@export var rare: NodeTheme
@export_group("Hotspots")
## Spots the nodes crowd around, (x, z, radius): glades, the trail.
@export var hotspots := PackedVector3Array()
## Share of the nodes placed inside a hotspot; the rest go anywhere in the area.
@export_range(0.0, 1.0) var hotspot_share := 0.6
@export_group("Core and edge")
## An ellipse (centre x, z, radius x, z) over which the entries' weights slide from `weight` in
## the middle to `edge_weight` at the rim. Zero radii = off.
@export var ellipse := Vector4.ZERO
@export_group("Keep clear (m)")
@export var building_margin := 2.0
@export var prop_margin := 1.0
@export var spawn_radius := 4.0

## Milliseconds of spawning per frame before it waits for the next; 0 = all at once.
var frame_budget_ms := 0.0
var done := false

var _taken: Array[Vector3] = []  # (x, z, radius) already used


func _ready() -> void:
	_spawn.call_deferred()  # once the terrain, buildings and props are in place


func _spawn() -> void:
	var terrain := get_tree().get_first_node_in_group("terrain") as Terrain3D
	if terrain == null or terrain.data == null or entries.is_empty():
		push_warning("NodeSpawner %s: nothing to spawn on" % name)
		_finish()
		return
	var frame_start := Time.get_ticks_usec()
	_collect_taken()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var placed := 0
	for _try in count * MAX_TRIES_PER_NODE:
		if placed >= count:
			break
		# draw every random number before checking, so a rejected spot doesn't shift the rest
		var in_hotspot := rng.randf() < hotspot_share and not hotspots.is_empty()
		var spot := hotspots[rng.randi() % maxi(hotspots.size(), 1)] if not hotspots.is_empty() else Vector3.ZERO
		var off := Vector2.from_angle(rng.randf() * TAU) * sqrt(rng.randf()) * spot.z
		var anywhere := Vector2(rng.randf_range(area.position.x, area.end.x), rng.randf_range(area.position.y, area.end.y))
		if ring.w > 0.0:  # spread evenly over the ring's area
			var r := sqrt(lerpf(ring.z * ring.z, ring.w * ring.w, (anywhere.x - area.position.x) / area.size.x))
			anywhere = Vector2(ring.x, ring.y) + Vector2.from_angle((anywhere.y - area.position.y) / area.size.y * TAU) * r
		var pick := rng.randf()
		var yaw := rng.randf() * TAU
		var p := Vector2(spot.x, spot.y) + off if in_hotspot else anywhere
		var ground: Variant = _ground(terrain, p)
		if ground == null:
			continue
		var entry := _pick(p, pick)
		if entry == null:
			continue
		var node := entry.scene.instantiate() as ResourceNode
		node.save_id = StringName("%s_%03d" % [save_prefix, placed])
		var cluster := cluster_at(p)
		if not entry.variants.is_empty():
			var v := _pick_look(entry.variants.size(), cluster, hash(node.save_id))
			if v > 0:
				node.model = entry.variants[v - 1]
		if theme:
			node.look = theme.look(cluster, hash([seed, node.save_id]))
		if rare and node.skill in [&"woodcutting", &"mining"]:
			node.look = rare.look(cluster, hash([seed, node.save_id]))
			node.rare = rare
			rare = null  # (just the one)
		node.name = String(node.save_id)
		node.position = to_local(ground as Vector3) - Vector3.UP * sink
		node.rotation.y = yaw
		add_child(node)
		_taken.append(Vector3(p.x, p.y, spacing))
		placed += 1
		if frame_budget_ms > 0.0 and Time.get_ticks_usec() - frame_start > frame_budget_ms * 1000.0:
			await get_tree().process_frame
			frame_start = Time.get_ticks_usec()
	if placed < count:
		push_warning("NodeSpawner %s: only found room for %d of %d" % [name, placed, count])
	_finish()


func _finish() -> void:
	done = true
	finished.emit()


## The ground point at `p` if a node may stand there, else null.
func _ground(terrain: Terrain3D, p: Vector2) -> Variant:
	if ring.w > 0.0:
		var d := p.distance_to(Vector2(ring.x, ring.y))
		if d < ring.z or d > ring.w:
			return null
	elif not area.has_point(p):
		return null
	var at := Vector3(p.x, 0.0, p.y)
	var h: float = terrain.data.get_height(at)
	if is_nan(h) or h < SAND_HEIGHT:
		return null
	at.y = h
	if terrain.data.get_normal(at).y < min_normal_y:
		return null
	var id: int = terrain.data.get_control_base_id(at)
	if not _allowed(id):
		return null
	for o in [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)]:
		if terrain.data.get_control_base_id(at + o * path_clearance) in BARE_TEXTURES \
				and not _allowed(terrain.data.get_control_base_id(at + o * path_clearance)):
			return null
	if WaterBody.depth_at(get_tree(), at) > 0.0:
		return null
	for t in _taken:
		if (p.x - t.x) * (p.x - t.x) + (p.y - t.y) * (p.y - t.y) < t.z * t.z:
			return null
	return at


## The cluster world XZ `p` is in: nodes in the same CLUSTER_SIZE square share their shape family
## and where they sit in their theme's ranges, so neighbours look like siblings.
func cluster_at(p: Vector2) -> int:
	var cell := Vector2i((p / CLUSTER_SIZE).floor())
	return hash([seed, cell.x, cell.y])


## Which look a node wears out of a model and its `variants` (0 = the model, v = variant v): one of
## the cluster's shape family (tools/blender/make_models.py's recipe(): the model and every
## FAMILIES-th variant after it), told apart by `salt`.
static func _pick_look(variants: int, cluster: int, salt: int) -> int:
	var family := cluster % FAMILIES
	var looks: Array[int] = []
	for v in variants + 1:
		if v % FAMILIES == family:
			looks.append(v)
	if looks.is_empty():  # (fewer variants than families)
		return salt % (variants + 1)
	return looks[salt % looks.size()]


func _allowed(id: int) -> bool:
	if allowed_ids.is_empty():
		return id not in BARE_TEXTURES
	return id in allowed_ids


## An entry, chosen by weight (`pick` in 0..1), with the weights slid toward their edge values
## the further out of the ellipse's middle `p` is.
func _pick(p: Vector2, pick: float) -> SpawnEntry:
	var edge := 0.0
	if ellipse.z > 0.0 and ellipse.w > 0.0:
		edge = clampf(((p - Vector2(ellipse.x, ellipse.y)) / Vector2(ellipse.z, ellipse.w)).length(), 0.0, 1.0)
	var weights: Array[float] = []
	var total := 0.0
	for e in entries:
		var w := lerpf(e.weight, e.edge_weight if e.edge_weight >= 0.0 else e.weight, edge)
		weights.append(w)
		total += w
	if total <= 0.0:
		return null
	var x := pick * total
	for i in entries.size():
		x -= weights[i]
		if x <= 0.0:
			return entries[i]
	return entries[-1]


func _collect_taken() -> void:
	_taken.clear()
	for n in get_tree().get_nodes_in_group("gatherable"):
		var g := (n as Node3D).global_position
		_taken.append(Vector3(g.x, g.z, spacing))
	for p in get_tree().get_nodes_in_group("prop"):
		var g := (p as Node3D).global_position
		_taken.append(Vector3(g.x, g.z, (p as Prop).footprint_radius() + prop_margin))
	for b in get_tree().get_nodes_in_group("building"):
		var g := (b as Node3D).global_position
		_taken.append(Vector3(g.x, g.z, (b as Building).footprint_radius() + building_margin))
	for f in get_tree().get_nodes_in_group("fixture"):
		var g := (f as Node3D).global_position
		_taken.append(Vector3(g.x, g.z, (f as Fixture).footprint_radius() + building_margin))
	for k in get_tree().get_nodes_in_group("keep_clear"):  # (the hidden haven's glade)
		_taken.append(k.call("keep_clear"))
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player:
		_taken.append(Vector3(player.global_position.x, player.global_position.z, spawn_radius))
