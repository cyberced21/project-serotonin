extends SceneTree
## Measures every track in audio/music/: length, peak and loudness (RMS over the whole piece,
## in dBFS), decoded offline through AudioStreamPlayback.mix_audio, so it runs headless in
## seconds. Prints the trim (dB) that brings each to TARGET_DB without its peak passing
## PEAK_CEILING, for data/music/library.tres:
##     godot --headless --path . -s res://tools/measure_music.gd

const DIR := "res://audio/music/"
## The loudness every piece is trimmed to (RMS dBFS). Quiet, so pieces sit as a soft bed.
const TARGET_DB := -20.0
const PEAK_CEILING := -1.0
const RATE := 44100.0
const CHUNK := 4096


func _initialize() -> void:
	for file in DirAccess.get_files_at(DIR):
		if not (file.ends_with(".ogg") or file.ends_with(".mp3")):
			continue
		var stream := load(DIR + file) as AudioStream
		var pb := stream.instantiate_playback()
		pb.start(0.0)
		var sum := 0.0
		var peak := 0.0
		var frames := 0
		var total := int(stream.get_length() * RATE)
		while frames < total:
			var buf := pb.mix_audio(1.0, CHUNK)
			if buf.is_empty():
				break
			for v in buf:
				var m := (v.x + v.y) * 0.5
				sum += m * m
				peak = maxf(peak, maxf(absf(v.x), absf(v.y)))
			frames += buf.size()
		var rms_db := linear_to_db(sqrt(sum / maxi(frames, 1)))
		var trim := minf(TARGET_DB - rms_db, PEAK_CEILING - linear_to_db(peak))
		print("%-22s %6.1f s   peak %6.1f dB   rms %6.1f dB   trim %+5.1f dB" % [file, stream.get_length(),
			linear_to_db(peak), rms_db, trim])
	quit()
