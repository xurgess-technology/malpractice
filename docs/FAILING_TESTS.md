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
- **Update 2026-09-22 (the `brains-out` task):** under load it is not intermittent at all — it failed
  three runs in a row while other slots were running tests, always with the same message:
  `timed out after 60 s waiting for client 1's burn on client 2`, while client 1 itself passes
  (`flew into the wall; hp now 2`). Reproduced on plain `main` at `eef06c7` from a detached checkout
  under the same load, so it is not any branch's doing.
- So **check what else is running before judging it**: "flaky" here means load-dependent, not
  random. The failing half is always the *second client* seeing the first client's burn, which is
  the hint if anyone does chase it — it looks like a replication step missing its window when frames
  are scarce, rather than a broken rule.

## 1e. looptest: carried loot does not survive the shift, and the furnace pays $0

- **Command:** `godot --headless --path . --fixed-fps 60 tools/looptest.tscn`
- **Result:** `result=FAIL failures=4`, all four:
  - `the loot is still in hand`
  - `carried loot survives into the next lobby`
  - `the bot threw the loot into the furnace and sold it for $0`
  - `last shift's untouched loot was cleared`
- **Found 2026-09-22** by the `brains-out` task, and confirmed on plain `main` at `eef06c7` from a
  detached checkout in a work slot, so it is not that branch's doing. It was never written down.
- **They look like one fault, not four:** the bot does pick the loot up (`the bot picked up loot`
  passes), and is then not holding it a moment later, so everything downstream — surviving the
  lobby, the furnace sale, the clear-up — fails behind that. Nobody has looked at the cause yet.
- **Where to look:** whatever empties a hand between the pickup and the next check
  (`tools/looptest.gd` around lines 184-221), and the shift/lobby transition that is supposed to
  carry hand slots across. Note the loot kind is whatever is nearest, so this is not about one item.

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

## Running the tests

The Godot binary is `C:\Users\ZachBurgess\Desktop\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe`
(the `.exe` in that path is a folder). From Git Bash, run from the project root.

- Import first after pulling or adding assets: `godot --headless --path . --import`
- **Always add `--fixed-fps 60`** to headless test scenes (about 12x faster).
- **Run headless tests one at a time per checkout.** Parallel runs in the same directory segfault.
- Test scenes, each prints `result=PASS` or `FAIL` at the end: `tools/*test.tscn` (carrycamtest,
  combattest, controlstest, databasetest, devtest, doortest,
  downedtest, fogtest, inventorytest, looptest, orscreentest, pockettest, settingstest,
  straptest) and
  `tools/monster_lab.tscn`
- A bot plays a whole shift: `tools/playtest.tscn -- --god --seed=N`
- Map validation: `godot --headless --path . -s tools/mapcheck.gd`
- Multiplayer, every scenario as real processes: `godot --headless --path . --script tools/nettest_run.gd`
  (`-- --only=wall,surgery` for a few)
- Windowed screenshot tools write to `tools/game_shots/` and friends: `menushot`, `faxshot`,
  `tipshot`, `database_shot` (`-- --wall`, `-- --wall2`), `gameshot`, `bootsshot` (rocket boots)
