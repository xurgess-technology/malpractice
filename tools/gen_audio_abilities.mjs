#!/usr/bin/env node
// tools/gen_audio_abilities.mjs: offline synth for the two surgeon abilities (Echo and Hive Eyes).
//
//   node tools/gen_audio_abilities.mjs          # write audio/sfx/ability_*.wav
//   node tools/gen_audio_abilities.mjs --check  # render and report, write nothing
//
// Same style as gen_audio.mjs: dependency-free, one seeded PRNG stream per file, so re-running
// produces byte-identical output.
//
//   ability_shriek   Echo: a rising, throat-tearing shriek with a ringing tail
//   ability_hive_in  into a Hive's eyes: a sucking whoosh into a sick low drone
//   ability_hive_out back into your body: a snap and a falling breath

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
function rngFor(name) {
  let h = 2166136261;
  for (let i = 0; i < name.length; i++) { h ^= name.charCodeAt(i); h = Math.imul(h, 16777619); }
  const r = mulberry32(h >>> 0);
  r.range = (a, b) => a + r() * (b - a);
  return r;
}

function biquad(type, f0, Q) {
  let b0, b1, b2, a1, a2, x1 = 0, x2 = 0, y1 = 0, y2 = 0, cur = -1;
  const set = (f) => {
    const w = TAU * Math.max(20, Math.min(f, SR * 0.45)) / SR, cw = Math.cos(w), al = Math.sin(w) / (2 * Q);
    let n0, n1, n2;
    if (type === 'lowpass') { n0 = (1 - cw) / 2; n1 = 1 - cw; n2 = n0; }
    else if (type === 'highpass') { n0 = (1 + cw) / 2; n1 = -(1 + cw); n2 = n0; }
    else { n0 = al; n1 = 0; n2 = -al; }
    const d0 = 1 + al, d1 = -2 * cw, d2 = 1 - al;
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

class Buf {
  constructor(sec) { this.d = new Float32Array(Math.round(sec * SR)); }
  add(i, v) { if (i >= 0 && i < this.d.length) this.d[i] += v; }
  peak() { let p = 0; for (const v of this.d) p = Math.max(p, Math.abs(v)); return p; }
}

const env = (t, a, d) => Math.min(1, t / a) * Math.exp(-t * d);




function shriek() {
  const r = rngFor('shriek'), b = new Buf(2.1);
  // Two formants over a rough glottal source whose pitch climbs, wavers and breaks.
  const f1 = biquad('bandpass', 800, 5);
  const f2 = biquad('bandpass', 2400, 6);
  const f3 = biquad('bandpass', 3600, 8);
  const air = biquad('highpass', 2500, 0.7);
  let ph = 0, ph2 = 0, vib = 0;
  for (let i = 0; i < b.d.length; i++) {
    const t = i / SR;
    const e = Math.min(1, t / 0.06) * (t < 1.1 ? 1 : Math.exp(-(t - 1.1) * 3.2));
    vib += TAU * (7 + 5 * t) / SR;
    const pitch = 420 + 520 * Math.min(1, t / 0.5) + 60 * Math.sin(vib) + (r() - 0.5) * 60;
    ph += TAU * pitch / SR;
    ph2 += TAU * pitch * 1.013 / SR;
    const src = (((ph / TAU) % 1) * 2 - 1) * 0.6 + (((ph2 / TAU) % 1) * 2 - 1) * 0.4 + (r() * 2 - 1) * 0.35;
    let v = f1(src, 900 + 300 * Math.sin(t * 5)) * 1.1 + f2(src, 2300 + 400 * Math.min(1, t)) * 0.9 + f3(src) * 0.5;
    v += air(r() * 2 - 1) * 0.25;
    // A metallic ring under it: the echo part of Echo.
    v += Math.sin(TAU * 1760 * t + Math.sin(TAU * 3 * t) * 2) * 0.12 * Math.exp(-Math.max(0, t - 0.3) * 1.6) * Math.min(1, t / 0.3);
    b.add(i, Math.tanh(v * 1.6) * e);
  }
  return b;
}

function hiveIn() {
  const r = rngFor('hive_in'), b = new Buf(1.2);
  const sweep = biquad('bandpass', 300, 1.5);
  let a = 0, c = 0;
  for (let i = 0; i < b.d.length; i++) {
    const t = i / SR;
    const s = Math.min(1, t / 0.35);
    let v = sweep(r() * 2 - 1, 2400 - 2100 * s) * Math.sin(Math.PI * Math.min(1, t / 0.5)) * 0.9;
    a += TAU * 55 / SR;
    c += TAU * 55.9 / SR;
    const drone = (Math.sin(a) + Math.sin(c) + 0.4 * Math.sin(a * 3.01)) * 0.35;
    v += drone * Math.min(1, Math.max(0, t - 0.2) / 0.3) * Math.exp(-Math.max(0, t - 0.7) * 4);
    b.add(i, v);
  }
  return b;
}

function hiveOut() {
  const r = rngFor('hive_out'), b = new Buf(0.7);
  const lp = biquad('lowpass', 3000, 0.7);
  let ph = 0;
  for (let i = 0; i < b.d.length; i++) {
    const t = i / SR;
    ph += TAU * (900 * Math.exp(-t * 10) + 60) / SR;
    let v = Math.sin(ph) * env(t, 0.002, 12) * 0.6;
    v += lp(r() * 2 - 1, 3000 * Math.exp(-t * 4) + 200) * env(t, 0.02, 5) * 0.5;
    b.add(i, v);
  }
  return b;
}

function writeWav(file, buf, targetDb = -3) {
  const p = buf.peak();
  const k = p > 0 ? Math.pow(10, targetDb / 20) / p : 1;
  const n = buf.d.length, bytes = n * 2;
  const out = Buffer.alloc(44 + bytes);
  out.write('RIFF', 0); out.writeUInt32LE(36 + bytes, 4); out.write('WAVE', 8);
  out.write('fmt ', 12); out.writeUInt32LE(16, 16); out.writeUInt16LE(1, 20); out.writeUInt16LE(1, 22);
  out.writeUInt32LE(SR, 24); out.writeUInt32LE(SR * 2, 28); out.writeUInt16LE(2, 32); out.writeUInt16LE(16, 34);
  out.write('data', 36); out.writeUInt32LE(bytes, 40);
  for (let i = 0; i < n; i++) {
    let v = buf.d[i] * k;
    const edge = Math.min(i, n - 1 - i);
    if (edge < 132) v *= edge / 132;
    out.writeInt16LE(Math.round(Math.max(-1, Math.min(1, v)) * 32767), 44 + i * 2);
  }
  if (DRY) {
    console.log(`${path.basename(file)}  ${(n / SR).toFixed(2)} s  peak ${p.toFixed(2)}`);
    return;
  }
  fs.writeFileSync(file, out);
  console.log('wrote', path.relative(ROOT, file));
}

const FILES = {
  'ability_shriek.wav': [shriek, -2],
  'ability_hive_in.wav': [hiveIn, -6],
  'ability_hive_out.wav': [hiveOut, -7],
};

fs.mkdirSync(OUT, { recursive: true });
for (const [name, [build, db]] of Object.entries(FILES)) {
  writeWav(path.join(OUT, name), build(), db);
}
