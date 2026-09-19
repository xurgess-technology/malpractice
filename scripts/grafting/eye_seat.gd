extends Node3D
## GRAFTING chunk C: the forceps eye step. eye_ops.gd creates this as a child for two variants and
## hands every Minigame call to it; it reports through the owner (owner.finish / owner.progress).
## There is no botching in either: the graft sets `no_fail`, and every mistake is just a retry.
##
##   grab  (Eyeball Grafting, step 3)   the new eye waits in the specimen vat on the table: take it
##                                      out and seat it in the empty socket. {"eye_seated": true}.
##   place (Eyeball Extraction, step 4) the cut-free eye lies in the socket: lift it out and drop it
##                                      in the vat on the table. {"eye_in_vat": true}.
##
## Both are the same trip, one each way: SOURCE -> carry -> TARGET. How hard the trip is depends on
## which way it goes, because one is millimetre work on somebody's face and the other is dropping a
## dead monster's eye in a jar.
##
## grab, into a socket -- the careful one:
##   SOURCE  Put the forceps over the eye in the vat and hold S to lower them into the fluid. Hold
##           left click and the jaws close on the nerve just above it.
##   CARRY   Hold W to lift it clear, then draw it across. It hangs on the nerve and lags, so
##           whipping the hand about, or running too far ahead of it, shakes it loose and it drops
##           back in the vat. Pick it up and try again; it costs nothing.
##   SEAT    Over the socket (its ring turns green), hold S and it goes in under slow, steady
##           pressure, turning so the pupil ends up facing out.
##
## place, into the vat -- 2026-09-19, pick it up, drag it over, let go, and nothing else:
##   SOURCE  Hold left click anywhere near the loose eye (it is lying in an open socket) and the
##           jaws take it. No lowering, no aiming.
##   CARRY   Move the mouse. It still swings on its nerve, but no speed and no distance can shake
##           it out: this step cannot be lost.
##   DROP    Let go over the vat and it falls in. Let go anywhere else and it drops back in the
##           socket, and you pick it up again. Either way it costs nothing.
##
## SETTLE  Home. The jaws open, it settles with a soft squelch, and the step finishes.
## A stir's shake never drops it (on_jolt).
##
## 2026-09-19: the eye comes out of the real `specimen_vat` standing on the table (ctx.vat, from
## Vats.vat_on_table) instead of a steel tray. This draws its own open copy of the vat where the
## real one stands and hides the real one while the step runs, and W / S raise and lower the
## forceps, instead of the tips diving when the mouse went past a point.

const Eyes := preload("res://scripts/grafting/eyes.gd")
const MinigameBase := preload("res://scripts/surgery/minigame.gd")

enum Stage { SOURCE, HELD, SEATING, SETTLE, DONE }

## Where the vat stands on the work plane when there is no real one to measure (the minigame lab),
## and how far below the eyes the table top is.
const VAT_AT_FALLBACK := Vector2(-0.04, -0.20)
const TABLE_Y_FALLBACK := -0.13
## The vat's jar (vats.gd's model, minus the lid -- it is open while you work out of it): the glass
## radius and how far above the table's steel the fluid sits.
const VAT_R := 0.062
const VAT_FLUID_Y := 0.035
## How far off the vat's centre the tips still count as in it (its mouth is wide), and off the
## socket's centre.
const VAT_REACH := 0.032
const SOCKET_REACH := 0.016
## `place` is the easy way round: a wide grab on the loose eye, a wide mouth to let go over, and
## forceps that raise and lower themselves.
const PLACE_GRAB := 0.055
const PLACE_DROP := 0.075
const PLACE_DEPTH_RATE := 3.0
## No further out on the work plane than this: the close-up view has to show both ends of the trip.
const VAT_MAX_OUT := 0.24
const TIP_TAU := 0.05
const TIP_SPEED := 0.30          # m/s the tips can follow the hand
const JAW_CLOSE_RATE := 5.0
const JAW_OPEN_RATE := 7.0
const JAW_ON := 0.6
const DEPTH_RATE := 0.9          # how fast W and S raise and lower the forceps (per second)
const DEEP_ENOUGH := 0.8         # this far down, the jaws are on the eye
const LIFT_CLEAR := 0.55         # above this it is still down in the vat (or the socket)
const HIGH_Y := 0.11             # the tips' carrying height over the work plane (clear of the rim)
const SWING_TAU := 0.13          # how far the eye lags behind the tips on its nerve
const SLACK_DROP := 0.021        # that far behind and it shakes out of the jaws
const CARRY_MAX_SPEED := 0.19    # m/s: faster than this and it shakes loose too
const SEAT_MAX_SPEED := 0.030    # hand faster than this while it goes in and it stalls instead
const SETTLE_TIME := 0.7
const ARM_LEN := 0.05            # the forceps' arms, hinge to tip

var owner_mg                     # the eye_ops Minigame that owns this (untyped: done, progress, finish)
var ctx: Dictionary = {}
var eye_kind := "eye_hive"
var eye_r := 0.0135
## "grab": the vat hands the eye to the socket. "place": the socket hands it to the vat.
var mode := "grab"

# ---- replicated state ----
var tip := Vector2.ZERO
var eye := Vector2.ZERO
var jaw := 0.0
var depth := 0.0                 # 0 at carrying height, 1 as low as the tips go where they are
var sink := 0.0                  # 0 on the rim .. 1 home in the target
var settle := 0.0
var stage: int = Stage.SOURCE
var drops := 0

# ---- operator only ----
var _empty := false              # the jaws closed on nothing: let go before trying again
var _speed := 0.0
var _jolt_t := 0.0
var _hint := ""
var _hint_t := 0.0
var _time := 0.0

# ---- visuals ----
var _built := false
var _tool: Node3D
var _arms: Array[Node3D] = []
var _eye_node: MeshInstance3D
var _nerve: MeshInstance3D
var _vat: Node3D
var _source_ring: MeshInstance3D
var _source_ring_mat: StandardMaterial3D
var _target_ring: MeshInstance3D
var _target_ring_mat: StandardMaterial3D
var _vis_tip := Vector2.ZERO
var _vis_eye := Vector2.ZERO
var _vis_depth := 0.0
var _vis_sink := 0.0
var _vis_y := HIGH_Y
var _cue_t := 0.0
var _seen_drops := 0
var _was_closed := false
var _settled := false

# ---- the vat on the table ----
var _vat_at := VAT_AT_FALLBACK   # its centre on the work plane
var _table_y := TABLE_Y_FALLBACK # the table top in work-plane metres (negative: below the eyes)
var _measured := false
var _hid_vat: Node3D = null      # the real world vat, hidden while this plays

# ---- bot ----
var _b_t := -1.0
var _b_cursor := Vector2.ZERO


func setup(owner, context: Dictionary, kind: String, radius: float) -> void:
	owner_mg = owner
	ctx = context
	name = "EyeSeat"
	eye_kind = kind
	eye_r = radius
	mode = "place" if String(context.get("variant", "grab")) == "place" else "grab"
	_measure()
	eye = source_at()
	tip = source_at() + Vector2(0.0, 0.06)
	_b_cursor = tip
	_vis_tip = tip
	_vis_eye = eye
	_build()


func _exit_tree() -> void:
	_show_real_vat()


# =============================================================================== the vat on the table

## Where the vat really is, and how far down the table top is. The body on the table has its origin
## on the steel, and ctx.vat is the vat standing on it (surgery_system looks it up on every machine).
## Kept trying until it lands: a step can be set up before its work plane is in the tree.
func _measure() -> bool:
	if _measured or not is_inside_tree():
		return _measured
	var body = ctx.get("body")
	if body != null and is_instance_valid(body):
		var y := to_local((body as Node3D).global_position).y
		if y < -0.02 and y > -0.5:
			_table_y = y
	var vat = ctx.get("vat")
	if vat == null or not is_instance_valid(vat):
		return false
	var l := to_local((vat as Node3D).global_position)
	var at := Vector2(l.x, l.z)
	if at.length() > VAT_MAX_OUT:
		at = at.normalized() * VAT_MAX_OUT
	_vat_at = at
	if l.y < -0.02 and l.y > -0.5:
		_table_y = l.y
	_measured = true
	_hide_real_vat(vat as Node3D)
	if _built:
		_place_vat()
		if stage == Stage.SOURCE:
			eye = source_at()
			_vis_eye = eye
	return true


func _hide_real_vat(vat: Node3D) -> void:
	if vat == null or not is_instance_valid(vat) or not vat.visible:
		return
	_hid_vat = vat
	vat.visible = false


func _show_real_vat() -> void:
	if _hid_vat != null and is_instance_valid(_hid_vat):
		_hid_vat.visible = true
	_hid_vat = null


# =============================================================================== contract

## Where the eye starts: the vat (grab) or the socket (place). A seam for tools/grafttest.gd.
func source_at() -> Vector2:
	return Vector2.ZERO if mode == "place" else _vat_at


## Where it has to end up: the socket (grab) or the vat (place).
func target_at() -> Vector2:
	return _vat_at if mode == "place" else Vector2.ZERO


func source_reach() -> float:
	return SOCKET_REACH if mode == "place" else VAT_REACH


func target_reach() -> float:
	return VAT_REACH if mode == "place" else SOCKET_REACH


func plane_extent() -> Vector2:
	return Vector2(maxf(absf(_vat_at.x) + VAT_R, 0.085) + 0.03, absf(_vat_at.y) + VAT_R + 0.03)


func camera_pose() -> Dictionary:
	if owner_mg != null and owner_mg.has_method("base_camera_pose"):
		return owner_mg.call("base_camera_pose")
	return {"height": 0.45, "back": -0.04, "fov": 54.0}


func on_jolt(_offset: Vector2, _strength: float, duration: float) -> void:
	_jolt_t = duration + 0.15


# =============================================================================== rules (operator)

func handle_cursor(p: Vector2, buttons: int, delta: float) -> void:
	if owner_mg.done:
		return
	delta = clampf(delta, 1e-4, 0.1)
	_time += delta
	_hint_t = maxf(0.0, _hint_t - delta)
	_jolt_t = maxf(0.0, _jolt_t - delta)
	var primary := (buttons & MinigameBase.BUTTON_PRIMARY) != 0
	var want_up := (buttons & MinigameBase.BUTTON_UP) != 0
	var want_down := (buttons & MinigameBase.BUTTON_DOWN) != 0
	var was := tip
	tip += ((p - tip) * (1.0 - exp(-delta / TIP_TAU))).limit_length(TIP_SPEED * delta)
	_speed = lerpf(_speed, was.distance_to(tip) / delta, 1.0 - exp(-delta / 0.08))
	if _jolt_t > 0.0:
		_speed = minf(_speed, CARRY_MAX_SPEED * 0.8)   # a stir never shakes it loose
	if want_down and not want_up:
		depth = minf(1.0, depth + DEPTH_RATE * delta)
	elif want_up and not want_down:
		depth = maxf(0.0, depth - DEPTH_RATE * delta)

	if mode == "place":
		_place_rules(primary, delta)
		_update_progress()
		return

	match stage:
		Stage.SOURCE:
			eye = eye.lerp(source_at(), 1.0 - exp(-delta / 0.12))
			var on_it := tip.distance_to(source_at()) < source_reach() and depth >= DEEP_ENOUGH
			if _jaws(primary, delta, on_it):
				stage = Stage.HELD
				eye = source_at()
		Stage.HELD:
			if not primary:
				_shake_loose("You let go: it dropped back.")
			else:
				jaw = JAW_ON
				eye = eye.lerp(tip, 1.0 - exp(-delta / SWING_TAU))
				var clear_of_source := eye.distance_to(source_at()) > source_reach() + 0.02
				if depth > LIFT_CLEAR and clear_of_source:
					_shake_loose("Lift it clear first: hold W. It knocked and dropped back.")
				elif _jolt_t <= 0.0 and (eye.distance_to(tip) > SLACK_DROP or _speed > CARRY_MAX_SPEED):
					_shake_loose("Too quick: it swung out of the jaws. Pick it up again.")
				elif eye.distance_to(target_at()) <= target_reach() \
						and tip.distance_to(target_at()) <= target_reach() + 0.014:
					stage = Stage.SEATING
		Stage.SEATING:
			if not primary:
				_shake_loose("You let go before it was in. Pick it up again.")
			elif tip.distance_to(target_at()) > target_reach() + 0.014 \
					or (_jolt_t <= 0.0 and _speed > CARRY_MAX_SPEED):
				stage = Stage.HELD
				_hint = "Keep it over the %s." % ("vat" if mode == "place" else "socket")
				_hint_t = 2.0
			else:
				jaw = JAW_ON
				eye = eye.lerp(target_at(), 1.0 - exp(-delta / 0.10))
				# It goes in as you lower, and only under a steady hand.
				var want := clampf((depth - 0.15) / 0.8, 0.0, 1.0)
				if _speed > SEAT_MAX_SPEED and _jolt_t <= 0.0:
					sink = maxf(0.0, sink - delta / 1.2)
					_hint = "Steady. Lower it slowly."
					_hint_t = 1.0
				else:
					sink = clampf(move_toward(sink, want, delta * DEPTH_RATE * 1.4), 0.0, 1.0)
				if sink >= 1.0:
					stage = Stage.SETTLE
					settle = 0.0
		Stage.SETTLE:
			jaw = maxf(jaw - JAW_OPEN_RATE * delta, 0.0)
			eye = target_at()
			settle += delta
			if settle >= SETTLE_TIME:
				stage = Stage.DONE
				_update_progress()
				owner_mg.finish({"eye_seated": true} if mode == "grab" else {"eye_in_vat": true})
				return
	if not primary:
		_empty = false
	_update_progress()


## Returns true on the frame the jaws close on something.
func _jaws(primary: bool, delta: float, can_take: bool) -> bool:
	if primary and not _empty:
		jaw = minf(jaw + JAW_CLOSE_RATE * delta, 1.0)
		if can_take and jaw >= JAW_ON:
			jaw = JAW_ON
			return true
		if jaw >= 1.0:
			_empty = true
	elif not primary:
		jaw = maxf(jaw - JAW_OPEN_RATE * delta, 0.0)
	return false


## `place`, the extraction's last step: hold left click on the loose eye, drag it to the vat, let
## go. The forceps lower and lift themselves, the carry cannot be lost, and letting go anywhere
## else just drops it back in the socket. (It used to ask for the whole careful trip, which is right
## for millimetre work on a face and far too much for putting a dead monster's eye in a jar.)
func _place_rules(primary: bool, delta: float) -> void:
	var want_depth := 0.35
	match stage:
		Stage.SOURCE:
			eye = eye.lerp(source_at(), 1.0 - exp(-delta / 0.12))
			var near := tip.distance_to(source_at()) < PLACE_GRAB
			want_depth = 1.0 if near else 0.35
			if primary and near and depth > 0.55:
				jaw = JAW_ON
				stage = Stage.HELD
				eye = source_at()
			elif primary:
				jaw = minf(jaw + JAW_CLOSE_RATE * delta, 1.0)
			else:
				jaw = maxf(jaw - JAW_OPEN_RATE * delta, 0.0)
		Stage.HELD:
			jaw = JAW_ON
			want_depth = 0.0
			eye = eye.lerp(tip, 1.0 - exp(-delta / SWING_TAU))   # the swing is for the look only
			if not primary:
				if eye.distance_to(target_at()) <= PLACE_DROP or tip.distance_to(target_at()) <= PLACE_DROP:
					stage = Stage.SEATING
					sink = 0.0
				else:
					drops += 1
					stage = Stage.SOURCE
					_hint = "It dropped back in the socket. Pick it up again."
					_hint_t = 3.0
		Stage.SEATING:
			# In it goes by itself: the jaws open and it sinks into the fluid.
			want_depth = 0.45
			jaw = maxf(jaw - JAW_OPEN_RATE * delta, 0.0)
			eye = eye.lerp(target_at(), 1.0 - exp(-delta / 0.10))
			sink = minf(1.0, sink + delta / 0.5)
			if sink >= 1.0:
				stage = Stage.SETTLE
				settle = 0.0
		Stage.SETTLE:
			want_depth = 0.2
			jaw = maxf(jaw - JAW_OPEN_RATE * delta, 0.0)
			eye = target_at()
			settle += delta
			if settle >= SETTLE_TIME * 0.6:
				stage = Stage.DONE
				_update_progress()
				owner_mg.finish({"eye_in_vat": true})
				return
	depth = move_toward(depth, want_depth, PLACE_DEPTH_RATE * delta)


## It slipped out of the jaws: back where it started, nothing lost. Never a botch (grafts can't fail).
func _shake_loose(why: String) -> void:
	stage = Stage.SOURCE
	sink = 0.0
	jaw = 0.25
	_empty = true
	drops += 1
	_hint = why
	_hint_t = 3.0


func _update_progress() -> void:
	var p := 0.0
	var span: float = maxf(source_at().distance_to(target_at()), 0.01)
	match stage:
		Stage.SOURCE:
			p = 0.04
		Stage.HELD:
			p = 0.12 + 0.36 * clampf(1.0 - eye.distance_to(target_at()) / span, 0.0, 1.0)
		Stage.SEATING:
			p = 0.5 + 0.42 * sink
		Stage.SETTLE:
			p = 0.96
		_:
			p = 1.0
	owner_mg.progress = 1.0 if stage == Stage.DONE else minf(p, 0.99)


# =============================================================================== HUD

func hud_state() -> Dictionary:
	var hint := _hint if _hint_t > 0.0 else ""
	var from_where := "vat" if mode == "grab" else "socket"
	var to_where := "socket" if mode == "grab" else "vat"
	if hint == "" and mode == "place":
		match stage:
			Stage.SOURCE:
				hint = "Hold left click on the eye, drag it to the vat, and let go."
			Stage.HELD:
				hint = "Drag it over the vat and let go."
			_:
				hint = "It's in the vat."
	elif hint == "":
		match stage:
			Stage.SOURCE:
				if tip.distance_to(source_at()) >= source_reach():
					hint = "Bring the forceps over the eye in the %s." % from_where
				elif depth < DEEP_ENOUGH:
					hint = "Hold S to lower them onto it."
				else:
					hint = "Hold left click to close the jaws on it."
			Stage.HELD:
				if depth > LIFT_CLEAR:
					hint = "Hold W to lift it clear."
				else:
					hint = "Carry it to the %s. Slowly: it swings on the nerve." % to_where
			Stage.SEATING:
				hint = "Hold S. It's sliding in."
			_:
				hint = "Seated."
	return {"title": String(ctx.get("step", {}).get("label", "Seat the new eye with forceps")),
		"hint": hint, "progress": owner_mg.progress, "gauges": [], "keys": keys()}


func keys() -> Array:
	if mode == "place":
		match stage:
			Stage.SOURCE:
				return [["Hold LMB", "grab the eye"], ["Mouse", "drag it to the vat"]]
			Stage.HELD:
				return [["Mouse", "drag it over the vat"], ["Let go", "drop it in"]]
		return []
	match stage:
		Stage.SOURCE:
			return [["Mouse", "move the forceps"], ["Hold S", "lower them"], ["Hold LMB", "close the jaws"]]
		Stage.HELD:
			return [["Hold W", "lift it clear"], ["Mouse", "carry it across"], ["Hold LMB", "keep hold"]]
		Stage.SEATING:
			return [["Hold S", "ease it in"], ["Hold LMB", "keep hold"]]
	return []


# =============================================================================== net

func net_state() -> Dictionary:
	return {"x": snappedf(tip.x, 0.0005), "y": snappedf(tip.y, 0.0005),
		"ex": snappedf(eye.x, 0.0005), "ez": snappedf(eye.y, 0.0005),
		"j": snappedf(jaw, 0.02), "d": snappedf(depth, 0.01), "k": snappedf(sink, 0.01),
		"st": int(stage), "se": snappedf(settle, 0.02), "dr": drops,
		"p": snappedf(owner_mg.progress, 0.001)}


func apply_net_state(s: Dictionary) -> void:
	tip = Vector2(float(s.get("x", tip.x)), float(s.get("y", tip.y)))
	eye = Vector2(float(s.get("ex", eye.x)), float(s.get("ez", eye.y)))
	jaw = float(s.get("j", jaw))
	depth = float(s.get("d", depth))
	sink = float(s.get("k", sink))
	stage = int(s.get("st", stage))
	settle = float(s.get("se", settle))
	drops = int(s.get("dr", drops))
	owner_mg.progress = float(s.get("p", owner_mg.progress))


# =============================================================================== bot

func bot_input(t: float, skill: float) -> Dictionary:
	var dt := 1.0 / 60.0 if _b_t < 0.0 else clampf(t - _b_t, 0.0, 0.1)
	_b_t = t
	var sk := clampf(maxf(skill, (t - 30.0) / 10.0), 0.0, 1.0)
	var buttons := 0
	if mode == "place":
		# Grab it, drag it over the vat, let go.
		match stage:
			Stage.SOURCE:
				_b_cursor = _b_cursor.move_toward(source_at(), lerpf(0.16, 0.24, sk) * dt)
				# A beat before it grabs, so the step reads (and a screenshot can catch its start).
				if t > 1.2 and tip.distance_to(source_at()) < PLACE_GRAB * 0.5:
					buttons |= MinigameBase.BUTTON_PRIMARY
			Stage.HELD:
				_b_cursor = _b_cursor.move_toward(target_at(), lerpf(0.12, 0.2, sk) * dt)
				if tip.distance_to(target_at()) > PLACE_DROP * 0.4:
					buttons |= MinigameBase.BUTTON_PRIMARY
		return {"cursor": _b_cursor, "buttons": buttons}
	match stage:
		Stage.SOURCE:
			_b_cursor = _b_cursor.move_toward(source_at(), lerpf(0.16, 0.24, sk) * dt)
			if tip.distance_to(source_at()) < source_reach() * 0.5:
				if depth < DEEP_ENOUGH + 0.06:
					buttons |= MinigameBase.BUTTON_DOWN
				elif not _empty:
					buttons |= MinigameBase.BUTTON_PRIMARY
		Stage.HELD:
			buttons |= MinigameBase.BUTTON_PRIMARY
			if depth > 0.2:
				buttons |= MinigameBase.BUTTON_UP   # lift it clear before drawing it across
			else:
				# A steady hand draws it across well under the speed that shakes it loose.
				_b_cursor = _b_cursor.move_toward(target_at(), lerpf(0.09, 0.05, sk) * dt)
		Stage.SEATING, Stage.SETTLE:
			buttons |= MinigameBase.BUTTON_PRIMARY | MinigameBase.BUTTON_DOWN
			_b_cursor = _b_cursor.move_toward(target_at(), 0.01 * dt)
	return {"cursor": _b_cursor, "buttons": buttons}


# =============================================================================== visuals

func _p3(p: Vector2, lift: float) -> Vector3:
	return Vector3(p.x, lift, p.y)


## How low the tips reach over plane point `p`: into the vat's fluid over the vat, down to the
## socket everywhere else.
func _low_y(p: Vector2) -> float:
	var k := clampf((p.distance_to(_vat_at) - VAT_REACH) / 0.05, 0.0, 1.0)
	return lerpf(_table_y + VAT_FLUID_Y + eye_r, -0.004, k)


func _cue_mat(col: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = col
	m.no_depth_test = true
	m.render_priority = 2
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


func _build() -> void:
	if _built:
		return
	_built = true
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.78, 0.8, 0.83)
	steel.metallic = 0.4
	steel.roughness = 0.35
	# The specimen vat, open, standing on the table where the real one stands.
	_vat = Node3D.new()
	_vat.name = "EyeVat"
	add_child(_vat)
	_build_vat(_vat)
	_place_vat()
	# The eye going in, and the nerve it hangs on.
	_eye_node = MeshInstance3D.new()
	_eye_node.name = "EyeBall_Seat"
	var sph := SphereMesh.new()
	sph.radius = eye_r
	sph.height = eye_r * 2.0
	sph.radial_segments = 20
	sph.rings = 10
	_eye_node.mesh = sph
	_eye_node.material_override = Eyes.material(eye_kind)
	add_child(_eye_node)
	var nmat := StandardMaterial3D.new()
	nmat.albedo_color = Color(0.88, 0.74, 0.66)
	nmat.roughness = 0.35
	_nerve = MeshInstance3D.new()
	var nc := CylinderMesh.new()
	nc.top_radius = 1.0
	nc.bottom_radius = 1.0
	nc.height = 1.0
	nc.radial_segments = 8
	nc.rings = 1
	_nerve.mesh = nc
	_nerve.material_override = nmat
	add_child(_nerve)
	# The cues: a ring over whatever the eye is being taken from, and one where it has to go.
	var tm := TorusMesh.new()
	tm.inner_radius = 0.8
	tm.outer_radius = 1.0
	tm.rings = 28
	tm.ring_segments = 6
	_source_ring_mat = _cue_mat(Color(1.0, 0.95, 0.8, 0.0))
	_source_ring = MeshInstance3D.new()
	_source_ring.mesh = tm
	_source_ring.material_override = _source_ring_mat
	add_child(_source_ring)
	_target_ring_mat = _cue_mat(Color(0.25, 1.0, 0.45, 0.0))
	_target_ring = MeshInstance3D.new()
	_target_ring.mesh = tm
	_target_ring.material_override = _target_ring_mat
	_target_ring.visible = false
	add_child(_target_ring)
	_tool = _make_forceps(steel)
	add_child(_tool)


## The vat as vats.gd builds it, minus the lid: a steel foot, a glass jar and the fluid in it.
func _build_vat(root: Node3D) -> void:
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.8, 0.9, 0.92, 0.22)
	glass.roughness = 0.05
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var fluid := StandardMaterial3D.new()
	fluid.albedo_color = Color(0.78, 0.85, 0.55, 0.28)
	fluid.roughness = 0.25
	fluid.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.5, 0.52, 0.55)
	steel.roughness = 0.35
	steel.metallic = 0.6
	for e in [[0.07, 0.014, 0.007, steel], [VAT_R, 0.2, 0.114, glass], [0.056, 0.17, 0.105, fluid]]:
		var mi := MeshInstance3D.new()
		var c := CylinderMesh.new()
		c.top_radius = float(e[0])
		c.bottom_radius = float(e[0])
		c.height = float(e[1])
		c.radial_segments = 16
		c.rings = 1
		mi.mesh = c
		mi.material_override = e[3]
		mi.position = Vector3(0, float(e[2]), 0)
		root.add_child(mi)


func _place_vat() -> void:
	if _vat != null:
		_vat.position = _p3(_vat_at, _table_y)


## Slim forceps: a grip, a hinge and two arms meeting at the tips, tips down at the origin.
func _make_forceps(steel: StandardMaterial3D) -> Node3D:
	var root := Node3D.new()
	root.name = "Forceps"
	var grip := MeshInstance3D.new()
	var gc := CylinderMesh.new()
	gc.top_radius = 0.0032
	gc.bottom_radius = 0.0024
	gc.height = 0.05
	gc.radial_segments = 10
	grip.mesh = gc
	grip.material_override = steel
	grip.position = Vector3(0, ARM_LEN + 0.025, 0)
	root.add_child(grip)
	for side in [-1.0, 1.0]:
		var pivot := Node3D.new()
		pivot.position = Vector3(0, ARM_LEN, 0)
		root.add_child(pivot)
		var arm := MeshInstance3D.new()
		var ab := BoxMesh.new()
		ab.size = Vector3(0.0022, ARM_LEN, 0.0016)
		arm.mesh = ab
		arm.material_override = steel
		arm.position = Vector3(0, -ARM_LEN * 0.5, 0)
		pivot.add_child(arm)
		pivot.rotation = Vector3(0, 0, 0)
		pivot.set_meta("side", side)
		_arms.append(pivot)
	return root


func tick(delta: float) -> void:
	if not _built:
		return
	if not _measured:
		_measure()
	_cue_t += delta
	var operator := bool(ctx.get("operator", false))
	var k := 1.0 if operator else 1.0 - exp(-delta * 18.0)
	_vis_tip = _vis_tip.lerp(tip, k)
	_vis_eye = _vis_eye.lerp(eye, k)
	_vis_depth = lerpf(_vis_depth, depth, 1.0 - exp(-delta * 16.0))
	_vis_sink = lerpf(_vis_sink, sink, k)

	var held := stage == Stage.HELD or stage == Stage.SEATING
	# The forceps: the tips ride from carrying height down to whatever is under them.
	_vis_y = lerpf(HIGH_Y, _low_y(_vis_tip), clampf(_vis_depth, 0.0, 1.0))
	_tool.position = _p3(_vis_tip, _vis_y + eye_r * 2.0 + 0.012)
	_tool.basis = Basis(Vector3.UP, 0.5) * Basis(Vector3.RIGHT, deg_to_rad(20.0))
	var gap := lerpf(0.0055, 0.0008, clampf(jaw, 0.0, 1.0))
	for a in _arms:
		var side := float(a.get_meta("side", 1.0))
		a.rotation = Vector3(0.0, 0.0, -side * atan2(gap, ARM_LEN))

	# The eye: waiting where it started, hanging under the jaws, or going home.
	var rest_y := _low_y(source_at())
	var home_y := _low_y(target_at())
	var ey := rest_y
	if stage == Stage.HELD:
		ey = _vis_y
	elif stage == Stage.SEATING:
		ey = lerpf(_vis_y, home_y, smoothstep(0.0, 1.0, _vis_sink))
	elif stage == Stage.SETTLE and mode == "place":
		ey = lerpf(_vis_y, home_y, smoothstep(0.0, 1.0, _vis_sink))
	elif stage == Stage.SETTLE or stage == Stage.DONE:
		ey = home_y
	_eye_node.position = _p3(_vis_eye, ey)
	# Turning as it goes in, so a seated pupil (the eye's -Z) ends up looking out of the socket.
	var seat_turn := _vis_sink if mode == "grab" else 0.0
	var turn := lerpf(PI * 0.5 - 0.95, PI * 0.5, smoothstep(0.0, 1.0, seat_turn))
	var swing := (_vis_eye - _vis_tip).limit_length(SLACK_DROP) * 14.0 if held else Vector2.ZERO
	_eye_node.basis = Basis(Vector3.UP, -swing.x) * Basis(Vector3.RIGHT, turn + swing.y)
	# The nerve: from the jaws down to the eye while it is carried, then trailing off it.
	var jaws_at := _p3(_vis_tip, _vis_y)
	var eye_at: Vector3 = _eye_node.position
	if held:
		_place_cyl(_nerve, jaws_at, eye_at + Vector3(0, eye_r * 0.5, 0), 0.0022)
	else:
		_place_cyl(_nerve, eye_at + Vector3(0, 0, eye_r * 0.8), eye_at + Vector3(0, eye_r * 0.2, eye_r * 1.9), 0.0022)

	# The cues.
	var at_source := stage == Stage.SOURCE
	var near := _vis_tip.distance_to(source_at()) < source_reach()
	_source_ring.visible = at_source
	if at_source:
		var sc := (eye_r * 1.7) if near else (eye_r * 1.35 + 0.004 * fmod(_cue_t * 0.9, 1.0))
		_source_ring.position = _p3(source_at(), rest_y + eye_r * 1.4)
		_source_ring.scale = Vector3(sc, sc * 0.3, sc)
		_source_ring_mat.albedo_color = Color(0.25, 1.0, 0.45, 0.9) if near \
			else Color(1.0, 0.95, 0.8, 0.75 * (1.0 - fmod(_cue_t * 0.9, 1.0)))
	# `place`: the vat's ring is up from the first frame and much bigger -- it is the whole target.
	var show_target := held or (mode == "place" and stage != Stage.DONE)
	_target_ring.visible = show_target
	if show_target:
		var reach: float = PLACE_DROP if mode == "place" else target_reach()
		var over := _vis_eye.distance_to(target_at()) <= reach or _vis_tip.distance_to(target_at()) <= reach
		var big := 2.6 if mode == "place" else 1.0
		var rs := eye_r * big * (1.7 if over else 1.5 + 0.12 * sin(_cue_t * 5.0))
		_target_ring.position = _p3(target_at(), home_y + eye_r * 1.4)
		_target_ring.scale = Vector3(rs, rs * 0.25, rs)
		_target_ring_mat.albedo_color = Color(0.25, 1.0, 0.45, 0.9 if over else 0.5)

	# Sounds, from the displayed state, so spectators hear them too.
	var closed := jaw >= JAW_ON - 0.05
	if closed and not _was_closed:
		_sfx("surgery_forceps_click", -7.0)
	_was_closed = closed
	if drops != _seen_drops:
		_seen_drops = drops
		_sfx("surgery_forceps_clink", -4.0)
	if (stage == Stage.SETTLE or stage == Stage.DONE) and not _settled:
		_settled = true
		_sfx("surgery_forceps_squelch", -5.0)


func _place_cyl(mi: MeshInstance3D, from: Vector3, to: Vector3, r: float) -> void:
	var dv := to - from
	var l := dv.length()
	if l < 1e-5:
		mi.visible = false
		return
	mi.visible = true
	mi.position = (from + to) * 0.5
	var up := dv / l
	var any := Vector3.RIGHT if absf(up.dot(Vector3.RIGHT)) < 0.9 else Vector3.FORWARD
	var x := any.cross(up).normalized()
	mi.basis = Basis(x, up, x.cross(up)) * Basis().scaled(Vector3(r * 2.0, l, r * 2.0))


func _sfx(cue: String, vol_db := 0.0) -> void:
	var loop := Engine.get_main_loop() as SceneTree
	if loop == null:
		return
	var a = loop.root.get_node_or_null("Audio")
	if a != null:
		a.play(cue, global_position if is_inside_tree() else null, vol_db, 0.08)
