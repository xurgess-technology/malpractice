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
//   personnel_vein_scan      the vein machine reading a palm: a contact click, then a rising
//                            shimmering sweep with a mains hum under it (scripts/personnel/vein_machine.gd)
//   personnel_vein_grow      the veins creeping across its screen: a wet, crackling rustle that
//                            swells and ends on two soft heartbeats
//   personnel_vein_unlock    blood let into a skill: a heartbeat thump and a liquid rush

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

// The vein machine. One-shots, so these get a fade at each end (see ONE_SHOTS below).
function env(t, a, d, total) {
  return Math.min(1, t / a) * Math.min(1, Math.max(0, (total - t) / d));
}

function veinScan() {
  const rnd = rngFor('vein_scan');
  const secs = 1.45;
  const out = new Buf(secs);
  const hp = biquad('highpass', 900, 0.7);
  let ph = 0, ph2 = 0;
  for (let i = 0; i < out.d.length; i++) {
    const t = i / SR;
    // The palm going down on the glass: a short damped knock.
    const knock = Math.exp(-t * 60) * Math.sin(TAU * 180 * t) * 0.9 + hp(rnd() * 2 - 1) * Math.exp(-t * 200) * 0.5;
    // The read: a sweep from 320 Hz to 980 Hz, shimmering, fading in after the knock.
    const k = Math.min(1, Math.max(0, (t - 0.12) / 1.15));
    const f = 320 + 660 * k * k;
    ph += TAU * f / SR;
    ph2 += TAU * f * 2.01 / SR;
    const shimmer = 0.75 + 0.25 * Math.sin(TAU * 17 * t);
    const sweep = (Math.sin(ph) * 0.5 + Math.sin(ph2) * 0.18) * shimmer * env(t - 0.12, 0.15, 0.25, secs - 0.12) * (t > 0.12 ? 1 : 0);
    const hum = (Math.sin(TAU * 60 * t) * 0.5 + Math.sin(TAU * 120 * t) * 0.25) * 0.22 * env(t, 0.1, 0.3, secs);
    out.d[i] = knock + sweep * 0.55 + hum;
  }
  return out;
}

function veinGrow() {
  const rnd = rngFor('vein_grow');
  const secs = 2.3;
  const out = new Buf(secs);
  const bp = biquad('bandpass', 300, 1.2);
  const lp = biquad('lowpass', 2400, 0.7);
  let crack = 0;
  for (let i = 0; i < out.d.length; i++) {
    const t = i / SR;
    const k = t / secs;
    // A creeping rustle: noise through a band that climbs as the veins spread.
    const rustle = bp(rnd() * 2 - 1, 220 + 520 * k) * 1.6 * env(t, 0.35, 0.5, secs) * (0.6 + 0.4 * Math.sin(TAU * 3.3 * t) ** 2);
    // Wet crackles, thicker in the middle.
    if (rnd() < 0.0009 * (0.4 + Math.sin(Math.PI * k))) crack = rnd.range(0.4, 1);
    crack *= 0.985;
    const wet = lp((rnd() * 2 - 1) * crack) * 0.8;
    // Two soft heartbeats as it finishes.
    let beat = 0;
    for (const bt of [1.7, 1.95]) {
      const u = t - bt;
      if (u > 0) beat += Math.sin(TAU * (58 - 20 * u) * u) * Math.exp(-u * 16) * 0.9;
    }
    out.d[i] = rustle * 0.6 + wet + beat;
  }
  return out;
}

function veinUnlock() {
  const rnd = rngFor('vein_unlock');
  const secs = 0.95;
  const out = new Buf(secs);
  const bp = biquad('bandpass', 1200, 2.0);
  for (let i = 0; i < out.d.length; i++) {
    const t = i / SR;
    // Lub-dub.
    let beat = 0;
    for (const [bt, amp] of [[0.0, 1.0], [0.2, 0.7]]) {
      const u = t - bt;
      if (u > 0) beat += Math.sin(TAU * (62 - 25 * u) * u) * Math.exp(-u * 14) * amp;
    }
    // The rush of blood into the vein: a band of noise falling in pitch.
    const f = 1300 * Math.exp(-t * 2.6) + 180;
    const rush = bp(rnd() * 2 - 1, f) * 2.2 * env(t - 0.05, 0.08, 0.4, secs - 0.05) * (t > 0.05 ? 1 : 0);
    out.d[i] = beat + rush * 0.5;
  }
  return out;
}

const FILES = {
  'personnel_shower_water.wav': () => showerWater(),
  'personnel_vein_scan.wav': () => veinScan(),
  'personnel_vein_grow.wav': () => veinGrow(),
  'personnel_vein_unlock.wav': () => veinUnlock(),
};
// Everything but the loop gets a few milliseconds of fade at each end.
const ONE_SHOTS = new Set(['personnel_vein_scan.wav', 'personnel_vein_grow.wav', 'personnel_vein_unlock.wav']);

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
  const fade = ONE_SHOTS.has(path.basename(file)) ? Math.round(0.006 * SR) : 0;
  for (let i = 0; i < n; i++) {
    const edge = fade > 0 ? Math.min(1, i / fade, (n - 1 - i) / fade) : 1;
    const v = Math.max(-1, Math.min(1, buf.d[i] * k * edge));
    out.writeInt16LE(Math.round(v * 32767), 44 + i * 2);
  }
  if (!DRY) fs.writeFileSync(file, out);
  console.log(`${DRY ? '[check] ' : ''}${path.basename(file).padEnd(34)} ${(n / SR).toFixed(2)} s  ${out.length} bytes`);
}

fs.mkdirSync(OUT, { recursive: true });
for (const [name, build] of Object.entries(FILES)) {
  writeWav(path.join(OUT, name), build(), -6);
}
