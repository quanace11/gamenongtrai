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

var _mm: MultiMesh
var _highlight: MeshInstance3D


func _ready() -> void:
	mass.resize(C * R)
	moist.resize(C * R)
	moist.fill(1.0)
	soaked.resize(C * R)
	var b := BoxMesh.new()
	b.size = Vector3(0.98, 1, 0.98)
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.use_colors = true
	_mm.mesh = b
	_mm.instance_count = C * R
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 1.0
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = _mm
	mmi.material_override = m
	add_child(mmi)
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
	if changed:
		refresh()


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
		_highlight.position = Vector3(c.x, 0.03 + mass[idx] * 0.012, c.y)


func refresh() -> void:
	for i in mass.size():
		var c := center(i)
		var h := maxf(mass[i] * 0.012, 0.0001)
		_mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3(1, h, 1)), Vector3(c.x, 0.015 + h / 2.0, c.y)))
		var wet := clampf(moist[i] - 0.14, 0.0, 1.0)
		var col := Color(0.8, 0.63, 0.27).lerp(Color(0.52, 0.4, 0.16), wet)
		col = col.lerp(Color(0.45, 0.55, 0.3), soaked[i] * 0.8)
		_mm.set_instance_color(i, col)
