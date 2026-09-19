extends Node3D
## GRAFTING chunk C, the graft's third step: "Seat the new eye with forceps" (the `grab` variant of
## the eye steps). eye_ops.gd creates this as a child when ctx.variant == "grab" and hands every
## Minigame call to it; it reports through the owner (owner.finish / owner.progress). There is no
## botching here at all: the graft sets `no_fail`, and every mistake is just a retry.
##
## The socket is open and empty (the scoop took the old eye out). The new eye -- whatever the vat
## held, ctx.eye_kind_in -- lies on a small steel tray beside it, on the end of its optic nerve.
##
## TRAY    Bring the forceps over the eye on the tray. A green ring says they are close enough;
##         hold left click and the jaws close on the nerve just above it.
## CARRY   Keep holding and draw it across to the socket. It hangs on the nerve and swings, so it
##         lags behind the tips: whip the hand about, or run too far ahead of it, and it shakes
##         loose and drops back on the tray. Pick it up and try again; it costs nothing.
## SEAT    Over the socket (its ring turns green) the eye starts to sink in, turning as it goes so
##         the pupil ends up facing out. It only goes in under slow, steady pressure: move the hand
##         and it stalls and backs out again.
## SETTLE  Home. The jaws open, the eye settles with a soft squelch, and the step finishes
##         {"eye_seated": true}.
## A stir's shake never drops it (on_jolt).

enum Stage { TRAY, HELD, SEATING, SETTLE, DONE }

## Where the tray sits on the work plane, in metres from the socket (plane +X runs down the body).
const TRAY_AT := Vector2(0.050, 0.006)
const TRAY_HALF := Vector2(0.018, 0.015)
const TIP_TAU := 0.05
const TIP_SPEED := 0.30          # m/s the tips can follow the hand
const GRAB_R := 0.014            # tips this close to the eye on the tray can close on it
const JAW_CLOSE_RATE := 5.0
const JAW_OPEN_RATE := 7.0
const JAW_ON := 0.6
const SWING_TAU := 0.13          # how far the eye lags behind the tips on its nerve
const SLACK_DROP := 0.021        # that far behind and it shakes out of the jaws
const CARRY_MAX_SPEED := 0.19    # m/s: faster than this and it shakes loose too
const SEAT_R := 0.010            # the eye this close to the socket's centre starts going in
const SEAT_LEAVE := 0.013        # the hand this far off the socket while seating lifts it back out
const SEAT_SECONDS := 2.0        # of slow, steady pressure to slide it home
const SEAT_MAX_SPEED := 0.030    # hand faster than this while pushing and it stalls instead
const SETTLE_TIME := 0.7
const ARM_LEN := 0.05            # the forceps' arms, hinge to tip

var owner_mg                     # the eye_ops Minigame that owns this (untyped: done, progress, finish)
var ctx: Dictionary = {}
var eye_kind := "eye_hive"
var eye_r := 0.0135

# ---- state (the operator simulates it; apply_net_state writes the same vars on spectators) ----
var tip := Vector2(0.056, 0.055)
var eye := TRAY_AT
var jaw := 0.0
var sink := 0.0                  # 0 sitting on the rim .. 1 home in the socket
var settle := 0.0
var stage: int = Stage.TRAY
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
var _tray_ring: MeshInstance3D
var _tray_ring_mat: StandardMaterial3D
var _socket_ring: MeshInstance3D
var _socket_ring_mat: StandardMaterial3D
var _vis_tip := Vector2.ZERO
var _vis_eye := Vector2.ZERO
var _vis_sink := 0.0
var _vis_y := 0.03
var _cue_t := 0.0
var _seen_drops := 0
var _was_closed := false
var _settled := false

# ---- bot ----
var _b_t := -1.0
var _b_cursor := Vector2(0.056, 0.055)


func setup(owner, context: Dictionary, kind: String, radius: float) -> void:
	owner_mg = owner
	ctx = context
	name = "EyeSeat"
	eye_kind = kind
	eye_r = radius
	tip = TRAY_AT + Vector2(0.0, 0.05)
	_b_cursor = tip
	_vis_tip = tip
	_vis_eye = eye
	_build()


# =============================================================================== contract

## Where the tray is on the work plane (a seam for tools/grafttest.gd).
func tray_at() -> Vector2:
	return TRAY_AT


func plane_extent() -> Vector2:
	return Vector2(TRAY_AT.x + TRAY_HALF.x + 0.02, 0.06)


func camera_pose() -> Dictionary:
	# Pulled back a little further than the other eye steps: the tray has to be in shot too.
	return {"height": 0.34, "back": 0.07, "fov": 50.0}


func on_jolt(_offset: Vector2, _strength: float, duration: float) -> void:
	_jolt_t = duration + 0.15


func handle_cursor(p: Vector2, buttons: int, delta: float) -> void:
	if owner_mg.done:
		return
	delta = clampf(delta, 1e-4, 0.1)
	_time += delta
	_hint_t = maxf(0.0, _hint_t - delta)
	_jolt_t = maxf(0.0, _jolt_t - delta)
	var primary := (buttons & 1) != 0
	var was := tip
	tip += ((p - tip) * (1.0 - exp(-delta / TIP_TAU))).limit_length(TIP_SPEED * delta)
	_speed = lerpf(_speed, was.distance_to(tip) / delta, 1.0 - exp(-delta / 0.08))
	if _jolt_t > 0.0:
		_speed = minf(_speed, CARRY_MAX_SPEED * 0.8)   # a stir never shakes it loose

	match stage:
		Stage.TRAY:
			eye = eye.lerp(TRAY_AT, 1.0 - exp(-delta / 0.12))
			if _jaws(primary, delta, tip.distance_to(TRAY_AT) < GRAB_R):
				stage = Stage.HELD
				eye = TRAY_AT
		Stage.HELD:
			if not primary:
				_shake_loose("You let go: it dropped back on the tray.")
			else:
				jaw = JAW_ON
				eye = eye.lerp(tip, 1.0 - exp(-delta / SWING_TAU))
				if _jolt_t <= 0.0 and (eye.distance_to(tip) > SLACK_DROP or _speed > CARRY_MAX_SPEED):
					_shake_loose("Too quick: it swung out of the jaws. Pick it up again.")
				elif eye.length() <= SEAT_R and tip.length() <= SEAT_R + SEAT_LEAVE:
					stage = Stage.SEATING
		Stage.SEATING:
			if not primary:
				_shake_loose("You let go before it was in. Pick it up again.")
			elif tip.length() > SEAT_R + SEAT_LEAVE or (_jolt_t <= 0.0 and _speed > CARRY_MAX_SPEED):
				stage = Stage.HELD
				_hint = "Keep it over the socket."
				_hint_t = 2.0
			else:
				jaw = JAW_ON
				eye = eye.lerp(Vector2.ZERO, 1.0 - exp(-delta / 0.10))
				if _speed > SEAT_MAX_SPEED and _jolt_t <= 0.0:
					sink = maxf(0.0, sink - delta / SEAT_SECONDS)
					_hint = "Steady. Push it in slowly."
					_hint_t = 1.0
				else:
					sink = minf(1.0, sink + delta / SEAT_SECONDS)
				if sink >= 1.0:
					stage = Stage.SETTLE
					settle = 0.0
		Stage.SETTLE:
			jaw = maxf(jaw - JAW_OPEN_RATE * delta, 0.0)
			eye = Vector2.ZERO
			settle += delta
			if settle >= SETTLE_TIME:
				stage = Stage.DONE
				_update_progress()
				owner_mg.finish({"eye_seated": true})
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


## It slipped out of the jaws: back on the tray, nothing lost. Never a botch (grafts can't fail).
func _shake_loose(why: String) -> void:
	stage = Stage.TRAY
	sink = 0.0
	jaw = 0.25
	_empty = true
	drops += 1
	_hint = why
	_hint_t = 3.0


func _update_progress() -> void:
	var p := 0.0
	match stage:
		Stage.TRAY:
			p = 0.04
		Stage.HELD:
			p = 0.12 + 0.36 * clampf(1.0 - eye.length() / maxf(TRAY_AT.length(), 0.01), 0.0, 1.0)
		Stage.SEATING:
			p = 0.5 + 0.42 * sink
		_:
			p = 1.0
	owner_mg.progress = 1.0 if stage == Stage.DONE else minf(p, 0.99)


func hud_state() -> Dictionary:
	var hint := _hint if _hint_t > 0.0 else ""
	if hint == "":
		match stage:
			Stage.TRAY:
				hint = "Hold left click to close the jaws on it." if tip.distance_to(TRAY_AT) < GRAB_R \
					else "Bring the forceps to the new eye on the tray."
			Stage.HELD:
				hint = "Carry it to the socket. Slowly: it swings on the nerve."
			Stage.SEATING:
				hint = "Hold it there. It's sliding in."
			_:
				hint = "Seated."
	return {"title": String(ctx.get("step", {}).get("label", "Seat the new eye with forceps")),
		"hint": hint, "progress": owner_mg.progress, "gauges": []}


func net_state() -> Dictionary:
	return {"x": snappedf(tip.x, 0.0005), "y": snappedf(tip.y, 0.0005),
		"ex": snappedf(eye.x, 0.0005), "ez": snappedf(eye.y, 0.0005),
		"j": snappedf(jaw, 0.02), "k": snappedf(sink, 0.01), "st": int(stage),
		"se": snappedf(settle, 0.02), "dr": drops, "p": snappedf(owner_mg.progress, 0.001)}


func apply_net_state(s: Dictionary) -> void:
	tip = Vector2(float(s.get("x", tip.x)), float(s.get("y", tip.y)))
	eye = Vector2(float(s.get("ex", eye.x)), float(s.get("ez", eye.y)))
	jaw = float(s.get("j", jaw))
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
	match stage:
		Stage.TRAY:
			_b_cursor = _b_cursor.move_toward(TRAY_AT, lerpf(0.16, 0.24, sk) * dt)
			if tip.distance_to(TRAY_AT) < GRAB_R * 0.5 and not _empty:
				buttons = 1
		Stage.HELD:
			buttons = 1
			# A steady hand draws it across well under the speed that shakes it loose.
			_b_cursor = _b_cursor.move_toward(Vector2.ZERO, lerpf(0.09, 0.05, sk) * dt)
		Stage.SEATING, Stage.SETTLE:
			buttons = 1
			_b_cursor = _b_cursor.move_toward(Vector2.ZERO, 0.02 * dt)
		_:
			buttons = 0
	return {"cursor": _b_cursor, "buttons": buttons}


# =============================================================================== visuals

func _p3(p: Vector2, lift: float) -> Vector3:
	return Vector3(p.x, lift, p.y)


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
	# The tray the new eye waits on. Darker steel than the tool: at this range a bright one under the
	# work lamp is a white card with an eye on it.
	var tray_steel := StandardMaterial3D.new()
	tray_steel.albedo_color = Color(0.42, 0.45, 0.48)
	tray_steel.metallic = 0.55
	tray_steel.roughness = 0.42
	var tray := Node3D.new()
	tray.name = "EyeTray"
	tray.position = _p3(TRAY_AT, 0.0)
	add_child(tray)
	var base := MeshInstance3D.new()
	var bb := BoxMesh.new()
	bb.size = Vector3(TRAY_HALF.x * 2.0, 0.003, TRAY_HALF.y * 2.0)
	base.mesh = bb
	base.material_override = tray_steel
	base.position = Vector3(0, 0.0015, 0)
	tray.add_child(base)
	for side in [[Vector3(TRAY_HALF.x, 0.007, 0), Vector3(0.003, 0.012, TRAY_HALF.y * 2.0)],
			[Vector3(-TRAY_HALF.x, 0.007, 0), Vector3(0.003, 0.012, TRAY_HALF.y * 2.0)],
			[Vector3(0, 0.007, TRAY_HALF.y), Vector3(TRAY_HALF.x * 2.0, 0.012, 0.003)],
			[Vector3(0, 0.007, -TRAY_HALF.y), Vector3(TRAY_HALF.x * 2.0, 0.012, 0.003)]]:
		var wall := MeshInstance3D.new()
		var wb := BoxMesh.new()
		wb.size = side[1]
		wall.mesh = wb
		wall.material_override = tray_steel
		wall.position = side[0]
		tray.add_child(wall)
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
	# The cues: a ring over the eye on the tray, and one round the socket while it is carried.
	var tm := TorusMesh.new()
	tm.inner_radius = 0.8
	tm.outer_radius = 1.0
	tm.rings = 28
	tm.ring_segments = 6
	_tray_ring_mat = _cue_mat(Color(1.0, 0.95, 0.8, 0.0))
	_tray_ring = MeshInstance3D.new()
	_tray_ring.mesh = tm
	_tray_ring.material_override = _tray_ring_mat
	add_child(_tray_ring)
	_socket_ring_mat = _cue_mat(Color(0.25, 1.0, 0.45, 0.0))
	_socket_ring = MeshInstance3D.new()
	_socket_ring.mesh = tm
	_socket_ring.material_override = _socket_ring_mat
	_socket_ring.visible = false
	add_child(_socket_ring)
	_tool = _make_forceps(steel)
	add_child(_tool)


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
	_cue_t += delta
	var operator := bool(ctx.get("operator", false))
	var k := 1.0 if operator else 1.0 - exp(-delta * 18.0)
	_vis_tip = _vis_tip.lerp(tip, k)
	_vis_eye = _vis_eye.lerp(eye, k)
	_vis_sink = lerpf(_vis_sink, sink, k)

	var held := stage == Stage.HELD or stage == Stage.SEATING
	# The eye: resting in the tray, hanging under the jaws, or sinking into the socket.
	var rest_y := 0.004 + eye_r
	var hang_y := eye_r + 0.012
	var home_y := -eye_r * 0.45
	var ey := rest_y
	if stage == Stage.HELD:
		ey = hang_y
	elif stage == Stage.SEATING:
		ey = lerpf(hang_y, home_y, smoothstep(0.0, 1.0, _vis_sink))
	elif stage == Stage.SETTLE or stage == Stage.DONE:
		ey = home_y
	_eye_node.position = _p3(_vis_eye, ey)
	# Turning as it goes in, so the pupil (the eye's -Z) ends up looking straight out of the socket.
	var turn := lerpf(PI * 0.5 - 0.95, PI * 0.5, smoothstep(0.0, 1.0, _vis_sink))
	var swing := (_vis_eye - _vis_tip).limit_length(SLACK_DROP) * 14.0 if held else Vector2.ZERO
	_eye_node.basis = Basis(Vector3.UP, -swing.x) * Basis(Vector3.RIGHT, turn + swing.y)
	# The nerve: from the jaws down to the eye while it is carried, then trailing into the socket.
	var jaws_at := _p3(_vis_tip, _tool_y())
	var eye_at: Vector3 = _eye_node.position
	if held:
		_place_cyl(_nerve, jaws_at, eye_at + Vector3(0, eye_r * 0.5, 0), 0.0022)
	else:
		_place_cyl(_nerve, eye_at + Vector3(0, 0, eye_r * 0.8), eye_at + Vector3(0, eye_r * 0.2, eye_r * 1.9), 0.0022)

	# The cues.
	var on_tray := stage == Stage.TRAY
	var near := _vis_tip.distance_to(TRAY_AT) < GRAB_R
	_tray_ring.visible = on_tray
	if on_tray:
		var sc := (eye_r * 1.5) if near else (eye_r * 1.2 + 0.004 * fmod(_cue_t * 0.9, 1.0))
		_tray_ring.position = _p3(TRAY_AT, rest_y + eye_r * 0.6)
		_tray_ring.scale = Vector3(sc, sc * 0.3, sc)
		_tray_ring_mat.albedo_color = Color(0.25, 1.0, 0.45, 0.9) if near \
			else Color(1.0, 0.95, 0.8, 0.75 * (1.0 - fmod(_cue_t * 0.9, 1.0)))
	_socket_ring.visible = held
	if held:
		var over := _vis_eye.length() <= SEAT_R
		var rs := eye_r * (1.7 if over else 1.5 + 0.12 * sin(_cue_t * 5.0))
		_socket_ring.position = _p3(Vector2.ZERO, 0.003)
		_socket_ring.scale = Vector3(rs, rs * 0.25, rs)
		_socket_ring_mat.albedo_color = Color(0.25, 1.0, 0.45, 0.9 if over else 0.5)

	# The forceps.
	_vis_y = lerpf(_vis_y, _tool_y(), 1.0 - exp(-delta * 14.0))
	_tool.position = _p3(_vis_tip, _vis_y)
	_tool.basis = Basis(Vector3.UP, 0.5) * Basis(Vector3.RIGHT, deg_to_rad(20.0))
	var gap := lerpf(0.0055, 0.0008, clampf(jaw, 0.0, 1.0))
	for a in _arms:
		var side := float(a.get_meta("side", 1.0))
		a.rotation = Vector3(0.0, 0.0, -side * atan2(gap, ARM_LEN))

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


func _tool_y() -> float:
	match stage:
		Stage.HELD:
			return eye_r * 2.0 + 0.014
		Stage.SEATING:
			return lerpf(eye_r * 2.0 + 0.014, eye_r + 0.008, smoothstep(0.0, 1.0, _vis_sink))
		Stage.SETTLE, Stage.DONE:
			return 0.03
		_:
			return (eye_r * 2.0 + 0.012) if _vis_tip.distance_to(TRAY_AT) < GRAB_R * 1.6 else 0.032


func _place_cyl(mi: MeshInstance3D, from: Vector3, to: Vector3, r: float) -> void:
	var dv := to - from
	var l := dv.length()
	mi.visible = l > 0.001
	if not mi.visible:
		return
	var yv := dv / l
	var ref := Vector3.UP if absf(yv.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
	var xv := ref.cross(yv).normalized()
	var zv := xv.cross(yv).normalized()
	mi.transform = Transform3D(Basis(xv * r, yv * l, zv * r), (from + to) * 0.5)


func _sfx(cue: String, vol_db := 0.0) -> void:
	var loop := Engine.get_main_loop() as SceneTree
	if loop == null:
		return
	var a = loop.root.get_node_or_null("Audio")
	if a != null:
		a.play(cue, global_position if is_inside_tree() else null, vol_db, 0.08)
