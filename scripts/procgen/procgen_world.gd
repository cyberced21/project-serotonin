class_name ProcgenWorld
extends Node3D
## The root of scenes/procgen.tscn: on load it builds a ProcgenMap from `settings`, hands it to
## the Terrain3D child, places everything, and only then lets the player move, behind a loading
## screen. The map generates on a worker thread and the spawning is spread over frames
## (FRAME_BUDGET_MS each), so the window keeps drawing (and Windows never calls it hung).
## Worlds.play() sets `settings` and loads this scene; the world's save is its own folder's.

const Player := preload("res://scripts/player.gd")
const WATER_SHADER := preload("res://shaders/water.gdshader")
const PERCH := preload("res://data/fish/perch.tres")
const TROUT := preload("res://data/fish/trout.tres")
const PIKE := preload("res://data/fish/pike.tres")
const CHAR := preload("res://data/fish/char.tres")
const GRAYLING := preload("res://data/fish/grayling.tres")
const SALMON := preload("res://data/fish/salmon.tres")
## Schools per water body, as in the hand-built ponds and lake.
const POND_SCHOOLS: Array[FishSpecies] = [PERCH, PERCH, TROUT, PIKE]
const LAKE_SCHOOLS: Array[FishSpecies] = [TROUT, TROUT, PERCH, CHAR, CHAR]
const PIKE_SCHOOLS: Array[FishSpecies] = [PIKE, PIKE, PIKE]
## Rivers: grayling holding station in every RIVER_GRAYLING-th stretch, a salmon in each pool.
const RIVER_GRAYLING := 3
## How fast the current runs (m/s): it carries a float down to the grayling.
const RIVER_FLOW := 0.45
const PROP := preload("res://scripts/prop.gd")
## Milliseconds of building per frame while loading (0: all at once, the window frozen meanwhile).
static var frame_budget_ms := 12.0
## How the loading bar splits: the map, the terrain, the water and village, the nodes and scenery.
const SHARE_MAP := 0.35
const SHARE_TERRAIN := 0.1
const SHARE_PLACES := 0.05

## What the scene builds next time it loads (Worlds.play() sets them): a WorldSettings dictionary,
## and the world's name for the loading screen.
static var settings: Dictionary = WorldSettings.defaults()
static var world_name := ""
## Whether an older generator made this world's save (the land may differ from what it saw).
static var regenerated := false

var map: ProcgenMap
var world_seed: int
var _thread: Thread

@onready var _terrain := $Terrain3D as Terrain3D
@onready var _player := $Player as Player


func _ready() -> void:
	world_seed = WorldSettings.normalized(settings)["seed"]
	add_to_group("procgen_world")
	Biome.locator = func(_p: Vector3) -> StringName: return &""  # until the map exists
	_player.process_mode = Node.PROCESS_MODE_DISABLED
	var loading := LoadingScreen.new(world_name, Worlds.thumb_path(Worlds.current) if Worlds.current != "" else "")
	add_child(loading)
	await get_tree().process_frame
	var started := Time.get_ticks_msec()
	map = ProcgenMap.new(world_seed, settings)
	_thread = Thread.new()
	_thread.start(map.generate)
	while _thread.is_alive():
		loading.report(map.progress * SHARE_MAP, ProcgenMap.STAGES[map.stage])
		await get_tree().process_frame
	_thread.wait_to_finish()
	_thread = null
	var times := PackedStringArray(["map %d" % (Time.get_ticks_msec() - started)])
	var lap := Time.get_ticks_msec()
	await _build_terrain(func(t: float) -> void:
		loading.report(SHARE_MAP + t * SHARE_TERRAIN, "Laying the ground"))
	loading.report(SHARE_MAP + SHARE_TERRAIN, "Filling the water")
	await get_tree().process_frame
	_build_water()
	_build_rivers()
	loading.report(SHARE_MAP + SHARE_TERRAIN + SHARE_PLACES * 0.5, "Waking the village")
	await get_tree().process_frame
	_build_village()
	ProcgenLandmarks.build(self, map)
	var lamps := PathLamps.new()  # before the scenery, which keeps clear of the posts
	lamps.name = "PathLamps"
	lamps.procgen(map)
	add_child(lamps)
	Biome.locator = func(p: Vector3) -> StringName: return map.biome_at(Vector2(p.x, p.z))
	if not map.quarry.is_empty():
		Biome.quarry_rim_height = map.quarry["rim_height"]
		Biome.quarry_depth = map.quarry["depth"]
	for biome in map.kinds:
		Biome.kind_names[biome] = map.kind_name(biome)
	_place_player()
	times.append("ground, water, village %d" % (Time.get_ticks_msec() - lap))
	lap = Time.get_ticks_msec()
	await get_tree().process_frame  # the landmarks' meadows scatter first, as they always have
	var placed := SHARE_MAP + SHARE_TERRAIN + SHARE_PLACES
	await ProcgenPopulation.populate(self, map, frame_budget_ms, func(t: float) -> void:
		loading.report(placed + t * (1.0 - placed) * 0.95, "Growing the forest" if t < 0.6 else "Scattering the meadows"))
	times.append("nodes and scenery %d" % (Time.get_ticks_msec() - lap))
	loading.report(1.0, "Almost there")
	for i in 3:  # the first frames compile the shaders; keep them behind the loading screen
		await get_tree().process_frame
	print("Procgen: seed %d (%s) ready in %d ms: %s" % [world_seed, map.settings["size"],
			Time.get_ticks_msec() - started, ", ".join(times)])
	_player.process_mode = Node.PROCESS_MODE_INHERIT
	loading.queue_free()


func _exit_tree() -> void:
	if _thread:  # left while the map was still generating
		_thread.wait_to_finish()
	Biome.locator = Callable()
	Biome.reset_quarry()


## A WaterBody per basin the map carved, built like the hand-made ponds in main.tscn: a box volume,
## the water surface, reeds and lily pads (PondDressing) and fish (FishPond).
## Each river's water: one surface following its bends (a strip, the water shader works from world
## position), and a WaterBody every RIVER_SEGMENT metres along it, its box turned along the river,
## so wading, splashes and footsteps work in it like in a pond. Each stretch has the current
## (WaterBody.flow, downstream) and some hold fish: grayling every few stretches, a salmon where a
## pool was scoured out at a bend.
const RIVER_SEGMENT := 10


func _build_rivers() -> void:
	var material := ShaderMaterial.new()
	material.shader = WATER_SHADER
	for r in map.rivers.size():
		var pts: PackedVector2Array = map.rivers[r]["points"]
		var widths: PackedFloat32Array = map.rivers[r]["widths"]
		var river := Node3D.new()
		river.name = "River%d" % (r + 1)
		add_child(river)
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var y := ProcgenMap.WATER_LEVEL
		for k in pts.size() - 1:
			var a := pts[k]
			var b := pts[k + 1]
			var na := _across(pts, k) * (widths[k] + 2.0)
			var nb := _across(pts, k + 1) * (widths[k + 1] + 2.0)
			var al := Vector3(a.x - na.x, y, a.y - na.y)
			var ar := Vector3(a.x + na.x, y, a.y + na.y)
			var bl := Vector3(b.x - nb.x, y, b.y - nb.y)
			var br := Vector3(b.x + nb.x, y, b.y + nb.y)
			for v in [al, bl, ar, ar, bl, br]:
				st.set_normal(Vector3.UP)
				st.add_vertex(v)
		var surface := MeshInstance3D.new()
		surface.name = "Surface"
		surface.mesh = st.commit()
		surface.material_override = material
		surface.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		river.add_child(surface)
		var pools: PackedInt32Array = map.rivers[r].get("pools", PackedInt32Array())
		for k in range(0, pts.size() - 1, RIVER_SEGMENT):
			var a := pts[k]
			var b := pts[mini(k + RIVER_SEGMENT, pts.size() - 1)]
			var body := WaterBody.new()
			body.name = "Stretch%d" % (k / RIVER_SEGMENT + 1)
			body.position = Vector3((a.x + b.x) * 0.5, 0.0, (a.y + b.y) * 0.5)
			body.rotation.y = atan2(b.x - a.x, b.y - a.y)  # its box's length (Z) along the river
			body.collision_layer = 0
			body.collision_mask = 0
			body.surface_height = y
			var down := (b - a).normalized()
			body.flow = Vector3(down.x, 0.0, down.y) * RIVER_FLOW
			var volume := CollisionShape3D.new()
			volume.name = "Volume"
			volume.position.y = -1.0
			var box := BoxShape3D.new()
			box.size = Vector3(widths[k] * 2.0 + 6.0, 3.0, a.distance_to(b) + 2.0)
			volume.shape = box
			body.add_child(volume)
			var schools: Array[FishSpecies] = []
			for p in pools:
				if p >= k and p < k + RIVER_SEGMENT:
					schools.append(SALMON)
			if (k / RIVER_SEGMENT) % RIVER_GRAYLING == 1:
				schools.append(GRAYLING)
			if not schools.is_empty():
				var fish := FishPond.new()
				fish.name = "Fish"
				fish.schools = schools
				body.add_child(fish)
			river.add_child(body)


## The unit vector across the river at point k (to its right, looking downstream).
static func _across(pts: PackedVector2Array, k: int) -> Vector2:
	var along := (pts[mini(k + 1, pts.size() - 1)] - pts[maxi(k - 1, 0)]).normalized()
	return Vector2(-along.y, along.x)


## Hearthvale's buildings (each with its villager) and props, where the map laid them out. Their
## tiers are the Village autoload's, saved with this seed like everything else.
func _build_village() -> void:
	if map.village.is_empty():
		return
	var root := Node3D.new()
	root.name = "Village"
	add_child(root)
	var y: float = map.village["height"]
	for b in map.village["buildings"]:
		var building := (load("res://scenes/village/%s.tscn" % b[0]) as PackedScene).instantiate() as Node3D
		building.position = Vector3(b[1].x, y, b[1].y)
		building.rotation.y = b[2]
		root.add_child(building)
	for p in map.village["props"]:
		var prop := StaticBody3D.new()
		prop.set_script(PROP)
		prop.set("model", load("res://models/village/props/%s.glb" % p[0]))
		prop.position = Vector3(p[1].x, y, p[1].y)
		prop.rotation.y = p[2]
		root.add_child(prop)
	var decor := VillageDecor.new()  # the noticeboard, and the projects as they're done
	decor.name = "Decor"
	decor.center = map.village["center"]
	decor.angle = map.village["angle"]
	decor.hearthvale = false
	decor.footbridge_site = Footbridge.find_ford(map)
	root.add_child(decor)


func _build_water() -> void:
	var material := ShaderMaterial.new()
	material.shader = WATER_SHADER
	for i in map.waters.size():
		var w: Dictionary = map.waters[i]
		var r: float = w["radius"]
		var lake: bool = w["lake"]
		var size := 2.0 * r + 8.0  # the box covers the shallows round the ragged shore too
		var body := WaterBody.new()
		body.name = w["name"]
		body.position = Vector3(w["center"].x, 0.0, w["center"].y)
		body.collision_layer = 0
		body.collision_mask = 0
		body.surface_height = ProcgenMap.WATER_LEVEL
		var volume := CollisionShape3D.new()
		volume.name = "Volume"
		volume.position.y = -1.0
		var box := BoxShape3D.new()
		box.size = Vector3(size, 3.0, size)
		volume.shape = box
		body.add_child(volume)
		var dressing := PondDressing.new()
		dressing.name = "Dressing"
		dressing.seed = map.sub_seed(StringName("dressing_%d" % i))
		var area := r * r / 81.0  # relative to the hand-built clearing pond (radius 9)
		dressing.reed_clumps = roundi(9 * area)
		dressing.lily_pads = roundi(14 * area)
		dressing.stones = roundi(12 * sqrt(area))
		body.add_child(dressing)
		var fish := FishPond.new()
		fish.name = "Fish"
		fish.schools = LAKE_SCHOOLS if lake else POND_SCHOOLS
		if w.get("schools") == &"pike":  # a rare spot: nothing but pike
			fish.schools = PIKE_SCHOOLS
		body.add_child(fish)
		var surface := MeshInstance3D.new()
		surface.name = "Surface"
		surface.position.y = ProcgenMap.WATER_LEVEL
		surface.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var plane := PlaneMesh.new()
		plane.material = material
		plane.size = Vector2(size, size)
		plane.subdivide_width = int(size) - 1
		plane.subdivide_depth = int(size) - 1
		surface.mesh = plane
		body.add_child(surface)
		add_child(body)


## The heights, then the painted ground a few rows at a time (`on_progress` 0..1).
func _build_terrain(on_progress: Callable) -> void:
	var images: Array[Image] = []
	images.resize(Terrain3DRegion.TYPE_MAX)
	var corner := map.origin
	images[Terrain3DRegion.TYPE_HEIGHT] = map.height_image()
	# Terrain3D only takes whole regions, so a map that doesn't fill them (a small world) is padded
	# out to them with its own edge: the rim carries on to the regions' end
	var region := float(_terrain.region_size)
	var half := ceilf(map.metres * 0.5 / region) * region
	if half > map.metres * 0.5:
		corner = Vector2.ONE * -half
		images[Terrain3DRegion.TYPE_HEIGHT] = _padded(images[Terrain3DRegion.TYPE_HEIGHT], int(half * 2.0),
				Vector2i(map.origin - corner))
	_terrain.data.import_images(images, Vector3(corner.x, 0.0, corner.y), 0.0, 1.0)
	var frame_start := Time.get_ticks_usec()
	for y in map.size:
		for x in map.size:
			var id := map.ids[y * map.size + x]
			if id != WorldMap.TEX_DEFAULT:
				var w := map.world(x, y)
				_terrain.data.set_control_base_id(Vector3(w.x, 0, w.y), id)
		if frame_budget_ms > 0.0 and Time.get_ticks_usec() - frame_start > frame_budget_ms * 1000.0:
			on_progress.call(float(y + 1) / map.size)
			await get_tree().process_frame
			frame_start = Time.get_ticks_usec()
	_terrain.data.update_maps(Terrain3DRegion.TYPE_CONTROL)  # painting at runtime only reaches the GPU here


## `img` in the middle of an n × n image at `at`, each pixel round it a copy of the nearest edge pixel.
static func _padded(img: Image, n: int, at: Vector2i) -> Image:
	var out := Image.create_empty(n, n, false, img.get_format())
	var last := img.get_size() - Vector2i.ONE
	for y in n:
		for x in n:
			out.set_pixel(x, y, img.get_pixelv((Vector2i(x, y) - at).clamp(Vector2i.ZERO, last)))
	return out


## A fresh character starts in the hub; a saved one where they left off, but never under the ground.
## In a world an older generator made, the land may have moved: back to the hub.
func _place_player() -> void:
	var p := _player
	if not SaveGame.has(&"player") or regenerated:
		var at := map.hub
		p.teleport(Vector3(at.x, map.height_at(at) + 0.1, at.y), Vector3(at.x, 0, at.y - 10.0))
		return
	var pos := p.global_position
	var ground := map.height_at(Vector2(pos.x, pos.z))
	if pos.y < ground:
		p.teleport(Vector3(pos.x, ground + 0.1, pos.z))

