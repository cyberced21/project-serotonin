class_name PathLamps
extends Node3D
## Lamp posts along the world's roads (plans/lamps.md). The roads are cut into stretches, each with
## an id the Lamps autoload saves as lit or not; a lit stretch gets a post every SPACING metres,
## on alternate sides, its arm reaching over the road. Unlit stretches have no posts at all, so
## lighting one (a project, later) visibly adds them.
## At dusk they catch one after another in a wave out from the village (L4), each with a little
## sputter before it takes, and at dawn go out the same way. They're kept out of the Sky's
## "night_light" / "night_glow" groups (which light everything at once) and lit from here.
## Hearthvale's stretches come from WorldMap (hearthvale()).

## A lamp catches (for its sound): where.
signal lamp_caught(at: Vector3)

const SPACING := 20.0
## The first post this far along a stretch (from its village end): the square has its own lamps.
const FIRST := 12.0
## Posts stand this far beyond the path's edge.
const SIDE_GAP := 0.9
## No two posts closer than this (where stretches meet).
const MIN_GAP := 12.0
## Kept this far from buildings (from their middle) and from gatherable nodes.
const BUILDING_CLEARANCE := 9.0
const NODE_CLEARANCE := 2.5
## Steeper ground than this (height change over a metre) gets no post.
const MAX_SLOPE := 0.6
## Over water, ground must stand this far above the surface for a post.
const WATER_MARGIN := 0.4
## Lights fade out this far away (the posts stay): a far road's pools of light cost nothing.
const LIGHT_FADE_BEGIN := 70.0
const LIGHT_FADE_LENGTH := 25.0
## The square's lamppost on the village's own stretches, the rustic one on the far roads (L5).
const VILLAGE_MODEL := preload("res://models/village/props/lamp_post.glb")
const FAR_MODEL := preload("res://models/village/props/lamp_post_rustic.glb")
## The wave: how dark it must be (the Sky's night amount, 0 by day to 1) before the village's
## nearest lamp catches, and how much darker before the farthest one does.
const WAVE_START := 0.12
const WAVE_SPREAD := 0.5
## A lamp catching: brightness over its first moments [seconds, level], then it holds.
const CATCH: Array[Vector2] = [Vector2(0.0, 0.0), Vector2(0.05, 0.7), Vector2(0.1, 0.15),
	Vector2(0.18, 0.85), Vector2(0.27, 0.3), Vector2(0.4, 0.6), Vector2(0.8, 1.0)]
## Going out at dawn takes this long.
const FADE_OUT := 1.5
## Sounds (audio/lamps/SOURCES.md): a soft whoomp as a lamp within CATCH_RANGE catches, and the
## crackle of the flame of the lit lamp nearest you, heard only right beside it.
const CATCHES: Array[AudioStream] = [preload("res://audio/lamps/catch_1.wav"),
	preload("res://audio/lamps/catch_2.wav"), preload("res://audio/lamps/catch_3.wav"),
	preload("res://audio/lamps/catch_4.wav")]
const CRACKLE := preload("res://audio/lamps/crackle.wav")
const CATCH_RANGE := 35.0
const CATCH_DB := -12.0
const CRACKLE_DB := -16.0
## A road just lit (a project paid for): its posts pop up one after another along it, this many
## seconds apart, and each catches as it does if it's dark.
const NEW_ROAD_STEP := 0.35

## {id: StringName, title: String, pts: PackedVector2Array (world XZ, from the village end),
## half_width: float, village: bool}
var stretches: Array[Dictionary] = []
## Where the wave of lighting starts at dusk (phase 2): the middle of the village square.
var village_center := Vector2.ZERO

var _terrain: Terrain3D
## One per post: {glow: Array[GeometryInstance3D], lights: Array[Light3D], wave: float 0..1,
## on: bool, since: float (seconds since it last caught or went out), level: float}
var _lamps: Array[Dictionary] = []
var _first := true  # the first frame sets every lamp as it should be, no wave
var _crackle: LoopBed
var _lit_before: Dictionary[StringName, bool] = {}  # the stretches lit at the last rebuild
var _built_once := false


func _ready() -> void:
	add_to_group("path_lamps")
	_crackle = LoopBed.new()
	_crackle.name = "Crackle"
	_crackle.stream = CRACKLE
	_crackle.positional = true
	_crackle.unit_size = 1.2
	_crackle.max_distance = 7.0
	_crackle.trim_db = CRACKLE_DB
	_crackle.top_level = true
	add_child(_crackle)
	_terrain = get_tree().get_first_node_in_group("terrain") as Terrain3D
	if stretches.is_empty():
		hearthvale()
	var listed: Array[Dictionary] = []
	for s in stretches:
		# how far out it runs on average (cheaper lamps near the village: every road in the bowl
		# starts at the green's edge, so the nearest point says nothing)
		var reach := 0.0
		for p in s["pts"]:
			reach += (p as Vector2).distance_to(village_center)
		reach /= maxf(s["pts"].size(), 1)
		listed.append({"id": s["id"], "title": s["title"], "closest": reach})
	Lamps.stretches = listed
	Lamps.changed.connect(_rebuild)
	_rebuild()


func _exit_tree() -> void:
	Lamps.stretches = []


## The posts standing now (all stretches).
func posts() -> Array[Prop]:
	var out: Array[Prop] = []
	for c in get_children():
		if c is Prop:
			out.append(c)
	return out


func _rebuild() -> void:
	for c in get_children():
		if c != _crackle:
			remove_child(c)
			c.queue_free()
	_lamps.clear()
	var avoid := _obstacles()
	var placed := PackedVector2Array()
	var fresh: Dictionary[StringName, bool] = {}
	for s in stretches:
		if Lamps.is_lit(s["id"]):
			if _built_once and not _lit_before.has(s["id"]):
				fresh[s["id"]] = true
			_place_stretch(s, avoid, placed)
	_lit_before.clear()
	for s in stretches:
		if Lamps.is_lit(s["id"]):
			_lit_before[s["id"]] = true
	_built_once = true
	var order: Dictionary[StringName, int] = {}
	for i in _lamps.size():
		var prop: Prop = _lamps[i]["prop"]
		var st: StringName = prop.get_meta("stretch")
		if fresh.has(st):
			var k: int = order.get(st, 0)
			order[st] = k + 1
			_lamps[i]["delay"] = 0.4 + k * NEW_ROAD_STEP
			_pop_in(prop, _lamps[i]["delay"])
	var farthest := 1.0
	for p in placed:
		farthest = maxf(farthest, p.distance_to(village_center))
	for i in _lamps.size():
		_lamps[i]["wave"] = placed[i].distance_to(village_center) / farthest
	_first = true


func _process(delta: float) -> void:
	var night := DayNight.darkness()
	var t := Time.get_ticks_msec() / 1000.0
	for lamp in _lamps:
		var on := night > WAVE_START + float(lamp["wave"]) * WAVE_SPREAD
		if float(lamp["delay"]) > 0.0:  # a new road's post, not up yet
			lamp["delay"] = float(lamp["delay"]) - delta
			on = false
		lamp["since"] = float(lamp["since"]) + delta
		if on != lamp["on"]:
			lamp["on"] = on
			lamp["since"] = 0.0
			if on and not _first and not (lamp["lights"] as Array).is_empty():
				_caught((lamp["lights"][0] as Light3D).global_position)
		var level: float
		if _first:
			level = 1.0 if on else 0.0
		elif on:
			level = _catch(lamp["since"])
		else:
			level = minf(float(lamp["level"]), 1.0 - float(lamp["since"]) / FADE_OUT)
		level = maxf(level, 0.0)
		if level == 0.0 and lamp["level"] == 0.0:
			continue
		lamp["level"] = level
		for g in lamp["glow"]:
			(g as GeometryInstance3D).set_instance_shader_parameter("glow", level)
		for l in lamp["lights"]:  # firelight flickers, each lamp out of step (as the Sky's do)
			var light := l as Light3D
			var ph := float(light.get_instance_id() % 997)
			var flicker := 1.0 + 0.1 * sin(t * 8.3 + ph) + 0.06 * sin(t * 21.7 + ph * 1.7)
			light.visible = level > 0.01
			light.light_energy = level * float(light.get_meta("night_energy", 1.0)) * flicker
	_first = false
	_place_crackle()


## A new road's post rising out of the ground after `delay` seconds, with a wooden tok.
func _pop_in(prop: Prop, delay: float) -> void:
	prop.scale = Vector3.ONE * 0.01
	var t := prop.create_tween()  # (dies with the post, if the road is rebuilt meanwhile)
	t.tween_interval(delay)
	t.tween_callback(func() -> void:
		var tok := AudioStreamPlayer3D.new()
		tok.stream = VillageDecor.TOK
		tok.bus = &"SFX"
		tok.unit_size = 6.0
		tok.max_distance = 45.0
		tok.top_level = true
		prop.add_child(tok)
		tok.global_position = prop.global_position
		tok.finished.connect(tok.queue_free)
		tok.play())
	t.tween_property(prop, "scale", Vector3.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _caught(at: Vector3) -> void:
	lamp_caught.emit(at)
	var cam := get_viewport().get_camera_3d()
	if cam == null or cam.global_position.distance_to(at) > CATCH_RANGE:
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = CATCHES.pick_random()
	p.pitch_scale = randf_range(0.9, 1.08)
	p.volume_db = CATCH_DB
	p.bus = &"SFX"
	p.unit_size = 4.0
	p.max_distance = CATCH_RANGE
	p.top_level = true
	add_child(p)
	p.global_position = at
	p.finished.connect(p.queue_free)
	p.play()


## The crackle sits on the lit lamp nearest you, as loud as that lamp burns.
func _place_crackle() -> void:
	var cam := get_viewport().get_camera_3d()
	var best: Dictionary = {}
	var best_d := INF
	if cam:
		for lamp in _lamps:
			if float(lamp["level"]) > 0.0 and not (lamp["lights"] as Array).is_empty():
				var d := cam.global_position.distance_squared_to((lamp["lights"][0] as Light3D).global_position)
				if d < best_d:
					best_d = d
					best = lamp
	_crackle.level = float(best.get("level", 0.0))
	if not best.is_empty():
		_crackle.global_position = (best["lights"][0] as Light3D).global_position


## How bright a lamp is `t` seconds after it catches.
static func _catch(t: float) -> float:
	for i in range(1, CATCH.size()):
		if t < CATCH[i].x:
			return lerpf(CATCH[i - 1].y, CATCH[i].y, (t - CATCH[i - 1].x) / (CATCH[i].x - CATCH[i - 1].x))
	return 1.0


## A post every SPACING metres, on alternate sides; where one doesn't fit (a tree, a steep bank,
## water), the other side, then a few metres further on.
func _place_stretch(s: Dictionary, avoid: Array, placed: PackedVector2Array) -> void:
	var pts: PackedVector2Array = s["pts"]
	var dist := PackedFloat32Array([0.0])
	for i in pts.size() - 1:
		dist.append(dist[i] + pts[i].distance_to(pts[i + 1]))
	var total := dist[dist.size() - 1]
	var off: float = float(s["half_width"]) + SIDE_GAP
	var side := 1.0
	var at := FIRST
	while at < total:
		var shift := 0.0
		var done := false
		while not done and shift <= SPACING * 0.5 and at + shift < total:
			var i := clampi(dist.bsearch(at + shift, false) - 1, 0, pts.size() - 2)
			var span := maxf(dist[i + 1] - dist[i], 0.001)
			var along := (pts[i + 1] - pts[i]) / span
			var left := Vector2(-along.y, along.x)
			var mid := pts[i].lerp(pts[i + 1], clampf((at + shift - dist[i]) / span, 0.0, 1.0))
			for sd in [side, -side]:
				var p: Vector2 = mid + left * off * sd
				if _fits(p, avoid, placed):
					_post(p, -left * sd, s["village"], s["id"])
					placed.append(p)
					side = -sd
					done = true
					break
			shift += 3.0
		at += shift - 3.0 + SPACING if done else SPACING


func _post(at: Vector2, toward_road: Vector2, village: bool, stretch: StringName) -> void:
	var prop := Prop.new()
	prop.model = VILLAGE_MODEL if village else FAR_MODEL
	prop.snap_to_ground = true
	prop.name = "Lamp_%s_%d" % [stretch, get_child_count()]
	prop.position = Vector3(at.x, 0, at.y)
	prop.rotation.y = atan2(-toward_road.y, toward_road.x)  # the arm (+X) reaches over the road
	prop.set_meta("stretch", stretch)
	add_child(prop)
	var lamp := {"glow": [], "lights": [], "wave": 0.0, "on": false, "since": 0.0, "level": 0.0,
			"delay": 0.0, "prop": prop}
	for g in prop.find_children("*", "GeometryInstance3D", true, false):
		if g.is_in_group("night_glow"):
			g.remove_from_group("night_glow")
			lamp["glow"].append(g)
	for l in prop.find_children("*", "OmniLight3D", true, false):
		var light := l as OmniLight3D
		light.remove_from_group("night_light")
		light.add_to_group("path_light")  # (GraphicsSettings still sets its shadows)
		light.distance_fade_enabled = true
		light.distance_fade_begin = LIGHT_FADE_BEGIN
		light.distance_fade_length = LIGHT_FADE_LENGTH
		lamp["lights"].append(light)
	_lamps.append(lamp)


## [Vector2 position, clearance] of everything a post keeps away from.
func _obstacles() -> Array:
	var out: Array = []
	for b in get_tree().get_nodes_in_group("building"):
		out.append([_xz((b as Node3D).global_position), BUILDING_CLEARANCE])
	for p in get_tree().get_nodes_in_group("prop"):
		if not is_ancestor_of(p):
			out.append([_xz((p as Node3D).global_position), (p as Prop).footprint_radius() + 1.5])
	for n in get_tree().get_nodes_in_group("gatherable"):
		out.append([_xz((n as Node3D).global_position), NODE_CLEARANCE])
	return out


func _fits(p: Vector2, avoid: Array, placed: PackedVector2Array) -> bool:
	for q in placed:
		if q.distance_to(p) < MIN_GAP:
			return false
	for o in avoid:
		if (o[0] as Vector2).distance_to(p) < float(o[1]):
			return false
	if _terrain and _terrain.data:
		var h := _terrain.data.get_height(Vector3(p.x, 0, p.y))
		if is_nan(h):
			return false
		for d in [Vector2(1, 0), Vector2(0, 1), Vector2(-1, 0), Vector2(0, -1)]:
			var hd := _terrain.data.get_height(Vector3(p.x + d.x, 0, p.y + d.y))
			if is_nan(hd) or absf(hd - h) > MAX_SLOPE:
				return false
		for w in get_tree().get_nodes_in_group("water"):  # in it, or on a bank barely above it
			var body := w as WaterBody
			if body and body.contains(Vector3(p.x, h, p.y)) and body.surface_height > h - WATER_MARGIN:
				return false
	return true


static func _xz(v: Vector3) -> Vector2:
	return Vector2(v.x, v.z)


# --- the worlds' stretches ---------------------------------------------------------------------

## Hearthvale: the clearing's paths to the village and the lake, the village's road out to the
## ring, the ring cut at each turn-off, and the spurs to the lake shore, the field and the quarry.
func hearthvale() -> void:
	village_center = WorldMap.VILLAGE_CENTER
	stretches = []
	for r in WorldMap.roads():
		stretches.append(_stretch(r["id"], r["title"], r["pts"], r["half_width"], r.get("village", false)))


static func _stretch(id: StringName, title: String, pts: PackedVector2Array, half_width: float,
		village := false) -> Dictionary:
	return {"id": id, "title": title, "pts": pts, "half_width": half_width, "village": village}


static func _nearest(pts: PackedVector2Array, to: Vector2) -> int:
	var best := 0
	for i in pts.size():
		if pts[i].distance_squared_to(to) < pts[best].distance_squared_to(to):
			best = i
	return best
