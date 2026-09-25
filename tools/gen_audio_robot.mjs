#!/usr/bin/env node
// tools/gen_audio_robot.mjs: offline synth for the surgical robot (scripts/robot/).
//
//   node tools/gen_audio_robot.mjs          # write audio/sfx/robot_*.wav
//   node tools/gen_audio_robot.mjs --check  # render and report, write nothing
//
// Same style as gen_audio.mjs: dependency-free, one seeded PRNG stream per file, so re-running
// produces byte-identical output.
//
//   robot_plug          the core going into its socket: a heavy clunk, a latch, a spark
//   robot_boot          the robot waking: a rising whine, servo stutters, three chimes
//   robot_link          someone remotes in: a quick rising two-note blip with a hiss of static
//   robot_unlink        and out again: the same, falling
//   robot_denied        P with no power (or in use): a low double buzz
//   robot_servo_01..03  an arm moving: a short geared whirr

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
    const w = TAU * Math.min(f, SR * 0.45) / SR, cw = Math.cos(w), al = Math.sin(w) / (2 * Q);
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

// A metal clunk at `at` seconds: a low body thump and a ringing steel partial.
function clunk(b, r, at, weight) {
  const lp = biquad('lowpass', 1200, 0.8);
  const s0 = Math.round(at * SR);
  let ph = 0, ph2 = 0;
  for (let i = 0; i < Math.round(0.35 * SR); i++) {
    const t = i / SR;
    const f = 70 + 120 * Math.exp(-t * 40.0);
    ph += TAU * f / SR;
    ph2 += TAU * 1730 / SR;
    const env = Math.min(1, t / 0.002) * Math.exp(-t * 16.0);
    const ring = Math.sin(ph2) * Math.exp(-t * 22.0) * 0.18;
    const noise = lp(r() * 2 - 1) * Math.exp(-t * 50.0) * 0.7;
    b.add(s0 + i, (Math.sin(ph) * env + ring + noise) * weight);
  }
}

// A short sine blip.
function blip(b, at, f, dur, vol) {
  const s0 = Math.round(at * SR);
  let ph = 0;
  for (let i = 0; i < Math.round(dur * SR); i++) {
    const t = i / SR;
    ph += TAU * f / SR;
    const env = Math.min(1, t / 0.004) * Math.min(1, (dur - t) / 0.02);
    b.add(s0 + i, (Math.sin(ph) * 0.8 + Math.sin(ph * 2) * 0.15) * env * vol);
  }
}

function plug() {
  const r = rngFor('plug'), b = new Buf(0.9);
  clunk(b, r, 0.0, 1.0);
  clunk(b, r, 0.12, 0.45);   // the latch
  // The spark: a crackle of high noise that fades.
  const hp = biquad('highpass', 2500, 0.7);
  for (let i = Math.round(0.14 * SR); i < b.d.length; i++) {
    const t = i / SR - 0.14;
    const crack = r() < 0.08 ? (r() * 2 - 1) : 0;
    b.add(i, hp(crack + (r() * 2 - 1) * 0.1) * Math.exp(-t * 7.0) * 0.5);
  }
  return b;
}

function boot() {
  const r = rngFor('boot'), b = new Buf(2.6);
  let ph = 0, ph2 = 0;
  const bp = biquad('bandpass', 400, 2.0);
  for (let i = 0; i < b.d.length; i++) {
    const t = i / SR;
    // The whine: a slow sweep up, then it settles into a hum.
    const k = Math.min(1, t / 1.6);
    const f = 70 + 780 * Math.pow(k, 1.6);
    ph += TAU * f / SR;
    ph2 += TAU * f * 0.5 / SR;
    const env = Math.min(1, t / 0.3) * (t < 2.0 ? 1 : Math.max(0, 1 - (t - 2.0) / 0.6));
    const whine = (Math.sin(ph) * 0.35 + Math.tanh(Math.sin(ph2) * 2.0) * 0.2) * env;
    // Servo stutters: a gated noise band through the middle of the sweep.
    const gate = (t > 0.5 && t < 1.5 && Math.sin(t * 38.0) > 0.2) ? 1 : 0;
    const servo = bp(r() * 2 - 1, 300 + 900 * k) * gate * 0.5;
    b.add(i, whine * 0.6 + servo);
  }
  blip(b, 1.75, 660, 0.12, 0.35);
  blip(b, 1.92, 880, 0.12, 0.35);
  blip(b, 2.09, 1320, 0.22, 0.4);
  return b;
}

function link(up) {
  const r = rngFor(up ? 'link' : 'unlink'), b = new Buf(0.4);
  const hp = biquad('highpass', 3000, 0.7);
  for (let i = 0; i < b.d.length; i++) {
    const t = i / SR;
    b.add(i, hp(r() * 2 - 1) * Math.exp(-t * 14.0) * 0.25);
  }
  const lo = up ? 740 : 1110, hi = up ? 1110 : 740;
  blip(b, 0.02, lo, 0.09, 0.5);
  blip(b, 0.13, hi, 0.14, 0.5);
  return b;
}

function denied() {
  const r = rngFor('denied'), b = new Buf(0.42);
  for (const at of [0.0, 0.2]) {
    const s0 = Math.round(at * SR);
    let ph = 0;
    for (let i = 0; i < Math.round(0.15 * SR); i++) {
      const t = i / SR;
      ph += TAU * 140 / SR;
      const env = Math.min(1, t / 0.005) * Math.min(1, (0.15 - t) / 0.02);
      b.add(s0 + i, Math.tanh(Math.sin(ph) * 4.0) * env * 0.5 + (r() * 2 - 1) * env * 0.04);
    }
  }
  return b;
}

function servo(variant) {
  const r = rngFor('servo' + variant), b = new Buf(0.3 + variant * 0.08);
  const f0 = 520 + variant * 110, f1 = f0 * (variant === 2 ? 0.7 : 1.35);
  const bp = biquad('bandpass', f0, 3.0);
  let ph = 0;
  for (let i = 0; i < b.d.length; i++) {
    const t = i / SR;
    const k = t / (b.d.length / SR);
    const f = f0 + (f1 - f0) * k;
    ph += TAU * f / SR;
    // Gear teeth: the tone chopped at a fast rate, with a noise band riding on it.
    const teeth = 0.6 + 0.4 * Math.sign(Math.sin(ph * 0.125));
    const env = Math.min(1, t / 0.03) * Math.min(1, (1 - k) / 0.15);
    const tone = Math.tanh(Math.sin(ph) * 2.5) * 0.3 * teeth;
    const grit = bp(r() * 2 - 1, f) * 0.6;
    b.add(i, (tone + grit) * env);
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
  'robot_plug.wav': [() => plug(), -3],
  'robot_boot.wav': [() => boot(), -4],
  'robot_link.wav': [() => link(true), -8],
  'robot_unlink.wav': [() => link(false), -8],
  'robot_denied.wav': [() => denied(), -9],
  'robot_servo_01.wav': [() => servo(1), -10],
  'robot_servo_02.wav': [() => servo(2), -10],
  'robot_servo_03.wav': [() => servo(3), -10],
};

fs.mkdirSync(OUT, { recursive: true });
for (const [name, [build, db]] of Object.entries(FILES)) {
  writeWav(path.join(OUT, name), build(), db);
}
