extends Node
## BETTER HANDS: solves every first-person grip and writes scripts/hands/grip_bake.gd.
##
##   godot --headless --path . res://tools/gripbake.tscn [-- --only=bone_saw,scalpel]
##
## Run it again after changing a model, a grip in scripts/hands/grips.gd (FP) or the hand in
## scripts/hands/fp_arms.gd. For each kind (and each bundle size it shows) it places the model by
## its grip, lets scripts/hands/grip_solver.gd push it out of the palm and close the fingers on it,
## and prints how many surface points are still inside the hand ("clip", 0 is clean) and how many
## were inside at the open pose ("start", a placement to fix). --only re-solves those kinds and keeps
## every other entry.

const Solver := preload("res://scripts/hands/grip_solver.gd")
const Grips := preload("res://scripts/hands/grips.gd")
const Arms := preload("res://scripts/hands/fp_arms.gd")
const HandsFP := preload("res://scripts/hands/fp_hands.gd")
const LootTable := preload("res://scripts/economy/loot_table.gd")
const OUT := "res://scripts/hands/grip_bake.gd"
## Surface sampling (socket metres) and the box around a hand worth sampling.
const STEP := 0.0035
const KEEP := AABB(Vector3(-0.16, -0.09, -0.22), Vector3(0.32, 0.3, 0.36))

var lines := {}


func _ready() -> void:
	await get_tree().process_frame
	var only: Array = []
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			only = Array(a.split("=")[1].split(","))
	var bake: Dictionary = Grips.GripBake.BAKE.duplicate(true) if not only.is_empty() else {}
	var kinds: Array = ["__torch", "__jab"]
	for k in Items.ITEMS.keys():
		if not Items.is_worn(k):
			kinds.append(k)
	for k in LootTable.kinds():
		if not kinds.has(k):
			kinds.append(k)
	var worst := 0
	for kind in kinds:
		if not only.is_empty() and not only.has(kind):
			continue
		for key in bake.keys():
			if String(key).begins_with(kind + ":"):
				bake.erase(key)
		var top := 1 if kind.begins_with("__") else Grips.fp_shown_count(kind, 99)
		for n in range(1, top + 1):
			var e := _solve(kind, n)
			bake["%s:%d" % [kind, n]] = e
			worst = maxi(worst, int(e.clip))
			print("[gripbake] %-22s n=%d grip=%-5s k=%.2f push=%.4f clip=%d start=%d" % [kind, n, e.grip, e.k, e.push, e.clip, e.start])
	_write(bake)
	print("[gripbake] wrote ", OUT, " (", bake.size(), " entries, worst clip ", worst, ")")
	get_tree().quit(0)


static func model_of(kind: String, n: int) -> Node3D:
	if kind == "__torch":
		return Arms.make_torch()
	if kind == "__jab":
		return preload("res://scripts/combat/combat.gd").make_syringe()
	return ItemModels.make(kind, n)


func _solve(kind: String, n: int) -> Dictionary:
	var model := model_of(kind, n)
	add_child(model)
	var spec := Grips.fp_spec(kind)
	var k: float = 1.0 if kind.begins_with("__") else HandsFP.fp_scale(kind)
	var two: bool = not kind.begins_with("__") and int(Grips.grip(kind).hands) >= 2
	var e := {}
	if two:
		# fp_hands' own layout: the model between the palms; only the fingers are solved.
		var lay := HandsFP.two_hand_layout(kind, k, 0.0)
		var model_xf: Transform3D = (lay.held as Transform3D) * (lay.pivot as Transform3D) * Transform3D(Basis.from_scale(Vector3.ONE * k), Vector3.ZERO)
		var pl := Solver.surface_points(model, (lay.xl as Transform3D).affine_inverse() * model_xf, KEEP, STEP)
		var pr := Solver.surface_points(model, (lay.xr as Transform3D).affine_inverse() * model_xf, KEEP, STEP)
		var sl := Solver.solve(pl, Grips.FP_TARGET.two, -1.0)
		var sr := Solver.solve(pr, Grips.FP_TARGET.two, 1.0)
		e = {"grip": "two", "k": k, "xf": lay.pivot, "shape": sl.shape, "shape_r": sr.shape,
			"spread": maxf(float(sl.push), float(sr.push)), "push": maxf(float(sl.push), float(sr.push)),
			"clip": int(sl.clip) + int(sr.clip), "start": int(sl.start_clip) + int(sr.start_clip)}
	else:
		var side := 1.0 if kind == "__torch" else -1.0
		var pos: Vector3
		if spec.pos == null:
			var box := _box(model)
			pos = Vector3(box.get_center().x, box.position.y, box.get_center().z)
		else:
			pos = spec.pos
		var target: Dictionary = Grips.FP_TARGET.get(String(spec.grip), Grips.FP_TARGET.palm)
		var frame: Array = pinch_frame(target, side) if String(spec.grip) == "pinch" else []
		var xf0 := Grips.fp_transform(spec, pos, k, side, frame)
		var pts := Solver.surface_points(model, xf0 * Transform3D(Basis.from_scale(Vector3.ONE * k), Vector3.ZERO), KEEP, STEP)
		# The palm pushes palm and fist grips out of itself; a pinch and a hook sit in the fingers.
		var s := Solver.solve(pts, target, side, not (String(spec.grip) in ["pinch", "hook"]), Arms.SHAPE_OPEN,
			-0.13 if String(spec.grip) == "palm" else Solver.PALM_MIN.z)   # a palm thing rests on the fingers too
		var xf := xf0
		xf.origin += Vector3(0.0, float(s.push), 0.0)
		e = {"grip": String(spec.grip), "k": k, "xf": xf, "shape": s.shape, "push": float(s.push),
			"clip": int(s.clip), "start": int(s.start_clip)}
	model.queue_free()
	return e


## A pinch: the thing goes between the index fingertip and the thumb tip of the pinch shape, its
## face (out of the palm, for a lying thing) along the line from the finger to the thumb, and it
## points away from the palm. The solver then closes both onto it from an open hand.
static func pinch_frame(target: Dictionary, side: float) -> Array:
	var segs := Arms.chain(target, side)
	var index_tip: Vector3 = segs[2][1] * Arms.HAND_SCALE
	var thumb_tip: Vector3 = segs[14][1] * Arms.HAND_SCALE
	var mid := (index_tip + thumb_tip) * 0.5
	var d := (thumb_tip - index_tip).normalized()
	var out := mid - Arms.PALM_CENTRE * Arms.HAND_SCALE
	# Mostly forward, away from the fingertips, so the thing reads as held out rather than up.
	out = out.normalized() * 0.4 + Vector3(0.0, 0.0, -1.0)
	out = (out - d * out.dot(d)).normalized()
	return [mid, out, d]


static func _box(root: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		var t := Transform3D()
		var p: Node = mi
		while p != null and p != root:
			if p is Node3D:
				t = (p as Node3D).transform * t
			p = p.get_parent()
		var a := t * mi.get_aabb()
		box = a if first else box.merge(a)
		first = false
	return box


static func _r(x: float) -> String:
	return str(snappedf(x, 0.0001))


static func _shape_str(s: Dictionary) -> String:
	if s.is_empty():
		return "{}"
	var f: Array = []
	for row in s.f:
		f.append("[%s, %s, %s]" % [_r(row[0]), _r(row[1]), _r(row[2])])
	return "{\"f\": [%s], \"t\": [%s, %s, %s, %s]}" % [", ".join(f), _r(s.t[0]), _r(s.t[1]), _r(s.t[2]), _r(s.t[3])]


func _write(bake: Dictionary) -> void:
	var keys := bake.keys()
	keys.sort()
	var out := "extends RefCounted\n## GENERATED by tools/gripbake.gd -- do not edit by hand; re-run it (docs/CONTRACTS.md \"Player:\n## hands\"). The solved first-person grips: the Held pivot's transform in the palm socket, the model\n## scale, and the hand's finger shape (scripts/hands/fp_arms.gd) closed on the model. Read through\n## scripts/hands/grips.gd fp_held().\n\nconst BAKE := {\n"
	for key in keys:
		var e: Dictionary = bake[key]
		var x: Transform3D = e.xf if e.xf is Transform3D else _xf_of(e.xf)
		var b := x.basis
		var xs := [b.x.x, b.x.y, b.x.z, b.y.x, b.y.y, b.y.z, b.z.x, b.z.y, b.z.z, x.origin.x, x.origin.y, x.origin.z]
		var xa: Array = []
		for v in xs:
			xa.append(_r(v))
		out += "\t\"%s\": {\"grip\": \"%s\", \"k\": %s, \"xf\": [%s], \"shape\": %s" % [key, e.grip, _r(e.k), ", ".join(xa), _shape_str(e.shape)]
		if e.get("shape_r", {}) is Dictionary and not (e.get("shape_r", {}) as Dictionary).is_empty():
			out += ", \"shape_r\": %s, \"spread\": %s" % [_shape_str(e.shape_r), _r(e.spread)]
		out += ", \"clip\": %d, \"start\": %d},\n" % [int(e.get("clip", 0)), int(e.get("start", 0))]
	out += "}\n"
	var f := FileAccess.open(OUT, FileAccess.WRITE)
	f.store_string(out)
	f.close()


static func _xf_of(x: Array) -> Transform3D:
	return Transform3D(Basis(Vector3(x[0], x[1], x[2]), Vector3(x[3], x[4], x[5]), Vector3(x[6], x[7], x[8])), Vector3(x[9], x[10], x[11]))
