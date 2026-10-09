// First-person body: walking, wading through mud, stamina and head bob.
import * as THREE from 'three';
import { BLOCKERS, WORLD_HALF, inField, baseGroundY, CANAL, POND } from './layout.js';
import { clamp, lerp } from './util.js';
import { sfx } from './audio.js';

export class Player {
  constructor(camera) {
    this.camera = camera;
    this.pos = new THREE.Vector3();
    this.yaw = Math.PI;
    this.pitch = -0.1;
    this.stamina = 100;
    this.y = 0;
    this.bobPhase = 0;
    this.stepDist = 0;
    this.moving = false;
    this.lastMove = 0;
    this.frozen = false;
    camera.rotation.order = 'YXZ';
  }

  forward(out = new THREE.Vector3()) { return out.set(-Math.sin(this.yaw), 0, -Math.cos(this.yaw)); }
  right(out = new THREE.Vector3()) { return out.set(Math.cos(this.yaw), 0, -Math.sin(this.yaw)); }

  look(dx, dy) {
    this.yaw -= dx * 0.0022;
    this.pitch = clamp(this.pitch - dy * 0.0022, -1.45, 1.35);
  }

  terrain(field) {
    const { x, z } = this.pos;
    if (inField(x, z)) {
      const muddy = field.till[field.cellAt(x, z)] > 0.5 || field.water > 1;
      return muddy ? 'mud' : 'dry';
    }
    if (x > CANAL.x0 && x < CANAL.x1) return 'water';
    const dx = x - POND.x, dz = z - POND.z;
    if (dx * dx + dz * dz < POND.r * POND.r) return 'water';
    return 'ground';
  }

  update(dt, keys, field, { load = 0 } = {}) {
    const fw = this.forward(), rt = this.right();
    const dir = new THREE.Vector3();
    if (!this.frozen) {
      if (keys.KeyW) dir.add(fw);
      if (keys.KeyS) dir.sub(fw);
      if (keys.KeyD) dir.add(rt);
      if (keys.KeyA) dir.sub(rt);
    }
    const terr = this.terrain(field);
    let speed = { ground: 3.4, dry: 3.0, mud: 1.5, water: 1.3 }[terr];
    speed *= 1 - 0.35 * load;
    const running = keys.ShiftLeft && dir.lengthSq() > 0 && this.stamina > 5;
    if (running) { speed *= 1.7; this.stamina -= 14 * dt; }
    this.moving = dir.lengthSq() > 0;
    let moved = 0;
    if (this.moving) {
      dir.normalize().multiplyScalar(speed * dt);
      const nx = this.pos.x + dir.x, nz = this.pos.z + dir.z;
      const blocked = (x, z) => BLOCKERS.some(b => x > b.x0 && x < b.x1 && z > b.z0 && z < b.z1);
      if (!blocked(nx, this.pos.z)) this.pos.x = nx;
      if (!blocked(this.pos.x, nz)) this.pos.z = nz;
      this.pos.x = clamp(this.pos.x, -WORLD_HALF, WORLD_HALF);
      this.pos.z = clamp(this.pos.z, -WORLD_HALF, WORLD_HALF);
      moved = dir.length();
      this.lastMove = moved;
    } else this.lastMove = 0;

    if (!running) this.stamina += (this.moving ? 4 : 9) * dt;
    this.stamina = clamp(this.stamina, 0, 100);

    // Feet sink in puddled mud.
    const sink = terr === 'mud' ? 0.12 + field.smooth[field.cellAt(this.pos.x, this.pos.z)] * 0.08 : terr === 'water' ? 0.1 : 0;
    const gy = baseGroundY(this.pos.x, this.pos.z) - sink;
    this.y = lerp(this.y, gy, 1 - Math.exp(-dt * 10));

    const mud = terr === 'mud' || terr === 'water';
    if (this.moving) this.bobPhase += moved * (mud ? 3.2 : 4.2);
    const amp = mud ? 0.07 : 0.035;
    const bob = this.moving ? Math.sin(this.bobPhase) * amp : 0;
    const sway = this.moving && mud ? Math.sin(this.bobPhase * 0.5) * 0.02 : 0;

    this.stepDist += moved;
    if (this.stepDist > (mud ? 0.75 : 0.9)) {
      this.stepDist = 0;
      if (mud) sfx.squelch(); else sfx.step();
    }

    this.camera.position.set(this.pos.x, this.y + 1.62 + bob, this.pos.z);
    this.camera.rotation.set(this.pitch, this.yaw, sway);
    return { terrain: terr, moved };
  }
}
