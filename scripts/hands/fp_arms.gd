extends RefCounted
## The first-person forearms and hands (docs/CONTRACTS.md "Player: hands", the arms seam).
##
## `make_arm(side, colour)` is the only builder the rest of the game calls: it returns a Node3D whose
## origin is the palm socket (scripts/hands/grips.gd axes: -Z fingers, +Y out of the palm, +X the
## hand's right) with the wrist and a scrub sleeve running back along +Z toward the elbow.
##
## BETTER HANDS (2026-09-24): a gloved surgical hand -- a rounded palm, four fingers of three
## phalanges each and a three-bone thumb, every bone its own pivot so the hand can close round what
## it holds. A hand's pose is a "shape" {f: [[knuckle, middle, tip] x index, middle, ring, pinky],
## t: [opposition 0..1, base, middle, tip]} in radians (apply()); `chain()` gives the same bones as
## capsules in rig space, which is what scripts/hands/grip_solver.gd curls against a held model so
## the fingers stop on its surface instead of going through it. Nodes: Rig/F0..F3 (each with J1/J2),
## Rig/Thumb (T1/T2); `set_curl(c)` still closes the whole hand from one number.

const ItemModelsScript := preload("res://scripts/item_models.gd")

## Radians of the old single-number curl at 1 (a fist). Kept for callers that still pass one.
const CURL_MAX := 1.55
## The glove: pale surgical nitrile.
const GLOVE := Color("7d9dbc")
const SKIN := GLOVE   # the name older code (warmup, tests) reads
## Drawn size of the hand and forearm against a real one.
const HAND_SCALE := 0.84

## Fingers of the RIGHT hand (the left mirrors x): knuckle x and z (the index sits on the thumb's
## side, +X), phalanx lengths, radius and splay (radians about Y, outward from the middle finger).
const FINGERS := [
	{"x": 0.0262, "z": -0.046, "l": [0.041, 0.025, 0.021], "r": 0.0093, "s": 0.07},
	{"x": 0.0085, "z": -0.049, "l": [0.045, 0.028, 0.022], "r": 0.0097, "s": 0.0},
	{"x": -0.0092, "z": -0.047, "l": [0.042, 0.027, 0.021], "r": 0.0092, "s": -0.06},
	{"x": -0.0258, "z": -0.042, "l": [0.034, 0.021, 0.019], "r": 0.0082, "s": -0.13},
]
## Knuckle height (the fingers' centre line, half way through the palm).
const FINGER_Y := -0.0125
## The palm: a rounded slab from the wrist to the knuckles, its front face on y = 0.
const PALM_SIZE := Vector3(0.078, 0.025, 0.094)
const PALM_CENTRE := Vector3(0.0, -0.0125, -0.003)
## The thumb (right hand): its root at the heel of the hand, then the metacarpal (the ball of the
## thumb), the first and the last phalanx.
const THUMB_ROOT := Vector3(0.024, -0.016, 0.03)
const THUMB_L := [0.037, 0.028, 0.023]
const THUMB_R := [0.0125, 0.0106, 0.0098]
## Root orientation (yaw about Y, pitch about X, roll about Z; right hand) at opposition 0 (lying
## beside the palm, pointing forward and out) and 1 (swung in across the palm, over what it holds).
const THUMB_OPEN := Vector3(0.28, -0.62, 0.95)
const THUMB_OPPOSED := Vector3(0.62, 0.28, 1.25)

## The wrist pivot (rig space): the forearm, cuff and sleeve turn about it.
const WRIST := Vector3(0.0, -0.014, 0.05)
## How far the wrist bends (radians).
const WRIST_MAX := 1.0

## Shapes (see the header).
const SHAPE_OPEN := {"f": [[0.08, 0.08, 0.05], [0.08, 0.08, 0.05], [0.1, 0.1, 0.06], [0.12, 0.12, 0.08]], "t": [0.0, 0.0, 0.05, 0.05]}
const SHAPE_FIST := {"f": [[1.45, 1.65, 0.95], [1.45, 1.7, 0.95], [1.45, 1.7, 0.95], [1.45, 1.65, 0.9]], "t": [0.85, 0.2, 0.55, 0.45]}

static var _mesh_cache := {}   # key -> Mesh
static var _mats := {}


static func make_arm(side: float, colour: Color) -> Node3D:
	var root := Node3D.new()
	root.name = "Arm" + ("R" if side > 0.0 else "L")
	# Everything is built at a real hand's size and drawn a little smaller (HAND_SCALE): at arm's
	# length in front of the camera a true-size hand fills too much of the view. The socket (the
	# root's origin) stays where the palm is.
	var rig := Node3D.new()
	rig.name = "Rig"
	rig.scale = Vector3.ONE * HAND_SCALE
	root.add_child(rig)
	var body := MeshInstance3D.new()
	body.name = "Palm"
	body.mesh = _hand_mesh(side)
	rig.add_child(body)
	# The forearm bends at the wrist (fp_hands aims it at an elbow below the camera), so a fist can
	# point its handle anywhere without the sleeve swinging across the view.
	var fore := Node3D.new()
	fore.name = "Forearm"
	fore.position = WRIST
	rig.add_child(fore)
	var cuff := MeshInstance3D.new()
	cuff.name = "Cuff"
	cuff.mesh = _cuff_mesh()
	cuff.position = -WRIST
	fore.add_child(cuff)
	var sleeve := MeshInstance3D.new()
	sleeve.name = "Sleeve"
	sleeve.mesh = _sleeve_mesh(colour)
	sleeve.position = -WRIST
	fore.add_child(sleeve)
	for i in FINGERS.size():
		var fd: Dictionary = FINGERS[i]
		var parent: Node3D = rig
		for j in 3:
			var joint := Node3D.new()
			joint.name = ("F%d" % i) if j == 0 else ("J%d" % j)
			if j == 0:
				joint.position = Vector3(side * float(fd.x), FINGER_Y, float(fd.z))
			else:
				joint.position = Vector3(0.0, 0.0, -float(fd.l[j - 1]))
			parent.add_child(joint)
			var seg := MeshInstance3D.new()
			seg.name = "Bone"
			seg.mesh = _bone_mesh(float(fd.r) * (1.0 - 0.06 * j), float(fd.l[j]))
			joint.add_child(seg)
			parent = joint
	var thumb := Node3D.new()
	thumb.name = "Thumb"
	thumb.position = Vector3(side * THUMB_ROOT.x, THUMB_ROOT.y, THUMB_ROOT.z)
	rig.add_child(thumb)
	var tp: Node3D = thumb
	for j in 3:
		var node: Node3D = tp
		if j > 0:
			node = Node3D.new()
			node.name = "T%d" % j
			node.position = Vector3(0.0, 0.0, -float(THUMB_L[j - 1]))
			tp.add_child(node)
		var seg := MeshInstance3D.new()
		seg.name = "Bone"
		seg.mesh = _bone_mesh(float(THUMB_R[j]), float(THUMB_L[j]))
		node.add_child(seg)
		tp = node
	apply(root, shape_from_curl(0.2), side)
	return root


# -------------------------------------------------------------------------------------------- posing

## 0 open .. 1 closed, the whole hand at once (empty hands, the shove, older callers).
static func set_curl(arm: Node3D, curl: float, side: float) -> void:
	apply(arm, shape_from_curl(curl), side)


static func shape_from_curl(curl: float) -> Dictionary:
	return blend_shapes(SHAPE_OPEN, SHAPE_FIST, clampf(curl, 0.0, 1.0))


static func blend_shapes(a: Dictionary, b: Dictionary, u: float) -> Dictionary:
	var f: Array = []
	for i in 4:
		var row: Array = []
		for j in 3:
			row.append(lerpf(float(a.f[i][j]), float(b.f[i][j]), u))
		f.append(row)
	var t: Array = []
	for j in 4:
		t.append(lerpf(float(a.t[j]), float(b.t[j]), u))
	return {"f": f, "t": t}


## Pose every bone of an arm made by make_arm.
static func apply(arm: Node3D, shape: Dictionary, side: float) -> void:
	var rig := arm.get_node_or_null("Rig")
	if rig == null:
		return
	for i in 4:
		var k := rig.get_node_or_null("F%d" % i) as Node3D
		if k == null:
			continue
		var a: Array = shape.f[i]
		k.basis = _finger_basis(i, float(a[0]), side)
		var j1 := k.get_node("J1") as Node3D
		j1.basis = Basis(Vector3.RIGHT, float(a[1]))
		(j1.get_node("J2") as Node3D).basis = Basis(Vector3.RIGHT, float(a[2]))
	var th := rig.get_node_or_null("Thumb") as Node3D
	if th != null:
		var t: Array = shape.t
		th.basis = thumb_basis(float(t[0]), float(t[1]), side)
		var t1 := th.get_node("T1") as Node3D
		t1.basis = Basis(Vector3.RIGHT, float(t[2]))
		(t1.get_node("T2") as Node3D).basis = Basis(Vector3.RIGHT, float(t[3]))


static func _finger_basis(i: int, bend: float, side: float) -> Basis:
	# Spread a little less as the hand closes, so a fist's fingers lie side by side.
	var splay := float(FINGERS[i].s) * side * clampf(1.0 - bend / 1.6, 0.25, 1.0)
	return Basis(Vector3.UP, splay) * Basis(Vector3.RIGHT, bend)


static func thumb_basis(oppose: float, flex: float, side: float) -> Basis:
	var e := THUMB_OPEN.lerp(THUMB_OPPOSED, clampf(oppose, 0.0, 1.0))
	return Basis(Vector3.UP, -side * e.x) * Basis(Vector3.RIGHT, e.y + flex) * Basis(Vector3.BACK, side * e.z)


## Every bone of a hand in `shape`, as capsules in RIG space (before HAND_SCALE):
## [[from, to, radius, finger 0..4 (4 the thumb), joint 0..2], ...]. Built from the same numbers
## as the nodes apply() poses, so the solver and the drawn hand always agree.
static func chain(shape: Dictionary, side: float) -> Array:
	var out: Array = []
	for i in 4:
		var fd: Dictionary = FINGERS[i]
		var a: Array = shape.f[i]
		var x := Transform3D(_finger_basis(i, float(a[0]), side), Vector3(side * float(fd.x), FINGER_Y, float(fd.z)))
		for j in 3:
			if j > 0:
				x = x * Transform3D(Basis(Vector3.RIGHT, float(a[j])), Vector3(0.0, 0.0, -float(fd.l[j - 1])))
			out.append([x.origin, x * Vector3(0.0, 0.0, -float(fd.l[j])), float(fd.r) * (1.0 - 0.06 * j), i, j])
	var t: Array = shape.t
	var tx := Transform3D(thumb_basis(float(t[0]), float(t[1]), side), Vector3(side * THUMB_ROOT.x, THUMB_ROOT.y, THUMB_ROOT.z))
	for j in 3:
		if j > 0:
			tx = tx * Transform3D(Basis(Vector3.RIGHT, float(t[j + 1])), Vector3(0.0, 0.0, -float(THUMB_L[j - 1])))
		out.append([tx.origin, tx * Vector3(0.0, 0.0, -float(THUMB_L[j])), float(THUMB_R[j]), 4, j])
	return out


# -------------------------------------------------------------------------------------------- meshes

static func _mat(key: String, col: Color, rough: float) -> StandardMaterial3D:
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = rough
	m.resource_name = "fp_arms_" + key
	_mats[key] = m
	return m


static func glove_material() -> StandardMaterial3D:
	if _mats.has("glove"):
		return _mats["glove"]
	var m := _mat("glove", GLOVE, 0.42)
	# A soft rim so the fingers read against a dark corridor (the flashlight never lights the hands).
	m.rim_enabled = true
	m.rim = 0.2
	m.rim_tint = 0.4
	return m


## One phalanx: a capsule from the joint (origin) to -Z `length`, its round ends overlapping the
## next bone's so a bent finger has no gap at the knuckle.
static func _bone_mesh(r: float, length: float) -> Mesh:
	var key := "bone|%.4f|%.4f" % [r, length]
	if _mesh_cache.has(key):
		return _mesh_cache[key]
	var c := CapsuleMesh.new()
	c.radius = r
	c.height = length + 2.0 * r
	c.radial_segments = 8
	c.rings = 2
	var mesh := ItemModelsScript.merge_parts([[c, 0, Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0.0, 0.0, -length * 0.5)), glove_material()]], 100000)
	mesh.resource_name = "fp_bone"
	_mesh_cache[key] = mesh
	return mesh


## The palm (a rounded slab a little narrower at the wrist), the wrist and the glove's cuff.
static func _hand_mesh(side: float) -> Mesh:
	var key := "hand|%d" % int(side)
	if _mesh_cache.has(key):
		return _mesh_cache[key]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_rounded_slab(st, PALM_CENTRE, PALM_SIZE, 0.42, 0.86)
	# The heel of the hand into the wrist, round enough that a bent wrist shows no seam.
	_rounded_slab(st, Vector3(0.0, -0.0135, 0.05), Vector3(0.056, 0.04, 0.05), 0.8, 1.0)
	st.generate_normals()
	var mesh := st.commit()
	mesh.surface_set_material(0, glove_material())
	mesh.resource_name = "fp_palm"
	_mesh_cache[key] = mesh
	return mesh


## The wrist and the glove's cuff, in rig space from the wrist back (moved with the forearm).
static func _cuff_mesh() -> Mesh:
	if _mesh_cache.has("cuff"):
		return _mesh_cache["cuff"]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Wrist: a flattened tube back into the cuff.
	_tube(st, Vector3(0.0, -0.0135, 0.05), Vector3(0.0, -0.015, 0.1), Vector2(0.028, 0.0195), Vector2(0.029, 0.021), 10)
	# The cuff: a rolled band, flared over the sleeve.
	_tube(st, Vector3(0.0, -0.016, 0.088), Vector3(0.0, -0.018, 0.128), Vector2(0.033, 0.026), Vector2(0.041, 0.034), 10)
	st.generate_normals()
	var mesh := st.commit()
	mesh.surface_set_material(0, glove_material())
	mesh.resource_name = "fp_cuff"
	_mesh_cache["cuff"] = mesh
	return mesh


## Bend the wrist so the forearm runs toward `dir` (socket space, from the wrist toward the elbow),
## at most WRIST_MAX away from straight.
static func aim_forearm(arm: Node3D, dir: Vector3) -> void:
	var fore := arm.get_node_or_null("Rig/Forearm") as Node3D
	if fore == null or dir.length_squared() < 1e-6:
		return
	var d := dir.normalized()
	var ang := Vector3.BACK.angle_to(d)
	if ang < 0.001:
		fore.basis = Basis()
		return
	var axis := Vector3.BACK.cross(d)
	if axis.length_squared() < 1e-8:
		fore.basis = Basis()
		return
	fore.basis = Basis(axis.normalized(), minf(ang, WRIST_MAX))


## A superellipsoid (a box with well-rounded edges): `k` < 1 squares it off; x shrinks to `taper`
## at the back (+Z) end.
static func _rounded_slab(st: SurfaceTool, centre: Vector3, size: Vector3, k: float, taper: float) -> void:
	var rings := 8
	var segs := 14
	var verts: Array = []
	for r in rings + 1:
		var v := PI * r / rings
		var row: Array = []
		for s in segs + 1:
			var u := TAU * s / segs
			var d := Vector3(sin(v) * cos(u), cos(v), sin(v) * sin(u))
			var p := Vector3(_spow(d.x, k), _spow(d.y, k), _spow(d.z, k)) * size * 0.5
			p.x *= lerpf(1.0, taper, clampf((p.z / size.z) + 0.5, 0.0, 1.0))
			row.append(centre + p)
		verts.append(row)
	for r in rings:
		for s in segs:
			var a: Vector3 = verts[r][s]
			var b: Vector3 = verts[r][s + 1]
			var c: Vector3 = verts[r + 1][s]
			var d2: Vector3 = verts[r + 1][s + 1]
			for p in [a, b, c, b, d2, c]:
				st.add_vertex(p)


static func _spow(x: float, k: float) -> float:
	return signf(x) * pow(absf(x), k)


## An elliptical tube from `a` to `b` (both roughly along Z), radii (x, y) at each end.
static func _tube(st: SurfaceTool, a: Vector3, b: Vector3, ra: Vector2, rb: Vector2, n: int) -> void:
	for i in n:
		var u0 := TAU * i / n
		var u1 := TAU * (i + 1) / n
		var p00 := a + Vector3(cos(u0) * ra.x, sin(u0) * ra.y, 0.0)
		var p01 := a + Vector3(cos(u1) * ra.x, sin(u1) * ra.y, 0.0)
		var p10 := b + Vector3(cos(u0) * rb.x, sin(u0) * rb.y, 0.0)
		var p11 := b + Vector3(cos(u1) * rb.x, sin(u1) * rb.y, 0.0)
		for p in [p00, p10, p01, p01, p10, p11]:
			st.add_vertex(p)


## CUSTOMIZATION: the sleeve for a given outfit colour, so fp_hands can swap it when the colour
## changes at the mirror (the mesh bakes the colour in, one cached mesh per colour).
static func sleeve_mesh(colour: Color) -> ArrayMesh:
	return _sleeve_mesh(colour)


static func _sleeve_mesh(colour: Color) -> ArrayMesh:
	var key := "sleeve|%s" % colour.to_html(false)
	if _mesh_cache.has(key):
		return _mesh_cache[key]
	var cloth := _mat("sleeve_" + colour.to_html(false), colour.darkened(0.12), 0.95)
	var cuff := _mat("cuff_" + colour.to_html(false), colour.darkened(0.3), 0.95)
	var parts: Array = []
	var along_z := Basis(Vector3.RIGHT, PI * 0.5)
	var sleeve := CylinderMesh.new()
	sleeve.top_radius = 0.043    # +Y of the cylinder is toward the wrist after the turn below
	sleeve.bottom_radius = 0.058
	sleeve.height = 0.36
	sleeve.radial_segments = 10
	sleeve.rings = 1
	# Rotated so its top points at -Z (the wrist), centred behind the cuff.
	parts.append([sleeve, 0, Transform3D(Basis(Vector3.RIGHT, -PI * 0.5).scaled(Vector3(1.15, 1.0, 1.0)), Vector3(0.0, -0.02, 0.3)), cloth])
	var band := CylinderMesh.new()
	band.top_radius = 0.046
	band.bottom_radius = 0.046
	band.height = 0.025
	band.radial_segments = 10
	band.rings = 1
	parts.append([band, 0, Transform3D(along_z.scaled(Vector3(1.15, 1.0, 1.0)), Vector3(0.0, -0.02, 0.13)), cuff])
	var mesh := ItemModelsScript.merge_parts(parts, 100000)
	_mesh_cache[key] = mesh
	return mesh


# -------------------------------------------------------------------------------------------- torch

## The torch the right hand holds: its lens at -Z, the handle centred on the origin.
static func make_torch() -> Node3D:
	var root := Node3D.new()
	root.name = "Torch"
	var metal := _mat("torch_metal", Color("2a2c30"), 0.4)
	metal.metallic = 0.6
	var parts: Array = []
	var along_z := Basis(Vector3.RIGHT, PI * 0.5)
	var body := CylinderMesh.new()
	body.top_radius = 0.021
	body.bottom_radius = 0.021
	body.height = 0.2
	body.radial_segments = 10
	body.rings = 1
	parts.append([body, 0, Transform3D(along_z, Vector3(0.0, 0.0, -0.01)), metal])
	var head := CylinderMesh.new()
	head.top_radius = 0.022
	head.bottom_radius = 0.031
	head.height = 0.05
	head.radial_segments = 10
	head.rings = 1
	parts.append([head, 0, Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(0.0, 0.0, -0.125)), metal])
	var mi := MeshInstance3D.new()
	mi.mesh = ItemModelsScript.merge_parts(parts, 100000)
	root.add_child(mi)
	var lens := MeshInstance3D.new()
	var lm := CylinderMesh.new()
	lm.top_radius = 0.027
	lm.bottom_radius = 0.027
	lm.height = 0.004
	lm.radial_segments = 10
	lm.rings = 1
	lens.mesh = lm
	lens.material_override = lens_material(true)
	lens.transform = Transform3D(along_z, Vector3(0.0, 0.0, -0.151))
	lens.name = "Lens"
	root.add_child(lens)
	return root


## The torch lens lit (warm glow) or off (dark glass). scan_fx.gd swaps in its own blue while scanning.
static func lens_material(lit: bool) -> StandardMaterial3D:
	if lit:
		if _mats.has("torch_lens"):
			return _mats["torch_lens"]
		var glow := _mat("torch_lens", Color(1.0, 0.92, 0.75), 0.2)
		glow.emission_enabled = true
		glow.emission = Color(1.0, 0.86, 0.62)
		glow.emission_energy_multiplier = 2.2
		return glow
	return _mat("torch_lens_off", Color(0.16, 0.16, 0.15), 0.12)
