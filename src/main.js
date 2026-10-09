// Ruộng Lúa Nước — first-person wet-rice farming prototype.
// Game loop, time & weather, interactions and the four-stage rice cycle.
import * as THREE from 'three';
import { initAudio, sfx, setRain, setWind } from './audio.js';
import { buildWorld } from './world.js';
import { Field } from './field.js';
import { Courtyard } from './courtyard.js';
import { Ducks } from './ducks.js';
import { Player } from './player.js';
import { Tools, TOOLS } from './tools.js';
import { Hud } from './hud.js';
import { Transplant } from './transplant.js';
import { FIELD, P, CORNERS, STAKES, DUCK_PEN, inField, inCourt } from './layout.js';
import { clamp, lerp, rand, fmtTime } from './util.js';

const MIN_PER_SEC = 4; // game minutes per real second
const CARRY = 48; // clumps per đòn gánh load (8 lượm × 6 khóm)
const LUOM = 6;
const BUNDLES = 8;
const PARAMS = new URLSearchParams(location.search);
const DEBUG = PARAMS.has('debug');
const LOW = PARAMS.has('low'); // ?low: no shadows, 1x pixels for weak GPUs

// ---------------------------------------------------------------- scene
const renderer = new THREE.WebGLRenderer({ antialias: true, preserveDrawingBuffer: DEBUG });
renderer.setPixelRatio(LOW ? 1 : Math.min(devicePixelRatio, 2));
renderer.setSize(innerWidth, innerHeight);
renderer.shadowMap.enabled = !LOW;
renderer.shadowMap.type = THREE.PCFSoftShadowMap;
document.getElementById('app').appendChild(renderer.domElement);

const scene = new THREE.Scene();
scene.fog = new THREE.Fog(0x9fd3f0, 40, 150);
const camera = new THREE.PerspectiveCamera(72, innerWidth / innerHeight, 0.05, 400);
scene.add(camera);

const hemi = new THREE.HemisphereLight(0xdfefff, 0x5a4a30, 1.0);
scene.add(hemi);
const sun = new THREE.DirectionalLight(0xfff2d8, 2.4);
sun.castShadow = true;
sun.shadow.mapSize.set(2048, 2048);
Object.assign(sun.shadow.camera, { left: -30, right: 30, top: 30, bottom: -30, near: 1, far: 200 });
sun.shadow.bias = -0.0006;
scene.add(sun, sun.target);
const sunDisk = new THREE.Mesh(new THREE.SphereGeometry(5, 16, 12), new THREE.MeshBasicMaterial({ color: 0xfff4c0, fog: false }));
scene.add(sunDisk);

const world = buildWorld(scene);
const field = new Field(scene);
const court = new Courtyard(scene);
const ducks = new Ducks(scene, 10);
const player = new Player(camera);
const tools = new Tools(camera);
const hud = new Hud();

player.pos.set(P.start[0], 0, P.start[1]);

const hoeMark = new THREE.Mesh(new THREE.PlaneGeometry(1.96, 1.96), new THREE.MeshBasicMaterial({ color: 0xffffff, transparent: true, opacity: 0.18, depthWrite: false }));
hoeMark.rotation.x = -Math.PI / 2;
hoeMark.visible = false;
scene.add(hoeMark);

// rain streaks
const RAIN_N = 2500;
const rainPos = new Float32Array(RAIN_N * 6);
for (let i = 0; i < RAIN_N; i++) {
  const x = rand(-25, 25), y = rand(0, 20), z = rand(-25, 25);
  rainPos.set([x, y, z, x + 0.05, y + 0.45, z], i * 6);
}
const rainGeo = new THREE.BufferGeometry();
rainGeo.setAttribute('position', new THREE.BufferAttribute(rainPos, 3));
const rain = new THREE.LineSegments(rainGeo, new THREE.LineBasicMaterial({ color: 0xc8d4e0, transparent: true, opacity: 0.55 }));
rain.visible = false;
rain.frustumCulled = false;
scene.add(rain);

// kitchen smoke (khói lam chiều)
const smoke = [];
for (let i = 0; i < 18; i++) {
  const s = new THREE.Mesh(new THREE.SphereGeometry(0.25, 8, 6), new THREE.MeshLambertMaterial({ color: 0xd8d8d8, transparent: true, opacity: 0 }));
  s.userData.t = Math.random() * 4;
  scene.add(s);
  smoke.push(s);
}

// ---------------------------------------------------------------- state
const G = {
  minutes: 6 * 60,
  get day() { return Math.floor(this.minutes / 1440) + 1; },
  get hour() { return (this.minutes % 1440) / 60; },
  stage: 'prep', // prep → care → harvest → drying → done
  mode: 'walk', // walk | transplant | summary
  playing: false,
  paused: false,
  realT: 0,
  inv: { ash: 3, cam: 4, beo: 0, beoBam: 0, chao: 0, fert: 0, eggs: 0, bricks: 0, sheaves: 0 },
  nursery: { state: 'none', soakDay: 0, waterDays: 0, lastWater: -1, bundles: 0 },
  canalFull: true,
  pig: { fed: false }, slurry: 0, smokeT: 0,
  duckPenOpen: false, duckEggs: 2, duckFieldMin: 0, duckForageMin: 0, eggsCollected: 0,
  barrel: { sheaves: 0, paddy: 0 },
  tarp: { on: false, placed: [false, false, false, false], blowT: 0 },
  storm: { phase: 'none', t: 0, level: 0, lightning: 0, nextBolt: 3 },
  rainAt: Infinity,
  raining: false,
  shake: 0,
  eHeld: false, eTimer: 0,
  mouse: { left: false, right: false },
  keys: {},
  target: null,
};

const transplant = new Transplant({
  scene, field, player, tools, hud,
  onFinish: ({ aesthetic, planted, neighbours }) => {
    G.mode = 'walk';
    G.stage = 'care';
    G.nursery.state = 'done';
    field.growthDay = 0;
    field.riceDirty = true;
    hud.log(`Cấy xong ${planted} khóm lúa${neighbours ? ' (có hàng xóm đổi công)' : ''}. Thẩm mỹ đồng ruộng: ${Math.round(aesthetic * 100)}% → +${Math.round(aesthetic * 15)}% sản lượng.`, 'good');
    hud.log('Giai đoạn 3: giữ nước 3–5 cm, trị sâu, bóc trứng ốc. Nằm võng để qua ngày.', 'info');
  },
});

// ---------------------------------------------------------------- interactions
const near = (x, z) => ({ x, z });
const interactables = [
  {
    ...near(...P.gate), r: 2.2,
    label: () => (field.gateOpen ? 'Đóng cửa cống (xẻng)' : 'Mở cửa cống dẫn nước từ mương (xẻng)'),
    act: () => {
      field.gateOpen = !field.gateOpen;
      sfx.thud(false);
      if (field.gateOpen) sfx.splash();
      if (field.gateOpen && !G.canalFull) hud.log('Kênh đang cạn, nước không chảy vào. Đứng ở bờ tây, cầm gàu sòng (phím 4) để tát.', 'warn');
    },
  },
  {
    ...near(...P.drain), r: 2.2,
    label: () => (field.drainOpen ? 'Đắp lại rãnh xả (xẻng)' : 'Khoét rãnh bờ để xả bớt nước (xẻng)'),
    act: () => { field.drainOpen = !field.drainOpen; sfx.thud(false); if (field.drainOpen) sfx.splash(); },
  },
  {
    ...near(...P.hammock), r: 2.4,
    label: () => (['warning', 'rain'].includes(G.storm.phase) ? null : 'Nằm võng nghỉ đến sáng mai'),
    act: () => sleep(),
  },
  {
    ...near(...P.basket), r: 2,
    label: () => {
      const n = G.nursery;
      if (n.state === 'none') return 'Ngâm thóc giống vào thúng nước ấm, ủ rơm';
      if (n.state === 'soaked') return 'Thóc đang ủ — chờ qua đêm cho nứt nanh';
      return null;
    },
    act: () => {
      const n = G.nursery;
      if (n.state !== 'none') return;
      n.state = 'soaked';
      n.soakDay = G.day;
      sfx.splash();
      hud.log('Đã ngâm thóc giống. Ủ qua đêm (nằm võng) để thóc nứt nanh.', 'good');
    },
  },
  {
    ...near(...P.nursery), r: 2.8,
    repeat: true,
    label: () => {
      const n = G.nursery;
      if (n.state === 'sprouted') return 'Gieo đều tay thóc nứt nanh lên vạt mạ';
      if (n.state === 'sown') return n.lastWater === G.day ? `Mạ đã tưới hôm nay (${n.waterDays}/3 ngày)` : `Tưới nước xăm xắp cho mạ (${n.waterDays}/3 ngày)`;
      if (n.state === 'ready') return `Nhổ mạ, gõ rễ vào mu bàn chân, buộc lạt (${n.bundles}/${BUNDLES} bó)`;
      return null;
    },
    act: () => {
      const n = G.nursery;
      if (n.state === 'sprouted') { n.state = 'sown'; sfx.pickup(); hud.log('Đã gieo mạ. Tưới mỗi ngày, 3 ngày là mạ lên xanh.', 'good'); }
      else if (n.state === 'sown' && n.lastWater !== G.day) { n.lastWater = G.day; n.waterDays++; sfx.splash(); }
      else if (n.state === 'ready' && n.bundles < BUNDLES) {
        if (!spend(4)) return;
        n.bundles++;
        tools.swing(0.35, 0.5, 'beat', () => sfx.thud(false));
        if (n.bundles >= BUNDLES) { n.state = 'pulled'; hud.log('Đủ 8 bó mạ! Gánh ra ruộng, đứng trong ruộng bấm E để cấy.', 'good'); }
      }
      refreshNursery();
    },
  },
  {
    ...near(...P.barrel), r: 2.4,
    repeat: true,
    label: () => {
      if (G.inv.sheaves > 0) return `Đặt ${(G.inv.sheaves / LUOM).toFixed(1)} lượm lúa xuống cạnh thùng`;
      if (G.barrel.sheaves > 0) return `Đập lúa vào thùng (còn ${Math.ceil(G.barrel.sheaves / LUOM)} lượm)`;
      if (G.barrel.paddy > 0 && G.stage === 'harvest') {
        if (field.cutCount() < field.plantedCount()) return `Thùng có ${G.barrel.paddy.toFixed(0)} kg thóc — gặt hết lúa ngoài đồng rồi đổ ra sân`;
        return `Đổ ${G.barrel.paddy.toFixed(0)} kg thóc ra sân gạch phơi`;
      }
      return null;
    },
    act: () => {
      if (G.inv.sheaves > 0) { G.barrel.sheaves += G.inv.sheaves; G.inv.sheaves = 0; sfx.pickup(); return; }
      if (G.barrel.sheaves > 0) {
        if (tools.busy() || !spend(3)) return;
        tools.swing(0.4, 0.45, 'beat', () => {
          const n = Math.min(G.barrel.sheaves, LUOM * 2);
          G.barrel.sheaves -= n;
          G.barrel.paddy += n * field.kgPerClump();
          sfx.thresh();
          G.shake = 0.05;
        });
        return;
      }
      if (G.barrel.paddy > 0 && G.stage === 'harvest' && field.cutCount() >= field.plantedCount()) {
        court.pour(G.barrel.paddy);
        G.barrel.paddy = 0;
        G.stage = 'drying';
        G.rainAt = G.realT + 35;
        tools.select('cao');
        hud.tool('cao');
        hud.log('Đã đổ thóc ra sân. Cầm cào (phím 6), chuột trái để rải mỏng thóc đón nắng.', 'good');
      }
    },
  },
  {
    ...near(...P.tarpRoll), r: 2.2,
    label: () => {
      if (G.stage !== 'drying') return null;
      return G.tarp.on ? 'Gỡ bạt, cuộn lại' : 'Kéo bạt ni-lông phủ khung giữa sân';
    },
    act: () => {
      sfx.tarp();
      if (G.tarp.on) { G.tarp.on = false; G.tarp.placed = [false, false, false, false]; }
      else { G.tarp.on = true; G.tarp.blowT = 0; hud.log('Đã kéo bạt! Lấy gạch chặn đủ 4 góc kẻo gió lật bạt.', 'info'); }
    },
  },
  {
    ...near(...P.brickPile), r: 2.2,
    label: () => {
      if (G.stage !== 'drying') return null;
      const need = 4 - G.tarp.placed.filter(Boolean).length - G.inv.bricks;
      return need > 0 ? `Ôm ${need} viên gạch` : null;
    },
    act: () => { G.inv.bricks = 4 - G.tarp.placed.filter(Boolean).length; sfx.pickup(); },
  },
  ...CORNERS.map(([x, z], i) => ({
    x, z, r: 1.6,
    label: () => (G.tarp.on && !G.tarp.placed[i] && G.inv.bricks > 0 ? 'Đặt gạch chặn góc bạt' : null),
    act: () => { G.tarp.placed[i] = true; G.inv.bricks--; sfx.thud(true); },
  })),
  {
    ...near(...P.duckGate), r: 2.2,
    label: () => (G.duckPenOpen ? 'Đóng cổng chuồng vịt' : 'Mở cổng chuồng vịt'),
    act: () => { G.duckPenOpen = !G.duckPenOpen; sfx.pickup(); if (G.duckPenOpen) hud.log('Cầm sào vịt (phím 7) giữ chuột trái để lùa, Q để huýt sáo gọi đàn.', 'info'); },
  },
  {
    x: DUCK_PEN.x1 - 1.1, z: DUCK_PEN.z0 + 0.7, r: 2.6,
    label: () => (G.duckEggs > 0 ? `Nhặt ${G.duckEggs} quả trứng vịt vào rổ` : null),
    act: () => { G.inv.eggs += G.duckEggs; G.eggsCollected += G.duckEggs; G.duckEggs = 0; sfx.pickup(); },
  },
  {
    ...near(...P.pondEdge), r: 2.6, repeat: true,
    label: () => (G.inv.beo < 5 ? `Vớt bèo tây (${G.inv.beo}/5)` : null),
    act: () => { if (!spend(3)) return; G.inv.beo++; sfx.splash(); },
  },
  {
    ...near(...P.board), r: 2, repeat: true,
    label: () => (G.inv.beo > 0 ? 'Băm nhỏ bèo tây bằng dao chuối' : null),
    act: () => { if (tools.busy() || !spend(2)) return; tools.swing(0.3, 0.5, 'chop', () => { G.inv.beo--; G.inv.beoBam++; sfx.chop(); }); },
  },
  {
    ...near(...P.stove), r: 2.2,
    label: () => (G.inv.beoBam > 0 && G.inv.cam > 0 ? 'Trộn bèo + cám, nấu cháo heo trên bếp củi' : (G.inv.beoBam > 0 ? 'Hết cám gạo để nấu cháo heo' : null)),
    act: () => {
      if (!(G.inv.beoBam > 0 && G.inv.cam > 0)) return;
      G.inv.beoBam--; G.inv.cam--; G.inv.chao++; G.inv.ash++;
      G.smokeT = 25;
      sfx.splash();
      hud.log('Nồi cháo heo thơm nức khói lam chiều. Bếp củi còn cho thêm tro bếp.', 'good');
    },
  },
  {
    ...near(...P.trough), r: 2.2,
    label: () => (G.inv.chao > 0 && !G.pig.fed ? 'Đổ cháo vào máng cho lợn ăn' : null),
    act: () => { G.inv.chao--; G.pig.fed = true; sfx.oink(); hud.log('Lợn ăn no. Phân lợn sẽ xuống hầm biogas qua đêm.', 'info'); },
  },
  {
    ...near(...P.biogas), r: 3.6,
    label: () => (G.slurry > 0 ? `Múc ${G.slurry} gánh bùn vi sinh từ hầm biogas` : null),
    act: () => { G.inv.fert += G.slurry; G.slurry = 0; sfx.splash(); hud.log('Có bùn vi sinh! Mang ra ruộng bấm E để bón.', 'good'); },
  },
  ...STAKES.map(([x, z], i) => ({
    x, z, r: 1.6,
    label: () => (field.eggs[i] ? 'Bóc ổ trứng ốc bươu vàng' : null),
    act: () => { field.eggs[i] = false; sfx.pickup(); },
  })),
  {
    ...near(...P.buffalo), r: 3,
    label: () => 'Trâu cày (bản sau: dắt trâu bừa nhanh gấp 4)',
    act: () => { sfx.oink(); hud.log('"Tắc! Rì! Họ!" — điều khiển trâu bằng khẩu lệnh sẽ có ở bản sau.', 'info'); },
  },
];

function fieldInteraction() {
  if (!inField(player.pos.x, player.pos.z, 0.9)) return null;
  if (G.stage === 'prep' && G.nursery.state === 'pulled') {
    if (!field.prepDone()) return { label: 'Mạ đã sẵn, nhưng ruộng chưa bừa xong', act: () => {} };
    if (field.water < 1 || field.water > 6) return { label: `Cần nước xăm xắp 1–6 cm để cấy (đang ${field.water.toFixed(1)} cm)`, act: () => {} };
    return { label: 'Bắt đầu cấy lúa (mini-game nhịp điệu)', act: startTransplant };
  }
  if (G.stage === 'care') {
    if (G.inv.fert > 0) return { label: `Bón bùn vi sinh cho ruộng (${G.inv.fert})`, act: () => { G.inv.fert--; field.fertilize(); sfx.splash(); hud.log('Ruộng thêm dinh dưỡng.', 'good'); } };
    if (G.inv.ash > 0) {
      const dew = G.hour >= 5 && G.hour < 8;
      return {
        label: `Rắc tro bếp lên lá lúa (${G.inv.ash})${dew ? ' — sương còn đọng' : ''}`,
        act: () => {
          G.inv.ash--;
          field.applyAsh(dew);
          sfx.rake();
          hud.log(dew ? 'Tro bám sương trên lá, sâu cuốn lá giảm hẳn.' : 'Nắng đã lên, sương tan — tro không bám lá, hiệu quả thấp.', dew ? 'good' : 'warn');
        },
      };
    }
  }
  return null;
}

function findInteraction() {
  const fw = player.forward();
  let best = null, bd = Infinity;
  for (const it of interactables) {
    const dx = it.x - player.pos.x, dz = it.z - player.pos.z;
    const d = Math.hypot(dx, dz);
    if (d > (it.r || 2)) continue;
    if (d > 0.9 && (dx * fw.x + dz * fw.z) / d < 0.3) continue;
    const label = it.label();
    if (!label) continue;
    if (d < bd) { bd = d; best = { label, act: it.act, repeat: it.repeat }; }
  }
  return best || fieldInteraction();
}

function spend(cost) {
  if (player.stamina < cost) { hud.hint('Mệt quá! Đứng nghỉ một chút cho lại sức…'); sfx.miss(); return false; }
  player.stamina -= cost;
  return true;
}

function startTransplant() {
  G.mode = 'transplant';
  tools.select('tay');
  hud.tool('tay');
  hud.prompt('');
  transplant.start();
}

function sleep() {
  hud.flash(1);
  const target = (Math.floor(G.minutes / 1440) + 1) * 1440 + 6 * 60;
  const hours = (target - G.minutes) / 60;
  field.water = Math.max(0, field.water - hours * 0.08);
  if (field.gateOpen && G.canalFull) field.water = Math.max(field.water, Math.min(10, field.water + hours * 2));
  if (field.drainOpen) field.water = Math.max(0, field.water - hours * 2);
  advance(target - G.minutes);
  player.stamina = 100;
  hud.log(`Một đêm yên giấc. Ngày ${G.day} bắt đầu, gà gáy, sương còn đọng trên lá.`, 'info');
}

function advance(mins) {
  const d0 = Math.floor(G.minutes / 1440);
  G.minutes += mins;
  const d1 = Math.floor(G.minutes / 1440);
  for (let d = d0 + 1; d <= d1; d++) dailyTick();
}

function dailyTick() {
  G.canalFull = Math.random() > 0.3;
  if (!G.canalFull) hud.log('Hôm nay nắng gắt, mương cạn — muốn có nước phải tát bằng gàu sòng.', 'warn');
  if (G.stage !== 'drying' && Math.random() < 0.22) {
    field.water += 2.5;
    hud.log('Đêm qua có mưa rào, ruộng thêm ~2.5 cm nước.', 'info');
  }
  const n = G.nursery;
  if (n.state === 'soaked') { n.state = 'sprouted'; hud.log('Thóc giống đã nứt nanh! Ra vạt mạ cạnh nhà để gieo.', 'good'); }
  if (n.state === 'sown' && n.waterDays >= 3) { n.state = 'ready'; hud.log('Mạ đã lên xanh non, nhổ được rồi!', 'good'); }
  refreshNursery();
  if (G.stage === 'care') {
    for (const [kind, text] of field.dailyCare({ ducksInField: G.duckFieldMin > 90 })) hud.log(text, kind);
    if (field.isRipe()) { G.stage = 'harvest'; tools.select('liem'); hud.tool('liem'); }
  }
  G.duckEggs = Math.min(8, G.duckEggs + (G.duckForageMin > 90 ? 5 : 2));
  G.duckFieldMin = 0;
  G.duckForageMin = 0;
  if (G.pig.fed) { G.slurry++; G.pig.fed = false; }
}

function refreshNursery() {
  const n = G.nursery;
  world.basketWater.visible = n.state === 'soaked';
  let h = 0.01;
  if (n.state === 'sown') h = 0.15 + n.waterDays * 0.25;
  if (n.state === 'ready') h = 1;
  world.seedlings.scale.set(1, h, 1);
  world.seedlings.count = n.state === 'ready' ? Math.round(300 * (1 - n.bundles / BUNDLES)) : n.state === 'pulled' || n.state === 'done' ? 0 : 300;
}

// ---------------------------------------------------------------- tools
function aimPoint(dist) {
  const fw = player.forward();
  return [player.pos.x + fw.x * dist, player.pos.z + fw.z * dist];
}

function useTool(button) {
  const id = tools.current;
  if (tools.busy()) return;
  if (id === 'cuoc') {
    if (G.stage !== 'prep') return hud.hint('Ruộng đã cấy, không cần cuốc nữa.');
    const [x, z] = aimPoint(1.3);
    if (field.cellAt(x, z) < 0) return hud.hint('Hướng cuốc vào ruộng.');
    const hard = field.isWet() ? 0.25 : 1;
    if (!spend(5 + 9 * hard)) return;
    tools.swing(0.6, 0.4, 'chop', () => {
      field.hoe(x, z);
      sfx.thud(hard > 0.5);
      G.shake = hard > 0.5 ? 0.12 : 0.05;
    });
  } else if (id === 'gau') {
    const { x, z } = player.pos;
    if (!(x < -8.1 && x > -12.5 && Math.abs(z) < 9)) return hud.hint('Đứng ở bờ tây giáp mương để tát nước vào ruộng.');
    if (!spend(7)) return;
    tools.swing(0.8, 0.45, 'scoop', () => {
      field.water = Math.min(12, field.water + 0.35);
      sfx.splash();
    });
  } else if (id === 'liem') {
    if (G.stage !== 'harvest') return hud.hint(G.stage === 'care' ? 'Lúa chưa chín.' : 'Chưa có lúa để gặt.');
    const room = CARRY - G.inv.sheaves;
    if (room <= 0) return hud.hint('Đòn gánh đã đầy — gánh về thùng đập lúa ở sân.');
    const [x, z] = aimPoint(0.9);
    if (!spend(3)) return;
    tools.swing(0.42, 0.5, 'slash', () => {
      const n = field.cutNear(x, z, 0.95, Math.min(6, room));
      if (n) { sfx.swish(); G.inv.sheaves += n; } else sfx.step();
    });
  } else if (id === 'cao') {
    const [x, z] = aimPoint(1.5);
    const idx = court.cellAt(x, z);
    if (idx < 0) return hud.hint('Cào dùng để rải/vun thóc trên sân gạch.');
    if (!spend(2)) return;
    tools.swing(0.32, 0.5, 'pull', () => {
      const ok = button === 2 ? court.gather(idx) : court.spread(idx);
      if (ok) sfx.rake();
    });
  }
}

// ---------------------------------------------------------------- input
const canvas = renderer.domElement;
addEventListener('keydown', e => {
  if (['Space', 'Tab'].includes(e.code)) e.preventDefault();
  G.keys[e.code] = true;
  if (!G.playing || e.repeat) return;
  if (G.mode === 'summary') { if (e.code === 'KeyR') location.reload(); return; }
  if (G.mode === 'transplant') { transplant.key(e.code); return; }
  const tool = TOOLS.find(t => 'Digit' + t.key === e.code);
  if (tool) { tools.select(tool.id); hud.tool(tools.current); }
  if (e.code === 'KeyE') {
    G.eHeld = true;
    G.eTimer = 0.45;
    G.target?.act();
  }
  if (e.code === 'KeyQ') ducks.whistle();
  if (DEBUG) debugKey(e.code);
});
addEventListener('keyup', e => {
  G.keys[e.code] = false;
  if (e.code === 'KeyE') G.eHeld = false;
});
canvas.addEventListener('contextmenu', e => e.preventDefault());
canvas.addEventListener('mousedown', e => {
  if (!G.playing) return;
  if (document.pointerLockElement !== canvas && !DEBUG) { lock(); return; }
  if (e.button === 0) G.mouse.left = true;
  if (e.button === 2) G.mouse.right = true;
});
addEventListener('mouseup', e => {
  if (e.button === 0) G.mouse.left = false;
  if (e.button === 2) G.mouse.right = false;
});
addEventListener('mousemove', e => {
  // ignore the occasional huge jump some browsers report right after locking
  if (Math.abs(e.movementX) > 250 || Math.abs(e.movementY) > 250) return;
  if (document.pointerLockElement === canvas && G.mode !== 'transplant') player.look(e.movementX, e.movementY);
});
function lock() {
  try { const p = canvas.requestPointerLock(); if (p && p.catch) p.catch(() => {}); } catch { /* not supported */ }
}
document.addEventListener('pointerlockchange', () => {
  const locked = document.pointerLockElement === canvas;
  G.paused = !locked && G.playing && G.mode !== 'summary';
  document.getElementById('pause').hidden = !G.paused;
});
document.getElementById('pause').addEventListener('click', lock);
document.getElementById('play').addEventListener('click', () => {
  initAudio();
  document.getElementById('start').hidden = true;
  G.playing = true;
  lock();
  hud.log('Sáng sớm ngày đầu vụ. Ruộng khô nứt nẻ đang chờ bạn.', 'info');
  hud.log('Cầm cuốc (phím 2), xuống ruộng, chuột trái để cuốc. Mẹo: dẫn nước vào trước thì đất mềm hơn.', 'info');
});
addEventListener('resize', () => {
  camera.aspect = innerWidth / innerHeight;
  camera.updateProjectionMatrix();
  renderer.setSize(innerWidth, innerHeight);
});

// ---------------------------------------------------------------- weather & sky
const C_DAY = new THREE.Color(0x9fd3f0), C_DUSK = new THREE.Color(0xf4b88a), C_NIGHT = new THREE.Color(0x0a1224), C_STORM = new THREE.Color(0x3c434c);
const skyColor = new THREE.Color();

function updateSky() {
  const h = G.hour;
  const ang = ((h - 6) / 12) * Math.PI;
  const elev = Math.sin(ang);
  const day = clamp(elev * 3 + 0.35, 0, 1);
  const dusk = elev > -0.15 && elev < 0.35 ? 1 - Math.abs(elev - 0.08) / 0.27 : 0;
  const storm = G.storm.level;
  skyColor.copy(C_NIGHT).lerp(C_DAY, day).lerp(C_DUSK, clamp(dusk, 0, 1) * 0.6).lerp(C_STORM, storm * 0.85);
  const flash = G.storm.lightning;
  if (flash > 0) skyColor.lerp(new THREE.Color(0xdde6ff), flash);
  scene.background = skyColor;
  scene.fog.color.copy(skyColor);
  scene.fog.near = lerp(40, 12, storm);
  scene.fog.far = lerp(150, 70, storm);
  const dir = new THREE.Vector3(Math.cos(ang) * 60, Math.max(elev, 0.08) * 70, -25);
  sun.position.copy(player.pos).add(dir);
  sun.target.position.copy(player.pos);
  sun.intensity = 2.6 * clamp(elev * 2.5, 0, 1) * (1 - 0.8 * storm);
  sun.color.copy(new THREE.Color(0xfff2d8)).lerp(C_DUSK, clamp(dusk, 0, 1) * 0.5);
  hemi.intensity = (0.25 + 0.85 * day) * (1 - 0.35 * storm) + flash * 2;
  sunDisk.position.copy(camera.position).add(dir.clone().normalize().multiplyScalar(220));
  sunDisk.visible = elev > -0.05 && storm < 0.5;
  return Math.max(0, elev) * (1 - storm) * (G.raining ? 0 : 1);
}

function updateStorm(dt) {
  const s = G.storm;
  if (s.phase === 'none' && G.realT >= G.rainAt) {
    s.phase = 'warning';
    s.t = 90;
    G.rainAt = Infinity;
    sfx.thunder(1);
    hud.log('Trời bỗng sầm tối, gió nổi mạnh… Mưa rào sắp ập tới!', 'bad');
  }
  if (s.phase === 'warning') {
    s.t -= dt;
    s.level = Math.min(0.85, s.level + dt / 30);
    s.nextBolt -= dt;
    if (s.nextBolt <= 0) { s.nextBolt = rand(5, 11); s.lightning = 0.6; setTimeout(() => sfx.thunder(1.2), 1500); }
    if (s.t <= 0) { s.phase = 'rain'; s.t = 40; G.raining = true; hud.log('Mưa trút xuống ào ào!', 'bad'); }
  } else if (s.phase === 'rain') {
    s.t -= dt;
    s.level = Math.min(1, s.level + dt / 5);
    s.nextBolt -= dt;
    if (s.nextBolt <= 0) { s.nextBolt = rand(3, 8); s.lightning = 1; setTimeout(() => sfx.thunder(0.2), 300); }
    const anchored = G.tarp.placed.every(Boolean);
    if (G.tarp.on && !anchored) {
      G.tarp.blowT += dt;
      if (G.tarp.blowT > 12) {
        G.tarp.on = false;
        G.tarp.placed = [false, false, false, false];
        G.tarp.flyT = 3;
        sfx.tarp();
        hud.log('Gió giật lật tung tấm bạt vì chưa chặn đủ gạch 4 góc!', 'bad');
      }
    }
    if (s.t <= 0) { s.phase = 'after'; s.t = 20; G.raining = false; hud.log('Tạnh mưa. Gỡ bạt và rải thóc ra phơi tiếp.', 'info'); }
  } else if (s.phase === 'after') {
    s.t -= dt;
    s.level = Math.max(0, s.level - dt / 10);
    if (s.t <= 0 && s.level <= 0) s.phase = 'done';
  }
  s.lightning = Math.max(0, s.lightning - dt * 3);
  hud.flash(s.lightning * 0.5);
  setWind(s.level * (s.phase === 'warning' || s.phase === 'rain' ? 1 : 0.3));
  setRain(G.raining ? 1 : 0);

  if (s.phase === 'warning') {
    const inside = Math.round(court.shareInside() * 100);
    const bricks = G.tarp.placed.filter(Boolean).length;
    hud.banner(`⛈ Mưa rào sau <b>${Math.ceil(s.t)}</b> giây!<small>Vun thóc vào khung bạt (chuột phải): ${inside}% · Bạt: ${G.tarp.on ? 'đã kéo' : 'chưa'} · Gạch: ${bricks}/4</small>`);
  } else if (s.phase === 'rain') {
    hud.banner(`🌧 Đang mưa — thóc ngoài bạt bị ướt: ${Math.round(court.soakedFraction() * 100)}%`);
  } else hud.banner('');
}

function updateRain(dt) {
  rain.visible = G.raining;
  if (!G.raining) return;
  const p = rainGeo.attributes.position;
  const a = p.array;
  for (let i = 0; i < RAIN_N; i++) {
    const o = i * 6;
    let y = a[o + 1] - dt * 18;
    if (y < 0) {
      y += 20;
      a[o] = rand(-25, 25);
      a[o + 2] = rand(-25, 25);
    }
    a[o] += dt * 2.5;
    if (a[o] > 25) a[o] -= 50;
    a[o + 1] = y;
    a[o + 3] = a[o] + 0.06;
    a[o + 4] = y + 0.45;
    a[o + 5] = a[o + 2];
  }
  p.needsUpdate = true;
  rain.position.set(player.pos.x, player.y, player.pos.z);
}

// ---------------------------------------------------------------- HUD text
const check = (ok, text) => `<div class="${ok ? 'done' : ''}">${ok ? '✓' : '○'} ${text}</div>`;
const bar = v => `<span class="bar"><i style="width:${Math.round(clamp(v, 0, 1) * 100)}%"></i></span>`;
const pct = v => `${Math.round(v * 100)}%`;

function objectives() {
  const n = G.nursery;
  if (G.stage === 'prep') {
    const nIdx = ['none', 'soaked', 'sprouted', 'sown', 'ready', 'pulled'].indexOf(n.state);
    return '<h4>Giai đoạn 1–2 · Làm đất & Ươm mạ</h4>' +
      check(field.avgTill() >= 0.9, `Cuốc xới đất khô (${pct(field.avgTill())}) — phím 2`) +
      check(field.water >= 1 || field.avgSmooth() >= 0.85, 'Mở cửa cống dẫn nước vào ruộng (bờ tây)') +
      check(field.avgSmooth() >= 0.85, `Bừa bùn nhuyễn (${pct(field.avgSmooth())}) — phím 3, giữ chuột trái & đi`) +
      check(nIdx >= 1, 'Ngâm thóc giống (thúng cạnh sân)') +
      check(nIdx >= 3, 'Ủ qua đêm → gieo thóc nứt nanh lên vạt mạ') +
      check(nIdx >= 4, `Tưới mạ 3 ngày (${n.waterDays}/3)`) +
      check(nIdx >= 5, `Nhổ & bó mạ (${n.bundles}/${BUNDLES})`) +
      check(false, 'Vào ruộng, bấm E để cấy') +
      '<div style="opacity:.7;margin-top:4px">Nằm võng ở hiên nhà để qua ngày.</div>';
  }
  if (G.stage === 'care') {
    const eggs = field.eggs.filter(Boolean).length;
    return `<h4>Giai đoạn 3 · Chăm sóc (lúa ${field.growthDay}/8 ngày)</h4>` +
      check(field.water >= 3 && field.water <= 5, 'Giữ nước 3–5 cm: cống / rãnh xả / gàu sòng') +
      check(field.pest < 0.3, 'Rắc tro bếp lúc sáng sớm (5h–8h) khi sâu tăng') +
      check(eggs === 0, `Bóc trứng ốc trên cọc tre (${eggs} ổ)`) +
      check(false, field.growthDay < 5 ? 'Thả vịt vào ruộng: dọn ốc, cỏ, sục bùn' : 'Lúa trổ bông: lùa vịt RA khỏi ruộng!') +
      '<div style="opacity:.7;margin-top:4px">Nằm võng để lúa lớn thêm một ngày.</div>';
  }
  if (G.stage === 'harvest') {
    return '<h4>Giai đoạn 4 · Gặt & Tuốt lúa</h4>' +
      check(field.cutCount() >= field.plantedCount(), `Gặt bằng liềm — phím 5 (${field.cutCount()}/${field.plantedCount()} khóm)`) +
      check(G.inv.sheaves === 0, `Gánh lúa về thùng đập ở sân (đang gánh ${(G.inv.sheaves / LUOM).toFixed(1)} lượm)`) +
      check(G.barrel.sheaves === 0 && G.barrel.paddy > 0, `Đập lúa vào thùng (${G.barrel.paddy.toFixed(0)} kg thóc)`) +
      check(false, 'Đổ thóc ra sân gạch');
  }
  if (G.stage === 'drying') {
    return '<h4>Chạy thóc · Phơi trên sân gạch đỏ</h4>' +
      check(court.dryFraction() > 0.98, `Rải mỏng thóc đón nắng — chuột trái (khô ${pct(court.dryFraction())})`) +
      check(['after', 'done'].includes(G.storm.phase), 'Khi giông tới: vun thóc vào khung bạt (chuột phải), kéo bạt, chặn 4 góc gạch');
  }
  return '';
}

function stats() {
  const w = field.water;
  const wc = w > 7 ? 'bad' : w < 1 ? (G.stage === 'care' ? 'bad' : 'warn') : w >= 3 && w <= 5 ? 'ok' : 'warn';
  let s = '<b>Thửa ruộng</b><br>' +
    `Mực nước: <span class="${wc}">${w.toFixed(1)} cm</span><br>` +
    `Độ tơi đất ${bar(field.avgTill())}<br>Độ nhuyễn bùn ${bar(field.avgSmooth())}<br>`;
  if (G.stage !== 'prep') {
    s += `Sâu hại <span class="${field.pest > 0.4 ? 'bad' : ''}">${bar(field.pest)}</span><br>` +
      `Dinh dưỡng ${bar(field.nutrient)}<br>Sức khỏe lúa ${bar(field.health)}<br>` +
      `Cỏ dại ${bar(field.weeds)}<br>Thẩm mỹ đồng ruộng: ${pct(field.aesthetic)}<br>`;
  }
  s += `Cống: ${field.gateOpen ? 'mở' : 'đóng'} · Rãnh xả: ${field.drainOpen ? 'mở' : 'đắp'}<br>` +
    `Mương: <span class="${G.canalFull ? 'ok' : 'warn'}">${G.canalFull ? 'đầy nước' : 'cạn'}</span> · Vịt trong ruộng: ${Math.round(ducks.fractionInField() * 10)}/10`;
  return s;
}

function inventory() {
  const i = G.inv;
  const parts = [`Tro bếp ${i.ash}`, `Cám ${i.cam}`];
  if (i.beo) parts.push(`Bèo ${i.beo}`);
  if (i.beoBam) parts.push(`Bèo băm ${i.beoBam}`);
  if (i.chao) parts.push(`Cháo heo ${i.chao}`);
  if (i.fert) parts.push(`Bùn vi sinh ${i.fert}`);
  if (i.eggs) parts.push(`Trứng vịt ${i.eggs}`);
  if (i.bricks) parts.push(`Gạch ${i.bricks}`);
  if (i.sheaves) parts.push(`Gánh ${(i.sheaves / LUOM).toFixed(1)}/8 lượm`);
  return parts.join(' · ');
}

function clockText() {
  const h = G.hour;
  const tod = h < 5 || h >= 19 ? '🌙 Đêm' : h < 8 ? '🌅 Sương sớm' : h < 17 ? '☀ Ban ngày' : '🌇 Chiều tà';
  return `Ngày ${G.day} · ${fmtTime(G.minutes)} · ${tod}${G.raining ? ' · 🌧 Mưa' : ''}`;
}

function showSummary() {
  G.mode = 'summary';
  document.exitPointerLock?.();
  const kg = court.total;
  const soaked = court.soakedFraction();
  const grade = soaked < 0.05 ? 'Gạo loại 1 — hạt trong, thơm' : soaked < 0.25 ? 'Gạo loại 2 — một phần thóc lên mầm' : 'Gạo nát / thức ăn chăn nuôi — thóc ướt mưa lên mầm nhiều';
  document.getElementById('summary-body').innerHTML = `
    <h2>Kết thúc vụ lúa</h2>
    <div class="grade">${grade}</div>
    <table>
      <tr><td>Thóc phơi khô</td><td>${kg.toFixed(0)} kg</td></tr>
      <tr><td>Thóc bị ướt mưa</td><td>${pct(soaked)}</td></tr>
      <tr><td>Thẩm mỹ đồng ruộng</td><td>${pct(field.aesthetic)} (+${Math.round(field.aesthetic * 15)}% sản lượng)</td></tr>
      <tr><td>Sức khỏe lúa cuối vụ</td><td>${pct(field.health)}</td></tr>
      <tr><td>Thưởng vịt chạy đồng</td><td>+${pct(field.duckBonus)}</td></tr>
      <tr><td>Trứng vịt đã nhặt</td><td>${G.eggsCollected}</td></tr>
      <tr><td>Số ngày</td><td>${G.day}</td></tr>
    </table>
    <p>Cảm ơn bạn đã xuống đồng! Bấm <kbd>R</kbd> hoặc nút dưới để làm vụ mới.</p>
    <button onclick="location.reload()">Vụ mới</button>`;
  document.getElementById('summary').hidden = false;
}

// ---------------------------------------------------------------- loop
const clock = new THREE.Clock();
let ambT = 0;
let fps = 60;

function frame() {
  requestAnimationFrame(frame);
  const raw = clock.getDelta();
  fps = lerp(fps, 1 / Math.max(raw, 1e-3), 0.05);
  const dt = Math.min(raw, 0.1);
  const running = G.playing && !G.paused && G.mode !== 'summary';
  if (running) step(dt);
  else player.update(0, {}, field);
  render(dt);
}

function step(dt) {
  G.realT += dt;
  const dtMin = dt * MIN_PER_SEC;
  advance(dtMin);
  const sunF = updateSky();
  updateStorm(dt);
  updateRain(dt);

  // body & tools
  const { moved } = player.update(dt, G.mode === 'walk' ? G.keys : {}, field, { load: G.inv.sheaves / CARRY });
  if (G.shake > 0) {
    camera.rotation.x += rand(-1, 1) * G.shake * 0.1;
    camera.rotation.z += rand(-1, 1) * G.shake * 0.1;
    G.shake = Math.max(0, G.shake - dt);
  }
  const poleActive = tools.current === 'sao' && G.mouse.left && G.mode === 'walk';
  tools.update(dt, { moving: player.moving, bob: player.bobPhase, time: G.realT, waving: poleActive, carrying: G.inv.sheaves / CARRY });

  if (G.mode === 'transplant') transplant.update(dt);

  if (G.mode === 'walk') {
    hud.hint('');
    if (G.mouse.left || G.mouse.right) {
      if (tools.current === 'bua' && G.mouse.left) {
        const res = field.harrow(player.pos.x, player.pos.z, moved);
        if (res === 'dry') hud.hint('Phải dẫn nước vào ruộng (≥ 1 cm) mới bừa được bùn.');
        else if (res === 'untilled') hud.hint('Chỗ này chưa cuốc kỹ.');
        else if (res === 'ok' && moved > 0) player.stamina -= moved * 3;
      } else if (tools.current !== 'sao') useTool(G.mouse.right ? 2 : 0);
    }
    G.target = findInteraction();
    if (G.target) hud.prompt(G.target.label);
    if (G.eHeld && G.target?.repeat) {
      G.eTimer -= dt;
      if (G.eTimer <= 0) { G.eTimer = 0.3; G.target.act(); }
    }
  }

  // simulation
  field.update(dtMin, { canalFull: G.canalFull, raining: G.raining, sun: sunF });
  if (G.stage === 'drying') {
    court.update(dtMin, { sun: sunF, raining: G.raining, tarpOn: G.tarp.on });
    if (court.dryFraction() > 0.98 && ['after', 'done'].includes(G.storm.phase) && !G.tarp.on) showSummary();
  }
  ducks.update(dt, { player: player.pos, forward: player.forward(), poleActive, penOpen: G.duckPenOpen, time: G.realT });
  const inF = ducks.fractionInField();
  if (inF > 0.5) G.duckFieldMin += dtMin;
  const outside = ducks.list.filter(d => !(d.pos.x > DUCK_PEN.x0 && d.pos.x < DUCK_PEN.x1 && d.pos.z > DUCK_PEN.z0 && d.pos.z < DUCK_PEN.z1)).length;
  if (outside > 5) G.duckForageMin += dtMin;

  // ambience: frogs and crickets at night, birds by day
  ambT -= dt;
  if (ambT <= 0) {
    ambT = 0.12;
    const h = G.hour;
    const night = h < 5 || h >= 18.5;
    const nearWater = Math.hypot(player.pos.x, player.pos.z) < 25;
    if ((night || G.raining) && nearWater && Math.random() < 0.6) sfx.frog();
    if (night && Math.random() < 0.3) sfx.cricket();
    if (!night && !G.raining && Math.random() < 0.04) sfx.bird();
  }

  updateVisuals(dt);
  hud.vignette(player.stamina < 20 ? 0.8 : 0);
  hud.stamina(player.stamina);
  hud.set('clock', clockText());
  hud.set('objective', objectives());
  hud.set('stats', stats());
  hud.set('inv', inventory());
}

function updateVisuals(dt) {
  field.refreshVisuals();
  world.gate.position.y = field.gateOpen ? 0.55 : -0.05;
  world.drainPlug.visible = !field.drainOpen;
  field.eggs.forEach((e, i) => { world.eggs[i].visible = e; });
  world.duckEggs.children.forEach((e, i) => { e.visible = i < G.duckEggs; });
  world.duckGate.rotation.y = G.duckPenOpen ? -Math.PI / 2 : 0;
  world.barrelGrain.scale.y = 1 + G.barrel.paddy / 6;
  world.barrelGrain.position.y = 0.05 + G.barrel.paddy / 240;
  world.canalWater.position.y = G.canalFull ? -0.3 : -0.7;
  world.pot.material.color.setHex(G.smokeT > 0 ? 0x4a3a2a : 0x2a2a2a);

  // tarp: sits on top of the heap, flaps in the wind, flies off if not weighted
  const tp = world.tarp;
  if (G.tarp.flyT > 0) {
    G.tarp.flyT -= dt;
    tp.visible = true;
    tp.position.x += dt * 8;
    tp.position.y += dt * 4;
    tp.rotation.z += dt * 2;
    if (G.tarp.flyT <= 0) { tp.visible = false; tp.position.set(0, 0.6, -17); tp.rotation.set(0, 0, 0); }
  } else {
    tp.visible = G.tarp.on;
    if (G.tarp.on) {
      tp.position.y = court.maxHeight() + 0.12;
      const anchored = G.tarp.placed.every(Boolean);
      const amp = G.storm.level * (anchored ? 0.03 : 0.25);
      const pos = tp.geometry.attributes.position;
      for (let i = 0; i < pos.count; i++) {
        const x = pos.getX(i), z = pos.getZ(i);
        const edge = Math.max(Math.abs(x), Math.abs(z)) / 2.2;
        pos.setY(i, Math.sin(G.realT * 9 + x * 2 + z) * amp * edge - edge * edge * tp.position.y * 0.8);
      }
      pos.needsUpdate = true;
    }
  }
  CORNERS.forEach((_, i) => {
    world.cornerBricks[i].visible = G.tarp.placed[i];
    world.cornerMarks[i].visible = G.tarp.on && !G.tarp.placed[i];
  });

  // aim markers
  hoeMark.visible = false;
  court.setHighlight(-1);
  if (G.mode === 'walk' && tools.current === 'cuoc' && G.stage === 'prep') {
    const [x, z] = aimPoint(1.3);
    const idx = field.cellAt(x, z);
    if (idx >= 0) {
      const [cx, cz] = field.cellCenter(idx);
      hoeMark.position.set(cx, FIELD.y + 0.12, cz);
      hoeMark.visible = true;
    }
  }
  if (G.mode === 'walk' && tools.current === 'cao') {
    const [x, z] = aimPoint(1.5);
    if (inCourt(x, z)) court.setHighlight(court.cellAt(x, z));
  }

  // smoke from the kitchen
  G.smokeT = Math.max(0, G.smokeT - dt);
  for (const s of smoke) {
    s.userData.t += dt;
    if (s.userData.t > 4) s.userData.t = 0;
    const t = s.userData.t;
    s.position.set(P.stove[0] + Math.sin(t + s.id) * 0.3 * t, 0.8 + t * 1.1, P.stove[1] + t * 0.3);
    s.scale.setScalar(0.6 + t * 0.5);
    s.material.opacity = G.smokeT > 0 ? (1 - t / 4) * 0.35 : 0;
  }
  world.pig.rotation.y = Math.sin(G.realT * 0.5) * 0.4;
}

function render() {
  renderer.render(scene, camera);
}

// ---------------------------------------------------------------- debug helpers (?debug)
function debugSkipPrep() {
  field.till.fill(1); field.smooth.fill(1); field.water = 3; field.soilDirty = true;
  G.nursery.state = 'pulled'; G.nursery.bundles = BUNDLES; refreshNursery();
}
function debugPlantAll() {
  for (let l = 0; l < 8; l++) for (let r = 0; r < 26; r++) for (const s of [-0.6, 0, 0.6]) field.plant(FIELD.x0 + 2 * l + 1 + s + rand(-0.04, 0.04), FIELD.z1 - 0.5 - r * 0.6);
  field.aesthetic = 0.85; G.stage = 'care'; G.nursery.state = 'done';
}
function debugKey(code) {
  if (code === 'F6') { debugSkipPrep(); hud.log('[debug] làm đất + mạ xong', 'info'); }
  if (code === 'F7') { if (G.stage === 'prep') { debugSkipPrep(); debugPlantAll(); } hud.log('[debug] đã cấy', 'info'); }
  if (code === 'F8') { if (G.stage === 'prep') { debugSkipPrep(); debugPlantAll(); } field.growthDay = 8; field.riceDirty = true; G.stage = 'harvest'; }
  if (code === 'F9') {
    if (G.stage === 'prep') { debugSkipPrep(); debugPlantAll(); }
    field.growthDay = 8; field.clumps.forEach(c => { c.cut = true; }); field.riceDirty = true;
    G.stage = 'harvest'; G.barrel.paddy = 150;
  }
}
if (DEBUG) window.game = { get fps() { return fps; }, G, field, court, ducks, player, tools, transplant, sleep, debugKey, interactables, findInteraction, useTool };

refreshNursery();
hud.tool('tay');
frame();
