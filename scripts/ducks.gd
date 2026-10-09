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
		W.sphere(node, 0.18, Color("f3efe4"), Vector3(0, 0.17, 0), Vector3(1, 0.75, 1.5))
		W.sphere(node, 0.09, Color("f3efe4"), Vector3(0, 0.33, 0.22))
		W.box(node, Vector3(0.06, 0.03, 0.1), Color("e8a23a"), Vector3(0, 0.31, 0.33))
		list.append({
			"node": node,
			"pos": Vector3(randf_range(p.x0 + 0.5, p.x1 - 0.5), 0, randf_range(p.z0 + 0.5, p.z1 - 0.5)),
			"vel": Vector3.ZERO,
			"wander": randf() * TAU,
		})


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
		if gy < -0.2:
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
