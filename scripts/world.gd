# Static scenery of the farm: ground, bunds, canal, house, courtyard,
# animal sheds, the props the player interacts with, and the village
# plants and karst hills around it. Surfaces use the CC0 Poly Haven
# textures and models in res://assets (see assets/CREDITS.md); plants and
# a few Vietnamese-specific props are built in code.
extends RefCounted

const L = preload("res://scripts/layout.gd")
const A = preload("res://scripts/assets.gd")
const F = preload("res://scripts/flora.gd")
const WATER = preload("res://shaders/water.gdshader")
const GROUND = preload("res://shaders/ground.gdshader")
const WALL = preload("res://shaders/wall.gdshader")
const ROOF = preload("res://shaders/roof.gdshader")
const COURT = preload("res://shaders/court.gdshader")
const KARST = preload("res://shaders/karst.gdshader")
const IDLE = preload("res://scripts/idle_anim.gd")

static var _mats := {}
static var _water_mats := {}


static func mat(color: Color, double_sided := false, unshaded := false) -> StandardMaterial3D:
	var key := "%s|%s|%s" % [color.to_html(), double_sided, unshaded]
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = color
		m.roughness = 0.9
		if double_sided:
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
		if unshaded:
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_mats[key] = m
	return _mats[key]


static func add_mesh(parent: Node3D, mesh: Mesh, color: Color, pos: Vector3, rot := Vector3.ZERO, shadow := true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat(color)
	mi.position = pos
	mi.rotation = rot
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


static func box(parent: Node3D, size: Vector3, color: Color, pos: Vector3, shadow := true) -> MeshInstance3D:
	var b := BoxMesh.new()
	b.size = size
	return add_mesh(parent, b, color, pos, Vector3.ZERO, shadow)


# Box with a material instead of a flat colour.
static func mbox(parent: Node3D, size: Vector3, m: Material, pos: Vector3, rot := Vector3.ZERO, shadow := true) -> MeshInstance3D:
	var mi := box(parent, size, Color.WHITE, pos, shadow)
	mi.rotation = rot
	mi.material_override = m
	return mi


static func cyl(parent: Node3D, rt: float, rb: float, h: float, color: Color, pos: Vector3, seg := 8) -> MeshInstance3D:
	var c := CylinderMesh.new()
	c.top_radius = rt
	c.bottom_radius = rb
	c.height = h
	c.radial_segments = seg
	c.rings = 1
	return add_mesh(parent, c, color, pos)


static func mcyl(parent: Node3D, rt: float, rb: float, h: float, m: Material, pos: Vector3, seg := 12) -> MeshInstance3D:
	var mi := cyl(parent, rt, rb, h, Color.WHITE, pos, seg)
	mi.material_override = m
	return mi


static func sphere(parent: Node3D, r: float, color: Color, pos: Vector3, scale := Vector3.ONE) -> MeshInstance3D:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = 16
	s.rings = 8
	var mi := add_mesh(parent, s, color, pos)
	mi.scale = scale
	return mi


static func place(parent: Node3D, id: String, pos: Vector3, scale := 1.0, yaw := 0.0) -> Node3D:
	var n := A.model(id)
	n.position = pos
	n.scale = Vector3.ONE * scale
	n.rotation.y = yaw
	parent.add_child(n)
	return n


# Largest single part of a model file that holds several pieces.
static func place_part(parent: Node3D, id: String, pos: Vector3, scale := 1.0, yaw := 0.0) -> MeshInstance3D:
	var best: Dictionary = {}
	for p in A.parts(id):
		if best.is_empty() or p.height > best.height:
			best = p
	var mi := MeshInstance3D.new()
	mi.mesh = best.mesh
	mi.transform = Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * scale), pos) * best.xf
	parent.add_child(mi)
	return mi


static func water_material(kind: String) -> ShaderMaterial:
	if _water_mats.has(kind):
		return _water_mats[kind]
	var m := ShaderMaterial.new()
	m.shader = WATER
	m.set_shader_parameter("wave_a", _wave_texture(3))
	m.set_shader_parameter("wave_b", _wave_texture(9))
	match kind:
		"paddy": # thin layer over mud, sky reflections
			m.set_shader_parameter("tint", Color(0.36, 0.34, 0.24))
			m.set_shader_parameter("clarity", 0.35)
			m.set_shader_parameter("scale", 0.5)
		"canal":
			# Turbid water reflects little light back up (albedo ~0.1), and is
			# clear enough that the bank slope shows under the edges.
			m.set_shader_parameter("tint", Color(0.12, 0.15, 0.09))
			m.set_shader_parameter("clarity", 0.5)
			m.set_shader_parameter("shore", 0.12)
		"pond":
			m.set_shader_parameter("tint", Color(0.16, 0.25, 0.18))
			m.set_shader_parameter("clarity", 0.88)
			m.set_shader_parameter("wind", 0.6)
	_water_mats[kind] = m
	return m


static func _wave_texture(seed: int) -> NoiseTexture2D:
	var n := FastNoiseLite.new()
	n.seed = seed
	n.frequency = 0.02
	n.fractal_octaves = 3
	var t := NoiseTexture2D.new()
	t.width = 256
	t.height = 256
	t.seamless = true
	t.as_normal_map = true
	t.bump_strength = 4.0
	t.generate_mipmaps = true
	t.noise = n
	return t


static func paddy_material() -> ORMMaterial3D:
	if _mats.has("paddy"):
		return _mats.paddy
	var m := ORMMaterial3D.new()
	m.albedo_color = Color(0.86, 0.68, 0.3)
	m.normal_enabled = true
	m.normal_texture = A.tex("farm_soil", "nor")
	m.normal_scale = 0.6
	m.roughness = 0.75
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3.ONE * 3.0
	_mats.paddy = m
	return m


static func _plastic(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.35
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


# ---------------------------------------------------------------- ground
# Grid coordinates from lo to hi: `step` apart, `fine` apart inside the
# given [a, b] bands (bund slopes, canal banks, the pond), always hitting
# the listed `must` values exactly.
static func _coords(lo: float, hi: float, step: float, bands: Array, must := []) -> PackedFloat32Array:
	var out := []
	var c := lo
	while c < hi:
		out.append(c)
		var st := step
		for bd in bands:
			if c >= bd[0] - 0.001 and c < bd[1]:
				st = minf(st, bd[2])
		c += st
	out.append(hi)
	for m in must:
		out.append(m)
	out.sort()
	var res := PackedFloat32Array()
	for v in out:
		if res.is_empty() or v - res[res.size() - 1] > 0.02:
			res.append(v)
	return res


# Height-field mesh on a tensor grid. `height` gives y for (x, z); cells
# for which `skip` returns true are left out. Normals come from the
# neighbouring heights, so slopes shade smoothly on the uneven grid.
static func _grid_mesh(xs: PackedFloat32Array, zs: PackedFloat32Array, height: Callable, skip: Callable) -> ArrayMesh:
	var nx := xs.size()
	var nz := zs.size()
	var hs := PackedFloat32Array()
	hs.resize(nx * nz)
	var v := PackedVector3Array()
	v.resize(nx * nz)
	for j in nz:
		for i in nx:
			var y: float = height.call(xs[i], zs[j])
			hs[j * nx + i] = y
			v[j * nx + i] = Vector3(xs[i], y, zs[j])
	var nrm := PackedVector3Array()
	nrm.resize(nx * nz)
	for j in nz:
		var j0 := maxi(j - 1, 0)
		var j1 := mini(j + 1, nz - 1)
		for i in nx:
			var i0 := maxi(i - 1, 0)
			var i1 := mini(i + 1, nx - 1)
			var dx := (hs[j * nx + i1] - hs[j * nx + i0]) / (xs[i1] - xs[i0])
			var dz := (hs[j1 * nx + i] - hs[j0 * nx + i]) / (zs[j1] - zs[j0])
			nrm[j * nx + i] = Vector3(-dx, 1.0, -dz).normalized()
	var idx := PackedInt32Array()
	for j in nz - 1:
		for i in nx - 1:
			if skip.call((xs[i] + xs[i + 1]) * 0.5, (zs[j] + zs[j + 1]) * 0.5):
				continue
			var a := j * nx + i
			idx.append_array([a, a + 1, a + nx, a + 1, a + nx + 1, a + nx])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = v
	arrays[Mesh.ARRAY_NORMAL] = nrm
	arrays[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return m


static func _ground_material(relief: bool) -> ShaderMaterial:
	var gm := ShaderMaterial.new()
	gm.shader = GROUND
	gm.set_shader_parameter("grass_alb", A.tex("sparse_grass", "diff"))
	gm.set_shader_parameter("grass_nor", A.tex("sparse_grass", "nor"))
	gm.set_shader_parameter("grass_arm", A.tex("sparse_grass", "arm"))
	gm.set_shader_parameter("earth_alb", A.tex("grass_path_3", "diff"))
	gm.set_shader_parameter("earth_nor", A.tex("grass_path_3", "nor"))
	gm.set_shader_parameter("earth_arm", A.tex("grass_path_3", "arm"))
	gm.set_shader_parameter("mud_alb", A.tex("brown_mud_03", "diff"))
	gm.set_shader_parameter("mud_nor", A.tex("brown_mud_03", "nor"))
	gm.set_shader_parameter("mud_arm", A.tex("brown_mud_03", "arm"))
	gm.set_shader_parameter("relief", relief)
	gm.set_shader_parameter("near_rect", Vector4(NEAR.x0, NEAR.z0, NEAR.x1, NEAR.z1))
	gm.set_shader_parameter("field_rect", Vector4(L.FIELD.x0, L.FIELD.z0, L.FIELD.x1, L.FIELD.z1))
	gm.set_shader_parameter("court_rect", Vector4(L.COURT.x0, L.COURT.z0, L.COURT.x1, L.COURT.z1))
	gm.set_shader_parameter("canal", Vector2((L.CANAL.x0 + L.CANAL.x1) * 0.5, (L.CANAL.x1 - L.CANAL.x0) * 0.5))
	gm.set_shader_parameter("pond", Vector3(L.POND.x, L.POND.z, L.POND.r))
	gm.set_shader_parameter("wallow", Vector3(L.BUFFALO.x, L.BUFFALO.y, 1.6))
	# Lối mòn: the paths people actually walk every day.
	var segs := []
	var widths := []
	for path in PATHS:
		for i in path[1].size() - 1:
			var a: Vector2 = path[1][i]
			var b: Vector2 = path[1][i + 1]
			segs.append(Vector4(a.x, a.y, b.x, b.y))
			widths.append(path[0])
	# Uniform arrays must be passed at their declared length.
	var count := segs.size()
	while segs.size() < 16:
		segs.append(Vector4(0, 0, 1, 0))
		widths.append(0.0)
	gm.set_shader_parameter("paths", PackedVector4Array(segs))
	gm.set_shader_parameter("path_w", PackedFloat32Array(widths))
	gm.set_shader_parameter("path_count", count)
	return gm


# [width, points] of each trodden path.
const PATHS := [
	[1.0, [Vector2(0, -14.2), Vector2(0.4, -11.6), Vector2(-0.3, -9.0)]], # sân -> ruộng
	[0.9, [Vector2(-6.2, -16.5), Vector2(-9.0, -14.2), Vector2(-11.0, -13.0), Vector2(-13.2, -12.4), Vector2(-15.6, -10.6)]], # sân -> cầu -> ao
	[0.9, [Vector2(-6.2, -19.6), Vector2(-9.4, -21.4), Vector2(-12.4, -22.6)]], # sân -> chuồng lợn
	[0.7, [Vector2(-9.4, -21.4), Vector2(-8.6, -23.6)]], # -> bếp
	[0.9, [Vector2(6.2, -17.0), Vector2(8.6, -16.4), Vector2(10.8, -16.2)]], # -> vạt mạ
	[0.8, [Vector2(6.2, -15.0), Vector2(9.9, -11.5), Vector2(10.2, -4.0), Vector2(10.8, 3.0), Vector2(11.0, 7.0), Vector2(12.0, 8.0)]], # -> chuồng vịt
	[0.8, [Vector2(-1.2, 9.0), Vector2(-2.6, 11.6)]], # -> chỗ trâu
]
const NEAR := {"x0": -40.0, "x1": 40.0, "z0": -44.0, "z1": 36.0}
const FAR := 700.0


static func _ground(root: Node3D, h: Dictionary) -> void:
	var t0 := Time.get_ticks_msec()
	var near_m := _ground_material(false)
	var far_m := _ground_material(true)
	var c0: float = L.CANAL.x0
	var c1: float = L.CANAL.x1
	var fx0: float = L.FIELD.x0
	var fx1: float = L.FIELD.x1
	var b: float = L.FIELD.bund
	# Near terrain: 0.4 m grid, 0.1 m across bund slopes, canal banks and notches.
	var bx := [[fx0 - b - 0.6, fx0 + 0.4, 0.1], [fx1 - 0.4, fx1 + b + 0.6, 0.1], [c0 - 0.6, c1 + 0.6, 0.12],
		[L.POND.x - 7.0, L.POND.x + 7.0, 0.22]]
	var bz := [[fx0 - b - 0.6, fx0 + 0.4, 0.1], [fx1 - 0.4, fx1 + b + 0.6, 0.1], [L.GATE.y - 0.7, L.GATE.y + 0.7, 0.1],
		[L.DRAIN.y - 0.7, L.DRAIN.y + 0.7, 0.1], [L.POND.z - 7.0, L.POND.z + 7.0, 0.22]]
	var xs := _coords(NEAR.x0, NEAR.x1, 0.4, bx, [c0 - 2.0, c1 + 2.0])
	var zs := _coords(NEAR.z0, NEAR.z1, 0.4, bz)
	var hole := func(x: float, z: float) -> bool: return L.in_field(x, z, -0.3)
	var near := _grid_mesh(xs, zs, Callable(L, "terrain_y"), hole)
	_terrain_node(root, near, near_m)
	# The canal runs on past the near terrain, north and south.
	var sx := PackedFloat32Array()
	for x in xs:
		if x >= c0 - 2.0 - 0.001 and x <= c1 + 2.0 + 0.001:
			sx.append(x)
	var never := func(_x: float, _z: float) -> bool: return false
	var canal_y := func(x: float, z: float) -> float: return L.terrain_y(x, z)
	_terrain_node(root, _grid_mesh(sx, _coords(NEAR.z1, 320.0, 1.0, []), canal_y, never), near_m)
	_terrain_node(root, _grid_mesh(sx, _coords(-320.0, NEAR.z0, 1.0, []), canal_y, never), near_m)
	# Far ground to the horizon: 1.5 m cells near the farm, growing outward.
	var fxs := _far_coords([NEAR.x0, NEAR.x1, c0 - 2.0, c1 + 2.0])
	var fzs := _far_coords([NEAR.z0, NEAR.z1, -320.0, 320.0])
	var far_hole := func(x: float, z: float) -> bool:
		if x > NEAR.x0 and x < NEAR.x1 and z > NEAR.z0 and z < NEAR.z1:
			return true
		return x > c0 - 2.0 and x < c1 + 2.0 and z > -320.0 and z < 320.0
	var flat := func(_x: float, _z: float) -> float: return 0.0
	_terrain_node(root, _grid_mesh(fxs, fzs, flat, far_hole), far_m).extra_cull_margin = 1.0
	print("terrain built in %d ms (%d near verts)" % [Time.get_ticks_msec() - t0, xs.size() * zs.size()])

	# Mương: murky water between the sloped banks.
	var cx: float = (c0 + c1) / 2.0
	var water := PlaneMesh.new()
	water.size = Vector2(c1 - c0 + 0.9, 640.0)
	var cw := MeshInstance3D.new()
	cw.mesh = water
	cw.material_override = water_material("canal")
	cw.position = Vector3(cx, -0.3, 0)
	cw.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(cw)
	h.canal_water = cw
	# Nước trong rãnh dẫn tới cửa cống
	var inlet := PlaneMesh.new()
	inlet.size = Vector2(2.2, 0.7)
	var iw := MeshInstance3D.new()
	iw.mesh = inlet
	iw.material_override = water_material("canal")
	iw.position = Vector3(L.GATE.x - 1.2, -0.13, L.GATE.y)
	iw.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(iw)
	_bridge(root)

	# Ao: the water plane is larger than the shore; the bank hides its edge.
	var pond := PlaneMesh.new()
	pond.size = Vector2(L.POND.r * 2.6, L.POND.r * 2.6)
	var pmi := MeshInstance3D.new()
	pmi.mesh = pond
	pmi.material_override = water_material("pond")
	pmi.position = Vector3(L.POND.x, L.POND_WATER, L.POND.z)
	pmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(pmi)
	_hyacinths(root)


static func _terrain_node(root: Node3D, mesh: ArrayMesh, m: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	return mi


static func _far_coords(must: Array) -> PackedFloat32Array:
	var out := []
	var c := -FAR
	while c < FAR:
		out.append(c)
		c += maxf(1.5, (absf(c) - 110.0) * 0.09)
	out.append(FAR)
	out.append_array(must)
	out.sort()
	var res := PackedFloat32Array()
	for v in out:
		if res.is_empty() or v - res[res.size() - 1] > 0.3:
			res.append(v)
		elif v in must:
			res[res.size() - 1] = v
	return res


# Cầu tre: two bamboo poles and split-bamboo slats across the canal.
static func _bridge(root: Node3D) -> void:
	var z: float = L.BRIDGE.z
	var x0: float = L.CANAL.x0 - 0.9
	var x1: float = L.CANAL.x1 + 0.9
	var pole := StandardMaterial3D.new()
	pole.albedo_color = Color(0.55, 0.5, 0.36)
	pole.roughness = 0.55
	for s in [-0.3, 0.3]:
		var c := mcyl(root, 0.06, 0.06, x1 - x0, pole, Vector3((x0 + x1) / 2.0, L.BRIDGE.y - 0.06, z + s), 8)
		c.rotation.z = PI / 2
	var slat := A.pbr("weathered_planks", 0.8, true, Color(0.75, 0.68, 0.55))
	var n := 22
	for i in n:
		var x := lerpf(x0 + 0.1, x1 - 0.1, float(i) / (n - 1))
		mbox(root, Vector3(0.12, 0.03, 0.85), slat, Vector3(x, L.BRIDGE.y + 0.01, z + randf_range(-0.04, 0.04)), Vector3(0, randf_range(-0.06, 0.06), 0))
	for x in [L.CANAL.x0 + 0.3, L.CANAL.x1 - 0.3]:
		for s in [-0.3, 0.3]:
			mcyl(root, 0.045, 0.05, 1.1, pole, Vector3(x, -0.45, z + s), 7)


# Bèo tây (water hyacinth): rosettes of glossy, cupped leaves on swollen
# stalks, floating in loose rafts, a few with a pale lilac flower spike.
static func _hyacinths(root: Node3D) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var leaf := _hyacinth_leaf()
	var stalk := _hyacinth_stalk()
	var leaves := []
	var stalks := []
	var flowers := []
	var rafts := [[Vector2(-1.9, 1.4), 1.1], [Vector2(1.6, -1.8), 0.8], [Vector2(2.4, 1.7), 0.6], [Vector2(-2.6, -1.6), 0.5], [Vector2(0.3, 3.1), 0.7]]
	for raft in rafts:
		var count := int(40 * raft[1] * raft[1]) + 6
		for i in count:
			var c: Vector2 = Vector2(L.POND.x, L.POND.z) + raft[0] + Vector2(rng.randfn(0.0, raft[1]), rng.randfn(0.0, raft[1] * 0.8))
			if not L.in_pond(c.x, c.y) or Vector2(c.x - L.POND.x, c.y - L.POND.z).length() > L.pond_r(c.x, c.y) - 0.35:
				continue
			var base := Vector3(c.x, L.POND_WATER - 0.015, c.y)
			var nl := rng.randi_range(6, 9)
			var s := rng.randf_range(1.1, 1.8)
			for k in nl:
				var a := k * TAU / nl + rng.randf_range(-0.25, 0.25)
				var tilt := rng.randf_range(0.6, 1.0)
				var b := Basis(Vector3.UP, a) * Basis(Vector3.RIGHT, -tilt * 0.5)
				stalks.append(Transform3D(b.scaled(Vector3.ONE * s), base))
				leaves.append(Transform3D((b * Basis(Vector3.RIGHT, tilt * 0.4)).scaled(Vector3.ONE * s), base + b * Vector3(0, 0.09, 0.06) * s))
			if rng.randf() < 0.12:
				flowers.append(base + Vector3(0, 0.02, 0))
	_multi(root, leaf, leaves, _leaf_material(Color(0.13, 0.3, 0.06), 0.35))
	_multi(root, stalk, stalks, _leaf_material(Color(0.22, 0.36, 0.1), 0.45))
	# Flower spikes: a stem with small lilac florets.
	var stem_m := _leaf_material(Color(0.25, 0.38, 0.12), 0.5)
	var petal := _leaf_material(Color(0.62, 0.55, 0.85), 0.6)
	var fl := SphereMesh.new()
	fl.radius = 0.022
	fl.height = 0.03
	fl.radial_segments = 6
	fl.rings = 3
	var florets := []
	for fp in flowers:
		mcyl(root, 0.006, 0.008, 0.22, stem_m, fp + Vector3(0, 0.12, 0), 5)
		for k in 9:
			var a := k * 2.4
			florets.append(Transform3D(Basis(Vector3.UP, a), fp + Vector3(cos(a) * 0.025, 0.17 + k * 0.012, sin(a) * 0.025)))
	_multi(root, fl, florets, petal)


static func _leaf_material(c: Color, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.backlight_enabled = true
	m.backlight = Color(0.25, 0.35, 0.1)
	return m


static func _multi(root: Node3D, mesh: Mesh, xforms: Array, m: Material, shadow := true) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = m
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mmi)
	return mmi


# A rounded, cupped hyacinth blade (about 12 cm), base at the origin, along +z.
static func _hyacinth_leaf() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rows := 6
	var cols := 6
	for j in rows:
		for i in cols:
			for q in [[0, 0], [1, 0], [0, 1], [1, 0], [1, 1], [0, 1]]:
				var u := float(i + q[0]) / cols * 2.0 - 1.0
				var v := float(j + q[1]) / rows
				# Kidney-shaped outline, wider than long, cupped upward.
				var w := sin(v * PI * 0.92 + 0.15) * 0.07
				var x := u * w
				var z := v * 0.11
				var y := u * u * 0.025 + v * v * 0.02
				st.set_normal(Vector3(-u * 0.5, 1.0, -v * 0.3).normalized())
				st.add_vertex(Vector3(x, y, z))
	return st.commit()


# The swollen, spongy leaf stalk that keeps the plant afloat.
static func _hyacinth_stalk() -> ArrayMesh:
	var c := CapsuleMesh.new()
	c.radius = 0.022
	c.height = 0.11
	c.radial_segments = 8
	c.rings = 2
	var arr := c.get_mesh_arrays()
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	for i in v.size():
		# lay it along +z, lift it to sit on the water
		v[i] = Vector3(v[i].x, v[i].z * 0.8 + 0.02, v[i].y + 0.04)
	arr[Mesh.ARRAY_VERTEX] = v
	var n: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	for i in n.size():
		n[i] = Vector3(n[i].x, n[i].z, n[i].y)
	arr[Mesh.ARRAY_NORMAL] = n
	arr[Mesh.ARRAY_TANGENT] = null
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m


# ---------------------------------------------------------------- house & courtyard
static func wall_material(tint := Color(1.0, 0.93, 0.78), base_y := 0.3, top_y := 2.9, damp := 1.0) -> ShaderMaterial:
	var key := "wall|%s|%s|%s|%s" % [tint.to_html(), base_y, top_y, damp]
	if _mats.has(key):
		return _mats[key]
	var m := ShaderMaterial.new()
	m.shader = WALL
	m.set_shader_parameter("plaster_alb", A.tex("yellow_plaster", "diff"))
	m.set_shader_parameter("plaster_nor", A.tex("yellow_plaster", "nor"))
	m.set_shader_parameter("stain_alb", A.tex("worn_mossy_plasterwall", "diff"))
	m.set_shader_parameter("tint", tint)
	m.set_shader_parameter("base_y", base_y)
	m.set_shader_parameter("top_y", top_y)
	m.set_shader_parameter("damp", damp)
	_mats[key] = m
	return m


static func tile_floor_material(rect: Vector4, edge_moss := 1.0) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = COURT
	m.set_shader_parameter("grain_alb", A.tex("red_brick_pavers", "diff"))
	m.set_shader_parameter("grain_nor", A.tex("red_brick_pavers", "nor"))
	m.set_shader_parameter("dirt_alb", A.tex("grass_path_3", "diff"))
	m.set_shader_parameter("rect", rect)
	m.set_shader_parameter("edge_moss", edge_moss)
	return m


static func _house(root: Node3D, h: Dictionary) -> void:
	# Sân gạch: 30 cm fired-clay tiles, aged, with moss creeping in at the edges
	var court := PlaneMesh.new()
	court.size = Vector2(L.COURT.x1 - L.COURT.x0, L.COURT.z1 - L.COURT.z0)
	var cmi := MeshInstance3D.new()
	cmi.mesh = court
	cmi.material_override = tile_floor_material(Vector4(L.COURT.x0, L.COURT.z0, L.COURT.x1, L.COURT.z1))
	cmi.position = Vector3((L.COURT.x0 + L.COURT.x1) / 2.0, 0.015, (L.COURT.z0 + L.COURT.z1) / 2.0)
	root.add_child(cmi)
	# Khung bạt: faint lime lines, only shown while paddy is drying
	var tw: float = L.TARP.x1 - L.TARP.x0
	var td: float = L.TARP.z1 - L.TARP.z0
	var tcx: float = (L.TARP.x0 + L.TARP.x1) / 2.0
	var tcz: float = (L.TARP.z0 + L.TARP.z1) / 2.0
	var lines := Node3D.new()
	lines.visible = false
	root.add_child(lines)
	var line_m := StandardMaterial3D.new()
	line_m.albedo_color = Color(0.72, 0.7, 0.64)
	line_m.roughness = 0.95
	for k in [[Vector3(tw, 0.004, 0.03), Vector3(tcx, 0.017, L.TARP.z0)], [Vector3(tw, 0.004, 0.03), Vector3(tcx, 0.017, L.TARP.z1)],
			[Vector3(0.03, 0.004, td), Vector3(L.TARP.x0, 0.017, tcz)], [Vector3(0.03, 0.004, td), Vector3(L.TARP.x1, 0.017, tcz)]]:
		mbox(lines, k[0], line_m, k[1], Vector3.ZERO, false)
	h.tarp_lines = lines

	# Nhà ba gian: lime-washed walls on a raised brick platform, a veranda
	# of wooden columns on stone bases, panelled doors set into the wall.
	var plaster := wall_material()
	var wood := A.pbr("weathered_planks", 1.2, true, Color(0.62, 0.46, 0.34))
	var door := A.pbr("weathered_planks", 0.9, true, Color(0.42, 0.27, 0.18))
	var plinth := A.pbr("red_brick_pavers", 0.9, true, Color(0.72, 0.66, 0.62))
	var stone := A.pbr("rock_pitted_mossy", 0.6, true, Color(0.42, 0.44, 0.44))
	mbox(root, Vector3(10.6, 0.3, 7.8), plinth, Vector3(0, 0.15, -25.0), Vector3.ZERO, false)
	var floor_tiles := MeshInstance3D.new()
	var fp := PlaneMesh.new()
	fp.size = Vector2(10.5, 1.4)
	floor_tiles.mesh = fp
	floor_tiles.material_override = tile_floor_material(Vector4(-5.25, -22.5, 5.25, -21.1), 0.0)
	floor_tiles.position = Vector3(0, 0.302, -21.8)
	root.add_child(floor_tiles)
	mbox(root, Vector3(2.6, 0.15, 0.4), plinth, Vector3(0, 0.075, -20.9), Vector3.ZERO, false) # bậc thềm
	# Body behind the facade; the facade is 12 cm proud of it with door openings.
	mbox(root, Vector3(10, 2.6, 5.88), plaster, Vector3(0, 1.6, -25.56))
	var openings := [-3.2, 0.0, 3.2]
	var ow := 1.5
	var oh := 2.15
	var edges := [-5.0]
	for x in openings:
		edges.append(x - ow / 2.0)
		edges.append(x + ow / 2.0)
	edges.append(5.0)
	for i in range(0, edges.size(), 2):
		var x0: float = edges[i]
		var x1: float = edges[i + 1]
		mbox(root, Vector3(x1 - x0, 2.6, 0.12), plaster, Vector3((x0 + x1) / 2.0, 1.6, -22.56))
	for x in openings:
		mbox(root, Vector3(ow, 2.6 - oh, 0.12), plaster, Vector3(x, 0.3 + oh + (2.6 - oh) / 2.0, -22.56))
		# Cửa bức bàn: four dark board leaves in a frame, recessed into the wall
		for k in 4:
			var lx: float = x - ow / 2.0 + 0.1 + (k + 0.5) * (ow - 0.2) / 4.0
			mbox(root, Vector3((ow - 0.2) / 4.0 - 0.012, oh - 0.12, 0.05), door, Vector3(lx, 0.3 + (oh - 0.1) / 2.0 + 0.02, -22.6))
			mbox(root, Vector3((ow - 0.2) / 4.0 - 0.04, 0.05, 0.02), wood, Vector3(lx, 1.15, -22.57))
		for s in [-1, 1]:
			mbox(root, Vector3(0.1, oh, 0.12), wood, Vector3(x + s * (ow / 2.0 - 0.05), 0.3 + oh / 2.0, -22.58))
		mbox(root, Vector3(ow, 0.1, 0.12), wood, Vector3(x, 0.3 + oh - 0.05, -22.58))
		mbox(root, Vector3(ow, 0.06, 0.16), wood, Vector3(x, 0.33, -22.56)) # ngưỡng cửa
	for x in [-4.6, -1.6, 1.6, 4.6]:
		mcyl(root, 0.11, 0.12, 2.75, wood, Vector3(x, 1.72, -21.6), 14)
		mcyl(root, 0.17, 0.2, 0.14, stone, Vector3(x, 0.37, -21.6), 12) # chân tảng
		_shadow_decal(root, Vector3(x, 0.3, -21.6), Vector2(0.75, 0.75), 0.6)
	mbox(root, Vector3(10.2, 0.2, 0.16), wood, Vector3(0, 3.0, -21.6)) # xà hiên
	for x in [-4.6, -1.6, 1.6, 4.6]:
		mbox(root, Vector3(0.1, 0.12, 1.0), wood, Vector3(x, 2.94, -22.1)) # kẻ hiên into the wall

	# Mái ngói: thick tiled slopes on rafters, a fascia at the eaves,
	# a plastered ridge with raised ends, plastered gables.
	var slope := atan2(2.0, 4.2)
	var length := 4.2 / cos(slope) + 0.4
	for s in [-1.0, 1.0]:
		var pivot := Node3D.new()
		pivot.position = Vector3(0, 3.95, -25.25 + s * 2.05)
		pivot.rotation.x = s * slope
		root.add_child(pivot)
		var rm := ShaderMaterial.new()
		rm.shader = ROOF
		rm.set_shader_parameter("tile_alb", A.tex("clay_roof_tiles_02", "diff"))
		rm.set_shader_parameter("tile_nor", A.tex("clay_roof_tiles_02", "nor"))
		rm.set_shader_parameter("tile_arm", A.tex("clay_roof_tiles_02", "arm"))
		rm.set_shader_parameter("half_len", length / 2.0)
		rm.set_shader_parameter("eave_sign", s)
		mbox(pivot, Vector3(11.4, 0.22, length), rm, Vector3.ZERO)
		var edge_z: float = s * (length / 2.0 - 0.025)
		mbox(pivot, Vector3(11.4, 0.24, 0.05), wood, Vector3(0, -0.03, edge_z)) # diềm mái
		# Cầu phong: rafters showing under the overhang
		var raf := BoxMesh.new()
		raf.size = Vector3(0.07, 0.09, 2.4)
		var xf := []
		var x := -5.5
		while x <= 5.5:
			xf.append(Transform3D(Basis(), Vector3(x, -0.155, s * (length / 2.0 - 1.25))))
			x += 0.6
		_multi(pivot, raf, xf, wood)
		var purl := BoxMesh.new()
		purl.size = Vector3(11.2, 0.08, 0.1)
		_multi(pivot, purl, [Transform3D(Basis(), Vector3(0, -0.24, s * (length / 2.0 - 0.35))), Transform3D(Basis(), Vector3(0, -0.24, s * (length / 2.0 - 1.2)))], wood)
	var ridge := wall_material(Color(0.78, 0.76, 0.7), 4.8, 5.4, 0.0)
	mbox(root, Vector3(11.6, 0.3, 0.42), ridge, Vector3(0, 5.04, -25.25))
	for x in [-5.75, 5.75]:
		var end := mbox(root, Vector3(0.36, 0.5, 0.48), ridge, Vector3(x, 5.2, -25.25))
		end.rotation.z = signf(x) * -0.25 # đầu kìm, turned up
	var gable := PrismMesh.new()
	gable.size = Vector3(6.0, 2.0, 0.2)
	for x in [-4.95, 4.95]:
		var g := MeshInstance3D.new()
		g.mesh = gable
		g.material_override = wall_material(Color(1.0, 0.93, 0.78), 2.9, 4.9, 0.0)
		g.position = Vector3(x, 3.9, -25.5)
		g.rotation.y = PI / 2
		root.add_child(g)
	_shadow_decal(root, Vector3(0, 0, -25.0), Vector2(11.8, 9.0), 0.55)

	# Hiên: a water jar, potted plants, the hammock
	var glaze := StandardMaterial3D.new()
	glaze.albedo_color = Color(0.2, 0.14, 0.1)
	glaze.roughness = 0.3
	var jar := sphere(root, 0.42, Color.WHITE, Vector3(-6.2, 0.45, -22.4), Vector3(1, 1.15, 1))
	jar.material_override = glaze
	var lid := mcyl(root, 0.3, 0.32, 0.05, wood, Vector3(-6.2, 0.95, -22.4))
	lid.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_shadow_decal(root, Vector3(-6.2, 0, -22.4), Vector2(1.4, 1.4), 0.7)
	for p in [Vector3(-5.4, 0.3, -21.4), Vector3(5.4, 0.3, -21.4), Vector3(-2.6, 0.3, -21.3), Vector3(2.6, 0.3, -21.3)]:
		place(root, "planter_pot_clay", p, 1.6, randf() * TAU)
		var pl := place_part(root, "fern_02", p + Vector3(0, 0.3, 0), 0.7, randf() * TAU)
		pl.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		_shadow_decal(root, p, Vector2(0.7, 0.7), 0.6)
	_hammock(root, wood)


# Võng: a faded, striped cloth hammock sagging between two posts.
static func _hammock(root: Node3D, wood: Material) -> void:
	var c := Vector3(L.HAMMOCK.x, 0.0, L.HAMMOCK.y)
	var span := 1.05
	for s in [-1, 1]:
		mcyl(root, 0.05, 0.065, 1.7, wood, c + Vector3(s * (span + 0.3), 0.85, 0), 10)
	var img := Image.create(4, 64, false, Image.FORMAT_RGB8)
	for y in 64:
		var col := Color(0.24, 0.32, 0.22)
		if y % 16 < 2:
			col = Color(0.62, 0.6, 0.5)
		elif y % 16 == 8:
			col = Color(0.45, 0.16, 0.12)
		for x in 4:
			img.set_pixel(x, y, col)
	var cloth := StandardMaterial3D.new()
	cloth.albedo_texture = ImageTexture.create_from_image(img)
	cloth.roughness = 0.95
	cloth.cull_mode = BaseMaterial3D.CULL_DISABLED
	cloth.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var nu := 24
	var nv := 8
	for i in nu:
		for j in nv:
			for q in [[0, 0], [1, 0], [0, 1], [1, 0], [1, 1], [0, 1]]:
				var u := float(i + q[0]) / nu
				var v := float(j + q[1]) / nv
				var x := (u * 2.0 - 1.0) * span
				var w := 0.08 + 0.3 * sin(u * PI) # gathered at the ends
				var z := (v * 2.0 - 1.0) * w
				var sag := 0.42 * (1.0 - pow(u * 2.0 - 1.0, 2.0))
				var y := 1.05 - sag + (z * z) * 1.4
				st.set_uv(Vector2(u, v))
				st.add_vertex(c + Vector3(x, y, z))
	st.generate_normals()
	var ham := MeshInstance3D.new()
	ham.mesh = st.commit()
	ham.material_override = cloth
	root.add_child(ham)
	var rope := mat(Color(0.45, 0.4, 0.3))
	for s in [-1, 1]:
		var a := c + Vector3(s * span, 1.05, 0)
		var b := c + Vector3(s * (span + 0.3), 1.55, 0)
		var r := cyl(root, 0.01, 0.01, a.distance_to(b), Color(0.45, 0.4, 0.3), (a + b) / 2.0, 5)
		r.material_override = rope
		r.rotation.z = -s * atan2(0.3, 0.5)


# Soft dark blob on the ground under an object, standing in for the
# contact shadow and ambient occlusion the renderer does not give us.
static var _blob: GradientTexture2D

static func _shadow_decal(root: Node3D, pos: Vector3, size: Vector2, strength := 0.55, yaw := 0.0) -> Decal:
	if _blob == null:
		var g := Gradient.new()
		g.set_color(0, Color(0, 0, 0, 1))
		g.set_color(1, Color(0, 0, 0, 0))
		g.add_point(0.45, Color(0, 0, 0, 0.6))
		_blob = GradientTexture2D.new()
		_blob.gradient = g
		_blob.fill = GradientTexture2D.FILL_RADIAL
		_blob.fill_from = Vector2(0.5, 0.5)
		_blob.fill_to = Vector2(1.0, 0.5)
		_blob.width = 128
		_blob.height = 128
	var d := Decal.new()
	d.texture_albedo = _blob
	d.modulate = Color(0, 0, 0, strength)
	d.albedo_mix = 1.0
	d.size = Vector3(size.x, 1.0, size.y)
	d.upper_fade = 0.3
	d.lower_fade = 0.3
	d.position = pos
	d.rotation.y = yaw
	d.cull_mask = 1
	root.add_child(d)
	return d


# ---------------------------------------------------------------- props
static func _props(root: Node3D, h: Dictionary) -> void:
	var wood := A.pbr("weathered_planks", 1.0, true, Color(0.8, 0.62, 0.45))
	var bamboo_m := StandardMaterial3D.new()
	bamboo_m.albedo_color = Color(0.72, 0.64, 0.4)
	bamboo_m.roughness = 0.45
	var dirt := A.pbr("dirt", 1.2)
	var brick := A.pbr("red_brick_pavers", 0.35)
	# Cửa cống trên bờ tây
	var gate := Node3D.new()
	gate.position = Vector3(L.GATE.x, 0, L.GATE.y)
	root.add_child(gate)
	mbox(gate, Vector3(0.15, 1.0, 0.15), wood, Vector3(0, 0.2, -0.55))
	mbox(gate, Vector3(0.15, 1.0, 0.15), wood, Vector3(0, 0.2, 0.55))
	mbox(gate, Vector3(0.15, 0.12, 1.25), wood, Vector3(0, 0.7, 0))
	h.gate = mbox(gate, Vector3(0.08, 0.6, 0.95), wood, Vector3(0, -0.05, 0))
	# Ụ đất bịt rãnh xả bờ đông
	h.drain_plug = sphere(root, 0.5, Color.WHITE, Vector3(L.DRAIN.x + 0.3, -0.02, L.DRAIN.y), Vector3(1.0, 0.36, 0.78))
	h.drain_plug.material_override = A.pbr("brown_mud_03", 1.0)

	# Cọc tre bẫy ốc + ổ trứng hồng
	h.eggs = []
	var egg_m := StandardMaterial3D.new()
	egg_m.albedo_color = Color(0.95, 0.3, 0.5)
	egg_m.roughness = 0.5
	egg_m.normal_enabled = true
	egg_m.normal_texture = A.tex("farm_soil", "nor")
	egg_m.uv1_scale = Vector3(4, 4, 4)
	for s in L.STAKES:
		mcyl(root, 0.035, 0.04, 1.4, bamboo_m, Vector3(s.x, L.FIELD.y + 0.6, s.y), 7)
		var egg := sphere(root, 0.07, Color.WHITE, Vector3(s.x + 0.06, L.FIELD.y + 0.55, s.y), Vector3(1, 1.8, 1))
		egg.material_override = egg_m
		egg.visible = false
		h.eggs.append(egg)
		_shadow_decal(root, Vector3(s.x, L.FIELD.y, s.y), Vector2(0.3, 0.3), 0.5)

	# Thùng đập lúa: big wooden tub with a bamboo screen behind
	place(root, "wooden_bucket_02", Vector3(L.BARREL.x, 0.0, L.BARREL.y), 1.8)
	var screen := A.pbr("bamboo_wall", 0.8, true, Color(1.0, 0.95, 0.85))
	mbox(root, Vector3(1.4, 1.1, 0.04), screen, Vector3(L.BARREL.x, 0.9, L.BARREL.y - 0.62), Vector3(-0.2, 0, 0))
	mbox(root, Vector3(0.9, 0.05, 0.6), wood, Vector3(L.BARREL.x, 0.66, L.BARREL.y - 0.2))
	h.barrel_grain = mcyl(root, 0.5, 0.5, 0.05, paddy_material(), Vector3(L.BARREL.x, 0.05, L.BARREL.y), 18)

	# Cuộn bạt, đống gạch, gạch chặn góc
	var tarp_m := _plastic(Color(0.13, 0.36, 0.78))
	var roll := mcyl(root, 0.2, 0.2, 1.6, tarp_m, Vector3(L.TARP_ROLL.x, 0.2, L.TARP_ROLL.y), 16)
	roll.rotation = Vector3(0, 0, PI / 2)
	for i in 8:
		mbox(root, Vector3(0.22, 0.07, 0.11), brick, Vector3(L.BRICK_PILE.x + (i % 2) * 0.25, 0.04 + int(i / 2) * 0.072, L.BRICK_PILE.y), Vector3(0, randf_range(-0.05, 0.05), 0))
	h.corner_bricks = []
	h.corner_marks = []
	for c in L.CORNERS:
		var br := mbox(root, Vector3(0.22, 0.08, 0.11), brick, Vector3(c.x, 0.12, c.y))
		br.visible = false
		h.corner_bricks.append(br)
		var ring := TorusMesh.new()
		ring.inner_radius = 0.18
		ring.outer_radius = 0.24
		var mk := add_mesh(root, ring, Color("ffe08a"), Vector3(c.x, 0.04, c.y), Vector3.ZERO, false)
		mk.material_override = mat(Color("ffe08a"), false, true)
		mk.visible = false
		h.corner_marks.append(mk)
	var tarp_mesh := PlaneMesh.new()
	tarp_mesh.size = Vector2(L.TARP.x1 - L.TARP.x0 + 0.4, L.TARP.z1 - L.TARP.z0 + 0.4)
	tarp_mesh.subdivide_width = 8
	tarp_mesh.subdivide_depth = 8
	var tarp := add_mesh(root, tarp_mesh, Color.WHITE, Vector3((L.TARP.x0 + L.TARP.x1) / 2.0, 0.6, (L.TARP.z0 + L.TARP.z1) / 2.0))
	tarp.material_override = tarp_m
	tarp.visible = false
	h.tarp = tarp
	place(root, "wooden_crate_01", Vector3(6.8, 0.0, -20.6), 1.0, 0.3)

	# Thúng ngâm thóc + vạt mạ + bình tưới
	place_part(root, "wicker_basket_02", Vector3(L.BASKET.x, 0.0, L.BASKET.y), 2.6, 0.4).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	h.basket_water = mcyl(root, 0.38, 0.38, 0.02, water_material("canal"), Vector3(L.BASKET.x, 0.42, L.BASKET.y), 20)
	h.basket_water.visible = false
	mbox(root, Vector3(4, 0.12, 3), A.pbr("brown_mud_03", 1.2), Vector3(L.NURSERY.x, 0.06, L.NURSERY.y), Vector3.ZERO, false)
	place(root, "watering_can_metal_01", Vector3(L.NURSERY.x - 2.4, 0.0, L.NURSERY.y + 1.2), 1.2, 2.2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var smi := F.seedling_bed(root, Vector3(L.NURSERY.x, 0.12, L.NURSERY.y), Vector2(3.7, 2.7), 300, rng)
	h.seedlings = smi

	# Chuồng vịt: bamboo fence, thatched shelter, gate on the west side
	var p: Dictionary = L.DUCK_PEN
	var pcx: float = (p.x0 + p.x1) / 2.0
	var pcz: float = (p.z0 + p.z1) / 2.0
	_fence(root, Vector3(p.x0, 0, p.z0), Vector3(p.x1, 0, p.z0), bamboo_m)
	_fence(root, Vector3(p.x0, 0, p.z1), Vector3(p.x1, 0, p.z1), bamboo_m)
	_fence(root, Vector3(p.x1, 0, p.z0), Vector3(p.x1, 0, p.z1), bamboo_m)
	_fence(root, Vector3(p.x0, 0, p.z0), Vector3(p.x0, 0, p.z0 + 1.2), bamboo_m)
	_fence(root, Vector3(p.x0, 0, p.z1 - 1.2), Vector3(p.x0, 0, p.z1), bamboo_m)
	var dgate := Node3D.new()
	dgate.position = Vector3(p.x0, 0, p.z0 + 1.2)
	root.add_child(dgate)
	_fence(dgate, Vector3(0, 0, 0.05), Vector3(0, 0, 1.55), bamboo_m)
	h.duck_gate = dgate
	var thatch := A.pbr("thatch_roof_angled", 1.4)
	mbox(root, Vector3(2.4, 0.12, 2.4), thatch, Vector3(p.x1 - 1.1, 1.05, p.z0 + 1.1), Vector3(0.18, 0, 0))
	for c in [Vector2(p.x1 - 2.2, p.z0 + 0.1), Vector2(p.x1 - 0.1, p.z0 + 0.1), Vector2(p.x1 - 2.2, p.z0 + 2.1), Vector2(p.x1 - 0.1, p.z0 + 2.1)]:
		mcyl(root, 0.04, 0.04, 1.1, bamboo_m, Vector3(c.x, 0.55, c.y), 6)
	mbox(root, Vector3(2.0, 0.04, 2.0), A.pbr("thatch_roof_angled", 0.8, true, Color(1.0, 0.9, 0.7)), Vector3(p.x1 - 1.1, 0.02, p.z0 + 1.1), Vector3.ZERO, false)
	h.duck_eggs = []
	var shell := StandardMaterial3D.new()
	shell.albedo_color = Color(0.96, 0.94, 0.88)
	shell.roughness = 0.4
	for i in 8:
		var e := sphere(root, 0.05, Color.WHITE, Vector3(p.x1 - 1.4 + (i % 4) * 0.2, 0.08, p.z0 + 0.6 + int(i / 4) * 0.2), Vector3(1, 1.3, 1))
		e.material_override = shell
		e.visible = false
		h.duck_eggs.append(e)

	# Chuồng lợn, máng, hầm biogas, bếp củi, thớt
	var wall := wall_material(Color(0.82, 0.8, 0.74), 0.0, 0.8, 0.8)
	mbox(root, Vector3(4, 0.8, 0.14), wall, Vector3(L.PIG.x, 0.4, L.PIG.y - 2))
	mbox(root, Vector3(4, 0.8, 0.14), wall, Vector3(L.PIG.x, 0.4, L.PIG.y + 2))
	mbox(root, Vector3(0.14, 0.8, 4), wall, Vector3(L.PIG.x - 2, 0.4, L.PIG.y))
	mbox(root, Vector3(0.14, 0.8, 4), wall, Vector3(L.PIG.x + 2, 0.4, L.PIG.y))
	mbox(root, Vector3(4, 0.04, 4), A.pbr("dirt", 1.0, true, Color(0.7, 0.7, 0.7)), Vector3(L.PIG.x, 0.02, L.PIG.y), Vector3.ZERO, false)
	mbox(root, Vector3(4.6, 0.14, 2.6), thatch, Vector3(L.PIG.x, 1.75, L.PIG.y - 1.1), Vector3(-0.2, 0, 0))
	for x in [L.PIG.x - 2, L.PIG.x + 2]:
		mcyl(root, 0.06, 0.06, 1.8, wood, Vector3(x, 0.9, L.PIG.y), 6)
	h.pig = _pig(root)
	mbox(root, Vector3(0.4, 0.25, 1.2), A.pbr("dirt", 0.6, true, Color(0.7, 0.7, 0.68)), Vector3(L.TROUGH.x, 0.12, L.TROUGH.y))
	var dome := sphere(root, 1.2, Color.WHITE, Vector3(L.BIOGAS.x, 0, L.BIOGAS.y), Vector3(1, 0.6, 1))
	dome.material_override = A.pbr("yellow_plaster", 1.2, true, Color(0.72, 0.72, 0.68))
	cyl(root, 0.04, 0.04, 1.2, Color("2b2b2b"), Vector3(L.BIOGAS.x, 1.2, L.BIOGAS.y), 8)
	place(root, "stone_fire_pit", Vector3(L.STOVE.x, 0.13, L.STOVE.y), 0.6)
	for i in 4:
		var log := mcyl(root, 0.05, 0.06, 0.9, wood, Vector3(L.STOVE.x + 0.55 + i * 0.13, 0.06, L.STOVE.y + 0.45), 7)
		log.rotation = Vector3(PI / 2, 0.15 * i, 0)
	h.pot = place(root, "ceramic_pot", Vector3(L.STOVE.x, 0.3, L.STOVE.y), 1.0)
	place(root, "tree_stump_01", Vector3(L.BOARD.x, 0.06, L.BOARD.y), 0.42, 0.7)
	place(root, "hatchet", Vector3(L.BOARD.x + 0.1, 0.3, L.BOARD.y), 1.4, 1.2).rotation.z = PI / 2
	place(root, "wicker_basket_01", Vector3(L.POND_EDGE.x + 0.5, L.ground_y(L.POND_EDGE.x + 0.5, L.POND_EDGE.y + 0.8) - 0.02, L.POND_EDGE.y + 0.8), 2.0, 0.5)
	place(root, "wooden_bucket_01", Vector3(-9.4, L.ground_y(-9.4, 1.6) - 0.02, 1.6), 0.9, 0.3)
	# Contact shadows under the props that stand on the ground.
	for d in [[L.BARREL, 1.6], [Vector2(6.8, -20.6), 1.0], [L.BASKET, 1.1], [L.STOVE, 1.3], [L.BOARD, 0.9],
			[Vector2(L.BIOGAS.x, L.BIOGAS.y), 3.0], [Vector2(L.POND_EDGE.x + 0.5, L.POND_EDGE.y + 0.8), 0.9], [Vector2(-9.4, 1.6), 0.6]]:
		var c: Vector2 = d[0]
		_shadow_decal(root, Vector3(c.x, 0, c.y), Vector2(d[1], d[1]), 0.6)

	h.buffalo = _buffalo(root)


static func _fence(parent: Node3D, a: Vector3, b: Vector3, m: Material) -> void:
	var d := b - a
	var n := maxi(2, int(d.length() / 0.5) + 1)
	for i in n:
		var p := a.lerp(b, float(i) / (n - 1))
		mcyl(parent, 0.03, 0.035, 0.75, m, p + Vector3(0, 0.37, 0), 6)
	for y in [0.2, 0.55]:
		var rail := mcyl(parent, 0.022, 0.022, d.length(), m, (a + b) / 2.0 + Vector3(0, y, 0), 6)
		rail.rotation = Vector3(PI / 2, atan2(d.x, d.z), 0)


# Ỉn: a photo-textured pig model (CC-BY 4.0, see assets/CREDITS.md). The
# model faces +z; the node is turned so the pig faces +x, as before.
static func _pig(root: Node3D) -> Node3D:
	var pig := Node3D.new()
	pig.position = Vector3(L.PIG.x + 0.5, 0.0, L.PIG.y)
	root.add_child(pig)
	var model := A.model("pig")
	model.rotation.y = PI / 2
	model.scale = Vector3.ONE * 1.05
	pig.add_child(model)
	_matte(model, 0.78)
	_shadow_decal(pig, Vector3.ZERO, Vector2(1.9, 0.9), 0.65, PI / 2)
	return pig


# Sketchfab exports set roughness 0 (mirror-like); make their skins matte.
static func _matte(n: Node, rough: float) -> void:
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		for s in mi.mesh.get_surface_count():
			var m := mi.get_active_material(s)
			if m is BaseMaterial3D:
				var d := (m as BaseMaterial3D).duplicate() as BaseMaterial3D
				d.roughness = rough
				d.metallic = 0.0
				d.metallic_specular = 0.35
				mi.set_surface_override_material(s, d)
	for c in n.get_children():
		_matte(c, rough)


# Lofted body: ellipse cross-sections [centre, half width (z), half height]
# along a path, capped at both ends. Colour per vertex from `paint`.
static func loft(sections: Array, seg: int, paint: Callable, side := Vector3(0, 0, 1)) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := sections.size()
	var rings := []
	for i in n:
		var c: Vector3 = sections[i][0]
		var prev: Vector3 = sections[maxi(i - 1, 0)][0]
		var next: Vector3 = sections[mini(i + 1, n - 1)][0]
		var t := (next - prev).normalized()
		var up := side.cross(t).normalized()
		if up.length() < 0.5:
			up = Vector3.UP
		var sd := t.cross(up).normalized()
		var ring := []
		for k in seg:
			var a := TAU * k / seg
			ring.append(c + sd * cos(a) * float(sections[i][1]) + up * sin(a) * float(sections[i][2]))
		rings.append(ring)
	var idx := 0
	var verts := []
	for i in n:
		for k in seg:
			verts.append(rings[i][k])
	for p in verts:
		st.set_color(paint.call(p))
		st.add_vertex(p)
	for i in n - 1:
		for k in seg:
			var a := i * seg + k
			var b := i * seg + (k + 1) % seg
			var c := (i + 1) * seg + k
			var d := (i + 1) * seg + (k + 1) % seg
			# Godot's front faces wind clockwise seen from outside.
			for q in [a, b, c, b, d, c]:
				st.add_index(q)
	# End caps: a centre point per end.
	for e: int in [0, n - 1]:
		var cp: Vector3 = sections[e][0]
		st.set_color(paint.call(cp))
		st.add_vertex(cp)
		var ci := verts.size() + (0 if e == 0 else 1)
		for k in seg:
			var a := e * seg + k
			var b := e * seg + (k + 1) % seg
			if e == 0:
				for q in [ci, b, a]:
					st.add_index(q)
			else:
				for q in [ci, a, b]:
					st.add_index(q)
	st.generate_normals()
	return st.commit()


static func _skin(rough: float, wrinkle := 0.35) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.roughness = rough
	m.normal_enabled = true
	m.normal_texture = A.tex("brown_mud_03", "nor")
	m.normal_scale = wrinkle
	m.uv1_triplanar = true
	m.uv1_scale = Vector3.ONE * 2.0
	return m


# Trâu: a Vietnamese swamp buffalo. Slate-grey barrel body with a shoulder
# hump, head carried low, pale chevron on the throat, lighter legs caked
# with paddy mud, and dark crescent horns swept back.
static func _buffalo(root: Node3D) -> Node3D:
	var buff := Node3D.new()
	buff.position = Vector3(L.BUFFALO.x, L.ground_y(L.BUFFALO.x, L.BUFFALO.y) - 0.02, L.BUFFALO.y)
	buff.rotation.y = 0.3
	root.add_child(buff)
	var hide := Color(0.3, 0.29, 0.29)
	var pale := Color(0.45, 0.43, 0.41)
	var mud := Color(0.3, 0.24, 0.17)
	var noise := FastNoiseLite.new()
	noise.frequency = 6.0
	var paint := func(p: Vector3) -> Color:
		var c := hide.lerp(pale, smoothstep(0.62, 0.42, p.y) * 0.6)
		# Pale chevron across the throat.
		if p.x > 0.95 and p.y < 0.86 and absf(p.y - (0.9 - (p.x - 0.95) * 0.5)) < 0.05:
			c = Color(0.62, 0.58, 0.55)
		var m := smoothstep(0.52, 0.36, p.y + noise.get_noise_3d(p.x, p.y, p.z) * 0.08)
		c = c.lerp(mud, m * 0.9)
		return c.darkened(noise.get_noise_3d(p.x * 0.3, p.y * 0.3, p.z * 0.3) * 0.08)
	var skin := _skin(0.72)
	var body := MeshInstance3D.new()
	body.mesh = loft([
		[Vector3(-1.27, 1.0, 0), 0.1, 0.14],
		[Vector3(-1.2, 0.98, 0), 0.3, 0.33],
		[Vector3(-1.0, 0.95, 0), 0.42, 0.43],
		[Vector3(-0.62, 0.92, 0), 0.46, 0.47],
		[Vector3(-0.2, 0.9, 0), 0.5, 0.52],
		[Vector3(0.2, 0.93, 0), 0.49, 0.53],
		[Vector3(0.55, 0.98, 0), 0.44, 0.52],
		[Vector3(0.82, 0.97, 0), 0.36, 0.44],
		[Vector3(1.02, 0.93, 0), 0.29, 0.36],
		[Vector3(1.22, 0.87, 0), 0.24, 0.28],
		[Vector3(1.36, 0.84, 0), 0.2, 0.22],
	], 20, paint)
	body.material_override = skin
	buff.add_child(body)
	# Legs: thigh, knee or hock, cannon bone, fetlock, hoof.
	for leg in [[0.55, 0.0, 1.0], [-0.88, -0.12, 1.15]]:
		for s in [-1.0, 1.0]:
			var x: float = leg[0]
			var b: float = leg[1]
			var w: float = leg[2]
			var lm := MeshInstance3D.new()
			lm.mesh = loft([
				[Vector3(x, 0.85, s * 0.26), 0.2 * w, 0.22 * w],
				[Vector3(x + b * 0.4, 0.58, s * 0.26), 0.14 * w, 0.15 * w],
				[Vector3(x + b, 0.42, s * 0.25), 0.1, 0.11],
				[Vector3(x + b * 0.6, 0.2, s * 0.25), 0.075, 0.08],
				[Vector3(x + b * 0.55, 0.09, s * 0.25), 0.085, 0.085],
				[Vector3(x + b * 0.5 + 0.02, 0.0, s * 0.25), 0.09, 0.085],
			], 10, paint, Vector3(1, 0, 0))
			lm.material_override = skin
			buff.add_child(lm)
	# Head on its own pivot so it can nod while grazing.
	var head := Node3D.new()
	head.position = Vector3(1.3, 0.88, 0)
	buff.add_child(head)
	var hm := MeshInstance3D.new()
	hm.mesh = loft([
		[Vector3(0.0, 0.0, 0), 0.2, 0.23],
		[Vector3(0.14, -0.01, 0), 0.22, 0.24],
		[Vector3(0.3, -0.08, 0), 0.18, 0.19],
		[Vector3(0.48, -0.18, 0), 0.135, 0.145],
		[Vector3(0.63, -0.27, 0), 0.13, 0.115],
		[Vector3(0.73, -0.31, 0), 0.115, 0.09],
	], 16, func(p: Vector3) -> Color:
		var c: Color = paint.call(p + Vector3(1.3, 0.88, 0))
		return c.lerp(Color(0.1, 0.095, 0.09), smoothstep(0.5, 0.62, p.x))) # dark wet muzzle
	hm.material_override = skin
	head.add_child(hm)
	var horn_m := StandardMaterial3D.new()
	horn_m.albedo_color = Color(0.2, 0.18, 0.16)
	horn_m.roughness = 0.45
	horn_m.normal_enabled = true
	horn_m.normal_texture = A.tex("weathered_planks", "nor")
	horn_m.normal_scale = 0.6
	horn_m.uv1_triplanar = true
	horn_m.uv1_scale = Vector3(6, 6, 6)
	var eye_m := mat(Color(0.03, 0.025, 0.02))
	var ear_m := StandardMaterial3D.new()
	ear_m.albedo_color = hide
	ear_m.roughness = 0.75
	for s in [-1.0, 1.0]:
		# Crescent horn: out, back and a little up, tapering to a point.
		var secs := []
		for k in 11:
			var t := k / 10.0
			var th := t * 2.6
			var r := 0.5
			var p := Vector3(0.14 + r * (cos(th) - 1.0) * 0.85, 0.17 + 0.12 * t + 0.1 * sin(th), s * (0.14 + r * sin(th)))
			secs.append([p, lerpf(0.095, 0.014, t), lerpf(0.07, 0.014, t)])
		var hn := MeshInstance3D.new()
		hn.mesh = loft(secs, 10, func(_p: Vector3) -> Color: return Color.WHITE, Vector3.UP)
		hn.material_override = horn_m
		head.add_child(hn)
		var ear := sphere(head, 0.11, Color.WHITE, Vector3(0.05, 0.04, s * 0.28), Vector3(0.45, 0.25, 1.0))
		ear.rotation = Vector3(s * 0.35, 0, 0)
		ear.material_override = ear_m
		sphere(head, 0.028, Color.WHITE, Vector3(0.24, 0.03, s * 0.175)).material_override = eye_m
	var tail := MeshInstance3D.new()
	tail.mesh = loft([
		[Vector3(-1.25, 1.08, 0), 0.04, 0.04],
		[Vector3(-1.33, 0.9, 0), 0.025, 0.025],
		[Vector3(-1.36, 0.6, 0), 0.02, 0.02],
		[Vector3(-1.36, 0.45, 0), 0.045, 0.035],
		[Vector3(-1.36, 0.36, 0), 0.01, 0.01],
	], 8, func(p: Vector3) -> Color: return Color(0.12, 0.11, 0.1) if p.y < 0.5 else hide, Vector3(1, 0, 0))
	tail.material_override = skin
	buff.add_child(tail)
	var idle := IDLE.new()
	idle.head = head
	idle.tail = tail
	buff.add_child(idle)
	_shadow_decal(buff, Vector3(0, 0, 0), Vector2(3.2, 1.5), 0.7)
	return buff


# ---------------------------------------------------------------- vegetation & distance
static func _plants(root: Node3D) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 2024
	# grove centres, for the lawn's thinner grass in the bamboo shade
	var groves := _trees(root)

	# The lawn: dense short blades that follow the camera (grass_lawn.gd),
	# masked off the paddy, yard, paths, house, canal and pond. No shadows.
	var lawn: Node3D = preload("res://scripts/grass_lawn.gd").new()
	lawn.name = "Lawn"
	# thinner, drier grass in the shade of the bamboo clumps
	for g in groves:
		lawn.shade_spots.append(Vector3(g.x, g.y, 4.0))
	root.add_child(lawn)
	# Taller, thin-bladed tufts only where grass grows rank: bund tops and
	# canal banks.
	var tall := []
	var b: float = L.FIELD.bund
	for i in 700:
		var t := rng.randf_range(-8.6, 8.6)
		var off: float = L.FIELD.x1 + b * rng.randf_range(0.15, 0.85)
		var pos: Array = [[t, -off], [t, off], [-off, t], [off, t]][i % 4]
		if Vector2(pos[0], pos[1]).distance_to(L.GATE) < 1.0 or Vector2(pos[0], pos[1]).distance_to(L.DRAIN) < 0.9:
			continue
		tall.append(Vector3(pos[0], L.FIELD.bund_top, pos[1]))
	for i in 500:
		var x: float = [L.CANAL.x0 - 0.25, L.CANAL.x1 + 0.25][i % 2] + rng.randf_range(-0.2, 0.2)
		tall.append(Vector3(x, 0, rng.randf_range(-34, 30)))
	F.grass(root, tall, F.tuft_mesh(16, 0.42, 0.0055), rng, 0.15, 8.0, 40.0)

	# Poly Haven plants and rocks around the edges
	# shrub_04 is a 22 cm model and the nettle parts 2-22 cm: scaled up so
	# they stand out of the 10-28 cm lawn. Each shrub gets a fern beside it,
	# not on top of it. Nettles grow where the lawn stops: along the house,
	# sheds and pens, and on the pond rim.
	var weeds := []
	var shrubs := []
	var ferns := []
	var rocks := []
	for i in 50:
		var x := rng.randf_range(-30, 30)
		var z := rng.randf_range(-34, 28)
		if not _clear_for_grass(x, z):
			continue
		shrubs.append([Vector3(x, L.ground_y(x, z), z), rng.randf() * TAU, rng.randf_range(2.5, 4.0)])
		var a := rng.randf() * TAU
		var d := rng.randf_range(0.6, 1.2)
		var f := Vector2(x + cos(a) * d, z + sin(a) * d)
		if _clear_for_grass(f.x, f.y):
			ferns.append([Vector3(f.x, L.ground_y(f.x, f.y), f.y), rng.randf() * TAU, rng.randf_range(1.5, 2.5)])
	var walls: Array = L.BLOCKERS.duplicate()
	walls.append([L.DUCK_PEN.x0, L.DUCK_PEN.x1, L.DUCK_PEN.z0, L.DUCK_PEN.z1])
	for rc in walls:
		var per: float = 2.0 * ((rc[1] - rc[0]) + (rc[3] - rc[2]))
		for k in int(per / 2.5):
			# a point on the rectangle's outline, 15-35 cm outside it
			var u := rng.randf() * per
			var o := rng.randf_range(0.15, 0.35)
			var q: Vector2
			var w: float = rc[1] - rc[0]
			var h: float = rc[3] - rc[2]
			if u < w:
				q = Vector2(rc[0] + u, rc[2] - o)
			elif u < w + h:
				q = Vector2(rc[1] + o, rc[2] + u - w)
			elif u < 2.0 * w + h:
				q = Vector2(rc[1] - (u - w - h), rc[3] + o)
			else:
				q = Vector2(rc[0] - o, rc[3] - (u - 2.0 * w - h))
			if L.in_court(q.x, q.y) or L.blocked(q.x, q.y) or L.in_field(q.x, q.y, L.FIELD.bund + 0.3):
				continue
			weeds.append([Vector3(q.x, L.ground_y(q.x, q.y), q.y), rng.randf() * TAU, rng.randf_range(2.0, 3.0)])
	for i in 18:
		var a := rng.randf() * TAU
		var r: float = L.POND.r + rng.randf_range(0.25, 0.5)
		var q := Vector2(L.POND.x + cos(a) * r, L.POND.z + sin(a) * r)
		weeds.append([Vector3(q.x, L.ground_y(q.x, q.y), q.y), rng.randf() * TAU, rng.randf_range(2.0, 3.0)])
	# River stones on the pond rim and canal banks: grey, half buried, a few
	# small ones beside each bigger one.
	for i in 22:
		var a := rng.randf() * TAU
		var r: float = L.POND.r + rng.randf_range(0.25, 0.9)
		rocks.append([Vector3(L.POND.x + cos(a) * r, 0.0, L.POND.z + sin(a) * r), rng.randf() * TAU, rng.randf_range(1.0, 2.0)])
	for i in 26:
		rocks.append([Vector3([L.CANAL.x0 - 0.35, L.CANAL.x1 + 0.35][i % 2] + rng.randf_range(-0.15, 0.15), 0.0, rng.randf_range(-30, 26)), rng.randf() * TAU, rng.randf_range(1.0, 2.0)])
	# Every stone sits on the real ground height; none in the canal or the
	# pond water (the canal floor is 0.75 m down, so they would float).
	var stones := []
	for p in rocks:
		if _stone_ok(p[0]):
			stones.append(p)
	var pebbles := []
	for p in stones:
		for k in 2:
			var q: Vector3 = p[0] + Vector3(rng.randf_range(-0.5, 0.5), 0.0, rng.randf_range(-0.5, 0.5))
			if _stone_ok(q):
				pebbles.append([q, rng.randf() * TAU, rng.randf_range(0.6, 1.2)])
	for p in stones + pebbles:
		var v: Vector3 = p[0]
		p[0] = Vector3(v.x, L.ground_y(v.x, v.z), v.z)
	rocks = stones
	# knee-high weeds cast no shadows (one less pass per cascade).
	# weed_plant_02 is dropped: its parts are 4-7 cm tall, invisible in the
	# lawn at any sane scale.
	A.scatter(root, "nettle_plant", weeds, false, 30.0)
	A.scatter(root, "shrub_04", shrubs, true, 40.0)
	A.scatter(root, "fern_02", ferns, true, 40.0)
	A.scatter(root, "rock_07", rocks, true, 45.0, 0.22, A.recolor("rock_07", 0.25, Color(0.95, 0.95, 0.93), 1.35))
	A.scatter(root, "stone_01", pebbles, false, 25.0, 0.35, A.recolor("stone_01", 0.2, Color(0.86, 0.87, 0.88), 1.1))


static func _stone_ok(q: Vector3) -> bool:
	if q.x > L.CANAL.x0 - 0.05 and q.x < L.CANAL.x1 + 0.05:
		return false
	return Vector2(q.x - L.POND.x, q.z - L.POND.z).length() > L.POND.r + 0.2


# Village trees. A lũy tre hedge closes the homestead on the north, west and
# east (the south opens onto the paddies), bananas and areca palms stand in
# the garden, and across the paddies other villages read as dark islands of
# bamboo with palms and fruit trees rising above them.
static func _trees(root: Node3D) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = 2025
	var groves := [Vector2(-24, -30), Vector2(24, -26), Vector2(-26, 18), Vector2(20, 22), Vector2(26, -6), Vector2(-6, -34), Vector2(10, -33)]
	# the hedge: clumps every ~4.5 m so their arching crowns close into a wall
	for i in 15:
		groves.append(Vector2(-32 + i * 4.6 + rng.randf_range(-1.0, 1.0), -38.5 + rng.randf_range(-1.2, 1.2)))
	for i in 11:
		var z := -34.0 + i * 4.8 + rng.randf_range(-1.0, 1.0)
		groves.append(Vector2(-34 + rng.randf_range(-1.2, 1.2), z))
		if i < 10:
			groves.append(Vector2(34 + rng.randf_range(-1.2, 1.2), z))
	# the hedge bends round the south-west and south-east corners
	for g in [Vector2(-31, 19), Vector2(-28, 23), Vector2(31, 14), Vector2(28, 19), Vector2(24, 24)]:
		groves.append(g + Vector2(rng.randf_range(-1, 1), rng.randf_range(-1, 1)))
	for g in groves:
		F.bamboo(root, Vector3(g.x, 0, g.y), rng, rng.randf_range(0.85, 1.1))
	for p in [Vector2(8, -24), Vector2(11, -23), Vector2(-12, -18), Vector2(17, -12), Vector2(-15, 3), Vector2(-24, -14), Vector2(7, -31),
			Vector2(-9, -31), Vector2(14, -27), Vector2(-22, -21), Vector2(21, -16), Vector2(-27, -2), Vector2(24, 4)]:
		F.banana(root, Vector3(p.x, 0, p.y), rng)
	for p in [Vector2(-8, -30), Vector2(7, -29), Vector2(-14, 14), Vector2(15, -2), Vector2(-24, -18), Vector2(-3, -31), Vector2(18, -24), Vector2(-29, 8)]:
		F.palm(root, Vector3(p.x, 0, p.y), rng, false)
	for p in [Vector2(22, 12), Vector2(-17, -4), Vector2(-21, -5)]:
		F.palm(root, Vector3(p.x, 0, p.y), rng, true)
	# Other villages across the paddies: [centre x, centre z, radius].
	# Gaps between them leave the karst towers in view.
	for v in [[-60, 85, 22], [45, 110, 28], [-15, 165, 30], [95, 15, 25], [80, -75, 22], [150, 60, 30],
			[-90, 35, 26], [-85, -55, 24], [-150, -10, 30], [-35, -100, 26], [40, -115, 30], [0, -170, 35]]:
		_village(root, Vector2(v[0], v[1]), v[2], rng)
	return groves


static func _village(root: Node3D, c: Vector2, rad: float, rng: RandomNumberGenerator) -> void:
	var items := []
	var p1 := rng.randf() * TAU
	var p2 := rng.randf() * TAU
	var r_at := func(a: float) -> float: return rad * (1.0 + 0.18 * sin(2.0 * a + p1) + 0.1 * sin(3.0 * a + p2))
	# the bamboo ring, a clump every ~4 m, with a staggered inner row
	var n := int(TAU * rad / 4.0)
	for i in n * 3 / 2:
		var a := (i % n + (0.5 if i >= n else 0.0) + rng.randf_range(-0.3, 0.3)) / n * TAU
		var r: float = r_at.call(a) + rng.randf_range(-1.5, 1.5) - (4.0 if i >= n else 0.0)
		var s := rng.randf_range(0.8, 1.2)
		items.append([F.bamboo_mesh(rng.randi() % F.BAMBOO_VARIANTS, 3), Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * s), Vector3(c.x + cos(a) * r, 0.0, c.y + sin(a) * r))])
	# fruit trees, areca and coconut palms inside, above the bamboo
	for i in int(rad * 0.8):
		var a := rng.randf() * TAU
		var r: float = r_at.call(a) * sqrt(rng.randf()) * 0.8
		var pos := Vector3(c.x + cos(a) * r, 0.0, c.y + sin(a) * r)
		var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(0.85, 1.2))
		var kind := rng.randf()
		var mesh: Mesh
		if kind < 0.55:
			mesh = F.village_tree_mesh(rng.randi() % 12)
		elif kind < 0.85:
			mesh = F.palm_mesh(rng.randi() % 10, false, 1)
		else:
			mesh = F.palm_mesh(rng.randi() % 10, true, 1)
		items.append([mesh, Transform3D(basis, pos)])
	F.far_group(root, items)


static func _clear_for_grass(x: float, z: float) -> bool:
	if L.in_field(x, z, L.FIELD.bund + 0.3) or L.in_court(x, z) or L.in_pen(x, z) or L.blocked(x, z):
		return false
	if x > L.CANAL.x0 - 0.5 and x < L.CANAL.x1 + 0.5:
		return false
	if Vector2(x - L.POND.x, z - L.POND.z).length() < L.POND.r + 0.6:
		return false
	if Vector2(x, z).distance_to(L.NURSERY) < 2.8 or Vector2(x, z).distance_to(L.BUFFALO) < 1.5:
		return false
	if absf(x) < 6.5 and z < -13.0 and z > -29.0: # courtyard and veranda
		return false
	return true


# Karst towers (núi đá vôi) on the horizon, like Ninh Bình: steep fluted
# limestone with jungle on the ledges and crowns, in clusters at 180-320 m
# and a taller, hazier ring at 380-550 m so the silhouettes layer.
static func _hills(root: Node3D) -> void:
	var t0 := Time.get_ticks_msec()
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	noise.fractal_octaves = 5
	noise.frequency = 0.9
	var m := ShaderMaterial.new()
	m.shader = KARST
	m.set_shader_parameter("rock_alb", A.tex("rock_pitted_mossy", "diff"))
	m.set_shader_parameter("rock_nor", A.tex("rock_pitted_mossy", "nor"))
	var towers := []
	# [angle, radius] of each cluster; angle 0 = east, PI/2 = south.
	for c in [[1.62, 235.0], [3.55, 265.0], [5.15, 215.0], [0.55, 300.0]]:
		var n := rng.randi_range(5, 8)
		for k in n:
			var a: float = c[0] + rng.randf_range(-0.2, 0.2)
			var r: float = c[1] + rng.randf_range(-45.0, 45.0)
			var hgt := rng.randf_range(38.0, 80.0)
			towers.append([a, r, hgt, hgt * rng.randf_range(0.36, 0.52), 56, 40])
	for k in 24:
		var a := k / 24.0 * TAU + rng.randf_range(-0.1, 0.1)
		var fh := rng.randf_range(70.0, 140.0)
		towers.append([a, rng.randf_range(380.0, 550.0), fh, fh * rng.randf_range(0.4, 0.6), 32, 24])
	for i in towers.size():
		var t: Array = towers[i]
		var mi := MeshInstance3D.new()
		mi.mesh = _tower(noise, i, t[3], t[2], t[4], t[5], rng)
		mi.material_override = m
		mi.position = Vector3(cos(t[0]) * t[1], -3.0, sin(t[0]) * t[1])
		mi.rotation.y = rng.randf() * TAU
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)
	print("karst built in %d ms" % (Time.get_ticks_msec() - t0))


static func _tower(noise: FastNoiseLite, i: int, rad: float, hgt: float, segs: int, rings: int, rng: RandomNumberGenerator) -> ArrayMesh:
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	sm.radial_segments = segs
	sm.rings = rings
	var arr := sm.get_mesh_arrays()
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var lean := Vector2(rng.randf_range(-0.15, 0.15), rng.randf_range(-0.15, 0.15))
	var crown := rng.randf_range(4.0, 7.0) # higher = flatter, squarer top
	for k in verts.size():
		var v := verts[k]
		var y := maxf(v.y, -0.25)
		# Near-vertical walls, a rounded crown and a talus flare at the foot.
		var w := sqrt(maxf(0.0, 1.0 - pow(clampf(y, 0.0, 1.0), crown))) if y > 0.0 else 1.0
		w *= 1.0 + 0.35 * (1.0 - smoothstep(-0.25, 0.12, y))
		# Vertical fluting and horizontal ledges from ridged noise, lumps on the crown.
		var n := noise.get_noise_3d(v.x * 1.5 + i * 13.0, y * 0.5, v.z * 1.5) * 0.22
		n += noise.get_noise_3d(v.x * 6.0 + i * 7.0, y * 4.0, v.z * 6.0) * 0.08
		var lump := noise.get_noise_3d(v.x * 0.7 + i * 3.0, 9.0, v.z * 0.7) * 0.18
		var yy := (y + 0.25) * hgt * (1.0 + lump * smoothstep(0.5, 1.0, y) + n * 0.06)
		verts[k] = Vector3(v.x * rad * w * (1.0 + n) + lean.x * yy, yy, v.z * rad * w * (1.0 + n) + lean.y * yy)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = null
	arr[Mesh.ARRAY_TANGENT] = null
	arr[Mesh.ARRAY_TEX_UV] = null
	var st := SurfaceTool.new()
	st.create_from_arrays(arr)
	st.generate_normals()
	arr = st.commit_to_arrays()
	verts = arr[Mesh.ARRAY_VERTEX]
	var nrm: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	var cols := PackedColorArray()
	cols.resize(verts.size())
	for k in verts.size():
		# Jungle on anything flat enough to hold soil, and on the scree at the foot.
		# Only the sheerest faces stay bare; scrub clings to everything else.
		var bare := noise.get_noise_3d(verts[k].x * 0.06, verts[k].y * 0.012, verts[k].z * 0.06) * 0.35
		var g := smoothstep(0.0, 0.4, nrm[k].y + bare)
		g = maxf(g, 1.0 - smoothstep(0.08, 0.22, verts[k].y / hgt))
		cols[k] = Color(g, 0, 0)
	arr[Mesh.ARRAY_COLOR] = cols
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return mesh


static func build(root: Node3D) -> Dictionary:
	var h := {}
	_ground(root, h)
	_house(root, h)
	_props(root, h)
	_plants(root)
	_hills(root)
	return h
