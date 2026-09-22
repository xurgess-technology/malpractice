extends "res://scripts/surgery/arcade/arcade_game.gd"
## ARCADE SURGERY -- WHACK! then WRAP!, step three of a gunshot wound. Step "dress" (`gauze` x1,
## variant `pack`, site `gunshot`). Built from docs/PACK_AND_WRAP_SPEC.md, "Addendum Two -- Pack &
## Wrap"; that file wins where anything here disagrees with it. It runs on the clipboard shell
## (scripts/surgery/panel/shell.gd) the Anesthetic Injection and DODGE! already use.
##
## ONE step, TWO stages, and one results card at the end.
##
## Stage A, WHACK! -- whack-a-mole, played straight: one clean commit per target, on a timer you do
##   not control. The wound tract lies across the page and the bleeders sit along it. Each open one
##   spurts for 2.2 s, then goes quiet for a while; at most two spurt at once and the rest wait their
##   turn. Point at a spurting one and HOLD SPACE: a ring closes over `pack_hold` and reaching full
##   plugs it for good. One commit, no partial credit, no re-opening. Letting go early costs nothing
##   but the time.
##   BLOOD IS AN EVENT, NOT A FILL. The old screen-filling column is gone: it never localized the
##   problem and never resolved. Instead the loss meter only climbs WHILE something is spurting, so
##   holding everything shut actually holds it; drips fall from open bleeders and leave marks where
##   they land; and past 40% the page starts throwing splats of its own. At 100% the stage ends after
##   a beat, and plugging everything ends it early and cleanly.
##
## Stage B, WRAP! -- Snake, played straight, in wrap_roll.gd (shared with the stump). The one piece of
##   cross-talk between the stages: the share of wound cells that need a SECOND bandage layer is
##   1 - pack quality. How badly you packed is the routing puzzle you get.
##
## CARRY-FORWARD IN: `flags.tears` from DODGE! (dodge_arcade.gd) is an Array of floats 0..1, one per
## wall you tore on the way out. Bleeders = 1 (the bullet bed) + one per tear + zero or one seeded
## extra, clamped to 3-7. A clean extraction, the legacy forceps step and the warmup's ctx all hand
## over no tears at all, so an absent or junk `tears` must fall through to the seeded floor.
## CARRY-FORWARD OUT: {"dressed": true, "pack_quality": q, "dress_marks": s} -- the same contract the
## script this replaced finished with.
##
## THE RESULTS CARD is a stamp card, not a screen, and it has no Retry: a live case cannot be retried
## (the standing ruling in docs/SURGERY_SHELL_AND_DODGE_SPEC.md, Decisions 1). It shows the grade and
## the numbers behind it, and the press that takes it down ends the step.
##
## Space: the spec's 960 x 600 reference px ("rpx") laid on the paper, same as DODGE!.

const RollScript := preload("res://scripts/surgery/arcade/wrap_roll.gd")

const REF := Vector2(960.0, 600.0)
## Splat index ranges, kept apart so the shell never throws the same blood twice.
const GORE_FROM := 5000
const DRIP_FROM := 20000

enum Stage { WHACK, WRAP, RESULT }

# -- the tract (spec 2.1) -------------------------------------------------------------------------
@export_group("Tract")
## Where the channel runs across the page, rpx, and how far its centreline may wander.
@export_range(40.0, 300.0, 1.0) var tract_x0 := 108.0
@export_range(400.0, 940.0, 1.0) var tract_x1 := 852.0
@export_range(100.0, 500.0, 1.0) var tract_mid_y := 286.0
@export_range(0.0, 120.0, 1.0) var tract_wander := 42.0
## Half-width of the channel, rpx, and its wobble along the way.
@export_range(10.0, 80.0, 1.0) var tract_half := 31.0
@export_range(0.0, 0.6, 0.01) var tract_half_wobble := 0.18

# -- the bleeders (spec 2.1, 2.2) -------------------------------------------------------------------
@export_group("Bleeders")
## Total bleeders is clamped into this band however many tears came over.
@export_range(1, 9) var min_bleeders := 3
@export_range(1, 9) var max_bleeders := 7
## How far a bleeder may be jittered off its even interval along the tract, share of one interval.
@export_range(0.0, 0.5, 0.01) var spacing_jitter := 0.30
## Seconds an open bleeder spurts before it cools (spec 2.2: 2.2 s).
@export_range(0.5, 6.0, 0.05) var spurt_time := 2.2
## And how long it stays quiet before its turn comes round again.
@export_range(0.1, 6.0, 0.05) var cool_min := 0.7
@export_range(0.1, 8.0, 0.05) var cool_max := 2.9
## At most this many spurt at once; the rest wait their turn.
@export_range(1, 5) var spurt_at_once := 2
## How near the cursor has to be, rpx. The bed is bigger, so it gets `bed_scale` of this too.
@export_range(10.0, 90.0, 1.0) var hit_px := 34.0
@export_range(1.0, 2.5, 0.05) var bed_scale := 1.45

# -- packing (spec 2.2, tuning knob "packHold") -----------------------------------------------------
@export_group("Packing")
## Hold Space this long with the ring over a spurting bleeder and it is plugged for good.
## SPEC 5 TUNING KNOB "packHold": 0.4 s (0.15-1). Divided by the shift's difficulty factor.
@export_range(0.15, 1.0, 0.01) var pack_hold := 0.4
## The ring's radius on the page, rpx.
@export_range(14.0, 70.0, 1.0) var ring_px := 30.0

# -- blood loss (spec 2.3, tuning knob "bloodRate") -------------------------------------------------
@export_group("Blood")
## SPEC 5 TUNING KNOB "bloodRate": 1.0x (0.4-2). It multiplies BOTH halves of the rate below.
@export_range(0.4, 2.0, 0.05) var blood_rate := 1.0
## Loss per second while anything is spurting: this, plus `loss_per_open` for each one that is.
@export_range(0.0, 0.2, 0.001) var loss_base := 0.030
@export_range(0.0, 0.2, 0.001) var loss_per_open := 0.026
## Drips per second from each spurting bleeder, and how fast they fall (rpx/s, rpx/s^2).
@export_range(0.0, 30.0, 0.5) var drips_per_sec := 9.0
@export_range(0.0, 600.0, 10.0) var drip_gravity := 340.0
@export_range(0.0, 300.0, 5.0) var drip_speed0 := 40.0
## Past this much loss the page starts throwing splats of its own, one per `gore_band` of loss...
@export_range(0.0, 1.0, 0.01) var gore_from := 0.40
@export_range(0.02, 0.5, 0.01) var gore_band := 0.10
## ...and three at a time past here.
@export_range(0.0, 1.0, 0.01) var gore_triple_from := 0.80
## The beat between bleeding out and the stage ending.
@export_range(0.0, 4.0, 0.05) var bleed_out_beat := 1.1

# -- wrapping (spec 3, tuning knob "snakeRate") -----------------------------------------------------
@export_group("Wrap")
## SPEC 5 TUNING KNOB "snakeRate": 0.16 s per cell (0.08-0.3). Divided by the difficulty factor.
@export_range(0.08, 0.3, 0.005) var snake_rate := 0.16
## SPEC 5: gauze in hand when WRAP! begins.
@export_range(0, 6) var start_carry := 1
## Cells the wound blob aims for, and the chance it branches into each free neighbour (spec 3.1).
@export_range(4, 60) var blob_cells := 14
@export_range(0.1, 1.0, 0.01) var branch_chance := 0.62
## What a tangle costs the patient (spec 3.2).
@export_range(0.0, 20.0, 0.5) var tangle_cost := 5.0

# -- the results card (spec 4) ----------------------------------------------------------------------
@export_group("Results")
## Score = packQ x this + coverage% x `score_cover` - tangles x `score_tangle`, clamped 0-100.
@export_range(0.0, 100.0, 1.0) var score_pack := 45.0
@export_range(0.0, 2.0, 0.01) var score_cover := 0.45
@export_range(0.0, 40.0, 0.5) var score_tangle := 6.0
@export_range(0, 100) var grade_clean := 80
@export_range(0, 100) var grade_sloppy := 48
## How long the results card sits there before it will take a press.
@export_range(0.0, 5.0, 0.1) var result_lock := 1.4
## The results card is bigger than the shell's instruction cards: it has to hold three lines of
## numbers as well as the grade and a flavour line.
@export var result_card_size := Vector2(600.0, 232.0)

@export_group("Difficulty")
## `pack_hold` and `snake_rate` are divided by difficulty ^ this, so later shifts are quicker.
@export_range(0.0, 2.0, 0.05) var difficulty_gain := 0.5

@export_group("Audio")
@export var pack_cue := "surgery_pack"
@export var plug_cue := "surgery_forceps_squelch"
@export var too_soon_cue := "surgery_swish"
@export var drip_cue := "surgery_saw_squelch"
@export var tangle_cue := "surgery_tear"
@export var layer_cue := "surgery_pack"
@export var eat_cue := "surgery_click"
@export_group("")

# ---- replicated ----
var stage: int = Stage.WHACK
## Per bleeder, in the order they were laid out. Index 0 is always the bullet bed.
var b_at: Array[Vector2] = []          ## rpx on the page
var b_u: Array[float] = []             ## 0..1 along the tract
var b_bed: Array[bool] = []
var b_closed: Array[bool] = []
var b_spurt: Array[bool] = []
var b_timer: Array[float] = []         ## seconds left of the spurt, or of the cool-down. THIS CREEPS.
## The closing ring: 0..1, and which bleeder it is over (-1 for none).
var ring := 0.0
var ring_on := -1
var loss := 0.0                        ## BLOOD LOST, 0..1. THIS CREEPS.
var gore := 0                          ## splats the page has thrown on its own
var beat := 0.0                        ## the pause between bleeding out and the stage ending
var bled_out := false
var pack_q := 1.0                      ## plugged / total, snapped before it goes on the wire
var roll: RollScript = null
var score := 0
var _grade := ""

# ---- from the seed ----
var lane: PackedFloat32Array = PackedFloat32Array()   ## centreline offset per rpx of tract
var half_w: PackedFloat32Array = PackedFloat32Array()
var tears_in := 0
var grime_spots: Array = []

# ---- local ----
var _rng := RandomNumberGenerator.new()
var _drips: Array = []                 ## [pos: Vector2, vel: float] -- cosmetic, per machine
var _marks := 0                        ## drip marks this machine has laid
var _gore_seen := 0
var _seen := {}
var _warm := false
var _spurt_seq := 0                    ## bumped every time one starts spurting, for the sound

# ---- bot ----
var _bt := 0.0
var _b_gate := -1.0
var _b_up := false
var _b_aim := Vector2.ZERO


# ---------------------------------------------------------------------------- setup

func use_ink() -> bool:
	return true


func ink_unit() -> float:
	return _u()


func card_word_for_start() -> String:
	return "WHACK!"


func build_game() -> void:
	if ink != null:
		ink.content = Rect2(Vector2(0.0, _top()), REF * _u())
	var seed_v := int(ctx.get("seed", 1))
	_rng.seed = hash("pack_wrap|%d" % seed_v)
	_build_tract()
	_build_bleeders()
	grime_spots = InkScript.make_grime(_rng, Rect2(Vector2(40, 60), panel.tex_size() - Vector2(80, 120)))
	_update_progress()


## difficulty ^ difficulty_gain: what the timing knobs are divided by on a later shift.
func dk() -> float:
	return pow(maxf(0.5, diff), difficulty_gain)


func hold_time() -> float:
	return maxf(0.05, pack_hold / dk())


## The channel across the page: a couple of seeded sines for the centreline, a wobbling half-width.
func _build_tract() -> void:
	var n: int = maxi(2, int(ceil(tract_x1 - tract_x0)) + 1)
	lane.resize(n)
	half_w.resize(n)
	var a1 := _rng.randf_range(0.45, 1.0)
	var a2 := _rng.randf_range(0.2, 0.6)
	var f1 := _rng.randf_range(0.006, 0.013)
	var f2 := _rng.randf_range(0.015, 0.028)
	var p1 := _rng.randf_range(0.0, TAU)
	var p2 := _rng.randf_range(0.0, TAU)
	var wf := _rng.randf_range(0.01, 0.02)
	var wp := _rng.randf_range(0.0, TAU)
	# One scale factor fits the whole centreline into the wander band: scaled, never clipped.
	var peak := 0.001
	for i in n:
		var v: float = a1 * sin(f1 * float(i) + p1) + a2 * sin(f2 * float(i) + p2)
		lane[i] = v
		peak = maxf(peak, absf(v))
	var k := tract_wander / peak
	for i in n:
		lane[i] = lane[i] * k
		half_w[i] = tract_half * (1.0 + tract_half_wobble * sin(wf * float(i) + wp))


## The page position of the point `u` (0 at the bed, 1 at the mouth) along the tract.
func tract_at(u: float) -> Vector2:
	var x: float = lerpf(tract_x0, tract_x1, clampf(u, 0.0, 1.0))
	var i: int = clampi(int(round(x - tract_x0)), 0, maxi(0, lane.size() - 1))
	return Vector2(x, tract_mid_y + (lane[i] if lane.size() > 0 else 0.0))


func tract_half_at(u: float) -> float:
	var x: float = lerpf(tract_x0, tract_x1, clampf(u, 0.0, 1.0))
	var i: int = clampi(int(round(x - tract_x0)), 0, maxi(0, half_w.size() - 1))
	return half_w[i] if half_w.size() > 0 else tract_half


## SPEC 2.1: 1 (the bullet bed) + one per tear carried over from DODGE! + zero or one seeded extra,
## clamped 3-7, spread along the tract at even intervals with jitter. Index 0 is always the bed.
func _build_bleeders() -> void:
	var flags = ctx.get("flags", {})
	var tears := 0
	if flags is Dictionary:
		var raw = (flags as Dictionary).get("tears", [])
		if raw is Array:
			for v in raw:
				if v is float or v is int:
					tears += 1
	tears_in = tears
	var extra: int = 1 if _rng.randf() < 0.5 else 0
	var n: int = clampi(1 + tears + extra, mini(min_bleeders, max_bleeders), maxi(min_bleeders, max_bleeders))
	b_at.clear()
	b_u.clear()
	b_bed.clear()
	b_closed.clear()
	b_spurt.clear()
	b_timer.clear()
	for i in n:
		# Even intervals, jittered, from the bed end to the mouth end.
		var span := 1.0 / float(n)
		var u: float = span * (float(i) + 0.5)
		u += span * _rng.randf_range(-spacing_jitter, spacing_jitter)
		u = clampf(u, 0.02, 0.98)
		b_u.append(u)
		b_at.append(tract_at(u))
		b_bed.append(i == 0)
		b_closed.append(false)
		b_spurt.append(false)
		# Staggered starts, so they do not all come up together on the first second.
		b_timer.append(_rng.randf_range(0.0, cool_max))


func bleeders() -> int:
	return b_u.size()


func plugged() -> int:
	var n := 0
	for v in b_closed:
		if v:
			n += 1
	return n


func spurting() -> int:
	var n := 0
	for i in b_spurt.size():
		if b_spurt[i] and not b_closed[i]:
			n += 1
	return n


func all_plugged() -> bool:
	return plugged() >= bleeders()


func hit_radius(i: int) -> float:
	return hit_px * (bed_scale if i < b_bed.size() and b_bed[i] else 1.0)


# ---------------------------------------------------------------------------- space

func _u() -> float:
	return (panel.tex_size().x if panel != null else 1200.0) / REF.x


func _top() -> float:
	return ((panel.tex_size().y if panel != null else 800.0) - REF.y * _u()) * 0.5


## rpx -> canvas px (the unturned layout the page is drawn in).
func cv(p: Vector2) -> Vector2:
	return Vector2(p.x * _u(), p.y * _u() + _top())


func cl(v: float) -> float:
	return v * _u()


## The framework's cursor (diagram mm) -> rpx, through the page's tilt.
func ref_of_mm(mm: Vector2) -> Vector2:
	var c: Vector2 = panel.mm_to_px(mm)
	if ink != null:
		c = ink.unpage(c, panel.tex_size())
	return Vector2(c.x / _u(), (c.y - _top()) / _u())


## rpx -> the framework's cursor (panel metres), for the bot.
func metres_of_ref(p: Vector2) -> Vector2:
	if panel == null:
		return Vector2.ZERO
	var c := cv(p)
	if ink != null:
		c = ink.onpage(c, panel.tex_size())
	var mm: Vector2 = (c - panel.tex_size() * 0.5) / panel.px_per_mm()
	return panel.metres_of(mm)


# ---------------------------------------------------------------------------- the cards and the HUD

func stamp_for(word: String) -> Dictionary:
	var I := ink
	match word:
		"WHACK!":
			var lines := ["Only a spurting bleeder can be packed. Hold until the ring closes."]
			if tears_in > 0:
				lines.append("Every wall you tore on the way out is bleeding: %d of these are yours." % tears_in)
			else:
				lines.append("He only bleeds while one of them is open. Shut them and it stops.")
			return {"goal": "Plug every bleeder before he empties.", "lines": lines,
				"prompt": "SPACE to start", "color": I.ink if I != null else Color.BLACK}
		"WRAP!":
			var lines2 := ["WASD to steer. Gauze lengthens the roll; laying a layer spends it."]
			var bleed := _bleed_cells()
			if bleed > 0:
				lines2.append("%d cells are still bleeding through: they want two layers, not one." % bleed)
			else:
				lines2.append("Packed clean, so one layer covers it. Don't drive into your own tail.")
			return {"goal": "Lay bandage over every cell of the wound.", "lines": lines2,
				"prompt": "SPACE to start", "color": I.ink if I != null else Color.BLACK}
		"CLEAN", "SLOPPY", "MALPRACTICE":
			return {"goal": _flavour(word), "lines": _result_lines(),
				"prompt": "SPACE to finish", "wait": "Look at it...",
				"color": (I.good if word == "CLEAN" else I.deep_red) if I != null else Color.BLACK}
	return {"prompt": "SPACE"}


func _result_lines() -> Array:
	return [
		"Bleeders plugged %d of %d   ·   pack %d%%" % [plugged(), bleeders(), int(round(pack_q * 100.0))],
		"Wound covered %d%%   ·   tangles %d   ·   vitals %d" % [int(round(coverage() * 100.0)), tangles(), int(round(vitals_lost()))],
		"SCORE %d" % score,
	]


func _flavour(grade: String) -> String:
	match grade:
		"CLEAN":
			return "Dry, covered, and nobody has to know."
		"SLOPPY":
			return "It'll hold. Probably. Don't jog."
	return "That is not a dressing. That is upholstery."


func hud_line() -> String:
	match stage:
		Stage.WHACK:
			return "Point at a spurting bleeder\nSPACE hold: pack it"
		Stage.WRAP:
			return "WASD: steer the roll\nGauze lengthens it, a layer spends it"
	return ""


## The one number that decides the grade: what he is losing, then how much is covered.
func hud_value() -> Array:
	match stage:
		Stage.WHACK:
			return ["BLOOD LOST %d%%" % int(round(loss * 100.0)), loss >= gore_from]
		Stage.WRAP:
			return ["WOUND %d%%" % int(round(coverage() * 100.0)), _bleed_open() > 0]
	return ["SCORE %d" % score, _grade == "MALPRACTICE"]


func keys() -> Array:
	match stage:
		Stage.WHACK:
			return [["Hold Space", "pack the bleeder"]]
		Stage.WRAP:
			return [["WASD", "steer"], ["Gauze", "lengthens the roll"]]
	return []


func hint() -> String:
	if stamp_waiting():
		match card_word:
			"WHACK!":
				return "The bullet's out and the wound is bleeding. Plug it."
			"WRAP!":
				return "Now dress it: lay bandage over every cell."
		return "Done. Space to finish."
	var base := super.hint()
	if base != "":
		return base
	match stage:
		Stage.WHACK:
			if bled_out:
				return "He's lost too much. Get off it."
			if spurting() <= 0:
				return "Nothing spurting: wait for the next one to come up."
			return "Hold Space on a spurting bleeder until the ring closes."
		Stage.WRAP:
			if roll != null and roll.carry() <= 0:
				return "Empty-handed. Go and pick up gauze."
			return "Lay a layer on every cell. The crossed ones want two."
	return ""


# ---------------------------------------------------------------------------- playing

func play(p_mm: Vector2, buttons: int, edges: int, delta: float) -> void:
	match stage:
		Stage.WHACK:
			_play_whack(ref_of_mm(p_mm), buttons, delta)
		Stage.WRAP:
			_play_wrap(buttons)
		Stage.RESULT:
			# Getting here at all means the results card has been taken down, and that press is the
			# stage's one action: the step ends.
			_finish_step()


## SPEC 2.2: hold Space and a ring closes over `pack_hold`. Reaching full plugs the bleeder under the
## cursor for good; reaching full with nothing under the cursor bursts TOO SOON! as a tell, not a
## punishment. Letting go early just cancels.
func _play_whack(p: Vector2, buttons: int, delta: float) -> void:
	_last_cursor = p
	if bled_out:
		return
	var held: bool = (buttons & BUTTON_ACTION) != 0
	if not held:
		ring = 0.0
		ring_on = -1
		return
	ring_on = _spurting_under(p)
	ring = minf(1.0, ring + delta / hold_time())
	if ring < 1.0:
		return
	ring = 0.0
	if ring_on >= 0:
		_plug(ring_on)
	else:
		burst("TOO SOON!", cv(p + Vector2(0.0, -54.0)))
		audio(too_soon_cue, -14.0, 0.15)
	ring_on = -1


## The spurting bleeder under `p`, or -1. Only a spurting one can be packed at all.
func _spurting_under(p: Vector2) -> int:
	var best := -1
	var best_d := INF
	for i in bleeders():
		if b_closed[i] or not b_spurt[i]:
			continue
		var d: float = p.distance_to(b_at[i])
		if d <= hit_radius(i) and d < best_d:
			best_d = d
			best = i
	return best


## One commit. No partial credit, and it can never open again.
func _plug(i: int) -> void:
	b_closed[i] = true
	b_spurt[i] = false
	b_timer[i] = 0.0
	_update_progress()
	if all_plugged():
		_to_wrap()


func _play_wrap(buttons: int) -> void:
	if roll == null:
		return
	if (buttons & BUTTON_UP) != 0:
		roll.steer(Vector2i(0, -1))
	elif (buttons & BUTTON_DOWN) != 0:
		roll.steer(Vector2i(0, 1))
	elif (buttons & BUTTON_LEFT) != 0:
		roll.steer(Vector2i(-1, 0))
	elif (buttons & BUTTON_RIGHT) != 0:
		roll.steer(Vector2i(1, 0))


func advance(delta: float) -> void:
	match stage:
		Stage.WHACK:
			_advance_whack(delta)
		Stage.WRAP:
			_advance_wrap(delta)


func _advance_whack(delta: float) -> void:
	if bled_out:
		beat = maxf(0.0, beat - delta)
		if beat <= 0.0:
			_to_wrap()
		return
	_cycle(delta)
	# SPEC 2.3: the meter moves ONLY while something is actually spurting, so shutting them all
	# holds it rather than slowing it.
	var open := spurting()
	if open > 0:
		loss = minf(1.0, loss + (loss_base + loss_per_open * float(open)) * blood_rate * delta)
		_page_gore()
		if loss >= 1.0:
			bled_out = true
			beat = bleed_out_beat
			ring = 0.0
			ring_on = -1


## SPEC 2.2: each open bleeder spurts for `spurt_time`, then cools for 0.7-2.9 s. At most
## `spurt_at_once` spurt together -- a bleeder whose turn has come waits at zero until there is room.
func _cycle(delta: float) -> void:
	for i in bleeders():
		if b_closed[i]:
			continue
		b_timer[i] = maxf(0.0, b_timer[i] - delta)
		if b_timer[i] > 0.0:
			continue
		if b_spurt[i]:
			b_spurt[i] = false
			b_timer[i] = _rng.randf_range(cool_min, maxf(cool_min, cool_max))
		elif spurting() < spurt_at_once:
			b_spurt[i] = true
			b_timer[i] = spurt_time
			_spurt_seq += 1


## SPEC 2.3: past `gore_from` the page throws one extra splat per band of loss, three at a time past
## `gore_triple_from`. Replicated as a count, so every machine throws the same blood.
func _page_gore() -> void:
	if loss < gore_from:
		return
	var bands: int = int(floor((loss - gore_from) / maxf(0.01, gore_band))) + 1
	var want := 0
	for b in bands:
		want += 3 if (gore_from + float(b) * gore_band) >= gore_triple_from else 1
	gore = maxi(gore, want)


func _advance_wrap(delta: float) -> void:
	if roll == null:
		return
	for e in roll.advance(delta):
		_pay(e)
	_update_progress()


## What the roll's events cost. A tangle is the only one that bills.
func _pay(e: Dictionary) -> void:
	match String(e.get("e", "")):
		"tangle":
			mistake("TANGLE!", tangle_cost, "Tangled the bandage", "tangle",
				cv(e.get("at", Vector2.ZERO)), true)
		"done":
			_to_result()


# ---------------------------------------------------------------------------- the stages

## SPEC 2.4: pack quality = plugged / total, and it goes straight into WRAP! as the share of wound
## cells that want a second layer. There is no WHACK! card of its own. It is SNAPPED HERE, before it
## can reach the wire, so an onlooker builds exactly the same board.
func _to_wrap() -> void:
	pack_q = snappedf(clampf(float(plugged()) / maxf(1.0, float(bleeders())), 0.0, 1.0), 0.01)
	stage = Stage.WRAP
	ring = 0.0
	ring_on = -1
	_build_roll()
	show_card("WRAP!")
	_update_progress()


func _build_roll() -> void:
	roll = RollScript.new()
	roll.blob_cells = blob_cells
	roll.branch_chance = branch_chance
	roll.start_carry = start_carry
	roll.step_time = maxf(0.02, snake_rate / dk())
	roll.tangle_cost = tangle_cost
	roll.build(int(ctx.get("seed", 1)), String(ctx.get("variant", "pack")), 1.0 - pack_q)


func _to_result() -> void:
	score = grade_score()
	_grade = grade_word()
	stage = Stage.RESULT
	# The results card carries three lines of numbers under its flavour line, which will not fit the
	# shell's instruction-card size. It is the last card of the step, so nothing has to be put back.
	if shell != null:
		shell.stamp_size = result_card_size
	show_card(_grade, result_lock)
	progress = 1.0


func _finish_step() -> void:
	var marks: String = roll.marks() if roll != null else ""
	quality = clampf(float(score) / 100.0, 0.05, 1.0)
	var b = body()
	if b != null:
		if b.has_method("set_bleeding"):
			b.set_bleeding(String(ctx.get("step", {}).get("site", "gunshot")), 0.0)
		if b.has_method("apply_flags"):
			var f: Dictionary = (ctx.get("flags", {}) as Dictionary).duplicate()
			f["dressed"] = true
			f["dress_marks"] = marks
			b.apply_flags(f)
	arcade_finish({"dressed": true, "pack_quality": snappedf(pack_q, 0.01), "dress_marks": marks})


# ---------------------------------------------------------------------------- the grade (spec 4)

func coverage() -> float:
	return roll.frac() if roll != null else 0.0


func tangles() -> int:
	return roll.tangles if roll != null else 0


func vitals_lost() -> float:
	return tangle_cost * float(tangles())


func _bleed_cells() -> int:
	if roll == null:
		return 0
	var n := 0
	for v in roll.bleeding:
		if v:
			n += 1
	return n


func _bleed_open() -> int:
	if roll == null:
		return 0
	var n := 0
	for w in roll.wound.size():
		if roll.bleeding[w] and not roll.satisfied(w):
			n += 1
	return n


## SPEC 4: round(packQ x 45 + coverage% x 0.45 - tangles x 6), clamped 0-100.
func grade_score() -> int:
	var s: float = pack_q * score_pack + coverage() * 100.0 * score_cover - float(tangles()) * score_tangle
	return clampi(int(round(s)), 0, 100)


## SPEC 4: CLEAN at 80 or over, SLOPPY at 48 or over, else MALPRACTICE.
func grade_word() -> String:
	var s := grade_score()
	if s >= grade_clean:
		return "CLEAN"
	if s >= grade_sloppy:
		return "SLOPPY"
	return "MALPRACTICE"


func _update_progress() -> void:
	match stage:
		Stage.WHACK:
			progress = 0.45 * clampf(float(plugged()) / maxf(1.0, float(bleeders())), 0.0, 1.0)
		Stage.WRAP:
			progress = 0.45 + 0.55 * coverage()
		_:
			progress = 1.0


# ---------------------------------------------------------------------------- animation and sound

## Runs on every machine, frozen or not: the drips and the blood they leave are local weather driven
## by the replicated spurting set, so a spectator's page gets messy at the same rate without any of it
## going over the wire.
func animate(delta: float) -> void:
	if stage == Stage.WHACK:
		_drip_spawn(delta)
	_drip_fall(delta)
	# The page's own splatter IS replicated (a count), so everyone throws the same blood.
	while _gore_seen < gore:
		if shell != null:
			shell.splat(GORE_FROM + _gore_seen)
		_gore_seen += 1


func _drip_spawn(delta: float) -> void:
	if shell == null or bled_out:
		return
	for i in bleeders():
		if b_closed[i] or not b_spurt[i]:
			continue
		if _rng.randf() < drips_per_sec * delta:
			_drips.append([b_at[i] + Vector2(_rng.randf_range(-6.0, 6.0), 0.0), drip_speed0])


func _drip_fall(delta: float) -> void:
	if _drips.is_empty():
		return
	var floor_y := REF.y - 24.0
	var keep: Array = []
	for d in _drips:
		var p: Vector2 = d[0]
		var v: float = float(d[1]) + drip_gravity * delta
		p.y += v * delta
		if p.y >= floor_y:
			if shell != null:
				shell.splat_at(cv(Vector2(p.x, floor_y)), DRIP_FROM + _marks)
			_marks += 1
			continue
		keep.append([p, v])
	_drips = keep


func react() -> void:
	var now := {"plug": plugged(), "sq": _spurt_seq, "lay": roll.laid if roll != null else 0,
		"eat": roll.eaten if roll != null else 0, "tg": tangles(), "marks": _marks}
	if _seen.is_empty():
		_seen = now
		return
	if int(now.plug) > int(_seen.plug):
		audio(plug_cue, -6.0, 0.12)
	if int(now.sq) > int(_seen.sq):
		audio(pack_cue, -18.0, 0.2)
	if int(now.lay) > int(_seen.lay):
		audio(layer_cue, -10.0, 0.15)
	if int(now.eat) > int(_seen.eat):
		audio(eat_cue, -16.0, 0.1)
	if int(now.tg) > int(_seen.tg):
		audio(tangle_cue, -6.0, 0.1)
	if int(now.marks) > int(_seen.marks):
		audio(drip_cue, -24.0, 0.25)
	_seen = now
	# The real patient keeps bleeding while anything is open.
	var b = body()
	if b != null and b.has_method("set_bleeding") and play_state != Play.DONE:
		var site := String(ctx.get("step", {}).get("site", "gunshot"))
		var amt := 0.0
		if stage == Stage.WHACK:
			amt = clampf(0.15 + 0.16 * float(spurting()), 0.0, 1.0)
		elif stage == Stage.WRAP:
			amt = clampf(0.4 * (1.0 - coverage()), 0.0, 1.0)
		b.set_bleeding(site, amt)


# ---------------------------------------------------------------------------- the page

func paint_game(c: CanvasItem) -> void:
	if panel == null or ink == null:
		return
	ink.draw_grime(c, grime_spots)
	if stage == Stage.WRAP and roll != null:
		roll.paint(c, self)
		_paint_wrap_strip(c)
		return
	if stage == Stage.RESULT and roll != null:
		roll.paint(c, self)
		return
	_paint_skin(c)
	_paint_tract(c)
	_paint_bleeders(c)
	_paint_drips(c)
	_paint_ring(c)
	_paint_loss(c)
	if _warm:
		ink.warm(c)
		c.draw_string(InkScript.font_upright(), Vector2(-100, -100), "WHACK! WRAP! TOO SOON! TANGLE! CLEAN SLOPPY MALPRACTICE",
			HORIZONTAL_ALIGNMENT_LEFT, -1.0, 110, ink.ink)


## Bare skin under the tract. It runs the full width of the sheet and fades out top and bottom rather
## than stopping at an edge: a hard-edged rectangle of skin reads as a box drawn on the page.
func _paint_skin(c: CanvasItem) -> void:
	var y0 := 150.0
	var y1 := 470.0
	var bands := 7
	for i in bands:
		var a := float(i) / float(bands)
		var b := float(i + 1) / float(bands)
		# Strongest across the middle, thinning towards both edges, so there is no seam.
		var k: float = 1.0 - absf(((a + b) * 0.5) - 0.5) * 2.0
		c.draw_rect(Rect2(cv(Vector2(0.0, lerpf(y0, y1, a))), Vector2(cl(REF.x), cl((y1 - y0) / float(bands)) + 1.0)),
			Color(ink.skin_human, 0.10 + 0.34 * k))


## The same flesh-red channel DODGE! flew down, seen from above this time.
func _paint_tract(c: CanvasItem) -> void:
	var steps := 48
	var top := PackedVector2Array()
	var bot := PackedVector2Array()
	for i in steps + 1:
		var u := float(i) / float(steps)
		var at := tract_at(u)
		var h := tract_half_at(u)
		top.append(cv(at + Vector2(0.0, -h)))
		bot.append(cv(at + Vector2(0.0, h)))
	var wash := PackedVector2Array()
	for i in steps + 1:
		var u2 := float(i) / float(steps)
		wash.append(cv(tract_at(u2) + Vector2(0.0, -tract_half_at(u2) - 9.0)))
	for i in range(steps, -1, -1):
		var u3 := float(i) / float(steps)
		wash.append(cv(tract_at(u3) + Vector2(0.0, tract_half_at(u3) + 9.0)))
	c.draw_colored_polygon(wash, Color("6e1b1b", 0.28))
	var fill := PackedVector2Array(top)
	for i in range(bot.size() - 1, -1, -1):
		fill.append(bot[i])
	c.draw_colored_polygon(fill, Color("b8443a", 0.85))
	ink.halftone_poly(c, fill, 0.32, Color("5a1414"))
	ink.stroke(c, ink.jittered_cached(top, 6101), ink.ink, 3.0)
	ink.stroke(c, ink.jittered_cached(bot, 6102), ink.ink, 3.0)


## Every bleeder: a spurting one throws a plume, a dormant one is a dark blob, a plugged one is a pale
## disc with a stitched cross and is never coming back (spec 2.2).
func _paint_bleeders(c: CanvasItem) -> void:
	for i in bleeders():
		var at: Vector2 = b_at[i]
		# SPEC 2.1: the bed the slug was lying in is visibly the bigger hole.
		var r: float = (23.0 if b_bed[i] else 12.0)
		if b_closed[i]:
			ink.circle(c, cv(at), cl(r), ink.ink, 2.6, 6200 + i, Color(ink.paper, 0.95))
			var q := r * 0.62
			ink.seg(c, cv(at + Vector2(-q, -q)), cv(at + Vector2(q, q)), Color(ink.ink, 0.8), 2.2, 6300 + i * 2)
			ink.seg(c, cv(at + Vector2(-q, q)), cv(at + Vector2(q, -q)), Color(ink.ink, 0.8), 2.2, 6301 + i * 2)
		elif b_spurt[i]:
			# The plume: how long it has been up is how far it has thrown.
			var k: float = 1.0 - clampf(b_timer[i] / maxf(0.05, spurt_time), 0.0, 1.0)
			var reach: float = r * (2.0 + 1.6 * sin(k * PI))
			ink.circle(c, cv(at), cl(r * 1.15), ink.deep_red, 3.0, 6400 + i, Color("8f2020"))
			for j in 5:
				var ang: float = -PI * 0.5 + (float(j) - 2.0) * 0.26
				var to: Vector2 = at + Vector2(cos(ang), sin(ang)) * reach
				ink.seg(c, cv(at), cv(to), Color("7c1f24", 0.85), 2.4, 6500 + i * 8 + j)
				ink.dot(c, cv(to), cl(3.0 + 1.5 * sin(k * PI)), Color("7c1f24", 0.9))
		else:
			ink.circle(c, cv(at), cl(r * 0.85), Color(ink.ink, 0.7), 2.2, 6600 + i, Color("5a1414", 0.85))
		if b_bed[i]:
			# Clear of the channel itself, with a leader down to it, or the flesh swallows the label.
			var u: float = b_u[i] if i < b_u.size() else 0.0
			var below: float = tract_at(u).y + tract_half_at(u) + 34.0
			ink.seg(c, cv(at + Vector2(0.0, r)), cv(Vector2(at.x, below - 14.0)), Color(ink.label, 0.7), 1.6, 6250 + i)
			ink.text(c, cv(Vector2(at.x, below)), "bullet bed", 14.0, Color(ink.label, 0.95), 1)


func _paint_drips(c: CanvasItem) -> void:
	for d in _drips:
		var p: Vector2 = d[0]
		ink.dot(c, cv(p), cl(3.4), Color("7c1f24", 0.85))
		ink.seg(c, cv(p - Vector2(0.0, 7.0)), cv(p), Color("7c1f24", 0.55), 1.8, 6700)


## The closing ring: it only means anything while Space is down.
func _paint_ring(c: CanvasItem) -> void:
	if ring <= 0.0:
		return
	var at: Vector2 = b_at[ring_on] if ring_on >= 0 and ring_on < b_at.size() else _last_cursor
	var col: Color = ink.good if ring_on >= 0 else Color(ink.ink, 0.5)
	ink.circle(c, cv(at), cl(ring_px), Color(ink.ink, 0.25), 1.6, 6801)
	# The closing arc: a ring that shuts as the hold fills.
	var pts := PackedVector2Array()
	var n: int = maxi(3, int(round(26.0 * ring)))
	for i in n + 1:
		var a: float = -PI * 0.5 + TAU * ring * float(i) / float(n)
		pts.append(cv(at + Vector2(cos(a), sin(a)) * ring_px))
	ink.stroke(c, pts, col, 3.4)


var _last_cursor := Vector2(480.0, 300.0)


## BLOOD LOST along the foot of the page, with the 40% mark on it: the number the grade reads.
func _paint_loss(c: CanvasItem) -> void:
	var y := REF.y - 46.0
	var x0 := 150.0
	var x1 := 810.0
	ink.seg(c, cv(Vector2(x0, y)), cv(Vector2(x1, y)), Color(ink.ink, 0.6), 2.0, 6901)
	var x := lerpf(x0, x1, clampf(loss, 0.0, 1.0))
	c.draw_rect(Rect2(cv(Vector2(x0, y - 7.0)), Vector2(cl(x - x0), cl(14.0))), Color("7c1f24", 0.8))
	var gx := lerpf(x0, x1, gore_from)
	ink.seg(c, cv(Vector2(gx, y - 13.0)), cv(Vector2(gx, y + 13.0)), Color(ink.ink, 0.6), 2.0, 6902)
	var txt := "BLOOD LOST %d%%   ·   plugged %d of %d" % [int(round(loss * 100.0)), plugged(), bleeders()]
	ink.text(c, cv(Vector2((x0 + x1) * 0.5, y - 20.0)), txt, 14.0,
		ink.deep_red if loss >= gore_from else Color(ink.label, 0.9), 1)


## In WRAP!, what is left to do, along the foot of the page.
func _paint_wrap_strip(c: CanvasItem) -> void:
	if roll == null:
		return
	var txt := "covered %d%%   ·   in hand %d   ·   tangles %d" % [
		int(round(coverage() * 100.0)), roll.carry(), tangles()]
	ink.text(c, cv(Vector2(REF.x * 0.5, REF.y - 18.0)), txt, 14.0, Color(ink.label, 0.9), 1)


## Warmup (scripts/warmup.gd): draw BOTH boards and every card once, so the stage change never
## compiles anything mid-step.
func warm_all() -> void:
	_warm = true
	for i in bleeders():
		b_spurt[i] = i == 0
	if bleeders() > 1:
		b_closed[1] = true
	loss = 0.5
	ring = 0.6
	ring_on = 0
	_drips = [[Vector2(300.0, 300.0), 60.0]]
	pack_q = 0.6
	_build_roll()
	score = 61
	_grade = "SLOPPY"
	if shell != null:
		shell.mistake("TANGLE!", shell.area.get_center(), true, 0)
		shell.splat(GORE_FROM)
	if panel != null:
		panel.redraw()
	# Draw the WRAP! board too, then put it back the way it was.
	var keep := stage
	stage = Stage.WRAP
	if panel != null:
		panel.redraw()
	stage = keep


# ---------------------------------------------------------------------------- net

## What an onlooker needs. The tract and the bleeder layout come from the seed on every machine; the
## roll's board is rebuilt from the SNAPPED `pack_q` the moment the stage flips. NOTHING THAT CREEPS
## IS SNAPPED (the lab round-trips this every frame).
func net_pack() -> Dictionary:
	var closed := PackedInt32Array()
	var spurt := PackedInt32Array()
	var timer := PackedFloat32Array()
	for i in bleeders():
		closed.append(1 if b_closed[i] else 0)
		spurt.append(1 if b_spurt[i] else 0)
		timer.append(b_timer[i])
	# KEYS STARTING "b" ARE THE BLEEDERS. Do not use short generic names here: ArcadeGame.net_state()
	# writes its own "cl" (card_left), "cw", "ps", "pt", "fz", "q" and "p" over whatever net_pack()
	# returned, so a game key that collides is silently replaced and the state never arrives.
	var s := {"st": stage, "bc": closed, "bs": spurt, "bm": timer, "rg": ring, "ro": ring_on,
		"ls": loss, "go": gore, "be": beat, "bo": bled_out, "pq": pack_q, "sq": _spurt_seq,
		"sc": score, "gr": _grade}
	if roll != null:
		s["rl"] = roll.pack()
	return s


func net_apply(s: Dictionary) -> void:
	var was := stage
	stage = int(s.get("st", stage))
	var bc = s.get("bc", null)
	var bs = s.get("bs", null)
	var bm = s.get("bm", null)
	if bc is PackedInt32Array and bs is PackedInt32Array and bm is PackedFloat32Array:
		for i in mini(bleeders(), bc.size()):
			b_closed[i] = int(bc[i]) != 0
			b_spurt[i] = int(bs[i]) != 0
			b_timer[i] = float(bm[i])
	ring = float(s.get("rg", ring))
	ring_on = int(s.get("ro", ring_on))
	loss = float(s.get("ls", loss))
	gore = int(s.get("go", gore))
	beat = float(s.get("be", beat))
	bled_out = bool(s.get("bo", bled_out))
	pack_q = float(s.get("pq", pack_q))
	_spurt_seq = int(s.get("sq", _spurt_seq))
	score = int(s.get("sc", score))
	_grade = String(s.get("gr", _grade))
	# The board is built from the snapped pack quality, so an onlooker lays out exactly the same one.
	if stage != Stage.WHACK and roll == null:
		_build_roll()
	if was != stage:
		_update_progress()
	if roll != null and s.has("rl"):
		roll.unpack(s.get("rl", {}))
		_update_progress()


# ---------------------------------------------------------------------------- bot

## WHACK!: put the cursor on the nearest spurting bleeder and hold Space until the ring shuts. A good
## hand goes straight to it; a bad one aims off and lets go early now and then. WRAP!: ask the roll
## which way to turn and hold that key. Cards get a press after a reaction delay.
func bot_input(t: float, skill: float) -> Dictionary:
	var dt: float = clampf(t - _bt, 0.0, 0.1)
	_bt = t
	skill = clampf(skill, 0.0, 1.0)
	var cur := metres_of_ref(_b_aim)
	var none := {"cursor": cur, "buttons": 0}
	if stamp_waiting() and not frozen:
		if card_left > 0.0:
			_b_gate = -1.0
			return none
		if _b_gate < 0.0:
			_b_gate = lerpf(0.6, 0.18, skill)
		_b_gate -= dt
		if _b_gate <= 0.0:
			_b_gate = -1.0
			_b_up = true
			return {"cursor": cur, "buttons": BUTTON_ACTION}
		return none
	if not armed():
		return none
	if _b_up:
		_b_up = false
		return none
	match stage:
		Stage.WHACK:
			return _bot_whack(skill)
		Stage.WRAP:
			return _bot_wrap(skill)
		Stage.RESULT:
			return {"cursor": cur, "buttons": BUTTON_ACTION}
	return none


func _bot_whack(skill: float) -> Dictionary:
	var target := -1
	var best := INF
	for i in bleeders():
		if b_closed[i] or not b_spurt[i]:
			continue
		var d: float = _b_aim.distance_to(b_at[i])
		if d < best:
			best = d
			target = i
	if target < 0:
		# Nothing up: wait over the next one due, so the hand is already there.
		var soon := -1
		var soonest := INF
		for i in bleeders():
			if b_closed[i]:
				continue
			if b_timer[i] < soonest:
				soonest = b_timer[i]
				soon = i
		if soon >= 0:
			_b_aim = b_at[soon]
		return {"cursor": metres_of_ref(_b_aim), "buttons": 0}
	# A sloppy hand sits off to one side of it, sometimes far enough to miss entirely.
	var err: float = (1.0 - skill) * hit_radius(target) * 1.35
	var off := Vector2(cos(float(target) * 2.3 + _bt), sin(float(target) * 1.7 + _bt * 0.6)) * err
	_b_aim = b_at[target] + off
	return {"cursor": metres_of_ref(_b_aim), "buttons": BUTTON_ACTION}


func _bot_wrap(skill: float) -> Dictionary:
	if roll == null:
		return {"cursor": metres_of_ref(_b_aim), "buttons": 0}
	var d: Vector2i = roll.route()
	# A sloppy hand sometimes keeps going instead of taking the turn, which is how it tangles.
	if skill < 0.99 and fposmod(_bt * 7.3 + float(roll.tangles), 1.0) > lerpf(0.55, 1.0, skill):
		d = roll.dir
	var bit := 0
	if d == Vector2i(0, -1):
		bit = BUTTON_UP
	elif d == Vector2i(0, 1):
		bit = BUTTON_DOWN
	elif d == Vector2i(-1, 0):
		bit = BUTTON_LEFT
	elif d == Vector2i(1, 0):
		bit = BUTTON_RIGHT
	return {"cursor": metres_of_ref(_b_aim), "buttons": bit}


# ---------------------------------------------------------------------------- self-test

## Headless: `godot --headless --path . --fixed-fps 60 tools/minigame_lab.tscn -- --selftest=gauze:arcade`
static func self_test() -> Array:
	var script: GDScript = load("res://scripts/surgery/arcade/pack_wrap_arcade.gd")
	var out := []
	var ok := true
	for cond: Dictionary in [{"tears": [], "sed": 1.0}, {"tears": [0.22, 0.51, 0.77], "sed": 0.4}]:
		for pid: String in ["bob", "seal"]:
			for skill: float in [1.0, 0.5, 0.0]:
				var g = script.new()
				var tally := {"n": 0, "v": 0.0, "done": false, "q": 0.0, "m": ""}
				g.botched.connect(func(a, _r): tally.n += 1; tally.v += a)
				g.finished.connect(func(r): tally.done = true; tally.q = float(r.get("pack_quality", 0.0)); tally.m = String(r.get("dress_marks", "")))
				g.setup(_case(pid, cond.tears, float(cond.sed)))
				var t: float = run_bot(g, skill, float(cond.sed), hash(pid) + int(skill * 100), 240.0)
				print("[pack-wrap self-test] %-4s skill=%.1f tears=%d  %s  bleeders=%d plugged=%d loss=%.2f pq=%.2f  cover=%.2f tangles=%d  score=%3d %-11s  time=%5.1fs vitals=%5.1f" % [
					pid, skill, int((cond.tears as Array).size()), "DONE" if tally.done else "UNFINISHED",
					g.bleeders(), g.plugged(), g.loss, g.pack_q, g.coverage(), g.tangles(), g.score, g._grade, t, tally.v])
				out.append({"patient": pid, "skill": skill, "done": tally.done, "time": t, "score": g.score,
					"bleeders": g.bleeders(), "tangles": g.tangles()})
				if not tally.done:
					print("[pack-wrap self-test] MISS: every hand has to be able to finish")
					ok = false
				else:
					if tally.m.length() != g.roll.wound.size():
						print("[pack-wrap self-test] MISS: dress_marks is one character per wound cell")
						ok = false
					if absf(float(tally.q) - g.pack_q) > 0.011:
						print("[pack-wrap self-test] MISS: the result's pack_quality is not the game's")
						ok = false
					if absf(tally.v - 5.0 * float(g.tangles())) > 0.01:
						print("[pack-wrap self-test] MISS: a tangle costs 5 vitals and nothing else bills")
						ok = false
				# SPEC 2.1: 1 + one per tear + 0 or 1, clamped 3-7.
				var want_lo: int = clampi(1 + int((cond.tears as Array).size()), 3, 7)
				var want_hi: int = clampi(2 + int((cond.tears as Array).size()), 3, 7)
				if g.bleeders() < want_lo or g.bleeders() > want_hi or g.bleeders() < 3 or g.bleeders() > 7:
					print("[pack-wrap self-test] MISS: %d tears gave %d bleeders (wanted %d-%d)" % [
						(cond.tears as Array).size(), g.bleeders(), want_lo, want_hi])
					ok = false
				g.free()
	# The spurt cycle: never more than two at once, and a plugged bleeder never comes back.
	var cyc := _cycle_check(script)
	print("[pack-wrap self-test] spurt cycle: most up at once %d (limit 2), a spurt lasted %.2f s (want 2.2), cools scheduled %.2f-%.2f s (want 0.7-2.9), longest actual wait for a turn %.2f s, a plugged one re-opened %d times" % [
		cyc.most, cyc.spurt, cyc.cool_lo, cyc.cool_hi, cyc.waited, cyc.reopened])
	if cyc.most > 2 or absf(cyc.spurt - 2.2) > 0.1 or cyc.cool_lo < 0.69 or cyc.cool_hi > 2.91 \
			or cyc.waited < cyc.cool_hi - 0.01 or cyc.reopened > 0:
		print("[pack-wrap self-test] MISS: the spurt cycle")
		ok = false
	# SPEC 2.3: at 100% he is gone, after a beat, however many are still open.
	var bo := _bleedout_check(script)
	print("[pack-wrap self-test] bleeding out: the stage ran on for %.2f s after 100%% (want 1.1), then handed over with %d of %d plugged and pack quality %.2f" % [
		bo.beat, bo.plugged, bo.total, bo.pq])
	if absf(bo.beat - 1.1) > 0.06 or bo.pq >= 1.0 or absf(bo.pq - float(bo.plugged) / float(bo.total)) > 0.011:
		print("[pack-wrap self-test] MISS: bleeding out")
		ok = false
	# The meter moves only while something is spurting, and the hold is one clean commit.
	var bl := _blood_check(script)
	print("[pack-wrap self-test] blood: with everything shut the meter moved %.4f in 3 s; with one open it moved %.3f (want ~%.3f); holding %.2f s plugged %d, letting go at 80%% plugged %d" % [
		bl.shut, bl.open1, bl.want1, bl.held, bl.plugged, bl.early])
	if bl.shut > 0.0001 or absf(bl.open1 - bl.want1) > 0.01 or bl.plugged != 1 or bl.early != 0:
		print("[pack-wrap self-test] MISS: blood loss or the pack hold")
		ok = false
	# WRAP!: a tangle costs vitals and momentum, never what is in hand or already laid.
	var tg := _tangle_check(script)
	print("[pack-wrap self-test] tangle: carried %d before and %d after, layers %d before and %d after, back on the left edge %s" % [
		tg.carry0, tg.carry1, tg.laid0, tg.laid1, "yes" if tg.left else "NO"])
	if tg.carry0 != tg.carry1 or tg.laid0 != tg.laid1 or not tg.left:
		print("[pack-wrap self-test] MISS: a tangle must cost vitals and momentum, not progress")
		ok = false
	# The grade bands (spec 4).
	var gr := _grade_check(script)
	print("[pack-wrap self-test] grades: perfect %d %s, half-packed full cover %d %s, five tangles %d %s" % [
		gr.best, gr.best_w, gr.mid, gr.mid_w, gr.bad, gr.bad_w])
	if gr.best_w != "CLEAN" or gr.best != 90 or gr.mid_w != "SLOPPY" or gr.bad_w != "MALPRACTICE":
		print("[pack-wrap self-test] MISS: the grade bands")
		ok = false
	# An onlooker sees what the operator sees.
	var net := _net_check(script)
	print("[pack-wrap self-test] spectator: plugged %d vs %d, loss %.3f vs %.3f, coverage %.3f vs %.3f, page splats %d vs %d" % net)
	if net[0] != net[1] or absf(net[2] - net[3]) > 0.02 or absf(net[4] - net[5]) > 0.02 or net[6] != net[7]:
		print("[pack-wrap self-test] MISS: a spectator does not see what the operator sees")
		ok = false
	print("[pack-wrap self-test] %s" % ("PASS" if ok else "FAIL"))
	return out


static func _case(pid: String, tears: Array, sed: float) -> Dictionary:
	return {"patient_id": pid, "patient": Procedures.patient(pid), "ailment_id": "gunshot",
		"step": Procedures.step("gunshot", 2), "variant": "pack", "shift": 1,
		"difficulty": Procedures.difficulty(1),
		"flags": {"sedation": sed, "bullet_removed": true, "tears": tears},
		"seed": hash("packwrap" + pid), "body": null, "operator": true, "operating": true}


static func _armed(g) -> void:
	# Take the opening card down so the game is actually running.
	var dt := 1.0 / 60.0
	for i in 30:
		g.handle_cursor(Vector2.ZERO, 0, dt)
		g.tick(dt)
	g.handle_cursor(Vector2.ZERO, BUTTON_ACTION, dt)
	g.tick(dt)
	g.handle_cursor(Vector2.ZERO, 0, dt)
	g.tick(dt)


static func _cycle_check(script: GDScript) -> Dictionary:
	var r := {"most": 0, "spurt": 0.0, "cool_lo": INF, "cool_hi": 0.0, "reopened": 0, "waited": 0.0}
	var g = script.new()
	g.setup(_case("bob", [0.2, 0.4, 0.6, 0.8], 1.0))
	_armed(g)
	var dt := 1.0 / 60.0
	# Freeze the blood so the run is long enough to watch several cycles.
	g.blood_rate = 0.0
	var up := {}
	var down := {}
	g.b_closed[0] = true
	for i in 3600:
		var before: Array[bool] = g.b_spurt.duplicate()
		g.handle_cursor(Vector2.ZERO, 0, dt)
		g.tick(dt)
		if g.stage != Stage.WHACK:
			break
		if g.b_closed[0] and g.b_spurt[0]:
			r.reopened += 1
		r.most = maxi(r.most, g.spurting())
		for b in g.bleeders():
			if g.b_spurt[b] and not before[b]:
				up[b] = float(i) * dt
				if down.has(b):
					r.waited = maxf(r.waited, float(i) * dt - float(down[b]))
			elif not g.b_spurt[b] and before[b]:
				down[b] = float(i) * dt
				# The COOL-DOWN AS SCHEDULED. The observed gap between spurts is longer whenever a
				# bleeder's turn comes round while two others are already up: it waits at zero until
				# there is room, which is the rule, not a miss.
				r.cool_lo = minf(r.cool_lo, g.b_timer[b])
				r.cool_hi = maxf(r.cool_hi, g.b_timer[b])
				if up.has(b):
					r.spurt = maxf(r.spurt, float(i) * dt - float(up[b]))
	if r.cool_lo == INF:
		r.cool_lo = 0.7
	g.free()
	return r


## Let him bleed out with bleeders still open: the stage must end anyway, a beat later, and hand over
## a pack quality that is only what was actually plugged.
static func _bleedout_check(script: GDScript) -> Dictionary:
	var dt := 1.0 / 60.0
	var g = script.new()
	g.setup(_case("bob", [0.3, 0.6], 1.0))
	_armed(g)
	g.loss = 0.999
	g.b_spurt[0] = true
	g.b_timer[0] = 999.0
	var beat := 0.0
	var guard := 0
	while g.stage == Stage.WHACK and guard < 600:
		guard += 1
		g.handle_cursor(Vector2.ZERO, 0, dt)
		g.tick(dt)
		if g.bled_out:
			beat += dt
	var r := {"beat": beat, "plugged": g.plugged(), "total": g.bleeders(), "pq": g.pack_q}
	g.free()
	return r


static func _blood_check(script: GDScript) -> Dictionary:
	var dt := 1.0 / 60.0
	var r := {}
	# Everything shut: the meter must HOLD, not merely slow.
	var g = script.new()
	g.setup(_case("bob", [], 1.0))
	_armed(g)
	for i in g.bleeders():
		g.b_closed[i] = true
		g.b_spurt[i] = false
	var l0: float = g.loss
	for i in 180:
		g.handle_cursor(Vector2.ZERO, 0, dt)
		g.tick(dt)
	r.shut = g.loss - l0
	g.free()
	# Exactly one open and spurting: the spec's rate.
	var g2 = script.new()
	g2.setup(_case("bob", [], 1.0))
	_armed(g2)
	for i in g2.bleeders():
		g2.b_closed[i] = i > 0
		g2.b_spurt[i] = i == 0
	g2.b_timer[0] = 999.0
	var l2: float = g2.loss
	for i in 120:
		g2.handle_cursor(Vector2.ZERO, 0, dt)
		g2.tick(dt)
	r.open1 = g2.loss - l2
	r.want1 = (0.030 + 0.026) * 2.0
	g2.free()
	# The hold: 0.4 s on a spurting bleeder plugs it; letting go at 80% plugs nothing.
	var g3 = script.new()
	g3.setup(_case("bob", [], 1.0))
	_armed(g3)
	g3.b_spurt[0] = true
	g3.b_timer[0] = 999.0
	var at: Vector2 = g3.metres_of_ref(g3.b_at[0])
	var held := 0.0
	while held < 0.5 and g3.plugged() == 0:
		held += dt
		g3.handle_cursor(at, BUTTON_ACTION, dt)
		g3.tick(dt)
	r.held = held
	r.plugged = g3.plugged()
	g3.free()
	var g4 = script.new()
	g4.setup(_case("bob", [], 1.0))
	_armed(g4)
	g4.b_spurt[0] = true
	g4.b_timer[0] = 999.0
	var at4: Vector2 = g4.metres_of_ref(g4.b_at[0])
	for i in int(0.8 * 0.4 * 60.0):
		g4.handle_cursor(at4, BUTTON_ACTION, dt)
		g4.tick(dt)
	for i in 30:
		g4.handle_cursor(at4, 0, dt)
		g4.tick(dt)
	r.early = g4.plugged()
	g4.free()
	return r


static func _tangle_check(script: GDScript) -> Dictionary:
	var g = script.new()
	g.setup(_case("bob", [], 1.0))
	_armed(g)
	g.pack_q = 0.5
	g.stage = Stage.WRAP
	g._build_roll()
	var roll = g.roll
	# Three cells of gauze in hand and a couple of layers down, then drive into the wall.
	for i in 3:
		roll.body.append(roll.body[0])
	roll.layers[0] = 1
	roll.layers[1] = 1
	var r := {"carry0": roll.carry(), "laid0": 0}
	for w in roll.layers:
		r.laid0 += int(w)
	roll.body[0] = Vector2i(roll.cols - 1, 3)
	roll.dir = Vector2i(1, 0)
	roll.want_dir = Vector2i(1, 0)
	var ev: Array = roll.advance(roll.step_time * 1.1)
	var tangled := false
	for e in ev:
		if String(e.get("e", "")) == "tangle":
			tangled = true
	r.carry1 = roll.carry()
	r.laid1 = 0
	for w in roll.layers:
		r.laid1 += int(w)
	r.left = tangled and roll.body[0].x == 0
	g.free()
	return r


static func _grade_check(script: GDScript) -> Dictionary:
	var r := {}
	var g = script.new()
	g.setup(_case("bob", [], 1.0))
	g.pack_q = 1.0
	g.stage = Stage.WRAP
	g._build_roll()
	# Perfect: everything plugged, everything covered, nothing tangled.
	for w in g.roll.layers.size():
		g.roll.layers[w] = g.roll.need(w)
	r.best = g.grade_score()
	r.best_w = g.grade_word()
	g.pack_q = 0.5
	r.mid = g.grade_score()
	r.mid_w = g.grade_word()
	g.roll.tangles = 5
	r.bad = g.grade_score()
	r.bad_w = g.grade_word()
	g.free()
	return r


## The operator plays; the onlooker only ever gets net_state and must land on the same page.
static func _net_check(script: GDScript) -> Array:
	var op = script.new()
	var spec = script.new()
	op.setup(_case("bob", [0.3, 0.6], 1.0))
	var sctx := _case("bob", [0.3, 0.6], 1.0)
	sctx["operator"] = false
	spec.setup(sctx)
	var dt := 1.0 / 60.0
	var t := 0.0
	var n := 0
	while t < 200.0 and not op.done:
		t += dt
		var inp: Dictionary = op.bot_input(t, 0.75)
		op.handle_cursor(inp.get("cursor", Vector2.ZERO), int(inp.get("buttons", 0)), dt)
		op.tick(dt)
		spec.tick(dt)
		n += 1
		if n % 3 == 0:
			spec.apply_net_state(op.net_state())
	spec.apply_net_state(op.net_state())
	spec.tick(dt)
	# The page's own splatter is a replicated COUNT, so it must match exactly. The drips (and the
	# marks they leave) are deliberately local weather and are not compared.
	var r := [op.plugged(), spec.plugged(), op.loss, spec.loss, op.coverage(), spec.coverage(),
		op._gore_seen, spec._gore_seen]
	op.free()
	spec.free()
	return r
