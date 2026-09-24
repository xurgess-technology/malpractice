# The Service Dog: Blender sources

**Built 2026-09-24, art side of the Service Dog feature; revised twice the same day after Zach's
reviews (see "Revision 1" and "Revision 2" below).** The model is
`assets/models/monsters/service_dog/service_dog.glb` (asset key `monster/service_dog`; skinned mesh,
2 objects, 6 materials, 7 clips), registered in `scripts/assets.gd`. `scripts/monsters/dog_rig.gd` is
its `SkeletonModifier3D` (head-tracking, idle "wrongness"), following the Night Nurse / Hive
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
    closed) between the snap and the pull-back, not one pose fading in and out together.

## `scripts/monsters/dog_rig.gd`

The `SkeletonModifier3D` that layers procedural poses on top of whatever clip is playing (same
pattern as `night_nurse_rig.gd`/`hive_rig.gd`):

- `look_at` / `look_weight`: turns the head (and lets `ear_alert` turn the ears) toward a point in
  skeleton space — the growl/warning beat's head-track the brief asked for.
- `twitch`: a low, constant, barely-there tremor through the spine/tail plus a rare ear flick —
  "wrong" stillness, not nervous energy, matching the "looming, too patient" tone.
- `ear_alert`: ears pin back and orient toward `look_at`.

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
- **Legs meet the body at a bare tube junction**, same limitation the Seal's README calls out for
  its flipper root: no modelled shoulder/hip socket, just one loft pushed into another.
- **The vest is a snug wrap plus thin strap accents, not a cloth sim.** It now hugs the ribcage and
  follows the coat's own contour (Revision 2), which is the shape that matters, but the geometry
  itself is still simple lofts and thin raised boxes, not tailored/simulated cloth -- it won't fold
  or crease, and the patches, while flush, are still slightly-raised boxes up close rather than
  truly embroidered/printed detail.
- **`Dog_Vest_Worn`'s "pseudo-noise"** is a sum of sines of the vertex position, not real noise —
  fine at this triangle density, would tile visibly at higher resolution.
- **The mouth is a hair open even at rest.** The jaw loft's static offset below the skull (needed so
  the Bite clip has visible travel to open through) means the "closed" pose is a narrow, not zero,
  gap. Reads fine at gameplay distance and arguably suits the "wrong dog" tone (a mouth that never
  quite shuts), but it is a compromise, not a deliberate choice, and `dog_geometry.build_body`'s
  jaw hinge offset (currently -0.036 m) is the knob if Zach wants it flush shut at rest.

## Stats

- **Triangles:** `Dog_Body` 778 + `Dog_Vest` 356 = **1,134** for the whole model (no bake source, so
  no separate high-poly count).
- **Materials:** 6 flat Principled BSDF (`Dog_Coat`, `Dog_Skull`, `Dog_Vest_Clean`, `Dog_Vest_Worn`,
  `Dog_Vest_Cross`, `Dog_Vest_Badge`), no textures.
- **Bones:** 29 deform + `root`. **Clips:** Idle, Walk, PlaceItem, Growl, StandUp, Run, Bite.
