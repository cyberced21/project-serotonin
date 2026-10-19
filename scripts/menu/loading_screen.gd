class_name LoadingScreen
extends CanvasLayer
## A generated world's loading screen: its picture (dimmed) or a plain dark backdrop, its name,
## what's happening now and a progress bar. ProcgenWorld drives it while the world builds.

var _stage: Label
var _bar: ProgressBar
var _shown := 0.0
var _target := 0.0


func _init(world_name: String, picture_path := "") -> void:
	layer = 20
	add_to_group("loading_screen")
	var bg := ColorRect.new()
	bg.color = Color(0.09, 0.075, 0.06)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	if not picture_path.is_empty() and FileAccess.file_exists(picture_path):
		var img := Image.load_from_file(picture_path)
		if img:
			var pic := TextureRect.new()
			pic.texture = ImageTexture.create_from_image(img)
			pic.set_anchors_preset(Control.PRESET_FULL_RECT)
			pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
			pic.modulate = Color(0.45, 0.42, 0.4)
			add_child(pic)

	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BOTH
	box.custom_minimum_size = Vector2(520, 0)
	box.add_theme_constant_override("separation", 12)
	add_child(box)
	var title := MenuUI.title(world_name if world_name != "" else "A new world", 40)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	_stage = MenuUI.label("", 18, Color(1, 1, 1, 0.85))
	_stage.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_stage)
	_bar = ProgressBar.new()
	_bar.show_percentage = false
	_bar.custom_minimum_size = Vector2(0, 14)
	_bar.max_value = 1.0
	_bar.add_theme_stylebox_override("background", MenuUI.box(Color(0, 0, 0, 0.5), 0.0, MenuUI.BORDER, 7))
	_bar.add_theme_stylebox_override("fill", MenuUI.box(MenuUI.ACCENT, 0.0, Color.TRANSPARENT, 7))
	box.add_child(_bar)


## `progress` 0..1 overall; `stage` what's happening ("Growing the forest").
func report(progress: float, stage: String) -> void:
	_target = maxf(_target, clampf(progress, 0.0, 1.0))
	_stage.text = stage + "…"


func _process(delta: float) -> void:
	_shown = move_toward(_shown, _target, delta * 1.5)  # glides, never jumps back
	_bar.value = _shown
