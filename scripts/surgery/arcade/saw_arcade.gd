extends "res://scripts/surgery/arcade/arcade_game.gd"
## ARCADE SURGERY (docs/ARCADE_SURGERY.md) 5.5 -- SAW! Step "cut" of an amputation: saw through the
## limb. The arcade rebuild of scripts/surgery/games/saw.gd, played on the raised panel.
##
## Rhyme: Pong. A saw goes back and forth; so does the ball.
##
## What you do
##   The limb's CROSS-SECTION sits in the middle of the court, built from the body's own section:
##   skin ring, muscle, and bones as circles (Bob has two, the seal's flipper four or five). The
##   blade is the ball. It goes THROUGH the limb, it does not bounce off it, and every crossing is
##   one stroke: the cut line sinks, chips fly, and the saw rasps or grinds.
##   Both paddles are yours and they are MIRRORED -- the mouse, or W / S, moves them together -- so
##   you are covering the left and the right at once. Top and bottom bounce. Where the ball meets
##   the paddle sets the return angle.
##   WHAT IT IS CUTTING CHANGES THE BALL. Soft tissue is quick and clean. Bone is heavy, and it
##   CHATTERS: the ball wobbles off its line and has to be read. The feel flips the moment the cut
##   meets or leaves a bone.
##   Hold the mouse at contact for a HARD return: faster ball, faster sawing, less time to read it.
##   Miss, and the saw jumps out of the cut and tears.
##   A seeded artery sits in the muscle, and what it does when the cut reaches it is entirely down
##   to the tourniquet you put on: a good one drips, a bad one throws blood across the court and
##   the ball is invisible while it is under the patch.
##   For the last three crossings the card says EASY... and the ball speeds up. Take the last one
##   off a hard return and you saw into the table.
##
## Result {"amputated": true, "cut_quality": q}.

enum Layer { SKIN, MUSCLE, BONE, FAR }

## name, resistance (the bite divides by it), ball speed in mm/s, tear factor
const LAYERS := {
	Layer.SKIN: {"name": "skin", "res": 0.45, "speed": 170.0, "tear": 0.5},
	Layer.MUSCLE: {"name": "muscle", "res": 1.0, "speed": 170.0, "tear": 0.8},
	Layer.BONE: {"name": "bone", "res": 2.2, "speed": 120.0, "tear": 1.2},
	Layer.FAR: {"name": "far side", "res": 0.9, "speed": 170.0, "tear": 0.8},
}
const SAMPLES := 72

# -- the court --------------------------------------------------------------------------------
@export_range(20.0, 60.0, 1.0) var court_half_y := 30.0     ## mm to the top and bottom walls
@export_range(20.0, 60.0, 1.0) var paddle_x := 52.0         ## mm out to each paddle
@export_range(6.0, 50.0, 0.5) var paddle_mm := 22.0         ## paddle height before difficulty
@export_range(0.5, 8.0, 0.1) var ball_mm := 2.6             ## the blade's radius on the court
@export_range(10.0, 90.0, 1.0) var max_bounce_deg := 55.0   ## steepest return off a paddle's edge
@export_range(50.0, 400.0, 5.0) var paddle_key_speed := 150.0   ## mm/s on W / S

# -- the cut ----------------------------------------------------------------------------------
## Depth per crossing at resistance 1. Tuned for about 16 crossings end to end.
@export_range(0.01, 0.4, 0.002) var bite_per_crossing := 0.068
## More than this much of the cut line's chord inside bone and it is cutting bone.
@export_range(0.05, 0.9, 0.01) var bone_chord_frac := 0.30
@export_range(0.5, 10.0, 0.1) var skin_mm := 2.6
## A hard return (the mouse held at contact) buys this much ball speed.
@export_range(0.0, 1.0, 0.01) var hard_bonus := 0.25
## How far the ball wobbles off its line while the cut is in bone, before difficulty.
@export_range(0.0, 20.0, 0.5) var chatter_mm := 6.0
@export_range(0.2, 6.0, 0.05) var chatter_hz := 1.9

# -- missing ----------------------------------------------------------------------------------
@export_range(0.0, 10.0, 0.5) var miss_botch := 2.5
@export_range(0.05, 3.0, 0.05) var serve_delay := 0.6

# -- the artery -------------------------------------------------------------------------------
@export_range(0.0, 1.0, 0.01) var artery_drip := 0.15       ## spurt at or below this hides nothing
@export_range(0.0, 80.0, 1.0) var splat_base_mm := 10.0
@export_range(0.0, 200.0, 1.0) var splat_per_spurt_mm := 40.0
@export_range(0.0, 1.0, 0.01) var bleed_botch_rate := 0.08  ## botch units per unit spurt per second
@export_range(0.0, 10.0, 0.5) var bleed_botch := 1.0

# -- breaking through -------------------------------------------------------------------------
@export_range(1, 8) var easy_crossings := 3                 ## EASY... for the last this many
@export_range(1.0, 2.5, 0.05) var easy_speed := 1.3
@export_range(0.0, 10.0, 0.5) var table_botch := 3.0

# -- audio ------------------------------------------------------------------------------------
@export var rasp_cue := "surgery_saw_rasp"
@export var grind_cue := "surgery_saw_grind"
@export var squelch_cue := "surgery_saw_squelch"
@export var thunk_cue := "surgery_saw_thunk"
@export var paddle_cue := "surgery_click"
@export var wall_cue := "surgery_forceps_clink"
@export_range(-40.0, 0.0, 1.0) var paddle_volume := -14.0
@export_range(-40.0, 0.0, 1.0) var wall_volume := -22.0

# ---- replicated state ----
var depth := 0.0                  ## 0 at the near skin, 1 through the far side
var crossings := 0
var misses := 0
var ball := Vector2.ZERO          ## mm on the court
var ball_v := Vector2.ZERO        ## mm/s
var paddle_y := 0.0               ## mm; both paddles, mirrored
var serve_left := 0.0             ## seconds until the ball is served again
var hard_now := false             ## the mouse is down: the next return is a hard one
var last_hard := false            ## the return the ball is travelling on was a hard one
var spurt := 0.0
var artery_hit := false
var table_hit := false
var splat := Vector2.ZERO         ## where the blood landed on the court
var chips: Array = []             ## [x_mm, y_mm, r_mm]
var miss_flash := 0.0

# ---- derived from the seed ----
var tourniquet := 0.5
var sec_a := 34.0
var sec_b := 24.0
var sec_c := Vector2.ZERO
var sec_n := 3.0
var bones: Array = []
var artery := Vector2.ZERO
var artery_depth := 0.45

# ---- local ----
var _t := 0.0
var _shown_depth := 0.0
var _bleed_acc := 0.0
var _rng := RandomNumberGenerator.new()
var _seen_crossings := 0
var _seen_misses := 0
var _seen_artery := false
var _easy_shown := false
var _prev_x := 0.0
var _chatter_phase := 0.0
var _trail: Array = []            ## recent ball positions, for the blade's streak

# ---- bot ----
var _bt := 0.0
var _b_aim := 0.0
var _b_seq := 0
var _b_err := 0.0
var _b_err_for := -1


# ---------------------------------------------------------------------------- setup

func card_word_for_start() -> String:
	return "SAW!"


func build_game() -> void:
	var flags: Dictionary = ctx.get("flags", {})
	var tq = flags.get("tourniquet", 0.5)
	tourniquet = (1.0 if tq else 0.0) if tq is bool else clampf(float(tq), 0.0, 1.0)
	_rng.seed = int(ctx.get("seed", 1)) ^ 0x5a3
	_build_section()
	_serve(1 if _rng.randf() < 0.5 else -1)
	_update_progress()


func layer_table() -> Dictionary:
	return LAYERS


func paddle_half() -> float:
	return paddle_mm * 0.5 / sqrt(diff)


## The cross-section comes from the real limb (PatientBody.site_section), so Bob's forearm and the
## seal's flipper are visibly different things to saw through.
func _build_section() -> void:
	var hu := 0.024
	var hs := 0.032
	var shape := 3.0
	var body = ctx.get("body")
	var site := String(ctx.get("step", {}).get("site", "limb_cut"))
	if body != null and is_instance_valid(body) and body.has_method("site_section"):
		var sec: Dictionary = body.site_section(site)
		if not sec.is_empty():
			hs = clampf(float(sec.half_side), 0.008, 0.3)
			hu = clampf(maxf(float(sec.half_up), hs * 0.6), 0.008, 0.3)
			shape = clampf(float(sec.get("shape", 3.0)), 2.0, 6.0)
	else:
		var r := float(ctx.get("patient", {}).get("limb_radius_m", 0.05))
		hs = r
		hu = r * 0.8
	sec_n = shape
	# Big enough that the ball is visibly going through an arm and not past one.
	var k: float = minf(36.0 / (hs * 1000.0), 27.0 / (hu * 1000.0))
	sec_a = hs * 1000.0 * k
	sec_b = hu * 1000.0 * k
	sec_c = Vector2.ZERO
	bones.clear()
	if _bone_count() >= 3:
		var n := _bone_count()
		var r: float = sec_b * 0.16
		for i in n:
			var t: float = (float(i) + 0.5) / float(n)
			var x: float = lerpf(-sec_a * 0.62, sec_a * 0.62, t)
			var y: float = sec_c.y + sec_b * (0.06 + 0.1 * sin(t * PI))
			bones.append([Vector2(x, y), r * _rng.randf_range(0.86, 1.14)])
	else:
		var big: float = sec_b * 0.30 * _rng.randf_range(0.92, 1.08)
		var small: float = sec_b * 0.23 * _rng.randf_range(0.92, 1.08)
		var gap: float = sec_a * _rng.randf_range(0.28, 0.38)
		bones.append([Vector2(-gap, sec_c.y + sec_b * 0.12), big])
		bones.append([Vector2(gap, sec_c.y + sec_b * 0.18), small])
	artery_depth = _rng.randf_range(0.24, 0.42)
	var ay: float = sec_c.y - sec_b + artery_depth * 2.0 * sec_b
	var side: float = 1.0 if _rng.randf() < 0.5 else -1.0
	artery = Vector2(side * sec_a * _rng.randf_range(0.42, 0.72), ay)


func _bone_count() -> int:
	if String(ctx.get("patient_id", "bob")) == "seal":
		return 4 + (1 if _rng.randf() < 0.5 else 0)
	return 2


# ---------------------------------------------------------------------------- the section maths

func half_chord(y: float) -> float:
	var t: float = absf((y - sec_c.y) / maxf(0.01, sec_b))
	if t >= 1.0:
		return 0.0
	return sec_a * pow(maxf(0.0, 1.0 - pow(t, sec_n)), 1.0 / sec_n)


func depth_to_y(d: float) -> float:
	return sec_c.y - sec_b + clampf(d, 0.0, 1.0) * 2.0 * sec_b


## How much of the CUT LINE's chord at this depth is inside bone, 0..1.
func bone_fraction(d: float) -> float:
	var y := depth_to_y(d)
	var hc := half_chord(y)
	if hc <= 0.01:
		return 0.0
	var covered := 0.0
	for b in bones:
		var c: Vector2 = b[0]
		var r: float = b[1]
		var dy: float = absf(y - c.y)
		if dy < r:
			covered += 2.0 * sqrt(r * r - dy * dy)
	return clampf(covered / (2.0 * hc), 0.0, 1.0)


func layer_at(d: float) -> int:
	if bone_fraction(d) > bone_chord_frac:
		return Layer.BONE
	var skin_d: float = clampf(skin_mm / maxf(1.0, 2.0 * sec_b), 0.01, 0.3)
	if d < skin_d:
		return Layer.SKIN
	if d > 1.0 - skin_d:
		return Layer.FAR
	return Layer.MUSCLE


func layer() -> int:
	return layer_at(depth)


func in_bone() -> bool:
	return layer() == Layer.BONE


## How many crossings are left at the current bite. Drives the EASY... card and the scoreboard.
func crossings_left() -> int:
	var d := depth
	var n := 0
	while d < 1.0 and n < 99:
		d += bite_per_crossing / float(layer_table()[layer_at(d)].res)
		n += 1
	return n


## What the ball should be travelling at right now.
func target_speed() -> float:
	var s: float = float(layer_table()[layer()].speed)
	if last_hard:
		s *= 1.0 + hard_bonus
	if crossings_left() <= easy_crossings:
		s *= easy_speed
	return s


# ---------------------------------------------------------------------------- playing

func keys() -> Array:
	if play_state == Play.DONE:
		return []
	return [["Mouse / W S", "both paddles"], ["Hold LMB", "hard return"]]


func hint() -> String:
	var base := super.hint()
	if base != "":
		return base
	if play_state == Play.DONE:
		return "Through."
	if serve_left > 0.0:
		return "The saw jumped out. Re-serving."
	if crossings_left() <= easy_crossings:
		return "Nearly through. Take the last one off a soft return."
	if spurt > artery_drip:
		return "You can't see the ball under the blood."
	if in_bone():
		return "Bone: heavy, and it chatters."
	return "Keep the blade in the cut."


func play(p: Vector2, buttons: int, _edges: int, delta: float) -> void:
	hard_now = (buttons & BUTTON_PRIMARY) != 0
	var limit: float = court_half_y - paddle_half()
	if buttons & BUTTON_UP:
		paddle_y = clampf(paddle_y - paddle_key_speed * delta, -limit, limit)
	elif buttons & BUTTON_DOWN:
		paddle_y = clampf(paddle_y + paddle_key_speed * delta, -limit, limit)
	else:
		paddle_y = clampf(p.y, -limit, limit)


func advance(delta: float) -> void:
	_bleed(delta)
	if serve_left > 0.0:
		serve_left = maxf(0.0, serve_left - delta)
		if serve_left <= 0.0:
			_serve(1 if _rng.randf() < 0.5 else -1)
		return
	# The ball travels at whatever the cut is in, hard returns and the run-out included.
	var speed := target_speed()
	if ball_v.length() > 1.0:
		ball_v = ball_v.normalized() * speed
	_prev_x = ball.x
	ball += ball_v * delta
	# Bone chatters: the blade wanders off its line and has to be read.
	if in_bone():
		_chatter_phase += delta * chatter_hz
		var perp := Vector2(-ball_v.y, ball_v.x).normalized()
		ball += perp * cos(_chatter_phase * TAU) * TAU * chatter_hz * chatter_mm * diff * delta
	# Top and bottom.
	var wall: float = court_half_y - ball_mm
	if ball.y < -wall and ball_v.y < 0.0:
		ball.y = -wall
		ball_v.y = -ball_v.y
		audio(wall_cue, wall_volume, 0.15)
	elif ball.y > wall and ball_v.y > 0.0:
		ball.y = wall
		ball_v.y = -ball_v.y
		audio(wall_cue, wall_volume, 0.15)
	# Through the limb: one crossing is one stroke.
	if signf(_prev_x) != signf(ball.x) and absf(_prev_x) > 0.001:
		_crossing()
		if play_state == Play.DONE:
			return
	# The paddles, both of them, at the same height.
	for side: float in [-1.0, 1.0]:
		if signf(ball_v.x) != side:
			continue
		var face: float = side * paddle_x
		if side > 0.0 and (ball.x + ball_mm) < face:
			continue
		if side < 0.0 and (ball.x - ball_mm) > face:
			continue
		if absf(ball.y - paddle_y) <= paddle_half() + ball_mm:
			_return_ball(side)
		elif absf(ball.x) > paddle_x + 7.0:
			_miss()
		return


func _return_ball(side: float) -> void:
	var off: float = clampf((ball.y - paddle_y) / maxf(1.0, paddle_half()), -1.0, 1.0)
	var ang := deg_to_rad(off * max_bounce_deg)
	ball_v = Vector2(-side * cos(ang), sin(ang)) * target_speed()
	ball.x = side * (paddle_x - ball_mm * 1.3)
	last_hard = hard_now
	audio(paddle_cue, paddle_volume + (4.0 if last_hard else 0.0), 0.08)


func _miss() -> void:
	misses += 1
	miss_flash = 0.45
	var nm := String(layer_table()[layer()].name)
	shake(0.8)
	_chip(5)
	cost(miss_botch, "The saw jumped and tore the %s" % nm)
	serve_left = serve_delay
	ball_v = Vector2.ZERO
	ball = Vector2.ZERO
	last_hard = false


func _serve(dir: int) -> void:
	ball = Vector2.ZERO
	var ang := deg_to_rad(_rng.randf_range(-28.0, 28.0))
	ball_v = Vector2(float(dir) * cos(ang), sin(ang)) * float(layer_table()[layer()].speed)
	_prev_x = 0.0
	last_hard = false
	serve_left = 0.0


## One pass of the blade through the limb.
func _crossing() -> void:
	var lay := layer()
	var info: Dictionary = layer_table()[lay]
	crossings += 1
	_chip(2 if lay != Layer.BONE else 3)
	audio(grind_cue if lay == Layer.BONE else rasp_cue, -8.0, 0.14)
	var before := depth
	depth = clampf(depth + bite_per_crossing / float(info.res), 0.0, 1.0)
	if not artery_hit and before < artery_depth and depth >= artery_depth:
		_cut_artery()
	_update_progress()
	if depth >= 1.0:
		# The last one has to come off a soft return, or the blade is still travelling when it
		# breaks out of the far side and goes into the table.
		if last_hard and not table_hit:
			table_hit = true
			shake(1.0)
			cost(table_botch, "Sawed into the table")
		_through()
		return
	if not _easy_shown and crossings_left() <= easy_crossings and play_state == Play.RUNNING:
		_easy_shown = true
		show_card("EASY...", 0.45)


func _cut_artery() -> void:
	artery_hit = true
	spurt = clampf(1.0 - tourniquet, 0.0, 1.0)
	# It lands where it lands, and it may well land over the ball's line.
	splat = Vector2(_rng.randf_range(-26.0, 26.0), _rng.randf_range(-16.0, 16.0))
	_chip(6 + int(spurt * 10.0))
	audio(squelch_cue, -3.0 + 4.0 * spurt, 0.1)


func _bleed(delta: float) -> void:
	if spurt <= artery_drip:
		return
	_bleed_acc += spurt * bleed_botch_rate * delta
	if _bleed_acc >= 1.0:
		_bleed_acc -= 1.0
		cost(bleed_botch, "Blood is pouring out of the cut")


func animate(delta: float) -> void:
	_t += delta
	_shown_depth = move_toward(_shown_depth, depth, delta * 2.2)
	miss_flash = maxf(0.0, miss_flash - delta)
	_trail.push_front(ball)
	while _trail.size() > 7:
		_trail.pop_back()


## How big a patch of the court the blood took out. 0 when the tourniquet did its job.
func splat_radius() -> float:
	if spurt <= artery_drip:
		return 0.0
	return splat_base_mm + splat_per_spurt_mm * spurt


## The ball is invisible while it is under the blood.
func ball_hidden() -> bool:
	var r := splat_radius()
	return r > 0.0 and ball.distance_to(splat) < r


func _through() -> void:
	var b = body()
	if b != null and b.has_method("apply_flags"):
		var f: Dictionary = (ctx.get("flags", {}) as Dictionary).duplicate()
		f["amputated"] = true
		b.apply_flags(f)
	audio(thunk_cue, -2.0)
	quality = cut_quality()
	arcade_finish({"amputated": true, "cut_quality": quality})


func cut_quality() -> float:
	var q := 1.0 - 0.13 * float(misses)
	if table_hit:
		q -= 0.2
	return snappedf(clampf(q, 0.05, 1.0), 0.01)


func _update_progress() -> void:
	progress = clampf(depth, 0.0, 1.0)


func _chip(n: int) -> void:
	var y := depth_to_y(depth)
	for i in n:
		if chips.size() >= 26:
			chips.remove_at(0)
		var hc := half_chord(y)
		chips.append([_rng.randf_range(-hc, hc), y + _rng.randf_range(-2.0, 4.0), _rng.randf_range(0.8, 2.4)])


## A jerk knocks both paddles off where you were holding them.
func on_jolt(_offset: Vector2, strength: float, _duration: float) -> void:
	var limit: float = court_half_y - paddle_half()
	paddle_y = clampf(paddle_y + (15.0 if _rng.randf() < 0.5 else -15.0), -limit, limit)
	shake(clampf(0.5 + strength * 0.5, 0.0, 1.0))
	miss_flash = maxf(miss_flash, 0.2)


# ---------------------------------------------------------------------------- the body

func react() -> void:
	var b = body()
	if b == null:
		_seen_misses = misses
		_seen_crossings = crossings
		_seen_artery = artery_hit
		return
	if misses > _seen_misses:
		_seen_misses = misses
		if b.has_method("stir"):
			b.stir(0.6)
	if crossings > _seen_crossings:
		_seen_crossings = crossings
	if artery_hit and not _seen_artery:
		_seen_artery = true
		if b.has_method("stir"):
			b.stir(0.4)
	if b.has_method("set_bleeding"):
		var site := String(ctx.get("step", {}).get("site", "limb_cut"))
		var amount: float = clampf(0.1 + depth * 0.35 + spurt * 0.55 + miss_flash * 0.4, 0.0, 1.0)
		b.set_bleeding(site, amount if play_state != Play.DONE else 0.25)


# ---------------------------------------------------------------------------- the court

func paint_game(c: CanvasItem) -> void:
	if panel == null:
		return
	var st := style()
	_paint_court(c, st)
	_paint_section(c, st)
	_paint_cut(c, st)
	_paint_paddles(c, st)
	_paint_ball(c, st)
	_paint_blood(c, st)
	_paint_scoreboard(c, st)
	if miss_flash > 0.0:
		c.draw_rect(Rect2(Vector2.ZERO, panel.tex_size()), Color(st.danger, miss_flash * 0.2))


func _paint_court(c: CanvasItem, st: StyleScript) -> void:
	for sy: float in [-1.0, 1.0]:
		var y: float = sy * court_half_y
		c.draw_line(px(Vector2(-paddle_x - 4.0, y)), px(Vector2(paddle_x + 4.0, y)), Color(st.line_dim, 0.8), st.thin)
	st.dashed(c, px(Vector2(0.0, -court_half_y)), px(Vector2(0.0, court_half_y)),
		Color(st.line_dim, 0.32), st.hair, 7.0, 7.0)


func _paint_section(c: CanvasItem, st: StyleScript) -> void:
	var outline: PackedVector2Array = PackedVector2Array()
	var inner: PackedVector2Array = PackedVector2Array()
	for i in SAMPLES:
		var a: float = TAU * float(i) / float(SAMPLES)
		outline.append(px(sec_c + _superellipse(a, sec_a, sec_b)))
		inner.append(px(sec_c + _superellipse(a, sec_a - skin_mm, sec_b - skin_mm)))
	c.draw_colored_polygon(outline, Color(st.blood_dark, 0.55))
	c.draw_colored_polygon(inner, st.blood_dark)
	st.glow_poly(c, outline, st.line, st.thin)
	c.draw_polyline(outline, st.line, st.outline)
	c.draw_polyline(inner, Color(st.line_dim, 0.8), st.thin)
	for b in bones:
		var at: Vector2 = px(b[0])
		var r: float = px_len(b[1])
		c.draw_circle(at, r, Color(st.bone, 0.30))
		st.glow_circle(c, at, r, st.bone, st.thin)
		c.draw_arc(at, r, 0.0, TAU, 24, st.bone, st.outline)
		c.draw_circle(at, r * 0.45, Color(st.blood_dark, 0.8))
		c.draw_arc(at, r * 0.45, 0.0, TAU, 16, Color(st.bone, 0.75), st.hair)
	if not artery_hit:
		var aat: Vector2 = px(artery)
		c.draw_circle(aat, px_len(1.7), st.danger)
		c.draw_arc(aat, px_len(2.9), 0.0, TAU, 14, Color(st.danger, 0.55), st.hair)
	for ch in chips:
		c.draw_circle(px(Vector2(ch[0], ch[1])), px_len(ch[2]), Color(st.blood, 0.75))


func _superellipse(a: float, ra: float, rb: float) -> Vector2:
	var ca := cos(a)
	var sa := sin(a)
	var e := 2.0 / maxf(2.0, sec_n)
	return Vector2(signf(ca) * pow(absf(ca), e) * maxf(0.5, ra), signf(sa) * pow(absf(sa), e) * maxf(0.5, rb))


## Everything above the cut line is done: greyed and hatched. The line itself is the kerf.
func _paint_cut(c: CanvasItem, st: StyleScript) -> void:
	var top := sec_c.y - sec_b
	var y := depth_to_y(_shown_depth)
	if _shown_depth > 0.002:
		var done: PackedVector2Array = PackedVector2Array()
		var back: PackedVector2Array = PackedVector2Array()
		for i in 25:
			var yy: float = lerpf(top, y, float(i) / 24.0)
			var hc := half_chord(yy)
			done.append(px(Vector2(-hc, yy)))
			back.append(px(Vector2(hc, yy)))
		for i in range(back.size() - 1, -1, -1):
			done.append(back[i])
		c.draw_colored_polygon(done, Color(st.bg_inner, 0.72))
		var hy := top
		while hy < y:
			var hc2 := half_chord(hy)
			if hc2 > 0.5:
				c.draw_line(px(Vector2(-hc2, hy)), px(Vector2(hc2, hy)), Color(st.line_dim, 0.25), st.hair)
			hy += 2.4
	var hw := maxf(half_chord(y), 2.0) + 5.0
	var a := px(Vector2(-hw, y))
	var b := px(Vector2(hw, y))
	var col: Color = st.danger if in_bone() else st.line
	st.glow_line(c, a, b, col, st.outline)
	c.draw_line(a, b, col, st.outline)
	# Bone is called out with a pattern as well as the colour: ticks along the kerf.
	if in_bone():
		for i in 18:
			var x: float = lerpf(-hw, hw, float(i) / 17.0)
			c.draw_line(px(Vector2(x, y - 1.6)), px(Vector2(x, y + 1.6)), col, st.hair)


func _paint_paddles(c: CanvasItem, st: StyleScript) -> void:
	var h := paddle_half()
	for side: float in [-1.0, 1.0]:
		var x: float = side * paddle_x
		var a := px(Vector2(x, paddle_y - h))
		var b := px(Vector2(x, paddle_y + h))
		var col: Color = st.good if hard_now else st.line
		st.glow_line(c, a, b, col, st.outline * 1.6)
		c.draw_line(a, b, col, st.outline * 2.0)
		# A hard return is flagged by notches too, not only by the colour.
		if hard_now:
			for k in 3:
				var yy: float = lerpf(paddle_y - h * 0.6, paddle_y + h * 0.6, float(k) / 2.0)
				c.draw_line(px(Vector2(x - 3.4 * side, yy)), px(Vector2(x - 6.8 * side, yy)), col, st.thin)


## The blade, with a streak behind it so its line can be read at speed.
func _paint_ball(c: CanvasItem, st: StyleScript) -> void:
	if serve_left > 0.0:
		var k: float = 1.0 - serve_left / maxf(0.05, serve_delay)
		c.draw_arc(px(Vector2.ZERO), px_len(ball_mm + 10.0 * (1.0 - k)), 0.0, TAU, 20, Color(st.line, 0.5), st.thin)
		return
	if ball_hidden():
		return
	for i in _trail.size():
		var t: float = 1.0 - float(i) / float(maxi(1, _trail.size()))
		c.draw_circle(px(_trail[i]), px_len(ball_mm * t * 0.8), Color(st.steel, 0.16 * t))
	var at := px(ball)
	st.glow_circle(c, at, px_len(ball_mm), st.steel, st.thin)
	c.draw_circle(at, px_len(ball_mm), st.steel)
	# Teeth, so it reads as a blade and not a dot.
	var dir: Vector2 = ball_v.normalized() if ball_v.length() > 1.0 else Vector2.RIGHT
	var perp := Vector2(-dir.y, dir.x)
	for k in 5:
		var t: float = (float(k) / 4.0 - 0.5) * 2.0
		var base: Vector2 = px(ball + perp * t * ball_mm)
		c.draw_line(base, base + dir * px_len(ball_mm * 1.5), st.bg, st.hair)


func _paint_blood(c: CanvasItem, st: StyleScript) -> void:
	if spurt <= 0.001:
		return
	c.draw_circle(px(artery), px_len(3.0 + 4.0 * spurt), st.blood)
	var r := splat_radius()
	if r <= 0.0:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = int(ctx.get("seed", 1)) ^ 0x51a7
	for i in 10:
		var a: float = rng.randf() * TAU
		var d: float = rng.randf_range(0.0, r * 0.65)
		var rr: float = rng.randf_range(r * 0.35, r * 0.7)
		c.draw_circle(px(splat + Vector2(cos(a), sin(a)) * d), px_len(rr), Color(st.blood, 0.75))
	c.draw_circle(px(splat), px_len(r * 0.72), Color(st.blood, 0.8))


## Crossings left, misses, and what the blade is in, on one line under the court. Numbers, not a bar.
func _paint_scoreboard(c: CanvasItem, st: StyleScript) -> void:
	var font := ThemeDB.fallback_font
	var left := crossings_left()
	var txt := "%s   %d LEFT" % [String(layer_table()[layer()].name).to_upper(), left]
	if misses > 0:
		txt += "    MISSED %d" % misses
	var w: float = font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x
	var col: Color = st.danger if left <= easy_crossings or misses > 0 else Color(st.line_dim, 0.95)
	c.draw_string(font, px(Vector2(0.0, court_half_y + 7.5)) + Vector2(-w * 0.5, 0), txt,
		HORIZONTAL_ALIGNMENT_LEFT, -1.0, 22, col)


# ---------------------------------------------------------------------------- net

func net_pack() -> Dictionary:
	return {
		"d": snappedf(depth, 0.002), "x": crossings, "m": misses,
		"b": ball, "bv": ball_v, "py": snappedf(paddle_y, 0.2),
		"sl": serve_left, "hn": hard_now, "lh": last_hard,
		"sp": snappedf(spurt, 0.02), "ah": artery_hit, "th": table_hit,
		"sx": splat, "ch": chips.size(),
	}


func net_apply(s: Dictionary) -> void:
	depth = float(s.get("d", depth))
	crossings = int(s.get("x", crossings))
	misses = int(s.get("m", misses))
	ball = s.get("b", ball)
	ball_v = s.get("bv", ball_v)
	paddle_y = float(s.get("py", paddle_y))
	serve_left = float(s.get("sl", serve_left))
	hard_now = bool(s.get("hn", hard_now))
	last_hard = bool(s.get("lh", last_hard))
	var was := spurt
	spurt = float(s.get("sp", spurt))
	artery_hit = bool(s.get("ah", artery_hit))
	table_hit = bool(s.get("th", table_hit))
	splat = s.get("sx", splat)
	var want := int(s.get("ch", chips.size()))
	while chips.size() < want:
		_chip(1)
	while chips.size() > want:
		chips.remove_at(0)
	if spurt > was + 0.01:
		audio(squelch_cue, -3.0, 0.1)
	_update_progress()


# ---------------------------------------------------------------------------- bot

## The bot tracks the ball with an error that grows as its skill drops, and it leans on the hard
## return. A bad one is slow, reads the chatter badly, and keeps hitting hard when it should not.
func bot_input(t: float, skill: float) -> Dictionary:
	var dt: float = clampf(t - _bt, 0.0, 0.1)
	_bt = t
	skill = clampf(skill, 0.0, 1.0)
	if not armed():
		return {"cursor": _out(_b_aim), "buttons": 0}
	# One error per rally, from a golden-ratio sequence: the same hand every run.
	if crossings != _b_err_for:
		_b_err_for = crossings
		_b_seq += 1
		var u: float = fposmod(float(_b_seq) * 0.6180339887498949, 1.0)
		_b_err = (u - 0.5) * 2.0 * lerpf(27.0, 1.5, skill)
	var want: float = ball.y + _b_err
	if ball_hidden():
		want = _b_aim   # it cannot see it either
	var speed: float = lerpf(105.0, 460.0, skill) * dt
	_b_aim = move_toward(_b_aim, clampf(want, -court_half_y, court_half_y), speed)
	# A good hand hits hard except on the run-out; a bad one leans on it and saws the table.
	var hard: bool = crossings_left() > easy_crossings if skill > 0.5 else true
	return {"cursor": _out(_b_aim), "buttons": BUTTON_PRIMARY if hard else 0}


func _out(y: float) -> Vector2:
	return panel.metres_of(Vector2(0.0, y)) if panel != null else Vector2(0.0, y)


# ---------------------------------------------------------------------------- self-test

## Headless check: `tools/minigame_lab.tscn -- --selftest=saw:arcade`.
## Targets: skill 1.0 finishes in 8-20 s losing 0-2 vitals; skill 0.0 under 40 s losing 15-25.
static func self_test() -> Array:
	var script: GDScript = load("res://scripts/surgery/arcade/saw_arcade.gd")
	var out := []
	var ok := true
	var sloppy: Array = []
	for cond: Dictionary in [{"tq": 0.95, "sed": 1.0}, {"tq": 0.45, "sed": 0.4}]:
		for pid: String in ["bob", "seal"]:
			for skill: float in [1.0, 0.5, 0.0]:
				var g = script.new()
				var tally := {"n": 0, "v": 0.0, "done": false, "q": 0.0, "reasons": {}}
				g.botched.connect(func(a, r): tally.n += 1; tally.v += a; tally.reasons[r] = int(tally.reasons.get(r, 0)) + 1)
				g.finished.connect(func(r): tally.done = true; tally.q = float(r.get("cut_quality", 0.0)))
				g.setup({"patient_id": pid, "patient": Procedures.patient(pid), "ailment_id": "amputation",
					"step": Procedures.step("amputation", 2), "variant": "", "shift": 1,
					"difficulty": Procedures.difficulty(1),
					"flags": {"tourniquet": cond.tq, "sedation": cond.sed},
					"seed": hash("sawpong" + pid), "body": null, "operator": true, "operating": true})
				var t: float = run_bot(g, skill, float(cond.sed), hash(pid) + int(skill * 100))
				print("[saw-arcade self-test] %-4s skill=%.1f tq=%.2f sed=%.1f  %s  crossings=%2d missed=%2d  time=%5.1fs  botches=%2d vitals=%5.1f  q=%.2f  %s" % [
					pid, skill, cond.tq, cond.sed, "DONE" if tally.done else "UNFINISHED",
					g.crossings, g.misses, t, tally.n, tally.v, tally.q, str(tally.reasons)])
				out.append({"patient": pid, "skill": skill, "tq": cond.tq, "done": tally.done,
					"time": t, "vitals": tally.v, "q": tally.q, "crossings": g.crossings})
				if float(cond.tq) > 0.9 and float(cond.sed) > 0.9:
					if skill == 1.0 and (not tally.done or t < 8.0 or t > 20.0 or tally.v > 2.0):
						print("[saw-arcade self-test] MISS: skill 1.0 wants 8-20 s and 0-2 vitals")
						ok = false
					if skill == 0.0:
						sloppy.append(tally.v)
						if not tally.done or t > 40.0:
							print("[saw-arcade self-test] MISS: skill 0.0 wants to finish under 40 s")
							ok = false
				g.free()
	# The sloppy band, on the mean: how many rallies a seeded court happens to produce swings one
	# patient a few vitals either side of the other on its own.
	var mean := 0.0
	for v: float in sloppy:
		mean += v
	mean /= maxf(1.0, float(sloppy.size()))
	print("[saw-arcade self-test] skill 0.0 mean vitals %.1f across %d patients (want 15-25)" % [mean, sloppy.size()])
	if mean < 15.0 or mean > 25.0:
		print("[saw-arcade self-test] MISS: skill 0.0 wants 15-25 vitals on average")
		ok = false
	for pid: String in ["bob", "seal"]:
		var clean := _spurt_for(script, pid, 0.95)
		var messy := _spurt_for(script, pid, 0.1)
		print("[saw-arcade self-test] %-4s tourniquet 0.95 -> spurt %.2f, hides %.0f mm   0.10 -> spurt %.2f, hides %.0f mm" % [
			pid, clean[0], clean[1], messy[0], messy[1]])
		out.append({"patient": pid, "spurt_good_tq": clean[0], "spurt_bad_tq": messy[0]})
		if messy[0] <= clean[0] + 0.3 or messy[1] <= clean[1] + 20.0:
			print("[saw-arcade self-test] MISS: a bad tourniquet should blind you and a good one should not")
			ok = false
	print("[saw-arcade self-test] %s" % ("PASS" if ok else "FAIL"))
	return out


static func _spurt_for(script: GDScript, pid: String, tq: float) -> Array:
	var g = script.new()
	g.setup({"patient_id": pid, "patient": Procedures.patient(pid), "ailment_id": "amputation",
		"step": Procedures.step("amputation", 2), "variant": "", "shift": 1,
		"difficulty": 1.0, "flags": {"tourniquet": tq, "sedation": 1.0},
		"seed": hash("sawpong" + pid), "body": null, "operator": true, "operating": true})
	run_bot(g, 1.0, 1.0, 11)
	var r := [g.spurt, g.splat_radius()]
	g.free()
	return r
