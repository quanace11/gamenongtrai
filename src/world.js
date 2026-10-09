// Static scenery of the farm: ground, bunds, canal, house, courtyard,
// animals' sheds and the props the player interacts with.
import * as THREE from 'three';
import { FIELD, CANAL, POND, COURT, TARP, DUCK_PEN, P, CORNERS, STAKES } from './layout.js';

const matCache = new Map();
export function mat(color, opts = {}) {
  const key = color + JSON.stringify(opts);
  if (!matCache.has(key)) matCache.set(key, new THREE.MeshLambertMaterial({ color, ...opts }));
  return matCache.get(key);
}

function box(parent, w, h, d, color, x, y, z, opts = {}) {
  const m = new THREE.Mesh(new THREE.BoxGeometry(w, h, d), mat(color));
  m.position.set(x, y, z);
  if (opts.ry) m.rotation.y = opts.ry;
  m.castShadow = opts.shadow !== false;
  m.receiveShadow = true;
  parent.add(m);
  return m;
}

function cyl(parent, rt, rb, h, color, x, y, z, seg = 8) {
  const m = new THREE.Mesh(new THREE.CylinderGeometry(rt, rb, h, seg), mat(color));
  m.position.set(x, y, z);
  m.castShadow = true;
  parent.add(m);
  return m;
}

function brickTexture() {
  const c = document.createElement('canvas');
  c.width = 256; c.height = 256;
  const g = c.getContext('2d');
  g.fillStyle = '#7a3a26';
  g.fillRect(0, 0, 256, 256);
  for (let r = 0; r < 8; r++) {
    for (let k = 0; k < 9; k++) {
      const x = k * 32 - (r % 2) * 16;
      const shade = 150 + Math.random() * 40;
      g.fillStyle = `rgb(${shade + 20},${shade * 0.45},${shade * 0.32})`;
      g.fillRect(x + 1.5, r * 32 + 1.5, 29, 29);
    }
  }
  const t = new THREE.CanvasTexture(c);
  t.wrapS = t.wrapT = THREE.RepeatWrapping;
  t.repeat.set(3, 1.5);
  t.colorSpace = THREE.SRGBColorSpace;
  return t;
}

function grassTexture() {
  const c = document.createElement('canvas');
  c.width = 128; c.height = 128;
  const g = c.getContext('2d');
  g.fillStyle = '#6f9a45';
  g.fillRect(0, 0, 128, 128);
  for (let i = 0; i < 900; i++) {
    const v = Math.random();
    g.fillStyle = v < 0.5 ? 'rgba(80,120,40,0.5)' : 'rgba(140,170,80,0.4)';
    g.fillRect(Math.random() * 128, Math.random() * 128, 2, 3);
  }
  const t = new THREE.CanvasTexture(c);
  t.wrapS = t.wrapT = THREE.RepeatWrapping;
  t.repeat.set(80, 80);
  t.colorSpace = THREE.SRGBColorSpace;
  return t;
}

function buildGround(scene) {
  const S = 160;
  const shape = new THREE.Shape();
  shape.moveTo(-S, -S); shape.lineTo(S, -S); shape.lineTo(S, S); shape.lineTo(-S, S); shape.lineTo(-S, -S);
  // Shape lives in XY and is rotated onto XZ, so shape y = -world z.
  const rect = (x0, x1, z0, z1) => {
    const h = new THREE.Path();
    h.moveTo(x0, -z0); h.lineTo(x0, -z1); h.lineTo(x1, -z1); h.lineTo(x1, -z0); h.lineTo(x0, -z0);
    return h;
  };
  const b = FIELD.bund;
  shape.holes.push(rect(FIELD.x0 - b, FIELD.x1 + b, FIELD.z0 - b, FIELD.z1 + b));
  shape.holes.push(rect(CANAL.x0, CANAL.x1, CANAL.z0, CANAL.z1));
  const pond = new THREE.Path();
  pond.absarc(POND.x, -POND.z, POND.r, 0, Math.PI * 2, true);
  shape.holes.push(pond);
  const geo = new THREE.ShapeGeometry(shape, 24);
  geo.rotateX(-Math.PI / 2);
  const uv = geo.attributes.uv;
  for (let i = 0; i < uv.count; i++) uv.setXY(i, uv.getX(i) / (2 * S) + 0.5, uv.getY(i) / (2 * S) + 0.5);
  const ground = new THREE.Mesh(geo, new THREE.MeshLambertMaterial({ map: grassTexture() }));
  ground.receiveShadow = true;
  scene.add(ground);

  // Bờ ruộng (bunds)
  const bundColor = 0x7d6a3e;
  const L = FIELD.x1 - FIELD.x0 + 2 * b;
  const h = 0.55, yc = FIELD.bundTop - h / 2;
  box(scene, L, h, b, bundColor, 0, yc, FIELD.z0 - b / 2, { shadow: false });
  box(scene, L, h, b, bundColor, 0, yc, FIELD.z1 + b / 2, { shadow: false });
  box(scene, b, h, L, bundColor, FIELD.x0 - b / 2, yc, 0, { shadow: false });
  box(scene, b, h, L, bundColor, FIELD.x1 + b / 2, yc, 0, { shadow: false });
  // grass tufts on bunds
  const tuftGeo = new THREE.ConeGeometry(0.07, 0.25, 4);
  const tufts = new THREE.InstancedMesh(tuftGeo, mat(0x5f8a35), 220);
  const m4 = new THREE.Matrix4();
  for (let i = 0; i < 220; i++) {
    const side = i % 4, t = Math.random() * L - L / 2;
    const off = FIELD.x1 + b / 2 + (Math.random() - 0.5) * 0.5;
    const pos = [[t, -off], [t, off], [-off, t], [off, t]][side];
    m4.makeTranslation(pos[0], FIELD.bundTop + 0.1, pos[1]);
    tufts.setMatrixAt(i, m4);
  }
  scene.add(tufts);

  // Mương (canal)
  const canalLen = CANAL.z1 - CANAL.z0;
  const cx = (CANAL.x0 + CANAL.x1) / 2;
  box(scene, 2, 0.1, canalLen, 0x4b3b26, cx, -0.95, 0, { shadow: false });
  box(scene, 0.1, 0.9, canalLen, 0x5a4a30, CANAL.x0, -0.45, 0, { shadow: false });
  box(scene, 0.1, 0.9, canalLen, 0x5a4a30, CANAL.x1, -0.45, 0, { shadow: false });
  const canalWater = new THREE.Mesh(new THREE.PlaneGeometry(2, canalLen),
    new THREE.MeshPhongMaterial({ color: 0x4f7a78, transparent: true, opacity: 0.8, shininess: 90 }));
  canalWater.rotation.x = -Math.PI / 2;
  canalWater.position.set(cx, -0.3, 0);
  scene.add(canalWater);
  // Rãnh dẫn nước from canal to the gate
  box(scene, 1.2, 0.05, 0.9, 0x4f7a78, -9.4, 0.02, 0, { shadow: false });
  box(scene, 0.8, 0.05, 0.7, 0x4f7a78, 9.2, 0.02, 4, { shadow: false });

  // Ao (pond) with bèo tây
  const pondBottom = new THREE.Mesh(new THREE.CircleGeometry(POND.r, 32), mat(0x3e3222));
  pondBottom.rotation.x = -Math.PI / 2;
  pondBottom.position.set(POND.x, -0.9, POND.z);
  scene.add(pondBottom);
  const pondWall = new THREE.Mesh(new THREE.CylinderGeometry(POND.r, POND.r, 0.9, 32, 1, true), mat(0x5a4a30, { side: THREE.BackSide }));
  pondWall.position.set(POND.x, -0.45, POND.z);
  scene.add(pondWall);
  const pondWater = new THREE.Mesh(new THREE.CircleGeometry(POND.r, 32),
    new THREE.MeshPhongMaterial({ color: 0x46705a, transparent: true, opacity: 0.85, shininess: 80 }));
  pondWater.rotation.x = -Math.PI / 2;
  pondWater.position.set(POND.x, -0.2, POND.z);
  scene.add(pondWater);
  const hyacinths = new THREE.Group();
  for (let i = 0; i < 26; i++) {
    const a = Math.random() * Math.PI * 2, r = Math.random() * (POND.r - 0.6);
    const g = new THREE.Group();
    for (let k = 0; k < 4; k++) {
      const leaf = new THREE.Mesh(new THREE.SphereGeometry(0.18, 6, 4), mat(0x3f8f3a));
      leaf.scale.set(1, 0.4, 0.7);
      leaf.position.set(Math.cos(k * 1.6) * 0.15, 0.06, Math.sin(k * 1.6) * 0.15);
      g.add(leaf);
    }
    if (Math.random() < 0.4) {
      const fl = new THREE.Mesh(new THREE.SphereGeometry(0.07, 6, 4), mat(0xb28ad8));
      fl.position.y = 0.2;
      g.add(fl);
    }
    g.position.set(POND.x + Math.cos(a) * r, -0.2, POND.z + Math.sin(a) * r);
    hyacinths.add(g);
  }
  scene.add(hyacinths);

  return { canalWater, hyacinths };
}

function buildHouse(scene) {
  const g = new THREE.Group();
  // Courtyard (sân gạch đỏ)
  const courtMat = new THREE.MeshLambertMaterial({ map: brickTexture() });
  const court = new THREE.Mesh(new THREE.PlaneGeometry(COURT.x1 - COURT.x0, COURT.z1 - COURT.z0), courtMat);
  court.rotation.x = -Math.PI / 2;
  court.position.set((COURT.x0 + COURT.x1) / 2, 0.015, (COURT.z0 + COURT.z1) / 2);
  court.receiveShadow = true;
  g.add(court);
  // faint outline where the tarp should go
  const outline = new THREE.LineSegments(
    new THREE.EdgesGeometry(new THREE.PlaneGeometry(TARP.x1 - TARP.x0, TARP.z1 - TARP.z0)),
    new THREE.LineBasicMaterial({ color: 0xe8d6a0, transparent: true, opacity: 0.5 }));
  outline.rotation.x = -Math.PI / 2;
  outline.position.set((TARP.x0 + TARP.x1) / 2, 0.03, (TARP.z0 + TARP.z1) / 2);
  g.add(outline);

  // Nhà 3 gian
  box(g, 10, 2.6, 6, 0xd9c7a0, 0, 1.3, -25.5);
  box(g, 10.4, 0.25, 1.6, 0x8c7b5c, 0, 0.12, -21.9, { shadow: false }); // hiên
  for (const x of [-4.6, -1.6, 1.6, 4.6]) cyl(g, 0.12, 0.12, 2.6, 0x6b4a2b, x, 1.3, -21.4);
  box(g, 1.2, 2.0, 0.1, 0x5b3a1e, 0, 1.0, -22.45); // cửa
  box(g, 1.0, 0.9, 0.1, 0x5b3a1e, -3, 1.5, -22.45);
  box(g, 1.0, 0.9, 0.1, 0x5b3a1e, 3, 1.5, -22.45);
  const roofShape = new THREE.Shape();
  roofShape.moveTo(-3.8, 0); roofShape.lineTo(3.8, 0); roofShape.lineTo(0, 1.9); roofShape.lineTo(-3.8, 0);
  const roofGeo = new THREE.ExtrudeGeometry(roofShape, { depth: 11.2, bevelEnabled: false });
  roofGeo.rotateY(Math.PI / 2);
  roofGeo.translate(-5.6, 0, 0);
  const roof = new THREE.Mesh(roofGeo, mat(0x9a4a2a));
  roof.position.set(0, 2.6, -25.2);
  roof.castShadow = true;
  g.add(roof);
  // Võng (hammock) on the porch
  const ham = new THREE.Mesh(new THREE.CylinderGeometry(0.35, 0.35, 1.8, 10, 1, true, 0, Math.PI), mat(0x3d6fa8, { side: THREE.DoubleSide }));
  ham.rotation.z = Math.PI / 2;
  ham.rotation.x = Math.PI;
  ham.position.set(P.hammock[0], 0.85, P.hammock[1]);
  g.add(ham);
  scene.add(g);
}

function buildProps(scene) {
  const h = {};
  // Cửa cống (sluice gate) on the west bund
  const gateFrame = new THREE.Group();
  box(gateFrame, 0.15, 1.0, 0.15, 0x6b4a2b, 0, 0.2, -0.55);
  box(gateFrame, 0.15, 1.0, 0.15, 0x6b4a2b, 0, 0.2, 0.55);
  box(gateFrame, 0.15, 0.12, 1.25, 0x6b4a2b, 0, 0.7, 0);
  h.gate = box(gateFrame, 0.08, 0.6, 0.95, 0x8a6a3a, 0, -0.05, 0);
  gateFrame.position.set(P.gate[0], 0, P.gate[1]);
  scene.add(gateFrame);
  // Rãnh xả (drain) on the east bund: a plug of earth that can be dug out
  h.drainPlug = box(scene, 0.85, 0.45, 0.7, 0x7d6a3e, P.drain[0], -0.08, P.drain[1], { shadow: false });

  // Cọc tre bẫy ốc with egg clusters
  h.eggs = [];
  for (const [x, z] of STAKES) {
    cyl(scene, 0.035, 0.04, 1.4, 0xb9a46a, x, FIELD.y + 0.6, z, 6);
    const egg = new THREE.Mesh(new THREE.SphereGeometry(0.07, 8, 6), mat(0xe2437a));
    egg.scale.set(1, 1.8, 1);
    egg.position.set(x + 0.05, FIELD.y + 0.55, z);
    egg.visible = false;
    scene.add(egg);
    h.eggs.push(egg);
  }

  // Thùng đập lúa (threshing barrel)
  const barrel = new THREE.Group();
  const drum = new THREE.Mesh(new THREE.CylinderGeometry(0.55, 0.5, 0.95, 14, 1, true), mat(0x7a5a35, { side: THREE.DoubleSide }));
  drum.position.y = 0.48;
  barrel.add(drum);
  box(barrel, 0.9, 0.05, 0.6, 0xc9b27a, 0, 0.9, -0.2); // nan tre
  h.barrelGrain = new THREE.Mesh(new THREE.CylinderGeometry(0.5, 0.5, 0.05, 14), mat(0xd8b24a));
  h.barrelGrain.position.y = 0.05;
  barrel.add(h.barrelGrain);
  h.barrelSheaves = new THREE.Group();
  barrel.add(h.barrelSheaves);
  barrel.position.set(P.barrel[0], 0, P.barrel[1]);
  barrel.traverse(o => { if (o.isMesh) o.castShadow = true; });
  scene.add(barrel);

  // Bạt (tarp roll) and gạch (brick pile)
  const roll = cyl(scene, 0.2, 0.2, 1.6, 0x2f6fd0, P.tarpRoll[0], 0.2, P.tarpRoll[1], 10);
  roll.rotation.z = Math.PI / 2;
  h.tarpRoll = roll;
  for (let i = 0; i < 8; i++) box(scene, 0.25, 0.08, 0.12, 0xa84a2a, P.brickPile[0] + (i % 2) * 0.27, 0.04 + Math.floor(i / 2) * 0.08, P.brickPile[1]);
  h.cornerBricks = CORNERS.map(([x, z]) => {
    const b = box(scene, 0.25, 0.1, 0.12, 0xa84a2a, x, 0.12, z);
    b.visible = false;
    return b;
  });
  h.cornerMarks = CORNERS.map(([x, z]) => {
    const m = new THREE.Mesh(new THREE.RingGeometry(0.18, 0.24, 16), new THREE.MeshBasicMaterial({ color: 0xffe08a, transparent: true, opacity: 0.6 }));
    m.rotation.x = -Math.PI / 2;
    m.position.set(x, 0.04, z);
    m.visible = false;
    scene.add(m);
    return m;
  });
  const tarpGeo = new THREE.PlaneGeometry(TARP.x1 - TARP.x0 + 0.4, TARP.z1 - TARP.z0 + 0.4, 8, 8);
  tarpGeo.rotateX(-Math.PI / 2);
  h.tarp = new THREE.Mesh(tarpGeo, new THREE.MeshLambertMaterial({ color: 0x2f6fd0, side: THREE.DoubleSide }));
  h.tarp.position.set((TARP.x0 + TARP.x1) / 2, 0.6, (TARP.z0 + TARP.z1) / 2);
  h.tarp.visible = false;
  scene.add(h.tarp);

  // Thúng ngâm thóc + vạt mạ
  const basket = new THREE.Mesh(new THREE.CylinderGeometry(0.45, 0.35, 0.35, 12, 1, true), mat(0xb9965a, { side: THREE.DoubleSide }));
  basket.position.set(P.basket[0], 0.18, P.basket[1]);
  scene.add(basket);
  h.basketWater = new THREE.Mesh(new THREE.CircleGeometry(0.42, 12), mat(0x7c9aa0));
  h.basketWater.rotation.x = -Math.PI / 2;
  h.basketWater.position.set(P.basket[0], 0.28, P.basket[1]);
  h.basketWater.visible = false;
  scene.add(h.basketWater);
  box(scene, 4, 0.12, 3, 0x5a4026, P.nursery[0], 0.06, P.nursery[1], { shadow: false });
  const seedGeo = new THREE.ConeGeometry(0.04, 0.3, 4);
  h.seedlings = new THREE.InstancedMesh(seedGeo, mat(0x8ccf4a), 300);
  for (let i = 0; i < 300; i++) {
    m4.makeTranslation(P.nursery[0] - 1.8 + Math.random() * 3.6, 0.2, P.nursery[1] - 1.3 + Math.random() * 2.6);
    h.seedlings.setMatrixAt(i, m4);
  }
  h.seedlings.scale.set(1, 0.01, 1);
  scene.add(h.seedlings);

  // Chuồng vịt (duck pen) with a gate on its west side
  const fenceC = 0xa08a5a;
  const pen = DUCK_PEN;
  const pcx = (pen.x0 + pen.x1) / 2, pcz = (pen.z0 + pen.z1) / 2;
  box(scene, pen.x1 - pen.x0, 0.6, 0.06, fenceC, pcx, 0.3, pen.z0);
  box(scene, pen.x1 - pen.x0, 0.6, 0.06, fenceC, pcx, 0.3, pen.z1);
  box(scene, 0.06, 0.6, pen.z1 - pen.z0, fenceC, pen.x1, 0.3, pcz);
  box(scene, 0.06, 0.6, 1.2, fenceC, pen.x0, 0.3, pen.z0 + 0.6);
  box(scene, 0.06, 0.6, 1.2, fenceC, pen.x0, 0.3, pen.z1 - 0.6);
  const duckGate = new THREE.Group();
  const leaf = box(duckGate, 0.06, 0.6, 1.6, 0xc0a060, 0, 0.3, 0.8);
  leaf.position.z = 0.8;
  duckGate.position.set(pen.x0, 0, pen.z0 + 1.2);
  scene.add(duckGate);
  h.duckGate = duckGate;
  const roofPen = box(scene, 2, 0.08, 2, 0x8a7a50, pen.x1 - 1, 1.0, pen.z0 + 1);
  for (const [dx, dz] of [[-0.9, -0.9], [0.9, -0.9], [-0.9, 0.9], [0.9, 0.9]]) cyl(scene, 0.04, 0.04, 1, 0x6b4a2b, roofPen.position.x + dx, 0.5, roofPen.position.z + dz, 5);
  h.duckEggs = new THREE.Group();
  for (let i = 0; i < 8; i++) {
    const e = new THREE.Mesh(new THREE.SphereGeometry(0.05, 8, 6), mat(0xf6f1e4));
    e.scale.y = 1.3;
    e.position.set(pen.x1 - 1.4 + (i % 4) * 0.2, 0.06, pen.z0 + 0.6 + Math.floor(i / 4) * 0.2);
    e.visible = false;
    h.duckEggs.add(e);
  }
  scene.add(h.duckEggs);

  // Chuồng lợn, máng ăn, hầm biogas, bếp củi, thớt
  box(scene, 4, 0.8, 0.12, 0x8d8d86, P.pig[0], 0.4, P.pig[1] - 2);
  box(scene, 4, 0.8, 0.12, 0x8d8d86, P.pig[0], 0.4, P.pig[1] + 2);
  box(scene, 0.12, 0.8, 4, 0x8d8d86, P.pig[0] - 2, 0.4, P.pig[1]);
  box(scene, 0.12, 0.8, 4, 0x8d8d86, P.pig[0] + 2, 0.4, P.pig[1]);
  box(scene, 4.4, 0.1, 2.4, 0x9a4a2a, P.pig[0], 1.7, P.pig[1] - 1.1);
  const pig = new THREE.Group();
  const pb = new THREE.Mesh(new THREE.SphereGeometry(0.45, 10, 8), mat(0x3a3434));
  pb.scale.set(1.5, 0.9, 0.9);
  pig.add(pb);
  const snout = new THREE.Mesh(new THREE.CylinderGeometry(0.12, 0.14, 0.15, 8), mat(0x6a5a5a));
  snout.rotation.z = Math.PI / 2;
  snout.position.set(0.7, 0, 0);
  pig.add(snout);
  pig.position.set(P.pig[0] + 0.5, 0.45, P.pig[1]);
  pig.traverse(o => { if (o.isMesh) o.castShadow = true; });
  scene.add(pig);
  h.pig = pig;
  box(scene, 0.4, 0.25, 1.2, 0x8d8d86, P.trough[0], 0.12, P.trough[1]);
  const dome = new THREE.Mesh(new THREE.SphereGeometry(1.2, 14, 8, 0, Math.PI * 2, 0, Math.PI / 2), mat(0x9a9a92));
  dome.position.set(P.biogas[0], 0, P.biogas[1]);
  scene.add(dome);
  cyl(scene, 0.05, 0.05, 1.2, 0x333333, P.biogas[0], 1.6, P.biogas[1], 6);
  // Bếp củi: kiềng 3 chân + nồi
  box(scene, 1.4, 0.4, 1, 0x6e5a48, P.stove[0], 0.2, P.stove[1]);
  h.pot = cyl(scene, 0.3, 0.25, 0.35, 0x2a2a2a, P.stove[0], 0.58, P.stove[1], 12);
  box(scene, 0.8, 0.08, 0.5, 0x8a6a3a, P.board[0], 0.6, P.board[1]);
  cyl(scene, 0.05, 0.05, 0.56, 0x6b4a2b, P.board[0], 0.28, P.board[1], 5);
  // Rổ bèo by the pond
  const pondBasket = new THREE.Mesh(new THREE.CylinderGeometry(0.3, 0.22, 0.25, 10, 1, true), mat(0xb9965a, { side: THREE.DoubleSide }));
  pondBasket.position.set(P.pondEdge[0] + 0.5, 0.13, P.pondEdge[1] + 0.8);
  scene.add(pondBasket);

  // Trâu (buffalo) waiting by the field
  const buff = new THREE.Group();
  const bb = new THREE.Mesh(new THREE.BoxGeometry(1.8, 0.9, 0.8), mat(0x3b3836));
  bb.position.y = 1.0;
  buff.add(bb);
  const bh = new THREE.Mesh(new THREE.BoxGeometry(0.5, 0.45, 0.45), mat(0x3b3836));
  bh.position.set(1.1, 1.2, 0);
  buff.add(bh);
  for (const s of [-1, 1]) {
    const horn = new THREE.Mesh(new THREE.TorusGeometry(0.28, 0.04, 6, 10, Math.PI), mat(0xd8d0bc));
    horn.position.set(1.1, 1.45, s * 0.12);
    horn.rotation.y = Math.PI / 2;
    buff.add(horn);
  }
  for (const [dx, dz] of [[-0.7, -0.3], [-0.7, 0.3], [0.7, -0.3], [0.7, 0.3]]) {
    const leg = new THREE.Mesh(new THREE.BoxGeometry(0.16, 0.6, 0.16), mat(0x3b3836));
    leg.position.set(dx, 0.3, dz);
    buff.add(leg);
  }
  buff.position.set(P.buffalo[0], 0, P.buffalo[1]);
  buff.rotation.y = 0.3;
  buff.traverse(o => { if (o.isMesh) o.castShadow = true; });
  scene.add(buff);
  return h;
}

const m4 = new THREE.Matrix4();

function buildTrees(scene) {
  const rnd = (a, b) => a + Math.random() * (b - a);
  const bamboo = (x, z) => {
    for (let i = 0; i < 9; i++) {
      const hgt = rnd(5, 8);
      const c = cyl(scene, 0.06, 0.08, hgt, 0x7aa04a, x + rnd(-0.8, 0.8), hgt / 2, z + rnd(-0.8, 0.8), 6);
      c.rotation.z = rnd(-0.12, 0.12);
      c.rotation.x = rnd(-0.12, 0.12);
    }
    const crown = new THREE.Mesh(new THREE.SphereGeometry(2.2, 8, 6), mat(0x5d8a35));
    crown.scale.y = 1.4;
    crown.position.set(x, 6.5, z);
    crown.castShadow = true;
    scene.add(crown);
  };
  const banana = (x, z) => {
    cyl(scene, 0.15, 0.2, 2.2, 0x8a9a5a, x, 1.1, z, 7);
    for (let i = 0; i < 6; i++) {
      const leaf = new THREE.Mesh(new THREE.PlaneGeometry(0.5, 1.8), mat(0x6aa040, { side: THREE.DoubleSide }));
      const a = (i / 6) * Math.PI * 2;
      leaf.position.set(x + Math.cos(a) * 0.6, 2.3, z + Math.sin(a) * 0.6);
      leaf.rotation.set(-1.1, -a + Math.PI / 2, 0, 'YXZ');
      leaf.castShadow = true;
      scene.add(leaf);
    }
  };
  const palm = (x, z) => {
    const hgt = rnd(6, 8);
    const t = cyl(scene, 0.15, 0.22, hgt, 0x8a7a5a, x, hgt / 2, z, 7);
    t.rotation.z = rnd(-0.1, 0.1);
    for (let i = 0; i < 7; i++) {
      const leaf = new THREE.Mesh(new THREE.PlaneGeometry(0.6, 3), mat(0x4f8a3a, { side: THREE.DoubleSide }));
      const a = (i / 7) * Math.PI * 2;
      leaf.position.set(x + Math.cos(a) * 1.2, hgt - 0.3, z + Math.sin(a) * 1.2);
      leaf.rotation.set(-1.25, -a + Math.PI / 2, 0, 'YXZ');
      scene.add(leaf);
    }
  };
  [[-24, -30], [24, -26], [-26, 18], [20, 22], [26, -6], [-6, -34], [10, -33]].forEach(([x, z]) => bamboo(x, z));
  [[8, -24], [11, -23], [-12, -18], [17, -12], [-15, 3]].forEach(([x, z]) => banana(x, z));
  [[-8, -30], [7, -29], [-14, 14], [15, -2], [22, 12], [-24, -18]].forEach(([x, z]) => palm(x, z));

  // Núi đá vôi far away
  for (let i = 0; i < 14; i++) {
    const a = (i / 14) * Math.PI * 2 + rnd(-0.1, 0.1);
    const r = rnd(95, 130);
    const hgt = rnd(18, 40);
    const m = new THREE.Mesh(new THREE.ConeGeometry(rnd(10, 18), hgt, 6), mat(0x6f8a6a, { flatShading: true }));
    m.position.set(Math.cos(a) * r, hgt / 2 - 2, Math.sin(a) * r);
    m.rotation.y = rnd(0, 3);
    scene.add(m);
  }
  // Distant paddies: flat green squares around the farm
  const distGeo = new THREE.PlaneGeometry(14, 14);
  distGeo.rotateX(-Math.PI / 2);
  const greens = [0x7fb24a, 0x9cc45a, 0x6e9e40, 0xb7c46a];
  for (let gx = -4; gx <= 4; gx++) {
    for (let gz = -4; gz <= 4; gz++) {
      if ((Math.abs(gx) <= 2 && Math.abs(gz) <= 2) || gx === -1) continue;
      const m = new THREE.Mesh(distGeo, mat(greens[(gx * 7 + gz * 3 + 40) % 4]));
      m.position.set(gx * 16, 0.02, gz * 16);
      scene.add(m);
    }
  }
}

export function buildWorld(scene) {
  const ground = buildGround(scene);
  buildHouse(scene);
  const props = buildProps(scene);
  buildTrees(scene);
  return { ...ground, ...props };
}
