# First-person body: walking, wading through mud, stamina and head bob.
# Walking has inertia, the head bob follows the footsteps, the knees give
# when stepping down off a bund, and a loaded đòn gánh shortens the stride.
extends RefCounted

const L = preload("res://scripts/layout.gd")

const LOOK_SPEED := 0.0013 # radians per mouse count at sensitivity 1 (~15 cm per turn at 800 DPI)
const PITCH_MIN := -1.5 # look down at your own feet in the mud
const PITCH_MAX := 1.45
const EYE_HEIGHT := 1.56 # m: eyes of a 1.65 m farmer, so bunds and rice read at true scale
# A real walk is ~1.4 m/s at ~2 steps/s; wading in puddled mud 0.6-0.9 m/s.
const SPEED := {"ground": 1.75, "dry": 1.65, "mud": 0.95, "water": 0.85} # m/s
const RUN := {"ground": 1.75, "dry": 1.7, "mud": 1.3, "water": 1.25} # multiplier with Shift
const ACCEL := {"ground": 9.0, "dry": 8.0, "mud": 3.5, "water": 3.0} # m/s², x1.6 when braking
const STEP_LEN := {"ground": 0.82, "dry": 0.78, "mud": 0.5, "water": 0.46} # m per step (~2 steps/s)
const BOB_V := {"ground": 0.012, "dry": 0.013, "mud": 0.02, "water": 0.017} # m, half of the 2-4 cm peak-to-peak
const BOB_H := {"ground": 0.012, "dry": 0.013, "mud": 0.022, "water": 0.019} # m sideways, one sway per two steps

var camera: Camera3D
var audio: Node
var pos := Vector3.ZERO
var yaw := PI
var pitch := -0.1
var stamina := 100.0
var y := 0.0
var vel := Vector3.ZERO
var gait := 0.0 # steps taken; the head is lowest (foot strike) at whole numbers
var bob_phase := 0.0 # gait * PI, read by the tools for hand sway
var moving := false
var running := false
var frozen := false
var shake := 0.0
var fov_base := 62.0 # vertical degrees (the camera keeps height): ~94° across at 16:9
var land := 0.0 # knee spring offset of the head (m), read by the tools

var _terr := ""
var _ground := 0.0
var _land_v := 0.0
var _blend := 0.0 # fades the bob in and out with speed
var _breath := 0.0


func _init(cam: Camera3D, audio_node: Node) -> void:
	camera = cam
	audio = audio_node
	camera.fov = fov_base


func forward() -> Vector3:
	return Vector3(-sin(yaw), 0, -cos(yaw))


func right() -> Vector3:
	return Vector3(cos(yaw), 0, -sin(yaw))


# rel: mouse movement in screen pixels, already scaled by sensitivity.
func look(rel: Vector2, invert_y := false) -> void:
	yaw = wrapf(yaw - rel.x * LOOK_SPEED, -PI, PI)
	var dy := rel.y * LOOK_SPEED * (-1.0 if invert_y else 1.0)
	pitch = clampf(pitch - dy, PITCH_MIN, PITCH_MAX)


func terrain(field) -> String:
	if L.in_field(pos.x, pos.z):
		var muddy: bool = field.till[field.cell_at(pos.x, pos.z)] > 0.5 or field.water > 1.0
		return "mud" if muddy else "dry"
	if pos.x > L.CANAL.x0 and pos.x < L.CANAL.x1:
		return "water"
	if L.in_pond(pos.x, pos.z):
		return "water"
	return "ground"


func speed() -> float:
	return Vector2(vel.x, vel.z).length()


# input: Vector2(strafe, forward) in -1..1. Returns metres moved this frame.
func update(dt: float, input: Vector2, run: bool, field, load_frac: float) -> float:
	var terr := terrain(field)
	var wish := Vector3.ZERO
	if not frozen:
		wish = forward() * input.y + right() * input.x
		if wish.length_squared() > 1.0:
			wish = wish.normalized()
	running = run and wish.length_squared() > 0.0 and stamina > 5.0
	var top: float = SPEED[terr] * (1.0 - 0.3 * load_frac) * (RUN[terr] if running else 1.0)
	if frozen:
		vel = Vector3.ZERO
	else:
		# Mud sucks at the feet: slow to get going, quick to stop.
		var accel: float = ACCEL[terr] * (1.6 if wish == Vector3.ZERO else 1.0)
		vel = vel.move_toward(wish * top, accel * dt)
	if running:
		stamina -= 14.0 * dt

	var moved := 0.0
	if vel.length_squared() > 0.0:
		var ox := pos.x
		var oz := pos.z
		var nx := pos.x + vel.x * dt
		var nz := pos.z + vel.z * dt
		if L.blocked(nx, pos.z):
			vel.x = 0.0
		else:
			pos.x = nx
		if L.blocked(pos.x, nz):
			vel.z = 0.0
		else:
			pos.z = nz
		pos.x = clampf(pos.x, -L.WORLD_HALF, L.WORLD_HALF)
		pos.z = clampf(pos.z, -L.WORLD_HALF, L.WORLD_HALF)
		moved = Vector2(pos.x - ox, pos.z - oz).length()
	moving = moved > 0.0005
	if not running:
		stamina += (4.0 if moving else 9.0) * dt
	stamina = clampf(stamina, 0.0, 100.0)

	# Where the feet are now decides sinking, landing and sounds.
	terr = terrain(field)
	var soft := terr == "mud" or terr == "water"
	var sink := 0.0
	if terr == "mud":
		sink = 0.12 + field.smooth[field.cell_at(pos.x, pos.z)] * 0.08
	elif terr == "water":
		sink = 0.1
	var gy := L.ground_y(pos.x, pos.z) - sink
	if _terr == "":
		# First frame (or a teleport set _terr = ""): no landing.
		y = gy
	elif dt > 0.0 and moving:
		# Stepping off the bund or into the canal: the knees take the drop.
		var drop := _ground - gy
		if drop > 0.15:
			_land_v -= clampf(drop * 2.5, 0.0, 1.5)
			audio.play("squelch" if soft else "step", -2.0)
		elif soft and not (_terr == "mud" or _terr == "water"):
			_land_v -= 0.5 # feet sink in: a small give
			audio.play("squelch", -2.0)
	_ground = gy
	_terr = terr
	y = lerpf(y, gy, 1.0 - exp(-dt * 12.0))
	# Slightly under-damped spring (zeta ~0.63): one small rebound, settled in ~0.4 s.
	_land_v += (-140.0 * land - 15.0 * _land_v) * dt
	land += _land_v * dt

	# Gait: one vertical bob per step, one sideways sway per two steps.
	var spd := speed()
	var load_step := 0.85 if load_frac > 0.0 else 1.0
	var step_len: float = STEP_LEN[terr] * (1.35 if running else 1.0) * load_step
	var prev := floorf(gait)
	gait += moved / step_len
	if floorf(gait) != prev:
		# Footfall at the lowest point of the bob.
		audio.play("squelch" if soft else "step", -4.0, randf_range(0.92, 1.08))
	_blend = move_toward(_blend, clampf(spd / 0.8, 0.0, 1.0), dt * 4.0)
	bob_phase = gait * PI
	var av: float = BOB_V[terr] * (1.5 if running else 1.0) * (1.3 if load_frac > 0.0 else 1.0)
	var bob_y := -cos(gait * TAU) * av * _blend
	var bob_x: float = sin(gait * PI) * BOB_H[terr] * _blend
	# The pole sits on the right shoulder: a steady lean plus extra roll per step.
	var roll: float = -bob_x * (0.9 + 0.8 * load_frac) - 0.035 * load_frac
	var nod := -0.012 * (0.5 - 0.5 * cos(gait * TAU)) * _blend if soft else 0.0

	# Breathing: barely there when rested, heavy when stamina is low.
	var tired := 1.0 - stamina / 100.0
	_breath += dt * TAU * lerpf(0.25, 0.7, tired)
	var breath := sin(_breath) * lerpf(0.002, 0.008, tired)

	shake = maxf(0.0, shake - dt)
	var jitter := Vector3(randf_range(-1, 1), randf_range(-1, 1), 0) * shake * 0.1
	camera.position = Vector3(pos.x, y + EYE_HEIGHT + bob_y + land, pos.z) + right() * bob_x
	camera.rotation = Vector3(pitch + nod + breath + jitter.x, yaw + jitter.y, roll)
	var fov_target := fov_base + (5.0 if running and spd > 2.2 else 0.0) - 2.0 * load_frac
	camera.fov = lerpf(camera.fov, fov_target, 1.0 - exp(-dt * 6.0)) if dt > 0.0 else fov_target
	return moved


# Scripted cameras (tour, autotest) jump the body: settle at once.
func teleported() -> void:
	_terr = ""
	vel = Vector3.ZERO
	land = 0.0
	_land_v = 0.0
