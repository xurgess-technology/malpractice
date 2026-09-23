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
first person for its run, exactly as `devtest` did for the same reason.

**Section 1, `doortest`'s gurney check, went the same way on 2026-09-23 and has been removed.**
`doortest` now passes **all 91 checks**. It was half test bug and half product bug, and neither half
was visible until the door's `amount` was logged frame by frame against the crew's position through
an arrival.

- **The product half — late, not clipping.** The OR doors did open, all the way to 1.00, and the
  crew's *centre* never crossed a shut leaf. But they only began to move 0.67 m before that centre
  reached the door plane, and the paramedic pulling at the front stands **1.55 m ahead** of `cr.p`
  (`scripts/loop/crew.gd`). He and the gurney's nose were through a dead-shut door — he was 0.9 m
  past the plane before a leaf twitched. `Doors._agents` was sensing a three-metre convoy as the
  single point in its middle, and the lateral bound in `_push_check` is what held it off: the crew
  swings in off the hallway at a slant and its centre is outside the doorway's width until the last
  moment. Fixed by giving the crew agent a `push_pos` at `CREW_LEAD` (1.55 m) ahead of its middle,
  used for manual-door pushes only; the automatic sensor still uses the middle, since
  `CREW_SENSOR_RANGE` already allows for the convoy. The doors now stand fully open before anything
  reaches them.
- **The test half — the check was watching nothing.** The crew crosses about **0.96 m** off the
  doorway's centre, and the doorway is **3 m** wide, so a flat `|lp.x| < 0.8` side bound never once
  contained it: closest approach **0.81 m**, missed by a centimetre. *Both* gurney checks in that
  loop were vacuous, which is why "the crew never passed the doorway with the door mostly shut" had
  been quietly "passing" — it was never evaluated, not satisfied. The bound is now the door's own
  `width * 0.5`, which is what "in the doorway" actually means.
- **Not the same bug as the playtest's monsters walking through doors** (docs/KNOWN_ISSUES.md,
  "PLAYTEST 2026-09-22"), whose reproduced half was the open leaf's collider and is already fixed.
  This one is crew-only: nothing else in the game is sensed at a point set back from its leading
  edge. `4b7a431` ("Operator rooted at the table") was **not** involved — the lead named in the old
  section was a dead end.

**Sections 3 and 1l went the same way on 2026-09-23 and have both been removed.** They were one bug
written up twice by two tasks who never met: `tools\perfprobe.ps1 -Extra "--pockets"` printed a burst
of `ERROR: BUG, indexing did not unpair geometries from light` from `renderer_scene_cull.cpp`, then
`CrashHandlerException: Program crashed with signal 11`, straight after `[warmup] built and drew
everything once`, and not one scenario row was ever measured. Reproduced here on `fix-perfprobe` at
`f82a3bb` before anything was touched: the same twelve errors, the same place.

- **It was never any one pocket space, and never ours.** Three independent confirmations, kept
  because they rule out three different things: POCKET_SPACES_2 phase 3 got the identical crash (the
  same twelve errors, the same 67-line log) with the Chapel taken back out of `PocketSpaces.LAYOUTS`
  and the kind loop pinned to the old `["none", "factory", "restaurant"]`; phase 2 got it with the
  Natatorium out of `PocketPlan.KINDS`; phase 4 got it on a **detached checkout of plain `main`
  (`3b30969`)** with only `tools/perfprobe.ps1` brought over, no Laundromat in the tree at all.
- **It was the restart.** `_run_pockets` called `game.start_session()` once per kind, tearing a whole
  level and all its lights down and building another, and the first of those landed immediately after
  the one-time warmup. docs/KNOWN_ISSUES.md already had that renderer error down as a Godot bug seen
  in windowed runs ("Seen during this work and not ours"); doing it once per kind turned an error
  into a crash.
- **It is not a race, which is the one new measurement.** The obvious fix -- let the renderer settle
  before tearing down -- does nothing. `RenderingServer.force_sync()`, sixty frames, then
  `force_sync()` again, between the measuring and the `start_session`, crashes in exactly the same
  place with exactly the same twelve errors. So there was never a window to wait for, and any fix
  that timed the teardown would have been luck.
- **Our teardown was not at fault.** `game._clear_level` tears a pocket down and `queue_free()`s the
  level node; nothing frees a light by hand or keeps a `RID` past the node, and `WingLoader` does not
  touch lights. The engine's own light/geometry pairing index is what does not survive it.
- **The fix routes around it instead of racing it.** `--pockets` is now **`tools\perfprobe.ps1`'s**
  loop, not the probe's: one Godot process per kind, each running the `--pocket=<kind>` path that
  already worked (plus `--pocket=none` for the bare-hospital baseline), and the wrapper stitches their
  tables into one. Nothing restarts a session, so the engine bug is never reached. The kinds are read
  out of `PocketPlan.KINDS` in `scripts/level/pockets/pocket_plan.gd`, so a new space joins the sweep
  by itself. `_run_pockets` is gone; `_pocket_views` is now the one views list, with the four views
  only `_run_pockets` had (the factory catwalk, the restaurant kitchen, the seam from the pocket side,
  and the two mirrored teammates) folded back into it, so nothing stopped being measured.
- **What the next person should know.** `perfprobe.tscn -- --pockets` on its own now prints a line
  telling you to use the wrapper and quits 2 -- the loop cannot live in one process. Per-kind logs are
  `.godot\perfprobe-<kind>.log` and the whole sweep is concatenated into `.godot\perfprobe.log` as
  before. **The at-exit crash is still there** (the same engine bug, on the teardown at `quit()`), and
  is still harmless: it now happens strictly *after* the table has printed, and the wrapper judges a
  kind by the rows it parsed, never by an exit code, so a crashing exit cannot fail a good run. Fixing
  that one is Godot's job, not ours.

**Section 1g, nettest `pockets`, went the same way on 2026-09-23 and has been removed.** The scenario
now passes: 44 s, 46 s and 46 s on three runs, with the host reporting "client 1 carried client 2 into
the pocket" and client 2 confirming from inside its own body that it stayed there. It was neither the
seam nor the carry, and the old entry's headline was wrong: **the carry started fine every time.**

- **Which side dropped it: client 1, and not for a gameplay reason.** The old note said "carried 0,
  client 2's body in pocket false" and concluded the carry never started. It does start. What client
  1 actually reports most runs is `timed out after 60 s waiting for walking into the stub` — the
  *second* walk in, the one with a teammate on its shoulder. Logging its position, velocity, slide
  collisions and physics-frame count once a second through the whole scenario is what separated the
  two: the player was at a healthy 2.04 m/s (walk speed x `CARRY_SPEED_K`), on the floor, with no
  collision but the ground, and still covering **0.17 m per second of wall clock**. It was not being
  blocked or snapped back. It was running at **5 physics frames a second**, against 130-160 fps for
  the identical walk a few seconds earlier without the body.
- **The cause is one display-server call per frame.** `Player._key_label` (scripts/player.gd) turns a
  bound action into a prompt label through `DisplayServer.keyboard_get_keycode_from_physical`.
  Headless has no keyboard layout, so that call fails and Godot prints an eight-line error **with a
  GDScript backtrace** -- and `_update_aim_core` asks for the drop key on every frame you are
  carrying someone ("Put them down  (Q)"), and only then. So picking a teammate up turns on a
  per-frame error flood, the process spends its frame writing to a pipe, and the client collapses.
  Nothing else in the game calls `_key_label`, which is why only the carrying half of this scenario
  was ever slow.
- **Fixed by remembering the label.** `_key_label` now caches physical keycode -> label in a static
  dictionary, and in headless skips the layout translation entirely (the physical key *is* the
  label). One lookup per distinct binding instead of one per frame; rebinding lands on a different
  keycode and so a different entry. A run's `tools/nettest_logs/pockets_c1.log` now has **zero**
  `Not supported by this display server` lines, against thousands.
- **What the next person should know.** *Any* per-frame error on a headless nettest process is a
  25-30x slowdown, not a cosmetic nuisance: `nettest_run.gd` only echoes `[net...]`, `[stats]` and
  `SCRIPT ERROR` lines, so a flood like this is **invisible in the console** and only shows up in
  `tools/nettest_logs/<scenario>_<role>.log`. Read that file before believing a nettest timeout is
  about gameplay. The same flood was happening in the `downed` scenario, which carries too; it passed
  only because its carry walk is 1.2 s long. And be careful profiling these: adding `print`s to find
  the hot spot slowed every process to 7 fps and hid the difference between carrying and not.
- **In the shipped game this was a slow prompt, not a stall.** With a real display server the call
  succeeds and merely costs a layout lookup every frame while you carry; nobody would have seen it.

**Section 1k, spawncheck's 600 `suture_kit` failures, went the same way on 2026-09-23 and has been
removed.** `spawncheck` is now green: **300 seeds x 2 ailments, "OK - every rule held"**, against
600 failures on `main` at `fca51db` (reproduced here first, same count, all of them `gunshot`).
**It was a test-scope bug, and the product was fine** -- but the comment that sent everyone the
wrong way was not.

- **The old lead was right about the mechanism and wrong about the conclusion.** `suture_kit` is
  indeed missing from `Items.SURGICAL`, which is the list `ItemSpawner.plan`'s needed/herring split
  iterates, so the case plan never plans one. But `spawncheck` only ever looked at `plan()`, and a
  shift's supply is **two plans**: `game._populate_shift_world` scatters three stacks of kits
  (and of syringes) through what is now `ItemSpawner.loose_supply_plan`, before any case arrives.
  spawncheck could not see the path that actually supplies the item it was failing on.
- **Measured before changing anything, because the interesting question was whether a gunshot shift
  can be uncompletable.** A probe replayed the real scatter against real levels for 300 seeds: all
  three kits land in a legal container on **every** seed (never the floor fallback), in three
  distinct building units, **never** in a `SAFE_ROOMS` room, never in a type `Items.found`
  disallows, and at least one is past `FAR_M` on every seed (worst seed 29 at 26.4 m against a bar
  of 24). Total kits per seed 3 to 6 against a need of 1, so `CONSUMABLE_MULT` is met on the worst
  seed. The scarcest seed still had **86** legal spots to choose from. **No shift is uncompletable,
  and no kit lands anywhere unreasonable.** `tools/playtest.tscn -- --god --seed=2` (a gunshot
  shift) confirms it end to end: the bot found a kit in the wings, carried it in and closed the
  wound, clocking out stable.
- **The one guarantee the scatter does not meet is spread: 3 places, not `CONSUMABLE_STACKS[0]`
  (6).** That is now written down rather than discovered, and spawncheck asserts the weaker bar for
  a `LOOSE_SUPPLY` kind and the full one for a `SURGICAL` kind.
- **Adding `suture_kit` to `SURGICAL` was the other candidate and would have cost more.** It is
  read in six places -- `game.gd`'s `_level_info_usable` sizes `tool_spawns` against its length,
  `database_pages.gd` orders the whole database by it, `dev_room.gd` already appends `suture_kit` by
  hand and would have doubled it, and spawncheck's own slot-width check widens with it -- and it
  would have left two supply paths for one item unless `spawn_suture_kits` were deleted, which is
  the downed-teammate table's supply and must exist on amputation shifts too. The measurement said
  the product was fine, so the test was the thing to fix.
- **Two real bugs fell out of the measurement anyway**, both caught by the new checks rather than by
  reasoning. The scatter hard-coded stacks of 1-2 instead of the kind's own `batch`, so syringes
  spawned in packs of 1 while `Items` and the database page both promised 2 to 3. And `plan()` was
  called with an empty `used` set, so on about a fifth of seeds the case plan put a stack into a
  slot a kit or syringe already occupied -- two items inside each other in one drawer. `plan()` now
  takes the spots already taken, and spawncheck fails on a double-booking (max 2 per seed before,
  0 now).
- **What the next person should know.** A supply kind can live outside `Items.SURGICAL` on purpose;
  `ItemSpawner.LOOSE_SUPPLY` is the list of those, it is the single source for how many stacks each
  gets, and anything checking "what a shift holds" must read both it and `SURGICAL`. One more place
  was reading only `SURGICAL` and is fixed here: `shift_loop.missing_supplies()`, so the objective
  line now actually says `BRING TO THE OR SHELF: Suture kit x1` instead of going quiet.

How to run things is at the bottom of this file.

---

## 1f was two bugs, both fixed 2026-09-23 (`fix-1f`)

The Night Nurse "followed the player through the seam" failure, and the `laundromat seam 0 ... the
follower crossed exactly once` failure recorded beneath it as a lead, were **not the same fault and
neither was leftover state from `_run_space`**. Three days of notes here read them as one moving,
order-dependent bug; measuring found two ordinary ones. Kept as a short note because the reasoning
that misled everybody is worth not repeating.

- **The Night Nurse wedged on the floor.** She was not staying behind, refusing to cross or failing
  to see the player: she was walking on the spot in a hospital corridor for the whole 60 s, at
  `y = 0.000943 m` -- a hair inside the physics safe margin of `0.001` -- with her capsule tangent
  to the map-wide floor box. `move_and_slide()` spent all six of its slides on that one contact
  every frame: six collisions, all with the floor's own upward normal, all with zero travel.
  Lifting her two centimetres freed her instantly and every horizontal direction was clear up
  there. `step_toward`'s existing unjam could not help, because it only sidesteps, and what was in
  the way was underfoot. Fixed with `_unwedge()` in `scripts/monster.gd`: a monster that has gone
  nowhere at all for a second steps up over the lip, when both the lift and the step after it
  measure clear. **Which space it hit moved between runs because the pocket builds on a worker
  thread**, so a shift takes a slightly different number of frames each run and everything after it
  diverges -- nothing to do with the space, the seam or the run order.
- **The follower crossing check was counting from a window.** `pocket_spaces.crossings` keeps only
  the last 64 crossings; a full `pockettest` run makes more than that, monsters and items included,
  so once the window is full an older entry for the same body falls off the front and the
  before/after delta reads 0 instead of 1. That is why it only ever bit the last space, why it
  moved about, and why `--only=<kind>` was always green. `crossing_tally` / `crossed_times()` now
  keep a count that is never trimmed, and `tools/pockettest.gd` counts with it.

`pockettest` runs green: four full runs of 670 checks on `fix-1f`. On plain `main` the full run
failed every time it was tried (4 of 670 at `0756682`), and the cut-down reproducer
`--only=factory,natatorium` failed about half its runs -- which is all "it moves between runs" ever
was, and why one green run proves nothing here.

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

---

## 1m. A hospital corridor's 1% low of 30, on an idle machine

- **Not a failing test** — measured 2026-09-22 by the Chapel task during the perf read, on a machine
  with zero other Godot processes, final content, q1/medium.
- The Chapel's own worst view read **112 avg / 93 1% low** against a bar of 60 avg and 1% lows above
  50, and every view in the space beat the hospital corridor it opens off. **The bar is met.**
- But the *corridor baseline in the same table* read **86 avg / 30 1% low** — the only figure in the
  run under the bar, and it is **untouched hospital**, nothing to do with pocket spaces.
- It is the **first scenario measured**, so it may simply be the run settling rather than a real
  stutter. Nobody has checked. Recorded here because it is exactly the kind of number that gets
  noticed weeks later and blamed on whatever shipped near it.

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

- **A headless run starts from `Settings.DEFAULTS`, not from this machine's settings.** Every
  `tools/*test.tscn`, nettest's child processes and windows opened onto a scene in `res://tools/`
  boot on the defaults and never read or write `user://settings.cfg`, so a test measures the code
  rather than whoever owns the machine. (Slots seed their save folder from Zach's, which says
  `camera="shoulder"`; that read his view preference into four separate tests in one day.) Nothing
  to opt into and nothing to restore -- a run that crashes leaves the saved settings alone, because
  they were never opened. A test that genuinely wants settings behaviour calls
  `Settings.use_path("user://mytest_settings.cfg")` on a scratch file of its own, as
  `tools/settingstest.gd` and `tools/carrycamtest.gd` do. See `_machine_run` in `scripts/settings.gd`.
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
