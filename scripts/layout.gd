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


static func in_pond(x: float, z: float) -> bool:
	return Vector2(x - POND.x, z - POND.z).length() < POND.r


static func blocked(x: float, z: float) -> bool:
	for b in BLOCKERS:
		if x > b[0] and x < b[1] and z > b[2] and z < b[3]:
			return true
	return false


static func ground_y(x: float, z: float) -> float:
	if in_field(x, z):
		return FIELD.y
	if in_field(x, z, FIELD.bund):
		return FIELD.bund_top
	if x > CANAL.x0 and x < CANAL.x1:
		return -0.75
	return 0.0
