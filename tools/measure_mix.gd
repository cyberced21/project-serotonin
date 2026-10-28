extends SceneTree
## The final mix check (plans/cozy-sound.md, phase 10): plays each family of sounds through the
## game's own code and buses in Hearthvale by day, one family at a time (the other
## top-level buses muted), records Master and prints how loud each comes out: the loud part
## (the 90th percentile of 50 ms windows, dBFS RMS) and the peak. Families: the ambience bed,
## music, footsteps, gathering, pickups, interface clicks.
##   godot --headless --path . -s res://tools/measure_mix.gd -- --save-root=user://tool_worlds [--place=pinewood]

const TOP: Array[StringName] = [&"Effects", &"Ambience", &"Movement", &"Music"]

var _rec: AudioEffectRecord


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.get_node("Worlds").call("play_fresh")
	await process_frame
	while get_first_node_in_group("player") == null:
		await process_frame
	root.get_node("DayNight").set("time", 0.45)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--place="):
			root.get_node("Biome").set("current", StringName(a.trim_prefix("--place=")))
	_rec = AudioEffectRecord.new()
	AudioServer.add_bus_effect(0, _rec)
	var player := get_first_node_in_group("player")
	var steps: Node = player.get("footsteps")
	var sfx := root.get_node("Sfx")
	var music := root.get_node("Music")
	await create_timer(4.0).timeout  # beds settle into the day
	_report("ambience bed", await _take(&"Ambience", 6.0, func() -> void: pass))
	music.call("play_next")
	_report("music", await _take(&"Music", 10.0, func() -> void: pass, 5.0))  # past its fade-in
	_report("footsteps (walk)", await _take(&"Movement", 4.0, func() -> void:
		for i in 8:  # (straight to the step: the idle player's own tick would reset a stride)
			steps.call("_play", steps.get("walk_db"), 1.0)
			await create_timer(0.5).timeout))
	for path in ["res://audio/mining/iron/pickaxe_hit.tres", "res://audio/woodcutting/oak/axe_hit.tres"]:
		_report(path.get_file().get_basename() + " " + path.get_base_dir().get_file(),
			await _take(&"Effects", 2.0, _layers.bind(load(path))))
	_report("pickup", await _take(&"Effects", 2.0, func() -> void: sfx.call("play_pickup")))
	_report("ui click", await _take(&"Effects", 1.5, func() -> void: sfx.call("play_ui", &"click")))
	quit()


## Records Master for `secs` with only `bus` (of the top-level buses) unmuted, `lead` s in.
func _take(bus: StringName, secs: float, start: Callable, lead := 0.3) -> AudioStreamWAV:
	for b in TOP:
		AudioServer.set_bus_mute(AudioServer.get_bus_index(b), b != bus)
	await create_timer(lead).timeout
	_rec.set_recording_active(true)
	start.call()
	await create_timer(secs).timeout
	_rec.set_recording_active(false)
	return _rec.get_recording()


func _layers(sound: SoundLayers) -> void:
	for layer in sound.layers:
		var p := AudioStreamPlayer.new()
		root.add_child(p)
		p.stream = layer.stream
		p.volume_db = layer.volume_db
		p.pitch_scale = layer.pitch
		p.bus = sound.bus
		if layer.delay > 0.0:
			create_timer(layer.delay).timeout.connect(p.play)
		else:
			p.play()
		p.finished.connect(p.queue_free)


func _report(what: String, wav: AudioStreamWAV) -> void:
	var data := wav.data
	var ch := 2 if wav.stereo else 1
	var win := int(wav.mix_rate * 0.05)
	var frames := data.size() / 2 / ch
	var rms: Array[float] = []
	var peak := 0.0
	var f := 0
	while f + win <= frames:
		var sum := 0.0
		for j in win:
			var s := 0.0
			for c in ch:
				s += data.decode_s16(((f + j) * ch + c) * 2) / 32768.0
			s /= ch
			sum += s * s
			peak = maxf(peak, absf(s))
		rms.append(sqrt(sum / win))
		f += win
	rms.sort()
	var loud := rms[int(rms.size() * 0.9)] if not rms.is_empty() else 0.0
	print("%-22s loud part %6.1f dBFS   peak %6.1f dBFS" % [what, linear_to_db(maxf(loud, 1e-6)), linear_to_db(maxf(peak, 1e-6))])
