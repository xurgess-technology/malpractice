# Handoff: where everything stands (2026-09-25, version 0.12.5)

Written by the orchestrator so a cloud agent can carry on. NOW.md is gitignored and doesn't travel;
this is its stand-in. The older handoffs in this folder (graft-surgery, icon-bar, ...) are from
2026-09-18 and long since merged; they're kept for history only.

**Update (2026-09-25, later the same day):** all four items below are done. `skill-tree` merged as
**0.12.4** and `surgical-robot` as **0.12.5**, each independently verified (their own tests plus
`monster_lab`/`dogtest`) after merging in the other's changes and the Service Dog/gurney/hands work
already on `main`. The nettest `bandwidth` stall (item 3, `docs/FAILING_TESTS.md` section 1n) is
fixed and merged too (no changelog entry -- it's test tooling): the `shelf_count()` theory was
right, `_shift_bot` now fetches a step's tool from wherever it is instead of assuming the shelf
count means someone's already holding it; `bandwidth` runs in ~55 s now, was stalling to the 900 s
timeout. **Item 4, the perf re-check and full sweep, is also done, merged as 0.12.6**: it found and
fixed a real regression (the skill tree's vein-scanner SubViewport was rendering unseen every
frame, ~810 extra draw calls everywhere), plus two test-harness bugs (`grafttest` was passing with
half its checks never run; a `vats.gd` shutdown error). The only red result is the mortal playtest
(`--seed=12345` and `--seed=2`), confirmed pre-existing on the 0.10.55 baseline, not a regression --
see `docs/FAILING_TESTS.md` section 1o. **The whole 2026-09-24 list is done. Nothing has been
played by Zach yet** -- that's the actual next step, not more headless work.

**Also on `main` from earlier today:** the Service Dog (a new monster) and longer throws, merged in
at the prior handoff as 0.12.2 and 0.12.3.

## What Zach asked for (2026-09-24)

Eleven items, "pick an order for this and do it all to completion". Merge mode is on (Zach,
2026-09-22): branches go straight into `main` once their own tests pass, with no review sign-off.
**None of it has been played by Zach yet.**

| # | Item | State |
|---|---|---|
| 1 | Pocket-space textures flickering | **Merged, 0.11.2**: pocket props were drawn inside out |
| 2 | Make sure the perf audit is done | **Merged, 0.12.6**: the re-check found and fixed a real regression |
| 3 | Onlooker: shadowy fog; rushing him = poof into fading smoke | **Merged, 0.11.1** |
| 4 | Tune the thrown-item tumble | **Merged, 0.11.3** |
| 5 | Player-pushed gurney in the OR | **Merged, 0.12.1** |
| 6 | Surgical robot: $500 core from the pharmacy, P to remote in | **Merged, 0.12.5** |
| 7 | Puppet replaces Hive Eyes | **Merged, 0.11.4** |
| 8 | Skill tree v1 at the vein scanner | **Merged, 0.12.4** |
| 9 | Showers toggle on E | **Merged, 0.11.3** |
| 10 | First-person hands that grip things | **Merged, 0.12.0** |
| 11 | Third-person flashlight pose, synced beam and scan | **Merged, 0.11.0** |

What Zach decided when asked:
- **Skill tree trees** are placeholders: Surgery, Anatomy (grafting), Pharmacology, Survival (monsters/stealth) and Logistics (money/items). They live in one table and are easy to rename.
- **"The scrub room panel"** means the existing vein-machine palm scanner in the personnel room.
- **The robot** stays at the OR table and operates, so a solo player can get grafted.

## What's left

Items 1-3 (skill-tree, surgical-robot, the nettest `bandwidth` stall) are done -- see the update
note at the top. Their own details are kept below for reference (what each merge had to reconcile,
known limits), then item 4, which is still open.

### Done: skill-tree (merged 0.12.4)
- **Docs:** `docs/SKILL_TREE.md`.
- **Rules it picked:** one skill point per shift you clock out of; saved per player in
  `user://skills.save`, surviving a game over; one player at the machine at a time;
  `Skills.has_skill(peer, id)` is the hook for real effects, nothing calls it yet.
- **Merge:** `scripts/review_setups.gd`, `tools/nettest.gd`/`nettest_run.gd` and
  `docs/FAILING_TESTS.md` all took both sides (skill-tree's entries alongside the gurney/dog/etc.
  ones already there). No stand-in `Game` in `tools/` needed a new field -- the skill code never
  reaches through `game.skills`; `Skills` is a static class and `Net` holds the table.
- **Verified:** `skilltest` (43), `devtest`, `hudtest`, `settingstest`, nettest `veins`, plus
  `monster_lab` (179) and `mapcheck` post-merge.
- **Known nits, not fixed:** the review setup's on-screen hint overlaps the screen's header, and
  there's no animation of the hand going onto the plate (only the camera looks down at it).

### Done: surgical-robot (merged 0.12.5)
- **Built:** buy the core ($500, pharmacy), E to plug it in near the OR's first patient table; P
  (rebindable) to remote in from anywhere, E through its camera runs the normal surgery flow;
  strap yourself to its table and P for a solo self-graft.
- **Merge fixed:** every leftover Hive Eyes reference in the branch's own code (`robot.gd`'s
  `hive_view` -> `puppeting` in two places, the `_robot_graft` setup's ability card id
  `hive_in` -> `puppet`, `robottest`'s self-graft check, `CONTRACTS.md` wording); confirmed the
  robot fixture and the gurney's parking spot don't overlap (6.8 m apart) and a pushed gurney can't
  roll through the robot's collision; P is now refused with a reason if you're holding the gurney's
  handle (`robottest` covers pushing past the robot and back without losing the handle); a missing
  first-person grip for `robot_core` (baked, held like a bottle) that `handstest` caught.
- **Docs written:** the $500 line in `CONTRACTS.md`'s pharmacy section, `DESIGN.md` bullets under
  Items and Grafting, removed from `docs/backlog/SWEEP4B.md`, a note in `docs/GRAFTING.md`.
- **Verified:** `robottest`, `dogtest`, `monster_lab` (179), `gurneytest`, `grafttest`, `straptest`,
  `downedtest`, `inventorytest`, `faxcheck`, `controlstest`, `databasetest`, `devtest`,
  `orscreentest`, `hudtest`, `syringetest`, `settingstest`, `handstest`; nettest `robot`, `graft`,
  `surgery` all passed, `economy` failed once on a slow late-joining client (60 s timeout waiting
  for a 12 s level build) and passed clean alone -- a load/timing flake, not a robot regression.
- **Known limits, not fixed:** only serves the first patient table; no dev-panel button for it
  (the `robot`/`robot_graft`/`robot_buy` review setups stand in); starting Puppet while remoted in
  drops you out of the robot (Hive Eyes did the same, left as-is). **Nobody has played it yet** --
  Zach's `--setup=robot` / `--setup=robot_graft` review is still owed.

### Done: the nettest `bandwidth` stall (was docs/FAILING_TESTS.md, section 1n)
The `shelf_count()` theory was confirmed: `vats.gd` pre-stocks one pair of forceps on the OR
storage shelves at every level build, and `_shift_bot` in `tools/nettest.gd` only fetched an item
if `need - shelf_count` showed it missing -- with the shelf already at 1, no bot ever fetched it,
so every bot stood still forever at step 1. Fixed to fetch the current step's item wherever it is,
matching `playtest.gd`/`looptest.gd`'s existing fallback. A second bug the fix exposed (a client
reading "clocked out" before its unreliable-snapshot copy of the case caught up to "stable") got a
10 s grace wait instead of failing immediately. `bandwidth` now finishes in ~55 s (was stalling to
the 900 s timeout); `settingstest` still green. `docs/FAILING_TESTS.md` section 1n is replaced with
a short resolved note. One unrelated, unexplained runner crash (`nettest_run.gd` itself, signal 11,
"caller thread can't call `propagate_notification()`") turned up once in 14 runs, with the child
processes progressing normally -- not investigated, not blocking.

### Done: perf re-check and the full sweep (item 2 of Zach's list, merged 0.12.6)
Ran `perfprobe` on the hospital and (partially, see below) the pocket spaces, every headless test
scene, the playtest shifts and the full `nettest_run.gd` suite, all on this same cloud box, with
software Vulkan (`mesa-vulkan-drivers` under Xvfb) so the real Forward+ renderer's draw-call and
node-count numbers are comparable (fps itself is meaningless here, pinned around 7). Compared
against a `git archive` export of `11159d1` (0.10.55) as "before", same flags both sides
(`--quality=1 --frames=200`, seed 4242).

- **Found and fixed: ~810 extra draw calls in every hospital view.** The skill tree's
  `VeinMachine.warm()` left its warmup SubViewport on `UPDATE_ALWAYS` -- a SubViewport renders
  regardless of its parent's visibility, so the hidden warmup shelf's vein screen (~795 draws) was
  being redrawn, unseen, every frame of every session. Fixed in `scripts/warmup.gd`: every
  SubViewport under `WarmupKeepAlive` goes to `UPDATE_DISABLED` once the shelf sleeps.
- **After the fix vs. 0.10.55:** draws down 4-36% in 6 of 9 hospital views; up modestly (9-24%) in
  the three OR views, almost certainly the robot fixture's ~55 shadow-casting mesh pieces plus the
  gurney -- not a regression, just new geometry that's always in the OR now. Physics-script time is
  within this box's noise everywhere. Nodes are +392 everywhere (new systems' warmup instances).
  Pocket-space perf was only checked for `none` and `factory` (same pattern, fix confirmed) before
  being cut short in favor of the correctness sweep; `natatorium`, `chapel` and `laundromat` weren't
  measured, and neither was a close-up A/B of the gurney/robot/Onlooker specifically -- all four
  need a local Windows run if they're wanted.
- **Two test-harness bugs found and fixed, unrelated to perf:** `grafttest` was a false PASS
  (pre-existing on 0.10.55) -- a `String(null)` SCRIPT ERROR killed its `_run` coroutine at the
  first step, and `await` on the dead coroutine let it print PASS with 66 of 115 checks never run;
  fixed to fail loudly on an aborted run instead. A `vats.gd` shutdown error (assigning a freed
  marker to a typed `Area3D` var before the `is_instance_valid` check) fired on any level teardown,
  not just shutdown as `1n` had guessed; fixed, `downedtest`/`devtest` are now at 0 SCRIPT ERRORs.
- **Everything else: green.** All ~27 headless test scenes, `mapcheck`/`spawncheck`/`loottest`/
  `minimapcheck`, four of five playtest shifts (`--god`), and all 31 default `nettest` scenarios
  plus the opt-in `bandwidth`/`bandwidth_amp`, zero SCRIPT ERRORs anywhere.
- **The one red result:** the mortal playtest (no `--god`) goes down on both `--seed=12345` and
  `--seed=2` -- confirmed identical on the 0.10.55 baseline, so this is pre-existing bot behavior
  in `tools/playtest.gd`, not a regression from this batch. Documented as `docs/FAILING_TESTS.md`
  section 1o. Use `--god` to check that a shift can be completed.

## Things Zach should look at when he plays (feel calls, not bugs)
- **Onlooker:**
  - about 1.5 s into the poof, the cloud is a dense round black ball
  - he may look pasted-on in heavy fog
- **Flashlight:** teammates hold the torch in their left hand, but first person holds it in the right (mirror images).
- **Hands:**
  - the quarter bucket is carried on the palm
  - the collection plate is seen edge-on
  - the torch looks large in a real shift
  - third-person bodies still use the old grip table
- **Puppet:**
  - numbers to tune: 4/5/6 s by level, 2.0 m/s, the 1.0 s fly-in
  - its sounds are still named `ability_hive_*`
  - untested: the camera when the Hive's face is against a wall, and puppeting through a pocket seam
- **Gurney:**
  - needs completely empty hands to push (maybe too strict)
  - the 2.4 rad/s turn cap hasn't been played
  - a joining client letting go can snap it back 10–30 cm
- **Pocket props:** they now show their front faces, so everything in the pocket spaces is shaded a little differently.
- **Showers:**
  - syncing copies how the furnace hatch syncs, but there's no nettest for the showers themselves
  - the water's look and sound are a first pass

## How to work (cloud)
- Read CLAUDE.md, RULES.md and docs/FAILING_TESTS.md.
- `tools/setup_cloud.sh` installs `godot4`. Use it in place of the Windows console binary, headless with `--fixed-fps 60`, one test at a time per checkout.
- The work slots, `tools\*.bat` and review windows are Windows-only; skip them.
- Changelog:
  - entries are written when work lands on `main`, and `config/version` in `project.godot` must match
  - 2026-09-25 is 0.12.x, and the next entry is **0.12.6**
  - a later day starts a new minor (0.13.0)
- **Never `git stash` in a worktree.** The stash list is shared by every worktree of the repo; on 2026-09-25 two slots popped each other's stashes.
- Push `main` only when Zach says to. He asked for this handoff to be pushed.
