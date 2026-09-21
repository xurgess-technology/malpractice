extends "res://scripts/surgery/arcade/arcade_game.gd"
## ARCADE SURGERY (docs/ARCADE_SURGERY.md) 5.2 -- DODGE! Step "extract" of a gunshot wound: get the
## bullet out. The arcade rebuild of scripts/surgery/games/forceps.gd, played on the raised panel.
##
## Rhyme: a side-scroller down a tunnel. Tap to lift, gravity does the rest.
##
## What you do
##   The forceps go in and take hold of the slug on their own -- that part was never the hard part.
##   You play the way OUT. The wound tract is the SAME tract the legacy game digs: the very channel
##   forceps.gd's generate_channel() lays out, unrolled. Arc length along its centreline becomes X
##   and the centreline's lateral wander becomes Y, so every bend you used to steer around is now a
##   climb or a dip coming at you.
##   The slug sinks. Tap to lift it. Hold the right button to brake, which buys you time to read the
##   tract and costs you the only thing the patient is short of.
##   It is DARK in there. You see 30 mm of tract ahead of the slug and no further -- and a teammate
##   standing over the wound with a flashlight doubles that. Alone you are reading the next two
##   seconds; with a friend, the next five.
##   The walls squeeze on every heartbeat. Touch one and you have torn the tract: blood, a flinch,
##   and the slug is dragged 22 mm back down the way you came.
##   Out through the mouth and the slug arcs into the kidney dish.
##
## Result {"bullet_removed": true, "tears": [arc positions]}. CARRY-FORWARD: `tears` is an Array of
## floats, the arc position 0..1 of every wall contact, 0 at the wound's mouth and 1 at the bullet
## bed -- generate_channel()'s own `s` convention, normalised. WHACK! (5.3) puts one bleeder on the
## tract per tear, so your mistakes here are waiting for you in the next step.

const ForcepsScript := preload("res://scripts/surgery/games/forceps.gd")

## How far ahead the bot's hand thinks, in seconds. Every skill uses the same one; what skill
## changes is how often it looks and how badly it is holding the thing.
const BOT_TAU := 0.12

# -- the tract --------------------------------------------------------------------------------
## How far the unrolled centreline may wander above and below the middle of the panel.
@export_range(4.0, 36.0, 0.5) var lane_span_mm := 18.0
## And the steepest it may climb, in mm of lift per mm of tract. A bend that would stand the tract
## on end is flattened until it can be flown.
@export_range(0.2, 3.0, 0.05) var lane_slope_max := 1.0
## Half-width of the slug in the jaws. The tract's own half-width has to beat this or you are
## touching a wall.
@export_range(1.0, 12.0, 0.1) var slug_half_mm := 5.8
## Where the slug sits on the panel. Everything to the right of it is tract you have not flown yet.
@export_range(-55.0, 0.0, 1.0) var slug_x := -42.0
## How much of the tract behind the slug stays drawn, dimmed: where you have been.
@export_range(0.0, 60.0, 1.0) var behind_mm := 18.0
## Where the wound's mouth comes to rest once it is in sight. The view stops scrolling there and
## the slug flies the last stretch across the panel instead.
@export_range(-40.0, 30.0, 1.0) var mouth_x := -6.0

# -- flying -----------------------------------------------------------------------------------
@export_range(2.0, 60.0, 0.5) var scroll_mm := 12.0        ## mm of tract per second
@export_range(0.1, 1.0, 0.05) var brake_frac := 0.5        ## what the right button cuts that to
@export_range(10.0, 600.0, 5.0) var gravity_mm := 90.0     ## mm/s^2 the slug sinks at
@export_range(4.0, 120.0, 1.0) var flap_mm := 26.0         ## upward mm/s a tap buys
@export_range(20.0, 300.0, 5.0) var max_fall_mm := 90.0    ## it never sinks faster than this

# -- the heartbeat ----------------------------------------------------------------------------
@export_range(0.1, 4.0, 0.05) var heart_hz := 1.25
## How far the walls come in at the top of a beat.
@export_range(0.0, 4.0, 0.05) var pinch_mm := 0.6

# -- the dark ---------------------------------------------------------------------------------
## How far ahead you can see on your own. A teammate's flashlight on the wound doubles it.
@export_range(5.0, 120.0, 1.0) var see_mm := 30.0

# -- tearing ----------------------------------------------------------------------------------
@export_range(0.0, 10.0, 0.5) var tear_botch := 2.5
@export_range(0.0, 80.0, 1.0) var knock_mm := 22.0         ## dragged back this far down the tract
@export_range(0.0, 4.0, 0.05) var grace_time := 0.9        ## blinking, untouchable, after a tear

# -- the ends ---------------------------------------------------------------------------------
@export_range(0.0, 4.0, 0.05) var intro_time := 1.0        ## the forceps going in and taking hold
@export_range(0.1, 3.0, 0.05) var exit_time := 0.8         ## the slug's flight to the dish
@export_range(0.0, 3.0, 0.05) var jolt_kick_mm := 40.0     ## vertical kick a stir throws in
@export_range(0.0, 2.0, 0.05) var jolt_grace := 0.35       ## and the forgiveness that comes with it

# -- audio ------------------------------------------------------------------------------------
@export var flap_cue := "surgery_forceps_click"
@export var tear_cue := "surgery_forceps_scrape"
@export var blood_cue := "surgery_forceps_squelch"
@export var dish_cue := "surgery_forceps_clink"
@export_range(-40.0, 0.0, 1.0) var flap_volume := -19.0

# ---- replicated state ----
var s_slug := 0.0                 ## arc position of the slug, mm. Counts DOWN to 0 at the mouth.
var fly_y := 0.0                  ## the slug's height, mm on the panel
var fly_v := 0.0                  ## mm/s, +y down
var beat_phase := 0.0             ## 0..1 through the current heartbeat
var intro_left := 0.0
var out_left := 0.0
var grace := 0.0
var braking := false
var tears: Array = []             ## THE CARRY-FORWARD: arc position 0..1 of every wall contact
var tear_side: Array = []         ## which wall each one was, -1 up / +1 down. Drawing only.
var tear_flash := 0.0

# ---- derived from the seed ----
var lane_pts := PackedFloat32Array()   ## the unrolled centreline, mm, one sample per `step_mm`
var half_pts := PackedFloat32Array()   ## the tract's half-width there, mm
var tract_mm := 120.0
var step_mm := 1.0

# ---- local ----
var _help := 0.0                  ## smoothed teammate flashlight, 0..1
var _seen_tears := 0
var _flap_kick := 0.0             ## fades out the puff behind the slug
var _trail: Array = []            ## recent slug positions, mm, for the drag line

# ---- bot ----
var _bt := 0.0
var _b_wait := 0.0
var _b_err := 0.0
var _b_err_left := 0.0
var _b_seq := 0


# ---------------------------------------------------------------------------- setup

func card_word_for_start() -> String:
	return "DODGE!"


func build_game() -> void:
	_build_tract()
	s_slug = tract_mm
	fly_y = lane_at(s_slug)
	fly_v = 0.0
	intro_left = intro_time
	_update_progress()


## The level IS the legacy game's wound channel, unrolled. generate_channel() hands back a
## centreline sampled every millimetre of arc and a half-width for each sample; arc length becomes
## X and the centreline's own lateral wander becomes Y.
##
## Two things are normalised, because a seeded channel is laid out to be steered around at walking
## pace and not flown through: the wander is scaled to `lane_span_mm` so it always fits the panel,
## and then scaled again if any stretch climbs steeper than `lane_slope_max`. Both are pure
## functions of the channel, so every machine unrolls the same tract.
func _build_tract() -> void:
	var ch: Dictionary = ForcepsScript.generate_channel(int(ctx.get("seed", 1)), diff)
	var pts: PackedVector2Array = ch.pts
	var widths: PackedFloat32Array = ch.widths
	var n: int = pts.size()
	tract_mm = maxf(20.0, float(ch.length) * 1000.0)
	step_mm = tract_mm / maxf(1.0, float(n - 1))
	var raw := PackedFloat32Array()
	raw.resize(n)
	var mean := 0.0
	for i in n:
		raw[i] = pts[i].y * 1000.0
		mean += raw[i]
	mean /= maxf(1.0, float(n))
	var span := 0.0
	var slope := 0.0
	for i in n:
		raw[i] = raw[i] - mean
		span = maxf(span, absf(raw[i]))
		if i > 0:
			slope = maxf(slope, absf(raw[i] - raw[i - 1]) / maxf(0.001, step_mm))
	var k: float = minf(lane_span_mm / maxf(0.01, span), lane_slope_max / maxf(0.001, slope))
	lane_pts.resize(n)
	half_pts.resize(n)
	for i in n:
		lane_pts[i] = raw[i] * k
		half_pts[i] = maxf(slug_half_mm + 0.5, widths[i] * 1000.0)


# ---------------------------------------------------------------------------- the tract maths

func lane_at(s: float) -> float:
	var n: int = lane_pts.size()
	if n < 2:
		return 0.0
	var f: float = clampf(s / step_mm, 0.0, float(n - 1))
	var i: int = mini(int(f), n - 2)
	return lerpf(lane_pts[i], lane_pts[i + 1], f - float(i))


func half_at(s: float) -> float:
	var n: int = half_pts.size()
	if n < 2:
		return 10.0
	var f: float = clampf(s / step_mm, 0.0, float(n - 1))
	var i: int = mini(int(f), n - 2)
	return lerpf(half_pts[i], half_pts[i + 1], f - float(i))


## The heartbeat, 0 between beats and 1 at the top of one. A narrow squeeze, not a sine wave.
func beat_pulse() -> float:
	return pow(sin(PI * fposmod(beat_phase, 1.0)), 6.0)


## The wall the slug actually has to stay inside: the tract's half-width, less the slug's own, less
## whatever the heartbeat is taking off it right now.
func clear_at(s: float) -> float:
	return maxf(0.4, half_at(s) - slug_half_mm - pinch_mm * beat_pulse())


## How far down the tract the panel is lit. Your own 30 mm, doubled by a teammate's flashlight on
## the wound (Minigame.helper_light(), the same lights the legacy game reads).
func see_ahead() -> float:
	return see_mm * (1.0 + clampf(_help, 0.0, 1.0))


## The arc position the panel is centred on. It follows the slug until the way out would be pushed
## off the left of the panel, and then it stops: for the last stretch the tract holds still and the
## slug crosses the panel towards a mouth you can see, which is the whole point of the last stretch.
func view_s() -> float:
	return maxf(s_slug, mouth_x - slug_x)


## Screen X, in diagram mm, of a point at arc position `s`. Ahead, towards the mouth, is to the
## right; behind, back towards the bullet bed, is to the left.
func sx(s: float) -> float:
	return slug_x + (view_s() - s)


func in_intro() -> bool:
	return intro_left > 0.0


func flying() -> bool:
	return intro_left <= 0.0 and out_left <= 0.0 and play_state != Play.DONE


# ---------------------------------------------------------------------------- playing

func keys() -> Array:
	if play_state == Play.DONE:
		return []
	return [["LMB / Space", "lift"], ["Hold RMB", "brake"]]


func hint() -> String:
	var base := super.hint()
	if base != "":
		return base
	if play_state == Play.DONE:
		return "Out, and into the dish."
	if in_intro():
		return "The forceps have it. Bring it out."
	if grace > 0.0:
		return "Torn. Re-centred, but you lost ground."
	if _help > 0.05:
		return "Someone is lighting the wound: you can see further."
	return "Tap to lift. It is dark: you only see what is lit."


func play(_p: Vector2, buttons: int, edges: int, _delta: float) -> void:
	if not flying():
		return
	braking = (buttons & BUTTON_SECONDARY) != 0
	if (edges & (BUTTON_PRIMARY | BUTTON_ACTION)) != 0:
		fly_v = -flap_mm
		_flap_kick = 1.0
		audio(flap_cue, flap_volume, 0.12)


func advance(delta: float) -> void:
	beat_phase += heart_hz * delta
	grace = maxf(0.0, grace - delta)
	if intro_left > 0.0:
		intro_left = maxf(0.0, intro_left - delta)
		fly_y = lane_at(s_slug)
		return
	if out_left > 0.0:
		out_left = maxf(0.0, out_left - delta)
		if out_left <= 0.0:
			_land()
		return
	fly_v = minf(fly_v + gravity_mm * delta, max_fall_mm)
	fly_y += fly_v * delta
	s_slug -= scroll_mm * (brake_frac if braking else 1.0) * delta
	_update_progress()
	if s_slug <= 0.0:
		s_slug = 0.0
		_out_the_mouth()
		return
	if grace <= 0.0:
		var off := fly_y - lane_at(s_slug)
		var room := clear_at(s_slug)
		if absf(off) > room:
			_tear(signf(off))


## One wall contact. The tract tears, the slug is dragged back down it, and where it happened is
## written down for WHACK! to put a bleeder on.
func _tear(side: float) -> void:
	var pos: float = clampf(s_slug / maxf(1.0, tract_mm), 0.0, 1.0)
	tears.append(snappedf(pos, 0.001))
	tear_side.append(side)
	tear_flash = 0.5
	grace = grace_time
	shake(0.85)
	audio(tear_cue, -6.0, 0.15)
	audio(blood_cue, -7.0, 0.15)
	cost(tear_botch, "Forced the bullet into the wall")
	s_slug = minf(tract_mm, s_slug + knock_mm)
	fly_y = lane_at(s_slug)
	fly_v = 0.0
	_trail.clear()
	_update_progress()


func _out_the_mouth() -> void:
	out_left = exit_time
	fly_v = -flap_mm * 0.6
	audio(dish_cue, -5.0, 0.05)


func _land() -> void:
	var b = body()
	if b != null and b.has_method("set_bleeding"):
		b.set_bleeding(String(ctx.get("step", {}).get("site", "gunshot")), 0.3)
	quality = extract_quality()
	arcade_finish({"bullet_removed": true, "tears": tears.duplicate()})


## What the step was worth: clean out of the tract is 1.0, and every tear takes a chunk.
func extract_quality() -> float:
	return snappedf(clampf(1.0 - 0.15 * float(tears.size()), 0.05, 1.0), 0.01)


func _update_progress() -> void:
	progress = clampf(1.0 - s_slug / maxf(1.0, tract_mm), 0.0, 1.0)


func animate(delta: float) -> void:
	tear_flash = maxf(0.0, tear_flash - delta * 2.0)
	_flap_kick = maxf(0.0, _flap_kick - delta * 4.0)
	var h: Dictionary = helper_light()
	_help = move_toward(_help, float(h.amount), delta * (3.0 if float(h.amount) > _help else 1.5))
	if out_left <= 0.0 and play_state != Play.DONE:
		_trail.push_front(Vector2(sx(s_slug), fly_y))
		while _trail.size() > 9:
			_trail.pop_back()


## A stir kicks the slug off its line, but the tract is forgiving about it for a moment: the jerk
## came from the patient, not from you.
func on_jolt(_offset: Vector2, strength: float, _duration: float) -> void:
	var dir: float = 1.0 if fposmod(float(tears.size()) * 0.6180339887498949 + beat_phase, 1.0) < 0.5 else -1.0
	fly_v += dir * jolt_kick_mm * clampf(0.5 + strength * 0.5, 0.0, 1.0)
	grace = maxf(grace, jolt_grace)
	shake(clampf(0.4 + strength * 0.5, 0.0, 1.0))


# ---------------------------------------------------------------------------- the body

func react() -> void:
	var b = body()
	if b == null:
		_seen_tears = tears.size()
		return
	if tears.size() > _seen_tears:
		_seen_tears = tears.size()
		if b.has_method("stir"):
			b.stir(0.7)
	if b.has_method("set_bleeding"):
		var site := String(ctx.get("step", {}).get("site", "gunshot"))
		var amount: float = clampf(0.14 + 0.1 * float(tears.size()) + tear_flash * 0.5, 0.0, 1.0)
		b.set_bleeding(site, amount if play_state != Play.DONE else 0.3)


# ---------------------------------------------------------------------------- the panel

func paint_game(c: CanvasItem) -> void:
	if panel == null:
		return
	var st := style()
	_paint_tract(c, st)
	_paint_mouth(c, st)
	_paint_tear_marks(c, st)
	_paint_forceps(c, st)
	_paint_slug(c, st)
	_paint_beat(c, st)
	_paint_strip(c, st)
	if tear_flash > 0.0:
		c.draw_rect(Rect2(Vector2.ZERO, panel.tex_size()), Color(st.danger, tear_flash * 0.22))


## How lit a point `ahead` mm down the tract is. Behind the slug the panel keeps a dim memory of
## where you have been; ahead it goes black at the edge of the light and there is nothing to read.
func _lit(ahead: float) -> float:
	if ahead < 0.0:
		return lerpf(1.0, 0.22, clampf(-ahead / maxf(1.0, behind_mm), 0.0, 1.0))
	var see := see_ahead()
	return 1.0 - smoothstep(see * 0.55, see, ahead)


## The tract, one short quad at a time so each can fade out into the dark on its own.
func _paint_tract(c: CanvasItem, st: StyleScript) -> void:
	var seg := 2.0
	var from: float = maxf(0.0, s_slug - see_ahead())
	var to: float = minf(tract_mm, s_slug + behind_mm)
	var s := from
	while s < to:
		var s2: float = minf(s + seg, to)
		var a: float = _lit(s_slug - (s + s2) * 0.5)
		if a > 0.01:
			var hw1: float = half_at(s)
			var hw2: float = half_at(s2)
			var pinch: float = pinch_mm * beat_pulse()
			var y1: float = lane_at(s)
			var y2: float = lane_at(s2)
			var x1: float = sx(s)
			var x2: float = sx(s2)
			var up1 := Vector2(x1, y1 - hw1 + pinch)
			var up2 := Vector2(x2, y2 - hw2 + pinch)
			var dn1 := Vector2(x1, y1 + hw1 - pinch)
			var dn2 := Vector2(x2, y2 + hw2 - pinch)
			c.draw_colored_polygon(PackedVector2Array([px(up1), px(up2), px(dn2), px(dn1)]),
				Color(st.blood_dark, a))
			c.draw_line(px(up1), px(up2), Color(st.line, a), st.thin)
			c.draw_line(px(dn1), px(dn2), Color(st.line, a), st.thin)
		s = s2
	# The centreline, dashed, so the line you are meant to be flying is readable in the gloom.
	var d := from
	while d < to - 3.0:
		var a2: float = _lit(s_slug - d) * 0.85
		if a2 > 0.01:
			c.draw_line(px(Vector2(sx(d), lane_at(d))), px(Vector2(sx(d + 2.2), lane_at(d + 2.2))),
				Color(st.line_dim, a2), st.thin)
		d += 4.0
	# The edge of the light: a bar you can see coming, not just an absence.
	var lx: float = sx(maxf(0.0, s_slug - see_ahead()))
	if lx < 58.0 and from > 0.5:
		st.dashed(c, px(Vector2(lx, -38.0)), px(Vector2(lx, 38.0)), Color(st.line_dim, 0.22), st.hair, 5.0, 9.0)


## The way out, and the dish it goes in. Both only once they are inside the light.
func _paint_mouth(c: CanvasItem, st: StyleScript) -> void:
	if s_slug > see_ahead() and out_left <= 0.0:
		return
	var x := sx(0.0)
	var y := lane_at(0.0)
	var hw := half_at(0.0)
	var col: Color = st.good
	for sy: float in [-1.0, 1.0]:
		var a := px(Vector2(x, y + sy * hw))
		var b := px(Vector2(x + 5.0, y + sy * (hw + 6.0)))
		st.glow_line(c, a, b, col, st.thin)
		c.draw_line(a, b, col, st.outline)
	st.dashed(c, px(Vector2(x, y - hw)), px(Vector2(x, y + hw)), Color(col, 0.7), st.thin, 4.0, 4.0)
	# The kidney dish, waiting at the edge of the panel.
	var dish := _dish()
	var pts := PackedVector2Array()
	for i in 22:
		var a2: float = PI * float(i) / 21.0
		pts.append(px(dish + Vector2(cos(a2) * 13.0, sin(a2) * 7.0)))
	c.draw_polyline(pts, Color(st.steel, 0.85), st.thin)
	c.draw_line(px(dish + Vector2(-13.0, 0.0)), px(dish + Vector2(13.0, 0.0)), Color(st.steel, 0.55), st.hair)


func _dish() -> Vector2:
	return Vector2(46.0, 22.0)


## The forceps: in on their own during the intro, then trailing off towards the mouth, because that
## is the hand that is pulling. The shafts fade out where the light does, like everything else --
## a pair of hard lines running off into the black would read as tract that is not there.
func _paint_forceps(c: CanvasItem, st: StyleScript) -> void:
	if play_state == Play.DONE or out_left > 0.0:
		return
	var grip := Vector2(sx(s_slug), fly_y)
	var k: float = 1.0 - clampf(intro_left / maxf(0.05, intro_time), 0.0, 1.0)
	var spread: float = lerpf(9.0, slug_half_mm * 0.9, k)
	var reach: float = minf(see_ahead() * 0.8, 58.0 - grip.x)
	for sy: float in [-1.0, 1.0]:
		var tip := grip + Vector2(slug_half_mm * 0.6, sy * spread)
		for i in 5:
			var u0: float = float(i) / 5.0
			var u1: float = float(i + 1) / 5.0
			var a: float = (1.0 - u0) * 0.75
			c.draw_line(px(tip + Vector2(reach * u0, sy * 3.5 * u0)),
				px(tip + Vector2(reach * u1, sy * 3.5 * u1)), Color(st.steel, a), st.thin)


## The slug in the jaws. It blinks through the grace after a tear, so "you cannot be hurt right
## now" is a shape thing and not only a colour thing.
func _paint_slug(c: CanvasItem, st: StyleScript) -> void:
	var at := Vector2(sx(s_slug), fly_y)
	if out_left > 0.0:
		at = _flight_pos()
	elif play_state == Play.DONE:
		at = _dish() + Vector2(0.0, -3.0)
	if grace > 0.0 and out_left <= 0.0 and fposmod(grace, 0.18) < 0.09:
		return
	for i in _trail.size():
		if out_left > 0.0:
			break
		var t: float = 1.0 - float(i) / float(maxi(1, _trail.size()))
		c.draw_circle(px(_trail[i]), px_len(slug_half_mm * 0.45 * t), Color(st.steel, 0.10 * t))
	# A blunt slug: a nose, a body, and a crimped base. Not a dot.
	var r := slug_half_mm
	var body_pts := PackedVector2Array([
		px(at + Vector2(r * 1.35, 0.0)),
		px(at + Vector2(r * 0.45, -r * 0.85)),
		px(at + Vector2(-r * 1.25, -r * 0.85)),
		px(at + Vector2(-r * 1.25, r * 0.85)),
		px(at + Vector2(r * 0.45, r * 0.85)),
	])
	st.glow_poly(c, body_pts, st.steel, st.thin)
	c.draw_colored_polygon(body_pts, Color(st.steel, 0.9))
	c.draw_polyline(body_pts, st.line, st.thin)
	c.draw_line(px(at + Vector2(-r * 0.7, -r * 0.85)), px(at + Vector2(-r * 0.7, r * 0.85)), st.bg, st.hair)
	if _flap_kick > 0.0:
		var puff := at + Vector2(-r * 1.8, r * 0.4)
		c.draw_arc(px(puff), px_len(2.0 + 3.0 * _flap_kick), 0.0, TAU, 12,
			Color(st.line_dim, 0.4 * _flap_kick), st.hair)


## Where the slug is on its way to the dish: up out of the mouth and down into the tray.
func _flight_pos() -> Vector2:
	var k: float = 1.0 - clampf(out_left / maxf(0.05, exit_time), 0.0, 1.0)
	var a := Vector2(sx(0.0), lane_at(0.0))
	var b := _dish() + Vector2(0.0, -4.0)
	return a.lerp(b, k) + Vector2(0.0, -20.0 * sin(PI * k))


## Every tear so far, marked on the wall it happened on -- a cross, plus a torn zigzag, so it reads
## without the colour. This is exactly the list WHACK! is going to read.
func _paint_tear_marks(c: CanvasItem, st: StyleScript) -> void:
	for i in tears.size():
		var s: float = float(tears[i]) * tract_mm
		var ahead := s_slug - s
		var a := _lit(ahead)
		if a <= 0.02:
			continue
		var side: float = float(tear_side[i]) if i < tear_side.size() else 1.0
		var at := Vector2(sx(s), lane_at(s) + side * (half_at(s) - 0.5))
		var p := px(at)
		var r := px_len(2.6)
		c.draw_line(p + Vector2(-r, -r), p + Vector2(r, r), Color(st.danger, a), st.thin)
		c.draw_line(p + Vector2(-r, r), p + Vector2(r, -r), Color(st.danger, a), st.thin)
		c.draw_circle(p, px_len(1.4), Color(st.blood, a * 0.9))


## The heartbeat: a pip that runs, and arrows on the walls at the top of a beat so the squeeze is a
## shape and not a two-pixel colour change.
func _paint_beat(c: CanvasItem, st: StyleScript) -> void:
	var pulse := beat_pulse()
	var origin := Vector2(-22.0, -33.0)
	var trace := PackedVector2Array()
	for i in 26:
		var u := float(i) / 25.0
		var lag: float = fposmod(beat_phase - u * 0.5, 1.0)
		trace.append(px(origin + Vector2(u * 22.0, -5.5 * pow(sin(PI * lag), 8.0))))
	c.draw_polyline(trace, Color(st.good, 0.55), st.hair)
	if pulse < 0.35:
		return
	var a: float = (pulse - 0.35) / 0.65
	var s := maxf(0.0, s_slug - see_ahead() * 0.6)
	while s < minf(tract_mm, s_slug + 8.0):
		var x := sx(s)
		if x > -58.0 and x < 58.0:
			var hw: float = half_at(s) - pinch_mm * pulse
			var y: float = lane_at(s)
			for sy: float in [-1.0, 1.0]:
				var tip := Vector2(x, y + sy * hw)
				c.draw_line(px(tip + Vector2(-1.6, -sy * 2.2)), px(tip), Color(st.danger, a * 0.8), st.hair)
				c.draw_line(px(tip + Vector2(1.6, -sy * 2.2)), px(tip), Color(st.danger, a * 0.8), st.hair)
		s += 11.0


## The whole tract, end to end, on one rule across the bottom: the bed you started at, the mouth you
## are heading for, where the slug has got to and a tick for every tear. Most of the panel is
## unlit -- the machine only draws what the light reaches -- so what is down here is the only view
## of the tract as a whole anyone gets, operator or onlooker.
func _paint_strip(c: CanvasItem, st: StyleScript) -> void:
	var font := ThemeDB.fallback_font
	var y := 33.0
	var a := Vector2(-48.0, y)
	var b := Vector2(48.0, y)
	c.draw_line(px(a), px(b), Color(st.line_dim, 0.7), st.thin)
	# The bullet bed at one end, the way out at the other.
	c.draw_circle(px(a), px_len(1.8), Color(st.line_dim, 0.7))
	for sy: float in [-1.0, 1.0]:
		c.draw_line(px(b), px(b + Vector2(-3.0, sy * 3.0)), Color(st.good, 0.8), st.thin)
	var u: float = clampf(1.0 - s_slug / maxf(1.0, tract_mm), 0.0, 1.0)
	var at := Vector2(lerpf(a.x, b.x, u), y)
	# A caret pointing the way out, so which end is which reads without the colour.
	c.draw_colored_polygon(PackedVector2Array([px(at + Vector2(2.6, 0.0)), px(at + Vector2(-1.6, -2.6)),
		px(at + Vector2(-1.6, 2.6))]), st.steel)
	for t in tears:
		var tx: float = lerpf(a.x, b.x, clampf(1.0 - float(t), 0.0, 1.0))
		c.draw_line(px(Vector2(tx - 1.4, y + 1.4)), px(Vector2(tx + 1.4, y + 4.2)), st.danger, st.thin)
		c.draw_line(px(Vector2(tx - 1.4, y + 4.2)), px(Vector2(tx + 1.4, y + 1.4)), st.danger, st.thin)
	var txt := "%3d MM OUT" % int(round(s_slug))
	if tears.size() > 0:
		txt += "    TORN %d" % tears.size()
	if _help > 0.05:
		txt += "    LIT"
	if braking:
		txt += "    BRAKING"
	var w: float = font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x
	var col: Color = st.danger if tears.size() > 0 else Color(st.line_dim, 0.95)
	c.draw_string(font, px(Vector2(0.0, 28.0)) + Vector2(-w * 0.5, 0), txt,
		HORIZONTAL_ALIGNMENT_LEFT, -1.0, 22, col)


# ---------------------------------------------------------------------------- net

## Everything a spectator needs to watch someone fly this. NOTHING THAT CREEPS IS SNAPPED: the slug
## moves 0.2 mm of tract a frame and the countdowns tick by a sixtieth, so snapping any of them to
## a readable quantum would stop them dead the moment the lab round-trips this dictionary.
func net_pack() -> Dictionary:
	return {
		"s": s_slug, "y": fly_y, "v": fly_v, "bp": beat_phase,
		"il": intro_left, "ol": out_left, "gr": grace, "bk": braking,
		"tr": PackedFloat32Array(tears), "td": PackedFloat32Array(tear_side),
		"tf": snappedf(tear_flash, 0.05),
	}


func net_apply(s: Dictionary) -> void:
	s_slug = float(s.get("s", s_slug))
	fly_y = float(s.get("y", fly_y))
	fly_v = float(s.get("v", fly_v))
	beat_phase = float(s.get("bp", beat_phase))
	intro_left = float(s.get("il", intro_left))
	out_left = float(s.get("ol", out_left))
	grace = float(s.get("gr", grace))
	braking = bool(s.get("bk", braking))
	var was := tears.size()
	tears = Array(s.get("tr", PackedFloat32Array(tears)))
	tear_side = Array(s.get("td", PackedFloat32Array(tear_side)))
	tear_flash = maxf(tear_flash, float(s.get("tf", tear_flash)))
	if tears.size() > was:
		audio(tear_cue, -6.0, 0.15)
	_update_progress()


# ---------------------------------------------------------------------------- bot

## The bot flies by aiming at the centreline a little way ahead -- no further ahead than it can
## actually see, so a dark tract really is harder for it too -- and tapping whenever it works out
## that it is about to be below that line. A good hand looks well ahead, re-decides constantly and
## is almost on the line. A bad one decides three times a second, reads barely past its own nose,
## and holds a drifting offset it never notices.
func bot_input(t: float, skill: float) -> Dictionary:
	var dt: float = clampf(t - _bt, 0.0, 0.1)
	_bt = t
	skill = clampf(skill, 0.0, 1.0)
	if not armed() or not flying():
		return {"cursor": Vector2.ZERO, "buttons": 0}
	# The hand's drift, from a golden-ratio sequence: the same hand on every machine, every run.
	_b_err_left -= dt
	if _b_err_left <= 0.0:
		_b_err_left = 1.0
		_b_seq += 1
		var u: float = fposmod(float(_b_seq) * 0.6180339887498949, 1.0)
		_b_err = (u - 0.5) * 2.0 * lerpf(2.8, 0.25, skill)
	var press := false
	_b_wait -= dt
	if _b_wait <= 0.0:
		_b_wait = lerpf(0.13, 0.03, skill)
		# It judges where the slug will be in BOT_TAU against where the TRACT will be then, which is
		# a couple of millimetres of lookahead -- and never more than the light gives it.
		var lead: float = minf(scroll_mm * BOT_TAU, see_ahead() * 0.7)
		# It aims at a line BELOW the centreline, never at the centreline itself. Tapping keeps the
		# slug in a sawtooth that always sits above wherever it aims -- a tap's worth of lift, plus
		# whatever the velocity term is worth at the moment it fires -- so a hand that aimed at the
		# middle would ride the ceiling and lose every tract that dives away from it. Aiming low by
		# exactly that much puts the sawtooth on the centreline instead.
		var lift: float = flap_mm * flap_mm / (2.0 * maxf(1.0, gravity_mm))
		var target: float = lane_at(maxf(0.0, s_slug - lead)) + flap_mm * BOT_TAU + lift * 0.5 + _b_err
		press = fly_y + fly_v * BOT_TAU > target
	return {"cursor": Vector2.ZERO, "buttons": BUTTON_PRIMARY if press else 0}


# ---------------------------------------------------------------------------- self-test

## Headless check: `tools/minigame_lab.tscn -- --selftest=forceps:arcade`.
## Targets: skill 1.0 finishes in 8-20 s losing 0-2 vitals; skill 0.0 under 40 s losing 15-25.
static func self_test() -> Array:
	var script: GDScript = load("res://scripts/surgery/arcade/dodge_arcade.gd")
	var out := []
	var ok := true
	var sloppy: Array = []
	for sed: float in [1.0, 0.4]:
		for pid: String in ["bob", "seal"]:
			for skill: float in [1.0, 0.5, 0.0]:
				var g = script.new()
				var tally := {"n": 0, "v": 0.0, "done": false, "tears": [], "reasons": {}}
				g.botched.connect(func(a, r): tally.n += 1; tally.v += a; tally.reasons[r] = int(tally.reasons.get(r, 0)) + 1)
				g.finished.connect(func(r): tally.done = true; tally.tears = r.get("tears", []))
				g.setup(_case(pid, sed))
				var t: float = run_bot(g, skill, sed, hash(pid) + int(skill * 100))
				print("[dodge-arcade self-test] %-4s skill=%.1f sed=%.1f  %s  tract=%3dmm  tears=%2d  time=%5.1fs  botches=%2d vitals=%5.1f  %s" % [
					pid, skill, sed, "DONE" if tally.done else "UNFINISHED",
					int(g.tract_mm), g.tears.size(), t, tally.n, tally.v, str(tally.reasons)])
				out.append({"patient": pid, "skill": skill, "sed": sed, "done": tally.done,
					"time": t, "vitals": tally.v, "tears": tally.tears.size()})
				# The carry-forward, checked on every finished run: arc positions, 0..1, one per tear.
				if tally.done:
					if tally.tears.size() != g.tears.size():
						print("[dodge-arcade self-test] MISS: the result's tears do not match the game's")
						ok = false
					for v in tally.tears:
						if not (v is float) or v < 0.0 or v > 1.0:
							print("[dodge-arcade self-test] MISS: a tear is not a 0..1 float (%s)" % str(v))
							ok = false
							break
				if sed > 0.9:
					if skill == 1.0:
						if not tally.done or t < 8.0 or t > 20.0 or tally.v > 2.0:
							print("[dodge-arcade self-test] MISS: skill 1.0 wants 8-20 s and 0-2 vitals")
							ok = false
						if not tally.tears.is_empty():
							print("[dodge-arcade self-test] MISS: a clean run should tear nothing")
							ok = false
					if skill == 0.0:
						sloppy.append(tally.v)
						if not tally.done or t > 40.0:
							print("[dodge-arcade self-test] MISS: skill 0.0 wants to finish under 40 s")
							ok = false
						if tally.tears.is_empty():
							print("[dodge-arcade self-test] MISS: a sloppy run should tear the tract")
							ok = false
				g.free()
	# The sloppy band, on the MEAN: a seeded tract's bends and its length swing one patient a few
	# vitals either side of the other on its own, exactly as SAW!'s court does.
	var mean := 0.0
	for v: float in sloppy:
		mean += v
	mean /= maxf(1.0, float(sloppy.size()))
	print("[dodge-arcade self-test] skill 0.0 mean vitals %.1f across %d patients (want 15-25)" % [mean, sloppy.size()])
	if mean < 15.0 or mean > 25.0:
		print("[dodge-arcade self-test] MISS: skill 0.0 wants 15-25 vitals on average")
		ok = false
	# The dark, and the teammate who fixes it.
	var lg = script.new()
	lg.setup(_case("bob", 1.0))
	var alone: float = lg.see_ahead()
	lg._help = 1.0
	var lit: float = lg.see_ahead()
	print("[dodge-arcade self-test] sight alone %.0f mm, with a teammate's light %.0f mm" % [alone, lit])
	if absf(alone - 30.0) > 0.01 or absf(lit - alone * 2.0) > 0.01:
		print("[dodge-arcade self-test] MISS: a flashlight on the wound should double 30 mm to 60")
		ok = false
	lg.free()
	# The brake: half speed, so it buys reading time and spends the clock.
	var free_t := _timed(script, false)
	var braked_t := _timed(script, true)
	print("[dodge-arcade self-test] a clean run takes %.1f s, the same run braking all the way %.1f s" % [free_t, braked_t])
	if braked_t < free_t * 1.5:
		print("[dodge-arcade self-test] MISS: braking should cost real time")
		ok = false
	# Walking away and coming back. A real-time game that kept flying while nobody was at the table
	# would be a free failure, and one that started again the instant somebody leaned in would be
	# another; the shared frame handles both, and this is the check that it still does here.
	var hand := _handover(script)
	print("[dodge-arcade self-test] left alone the slug moved %.3f mm, the READY countdown held it %.2f s, then it flew again" % [hand[0], hand[1]])
	# One frame of scroll is allowed: the tick that retires the countdown is also the tick that flies.
	if hand[0] > 0.25 or absf(float(hand[1]) - 1.0) > 0.1 or not bool(hand[2]):
		print("[dodge-arcade self-test] MISS: the game must stop dead when the table empties and count down before it resumes")
		ok = false
	print("[dodge-arcade self-test] %s" % ("PASS" if ok else "FAIL"))
	return out


static func _case(pid: String, sed: float) -> Dictionary:
	return {"patient_id": pid, "patient": Procedures.patient(pid), "ailment_id": "gunshot",
		"step": Procedures.step("gunshot", 1), "variant": "", "shift": 1,
		"difficulty": Procedures.difficulty(1), "flags": {"sedation": sed},
		"seed": hash("dodge" + pid), "body": null, "operator": true, "operating": true}


## One skill-1.0 run, optionally with the brake pinned down the whole way.
static func _timed(script: GDScript, brake: bool) -> float:
	var g = script.new()
	g.setup(_case("bob", 1.0))
	var t := 0.0
	var dt := 1.0 / 60.0
	while t < 90.0 and not g.done:
		t += dt
		var inp: Dictionary = g.bot_input(t, 1.0)
		var b: int = int(inp.get("buttons", 0))
		if brake:
			b |= BUTTON_SECONDARY
		g.handle_cursor(Vector2.ZERO, b, dt)
		g.tick(dt)
		g.apply_net_state(g.net_state())
	g.free()
	return t


## Player A flies for four seconds, walks off for two, and player B picks it up. Returns
## [mm the slug drifted while nobody had it, seconds of READY countdown, whether it flew again].
static func _handover(script: GDScript) -> Array:
	var g = script.new()
	g.setup(_case("bob", 1.0))
	var dt := 1.0 / 60.0
	var t := 0.0
	while t < 4.0:
		t += dt
		var inp: Dictionary = g.bot_input(t, 1.0)
		g.handle_cursor(Vector2.ZERO, int(inp.get("buttons", 0)), dt)
		g.tick(dt)
		g.apply_net_state(g.net_state())
	var left_at: float = g.s_slug
	g.ctx["operating"] = false
	for i in 120:
		g.tick(dt)
		g.apply_net_state(g.net_state())
	var drift: float = absf(g.s_slug - left_at)
	# Somebody leans in. Mashing through the countdown must not fly it early.
	g.ctx["operating"] = true
	var held: float = g.s_slug
	# One frame for the frame to notice somebody is there and put the countdown up.
	g.handle_cursor(Vector2.ZERO, 0, dt)
	g.tick(dt)
	g.apply_net_state(g.net_state())
	var counted := dt
	while g.play_state == Play.READY and counted < 3.0:
		counted += dt
		t += dt
		g.handle_cursor(Vector2.ZERO, BUTTON_PRIMARY if int(counted * 60.0) % 4 < 2 else 0, dt)
		g.tick(dt)
		g.apply_net_state(g.net_state())
	drift = maxf(drift, absf(g.s_slug - held))
	for i in 30:
		t += dt
		var inp3: Dictionary = g.bot_input(t, 1.0)
		g.handle_cursor(Vector2.ZERO, int(inp3.get("buttons", 0)), dt)
		g.tick(dt)
		g.apply_net_state(g.net_state())
	var moving: bool = g.s_slug < held - 1.0
	g.free()
	return [drift, counted, moving]
