# Handoff: `graft-surgery` (grafting chunk C)

Slot wt-2. Written 2026-09-18 at the wrap-up. Two commits on top of `main`:

- `b209a6a` Eyeball Grafting: vat stands on every OR table, the graft, the eye and its glow
- `d4badd2` Review setups: drop straight into the graft (`--setup=graft`, `graft_back`)

The brief is [docs/GRAFTING.md](../GRAFTING.md), chunk C, plus Zach's decision that there is **no
dedicated player table**: you strap yourself to any free OR table, and every OR table has a **vat
stand** beside it. The contract note is in docs/CONTRACTS.md, "Grafting part one: the vat stands and
Eyeball Grafting".

## What is done and working

Everything in the chunk C brief, verified headless and in a smoke look:

- **The vat stand.** One beside every patient table (`Vats.stands`, built with the level on every
  machine, on the first of `STAND_OFFSETS` clear of the geometry). E with a carried vat sets it down
  (aim id `vatstand_<i>`, armed only while you carry one); picking it back up is the ordinary
  world-item pickup, so the stand holds a vat only for as long as someone leaves it there.
- **Eyeball Grafting** (`Procedures.AILMENTS.eye_graft`, four steps: scalpel `cut`, eye spoon
  `scoop`, eye spoon `seat`, suture kit `stitch`). It runs through `scripts/downed/player_surgery.gd`
  (which already stood in as a game for the player table's surgery system); `scripts/grafting/
  grafts.gd` owns the rules and the result. **No botching** (the case sets `no_fail`).
- **The refusals**, all on the table's own prompt: no vat on the stand, the vat is empty, the eye is
  spoiled, "X already has one", "X has two normal eyes", operating on yourself, not holding the
  scalpel, and "Nobody is strapped to this table" to someone holding a graft tool at a free table
  with a loaded vat on its stand.
- **The swap.** The `scoop` step is the moment it happens: the eye in the socket is packed into the
  vat on the stand and the vat's eye becomes the one going in. Never an empty socket.
- **Committed after the scoop.** `game.get_up_block` asks `player_surgery.graft_commit_block`, which
  refuses from step 2 on. Before that, holding E gets you up and clears the case.
- **Two new eye-minigame variants** in `eye_ops.gd`: `seat` (the scoop's rules run the other way --
  the new eye sinks into the socket) and `stitch` (the cut's rules over an already-open wound: it
  closes behind the needle and stitch marks appear). New ctx knobs `no_fail`, `eye_kind`,
  `eye_kind_in`, `eye_radius`, passed through by `surgery_system._spawn_mg` from the case's flags.
- **The eye on the body.** `scripts/grafting/graft_eye.gd` builds the `surgeon_graft` look at
  runtime (there is no such GLB in the game): `Human_Eye_L` is hidden and a Hive eyeball with the
  item's own shader is hung on the head's BoneAttachment3D with a ring of stitches. It follows every
  clip and shows in third person, on other players' screens, in the carry camera and in the mirrors.
- **The glow** is a new `instance uniform float lock` on the eye shader (0 a low pinpoint, 1 the
  whole ball lit). `Grafts` eases it to 1 while that player's `hive_view` is on, which is already
  replicated, so every machine agrees.
- **The ability.** Finishing the graft calls `abilities.set_level(peer, "hive_in", 1)` (next free
  slot, new-ability card); swapping back calls `abilities.clear_ability`, which empties the slot,
  zeroes the level and ends any Hive Eyes view. The graft lasts the run through death and
  `grafts.on_reset()` clears it on a game over.
- **Grafting is the only source of an ability** now that brains and the blender are gone
  (`docs/backlog/ABILITIES_REMOVED.md`), so Echo has no source at all until the trachea graft.
- **The first-person tell**: `scripts/grafting/graft_view.gd` (`main.graft_view`), an orange wash
  down the LEFT edge, stronger while Hive Eyes runs. **It is its own CanvasLayer at 52, above the
  look pass's grade (layer 50)** -- under it (where the HUD lives) a faint orange on a teal picture
  disappears completely, which cost an hour to find.
- **The awake patient's camera.** `Player._strapped_look` clamps a strapped surgeon's head to a cone
  about the rest pose (about +/-66 degrees of yaw, 26-86 degrees of pitch): enough to follow the
  surgeon round the table, not enough to spin the camera through your own chest.
- **Body parts are named "X's Y" everywhere** (the coordinator's mid-task rename): "Hive's eyeball",
  "Zach's eyeball", across `Eyes.label`, the loot table, the wall entries, the prompts, grafttest and
  the contracts note. `Eyes.NOUN` and `Grafts.PART_ABILITY` are the seams a trachea slots into later
  (docs/GRAFTING_TRACHEA.md) without a rewrite.
- **Co-op**: nettest scenario `graft` (host grafts a Hive eyeball into a client's surgeon; the other
  client checks the graft, the swapped eye on the body with `Human_Eye_L` hidden, and the glow while
  Hive Eyes runs). **Written but never run** -- see below.
- **DESIGN.md**: the Hive row now says what you harvest, the lab-wall paragraph mentions the vat
  benches and the stands, and there is a new
  "Grafting" section. **docs/CONTRACTS.md**: the chunk C section above.
- **Warmup**: the vat stand, a lying body wearing the grafted eyeball and the `eye_graft` steps'
  minigames all build in `scripts/warmup.gd`.

## Half-done or unverified

- **The nettest `graft` scenario has never been run.** `tools/nettest_run.gd` has its row
  (2 clients, 400 s). It compiles, but nothing has exercised it; expect to have to nudge timings.
- **`orscreentest` was never finished.** It is a full playtest shift and it wedged twice; the first
  time was my own fault (a stale grafttest process in the same checkout -- the CLAUDE.md parallel-run
  gotcha), the second time it just ran long and I killed it at the wrap-up. **I did not touch the OR
  screen**; `eye_graft` is `player_only`, so it never reaches `patient_ailments()` or a patient
  table's panel. Worth one clean run before merging, but I do not expect it to fail.
- The `graft_back` setup applies the graft with `grafts.apply` before any body exists to show it; the
  eye does appear (the setup shot's prompt offers your own eyeball back), but I never looked at that
  body up close.

## Zach's feedback so far, and what is still open

Zach has not seen the graft yet -- he closed the windows before reviewing and asked for review setups
instead. What came through the coordinator and is **done**: the "X's Y" rename, the vat stand on every
OR table (there is no player table), keeping the graft generic for a second part kind, making the
graft the only route to Hive Eyes, and the `--setup=` skeleton with a `graft` and a `graft_back`
setup.

**Still open, to put in front of him:** the whole feel of it -- the four steps' pacing, the stand's
model (it reads a bit like an IV pole), how strong the left-edge tint should be
(`graft_view.gd` `ALPHA`/`WIDTH`), how far the strapped head should be allowed to turn
(`Player.LYING_LOOK_YAW` / `LYING_LOOK_PITCH`), and whether the grafted face reads in the mirror
(your own torch never lights your own body, so the eye reads mostly as its glow).

## What I was about to do next

Open the review window with the new setup and stop. Then: run the nettest `graft` scenario, and one
clean `orscreentest`.

## How to test it

```
tools\review.bat 2 "GRAFT: as Botsworth, give yourself a Hive eye, then check the mirror" --setup=graft --dev
tools\review.bat 2 "GRAFT: swap your own eyeball back in" --setup=graft_back --dev
```

Both drop straight into a solo shift (no menu, no lobby): the phone is quiet, no monsters, no game
over. You are strapped to a free OR table with a vat on its stand, already driving Dr. Botsworth
beside your own head with the scalpel, the eye spoon and the suture kit. Aim at the table and press E
for each of the four steps (hold the right tool: 1/2/2/3). F1 -> "Back to my own body", hold E to get
up, then walk to Personnel and look in the big mirror. Alt shows the ability bar with Hive Eyes 1.

Smoke-look shots: `tools\review.bat 2 "SMOKE" -Scene res://tools/graftsurgeryshot.tscn` writes the
whole loop into `tools/graft_shots/`, and `-Scene res://tools/setupshot.tscn --setup=graft` writes
`tools/game_shots/setup_graft.png`.

## Tests

Run one at a time in this checkout (`--fixed-fps 60`), newest results:

| Test | Result |
|---|---|
| `tools/grafttest.tscn` | **PASS** (0 failures) -- chunk A plus the whole chunk C graft section: the stands, every refusal, all four steps with Dr. Botsworth operating, Hive Eyes 1 in and out, and not getting up after the scoop |
| `tools/downedtest.tscn` | **PASS** (0 failures) |
| `tools/straptest.tscn` | **PASS** (0 failures) |
| `tools/orscreentest.tscn` | **SKIPPED** (see above; unrelated to this branch as far as I can tell) |
| nettest `graft` | **NOT RUN** |

Nothing in docs/FAILING_TESTS.md was touched or fixed.

## Known risks

- **The stand's placement is geometry-dependent.** It takes the first of five offsets around the
  table that a box query finds clear, so on a cramped table it can land on the far side. It is
  deterministic (every machine runs the same query on identical geometry), but it is not *designed*
  placement.
- **`Player.stand_in`** is new and is what stops a strapped surgeon's own body drawing on top of the
  lying stand-in (without it you get two overlapping faces, which the smoke look caught). It is set
  from the case on every machine by `player_surgery._refresh_stand_in` and read by both
  `refresh_downed_visuals` and `_refresh_self_body`. Anything else that shows a local body has to
  respect it.
- **The graft rides `game.player_table`**, which on the hub follows `strap_table`. A level with a
  player table of its own has no table index, so `Grafts.vat_for` falls back to the stand nearest the
  table top (`Vats.nearest_stand`, 4 m). Only the hub is exercised.
- **`grafts.apply` is host-only** and the state rides the snapshot as `"gf"`; clients never write it.
- **Renderer errors in the `--setup=` boot path**: that path logs about 8
  `BUG, indexing did not unpair geometries from light` errors. A normal windowed boot that builds the
  same hospital and renders it (`tools/gameshot.tscn`, same seed) logs **zero**, so it is the setup
  boot (`prebuild_level` + `begin_shift` + settling frames), not normal play. Harmless as far as the
  picture goes, but it is the shared skeleton's, not this branch's.

---

## Follow-up: `graft-fixes` (slot wt-1, 2026-09-18)

Zach played the graft and asked for four things. All four are on branch `graft-fixes`.

1. **Step 3 is forceps now.** The `seat` variant (the scoop run backwards) is gone; step 3 is
   "Seat the new eye with forceps", item `forceps`, variant `grab`, and its own game
   `scripts/grafting/eye_seat.gd` (eye_ops.gd builds it as a child and hands every Minigame call to
   it, the way `forceps.gd` hands "brain" to `brain_forceps.gd`). The new eye waits on a small tray
   beside the socket, is picked up with the jaws, swings on its nerve while it is carried and drops
   back on the tray if you whip the hand about (no botch, just retry), then sinks in under slow
   steady pressure. Result is still `{"eye_seated": true}`. Forceps are stocked on the OR's storage
   shelves next to the scalpel and the eye spoon, and the `graft` / `graft_back` review setups give
   Botsworth all four tools (1 scalpel, 2 eye spoon, 3 forceps, 4 suture kit).
2. **The body on the table is dead still** during a graft (`player_body.still`): no breath, no
   Lying clip, no stir jolt. What moved before was the stand-in's own `_process` -- the breathing
   torso scale, the Lying clip's idle breath on the skeleton and the jolt offset on `rig` -- which
   moved the head under a work plane that had been measured off frame 0 of that clip.
3. **The brightness** was the work lamp, not an extra light: the eye steps put the operating camera
   0.3 m off the site and a surgeon's pale face under the full lamp measured about 3x the mean
   luminance of the same step on a Hive's dark head. New `Minigame.lamp_scale()`; `eye_ops` returns
   0.3 for a player. Before/after in `tools/graft_shots/`.
4. **The Hive eye not showing** was two bugs. `Grafts` remembered what it had attached by part kind
   alone, so once the body_visual was rebuilt (getting up off the table, the mirror's own body) the
   graft went with it and was never put back; it now keys on the human model instance and re-attaches
   whenever the node is missing. And `GraftEye`'s socket offset was on the opposite side from
   `Human_Eye_L`, so the surgery hid and operated on one eye while the graft appeared in the other:
   both now come from `GraftEye.local_offset`. Plus a size bump (`Grafts.BODY_EYE_RADIUS`) and a
   resting ember (`LOCK_IDLE`), since nothing lights your own face in the mirror.

Also: `tools/graftsurgeryshot.gd` takes a Hive Eyeball Extraction reference shot first
(`40_hive_cut_operating`) and prints every light near the work site; `tools/minigame_lab.gd` can play
the graft's eye steps (`--game=eye --patient=player --variant=grab --look=or`). Both screenshot
helpers now call `RenderingServer.force_draw()` before reading the viewport -- a minimized review
window redraws so rarely that every shot used to be of a frame from seconds earlier (which is why
the shots in the section above show the wrong step).

### Second round (Zach's notes on the screenshots)

1. **The red disc** was the grafted eye facing into the skull. `GraftEye.local_offset` gave it the
   skeleton's axes, whose front is +Z (glTF), but the eyeball's pupil is its -Z: everyone saw the
   back of the ball, lit all over by `LOCK_IDLE`. It is turned half round now. The earlier "size
   bump" was making up for this and is gone: the graft is `Human_Eye_L`'s own size and centre
   (`GraftEye.RADIUS` 0.0147, `SIDE` 0.035), so it sits in the socket instead of through the lids.
2. **The head moving between steps** was the camera, not the body: the forceps step asked for its own
   pulled-back view. It uses `eye_ops.base_camera_pose()` like the others now.
   `graftsurgeryshot` logs the eyes' site and where it lands on screen at every step: identical
   (800, 566) from the cut to the stitch.
3. **The eye sunk into the face** during the seat step: `eye_seat` put the seated eye 0.45 of a
   radius below the work plane, whose origin on a surgeon is already the eye's centre. Home is 0 now.
4. **The bright yellow face after getting up** is not the graft: it is the Personnel mirror's bulb
   glow (entrance.gd, a warm OmniLight at head height in front of the glass), 17 cm from your face
   when you stand at the mirror. With it off, the face goes dark (`67f_face_no_room_lights_near`).

### Third round (the table, and the tray on it)

- **The OR table is new** (`piece_defs.or_table`, `piece_factory`): a stainless prep table, 2.4 x 1.1
  on the floor with a 2.4 x 1.1 top at 0.945 (`Game.OR_TABLE_TOP`, unchanged), four square legs, a
  brace near the floor, leveling feet, a drawer under the head end and hooks under the near lip. It
  replaces the 2.2 x 0.7 pedestal one. The size came from what has to fit: a 1.8 m patient down the
  middle with a clear strip of steel either side for the tray, and the OR's own row -- the tables sit
  3.6 to 3.75 m apart on tile row 7 (TILE 1.5), so the footprint still claims exactly the tiles it
  did (`Defs.blocked_tiles`), the anesthesia carts and the vat stands still clear it, and there is
  1.7 m of walkway to the wall behind it.
- **The tray** in the seat step now stands on that top beside the head instead of floating on the
  work plane over the face (see the seat step in CONTRACTS).

### Fourth round (the vat is the centre of it)

- **No tray.** The `grab` step takes the new eye out of the **specimen vat standing on the table**
  (`ctx.vat`, hidden while the step draws its own open copy of it where the real one stands). A
  dropped eye falls back into the vat.
- **Raise and lower are keys.** `Minigame.BUTTON_DOWN` (S) joins `BUTTON_UP` (W) -- hold S to lower
  the forceps into the vat or the socket, W to lift the eye clear. Nothing dives because the mouse
  went past a point any more.
- **Every step says what the buttons do.** `hud_state()["keys"]` -> `[[key, what], ...]`, drawn by
  `surgery_hud` as a third line in the strip; every minigame fills it in per stage.
- **The extraction has a fourth step**, "Put the eye in the vat" (forceps, variant `place`): the
  same game run the other way, and `dissection._finish_eye` puts the eye in that vat instead of the
  operator's hand.
- **The vat stand is gone.** `Vats.places` / `vat_on_table` / `place_of_table` /
  `set_down_on_table`, one spot per table at `TABLE_VAT_OFFSET` on the table top beside the head.
- The swap moved from the scoop to the seat, so you never reach into a vat that already holds the
  eye that just came out.
- Review setup `--setup=eyes` stages both procedures at once.

### Fifth round (the extraction's last step was too hard)

Zach: "I cant figure out how to get the eye from the hive to the jar, its too complicated." The
`place` variant asked for five things in a row (lower, grab, lift clear, carry under a speed limit,
lower in) for what should be "pick it up, drop it in the jar". It is now: hold left click near the
loose eye, drag, let go over the vat. No W, no S (the forceps raise and lower themselves), no speed
limit, no slack drop -- the step cannot be lost -- and letting go anywhere else just puts the eye
back in the socket. The vat's ring is up from the first frame and 2.6x bigger, and the hint says
what to do in one line. `grab` (the graft) still has all its careful work; only `place` changed.
The snip's camera is raised (0.22 / 0.20 / 50) so the extraction's steps sit closer together; it
stays side-on because the nerve shows under the lifted eye and a view from straight above would
have the eye covering it.

### Sixth round (one way to handle an eyeball)

Zach: "make the new way of handling the eyeball true of the grafting surgery too". The graft's seat
step is the same grab-and-drag as the extraction's now, and `eye_seat.gd` has one set of rules with
`mode` only choosing where the eye comes from and where it goes. Gone from the step, and from the
file: the depth input and `Minigame.BUTTON_DOWN` (S; W stays for the snip's pull), `DEEP_ENOUGH` /
`LIFT_CLEAR` and the lift-clear drop, `CARRY_MAX_SPEED` and the slack drop, `SEAT_MAX_SPEED` and
the steady-pressure push, the `_speed` tracking and the jolt reaction (nothing is left to shake
loose). What is left: hold left click near the eye, drag, let go over the ring.
