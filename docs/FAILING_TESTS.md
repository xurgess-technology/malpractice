# Failing tests on main

**Read this before running the test suites.** These failures were already on `main` when they were
written down, so seeing them does not mean your change broke something. If you fix one, delete its
section here (and its entry in docs/KNOWN_ISSUES.md, if it has one) in the same commit.

Last checked: 2026-09-17, `main` at `ded2d46`. The failures reproduce identically on `58d088a`, the
commit before that day's merge. Everything else passes: every headless test scene, three playtest
shifts (`--god --seed=1..3`) and all 19 multiplayer scenarios in `tools/nettest_run.gd`.

How to run things is at the bottom of this file.

---

## 1. doortest: the paramedics don't push the OR doors open for the gurney

- **Command:** `godot --headless --path . --fixed-fps 60 tools/doortest.tscn`
- **Result:** `FAIL (1 of 82 checks)`, the check `the crew pushed the OR's doors open to bring the gurney through`
- **The check:** `tools/doortest.gd`, around line 361. While the paramedic crew is right in the OR
  doorway (`|lp.z| < 0.9`, `|lp.x| < 0.8` in the door's frame), the OR door's `amount` must go past
  0.7 at some point before the patient is on the table. It never does.
- **The patient still arrives.** The crew gets through, so a shift isn't broken; the doors just
  don't visibly swing for them. Whether the crew clips through a closed door or the door opens too
  late for the check to see it hasn't been established.
- **Where to look:** how the crew pushes manual doors (the loop's crew movement and the door scripts
  in `scripts/doors/`), and `scripts/player.gd` from commit `4b7a431` ("Operator rooted at the
  table"), which changed how the crew and the operating player push each other. That commit is the
  most recent change near this behaviour, but it hasn't been confirmed as the cause.

## 1b. doortest: four more failures in the hinged-door E section

- **Command:** `godot --headless --path . --fixed-fps 60 tools/doortest.tscn`
- **Result:** these four, alongside the gurney one above:
  - `the open door can be aimed at:` (the prompt comes back empty)
  - `E again closes it (-1.00)`
  - `E from the tunnel side swings it away from the player (-1.00, max_out 90)`
  - `closed again`
- **Found 2026-09-22** while fixing the open-leaf collision bug (0.10.10), on plain `main` before
  that change, so they are not its doing. They were simply never written down: this file recorded
  only the gurney failure, so `doortest` has been failing 5 checks, not 1, for some unknown time.
  The totals move because that fix added checks: 5 of 82 before it, 5 of 91 after, the same five.
- **They look like one fault, not four:** all four are about opening or closing a hinged door with
  E and reading its prompt, and the `-1.00` values suggest the door's `amount` is not being read at
  all rather than being wrong. Nobody has looked yet.

## 1c. Strapping a monster to a table is broken, in three places at once

Found 2026-09-22 by two tasks independently, and confirmed on plain `main` each time (once by
stashing, once from a clean checkout, once by the orchestrator running the baseline directly). None
of it was written down before. The three look like **one fault**, not three: every one of them is a
monster failing to get strapped to a table.

- **`combattest`: 1 of N, `a taken table does not offer to strap`** (the prompt reads
  'Put the Sonographer down').
  `godot --headless --path . --fixed-fps 60 tools/combattest.tscn` → `result=FAIL failures=1`.
- **nettest `combat`: times out on strapping a monster.**
  `godot --headless --path . --script tools/nettest_run.gd -- --only=combat`. It sedates the monster
  at t=60 and then never drags/straps it — a gameplay step, not a connection step.
- **nettest `graft`: `timed out after 30 s waiting for the cut step`.**
  `-- --only=graft`. Same shape: it cannot get the monster onto the table to start cutting.

Nobody has looked into the cause yet. Since GRAFTING and the monster cases both depend on getting a
monster strapped down, this is probably worth more than its line count suggests.

## 1d. nettest `rocket_boots` is flaky under load, not broken

- Failed once during a full suite run on 2026-09-22 while four Godot instances were running in other
  work slots, then **passed three times in a row** on re-run (43 s each).
- Treat a lone `rocket_boots` failure as a flake first: re-run it alone before chasing it. If it ever
  fails on an otherwise idle machine, that is new information worth recording here.

## 2. mapcheck: a morgue tray out of reach on seeds 38 and 112

- **Command:** `godot --headless --path . -s tools/mapcheck.gd`
- **Result:** exit 1, with
  - `seed 38: 1 containers / anchors out of reach, e.g. anchor 92 (tray, morgue) at (134.9, 0.96, 29.8), nav 3.35 m away`
  - `seed 112: 1 containers / anchors out of reach, e.g. anchor 38 (tray, morgue) at (31.7, 0.96, 59.1), nav 2.60 m away`
- **Effect:** one morgue tray on those seeds can't be reached by the bot's navigation, so loot or
  supplies on it may be unreachable in that shift.
- **Already noted** in docs/KNOWN_ISSUES.md (search for "morgue tray"): seed 112 has been reported
  before, and seed 149 has too; seed 38 is new as of 2026-09-17.
- **Where to look:** morgue furnishing in `scripts/level/room_furnish.gd` (where tray anchors are
  placed against walls or equipment) versus the navmesh bake around them.

## 3. The laser surge plays no sound (`dev_zap_01`)

- **Not a test failure**, but it logs a warning during windowed runs:
  `Audio: no cue named 'dev_zap_01' (run node tools/gen_audio.mjs).`
- **Cause:** `scripts/scan_fx.gd` line 262 calls `_sfx("dev_zap_01", -10.0)`. The Audio autoload
  registers numbered files as one cue without the number (`dev_zap_01.wav` and `dev_zap_02.wav` are
  the cue `dev_zap`, picked at random), the way `scripts/dev/dev_room.gd` line 522 already uses it.
- **Likely fix:** call `_sfx("dev_zap", -10.0)`. The WAV files exist; nothing needs regenerating.

## 4. devtest: the free camera leaves your body showing when you untick it

- **Command:** `godot --headless --path . --fixed-fps 60 tools/devtest.tscn`
- **Result:** `result=FAIL failures=1`, the check `unticking it puts you back behind your eyes`
- **The check:** `tools/devtest.gd`, in `_free_cam()` (around line 496). After the panel's "Free
  camera" box is unticked it wants `not fc.is_on() and me.camera.current and not me.dev_input_held
  and not me.body_visual.visible`; one of those is still wrong, most likely the body.
- **Noticed 2026-09-18** on the `graft-strap` branch and confirmed on `main` at `a50899a` with the
  branch's changes stashed, so it is not that branch's doing. It was not in this file before, so it
  broke some time after the 2026-09-17 sweep.
- **Where to look:** `scripts/dev/free_cam.gd` `stop()` / `_show_body_on`, and whatever else turns
  the local body on and off (the carry camera's `set_carry_body`, `Player._refresh_self_body`).

---

## 5. nettest `brains`: the client never gets a hive view

- **Command:** `godot --headless --path . --fixed-fps 60 --script tools/nettest_run.gd -- --only=brains`
- **Result:** `FAIL`, "timed out after 200 s waiting for the client's hive view and echo (hive false echo false)"; the client logs `Invalid access to property or key 'hive_view' on a base object of type 'Nil'` repeatedly (`tools/nettest.gd` around line 876).
- **Noticed 2026-09-19** while merging `sono-brain`; it fails the same on `main` at `56d6b6f`, before that merge. Likely from the 0.7.1 eyeball changes, not confirmed. The other 21 scenarios pass.

---

## 6. orscreentest: the OR monitor's case panel is wrong in several places

- **Command:** `godot --headless --path . --fixed-fps 60 tools/orscreentest.tscn`
- **Result:** `[orscreen] FAIL`, with these problems:
  - `an incoming case shows its supplies`
  - `step 1 is todo, expected current`
  - `supplies: 0 rows for 3 needed kinds`
  - `saw every step of amputation become current ([0, 1])`
  - `the screen read stable when the shift was won`
- **Found 2026-09-22** while building the minimap, and confirmed on plain `main` at `c933607` by
  checking the baseline out directly in the same slot. It was not in this file before.
- **How many you see varies.** It is a playtest: a bot plays a real shift, so how far it gets
  changes between runs and so does how many of the five a run reaches. The branch run saw 1 of them
  (`shifts_won=1`, 438 s); the `c933607` baseline saw all 5 (`shifts_won=0`, 1500 s). Treat **any**
  of those five names as this entry, and the count as meaningless.
- **They look like one fault:** every one is the OR wall monitor's case panel disagreeing about a
  case's steps or its supplies.
- **Where to look:** `scripts/orscreen/or_screen_model.gd` (what the panel says a case needs and
  which step is current) against `tools/orscreentest.gd`'s expectations. Nobody has looked yet.

---

## Running the tests

The Godot binary is `C:\Users\ZachBurgess\Desktop\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe`
(the `.exe` in that path is a folder). From Git Bash, run from the project root.

- Import first after pulling or adding assets: `godot --headless --path . --import`
- **Always add `--fixed-fps 60`** to headless test scenes (about 12x faster).
- **Run headless tests one at a time per checkout.** Parallel runs in the same directory segfault.
- Test scenes, each prints `result=PASS` or `FAIL` at the end: `tools/*test.tscn` (braintest,
  carrycamtest, combattest, controlstest, databasetest, devtest, doortest,
  downedtest, fogtest, inventorytest, looptest, orscreentest, pockettest, settingstest,
  straptest) and
  `tools/monster_lab.tscn`
- A bot plays a whole shift: `tools/playtest.tscn -- --god --seed=N`
- Map validation: `godot --headless --path . -s tools/mapcheck.gd`
- Multiplayer, every scenario as real processes: `godot --headless --path . --script tools/nettest_run.gd`
  (`-- --only=wall,surgery` for a few)
- **Two work slots must not run nettest at the same time.** `nettest_run.gd`'s ports start at 7790
  and are numbered per scenario, not per slot, so two slots running it together clash and a scenario
  fails for no reason (seen 2026-09-22: `monsters` failed on a port clash, then passed alone). If a
  nettest scenario fails and another slot was also testing, re-run it alone before believing it.
- **Expect flakes when the machine is loaded.** With four slots running Godot at once, wall-clock
  timeouts get tight: `rocket_boots` and `downedtest` have each failed once under load and then
  passed on a quiet re-run. Re-run alone before chasing.
- Windowed screenshot tools write to `tools/game_shots/` and friends: `menushot`, `faxshot`,
  `tipshot`, `database_shot` (`-- --wall`, `-- --wall2`), `gameshot`, `bootsshot` (rocket boots)
