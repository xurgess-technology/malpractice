# The Service Dog: Blender sources

**Built 2026-09-24, art side of the Service Dog feature; revised eight times the same day after
Zach's reviews (see "Revision 1" through "Revision 8" below), then given a ninth pass the same day
for a design change (see "Revision 9" below): the attack is now a dementor-style soul-drain, not a
chase/bite; a tenth pass fixing three problems Zach found in that pass (see "Revision 10" below); an
eleventh pass fixing two more (see "Revision 11" below); a twelfth pass fixing the real bug
underneath all of that, found by a real cross-branch integration test (see "Revision 12" below);
a thirteenth, styling pass once Zach approved the base model (baked-texture grime/blood detail,
a real two-layer crystal-ball orb -- see "Revision 13" below); a fourteenth pass fixing
Revision 13's grime/blood texture, which turned out to be genuinely invisible on screen (see
"Revision 14" below); a fifteenth pass pushing the blood coverage much further, per Zach's
direct ask for the dog to read as genuinely covered, not lightly stained (see "Revision 15"
below); and a sixteenth pass pulling that back to discrete splatters once Revision 15 turned out
to be "WAYYYYY too much" (see "Revision 16" below).**
The model is `assets/models/monsters/service_dog/service_dog.glb` (asset key
`monster/service_dog`; skinned mesh, 2 objects, 6 materials, 2 baked textures, 11 clips), registered
in `scripts/assets.gd`. `scripts/monsters/dog_rig.gd` is its `SkeletonModifier3D` (head-tracking,
idle "wrongness", continuous tail wag, the throat orb's glow hook), following the Night Nurse / Hive
convention (`scripts/monsters/night_nurse_rig.gd`, `hive_rig.gd`). `tools/dog_lab.gd` /
`tools/dog_lab.tscn` is its smoke-test viewer (see "Validate" below). This folder has a `.gdignore`,
so Godot never imports it.

Like every other creature here, the Service Dog is modelled entirely from Python in Blender 5.2,
headless. No AI generation, downloaded models or hand sculpting: every vertex, weight and keyframe
comes from `blender_src/`. It is the **first quadruped** in the project — there was no locomotion
rig to fork for legs, so `blender_src/dog_rig.py` builds one from scratch, borrowing the Night
Nurse's clip-authoring conventions (`Poser`, per-bone `(axis, angle)` pose dicts, `keyframe_action`)
rather than the Seal's (the Seal has a from-scratch rig too, but no legs or locomotion at all).

A **separate branch, `service-dog-brain`,** builds this creature's AI/state machine against a
placeholder body; this branch is art/model/rig/clips only. `scripts/monsters/monster_model.gd`
dispatches `kind == "service_dog"` to `DogRig.build()` (mirroring the Nurse/Hive/Sonographer cases)
so the real GLB slots in automatically once both branches land — nothing else needs rewiring.

## Design brief (from Zach's reference images)

A borzoi (Russian wolfhound) pushed taller and gaunter than a real one, wearing a service-dog vest,
and unsettling rather than merely tall: real sighthound anatomy and gait as the base (long narrow
skull, deep narrow chest, extremely long thin legs), pushed further wrong with a gaunt frame, a
sunken/blank-socketed skull-pale head, and an unnervingly still stance. Four reference images set
the tone; the read each contributed:

- A painted piece: emaciated, unnaturally tall, a skull-like head with dark sunken sockets, a wet
  snout, a thin wispy tail, looming in fog. The strongest single reference for "wrong."
- A photo of a real borzoi mid-bark: the anatomy source (skull shape, leg proportions, chest depth),
  not the tone source.
- A sketch: gaunt ribs through the skin, blank sclera-less eyes, bared teeth, stiff too-long legs
  ending in almost hoof-like feet.
- A sketch: a pale skull-like head with no visible eyes at all, a dark wiry body. Its tentacle-tail
  was deliberately not used (too far past the brief); the blank-eyed head and dark wiry body were.

## Revision 1 (2026-09-24, same day, after Zach's first look at the screenshots)

Three fixes, all in `blender_src/`, no wiring changes:

1. **The vest was unreadable.** The girth strap was barely proud of the coat and close enough in
   tone to it that it read as a smudge, not a garment. Fixed by making it a genuinely different
   garment, not a tweak: a wide strap standing clearly proud of the coat in a saturated safety-vest
   orange (`Dog_Vest_Clean`, `dog_materials.py`), a much bigger back/saddle panel, a shoulder strap
   tying the two together so the whole thing reads as one wrapped garment, and two pieces of
   first-aid iconography (`dog_geometry.build_vest`'s `add_patch` calls) — a red cross on top of the
   girth strap and a pale ID badge on its front. Both patches are forced onto their own material
   (`Dog_Vest_Cross`, `Dog_Vest_Badge`) via the new `Part.face_mat` override, bypassing the usual
   per-face mask average entirely. The wear mask still exists (`Dog_Vest_Worn`) but only ever
   touches a minority of the surface now, so it can no longer compete with the base garment's
   legibility. See `godot_shots/dog_vest_closeup.png` and `dog_vest_cross_patch.png`.
2. **The StandUp/Run end pose read as balanced on one leg.** The cause: `thigh` is a direct child of
   `pelvis`, and every pose delta in `dog_rig.Poser` is a world-space rotation about a shared global
   axis, so `thigh`'s own delta was simply *added* to `pelvis`'s ~90 degree pitch instead of
   cancelling it — the hind legs got carried along for the ride and ended up pointing sideways
   instead of staying planted. Fixed by making `biped_stand_pose`'s hind-leg deltas cancel the
   pelvis's pitch first (`-BIPED_PELVIS_PITCH`) before adding the crouch/weight-bearing bend on top
   (documented in the pose function's docstring, with the reasoning spelled out since it is easy to
   get backwards again). The front legs got the same treatment relative to the chest's cumulative
   pitch, so they curl up and tuck rather than over-rotating past vertical. Re-rendered the same
   4-frame sequence: `godot_shots/dog_standup_00/_35/_65/_100.png`.
3. **The Bite clip didn't read as an attack.** Two bugs, one design fix: the jaw's hinge offset was
   accidentally authored along the wrong axis (a leftover from the Y/Z frame fix below — it offset
   the jaw *backward* by 2.8 cm instead of *downward*, so the mouth had almost no visible gap to
   open), and `bite_pose`'s `reach` (head/neck/lunge) and `jaw_open` curves peaked and decayed
   together, so the "open" and the "lunge" faded out as one move with no distinct snap. Fixed the
   hinge axis, then rebuilt the timing as two independent curves: `reach` ramps up and holds while
   `jaw_open` opens fast and slams shut well before `reach` lets go, giving a held "gripping" frame
   (head still thrust forward, jaw shut) between the snap and the retract. See
   `godot_shots/dog_bite_open.png` / `dog_bite_closed.png`.

## Revision 2 (2026-09-24, after Zach's second look, with real service-dog-vest reference photos)

Two more fixes:

1. **The vest needed to hug the torso, not stand off it.** Zach sent two real service-dog-vest
   photos: a mesh harness that hugs the ribcage closely with a girth strap under the belly and a
   chest strap in front, patches sewn flat onto the surface following its contour; a simpler red
   harness, same idea, fabric conforming to the body's curve. Revision 1's vest -- a big raised
   panel plus a wide standoff band -- was a "more visible" fix, not a "correctly shaped" one.
   Rebuilt `build_vest` around a `_coat_radius(y)` helper that samples the coat's own half-width/
   half-height along the torso (the same profile `build_body`'s spine loft uses) and adds a small
   constant `MARGIN` (1.1 cm): the vest BODY is now a snug wrap that grows and shrinks with the
   torso instead of an independently-sized shape, with the girth strap and chest strap as thin
   accents a hair proud of *that* surface, not of the bare coat. The cross and badge patches are
   flush (a third of Revision 1's thickness) and centred on the vest body's own local radius at
   their position, not a fixed height, so they sit like sewn patches instead of floating tabs. See
   `godot_shots/dog_vest_closeup.png` and `dog_vest_cross_patch.png`.
2. **The reared pose's hind legs weren't reading as planted, weight-bearing legs.** Two compounding
   bugs, found by actually querying the built rig's bone world positions (`htoe.L`/`.R`) instead of
   judging by eye alone:
   - **The real bug: `thigh.R`, `shin.R`, `hock.R`, `htoe.R` (and the front legs' `.R` equivalents)
     were rotating the *opposite* way from their `.L` counterparts.** `Poser.rot` mirrors the `X`
     axis for every bone ending in `.R` (so a single formula can drive both sides of a *mirrored*
     motion, like a walk cycle's alternating strides) -- but `biped_stand_pose` wants both legs to
     bend *identically* (a symmetric standing pose, not a mirrored one), and passed the same raw
     angle for both sides without accounting for that automatic mirroring. Measured result before
     the fix: `htoe.L`'s tail at world z = 0.53 m, `htoe.R`'s at z = 2.29 m -- the right hind "foot"
     was floating up near head height, which is exactly Zach's "not reading as two planted legs."
     Fixed with an explicit `msign` (1 for `.L`, -1 for `.R`) multiplied into every `X` angle in the
     hind- and front-leg loop, cancelling the built-in mirroring so both legs actually match.
   - **Pelvis height was a guess, not a measurement.** Once both legs bent identically, the hind toe
     tips still landed at world z = 0.53 m -- 0.53 m above the ground -- because `_pelvis_loc`'s
     height was chosen by eye in Revision 1. Fixed by measuring that exact number off the built rig
     (`GROUND_DROP = 0.5327`, with the measurement documented next to the constant) and subtracting
     it from `_pelvis_loc.z`, rather than nudging it and re-rendering until it looked close.
   Both hind paws now land within 1 cm of world y = 0 (the ground) and within 1 cm of each other --
   `tools/dog_lab.gd`'s `--shots` run checks this directly off the built rig every time
   (`PASS  both hind paws on the ground and level`) rather than relying on a screenshot looking
   right. New shot: `godot_shots/dog_standup_ground_sideon.png`, a level side view against a visible
   ground plane (`dog_lab.gd` now draws one) framed on the hind paws' own position specifically to
   show the contact.

## Revision 3 (2026-09-24, after Zach approved Revision 2's direction, four more small fixes)

Zach signed off on the ground contact and the form-fitting vest direction from Revision 2, then
asked for four more:

1. **The vest clipped through the neck.** Revision 2's vest body reached almost to `NECK1` and
   still weighted its front rings partly to `neck1`, so it clipped whenever the neck rotated away
   from the chest (idle's tilt, walk's pitch, and especially the big standup bend). Fixed by adding
   a hard `FRONT_Y` limit (`CHEST.y + 0.07`, well short of `NECK1`) that the vest body, both straps
   and every patch now respect, and by weighting the whole vest 100% to `chest` (no `neck1`
   anywhere) so it physically cannot follow the neck into a clash -- it stays with the torso no
   matter how the neck bends. Checked at idle (including the head-tilt extreme), mid-walk and the
   fully reared standup pose; see `godot_shots/dog_vest_closeup.png`, `dog_vest_cross_patch.png` and
   `dog_standup_ground_sideon.png` -- clear daylight between the coat's neck colour and the vest in
   all three.
2. **The cross patches moved from top-centre to the flanks.** Zach wanted them mirrored on the
   vest's left and right sides, not one on top. `build_vest` now places a cross patch on each side,
   facing outward (`cross_normal = (+/-1, 0, 0)`), instead of one centred on top.
3. **The legs didn't read as attached to the torso.** This was already flagged as a known rough
   edge ("legs meet the body at a bare tube junction") and Zach confirmed it was bothering him. Each
   leg's `add_tube` call now starts with an extra ring pulled inward toward the spine axis
   (`root_flare = (shoulder.x * 0.4, shoulder.y, shoulder.z)`) at a radius noticeably wider than the
   leg itself and sized closer to the torso's own local radius there, so the leg visibly flares into
   a shoulder/hip join instead of butting a uniform cylinder against the coat. Applied to all four
   legs (front legs default to a smaller flare, hind legs to a bigger one, since the hip region is
   naturally broader). See `godot_shots/dog_leg_junctions.png`.
4. **No real skull volume.** Also flagged by Zach after looking again: the neck ran straight into
   the tapering muzzle with nothing between them, and the ears had no head mass to visibly attach
   to. Added a `CRANIUM` control point to the skull loft (`HEAD -> CRANIUM -> SKULL_MID -> HEAD_TIP`,
   was just `HEAD -> SKULL_MID -> HEAD_TIP`) with a noticeably larger radius than either neighbour,
   giving the skull a real rounded bulge between the neck and the muzzle before it narrows again.
   `EAR_BASE`/`EAR_TIP` now anchor off `CRANIUM` instead of `HEAD` directly, so the ears sit on that
   bulge rather than floating off a bare taper. It is weighted entirely to the `head` bone like the
   rest of the skull, so it inherits the same pale `Dog_Skull` material automatically -- no separate
   color call needed, it reads as one continuous pale head structure by construction. See
   `godot_shots/dog_head_closeup.png`.

## Revision 4 (2026-09-24, leg junctions redone properly, not re-tuned)

Zach looked at Revision 3's leg junctions again: still off, and inconsistent across the four legs
(not the same construction front-to-back or left-to-right). Correctly diagnosed the cause --
Revision 3's `root_flare` was one hand-picked point per leg, tuned by eye per call site (front legs
got one `flare_rx`/`flare_rz`, hind legs another), so of course they didn't match: they were never
built the same way. This revision replaces that with one real fix instead of another nudge:

- **One shared routine, `_leg_junction(target, leg_r0)`, that every leg goes through** -- front and
  hind, left and right, with no per-call tuning left at all. It returns a 4-ring blend from ring 0
  (centred on the spine axis, at the coat's own `_coat_radius` for that ring's y -- not a guessed
  "wider" radius, the actual coat surface radius there) to `target` (the leg's own root landmark) at
  the leg's own thickness, eased with `smooth01`. Because ring 0 uses the coat's real radius at that
  exact y instead of an independently chosen bigger number, the leg's surface and the torso's
  surface actually coincide at the start of the blend -- which is what removes the seam, not just
  widening the ring next to it. `_COAT_PROFILE` was extended back to `RUMP`/`PELVIS` (previously it
  only covered `SPINE1`-`NECK1`) so this same profile now describes the whole torso, front or rear.
- **Front vs. hind sizing falls out of the shared function automatically, not a hand-picked
  parameter.** The hip region's `_coat_radius` is bigger than the chest's (matching `build_body`'s
  own spine numbers there), so hind-leg junctions come out visibly broader than front-leg ones
  without either being told to be a particular size -- exactly "same method, different attachment
  point," which is what was asked for.
- **Symmetry is now structural, not just a hope.** `_leg_junction` takes only `target` (already the
  correctly mirrored landmark, e.g. `mirror(HIP)` for the right leg) and a radius that does not
  depend on side at all -- there is no code path left where a `.L`/`.R` pair could be given different
  numbers. Verified from both sides, not just the one every earlier screenshot happened to favour:
  `godot_shots/dog_leg_junctions_left.png` / `_right.png` (full body) and
  `dog_leg_junction_front_left/right.png`, `dog_leg_junction_hind_left/right.png` (one front and one
  hind junction, close up, from each side) -- all four junctions read the same way, and the left and
  right shots of the same junction match.

## Revision 5 (2026-09-24, the vest clips the front legs after Revision 4)

A new issue Revision 4's own fix exposed: the vest now clips into the front legs. Measured, not
guessed, before touching anything: `_leg_junction(SHOULDER, 0.040)`'s rings all sit at
`y = SHOULDER.y = 0.24` (the whole junction blend happens at one Y, only varying X and radius --
see `_leg_junction`'s own docstring), and by ring 3 (at `SHOULDER` itself) the leg's outer edge
reaches `x = 0.175`. The vest's own radius at that same y was only `~0.079`. Worse, `ELBOW.y` is
`0.20` -- identical to `CHEST.y`, the torso's own widest point -- so the front leg's solid upper-arm
tube occupies almost exactly the same y range (0.20-0.24) as the vest body's peak coverage. There is
no vest radius that clears the leg there without the vest ballooning to a comically oversized shape,
so (as Zach offered as one of two acceptable approaches) this pulls the vest's coverage back instead
of trying to reshape around the leg -- the same shape of fix as Revision 3's neck clearance, and for
the same reason: a hard, measured boundary the geometry cannot cross, not a nudged number.

- Added `LEG_CLEAR_Y = min(SHOULDER.y, ELBOW.y) - 0.05`, measured directly off those two landmarks
  (not eyeballed), and folded it into `FRONT_Y` (`min(CHEST.y + 0.07, LEG_CLEAR_Y)`), so the vest
  body, the girth strap, the chest strap and every patch all stay behind it. In practice this means
  the vest body now stops short of the torso's own widest point and the front legs entirely, and the
  chest strap -- which used to cross right where the legs attach -- now stays behind them too, rather
  than risk brushing the leg on its way past.
- This does trade away a little accuracy against the reference photos (their chest strap visibly
  crosses right at the front legs); flagged below as the deliberate cost of guaranteeing zero
  clipping, and the one place in the vest a future pass might want to put back if a real strap can be
  routed around the leg's actual geometry instead of just avoiding its whole y range.
- Checked at idle, mid-walk and the fully reared standup pose, **from both sides** (the leg-junction
  mesh only needed checking once its symmetry was fixed in Revision 4, but the vest is new geometry
  laid on top and gets its own from-scratch check): `godot_shots/dog_vest_leg_clear_idle_left/
  right.png`, `_walk_left/right.png`, `_standup_left/right.png` -- no clipping in any of the six.

## Revision 6 (2026-09-24, re-fit the shrunk vest and move the cross to a flush centre decal)

Zach approved Revision 5's approach, then asked for two follow-ups now that the vest's covered
zone is smaller:

1. **Re-fit the vest to its new, smaller span.** Revision 5 kept every internal proportion
   (the girth strap's y, the chest strap's three points) as fractions of the *old*, larger
   `CHEST`/`NECK1`-based span, just clamped to not exceed the new `FRONT_Y`. That left several of
   them bunched at or past the new edge -- the chest strap's `top_y` and `strap_mid.y` had both
   collapsed onto the exact same value (`FRONT_Y`), which is a flat, squished-looking strap, not a
   diagonal one. Replaced every position in `build_vest` with a fraction `t` of the vest's actual
   `[REAR_Y, FRONT_Y]` span via a small `_y(t)` helper (`t=0` at the rear edge, `t=1` at `FRONT_Y`),
   so the body, the girth strap and the chest strap's three points are spread out properly across
   whatever span the vest actually has, however large or small that turns out to be -- re-fitting
   it once, structurally, instead of patching each collapsed number individually.
2. **Cross patches moved to the centre and made flush.** Back to one centred cross (not the
   Revision 3 flanks), and no longer a raised appliqué: two overlapping `add_patch` boxes (the
   Revision 3/5 construction) left a visible dark seam where their surfaces crossed, which read as a
   carved shape rather than paint. Added `Part.add_flat_poly`, a generic thin decal from any 2D
   outline, and built the cross as ONE twelve-point "+" outline through it -- a single continuous
   surface with no internal seam, at a third of the earlier patches' thickness so it reads as
   painted/printed rather than sewn on. The badge kept its box shape but was thinned the same amount
   for a consistent flush treatment.

Checked from both sides at idle, mid-walk and the fully reared standup pose again (the vest is
different geometry now, not just resized, so it earns a fresh clearance check, not just eyeballing
that the earlier one still looks fine): `godot_shots/dog_vest_leg_clear_idle_left/right.png`,
`_walk_left/right.png`, `_standup_left/right.png` -- no clipping in any of the six. New close-up of
the centred, flush cross: `godot_shots/dog_vest_closeup.png` and `dog_vest_cross_patch.png`.

## Revision 7 (2026-09-24, the Revision 6 cross was not actually visible)

Zach confirmed Revision 6's cross was not a rendering fluke -- it genuinely could not be seen in
`dog_vest_closeup.png` or `dog_vest_cross_patch.png`. Two real bugs, found by actually looking at
close-up renders rather than trusting that the geometry existed:

1. **`Dog_Vest_Cross`'s colour shared the exact same red channel as `Dog_Vest_Clean`'s** -- `(0.62,
   0.03, 0.02)` against the vest's `(0.62, 0.24, 0.05)`. They only differed in green/blue, which
   washed out under directional lighting; from a normal viewing angle the two were nearly the same
   brightness of the same hue. Fixed in `dog_materials.py`: a true bright red, `(0.85, 0.04, 0.03)`
   -- a higher red channel than the vest itself, not just a darker version of it.
2. **The decal's own bottom face sat exactly on the vest body's surface.** Revision 6's `cross_center`
   used `CHEST.z + ccz + MARGIN` -- precisely the vest's own outer radius there -- so the patch's
   bottom cap and the vest's surface beneath it were two coincident polygons z-fighting for the same
   pixels, which on top of `DECAL`'s already-thin extrusion could lose the fight entirely. Added a
   `STANDOFF` (0.0015 m) so the decal sits a hair clear of the surface it is painted onto, and
   brought `DECAL` back up near Revision 3's original, clearly-visible thickness (Zach: "if flush and
   visible are in tension, err toward visibility") -- still much thinner than an appliqué, but no
   longer imperceptible. Made the cross itself a little larger for the same reason.

The camera in `tools/dog_lab.gd`'s `vest_cross_patch` shot was also part of the problem: it framed
the vest side-on, level with the chest bone, while the cross sits on TOP of the vest at roughly the
chest bone's height plus the vest's own local radius -- out of frame regardless of how visible the
decal itself was. Retargeted at that actual position. See the new
`godot_shots/dog_vest_cross_patch.png`: the cross is unambiguous.

## Revision 8 (2026-09-24, the cross was self-intersecting, and a strap end poked out as a spike)

Zach looked at Revision 7's own screenshot again and flagged two more geometry problems in it,
both real, both found this time by actually reading `add_flat_poly`'s implementation rather than
just tuning numbers:

1. **The cross was clipping/self-intersecting, not clean paint.** The real bug was in
   `Part.add_flat_poly` itself, present since Revision 6: its cap triangulated the outline with a
   fan from point 0 (`for i in range(1, n - 1): faces.append((base+n, base+n+i, base+n+i+1))`),
   which is only a valid triangulation for a CONVEX polygon. A "+" outline is concave (it has
   reflex corners where the arms meet the centre square), so the fan produced triangles that fold
   back across the shape instead of tiling it -- reading as a dark self-intersecting gap right
   through the middle of the cross, which is exactly what Zach saw as "clipping into the vest."
   Fixed by giving `add_flat_poly` an explicit `cap_faces` parameter: a caller-supplied
   decomposition into convex pieces, wound the same way as the outline. A plus splits cleanly into
   5 quads -- the centre square (using the outline's own 4 inner-corner indices, no new vertices
   needed) plus one rectangle per arm -- so `build_vest` now passes that decomposition instead of
   leaving the cap logic to guess at a fan. No more coincident/folded triangles, so no more seam.
2. **A small spike near the vest's front-top was the chest strap's own end cap.** `strap_top` (the
   chest strap's upper end, `add_tube`'s default `cap_start=True`) sat proud of the vest body's
   surface by `top_cz + MARGIN` with nothing else covering it, so its pointed tube-end cap read as a
   stray spike sticking out of nothing rather than a strap disappearing into the vest it's meant to
   be stitched to. Pulled `strap_top` in to `top_cz * 0.72` -- inside the vest body's own local
   radius, not proud of it -- so that end (and its cap) sits buried in the body's solid volume,
   invisible, the way the girth strap's own ends already were.

Checked against the exact screenshot Zach flagged (`godot_shots/dog_vest_cross_patch.png`, same
angle) plus a fresh look at `dog_vest_closeup.png` and the standard idle/walk/standup, both-sides
leg-clearance set, since any vest-geometry change earns that check again.

## Revision 9 (2026-09-24, design change: the attack is a soul-drain, not a chase/bite)

Zach's design change, relayed the same day: the dog's "attack" is no longer a physical chase/bite —
it is a dementor-style soul-drain. This does not remove `Bite`/`Run` (kept, unpolished, in case
something else ever wants them) but adds the sequence the new mechanic actually uses, under a naming
contract shared with `service-dog-brain` (built in parallel on that branch against this same names):

1. **Four new clips**, all in `blender_src/dog_rig.py`, sharing a new `biped_drain_pose()` base (the
   same weight-bearing hind-leg stance as `biped_stand_pose()`, but jaws held wide, head level (not
   lowered — the head-track layer in `dog_rig.gd` aims it), front legs hanging loose at the sides
   instead of curled up tight like tucked forepaws):
   - `RearUp` (45 f / 0.75 s, one-shot): quadruped `stand_pose()` -> `biped_drain_pose()` via
     `lerp_pose` on an eased `smooth01` curve — a deliberate rise, not a jump. Since `stand_pose` has
     no `jaw` entry and `biped_drain_pose`'s is wide open, the lerp itself makes the jaw open
     progressively as it rises, with no separate curve needed.
   - `DrainIdle` (120 f / 2 s loop): standing tall, jaws held wide, a slow throb through the jaw/neck/
     chest (`0.5 - 0.5*cos`, the same easing shape `dog_rig.gd`'s glow hook is meant to pulse with)
     layered on top of the base pose.
   - `UprightWalk` (64 f / ~1 s loop): a slow, stiff biped walk cycle — small alternating hip/knee
     swings and loosely swinging front legs, deliberately far short of `Run`'s big lunging strides,
     roughly human walking pace.
   - `DropDown` (24 f / 0.4 s, one-shot): `biped_drain_pose()` -> quadruped `stand_pose()`, the
     reverse of `RearUp` but at half its duration — an abrupt "back to being a normal dog" snap
     instead of a mirrored deliberate rise.

   Registered in `scripts/assets.gd`'s `anims` dict as `rear_up`/`drain_idle`/`upright_walk`/
   `drop_down`, alongside (not replacing) the existing logical names.

2. **A continuous tail wag**, `dog_rig.gd`'s new `_wag()`, runs every frame regardless of
   `look_weight`/`twitch`/`ear_alert` (previously the whole modifier early-returned when all three
   were zero — restructured so `_wag` always runs and the rest of the function still short-circuits
   when there is nothing else to layer). Small enough (0.16 rad peak, tapering out along `tail1` ->
   `tail3`) to sit under a clip's own tail keyframes (e.g. `Walk`'s gait-tied tail motion) rather than
   fighting them, and it is what keeps the tail moving through `RearUp`/`DrainIdle`/`UprightWalk`/
   `DropDown`, none of which animate the tail themselves.

3. **The throat orb** — a real, separate piece, not baked into the skull/jaw geometry and not a
   texture trick, because it is meant to be harvestable in a future task. Built in
   `dog_rig.gd`'s `_build_orb()` (Godot-side, not Blender-side — simpler, and satisfies "own distinct
   mesh/node" without a Blender pipeline change): a small `SphereMesh` named `Orb`, its own
   `StandardMaterial3D`, on a `BoneAttachment3D` (`OrbAttach`) parented to the `jaw` bone near its
   head end — i.e. at the back of the mouth/throat, not the jaw tip. A sickly pale-green
   (`Color(0.62, 1.0, 0.58)`), deliberately not the same hue as the white skull or dark coat, so it
   reads as a distinct lit object rather than blending in. Dim (`albedo_color` at 35% of the emission
   colour, `emission_energy_multiplier` at 0.05) by default; `set_drain_glow(v: float)` (0..1) drives
   `emission_energy_multiplier` up to 2.6 — enough to read as a clear, saturating glow against the
   scene lighting without blowing out to pure white. This poser does not decide when to drain; the
   brain-logic side calls `set_drain_glow` from its own replicated state, and can reach the orb's
   world position via `model.skeleton.get_node("DogPoser/OrbAttach/Orb").global_position`.

Validated with the same loop as every prior revision: rebuild, reimport, `tools/dog_lab.tscn`
(headless structure check, then `--shots`) plus `tools/monster_lab.tscn`'s full 179-check regression
(0 failed, no changes needed there — this branch never touches gameplay/state-machine code).
`dog_lab.gd` gained shot blocks for all four new clips (`dog_rear_up_00/50/100.png`,
`dog_drain_idle.png`, `dog_upright_walk_midstride.png`, `dog_drop_down_00/50/100.png`) plus an orb
glow comparison (`dog_orb_glow_off.png` vs `dog_orb_glow_on.png`, `set_drain_glow(0.0)` then `(1.0)`
on the same frame/camera) and a `DogPoser`/`Orb` node-presence check.

## Revision 10 (2026-09-24, RearUp's backbend, and the orb's size/colour/one-sidedness)

Zach reviewed Revision 9's drain sequence and flagged three real problems, all fixed:

1. **`RearUp` ended in a backward arc, not upright.** The bug was in the new `biped_drain_pose()`:
   its `neck1`/`neck2`/`head` cancellation angles (`-0.05`/`-0.05`/`+0.05`) were half of
   `biped_stand_pose()`'s (`-0.15`/`-0.10`/`+0.10`), on the theory that the head should be "level,
   not lowered" for the look-track layer. But `chest`'s cumulative world-space pitch is the same
   ~1.79 rad in both poses, and it is exactly `neck1`/`neck2`/`head`'s job to cancel that pitch back
   out -- under-cancelling it left the head carrying most of the torso's backward lean, arcing back
   over the body instead of standing up straight. Fixed by copying `biped_stand_pose()`'s neck/head
   angles exactly, with a comment on `biped_drain_pose()` explaining why they have to match. The
   look-track layer still aims the head from there when `look_weight` is set; it did not need its
   own, different neck bend to do that.
2. **The orb was too big, and pale-green (not black) at rest.** Shrunk (`SphereMesh` radius
   0.032 m -> 0.014 m) and given a genuinely near-black rest colour (`ORB_REST_COLOR = Color(0.03,
   0.03, 0.03)`, both `albedo_color` AND `emission_energy_multiplier` down to 0 at rest -- previously
   only the emission was dim while the albedo stayed a lit pale-green, which is what read as "a
   visible glowing dot even at low intensity"). `set_drain_glow` now lerps `albedo_color` from
   `ORB_REST_COLOR` toward the glow colour as well as the emission, so a partial value reads as a
   faint green ember rather than the same green surface just changing brightness.
3. **The orb needed a ghostly green glow, visible from the front only, invisible from behind** (Zach
   attached a reference: a glowing green pendant with a dark silhouette inside, spectral/ectoplasm
   in mood -- colour and glow quality only, not the silhouette). Pulled the orb further back and down
   into the mouth cavity (`position` z -0.05 -> -0.075, plus a small extra recess on y) so the
   skull/jaw's own solid mesh occludes it from behind -- verified directly with `dog_lab.gd`'s new
   front/behind shot pair (`dog_orb_glow_*.png` vs `dog_orb_behind_*.png`, both computed off the
   model's own registered forward, `-model.rig.global_transform.basis.z`, not a guessed world axis
   or the head bone's own pitch -- the latter degenerates once the neck points near-vertical in the
   reared pose). Recoloured to a desaturated, low red/blue spectral green (`Color(0.12, 0.88, 0.34)`)
   and capped `ORB_ENERGY_MAX` at 1.5 (down from 2.6): pushed higher, this engine's tonemapping drives
   all three emission channels toward white together once bright enough, which erased the green read
   entirely at the old energy level -- capping it lower keeps the brightest frame still visibly green
   instead of clipping to white.

Checked with `dog_orb_glow_off.png`/`_on.png` (front, at rest and lit) and `dog_orb_behind_off.png`/
`_on.png` (directly behind, at rest and lit -- the orb is not visible in either), plus the corrected
`dog_rear_up_00/50/100.png` sequence, `dog_drain_idle.png` and the standard `monster_lab.tscn`
179-check regression (0 failed).

## Revision 11 (2026-09-24, the orb read as sitting on the neck, and RearUp still leaned back)

Zach looked at Revision 10 again and flagged two more problems:

1. **The orb read as sitting on the back of the neck, not inside the mouth.** Checked directly by
   printing the `jaw` bone's own world position and the orb's, and by adding a debug probe at the
   `jaw` bone's exact pivot with zero offset: the pivot itself sits at the base of the mouth's own
   hinge, but Revision 10's offset (`Vector3(0, -0.015, -0.075)`) moved AWAY from the visible opening
   (recessed toward the throat, past the point where the jaw's two prongs separate), which is why it
   read as sitting on the closed exterior skin below the jaw rather than inside the open gap. Fixed
   by moving it the other way along the jaw bone's own length axis (empirically confirmed which local
   axis that is, by comparing a few test offsets' world positions against the bone's own pivot) to
   `Vector3(0, -0.015, 0.10)`, which sits it visibly inside the mouth's own opening. Confirmed with a
   new `dog_orb_into_mouth.png` shot, framed from below and looking up into the open jaws (roughly how
   a player, now shorter than the reared dog, would actually see it) -- the orb sits tucked under the
   jaw's own overhang rather than floating on a flat exterior surface. This position is close enough
   to the opening that a close, head-height "directly behind" test camera can catch a faint glimpse of
   it at a steep grazing angle (`dog_orb_behind_on.png`); a second, more realistic behind check at
   human eye height and several metres back (`dog_orb_behind_far_*.png`, the distance and elevation an
   actual player standing behind this now-much-taller reared dog would be at) does not.
2. **`RearUp` still leaned back, just less than Revision 10's fix.** Rather than tune the neck
   cancellation angles even further (which is what caused the original bug -- see Revision 10),
   `biped_drain_pose()` now gives `spine1`/`chest` their OWN, smaller additions
   (`DRAIN_SPINE1_PITCH`/`DRAIN_CHEST_PITCH`, 0.06/0.05 rad instead of `biped_stand_pose()`'s
   0.14/0.10) on top of the same pelvis pitch: a genuine forward lean of the torso, not a neck trick,
   per Zach's suggestion. `neck1`/`neck2`/`head` keep the same angles as `biped_stand_pose()`'s
   (unchanged from Revision 10), and now land a few degrees past level -- a slight, deliberate forward
   lean instead of a backward arc. The front-leg cancellation, which depends on the chest's cumulative
   pitch, now uses this pose's own `DRAIN_CHEST_TOTAL` rather than the shared `BIPED_CHEST_PITCH`
   constant (which is still `biped_stand_pose()`'s own, different, value), so the arms still hang
   correctly relative to the new lean.

Checked with the corrected `dog_rear_up_00/50/100.png` sequence (now a genuine forward lean, not a
backbend, at the top of the rise) and the orb shots above, plus the standard `monster_lab.tscn`
179-check regression (0 failed).

## Revision 12 (2026-09-24, the real bug: the biped pose faced backward, not just leaned back)

A real integration test from `service-dog-brain` (merging this model into their running code, not
just eyeballing screenshots) found the actual bug Revisions 10-11 were dancing around: **the
quadruped clips (Idle/Walk/Growl/PlaceItem) and the standing clips (RearUp/DrainIdle/UprightWalk)
faced OPPOSITE directions in the exported rig.** No single `yaw` in `scripts/assets.gd` could make
both correct. Confirmed by measuring bone positions directly (not a camera illusion): on all fours
the `head` bone sits at +0.62 m (local); reared up, it sits at -0.60 m -- the opposite sign.
Reproduced exactly by probing the built rig directly in Blender (see below).

**Root cause**, found by actually computing what `biped_stand_pose()`/`biped_drain_pose()` do to
bone POSITIONS, not just bone rotations (which is all Revisions 10-11 ever looked at): every pose
delta here is a world-space rotation about a shared 'X' axis, and a bone's final POSITION is the sum,
across the whole kinematic chain, of each ancestor segment's REST vector rotated by THAT segment's
own cumulative angle. A segment whose cumulative angle overshoots past its own "straight up" angle
contributes a NEGATIVE (backward) residual instead of a positive (forward) one. `neck2`'s rest vector
in particular is unusually steep -- the quadruped idle neck already curves up sharply toward the head,
so at rest it is already ~43 degrees off vertical -- and the old flat `-0.10` rad delta left its
cumulative pitch at ~81 degrees, 38 degrees PAST that, which is what actually flipped the whole
standing figure's measured forward direction. Revisions 10-11 only ever looked at the head bone's own
final ORIENTATION (does it visually look like it's arcing back?), which is a real but DIFFERENT
symptom of the same underlying pitch, and never caught the POSITION bug the brain track's integration
test found, because a bone can still be oriented "facing forward" while its actual computed position
sits behind where the quadruped pose's own convention says it should.

**Fix**: `dog_rig.py`'s `BIPED_SPINE1_PITCH`/`BIPED_CHEST_PITCH_DELTA`/`BIPED_NECK1_PITCH`/
`BIPED_NECK2_PITCH`/`BIPED_HEAD_PITCH` replace the old hand-tuned `spine1`/`chest`/`neck1`/`neck2`/
`head` deltas in both `biped_stand_pose()` and `biped_drain_pose()` (now sharing one set, since the
correct value is a property of each bone's own rest geometry, not a per-pose stylistic choice).
Each is derived from that bone's own rest vector, landing its cumulative pitch close to its own
"straight up" angle -- `BIPED_PELVIS_PITCH` (which the hind-leg and `GROUND_DROP` math both depend
on) is untouched, so grounding is unaffected. This fixes the actual bug at the source (in Blender,
not a runtime spin bolted onto specific clips in `dog_rig.gd`) and, as a side effect, also finishes
what Revisions 10-11 were chasing by eye (no more visible backward arc). `biped_drain_pose()`'s own
Revision 11 patch (separate, smaller `spine1`/`chest` additions) is gone -- superseded.

Confirmed directly with a side-by-side: the SAME camera offset, relative to each pose's own measured
pelvis->head forward direction, applied to both `Idle` and `DrainIdle` (`dog_facing_check_idle.png` /
`dog_facing_check_drain_idle.png`) -- the dog faces the same way in both. `tools/dog_lab.gd`'s orb
shots were re-verified too: the earlier "into the mouth" shot (`dog_orb_into_mouth.png`) had actually
been aimed at the back of the skull/neck the whole time (this same bug fooled the camera script, not
just the rig) -- it now genuinely shows the orb inside the open jaws, confirmed from a wide,
whole-body "player standing in front" angle (`dog_orb_front_wide.png`) as well as the close crop.

**Two smaller things** flagged by the same integration test:
- `RearUp` (45 frames/1.5 s) and `DropDown` (24 frames/0.8 s) were roughly double the design brief's
  ~0.7 s / ~0.4 s (the brain track was compensating with its own time-scaling). Shortened to 21 and 12
  frames respectively (30 fps bake rate) to match the brief directly.
- `dog_rig.gd`'s `ear_alert` code converted `look_at` from world space before using it, while the
  class doc comment and `_look()` (the head-track code right above it) both treat `look_at` as
  already skeleton space. Removed the stray `affine_inverse()` conversion so both code paths agree
  with the documented contract, which is what the brain track is actually passing.

Not changed (flagged as a design question, not a bug): the reared model's head sits at 1.83 m (mouth
at 1.98 m), only slightly above the player's 1.70 m eye height, versus the brief's "taller than the
player." Left for Zach's judgement when he sees it in a real review; the height comes from
`BIPED_PELVIS_PITCH` and `GROUND_DROP`, both load-bearing for leg-grounding, so changing it is a
bigger, separate task rather than a quick tweak.

Validated with the full loop: rebuild, reimport, `tools/dog_lab.tscn` (structure check + `--shots`)
and `tools/monster_lab.tscn`'s 179-check regression (0 failed) -- including `StandUp`/`Run`, which
share the corrected `biped_stand_pose()` and were re-screenshotted to confirm they still read as
upright and still have both hind paws grounded (the dedicated check in `dog_lab.gd` still passes).

## Revision 13 (2026-09-24, styling pass: surface detail, and a real crystal-ball orb)

Zach approved the base model/rig/animations after Revision 12 -- this pass is styling/detail only,
not another correctness fix.

1. **Grime, fur variation and blood on the coat and vest.** `dog_materials.py`'s `Dog_Coat`,
   `Dog_Skull`, `Dog_Vest_Clean` and `Dog_Vest_Worn` (the two small icon patches, `Dog_Vest_Cross`/
   `Dog_Vest_Badge`, stay flat/clean -- Zach has twice asked for the cross specifically to read
   unambiguously, not weathered) each build a small procedural Cycles node graph -- fine fur-clump
   micro-noise, blotchy grime concentrated low on the legs/belly/hem (a real animal picks up dirt
   from the ground, not the shoulders), and a scatter of dried-blood stains -- and `dog_build.py`
   self-bakes each one (a Cycles `DIFFUSE`/`COLOR`-pass bake, no separate high-poly source since this
   mesh has none) through each part's own already-packed UV layer into `Dog_Body_Albedo` (1024,
   covering Coat + Skull) and `Dog_Vest_Albedo` (512, covering Vest_Clean + Vest_Worn) -- the same
   "real baked texture atlas" pattern art/seal/ and art/night_nurse/ use, just without their AO/normal
   bake (no high-poly sculpt to bake those from). Textures live in `blender_src/textures/` (committed,
   like the seal's) and the game copy under `assets/models/monsters/service_dog/textures/`.
   - **Bug found and fixed while wiring this up:** baking `Dog_Body_Albedo` then `Dog_Vest_Albedo`
     right after it silently zeroed the FIRST image back to solid black. Root cause: Blender's bake
     operator, with `use_clear=True`, clears whichever image is the "active" bake target it finds --
     and a stale active/selected node left over in the FIRST bake's own materials (never explicitly
     deselected before starting the second) still counted, even though those materials were not used
     by the second bake's object at all. Fixed by deselecting every node in every material in the
     whole file before each bake, not just the ones about to be baked.
   - Getting the blood stains to a "reads well, not overwhelming" AMOUNT took a few passes: a
     colour-ramp threshold on a single noise turned out to be extremely sensitive (swinging from
     "invisible" to "half the model soaked in red" over a few percent of threshold), because the
     underlying noise's actual value distribution was not what a naive 0..1 assumption expects.
     Replaced with a noise raised to a high power (`POWER`, exponent 9) before scaling: this makes
     only the noise's own highest peaks survive, which is far less sensitive to the exact multiplier
     and also gives the surviving spots a soft, organic falloff (a soaked-in stain edge, not a
     painted one) for free.
2. **The throat orb is now a real two-layer crystal ball, not a plain sphere** (Zach: "bigger and
   more detailed -- like an actual crystal ball"). `dog_rig.gd`'s `_build_orb()` builds two nested
   meshes on the same `OrbAttach`: an OUTER glass shell (bigger than before -- 0.026 m radius, up
   from 0.014 -- glossy via a clearcoat pass, a fresnel rim highlight, and `refraction_enabled` for a
   little glass-like distortion) around an INNER wisp core (a smaller, unshaded, emissive sphere
   whose `emission_texture` is a `NoiseTexture2D` cellular-noise swirl run through a steep colour
   ramp, so it reads as distinct bright threads rather than an even glow, slowly rotated in
   `_process_modification_with_delta` for a lazy tumbling-wisp read). `set_drain_glow` now drives
   both layers together: the outer shell's own colour/emission (dark, near-opaque glass at rest;
   ghostly green, more translucent once lit, so the inner wisp's glow can actually show through) and
   the inner core's emission energy (dim at rest, brighter at full drain). Still respects every
   existing rule: small/dark/inert at rest, ghostly green and clearly visible from the front once
   active, not visible from directly behind (re-confirmed -- see below).

Validated with the full loop: rebuild, reimport, `tools/dog_lab.tscn` (structure check + `--shots`)
and `tools/monster_lab.tscn`'s 179-check regression (0 failed). Screenshots: `dog_idle.png`,
`dog_vest_closeup.png`, `dog_walk_midstride.png` and the leg-clearance set for the new grime/fur/
blood texture from several angles; `dog_orb_glow_off.png`/`_on.png`, `dog_orb_into_mouth.png` and
`dog_orb_front_wide.png` for the new crystal-ball orb at rest and active, plus `dog_orb_behind_on.png`/
`dog_orb_behind_far_on.png` re-confirming it still is not visible from behind at the bigger size.

## Revision 14 (2026-09-24, Revision 13's grime/blood texture was genuinely invisible)

Zach confirmed directly: Revision 13's grime/fur/blood texture read as completely absent in actual
renders, the same category of bug as an earlier invisible-cross-patch problem (something technically
built, not actually reaching the screen) -- not a "just re-tune the intensity" ask, a "find out why
it is not rendering at all" one. Checked the whole pipeline end to end before touching any numbers:

1. **The exported GLB's materials.** Dumped the `.glb`'s JSON directly: `Dog_Coat`/`Dog_Skull`/
   `Dog_Vest_Clean` all have a real `baseColorTexture` (not just a flat `baseColorFactor`), pointing
   at the correct `images[]` entries (`Dog_Body_Albedo` / `Dog_Vest_Albedo`). Correct.
2. **The imported Godot material.** A headless probe script instantiating the actual game `.glb` and
   reading each `MeshInstance3D`'s active `BaseMaterial3D` confirmed `albedo_texture` is set to the
   right `CompressedTexture2D` (correct size, correct resource path) and `albedo_color` is pure white
   (so it would not tint/hide the texture). Correct.
3. **The UV mapping.** The same probe dumped each surface's actual `ARRAY_TEX_UV` range: a healthy
   spread across ~0.01-0.99 on every textured surface, not degenerate or collapsed to a single point
   (which would bake fine but sample as a single flat colour on the model, exactly the reported
   symptom). Correct.
4. **The texture files themselves, opened directly.** `Dog_Body_Albedo.png`/`Dog_Vest_Albedo.png`
   DID show real per-island noise variation and a faint reddish tint under close inspection --
   nothing was blank or corrupt.

So every link in the pipeline Zach's checklist named was actually fine. The real root cause was
narrower and easy to miss precisely because everything upstream looked correct: **the numbers
Revision 13 landed on were themselves too small to survive being lit, shaded and re-encoded into a
screenshot** -- not a pipeline bug, a contrast bug in the material graph itself:

- The fur micro-noise varied brightness by only +-12%.
- `Dog_Coat`'s grime colour (`(0.008, 0.007, 0.009)`) was DARKER than the coat's own near-black base
  colour (`(0.028, 0.026, 0.030)`) -- on an already near-zero-luminance material, "even darker" has
  nowhere to go and reads as nothing. Real dirt is dusty and lighter/warmer than wet black fur, not
  blacker-than-black; the grime colour was tonally backwards for what it was supposed to depict.
- The blood mask, after Revision 13's own "stop it covering half the model" fix, had been dialed
  back to a coverage so small it amounted to a handful of near-invisible pixels once baked into a
  1024x1024 atlas shared across ~40 UV islands.

Fixed by actually confronting the contrast, not just nudging a knob: fur micro-noise to +-35%;
`Dog_Coat`'s grime colour flipped to a genuinely lighter, warmer dust tone that contrasts against
the near-black base instead of trying to out-black it; the grime factor's cap raised from 0.85 to
1.0 (it was never allowed to fully show even where the mask said it should); and every material's
`blood_amount` roughly doubled. Confirmed directly, not just by re-reading the flat texture atlas
this time: `dog_idle.png` and `dog_vest_leg_clear_idle_left.png` show an unmistakable grey-brown
grime pattern up the legs against the near-black torso, and `dog_leg_junction_hind_left.png` shows a
clearly visible dark-red dried-blood stain at the shoulder, right where the front leg meets the
vest strap -- a specific, pointable patch, not a texture-atlas crop.

Validated with the same full loop: rebuild, reimport, `tools/dog_lab.tscn` (structure check +
`--shots`), `tools/monster_lab.tscn`'s 179-check regression (0 failed).

## Revision 15 (2026-09-24, much more blood: genuinely covered, not a stain or two)

Zach: Revision 14's blood was the right technique but far too little of it -- he wants the dog
genuinely covered (body, vest, face, everywhere), not a stain here and there. Same masking technique
as Revision 14 (a low-frequency noise raised to a power for a soft, soaked-in edge), pushed
substantially harder in three ways:

- The power exponent dropped from 9 (Revision 13) already down to a moderate value in Revision 14,
  now down further (1.7) so far more of the noise's own range clears the mask, not just its rare
  peaks -- the difference between "a few isolated spots" and "a wash".
- `blood_amount` roughly tripled to quintupled across all four materials (`Dog_Coat`/`Dog_Skull`
  0.09/0.10 -> 0.55, `Dog_Vest_Clean`/`Dog_Vest_Worn` 0.12/0.10 -> 1.1/1.0), with `blood_color`
  pushed toward a more saturated red on top.
- **The skull needed a separate fix, not just a bigger number.** Turning up `blood_amount` alone left
  the skull/face completely white -- no blood at all -- even though the coat right next to it was
  visibly soaked. Root cause: the skull is a small, confined area in object space, and the blood
  noise's frequency (tuned for the much bigger coat/vest) was low enough that the ENTIRE skull sat
  inside a single low-noise cell, so no amount of scaling that one value up could push it over the
  mask threshold. Added a per-material `blood_scale` knob and gave the skull a much higher one (7.0
  vs the default 2.2) so the noise actually varies across its own small footprint instead of sampling
  it as one uniform (low) value.

Confirmed on a fresh render, not the texture atlas: `dog_idle.png` and `dog_vest_closeup.png` read as
heavily bloodied at a glance -- the coat, legs and vest are all a deep, saturated red-brown, not a
subtle tint -- and `dog_head_closeup.png` shows the skull/snout carrying the same coverage as the
body (previously pure white with nothing on it).

Validated with the same full loop: rebuild, reimport, `tools/dog_lab.tscn` (structure check +
`--shots`), `tools/monster_lab.tscn`'s 179-check regression (0 failed).

## Revision 16 (2026-09-25, Revision 15 overshot: splatters, not a full-body soak)

Zach on Revision 15: "WAYYYYY too much." He wants distinct blood splatters/drips with clearly clean
coat/vest/skull visible everywhere else, not full coverage -- and specifically asked for this to come
from making the mask itself sharper/more discrete, not just multiplying the same wash down by a
uniform factor (which would just be a fainter version of the same problem).

- Added a `blood_power` knob to `_grimy_material` (the exponent the blood noise is raised to before
  masking): Revision 15 had dropped it to 1.7 for maximum coverage; Revision 16 raises it back up to
  4.0, so the clean-to-bloody transition is sharp and only the noise's own high spots read as blood
  at all, instead of most of its range doing so.
- Added a `blood_scale` override per material (the coat/vest's own default lowered to 1.3, well below
  Revision 14/15's 2.2): a lower frequency makes each surviving mark a recognisable splatter-sized
  blob instead of an even, fine speckle.
- `blood_amount` cut to well under half of Revision 15's levels across `Dog_Coat` (0.55 -> 0.45),
  `Dog_Vest_Clean` (1.1 -> 0.65) and `Dog_Vest_Worn` (1.0 -> 0.6).
- **The skull needed the opposite adjustment on `blood_amount` despite the same sharper `blood_power`**
  -- turning the mask more discrete (a good thing for the coat/vest) made the skull's already-touchy
  small-area problem (see Revision 14/15) worse, not better: at the coat/vest-appropriate amount, the
  sharpened mask cleared threshold NOWHERE on the skull's small footprint, reading as plain white
  again. Fixed empirically by pushing `blood_amount` up to 1.6 (well above the coat/vest's ~0.5-0.65)
  while keeping `blood_scale` at a separate, higher 4.5 (down a little from Revision 15's 7.0, for a
  slightly bigger/more recognisable mark, but still well above the coat/vest's 1.3 so the skull's own
  small area still has room to vary instead of landing in one uniform noise cell).

Confirmed on a fresh render, not the texture atlas: `dog_head_closeup.png` shows a single, clearly
bounded dark-red streak along the jaw with the rest of the snout and skull tip still pale and clean;
`dog_leg_junction_hind_left.png` shows a distinct red splatter at the shoulder/vest seam with clean
coat visible on both sides of it; `dog_idle.png` and `dog_vest_closeup.png` show the dog mostly its
normal coat/vest colour at a glance, with a few clearly readable blood marks, not an even tint.

Validated with the same full loop: rebuild, reimport, `tools/dog_lab.tscn` (structure check +
`--shots`), `tools/monster_lab.tscn`'s 179-check regression (0 failed).

## Folder

| Path | What |
|---|---|
| `../../assets/models/monsters/service_dog/` | The game copy: `service_dog.glb` (no separate texture files -- see "Materials" below) |
| `blender_src/dog_geometry.py` | Ring-loft shape functions for the whole body, in Blender's own Z-up frame |
| `blender_src/dog_materials.py` | Four flat Principled BSDF materials (no bake pass -- see "Known problems") |
| `blender_src/dog_rig.py` | The from-scratch quadruped armature, direct analytic skin weights, and all 7 clips |
| `blender_src/dog_build.py` | Runs everything: mesh, materials, rig, weights, actions, `.blend`, `.glb` |
| `blender_src/dog_glb_extern.py` | Splits embedded GLB images into external PNGs (copy of the Seal's/Nurse's; currently a no-op here since there are no baked textures to split) |
| `blender_src/service_dog.blend`, `service_dog_embedded.glb` | Blender source and the intermediate export (both git-ignored) |
| `godot_shots/` | Screenshots from `tools/dog_lab.tscn` |

## Rebuild

```
cd art/service_dog/blender_src
blender --background --factory-startup --python dog_build.py -- --export   # ~10 s

cd ../../..
godot4 --headless --path . --import
godot4 --headless --fixed-fps 60 --path . tools/dog_lab.tscn               # structure + clip check, exit code
xvfb-run -a godot4 --path . --resolution 1000x750 tools/dog_lab.tscn -- --shots   # -> art/service_dog/godot_shots/
```

There is no `--tex=`/`--ao-samples=`/`--nobake` knob like the Seal or Night Nurse builds: this
pipeline does not bake, so it has nothing to tune there (see "Known problems").

## How it is made

- **Frame.** Authored in Blender's native Z-up axes (X side, Y forward, Z height) — the same
  convention as `nn_geometry.py` and `seal_geometry.py` — with the animal standing on z = 0 and the
  root under its centre of mass. `--export` writes glTF Y-up (`export_yup=True`), which is what
  turns this into the +Z-forward, y-is-height frame every monster GLB in this project uses;
  `assets.gd` registers it with yaw 180 like the others. **This axis convention bit twice while
  building it** (see "Known problems" — worth flagging for whoever templates the next quadruped).
- **Body.** A single `Dog_Body` mesh, all ring lofts (`dog_geometry.loft_tube`): one continuous
  spine loft from the rump through the pelvis, waist, chest, neck and into the skull base; a
  separate skull loft (base -> mid -> tip) with a per-angle radius dip carved into the mid ring for
  sunken eye sockets (a small raised "brow" ridge just above each, per the reference art); a thin
  lower-jaw loft; two small ear cones; a four-bone tail whip; and four legs, each three tube segments
  (upper/lower/pastern) plus a tapered "toe" cone standing in for a single hoof-like paw (image ref
  3's "almost hoof-like feet" — simpler to build than splayed toes and read strongly as wrong).
- **No separate eyes.** The sockets are geometry only — sunken, and left the same dark coat colour
  as the rest of the head map (no globe, no glint). This is the strongest and most deliberate tonal
  call in the whole model; see "Open design calls" below, it is the one most worth Zach's eyes.
- **Materials — a smaller step than the Seal/Night Nurse pipeline, but the same bake-to-texture
  pattern since Revision 13.** Those bake a procedural Cycles material to a full PBR texture atlas
  (albedo/roughness/normal/AO) from a separate high-poly source. This model still skips the
  high-poly source (there isn't one) and the roughness/normal/AO maps, but `dog_materials.py`'s six
  Principled BSDF materials (`Dog_Coat`, `Dog_Skull`, `Dog_Vest_Clean`, `Dog_Vest_Worn`,
  `Dog_Vest_Cross`, `Dog_Vest_Badge`) are no longer flat colour blocks: `dog_geometry.py` computes a
  per-vertex `head` mask (from the same bone-weight blend used for skinning: near 1 on the skull and
  jaw, 0 everywhere else) and a `stain` mask on the vest (low on the girth, along the back panel's
  rear edge, plus a deterministic sine-based pseudo-noise — no RNG); `dog_build.py` picks each face's
  material by averaging its vertices' mask value, so the pale skull, dark body and clean/worn vest
  patches are real per-face material choices with no UV-packing risk. The vest's two icon patches
  (`Part.add_patch`, small raised boxes) instead force their material directly, bypassing the mask
  average entirely (`Part.face_mat`) and stay flat/clean (see "Revision 13" below for why). The four
  big-area materials now carry a real baked texture (fur-clump micro-noise, grime, dried-blood
  stains) instead of a flat colour — see "Revision 13".
- **Rig — the first quadruped skeleton in the project.** 29 deform bones: `pelvis` -> `spine1` ->
  `chest` -> `neck1` -> `neck2` -> `head` -> `jaw`; `tail1..4`; `ear.L`/`ear.R`; and per side
  `upperarm`/`forearm`/`pastern`/`toe` (front) and `thigh`/`shin`/`hock`/`htoe` (hind). Bone naming
  follows the human/Night-Nurse `.L`/`.R` convention. Weights are direct and analytic (each ring's
  vertices get the exact bone-blend `dog_geometry.py` computed while building it), not bone heat —
  same reasoning as the Seal: everything here is a tube loft, so heat weighting has nothing to add
  and analytic weights guarantee the sockets and paws stay exactly on the bones they were authored
  against in every pose. **Gotcha that cost real time:** `dog_rig.skin()` parents with
  `ARMATURE_NAME`, which auto-creates one *empty* vertex group per deform bone; the first pass then
  called `vertex_groups.new()` again for the real weights, which Blender silently renamed to
  `"name.001"` — the Armature modifier read the original (empty) groups and the mesh never visibly
  deformed in any clip. Fixed by `vertex_groups.get(bone) or vertex_groups.new(name=bone)`; worth
  grepping for if a future rig here "plays" every clip but never looks like it's moving.
- **Clips**, all 30 fps, built the same way as the Night Nurse's (`Poser` + per-bone
  `[(axis, angle), ...]` pose dicts, baked to keyframes by `keyframe_action`):
  - `Idle` (150 f / 5 s loop): held still, then one slow, too-deliberate head tilt — longer than a
    real dog would hold a look — with a barely-there weight-shift sway. `dog_rig.gd`'s `twitch`
    input layers a further tremor and an occasional ear flick on top at runtime.
  - `Walk` (48 f / 1.6 s loop, in place): a sighthound-ish gait, front and hind roughly opposite
    phase, long low strides.
  - `PlaceItem` (60 f / 2 s, one-shot): head and neck lower, jaw opens, holds near the ground, rises.
  - `Growl` (24 f / 0.8 s, one-shot): ears pin, the jaw parts a hair, ~1 mm chest tremor. Short and
    subtle on purpose — the brief only asked for triggerable-on-demand, not long.
  - `StandUp` (50 f / 1.7 s, one-shot): quadruped -> biped. **The hardest single piece of this
    task** — see "Revision 1" below for the fix that made the hind legs actually plant and bear
    weight instead of the whole body reading as balanced on one leg. `dog_rig.lerp_pose` blends the
    quadruped `stand_pose()` into a new `biped_stand_pose()` (hips pitched up, hind legs bent and
    under the body bearing weight, front legs curled up and tucked against the chest like forepaws,
    tail out for balance) with an eased `smooth01` timing curve.
  - `Run` (30 f / 1 s loop, biped): built on `biped_stand_pose()`, big alternating hind-leg strides,
    the folded front legs pumping a little, torso pitched forward.
  - `Bite` (24 f / 0.8 s, one-shot): a lunging attack, reworked in Revision 1 — see below. The
    head/neck/body reach forward and hold while the jaw opens fast and snaps shut well before the
    head retracts, so there is a distinct held "gripping" frame (head still thrust forward, jaw
    closed) between the snap and the pull-back, not one pose fading in and out together. **Kept but
    no longer used for the attack** as of Revision 9 (see below) — the soul-drain sequence replaced
    it for that purpose.
  - `RearUp`/`DrainIdle`/`UprightWalk`/`DropDown`: the soul-drain sequence added in Revision 9 (see
    below) — quadruped -> biped with jaws opening, a held wide-jawed idle with a slow throb, a slow
    stiff biped walk, and the snap back down to quadruped.

## `scripts/monsters/dog_rig.gd`

The `SkeletonModifier3D` that layers procedural poses on top of whatever clip is playing (same
pattern as `night_nurse_rig.gd`/`hive_rig.gd`):

- `look_at` / `look_weight`: turns the head (and lets `ear_alert` turn the ears) toward a point in
  skeleton space — the growl/warning beat's head-track the brief asked for, and the soul-drain
  sequence's head-lock-on-target.
- `twitch`: a low, constant, barely-there tremor through the spine/tail plus a rare ear flick —
  "wrong" stillness, not nervous energy, matching the "looming, too patient" tone.
- `ear_alert`: ears pin back and orient toward `look_at`.
- A continuous slow tail wag (Revision 9) runs every frame regardless of the three inputs above.
- `set_drain_glow(v: float)` (Revision 9): 0..1, controls the throat orb's emission brightness —
  see "Revision 9" above for what the orb is and where it lives.

It does not yet plug into `MonsterModel`'s `dog` field beyond `setup()`/`_anim_key()`/`eye_offset()`
(added on this branch so `monster_lab`-style validation works today); anything state-machine-driven
(when to raise `twitch`, when to call `look_at`) is `service-dog-brain`'s to wire.

## Validate

`tools/dog_lab.gd`/`.tscn`: builds `MonsterModel` directly with `kind = "service_dog"` (no
Monster/brain in the loop, since that lives on `service-dog-brain`), the same way the other monsters'
labs work but scoped to just this model.

```
godot4 --headless --fixed-fps 60 --path . tools/dog_lab.tscn        # structure + every clip present, exit 0/1
xvfb-run -a godot4 --path . --resolution 1000x750 tools/dog_lab.tscn -- --shots
```

The `--shots` run has no display in this container, so it renders through Xvfb + the software
(llvmpipe) GL renderer — slow, but pixel-correct, and it is what produced `godot_shots/`.

## Known problems / open design calls

**Two calls Zach has not signed off on — flag these:**

- **Vest condition.** The garment itself is locked in (bold safety-orange, cross + badge -- Zach's
  Revision 1 note was "make the vest itself unmistakable first," which this now is). What's still a
  judgement call is how dirty it gets: `Dog_Vest_Worn`'s stain mask darkens the low girth and the
  back panel's rear edge, plus a scattered pseudo-noise pattern, kept deliberately to a minority of
  the surface so it never competes with the base garment's visibility. `dog_geometry.build_vest`'s
  stain formula (three weighted terms, commented inline) is the one knob to turn either direction.
- **Blank eye sockets, no eyeball geometry.** The skull's sockets are sunken but otherwise plain
  coat-dark — no separate eye mesh, no glint, nothing for the game's eye-tracking/glow conventions
  (`Monster.eye_transform`, other monsters' `eye_glint`) to hang off visually. This is the strongest
  tonal choice in the model (matches image refs 3/4 exactly) but may read as *too* blank for
  gameplay legibility (e.g. telegraphing a head-track). If Zach wants any eye readability back, the
  cheapest fix is a small emissive dot placed by `dog_rig.gd` at the socket location, not a geometry
  change.

**Technical simplifications, not tonal calls:**

- **Bake pipeline is colour-only (Revision 13).** A self-bake of `dog_materials.py`'s procedural
  grime/blood/fur node graphs to `Dog_Body_Albedo`/`Dog_Vest_Albedo` (see "Revision 13" below) —
  still no roughness/normal/AO maps, and no separate high-poly source to bake them from even if
  added. The seal/night-nurse bake pipeline (`seal_materials.py` + `seal_build.py`'s bake step,
  which DOES have a high-poly source) would be the template to fork if this needs that level of
  surface detail later.
- **StandUp and Run are a working pass, not a polished one.** This is a genuinely novel animation
  problem for the project (nothing else here blends a quadruped and a biped skeleton). Revision 2
  fixed the actual ground contact (both hind paws measured within 1 cm of the ground and of each
  other -- see "Revision 2" above and `godot_shots/dog_standup_ground_sideon.png`), so the pose now
  reads as genuinely standing rather than floating or balanced on one leg, but the transition itself
  (see `godot_shots/dog_standup_35.png` / `_65.png`) is still not graceful frame-by-frame, and
  `Run`'s stride reads as a dynamic lunge more than a controlled sprint. Both would benefit from
  another pass with fresh eyes before they ship as final.
- **Legs now blend into a shoulder/hip join through the shared `_leg_junction` (Revision 4)**
  instead of the bare tube junction the Seal's README calls out for its own flipper root. Ring 0 of
  the blend sits exactly on the coat's own surface radius, so there is no seam at gameplay distance
  and the four junctions are provably built the same way. It is still a procedural approximation
  (four rings interpolating position and radius), not sculpted anatomy or a true modelled socket --
  up close, it is a smooth taper into the torso rather than an anatomically detailed shoulder.
- **The vest is a snug wrap plus thin strap accents, not a cloth sim.** It now hugs the ribcage and
  follows the coat's own contour (Revision 2), which is the shape that matters, but the geometry
  itself is still simple lofts and thin raised boxes, not tailored/simulated cloth -- it won't fold
  or crease, and the patches, while flush, are still slightly-raised boxes up close rather than
  truly embroidered/printed detail.
- **The vest no longer reaches the front legs at all (Revision 5).** Necessary to guarantee zero
  clipping against Revision 4's wider leg junctions (see "Revision 5" above), but it means the vest
  body and chest strap now stop noticeably short of the torso's own widest point and the front legs,
  which is less accurate to the reference photos than earlier revisions in that one respect (their
  chest strap visibly crosses right at the front legs). The next real improvement here would be
  routing the chest strap around the leg's actual measured geometry instead of just staying behind
  its whole y range.
- **`Dog_Vest_Worn`'s "pseudo-noise"** is a sum of sines of the vertex position, not real noise —
  fine at this triangle density, would tile visibly at higher resolution.
- **The mouth is a hair open even at rest.** The jaw loft's static offset below the skull (needed so
  the Bite clip has visible travel to open through) means the "closed" pose is a narrow, not zero,
  gap. Reads fine at gameplay distance and arguably suits the "wrong dog" tone (a mouth that never
  quite shuts), but it is a compromise, not a deliberate choice, and `dog_geometry.build_body`'s
  jaw hinge offset (currently -0.036 m) is the knob if Zach wants it flush shut at rest.

## Stats

- **Triangles:** `Dog_Body` 986 + `Dog_Vest` 344 = **1,330** for the whole model (no bake source, so
  no separate high-poly count).
- **Materials:** 6 Principled BSDF (`Dog_Coat`, `Dog_Skull`, `Dog_Vest_Clean`, `Dog_Vest_Worn`,
  `Dog_Vest_Cross`, `Dog_Vest_Badge`); the first four carry a baked grime/blood/fur texture as of
  Revision 13 (`Dog_Body_Albedo` 1024x1024, `Dog_Vest_Albedo` 512x512), the icon-patch two stay flat.
- **Bones:** 29 deform + `root`. **Clips:** Idle, Walk, PlaceItem, Growl, StandUp, Run, Bite,
  RearUp, DrainIdle, UprightWalk, DropDown (11 total).
- **Throat orb (Revision 9, restyled Revision 13):** Godot-side, on `BoneAttachment3D` "OrbAttach"
  under `jaw`, not part of the Blender build's own triangle/material counts above -- a two-layer
  crystal ball, an outer glass-shell `SphereMesh` (`Orb`) around a smaller unshaded, emissive inner
  wisp `SphereMesh` (`OrbCore`) with a swirl `NoiseTexture2D`.
