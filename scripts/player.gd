extends CharacterBody3D
## First-person player: WASD to move, mouse to look, Shift to sprint, Space to jump,
## Ctrl / C to crouch (slide while sprinting), jump at a ledge while moving forward to mantle,
## Shift in the air to dash, jump alongside a wall at speed to wall-run (jump again to kick off),
## hold E / left-click to gather whatever the crosshair is on. E on a villager talks to them
## instead (left-click never swings at villagers).
## Esc frees the mouse; clicking the game captures it again.
## Mouse-look runs in _unhandled_input (raw events), so it stays smooth during hit-stop.
## Physics interpolation is on for the body; the eye (Head) is placed every rendered frame from the
## body's interpolated position plus the current look angles, so the view is smooth at any frame
## rate and mouse look never lags a tick. Head bob, landing dip and strafe lean are added there, and
## the held tool sways with mouse movement and bobs with your steps (see _process).
## Movement keeps momentum (Ghostrunner-ish): speed above running pace bleeds off slowly on the
## ground and not at all in the instant after landing, so jumping right as you land (bunny hop)
## keeps it, and adds a little, up to max_speed. Jumping out of a slide keeps the slide's speed
## (slide cancel); landing with crouch held at speed drops straight into a slide. In the air,
## steering turns your velocity without losing speed. See _move.
## The node is hit on the *impact frame* of the swing, not when the button is pressed —
## lining sound + hit-stop up with the animation is what makes it feel solid.

@export_group("Look")
@export var mouse_sensitivity := 0.0025
@export_range(1.0, 89.0) var max_pitch_deg := 88.0

@export_group("Ground")
@export var walk_speed := 4.5
@export var sprint_speed := 7.0
@export var ground_accel := 45.0
@export var ground_friction := 55.0

@export_group("Air")
@export var air_accel := 12.0
@export var jump_velocity := 5.2
## Gravity is multiplied by this while falling, for a snappier arc.
@export var fall_gravity_mult := 1.6
## Releasing jump early multiplies upward speed by this (short hop vs. full jump).
@export_range(0.0, 1.0) var jump_cut := 0.5
## Jump still works this long after walking off a ledge.
@export var coyote_time := 0.1
## A jump pressed this long before landing still fires on landing.
@export var jump_buffer := 0.12

@export_group("Momentum")
## Nothing makes you faster than this (m/s).
@export var max_speed := 16.0
## After landing, this long with no ground friction at all: jump within it to keep your speed.
@export var bhop_window := 0.12
## Speed added by each clean hop (jumping within the window while faster than walking).
@export var bhop_gain := 0.6
## Speed above running pace lost per second on the ground (with input; more without).
@export var overspeed_decay := 5.0
## How fast you can turn while moving faster than running pace, on the ground (rad/s).
@export var ground_steer := 4.0
## How fast you can turn your velocity in the air without losing speed (rad/s).
@export var air_control := 3.2
## Braking in the air when pulling back against your motion (m/s per second).
@export var air_brake := 8.0
## Extra speed when you jump out of a slide.
@export var slide_jump_boost := 1.2

@export_group("Air dash")
@export var dash_enabled := true
## You dash at least this fast, in the direction you're looking.
@export var dash_speed := 12.0
## Upward speed at the start of the dash, and how long gravity is mostly off after it.
@export var dash_lift := 1.5
@export var dash_float := 0.18

@export_group("Wall run")
@export var wallrun_enabled := true
## You need to be going at least this fast along the wall to start.
@export var wallrun_min_speed := 5.5
## Speed kept up while running along a wall.
@export var wallrun_speed := 8.0
@export var wallrun_max_time := 1.2
## Upward speed when you hit the wall, so the run starts with a little climb.
@export var wallrun_lift := 3.0
## How fast you slide down the wall by the end of the run (m/s).
@export var wallrun_sink := 2.5
## Push away from the wall when you jump off it.
@export var wall_jump_push := 5.5
@export var wallrun_roll_deg := 10.0

@export_group("Speed feel")
## Extra FOV at max speed (degrees).
@export var speed_fov_kick := 14.0
@export var wind_sfx: AudioStream = preload("res://audio/movement/wind_loop.wav")

@export_group("View feel")
## Gentle up-and-down of the eye with your steps (m at full sprint; 0 = off).
@export var head_bob := 0.035
## How much the view dips when you land (per m/s of fall speed).
@export var landing_dip := 0.012
## Roll toward the side you strafe (degrees).
@export var strafe_lean_deg := 1.2
## How far the held tool lags behind mouse movement.
@export var tool_sway := 1.0

@export_group("Water")
## Speed multiplier when wading at full depth (scales in with depth).
@export var wade_slow := 0.5
## Depth (m) at which wading is at its slowest.
@export var wade_full_depth := 0.9
## Slides stop in water deeper than this.
@export var slide_max_water := 0.3

@export_group("Crouch / slide")
@export var crouch_speed := 2.5
## Seconds to go fully down / up.
@export var crouch_transition := 0.12
## Extra speed when a slide starts (only once per slide_boost_cooldown, so it can't be spammed).
@export var slide_boost := 2.5
@export var slide_boost_cooldown := 0.8
## Speed lost per second on flat ground.
@export var slide_friction := 4.0
## How strongly slopes speed you up (downhill) or slow you down (uphill).
@export var slide_gravity := 1.0
@export var slide_steer := 4.0
## The slide ends below this speed.
@export var slide_min_speed := 3.0
@export var slide_fov_kick := 10.0
@export var slide_roll_deg := 3.0

@export_group("Mantle")
## How far ahead a wall is detected.
@export var mantle_reach := 0.8
## Ledges lower than this (above the feet) are just stepped/jumped onto.
@export var mantle_min_height := 0.45
@export var mantle_max_height := 2.2
## Pull-up time per metre of height.
@export var mantle_time_per_m := 0.18

@export_group("Gathering")
## How far the crosshair reaches (m).
@export var reach := 2.4
## How far away you can talk to a villager (m).
@export var interact_reach := 3.2
@export var swing_sfx: AudioStream
## Tool models (.glb, handle from the origin up +Y). Replace the greybox tools when set.
@export var pickaxe_model: PackedScene
@export var axe_model: PackedScene
@export var spear_model: PackedScene

@export_group("Swing timing")
@export var windup_time := 0.13
@export var strike_time := 0.05
@export var recover_time := 0.16
@export var swing_cooldown := 0.12
@export var move_slow_while_swinging := 0.3

@export_group("Bite")
## How far the tool sinks into the node on impact (m, viewmodel space).
@export var bite_depth := 0.07
## How long the tool stays stuck in the node after the hit-stop.
@export var bite_hold := 0.06
## How long the yank back out takes. The chunk tears out at the end of it.
@export var yank_time := 0.09
## How far the tool's edge is buried in the node while it's stuck (m, world space).
@export var stick_depth := 0.1

## Tool pivot rotation around X (radians): positive tilts the head back toward the camera.
const REST_ANGLE := -0.3
const WINDUP_ANGLE := 0.7
const STRIKE_ANGLE := -0.7
## At impact the arm reaches up (viewmodel space) so the tool's head lands right on the crosshair,
## where the world copy of it sticks into the node (measured: within ~5% of screen of the centre).
const STRIKE_REACH := Vector3(0, 0.33, 0)
## A little lift during the wind-up.
const WINDUP_LIFT := Vector3(0, 0.06, 0.04)
## How long the stuck tool takes to drive in, and to come back out (real seconds).
const STICK_TIME := 0.035
## The yank out of the node: back toward the eye, head tipping up. Kept small so it reads as a jerk
## over a few frames rather than a jump.
const YANK_OFFSET := Vector3(0, 0.02, 0.07)
const YANK_TIP := 0.22
const WORLD_MASK := 1
## Villagers (see Villager.NPC_LAYER): the crosshair ray stops on them, mantling ignores them.
const NPC_MASK := 1 << 6
const STAND_HEIGHT := 1.8
const CROUCH_HEIGHT := 1.0
const STAND_EYE := 1.6
const CROUCH_EYE := 0.9

enum State { NORMAL, SLIDE, MANTLE, WALLRUN }

## Slide scrape pitch per surface (see footsteps.gd): sand is dull, rock is sharp.
const SLIDE_PITCH := {&"grass": 1.1, &"dirt": 0.9, &"rock": 1.3, &"sand": 0.75, &"snow": 1.0}
const DEFLECT_COLOR := Color("ff8a7a")
const TOOL_MATERIAL := preload("res://materials/node_palette.tres")
const SPEED_LINES := preload("res://shaders/speed_lines.gdshader")
## Where each tool's cutting edge is, in its model's space (tools/blender/make_models.py): the
## point that gets buried in the node during the bite.
const TOOL_HEADS := {&"axe": Vector3(0, 0.38, -0.185), &"pickaxe": Vector3(0, 0.385, -0.26)}

@onready var head: Node3D = $Head
@onready var body_collision: CollisionShape3D = $CollisionShape3D
@onready var body_shape: CapsuleShape3D = body_collision.shape
@onready var camera: Camera3D = $Head/Camera3D
@onready var grip: Node3D = $Viewmodel/SubViewport/Camera3D/Grip
@onready var tool_pivot: Node3D = %ToolPivot
@onready var tools: Dictionary[StringName, Node3D] = {&"axe": %Axe, &"pickaxe": %Pickaxe, &"spear": %Spear}
@onready var spearfishing: SpearFishing = $SpearFishing
@onready var dot: Control = $Reticle/Dot
@onready var hover_label: Label = $Reticle/Hover
@onready var audio: AudioStreamPlayer = $Audio
@onready var footsteps: Node = $Footsteps
@onready var slide_audio: AudioStreamPlayer3D = $SlideAudio
@onready var mantle_audio: AudioStreamPlayer3D = $MantleAudio

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _base_fov := 75.0
var _coyote := 0.0
var _jump_buffer := 0.0
var _state := State.NORMAL
var _crouch := 0.0  # 0 = standing, 1 = fully crouched
var _slide_boost_cooldown := 0.0
var _since_land := 1.0  # time on the ground since the last landing (bunny-hop window)
var _dashed := false  # dash used this airtime
var _dash_float_left := 0.0
var _fov_punch := 0.0
var _wall_normal := Vector3.ZERO
var _last_wall_normal := Vector3.ZERO  # can't run the same wall twice in one airtime
var _wall_side := 0.0  # +1 wall on the right, -1 on the left
var _wallrun_time := 0.0
var _wallrun_cooldown := 0.0
var _wind: AudioStreamPlayer
var _speed_lines: ShaderMaterial
var _stand_probe := CapsuleShape3D.new()

var _target: ResourceNode
var _talk_target: Villager
var _swinging := false
var _cooldown := 0.0
var _tool_rest := Vector3.ZERO
var _equipped: StringName = &""

# the eye (see _process)
var _pitch := 0.0
var _roll := 0.0  # slide roll
var _lean := 0.0  # strafe lean
var _eye := STAND_EYE
var _move_input := Vector2.ZERO
var _bob_phase := 0.0
var _bob_amp := 0.0
var _dip := 0.0  # landing dip spring (m, + = down)
var _dip_vel := 0.0
# the held tool
var _grip_rest := Transform3D.IDENTITY
var _look_delta := Vector2.ZERO  # mouse motion since the last frame
var _sway := Vector2.ZERO
var _equip_dip := 0.0


func _ready() -> void:
	add_to_group("player")
	_base_fov = camera.fov
	_tool_rest = tool_pivot.position
	_stand_probe.radius = body_shape.radius - 0.01
	_stand_probe.height = STAND_HEIGHT
	var scrape := slide_audio.stream as AudioStreamWAV
	if scrape:  # the scrape is a seamless loop; make it loop without needing import settings
		scrape.loop_mode = AudioStreamWAV.LOOP_FORWARD
		scrape.loop_begin = 0
		scrape.loop_end = int(scrape.get_length() * scrape.mix_rate)  # in frames; works for any import compression
	tool_pivot.rotation.x = REST_ANGLE
	_grip_rest = grip.transform
	# the eye is placed by hand each frame (see _process); the viewmodel is animated per frame too
	head.top_level = true
	head.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	$Viewmodel.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_build_speed_feel()
	_use_tool_model(tools[&"pickaxe"], pickaxe_model)
	_use_tool_model(tools[&"axe"], axe_model)
	_use_tool_model(tools[&"spear"], spear_model)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	SaveGame.register(&"player", self)


func to_dict() -> Dictionary:
	return {
		"x": global_position.x, "y": global_position.y, "z": global_position.z,
		"yaw": rotation.y, "pitch": _pitch,
	}


func from_dict(d: Dictionary) -> void:
	if not d.has("z"):
		return  # save from the 2D version — spawn at the default position instead
	global_position = Vector3(float(d["x"]), float(d["y"]), float(d["z"]))
	rotation.y = float(d.get("yaw", 0.0))
	_pitch = float(d.get("pitch", 0.0))
	reset_physics_interpolation()  # a teleport, not a move


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var motion := event as InputEventMouseMotion
		rotate_y(-motion.relative.x * mouse_sensitivity)
		var limit := deg_to_rad(max_pitch_deg)
		_pitch = clampf(_pitch - motion.relative.y * mouse_sensitivity, -limit, limit)
		_look_delta += motion.relative
	elif event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		get_viewport().set_input_as_handled()


## The eye and the held tool, every rendered frame.
func _process(delta: float) -> void:
	var speed := Vector2(velocity.x, velocity.z).length()
	var grounded := (is_on_floor() and _state == State.NORMAL) or _state == State.WALLRUN
	# head bob: one soft dip per footstep, scaled by speed, gone when standing still or airborne
	var bob_target := 0.0
	if grounded and speed > 0.5:
		bob_target = head_bob * clampf(speed / sprint_speed, 0.0, 1.0) * (0.5 if _crouch > 0.5 else 1.0)
	_bob_amp = lerpf(_bob_amp, bob_target, 1.0 - exp(-8.0 * delta))
	var run := clampf(inverse_lerp(walk_speed, sprint_speed, speed), 0.0, 1.0)
	_bob_phase = fmod(_bob_phase + speed / lerpf(footsteps.walk_stride, footsteps.sprint_stride, run) * PI * delta, TAU)
	var bob := (0.5 - absf(sin(_bob_phase))) * _bob_amp
	# landing dip: a critically damped spring back up
	var stiffness := 90.0
	_dip_vel += (-stiffness * _dip - 2.0 * sqrt(stiffness) * _dip_vel) * delta
	_dip += _dip_vel * delta
	# lean into strafes
	var lean_target := -_move_input.x * deg_to_rad(strafe_lean_deg) if grounded else 0.0
	if _state == State.WALLRUN:  # tilt away from the wall
		lean_target = _wall_side * deg_to_rad(wallrun_roll_deg)
	_lean = lerp_angle(_lean, lean_target, 1.0 - exp(-6.0 * delta))

	var feet := get_global_transform_interpolated().origin
	head.global_transform = Transform3D(
		Basis.from_euler(Vector3(_pitch - _dip * 0.6, rotation.y, _roll + _lean)),
		feet + Vector3.UP * (_eye + bob - _dip))
	_update_tool_feel(delta, bob, run)
	_update_speed_feel(delta, speed)


## Rushing wind and faint speed lines, both growing from running pace up to max speed.
func _update_speed_feel(delta: float, speed: float) -> void:
	var t := smoothstep(sprint_speed + 0.5, max_speed, speed)
	if _wind:
		var db := lerpf(-38.0, -6.0, t)
		_wind.volume_db = move_toward(_wind.volume_db, db, 60.0 * delta)
		_wind.pitch_scale = lerpf(0.85, 1.25, t)
		var audible := _wind.volume_db > -37.0
		if audible and not _wind.playing:
			_wind.play(randf() * 2.0)
		elif not audible and _wind.playing:
			_wind.stop()
	if _speed_lines:
		var current: float = _speed_lines.get_shader_parameter("intensity")
		_speed_lines.set_shader_parameter("intensity", lerpf(current, t, 1.0 - exp(-6.0 * delta)))


## The held tool lags a little behind mouse movement, bobs with your steps, dips when you land,
## and drops out of view and back up when you switch tools.
func _update_tool_feel(delta: float, bob: float, run: float) -> void:
	var look_speed := _look_delta / maxf(delta, 0.001)
	_look_delta = Vector2.ZERO
	var target := (-look_speed * 0.00006 * tool_sway).limit_length(0.12)
	_sway = _sway.lerp(target, 1.0 - exp(-12.0 * delta))
	var stride := cos(_bob_phase) * _bob_amp * 0.5
	var offset := Vector3(_sway.x * 0.35 + stride, -_sway.y * 0.35 + bob * 0.6 - _dip * 0.5 - _equip_dip, 0.0)
	var tilt := Basis.from_euler(Vector3(_sway.y, _sway.x, _sway.x * 0.5 + run * 0.03))
	grip.transform = Transform3D(tilt * _grip_rest.basis, _grip_rest.origin + offset)


func _build_speed_feel() -> void:
	_wind = AudioStreamPlayer.new()
	_wind.name = "Wind"
	var loop := wind_sfx as AudioStreamWAV
	if loop:  # a seamless loop; loop it without needing import settings
		loop.loop_mode = AudioStreamWAV.LOOP_FORWARD
		loop.loop_begin = 0
		loop.loop_end = int(loop.get_length() * loop.mix_rate)
	_wind.stream = wind_sfx
	_wind.volume_db = -40.0
	add_child(_wind)
	var layer := CanvasLayer.new()
	layer.name = "SpeedLines"
	layer.layer = 1  # over the world and the held tool, under the crosshair and HUD
	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_speed_lines = ShaderMaterial.new()
	_speed_lines.shader = SPEED_LINES
	_speed_lines.set_shader_parameter("intensity", 0.0)
	rect.material = _speed_lines
	layer.add_child(rect)
	add_child(layer)


## A soft knock to the view on touching down, harder the faster you fell.
func _land_dip(fall_speed: float) -> void:
	_dip_vel += clampf(fall_speed, 0.0, 16.0) * landing_dip * 12.0


func _physics_process(delta: float) -> void:
	if _state != State.MANTLE:
		_move(delta)
	_update_crouch(delta)

	_cooldown -= delta
	_update_target()
	if _talk_target:
		if Input.is_action_just_pressed("interact") and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED \
				and not _swinging and not _panel_just_closed():
			_talk_target.interact()
	elif Input.is_action_pressed("gather") and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED \
			and is_on_floor() and _state == State.NORMAL and not _swinging and _cooldown <= 0.0:
		if _target:
			_swing(_target.tool_type)
		elif spearfishing.can_thrust():
			spearfishing.thrust()


func _move(delta: float) -> void:
	var input := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	_move_input = input
	var wish_dir := transform.basis * Vector3(input.x, 0.0, input.y)
	var wish := Vector2(wish_dir.x, wish_dir.z)
	var water_depth := WaterBody.depth_at(get_tree(), global_position)
	var wading := lerpf(1.0, wade_slow, clampf(water_depth / wade_full_depth, 0.0, 1.0))
	if _state == State.SLIDE and water_depth > slide_max_water:
		_state = State.NORMAL  # the water stops you
	_wallrun_cooldown -= delta

	# gravity + coyote time
	var on_floor := is_on_floor()
	if on_floor:
		_coyote = coyote_time
		_since_land += delta
		_dashed = false
		_last_wall_normal = Vector3.ZERO
	else:
		_coyote -= delta
		if _state != State.WALLRUN:  # the wall run handles its own vertical speed
			var g := _gravity * (fall_gravity_mult if velocity.y < 0.0 else 1.0)
			if _dash_float_left > 0.0:
				_dash_float_left -= delta
				g *= 0.15
			velocity.y -= g * delta

	# mantle: jump at a ledge while pushing forward (on the ground or in the air)
	_jump_buffer -= delta
	if Input.is_action_just_pressed("jump"):
		_jump_buffer = jump_buffer
	var wants_mantle := input.y < -0.3 and not _swinging and _state != State.WALLRUN \
		and (_jump_buffer > 0.0 or (not on_floor and Input.is_action_pressed("jump")))
	if wants_mantle and _try_mantle():
		return

	var horizontal := Vector2(velocity.x, velocity.z)

	# air dash: Shift in the air, once per airtime, toward where you're looking
	if dash_enabled and not on_floor and _state == State.NORMAL and not _dashed \
			and Input.is_action_just_pressed("sprint") and not _swinging:
		horizontal = _dash(horizontal)

	# jumps: off a wall, or off the ground (keeping speed: bunny hop, slide cancel)
	var jumped := false
	if _state == State.WALLRUN and _jump_buffer > 0.0:
		horizontal = _wall_jump(horizontal)
		jumped = true
	elif _jump_buffer > 0.0 and _coyote > 0.0 and not _swinging and _can_stand():
		var spd := horizontal.length()
		if _state == State.SLIDE:
			spd += slide_jump_boost  # slide cancel: keep the slide's speed, plus a kick
		elif on_floor and _since_land <= bhop_window and spd > walk_speed:
			spd += bhop_gain  # clean hop
		if horizontal.length() > 0.01:
			horizontal = horizontal.normalized() * minf(spd, max_speed)
		velocity.y = jump_velocity
		_jump_buffer = 0.0
		_coyote = 0.0
		_state = State.NORMAL
		jumped = true
	if Input.is_action_just_released("jump") and velocity.y > 0.0 and _state != State.WALLRUN:
		velocity.y *= jump_cut

	# start a slide: crouch while running fast on the ground
	if _state == State.NORMAL and Input.is_action_just_pressed("crouch") and on_floor and not jumped \
			and not _swinging and horizontal.length() > walk_speed + 0.5:
		horizontal = _start_slide(horizontal)
	_slide_boost_cooldown -= delta

	# the walk / sprint / crouch-walk speed you're steering toward (yaw only; the head pitches)
	var crouched := Input.is_action_pressed("crouch") or not _can_stand()
	var sprinting := Input.is_action_pressed("sprint") and input.y < 0.0 and not _swinging and not crouched
	var speed := crouch_speed if crouched else (sprint_speed if sprinting else walk_speed)
	speed *= move_slow_while_swinging if _swinging else 1.0
	speed *= wading

	match _state:
		State.SLIDE:
			horizontal = _slide(delta, horizontal, wish)
		State.WALLRUN:
			horizontal = _wallrun(delta, horizontal)
		_:
			if on_floor and not jumped:
				horizontal = _ground_move(delta, horizontal, wish, speed)
			else:
				horizontal = _air_move(delta, horizontal, wish, speed)
	horizontal = horizontal.limit_length(max_speed)
	velocity.x = horizontal.x
	velocity.z = horizontal.y
	var was_on_floor := on_floor
	var fall_speed := -velocity.y
	move_and_slide()

	if is_on_floor() and not was_on_floor:
		_on_land(fall_speed)
	elif not is_on_floor() and _state == State.NORMAL and not jumped:
		_try_wallrun(input)
	var stepping := _state == State.NORMAL or _state == State.WALLRUN  # no steps mid-slide
	footsteps.tick(delta, horizontal.length() if stepping else 0.0, is_on_floor() or _state == State.WALLRUN,
		_crouch > 0.5, walk_speed, sprint_speed)
	_update_slide_audio(delta, horizontal.length())

	# a wider view the faster you go
	var spd_t := clampf((horizontal.length() - walk_speed) / (max_speed - walk_speed), 0.0, 1.0)
	var kick := spd_t * speed_fov_kick + (slide_fov_kick * 0.5 if _state == State.SLIDE else 0.0) + _fov_punch
	_fov_punch = move_toward(_fov_punch, 0.0, 40.0 * delta)
	camera.fov = lerpf(camera.fov, _base_fov + kick, 1.0 - exp(-10.0 * delta))


func _on_land(fall_speed: float) -> void:
	footsteps.land(fall_speed)
	if fall_speed > 2.0:
		_land_dip(fall_speed)
	_since_land = 0.0
	if _state == State.WALLRUN:
		_state = State.NORMAL
	# land with crouch held at speed: straight into a slide (slide-hop chains)
	var horizontal := Vector2(velocity.x, velocity.z)
	if _state == State.NORMAL and Input.is_action_pressed("crouch") and horizontal.length() > walk_speed + 0.5:
		horizontal = _start_slide(horizontal)
		velocity.x = horizontal.x
		velocity.z = horizontal.y


# --- ground / air ---------------------------------------------------------------------------

## On the ground. Faster than you could run (from a slide, a hop chain, a slope): keep the
## momentum, steer it toward your input, bleed it off slowly, and not at all just after landing,
## so a quick jump carries all of it. Otherwise plain acceleration / friction.
func _ground_move(delta: float, horizontal: Vector2, wish: Vector2, speed: float) -> Vector2:
	var spd := horizontal.length()
	if spd > speed + 0.2:
		if _since_land > bhop_window:
			var decay := overspeed_decay if wish != Vector2.ZERO else overspeed_decay * 2.5
			spd = move_toward(spd, speed, decay * delta)
		var dir := horizontal / horizontal.length()
		if wish != Vector2.ZERO:
			dir = _turn_toward(dir, wish.normalized(), ground_steer * delta)
		return dir * spd
	var target := wish * speed
	if _since_land <= bhop_window and target == Vector2.ZERO:
		return horizontal  # no friction in the hop window
	var rate := ground_friction if target == Vector2.ZERO else ground_accel
	return horizontal.move_toward(target, rate * delta)


## In the air. Slower than running pace: build up toward it. Faster: steer without losing speed
## (pulling back brakes). No air drag.
func _air_move(delta: float, horizontal: Vector2, wish: Vector2, speed: float) -> Vector2:
	if wish == Vector2.ZERO:
		return horizontal
	var w := wish.normalized()
	var spd := horizontal.length()
	if spd < speed:
		return horizontal.move_toward(w * speed, air_accel * delta)
	if horizontal.dot(w) < -0.5 * spd:
		return horizontal.move_toward(Vector2.ZERO, air_brake * delta)
	return _turn_toward(horizontal / spd, w, air_control * delta) * spd


## Turns unit vector `dir` toward unit vector `to` by at most `max_angle` radians.
static func _turn_toward(dir: Vector2, to: Vector2, max_angle: float) -> Vector2:
	var angle := dir.angle_to(to)
	return dir.rotated(clampf(angle, -max_angle, max_angle))


# --- slide ----------------------------------------------------------------------------------

func _start_slide(horizontal: Vector2) -> Vector2:
	_state = State.SLIDE
	if _slide_boost_cooldown <= 0.0:
		horizontal += horizontal.normalized() * slide_boost
		_slide_boost_cooldown = slide_boost_cooldown
	return horizontal.limit_length(max_speed)


## Low friction, speeds up going downhill, a little steering. Ends when it's too slow, when
## crouch is released, or on a jump (which keeps the momentum: the slide cancel).
func _slide(delta: float, horizontal: Vector2, wish: Vector2) -> Vector2:
	if is_on_floor():
		var n := get_floor_normal()
		# the downhill part of gravity: (n.x, n.z) points down the slope, longer on steeper ground
		horizontal += Vector2(n.x, n.z) * _gravity * slide_gravity * delta
		horizontal = horizontal.move_toward(Vector2.ZERO, slide_friction * delta)
	# steering only bends the slide sideways; holding forward can't keep it going forever
	if horizontal.length() > 0.01:
		var along := horizontal.normalized()
		horizontal += (wish - along * wish.dot(along)) * slide_steer * delta
	if horizontal.length() < slide_min_speed or not Input.is_action_pressed("crouch"):
		_state = State.NORMAL
	return horizontal


# --- air dash -------------------------------------------------------------------------------

## A burst toward where you're looking (flattened), at least dash_speed; gravity mostly off for a
## moment so it reads as a dash, not a fall.
func _dash(horizontal: Vector2) -> Vector2:
	var look := -camera.global_basis.z
	var dir := Vector2(look.x, look.z)
	if dir.length() < 0.1:
		dir = Vector2(-global_basis.z.x, -global_basis.z.z)
	dir = dir.normalized()
	var spd := maxf(horizontal.length(), dash_speed)
	velocity.y = maxf(velocity.y, dash_lift)
	_dash_float_left = dash_float
	_dashed = true
	_fov_punch = 8.0
	Juice.shake(0.8)
	if swing_sfx:
		audio.stream = swing_sfx
		audio.pitch_scale = 0.6
		audio.play()
	return dir * minf(spd, max_speed)


# --- wall run -------------------------------------------------------------------------------

## A wall beside you (left or right), as {normal, side}, or {} if none. Rays from chest height.
func _wall_beside() -> Dictionary:
	var space := get_world_3d().direct_space_state
	var from := global_position + Vector3.UP * 1.0
	for side in [1.0, -1.0]:
		var dir: Vector3 = global_basis.x * side
		var q := PhysicsRayQueryParameters3D.create(from, from + dir * 0.8, WORLD_MASK, [get_rid()])
		var hit := space.intersect_ray(q)
		if not hit.is_empty() and absf((hit["normal"] as Vector3).y) < 0.3:
			return {"normal": hit["normal"], "side": side}
	return {}


func _try_wallrun(input: Vector2) -> void:
	if not wallrun_enabled or _wallrun_cooldown > 0.0 or input.y > -0.3 or _swinging:
		return
	var wall := _wall_beside()
	if wall.is_empty():
		return
	var n: Vector3 = wall["normal"]
	if _last_wall_normal != Vector3.ZERO and n.dot(_last_wall_normal) > 0.9:
		return  # the same wall again, before touching the ground
	var hv := Vector3(velocity.x, 0.0, velocity.z)
	var along := hv - n * hv.dot(n)
	if along.length() < wallrun_min_speed:
		return
	_state = State.WALLRUN
	_wall_normal = n
	_wall_side = wall["side"]
	_last_wall_normal = n
	_wallrun_time = 0.0
	_dashed = false
	velocity.y = maxf(velocity.y, wallrun_lift)  # a lift onto the wall


## Running along the wall: keep (at least) running speed along it, hug it, float at first and slide
## down toward the end. Ends on timeout, losing the wall, landing, crouching or slowing down.
func _wallrun(delta: float, horizontal: Vector2) -> Vector2:
	_wallrun_time += delta
	var space := get_world_3d().direct_space_state
	var from := global_position + Vector3.UP * 1.0
	var q := PhysicsRayQueryParameters3D.create(from, from - _wall_normal * 1.0, WORLD_MASK, [get_rid()])
	var hit := space.intersect_ray(q)
	if not hit.is_empty() and absf((hit["normal"] as Vector3).y) < 0.3:
		_wall_normal = hit["normal"]
	var hv := Vector3(horizontal.x, 0.0, horizontal.y)
	var along := hv - _wall_normal * hv.dot(_wall_normal)
	if hit.is_empty() or _wallrun_time > wallrun_max_time or is_on_floor() \
			or Input.is_action_pressed("crouch") or along.length() < wallrun_min_speed * 0.6:
		_state = State.NORMAL
		_wallrun_cooldown = 0.2
		return horizontal
	along = along.normalized() * minf(maxf(along.length(), wallrun_speed), max_speed)
	along -= _wall_normal * 1.0  # press into it so the contact holds
	# hold the line at first, then slide down more and more toward the end of the run
	var sink := smoothstep(0.35, 1.0, _wallrun_time / wallrun_max_time)
	velocity.y = move_toward(velocity.y, -wallrun_sink * sink, 9.0 * delta)
	return Vector2(along.x, along.z)


## Kick off the wall: away from it and up, keeping the speed along it.
func _wall_jump(horizontal: Vector2) -> Vector2:
	var hv := Vector3(horizontal.x, 0.0, horizontal.y)
	var along := hv - _wall_normal * hv.dot(_wall_normal)
	var out := along + _wall_normal * wall_jump_push
	velocity.y = jump_velocity
	_jump_buffer = 0.0
	_state = State.NORMAL
	_wallrun_cooldown = 0.25
	_dashed = false
	return Vector2(out.x, out.z).limit_length(max_speed)


## Scrape loop while sliding on the ground: louder and higher the faster you go, pitched by
## surface; fades out (rather than cutting) when the slide ends or you leave the ground.
func _update_slide_audio(delta: float, speed: float) -> void:
	if _state == State.SLIDE and is_on_floor():
		if not slide_audio.playing:
			slide_audio.volume_db = -20.0
			slide_audio.play(randf() * 1.0)  # random start so repeated slides don't sound identical
		var t := clampf(speed / (sprint_speed + slide_boost), 0.0, 1.0)
		slide_audio.pitch_scale = SLIDE_PITCH.get(footsteps.surface(), 1.0) * lerpf(0.85, 1.15, t)
		slide_audio.volume_db = move_toward(slide_audio.volume_db, lerpf(-14.0, -2.0, t), 120.0 * delta)
	elif slide_audio.playing:
		slide_audio.volume_db = move_toward(slide_audio.volume_db, -40.0, 120.0 * delta)
		if slide_audio.volume_db <= -39.0:
			slide_audio.stop()


## Smoothly lowers the eye and shrinks the capsule while sliding / crouching.
func _update_crouch(delta: float) -> void:
	var want := 1.0 if (_state == State.SLIDE or Input.is_action_pressed("crouch") or not _can_stand()) \
		and _state != State.MANTLE else 0.0
	_crouch = move_toward(_crouch, want, delta / crouch_transition)
	var height := lerpf(STAND_HEIGHT, CROUCH_HEIGHT, _crouch)
	body_shape.height = height
	body_collision.position.y = height / 2.0
	_eye = lerpf(STAND_EYE, CROUCH_EYE, _crouch)
	# slight camera roll while sliding
	var roll := slide_roll_deg if _state == State.SLIDE else 0.0
	_roll = lerp_angle(_roll, deg_to_rad(roll), 1.0 - exp(-8.0 * delta))


## True if there's nothing overhead stopping the player standing up.
func _can_stand() -> bool:
	return _fits(global_position)


## True if a standing capsule fits with its feet at `at`.
func _fits(at: Vector3) -> bool:
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _stand_probe
	query.transform = Transform3D(Basis.IDENTITY, at + Vector3.UP * (STAND_HEIGHT / 2.0 + 0.02))
	query.collision_mask = WORLD_MASK
	query.exclude = [get_rid()]
	return get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()


# --- mantle ---------------------------------------------------------------------------------

## Looks for a ledge in front: a steep face within reach, a walkable top no higher than
## mantle_max_height above the feet, and room to stand up there. Starts the climb if found.
func _try_mantle() -> bool:
	var space := get_world_3d().direct_space_state
	var fwd := -global_basis.z
	var feet := global_position
	# 1. a wall in front, probing knee → chest → head height
	var wall := {}
	for h in [0.4, 1.0, 1.6]:
		var from: Vector3 = feet + Vector3.UP * h
		var q := PhysicsRayQueryParameters3D.create(from, from + fwd * mantle_reach, WORLD_MASK, [get_rid()])
		wall = space.intersect_ray(q)
		if not wall.is_empty():
			break
	if wall.is_empty() or wall["normal"].y > 0.3:
		return false
	# 2. its top: cast down from above the max height, a little way past the face
	var probe: Vector3 = wall["position"] - wall["normal"] * 0.3
	var q2 := PhysicsRayQueryParameters3D.create(
		Vector3(probe.x, feet.y + mantle_max_height + 0.1, probe.z),
		Vector3(probe.x, feet.y + mantle_min_height, probe.z), WORLD_MASK, [get_rid()])
	var top := space.intersect_ray(q2)
	if top.is_empty() or top["normal"].y < 0.7:
		return false
	# 3. room to stand on it
	var land: Vector3 = top["position"] + fwd * 0.15
	if not _fits(land + Vector3.UP * 0.02):
		return false
	_mantle(land)
	return true


## Pull up (fast, then slower as you crest), then step forward onto the ledge.
func _mantle(land: Vector3) -> void:
	_state = State.MANTLE
	_jump_buffer = 0.0
	mantle_audio.play()  # hands slap onto the ledge, clothes rustle on the way up
	velocity = Vector3.ZERO
	var start := global_position
	var rise := land.y - start.y
	var up_time := clampf(rise * mantle_time_per_m, 0.12, 0.4)
	var crest := Vector3(start.x, land.y + 0.05, start.z)
	var t := create_tween().set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)  # body moves on physics ticks (interpolated)
	t.tween_property(self, "global_position", crest, up_time).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_property(self, "global_position", land + Vector3.UP * 0.05, 0.12).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	# hands busy: tool dips out of view and comes back; head nods with the effort
	var tool_t := create_tween()
	tool_t.tween_property(tool_pivot, "position", _tool_rest + Vector3(0, -0.25, 0.05), up_time * 0.5)
	tool_t.tween_property(tool_pivot, "position", _tool_rest, 0.2).set_delay(up_time * 0.5)
	var nod := create_tween()
	nod.tween_property(camera, "position:y", -0.06, up_time).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	nod.tween_property(camera, "position:y", 0.0, 0.15).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await t.finished
	velocity = -global_basis.z * walk_speed * 0.5  # carry on moving instead of stopping dead
	footsteps.land(footsteps.land_min_speed + 1.0)  # feet planting on the ledge
	_land_dip(3.0)
	_state = State.NORMAL


# --- gathering ------------------------------------------------------------------------------

## Swaps a tool's greybox meshes for a model. Viewmodel meshes must be on render layer 2 (only
## the viewmodel camera sees it) and cast no shadows into the world.
func _use_tool_model(slot: Node3D, model: PackedScene) -> void:
	if model == null:
		return
	for old in slot.get_children():
		old.queue_free()
	var inst := model.instantiate()
	slot.add_child(inst)
	for m in inst.find_children("*", "MeshInstance3D", true, false):
		m.layers = 2
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		m.material_override = TOOL_MATERIAL


## Ray from the centre of the screen. Only the world and villagers, so debris and drops don't
## block it.
func _aim(length := reach) -> Dictionary:
	var from := camera.global_position
	var to := from - camera.global_basis.z * length
	var query := PhysicsRayQueryParameters3D.create(from, to, WORLD_MASK | NPC_MASK, [get_rid()])
	return get_world_3d().direct_space_state.intersect_ray(query)


func _node_under_crosshair(hit: Dictionary) -> ResourceNode:
	var node := hit.get("collider") as ResourceNode
	return node if node and node.is_available() else null


func _update_target() -> void:
	# one ray out to the further reach: villagers can be talked to a bit further than you can swing
	var hit := _aim(maxf(reach, interact_reach))
	var talk := hit.get("collider") as Villager
	var node: ResourceNode = null
	if talk == null and not hit.is_empty() and camera.global_position.distance_to(hit["position"]) <= reach:
		node = _node_under_crosshair(hit)
	if talk == null and node == null:
		talk = _villager_behind_clutter()
	if talk != _talk_target:
		if is_instance_valid(_talk_target):
			_talk_target.set_highlighted(false)
		_talk_target = talk
		if _talk_target:
			_talk_target.set_highlighted(true)
	if node != _target:
		if is_instance_valid(_target):
			_target.set_highlighted(false)
		_target = node
		if _target:
			_target.set_highlighted(true)
	if _target or _talk_target:
		spearfishing.clear_target()
	elif not _swinging:  # mid-thrust, SpearFishing re-aims on its own impact frame
		spearfishing.update_target()

	# bring out the right tool for whatever you're looking at
	if not _swinging:
		if _target:
			_equip(_target.tool_type)
		elif spearfishing.can_thrust():
			_equip(&"spear")

	var fish := spearfishing.fish_target
	dot.scale = Vector2.ONE * (1.75 if _target or fish or _talk_target else (1.3 if spearfishing.can_thrust() else 1.0))
	if _talk_target:
		hover_label.text = _talk_target.prompt() if not _panel_open() else ""
		hover_label.modulate = Color.WHITE
	elif _target and not _target.can_gather():
		hover_label.text = "%s %d" % [Skills.display_name(_target.skill), _target.required_level]
		hover_label.modulate = DEFLECT_COLOR
	elif fish and not fish.can_catch():
		hover_label.text = "%s %d" % [Skills.display_name(&"fishing"), fish.species.required_level]
		hover_label.modulate = DEFLECT_COLOR
	else:
		hover_label.text = ""


## The crosshair ray stops at the first thing it touches, so a post or pole in front of a
## villager would hide them. This looks for a villager on the crosshair line ignoring the world,
## then accepts them if any of head, chest or hips is in plain sight (a wall still hides them).
func _villager_behind_clutter() -> Villager:
	var from := camera.global_position
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(from, from - camera.global_basis.z * interact_reach, NPC_MASK, [get_rid()])
	var v := space.intersect_ray(q).get("collider") as Villager
	if v == null:
		return null
	for h in [0.5, 1.0, 1.3]:
		var look := PhysicsRayQueryParameters3D.create(from, v.global_position + Vector3.UP * h, WORLD_MASK, [get_rid()])
		if space.intersect_ray(look).is_empty():
			return v
	return null


func _panel_open() -> bool:
	var panel := get_tree().get_first_node_in_group("upgrade_panel") as UpgradePanel
	return panel != null and panel.is_open()


## The E that closed the upgrade panel mustn't open it again straight away.
func _panel_just_closed() -> bool:
	var panel := get_tree().get_first_node_in_group("upgrade_panel") as UpgradePanel
	return panel != null and panel.just_closed()


func _equip(tool: StringName) -> void:
	if tool == _equipped:
		return
	var first := _equipped == &""
	_equipped = tool
	for id in tools:
		tools[id].visible = id == tool
	if not first:  # the new tool comes up from below the view
		_equip_dip = 0.35
		create_tween().tween_property(self, "_equip_dip", 0.0, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _swing(tool: StringName) -> void:
	_swinging = true
	for id in tools:
		tools[id].visible = id == tool
	_equipped = tool

	# 1. wind-up (anticipation): tip back, lift a little
	var t := create_tween().set_parallel()
	t.tween_property(tool_pivot, "rotation:x", WINDUP_ANGLE, windup_time).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	t.tween_property(tool_pivot, "position", _tool_rest + WINDUP_LIFT, windup_time).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	await t.finished

	# 2. strike — whoosh starts with the fast part of the motion; the arm reaches up and forward so
	# the head lands right on the crosshair
	if swing_sfx:
		audio.stream = swing_sfx
		audio.pitch_scale = 1.0  # (the dash plays it lower)
		audio.play()
	t = create_tween().set_parallel()
	t.tween_property(tool_pivot, "rotation:x", STRIKE_ANGLE, strike_time).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	t.tween_property(tool_pivot, "position", _tool_rest + STRIKE_REACH, strike_time).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await t.finished

	# 3. impact frame — hits whatever the crosshair is on *now*; looked away = whiff
	var hit := _aim()
	var node := _node_under_crosshair(hit)
	if node:
		var info := HitInfo.new(hit["position"], hit["normal"], node, camera.global_position)
		if node.hit(info):
			await _bite(tool, info)
			if is_instance_valid(node):
				node.pull(info)  # the chunk tears out as the tool comes free
		else:
			await _bounce()

	# 4. recover
	t = create_tween().set_parallel()
	t.tween_property(tool_pivot, "rotation:x", REST_ANGLE, recover_time).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(tool_pivot, "position", _tool_rest, recover_time).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	await t.finished
	_cooldown = swing_cooldown
	_swinging = false


## The tool bites in and sticks (the hit-stop freezes it there), then gets yanked back out with a
## jerk — the moment the chunk comes free. Sticking: see _stick_in_world.
func _bite(tool: StringName, info: HitInfo) -> void:
	var strike := _tool_rest + STRIKE_REACH
	var stuck := _stick_in_world(tool, info)
	if stuck == null:  # no world copy for this tool: just shove the held one forward
		tool_pivot.position = strike + Vector3(0, -bite_depth * 0.4, -bite_depth)
	var t := create_tween()
	t.tween_interval(bite_hold)  # (stretched by the hit-stop)
	await t.finished
	if stuck:
		await _unstick(stuck, tool)
	# yank: back toward the camera, head tipping up as it comes free
	t = create_tween().set_parallel()
	t.tween_property(tool_pivot, "position", strike + YANK_OFFSET, yank_time) 		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	t.tween_property(tool_pivot, "rotation:x", STRIKE_ANGLE + YANK_TIP, yank_time) 		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	await t.finished


## For the bite, the held tool is swapped for a copy in the world, so its edge can really bury
## itself in the node (the node's surface hides the part that's inside). The copy starts exactly
## where the held tool is on screen — its pose in viewmodel-camera space, widened for the main
## camera's wider FOV and scaled out from the eye until the edge is at the hit's depth — so the
## swap can't be seen; then it drives the last few centimetres in (in real time, so it happens
## even during the hit-stop). _unstick reverses it.
func _stick_in_world(tool: StringName, info: HitInfo) -> Node3D:
	var slot := tools[tool]
	if not TOOL_HEADS.has(tool):
		return null
	var buried := info.position - info.normal * stick_depth
	var start: Variant = _screen_matched(slot, tool, buried)
	if start == null:
		return null
	var from: Transform3D = start
	var edge: Vector3 = TOOL_HEADS[tool]
	var copy := slot.duplicate() as Node3D
	for m in copy.find_children("*", "MeshInstance3D", true, false):
		var mesh := m as MeshInstance3D
		mesh.layers = 1
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF  # it's huge in the world; no shadow
	get_parent().add_child(copy)
	copy.global_transform = from
	copy.set_meta("buried", buried)
	slot.visible = false
	var t := copy.create_tween().set_ignore_time_scale(true)
	t.tween_property(copy, "global_position", from.origin + (buried - from * edge), STICK_TIME) 		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	return copy


## Pulls the world copy back to where the held tool is on screen, then swaps back to it.
func _unstick(stuck: Node3D, tool: StringName) -> void:
	var slot := tools[tool]
	var back: Variant = _screen_matched(slot, tool, stuck.get_meta("buried"))
	if back != null:
		var t := stuck.create_tween().set_ignore_time_scale(true)
		t.tween_property(stuck, "global_position", (back as Transform3D).origin, STICK_TIME) 			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		await t.finished
	stuck.queue_free()
	slot.visible = true


## Where a held tool would have to be in the world to look exactly as it does on screen, pushed
## out from the eye so its edge is as deep as `depth_point`. Null if that can't be worked out.
func _screen_matched(slot: Node3D, tool: StringName, depth_point: Vector3) -> Variant:
	var vm_cam := slot.get_viewport().get_camera_3d()
	if vm_cam == null:
		return null
	var in_cam := vm_cam.global_transform.affine_inverse() * slot.global_transform
	var edge_cam := in_cam * (TOOL_HEADS[tool] as Vector3)
	var target_cam := camera.global_transform.affine_inverse() * depth_point
	if edge_cam.z >= -0.01 or target_cam.z >= -0.01:
		return null
	var widen := tan(deg_to_rad(camera.fov) * 0.5) / tan(deg_to_rad(vm_cam.fov) * 0.5)
	var k := target_cam.z / edge_cam.z
	return camera.global_transform * Transform3D(Basis.from_scale(Vector3(k * widen, k * widen, k)), Vector3.ZERO) * in_cam


## Deflected (level too low): the tool rebounds off the surface instead of biting in.
func _bounce() -> void:
	var t := create_tween().set_parallel().set_ignore_time_scale(true)
	t.tween_property(tool_pivot, "position", _tool_rest + STRIKE_REACH + Vector3(0, 0.03, 0.1), 0.06) 		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(tool_pivot, "rotation:x", STRIKE_ANGLE + 0.7, 0.06).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	await t.finished
