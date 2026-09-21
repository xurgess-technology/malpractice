extends "res://scripts/surgery/arcade/arcade_game.gd"
## ARCADE SURGERY (docs/ARCADE_SURGERY.md) 5.11 -- GRAB! The forceps eye step, both ways round. The
## arcade rebuild of scripts/grafting/eye_seat.gd, played on the raised panel.
##
##   place  Eyeball Extraction step 4: the loose eye out of the socket and into the specimen vat.
##          Finishes {"eye_in_vat": true}.
##   grab   Eyeball Grafting step 3: the new eye out of the vat and into the empty socket.
##          Finishes {"eye_seated": true} -- which is the moment grafts.gd swaps the eyes over.
##
## Rhyme: claw machine. A claw hangs off a rail, the prize is an eyeball, and the prize swings.
##
## What you do
##   The socket is at one end of the rail and the specimen vat at the other, at the distance the
##   real vat is standing from the head (ctx.vat, the same measurement eye_seat makes; with no vat
##   on the table it falls back to the same fallback spot). The claw parks over the target, like a
##   claw machine parks over its chute.
##   Drive the claw along the rail with A / D or the mouse. It has weight: it takes a moment to get
##   going and a moment to stop. Line it up over the eye and hit SPACE, and the claw commits -- down,
##   shut, up, and you cannot steer it while it is going. Come down more than a jaw's width off the
##   eye and it comes back up with nothing.
##   Then the eye is DANGLING OFF ITS NERVE under the claw, and it is a pendulum. Every shove you
##   give the claw swings it, and a shove at the wrong moment pumps the swing bigger. Past fifty
##   degrees it tears off the jaws and drops back where it came from. So the trip across is a
##   question of how much hurry you can afford.
##   SPACE again opens the jaws. Where the EYE is when you let go is what counts, swing and all: over
##   the vat's mouth it goes in, over the socket it seats. Off either one it bounces off the rim and
##   lies on the table beside it, and you go and pick it up from there.
##   On the graft the eye also turns on its nerve the whole time it hangs, about a quarter turn a
##   second. Where the iris keyway is pointing when you let go is the angle the eye is stitched in
##   at. Nothing stops you seating it sideways. Your friend will be wall-eyed and it will be your
##   fault.
##
## IT IS NO-FAIL, both ways. Not one cost() call in this file, and on_jolt does nothing: a stir
## cannot shake an eyeball out of a claw. The only thing a mistake costs is time -- and on the
## monster table time is sedation, which is quite enough.

enum Stage { SOURCE, DIP, CARRY, LAND, SETTLE, DONE }

## The metres the real vat can stand from the head, mapped onto `vat_out_mm` either side.
const VAT_NEAR_M := 0.11
const VAT_FAR_M := 0.30
## No vat on the table (the lab, a table somebody cleared): eye_seat's own fallback spot.
const VAT_FALLBACK := Vector2(-0.04, -0.20)
## The dip: how much of the 1.2 s is the claw going down, and how much of it is the jaws shutting.
const DIP_DOWN := 0.38
const DIP_SHUT := 0.60

# -- the rail ------------------------------------------------------------------------------------
@export_range(20.0, 58.0, 0.5) var rail_half := 50.0        ## mm the claw may run either side of centre
@export_range(-40.0, 0.0, 0.5) var rail_y := -30.0          ## mm, the rail itself
@export_range(-40.0, 10.0, 0.5) var carry_y := -22.0        ## mm, the jaws at carrying height
@export_range(0.0, 40.0, 0.5) var floor_y := 30.0           ## mm, the table top
@export_range(0.0, 40.0, 0.5) var rest_y := 22.0            ## mm, an eye lying on the table

# -- where the two ends are ------------------------------------------------------------------------
## How far out the vat stands, before the real one on the table is measured.
@export_range(20.0, 56.0, 0.5) var vat_out_mm := 46.0
## And the socket, on the other side. Seeded within a few mm of this.
@export_range(20.0, 56.0, 0.5) var socket_out_mm := 42.0
## How far the measurement may push the vat off `vat_out_mm`.
@export_range(0.0, 20.0, 0.5) var vat_out_spread := 9.0
## Half the jar's width on the diagram. The vat is never pushed so far out that its far wall leaves
## the panel.
@export_range(5.0, 30.0, 0.5) var vat_wall_mm := 13.0

# -- the claw ------------------------------------------------------------------------------------
@export_range(20.0, 200.0, 1.0) var claw_speed := 80.0      ## mm/s, flat out
@export_range(40.0, 900.0, 5.0) var claw_accel := 340.0     ## mm/s^2 getting going
@export_range(40.0, 900.0, 5.0) var claw_brake := 400.0     ## mm/s^2 pulling up
@export_range(0.3, 3.0, 0.05) var dip_time := 1.2           ## down, shut, up
@export_range(2.0, 30.0, 0.5) var grab_reach := 10.0        ## mm off the eye the jaws still find it

# -- the eye on its nerve --------------------------------------------------------------------------
@export_range(3.0, 16.0, 0.5) var eye_mm := 7.0             ## the eyeball's radius on the diagram
@export_range(8.0, 60.0, 0.5) var cord_mm := 28.0           ## how far under the jaws it hangs
@export_range(0.3, 3.0, 0.05) var swing_period := 1.90      ## seconds for one swing out and back
@export_range(0.3, 12.0, 0.1) var swing_damp := 3.4         ## seconds for the swing to fall off by e
@export_range(10.0, 90.0, 1.0) var slip_deg := 50.0         ## past this it tears off the jaws

# -- the two mouths --------------------------------------------------------------------------------
@export_range(2.0, 40.0, 0.5) var vat_tol_mm := 12.0        ## the vat's mouth
@export_range(2.0, 40.0, 0.5) var socket_tol_mm := 9.0      ## the socket
@export_range(2.0, 40.0, 0.5) var bounce_mm := 14.0         ## how far past the rim a bad drop rolls
@export_range(0.1, 3.0, 0.05) var sink_time := 0.9          ## it going in, or it falling on the table
@export_range(0.1, 3.0, 0.05) var settle_time := 0.6        ## and coming to rest

# -- the graft's keyway ------------------------------------------------------------------------------
@export_range(0.0, 360.0, 5.0) var pupil_rate := 90.0       ## deg/s the eye turns while it hangs
@export_range(0.0, 90.0, 1.0) var pupil_straight := 20.0    ## inside this and it is stitched in straight

# -- audio -----------------------------------------------------------------------------------------
@export var dip_cue := "surgery_swish"
@export var grip_cue := "surgery_forceps_click"
@export var clink_cue := "surgery_forceps_clink"
@export var seat_cue := "surgery_forceps_squelch"
@export var glass_cue := "items_glass"

# ---- replicated state ----
var stage: int = Stage.SOURCE
var claw_x := 0.0                 ## mm along the rail
var claw_v := 0.0                 ## mm/s
var claw_y := 0.0                 ## mm, the jaws' height
var jaw := 0.0                    ## 0 wide open .. 1 shut
var holding := false              ## the eye is in the jaws
var theta := 0.0                  ## radians off vertical; + is the eye hanging to the right
var theta_v := 0.0
var cord_now := 0.0               ## the nerve pays out as the claw lifts
var cycle_t := 0.0                ## seconds into the dip
var sink := 0.0                   ## 0 let go .. 1 landed
var settle := 0.0
var pupil_deg := 0.0              ## which way the iris keyway points; grab only
var offset_deg := 0.0             ## and what it was when the jaws opened
var rest_x := 0.0                 ## where the loose eye is lying
var land_ok := false              ## the drop that is playing out went in
var fall_from := Vector2.ZERO
var fall_to := Vector2.ZERO
var drops := 0                    ## eyes on the floor
var misses := 0                   ## dips that came up empty

# ---- the board, from the seed and the real vat ----
var mode := "grab"
var vat_x := -46.0
var socket_x := 42.0
var src_x := 0.0
var tgt_x := 0.0
var measured := false

# ---- local ----
var _rng := RandomNumberGenerator.new()
var _t := 0.0
var _want_v := 0.0
var _drop_edge := false
var _pivot_accel := 0.0           ## what the carriage did to the pendulum's pivot this frame
var _vis_eye := Vector2.ZERO
var _vis_claw := Vector2.ZERO
var _seen_holding := false
var _seen_drops := 0
var _seen_misses := 0
var _seen_stage: int = Stage.SOURCE
var _slip_flash := 0.0
## Tuning read-outs for the self-test: the worst swing anyone got into, and how far off the mouth
## the eye was the last time the jaws opened.
var peak_swing_deg := 0.0
var last_drop_mm := 0.0

# ---- bot ----
var _bt := 0.0
var _b_x := 0.0
var _b_seq := 0
var _b_err := 0.0
var _b_err_for := -1


# ---------------------------------------------------------------------------- setup

func card_word_for_start() -> String:
	return "GRAB!"


func build_game() -> void:
	mode = "place" if String(ctx.get("variant", "grab")) == "place" else "grab"
	_rng.seed = int(ctx.get("seed", 1)) ^ 0x9e11
	_layout()
	src_x = vat_x if mode == "grab" else socket_x
	tgt_x = socket_x if mode == "grab" else vat_x
	rest_x = src_x
	# Parked over the chute, the way a claw machine parks: the whole rail is in front of you.
	claw_x = tgt_x
	claw_y = carry_y
	cord_now = cord_mm
	_vis_claw = Vector2(claw_x, claw_y)
	_vis_eye = Vector2(rest_x, rest_y)
	_b_x = claw_x
	_update_progress()


## Where the two ends of the rail are. The vat is the REAL one standing on the table (ctx.vat, the
## same node eye_seat measures): which side of the head it is on picks the side, and how far out it
## is stretches the rail to match. With no vat to measure -- the lab, or a table somebody cleared --
## it falls back to eye_seat's own fallback spot, which is on the left.
func _layout() -> void:
	var at := VAT_FALLBACK
	var vat = ctx.get("vat")
	if vat != null and is_instance_valid(vat) and vat is Node3D:
		# Out of the tree (the self-test, a game built before its site is parented) the global
		# transforms are not there to ask for, so fall back to the plain local positions.
		var l: Vector3 = to_local((vat as Node3D).global_position) \
			if is_inside_tree() and (vat as Node3D).is_inside_tree() \
			else transform.affine_inverse() * (vat as Node3D).position
		at = Vector2(l.x, l.z)
		measured = true
	var side: float = -1.0 if at.x <= 0.0 else 1.0
	var out: float = vat_out_mm * clampf(at.length(), VAT_NEAR_M, VAT_FAR_M) / 0.20
	# The jar has to fit on the panel whole, however far out the real one is standing.
	var edge: float = minf(rail_half, view_mm().x * 0.5 - vat_wall_mm - 4.0)
	vat_x = side * clampf(clampf(out, vat_out_mm - vat_out_spread, vat_out_mm + vat_out_spread),
		12.0, edge)
	# And the socket faces it, a seeded few millimetres nearer or further.
	socket_x = -side * clampf(socket_out_mm + _rng.randf_range(-5.0, 5.0), 12.0,
		minf(rail_half - 8.0, view_mm().x * 0.5 - eye_mm - 11.0))


func target_tol() -> float:
	return socket_tol_mm if mode == "grab" else vat_tol_mm


## The pendulum's stiffness, from the period you asked for and the length it is hanging on.
func swing_gravity() -> float:
	var w: float = TAU / maxf(0.05, swing_period)
	return w * w * maxf(1.0, cord_mm)


## Where the eyeball actually is, in diagram millimetres. Everything -- the aim, the drop, the
## drawing -- reads it from here, so the swing is never cosmetic.
func eye_at() -> Vector2:
	match stage:
		Stage.CARRY:
			return Vector2(claw_x + cord_now * sin(theta), claw_y + cord_now * cos(theta))
		Stage.DIP:
			if holding:
				return Vector2(claw_x + cord_now * sin(theta), claw_y + cord_now * cos(theta))
			return Vector2(rest_x, rest_y)
		Stage.LAND:
			var k: float = smoothstep(0.0, 1.0, clampf(sink, 0.0, 1.0))
			return fall_from.lerp(fall_to, k)
		Stage.SETTLE, Stage.DONE:
			return fall_to
	return Vector2(rest_x, rest_y)


## How far off upright the iris keyway is, folded to +/-180.
func pupil_offset() -> float:
	var a: float = fposmod(pupil_deg + 180.0, 360.0) - 180.0
	return a


func pupil_straight_now() -> bool:
	return absf(pupil_offset()) <= pupil_straight


# ---------------------------------------------------------------------------- playing

func keys() -> Array:
	match stage:
		Stage.SOURCE:
			return [["A / D or Mouse", "run the claw"], ["Space", "drop the claw"]]
		Stage.DIP:
			return [["Wait", "the claw is committed"]]
		Stage.CARRY:
			return [["A / D or Mouse", "carry it over"], ["Space", "open the jaws"]]
	return []


func hint() -> String:
	var base := super.hint()
	if base != "":
		return base
	var where := "vat" if mode == "place" else "socket"
	match stage:
		Stage.SOURCE:
			if absf(claw_x - rest_x) <= grab_reach:
				return "Over it. Drop the claw."
			return "Line the claw up over the eye."
		Stage.DIP:
			return "Down, shut, up. Nothing to do."
		Stage.CARRY:
			if absf(rad_to_deg(theta)) > slip_deg * 0.7:
				return "It's swinging off the jaws. Stop shoving it."
			if mode == "grab" and not pupil_straight_now():
				return "Over the %s, and wait for the keyway to come up straight." % where
			return "Let go with the eye over the %s, not the claw." % where
		Stage.LAND:
			return "In it goes." if land_ok else "It bounced off the rim."
		Stage.SETTLE:
			return "In it goes."
	return "Seated." if mode == "grab" else "It's in the vat."


## The operator's hand. Nothing is decided here: it says which way the claw is being asked to go and
## whether the button went down, and advance() does the physics.
func play(p: Vector2, buttons: int, edges: int, _delta: float) -> void:
	if edges & (BUTTON_ACTION | BUTTON_PRIMARY):
		_drop_edge = true
	if buttons & BUTTON_LEFT:
		_want_v = -claw_speed
	elif buttons & BUTTON_RIGHT:
		_want_v = claw_speed
	else:
		# The mouse eases in near the cursor, so a steady hand barely swings the eye and a snatched
		# one swings it like a key held down. Same top speed, same weight, either way.
		var dx: float = p.x - claw_x
		_want_v = 0.0 if absf(dx) < 0.6 else clampf(dx * 6.0, -claw_speed, claw_speed)


func advance(delta: float) -> void:
	_t += delta
	match stage:
		Stage.SOURCE:
			_drive(delta, _want_v)
			jaw = maxf(0.0, jaw - delta * 4.0)
			claw_y = move_toward(claw_y, carry_y, 60.0 * delta)
			if _drop_edge:
				stage = Stage.DIP
				cycle_t = 0.0
				holding = false
		Stage.DIP:
			_drive(delta, 0.0)   # committed: the claw ignores the hand until it is back up
			_dip(delta)
		Stage.CARRY:
			_drive(delta, _want_v)
			jaw = 1.0
			claw_y = move_toward(claw_y, carry_y, 80.0 * delta)
			cord_now = move_toward(cord_now, cord_mm, 60.0 * delta)
			_swing(delta)
			if mode == "grab":
				pupil_deg = fposmod(pupil_deg + pupil_rate * delta, 360.0)
			if absf(rad_to_deg(theta)) > slip_deg:
				_slip()
			elif _drop_edge:
				_let_go()
		Stage.LAND:
			_drive(delta, 0.0)
			jaw = maxf(0.0, jaw - delta * 5.0)
			sink = minf(1.0, sink + delta / maxf(0.05, sink_time))
			if sink >= 1.0:
				if land_ok:
					stage = Stage.SETTLE
					settle = 0.0
				else:
					stage = Stage.SOURCE
					theta = 0.0
					theta_v = 0.0
					cord_now = cord_mm
		Stage.SETTLE:
			_drive(delta, 0.0)
			jaw = maxf(0.0, jaw - delta * 5.0)
			settle += delta
			if settle >= settle_time:
				_home()
				return
	_drop_edge = false
	_want_v = 0.0
	_update_progress()


## The carriage has weight. Getting going is one number, pulling up is another, and the difference
## is what the eye feels.
func _drive(delta: float, want: float) -> void:
	var rate: float = claw_accel
	if absf(want) < absf(claw_v) or (want != 0.0 and signf(want) != signf(claw_v) and claw_v != 0.0):
		rate = claw_brake
	var next_v: float = move_toward(claw_v, want, rate * delta)
	var acc: float = (next_v - claw_v) / maxf(0.0001, delta)
	claw_v = next_v
	claw_x += claw_v * delta
	if claw_x < -rail_half:
		claw_x = -rail_half
		claw_v = 0.0
	elif claw_x > rail_half:
		claw_x = rail_half
		claw_v = 0.0
	_pivot_accel = acc


## Down, shut, up, 1.2 seconds, and the hand is out of it. The jaws find the eye if they came down
## within a jaw's width of it; otherwise they come back up with nothing and you go again.
func _dip(delta: float) -> void:
	var before: float = cycle_t / maxf(0.05, dip_time)
	cycle_t += delta
	var f: float = clampf(cycle_t / maxf(0.05, dip_time), 0.0, 1.0)
	var low: float = rest_y - eye_mm - 1.0
	if f < DIP_DOWN:
		claw_y = lerpf(carry_y, low, smoothstep(0.0, 1.0, f / DIP_DOWN))
		jaw = maxf(0.0, jaw - delta * 4.0)
		cord_now = eye_mm + 1.0
	elif f < DIP_SHUT:
		claw_y = low
		jaw = minf(1.0, jaw + delta / maxf(0.02, dip_time * (DIP_SHUT - DIP_DOWN)))
	else:
		var up: float = (f - DIP_SHUT) / maxf(0.01, 1.0 - DIP_SHUT)
		claw_y = lerpf(low, carry_y, smoothstep(0.0, 1.0, up))
		jaw = 1.0
		cord_now = lerpf(eye_mm + 1.0, cord_mm, smoothstep(0.0, 1.0, up))
	# The moment the jaws arrive is the moment it is decided.
	if before < DIP_DOWN and f >= DIP_DOWN:
		holding = absf(claw_x - rest_x) <= grab_reach
		theta = 0.0
		theta_v = 0.0
		if not holding:
			misses += 1
	if f >= 1.0:
		if holding:
			stage = Stage.CARRY
			if mode == "grab":
				pupil_deg = 0.0
		else:
			stage = Stage.SOURCE
			claw_y = carry_y
			cord_now = cord_mm


## A pendulum hanging off a pivot that is being shoved along a rail. Shove it in time with the swing
## and the swing grows; that is the whole difficulty of the carry.
func _swing(delta: float) -> void:
	var g: float = swing_gravity()
	var l: float = maxf(1.0, cord_now)
	var steps: int = maxi(1, int(ceil(delta / 0.02)))
	var h: float = delta / float(steps)
	for i in steps:
		var acc: float = -(g / l) * sin(theta) - (_pivot_accel / l) * cos(theta) \
			- (2.0 / maxf(0.05, swing_damp)) * theta_v
		theta_v += acc * h
		theta += theta_v * h
	peak_swing_deg = maxf(peak_swing_deg, absf(rad_to_deg(theta)))


## Past fifty degrees the nerve tears off the jaws and the eye goes back where it came from.
func _slip() -> void:
	drops += 1
	_slip_flash = 0.5
	holding = false
	land_ok = false
	fall_from = eye_at()
	fall_to = Vector2(rest_x, rest_y)
	stage = Stage.LAND
	sink = 0.0
	shake(0.35)


## The jaws open. What counts is where the EYE is, swing and all -- not where the claw is.
func _let_go() -> void:
	var at: Vector2 = eye_at()
	last_drop_mm = at.x - tgt_x
	offset_deg = pupil_offset() if mode == "grab" else 0.0
	holding = false
	fall_from = at
	sink = 0.0
	stage = Stage.LAND
	if absf(at.x - tgt_x) <= target_tol():
		land_ok = true
		fall_to = Vector2(tgt_x, rest_y)
	else:
		# Off the rim and onto the table beside it. Pick it up from there.
		land_ok = false
		var side: float = signf(at.x - tgt_x)
		if side == 0.0:
			side = 1.0
		drops += 1
		rest_x = clampf(tgt_x + side * (target_tol() + bounce_mm), -rail_half, rail_half)
		fall_to = Vector2(rest_x, rest_y)


func _home() -> void:
	stage = Stage.DONE
	progress = 1.0
	# Every drop and every empty dip costs time and nothing else, but the machine still keeps score.
	quality = snappedf(clampf(1.0 - 0.08 * float(drops) - 0.04 * float(misses), 0.15, 1.0), 0.01)
	if mode == "grab":
		var off: float = 0.0 if absf(offset_deg) <= pupil_straight else snappedf(offset_deg, 1.0)
		arcade_finish({"eye_seated": true, "eye_offset_deg": off})
	else:
		arcade_finish({"eye_in_vat": true})


func _update_progress() -> void:
	var span: float = maxf(absf(tgt_x - src_x), 1.0)
	var p := 0.04
	match stage:
		Stage.SOURCE:
			p = 0.04
		Stage.DIP:
			p = 0.08
		Stage.CARRY:
			p = 0.12 + 0.44 * clampf(1.0 - absf(eye_at().x - tgt_x) / span, 0.0, 1.0)
		Stage.LAND:
			p = (0.60 + 0.35 * sink) if land_ok else 0.12
		Stage.SETTLE:
			p = 0.96
		Stage.DONE:
			p = 1.0
	progress = 1.0 if stage == Stage.DONE else minf(p, 0.99)


## A stir cannot shake an eyeball out of a claw: GRAB! ignores jolts, exactly as the legacy step did.
func on_jolt(_offset: Vector2, _strength: float, _duration: float) -> void:
	pass


# ---------------------------------------------------------------------------- every machine

func animate(delta: float) -> void:
	_slip_flash = maxf(0.0, _slip_flash - delta)
	var k: float = 1.0 - exp(-delta * 22.0)
	_vis_claw = _vis_claw.lerp(Vector2(claw_x, claw_y), k)
	_vis_eye = _vis_eye.lerp(eye_at(), k)


## Sounds off the replicated state, so an onlooker hears the claw too.
func react() -> void:
	if holding and not _seen_holding:
		audio(grip_cue, -7.0, 0.08)
	_seen_holding = holding
	if stage != _seen_stage:
		if stage == Stage.DIP:
			audio(dip_cue, -14.0, 0.1)
		elif stage == Stage.SETTLE:
			audio(glass_cue if mode == "place" else seat_cue, -5.0, 0.08)
		_seen_stage = stage
	if drops != _seen_drops:
		_seen_drops = drops
		audio(clink_cue, -4.0, 0.1)
	if misses != _seen_misses:
		_seen_misses = misses
		audio(clink_cue, -12.0, 0.1)


# ---------------------------------------------------------------------------- the diagram

func paint_game(c: CanvasItem) -> void:
	if panel == null:
		return
	var st := style()
	_paint_table(c, st)
	_paint_socket(c, st)
	_paint_vat(c, st)
	_paint_target(c, st)
	_paint_pickup(c, st)
	_paint_rail(c, st)
	_paint_claw(c, st)
	_paint_eye(c, st)
	if mode == "grab":
		_paint_keyway_dial(c, st)
	_paint_scoreboard(c, st)
	if _slip_flash > 0.0:
		c.draw_rect(Rect2(Vector2.ZERO, panel.tex_size()), Color(st.sloppy, _slip_flash * 0.14))


func _paint_table(c: CanvasItem, st: StyleScript) -> void:
	var a := px(Vector2(-rail_half - 6.0, floor_y))
	var b := px(Vector2(rail_half + 6.0, floor_y))
	c.draw_line(a, b, Color(st.line_dim, 0.9), st.thin)
	var x := -rail_half - 4.0
	while x < rail_half + 6.0:
		c.draw_line(px(Vector2(x, floor_y)), px(Vector2(x - 3.0, floor_y + 3.4)), Color(st.line_dim, 0.4), st.hair)
		x += 6.0


## The rail, with its stops, and a tick every ten millimetres so the claw's travel can be read.
func _paint_rail(c: CanvasItem, st: StyleScript) -> void:
	var a := px(Vector2(-rail_half - 4.0, rail_y))
	var b := px(Vector2(rail_half + 4.0, rail_y))
	st.glow_line(c, a, b, st.steel, st.thin)
	c.draw_line(a, b, st.steel, st.outline)
	var i := -5
	while i <= 5:
		var x: float = rail_half * float(i) / 5.0
		c.draw_line(px(Vector2(x, rail_y)), px(Vector2(x, rail_y + 2.4)), Color(st.line_dim, 0.7), st.hair)
		i += 1
	for s: float in [-1.0, 1.0]:
		var e: float = s * (rail_half + 4.0)
		c.draw_line(px(Vector2(e, rail_y - 3.5)), px(Vector2(e, rail_y + 3.5)), st.steel, st.thin)


func _paint_claw(c: CanvasItem, st: StyleScript) -> void:
	var cx: float = _vis_claw.x
	var cy: float = _vis_claw.y
	# The carriage on the rail.
	var car := Rect2(px(Vector2(cx - 5.0, rail_y - 2.6)), px(Vector2(cx + 5.0, rail_y + 2.6)) - px(Vector2(cx - 5.0, rail_y - 2.6)))
	c.draw_rect(car, Color(st.steel, 0.35))
	c.draw_rect(car, st.steel, false, st.thin)
	# The hoist cable, and the claw's body on the end of it.
	c.draw_line(px(Vector2(cx, rail_y + 2.6)), px(Vector2(cx, cy - 4.0)), Color(st.steel, 0.85), st.thin)
	var head: PackedVector2Array = PackedVector2Array([
		px(Vector2(cx - 4.4, cy - 4.0)), px(Vector2(cx + 4.4, cy - 4.0)),
		px(Vector2(cx + 2.8, cy)), px(Vector2(cx - 2.8, cy))])
	c.draw_colored_polygon(head, Color(st.steel, 0.30))
	st.glow_poly(c, head, st.steel, st.hair)
	c.draw_polyline(head, st.steel, st.thin)
	c.draw_line(head[0], head[3], st.steel, st.thin)
	# Three jaws, splayed open and folded shut. Shut is drawn as a closed V, not just a colour.
	var shut: float = clampf(jaw, 0.0, 1.0)
	for s: float in [-1.0, 0.0, 1.0]:
		var spread: float = lerpf(7.0, 1.2, shut) * s
		var tip := Vector2(cx + spread, cy + 6.5)
		var knee := Vector2(cx + spread * 0.55, cy + 2.4)
		c.draw_line(px(Vector2(cx + s * 2.2, cy)), px(knee), st.steel, st.thin)
		c.draw_line(px(knee), px(tip), st.steel, st.thin)


func _paint_socket(c: CanvasItem, st: StyleScript) -> void:
	var at := Vector2(socket_x, rest_y + 1.0)
	var r: float = eye_mm + 4.0
	# A bowl cut into the table: dark inside, bright rim, lashes so it reads as a socket.
	var bowl: PackedVector2Array = PackedVector2Array()
	for i in 17:
		var a: float = lerpf(PI, TAU, float(i) / 16.0)
		bowl.append(px(at + Vector2(cos(a) * r, -sin(a) * r * 0.95)))
	c.draw_colored_polygon(bowl, st.blood_dark)
	c.draw_polyline(bowl, Color(st.line, 0.9), st.thin)
	c.draw_line(px(at + Vector2(-r, 0.0)), px(at + Vector2(r, 0.0)), Color(st.line, 0.9), st.thin)
	for i in 5:
		var x: float = lerpf(-r * 0.8, r * 0.8, float(i) / 4.0)
		c.draw_line(px(at + Vector2(x, 0.0)), px(at + Vector2(x * 1.15, -3.0)), Color(st.line_dim, 0.8), st.hair)


## The specimen vat as it stands on the table: a jar, its fluid hatched so it reads without colour,
## and an open mouth to aim at.
func _paint_vat(c: CanvasItem, st: StyleScript) -> void:
	var hw: float = vat_wall_mm
	var mouth: float = rest_y - 13.0
	var fluid: float = rest_y - 4.0
	for s: float in [-1.0, 1.0]:
		c.draw_line(px(Vector2(vat_x + s * hw, mouth)), px(Vector2(vat_x + s * hw, floor_y - 1.0)),
			Color(st.line, 0.85), st.thin)
		c.draw_line(px(Vector2(vat_x + s * hw, mouth)), px(Vector2(vat_x + s * (hw + 2.6), mouth - 1.8)),
			Color(st.line, 0.85), st.thin)
	c.draw_line(px(Vector2(vat_x - hw, floor_y - 1.0)), px(Vector2(vat_x + hw, floor_y - 1.0)),
		Color(st.line, 0.85), st.thin)
	c.draw_line(px(Vector2(vat_x - hw - 3.0, floor_y)), px(Vector2(vat_x + hw + 3.0, floor_y)),
		Color(st.steel, 0.9), st.thin)
	c.draw_line(px(Vector2(vat_x - hw, fluid)), px(Vector2(vat_x + hw, fluid)), Color(st.line_dim, 0.95), st.thin)
	var y := fluid + 2.2
	while y < floor_y - 1.5:
		c.draw_line(px(Vector2(vat_x - hw + 1.0, y)), px(Vector2(vat_x + hw - 1.0, y - 2.0)),
			Color(st.line_dim, 0.30), st.hair)
		y += 3.0


## The mouth you are aiming at, drawn across the rim itself: a bracket the width of the tolerance,
## and a plumb line down from the eye. Solid and chevroned when the eye would go in, dashed and dim
## when it would not -- so it reads as a shape and not only as green.
func _paint_target(c: CanvasItem, st: StyleScript) -> void:
	var tol: float = target_tol()
	var y: float = (rest_y - 15.5) if mode == "place" else (rest_y - 7.5)
	var at: Vector2 = eye_at()
	var over: bool = absf(at.x - tgt_x) <= tol and (stage == Stage.CARRY or stage == Stage.DIP)
	var col: Color = st.good if over else Color(st.line_dim, 0.9)
	for s: float in [-1.0, 1.0]:
		c.draw_line(px(Vector2(tgt_x + s * tol, y - 3.0)), px(Vector2(tgt_x + s * tol, y + 3.0)), col, st.thin)
	if over:
		c.draw_line(px(Vector2(tgt_x - tol, y)), px(Vector2(tgt_x + tol, y)), col, st.thin)
	else:
		st.dashed(c, px(Vector2(tgt_x - tol, y)), px(Vector2(tgt_x + tol, y)), col, st.hair, 5.0, 4.0)
	if stage != Stage.CARRY and stage != Stage.DIP:
		return
	# The plumb line: where the eye would land if you opened the jaws right now.
	st.dashed(c, px(Vector2(at.x, at.y + eye_mm)), px(Vector2(at.x, y - 4.0)),
		Color(col, 0.9), st.thin, 4.0, 4.0)
	var tip := px(Vector2(at.x, y - 4.0))
	if over:
		c.draw_line(tip, tip + Vector2(-6.0, -8.0), col, st.thin)
		c.draw_line(tip, tip + Vector2(6.0, -8.0), col, st.thin)
	else:
		# Off the mouth: a bar through the plumb line, and an arrow at the rim saying which way.
		c.draw_line(tip + Vector2(-5.0, -5.0), tip + Vector2(5.0, -5.0), col, st.thin)
		var dir: float = signf(tgt_x - at.x)
		var a := px(Vector2(at.x + dir * 6.0, y - 4.0))
		c.draw_line(a, a + Vector2(dir * 7.0, 0.0), col, st.hair)


## Where the loose eye is, and how much room the jaws have. The marks close on the eye when the claw
## is over it: the one thing you have to get right before you commit.
func _paint_pickup(c: CanvasItem, st: StyleScript) -> void:
	if stage != Stage.SOURCE:
		return
	var inside: bool = absf(claw_x - rest_x) <= grab_reach
	var col: Color = st.good if inside else Color(st.line_dim, 0.9)
	var y: float = rest_y - eye_mm - 3.5
	for s: float in [-1.0, 1.0]:
		var x: float = rest_x + s * grab_reach
		c.draw_line(px(Vector2(x, y - 3.5)), px(Vector2(x, y)), col, st.thin)
		c.draw_line(px(Vector2(x, y)), px(Vector2(x - s * 3.5, y)), col, st.thin)
	if inside:
		st.dashed(c, px(Vector2(claw_x, _vis_claw.y + 7.0)), px(Vector2(claw_x, y - 4.0)),
			Color(col, 0.8), st.hair, 4.0, 4.0)


func _paint_eye(c: CanvasItem, st: StyleScript) -> void:
	var at: Vector2 = _vis_eye
	var carried: bool = holding and (stage == Stage.CARRY or stage == Stage.DIP)
	if carried:
		# The nerve it is hanging on: a kinked line, not a straight one, so it reads as tissue.
		var top := Vector2(_vis_claw.x, _vis_claw.y + 5.5)
		var mid: Vector2 = top.lerp(at, 0.5) + Vector2(sin(_t * 3.0) * 0.8, 0.0)
		c.draw_line(px(top), px(mid), Color(st.blood, 0.95), st.thin)
		c.draw_line(px(mid), px(at - Vector2(0.0, eye_mm * 0.6)), Color(st.blood, 0.95), st.thin)
	var p := px(at)
	var r: float = px_len(eye_mm)
	st.glow_circle(c, p, r, st.line, st.thin)
	c.draw_circle(p, r, Color(st.thread, 0.14))
	c.draw_arc(p, r, 0.0, TAU, 28, st.line, st.outline)
	# The iris, and a keyway notch on it. The notch is the whole point on a graft: it is where the
	# top of the eye is, and it is a SHAPE, so it reads with the colour off.
	var roll: float = deg_to_rad(pupil_deg if mode == "grab" else 0.0)
	var up := Vector2(sin(roll), -cos(roll))
	c.draw_circle(p, r * 0.52, Color(st.line_dim, 0.85))
	c.draw_arc(p, r * 0.52, 0.0, TAU, 20, Color(st.line, 0.9), st.thin)
	c.draw_circle(p, r * 0.22, Color(st.bg, 0.95))
	var straight: bool = mode != "grab" or pupil_straight_now()
	var kc: Color = st.good if straight else st.sloppy
	var perp := Vector2(-up.y, up.x)
	var key: PackedVector2Array = PackedVector2Array([
		p + up * r * 0.78, p + up * r * 0.40 + perp * r * 0.20, p + up * r * 0.40 - perp * r * 0.20])
	c.draw_colored_polygon(key, kc)
	c.draw_polyline(key, kc, st.hair)


## Grab only: which way up the eye is going in, against the sector that counts as straight.
func _paint_keyway_dial(c: CanvasItem, st: StyleScript) -> void:
	# Parked at the end of the rail the eye is coming FROM, where nothing else is by the time it
	# matters -- the claw is busy at the other end and would sit right on top of it.
	var at := Vector2(-signf(tgt_x) * (rail_half - 12.0), -3.0)
	var p := px(at)
	var r: float = px_len(9.0)
	c.draw_arc(p, r, 0.0, TAU, 28, Color(st.line_dim, 0.8), st.hair)
	# The straight sector, marked with ticks and a bar rather than a colour fill.
	var half := deg_to_rad(pupil_straight)
	c.draw_arc(p, r, -PI * 0.5 - half, -PI * 0.5 + half, 12, Color(st.good, 0.9), st.thin)
	for s: float in [-1.0, 1.0]:
		var a: float = -PI * 0.5 + s * half
		var d := Vector2(cos(a), sin(a))
		c.draw_line(p + d * r * 0.72, p + d * r * 1.18, Color(st.good, 0.9), st.hair)
	var roll: float = deg_to_rad(pupil_deg)
	var n := Vector2(sin(roll), -cos(roll))
	var col: Color = st.good if pupil_straight_now() else st.sloppy
	c.draw_line(p, p + n * r * 0.9, col, st.thin)
	c.draw_circle(p + n * r * 0.9, px_len(1.4), col)
	c.draw_circle(p, px_len(1.2), Color(st.line, 0.9))


## What the machine is doing, and what it has cost you, in words under the rail.
func _paint_scoreboard(c: CanvasItem, st: StyleScript) -> void:
	var font := ThemeDB.fallback_font
	var txt := ""
	match stage:
		Stage.SOURCE:
			txt = "LINE IT UP"
		Stage.DIP:
			txt = "DROPPING"
		Stage.CARRY:
			txt = "CARRYING"
		_:
			txt = "IN" if land_ok else "ON THE TABLE"
	if drops > 0:
		txt += "    DROPPED %d" % drops
	if misses > 0:
		txt += "    EMPTY %d" % misses
	if mode == "grab" and (stage == Stage.CARRY or stage == Stage.DIP):
		txt += "    KEYWAY %d deg" % int(round(absf(pupil_offset())))
	var w: float = font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x
	var col: Color = st.sloppy if drops > 0 or misses > 0 else Color(st.line_dim, 0.95)
	c.draw_string(font, px(Vector2(0.0, floor_y + 6.5)) + Vector2(-w * 0.5, 0.0), txt,
		HORIZONTAL_ALIGNMENT_LEFT, -1.0, 22, col)


# ---------------------------------------------------------------------------- net

## Almost everything in this game CREEPS -- the carriage, the swing, the dip clock, the eye turning
## on its nerve -- and the lab round-trips this dictionary through apply_net_state every frame, so
## snapping any of it would stop it dead. Only the things that jump are snapped.
func net_pack() -> Dictionary:
	return {
		"sg": stage, "cx": claw_x, "cv": claw_v, "cy": claw_y, "jw": jaw,
		"hd": holding, "th": theta, "tv": theta_v, "cn": cord_now, "ct": cycle_t,
		"sk": sink, "se": settle, "pu": pupil_deg, "od": snappedf(offset_deg, 0.5),
		"rx": snappedf(rest_x, 0.1), "sx": snappedf(src_x, 0.1), "tx": snappedf(tgt_x, 0.1),
		"vx": snappedf(vat_x, 0.1), "ox": snappedf(socket_x, 0.1),
		"ok": land_ok, "ff": fall_from, "ft": fall_to, "dr": drops, "ms": misses,
	}


func net_apply(s: Dictionary) -> void:
	stage = int(s.get("sg", stage))
	claw_x = float(s.get("cx", claw_x))
	claw_v = float(s.get("cv", claw_v))
	claw_y = float(s.get("cy", claw_y))
	jaw = float(s.get("jw", jaw))
	holding = bool(s.get("hd", holding))
	theta = float(s.get("th", theta))
	theta_v = float(s.get("tv", theta_v))
	cord_now = float(s.get("cn", cord_now))
	cycle_t = float(s.get("ct", cycle_t))
	sink = float(s.get("sk", sink))
	settle = float(s.get("se", settle))
	pupil_deg = float(s.get("pu", pupil_deg))
	offset_deg = float(s.get("od", offset_deg))
	rest_x = float(s.get("rx", rest_x))
	src_x = float(s.get("sx", src_x))
	tgt_x = float(s.get("tx", tgt_x))
	vat_x = float(s.get("vx", vat_x))
	socket_x = float(s.get("ox", socket_x))
	land_ok = bool(s.get("ok", land_ok))
	fall_from = s.get("ff", fall_from)
	fall_to = s.get("ft", fall_to)
	drops = int(s.get("dr", drops))
	misses = int(s.get("ms", misses))


# ---------------------------------------------------------------------------- bot

## A careful hand moves the cursor steadily, lines the claw up before it commits, and waits for the
## swing to die (and, on a graft, for the keyway to come round) before it opens the jaws. A sloppy
## one snatches the claw about, which pumps the pendulum, and lets go too early.
##
## Its error is a golden-ratio sequence, not a random draw: the same hand on every seed, so the
## numbers do not swing from patient to patient for no reason.
func bot_input(t: float, skill: float) -> Dictionary:
	var dt: float = clampf(t - _bt, 0.0, 0.1)
	_bt = t
	# Nobody stands there forever. A bad hand steadies up once it has been at this long enough.
	var sk: float = clampf(maxf(clampf(skill, 0.0, 1.0), (t - 18.0) / 14.0), 0.0, 1.0)
	if not armed():
		return {"cursor": _out(_b_x), "buttons": 0}
	if drops + misses != _b_err_for:
		_b_err_for = drops + misses
		_b_seq += 1
		var u: float = fposmod(float(_b_seq) * 0.6180339887498949, 1.0)
		_b_err = (u - 0.5) * 2.0 * lerpf(13.0, 0.8, sk)
	var buttons := 0
	match stage:
		Stage.SOURCE:
			var aim: float = clampf(rest_x + _b_err * 0.5, -rail_half, rail_half)
			_b_x = move_toward(_b_x, aim, lerpf(95.0, 38.0, sk) * dt)
			# A good hand allows for the coast. A bad one hits the button where the claw is right
			# now and watches it drift on past the eye all the way down.
			var stop_at: float = claw_x + signf(claw_v) * claw_v * claw_v / (2.0 * claw_brake)
			var lead: float = lerpf(claw_x, stop_at, sk)
			if absf(lead - rest_x) < grab_reach * lerpf(0.85, 0.45, sk) \
					and absf(claw_v) < lerpf(38.0, 9.0, sk):
				buttons |= BUTTON_ACTION
		Stage.CARRY:
			# A bad hand fidgets on the way over, at about the speed the eye wants to swing, which is
			# the worst thing you can do to a pendulum.
			var travel: float = clampf(absf(tgt_x - claw_x) / 25.0, 0.0, 1.0)
			var wobble: float = (1.0 - sk) * 9.0 * sin(t * 4.2) * travel
			var aim2: float = clampf(tgt_x + _b_err + wobble, -rail_half, rail_half)
			_b_x = move_toward(_b_x, aim2, lerpf(95.0, 34.0, sk) * dt)
			var at: Vector2 = eye_at()
			# And it aims the CLAW, not the eye: the classic way to lose an eyeball off a rim.
			var judge: float = lerpf(claw_x, at.x, clampf(sk * 2.0, 0.0, 1.0))
			var near: bool = absf(judge - tgt_x) <= target_tol() * lerpf(1.3, 0.50, sk)
			var calm: bool = absf(theta_v) < lerpf(3.0, 0.30, sk)
			# Nobody hovers forever waiting for the keyway. Past half a minute it goes in crooked.
			var keyed: bool = mode != "grab" or sk < 0.35 or t > lerpf(12.0, 30.0, sk) \
				or absf(pupil_offset()) <= pupil_straight * 0.7
			if near and calm and keyed:
				buttons |= BUTTON_ACTION
	return {"cursor": _out(_b_x), "buttons": buttons}


func _out(x: float) -> Vector2:
	return panel.metres_of(Vector2(x, 0.0)) if panel != null else Vector2(x, 0.0)


# ---------------------------------------------------------------------------- self-test

## Headless: `tools/minigame_lab.tscn -- --selftest=eye:grab:arcade`.
## GRAB! is no-fail, so the target is TIME only: skill 1.0 finishes in 8-20 s, skill 0.0 under 40 s,
## and nothing anywhere may cost a single vital.
static func self_test() -> Array:
	var script: GDScript = load("res://scripts/surgery/arcade/grab_arcade.gd")
	var out := []
	var ok := true
	for case: Dictionary in [
			{"variant": "place", "pid": "hive", "ailment": "eye_extraction", "idx": 3, "flag": "eye_in_vat"},
			{"variant": "grab", "pid": "player", "ailment": "eye_graft", "idx": 2, "flag": "eye_seated"}]:
		for sed: float in [1.0, 0.4]:
			for skill: float in [1.0, 0.5, 0.0]:
				var g = script.new()
				var tally := {"n": 0, "v": 0.0, "done": false, "flag": false, "off": 0.0}
				g.botched.connect(func(a, r): tally.n += 1; tally.v += a; print("  botch %.1f %s" % [a, r]))
				g.finished.connect(func(r):
					tally.done = true
					tally.flag = bool(r.get(case.flag, false))
					tally.off = float(r.get("eye_offset_deg", 0.0)))
				g.setup(_case_ctx(case, sed, hash("grabclaw" + String(case.variant) + str(sed))))
				var t: float = run_bot(g, skill, sed, hash(String(case.variant)) + int(skill * 100), 60.0)
				print("[grab-arcade self-test] %-5s sed=%.1f skill=%.1f  %s  time=%5.1fs  dropped=%d empty=%d  worst swing=%3.0f deg  last drop %+5.1f mm  keyway=%4.0f  vitals=%.1f" % [
					String(case.variant), sed, skill, "DONE" if tally.done else "UNFINISHED",
					t, g.drops, g.misses, g.peak_swing_deg, g.last_drop_mm, tally.off, tally.v])
				out.append({"variant": String(case.variant), "sed": sed, "skill": skill,
					"done": tally.done, "time": t, "vitals": tally.v, "drops": g.drops})
				if not tally.done or not tally.flag:
					print("[grab-arcade self-test] MISS: %s must finish with {\"%s\": true}" % [case.variant, case.flag])
					ok = false
				if tally.n > 0:
					print("[grab-arcade self-test] MISS: GRAB! is no-fail and cost %.1f vitals" % tally.v)
					ok = false
				if skill == 1.0 and (t < 8.0 or t > 20.0):
					print("[grab-arcade self-test] MISS: skill 1.0 wants 8-20 s, got %.1f" % t)
					ok = false
				if skill == 0.0 and t > 40.0:
					print("[grab-arcade self-test] MISS: skill 0.0 wants under 40 s, got %.1f" % t)
					ok = false
				g.free()
	# The board: the real vat on the table picks the side and the distance, and with no vat at all it
	# falls back to eye_seat's own fallback spot, on the left. Both ways the socket faces it.
	var no_vat = script.new()
	no_vat.setup(_case_ctx({"variant": "grab", "pid": "player", "ailment": "eye_graft", "idx": 2}, 1.0, 7))
	var probe := Node3D.new()
	probe.position = Vector3(0.19, -0.13, -0.08)
	var with_vat = script.new()
	var vctx: Dictionary = _case_ctx({"variant": "grab", "pid": "player", "ailment": "eye_graft", "idx": 2}, 1.0, 7)
	vctx["vat"] = probe
	with_vat.setup(vctx)
	print("[grab-arcade self-test] no vat -> vat at %+.0f mm, socket %+.0f (fallback)   vat on the right -> vat at %+.0f mm, socket %+.0f" % [
		no_vat.vat_x, no_vat.socket_x, with_vat.vat_x, with_vat.socket_x])
	if no_vat.vat_x > 0.0 or no_vat.measured or with_vat.vat_x < 0.0 or not with_vat.measured \
			or signf(with_vat.socket_x) == signf(with_vat.vat_x):
		print("[grab-arcade self-test] MISS: the board must follow ctx.vat, and fall back without one")
		ok = false
	out.append({"vat_x_fallback": no_vat.vat_x, "vat_x_measured": with_vat.vat_x})
	no_vat.free()
	with_vat.free()
	probe.free()
	# A spectator watching the blob sees what the operator sees, the whole way across.
	var live = script.new()
	live.setup(_case_ctx({"variant": "place", "pid": "hive", "ailment": "eye_extraction", "idx": 3}, 1.0, 21))
	var watcher = script.new()
	var wctx: Dictionary = _case_ctx({"variant": "place", "pid": "hive", "ailment": "eye_extraction", "idx": 3}, 1.0, 21)
	wctx["operator"] = false
	watcher.setup(wctx)
	var worst := 0.0
	var steps := 0
	while steps < 1800 and not live.done:
		steps += 1
		var inp: Dictionary = live.bot_input(float(steps) / 60.0, 1.0)
		live.handle_cursor(inp.get("cursor", Vector2.ZERO), int(inp.get("buttons", 0)), 1.0 / 60.0)
		live.tick(1.0 / 60.0)
		watcher.apply_net_state(live.net_state())
		watcher.tick(1.0 / 60.0)
		worst = maxf(worst, watcher.eye_at().distance_to(live.eye_at()))
	print("[grab-arcade self-test] spectator tracks the eye to within %.2f mm over %d frames" % [worst, steps])
	if worst > 0.5:
		print("[grab-arcade self-test] MISS: a spectator must see the same eye in the same place")
		ok = false
	out.append({"spectator_error_mm": worst})
	live.free()
	watcher.free()
	print("[grab-arcade self-test] %s" % ("PASS" if ok else "FAIL"))
	return out


static func _case_ctx(case: Dictionary, sed: float, seed_v: int) -> Dictionary:
	var c := {
		"patient_id": String(case.pid), "patient": Procedures.patient(String(case.pid)),
		"ailment_id": String(case.ailment), "step": Procedures.step(String(case.ailment), int(case.idx)),
		"variant": String(case.variant), "shift": 1, "difficulty": Procedures.difficulty(1),
		"flags": {"sedation": sed}, "seed": seed_v, "body": null,
		"operator": true, "operating": true,
	}
	if String(case.ailment) == "eye_graft":
		c["no_fail"] = true
		c["eye_kind"] = "eye_surgeon"
		c["eye_kind_in"] = "eye_hive"
	return c
