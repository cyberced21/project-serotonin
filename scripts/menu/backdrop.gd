extends Node3D
## The main menu's backdrop: the classic clearing's pond with a treeline, filmed by a camera
## drifting slowly round it. Nothing here saves or plays: no nodes to gather, no player.
## The day runs on from late afternoon (DayNight is the autoload's, so a world resets it on load).

const CENTER := Vector3(20, 0, 16)
const RADIUS := 27.0
const HEIGHT := 4.5
const LOOK_HEIGHT := 1.6
## Radians per second round the pond: a full turn in about seven minutes.
const SPEED := 0.015
const START_ANGLE := 0.35
const START_TIME := 0.66

@onready var _camera := $Camera3D as Camera3D
@onready var _terrain := $Terrain3D as Terrain3D
var _angle := START_ANGLE


## Before the scenery scatters (children are ready first): keep its trees off the camera's path.
func _enter_tree() -> void:
	var scenery := $Scenery as SceneryScatter
	var spots := scenery.clear_spots
	for i in 48:
		var a := TAU * i / 48.0
		spots.append(Vector3(CENTER.x + sin(a) * RADIUS, CENTER.z + cos(a) * RADIUS, 7.0))
	scenery.clear_spots = spots


func _ready() -> void:
	DayNight.time = START_TIME
	_camera.make_current()
	_place_camera()
	_camera.reset_physics_interpolation()


func _process(delta: float) -> void:
	_angle += SPEED * delta
	_place_camera()


func _place_camera() -> void:
	var at := CENTER + Vector3(sin(_angle), 0.0, cos(_angle)) * RADIUS
	var ground := _terrain.data.get_height(at) if _terrain.data else 0.0
	if is_nan(ground):
		ground = 0.0
	at.y = maxf(ground, 0.0) + HEIGHT
	_camera.global_position = at
	_camera.look_at(CENTER + Vector3.UP * LOOK_HEIGHT)
