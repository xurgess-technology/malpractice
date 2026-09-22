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

## 1f. pockettest: the Night Nurse follows you through a seam

- **Command:** `godot --headless --path . --fixed-fps 60 tools/pockettest.tscn`
- **Result:** `FAILED 2 of 180 checks`:
  `restaurant: the Night Nurse followed the player through the seam (60.0 s, 1444.3 m away)` and
  `restaurant: she crossed exactly once`.
- **Found 2026-09-22** during the strapping fix, and **confirmed identical on plain `main`** at
  `c933607` — the same two checks with the same numbers to the decimal (60.0 s, 1444.3 m), so
  nothing about it is timing-dependent. Never written down before; nobody has looked at the cause.
- The other 178 checks pass, the seams themselves included.

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
