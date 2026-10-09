# Hand-held tools drawn in front of the camera, with simple swing
# animations so every action has a physical weight.
extends Node3D

const W = preload("res://scripts/world.gd")

const TOOLS := [
	{"id": "tay", "key": KEY_1, "name": "Tay không", "en": "Hands"},
	{"id": "cuoc", "key": KEY_2, "name": "Cuốc", "en": "Hoe"},
	{"id": "bua", "key": KEY_3, "name": "Bừa gỗ", "en": "Harrow"},
	{"id": "gau", "key": KEY_4, "name": "Gàu sòng", "en": "Scoop"},
	{"id": "liem", "key": KEY_5, "name": "Liềm", "en": "Sickle"},
	{"id": "cao", "key": KEY_6, "name": "Cào gỗ", "en": "Rake"},
	{"id": "sao", "key": KEY_7, "name": "Sào vịt", "en": "Duck pole"},
]

const WOOD := Color("8a6236")
const BAMBOO := Color("c9b27a")
const IRON := Color("6d6d6d")
const SKIN := Color("c99a74")

var models := {}
var current := "tay"
var bo_ma: Node3D # bó mạ in the left hand while transplanting
var ganh: Node3D # đòn gánh with two loads of sheaves
var ganh_loads: Array = []
var streamers: Array = []

var _swing_t := 0.0
var _swing_dur := 0.0
var _impact_at := 0.0
var _on_impact: Callable
var _style := "chop"
var _wave := 0.0


func _ready() -> void:
	position = Vector3(0.32, -0.32, -0.45)
	for t in TOOLS:
		var g := Node3D.new()
		g.visible = t.id == current
		add_child(g)
		models[t.id] = g
	_part(models.cuoc, _cyl(0.02, 1.0), WOOD, Vector3(0, 0.1, -0.15), Vector3(-1.1, 0, 0))
	_part(models.cuoc, _box(Vector3(0.2, 0.02, 0.24)), IRON, Vector3(0, 0.38, -0.62), Vector3(-0.5, 0, 0))

	_part(models.bua, _box(Vector3(0.9, 0.07, 0.07)), WOOD, Vector3(-0.3, -0.25, -0.75))
	for i in 8:
		_part(models.bua, _box(Vector3(0.025, 0.18, 0.025)), WOOD, Vector3(-0.7 + i * 0.115, -0.36, -0.75))
	_part(models.bua, _cyl(0.02, 0.6), BAMBOO, Vector3(-0.05, -0.05, -0.5), Vector3(1.0, 0, 0))
	_part(models.bua, _cyl(0.02, 0.6), BAMBOO, Vector3(-0.55, -0.05, -0.5), Vector3(1.0, 0, 0))

	var scoop := CylinderMesh.new()
	scoop.top_radius = 0.22
	scoop.bottom_radius = 0.12
	scoop.height = 0.25
	scoop.cap_top = false
	_part(models.gau, scoop, BAMBOO, Vector3(0, -0.05, -0.6), Vector3(1.3, 0, 0)).material_override = W.mat(BAMBOO, true)
	_part(models.gau, _cyl(0.015, 0.9), BAMBOO, Vector3(0, 0.15, -0.25), Vector3(-0.9, 0, 0))

	_part(models.liem, _cyl(0.02, 0.22), WOOD, Vector3(0, -0.05, -0.1), Vector3(0, 0, 0.3))
	var blade := TorusMesh.new()
	blade.inner_radius = 0.15
	blade.outer_radius = 0.17
	var bl := _part(models.liem, blade, IRON, Vector3(-0.12, 0.1, -0.12), Vector3(PI / 2, 0, 0.6))
	bl.scale = Vector3(1, 1, 0.4)

	_part(models.cao, _cyl(0.018, 1.6), WOOD, Vector3(0, 0, -0.5), Vector3(-1.25, 0, 0))
	_part(models.cao, _box(Vector3(0.55, 0.05, 0.06)), WOOD, Vector3(0, -0.3, -1.25))
	for i in 7:
		_part(models.cao, _box(Vector3(0.02, 0.1, 0.02)), WOOD, Vector3(-0.24 + i * 0.08, -0.36, -1.25))

	_part(models.sao, _cyl(0.022, 2.6), BAMBOO, Vector3(0, 0.5, -1.0), Vector3(-0.7, 0, 0))
	var cols := [Color("e84a4a"), Color("4ae8c0"), Color("f0e04a"), Color("4a8ae8")]
	for i in 4:
		var s := _part(models.sao, _box(Vector3(0.05, 0.5, 0.005)), cols[i], Vector3(0, 1.35, -1.95 + i * 0.03))
		s.material_override = W.mat(cols[i], true)
		streamers.append(s)

	bo_ma = Node3D.new()
	bo_ma.position = Vector3(-0.78, -0.02, -0.15)
	bo_ma.scale = Vector3.ONE * 0.6
	bo_ma.visible = false
	add_child(bo_ma)
	_part(bo_ma, _cyl(0.05, 0.3), Color("7cc04a"), Vector3(0, 0.1, 0))
	_part(bo_ma, _cyl(0.052, 0.04), BAMBOO, Vector3.ZERO)
	_part(bo_ma, _box(Vector3(0.09, 0.07, 0.15)), SKIN, Vector3(0, -0.05, 0.05))

	ganh = Node3D.new()
	ganh.position = Vector3(-0.32, 0.05, 0.25)
	ganh.visible = false
	add_child(ganh)
	_part(ganh, _cyl(0.02, 1.6), BAMBOO, Vector3.ZERO, Vector3(0, 0, PI / 2))
	for x in [-0.75, 0.75]:
		var cone := CylinderMesh.new()
		cone.top_radius = 0.25
		cone.bottom_radius = 0.0
		cone.height = 0.5
		ganh_loads.append(_part(ganh, cone, Color("d8b24a"), Vector3(x, -0.35, 0)))


func _cyl(r: float, h: float) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r
	c.height = h
	c.radial_segments = 6
	c.rings = 1
	return c


func _box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


func _part(parent: Node3D, mesh: Mesh, color: Color, pos: Vector3, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = W.mat(color)
	mi.position = pos
	mi.rotation = rot
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


func select(id: String) -> void:
	if not models.has(id) or busy():
		return
	models[current].visible = false
	current = id
	models[id].visible = true


func busy() -> bool:
	return _swing_t > 0.0


# style: "chop" (hoe), "slash" (sickle), "scoop" (bucket), "pull" (rake), "beat" (threshing)
func swing(dur: float, impact_frac: float, style: String, cb: Callable) -> bool:
	if _swing_t > 0.0:
		return false
	_swing_dur = dur
	_swing_t = dur
	_impact_at = dur * (1.0 - impact_frac)
	_on_impact = cb
	_style = style
	return true


func animate(dt: float, moving: bool, bob: float, time: float, waving: bool, carrying: float) -> void:
	var r := Vector3.ZERO
	var p := Vector3.ZERO
	if _swing_t > 0.0:
		var prev := _swing_t
		_swing_t = maxf(0.0, _swing_t - dt)
		if prev > _impact_at and _swing_t <= _impact_at and _on_impact.is_valid():
			var cb := _on_impact
			_on_impact = Callable()
			cb.call()
		var k := 1.0 - _swing_t / _swing_dur
		var up := k / 0.45 if k < 0.45 else 1.0 - (k - 0.45) / 0.55
		var down := 0.0 if k < 0.45 else sin((k - 0.45) / 0.55 * PI)
		match _style:
			"chop":
				r.x = up * 1.4 - down * 0.5; p.y = up * 0.15 - down * 0.1
			"slash":
				r.y = up * 0.9 - down * 1.6; r.z = -down * 0.4; p.x = -down * 0.25
			"scoop":
				r.x = -down * 1.0 + up * 0.6; p.y = up * 0.2
			"pull":
				p.z = up * -0.35 + down * 0.25
			"beat":
				r.x = up * 1.6 - down * 0.4; p.y = up * 0.2
	if waving:
		_wave += dt * 9.0
		r.z = sin(_wave) * 0.5
	for i in streamers.size():
		streamers[i].rotation.y = sin(time * 8.0 + i) * 0.8 + (sin(_wave * 1.3 + i) if waving else 0.0)
	var sway := sin(bob) * 0.02 if moving else sin(time * 1.5) * 0.005
	var m: Node3D = models[current]
	m.rotation = r
	m.position = p + Vector3(sway, absf(sway), 0)
	ganh.visible = carrying > 0.0
	for l in ganh_loads:
		l.scale = Vector3.ONE * (0.4 + 0.6 * carrying)
