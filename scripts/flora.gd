# Vietnamese village plants built in code: bamboo groves (lũy tre), banana
# clumps, areca (cau) and coconut (dừa) palms, broadleaf village trees for
# the far tree lines, and grass tufts. Trees are real geometry: arching
# culms with small leaf-spray cards, palm fronds with a rachis and leaflets,
# banana blades whose halves hang from the midrib. Every tree mesh uses the
# vertex layout of shaders/tree_wind.gdshaderinc, so culm, branch and
# leaves sway together, each culm and frond with its own phase.
extends RefCounted

const FOLIAGE = preload("res://shaders/foliage.gdshader")
const BLADE = preload("res://shaders/grass_blade.gdshader")
const LEAF_CARD = preload("res://shaders/leaf_card.gdshader")
const CULM = preload("res://shaders/bamboo_culm.gdshader")
const FROND = preload("res://shaders/frond.gdshader")
const SPRAY_TEX = preload("res://assets/textures/veg/bamboo_spray.png")
const BANANA_TEX = preload("res://assets/textures/veg/banana_leaf.png")
const TREE_QUALITY = preload("res://scripts/tree_quality.gd")

# Bamboo LOD switch distances (m) and the number of cached grove shapes.
const BAMBOO_LOD := [26.0, 75.0]
const BAMBOO_VARIANTS := 6
const PALM_LOD := 45.0
const LOD_MARGIN := 4.0

static var _mats := {}
static var _meshes := {}
static var _wind: NoiseTexture2D
static var _quality: Node


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
			m.set_shader_parameter("translucency", 0.18)
			m.set_shader_parameter("rough", 0.6)
			m.set_shader_parameter("keep_normal", true)
		"blade": # rice and grass: colour from vertices/instances
			m.set_shader_parameter("sway", 0.09)
			m.set_shader_parameter("keep_normal", true)
			m.set_shader_parameter("translucency", 0.15)
	_mats[kind] = m
	return m


# Tree materials. Wind amplitudes must match between the parts of one plant
# (culm and leaves, trunk and fronds) or the leaves come loose in a gust.
static func tree_material(kind: String) -> ShaderMaterial:
	if _mats.has(kind):
		return _mats[kind]
	var m := ShaderMaterial.new()
	var p := {"noise": wind_noise()}
	match kind:
		"culm":
			m.shader = CULM
			p.merge({"plant_height": 12.0, "trunk_sway": 0.4, "branch_sway": 0.22})
		"spray": # bamboo leaf sprays
			m.shader = LEAF_CARD
			p.merge({"leaf_alb": SPRAY_TEX, "plant_height": 12.0, "trunk_sway": 0.4, "branch_sway": 0.22, "flutter": 0.03, "translucency": 0.65})
		"tree_leaf": # broadleaf crowns of the far village trees
			m.shader = LEAF_CARD
			p.merge({"leaf_alb": SPRAY_TEX, "plant_height": 9.0, "trunk_sway": 0.12, "branch_sway": 0.15, "flutter": 0.02, "translucency": 0.4, "tint": Color(0.78, 0.86, 0.66), "ao_low": 0.55})
		"tree_wood":
			m.shader = FROND
			p.merge({"plant_height": 9.0, "trunk_sway": 0.12, "branch_sway": 0.15, "translucency": 0.0, "rough": 0.85, "spec": 0.3})
		"banana_leaf":
			m.shader = LEAF_CARD
			p.merge({"leaf_alb": BANANA_TEX, "plant_height": 3.0, "trunk_sway": 0.07, "branch_sway": 0.2, "flutter": 0.04, "translucency": 0.55, "rough": 0.6, "spec": 0.25})
		"banana_dead":
			m.shader = LEAF_CARD
			p.merge({"leaf_alb": BANANA_TEX, "plant_height": 3.0, "trunk_sway": 0.07, "branch_sway": 0.1, "flutter": 0.01, "translucency": 0.2, "rough": 0.8, "spec": 0.3, "dry": 1.0})
		"banana_stem":
			m.shader = FROND
			p.merge({"plant_height": 3.0, "trunk_sway": 0.07, "branch_sway": 0.2, "translucency": 0.15, "rough": 0.55})
		"palm_leaf":
			m.shader = FROND
			p.merge({"plant_height": 11.0, "trunk_sway": 0.3, "branch_sway": 0.3, "flutter": 0.04, "translucency": 0.4, "rough": 0.6, "spec": 0.3})
		"areca_trunk": # grey with pale leaf-scar rings
			m.shader = CULM
			p.merge({"plant_height": 11.0, "trunk_sway": 0.3, "internode": 0.16, "young": Color(0.5, 0.51, 0.45), "old": Color(0.47, 0.47, 0.43),
				"sheath_amount": 0.0, "wax": 0.1, "node_dark": 0.3, "node_width": 0.02, "streaks": 0.05, "rough_range": Vector2(0.7, 0.9)})
		"coconut_trunk": # grey-brown, rough, close leaf scars
			m.shader = CULM
			p.merge({"plant_height": 11.0, "trunk_sway": 0.3, "internode": 0.07, "young": Color(0.47, 0.42, 0.36), "old": Color(0.55, 0.52, 0.47),
				"sheath_amount": 0.0, "wax": 0.0, "node_dark": 0.35, "node_width": 0.025, "streaks": 0.12, "bark_noise": 0.35, "rough_range": Vector2(0.85, 0.95)})
	for k in p:
		m.set_shader_parameter(k, p[k])
	_mats[kind] = m
	return m


# ---------------------------------------------------------------- mesh helpers
# One surface. Vertex layout (tree_wind.gdshaderinc): COLOR.a = height
# fraction on the culm or trunk, UV2 = (branch index + 0.999 * along, phase).
class Buf:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var t := PackedFloat32Array()
	var uv := PackedVector2Array()
	var uv2 := PackedVector2Array()
	var c := PackedColorArray()
	var i := PackedInt32Array()

	func vert(p: Vector3, nrm: Vector3, u: Vector2, u2: Vector2, col: Color, tan := Vector3.RIGHT) -> int:
		v.append(p)
		n.append(nrm)
		t.append_array([tan.x, tan.y, tan.z, -1.0])
		uv.append(u)
		uv2.append(u2)
		c.append(col)
		return v.size() - 1

	func commit(m: ArrayMesh, mat: Material) -> void:
		if i.is_empty():
			return
		var a := []
		a.resize(Mesh.ARRAY_MAX)
		a[Mesh.ARRAY_VERTEX] = v
		a[Mesh.ARRAY_NORMAL] = n
		a[Mesh.ARRAY_TANGENT] = t
		a[Mesh.ARRAY_TEX_UV] = uv
		a[Mesh.ARRAY_TEX_UV2] = uv2
		a[Mesh.ARRAY_COLOR] = c
		a[Mesh.ARRAY_INDEX] = i
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
		m.surface_set_material(m.get_surface_count() - 1, mat)


static func _instance(parent: Node3D, mesh: Mesh, pos: Vector3, yaw := 0.0, scale := 1.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.transform = Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * scale), pos)
	parent.add_child(mi)
	return mi


# Distance LOD with a short cross-fade. Registered with the tree quality
# node so Low and Medium can pull the switch distances in.
static func _lod_range(gi: GeometryInstance3D, begin: float, end: float) -> void:
	if _quality == null or not is_instance_valid(_quality):
		_quality = TREE_QUALITY.new()
		_quality.name = "TreeQuality"
		gi.add_sibling.call_deferred(_quality)
	_quality.nodes.append(gi)
	gi.set_meta("lod_range", Vector2(begin, end))
	gi.visibility_range_begin = begin
	gi.visibility_range_begin_margin = LOD_MARGIN if begin > 0.0 else 0.0
	gi.visibility_range_end = end
	gi.visibility_range_end_margin = LOD_MARGIN if end > 0.0 else 0.0
	gi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF


# A tube along `pts` (parallel-transported frame, so arching culms do not
# twist). UV.x runs around and UV.y is metres along (nodes and rings), or,
# with `ao` set, UV = (ambient occlusion, 0) for the frond shader. COLOR.a
# runs h.x..h.y, UV2 u2a..u2b. `swell` widens the base (coconut bole).
static func _tube(b: Buf, pts: Array, r0: float, r1: float, sides: int, col: Color, h: Vector2, u2a: Vector2, u2b: Vector2, ao := Vector2(-1, -1), swell := 0.0, ring_cols := PackedColorArray()) -> void:
	var n := pts.size()
	var base := b.v.size()
	var along := 0.0
	var side := Vector3.ZERO
	for k in n:
		var f := float(k) / (n - 1)
		var p: Vector3 = pts[k]
		if k > 0:
			along += p.distance_to(pts[k - 1])
		var fwd: Vector3 = (pts[mini(k + 1, n - 1)] - pts[maxi(k - 1, 0)]).normalized()
		if k == 0:
			side = fwd.cross(Vector3.FORWARD if absf(fwd.z) < 0.9 else Vector3.RIGHT).normalized()
		else:
			side = (side - fwd * side.dot(fwd)).normalized()
		var up := side.cross(fwd)
		var r := lerpf(r0, r1, f) + swell * pow(1.0 - f, 6.0)
		var cc: Color = ring_cols[k] if k < ring_cols.size() else col
		cc.a = lerpf(h.x, h.y, f)
		var u2 := u2a.lerp(u2b, f)
		for s in sides + 1:
			var a := TAU * s / sides
			var d := side * cos(a) + up * sin(a)
			var uv := Vector2(float(s) / sides, along) if ao.x < 0.0 else Vector2(lerpf(ao.x, ao.y, f), 0.0)
			b.vert(p + d * r, d, uv, u2, cc, up * cos(a) - side * sin(a))
	for k in n - 1:
		for s in sides:
			var a := base + k * (sides + 1) + s
			var a2 := a + sides + 1
			b.i.append_array([a, a2, a + 1, a + 1, a2, a2 + 1])


# A low ellipsoid (nuts, fruit) for the frond shader.
static func _blob(b: Buf, c: Vector3, r: Vector3, col: Color, u2: Vector2, ao: float, lat := 4, lon := 6) -> void:
	var base := b.v.size()
	for y in lat + 1:
		var th := PI * y / lat
		for x in lon + 1:
			var ph := TAU * x / lon
			var d := Vector3(sin(th) * cos(ph), cos(th), sin(th) * sin(ph))
			b.vert(c + d * r, d, Vector2(ao * (0.75 + 0.25 * d.y), 0.0), u2, col)
	for y in lat:
		for x in lon:
			var a := base + y * (lon + 1) + x
			var a2 := a + lon + 1
			b.i.append_array([a, a + 1, a2, a + 1, a2 + 1, a2])


# A leaf-spray card hanging from `p` along `dir` (texture: the twig runs
# down the middle from v = 0), bent down in `rows` rows and rolled about its
# axis. Normals blend the card normal with the direction from the crown
# centre, so the canopy shades like a volume and not a stack of paper.
static func _card(b: Buf, p: Vector3, dir: Vector3, length: float, width: float, roll: float, droop: float, rows: int, crown: Vector3, col: Color, u2: Vector2, blend := 0.6) -> void:
	var d := dir.normalized()
	var across := Vector3.UP.cross(d)
	if across.length() < 0.05:
		across = Vector3.RIGHT
	across = across.normalized().rotated(d, roll)
	var base := b.v.size()
	for row in rows + 1:
		var f := float(row) / rows
		var pos := p + d * length * f + Vector3.DOWN * length * droop * f * f
		var tng := (d + Vector3.DOWN * 2.0 * droop * f).normalized()
		var card_n := tng.cross(across).normalized()
		if card_n.y < 0.0:
			card_n = -card_n
		var nrm := card_n.lerp((pos - crown).normalized(), blend).normalized()
		for s in 2:
			b.vert(pos + across * width * (float(s) - 0.5), nrm, Vector2(float(s), f), u2, col)
	for row in rows:
		var a := base + row * 2
		b.i.append_array([a, a + 2, a + 1, a + 1, a + 2, a + 3])


# ---------------------------------------------------------------- bamboo
# Lũy tre clump (Bambusa, tre gai): 30-40 culms 9-14 m tall from a base about
# 3 m across, 7-10 cm thick with little taper; the outer culms arch out and
# down (the fountain silhouette of a village hedge). Branches grow at the
# nodes of the upper 60 % and end in leaf sprays of 6-12 leaves 10-25 cm long.
# lod 0: full (~30 k triangles); 1: coarser culms, no branch wood, two bigger
# sprays per branch (~7 k); 2: beyond 75 m and shadow proxy (~3.6 k); 3: the
# far villages (~1.3 k, a third of the culms, big sprays). Every LOD draws the same
# random numbers, so the culms keep their shape when the LOD switches.
static func bamboo_mesh(variant: int, lod: int) -> ArrayMesh:
	var key := "bamboo%d_%d" % [variant, lod]
	if _meshes.has(key):
		return _meshes[key]
	var wood := Buf.new()
	var leaves := Buf.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = variant * 7919 + 13
	var culms := rng.randi_range(40, 52)
	var crown := Vector3(0.0, 6.0, 0.0)
	var segs: int = [14, 8, 5, 4][lod]
	var sides: int = [7, 5, 4, 3][lod]
	var bid := 0
	for k in culms:
		var r := RandomNumberGenerator.new()
		r.seed = rng.randi()
		var az := r.randf() * TAU
		var out := Vector3(cos(az), 0.0, sin(az))
		var rf := sqrt(r.randf())
		var root := out * rf * 1.7
		var hgt := r.randf_range(9.0, 14.0) * (1.0 - 0.2 * rf * r.randf())
		var arch := r.randf_range(0.55, 1.25) * (0.5 + 0.75 * rf)
		var lean := (out + Vector3(r.randf_range(-0.35, 0.35), 0.0, r.randf_range(-0.35, 0.35))).normalized()
		var pts := []
		var tng := []
		var p := root
		for s in segs + 1:
			var f := float(s) / segs
			var th := 0.04 + 0.14 * rf + arch * pow(f, 2.0)
			var d := Vector3.UP * cos(th) + lean * sin(th)
			pts.append(p)
			tng.append(d)
			p += d * hgt / segs
		var age := r.randf()
		var col := Color(r.randf_range(0.85, 1.08), r.randf() * 0.5, age, 0.0)
		var ph := r.randf()
		var cr := r.randf_range(0.035, 0.05)
		if lod < 3 or k % 3 == 0: # culms are sub-pixel in the far villages
			_tube(wood, pts, cr, 0.012, sides, col, Vector2(0.0, 1.0), Vector2(0.0, ph), Vector2(0.0, ph))
		# Branches at the nodes, alternating sides: short twiggy ones low down
		# (the thorny tangle of tre gai), long leafy ones in the upper 60 %.
		var node := r.randf_range(0.3, 0.42)
		var along := r.randf_range(0.0, node)
		var bside := 1.0 if r.randf() < 0.5 else -1.0
		while true:
			along += node
			var f := along / hgt
			if f >= 0.97:
				break
			if f < 0.15:
				continue
			var low := f < 0.38
			var q := f * segs
			var i0 := mini(int(q), segs - 1)
			var bp: Vector3 = (pts[i0] as Vector3).lerp(pts[i0 + 1], q - i0)
			var ct: Vector3 = tng[i0]
			bside = -bside
			var radial := ct.cross(Vector3.UP)
			if radial.length() < 0.05:
				radial = Vector3.RIGHT
			radial = radial.normalized().rotated(ct, bside * 1.3 + r.randf_range(-0.5, 0.5))
			var blen := r.randf_range(0.25, 0.6) if low else r.randf_range(0.6, 1.6) * (1.0 - 0.6 * absf(f - 0.65))
			var bdir := (radial * 0.85 + ct * 0.45 + Vector3.DOWN * 0.1).normalized()
			var bend := Vector3.DOWN * blen * 0.2
			var u2a := Vector2(bid, ph)
			if lod == 0:
				_tube(wood, [bp, bp + bdir * blen * 0.5 + bend * 0.25, bp + bdir * blen + bend], 0.008, 0.003, 3, col, Vector2(f, f), u2a, Vector2(bid + 0.999, ph))
			var cards := r.randi_range(2, 3) if low else r.randi_range(5, 8)
			for j in cards:
				var g := (j + 1.0) / cards
				var cdir := (bdir + Vector3(r.randf_range(-0.6, 0.6), r.randf_range(-0.7, 0.1), r.randf_range(-0.6, 0.6))).normalized()
				var length := r.randf_range(0.4, 0.6) if low else r.randf_range(0.55, 0.9)
				var roll := r.randf_range(-0.9, 0.9)
				var droop := r.randf_range(0.1, 0.45)
				var tint := Color(1, 1, 1).lerp(Color(0.82, 0.97, 0.7), r.randf())
				if r.randf() < 0.07:
					tint = Color(1.0, 0.9, 0.5) # a yellowing spray
				var keep := lod == 0 or (lod == 1 and (j == cards - 1 or j == (cards - 1) / 2)) or (lod == 2 and j == cards - 1) or (lod == 3 and j == cards - 1 and bid % 3 == 0)
				if not keep:
					continue
				var grow: float = [1.0, 1.6, 2.5 if not low else 1.6, 4.0 if not low else 2.6][lod]
				# Sprays deep inside the clump are darker (light reaches them through the canopy).
				var cp := bp + bdir * blen * g + bend * g * g
				tint = tint.darkened(0.3 * (1.0 - clampf(Vector2(cp.x, cp.z).length() / 4.5, 0.0, 1.0)) + (0.15 if low else 0.0))
				tint.a = f
				_card(leaves, cp, cdir, length * grow, length * grow * 0.5, roll, droop, 2 if lod == 0 else 1, crown, tint, Vector2(bid + 0.999 * g, ph))
			bid += 1
	var m := ArrayMesh.new()
	wood.commit(m, tree_material("culm"))
	leaves.commit(m, tree_material("spray"))
	_meshes[key] = m
	return m


# A grove: one node per LOD, switched by distance with a short cross-fade.
# Shadows come from a separate LOD 2 proxy (same culms, same leaf coverage,
# a tenth of the triangles): the dappled shadow is soft anyway.
static func bamboo(parent: Node3D, pos: Vector3, rng: RandomNumberGenerator, scale := 1.0) -> void:
	var v := rng.randi() % BAMBOO_VARIANTS
	var yaw := rng.randf() * TAU
	for lod in 3:
		var mi := _instance(parent, bamboo_mesh(v, lod), pos, yaw, scale)
		_lod_range(mi, 0.0 if lod == 0 else BAMBOO_LOD[lod - 1], BAMBOO_LOD[lod] if lod < 2 else 0.0)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var sh := _instance(parent, bamboo_mesh(v, 2), pos, yaw, scale)
	sh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	_lod_range(sh, 0.0, BAMBOO_LOD[1])


# ---------------------------------------------------------------- banana
# One banana leaf: 5 vertices across with the two halves hanging from the
# midrib (lamina angle), the midrib arching down toward the tip. Texture:
# across = u, along = v from the petiole. UV2.x runs from `from` to 1 along
# the whole leaf (petiole included) so the blade swings from its base.
static func _banana_leaf(b: Buf, base: Vector3, dir: Vector3, length: float, width: float, droop: float, hang: float, segs: int, center: Vector3, col: Color, bid: int, ph: float, from: float) -> void:
	var flat := Vector3(dir.x, 0.0, dir.z).normalized()
	var side := Vector3.UP.cross(flat).normalized()
	var th0 := acos(clampf(dir.y, -1.0, 1.0))
	var p := base
	var start := b.v.size()
	for s in segs + 1:
		var f := float(s) / segs
		var th := minf(th0 + droop * f * f, PI * 0.97)
		var t := Vector3.UP * cos(th) + flat * sin(th)
		var up := t.cross(side).normalized()
		var hw := width * 0.5
		var hh := hang * (0.6 + 0.4 * f)
		var u2 := Vector2(bid + 0.999 * lerpf(from, 1.0, f), ph)
		for k in 5:
			var a := (k - 2) / 2.0
			var lam := absf(a)
			var pos := p + side * a * hw * cos(hh * lam) - up * hw * lam * sin(hh * lam)
			var nrm := (up * cos(hh * lam) + side * signf(a) * sin(hh * lam)).lerp((pos - center).normalized(), 0.35).normalized()
			b.vert(pos, nrm, Vector2(0.5 + a * 0.5, f), u2, col)
		p += t * length / segs
	for s in segs:
		for k in 4:
			var a := start + s * 5 + k
			b.i.append_array([a, a + 5, a + 1, a + 1, a + 5, a + 6])


# Bụi chuối: a main plant 2.2-3.2 m and 1-3 suckers. Pseudostems of
# overlapping sheaths (green with brown blotches), leaves in a spiral: the
# youngest steep, the older ones flatter and drooping, the oldest dead and
# hanging brown down the stem. Some plants carry a fruit bunch and the purple
# flower bell (bắp chuối).
static func banana_mesh(variant: int) -> ArrayMesh:
	var key := "banana%d" % variant
	if _meshes.has(key):
		return _meshes[key]
	var stems := Buf.new()
	var leaves := Buf.new()
	var dead := Buf.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = variant * 4111 + 7
	var bid := 0
	for k in rng.randi_range(2, 4):
		var main := k == 0
		var a := rng.randf() * TAU
		var root := Vector3.ZERO if main else Vector3(cos(a), 0.0, sin(a)) * rng.randf_range(0.5, 1.0)
		var hgt := rng.randf_range(2.2, 3.2) if main else rng.randf_range(0.7, 1.9)
		var top := root + Vector3(rng.randf_range(-0.12, 0.12), hgt, rng.randf_range(-0.12, 0.12))
		var ph := rng.randf()
		var hf := hgt / 3.0
		var pts := []
		var cols := PackedColorArray()
		for s in 7:
			var f := s / 6.0
			pts.append(root.lerp(top, f))
			var c := Color(0.55, 0.62, 0.32).lerp(Color(0.42, 0.52, 0.24), rng.randf())
			if rng.randf() < 0.4:
				c = c.lerp(Color(0.3, 0.22, 0.13), rng.randf_range(0.3, 0.7))
			if f < 0.25:
				c = c.lerp(Color(0.48, 0.38, 0.24), 0.55)
			cols.append(c)
		var sr := 0.06 + 0.03 * hgt
		_tube(stems, pts, sr, sr * 0.65, 8, Color.WHITE, Vector2(0.0, hf), Vector2(0.0, ph), Vector2(0.0, ph), Vector2(0.45, 0.95), 0.0, cols)
		var n := rng.randi_range(8, 11) if main else rng.randi_range(4, 7)
		var size := 1.0 if main else 0.45 + 0.25 * hgt
		var b0 := rng.randf() * TAU
		for i in n:
			var age := float(i) / (n - 1)
			var b := b0 + i * 2.4 + rng.randf_range(-0.3, 0.3)
			var out := Vector3(cos(b), 0.0, sin(b))
			var attach := top - Vector3(0, age * 0.25 * size, 0)
			if age > 0.82 and rng.randf() < 0.75:
				# a dead leaf hanging down along the stem
				var dd := (out * 0.35 + Vector3.DOWN).normalized()
				_banana_leaf(dead, attach + out * sr, dd, rng.randf_range(1.0, 1.6) * size, rng.randf_range(0.25, 0.4) * size, 0.0, 1.2, 6, top, Color(1, 1, 1, hf), bid, ph, 0.0)
				bid += 1
				continue
			var up := lerpf(0.9, 0.15, age) + rng.randf_range(-0.1, 0.1)
			var dir := (out * sqrt(1.0 - up * up) + Vector3.UP * up).normalized()
			var plen := rng.randf_range(0.3, 0.5) * size
			var pend := attach + dir * plen
			var green := Color(1, 1, 1).lerp(Color(0.85, 0.95, 0.8), rng.randf())
			if age > 0.7:
				green = green.lerp(Color(1.0, 0.92, 0.6), rng.randf() * 0.6)
			green.a = hf
			_tube(stems, [attach, attach.lerp(pend, 0.5), pend], 0.035 * size, 0.022 * size, 4, Color(0.5, 0.6, 0.3), Vector2(hf, hf), Vector2(bid, ph), Vector2(bid + 0.15, ph), Vector2(0.6, 0.9))
			var lead := rng.randf_range(1.5, 2.3) * size
			_banana_leaf(leaves, pend, dir, lead, rng.randf_range(0.45, 0.6) * size, rng.randf_range(0.5, 1.1) + age * 0.9, rng.randf_range(0.25, 0.6), 9, top, green, bid, ph, 0.15)
			bid += 1
		if main and rng.randf() < 0.5:
			# fruit bunch on a stalk curving out and down, with the flower bell
			var o := Vector3(cos(b0 + 1.0), 0.0, sin(b0 + 1.0))
			var stalk := [top, top + o * 0.3 + Vector3.UP * 0.12, top + o * 0.55 - Vector3.UP * 0.35, top + o * 0.6 - Vector3.UP * 1.0, top + o * 0.6 - Vector3.UP * 1.25]
			_tube(stems, stalk, 0.03, 0.022, 5, Color(0.45, 0.52, 0.28), Vector2(hf, hf), Vector2(bid, ph), Vector2(bid + 0.999, ph), Vector2(0.6, 0.9))
			for hand in 5:
				var g := 0.5 + hand * 0.1
				var hp: Vector3 = (stalk[2] as Vector3).lerp(stalk[3], (g - 0.4) / 0.6)
				for fi in 10:
					var fa := fi * TAU / 10.0 + hand * 0.4
					var rd := Vector3(cos(fa), 0.0, sin(fa))
					var fp := [hp + rd * 0.05, hp + rd * 0.12 + Vector3.UP * 0.05, hp + rd * 0.16 + Vector3.UP * 0.15]
					_tube(stems, fp, 0.022, 0.014, 4, Color(0.42, 0.52, 0.2), Vector2(hf, hf), Vector2(bid + 0.999 * g, ph), Vector2(bid + 0.999 * g, ph), Vector2(0.5, 0.85))
			var tip: Vector3 = stalk[4]
			_tube(stems, [tip, tip - Vector3.UP * 0.15, tip - Vector3.UP * 0.32], 0.075, 0.01, 6, Color(0.4, 0.13, 0.17), Vector2(hf, hf), Vector2(bid + 0.999, ph), Vector2(bid + 0.999, ph), Vector2(0.7, 0.9))
			bid += 1
	var m := ArrayMesh.new()
	stems.commit(m, tree_material("banana_stem"))
	leaves.commit(m, tree_material("banana_leaf"))
	dead.commit(m, tree_material("banana_dead"))
	_meshes[key] = m
	return m


static func banana(parent: Node3D, pos: Vector3, rng: RandomNumberGenerator, view := 90.0) -> void:
	var mi := _instance(parent, banana_mesh(rng.randi() % 8), pos, rng.randf() * TAU, rng.randf_range(0.85, 1.1))
	_lod_range(mi, 0.0, view)


# ---------------------------------------------------------------- palms
# One pinnate frond. The rachis arcs over (droop * f²); leaflet pairs leave
# it forward and sideways, lifted into a V by `keel`, their tips hanging by
# `hang`. Leaflets are 2-vertex strips (alpha-free).
static func _frond(b: Buf, base: Vector3, dir: Vector3, length: float, pairs: int, ll: float, lw: float, droop: float, keel: float, hang: float, lsegs: int, col: Color, tip: Color, bid: int, ph: float, center: Vector3, rachis: float, fwd := 0.55) -> void:
	var flat := Vector3(dir.x, 0.0, dir.z)
	flat = flat.normalized() if flat.length() > 0.01 else Vector3.RIGHT
	var side := Vector3.UP.cross(flat).normalized()
	var segs := 10 if lsegs > 1 else 5
	var pts := []
	var tans := []
	var p := base
	var th0 := acos(clampf(dir.y, -1.0, 1.0))
	for s in segs + 1:
		var f := float(s) / segs
		var th := minf(th0 + droop * f * f, PI * 0.95)
		var t := Vector3.UP * cos(th) + flat * sin(th)
		pts.append(p)
		tans.append(t)
		p += t * length / segs
	var rc := col.lerp(Color(0.62, 0.6, 0.35), 0.5)
	rc.a = 1.0
	_tube(b, pts, rachis, rachis * 0.25, 3, rc, Vector2(1.0, 1.0), Vector2(bid, ph), Vector2(bid + 0.999, ph), Vector2(0.5, 1.0))
	for k in pairs:
		var f := 0.1 + 0.88 * float(k) / pairs
		var q := f * segs
		var i := mini(int(q), segs - 1)
		var rp: Vector3 = (pts[i] as Vector3).lerp(pts[i + 1], q - i)
		var rt: Vector3 = (tans[i] as Vector3).lerp(tans[i + 1], q - i).normalized()
		var rup := rt.cross(side).normalized()
		var lk := ll * (0.35 + 0.65 * sin(PI * clampf(f * 1.05, 0.05, 1.0)))
		var c := col.lerp(tip, f * f * 0.6)
		var u2 := Vector2(bid + 0.999 * f, ph)
		var ao := 0.35 + 0.65 * f
		for sgn: float in [-1.0, 1.0]:
			var out := (rt * fwd + side * sgn * 0.8 + rup * keel).normalized()
			var across := rup.cross(out).normalized()
			var base_i := b.v.size()
			for s in lsegs + 1:
				var g := float(s) / lsegs
				var cp := rp + out * lk * g + Vector3.DOWN * lk * hang * g * g
				var w := lw * (1.0 - 0.75 * g)
				var nrm := rup.lerp((cp - center).normalized(), 0.5).normalized()
				var cc := c.lerp(tip, 0.25 * g)
				cc.a = 1.0
				b.vert(cp - across * w, nrm, Vector2(ao, g), u2, cc)
				b.vert(cp + across * w, nrm, Vector2(ao, g), u2, cc)
			for s in lsegs:
				var a := base_i + s * 2
				b.i.append_array([a, a + 2, a + 1, a + 1, a + 2, a + 3])


# Cây cau (areca): a slender grey trunk with pale rings, a smooth green
# crownshaft and 8-11 arching fronds 1.8-2.4 m, nut bunches below the shaft.
# Cây dừa (coconut): a thicker grey-brown trunk curving up from a swollen
# base, 20-26 fronds 3.8-5 m whose leaflets hang from a V-shaped keel, the
# lower fronds yellowing, dead ones hanging down the trunk, a ring of nuts.
# lod 1 (far): one segment per leaflet, half the leaflets, twice as wide.
static func palm_mesh(variant: int, coconut: bool, lod: int) -> ArrayMesh:
	var key := "palm%d_%s_%d" % [variant, coconut, lod]
	if _meshes.has(key):
		return _meshes[key]
	var trunk := Buf.new()
	var crown := Buf.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = variant * 104729 + (1 if coconut else 0)
	var hgt := rng.randf_range(10.0, 14.0) if coconut else rng.randf_range(9.0, 13.0)
	var az := rng.randf() * TAU
	var lean_dir := Vector3(cos(az), 0.0, sin(az))
	var lean := rng.randf_range(1.0, 2.6) if coconut else rng.randf_range(0.1, 0.5)
	var ph := rng.randf()
	var n := 14 if lod == 0 else 7
	var pts := []
	for i in n + 1:
		var t := float(i) / n
		var off := (1.0 - pow(1.0 - t, 1.8)) if coconut else t * t
		pts.append(Vector3(0, hgt * t, 0) + lean_dir * lean * off)
	var tc := Color(rng.randf_range(0.9, 1.05), 0.0, rng.randf(), 0.0)
	if coconut:
		_tube(trunk, pts, 0.16, 0.13, 10 if lod == 0 else 6, tc, Vector2(0.0, 1.0), Vector2(0.0, ph), Vector2(0.0, ph), Vector2(-1, -1), 0.14)
	else:
		_tube(trunk, pts, 0.085, 0.065, 8 if lod == 0 else 5, tc, Vector2(0.0, 1.0), Vector2(0.0, ph), Vector2(0.0, ph))
	var top: Vector3 = pts[n]
	var up_dir := ((pts[n] as Vector3) - (pts[n - 1] as Vector3)).normalized()
	var bid := 1
	var lsegs := 3 if lod == 0 else 1
	var wide := 1.0 if lod == 0 else 3.0
	if not coconut:
		# smooth green crownshaft
		var cs := [top, top + up_dir * 0.6, top + up_dir * 1.15]
		_tube(crown, cs, 0.09, 0.07, 8 if lod == 0 else 5, Color(0.42, 0.55, 0.25), Vector2(1.0, 1.0), Vector2(0.0, ph), Vector2(0.0, ph), Vector2(0.75, 1.0))
		# nut bunches hanging just below the crownshaft
		for bunch in rng.randi_range(1, 3):
			var ba := rng.randf() * TAU
			var bo := Vector3(cos(ba), 0.0, sin(ba))
			var bc := top + bo * 0.16 - Vector3.UP * 0.25
			var ripe := rng.randf() < 0.4
			for k in (14 if lod == 0 else 5):
				var np := bc + Vector3(rng.randf_range(-0.12, 0.12), rng.randf_range(-0.3, 0.05), rng.randf_range(-0.12, 0.12)) + bo * rng.randf_range(0.0, 0.1)
				var nc := Color(0.85, 0.5, 0.15) if ripe else Color(0.42, 0.55, 0.2)
				nc.a = 1.0
				_blob(crown, np, Vector3(0.028, 0.038, 0.028), nc.lerp(Color(0.5, 0.45, 0.2), rng.randf() * 0.3), Vector2(0.0, ph), 0.6, 3, 4)
		top = cs[2]
	var nf := rng.randi_range(20, 26) if coconut else rng.randi_range(8, 11)
	var center := top - Vector3.UP * (0.6 if coconut else 0.3)
	var g0 := rng.randf() * TAU
	for i in nf:
		var age := float(i) / (nf - 1)
		var b := g0 + i * 2.39996 + rng.randf_range(-0.15, 0.15)
		var out := Vector3(cos(b), 0.0, sin(b))
		var elev := lerpf(0.92, -0.05, age) + rng.randf_range(-0.08, 0.08)
		var dir := (out * sqrt(maxf(1.0 - elev * elev, 0.0)) + Vector3.UP * elev).normalized()
		var base := top - Vector3.UP * age * (0.4 if coconut else 0.15) + out * 0.05
		var green := Color(0.27, 0.4, 0.12).lerp(Color(0.38, 0.48, 0.15), rng.randf())
		var tip := Color(0.48, 0.5, 0.22)
		if coconut and age > 0.75:
			green = green.lerp(Color(0.62, 0.56, 0.24), (age - 0.75) * 3.0 * rng.randf())
			tip = Color(0.55, 0.42, 0.22)
		var young := 0.7 if age < 0.1 else 1.0
		if coconut:
			_frond(crown, base, dir, rng.randf_range(3.8, 5.0) * young, 42 / int(wide), 0.8, 0.022 * wide, rng.randf_range(0.5, 0.9) + age * 1.0, 0.45, 0.55, lsegs, green, tip, bid, ph, center, 0.045)
		else:
			_frond(crown, base, dir, rng.randf_range(1.8, 2.4) * young, 30 / int(wide), 0.5, 0.022 * wide, rng.randf_range(0.5, 0.8) + age * 0.6, 0.15, 0.25, lsegs, green, tip, bid, ph, center, 0.03, 0.8)
		bid += 1
	if coconut:
		# two or three dead fronds hanging down the trunk
		for i in rng.randi_range(2, 3):
			var b := rng.randf() * TAU
			var dir := (Vector3(cos(b), 0.0, sin(b)) * 0.45 + Vector3.DOWN).normalized()
			_frond(crown, top - Vector3.UP * 0.5, dir, rng.randf_range(2.5, 3.5), 30 / int(wide), 0.6, 0.02 * wide, 0.0, -0.3, 0.2, lsegs, Color(0.5, 0.4, 0.24), Color(0.42, 0.33, 0.2), bid, ph, center, 0.04)
			bid += 1
		# the ring of nuts under the crown
		for k in rng.randi_range(8, 14):
			var na := rng.randf() * TAU
			var np := top + Vector3(cos(na), 0.0, sin(na)) * rng.randf_range(0.18, 0.32) - Vector3.UP * rng.randf_range(0.35, 0.65)
			var nc := Color(0.4, 0.48, 0.16).lerp(Color(0.55, 0.5, 0.2), rng.randf())
			if rng.randf() < 0.2:
				nc = Color(0.45, 0.33, 0.18)
			nc.a = 1.0
			_blob(crown, np, Vector3(0.12, 0.14, 0.12), nc, Vector2(0.0, ph), 0.55, 4 if lod == 0 else 3, 6 if lod == 0 else 4)
	var m := ArrayMesh.new()
	trunk.commit(m, tree_material("coconut_trunk" if coconut else "areca_trunk"))
	crown.commit(m, tree_material("palm_leaf"))
	_meshes[key] = m
	return m


static func palm(parent: Node3D, pos: Vector3, rng: RandomNumberGenerator, coconut := false, far := false) -> void:
	var v := rng.randi() % 10
	var yaw := rng.randf() * TAU
	if not far:
		var near := _instance(parent, palm_mesh(v, coconut, 0), pos, yaw)
		_lod_range(near, 0.0, PALM_LOD)
		near.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var sh := _instance(parent, palm_mesh(v, coconut, 1), pos, yaw)
		sh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
		_lod_range(sh, 0.0, PALM_LOD)
	var mi := _instance(parent, palm_mesh(v, coconut, 1), pos, yaw)
	_lod_range(mi, 0.0 if far else PALM_LOD, 0.0)
	if far:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


# ---------------------------------------------------------------- village trees
# Broadleaf village trees for the far tree lines (nhãn, vải, xoan, gạo): a
# trunk forking into a few limbs, each ending in a cluster of leaf cards
# facing out of the crown. Only used beyond ~50 m, where single leaves are
# not resolved, so a few hundred triangles are enough.
static func village_tree_mesh(variant: int) -> ArrayMesh:
	var key := "vtree%d" % variant
	if _meshes.has(key):
		return _meshes[key]
	var wood := Buf.new()
	var leaves := Buf.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = variant * 6007 + 3
	var hgt := rng.randf_range(7.0, 16.0)
	var rad := rng.randf_range(2.2, 4.5) * (0.6 + 0.4 * hgt / 10.0)
	var squash := rng.randf_range(0.55, 1.1)
	var bole := rng.randf_range(0.3, 0.5) # crown starts at this fraction of the height
	var cc := Vector3(0.0, hgt * (bole + (1.0 - bole) * 0.5), 0.0)
	var cr := Vector3(rad, hgt * (1.0 - bole) * 0.5 * squash + 0.8, rad)
	var fork := Vector3(rng.randf_range(-0.3, 0.3), hgt * bole, rng.randf_range(-0.3, 0.3))
	var bark := Color(0.36, 0.32, 0.27).lerp(Color(0.5, 0.47, 0.42), rng.randf())
	_tube(wood, [Vector3.ZERO, fork * 0.5, fork], 0.07 * hgt / 4.0, 0.05 * hgt / 4.0, 5, bark, Vector2(0.0, bole), Vector2(0.0, 0.0), Vector2(0.0, 0.0), Vector2(0.4, 0.7))
	var clusters := rng.randi_range(7, 11)
	for k in clusters:
		var d := Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.6, 1), rng.randf_range(-1, 1)).normalized() * rng.randf_range(0.35, 0.8)
		var c := cc + d * cr
		_tube(wood, [fork, fork.lerp(c, 0.5) + Vector3.UP * 0.4, c], 0.03 * hgt / 4.0, 0.012 * hgt / 4.0, 3, bark, Vector2(bole, c.y / hgt), Vector2(k, 0.0), Vector2(k + 0.999, 0.0), Vector2(0.4, 0.8))
		for j in rng.randi_range(9, 13):
			var o := (c - cc).normalized().lerp(Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.5, 1), rng.randf_range(-1, 1)).normalized(), 0.6).normalized()
			var cp := c + o * rng.randf_range(0.0, 0.7) * rad * 0.45
			var length := rng.randf_range(1.3, 1.9)
			var tint := Color(1, 1, 1).lerp(Color(0.8, 0.9, 0.75), rng.randf())
			tint = tint.darkened(0.3 * clampf(1.0 - (cp - cc).length() / rad, 0.0, 1.0))
			tint.a = clampf(cp.y / hgt, 0.0, 1.0)
			_card(leaves, cp, (o + Vector3.DOWN * 0.4).normalized(), length, length * 0.5, rng.randf_range(-1.2, 1.2), 0.3, 1, cc, tint, Vector2(k + 0.999, 0.0), 0.75)
	var m := ArrayMesh.new()
	wood.commit(m, tree_material("tree_wood"))
	leaves.commit(m, tree_material("tree_leaf"))
	_meshes[key] = m
	return m


# Far tree lines: copies of a few cheap meshes, one MultiMesh per mesh per
# group (a village), so a whole village costs a handful of draw calls and is
# culled as one. items: [[mesh, Transform3D], ...]. No shadows: the groups
# lie beyond the sun's shadow distance.
static func far_group(parent: Node3D, items: Array) -> void:
	var by_mesh := {}
	for it in items:
		if not by_mesh.has(it[0]):
			by_mesh[it[0]] = []
		by_mesh[it[0]].append(it[1])
	for mesh in by_mesh:
		var xfs: Array = by_mesh[mesh]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh
		mm.instance_count = xfs.size()
		for i in xfs.size():
			mm.set_instance_transform(i, xfs[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(mmi)


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
		var k := rng.randf_range(0.85, 1.02)
		var yellow := rng.randf()
		# mạ: a deeper green than lawn grass, a few paler yellowish seedlings
		var col := Color(0.30, 0.46, 0.14).lerp(Color(0.46, 0.56, 0.22), yellow * yellow * 0.7) * k
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
					var c0: Color = Color(0.62, 0.66, 0.42).lerp(col, minf((s - 1) / 1.5, 1.0))
					var c1: Color = Color(0.62, 0.66, 0.42).lerp(col, minf(s / 1.5, 1.0))
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
	# Two 18 cm walkway furrows across the bed (rãnh luống) split it into
	# three strips, as in a real mạ bed; the patches fill the strips.
	var gap := 0.18
	var strip := (size.y - 2.0 * gap) / 3.0
	for i in count:
		var cx := (float(i % cols) + 0.5 + rng.randf_range(-0.35, 0.35)) / cols - 0.5
		var u := clampf((float(i / cols) + 0.5 + rng.randf_range(-0.35, 0.35)) / rows, 0.0, 0.999)
		var zs := u * 3.0
		var cz := (floorf(zs) * (strip + gap) + fmod(zs, 1.0) * strip) / size.y - 0.5
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
		var c := Color(0.24, 0.40, 0.10).lerp(Color(0.38, 0.50, 0.16), rng.randf())
		c = c.lerp(Color(0.62, 0.56, 0.3), rng.randf() * dry)
		mm.set_instance_color(i, c)
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = material("blade")
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mmi)
	return mmi
