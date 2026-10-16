class_name SoundLayer
extends Resource
## One layer of a SoundLayers stack: a stream played some time after the event, at its own
## volume, with its own pitch wobble. See SoundLayers.

@export var stream: AudioStream
## Seconds after the event (real time: hit-stop doesn't stretch it). Lets a gravel trickle land
## a beat after the crack.
@export_range(0.0, 1.0) var delay := 0.0
@export_range(-40.0, 12.0) var volume_db := 0.0
## Random pitch change each time, as a fraction (0.05 = up to 5% higher or lower).
@export_range(0.0, 0.5) var pitch_jitter := 0.0
## Multiply this layer's pitch by the pitch the caller asks for (e.g. the rock's stress
## escalation). Off for layers that should stay put, like a low thump.
@export var follows_pitch := true
## Base pitch before the caller's pitch and the jitter.
@export_range(0.25, 4.0) var pitch := 1.0
