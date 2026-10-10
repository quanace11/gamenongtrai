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
			m.set_shader_parameter("tint", Color(0.22, 0.28, 0.2))
			m.set_shader_parameter("clarity", 0.82)
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
static func _ground(root: Node3D, h: Dictionary) -> void:
	var gm := ShaderMaterial.new()
	gm.shader = GROUND
	gm.set_shader_parameter("grass_alb", A.tex("leafy_grass", "diff"))
	gm.set_shader_parameter("grass_nor", A.tex("leafy_grass", "nor"))
	gm.set_shader_parameter("grass_arm", A.tex("leafy_grass", "arm"))
	gm.set_shader_parameter("path_alb", A.tex("grass_path_2", "diff"))
	gm.set_shader_parameter("path_nor", A.tex("grass_path_2", "nor"))
	gm.set_shader_parameter("mud_alb", A.tex("brown_mud_03", "diff"))
	var S := 220.0
	var b: float = L.FIELD.bund
	var fx0: float = L.FIELD.x0 - b
	var fx1: float = L.FIELD.x1 + b
	# Rectangles of ground around the sunken field and the canal strip.
	var rects := [
		[-S, L.CANAL.x0, -S, S],
		[L.CANAL.x1, fx0, -S, S],
		[fx0, fx1, -S, fx0],
		[fx0, fx1, fx1, S],
		[fx1, S, -S, S],
	]
	for r in rects:
		var p := PlaneMesh.new()
		p.size = Vector2(r[1] - r[0], r[3] - r[2])
		var mi := MeshInstance3D.new()
		mi.mesh = p
		mi.material_override = gm
		mi.position = Vector3((r[0] + r[1]) / 2.0, 0, (r[2] + r[3]) / 2.0)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)

	# Bờ ruộng: packed earth with grass on top
	var bund_m := A.pbr("grass_path_2", 1.6, true, Color(0.8, 0.95, 0.65))
	var size := fx1 - fx0
	var hgt := 0.55
	var yc: float = L.FIELD.bund_top - hgt / 2.0
	mbox(root, Vector3(size, hgt, b), bund_m, Vector3(0, yc, L.FIELD.z0 - b / 2.0), Vector3.ZERO, false)
	mbox(root, Vector3(size, hgt, b), bund_m, Vector3(0, yc, L.FIELD.z1 + b / 2.0), Vector3.ZERO, false)
	mbox(root, Vector3(b, hgt, size), bund_m, Vector3(L.FIELD.x0 - b / 2.0, yc, 0), Vector3.ZERO, false)
	mbox(root, Vector3(b, hgt, size), bund_m, Vector3(L.FIELD.x1 + b / 2.0, yc, 0), Vector3.ZERO, false)

	# Mương: muddy bed, earth banks, murky water
	var cx: float = (L.CANAL.x0 + L.CANAL.x1) / 2.0
	mbox(root, Vector3(2, 0.1, 2 * S), A.pbr("brown_mud_03", 2.0), Vector3(cx, -0.95, 0), Vector3.ZERO, false)
	var bank := A.pbr("dirt", 2.0)
	mbox(root, Vector3(0.1, 0.9, 2 * S), bank, Vector3(L.CANAL.x0, -0.45, 0), Vector3.ZERO, false)
	mbox(root, Vector3(0.1, 0.9, 2 * S), bank, Vector3(L.CANAL.x1, -0.45, 0), Vector3.ZERO, false)
	var water := PlaneMesh.new()
	water.size = Vector2(2, 2 * S)
	var cw := MeshInstance3D.new()
	cw.mesh = water
	cw.material_override = water_material("canal")
	cw.position = Vector3(cx, -0.3, 0)
	root.add_child(cw)
	h.canal_water = cw
	# Rãnh dẫn nước từ mương tới cửa cống, và rãnh xả bờ đông
	var mud := A.pbr("brown_mud_03", 1.5)
	mbox(root, Vector3(1.2, 0.05, 0.9), mud, Vector3(-9.4, 0.0, 0), Vector3.ZERO, false)
	mbox(root, Vector3(0.8, 0.05, 0.7), mud, Vector3(9.2, 0.0, 4), Vector3.ZERO, false)
	for c in [[Vector2(1.2, 0.9), Vector3(-9.4, 0.04, 0)], [Vector2(0.8, 0.7), Vector3(9.2, 0.04, 4)]]:
		var wp := PlaneMesh.new()
		wp.size = c[0]
		var wi := MeshInstance3D.new()
		wi.mesh = wp
		wi.material_override = water_material("canal")
		wi.position = c[1]
		root.add_child(wi)

	# Ao với bèo tây: muddy bank, dark water, hyacinth rosettes with lilac flowers
	var rim := TorusMesh.new()
	rim.inner_radius = L.POND.r - 0.3
	rim.outer_radius = L.POND.r + 0.5
	rim.rings = 48
	var rmi := MeshInstance3D.new()
	rmi.mesh = rim
	rmi.material_override = A.pbr("brown_mud_03", 1.5)
	rmi.position = Vector3(L.POND.x, -0.02, L.POND.z)
	rmi.scale = Vector3(1, 0.12, 1)
	root.add_child(rmi)
	var pond := CylinderMesh.new()
	pond.top_radius = L.POND.r
	pond.bottom_radius = L.POND.r
	pond.height = 0.04
	pond.radial_segments = 48
	var pmi := MeshInstance3D.new()
	pmi.mesh = pond
	pmi.material_override = water_material("pond")
	pmi.position = Vector3(L.POND.x, 0.02, L.POND.z)
	root.add_child(pmi)
	var leaf_m := StandardMaterial3D.new()
	leaf_m.albedo_color = Color(0.22, 0.48, 0.16)
	leaf_m.roughness = 0.3
	var flower_m := StandardMaterial3D.new()
	flower_m.albedo_color = Color(0.72, 0.6, 0.9)
	flower_m.roughness = 0.6
	var leaf := SphereMesh.new()
	leaf.radius = 0.11
	leaf.height = 0.08
	leaf.radial_segments = 10
	leaf.rings = 4
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	for i in 34:
		var a := rng.randf() * TAU
		var rr := sqrt(rng.randf()) * (L.POND.r - 0.7)
		var c := Vector3(L.POND.x + cos(a) * rr, 0.06, L.POND.z + sin(a) * rr)
		for k in 7:
			var la := k * TAU / 7.0 + rng.randf() * 0.4
			var lm := MeshInstance3D.new()
			lm.mesh = leaf
			lm.material_override = leaf_m
			lm.position = c + Vector3(cos(la) * 0.13, 0.05 + rng.randf() * 0.06, sin(la) * 0.13)
			lm.rotation = Vector3(0.5, -la, 0)
			lm.scale = Vector3(1, 1, 1.4)
			root.add_child(lm)
		if rng.randf() < 0.45:
			for k in 5:
				var fm := MeshInstance3D.new()
				var fs := SphereMesh.new()
				fs.radius = 0.035
				fs.height = 0.05
				fm.mesh = fs
				fm.material_override = flower_m
				fm.position = c + Vector3(rng.randf_range(-0.03, 0.03), 0.22 + k * 0.035, rng.randf_range(-0.03, 0.03))
				root.add_child(fm)


# ---------------------------------------------------------------- house & courtyard
static func _house(root: Node3D) -> void:
	# Sân gạch đỏ
	var court := PlaneMesh.new()
	court.size = Vector2(L.COURT.x1 - L.COURT.x0, L.COURT.z1 - L.COURT.z0)
	var cmi := MeshInstance3D.new()
	cmi.mesh = court
	cmi.material_override = A.pbr("red_brick_pavers", 2.6)
	cmi.position = Vector3((L.COURT.x0 + L.COURT.x1) / 2.0, 0.015, (L.COURT.z0 + L.COURT.z1) / 2.0)
	root.add_child(cmi)
	# Khung bạt (vạch vôi)
	var tw: float = L.TARP.x1 - L.TARP.x0
	var td: float = L.TARP.z1 - L.TARP.z0
	var tcx: float = (L.TARP.x0 + L.TARP.x1) / 2.0
	var tcz: float = (L.TARP.z0 + L.TARP.z1) / 2.0
	var line_c := Color("e8e2d0")
	box(root, Vector3(tw, 0.01, 0.05), line_c, Vector3(tcx, 0.025, L.TARP.z0), false)
	box(root, Vector3(tw, 0.01, 0.05), line_c, Vector3(tcx, 0.025, L.TARP.z1), false)
	box(root, Vector3(0.05, 0.01, td), line_c, Vector3(L.TARP.x0, 0.025, tcz), false)
	box(root, Vector3(0.05, 0.01, td), line_c, Vector3(L.TARP.x1, 0.025, tcz), false)

	# Nhà ba gian: yellow lime-plaster walls, wooden columns, red tile roof
	var plaster := A.pbr("yellow_plaster", 2.5, true, Color(1.0, 0.93, 0.78))
	var wood := A.pbr("weathered_planks", 1.2, true, Color(0.75, 0.55, 0.4))
	var door := A.pbr("weathered_planks", 0.9, true, Color(0.7, 0.42, 0.28))
	var plinth := A.pbr("red_brick_pavers", 0.9, true, Color(0.85, 0.8, 0.75))
	mbox(root, Vector3(10, 2.8, 6), plaster, Vector3(0, 1.5, -25.5))
	mbox(root, Vector3(10.6, 0.3, 7.8), plinth, Vector3(0, 0.15, -25.0), Vector3.ZERO, false)
	for x in [-4.6, -1.6, 1.6, 4.6]:
		mcyl(root, 0.11, 0.13, 2.7, wood, Vector3(x, 1.65, -21.6))
		mcyl(root, 0.18, 0.18, 0.12, plinth, Vector3(x, 0.36, -21.6))
	mbox(root, Vector3(10.2, 0.22, 0.18), wood, Vector3(0, 2.95, -21.6))
	for x in [-3.2, 0.0, 3.2]:
		mbox(root, Vector3(1.4, 2.1, 0.08), door, Vector3(x, 1.35, -22.47))
		mbox(root, Vector3(0.04, 2.1, 0.1), wood, Vector3(x, 1.35, -22.42))
		mbox(root, Vector3(1.6, 0.12, 0.14), wood, Vector3(x, 2.46, -22.44))
	# Mái ngói: two tiled slopes, ridge, gable ends
	var tiles := A.pbr("clay_roof_tiles_02", 1.6)
	var slope := atan2(2.0, 4.2)
	var half := 4.2 / cos(slope)
	for s in [-1.0, 1.0]:
		var z: float = -25.25 + s * 2.05
		mbox(root, Vector3(11.4, 0.14, half + 0.4), tiles, Vector3(0, 3.95, z), Vector3(s * slope, 0, 0))
	mbox(root, Vector3(11.6, 0.3, 0.36), A.pbr("clay_roof_tiles_02", 0.8, true, Color(0.8, 0.75, 0.7)), Vector3(0, 5.0, -25.25))
	for x in [-5.75, 5.75]:
		mbox(root, Vector3(0.3, 0.55, 0.5), plaster, Vector3(x, 5.2, -25.25))
	var gable := PrismMesh.new()
	gable.size = Vector3(6.0, 2.0, 0.2)
	for x in [-4.95, 4.95]:
		var g := MeshInstance3D.new()
		g.mesh = gable
		g.material_override = plaster
		g.position = Vector3(x, 3.9, -25.5)
		g.rotation.y = PI / 2
		root.add_child(g)

	# Hiên: a water jar, potted plants, the hammock between two columns
	var glaze := StandardMaterial3D.new()
	glaze.albedo_color = Color(0.28, 0.2, 0.14)
	glaze.roughness = 0.25
	var jar := sphere(root, 0.42, Color.WHITE, Vector3(-6.2, 0.45, -22.4), Vector3(1, 1.15, 1))
	jar.material_override = glaze
	var lid := mcyl(root, 0.3, 0.32, 0.05, wood, Vector3(-6.2, 0.95, -22.4))
	lid.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	for p in [Vector3(-5.4, 0.3, -21.4), Vector3(5.4, 0.3, -21.4), Vector3(-2.6, 0.3, -21.3), Vector3(2.6, 0.3, -21.3)]:
		place(root, "planter_pot_clay", p, 1.6, randf() * TAU)
		var pl := place_part(root, "fern_02", p + Vector3(0, 0.3, 0), 0.7, randf() * TAU)
		pl.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	var cloth := StandardMaterial3D.new()
	cloth.albedo_color = Color(0.25, 0.42, 0.62)
	cloth.roughness = 0.95
	cloth.cull_mode = BaseMaterial3D.CULL_DISABLED
	var ham := sphere(root, 0.4, Color.WHITE, Vector3(L.HAMMOCK.x, 0.72, L.HAMMOCK.y), Vector3(2.3, 0.3, 0.8))
	ham.material_override = cloth
	ham.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mcyl(root, 0.05, 0.06, 1.3, wood, Vector3(L.HAMMOCK.x - 1.05, 0.65, L.HAMMOCK.y))
	mcyl(root, 0.05, 0.06, 1.3, wood, Vector3(L.HAMMOCK.x + 1.05, 0.65, L.HAMMOCK.y))


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
	h.drain_plug = mbox(root, Vector3(0.85, 0.45, 0.7), A.pbr("grass_path_2", 1.0), Vector3(L.DRAIN.x, -0.08, L.DRAIN.y), Vector3.ZERO, false)

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
	var wall := A.pbr("yellow_plaster", 1.5, true, Color(0.78, 0.76, 0.7))
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
	place(root, "wicker_basket_01", Vector3(L.POND_EDGE.x + 0.5, 0.0, L.POND_EDGE.y + 0.8), 2.0, 0.5)
	place(root, "wooden_bucket_01", Vector3(-9.4, 0.0, 1.6), 0.9, 0.3)

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


static func _pig(root: Node3D) -> Node3D:
	var pig := Node3D.new()
	pig.position = Vector3(L.PIG.x + 0.5, 0.0, L.PIG.y)
	root.add_child(pig)
	var skin := StandardMaterial3D.new()
	skin.albedo_color = Color(0.2, 0.18, 0.18)
	skin.roughness = 0.75
	var pink := StandardMaterial3D.new()
	pink.albedo_color = Color(0.85, 0.6, 0.55)
	pink.roughness = 0.6
	var body := CapsuleMesh.new()
	body.radius = 0.32
	body.height = 1.15
	var bm := MeshInstance3D.new()
	bm.mesh = body
	bm.material_override = skin
	bm.position = Vector3(0, 0.5, 0)
	bm.rotation.z = PI / 2
	pig.add_child(bm)
	var belly := sphere(pig, 0.3, Color.WHITE, Vector3(0, 0.36, 0), Vector3(1.6, 0.6, 0.95))
	belly.material_override = pink
	var head := sphere(pig, 0.24, Color.WHITE, Vector3(0.62, 0.55, 0), Vector3(1.1, 1, 1))
	head.material_override = skin
	var snout := mcyl(pig, 0.1, 0.12, 0.14, pink, Vector3(0.86, 0.5, 0), 12)
	snout.rotation = Vector3(0, 0, PI / 2)
	for s in [-1, 1]:
		var ear := mbox(pig, Vector3(0.12, 0.02, 0.12), skin, Vector3(0.6, 0.72, s * 0.14), Vector3(0.4 * s, 0, -0.5))
		ear.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	for d in [Vector2(-0.35, -0.16), Vector2(-0.35, 0.16), Vector2(0.35, -0.16), Vector2(0.35, 0.16)]:
		mcyl(pig, 0.06, 0.05, 0.3, skin, Vector3(d.x, 0.15, d.y), 8)
	return pig


static func _buffalo(root: Node3D) -> Node3D:
	var buff := Node3D.new()
	buff.position = Vector3(L.BUFFALO.x, 0, L.BUFFALO.y)
	buff.rotation.y = 0.3
	root.add_child(buff)
	var hide := StandardMaterial3D.new()
	hide.albedo_color = Color(0.2, 0.19, 0.19)
	hide.roughness = 0.7
	hide.normal_enabled = true
	hide.normal_texture = A.tex("brown_mud_03", "nor")
	hide.normal_scale = 0.4
	var horn_m := StandardMaterial3D.new()
	horn_m.albedo_color = Color(0.75, 0.72, 0.62)
	horn_m.roughness = 0.4
	var body := CapsuleMesh.new()
	body.radius = 0.5
	body.height = 2.1
	var bm := MeshInstance3D.new()
	bm.mesh = body
	bm.material_override = hide
	bm.position = Vector3(0, 1.05, 0)
	bm.rotation.z = PI / 2
	buff.add_child(bm)
	sphere(buff, 0.45, Color.WHITE, Vector3(0.55, 1.15, 0), Vector3(1.1, 1.15, 1.0)).material_override = hide
	var neck := mcyl(buff, 0.26, 0.36, 0.6, hide, Vector3(1.05, 1.15, 0), 12)
	neck.rotation.z = -1.0
	var head := sphere(buff, 0.26, Color.WHITE, Vector3(1.4, 1.0, 0), Vector3(1.4, 1.0, 0.9))
	head.material_override = hide
	var muzzle := sphere(buff, 0.15, Color.WHITE, Vector3(1.68, 0.92, 0), Vector3(1, 0.9, 1.1))
	muzzle.material_override = mat(Color(0.12, 0.11, 0.11))
	for s in [-1, 1]:
		var horn := TorusMesh.new()
		horn.inner_radius = 0.24
		horn.outer_radius = 0.3
		horn.rings = 24
		var hm := MeshInstance3D.new()
		hm.mesh = horn
		hm.material_override = horn_m
		hm.position = Vector3(1.32, 1.3, s * 0.22)
		hm.rotation = Vector3(PI / 2, 0, s * 0.3)
		hm.scale = Vector3(1, 1, 0.45)
		buff.add_child(hm)
	for d in [Vector2(-0.7, -0.28), Vector2(-0.7, 0.28), Vector2(0.65, -0.28), Vector2(0.65, 0.28)]:
		mcyl(buff, 0.1, 0.08, 0.7, hide, Vector3(d.x, 0.35, d.y), 10)
	var tail := mcyl(buff, 0.03, 0.02, 0.8, hide, Vector3(-1.08, 0.85, 0), 6)
	tail.rotation.z = -0.2
	return buff


# ---------------------------------------------------------------- vegetation & distance
static func _plants(root: Node3D) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 2024
	# Lũy tre around the farm and the village edge
	var groves := [Vector2(-24, -30), Vector2(24, -26), Vector2(-26, 18), Vector2(20, 22), Vector2(26, -6), Vector2(-6, -34), Vector2(10, -33)]
	for x in range(-30, 31, 6):
		groves.append(Vector2(x + rng.randf_range(-1.5, 1.5), -38 + rng.randf_range(-1, 1)))
	for z in range(-30, 25, 7):
		groves.append(Vector2(-33 + rng.randf_range(-1, 1), z + rng.randf_range(-2, 2)))
		groves.append(Vector2(33 + rng.randf_range(-1, 1), z + rng.randf_range(-2, 2)))
	for g in groves:
		F.bamboo(root, Vector3(g.x, 0, g.y), rng, rng.randi_range(10, 16))
	for p in [Vector2(8, -24), Vector2(11, -23), Vector2(-12, -18), Vector2(17, -12), Vector2(-15, 3), Vector2(-24, -14), Vector2(7, -31)]:
		F.banana(root, Vector3(p.x, 0, p.y), rng)
	for p in [Vector2(-8, -30), Vector2(7, -29), Vector2(-14, 14), Vector2(15, -2), Vector2(-24, -18), Vector2(-3, -31)]:
		F.palm(root, Vector3(p.x, 0, p.y), rng, false)
	for p in [Vector2(22, 12), Vector2(-17, -4), Vector2(-21, -5)]:
		F.palm(root, Vector3(p.x, 0, p.y), rng, true)
	# Village tree lines across the paddies
	for i in 26:
		var a := rng.randf() * TAU
		var r := rng.randf_range(55, 85)
		var c := Vector2(cos(a), sin(a)) * r
		for k in rng.randi_range(2, 4):
			var o := c + Vector2(rng.randf_range(-6, 6), rng.randf_range(-6, 6))
			if rng.randf() < 0.65:
				F.bamboo(root, Vector3(o.x, 0, o.y), rng, 8)
			else:
				F.palm(root, Vector3(o.x, 0, o.y), rng, rng.randf() < 0.4)

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
	F.grass(root, tall, F.tuft_mesh(16, 0.42, 0.0055), rng, 0.3, 8.0, 40.0)

	# Poly Haven plants and rocks around the edges
	var weeds := []
	var shrubs := []
	var rocks := []
	for i in 140:
		var x := rng.randf_range(-30, 30)
		var z := rng.randf_range(-34, 28)
		if not _clear_for_grass(x, z):
			continue
		var pt := [Vector3(x, 0, z), rng.randf() * TAU, rng.randf_range(0.8, 1.6)]
		if i % 3 == 0:
			shrubs.append(pt)
		else:
			weeds.append(pt)
	# River stones on the pond rim and canal banks: grey, half buried, a few
	# small ones beside each bigger one.
	for i in 22:
		var a := rng.randf() * TAU
		var r: float = L.POND.r + rng.randf_range(0.25, 0.9)
		rocks.append([Vector3(L.POND.x + cos(a) * r, 0.0, L.POND.z + sin(a) * r), rng.randf() * TAU, rng.randf_range(0.8, 1.7)])
	for i in 26:
		rocks.append([Vector3([L.CANAL.x0 - 0.35, L.CANAL.x1 + 0.35][i % 2] + rng.randf_range(-0.15, 0.15), 0.0, rng.randf_range(-30, 26)), rng.randf() * TAU, rng.randf_range(0.8, 1.6)])
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
	# knee-high weeds cast no shadows (one less pass per cascade)
	A.scatter(root, "weed_plant_02", weeds, false, 30.0)
	A.scatter(root, "nettle_plant", weeds.slice(0, weeds.size() / 2), false, 30.0)
	A.scatter(root, "shrub_04", shrubs, true, 40.0)
	A.scatter(root, "fern_02", shrubs, true, 40.0)
	A.scatter(root, "rock_07", rocks, true, 45.0, 0.4, A.recolor("rock_07", 0.25, Color(0.9, 0.92, 0.94), 1.2))
	A.scatter(root, "stone_01", pebbles, false, 25.0, 0.35, A.recolor("stone_01", 0.2, Color(0.86, 0.87, 0.88), 1.1))


static func _stone_ok(q: Vector3) -> bool:
	if q.x > L.CANAL.x0 - 0.05 and q.x < L.CANAL.x1 + 0.05:
		return false
	return Vector2(q.x - L.POND.x, q.z - L.POND.z).length() > L.POND.r + 0.2


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


# Karst towers (núi đá vôi) on the horizon, like Ninh Bình.
static func _hills(root: Node3D) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var noise := FastNoiseLite.new()
	noise.frequency = 0.08
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.roughness = 0.95
	m.normal_enabled = true
	m.normal_texture = A.tex("dirt", "nor")
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3.ONE / 12.0
	for i in 22:
		var a := i / 22.0 * TAU + rng.randf_range(-0.12, 0.12)
		var r := rng.randf_range(110, 170)
		var hgt := rng.randf_range(22, 48)
		var rad := rng.randf_range(13, 24)
		var sm := SphereMesh.new()
		sm.radius = 1.0
		sm.height = 2.0
		sm.radial_segments = 24
		sm.rings = 16
		var arr := sm.get_mesh_arrays()
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var cols := PackedColorArray()
		cols.resize(verts.size())
		var center := Vector3(cos(a) * r, 0, sin(a) * r)
		for k in verts.size():
			var v := verts[k]
			var y := maxf(v.y, -0.2)
			# Near-vertical cliffs with a rounded crown, broken up by noise so
			# each tower has ledges, bulges and a lumpy top.
			var w := sqrt(1.0 - pow(clampf(y, 0.0, 1.0), 2.0)) if y > 0.0 else 1.0
			var n := noise.get_noise_3d(v.x * 4 + i * 13, y * 5, v.z * 4) * 0.45
			n += noise.get_noise_3d(v.x * 11 + i * 7, y * 13, v.z * 11) * 0.18
			var p := Vector3(v.x * rad * w * (1.0 + n), (y + 0.2) * hgt * (1.0 + n * 0.25), v.z * rad * w * (1.0 + n))
			verts[k] = p
			# Green scrub on ledges and the crown, grey limestone on steep faces.
			var steep := clampf(1.0 - absf(v.y) * 1.4, 0.0, 1.0)
			var rock := clampf(noise.get_noise_3d(v.x * 9, y * 18 + i, v.z * 9) * 1.8 + steep * 0.6 - 0.1, 0.0, 1.0)
			cols[k] = Color(0.2, 0.3, 0.13).lerp(Color(0.48, 0.48, 0.44), rock * 0.85)
		arr[Mesh.ARRAY_VERTEX] = verts
		arr[Mesh.ARRAY_COLOR] = cols
		arr[Mesh.ARRAY_NORMAL] = null
		arr[Mesh.ARRAY_TANGENT] = null
		var st := SurfaceTool.new()
		st.create_from_arrays(arr)
		st.generate_normals()
		st.generate_tangents()
		var mi := MeshInstance3D.new()
		mi.mesh = st.commit()
		mi.material_override = m
		mi.position = center + Vector3(0, -4, 0)
		mi.rotation.y = rng.randf() * TAU
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)


static func build(root: Node3D) -> Dictionary:
	var h := {}
	_ground(root, h)
	_house(root)
	_props(root, h)
	_plants(root)
	_hills(root)
	return h
