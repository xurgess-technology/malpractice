extends SkeletonModifier3D
## Pose overrides on a player body (third person), applied after the idle / walk clip: each arm is
## pointed along a direction in skeleton space and the torso leans and twists, each blended over the
## clip by its own weight. body_hands.gd sets the targets every frame from the rig map's pose table.

var rig: Dictionary = {}
## Targets: arm direction (skeleton space) and weight; torso [pitch, yaw] and weight.
var arm_r := Vector3.FORWARD
var arm_r_w := 0.0
var arm_l := Vector3.FORWARD
var arm_l_w := 0.0
var torso := Vector2.ZERO
var torso_w := 0.0
## SWEEP 4A HOOK (controls): 0..1, the third-person crouch lean. Additive on top of torso_w (set
## every frame by body_hands.gd from the hold/carry/wind-up pose table) so crouching still reads
## while holding or carrying something.
var crouch := 0.0
## The Night Nurse's grab (scripts/monsters/nurse_grab.gd): 0..1, hanging by the neck from her hands.
## The arms hang limp at their sides, swinging a little with the kick; the legs hang limp, toes
## pointed, kicking weakly and less and less; the head tipped back toward her. `dangle_t` is how long they have
## hung (body_hands.gd counts it). Generic (human) rigs only; it replaces the arm targets meanwhile.
var dangle := 0.0
var dangle_t := 0.0

var _idx := {}


func _bones(sk: Skeleton3D) -> bool:
	if _idx.is_empty() and not rig.is_empty():
		for key in (rig.bones as Dictionary).keys():
			_idx[key] = sk.find_bone(String(rig.bones[key]))
	return not _idx.is_empty() and int(_idx.get("torso", -1)) >= 0


func _process_modification_with_delta(_delta: float) -> void:
	var sk := get_skeleton()
	if sk == null or not _bones(sk):
		return
	if rig.get("generic", false):   # HUMAN HOOK
		_generic(sk)
		return
	var ti: int = _idx.torso
	var tq := sk.get_bone_pose_rotation(ti)
	if torso_w > 0.001:
		var want := tq * Quaternion.from_euler(Vector3(torso.x, torso.y, 0.0))
		tq = tq.slerp(want, clampf(torso_w, 0.0, 1.0))
		sk.set_bone_pose_rotation(ti, tq)
	if crouch > 0.001:
		tq = tq * Quaternion(Vector3.RIGHT, 0.3 * clampf(crouch, 0.0, 1.0))
		sk.set_bone_pose_rotation(ti, tq)
	# The arms hang off the torso: express the skeleton-space direction in the torso's frame.
	var parent := sk.get_bone_parent(ti)
	var tb := Basis(tq)
	while parent >= 0:
		tb = Basis(sk.get_bone_pose_rotation(parent)) * tb
		parent = sk.get_bone_parent(parent)
	var inv := tb.inverse()
	for side in [["arm_r", arm_r, arm_r_w], ["arm_l", arm_l, arm_l_w]]:
		var w: float = side[2]
		var bi := int(_idx.get(side[0], -1))
		if w <= 0.001 or bi < 0:
			continue
		var rest: Vector3 = rig.arm_rest[side[0]]
		var dir: Vector3 = (inv * (side[1] as Vector3)).normalized()
		var target := Quaternion(rest.normalized(), dir)
		var aq := sk.get_bone_pose_rotation(bi)
		sk.set_bone_pose_rotation(bi, aq.slerp(target, clampf(w, 0.0, 1.0)))


# -- HUMAN HOOK: rigs with rest rotations and two-bone arms (the Blender humans) ---------------------

var _gidx := {}


func _generic(sk: Skeleton3D) -> void:
	if _gidx.is_empty():
		var chain: Array = []
		for nm in rig.get("torso_chain", [rig.bones.torso]):
			var bi := sk.find_bone(String(nm))
			if bi >= 0:
				chain.append(bi)
		_gidx["chain"] = chain
		for side in ["arm_r", "arm_l"]:
			_gidx[side] = sk.find_bone(String(rig.bones[side]))
			_gidx[side + "_fore"] = sk.find_bone(String(rig.fore[side]))
	var chain: Array = _gidx.chain
	if torso_w > 0.001 and not chain.is_empty():
		var k := clampf(torso_w, 0.0, 1.0) / float(chain.size())
		var q := Quaternion(Vector3.UP, torso.y * k) * Quaternion(Vector3.RIGHT, torso.x * k)
		for bi in chain:
			_turn(sk, int(bi), q)
	if crouch > 0.001 and not chain.is_empty():   # SWEEP 4A HOOK (controls)
		var ck := clampf(crouch, 0.0, 1.0) / float(chain.size())
		var cq := Quaternion(Vector3.RIGHT, 0.3 * ck)
		for bi in chain:
			_turn(sk, int(bi), cq)
	if crouch > 0.001:   # CROUCH POSE: the legs, which is where the height actually comes off
		_crouch_legs(sk, clampf(crouch, 0.0, 1.0))
	for side in [["arm_r", arm_r, arm_r_w], ["arm_l", arm_l, arm_l_w]]:
		var w: float = side[2]
		var upper := int(_gidx.get(side[0], -1))
		var fore := int(_gidx.get(side[0] + "_fore", -1))
		if w <= 0.001 or upper < 0:
			continue
		var d: Vector3 = (side[1] as Vector3).normalized()
		# The elbow bends: the upper arm hangs lower than the forearm unless the arm is raised.
		var up_dir := (d + Vector3(0.0, -0.65, 0.0) * (1.0 - maxf(0.0, d.y))).normalized()
		if absf(d.x) > 0.6:
			# a forearm across the body (the carry): the upper arm goes forward, the elbow bends in
			up_dir = Vector3(d.x * 0.2, maxf(d.y, 0.0) * 0.5 - 0.15, 0.95).normalized()
		_aim(sk, upper, up_dir, w)
		if fore >= 0:
			_aim(sk, fore, d, w)
	if dangle > 0.001:
		_dangle(sk, clampf(dangle, 0.0, 1.0))


## CROUCH POSE: how far the knee bends at a full crouch, radians. The torso lean above is only a
## lean -- on its own a crouching player stands at full height, which is why crouch read as standing.
const CROUCH_KNEE := 0.9


## CROUCH POSE (2026-09-22): bend the knees and sink the hips by exactly what the bent leg lost, so
## the feet stay on the floor and the whole body gets shorter.
##
## Every turn here is a *delta* in skeleton space on top of whatever clip is playing, not an `_aim`
## that would pin the legs where they are: that is what lets one piece of code be both the crouch
## pose (over Idle) and the crouch walk (over Walk), with the clip's own stepping still showing
## through. Aiming the legs absolutely would freeze them and the feet would skate.
##
## Geometry: thigh forward by `a` puts the knee out front, shin back by `a` brings the ankle home
## under the hip again, so the leg keeps its footprint and only loses height -- (thigh + shin) *
## (1 - cos a) of it. The shin's delta is 2a because it has already inherited the thigh's -a, and
## the foot's -a undoes the shin's so the sole stays flat.
func _crouch_legs(sk: Skeleton3D, k: float) -> void:
	var a := CROUCH_KNEE * k
	var drop := 0.0
	for sd in [".L", ".R"]:
		var thigh := sk.find_bone("thigh" + sd)
		var shin := sk.find_bone("shin" + sd)
		var foot := sk.find_bone("foot" + sd)
		if thigh < 0 or shin < 0:
			continue
		_turn(sk, thigh, Quaternion(Vector3.RIGHT, -a))
		_turn(sk, shin, Quaternion(Vector3.RIGHT, 2.0 * a))
		if foot >= 0:
			_turn(sk, foot, Quaternion(Vector3.RIGHT, -a))
		# A bone's rest origin is its offset from its parent, so the shin's is the thigh's length.
		var legs := sk.get_bone_rest(shin).origin.length()
		if foot >= 0:
			legs += sk.get_bone_rest(foot).origin.length()
		drop = maxf(drop, legs * (1.0 - cos(a)))
	var hips := sk.find_bone("hips")
	if hips >= 0 and drop > 0.0:
		var parent := sk.get_bone_parent(hips)
		var pb := _global(sk, parent).basis if parent >= 0 else Basis.IDENTITY
		sk.set_bone_pose_position(hips, sk.get_bone_pose_position(hips) + pb.inverse() * Vector3(0.0, -drop, 0.0))
	# The chest lean above tips the head down with it: look back up, so a crouching player is still
	# watching where they are going rather than studying the floor.
	var head := sk.find_bone(String(rig.bones.get("head", "head")))
	if head >= 0:
		_turn(sk, head, Quaternion(Vector3.RIGHT, -0.22 * k))


func _dangle(sk: Skeleton3D, k: float) -> void:
	var t := dangle_t
	# The kick: fast and wild at first, then weaker and slower as it runs out.
	var fade := exp(-t * 1.1)
	var kick := sin(t * 11.0) * fade
	var tremble := Vector3(sin(t * 53.0), cos(t * 47.0), sin(t * 61.0)) * 0.05 * (0.4 + fade)
	for side in [[".L", 1.0], [".R", -1.0]]:
		var sd: String = side[0]
		var s: float = side[1]
		var thigh := sk.find_bone("thigh" + sd)
		var shin := sk.find_bone("shin" + sd)
		var foot := sk.find_bone("foot" + sd)
		if thigh >= 0:
			_aim(sk, thigh, Vector3(0.04 * s, -1.0, 0.10 + 0.30 * kick * s).normalized(), k)
		if shin >= 0:
			_aim(sk, shin, Vector3(0.0, -1.0, -0.18 - 0.35 * maxf(0.0, kick * s)).normalized(), k)
		if foot >= 0:
			_aim(sk, foot, Vector3(0.0, -0.85, 0.5).normalized(), k)   # toes pointed down
		# The arms hang limp at their sides, swaying a little with the kick.
		var upper := int(_gidx.get("arm_r" if s < 0.0 else "arm_l", -1))
		var fore := int(_gidx.get(("arm_r" if s < 0.0 else "arm_l") + "_fore", -1))
		var sway := 0.12 * kick * s
		if upper >= 0:
			_aim(sk, upper, (Vector3(0.14 * s, -1.0, 0.04 + sway) + tremble * 0.3).normalized(), k)
		if fore >= 0:
			_aim(sk, fore, (Vector3(0.06 * s, -1.0, 0.12 + sway) + tremble * 0.3).normalized(), k)
	var head := sk.find_bone(String(rig.bones.get("head", "head")))
	if head >= 0:
		_turn(sk, head, Quaternion.IDENTITY.slerp(Quaternion(Vector3.RIGHT, -0.4), k))   # tipped back, up at her


## Turn a bone (skeleton space) so its +Y points along dir, by weight w.
func _aim(sk: Skeleton3D, bone: int, dir: Vector3, w: float) -> void:
	var g := _global(sk, bone)
	var cur := g.basis.y.normalized()
	if cur.dot(dir) > 0.9999:
		return
	var q := Quaternion(cur, dir)
	_turn(sk, bone, Quaternion.IDENTITY.slerp(q, clampf(w, 0.0, 1.0)))


func _turn(sk: Skeleton3D, bone: int, q: Quaternion) -> void:
	var parent := sk.get_bone_parent(bone)
	var pq := _global(sk, parent).basis.get_rotation_quaternion() if parent >= 0 else Quaternion.IDENTITY
	sk.set_bone_pose_rotation(bone, (pq.inverse() * q * pq * sk.get_bone_pose_rotation(bone)).normalized())


func _global(sk: Skeleton3D, bone: int) -> Transform3D:
	var xf := Transform3D()
	var i := bone
	while i >= 0:
		xf = Transform3D(Basis(sk.get_bone_pose_rotation(i)), sk.get_bone_pose_position(i)) * xf
		i = sk.get_bone_parent(i)
	return xf
