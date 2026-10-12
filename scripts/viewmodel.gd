extends CanvasLayer
## Draws the held tool from a second camera into a transparent SubViewport layered over the main
## view, so the tool never clips into trees / rocks and can have its own FOV.
## Both cameras share the world (and its sun): the main camera skips render layer 2,
## the viewmodel camera only sees layer 2. Tool meshes must be on layer 2.

## The main (eye) camera to follow.
@export var main_camera: Camera3D

@onready var viewport: SubViewport = $SubViewport
@onready var view: TextureRect = $View
@onready var camera: Camera3D = $SubViewport/Camera3D


func _ready() -> void:
	process_priority = 100  # after the main camera's shake has been applied this frame
	view.texture = viewport.get_texture()
	get_window().size_changed.connect(_fit)
	_fit()


## Render at the real window resolution so the tool stays crisp at any window size.
func _fit() -> void:
	viewport.size = get_window().size


func _process(_delta: float) -> void:
	camera.global_transform = main_camera.global_transform
