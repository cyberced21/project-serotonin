class_name ForgeCutscene
extends Node
## The forge moment (plans/tool-progression.md T12): Greta forging the tool you just paid for, in
## first person, about 8 s. A timeline of beats (_at), so a second E can skip to the reveal:
##   1. the village holds its breath: ambience ducks, the screen darkens round the forge, which
##      flares (embers, a light), and the view eases to the anvil
##   2. three blows, each heavier: hit-stop, sparks, a ring off the buildings, growing shake
##   3. the quench: a huge hiss, steam, everything white for a beat
##   4. the reveal: the tool in a shaft of light in its tier's colour, its name in big letters
##   5. into your hands: it rises into the viewmodel with a glint; villagers nearby cheer
## It escalates by tier: copper is the plain version; iron adds a thunder roll and the town
## hall's bell; crystal is the finale (the sky darkens, a violet beam rises over the village,
## every villager cheers, the bell rings out twice).
## The first biting hit with the new tool then lands oversized (first_swing, from ResourceNode).

const SOUND_DIR := "res://audio/forge/"
const REVEAL_AT := 4.9
const HANDOVER_AT := 7.6
const END_AT := 8.6
const BLOWS: Array[float] = [1.5, 2.4, 3.3]
## How big the tool shows at the reveal, 0.75 m in front of the eye.
const REVEAL_SCALE := 1.4
## The tier's colour: copper warm, iron cold steel, crystal violet (index = tool tier).
const TIER_COLORS: Array[Color] = [Color("d8c8a8"), Color("ff9a4a"), Color("bcd6ff"), Color("c58bff")]
const LINES: Array[String] = ["Well forged!", "Look at that edge!", "Now that's a tool!", "Greta's outdone herself!",
	"Hear that ring?", "Fine work!"]
const GRETA_LINES: Array[String] = ["Mind the edge.", "Treat it well.", "Best I've made."]

var tool: StringName
var tier := 0

var _t := 0.0
var _events: Array = []  # [time, Callable], sorted
var _skipped := false
var _greta: Villager
var _player: Node3D
var _anvil := Vector3.ZERO
var _hearth := Vector3.ZERO
var _quench := Vector3.ZERO
var _voices: Array[AudioStreamPlayer] = []
var _hud: CanvasLayer

var _layer: CanvasLayer
var _vignette: ColorRect
var _sky: ColorRect
var _white: ColorRect
var _title: Label
var _sub: Label
var _hint: Label
var _forge_light: OmniLight3D
var _embers: CPUParticles3D
var _blank: MeshInstance3D
var _model: Node3D
var _spot: SpotLight3D
var _beam: MeshInstance3D


## Plays the forge moment for `tool` (already forged: Tools.tier is the new tier), at Greta.
static func play(greta: Villager, tool_id: StringName) -> ForgeCutscene:
	var c := ForgeCutscene.new()
	c.tool = tool_id
	c.tier = Tools.tier(tool_id)
	c._greta = greta
	greta.get_tree().current_scene.add_child(c)
	return c


static func tier_color(t: int) -> Color:
	return TIER_COLORS[clampi(t, 0, TIER_COLORS.size() - 1)]


## The first biting hit with a freshly forged tool: a shockwave ring, a boom, the biggest kick.
static func first_swing(parent: Node, at: Vector3, normal: Vector3, color: Color) -> void:
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.9
	torus.outer_radius = 1.0
	ring.mesh = torus
	ring.material_override = _glow_material(color, 3.0)
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(ring)
	ring.global_position = at
	ring.global_basis = Basis(Quaternion(Vector3.UP, normal.normalized())) if normal.length() > 0.01 else Basis.IDENTITY
	ring.scale = Vector3.ONE * 0.1
	var mat := ring.material_override as StandardMaterial3D
	var t := ring.create_tween().set_parallel()
	t.tween_property(ring, "scale", Vector3.ONE * 0.9, 0.5).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	t.tween_property(mat, "albedo_color:a", 0.0, 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	t.chain().tween_callback(ring.queue_free)
	HitFx.star(parent, at + normal * 0.1, color, 1.6)
	var boom := AudioStreamPlayer.new()
	boom.stream = load(SOUND_DIR + "shockwave.wav")
	boom.volume_db = -2.0
	parent.add_child(boom)
	boom.play()
	boom.finished.connect(boom.queue_free)
	Juice.hitstop(0.16)
	Juice.shake(7.0)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_player = get_tree().get_first_node_in_group("player") as Node3D
	_find_spots()
	_build_overlay()
	_build_world()
	_plan()
	_begin()


func _process(delta: float) -> void:
	_t += delta
	while not _events.is_empty() and _events[0][0] <= _t:
		var e: Array = _events.pop_front()
		(e[1] as Callable).call()
	if _model and is_instance_valid(_model):
		_model.rotate_y(delta * 0.9)
	if _forge_light:  # the coals breathing
		_forge_light.light_energy += (randf() - 0.5) * 0.6


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("interact") and not _skipped and _t > 0.3 and _t < REVEAL_AT:
		get_viewport().set_input_as_handled()
		_skip()


# --- the timeline ---------------------------------------------------------------------------

func _at(time: float, f: Callable) -> void:
	_events.append([time, f])


func _plan() -> void:
	for i in BLOWS.size():
		_at(BLOWS[i] - 0.45, _raise_hammer)
		_at(BLOWS[i], _blow.bind(i))
	_at(3.9, _lift_blank)
	_at(4.25, _quench_it)
	_at(4.55, _look_up)
	_at(REVEAL_AT, _reveal)
	_at(HANDOVER_AT, _handover)
	_at(END_AT, _end)
	if tier >= 2:  # iron and above: thunder over the reveal, then the bell
		_at(REVEAL_AT + 0.1, _sound.bind("thunder", -2.0))
		_at(REVEAL_AT + 0.1, Juice.shake.bind(3.0))
		_at(REVEAL_AT + 1.3, _sound.bind("bell", -3.0))
	if tier >= 3:  # crystal: the beam, and the bell again
		_at(3.6, _raise_beam)
		_at(REVEAL_AT + 2.4, _sound.bind("bell", -5.0, 1.0))
	_events.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])


func _begin() -> void:
	_player.call("set_cutscene", true)
	_greta.scripted = true
	var from := _player.global_position
	var across := _anvil - from
	across.y = 0.0
	_greta.script_place(_anvil + across.normalized() * 0.7, _anvil)
	_greta.script_pose(&"ArmL", -0.8, -0.1)
	_greta.script_pose(&"ArmR", -0.9, 0.05)
	_player.call("face_point", _anvil + Vector3.UP * 0.15, 1.1)
	_hud = get_tree().current_scene.get_node_or_null("HUD") as CanvasLayer
	if _hud:
		_hud.visible = false
	var t := create_tween().set_parallel()
	t.tween_property(Biome, "ambience_duck", 0.12, 0.8)
	t.tween_property(Music, "duck", 0.15, 0.8)
	t.tween_method(_set_vignette, 0.0, 1.0, 0.9)
	t.tween_property(_forge_light, "light_energy", 7.0, 0.6).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	if tier >= 3:
		t.tween_property(_sky, "color:a", 0.5, 2.5)
	_embers.emitting = true
	Biome.hide_card()
	_sound("flare", -3.0)
	_sound("drone", -6.0)


func _raise_hammer() -> void:
	_greta.script_pose(&"ArmR", -2.3, 0.05)
	_greta.script_pose(&"Body", 0.05)


func _blow(i: int) -> void:
	var heavy := float(i) / (BLOWS.size() - 1)  # 0, 0.5, 1
	_greta.script_pose(&"ArmR", -0.85, 0.05)
	_greta.script_pose(&"Body", -0.12)
	_sound("blow_%d" % (i + 1), -1.0 + 2.0 * heavy)
	Juice.hitstop(0.05 + 0.04 * i)
	Juice.shake(2.0 + 2.0 * i)
	_sparks(_blank.global_position, 30 + 25 * i, 3.0 + 1.5 * i)
	_forge_light.light_energy = 14.0 + 4.0 * i
	var mat := _blank.material_override as StandardMaterial3D
	mat.emission_energy_multiplier = 3.0 + 2.0 * i


func _lift_blank() -> void:
	_greta.script_pose(&"ArmR", -1.3, 0.3)
	var t := create_tween()
	t.tween_property(_blank, "global_position", _quench + Vector3.UP * 0.25, 0.3).set_trans(Tween.TRANS_SINE)


func _quench_it() -> void:
	_greta.script_pose(&"ArmR", -0.5, 0.3)
	create_tween().tween_property(_blank, "global_position", _quench - Vector3.UP * 0.05, 0.12)
	_sound("hiss", 0.0)
	_steam(_quench)
	Juice.shake(2.5)
	create_tween().tween_property(_white, "color:a", 1.0, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)


## Under the white: the view comes up level, toward Greta, for the reveal.
func _look_up() -> void:
	var cam := (_player.get("camera") as Camera3D)
	_player.call("face_point", cam.global_position + _level_forward() * 3.0, 0.3)


func _level_forward() -> Vector3:
	var f := _anvil - _player.global_position
	f.y = 0.0
	return f.normalized() if f.length() > 0.01 else Vector3.FORWARD


func _reveal() -> void:
	_blank.visible = false
	_greta.script_pose(&"ArmR", -0.9, 0.05)
	_greta.script_pose(&"Body", 0.0)
	var color := tier_color(tier)
	var cam := (_player.get("camera") as Camera3D)
	var at := cam.global_position + _level_forward() * 0.75 + Vector3.DOWN * 0.05
	_model = _tool_model()
	if _model:
		add_child(_model)
		_model.global_position = at - Vector3.UP * REVEAL_SCALE * 0.3  # (its origin is the handle's end)
		_model.scale = Vector3.ONE * REVEAL_SCALE * 0.4
		var pop := create_tween()
		pop.tween_property(_model, "scale", Vector3.ONE * REVEAL_SCALE, 0.6).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_spot = SpotLight3D.new()
	_spot.light_color = color
	_spot.light_energy = 12.0
	_spot.spot_range = 4.0
	_spot.spot_angle = 16.0
	add_child(_spot)
	_spot.global_position = at + Vector3.UP * 2.0
	_spot.look_at(at, Vector3.FORWARD)
	_sound("reveal", -2.0)
	_title.text = Tools.display_name(tool, tier).to_upper()
	_title.add_theme_color_override("font_color", color)
	var recipes: Array = Tools.RECIPES.get(tool, [])
	_sub.text = recipes[tier - 1]["opens"] if tier >= 1 and tier <= recipes.size() else ""
	_title.pivot_offset = _title.size / 2.0
	_title.scale = Vector2(1.6, 1.6)
	var t := create_tween().set_parallel()
	t.tween_property(_white, "color:a", 0.0, 0.8).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_property(_title, "modulate:a", 1.0, 0.4)
	t.tween_property(_title, "scale", Vector2.ONE, 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(_sub, "modulate:a", 1.0, 0.6).set_delay(0.5)
	_hint.visible = false


func _handover() -> void:
	var cam := (_player.get("camera") as Camera3D)
	if _model:
		var t := create_tween().set_parallel().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		t.tween_property(_model, "global_position", cam.global_position + cam.global_basis * Vector3(0.35, -0.45, -0.4), 0.3)
		t.tween_property(_model, "scale", Vector3.ONE * 0.1, 0.3)
		t.chain().tween_callback(_model.queue_free)
	get_tree().create_timer(0.3).timeout.connect(func() -> void:
		_player.call("equip_now", tool)
		_sound("settle", 0.0)
		_sound("glint", -4.0))
	var fade := create_tween().set_parallel()
	fade.tween_property(_title, "modulate:a", 0.0, 0.6).set_delay(0.3)
	fade.tween_property(_sub, "modulate:a", 0.0, 0.6).set_delay(0.3)
	fade.tween_method(_set_vignette, 1.0, 0.0, 0.9)
	fade.tween_property(_sky, "color:a", 0.0, 1.2)
	fade.tween_property(Biome, "ambience_duck", 1.0, 1.4)
	fade.tween_property(Music, "duck", 1.0, 1.4)
	fade.tween_property(_forge_light, "light_energy", 0.0, 1.0)
	if _spot:
		fade.tween_property(_spot, "light_energy", 0.0, 0.5)
	if _beam:
		fade.tween_property(_beam, "scale:x", 0.0, 1.0)
		fade.tween_property(_beam, "scale:z", 0.0, 1.0)
	_embers.emitting = false
	_cheers()


func _end() -> void:
	_player.call("set_cutscene", false)
	_greta.scripted = false
	if _hud:
		_hud.visible = true
	Biome.ambience_duck = 1.0
	Music.duck = 1.0
	queue_free()


## E during the build-up: straight to the reveal (from white, as if the quench just happened).
func _skip() -> void:
	_skipped = true
	for v in _voices:
		if is_instance_valid(v):
			v.stop()
	_events = _events.filter(func(e: Array) -> bool: return e[0] >= REVEAL_AT)
	_white.color.a = 1.0
	_set_vignette(1.0)
	if tier >= 3 and _beam == null:
		_raise_beam()
	_t = REVEAL_AT - 0.01


# --- the beats' pieces ----------------------------------------------------------------------

func _cheers() -> void:
	PopupText.spawn(get_tree().current_scene, _greta.global_position + Vector3.UP * 2.3,
		GRETA_LINES[randi() % GRETA_LINES.size()], Color("ffd27a"), 12)
	var lines := LINES.duplicate()
	lines.shuffle()
	var k := 0
	for v: Villager in get_tree().current_scene.find_children("*", "Villager", true, false):
		if v == _greta or v.building.tier_shown == 0:
			continue
		if tier < 3 and v.global_position.distance_to(_player.global_position) > 30.0:
			continue  # crystal: the whole village
		v.cheer()
		PopupText.spawn(get_tree().current_scene, v.global_position + Vector3.UP * 2.3,
			lines[k % lines.size()], Color.WHITE, 10, 0.15 * k)
		k += 1


func _raise_beam() -> void:
	_beam = MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.5
	cyl.bottom_radius = 0.18
	cyl.height = 90.0
	_beam.mesh = cyl
	var mat := _glow_material(tier_color(3), 4.0)
	mat.albedo_color.a = 0.55
	_beam.material_override = mat
	_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_beam)
	_beam.global_position = _anvil + Vector3.UP * 45.0  # (out of the glowing blade, through the roof)
	_beam.scale = Vector3(1.0, 0.01, 1.0)
	var light := OmniLight3D.new()
	light.light_color = tier_color(3)
	light.omni_range = 30.0
	light.light_energy = 0.0
	_beam.add_child(light)
	light.position = Vector3(0, -40.0, 0)
	var t := create_tween().set_parallel()
	t.tween_property(_beam, "scale:y", 1.0, 1.3).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	t.tween_property(light, "light_energy", 6.0, 1.0)
	_sound("beam", -2.0)
	Juice.shake(4.0)


func _sparks(at: Vector3, amount: int, speed: float) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.amount = amount
	p.lifetime = 0.7
	p.explosiveness = 1.0
	p.direction = Vector3.UP
	p.spread = 80.0
	p.initial_velocity_min = speed * 0.5
	p.initial_velocity_max = speed
	p.gravity = Vector3(0, -9.8, 0)
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.0
	var quad := QuadMesh.new()
	quad.size = Vector2(0.06, 0.06)
	p.mesh = quad
	p.material_override = _glow_material(Color("ffd890"), 6.0, true)
	add_child(p)
	p.global_position = at
	p.emitting = true
	p.finished.connect(p.queue_free)


func _steam(at: Vector3) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.amount = 60
	p.lifetime = 1.6
	p.explosiveness = 0.8
	p.direction = Vector3.UP
	p.spread = 35.0
	p.initial_velocity_min = 1.0
	p.initial_velocity_max = 2.5
	p.gravity = Vector3(0, 0.6, 0)
	p.scale_amount_min = 1.0
	p.scale_amount_max = 3.0
	var quad := QuadMesh.new()
	quad.size = Vector2(0.5, 0.5)
	p.mesh = quad
	var mat := _glow_material(Color(1, 1, 1, 0.3), 0.0, true)
	p.material_override = mat
	add_child(p)
	p.global_position = at
	p.emitting = true
	p.finished.connect(p.queue_free)


func _sound(id: String, db := 0.0, pitch := 1.0) -> void:
	var stream := load(SOUND_DIR + id + ".wav") as AudioStream
	if stream == null:
		return
	var a := AudioStreamPlayer.new()
	a.stream = stream
	a.volume_db = db
	a.pitch_scale = pitch
	add_child(a)
	a.play()
	a.finished.connect(a.queue_free)
	_voices.append(a)


func _set_vignette(v: float) -> void:
	(_vignette.material as ShaderMaterial).set_shader_parameter("amount", v)


## The tool's model (the player's), lit by the palette like the held one.
func _tool_model() -> Node3D:
	var scene := _player.call("tool_model", tool) as PackedScene
	if scene == null:
		return null
	var inst := scene.instantiate() as Node3D
	for m in inst.find_children("*", "MeshInstance3D", true, false):
		(m as MeshInstance3D).material_override = preload("res://materials/node_palette.tres")
	if tool == &"spear" or tool == &"rod":  # long, and lying along -Z: stood up and scaled to fit
		var holder := Node3D.new()
		holder.add_child(inst)
		inst.rotation.x = PI * 0.5
		inst.scale = Vector3.ONE * 0.38
		inst.position.y = 0.1
		return holder
	return inst


static func _glow_material(color: Color, energy: float, billboard := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = color
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if energy > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = energy
	if billboard:  # (particles: soft round sprites, not squares)
		m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		m.albedo_texture = _soft_dot()
		m.vertex_color_use_as_albedo = true
	return m


static var _dot: Texture2D


static func _soft_dot() -> Texture2D:
	if _dot == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		var tex := GradientTexture2D.new()
		tex.gradient = g
		tex.fill = GradientTexture2D.FILL_RADIAL
		tex.fill_from = Vector2(0.5, 0.5)
		tex.fill_to = Vector2(0.5, 0.0)
		tex.width = 32
		tex.height = 32
		_dot = tex
	return _dot


# --- setup ----------------------------------------------------------------------------------

## The anvil, hearth and quench water of the smithy's current tier (by mesh name, from
## make_village.py), each falling back to a spot near Greta.
func _find_spots() -> void:
	var b := _greta.building
	var anvil := _visible_mesh(b, "AnvilTop", "")
	_anvil = anvil.global_position if anvil else _greta.global_position + _greta.global_basis.z * 0.8 + Vector3.UP * 0.75
	var hearth := _visible_mesh(b, "Forge", "Crystal")
	_hearth = hearth.global_position if hearth else _anvil + Vector3(0, 0.3, 0)
	var water := _visible_mesh(b, "Water", "")  # (the trough, or the stone forge's barrel)
	_quench = water.global_position if water else _anvil + _greta.global_basis.x * 0.9 - Vector3.UP * 0.3


static func _visible_mesh(root: Node, contains: String, excludes: String) -> MeshInstance3D:
	for m: MeshInstance3D in root.find_children("*%s*" % contains, "MeshInstance3D", true, false):
		if m.is_visible_in_tree() and (excludes.is_empty() or not excludes in m.name):
			return m
	return null


func _build_world() -> void:
	_forge_light = OmniLight3D.new()
	_forge_light.light_color = Color("ff8a3a")
	_forge_light.omni_range = 7.0
	_forge_light.light_energy = 0.0
	_forge_light.shadow_enabled = false
	add_child(_forge_light)
	_forge_light.global_position = _hearth + Vector3.UP * 0.4

	_embers = CPUParticles3D.new()
	_embers.amount = 50
	_embers.lifetime = 2.2
	_embers.direction = Vector3.UP
	_embers.spread = 25.0
	_embers.initial_velocity_min = 0.6
	_embers.initial_velocity_max = 1.6
	_embers.gravity = Vector3(0, 0.4, 0)
	_embers.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	_embers.emission_sphere_radius = 0.35
	var quad := QuadMesh.new()
	quad.size = Vector2(0.07, 0.07)
	_embers.mesh = quad
	_embers.material_override = _glow_material(Color("ffa040"), 5.0, true)
	_embers.emitting = false
	add_child(_embers)
	_embers.global_position = _hearth + Vector3.UP * 0.3

	_blank = MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.3, 0.05, 0.08)
	_blank.mesh = box
	var glow := _glow_material(Color("ffb060"), 2.0)
	glow.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	_blank.material_override = glow
	add_child(_blank)
	_blank.global_position = _anvil + Vector3.UP * 0.1


func _build_overlay() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 5
	add_child(_layer)
	_vignette = _rect(Color.BLACK)
	var shader := Shader.new()
	shader.code = """shader_type canvas_item;
uniform float amount = 0.0;
uniform vec4 tint : source_color = vec4(0.02, 0.01, 0.0, 1.0);
void fragment() {
	float d = distance(UV, vec2(0.5)) * 1.45;
	COLOR = vec4(tint.rgb, mix(0.38, 0.96, smoothstep(0.2, 0.95, d)) * amount);
}"""
	var mat := ShaderMaterial.new()
	mat.shader = shader
	_vignette.material = mat
	_sky = _rect(Color(0.12, 0.02, 0.2, 0.0))
	_white = _rect(Color(1, 1, 1, 0.0))
	_title = _text(64)
	_title.anchor_top = 0.68
	_title.anchor_bottom = 0.68
	_sub = _text(26)
	_sub.anchor_top = 0.78
	_sub.anchor_bottom = 0.78
	_hint = Label.new()
	_hint.text = "E  skip"
	_hint.modulate = Color(1, 1, 1, 0.5)
	_hint.add_theme_font_size_override("font_size", 16)
	_hint.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_hint.position -= Vector2(110, 50)
	_layer.add_child(_hint)


func _rect(color: Color) -> ColorRect:
	var r := ColorRect.new()
	r.color = color
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(r)
	return r


func _text(font_size: int) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("shadow_offset_x", 2)
	l.add_theme_constant_override("shadow_offset_y", 3)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.anchor_left = 0.0
	l.anchor_right = 1.0
	l.modulate.a = 0.0
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(l)
	return l
