// "Vịt chạy đồng": a small flock herded with the duck pole and a whistle.
import * as THREE from 'three';
import { DUCK_PEN, WORLD_HALF, BLOCKERS, inField, baseGroundY } from './layout.js';
import { clamp, rand } from './util.js';
import { mat } from './world.js';
import { sfx } from './audio.js';

function duckMesh() {
  const g = new THREE.Group();
  const body = new THREE.Mesh(new THREE.SphereGeometry(0.18, 8, 6), mat(0xf3efe4));
  body.scale.set(1, 0.75, 1.5);
  body.position.y = 0.17;
  g.add(body);
  const head = new THREE.Mesh(new THREE.SphereGeometry(0.09, 8, 6), mat(0xf3efe4));
  head.position.set(0, 0.33, 0.22);
  g.add(head);
  const beak = new THREE.Mesh(new THREE.BoxGeometry(0.06, 0.03, 0.1), mat(0xe8a23a));
  beak.position.set(0, 0.31, 0.33);
  g.add(beak);
  g.traverse(o => { if (o.isMesh) o.castShadow = true; });
  return g;
}

export class Ducks {
  constructor(scene, n = 10) {
    this.list = [];
    for (let i = 0; i < n; i++) {
      const mesh = duckMesh();
      scene.add(mesh);
      this.list.push({
        mesh,
        pos: new THREE.Vector3(rand(DUCK_PEN.x0 + 0.5, DUCK_PEN.x1 - 0.5), 0, rand(DUCK_PEN.z0 + 0.5, DUCK_PEN.z1 - 0.5)),
        vel: new THREE.Vector3(),
        wander: rand(0, Math.PI * 2),
      });
    }
    this.whistleT = 0;
    this.quackT = 2;
  }

  whistle() { this.whistleT = 6; sfx.whistle(); }

  fractionInField() {
    return this.list.filter(d => inField(d.pos.x, d.pos.z)).length / this.list.length;
  }

  update(dt, { player, forward, poleActive, penOpen, time }) {
    this.whistleT = Math.max(0, this.whistleT - dt);
    const center = new THREE.Vector3();
    for (const d of this.list) center.add(d.pos);
    center.multiplyScalar(1 / this.list.length);
    const f = new THREE.Vector3(), tmp = new THREE.Vector3();
    let scared = false;
    for (const d of this.list) {
      f.set(0, 0, 0);
      d.wander += rand(-1.5, 1.5) * dt;
      f.x += Math.cos(d.wander) * 0.4;
      f.z += Math.sin(d.wander) * 0.4;
      tmp.subVectors(center, d.pos).multiplyScalar(0.25);
      f.add(tmp);
      for (const o of this.list) {
        if (o === d) continue;
        tmp.subVectors(d.pos, o.pos);
        const l = tmp.length();
        if (l < 0.5 && l > 0.001) f.add(tmp.multiplyScalar((0.5 - l) * 6 / l));
      }
      tmp.subVectors(d.pos, player);
      tmp.y = 0;
      const dist = tmp.length();
      if (poleActive && dist < 7) {
        // flee from the waving pole, mostly along the direction the player faces
        tmp.normalize().multiplyScalar(4 * (7 - dist) / 7);
        tmp.addScaledVector(forward, 2 * (7 - dist) / 7);
        f.add(tmp);
        scared = true;
      } else if (dist < 1.2) {
        f.add(tmp.normalize().multiplyScalar(2));
      }
      if (this.whistleT > 0 && dist > 2) {
        tmp.subVectors(player, d.pos);
        tmp.y = 0;
        f.add(tmp.normalize().multiplyScalar(2.2));
      }
      d.vel.addScaledVector(f, dt * 2);
      const maxV = poleActive && dist < 7 ? 2.6 : this.whistleT > 0 ? 2.0 : 0.7;
      d.vel.multiplyScalar(0.92);
      if (d.vel.length() > maxV) d.vel.setLength(maxV);
      d.pos.addScaledVector(d.vel, dt);
      d.pos.x = clamp(d.pos.x, -WORLD_HALF, WORLD_HALF);
      d.pos.z = clamp(d.pos.z, -WORLD_HALF, WORLD_HALF);
      const inPen = d.pos.x > DUCK_PEN.x0 - 0.3 && d.pos.x < DUCK_PEN.x1 && d.pos.z > DUCK_PEN.z0 && d.pos.z < DUCK_PEN.z1;
      if (!penOpen && inPen) {
        d.pos.x = clamp(d.pos.x, DUCK_PEN.x0 + 0.2, DUCK_PEN.x1 - 0.2);
        d.pos.z = clamp(d.pos.z, DUCK_PEN.z0 + 0.2, DUCK_PEN.z1 - 0.2);
      }
      for (const b of BLOCKERS) {
        if (d.pos.x > b.x0 && d.pos.x < b.x1 && d.pos.z > b.z0 && d.pos.z < b.z1) d.pos.addScaledVector(d.vel, -dt * 1.5);
      }
      const gy = baseGroundY(d.pos.x, d.pos.z);
      const swim = gy < -0.2;
      d.mesh.position.set(d.pos.x, (swim ? Math.max(gy, -0.3) + 0.02 : gy) + Math.sin(time * 6 + d.wander) * 0.015, d.pos.z);
      if (d.vel.lengthSq() > 0.01) d.mesh.rotation.y = Math.atan2(d.vel.x, d.vel.z);
    }
    this.quackT -= dt * (scared ? 4 : 1);
    if (this.quackT <= 0) {
      this.quackT = rand(2, 6);
      const near = this.list.some(d => d.pos.distanceTo(player) < 15);
      if (near) sfx.quack();
    }
  }
}
