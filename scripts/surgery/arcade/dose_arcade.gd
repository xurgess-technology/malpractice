extends "res://scripts/surgery/arcade/arcade_game.gd"
## ARCADE SURGERY (docs/ARCADE_SURGERY.md) 5.1 -- DOSE! Step "sedate": put the needle in the vein
## and push until the patient goes under. The arcade rebuild of scripts/surgery/games/anesthetic.gd,
## played on the raised panel.
##
## Rhyme: the old golf-game power meter. Two presses, and that is the whole step.
##
## What you do
##   STICK. A diagram of the forearm (the seal's flipper is fatter and its vein is thinner under all
##   that blubber) with the vein running down it at a seeded X. The needle marker sweeps side to
##   side over the arm on its own. One press stops it. On the vein, blood flashes back into the hub
##   and you are in. Off it, you have put a hole in the arm: a bead of blood, the patient jerks, and
##   the vein bruises and NARROWS, so every miss makes the next press harder.
##   PUSH. Hold to push the plunger, let go to stop. Let go for long enough and the needle comes out
##   and that is the dose you gave.
##
## THE DOSE IS NEVER A NUMBER AND THERE IS NO GREEN ZONE -- the best idea in the legacy game, kept.
## The barrel shows you how far the plunger has gone and nothing else; how much this patient needs
## is a thing you read off the PATIENT. The little figure on the panel twitches, twitches less as
## the drug goes in, lies still once it is enough, and goes slack and blue-grey if you keep going,
## with the alarm chirping. The real body does the same through the existing calls. A big patient
## needs a lot more than a small one and nothing on the panel will tell you how much.
##
## Result {"sedation": s}, exactly as the legacy game emits it: the framework's stir system keys off
## sedation < 0.75 and SQUEEZE! reads it for pulse noise, so the shape may not drift.

enum Stage { STICK, DOSE, DONE }

## Which way the vein hop rolls. 0 nothing yet, 1 flickering, 2 moved.
enum Hop { PENDING, FLICKER, DONE, OFF }

# -- the limb ----------------------------------------------------------------------------------
## The arm on the diagram: how wide it can get, and the band of panel it lies in.
@export_range(10.0, 50.0, 0.5) var limb_half_max := 30.0
@export_range(-40.0, 0.0, 0.5) var limb_top := -20.0
@export_range(0.0, 40.0, 0.5) var limb_bot := 12.0
## How much narrower the limb is at the wrist end than at the elbow end.
@export_range(0.3, 1.0, 0.01) var limb_taper := 0.78

# -- the vein ----------------------------------------------------------------------------------
## The vein a person has, across the arm, in mm. Divided by sqrt(difficulty).
@export_range(2.0, 40.0, 0.5) var vein_mm := 14.0
## What you get through blubber instead: the seal's flipper vein is thinner than Bob's.
@export_range(2.0, 40.0, 0.5) var vein_mm_blubber := 9.0
## The vein sits this far either side of the middle of the arm, as a share of its half-width.
@export_range(0.0, 0.95, 0.01) var vein_spread := 0.58
## A miss bruises the vein and it narrows by this much, down to this share of what it was.
@export_range(0.0, 0.6, 0.01) var bruise_narrow := 0.15
@export_range(0.2, 1.0, 0.01) var bruise_floor := 0.5

# -- the sweep ---------------------------------------------------------------------------------
@export_range(10.0, 300.0, 1.0) var sweep_speed := 90.0     ## mm/s before sqrt(difficulty)
@export_range(10.0, 58.0, 1.0) var sweep_half := 46.0       ## how far out the needle marker runs
@export_range(-40.0, 0.0, 0.5) var track_y := -31.0         ## the height the marker rides at
@export_range(0.0, 10.0, 0.5) var miss_botch := 2.0
@export_range(0.0, 3.0, 0.05) var miss_cd := 0.5
## Blood flashing back into the hub: the beat between the stick and the push. The plunger is locked
## until it clears, which is also what keeps the step from being over in seven seconds.
@export_range(0.0, 2.0, 0.05) var flash_time := 0.45

# -- the hop (shift 3 and up) -------------------------------------------------------------------
@export_range(1, 9) var hop_from_shift := 3
@export_range(0.5, 10.0, 0.1) var hop_at_lo := 1.2          ## seconds of stage A before it hops
@export_range(0.5, 12.0, 0.1) var hop_at_hi := 2.6
@export_range(0.05, 1.5, 0.05) var hop_flicker := 0.3       ## the telegraph before it moves
@export_range(1.0, 40.0, 0.5) var hop_min_mm := 14.0        ## how far it must move to be worth it

# -- the dose (the legacy maths, unchanged: every later step is priced off it) -------------------
@export_range(0.005, 0.2, 0.001) var ml_per_kg := 0.05
@export_range(0.1, 5.0, 0.05) var fill_rate := 0.8          ## ml per second on the plunger
@export_range(1.0, 4.0, 0.05) var capacity_k := 1.9         ## barrel = this many doses
@export_range(0.0, 1.0, 0.01) var min_dose_k := 0.2         ## less than this given and it is nothing
@export_range(0.1, 5.0, 0.05) var withdraw_time := 1.2
@export_range(0.0, 1.5, 0.01) var good_lo := 0.8
@export_range(0.5, 3.0, 0.01) var good_hi := 1.25
@export_range(0.0, 20.0, 0.5) var overdose_botch := 4.0
@export_range(0.0, 100.0, 1.0) var overdose_per_excess := 30.0

# -- the patient icon ---------------------------------------------------------------------------
## Still from here up: the point the twitching has faded out.
@export_range(0.1, 1.5, 0.01) var still_from := 0.85
## Past here the figure goes slack and blue-grey and the alarm chirps.
@export_range(0.5, 2.5, 0.01) var alarm_from := 1.15
@export_range(0.0, 8.0, 0.1) var twitch_mm := 1.9
@export var icon_at := Vector2(43.0, 25.0)
@export_range(0.3, 3.0, 0.05) var icon_scale := 1.0

# -- the barrel ---------------------------------------------------------------------------------
@export_range(-58.0, 0.0, 0.5) var meter_left := -46.0
@export_range(0.0, 58.0, 0.5) var meter_right := 22.0
@export_range(0.0, 39.0, 0.5) var meter_y := 27.0
@export_range(1.0, 20.0, 0.5) var meter_half_h := 7.0

# -- audio --------------------------------------------------------------------------------------
@export var tick_cue := "surgery_needle"
@export var miss_cue := "surgery_needle"
@export var push_cue := "surgery_inject"
@export var draw_cue := "surgery_draw"
@export var alarm_cue := "surgery_beep_crit"
@export_range(0.05, 2.0, 0.05) var push_every := 0.55
@export_range(0.05, 2.0, 0.05) var alarm_every := 0.45

# -- the bot ------------------------------------------------------------------------------------
## How far ahead of the vein the worst hand jabs, and where each hand stops pushing. These set what
## the lab measures and nothing a player does touches them.
@export_range(0.0, 60.0, 0.5) var bot_jab_mm := 26.0
@export_range(0.5, 3.0, 0.01) var bot_good_stop := 1.02
@export_range(0.5, 3.0, 0.01) var bot_sloppy_stop := 1.62

# ---- replicated state ----
var stage: int = Stage.STICK
var sweep_x := 0.0                ## mm, where the needle marker is
var sweep_dir := 1.0
var vein_x := 0.0                 ## mm, the middle of the vein
var vein_half := 7.0              ## mm, half the vein's width RIGHT NOW (bruising narrows it)
var injected := 0.0               ## ml in the patient
var pressing := false
var inserted := false
var flash := 0.0                  ## seconds of flash-back left before the plunger frees up
var withdraw := 0.0               ## seconds since letting go with the needle in
var cooldown := 0.0               ## seconds before another press counts, after a miss
var misses := 0
var beads: Array = []             ## x positions (mm) where the needle went through skin
var hop_state: int = Hop.OFF
var hop_left := 0.0
var sedation := 1.0

# ---- derived from the patient and the seed ----
var target_ml := 4.0
var capacity_ml := 7.6
var vein_half_full := 7.0         ## what the vein was before anybody bruised it
var limb_half := 26.0
var hop_x := 0.0

# ---- local ----
var _t := 0.0
var _rng := RandomNumberGenerator.new()
var _vrng := RandomNumberGenerator.new()
var _seen := {}
var _push_snd := 0.0
var _alarm_t := 0.0
var _stir_t := 0.7
var _shown_plunger := 0.0
var _miss_flash := 0.0

# ---- bot ----
var _bt := 0.0
var _b_seq := 0
var _b_err_for := -1
var _b_jab := 0.0
var _b_prev := 0.0
var _b_started := false


# ---------------------------------------------------------------------------- setup

func card_word_for_start() -> String:
	return "DOSE!"


func build_game() -> void:
	_rng.seed = int(ctx.get("seed", 1)) ^ 0xd05e
	_vrng.seed = int(ctx.get("seed", 1)) ^ 0x115e
	var weight := float(ctx.get("patient", {}).get("weight_kg", 80.0))
	# The dose maths is the legacy game's, to the decimal: every later step is priced off it.
	target_ml = clampf(weight * ml_per_kg, 1.0, 9.0)
	capacity_ml = target_ml * capacity_k
	var radius := float(ctx.get("patient", {}).get("limb_radius_m", 0.06))
	limb_half = clampf(radius * 1000.0 * 0.42, 14.0, limb_half_max)
	var wide := String(ctx.get("patient_id", "bob")) == "seal"
	vein_half_full = (vein_mm_blubber if wide else vein_mm) * 0.5 / sqrt(diff)
	vein_half = vein_half_full
	var reach: float = limb_half * vein_spread
	vein_x = _rng.randf_range(-reach, reach)
	# The marker starts at the far edge, so there is always a run-up to read rather than the vein
	# landing under the needle on the first frame.
	sweep_x = -signf(vein_x) * sweep_half if absf(vein_x) > 0.5 else -sweep_half
	sweep_dir = 1.0 if sweep_x < 0.0 else -1.0
	# Shift 3 and up: the vein hops once, mid-sweep, with a flicker first so it is readable.
	if int(ctx.get("shift", 1)) >= hop_from_shift:
		hop_state = Hop.PENDING
		hop_left = _rng.randf_range(hop_at_lo, hop_at_hi)
		for _i in 8:
			hop_x = _rng.randf_range(-reach, reach)
			if absf(hop_x - vein_x) >= hop_min_mm:
				break
	_update_progress()


func ratio() -> float:
	return injected / maxf(target_ml, 0.01)


func sweep_speed_now() -> float:
	return sweep_speed * sqrt(diff)


# ---------------------------------------------------------------------------- playing

func keys() -> Array:
	match stage:
		Stage.STICK:
			return [["LMB / Space", "stick the vein"]]
		Stage.DOSE:
			return [["Hold LMB", "push the plunger"], ["Let go", "withdraw"]]
	return []


func hint() -> String:
	var base := super.hint()
	if base != "":
		return base
	match stage:
		Stage.STICK:
			if cooldown > 0.0:
				return "You put that one through the skin. Wait for the marker to come round."
			if misses > 0:
				return "The vein is bruised and narrower now. Time it."
			return "Stop the needle on the vein."
		Stage.DOSE:
			if flash > 0.0:
				return "In. Wait for the flash-back."
			if not pressing:
				return "Letting go withdraws the needle. Hold again to give more."
			if ratio() > alarm_from:
				return "That is too much. LET GO."
			if ratio() >= still_from:
				return "They have stopped moving. That is the dose."
			return "Watch the patient, not the barrel."
	if sedation < 0.75:
		return "Underdosed: expect them to stir."
	return "Overdosed." if sedation > good_hi else "Under."


## The operator's two presses, and nothing else: the marker sweeps on its own.
func play(_p: Vector2, buttons: int, edges: int, _delta: float) -> void:
	var hit: bool = (buttons & (BUTTON_PRIMARY | BUTTON_ACTION)) != 0
	var went_down: bool = (edges & (BUTTON_PRIMARY | BUTTON_ACTION)) != 0
	match stage:
		Stage.STICK:
			pressing = false
			if went_down and cooldown <= 0.0:
				_stick()
		Stage.DOSE:
			pressing = hit
			if went_down:
				withdraw = 0.0


func _stick() -> void:
	if absf(sweep_x - vein_x) <= vein_half:
		stage = Stage.DOSE
		inserted = true
		flash = flash_time
		withdraw = 0.0
		show_card("PUSH!")   # react() makes the noise, on every machine at once
		return
	# Through the skin and into nothing. The vein bruises where the needle went past it and the
	# next press has less to aim at.
	misses += 1
	cooldown = miss_cd
	_miss_flash = 0.45
	beads.append(snappedf(sweep_x, 0.1))
	if beads.size() > 6:
		beads.pop_front()
	vein_half = maxf(vein_half_full * bruise_floor, vein_half * (1.0 - bruise_narrow))
	shake(0.5)
	cost(miss_botch, "Missed the vein")


func advance(delta: float) -> void:
	cooldown = maxf(0.0, cooldown - delta)
	match stage:
		Stage.STICK:
			_sweep(delta)
			_hop(delta)
		Stage.DOSE:
			flash = maxf(0.0, flash - delta)
			if pressing and flash <= 0.0:
				injected = minf(capacity_ml, injected + fill_rate * delta)
				withdraw = 0.0
			elif not pressing:
				withdraw += delta
				if withdraw >= withdraw_time:
					if injected >= target_ml * min_dose_k:
						_complete()
					else:
						# Nothing worth calling a dose: the needle comes out and you start again.
						inserted = false
						withdraw = 0.0
						stage = Stage.STICK
						show_card("DOSE!")
	_update_progress()


func _sweep(delta: float) -> void:
	sweep_x += sweep_dir * sweep_speed_now() * delta
	if sweep_x > sweep_half:
		sweep_x = sweep_half - (sweep_x - sweep_half)
		sweep_dir = -1.0
	elif sweep_x < -sweep_half:
		sweep_x = -sweep_half + (-sweep_half - sweep_x)
		sweep_dir = 1.0


func _hop(delta: float) -> void:
	match hop_state:
		Hop.PENDING:
			hop_left -= delta
			if hop_left <= 0.0:
				hop_state = Hop.FLICKER
				hop_left = hop_flicker
		Hop.FLICKER:
			hop_left -= delta
			if hop_left <= 0.0:
				hop_state = Hop.DONE
				vein_x = hop_x
				audio(tick_cue, -14.0, 0.2)


func _complete() -> void:
	stage = Stage.DONE
	pressing = false
	inserted = false
	# The legacy result, to the letter. 0.8 to 1.25 of what they needed reads as a clean 1.0-ish;
	# anything else carries its own error forward for every later step to trip over.
	var r := ratio()
	sedation = r
	if r >= good_lo and r <= good_hi:
		sedation = 1.0 + (r - 1.0) * 0.35
	sedation = clampf(sedation, 0.0, 2.0)
	if sedation > 1.25:
		cost(overdose_botch + (sedation - 1.25) * overdose_per_excess,
			"Overdose: the patient's blood pressure crashed")
	var b = body()
	if b != null and b.has_method("set_sedation"):
		b.set_sedation(clampf(sedation, 0.0, 1.0))
	quality = snappedf(clampf(1.0 - 0.12 * float(misses) - absf(sedation - 1.0) * 0.8, 0.05, 1.0), 0.01)
	arcade_finish({"sedation": snappedf(sedation, 0.01)})


func _update_progress() -> void:
	if stage == Stage.DONE:
		progress = 1.0
		return
	var p := 0.06 if stage == Stage.STICK else 0.1 + 0.8 * clampf(ratio(), 0.0, 1.0) \
		+ 0.1 * clampf(withdraw / withdraw_time, 0.0, 1.0)
	progress = clampf(p, 0.0, 0.98)


func animate(delta: float) -> void:
	_t += delta
	_miss_flash = maxf(0.0, _miss_flash - delta)
	_shown_plunger = move_toward(_shown_plunger, injected / maxf(0.01, capacity_ml), delta * 1.6)
	# react() has no delta of its own, so its three repeating cues are wound down here.
	_push_snd -= delta
	_alarm_t -= delta
	_stir_t -= delta
	# Spectators only get the marker 20 times a second, and it is the one thing that has to look
	# smooth, so they dead-reckon between updates and the next blob corrects them.
	if armed() and stage == Stage.STICK and not bool(ctx.get("operator", false)):
		_sweep(delta)


## This step never gets jolts: the framework excludes it, because the patient is not sedated yet and
## a stir is the very thing this step is here to stop. Nothing to do, and nothing should be added --
## a jolt here would be the game punishing you for not having done the thing you are doing.
func on_jolt(_offset: Vector2, _strength: float, _duration: float) -> void:
	pass


# ---------------------------------------------------------------------------- the body

## Sounds and the patient, on every machine, from the replicated state. The panel's little figure
## and the real body on the table say the same thing at the same time.
func react() -> void:
	var b = body()
	if _seen.is_empty():
		_seen = {"stage": stage, "inserted": inserted, "beads": beads.size()}
		audio(draw_cue, -8.0, 0.05)
		return
	if inserted and not bool(_seen.inserted):
		audio(tick_cue, -2.0)
	if beads.size() != int(_seen.beads):
		audio(miss_cue, -4.0, 0.3)
		if b != null and b.has_method("stir"):
			b.stir(0.6)
	_seen = {"stage": stage, "inserted": inserted, "beads": beads.size()}
	var r := ratio()
	# The plunger hiss, and the monitor once there is too much in them.
	if pressing and inserted and flash <= 0.0 and stage == Stage.DOSE:
		if _push_snd <= 0.0:
			_push_snd = push_every
			audio(push_cue, -9.0, 0.04)
	else:
		_push_snd = 0.0
	if stage == Stage.DOSE and r > alarm_from:
		if _alarm_t <= 0.0:
			_alarm_t = alarm_every
			audio(alarm_cue, -3.0)
	else:
		_alarm_t = 0.0
	if b == null or stage == Stage.DONE:
		return
	if b.has_method("set_sedation"):
		b.set_sedation(clampf(r * 0.75, 0.0, 1.0))
	var awake := clampf(1.0 - r / still_from, 0.0, 1.0)
	if awake <= 0.0 or not b.has_method("stir"):
		return
	if _stir_t <= 0.0:
		_stir_t = _vrng.randf_range(0.45, 0.9) / (0.4 + awake)
		b.stir(0.12 + 0.45 * awake * _vrng.randf_range(0.6, 1.0))


# ---------------------------------------------------------------------------- the diagram

func paint_game(c: CanvasItem) -> void:
	if panel == null:
		return
	var st := style()
	_paint_limb(c, st)
	_paint_vein(c, st)
	_paint_needle(c, st)
	_paint_barrel(c, st)
	_paint_patient(c, st)
	if _miss_flash > 0.0:
		c.draw_rect(Rect2(Vector2.ZERO, panel.tex_size()), Color(st.danger, _miss_flash * 0.18))


## Half the arm's width at `t`, 0 at the elbow end and 1 at the wrist end. The ^8 keeps the sides
## near-straight and rounds the two ends off.
func limb_half_at(t: float) -> float:
	var cap: float = pow(maxf(0.0, 1.0 - pow(2.0 * t - 1.0, 8.0)), 0.35)
	return limb_half * lerpf(1.0, limb_taper, t) * cap


func _limb_outline() -> PackedVector2Array:
	var right := PackedVector2Array()
	var left := PackedVector2Array()
	for i in 33:
		var t := float(i) / 32.0
		var y := lerpf(limb_top, limb_bot, t)
		var h := limb_half_at(t)
		right.append(px(Vector2(h, y)))
		left.append(px(Vector2(-h, y)))
	for i in range(left.size() - 1, -1, -1):
		right.append(left[i])
	return right


func _paint_limb(c: CanvasItem, st: StyleScript) -> void:
	var out := _limb_outline()
	c.draw_colored_polygon(out, Color(st.blood_dark, 0.32))
	st.glow_poly(c, out, st.line, st.thin)
	c.draw_polyline(out, st.line, st.outline)
	# Skin: a second line inside the first, so the arm reads as a thing with an outside.
	var inner := PackedVector2Array()
	for i in 33:
		var t := float(i) / 32.0
		var h: float = maxf(1.0, limb_half_at(t) - 2.6)
		inner.append(px(Vector2(h, lerpf(limb_top + 1.4, limb_bot - 1.4, t))))
	for i in 33:
		var t := 1.0 - float(i) / 32.0
		var h: float = maxf(1.0, limb_half_at(t) - 2.6)
		inner.append(px(Vector2(-h, lerpf(limb_top + 1.4, limb_bot - 1.4, t))))
	inner.append(inner[0])
	c.draw_polyline(inner, Color(st.line_dim, 0.55), st.hair)
	# The beads of blood left by every press that went through skin and found nothing.
	for bx in beads:
		var at := px(Vector2(float(bx), lerpf(limb_top, limb_bot, 0.42)))
		c.draw_circle(at, px_len(1.9), st.blood)
		c.draw_arc(at, px_len(3.1), 0.0, TAU, 12, Color(st.blood, 0.5), st.hair)


func _paint_vein(c: CanvasItem, st: StyleScript) -> void:
	var y0 := limb_top + 3.0
	var y1 := limb_bot - 3.0
	# The bruising is drawn as well as counted: the vein you started with, as a dashed ghost either
	# side of the one you have left.
	if vein_half < vein_half_full - 0.05:
		for s: float in [-1.0, 1.0]:
			var x: float = vein_x + s * vein_half_full
			st.dashed(c, px(Vector2(x, y0)), px(Vector2(x, y1)), Color(st.line_dim, 0.45), st.hair, 5.0, 5.0)
		for i in misses:
			var bx: float = vein_x + (vein_half_full + 1.6) * (1.0 if i % 2 == 0 else -1.0)
			var by: float = lerpf(y0 + 3.0, y1 - 3.0, float(i % 4) / 3.0)
			c.draw_circle(px(Vector2(bx, by)), px_len(2.6), Color(st.blood_dark, 0.85))
	var flick: bool = hop_state == Hop.FLICKER and fmod(_t * 14.0, 1.0) < 0.5
	var col: Color = st.sloppy if hop_state == Hop.FLICKER else st.line
	var alpha: float = 0.25 if flick else 1.0
	var poly := PackedVector2Array([
		px(Vector2(vein_x - vein_half, y0)), px(Vector2(vein_x + vein_half, y0)),
		px(Vector2(vein_x + vein_half, y1)), px(Vector2(vein_x - vein_half, y1))])
	c.draw_colored_polygon(poly, Color(st.steel, 0.16 * alpha))
	# Pattern as well as colour: the vein is the hatched stripe, so it is still the vein when the
	# hop turns it amber or the panel is being watched from across the room.
	var y := y0 + 1.5
	while y < y1:
		c.draw_line(px(Vector2(vein_x - vein_half, y)), px(Vector2(vein_x + vein_half, y)),
			Color(col, 0.22 * alpha), st.hair)
		y += 3.0
	for s: float in [-1.0, 1.0]:
		var x: float = vein_x + s * vein_half
		st.glow_line(c, px(Vector2(x, y0)), px(Vector2(x, y1)), Color(col, alpha), st.thin)
		c.draw_line(px(Vector2(x, y0)), px(Vector2(x, y1)), Color(col, alpha), st.thin)


## The marker riding its track, and the guide line down to whatever is under it.
func _paint_needle(c: CanvasItem, st: StyleScript) -> void:
	var x: float = vein_x if stage != Stage.STICK else sweep_x
	var tip_y: float = lerpf(limb_top, limb_bot, 0.42) if inserted else limb_top - 2.0
	if inserted and withdraw > 0.0:
		tip_y = lerpf(tip_y, limb_top - 2.0, clampf(withdraw / withdraw_time, 0.0, 1.0))
	var live: bool = stage == Stage.STICK and cooldown <= 0.0
	var body_col: Color = st.steel if live else Color(st.steel, 0.45)
	# The track, so the sweep is read as a thing with two ends.
	st.dashed(c, px(Vector2(-sweep_half, track_y)), px(Vector2(sweep_half, track_y)),
		Color(st.line_dim, 0.4), st.hair, 4.0, 6.0)
	# Guide line from the tip down onto the arm.
	st.dashed(c, px(Vector2(x, track_y + 2.0)), px(Vector2(x, tip_y)), Color(st.line_dim, 0.6), st.hair, 3.0, 4.0)
	# Barrel of the marker, hub, needle.
	var top := track_y - 5.0
	var hub_y := track_y + 2.4
	c.draw_rect(Rect2(px(Vector2(x - 3.2, top)), px(Vector2(x + 3.2, hub_y)) - px(Vector2(x - 3.2, top))),
		Color(st.steel, 0.22))
	c.draw_rect(Rect2(px(Vector2(x - 3.2, top)), px(Vector2(x + 3.2, hub_y)) - px(Vector2(x - 3.2, top))),
		body_col, false, st.thin)
	c.draw_line(px(Vector2(x - 5.2, top)), px(Vector2(x + 5.2, top)), body_col, st.thin)
	# The hub: filled solid with a notch once blood has flashed back, hollow before. Shape, not
	# just the red, says the needle is in.
	var hub := Rect2(px(Vector2(x - 2.4, hub_y)), px(Vector2(x + 2.4, hub_y + 3.2)) - px(Vector2(x - 2.4, hub_y)))
	if inserted:
		var beat: float = 1.0 if flash <= 0.0 else (0.35 + 0.65 * absf(sin(_t * 18.0)))
		c.draw_rect(hub, Color(st.danger, beat))
		c.draw_line(px(Vector2(x - 2.4, hub_y + 1.6)), px(Vector2(x + 2.4, hub_y + 1.6)), st.bg, st.hair)
	else:
		c.draw_rect(hub, body_col, false, st.hair)
	c.draw_line(px(Vector2(x, hub_y + 3.2)), px(Vector2(x, tip_y)), body_col, st.thin)
	if live:
		st.glow_line(c, px(Vector2(x, hub_y + 3.2)), px(Vector2(x, tip_y)), st.steel, st.hair)
	# Cooling off after a miss: the marker is crossed out, not just dimmed.
	if cooldown > 0.0:
		var a := px(Vector2(x - 4.0, top + 1.0))
		var b := px(Vector2(x + 4.0, hub_y - 1.0))
		c.draw_line(a, b, Color(st.danger, 0.8), st.thin)
		c.draw_line(Vector2(a.x, b.y), Vector2(b.x, a.y), Color(st.danger, 0.8), st.thin)


## The barrel. No scale, no marks, no green zone: it says how far the plunger has gone and not one
## thing about how far it ought to go.
func _paint_barrel(c: CanvasItem, st: StyleScript) -> void:
	var dim: float = 1.0 if stage == Stage.DOSE else 0.4
	var y0 := meter_y - meter_half_h
	var y1 := meter_y + meter_half_h
	var px0 := px(Vector2(meter_left, y0))
	var px1 := px(Vector2(meter_right, y1))
	var box := Rect2(px0, px1 - px0)
	# Shift 1 only: the training wheels, a faint dashed zone where the dose lives. It is the only
	# time the panel ever tells you.
	if int(ctx.get("shift", 1)) <= 1:
		var a: float = meter_left + (meter_right - meter_left) * clampf(good_lo / capacity_k, 0.0, 1.0)
		var b: float = meter_left + (meter_right - meter_left) * clampf(good_hi / capacity_k, 0.0, 1.0)
		c.draw_rect(Rect2(px(Vector2(a, y0)), px(Vector2(b, y1)) - px(Vector2(a, y0))),
			Color(st.line_dim, 0.10 * dim))
		for x: float in [a, b]:
			st.dashed(c, px(Vector2(x, y0 - 1.5)), px(Vector2(x, y1 + 1.5)),
				Color(st.line_dim, 0.5 * dim), st.hair, 3.0, 4.0)
	var k: float = clampf(_shown_plunger, 0.0, 1.0)
	var plunger_x: float = lerpf(meter_left, meter_right, k)
	# What has gone in, behind the plunger, hatched.
	if k > 0.001:
		var gx := meter_left
		while gx < plunger_x:
			c.draw_line(px(Vector2(gx, y0 + 1.0)), px(Vector2(minf(gx + 2.0, plunger_x), y1 - 1.0)),
				Color(st.steel, 0.20), st.hair)
			gx += 3.0
	# What is left in the barrel.
	if plunger_x < meter_right - 0.2:
		c.draw_rect(Rect2(px(Vector2(plunger_x, y0 + 0.8)), px(Vector2(meter_right, y1 - 0.8)) - px(Vector2(plunger_x, y0 + 0.8))),
			Color(st.sloppy, 0.34 * dim))
	st.glow_rect(c, box, Color(st.line, dim))
	c.draw_rect(box, Color(st.line, dim), false, st.thin)
	# The plunger: a solid block with a rod out the back, so its position reads at a glance.
	var pa := px(Vector2(plunger_x - 1.2, y0 + 0.6))
	var pb := px(Vector2(plunger_x + 1.2, y1 - 0.6))
	c.draw_rect(Rect2(pa, pb - pa), Color(st.line, dim))
	c.draw_line(px(Vector2(plunger_x, meter_y)), px(Vector2(meter_left - 8.0, meter_y)), Color(st.line, dim), st.thin)
	c.draw_line(px(Vector2(meter_left - 8.0, y0 - 1.0)), px(Vector2(meter_left - 8.0, y1 + 1.0)), Color(st.line, dim), st.thin)
	# Hub and needle off the right-hand end, pointing at the arm.
	c.draw_rect(Rect2(px(Vector2(meter_right, meter_y - 2.2)), px(Vector2(meter_right + 3.0, meter_y + 2.2)) - px(Vector2(meter_right, meter_y - 2.2))),
		Color(st.danger if inserted else st.steel, dim))
	c.draw_line(px(Vector2(meter_right + 3.0, meter_y)), px(Vector2(meter_right + 11.0, meter_y)), Color(st.steel, dim), st.thin)


## The patient. This is the whole read-out: there is no number anywhere on this panel.
func _paint_patient(c: CanvasItem, st: StyleScript) -> void:
	var r := ratio()
	var awake: float = clampf(1.0 - r / still_from, 0.0, 1.0)
	var over: float = clampf((r - alarm_from) / 0.35, 0.0, 1.0)
	var s := icon_scale
	var jit := Vector2(sin(_t * 23.0) + 0.6 * sin(_t * 41.0 + 1.0), cos(_t * 19.0)) * twitch_mm * awake
	var o: Vector2 = icon_at + jit + Vector2(0.0, 2.0 * over)
	var col: Color = st.line.lerp(st.good, 1.0 - awake).lerp(st.line_dim, over)
	var dash: bool = over > 0.35
	var head: Vector2 = o + Vector2(0.0, -8.0 * s)
	var hr: float = 4.4 * s
	# Head.
	c.draw_circle(px(head), px_len(hr), Color(col, 0.16))
	if dash:
		for i in 10:
			var a0: float = TAU * float(i) / 10.0
			c.draw_arc(px(head), px_len(hr), a0, a0 + TAU / 20.0, 4, col, st.thin)
	else:
		c.draw_arc(px(head), px_len(hr), 0.0, TAU, 20, col, st.thin)
	# Eyes: two dots awake, one closed line asleep, two crosses gone.
	if over > 0.35:
		for sx: float in [-1.0, 1.0]:
			var e: Vector2 = head + Vector2(sx * 1.8 * s, -0.4 * s)
			c.draw_line(px(e + Vector2(-1.0, -1.0) * s), px(e + Vector2(1.0, 1.0) * s), col, st.hair)
			c.draw_line(px(e + Vector2(-1.0, 1.0) * s), px(e + Vector2(1.0, -1.0) * s), col, st.hair)
	elif awake > 0.05:
		for sx: float in [-1.0, 1.0]:
			c.draw_circle(px(head + Vector2(sx * 1.8 * s, -0.4 * s)), px_len(0.8 * s), col)
	else:
		c.draw_line(px(head + Vector2(-2.4 * s, -0.4 * s)), px(head + Vector2(2.4 * s, -0.4 * s)), col, st.thin)
	# Body.
	var b0: Vector2 = o + Vector2(-5.6 * s, -3.0 * s)
	var b1: Vector2 = o + Vector2(5.6 * s, 10.0 * s)
	var rect := Rect2(px(b0), px(b1) - px(b0))
	c.draw_rect(rect, Color(col, 0.12))
	if dash:
		st.dashed(c, px(b0), px(Vector2(b1.x, b0.y)), col, st.thin, 4.0, 4.0)
		st.dashed(c, px(Vector2(b1.x, b0.y)), px(b1), col, st.thin, 4.0, 4.0)
		st.dashed(c, px(b1), px(Vector2(b0.x, b1.y)), col, st.thin, 4.0, 4.0)
		st.dashed(c, px(Vector2(b0.x, b1.y)), px(b0), col, st.thin, 4.0, 4.0)
	else:
		c.draw_rect(rect, col, false, st.thin)
	# The chest trace: a beating chevron while they are with you, flat once they are not.
	var tw := 4.6 * s
	var ty := o.y + 3.0 * s
	var amp: float = lerpf(2.2, 0.0, over) * s
	var trace := PackedVector2Array([
		px(Vector2(o.x - tw, ty)), px(Vector2(o.x - tw * 0.45, ty)),
		px(Vector2(o.x - tw * 0.2, ty - amp)), px(Vector2(o.x + tw * 0.1, ty + amp * 0.7)),
		px(Vector2(o.x + tw * 0.45, ty)), px(Vector2(o.x + tw, ty))])
	c.draw_polyline(trace, Color(col if over < 0.5 else st.danger, 0.95), st.thin)
	# Twitching: ticks either side, one more the more awake they are. Shape, not colour.
	var ticks := int(ceil(awake * 3.0))
	for i in ticks:
		var rr: float = (8.0 + 2.6 * float(i)) * s
		for sx: float in [-1.0, 1.0]:
			var mid := o + Vector2(sx * rr, 0.0)
			c.draw_line(px(mid + Vector2(0.0, -1.8 * s)), px(mid + Vector2(0.0, 1.8 * s)), Color(col, 0.75), st.hair)
	# The alarm: a blinking ring round the whole figure, with the cross-hatch under it.
	if over > 0.0 and fmod(_t * 3.0, 1.0) < 0.5:
		c.draw_arc(px(o + Vector2(0.0, 1.0 * s)), px_len(15.0 * s), 0.0, TAU, 28, Color(st.danger, 0.75 * over), st.thin)
	if over > 0.35:
		var hx := b0.x
		while hx < b1.x + (b1.y - b0.y):
			var xa: float = maxf(b0.x, hx - (b1.y - b0.y))
			c.draw_line(px(Vector2(minf(hx, b1.x), b0.y + maxf(0.0, hx - b1.x))),
				px(Vector2(xa, b0.y + (minf(hx, b1.x) - xa))), Color(col, 0.35), st.hair)
			hx += 3.0
	var font := ThemeDB.fallback_font
	var label := "PATIENT"
	var w: float = font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
	c.draw_string(font, px(Vector2(icon_at.x, icon_at.y + 15.0)) + Vector2(-w * 0.5, 0.0), label,
		HORIZONTAL_ALIGNMENT_LEFT, -1.0, 16, Color(st.line_dim, 0.8))


# ---------------------------------------------------------------------------- net

## Everything an onlooker needs to follow the step. The marker, the plunger and the two timers CREEP
## -- less than their own quantum in a frame -- so they go out raw; only what jumps is snapped.
func net_pack() -> Dictionary:
	return {
		"st": stage, "sx": sweep_x, "sd": sweep_dir,
		"vx": snappedf(vein_x, 0.05), "vh": snappedf(vein_half, 0.01),
		"in": injected, "pg": pressing, "ins": inserted,
		"fl": flash, "wd": withdraw, "cd": cooldown,
		"ms": misses, "bd": beads, "hp": hop_state, "hl": hop_left,
		"se": snappedf(sedation, 0.01),
	}


func net_apply(s: Dictionary) -> void:
	stage = int(s.get("st", stage))
	sweep_x = float(s.get("sx", sweep_x))
	sweep_dir = float(s.get("sd", sweep_dir))
	vein_x = float(s.get("vx", vein_x))
	vein_half = float(s.get("vh", vein_half))
	injected = float(s.get("in", injected))
	pressing = bool(s.get("pg", pressing))
	inserted = bool(s.get("ins", inserted))
	flash = float(s.get("fl", flash))
	withdraw = float(s.get("wd", withdraw))
	cooldown = float(s.get("cd", cooldown))
	var was := misses
	misses = int(s.get("ms", misses))
	var bd = s.get("bd", beads)
	if bd is Array:
		beads = bd
	hop_state = int(s.get("hp", hop_state))
	hop_left = float(s.get("hl", hop_left))
	sedation = float(s.get("se", sedation))
	if misses > was:
		_miss_flash = 0.45


# ---------------------------------------------------------------------------- bot

## The bot jabs EARLY, which is what a hand under pressure does: it decides how far ahead of the
## vein it is going to press and then presses there. The error is a golden-ratio sequence, not a
## draw, so every run of the lab is the same run.
func bot_input(t: float, skill: float) -> Dictionary:
	var dt: float = clampf(t - _bt, 0.0, 0.1)
	_bt = t
	skill = clampf(skill, 0.0, 1.0)
	if not armed() or not _b_started:
		_b_started = armed()
		_b_prev = sweep_x
		return {"cursor": _out(), "buttons": 0}
	var buttons := 0
	match stage:
		Stage.STICK:
			if misses != _b_err_for:
				_b_err_for = misses
				_b_seq += 1
				var u: float = fposmod(float(_b_seq) * 0.6180339887498949, 1.0)
				_b_jab = u * bot_jab_mm * (1.0 - skill)
			# Where it means to press: `jab` mm short of the vein, on the side it is coming from.
			var target: float = vein_x - sweep_dir * _b_jab
			if cooldown <= 0.0 and dt > 0.0 and signf(_b_prev - target) != signf(sweep_x - target):
				buttons = BUTTON_PRIMARY
			_b_prev = sweep_x
		Stage.DOSE:
			# A good hand stops the moment the patient goes still; a bad one keeps pushing.
			if ratio() < lerpf(bot_sloppy_stop, bot_good_stop, skill):
				buttons = BUTTON_PRIMARY
	return {"cursor": _out(), "buttons": buttons}


func _out() -> Vector2:
	return panel.metres_of(Vector2(sweep_x, track_y)) if panel != null else Vector2.ZERO


# ---------------------------------------------------------------------------- self-test

## Headless check: `tools/minigame_lab.tscn -- --selftest=anesthetic:arcade`.
## Targets: skill 1.0 finishes in 8-20 s losing 0-2 vitals; skill 0.0 under 40 s losing 15-25.
static func self_test() -> Array:
	var script: GDScript = load("res://scripts/surgery/arcade/dose_arcade.gd")
	var out := []
	var ok := true
	var sloppy: Array = []
	for pid: String in ["bob", "seal"]:
		for skill: float in [1.0, 0.5, 0.0]:
			var g = script.new()
			var tally := {"n": 0, "v": 0.0, "done": false, "sed": -1.0, "reasons": {}}
			g.botched.connect(func(a, r): tally.n += 1; tally.v += a; tally.reasons[r] = int(tally.reasons.get(r, 0)) + 1)
			g.finished.connect(func(r): tally.done = true; tally.sed = float(r.get("sedation", -1.0)))
			g.setup(_ctx(pid, 1))
			var t: float = run_bot(g, skill, 1.0, hash(pid) + int(skill * 100))
			print("[dose-arcade self-test] %-4s skill=%.1f  %s  need=%.2fml gave=%.2fml  missed=%d  time=%5.1fs  botches=%d vitals=%5.1f  sedation=%.2f  %s" % [
				pid, skill, "DONE" if tally.done else "UNFINISHED", g.target_ml, g.injected, g.misses,
				t, tally.n, tally.v, tally.sed, str(tally.reasons)])
			out.append({"patient": pid, "skill": skill, "done": tally.done, "time": t,
				"vitals": tally.v, "sedation": tally.sed, "misses": g.misses})
			if skill == 1.0:
				if not tally.done or t < 8.0 or t > 20.0 or tally.v > 2.0:
					print("[dose-arcade self-test] MISS: skill 1.0 wants 8-20 s and 0-2 vitals")
					ok = false
				# The carry-forward every later step reads: a clean dose is a clean 1.0.
				if absf(tally.sed - 1.0) > 0.05:
					print("[dose-arcade self-test] MISS: skill 1.0 wants sedation near 1.0, got %.2f" % tally.sed)
					ok = false
			if skill == 0.0:
				sloppy.append(tally.v)
				if not tally.done or t > 40.0:
					print("[dose-arcade self-test] MISS: skill 0.0 wants to finish under 40 s")
					ok = false
				if tally.v < 15.0 or tally.v > 25.0:
					print("[dose-arcade self-test] MISS: skill 0.0 wants 15-25 vitals")
					ok = false
				if tally.sed >= 0.75 and tally.sed <= 1.25:
					print("[dose-arcade self-test] MISS: skill 0.0 should carry a clearly wrong sedation, got %.2f" % tally.sed)
					ok = false
			g.free()
	# The sloppy band on the MEAN: the two patients need very different amounts of drug, so the
	# same sloppy hand lands a few vitals either side of the other on its own. saw_arcade does the
	# same for the same reason.
	var mean := 0.0
	for v: float in sloppy:
		mean += v
	mean /= maxf(1.0, float(sloppy.size()))
	print("[dose-arcade self-test] skill 0.0 mean vitals %.1f across %d patients (want 15-25)" % [mean, sloppy.size()])
	if mean < 15.0 or mean > 25.0:
		print("[dose-arcade self-test] MISS: skill 0.0 wants 15-25 vitals on average")
		ok = false
	# Shift 3 and up, where the vein hops once mid-sweep. The lab only ever builds shift 1, so this
	# is the only place the hop is exercised. It is checked on a hand that does not press at all,
	# because a hand that sticks it first time is out of stage A before the hop comes round -- which
	# is the point of the hop: it is a tax on hesitating, not a coin flip.
	for pid: String in ["bob", "seal"]:
		var g3 = script.new()
		var t3 := {"v": 0.0, "done": false}
		g3.botched.connect(func(a, _r): t3.v += a)
		g3.finished.connect(func(_r): t3.done = true)
		g3.setup(_ctx(pid, 3))
		var was: float = g3.vein_x
		var waited := 0.0
		while waited < 5.0:
			waited += 1.0 / 60.0
			g3.handle_cursor(Vector2.ZERO, 0, 1.0 / 60.0)
			g3.tick(1.0 / 60.0)
			g3.apply_net_state(g3.net_state())
		var moved: float = absf(g3.vein_x - was)
		var tt: float = run_bot(g3, 0.0, 1.0, hash(pid))
		print("[dose-arcade self-test] %-4s shift=3 dawdling  %s  vein hopped %s (%.1f -> %.1f mm)  missed=%d  then finished in %5.1fs  vitals=%4.1f" % [
			pid, "DONE" if t3.done else "UNFINISHED", "yes" if g3.hop_state == Hop.DONE else "NO",
			was, g3.vein_x, g3.misses, tt + 5.0, t3.v])
		out.append({"patient": pid, "shift": 3, "done": t3.done, "hopped": moved})
		if not t3.done or g3.hop_state != Hop.DONE or moved < g3.hop_min_mm:
			print("[dose-arcade self-test] MISS: shift 3 must hop the vein once and still finish")
			ok = false
		g3.free()
	# The dose is by weight, and that difference IS the step: the same syringe-full is right for one
	# patient and nowhere near enough for the other.
	var bob_need := _dose(script, "bob", 0.0)
	var seal_need := _dose(script, "seal", 0.0)
	print("[dose-arcade self-test] by weight: bob needs %.2f ml, seal needs %.2f ml" % [bob_need, seal_need])
	var cross := _dose(script, "seal", bob_need)
	print("[dose-arcade self-test] bob's dose (%.2f ml) into the seal -> sedation %.2f (wants < 0.75)" % [bob_need, cross])
	out.append({"bob_ml": bob_need, "seal_ml": seal_need, "cross_sedation": cross})
	if seal_need <= bob_need + 1.0 or cross >= 0.75:
		print("[dose-arcade self-test] MISS: a big patient must need a clearly bigger dose")
		ok = false
	# An onlooker has to be able to watch: a second copy fed only net_state must track the operator.
	var drift := _net_round_trip(script)
	print("[dose-arcade self-test] spectator drift after the blob: marker %.3f mm, dose %.4f ml, stage %s" % [
		drift[0], drift[1], "same" if drift[2] < 0.5 else "DIFFERENT"])
	if drift[0] > 0.01 or drift[1] > 0.001 or drift[2] > 0.5:
		print("[dose-arcade self-test] MISS: a spectator does not see what the operator sees")
		ok = false
	# Walking away and somebody else picking it up: the marker must stop dead, and the countdown
	# must swallow whatever the new pair of hands is mashing.
	var hand := _hand_over(script)
	print("[dose-arcade self-test] hand-over: frozen marker moved %.3f mm, mashed %d times through READY -> %d misses, running again %s" % [
		hand[0], hand[1], hand[2], "yes" if hand[3] > 0.5 else "NO"])
	if hand[0] > 0.001 or hand[2] > 0 or hand[3] < 0.5:
		print("[dose-arcade self-test] MISS: a hand-over must not cost the new operator anything")
		ok = false
	print("[dose-arcade self-test] %s" % ("PASS" if ok else "FAIL"))
	return out


static func _ctx(pid: String, shift: int) -> Dictionary:
	return {"patient_id": pid, "patient": Procedures.patient(pid), "ailment_id": "gunshot",
		"step": Procedures.step("gunshot", 0), "variant": "", "shift": shift,
		"difficulty": Procedures.difficulty(shift), "flags": {},
		"seed": hash("dose" + pid), "body": null, "operator": true, "operating": true}


## With `ml` of 0, what this patient needs. Otherwise the sedation that giving them `ml` produces.
static func _dose(script: GDScript, pid: String, ml: float) -> float:
	var g = script.new()
	g.setup(_ctx(pid, 1))
	var v: float = g.target_ml
	if ml > 0.0:
		g.injected = ml
		g.stage = 0
		g._complete()
		v = g.sedation
	g.free()
	return v


## Player A dithers, walks off, and player B takes the machine over on the state blob alone.
## Returns [mm the frozen marker drifted, presses mashed during READY, misses they cost, running].
static func _hand_over(script: GDScript) -> Array:
	var dt := 1.0 / 60.0
	var a = script.new()
	a.setup(_ctx("bob", 1))
	var t := 0.0
	while t < 3.0:
		t += dt
		a.handle_cursor(Vector2.ZERO, 0, dt)
		a.tick(dt)
	# A steps away from the table.
	a.ctx["operating"] = false
	var parked: float = a.sweep_x
	for _i in 30:
		a.tick(dt)
	var drift: float = absf(a.sweep_x - parked)
	# B arrives, is handed the blob, and mashes through the countdown.
	var b = script.new()
	var bctx := _ctx("bob", 1)
	bctx["operating"] = false
	b.setup(bctx)
	b.apply_net_state(a.net_state())
	b.ctx["operating"] = true
	var mashed := 0
	var counted_down := false
	for _i in 600:
		mashed += 1
		b.handle_cursor(Vector2.ZERO, BUTTON_PRIMARY if mashed % 2 == 0 else 0, dt)
		b.tick(dt)
		if b.play_state == b.Play.READY:
			counted_down = true
		elif counted_down:
			break
	var back: bool = counted_down and b.play_state == b.Play.RUNNING
	var out := [drift, mashed, b.misses, 1.0 if back else 0.0]
	a.free()
	b.free()
	return out


## Operator and onlooker, side by side: one plays, the other only ever sees net_state().
static func _net_round_trip(script: GDScript) -> Array:
	var op = script.new()
	var spec = script.new()
	op.setup(_ctx("bob", 1))
	var sctx := _ctx("bob", 1)
	sctx["operator"] = false
	spec.setup(sctx)
	var dt := 1.0 / 60.0
	var t := 0.0
	var n := 0
	while t < 12.0 and not op.done:
		t += dt
		var inp: Dictionary = op.bot_input(t, 1.0)
		op.handle_cursor(Vector2.ZERO, int(inp.get("buttons", 0)), dt)
		op.tick(dt)
		spec.tick(dt)
		# 20 Hz, as the real relay does, with the spectator dead-reckoning in between.
		n += 1
		if n % 3 == 0:
			spec.apply_net_state(op.net_state())
	# The last blob of the step, which is the one that puts the onlooker's panel away.
	spec.apply_net_state(op.net_state())
	var drift := [absf(spec.sweep_x - op.sweep_x), absf(spec.injected - op.injected),
		absf(float(spec.stage) - float(op.stage))]
	op.free()
	spec.free()
	return drift
