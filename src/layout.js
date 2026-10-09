// World layout: every coordinate of the farm lives here so the scenery,
// the simulation and the interactions all agree on where things are.
// x = east, z = south, y = up. Units are metres.

export const FIELD = { x0: -8, x1: 8, z0: -8, z1: 8, y: -0.25, bund: 0.8, bundTop: 0.15 };
export const CANAL = { x0: -12, x1: -10, z0: -55, z1: 55 };
export const POND = { x: -20, z: -10, r: 4.5 };
export const COURT = { x0: -6, x1: 6, z0: -20, z1: -14, cols: 12, rows: 6 };
export const TARP = { x0: -2, x1: 2, z0: -19, z1: -15 };
export const DUCK_PEN = { x0: 12, x1: 16, z0: 6, z1: 10 };

export const P = {
  start: [0, -12.5],
  gate: [-8.4, 0], // cửa cống, west bund
  drain: [8.4, 4], // rãnh xả, east bund
  scoop: [-9.6, -4], // chỗ tát nước
  hammock: [3.5, -21.0],
  barrel: [8.5, -17],
  tarpRoll: [-7.5, -15.5],
  brickPile: [-7.5, -19.2],
  basket: [9.5, -20.5],
  nursery: [13, -16],
  duckGate: [12, 8],
  pondEdge: [-16, -10],
  board: [-10.5, -22.5],
  stove: [-8.5, -24.5],
  trough: [-12.6, -24],
  pig: [-15, -24],
  biogas: [-18, -28],
  buffalo: [-3, 12.5],
};

export const CORNERS = [[-2, -19], [2, -19], [-2, -15], [2, -15]];
export const STAKES = [[-5, -5], [0, -6.2], [5, -4], [-4.2, 3], [2.2, 5], [6, 1.5]];

// Axis-aligned blockers the player cannot walk through.
export const BLOCKERS = [
  { x0: -5.2, x1: 5.2, z0: -29, z1: -22 }, // nhà
  { x0: -17.2, x1: -13, z0: -26.2, z1: -21.8 }, // chuồng lợn
  { x0: -19.3, x1: -16.7, z0: -29.3, z1: -26.7 }, // hầm biogas
];

export const WORLD_HALF = 34;

export function inField(x, z, margin = 0) {
  return x > FIELD.x0 - margin && x < FIELD.x1 + margin && z > FIELD.z0 - margin && z < FIELD.z1 + margin;
}

export function inCourt(x, z) {
  return x > COURT.x0 && x < COURT.x1 && z > COURT.z0 && z < COURT.z1;
}

export function baseGroundY(x, z) {
  if (inField(x, z)) return FIELD.y;
  if (inField(x, z, FIELD.bund)) return FIELD.bundTop;
  if (x > CANAL.x0 && x < CANAL.x1) return -0.75;
  const dx = x - POND.x, dz = z - POND.z;
  if (dx * dx + dz * dz < POND.r * POND.r) return -0.6;
  return 0;
}
