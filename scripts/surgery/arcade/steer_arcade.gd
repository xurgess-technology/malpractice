extends "res://scripts/surgery/arcade/arcade_game.gd"
## ARCADE SURGERY (docs/ARCADE_SURGERY.md) 5.8 -- STEER! Step "cut" of an eye job: open the ring
## round the eye. The arcade rebuild of the `cut` variant of scripts/surgery/games/eye_ops.gd,
## played on the raised panel. EX step 1 on a strapped Hive, EG step 1 on a strapped surgeon.
##
## Rhyme: a top-down racer on a ring track.
##
## What you do
##   The socket is the circuit. The scalpel drives itself forward and you only steer it: A and D
##   round the ring, W for the boost. Stay between the two lines and the incision opens behind you.
##   THE INSIDE WALL IS THE EYEBALL. Clip it and you have nicked the eye, which is the one thing
##   here that costs anything. The outside wall is the drape: hit that and the blade lifts, and so
##   does wandering off the track for more than a moment. A lift is free -- you are set back down at
##   the cut front -- but it is time, and time is the whole game.
##   VESSELS cross the track. Roll over one slowly and it seals. Take it at speed and it opens: it
##   costs, it puts a blot of blood across that stretch of the ring for the rest of the step, and it
##   is written into the case as `vessel_bleeds` -- the stitch step hides its dots under exactly
##   those blots (5.12), so a fast lap here is paid for two steps later.
##   THE EYE IS AWAKE. On a Hive the pupil snaps round to find the blade and the eyeball BULGES
##   toward it a moment later, so the inside wall moves while you are riding it. A surgeon on the
##   graft table just watches you work.
##
## Result {"eye_cut": true, "vessel_bleeds": [deg, ...], "cut_quality": q}. The angles are degrees
## round the ring, measured the way the panel's diagram measures them: atan2(y, x) with +y DOWN,
## wrapped to 0..360. The ring game (ring_arcade.gd) reads them back in the same frame of reference.

const SAMPLES := 64

# -- the circuit ---------------------------------------------------------------------------------
## The eyeball's radius on the diagram, and the inside wall of the track. Nudged by the case's
## `eye_radius` so a surgeon's smaller eye is a slightly tighter circuit than a Hive's.
@export_range(4.0, 26.0, 0.5) var eye_mm := 12.0
## The track's centreline, this far out from the eyeball's edge.
@export_range(4.0, 30.0, 0.5) var track_gap_mm := 10.5
## Half the width of the track. Outside it you are off the line and the clock is running.
@export_range(2.0, 16.0, 0.5) var track_half_mm := 9.0
## The drape, this far past the track's outer edge. Touching it lifts the blade.
@export_range(1.0, 14.0, 0.5) var outer_gap_mm := 3.0

# -- the blade -----------------------------------------------------------------------------------
## It drives itself: this is how fast, and how fast with the boost held.
@export_range(4.0, 80.0, 0.5) var drive_mm_s := 16.0
@export_range(8.0, 140.0, 0.5) var boost_mm_s := 34.0
@export_range(20.0, 360.0, 5.0) var steer_deg := 140.0
@export_range(20.0, 360.0, 5.0) var steer_boost_deg := 120.0
## Off the track for longer than this and the blade lifts out.
@export_range(0.05, 2.0, 0.05) var off_grace := 0.4
@export_range(0.1, 3.0, 0.05) var lift_time := 0.6
## How far ahead of the cut front the blade may be and still extend it: a short hop off the line is
## forgiven, a whole stretch skipped is not.
@export_range(2.0, 90.0, 1.0) var jump_tol_deg := 20.0
## The last sliver of the ring, which the incision closes on its own.
@export_range(1.0, 40.0, 1.0) var finish_slack_deg := 12.0

# -- the vessels ---------------------------------------------------------------------------------
@export_range(1, 6) var vessels_min := 2
@export_range(1, 8) var vessels_max := 4
@export_range(1.0, 20.0, 0.5) var vessel_mm := 6.0        ## how wide a vessel's band is
## Cross one faster than this and it opens. It sits between the two driving speeds on purpose.
@export_range(4.0, 120.0, 0.5) var vessel_fast_mm_s := 24.0
@export_range(2.0, 60.0, 1.0) var blot_deg := 12.0        ## how much of the ring a bleed hides
@export_range(0.0, 10.0, 0.1) var vessel_botch := 1.5

# -- the eyeball ---------------------------------------------------------------------------------
@export_range(0.0, 20.0, 0.5) var nick_botch := 5.0
## Hive only: it looks for the blade this often, telegraphs for `stare_tell`, then bulges.
@export_range(0.5, 20.0, 0.1) var stare_min := 3.0
@export_range(0.5, 20.0, 0.1) var stare_max := 5.0
@export_range(0.05, 3.0, 0.05) var stare_tell := 0.4
@export_range(0.05, 3.0, 0.05) var bulge_time := 0.6
@export_range(0.0, 16.0, 0.5) var bulge_mm := 4.0
@export_range(5.0, 120.0, 1.0) var bulge_span_deg := 40.0

# -- jolts ---------------------------------------------------------------------------------------
@export_range(0.0, 90.0, 1.0) var jolt_kick_deg := 20.0

# -- the bot (the lab only; a player has their own bad habits) -------------------------------------
## How far off the centreline a skill-0 hand aims, and how long it holds that line before picking a
## new one. Skewed past the middle so the bad line is usually the inside one.
@export_range(0.0, 40.0, 0.5) var bot_wander_mm := 26.0
@export_range(0.1, 4.0, 0.05) var bot_hold := 1.2
@export_range(0.0, 1.0, 0.01) var bot_skew := 0.66
## How far inside its line the bad hand has to have thrown the blade before it comes off the boost.
@export_range(0.0, 1.0, 0.01) var bot_lift_off := 0.52
## How long a skill-0 hand takes to notice it has gone wrong and let go of the key.
@export_range(0.0, 1.0, 0.01) var bot_react := 0.26

# -- audio ---------------------------------------------------------------------------------------
@export var cut_cue := "surgery_swish"
@export var slip_cue := "surgery_forceps_clink"
@export var nick_cue := "surgery_tear"
@export var bleed_cue := "surgery_saw_squelch"
@export_range(-40.0, 0.0, 1.0) var cut_volume := -20.0

# ---- replicated state ----
var pos := Vector2.ZERO           ## the blade, mm
var head := 0.0                   ## its heading, radians
var cut := 0.0                    ## radians of the ring opened so far, 0..TAU
var boosting := false
var lift_left := 0.0              ## seconds the blade is out of the skin
var off_t := 0.0                  ## how long it has been off the track
var slips := 0
var nicks := 0
var bleeds: Array = []            ## the carry-forward: angles in degrees, one per opened vessel
var look_a := 0.0                 ## where the pupil is pointed
var bulge_a := 0.0
var bulge_k := 0.0                ## 0..1, how far the eyeball is pushed out toward `bulge_a`
var staring := false              ## the telegraph: it has found the blade and is about to move

# ---- derived from the seed ----
var hive := false
var vessels: Array = []           ## [{"a": radians, "hit": bool, "bled": bool}]
var start_a := PI * 0.5           ## the bottom of the ring: where the incision begins and ends

# ---- local ----
var _rng := RandomNumberGenerator.new()
var _t := 0.0
var _stare_t := 0.0
var _stare_left := 0.0
var _stare_phase := 0             ## 0 waiting, 1 telegraph, 2 bulging
var _nick_flash := 0.0
var _ribbon: Array = []           ## the incision as it was actually cut, mm
var _ribbon_cut := -1.0
var _seen_nicks := 0
var _seen_slips := 0
var _seen_bleeds := 0
## Why the blade came out, and how close it ever came to the eyeball. The lab reads these; nothing
## else does, and they are not replicated.
var lifts_line := 0
var lifts_wall := 0
var closest_r := 999.0

# ---- bot ----
var _bt := 0.0
var _b_seq := 0
var _b_err := 0.0
var _b_next := 0.0
var _b_react := 0.0
var _b_btn := 0


# ---------------------------------------------------------------------------- setup

func card_word_for_start() -> String:
	return "STEER!"


func build_game() -> void:
	hive = String(ctx.get("patient_id", "hive")) != "player"
	_rng.seed = int(ctx.get("seed", 1)) ^ 0x57e3
	# The diagram is a diagram, not a scale drawing, but a surgeon's smaller eye still makes for a
	# slightly tighter circuit than a Hive's.
	var er: float = float(ctx.get("eye_radius", 0.0155))
	eye_mm *= clampf(er / 0.0155, 0.85, 1.15)
	_build_vessels()
	pos = ring_point(start_a, centre_r())
	head = start_a + PI * 0.5
	look_a = start_a
	_stare_t = _rng.randf_range(stare_min, stare_max)
	_update_progress()


## Two to four of them, never on the start line and never on top of each other, so every lap has
## the same shape of decision in a different order.
func _build_vessels() -> void:
	vessels.clear()
	var n: int = _rng.randi_range(mini(vessels_min, vessels_max), maxi(vessels_min, vessels_max))
	var tries := 0
	while vessels.size() < n and tries < 200:
		tries += 1
		var a: float = _rng.randf_range(0.5, TAU - 0.5)
		var ok := true
		for v in vessels:
			if absf(angle_difference(float(v.a), a)) < 0.7:
				ok = false
				break
		if ok:
			vessels.append({"a": fposmod(start_a + a, TAU), "hit": false, "bled": false})
	vessels.sort_custom(func(x, y): return float(x.a) < float(y.a))


# ---------------------------------------------------------------------------- the circuit

func centre_r() -> float:
	return eye_mm + track_gap_mm


func track_in() -> float:
	return centre_r() - track_half_mm


func track_out() -> float:
	return centre_r() + track_half_mm


func wall_r() -> float:
	return track_out() + outer_gap_mm


func ring_point(a: float, r: float) -> Vector2:
	return Vector2(cos(a), sin(a)) * r


func blade_angle() -> float:
	return atan2(pos.y, pos.x)


## The inside wall where it is right now. On a Hive it moves: the eyeball bulges toward wherever it
## last looked, which is wherever the blade was 0.4 s ago.
func eye_radius_at(a: float) -> float:
	if bulge_k <= 0.001:
		return eye_mm
	var span := deg_to_rad(bulge_span_deg)
	var d: float = absf(angle_difference(a, bulge_a))
	if d >= span:
		return eye_mm
	return eye_mm + bulge_mm * bulge_k * (0.5 + 0.5 * cos(PI * d / span))


func speed_now() -> float:
	return boost_mm_s if boosting else drive_mm_s


## True where a bleed has painted the ring out. Guidance only: it still cuts under there.
func hidden_at(a: float) -> bool:
	for v in vessels:
		if bool(v.bled) and absf(angle_difference(a, float(v.a))) <= deg_to_rad(blot_deg):
			return true
	return false


# ---------------------------------------------------------------------------- playing

func keys() -> Array:
	if play_state == Play.DONE:
		return []
	return [["A / D", "steer"], ["W", "boost"]]


func hint() -> String:
	var base := super.hint()
	if base != "":
		return base
	if play_state == Play.DONE:
		return "All the way round."
	if lift_left > 0.0:
		return "The blade lifted. Back down at the cut front."
	if not bleeds.is_empty():
		return "Slow over the vessels. That one is going to cost you at the stitches."
	if boosting:
		return "Quick, and it takes the outside line."
	return "Keep it between the lines."


func play(_p: Vector2, buttons: int, _edges: int, delta: float) -> void:
	if lift_left > 0.0:
		boosting = false
		return
	boosting = (buttons & BUTTON_UP) != 0
	var rate: float = deg_to_rad(steer_boost_deg if boosting else steer_deg) * delta
	if buttons & BUTTON_LEFT:
		head -= rate
	if buttons & BUTTON_RIGHT:
		head += rate
	head = fposmod(head, TAU)


func advance(delta: float) -> void:
	_eye_watches(delta)
	if lift_left > 0.0:
		lift_left = maxf(0.0, lift_left - delta)
		if lift_left <= 0.0:
			_set_down()
		return
	closest_r = minf(closest_r, pos.length())
	var prev_a := blade_angle()
	pos += Vector2(cos(head), sin(head)) * speed_now() * delta
	_check_vessels(prev_a)
	_extend_cut()
	if play_state == Play.DONE:
		return
	_check_walls(delta)


## The eye is awake and it is watching. On a Hive that is a hazard: it finds the blade, telegraphs
## for a moment, then the eyeball pushes out toward where it looked. On the graft table the patient
## is a surgeon under a local, and all they do is watch.
func _eye_watches(delta: float) -> void:
	if not hive:
		look_a = lerp_angle(look_a, blade_angle(), clampf(delta * 3.0, 0.0, 1.0))
		bulge_k = 0.0
		staring = false
		return
	match _stare_phase:
		0:
			look_a = lerp_angle(look_a, blade_angle(), clampf(delta * 0.8, 0.0, 1.0))
			bulge_k = maxf(0.0, bulge_k - delta / maxf(0.05, bulge_time))
			_stare_t -= delta
			if _stare_t <= 0.0:
				_stare_phase = 1
				_stare_left = stare_tell
				staring = true
				look_a = blade_angle()
		1:
			look_a = blade_angle()
			_stare_left -= delta
			if _stare_left <= 0.0:
				_stare_phase = 2
				_stare_left = bulge_time
				staring = false
				bulge_a = look_a
		2:
			_stare_left -= delta
			# Out fast, back slow, so the wall arrives before you can argue with it.
			var k: float = 1.0 - clampf(_stare_left / maxf(0.05, bulge_time), 0.0, 1.0)
			bulge_k = sin(clampf(k, 0.0, 1.0) * PI)
			if _stare_left <= 0.0:
				_stare_phase = 0
				_stare_t = _rng.randf_range(stare_min, stare_max)


## One vessel is crossed the moment the blade's angle sweeps over it. What it does about that is
## entirely down to how fast the blade was going.
func _check_vessels(prev_a: float) -> void:
	var a := blade_angle()
	if absf(angle_difference(prev_a, a)) < 1e-6:
		return
	for v in vessels:
		if bool(v.hit):
			continue
		var d0: float = angle_difference(prev_a, float(v.a))
		var d1: float = angle_difference(a, float(v.a))
		if signf(d0) == signf(d1) or absf(d0) > 0.6 or absf(d1) > 0.6:
			continue
		v.hit = true
		if speed_now() <= vessel_fast_mm_s:
			audio(cut_cue, cut_volume + 6.0, 0.1)
			continue
		v.bled = true
		bleeds.append(snappedf(rad_to_deg(fposmod(float(v.a), TAU)), 0.1))
		audio(bleed_cue, -4.0, 0.1)
		shake(0.5)
		cost(vessel_botch, "Opened a vessel at speed")


func _extend_cut() -> void:
	var r := pos.length()
	if r < track_in() or r > track_out():
		return
	var prog: float = fposmod(blade_angle() - start_a, TAU)
	if prog > cut + deg_to_rad(jump_tol_deg):
		return
	if prog > cut:
		cut = prog
		_update_progress()
		if cut >= TAU - deg_to_rad(finish_slack_deg):
			_through()


func _check_walls(delta: float) -> void:
	var r := pos.length()
	var a := blade_angle()
	if r <= eye_radius_at(a):
		nicks += 1
		_nick_flash = 0.5
		shake(0.9)
		cost(nick_botch, "The scalpel nicked the eyeball")
		_lift("nick")
		return
	if r >= wall_r():
		_lift("wall")
		return
	if r < track_in() or r > track_out():
		off_t += delta
		if off_t > off_grace:
			_lift()
	else:
		off_t = 0.0


## A free slip: the blade comes out, and it goes back down at the cut front. It costs nothing but
## the seconds, which on a one-lap circuit is quite enough.
func _lift(why := "off") -> void:
	if lift_left > 0.0:
		return
	if why == "wall":
		lifts_wall += 1
	elif why == "off":
		lifts_line += 1
	slips += 1
	lift_left = lift_time
	off_t = 0.0
	boosting = false
	audio(slip_cue, -18.0, 0.15)


func _set_down() -> void:
	var a: float = start_a + cut
	pos = ring_point(a, centre_r())
	head = fposmod(a + PI * 0.5, TAU)
	off_t = 0.0


func _through() -> void:
	cut = TAU
	progress = 1.0
	quality = cut_quality()
	arcade_finish({"eye_cut": true, "vessel_bleeds": bleeds.duplicate(), "cut_quality": quality})


func cut_quality() -> float:
	var q := 1.0 - 0.06 * float(slips) - 0.1 * float(nicks) - 0.08 * float(bleeds.size())
	return snappedf(clampf(q, 0.05, 1.0), 0.01)


func _update_progress() -> void:
	progress = clampf(cut / TAU, 0.0, 1.0)


## A jerk knocks the blade off its heading, which on a ring track is the whole of the difficulty.
func on_jolt(_offset: Vector2, strength: float, _duration: float) -> void:
	head = fposmod(head + deg_to_rad(jolt_kick_deg) * (1.0 if _rng.randf() < 0.5 else -1.0), TAU)
	shake(clampf(0.4 + strength * 0.5, 0.0, 1.0))


func animate(delta: float) -> void:
	_t += delta
	_nick_flash = maxf(0.0, _nick_flash - delta)
	# The incision is drawn from where the blade actually went, not from the centreline, so a
	# wobbly lap leaves a wobbly scar. Every machine builds it from the replicated blade.
	if lift_left <= 0.0 and cut > _ribbon_cut + 0.015:
		_ribbon_cut = cut
		_ribbon.append(pos)
		while _ribbon.size() > 220:
			_ribbon.pop_front()


# ---------------------------------------------------------------------------- the body

func react() -> void:
	var b = body()
	if nicks > _seen_nicks:
		_seen_nicks = nicks
		_nick_flash = maxf(_nick_flash, 0.5)
		audio(nick_cue, -4.0, 0.1)
		ghost(0.5)
		if b != null and b.has_method("stir"):
			b.stir(0.7)
	if slips > _seen_slips:
		_seen_slips = slips
	if bleeds.size() > _seen_bleeds:
		_seen_bleeds = bleeds.size()
		if b != null and b.has_method("stir"):
			b.stir(0.35)
	if b != null and b.has_method("set_bleeding"):
		var site := String(ctx.get("step", {}).get("site", "eye"))
		var amount: float = clampf(0.08 + progress * 0.25 + float(bleeds.size()) * 0.18 + _nick_flash * 0.5, 0.0, 1.0)
		b.set_bleeding(site, amount if play_state != Play.DONE else 0.3)


# ---------------------------------------------------------------------------- the diagram

func paint_game(c: CanvasItem) -> void:
	if panel == null:
		return
	var st := style()
	_paint_track(c, st)
	_paint_eye(c, st)
	_paint_ribbon(c, st)
	_paint_vessels(c, st)
	_paint_blade(c, st)
	_paint_scoreboard(c, st)
	if _nick_flash > 0.0:
		c.draw_rect(Rect2(Vector2.ZERO, panel.tex_size()), Color(st.danger, _nick_flash * 0.2))


func _arc_pts(r: float, from: float, to: float, steps: int) -> PackedVector2Array:
	var out: PackedVector2Array = PackedVector2Array()
	for i in steps + 1:
		out.append(px(ring_point(lerpf(from, to, float(i) / float(steps)), r)))
	return out


func _paint_track(c: CanvasItem, st) -> void:
	var o := px(Vector2.ZERO)
	# The drape: the hard edge of the field, dashed so it never reads as part of the track.
	for i in 40:
		var a0: float = TAU * float(i) / 40.0
		c.draw_arc(o, px_len(wall_r()), a0, a0 + TAU / 70.0, 3, Color(st.line_dim, 0.7), st.thin)
	# The road itself, faintly filled so the two lines read as one band and not as two rings.
	var band: PackedVector2Array = _arc_pts(track_out(), 0.0, TAU, SAMPLES)
	var inner: PackedVector2Array = _arc_pts(track_in(), TAU, 0.0, SAMPLES)
	for p in inner:
		band.append(p)
	c.draw_colored_polygon(band, Color(st.line_dim, 0.10))
	c.draw_polyline(_arc_pts(track_out(), 0.0, TAU, SAMPLES), Color(st.line_dim, 0.85), st.thin)
	c.draw_polyline(_arc_pts(track_in(), 0.0, TAU, SAMPLES), Color(st.line_dim, 0.85), st.thin)
	# The line to follow, dashed, and gone where a bleed has painted it out.
	for i in 72:
		var a: float = TAU * float(i) / 72.0
		if hidden_at(a):
			continue
		c.draw_arc(o, px_len(centre_r()), a, a + TAU / 150.0, 3, Color(st.line_dim, 0.5), st.hair)
	# The start and finish line across the track, with its own ticks.
	var sa := px(ring_point(start_a, track_in()))
	var sb := px(ring_point(start_a, track_out()))
	st.dashed(c, sa, sb, Color(st.line, 0.8), st.thin, 4.0, 4.0)


func _paint_eye(c: CanvasItem, st) -> void:
	var shape: PackedVector2Array = PackedVector2Array()
	for i in SAMPLES:
		var a: float = TAU * float(i) / float(SAMPLES)
		shape.append(px(ring_point(a, eye_radius_at(a))))
	shape.append(shape[0])
	c.draw_colored_polygon(shape, Color(st.bg_inner, 0.95))
	st.glow_poly(c, shape, st.line, st.thin)
	c.draw_polyline(shape, st.line, st.outline)
	# The wall is called out by pattern as well as by being the eye: barbs pointing in, all the way
	# round, so "do not touch this" reads even where the blot has covered the colour.
	for i in 48:
		var a: float = TAU * float(i) / 48.0
		var r := eye_radius_at(a)
		c.draw_line(px(ring_point(a, r)), px(ring_point(a, r - 1.8)), Color(st.line, 0.55), st.hair)
	# The iris and the pupil, pointed at whatever it is looking at. The pupil is drawn as a slit on
	# a Hive and round on a surgeon, so whose eye it is reads without a caption.
	var off: float = eye_mm * 0.34
	var at: Vector2 = ring_point(look_a, off)
	var ir := eye_mm * 0.46
	c.draw_arc(px(at), px_len(ir), 0.0, TAU, 22, Color(st.line, 0.8), st.thin)
	for k in 10:
		var a: float = TAU * float(k) / 10.0
		c.draw_line(px(at + ring_point(a, ir * 0.45)), px(at + ring_point(a, ir)), Color(st.line, 0.45), st.hair)
	if hive:
		var up: Vector2 = ring_point(look_a + PI * 0.5, ir * 0.72)
		var wide: Vector2 = ring_point(look_a, ir * 0.22)
		c.draw_colored_polygon(PackedVector2Array([px(at + up), px(at + wide), px(at - up), px(at - wide)]), st.bg)
	else:
		c.draw_circle(px(at), px_len(ir * 0.5), st.bg)
	# The telegraph: it has found the blade and the wall is about to move.
	if staring:
		var k: float = 0.5 + 0.5 * sin(_t * 40.0)
		c.draw_arc(px(Vector2.ZERO), px_len(eye_mm + 1.6), look_a - 0.6, look_a + 0.6, 14,
			Color(st.danger, 0.45 + 0.45 * k), st.outline)
	if bulge_k > 0.01:
		var span := deg_to_rad(bulge_span_deg)
		c.draw_arc(px(Vector2.ZERO), px_len(eye_mm + bulge_mm * bulge_k + 1.2), bulge_a - span, bulge_a + span,
			20, Color(st.danger, 0.5 * bulge_k), st.thin)


## The incision, drawn along the line the blade really took.
func _paint_ribbon(c: CanvasItem, st) -> void:
	if cut <= 0.001:
		return
	var path: PackedVector2Array = PackedVector2Array()
	if _ribbon.size() >= 3:
		for p in _ribbon:
			path.append(px(p))
	else:
		path = _arc_pts(centre_r(), start_a, start_a + cut, maxi(3, int(cut * 12.0)))
	c.draw_polyline(path, st.blood_dark, px_len(2.6))
	st.glow_poly(c, path, st.danger, st.thin)
	c.draw_polyline(path, st.danger, st.outline)
	# Ticks across the open cut, every few samples: it reads as a parted edge and not as a drawn line.
	for i in range(2, path.size() - 1, 4):
		var t: Vector2 = (path[i + 1] - path[i - 1]).normalized().orthogonal()
		c.draw_line(path[i] - t * px_len(1.5), path[i] + t * px_len(1.5), Color(st.danger, 0.55), st.hair)


func _paint_vessels(c: CanvasItem, st) -> void:
	for v in vessels:
		var a := float(v.a)
		if bool(v.bled):
			_paint_blot(c, st, a)
			continue
		var half: float = (vessel_mm * 0.5) / maxf(1.0, centre_r())
		var r0 := eye_mm
		var r1 := wall_r()
		var col: Color = Color(st.sloppy, 0.85) if not bool(v.hit) else Color(st.line_dim, 0.5)
		var quad: PackedVector2Array = PackedVector2Array([
			px(ring_point(a - half, r0)), px(ring_point(a + half, r0)),
			px(ring_point(a + half, r1)), px(ring_point(a - half, r1))])
		c.draw_colored_polygon(quad, Color(col, 0.22))
		c.draw_polyline(PackedVector2Array([quad[0], quad[3]]), col, st.thin)
		c.draw_polyline(PackedVector2Array([quad[1], quad[2]]), col, st.thin)
		# Rungs across it: a vessel, not a stripe of colour.
		for k in 7:
			var r: float = lerpf(r0, r1, (float(k) + 0.5) / 7.0)
			c.draw_line(px(ring_point(a - half, r)), px(ring_point(a + half, r)), Color(col, 0.7), st.hair)


## What a vessel taken at speed leaves: a blot over that stretch of the ring, for good.
func _paint_blot(c: CanvasItem, st, a: float) -> void:
	var span := deg_to_rad(blot_deg)
	var outer: PackedVector2Array = _arc_pts(wall_r(), a - span, a + span, 14)
	var inner: PackedVector2Array = _arc_pts(eye_mm - 1.0, a + span, a - span, 14)
	for p in inner:
		outer.append(p)
	c.draw_colored_polygon(outer, Color(st.blood, 0.92))
	var rng := RandomNumberGenerator.new()
	rng.seed = int(round(rad_to_deg(a) * 10.0)) ^ 0x51a7
	for i in 9:
		var ra: float = a + rng.randf_range(-span, span)
		var rr: float = rng.randf_range(eye_mm, wall_r() + 3.0)
		c.draw_circle(px(ring_point(ra, rr)), px_len(rng.randf_range(1.6, 4.2)), Color(st.blood, 0.85))


func _paint_blade(c: CanvasItem, st) -> void:
	if lift_left > 0.0:
		# Lifted: where it is coming back down, and how long you have to wait.
		var k: float = 1.0 - lift_left / maxf(0.05, lift_time)
		var at := px(ring_point(start_a + cut, centre_r()))
		c.draw_arc(at, px_len(2.0 + 9.0 * (1.0 - k)), 0.0, TAU, 20, Color(st.steel, 0.55), st.thin)
		c.draw_arc(at, px_len(2.0), 0.0, TAU, 14, Color(st.steel, 0.8), st.hair)
		return
	var dir := Vector2(cos(head), sin(head))
	var side := dir.orthogonal()
	var nose: Vector2 = pos + dir * 4.2
	var tail_a: Vector2 = pos - dir * 2.6 + side * 2.0
	var tail_b: Vector2 = pos - dir * 2.6 - side * 2.0
	var body_col: Color = st.good if boosting else st.steel
	st.glow_poly(c, PackedVector2Array([px(nose), px(tail_a), px(tail_b), px(nose)]), body_col, st.thin)
	c.draw_colored_polygon(PackedVector2Array([px(nose), px(tail_a), px(tail_b)]), body_col)
	c.draw_polyline(PackedVector2Array([px(nose), px(tail_a), px(tail_b), px(nose)]), st.line, st.thin)
	# The boost is chevrons behind the blade as well as a colour, and they say which way it is going.
	if boosting:
		for k in 3:
			var back: Vector2 = pos - dir * (3.4 + 2.6 * float(k))
			c.draw_polyline(PackedVector2Array([px(back + side * 2.2), px(back - dir * 1.8), px(back - side * 2.2)]),
				Color(st.good, 0.8 - 0.2 * float(k)), st.thin)


## Where the lap is, and what it has cost, in numbers along the bottom-left where the ring is not.
func _paint_scoreboard(c: CanvasItem, st) -> void:
	var font := ThemeDB.fallback_font
	var txt := "LAP %d%%" % int(round(progress * 100.0))
	if nicks > 0:
		txt += "   NICKED %d" % nicks
	if not bleeds.is_empty():
		txt += "   BLED %d" % bleeds.size()
	if slips > 0:
		txt += "   LIFTS %d" % slips
	var col: Color = st.danger if nicks > 0 or not bleeds.is_empty() else Color(st.line_dim, 0.95)
	c.draw_string(font, px(Vector2(-56.0, 34.0)), txt, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 22, col)


# ---------------------------------------------------------------------------- net

## Everything a spectator needs to watch the lap. The blade's position, its heading and the lap
## itself all CREEP -- a couple of tenths of a millimetre a frame -- so they go out raw; snapping
## them would stop the blade dead on every machine that is not the operator's.
func net_pack() -> Dictionary:
	var vs: Array = []
	for v in vessels:
		vs.append(1 if bool(v.bled) else (2 if bool(v.hit) else 0))
	return {
		"bp": pos, "bh": head, "ct": cut, "bo": boosting, "lf": lift_left, "ot": off_t,
		"sl": slips, "nk": nicks, "bl": bleeds.duplicate(), "vs": vs,
		"la": look_a, "ba": bulge_a, "bk": bulge_k, "sr": staring,
	}


func net_apply(s: Dictionary) -> void:
	pos = s.get("bp", pos)
	head = float(s.get("bh", head))
	cut = float(s.get("ct", cut))
	boosting = bool(s.get("bo", boosting))
	lift_left = float(s.get("lf", lift_left))
	off_t = float(s.get("ot", off_t))
	slips = int(s.get("sl", slips))
	nicks = int(s.get("nk", nicks))
	bleeds = s.get("bl", bleeds)
	var vs: Array = s.get("vs", [])
	for i in mini(vs.size(), vessels.size()):
		vessels[i].bled = int(vs[i]) == 1
		vessels[i].hit = int(vs[i]) != 0
	look_a = float(s.get("la", look_a))
	bulge_a = float(s.get("ba", bulge_a))
	bulge_k = float(s.get("bk", bulge_k))
	staring = bool(s.get("sr", staring))
	_update_progress()


# ---------------------------------------------------------------------------- bot

## It aims at a radius and steers toward it. A good hand aims at the centreline, never boosts over a
## vessel, and gets round clean. A bad one boosts the whole way and aims at a radius that wanders --
## into the eyeball, into the drape, and over every vessel at full speed.
func bot_input(t: float, skill: float) -> Dictionary:
	var dt: float = clampf(t - _bt, 0.0, 0.1)
	_bt = t
	skill = clampf(skill, 0.0, 1.0)
	if not armed() or lift_left > 0.0:
		return {"cursor": _out(pos), "buttons": 0}
	# One aim error at a time, from a golden-ratio sequence: the same bad hand every run. It is
	# skewed to the INSIDE, because that is what a panicking driver does -- cut the corner -- and on
	# this circuit the inside of the corner is the eyeball.
	_b_next -= dt
	if _b_next <= 0.0:
		_b_next = bot_hold
		_b_seq += 1
		var u: float = fposmod(float(_b_seq) * 0.6180339887498949, 1.0)
		_b_err = (u - bot_skew) * 2.0 * lerpf(bot_wander_mm, 0.0, skill)
	# And it only LOOKS at the track every so often. A bad hand holds the key long past the moment it
	# should have let go, so it crosses its line and has to come back, over and over; a good one is
	# correcting every frame and never leaves the middle.
	_b_react -= dt
	if _b_react > 0.0:
		return {"cursor": _out(pos), "buttons": _b_btn}
	_b_react = lerpf(bot_react, 0.0, skill)
	var a := blade_angle()
	var want_r: float = clampf(centre_r() + _b_err, eye_mm - 5.0, wall_r() + 5.0)
	# Steer for the tangent, leaned toward the radius it wants to be riding. Turning further round
	# than the tangent pulls the blade IN, so a blade too far out wants a bigger heading. A good
	# hand eases onto its line; a bad one throws the blade at it and arrives sideways.
	var err: float = clampf((pos.length() - want_r) / lerpf(4.0, 12.0, skill), -1.0, 1.0)
	var want_head: float = a + PI * 0.5 + err * 0.9
	var d: float = angle_difference(head, want_head)
	_b_btn = 0
	if d > 0.02:
		_b_btn |= BUTTON_RIGHT
	elif d < -0.02:
		_b_btn |= BUTTON_LEFT
	# A good hand never touches the boost. A bad one leans on it, and only comes off it when it has
	# thrown the blade so far inside its line that even it can see the eyeball coming -- which is
	# also the only time it can turn hard enough to reach the eyeball at all.
	if skill < 0.5 and _b_err > -bot_wander_mm * bot_lift_off:
		_b_btn |= BUTTON_UP
	return {"cursor": _out(pos), "buttons": _b_btn}


func _out(mm: Vector2) -> Vector2:
	return panel.metres_of(mm) if panel != null else mm


# ---------------------------------------------------------------------------- self-test

## Headless check: `tools/minigame_lab.tscn -- --selftest=eye:cut:arcade`.
## Targets: skill 1.0 finishes in 8-20 s losing 0-2 vitals; skill 0.0 under 40 s losing 15-25. The
## graft sets `no_fail`, so there are no vitals to lose there and only the clock is checked.
static func self_test() -> Array:
	var script: GDScript = load("res://scripts/surgery/arcade/steer_arcade.gd")
	var out := []
	var ok := true
	var sloppy: Array = []
	for case: Dictionary in [{"pid": "hive", "ail": "eye_extraction"}, {"pid": "player", "ail": "eye_graft"}]:
		# The last row is a patient who is coming round: the framework's stirs jolt the heading.
		for cond: Dictionary in [{"skill": 1.0, "sed": 1.0}, {"skill": 0.5, "sed": 1.0},
				{"skill": 0.0, "sed": 1.0}, {"skill": 1.0, "sed": 0.35}]:
			var skill := float(cond.skill)
			var g = script.new()
			var tally := {"n": 0, "v": 0.0, "done": false, "q": 0.0, "bleeds": [], "reasons": {}}
			g.botched.connect(func(a, r): tally.n += 1; tally.v += a; tally.reasons[r] = int(tally.reasons.get(r, 0)) + 1)
			g.finished.connect(func(r): tally.done = true; tally.q = float(r.get("cut_quality", 0.0)); tally.bleeds = r.get("vessel_bleeds", []))
			g.setup(_ctx(String(case.pid), String(case.ail), hash("steer" + String(case.pid))))
			var t: float = run_bot(g, skill, float(cond.sed), hash(String(case.pid)) + int(skill * 100))
			print("[steer self-test] %-6s skill=%.1f sed=%.2f  %s  time=%5.1fs  lifts=%2d(line %d drape %d) closest=%4.1fmm nicks=%d bled=%d  botches=%2d vitals=%5.1f  q=%.2f  %s" % [
				case.pid, skill, cond.sed, "DONE" if tally.done else "UNFINISHED", t, g.slips,
				g.lifts_line, g.lifts_wall, g.closest_r, g.nicks,
				(tally.bleeds as Array).size(), tally.n, tally.v, tally.q, str(tally.reasons)])
			out.append({"patient": case.pid, "skill": skill, "sed": cond.sed, "done": tally.done,
				"time": t, "vitals": tally.v, "bleeds": tally.bleeds})
			if not tally.done:
				print("[steer self-test] MISS: it has to get round the lap")
				ok = false
			if float(cond.sed) < 0.9:
				g.free()
				continue
			if skill == 1.0 and (t < 8.0 or t > 20.0):
				print("[steer self-test] MISS: skill 1.0 wants 8-20 s")
				ok = false
			if skill == 0.0 and t > 40.0:
				print("[steer self-test] MISS: skill 0.0 wants to finish under 40 s")
				ok = false
			if String(case.pid) == "hive":
				if skill == 1.0 and tally.v > 2.0:
					print("[steer self-test] MISS: skill 1.0 wants 0-2 vitals")
					ok = false
				if skill == 0.0:
					sloppy.append(tally.v)
			else:
				if tally.v > 0.0:
					print("[steer self-test] MISS: the graft sets no_fail and must cost nothing")
					ok = false
			g.free()
	# The sloppy band, on the mean over several Hives: how many vessels a seeded ring happens to put
	# in the way, and where, swings one case a few vitals either side of the next on its own.
	for seed_v: int in [5, 23, 64, 88]:
		var g = script.new()
		var tally := {"v": 0.0}
		g.botched.connect(func(a, _r): tally.v += a)
		g.setup(_ctx("hive", "eye_extraction", seed_v))
		var t: float = run_bot(g, 0.0, 1.0, seed_v)
		print("[steer self-test] hive   skill=0.0 seed=%-3d  time=%5.1fs  lifts=%2d nicks=%d bled=%d  vitals=%5.1f" % [
			seed_v, t, g.slips, g.nicks, (g.bleeds as Array).size(), tally.v])
		sloppy.append(tally.v)
		if not g.done or t > 40.0:
			print("[steer self-test] MISS: skill 0.0 wants to finish under 40 s")
			ok = false
		g.free()
	var mean := 0.0
	for v: float in sloppy:
		mean += v
	mean /= maxf(1.0, float(sloppy.size()))
	print("[steer self-test] skill 0.0 on a Hive: %.1f vitals across %d cases (want 15-25)" % [mean, sloppy.size()])
	if mean < 15.0 or mean > 25.0:
		print("[steer self-test] MISS: skill 0.0 wants 15-25 vitals")
		ok = false
	# The carry-forward: a careful lap seals its vessels and a fast one does not. The angles are
	# degrees round the ring, and the stitch step (ring_arcade.gd) hides its dots under them.
	for seed_v: int in [3, 17, 41]:
		var careful := _lap(script, seed_v, 1.0)
		var fast := _lap(script, seed_v, 0.0)
		print("[steer self-test] seed=%-3d careful bleeds=%s   fast bleeds=%s" % [seed_v, str(careful), str(fast)])
		out.append({"seed": seed_v, "careful": careful, "fast": fast})
		if not careful.is_empty():
			print("[steer self-test] MISS: a careful lap should not open a vessel")
			ok = false
		if fast.is_empty():
			print("[steer self-test] MISS: a fast lap should open vessels")
			ok = false
		for a in fast:
			if float(a) < 0.0 or float(a) >= 360.0:
				print("[steer self-test] MISS: a vessel angle must be 0..360 degrees")
				ok = false
	print("[steer self-test] %s" % ("PASS" if ok else "FAIL"))
	return out


static func _ctx(pid: String, ail: String, seed_v: int) -> Dictionary:
	var c := {"patient_id": pid, "patient": Procedures.patient(pid), "ailment_id": ail,
		"step": Procedures.step(ail, 0), "variant": "cut", "shift": 1,
		"difficulty": Procedures.difficulty(1), "flags": {"sedation": 1.0},
		"seed": seed_v, "body": null, "operator": true, "operating": true}
	if ail == "eye_graft":
		c["no_fail"] = true
		c["eye_radius"] = Grafts.EYE_RADIUS
		c["flags"] = {"sedation": 1.0, "no_fail": true, "eye_radius": Grafts.EYE_RADIUS}
	return c


## One lap on a Hive at `skill`, and the vessel angles it leaves behind.
static func _lap(script: GDScript, seed_v: int, skill: float) -> Array:
	var g = script.new()
	g.setup(_ctx("hive", "eye_extraction", seed_v))
	run_bot(g, skill, 1.0, seed_v)
	var b: Array = (g.bleeds as Array).duplicate()
	g.free()
	return b
