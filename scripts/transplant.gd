# Mini-game "Cấy lúa": a rhythm track that follows the backward steps of
# transplanting. Space = lùi 1 bước, A / S / D = cắm trái / giữa / phải.
extends Node3D

const L = preload("res://scripts/layout.gd")
const LANES := 8
const LANE_W := 2.0
const ROW_STEP := 0.6
const ROWS := 26
const SPREAD := [-0.6, 0.0, 0.6]
const BEAT := 0.5 # seconds per beat
const KEYS := [KEY_SPACE, KEY_A, KEY_S, KEY_D]
const LABELS := ["Lùi", "Trái", "Giữa", "Phải"]
const KEYCAPS := ["Space", "A", "S", "D"]
const COLORS := [Color("6a5a8a"), Color("3f8a5a"), Color("3f7a8a"), Color("8a7a3f")]
const PERFECT := 0.07
const GOOD := 0.16
const WINDOW := 0.26

signal finished(aesthetic: float, planted: int, neighbours: bool)

var field
var player
var tools
var hud
var audio

var active := false
var waiting := false
var lane := 0
var t := 0.0
var next := 0
var notes: Array = [] # [{time, k, row, done, node}]
var row_z := 0.0
var errors: Array = [] # lateral error (m) of each clump the player planted; null = missed
var _guides: MeshInstance3D


func setup(f, p, tl, h, a) -> void:
	field = f
	player = p
	tools = tl
	hud = h
	audio = a
	# faint guide lines under the mud (vạch căn hàng)
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	for l in LANES:
		for s in SPREAD:
			var x: float = L.FIELD.x0 + LANE_W * (l + 0.5) + s
			im.surface_add_vertex(Vector3(x, L.FIELD.y + 0.03, L.FIELD.z0 + 0.3))
			im.surface_add_vertex(Vector3(x, L.FIELD.y + 0.03, L.FIELD.z1 - 0.3))
	im.surface_end()
	_guides = MeshInstance3D.new()
	_guides.mesh = im
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(0.96, 0.9, 0.72, 0.35)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_guides.material_override = m
	_guides.visible = false
	add_child(_guides)


func start() -> void:
	active = true
	lane = 0
	_guides.visible = true
	hud.rhythm.visible = true
	player.frozen = true
	tools.bo_ma.visible = true
	_begin_lane()


func lane_x(l: int) -> float:
	return L.FIELD.x0 + LANE_W * (l + 0.5)


func _begin_lane() -> void:
	waiting = false
	row_z = L.FIELD.z1 - 0.5 + ROW_STEP # the first "lùi" brings us to row 0
	t = -1.5 # count-in
	next = 0
	notes.clear()
	for r in ROWS:
		for k in 4:
			notes.append({"time": (r * 4 + k) * BEAT, "k": k, "row": r, "done": false,
				"node": hud.make_note(KEYCAPS[k], LABELS[k], COLORS[k])})
	_place_camera(true)
	hud.set_text(hud.rhythm_info, "rinfo", "[center]Làn %d/%d — bấm theo nhịp khi nốt chạm vạch vàng[/center]" % [lane + 1, LANES])


func _place_camera(snap: bool) -> void:
	player.pos.x = lane_x(lane)
	player.pos.z = row_z - 0.75
	if snap:
		player.yaw = PI # facing +z, stepping backwards toward -z
		player.pitch = -0.75


func _judge(note: Dictionary, dt) -> void:
	note.done = true
	var grade := "miss"
	if dt != null:
		var ad := absf(dt)
		grade = "perfect" if ad < PERFECT else ("good" if ad < GOOD else "poor")
	var node: ColorRect = note.node
	match grade:
		"perfect", "good":
			node.modulate.a = 0.0
		"poor":
			node.modulate.a = 0.35
		_:
			node.color = Color("8a3f3f")
			node.modulate.a = 0.5
	audio.play("miss" if grade == "miss" else "good", -6.0)
	if note.k == 0:
		# step back; a sloppy step makes uneven row spacing
		var drift: float = {"miss": 0.25, "poor": 0.12, "good": 0.04, "perfect": 0.0}[grade]
		row_z -= ROW_STEP + drift * (1.0 if randf() < 0.5 else -1.0)
		_place_camera(false)
		if grade != "miss":
			audio.play("squelch", -6.0)
		return
	if grade == "miss":
		errors.append(null)
		return
	var sgn := signf(dt) if dt != 0.0 else 1.0
	var err: float = randfn(0.0, 0.02) if grade == "perfect" else sgn * (absf(dt) * 1.1 + randf() * 0.05)
	var x: float = lane_x(lane) + SPREAD[note.k - 1] + err
	var z: float = row_z + randfn(0.0, 0.02 if grade == "perfect" else 0.06)
	if z > L.FIELD.z0 + 0.2:
		field.plant(x, z)
	errors.append(err)
	tools.swing(0.2, 0.5, "scoop", func(): pass)


# Returns true when the key was consumed.
func key(code: int) -> bool:
	if not active:
		return false
	if waiting:
		if code == KEY_SPACE and lane < LANES - 1:
			lane += 1
			_clear_notes()
			_begin_lane()
		elif code == KEY_ENTER or code == KEY_KP_ENTER:
			finish(true)
		return true
	var k := KEYS.find(code)
	if k < 0:
		return false
	if next >= notes.size():
		return true
	var note: Dictionary = notes[next]
	var dt: float = t - note.time
	if note.k == k and absf(dt) < WINDOW:
		_judge(note, dt)
		next += 1
	else:
		audio.play("miss", -10.0)
	return true


func _clear_notes() -> void:
	for n in notes:
		n.node.queue_free()
	notes.clear()


func stats() -> Vector2:
	var sq := 0.0
	var planted := 0
	for e in errors:
		if e != null:
			sq += e * e
			planted += 1
	var rms := sqrt(sq / planted) if planted > 0 else 0.2
	var miss_rate := 1.0 - float(planted) / errors.size() if errors.size() > 0 else 1.0
	return Vector2(rms, miss_rate)


func step(dt: float) -> void:
	if not active or waiting:
		return
	var prev := t
	t += dt
	var b0 := int(floor(prev / BEAT))
	var b1 := int(floor(t / BEAT))
	if b1 > b0 and b1 >= 0 and b1 < ROWS * 4:
		audio.play("beat_accent" if b1 % 4 == 0 else "beat", -8.0)
	while next < notes.size() and t - notes[next].time > WINDOW:
		_judge(notes[next], null)
		next += 1
	var hit_x := 90.0
	var px_per_sec := 220.0
	var w: float = hud.rhythm_track.size.x
	for n in notes:
		var x: float = hit_x + (n.time - t) * px_per_sec
		var node: ColorRect = n.node
		node.visible = x > -60.0 and x < w + 60.0
		node.position = Vector2(x - 26.0, 8.0)
	var s := stats()
	hud.set_text(hud.rhythm_score, "rscore", "Độ thẳng hàng: %d%% · Bỏ sót: %d%%" % [int(clampf(1.0 - s.x / 0.25, 0, 1) * 100), int(s.y * 100)])
	if next >= notes.size():
		waiting = true
		if lane < LANES - 1:
			hud.set_text(hud.rhythm_info, "rinfo", "[center]Xong làn %d! [b]Space[/b]: cấy tiếp làn sau · [b]Enter[/b]: nhờ hàng xóm \"đổi công\" cấy nốt[/center]" % (lane + 1))
		else:
			hud.set_text(hud.rhythm_info, "rinfo", "[center]Cấy xong cả thửa! Bấm [b]Enter[/b].[/center]")


func finish(neighbours: bool) -> void:
	var s := stats()
	if neighbours:
		# Đổi công: the village finishes the remaining lanes at the player's pace.
		var sigma := maxf(0.03, s.x)
		for l in range(lane + 1, LANES):
			for r in ROWS:
				for sp in SPREAD:
					if randf() < s.y * 0.5:
						continue
					var z: float = L.FIELD.z1 - 0.5 - r * ROW_STEP + randfn(0.0, sigma * 0.5)
					if z < L.FIELD.z0 + 0.2:
						continue
					field.plant(lane_x(l) + sp + randfn(0.0, sigma), z)
	var expected := LANES * ROWS * 3
	var fill := minf(1.0, float(field.planted_count()) / expected)
	var straight := clampf(1.0 - s.x / 0.25, 0.0, 1.0)
	field.aesthetic = clampf(straight * 0.75 + fill * 0.25, 0.0, 1.0)
	active = false
	_clear_notes()
	hud.rhythm.visible = false
	_guides.visible = false
	player.frozen = false
	player.pitch = -0.2
	tools.bo_ma.visible = false
	finished.emit(field.aesthetic, field.planted_count(), neighbours)
