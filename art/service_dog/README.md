# The Service Dog: Blender sources

**Built 2026-09-24, art side of the Service Dog feature; revised eight times the same day after
Zach's reviews (see "Revision 1" through "Revision 8" below), then given a ninth pass the same day
for a design change (see "Revision 9" below): the attack is now a dementor-style soul-drain, not a
chase/bite.** The model is `assets/models/monsters/service_dog/service_dog.glb` (asset key
`monster/service_dog`; skinned mesh, 2 objects, 6 materials, 11 clips), registered in
`scripts/assets.gd`. `scripts/monsters/dog_rig.gd` is its `SkeletonModifier3D` (head-tracking, idle
"wrongness", continuous tail wag, the throat orb's glow hook), following the Night Nurse / Hive
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
- **Materials — a smaller step than the Seal/Night Nurse pipeline.** Those bake a procedural Cycles
  material to a PBR texture atlas (albedo/roughness/normal/AO) from a high-poly source. This model
  skips that: `dog_materials.py` is six flat Principled BSDF materials (`Dog_Coat` dark charcoal,
  `Dog_Skull` pale bone, `Dog_Vest_Clean` a saturated safety-vest orange, `Dog_Vest_Worn`,
  `Dog_Vest_Cross`, `Dog_Vest_Badge`), and `dog_geometry.py` computes a per-vertex `head` mask (from
  the same bone-weight blend used for skinning: near 1 on the skull and jaw, 0 everywhere else) and a
  `stain` mask on the vest (low on the girth, along the back panel's rear edge, plus a deterministic
  sine-based pseudo-noise — no RNG). `dog_build.py` picks each face's material by averaging its
  vertices' mask value, so the pale skull, dark body and clean/worn vest patches are real per-face
  material choices with no bake step and no UV-packing risk. The vest's two icon patches
  (`Part.add_patch`, small raised boxes) instead force their material directly, bypassing the mask
  average entirely (`Part.face_mat`). The trade: no fur variation, no normal-mapped detail, no AO.
  Flagged as a place to invest more if the flat look reads too clean in the finished lighting.
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

- **No baked texture pipeline.** Flat per-face materials only (see "Materials" above) — no fur
  variation, no normal map, no AO. The seal/night-nurse bake pipeline (`seal_materials.py` +
  `seal_build.py`'s bake step) would be the template to fork if this needs more surface detail later.
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
- **Materials:** 6 flat Principled BSDF (`Dog_Coat`, `Dog_Skull`, `Dog_Vest_Clean`, `Dog_Vest_Worn`,
  `Dog_Vest_Cross`, `Dog_Vest_Badge`), no textures.
- **Bones:** 29 deform + `root`. **Clips:** Idle, Walk, PlaceItem, Growl, StandUp, Run, Bite,
  RearUp, DrainIdle, UprightWalk, DropDown (11 total).
- **Throat orb (Revision 9):** a Godot-side `SphereMesh` (`Orb`, on `BoneAttachment3D` "OrbAttach"
  under `jaw`), not part of the Blender build's own triangle/material counts above.
