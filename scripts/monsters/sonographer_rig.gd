extends SkeletonModifier3D
## The Sonographer's stylized model (`monster/sonographer`, art/stylized variant `sonographer`) on a
## monster model. A standalone model: no cart, no console.
##
## The thing that makes it work is **the neck**. It looks almost normal at rest (an ordinary neck with a
## glowing windpipe behind a thin pane of skin), and the first time you see it longer than a person's is
## when it starts to grow. The shared skeleton's one neck bone is cut into a chain of four
## (art/stylized: `st_build.add_neck_bones`), and this modifier stretches that chain by up to `CRANE_M`
## as `suspicion` rises. The windpipe and the thin skin over it are weighted along the same chain, so the
## glowing windpipe stretches out along it and the throat burns brighter. **The neck is the suspicion
## meter**, so the clips never stretch it: they all pose it with only a slight stoop, and the crane is a
## 0..1 blend laid on top of whatever is playing.
##
## `build(model)` spawns the GLB under the MonsterModel, points the model's `rig`, `skeleton` and
## `anim` at it, adds this modifier to its skeleton and hangs a node named `Head` on the head bone in
## the model's own axes (+Y up, +Z its face), the way the Hive does. It also:
##   - takes the two ear pieces (Human_Ear_L / _R) off the mesh and re-hangs each under a pivot at its
##     Site_ear_*, so MonsterModel.set_ears can swivel them toward a sound;
##   - puts the glow shader on the windpipe (Human_Throat) behind the throat's see-through skin
##     (Human_ThroatSkin) and on the wand (Human_Probe) fitted to the cut right wrist, so the charge
##     lights the throat first and then the wand;
##   - wets the skin: a glossy copy of the skin material, because the gel is what the flashlight
##     catches;
##   - hangs a marker on the probe's tip (Site_probe), which is where an echo fires from.
##
## Clips (Assets anims): SonoIdle, SonoWander (0.8 m/s), SonoListen, SonoCharge, SonoEcho, SonoRush
## (3.1 m/s), SonoWail, SonoSearch, SonoStagger, SonoLying.
##
## It stands in for rig_shaper.gd: `model.shaper` points here, so monster.gd, the stun window and the
## dissection table set the same inputs they give every other monster:
##   lying, daze, rise, stagger, twitch, listen, listen_yaw, lunge   (see hive_rig.gd)
## and the look interface it adds is documented on MonsterModel.set_sono_look (docs/CONTRACTS.md).
##
## Every value is in skeleton space (+Y up, +Z its front, +X its left).

const Shapes := preload("res://scripts/monsters/shapes.gd")

const KEY := "monster/sonographer"
## Ground speeds the wander and rush clips were authored at (art/stylized/st_sono_clips.py).
const WANDER_SPEED := 0.80
const RUSH_SPEED := 3.10
## How far the neck chain stretches from rest to fully craned, in metres (art/stylized: CRANE_M). The
## neck is an ordinary length at rest, so all of this is new length.
const CRANE_M := 0.90
## How long the echo's burst lasts, and how far its rings get.
const BURST_T := 0.75
const BURST_R := 1.9
## How far the chain unfolds out of its slight stoop at full crane, in radians, shared down the chain.
const CRANE_LIFT := 0.16
## Where the crane goes instead when there is a ceiling: forward, not up.
const CRANE_FORWARD := 0.85
const GLOW := Color(0.61, 0.42, 1.0)         # #9b6bff, the ability icon's trachea
const GLOW_SHADER := "res://shaders/sono_glow.gdshader"
const NECK_BONES := ["neck", "neck2", "neck3", "neck4"]
## How the stretch and the unfold are shared down the chain, low to high.
const NECK_SHARE := [0.34, 0.28, 0.22, 0.16]

var cfg := {"lying_spread": 6.0}
var listen := 0.0
var listen_yaw := 0.0
var lunge := 0.0
var stagger := 0.0
var twitch := Vector3.ZERO
var lying := 0.0
var daze := 0.0
var rise := 0.0
## The look interface (MonsterModel.set_sono_look sets these).
##   suspicion  0..1  the neck stretches with it and the throat glows brighter
##   charge     0..1  the charge pose and the glow coming on in the throat and then the wand
##   mode             which clip family is playing
##   aim              world direction the probe points while charging and echoing
##   crane_limit 0..1 how far the neck may stretch up before it bends forward instead (the ceiling
##                    check; chunk B does the raycast, this only obeys the number)
var suspicion := 0.0
var charge := 0.0
var mode := "idle"
var aim := Vector3.ZERO
var crane_limit := 1.0
## Where the eyes would have been, in the Head node's frame; set from the model's Site_eyes.
var eye_offset := Vector3(0.0, 0.10, 0.09)
## World positions of the hands after this frame's pose.
var hand_left := Vector3.ZERO
var hand_right := Vector3.ZERO

var _b := {}
var _rest_fwd := Vector3.BACK
var _rest_up := Vector3.UP
var _throat: ShaderMaterial = null
var _pane: StandardMaterial3D = null
var _probe_mat: ShaderMaterial = null
var _light: OmniLight3D = null
var _probe: Node3D = null
var _shown := -1.0
var _crane := 0.0
var _mouth: Node3D = null
var _rings: Array = []          ## [MeshInstance3D], the echo's rings: mouth first, then the probe
var _ring_mats: Array = []
var _flash: Array = []          ## [OmniLight3D] at the mouth and the probe
var _burst := -1.0              ## seconds since the echo fired, or -1 for nothing happening
var _model: Node3D = null       ## the MonsterModel: its origin is at the feet
var _drips: Array = []          ## [GPUParticles3D], the gel falling off the mouth, the left hand and the wand
var _was_echo := false

static var _looped := false


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
	if not _looped:
		# The imported clips are one-shot; only this model uses them, so loop the shared copies once.
		_looped = true
		for n in ["SonoIdle", "SonoWander", "SonoListen", "SonoRush", "SonoSearch", "SonoLying"]:
			if ap.has_animation(n):
				ap.get_animation(n).loop_mode = Animation.LOOP_LINEAR
	var sk: Skeleton3D = skels[0]
	var poser = load("res://scripts/monsters/sonographer_rig.gd").new()
	poser.name = "SonoPoser"
	sk.add_child(poser)
	poser._setup(root, sk, model)
	model.sono = poser
	model.shaper = poser
	return true


func _setup(root: Node3D, sk: Skeleton3D, model: Node3D) -> void:
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	var hi := _bone(sk, "head")
	var rest := sk.get_bone_global_rest(hi) if hi >= 0 else Transform3D()
	var rb := rest.basis.orthonormalized()
	_rest_fwd = rb.inverse() * Vector3.BACK
	_rest_up = rb.inverse() * Vector3.UP
	var ba := BoneAttachment3D.new()
	ba.name = "HeadBone"
	ba.bone_name = "head"
	sk.add_child(ba)
	var head := Node3D.new()
	head.name = "Head"
	head.transform = Transform3D(rb.inverse(), Vector3.ZERO)
	ba.add_child(head)
	var site := root.find_child("Site_eyes", true, false) as Node3D
	if site != null and hi >= 0:
		eye_offset = (rest * site.position) - rest.origin

	_ears(root, sk, model)
	_throat_glow(root, sk)
	_probe_glow(root)
	_wet_skin(root)
	_probe = _marker(root, sk, "Site_probe", "hand.R", "ProbeTip", Vector3(0.0, 0.0, -0.18))
	_mouth = _marker(root, sk, "Site_mouth", "head", "Mouth", Vector3(0.0, 0.02, 0.10))
	_make_burst()
	_model = model
	_make_drips(sk)
	set_process(true)
	_set_glow(0.0)


## A node riding `bone` at the GLB's `site`, or at `fallback` in the bone's frame when it is missing.
func _marker(root: Node3D, sk: Skeleton3D, site: String, bone: String, node_name: String, fallback: Vector3) -> Node3D:
	var ba := BoneAttachment3D.new()
	ba.name = node_name + "Bone"
	ba.bone_name = bone
	sk.add_child(ba)
	var n := Node3D.new()
	n.name = node_name
	var at := root.find_child(site, true, false) as Node3D
	if at != null:
		n.transform = at.transform
	else:
		n.position = fallback
	ba.add_child(n)
	return n


## Each ear off the mesh and onto a pivot at its site, so set_ears can turn it.
func _ears(root: Node3D, sk: Skeleton3D, model: Node3D) -> void:
	var hi := _bone(sk, "head")
	if hi < 0:
		return
	var head_rest := sk.get_bone_global_rest(hi)
	# the pivots stand in the model's own axes (X its left, Y up, Z its face), not the head bone's,
	# so MonsterModel.set_ears can yaw an ear about Y and tip it about X the way it expects
	var model_axes := head_rest.basis.orthonormalized().inverse()
	for tag in ["L", "R"]:
		var mi := root.find_child("Human_Ear_" + tag, true, false) as MeshInstance3D
		var at := root.find_child("Site_ear_" + tag, true, false) as Node3D
		if mi == null or at == null:
			continue
		var sx := 1.0 if tag == "L" else -1.0
		var ba := BoneAttachment3D.new()
		ba.name = "EarBone" + tag
		ba.bone_name = "head"
		sk.add_child(ba)
		var pivot := Node3D.new()
		pivot.name = "Ear" + tag
		pivot.transform = Transform3D(model_axes, at.position)
		ba.add_child(pivot)
		# The ear mesh's vertices are in the skeleton's space, so under the pivot it needs the inverse
		# of everything above it to land back where the sculpt put it. Its skin goes: the pivot moves
		# it now, not the head bone's weights.
		mi.get_parent().remove_child(mi)
		mi.skin = null
		mi.skeleton = NodePath()
		mi.transform = (head_rest * pivot.transform).affine_inverse()
		pivot.add_child(mi)
		model.ears.append({"node": pivot, "side": sx, "rest": 0.0})


func _glow_material(mi: MeshInstance3D, idle: float, full: float, fallback: Color) -> ShaderMaterial:
	var shader := load(GLOW_SHADER) as Shader
	if mi == null or shader == null:
		return null
	var src := mi.get_active_material(0) as BaseMaterial3D
	var sm := ShaderMaterial.new()
	sm.shader = shader
	if src != null and src.albedo_texture != null:
		sm.set_shader_parameter("albedo_tex", src.albedo_texture)
	else:
		sm.set_shader_parameter("use_tex", false)
		sm.set_shader_parameter("base_color", fallback)
	sm.set_shader_parameter("glow", GLOW)
	sm.set_shader_parameter("idle_energy", idle)
	sm.set_shader_parameter("full_energy", full)
	# each piece lights as a whole; the travel is piece to piece, up the arm
	sm.set_shader_parameter("t_scale", 0.0)
	sm.set_shader_parameter("t_offset", 0.5)
	sm.set_shader_parameter("flow", 1.0)
	mi.material_override = sm
	return sm


## The windpipe glows behind the thin skin of the throat, and throws violet light into the neck.
func _throat_glow(root: Node3D, sk: Skeleton3D) -> void:
	_throat = _glow_material(root.find_child("Human_Throat", true, false) as MeshInstance3D,
		0.30, 11.0, Color("9b6bff"))
	var pane := root.find_child("Human_ThroatSkin", true, false) as MeshInstance3D
	if pane != null:
		var src2 := pane.get_active_material(0) as BaseMaterial3D
		var m := StandardMaterial3D.new()
		if src2 != null:
			m.albedo_texture = src2.albedo_texture
		m.albedo_color = Color(1.0, 1.0, 1.0, 0.44)
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.roughness = 0.16
		pane.material_override = m
		_pane = m
	var neck := BoneAttachment3D.new()
	neck.name = "ThroatBone"
	neck.bone_name = "neck2"
	sk.add_child(neck)
	_light = OmniLight3D.new()
	_light.name = "ThroatGlow"
	_light.light_color = GLOW
	_light.omni_range = 0.8
	_light.light_energy = 0.0
	_light.shadow_enabled = false
	_light.visible = false
	var thr := root.find_child("Site_throat", true, false) as Node3D
	if thr != null:
		_light.transform = thr.transform
	else:
		_light.position = Vector3(0.0, 0.06, 0.0)
	neck.add_child(_light)


## The wand fitted to the cut wrist lights once the charge is well built, after the throat.
func _probe_glow(root: Node3D) -> void:
	_probe_mat = _glow_material(root.find_child("Human_Probe", true, false) as MeshInstance3D,
		0.02, 8.0, Color("cdc9c0"))


## Ultrasound gel over everything: the skin gets its own glossy copy of the baked material, so the
## flashlight catches it the way nothing else in the game does.
func _wet_skin(root: Node3D) -> void:
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null or m.material_override != null:
			continue
		for si in m.mesh.get_surface_count():
			var mat := m.mesh.surface_get_material(si) as BaseMaterial3D
			if mat == null or not mat.resource_name.contains("Skin") or mat.has_meta("sono_wet"):
				continue
			mat.set_meta("sono_wet", true)
			mat.roughness = 0.22
			mat.metallic_specular = 0.75
			mat.clearcoat_enabled = true
			mat.clearcoat = 0.9
			mat.clearcoat_roughness = 0.06


# ====================================================================== the look interface
## `mode` is one of idle, wander, suspicious, charging, echo, rush, wail, search, stagger, lying.
## `probe_aim` is the world direction the probe points while it charges and echoes.
## `limit` 0..1 is how far the neck may stretch up before it bends forward instead: 1 is open sky,
## 0 is a ceiling right above it. Chunk B does the raycast; this just obeys the number.
func set_look(susp: float, chg: float, m: String, probe_aim := Vector3.ZERO, limit := 1.0) -> void:
	suspicion = clampf(susp, 0.0, 1.0)
	charge = clampf(chg, 0.0, 1.0)
	mode = m
	aim = probe_aim
	crane_limit = clampf(limit, 0.0, 1.0)
	_set_glow(maxf(charge, suspicion))
	# the echo is a beat: fire the burst the moment the mode turns to it
	var echoing := m == "echo"
	if echoing and not _was_echo:
		fire_echo()
	_was_echo = echoing


## How far the neck is craned right now, 0..1. Suspicion drives it; a charge holds it at full.
func crane() -> float:
	return maxf(suspicion, charge)


## Where an echo fires from and which way it points: the probe's tip, not the head. Its -Z is the way
## the wand points, worked out from the hand it is grown into rather than trusted to the site's own
## axes, so it stays right whatever the exporter did with them.
func echo_origin() -> Transform3D:
	if _probe == null:
		return global_transform
	var t := _probe.global_transform
	var fwd := (t.origin - bone_world("hand.R"))
	if fwd.length() < 0.02:
		return t
	fwd = fwd.normalized()
	var up := Vector3.UP if absf(fwd.dot(Vector3.UP)) < 0.9 else Vector3.BACK
	var x := up.cross(fwd).normalized()
	return Transform3D(Basis(x, fwd.cross(x).normalized(), -fwd), t.origin)


## The throat: 0 a cold ember behind the skin, 1 the windpipe burning through it, with the charge
## coming on in the wand once it is mostly built.
func _set_glow(v: float) -> void:
	if absf(v - _shown) < 0.01:
		return
	_shown = v
	if _throat != null:
		_throat.set_shader_parameter("level", v)
	if _pane != null:
		_pane.albedo_color = Color(1.0, 1.0, 1.0, 0.44 - 0.20 * v)
	if _light != null:
		_light.visible = v > 0.02
		_light.light_energy = 0.75 * v
	# the throat fills first, then the wand
	if _probe_mat != null:
		_probe_mat.set_shader_parameter("level", clampf((charge - 0.55) / 0.35, 0.0, 1.0))


# ====================================================================== posing
func _bone(sk: Skeleton3D, n: String) -> int:
	if _b.is_empty():
		for i in sk.get_bone_count():
			_b[sk.get_bone_name(i)] = i
	return int(_b.get(n, -1))


## World position of a bone (after this frame's pose).
func bone_world(n: String) -> Vector3:
	var sk := get_skeleton()
	if sk == null:
		return Vector3.ZERO
	var i := _bone(sk, n)
	if i < 0:
		return sk.global_position
	return sk.global_transform * sk.get_bone_global_pose(i).origin


## rig_shaper.gd's API, for anything that asks.
func attach(node: Node3D, bone: String, offset := Transform3D.IDENTITY, _tip := 0.0) -> void:
	var sk := get_skeleton()
	var ba := BoneAttachment3D.new()
	ba.bone_name = bone
	sk.add_child(ba)
	node.transform = offset
	ba.add_child(node)


func bone_point(bone: String, offset := Vector3.ZERO, _tip := 0.0) -> Vector3:
	var sk := get_skeleton()
	var i := _bone(sk, bone)
	if i < 0:
		return sk.global_position
	return sk.global_transform * (sk.get_bone_global_pose(i) * offset)


## Turn `bone` about a skeleton-space axis through its own head, on top of its current pose.
func _turn(sk: Skeleton3D, bone: String, axis: Vector3, angle: float) -> void:
	if absf(angle) < 0.0001 or axis.length_squared() < 1e-8:
		return
	var i := _bone(sk, bone)
	if i < 0:
		return
	var p := sk.get_bone_parent(i)
	var pg := sk.get_bone_global_pose(p).basis.orthonormalized() if p >= 0 else Basis()
	var g := pg * Basis(sk.get_bone_pose_rotation(i))
	var local := pg.inverse() * (Basis(axis.normalized(), angle) * g)
	sk.set_bone_pose_rotation(i, local.get_rotation_quaternion())


func _process_modification_with_delta(delta: float) -> void:
	var sk := get_skeleton()
	if sk == null:
		return
	var X := Vector3.RIGHT
	var Z := Vector3.BACK
	if lying > 0.0:
		_lie(sk)
	var l := 1.0 - lying
	# the crane: eased, so the neck never snaps except when the clip snaps it
	var want := crane() * l
	_crane = move_toward(_crane, want, delta * (3.2 if want > _crane else 1.6))
	if _crane > 0.001:
		_stretch(sk, _crane)
	if daze > 0.0 or rise > 0.0:
		# Stunned: the long neck folds right down into its shoulders and the head hangs off it.
		var jolt := sin(Time.get_ticks_msec() * 0.031) * rise * (1.0 - rise) * 2.2
		_turn(sk, "spine", X, (0.30 * daze - 0.18 * jolt) * l)
		for i in NECK_BONES.size():
			_turn(sk, NECK_BONES[i], X, (0.55 * daze - 0.30 * jolt) * l * NECK_SHARE[i])
		_turn(sk, "head", X, 0.35 * daze * l)
		_turn(sk, "upperarm.L", X, 0.25 * daze * l)
	if stagger > 0.0:
		_turn(sk, "spine", X, -0.35 * stagger * l)
		for i in NECK_BONES.size():
			_turn(sk, NECK_BONES[i], X, 0.35 * stagger * l * NECK_SHARE[i])
		_turn(sk, "head", X, -0.25 * stagger * l)
	if twitch != Vector3.ZERO:
		var tw := twitch * l
		_turn(sk, "head", Vector3.UP, tw.y)
		_turn(sk, "head", X, tw.x)
		_turn(sk, "head", Z, tw.z)
	if listen > 0.0 and l > 0.0:
		_cock(sk, listen * l)
	_record_hands(sk)


## The crane: the chain stretches by CRANE_M and unfolds out of its slight stoop. `crane_limit` below 1 is a
## ceiling: it stretches less and leans the whole run forward instead, so the head never goes up
## through anything. Chunk B measures the headroom; this obeys it.
func _stretch(sk: Skeleton3D, amount: float) -> void:
	var up := crane_limit
	var fwd := 1.0 - crane_limit
	var per := CRANE_M * amount * (0.35 + 0.65 * up)
	for i in NECK_BONES.size():
		var bi := _bone(sk, NECK_BONES[i])
		if bi < 0:
			continue
		# The bottom bone never moves: its head sits on the collarbones, and pushing it would carry
		# the shoulders and the shirt's collar up with the neck. Only the three above it stretch.
		if i > 0:
			# on top of whatever the clip left, the way _turn does for rotations
			var d := sk.get_bone_pose_position(bi)
			if d.length() > 1e-5:
				sk.set_bone_pose_position(bi, d + d.normalized() * per * NECK_SHARE[i] / (1.0 - NECK_SHARE[0]))
		# unfold out of the stoop, and under a ceiling bend forward instead of standing up
		_turn(sk, NECK_BONES[i], Vector3.RIGHT, (-CRANE_LIFT * up + CRANE_FORWARD * fwd) * amount * NECK_SHARE[i])
	# the head levels out with it, so it ends up looking where it is listening
	_turn(sk, "head", Vector3.RIGHT, (CRANE_LIFT * 0.55 * up - CRANE_FORWARD * 0.4 * fwd) * amount)


func _record_hands(sk: Skeleton3D) -> void:
	var li := _bone(sk, "hand.L")
	var ri := _bone(sk, "hand.R")
	if li >= 0:
		hand_left = sk.global_transform * sk.get_bone_global_pose(li).origin
	if ri >= 0:
		hand_right = sk.global_transform * sk.get_bone_global_pose(ri).origin


## Straight on its back: every bone eases back to rest (so the neck goes back to rest length too),
## then the arms come in to its sides.
func _lie(sk: Skeleton3D) -> void:
	var k := lying
	for i in sk.get_bone_count():
		var r := sk.get_bone_rest(i)
		sk.set_bone_pose_rotation(i, sk.get_bone_pose_rotation(i).slerp(r.basis.get_rotation_quaternion(), k))
		sk.set_bone_pose_position(i, sk.get_bone_pose_position(i).lerp(r.origin, k))
	var spread := deg_to_rad(float(cfg.get("lying_spread", 6.0)))
	for side in [["L", 1.0], ["R", -1.0]]:
		var ua := _bone(sk, "upperarm." + side[0])
		var fa := _bone(sk, "forearm." + side[0])
		if ua < 0 or fa < 0:
			continue
		var d := sk.get_bone_global_pose(fa).origin - sk.get_bone_global_pose(ua).origin
		var now := atan2(d.x * side[1], -d.y)
		_turn(sk, "upperarm." + side[0], Vector3.BACK, (spread - now) * side[1] * k)


## Listening: the neck swings the head round toward the sound and tips it further over its ear. It
## does not point its face at you: it points an ear.
const LOOK_SHARE := {"chest": 0.12, "head": 0.34}


func _cock(sk: Skeleton3D, amt: float) -> void:
	var yaw := clampf(listen_yaw, -1.3, 1.3)
	_turn(sk, "chest", Vector3.UP, yaw * float(LOOK_SHARE["chest"]) * amt)
	for i in NECK_BONES.size():
		_turn(sk, NECK_BONES[i], Vector3.UP, yaw * 0.54 * NECK_SHARE[i] * amt)
	_turn(sk, "head", Vector3.UP, yaw * float(LOOK_SHARE["head"]) * amt)
	_turn(sk, "head", Vector3.BACK, -0.24 * amt)


# ====================================================================== the echo's burst
## Rings that fly out of its mouth and off the probe when the echo goes, so the pulse is a beat you
## can see and not just a pose. Three from each, staggered, growing and fading, with a violet flash
## behind them. Built once and hidden; `fire_echo()` starts them, and `set_look` fires it for you the
## moment the mode turns to "echo".
func _make_burst() -> void:
	for where in [_mouth, _probe]:
		if where == null:
			continue
		var light := OmniLight3D.new()
		light.light_color = GLOW
		light.omni_range = 2.4
		light.light_energy = 0.0
		light.shadow_enabled = false
		light.visible = false
		where.add_child(light)
		_flash.append(light)
		for i in 3:
			var m := StandardMaterial3D.new()
			m.albedo_color = Color(GLOW.r, GLOW.g, GLOW.b, 0.55)
			m.emission_enabled = true
			m.emission = GLOW
			m.emission_energy_multiplier = 6.0
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
			m.disable_receive_shadows = true
			var torus := TorusMesh.new()
			torus.inner_radius = 0.30
			torus.outer_radius = 0.38
			torus.material = m
			var mi := MeshInstance3D.new()
			mi.name = "EchoRing"
			mi.mesh = torus
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mi.visible = false
			# a torus lies in its own XZ plane, so stand it up to face the way the mouth or the wand
			# points (both markers point along their -Z)
			mi.rotation = Vector3(PI * 0.5, 0.0, 0.0)
			where.add_child(mi)
			_rings.append(mi)
			_ring_mats.append(m)


## Fire the echo's burst now. sono-brain can call this on the exact frame the fan goes out; set_look
## also calls it when the mode first becomes "echo".
func fire_echo() -> void:
	_burst = 0.0


func _process(delta: float) -> void:
	_update_drips()
	if _burst < 0.0:
		return
	_burst += delta
	if _burst > BURST_T:
		_burst = -1.0
		for mi in _rings:
			(mi as MeshInstance3D).visible = false
		for l in _flash:
			(l as OmniLight3D).visible = false
		return
	for l in _flash:
		var light := l as OmniLight3D
		light.visible = true
		light.light_energy = 5.0 * pow(1.0 - _burst / BURST_T, 2.2)
	for i in _rings.size():
		var mi := _rings[i] as MeshInstance3D
		# three rings per mouth/probe, each starting a beat after the one before it
		var t := _burst / BURST_T - 0.14 * float(i % 3)
		if t <= 0.0 or t >= 1.0:
			mi.visible = false
			continue
		mi.visible = true
		var r := 0.12 + BURST_R * t
		mi.scale = Vector3(r, r, r)
		# they fly out in front of whatever they hang on, and thin as they go
		mi.position = Vector3(0.0, 0.0, -0.10 - 1.5 * t)
		var m := _ring_mats[i] as StandardMaterial3D
		var a := (1.0 - t) * (1.0 - t)
		m.albedo_color = Color(GLOW.r, GLOW.g, GLOW.b, 0.65 * a)
		m.emission_energy_multiplier = 9.0 * a


# ====================================================================== the dripping
## Ultrasound gel really does drip off it: drops form at the mouth, the left hand and the wand's face,
## fall under gravity and are gone when they reach the floor. They are world-space particles, so they
## are left behind when it walks. More of them the more suspicious it is.
const DRIP_AMOUNT := 6
const DRIP_RATE_CALM := 0.16       ## amount_ratio when calm: about two drops a second from each place
const DRIP_RATE_TENSE := 0.6


func _make_drips(sk: Skeleton3D) -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.86, 0.90, 0.86, 0.62)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness = 0.04
	mat.metallic_specular = 0.9
	mat.clearcoat_enabled = true
	mat.clearcoat = 1.0
	mat.clearcoat_roughness = 0.03
	var drop := SphereMesh.new()
	drop.radius = 0.0055
	drop.height = 0.015          # a teardrop: taller than it is wide
	drop.radial_segments = 8
	drop.rings = 4
	drop.material = mat
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3.ZERO
	pm.spread = 0.0
	pm.initial_velocity_min = 0.0
	pm.initial_velocity_max = 0.0
	pm.gravity = Vector3(0.0, -9.8, 0.0)
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.012
	pm.scale_min = 0.6
	pm.scale_max = 1.4
	var hand := BoneAttachment3D.new()
	hand.name = "DripHandBone"
	hand.bone_name = "hand.L"
	sk.add_child(hand)
	# a drop of gel forms, hangs and lets go: each place gets its own emitter
	for where in [_mouth, hand, _probe]:
		if where == null:
			continue
		var p := GPUParticles3D.new()
		p.name = "GelDrip"
		p.amount = DRIP_AMOUNT
		p.amount_ratio = DRIP_RATE_CALM
		p.lifetime = 0.6
		p.randomness = 0.7
		p.local_coords = false
		p.fixed_fps = 0
		p.draw_pass_1 = drop
		p.process_material = pm
		p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# the drops fall a long way below where they were made (the neck can reach 2.7 m)
		p.visibility_aabb = AABB(Vector3(-1.5, -4.0, -1.5), Vector3(3.0, 4.2, 3.0))
		where.add_child(p)
		_drips.append(p)


## Each emitter's drops live exactly as long as the fall to the floor, so they vanish as they land
## and never sink through it. Off while it lies on a table (the floor is not under it there).
func _update_drips() -> void:
	if _drips.is_empty() or _model == null or not _model.is_inside_tree():
		return
	var floor_y := _model.global_position.y
	var ratio := lerpf(DRIP_RATE_CALM, DRIP_RATE_TENSE, clampf(maxf(suspicion, charge), 0.0, 1.0))
	var on := lying < 0.5
	for d in _drips:
		var p := d as GPUParticles3D
		p.emitting = on
		p.amount_ratio = ratio
		var h := maxf(p.global_position.y - floor_y, 0.1)
		var t := sqrt(2.0 * h / 9.8)
		if absf(t - p.lifetime) > 0.03:
			p.lifetime = t
