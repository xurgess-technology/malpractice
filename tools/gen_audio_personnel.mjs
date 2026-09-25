#!/usr/bin/env node
// tools/gen_audio_personnel.mjs: offline synth for the personnel room's working fixtures.
//
//   node tools/gen_audio_personnel.mjs          # write audio/sfx/personnel_*.wav
//   node tools/gen_audio_personnel.mjs --check  # render and report, write nothing
//
// Same style as gen_audio_containers.mjs: dependency-free, one seeded PRNG stream per file, so
// re-running produces byte-identical output.
//
//   personnel_shower_water   sample-exact loop of falling water (looped by scripts/personnel/
//                            showers.gd, the same way containers_fridge_hum loops in med_fridge.gd)

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const SR = 44100;
const TAU = Math.PI * 2;
const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const OUT = path.join(ROOT, 'audio', 'sfx');
const DRY = process.argv.includes('--check');

function mulberry32(seed) {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}
function seedOf(name) {
  let h = 2166136261;
  for (let i = 0; i < name.length; i++) { h ^= name.charCodeAt(i); h = Math.imul(h, 16777619); }
  return h >>> 0;
}
function rngFor(name) {
  const r = mulberry32(seedOf(name));
  r.range = (a, b) => a + r() * (b - a);
  return r;
}

function biquad(type, f0, Q) {
  let b0, b1, b2, a1, a2, x1 = 0, x2 = 0, y1 = 0, y2 = 0, cur = -1;
  const set = (f) => {
    const w = TAU * Math.min(f, SR * 0.45) / SR, cw = Math.cos(w), al = Math.sin(w) / (2 * Q);
    let n0, n1, n2, d0, d1, d2;
    if (type === 'lowpass') { n0 = (1 - cw) / 2; n1 = 1 - cw; n2 = n0; }
    else if (type === 'highpass') { n0 = (1 + cw) / 2; n1 = -(1 + cw); n2 = n0; }
    else { n0 = al; n1 = 0; n2 = -al; }
    d0 = 1 + al; d1 = -2 * cw; d2 = 1 - al;
    b0 = n0 / d0; b1 = n1 / d0; b2 = n2 / d0; a1 = d1 / d0; a2 = d2 / d0; cur = f;
  };
  set(f0);
  return (x, f) => {
    if (f !== undefined && Math.abs(f - cur) > 1) set(f);
    const y = b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2;
    x2 = x1; x1 = x; y2 = y1; y1 = y;
    return y;
  };
}

/** Run a filter over a periodic buffer repeatedly so its state converges to the periodic steady
 *  state and the last pass's output loops without a seam (same trick as gen_audio.mjs's ambient
 *  loops: db_fan and the base hospital hum). */
function periodicFilter(arr, make, passes) {
  const f = make();
  let out = null;
  for (let p = 0; p < passes; p++) {
    const keep = p === passes - 1;
    if (keep) out = new Float32Array(arr.length);
    for (let i = 0; i < arr.length; i++) {
      const y = f(arr[i]);
      if (keep) out[i] = y;
    }
  }
  arr.set(out);
}

class Buf {
  constructor(sec) { this.d = new Float32Array(Math.round(sec * SR)); }
  peak() { let p = 0; for (const v of this.d) p = Math.max(p, Math.abs(v)); return p; }
}

// A seamless loop of falling water: broadband hiss (the spray leaving the head) mixed with a
// lower rush (the fall itself), under a slow, irregular gurgle so it never reads as a static
// texture. Every continuous frequency is a whole number of cycles per loop, and the base noise is
// crossfaded before filtering, so the buffer is exactly periodic (no click at the seam).
const WATER_SECONDS = 2.5;
function showerWater() {
  const rnd = rngFor('shower_water');
  const n = Math.round(WATER_SECONDS * SR);
  const snap = (f) => Math.max(1, Math.round(f * WATER_SECONDS)) / WATER_SECONDS;
  const base = new Float32Array(n);
  for (let i = 0; i < n; i++) base[i] = rnd() * 2 - 1;
  const xf = Math.round(0.4 * SR);
  for (let i = 0; i < xf; i++) {
    const k = i / xf;
    base[i] = base[i] * k + base[n - xf + i] * (1 - k);
  }
  const hiss = new Float32Array(base);
  periodicFilter(hiss, () => biquad('bandpass', 3600, 0.55), 3);
  const rush = new Float32Array(base);
  periodicFilter(rush, () => biquad('lowpass', 480, 0.7), 3);
  const lfoA = snap(0.55), lfoB = snap(1.65);
  const out = new Buf(WATER_SECONDS);
  for (let i = 0; i < n; i++) {
    const t = i / SR;
    const wobble = 1 + 0.12 * Math.sin(TAU * lfoA * t) + 0.07 * Math.sin(TAU * lfoB * t + 1.3);
    out.d[i] = (hiss[i] * 0.5 + rush[i] * 0.85) * wobble * 0.55;
  }
  return out;
}

const FILES = {
  'personnel_shower_water.wav': () => showerWater(),
};

function writeWav(file, buf, targetDb) {
  const p = buf.peak();
  const k = p > 0 ? Math.pow(10, targetDb / 20) / p : 1;
  const n = buf.d.length, bytes = n * 2;
  const out = Buffer.alloc(44 + bytes);
  out.write('RIFF', 0); out.writeUInt32LE(36 + bytes, 4); out.write('WAVE', 8);
  out.write('fmt ', 12); out.writeUInt32LE(16, 16); out.writeUInt16LE(1, 20); out.writeUInt16LE(1, 22);
  out.writeUInt32LE(SR, 24); out.writeUInt32LE(SR * 2, 28); out.writeUInt16LE(2, 32); out.writeUInt16LE(16, 34);
  out.write('data', 36); out.writeUInt32LE(bytes, 40);
  // No fade at the ends: this is a loop (loop_mode is set at load time by showers.gd), and a fade
  // here would put an audible dip at the seam every time round.
  for (let i = 0; i < n; i++) {
    const v = Math.max(-1, Math.min(1, buf.d[i] * k));
    out.writeInt16LE(Math.round(v * 32767), 44 + i * 2);
  }
  if (!DRY) fs.writeFileSync(file, out);
  console.log(`${DRY ? '[check] ' : ''}${path.basename(file).padEnd(34)} ${(n / SR).toFixed(2)} s  ${out.length} bytes`);
}

fs.mkdirSync(OUT, { recursive: true });
for (const [name, build] of Object.entries(FILES)) {
  writeWav(path.join(OUT, name), build(), -6);
}
