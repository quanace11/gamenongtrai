# Procedural sound: every effect is synthesised once at start-up into an
# AudioStreamWAV, so the game ships without audio assets.
extends Node

const RATE := 22050

var sounds := {} # name -> Array[AudioStreamWAV] (variants)
var players: Array[AudioStreamPlayer] = []
var next_player := 0
var rain_player: AudioStreamPlayer
var wind_player: AudioStreamPlayer


func _ready() -> void:
	for i in 14:
		var p := AudioStreamPlayer.new()
		add_child(p)
		players.append(p)
	_build()
	rain_player = _loop_player(_noise(2.0, "hp", 1200.0, 1200.0, 0.7, 0.5, 0.0, true))
	wind_player = _loop_player(_noise(3.0, "lp", 350.0, 350.0, 1.5, 0.7, 0.0, true))


func play(name: String, volume_db := 0.0, pitch := 1.0) -> void:
	if not sounds.has(name):
		return
	var variants: Array = sounds[name]
	var p := players[next_player]
	next_player = (next_player + 1) % players.size()
	p.stream = variants[randi() % variants.size()]
	p.volume_db = volume_db
	p.pitch_scale = pitch
	p.play()


func set_rain(level: float) -> void:
	_set_loop(rain_player, level * 0.8)


func set_wind(level: float) -> void:
	_set_loop(wind_player, level)


func _set_loop(p: AudioStreamPlayer, level: float) -> void:
	if level < 0.01:
		if p.playing:
			p.stop()
		return
	p.volume_db = linear_to_db(level)
	if not p.playing:
		p.play()


func _loop_player(buf: PackedFloat32Array) -> AudioStreamPlayer:
	var w := _wav(buf)
	w.loop_mode = AudioStreamWAV.LOOP_FORWARD
	w.loop_begin = 0
	w.loop_end = buf.size()
	var p := AudioStreamPlayer.new()
	p.stream = w
	add_child(p)
	return p


# ---------------------------------------------------------------- synthesis

func _env(i: int, n: int, gain: float, attack: float) -> float:
	var t := float(i) / RATE
	var dur := float(n) / RATE
	if t < attack:
		return gain * t / attack
	return gain * pow(0.0005, (t - attack) / maxf(dur - attack, 0.001))


# Filtered white noise. kind: "lp", "hp", "bp". Frequency sweeps exponentially f0 -> f1.
func _noise(dur: float, kind: String, f0: float, f1: float, q: float, gain: float, attack: float, flat := false) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var x1 := 0.0
	var x2 := 0.0
	var y1 := 0.0
	var y2 := 0.0
	var b0 := 0.0
	var b1 := 0.0
	var b2 := 0.0
	var a1 := 0.0
	var a2 := 0.0
	for i in n:
		if i % 64 == 0:
			var f: float = f0 * pow(f1 / f0, float(i) / n)
			var w0 := TAU * minf(f, RATE * 0.45) / RATE
			var cw := cos(w0)
			var alpha := sin(w0) / (2.0 * q)
			var a0 := 1.0 + alpha
			match kind:
				"lp":
					b0 = (1.0 - cw) / 2.0; b1 = 1.0 - cw; b2 = b0
				"hp":
					b0 = (1.0 + cw) / 2.0; b1 = -(1.0 + cw); b2 = b0
				_:
					b0 = alpha; b1 = 0.0; b2 = -alpha
			b0 /= a0; b1 /= a0; b2 /= a0
			a1 = -2.0 * cw / a0
			a2 = (1.0 - alpha) / a0
		var x := randf() * 2.0 - 1.0
		var y := b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
		x2 = x1; x1 = x; y2 = y1; y1 = y
		out[i] = y * (gain if flat else _env(i, n, gain, attack))
	return out


func _tone(dur: float, f0: float, f1: float, wave: String, gain: float, attack := 0.01) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var ph := 0.0
	for i in n:
		var f: float = f0 * pow(f1 / f0, float(i) / n)
		ph = fmod(ph + f / RATE, 1.0)
		var v: float
		match wave:
			"square":
				v = 1.0 if ph < 0.5 else -1.0
			"saw":
				v = ph * 2.0 - 1.0
			"tri":
				v = 4.0 * absf(ph - 0.5) - 1.0
			_:
				v = sin(ph * TAU)
		out[i] = v * _env(i, n, gain, attack)
	return out


# Mix b into a starting at `at` seconds, growing a as needed.
func _mix(a: PackedFloat32Array, b: PackedFloat32Array, at := 0.0) -> PackedFloat32Array:
	var off := int(at * RATE)
	if a.size() < off + b.size():
		a.resize(off + b.size())
	for i in b.size():
		a[off + i] += b[i]
	return a


func _wav(buf: PackedFloat32Array) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(buf.size() * 2)
	for i in buf.size():
		data.encode_s16(i * 2, int(clampf(buf[i], -1.0, 1.0) * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = data
	return w


func _add(name: String, buf: PackedFloat32Array) -> void:
	if not sounds.has(name):
		sounds[name] = []
	sounds[name].append(_wav(buf))


func _build() -> void:
	# cuốc: đất khô (cứng) và đất ướt (bùn)
	var hard := _mix(_noise(0.22, "lp", 700, 700, 0.7, 0.9, 0.003), _tone(0.18, 120, 40, "sine", 0.5))
	_add("thud_hard", hard)
	var soft := _mix(_noise(0.22, "lp", 350, 350, 0.7, 0.8, 0.003), _tone(0.18, 80, 40, "sine", 0.4))
	_add("thud_soft", _mix(soft, _noise(0.35, "bp", 250, 800, 4.0, 0.5, 0.01), 0.05))
	for i in 3:
		_add("squelch", _noise(0.28, "bp", 260 + i * 40, 900, 5.0, 0.6, 0.01))
	_add("step", _noise(0.07, "lp", 700, 700, 0.7, 0.25, 0.003))
	_add("swish", _mix(_noise(0.2, "hp", 2500, 7000, 0.7, 0.5, 0.04), _noise(0.12, "bp", 4000, 4000, 2.0, 0.3, 0.01), 0.12))
	_add("splash", _noise(0.5, "bp", 900, 250, 1.0, 0.6, 0.005))
	_add("thunder", _mix(_noise(3.5, "lp", 260, 50, 0.7, 1.0, 0.05), _tone(2.5, 55, 30, "sine", 0.5)))
	_add("thunder_far", _noise(4.0, "lp", 150, 45, 0.7, 0.7, 0.4))
	for i in 3:
		var f := 470.0 + i * 50.0
		_add("quack", _mix(_tone(0.12, f, f * 0.7, "saw", 0.12), _tone(0.12, f, f * 0.7, "saw", 0.12), 0.16))
	_add("whistle", _mix(_tone(0.3, 1700, 2700, "sine", 0.25), _tone(0.35, 2700, 1600, "sine", 0.25), 0.38))
	_add("beat", _tone(0.06, 660, 660, "tri", 0.25, 0.002))
	_add("beat_accent", _tone(0.06, 990, 990, "tri", 0.25, 0.002))
	_add("good", _tone(0.12, 880, 1320, "tri", 0.2))
	_add("miss", _tone(0.15, 220, 160, "square", 0.08))
	var thresh := _tone(0.15, 140, 60, "sine", 0.6)
	for i in 6:
		thresh = _mix(thresh, _noise(0.05, "hp", 3000 + randf() * 3000, 4000, 0.7, 0.2, 0.002), 0.05 + i * 0.03)
	_add("thresh", thresh)
	_add("rake", _noise(0.3, "bp", 2200, 1600, 0.8, 0.35, 0.05))
	for i in 4:
		var f := 260.0 + randf() * 260.0
		_add("frog", _mix(_tone(0.06, f, f * 0.75, "square", 0.05), _tone(0.07, f * 1.1, f * 0.8, "square", 0.05), 0.09))
	var cricket := PackedFloat32Array()
	for i in 3:
		cricket = _mix(cricket, _tone(0.03, 4200, 4200, "sine", 0.04, 0.003), i * 0.05)
	_add("cricket", cricket)
	for i in 3:
		var f := 2200.0 + randf() * 1500.0
		_add("bird", _mix(_tone(0.08, f, f * 1.4, "sine", 0.06), _tone(0.1, f * 1.2, f * 0.9, "sine", 0.06), 0.12))
	_add("pickup", _tone(0.08, 600, 900, "tri", 0.18))
	_add("chop", _mix(_noise(0.08, "bp", 1500, 1500, 2.0, 0.6, 0.002), _tone(0.08, 200, 90, "sine", 0.35)))
	_add("tarp", _noise(0.6, "bp", 1800, 600, 0.6, 0.45, 0.1))
	_add("oink", _tone(0.2, 220, 140, "saw", 0.12))
