extends "res://scripts/surgery/arcade/arcade_game.gd"
## ARCADE SURGERY (docs/ARCADE_SURGERY.md) 5.5 -- SAW! Step "cut" of an amputation: saw through the
## limb. The arcade rebuild of scripts/surgery/games/saw.gd, played on the raised panel.
##
## Rhyme: alternating-key track-and-field mashing, but to a CADENCE. You are not racing, you are
## keeping time, and the time changes with what the blade is in.
##
## What you do
##   The panel shows a CROSS-SECTION of the real limb, built from the body's own section: skin,
##   muscle, and bones (Bob has two, the seal's flipper has a row of little ones). A blade sinks
##   through it. Alternate A and D; each alternation is one stroke and the blade slides across.
##   A pendulum swings at the cadence for the layer the blade is IN -- slow and heavy in bone, quick
##   in skin -- and it flips the moment the blade meets or leaves a bone.
##     ON CADENCE   a full bite.
##     TOO FAST     the saw jumps: almost no bite, chips and blood, and the kerf tears.
##     TOO SLOW     a small bite. No penalty but the clock.
##     SAME KEY     the blade binds for half a second. No cost, just a fool.
##   A seeded artery sits in the muscle. What happens when the blade finds it is entirely down to
##   the tourniquet you put on: a good one dribbles, a bad one paints the panel and HIDES THE
##   PENDULUM, so you have to keep time by ear.
##   And when you are nearly through, the card says EASY... Come off the last strokes too fast and
##   you saw into the table.
##
## Result {"amputated": true, "cut_quality": q} (or `skull_open` on the monster table's variant).

enum Layer { SKIN, MUSCLE, BONE, FAR }

## name, seconds per stroke, resistance, tear factor
const LAYERS := {
	Layer.SKIN: {"name": "skin", "beat": 0.22, "res": 0.45, "tear": 0.5},
	Layer.MUSCLE: {"name": "muscle", "beat": 0.30, "res": 1.0, "tear": 0.8},
	Layer.BONE: {"name": "bone", "beat": 0.50, "res": 2.2, "tear": 1.2},
	Layer.FAR: {"name": "far side", "beat": 0.25, "res": 0.9, "tear": 0.8},
}
## The skull variant's layers, in the same order (its "bone" is the middle of the depth, not a set
## of circles). Only reachable if `saw:skull` is ever switched to the arcade build.
const SKULL_LAYERS := {
	Layer.SKIN: {"name": "scalp", "beat": 0.24, "res": 0.5, "tear": 0.5},
	Layer.MUSCLE: {"name": "scalp", "beat": 0.24, "res": 0.5, "tear": 0.5},
	Layer.BONE: {"name": "bone", "beat": 0.48, "res": 2.0, "tear": 0.75},
	Layer.FAR: {"name": "dura", "beat": 0.28, "res": 0.8, "tear": 0.9},
}

const SAMPLES := 72

# -- the cut ------------------------------------------------------------------------------------
## Depth per full-bite stroke at resistance 1. Tuned for about 35 strokes end to end.
@export_range(0.005, 0.2, 0.001) var bite_per_stroke := 0.039
## What a rushed stroke and a lazy one get instead.
@export_range(0.0, 1.0, 0.01) var rushed_bite := 0.15
@export_range(0.0, 1.0, 0.01) var slow_bite := 0.45
## How far off the cadence a stroke may be, before difficulty tightens it.
@export_range(0.05, 0.9, 0.01) var beat_tolerance := 0.35
## Tear added per rushed stroke, times the layer's tear factor. At 1.0 the kerf gives.
@export_range(0.0, 1.0, 0.01) var tear_per_rush := 0.25
@export_range(0.0, 10.0, 0.5) var tear_botch := 3.0
## Pressing the same key twice running: the blade jams for this long. Costs nothing.
@export_range(0.0, 2.0, 0.05) var bind_time := 0.5
## More than 30% of the blade's chord inside bone and the cadence is the bone cadence.
@export_range(0.05, 0.9, 0.01) var bone_chord_frac := 0.30
## Millimetres of skin at each face of the limb.
@export_range(0.5, 10.0, 0.1) var skin_mm := 2.6

# -- the artery ---------------------------------------------------------------------------------
@export_range(0.0, 1.0, 0.01) var artery_dribble := 0.15   ## spurt below this is just a dribble
@export_range(0.1, 1.0, 0.01) var artery_blinding := 0.5   ## spurt at or above this hides the pendulum
@export_range(0.0, 1.0, 0.01) var bleed_botch_rate := 0.08 ## botch units per unit spurt per second
@export_range(0.0, 10.0, 0.5) var bleed_botch := 1.0

# -- breaking through ----------------------------------------------------------------------------
@export_range(0.5, 1.0, 0.005) var easy_from := 0.97       ## depth where the card says EASY...
@export_range(0.05, 1.0, 0.01) var table_interval := 0.25  ## faster than this down there hits the table
@export_range(0.0, 10.0, 0.5) var table_botch := 3.0

# -- feel -----------------------------------------------------------------------------------------
@export_range(0.0, 1.0, 0.01) var blade_swing_mm := 9.0    ## how far the blade slides on a stroke
@export_range(0.02, 1.0, 0.01) var swing_time := 0.12
@export_range(0, 40) var max_chips := 26

# -- audio ----------------------------------------------------------------------------------------
@export var rasp_cue := "surgery_saw_rasp"
@export var grind_cue := "surgery_saw_grind"
@export var squelch_cue := "surgery_saw_squelch"
@export var thunk_cue := "surgery_saw_thunk"
@export var tick_cue := "surgery_click"
@export var bind_cue := "surgery_forceps_clink"

# ---- replicated state ----
var depth := 0.0                  ## 0 at the near skin, 1 through the far side
var strokes := 0
var rushed := 0
var tear := 0.0                   ## 0..1, how ragged the kerf is right now
var blade_side := -1              ## which way the blade last slid
var bind_left := 0.0
var spurt := 0.0                  ## 0 clean .. 1 pumping, once the artery is cut
var artery_hit := false
var table_hit := false
var beat_phase := 0.0             ## 0..1 through the pendulum's swing
var last_verdict := 0             ## 0 none, 1 good, 2 slow, 3 rushed, 4 bind
var chips: Array = []             ## [x_mm, y_mm, r_mm] splatter on the section
var tear_events := 0
var bleed_events := 0

# ---- derived from the seed ----
var skull := false
var tourniquet := 0.5
var sec_a := 34.0                 ## drawn section half-width, mm
var sec_b := 24.0                 ## drawn section half-height, mm
var sec_c := Vector2(0.0, -6.0)   ## its centre on the panel
var sec_n := 3.0                  ## superellipse exponent
var bones: Array = []             ## [Vector2 centre mm, radius mm]
var artery := Vector2.ZERO        ## mm; .y is the depth line it sits on
var artery_depth := 0.45

# ---- local ----
var _last_key := 0
var _last_stroke_t := -1.0
var _swing := 0.0                 ## 0..1 through the blade's slide
var _shown_depth := 0.0
var _beat_shown := 0.30
var _bleed_acc := 0.0
var _rng := RandomNumberGenerator.new()
var _seen_strokes := 0
var _seen_tears := 0
var _seen_bleeds := 0
var _seen_artery := false
var _easy_shown := false
var _jolt_flip := false           ## after a jolt the next stroke must be the other key
var _flash := 0.0

# ---- bot ----
var _bt := 0.0
var _b_next := 0.0
var _b_key := 0
var _b_seq := 0
var _b_hold := 0.0


# ---------------------------------------------------------------------------- setup

func card_word_for_start() -> String:
	return "SAW!"


func build_game() -> void:
	skull = String(ctx.get("variant", "")) == "skull"
	var flags: Dictionary = ctx.get("flags", {})
	var tq = flags.get("tourniquet", 0.5)
	tourniquet = (1.0 if tq else 0.0) if tq is bool else clampf(float(tq), 0.0, 1.0)
	if skull:
		tourniquet = 1.0
	_rng.seed = int(ctx.get("seed", 1)) ^ 0x5a3
	_build_section()
	_beat_shown = float(layer_table()[Layer.SKIN].beat)
	_update_progress()


func layer_table() -> Dictionary:
	return SKULL_LAYERS if skull else LAYERS


## The cross-section comes from the real limb (PatientBody.site_section), scaled to fit the panel,
## so Bob's forearm and the seal's flipper are visibly different things to saw through.
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
	if skull:
		hu = maxf(hu, hs * 0.42)
	sec_n = shape
	# Fit it into the top two thirds of the panel; the pendulum lives underneath.
	var k: float = minf(44.0 / (hs * 1000.0), 21.0 / (hu * 1000.0))
	sec_a = hs * 1000.0 * k
	sec_b = hu * 1000.0 * k
	sec_c = Vector2(0.0, -9.0)
	bones.clear()
	if skull:
		pass   # the skull's "bone" is a depth band, not circles
	elif _bone_count() >= 3:
		# The flipper: a row of little ones.
		var n := _bone_count()
		var r: float = sec_b * 0.16
		for i in n:
			var t: float = (float(i) + 0.5) / float(n)
			var x: float = lerpf(-sec_a * 0.62, sec_a * 0.62, t)
			var y: float = sec_c.y + sec_b * (0.06 + 0.1 * sin(t * PI))
			bones.append([Vector2(x, y), r * _rng.randf_range(0.86, 1.14)])
	else:
		# Two bones: a big one and a smaller one beside it, the way a forearm goes.
		var big: float = sec_b * 0.30 * _rng.randf_range(0.92, 1.08)
		var small: float = sec_b * 0.23 * _rng.randf_range(0.92, 1.08)
		var gap: float = sec_a * _rng.randf_range(0.28, 0.38)
		bones.append([Vector2(-gap, sec_c.y + sec_b * 0.12), big])
		bones.append([Vector2(gap, sec_c.y + sec_b * 0.18), small])
	# The artery: somewhere in the muscle on the near half, off to one side of the bones.
	artery_depth = _rng.randf_range(0.24, 0.42)
	var ay: float = sec_c.y - sec_b + artery_depth * 2.0 * sec_b
	var side: float = 1.0 if _rng.randf() < 0.5 else -1.0
	artery = Vector2(side * sec_a * _rng.randf_range(0.42, 0.72), ay)


func _bone_count() -> int:
	var pid := String(ctx.get("patient_id", "bob"))
	if pid == "seal":
		return 4 + (1 if _rng.randf() < 0.5 else 0)
	return 2


# ---------------------------------------------------------------------------- the section maths

## Half the chord of the section at panel y, in mm. 0 outside it.
func half_chord(y: float) -> float:
	var t: float = absf((y - sec_c.y) / maxf(0.01, sec_b))
	if t >= 1.0:
		return 0.0
	return sec_a * pow(maxf(0.0, 1.0 - pow(t, sec_n)), 1.0 / sec_n)


func depth_to_y(d: float) -> float:
	return sec_c.y - sec_b + clampf(d, 0.0, 1.0) * 2.0 * sec_b


## How much of the blade's chord at this depth is inside bone, 0..1.
func bone_fraction(d: float) -> float:
	if skull:
		return 1.0 if d > 0.16 and d < 0.84 else 0.0
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


## Which layer the blade is in right now. Bone wins wherever the blade is mostly in bone, so the
## cadence flips as it meets and leaves each one.
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


func beat() -> float:
	return float(layer_table()[layer()].beat)


func tolerance() -> float:
	return beat_tolerance / sqrt(diff)


# ---------------------------------------------------------------------------- playing

func keys() -> Array:
	if play_state == Play.DONE:
		return []
	return [["A / D", "alternate, to the beat"], ["Pendulum", "the cadence for this layer"]]


func hint() -> String:
	var base := super.hint()
	if base != "":
		return base
	if play_state == Play.DONE:
		return "Through."
	if bind_left > 0.0:
		return "The blade is bound: the other key."
	if depth >= easy_from:
		return "Nearly through. Ease off."
	if spurt >= artery_blinding:
		return "You can't see the pendulum. Keep time by ear."
	match last_verdict:
		3: return "Too fast: keep to the beat."
		2: return "You can go with the beat, not behind it."
	return "Alternate A and D on the beat."


func play(_p: Vector2, _buttons: int, edges: int, delta: float) -> void:
	bind_left = maxf(0.0, bind_left - delta)
	var key := 0
	if edges & BUTTON_LEFT:
		key = -1
	elif edges & BUTTON_RIGHT:
		key = 1
	if key == 0:
		return
	if bind_left > 0.0:
		return
	if key == _last_key:
		# Same key twice: the teeth bite the same way and the blade jams. No cost, just time.
		bind_left = bind_time
		last_verdict = 4
		shake(0.35)
		audio(bind_cue, -8.0, 0.1)
		return
	_stroke(key)


## One alternation. The interval since the last one against the cadence for the layer the blade is
## in is the whole game.
func _stroke(key: int) -> void:
	var lay := layer()
	var info: Dictionary = layer_table()[lay]
	var target: float = float(info.beat)
	var tol := tolerance()
	var interval: float = play_t - _last_stroke_t if _last_stroke_t >= 0.0 else target
	_last_stroke_t = play_t
	_last_key = key
	_jolt_flip = false
	blade_side = key
	_swing = 0.0
	strokes += 1
	var bite: float = bite_per_stroke / float(info.res) / pow(diff, 0.35)
	if interval < target * (1.0 - tol):
		last_verdict = 3
		rushed += 1
		bite *= rushed_bite
		tear += tear_per_rush * float(info.tear)
		shake(0.45)
		_chip(3)
		audio(grind_cue if lay == Layer.BONE else rasp_cue, -6.0, 0.15)
		if tear >= 1.0:
			tear -= 1.0
			tear_events += 1
			cost(tear_botch, "The saw jumped and tore the %s" % String(info.name))
	elif interval > target * (1.0 + tol):
		last_verdict = 2
		bite *= slow_bite
		audio(rasp_cue, -12.0, 0.2)
	else:
		last_verdict = 1
		tear = maxf(0.0, tear - 0.02)
		audio(grind_cue if lay == Layer.BONE else rasp_cue, -9.0, 0.12)
	# Sawing into the table: down at the far skin, the last strokes have to come off slowly.
	if depth >= easy_from and interval < table_interval and not table_hit:
		table_hit = true
		cost(table_botch, "Sawed into the table")
		shake(1.0)
	var before := depth
	depth = clampf(depth + bite, 0.0, 1.0)
	if not artery_hit and before < artery_depth and depth >= artery_depth:
		_cut_artery()
	_update_progress()
	if depth >= 1.0:
		_through()


func _cut_artery() -> void:
	artery_hit = true
	# Entirely down to the tourniquet you put on. No tourniquet at all is treated as a bad one.
	spurt = clampf(1.0 - tourniquet, 0.0, 1.0)
	if skull:
		spurt = 0.3
	_chip(6 + int(spurt * 10.0))
	audio(squelch_cue, -3.0 + 4.0 * spurt, 0.1)


func advance(delta: float) -> void:
	bind_left = maxf(0.0, bind_left - delta)
	if spurt > artery_dribble:
		_bleed_acc += spurt * bleed_botch_rate * delta
		if _bleed_acc >= 1.0:
			_bleed_acc -= 1.0
			bleed_events += 1
			cost(bleed_botch, "Blood is pouring out of the cut")
	if depth >= easy_from and not _easy_shown and play_state == Play.RUNNING:
		_easy_shown = true
		show_card("EASY...", 0.45)


func animate(delta: float) -> void:
	_swing = minf(1.0, _swing + delta / maxf(0.02, swing_time))
	_shown_depth = move_toward(_shown_depth, depth, delta * 1.6)
	_flash = maxf(0.0, _flash - delta)
	# The pendulum eases into the new layer's cadence instead of snapping.
	_beat_shown = move_toward(_beat_shown, beat(), delta * 0.9)
	if armed():
		beat_phase = fposmod(beat_phase + delta / maxf(0.05, _beat_shown * 2.0), 1.0)


func _through() -> void:
	var body = body()
	if body != null and body.has_method("apply_flags"):
		var f: Dictionary = (ctx.get("flags", {}) as Dictionary).duplicate()
		f["skull_open" if skull else "amputated"] = true
		body.apply_flags(f)
	audio(thunk_cue, -2.0)
	quality = cut_quality()
	if skull:
		arcade_finish({"skull_open": true, "cut_quality": quality})
	else:
		arcade_finish({"amputated": true, "cut_quality": quality})


func cut_quality() -> float:
	if strokes == 0:
		return 1.0
	var rush_share: float = float(rushed) / float(strokes)
	var q := 1.0 - 0.5 * rush_share - 0.18 * float(tear_events) - 0.06 * float(bleed_events)
	if table_hit:
		q -= 0.2
	return snappedf(clampf(q, 0.05, 1.0), 0.01)


func _update_progress() -> void:
	progress = clampf(depth, 0.0, 1.0)


func _chip(n: int) -> void:
	var y := depth_to_y(depth)
	for i in n:
		if chips.size() >= max_chips:
			chips.remove_at(0)
		var hc := half_chord(y)
		chips.append([_rng.randf_range(-hc, hc), y + _rng.randf_range(-2.0, 4.0), _rng.randf_range(0.8, 2.4)])


## A jerk jams the blade, and the tooth that was about to bite now has to come from the other side.
func on_jolt(_offset: Vector2, strength: float, _duration: float) -> void:
	bind_left = maxf(bind_left, bind_time)
	_jolt_flip = true
	_last_key = -_last_key if _last_key != 0 else 1
	shake(clampf(0.5 + strength * 0.5, 0.0, 1.0))
	_flash = 0.4


# ---------------------------------------------------------------------------- the body

func react() -> void:
	var b = body()
	if b == null:
		return
	if strokes > _seen_strokes:
		_seen_strokes = strokes
		if b.has_method("stir") and last_verdict == 3:
			b.stir(0.25)
	if artery_hit and not _seen_artery:
		_seen_artery = true
		if b.has_method("stir"):
			b.stir(0.4)
	if tear_events > _seen_tears:
		_seen_tears = tear_events
		if b.has_method("stir"):
			b.stir(0.6)
	if bleed_events > _seen_bleeds:
		_seen_bleeds = bleed_events
	if b.has_method("set_bleeding"):
		var site := String(ctx.get("step", {}).get("site", "limb_cut"))
		var amount: float = clampf(0.1 + depth * 0.35 + spurt * 0.55 + tear * 0.2, 0.0, 1.0)
		b.set_bleeding(site, amount if play_state != Play.DONE else 0.25)


# ---------------------------------------------------------------------------- the diagram

func paint_game(c: CanvasItem) -> void:
	if panel == null:
		return
	var st := style()
	_paint_section(c, st)
	_paint_kerf(c, st)
	_paint_blade(c, st)
	_paint_depth_scale(c, st)
	_paint_pendulum(c, st)
	_paint_blood(c, st)
	if _flash > 0.0:
		c.draw_rect(Rect2(Vector2.ZERO, panel.tex_size()), Color(st.danger, _flash * 0.18))


## The limb, end on: a skin ring, the muscle inside it, and the bones.
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
		# The marrow, so a bone reads as a bone and not a hole.
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


## Everything above the blade is already cut: a dark slot with a ragged edge where you tore it.
func _paint_kerf(c: CanvasItem, st: StyleScript) -> void:
	if _shown_depth <= 0.002:
		return
	var top := sec_c.y - sec_b
	var y := depth_to_y(_shown_depth)
	# Everything the blade has already been through is greyed out and hatched, so how far you are
	# reads in one look and not only off the scale at the side.
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
			c.draw_line(px(Vector2(-hc2, hy)), px(Vector2(hc2, hy)), Color(st.line_dim, 0.22), st.hair)
		hy += 2.4
	var left: PackedVector2Array = PackedVector2Array()
	var right: PackedVector2Array = PackedVector2Array()
	var steps := 24
	for i in steps + 1:
		var yy: float = lerpf(top, y, float(i) / float(steps))
		var w: float = minf(half_chord(yy), 3.2 + tear * 2.0)
		left.append(px(Vector2(-w, yy)))
		right.append(px(Vector2(w, yy)))
	var poly: PackedVector2Array = PackedVector2Array()
	poly.append_array(left)
	for i in range(right.size() - 1, -1, -1):
		poly.append(right[i])
	c.draw_colored_polygon(poly, Color(0.02, 0.01, 0.02, 1.0))
	c.draw_polyline(left, Color(st.danger, 0.7), st.thin)
	c.draw_polyline(right, Color(st.danger, 0.7), st.thin)


func _paint_blade(c: CanvasItem, st: StyleScript) -> void:
	var y := depth_to_y(_shown_depth)
	var ease: float = 1.0 - pow(1.0 - _swing, 3.0)
	var slide: float = float(blade_side) * blade_swing_mm * lerpf(-1.0, 1.0, ease)
	if bind_left > 0.0:
		slide += sin(bind_left * 70.0) * 1.6
	var half := sec_a + 14.0
	var a := px(Vector2(-half + slide, y))
	var b := px(Vector2(half + slide, y))
	var col: Color = st.danger if bind_left > 0.0 else st.steel
	st.glow_line(c, a, b, col, st.outline)
	c.draw_line(a, b, col, st.outline)
	# Teeth, so the direction of the last stroke is readable.
	var n := 26
	for i in n:
		var t: float = float(i) / float(n - 1)
		var x: float = lerpf(-half + slide, half + slide, t)
		var top := px(Vector2(x, y))
		c.draw_line(top, top + Vector2(px_len(1.1) * float(blade_side), px_len(1.9)), col, st.hair)
	# The handle end, on the side it just swung to.
	var hx: float = (half + slide) * float(blade_side)
	c.draw_circle(px(Vector2(clampf(hx, -half, half) * 0.0 + (half + slide) * float(blade_side) / maxf(1.0, absf(float(blade_side))), y)), st.thin, col)


## How far through, and how ragged the kerf is, up the right-hand edge.
func _paint_depth_scale(c: CanvasItem, st: StyleScript) -> void:
	var x := 50.0
	var top := -31.0
	var bot := 6.0
	c.draw_line(px(Vector2(x, top)), px(Vector2(x, bot)), Color(st.line_dim, 0.8), st.thin)
	var y: float = lerpf(top, bot, clampf(_shown_depth, 0.0, 1.0))
	c.draw_line(px(Vector2(x - 3.0, y)), px(Vector2(x + 3.0, y)), st.good, st.outline)
	for i in 5:
		var ty: float = lerpf(top, bot, float(i) / 4.0)
		c.draw_line(px(Vector2(x - 1.6, ty)), px(Vector2(x + 1.6, ty)), Color(st.line_dim, 0.7), st.hair)
	# The tear meter beside it: shape as well as colour, so it reads without the red.
	if tear > 0.005:
		var th: float = (bot - top) * clampf(tear, 0.0, 1.0)
		var bx := x + 6.0
		c.draw_line(px(Vector2(bx, bot)), px(Vector2(bx, bot - th)), st.danger, st.outline)
		var n := int(th / 3.0)
		for i in n:
			var ny: float = bot - float(i) * 3.0 - 1.5
			c.draw_line(px(Vector2(bx - 2.0, ny)), px(Vector2(bx + 2.0, ny)), st.danger, st.hair)


## The cadence for the layer the blade is in. A bob swings between the A mark and the D mark: meet
## it at each end and the stroke lands on the beat.
func _paint_pendulum(c: CanvasItem, st: StyleScript) -> void:
	var cy := 25.0
	var span := 38.0
	var lay := layer()
	var name := String(layer_table()[lay].name).to_upper()
	var font := ThemeDB.fallback_font
	c.draw_line(px(Vector2(-span - 6.0, cy)), px(Vector2(span + 6.0, cy)), Color(st.line_dim, 0.7), st.hair)
	for side in [-1.0, 1.0]:
		var at := px(Vector2(side * span, cy))
		c.draw_arc(at, px_len(4.2), 0.0, TAU, 18, Color(st.line_dim, 0.9), st.thin)
		var letter := "A" if side < 0.0 else "D"
		var w: float = font.get_string_size(letter, HORIZONTAL_ALIGNMENT_LEFT, -1, 26).x
		c.draw_string(font, at + Vector2(-w * 0.5, 9.0), letter, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 26, st.line_dim)
	# The bob: a cosine sweep, so it slows at each end where the stroke belongs.
	var bx: float = -cos(beat_phase * TAU) * span
	var at_bob := px(Vector2(bx, cy))
	var near: float = absf(bx) / span
	var on_target: bool = near > 0.86
	var bob_col: Color = st.good if on_target else st.line
	st.glow_circle(c, at_bob, px_len(3.4), bob_col, st.thin)
	c.draw_circle(at_bob, px_len(3.4), bob_col)
	if on_target:
		c.draw_arc(at_bob, px_len(6.4), 0.0, TAU, 20, bob_col, st.thin)
	# Which layer, and its beat, spelled out: the bone cadence is the slow one.
	var label := "%s  %.2fs" % [name, beat()]
	var lw: float = font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x
	c.draw_string(font, px(Vector2(0.0, cy + 9.5)) + Vector2(-lw * 0.5, 0), label,
		HORIZONTAL_ALIGNMENT_LEFT, -1.0, 22, Color(st.line_dim, 0.95))


## The artery. A good tourniquet dribbles; a bad one paints the panel and buries the pendulum.
func _paint_blood(c: CanvasItem, st: StyleScript) -> void:
	if spurt <= 0.001:
		return
	var cover: float = clampf((spurt - artery_dribble) / maxf(0.05, artery_blinding - artery_dribble), 0.0, 1.0)
	var src := px(artery)
	c.draw_circle(src, px_len(3.0 + 4.0 * spurt), st.blood)
	if cover <= 0.001:
		return
	# Seeded blobs, thickest over the pendulum strip: that is the thing you lose.
	var rng := RandomNumberGenerator.new()
	rng.seed = int(ctx.get("seed", 1)) ^ 0x51a7
	var n := int(6 + 16.0 * cover)
	for i in n:
		var x: float = rng.randf_range(-52.0, 52.0)
		var y: float = lerpf(rng.randf_range(10.0, 36.0), rng.randf_range(24.0, 37.0), 0.6)
		var r: float = rng.randf_range(4.0, 13.0) * (0.5 + 0.7 * cover)
		c.draw_circle(px(Vector2(x, y)), px_len(r), Color(st.blood, 0.55 + 0.45 * cover))


# ---------------------------------------------------------------------------- net

func net_pack() -> Dictionary:
	return {
		"d": snappedf(depth, 0.002), "s": strokes, "r": rushed, "tr": snappedf(tear, 0.02),
		"bs": blade_side, "bl": snappedf(bind_left, 0.05), "sp": snappedf(spurt, 0.02),
		"ah": artery_hit, "th": table_hit, "bp": beat_phase,
		"lv": last_verdict, "te": tear_events, "be": bleed_events, "ch": chips.size(),
	}


func net_apply(s: Dictionary) -> void:
	depth = float(s.get("d", depth))
	strokes = int(s.get("s", strokes))
	rushed = int(s.get("r", rushed))
	tear = float(s.get("tr", tear))
	blade_side = int(s.get("bs", blade_side))
	bind_left = float(s.get("bl", bind_left))
	var was_spurt := spurt
	spurt = float(s.get("sp", spurt))
	artery_hit = bool(s.get("ah", artery_hit))
	table_hit = bool(s.get("th", table_hit))
	beat_phase = float(s.get("bp", beat_phase))
	last_verdict = int(s.get("lv", last_verdict))
	tear_events = int(s.get("te", tear_events))
	bleed_events = int(s.get("be", bleed_events))
	# Spectators only get the chip COUNT; the splatter is regenerated locally from the same seed.
	var want := int(s.get("ch", chips.size()))
	while chips.size() < want:
		_chip(1)
	while chips.size() > want:
		chips.remove_at(0)
	if spurt > was_spurt + 0.01:
		audio(squelch_cue, -3.0, 0.1)
	_update_progress()


# ---------------------------------------------------------------------------- bot

## The bot keeps time. A good one lands on the beat; a bad one rushes most of its strokes, goes
## slack on the rest, and now and then hits the same key twice.
func bot_input(t: float, skill: float) -> Dictionary:
	var dt: float = clampf(t - _bt, 0.0, 0.1)
	_bt = t
	skill = clampf(skill, 0.0, 1.0)
	if _b_hold > 0.0:
		_b_hold = maxf(0.0, _b_hold - dt)
		return {"cursor": Vector2.ZERO, "buttons": 0}
	if not armed():
		return {"cursor": Vector2.ZERO, "buttons": 0}
	_b_next -= dt
	if _b_next > 0.0:
		return {"cursor": Vector2.ZERO, "buttons": 0}
	var target := beat()
	# A golden-ratio sequence rather than a random draw: the same hand every run, so the self-test
	# numbers do not swing from seed to seed.
	_b_seq += 1
	var u: float = fposmod(float(_b_seq) * 0.6180339887498949, 1.0)
	# A panicking hand mashes: the sloppy spread is skewed hard toward "too fast", not spread evenly
	# either side of the beat. A good hand sits on it.
	var sloppy: float = lerpf(0.30, 1.45, pow(u, 3.5))
	var factor: float = lerpf(sloppy, lerpf(0.94, 1.06, u), skill)
	# Down at the far skin even a bad hand is told to ease off; a good one listens.
	if depth >= easy_from:
		factor = maxf(factor, lerpf(0.5, 1.7, skill))
	_b_next = maxf(0.05, target * factor)
	_b_hold = 0.05
	# The sloppy hand fumbles the alternation now and then.
	var repeat: bool = skill < 0.5 and fposmod(float(_b_seq) * 0.3819660112501051, 1.0) < (0.10 * (1.0 - skill))
	if not repeat:
		_b_key = -_b_key if _b_key != 0 else -1
	return {"cursor": Vector2.ZERO, "buttons": BUTTON_LEFT if _b_key < 0 else BUTTON_RIGHT}


# ---------------------------------------------------------------------------- self-test

## Headless check: `tools/minigame_lab.tscn -- --selftest=saw:arcade`.
## Targets: skill 1.0 finishes in 8-20 s losing 0-2 vitals; skill 0.0 under 40 s losing 15-25.
static func self_test() -> Array:
	var script: GDScript = load("res://scripts/surgery/arcade/saw_arcade.gd")
	var out := []
	var ok := true
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
					"seed": hash("sawarcade" + pid), "body": null, "operator": true, "operating": true})
				var t: float = run_bot(g, skill, float(cond.sed), hash(pid) + int(skill * 100))
				print("[saw-arcade self-test] %-4s skill=%.1f tq=%.2f sed=%.1f  %s  strokes=%3d rushed=%3d  time=%5.1fs  botches=%2d vitals=%5.1f  q=%.2f  %s" % [
					pid, skill, cond.tq, cond.sed, "DONE" if tally.done else "UNFINISHED",
					g.strokes, g.rushed, t, tally.n, tally.v, tally.q, str(tally.reasons)])
				out.append({"patient": pid, "skill": skill, "tq": cond.tq, "done": tally.done,
					"time": t, "vitals": tally.v, "q": tally.q, "strokes": g.strokes})
				if float(cond.tq) > 0.9 and float(cond.sed) > 0.9:
					if skill == 1.0 and (not tally.done or t < 8.0 or t > 20.0 or tally.v > 2.0):
						print("[saw-arcade self-test] MISS: skill 1.0 wants 8-20 s and 0-2 vitals")
						ok = false
					if skill == 0.0 and (not tally.done or t > 40.0 or tally.v < 15.0 or tally.v > 25.0):
						print("[saw-arcade self-test] MISS: skill 0.0 wants under 40 s and 15-25 vitals")
						ok = false
				g.free()
	# The carry-forward: a bad tourniquet must cost more than a good one on the same hand.
	for pid: String in ["bob", "seal"]:
		var clean := _bleed_cost(script, pid, 0.95)
		var messy := _bleed_cost(script, pid, 0.1)
		print("[saw-arcade self-test] %-4s tourniquet 0.95 -> spurt %.2f   0.10 -> spurt %.2f" % [pid, clean, messy])
		out.append({"patient": pid, "spurt_good_tq": clean, "spurt_bad_tq": messy})
		if messy <= clean + 0.3:
			print("[saw-arcade self-test] MISS: a bad tourniquet should spurt much harder")
			ok = false
	print("[saw-arcade self-test] %s" % ("PASS" if ok else "FAIL"))
	return out


static func _bleed_cost(script: GDScript, pid: String, tq: float) -> float:
	var g = script.new()
	g.setup({"patient_id": pid, "patient": Procedures.patient(pid), "ailment_id": "amputation",
		"step": Procedures.step("amputation", 2), "variant": "", "shift": 1,
		"difficulty": 1.0, "flags": {"tourniquet": tq, "sedation": 1.0},
		"seed": hash("sawarcade" + pid), "body": null, "operator": true, "operating": true})
	run_bot(g, 1.0, 1.0, 11)
	var s: float = g.spurt
	g.free()
	return s
