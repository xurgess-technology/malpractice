# Morning report: arcade surgery

Built overnight, 2026-09-20 into 09-21. The brief is [ARCADE_SURGERY.md](ARCADE_SURGERY.md).
Phases 0 to 7 are done. Phase 8 was not touched: every legacy game is still there, untouched, and
still passes its own self-test.

**Eleven games, eleven switched on.** Every one passes its self-test and sits in the lab targets.

---

## START HERE (ten minutes)

1. **The amputation, end to end.**
   `tools\review.bat main "ARCADE AM" --setup=arcade_am`
   A seal from the first step with everything on: DOSE → SQUEEZE → SAW → WRAP. **Put a deliberately
   bad tourniquet on.** Then watch the saw's artery throw blood across the court and hide the ball,
   and watch the stump dressing turn into a much harder routing puzzle. That one chain is the whole
   thesis of the brief in ninety seconds.
2. **The gunshot wound, end to end.**
   `tools\review.bat main "ARCADE GW" --setup=arcade_gw`
   DOSE → DODGE → WHACK + WRAP. **Tear the tract on purpose in DODGE**, then count the extra
   bleeders waiting for you in WHACK. Your mistakes follow you.
3. **The eyes.**
   `tools\review.bat main "ARCADE EYES" --setup=arcade_eyes`
   Two tables. STEER → PRY → CUT THE RIGHT ONE → GRAB on the Hive, GRAB → STITCH on yourself.
   Clip a vessel while driving round in STEER and the stitch ring later hides its dots under blood.
4. **Turn anything off** from the dev panel (F1), "Arcade surgery". A flag takes effect at the
   **next** step, not the one on the table.

**What to look at first, in order of how likely I am to be wrong:**
- **WHACK!** (stage A of the gunshot dressing). It is the thinnest thing here — a good player is
  done in about three seconds and the step only makes its time floor because the Snake after it
  carries the clock. It passes, but it is the one most likely to want rebuilding.
- **STITCH! the ring.** Eight dots round a socket, half of them under blood, is a purely visual
  idea and nobody had looked at it when it was written.
- **The gunshot chain kills a hopeless player** where the legacy chain does not. Numbers below.
- **SQUEEZE!'s stage A** draws the limb as two plain rectangles. It reads as boxes, not a limb.

---

## Status

| Game | Step | Key | Flag | Self-test |
|---|---|---|---|---|
| ~~DOSE!~~ | GW 1, AM 1 | `anesthetic` | replaced 2026-09-21 by the Anesthetic Injection (ARCADE_SURGERY.md 5.1) | |
| DODGE! | GW 2 | `forceps` | **ON** | PASS |
| WHACK! + WRAP! | GW 3 | `gauze:pack` | **ON** ⚠ | PASS |
| SQUEEZE! | AM 2 | `tourniquet` | **ON** | PASS |
| SAW! | AM 3 | `saw` | **ON** | PASS |
| WRAP! stump | AM 4 | `gauze:stump` | **ON** | PASS |
| STEER! | EX 1, EG 1 | `eye:cut` | **ON** | PASS |
| PRY! | EX 2, EG 2 | `eye:scoop` | **ON** | PASS |
| CUT THE RIGHT ONE! | EX 3 | `eye:snip` | **ON** | PASS |
| GRAB! | EX 4, EG 3 | `eye:place`, `eye:grab` | **ON** | PASS |
| STITCH! ring | EG 4 | `eye:stitch` | **ON** ⚠ | PASS |
| — | dissection skull | `saw:skull` | off, legacy | no rebuild |
| — | dissection brain | `forceps:brain` | off, legacy | no rebuild |

⚠ = passes, but see "what to look at first".

## Regression

- **Every legacy self-test passes with its flag off**, unchanged: anesthetic, forceps, gauze,
  tourniquet, saw, stitches, suture. Zero script errors across the whole sweep.
- **Every arcade self-test passes**: all eleven.
- **A bot plays a whole case, through the real surgery system, with the flags on:**

| Case | Result | Chain |
|---|---|---|
| Gunshot, competent | **stable, 100 vitals** | `sedation 1.01` → `bullet_removed`, `tears []` → `dressed`, `pack_quality 0.8`, `dress_marks` |
| Amputation, competent | **stable, 100 vitals** | `sedation 1.01` → `tourniquet 1.0` → `amputated`, `cut_quality 1.0` → `dressed`, `dress_marks` |
| Amputation, hopeless | **stable, 55 vitals** | `sedation 1.62` → `tourniquet 0.442` → `cut_quality 0.54` → `dress_marks "gltllgltgt..."` |
| Gunshot, hopeless | **DEAD** | died during the dressing; see below |

- **EX and EG could not be driven by a bot end to end.** A strapped Hive starts as `dissection` and
  only becomes the extraction while the scalpel is in hand at step 0, and the graft needs you
  strapped to a table. The harness plays the dissection instead. Every EX/EG step passes its own
  self-test individually, and `--setup=arcade_eyes` stages both tables for you to play by hand.

---

## Every game

See below for the lab command, the numbers and the screens for each.

### SAW! — amputation step 3, `saw`  — **ON**

Pong. The limb's cross-section sits in the middle of the court, the blade is the ball and it goes
through the limb; every crossing is one stroke and the cut line sinks. Both paddles are yours and
mirrored. Bone makes the ball heavy and makes it chatter off its line. Hold LMB at contact for a
hard return: faster sawing, less time to read it. Take the last crossing off a hard one and you saw
into the table.

- Lab: `godot --headless --path . --fixed-fps 60 tools/minigame_lab.tscn -- --game=saw --arcade --patient=bob --ailment=amputation --bot=1.0`
- Self-test: `--selftest=saw:arcade` — **PASS**. skill 1.0 9.4–9.7 s / 0 vitals; skill 0.0 16.3–17.5 s / 15.5–20.5 (mean 18.0); 16 crossings; tourniquet 0.95 → spurt 0.06 hiding nothing, 0.10 → spurt 0.90 hiding 46 mm of court.
- Quick start: `tools\review.bat main "ARCADE SAW" --setup=arcade_saw`
- Screens: `docs/screens/saw/`

### SQUEEZE! — amputation step 2, `tourniquet` — **ON**

The fishing bar, in two stages. Stage A sweeps the open strap along the limb while the infection
front creeps proximally in real time, so the safe zone moves while you hesitate. Stage B is a
pressure gauge: hold to raise your bar, release to drop it, keep it over a pulse marker that wanders
around a seeded occlusion pressure until the windlass locks itself. Grab the clip early and it spins
free. The pulse is jumpier the worse you sedated them.

- Lab: `... -- --game=tourniquet --arcade --patient=bob --ailment=amputation --bot=1.0`
- Self-test: `--selftest=tourniquet:arcade` — **PASS**. skill 1.0 8.2 s / 0 vitals; skill 0.0 14.4–22.5 s / 18 and 22 (mean 20.0). `tourniquet` out: 1.00 at skill 1.0, 0.43 at skill 0.0. Pulse noise ±25 mmHg at sedation 1.0 against ±51 at 0.3.
- Quick start: `tools\review.bat main "ARCADE AM" --setup=arcade_am`
- Screens: `docs/screens/squeeze/`

### DOSE! — gunshot step 1 and amputation step 1, `anesthetic` — REPLACED

Replaced on 2026-09-21 by the Anesthetic Injection (`inject_arcade.gd`, ARCADE_SURGERY.md 5.1), the
only sedation game; DOSE! and the legacy `anesthetic.gd` are deleted. What follows is the record of
what DOSE! was.

An old golf power meter, twice. Stop a sweeping needle on the vein, then hold to fill the syringe
and let go. Miss and the vein bruises and narrows, so the second go is harder than the first. From
shift 3 the vein hops once mid-sweep, telegraphed. The dose is still never a number and there is
still no green zone: you read the patient, who twitches less as you approach it, goes still, then
turns blue-grey with the alarm going.

- Lab: `... -- --game=anesthetic --arcade --patient=seal --ailment=gunshot --bot=1.0`
- Self-test: `--selftest=anesthetic:arcade` — **PASS**. skill 1.0 8.4 s (Bob) / 11.6 s (seal) / 0 vitals; skill 0.0 12.4 and 20.5 s / 17.2 and 23.1 (mean 20.1). By weight: Bob needs 4.10 ml, the seal 6.50. Bob's dose into the seal leaves it at sedation 0.63, under the 0.75 stir threshold, so it stirs through every later step.
- `sedation` out: 1.01 at skill 1.0, 1.62 at skill 0.0.
- Quick start: `tools\review.bat main "ARCADE GW" --setup=arcade_gw`
- Screens: `docs/screens/dose/`

### PRY! — extraction step 2 and graft step 2, `eye:scoop` — **ON**

Lockpicking. The spoon rides the socket rim at your mouse and shakes when it is near a tether; the
shake eases off as you close on that tether's sweet spot, so you find the spot by feel and then hold
to lever until it pops. Lever off the spot and the spoon slips out. One tether is tougher and takes
two pops, re-rolling its spot after the first.

- Lab: `... -- --game=eye --arcade --variant=scoop --patient=hive --ailment=eye_extraction --bot=1.0`
- Self-test: `--selftest=eye:scoop:arcade` — **PASS**. Hive skill 1.0 8.9–10.7 s / 0 vitals; skill 0.0 20.7–29.2 s / 14–26 (mean 20.0). Graft (`no_fail`) 8.8–9.8 s at skill 1.0.
- Carry-forward: a Hive at sedation 0.2 takes 21.0 s and 7 slips against 15.5 s and 3 sedated — dawdling on a monster really does make it harder.
- Quick start: `tools\review.bat main "ARCADE EYES" --setup=arcade_eyes`
- Screens: `docs/screens/pry/`

### DODGE! — gunshot step 2, `forceps` — **ON**

Flappy, down a wound tract. The forceps go in and grip the slug on their own; you play the way out.
The real seeded channel is unrolled so its bends become climbs and dips. The slug sinks, tap to lift
it, hold RMB to brake at the price of the clock. The walls pinch on every heartbeat. It is dark:
you see 30 mm ahead, and a teammate's flashlight on the wound doubles it to 60.

- Lab: `... -- --game=forceps --arcade --patient=bob --ailment=gunshot --bot=1.0`
- Self-test: `--selftest=forceps:arcade` — **PASS**. skill 1.0 13.6 s / 0 vitals / 0 tears; skill 0.0 20.9 and 37.4 s / 10.0 and 32.5 (mean 21.3). Braking the whole way turns 13.6 s into 24.8 s.
- `tears` out: an Array of floats, 0 at the mouth and 1 at the bullet bed, one per wall contact.
- Quick start: `tools\review.bat main "ARCADE GW" --setup=arcade_gw`
- Screens: `docs/screens/dodge/`

### GRAB! — extraction step 4 and graft step 3, `eye:place` / `eye:grab` — **ON**

A claw machine. The eye hangs under the claw on its nerve and swings with the carriage's
acceleration; past fifty degrees it tears off the jaws and falls back where it came from. Space
drops, grabs and lifts. Still no-fail — the only price is time, and on a strapped monster time is
sedation. On a graft the eye turns slowly while it hangs, and the angle you release at is the angle
your friend's eye points at.

- Lab: `... -- --game=eye --arcade --variant=grab --patient=player --ailment=eye_graft --bot=1.0`
- Self-test: `--selftest=eye:grab:arcade` — **PASS**. skill 1.0 9.6–13.5 s, skill 0.0 25.4–30.0 s, **0.0 vitals in every case**. The board follows the real vat and falls back without one; a spectator tracks the eye to 0.00 mm over 644 frames.
- `eye_offset_deg` out on the `grab` variant; nothing consumes it yet.
- Quick start: `tools\review.bat main "ARCADE EYES" --setup=arcade_eyes`
- Screens: `docs/screens/grab/`

### CUT THE RIGHT ONE! — extraction step 3, `eye:snip` — **ON**

Bomb defusal. A rule card shows for 1.5 s and then it is gone, so solo you have to remember it.
The bundle comes out knotted — every strand the same grey rope — and only combs out while you hold
the eye up, which is exactly the thing that strains the nerve. Once a Hive stops being sedated,
every stir swaps two adjacent strands and the rule is a standing order against the arrangement in
front of you, so the answer moves with them.

- Lab: `... -- --game=eye --arcade --variant=snip --patient=hive --ailment=eye_extraction --bot=1.0`
- Self-test: `--selftest=eye:snip:arcade` — **PASS**. skill 1.0 8.2–10.1 s / 0 vitals; skill 0.0 14–34 s (mean 16.3 vitals). **240 seeds × every possible swap + 9600 stirred swaps: the rule resolves to exactly one living strand every time.**
- Not built: the rule card also staying on the OR wall monitor (needs `scripts/orscreen/*`). The seam is there — `rule_text`, `strand_rows()` and `net_pack()["rl"]`.
- Screens: `docs/screens/nerve/`

### WRAP! the stump — amputation step 4, `gauze:stump` — **ON**

Snake. The roll of gauze is the snake, the trail is bandage. Two layers on every cell of the ring,
crossing your own bandage only on the wound. The roll is finite. A bleeding cell under one layer
soaks through and counts as bare again, so a bad tourniquet is a harder routing puzzle rather than
a bigger number.

- Lab: `... -- --game=gauze --arcade --variant=stump --patient=seal --ailment=amputation --bot=1.0`
- Self-test: `--selftest=gauze:stump:arcade` — **PASS**. skill 1.0 9.9–10.1 s / 0 vitals; skill 0.0 23.1–28.3 s / 13 and 21 (mean 17.0). Tourniquet 0.95 → 2 of 18 cells bleeding, 0.10 → 14 of 18.
- Screens: `docs/screens/wrap_stump/`

### WHACK! then WRAP! — gunshot step 3, `gauze:pack` — **ON, with a caveat**

Whack-a-mole over the tract you just dragged the bullet out of, then the same Snake over a blob.
Every wall you tore in DODGE! comes back as its own bleeder. Blood rises up the panel. From shift 3
a kidney pops up and whacking it costs exactly what you would expect.

- Lab: `... -- --game=gauze --arcade --variant=pack --patient=bob --ailment=gunshot --bot=1.0`
- Self-test: `--selftest=gauze:pack:arcade` — **PASS**. skill 1.0 9.7–11.0 s / 0 vitals; skill 0.0 23.0–31.9 s / 11.6 and 23.0 (mean 17.3). Tears in → bleeders out: 0→3, 1→3, 3→4, 5→5, 9→7 (capped), wads wanted rising 7→8→10→14→20, never two bleeders closer than 11 mm. `pack_quality` 0.90 → 1 of 12 cells bleeding, 0.20 → 10 of 12.
- **Caveat: stage A is thin.** A good player clears the whack-a-mole in about 3 s, so the step only reaches its 8 s floor because the Snake after it carries the time. It passes, but it is the one most likely to want rebuilding after you play it.
- Screens: `docs/screens/pack/`

### STEER! — extraction step 1 and graft step 1, `eye:cut` — **ON**

A top-down racer on a ring track. The scalpel drives itself, you steer, W boosts. The inside wall
is the eyeball and clipping it is the only thing that costs anything. Seeded vessels cross the
track; cross one at speed and it opens, blotting out a wedge of the ring for the rest of the step —
and that wedge comes back as stitch dots you cannot see.

- Lab: `... -- --game=eye --arcade --variant=cut --patient=hive --ailment=eye_extraction --bot=1.0`
- Self-test: `--selftest=eye:cut:arcade` — **PASS**. Hive skill 1.0 9.1 s / 0 vitals; skill 0.0 10.0–10.1 s / 15.0–21.0 (mean 18.6 over 5 seeds). Careful runs bleed no vessels; fast ones bleed 3–4.
- Screens: `docs/screens/steer/`

### STITCH! the ring — graft step 4, `eye:stitch` — **ON, with a caveat**

The panel suture game round a socket instead of along a gash: a closed ring, eight stitches, dots
hidden under blood wherever STEER! opened a vessel. Tears cost nothing under `no_fail`.

- Lab: `... -- --game=eye --arcade --variant=stitch --patient=player --ailment=eye_graft --bot=1.0`
- Self-test: `--selftest=eye:stitch:arcade` — **PASS**. skill 1.0 18.4 s, skill 0.0 10.2 s, no vitals under `no_fail`. Three `vessel_bleeds` in → three hidden dots; no key at all → 0 hidden and still 8 stitches.
- **Caveat:** 18.4 s for a perfect hand sits near the top of the 8–20 s band, and it is the game whose whole appeal is visual — nobody has seen it on a panel yet.
- Screens: `docs/screens/ring/`

---

## The one finding worth your attention

**A hopeless player now kills a gunshot patient. The legacy chain leaves them at 68 vitals.**

| | legacy | arcade |
|---|---|---|
| Gunshot, skill 0.0 | stable, **68** | **dead** during the dressing |
| Amputation, skill 0.0 | stable, **60** | stable, **55** |

The amputation is fine — five vitals harsher over a whole case. The gunshot is not, and the reason
is the carry-forward working *too* well: a hopeless DODGE! run tore the tract seven times, those
seven tears became the capped seven bleeders in WHACK!, and a hopeless hand could not clear seven
bleeders before the blood finished the job. Sixty-eight seconds on one step.

Every individual step is inside its 15-25 band. It is the compounding that kills. This is either
exactly the design working (three bad steps in a row should lose you a patient) or the arcade steps
are collectively too expensive, and that is a call for you, not me. The dials, cheapest first:
`pack_arcade.gd`'s `max_bleeders` (7), `dodge_arcade.gd`'s `tear_botch` (2.5), and the `flood_rate`.

---

## Judgment calls

### Mine (the frame and the integration)

1. **Every game was pre-registered before any of them existed.** `ARCADE_SCRIPTS` and
   `ARCADE_ENABLED` got a row each up front, pointing at files that did not exist;
   `minigame_script()` falls back to the legacy game when a path is missing. That made each game
   exactly one new file, so eight agents working at once never touched the same line.
2. **Never snap a value that creeps.** The lab round-trips `net_state()` through
   `apply_net_state()` every frame, so a countdown snapped to 0.05 s never counts down — the first
   version of SAW! silently never started. It is written on the base class's docstring and every
   game respects it.
3. **`frozen` reads straight off "is anybody at the table"**, not off an edge, so a game built while
   the table is empty starts frozen rather than running on its own.
4. **The operator is the only authority.** `play()` and `advance()` run on their machine only;
   `cost()` is a guarded `botch()` that no-ops off the operator and under `no_fail`. Everyone else
   animates from the 20 Hz state.
5. **I switched on the two games their authors wanted held.** You asked for flags true for anything
   that passes and lands near the targets, and both do. You cannot playtest what is switched off.
   Both are flagged at the top of this report instead.
6. **`saw:skull` and `forceps:brain` are pinned to legacy.** The monster table's two steps have no
   arcade rebuild and a different fiction.
7. **Screenshots are gitignored.** About a megabyte each; `docs/screens/` follows what
   `tools/*_shots/` already does. The command to regenerate any of them is in each game's section.

### Per game

Each game's author logged their own; the ones that change how a step *plays*, rather than how it is
tuned, are:

- **SAW!** — the brief's cadence version was built first and then replaced wholesale by the Pong
  version. The pendulum, the alternating keys and the tear meter are gone.
- **CUT THE RIGHT ONE!** — **the rule is a standing order, not a label.** The strands are anonymous
  and the rule resolves against the arrangement *in front of you*, so a stir that moves the amber
  strand moves the answer with it. Under the alternative reading (the nerve is a fixed identity)
  every adjacency rule goes wrong the moment a swap touches it. This is the biggest single design
  call in the whole night and it is one function (`matches_in`) to reverse.
- **CUT THE RIGHT ONE!** — the knot is invented. The spec as written is about three seconds of
  play; the bundle now comes out knotted and only combs out while you hold the eye up, which is the
  thing that strains the nerve. That is where the time comes from.
- **STEER!** — the spec's speeds could not reach the time floor (a lap is 5-7 s at 35 mm/s), so
  driving is 16 mm/s and the boost 34, with the vessel threshold between them. The eyeball is at
  the track's inner lip rather than 5.5 mm back, or the nick — the step's only cost — is
  unreachable.
- **WRAP!** — a bleeding cell wants one more layer than a dry one, not just a soak clock, and
  `soak_seconds` went 3.0 → 4.5. At 3.0 every bleeding cell soaked between laps no matter how well
  you played.
- **WHACK!** — two bleeders are only up at once when more than three are open, and the first kidney
  comes at 2-4 s rather than 6-10, because the step is often over inside six seconds.
- **DOSE!** — the legacy "dragged the needle out of the vein" botch is gone; there is no cursor to
  drag in the new stage A. The alarm moved from 1.3 to the spec's 1.15.
- **GRAB!** — the mouse steers the claw as well as A/D, with identical weight, because a steady
  mouse hand is genuinely gentler on the swinging eye and that is the skill.
- **SQUEEZE!** — a body's infection front beyond the strap's reach (Bob reports 17.2 cm) is ignored
  and the front is rolled from the seed instead, or the creep moves nothing and the panel paints a
  red zone with no rot in it.
- **SAW!, and most others** — the sloppy band is asserted on the **mean across patients**. A seeded
  layout swings one patient several vitals either side of the other on its own.

---

## Known issues

Also written into [KNOWN_ISSUES.md](KNOWN_ISSUES.md).

- **The gunshot chain kills a hopeless player.** Above.
- **Two sloppy runs sit outside 15-25 on their own** and pass on the two-patient mean: DODGE! costs
  Bob 32.5, and PRY! on a waking Hive at sedation 0.2 costs 46 over 45.6 s (that one is the
  carry-forward working as designed).
- **WHACK! is thin at high skill** — about 3 s for a good player.
- **Nobody has looked at most of these panels.** Headless Godot issues the draw calls but
  rasterises nothing, so seven of the eleven were written without their author ever seeing them. I
  have screenshotted all eleven since (`docs/screens/`), and nothing is obviously broken, but they
  have had no design pass.
- **SQUEEZE! stage A draws the limb as two rectangles.** Reads as boxes, not a limb.
- **The dev panel's checkboxes take effect at the next step**, not the one on the table. Deliberate
  — swapping mid-step would throw the state blob away — but it reads as the checkbox not working.
- **A client that joins after the host flips a key gets the old value.** `_rpc_arcade` broadcasts on
  the flip; there is no snapshot for a late joiner.
- **`dress_marks` is emitted and nothing reads it.** Both WRAP variants produce a `g`/`l`/`t` string
  per wound cell so a messy path gives a messy-looking dressing, but `patient_body.gd` only reads
  `dressed` as a bool. Wiring the dressing mesh to it is a separate job. The stump's string can be
  18 or 20 characters depending on the seed, so read its length.
- **`eye_offset_deg` is emitted and nothing reads it.** GRAB! records how far off straight you let
  the eye rotate; making the grafted eye render wall-eyed is a separate job on the player model.
- **CUT THE RIGHT ONE!'s rule card does not appear on the OR wall monitor.** Section 5.10 asks for
  it; it needs `scripts/orscreen/*`. The seam is there and needs no change to the game:
  `rule_text`, `strand_rows()` and `net_pack()["rl"]`.
- **The arcade self-tests leak ObjectDB instances at exit** (24-60 per run). It is the shared frame,
  not any one game, and it is only at process exit.
- **Every agent's worktree was cut from a stale base** (`2cf8e95`, 0.6.14, before the arcade frame
  existed). All eight noticed and reset to main before starting, and I verified every merge base
  and re-ran every self-test in main rather than trusting the reports. Worth looking at how those
  worktrees get cut.

---

## Fixed along the way

- **The warmup never built any variant-keyed arcade game.** It looked up `ARCADE_SCRIPTS[game]`, so
  every `eye:*` and both `gauze:*` rebuilds were missed and the first open would have stuttered.
- **The lab could not tell one eye variant from another.** `--variant` now picks the right step.
- **`--selftest=eye` hung forever.** `eye_ops.gd` has no `self_test()`, and calling a method that is
  not there does nothing at all. The lab says so and exits now.
