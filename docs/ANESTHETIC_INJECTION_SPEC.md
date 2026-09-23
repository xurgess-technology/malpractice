# Anesthetic Injection — Implementation Handoff (verbatim spec)

Zach's handoff, pasted 2026-09-21. It describes an approved HTML prototype. **Read the
"Decisions" section at the bottom first: it overrides the spec where they disagree.**

---

Surgery minigame for the co-op horror hospital project. Target engine: Godot. This spec describes the approved HTML prototype exactly — mechanics, constants, and art style. Where a value is a tuning knob it is marked (T).

Source of truth: Anesthetic Injection.dc.html · reference play space 960 × 600 px · September 2026

## 1 · Overview and flow
One mouse-driven scheme throughout. A single state machine drives four states in strict sequence: DRAW → DEBUBBLE → INJECT → RESULTS. Each state shows a one-line italic instruction above the play panel. Space (or a Done/Continue button) advances DRAW and DEBUBBLE; INJECT ends itself when the full dose is depressed; RESULTS offers Retry, which re-rolls every randomized value (target dose, bubble set, vein layout).

All state carried between phases: fluid (0–1 fraction of the barrel, displayed as 0–5 mL), the bubbles array (leftovers from DEBUBBLE are carried into INJECT and scored), and the running stats record (misses, bubble units, fast-push count).

Cut feature: an in-panel heart-rate monitor existed in earlier iterations and was removed by direction. The code keeps a no-op spike(n) hook at every mistake site (air drawn, purge below band, slap, miss, tourniquet timeout, fast push) — preserve these call sites in the port so vitals can be reattached later.

## 2 · Art direction
The minigame lives inside a raised comic panel: a paper-colored canvas in a 3 px ink border, tilted −0.65°, sitting on a flat offset shadow (9 px right, 11 px down, no blur — a printed-page drop, not a soft glow). The mood is grimy clinical: unsettling but readable, never gory.

### 2.1 Hand-drawn ink rendering (the core of the look)
- Every outline is a polyline sampled roughly every 20–26 px (rectangles: 4 samples per edge; circles: 18 segments).
- Each vertex is offset by seeded hash noise, ±1.3 px on both axes. The noise seed combines a per-shape constant with floor(t × 7), so lines "boil" at ~7 fps like hand-inked animation while staying stable within a frame.
- Round joins and round caps everywhere. Stroke widths: 1.8–2.5 px detail, 3–3.5 px object outlines, 4 px heavy rules.
- Fills are flat and un-jittered; only the ink outline wobbles. No gradients anywhere.
- Halftone shading: an 8 px repeating tile with two ink dots (r ≈ 1.3, ~50% alpha), used as a low-alpha pattern fill under skin edges and in shaded bands.
- Paper grime: 6–8 random soft ellipses per run, olive-brown at 3–7% alpha, scattered across the panel.

### 2.2 Palette
| Role | Value | Notes |
|---|---|---|
| Panel paper | #efe9dc | mat around it #e9e3d6 |
| Ink | #221d18 / #2a241d | labels #3a332a |
| Anesthetic (sickly green) | #a0af5f @ 75% | vial pool #788c50 @ 65%; meniscus line #5a6932 |
| Target band | #5a8c3c @ 30% | edge rules #4c6b3c |
| Deep red (warnings, flash) | #7c1f24 | hub flash #961e1e @ 50–85% |
| Stuck-bubble amber | #a06a1f | fill #cdb478 @ 55% |
| Bruise purple | #5f2d5f @ 45% | darker core #3c1946 @ 50% |
| Human skin / seal hide | #dcc7a8 / #67757b | vein stroke #5a7268 (seal #2e4a4a) |
| Redness overlay (tourniquet) | #a52d28 @ 0–22% | alpha = redness × 0.22 |

### 2.3 Typography and page chrome
Everything outside the panel follows the Classical design system: Cormorant Garamond headings (semibold max), Lora body, hairline dividers, outlined gold-accent buttons (#b68235), light ground #f3f2f2. In-panel canvas labels are set in Lora italic 12–15 px, ink-colored; the results stamp is Cormorant, letterspaced, rotated −6°, in a 3.5 px double border. Kicker: "ST. AGNES MEMORIAL — THEATRE III". Title: "Anesthetic Injection / a rehearsal in three movements".

## 3 · Phase 1 — DRAW
Instruction: "Hold the left mouse button to draw the plunger back — land the level in the green band. Right-click or scroll returns fluid to the vial."

Layout. Syringe vertical, needle up, at x = 430: barrel 92 wide, y 232–508, fluid travel 250 px (fraction 0–1 ⇒ 0–5 mL, ticks each 1 mL on the right). The needle runs up through the vial neck to y ≈ 104, bevel tip visibly inside the anesthetic pool. Inverted vial ("SOMNUL-9") body 84 × 90 at y 56–146, neck tapering to y 168; its pool sits at the neck end and drains as you draw. Plunger seal tracks the fluid line; rod and thumb pad extend below the barrel flange.

| Mechanic | Rule |
|---|---|
| Draw (hold LMB) | speed = 0.05 + holdTime × drawAccel, in barrel-fractions/s. sc-camel-draw-accel = 0.22 (T). Accelerates the longer the hold — overshoot is the intended risk. Releasing resets holdTime. |
| Vial volume | starts 0.90, capacity 1.00 (barrel fractions). Draw is capped by vial contents; "vial empty" label when drained. |
| Return fluid | hold RMB: 0.25/s back to vial. Scroll: 0.02 per notch. Blocked when the vial is full. |
| Target band | center uniform in [0.35, 0.75] per run; half-width 0.05 (±0.25 mL) (T). Drawn as a translucent green band on the barrel. |
| Air bubble | if (vial empty OR continuous hold > 2.8 s) sustained for 0.3 s → one large air bubble (r 16) appears at the fluid top; "air drawn in" warning. It joins the DEBUBBLE set. |
| Advance | Done button or Space. |

## 4 · Phase 2 — DEBUBBLE
Instruction: "Flick the barrel: loose bubbles rise on their own; amber wall-stuck bubbles need a flick right beside them. Tap the plunger pad to purge at the needle."

Same syringe, needle up. A legend in the top-left corner shows the two bubble types. Loose bubbles are round, ink-outlined; stuck bubbles are amber, drawn flattened against the barrel wall.

| Mechanic | Rule |
|---|---|
| Spawn | 3–6 bubbles, r uniform 5–14, random positions inside the fluid column; the first two spawn stuck to the left/right walls. The Phase-1 air bubble (r 16) is appended if present. |
| Buoyancy & wobble | free bubbles rise at 9 + 0.9r px/s with a sideways wobble sin(t·3 + φ) × 12 px/s; impulse velocities damp at 2.5/s (x) and 1.4/s (y). Clamped inside the fluid region (walls, fluid top, plunger seal). Stuck bubbles do not move. |
| Flick (click barrel) | every free bubble gets vy −(35–90), vx ±50 random impulse; stuck bubbles within 85 px of the click un-stick with an upward kick. A quick ink ripple ring marks the click. |
| Merging | two free bubbles overlapping (dist < r₁+r₂−2) merge at the midpoint with r = √(r₁²+r₂²), capped at 26. |
| Purge (tap plunger pad) | click zone is the thumb pad below the barrel. If a free bubble's top is within 18 px of the fluid top: pop it (grey droplet particles from the needle, fluid −0.004). Otherwise the tap squirts medicine: green droplets, fluid −0.02. |
| Low-dose warning | when fluid falls below (target − band): red "⚠ level below target band" while true. |
| Advance | Continue or Space at any time. Leftover bubbles are allowed, carried forward, and scored. |

## 5 · Phase 3 — FIND THE VEIN & INJECT
Instruction: "Slap the skin bare-handed to raise a vein, then take the syringe from the tray. Scroll or A/D sets the angle — push until about half the needle is in and stop at the red flash."

Layout. Arm fills the panel below a wavy ink top edge: human skin top ≈ y 292 ± 9 (sin 0.004x); seal flipper top ≈ y 255 ± 10 with a slight downward drift, three lengthwise ridge lines, and speckles. Patient toggle (Human/Seal) regenerates veins and clears marks. An instrument tray (ellipse, top-left, center 127,106) holds the syringe.

### 5.1 Bare hand
| Mechanic | Rule |
|---|---|
| Slap (click skin) | only while empty-handed, press < 0.3 s. Vein visibility snaps to 1 and fades linearly over sc-camel-vein-fade = 1.5 s (T). Ripple ring at the slap point. |
| Pick up / set down | click the tray to take the syringe; a quick click (< 0.18 s, no insertion) back on the tray sets it down. While held, the assembly follows the mouse. |
| Tourniquet (button) | pins visibility at 1; a depleting 9 s timer bar shows top-left; arm redness ramps +0.10/s (overlay alpha = redness × 0.22) and decays 0.03/s when off. At 9 s it auto-releases. |
| Veins | 2–3 per run (third at 50%). Polyline sampled every 16 px across x 50–910; y = base + sin(k₁x+φ₁)·A₁ + sin(k₂x+φ₂)·A₂ with A₁ 10–24, k₁ 0.004–0.009, A₂ 4–10, k₂ 0.010–0.018. Base y bands: human 340–500, seal 330–470, spread evenly. |

### 5.2 Needle
| Mechanic | Rule |
|---|---|
| Geometry | assembly along the aim direction: barrel 64 px (mini fluid level inside), needle 62 px, tip at 126 px from the grip. Half-length tick on the needle. |
| Angle | **DECIDED AWAY 2026-09-22.** A fixed 25° tilt, no longer a control: setting it with the wheel or A/D, and gating the flash on it, was the main reason a stick lined up over a vein missed anyway. |
| Aim | the mouse holds the assembly by the needle tip, so the tip is the cursor. |
| Insertion | hold ≥ 0.15 s to start; the tip must be on skin. Going in is **depth, not travel**: the tip stays pinned to the point the mouse was on when Space went down, and `sink` runs 0 → 52 at 30 px/s (T). Nothing after the press is a reaction test. |
| Depth reading | the needle visibly disappears into the skin: the exposed needle shortens by the depth and the barrel rides down onto it, the tip and the entry dimple being one ringed point. "depth NN%" readout turns red past 75% without a flash. |
| Vein hit → stop | settled the instant the needle starts down: the tip within 9 px of a vein polyline. If it is, the needle **stops itself** at depth 30, red flash in the hub, and locks in. |
| Miss | the needle reaches depth 52 with no vein under it (or is let go past depth 15): small red puncture ring at the tip, misses++. |
| Depress plunger | hold to build push rate +0.55/s, decay −0.9/s released (pulsing keeps it low); fluid drains at rate × 0.09/s. A vertical PUSH meter (green lower 55%, red upper 45%) shows the rate; rate > 0.55 counts a fast-push every 0.9 s. At fluid 0: "dose delivered…", 0.9 s beat, then RESULTS. |

## 6 · Results card
Modal card over a 35% ink scrim: rotated double-border stamp, a two-column breakdown (Dose "x.x mL / t.t ±0.3 — IN BAND / OVER / UNDER", Bubbles injected, Sticks "n missed", Push speed "steady hand / n pressure spikes"), one italic flavor line, Retry, and the numeric score in small type. Big bubbles (r > 12) count as 2 bubble units.

| Scoring (start 100) | Penalty |
|---|---|
| Dose outside band | min(40, (\|error\| − band) × 260) |
| Per bubble unit injected | −10 |
| Per missed stick | −8 |
| Per fast-push event | −6 |

Grades: CLEAN ≥ 82 (green #4c6b3c) · SLOPPY ≥ 50 (gold #a06a1f) · MALPRACTICE below (red #7c1f24). Flavor line, first match wins: bubbles ≥ 2 → "Something extra is on its way to the heart." · underdose → "Patient may wake up mid-surgery." · overdose → "That is a deeper sleep than anyone scheduled." · misses ≥ 3 → "The arm has more holes than the chart explains." · any fast push → "You pushed like the elevator was waiting." · else → "Textbook. Suspiciously textbook."

## 7 · Debug & tuning
A Debug toggle overlays: vein polylines (bright green), the reach the tip has to land inside as a ring around it, a cross on the exact point the vein test uses, and a readout line with target mL ± band, current fluid, the reach and the depth. Exposed tuning knobs (T): drawAccel 0.22 (0.05–0.5) · veinFade 1.5 s (0.5–4) · tipTol 9 px (2–30) · insertSpeed 30 px/s (5–150). Keep every (T) value in one tuning resource in Godot.

## 8 · Godot port notes
- Keep the 960 × 600 reference space and scale the panel as a whole; all constants above are in that space.
- Ink lines: Line2D per shape with vertices re-jittered on a 7 fps tick (or a vertex shader with a time-quantized noise offset). Never re-jitter per rendered frame — the boil must be steppy.
- One Minigame scene with a phase enum; each phase a plain function set, not separate scenes — the syringe node persists across DRAW/DEBUBBLE.
- Bubbles: plain physics in _process as specced — do not use the physics engine.
- Emit signals at every current spike() call site (mistake events) so vitals/audio/co-op reactions can subscribe later.
- Seed one RNG per run; re-roll on Retry (target, bubbles, veins, grime, arm phase).
- Timing is frame-rate independent in the prototype (dt-based, dt capped at 0.05 s) — preserve that.

---

## 9 · Loading a syringe away from the table (SYRINGE DRAW, 2026-09-22)

DRAW! and FLICK! stop being things you only do standing over a patient. There is a `syringe` item
(`scripts/items.gd`), a batch consumable like the vials, and the two loading stages can be played
anywhere with one in your hand. This is the first minigame that happens outside the OR.

**One game, two entry points, no fork.** `inject_arcade.gd` already had `_stick_only()` — a `--stick`
debug flag that pre-filled the barrel and opened on STICK!. That is now the real mechanism, driven
by the context instead of the command line:

| context | stages | where |
|---|---|---|
| `draw_only` | DRAW! FLICK! | anywhere, holding a syringe |
| `loaded` | STICK! PUSH! | the table, holding a syringe you already loaded |
| neither | DRAW! FLICK! STICK! PUSH! | the table, empty-handed |

**The last row is not a legacy path, it is the fallback, and it stays.** Arriving at a patient with
no syringe still offers the whole game exactly as before. Loading ahead is a convenience that saves
time at the table, never a requirement.

**What a loaded syringe carries, and why it is a level and not a dose.** The contents ride the
stack's / world item's `x` string (`scripts/syringe/syringes.gd`), the way a specimen vat carries
its eye — so they survive every carry, drop, shelf and snapshot path with no new replication. The
string is `fluid|level|bubbles`, and `level` is the **absolute barrel level**, not a score.

The green band is placed by the patient's weight, and a corridor has no patient. So a syringe loaded
away from the table aims at a **standard 80 kg dose** and stores the level it actually reached; at
the table the real band is worked out from the real patient and that stored level is scored against
it, unchanged. **Pre-loading buys time and costs precision** — a standard dose is light for a heavy
patient and heavy for a light one, and the syringe has no idea which it is about to meet. That is
the trade, and it is deliberate. (The self-test already measured this shape: "bob's dose into the
seal -> sedation 0.63".)

**One loaded syringe per slot.** A slot has one `x` and a batch of three syringes shares it, so the
loaded one is the top of the batch: draw one, stick it, draw the next. That is also what makes a
syringe one-use — injecting takes one off the count and clears `x`.

**Nothing is billed in the corridor.** No dose is scored and no vitals are charged for a draw away
from the table: you have not touched a patient, so there is no patient to hurt. The bill comes at
the table, on the dose that actually goes in.

### The second anchoring mode

The panel is anchored at the step's site and lifted along the site normal, oriented **once** at open
time — it is not a billboard. Standing in a corridor there is no site and no patient.

The answer is **a synthetic site**, not a second kind of panel: `surgery_system._site_transform()`
lets a stand-in game pin the site itself, in front of the player instead of on a body. Everything
downstream is untouched — the panel still lifts `panel_lift` along the site's +Y and still orients
once to the operator's leaned-in camera, the camera pose is still derived from the site, the cursor
still projects onto the panel's plane. Neither `surgery_panel.gd` nor the OR path knows which kind
of site it got, which is exactly why the OR path is unaffected.

Freeze / hand-over comes along for free with it: the arcade's "step away and the game stops dead,
whoever picks it up gets a READY countdown" is driven by `operating`, not by a table.

### Not built yet

The item, the split and the anchoring mode are in. **The station that opens the window
(`scripts/syringe/syringe_station.gd`), the three-fluid rack, and the table's acceptance of a
loaded syringe are not.** The shape is a stand-in game after the model of
`scripts/downed/player_surgery.gd`, reached by the `"vat_hand"` pseudo-target pattern
(`player._update_aim` → `game.player_pressed_interact`), with the rack drawn across the top of the
DRAW! page and the syringe moving between up to three fluids the player is actually carrying.

---

## Decisions (Zach, 2026-09-21) — these override the spec

1. **It replaces DOSE!, and there is one version.** Delete `scripts/surgery/arcade/dose_arcade.gd` *and* the legacy `scripts/surgery/games/anesthetic.gd`, their `ARCADE_ENABLED` / `MINIGAME_SCRIPTS` / `ARCADE_SCRIPTS` entries and the dev-panel toggle for them. This game is the only sedation game. Rewrite ARCADE_SURGERY.md §5.1 to describe it.
2. **Art: this is the pilot for restyling every surgery panel into the ink/paper comic look.** Build the look as shared, reusable pieces (an ink-drawing helper: boiling jittered polylines, rects, circles, halftone fill, grime; a paper palette alongside or inside `panel_style.gd`). Other games will adopt it later, so don't bury it inside this one game. Don't restyle the other games in this task.
3. **No results card and no Retry.** Each `spike()` site is a live `cost()` botch, with the spec's penalties scaled to vitals. The flavour lines become the reasons that botch says. The dose result maps to the `sedation` flag, so an underdose still makes the patient stir in later steps and an overdose still costs vitals. Its score becomes `quality`. Keep a signal at every spike site.
4. **The target band is centred by patient weight** (the seal needs more, so its band sits higher on the barrel), not uniformly at random.
5. **Every difficulty-affecting value is a slider**: `@export_range` on the game (the house convention, listed in ARCADE_SURGERY.md), and it scales with the framework's difficulty, so it can be made harder later. That covers every (T) knob, plus band half-width, bubble count and sizes, stuck-bubble count, vein fade, tip tolerance, the angle window, insertion speed, and the fast-push threshold.
6. **The tourniquet is optional help that uses up a real tourniquet.** The in-panel button works only when the operator has a tourniquet available, and pressing it consumes one. Look at how step `item` / `uses` and inventory work. With none, the button shows as unavailable.
7. **No page chrome.** Drop the kicker, the title and the Classical buttons. In-panel instructions use the framework's card words. Map 960×600 px onto the 120×80 mm diagram at 8 px/mm; the extra height is spare top and bottom. Add a scroll input bit to the framework's button bits (A/D stays as the fallback). Everything spectators need goes in `net_pack`/`net_apply`. Write `bot_input` and `self_test`. Register first-draw content in `scripts/warmup.gd`.
