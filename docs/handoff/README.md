# Handoff: where everything stands (2026-09-25, version 0.12.5)

Written by the orchestrator so a cloud agent can carry on. NOW.md is gitignored and doesn't travel;
this is its stand-in. The older handoffs in this folder (graft-surgery, icon-bar, ...) are from
2026-09-18 and long since merged; they're kept for history only.

**Update (2026-09-25, later the same day):** items 1-3 below are done. `skill-tree` merged as
**0.12.4** and `surgical-robot` as **0.12.5**, each independently verified (their own tests plus
`monster_lab`/`dogtest`) after merging in the other's changes and the Service Dog/gurney/hands work
already on `main`. The nettest `bandwidth` stall (item 3, `docs/FAILING_TESTS.md` section 1n) is
fixed and merged too (no changelog entry -- it's test tooling): the `shelf_count()` theory was
right, `_shift_bot` now fetches a step's tool from wherever it is instead of assuming the shelf
count means someone's already holding it; `bandwidth` runs in ~55 s now, was stalling to the 900 s
timeout. **What's left is item 4: the perf re-check and full sweep**, below -- it hasn't run on the
combined `main` yet.

**Also on `main` from earlier today:** the Service Dog (a new monster) and longer throws, merged in
at the prior handoff as 0.12.2 and 0.12.3.

## What Zach asked for (2026-09-24)

Eleven items, "pick an order for this and do it all to completion". Merge mode is on (Zach,
2026-09-22): branches go straight into `main` once their own tests pass, with no review sign-off.
**None of it has been played by Zach yet.**

| # | Item | State |
|---|---|---|
| 1 | Pocket-space textures flickering | **Merged, 0.11.2**: pocket props were drawn inside out |
| 2 | Make sure the perf audit is done | **Open**: the audit itself landed in 0.10.54; the re-check after all the new content is still owed (below) |
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

### 4. Perf re-check and the full sweep (item 2 of Zach's list)
Run these after 1 and 2 land:
- `perfprobe` on the hospital
- `perfprobe --pockets`
- every headless test scene
- the playtest shifts
- `tools/nettest_run.gd`

Fix what regressed, or write it into docs/FAILING_TESTS.md. Items 3, 5 and 6 all added content, so look closest at the Onlooker's smoke, the gurney and the robot. **A cloud Linux box's frame times don't compare with Zach's Windows machine.** Compare before and after on the same box (check out `11159d1`, 0.10.55, for "before"), or leave the absolute numbers for a local run.

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
