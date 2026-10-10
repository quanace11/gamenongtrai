# The paddy: the three GDD parameters (mud texture, water level,
# nutrient & pest index) plus the rice clumps planted in it.
extends Node3D

const L = preload("res://scripts/layout.gd")
const A = preload("res://scripts/assets.gd")
const F = preload("res://scripts/flora.gd")
const W = preload("res://scripts/world.gd")
const SOIL = preload("res://shaders/soil.gdshader")
const N := 8 # soil grid: 8 x 8 cells of 2 m
const CELL := 2.0
const MAX_CLUMPS := 700
const WATER_VIS := 0.02 # metres of visual water per cm (exaggerated so 3–5 cm reads on screen)
const VERT := 33

var till := PackedFloat32Array()
var smooth := PackedFloat32Array()
var water := 0.0 # cm
var gate_open := false
var drain_open := false
var nutrient := 0.5
var pest := 0.1
var weeds := 0.0
var health := 1.0
var growth_day := 0
var aesthetic := 0.0
var duck_bonus := 0.0
var clumps: Array = [] # [{x, z, rot, cut}]
var eggs: Array = [false, false, false, false, false, false]

var soil_dirty := true
var rice_dirty := true

var _noise := PackedFloat32Array()
var _soil: MeshInstance3D
var _water: MeshInstance3D
var _soil_mat: ShaderMaterial
var _rice: MultiMeshInstance3D
var _panicles: MultiMeshInstance3D
var _weeds: MultiMeshInstance3D
var _weed_pos: Array = []


func _ready() -> void:
	till.resize(N * N)
	smooth.resize(N * N)
	_noise.resize(VERT * VERT)
	for i in _noise.size():
		_noise[i] = randf()
	_soil_mat = ShaderMaterial.new()
	_soil_mat.shader = SOIL
	for k in [["dry", "mud_cracked_dry_03"], ["till", "farm_soil"], ["mud", "brown_mud_03"]]:
		_soil_mat.set_shader_parameter(k[0] + "_alb", A.tex(k[1], "diff"))
		_soil_mat.set_shader_parameter(k[0] + "_nor", A.tex(k[1], "nor"))
		_soil_mat.set_shader_parameter(k[0] + "_arm", A.tex(k[1], "arm"))
	# The flooded water is drawn by the soil shader itself (opaque, so it
	# gets screen-space reflections); it only needs gentle ripple normals.
	_soil_mat.set_shader_parameter("wave_a", _ripple_texture(5))
	_soil_mat.set_shader_parameter("wave_b", _ripple_texture(11))
	_soil_mat.set_shader_parameter("floor_y", L.FIELD.y)
	_soil = MeshInstance3D.new()
	_soil.material_override = _soil_mat
	_soil.position.y = L.FIELD.y
	_soil.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF # the shader moves its depth
	add_child(_soil)

	# Skirt: four inward-facing walls at the field edge, same material. Rays
	# that reach a bund face below the water line pass through it first, so
	# the water surface also covers the submerged bund faces.
	_water = MeshInstance3D.new()
	_water.mesh = _skirt_mesh()
	_water.material_override = _soil_mat
	_water.position.y = L.FIELD.y
	_water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_water.visible = false
	add_child(_water)

	_rice = _multimesh(_clump_mesh(), MAX_CLUMPS)
	_panicles = _multimesh(_panicle_mesh(), MAX_CLUMPS)
	_weeds = _multimesh(F.tuft_mesh(8, 0.45, 0.03), 80)
	for i in 80:
		_weed_pos.append(Vector2(randf_range(-7.6, 7.6), randf_range(-7.6, 7.6)))


static func _ripple_texture(seed: int) -> NoiseTexture2D:
	var n := FastNoiseLite.new()
	n.seed = seed
	n.frequency = 0.03
	n.fractal_octaves = 3
	var t := NoiseTexture2D.new()
	t.width = 256
	t.height = 256
	t.seamless = true
	t.as_normal_map = true
	t.bump_strength = 3.0
	t.generate_mipmaps = true
	t.noise = n
	return t


# Vertical quads just inside the field edge, from below the soil to above
# the highest water, facing the field centre. Vertex alpha 0 marks them.
static func _skirt_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var e := 7.995
	var y0 := -0.08
	var y1 := 0.6
	var c := Color(0, 1, 0, 0)
	for side in [[Vector2(-e, -e), Vector2(e, -e)], [Vector2(e, -e), Vector2(e, e)], [Vector2(e, e), Vector2(-e, e)], [Vector2(-e, e), Vector2(-e, -e)]]:
		var a: Vector2 = side[0]
		var b: Vector2 = side[1]
		var inward := Vector3(-(a.x + b.x), 0, -(a.y + b.y)).normalized()
		var q := [Vector3(a.x, y0, a.y), Vector3(b.x, y0, b.y), Vector3(b.x, y1, b.y), Vector3(a.x, y1, a.y)]
		# Godot's front faces wind clockwise: their cross product points away
		# from the side they are seen from.
		var tris := [[q[0], q[1], q[2]], [q[0], q[2], q[3]]]
		if (q[1] - q[0]).cross(q[2] - q[0]).dot(inward) > 0.0:
			tris = [[q[0], q[2], q[1]], [q[0], q[3], q[2]]]
		for tri in tris:
			for v in tri:
				st.set_color(c)
				st.set_normal(inward)
				st.add_vertex(v)
	return st.commit()


func _multimesh(mesh: Mesh, count: int) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = count
	mm.visible_instance_count = 0
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = F.material("blade")
	add_child(mmi)
	return mmi


# One transplanted clump (khóm lúa): ~16 curved, tapering leaves. Vertex
# alpha runs 0 at the base to 1 at the tip for the foliage shader's AO.
func _clump_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var blades := 16
	for i in blades:
		var a := float(i) / blades * TAU + randf() * 0.5
		var lean := 0.15 + randf() * 0.3
		var h := 0.7 + randf() * 0.35
		var w := 0.018 + randf() * 0.008
		var d := Vector3(cos(a), 0, sin(a))
		var side := Vector3(-sin(a), 0, cos(a))
		var base := d * 0.025
		var prev := []
		for k in 6:
			var t := k / 5.0
			var p := base + d * lean * h * t * t + Vector3(0, h * (t - 0.25 * t * t * lean * 2.0), 0)
			var ww := w * (1.0 - t * 0.85)
			var cur := [p - side * ww, p + side * ww]
			if k > 0:
				var c0 := Color(1, 1, 1, (k - 1) / 5.0)
				var c1 := Color(1, 1, 1, t)
				for v in [[prev[0], c0], [prev[1], c0], [cur[1], c1], [prev[0], c0], [cur[1], c1], [cur[0], c1]]:
					st.set_color(v[1])
					st.add_vertex(v[0])
			prev = cur
	st.generate_normals()
	return st.commit()


# Drooping panicles (bông lúa): arcs of grain lumps hanging out of the clump.
func _panicle_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 7:
		var a := i / 7.0 * TAU + randf() * 0.4
		var d := Vector3(cos(a), 0, sin(a))
		var side := Vector3(-sin(a), 0, cos(a))
		var prev := []
		for k in 7:
			var t := k / 6.0
			var p := d * (0.04 + 0.2 * t) + Vector3(0, 0.98 - 0.32 * t * t, 0)
			var w := 0.022 * sin(PI * clampf(t * 1.1 + 0.1, 0.0, 1.0)) + 0.004
			var cur := [p - side * w, p + side * w, p + Vector3(0, w, 0)]
			if k > 0:
				var c := Color(1, 1, 1, 1)
				for tri in [[prev[0], prev[1], cur[1]], [prev[0], cur[1], cur[0]], [prev[0], prev[2], cur[2]], [prev[0], cur[2], cur[0]]]:
					for v in tri:
						st.set_color(c)
						st.add_vertex(v)
			prev = cur
	st.generate_normals()
	return st.commit()


func cell_at(x: float, z: float) -> int:
	var i := int(floor((x - L.FIELD.x0) / CELL))
	var j := int(floor((z - L.FIELD.z0) / CELL))
	if i < 0 or j < 0 or i >= N or j >= N:
		return -1
	return j * N + i


func cell_center(idx: int) -> Vector2:
	return Vector2(L.FIELD.x0 + (idx % N) * CELL + 1.0, L.FIELD.z0 + int(idx / N) * CELL + 1.0)


func avg_till() -> float:
	var s := 0.0
	for v in till:
		s += v
	return s / till.size()


func avg_smooth() -> float:
	var s := 0.0
	for v in smooth:
		s += v
	return s / smooth.size()


func is_wet() -> bool:
	return water >= 0.5


func prep_done() -> bool:
	return avg_till() >= 0.9 and avg_smooth() >= 0.85


# Hoe one cell. Returns how hard the soil was (0..1), or -1 if outside.
func hoe(x: float, z: float) -> float:
	var idx := cell_at(x, z)
	if idx < 0:
		return -1.0
	var amt := 0.4 if is_wet() else 0.26
	till[idx] = minf(1.0, till[idx] + amt)
	var i := idx % N
	var j := int(idx / N)
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var ii: int = i + d.x
		var jj: int = j + d.y
		if ii >= 0 and jj >= 0 and ii < N and jj < N:
			till[jj * N + ii] = minf(1.0, till[jj * N + ii] + amt * 0.15)
	soil_dirty = true
	return 0.25 if is_wet() else 1.0


# Drag the wooden harrow over the cell under the player.
func harrow(x: float, z: float, dist: float) -> String:
	var idx := cell_at(x, z)
	if idx < 0:
		return "out"
	if water < 1.0:
		return "dry"
	if till[idx] < 0.6:
		return "untilled"
	smooth[idx] = minf(1.0, smooth[idx] + dist * 0.5)
	soil_dirty = true
	return "ok"


# Continuous water dynamics. dt_min = game minutes elapsed.
func step(dt_min: float, canal_full: bool, raining: bool, sun: float) -> void:
	var dw := 0.0
	if gate_open and canal_full:
		dw += 0.06 * dt_min
	if drain_open:
		dw -= 0.06 * dt_min
	if raining:
		dw += 0.035 * dt_min
	dw -= 0.0035 * sun * dt_min
	# Through the gate the field can only fill up to the canal level (~6 cm);
	# anything above that comes from rain.
	if gate_open and canal_full and water + dw > 6.0:
		dw = minf(dw, maxf(0.0, 6.0 - water))
	water = clampf(water + dw, 0.0, 20.0)


func plant(x: float, z: float) -> void:
	if clumps.size() >= MAX_CLUMPS:
		return
	clumps.append({"x": x, "z": z, "rot": randf() * TAU, "cut": false})
	rice_dirty = true


func planted_count() -> int:
	return clumps.size()


func cut_count() -> int:
	var n := 0
	for c in clumps:
		if c.cut:
			n += 1
	return n


func is_ripe() -> bool:
	return growth_day >= 8


# Cut up to `max_n` clumps within radius r of (x, z). Returns how many.
func cut_near(x: float, z: float, r: float, max_n: int) -> int:
	var n := 0
	for c in clumps:
		if c.cut:
			continue
		if Vector2(c.x - x, c.z - z).length() < r:
			c.cut = true
			n += 1
			if n >= max_n:
				break
	if n > 0:
		rice_dirty = true
	return n


func apply_ash(with_dew: bool) -> void:
	pest = maxf(0.0, pest - (0.35 if with_dew else 0.08))
	rice_dirty = true


func fertilize() -> void:
	nutrient = minf(1.0, nutrient + 0.25)


func kg_per_clump() -> float:
	return 0.25 * health * (1.0 + 0.15 * aesthetic) * (1.0 + duck_bonus) * (0.9 + 0.2 * nutrient)


# Once per in-game day while rice is in the field. Returns [[kind, text], ...].
func daily_care(ducks_in_field: bool) -> Array:
	var msgs := []
	growth_day += 1
	var w := water
	if w > 7.0:
		health -= 0.08
		msgs.append(["bad", "Nước ngập %.1f cm — ngập bẹ, lúa bắt đầu thối!" % w])
	elif w < 1.0:
		weeds = minf(1.0, weeds + 0.25)
		health -= 0.05
		msgs.append(["bad", "Ruộng cạn nứt nẻ — cỏ dại mọc lấn lúa!"])
	elif w >= 3.0 and w <= 5.0:
		health += 0.02

	var heading := growth_day >= 5 and growth_day < 8
	var pest_growth := 0.09 * (1.25 - 0.5 * aesthetic)
	if ducks_in_field and growth_day < 5:
		pest_growth -= 0.18
		weeds = maxf(0.0, weeds - 0.25)
		for i in eggs.size():
			eggs[i] = eggs[i] and randf() < 0.4
		duck_bonus = minf(0.08, duck_bonus + 0.02)
		msgs.append(["good", "Đàn vịt đã sục bùn, ăn ốc non và cỏ dại."])
	if ducks_in_field and heading:
		health -= 0.1
		msgs.append(["bad", "Vịt rỉa mất bông lúa đang trổ! Lùa vịt ra kênh."])
	pest = clampf(pest + pest_growth, 0.0, 1.0)
	if pest > 0.4:
		health -= (pest - 0.4) * 0.25
	var egg_count := eggs.count(true)
	if egg_count > 0:
		health -= egg_count * 0.015
		msgs.append(["warn", "%d ổ trứng ốc bươu vàng chưa bóc — ốc con đang cắn lúa." % egg_count])
	for i in eggs.size():
		eggs[i] = eggs[i] or randf() < 0.35
	health -= weeds * 0.04
	health += (nutrient - 0.5) * 0.04
	nutrient = maxf(0.0, nutrient - 0.04)
	health = clampf(health, 0.2, 1.0)
	if growth_day == 5:
		msgs.append(["info", "Lúa bắt đầu trổ bông — cấm thả vịt vào ruộng!"])
	if growth_day == 8:
		msgs.append(["good", "Lúa chín vàng! Cầm liềm (phím 5) ra gặt."])
	rice_dirty = true
	return msgs


func refresh() -> void:
	if soil_dirty:
		_update_soil()
	if rice_dirty:
		_update_rice()
	# The soil shader draws water wherever the soil lies under this level.
	var flooded := water > 0.15
	_water.visible = flooded
	_soil_mat.set_shader_parameter("water_y", L.FIELD.y + 0.01 + water * WATER_VIS if flooded else -10.0)
	_soil_mat.set_shader_parameter("wet", clampf(water / 2.0, 0.0, 1.0))


func _update_soil() -> void:
	soil_dirty = false
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pts := []
	var cols := []
	for vj in VERT:
		for vi in VERT:
			var x := -8.0 + vi * 0.5
			var z := -8.0 + vj * 0.5
			var idx := cell_at(clampf(x, -7.99, 7.99), clampf(z, -7.99, 7.99))
			var t := till[idx]
			var s := smooth[idx]
			var nz := _noise[vj * VERT + vi]
			var crack := t < 0.5 and nz > 0.72
			# The soil shader reads R = hoed, G = puddled.
			var c := Color(t, s, 1.0 if crack else 0.0)
			var edge := absf(x) > 7.9 or absf(z) > 7.9
			var y := 0.0
			if not edge:
				if t < 0.5:
					y = -0.03 if crack else nz * 0.03
				else:
					y = nz * 0.1 * t
				y *= 1.0 - s
			pts.append(Vector3(x, y, z))
			cols.append(c)
	for vj in VERT - 1:
		for vi in VERT - 1:
			var a := vj * VERT + vi
			for k in [a, a + 1, a + VERT, a + 1, a + VERT + 1, a + VERT]:
				st.set_color(cols[k])
				st.add_vertex(pts[k])
	st.generate_normals()
	_soil.mesh = st.commit()


func _update_rice() -> void:
	rice_dirty = false
	var g := float(growth_day)
	var grow := 0.32 + 0.68 * clampf(g / 5.0, 0.0, 1.0)
	var ripe := clampf((g - 5.0) / 3.0, 0.0, 1.0)
	var yellow := clampf(pest - 0.3, 0.0, 0.7) + (1.0 - health) * 0.5
	var mm := _rice.multimesh
	var pm := _panicles.multimesh
	var pi := 0
	for i in clumps.size():
		var cl: Dictionary = clumps[i]
		var b := Basis(Vector3.UP, cl.rot)
		var pos := Vector3(cl.x, L.FIELD.y, cl.z)
		if cl.cut:
			mm.set_instance_transform(i, Transform3D(b.scaled(Vector3(0.8, 0.18, 0.8)), pos))
			mm.set_instance_color(i, Color(0.78, 0.68, 0.42))
			continue
		var c := Color(0.34, 0.56, 0.16).lerp(Color(0.74, 0.64, 0.3), ripe)
		c = c.lerp(Color(0.7, 0.6, 0.3), yellow * (1.0 - ripe))
		mm.set_instance_transform(i, Transform3D(b.scaled(Vector3(grow, grow, grow)), pos))
		mm.set_instance_color(i, c)
		if growth_day >= 5:
			pm.set_instance_transform(pi, Transform3D(b.scaled(Vector3(grow, grow * (1.0 - ripe * 0.1), grow)), pos))
			pm.set_instance_color(pi, Color(0.55, 0.62, 0.3).lerp(Color(0.86, 0.7, 0.32), ripe))
			pi += 1
	mm.visible_instance_count = clumps.size()
	pm.visible_instance_count = pi
	var wm := _weeds.multimesh
	var nw := int(round(weeds * 80))
	wm.visible_instance_count = nw
	for i in nw:
		wm.set_instance_transform(i, Transform3D(Basis(), Vector3(_weed_pos[i].x, L.FIELD.y, _weed_pos[i].y)))
		wm.set_instance_color(i, Color(0.3, 0.48, 0.14).lerp(Color(0.45, 0.55, 0.2), float(i % 5) / 4.0))
