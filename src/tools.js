// Hand-held tools rendered in front of the camera, with simple swing
// animations so every action has a physical "weight".
import * as THREE from 'three';
import { mat } from './world.js';

export const TOOLS = [
  { id: 'tay', key: '1', name: 'Tay không', en: 'Hands' },
  { id: 'cuoc', key: '2', name: 'Cuốc', en: 'Hoe' },
  { id: 'bua', key: '3', name: 'Bừa gỗ', en: 'Harrow' },
  { id: 'gau', key: '4', name: 'Gàu sòng', en: 'Scoop' },
  { id: 'liem', key: '5', name: 'Liềm', en: 'Sickle' },
  { id: 'cao', key: '6', name: 'Cào gỗ', en: 'Rake' },
  { id: 'sao', key: '7', name: 'Sào vịt', en: 'Duck pole' },
];

const WOOD = 0x8a6236, BAMBOO = 0xc9b27a, IRON = 0x6d6d6d, SKIN = 0xc99a74;

function part(g, geo, color, x, y, z, rx = 0, ry = 0, rz = 0) {
  const m = new THREE.Mesh(geo, mat(color));
  m.position.set(x, y, z);
  m.rotation.set(rx, ry, rz);
  g.add(m);
  return m;
}

function build() {
  const t = {};
  t.tay = new THREE.Group();

  t.cuoc = new THREE.Group();
  part(t.cuoc, new THREE.CylinderGeometry(0.02, 0.022, 1.0, 6), WOOD, 0, 0.1, -0.15, -1.1);
  part(t.cuoc, new THREE.BoxGeometry(0.2, 0.02, 0.24), IRON, 0, 0.38, -0.62, -0.5);

  t.bua = new THREE.Group();
  part(t.bua, new THREE.BoxGeometry(0.9, 0.07, 0.07), WOOD, -0.3, -0.25, -0.75);
  for (let i = 0; i < 8; i++) part(t.bua, new THREE.BoxGeometry(0.025, 0.18, 0.025), WOOD, -0.7 + i * 0.115, -0.36, -0.75);
  part(t.bua, new THREE.CylinderGeometry(0.02, 0.02, 0.6, 5), BAMBOO, -0.05, -0.05, -0.5, 1.0);
  part(t.bua, new THREE.CylinderGeometry(0.02, 0.02, 0.6, 5), BAMBOO, -0.55, -0.05, -0.5, 1.0);

  t.gau = new THREE.Group();
  part(t.gau, new THREE.CylinderGeometry(0.22, 0.12, 0.25, 8, 1, true), BAMBOO, 0, -0.05, -0.6, 1.3);
  part(t.gau, new THREE.CylinderGeometry(0.015, 0.015, 0.9, 5), BAMBOO, 0, 0.15, -0.25, -0.9);

  t.liem = new THREE.Group();
  part(t.liem, new THREE.CylinderGeometry(0.02, 0.022, 0.22, 6), WOOD, 0, -0.05, -0.1, 0, 0, 0.3);
  part(t.liem, new THREE.TorusGeometry(0.16, 0.012, 4, 16, Math.PI * 1.2), IRON, -0.12, 0.08, -0.12, 0, 0, 0.6);

  t.cao = new THREE.Group();
  part(t.cao, new THREE.CylinderGeometry(0.018, 0.018, 1.6, 6), WOOD, 0, 0, -0.5, -1.25);
  part(t.cao, new THREE.BoxGeometry(0.55, 0.05, 0.06), WOOD, 0, -0.3, -1.25);
  for (let i = 0; i < 7; i++) part(t.cao, new THREE.BoxGeometry(0.02, 0.1, 0.02), WOOD, -0.24 + i * 0.08, -0.36, -1.25);

  t.sao = new THREE.Group();
  part(t.sao, new THREE.CylinderGeometry(0.018, 0.025, 2.6, 6), BAMBOO, 0, 0.5, -1.0, -0.7);
  t.streamers = [];
  for (let i = 0; i < 4; i++) {
    const s = part(t.sao, new THREE.PlaneGeometry(0.05, 0.5), [0xe84a4a, 0x4ae8c0, 0xf0e04a, 0x4a8ae8][i], 0, 1.35, -1.95 + i * 0.03);
    s.material = new THREE.MeshLambertMaterial({ color: s.material.color, side: THREE.DoubleSide });
    t.streamers.push(s);
  }

  // Left hand holding a bundle of seedlings (bó mạ) during transplanting
  t.boMa = new THREE.Group();
  part(t.boMa, new THREE.CylinderGeometry(0.05, 0.04, 0.3, 6), 0x7cc04a, 0, 0.1, 0);
  part(t.boMa, new THREE.CylinderGeometry(0.052, 0.052, 0.04, 6), 0xc9b27a, 0, 0.0, 0);
  part(t.boMa, new THREE.BoxGeometry(0.09, 0.07, 0.15), SKIN, 0, -0.05, 0.05);

  // Đòn gánh with two loads of sheaves, shown when carrying
  t.ganh = new THREE.Group();
  part(t.ganh, new THREE.CylinderGeometry(0.02, 0.02, 1.6, 5), BAMBOO, 0, 0, 0, 0, 0, Math.PI / 2);
  t.ganhLoads = [part(t.ganh, new THREE.ConeGeometry(0.25, 0.5, 6), 0xd8b24a, -0.75, -0.35, 0, Math.PI), part(t.ganh, new THREE.ConeGeometry(0.25, 0.5, 6), 0xd8b24a, 0.75, -0.35, 0, Math.PI)];
  return t;
}

export class Tools {
  constructor(camera) {
    this.root = new THREE.Group();
    this.root.position.set(0.32, -0.32, -0.45);
    camera.add(this.root);
    this.models = build();
    for (const id of TOOLS.map(t => t.id)) {
      this.models[id].visible = false;
      this.root.add(this.models[id]);
    }
    this.models.boMa.position.set(-0.62, 0.0, -0.2);
    this.models.boMa.visible = false;
    this.root.add(this.models.boMa);
    this.models.ganh.position.set(-0.32, 0.05, 0.25);
    this.models.ganh.visible = false;
    this.root.add(this.models.ganh);
    this.current = 'tay';
    this.models.tay.visible = true;
    this.swingT = 0;
    this.swingDur = 0;
    this.impactAt = 0;
    this.onImpact = null;
    this.style = 'chop';
    this.wave = 0;
  }

  select(id) {
    if (!this.models[id] || this.swingT > 0) return;
    this.models[this.current].visible = false;
    this.current = id;
    this.models[id].visible = true;
  }

  busy() { return this.swingT > 0; }

  // style: 'chop' (hoe), 'slash' (sickle), 'scoop' (bucket), 'pull' (rake), 'beat' (threshing)
  swing(dur, impactFrac, style, cb) {
    if (this.swingT > 0) return false;
    this.swingDur = dur;
    this.swingT = dur;
    this.impactAt = dur * (1 - impactFrac);
    this.onImpact = cb;
    this.style = style;
    return true;
  }

  update(dt, { moving, bob, time, waving, carrying }) {
    const m = this.models[this.current];
    let rx = 0, ry = 0, rz = 0, px = 0, py = 0, pz = 0;
    if (this.swingT > 0) {
      const prev = this.swingT;
      this.swingT = Math.max(0, this.swingT - dt);
      if (prev > this.impactAt && this.swingT <= this.impactAt && this.onImpact) {
        const cb = this.onImpact;
        this.onImpact = null;
        cb();
      }
      const k = 1 - this.swingT / this.swingDur; // 0..1
      const up = k < 0.45 ? k / 0.45 : 1 - (k - 0.45) / 0.55;
      const down = k < 0.45 ? 0 : Math.sin(((k - 0.45) / 0.55) * Math.PI);
      if (this.style === 'chop') { rx = up * 1.4 - down * 0.5; py = up * 0.15 - down * 0.1; }
      else if (this.style === 'slash') { ry = up * 0.9 - down * 1.6; rz = -down * 0.4; px = -down * 0.25; }
      else if (this.style === 'scoop') { rx = -down * 1.0 + up * 0.6; py = up * 0.2; }
      else if (this.style === 'pull') { pz = up * -0.35 + down * 0.25; }
      else if (this.style === 'beat') { rx = up * 1.6 - down * 0.4; py = up * 0.2; }
    }
    if (waving) {
      this.wave += dt * 9;
      rz = Math.sin(this.wave) * 0.5;
    }
    if (this.models.streamers) {
      this.models.streamers.forEach((s, i) => { s.rotation.y = Math.sin(time * 8 + i) * 0.8 + (waving ? Math.sin(this.wave * 1.3 + i) : 0); });
    }
    const sway = moving ? Math.sin(bob) * 0.02 : Math.sin(time * 1.5) * 0.005;
    m.rotation.set(rx, ry, rz);
    m.position.set(px + sway, py + Math.abs(sway), pz);
    this.models.ganh.visible = carrying > 0;
    this.models.ganhLoads.forEach(l => l.scale.setScalar(0.4 + 0.6 * carrying));
  }
}
