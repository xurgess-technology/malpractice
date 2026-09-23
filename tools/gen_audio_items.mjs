// Sounds for items, the shelf and ceiling fixtures. Same deterministic, dependency-free
// approach as tools/gen_audio.mjs. Writes audio/sfx/items_*.wav and audio/sfx/buzz_*.wav.
//   node tools/gen_audio_items.mjs
//
//   quarters_scatter  POCKETS 2 phase 4: a thrown handful of quarters bursting across a hard floor
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const SR = 44100;
const TAU = Math.PI * 2;
const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const OUT = path.join(ROOT, 'audio', 'sfx');

function mulberry32(seed) {
  return () => {
    seed |= 0; seed = (seed + 0x6d2b79f5) | 0;
    let t = Math.imul(seed ^ (seed >>> 15), 1 | seed);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}
function rngFor(name) {
  let h = 2166136261;
  for (const c of name) { h ^= c.charCodeAt(0); h = Math.imul(h, 16777619); }
  return mulberry32(h >>> 0);
}

function writeWav(name, data) {
  let peak = 0;
  for (const v of data) peak = Math.max(peak, Math.abs(v));
  const gain = peak > 0 ? 0.708 / peak : 1; // about -3 dBFS
  const buf = Buffer.alloc(44 + data.length * 2);
  buf.write('RIFF', 0); buf.writeUInt32LE(36 + data.length * 2, 4); buf.write('WAVE', 8);
  buf.write('fmt ', 12); buf.writeUInt32LE(16, 16); buf.writeUInt16LE(1, 20); buf.writeUInt16LE(1, 22);
  buf.writeUInt32LE(SR, 24); buf.writeUInt32LE(SR * 2, 28); buf.writeUInt16LE(2, 32); buf.writeUInt16LE(16, 34);
  buf.write('data', 36); buf.writeUInt32LE(data.length * 2, 40);
  for (let i = 0; i < data.length; i++) {
    buf.writeInt16LE(Math.max(-32768, Math.min(32767, Math.round(data[i] * gain * 32767))), 44 + i * 2);
  }
  fs.writeFileSync(path.join(OUT, name + '.wav'), buf);
  console.log(`wrote ${name}.wav  ${(data.length / SR).toFixed(3)} s`);
}

// One-pole filters
function highpass(x, cutoff) {
  const rc = 1 / (TAU * cutoff), dt = 1 / SR, a = rc / (rc + dt);
  const y = new Float32Array(x.length); let px = 0, py = 0;
  for (let i = 0; i < x.length; i++) { y[i] = a * (py + x[i] - px); px = x[i]; py = y[i]; }
  return y;
}
function lowpass(x, cutoff) {
  const dt = 1 / SR, rc = 1 / (TAU * cutoff), a = dt / (rc + dt);
  const y = new Float32Array(x.length); let p = 0;
  for (let i = 0; i < x.length; i++) { p += a * (x[i] - p); y[i] = p; }
  return y;
}

// Glass: a sharp broadband crack, then a spray of tiny high ringing shards bouncing.
function glass(name) {
  const r = rngFor(name);
  const n = Math.floor(SR * 1.1);
  const x = new Float32Array(n);
  for (let i = 0; i < SR * 0.05; i++) x[i] += (r() * 2 - 1) * Math.exp(-i / (SR * 0.012));
  for (let k = 0; k < 38; k++) {
    const start = Math.floor((0.004 + Math.pow(r(), 1.6) * 0.7) * SR);
    const f = 2600 + r() * 5200, dec = 0.02 + r() * 0.07, amp = 0.15 + r() * 0.45;
    for (let i = 0; i < SR * dec * 4 && start + i < n; i++) {
      x[start + i] += Math.sin(TAU * f * i / SR) * Math.exp(-i / (SR * dec)) * amp * (1 - start / n);
    }
  }
  writeWav(name, highpass(x, 900));
}

// A small metal-on-steel clink for setting things down on the shelf.
function clink(name) {
  const r = rngFor(name);
  const n = Math.floor(SR * 0.45);
  const x = new Float32Array(n);
  const partials = [[1840, 1], [3120, 0.55], [4710, 0.3], [6200, 0.18]];
  for (const [f, a] of partials) {
    const ff = f * (0.97 + r() * 0.06);
    for (let i = 0; i < n; i++) x[i] += Math.sin(TAU * ff * i / SR) * a * Math.exp(-i / (SR * (0.09 / (a + 0.3))));
  }
  for (let i = 0; i < SR * 0.01; i++) x[i] += (r() * 2 - 1) * 0.6 * (1 - i / (SR * 0.01));
  writeWav(name, x);
}

// Fluorescent buzz: 120 Hz hum with harmonics and a crackly ballast edge; short, retriggerable.
function buzz(name, dur) {
  const r = rngFor(name);
  const n = Math.floor(SR * dur);
  const x = new Float32Array(n);
  for (let i = 0; i < n; i++) {
    const t = i / SR;
    let v = 0;
    for (let h = 1; h <= 7; h++) v += Math.sin(TAU * 120 * h * t + h) / (h * 1.3);
    v = Math.sign(v) * Math.pow(Math.abs(v), 0.6);
    const crackle = r() < 0.002 ? (r() * 2 - 1) * 2.5 : 0;
    const env = Math.min(1, t / 0.02) * Math.min(1, (dur - t) / 0.04);
    x[i] = (v * 0.35 + crackle) * env;
  }
  writeWav(name, lowpass(x, 5200));
}

// POCKETS 2 phase 4 (the Laundromat): a handful of quarters hitting a hard floor and going
// everywhere. One sharp burst of coins landing at once, then twenty-odd individual rings spraying
// out over the next second as each one bounces, spins down and rattles flat.
function quarters(name) {
  const r = rngFor(name);
  const dur = 1.5;
  const n = Math.floor(SR * dur);
  const x = new Float32Array(n);
  // One coin: a bright metallic ring made of a few inharmonic partials over a click.
  const coin = (at, amp, bright) => {
    const f0 = (2300 + r() * 1900) * bright;
    const parts = [[1.0, 1.0], [2.37, 0.5], [4.11, 0.24], [6.05, 0.11]];
    const len = Math.floor(SR * 0.26);
    for (let i = 0; i < len && at + i < n; i++) {
      const t = i / SR;
      let v = (r() * 2 - 1) * Math.exp(-t / 0.0012) * 0.5;   // the strike
      for (const [m, a] of parts) v += Math.sin(TAU * f0 * m * t) * a * Math.exp(-t / (0.055 / m));
      x[at + i] += v * amp;
    }
  };
  // The impact: most of the handful lands together.
  for (let k = 0; k < 9; k++) coin(Math.floor(SR * r() * 0.045), 0.55 + r() * 0.45, 0.85 + r() * 0.3);
  // Then the spray, thinning out and getting quieter as they scatter away.
  for (let k = 0; k < 24; k++) {
    const t = 0.05 + Math.pow(r(), 0.6) * 1.05;
    coin(Math.floor(SR * t), (0.42 - t * 0.24) * (0.5 + r() * 0.5), 0.9 + r() * 0.4);
  }
  // A couple of them spin down flat: a rattle that speeds up and dies.
  for (const [start, len] of [[0.34, 0.5], [0.72, 0.42]]) {
    const at = Math.floor(SR * start);
    const m = Math.floor(SR * len);
    let next = 0;
    for (let i = 0; i < m && at + i < n; i++) {
      const t = i / SR;
      if (i >= next) {
        const amp = 0.20 * (1 - t / len);
        for (let j = 0; j < SR * 0.004 && at + i + j < n; j++) {
          x[at + i + j] += (r() * 2 - 1) * Math.exp(-j / (SR * 0.0008)) * amp;
        }
        next = i + Math.max(1, Math.floor(SR * (0.075 * (1 - t / len) + 0.006)));
      }
    }
  }
  writeWav(name, highpass(x, 620));
}

fs.mkdirSync(OUT, { recursive: true });
glass('items_glass');
clink('items_clink_01');
clink('items_clink_02');
clink('items_clink_03');
buzz('buzz_01', 0.35);
buzz('buzz_02', 0.6);
buzz('buzz_03', 0.22);
quarters('quarters_scatter');
