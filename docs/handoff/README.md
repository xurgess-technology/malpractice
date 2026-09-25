# Handoff: where everything stands (2026-09-25, version 0.12.3)

Written by the orchestrator so a cloud agent can carry on. NOW.md is gitignored and doesn't travel;
this is its stand-in. The older handoffs in this folder (graft-surgery, icon-bar, ...) are from
2026-09-18 and long since merged; they're kept for history only.

**Also on `main`:** another session's Service Dog (a new monster) and longer throws were pushed to
origin while this list was being worked on. They were merged in at handoff and renumbered 0.12.2
and 0.12.3 (their changelog had called them 0.11.0 and 0.11.1). After that merge, `dogtest`,
`tumbletest`, `gurneytest` and `monster_lab` (179/179, after giving its stand-in game a `gurney`
field) all pass. The full sweep hasn't run on the combined `main`.

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
| 6 | Surgical robot: $500 core from the pharmacy, P to remote in | **Branch `surgical-robot`, finished but not merged** (below) |
| 7 | Puppet replaces Hive Eyes | **Merged, 0.11.4** |
| 8 | Skill tree v1 at the vein scanner | **Branch `skill-tree`, finished but not merged** (below) |
| 9 | Showers toggle on E | **Merged, 0.11.3** |
| 10 | First-person hands that grip things | **Merged, 0.12.0** |
| 11 | Third-person flashlight pose, synced beam and scan | **Merged, 0.11.0** |

What Zach decided when asked:
- **Skill tree trees** are placeholders: Surgery, Anatomy (grafting), Pharmacology, Survival (monsters/stealth) and Logistics (money/items). They live in one table and are easy to rename.
- **"The scrub room panel"** means the existing vein-machine palm scanner in the personnel room.
- **The robot** stays at the OR table and operates, so a solo player can get grafted.

## What's left, in order

### 1. Merge `skill-tree` (`a8d4001`, one WIP commit, based on 0.11.4)
The feature is finished; "WIP" only means it was committed in a hurry at handoff.
- **Tests:** `skilltest` (43 checks), a restart-persistence run and a new nettest `veins` all passed on the branch.
- **Docs:** read `docs/SKILL_TREE.md` first.
- **Rules it picked:**
  - one skill point per shift you clock out of
  - saved per player in `user://skills.save`, so skills survive a game over
  - one player at the machine at a time
  - `Skills.has_skill(peer, id)` is the hook for real effects; nothing calls it yet
- **To finish:**
  - Merge `main` into the branch. Expect conflicts in `scripts/review_setups.gd` (keep both sides), `docs/CONTRACTS.md` and possibly `scripts/game.gd` / `DESIGN.md`.
  - Re-run `skilltest`, `devtest`, `hudtest`, `settingstest` and nettest `veins`, then merge.
  - Any stand-in game in `tools/` (monster_lab's `LabGame`, style_lab's) that the new code reaches through `game.skills` needs a null field, as `monster_lab` needed `gurney`.
  - Known nits: the review setup's own on-screen hint overlaps the screen's header, and there's no animation of the hand going onto the plate (only the camera looks down at it).

### 2. Finish and merge `surgical-robot` (`a1e9403`, one WIP commit, based on 0.11.3)
The commit message is the full handoff; read it.
- **Built:**
  - buy the core ($500, pharmacy) and E to plug it in; it stays on for the run and a game over switches it off
  - P, rebindable, to remote in from anywhere; E through the robot's camera runs the normal surgery flow
  - solo self-graft: strap yourself to the robot's table, then P
- **Tests passed on the branch:** `robottest`, nettest `robot` and the related suites.
- **To finish:**
  - **It predates Puppet.** Merge `main` in and fix everything that still says Hive Eyes: `robottest`'s self-graft ends by checking for Hive Eyes, which is now Puppet (`hive_view` became `puppeting`). Grep for `hive`.
  - **It predates the gurney.** Both live in the OR. Check that the robot fixture (head end of the first patient table) and the gurney's parking spot (`entrance.gd`) don't overlap, and that pushing the gurney past the robot is fine.
  - **Docs still owed:** the $500 line in the pharmacy section of CONTRACTS.md; DESIGN.md bullets under Items and Grafting; remove the robot from `docs/backlog/SWEEP4B.md`; a note in `docs/GRAFTING.md`.
  - **It predates the Service Dog**, which takes up a fifth monster kind. Run `dogtest` and `monster_lab` after merging `main` in.
  - **Tests still owed:** nettest `graft`, `economy` and `surgery`.
  - Then merge.
  - Known limits: it only serves the first patient table, and there's no dev-panel button for it.

### 3. The nettest `bandwidth` stall (docs/FAILING_TESTS.md, section 1n)
This is an opt-in measurement run. The bot gets stuck at step 1 of Bob's gunshot for about 850 s. The leading theory, not yet confirmed: `_shift_bot` trusts `game.shelf_count()`, which counts forceps sitting in OR storage as already held, so no bot ever fetches them. The next step is in 1n. The `settingstest` failure found alongside it is fixed (a test bug).

### 4. Item 2: perf re-check and the full sweep
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
  - 2026-09-25 is 0.12.x, and the next entry is **0.12.4**
  - a later day starts a new minor (0.13.0)
- **Never `git stash` in a worktree.** The stash list is shared by every worktree of the repo; on 2026-09-25 two slots popped each other's stashes.
- Push `main` only when Zach says to. He asked for this handoff to be pushed.
