extends RefCounted
## BETTER HANDS: closes a first-person hand round a held model so it looks gripped, not clipped.
##
## The model's surface is sampled into points in the hand's socket space; the palm pushes the model
## out along +Y until nothing is inside it; then every finger curls from open toward its target
## shape a step at a time, and a bone that touches the surface stops (with the joints before it),
## while the bones after it keep closing -- so fingers wrap a handle, cup a box's edge, or lie flat
## under a tray. The thumb swings in (opposition), then bends the same way.
##
## This is slow (GDScript, thousands of points), so it runs offline: tools/gripbake.gd solves every
## holdable kind and writes scripts/hands/grip_bake.gd, and the game only reads that. docs/CONTRACTS.md
## "Player: hands".

const Arms := preload("res://scripts/hands/fp_arms.gd")

## Gap kept between a bone and the surface (rig units, metres before HAND_SCALE).
const MARGIN := 0.0012
const STEPS := 36
## The palm's box in rig space (the rounded slab's footprint), for the push.
const PALM_MIN := Vector3(-0.037, -0.03, -0.05)
const PALM_MAX := Vector3(0.037, 0.0, 0.044)


## Surface points of every mesh under `root`, mapped by `xf` (root space -> target space), sampled
## every `step` metres, keeping only those inside `keep` (target space).
static func surface_points(root: Node3D, xf: Transform3D, keep: AABB, step: float) -> PackedVector3Array:
	var out := PackedVector3Array()
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null or not mi.visible:
			continue
		var t := Transform3D()
		var p: Node = mi
		while p != null and p != root:
			if p is Node3D:
				t = (p as Node3D).transform * t
			p = p.get_parent()
		t = xf * t
		for s in mi.mesh.get_surface_count():
			var arr := mi.mesh.surface_get_arrays(s)
			var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			var tri_n := idx.size() / 3 if idx.size() > 0 else verts.size() / 3
			var tv := PackedVector3Array()
			tv.resize(verts.size())
			for i in verts.size():
				tv[i] = t * verts[i]
			for ti in tri_n:
				var a: Vector3 = tv[idx[ti * 3] if idx.size() > 0 else ti * 3]
				var b: Vector3 = tv[idx[ti * 3 + 1] if idx.size() > 0 else ti * 3 + 1]
				var c: Vector3 = tv[idx[ti * 3 + 2] if idx.size() > 0 else ti * 3 + 2]
				var box := AABB(a, Vector3.ZERO).expand(b).expand(c)
				if not box.grow(0.001).intersects(keep):
					continue
				var edge := maxf(a.distance_to(b), maxf(b.distance_to(c), c.distance_to(a)))
				var m := clampi(int(ceil(edge / step)), 1, 48)
				for i in m + 1:
					for j in m + 1 - i:
						var u := float(i) / m
						var v := float(j) / m
						var q := a + (b - a) * u + (c - a) * v
						if keep.has_point(q):
							out.append(q)
	return out


## Everything a solve returns: {push (socket units, along +Y), shape, clip (points still inside a
## bone or the palm after solving), start_clip (inside at the open pose: a placement problem)}.
## `pts` are in SOCKET space; `target` is the shape the hand would close to with nothing in it.
static func solve(pts: PackedVector3Array, target: Dictionary, side: float, push_palm := true, open := Arms.SHAPE_OPEN, push_reach := PALM_MIN.z) -> Dictionary:
	var k := Arms.HAND_SCALE
	var rig := PackedVector3Array()
	rig.resize(pts.size())
	for i in pts.size():
		rig[i] = pts[i] / k
	# ---- the palm pushes the model out of itself (only what is over the palm and not far behind it)
	var push := 0.0
	if push_palm:
		for q in rig:
			if q.x > PALM_MIN.x and q.x < PALM_MAX.x and q.z > push_reach and q.z < PALM_MAX.z and q.y > -0.06 and q.y < 0.0015:
				push = maxf(push, 0.0015 - q.y)
		if push > 0.0:
			for i in rig.size():
				rig[i] += Vector3(0.0, push, 0.0)
	# Only points a finger could reach are worth testing.
	var near := PackedVector3Array()
	for q in rig:
		if q.y > -0.05 and q.length() < 0.2:
			near.append(q)
	var shape := {"f": [], "t": [0.0, 0.0, 0.0, 0.0]}
	var start_clip := 0
	for i in 4:
		var r := _curl_finger(near, i, open.f[i], target.f[i], side)
		shape.f.append(r[0])
		start_clip += int(r[1])
	var tr := _curl_thumb(near, open.t, target.t, side, shape)
	shape.t = tr[0]
	start_clip += int(tr[1])
	return {"push": push * k, "shape": shape, "clip": clip_count(near, shape, side), "start_clip": start_clip}


## How many points sit inside a bone (rig space).
static func clip_count(rig_pts: PackedVector3Array, shape: Dictionary, side: float) -> int:
	var n := 0
	var segs := Arms.chain(shape, side)
	for q in rig_pts:
		for s in segs:
			if _seg_dist(q, s[0], s[1]) < float(s[2]) - 0.0015:
				n += 1
				break
	return n


static func _curl_finger(pts: PackedVector3Array, i: int, open: Array, target: Array, side: float) -> Array:
	var a := [float(open[0]), float(open[1]), float(open[2])]
	var frozen := [false, false, false]
	var start := _finger_hit(pts, i, a, side)
	# Already touching at the open pose (a thing lying over the fingers): straighten, even bend back a
	# little, until clear.
	var back := 0
	while start >= 0 and back < 10:
		back += 1
		for j in 3:
			a[j] = float(open[j]) - 0.03 * back
		start = _finger_hit(pts, i, a, side)
	open = a.duplicate()
	for step in STEPS:
		var t := float(step + 1) / STEPS
		var prev := a.duplicate()
		for j in 3:
			if not frozen[j]:
				a[j] = lerpf(float(open[j]), float(target[j]), t)
		var hit := _finger_hit(pts, i, a, side)
		# A bone that was already inside the model at the open pose does not stop the curl (the
		# placement is at fault there, and clip_count reports it).
		if hit >= 0 and hit != start:
			for j in hit + 1:
				a[j] = prev[j]
				frozen[j] = true
			# The bones after the one that touched keep closing from where they are.
		if frozen[2]:
			break
	return [a, 1 if start >= 0 else 0]


## The first bone (0..2) of finger i that touches a point, or -1.
static func _finger_hit(pts: PackedVector3Array, i: int, a: Array, side: float) -> int:
	var fd: Dictionary = Arms.FINGERS[i]
	var x := Transform3D(Arms._finger_basis(i, float(a[0]), side), Vector3(side * float(fd.x), Arms.FINGER_Y, float(fd.z)))
	for j in 3:
		if j > 0:
			x = x * Transform3D(Basis(Vector3.RIGHT, float(a[j])), Vector3(0.0, 0.0, -float(fd.l[j - 1])))
		var from := x.origin
		var to := x * Vector3(0.0, 0.0, -float(fd.l[j]))
		var r := float(fd.r) * (1.0 - 0.06 * j) + MARGIN
		for q in pts:
			if _seg_dist(q, from, to) < r:
				return j
	return -1


static func _curl_thumb(pts: PackedVector3Array, open: Array, target: Array, side: float, hand: Dictionary) -> Array:
	var t := [float(open[0]), float(open[1]), float(open[2]), float(open[3])]
	var start := _thumb_hit(pts, t, side, hand)
	# Swing in first (opposition and the base bend together), then close the two phalanges.
	for step in STEPS:
		var u := float(step + 1) / STEPS
		var prev := t.duplicate()
		t[0] = lerpf(float(open[0]), float(target[0]), u)
		t[1] = lerpf(float(open[1]), float(target[1]), u)
		var hit := _thumb_hit(pts, t, side, hand)
		if hit >= 0 and hit != start:
			t = prev
			break
	var frozen := [false, false]
	for step in STEPS:
		var u := float(step + 1) / STEPS
		var prev := t.duplicate()
		for j in 2:
			if not frozen[j]:
				t[j + 2] = lerpf(float(open[j + 2]), float(target[j + 2]), u)
		var hit := _thumb_hit(pts, t, side, hand)
		if hit >= 1 and hit != start:
			for j in hit:
				t[j + 2] = prev[j + 2]
				frozen[j] = true
		elif hit == 0 and hit != start:
			t = prev
			break
		if frozen[1]:
			break
	return [t, 1 if start >= 0 else 0]


## The first thumb bone touching a point (or the index finger's bones, so the thumb stops on the
## finger it closes over instead of sinking through it), or -1.
static func _thumb_hit(pts: PackedVector3Array, t: Array, side: float, hand: Dictionary) -> int:
	var tx := Transform3D(Arms.thumb_basis(float(t[0]), float(t[1]), side), Vector3(side * Arms.THUMB_ROOT.x, Arms.THUMB_ROOT.y, Arms.THUMB_ROOT.z))
	var fingers: Array = []
	if not hand.f.is_empty():
		var shape := {"f": hand.f, "t": [0.0, 0.0, 0.0, 0.0]}
		for s in Arms.chain(shape, side):
			if int(s[3]) < 2 and int(s[4]) >= 1:
				fingers.append(s)
	for j in 3:
		if j > 0:
			tx = tx * Transform3D(Basis(Vector3.RIGHT, float(t[j + 1])), Vector3(0.0, 0.0, -float(Arms.THUMB_L[j - 1])))
		var from := tx.origin
		var to := tx * Vector3(0.0, 0.0, -float(Arms.THUMB_L[j]))
		var r := float(Arms.THUMB_R[j]) + MARGIN
		for q in pts:
			if _seg_dist(q, from, to) < r:
				return j
		if j >= 1:
			for s in fingers:
				if _seg_seg_dist(from, to, s[0], s[1]) < r + float(s[2]):
					return j
	return -1


static func _seg_dist(q: Vector3, a: Vector3, b: Vector3) -> float:
	var ab := b - a
	var u := clampf((q - a).dot(ab) / maxf(ab.length_squared(), 1e-9), 0.0, 1.0)
	return q.distance_to(a + ab * u)


static func _seg_seg_dist(a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> float:
	var pts := Geometry3D.get_closest_points_between_segments(a, b, c, d)
	return (pts[0] as Vector3).distance_to(pts[1])
