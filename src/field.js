// The paddy: the three GDD parameters (mud texture, water level,
// nutrient & pest index) plus the rice clumps planted in it.
import * as THREE from 'three';
import { FIELD, STAKES } from './layout.js';
import { clamp, lerp } from './util.js';

const N = 8; // soil grid: 8 x 8 cells of 2 m
const CELL = 2;
const MAX_CLUMPS = 700;
const WATER_VIS = 0.02;
const tmpC = new THREE.Color(); // metres of visual water per cm (exaggerated so 3–5 cm reads on screen)

function clumpGeometry() {
  const pos = [];
  const blades = 11;
  for (let i = 0; i < blades; i++) {
    const a = (i / blades) * Math.PI * 2 + Math.random() * 0.5;
    const lean = 0.12 + Math.random() * 0.22;
    const h = 0.75 + Math.random() * 0.3;
    const w = 0.022;
    const bx = Math.cos(a) * 0.03, bz = Math.sin(a) * 0.03;
    const mx = bx + Math.cos(a) * lean * h * 0.4, mz = bz + Math.sin(a) * lean * h * 0.4;
    const tx = bx + Math.cos(a) * lean * h, tz = bz + Math.sin(a) * lean * h;
    const px = -Math.sin(a) * w, pz = Math.cos(a) * w;
    pos.push(bx - px, 0, bz - pz, bx + px, 0, bz + pz, mx + px * 0.7, h * 0.55, mz + pz * 0.7);
    pos.push(bx - px, 0, bz - pz, mx + px * 0.7, h * 0.55, mz + pz * 0.7, mx - px * 0.7, h * 0.55, mz - pz * 0.7);
    pos.push(mx - px * 0.7, h * 0.55, mz - pz * 0.7, mx + px * 0.7, h * 0.55, mz + pz * 0.7, tx, h, tz);
  }
  const g = new THREE.BufferGeometry();
  g.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
  g.computeVertexNormals();
  return g;
}

function panicleGeometry() {
  const pos = [];
  for (let i = 0; i < 6; i++) {
    const a = (i / 6) * Math.PI * 2;
    const r0 = 0.05, r1 = 0.22;
    const x0 = Math.cos(a) * r0, z0 = Math.sin(a) * r0;
    const x1 = Math.cos(a) * r1, z1 = Math.sin(a) * r1;
    const px = -Math.sin(a) * 0.03, pz = Math.cos(a) * 0.03;
    pos.push(x0 - px, 0.95, z0 - pz, x0 + px, 0.95, z0 + pz, x1, 0.68, z1);
  }
  const g = new THREE.BufferGeometry();
  g.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
  g.computeVertexNormals();
  return g;
}

export class Field {
  constructor(scene) {
    this.till = new Float32Array(N * N);
    this.smooth = new Float32Array(N * N);
    this.water = 0; // cm
    this.gateOpen = false;
    this.drainOpen = false;
    this.nutrient = 0.5;
    this.pest = 0.1;
    this.weeds = 0;
    this.health = 1;
    this.growthDay = 0;
    this.aesthetic = 0;
    this.duckBonus = 0;
    this.clumps = []; // {x, z, rot, cut}
    this.eggs = STAKES.map(() => false);

    const geo = new THREE.PlaneGeometry(16, 16, 32, 32);
    geo.rotateX(-Math.PI / 2);
    const n = geo.attributes.position.count;
    geo.setAttribute('color', new THREE.Float32BufferAttribute(new Float32Array(n * 3), 3));
    this.noise = new Float32Array(n).map(() => Math.random());
    this.soilGeo = geo;
    this.soil = new THREE.Mesh(geo, new THREE.MeshLambertMaterial({ vertexColors: true }));
    this.soil.position.set(0, FIELD.y, 0);
    this.soil.receiveShadow = true;
    scene.add(this.soil);

    this.waterMesh = new THREE.Mesh(new THREE.PlaneGeometry(16, 16),
      new THREE.MeshPhongMaterial({ color: 0x8aa59a, transparent: true, opacity: 0.5, shininess: 120, specular: 0x888888 }));
    this.waterMesh.rotation.x = -Math.PI / 2;
    this.waterMesh.visible = false;
    scene.add(this.waterMesh);

    this.rice = new THREE.InstancedMesh(clumpGeometry(), new THREE.MeshLambertMaterial({ side: THREE.DoubleSide }), MAX_CLUMPS);
    this.rice.count = 0;
    this.rice.frustumCulled = false;
    this.panicles = new THREE.InstancedMesh(panicleGeometry(), new THREE.MeshLambertMaterial({ side: THREE.DoubleSide, color: 0xd9b84a }), MAX_CLUMPS);
    this.panicles.count = 0;
    this.panicles.frustumCulled = false;
    scene.add(this.rice, this.panicles);

    const weedGeo = new THREE.ConeGeometry(0.15, 0.4, 4);
    this.weedMesh = new THREE.InstancedMesh(weedGeo, new THREE.MeshLambertMaterial({ color: 0x4f7a2a }), 80);
    this.weedPos = Array.from({ length: 80 }, () => [lerp(-7.6, 7.6, Math.random()), lerp(-7.6, 7.6, Math.random())]);
    scene.add(this.weedMesh);

    this.soilDirty = true;
    this.riceDirty = true;
  }

  cellAt(x, z) {
    const i = Math.floor((x - FIELD.x0) / CELL), j = Math.floor((z - FIELD.z0) / CELL);
    if (i < 0 || j < 0 || i >= N || j >= N) return -1;
    return j * N + i;
  }

  cellCenter(idx) {
    return [FIELD.x0 + (idx % N) * CELL + 1, FIELD.z0 + Math.floor(idx / N) * CELL + 1];
  }

  avgTill() { return this.till.reduce((a, b) => a + b, 0) / this.till.length; }
  avgSmooth() { return this.smooth.reduce((a, b) => a + b, 0) / this.smooth.length; }
  isWet() { return this.water >= 0.5; }
  prepDone() { return this.avgTill() >= 0.9 && this.avgSmooth() >= 0.85; }

  // Hoe one cell. Returns how hard the soil was (0..1) so the caller can
  // charge stamina, or -1 if out of the field.
  hoe(x, z) {
    const idx = this.cellAt(x, z);
    if (idx < 0) return -1;
    const hard = this.isWet() ? 0.25 : 1;
    const amt = this.isWet() ? 0.4 : 0.26;
    this.till[idx] = Math.min(1, this.till[idx] + amt);
    const i = idx % N, j = Math.floor(idx / N);
    for (const [di, dj] of [[1, 0], [-1, 0], [0, 1], [0, -1]]) {
      const ii = i + di, jj = j + dj;
      if (ii >= 0 && jj >= 0 && ii < N && jj < N) this.till[jj * N + ii] = Math.min(1, this.till[jj * N + ii] + amt * 0.15);
    }
    this.soilDirty = true;
    return hard;
  }

  // Drag the wooden harrow over the cell under the player.
  harrow(x, z, dist) {
    const idx = this.cellAt(x, z);
    if (idx < 0) return 'out';
    if (this.water < 1) return 'dry';
    if (this.till[idx] < 0.6) return 'untilled';
    this.smooth[idx] = Math.min(1, this.smooth[idx] + dist * 0.5);
    this.soilDirty = true;
    return 'ok';
  }

  // Continuous water dynamics. dtMin = game minutes elapsed.
  update(dtMin, env) {
    let dw = 0;
    if (this.gateOpen && env.canalFull) dw += 0.06 * dtMin;
    if (this.drainOpen) dw -= 0.06 * dtMin;
    if (env.raining) dw += 0.035 * dtMin;
    dw -= 0.0035 * env.sun * dtMin;
    const cap = this.gateOpen && env.canalFull ? Math.max(this.water, 10) : 20;
    this.water = clamp(this.water + dw, 0, cap);
    if (this.water < 0.3 && this.avgSmooth() < 0.85) {
      // soil dries back out slowly if left without water before planting
      for (let i = 0; i < this.smooth.length; i++) this.smooth[i] = Math.max(0, this.smooth[i] - 0.0004 * dtMin * env.sun);
    }
  }

  plant(x, z) {
    if (this.clumps.length >= MAX_CLUMPS) return;
    this.clumps.push({ x, z, rot: Math.random() * Math.PI * 2, cut: false });
    this.riceDirty = true;
  }

  plantedCount() { return this.clumps.length; }
  cutCount() { return this.clumps.reduce((a, c) => a + (c.cut ? 1 : 0), 0); }
  isRipe() { return this.growthDay >= 8; }

  // Cut up to `max` clumps within radius r of (x, z). Returns how many.
  cutNear(x, z, r, max) {
    let n = 0;
    for (const c of this.clumps) {
      if (c.cut) continue;
      const dx = c.x - x, dz = c.z - z;
      if (dx * dx + dz * dz < r * r) {
        c.cut = true;
        n++;
        if (n >= max) break;
      }
    }
    if (n) this.riceDirty = true;
    return n;
  }

  applyAsh(withDew) {
    this.pest = Math.max(0, this.pest - (withDew ? 0.35 : 0.08));
    this.riceDirty = true;
  }

  fertilize() {
    this.nutrient = Math.min(1, this.nutrient + 0.25);
  }

  // Yield in kg for one clump at harvest time.
  kgPerClump() {
    return 0.25 * this.health * (1 + 0.15 * this.aesthetic) * (1 + this.duckBonus) * (0.9 + 0.2 * this.nutrient);
  }

  // Once per in-game day while rice is in the field.
  dailyCare({ ducksInField }) {
    const msgs = [];
    this.growthDay++;
    const w = this.water;
    if (w > 7) { this.health -= 0.08; msgs.push(['bad', `Nước ngập ${w.toFixed(1)} cm — ngập bẹ, lúa bắt đầu thối!`]); }
    else if (w < 1) { this.weeds = Math.min(1, this.weeds + 0.25); this.health -= 0.05; msgs.push(['bad', 'Ruộng cạn nứt nẻ — cỏ dại mọc lấn lúa!']); }
    else if (w >= 3 && w <= 5) this.health += 0.02;

    const heading = this.growthDay >= 5 && this.growthDay < 8;
    let pestGrowth = 0.09 * (1.25 - 0.5 * this.aesthetic);
    if (ducksInField && this.growthDay < 5) {
      pestGrowth -= 0.18;
      this.weeds = Math.max(0, this.weeds - 0.25);
      this.eggs = this.eggs.map(e => e && Math.random() < 0.4);
      this.duckBonus = Math.min(0.08, this.duckBonus + 0.02);
      msgs.push(['good', 'Đàn vịt đã sục bùn, ăn ốc non và cỏ dại.']);
    }
    if (ducksInField && heading) {
      this.health -= 0.1;
      msgs.push(['bad', 'Vịt rỉa mất bông lúa đang trổ! Lùa vịt ra kênh.']);
    }
    this.pest = clamp(this.pest + pestGrowth, 0, 1);
    if (this.pest > 0.4) this.health -= (this.pest - 0.4) * 0.25;
    const eggCount = this.eggs.filter(Boolean).length;
    if (eggCount) { this.health -= eggCount * 0.015; msgs.push(['warn', `${eggCount} ổ trứng ốc bươu vàng chưa bóc — ốc con đang cắn lúa.`]); }
    this.eggs = this.eggs.map(e => e || Math.random() < 0.35);
    this.health -= this.weeds * 0.04;
    this.health += (this.nutrient - 0.5) * 0.04;
    this.nutrient = Math.max(0, this.nutrient - 0.04);
    this.health = clamp(this.health, 0.2, 1);
    if (this.growthDay === 5) msgs.push(['info', 'Lúa bắt đầu trổ bông — cấm thả vịt vào ruộng!']);
    if (this.growthDay === 8) msgs.push(['good', 'Lúa chín vàng! Cầm liềm (phím 5) ra gặt.']);
    this.riceDirty = true;
    return msgs;
  }

  refreshVisuals() {
    if (this.soilDirty) this.updateSoil();
    if (this.riceDirty) this.updateRice();
    this.waterMesh.visible = this.water > 0.15;
    this.waterMesh.position.y = FIELD.y + 0.01 + this.water * WATER_VIS;
    this.waterMesh.material.opacity = clamp(0.25 + this.water * 0.06, 0.25, 0.75);
  }

  updateSoil() {
    this.soilDirty = false;
    const pos = this.soilGeo.attributes.position;
    const col = this.soilGeo.attributes.color;
    for (let v = 0; v < pos.count; v++) {
      const x = pos.getX(v), z = pos.getZ(v);
      const idx = this.cellAt(clamp(x, -7.99, 7.99), clamp(z, -7.99, 7.99));
      const t = this.till[idx], s = this.smooth[idx], nz = this.noise[v];
      const crack = t < 0.5 && nz > 0.72;
      let r = lerp(0.66, 0.4, t), g = lerp(0.54, 0.29, t), b = lerp(0.38, 0.18, t);
      if (crack) { r *= 0.6; g *= 0.6; b *= 0.6; }
      r = lerp(r, 0.26, s); g = lerp(g, 0.2, s); b = lerp(b, 0.13, s);
      tmpC.setRGB(r, g, b, THREE.SRGBColorSpace);
      col.setXYZ(v, tmpC.r, tmpC.g, tmpC.b);
      const edge = Math.abs(x) > 7.9 || Math.abs(z) > 7.9;
      const y = edge ? 0 : (1 - s) * (t < 0.5 ? (crack ? -0.03 : nz * 0.03) : nz * 0.1 * t);
      pos.setY(v, y);
    }
    pos.needsUpdate = true;
    col.needsUpdate = true;
    this.soilGeo.computeVertexNormals();
  }

  updateRice() {
    this.riceDirty = false;
    const m = new THREE.Matrix4(), q = new THREE.Quaternion(), s = new THREE.Vector3(), p = new THREE.Vector3();
    const up = new THREE.Vector3(0, 1, 0);
    const c = new THREE.Color();
    const g = this.growthDay;
    const grow = 0.32 + 0.68 * clamp(g / 5, 0, 1);
    const ripe = clamp((g - 5) / 3, 0, 1);
    const sick = 1 - this.health;
    const yellow = clamp(this.pest - 0.3, 0, 0.7) + sick * 0.5;
    let pi = 0;
    this.clumps.forEach((cl, i) => {
      q.setFromAxisAngle(up, cl.rot);
      p.set(cl.x, FIELD.y, cl.z);
      if (cl.cut) {
        s.set(0.8, 0.18, 0.8);
        c.setRGB(0.78, 0.68, 0.42, THREE.SRGBColorSpace);
      } else {
        s.set(grow, grow, grow);
        c.setRGB(lerp(0.36, 0.85, ripe), lerp(0.62, 0.68, ripe), lerp(0.2, 0.22, ripe), THREE.SRGBColorSpace);
        c.lerp(new THREE.Color().setRGB(0.7, 0.6, 0.3, THREE.SRGBColorSpace), yellow * (1 - ripe));
        if (g >= 5) {
          m.compose(p, q, new THREE.Vector3(grow, grow * (1 - ripe * 0.1), grow));
          this.panicles.setMatrixAt(pi, m);
          this.panicles.setColorAt(pi, new THREE.Color().setRGB(lerp(0.55, 0.88, ripe), lerp(0.66, 0.66, ripe), lerp(0.3, 0.2, ripe), THREE.SRGBColorSpace));
          pi++;
        }
      }
      m.compose(p, q, s);
      this.rice.setMatrixAt(i, m);
      this.rice.setColorAt(i, c);
    });
    this.rice.count = this.clumps.length;
    this.panicles.count = pi;
    this.rice.instanceMatrix.needsUpdate = true;
    if (this.rice.instanceColor) this.rice.instanceColor.needsUpdate = true;
    this.panicles.instanceMatrix.needsUpdate = true;
    if (this.panicles.instanceColor) this.panicles.instanceColor.needsUpdate = true;

    const nWeeds = Math.round(this.weeds * 80);
    for (let i = 0; i < 80; i++) {
      const [x, z] = this.weedPos[i];
      m.makeScale(i < nWeeds ? 1 : 0.0001, i < nWeeds ? 1 : 0.0001, i < nWeeds ? 1 : 0.0001);
      m.setPosition(x, FIELD.y + 0.15, z);
      this.weedMesh.setMatrixAt(i, m);
    }
    this.weedMesh.instanceMatrix.needsUpdate = true;
  }
}
