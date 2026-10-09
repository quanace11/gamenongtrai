# Static scenery of the farm: ground, bunds, canal, house, courtyard,
# animal sheds and the props the player interacts with. Everything is
# low-poly geometry built in code.
extends RefCounted

const L = preload("res://scripts/layout.gd")

static var _mats := {}


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


static func cyl(parent: Node3D, rt: float, rb: float, h: float, color: Color, pos: Vector3, seg := 8) -> MeshInstance3D:
	var c := CylinderMesh.new()
	c.top_radius = rt
	c.bottom_radius = rb
	c.height = h
	c.radial_segments = seg
	c.rings = 1
	return add_mesh(parent, c, color, pos)


static func sphere(parent: Node3D, r: float, color: Color, pos: Vector3, scale := Vector3.ONE) -> MeshInstance3D:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = 10
	s.rings = 6
	var mi := add_mesh(parent, s, color, pos)
	mi.scale = scale
	return mi


static func _grass_material() -> StandardMaterial3D:
	var noise := FastNoiseLite.new()
	noise.frequency = 0.08
	var tex := NoiseTexture2D.new()
	tex.width = 256
	tex.height = 256
	tex.seamless = true
	tex.noise = noise
	var ramp := Gradient.new()
	ramp.set_color(0, Color("4f7a30"))
	ramp.set_color(1, Color("8fb357"))
	tex.color_ramp = ramp
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	m.uv1_scale = Vector3(0.25, 0.25, 0.25)
	m.uv1_triplanar = true
	m.roughness = 1.0
	return m


static func _brick_material() -> StandardMaterial3D:
	var img := Image.create(256, 256, false, Image.FORMAT_RGB8)
	img.fill(Color("5e2a1a"))
	for r in 8:
		for k in 9:
			var x := k * 32 - (r % 2) * 16
			var shade := 0.55 + randf() * 0.15
			img.fill_rect(Rect2i(x + 2, r * 32 + 2, 28, 28), Color(shade + 0.08, shade * 0.45, shade * 0.32))
	var m := StandardMaterial3D.new()
	m.albedo_texture = ImageTexture.create_from_image(img)
	m.uv1_scale = Vector3(3, 1.5, 1)
	m.roughness = 0.95
	return m


static func _ground(root: Node3D, h: Dictionary) -> void:
	var grass := _grass_material()
	var S := 160.0
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
		mi.material_override = grass
		mi.position = Vector3((r[0] + r[1]) / 2.0, 0, (r[2] + r[3]) / 2.0)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)

	# Bờ ruộng
	var bund_c := Color("7d6a3e")
	var size := fx1 - fx0
	var hgt := 0.55
	var yc: float = L.FIELD.bund_top - hgt / 2.0
	box(root, Vector3(size, hgt, b), bund_c, Vector3(0, yc, L.FIELD.z0 - b / 2.0), false)
	box(root, Vector3(size, hgt, b), bund_c, Vector3(0, yc, L.FIELD.z1 + b / 2.0), false)
	box(root, Vector3(b, hgt, size), bund_c, Vector3(L.FIELD.x0 - b / 2.0, yc, 0), false)
	box(root, Vector3(b, hgt, size), bund_c, Vector3(L.FIELD.x1 + b / 2.0, yc, 0), false)
	# Cỏ trên bờ
	var tuft := CylinderMesh.new()
	tuft.top_radius = 0.0
	tuft.bottom_radius = 0.07
	tuft.height = 0.25
	tuft.radial_segments = 4
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = tuft
	mm.instance_count = 220
	for i in 220:
		var t := randf() * size - size / 2.0
		var off: float = L.FIELD.x1 + b / 2.0 + (randf() - 0.5) * 0.5
		var pos: Array = [[t, -off], [t, off], [-off, t], [off, t]][i % 4]
		mm.set_instance_transform(i, Transform3D(Basis(), Vector3(pos[0], L.FIELD.bund_top + 0.1, pos[1])))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = mat(Color("5f8a35"))
	root.add_child(mmi)

	# Mương
	var cx: float = (L.CANAL.x0 + L.CANAL.x1) / 2.0
	box(root, Vector3(2, 0.1, 2 * S), Color("4b3b26"), Vector3(cx, -0.95, 0), false)
	box(root, Vector3(0.1, 0.9, 2 * S), Color("5a4a30"), Vector3(L.CANAL.x0, -0.45, 0), false)
	box(root, Vector3(0.1, 0.9, 2 * S), Color("5a4a30"), Vector3(L.CANAL.x1, -0.45, 0), false)
	var water := PlaneMesh.new()
	water.size = Vector2(2, 2 * S)
	var wm := StandardMaterial3D.new()
	wm.albedo_color = Color(0.31, 0.48, 0.47, 0.8)
	wm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	wm.roughness = 0.1
	wm.metallic_specular = 0.8
	var cw := MeshInstance3D.new()
	cw.mesh = water
	cw.material_override = wm
	cw.position = Vector3(cx, -0.3, 0)
	root.add_child(cw)
	h.canal_water = cw
	# Rãnh dẫn nước từ mương tới cửa cống, và rãnh xả bờ đông
	box(root, Vector3(1.2, 0.05, 0.9), Color("4f7a78"), Vector3(-9.4, 0.02, 0), false)
	box(root, Vector3(0.8, 0.05, 0.7), Color("4f7a78"), Vector3(9.2, 0.02, 4), false)

	# Ao với bèo tây
	var pond := CylinderMesh.new()
	pond.top_radius = L.POND.r
	pond.bottom_radius = L.POND.r
	pond.height = 0.04
	pond.radial_segments = 32
	var pm := StandardMaterial3D.new()
	pm.albedo_color = Color(0.27, 0.44, 0.35)
	pm.roughness = 0.1
	pm.metallic_specular = 0.8
	var pmi := MeshInstance3D.new()
	pmi.mesh = pond
	pmi.material_override = pm
	pmi.position = Vector3(L.POND.x, 0.02, L.POND.z)
	root.add_child(pmi)
	for i in 26:
		var a := randf() * TAU
		var rr := randf() * (L.POND.r - 0.6)
		var c := Vector3(L.POND.x + cos(a) * rr, 0.05, L.POND.z + sin(a) * rr)
		for k in 4:
			sphere(root, 0.18, Color("3f8f3a"), c + Vector3(cos(k * 1.6) * 0.15, 0.03, sin(k * 1.6) * 0.15), Vector3(1, 0.4, 0.7))
		if randf() < 0.4:
			sphere(root, 0.07, Color("b28ad8"), c + Vector3(0, 0.15, 0))


static func _house(root: Node3D) -> void:
	# Sân gạch đỏ
	var court := PlaneMesh.new()
	court.size = Vector2(L.COURT.x1 - L.COURT.x0, L.COURT.z1 - L.COURT.z0)
	var cmi := MeshInstance3D.new()
	cmi.mesh = court
	cmi.material_override = _brick_material()
	cmi.position = Vector3((L.COURT.x0 + L.COURT.x1) / 2.0, 0.015, (L.COURT.z0 + L.COURT.z1) / 2.0)
	root.add_child(cmi)
	# Khung bạt (vạch mờ)
	var tw: float = L.TARP.x1 - L.TARP.x0
	var td: float = L.TARP.z1 - L.TARP.z0
	var tcx: float = (L.TARP.x0 + L.TARP.x1) / 2.0
	var tcz: float = (L.TARP.z0 + L.TARP.z1) / 2.0
	var line_c := Color("e8d6a0")
	box(root, Vector3(tw, 0.01, 0.05), line_c, Vector3(tcx, 0.03, L.TARP.z0), false)
	box(root, Vector3(tw, 0.01, 0.05), line_c, Vector3(tcx, 0.03, L.TARP.z1), false)
	box(root, Vector3(0.05, 0.01, td), line_c, Vector3(L.TARP.x0, 0.03, tcz), false)
	box(root, Vector3(0.05, 0.01, td), line_c, Vector3(L.TARP.x1, 0.03, tcz), false)

	# Nhà ba gian
	box(root, Vector3(10, 2.6, 6), Color("d9c7a0"), Vector3(0, 1.3, -25.5))
	box(root, Vector3(10.4, 0.25, 1.6), Color("8c7b5c"), Vector3(0, 0.12, -21.9), false)
	for x in [-4.6, -1.6, 1.6, 4.6]:
		cyl(root, 0.12, 0.12, 2.6, Color("6b4a2b"), Vector3(x, 1.3, -21.4))
	box(root, Vector3(1.2, 2.0, 0.1), Color("5b3a1e"), Vector3(0, 1.0, -22.45))
	box(root, Vector3(1.0, 0.9, 0.1), Color("5b3a1e"), Vector3(-3, 1.5, -22.45))
	box(root, Vector3(1.0, 0.9, 0.1), Color("5b3a1e"), Vector3(3, 1.5, -22.45))
	var roof := PrismMesh.new()
	roof.size = Vector3(7.6, 1.9, 11.2)
	add_mesh(root, roof, Color("9a4a2a"), Vector3(0, 3.55, -25.2), Vector3(0, PI / 2, 0))
	# Võng
	var ham := sphere(root, 0.4, Color("3d6fa8"), Vector3(L.HAMMOCK.x, 0.75, L.HAMMOCK.y), Vector3(2.3, 0.35, 0.9))
	ham.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	cyl(root, 0.03, 0.03, 1.2, Color("6b4a2b"), Vector3(L.HAMMOCK.x - 1.0, 0.6, L.HAMMOCK.y))
	cyl(root, 0.03, 0.03, 1.2, Color("6b4a2b"), Vector3(L.HAMMOCK.x + 1.0, 0.6, L.HAMMOCK.y))


static func _props(root: Node3D, h: Dictionary) -> void:
	var wood := Color("6b4a2b")
	# Cửa cống trên bờ tây
	var gate := Node3D.new()
	gate.position = Vector3(L.GATE.x, 0, L.GATE.y)
	root.add_child(gate)
	box(gate, Vector3(0.15, 1.0, 0.15), wood, Vector3(0, 0.2, -0.55))
	box(gate, Vector3(0.15, 1.0, 0.15), wood, Vector3(0, 0.2, 0.55))
	box(gate, Vector3(0.15, 0.12, 1.25), wood, Vector3(0, 0.7, 0))
	h.gate = box(gate, Vector3(0.08, 0.6, 0.95), Color("8a6a3a"), Vector3(0, -0.05, 0))
	# Ụ đất bịt rãnh xả bờ đông
	h.drain_plug = box(root, Vector3(0.85, 0.45, 0.7), Color("7d6a3e"), Vector3(L.DRAIN.x, -0.08, L.DRAIN.y), false)

	# Cọc tre bẫy ốc + ổ trứng
	h.eggs = []
	for s in L.STAKES:
		cyl(root, 0.035, 0.04, 1.4, Color("b9a46a"), Vector3(s.x, L.FIELD.y + 0.6, s.y), 6)
		var egg := sphere(root, 0.07, Color("e2437a"), Vector3(s.x + 0.06, L.FIELD.y + 0.55, s.y), Vector3(1, 1.8, 1))
		egg.visible = false
		h.eggs.append(egg)

	# Thùng đập lúa
	var drum := cyl(root, 0.55, 0.5, 0.95, Color("7a5a35"), Vector3(L.BARREL.x, 0.48, L.BARREL.y), 14)
	drum.material_override = mat(Color("7a5a35"), true)
	box(root, Vector3(0.9, 0.05, 0.6), Color("c9b27a"), Vector3(L.BARREL.x, 0.95, L.BARREL.y - 0.2))
	h.barrel_grain = cyl(root, 0.5, 0.5, 0.05, Color("d8b24a"), Vector3(L.BARREL.x, 0.05, L.BARREL.y), 14)

	# Cuộn bạt, đống gạch, gạch chặn góc
	var roll := cyl(root, 0.2, 0.2, 1.6, Color("2f6fd0"), Vector3(L.TARP_ROLL.x, 0.2, L.TARP_ROLL.y), 10)
	roll.rotation = Vector3(0, 0, PI / 2)
	for i in 8:
		box(root, Vector3(0.25, 0.08, 0.12), Color("a84a2a"), Vector3(L.BRICK_PILE.x + (i % 2) * 0.27, 0.04 + int(i / 2) * 0.08, L.BRICK_PILE.y))
	h.corner_bricks = []
	h.corner_marks = []
	for c in L.CORNERS:
		var br := box(root, Vector3(0.25, 0.1, 0.12), Color("a84a2a"), Vector3(c.x, 0.12, c.y))
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
	var tarp := add_mesh(root, tarp_mesh, Color("2f6fd0"), Vector3((L.TARP.x0 + L.TARP.x1) / 2.0, 0.6, (L.TARP.z0 + L.TARP.z1) / 2.0))
	tarp.material_override = mat(Color("2f6fd0"), true)
	tarp.visible = false
	h.tarp = tarp

	# Thúng ngâm thóc + vạt mạ
	var basket := cyl(root, 0.45, 0.35, 0.35, Color("b9965a"), Vector3(L.BASKET.x, 0.18, L.BASKET.y), 12)
	basket.material_override = mat(Color("b9965a"), true)
	h.basket_water = cyl(root, 0.42, 0.42, 0.02, Color("7c9aa0"), Vector3(L.BASKET.x, 0.28, L.BASKET.y), 12)
	h.basket_water.visible = false
	box(root, Vector3(4, 0.12, 3), Color("5a4026"), Vector3(L.NURSERY.x, 0.06, L.NURSERY.y), false)
	var sprout := CylinderMesh.new()
	sprout.top_radius = 0.0
	sprout.bottom_radius = 0.04
	sprout.height = 0.3
	sprout.radial_segments = 4
	var smm := MultiMesh.new()
	smm.transform_format = MultiMesh.TRANSFORM_3D
	smm.mesh = sprout
	smm.instance_count = 300
	for i in 300:
		smm.set_instance_transform(i, Transform3D(Basis(), Vector3(L.NURSERY.x - 1.8 + randf() * 3.6, 0.15, L.NURSERY.y - 1.3 + randf() * 2.6)))
	var smi := MultiMeshInstance3D.new()
	smi.multimesh = smm
	smi.material_override = mat(Color("8ccf4a"))
	root.add_child(smi)
	h.seedlings = smi

	# Chuồng vịt, cổng phía tây
	var fence := Color("a08a5a")
	var p: Dictionary = L.DUCK_PEN
	var pcx: float = (p.x0 + p.x1) / 2.0
	var pcz: float = (p.z0 + p.z1) / 2.0
	box(root, Vector3(p.x1 - p.x0, 0.6, 0.06), fence, Vector3(pcx, 0.3, p.z0))
	box(root, Vector3(p.x1 - p.x0, 0.6, 0.06), fence, Vector3(pcx, 0.3, p.z1))
	box(root, Vector3(0.06, 0.6, p.z1 - p.z0), fence, Vector3(p.x1, 0.3, pcz))
	box(root, Vector3(0.06, 0.6, 1.2), fence, Vector3(p.x0, 0.3, p.z0 + 0.6))
	box(root, Vector3(0.06, 0.6, 1.2), fence, Vector3(p.x0, 0.3, p.z1 - 0.6))
	var dgate := Node3D.new()
	dgate.position = Vector3(p.x0, 0, p.z0 + 1.2)
	root.add_child(dgate)
	box(dgate, Vector3(0.06, 0.6, 1.6), Color("c0a060"), Vector3(0, 0.3, 0.8))
	h.duck_gate = dgate
	box(root, Vector3(2, 0.08, 2), Color("8a7a50"), Vector3(p.x1 - 1, 1.0, p.z0 + 1))
	h.duck_eggs = []
	for i in 8:
		var e := sphere(root, 0.05, Color("f6f1e4"), Vector3(p.x1 - 1.4 + (i % 4) * 0.2, 0.06, p.z0 + 0.6 + int(i / 4) * 0.2), Vector3(1, 1.3, 1))
		e.visible = false
		h.duck_eggs.append(e)

	# Chuồng lợn, máng, hầm biogas, bếp củi, thớt
	var wall := Color("8d8d86")
	box(root, Vector3(4, 0.8, 0.12), wall, Vector3(L.PIG.x, 0.4, L.PIG.y - 2))
	box(root, Vector3(4, 0.8, 0.12), wall, Vector3(L.PIG.x, 0.4, L.PIG.y + 2))
	box(root, Vector3(0.12, 0.8, 4), wall, Vector3(L.PIG.x - 2, 0.4, L.PIG.y))
	box(root, Vector3(0.12, 0.8, 4), wall, Vector3(L.PIG.x + 2, 0.4, L.PIG.y))
	box(root, Vector3(4.4, 0.1, 2.4), Color("9a4a2a"), Vector3(L.PIG.x, 1.7, L.PIG.y - 1.1))
	var pig := Node3D.new()
	pig.position = Vector3(L.PIG.x + 0.5, 0.45, L.PIG.y)
	root.add_child(pig)
	sphere(pig, 0.45, Color("3a3434"), Vector3.ZERO, Vector3(1.5, 0.9, 0.9))
	var snout := cyl(pig, 0.12, 0.14, 0.15, Color("6a5a5a"), Vector3(0.7, 0, 0))
	snout.rotation = Vector3(0, 0, PI / 2)
	h.pig = pig
	box(root, Vector3(0.4, 0.25, 1.2), wall, Vector3(L.TROUGH.x, 0.12, L.TROUGH.y))
	sphere(root, 1.2, Color("9a9a92"), Vector3(L.BIOGAS.x, 0, L.BIOGAS.y), Vector3(1, 0.6, 1))
	cyl(root, 0.05, 0.05, 1.2, Color("333333"), Vector3(L.BIOGAS.x, 1.2, L.BIOGAS.y), 6)
	box(root, Vector3(1.4, 0.4, 1), Color("6e5a48"), Vector3(L.STOVE.x, 0.2, L.STOVE.y))
	h.pot = cyl(root, 0.3, 0.25, 0.35, Color("2a2a2a"), Vector3(L.STOVE.x, 0.58, L.STOVE.y), 12)
	box(root, Vector3(0.8, 0.08, 0.5), Color("8a6a3a"), Vector3(L.BOARD.x, 0.6, L.BOARD.y))
	cyl(root, 0.05, 0.05, 0.56, wood, Vector3(L.BOARD.x, 0.28, L.BOARD.y), 5)
	var pond_basket := cyl(root, 0.3, 0.22, 0.25, Color("b9965a"), Vector3(L.POND_EDGE.x + 0.5, 0.13, L.POND_EDGE.y + 0.8), 10)
	pond_basket.material_override = mat(Color("b9965a"), true)

	# Trâu đứng chờ cạnh ruộng
	var buff := Node3D.new()
	buff.position = Vector3(L.BUFFALO.x, 0, L.BUFFALO.y)
	buff.rotation.y = 0.3
	root.add_child(buff)
	var dark := Color("3b3836")
	box(buff, Vector3(1.8, 0.9, 0.8), dark, Vector3(0, 1.0, 0))
	box(buff, Vector3(0.5, 0.45, 0.45), dark, Vector3(1.1, 1.2, 0))
	for s in [-1, 1]:
		var horn := TorusMesh.new()
		horn.inner_radius = 0.22
		horn.outer_radius = 0.28
		var hm := add_mesh(buff, horn, Color("d8d0bc"), Vector3(1.1, 1.45, s * 0.12), Vector3(PI / 2, 0, 0))
		hm.scale = Vector3(1, 1, 0.5)
	for d in [Vector2(-0.7, -0.3), Vector2(-0.7, 0.3), Vector2(0.7, -0.3), Vector2(0.7, 0.3)]:
		box(buff, Vector3(0.16, 0.6, 0.16), dark, Vector3(d.x, 0.3, d.y))


static func _trees(root: Node3D) -> void:
	for p in [Vector2(-24, -30), Vector2(24, -26), Vector2(-26, 18), Vector2(20, 22), Vector2(26, -6), Vector2(-6, -34), Vector2(10, -33)]:
		for i in 9:
			var hgt := randf_range(5, 8)
			var c := cyl(root, 0.06, 0.08, hgt, Color("7aa04a"), Vector3(p.x + randf_range(-0.8, 0.8), hgt / 2, p.y + randf_range(-0.8, 0.8)), 6)
			c.rotation = Vector3(randf_range(-0.12, 0.12), 0, randf_range(-0.12, 0.12))
		sphere(root, 2.2, Color("5d8a35"), Vector3(p.x, 6.5, p.y), Vector3(1, 1.4, 1))
	for p in [Vector2(8, -24), Vector2(11, -23), Vector2(-12, -18), Vector2(17, -12), Vector2(-15, 3)]:
		cyl(root, 0.15, 0.2, 2.2, Color("8a9a5a"), Vector3(p.x, 1.1, p.y), 7)
		for i in 6:
			var a := i / 6.0 * TAU
			var leaf := BoxMesh.new()
			leaf.size = Vector3(0.5, 0.02, 1.8)
			add_mesh(root, leaf, Color("6aa040"), Vector3(p.x + cos(a) * 0.7, 2.3, p.y + sin(a) * 0.7), Vector3(0.45, -a + PI / 2, 0))
	for p in [Vector2(-8, -30), Vector2(7, -29), Vector2(-14, 14), Vector2(15, -2), Vector2(22, 12), Vector2(-24, -18)]:
		var hgt := randf_range(6, 8)
		cyl(root, 0.15, 0.22, hgt, Color("8a7a5a"), Vector3(p.x, hgt / 2, p.y), 7)
		for i in 7:
			var a := i / 7.0 * TAU
			var leaf := BoxMesh.new()
			leaf.size = Vector3(0.6, 0.02, 3.0)
			add_mesh(root, leaf, Color("4f8a3a"), Vector3(p.x + cos(a) * 1.3, hgt - 0.4, p.y + sin(a) * 1.3), Vector3(0.35, -a + PI / 2, 0))
	# Núi đá vôi phía xa
	for i in 14:
		var a := i / 14.0 * TAU + randf_range(-0.1, 0.1)
		var r := randf_range(95, 130)
		var hgt := randf_range(18, 40)
		var cone := CylinderMesh.new()
		cone.top_radius = randf_range(0.5, 2.0)
		cone.bottom_radius = randf_range(10, 18)
		cone.height = hgt
		cone.radial_segments = 6
		add_mesh(root, cone, Color("6f8a6a"), Vector3(cos(a) * r, hgt / 2 - 2, sin(a) * r), Vector3(0, randf() * 3, 0), false)
	# Những thửa ruộng xa
	var greens := [Color("7fb24a"), Color("9cc45a"), Color("6e9e40"), Color("b7c46a")]
	for gx in range(-4, 5):
		for gz in range(-4, 5):
			if (absi(gx) <= 2 and absi(gz) <= 2) or gx == -1:
				continue
			var pl := PlaneMesh.new()
			pl.size = Vector2(14, 14)
			add_mesh(root, pl, greens[(gx * 7 + gz * 3 + 40) % 4], Vector3(gx * 16, 0.02, gz * 16), Vector3.ZERO, false)


static func build(root: Node3D) -> Dictionary:
	var h := {}
	_ground(root, h)
	_house(root)
	_props(root, h)
	_trees(root)
	return h
