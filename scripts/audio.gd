# Procedural sound of a Red River delta village. Every sound is synthesised
# in GDScript, so the game ships without audio assets:
#   - one-shot effects for tools and the body (2D, played by `play`),
#   - stereo ambience beds that cross-fade with the in-game hour
#     (birds, cicadas, crickets, frogs, rain, wind),
#   - positional loops and calls in the world (canal, sluice gate, buffalo,
#     pig, ducks, bamboo, rain on the tile roof, distant roosters, dogs,
#     motorbikes, children and the commune loudspeaker).
# Synthesis runs on a worker thread and is cached to user:// so later
# start-ups only read the PCM back. Bump CACHE_VERSION after changing a sound.
extends Node

const L = preload("res://scripts/layout.gd")

const RATE := 44100
const CACHE_VERSION := 3
const CACHE_DIR := "user://audio_cache"
const ONE_SHOT_PEAK := 0.7 # -3 dBFS ceiling for any one-shot
const BED_RMS := 0.1 # -20 dBFS: beds are levelled, then mixed by BED_DB
const BED_PEAK := 0.5 # -6 dBFS ceiling for a bed
const EVENT_PEAK := 0.5 # animal and village calls are levelled to -6 dBFS

# Mix level of each bed at weight 1, in dB. The weights come from `weights`.
const BED_DB := {
	"air": -30.0, "birds": -14.0, "cicadas": -12.0, "crickets": -18.0,
	"frogs": -15.0, "rain_field": -10.0, "wind": -14.0,
}
# Positional loops: [dB at weight 1, unit_size (m at which they play at dB)].
const LOOP3D := {
	"canal": [-12.0, 3.0], "gate_flow": [-10.0, 2.5], "drain_flow": [-11.0, 2.0],
	"buffalo_breath": [-16.0, 1.6], "bamboo": [-9.0, 7.0], "rain_roof": [-7.0, 5.0],
	"moto": [-6.0, 14.0],
}
# Where the bamboo hedge rings the farm (see world.gd _plants groves).
const GROVE := {"x0": -33.0, "x1": 33.0, "z0": -38.0, "z1": 24.0}
const HOUSE := {"x0": -5.6, "x1": 5.6, "z0": -29.4, "z1": -21.6}

var sounds := {} # name -> Array[AudioStreamWAV] (variants)
var stats := {} # "name#i" -> [peak, rms] of the synthesised buffer
var synth_ms := {} # name -> ms spent synthesising (cache misses only)
var loaded := false
var players: Array[AudioStreamPlayer] = []
var next_player := 0
var players3d: Array[AudioStreamPlayer3D] = []
var next_player3d := 0
var beds := {} # name -> {"p": AudioStreamPlayer, "lvl": float}
var loops3d := {} # name -> {"p": AudioStreamPlayer3D, "lvl": float}
var main: Node
var listener := Vector3.ZERO
var rain := 0.0 # smoothed 0..1
var rain_target := 0.0
var storm_wind := 0.0
var storm_wind_target := 0.0
var wetness := 0.0 # ground and leaves still wet after rain: frogs keep calling
var timers := {}
var moto := {"t": -1.0}
var _results: Array = []
var _mutex := Mutex.new()
var _thread: Thread
var _abort := false
var _srng := RandomNumberGenerator.new() # synthesis thread only
var _rng := RandomNumberGenerator.new() # main thread
var _jobs: Array = []
var _world_ready := false


func _ready() -> void:
	_rng.randomize()
	_setup_buses()
	for i in 14:
		var p := AudioStreamPlayer.new()
		p.bus = "Sfx"
		add_child(p)
		players.append(p)
	for i in 16:
		var p := AudioStreamPlayer3D.new()
		p.bus = "World"
		p.max_distance = 320.0
		p.attenuation_filter_cutoff_hz = 7000.0
		add_child(p)
		players3d.append(p)
	for b in BED_DB:
		var p := AudioStreamPlayer.new()
		p.bus = "Amb"
		add_child(p)
		beds[b] = {"p": p, "lvl": 0.0}
	_define_jobs()
	_thread = Thread.new()
	_thread.start(_synth_all)


func _exit_tree() -> void:
	_abort = true
	if _thread != null and _thread.is_started():
		_thread.wait_to_finish()


func _process(_dt: float) -> void:
	if loaded:
		return
	_install_results()
	if not _thread.is_alive():
		_thread.wait_to_finish()
		_install_results()
		loaded = true
		set_process(false)


# Ambience goes to its own bus so a settings slider can turn it down, and a
# limiter on the master keeps the sum of beds, loops and effects below 0 dBFS.
func _setup_buses() -> void:
	for b in ["Amb", "World", "Sfx"]:
		if AudioServer.get_bus_index(b) == -1:
			AudioServer.add_bus()
			var i := AudioServer.bus_count - 1
			AudioServer.set_bus_name(i, b)
			AudioServer.set_bus_send(i, "Master")
	var m := AudioServer.get_bus_index("Master")
	for i in AudioServer.get_bus_effect_count(m):
		if AudioServer.get_bus_effect(m, i) is AudioEffectHardLimiter:
			return
	var lim := AudioEffectHardLimiter.new()
	lim.ceiling_db = -1.0
	AudioServer.add_bus_effect(m, lim)


# ------------------------------------------------------------------ playback

func play(name: String, volume_db := 0.0, pitch := 1.0) -> void:
	# Footsteps pick their sound from the ground under the player.
	if name == "step" or name == "squelch":
		var s := surface_at(listener.x, listener.z, name == "squelch")
		name = "step_" + s
		volume_db += {"dry": 0.0, "grass": -1.0, "brick": -2.0, "mud": 0.0, "wade": 1.0}[s]
		pitch *= _rng.randf_range(0.93, 1.07)
	elif name == "oink" and _node("pig") != null:
		play_at("pig", _node("pig").global_position + Vector3(0.7, 0.5, 0), volume_db, pitch, 3.0)
		return
	if not sounds.has(name):
		return
	var variants: Array = sounds[name]
	var p := players[next_player]
	next_player = (next_player + 1) % players.size()
	p.stream = variants[_rng.randi() % variants.size()]
	p.volume_db = volume_db
	p.pitch_scale = pitch
	p.play()


# A one-shot heard from a place in the world. unit_size is the distance in
# metres at which it plays at volume_db; it falls off as 1/distance beyond.
func play_at(name: String, pos: Vector3, volume_db := 0.0, pitch := 1.0, unit_size := 4.0) -> void:
	if not sounds.has(name):
		return
	var variants: Array = sounds[name]
	var p := players3d[next_player3d]
	next_player3d = (next_player3d + 1) % players3d.size()
	p.stream = variants[_rng.randi() % variants.size()]
	p.global_position = pos
	p.volume_db = volume_db
	p.unit_size = unit_size
	p.pitch_scale = pitch
	p.play()


func set_rain(level: float) -> void:
	rain_target = clampf(level, 0.0, 1.0)


func set_wind(level: float) -> void:
	storm_wind_target = clampf(level, 0.0, 1.0)


# Ground type for footsteps at (x, z). wet: the caller already knows the feet
# are in mud or water.
func surface_at(x: float, z: float, wet := false) -> String:
	if (x > L.CANAL.x0 and x < L.CANAL.x1) or L.in_pond(x, z):
		return "wade"
	var field = main.get("field") if main != null else null
	if L.in_field(x, z):
		if field != null and "water" in field and field.water > 3.0:
			return "wade"
		if wet:
			return "mud"
		if field != null and "till" in field and field.till[field.cell_at(x, z)] > 0.5:
			return "mud"
		return "dry"
	if wet:
		return "mud"
	if L.in_field(x, z, L.FIELD.bund):
		return "dry"
	if L.in_court(x, z) or _in_rect(x, z, HOUSE, 1.5):
		return "brick"
	return "grass"


# ------------------------------------------------------------------- update

# Called every simulation step by main.gd.
func update(dt: float, m: Node) -> void:
	main = m
	if not _world_ready:
		_attach_world()
	var cam = m.get("camera")
	if cam != null:
		listener = cam.global_position
	var h: float = m.hour()
	rain = move_toward(rain, rain_target, dt / 3.0)
	storm_wind = move_toward(storm_wind, storm_wind_target, dt / 2.0)
	# 4 game minutes pass per real second: drying out takes about 2 game hours.
	wetness = maxf(rain, wetness - dt / 30.0)
	var w := weights(h, rain, wetness, storm_wind)
	for b in beds:
		var bed: Dictionary = beds[b]
		bed.lvl = move_toward(bed.lvl, w.get(b, 0.0), dt / 2.5)
		_drive(bed.p, b, bed.lvl, BED_DB[b])
	_update_loops(dt, h, w)
	_update_events(dt, h, w)


# Weight 0..1 of every bed and event family at hour h. Pure, so the test
# script can print a table for a whole day.
static func weights(h: float, rain_v := 0.0, wet := 0.0, wind_v := 0.0) -> Dictionary:
	var dry := 1.0 - rain_v
	var w := {}
	w.air = 1.0
	w.birds = (_win(h, 4.6, 5.6, 9.0, 11.5) + 0.3 * _win(h, 11.0, 12.0, 15.0, 16.0)
		+ 0.75 * _win(h, 15.5, 16.5, 17.8, 19.0)) * (0.15 + 0.85 * dry)
	w.cicadas = _win(h, 9.5, 11.3, 15.5, 17.6) * dry * dry
	w.crickets = _win(h, 17.8, 19.3, 4.0, 5.4) * (0.5 + 0.5 * dry)
	w.frogs = clampf(_win(h, 17.6, 18.9, 3.6, 5.2) * (0.7 + 0.5 * wet) + 0.55 * wet * (1.0 - _win(h, 17.6, 18.9, 3.6, 5.2)), 0.0, 1.0)
	w.rain_field = rain_v
	w.wind = clampf(0.25 * _win(h, 9.0, 12.0, 16.0, 19.0) + 0.12 + wind_v, 0.0, 1.0)
	w.bamboo = clampf(0.3 + 0.25 * _win(h, 9.0, 12.0, 16.0, 19.0) + wind_v, 0.0, 1.0)
	w.rooster = maxf(_win(h, 4.2, 4.8, 6.6, 7.6), 0.12 * _win(h, 7.6, 8.0, 17.0, 18.0) + 0.35 * _win(h, 0.8, 1.0, 1.4, 1.6) + 0.35 * _win(h, 2.9, 3.1, 3.4, 3.6))
	w.dog = 0.15 + 0.35 * _win(h, 18.5, 19.5, 22.5, 23.5)
	w.koel = 0.6 * _win(h, 5.2, 6.0, 9.5, 10.5) * dry
	w.village = (0.5 * _win(h, 6.0, 7.0, 10.5, 11.5) + 0.6 * _win(h, 15.0, 16.0, 18.5, 19.5)) * dry
	w.moto = 0.08 + 0.6 * _win(h, 5.5, 6.5, 20.0, 21.5)
	w.loudspeaker = _win(h, 5.95, 6.0, 6.7, 6.75) + _win(h, 16.95, 17.0, 17.7, 17.75)
	w.gecko = 0.7 * _win(h, 18.6, 19.5, 3.5, 4.5)
	w.animals = 0.25 + 0.75 * _win(h, 5.0, 6.0, 18.5, 19.5)
	return w


# Trapezoid window over the 24 h clock: rises a->b, holds b->c, falls c->d.
# A window may wrap past midnight (c or d smaller than a).
static func _win(h: float, a: float, b: float, c: float, d: float) -> float:
	if b < a: b += 24.0
	if c < b: c += 24.0
	if d < c: d += 24.0
	var best := 0.0
	for x in [h - 24.0, h, h + 24.0]:
		var v := 0.0
		if x >= a and x <= d:
			if x < b:
				v = smoothstep(a, b, x)
			elif x <= c:
				v = 1.0
			else:
				v = 1.0 - smoothstep(c, d, x)
		best = maxf(best, v)
	return best


func _drive(p: Node, name: String, lvl: float, db: float) -> void:
	if not sounds.has(name):
		return
	if lvl < 0.005:
		if p.playing:
			p.stop()
		return
	p.volume_db = db + linear_to_db(lvl)
	if not p.playing:
		var variants: Array = sounds[name]
		p.stream = variants[0]
		# Start beds at a random point so the loop seam lands differently each time.
		p.play(_rng.randf() * p.stream.get_length())


func _node(key: String) -> Node3D:
	if main == null:
		return null
	var world = main.get("world")
	if world == null or not world is Dictionary or not world.has(key):
		return null
	var n = world[key]
	return n if n is Node3D and is_instance_valid(n) else null


func _attach_world() -> void:
	if main.get("world") == null:
		return
	_world_ready = true
	for n in LOOP3D:
		var p := AudioStreamPlayer3D.new()
		p.bus = "World"
		p.unit_size = LOOP3D[n][1]
		p.max_distance = 400.0 if n == "moto" else 120.0
		p.attenuation_filter_cutoff_hz = 7000.0
		if n == "moto":
			p.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_PHYSICS_STEP
		add_child(p)
		loops3d[n] = {"p": p, "lvl": 0.0}


func _update_loops(dt: float, h: float, w: Dictionary) -> void:
	if not _world_ready:
		return
	var field = main.get("field")
	var canal_full: bool = main.get("canal_full") == true
	var water: float = field.water if field != null and "water" in field else 0.0
	var gate_open: bool = field != null and field.get("gate_open") == true
	var drain_open: bool = field != null and field.get("drain_open") == true
	var lx := listener.x
	var lz := listener.z
	var target := {
		"canal": 1.0 if canal_full else 0.25,
		"gate_flow": 1.0 if gate_open and canal_full else 0.0,
		"drain_flow": clampf(water / 2.0, 0.0, 1.0) if drain_open else 0.0,
		"buffalo_breath": 1.0 if _node("buffalo") != null else 0.0,
		"bamboo": w.bamboo,
		"rain_roof": rain,
		"moto": 0.0,
	}
	var pos := {
		"canal": Vector3((L.CANAL.x0 + L.CANAL.x1) / 2.0, -0.5, clampf(lz, -34.0, 30.0)),
		"gate_flow": Vector3(L.GATE.x, 0.1, L.GATE.y),
		"drain_flow": Vector3(L.DRAIN.x, 0.0, L.DRAIN.y),
		"bamboo": _nearest_on_ring(lx, lz),
		"rain_roof": Vector3(clampf(lx, HOUSE.x0, HOUSE.x1), 3.0, clampf(lz, HOUSE.z0, HOUSE.z1)),
	}
	var buff := _node("buffalo")
	if buff != null:
		pos["buffalo_breath"] = buff.global_transform * Vector3(0, 1.0, 1.2)
	# A motorbike passing on the village road beyond the paddies.
	if moto.t >= 0.0:
		moto.t += dt
		var k: float = moto.t / moto.dur
		if k >= 1.0:
			moto.t = -1.0
		else:
			pos["moto"] = moto.a.lerp(moto.b, k)
			target["moto"] = 1.0
			loops3d.moto.lvl = 1.0
			loops3d.moto.p.pitch_scale = moto.pitch * (1.0 + 0.05 * sin(moto.t * 0.7))
	for n in loops3d:
		var lp: Dictionary = loops3d[n]
		if n != "moto":
			lp.lvl = move_toward(lp.lvl, target[n], dt / 1.5)
		else:
			lp.lvl = target[n]
		if pos.has(n):
			lp.p.global_position = pos[n]
		_drive(lp.p, n, lp.lvl, LOOP3D[n][0])


func _nearest_on_ring(x: float, z: float) -> Vector3:
	var cx := clampf(x, GROVE.x0, GROVE.x1)
	var cz := clampf(z, GROVE.z0, GROVE.z1)
	# Inside the ring: snap to the closest edge.
	var d := [cx - GROVE.x0, GROVE.x1 - cx, cz - GROVE.z0, GROVE.z1 - cz]
	var i: int = d.find(d.min())
	match i:
		0: cx = GROVE.x0
		1: cx = GROVE.x1
		2: cz = GROVE.z0
		_: cz = GROVE.z1
	return Vector3(cx, 5.0, cz)


func _in_rect(x: float, z: float, r: Dictionary, m := 0.0) -> bool:
	return x > r.x0 - m and x < r.x1 + m and z > r.z0 - m and z < r.z1 + m


# ------------------------------------------------------------------- events

# [weight key, min s, max s] between tries; a try fires with probability = weight.
const EVENTS := {
	"rooster": ["rooster", 3.0, 9.0], "dog": ["dog", 9.0, 26.0], "koel": ["koel", 10.0, 24.0],
	"bird_near": ["birds", 1.2, 4.5], "gecko": ["gecko", 14.0, 34.0], "moto": ["moto", 18.0, 45.0],
	"kids": ["village", 14.0, 34.0], "loudspeaker": ["loudspeaker", 1.0, 1.0],
	"pig": ["animals", 4.0, 13.0], "buffalo_call": ["animals", 28.0, 70.0],
	"duck": ["animals", 1.5, 6.0], "frog_near": ["frogs", 0.6, 2.4],
	"cricket_near": ["crickets", 1.5, 5.0],
}


func _update_events(dt: float, h: float, w: Dictionary) -> void:
	if not _world_ready:
		return
	for e in EVENTS:
		var cfg: Array = EVENTS[e]
		var t: float = timers.get(e, _rng.randf_range(0.0, cfg[2]))
		t -= dt
		if t <= 0.0:
			t = _rng.randf_range(cfg[1], cfg[2])
			if _rng.randf() < w.get(cfg[0], 0.0):
				t = maxf(t, _fire(e))
		timers[e] = t


func _around(dmin: float, dmax: float, y := 1.5) -> Vector3:
	var a := _rng.randf() * TAU
	var d := _rng.randf_range(dmin, dmax)
	return Vector3(listener.x + cos(a) * d, y, listener.z + sin(a) * d)


# Plays event e; returns the minimum seconds before it may fire again.
func _fire(e: String) -> float:
	match e:
		"rooster":
			# A neighbour's rooster, often answered by another across the hamlet.
			play_at("rooster", _around(30, 110, 1.5), _rng.randf_range(-4, 2), _rng.randf_range(0.92, 1.08), 12.0)
			if _rng.randf() < 0.5:
				get_tree().create_timer(_rng.randf_range(1.8, 3.5)).timeout.connect(
					func(): play_at("rooster", _around(60, 160, 1.5), _rng.randf_range(-8, -2), _rng.randf_range(0.9, 1.1), 12.0))
		"dog":
			play_at("dog", _around(50, 150, 0.6), _rng.randf_range(-6, 0), _rng.randf_range(0.9, 1.1), 12.0)
		"koel":
			play_at("koel", _around(35, 90, 9.0), -4.0, _rng.randf_range(0.95, 1.05), 12.0)
			return 8.0
		"bird_near":
			play_at("bird", _around(8, 30, _rng.randf_range(3, 9)), _rng.randf_range(-10, -4), _rng.randf_range(0.9, 1.15), 4.0)
		"gecko":
			var p := Vector3(_rng.randf_range(HOUSE.x0, HOUSE.x1), 2.8, HOUSE.z0 if _rng.randf() < 0.5 else HOUSE.z1)
			if _rng.randf() < 0.35:
				p = _nearest_on_ring(listener.x, listener.z)
			play_at("gecko", p, -2.0, _rng.randf_range(0.95, 1.05), 6.0)
			return 9.0
		"kids":
			play_at("kids", _around(45, 90, 1.2), -6.0, _rng.randf_range(0.95, 1.05), 12.0)
			return 7.0
		"loudspeaker":
			# The commune loudspeaker reads the news at 6:00 and 17:00.
			play_at("loudspeaker", Vector3(-60, 8, -140), 2.0, 1.0, 40.0)
			return 13.0
		"moto":
			if moto.t < 0.0 and loops3d.has("moto"):
				var z := -95.0 if _rng.randf() < 0.6 else 75.0
				var dir := 1.0 if _rng.randf() < 0.5 else -1.0
				var speed := _rng.randf_range(8.0, 13.0)
				moto.a = Vector3(-170.0 * dir, 1.0, z)
				moto.b = Vector3(170.0 * dir, 1.0, z)
				moto.dur = 340.0 / speed
				moto.t = 0.0
				moto.pitch = speed / 11.0
		"pig":
			var pig := _node("pig")
			if pig != null:
				play_at("pig", pig.global_position + Vector3(0.7, 0.5, 0), -4.0, _rng.randf_range(0.9, 1.1), 3.0)
		"buffalo_call":
			var b := _node("buffalo")
			if b != null:
				play_at("buffalo_call", b.global_transform * Vector3(0, 1.1, 1.4), -2.0, _rng.randf_range(0.95, 1.05), 6.0)
		"duck":
			var ducks = main.get("ducks")
			if ducks != null and "list" in ducks and ducks.list.size() > 0:
				var d: Dictionary = ducks.list[_rng.randi() % ducks.list.size()]
				var kind := "duck_chatter" if _rng.randf() < 0.6 else "quack"
				play_at(kind, d.pos + Vector3(0, 0.3, 0), -6.0, _rng.randf_range(0.92, 1.08), 3.0)
		"frog_near":
			# Single frogs close by in the paddy, canal and pond.
			var spots := [Vector3(_rng.randf_range(L.FIELD.x0, L.FIELD.x1), 0.0, _rng.randf_range(L.FIELD.z0, L.FIELD.z1)),
				Vector3(-11.0, -0.5, _rng.randf_range(-30, 25)), Vector3(L.POND.x, 0, L.POND.z)]
			var sp: Vector3 = spots[_rng.randi() % spots.size()]
			if sp.distance_to(listener) < 45.0:
				play_at("frog", sp, _rng.randf_range(-10, -3), _rng.randf_range(0.92, 1.08), 3.0)
		"cricket_near":
			play_at("cricket", _around(3, 12, 0.1), _rng.randf_range(-14, -8), _rng.randf_range(0.95, 1.05), 2.0)
	return 0.0


# --------------------------------------------------------- jobs and caching

# norm: level a call to EVENT_PEAK so quiet and loud animals start equal and
# their loudness is set where they are played.
func _job(name: String, fn: Callable, stereo := false, loop := false, norm := false) -> void:
	_jobs.append({"name": name, "fn": fn, "stereo": stereo, "loop": loop, "norm": norm,
		"idx": _jobs.filter(func(j): return j.name == name).size()})


func _define_jobs() -> void:
	# Tools and body (short, needed first).
	_job("thud_hard", func(): return _mix(_noise(0.22, "lp", 700, 700, 0.7, 0.9, 0.003), _tone(0.18, 120, 40, "sine", 0.5)))
	_job("thud_soft", func(): return _mix(_mix(_noise(0.22, "lp", 350, 350, 0.7, 0.8, 0.003), _tone(0.18, 80, 40, "sine", 0.4)), _noise(0.35, "bp", 250, 800, 4.0, 0.5, 0.01), 0.05))
	for i in 4:
		_job("step_dry", _step_dry)
		_job("step_grass", _step_grass)
		_job("step_brick", _step_brick)
		_job("step_mud", _step_mud)
		_job("step_wade", _step_wade)
	_job("swish", func(): return _mix(_noise(0.2, "hp", 2500, 7000, 0.7, 0.5, 0.04), _noise(0.12, "bp", 4000, 4000, 2.0, 0.3, 0.01), 0.12))
	_job("splash", func(): return _mix(_noise(0.5, "bp", 900, 250, 1.0, 0.6, 0.005), _bubbles(0.5, 30, 500, 1800, 0.25)))
	_job("pickup", func(): return _tone(0.08, 600, 900, "tri", 0.18))
	_job("chop", func(): return _mix(_noise(0.08, "bp", 1500, 1500, 2.0, 0.6, 0.002), _tone(0.08, 200, 90, "sine", 0.35)))
	_job("rake", func(): return _noise(0.3, "bp", 2200, 1600, 0.8, 0.35, 0.05))
	_job("tarp", func(): return _noise(0.6, "bp", 1800, 600, 0.6, 0.45, 0.1))
	_job("thresh", _thresh)
	_job("whistle", func(): return _mix(_tone(0.3, 1700, 2700, "sine", 0.25), _tone(0.35, 2700, 1600, "sine", 0.25), 0.38))
	_job("beat", func(): return _tone(0.06, 660, 660, "tri", 0.25, 0.002))
	_job("beat_accent", func(): return _tone(0.06, 990, 990, "tri", 0.25, 0.002))
	_job("good", func(): return _tone(0.12, 880, 1320, "tri", 0.2))
	_job("miss", func(): return _tone(0.15, 220, 160, "square", 0.08))
	_job("thunder", func(): return _mix(_noise(3.5, "lp", 260, 50, 0.7, 1.0, 0.05), _tone(2.5, 55, 30, "sine", 0.5)))
	_job("thunder_far", func(): return _noise(4.0, "lp", 150, 45, 0.7, 0.7, 0.4))
	# Animals (positional calls).
	for i in 3:
		_job("quack", _quack_series, false, false, true)
		_job("duck_chatter", _duck_chatter, false, false, true)
		_job("pig", _pig_grunts, false, false, true)
	for i in 2:
		_job("buffalo_call", _buffalo_call, false, false, true)
		_job("rooster", _rooster, false, false, true)
		_job("dog", _dog, false, false, true)
	for i in 4:
		_job("frog", _frog_call.bind(i % 4), false, false, true)
		_job("bird", _bird_call, false, false, true)
	_job("cricket", func(): var b := PackedFloat32Array(); b.resize(_n(1.2)); _cricket_chirps(b, 0, 4400.0 + _srng.randf() * 500.0, 1.0, 3); return b)
	_job("koel", _koel, false, false, true)
	_job("gecko", _gecko, false, false, true)
	# Loops: ambience beds (stereo) and positional loops (mono).
	_job("air", _bed_air, true, true)
	_job("birds", _bed_birds, true, true)
	_job("cicadas", _bed_cicadas, true, true)
	_job("crickets", _bed_crickets, true, true)
	_job("frogs", _bed_frogs, true, true)
	_job("rain_field", _bed_rain_field, true, true)
	_job("wind", _bed_wind, true, true)
	_job("canal", _loop_canal, false, true)
	_job("gate_flow", _loop_pour.bind(1.0), false, true)
	_job("drain_flow", _loop_pour.bind(0.6), false, true)
	_job("buffalo_breath", _loop_buffalo, false, true)
	_job("bamboo", _loop_bamboo, false, true)
	_job("rain_roof", _loop_rain_roof, false, true)
	_job("moto", _loop_moto, false, true)
	# Distant village (long, needed last).
	for i in 2:
		_job("kids", _kids, false, false, true)
	_job("loudspeaker", _loudspeaker, false, false, true)


func _synth_all() -> void:
	var dir := "%s/v%d" % [CACHE_DIR, CACHE_VERSION]
	DirAccess.make_dir_recursive_absolute(dir)
	for j in _jobs:
		if _abort:
			return
		var path := "%s/%s_%d.bin" % [dir, j.name, j.idx]
		var r := _load_cached(path)
		if r.is_empty():
			var t0 := Time.get_ticks_msec()
			_srng.seed = hash("%s#%d#%d" % [j.name, j.idx, CACHE_VERSION])
			r = _render(j)
			synth_ms[j.name] = synth_ms.get(j.name, 0) + Time.get_ticks_msec() - t0
			_save_cached(path, r)
		r.name = j.name
		r.idx = j.idx
		_mutex.lock()
		_results.append(r)
		_mutex.unlock()


func _render(j: Dictionary) -> Dictionary:
	var a: PackedFloat32Array = j.fn.call()
	var b := PackedFloat32Array()
	if j.stereo:
		b = j.fn.call()
		var n := mini(a.size(), b.size())
		a.resize(n)
		b.resize(n)
		# A little crosstalk so the two sides read as one place, not two.
		for i in n:
			var l := a[i]
			a[i] = l + 0.25 * b[i]
			b[i] = b[i] + 0.25 * l
	var peak := 0.0
	var sq := 0.0
	for x in a:
		peak = maxf(peak, absf(x))
		sq += x * x
	for x in b:
		peak = maxf(peak, absf(x))
		sq += x * x
	var rms := sqrt(sq / maxf(1.0, a.size() + b.size()))
	var g := 1.0
	if j.loop:
		g = BED_RMS / maxf(rms, 1e-6)
		g = minf(g, BED_PEAK / maxf(peak, 1e-6))
	elif j.norm:
		g = EVENT_PEAK / maxf(peak, 1e-6)
	elif peak > ONE_SHOT_PEAK:
		g = ONE_SHOT_PEAK / peak
	var data := PackedByteArray()
	var frames := a.size()
	if j.stereo:
		data.resize(frames * 4)
		for i in frames:
			data.encode_s16(i * 4, int(clampf(a[i] * g, -1.0, 1.0) * 32767.0))
			data.encode_s16(i * 4 + 2, int(clampf(b[i] * g, -1.0, 1.0) * 32767.0))
	else:
		data.resize(frames * 2)
		for i in frames:
			data.encode_s16(i * 2, int(clampf(a[i] * g, -1.0, 1.0) * 32767.0))
	return {"stereo": j.stereo, "loop": j.loop, "frames": frames, "peak": peak * g, "rms": rms * g, "data": data}


func _save_cached(path: String, r: Dictionary) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return
	f.store_8(1 if r.stereo else 0)
	f.store_8(1 if r.loop else 0)
	f.store_32(r.frames)
	f.store_float(r.peak)
	f.store_float(r.rms)
	f.store_buffer(r.data)


func _load_cached(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null or f.get_length() < 14:
		return {}
	var r := {"stereo": f.get_8() == 1, "loop": f.get_8() == 1, "frames": f.get_32(), "peak": f.get_float(), "rms": f.get_float()}
	r.data = f.get_buffer(f.get_length() - 14)
	if r.data.size() != r.frames * (4 if r.stereo else 2):
		return {}
	return r


func _install_results() -> void:
	_mutex.lock()
	var rs := _results.duplicate()
	_results.clear()
	_mutex.unlock()
	for r in rs:
		var w := AudioStreamWAV.new()
		w.format = AudioStreamWAV.FORMAT_16_BITS
		w.mix_rate = RATE
		w.stereo = r.stereo
		w.data = r.data
		if r.loop:
			w.loop_mode = AudioStreamWAV.LOOP_FORWARD
			w.loop_begin = 0
			w.loop_end = r.frames
		if not sounds.has(r.name):
			sounds[r.name] = []
		sounds[r.name].append(w)
		stats["%s#%d" % [r.name, r.idx]] = [r.peak, r.rms]


# --------------------------------------------------------- synthesis basics

func _n(dur: float) -> int:
	return int(dur * RATE)


func _white() -> float:
	return _srng.randf() * 2.0 - 1.0


func _env(i: int, n: int, gain: float, attack: float) -> float:
	var t := float(i) / RATE
	var dur := float(n) / RATE
	if t < attack:
		return gain * t / attack
	return gain * pow(0.0005, (t - attack) / maxf(dur - attack, 0.001))


func _coefs(kind: String, f: float, q: float) -> PackedFloat32Array:
	var w0 := TAU * clampf(f, 10.0, RATE * 0.45) / RATE
	var cw := cos(w0)
	var alpha := sin(w0) / (2.0 * q)
	var a0 := 1.0 + alpha
	var b0: float
	var b1: float
	var b2: float
	match kind:
		"lp":
			b0 = (1.0 - cw) / 2.0; b1 = 1.0 - cw; b2 = b0
		"hp":
			b0 = (1.0 + cw) / 2.0; b1 = -(1.0 + cw); b2 = b0
		_:
			b0 = alpha; b1 = 0.0; b2 = -alpha
	return PackedFloat32Array([b0 / a0, b1 / a0, b2 / a0, -2.0 * cw / a0, (1.0 - alpha) / a0])


# Fixed biquad over a whole buffer (returns a new buffer).
func _filt(buf: PackedFloat32Array, kind: String, f: float, q := 0.707) -> PackedFloat32Array:
	var c := _coefs(kind, f, q)
	var b0 := c[0]; var b1 := c[1]; var b2 := c[2]; var a1 := c[3]; var a2 := c[4]
	var x1 := 0.0; var x2 := 0.0; var y1 := 0.0; var y2 := 0.0
	var out := PackedFloat32Array()
	out.resize(buf.size())
	for i in buf.size():
		var x := buf[i]
		var y := b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
		x2 = x1; x1 = x; y2 = y1; y1 = y
		out[i] = y
	return out


# Biquad over a loop: the filter is first run over the loop's tail so its
# state at sample 0 matches the end, and the seam stays click-free.
func _filt_loop(buf: PackedFloat32Array, kind: String, f: float, q := 0.707) -> PackedFloat32Array:
	var warm := mini(buf.size(), _n(0.5))
	var tmp := buf.slice(buf.size() - warm)
	tmp.append_array(buf)
	return _filt(tmp, kind, f, q).slice(warm)


# Filtered white noise. kind: "lp", "hp", "bp". Frequency sweeps exponentially f0 -> f1.
func _noise(dur: float, kind: String, f0: float, f1: float, q: float, gain: float, attack: float, flat := false) -> PackedFloat32Array:
	var n := _n(dur)
	var out := PackedFloat32Array()
	out.resize(n)
	var x1 := 0.0; var x2 := 0.0; var y1 := 0.0; var y2 := 0.0
	var c := PackedFloat32Array()
	for i in n:
		if i % 64 == 0:
			c = _coefs(kind, f0 * pow(f1 / f0, float(i) / n), q)
		var x := _white()
		var y := c[0] * x + c[1] * x1 + c[2] * x2 - c[3] * y1 - c[4] * y2
		x2 = x1; x1 = x; y2 = y1; y1 = y
		out[i] = y * (gain if flat else _env(i, n, gain, attack))
	return out


func _tone(dur: float, f0: float, f1: float, wave: String, gain: float, attack := 0.01) -> PackedFloat32Array:
	var n := _n(dur)
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
func _mix(a: PackedFloat32Array, b: PackedFloat32Array, at := 0.0, gain := 1.0) -> PackedFloat32Array:
	var off := int(at * RATE)
	if a.size() < off + b.size():
		a.resize(off + b.size())
	for i in b.size():
		a[off + i] += b[i] * gain
	return a


# Add src into a loop buffer at sample `at`, wrapping round the end so that
# events placed near the seam continue at the start (seamless loops).
func _wrap_add(dst: PackedFloat32Array, src: PackedFloat32Array, at: int, gain := 1.0) -> void:
	var n := dst.size()
	for i in src.size():
		dst[(at + i) % n] += src[i] * gain


# Turn a buffer of n + fade samples into a click-free loop of n samples by
# cross-fading its tail into its head (equal power: the noise is uncorrelated).
func _loopify(buf: PackedFloat32Array, n: int) -> PackedFloat32Array:
	var f := buf.size() - n
	var out := buf.slice(0, n)
	for i in f:
		var k := float(i) / f
		out[i] = buf[i] * sin(k * PI * 0.5) + buf[n + i] * cos(k * PI * 0.5)
	return out


func _fade(buf: PackedFloat32Array, attack: float, release: float) -> PackedFloat32Array:
	var na := maxi(1, _n(attack))
	var nr := maxi(1, _n(release))
	var n := buf.size()
	for i in mini(na, n):
		buf[i] *= float(i) / na
	for i in mini(nr, n):
		buf[n - 1 - i] *= float(i) / nr
	return buf


func _gain(buf: PackedFloat32Array, g: float) -> PackedFloat32Array:
	for i in buf.size():
		buf[i] *= g
	return buf


func _peak(buf: PackedFloat32Array) -> float:
	var p := 0.0
	for x in buf:
		p = maxf(p, absf(x))
	return p


func _norm(buf: PackedFloat32Array, to := 0.5) -> PackedFloat32Array:
	return _gain(buf, to / maxf(_peak(buf), 1e-6))


# Piecewise-linear curve through [[x 0..1, value], ...].
func _curve(pts: Array, x: float) -> float:
	if x <= pts[0][0]:
		return pts[0][1]
	for k in range(1, pts.size()):
		if x <= pts[k][0]:
			var a: Array = pts[k - 1]
			var b: Array = pts[k]
			return lerpf(a[1], b[1], (x - a[0]) / maxf(b[0] - a[0], 1e-6))
	return pts[-1][1]


# Voiced source for animal and human calls: a sawtooth whose pitch follows
# `contour`, with a little jitter, an optional rough flutter (rasp) and breath.
func _src(dur: float, contour: Array, rough := 0.0, rough_hz := 30.0, breath := 0.0) -> PackedFloat32Array:
	var n := _n(dur)
	var out := PackedFloat32Array()
	out.resize(n)
	var ph := 0.0
	var jit := 0.0
	var rph := 0.0
	for i in n:
		if i % 220 == 0:
			jit = _white() * 0.012
		var f := _curve(contour, float(i) / n) * (1.0 + jit)
		ph = fmod(ph + f / RATE, 1.0)
		var v := ph * 2.0 - 1.0
		if rough > 0.0:
			rph = fmod(rph + rough_hz * (1.0 + jit * 4.0) / RATE, 1.0)
			v *= 1.0 - rough * (0.5 + 0.5 * sin(rph * TAU))
		if breath > 0.0:
			v += breath * _white()
		out[i] = v
	return out


# Vocal tract: a sum of band-pass resonances [[hz, q, gain], ...].
func _formants(src: PackedFloat32Array, list: Array) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(src.size())
	for fm in list:
		var y := _filt(src, "bp", fm[0], fm[1])
		for i in y.size():
			out[i] += y[i] * fm[2]
	return out


# A decaying sine ring (wood, ceramic) added into dst at sample `at` (wraps).
func _ring(dst: PackedFloat32Array, at: int, f: float, decay: float, amp: float) -> void:
	var n := dst.size()
	var len := mini(_n(decay * 5.0), n)
	var k := -1.0 / (decay * RATE)
	for i in len:
		dst[(at + i) % n] += amp * sin(TAU * f * i / RATE) * exp(k * i) * minf(1.0, i / 20.0)


# A water bubble: a sine that rises in pitch as it decays (Minnaert resonance).
func _bubble(dst: PackedFloat32Array, at: int, f: float, dur: float, amp: float) -> void:
	var n := dst.size()
	var len := mini(_n(dur), n)
	var ph := 0.0
	for i in len:
		var x := float(i) / len
		ph += f * (1.0 + 1.2 * x) / RATE
		dst[(at + i) % n] += amp * sin(ph * TAU) * pow(1.0 - x, 2.0) * minf(1.0, i / 30.0)


func _bubbles(dur: float, per_s: float, f0: float, f1: float, amp: float) -> PackedFloat32Array:
	var b := PackedFloat32Array()
	b.resize(_n(dur))
	for k in int(dur * per_s):
		_bubble(b, _srng.randi() % b.size(), _srng.randf_range(f0, f1), _srng.randf_range(0.01, 0.04), amp * _srng.randf_range(0.2, 1.0))
	return _fade(b, 0.002, 0.05)


# A slow random swell 0..1 that repeats exactly every n samples.
func _lfo_def(count := 4, kmin := 1, kmax := 7) -> Array:
	var parts := []
	for c in count:
		parts.append([_srng.randi_range(kmin, kmax), _srng.randf() * TAU, _srng.randf_range(0.4, 1.0)])
	return parts


func _lfo(parts: Array, i: int, n: int) -> float:
	var s := 0.0
	var t := 0.0
	for p in parts:
		s += p[2] * sin(TAU * p[0] * float(i) / n + p[1])
		t += p[2]
	return 0.5 + 0.5 * s / t


# ------------------------------------------------------------ footsteps

func _step_dry() -> PackedFloat32Array:
	# Heel thump on packed earth, then a few crumbs of soil.
	var b := _mix(_noise(0.09, "lp", 420, 260, 0.8, 0.8, 0.004), _tone(0.07, 95, 55, "sine", 0.35, 0.003))
	for k in _srng.randi_range(3, 7):
		_mix(b, _noise(0.012, "bp", _srng.randf_range(1800, 4200), 3000, 1.2, _srng.randf_range(0.05, 0.15), 0.001), _srng.randf_range(0.01, 0.09))
	return _fade(b, 0.001, 0.02)


func _step_grass() -> PackedFloat32Array:
	# Blades brushing the shin and a soft pad onto turf.
	var b := _noise(0.22, "bp", _srng.randf_range(2500, 3500), 5500, 0.8, 0.3, 0.05)
	_mix(b, _noise(0.08, "lp", 300, 220, 0.8, 0.5, 0.008), 0.02)
	return _fade(b, 0.002, 0.03)


func _step_brick() -> PackedFloat32Array:
	# Sandal slapping fired-brick pavers: heel tap, then the sole flapping up.
	var b := _noise(0.03, "bp", 2200, 1600, 1.4, 0.9, 0.0008)
	_ring(b, 0, _srng.randf_range(900, 1300), 0.004, 0.2)
	_mix(b, _noise(0.05, "lp", 300, 200, 0.8, 0.4, 0.002))
	_mix(b, _noise(0.025, "bp", 3000, 2400, 1.0, 0.45, 0.001), _srng.randf_range(0.07, 0.1))
	_mix(b, _noise(0.06, "hp", 4000, 4000, 0.7, 0.06, 0.01), 0.02)
	return _fade(b, 0.0005, 0.02)


func _step_mud() -> PackedFloat32Array:
	# Foot pressing into puddled mud, then the suck as it pulls free.
	var b := _noise(0.22, "bp", _srng.randf_range(220, 300), 700, 4.0, 0.6, 0.02)
	_mix(b, _tone(0.12, 110, 60, "sine", 0.3, 0.01))
	_mix(b, _noise(0.12, "bp", 900, 2600, 3.0, 0.35, 0.03), _srng.randf_range(0.17, 0.24))
	var bub := _bubbles(0.35, 25, 300, 900, 0.18)
	_mix(b, bub, 0.05)
	return _fade(b, 0.002, 0.04)


func _step_wade() -> PackedFloat32Array:
	# Shin pushing through ankle-deep water: a slosh and falling droplets.
	var b := _noise(0.4, "bp", 500, 1400, 0.9, 0.55, 0.06)
	_mix(b, _noise(0.25, "lp", 400, 250, 0.7, 0.3, 0.02), 0.05)
	_mix(b, _bubbles(0.45, 40, 600, 2400, 0.22), 0.1)
	return _fade(b, 0.003, 0.08)


func _thresh() -> PackedFloat32Array:
	var b := _tone(0.15, 140, 60, "sine", 0.6)
	for i in 6:
		b = _mix(b, _noise(0.05, "hp", 3000 + _srng.randf() * 3000, 4000, 0.7, 0.2, 0.002), 0.05 + i * 0.03)
	return b


# ------------------------------------------------------------ animals

func _quack1(f: float, dur: float) -> PackedFloat32Array:
	var s := _src(dur, [[0, f * 0.9], [0.25, f * 1.05], [1, f * 0.75]], 0.5, 55.0, 0.15)
	var b := _formants(s, [[1150, 5.0, 1.0], [2100, 6.0, 0.55], [3300, 6.0, 0.2]])
	return _fade(b, 0.012, dur * 0.45)


func _quack_series() -> PackedFloat32Array:
	# The female mallard's descending "quack quack quack".
	var b := PackedFloat32Array()
	var count := _srng.randi_range(1, 5)
	var t := 0.0
	var f := _srng.randf_range(420, 520)
	for k in count:
		_mix(b, _quack1(f, _srng.randf_range(0.13, 0.19)), t, 1.0 - 0.13 * k)
		t += _srng.randf_range(0.2, 0.27)
		f *= 0.96
	return b


func _duck_chatter() -> PackedFloat32Array:
	# Low contented "rab rab" while dabbling.
	var b := PackedFloat32Array()
	var t := 0.0
	for k in _srng.randi_range(2, 6):
		var f := _srng.randf_range(260, 330)
		var d := _srng.randf_range(0.05, 0.09)
		var s := _src(d, [[0, f], [1, f * 0.85]], 0.6, 70.0, 0.25)
		_mix(b, _fade(_formants(s, [[900, 4.0, 1.0], [1700, 5.0, 0.4]]), 0.006, 0.03), t, _srng.randf_range(0.4, 1.0))
		t += _srng.randf_range(0.09, 0.2)
	return b


func _pig_grunts() -> PackedFloat32Array:
	var b := PackedFloat32Array()
	var t := 0.0
	for k in _srng.randi_range(2, 4):
		var f := _srng.randf_range(90, 140)
		var d := _srng.randf_range(0.1, 0.22)
		var s := _src(d, [[0, f * 1.15], [0.4, f], [1, f * 0.8]], 0.8, 28.0, 0.35)
		_mix(b, _fade(_formants(s, [[380, 3.0, 1.0], [1050, 4.0, 0.5], [2400, 5.0, 0.15]]), 0.01, d * 0.5), t, _srng.randf_range(0.6, 1.0))
		t += d + _srng.randf_range(0.06, 0.2)
	return b


func _buffalo_call() -> PackedFloat32Array:
	# A water buffalo's long, low "ọ".
	var d := _srng.randf_range(1.4, 2.0)
	var f := _srng.randf_range(85, 105)
	var s := _src(d, [[0, f], [0.25, f * 1.3], [0.7, f * 1.22], [1, f * 0.8]], 0.25, 22.0, 0.08)
	var b := _formants(s, [[330, 4.0, 1.0], [720, 5.0, 0.5], [1750, 6.0, 0.12]])
	_mix(b, _noise(d, "bp", 500, 300, 1.0, 0.08, 0.3, true))
	return _fade(b, 0.18, 0.5)


func _loop_buffalo() -> PackedFloat32Array:
	# Slow breathing and cud-chewing, 8 s.
	var n := _n(8.0)
	var b := PackedFloat32Array()
	b.resize(n)
	for c in 2:
		var t0 := 0.3 + c * 4.0 + _srng.randf_range(-0.2, 0.2)
		_wrap_add(b, _fade(_noise(1.2, "lp", 480, 320, 0.9, 0.5, 0.15, true), 0.15, 0.8), _n(t0))
		_wrap_add(b, _fade(_noise(1.3, "bp", 900, 700, 0.8, 0.25, 0.3, true), 0.5, 0.5), _n(t0 + 1.8))
	var t := 0.2
	while t < 7.6:
		var chew := _mix(_noise(0.07, "bp", 2200, 1500, 1.2, 0.22, 0.01), _noise(0.06, "lp", 200, 150, 0.8, 0.25, 0.005))
		_wrap_add(b, chew, _n(t), _srng.randf_range(0.5, 1.0))
		t += _srng.randf_range(0.65, 0.8)
	return b


func _rooster() -> PackedFloat32Array:
	# "Ò ó o o": four syllables, the long third one held high and hoarse.
	var d := _srng.randf_range(1.8, 2.3)
	var f := _srng.randf_range(480, 560)
	var s := _src(d, [[0, f], [0.1, f * 1.15], [0.16, f * 1.05], [0.26, f * 1.35], [0.32, f * 1.4],
		[0.7, f * 1.45], [0.8, f * 1.3], [1, f * 0.8]], 0.35, 38.0, 0.12)
	var b := _formants(s, [[1150, 4.0, 1.0], [2400, 5.0, 0.7], [3600, 6.0, 0.25]])
	# Amplitude: separate syllables.
	var gaps := [0.12, 0.2, 0.75]
	for i in b.size():
		var x := float(i) / b.size()
		var a := 1.0
		for gx in gaps:
			a = minf(a, clampf(absf(x - gx) / 0.025, 0.15, 1.0))
		b[i] *= a * (1.0 - 0.4 * x)
	return _fade(b, 0.02, 0.35)


func _dog() -> PackedFloat32Array:
	var b := PackedFloat32Array()
	var t := 0.0
	for k in _srng.randi_range(2, 5):
		var f := _srng.randf_range(420, 560)
		var d := _srng.randf_range(0.11, 0.17)
		var s := _src(d, [[0, f * 1.1], [0.2, f * 1.3], [1, f * 0.7]], 0.5, 45.0, 0.3)
		_mix(b, _fade(_formants(s, [[750, 4.0, 1.0], [1500, 5.0, 0.6], [2700, 5.0, 0.25]]), 0.004, d * 0.6), t, _srng.randf_range(0.7, 1.0))
		t += _srng.randf_range(0.28, 0.5)
	return b


func _koel() -> PackedFloat32Array:
	# Tu hú: "ku-ooo", repeated and rising.
	var b := PackedFloat32Array()
	var f := _srng.randf_range(620, 720)
	var t := 0.0
	for k in _srng.randi_range(4, 7):
		var n1 := _tone(0.16, f, f * 1.05, "sine", 0.5, 0.02)
		var n2 := _tone(0.38, f * 1.32, f * 1.42, "sine", 0.5, 0.03)
		_mix(b, n1, t)
		_mix(b, _mix(n2, _tone(0.38, f * 2.64, f * 2.84, "sine", 0.06, 0.03)), t + 0.2)
		t += _srng.randf_range(0.85, 1.0)
		f *= 1.035
	return b


func _gecko() -> PackedFloat32Array:
	# Tắc kè: a rattle, then "tắc-kè" five to eight times, fading out.
	var b := PackedFloat32Array()
	b.resize(_n(0.5))
	for k in 14:
		_ring(b, _n(0.03 * k), _srng.randf_range(1500, 2000), 0.004, 0.25)
	var t := 0.8
	var reps := _srng.randi_range(5, 8)
	for k in reps:
		var g := 1.0 - 0.07 * k
		var tac := _formants(_src(0.07, [[0, 320], [1, 260]], 0.3, 60.0, 0.4), [[1000, 4.0, 1.0], [2300, 5.0, 0.5]])
		_mix(b, _fade(tac, 0.003, 0.03), t, g)
		var ke := _formants(_src(0.3, [[0, 190], [0.5, 175], [1, 140]], 0.6, 55.0, 0.15), [[650, 4.0, 1.0], [1350, 5.0, 0.5], [2600, 6.0, 0.15]])
		_mix(b, _fade(ke, 0.02, 0.12), t + 0.14, g)
		t += _srng.randf_range(1.0, 1.15)
	return b


# Rice-paddy frogs. kind 0: nhái creaking series, 1: ếch đồng "ộp ộp",
# 2: ễnh ương two-part bleat, 3: tiny Microhyla rasps.
func _frog_call(kind: int) -> PackedFloat32Array:
	var b := PackedFloat32Array()
	match kind:
		0:
			var f := _srng.randf_range(1500, 2400)
			var t := 0.0
			for k in _srng.randi_range(4, 10):
				_mix(b, _pulse_note(_srng.randf_range(0.04, 0.07), _srng.randf_range(90, 140), f, 6.0), t)
				t += _srng.randf_range(0.13, 0.18)
		1:
			var f := _srng.randf_range(230, 300)
			var t := 0.0
			for k in _srng.randi_range(2, 3):
				var s := _src(0.12, [[0, f], [1, f * 0.9]], 0.4, 40.0, 0.05)
				_mix(b, _fade(_formants(s, [[520, 4.0, 1.0], [1150, 5.0, 0.5]]), 0.01, 0.05), t)
				t += 0.24
		2:
			var f := _srng.randf_range(210, 260)
			var s1 := _src(0.3, [[0, f * 1.1], [1, f]], 0.3, 35.0, 0.05)
			var s2 := _src(0.45, [[0, f * 0.85], [1, f * 0.75]], 0.3, 35.0, 0.05)
			_mix(b, _fade(_formants(s1, [[640, 5.0, 1.0], [1250, 6.0, 0.4]]), 0.03, 0.1))
			_mix(b, _fade(_formants(s2, [[480, 5.0, 1.0], [950, 6.0, 0.4]]), 0.04, 0.2), 0.42)
		_:
			for k in _srng.randi_range(2, 4):
				_mix(b, _pulse_note(_srng.randf_range(0.2, 0.4), _srng.randf_range(60, 90), _srng.randf_range(2600, 3400), 8.0), k * 0.55)
	return b


# A pulsed note: clicks at `rate` Hz each ringing a resonance at f (insects, frogs).
func _pulse_note(dur: float, rate: float, f: float, q: float) -> PackedFloat32Array:
	var n := _n(dur)
	var src := PackedFloat32Array()
	src.resize(n + _n(0.02))
	var t := 0.0
	while t < dur:
		var i := _n(t)
		src[i] = sin(PI * t / dur) * _srng.randf_range(0.7, 1.0)
		t += 1.0 / rate
	return _fade(_filt(_filt(src, "bp", f, q), "bp", f, q * 0.5), 0.002, 0.01)


func _bird_call() -> PackedFloat32Array:
	var b := PackedFloat32Array()
	b.resize(_n(1.4))
	_bird_into(b, 0, _srng.randi() % 4, 1.0)
	return _fade(b, 0.001, 0.05)


# One bird phrase into dst at sample `at`. species 0: bulbul (chào mào)
# liquid notes, 1: sparrow chips, 2: magpie-robin (chích chòe) whistle,
# 3: tailorbird "chee-wit" pairs.
func _bird_into(dst: PackedFloat32Array, at: int, species: int, amp: float) -> void:
	var t := 0
	match species:
		0:
			for k in _srng.randi_range(3, 5):
				var d := _srng.randf_range(0.06, 0.14)
				var f := _srng.randf_range(1700, 3000)
				_wrap_add(dst, _tone(d, f, f * _srng.randf_range(0.75, 1.35), "sine", 0.5, 0.012), at + t, amp)
				t += _n(d + _srng.randf_range(0.02, 0.06))
		1:
			var f := _srng.randf_range(3600, 4800)
			for k in _srng.randi_range(2, 6):
				var c := _tone(0.05, f, f * 0.8, "sine", 0.4, 0.004)
				_mix(c, _tone(0.05, f * 2.0, f * 1.6, "sine", 0.08, 0.004))
				_wrap_add(dst, c, at + t, amp * _srng.randf_range(0.7, 1.0))
				t += _n(_srng.randf_range(0.1, 0.16))
		2:
			for k in _srng.randi_range(2, 4):
				var d := _srng.randf_range(0.18, 0.35)
				var f := _srng.randf_range(2000, 3600)
				var w := _tone(d, f, f * _srng.randf_range(0.85, 1.2), "sine", 0.45, 0.03)
				for i in w.size():
					w[i] *= 1.0 + 0.3 * sin(TAU * 26.0 * i / RATE)
				_wrap_add(dst, w, at + t, amp)
				t += _n(d + _srng.randf_range(0.04, 0.12))
		_:
			for k in _srng.randi_range(2, 4):
				var f := _srng.randf_range(3000, 3800)
				_wrap_add(dst, _tone(0.07, f * 0.8, f, "sine", 0.45, 0.006), at + t, amp)
				_wrap_add(dst, _tone(0.09, f * 1.15, f * 0.9, "sine", 0.45, 0.006), at + t + _n(0.1), amp)
				t += _n(_srng.randf_range(0.3, 0.45))


func _cricket_chirps(dst: PackedFloat32Array, at: int, f: float, amp: float, chirps: int) -> void:
	# Field cricket: chirps of 3-4 pulses at ~30 pulses/s.
	var n := dst.size()
	var t := 0.0
	for c in chirps:
		for p in _srng.randi_range(3, 4):
			var i0 := at + _n(t + p * 0.032)
			var len := _n(0.018)
			for i in len:
				dst[(i0 + i) % n] += amp * 0.4 * sin(TAU * f * i / RATE) * sin(PI * i / len)
		t += _srng.randf_range(0.32, 0.42)


# ------------------------------------------------------------ ambience beds

func _bed_air() -> PackedFloat32Array:
	# Open-country room tone: distant traffic-free rumble and leaf hiss.
	var n := _n(10.0)
	var tot := n + _n(1.0)
	var raw := PackedFloat32Array()
	raw.resize(tot)
	var br := 0.0
	for i in tot:
		br = br * 0.995 + _white() * 0.05
		raw[i] = br
	var lo := _filt(raw, "lp", 250.0)
	var hi := _filt(_noise(float(tot) / RATE, "bp", 3000, 3000, 0.5, 0.05, 0.0, true), "lp", 6000.0)
	for i in tot:
		lo[i] += hi[i] * 0.4
	return _loopify(lo, n)


func _bed_birds() -> PackedFloat32Array:
	var n := _n(16.0)
	var b := PackedFloat32Array()
	b.resize(n)
	for k in 70:
		var far := _srng.randf()
		_bird_into(b, _srng.randi() % n, _srng.randi() % 4, lerpf(0.9, 0.12, far))
	# Distant birds lose their top end.
	return _filt_loop(b, "lp", 6500.0)


func _bed_cicadas() -> PackedFloat32Array:
	# Ve sầu: several males, each a shrill pulsed whine swelling over seconds.
	var n := _n(16.0)
	var out := PackedFloat32Array()
	out.resize(n)
	for v in 6:
		var f := _srng.randf_range(4300, 6800)
		var rate := _srng.randf_range(140, 230)
		var amp := _srng.randf_range(0.25, 1.0)
		var src := PackedFloat32Array()
		src.resize(n)
		# Phrases: swell, hold, fade, rest, laid round the loop.
		var phrases := []
		var t := _srng.randf_range(0.0, 4.0)
		while t < 16.0:
			var up := _srng.randf_range(1.0, 2.0)
			var hold := _srng.randf_range(2.0, 5.0)
			var down := _srng.randf_range(1.0, 2.0)
			phrases.append([t, up, hold, down])
			t += up + hold + down + _srng.randf_range(0.5, 3.0)
		var step := 1.0 / rate
		var k := 0.0
		while k < 16.0:
			var e := 0.0
			for p in phrases:
				for x in [k, k + 16.0]:
					var r: float = x - p[0]
					if r > 0.0 and r < p[1] + p[2] + p[3]:
						var ev := 1.0
						if r < p[1]:
							ev = r / p[1]
						elif r > p[1] + p[2]:
							ev = 1.0 - (r - p[1] - p[2]) / p[3]
						e = maxf(e, ev)
			if e > 0.0:
				src[_n(k) % n] += e * _srng.randf_range(0.7, 1.0)
			k += step
		var y := _filt_loop(_filt_loop(src, "bp", f, 6.0), "bp", f * 1.02, 3.0)
		for i in n:
			out[i] += y[i] * amp
	return out


func _bed_crickets() -> PackedFloat32Array:
	var n := _n(12.0)
	var b := PackedFloat32Array()
	b.resize(n)
	for v in 9:
		var f := _srng.randf_range(3900, 5000)
		var amp := _srng.randf_range(0.15, 1.0)
		var t := _srng.randf_range(0.0, 1.0)
		var at := _n(t)
		_cricket_chirps(b, at, f, amp, int(12.0 / 0.4))
	# Dế trũi: a mole cricket's unbroken low trill.
	var f2 := _srng.randf_range(2600, 3000)
	for i in n:
		var tt := float(i) / RATE
		b[i] += 0.12 * sin(TAU * f2 * tt) * maxf(0.0, sin(TAU * 60.0 * tt))
	return b


func _bed_frogs() -> PackedFloat32Array:
	var n := _n(16.0)
	var b := PackedFloat32Array()
	b.resize(n)
	var counts := [40, 14, 5, 18]
	for kind in 4:
		for k in counts[kind]:
			var c := _frog_call(kind)
			var far := _srng.randf()
			if far > 0.5:
				c = _filt(c, "lp", 2500.0)
			_wrap_add(b, c, _srng.randi() % n, lerpf(1.0, 0.15, far))
	return b


func _bed_rain_field() -> PackedFloat32Array:
	# Rain on standing water and rice leaves: hiss, patter and tiny bubbles.
	var n := _n(8.0)
	var tot := n + _n(0.8)
	var hiss := _filt(_noise(float(tot) / RATE, "bp", 3500, 3500, 0.5, 0.35, 0.0, true), "hp", 900.0)
	var rumble := _noise(float(tot) / RATE, "lp", 300, 300, 0.7, 0.25, 0.0, true)
	for i in tot:
		hiss[i] += rumble[i]
	var b := _loopify(hiss, n)
	for k in 1800:
		_bubble(b, _srng.randi() % n, _srng.randf_range(1400, 5000), _srng.randf_range(0.006, 0.02), _srng.randf_range(0.02, 0.18))
	for k in 260:
		_bubble(b, _srng.randi() % n, _srng.randf_range(500, 1200), _srng.randf_range(0.02, 0.04), _srng.randf_range(0.05, 0.25))
	return b


func _bed_wind() -> PackedFloat32Array:
	# Gusts: brown noise through a low-pass that opens as each gust builds.
	var n := _n(16.0)
	var tot := n + _n(1.5)
	var lfo := _lfo_def(4, 1, 6)
	var out := PackedFloat32Array()
	out.resize(tot)
	var br := 0.0
	var x1 := 0.0; var x2 := 0.0; var y1 := 0.0; var y2 := 0.0
	var c := PackedFloat32Array()
	var g := 0.0
	for i in tot:
		if i % 64 == 0:
			g = _lfo(lfo, i % n, n)
			c = _coefs("lp", 120.0 + 700.0 * g * g, 0.9)
		br = br * 0.99 + _white() * 0.1
		var y := c[0] * br + c[1] * x1 + c[2] * x2 - c[3] * y1 - c[4] * y2
		x2 = x1; x1 = br; y2 = y1; y1 = y
		out[i] = y * (0.25 + g * g)
	return _loopify(out, n)


# ------------------------------------------------------------ positional loops

func _loop_canal() -> PackedFloat32Array:
	# Slow water in the irrigation ditch: soft murmur and occasional gurgles.
	var n := _n(10.0)
	var tot := n + _n(0.8)
	var b := _loopify(_noise(float(tot) / RATE, "lp", 500, 500, 0.7, 0.15, 0.0, true), n)
	for k in 320:
		_bubble(b, _srng.randi() % n, _srng.randf_range(250, 900), _srng.randf_range(0.02, 0.06), _srng.randf_range(0.04, 0.22))
	return b


func _loop_pour(strength: float) -> PackedFloat32Array:
	# Water spilling through the sluice into the paddy.
	var n := _n(8.0)
	var tot := n + _n(0.8)
	var lfo := _lfo_def(5, 8, 40)
	var raw := _noise(float(tot) / RATE, "bp", 1100, 1100, 0.6, 0.4, 0.0, true)
	for i in tot:
		raw[i] *= 0.6 + 0.4 * _lfo(lfo, i % n, n)
	var b := _loopify(raw, n)
	for k in int(1100 * strength):
		_bubble(b, _srng.randi() % n, _srng.randf_range(400, 2200), _srng.randf_range(0.01, 0.04), _srng.randf_range(0.05, 0.3))
	return b


func _loop_bamboo() -> PackedFloat32Array:
	# Lũy tre in the wind: leaf rustle in gusts, culms creaking and knocking.
	var n := _n(14.0)
	var tot := n + _n(1.0)
	var lfo := _lfo_def(4, 1, 7)
	var flutter := _lfo_def(5, 60, 160)
	var raw := _noise(float(tot) / RATE, "bp", 5000, 5000, 0.6, 0.5, 0.0, true)
	for i in tot:
		var g := _lfo(lfo, i % n, n)
		raw[i] *= g * g * (0.6 + 0.4 * _lfo(flutter, i % n, n))
	var b := _loopify(_filt(raw, "lp", 9000.0), n)
	# Creaks: stick-slip clicks ringing a culm.
	for k in 5:
		var f := _srng.randf_range(650, 1300)
		var at := _srng.randi() % n
		var t := 0.0
		var dur := _srng.randf_range(0.3, 0.8)
		while t < dur:
			_ring(b, at + _n(t), f * (1.0 + 0.1 * t / dur), 0.006, 0.12 * sin(PI * t / dur))
			t += 1.0 / _srng.randf_range(35, 80)
	# Knocks: hollow "tốc" of culms striking each other.
	for k in 9:
		var at := _srng.randi() % n
		var f := _srng.randf_range(380, 650)
		_ring(b, at, f, 0.03, 0.35)
		_ring(b, at, f * 2.7, 0.01, 0.12)
		if _srng.randf() < 0.4:
			_ring(b, at + _n(0.12), f * 1.05, 0.025, 0.2)
	return b


func _loop_rain_roof() -> PackedFloat32Array:
	# Rain on the red tile roof: hard ticks, eave drips into puddles, gutters.
	var n := _n(8.0)
	var tot := n + _n(0.8)
	var gutter := _noise(float(tot) / RATE, "bp", 1500, 1500, 1.0, 0.18, 0.0, true)
	var lfo := _lfo_def(5, 20, 70)
	for i in tot:
		gutter[i] *= 0.5 + 0.5 * _lfo(lfo, i % n, n)
	var b := _loopify(gutter, n)
	var tick := _noise(0.004, "bp", 3000, 3000, 1.2, 1.0, 0.0005)
	for k in 4200:
		var at := _srng.randi() % n
		var a := _srng.randf_range(0.04, 0.3)
		_wrap_add(b, tick, at, a)
		_ring(b, at, _srng.randf_range(1300, 2300), 0.0025, a * 0.6)
	for k in 70:
		var at := _srng.randi() % n
		_bubble(b, at, _srng.randf_range(600, 1100), _srng.randf_range(0.03, 0.06), _srng.randf_range(0.2, 0.5))
		_wrap_add(b, _noise(0.05, "hp", 2000, 2000, 0.7, 0.15, 0.001), at)
	return b


func _loop_moto() -> PackedFloat32Array:
	# Single-cylinder four-stroke at ~4500 rpm: one firing every 1/38 s.
	# Exactly 76 firings so the loop closes on a cycle.
	var fire := 38.0
	var n := int(round(76.0 / fire * RATE))
	var b := PackedFloat32Array()
	b.resize(n)
	var pulse := _fade(_noise(0.012, "lp", 900, 400, 0.7, 1.0, 0.0008), 0.0005, 0.004)
	for k in 76:
		_wrap_add(b, pulse, int(k * n / 76.0), _srng.randf_range(0.75, 1.0))
	var body := _filt(b, "bp", 160.0, 1.5)
	var muf := _filt(b, "lp", 1100.0)
	var mech := _loopify(_noise(float(n + 2000) / RATE, "bp", 2600, 2600, 1.0, 0.04, 0.0, true), n)
	for i in n:
		body[i] = body[i] * 1.2 + muf[i] * 0.6 + mech[i]
	return body


# ------------------------------------------------------------ village voices

# Syllables of tonal speech: Vietnamese tones as pitch contours over a base f0.
const TONES := [
	[[0, 1.0], [1, 1.0]], # ngang
	[[0, 0.92], [1, 0.78]], # huyền
	[[0, 1.0], [1, 1.3]], # sắc
	[[0, 0.95], [0.5, 0.8], [1, 0.95]], # hỏi
	[[0, 1.0], [0.45, 0.9], [0.55, 1.15], [1, 1.35]], # ngã
	[[0, 0.9], [1, 0.7]], # nặng
]
const VOWELS := [[800, 1300], [500, 1900], [320, 2400], [500, 900], [350, 850], [520, 1250]]


func _speech(dur: float, f0: float, scale: float, breath: float) -> PackedFloat32Array:
	var b := PackedFloat32Array()
	b.resize(_n(dur))
	var t := 0.0
	while t < dur - 0.3:
		var words := _srng.randi_range(2, 7)
		for w in words:
			var d := _srng.randf_range(0.11, 0.24)
			var tone: Array = TONES[_srng.randi() % TONES.size()]
			var cont := []
			for p in tone:
				cont.append([p[0], p[1] * f0 * _srng.randf_range(0.95, 1.05)])
			var v: Array = VOWELS[_srng.randi() % VOWELS.size()]
			var s := _src(d, cont, 0.1, 30.0, breath)
			var syl := _formants(s, [[v[0] * scale, 5.0, 1.0], [v[1] * scale, 6.0, 0.6], [3000 * scale, 6.0, 0.15]])
			# Consonant onset.
			_mix(syl, _noise(0.02, "hp", 2500, 2500, 0.7, 0.15, 0.002))
			_mix(b, _fade(syl, 0.015, 0.04), t)
			t += d + _srng.randf_range(0.02, 0.07)
			if t > dur - 0.3:
				break
		t += _srng.randf_range(0.25, 0.6)
	b.resize(_n(dur))
	return b


func _kids() -> PackedFloat32Array:
	# Children playing in a neighbour's yard: chatter, a shout and laughter.
	var b := PackedFloat32Array()
	for v in 3:
		_mix(b, _speech(5.0, _srng.randf_range(290, 360), 1.25, 0.08), _srng.randf_range(0.0, 1.0), _srng.randf_range(0.5, 1.0))
	var t := _srng.randf_range(1.0, 3.5)
	for k in 5:
		var s := _src(0.1, [[0, 470], [1, 430]], 0.0, 30.0, 0.35)
		_mix(b, _fade(_formants(s, [[1000, 4.0, 1.0], [1800, 5.0, 0.5]]), 0.01, 0.05), t + k * 0.14, 0.9)
	b = _filt(b, "lp", 3000.0)
	return _fade(_echo(b, [[0.18, 0.25]]), 0.2, 0.6)


func _loudspeaker():
	# Loa phát thanh xã: a jingle, then a reader's voice through horn speakers
	# on poles across the village, each echoing the next.
	var b := PackedFloat32Array()
	var notes := [392.0, 523.3, 659.3, 784.0, 659.3, 784.0]
	for k in notes.size():
		var nt := _tone(0.24, notes[k], notes[k], "tri", 0.4, 0.01)
		_mix(nt, _tone(0.24, notes[k] * 2.0, notes[k] * 2.0, "sine", 0.1, 0.01))
		_mix(b, nt, k * 0.26)
	_mix(b, _speech(11.0, 215.0, 1.08, 0.04), 1.9, 0.9)
	# Cheap horn speaker: band-limited and overdriven.
	b = _filt(_filt(b, "hp", 450.0), "lp", 3200.0)
	for i in b.size():
		b[i] = tanh(b[i] * 3.0)
	b = _echo(b, [[0.33, 0.45], [0.71, 0.3], [1.12, 0.18]])
	return _fade(_filt(b, "lp", 2200.0), 0.05, 0.8)


func _echo(b: PackedFloat32Array, taps: Array) -> PackedFloat32Array:
	var extra := 0
	for tp in taps:
		extra = maxi(extra, _n(tp[0]))
	var out := b.duplicate()
	out.resize(b.size() + extra)
	for tp in taps:
		var o := _n(tp[0])
		for i in b.size():
			out[i + o] += b[i] * tp[1]
	return out
