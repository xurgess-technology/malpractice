extends Node3D
## The local player's first-person hands (node "Hands" under the camera; docs/HANDS_AND_FEEDBACK.md
## "Held items in the hands"). The right hand holds the torch, the left hand the selected stack;
## bulky loot takes both hands and the torch tucks under the right arm. Every frame it
## poses both hands (rest pose for what is held, the wind-up / strike / recover of combat.action_of,
## walk bob, sway lagging the mouse, lower-and-raise on a new stack, lowered while sprinting, pulled
## in near walls) and puts HeldFirstPerson on the palm with the kind's grip.
##
## BETTER HANDS (2026-09-24): what the hand holds and how its fingers close round it come from the
## baked first-person grips (scripts/hands/grips.gd fp_held(), solved by tools/gripbake.gd): a fist
## round a saw's handle, a pinch on a clipboard's edge, fingers cupped round a bottle on the palm.
## The torch and the jab's syringe are held the same way. A kind with no bake falls back to the old
## grips.gd placement and a plain curl.
##
## Hands and held stacks render on HANDS_LAYER, which the flashlight does not light (it sits a hand's
## width away and would bleach them), and cast no shadows.

const Arms := preload("res://scripts/hands/fp_arms.gd")
const Poses := preload("res://scripts/hands/hand_poses.gd")
const Grips := preload("res://scripts/hands/grips.gd")
const WindupScript := preload("res://scripts/combat/windup.gd")
const ThrowPoseScript := preload("res://scripts/hands/throw_pose.gd")   # THROW HOOK

const HANDS_LAYER := 1 << 18
## First-person stack sizes: bulky / two-handed things fit this longest side, big loot this one.
const FP_BOTH_SIZE := 0.22
const FP_LOOT_SIZE := 0.13
const FP_FIST_SIZE := 0.26
## Seconds to lower and raise the hands when the stack changes.
const RAISE_TIME := 0.38
## How far in front of the camera the wall check reaches, and how far the hands pull back.
const WALL_REACH := 0.62
const WALL_PULL := 0.17
## Where each forearm runs to, camera space (the elbows, below and just behind the eye): the wrists
## bend toward them, so a hand can turn a handle anywhere and its sleeve still comes from the corner.
const ELBOW_L := Vector3(-0.3, -0.62, 0.08)
const ELBOW_R := Vector3(0.3, -0.62, 0.08)
## How fast the fingers move to a new shape (per second, exponential).
const SHAPE_RATE := 16.0

var player: Node = null
var arm_r: Node3D
var arm_l: Node3D
var torch: Node3D
var syringe: Node3D
## x/y scale of every placed position for the current field of view (Player.apply_fov sets it).
var fov_k := 1.0
## The pose each hand ended on last frame (tests and the gameshot read these).
var pose_r: Dictionary = {}
var pose_l: Dictionary = {}
## The finger shapes each hand ended on last frame (fp_arms shapes).
var shape_l: Dictionary = Arms.shape_from_curl(0.4)
var shape_r: Dictionary = Arms.shape_from_curl(1.0)
## The baked hold of the selected stack (grips.gd fp_held), {} when empty or not baked.
var held: Dictionary = {}

var _kind := ""
var _count := 0
var _raise := 0.0
var _bob := 0.0
var _speed := 0.0
var _sprint := 0.0
var _sway := Vector2.ZERO
var _last_look := Vector2.INF
var _pull := 0.0
var _stow := 0.0   ## 0..1: hands dropped out of view while the laptop map is up (hud.gd draws the laptop)
var _wall_t := 0.0
var _shake_t := 0.0
var _throw = ThrowPoseScript.new()   # THROW HOOK
var _torch_hold: Dictionary = {}
var _jab_hold: Dictionary = {}
var _lens_lit := -1


func setup(p: Node) -> void:
	player = p
	name = "Hands"
	var col: Color = p.colour
	arm_r = Arms.make_arm(1.0, col)
	add_child(arm_r)
	arm_l = Arms.make_arm(-1.0, col)
	add_child(arm_l)
	torch = Arms.make_torch()
	arm_r.add_child(torch)
	_torch_hold = Grips.fp_held("__torch", 1)
	torch.transform = _torch_hold.xf if not _torch_hold.is_empty() else Transform3D(Basis(), Vector3(0.0, 0.022, -0.01))
	syringe = preload("res://scripts/combat/combat.gd").make_syringe()
	syringe.name = "HandsSyringe"
	syringe.visible = false
	arm_l.add_child(syringe)
	_jab_hold = Grips.fp_held("__jab", 1)
	syringe.transform = _jab_hold.xf if not _jab_hold.is_empty() else Transform3D(Basis(), Vector3(0.0, 0.024, 0.0))
	dress(self)


## Put every mesh under `node` on the hands layer, shadowless.
static func dress(node: Node) -> void:
	if node is VisualInstance3D:
		(node as VisualInstance3D).layers = HANDS_LAYER
	if node is GeometryInstance3D:
		(node as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for c in node.get_children():
		dress(c)


## CUSTOMIZATION: the sleeves bake the outfit colour into their mesh, so a colour picked at the
## mirror is a mesh swap on both arms.
func recolour(col: Color) -> void:
	for arm in [arm_r, arm_l]:
		if arm == null:
			continue
		var sleeve := arm.find_child("Sleeve", true, false) as MeshInstance3D
		if sleeve != null:
			sleeve.mesh = Arms.sleeve_mesh(col)


## The selected stack changed: lower the hands and bring the new one up.
func held_changed(kind: String, count: int) -> void:
	if kind != _kind:
		_raise = 1.0
	_kind = kind
	_count = count
	held = Grips.fp_held(kind, Grips.fp_shown_count(kind, count)) if kind != "" else {}


## How big a stack of `kind` is drawn in first person.
static func fp_scale(kind: String) -> float:
	var fp := ItemModels.footprint(kind)
	var biggest := maxf(fp.x, maxf(fp.y, fp.z))
	var g := Grips.grip(kind)
	var spec: Dictionary = Grips.FP.get(kind, {})
	if int(g.hands) >= 2:
		return minf(1.0, FP_BOTH_SIZE / maxf(0.01, biggest))
	if spec.has("size"):
		return minf(1.0, float(spec.size) / maxf(0.01, biggest))
	if String(spec.get("grip", "palm")) in ["power", "hook"] or String(g.style) == "fist":
		return minf(1.0, FP_FIST_SIZE / maxf(0.01, biggest))   # a handle stays long enough to see past the fist
	if Items.is_loot(kind) and biggest > FP_LOOT_SIZE:
		return FP_LOOT_SIZE / biggest
	return 1.0


## Where the two hands and the thing between them sit at rest (no bob, sway or FOV): {xl, xr (the
## palm sockets), held (the HeldFirstPerson node), pivot (the Held pivot under it, scale k)}.
## update() uses the same numbers; tools/gripbake.gd solves the fingers against it.
static func two_hand_layout(kind: String, k: float, spread: float) -> Dictionary:
	var centre := Poses.BOTH_CENTRE
	var half := ItemModels.footprint(kind).x * k * 0.5 + spread
	var xl := Poses.xform(_offset(Poses.BOTH_LEFT, centre + Vector3(-half, 0.0, 0.0)))
	var xr := Poses.xform(_offset(Poses.mirror(Poses.BOTH_LEFT), centre + Vector3(half, 0.0, 0.0)))
	var g := Grips.grip(kind).duplicate()
	g.pos = (g.pos as Vector3) * k
	return {"xl": xl, "xr": xr, "held": Transform3D(Basis(), (xl.origin + xr.origin) * 0.5 + Vector3(0.0, 0.03, 0.0)),
		"pivot": Grips.transform_of(g), "half": half}


func update(delta: float) -> void:
	if player == null or not visible:
		return
	var g = player.game
	var act: Dictionary = g.combat.action_of(player) if g != null and g.combat != null else {}
	var grip := Grips.grip(_kind) if _kind != "" else {}
	var two := _kind != "" and int(grip.get("hands", 1)) >= 2
	var style := String(held.get("grip", "")) if not held.is_empty() else ("fist" if String(grip.get("style", "palm")) == "fist" else "palm")
	var fist := _kind != "" and style in ["power", "hook", "fist"]

	# ---- rest poses for what is held
	var rest_l: Dictionary = Poses.LEFT_EMPTY
	var rest_r: Dictionary = Poses.TORCH_GRIP if not _torch_hold.is_empty() else Poses.TORCH
	var centre := Poses.BOTH_CENTRE
	var half := 0.0
	if two:
		half = ItemModels.footprint(_kind).x * fp_scale(_kind) * 0.5 + float(held.get("spread", 0.0))
		rest_l = _offset(Poses.BOTH_LEFT, centre + Vector3(-half, 0.0, 0.0))
		rest_r = Poses.TORCH_TUCKED_GRIP if not _torch_hold.is_empty() else Poses.TORCH_TUCKED
	elif _kind != "":
		match style:
			"power", "fist":
				rest_l = Poses.LEFT_POWER if not held.is_empty() else Poses.LEFT_FIST
			"hook":
				rest_l = Poses.LEFT_HOOK
			"pinch":
				rest_l = Poses.LEFT_PINCH
			_:
				rest_l = Poses.LEFT_PALM
	var right_both := _offset(Poses.mirror(Poses.BOTH_LEFT), centre + Vector3(half, 0.0, 0.0))

	# ---- actions
	var pl: Dictionary = rest_l
	var pr: Dictionary = right_both if two else rest_r
	var jab := false
	var shove := false
	if not act.is_empty():
		match String(act.k):
			"jab":
				pl = Poses.action_pose(rest_l, Poses.JAB_GRIP if not _jab_hold.is_empty() else Poses.JAB, act)
				jab = true
			"shove":
				shove = true
				pl = Poses.action_pose(rest_l, Poses.SHOVE_LEFT, act)
				var keys_r := [Poses.mirror(Poses.SHOVE_LEFT[0]), Poses.mirror(Poses.SHOVE_LEFT[1])]
				pr = Poses.action_pose(pr, keys_r, act)
				if int(act.ph) == WindupScript.WINDUP:
					# Shaking as the charge builds.
					_shake_t += delta
					var amp := 0.002 + 0.007 * float(act.charge)
					var jig := Vector3(sin(_shake_t * 71.0), cos(_shake_t * 57.0), 0.0) * amp
					pl.p = (pl.p as Vector3) + jig
					pr.p = (pr.p as Vector3) - jig
	if two and (act.is_empty() or String(act.k) != "shove"):
		pr = right_both

	# ---- THROW HOOK: the drop key's charged throw (scripts/hands/throw_pose.gd)
	var saw_swing := not act.is_empty() and String(act.k) == "saw"   # the saw swings like the hammer
	var wind: float = WindupScript.saw_wind(act) if saw_swing else (float(player.throw_wind) if act.is_empty() else 0.0)
	_throw.update(delta, wind, two,
		float(player.swing_speed))   # TRINKETS chunk B: a reflex-hammer bonk is this pose, sped up
	if _throw.active():
		var ww: float = _throw.wind_w()
		var sw: float = _throw.strike_w()
		if _throw.two:
			# Both hands carry the thing's centre up over the head, then heave it out in front.
			var c: Vector3 = centre.lerp(Poses.THROW_BOTH_CENTRE[0], ww).lerp(Poses.THROW_BOTH_CENTRE[1], sw)
			var lw := Poses.blend(Poses.blend(Poses.BOTH_LEFT, Poses.THROW_BOTH_LEFT[0], ww), Poses.THROW_BOTH_LEFT[1], sw)
			# Full charge: a small tremble, the same on both palms so the thing between them shakes too.
			var jig: Vector3 = _throw.jig(0.0) * 0.0045
			if two:
				pl = _offset(lw, c + Vector3(-half, 0.0, 0.0) + jig)
				pr = _offset(Poses.mirror(lw), c + Vector3(half, 0.0, 0.0) + jig)
			else:
				# The last of it just left the hands: the left hand still follows through.
				pl = Poses.blend(pl, _offset(lw, c), maxf(ww, sw))
		else:
			# A fist swings its handle over the shoulder and down; an open hand throws from the palm.
			var keys: Array = Poses.THROW_FIST if fist and not held.is_empty() else Poses.THROW_LEFT
			pl = Poses.blend(Poses.blend(pl, keys[0], ww), keys[1], sw)

	# ---- life: bob, sway, raise, sprint, walls
	var speed01 := 0.0
	if player.is_on_floor():
		speed01 = clampf(Vector2(player.velocity.x, player.velocity.z).length() / C.SPRINT_SPEED, 0.0, 1.0)
	_speed = lerpf(_speed, speed01, clampf(delta * 8.0, 0.0, 1.0))
	_bob = fmod(_bob + delta * (7.5 + 4.0 * _speed) * maxf(_speed, 0.05), TAU)
	var sprint_on: bool = player.sprinting and act.is_empty() and not _throw.active()
	_sprint = move_toward(_sprint, 1.0 if sprint_on else 0.0, delta * 4.0)
	var look := Vector2(player.rotation.y, player.head.rotation.x)
	if _last_look == Vector2.INF:
		_last_look = look
	var dl := Vector2(wrapf(look.x - _last_look.x, -PI, PI), look.y - _last_look.y)
	_last_look = look
	var want_sway := Vector2(clampf(dl.x / maxf(delta, 0.001) * 0.012, -0.05, 0.05), clampf(dl.y / maxf(delta, 0.001) * 0.01, -0.04, 0.04))
	_sway = _sway.lerp(want_sway, clampf(delta * 9.0, 0.0, 1.0))
	_raise = maxf(0.0, _raise - delta / RAISE_TIME)
	_wall_t -= delta
	if _wall_t <= 0.0:
		_wall_t = 0.05
		_wall_target = _wall_check()
	_pull = lerpf(_pull, _wall_target, clampf(delta * 12.0, 0.0, 1.0))

	var bob := Vector3(sin(_bob) * 0.009, -absf(cos(_bob)) * 0.011, 0.0) * _speed
	var raise_e := Poses.smooth(_raise)
	var map_up: bool = g != null and g.get("trinkets") != null and _kind == "laptop" and g.trinkets.map_left(player) > 0.0
	_stow = move_toward(_stow, 1.0 if map_up else 0.0, delta * 5.0)
	var extra := bob + Vector3(_sway.x, -_sway.y, 0.0) + Vector3(0.0, -0.3 * raise_e, 0.05 * raise_e) \
		+ Vector3(0.02, -0.13, 0.07) * _sprint + Vector3(0.0, -0.05, WALL_PULL) * _pull \
		+ Vector3(0.0, -0.7, 0.0) * Poses.smooth(_stow)
	var tilt := Basis(Vector3.RIGHT, -0.55 * raise_e - 0.45 * _sprint - 0.2 * _pull)
	pose_l = pl
	pose_r = pr
	var xl := _placed(pl, extra, tilt)
	var xr := _placed(pr, extra, tilt)
	arm_l.transform = xl
	arm_r.transform = xr
	_aim_forearm(arm_l, xl, ELBOW_L)
	_aim_forearm(arm_r, xr, ELBOW_R)

	# ---- fingers: closed round what each hand holds (the bake), else the pose's plain curl
	var want_l: Dictionary
	if jab and not _jab_hold.is_empty():
		want_l = _jab_hold.shape
	elif _kind != "" and not held.is_empty():
		want_l = held.shape
	else:
		want_l = Arms.shape_from_curl(float(pl.c))
	var want_r: Dictionary
	if two and not held.is_empty() and not (held.get("shape_r", {}) as Dictionary).is_empty() and not shove:
		want_r = held.shape_r
	elif not two and not _torch_hold.is_empty():
		# The torch never leaves the fist, shove or not.
		want_r = _torch_hold.shape
	else:
		want_r = Arms.shape_from_curl(float(pr.c))
	var su := 1.0 - exp(-SHAPE_RATE * delta)
	shape_l = Arms.blend_shapes(shape_l, want_l, su)
	shape_r = Arms.blend_shapes(shape_r, want_r, su)
	Arms.apply(arm_l, shape_l, -1.0)
	Arms.apply(arm_r, shape_r, 1.0)

	# ---- the torch: in the right hand unless both hands carry something (then along the forearm);
	# its lens only glows while the light is on (the scanner tints it blue itself, scan_fx.gd).
	torch.visible = true
	if not _torch_hold.is_empty():
		torch.transform = _torch_hold.xf if not two else Transform3D(Basis(Vector3.RIGHT, -0.2), Vector3(0.0, -0.035, 0.07))
	_update_lens()
	syringe.visible = jab and int(act.ph) != WindupScript.RECOVER or (jab and float(act.u) < 0.5)

	# ---- the held stack
	var held_node: Node3D = player._held_fp
	if held_node != null:
		if two:
			# The midpoint of the two palms, facing forward, palm-up frame.
			var mid := (xl.origin + xr.origin) * 0.5 + Vector3(0.0, 0.03, 0.0)
			held_node.transform = Transform3D(tilt, mid)
		else:
			held_node.transform = xl
		for c in held_node.get_children():
			for part in c.get_children():
				if part is Node3D and part != syringe:
					(part as Node3D).visible = not syringe.visible


## FLASHLIGHT POSE follow-up: the first-person lens is dark while the light is off.
func _update_lens() -> void:
	var lens := torch.get_node_or_null("Lens") as MeshInstance3D
	if lens == null or bool(player.get("scan_holding")):
		_lens_lit = -1   # scan_fx owns the lens while scanning; take it back afterwards
		return
	var lit := 1 if player.torch_state() == 1 else 0
	if lit != _lens_lit:
		_lens_lit = lit
		lens.material_override = Arms.lens_material(lit == 1)


var _wall_target := 0.0


func _aim_forearm(arm: Node3D, x: Transform3D, elbow: Vector3) -> void:
	var wrist := x * (Arms.WRIST * Arms.HAND_SCALE)
	var e := Vector3(elbow.x * fov_k, elbow.y * fov_k, elbow.z)
	Arms.aim_forearm(arm, x.basis.inverse() * (e - wrist))


## 0..1: how much a wall in front of the camera pushes the hands back.
func _wall_check() -> float:
	var cam: Camera3D = player.camera
	if cam == null or not cam.is_inside_tree():
		return 0.0
	var space := cam.get_world_3d().direct_space_state
	var from := cam.global_position
	var basis := cam.global_transform.basis
	var best := WALL_REACH
	for dir in [Vector3(0.0, -0.25, -1.0), Vector3(0.35, -0.4, -1.0), Vector3(-0.35, -0.4, -1.0)]:
		var d: Vector3 = (basis * dir).normalized()
		var q := PhysicsRayQueryParameters3D.create(from, from + d * WALL_REACH)
		q.collision_mask = C.L_WORLD
		q.exclude = [player.get_rid()]
		var hit := space.intersect_ray(q)
		if not hit.is_empty():
			best = minf(best, from.distance_to(hit.position))
	return clampf((WALL_REACH - best) / (WALL_REACH - 0.25), 0.0, 1.0)


func _placed(pose: Dictionary, extra: Vector3, tilt: Basis) -> Transform3D:
	var x := Poses.xform(pose)
	var p := x.origin + extra
	return Transform3D(tilt * x.basis, Vector3(p.x * fov_k, p.y * fov_k, p.z))


static func _offset(pose: Dictionary, by: Vector3) -> Dictionary:
	var d := pose.duplicate()
	d.p = (pose.p as Vector3) + by
	return d
