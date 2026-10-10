# Draws the rice of the paddy. Every gameplay clump of field.gd (0.6 m
# apart) is shown as sub x sub real hills 0.6/sub m apart (3 x 3 on High =
# 20 cm, the spacing Vietnamese farmers use), each inheriting the clump's
# row error. The field is cut into 2 m chunks; each chunk holds MultiMeshes
# for three levels of detail switched by visibility range with a dithered
# fade, so near hills are full 3D and the far paddy costs ~50 triangles a
# hill. Gameplay data stays in field.gd; this only reads it.
extends Node3D

const L = preload("res://scripts/layout.gd")
const R = preload("res://scripts/rice_hill.gd")
const F = preload("res://scripts/flora.gd")
const RICE = preload("res://shaders/rice.gdshader")
const PANICLE = preload("res://shaders/rice_panicle.gdshader")
const CHUNK := 2.0
const NC := 8 # chunks per side
const VARIANTS := [2, 2, 1] # meshes per level of detail
# lod 0 ends, lod 1 ends (metres). Kept short: with 3 x 3 hills per clump
# a ripe paddy holds ~5,600 hills, and every lod-0 hill (~2.2 k triangles)
# is drawn in the depth prepass, the colour pass and the shadow cascades.
const BASE_RANGES := [2.5, 8.0]
# Dithered fade-out width of lod 0 and lod 1 (metres either side of the end).
const MARGINS := [1.0, 2.0]

var sub := 3
var ranges: Array = BASE_RANGES.duplicate()
var _stage := -1.0
var _meshes := [] # [lod][variant]
var _stubble := [] # [lod]
var _leaf_mat: ShaderMaterial
var _pan_mat: ShaderMaterial
var _stub_mat: ShaderMaterial
var _chunks := {} # Vector2i -> {"sig": String, "mm": [MultiMeshInstance3D x 8]}
var _last := [] # last update() arguments, to refill on a quality change


func _ready() -> void:
	add_to_group("quality")
	var nz := F.wind_noise()
	_leaf_mat = ShaderMaterial.new()
	_leaf_mat.shader = RICE
	_pan_mat = ShaderMaterial.new()
	_pan_mat.shader = PANICLE
	_pan_mat.set_shader_parameter("grain_tex", R.grain_texture())
	_stub_mat = ShaderMaterial.new()
	_stub_mat.shader = RICE
	_stub_mat.set_shader_parameter("stubble", 1.0)
	_stub_mat.set_shader_parameter("ripe", 1.0)
	_stub_mat.set_shader_parameter("stage", 1.0)
	_stub_mat.set_shader_parameter("plant_height", 0.2)
	for m in [_leaf_mat, _pan_mat, _stub_mat]:
		m.set_shader_parameter("noise", nz)
	for lod in 2:
		var sm := R.stubble(900 + lod, lod)
		sm.surface_set_material(0, _stub_mat)
		_stubble.append(sm)


# growth_day 0..8 to the generator's stage: day 2 is still young seedlings,
# day 4 full tillering, day 5 heading, day 8 ripe.
static func stage_of(day: int) -> float:
	var curve := [0.0, 0.04, 0.09, 0.24, 0.44, 0.62, 0.76, 0.89, 1.0]
	return curve[clampi(day, 0, curve.size() - 1)]


func set_quality(level: int) -> void:
	var s: int = [1, 2, 3][clampi(level, 0, 2)]
	var k: float = [0.7, 0.85, 1.0][clampi(level, 0, 2)]
	ranges = [BASE_RANGES[0] * k, BASE_RANGES[1] * k]
	if s != sub:
		sub = s
		for c in _chunks.values():
			c.sig = ""
	for c in _chunks.values():
		_set_ranges(c.mm)
	if not _last.is_empty():
		callv("update", _last)


func set_water_y(y: float) -> void:
	for m in [_leaf_mat, _pan_mat, _stub_mat]:
		m.set_shader_parameter("water_y", y)


# Called by field.gd whenever clumps, growth or health change.
func update(clumps: Array, growth_day: int, pest: float, health: float) -> void:
	_last = [clumps, growth_day, pest, health]
	var s := stage_of(growth_day)
	var ripe := clampf((s - 0.62) / 0.38, 0.0, 1.0)
	if s != _stage:
		_stage = s
		_build_meshes(s)
	var stress := (clampf(pest - 0.3, 0.0, 0.7) + (1.0 - health) * 0.5) * (1.0 - ripe)
	for m in [_leaf_mat, _pan_mat]:
		m.set_shader_parameter("stage", s)
		m.set_shader_parameter("ripe", ripe)
		m.set_shader_parameter("stress", stress)
		m.set_shader_parameter("plant_height", lerpf(0.22, 1.0, smoothstep(0.0, 0.62, s)))
	# Group clumps per chunk; rebuild only the chunks whose content changed.
	var groups := {}
	for c in clumps:
		var k := Vector2i(clampi(int(floor((c.x - L.FIELD.x0) / CHUNK)), 0, NC - 1), clampi(int(floor((c.z - L.FIELD.z0) / CHUNK)), 0, NC - 1))
		if not groups.has(k):
			groups[k] = []
		groups[k].append(c)
	for k in _chunks:
		if not groups.has(k):
			groups[k] = []
	for k in groups:
		var list: Array = groups[k]
		var cut := 0
		for c in list:
			if c.cut:
				cut += 1
		var sig := "%d|%d|%d" % [list.size(), cut, sub]
		if not _chunks.has(k):
			if list.is_empty():
				continue
			_chunks[k] = {"sig": "", "mm": _make_chunk(k)}
		var ch: Dictionary = _chunks[k]
		if ch.sig != sig:
			ch.sig = sig
			_fill_chunk(ch.mm, list)


func _build_meshes(s: float) -> void:
	_meshes.clear()
	for lod in 3:
		var row := []
		for v in VARIANTS[lod]:
			var m := R.hill(s, 101 + v * 17, lod)
			m.surface_set_material(0, _leaf_mat)
			if m.get_surface_count() > 1:
				m.surface_set_material(1, _pan_mat)
			row.append(m)
		_meshes.append(row)
	for ch in _chunks.values():
		var i := 0
		for lod in 3:
			for v in VARIANTS[lod]:
				(ch.mm[i] as MultiMeshInstance3D).multimesh.mesh = _meshes[lod][v]
				i += 1
		(ch.mm[7] as MultiMeshInstance3D).multimesh.mesh = _meshes[2][0]


# 5 hill MultiMeshes (lod 0 x2, lod 1 x2, lod 2) + 2 stubble MultiMeshes
# + a shadow-only lod-2 proxy so the middle band keeps its canopy shading.
func _make_chunk(k: Vector2i) -> Array:
	var out := []
	var box := AABB(Vector3(L.FIELD.x0 + k.x * CHUNK - 0.6, L.FIELD.y - 0.1, L.FIELD.z0 + k.y * CHUNK - 0.6), Vector3(CHUNK + 1.2, 1.5, CHUNK + 1.2))
	for i in 8:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true # must be set before instance_count
		mm.custom_aabb = box # no AABB recomputation per instance
		if i < 5:
			var lod := 0 if i < 2 else (1 if i < 4 else 2)
			mm.mesh = _meshes[lod][i % 2 if lod < 2 else 0]
		elif i < 7:
			mm.mesh = _stubble[i - 5]
		else:
			mm.mesh = _meshes[2][0]
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		mmi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		add_child(mmi)
		out.append(mmi)
	_set_ranges(out)
	return out


func _set_ranges(mms: Array) -> void:
	# Only the outgoing lod dithers out (over end +- margin); the incoming lod
	# is already fully drawn under it from where that fade starts. Two
	# overlapping dither fades use the same screen pattern and leave a ring
	# of holes where both are half transparent.
	for i in mms.size():
		var mmi: MultiMeshInstance3D = mms[i]
		var lod := 0 if i < 2 else (1 if i < 4 else (2 if i < 5 else (0 if i == 5 else 2)))
		mmi.visibility_range_begin = 0.0 if lod == 0 else ranges[lod - 1] - MARGINS[lod - 1]
		mmi.visibility_range_begin_margin = 0.0
		mmi.visibility_range_end = ranges[lod] if lod < 2 else 0.0
		mmi.visibility_range_end_margin = MARGINS[lod] if lod < 2 else 0.0
		if i == 5: # near stubble reaches out to where lod 2 begins
			mmi.visibility_range_end = ranges[1]
			mmi.visibility_range_end_margin = MARGINS[1]
		# Only the nearest hills cast shadows (canopy self-shading at the
		# player's feet): every shadow cascade redraws its casters, and the
		# paddy would otherwise cost millions of triangles per frame.
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if lod == 0 else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if i == 7: # cheap lod-2 shadow caster for the middle band
			mmi.visibility_range_begin = ranges[0]
			# out to 6 m only: a ring of shadow casters costs its area in
			# every cascade, and farther out the shading is lost in the haze
			mmi.visibility_range_end = ranges[1] - MARGINS[1]
			mmi.visibility_range_end_margin = 0.0
			mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY


func _fill_chunk(mms: Array, list: Array) -> void:
	var hills := [[], [], [], [], [], [], [], []]
	var step := 0.6 / sub
	for c in list:
		var rng := RandomNumberGenerator.new()
		for a in sub:
			for b in sub:
				rng.seed = hash(Vector3(c.x, c.z, a * 7 + b))
				var off := (Vector2(a, b) - Vector2(sub - 1, sub - 1) * 0.5) * step
				# small jitter and tilt only, so the 20 cm transplant rows stay readable
				off += Vector2(rng.randf_range(-0.015, 0.015), rng.randf_range(-0.015, 0.015)) * (step / 0.2)
				var pos := Vector3(c.x + off.x, L.FIELD.y, c.z + off.y)
				var tilt := Vector3(rng.randf_range(-1, 1), 0.0, rng.randf_range(-1, 1)).normalized()
				var basis := Basis(tilt, rng.randf_range(0.0, 0.04)) * Basis(Vector3.UP, rng.randf() * TAU)
				var sc := rng.randf_range(0.86, 1.12)
				var xf := Transform3D(basis.scaled(Vector3.ONE * sc), pos)
				var custom := Color(rng.randf_range(-1.0, 1.0), rng.randf_range(0.4, 1.6), rng.randf(), rng.randf())
				if c.cut:
					hills[5].append([xf, custom])
					hills[6].append([xf, custom])
				else:
					var pick := rng.randi()
					hills[pick % 2].append([xf, custom])
					hills[2 + (pick >> 3) % 2].append([xf, custom])
					hills[4].append([xf, custom])
					hills[7].append([xf, custom])
	for i in 8:
		var mm: MultiMesh = (mms[i] as MultiMeshInstance3D).multimesh
		var hs: Array = hills[i]
		mm.instance_count = hs.size()
		for j in hs.size():
			mm.set_instance_transform(j, hs[j][0])
			mm.set_instance_custom_data(j, hs[j][1])
		(mms[i] as MultiMeshInstance3D).visible = hs.size() > 0
