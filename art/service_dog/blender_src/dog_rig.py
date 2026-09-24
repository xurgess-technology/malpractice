"""Armature, weights and hand-authored procedural animation for the Service Dog: the first
from-scratch quadruped rig in this project (art/night_nurse/blender_src/nn_rig.py is the sibling
convention for a monster with a locomotion rig; art/seal/blender_src/seal_rig.py is the sibling
convention for authoring a non-human skeleton, but the seal never walks).

Bone naming follows the human/night-nurse convention (dotted `.L`/`.R` suffixes) so
`scripts/monsters/dog_rig.gd` and any tooling that already knows that convention keeps working.
"""
import math
import bpy
from mathutils import Vector, Matrix
import dog_geometry as G

# (name, head, tail, parent)
SPINE = [
    ('pelvis', tuple(G.RUMP), tuple(G.PELVIS), 'root'),
    ('spine1', tuple(G.PELVIS), tuple(G.SPINE1), 'pelvis'),
    ('chest', tuple(G.SPINE1), tuple(G.CHEST), 'spine1'),
    ('neck1', tuple(G.CHEST), tuple(G.NECK1), 'chest'),
    ('neck2', tuple(G.NECK1), tuple(G.NECK2), 'neck1'),
    ('head', tuple(G.NECK2), tuple(G.HEAD_TIP), 'neck2'),
    ('jaw', (G.HEAD.x, G.HEAD.y, G.HEAD.z - 0.036), tuple(G.JAW_TIP), 'head'),
]

TAIL = [
    ('tail1', tuple(G.TAIL[0]), tuple(G.TAIL[1]), 'pelvis'),
    ('tail2', tuple(G.TAIL[1]), tuple(G.TAIL[2]), 'tail1'),
    ('tail3', tuple(G.TAIL[2]), tuple(G.TAIL[3]), 'tail2'),
    ('tail4', tuple(G.TAIL[3]), tuple(G.TAIL[4]), 'tail3'),
]

EARS = [
    ('ear.L', tuple(G.EAR_BASE), tuple(G.EAR_TIP), 'head'),
]


def leg_bones_front(side, shoulder, elbow, wrist, paw, toe):
    return [
        ('upperarm.' + side, tuple(shoulder), tuple(elbow), 'chest'),
        ('forearm.' + side, tuple(elbow), tuple(wrist), 'upperarm.' + side),
        ('pastern.' + side, tuple(wrist), tuple(paw), 'forearm.' + side),
        ('toe.' + side, tuple(paw), tuple(toe), 'pastern.' + side),
    ]


def leg_bones_hind(side, hip, knee, hock, paw, toe):
    return [
        ('thigh.' + side, tuple(hip), tuple(knee), 'pelvis'),
        ('shin.' + side, tuple(knee), tuple(hock), 'thigh.' + side),
        ('hock.' + side, tuple(hock), tuple(paw), 'shin.' + side),
        ('htoe.' + side, tuple(paw), tuple(toe), 'hock.' + side),
    ]


def all_defs():
    defs = list(SPINE) + list(TAIL) + list(EARS)
    defs.append(('ear.R', tuple(G.mirror(G.EAR_BASE)), tuple(G.mirror(G.EAR_TIP)), 'head'))
    defs += leg_bones_front('L', G.SHOULDER, G.ELBOW, G.WRIST, G.FPAW, G.FTOE)
    defs += leg_bones_front('R', G.mirror(G.SHOULDER), G.mirror(G.ELBOW), G.mirror(G.WRIST), G.mirror(G.FPAW), G.mirror(G.FTOE))
    defs += leg_bones_hind('L', G.HIP, G.KNEE, G.HOCK, G.HPAW, G.HTOE)
    defs += leg_bones_hind('R', G.mirror(G.HIP), G.mirror(G.KNEE), G.mirror(G.HOCK), G.mirror(G.HPAW), G.mirror(G.HTOE))
    return defs


def build_armature(_joints=None):
    arm_data = bpy.data.armatures.new('Dog_Rig')
    arm = bpy.data.objects.new('ServiceDog_Rig', arm_data)
    bpy.context.scene.collection.objects.link(arm)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.mode_set(mode='EDIT')
    eb = arm_data.edit_bones
    root = eb.new('root')
    root.head, root.tail = (0, 0, 0), (0, 0.15, 0)
    root.use_deform = False
    defs = all_defs()
    for name, h, t, parent in defs:
        b = eb.new(name)
        b.head, b.tail = Vector(h), Vector(t)
    for name, h, t, parent in defs:
        b = eb[name]
        b.parent = eb[parent]
        b.use_connect = (Vector(h) - eb[parent].tail).length < 1e-4
        # Blender is Z-up here (see dog_geometry.py): a bone is "vertical" when its length is
        # mostly a change in Z (the legs), "horizontal" when it is mostly a change in Y (the spine).
        vertical = abs(Vector(t).z - Vector(h).z) > 0.5 * (Vector(t) - Vector(h)).length
        b.align_roll(Vector((0, -1, 0)) if vertical else Vector((0, 0, 1)))
    bpy.ops.object.mode_set(mode='OBJECT')
    return arm


def assign_weights(obj, part):
    """Direct analytic weights from dog_geometry.Part.w -- no bone heat, so the sockets and paws
    stay exactly on the bones they were authored against in every pose. Reuses the (empty) vertex
    groups `skin`'s ARMATURE_NAME parenting already created one per deform bone: creating new ones
    of the same name here would silently rename them to "name.001" and leave the Armature modifier
    reading the original, empty group -- every deform bone would then move with no vertex following it."""
    groups = {}
    for i, wd in enumerate(part.w):
        for bone, weight in wd.items():
            if weight <= 1e-4:
                continue
            if bone not in groups:
                groups[bone] = obj.vertex_groups.get(bone) or obj.vertex_groups.new(name=bone)
            groups[bone].add([i], weight, 'REPLACE')


def skin(obj, arm):
    bpy.ops.object.select_all(action='DESELECT')
    obj.select_set(True)
    arm.select_set(True)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.parent_set(type='ARMATURE_NAME')
    mod = obj.modifiers.get('Armature')
    if mod is None:
        mod = obj.modifiers.new('Armature', 'ARMATURE')
    mod.object = arm


# ------------------------------------------------------------------ posing (see nn_rig.py Poser)
class Poser:
    def __init__(self, arm):
        self.arm = arm
        self.rest = {b.name: b.matrix_local.to_3x3() for b in arm.data.bones}

    def rot(self, name, rots):
        R = Matrix.Identity(3)
        right = name.endswith('.R')
        for ax, ang in rots:
            if right and ax in ('X', 'Z'):
                ang = -ang
            R = Matrix.Rotation(ang, 3, ax) @ R
        M = self.rest[name]
        return (M.inverted() @ R @ M).to_quaternion()

    def apply(self, pose, frame=None):
        pbs = self.arm.pose.bones
        for pb in pbs:
            pb.rotation_mode = 'QUATERNION'
            pb.rotation_quaternion = self.rot(pb.name, pose.get(pb.name, []))
            if frame is not None:
                pb.keyframe_insert('rotation_quaternion', frame=frame)
        loc = pose.get('_pelvis_loc', Vector())
        M = self.rest['pelvis']
        pbs['pelvis'].location = M.inverted() @ Vector(loc)
        if frame is not None:
            pbs['pelvis'].keyframe_insert('location', frame=frame)


def add(pose, bone, *rots):
    pose.setdefault(bone, []).extend(rots)


def lerp_pose(a, b, t):
    """Blend two pose dicts (lists of (axis, angle) per bone) linearly by angle; used only for the
    stand-up transition, where every source pose shares the same bones and axis order."""
    out = {}
    keys = set(a) | set(b)
    for k in keys:
        if k == '_pelvis_loc':
            va = a.get(k, Vector())
            vb = b.get(k, Vector())
            out[k] = va.lerp(vb, t)
            continue
        ra = a.get(k, [])
        rb = b.get(k, [])
        n = max(len(ra), len(rb))
        merged = []
        for i in range(n):
            ax = ra[i][0] if i < len(ra) else rb[i][0]
            va = ra[i][1] if i < len(ra) else 0.0
            vb = rb[i][1] if i < len(rb) else 0.0
            merged.append((ax, va + (vb - va) * t))
        out[k] = merged
    return out


# --------------------------------------------------------------------------- rest / quadruped poses
def stand_pose():
    """Alert quadruped stance: legs planted, spine level, head up. This is also frame 0 of every
    quadruped clip and the reference the walk cycle oscillates around."""
    p = {}
    add(p, 'neck1', ('X', -0.05))
    add(p, 'neck2', ('X', -0.20))
    add(p, 'head', ('X', 0.05))
    return p


def idle_pose(f, n=150):
    """Held stillness, then a slow, too-deliberate head tilt -- longer than a real dog would ever
    hold a look (image ref 1: 'looming', unnervingly patient)."""
    t = f / n
    p = stand_pose()
    hold = 0.55
    if t < hold:
        tilt = 0.0
    else:
        tilt = math.sin((t - hold) / (1.0 - hold) * math.pi)
    add(p, 'neck2', ('Z', 0.10 * tilt))
    add(p, 'head', ('Z', 0.22 * tilt), ('X', 0.05 * tilt))
    add(p, 'ear.L', ('X', -0.08 * tilt))
    add(p, 'ear.R', ('X', 0.05 * tilt))
    # An almost-imperceptible sway, like weight shifting on locked legs -- not a breath.
    sway = math.sin(t * G.TAU) * 0.008
    add(p, 'spine1', ('Z', sway))
    add(p, 'chest', ('Z', -sway * 0.6))
    p['_pelvis_loc'] = Vector((0, sway * 0.01, 0))
    return p


def walk_pose(f, n=48):
    """A quadruped walk cycle: diagonal-ish sighthound gait (front/hind roughly opposite phase),
    long low strides on the exaggerated legs."""
    ph = f / n * G.TAU
    p = stand_pose()
    add(p, 'spine1', ('X', 0.03 * math.sin(ph * 2)))
    add(p, 'chest', ('X', -0.02 * math.sin(ph * 2)))
    bob = -0.02 * (1.0 - math.cos(ph * 2))
    p['_pelvis_loc'] = Vector((0, bob, 0))
    front = [('L', 0.0), ('R', math.pi)]
    hind = [('L', math.pi * 0.5), ('R', math.pi * 1.5)]
    for side, offset in front:
        s = math.sin(ph + offset)
        swing = max(0.0, s)
        stance = max(0.0, -s)
        add(p, 'upperarm.' + side, ('X', 0.55 * s))
        add(p, 'forearm.' + side, ('X', -0.35 - 0.55 * swing))
        add(p, 'pastern.' + side, ('X', 0.15 + 0.35 * swing))
        add(p, 'toe.' + side, ('X', -0.25 * swing))
    for side, offset in hind:
        s = math.sin(ph + offset)
        swing = max(0.0, s)
        add(p, 'thigh.' + side, ('X', 0.5 * s))
        add(p, 'shin.' + side, ('X', -0.30 - 0.6 * swing))
        add(p, 'hock.' + side, ('X', 0.30 + 0.45 * swing))
        add(p, 'htoe.' + side, ('X', -0.20 * swing))
    add(p, 'tail1', ('X', 0.05 * math.sin(ph)), ('Z', 0.10 * math.sin(ph * 2)))
    add(p, 'tail2', ('Z', 0.10 * math.sin(ph * 2 + 0.4)))
    add(p, 'tail3', ('Z', 0.10 * math.sin(ph * 2 + 0.8)))
    add(p, 'head', ('Z', 0.03 * math.sin(ph)))
    return p


def place_pose(f, n=60):
    """Head lowers, mouth opens, something is set down at the ground (a quadruped clip; not
    cyclic). Peaks a little past halfway and holds briefly before rising back."""
    t = f / n
    lower = G.smooth01(t / 0.55) if t < 0.55 else 1.0 - G.smooth01((t - 0.75) / 0.25)
    lower = max(0.0, min(1.0, lower))
    p = stand_pose()
    add(p, 'neck1', ('X', 0.55 * lower))
    add(p, 'neck2', ('X', 0.75 * lower))
    add(p, 'head', ('X', 0.35 * lower))
    add(p, 'jaw', ('X', -0.85 * lower))
    add(p, 'thigh.L', ('X', 0.06 * lower))
    add(p, 'thigh.R', ('X', 0.06 * lower))
    p['_pelvis_loc'] = Vector((0, -0.02 * lower, 0))
    return p


def growl_pose(f, n=24):
    """Short, subtle: ears pin, lip curls (jaw parts a little, head lowers a hair), a low
    almost-inaudible-looking tremor. Triggerable on demand, does not need to be long."""
    t = f / n
    k = math.sin(t * math.pi)
    p = stand_pose()
    add(p, 'neck1', ('X', 0.12 * k))
    add(p, 'neck2', ('X', 0.10 * k))
    add(p, 'head', ('X', -0.05 * k))
    add(p, 'jaw', ('X', -0.30 * k))
    add(p, 'ear.L', ('X', -0.30 * k), ('Z', -0.10 * k))
    add(p, 'ear.R', ('X', 0.20 * k), ('Z', 0.10 * k))
    tremor = math.sin(t * G.TAU * 6) * 0.01 * k
    add(p, 'chest', ('X', tremor))
    return p


def bite_pose(f, n=24):
    """A fast lunging bite, unambiguous as an attack (Zach: "should read as the dog lunging its
    head/jaw at the target and biting -- jaw should visibly open and snap shut, ideally with a
    forward head/neck lunge, not a static pose"). Two independent curves, not one: `reach` (the
    head/neck/body driving forward) ramps up and HOLDS while `jaw` opens fast, then slams shut well
    before the head retracts -- so there is a distinct held "gripping" frame (head still thrust
    forward, jaw closed) between the snap and the pull-back, instead of the open and the lunge
    peaking and fading together. Not cyclic."""
    t = f / n
    if t < 0.22:
        reach = G.smooth01(t / 0.22)
    elif t < 0.62:
        reach = 1.0
    else:
        reach = 1.0 - G.smooth01((t - 0.62) / 0.38)
    if t < 0.16:
        jaw_open = G.smooth01(t / 0.16)
    elif t < 0.28:
        jaw_open = 1.0 - G.smooth01((t - 0.16) / 0.12)
    else:
        jaw_open = 0.0
    p = stand_pose()
    add(p, 'neck1', ('X', 0.50 * reach))
    add(p, 'neck2', ('X', 0.75 * reach))
    add(p, 'head', ('X', 0.30 * reach))
    add(p, 'jaw', ('X', -1.95 * jaw_open))
    add(p, 'upperarm.L', ('X', 0.30 * reach))
    add(p, 'upperarm.R', ('X', 0.30 * reach))
    add(p, 'thigh.L', ('X', 0.12 * reach))
    add(p, 'thigh.R', ('X', 0.12 * reach))
    p['_pelvis_loc'] = Vector((0, 0.09 * reach, -0.02 * reach))
    return p


# --------------------------------------------------------------------------- biped poses
## How much the pelvis pitches up in the biped pose (world-space 'X' rotation, see Poser.rot).
BIPED_PELVIS_PITCH = 1.55
## Cumulative world-space rotation carried down to 'chest' once pelvis + spine1 + chest all add
## their own deltas on top of each other (each bone's delta composes with its parents', since
## Poser.rot expresses every delta as a genuine world-space rotation about the same global axis --
## rotations about the same axis simply add). Front-leg angles below are chosen relative to this,
## not the pelvis pitch alone, since the arms hang off the chest, not the hips.
BIPED_CHEST_PITCH = BIPED_PELVIS_PITCH + 0.14 + 0.10


def biped_stand_pose():
    """Reared onto the hind legs: hips pitched up under the spine, the hind legs bent and planted
    under the body to bear the shifted weight (like a dog sitting up on its haunches, not a rigid
    pivot), the front legs curled up and tucked against the chest like forepaws, the tail out for
    balance. The end pose of StandUp and the rest pose of Run.

    The hind legs matter most here (Zach: "two hind legs planted and weight-bearing, not the whole
    body balanced on one leg"). `thigh` is a direct child of `pelvis`, and since every pose delta
    below is a world-space rotation about a shared global axis, thigh's own delta needs to roughly
    CANCEL the pelvis's pitch (so the leg doesn't get carried along for the ride and end up
    pointing sideways) before adding the extra bend that makes it read as crouched and bearing
    weight. `shin`/`hock` don't need that cancellation -- their parent (`thigh`) is back near its
    own rest orientation once cancelled, so their deltas act like an ordinary standing bend."""
    p = {}
    add(p, 'pelvis', ('X', BIPED_PELVIS_PITCH))
    add(p, 'spine1', ('X', 0.14))
    add(p, 'chest', ('X', 0.10))
    add(p, 'neck1', ('X', -0.15))
    add(p, 'neck2', ('X', -0.10))
    add(p, 'head', ('X', 0.10))
    for side in ('L', 'R'):
        # Poser.rot mirrors 'X' (and 'Z') for every ".R" bone (matches this rig's other poses,
        # e.g. walk_pose's per-side sin phases already expect it) -- but here both legs are meant
        # to bend IDENTICALLY (a symmetric standing pose, not a mirrored one), so every 'X' value
        # below is pre-negated for the right side to cancel that mirroring out. Forgetting this is
        # exactly what put the right hind paw up near head height in the previous revision.
        msign = 1.0 if side == 'L' else -1.0
        # Cancel the pelvis's pitch, then bend the knee and hock as if crouched and weight-bearing.
        add(p, 'thigh.' + side, ('X', msign * (-BIPED_PELVIS_PITCH - 0.55)))
        add(p, 'shin.' + side, ('X', msign * 1.05))
        add(p, 'hock.' + side, ('X', msign * -0.35))
        add(p, 'htoe.' + side, ('X', msign * 0.15))
        # Front legs curl up and in against the chest like tucked forepaws: cancel the chest's
        # cumulative pitch (so they don't get carried past vertical with the torso), fold the
        # "shoulder" forward and up, then curl the elbow and wrist in tight.
        add(p, 'upperarm.' + side, ('X', msign * (-BIPED_CHEST_PITCH + 1.15)), ('Z', 0.12 if side == 'L' else -0.12))
        add(p, 'forearm.' + side, ('X', msign * -1.55))
        add(p, 'pastern.' + side, ('X', msign * 0.75))
    add(p, 'tail1', ('X', -0.35))
    add(p, 'tail2', ('X', -0.25))
    # This is the number that actually plants the hind paws: with the leg bend above, the hind
    # toe tips land 0.533 m above z = 0 (ground) at pelvis_loc = 0, measured directly off the rig
    # (see the worked-out comment on GROUND_DROP below) -- so the pelvis has to come down by
    # that much, not by eye.
    p['_pelvis_loc'] = Vector((0, 0.16, 0.30 - GROUND_DROP))
    return p


## Measured, not guessed: with `biped_stand_pose`'s hind-leg bend and `_pelvis_loc.z = 0`, the hind
## toe tips (htoe's tail) sit at world z = 0.5327 (checked directly off the built rig -- see
## art/service_dog/README.md, "Revision 2: getting the hind paws on the ground"). Subtracting this
## from `_pelvis_loc.z` is what actually grounds them, rather than an eyeballed offset.
GROUND_DROP = 0.5327


def standup_pose(f, n=50):
    """The stand-up transition: quadruped -> biped. A first pass at a novel problem for this
    project (nothing else here blends quadruped and biped poses) -- see README 'Known problems'."""
    t = G.smooth01(f / n)
    return lerp_pose(stand_pose(), biped_stand_pose(), t)


def run_pose(f, n=30):
    """Biped chase run, once reared up: big alternating strides, arms (the folded front legs)
    pumping a little, torso pitched forward."""
    ph = f / n * G.TAU
    base = biped_stand_pose()
    p = {k: list(v) for k, v in base.items() if k != '_pelvis_loc'}
    add(p, 'pelvis', ('X', -1.40))
    add(p, 'spine1', ('X', 0.28))
    add(p, 'chest', ('X', 0.10))
    add(p, 'neck1', ('X', -0.30))
    add(p, 'head', ('X', 0.10))
    bob = abs(math.sin(ph)) * 0.05
    p['_pelvis_loc'] = base['_pelvis_loc'] + Vector((0, bob - 0.03, 0))
    for side, off in (('L', 0.0), ('R', math.pi)):
        s = math.sin(ph + off)
        add(p, 'thigh.' + side, ('X', 1.10 + 0.75 * s))
        add(p, 'shin.' + side, ('X', -0.20 - 0.9 * max(0.0, -s)))
        add(p, 'hock.' + side, ('X', 0.20 + 0.5 * max(0.0, s)))
        add(p, 'upperarm.' + side, ('X', 1.55 - 0.35 * s))
        add(p, 'forearm.' + side, ('X', -2.0 + 0.25 * s))
    add(p, 'tail1', ('X', -0.30), ('Z', 0.15 * math.sin(ph)))
    return p


def biped_drain_pose():
    """Soul-drain reared pose (Zach: the attack is now a dementor-style drain, not a chase/bite).
    Same weight-bearing hind-leg stance as `biped_stand_pose`, but the jaw is held wide open, the
    head stays level (not lowered) so the look-track layer in dog_rig.gd can lock it onto the
    target, and the front legs hang loose at the sides instead of curling up tight against the
    chest -- a tidy "tucked forepaws" read is wrong for something looming and draining. This is the
    shared base for RearUp's end state, DrainIdle, UprightWalk and DropDown's start state."""
    p = {}
    add(p, 'pelvis', ('X', BIPED_PELVIS_PITCH))
    add(p, 'spine1', ('X', 0.14))
    add(p, 'chest', ('X', 0.10))
    add(p, 'neck1', ('X', -0.05))
    add(p, 'neck2', ('X', -0.05))
    add(p, 'head', ('X', 0.05))
    add(p, 'jaw', ('X', -1.65))
    for side in ('L', 'R'):
        # Same mirror-cancelling convention as biped_stand_pose (see its comment): every 'X' value
        # below is pre-negated for the right side so both legs bend identically.
        msign = 1.0 if side == 'L' else -1.0
        add(p, 'thigh.' + side, ('X', msign * (-BIPED_PELVIS_PITCH - 0.55)))
        add(p, 'shin.' + side, ('X', msign * 1.05))
        add(p, 'hock.' + side, ('X', msign * -0.35))
        add(p, 'htoe.' + side, ('X', msign * 0.15))
        # Loose hang, not a tight curl: cancel the chest's cumulative pitch down to just past
        # vertical, then only a slight, relaxed elbow/wrist bend -- limp, not tucked.
        add(p, 'upperarm.' + side, ('X', msign * (-BIPED_CHEST_PITCH + 0.15)))
        add(p, 'forearm.' + side, ('X', msign * -0.35))
        add(p, 'pastern.' + side, ('X', msign * 0.15))
    add(p, 'tail1', ('X', -0.35))
    add(p, 'tail2', ('X', -0.25))
    p['_pelvis_loc'] = Vector((0, 0.16, 0.30 - GROUND_DROP))
    return p


def rear_up_pose(f, n=45):
    """Quadruped -> biped_drain: a deliberate rise onto the hind legs, NOT a jump (Zach), jaws
    opening progressively as it rises since `stand_pose` has no jaw entry and `biped_drain_pose`'s
    is wide open -- `lerp_pose` ramps that in step with everything else. ~0.75s at 60 fps."""
    t = G.smooth01(f / n)
    return lerp_pose(stand_pose(), biped_drain_pose(), t)


def drop_down_pose(f, n=24):
    """Biped_drain -> quadruped stand: the reverse of RearUp, jaws closing, but snappier -- an
    abrupt "back to being a normal dog" snap rather than a mirrored deliberate rise. ~0.4s at
    60 fps (half of RearUp's duration)."""
    t = G.smooth01(f / n)
    return lerp_pose(biped_drain_pose(), stand_pose(), t)


def drain_idle_pose(f, n=120):
    """Standing tall, jaws held wide, head locked on the target (the look-track layer in
    dog_rig.gd handles the actual aiming) -- a slow throb through the jaw/throat and chest in time
    with the orb's glow pulse (dog_rig.gd's `set_drain_glow` uses the same cadence), front legs
    hanging loose. Cyclic."""
    t = f / n
    p = biped_drain_pose()
    throb = 0.5 - 0.5 * math.cos(t * G.TAU)  # 0..1, eases through both ends like the orb's pulse
    add(p, 'jaw', ('X', -0.12 * throb))
    add(p, 'neck2', ('X', -0.04 * throb))
    add(p, 'chest', ('X', 0.02 * throb))
    return p


def upright_walk_pose(f, n=64):
    """A slow, stiff biped walk toward the target -- roughly human walking pace, deliberately NOT
    fast or lunging (Zach). Head stays locked on via the look-track layer; jaws stay open; front
    legs swing loosely at the sides like slack arms instead of pumping like `run_pose`'s folded
    ones. Cyclic."""
    ph = f / n * G.TAU
    base = biped_drain_pose()
    p = {k: list(v) for k, v in base.items() if k != '_pelvis_loc'}
    bob = abs(math.sin(ph)) * 0.02
    p['_pelvis_loc'] = base['_pelvis_loc'] + Vector((0, bob, 0))
    for side, off in (('L', 0.0), ('R', math.pi)):
        s = math.sin(ph + off)
        add(p, 'thigh.' + side, ('X', 0.35 * s))
        add(p, 'shin.' + side, ('X', -0.15 - 0.25 * max(0.0, -s)))
        add(p, 'hock.' + side, ('X', 0.10 + 0.15 * max(0.0, s)))
        add(p, 'upperarm.' + side, ('X', -0.20 * s))
        add(p, 'forearm.' + side, ('X', 0.10 * max(0.0, s)))
    add(p, 'tail1', ('X', -0.30), ('Z', 0.08 * math.sin(ph)))
    return p


def build_actions(arm):
    poser = Poser(arm)

    def act(name, n, fn, cyclic=True):
        a = bpy.data.actions.new(name)
        a.use_fake_user = True
        arm.animation_data_create()
        arm.animation_data.action = a
        for f in range(n + 1 if cyclic else n):
            poser.apply(fn(f), frame=f)
        try:
            a.frame_range = (0, n)
            a.use_frame_range = True
            a.use_cyclic = cyclic
        except Exception:
            pass
        return a

    act('Idle', 150, idle_pose, cyclic=True)
    act('Walk', 48, walk_pose, cyclic=True)
    act('PlaceItem', 60, place_pose, cyclic=False)
    act('Growl', 24, growl_pose, cyclic=False)
    act('StandUp', 50, standup_pose, cyclic=False)
    act('Run', 30, run_pose, cyclic=True)
    act('Bite', 24, bite_pose, cyclic=False)
    # Soul-drain sequence (Zach's design change: the attack is a dementor-style drain, not a
    # chase/bite -- Bite/Run above are kept, unused for this, so nothing else that still calls
    # them breaks). Naming contract shared with the brain-logic side on service-dog-brain.
    act('RearUp', 45, rear_up_pose, cyclic=False)
    act('DrainIdle', 120, drain_idle_pose, cyclic=True)
    act('UprightWalk', 64, upright_walk_pose, cyclic=True)
    act('DropDown', 24, drop_down_pose, cyclic=False)
    arm.animation_data.action = bpy.data.actions['Idle']
    return poser
