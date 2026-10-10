# Headless check of the procedural audio: synthesis time, peak and RMS of
# every sound, which ambience beds play at each hour, and a worst-case
# estimate of the master bus level.
#   godot --headless --path . -s res://tools/audio_check.gd
extends SceneTree

const AudioScript = preload("res://scripts/audio.gd")


func _init() -> void:
	var a = AudioScript.new()
	root.add_child(a)
	var t0 := Time.get_ticks_msec()
	while not a.loaded:
		await process_frame
	print("synth/load: %d ms, %d sounds" % [Time.get_ticks_msec() - t0, a.sounds.size()])
	for k in a.synth_ms:
		if a.synth_ms[k] > 300:
			print("  slow: %s %d ms" % [k, a.synth_ms[k]])
	var worst := -INF
	var keys: Array = a.stats.keys()
	keys.sort()
	for k in keys:
		var s: Array = a.stats[k]
		var pk := linear_to_db(s[0])
		worst = maxf(worst, pk)
		var w: AudioStreamWAV = a.sounds[k.get_slice("#", 0)][int(k.get_slice("#", 1))]
		print("%-18s peak %6.1f dBFS  rms %6.1f dBFS  %5.2f s %s" % [k, pk, linear_to_db(s[1]), w.get_length(), "stereo loop" if w.stereo else ("loop" if w.loop_mode else "")])
	print("loudest sample peak: %.1f dBFS" % worst)
	_seams(a)

	var beds: Array = a.BED_DB.keys()
	var head := "hour  weather   "
	for b in beds:
		head += "%-11s" % b
	print("\nAmbience beds by hour (dB on the mix, '-' = silent); events with weight > 0.2")
	print(head)
	var max_sum := 0.0
	var worst_rows := {}
	for wx in [["clear", 0.0, 0.0, 0.0], ["rain", 1.0, 1.0, 0.8], ["after", 0.0, 0.7, 0.0]]:
		for h in range(0, 24):
			var w: Dictionary = a.weights(float(h), wx[1], wx[2], wx[3])
			var line := "%02d:00 %-9s " % [h, wx[0]]
			var sum_pk := 0.0
			for b in beds:
				var lv: float = w.get(b, 0.0)
				if lv < 0.005:
					line += "%-11s" % "-"
				else:
					var db: float = a.BED_DB[b] + linear_to_db(lv)
					line += "%-11s" % ("%.1f" % db)
					sum_pk += a.stats[b + "#0"][0] * db_to_linear(db)
			var ev := []
			for e in a.EVENTS:
				if w.get(a.EVENTS[e][0], 0.0) > 0.2:
					ev.append(e)
			# Loops near the player at full level add on top.
			sum_pk += _loop_peak(a, w, wx[1])
			max_sum = maxf(max_sum, sum_pk)
			if sum_pk > worst_rows.get(wx[0], [0.0])[0]:
				worst_rows[wx[0]] = [sum_pk, w]
			print(line + " sum-of-peaks %5.1f dB  events: %s" % [linear_to_db(sum_pk), ", ".join(ev)])
	print("\nworst-case sum of bed+loop peaks: %.1f dBFS (master limiter ceiling -1 dB)" % linear_to_db(max_sum))
	# The sum of peaks assumes every peak lines up; mix the real PCM of the
	# loudest hour of each weather to measure what the master bus sees.
	for k in worst_rows:
		print("true mix peak, loudest %s hour: %.1f dBFS" % [k, linear_to_db(_mix_peak(a, worst_rows[k][1], 1.0 if k == "rain" else 0.0))])
	quit()


func _mix_peak(a, w: Dictionary, rain: float) -> float:
	var n := 6 * 44100
	var mix := PackedFloat32Array()
	mix.resize(n * 2)
	var srcs := []
	for b in a.BED_DB:
		var lv: float = w.get(b, 0.0)
		if lv > 0.005:
			srcs.append([b, db_to_linear(a.BED_DB[b]) * lv, true])
	for n3 in ["canal", "gate_flow"]:
		srcs.append([n3, db_to_linear(a.LOOP3D[n3][0]), false])
	srcs.append(["bamboo", db_to_linear(a.LOOP3D["bamboo"][0]) * w.bamboo, false])
	if rain > 0.0:
		srcs.append(["rain_roof", db_to_linear(a.LOOP3D["rain_roof"][0]), false])
	for s in srcs:
		var wav: AudioStreamWAV = a.sounds[s[0]][0]
		var d: PackedByteArray = wav.data
		var ch := 2 if wav.stereo else 1
		var frames := d.size() / (2 * ch)
		for i in n:
			var f := i % frames
			var l := d.decode_s16(f * ch * 2) / 32767.0
			var r := d.decode_s16((f * ch + ch - 1) * 2) / 32767.0
			mix[i * 2] += l * s[1]
			mix[i * 2 + 1] += r * s[1]
	var pk := 0.0
	for x in mix:
		pk = maxf(pk, absf(x))
	return pk


# Every positional loop at its unit distance, the nearest case for the player.
func _loop_peak(a, w: Dictionary, rain: float) -> float:
	var s := 0.0
	for n in ["canal", "gate_flow"]:
		s += a.stats[n + "#0"][0] * db_to_linear(a.LOOP3D[n][0])
	s += a.stats["bamboo#0"][0] * db_to_linear(a.LOOP3D["bamboo"][0]) * w.bamboo
	s += a.stats["rain_roof#0"][0] * db_to_linear(a.LOOP3D["rain_roof"][0]) * rain
	return s


# Loop seams: the jump from the last frame to the first should be no bigger
# than an ordinary step inside the loop.
func _seams(a) -> void:
	for n in a.sounds:
		var w: AudioStreamWAV = a.sounds[n][0]
		if w.loop_mode == AudioStreamWAV.LOOP_DISABLED:
			continue
		var d: PackedByteArray = w.data
		var ch := 2 if w.stereo else 1
		var frames := d.size() / (2 * ch)
		var seam := 0.0
		var typical := 0.0
		for c in ch:
			var first := d.decode_s16(c * 2) / 32767.0
			var last := d.decode_s16(((frames - 1) * ch + c) * 2) / 32767.0
			seam = maxf(seam, absf(first - last))
			var acc := 0.0
			for i in range(1, frames, 97):
				acc += absf(d.decode_s16((i * ch + c) * 2) - d.decode_s16(((i - 1) * ch + c) * 2)) / 32767.0
			typical = maxf(typical, acc / (frames / 97.0))
		print("seam %-14s jump %.4f  typical step %.4f  %s" % [n, seam, typical, "OK" if seam <= typical * 4.0 + 0.002 else "CLICK?"])
