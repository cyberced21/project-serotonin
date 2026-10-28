extends AudioStreamPlayer3D
## Positional footsteps from the player's feet. Steps are spaced by distance travelled (longer
## strides when sprinting, short quiet ones crouched), and the sound matches the surface:
## on the terrain it's picked the same way the low-poly shader picks colours (slope + height),
## anything else (rocks, greybox blocks) sounds like stone. In water (see WaterBody) every step
## sloshes and leaves a ripple ring, and landing in it splashes.
## The player calls tick() every physics frame and land() when touching down.

const SOUNDS := {
	&"grass": preload("res://audio/footsteps/grass.tres"),
	&"dirt": preload("res://audio/footsteps/dirt.tres"),
	&"rock": preload("res://audio/footsteps/rock.tres"),
	&"sand": preload("res://audio/footsteps/sand.tres"),
	&"snow": preload("res://audio/footsteps/snow.tres"),
	&"water": preload("res://audio/footsteps/water.tres"),
}
const SPLASH := preload("res://audio/movement/splash.tres")
## Water shallower than this (m) still sounds like the ground under it.
const WET_DEPTH := 0.06
## Fallbacks matching the defaults in shaders/terrain.gdshader, used when the terrain
## material doesn't override them.
## What the painted surfaces (WorldMap.TEX_*) sound like on walkable ground: dirt paths, the
## gravel road and quarry stone crunch; forest floor, meadow and crops are grassy.
const TEXTURE_SOUNDS := {
	WorldMap.TEX_PATH: &"dirt", WorldMap.TEX_ROAD: &"rock", WorldMap.TEX_QUARRY: &"rock",
	WorldMap.TEX_FOREST: &"grass", WorldMap.TEX_FIELD: &"grass", WorldMap.TEX_CROP: &"grass",
}
const SHADER_DEFAULTS := {
	&"dirt_slope": 0.86, &"rock_slope": 0.68, &"sand_height": -2.0, &"snow_height": 40.0,
}

@export var walk_stride := 1.9
@export var sprint_stride := 2.4
@export var crouch_stride := 1.1
@export var walk_db := -9.0
@export var sprint_db := -5.0
@export var crouch_db := -16.0
@export var land_db := -1.0
## Falls slower than this (m/s) make no landing sound.
@export var land_min_speed := 3.0

var _dist := 0.0


## speed: horizontal speed (m/s). Call every physics frame.
func tick(delta: float, speed: float, on_floor: bool, crouched: bool, walk_speed: float, sprint_speed: float) -> void:
	if not on_floor or speed < 0.5:
		_dist = 0.0  # the first step after starting to move comes quickly
		return
	var t := clampf(inverse_lerp(walk_speed, sprint_speed, speed), 0.0, 1.0)
	var stride := crouch_stride if crouched else lerpf(walk_stride, sprint_stride, t)
	_dist += speed * delta
	if _dist >= stride * 0.5:  # half stride: first footfall lands half a stride in
		_dist -= stride
		# how loud the step is to fish: crouch-walking barely registers, sprinting carries
		_play(crouch_db if crouched else lerpf(walk_db, sprint_db, t), 1.0, 0.15 if crouched else lerpf(0.6, 1.0, t))


## fall_speed: downward speed just before touching down (positive, m/s).
func land(fall_speed: float) -> void:
	if fall_speed < land_min_speed:
		return
	var hard := clampf(inverse_lerp(land_min_speed, 12.0, fall_speed), 0.0, 1.0)
	if surface() == &"water":
		stream = SPLASH
		volume_db = land_db + hard * 3.0
		pitch_scale = lerpf(1.05, 0.85, hard)
		play()
		_ripple(2.4)
		FishPond.disturb(get_tree(), global_position, 1.5)
	else:
		_play(land_db + hard * 3.0, lerpf(0.95, 0.8, hard))
	_dist = 0.0


func _play(db: float, pitch: float, loudness := 0.6) -> void:
	var s := surface()
	stream = SOUNDS[s]
	volume_db = db
	pitch_scale = pitch
	play()
	if s == &"water":
		_ripple(1.4)
		FishPond.disturb(get_tree(), global_position, loudness)


func _ripple(size: float) -> void:
	var water := WaterBody.surface_at(get_tree(), global_position)
	if water:
		var p := global_position
		WaterRipple.spawn(water, Vector3(p.x, water.surface_height, p.z), size)


## Which surface the feet are on: water, grass, dirt, rock, sand or snow.
func surface() -> StringName:
	var feet := global_position
	if Footbridge.on_bridge(get_tree(), feet):
		return &"rock"  # (planks: until they have footsteps of their own)
	if WaterBody.depth_at(get_tree(), feet) > WET_DEPTH:
		return &"water"
	var terrain := get_tree().get_first_node_in_group("terrain") as Terrain3D
	if terrain and terrain.data:
		var h: float = terrain.data.get_height(feet)
		if not is_nan(h) and absf(h - feet.y) < 0.3:
			var slope: float = terrain.data.get_normal(feet).y
			if slope < _param(terrain, &"rock_slope"):
				return &"rock"
			if h > _param(terrain, &"snow_height"):
				return &"snow"
			var id: int = terrain.data.get_control_base_id(feet)
			if id == WorldMap.TEX_QUARRY:
				return &"rock"
			if slope < _param(terrain, &"dirt_slope") and id != WorldMap.TEX_ROAD:
				return &"dirt"
			if TEXTURE_SOUNDS.has(id):
				return TEXTURE_SOUNDS[id]
			if h < _param(terrain, &"sand_height"):
				return &"sand"
			return &"grass"
	return &"rock"


func _param(terrain: Terrain3D, name: StringName) -> float:
	var v = terrain.material.get_shader_param(name) if terrain.material else null
	return float(v) if v != null else SHADER_DEFAULTS[name]
