# "Vịt chạy đồng": a small flock herded with the duck pole and a whistle.
extends Node3D

const L = preload("res://scripts/layout.gd")
const W = preload("res://scripts/world.gd")

var audio: Node
var list: Array = [] # [{node, pos: Vector3, vel: Vector3, wander: float}]
var whistle_t := 0.0
var _quack_t := 2.0


func setup(audio_node: Node, n := 10) -> void:
	audio = audio_node
	var p: Dictionary = L.DUCK_PEN
	for i in n:
		var node := Node3D.new()
		add_child(node)
		_build_duck(node, i)
		list.append({
			"node": node,
			"pos": Vector3(randf_range(p.x0 + 0.5, p.x1 - 0.5), 0, randf_range(p.z0 + 0.5, p.z1 - 0.5)),
			"vel": Vector3.ZERO,
			"wander": randf() * TAU,
		})


# Vịt cỏ: small field ducks, mostly mottled brown with a darker back and
# head and a pale eye stripe, a few white; orange-yellow bills and feet.
# Bodies are lofted once per colour variant and shared by the flock.
static var _meshes := {}


func _build_duck(node: Node3D, i: int) -> void:
	var white := i % 4 == 0
	var key := "white" if white else "brown%d" % (i % 3)
	if not _meshes.has(key):
		_meshes[key] = _duck_meshes(white, i % 3)
	var parts: Array = _meshes[key]
	for k in parts.size():
		var mi := MeshInstance3D.new()
		mi.mesh = parts[k][0]
		mi.material_override = parts[k][1]
		node.add_child(mi)


func _duck_meshes(white: bool, v: int) -> Array:
	var feather := StandardMaterial3D.new()
	feather.vertex_color_use_as_albedo = true
	feather.vertex_color_is_srgb = true
	feather.roughness = 0.85
	var bill := StandardMaterial3D.new()
	bill.albedo_color = Color("e2a23c") if white else Color("b89a4a")
	bill.roughness = 0.45
	var feet := StandardMaterial3D.new()
	feet.albedo_color = Color("e08a2c") if white else Color("b07a3a")
	feet.roughness = 0.6
	var n := FastNoiseLite.new()
	n.seed = v * 31
	n.frequency = 45.0
	var base := Color("6e5236").lerp(Color("8c6a44"), v * 0.4)
	var paint := func(p: Vector3) -> Color:
		if white:
			return Color("e6e1d4").darkened(0.06 * n.get_noise_3dv(p))
		# Mottled breast and flanks, darker back and wings, brown-black head.
		var c := base.lerp(Color("a68862"), smoothstep(0.2, 0.12, p.y) * 0.6)
		c = c.darkened(0.25 * maxf(0.0, n.get_noise_3dv(p)) + 0.15 * smoothstep(0.24, 0.29, p.y))
		if p.y > 0.34:
			c = Color("3e3020")
			if absf(p.y - 0.41) < 0.008 and p.z > 0.2:
				c = Color("b8a07a") # eye stripe
		return c
	var out := []
	out.append([W.loft([
		[Vector3(0, 0.255, -0.24), 0.012, 0.01],
		[Vector3(0, 0.225, -0.19), 0.06, 0.035],
		[Vector3(0, 0.2, -0.12), 0.11, 0.085],
		[Vector3(0, 0.185, -0.02), 0.13, 0.11],
		[Vector3(0, 0.19, 0.07), 0.125, 0.11],
		[Vector3(0, 0.215, 0.14), 0.095, 0.09],
		[Vector3(0, 0.255, 0.18), 0.06, 0.06],
	], 14, paint, Vector3(1, 0, 0)), feather])
	out.append([W.loft([
		[Vector3(0, 0.26, 0.16), 0.045, 0.045],
		[Vector3(0, 0.31, 0.19), 0.033, 0.035],
		[Vector3(0, 0.36, 0.205), 0.032, 0.033],
		[Vector3(0, 0.395, 0.215), 0.042, 0.04],
		[Vector3(0, 0.41, 0.245), 0.045, 0.042],
		[Vector3(0, 0.405, 0.28), 0.032, 0.03],
	], 12, paint, Vector3(1, 0, 0)), feather])
	out.append([W.loft([
		[Vector3(0, 0.398, 0.28), 0.024, 0.014],
		[Vector3(0, 0.392, 0.31), 0.022, 0.009],
		[Vector3(0, 0.388, 0.335), 0.019, 0.006],
	], 8, func(_p: Vector3) -> Color: return Color.WHITE, Vector3(1, 0, 0)), bill])
	for s in [-1.0, 1.0]:
		out.append([W.loft([
			[Vector3(s * 0.05, 0.13, 0.0), 0.012, 0.012],
			[Vector3(s * 0.055, 0.05, 0.01), 0.009, 0.009],
			[Vector3(s * 0.055, 0.008, 0.04), 0.03, 0.004],
			[Vector3(s * 0.055, 0.006, 0.075), 0.035, 0.003],
		], 6, func(_p: Vector3) -> Color: return Color.WHITE, Vector3(1, 0, 0)), feet])
	return out


func whistle() -> void:
	whistle_t = 6.0
	audio.play("whistle")


func fraction_in_field() -> float:
	var n := 0
	for d in list:
		if L.in_field(d.pos.x, d.pos.z):
			n += 1
	return float(n) / list.size()


func count_outside_pen() -> int:
	var n := 0
	for d in list:
		if not L.in_pen(d.pos.x, d.pos.z):
			n += 1
	return n


func step(dt: float, player: Vector3, fwd: Vector3, pole_active: bool, pen_open: bool, time: float) -> void:
	whistle_t = maxf(0.0, whistle_t - dt)
	var center := Vector3.ZERO
	for d in list:
		center += d.pos
	center /= list.size()
	var scared := false
	var p: Dictionary = L.DUCK_PEN
	for d in list:
		var pos: Vector3 = d.pos
		var f := Vector3.ZERO
		d.wander += randf_range(-1.5, 1.5) * dt
		f += Vector3(cos(d.wander), 0, sin(d.wander)) * 0.4
		f += (center - pos) * 0.25
		for o in list:
			if is_same(o, d):
				continue
			var away: Vector3 = pos - o.pos
			var l := away.length()
			if l < 0.5 and l > 0.001:
				f += away * ((0.5 - l) * 6.0 / l)
		var to_me := pos - player
		to_me.y = 0
		var dist := to_me.length()
		if pole_active and dist < 7.0:
			# flee the waving pole, mostly along the way the player faces
			f += to_me.normalized() * 4.0 * (7.0 - dist) / 7.0 + fwd * 2.0 * (7.0 - dist) / 7.0
			scared = true
		elif dist < 1.2:
			f += to_me.normalized() * 2.0
		if whistle_t > 0.0 and dist > 2.0:
			f += -to_me.normalized() * 2.2
		var vel: Vector3 = d.vel + f * dt * 2.0
		vel *= 0.92
		var max_v := 2.6 if (pole_active and dist < 7.0) else (2.0 if whistle_t > 0.0 else 0.7)
		if vel.length() > max_v:
			vel = vel.normalized() * max_v
		pos += vel * dt
		pos.x = clampf(pos.x, -L.WORLD_HALF, L.WORLD_HALF)
		pos.z = clampf(pos.z, -L.WORLD_HALF, L.WORLD_HALF)
		var in_pen: bool = pos.x > p.x0 - 0.3 and pos.x < p.x1 and pos.z > p.z0 and pos.z < p.z1
		if not pen_open and in_pen:
			pos.x = clampf(pos.x, p.x0 + 0.2, p.x1 - 0.2)
			pos.z = clampf(pos.z, p.z0 + 0.2, p.z1 - 0.2)
		if L.blocked(pos.x, pos.z):
			pos -= vel * dt * 1.5
		d.pos = pos
		d.vel = vel
		var gy := L.ground_y(pos.x, pos.z)
		if L.in_pond(pos.x, pos.z):
			gy = maxf(gy, L.POND_WATER - 0.06) # swimming in the pond
		elif gy < -0.2:
			gy = -0.3 # swimming in the canal
		var node: Node3D = d.node
		node.position = Vector3(pos.x, gy + sin(time * 6.0 + d.wander) * 0.015, pos.z)
		if vel.length_squared() > 0.01:
			node.rotation.y = atan2(vel.x, vel.z)
	_quack_t -= dt * (4.0 if scared else 1.0)
	if _quack_t <= 0.0:
		_quack_t = randf_range(2, 6)
		for d in list:
			if d.pos.distance_to(player) < 15.0:
				audio.play("quack", -6.0)
				break
