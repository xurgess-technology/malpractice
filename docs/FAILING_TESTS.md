# Failing tests on main

**Read this before running the test suites.** These failures were already on `main` when they were
written down, so seeing them does not mean your change broke something. If you fix one, delete its
section here (and its entry in docs/KNOWN_ISSUES.md, if it has one) in the same commit.

Last checked: 2026-09-22, `main` at `c933607` (0.10.17), by the `strap-fix` task: the whole
`nettest_run.gd` suite plus the headless scenes it touched, each failure below re-run against
`c933607` itself to be sure it was not the branch's doing.

The list got longer that day, and **not because anything broke**: several of these had been failing
for some unknown time with nobody writing them down (`pockettest`, nettest `pockets`, and
`looptest`, whose entry has since been fixed and removed). Of the 22 nettest scenarios, 17 pass,
`full_shift_lag` passes on a quiet re-run, and `brains` and `pockets` fail. (`rocket_boots` failed
that day too; it was a real replication bug, fixed 2026-09-22, and its section is gone.) The
earlier note that everything but this file's entries passed dated from 2026-09-17, `main` at
`ded2d46`.

Two of that day's entries turned out to be **wrong diagnoses, corrected by measuring**. `looptest`
was blamed on loot not surviving a shift change; in fact the test's own bot was shelving its loot
mid-surgery. `hit_feedback` was on this list as 1h, blamed on 0.10.16's stagger change; in fact the
push had never been lost -- the test was shoving a Hive into a wall. Both fixed and removed
2026-09-22. Worth remembering while reading the rest of this file: **an entry here is a lead, not a
verdict.**

`orscreentest` (section 6) went the same way later that day and has been removed: the OR monitor's
case panel was right about every one of its five reported problems. The test hard-coded a supply
count from before SUTURE! gave `gunshot` a fourth step, and it had never been taught that a patient
can die on the table while the shift carries on -- a dead case has no current step and needs no
more supplies, which is the panel's contract, not a fault. Fixed in `tools/orscreentest.gd`.

So did **section 1b**, `doortest`'s four hinged-door E failures, removed the same day: the doors were
right and so was the aiming. The test aims by turning the bot's head and then reads `aim_prompt`, but
the crosshair's ray starts at the *camera*, and with the `camera` setting on "shoulder" the carry
camera puts that camera 1.4 m behind and 0.5 m right of the head, looking along its own line. The
first aim target (a whole door) survived that; a thin open leaf at arm's length did not, and the
three checks after it only failed because that first press never happened. Slots seed their settings
from Zach's, which say "shoulder", so the test read his view preference. `tools/doortest.gd` now pins
first person for its run, exactly as `devtest` did for the same reason. That leaves `doortest` failing
the one gurney check in section 1 and nothing else.

How to run things is at the bottom of this file.

---

## 1. doortest: the paramedics don't push the OR doors open for the gurney

- **Command:** `godot --headless --path . --fixed-fps 60 tools/doortest.tscn`
- **Result:** `FAIL (1 of 91 checks)`, the check `the crew pushed the OR's doors open to bring the gurney through`
  — the only check `doortest` still fails, as of 2026-09-22 (the four in the old section 1b were the
  test's own camera setting and are fixed).
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


## 1f. pockettest: the Night Nurse follows you through a seam

- **Command:** `godot --headless --path . --fixed-fps 60 tools/pockettest.tscn`
- **Result:** `FAILED 2 of 180 checks`:
  `restaurant: the Night Nurse followed the player through the seam (60.0 s, 1444.3 m away)` and
  `restaurant: she crossed exactly once`.
- **Found 2026-09-22** during the strapping fix, and **confirmed identical on plain `main`** at
  `c933607` — the same two checks with the same numbers to the decimal (60.0 s, 1444.3 m), so
  nothing about it is timing-dependent. Never written down before; nobody has looked at the cause.
- The other 178 checks pass, the seams themselves included.
- **It became intermittent on 2026-09-22** with the POCKET_SPACES_2 phase 1 fence (`pockets-phase1`),
  which stops idle wander crossing a seam. Five runs on that branch: **pass, fail, pass, pass, fail**.
  A passing run has her following in **9.2 s, 3.9 m** — a healthy follow, not a near-miss — and a
  failing one still reports exactly 60.0 s and 1444.3 m, which is just "she stayed in the hospital
  while the bot walked into the pocket", so the identical number says nothing about the cause.
- **So it is not fixed, and the branch did not break it either**: a deterministic failure became a
  coin flip. That is a strong hint about the cause. The Night Nurse's `_vanish()` asks
  `random_nav_point` for a point up to **400 m** away, which used to reach the pocket at tile 800;
  the fence now refuses those, so she is far likelier to still be nearby when the bot crosses.
  Whoever picks this up should look at `_vanish()` in `scripts/monsters/night_nurse_brain.gd` and at
  how `_nurse_follows` in `tools/pockettest.gd` stages her, rather than at the seam.

## 1g. nettest `pockets`: client 1 never carries client 2 into the pocket

- **Command:** `-- --only=pockets`
- **Result:** `FAIL` after 140 s: client 1 says `carried 0, client 2's body in pocket false`, and the
  host and client 2 both time out after 120 s `waiting for client 1 to carry client 2 into the
  pocket`. The carry never starts, so nothing about the seam itself is exercised.
- **Found 2026-09-22** during the strapping fix, **confirmed on plain `main`** at `c933607` with the
  identical message, and it reproduces every run (not a load flake). Never written down before.
- Not to be confused with the headless `pockettest` scene (section 1f), which fails on something
  else entirely (the Night Nurse).

## 1i. nettest `full_shift_lag` is a load flake

- Failed once on 2026-09-22 during a full suite run (`timed out after 90 s waiting for start` on
  client 1 — it never finished connecting, before any gameplay), while three other slots were
  running Godot. **Passed on its own re-run in 66 s**, against the 895 s it burned failing.
- It runs with 120 ms lag and 3% loss, so its connection window is the tightest in the suite.
  Re-run it alone before believing a failure.

## 1j. The host stalls 130-540 ms mid-shift, headless, even when idle

- **Not a failing test** — found 2026-09-22 while fixing the rocket-boot burn, with temporary
  instrumentation on the host's net tick. It is recorded here because it is the kind of thing that
  makes other tests look flaky.
- **What was measured:** gap probes showed the host's physics frame routinely stalling **130-330 ms**
  on an otherwise quiet machine, and once **541 ms** — a gap that straddled an entire rocket burn, so
  `_build_state` never ran while the bit was true and there was nothing to send. That was the second
  half of the boots bug (fixed in 0.10.30 by holding and counting the burn rather than sampling it).
- **The stalls themselves were never explained**, and they are no longer anyone's known bug. Anything
  that depends on a short-lived state being sampled at 20 Hz is vulnerable to them, so this is worth
  its own look before the next netcode feature leans on snapshot timing.

## 3. perfprobe --pockets crashes after the warmup, before it measures anything

- **Command:** `godot --path . tools/perfprobe.tscn -- --pockets` (a real window; `tools/pocketperf.ps1`
  runs it minimized and never activated)
- **Result:** twelve `BUG, indexing did not unpair geometries from light` errors from
  `renderer_scene_cull.cpp`, then `CrashHandlerException: Program crashed with signal 11`. The log
  stops at the warmup line and **not one scenario is measured**.
- **Found 2026-09-22** by the POCKET_SPACES_2 phase 3 task, and **confirmed pre-existing**: the same
  crash, the same twelve errors, the same 67-line log with the Chapel taken back out of
  `PocketSpaces.LAYOUTS` and perfprobe's kind loop pinned to the old `["none", "factory",
  "restaurant"]`. It is not the third space's doing.
- **Where the fault is.** `perfprobe._run_pockets()` calls `game.start_session()` again, once per
  kind, and the first of those restarts lands immediately after the one-time warmup. Tearing that
  down while the renderer still holds the warmup shelf's light-geometry pairings is what trips the
  engine bug. Plain `perfprobe` (one session, no restart) completes all 27 scenarios on the same
  machine and only crashes **at exit**, after the summary table has printed, which is harmless and
  has presumably been happening for a while.
- **The way round it, which works today:** `-- --pocketkind=<kind>` forces the kind *before* the one
  and only `start_session` and measures that space in the session that is already up. Added by the
  same task; it is what the Chapel's numbers were taken with.
- **Where to look:** whether `_run_pockets` can wait out the renderer (a few frames, or
  `RenderingServer.force_sync()`) before restarting, or whether it should simply be rebuilt on top
  of `--pocketkind` and run one process per kind.


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
- **The seed numbers are not the bug — don't chase a new one.** Which seeds trip this depends on
  whether that seed's map got a pocket, because the entrance stubs reserve room slots and the whole
  wing lays out differently. Shown on 2026-09-22 with mapcheck's own flag, nothing else changed:
  `--seeds=8 --builds=8 --build_pocket=none` fails seeds **3 and 4**, and the same command with a
  pocket fails seeds **1 and 3**. Same bug, same ~2.6-3.3 m, different seeds.
- So a change that alters how often pockets appear moves this list. POCKET_SPACES_2 phase 1
  (`pockets-phase1`) did exactly that, and the full run there reports **seeds 1, 38 and 112** —
  seed 1 being the pre-existing bug landing on one more seed, not a new fault.

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
- **Two work slots must not run nettest at the same time _on the same ports_.** `nettest_run.gd`'s
  ports start at 7790 and are numbered per scenario, not per slot, so two slots running it together
  clash and a scenario fails for no reason (seen 2026-09-22: `monsters` failed on a port clash, then
  passed alone). If a nettest scenario fails and another slot was also testing, re-run it alone
  before believing it.
- **Or give your slot its own port base:** `-- --port=7900` (one port per scenario from there, so
  leave a slot's bases about 100 apart). Used on 2026-09-22 to run `combat` and `graft` in wt-4
  while wt-1 was running the whole suite on 7790/7800, with no clash either way. This is the way to
  test without waiting for another slot to finish; the machine still gets loaded, so the flake
  warning below still applies.
- **Expect flakes when the machine is loaded.** With four slots running Godot at once, wall-clock
  timeouts get tight: `downedtest` has failed once under load and then
  passed on a quiet re-run. Re-run alone before chasing.
- Windowed screenshot tools write to `tools/game_shots/` and friends: `menushot`, `faxshot`,
  `tipshot`, `database_shot` (`-- --wall`, `-- --wall2`), `gameshot`, `bootsshot` (rocket boots)
