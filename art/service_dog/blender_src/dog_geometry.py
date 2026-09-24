"""Service Dog geometry: a from-scratch procedural quadruped body, built as ring lofts in pure
Python + mathutils, no third-party assets. See art/service_dog/README.md for the design brief
(a borzoi/sighthound pushed taller, gaunter and wrong: sunken blank eye sockets, a wet muzzle,
hoof-like paws, a thin whip tail) and `art/night_nurse/blender_src/nn_geometry.py` /
`art/seal/blender_src/seal_geometry.py` for the sibling conventions this follows.

Frame: authored in Blender's own Z-up axes (X left/right, Y forward/back, Z up), exactly like
`nn_geometry.py` and `seal_geometry.py` -- e.g. NECK2.z is a height, NECK2.y is how far forward of
the root it sits. `--export` writes glTF Y-up (`export_yup=True`), which is what turns this into
the +Z-forward, y-is-height frame `assets.gd` registers (yaw 180) and every monster GLB in this
project uses; nothing here has to think about that conversion. Standing on z = 0 (Blender) / y = 0
(game), root under the animal midway between the front and hind legs.
"""
import math
from mathutils import Vector

TAU = math.tau
SCALE = 1.0

# ---------------------------------------------------------------------------
# Landmarks (metres, Blender Z-up: X side, Y forward, Z height). Shared by dog_rig.py so the
# skeleton and the mesh always agree. Exaggerated past a real borzoi: shoulder height 1.0 m (a real
# borzoi is about 0.75 m), legs pushed long and thin, the skull elongated and narrow.
PELVIS = Vector((0.0, -0.34, 1.00))
SPINE1 = Vector((0.0, -0.06, 1.03))
CHEST = Vector((0.0, 0.20, 1.06))
NECK1 = Vector((0.0, 0.42, 1.10))
NECK2 = Vector((0.0, 0.58, 1.27))
HEAD = Vector((0.0, 0.72, 1.43))
SKULL_MID = Vector((0.0, 0.92, 1.43))
HEAD_TIP = Vector((0.0, 1.14, 1.37))
JAW_MID = Vector((0.0, 0.92, 1.33))
JAW_TIP = Vector((0.0, 1.12, 1.30))
RUMP = PELVIS + Vector((0.0, -0.14, -0.02))

SHOULDER = Vector((0.135, 0.24, 0.98))
ELBOW = Vector((0.150, 0.20, 0.56))
WRIST = Vector((0.140, 0.17, 0.20))
FPAW = Vector((0.135, 0.145, 0.0))
FTOE = Vector((0.135, 0.21, -0.03))

HIP = Vector((0.125, -0.40, 0.97))
KNEE = Vector((0.175, -0.30, 0.58))
HOCK = Vector((0.130, -0.12, 0.22))
HPAW = Vector((0.130, -0.02, 0.0))
HTOE = Vector((0.130, 0.045, -0.03))

TAIL = [
    PELVIS + Vector((0.0, -0.10, 0.04)),
    PELVIS + Vector((0.0, -0.30, 0.10)),
    PELVIS + Vector((0.0, -0.50, 0.12)),
    PELVIS + Vector((0.0, -0.68, 0.08)),
    PELVIS + Vector((0.0, -0.82, 0.00)),
]

EAR_BASE = HEAD + Vector((0.045, -0.05, 0.10))
EAR_TIP = HEAD + Vector((0.075, -0.08, 0.26))

# Where the vest sits: a girth band round the chest and a back panel from the withers to the
# shoulders (skeleton space, used again by dog_rig for nothing but kept here for one source of truth).
VEST_GIRTH = CHEST + Vector((0.0, 0.0, -0.01))
VEST_BACK_FRONT = NECK1 + Vector((0.0, 0.0, 0.055))
VEST_BACK_REAR = SPINE1 + Vector((0.0, 0.0, 0.05))


def mirror(v):
    return Vector((-v.x, v.y, v.z))


def mirror_bone(name):
    if name.endswith('.L'):
        return name[:-2] + '.R'
    if name.endswith('.R'):
        return name[:-2] + '.L'
    return name


def smooth01(t):
    t = max(0.0, min(1.0, t))
    return t * t * (3.0 - 2.0 * t)


# ---------------------------------------------------------------------------
# Ring-loft helper. `radius_fn(i, theta) -> r` gives the polar radius (metres, in the ring's own
# (a, b) frame) of the loft at control point i and angle theta; supply per-ring ellipse axes with
# `ellipse_radius_fn` (below) or sculpt with your own function (the skull's eye sockets do this).

def ring_frame(tangent):
    t = tangent.normalized()
    ref = Vector((0.0, 0.0, 1.0))
    if abs(t.dot(ref)) > 0.9:
        ref = Vector((1.0, 0.0, 0.0))
    a = t.cross(ref).normalized()
    b = a.cross(t).normalized()
    return a, b


def _tangents(pts):
    n = len(pts)
    out = []
    for i in range(n):
        p0 = pts[i - 1] if i > 0 else pts[i]
        p1 = pts[i + 1] if i < n - 1 else pts[i]
        d = p1 - p0
        out.append(d if d.length > 1e-6 else Vector((0, 0, 1)))
    return out


def ellipse_radius_fn(rx_list, rz_list):
    def fn(i, theta):
        rx, rz = rx_list[i], rz_list[i]
        c, s = math.cos(theta), math.sin(theta)
        # Superellipse-free polar ellipse radius: r(theta) such that (r*c/rx)^2 + (r*s/rz)^2 = 1.
        denom = (c * c) / max(rx * rx, 1e-9) + (s * s) / max(rz * rz, 1e-9)
        return 1.0 / math.sqrt(max(denom, 1e-9))
    return fn


def loft_tube(centerline, radius_fn, nseg=10, cap_start=True, cap_end=True, twist=0.0):
    """Returns (verts: [Vector], faces: [tuple[int]], face_uvs: [[(u, v)]], rings: [[int]])."""
    tans = _tangents(centerline)
    verts = []
    uvs = {}
    rings = []
    n_rings = len(centerline)
    for i, c in enumerate(centerline):
        a, b = ring_frame(tans[i])
        ring = []
        base = len(verts)
        for k in range(nseg):
            th = TAU * k / nseg + twist
            r = radius_fn(i, th)
            verts.append(c + a * (r * math.cos(th)) + b * (r * math.sin(th)))
            idx = base + k
            ring.append(idx)
            uvs[idx] = (k / float(nseg), i / float(max(1, n_rings - 1)))
        rings.append(ring)
    faces = []
    face_uvs = []
    for i in range(len(rings) - 1):
        r0, r1 = rings[i], rings[i + 1]
        for k in range(nseg):
            k2 = (k + 1) % nseg
            faces.append((r0[k], r0[k2], r1[k2], r1[k]))
            face_uvs.append([uvs[r0[k]], (uvs[r0[k2]][0] + (1.0 if k2 == 0 else 0.0), uvs[r0[k2]][1]),
                             (uvs[r1[k2]][0] + (1.0 if k2 == 0 else 0.0), uvs[r1[k2]][1]), uvs[r1[k]]])
    if cap_start:
        tip = centerline[0] - tans[0].normalized() * 0.002
        verts.append(tip)
        cidx = len(verts) - 1
        uvs[cidx] = (0.5, 0.0)
        for k in range(nseg):
            k2 = (k + 1) % nseg
            faces.append((cidx, rings[0][k2], rings[0][k]))
            face_uvs.append([uvs[cidx], uvs[rings[0][k2]], uvs[rings[0][k]]])
    if cap_end:
        tip = centerline[-1] + tans[-1].normalized() * 0.002
        verts.append(tip)
        cidx = len(verts) - 1
        uvs[cidx] = (0.5, 1.0)
        for k in range(nseg):
            k2 = (k + 1) % nseg
            faces.append((cidx, rings[-1][k], rings[-1][k2]))
            face_uvs.append([uvs[cidx], uvs[rings[-1][k]], uvs[rings[-1][k2]]])
    return verts, faces, face_uvs, rings


def chain_weights(n, breaks):
    """breaks: [(index, bone_name), ...] increasing by index. Linear blend between consecutive
    breaks; before the first / after the last, that bone carries full weight."""
    out = []
    for i in range(n):
        prev, nxt = breaks[0], None
        for b in breaks:
            if b[0] <= i:
                prev = b
            if b[0] >= i and nxt is None:
                nxt = b
        if nxt is None:
            nxt = prev
        if prev[0] == nxt[0] or prev[1] == nxt[1]:
            out.append({prev[1]: 1.0})
        else:
            t = (i - prev[0]) / float(nxt[0] - prev[0])
            out.append({prev[1]: 1.0 - t, nxt[1]: t})
    return out


# ---------------------------------------------------------------------------
ATTRS = ['head', 'wet', 'stain']   # per-vertex float masks; dog_materials.py reads them to bake


class Part:
    """One mesh part: verts, quad/tri faces, per-vertex UV (cylindrical, packed later), a bone
    weight dict per vertex, and a material name ('coat' or 'vest')."""

    def __init__(self, name, mat='coat'):
        self.name = name
        self.mat = mat
        self.uv_boost = 1.0
        self.v = []
        self.f = []
        self.fuv = []
        self.w = []    # per-vertex {bone: weight}
        self.attr = {k: [] for k in ATTRS}   # per-vertex float masks the shader reads (below)
        self.face_mat = []   # per-face forced material index, or None to use the mask-average pick

    def add_tube(self, centerline, rx, rz, nseg, weights, cap_start=True, cap_end=True,
                 dip=None, uv_v_range=(0.0, 1.0)):
        def rfn(i, th):
            r = ellipse_radius_fn(rx, rz)(i, th)
            if dip is not None:
                r *= dip(i, th)
            return r
        verts, faces, face_uvs, rings = loft_tube(centerline, rfn, nseg=nseg, cap_start=cap_start, cap_end=cap_end)
        base = len(self.v)
        self.v += verts
        n_rings = len(centerline)
        n_ring_verts = n_rings * nseg
        for i in range(len(verts)):
            ring_i = min(i // nseg, n_rings - 1) if i < n_ring_verts else (0 if i == n_ring_verts else n_rings - 1)
            wd = weights[ring_i]
            self.w.append(dict(wd))
            headness = wd.get('head', 0.0) + wd.get('jaw', 0.0) + 0.5 * wd.get('neck2', 0.0) + 0.15 * wd.get('neck1', 0.0)
            self.attr['head'].append(min(1.0, headness))
            self.attr['wet'].append(max(0.0, min(1.0, (wd.get('jaw', 0.0) + wd.get('head', 0.0)) * 1.3 - 0.35)))
            self.attr['stain'].append(0.0)
        for face, fuv in zip(faces, face_uvs):
            self.f.append(tuple(base + idx for idx in face))
            self.fuv.append([(u, uv_v_range[0] + (uv_v_range[1] - uv_v_range[0]) * v) for u, v in fuv])
            self.face_mat.append(None)

    def add_patch(self, center, right, up, half_w, half_h, thickness, weight, mat_index):
        """A small raised rectangular patch (a thin box), for appliques like the vest's cross and
        badge: `center` on the surface, `right`/`up` its in-plane axes, offset outward along their
        cross product (the surface normal) by `thickness`. `mat_index` forces the material on
        every face of the patch, bypassing the usual per-face mask average."""
        right = right.normalized()
        up = up.normalized()
        normal = right.cross(up).normalized()
        base = len(self.v)
        corners = [center + right * sx * half_w + up * sy * half_h for sx in (-1.0, 1.0) for sy in (-1.0, 1.0)]
        self.v += corners
        self.v += [c + normal * thickness for c in corners]
        b0, b1, b2, b3 = base, base + 1, base + 2, base + 3
        t0, t1, t2, t3 = base + 4, base + 5, base + 6, base + 7
        faces = [(t0, t1, t3, t2), (b0, b2, b3, b1), (b0, b1, t1, t0), (b1, b3, t3, t1), (b3, b2, t2, t3), (b2, b0, t0, t2)]
        for f in faces:
            self.f.append(f)
            self.fuv.append([(0.0, 0.0)] * len(f))
            self.face_mat.append(mat_index)
        for _ in range(8):
            self.w.append(dict(weight))
            for k in ATTRS:
                self.attr[k].append(0.0)

    def tris(self):
        return sum(len(f) - 2 for f in self.f)


def _socket_dip(i, theta, sock_ring, sigma=0.9, depth=0.42, side_center=1.05, brow_boost=0.14):
    """Multiplier < 1 that carves a shallow, wide eye-socket dimple into a ring's radius on both
    sides, with a faint raised brow just above it (image refs 1/3/4: sunken, blank sockets)."""
    if i != sock_ring:
        return 1.0
    m = 1.0
    for sign in (1.0, -1.0):
        d = theta - sign * side_center
        d = (d + math.pi) % TAU - math.pi
        m -= depth * math.exp(-(d * d) / (2.0 * sigma * sigma))
        bd = theta - sign * (side_center - 0.65)
        bd = (bd + math.pi) % TAU - math.pi
        m += brow_boost * math.exp(-(bd * bd) / (2.0 * 0.35 * 0.35))
    return max(0.25, m)


# ---------------------------------------------------------------------------
def build_body(nseg=10, nseg_small=8):
    p = Part('Dog_Body', 'coat')

    # ---- spine: rump -> pelvis -> spine1 -> chest -> neck1 -> neck2 -> head base -------------
    spine_pts = [RUMP, PELVIS, SPINE1, CHEST, NECK1, NECK2, HEAD]
    spine_rx = [0.100, 0.092, 0.062, 0.072, 0.050, 0.040, 0.044]
    spine_rz = [0.125, 0.118, 0.082, 0.145, 0.062, 0.048, 0.052]
    breaks = [(0, 'pelvis'), (1, 'pelvis'), (2, 'spine1'), (3, 'chest'), (4, 'neck1'), (5, 'neck2'), (6, 'head')]
    w = chain_weights(len(spine_pts), breaks)
    p.add_tube(spine_pts, spine_rx, spine_rz, nseg, w, cap_start=True, cap_end=False, uv_v_range=(0.0, 0.5))

    # ---- skull: head base -> mid -> tip, with sunken eye sockets carved at the mid ring -------
    skull_pts = [HEAD, SKULL_MID, HEAD_TIP]
    skull_rx = [0.044, 0.034, 0.010]
    skull_rz = [0.050, 0.036, 0.012]
    w2 = [{'head': 1.0}, {'head': 1.0}, {'head': 1.0}]
    p.add_tube(skull_pts, skull_rx, skull_rz, nseg_small, w2, cap_start=False, cap_end=True,
               dip=lambda i, th: _socket_dip(i, th, sock_ring=1), uv_v_range=(0.5, 0.75))

    # ---- lower jaw: a thin loft from under the head to the jaw tip, hinged conceptually at 'jaw' -
    jaw_pts = [HEAD + Vector((0.0, 0.0, -0.036)), JAW_MID, JAW_TIP]
    jaw_rx = [0.034, 0.022, 0.007]
    jaw_rz = [0.030, 0.020, 0.007]
    w3 = [{'jaw': 1.0}] * 3
    p.add_tube(jaw_pts, jaw_rx, jaw_rz, nseg_small, w3, cap_start=False, cap_end=True, uv_v_range=(0.75, 0.85))

    # ---- ears: small flat cones, one bone each -------------------------------------------------
    for side, base, tip in (('L', EAR_BASE, EAR_TIP), ('R', mirror(EAR_BASE), mirror(EAR_TIP))):
        pts = [base, base.lerp(tip, 0.5), tip]
        rx = [0.028, 0.016, 0.002]
        rz = [0.010, 0.006, 0.001]
        w4 = [{'ear.' + side: 1.0}] * 3
        p.add_tube(pts, rx, rz, 6, w4, cap_start=True, cap_end=True, uv_v_range=(0.85, 0.9))

    # ---- tail: thin whip, four bones ------------------------------------------------------------
    tail_rx = [0.028, 0.020, 0.014, 0.008, 0.003]
    tail_rz = [0.028, 0.020, 0.014, 0.008, 0.003]
    tbreaks = [(0, 'tail1'), (1, 'tail1'), (2, 'tail2'), (3, 'tail3'), (4, 'tail4')]
    tw = chain_weights(len(TAIL), tbreaks)
    p.add_tube(TAIL, tail_rx, tail_rz, nseg_small, tw, cap_start=False, cap_end=True, uv_v_range=(0.9, 1.0))

    # ---- legs: front L/R, hind L/R ----------------------------------------------------------
    def leg(side, sign, shoulder, elbow, wrist, paw, toe, upper_bone, lower_bone, pastern_bone, toe_bone,
            r0=0.040, r1=0.026, r2=0.022, r3=0.020, r4=0.010):
        pts_upper = [shoulder, shoulder.lerp(elbow, 0.5), elbow]
        p.add_tube(pts_upper, [r0, (r0 + r1) * 0.5, r1], [r0, (r0 + r1) * 0.5, r1], nseg_small,
                   [{upper_bone: 1.0}, {upper_bone: 1.0}, {upper_bone: 0.6, lower_bone: 0.4}],
                   cap_start=True, cap_end=False, uv_v_range=(0.0, 0.3))
        pts_lower = [elbow, elbow.lerp(wrist, 0.5), wrist]
        p.add_tube(pts_lower, [r1, (r1 + r2) * 0.5, r2], [r1, (r1 + r2) * 0.5, r2], nseg_small,
                   [{lower_bone: 1.0}, {lower_bone: 1.0}, {lower_bone: 0.6, pastern_bone: 0.4}],
                   cap_start=False, cap_end=False, uv_v_range=(0.3, 0.55))
        pts_pastern = [wrist, paw]
        p.add_tube(pts_pastern, [r2, r3], [r2, r3], nseg_small,
                   [{pastern_bone: 1.0}, {pastern_bone: 0.5, toe_bone: 0.5}],
                   cap_start=False, cap_end=False, uv_v_range=(0.55, 0.7))
        # Hoof-like single paw: a short tapered point past the ankle (image ref 3).
        pts_toe = [paw, toe]
        p.add_tube(pts_toe, [r3, r4], [r3 * 0.9, r4 * 0.5], 6,
                   [{toe_bone: 1.0}, {toe_bone: 1.0}], cap_start=False, cap_end=True, uv_v_range=(0.7, 0.8))

    leg('L', 1.0, SHOULDER, ELBOW, WRIST, FPAW, FTOE, 'upperarm.L', 'forearm.L', 'pastern.L', 'toe.L')
    leg('R', -1.0, mirror(SHOULDER), mirror(ELBOW), mirror(WRIST), mirror(FPAW), mirror(FTOE),
        'upperarm.R', 'forearm.R', 'pastern.R', 'toe.R')
    leg('L', 1.0, HIP, KNEE, HOCK, HPAW, HTOE, 'thigh.L', 'shin.L', 'hock.L', 'htoe.L',
        r0=0.046, r1=0.028, r2=0.022, r3=0.020, r4=0.010)
    leg('R', -1.0, mirror(HIP), mirror(KNEE), mirror(HOCK), mirror(HPAW), mirror(HTOE),
        'thigh.R', 'shin.R', 'hock.R', 'htoe.R', r0=0.046, r1=0.028, r2=0.022, r3=0.020, r4=0.010)

    return p


# Material indices dog_materials.build_all() returns them in (must stay in sync with that list).
VEST_CROSS_MAT = 4
VEST_BADGE_MAT = 5

# The coat's own half-width/half-height along the torso (must match build_body's spine profile at
# these same landmarks), so the vest can hug it: a snug wrap is this profile plus a small constant
# margin, not an independently-sized shape. (y, rx, rz), y increasing toward the head.
_COAT_PROFILE = [
    (SPINE1.y, 0.062, 0.082),
    (SPINE1.y * 0.35 + CHEST.y * 0.65, 0.068, 0.118),
    (CHEST.y, 0.072, 0.145),
    (CHEST.y * 0.55 + NECK1.y * 0.45, 0.061, 0.104),
    (NECK1.y, 0.050, 0.062),
]


def _coat_radius(y):
    """Linear-interpolate the coat's own (rx, rz) at a given y from `_COAT_PROFILE`."""
    pts = _COAT_PROFILE
    if y <= pts[0][0]:
        return pts[0][1], pts[0][2]
    for i in range(len(pts) - 1):
        y0, rx0, rz0 = pts[i]
        y1, rx1, rz1 = pts[i + 1]
        if y <= y1:
            t = (y - y0) / (y1 - y0)
            return rx0 + (rx1 - rx0) * t, rz0 + (rz1 - rz0) * t
    return pts[-1][1], pts[-1][2]


def build_vest(nseg=16):
    """A real, clearly-readable service-dog vest that hugs the ribcage the way an actual
    harness-style service-dog vest does (Zach's reference photos: mesh/fabric conforming closely
    to the body, a girth strap under the belly, a chest strap in front, patches sewn flat onto the
    surface) rather than a panel standing proud of the coat. The vest BODY is a snug wrap: the same
    tube loft technique as the coat, at the coat's own radius (`_coat_radius`) plus a small
    constant margin (`MARGIN`), so it grows and shrinks with the torso instead of being its own
    independently-sized shape. The girth and chest straps are thin accents a hair proud of THAT
    surface, not of the bare coat. Zach has not signed off on clean vs. worn/dirty (see README);
    geometry-wise the base garment stays bold and legible and the wear mask (below) only ever
    touches a minority of it."""
    p = Part('Dog_Vest', 'vest')
    MARGIN = 0.011   # how far the fabric stands off the coat: snug, not a floating panel

    # Vest body: one continuous wrap from just behind the front legs to the base of the neck,
    # covering the ribcage the way the reference vests do (their mesh/fabric body, not just a
    # strip down the spine).
    ys = [SPINE1.y, SPINE1.y * 0.3 + CHEST.y * 0.7, CHEST.y, CHEST.y * 0.45 + NECK1.y * 0.55, NECK1.y - 0.02]
    rx_list, rz_list = [], []
    for y in ys:
        cx, cz = _coat_radius(y)
        rx_list.append(cx + MARGIN)
        rz_list.append(cz + MARGIN)
    # The loft's centreline sits at the torso's own height (CHEST.z) at every ring: the coat's
    # centreline is also flat in z along this stretch (the spine loft's height variation here is
    # small), so this is a close enough approximation without needing the full spine centreline.
    body_pts = [Vector((0.0, y, CHEST.z)) for y in ys]
    bw = [{'spine1': 0.7, 'chest': 0.3}, {'spine1': 0.3, 'chest': 0.7}, {'chest': 1.0},
          {'chest': 0.6, 'neck1': 0.4}, {'chest': 0.3, 'neck1': 0.7}]
    p.add_tube(body_pts, rx_list, rz_list, nseg, bw, cap_start=True, cap_end=True, uv_v_range=(0.0, 0.5))

    # Girth strap: a thin band a hair proud of the vest body (not the bare coat), under the belly
    # and round the sides -- the buckle strap visible in both reference photos.
    gy = CHEST.y * 0.7 + SPINE1.y * 0.3
    gcx, gcz = _coat_radius(gy)
    girth_pts = [Vector((0, gy - 0.018, CHEST.z)), Vector((0, gy, CHEST.z)), Vector((0, gy + 0.018, CHEST.z))]
    grx = [gcx + MARGIN + 0.007] * 3
    grz = [gcz + MARGIN + 0.007] * 3
    gw = [{'spine1': 0.4, 'chest': 0.6}] * 3
    p.add_tube(girth_pts, grx, grz, nseg, gw, cap_start=False, cap_end=False, uv_v_range=(0.5, 0.65))

    # Chest strap: a thin band from the top of the vest, down each side, to the girth strap in
    # front of the shoulder -- the second strap both reference vests show, tying the body down.
    top_y = CHEST.y * 0.5 + NECK1.y * 0.5
    top_cx, top_cz = _coat_radius(top_y)
    strap_top = Vector((0.0, top_y, CHEST.z + top_cz + MARGIN))
    strap_mid = Vector((0.0, CHEST.y, CHEST.z + _coat_radius(CHEST.y)[1] * 0.35))
    strap_bot = Vector((0.0, gy, CHEST.z - (gcz + MARGIN + 0.004)))
    for side in ('L', 'R'):
        sx = 1.0 if side == 'L' else -1.0
        pts = [strap_top + Vector((sx * top_cx * 0.55, 0, 0)),
               strap_mid + Vector((sx * _coat_radius(CHEST.y)[0] * 0.85, 0, 0)),
               strap_bot + Vector((sx * gcx * 0.5, 0, 0))]
        srx = [0.010, 0.010, 0.010]
        srz = [0.016, 0.016, 0.016]
        sw = [{'chest': 0.5, 'neck1': 0.5}, {'chest': 1.0}, {'chest': 0.6, 'spine1': 0.4}]
        p.add_tube(pts, srx, srz, 8, sw, cap_start=True, cap_end=True, uv_v_range=(0.65, 0.8))

    # First-aid iconography, sewn flush onto the vest body's own surface (image refs 5/6: patches
    # follow the vest's contour, they don't float above it) -- a red cross on top near the withers
    # and a small badge on the front-side face, both barely raised (thickness half what Revision 1
    # used, and centred exactly on the vest body's own radius at that point, not a fixed height).
    cross_y = CHEST.y * 0.6 + NECK1.y * 0.4
    ccx, ccz = _coat_radius(cross_y)
    cross_center = Vector((0.0, cross_y, CHEST.z + ccz + MARGIN))
    p.add_patch(cross_center, Vector((1, 0, 0)), Vector((0, 1, 0)), 0.040, 0.013, 0.004,
                {'chest': 0.5, 'neck1': 0.5}, VEST_CROSS_MAT)
    p.add_patch(cross_center, Vector((1, 0, 0)), Vector((0, 1, 0)), 0.013, 0.040, 0.004,
                {'chest': 0.5, 'neck1': 0.5}, VEST_CROSS_MAT)
    badge_y = CHEST.y - 0.03
    bcx, bcz = _coat_radius(badge_y)
    badge_normal = Vector((0.75, 0.0, 0.66)).normalized()   # forward-and-out, the vest's side face
    badge_right = Vector((0.0, 1.0, 0.0))
    badge_up = badge_normal.cross(badge_right).normalized()
    badge_center = Vector((bcx * 0.78, badge_y, CHEST.z + bcz * 0.35)) + badge_normal * MARGIN
    p.add_patch(badge_center, badge_right, badge_up, 0.026, 0.026, 0.004, {'chest': 1.0}, VEST_BADGE_MAT)

    # Deterministic wear mask, kept to a minority of the surface so the garment itself always
    # reads clearly first: dirtiest low on the girth strap (brushes the ground) and along the vest
    # body's rear edge (strap friction), with a touch of pseudo-noise (a sum of sines of the vertex
    # position -- no RNG, so it is stable across rebuilds) so it does not read as a flat gradient.
    # See README for the "worn" call.
    for i, v in enumerate(p.v):
        low = smooth01((CHEST.z - 0.08 - v.z) / 0.10)
        rear = smooth01((SPINE1.y + 0.05 - v.y) / 0.08)
        noise = 0.5 + 0.5 * math.sin(v.x * 53.0 + v.y * 91.0 + v.z * 37.0)
        p.attr['stain'][i] = max(0.0, min(1.0, 0.45 * low + 0.25 * rear + 0.20 * noise - 0.25))

    return p


def build_all(res=1):
    """res is accepted for parity with the seal/night_nurse convention (higher res = a bake
    source); the Service Dog does not bake a high-poly source (dog_materials.py is procedural
    only), so res has no effect yet. Returns (parts, joints) where joints mirrors the landmarks
    above for dog_rig.py."""
    body = build_body()
    vest = build_vest()
    joints = {
        'PELVIS': PELVIS, 'SPINE1': SPINE1, 'CHEST': CHEST, 'NECK1': NECK1, 'NECK2': NECK2,
        'HEAD': HEAD, 'HEAD_TIP': HEAD_TIP, 'JAW_TIP': JAW_TIP,
        'SHOULDER': SHOULDER, 'ELBOW': ELBOW, 'WRIST': WRIST, 'FPAW': FPAW, 'FTOE': FTOE,
        'HIP': HIP, 'KNEE': KNEE, 'HOCK': HOCK, 'HPAW': HPAW, 'HTOE': HTOE,
        'TAIL': TAIL, 'EAR_BASE': EAR_BASE, 'EAR_TIP': EAR_TIP,
    }
    return [body, vest], joints
