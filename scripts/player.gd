# First-person body: walking, wading through mud, stamina and head bob.
extends RefCounted

const L = preload("res://scripts/layout.gd")

var camera: Camera3D
var audio: Node
var pos := Vector3.ZERO
var yaw := PI
var pitch := -0.1
var stamina := 100.0
var y := 0.0
var bob_phase := 0.0
var step_dist := 0.0
var moving := false
var frozen := false
var shake := 0.0


func _init(cam: Camera3D, audio_node: Node) -> void:
	camera = cam
	audio = audio_node


func forward() -> Vector3:
	return Vector3(-sin(yaw), 0, -cos(yaw))


func right() -> Vector3:
	return Vector3(cos(yaw), 0, -sin(yaw))


func look(rel: Vector2) -> void:
	yaw -= rel.x * 0.0022
	pitch = clampf(pitch - rel.y * 0.0022, -1.45, 1.35)


func terrain(field) -> String:
	if L.in_field(pos.x, pos.z):
		var muddy: bool = field.till[field.cell_at(pos.x, pos.z)] > 0.5 or field.water > 1.0
		return "mud" if muddy else "dry"
	if pos.x > L.CANAL.x0 and pos.x < L.CANAL.x1:
		return "water"
	if L.in_pond(pos.x, pos.z):
		return "water"
	return "ground"


# input: Vector2(strafe, forward) in -1..1. Returns metres moved this frame.
func update(dt: float, input: Vector2, run: bool, field, load_frac: float) -> float:
	var dir := Vector3.ZERO
	if not frozen:
		dir = forward() * input.y + right() * input.x
	var terr := terrain(field)
	var speed: float = {"ground": 3.4, "dry": 3.0, "mud": 1.5, "water": 1.3}[terr]
	speed *= 1.0 - 0.35 * load_frac
	var running := run and dir.length_squared() > 0.0 and stamina > 5.0
	if running:
		speed *= 1.7
		stamina -= 14.0 * dt
	moving = dir.length_squared() > 0.0
	var moved := 0.0
	if moving:
		dir = dir.normalized() * speed * dt
		var nx := pos.x + dir.x
		var nz := pos.z + dir.z
		if not L.blocked(nx, pos.z):
			pos.x = nx
		if not L.blocked(pos.x, nz):
			pos.z = nz
		pos.x = clampf(pos.x, -L.WORLD_HALF, L.WORLD_HALF)
		pos.z = clampf(pos.z, -L.WORLD_HALF, L.WORLD_HALF)
		moved = dir.length()
	if not running:
		stamina += (4.0 if moving else 9.0) * dt
	stamina = clampf(stamina, 0.0, 100.0)

	# Feet sink into puddled mud.
	var sink := 0.0
	if terr == "mud":
		sink = 0.12 + field.smooth[field.cell_at(pos.x, pos.z)] * 0.08
	elif terr == "water":
		sink = 0.1
	var gy := L.ground_y(pos.x, pos.z) - sink
	y = lerpf(y, gy, 1.0 - exp(-dt * 10.0))

	var mud := terr == "mud" or terr == "water"
	if moving:
		bob_phase += moved * (3.2 if mud else 4.2)
	var amp := 0.07 if mud else 0.035
	var bob := sin(bob_phase) * amp if moving else 0.0
	var sway := sin(bob_phase * 0.5) * 0.02 if (moving and mud) else 0.0

	step_dist += moved
	if step_dist > (0.75 if mud else 0.9):
		step_dist = 0.0
		audio.play("squelch" if mud else "step", -4.0)

	shake = maxf(0.0, shake - dt)
	var jitter := Vector3(randf_range(-1, 1), randf_range(-1, 1), 0) * shake * 0.1
	camera.position = Vector3(pos.x, y + 1.62 + bob, pos.z)
	camera.rotation = Vector3(pitch + jitter.x, yaw + jitter.y, sway)
	return moved
