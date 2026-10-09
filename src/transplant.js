// Mini-game "Cấy lúa": a rhythm track that follows the backward steps of
// transplanting. Space = lùi 1 bước, A / S / D = cắm trái / giữa / phải.
import * as THREE from 'three';
import { FIELD } from './layout.js';
import { gauss, clamp } from './util.js';
import { sfx } from './audio.js';

const LANES = 8;
const LANE_W = 2;
const ROW_STEP = 0.6;
const ROWS = 26;
const SPREAD = [-0.6, 0, 0.6];
const BEAT = 0.5; // seconds per beat
const KEYS = ['Space', 'KeyA', 'KeyS', 'KeyD'];
const LABELS = ['Lùi', 'Trái', 'Giữa', 'Phải'];
const KEYCAPS = ['␣', 'A', 'S', 'D'];
const PERFECT = 0.07, GOOD = 0.16, WINDOW = 0.26;

export class Transplant {
  constructor({ scene, field, player, tools, hud, onFinish }) {
    Object.assign(this, { scene, field, player, tools, hud, onFinish });
    this.el = document.getElementById('rhythm');
    this.track = document.getElementById('rhythm-track');
    this.info = document.getElementById('rhythm-info');
    this.active = false;
    // faint guide lines under the mud (vạch căn hàng)
    const pts = [];
    for (let l = 0; l < LANES; l++) for (const s of SPREAD) {
      const x = FIELD.x0 + LANE_W * (l + 0.5) + s;
      pts.push(x, FIELD.y + 0.02, FIELD.z0 + 0.3, x, FIELD.y + 0.02, FIELD.z1 - 0.3);
    }
    const g = new THREE.BufferGeometry();
    g.setAttribute('position', new THREE.Float32BufferAttribute(pts, 3));
    this.guides = new THREE.LineSegments(g, new THREE.LineBasicMaterial({ color: 0xf5e6b8, transparent: true, opacity: 0.25 }));
    this.guides.visible = false;
    scene.add(this.guides);
    this.errors = []; // lateral error (m) of every clump the player planted; null = missed
  }

  start() {
    this.active = true;
    this.lane = 0;
    this.guides.visible = true;
    this.el.hidden = false;
    this.player.frozen = true;
    this.tools.models.boMa.visible = true;
    this.beginLane();
  }

  laneX(l) { return FIELD.x0 + LANE_W * (l + 0.5); }

  beginLane() {
    this.row = -1;
    this.rowZ = FIELD.z1 - 0.5 + ROW_STEP; // first "lùi" brings us to row 0
    this.waiting = false;
    this.t = -1.5; // count-in
    this.notes = [];
    for (let r = 0; r < ROWS; r++) for (let k = 0; k < 4; k++) {
      const div = document.createElement('div');
      div.className = 'note n' + k;
      div.innerHTML = `<b>${KEYCAPS[k]}</b><span>${LABELS[k]}</span>`;
      this.track.appendChild(div);
      this.notes.push({ time: (r * 4 + k) * BEAT, k, row: r, done: false, div });
    }
    this.next = 0;
    this.placeCamera(true);
    this.info.textContent = `Làn ${this.lane + 1}/${LANES} — bấm theo nhịp khi nốt chạm vạch`;
  }

  placeCamera(snap) {
    const x = this.laneX(this.lane);
    this.player.pos.x = x;
    this.player.pos.z = this.rowZ - 0.75;
    this.player.yaw = Math.PI; // facing +z, walking backwards toward -z
    if (snap) this.player.pitch = -0.75;
  }

  judge(note, dt) {
    note.done = true;
    const ad = Math.abs(dt);
    const grade = dt === null ? 'miss' : ad < PERFECT ? 'perfect' : ad < GOOD ? 'good' : 'poor';
    note.div.classList.add(grade);
    if (grade === 'miss') sfx.miss(); else sfx.good();
    if (note.k === 0) {
      // step back; a sloppy step makes uneven row spacing
      const drift = grade === 'miss' ? 0.25 : grade === 'poor' ? 0.12 : grade === 'good' ? 0.04 : 0;
      this.row = note.row;
      this.rowZ -= ROW_STEP + drift * (Math.random() < 0.5 ? -1 : 1);
      this.placeCamera(false);
      if (grade !== 'miss') sfx.squelch();
      return;
    }
    if (grade === 'miss') { this.errors.push(null); return; }
    const sign = Math.sign(dt) || 1;
    const err = grade === 'perfect' ? gauss() * 0.02 : sign * (ad * 1.1 + Math.random() * 0.05);
    const x = this.laneX(this.lane) + SPREAD[note.k - 1] + err;
    const z = this.rowZ + gauss() * (grade === 'perfect' ? 0.02 : 0.06);
    if (z > FIELD.z0 + 0.2) this.field.plant(x, z);
    this.errors.push(err);
    this.tools.swing(0.2, 0.5, 'scoop', () => {});
  }

  key(code) {
    if (!this.active) return false;
    if (this.waiting) {
      if (code === 'Space' && this.lane < LANES - 1) { this.lane++; this.clearNotes(); this.beginLane(); }
      else if (code === 'Enter') this.finish(true);
      return true;
    }
    const k = KEYS.indexOf(code);
    if (k < 0) return code === 'Space' || code === 'Enter';
    // the pending note must match the key and be inside the hit window
    const note = this.notes[this.next];
    if (!note) return true;
    const dt = this.t - note.time;
    if (note.k === k && Math.abs(dt) < WINDOW) { this.judge(note, dt); this.next++; }
    else sfx.miss();
    return true;
  }

  clearNotes() { this.track.querySelectorAll('.note').forEach(n => n.remove()); }

  stats() {
    const planted = this.errors.filter(e => e !== null);
    const rms = planted.length ? Math.sqrt(planted.reduce((a, e) => a + e * e, 0) / planted.length) : 0.2;
    const missRate = this.errors.length ? 1 - planted.length / this.errors.length : 1;
    return { rms, missRate };
  }

  update(dt) {
    if (!this.active || this.waiting) return;
    const prevT = this.t;
    this.t += dt;
    // metronome
    const b0 = Math.floor(prevT / BEAT), b1 = Math.floor(this.t / BEAT);
    if (b1 > b0 && b1 >= 0 && b1 < ROWS * 4) sfx.beat(b1 % 4 === 0);
    // misses
    while (this.next < this.notes.length && this.t - this.notes[this.next].time > WINDOW) {
      this.judge(this.notes[this.next], null);
      this.next++;
    }
    const W = this.track.clientWidth || 600;
    const hitX = 90, pxPerSec = 220;
    for (const n of this.notes) {
      const x = hitX + (n.time - this.t) * pxPerSec;
      if (x < -60 || x > W + 60) { n.div.style.display = 'none'; continue; }
      n.div.style.display = '';
      n.div.style.transform = `translateX(${x - 26}px)`;
    }
    const { rms, missRate } = this.stats();
    this.hud.setRhythmScore(`Độ thẳng hàng: ${Math.round(clamp(1 - rms / 0.25, 0, 1) * 100)}% · Bỏ sót: ${Math.round(missRate * 100)}%`);
    if (this.next >= this.notes.length) {
      this.waiting = true;
      this.info.innerHTML = this.lane < LANES - 1
        ? `Xong làn ${this.lane + 1}! <b>Space</b>: cấy tiếp làn sau · <b>Enter</b>: nhờ hàng xóm "đổi công" cấy nốt`
        : 'Cấy xong cả thửa! Bấm <b>Enter</b>.';
    }
  }

  finish(neighbours) {
    const { rms, missRate } = this.stats();
    if (neighbours) {
      // Đổi công: the village finishes the remaining lanes at the player's pace.
      const sigma = Math.max(0.03, rms);
      for (let l = this.lane + 1; l < LANES; l++) {
        for (let r = 0; r < ROWS; r++) for (const s of SPREAD) {
          if (Math.random() < missRate * 0.5) continue;
          const z = FIELD.z1 - 0.5 - r * ROW_STEP + gauss() * sigma * 0.5;
          if (z < FIELD.z0 + 0.2) continue;
          this.field.plant(this.laneX(l) + s + gauss() * sigma, z);
        }
      }
    }
    const expected = LANES * ROWS * 3;
    const fill = Math.min(1, this.field.plantedCount() / expected);
    const straight = clamp(1 - rms / 0.25, 0, 1);
    this.field.aesthetic = clamp(straight * 0.75 + fill * 0.25, 0, 1);
    this.active = false;
    this.clearNotes();
    this.el.hidden = true;
    this.guides.visible = false;
    this.player.frozen = false;
    this.player.pitch = -0.2;
    this.tools.models.boMa.visible = false;
    this.onFinish({ aesthetic: this.field.aesthetic, planted: this.field.plantedCount(), neighbours });
  }
}
