# Vietnamese village plants built in code: bamboo groves (lũy tre),
# banana clumps, areca and coconut palms, grass tufts and rice clumps.
# Leaves use small textures painted at startup and the foliage shader,
# which sways them in the wind.
extends RefCounted

const FOLIAGE = preload("res://shaders/foliage.gdshader")
const BLADE = preload("res://shaders/grass_blade.gdshader")

static var _tex := {}
static var _mats := {}
static var _wind: NoiseTexture2D


# Seamless gust noise shared by every plant shader (rice, lawn, bamboo):
# sampled at world xz * 0.035 and scrolled along the wind_dir global, so
# gust waves cross the lawn, the paddy and the groves together.
static func wind_noise() -> NoiseTexture2D:
	if _wind == null:
		var n := FastNoiseLite.new()
		n.frequency = 0.012
		n.fractal_octaves = 3
		_wind = NoiseTexture2D.new()
		_wind.width = 256
		_wind.height = 256
		_wind.seamless = true
		_wind.generate_mipmaps = true
		_wind.noise = n
	return _wind


static func material(kind: String) -> ShaderMaterial:
	if _mats.has(kind):
		return _mats[kind]
	var m := ShaderMaterial.new()
	# Untextured blades skip the alpha-clip path; leaf cards keep it.
	m.shader = BLADE if kind in ["blade", "seedling"] else FOLIAGE
	m.set_shader_parameter("noise", wind_noise())
	match kind:
		"seedling": # nursery bed: soft, short, fluttering
			m.set_shader_parameter("sway", 0.12)
			m.set_shader_parameter("flex_sway", 0.02)
			m.set_shader_parameter("translucency", 0.45)
			m.set_shader_parameter("rough", 0.55)
			m.set_shader_parameter("keep_normal", true)
		"blade": # rice and grass: colour from vertices/instances
			m.set_shader_parameter("sway", 0.09)
			m.set_shader_parameter("keep_normal", true)
			m.set_shader_parameter("translucency", 0.25)
		"bamboo_leaf":
			m.set_shader_parameter("use_leaf", true)
			m.set_shader_parameter("leaf", _leaf_texture("bamboo"))
			m.set_shader_parameter("sway", 0.025)
			m.set_shader_parameter("stiffness", 0.9)
		"stem": # bamboo culms, palm trunks: bend only a little
			m.set_shader_parameter("sway", 0.012)
			m.set_shader_parameter("stiffness", 1.1)
			m.set_shader_parameter("translucency", 0.0)
			m.set_shader_parameter("rough", 0.5)
		"banana_leaf":
			m.set_shader_parameter("use_leaf", true)
			m.set_shader_parameter("leaf", _leaf_texture("banana"))
			m.set_shader_parameter("sway", 0.03)
			m.set_shader_parameter("rough", 0.45)
		"frond":
			m.set_shader_parameter("use_leaf", true)
			m.set_shader_parameter("leaf", _leaf_texture("frond"))
			m.set_shader_parameter("sway", 0.008)
			m.set_shader_parameter("stiffness", 1.2)
	_mats[kind] = m
	return m


# ---------------------------------------------------------------- leaf textures
static func _leaf_texture(kind: String) -> Texture2D:
	if _tex.has(kind):
		return _tex[kind]
	var img: Image
	match kind:
		"bamboo":
			img = _paint_bamboo()
		"banana":
			img = _paint_banana()
		"frond":
			img = _paint_frond()
	img.generate_mipmaps()
	var t := ImageTexture.create_from_image(img)
	_tex[kind] = t
	return t


# Thin lance leaves fanning from a twig along the card's centre line.
static func _paint_bamboo() -> Image:
	var S := 256
	var img := Image.create(S, S, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.3, 0.45, 0.15, 0.0))
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var leaves := []
	for i in 22:
		var y := 0.05 + i * 0.04
		var side := -1.0 if i % 2 == 0 else 1.0
		leaves.append({"o": Vector2(0.5 + rng.randf_range(-0.03, 0.03), y), "a": Vector2(side * rng.randf_range(0.3, 0.8), rng.randf_range(0.6, 1.0)).normalized(), "len": rng.randf_range(0.28, 0.42), "w": rng.randf_range(0.022, 0.032), "c": Color(0.22, 0.4, 0.1).lerp(Color(0.42, 0.55, 0.16), rng.randf())})
	for py in S:
		for px in S:
			var p := Vector2((px + 0.5) / S, (py + 0.5) / S)
			if absf(p.x - 0.5) < 0.006 and p.y < 0.95:
				img.set_pixel(px, py, Color(0.45, 0.5, 0.25, 1))
				continue
			for l in leaves:
				var d: Vector2 = p - l.o
				var u: float = d.dot(l.a) / l.len
				if u < 0.0 or u > 1.0:
					continue
				var v: float = absf(d.dot(Vector2(-l.a.y, l.a.x)))
				var w: float = l.w * pow(sin(PI * u), 0.6) * (1.0 - 0.4 * u)
				if v < w:
					var c: Color = l.c
					if v < w * 0.12:
						c = c.lightened(0.15)
					c = c.darkened(0.15 * (1.0 - u))
					c.a = 1.0
					img.set_pixel(px, py, c)
					break
	return img


# Banana leaf: wide blade with a pale midrib, parallel veins and tears.
static func _paint_banana() -> Image:
	var S := 256
	var img := Image.create(S, S, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.3, 0.5, 0.15, 0.0))
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var tears := []
	for i in 9:
		tears.append([rng.randf_range(0.1, 0.95), rng.randf_range(0.004, 0.012), -1.0 if rng.randf() < 0.5 else 1.0])
	for py in S:
		var v := (py + 0.5) / S # along the leaf, 0 = stem
		var half := 0.48 * pow(sin(PI * clampf(v * 1.05, 0.0, 1.0)), 0.45)
		for px in S:
			var u := (px + 0.5) / S - 0.5 # across
			var au := absf(u)
			if au > half:
				continue
			var torn := false
			for t in tears:
				if absf(v - t[0] - au * 0.25) < t[1] and signf(u) == t[2] and au > 0.04:
					torn = true
					break
			if torn:
				continue
			var c := Color(0.24, 0.5, 0.12).lerp(Color(0.42, 0.66, 0.2), au / maxf(half, 0.01))
			c = c.darkened(0.08 * (0.5 + 0.5 * sin((v + au * 0.4) * 140.0)))
			if au < 0.018:
				c = Color(0.72, 0.78, 0.45)
			if v > 0.9 or au > half - 0.012:
				c = c.lerp(Color(0.55, 0.45, 0.2), 0.5)
			img.set_pixel(px, py, c)
	return img


# Pinnate palm frond: a rachis down the centre and narrow leaflets.
static func _paint_frond() -> Image:
	var S := 256
	var img := Image.create(S, S, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.3, 0.45, 0.15, 0.0))
	var n := 22
	for py in S:
		var v := (py + 0.5) / S
		var reach := 0.47 * sin(PI * clampf(v * 1.02, 0.0, 1.0))
		for px in S:
			var u := (px + 0.5) / S - 0.5
			var au := absf(u)
			if au < 0.012:
				img.set_pixel(px, py, Color(0.55, 0.55, 0.25))
				continue
			if au > reach:
				continue
			# Leaflets slant toward the tip.
			var k := (v - au * 0.55) * n
			var f := k - floorf(k)
			if absf(f - 0.5) < 0.3 * (1.0 - au / maxf(reach, 0.01) * 0.5):
				var c := Color(0.22, 0.42, 0.12).lerp(Color(0.4, 0.58, 0.18), au / maxf(reach, 0.01))
				img.set_pixel(px, py, c)
	return img


# ---------------------------------------------------------------- mesh helpers
static func _instance(parent: Node3D, mesh: Mesh, pos: Vector3, yaw := 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	mi.rotation.y = yaw
	parent.add_child(mi)
	return mi


# A tube along `pts` with radius `r(t)`, vertex colour `col(t)`.
static func _tube(st: SurfaceTool, pts: Array, r0: float, r1: float, c0: Color, c1: Color, sides := 6, rings_every := 0.0) -> void:
	var n := pts.size()
	var rings := []
	for i in n:
		var t := float(i) / (n - 1)
		var p: Vector3 = pts[i]
		var fwd: Vector3 = (pts[mini(i + 1, n - 1)] - pts[maxi(i - 1, 0)]).normalized()
		var side := fwd.cross(Vector3.FORWARD if absf(fwd.z) < 0.9 else Vector3.RIGHT).normalized()
		var up := side.cross(fwd).normalized()
		var r := lerpf(r0, r1, t)
		var c := c0.lerp(c1, t)
		var ring := []
		for s in sides + 1:
			var a := float(s) / sides * TAU
			ring.append([p + (side * cos(a) + up * sin(a)) * r, (side * cos(a) + up * sin(a)), c, Vector2(float(s) / sides, t)])
		rings.append(ring)
	for i in n - 1:
		for s in sides:
			var quad := [rings[i][s], rings[i][s + 1], rings[i + 1][s + 1], rings[i][s], rings[i + 1][s + 1], rings[i + 1][s]]
			for v in quad:
				st.set_color(v[2])
				st.set_normal(v[1])
				st.set_uv(v[3])
				st.add_vertex(v[0])


# A curved strip (leaf/frond) from `base` along `dir`, drooping with `droop`.
static func _strip(st: SurfaceTool, base: Vector3, dir: Vector3, length: float, width: float, droop: float, segs := 8, twist := 0.0, col := Color.WHITE) -> void:
	var flat := Vector3(dir.x, 0, dir.z).normalized()
	var across := Vector3(-flat.z, 0, flat.x)
	var prev := []
	for i in segs + 1:
		var t := float(i) / segs
		var p := base + dir * length * t + Vector3.DOWN * droop * t * t
		var a := across.rotated(dir.normalized(), twist * t)
		var l := p - a * width * 0.5
		var r := p + a * width * 0.5
		var cur := [[l, Vector2(0, t)], [r, Vector2(1, t)]]
		if i > 0:
			for v in [prev[0], prev[1], cur[1], prev[0], cur[1], cur[0]]:
				st.set_color(Color(col.r, col.g, col.b, clampf(v[1].y + 0.4, 0.0, 1.0)))
				st.set_uv(v[1])
				st.add_vertex(v[0])
		prev = cur


static func _commit(st: SurfaceTool, mat: Material) -> ArrayMesh:
	st.generate_normals()
	var m := st.commit()
	m.surface_set_material(0, mat)
	return m


# ---------------------------------------------------------------- plants
# Lũy tre: a clump of arching culms with leaf sprays along the upper half.
static func bamboo(parent: Node3D, pos: Vector3, rng: RandomNumberGenerator, culms := 14) -> void:
	var stems := SurfaceTool.new()
	stems.begin(Mesh.PRIMITIVE_TRIANGLES)
	var leaves := SurfaceTool.new()
	leaves.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in culms:
		var a := rng.randf() * TAU
		var root := Vector3(cos(a), 0, sin(a)) * rng.randf_range(0.1, 0.9)
		var hgt := rng.randf_range(7.0, 11.0)
		var lean := Vector3(cos(a), 0, sin(a)) * rng.randf_range(0.15, 0.35)
		var pts := []
		for i in 9:
			var t := i / 8.0
			pts.append(root + Vector3(0, hgt * t, 0) + lean * hgt * t * t * 1.2)
		var green := Color(0.42, 0.55, 0.2).lerp(Color(0.6, 0.62, 0.3), rng.randf())
		_tube(stems, pts, 0.06, 0.018, Color(green.r, green.g, green.b, 0.3), Color(green.r, green.g, green.b, 1.0), 6)
		# leaf cards hanging from the upper culm
		for j in 16:
			var t := rng.randf_range(0.5, 1.0)
			var p := root + Vector3(0, hgt * t, 0) + lean * hgt * t * t * 1.2
			var out := (lean.normalized() * 0.6 + Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)) * 0.6).normalized()
			var sz := rng.randf_range(1.5, 2.4)
			var tint := Color(1, 1, 1).lerp(Color(0.85, 0.95, 0.75), rng.randf())
			for twist in [0.0, PI / 2]:
				var across := Vector3(-out.z, 0, out.x).rotated(out, twist)
				var down := Vector3(0, -0.85, 0) * sz
				var c0 := p - across * sz * 0.5
				var c1 := p + across * sz * 0.5
				var c2 := c1 + out * sz + down
				var c3 := c0 + out * sz + down
				for v in [[c0, Vector2(0, 0)], [c1, Vector2(1, 0)], [c2, Vector2(1, 1)], [c0, Vector2(0, 0)], [c2, Vector2(1, 1)], [c3, Vector2(0, 1)]]:
					leaves.set_color(Color(tint.r, tint.g, tint.b, 1.0))
					# Card UV: twig runs along v.
					leaves.set_uv(Vector2(v[1].x, v[1].y))
					leaves.add_vertex(v[0])
	var yaw := rng.randf() * TAU
	_instance(parent, _commit(stems, material("stem")), pos, yaw)
	var lm := _instance(parent, _commit(leaves, material("bamboo_leaf")), pos, yaw)
	lm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON


static func banana(parent: Node3D, pos: Vector3, rng: RandomNumberGenerator) -> void:
	var stems := SurfaceTool.new()
	stems.begin(Mesh.PRIMITIVE_TRIANGLES)
	var leaves := SurfaceTool.new()
	leaves.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in rng.randi_range(2, 4):
		var a := rng.randf() * TAU
		var root := Vector3(cos(a), 0, sin(a)) * (0.0 if k == 0 else rng.randf_range(0.5, 1.1))
		var hgt := rng.randf_range(1.8, 3.0) * (1.0 if k == 0 else 0.7)
		var top := root + Vector3(rng.randf_range(-0.1, 0.1), hgt, rng.randf_range(-0.1, 0.1))
		_tube(stems, [root, root.lerp(top, 0.5), top], 0.16, 0.1, Color(0.45, 0.5, 0.25, 0.3), Color(0.5, 0.6, 0.28, 1.0), 8)
		var n := rng.randi_range(6, 9)
		for i in n:
			var b := float(i) / n * TAU + rng.randf() * 0.4
			var up := rng.randf_range(0.4, 1.2)
			var dir := Vector3(cos(b), up, sin(b)).normalized()
			var dead := rng.randf() < 0.15
			var col := Color(0.6, 0.48, 0.25) if dead else Color(1, 1, 1).lerp(Color(0.85, 1.0, 0.8), rng.randf())
			_strip(leaves, top + dir * 0.1, dir, rng.randf_range(1.6, 2.4), rng.randf_range(0.5, 0.7), rng.randf_range(0.8, 1.6) * (1.6 if dead else 1.0), 8, rng.randf_range(-0.4, 0.4), col)
	var yaw := rng.randf() * TAU
	_instance(parent, _commit(stems, material("stem")), pos, yaw)
	_instance(parent, _commit(leaves, material("banana_leaf")), pos, yaw)


# Cây cau (slender, ringed) or cây dừa (thicker, more fronds, leaning).
static func palm(parent: Node3D, pos: Vector3, rng: RandomNumberGenerator, coconut := false) -> void:
	var trunk := SurfaceTool.new()
	trunk.begin(Mesh.PRIMITIVE_TRIANGLES)
	var fronds := SurfaceTool.new()
	fronds.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hgt := rng.randf_range(8.0, 11.0) if coconut else rng.randf_range(7.0, 10.0)
	var lean := Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)).normalized() * (rng.randf_range(0.6, 1.6) if coconut else rng.randf_range(0.0, 0.4))
	var pts := []
	for i in 10:
		var t := i / 9.0
		pts.append(Vector3(0, hgt * t, 0) + lean * t * t)
	var bark := Color(0.48, 0.43, 0.36) if coconut else Color(0.5, 0.48, 0.42)
	_tube(trunk, pts, 0.22 if coconut else 0.13, 0.15 if coconut else 0.09, Color(bark.r, bark.g, bark.b, 0.2), Color(bark.r, bark.g, bark.b, 1.0), 8)
	var top: Vector3 = pts[9]
	if not coconut: # green crownshaft
		_tube(trunk, [top, top + Vector3(0, 1.0, 0)], 0.12, 0.1, Color(0.4, 0.55, 0.2, 1), Color(0.45, 0.6, 0.25, 1), 8)
		top += Vector3(0, 1.0, 0)
	var n := 16 if coconut else 12
	for i in n:
		var b := float(i) / n * TAU + rng.randf() * 0.3
		var dir := Vector3(cos(b), rng.randf_range(0.2, 0.9), sin(b)).normalized()
		var length := rng.randf_range(4.0, 5.0) if coconut else rng.randf_range(3.0, 3.8)
		_strip(fronds, top, dir, length, rng.randf_range(1.5, 1.9), length * rng.randf_range(0.35, 0.6), 8, rng.randf_range(-0.3, 0.3))
	if coconut: # a few nuts
		for i in 5:
			var a := rng.randf() * TAU
			var nut := SphereMesh.new()
			nut.radius = 0.13
			nut.height = 0.28
			var m := StandardMaterial3D.new()
			m.albedo_color = Color(0.4, 0.45, 0.2)
			m.roughness = 0.6
			nut.material = m
			_instance(parent, nut, pos + top + Vector3(cos(a) * 0.25, -0.35, sin(a) * 0.25))
	var yaw := rng.randf() * TAU
	_instance(parent, _commit(trunk, material("stem")), pos, yaw)
	_instance(parent, _commit(fronds, material("frond")), pos, yaw)


# Grass tuft: a handful of curved blades, vertex alpha = height for AO.
static func tuft_mesh(blades := 9, height := 0.35, width := 0.025) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = blades * 31 + int(height * 100)
	for i in blades:
		var a := rng.randf() * TAU
		var d := Vector3(cos(a), 0, sin(a))
		var side := Vector3(-d.z, 0, d.x)
		var h := height * rng.randf_range(0.6, 1.2)
		var lean := rng.randf_range(0.15, 0.5)
		var base := d * rng.randf_range(0.0, 0.06)
		# Per-blade hue and value so one tuft is not one flat colour (the
		# instance colour multiplies this).
		var k := rng.randf_range(0.82, 1.12)
		var o := rng.randf()
		var tint := Color(k * (1.0 + 0.12 * o), k, k * (1.0 - 0.25 * o))
		var prev := []
		for s in 5:
			var t := s / 4.0
			var p := base + d * lean * h * t * t + Vector3(0, h * t, 0)
			var w := width * (1.0 - t * 0.9)
			var cur := [p - side * w, p + side * w]
			if s > 0:
				var c0 := Color(tint.r, tint.g, tint.b, (s - 1) / 4.0)
				var c1 := Color(tint.r, tint.g, tint.b, t)
				for v in [[prev[0], c0], [prev[1], c0], [cur[1], c1], [prev[0], c0], [cur[1], c1], [cur[0], c1]]:
					st.set_color(v[1])
					# Normals bent to the sky: a tuft shades as a soft mass,
					# not as flat ribbons flipping light and dark.
					st.set_normal((Vector3.UP * 1.4 + d * 0.6 + side * 0.2).normalized())
					st.add_vertex(v[0])
			prev = cur
	return st.commit()


# One patch of the nursery bed (vạt mạ): ~28 rice seedlings 15-25 cm tall,
# each 3-4 narrow leaves arching from a pale base, sown densely so the bed
# reads as a velvet of young green. Vertex colour carries per-seedling
# variation and COLOR.a the height (AO and wind weight).
static func seedling_patch_mesh(n := 28, radius := 0.075) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	for i in n:
		var r := radius * sqrt(rng.randf())
		var aa := rng.randf() * TAU
		var root := Vector3(cos(aa) * r, 0.0, sin(aa) * r)
		var hgt := rng.randf_range(0.15, 0.25)
		var k := rng.randf_range(0.85, 1.12)
		var yellow := rng.randf()
		var col := Color(0.46, 0.7, 0.2).lerp(Color(0.62, 0.78, 0.3), yellow * 0.6) * k
		var phi := rng.randf() * TAU
		for j in rng.randi_range(3, 4):
			var a := phi + PI * j + rng.randf_range(-0.6, 0.6)
			var d := Vector3(cos(a), 0, sin(a))
			var side := Vector3(-d.z, 0, d.x)
			var ln := hgt * (1.0 - 0.18 * j) * rng.randf_range(0.85, 1.1)
			var th0 := deg_to_rad(4.0 + 10.0 * j + rng.randf_range(0.0, 6.0))
			var droop := deg_to_rad(20.0 + 22.0 * j) * rng.randf_range(0.6, 1.3)
			var w := rng.randf_range(0.0022, 0.0032)
			var p := root + Vector3(0, 0.01 * j, 0)
			var prev := []
			for s in 5:
				var f := s / 4.0
				var th := th0 + droop * f * f
				var tng := (Vector3.UP * cos(th) + d * sin(th)).normalized()
				var ww := w * (1.0 - pow(f, 2.0))
				var cur := [p - side * ww, p + side * ww, p.y]
				if s > 0:
					var nrm := (Vector3.UP * 1.3 + d * 0.5).normalized()
					var c0: Color = Color(0.72, 0.76, 0.5).lerp(col, minf((s - 1) / 1.5, 1.0))
					var c1: Color = Color(0.72, 0.76, 0.5).lerp(col, minf(s / 1.5, 1.0))
					if s == 4:
						c1 = c1.lerp(Color(0.6, 0.55, 0.3), 0.35 * float(rng.randf() < 0.3))
					c0.a = clampf(prev[2] / 0.25, 0.0, 1.0)
					c1.a = clampf(cur[2] / 0.25, 0.0, 1.0)
					for v in [[prev[0], c0], [prev[1], c0], [cur[1], c1], [prev[0], c0], [cur[1], c1], [cur[0], c1]]:
						st.set_color(v[1])
						st.set_normal(nrm)
						st.add_vertex(v[0])
				prev = cur
				p += tng * (ln / 4.0)
	return st.commit()


# The nursery bed: `count` seedling patches on a jittered grid over `size`
# (x, z) metres centred on `center`. main.gd scales the node in y as the
# seedlings grow and hides patches via visible_instance_count as bundles
# are pulled, so the instance count stays fixed.
static func seedling_bed(parent: Node3D, center: Vector3, size: Vector2, count: int, rng: RandomNumberGenerator) -> MultiMeshInstance3D:
	var cols := int(round(sqrt(count * size.x / size.y)))
	var rows := int(ceil(float(count) / cols))
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = seedling_patch_mesh()
	mm.instance_count = count
	for i in count:
		var cx := (float(i % cols) + 0.5 + rng.randf_range(-0.35, 0.35)) / cols - 0.5
		var cz := (float(i / cols) + 0.5 + rng.randf_range(-0.35, 0.35)) / rows - 0.5
		var s := rng.randf_range(0.9, 1.15)
		var b := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s * 1.15, s * rng.randf_range(0.85, 1.1), s * 1.15))
		mm.set_instance_transform(i, Transform3D(b, center + Vector3(cx * size.x, 0.0, cz * size.y)))
		var k := rng.randf_range(0.9, 1.08)
		mm.set_instance_color(i, Color(k, k * rng.randf_range(0.97, 1.03), k))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = material("seedling")
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	mmi.visibility_range_end = 45.0
	mmi.visibility_range_end_margin = 5.0
	mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	parent.add_child(mmi)
	return mmi


# Scatter grass tufts at `points` ([Vector3]) with colour variation.
static func grass(parent: Node3D, points: Array, mesh: Mesh, rng: RandomNumberGenerator, dry := 0.3, chunk := 0.0, view := 45.0) -> MultiMeshInstance3D:
	# Split into chunks that stop drawing beyond `view` metres.
	if chunk > 0.0:
		var cells := {}
		for p in points:
			var k := Vector2i(floori(p.x / chunk), floori(p.z / chunk))
			if not cells.has(k):
				cells[k] = []
			cells[k].append(p)
		var last: MultiMeshInstance3D
		for k in cells:
			last = grass(parent, cells[k], mesh, rng, dry)
			last.visibility_range_end = view
			last.visibility_range_end_margin = 5.0
			last.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		return last
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = points.size()
	for i in points.size():
		var s := rng.randf_range(0.7, 1.4)
		mm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.8, 1.3), s)), points[i]))
		var c := Color(0.3, 0.45, 0.12).lerp(Color(0.45, 0.55, 0.18), rng.randf())
		c = c.lerp(Color(0.62, 0.56, 0.3), rng.randf() * dry)
		mm.set_instance_color(i, c)
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = material("blade")
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mmi)
	return mmi
