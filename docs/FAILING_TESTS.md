# Failing tests on main

**Read this before running the test suites.** These failures were already on `main` when they were
written down, so seeing them does not mean your change broke something. If you fix one, delete its
section here (and its entry in docs/KNOWN_ISSUES.md, if it has one) in the same commit.

Last checked: **2026-09-25, `main` at `f3a60f9` (0.12.5)** plus this sweep's three fixes, by the
item-4 sweep (cloud Linux, `godot4` 4.7.2): **every** `tools/*test.tscn`, `monster_lab`,
`exitcheck`, `faxcheck`, `mapcheck`, `spawncheck`, `loottest`, `minimapcheck`, five playtest
shifts, and the whole default `nettest_run.gd` suite (**31 of 31 pass**, zero SCRIPT ERROR in any
process log). Everything is green except the mortal playtest (section 1o, and not new). Found on
the way: grafttest had been reporting PASS with half its checks never run (note below 1n, fixed),
and a perf regression, not a test failure, fixed in `scripts/warmup.gd` (the warmup shelf's
vein-machine screen redrawing ~800 draw calls a frame, unseen, in every view since 0.12.4). The
`-s` check scripts all print `Identifier not found: Net` compile errors from
`scripts/personnel/mirror_aim.gd`. They are the same on 0.10.55 and harmless: `-s` has no autoloads,
and every one of them still reaches its OK.

Before that: 2026-09-22, `main` at `c933607` (0.10.17), by the `strap-fix` task: the whole
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

**Section 2, mapcheck's morgue tray, went the same way on 2026-09-23 and has been removed
(`fix-morgue-trays`).** `mapcheck` is clean now: 300 seeds x 8 builds with the default round-robin
pockets, and separately `--seeds=8 --builds=8` with `--build_pocket=none` and
`--build_pocket=factory` (the two flag combinations that used to fail on different seeds) -- seeds
38 and 112 both build with **0 out of reach**.

- **It was two pieces sealing a wall off, not the anchor or the navmesh bake.** Dumping
  `gen.rows`/`gen.blocked` for seed 112's failing tray directly showed the mechanism:
  `scripts/level/room_furnish.gd`'s `_morgue()` puts the instrument cart at a fixed offset from the
  autopsy table (`tables[0] + 1.1, D * 0.5 + 0.9`) with no clearance check, and `scrub_sink` goes
  flush against the room's side wall right after it. On a small morgue (this one 5x4 tiles) both
  footprints straddle a tile boundary wide enough that between them they filled **every** tile of
  the interior row against that wall -- the cart in two columns, the sink in the other two of a
  4-wide room. The tray anchor sits on the cart, so it landed in the middle of that sealed strip;
  the nearest open floor was two tiles over and one tile in, `sqrt(5) * 1.5 m` = **3.35 m**,
  matching the reported gap exactly. Nothing was wrong with the navmesh bake
  (`scripts/hospital_builder.gd`'s `bake_nav`, which correctly cuts furniture-blocked tiles from the
  source geometry before baking) or with mapcheck's own reachability search -- the floor genuinely
  wasn't there to stand on.
- **`room_connected()` doesn't catch this.** Every blocking piece already checks that the room's
  open tiles stay reachable from its door (`Frame.put`, `level_state.room_connected`), but that's a
  flood-fill over open tiles: it says nothing about whether a piece that's still standing (the cart)
  has an open tile *next to it*. Two pieces placed independently, each individually legal on its
  own, can wall a third one in without either overlapping it.
- **The fix:** `Frame` gets `put_reachable()`, which backs a blocking piece back out if none of the
  tiles touching its footprint are open floor once it lands (`_has_open_approach()`). `_morgue()`
  now places `scrub_sink` before the cart, so the cart's own tries see the room as it will actually
  end up, and gives the cart a short list of fallback offsets instead of the one fixed spot, trying
  each with `put_reachable()` until one leaves it reachable.
- **What the next person should know.** `put_reachable()` and `_has_open_approach()` are general
  (any blocking piece with something worth reaching can use them) but only the morgue's cart calls
  them so far. If a mapcheck anchor turns up unreachable in another room kind, this is the shape to
  look for first. Separately, and unrelated to this bug: `mapcheck.gd`'s pocket-forced sweeps can
  report `navigation map never synchronised` on one seed under a loaded machine -- a timing flake,
  confirmed here on seed 8 with `--build_pocket=factory` (fails in an 8-seed batch, passes alone).

## 1n was the test's bot, not the game -- fixed 2026-09-25 (`nettest-bandwidth-fix`)

`bandwidth` (`tools/nettest_run.gd -- --only=bandwidth`, Bob's gunshot, seed 4242) sat at GW step 1
("extract", forceps) from about 55 s until its 900 s timeout. **The leading theory was right**, and
instrumenting `_shift_bot` confirmed it:

- **The mechanism.** `scripts/grafting/vats.gd`'s `on_level_built` has stocked one pair of forceps
  (with a scalpel and an eye spoon) on the OR's storage shelves at every level build since 0.10.24
  (2026-09-22), so a graft is never blocked by a search. `game.shelf_count()` counts the shelves
  *and* everyone's hands as "in the OR" (that is its contract: the OR monitor, the dev panel and
  the syringe station all read it that way). `_shift_bot` in `tools/nettest.gd` fetched only what
  `need - shelf_count` left short, and when nothing was short it returned ("someone else is holding
  it"). At step 1 forceps needed 1 and the shelf had 1, so every bot stood still. Logged on the
  host: `forceps need=1 shelf_count=1`, the only counted pair `IN_CONTAINER:storage_0`, nobody's
  hands holding one. No other ailment a shift case can roll is affected: the only other pre-stocked
  tools (scalpel, eye spoon) are used only by the graft procedures, and amputation's tourniquet and
  bone saw are never on the shelves at clock-in.
- **Why only nettest.** `tools/playtest.gd` and `tools/looptest.gd` already had the fallback
  (`from_storage`): when nothing is short, fetch the current step's item from wherever it sits.
  `_shift_bot` now does the same. `full_shift_lag` and `bandwidth_amp` never showed it because
  their seeds roll an amputation.
- **After the fix:** step 1 to step 2 in 9-13 s of game time; the whole scenario **passes in 70-140
  s wall** (11 of 14 runs green; see below for the other three). `full_shift_lag` and
  `bandwidth_amp` still pass.
- **A second test bug it uncovered.** With the stall gone, 2 of the first 5 runs failed with
  `clocked out without seeing the patient stable` on one client. The phase change reaches clients as
  a reliable RPC, but a case's state rides the unreliable, acked snapshots, and the host goes from
  "stable" to clocked out in about a second -- so a client can hear the shift end before its replica
  of the case turns stable. The case stays in `game.cases` after the shift (every client read
  "stable" there in the runs that were logged), so `_sc_full_shift` now waits up to 10 s for it to
  converge instead of requiring it be seen mid-shift, and says so when it had to. Five runs after
  that change: four passed, one never finished because the **runner process itself**
  (`nettest_run.gd`) segfaulted mid-shift ("The caller thread can't call the function
  `propagate_notification()` on this node", then signal 11) while its children were progressing
  normally. That crash is not this bug and was not investigated; re-run before believing it.
- **The `vats.gd` error is fixed too (2026-09-25, item-4 sweep).** `SCRIPT ERROR: Trying to assign
  invalid previously freed instance. at: Vats._arm_markers (res://scripts/grafting/vats.gd:545)`
  was not shutdown-only: it fires on any level teardown (mid-run in `downedtest`, lobby -> next
  shift, and after `devtest`'s result). `_arm_markers` *did* check `is_instance_valid`, but it
  fetched each marker into an `Area3D`-typed variable first, and assigning a freed instance to a
  typed variable is itself the error. It now fetches untyped and casts after the check.

## grafttest said PASS with half of it never run -- fixed 2026-09-25 (item-4 sweep)

Kept because the trap is general. `grafttest` printed `result=PASS failures=0` with **66** checks
while a `SCRIPT ERROR: Invalid call 'String' constructor` killed `_run` at the extraction's first
step. STEER! replaced `eye_ops.gd` for the cut and has no `variant` property, so
`String(sys.mg.get("variant"))` was `String(null)`. It was the same at 0.10.55 (`11159d1`), so it
did not come with the 2026-09-24/25 content. The scoop, the nerve snip, the vat, and every graft and
swap-back check with Dr. Botsworth had not run since the arcade rebuild. They run now, **115 checks,
all passing**: the product was fine and only the test had gone blind.

- **The trap.** A script error aborts a GDScript coroutine, and whatever `await`s it carries on as if
  it had returned. `await _run()` then `_finish()` reads "no failures" and prints PASS. The only
  trace is one `SCRIPT ERROR` line in the log, above a green result. Every harness in `tools/` with
  that shape can do this. **Read a test's SCRIPT ERROR lines before believing its PASS.** On this
  sweep every other scene had none.
- **The fix, in `tools/grafttest.gd`.** `_playing()` reads the game's own `variant` when it has one,
  else the case's current step's. The graft's no-botching check falls back to the case's `no_fail`
  flag (the arcade games take it through their ctx and STEER! keeps no property of it). And
  `_ran_to_end`, set on the last line of the awaited chain, is checked before `_finish()`, so an
  aborted run now fails instead of passing.

## 1o. The mortal playtest goes down (not new)

- `tools/playtest.tscn -- --seed=12345` (no `--god`): **FAIL**, `the bot went down at t=276 after 3
  hits` (all from a Hive). `-- --seed=2`: **FAIL** at t=81, three Sonographer hits.
- **Not a regression.** Both seeds fail the same way on 0.10.55 (`11159d1`), seed 2 frame for frame
  (t=73/77/81) and seed 12345 at t=279 instead of 276, from a Sonographer instead of a Hive. The bot
  has no fighting or fleeing beyond the pinned-by-a-monster sidestep, so an unarmed mortal shift
  is roughly a coin toss against the monster roster. Every `--god` shift passes (seed 2 gunshot,
  12345 amputation, 4242 over two shifts, 7 with `--extra`).
- **What would fix it** is bot behaviour in `tools/playtest.gd` (keeping its distance, hiding,
  sedating), not the game. Until then use `--god` for "can a shift be completed", and read a
  mortal run's `hit by` lines for what hurt it.

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

## 1m was the instrument, not the hospital — checked and removed 2026-09-23 (POCKETS 2 phase 7)

The corridor's **86 avg / 30 1% low** was not a stutter in the hospital. It was two measurement
faults stacked, and both are now fixed in `tools/perfprobe.gd`. Kept as a short note because the
number is quoted in docs/POCKET_SPACES_2.md and somebody will meet it again.

- **The first scenario in a process is measured before the CPU has finished with the level.** Same
  camera, same map, same ~480 draws, one run: `hospital corridor` as the **first** view read
  **60 avg / 22 low with 58 ms of process time a frame**; as the **last** view it read
  **127 / 100 with 5 ms**. Every kind showed it (20-40 ms of proc on its first row). The probe now
  measures one view and throws the row away before it keeps anything. **The plain sweep's `lobby
  clock-in room` was the same artefact**: it is that sweep's first scenario, it is quoted around
  the docs at **31 / 17**, and with the warm-up dropped it reads **82 / 75**.
- **A "1% low" over 240 frames is the third-worst frame of about two seconds**, so one hitch
  decided it. Measured across three full sweeps on an idle machine, the *same* view swung
  **24 to 105**. The default window is now 600 frames, and anything being published wants
  `--frames=1200`, at which the rows do settle down.
- **What is left after both fixes is small and is not the pocket spaces' doing.** At 1200 frames
  the 1% low is still occasionally dragged to 24-46 by a single 30-55 ms frame, and it lands on
  untouched hospital views (`chapel map: hospital corridor` 90/33, `factory: seam, hospital side`
  102/24) as readily as on anything new. That looks like **1j** below seen from the rendering side,
  and it is the thing actually worth chasing.

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
  downedtest, dogtest, fogtest, gurneytest, handstest, inventorytest, looptest, orscreentest, pockettest, settingstest, skilltest,
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
- **perfprobe: the first row is thrown away, and a published number wants `--frames=1200`.** See
  the 1m note above for why both. `tools\perfprobe.ps1 -Extra "--pockets --quality=1 --frames=1200"`
  is the whole five-space sweep plus the bare-hospital baseline, one process per kind, about
  25 minutes on an idle machine. It needs a **real rendering window** (it uses SW_SHOWNOACTIVATE,
  which draws without taking focus); never run it headless or minimized, and close it when done.
- **perfprobe on a cloud Linux box (no GPU)** works through software Vulkan: `apt-get install
  mesa-vulkan-drivers`, then `xvfb-run -a -s "-screen 0 1920x1080x24" godot4 --path . --resolution
  1280x720 res://tools/perfprobe.tscn -- --no-steam --quality=1 --frames=200` (add `--pocket=<kind>`
  per kind; the `.ps1` wrapper is Windows-only). llvmpipe is fill-bound at about 7 fps in every view
  and the warmup takes 3-7 minutes, so **fps means nothing there**. Draw calls, node count and phys
  ms are the comparable columns, and only against another commit run on the same box
  (`git archive <commit> | tar -x -C <dir>`, import it, run the same flags). That is how the
  vein-screen regression was found (2026-09-25): +~810 draws in every view against 0.10.55.
- **A pocket space's own air is blended in by where the CAMERA stands** (`PocketSpaces.air_factor`:
  0 within a few metres of a seam opening, 1 by 14 m in), so a view taken just inside an entrance
  draws the whole room in the *hospital's* fog and ambient. `tools/gameshot.gd --pocket=<kind>`
  prints the factor with every shot. On seed 4242 the Laundromat's three canonical wide views sit
  at **0.00, 0.11 and 0.76** — and perfprobe measures those same three positions, so its Laundromat
  interior rows are partly measuring hospital air.
- Windowed screenshot tools write to `tools/game_shots/` and friends: `menushot`, `faxshot`,
  `tipshot`, `database_shot` (`-- --wall`, `-- --wall2`), `gameshot`, `bootsshot` (rocket boots)
