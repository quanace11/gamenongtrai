# "Chạy thóc": paddy spread on the red-brick courtyard to sun-dry, with
# the rake, the tarp and the four corner bricks.
extends Node3D

const L = preload("res://scripts/layout.gd")
const C := 12
const R := 6

var mass := PackedFloat32Array() # kg on each 1 m² cell
var moist := PackedFloat32Array() # 1 = fresh from threshing, <= 0.14 = dry
var soaked := PackedFloat32Array() # 0..1 rain damage (germination)
var total := 0.0

var _mesh_i: MeshInstance3D
var _highlight: MeshInstance3D
var _dirty_t := -1.0

const RES := 4 # heightfield vertices per metre
const KG_H := 0.012 # metres of grain per kg on a 1 m² cell


func _ready() -> void:
	mass.resize(C * R)
	moist.resize(C * R)
	moist.fill(1.0)
	soaked.resize(C * R)
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.roughness = 0.78
	# Grain-sized bumps (about 6 mm cells) so the layer reads as loose paddy.
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_CELLULAR
	n.cellular_return_type = FastNoiseLite.RETURN_DISTANCE
	n.frequency = 0.08
	var nt := NoiseTexture2D.new()
	nt.width = 512
	nt.height = 512
	nt.seamless = true
	nt.as_normal_map = true
	nt.bump_strength = 6.0
	nt.noise = n
	m.normal_enabled = true
	m.normal_texture = nt
	m.normal_scale = 0.9
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3.ONE * 4.0
	_mesh_i = MeshInstance3D.new()
	_mesh_i.material_override = m
	add_child(_mesh_i)
	var hp := PlaneMesh.new()
	hp.size = Vector2(0.98, 0.98)
	var hm := StandardMaterial3D.new()
	hm.albedo_color = Color(1, 1, 1, 0.25)
	hm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	hm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_highlight = MeshInstance3D.new()
	_highlight.mesh = hp
	_highlight.material_override = hm
	_highlight.visible = false
	add_child(_highlight)
	refresh()


func _process(_dt: float) -> void:
	# Drying only changes colours; rebuild at most four times a second.
	if _dirty_t >= 0.0 and Time.get_ticks_msec() / 1000.0 - _dirty_t > 0.25:
		refresh()


func cell_at(x: float, z: float) -> int:
	var i := int(floor(x - L.COURT.x0))
	var j := int(floor(z - L.COURT.z0))
	if i < 0 or j < 0 or i >= C or j >= R:
		return -1
	return j * C + i


func center(idx: int) -> Vector2:
	return Vector2(L.COURT.x0 + (idx % C) + 0.5, L.COURT.z0 + int(idx / C) + 0.5)


func covered(idx: int, tarp_on: bool) -> bool:
	if not tarp_on:
		return false
	var c := center(idx)
	return c.x > L.TARP.x0 and c.x < L.TARP.x1 and c.y > L.TARP.z0 and c.y < L.TARP.z1


# Dumped as one heap in the middle of the yard.
func pour(kg: float) -> void:
	var heap := [cell_at(-0.5, -17.5), cell_at(0.5, -17.5), cell_at(-0.5, -16.5), cell_at(0.5, -16.5)]
	for i in heap:
		mass[i] += kg / heap.size()
	total += kg
	refresh()


func neighbours(idx: int) -> Array:
	var i := idx % C
	var j := int(idx / C)
	var out := []
	for dj in range(-1, 2):
		for di in range(-1, 2):
			if di == 0 and dj == 0:
				continue
			var ii := i + di
			var jj := j + dj
			if ii >= 0 and jj >= 0 and ii < C and jj < R:
				out.append(jj * C + ii)
	return out


# Move paddy between cells, mixing moisture and rain damage.
func move(from: int, to: int, kg: float) -> void:
	if kg <= 0.0:
		return
	var tot := mass[to] + kg
	moist[to] = (moist[to] * mass[to] + moist[from] * kg) / tot
	soaked[to] = (soaked[to] * mass[to] + soaked[from] * kg) / tot
	mass[to] = tot
	mass[from] -= kg


# Rake outward: level the cell with its neighbours (rải mỏng).
func spread(idx: int) -> bool:
	if idx < 0 or mass[idx] < 0.05:
		return false
	var nb := neighbours(idx)
	var share := mass[idx] * 0.6 / nb.size()
	for n in nb:
		move(idx, n, share)
	refresh()
	return true


# Rake inward: pull neighbours onto this cell (vun đống).
func gather(idx: int) -> bool:
	if idx < 0:
		return false
	var moved := false
	for n in neighbours(idx):
		if mass[n] > 0.01:
			move(n, idx, mass[n] * 0.65)
			moved = true
	refresh()
	return moved


func step(dt_min: float, sun: float, raining: bool, tarp_on: bool) -> void:
	var changed := false
	for i in mass.size():
		var m := mass[i]
		if m < 0.02:
			continue
		var cov := covered(i, tarp_on)
		if raining and not cov:
			moist[i] = minf(1.3, moist[i] + 0.02 * dt_min)
			soaked[i] = minf(1.0, soaked[i] + 0.012 * dt_min)
			changed = true
		elif not raining and not cov and sun > 0.1:
			var thin := clampf(3.0 / m, 0.12, 1.0)
			moist[i] = maxf(0.0, moist[i] - 0.004 * sun * thin * dt_min)
			changed = true
	if changed and _dirty_t < 0.0:
		_dirty_t = Time.get_ticks_msec() / 1000.0


func dry_fraction() -> float:
	if total <= 0.0:
		return 0.0
	var d := 0.0
	for i in mass.size():
		if moist[i] <= 0.14:
			d += mass[i]
	return d / total


func soaked_fraction() -> float:
	if total <= 0.0:
		return 0.0
	var s := 0.0
	for i in mass.size():
		s += mass[i] * soaked[i]
	return s / total


func share_inside() -> float:
	if total <= 0.0:
		return 0.0
	var s := 0.0
	for i in mass.size():
		if covered(i, true):
			s += mass[i]
	return s / total


func max_height() -> float:
	var h := 0.0
	for i in mass.size():
		if covered(i, true):
			h = maxf(h, mass[i] * 0.012)
	return h


func set_highlight(idx: int) -> void:
	_highlight.visible = idx >= 0
	if idx >= 0:
		var c := center(idx)
		_highlight.position = Vector3(c.x, 0.03 + mass[idx] * KG_H, c.y)


# Bilinear sample of a per-cell field at a point in yard metres, cells
# treated as their centres; blur = 1 also averages the 3x3 neighbourhood.
func _sample(f: PackedFloat32Array, u: float, v: float) -> float:
	var x := clampf(u - 0.5, 0.0, C - 1.0)
	var y := clampf(v - 0.5, 0.0, R - 1.0)
	var i := mini(int(x), C - 2)
	var j := mini(int(y), R - 2)
	var fx := x - i
	var fy := y - j
	var a := lerpf(f[j * C + i], f[j * C + i + 1], fx)
	var b := lerpf(f[(j + 1) * C + i], f[(j + 1) * C + i + 1], fx)
	return lerpf(a, b, fy)


# The spread paddy as one soft heightfield: mounds where it is heaped,
# a thin raked layer with furrows where it is spread, bare bricks where
# there is none.
func refresh() -> void:
	_dirty_t = -1.0
	var nx := C * RES + 1
	var nz := R * RES + 1
	# Blur mass a little so cell borders don't show as steps.
	var bm := PackedFloat32Array()
	bm.resize(C * R)
	for j in R:
		for i in C:
			var s := 0.0
			var w := 0.0
			for dj in range(-1, 2):
				for di in range(-1, 2):
					var ii := i + di
					var jj := j + dj
					if ii < 0 or jj < 0 or ii >= C or jj >= R:
						continue
					var k := 1.0 if (di == 0 and dj == 0) else 0.35
					s += mass[jj * C + ii] * k
					w += k
			bm[j * C + i] = s / w
	var hs := PackedFloat32Array()
	hs.resize(nx * nz)
	var cols := PackedColorArray()
	cols.resize(nx * nz)
	var any := false
	for vj in nz:
		for vi in nx:
			var u := float(vi) / RES
			var v := float(vj) / RES
			var m := _sample(bm, u, v)
			# Only where some cell really holds grain.
			var raw := _sample(mass, u, v)
			var h := 0.0
			if raw > 0.05:
				h = m * KG_H
				# Rake furrows across the layer, strongest where it is thin.
				var thin := clampf(1.0 - h / 0.06, 0.0, 1.0)
				h += (sin(u * 38.0 + sin(v * 3.0) * 0.6) * 0.5 + 0.5) * 0.006 * thin * clampf(h / 0.008, 0.0, 1.0)
				h += 0.003 * sin(u * 91.0 + v * 57.0) * sin(v * 83.0 - u * 23.0)
				any = true
			hs[vj * nx + vi] = h
			var wet := clampf(_sample(moist, u, v) - 0.14, 0.0, 1.0)
			var col := Color(0.74, 0.6, 0.34).lerp(Color(0.52, 0.42, 0.24), wet)
			col = col.lerp(Color(0.45, 0.52, 0.3), _sample(soaked, u, v) * 0.8)
			col = col.darkened(0.06 * sin(u * 7.3 + v * 5.1) * sin(v * 6.7 - u * 2.9))
			cols[vj * nx + vi] = col
	_mesh_i.visible = any
	if not any:
		return
	var verts := PackedVector3Array()
	verts.resize(nx * nz)
	var nrm := PackedVector3Array()
	nrm.resize(nx * nz)
	var step := 1.0 / RES
	for vj in nz:
		for vi in nx:
			var h := hs[vj * nx + vi]
			# Edges of the layer dip under the bricks so the rim is hidden.
			var y := 0.016 + h if h > 0.0015 else 0.004
			verts[vj * nx + vi] = Vector3(L.COURT.x0 + vi * step, y, L.COURT.z0 + vj * step)
			var hl := hs[vj * nx + maxi(vi - 1, 0)]
			var hr := hs[vj * nx + mini(vi + 1, nx - 1)]
			var hd := hs[maxi(vj - 1, 0) * nx + vi]
			var hu := hs[mini(vj + 1, nz - 1) * nx + vi]
			nrm[vj * nx + vi] = Vector3(hl - hr, 2.0 * step, hd - hu).normalized()
	var idx := PackedInt32Array()
	for vj in nz - 1:
		for vi in nx - 1:
			var a := vj * nx + vi
			if hs[a] <= 0.0 and hs[a + 1] <= 0.0 and hs[a + nx] <= 0.0 and hs[a + nx + 1] <= 0.0:
				continue
			idx.append_array([a, a + 1, a + nx, a + 1, a + nx + 1, a + nx])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = nrm
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_mesh_i.mesh = mesh
