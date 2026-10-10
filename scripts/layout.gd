# World layout: every coordinate of the farm lives here so the scenery,
# the simulation and the interactions agree on where things are.
# x = east, z = south, y = up. Units are metres. Points are Vector2(x, z).
extends RefCounted

const FIELD := {"x0": -8.0, "x1": 8.0, "z0": -8.0, "z1": 8.0, "y": -0.25, "bund": 0.8, "bund_top": 0.15}
const CANAL := {"x0": -12.0, "x1": -10.0}
const POND := {"x": -20.0, "z": -10.0, "r": 4.5}
const COURT := {"x0": -6.0, "x1": 6.0, "z0": -20.0, "z1": -14.0, "cols": 12, "rows": 6}
const TARP := {"x0": -2.0, "x1": 2.0, "z0": -19.0, "z1": -15.0}
const DUCK_PEN := {"x0": 12.0, "x1": 16.0, "z0": 6.0, "z1": 10.0}
const WORLD_HALF := 34.0

const START := Vector2(0, -12.5)
const GATE := Vector2(-8.4, 0) # cửa cống, bờ tây
const DRAIN := Vector2(8.4, 4) # rãnh xả, bờ đông
const HAMMOCK := Vector2(3.5, -21.0)
const BARREL := Vector2(8.5, -17)
const TARP_ROLL := Vector2(-7.5, -15.5)
const BRICK_PILE := Vector2(-7.5, -19.2)
const BASKET := Vector2(9.5, -20.5)
const NURSERY := Vector2(13, -16)
const DUCK_GATE := Vector2(12, 8)
const POND_EDGE := Vector2(-16, -10)
const BOARD := Vector2(-10.5, -22.5)
const STOVE := Vector2(-8.5, -24.5)
const TROUGH := Vector2(-12.6, -24)
const PIG := Vector2(-15, -24)
const BIOGAS := Vector2(-18, -28)
const BUFFALO := Vector2(-3, 12.5)

const CORNERS := [Vector2(-2, -19), Vector2(2, -19), Vector2(-2, -15), Vector2(2, -15)]
const STAKES := [Vector2(-5, -5), Vector2(0, -6.2), Vector2(5, -4), Vector2(-4.2, 3), Vector2(2.2, 5), Vector2(6, 1.5)]

# Axis-aligned blockers the player cannot walk through: [x0, x1, z0, z1]
const BLOCKERS := [
	[-5.2, 5.2, -29.0, -22.0], # nhà
	[-17.2, -13.0, -26.2, -21.8], # chuồng lợn
	[-19.3, -16.7, -29.3, -26.7], # hầm biogas
]


static func in_field(x: float, z: float, margin := 0.0) -> bool:
	return x > FIELD.x0 - margin and x < FIELD.x1 + margin and z > FIELD.z0 - margin and z < FIELD.z1 + margin


static func in_court(x: float, z: float) -> bool:
	return x > COURT.x0 and x < COURT.x1 and z > COURT.z0 and z < COURT.z1


static func in_pen(x: float, z: float) -> bool:
	return x > DUCK_PEN.x0 and x < DUCK_PEN.x1 and z > DUCK_PEN.z0 and z < DUCK_PEN.z1


# The pond shore wobbles around POND.r so it does not read as a pool.
static func pond_r(x: float, z: float) -> float:
	var a := atan2(z - POND.z, x - POND.x)
	return POND.r * (1.0 + 0.09 * sin(a * 2.0 - 1.57) + 0.05 * sin(a * 3.0 - 0.5) + 0.03 * sin(a * 5.0 - 0.3))


static func in_pond(x: float, z: float) -> bool:
	return Vector2(x - POND.x, z - POND.z).length() < pond_r(x, z)


static func blocked(x: float, z: float) -> bool:
	for b in BLOCKERS:
		if x > b[0] and x < b[1] and z > b[2] and z < b[3]:
			return true
	return false


# Where the plank bridge crosses the canal on the way to the pond.
const BRIDGE := {"z": -13.0, "half": 0.45, "y": 0.1}
const POND_WATER := -0.12

static var _n1: FastNoiseLite
static var _n2: FastNoiseLite


static func _rect_sd(x: float, z: float, x0: float, x1: float, z0: float, z1: float) -> float:
	var dx := maxf(x0 - x, x - x1)
	var dz := maxf(z0 - z, z - z1)
	return Vector2(maxf(dx, 0.0), maxf(dz, 0.0)).length() + minf(maxf(dx, dz), 0.0)


# Height of the bare land in metres, outside the paddy floor. The terrain
# mesh, the ground shader's wet band and ground_y all use it, so the player
# walks on what is drawn. Gentle swells only rise above y = 0, so plants
# scattered at y = 0 sink into the grass instead of floating.
static func terrain_y(x: float, z: float) -> float:
	if _n1 == null:
		_n1 = FastNoiseLite.new()
		_n1.seed = 3
		_n1.frequency = 0.06
		_n1.fractal_octaves = 3
		_n2 = FastNoiseLite.new()
		_n2.seed = 11
		_n2.frequency = 0.012
	var h := (_n1.get_noise_2d(x, z) * 0.5 + 0.5) * 0.05 + (_n2.get_noise_2d(x, z) * 0.5 + 0.5) * 0.14
	# Yard, house, pens and nursery are levelled and trodden flat.
	var flat := 1.0 - smoothstep(0.0, 2.0, _rect_sd(x, z, -6.5, 6.5, -30.0, -13.5))
	flat = maxf(flat, 1.0 - smoothstep(0.0, 1.5, _rect_sd(x, z, -19.5, -6.5, -29.5, -21.5)))
	flat = maxf(flat, 1.0 - smoothstep(0.0, 1.5, _rect_sd(x, z, DUCK_PEN.x0, DUCK_PEN.x1, DUCK_PEN.z0, DUCK_PEN.z1)))
	flat = maxf(flat, 1.0 - smoothstep(0.0, 1.5, Vector2(x, z).distance_to(NURSERY) - 2.2))
	h *= 1.0 - flat
	# Back to y = 0 at the edge of the near terrain, where the far ground starts.
	var edge := maxf(absf(x) - 36.0, maxf(-40.0 - z, z - 32.0))
	h *= 1.0 - smoothstep(0.0, 3.5, edge)

	# Bờ ruộng: steep plastered side toward the paddy, a narrow rounded
	# crown, a gentler grassy slope outward.
	var fd := _rect_sd(x, z, FIELD.x0, FIELD.x1, FIELD.z0, FIELD.z1)
	if fd < 1.2:
		var top: float = FIELD.bund_top
		var bund: float
		if fd < 0.25:
			bund = lerpf(FIELD.y + 0.13, top, smoothstep(-0.02, 0.25, fd))
			if fd < 0.0:
				bund = lerpf(FIELD.y + 0.13, FIELD.y - 0.06, smoothstep(0.0, 0.3, -fd))
		elif fd < 0.6:
			var t := (fd - 0.425) / 0.175
			bund = top + 0.025 * (1.0 - t * t)
		else:
			bund = lerpf(top, h, smoothstep(0.6, 1.0, fd))
		h = bund
		# Notches in the bund: the sluice from the canal (west) and the drain (east).
		var gate := (1.0 - smoothstep(0.25, 0.45, absf(z - GATE.y))) * (1.0 - smoothstep(-8.0, -7.9, x)) * smoothstep(-10.7, -10.3, x)
		var drain := (1.0 - smoothstep(0.25, 0.45, absf(z - DRAIN.y))) * smoothstep(7.9, 8.0, x) * (1.0 - smoothstep(9.3, 9.7, x))
		h = minf(h, lerpf(h, -0.18, maxf(gate, drain)))

	# Mương: trapezoid channel with a muddy bed.
	var cd := absf(x - (CANAL.x0 + CANAL.x1) * 0.5)
	if cd < 1.4:
		var bed := -0.95 + 0.04 * sin(z * 0.7)
		h = lerpf(bed, h, smoothstep(0.55, 1.35, cd))

	# Ao: a bowl under the water, a muddy bank sloping up to the grass.
	var pd := Vector2(x - POND.x, z - POND.z).length()
	if pd < POND.r * 1.5 + 1.0:
		var d := pd / pond_r(x, z)
		var bowl: float
		if d < 1.0:
			bowl = POND_WATER - 0.78 * pow(1.0 - d * d, 0.6)
		else:
			bowl = lerpf(POND_WATER - 0.02, h, smoothstep(0.0, 1.0, (pd - pond_r(x, z)) / 0.9))
		h = minf(h, bowl) if d >= 1.0 else bowl
	return h


static func ground_y(x: float, z: float) -> float:
	if in_field(x, z):
		return FIELD.y
	if absf(z - BRIDGE.z) < BRIDGE.half and x > CANAL.x0 - 0.9 and x < CANAL.x1 + 0.9:
		return maxf(BRIDGE.y, terrain_y(x, z))
	return terrain_y(x, z)
