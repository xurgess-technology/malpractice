extends SkeletonModifier3D
## The Service Dog's Blender-made model (`monster/service_dog`, art/service_dog/) on a monster
## model. Analogous to night_nurse_rig.gd and hive_rig.gd: `build(model)` spawns the GLB, points
## the model's `rig`, `skeleton` and `anim` at it and adds this modifier to its skeleton, plus a
## BoneAttachment3D named `Head` on the head bone.
##
## Clips (Assets anims): Idle (5 s loop), Walk (1.6 s loop, in place), PlaceItem (2 s, one-shot),
## Growl (0.8 s, one-shot), StandUp (quadruped -> biped, one-shot), Run (1 s loop, biped), Bite
## (0.6 s, one-shot). The monster (brain side, service-dog-brain) picks the clip and the rate; this
## modifier layers the poses there are no clips for, on top of whatever clip is playing:
##
##   look_at     Vector3, skeleton space; Vector3.ZERO to release. Turns the head (and a little of
##               the neck) toward it -- the growl/warning beat's head-track.
##   look_weight 0..1  how much of `look_at` to take (lets the brain ease it in/out)
##   twitch      0..1  a barely-there tremor through the spine/ears/tail: "wrong" stillness, not
##               nervous energy. Intended to run low and constant at idle, per DESIGN's tone.
##   ear_alert   0..1  ears pin back and turn toward `look_at` (or forward if none is set)
##
## Every value is in skeleton space (+Y up, +Z its front, +X its left), matching the convention in
## night_nurse_rig.gd, so the numbers do not depend on how each bone's local axes were authored.
## Nothing runs while look_weight, twitch and ear_alert are all zero.

const KEY := "monster/service_dog"

var look_at := Vector3.ZERO
var look_weight := 0.0
var twitch := 0.0
var ear_alert := 0.0

var _b := {}
var _t := 0.0


## Spawn the model under `model` (a MonsterModel). False when the asset is missing or broken.
static func build(model: Node3D) -> bool:
	if not Assets.has(KEY):
		return false
	var root: Node3D = Assets.spawn(KEY)
	if root == null:
		return false
	var skels := root.find_children("*", "Skeleton3D", true, false)
	var ap: AnimationPlayer = Assets.anim_player(root)
	if skels.is_empty() or ap == null:
		root.free()
		return false
	model.add_child(root)
	model.rig = root
	model.skeleton = skels[0]
	model.anim = ap
	for n in ["Idle", "Walk", "Run"]:
		if ap.has_animation(n):
			ap.get_animation(n).loop_mode = Animation.LOOP_LINEAR
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	var sk: Skeleton3D = skels[0]
	var head := BoneAttachment3D.new()
	head.name = "Head"
	head.bone_name = "head"
	sk.add_child(head)
	var poser = load("res://scripts/monsters/dog_rig.gd").new()
	poser.name = "DogPoser"
	sk.add_child(poser)
	# MonsterModel does not yet carry a `dog` field the way it carries `nurse`/`hive`/`sono` (that
	# wiring belongs to service-dog-brain, which owns monster_model.gd's dispatch); callers can
	# always reach this poser as `model.skeleton.get_node("DogPoser")` in the meantime.
	return true


func _bone(sk: Skeleton3D, n: String) -> int:
	if _b.is_empty():
		for i in sk.get_bone_count():
			_b[sk.get_bone_name(i)] = i
	return int(_b.get(n, -1))


func bone_world(n: String) -> Vector3:
	var sk := get_skeleton()
	if sk == null:
		return Vector3.ZERO
	var i := _bone(sk, n)
	if i < 0:
		return sk.global_position
	return sk.global_transform * sk.get_bone_global_pose(i).origin


func _turn(sk: Skeleton3D, bone: String, axis: Vector3, angle: float) -> void:
	if absf(angle) < 0.0001:
		return
	var i := _bone(sk, bone)
	if i < 0:
		return
	var p := sk.get_bone_parent(i)
	var pg := sk.get_bone_global_pose(p).basis.orthonormalized() if p >= 0 else Basis()
	var g := pg * Basis(sk.get_bone_pose_rotation(i))
	var local := pg.inverse() * (Basis(axis.normalized(), angle) * g)
	sk.set_bone_pose_rotation(i, local.get_rotation_quaternion())


## Turn the head (and a slice of the neck) to face `at`, blended by `w`; matches night_nurse_rig's
## `_face` in spirit but simpler -- the dog has no cocked-head snap, just a level, patient turn.
func _look(sk: Skeleton3D, at: Vector3, w: float) -> void:
	var i := _bone(sk, "head")
	if i < 0 or w <= 0.0:
		return
	var p := sk.get_bone_parent(i)
	var pg := sk.get_bone_global_pose(p).basis.orthonormalized() if p >= 0 else Basis()
	var g := (pg * Basis(sk.get_bone_pose_rotation(i))).orthonormalized()
	var z := at - sk.get_bone_global_pose(i).origin
	if z.length() < 0.01:
		return
	z = z.normalized()
	var x := Vector3.UP.cross(z)
	if x.length() < 0.01:
		return
	x = x.normalized()
	var want := Basis(x, z.cross(x), z)
	var q := g.get_rotation_quaternion().slerp(want.get_rotation_quaternion(), clampf(w, 0.0, 1.0))
	sk.set_bone_pose_rotation(i, (pg.inverse() * Basis(q)).get_rotation_quaternion())


func _process_modification_with_delta(delta: float) -> void:
	_t += delta
	if look_weight <= 0.0 and twitch <= 0.0 and ear_alert <= 0.0:
		return
	var sk := get_skeleton()
	if sk == null:
		return
	if look_weight > 0.0 and look_at != Vector3.ZERO:
		_look(sk, look_at, look_weight)
	if ear_alert > 0.0:
		var toward := 0.0
		if look_at != Vector3.ZERO:
			var head_i := _bone(sk, "head")
			if head_i >= 0:
				var local_dir: Vector3 = sk.global_transform.affine_inverse() * look_at - sk.get_bone_global_pose(head_i).origin
				toward = clampf(local_dir.x, -1.0, 1.0)
		_turn(sk, "ear.L", Vector3.RIGHT, -0.35 * ear_alert)
		_turn(sk, "ear.R", Vector3.RIGHT, -0.35 * ear_alert)
		_turn(sk, "ear.L", Vector3.FORWARD, 0.25 * ear_alert * toward)
		_turn(sk, "ear.R", Vector3.FORWARD, 0.25 * ear_alert * toward)
	if twitch > 0.0:
		# A barely-there tremor, not nervous energy: the "held too still, then a wrong little
		# jolt" read from the reference art, layered under whatever clip is playing.
		var tremor := sin(_t * 14.0) * 0.006 + sin(_t * 3.3 + 1.7) * 0.004
		_turn(sk, "spine1", Vector3.RIGHT, tremor * twitch)
		_turn(sk, "tail1", Vector3.FORWARD, tremor * 2.0 * twitch)
		_turn(sk, "tail2", Vector3.FORWARD, tremor * 1.4 * twitch)
		var spike := 0.0
		var cyc := fmod(_t, 5.0)
		if cyc > 4.85:
			spike = (cyc - 4.85) / 0.15
		_turn(sk, "ear.L", Vector3.RIGHT, -0.15 * spike * twitch)
		_turn(sk, "ear.R", Vector3.RIGHT, -0.15 * spike * twitch)
