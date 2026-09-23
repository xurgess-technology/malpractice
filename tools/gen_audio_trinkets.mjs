// TRINKETS chunk B (docs/ITEMS_AND_ICONS.md): the six trinkets' sounds. Same deterministic,
// dependency-free approach as tools/gen_audio.mjs. Writes audio/sfx/trinkets_*.wav.
//   node tools/gen_audio_trinkets.mjs
//
//   trinkets_phone_ring     one burst of an old bell desk phone (the decoy, every 1.5 s)
//   trinkets_phone_pick     the handset knocking down onto the cradle as you set it on the floor
//   trinkets_laptop_open    a lid, a fan spinning up and a tired boot chime
//   trinkets_defib_zap      the charge whine and the thump of the paddles
//   trinkets_heartbeat      lub-dub, low and wet: a tagged monster, heard through walls
//   trinkets_hammer_bonk    a rubber head on something that did not expect it
//   trinkets_clip_on        the pulse oximeter's plastic jaws snapping shut, then its own beep
//   trinkets_epipen         the spring, the click and the hiss of an auto-injector
//   trinkets_whistle        one long pea-whistle blast: two close tones beating, the pea warbling
//                           over them, and a tiled room ringing after it (POCKETS 2, the Natatorium)
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

function lowpass(x, cutoff) {
  const dt = 1 / SR, rc = 1 / (TAU * cutoff), a = dt / (rc + dt);
  const y = new Float32Array(x.length); let p = 0;
  for (let i = 0; i < x.length; i++) { p += a * (x[i] - p); y[i] = p; }
  return y;
}
function highpass(x, cutoff) {
  const rc = 1 / (TAU * cutoff), dt = 1 / SR, a = rc / (rc + dt);
  const y = new Float32Array(x.length); let px = 0, py = 0;
  for (let i = 0; i < x.length; i++) { y[i] = a * (py + x[i] - px); px = x[i]; py = y[i]; }
  return y;
}

// Two struck bells beating against each other, hammered about 22 times a second: a bell phone.
function phoneRing(name) {
  const r = rngFor(name);
  const dur = 1.15;
  const n = Math.floor(SR * dur);
  const x = new Float32Array(n);
  const hammer = 22;                     // strikes per second
  const strikes = Math.floor(dur * hammer);
  for (let k = 0; k < strikes; k++) {
    const start = Math.floor((k / hammer) * SR);
    const which = k % 2;
    const f = which ? 1055 : 1290;       // the two gongs
    const amp = 0.55 + r() * 0.12;
    for (let i = 0; i < SR * 0.09 && start + i < n; i++) {
      const t = i / SR;
      const env = Math.exp(-t / 0.026);
      x[start + i] += (Math.sin(TAU * f * t) + 0.5 * Math.sin(TAU * f * 2.01 * t) + 0.22 * Math.sin(TAU * f * 3.4 * t))
        * env * amp;
      if (i < SR * 0.001) x[start + i] += (r() * 2 - 1) * 0.5 * amp;   // the clapper itself
    }
  }
  // The whole burst swells in and stops dead, the way a bell phone does.
  for (let i = 0; i < n; i++) {
    const t = i / SR;
    x[i] *= Math.min(1, t / 0.02) * Math.min(1, (dur - t) / 0.05);
  }
  writeWav(name, highpass(x, 350));
}

// The handset and its cradle meeting a floor: a plastic knock with a half-hearted bell shiver.
function phonePick(name) {
  const r = rngFor(name);
  const n = Math.floor(SR * 0.5);
  const x = new Float32Array(n);
  for (let i = 0; i < SR * 0.03; i++) x[i] += (r() * 2 - 1) * Math.exp(-i / (SR * 0.006)) * 0.9;
  for (const [f, a, d] of [[210, 0.7, 0.07], [430, 0.4, 0.05], [1180, 0.25, 0.12]]) {
    for (let i = 0; i < n; i++) x[i] += Math.sin(TAU * f * i / SR) * a * Math.exp(-i / (SR * d));
  }
  const shiver = Math.floor(SR * 0.05);
  for (let i = shiver; i < n; i++) {
    x[i] += Math.sin(TAU * 1180 * (i - shiver) / SR) * 0.12 * Math.exp(-(i - shiver) / (SR * 0.09));
  }
  writeWav(name, lowpass(x, 6500));
}

// A lid, a fan finding its speed, and a boot chime that sags because the battery is nearly gone.
function laptopOpen(name) {
  const r = rngFor(name);
  const dur = 1.0;
  const n = Math.floor(SR * dur);
  const x = new Float32Array(n);
  for (let i = 0; i < SR * 0.05; i++) x[i] += (r() * 2 - 1) * Math.exp(-i / (SR * 0.01)) * 0.8;  // the hinge
  for (let i = 0; i < n; i++) {                                                                  // the fan
    const t = i / SR;
    const spin = Math.min(1, t / 0.45);
    x[i] += ((r() * 2 - 1) * 0.35 + Math.sin(TAU * (60 + 130 * spin) * t) * 0.2) * spin * Math.min(1, (dur - t) / 0.2);
  }
  const chime = Math.floor(SR * 0.22);                                                           // the chime, sagging
  for (let i = 0; chime + i < n; i++) {
    const t = i / SR;
    const f = 720 * (1 - 0.07 * Math.min(1, t / 0.5));
    x[chime + i] += (Math.sin(TAU * f * t) + 0.4 * Math.sin(TAU * f * 1.5 * t)) * 0.5 * Math.exp(-t / 0.28);
  }
  writeWav(name, lowpass(x, 8000));
}

// The capacitor whine climbing, a beat of nothing, then the paddles going off in somebody's chest.
function defibZap(name) {
  const r = rngFor(name);
  const dur = 2.1;
  const n = Math.floor(SR * dur);
  const x = new Float32Array(n);
  const charge = Math.floor(SR * 1.25);
  for (let i = 0; i < charge; i++) {
    const t = i / SR;
    const f = 520 + 900 * (t / (charge / SR)) ** 1.7;
    x[i] += Math.sin(TAU * f * t) * 0.28 * Math.min(1, t / 0.08);
    x[i] += Math.sin(TAU * f * 2 * t) * 0.09;
  }
  const hit = Math.floor(SR * 1.45);
  for (let i = 0; hit + i < n; i++) {
    const t = i / SR;
    const body = Math.sin(TAU * 62 * t) * Math.exp(-t / 0.13) + Math.sin(TAU * 41 * t) * 0.7 * Math.exp(-t / 0.3);
    const crack = (r() * 2 - 1) * Math.exp(-t / 0.012);
    x[hit + i] += body * 0.9 + crack * 0.85;
  }
  writeWav(name, x);
}

// Lub-dub. Two soft low thumps, the second smaller, with a wet edge: it is a monster's.
function heartbeat(name) {
  const r = rngFor(name);
  const n = Math.floor(SR * 0.55);
  const x = new Float32Array(n);
  const thump = (start, amp, f, dec) => {
    for (let i = 0; start + i < n; i++) {
      const t = i / SR;
      x[start + i] += (Math.sin(TAU * f * t) + 0.35 * Math.sin(TAU * f * 1.8 * t)) * amp * Math.exp(-t / dec);
      x[start + i] += (r() * 2 - 1) * amp * 0.25 * Math.exp(-t / (dec * 0.35));
    }
  };
  thump(0, 1.0, 52, 0.085);
  thump(Math.floor(SR * 0.17), 0.62, 44, 0.065);
  writeWav(name, lowpass(x, 420));
}

// A rubber head on a knee, a skull, a monster: a dull tap with a short rubbery ring.
function hammerBonk(name) {
  const r = rngFor(name);
  const n = Math.floor(SR * 0.3);
  const x = new Float32Array(n);
  for (let i = 0; i < SR * 0.02; i++) x[i] += (r() * 2 - 1) * Math.exp(-i / (SR * 0.004)) * 0.9;
  for (const [f, a, d] of [[168, 0.9, 0.045], [312, 0.45, 0.03], [605, 0.2, 0.018]]) {
    for (let i = 0; i < n; i++) x[i] += Math.sin(TAU * f * i / SR) * a * Math.exp(-i / (SR * d));
  }
  writeWav(name, lowpass(x, 2600));
}

// Plastic jaws snapping shut on something, then the little clip finding a pulse and beeping.
function clipOn(name) {
  const r = rngFor(name);
  const n = Math.floor(SR * 0.7);
  const x = new Float32Array(n);
  for (let i = 0; i < SR * 0.012; i++) x[i] += (r() * 2 - 1) * Math.exp(-i / (SR * 0.0025)) * 1.0;
  for (const [f, a, d] of [[1420, 0.5, 0.012], [2310, 0.3, 0.008]]) {
    for (let i = 0; i < n; i++) x[i] += Math.sin(TAU * f * i / SR) * a * Math.exp(-i / (SR * d));
  }
  for (const start of [Math.floor(SR * 0.3), Math.floor(SR * 0.48)]) {
    for (let i = 0; i < SR * 0.09 && start + i < n; i++) {
      const t = i / SR;
      x[start + i] += Math.sin(TAU * 2050 * t) * 0.45 * Math.min(1, t / 0.004) * Math.exp(-t / 0.03);
    }
  }
  writeWav(name, highpass(x, 500));
}

// The safety, the spring letting go, the needle, and the drug going in under pressure.
function epipen(name) {
  const r = rngFor(name);
  const n = Math.floor(SR * 0.85);
  const x = new Float32Array(n);
  for (let i = 0; i < SR * 0.008; i++) x[i] += (r() * 2 - 1) * Math.exp(-i / (SR * 0.002)) * 0.6;  // the cap
  const fire = Math.floor(SR * 0.12);
  for (let i = 0; i < SR * 0.05 && fire + i < n; i++) {
    x[fire + i] += (r() * 2 - 1) * Math.exp(-i / (SR * 0.004)) * 1.0;                              // the spring
    x[fire + i] += Math.sin(TAU * 900 * i / SR) * 0.35 * Math.exp(-i / (SR * 0.01));
  }
  const hissStart = Math.floor(SR * 0.16);
  for (let i = 0; hissStart + i < n; i++) {
    const t = i / SR;
    x[hissStart + i] += (r() * 2 - 1) * 0.3 * Math.min(1, t / 0.02) * Math.exp(-t / 0.22);         // the dose
  }
  writeWav(name, highpass(lowpass(x, 7200), 240));
}

// POCKETS 2 phase 2: the lifeguard whistle. A pea whistle is two slightly detuned tones beating
// against each other with the pea chattering across them, and this one is blown in a natatorium,
// so it is followed by a long bright tail. It is the loudest trinket in the game because it is the
// loudest thing the monsters hear (Trinkets.WHISTLE_NOISE).
function whistle(name) {
  const r = rngFor(name);
  const n = Math.floor(SR * 1.5);
  const x = new Float32Array(n);
  const body = 0.62;          // the blast itself; the rest is the room
  const f0 = 2350, f1 = 2412; // the two tones, ~60 Hz apart: that is the beat you hear
  let ph0 = 0, ph1 = 0, peaPh = 0;
  for (let i = 0; i < n; i++) {
    const t = i / SR;
    // Attack, hold, and a quick release as the breath runs out.
    let env = Math.min(1, t / 0.022) * (t < body ? 1 : Math.exp(-(t - body) / 0.05));
    if (t > body + 0.2) env = 0;
    if (env <= 0) continue;
    // The pea: a fast warble across both tones, plus the chatter it makes rattling round the chamber.
    peaPh += TAU * 26 / SR;
    const warble = 1 + Math.sin(peaPh) * 0.018 + (r() * 2 - 1) * 0.004;
    ph0 += TAU * f0 * warble / SR;
    ph1 += TAU * f1 * warble / SR;
    let v = Math.sin(ph0) * 0.5 + Math.sin(ph1) * 0.45;
    v += Math.sin(ph0 * 2) * 0.12 + Math.sin(ph1 * 3) * 0.05;   // the shrillness
    v += (r() * 2 - 1) * 0.10;                                   // breath through the mouthpiece
    x[i] += v * env * 0.85;
  }
  // The room: a handful of bright late reflections off wet tile, well after the blast stops.
  const src = x.slice();
  for (const [delay, gain] of [[0.037, 0.30], [0.071, 0.22], [0.119, 0.16], [0.181, 0.11], [0.262, 0.07], [0.36, 0.045]]) {
    const d = Math.floor(SR * delay);
    for (let i = 0; i + d < n; i++) x[i + d] += src[i] * gain;
  }
  writeWav(name, highpass(lowpass(x, 11000), 700));
}

fs.mkdirSync(OUT, { recursive: true });
phoneRing('trinkets_phone_ring');
phonePick('trinkets_phone_pick');
laptopOpen('trinkets_laptop_open');
defibZap('trinkets_defib_zap');
heartbeat('trinkets_heartbeat');
hammerBonk('trinkets_hammer_bonk');
clipOn('trinkets_clip_on');
epipen('trinkets_epipen');
whistle('trinkets_whistle');
