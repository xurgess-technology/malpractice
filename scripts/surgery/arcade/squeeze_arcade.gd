extends "res://scripts/surgery/arcade/arcade_game.gd"
## ARCADE SURGERY (docs/ARCADE_SURGERY.md) 5.4 -- SQUEEZE! Step "tourniquet" of an amputation: get
## the strap on above the rot and crank it until the pulse stops. The arcade rebuild of
## scripts/surgery/games/tourniquet.gd, played on the raised panel.
##
## Rhyme: the fishing-bar minigame. Two stages, two command cards.
##
## What you do
##   PLACE. A side view of the limb, the dead end of it away to the right. The open strap sweeps
##   back and forth along the arm and you click to cinch it. Where it lands is judged exactly as it
##   always was: a hand's width above the infection holds, further up holds but badly, on or beside
##   the rot slips straight off and costs you. The front CREEPS toward you the whole time, so the
##   safe stretch of arm slides away while you dither.
##   TIGHTEN. A pressure gauge, nought to four hundred and fifty. Hold the mouse and your bar
##   climbs; let go and it sinks, and it carries its own momentum either way. Somewhere up the
##   gauge is the pulse, and the pulse does not hold still: it wanders, and now and then it darts.
##   HOW MUCH it moves is the anaesthetic you gave it -- CARRY-FORWARD from the injection, and on a badly
##   sedated patient the marker is all over the gauge and you are chasing it.
##   Keep your bar over the pulse and the occlusion meter fills; drift off and it drains twice as
##   slowly as it filled. Fill it and the windlass drops into its clip on its own. Right-click and
##   you take whatever you have got, which below two fifths of a meter is the windlass spinning
##   free in your hand. Sit sixty over the pulse and the limb goes purple and the bill starts.
##
## Result {"tourniquet": placement x fill_at_lock x hold_factor} -- the same single number the
## legacy game emits, because SAW! reads it for the spurt and WRAP! reads it for the bleeding cells.

enum Stage { PLACE, TIGHTEN, LOCKED }

const PLACE_GOOD := 0
const PLACE_FAR := 1
const PLACE_BAD := 2

const PHI := 0.6180339887498949

# -- the limb, in diagram millimetres -----------------------------------------------------------
## Half the limb's depth in the side view. The site marker is x = 0 and distal (the dead hand) is +x.
@export_range(4.0, 30.0, 0.5) var limb_half_mm := 15.0
@export_range(-30.0, 20.0, 0.5) var limb_y_mm := -4.0
## How far each way the open strap sweeps along the limb.
@export_range(10.0, 58.0, 1.0) var sweep_half_mm := 52.0
@export_range(10.0, 300.0, 1.0) var sweep_speed := 80.0
## A real CAT strap is 3.8 cm wide, and the whole width of it has to clear the rot.
@export_range(5.0, 60.0, 0.5) var strap_w_mm := 38.0

# -- the infection ------------------------------------------------------------------------------
## Where the front starts, distal of the site marker. A body that reports its own
## (PatientBody.infection_start) overrides this, as long as the strap can actually reach it.
@export_range(5.0, 90.0, 0.5) var front_min_mm := 30.0
@export_range(5.0, 90.0, 0.5) var front_max_mm := 55.0
## It does not wait for you: the front creeps proximally at this rate while you are placing.
@export_range(0.0, 10.0, 0.1) var creep_mm_s := 1.5
## It stops here, just short of the site marker, or the step becomes unwinnable.
@export_range(-40.0, 20.0, 1.0) var front_floor_mm := -10.0

# -- the placement bands (the legacy game's rule, unchanged) --------------------------------------
## The ideal strap centre, this far proximal of the front.
@export_range(10.0, 90.0, 1.0) var band_centre_mm := 50.0
@export_range(2.0, 50.0, 0.5) var band_half_mm := 30.0
@export_range(1.0, 30.0, 0.5) var band_half_min_mm := 8.0
## Slack below the green band that still counts as green.
@export_range(0.0, 20.0, 0.5) var band_slack_mm := 4.0
## Placement quality loses 0.6 over this much of arm past the top of the band.
@export_range(10.0, 300.0, 5.0) var far_falloff_mm := 100.0
@export_range(0.1, 3.0, 0.05) var slip_time := 0.8
@export_range(0.0, 20.0, 0.5) var on_infection_botch := 9.0
@export_range(0.0, 20.0, 0.5) var too_close_botch := 5.0

# -- the gauge, in mmHg ---------------------------------------------------------------------------
@export_range(100.0, 800.0, 10.0) var gauge_max := 450.0
## The seeded pressure at which this limb's pulse actually stops.
@export_range(50.0, 500.0, 5.0) var occlusion_min := 230.0
@export_range(50.0, 500.0, 5.0) var occlusion_max := 310.0
## Your bar's height on the gauge, before difficulty narrows it.
@export_range(10.0, 200.0, 1.0) var bar_span := 90.0
@export_range(4.0, 100.0, 1.0) var bar_span_min := 24.0

# -- the pulse ------------------------------------------------------------------------------------
## CARRY-FORWARD from the injection: noise = pulse_noise x difficulty x (1 + sedation_gain x (1 - sedation)).
@export_range(0.0, 100.0, 1.0) var pulse_noise := 25.0
@export_range(0.0, 5.0, 0.1) var sedation_gain := 1.5
@export_range(0.05, 3.0, 0.05) var pulse_hz := 0.42
@export_range(0.2, 20.0, 0.1) var dart_gap_min := 2.0
@export_range(0.2, 20.0, 0.1) var dart_gap_max := 5.0
@export_range(0.1, 3.0, 0.05) var dart_time := 0.55

# -- the bar --------------------------------------------------------------------------------------
@export_range(50.0, 3000.0, 10.0) var rise_accel := 560.0
@export_range(50.0, 3000.0, 10.0) var fall_accel := 430.0
## Drag on the bar. Low numbers make it float about; high ones make it stiff.
@export_range(0.2, 20.0, 0.1) var bar_damp := 3.0
@export_range(20.0, 1000.0, 10.0) var bar_max_v := 165.0

# -- occluding ------------------------------------------------------------------------------------
@export_range(0.5, 20.0, 0.1) var fill_time := 4.6
@export_range(0.5, 40.0, 0.1) var decay_time := 8.0
## Sit this far over the pulse and the limb starts dying.
@export_range(10.0, 200.0, 1.0) var over_margin := 60.0
@export_range(0.0, 20.0, 0.5) var over_botch := 2.0
@export_range(0.1, 3.0, 0.05) var over_chunk := 0.5
## Lock below this much meter and the windlass spins free instead.
@export_range(0.0, 1.0, 0.01) var early_fill_min := 0.40
@export_range(0.0, 20.0, 0.5) var early_botch := 3.0
@export_range(0.0, 1.0, 0.05) var early_keep := 0.6
@export_range(0.0, 200.0, 5.0) var jolt_drop := 40.0
@export_range(0.0, 3.0, 0.05) var lock_delay := 0.6

# -- the bot ----------------------------------------------------------------------------------------
## How far off the band a hopeless hand aims the strap, in mm.
@export_range(0.0, 120.0, 1.0) var bot_place_err := 42.0
## How far off the pulse it aims the bar, in mmHg, and how long it sticks with each wrong idea.
@export_range(0.0, 300.0, 1.0) var bot_press_err := 120.0
@export_range(0.1, 5.0, 0.05) var bot_dither := 1.4
## How far ahead a good hand reads its own momentum, in seconds.
@export_range(0.0, 1.0, 0.01) var bot_lead := 0.18
## A panicking hand grabs at the clip every time the meter has crept up another notch this big --
## all of them under early_fill_min, so all of them spin free -- this many times before it waits.
@export_range(0.02, 0.4, 0.01) var bot_grab_fill := 0.12
@export_range(0, 6) var bot_panic_grabs := 3

# -- audio ------------------------------------------------------------------------------------------
@export var swish_cue := "surgery_tourniquet_swish"
@export var cinch_cue := "surgery_tourniquet_cinch"
@export var lock_cue := "surgery_tourniquet_lock"
@export var ratchet_cue := "surgery_tourniquet_ratchet"
@export var creak_cue := "surgery_tourniquet_creak"
@export var beat_cue := "surgery_beep"
@export_range(-40.0, 0.0, 1.0) var ratchet_volume := -12.0
@export_range(-40.0, 0.0, 1.0) var beat_volume := -18.0

# ---- replicated state ----
var stage: int = Stage.PLACE
var sweep_x := 0.0                ## mm along the limb, the open strap's centre
var sweep_dir := 1.0
var slip := 0.0                   ## 0 = hanging where you put it, else 0..1 sliding off
var front := 45.0                 ## mm, the infection's leading edge; it creeps
var misplaces := 0
var place_q := 1.0
var strap_x := 0.0                ## mm, where it finally went on
var bar_p := 0.0                  ## mmHg, the centre of your bar
var bar_v := 0.0                  ## mmHg/s
var fill := 0.0                   ## the occlusion meter, 0..1
var fill_at_lock := 0.0
var tight_t := 0.0                ## seconds of stage B, and the pulse's whole clock
var on_t := 0.0                   ## seconds of it spent over the pulse
var contact_t := 0.0              ## seconds since the bar first found the pulse
var held := false
var lock_t := 0.0

# ---- derived from the seed ----
var sedation := 1.0
var occlusion := 270.0
var band_half := 30.0
var darts: Array = []             ## [start second, magnitude in units of the noise amplitude]
var _ph1 := 0.0
var _ph2 := 0.0
var _jag := 0.0

# ---- local ----
var _t := 0.0
var _over_acc := 0.0
var _shown_fill := 0.0
var _shown_bar := 0.0
var _purple := 0.0
var _blanch := 0.0
var _flash := 0.0
var _contacted := false
var _rng := RandomNumberGenerator.new()
var _seen_misplaces := 0
var _seen_stage: int = Stage.PLACE
var _seen_slip := false
var _beat_seen := -1
var _ratchet_seen := 0

# ---- bot ----
var _bt := 0.0
var _b_seq := 0
var _b_attempt := -1
var _b_want := 0.0
var _b_wait := 0.0
var _b_press := 0
var _b_mode_t := 0.0
var _b_seq2 := 0
var _b_grabs := 0


# ---------------------------------------------------------------------------- setup

func card_word_for_start() -> String:
	return "SQUEEZE!"


func build_game() -> void:
	var flags: Dictionary = ctx.get("flags", {})
	sedation = clampf(float(flags.get("sedation", 1.0)), 0.0, 1.0)
	_rng.seed = int(ctx.get("seed", 1)) ^ 0x51ee
	band_half = maxf(band_half_min_mm, band_half_mm / diff)
	occlusion = _rng.randf_range(occlusion_min, occlusion_max)
	_ph1 = _rng.randf() * TAU
	_ph2 = _rng.randf() * TAU
	_jag = _rng.randf() * TAU
	# Every dart the pulse will ever make, rolled up front so every machine gets the same ones.
	var at := _rng.randf_range(dart_gap_min, dart_gap_max)
	while at < 120.0:
		darts.append([at, (1.0 if _rng.randf() < 0.5 else -1.0) * _rng.randf_range(0.7, 1.3)])
		at += _rng.randf_range(dart_gap_min, dart_gap_max)
	front = _roll_front()
	sweep_x = -sweep_half_mm
	sweep_dir = 1.0
	bar_p = 0.0
	_shown_bar = 0.0
	_update_progress()


## Where the rot has got to, in diagram millimetres distal of the site marker.
##
## The body paints its own infection and knows where it starts, so take that when the strap can
## actually reach it. Bob's is 17 cm along his forearm and the seal's is nearly 10, both of them
## past the end of the sweep and off the side of this diagram, and a panel that shows a red zone
## with nothing in it is a panel that lies. For those the front is rolled from the seed the way the
## legacy game rolls it with no body at all: 3 to 5.5 cm, on the diagram, creeping.
func _roll_front() -> float:
	var rolled := _rng.randf_range(front_min_mm, front_max_mm)
	var b = body()
	if b == null or not b.has_method("infection_start"):
		return rolled
	var m := float(b.infection_start(String(ctx.get("step", {}).get("site", "limb"))))
	if not is_finite(m):
		return rolled
	var mm := m * 1000.0
	return mm if mm <= sweep_half_mm + strap_w_mm * 0.5 else rolled


# ---------------------------------------------------------------------------- the rules

## Millimetres of clean arm between a strap centred at x and the front. The legacy game's measure.
func above_front(x: float) -> float:
	return front - x


## Green, amber or red, exactly as the legacy game judges it.
func placement_at(x: float) -> int:
	var d := above_front(x)
	if d < band_centre_mm - band_half - band_slack_mm:
		return PLACE_BAD
	if d <= band_centre_mm + band_half:
		return PLACE_GOOD
	return PLACE_FAR


## The proximal edge of the red zone, in mm along the limb. Everything distal of it is a slip.
func red_from() -> float:
	return front - (band_centre_mm - band_half - band_slack_mm)


func green_from() -> float:
	return front - band_centre_mm - band_half


func green_to() -> float:
	return red_from()


## Half the height of your bar on the gauge.
func bar_half() -> float:
	return maxf(bar_span_min, bar_span / diff) * 0.5


## CARRY-FORWARD from the injection: how far the pulse marker wanders. A badly sedated patient's heart is
## not being talked down by anything, and you can see it on the gauge.
func noise_amp() -> float:
	return pulse_noise * diff * (1.0 + sedation_gain * (1.0 - sedation))


## The pulse marker's pressure at stage-B second `t`. A pure function of the clock and the seed, so
## the operator, every spectator and the bot all read the same gauge.
func pulse_at(t: float) -> float:
	var a := noise_amp()
	var w := sin(t * TAU * pulse_hz + _ph1) * 0.62 + sin(t * TAU * pulse_hz * 1.73 + _ph2) * 0.38
	var p := occlusion + a * w
	for d in darts:
		var u: float = t - float(d[0])
		if u < 0.0:
			break
		if u < dart_time:
			p += float(d[1]) * a * sin(PI * u / dart_time)
	return clampf(p, 30.0, gauge_max - 20.0)


func pulse_now() -> float:
	return pulse_at(tight_t)


func on_pulse() -> bool:
	return absf(bar_p - pulse_now()) <= bar_half()


func over_tight() -> bool:
	return bar_p > pulse_now() + over_margin


# ---------------------------------------------------------------------------- playing

func keys() -> Array:
	match stage:
		Stage.PLACE:
			return [["LMB / Space", "cinch the strap"]]
		Stage.TIGHTEN:
			return [["Hold LMB", "tighten"], ["RMB", "lock it now"]]
	return []


func hint() -> String:
	var base := super.hint()
	if base != "":
		return base
	match stage:
		Stage.PLACE:
			if slip > 0.0:
				return "It slipped off. The rot is still coming up the arm."
			return "Cinch it on the hatched stretch, above the front."
		Stage.TIGHTEN:
			if over_tight():
				return "Too tight. The limb is going purple."
			if on_pulse():
				return "That's the pulse. Hold it there."
			return "Hold the mouse to climb, let go to sink."
	return "Locked."


func play(_p: Vector2, buttons: int, edges: int, _delta: float) -> void:
	match stage:
		Stage.PLACE:
			if slip <= 0.0 and (edges & (BUTTON_PRIMARY | BUTTON_ACTION)) != 0:
				_cinch()
		Stage.TIGHTEN:
			held = (buttons & (BUTTON_PRIMARY | BUTTON_ACTION)) != 0
			if (edges & BUTTON_SECONDARY) != 0:
				_try_lock()


func advance(delta: float) -> void:
	match stage:
		Stage.PLACE:
			_advance_place(delta)
		Stage.TIGHTEN:
			_advance_tighten(delta)
		Stage.LOCKED:
			lock_t += delta
			if lock_t >= lock_delay:
				arcade_finish({"tourniquet": snappedf(quality, 0.001)})


func _advance_place(delta: float) -> void:
	# The rot does not wait for you: the whole safe stretch of arm slides proximally while you look.
	front = maxf(front_floor_mm, front - creep_mm_s * diff * delta)
	if slip > 0.0:
		slip += delta / slip_time
		if slip >= 1.0:
			slip = 0.0
		return
	sweep_x += sweep_dir * sweep_speed * delta
	if sweep_x > sweep_half_mm:
		sweep_x = sweep_half_mm
		sweep_dir = -1.0
	elif sweep_x < -sweep_half_mm:
		sweep_x = -sweep_half_mm
		sweep_dir = 1.0
	_update_progress()


## Click. Where the strap's centre is at this instant is where it goes.
func _cinch() -> void:
	var d := above_front(sweep_x)
	var near := band_centre_mm - band_half
	if d < near - band_slack_mm:
		misplaces += 1
		slip = 0.001
		_flash = 0.5
		shake(0.75)
		# On the rot itself, or beside it: the same two bills the legacy game hands you.
		if d < strap_w_mm * 0.5 + 2.0:
			cost(on_infection_botch, "The strap is on the infection: it slipped off")
		else:
			cost(too_close_botch, "Too close to the infection: the strap slipped off")
		return
	var far := band_centre_mm + band_half
	if d <= far:
		var e := absf(d - band_centre_mm) / maxf(0.5, band_half)
		place_q = 1.0 - 0.08 * e * e
	else:
		place_q = clampf(0.92 - 0.6 * (d - far) / far_falloff_mm, 0.3, 0.92)
	strap_x = sweep_x
	stage = Stage.TIGHTEN
	bar_p = 0.0
	bar_v = 0.0
	fill = 0.0
	tight_t = 0.0
	on_t = 0.0
	contact_t = 0.0
	_contacted = false
	held = false
	_update_progress()
	show_card("TIGHTEN!")


func _advance_tighten(delta: float) -> void:
	tight_t += delta
	var a: float = rise_accel if held else -fall_accel
	bar_v = clampf((bar_v + a * delta) * exp(-bar_damp * delta), -bar_max_v, bar_max_v)
	bar_p += bar_v * delta
	if bar_p <= 0.0:
		bar_p = 0.0
		bar_v = maxf(bar_v, 0.0)
	elif bar_p >= gauge_max:
		bar_p = gauge_max
		bar_v = minf(bar_v, 0.0)
	var on := on_pulse()
	if on:
		_contacted = true
	if _contacted:
		contact_t += delta
	if on:
		on_t += delta
		fill = minf(1.0, fill + delta / fill_time)
	else:
		fill = maxf(0.0, fill - delta / decay_time)
	if over_tight():
		_over_acc += delta
		if _over_acc >= over_chunk:
			_over_acc -= over_chunk
			cost(over_botch, "Too tight: the limb is going purple")
	else:
		_over_acc = 0.0
	_update_progress()
	if fill >= 1.0:
		_lock()


## Right-click, or the meter filling on its own. Below two fifths the windlass has nothing to bite
## on and spins free in your hand.
func _try_lock() -> void:
	if fill < early_fill_min:
		cost(early_botch, "Far too loose: the windlass spun free")
		fill *= early_keep
		_flash = 0.4
		shake(0.5)
		return
	_lock()


func _lock() -> void:
	fill_at_lock = clampf(fill, 0.0, 1.0)
	# How much of the time since you first found the pulse you actually kept the bar on it.
	var frac: float = clampf(on_t / maxf(0.001, contact_t), 0.0, 1.0) if _contacted else 0.0
	var hold_f := 0.75 + 0.25 * frac
	quality = clampf(place_q * fill_at_lock * hold_f, 0.0, 1.0)
	stage = Stage.LOCKED
	lock_t = 0.0
	held = false
	progress = 0.97
	var b = body()
	if b != null and b.has_method("set_bleeding"):
		b.set_bleeding(String(ctx.get("step", {}).get("site", "limb")), 0.0)


func _update_progress() -> void:
	match stage:
		Stage.PLACE:
			progress = 0.05
		Stage.TIGHTEN:
			progress = 0.2 + 0.75 * clampf(fill, 0.0, 1.0)
		_:
			progress = 0.97


## A jerk on the table knocks the crank back out of your hand.
func on_jolt(_offset: Vector2, strength: float, _duration: float) -> void:
	shake(clampf(0.4 + strength * 0.6, 0.0, 1.0))
	_flash = maxf(_flash, 0.25)
	if stage == Stage.TIGHTEN:
		bar_p = maxf(0.0, bar_p - jolt_drop)
		bar_v = minf(bar_v, 0.0)
	elif stage == Stage.PLACE:
		sweep_x = clampf(sweep_x + (6.0 if _rng.randf() < 0.5 else -6.0), -sweep_half_mm, sweep_half_mm)


func animate(delta: float) -> void:
	_t += delta
	_flash = maxf(0.0, _flash - delta)
	_shown_fill = move_toward(_shown_fill, fill, delta * 1.6)
	_shown_bar = move_toward(_shown_bar, bar_p, delta * 900.0)
	var want_purple: float = 1.0 if (stage == Stage.TIGHTEN and over_tight()) else 0.0
	_purple = move_toward(_purple, want_purple, delta * 3.0)
	var want_blanch: float = 1.0 if (stage != Stage.PLACE and (on_pulse() or stage == Stage.LOCKED)) else 0.0
	_blanch = move_toward(_blanch, want_blanch, delta * 2.0)


# ---------------------------------------------------------------------------- the body

func react() -> void:
	var slipping := slip > 0.0
	if stage != _seen_stage:
		if stage == Stage.TIGHTEN:
			audio(cinch_cue, -2.0)
		elif stage == Stage.LOCKED:
			audio(lock_cue, 0.0)
		_seen_stage = stage
	if slipping != _seen_slip:
		_seen_slip = slipping
		audio(swish_cue, -4.0 if slipping else -9.0, 0.1)
	# The windlass ratchets as the bar climbs: one click every twentieth of the gauge.
	var ri := int(floor(bar_p / maxf(1.0, gauge_max * 0.05)))
	if stage == Stage.TIGHTEN and ri > _ratchet_seen:
		audio(ratchet_cue, ratchet_volume, 0.06)
	if stage == Stage.TIGHTEN and ri != _ratchet_seen:
		_ratchet_seen = ri
	# And the probe beeps on every beat that still gets past the strap; it creaks when it is too tight.
	var beat := int(floor(_t * 1.25))
	if beat != _beat_seen:
		_beat_seen = beat
		if stage == Stage.TIGHTEN and play_state == Play.RUNNING:
			if over_tight():
				audio(creak_cue, -6.0, 0.1)
			elif not on_pulse():
				audio(beat_cue, beat_volume)
	var b = body()
	if b == null:
		_seen_misplaces = misplaces
		return
	if misplaces > _seen_misplaces:
		_seen_misplaces = misplaces
		if b.has_method("stir"):
			b.stir(0.5)
	if b.has_method("set_bleeding") and stage != Stage.LOCKED:
		var site := String(ctx.get("step", {}).get("site", "limb"))
		b.set_bleeding(site, clampf(0.12 + 0.2 * float(misplaces), 0.0, 0.6))


# ---------------------------------------------------------------------------- the diagram

func paint_game(c: CanvasItem) -> void:
	if panel == null:
		return
	var st := style()
	if stage == Stage.PLACE:
		_paint_place(c, st)
	else:
		_paint_tighten(c, st)
	if _flash > 0.0:
		c.draw_rect(Rect2(Vector2.ZERO, panel.tex_size()), Color(st.danger, _flash * 0.22))


# -- stage A ----------------------------------------------------------------------------------

func _limb_rect(half: float, y: float, x0 := -58.0, x1 := 58.0) -> Rect2:
	var a := px(Vector2(x0, y - half))
	var b := px(Vector2(x1, y + half))
	return Rect2(a, b - a)


func _paint_place(c: CanvasItem, st) -> void:
	var y := limb_y_mm
	var h := limb_half_mm
	var limb := _limb_rect(h, y)
	# The arm itself: a plain band running off the diagram at the shoulder end.
	c.draw_rect(limb, Color(st.bg_inner, 1.0))
	st.glow_line(c, px(Vector2(-58.0, y - h)), px(Vector2(58.0, y - h)), st.line, st.thin)
	c.draw_line(px(Vector2(-58.0, y - h)), px(Vector2(58.0, y - h)), st.line, st.outline)
	c.draw_line(px(Vector2(-58.0, y + h)), px(Vector2(58.0, y + h)), st.line, st.outline)
	# A long bone down the middle so the side view reads as an arm and not a pipe.
	st.dashed(c, px(Vector2(-58.0, y)), px(Vector2(58.0, y)), Color(st.bone, 0.30), st.hair, 10.0, 8.0)

	_paint_zones(c, st, y, h)
	_paint_infection(c, st, y, h)
	_paint_scale(c, st, y, h)
	_paint_strap(c, st, y, h)
	_paint_place_readout(c, st)


## Green, amber and red, each with its own pattern as well as its own colour: the green stretch is
## hatched one way, the amber is dotted, the red is crossed.
func _paint_zones(c: CanvasItem, st, y: float, h: float) -> void:
	var g0 := maxf(-58.0, green_from())
	var g1 := minf(58.0, green_to())
	var amber1 := minf(58.0, green_from())
	if amber1 > -58.0:
		var r := _limb_rect(h - 1.0, y, -58.0, amber1)
		c.draw_rect(r, Color(st.sloppy, 0.07))
		_dots(c, r, px_len(4.5), Color(st.sloppy, 0.55), px_len(0.7))
	if g1 > g0:
		var r2 := _limb_rect(h - 1.0, y, g0, g1)
		c.draw_rect(r2, Color(st.good, 0.08))
		_hatch(c, r2, px_len(4.0), Vector2(0.7071, -0.7071), Color(st.good, 0.55), st.hair)
		for gx: float in [g0, g1]:
			c.draw_line(px(Vector2(gx, y - h)), px(Vector2(gx, y + h)), Color(st.good, 0.85), st.thin)
	var rf := maxf(-58.0, red_from())
	if rf < 58.0:
		var r3 := _limb_rect(h - 1.0, y, rf, 58.0)
		c.draw_rect(r3, Color(st.danger, 0.09))
		_hatch(c, r3, px_len(3.6), Vector2(0.7071, 0.7071), Color(st.danger, 0.55), st.hair)
		_hatch(c, r3, px_len(3.6), Vector2(0.7071, -0.7071), Color(st.danger, 0.55), st.hair)
		c.draw_line(px(Vector2(rf, y - h)), px(Vector2(rf, y + h)), st.danger, st.thin)


## The rot, with a ragged margin, from the front out to the dead end of the limb.
func _paint_infection(c: CanvasItem, st, y: float, h: float) -> void:
	if front >= 58.0:
		return
	var top := y - h
	var bot := y + h
	var pts := PackedVector2Array()
	for i in 11:
		var f := float(i) / 10.0
		var jag: float = sin(f * 9.0 + _jag) * 2.1 + sin(f * 23.0 + _jag * 1.7) * 1.0
		pts.append(px(Vector2(front + jag, lerpf(top, bot, f))))
	pts.append(px(Vector2(58.0, bot)))
	pts.append(px(Vector2(58.0, top)))
	c.draw_colored_polygon(pts, Color(st.blood_dark, 0.94))
	var body_r := _limb_rect(h - 0.6, y, minf(57.0, front + 3.0), 58.0)
	if body_r.size.x > 1.0:
		_hatch(c, body_r, px_len(3.0), Vector2(0.7071, 0.7071), Color(st.blood, 0.8), st.hair)
		var rng := RandomNumberGenerator.new()
		rng.seed = int(ctx.get("seed", 1)) ^ 0x1c0a
		for i in 22:
			var sx: float = lerpf(front + 2.0, 57.0, rng.randf())
			var sy: float = lerpf(top + 1.5, bot - 1.5, rng.randf())
			c.draw_circle(px(Vector2(sx, sy)), px_len(rng.randf_range(0.6, 1.7)), Color(st.blood, 0.75))
	var edge := PackedVector2Array()
	for i in 11:
		edge.append(pts[i])
	st.glow_poly(c, edge, st.danger, st.thin)
	c.draw_polyline(edge, st.danger, st.outline)


func _paint_scale(c: CanvasItem, st, y: float, h: float) -> void:
	var base := y + h + 3.0
	c.draw_line(px(Vector2(-56.0, base)), px(Vector2(56.0, base)), Color(st.line_dim, 0.7), st.hair)
	var mm := -50.0
	while mm <= 50.0:
		var long: bool = absf(mm) < 0.5 or absf(fmod(mm, 50.0)) < 0.5
		c.draw_line(px(Vector2(mm, base)), px(Vector2(mm, base + (4.0 if long else 2.0))),
			Color(st.line_dim, 0.9 if long else 0.5), st.hair)
		mm += 10.0
	var font := ThemeDB.fallback_font
	c.draw_string(font, px(Vector2(-1.6, base + 10.5)), "0", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 17,
		Color(st.line_dim, 0.9))


## The open strap: the whole width of it hangs across the limb, and the bright line down the middle
## is the bit that gets judged.
func _paint_strap(c: CanvasItem, st, y: float, h: float) -> void:
	var x := sweep_x
	var drop := 0.0
	var alpha := 1.0
	if slip > 0.0:
		x += slip * slip * 26.0
		drop = slip * 14.0
		alpha = 1.0 - smoothstep(0.55, 1.0, slip)
	if alpha <= 0.01:
		return
	var hw := strap_w_mm * 0.5
	var top := y - h - 6.0 + drop
	var bot := y + h + 6.0 + drop
	var a := px(Vector2(x - hw, top))
	var b := px(Vector2(x + hw, bot))
	var body_rect := Rect2(a, b - a)
	c.draw_rect(body_rect, Color(st.bg, 0.55 * alpha))
	c.draw_rect(body_rect, Color(st.steel, 0.8 * alpha), false, st.thin)
	# Webbing, so it reads as a strap.
	var wy := top + 3.0
	while wy < bot:
		c.draw_line(px(Vector2(x - hw, wy)), px(Vector2(x + hw, wy)), Color(st.steel, 0.2 * alpha), st.hair)
		wy += 3.0
	# The windlass sitting on top of it.
	var wa := px(Vector2(x - 7.0, top - 6.0))
	var wb := px(Vector2(x + 7.0, top - 0.5))
	c.draw_rect(Rect2(wa, wb - wa), Color(st.steel, 0.85 * alpha))
	c.draw_line(px(Vector2(x - 11.0, top - 3.2)), px(Vector2(x + 11.0, top - 3.2)), Color(st.danger, alpha), st.outline)
	# The centre line and the mark under it, which says what would happen if you clicked now.
	var mark: int = placement_at(x)
	var col: Color = st.good
	if mark == PLACE_FAR:
		col = st.sloppy
	elif mark == PLACE_BAD:
		col = st.danger
	st.glow_line(c, px(Vector2(x, top)), px(Vector2(x, bot)), col, st.thin)
	c.draw_line(px(Vector2(x, top)), px(Vector2(x, bot)), Color(col, alpha), st.outline)
	_verdict_mark(c, st, Vector2(x, bot + 7.0), mark, col, alpha)


## The same verdict again as a shape, for anyone who cannot use the colour: a tick, a ring, a cross.
func _verdict_mark(c: CanvasItem, st, at: Vector2, mark: int, col: Color, alpha: float) -> void:
	var w: float = st.outline
	match mark:
		PLACE_GOOD:
			c.draw_line(px(at + Vector2(-3.4, -0.4)), px(at + Vector2(-1.0, 2.6)), Color(col, alpha), w)
			c.draw_line(px(at + Vector2(-1.0, 2.6)), px(at + Vector2(3.6, -3.0)), Color(col, alpha), w)
		PLACE_FAR:
			c.draw_arc(px(at), px_len(3.2), 0.0, TAU, 18, Color(col, alpha), w)
		_:
			c.draw_line(px(at + Vector2(-3.2, -3.2)), px(at + Vector2(3.2, 3.2)), Color(col, alpha), w)
			c.draw_line(px(at + Vector2(-3.2, 3.2)), px(at + Vector2(3.2, -3.2)), Color(col, alpha), w)


func _paint_place_readout(c: CanvasItem, st) -> void:
	var font := ThemeDB.fallback_font
	var d := above_front(sweep_x)
	var txt := "%.1f cm OF CLEAN ARM" % (maxf(0.0, d) * 0.1)
	if slip > 0.0:
		txt = "SLIPPED OFF"
	var col: Color = Color(st.line_dim, 0.95)
	if placement_at(sweep_x) == PLACE_BAD:
		col = st.danger
	var w: float = font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
	c.draw_string(font, px(Vector2(0.0, 31.0)) + Vector2(-w * 0.5, 0.0), txt,
		HORIZONTAL_ALIGNMENT_LEFT, -1.0, 20, col)
	# Which way the strap is travelling, as a pair of chevrons on the sweep's rail.
	var rail := 34.5
	c.draw_line(px(Vector2(-sweep_half_mm, rail)), px(Vector2(sweep_half_mm, rail)), Color(st.line_dim, 0.4), st.hair)
	for k in 2:
		var cx: float = sweep_x + sweep_dir * (2.5 + 3.0 * float(k))
		c.draw_line(px(Vector2(cx - sweep_dir * 2.2, rail - 2.2)), px(Vector2(cx, rail)), Color(st.line_dim, 0.8), st.hair)
		c.draw_line(px(Vector2(cx - sweep_dir * 2.2, rail + 2.2)), px(Vector2(cx, rail)), Color(st.line_dim, 0.8), st.hair)


# -- stage B ----------------------------------------------------------------------------------

const GAUGE_X0 := 12.0
const GAUGE_X1 := 36.0
const GAUGE_TOP := -30.0
const GAUGE_BOT := 30.0


func _p_to_y(p: float) -> float:
	return lerpf(GAUGE_BOT, GAUGE_TOP, clampf(p / maxf(1.0, gauge_max), 0.0, 1.0))


func _paint_tighten(c: CanvasItem, st) -> void:
	_paint_cinched_limb(c, st)
	_paint_meter(c, st)
	_paint_gauge(c, st)


## The limb again, smaller, with the strap on it and the colour of what you are doing to it.
func _paint_cinched_limb(c: CanvasItem, st) -> void:
	var y := -17.0
	var h := 10.0
	var limb := _limb_rect(h, y, -56.0, -4.0)
	c.draw_rect(limb, Color(st.bg_inner, 1.0))
	c.draw_line(px(Vector2(-56.0, y - h)), px(Vector2(-4.0, y - h)), st.line, st.outline)
	c.draw_line(px(Vector2(-56.0, y + h)), px(Vector2(-4.0, y + h)), st.line, st.outline)
	if _blanch > 0.01:
		c.draw_rect(limb, Color(st.line, 0.16 * _blanch))
	if _purple > 0.01:
		# Too tight reads as a colour AND as a hard cross-hatch closing over the limb.
		c.draw_rect(limb, Color(0.42, 0.13, 0.52, 0.45 * _purple))
		_hatch(c, limb, px_len(3.0), Vector2(0.7071, 0.7071), Color(0.78, 0.45, 0.95, 0.8 * _purple), st.hair)
		_hatch(c, limb, px_len(3.0), Vector2(0.7071, -0.7071), Color(0.78, 0.45, 0.95, 0.8 * _purple), st.hair)
	# The strap, cinched, where you put it.
	var sx: float = clampf(strap_x, -46.0, -12.0)
	var hw := strap_w_mm * 0.28
	var a := px(Vector2(sx - hw, y - h - 2.0))
	var b := px(Vector2(sx + hw, y + h + 2.0))
	c.draw_rect(Rect2(a, b - a), Color(st.bg, 0.8))
	c.draw_rect(Rect2(a, b - a), st.steel, false, st.thin)
	var rod := px(Vector2(sx, y - h - 6.0))
	c.draw_line(rod + Vector2(-px_len(9.0), 0.0), rod + Vector2(px_len(9.0), 0.0), st.danger, st.outline)
	c.draw_circle(rod, px_len(2.0), st.danger)
	var font := ThemeDB.fallback_font
	if _purple > 0.5:
		c.draw_string(font, px(Vector2(-56.0, y - h - 9.0)), "TOO TIGHT", HORIZONTAL_ALIGNMENT_LEFT,
			-1.0, 20, Color(0.85, 0.5, 1.0, 0.6 + 0.4 * sin(_t * 14.0)))


## The occlusion meter: ten cells, and a notch at the fraction below which the windlass spins free.
func _paint_meter(c: CanvasItem, st) -> void:
	var x0 := -56.0
	var x1 := -4.0
	var y0 := 9.0
	var y1 := 19.0
	var a := px(Vector2(x0, y0))
	var b := px(Vector2(x1, y1))
	c.draw_rect(Rect2(a, b - a), Color(st.bg, 0.7))
	c.draw_rect(Rect2(a, b - a), Color(st.line_dim, 0.9), false, st.thin)
	var cells := 10
	for i in cells:
		var f0: float = float(i) / float(cells)
		if f0 + 0.001 > _shown_fill:
			break
		var f1: float = minf(float(i + 1) / float(cells), _shown_fill)
		var ca := px(Vector2(lerpf(x0, x1, f0) + 0.4, y0 + 1.2))
		var cb := px(Vector2(lerpf(x0, x1, f1) - 0.4, y1 - 1.2))
		var cell := Rect2(ca, cb - ca)
		if cell.size.x <= 0.5:
			continue
		c.draw_rect(cell, Color(st.good, 0.45))
		_hatch(c, cell, px_len(2.4), Vector2(0.7071, -0.7071), Color(st.good, 0.95), st.hair)
	var nx: float = lerpf(x0, x1, early_fill_min)
	c.draw_line(px(Vector2(nx, y0 - 2.5)), px(Vector2(nx, y1 + 2.5)), Color(st.sloppy, 0.9), st.thin)
	var font := ThemeDB.fallback_font
	c.draw_string(font, px(Vector2(x0, y0 - 2.5)), "OCCLUSION", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 18,
		Color(st.line_dim, 0.95))
	c.draw_string(font, px(Vector2(nx + 1.5, y1 + 8.0)), "CLIP HOLDS", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 16,
		Color(st.sloppy, 0.85))
	var pct := "%3d%%" % int(round(_shown_fill * 100.0))
	var w: float = font.get_string_size(pct, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
	c.draw_string(font, px(Vector2(x1, y0 - 2.5)) + Vector2(-w, 0.0), pct, HORIZONTAL_ALIGNMENT_LEFT,
		-1.0, 18, Color(st.line, 0.95))


func _paint_gauge(c: CanvasItem, st) -> void:
	var font := ThemeDB.fallback_font
	var a := px(Vector2(GAUGE_X0, GAUGE_TOP))
	var b := px(Vector2(GAUGE_X1, GAUGE_BOT))
	var box := Rect2(a, b - a)
	c.draw_rect(box, Color(st.bg, 0.85))
	st.glow_rect(c, box, st.line_dim)
	c.draw_rect(box, Color(st.line_dim, 0.95), false, st.thin)
	var p := 0.0
	while p <= gauge_max + 0.5:
		var yy := _p_to_y(p)
		var long: bool = fmod(p, 150.0) < 0.5
		c.draw_line(px(Vector2(GAUGE_X1, yy)), px(Vector2(GAUGE_X1 + (4.5 if long else 2.5), yy)),
			Color(st.line_dim, 0.9 if long else 0.5), st.hair)
		if long:
			c.draw_string(font, px(Vector2(GAUGE_X1 + 6.0, yy + 2.2)), "%d" % int(p),
				HORIZONTAL_ALIGNMENT_LEFT, -1.0, 16, Color(st.line_dim, 0.9))
		p += 50.0
	c.draw_string(font, px(Vector2(GAUGE_X0, GAUGE_TOP - 3.0)), "mmHg", HORIZONTAL_ALIGNMENT_LEFT,
		-1.0, 17, Color(st.line_dim, 0.95))

	# Your bar.
	var hb := bar_half()
	var top := _p_to_y(_shown_bar + hb)
	var bot := _p_to_y(_shown_bar - hb)
	var ba := px(Vector2(GAUGE_X0 + 1.0, top))
	var bb := px(Vector2(GAUGE_X1 - 1.0, bot))
	var bar := Rect2(ba, bb - ba)
	var bcol: Color = st.steel
	if stage == Stage.TIGHTEN and over_tight():
		bcol = Color(0.78, 0.45, 0.95)
	elif on_pulse() or stage == Stage.LOCKED:
		bcol = st.good
	c.draw_rect(bar, Color(bcol, 0.30))
	st.glow_rect(c, bar, bcol)
	c.draw_rect(bar, bcol, false, st.thin)
	# Knurling across the bar, so its extent reads without the fill colour.
	var ky := _shown_bar - hb + 4.0
	while ky < _shown_bar + hb - 1.0:
		c.draw_line(px(Vector2(GAUGE_X0 + 2.5, _p_to_y(ky))), px(Vector2(GAUGE_X1 - 2.5, _p_to_y(ky))),
			Color(bcol, 0.35), st.hair)
		ky += 8.0

	# The pulse marker: an arrowhead on the left and a beat drawn across the gauge.
	var pp := pulse_now()
	var py := _p_to_y(pp)
	var tri := PackedVector2Array([px(Vector2(GAUGE_X0 - 7.5, py - 3.2)), px(Vector2(GAUGE_X0 - 7.5, py + 3.2)),
		px(Vector2(GAUGE_X0 - 1.0, py))])
	c.draw_colored_polygon(tri, st.danger)
	var beat := PackedVector2Array()
	var steps := 14
	var wave: Array = [0.0, 0.0, -0.6, 0.3, -2.6, 3.4, -1.2, 0.2, 0.0, 0.0, 0.5, 0.0, 0.0, 0.0, 0.0]
	for i in steps + 1:
		var f: float = float(i) / float(steps)
		var xx: float = lerpf(GAUGE_X0 + 0.5, GAUGE_X1 - 0.5, f)
		beat.append(px(Vector2(xx, py + float(wave[i]))))
	st.glow_poly(c, beat, st.danger, st.hair)
	c.draw_polyline(beat, st.danger, st.thin)
	var lbl := "%d" % int(round(pp))
	c.draw_string(font, px(Vector2(GAUGE_X0 - 9.0, py + 10.0)) - Vector2(font.get_string_size(lbl,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x, 0.0), lbl, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 16,
		Color(st.danger, 0.9))


# -- pattern helpers ----------------------------------------------------------------------------

## Liang-Barsky: the part of segment a..b that is inside `r`, or an empty array.
func _clip_seg(r: Rect2, a: Vector2, b: Vector2) -> Array:
	var d := b - a
	var t0 := 0.0
	var t1 := 1.0
	for i in 4:
		var p := 0.0
		var q := 0.0
		match i:
			0:
				p = -d.x
				q = a.x - r.position.x
			1:
				p = d.x
				q = r.end.x - a.x
			2:
				p = -d.y
				q = a.y - r.position.y
			_:
				p = d.y
				q = r.end.y - a.y
		if absf(p) < 0.00001:
			if q < 0.0:
				return []
		else:
			var t := q / p
			if p < 0.0:
				t0 = maxf(t0, t)
			else:
				t1 = minf(t1, t)
	if t0 > t1:
		return []
	return [a + d * t0, a + d * t1]


## Parallel rules across a rect, clipped to it. Everything the colour says, the pattern says too.
func _hatch(c: CanvasItem, r: Rect2, step: float, dir: Vector2, col: Color, w: float) -> void:
	if r.size.x <= 0.5 or r.size.y <= 0.5 or step < 1.0:
		return
	var n := dir.orthogonal().normalized()
	var span: float = absf(r.size.x * n.x) + absf(r.size.y * n.y)
	var reach: float = r.size.length()
	var mid := r.get_center()
	var k := -span * 0.5
	while k <= span * 0.5:
		var seg := _clip_seg(r, mid + n * k - dir * reach, mid + n * k + dir * reach)
		if seg.size() == 2:
			c.draw_line(seg[0], seg[1], col, w)
		k += step


func _dots(c: CanvasItem, r: Rect2, step: float, col: Color, radius: float) -> void:
	if r.size.x <= 0.5 or r.size.y <= 0.5 or step < 1.0:
		return
	var yy: float = r.position.y + step * 0.5
	var row := 0
	while yy < r.end.y:
		var xx: float = r.position.x + step * (0.5 if row % 2 == 0 else 1.0)
		while xx < r.end.x:
			c.draw_circle(Vector2(xx, yy), radius, col)
			xx += step
		yy += step
		row += 1


# ---------------------------------------------------------------------------- net

## Everything a spectator needs to watch someone else make a mess of it.
##
## NOTHING that creeps is snapped here. `front` moves 0.025 mm a frame and `fill` 0.004, and the lab
## and the bot round-trip this dictionary through apply_net_state EVERY frame, so either of them
## snapped to its own quantum would simply never move. Snap what jumps; send what creeps.
func net_pack() -> Dictionary:
	return {
		"st": stage, "sx": sweep_x, "sd": sweep_dir, "sl": slip, "fr": front,
		"mp": misplaces, "pq": snappedf(place_q, 0.01), "px": snappedf(strap_x, 0.2),
		"bp": bar_p, "bv": bar_v, "fl": fill, "tt": tight_t,
		"ot": on_t, "ct": contact_t, "hd": held, "lt": lock_t,
		"fal": snappedf(fill_at_lock, 0.01),
	}


func net_apply(s: Dictionary) -> void:
	stage = int(s.get("st", stage))
	sweep_x = float(s.get("sx", sweep_x))
	sweep_dir = float(s.get("sd", sweep_dir))
	slip = float(s.get("sl", slip))
	front = float(s.get("fr", front))
	misplaces = int(s.get("mp", misplaces))
	place_q = float(s.get("pq", place_q))
	strap_x = float(s.get("px", strap_x))
	bar_p = float(s.get("bp", bar_p))
	bar_v = float(s.get("bv", bar_v))
	fill = float(s.get("fl", fill))
	tight_t = float(s.get("tt", tight_t))
	on_t = float(s.get("ot", on_t))
	contact_t = float(s.get("ct", contact_t))
	held = bool(s.get("hd", held))
	lock_t = float(s.get("lt", lock_t))
	fill_at_lock = float(s.get("fal", fill_at_lock))
	if contact_t > 0.0:
		_contacted = true


# ---------------------------------------------------------------------------- bot

## A good hand puts the strap in the middle of the band and leads the bar onto the pulse. A bad one
## aims from a golden-ratio sequence -- the same wrong hand every run, no dice anywhere -- lands on
## the rot at least once, then panics at the gauge, overshoots, and grabs at the clip far too early.
func bot_input(t: float, skill: float) -> Dictionary:
	var dt: float = clampf(t - _bt, 0.0, 0.1)
	_bt = t
	skill = clampf(skill, 0.0, 1.0)
	if not armed():
		return {"cursor": Vector2.ZERO, "buttons": 0}
	match stage:
		Stage.PLACE:
			return {"cursor": Vector2.ZERO, "buttons": _bot_place(dt, skill)}
		Stage.TIGHTEN:
			return {"cursor": Vector2.ZERO, "buttons": _bot_tighten(dt, skill)}
	return {"cursor": Vector2.ZERO, "buttons": 0}


func _bot_place(dt: float, skill: float) -> int:
	if slip > 0.0:
		_b_press = 0
		return 0
	if _b_attempt != misplaces:
		_b_attempt = misplaces
		_b_seq += 1
		var u: float = fposmod(float(_b_seq) * PHI, 1.0)
		# Each go is tighter than the last, so even a hopeless hand gets it on eventually.
		var spread: float = lerpf(bot_place_err, 1.5, skill) * pow(0.42, float(misplaces))
		_b_want = (u - 0.5) * 2.0 * spread
		if skill < 0.5 and misplaces == 0:
			# A panicking hand goes for the middle of the arm, which is the rot. Same as the legacy
			# bot: the first strap of a bad run lands on the infection and slides straight off.
			_b_want = band_centre_mm + 12.0
		_b_wait = lerpf(0.30, 0.0, skill)
		_b_press = 0
	_b_wait = maxf(0.0, _b_wait - dt)
	if _b_press > 0:
		_b_press -= 1
		return BUTTON_PRIMARY
	var target: float = clampf(front - band_centre_mm + _b_want, -sweep_half_mm + 1.0, sweep_half_mm - 1.0)
	if _b_wait <= 0.0 and absf(sweep_x - target) <= sweep_speed * maxf(dt, 1.0 / 60.0) * 1.6:
		_b_press = 2
		return BUTTON_PRIMARY
	return 0


func _bot_tighten(dt: float, skill: float) -> int:
	var pp := pulse_now()
	var btn := 0
	if skill >= 0.5:
		# Lead the bar: release before it gets there or the momentum carries it over the pulse.
		if bar_p + bar_v * bot_lead < pp:
			btn |= BUTTON_PRIMARY
		return btn
	_b_mode_t += dt
	if _b_mode_t >= bot_dither or _b_seq2 == 0:
		_b_mode_t = 0.0
		_b_seq2 += 1
		var u: float = fposmod(float(_b_seq2) * PHI, 1.0)
		# It flails wide at first and settles down as the panic wears off.
		var spread: float = lerpf(bot_press_err, 10.0, clampf(tight_t / 18.0, 0.0, 1.0))
		_b_want = pp + (u - 0.5) * 2.0 * spread
	if bar_p + bar_v * 0.10 < _b_want:
		btn |= BUTTON_PRIMARY
	# It grabs at the clip far too early, again and again, because the first time it spun free and it
	# does not know why. After that it takes the meter the moment it looks like enough -- which is the moment
	# it is barely enough.
	if _b_grabs < bot_panic_grabs:
		if fill >= bot_grab_fill * float(_b_grabs + 1):
			_b_grabs += 1
			btn |= BUTTON_SECONDARY
	elif fill >= early_fill_min + 0.08:
		btn |= BUTTON_SECONDARY
	return btn


# ---------------------------------------------------------------------------- self-test

## Headless check: `tools/minigame_lab.tscn -- --selftest=tourniquet:arcade`.
## Targets: skill 1.0 finishes in 8-20 s losing 0-2 vitals; skill 0.0 under 40 s losing 15-25.
static func self_test() -> Array:
	var script: GDScript = load("res://scripts/surgery/arcade/squeeze_arcade.gd")
	var out := []
	var ok := true
	var sloppy: Array = []
	var qs := {}
	for sed: float in [1.0, 0.3]:
		for pid: String in ["bob", "seal"]:
			for skill: float in [1.0, 0.5, 0.0]:
				var g = script.new()
				var tally := {"n": 0, "v": 0.0, "done": false, "q": 0.0, "reasons": {}}
				g.botched.connect(func(a, r): tally.n += 1; tally.v += a; tally.reasons[r] = int(tally.reasons.get(r, 0)) + 1)
				g.finished.connect(func(r): tally.done = true; tally.q = float(r.get("tourniquet", 0.0)))
				g.setup(_case(pid, sed))
				var t: float = run_bot(g, skill, sed, hash(pid) + int(skill * 100))
				print("[squeeze-arcade self-test] %-4s skill=%.1f sed=%.1f  %s  misplaced=%d  fill=%.2f  time=%5.1fs  botches=%2d vitals=%5.1f  tourniquet=%.2f  %s" % [
					pid, skill, sed, "DONE" if tally.done else "UNFINISHED", g.misplaces,
					g.fill_at_lock, t, tally.n, tally.v, tally.q, str(tally.reasons)])
				out.append({"patient": pid, "skill": skill, "sedation": sed, "done": tally.done,
					"time": t, "vitals": tally.v, "tourniquet": tally.q, "misplaces": g.misplaces})
				if sed > 0.9:
					qs["%s|%.1f" % [pid, skill]] = tally.q
					if skill == 1.0:
						if not tally.done or t < 8.0 or t > 20.0 or tally.v > 2.0:
							print("[squeeze-arcade self-test] MISS: skill 1.0 wants 8-20 s and 0-2 vitals")
							ok = false
					if skill == 0.0:
						sloppy.append(tally.v)
						if not tally.done or t > 40.0:
							print("[squeeze-arcade self-test] MISS: skill 0.0 wants to finish under 40 s")
							ok = false
				elif not tally.done:
					print("[squeeze-arcade self-test] MISS: an unsedated patient still has to finish")
					ok = false
				g.free()
	# The sloppy band on the mean: which side of the band a seeded sweep happens to put the strap
	# swings one patient a few vitals either side of the other on its own.
	var mean := 0.0
	for v: float in sloppy:
		mean += v
	mean /= maxf(1.0, float(sloppy.size()))
	print("[squeeze-arcade self-test] skill 0.0 mean vitals %.1f across %d patients (want 15-25)" % [mean, sloppy.size()])
	if mean < 15.0 or mean > 25.0:
		print("[squeeze-arcade self-test] MISS: skill 0.0 wants 15-25 vitals on average")
		ok = false
	# CARRY-FORWARD OUT: the one number SAW! and WRAP! read.
	for pid: String in ["bob", "seal"]:
		var good: float = float(qs.get("%s|1.0" % pid, 0.0))
		var bad: float = float(qs.get("%s|0.0" % pid, 1.0))
		print("[squeeze-arcade self-test] %-4s tourniquet: skill 1.0 -> %.2f, skill 0.0 -> %.2f" % [pid, good, bad])
		if good < 0.85:
			print("[squeeze-arcade self-test] MISS: a clean run should hand SAW! a tourniquet near 1.0")
			ok = false
		if bad > good - 0.2:
			print("[squeeze-arcade self-test] MISS: a botched run should hand SAW! a much worse tourniquet")
			ok = false
	# CARRY-FORWARD IN: sedation, and whether you can actually see it in the pulse.
	for pid: String in ["bob", "seal"]:
		var calm := _pulse_spread(script, pid, 1.0)
		var jumpy := _pulse_spread(script, pid, 0.3)
		print("[squeeze-arcade self-test] %-4s pulse noise: sedation 1.0 -> +/-%.0f mmHg (swing %.0f), 0.3 -> +/-%.0f mmHg (swing %.0f)" % [
			pid, calm[0], calm[1], jumpy[0], jumpy[1]])
		out.append({"patient": pid, "noise_sed_1": calm[0], "noise_sed_03": jumpy[0]})
		if jumpy[0] < calm[0] * 1.8 or jumpy[1] < calm[1] * 1.5:
			print("[squeeze-arcade self-test] MISS: a badly sedated patient must have a visibly jumpier pulse")
			ok = false
	print("[squeeze-arcade self-test] %s" % ("PASS" if ok else "FAIL"))
	return out


static func _case(pid: String, sed: float) -> Dictionary:
	return {"patient_id": pid, "patient": Procedures.patient(pid), "ailment_id": "amputation",
		"step": Procedures.step("amputation", 1), "variant": "", "shift": 1,
		"difficulty": Procedures.difficulty(1), "flags": {"sedation": sed},
		"seed": hash("squeeze" + pid), "body": null, "operator": true, "operating": true}


## [the noise amplitude the formula asks for, the peak-to-peak the marker actually makes in 30 s].
static func _pulse_spread(script: GDScript, pid: String, sed: float) -> Array:
	var g = script.new()
	g.setup(_case(pid, sed))
	var lo := INF
	var hi := -INF
	for i in 1800:
		var p: float = g.pulse_at(float(i) / 60.0)
		lo = minf(lo, p)
		hi = maxf(hi, p)
	var r := [g.noise_amp(), hi - lo]
	g.free()
	return r
