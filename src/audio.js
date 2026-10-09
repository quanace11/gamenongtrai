// Procedural sound: every effect is synthesised with WebAudio so the
// prototype ships without audio assets.

let ctx = null;
let master = null;
let noiseBuf = null;
const loops = {};

export function initAudio() {
  if (ctx) { ctx.resume(); return; }
  const AC = window.AudioContext || window.webkitAudioContext;
  if (!AC) return;
  ctx = new AC();
  master = ctx.createGain();
  master.gain.value = 0.7;
  master.connect(ctx.destination);
  noiseBuf = ctx.createBuffer(1, ctx.sampleRate * 2, ctx.sampleRate);
  const d = noiseBuf.getChannelData(0);
  for (let i = 0; i < d.length; i++) d[i] = Math.random() * 2 - 1;
}

function noise({ dur, type = 'bandpass', freq = 1000, freqEnd, q = 1, gain = 0.5, attack = 0.005, delay = 0 }) {
  if (!ctx) return;
  const t = ctx.currentTime + delay;
  const src = ctx.createBufferSource();
  src.buffer = noiseBuf;
  src.loop = true;
  const f = ctx.createBiquadFilter();
  f.type = type;
  f.frequency.setValueAtTime(freq, t);
  if (freqEnd) f.frequency.exponentialRampToValueAtTime(freqEnd, t + dur);
  f.Q.value = q;
  const g = ctx.createGain();
  g.gain.setValueAtTime(0.0001, t);
  g.gain.linearRampToValueAtTime(gain, t + attack);
  g.gain.exponentialRampToValueAtTime(0.0001, t + dur);
  src.connect(f).connect(g).connect(master);
  src.start(t, Math.random());
  src.stop(t + dur + 0.05);
}

function tone({ freq, freqEnd, dur, type = 'sine', gain = 0.3, attack = 0.01, delay = 0 }) {
  if (!ctx) return;
  const t = ctx.currentTime + delay;
  const o = ctx.createOscillator();
  o.type = type;
  o.frequency.setValueAtTime(freq, t);
  if (freqEnd) o.frequency.exponentialRampToValueAtTime(freqEnd, t + dur);
  const g = ctx.createGain();
  g.gain.setValueAtTime(0.0001, t);
  g.gain.linearRampToValueAtTime(gain, t + attack);
  g.gain.exponentialRampToValueAtTime(0.0001, t + dur);
  o.connect(g).connect(master);
  o.start(t);
  o.stop(t + dur + 0.05);
}

function loop(name, filterType, freq, q = 0.7) {
  if (!ctx) return null;
  if (loops[name]) return loops[name];
  const src = ctx.createBufferSource();
  src.buffer = noiseBuf;
  src.loop = true;
  const f = ctx.createBiquadFilter();
  f.type = filterType;
  f.frequency.value = freq;
  f.Q.value = q;
  const g = ctx.createGain();
  g.gain.value = 0;
  src.connect(f).connect(g).connect(master);
  src.start();
  loops[name] = { g, f };
  return loops[name];
}

export function setRain(level) {
  const l = loop('rain', 'highpass', 1200);
  if (l) l.g.gain.setTargetAtTime(level * 0.45, ctx.currentTime, 0.6);
}

export function setWind(level) {
  const l = loop('wind', 'lowpass', 400, 1.5);
  if (!l) return;
  l.g.gain.setTargetAtTime(level * 0.5, ctx.currentTime, 0.8);
  l.f.frequency.setTargetAtTime(250 + level * 500, ctx.currentTime, 1.5);
}

export const sfx = {
  thud(hard) {
    noise({ dur: 0.22, type: 'lowpass', freq: hard ? 700 : 350, gain: 0.9 });
    tone({ freq: hard ? 120 : 80, freqEnd: 40, dur: 0.18, gain: 0.5 });
    if (!hard) noise({ dur: 0.35, type: 'bandpass', freq: 250, freqEnd: 800, q: 4, gain: 0.3, delay: 0.05 });
  },
  squelch() { noise({ dur: 0.28, type: 'bandpass', freq: 280, freqEnd: 900, q: 5, gain: 0.35 }); },
  step() { noise({ dur: 0.07, type: 'lowpass', freq: 700, gain: 0.12 }); },
  swish() { // "xoẹt"
    noise({ dur: 0.2, type: 'highpass', freq: 2500, freqEnd: 7000, gain: 0.45, attack: 0.04 });
    noise({ dur: 0.12, type: 'bandpass', freq: 4000, q: 2, gain: 0.25, delay: 0.12 });
  },
  splash() { noise({ dur: 0.5, type: 'bandpass', freq: 900, freqEnd: 250, q: 1, gain: 0.5 }); },
  thunder(dist = 0) {
    noise({ dur: 3 + dist, type: 'lowpass', freq: 260 - dist * 60, freqEnd: 50, gain: 1.0 - dist * 0.25, attack: 0.05 + dist * 0.3 });
    tone({ freq: 55, freqEnd: 30, dur: 2.5, gain: 0.5 - dist * 0.15 });
  },
  quack() {
    const f = 480 + Math.random() * 120;
    tone({ freq: f, freqEnd: f * 0.7, dur: 0.12, type: 'sawtooth', gain: 0.06 });
    tone({ freq: f, freqEnd: f * 0.7, dur: 0.12, type: 'sawtooth', gain: 0.06, delay: 0.16 });
  },
  whistle() {
    tone({ freq: 1700, freqEnd: 2700, dur: 0.3, gain: 0.18 });
    tone({ freq: 2700, freqEnd: 1600, dur: 0.35, gain: 0.18, delay: 0.38 });
  },
  beat(accent) { tone({ freq: accent ? 990 : 660, dur: 0.06, type: 'triangle', gain: 0.12 }); },
  good() { tone({ freq: 880, freqEnd: 1320, dur: 0.12, type: 'triangle', gain: 0.12 }); },
  miss() { tone({ freq: 220, freqEnd: 160, dur: 0.15, type: 'square', gain: 0.06 }); },
  thresh() {
    tone({ freq: 140, freqEnd: 60, dur: 0.15, gain: 0.5 });
    for (let i = 0; i < 6; i++) noise({ dur: 0.05, type: 'highpass', freq: 3000 + Math.random() * 3000, gain: 0.12, delay: 0.05 + i * 0.03 });
  },
  rake() { noise({ dur: 0.3, type: 'bandpass', freq: 2200, freqEnd: 1600, q: 0.8, gain: 0.22, attack: 0.05 }); },
  frog() {
    const f = 260 + Math.random() * 260;
    tone({ freq: f, freqEnd: f * 0.75, dur: 0.06, type: 'square', gain: 0.035 });
    tone({ freq: f * 1.1, freqEnd: f * 0.8, dur: 0.07, type: 'square', gain: 0.035, delay: 0.09 });
  },
  cricket() { for (let i = 0; i < 3; i++) tone({ freq: 4200, dur: 0.03, type: 'sine', gain: 0.02, delay: i * 0.05 }); },
  bird() {
    const f = 2200 + Math.random() * 1500;
    tone({ freq: f, freqEnd: f * 1.4, dur: 0.08, gain: 0.04 });
    tone({ freq: f * 1.2, freqEnd: f * 0.9, dur: 0.1, gain: 0.04, delay: 0.12 });
  },
  pickup() { tone({ freq: 600, freqEnd: 900, dur: 0.08, type: 'triangle', gain: 0.1 }); },
  chop() { noise({ dur: 0.08, type: 'bandpass', freq: 1500, q: 2, gain: 0.5 }); tone({ freq: 200, freqEnd: 90, dur: 0.08, gain: 0.3 }); },
  tarp() { noise({ dur: 0.6, type: 'bandpass', freq: 1800, freqEnd: 600, q: 0.6, gain: 0.35, attack: 0.1 }); },
  oink() { tone({ freq: 220, freqEnd: 140, dur: 0.2, type: 'sawtooth', gain: 0.08 }); },
};
