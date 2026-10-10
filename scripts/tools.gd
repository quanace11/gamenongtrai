# Hand-held tools drawn in front of the camera, held in the farmer's own
# hands (CC0 rigged hands from Godot XR Tools, see assets/CREDITS.md), with
# simple swing animations so every action has a physical weight.
# Every held item draws with z_clip_scale and fov_override, so it never
# pokes through a wall or bund and keeps its size when the FOV changes.
extends Node3D

const A = preload("res://scripts/assets.gd")

const TOOLS := [
	{"id": "tay", "key": KEY_1, "name": "Tay không", "en": "Hands"},
	{"id": "cuoc", "key": KEY_2, "name": "Cuốc", "en": "Hoe"},
	{"id": "bua", "key": KEY_3, "name": "Bừa gỗ", "en": "Harrow"},
	{"id": "gau", "key": KEY_4, "name": "Gàu sòng", "en": "Scoop"},
	{"id": "liem", "key": KEY_5, "name": "Liềm", "en": "Sickle"},
	{"id": "cao", "key": KEY_6, "name": "Cào gỗ", "en": "Rake"},
	{"id": "sao", "key": KEY_7, "name": "Sào vịt", "en": "Duck pole"},
]

# How much each tool lags behind a turn of the head.
const WEIGHT := {"tay": 0.5, "liem": 0.7, "gau": 1.0, "cao": 1.1, "cuoc": 1.2, "sao": 1.4, "bua": 1.6}
const VM_FOV := 62.0 # held items always draw as if the camera had this vertical FOV
const VM_ZCLIP := 0.6 # docs: keep near 1, SSAO and SSR suffer at low values
const HANDS := "res://assets/models/hands/"
# Grip frame of the rigged hands, measured from the "Grip" pose: the fist
# closes around an axis close to +Y (the thumb side), centred here; the
# forearm leaves the wrist along +Z. The left hand is the mirror image.
const GRIP_AXIS := Vector3(0.08, 0.99, -0.1)
const GRIP_CENTRE := Vector3(-0.022, -0.007, -0.068)
const SKIN := Color8(167, 109, 83) # mean colour of the hand texture at the wrist

var models := {}
var current := "tay"
var bo_ma: Node3D # bó mạ in the left hand while transplanting
var ganh: Node3D # đòn gánh on the right shoulder, two loads of sheaves
var ganh_loads: Array = []
var streamers: Array = []

var rig: Node3D # everything that sways with the hands
var hands := {} # "r"/"l" -> Node3D (hand + forearm + sleeve)
var _skel := {} # "r"/"l" -> Skeleton3D
var _poses := {}
var _grips := {} # tool id -> {"r": [...], "l": [...]}, see _hold
var _base := {} # tool id -> rest Transform3D of its group
var _body_space := {"bua": true} # dragged on the ground: does not tilt with the view
var _hand_state := ""

var _swing_t := 0.0
var _swing_dur := 0.0
var _impact_at := 0.0
var _on_impact: Callable
var _style := "chop"
var _wave := 0.0
var _sway := Vector2.ZERO
var _sway_v := Vector2.ZERO
var _prev_look := Vector2.INF
var _load_ang: Array = [Vector2.ZERO, Vector2.ZERO] # pendulum angles of the two loads
var _load_vel: Array = [Vector2.ZERO, Vector2.ZERO]
var _prev_vel := Vector3.ZERO

static var _vm_cache := {}


func _ready() -> void:
	_poses = JSON.parse_string(FileAccess.get_file_as_string(HANDS + "poses.json"))
	rig = Node3D.new()
	add_child(rig)
	for t in TOOLS:
		var g := Node3D.new()
		g.visible = t.id == current
		rig.add_child(g)
		models[t.id] = g
	for side in ["r", "l"]:
		hands[side] = _make_hand(side)
	_build_tay()
	_build_cuoc()
	_build_bua()
	_build_gau()
	_build_liem()
	_build_cao()
	_build_sao()
	_build_bo_ma()
	_build_ganh()
	for id in models:
		_base[id] = models[id].transform
	_attach_hands()


# ---------------------------------------------------------------- materials
# A copy of a world material that draws as a held item.
func _vm(m: BaseMaterial3D) -> BaseMaterial3D:
	var key := m.get_instance_id()
	if not _vm_cache.has(key):
		var v := m.duplicate() as BaseMaterial3D
		v.use_z_clip_scale = true
		v.z_clip_scale = VM_ZCLIP
		v.use_fov_override = true
		v.fov_override = VM_FOV
		_vm_cache[key] = v
	return _vm_cache[key]


static var _m := {}


func _mat(id: String) -> BaseMaterial3D:
	if _m.has(id):
		return _m[id]
	var m: BaseMaterial3D
	match id:
		"wood": # a handle polished by years of hands
			m = _grained(Color(0.5, 0.34, 0.2), 0.55)
		"bamboo": # dry pale bamboo
			m = _grained(Color(0.78, 0.68, 0.45), 0.5)
		"woven": # gàu: split bamboo woven into a scoop
			m = A.pbr("bamboo_wall", 1.0, false, Color(1.05, 0.95, 0.75), true).duplicate()
			m.uv1_scale = Vector3(2.0, 1.0, 1)
		"straw":
			m = _grained(Color(0.85, 0.7, 0.38), 0.85)
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
		"iron": # forged iron, dark with soil; the vertex colour brightens the honed edge
			var s := StandardMaterial3D.new()
			s.vertex_color_use_as_albedo = true
			s.vertex_color_is_srgb = true
			s.albedo_color = Color(0.5, 0.48, 0.46)
			s.metallic = 0.45
			s.roughness = 0.58
			m = s
		"skin":
			var s := StandardMaterial3D.new()
			s.albedo_color = SKIN
			s.roughness = 0.62
			s.subsurf_scatter_enabled = true
			s.subsurf_scatter_strength = 0.25
			s.subsurf_scatter_skin_mode = true
			m = s
		"sleeve": # áo nâu: plain brown work cloth, linen weave
			var o := ORMMaterial3D.new()
			o.albedo_texture = load("res://assets/textures/rough_linen/rough_linen_diff_1k.jpg")
			o.albedo_color = Color(0.62, 0.42, 0.27)
			o.normal_enabled = true
			o.normal_texture = load("res://assets/textures/rough_linen/rough_linen_nor_1k.jpg")
			o.orm_texture = load("res://assets/textures/rough_linen/rough_linen_arm_1k.jpg")
			o.uv1_scale = Vector3(1.2, 1.2, 1)
			o.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
			m = o
		"hand":
			var o := ORMMaterial3D.new()
			o.albedo_texture = load(HANDS + "textures/hands_farmer_baseColor.jpg")
			o.normal_enabled = true
			o.normal_scale = 0.25
			o.normal_texture = load(HANDS + "textures/hands_normal.png")
			o.orm_texture = load(HANDS + "textures/hands_orm.jpg")
			o.subsurf_scatter_enabled = true
			o.subsurf_scatter_strength = 0.25
			o.subsurf_scatter_skin_mode = true
			m = o
		"rope":
			var s := StandardMaterial3D.new()
			s.albedo_color = Color(0.55, 0.45, 0.3)
			s.roughness = 1.0
			m = s
		"seedling":
			var s := StandardMaterial3D.new()
			s.vertex_color_use_as_albedo = true
			s.vertex_color_is_srgb = true
			s.roughness = 0.7
			s.cull_mode = BaseMaterial3D.CULL_DISABLED
			s.backlight_enabled = true
			s.backlight = Color(0.25, 0.35, 0.1)
			m = s
		"mud":
			var s := StandardMaterial3D.new()
			s.albedo_color = Color(0.32, 0.25, 0.18)
			s.roughness = 0.4 # wet
			m = s
		"sheaf":
			var s := StandardMaterial3D.new()
			s.vertex_color_use_as_albedo = true
			s.vertex_color_is_srgb = true
			s.roughness = 0.85
			s.cull_mode = BaseMaterial3D.CULL_DISABLED
			m = s
		"cloth":
			var s := StandardMaterial3D.new()
			s.vertex_color_use_as_albedo = true
			s.vertex_color_is_srgb = true
			s.roughness = 0.95
			s.cull_mode = BaseMaterial3D.CULL_DISABLED
			m = s
	_m[id] = _vm(m)
	return _m[id]


# Plain colour with fine lengthwise streaks (wood or bamboo grain).
static var _grain: NoiseTexture2D


func _grained(c: Color, rough: float) -> StandardMaterial3D:
	if _grain == null:
		var n := FastNoiseLite.new()
		n.frequency = 0.05
		n.fractal_octaves = 3
		_grain = NoiseTexture2D.new()
		_grain.width = 32
		_grain.height = 512
		_grain.seamless = true
		_grain.noise = n
		var ramp := Gradient.new()
		ramp.set_color(0, Color(0.72, 0.72, 0.72))
		ramp.set_color(1, Color(1.08, 1.08, 1.08))
		_grain.color_ramp = ramp
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.albedo_texture = _grain
	m.uv1_scale = Vector3(60.0, 0.05, 1) # tube UVs are in metres: streaks run along the length
	m.roughness = rough
	return m


func _add(parent: Node3D, mesh: Mesh, mat: String, xf := Transform3D.IDENTITY) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _mat(mat)
	mi.transform = xf
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


# ---------------------------------------------------------------- mesh helpers
# Basis whose +Z points along dir.
static func _along(dir: Vector3, up := Vector3.UP) -> Basis:
	dir = dir.normalized()
	if absf(dir.dot(up)) > 0.98:
		up = Vector3.FORWARD
	return Basis.looking_at(-dir, up)


# Elliptic tube along +Z from z0 to z1, radii (x, y) tapering r0 -> r1.
# bend sags the middle along -Y (a loaded carrying pole).
static func _tube(z0: float, z1: float, r0: Vector2, r1: Vector2, seg := 10, rings := 1, caps := true, bend := 0.0) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var circ := PI * (r0.x + r0.y)
	for j in rings + 1:
		var v := float(j) / rings
		var z := lerpf(z0, z1, v)
		var r := r0.lerp(r1, v)
		var sag := -bend * 4.0 * v * (1.0 - v)
		for i in seg + 1:
			var a := TAU * i / seg
			st.set_normal(Vector3(cos(a) / r.x, sin(a) / r.y, 0).normalized())
			st.set_uv(Vector2(float(i) / seg * circ, (z - z0)))
			st.add_vertex(Vector3(cos(a) * r.x, sin(a) * r.y + sag, z))
	for j in rings:
		for i in seg:
			var a := j * (seg + 1) + i
			var b := a + seg + 1
			st.add_index(a); st.add_index(a + 1); st.add_index(b)
			st.add_index(b); st.add_index(a + 1); st.add_index(b + 1)
	if caps:
		for e in 2:
			var z := z0 if e == 0 else z1
			var r := r0 if e == 0 else r1
			var sag := 0.0
			var n := Vector3(0, 0, -1 if e == 0 else 1)
			var c := (rings + 1) * (seg + 1) + e * (seg + 2)
			st.set_normal(n); st.set_uv(Vector2(0.5, 0.5)); st.add_vertex(Vector3(0, sag, z))
			for i in seg + 1:
				var a := TAU * i / seg
				st.set_normal(n)
				st.set_uv(Vector2(0.5 + cos(a) * 0.5, 0.5 + sin(a) * 0.5))
				st.add_vertex(Vector3(cos(a) * r.x, sin(a) * r.y + sag, z))
			for i in seg:
				if e == 0:
					st.add_index(c); st.add_index(c + 2 + i); st.add_index(c + 1 + i)
				else:
					st.add_index(c); st.add_index(c + 1 + i); st.add_index(c + 2 + i)
	st.generate_tangents()
	return st.commit()


# A cylinder part from a to b.
func _rod(parent: Node3D, a: Vector3, b: Vector3, r0: float, r1: float, mat: String, seg := 10) -> MeshInstance3D:
	var l := a.distance_to(b)
	return _add(parent, _tube(0, l, Vector2(r0, r0), Vector2(r1, r1), seg, 1), mat, Transform3D(_along(b - a), a))


# Thin plate from a grid: pos.call(u, v) -> Vector3 on the mid-surface,
# thick.call(u, v) -> thickness, col.call(u, v) -> vertex colour. The plate
# normal is +Z of the grid's local frame.
static func _plate(nu: int, nv: int, pos: Callable, thick: Callable, col: Callable) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var grid := []
	for side in 2:
		var s := 1.0 if side == 0 else -1.0
		var rows := []
		for j in nv + 1:
			var row := []
			for i in nu + 1:
				var u := float(i) / nu
				var v := float(j) / nv
				var p: Vector3 = pos.call(u, v)
				p.z += s * float(thick.call(u, v)) * 0.5
				row.append([p, col.call(u, v), Vector2(u, v)])
			rows.append(row)
		grid.append(rows)
	var quad := func(a, b, c, d, group: int):
		st.set_smooth_group(group)
		for q in [a, b, c, a, c, d]:
			st.set_color(q[1]); st.set_uv(q[2]); st.add_vertex(q[0])
	for j in nv:
		for i in nu:
			var f: Array = grid[0]
			var k: Array = grid[1]
			quad.call(f[j][i], f[j][i + 1], f[j + 1][i + 1], f[j + 1][i], 0)
			quad.call(k[j][i], k[j + 1][i], k[j + 1][i + 1], k[j][i + 1], 1)
	# rims
	for j in nv:
		quad.call(grid[0][j][0], grid[0][j + 1][0], grid[1][j + 1][0], grid[1][j][0], 2)
		quad.call(grid[0][j][nu], grid[1][j][nu], grid[1][j + 1][nu], grid[0][j + 1][nu], 3)
	for i in nu:
		quad.call(grid[0][0][i], grid[1][0][i], grid[1][0][i + 1], grid[0][0][i + 1], 4)
		quad.call(grid[0][nv][i], grid[0][nv][i + 1], grid[1][nv][i + 1], grid[1][nv][i], 5)
	st.generate_normals()
	return st.commit()


# ---------------------------------------------------------------- hands
func _make_hand(side: String) -> Node3D:
	var root := Node3D.new()
	var h: Node3D = (load(HANDS + "hand_%s.gltf" % side) as PackedScene).instantiate()
	root.add_child(h)
	var sk: Skeleton3D = h.find_child("Skeleton3D", true, false)
	_skel[side] = sk
	for mi in h.find_children("*", "MeshInstance3D", true, false):
		mi.material_override = _mat("hand")
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Forearm and a rolled sleeve, along +Z from the wrist; aimed at the
	# elbow in _hold. The wrist is flatter across the palm than across the
	# thumb side.
	var arm := Node3D.new()
	arm.name = "Arm"
	root.add_child(arm)
	# Starts inside the hand and is capped, so a bent wrist shows no gap.
	_add(arm, _tube(-0.02, 0.29, Vector2(0.024, 0.032), Vector2(0.036, 0.043), 14, 4, true), "skin", Transform3D(Basis.IDENTITY, Vector3(0, -0.002, 0)))
	# Rolled cuff: a fat ring of folded cloth, then the sleeve to the elbow.
	_add(arm, _tube(0.0, 0.055, Vector2(0.05, 0.057), Vector2(0.052, 0.059), 16, 3, true), "sleeve", Transform3D(Basis.IDENTITY, Vector3(0, -0.002, 0.15)))
	_add(arm, _tube(0.0, 0.4, Vector2(0.047, 0.054), Vector2(0.056, 0.062), 16, 4, true), "sleeve", Transform3D(Basis.IDENTITY, Vector3(0, -0.002, 0.195)))
	return root


func _set_pose(side: String, pose: String, amount := 1.0) -> void:
	var sk: Skeleton3D = _skel[side]
	sk.reset_bone_poses()
	var key := ("right/" if side == "r" else "left/") + pose
	if not _poses.has(key):
		return
	var p: Dictionary = _poses[key]
	for b in p:
		var i := sk.find_bone(b)
		if i < 0:
			continue
		var q: Array = p[b]
		var rest := sk.get_bone_rest(i).basis.get_rotation_quaternion()
		sk.set_bone_pose_rotation(i, rest.slerp(Quaternion(q[0], q[1], q[2], q[3]), amount))


# Grip spec: [point, thumb_dir, elbow, pose, amount] in the parent's space.
# point is where the fist closes (the handle axis), thumb_dir the way the
# thumb side of the fist faces along the handle, elbow where the forearm goes.
func _hold(id: String, side: String, point: Vector3, thumb: Vector3, elbow: Vector3, pose := "Grip", amount := 1.0) -> void:
	if not _grips.has(id):
		_grips[id] = {}
	_grips[id][side] = [point, thumb, elbow, pose, amount]


func _place_hand(side: String, parent: Node3D, g: Array) -> void:
	var h: Node3D = hands[side]
	if h.get_parent() != parent:
		if h.get_parent() != null:
			h.get_parent().remove_child(h)
		parent.add_child(h)
	var mx := 1.0 if side == "r" else -1.0
	var al := (GRIP_AXIS * Vector3(mx, 1, 1)).normalized()
	var zl := (Vector3.BACK - al * al.z).normalized()
	var bl := Basis(al.cross(zl), al, zl)
	var point: Vector3 = g[0]
	var at: Vector3 = (g[1] as Vector3).normalized()
	var to_elbow: Vector3 = g[2] - point
	var zt := (to_elbow - at * to_elbow.dot(at)).normalized()
	var bt := Basis(at.cross(zt), at, zt)
	var b := bt * bl.inverse()
	h.transform = Transform3D(b, point - b * (GRIP_CENTRE * Vector3(mx, 1, 1)))
	# The forearm aims at the elbow; the wrist bends at most ~35°.
	var arm: Node3D = h.get_node("Arm")
	var wrist := Vector3(0, 0, 0.02)
	var d: Vector3 = (b.inverse() * (g[2] - h.transform.origin) - wrist).normalized()
	if d.angle_to(Vector3.BACK) > 0.6:
		d = Vector3.BACK.slerp(d, 0.6 / d.angle_to(Vector3.BACK))
	arm.transform = Transform3D(_along(d, Vector3.UP), wrist)
	_set_pose(side, g[3], g[4])


# Puts both hands where the current tool (or the bó mạ / gánh) needs them.
func _attach_hands() -> void:
	var g: Dictionary = _grips[current]
	if bo_ma.visible:
		_place_hand("l", bo_ma, _grips.bo_ma.l)
	else:
		_place_hand("l", models[current], g.l)
	if bo_ma.visible and current == "tay":
		_place_hand("r", models.tay, _grips.bo_ma.r)
	elif ganh.visible and current == "tay":
		_place_hand("r", ganh, _grips.ganh.r)
	else:
		_place_hand("r", models[current], g.r)


# ---------------------------------------------------------------- tools
func _build_tay() -> void:
	var m: Node3D = models.tay
	m.position = Vector3(0, -0.24, -0.34)
	# Relaxed, half-open hands low in view, palms turned in and down.
	_hold("tay", "r", Vector3(0.22, -0.02, -0.06), Vector3(-0.85, 0.5, 0.0), Vector3(0.28, -0.36, 0.26), "Grip", 0.2)
	_hold("tay", "l", Vector3(-0.22, -0.02, -0.06), Vector3(0.85, 0.5, 0.0), Vector3(-0.28, -0.36, 0.26), "Grip", 0.2)
	# Transplanting: the right hand pinches seedlings from the bó mạ.
	_hold("bo_ma", "r", Vector3(0.2, 0.0, -0.1), Vector3(-0.5, 0.3, -0.8), Vector3(0.26, -0.36, 0.24), "Pinch Tight", 1.0)


func _build_cuoc() -> void:
	var m: Node3D = models.cuoc
	m.position = Vector3(0.15, -0.21, -0.36)
	# Handle forward and down to the blade near the ground; both hands
	# overhand, thumbs toward the blade.
	var d := Vector3(-0.3, -0.04, -1.0).normalized()
	var butt := -d * 0.06
	var tip := d * 1.1
	_rod(m, butt, tip, 0.019, 0.017, "wood")
	# Socket (khâu) and neck: the blade hangs back toward the farmer at ~65°.
	var side := d.cross(Vector3.UP).normalized()
	var down := d.cross(side).normalized()
	_rod(m, tip - d * 0.06, tip + d * 0.025, 0.026, 0.024, "iron", 12)
	var e := (d * cos(deg_to_rad(115)) + down * sin(deg_to_rad(115))).normalized()
	var bx := Basis(side, -e, side.cross(-e))
	_add(m, _hoe_blade(), "iron", Transform3D(bx, tip + d * 0.01))
	_hold("cuoc", "r", Vector3.ZERO, d, Vector3(0.14, -0.36, 0.24))
	_hold("cuoc", "l", d * 0.4, d, Vector3(-0.14, -0.22, 0.3))


# Trapezoid iron blade: a narrow neck, then 11 cm widening to a 17 cm edge,
# thick at the neck and honed thin and bright at the cutting edge.
func _hoe_blade() -> ArrayMesh:
	var pos := func(u: float, v: float) -> Vector3:
		var y := -v * 0.26
		var w := 0.035 if v < 0.15 else lerpf(0.11, 0.17, (v - 0.15) / 0.85)
		var x := (u - 0.5) * w
		return Vector3(x, y, 0.012 * (x * x) / 0.007 - 0.01 * v)
	var thick := func(_u: float, v: float) -> float:
		return lerpf(0.009, 0.0015, v * v)
	var col := func(u: float, v: float) -> Color:
		var edge := smoothstep(0.82, 1.0, v)
		var mud := smoothstep(0.35, 0.7, v) * (1.0 - edge) * (0.6 + 0.4 * sin(u * 19.0 + v * 7.0))
		return Color(0.45, 0.42, 0.4).lerp(Color(0.3, 0.22, 0.15), mud * 0.7).lerp(Color(1.6, 1.55, 1.5), edge)
	return _plate(8, 10, pos, thick, col)


func _build_bua() -> void:
	var m: Node3D = models.bua
	m.position = Vector3(0, -0.27, -0.46)
	# Bừa: a bamboo handle bar at waist height, two uprights down to the
	# toothed beam that drags through the mud ahead.
	_rod(m, Vector3(-0.34, 0, 0), Vector3(0.34, 0, 0), 0.02, 0.02, "bamboo")
	var beam_y := -0.86
	var beam_z := -0.55
	for x in [-0.28, 0.28]:
		_rod(m, Vector3(x, 0.02, 0.0), Vector3(x * 1.4, beam_y + 0.03, beam_z), 0.022, 0.026, "wood")
	_add(m, _tube(-0.56, 0.56, Vector2(0.04, 0.045), Vector2(0.04, 0.045), 8, 1), "wood", Transform3D(Basis(Vector3.UP, PI / 2), Vector3(0, beam_y, beam_z)))
	for i in 11:
		var x := -0.5 + i * 0.1
		_rod(m, Vector3(x, beam_y - 0.02, beam_z), Vector3(x, beam_y - 0.2, beam_z - 0.03), 0.011, 0.006, "wood", 6)
	_hold("bua", "r", Vector3(0.2, 0, 0), Vector3(-1, 0, 0), Vector3(0.27, -0.2, 0.3))
	_hold("bua", "l", Vector3(-0.2, 0, 0), Vector3(1, 0, 0), Vector3(-0.27, -0.2, 0.3))


func _build_gau() -> void:
	var m: Node3D = models.gau
	m.position = Vector3(0.15, -0.21, -0.36)
	var d := Vector3(-0.2, -0.26, -1.0).normalized()
	_rod(m, -d * 0.06, d * 0.95, 0.017, 0.015, "bamboo")
	# Woven scoop: open toward the farmer and up, like a big spoon.
	var cone := CylinderMesh.new()
	cone.top_radius = 0.2
	cone.bottom_radius = 0.1
	cone.height = 0.24
	cone.cap_top = false
	cone.radial_segments = 20
	var up := -d.cross(Vector3.RIGHT).normalized()
	var axis := (up * 0.6 - d * 0.4).normalized()
	var b := Basis(axis.cross(d).normalized(), axis, axis.cross(axis.cross(d)).normalized())
	_add(m, cone, "woven", Transform3D(b, d * 1.05 + axis * 0.06))
	var rim := TorusMesh.new()
	rim.inner_radius = 0.19
	rim.outer_radius = 0.215
	rim.rings = 24
	rim.ring_segments = 6
	_add(m, rim, "bamboo", Transform3D(b, d * 1.05 + axis * 0.18))
	_hold("gau", "r", Vector3.ZERO, d, Vector3(0.14, -0.36, 0.24))
	_hold("gau", "l", d * 0.38, d, Vector3(-0.14, -0.22, 0.3))


func _build_liem() -> void:
	var m: Node3D = models.liem
	m.position = Vector3(0.2, -0.17, -0.42)
	# Liềm: a short wooden handle in the right fist, the toothed crescent
	# blade curling forward and to the left from its top.
	var d := Vector3(-0.3, 0.85, -0.42).normalized()
	_rod(m, -d * 0.08, d * 0.13, 0.016, 0.018, "wood")
	_rod(m, d * 0.12, d * 0.15, 0.019, 0.017, "iron", 10) # ferrule
	var v := Vector3(-1.0, 0.0, -0.75)
	v = (v - d * v.dot(d)).normalized()
	_add(m, _sickle_blade(), "iron", Transform3D(Basis(v, d, v.cross(d)), d * 0.15))
	_hold("liem", "r", Vector3.ZERO, d, Vector3(0.16, -0.16, 0.32))
	# The left hand is free, half open, ready to gather the stalks.
	_hold("liem", "l", Vector3(-0.44, -0.04, 0.0), Vector3(0.85, 0.5, 0.0), Vector3(-0.5, -0.4, 0.3), "Grip", 0.2)


# Crescent blade in its own frame: X toward the inside of the curve, Y up
# the handle, Z the blade normal. A spiral (radius 15 -> 10 cm) so it reads
# as a sickle and not a ring, with a toothed inner edge.
func _sickle_blade() -> ArrayMesh:
	var spine := func(v: float) -> Vector3:
		var a := lerpf(0.0, 2.75, v)
		var r := lerpf(0.15, 0.1, v)
		return Vector3(0.15 - cos(a) * r, sin(a) * r + v * 0.02, 0)
	var nv := 44
	var pos := func(u: float, v: float) -> Vector3:
		var sp: Vector3 = spine.call(v)
		var c := Vector3(0.15, 0.0, 0)
		var w := lerpf(0.032, 0.006, pow(v, 0.8))
		var tooth := 0.0
		if u > 0.99 and v > 0.06:
			tooth = 0.0016 if int(round(v * nv)) % 2 == 0 else -0.0016
		var inward := (c - sp).normalized()
		if v < 0.02:
			inward = Vector3.RIGHT
		return sp + inward * (w * u + tooth)
	var thick := func(u: float, v: float) -> float:
		return lerpf(0.0042, 0.0008, u) * lerpf(1.0, 0.6, v)
	var col := func(u: float, _v: float) -> Color:
		return Color(0.42, 0.4, 0.38).lerp(Color(1.7, 1.65, 1.6), smoothstep(0.55, 1.0, u))
	return _plate(3, nv, pos, thick, col)


func _build_cao() -> void:
	var m: Node3D = models.cao
	m.position = Vector3(0.14, -0.21, -0.36)
	var d := Vector3(-0.2, -0.32, -1.0).normalized()
	var tip := d * 1.5
	_rod(m, -d * 0.06, tip, 0.018, 0.017, "wood")
	# Cào thóc: a wooden board with short teeth, for raking paddy on the yard.
	var side := Vector3.RIGHT
	var b := Basis(side, Vector3.UP, side.cross(Vector3.UP))
	_add(m, _tube(-0.28, 0.28, Vector2(0.03, 0.045), Vector2(0.03, 0.045), 6, 1), "wood", Transform3D(Basis(Vector3.UP, PI / 2), tip))
	for i in 9:
		var x := -0.24 + i * 0.06
		_rod(m, tip + b * Vector3(x, -0.03, 0), tip + b * Vector3(x, -0.11, 0.01), 0.008, 0.005, "wood", 6)
	_hold("cao", "r", Vector3.ZERO, d, Vector3(0.14, -0.36, 0.24))
	_hold("cao", "l", d * 0.42, d, Vector3(-0.14, -0.22, 0.3))


func _build_sao() -> void:
	var m: Node3D = models.sao
	m.position = Vector3(0.16, -0.2, -0.36)
	# A long bamboo pole raised ahead, rag strips tied at the tip.
	var d := Vector3(-0.12, 0.62, -1.0).normalized()
	var tip := d * 2.6
	_rod(m, -d * 0.05, tip, 0.022, 0.012, "bamboo", 8)
	for i in 7:
		var k := 0.35 + i * 0.33
		var r := lerpf(0.022, 0.012, k / 2.6) + 0.003
		_rod(m, d * (k - 0.008), d * (k + 0.008), r, r, "bamboo", 8) # culm nodes
	var cols := [Color("a8473a"), Color("3c5a8a"), Color("c9a640"), Color("7a8a5a")]
	for i in 4:
		var s := Node3D.new()
		s.position = tip - d * (0.02 + i * 0.035)
		m.add_child(s)
		_add(s, _strip(0.045, 0.5, cols[i]), "cloth")
		streamers.append(s)
	_hold("sao", "r", Vector3.ZERO, d, Vector3(0.14, -0.38, 0.22))
	_hold("sao", "l", d * 0.32, d, Vector3(-0.2, -0.38, 0.14))


# A hanging strip of cloth, from the knot down.
static func _strip(w: float, h: float, c: Color) -> ArrayMesh:
	var pos := func(u: float, v: float) -> Vector3:
		return Vector3((u - 0.5) * w * lerpf(1.0, 0.7, v), -v * h, sin(v * 5.0) * 0.02 * v)
	var thick := func(_u: float, _v: float) -> float:
		return 0.002
	var col := func(_u: float, v: float) -> Color:
		return c.darkened(0.25 * v)
	return _plate(1, 6, pos, thick, col)


func _build_bo_ma() -> void:
	bo_ma = Node3D.new()
	bo_ma.position = Vector3(-0.2, -0.2, -0.42)
	bo_ma.rotation = Vector3(0.35, 0, 0.25)
	bo_ma.visible = false
	rig.add_child(bo_ma)
	# A bundle of seedlings pulled from the nursery: green leaves fanning
	# out on top, a straw tie, roots and a lump of mud below.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 46:
		var a := rng.randf() * TAU
		var r := rng.randf() * 0.022
		var base := Vector3(cos(a) * r, 0.0, sin(a) * r)
		var lean := Vector3(cos(a), 0, sin(a)) * rng.randf_range(0.08, 0.35) + Vector3(rng.randf_range(-0.1, 0.1), 0, rng.randf_range(-0.1, 0.1))
		var h := rng.randf_range(0.17, 0.27)
		var w := 0.0035
		var tw := Vector3(-sin(a), 0, cos(a))
		for k in 4:
			var t0 := k / 4.0
			var t1 := (k + 1) / 4.0
			var p0 := base + Vector3(0, h * t0, 0) + lean * h * t0 * t0
			var p1 := base + Vector3(0, h * t1, 0) + lean * h * t1 * t1
			var w0 := w * (1.0 - t0 * 0.8)
			var w1 := w * (1.0 - t1 * 0.8)
			var c0 := Color(0.62, 0.7, 0.36).lerp(Color(0.24, 0.48, 0.12), t0)
			var c1 := Color(0.62, 0.7, 0.36).lerp(Color(0.24, 0.48, 0.12), t1)
			for q in [[p0 - tw * w0, c0], [p0 + tw * w0, c0], [p1 + tw * w1, c1], [p0 - tw * w0, c0], [p1 + tw * w1, c1], [p1 - tw * w1, c1]]:
				st.set_color(q[1]); st.add_vertex(q[0])
	st.generate_normals()
	_add(bo_ma, st.commit(), "seedling", Transform3D(Basis.IDENTITY, Vector3(0, 0.02, 0)))
	_rod(bo_ma, Vector3(0, 0.03, 0), Vector3(0, 0.06, 0), 0.026, 0.024, "straw", 10)
	var mud := SphereMesh.new()
	mud.radius = 0.035
	mud.height = 0.05
	mud.radial_segments = 12
	mud.rings = 6
	_add(bo_ma, mud, "mud", Transform3D(Basis.IDENTITY, Vector3(0, -0.025, 0)))
	_hold("bo_ma", "l", Vector3(0, 0.08, 0), Vector3(0.0, 1.0, 0.0), Vector3(-0.05, -0.2, 0.35), "Grip", 0.9)


func _build_ganh() -> void:
	ganh = Node3D.new()
	ganh.visible = false
	add_child(ganh)
	# Đòn gánh: a flat bamboo strip on the right shoulder along the walking
	# direction, bending under the two loads; each load hangs from a quang
	# (four ropes) as a pendulum.
	var pole := _tube(-0.85, 0.85, Vector2(0.024, 0.01), Vector2(0.024, 0.01), 10, 12, true, -0.05)
	_add(ganh, pole, "bamboo", Transform3D(Basis.IDENTITY, Vector3.ZERO))
	for k in 2:
		var z := -0.78 if k == 0 else 0.78
		var hook := Node3D.new()
		hook.position = Vector3(0, -0.012, z)
		ganh.add_child(hook)
		var ld := Node3D.new()
		hook.add_child(ld)
		ganh_loads.append(ld)
		var drop := 0.5
		for c in 4:
			var a := TAU * (c + 0.5) / 4.0
			_rod(ld, Vector3.ZERO, Vector3(cos(a) * 0.17, -drop, sin(a) * 0.17), 0.004, 0.004, "rope", 4)
		var ring := TorusMesh.new()
		ring.inner_radius = 0.17
		ring.outer_radius = 0.185
		ring.rings = 16
		ring.ring_segments = 4
		_add(ld, ring, "rope", Transform3D(Basis.IDENTITY, Vector3(0, -drop, 0)))
		# Sheaves (lượm lúa) laid crosswise in the cradle, heads outward.
		var rng := RandomNumberGenerator.new()
		rng.seed = 3 + k
		for s in 6:
			var ang := PI / 2 + rng.randf_range(-0.25, 0.25) + (PI if s % 2 == 1 else 0.0)
			var y := -drop + 0.06 + s * 0.045
			var sb := Basis(Vector3.UP, ang)
			var sheaf := Node3D.new()
			sheaf.transform = Transform3D(sb, Vector3(rng.randf_range(-0.03, 0.03), y, rng.randf_range(-0.03, 0.03)))
			ld.add_child(sheaf)
			_add(sheaf, _sheaf_mesh(), "sheaf")
			_rod(sheaf, Vector3(-0.13, 0, 0), Vector3(-0.11, 0, 0), 0.032, 0.032, "rope", 8)
	_hold("ganh", "r", Vector3(0, 0.02, -0.32), Vector3(0, 0, -1), Vector3(0.13, -0.3, -0.05))


# A lượm of cut rice along +X: straw butts at -X, tied near the butt,
# heavy golden panicles drooping at +X. One mesh shared by every sheaf.
static var _sheaf: ArrayMesh


static func _sheaf_mesh() -> ArrayMesh:
	if _sheaf != null:
		return _sheaf
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for i in 60:
		var a := rng.randf() * TAU
		var rr := sqrt(rng.randf())
		var off := Vector2(cos(a), sin(a)) * rr
		var tw := Vector3(0, cos(a + 1.3), sin(a + 1.3))
		var len := rng.randf_range(0.5, 0.6)
		var droop := rng.randf_range(0.04, 0.1)
		var pts := []
		for k in 7:
			var t := k / 6.0
			var x := -0.24 + t * len
			# Bundle radius: splayed butts, tight at the tie, fanning heads.
			var rad := lerpf(0.045, 0.028, smoothstep(0.0, 0.2, t)) if t < 0.35 else lerpf(0.028, 0.075, (t - 0.35) / 0.65)
			var yz := off * rad
			var y := yz.x - droop * maxf(0.0, t - 0.6) * maxf(0.0, t - 0.6) / 0.16
			pts.append([Vector3(x, y, yz.y), t])
		for k in 6:
			var p0: Vector3 = pts[k][0]
			var p1: Vector3 = pts[k + 1][0]
			var t0: float = pts[k][1]
			var t1: float = pts[k + 1][1]
			# Panicles are wider and darker gold than the straw.
			var w0 := 0.0025 if t0 < 0.65 else 0.006
			var w1 := 0.0025 if t1 < 0.65 else 0.006
			var straw := Color(0.64, 0.53, 0.29)
			var head := Color(0.55, 0.4, 0.15)
			var c0 := straw.lerp(head, smoothstep(0.55, 0.8, t0)).darkened(rng.randf() * 0.15)
			var c1 := straw.lerp(head, smoothstep(0.55, 0.8, t1))
			for q in [[p0 - tw * w0, c0], [p0 + tw * w0, c0], [p1 + tw * w1, c1], [p0 - tw * w0, c0], [p1 + tw * w1, c1], [p1 - tw * w1, c1]]:
				st.set_color(q[1]); st.add_vertex(q[0])
	st.generate_normals()
	_sheaf = st.commit()
	return _sheaf


func select(id: String) -> void:
	if not models.has(id) or busy():
		return
	models[current].visible = false
	current = id
	models[id].visible = true
	_hand_state = ""


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


# player: the body (for head turns, steps and walking speed).
func animate(dt: float, player, time: float, waving: bool, carrying: float) -> void:
	var cam := get_parent() as Node3D
	ganh.visible = carrying > 0.0
	var state := "%s|%s|%s" % [current, bo_ma.visible, ganh.visible]
	if state != _hand_state:
		_hand_state = state
		_attach_hands()

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
		streamers[i].rotation = Vector3(sin(time * 3.1 + i) * 0.25, sin(time * 8.0 + i) * 0.8 + (sin(_wave * 1.3 + i) if waving else 0.0), 0.9 + sin(time * 5.0 + i * 2.0) * 0.3)

	# Viewmodel lag: a spring pulled by head turns, heavier tools lag more.
	var w: float = WEIGHT[current]
	var look := Vector2(player.yaw, player.pitch)
	if _prev_look == Vector2.INF or dt <= 0.0:
		_prev_look = look
	var rate := Vector2(angle_difference(_prev_look.x, look.x), look.y - _prev_look.y) / maxf(dt, 0.001)
	_prev_look = look
	_sway_v += (-80.0 * _sway - 13.0 * _sway_v - rate * 0.6 * w) * dt
	_sway += _sway_v * dt
	_sway = _sway.clamp(Vector2(-0.12, -0.12), Vector2(0.12, 0.12))
	# Hands swing a little against each step and dip after the knees give.
	var bob: float = player.bob_phase
	var amt := clampf(player.speed() / 1.5, 0.0, 1.0)
	var walk := Vector3(sin(bob) * 0.012, -absf(cos(bob)) * 0.01, 0) * amt * (0.6 + 0.4 * w)
	var idle := Vector3(0, sin(time * 1.4) * 0.003, 0)
	rig.rotation = Vector3(_sway.y, _sway.x, _sway.x * 0.4)
	rig.position = walk + idle + Vector3(0, -player.land * 0.35, 0)

	# The tool group: rest pose x swing. Body-space tools (the harrow) cancel
	# the view pitch so they stay on the ground.
	var m: Node3D = models[current]
	var xf := Transform3D(Basis.from_euler(r), p)
	var body := Basis.from_euler(Vector3(cam.rotation.x, 0, cam.rotation.z)).inverse()
	if _body_space.has(current):
		var rb := Basis.from_euler(Vector3(rig.rotation.x, rig.rotation.y, rig.rotation.z)).inverse()
		m.transform = Transform3D(rb * body, rb * -rig.position) * _base[current] * xf
	else:
		m.transform = _base[current] * xf

	# Đòn gánh: rides on the right shoulder in body space; the loads swing.
	if ganh.visible:
		ganh.transform = Transform3D(body, body * Vector3(0.17, -0.24, 0.05)) * Transform3D(Basis(Vector3.UP, 0.06), Vector3.ZERO)
		var vel: Vector3 = player.vel
		var acc := (vel - _prev_vel) / maxf(dt, 0.001) if dt > 0.0 else Vector3.ZERO
		_prev_vel = vel
		# Acceleration in body space (x right, z back).
		var yb := Basis(Vector3.UP, player.yaw).inverse()
		var ab := yb * acc
		var g := 9.81
		for i in 2:
			var ang: Vector2 = _load_ang[i]
			var av: Vector2 = _load_vel[i]
			# Pendulum on a ~0.55 m rope: about 0.67 Hz.
			var drive := Vector2(ab.z, -ab.x) / 0.55 * 0.6 + Vector2(0, rate.x * 0.3)
			var step := Vector2(sin(bob * 2.0 + i) * 0.4, 0) * amt
			av += (-(g / 0.55) * ang - 1.2 * av + drive + step) * dt
			ang += av * dt
			ang = ang.clamp(Vector2(-0.5, -0.5), Vector2(0.5, 0.5))
			_load_ang[i] = ang
			_load_vel[i] = av
			var l: Node3D = ganh_loads[i]
			l.rotation = Vector3(ang.x, 0, ang.y)
			l.scale = Vector3.ONE * (0.55 + 0.45 * carrying)
			l.position.y = 0.012 * sin(bob * 2.0 - 1.2) * amt
	else:
		_prev_vel = player.vel
