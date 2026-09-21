# Arcade surgery

The brief below is Zach's, kept verbatim as the source of truth. This section is the build log:
what exists, what it is really called, and what was decided along the way.

## Status

**Phases 0 to 7 are done (2026-09-20/21). Eleven games, all switched on.** On 2026-09-21 DOSE! and
the legacy anaesthetic were replaced by the Anesthetic Injection (5.1), the only sedation game, which
has no switch. Read
[MORNING_REPORT.md](MORNING_REPORT.md) first: it has the status table, the lab and quick-start
commands for every game, what to look at first, every judgment call and the known issues.

Phase 8 has NOT been touched and needs Zach's explicit say-so. Every legacy game is still present,
unedited, and still passes its own self-test.

## The real names

| The brief says | It is actually |
|---|---|
| the raised panel | `scripts/surgery/panel/surgery_panel.gd` (+ `panel_style.gd`), see [PANEL_STYLE.md](PANEL_STYLE.md) |
| ArcadeGame base | `scripts/surgery/arcade/arcade_game.gd` |
| SAW! | `scripts/surgery/arcade/saw_arcade.gd` |
| the legacy switch | `Procedures.ARCADE_ENABLED` / `ARCADE_SCRIPTS` / `minigame_script()` |
| the command card | `ArcadeGame.show_card()` / `card_word` / `armed()` |
| freeze / resume | `ArcadeGame.frozen`, the `READY` card, `play_t` in the state blob |
| the lab | `godot --path . tools/minigame_lab.tscn -- --game=saw --arcade` |
| its self-test | `--selftest=saw:arcade` (`--selftest=saw` still runs the legacy one) |
| the sedation game | `scripts/surgery/arcade/inject_arcade.gd`, in `MINIGAME_SCRIPTS` (no legacy twin, no switch); `--selftest=anesthetic` |
| the ink look | `scripts/surgery/panel/ink.gd`, see PANEL_STYLE.md |

`--quick` does **not** exist on `main` (it is on the unmerged `quick-start` branch), so nothing was
built for it, per section 3.4.

## Phase 0: the shared frame

- **Input bits** (`Minigame`): `BUTTON_LEFT` (A / Left), `BUTTON_RIGHT` (D / Right), `BUTTON_DOWN`
  (S / Down), `BUTTON_ACTION` (Space) alongside the three that existed. No new input actions were
  needed: `move_left`, `move_right`, `move_back` and `jump` are already in `project.godot`, and the
  player is locked in place while operating so they are free. `Minigame.pressed_edges(buttons)`
  gives the bits that went down this frame; call it once, at the top of `handle_cursor`.
  **2026-09-21:** `BUTTON_SCROLL_UP` / `BUTTON_SCROLL_DOWN`, one frame per mouse-wheel notch (the
  surgery system and the lab queue notches and let them out one a frame; bots set them the same way).
- **`ArcadeGame`** owns the panel, the diagram-millimetre space, the palette, the command card, the
  freeze/resume, the panel shake, `quality`, the audio hooks, and a `run_bot()` for the self-tests.
  A game writes `build_game()`, `card_word_for_start()`, `play()`, `advance()`, `animate()`,
  `paint_game()`, `react()`, `net_pack()` / `net_apply()`, `bot_input()` and `self_test()`.
- **Authority.** `play()` and `advance()` run on the OPERATOR'S machine only, so a botch is never
  counted twice; everyone else runs `animate()` off the replicated state and is corrected 20 times
  a second. `cost()` is a guarded `botch()` that no-ops off the operator and under `no_fail`.
- **The switch.** `Procedures.ARCADE_ENABLED` is a `static var` keyed `"<game>"` or
  `"<game>:<variant>"`, the variant key winning. `minigame_script()` is the single place anything
  resolves a step's script: the surgery system, the lab and the warmup all go through it. The dev
  panel has an "Arcade surgery" checkbox per key; the host applies it and broadcasts
  (`dev_room._rpc_arcade`) so every machine builds the same game.
- **Warmup** builds the legacy game *and* the arcade rebuild for every step that has one.
- **Onlookers.** Everything a spectator needs is in `net_state()` at 20 Hz and they interpolate.

## Judgment calls

1. **`saw:skull` is pinned to the legacy game.** The monster table's skull cut is a different
   fiction and section 5.5 describes the limb, so flipping `saw` moves the amputation to the arcade
   and leaves the skull alone. The arcade saw does handle the skull variant (its own layers, a
   depth band instead of bone circles) so the key can be flipped later without breaking.
2. **Never snap a value that creeps.** The lab and the bot round-trip `net_state()` through
   `apply_net_state()` every frame, so a countdown snapped to 0.05 s never counts down. `card_left`,
   `play_t` and `beat_phase` go out raw; everything that moves in jumps is snapped. This cost an
   hour; it is written on the `net_state()` docstring so it does not cost another.
3. **`frozen` is read straight off "is anybody at the table"**, not off an edge, so a game built
   while the table is empty starts frozen instead of running on its own.
4. **The pendulum is guidance, not the judge.** A stroke is judged on the interval since the last
   one, which is what lets the artery hide the pendulum and leave you keeping time by ear.
5. **Tuning that moved off the brief's starting numbers:** `tear_per_rush` 0.14 -> 0.25 and the
   good-stroke tear recovery 0.04 -> 0.02, to get the sloppy bot into the 15-25 vitals band. The
   rest of 5.5's numbers are as written.
6. **The sloppy bot mashes.** Its stroke interval is a golden-ratio sequence skewed hard toward
   "too fast" rather than spread evenly either side of the beat, because that is what a panicking
   player does -- and because an even spread made the numbers swing from patient to patient.
7. **`panel_style.gd` gained a `bone` colour.** A cross-section needs bone to read as bone and not
   as a hole, and it belongs in the shared palette with the rest.
8. **The already-cut half of the limb is greyed and hatched**, not just marked on the depth scale,
   so how far through you are reads in one look.

## Tuning: every `@export` and where it starts

`ArcadeGame` (shared by every arcade step):

| Export | Start | What |
|---|---|---|
| `view_fill` | 0.78 | how much of the view's height the panel fills |
| `view_tilt_deg` | 32 | how far back the operating camera sits from straight over the site |
| `view_fov` | 50 | the operating camera's field of view |
| `card_time` | 0.5 s | how long the one-word command card holds |
| `ready_time` | 1.0 s | the countdown whoever takes over gets |
| `card_size` / `ready_size` | 110 / 64 px | the type on the card |
| `card_cue` / `ready_cue` / `done_cue` | click / beep / done | audio hooks (the first two are not played yet) |

`SawArcade`:

| Export | Start | What |
|---|---|---|
| `bite_per_stroke` | 0.039 | depth per full-bite stroke at resistance 1; about 30 strokes end to end |
| `rushed_bite` / `slow_bite` | 0.15 / 0.45 | what a rushed and a lazy stroke get instead |
| `beat_tolerance` | 0.35 | how far off the cadence a stroke may be, before `/ sqrt(difficulty)` |
| `tear_per_rush` | **0.25** | tear per rushed stroke, times the layer's factor (brief said 0.14) |
| `tear_botch` | 3.0 | what a torn kerf costs |
| `bind_time` | 0.5 s | the blade jams for this long on the same key twice, or a jolt |
| `bone_chord_frac` | 0.30 | blade chord inside bone before the cadence becomes the bone cadence |
| `skin_mm` | 2.6 mm | skin at each face of the limb |
| `artery_dribble` | 0.15 | spurt below this is just a dribble |
| `artery_blinding` | 0.5 | spurt at or above this buries the pendulum completely |
| `bleed_botch_rate` / `bleed_botch` | 0.08 / 1.0 | botch units per unit spurt per second, and the bill |
| `easy_from` | 0.97 | depth where the card says EASY... |
| `table_interval` / `table_botch` | 0.25 s / 3.0 | come off the last strokes faster than this and you hit the table |
| `blade_swing_mm` / `swing_time` | 9 mm / 0.12 s | how far and how fast the blade slides on a stroke |
| `max_chips` | 26 | splatter kept on the section |
| `tick_volume` | -21 dB | the cadence tick |
| audio cues | rasp / grind / squelch / thunk / click / clink | all existing cues; nothing new generated |

`InjectArcade` (5.1; exports grouped in the inspector). "x k" / "/ k" is times / divided by the
difficulty factor k = difficulty ^ `difficulty_gain` (0.5):

| Export | Start | What |
|---|---|---|
| `ml_per_kg` / `barrel_ml` | 0.05 / 10 ml | the dose by weight and the barrel it is read on; they place the band |
| `band_half` | 0.05 / k | half the band, share of the barrel |
| `band_jitter` | 0 | a seeded nudge to the band centre (0: weight alone) |
| `vial_start` | 0.90 | what is in the vial |
| `draw_base` / `draw_accel` | 0.05 / 0.22 x k | draw speed = base + seconds held x accel |
| `return_rate` / `scroll_return` | 0.25/s / 0.02 | RMB and each wheel notch putting drug back |
| `air_hold` / `air_sustain` / `air_r` | 2.8 s / k, 0.3 s, 16 | when a hold pulls in air, and how big |
| `in_band_k` | 0.35 | how much of the error an in-band dose carries |
| `bubbles_min` / `bubbles_max` | 3-6 x k | bubbles at the flick stage |
| `bubble_r_min` / `bubble_r_max` | 5 / 14 x k | their sizes |
| `stuck_count` | 2 x k | how many start stuck to the wall |
| `merge_cap` / `big_bubble_r` | 26 / 12 | the biggest merge; over this a bubble counts twice |
| `rise_base` / `rise_per_r` / `wobble` | 9 / 0.9 / 12 | rise speed and wobble, px/s |
| `damp_x` / `damp_y` | 2.5 / 1.4 | how fast a flick's kick dies |
| `flick_vy_min` / `flick_vy_max` / `flick_vx` | 35 / 90 / 50 | the kick |
| `unstick_reach` | 85 / k | how close a flick must land to free a stuck bubble |
| `purge_reach` | 18 / k | how close to the needle end a bubble must be to pop |
| `pop_cost` / `squirt_cost` | 0.004 / 0.02 | dose lost to a pop and to a squirt |
| `vein_fade` | 1.5 s / k | how long a slap shows the veins |
| `slap_max` / `pickup_quick` | 0.3 / 0.18 s | how short a click is a slap / a set-down |
| `angle_min` / `angle_max` | 8 / 80 deg | the needle's range |
| `scroll_deg` / `key_deg` | 3 / 2 | per wheel notch / per A or D |
| `push_hold` | 0.15 s | hold this long before the needle goes in |
| `cursor_at_tip` | true | the mouse holds the syringe by the needle tip (false: the spec's grip) |
| `buried_alpha` | 0.5 | how strongly the needle shows under the skin |
| `debug_overlay` | false | the section 7 overlay (or `--inject-debug`) |
| `insert_speed` / `insert_max` | 38 x k / 55 px | needle speed and reach |
| `flash_min` / `tip_tol` | 14 / 9 / k px | the flash wants the tip this deep and this close to a vein |
| `window_lo` / `window_hi` | 14 / 32 deg | the angle to the vein that flashes (half-width / k) |
| `blow_past` / `blown_half_x` | 12 / k, 45 px | pushing past the flash blows the vein, for this far either side |
| `push_up` / `push_down` / `push_cap` | 0.55 / 0.9 / 1.2 | the plunger's push rate |
| `drain_k` | 0.09 | drain = rate x this per second |
| `fast_rate` / `fast_every` | 0.55 / k, 0.9 s | a fast push, and how often one counts |
| `deliver_beat` | 0.9 s | the pause after the last drop |
| `tourniquet_item` / `tq_time` | tourniquet / 9 s | what the button spends and how long it holds |
| `redness_up` / `redness_down` | 0.10 / 0.03 per s | the arm reddening under it |
| `vitals_per_point` | 0.25 | vitals per point of the spec's score |
| `pts_miss` / `pts_blown` / `pts_bubble` / `pts_fast` | 8 / 16 / 10 / 6 | the spec's penalties |
| `pts_dose_max` / `pts_dose_slope` | 40 / 260 | the dose penalty |
| `cost_air` / `cost_purge_low` / `cost_slap` / `cost_tourniquet_timeout` | 0 | vitals at the unpriced spike sites |
| audio cues | draw / forceps click / plop / inject / pack / needle / tear / beep crit / cinch | all existing cues |

`ArcadeGame` grew `use_ink()`, `ink_unit()`, `ink_glow` (warm) and `ink_brightness` (0.82) for games
on the ink look.

Layer cadences, resistances and tear factors are in `SawArcade.LAYERS` (skin 0.22 s / 0.45 / 0.5,
muscle 0.30 / 1.0 / 0.8, bone 0.50 / 2.2 / 1.2, far side 0.25 / 0.9 / 0.8), as the brief specifies.

## Lab results (2026-09-20)

`--selftest=saw:arcade`, **PASS**:

| | skill 1.0 | skill 0.5 | skill 0.0 | target |
|---|---|---|---|---|
| Bob | 12.9 s, 0 vitals | 12.5 s, 3 | 19.6 s, 24 | 8-20 s / 0-2, and <40 s / 15-25 |
| seal | 12.3 s, 0 | 10.7 s, 0 | 15.2 s, 15 | |

Carry-forward: tourniquet 0.95 -> spurt 0.06 (a dribble), tourniquet 0.10 -> spurt 0.90 (the panel
is painted over and the pendulum is gone).

Also run and passing: the net round-trip and hand-over (a spectator tracks the operator exactly, a
second player resumes on the blob and gets the READY countdown, and mashing through the countdown
cuts nothing), the arcade saw end to end through the real surgery system, and every legacy
self-test with its flag off, unchanged.

---

# TASK: Convert every surgery step to an arcade-style panel minigame

You are the orchestrator for this work. Read this whole document before
doing anything. It describes the full vision, but you will build it in
PHASES with a hard STOP after each one (see "Phases"). Do not run ahead.

Save a copy of this document as `docs/ARCADE_SURGERY.md` and keep it
updated as the source of truth.

---

## 1. Why we're doing this

The raised surgery panel (the flat glowing screen that pops in over the
patient when someone operates, built for the stitches testbed) is
approved. It looks and feels right. We are moving EVERY surgery step
onto it.

But we are not porting the old steps as they are. Several of them were
"click here, click here" or "circle, circle, circle". They didn't feel
like doing the procedure, and they weren't fun on their own either.
Since the panel openly admits it's a screen, we no longer have to
simulate the hand motion. So:

**Each step becomes a short, self-contained arcade minigame that RHYMES
with the procedure. It is a joke about the step, not a model of it.**

Sawing a limb is alternating-key mashing to a cadence. Pulling a bullet
out of a wound tract is a Flappy-style dodge through that tract.
Picking an eye up with forceps is a claw machine.

The fiction: the hospital's surgical-assist machine runs bootleg arcade
software. Reference points for the feel: WarioWare, Among Us tasks,
Helldivers stratagem codes. They are fun BECAUSE you do them under
pressure while something is coming to kill you and your friends watch
you choke.

**Rule that still holds: THE PANEL IS THE INPUT SURFACE, THE BODY IS
THE CONSEQUENCE SURFACE.** Flinches, blood on the gown, wound overlays,
the monitor, the noise that draws monsters: all of that stays on the
real patient through the existing calls.

**Legal/taste rule:** spoof MECHANICS only. No names, art, sounds, UI,
or level layouts from any real game. All art is original, in the panel
diagram style.

---

## 2. What must NOT change (the plumbing)

- `can_begin()` gating, required items, and `uses` counts per step.
- Procedure data shape in `scripts/procedures.gd` and the step counts
  (GW 3, AM 4, EX 4, EG 4, plus the laceration testbed).
- One failure currency: `botch(amount, reason)` -> host subtracts
  vitals and says the reason. Prices stay at roughly today's values
  (listed per game below).
- `finish({...})` merges result flags; flags are how steps talk.
- Everything random derives from the case seed. Same seed = same
  layout on every machine.
- Difficulty is `1.0 + 0.12 * (shift - 1)` and every game reads it.
- Host-authoritative reports, 20 Hz `net_state()`, progress in the
  replicated `ms` blob so another player can take over.
- The framework's stir system and `on_jolt()`.
- Monster-table rules in `dissection.gd` (sedation wears off over
  120 s, vitals = eye condition, re-dosing with E) and graft rules in
  `grafts.gd` / `player_surgery.gd` (`no_fail`, commit block, swap
  timing on `eye_seated`).
- Monitor beeps, table noise emission, +8 vitals per finished step
  (and its removal on the monster table).
- `bot_input(t, skill)`, `self_test()`, and the minigame lab.
- `Warmup.run()` must build one of every new game so first open
  doesn't hitch.

Do NOT add items, procedures, monsters, meta systems, or anything in
the wings or hub. Do NOT execute `docs/SURGERY_OVERHAUL.md`; add a note
at its top that its step redesigns are superseded by this document.

---

## 3. Before you build: read what exists

1. `docs/PANEL_STYLE.md`, the SurgeryPanel component, its style
   resource, and the suture game. Use the real names you find there;
   names in this document are suggestions.
2. `scripts/surgery/surgery_system.gd` and one legacy game end to end.
3. `tools/minigame_lab.tscn` and how games register.
4. Whether a `--quick` debug start exists. If it does, support every
   new game in it. If not, don't build it here.

---

## 4. Shared frame (Phase 0)

### 4.1 Inputs
Add button bits alongside BUTTON_PRIMARY / BUTTON_SECONDARY /
BUTTON_UP: LEFT (A / Left), RIGHT (D / Right), DOWN (S / Down),
ACTION (Space). W / Up stays BUTTON_UP. Movement is already locked
while operating, so these keys are free. Track press EDGES as well as
held state; several games need "just pressed".

### 4.2 ArcadeGame base
A small base class for panel games providing:
- diagram-mm coordinate space and the panel palette
- the COMMAND CARD: a 0.5 s one-word order in big type when the step
  (or stage) begins, e.g. "SAW!". Gameplay starts when it clears.
- FREEZE / RESUME: stepping away freezes the game state into `ms`.
  Whoever resumes gets a 1.0 s "READY" countdown before it unfreezes.
  This matters for the real-time games (dodge, snake, claw).
- panel shake helper for jolts
- a `quality` 0..1 convention for results
- audio hook exports

### 4.3 Legacy switch
Do not delete or edit legacy games. Add one dictionary in one place,
e.g. `ARCADE_ENABLED := {"saw": false, ...}`. When true, the framework
instantiates the arcade version for that step game/variant; when false,
the legacy one. I flip these after I approve each game. Add a dev-panel
checkbox list that flips them at runtime.

### 4.4 Onlookers
The panel is a world object everyone can see. Each arcade game sends
enough state at 20 Hz for spectators to watch it live (interpolate).
Watching a friend fail is a core feature, not a nicety.

### 4.5 Standards for every game
- 8-20 s for a competent player.
- Lab targets: bot skill 1.0 finishes in 8-20 s losing 0-2 vitals;
  skill 0.0 finishes in under 40 s losing 15-25. For no-fail games,
  time targets only.
- Every number is an `@export` with a sensible range.
- `keys()` returns the right controls line per stage.
- `on_jolt()` does something specific (defined per game below).
- Anything conveyed by colour is also conveyed by shape or pattern.

---

## 5. The games

Numbers are starting points. Tune to hit the lab targets.

### 5.1 The Anesthetic Injection - Sedate the patient
`anesthetic` x1, site `injection`. GW step 1, AM step 1.
`scripts/surgery/arcade/inject_arcade.gd`. **The only sedation game** (2026-09-21): it replaced
DOSE! and the legacy `anesthetic.gd`, so this step has no `ARCADE_*` entry and no dev-panel switch.
Built from Zach's handoff, `docs/ANESTHETIC_INJECTION_SPEC.md`; that file's "Decisions" section
won wherever it disagreed with the handoff. It pilots the ink/paper look (PANEL_STYLE.md, "The ink
look") that every other panel is to move onto later.

Space: the spec's 960 x 600 reference px on the 120 x 80 mm diagram at 8 px/mm, the spare 5 mm
split top and bottom. Everything below is in reference px.

**DRAW!** The syringe hangs needle-up in an upside-down vial ("SOMNUL-9", 0.9 of a barrel in it).
- Hold LMB to draw: speed = 0.05 + seconds held x 0.22 x difficulty (barrel shares per second).
  It runs away the longer you hold: overshooting is the risk. Releasing starts it slow again.
- RMB puts it back at 0.25/s; each wheel notch puts back 0.02 (either direction).
- The green **band is centred by the patient's weight**: dose = weight x 0.05 ml on a 10 ml barrel,
  so Bob (82 kg) at 0.41 and the seal (130 kg) at 0.65 of the barrel. Half-width 0.05 / difficulty.
- An empty vial, or one hold longer than 2.8 s / difficulty, for 0.3 s draws in a big air bubble
  (r 16), which joins the next stage's bubbles.
- Space or the Done button moves on.

**FLICK!** 3-6 bubbles (times difficulty), r 5-14 (the top end times difficulty); the first two
(times difficulty) are amber and stuck to the walls.
- Free bubbles rise at 9 + 0.9 r px/s with a sideways wobble, and merge when they touch
  (r = sqrt(r1^2 + r2^2), capped at 26).
- Click the barrel: every free bubble gets an upward kick; stuck ones within 85 px / difficulty come
  off the wall.
- Tap the thumb pad: a bubble whose top is within 18 px / difficulty of the needle end pops (costs
  0.004 of the dose). With nothing there you squirt drug out (0.02). The panel warns in red while
  the level is under the band.
- Space or Continue moves on whenever you like; what is left goes into the patient.

**STICK!** The forearm, or the seal's flipper (slate hide, three ridges, speckles), below a wavy
ink edge; 2-3 seeded veins across it; the instrument tray top left.
- Bare-handed, click (under 0.3 s) the skin to slap it: the veins show fully and fade out over
  1.5 s / difficulty. Click the tray to take the syringe; a quick click back on it sets it down.
- Held, the syringe hangs from the mouse **by its needle tip** (`cursor_at_tip`; the spec held it
  by the grip, 126 px back, and a miss's hole then landed far from the pointer); wheel +/-3
  degrees, A/D +/-2 (8-80 degrees below horizontal), turning about the tip. Hold LMB for 0.15 s with
  the tip on the skin and the needle goes in there at 38 px/s x difficulty (max 55): solid down to
  the entry dimple, then dashed (`buried_alpha` 0.5; the spec's 0.15 hid it) to a ringed tip, which
  is the exact point the vein test uses and where a miss leaves its hole. A depth readout goes red
  past 65%. The self-test checks pointer, drawn tip, hit-test tip, hole and dimple land within 1 px,
  through the page's tilt, at twelve grips and angles.
- The spec's section 7 debug overlay: `debug_overlay`, or `--inject-debug` on the command line (it
  works after `--setup=sedate` too). Veins in green, blown stretches in red, the angle window as
  dashed rays, a cross at the hit-test tip, and a readout.
- **The flash**: tip past 14 px, within 9 px / difficulty of a vein, at 14-32 degrees to it (the
  window narrows about its middle with difficulty). The hub fills red. Let go: locked in.
- Push on 12 px / difficulty past the flash and the vein blows (a bruise; that vein is dead for
  45 px either side). Let go past 14 px with no flash: a miss (a puncture mark).
- **The tourniquet button** pins the veins up for 9 s while the arm reddens, then lets go. It
  spends a real tourniquet from your hands (`Minigame.use_item`; the host takes it out of your
  slots) and is greyed out ("none to spare") without one, or when the rest of the procedure
  still needs the one you hold (the amputation's step 2 does). Click it again to take it off early.

**PUSH!** Hold LMB to build the push rate (+0.55/s, -0.9/s let go, capped at 1.2); the drug drains
at rate x 0.09/s. The PUSH meter is green below 0.55 / difficulty and red above; every 0.9 s in the
red is a fast push. The bubbles still in the barrel go in one by one as the plunger passes them. At
empty: "dose delivered...", a 0.9 s beat, done.

**Costs are live** (no results card, no Retry): every mistake is `cost()` the moment it happens,
at the spec's score penalty x `vitals_per_point` (0.25), with the spec's flavour line as the
reason. Miss 2.0, blown vein 4.0, each bubble 2.5 (5.0 when r > 12), each fast push 1.5, and at
delivery a dose outside the band min(40, (|error| - band) x 260) x 0.25 (up to 10), "Underdosed"
or "Overdosed". The spike sites with no price in the spec (air drawn, a purge below the band, the
slap, the tourniquet running out) cost 0 by default (`cost_*` exports), because what they lead to is
billed when it lands. **`spiked(kind)`** goes out at every one of the spec's spike() sites.

**Result** `{"sedation": s}`: in the band, 1.0 + (ratio - 1) x 0.35 (a clean ~1.0); outside it the
ratio itself, so an underdose still stirs every later step (< 0.75) and SQUEEZE! reads it for pulse
noise. `quality` = the spec's score / 100.

**Onlookers** get the whole state at 20 Hz (bubbles, hand, needle, marks, timers) and ease the
bubbles and the hand between updates. **Jolts**: none (the framework excludes this step).
**Bot**: plays all three stages; skill 1.0 draws into the band and trims with the wheel, clears the
bubbles, slaps, sticks at the window's middle and pushes in pulses. Self-test
`--selftest=anesthetic` (`anesthetic:arcade` still works).

### 5.2 DODGE! - Remove the bullet
`forceps` x0, site `gunshot`. GW step 2.
Rhyme: Flappy-style side-scroller through the wound tract.

- 1.0 s intro: the forceps slide down the tract and grip the slug on
  their own. You play the way OUT.
- The level is the existing `generate_channel(seed, difficulty)`
  output: arc length along the centreline becomes X, lateral offset
  becomes Y, so bends become climbs and dips. Channel half-width as
  today (12.5 mm -> 8 mm with difficulty); the gripped slug's
  half-width is 5.8 mm.
- Scroll 12 mm/s. Gravity pulls the slug down; tap LMB or Space for an
  upward impulse. Hold RMB to brake to 50% scroll speed (vitals are
  draining, so braking has a price).
- Walls pinch inward 0.6 mm on each heartbeat (1.25 Hz).
- CO-OP: it's dark. You see 30 mm ahead. A teammate's flashlight on
  the wound (existing `ctx.helper_lights`) doubles that to 60 mm.
- Wall contact = tear: botch 2.5 "Forced the bullet into the wall",
  blood spurt and flinch on the body, knocked back 22 mm, re-centred,
  0.9 s of blinking grace. Record the tear's arc position.
- Leaving the mouth: the bullet arcs into a kidney dish at the panel
  edge and clinks.
- Result: {"bullet_removed": true, "tears": [arc positions]}.
- Jolt: random vertical kick plus 0.35 s wall forgiveness.

### 5.3 WHACK! then WRAP! - Pack and dress the wound
`gauze` x1, variant `pack`, site `gunshot`. GW step 3. One step, two
stages, two command cards.

**Stage A - WHACK! (whack-a-mole).**
- Draw the same tract from 5.2, top-down and stylised. Bleeders = the
  bullet bed + one per recorded tear (pad with seeded extras to a
  minimum of 3, cap at 7). YOUR MISTAKES FOLLOW YOU.
- 1-2 open bleeders are "up" (spurting) at a time for
  1.1 s / sqrt(difficulty). Click one while it's up to slap a wad on
  it. Each needs 2-3 hits (the bed needs 3) to plug.
- STATE: a bleeder that took longer than 4 s from first hit to plugged
  soaks through once, 5 s later, and needs 1 more hit.
- Clicking nothing: the wad lands on skin and stays visible, botch 1.2
  "Packed gauze onto the skin, not into the wound".
- Blood rises from the bottom of the panel like water: starts 0.45
  (0.65 if the bullet is somehow still in), rises 0.055/s x difficulty
  x (open / total). At 1.0: gush, botch 3.0, reset to 0.7, particle
  burst on the body.
- Shift 3+: every 6-10 s a kidney pops up for 0.9 s. Whack it and it's
  botch 2.0 "That was a kidney."
- Ends when all are plugged. pack_quality from peak flood and soaks.
- Jolt: everything currently up ducks early. No cost.

**Stage B - WRAP! (Snake).** See 5.7; pack variant.

### 5.4 SQUEEZE! - Apply the tourniquet
`tourniquet` x0, site `limb`. AM step 2.
Rhyme: the fishing-bar minigame.

**Stage A - Place.** Side view of the limb. The strap sweeps along it
(80 mm/s, ping-pong). The infection front starts where it does today
(3-5.5 cm distal of the marker) and CREEPS proximally in real time
during this stage (1.5 mm/s x difficulty), so the safe zone moves
while you hesitate. Zones as today: green = 5 cm above the front
+/- band (3 cm narrowing to 0.8 cm), amber further up, red on or near
the infection. Click to cinch.
- On the infection: botch 9.0. Too close: botch 5.0. Strap slips off
  (0.8 s), sweep resumes.

**Stage B - Tighten.** Vertical pressure gauge, 0-450 mmHg.
- Your bar rises while LMB is held and falls when released, with a
  little momentum. Bar height = the legacy band (90 mmHg narrowing to
  24 with difficulty).
- The pulse marker hovers around a SEEDED occlusion pressure
  (230-310) with smooth noise and occasional darts. CARRY-FORWARD:
  noise amplitude = 25 x difficulty x (1 + 1.5 x (1 - sedation)). A
  badly sedated patient has a jumpy pulse.
- Occlusion meter fills over 4.0 s of overlap, decays over 8 s
  otherwise. Full = windlass locks itself, clip snaps.
- Bar centre more than 60 above the pulse = over-tight: botch 2.0 per
  0.5 s, limb goes purple, strap creaks.
- RMB locks early at the current fill. Under 40% fill: botch 3.0 "the
  windlass spun free", fill drops to 60% of itself.
- Result: {"tourniquet": placement x fill_at_lock x hold_factor}
  (hold_factor 0.75-1.0 from on-target fraction). This feeds 5.5 and
  5.7 exactly like today.
- Jolt: bar knocked down 40 mmHg.

### 5.5 SAW! - Saw through the limb
`bone_saw` x0, site `limb_cut`. AM step 3.
Rhyme: Pong. A saw goes back and forth; so does the ball.

- The limb CROSS-SECTION (built from site_section as before: skin
  ring, muscle, bones as circles; Bob has two, the flipper four or
  five) sits in the centre of the court. The blade is the ball. It
  passes THROUGH the limb, it doesn't bounce off it. Every crossing is
  one stroke: the cut line sinks, chips fly, and a rasp or grind plays.
- Paddles on the left and right edges are MIRRORED: mouse Y (or W/S)
  moves both together. Top and bottom walls bounce. Return angle
  depends on where the ball meets the paddle.
- Paddle height 22 mm / sqrt(difficulty).
- Tune for about 16 crossings total (roughly skin 1, muscle 4, bone 8,
  far side 3), 12-18 s for a good player.
- LAYERS CHANGE THE BALL. Soft tissue: quick and clean (~170 mm/s).
  "Bone" applies whenever more than 30% of the cut line's chord is
  inside bone: the ball gets heavy (~120 mm/s) and CHATTERS, wobbling
  off its line (amplitude ~6 mm x difficulty) so it has to be read.
  The feel flips as the cut meets and leaves each bone.
- HARD / SOFT RETURNS: holding LMB at contact is a hard return (+25%
  ball speed, so faster sawing, riskier). Not holding is a soft one.
- MISS: the saw jumps out of the cut. botch 2.5 "The saw jumped and
  tore the {layer}", blood and chips on the body, re-serve from the
  centre after 0.6 s.
- CARRY-FORWARD: a seeded artery sits in the muscle. When the cut
  reaches it, spurt = 1 - flags.tourniquet (missing = 0.5). Blood
  splatters a patch of the COURT (radius ~10 + 40 x spurt mm) and the
  ball is invisible while under it. At tourniquet >= 0.85 it's a drip
  and hides nothing. Bleed botch accumulates as in the legacy game.
- BREAKTHROUGH: for the last three crossings the card flashes
  "EASY..." and the ball speeds up 1.3x. If the final crossing came
  off a HARD return: botch 3.0 "Sawed into the table".
- Finish: apply_flags(amputated), thunk, cut_quality from misses and
  the table hit.
- Jolt: both paddles get knocked ~15 mm in a random direction.
- Freeze/READY resume and 20 Hz spectator state (ball, paddles) as per
  the shared frame.
Original art only. It's a saw and an arm, not a tennis court.

### 5.6 (reserved)

### 5.7 WRAP! - Dress the wound / dress the stump
`gauze`. Stage B of GW step 3 (variant `pack`, part of the same x1),
and all of AM step 4 (variant `stump`, x2).
Rhyme: Snake. The bandage roll is the snake; the trail is bandage.

- Grid 16 x 10 cells over the 120 x 80 mm panel. WOUND CELLS: pack =
  a 10-14 cell blob shaped like the wound; stump = a 16-20 cell ring,
  every cell needing 2 layers.
- The roll enters from the left and moves continuously (5 cells/s x
  sqrt(difficulty)). Steer with WASD/arrows. No reversing. The trail
  is permanent.
- You may cross your own bandage ONLY on wound cells; that's how you
  layer (max 3). Hitting your trail anywhere else, or the panel edge,
  is a tangle: botch 2.0 "The bandage tangled", roll respawns next to
  the nearest unfinished wound cell after 0.6 s.
- The roll is finite: pack 60 cells, stump 90. Run out early: botch
  3.0 "Ran out of bandage", then it refills and continues.
- CARRY-FORWARD: some wound cells are BLEEDING. Count = wound cells x
  bleed, where pack bleed = 1 - pack_quality (clamp 0.1-0.8) and stump
  bleed = 0.85 - 0.75 x tourniquet (clamp 0.1-0.8, today's formula).
  A bleeding cell with one layer soaks red after 3 s and counts as
  uncovered again; each soak is botch 2.0 (max one per 2 s). Bad
  earlier work makes the routing puzzle harder.
- The legacy tension mechanic (loose / good / tight) is DROPPED.
- Done when every wound cell is satisfied. Marks string derived from
  path neatness (turn and overlap count) so the finished dressing on
  the body looks as messy as the path was.
- Jolt: lose the last 3 trail cells, botch 2.0, 0.8 s cooldown.

### 5.8 STEER! - Cut around the eye / socket
`scalpel` x0, variant `cut`, site `eye`. EX step 1, EG step 1.
Rhyme: top-down racer on a ring track.

- Track centreline at eye_radius + 14.5 mm, half-width 9 mm. Inner
  wall is the eyeball edge; outer wall is 22 mm past the ring.
- The scalpel drives itself forward: 35 mm/s, or 60 mm/s while W is
  held. A/D steer (140 deg/s, 100 deg/s at speed). One lap.
- On the track = cutting; the incision ribbon opens behind the blade.
  Off the track for more than 0.4 s, or touching the outer wall = a
  free slip: blade lifts, respawns at the cut front after 0.6 s.
- Touching the inner wall = nick: botch 5.0 "The scalpel nicked the
  eyeball" (suppressed under no_fail), plus a slip.
- 2-4 seeded VESSELS cross the track as 6 mm bands. Cross one above
  40 mm/s and it bleeds: a blot hides +/-12 deg of the ring for the
  rest of the step, is recorded in flags as vessel_bleeds, and costs
  1.5 condition on a Hive.
- Hive only: every 3-5 s the pupil snaps to look at the blade (0.4 s
  telegraph), then the eyeball edge bulges 4 mm toward it for 0.6 s.
  On a graft the eye just watches the blade.
- Jolt: heading kicked +/-20 deg.

### 5.9 PRY! - Scoop the eye out
`eye_spoon` x0, variant `scoop`. EX step 2, EG step 2.
Rhyme: lockpicking. Feel for the sweet spot, then lever.

- Top view: eye, socket rim, 4-6 muscle TETHERS at seeded angles (min
  35 deg apart), faintly visible.
- The spoon rides the rim at the mouse's angle. Within 25 deg of a
  tether it wobbles; the wobble is SMALLEST at the sweet spot
  (+/-6 deg; the one tough tether +/-3 deg).
- Hold LMB to lever. In the sweet spot: tension fills over 0.8 s, then
  a wet pop and the tether is gone. Outside it: the spoon shudders and
  after 0.6 s slips out (0.5 s). On a Hive that's botch 2.0 "The spoon
  squeezed the eye"; on a graft the patient just yelps.
- The tough tether takes two pops; after the first its sweet spot
  re-rolls within +/-10 deg.
- STATE: the eye rocks looser with every tether popped. Below Hive
  sedation 0.35 its twitching adds noise to the wobble, so the sweet
  spot is harder to feel the longer you've taken.
- Done when all tethers are popped.
- Jolt: cancels the current lever, no cost.

### 5.10 CUT THE RIGHT ONE! - Snip the optic nerve
`scalpel` x0, variant `snip`. EX step 3.
Rhyme: bomb defusal, with a memory element and a co-op information
split.

- A RULE CARD shows on the panel for 1.5 s at step start, then
  disappears. It ALSO stays on that table's OR wall monitor for the
  whole step, so a teammate can read it out. The operator can't see
  the monitor while leaned in. Solo players have to remember it.
- Hold W to lift the eye (0 -> 1 over 2.4 s, falls over 1.5 s, as
  today). Strands show from lift 0.35; cutting is armed at 0.8.
  More than 3 s cumulative above 0.95 lift strains the nerve: botch
  1.0 per second "The nerve is stretching".
- 4-6 strands by difficulty, each with a colour AND a pattern (solid /
  striped / dotted). Exactly one is the nerve. Seeded rule templates,
  validated to resolve to exactly one strand:
    - "The nerve is the only striped strand."
    - "The nerve is directly left of the red strand."
    - "The nerve is between the blue and the yellow."
    - "The nerve is the second strand from the left." (graft only)
  On a Hive use only colour/pattern/adjacency rules fixed at
  generation, never absolute position, because:
- STATE: once Hive sedation is under 0.75, every stir swaps two
  adjacent strands (0.4 s, visible, trackable). Dawdling makes it
  worse.
- Click a strand (hit radius 3.5 mm). Right: 0.8 s slice, finish.
  Wrong: botch 6.0 "That wasn't the nerve", that strand bleeds, is
  removed, and partly obscures its neighbours.
- Clicking before lift 0.8: "Pull the eye up first: hold W." No cost.
- Jolt: lift drops 0.3, plus the swap above.

### 5.11 GRAB! - Eye into the vat / new eye into the socket
`forceps` x0, variants `place` (EX step 4) and `grab` (EG step 3).
Rhyme: claw machine. STAYS NO-FAIL. No botch calls anywhere. Jolts
ignored. The cost is time, and on a Hive time is sedation.

- Side view. A claw hangs from a rail. Source on one side, target on
  the other, distances seeded. `place`: loose eye -> vat mouth.
  `grab`: vat -> socket. Keep measuring where the real vat stands, as
  the legacy game does.
- A/D move the claw (up to 80 mm/s, with acceleration). Space drops
  it: down, close, up, 1.2 s. It grabs if within 10 mm of the eye.
- The eye is a PENDULUM under the claw, driven by the claw's
  acceleration. Swing past 50 deg and it slips out and falls back to
  where it came from.
- Space again releases. Success if the eye's actual X (swing included)
  is within the target: vat mouth +/-12 mm, socket +/-9 mm. Otherwise
  it bounces off the rim and lands beside it; pick it up from there.
- `grab` only: the eye slowly rotates while hanging (90 deg/s). Record
  the pupil offset at release. Under 20 deg is straight. Otherwise the
  grafted eye renders rotated by that amount on the player until it's
  regrafted. Cosmetic only. Your friend is wall-eyed and it's your
  fault.
- All existing results and side effects unchanged (eye_in_vat, the
  no-vat fallback, the swap firing on eye_seated).

### 5.12 STITCH! - Stitch the eye in / close a laceration
`suture_kit` x1. EG step 4 and the laceration testbed.
Use the existing panel suture game. Add a `ring` variant for the
graft: a closed wound around the socket, 8 stitches (down from 14),
dots hidden under blood at the vessel_bleeds angles from 5.8, tears
cost nothing under no_fail. Result {"eye_stitched": true,
"stitch_marks": "..."}. The marks render on the PLAYER'S FACE around
the grafted eye and persist like the graft does. Leave the laceration
procedure's test_only flag alone; I'll flip it.

---

## 6. Carry-forward chain (must work end to end)

| From | Flag | Into | Effect |
|---|---|---|---|
| INJECTION | sedation | every later step | stirs (existing) |
| INJECTION | sedation | SQUEEZE | jumpier pulse |
| DODGE | tears | WHACK | one bleeder per tear |
| WHACK | pack_quality | WRAP (pack) | bleeding cells |
| SQUEEZE | tourniquet | SAW | spurt hides the pendulum |
| SQUEEZE | tourniquet | WRAP (stump) | bleeding cells |
| STEER | vessel_bleeds | STITCH (ring) | hidden dots |
| GRAB (grab) | eye_offset_deg | player model | wall-eyed graft |
| STITCH (ring) | stitch_marks | player model | stitches on the face |

---

## 7. Phases

After each phase: commit, post the deliverables, and STOP. Wait for me
to say "go". I will playtest and flip the ARCADE_ENABLED flag myself.
Do not start the next phase early, and do not "get ahead" by
scaffolding later games.

- **Phase 0 + 1:** Shared frame (section 4), then SAW!.
- **Phase 2:** GRAB!, both variants.
- **Phase 3:** DODGE! and WHACK! together (they share the tract and
  the tears flag).
- **Phase 4:** WRAP!, both variants.
- **Phase 5:** SQUEEZE!.
- **Phase 6:** DOSE!. (Replaced on 2026-09-21 by the Anesthetic Injection, 5.1.)
- **Phase 7:** STEER!, PRY!, CUT THE RIGHT ONE!, and the STITCH! ring
  variant.
- **Phase 8:** Only on my explicit say-so: remove legacy games and the
  switch.

If a phase can't be done without breaking section 2, STOP and report
rather than pushing through. Otherwise don't stop to ask questions:
make a reasonable call and list it.

---

## 8. Deliverables per phase

For each game built:
- Lab entry and `--selftest`, with the bot results against the targets.
- A net round-trip test and a take-over test (player A leaves
  mid-game, player B resumes after the READY countdown).
- Screenshots on Bob AND the seal where applicable: standing height as
  an onlooker while a bot plays; leaned in at the command card; leaned
  in mid-game; the moment of a failure; the body afterwards.
- The list of `@export` tuning values with their starting numbers.
- Every judgment call you made.
- `docs/ARCADE_SURGERY.md` and `docs/KNOWN_ISSUES.md` updated.
- Confirmation that every legacy game still passes its self-test with
  its flag off.

---

## 9. Explicitly out of scope (ideas parked for later)

- "Crash code": a Helldivers-style arrow-code interrupt the first time
  vitals drop under 25. Good idea, not now.
- Per-action consumable use, tool condition modifiers, skipping steps
  at a penalty.
- A physical arm/scope prop for the panel, screen noise near the
  Sonographer.
- Any new procedure, item, patient, or monster.
