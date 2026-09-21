# Addendum — Bullet Extraction, and the shared presentation layer (verbatim spec)

Zach's handoff, pasted 2026-09-21. Companion to docs/ANESTHETIC_INJECTION_SPEC.md. **Read the
"Decisions" section at the bottom first: it overrides the spec where they disagree.**

---

Companion to the Anesthetic Injection handoff. Part One describes the shared shell both minigames now use, and the changes made to the injection step since that document. Part Two specifies DODGE! (bullet extraction) as prototyped. Tuning knobs are marked (T).

Sources of truth: Anesthetic Injection.dc.html, DODGE Bullet Extraction.dc.html · reference play space 960 × 600 px · September 2026

## Part One · The shared shell
Every surgical step should read as one page of the same case file. Build the shell once in Godot and let each minigame fill the page; the elements below are common property, not per-step decoration.

### 1 · The clipboard, replacing the raised panel
The comic panel is now a clipboard held at a −0.65° tilt. Brown hardboard (#8a6b45) in a 3 px ink border, 10 px corner radius, an even 14 px of board visible on all four sides, and a 1.5 px inset bevel line 5 px in at 30% ink. The play surface is a cream sheet (#efe9dc) in a 1.5 px ink border that runs all the way to the top edge of the board. A steel spring clip sits over the top of the sheet: a 186 × 58 body (#9aa0a4) with an inset bottom shadow, a 54 × 20 thumb loop (#b6bbbe) arching above it, and a dark hinge bar across the page below. Only the clip casts a shadow — the board itself does not, and neither does the paper.

Why: the earlier floating panel with an offset drop shadow read as a UI card. The clipboard reads as an object on the table in the room, which is the tone we want, and it gives every step the same frame at no per-step cost.

### 2 · Stamp cards carry every instruction
Each phase opens on a stamp card drawn on the page: a 430 × 228 box at 80% cream over the live game, a 5 px colored border with a 2 px inner rule, tilted about 6°. Inside, in order: the phase shout in Cormorant at 60–66 px (DRAW! · FLICK! · STICK! · DODGE! · TORN!), a hairline rule, one italic goal line, then one or two 13 px lines and the prompt to press the key.

- The card is translucent and there is no dimming scrim behind it: the player can see the tract, the arm or the syringe underneath and orient before starting.
- Gameplay is frozen while a card is up. It dismisses on the action key (or a click) and that same press counts as the player's first action.
- The card holds the goal and the hazard, never the control list — controls live in the corner HUD, permanently.
- Use the same card for interruptions, not just openings: a tear in DODGE! raises a TORN! card with a live countdown in the body text.

### 3 · Corner HUD
Two anchors, at the literal top corners of the page, present in every step: top-left, the control line for the current phase in 13 px Lora at 70% ink; top-right, the one number that decides the grade, in Cormorant semibold 22 px — dose in mL for the injection, VITALS for the extraction — turning deep red (#7c1f24) when that number is in trouble. Nothing else is chrome. The old floating readouts, the corner heart monitor and the mid-panel status text are all gone.

Where a step has a "you may proceed" moment, draw it as a key cap on the page rather than a sentence: a bordered ENTER cap with a short italic label, dim while the player is still working, brightening on a slow pulse in green (#4c6b3c) when the condition is actually met. Place it clear of every click target.

### 4 · Mistakes are drawn on the page
| Element | Specification |
|---|---|
| Comic burst | A cream starburst (16-point, alternating radii 46/72, squashed to 1.7 × 0.75) in a 3.5 px ink outline, tilted about 7°, holding one red word in Cormorant 34 px. Fires on every mistake and fades over ~1.4 s. Vocabulary so far: MISS! · BLOWN! · AIR! · WASTED! · TOO FAST! · SQUIRM! |
| Blood on the page | Each mistake throws 2–4 splats at fully random positions anywhere on the sheet — not near the error, the page itself is getting messy. Every splat rolls its own shape: an irregular 10–14 vertex blob (radius jittered 0.55–1.45× base), one of three kinds (small speckle cluster / round splat / streaky splat whose droplets fling along one direction), one of four blood tones (#6e1b1b, #7c1f24, #5a1414, #84262a), alpha 0.32–0.62, a vertical squash of 0.6–1.1, and a 60% chance of a drip that hangs straight down regardless of the splat's own rotation. Splats scale up over 0.35 s with an ease-out and then stay for the rest of the run. |
| Screen shake / flash | Serious errors only: a decaying ±14 px translate and a red wash at up to 50% for ~0.3 s. |

The heart monitor is cut from both steps. It was competing with the page for attention and the vitals number does the same job in one glyph. Keep an event hook at every mistake site so audio, co-op reactions or a future monitor can subscribe.

### 5 · Controls: one key does the work
Space is the verb in both steps. In the injection it draws (hold), purges (tap) and pushes the needle and plunger (hold); Enter advances between phases. In the extraction Space is the only control at all, and the mouse does nothing. The mouse stays for spatial choices that a key cannot express — aiming the needle, slapping the skin, flicking the barrel, picking the syringe off the tray, setting the angle by scroll.

Rule to carry into every future step: the press that starts or resumes a step also performs the first action. Starting DODGE! gives you your first flap; resuming after a tear gives you one too. A player should never resume into a fall.

### 6 · Changes to the injection step since the first handoff
- Heart monitor removed entirely, as above; the mistake hooks remain as no-ops.
- In the DRAW phase the needle now runs up through the vial neck with its bevel tip visibly inside the anesthetic pool, instead of stopping at the barrel top.
- Phase 3 starts empty-handed: the player slaps the skin with a bare hand, then clicks the instrument tray to take the syringe (and can click it again to set it down). Vein registration requires roughly a quarter of the needle in, so a graze no longer flashes.
- The needle visibly disappears into the arm: visible length = max(4, 62 − 1.05 × advance), with a half-length tick, a 15%-alpha dashed ghost of the buried portion, an entry dimple, and a "depth NN%" readout that reddens past 65% without a flash. Target depth is about half the needle.
- Insertion speed reduced from 95 to 38 px/s (T) so the depth read is actionable.
- Bubble types are now visually distinct: loose bubbles are round ink circles, wall-stuck bubbles are amber and drawn flattened against the glass, with a two-line legend on the page.
- Clipboard, stamp cards, corner HUD, bursts and blood as described above.

## Part Two · DODGE! — bullet extraction
Step two of the gunshot wound. A side-scrolling flight back out along the bullet's own channel: the forceps have the slug, and the player keeps it off the walls while it is drawn out. The prototype deliberately departs from the original brief in several places; each departure is called out below.

### 7 · Flow
DODGE! card → fly → (tear → TORN! card → fly)* → exit → results. The opening card waits for Space; there is no timed intro. The slug sits at the left of the page with the tract already drawn behind it to the page edge and the forceps visible at its base, so the player can read the starting situation before committing. The first Space both starts the run and gives the first flap.

### 8 · The channel
| Property | Rule |
|---|---|
| Generation | Seeded per run. The centreline is the sum of 3–5 sines (amplitude 6–18, frequency 0.02–0.07 rad/mm, random phase), sampled every millimetre. In the shipping version this is the legacy channel unrolled; the prototype generates it directly, and the two are interchangeable as long as the output is a per-millimetre (offset, half-width) pair. |
| Fitting | The whole centreline is scaled by one factor so that it fits ±16 mm of lane and never climbs more than 1 mm per mm of tract. Scale, do not clip: clipping flattens one bend and leaves the rest untouched, which reads as a bug. |
| Length | 135 mm ± 8 at shift 1, growing to about 192 mm by shift 6 — roughly 11–16 s of flying. |
| Half-width | 12.5 mm at shift 1 narrowing to 8 mm by shift 6, with a ±14% wobble along the length, a 28% flare over the last 12 mm at the bullet bed and 30% at the mouth, floored at 3.6 mm. Behind the slug the tract keeps widening slightly toward the page edge so the bed reads as a cavity. |
| Rendering | Drawn in 2 mm segments at 6 px/mm: flesh-red fill (#b8443a at 85%) over a darker wash (#6e1b1b at 30%), 3 px boiling ink walls, and a pale dashed centreline showing the line to fly. |

### 9 · Flight
The slug holds at x = 100 px while the tract scrolls past at 12 mm/s (T). Gravity 90 mm/s² (T), terminal fall 90 mm/s. A flap sets vertical speed to −26 mm/s (T) rather than adding to it, so mashing does not stack lift and the game is played on rhythm. Collision is one-dimensional: each frame, |slug offset − centreline| against a clearance of half-width − 3.1 mm − the current squirm pinch, floored at 0.4 mm.

The slug faces into the wound. Its nose points left, its base leads the way out, and the forceps jaws grip that base and trail off to the right — the direction of the pull. A short puff ring marks each flap. Once the mouth is 70 mm away the camera stops and the last stretch is flown across a still page toward a mouth the player can see; the slug then clinks and arcs into the kidney dish over 0.8 s.

### 10 · Squirm, in place of the heartbeat
The constant 1.25 Hz heartbeat pinch is cut. Its squeezing motion is reassigned to the patient squirming, which only happens when the patient is unsedated — a toggle in the prototype, and in the game the carried-forward result of the sedation step.

- Squirms are scheduled deterministically from the run seed, first at 4–10 s and then every 8–14 s. Rare enough to be an event, not weather.
- Envelope: the walls squeeze inward over 0.35 s, hold fully closed-in for 0.8 s, then release over 0.6 s. Sudden enough to alarm, slow enough to fly out of — this shape is the whole point, so tune the depth (2.5 mm default, T) rather than the timing.
- Presentation: a SQUIRM! burst beside the slug, inward-pointing red arrows on both walls for the duration (shape, not colour, per the colour-blind rule), and a brief shake. No vertical kick — the squeeze itself is the hazard.

### 11 · Tearing
Touching a wall costs 2.5 vitals, shakes the page, flashes it red, throws 2–4 blood splats, drags the slug 22 mm back down the tract, re-centres it with zero speed, and marks that wall with a red X over a blood dot plus a tick on the status strip.

A tear pauses the game. The TORN! card comes up over the frozen scene and Space is ignored for 2 seconds — the body text counts down, then changes to the prompt. This replaces the original brief's blinking 0.9 s grace period, which passed before the player had understood what happened. On resume the slug gets 0.9 s of invulnerability, blinking, and the resuming press flaps.

### 12 · What was cut from the brief, and why
- The dark and the flashlight. The full tract is now visible. Two seconds of warning at 12 mm/s turned the step into reaction-testing, and the darkness hid the one thing the art is good at. If the co-op lighting hook is wanted later, reintroduce it as a bonus on a still-visible tract — wider view, not first view.
- The brake. Cut with the dark, since its purpose was buying reaction time. Without it, the squirm carries the entire difficulty curve; keep that in mind when tuning.
- Vitals as a network of consequences. The prototype drains 0.8 vitals/s plus 2.5 per tear, purely so that time has a cost. The real drain rates belong to the wider game.
- Networking, bot and self-test. Out of scope for a feel test. Nothing in the prototype's simulation is frame-rate dependent (dt-based, dt capped at 0.05 s) and the whole tract derives from one seed, so both remain straightforward to add.

### 13 · Results and carry-forward
Same card as the injection step: a rotated double-border stamp — CLEAN (no tears and inside par + 6 s), SLOPPY (1–2 tears), MALPRACTICE (3 or more) — over a breakdown of extraction time against par, tears, vitals lost and whether the patient stirred, one italic flavor line, Retry, and the score. Score starts at 100, −15 per tear and −2 per second over par.

The step should hand forward {bullet_removed, tears: [positions along the tract]} as the original brief specifies, so the dressing step can put one bleeder on the wound per tear. Quality = 1.0 − 0.15 per tear, floor 0.05.

### 14 · Tuning knobs
Scroll speed 12 mm/s (6–24) · gravity 90 mm/s² (40–160) · flap 26 mm/s (14–40) · squirm depth 2.5 mm (0.5–5) · shift 1–6. Keep these in one tuning resource alongside the injection step's, and expect the first real balance pass to be gravity against flap: everything else is scenery by comparison.

---

## Decisions (orchestrator, 2026-09-21, from Zach's earlier rulings) — these override the spec

1. **Still no results card and no Retry**, in either step (Zach's ruling on the injection). A live case can't be retried. Tears and other mistakes are live `cost()` botches (a tear = 2.5 vitals, per the spec). Quality uses the spec's formulas. The flavour lines are the botch reasons. The prototype's 0.8/s vitals drain is not ported; the game's own drain applies.
2. **One version per game.** DODGE! replaces the existing `scripts/surgery/arcade/dodge_arcade.gd` and the legacy `scripts/surgery/games/forceps.gd` for the gunshot step. It keeps `forceps:brain` (the monster table's brain harvest), which is legacy-only and a different game, working untouched.
3. **Networking, `bot_input` and `self_test` are in scope** (every arcade game has them), despite §12. The whole tract comes from one seed, so spectators rebuild it from the seed and a small state blob.
4. **The injection keeps the fixes Zach approved.** The cursor holds the needle tip (`cursor_at_tip`), and the buried needle is drawn clearly (`buried_alpha` 0.5, ring at the tip), where the spec says a 15% dashed ghost. Everything else in §6 applies. Keep the approved horizontal PUSH bar beside the needle.
5. **Squirm is driven by the carried-forward `sedation` flag.** It happens when sedation is under the framework's stir threshold (0.75), and its depth can scale with how far under the threshold it is. In DODGE!, squirm replaces the framework's generic jolt/stir for this step.
6. **The flashlight/dark is cut.** The co-op `helper_light()` no longer does anything in this step. Note it in KNOWN_ISSUES/ARCADE_SURGERY as a possible later bonus.
7. **Every difficulty value is a slider** (`@export_range`) that scales with the framework's difficulty/shift, per Zach's rule on the injection. The spec's shift 1→6 ramps (length, half-width) map onto that.
8. **Controls need two new input bits**, Enter and (already added) scroll. The operator's own mouse still does nothing in DODGE!.
