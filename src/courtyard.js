// "Chạy thóc": paddy spread on the red-brick courtyard to sun-dry, with
// the rake, the tarp and the four corner bricks.
import * as THREE from 'three';
import { COURT, TARP } from './layout.js';
import { clamp, lerp } from './util.js';

const C = COURT.cols, R = COURT.rows;

export class Courtyard {
  constructor(scene) {
    this.mass = new Float32Array(C * R); // kg on each 1 m² cell
    this.moist = new Float32Array(C * R).fill(1); // 1 = fresh from threshing, ≤ 0.14 = dry
    this.soaked = new Float32Array(C * R); // 0..1 rain damage (germination)
    this.total = 0;
    const geo = new THREE.BoxGeometry(0.98, 1, 0.98);
    geo.translate(0, 0.5, 0);
    this.mesh = new THREE.InstancedMesh(geo, new THREE.MeshLambertMaterial(), C * R);
    this.mesh.frustumCulled = false;
    this.mesh.receiveShadow = true;
    scene.add(this.mesh);
    const hl = new THREE.Mesh(new THREE.PlaneGeometry(0.98, 0.98), new THREE.MeshBasicMaterial({ color: 0xffffff, transparent: true, opacity: 0.25, depthWrite: false }));
    hl.rotation.x = -Math.PI / 2;
    hl.visible = false;
    scene.add(hl);
    this.highlight = hl;
    this.refresh();
  }

  cellAt(x, z) {
    const i = Math.floor(x - COURT.x0), j = Math.floor(z - COURT.z0);
    if (i < 0 || j < 0 || i >= C || j >= R) return -1;
    return j * C + i;
  }

  center(idx) { return [COURT.x0 + (idx % C) + 0.5, COURT.z0 + Math.floor(idx / C) + 0.5]; }

  covered(idx, tarpOn) {
    if (!tarpOn) return false;
    const [x, z] = this.center(idx);
    return x > TARP.x0 && x < TARP.x1 && z > TARP.z0 && z < TARP.z1;
  }

  pour(kg) {
    // dumped as one heap in the middle of the yard
    const heap = [this.cellAt(-0.5, -17.5), this.cellAt(0.5, -17.5), this.cellAt(-0.5, -16.5), this.cellAt(0.5, -16.5)];
    for (const i of heap) this.mass[i] += kg / heap.length;
    this.total += kg;
    this.refresh();
  }

  neighbours(idx) {
    const i = idx % C, j = Math.floor(idx / C), out = [];
    for (let dj = -1; dj <= 1; dj++) for (let di = -1; di <= 1; di++) {
      if (!di && !dj) continue;
      const ii = i + di, jj = j + dj;
      if (ii >= 0 && jj >= 0 && ii < C && jj < R) out.push(jj * C + ii);
    }
    return out;
  }

  // Mix moisture/damage when paddy moves between cells.
  move(from, to, kg) {
    if (kg <= 0) return;
    const m0 = this.mass[to];
    const tot = m0 + kg;
    this.moist[to] = (this.moist[to] * m0 + this.moist[from] * kg) / tot;
    this.soaked[to] = (this.soaked[to] * m0 + this.soaked[from] * kg) / tot;
    this.mass[to] = tot;
    this.mass[from] -= kg;
  }

  // Rake outward: level the cell with its neighbours (rải mỏng).
  spread(idx) {
    if (idx < 0 || this.mass[idx] < 0.05) return false;
    const nb = this.neighbours(idx);
    const share = this.mass[idx] * 0.6 / nb.length;
    for (const n of nb) this.move(idx, n, share);
    this.refresh();
    return true;
  }

  // Rake inward: pull neighbours onto this cell (vun đống).
  gather(idx) {
    if (idx < 0) return false;
    let moved = false;
    for (const n of this.neighbours(idx)) {
      if (this.mass[n] > 0.01) { this.move(n, idx, this.mass[n] * 0.65); moved = true; }
    }
    this.refresh();
    return moved;
  }

  update(dtMin, { sun, raining, tarpOn }) {
    let changed = false;
    for (let i = 0; i < this.mass.length; i++) {
      const m = this.mass[i];
      if (m < 0.02) continue;
      const cov = this.covered(i, tarpOn);
      if (raining && !cov) {
        this.moist[i] = Math.min(1.3, this.moist[i] + 0.02 * dtMin);
        this.soaked[i] = Math.min(1, this.soaked[i] + 0.012 * dtMin);
        changed = true;
      } else if (!raining && !cov && sun > 0.1) {
        const thin = clamp(3 / m, 0.12, 1);
        this.moist[i] = Math.max(0, this.moist[i] - 0.004 * sun * thin * dtMin);
        changed = true;
      }
    }
    if (changed) this.refresh();
  }

  dryFraction() {
    let dry = 0;
    for (let i = 0; i < this.mass.length; i++) if (this.moist[i] <= 0.14) dry += this.mass[i];
    return this.total ? dry / this.total : 0;
  }

  soakedFraction() {
    let s = 0;
    for (let i = 0; i < this.mass.length; i++) s += this.mass[i] * this.soaked[i];
    return this.total ? s / this.total : 0;
  }

  // Share of paddy under the tarp outline (for the rain-rush hint).
  shareInside() {
    let s = 0;
    for (let i = 0; i < this.mass.length; i++) if (this.covered(i, true)) s += this.mass[i];
    return this.total ? s / this.total : 0;
  }

  maxHeight() {
    let h = 0;
    for (let i = 0; i < this.mass.length; i++) if (this.covered(i, true)) h = Math.max(h, this.mass[i] * 0.012);
    return h;
  }

  setHighlight(idx) {
    this.highlight.visible = idx >= 0;
    if (idx >= 0) {
      const [x, z] = this.center(idx);
      this.highlight.position.set(x, 0.03 + this.mass[idx] * 0.012, z);
    }
  }

  refresh() {
    const m = new THREE.Matrix4(), c = new THREE.Color();
    for (let i = 0; i < this.mass.length; i++) {
      const [x, z] = this.center(i);
      const h = this.mass[i] * 0.012;
      m.makeScale(1, Math.max(h, 0.0001), 1);
      m.setPosition(x, 0.015, z);
      this.mesh.setMatrixAt(i, m);
      const wet = clamp(this.moist[i] - 0.14, 0, 1);
      c.setRGB(lerp(0.9, 0.6, wet), lerp(0.74, 0.48, wet), lerp(0.32, 0.2, wet), THREE.SRGBColorSpace);
      c.lerp(new THREE.Color().setRGB(0.45, 0.55, 0.3, THREE.SRGBColorSpace), this.soaked[i] * 0.8);
      this.mesh.setColorAt(i, c);
    }
    this.mesh.instanceMatrix.needsUpdate = true;
    this.mesh.instanceColor.needsUpdate = true;
  }
}
