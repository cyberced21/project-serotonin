extends SceneTree
## Plays gathering sound stacks through the real buses (SFX's effects, then Master) and records
## what comes out of Master, so distortion from the bus effects can be measured without
## listening. Each event plays twice, once with SFX's effects bypassed, and both are saved:
##     godot --headless --path . -s res://tools/record_sfx_chain.gd -- [--out=user://sfx_chain]
## The report gives each event's peak at Master and how far the effects pulled its loudest
## moment down; a few dB is the compressor, much more is the limiter squashing it.

const EVENTS := {
	"axe_hit_oak": ["res://audio/woodcutting/oak/axe_hit.tres"],
	"clean_cut": ["res://audio/woodcutting/clean_cut.tres"],
	"tree_land_oak": ["res://audio/woodcutting/oak/tree_land.tres"],
	"pick_hit_iron": ["res://audio/mining/iron/pickaxe_hit.tres"],
	"pick_split_iron": ["res://audio/mining/iron/pickaxe_hit.tres", "res://audio/mining/iron/crack_tip.tres",
		"res://audio/mining/iron/split.tres"],
	"pick_hit_crystal": ["res://audio/mining/crystal/pickaxe_hit.tres"],
}
const LENGTH := 2.5

func _initialize() -> void:
	var out := "user://sfx_chain"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.trim_prefix("--out=")
	DirAccess.make_dir_recursive_absolute(out)
	var rec := AudioEffectRecord.new()
	AudioServer.add_bus_effect(0, rec)
	var sfx := AudioServer.get_bus_index(&"SFX")
	await create_timer(0.3).timeout
	for name: String in EVENTS:
		var peaks := []
		for bypass in [true, false]:
			AudioServer.set_bus_bypass_effects(sfx, bypass)
			seed(7)  # the same layer picks and pitches both times
			rec.set_recording_active(true)
			for path: String in EVENTS[name]:
				_play(load(path))
			await create_timer(LENGTH).timeout
			rec.set_recording_active(false)
			var wav := rec.get_recording()
			wav.save_to_wav("%s/%s_%s.wav" % [out, name, "dry" if bypass else "chain"])
			peaks.append(_peak_db(wav))
		print("%-18s peak %+5.1f dBFS raw, %+5.1f dBFS at Master: pulled down %4.1f dB" % [name, peaks[0], peaks[1], peaks[0] - peaks[1]])
	AudioServer.set_bus_bypass_effects(sfx, false)
	quit()

func _play(sound: SoundLayers) -> void:
	for layer in sound.layers:
		var p := AudioStreamPlayer.new()
		root.add_child(p)
		p.stream = layer.stream
		p.volume_db = layer.volume_db
		p.pitch_scale = layer.pitch * (1.0 + randf_range(-layer.pitch_jitter, layer.pitch_jitter))
		p.bus = sound.bus
		if layer.delay > 0.0:
			create_timer(layer.delay).timeout.connect(p.play)
		else:
			p.play()
		p.finished.connect(p.queue_free)

func _peak_db(wav: AudioStreamWAV) -> float:
	var data := wav.data
	var peak := 0
	var step := 2 if wav.stereo else 1
	for i in range(0, data.size() / 2, step):
		peak = maxi(peak, absi(data.decode_s16(i * 2)))
	return linear_to_db(maxf(peak, 1) / 32768.0)
