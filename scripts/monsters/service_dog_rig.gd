extends Node3D
## The Service Dog's body. **A PLACEHOLDER**: the real quadruped (a Blender GLB, `monster/service_dog`)
## is being built on its own branch. Until it lands this is primitives on a few Node3D pivots, bent
## tall and lanky -- shoulders at about 1.1 m, the head near 1.5 m, about 2.4 m reared up -- so scale,
## sightlines and the timing of every state can be judged in the game. It is not meant to look right.
##
## `build(model)` prefers the GLB when Assets has it (Assets.has(KEY), i.e. the art branch has added
## the key and the file), and only then falls back to the primitives. Either way the Monster talks to
## it through the same few inputs and sockets, and nothing else assumes a shape:
##   speed      m/s over the ground (the gait's rate)
##   moving     whether it is walking at all
##   rear       0..1  on all fours -> standing on its hind legs, jaws wide (the drain)
##   head_down  0..1  nose to the floor (setting an item down, picking one up)
##   growl      0..1  jaw open, head shaking; set by the Monster when a growl plays
##   look_yaw   radians the head turns toward whoever it is looking at (positive: its left)
##   carrying   an item is in its mouth (the jaw stays a little open)
##   lying      0..1  sedated, on its side
##   daze, rise, stagger   the shove's stun window (combat.stun_pose writes them, as for the Hive)
##   set_drain_glow(v)     0..1 the orb at the back of its throat
## Sockets: `mouth` (the carried item; origin between the jaws, -Z along the snout; mouth_world()),
## `orb` (a node named `Orb`: its own mesh, NOT part of the head's material, so a later task can take
## it out of the body; orb_world()), and `Head` (Monster.eye_transform).
##
## GLB contract for the art branch (what this file does with a real model, and all it needs):
##   clips through Assets.anim_name(KEY, logical): "idle", "walk" (on all fours; the retrieve trot is
##     "walk" played faster), "rear_up" (all fours -> standing, jaws opening, ~0.6-0.8 s), "drain_idle"
##     (standing, jaws wide, head on the target, throat pulsing), "upright_walk" (slow stiff biped walk),
##     "drop_down" (standing -> all fours, jaws closing, ~0.4 s). A missing clip falls back to
##     idle/walk. The tail's slow wag is the art's, in every clip.
##   the orb: a node named `Orb` (a MeshInstance3D, or a node with one under it), anywhere in the
##     model; set_drain_glow drives its emission. A `Site_orb` node or a bone `throat` works as the
##     socket if the mesh is somewhere else.
##   the mouth socket: a `Site_mouth` node, else a BoneAttachment3D on bone `jaw` or `head`; `Head`
##   rides the `head` bone the same way.

const Shapes := preload("res://scripts/monsters/shapes.gd")
## The brain's timings (REAR_RISE, REAR_DROP, OFFER_TIME): a one-shot clip is played at whatever rate
## makes it last exactly as long as the state it shows, whatever length the art authored it at.
const DogBrain := preload("res://scripts/monsters/service_dog_brain.gd")

const KEY := "monster/service_dog"
## The art track's own poser for that GLB (service-dog-art: a SkeletonModifier3D `DogPoser` with the
## throat orb, the tail wag, the head-look). When the file is there, the GLB is built through it and
## this node drives it; when it is not, the GLB (if any) is built generically below.
const ART_RIG := "res://scripts/monsters/dog_rig.gd"

## Proportions (metres). Hips a hair lower than the shoulders; everything too long.
const HIP_Y := 1.03
const SHOULDER_Y := 1.08
const BODY_LEN := 0.95
const LEG_UP := 0.52
const LEG_LOW := 0.56
const HIP_W := 0.13
const NECK := Vector3(0.0, 0.46, -0.30)
## How far a full rear tips the body up (radians), and how far a nose-down tips it forward.
const REAR_TILT := 1.2
const BOW_TILT := 0.22
## Ground covered per full gait cycle.
const STRIDE := 1.35

## The orb: pale, a little green, like something at the bottom of a pool.
const ORB_COLOR := Color(0.78, 0.96, 0.9)
const ORB_R := 0.03
## Emission at glow 0 and at glow 1, and the throat pulse (cycles a second) while it drains.
const ORB_DIM := 0.5
const ORB_BRIGHT := 9.0
const ORB_PULSE_HZ := 1.1

const SKIN := Color("b9aea4")
const VEST := Color("5a1c1c")
const PATCH := Color("d8d2c4")

var speed := 0.0
var moving := false
var rear := 0.0
var head_down := 0.0
var growl := 0.0
var look_yaw := 0.0
## World point the head looks at (its surgeon's face), Vector3.INF for none. The art poser tracks it
## with bones; the placeholder only uses look_yaw.
var look_target := Vector3.INF
var carrying := false
var lying := 0.0
var daze := 0.0
var rise := 0.0
var stagger := 0.0
var drain_glow := 0.0
## Kept so a Monster written for the old rig can still set it; nothing reads it now.
var lunge := 0.0

var mouth: Node3D = null
var head: Node3D = null
## The throat orb (named `Orb`), its mesh and material, and the small light it throws on its jaws.
var orb: Node3D = null
var _orb_mesh: MeshInstance3D = null
var _orb_mat: StandardMaterial3D = null
var _orb_light: OmniLight3D = null
var _last_rear := 0.0
## The art track's DogPoser (dog_rig.gd) when the GLB was built through it, else null.
var poser: Node = null
var _look_w := 0.0
## How far the mouth reaches ahead of the body's middle on all fours, measured (see reach()).
var _reach := -1.0
var glb := false

var _hips: Node3D
var _chest: Node3D
var _neck: Node3D
var _skull: Node3D
var _jaw: Node3D
var _tail: Node3D
## [pivot, knee, side (+1 left), front (bool), phase offset]
var _legs: Array = []
var _phase := 0.0
var _t := 0.0
var _model: Node3D = null


## Put the body under `model` (a MonsterModel). Always succeeds: the GLB when there is one, else
## the primitives.
static func build(model: Node3D) -> Node3D:
	var r: Node3D = (load("res://scripts/monsters/service_dog_rig.gd") as GDScript).new()
	r.name = "ServiceDogRig"
	model.add_child(r)
	r._model = model
	if not r._try_glb(model):
		r._make()
		model.rig = r
	return r


func _try_glb(model: Node3D) -> bool:
	if not Assets.has(KEY):
		return false
	if ResourceLoader.exists(ART_RIG) and _try_art_rig(model):
		return true
	var root: Node3D = Assets.spawn(KEY)
	if root == null:
		return false
	add_child(root)
	glb = true
	model.rig = root
	model.anim = Assets.anim_player(root)
	var skels := root.find_children("*", "Skeleton3D", true, false)
	model.skeleton = skels[0] if not skels.is_empty() else null
	var site := root.find_child("Site_mouth", true, false) as Node3D
	mouth = site if site != null else _bone_node(model.skeleton, ["jaw", "head"], "MouthBone")
	if mouth == null:
		mouth = Node3D.new()
		mouth.position = Vector3(0.0, 1.2, -0.9)
		add_child(mouth)
	orb = root.find_child("Orb", true, false) as Node3D
	if orb == null:
		orb = root.find_child("Site_orb", true, false) as Node3D
	if orb == null:
		orb = _bone_node(model.skeleton, ["throat", "jaw", "head"], "OrbBone")
	_orb_mesh = orb as MeshInstance3D if orb is MeshInstance3D else (orb.find_children("*", "MeshInstance3D", true, false).front() if orb != null and not orb.find_children("*", "MeshInstance3D", true, false).is_empty() else null)
	if _orb_mesh == null and orb != null:
		_make_orb(orb)   # the model has a socket but no orb of its own: ours goes there
	elif _orb_mesh != null:
		_orb_mat = StandardMaterial3D.new()
		_orb_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_orb_mat.albedo_color = ORB_COLOR
		_orb_mat.emission_enabled = true
		_orb_mat.emission = ORB_COLOR
		_orb_mesh.material_override = _orb_mat
		_add_orb_light(orb)
	var hb := _bone_node(model.skeleton, ["head"], "HeadBone")
	head = Node3D.new()
	head.name = "Head"
	head.rotation.y = PI   # Head's +Z is the face; the model faces -Z
	(hb if hb != null else self).add_child(head)
	return true


## The art track's build: its dog_rig.gd spawns the GLB, points model.rig / skeleton / anim at it and
## adds its DogPoser (the orb, `Head`). Its root is then moved under this node so the lying roll
## applies to it, and this node takes the poser's orb and head as its own sockets.
func _try_art_rig(model: Node3D) -> bool:
	var art: GDScript = load(ART_RIG) as GDScript
	if art == null or not bool(art.call("build", model)):
		return false
	glb = true
	var root: Node3D = model.rig
	if root != null and root.get_parent() != self:
		root.reparent(self, false)
	var sk: Skeleton3D = model.skeleton
	poser = sk.get_node_or_null("DogPoser") if sk != null else null
	orb = poser.get_node_or_null("OrbAttach/Orb") as Node3D if poser != null else null
	if orb == null and root != null:
		orb = root.find_child("Orb", true, false) as Node3D
	head = sk.get_node_or_null("Head") as Node3D if sk != null else null
	var site := root.find_child("Site_mouth", true, false) as Node3D if root != null else null
	mouth = site if site != null else _bone_node(sk, ["jaw", "head"], "MouthBone")
	if mouth == null:
		mouth = Node3D.new()
		mouth.position = Vector3(0.0, 1.2, -0.9)
		add_child(mouth)
	return true


func _bone_node(sk: Skeleton3D, names: Array, node_name: String) -> Node3D:
	if sk == null:
		return null
	for n in names:
		if sk.find_bone(n) >= 0:
			var ba := BoneAttachment3D.new()
			ba.name = node_name
			ba.bone_name = n
			sk.add_child(ba)
			return ba
	return null


# =========================================================================
# the placeholder body
# =========================================================================

func _make() -> void:
	var skin := Shapes.mat(SKIN, {"mottle": 0.22, "vein": 0.35, "stain_amt": 0.25, "stain_col": Color("6d5a4e"), "sss": 0.25})
	var dark := Shapes.flat(Color("2a2320"), 0.8)
	var vest := Shapes.mat(VEST, {"mottle": 0.1, "weave": 0.4, "stain_amt": 0.2})
	var patch := Shapes.flat(PATCH, 0.7)
	var eye_white := Shapes.flat(Color("e9e4d8"), 0.25)
	var pupil := Shapes.flat(Color("15110f"), 0.2)

	# Hips: the rear pivot. The whole body tips up around it.
	_hips = Node3D.new()
	_hips.name = "Hips"
	_hips.position = Vector3(0.0, HIP_Y, BODY_LEN * 0.5)
	add_child(_hips)
	var torso := Node3D.new()
	torso.name = "Torso"
	_hips.add_child(torso)
	# A long, narrow, rib-sprung trunk: lathed along -Z by laying a Y lathe on its side.
	var trunk := Shapes.mesh_node(Shapes.lathe([
		[0.0, 0.10, 0.12], [0.15, 0.13, 0.15], [0.42, 0.12, 0.17], [0.7, 0.15, 0.21], [0.9, 0.14, 0.18], [1.02, 0.09, 0.11],
	], 14, 0.0, 0.0, 0.03, 7), skin)
	trunk.rotation.x = -PI * 0.5
	trunk.position = Vector3(0.0, 0.02, 0.06)
	torso.add_child(trunk)
	# Ribs you can count.
	for i in 5:
		var z := -0.5 - float(i) * 0.07
		for s in [-1.0, 1.0]:
			var rib := Shapes.ellipsoid(Vector3(0.02, 0.1, 0.03), skin, Vector3(s * 0.135, -0.03, z), 8)
			rib.rotation.z = s * 0.25
			torso.add_child(rib)
	# The vest, the one thing about it that is trying to look official.
	torso.add_child(Shapes.box(Vector3(0.30, 0.2, 0.42), vest, Vector3(0.0, 0.07, -0.55)))
	for s in [-1.0, 1.0]:
		torso.add_child(Shapes.box(Vector3(0.012, 0.11, 0.22), patch, Vector3(s * 0.152, 0.07, -0.55)))
	torso.add_child(Shapes.box(Vector3(0.05, 0.14, 0.05), dark, Vector3(0.0, 0.2, -0.62)))   # the harness handle
	Shapes.bake(torso, "service_dog|torso")

	_tail = Node3D.new()
	_tail.name = "Tail"
	_tail.position = Vector3(0.0, 0.04, 0.06)
	_hips.add_child(_tail)
	var tail_mesh := Shapes.cylinder(0.022, 0.62, skin, Vector3(0.0, 0.0, 0.31), 0.006, 6)
	tail_mesh.rotation.x = PI * 0.5
	_tail.add_child(tail_mesh)

	_chest = Node3D.new()
	_chest.name = "Chest"
	_chest.position = Vector3(0.0, SHOULDER_Y - HIP_Y, -BODY_LEN)
	_hips.add_child(_chest)

	for s in [1.0, -1.0]:
		_legs.append(_make_leg(_hips, Vector3(s * HIP_W, -0.02, 0.0), skin, s, false, 0.0 if s > 0.0 else PI))
		_legs.append(_make_leg(_chest, Vector3(s * (HIP_W - 0.01), -0.04, 0.0), skin, s, true, PI if s > 0.0 else 0.0))

	_neck = Node3D.new()
	_neck.name = "Neck"
	_neck.position = Vector3(0.0, 0.06, -0.04)
	_chest.add_child(_neck)
	var neck_mesh := Shapes.cylinder(0.055, 1.0, skin, Vector3.ZERO, 0.045, 8)
	_neck.add_child(neck_mesh)
	Shapes.stretch_between(neck_mesh, Vector3.ZERO, NECK)

	_skull = Node3D.new()
	_skull.name = "Skull"
	_skull.position = NECK
	_neck.add_child(_skull)
	# A head too long for the body and held too still: cranium, a narrow snout, flat ears.
	_skull.add_child(Shapes.ellipsoid(Vector3(0.085, 0.09, 0.12), skin, Vector3(0.0, 0.02, -0.02), 12))
	var snout := Shapes.ellipsoid(Vector3(0.05, 0.045, 0.17), skin, Vector3(0.0, -0.005, -0.2), 10)
	_skull.add_child(snout)
	_skull.add_child(Shapes.ellipsoid(Vector3(0.022, 0.018, 0.02), dark, Vector3(0.0, 0.01, -0.36), 8))   # the nose
	for s in [-1.0, 1.0]:
		var ear := Shapes.ellipsoid(Vector3(0.02, 0.07, 0.04), skin, Vector3(s * 0.07, 0.07, 0.07), 8)
		ear.rotation = Vector3(0.9, 0.0, s * 0.5)
		_skull.add_child(ear)
		# Human eyes, facing forward like a person's. This is most of what is wrong with it.
		_skull.add_child(Shapes.ellipsoid(Vector3(0.026, 0.02, 0.012), eye_white, Vector3(s * 0.042, 0.04, -0.105), 10))
		_skull.add_child(Shapes.ellipsoid(Vector3(0.009, 0.009, 0.006), pupil, Vector3(s * 0.042, 0.04, -0.115), 8))

	_jaw = Node3D.new()
	_jaw.name = "Jaw"
	_jaw.position = Vector3(0.0, -0.035, -0.05)
	_skull.add_child(_jaw)
	_jaw.add_child(Shapes.ellipsoid(Vector3(0.042, 0.022, 0.15), skin, Vector3(0.0, -0.015, -0.14), 10))
	# Teeth: a row of small pale pegs, only seen when it opens up.
	for i in 6:
		for s in [-1.0, 1.0]:
			_jaw.add_child(Shapes.cylinder(0.006, 0.03, eye_white, Vector3(s * 0.03, 0.01, -0.06 - float(i) * 0.035), 0.001, 5))

	mouth = Node3D.new()
	mouth.name = "Mouth"
	mouth.position = Vector3(0.0, -0.03, -0.2)
	_skull.add_child(mouth)

	# The orb: at the back of the throat, where the jaw hinges, so it shows when the jaws open wide.
	var socket := Node3D.new()
	socket.name = "OrbSocket"
	socket.position = Vector3(0.0, -0.058, -0.085)
	_skull.add_child(socket)
	_make_orb(socket)

	head = Node3D.new()
	head.name = "Head"
	head.position = Vector3(0.0, 0.0, -0.02)
	head.rotation.y = PI   # Monster.eye_transform: +Z is the face, and this body faces -Z
	_skull.add_child(head)

	for n in find_children("*", "MeshInstance3D", true, false):
		(n as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	tick(0.0)


## The orb itself: its own node and material (never baked into the head), so it can be taken out
## of the body later. A dim glow at rest; set_drain_glow brings it up.
func _make_orb(parent: Node3D) -> void:
	var mi := MeshInstance3D.new()
	mi.name = "Orb"
	var sm := SphereMesh.new()
	sm.radius = ORB_R
	sm.height = ORB_R * 2.0
	sm.radial_segments = 12
	sm.rings = 6
	mi.mesh = sm
	_orb_mat = StandardMaterial3D.new()
	_orb_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_orb_mat.albedo_color = ORB_COLOR
	_orb_mat.emission_enabled = true
	_orb_mat.emission = ORB_COLOR
	_orb_mat.emission_energy_multiplier = ORB_DIM
	mi.material_override = _orb_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	orb = mi
	_orb_mesh = mi
	_add_orb_light(parent)


func _add_orb_light(parent: Node3D) -> void:
	_orb_light = OmniLight3D.new()
	_orb_light.name = "OrbLight"
	_orb_light.light_color = ORB_COLOR
	_orb_light.omni_range = 1.4
	_orb_light.light_energy = 0.0
	_orb_light.shadow_enabled = false
	_orb_light.visible = false
	parent.add_child(_orb_light)


## 0..1: the orb's brightness (Monster sets it every frame from the replicated `og`).
func set_drain_glow(v: float) -> void:
	drain_glow = clampf(v, 0.0, 1.0)
	if poser != null and poser.has_method("set_drain_glow"):
		poser.set_drain_glow(drain_glow)   # the art's own orb material


## Where the orb is this frame (the thread's far end).
func orb_world() -> Vector3:
	if orb != null and orb.is_inside_tree():
		return orb.global_position
	return mouth_world().origin


func _tick_orb() -> void:
	if _orb_mat == null:
		return
	var pulse := 1.0 + 0.3 * sin(_t * TAU * ORB_PULSE_HZ) * drain_glow
	_orb_mat.emission_energy_multiplier = lerpf(ORB_DIM, ORB_BRIGHT, drain_glow) * pulse
	if _orb_mesh != null:
		_orb_mesh.scale = Vector3.ONE * (1.0 + 0.18 * drain_glow * sin(_t * TAU * ORB_PULSE_HZ))
	if _orb_light != null:
		_orb_light.visible = drain_glow > 0.2
		_orb_light.light_energy = 0.9 * drain_glow * pulse


func _make_leg(parent: Node3D, at: Vector3, skin: Material, side: float, front: bool, phase: float) -> Array:
	var pivot := Node3D.new()
	pivot.name = ("Front" if front else "Hind") + ("L" if side > 0.0 else "R")
	pivot.position = at
	parent.add_child(pivot)
	var up := Shapes.cylinder(0.05 if not front else 0.042, LEG_UP, skin, Vector3(0.0, -LEG_UP * 0.5, 0.0), 0.032, 8)
	pivot.add_child(up)
	var knee := Node3D.new()
	knee.position = Vector3(0.0, -LEG_UP, 0.0)
	pivot.add_child(knee)
	knee.add_child(Shapes.ellipsoid(Vector3(0.035, 0.04, 0.035), skin, Vector3.ZERO, 8))
	knee.add_child(Shapes.cylinder(0.03, LEG_LOW, skin, Vector3(0.0, -LEG_LOW * 0.5, 0.0), 0.02, 8))
	# Long, splayed toes: more hand than paw.
	var paw := Node3D.new()
	paw.position = Vector3(0.0, -LEG_LOW, 0.0)
	knee.add_child(paw)
	for i in 4:
		var toe := Shapes.cylinder(0.009, 0.1, skin, Vector3.ZERO, 0.004, 5)
		toe.rotation = Vector3(-PI * 0.5 + 0.1, (float(i) - 1.5) * 0.25, 0.0)
		toe.position = Vector3((float(i) - 1.5) * 0.016, 0.0, -0.05)
		paw.add_child(toe)
	return [pivot, knee, side, front, phase]


# =========================================================================
# every frame
# =========================================================================

func tick(delta: float) -> void:
	_t += delta
	_measure_reach()
	_tick_orb()
	_tick_lying()
	if glb:
		_tick_glb()
		return
	if _hips == null:
		return
	var gait := clampf(speed / 2.6, 0.0, 1.0) if moving and lying < 0.5 else 0.0
	_phase = wrapf(_phase + delta * maxf(speed, 0.0) / STRIDE * TAU, 0.0, TAU)
	var up := rear * rear * (3.0 - 2.0 * rear)
	var bow := maxf(head_down, daze * 0.85) * (1.0 - up)
	var tilt := up * REAR_TILT - bow * BOW_TILT
	# Upright it bobs with its steps; standing still it breathes, slowly, not quite in rhythm.
	var bob := sin(_phase * 2.0) * 0.025 * gait + sin(_t * 1.3) * 0.006
	_hips.rotation.x = tilt + sin(_phase * 2.0) * 0.02 * gait
	_hips.position.y = HIP_Y + bob - bow * 0.08 - daze * 0.22
	_hips.rotation.z = sin(_t * 19.0) * 0.08 * stagger
	for leg in _legs:
		var pivot: Node3D = leg[0]
		var knee: Node3D = leg[1]
		var front: bool = leg[3]
		var ph: float = _phase + float(leg[4])
		var swing := sin(ph) * 0.42 * gait
		var lift := maxf(0.0, cos(ph)) * 0.7 * gait
		if front:
			# Standing, the front legs hang a little limp off its chest, swaying with it.
			var hang := -tilt + 0.3 + sin(_t * 1.7 + float(leg[2])) * 0.05
			pivot.rotation.x = lerpf(-0.12 + swing + bow * 0.5, hang, up)
			knee.rotation.x = lerpf(0.25 + lift + bow * 0.9, -0.45, up)
		else:
			# Hind legs stay under it whatever the body does.
			var biped_step := sin(_phase) * 0.35 * gait
			pivot.rotation.x = -tilt + lerpf(0.22 + swing, 0.05 + biped_step, up)
			knee.rotation.x = lerpf(-0.45 - lift, -0.12 - maxf(0.0, cos(_phase)) * 0.5 * gait, up)
	# The neck: up and craning forward on all fours, straight up the spine's line when reared, down to
	# the floor when it sets something down or picks it up.
	var shake := sin(_t * 31.0) * 0.06 * growl
	# Reared, the neck comes forward over the top of you rather than following the spine up.
	var neck_pitch := lerpf(0.0, -1.45, bow) - up * (REAR_TILT + 0.35) - 0.12 * growl
	_neck.rotation = Vector3(neck_pitch, clampf(look_yaw, -0.9, 0.9) * (1.0 - bow * 0.7), shake)
	# The head's pitch in the world: level on all fours, nose down over you reared, to the floor bowed.
	var head_world := -0.3 * up - 0.9 * bow + 0.08 * growl
	_skull.rotation.x = head_world - (tilt + neck_pitch)
	_skull.rotation.z = sin(_t * 0.7) * 0.05 * (1.0 - growl)   # a slow tilt, like it is trying to work you out
	var jaw := 0.14 if carrying else 0.0
	jaw = maxf(jaw, 0.38 * growl + sin(_t * 23.0) * 0.05 * growl)
	# Standing, the jaws open wide as it rises and stay open: the orb shows in the throat.
	jaw = maxf(jaw, 0.95 * up)
	_jaw.rotation.x = jaw
	_tail.rotation = Vector3(-0.35 + up * 0.9 + sin(_t * 2.1) * 0.05, sin(_t * (1.0 if up > 0.5 else 6.0)) * 0.12 * (1.0 - growl), 0.0)


## Sedated: on its side. The whole body rolls about its long axis and settles on the floor (every
## machine, GLB or not; the Monster's collider lies down on its own).
func _tick_lying() -> void:
	var e := lying
	rotation.z = -e * PI * 0.5
	position = Vector3(-e * 0.62, e * 0.2, 0.0)


func _tick_glb() -> void:
	if _model == null or not _model.has_method("play"):
		return
	_tick_poser()
	var rising := rear > _last_rear + 0.0001
	var falling := rear < _last_rear - 0.0001
	_last_rear = rear
	var clip := "idle"
	var rate := 1.0
	if lying > 0.5:
		clip = "idle"
		rate = 0.0
	elif rising and rear < 0.98:
		clip = "rear_up"
		rate = _fit(clip, DogBrain.REAR_RISE)
	elif falling and rear > 0.02:
		clip = "drop_down"
		rate = _fit(clip, DogBrain.REAR_DROP)
	elif rear >= 0.98:
		clip = "upright_walk" if moving else "drain_idle"
		rate = clampf(speed / 1.8, 0.6, 2.0) if moving else 1.0
	elif head_down > 0.3 and not moving and Assets.anim_name(KEY, "place") != "":
		clip = "place"   # the art's PlaceItem: setting an item down, or nosing one up
		rate = _fit(clip, DogBrain.OFFER_TIME)
	elif growl > 0.3 and not moving and Assets.anim_name(KEY, "growl") != "":
		clip = "growl"
	elif moving:
		clip = "walk"
		rate = clampf(speed / 1.4, 0.5, 2.5)
	if Assets.anim_name(KEY, clip) == "":
		clip = "walk" if moving else "idle"
	_model.play(clip, rate, 0.15)


## The rate that makes the logical clip `clip` last `seconds` (1.0 when the clip is missing).
func _fit(clip: String, seconds: float) -> float:
	var anim: AnimationPlayer = _model.anim if _model != null else null
	var real := Assets.anim_name(KEY, clip)
	if anim == null or real == "" or not anim.has_animation(real) or seconds <= 0.0:
		return 1.0
	return clampf(anim.get_animation(real).length / seconds, 0.25, 4.0)


## Flat metres from the body's middle to its mouth, standing on all fours with its head up. Measured
## off the body itself whenever it is in that pose (so the art's model and the placeholder each give
## their own), and a sensible guess until it has been.
func reach() -> float:
	return _reach if _reach > 0.0 else 1.35


func _measure_reach() -> void:
	if rear > 0.01 or head_down > 0.01 or lying > 0.01 or daze > 0.01 or mouth == null or not mouth.is_inside_tree():
		return
	var o: Vector3 = (_model as Node3D).global_position if _model != null else global_position
	var mw: Vector3 = mouth_world().origin
	var r := Vector2(mw.x - o.x, mw.z - o.z).length()
	_reach = r if _reach < 0.0 else lerpf(_reach, r, 0.1)


## The art poser's own inputs (dog_rig.gd): the head tracks its surgeon, ears pin back while it
## growls or stands, and a low constant tremor (the art's "wrong stillness").
func _tick_poser() -> void:
	if poser == null:
		return
	var sk: Skeleton3D = _model.skeleton if _model != null else null
	var want := 1.0 if look_target.is_finite() and lying < 0.5 else 0.0
	_look_w = move_toward(_look_w, want, 0.05)
	if look_target.is_finite() and sk != null:
		poser.look_at = sk.global_transform.affine_inverse() * look_target   # skeleton space
	poser.look_weight = _look_w * (1.0 - head_down)
	poser.ear_alert = maxf(growl, rear)
	poser.twitch = 0.35 * (1.0 - lying)


func mouth_world() -> Transform3D:
	if mouth != null and mouth.is_inside_tree():
		return mouth.global_transform
	return global_transform * Transform3D(Basis(), Vector3(0.0, 1.2, -0.95))
