extends "res://scripts/surgery/arcade/arcade_game.gd"
## ARCADE SURGERY (docs/ARCADE_SURGERY.md 5.1) -- the ANESTHETIC INJECTION. Step "sedate" (`anesthetic`,
## site `injection`): GW step 1 and AM step 1. The only sedation game; the spec it was built from is
## docs/ANESTHETIC_INJECTION_SPEC.md, and its "Decisions" section is what won where they disagree.
##
## Three movements on one paper panel, drawn in the ink look (scripts/surgery/panel/ink.gd) this game
## pilots for every other panel:
##   DRAW!   The syringe hangs needle-up in an upside-down vial. Hold left to draw the plunger back;
##           it speeds up the longer you hold, so overshooting is the risk. Right mouse or the wheel
##           puts some back. Land the level in the green band, which sits where THIS patient's
##           weight says (the seal needs more, so its band is higher up the barrel). Hold too long, or
##           draw from an empty vial, and you pull in a big air bubble. Space (or Done) moves on.
##   FLICK!  Bubbles in the barrel. Loose ones rise; click the barrel to flick them up. Amber ones
##           stuck to the wall need a flick right beside them. Tap the thumb pad to purge a bubble
##           that has reached the needle end -- tap with nothing there and you squirt drug out.
##           Space (or Continue) moves on whenever you like: what is left goes into the patient.
##   STICK!  The forearm (or flipper). Slap it bare-handed to raise the veins for a moment, take the
##           syringe off the tray, set the angle with the wheel (or A/D), and hold to push the needle
##           in. Blood flashes into the hub when the tip is in a vein at a shallow angle to it: let go
##           and it is in. Push on past the flash and you blow the vein. Let go with nothing and you
##           have made a hole. Then PUSH!: hold to push the plunger, gently -- the meter goes red if
##           you shove it -- until the barrel is empty.
##   The tourniquet button pins the veins up for a while. It uses up a real tourniquet from your
##   hands and is greyed out when you have none to spare.
##
## Costs are live: every mistake is billed the moment it happens, with a reason said out loud (the
## spec's results-card penalties times `vitals_per_point`). Result {"sedation": s}: in the band is a
## clean ~1.0; outside it the ratio itself carries on, so an underdose still stirs in every later step
## and SQUEEZE! reads it for pulse noise. `quality` is the spec's score / 100.
##
## Space: the spec's 960 x 600 reference px, drawn on the panel's 120 x 80 mm diagram at 8 px/mm (the
## spare 5 mm is split top and bottom). Every rule below is in reference px ("rpx").
##
## A signal (`spiked`) goes out at every one of the spec's spike() sites -- air drawn, purge below the
## band, slap, miss, blown vein, tourniquet timeout, fast push, and the two billed at delivery (a
## bubble going in, the dose) -- so vitals, audio or co-op reactions can hang off them later.

## A mistake (or a heart-rate moment) the spec marks with spike(). `kind` is one of: air, purge_low,
## slap, miss, blown, tourniquet_timeout, fast_push, bubble, dose. Emitted on the operator's machine.
signal spiked(kind: String)

enum Phase { DRAW, DEBUBBLE, INJECT, DONE }

const REF := Vector2(960.0, 600.0)

# -- layout, reference px (the spec's; not tuning) -------------------------------------------------
const SYR_X := 430.0
const BARREL_HALF := 46.0
const BARREL_Y0 := 232.0
const BARREL_Y1 := 508.0
const FLUID_TOP := 240.0
const TRAVEL := 250.0
const VIAL := Rect2(388.0, 56.0, 84.0, 90.0)
const VIAL_NECK_Y := 168.0
const NEEDLE_TIP_Y := 104.0
const HUB_Y := 214.0
const TRAY := Vector2(127.0, 106.0)
const TRAY_R := Vector2(96.0, 40.0)
const DONE_BTN := Rect2(712.0, 498.0, 170.0, 52.0)
const TQ_BTN := Rect2(772.0, 26.0, 168.0, 50.0)
const TQ_BAR := Rect2(34.0, 20.0, 190.0, 10.0)
const METER := Rect2(900.0, 318.0, 24.0, 220.0)
const ASM_BARREL := 64.0
const ASM_NEEDLE := 62.0
const ASM_TIP := 126.0

# -- the dose -------------------------------------------------------------------------------------
@export_group("Dose")
## The dose by weight, and the barrel it is measured in. Bob (82 kg) needs 4.1 ml, the seal (130 kg)
## 6.5, so on a 10 ml barrel their bands sit at 0.41 and 0.65 of the way down.
@export_range(0.005, 0.2, 0.001) var ml_per_kg := 0.05
@export_range(2.0, 30.0, 0.5) var barrel_ml := 10.0
## Half the band, as a share of the barrel. Divided by the difficulty factor.
@export_range(0.01, 0.2, 0.005) var band_half := 0.05
## A seeded nudge to the band's centre either way, share of the barrel. 0: the weight alone decides.
@export_range(0.0, 0.2, 0.005) var band_jitter := 0.0
@export_range(0.0, 1.0, 0.01) var vial_start := 0.90
## Draw speed = draw_base + seconds held x draw_accel (barrel shares per second). Accel x difficulty.
@export_range(0.0, 0.5, 0.005) var draw_base := 0.05
@export_range(0.05, 0.5, 0.01) var draw_accel := 0.22
@export_range(0.05, 1.0, 0.01) var return_rate := 0.25
@export_range(0.005, 0.1, 0.005) var scroll_return := 0.02
## Hold longer than this (divided by difficulty), or draw from an empty vial for air_sustain, and a big
## air bubble comes in.
@export_range(0.5, 6.0, 0.1) var air_hold := 2.8
@export_range(0.05, 1.0, 0.05) var air_sustain := 0.3
@export_range(4.0, 26.0, 0.5) var air_r := 16.0
## In the band, the result reads as a clean 1.0 give or take this share of the error (the legacy maths).
@export_range(0.0, 1.0, 0.01) var in_band_k := 0.35

# -- the bubbles ----------------------------------------------------------------------------------
@export_group("Bubbles")
## How many (times difficulty, rounded), how big (the top end times difficulty), how many stuck.
@export_range(0, 12) var bubbles_min := 3
@export_range(0, 12) var bubbles_max := 6
@export_range(2.0, 20.0, 0.5) var bubble_r_min := 5.0
@export_range(2.0, 26.0, 0.5) var bubble_r_max := 14.0
@export_range(0, 6) var stuck_count := 2
@export_range(5.0, 40.0, 0.5) var merge_cap := 26.0
## A bubble counts as two when it is bigger than this.
@export_range(4.0, 26.0, 0.5) var big_bubble_r := 12.0
@export_range(0.0, 40.0, 0.5) var rise_base := 9.0
@export_range(0.0, 4.0, 0.05) var rise_per_r := 0.9
@export_range(0.0, 40.0, 0.5) var wobble := 12.0
@export_range(0.1, 10.0, 0.1) var damp_x := 2.5
@export_range(0.1, 10.0, 0.1) var damp_y := 1.4
@export_range(0.0, 200.0, 1.0) var flick_vy_min := 35.0
@export_range(0.0, 200.0, 1.0) var flick_vy_max := 90.0
@export_range(0.0, 200.0, 1.0) var flick_vx := 50.0
## How close to a stuck bubble a flick has to land to knock it off the wall (divided by difficulty).
@export_range(10.0, 200.0, 1.0) var unstick_reach := 85.0
## A purge pops a bubble whose top is this close to the needle end (divided by difficulty).
@export_range(2.0, 60.0, 0.5) var purge_reach := 18.0
@export_range(0.0, 0.05, 0.001) var pop_cost := 0.004
@export_range(0.0, 0.1, 0.001) var squirt_cost := 0.02

# -- the vein and the needle --------------------------------------------------------------------
@export_group("Vein")
## Seconds a slap keeps the veins up (divided by difficulty).
@export_range(0.3, 6.0, 0.05) var vein_fade := 1.5
@export_range(0.05, 1.0, 0.01) var slap_max := 0.3
@export_range(0.05, 0.6, 0.01) var pickup_quick := 0.18
@export_range(8.0, 45.0, 0.5) var angle_min := 8.0
@export_range(30.0, 89.0, 0.5) var angle_max := 80.0
@export_range(0.5, 10.0, 0.5) var scroll_deg := 3.0
@export_range(0.5, 10.0, 0.5) var key_deg := 2.0
@export_range(0.0, 1.0, 0.01) var push_hold := 0.15
## Needle speed into the skin (times difficulty) and how far it can go.
@export_range(5.0, 150.0, 1.0) var insert_speed := 38.0
@export_range(20.0, 80.0, 1.0) var insert_max := 55.0
## The flash wants the tip past this, within tip_tol of a vein (divided by difficulty), at an angle
## to the vein inside [window_lo, window_hi] (the window narrows about its middle with difficulty).
@export_range(0.0, 40.0, 0.5) var flash_min := 14.0
@export_range(2.0, 30.0, 0.5) var tip_tol := 9.0
@export_range(0.0, 45.0, 0.5) var window_lo := 14.0
@export_range(5.0, 60.0, 0.5) var window_hi := 32.0
## Push this far past the flash (divided by difficulty) and the vein blows, for this far either side.
@export_range(2.0, 40.0, 0.5) var blow_past := 12.0
@export_range(5.0, 120.0, 1.0) var blown_half_x := 45.0

@export_group("Push")
@export_range(0.05, 3.0, 0.05) var push_up := 0.55
@export_range(0.05, 3.0, 0.05) var push_down := 0.9
@export_range(0.5, 2.0, 0.05) var push_cap := 1.2
@export_range(0.01, 0.5, 0.005) var drain_k := 0.09
## A push rate over this (divided by difficulty) counts as a fast push every fast_every seconds.
@export_range(0.1, 1.5, 0.01) var fast_rate := 0.55
@export_range(0.1, 3.0, 0.05) var fast_every := 0.9
@export_range(0.0, 3.0, 0.05) var deliver_beat := 0.9

@export_group("Tourniquet")
## The item it spends, how long it holds the veins up, and how the arm reddens under it.
@export var tourniquet_item := "tourniquet"
@export_range(1.0, 30.0, 0.5) var tq_time := 9.0
@export_range(0.0, 1.0, 0.01) var redness_up := 0.10
@export_range(0.0, 1.0, 0.01) var redness_down := 0.03

@export_group("Costs")
## Vitals per point of the spec's score (100 points = a perfect run). 0.25 makes a missed stick 2.0,
## what a miss always cost.
@export_range(0.0, 1.0, 0.01) var vitals_per_point := 0.25
@export_range(0.0, 40.0, 0.5) var pts_miss := 8.0
@export_range(0.0, 60.0, 0.5) var pts_blown := 16.0
@export_range(0.0, 40.0, 0.5) var pts_bubble := 10.0
@export_range(0.0, 40.0, 0.5) var pts_fast := 6.0
@export_range(0.0, 100.0, 1.0) var pts_dose_max := 40.0
@export_range(0.0, 1000.0, 5.0) var pts_dose_slope := 260.0
## The spike sites with no price in the spec. Vitals, not points; 0 by default because what they lead
## to (the bubble, the dose) is billed when it lands.
@export_range(0.0, 10.0, 0.25) var cost_air := 0.0
@export_range(0.0, 10.0, 0.25) var cost_purge_low := 0.0
@export_range(0.0, 10.0, 0.25) var cost_slap := 0.0
@export_range(0.0, 10.0, 0.25) var cost_tourniquet_timeout := 0.0

@export_group("Difficulty")
## Every value marked "difficulty" above goes through factor = difficulty ^ this.
@export_range(0.0, 2.0, 0.05) var difficulty_gain := 0.5

@export_group("Audio")
@export var draw_cue := "surgery_draw"
@export var flick_cue := "surgery_forceps_click"
@export var pop_cue := "dissection_plop"
@export var squirt_cue := "surgery_inject"
@export var slap_cue := "surgery_pack"
@export var stick_cue := "surgery_needle"
@export var blow_cue := "surgery_tear"
@export var push_cue := "surgery_inject"
@export var alarm_cue := "surgery_beep_crit"
@export var tourniquet_cue := "surgery_tourniquet_cinch"
@export_group("")

# ---- replicated ----
var phase: int = Phase.DRAW
var fluid := 0.0                  ## share of the barrel drawn, 0..1
var vial := 0.9                   ## share of the barrel left in the vial
var bubbles: Array = []           ## [x, y, r, vx, vy, stuck(0/1), phase]
var air_drawn := 0                ## air bubbles pulled in
var drawing := false
var held := false                 ## the syringe is in the hand (stage 3)
var grip := Vector2(480.0, 200.0) ## rpx, where the hand holds the assembly
var angle := 25.0                 ## degrees below horizontal
var inserting := false
var sink := 0.0
var entry := Vector2.ZERO
var flashed := false
var flash_adv := 0.0
var locked := false
var rate := 0.0
var dose := 0.0                   ## the share of the barrel locked in
var carried: Array = []           ## radii of the bubbles that went into the push
var billed := 0                   ## of those, how many have gone in so far
var vis := 0.0                    ## vein visibility, 0..1
var tq_on := false
var tq_left := 0.0
var tq_avail := false
var redness := 0.0
var blown_ranges: Array = []      ## [vein index, x lo, x hi]
var punctures: Array = []         ## [x, y]
var bruises: Array = []           ## [x, y]
var ripples: Array = []           ## [x, y, play_t born]
var deliver_t := -1.0
var misses := 0
var blown := 0
var fast_pushes := 0
var slaps := 0
var pops := 0
var squirts := 0
var sedation := 1.0

# ---- from the patient and the seed ----
var target := 0.41                ## share of the barrel the band is centred on
var band := 0.05
var veins: Array = []             ## PackedVector2Array per vein, rpx
var seal := false
var skin_phase := 0.0
var grime_spots: Array = []
var speckles: PackedVector2Array = PackedVector2Array()
var k := 1.0                      ## difficulty factor

# ---- local ----
var _rng := RandomNumberGenerator.new()
var _hold := 0.0
var _air_acc := 0.0
var _air_this_hold := false
var _press_t := -1.0              ## seconds the left button has been down, -1 when up
var _press_at := Vector2.ZERO
var _press_what := ""             ## what the current press started on
var _need_release := false
var _fast_acc := 0.0
var _purge_low_warned := false
var _tq_hand_at_press := -1
var _t := 0.0
var _drops: Array = []            ## [pos, vel, age, color]
var _seen := {}
var _push_snd := 0.0
var _warm := false
var _shown: Array = []            ## bubbles as drawn (spectators ease toward the 20 Hz state)
var _shown_grip := Vector2(480.0, 200.0)

# ---- profiling (the lab's --fps reads prof_line) ----
var prof_line := ""
var _prof := {}
var _prof_frames := 0
var _prof_ops := 0

func _prof_mark(key: String, t0: int) -> void:
	var rec: Array = _prof.get(key, [0, 0])
	rec[0] = int(rec[0]) + Time.get_ticks_usec() - t0
	rec[1] = int(rec[1]) + ink.ops - _prof_ops
	_prof_ops = ink.ops
	_prof[key] = rec

# ---- bot ----
var _bt := 0.0
var _b := {}


# ---------------------------------------------------------------------------- setup

func use_ink() -> bool:
	return true


func ink_unit() -> float:
	return _u()


func card_word_for_start() -> String:
	return "DRAW!"


func build_game() -> void:
	k = pow(diff, difficulty_gain)
	var seed_v := int(ctx.get("seed", 1))
	_rng.seed = seed_v ^ 0x1a5e
	seal = String(ctx.get("patient_id", "bob")) == "seal"
	var weight := float(ctx.get("patient", {}).get("weight_kg", 80.0))
	var ml := clampf(weight * ml_per_kg, 1.0, barrel_ml * 0.9)
	target = clampf(ml / barrel_ml + _rng.randf_range(-band_jitter, band_jitter), 0.15, 0.85)
	band = band_half / k
	vial = vial_start
	skin_phase = _rng.randf_range(0.0, TAU)
	_build_veins()
	grime_spots = InkScript.make_grime(_rng, Rect2(Vector2(40, 60), panel.tex_size() - Vector2(80, 120)))
	speckles = PackedVector2Array()
	for i in 90:
		var x := _rng.randf_range(20.0, 940.0)
		speckles.append(Vector2(x, _rng.randf_range(skin_top(x) + 14.0, 585.0)))
	angle = 25.0
	_refresh_tq()


func _build_veins() -> void:
	veins.clear()
	var n := 2 + (1 if _rng.randf() < 0.5 else 0)
	var lo := 330.0 if seal else 340.0
	var hi := 470.0 if seal else 500.0
	for i in n:
		var base := lerpf(lo, hi, (float(i) + 0.5) / float(n)) + _rng.randf_range(-8.0, 8.0)
		var a1 := _rng.randf_range(10.0, 24.0)
		var k1 := _rng.randf_range(0.004, 0.009)
		var p1 := _rng.randf_range(0.0, TAU)
		var a2 := _rng.randf_range(4.0, 10.0)
		var k2 := _rng.randf_range(0.010, 0.018)
		var p2 := _rng.randf_range(0.0, TAU)
		var pts := PackedVector2Array()
		var x := 50.0
		while x <= 910.0:
			pts.append(Vector2(x, base + sin(k1 * x + p1) * a1 + sin(k2 * x + p2) * a2))
			x += 16.0
		veins.append(pts)


## The wavy top edge of the arm (human) or flipper (seal), rpx.
func skin_top(x: float) -> float:
	if seal:
		return 255.0 + 10.0 * sin(0.004 * x + skin_phase) + (x - 480.0) * 0.025
	return 292.0 + 9.0 * sin(0.004 * x + skin_phase)


func on_skin(p: Vector2) -> bool:
	return p.x > 12.0 and p.x < 948.0 and p.y > skin_top(p.x) + 3.0 and p.y < 592.0


# ---------------------------------------------------------------------------- space

## Canvas px per reference px.
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


func dir() -> Vector2:
	return Vector2(cos(deg_to_rad(angle)), sin(deg_to_rad(angle)))


## Where the tip is right now (rpx).
func tip() -> Vector2:
	if inserting or locked:
		return entry + dir() * sink
	return grip + dir() * ASM_TIP


func seal_y() -> float:
	return FLUID_TOP + fluid * TRAVEL


func pad_y() -> float:
	return BARREL_Y1 + 20.0 + fluid * 52.0


# ---------------------------------------------------------------------------- rules

func _spike(kind: String, vitals: float, reason: String) -> void:
	spiked.emit(kind)
	if vitals > 0.0:
		cost(vitals, reason)


func keys() -> Array:
	match phase:
		Phase.DRAW:
			return [["Hold LMB", "draw"], ["RMB / wheel", "put back"], ["Space", "done"]]
		Phase.DEBUBBLE:
			return [["Click barrel", "flick"], ["Click pad", "purge"], ["Space", "continue"]]
		Phase.INJECT:
			if locked:
				return [["Hold LMB", "push, gently"]]
			if held:
				return [["Wheel / A D", "angle"], ["Hold LMB", "needle in"], ["Let go", "at the flash"]]
			return [["Click skin", "slap"], ["Click tray", "take syringe"]]
	return []


func hint() -> String:
	var base := super.hint()
	if base != "":
		return base
	match phase:
		Phase.DRAW:
			return "Land the level in the green band. It speeds up the longer you hold."
		Phase.DEBUBBLE:
			return "Flick the bubbles up and purge them at the needle. Amber ones need a flick right beside them."
		Phase.INJECT:
			if locked:
				return "Dose delivered." if deliver_t >= 0.0 else "In. Push it slow: keep the meter out of the red."
			if flashed:
				return "In the vein. Let go."
			if held:
				return "Shallow to the vein, and stop at the red flash."
			return "Slap the arm to raise a vein, then take the syringe from the tray."
	return ""


func play(p_mm: Vector2, buttons: int, edges: int, delta: float) -> void:
	var p := ref_of_mm(p_mm)
	var lmb: bool = (buttons & BUTTON_PRIMARY) != 0
	var down: bool = (edges & BUTTON_PRIMARY) != 0
	var notches := 0
	if (buttons & BUTTON_SCROLL_UP) != 0:
		notches += 1
	if (buttons & BUTTON_SCROLL_DOWN) != 0:
		notches -= 1
	var released := false
	var press_len := 0.0
	if lmb:
		if down or _press_t < 0.0:
			_press_t = 0.0
			_press_at = p
			_press_what = _what_at(p)
		else:
			_press_t += delta
	elif _press_t >= 0.0:
		released = true
		press_len = _press_t
		_press_t = -1.0
	match phase:
		Phase.DRAW:
			_play_draw(p, buttons, edges, lmb, down, notches, delta)
		Phase.DEBUBBLE:
			_play_debubble(p, edges, down)
		Phase.INJECT:
			_play_inject(p, buttons, edges, lmb, down, released, press_len, notches, delta)


## What a press at `p` landed on, so a press that starts on a button never also draws or stabs.
func _what_at(p: Vector2) -> String:
	if phase != Phase.INJECT and DONE_BTN.grow(6.0).has_point(p):
		return "done"
	if phase == Phase.INJECT:
		if not locked and TQ_BTN.grow(6.0).has_point(p):
			return "tq"
		if not inserting and not locked and (((p - TRAY) / TRAY_R).length() <= 1.15):
			return "tray"
		if on_skin(p):
			return "skin"
	if phase == Phase.DEBUBBLE:
		if Rect2(SYR_X - 60.0, pad_y() - 24.0, 120.0, 48.0).has_point(p):
			return "pad"
		if Rect2(SYR_X - BARREL_HALF - 34.0, BARREL_Y0 - 10.0, BARREL_HALF * 2.0 + 68.0, BARREL_Y1 - BARREL_Y0 + 14.0).has_point(p):
			return "barrel"
	return ""


# -- DRAW --------------------------------------------------------------------------------------

func _play_draw(p: Vector2, buttons: int, edges: int, lmb: bool, down: bool, notches: int, delta: float) -> void:
	if (edges & BUTTON_ACTION) != 0 or (down and _press_what == "done"):
		_to_debubble()
		return
	drawing = lmb and _press_what != "done"
	if drawing:
		_hold += delta
		var speed := draw_base + _hold * draw_accel * k
		var amt: float = minf(speed * delta, minf(vial, 1.0 - fluid))
		fluid += maxf(0.0, amt)
		vial -= maxf(0.0, amt)
		# Air: an empty vial, or a hold long past what anybody needs.
		if vial <= 0.0005 or _hold > air_hold / k:
			_air_acc += delta
			if _air_acc >= air_sustain and not _air_this_hold:
				_air_this_hold = true
				air_drawn += 1
				bubbles.append([SYR_X + _rng.randf_range(-12.0, 12.0), FLUID_TOP + air_r + 2.0, air_r, 0.0, 0.0, 0, _rng.randf() * TAU])
				_spike("air", cost_air, "Drew air into the syringe")
		else:
			_air_acc = 0.0
	else:
		_hold = 0.0
		_air_acc = 0.0
		_air_this_hold = false
	var back := 0.0
	if (buttons & BUTTON_SECONDARY) != 0:
		back += return_rate * delta
	back += absf(float(notches)) * scroll_return
	if back > 0.0:
		var amt2: float = minf(back, minf(fluid, 1.0 - vial))
		fluid -= maxf(0.0, amt2)
		vial += maxf(0.0, amt2)


func _to_debubble() -> void:
	phase = Phase.DEBUBBLE
	drawing = false
	_hold = 0.0
	var n := clampi(int(round(float(_rng.randi_range(bubbles_min, bubbles_max)) * k)), 0, 12)
	var stuck := mini(n, int(round(float(stuck_count) * k)))
	var rmax := bubble_r_max * k
	var y0 := FLUID_TOP + 8.0
	var y1 := maxf(y0 + 4.0, seal_y() - 8.0)
	var fresh: Array = []
	for i in n:
		var r := _rng.randf_range(bubble_r_min, maxf(bubble_r_min, rmax))
		r = minf(r, maxf(3.0, (y1 - y0) * 0.5))
		var st := 1 if i < stuck else 0
		var x := _rng.randf_range(SYR_X - BARREL_HALF + r + 2.0, SYR_X + BARREL_HALF - r - 2.0)
		if st == 1:
			x = (SYR_X - BARREL_HALF + r * 0.55) if i % 2 == 0 else (SYR_X + BARREL_HALF - r * 0.55)
		fresh.append([x, _rng.randf_range(y0 + r, maxf(y0 + r, y1 - r)), r, 0.0, 0.0, st, _rng.randf() * TAU])
	# The air bubble(s) from drawing too long go last, as the spec has it.
	fresh.append_array(bubbles)
	bubbles = fresh
	show_card("FLICK!")


# -- DEBUBBLE ----------------------------------------------------------------------------------

func _play_debubble(p: Vector2, edges: int, down: bool) -> void:
	if (edges & BUTTON_ACTION) != 0 or (down and _press_what == "done"):
		_to_inject()
		return
	if not down:
		return
	if _press_what == "pad":
		_purge()
	elif _press_what == "barrel":
		_flick(p)


func _flick(p: Vector2) -> void:
	for b in bubbles:
		if int(b[5]) == 1:
			if Vector2(float(b[0]), float(b[1])).distance_to(p) <= unstick_reach / k:
				b[5] = 0
				b[4] = -60.0
				b[0] = clampf(float(b[0]), SYR_X - BARREL_HALF + float(b[2]), SYR_X + BARREL_HALF - float(b[2]))
			continue
		b[4] = float(b[4]) - _rng.randf_range(flick_vy_min, flick_vy_max)
		b[3] = float(b[3]) + _rng.randf_range(-flick_vx, flick_vx)
	_ripple(p)


func _purge() -> void:
	var best := -1
	for i in bubbles.size():
		var b: Array = bubbles[i]
		if int(b[5]) == 1:
			continue
		if float(b[1]) - float(b[2]) - FLUID_TOP <= purge_reach / k:
			best = i
			break
	if best >= 0:
		bubbles.remove_at(best)
		fluid = maxf(0.0, fluid - pop_cost)
		pops += 1
	else:
		fluid = maxf(0.0, fluid - squirt_cost)
		squirts += 1
	var low := fluid < target - band
	if low and not _purge_low_warned:
		_purge_low_warned = true
		_spike("purge_low", cost_purge_low, "Squirted the dose away")
	elif not low:
		_purge_low_warned = false


func _to_inject() -> void:
	phase = Phase.INJECT
	carried.clear()
	for b in bubbles:
		carried.append(snappedf(float(b[2]), 0.1))
	bubbles.clear()
	_shown.clear()
	billed = 0
	_need_release = true
	show_card("STICK!")


## Bubble physics, as specced: no physics engine, dt capped, every frame on the operator's machine.
func _step_bubbles(delta: float) -> void:
	var dt := minf(delta, 0.05)
	var sy := seal_y()
	for b in bubbles:
		if int(b[5]) == 1:
			continue
		var r := float(b[2])
		b[3] = float(b[3]) * exp(-damp_x * dt)
		b[4] = float(b[4]) * exp(-damp_y * dt)
		var vx := float(b[3]) + sin(_t * 3.0 + float(b[6])) * wobble
		var vy := float(b[4]) - (rise_base + rise_per_r * r)
		b[0] = clampf(float(b[0]) + vx * dt, SYR_X - BARREL_HALF + r + 1.0, SYR_X + BARREL_HALF - r - 1.0)
		b[1] = clampf(float(b[1]) + vy * dt, FLUID_TOP + r, maxf(FLUID_TOP + r, sy - r))
	# Merging.
	var i := 0
	while i < bubbles.size():
		var a: Array = bubbles[i]
		var j := i + 1
		var merged := false
		while j < bubbles.size():
			var c: Array = bubbles[j]
			if int(a[5]) == 0 and int(c[5]) == 0:
				var d := Vector2(float(a[0]), float(a[1])).distance_to(Vector2(float(c[0]), float(c[1])))
				if d < float(a[2]) + float(c[2]) - 2.0:
					var nr := minf(merge_cap, sqrt(float(a[2]) * float(a[2]) + float(c[2]) * float(c[2])))
					a[0] = (float(a[0]) + float(c[0])) * 0.5
					a[1] = (float(a[1]) + float(c[1])) * 0.5
					a[2] = nr
					bubbles.remove_at(j)
					merged = true
					continue
			j += 1
		if not merged:
			i += 1


# -- INJECT ------------------------------------------------------------------------------------

func _play_inject(p: Vector2, buttons: int, edges: int, lmb: bool, down: bool, released: bool,
		press_len: float, notches: int, delta: float) -> void:
	if locked:
		return   # the plunger is advance()'s; lmb is read there through _push_held
	if down and _press_what == "tq":
		_press_tourniquet()
		_need_release = true
		return
	if not held:
		# Bare-handed: take the syringe, or slap the arm.
		if down and _press_what == "tray":
			held = true
			grip = p
			_need_release = true
			return
		if released and _press_what == "skin" and press_len < slap_max:
			_slap(_press_at)
		return
	# Holding it: it follows the mouse until the needle goes in.
	if not inserting:
		grip = p
		if (edges & BUTTON_LEFT) != 0:
			angle -= key_deg
		if (edges & BUTTON_RIGHT) != 0:
			angle += key_deg
		angle = clampf(angle + float(notches) * scroll_deg, angle_min, angle_max)
	if _need_release:
		if not lmb:
			_need_release = false
		return
	if released and not inserting:
		if _press_what == "tray" and press_len < pickup_quick:
			held = false   # a quick click back on the tray sets it down
		return
	if lmb and not inserting and _press_t >= push_hold and _press_what != "tray":
		var t0 := grip + dir() * ASM_TIP
		if on_skin(t0):
			inserting = true
			entry = t0
			sink = 0.0
			flashed = false
	if inserting:
		if lmb:
			sink = minf(insert_max, sink + insert_speed * k * delta)
			_check_flash()
		else:
			_release_needle()


func _check_flash() -> void:
	if not inserting:
		return
	var t := tip()
	if not flashed and sink > flash_min:
		var hit := vein_near(t)
		if not hit.is_empty() and float(hit.d) <= tip_tol / k and not _is_blown(int(hit.i), t.x):
			var rel := absf(angle - float(hit.tan))
			var mid := (window_lo + window_hi) * 0.5
			var half := (window_hi - window_lo) * 0.5 / k
			if rel >= mid - half and rel <= mid + half:
				flashed = true
				flash_adv = sink
	if flashed and sink > flash_adv + blow_past / k:
		var hit2 := vein_near(t)
		var vi := int(hit2.get("i", 0))
		blown_ranges.append([vi, snappedf(t.x - blown_half_x, 0.5), snappedf(t.x + blown_half_x, 0.5)])
		bruises.append([snappedf(t.x, 0.5), snappedf(t.y, 0.5)])
		blown += 1
		_spike("blown", pts_blown * vitals_per_point, "Blew the vein: the vein map reads like a bruise atlas")
		_retract()
		_need_release = true


func _release_needle() -> void:
	if flashed:
		locked = true
		inserting = false
		dose = fluid
		rate = 0.0
		show_card("PUSH!")
		return
	if sink > flash_min:
		var t := tip()
		punctures.append([snappedf(t.x, 0.5), snappedf(t.y, 0.5)])
		if punctures.size() > 10:
			punctures.pop_front()
		misses += 1
		_spike("miss", pts_miss * vitals_per_point, "Missed the vein: the arm has more holes than the chart explains")
	_retract()


func _retract() -> void:
	inserting = false
	flashed = false
	sink = 0.0


func _slap(at: Vector2) -> void:
	vis = 1.0
	slaps += 1
	_ripple(at)
	_spike("slap", cost_slap, "Slapped the patient")


func _ripple(at: Vector2) -> void:
	ripples.append([snappedf(at.x, 0.5), snappedf(at.y, 0.5), play_t])
	if ripples.size() > 4:
		ripples.pop_front()


## The index of this step in its procedure, so the tourniquet button keeps back what a later step needs.
func _step_index() -> int:
	var sid := String(ctx.get("step", {}).get("id", ""))
	var all := Procedures.steps(String(ctx.get("ailment_id", "")))
	for i in all.size():
		if String(all[i].get("id", "")) == sid:
			return i
	return 0


## How many tourniquets are in hand beyond what the rest of this procedure still needs.
func tourniquets_spare() -> int:
	var have := hand_count(tourniquet_item)
	if have < 0:
		return 0
	var keep := int(Procedures.remaining_requirements(String(ctx.get("ailment_id", "")), _step_index() + 1).get(tourniquet_item, 0))
	return have - keep


func _refresh_tq() -> void:
	if not bool(ctx.get("operator", false)):
		return
	var spare := tourniquets_spare()
	# A press is waiting on the host to take the tourniquet out of the hand: nothing more until it has.
	if _tq_hand_at_press >= 0:
		if hand_count(tourniquet_item) < _tq_hand_at_press:
			_tq_hand_at_press = -1
		else:
			spare = 0
	tq_avail = spare > 0 and not tq_on


func _press_tourniquet() -> void:
	if tq_on:
		tq_on = false
		tq_left = 0.0
		return
	if not tq_avail:
		return
	_tq_hand_at_press = hand_count(tourniquet_item)
	tq_on = true
	tq_left = tq_time
	tq_avail = false
	use_item(tourniquet_item, 1)


## The operator's clock: bubbles rising, the veins fading, the tourniquet running down, the plunger.
func advance(delta: float) -> void:
	match phase:
		Phase.DEBUBBLE:
			_step_bubbles(delta)
		Phase.INJECT:
			_refresh_tq()
			if tq_on:
				vis = 1.0
				redness = minf(1.0, redness + redness_up * delta)
				tq_left -= delta
				if tq_left <= 0.0:
					tq_on = false
					tq_left = 0.0
					_spike("tourniquet_timeout", cost_tourniquet_timeout, "Left the tourniquet on too long")
			else:
				vis = maxf(0.0, vis - delta / maxf(0.05, vein_fade / k))
				redness = maxf(0.0, redness - redness_down * delta)
			if locked:
				_advance_push(delta)
	_update_progress()


var _push_held := false

func handle_cursor(p: Vector2, buttons: int, delta: float) -> void:
	_push_held = (buttons & BUTTON_PRIMARY) != 0
	super.handle_cursor(p, buttons, delta)


func _advance_push(delta: float) -> void:
	if deliver_t >= 0.0:
		deliver_t += delta
		if deliver_t >= deliver_beat:
			_complete()
		return
	if _push_held and armed():
		rate = minf(push_cap, rate + push_up * delta)
	else:
		rate = maxf(0.0, rate - push_down * delta)
	fluid = maxf(0.0, fluid - rate * drain_k * delta)
	if rate > fast_rate / k:
		_fast_acc += delta
		if _fast_acc >= fast_every:
			_fast_acc -= fast_every
			fast_pushes += 1
			_spike("fast_push", pts_fast * vitals_per_point, "Pushed it too fast, like the elevator was waiting")
	else:
		_fast_acc = 0.0
	# The bubbles left in the barrel go in, one by one, as the plunger passes them.
	var gone := 1.0 - (fluid / dose if dose > 0.0001 else 0.0)
	while billed < carried.size() and gone >= float(billed + 1) / float(carried.size() + 1):
		var units := 2 if float(carried[billed]) > big_bubble_r else 1
		billed += 1
		_spike("bubble", float(units) * pts_bubble * vitals_per_point, "Air in the line: something extra is on its way to the heart")
	if fluid <= 0.0:
		fluid = 0.0
		rate = 0.0
		deliver_t = 0.0


func _complete() -> void:
	phase = Phase.DONE
	var err := dose - target
	var r := dose / maxf(0.001, target)
	sedation = r
	if absf(err) <= band:
		sedation = 1.0 + (r - 1.0) * in_band_k
	sedation = clampf(sedation, 0.0, 2.0)
	var dose_pts := 0.0
	if absf(err) > band:
		dose_pts = minf(pts_dose_max, (absf(err) - band) * pts_dose_slope)
		if err < 0.0:
			_spike("dose", dose_pts * vitals_per_point, "Underdosed: the patient may wake up mid-surgery")
		else:
			_spike("dose", dose_pts * vitals_per_point, "Overdosed: that is a deeper sleep than anyone scheduled")
	var units := 0
	for rr in carried:
		units += 2 if float(rr) > big_bubble_r else 1
	var score := 100.0 - dose_pts - float(units) * pts_bubble - float(misses) * pts_miss \
		- float(blown) * pts_blown - float(fast_pushes) * pts_fast
	quality = snappedf(clampf(score / 100.0, 0.05, 1.0), 0.01)
	var b = body()
	if b != null and b.has_method("set_sedation"):
		b.set_sedation(clampf(sedation, 0.0, 1.0))
	arcade_finish({"sedation": snappedf(sedation, 0.01)})


func _update_progress() -> void:
	var p := 0.0
	match phase:
		Phase.DRAW:
			p = 0.3 * clampf(fluid / maxf(0.01, target), 0.0, 1.0)
		Phase.DEBUBBLE:
			p = 0.35
		Phase.INJECT:
			p = 0.45 if not locked else 0.55 + 0.43 * clampf(1.0 - fluid / maxf(0.0001, dose), 0.0, 1.0)
		Phase.DONE:
			p = 1.0
	progress = clampf(p, 0.0, 1.0 if phase == Phase.DONE else 0.98)


## The nearest vein to `p`: {i, d (rpx), tan (degrees, +down), x}. Empty with no veins.
func vein_near(p: Vector2) -> Dictionary:
	var best := {}
	var bd := INF
	for vi in veins.size():
		var pts: PackedVector2Array = veins[vi]
		for s in pts.size() - 1:
			var a: Vector2 = pts[s]
			var b: Vector2 = pts[s + 1]
			var ab := b - a
			var tt := clampf((p - a).dot(ab) / maxf(0.0001, ab.length_squared()), 0.0, 1.0)
			var q := a + ab * tt
			var d := p.distance_to(q)
			if d < bd:
				bd = d
				best = {"i": vi, "d": d, "tan": rad_to_deg(atan2(ab.y, ab.x)), "x": q.x, "y": q.y}
	return best


func _is_blown(vi: int, x: float) -> bool:
	for br in blown_ranges:
		if int(br[0]) == vi and x >= float(br[1]) and x <= float(br[2]):
			return true
	return false


# ---------------------------------------------------------------------------- every machine

func animate(delta: float) -> void:
	_t += delta
	_push_snd -= delta
	var e := 1.0 - exp(-18.0 * delta)
	# Spectators get the bubbles and the hand 20 times a second; ease toward them so they glide.
	if _shown.size() != bubbles.size():
		_shown = []
		for b in bubbles:
			_shown.append(Vector3(float(b[0]), float(b[1]), float(b[2])))
	else:
		for i in bubbles.size():
			var b: Array = bubbles[i]
			var to := Vector3(float(b[0]), float(b[1]), float(b[2]))
			_shown[i] = (to if bool(ctx.get("operator", false)) else (_shown[i] as Vector3).lerp(to, e))
	_shown_grip = grip if bool(ctx.get("operator", false)) else _shown_grip.lerp(grip, e)
	var keep: Array = []
	for d in _drops:
		d[2] = float(d[2]) + delta
		d[1] = (d[1] as Vector2) + Vector2(0.0, 260.0) * delta
		d[0] = (d[0] as Vector2) + (d[1] as Vector2) * delta
		if float(d[2]) < 0.8:
			keep.append(d)
	_drops = keep


## This step never gets jolts: the framework excludes it (the patient is not under yet).
func on_jolt(_offset: Vector2, _strength: float, _duration: float) -> void:
	pass


## Sounds, droplets and the real patient, on every machine, off the replicated counters.
func react() -> void:
	var b = body()
	var now := {"phase": phase, "air": air_drawn, "pops": pops, "squirts": squirts, "slaps": slaps,
		"misses": misses, "blown": blown, "flashed": flashed, "locked": locked, "fast": fast_pushes,
		"billed": billed, "tq": tq_on, "rip": ripples.size(), "held": held}
	if _seen.is_empty():
		_seen = now
		return
	if int(now.air) > int(_seen.air):
		audio(draw_cue, -3.0, 0.2)
	if int(now.pops) > int(_seen.pops):
		audio(pop_cue, -6.0, 0.15)
		_spray(Vector2(SYR_X, HUB_Y - 30.0), Color(0.55, 0.55, 0.55, 0.9), 5)
	if int(now.squirts) > int(_seen.squirts):
		audio(squirt_cue, -8.0, 0.2)
		_spray(Vector2(SYR_X, NEEDLE_TIP_Y + 10.0), ink.drug if ink != null else Color.GREEN, 7)
	if int(now.slaps) > int(_seen.slaps):
		audio(slap_cue, -4.0, 0.1)
		if b != null and b.has_method("stir"):
			b.stir(0.25)
	if int(now.misses) > int(_seen.misses):
		audio(stick_cue, -4.0, 0.3)
		shake(0.4)
		ghost(0.4)
		if b != null and b.has_method("stir"):
			b.stir(0.6)
	if int(now.blown) > int(_seen.blown):
		audio(blow_cue, -4.0, 0.1)
		shake(0.6)
		ghost(0.5)
		if b != null and b.has_method("stir"):
			b.stir(0.8)
	if bool(now.flashed) and not bool(_seen.flashed):
		audio(stick_cue, -2.0)
	if bool(now.locked) and not bool(_seen.locked):
		audio(push_cue, -6.0)
	if bool(now.held) and not bool(_seen.held):
		audio("items_clink", -10.0, 0.2)
	if bool(now.tq) and not bool(_seen.tq):
		audio(tourniquet_cue, -4.0)
	if int(now.fast) > int(_seen.fast) or int(now.billed) > int(_seen.billed):
		audio(alarm_cue, -4.0)
		if b != null and b.has_method("stir"):
			b.stir(0.35)
	if int(now.rip) != int(_seen.rip) and int(now.phase) == Phase.DEBUBBLE:
		audio(flick_cue, -8.0, 0.2)
	if int(now.phase) != int(_seen.phase) and int(now.phase) == Phase.DEBUBBLE:
		audio("items_clink", -8.0, 0.1)
	_seen = now
	# The plunger hiss while it moves.
	if locked and rate > 0.08 and deliver_t < 0.0:
		if _push_snd <= 0.0:
			_push_snd = 0.6
			audio(push_cue, -12.0, 0.05)
	# The drug going in shows on the patient as it goes.
	if b != null and locked and phase != Phase.DONE and b.has_method("set_sedation"):
		var given := clampf((dose - fluid) / maxf(0.001, target), 0.0, 1.5)
		b.set_sedation(clampf(given * 0.75, 0.0, 1.0))


func _spray(at: Vector2, col: Color, n: int) -> void:
	for i in n:
		var a := -PI * 0.5 + randf_range(-0.7, 0.7)
		_drops.append([at, Vector2(cos(a), sin(a)) * randf_range(90.0, 170.0), 0.0, col])


# ---------------------------------------------------------------------------- the diagram

func paint_game(c: CanvasItem) -> void:
	if panel == null or ink == null:
		return
	var t0 := Time.get_ticks_usec()
	ink.ops = 0
	_prof_ops = 0
	ink.draw_grime(c, grime_spots)
	_prof_mark("grime", t0)
	if _warm:
		# Warmup: one of everything, so nothing draws for the first time mid-step.
		_paint_syringe(c, true)
		_paint_inject(c)
		ink.warm(c)
		return
	t0 = Time.get_ticks_usec()
	match phase:
		Phase.DRAW:
			_paint_syringe(c, false)
		Phase.DEBUBBLE:
			_paint_syringe(c, true)
		Phase.INJECT, Phase.DONE:
			_paint_inject(c)
	_prof_mark("stage", t0)
	_prof_frames += 1
	if _prof_frames >= 30:
		var parts := []
		for key in _prof:
			parts.append("%s %.2fms/%dops" % [key, float(_prof[key][0]) / 1000.0 / 30.0, int(_prof[key][1]) / 30])
		prof_line = ", ".join(parts)
		_prof.clear()
		_prof_frames = 0
	for d in _drops:
		var a: float = 1.0 - float(d[2]) / 0.8
		ink.dot(c, cv(d[0]), cl(2.6), Color(d[3], (d[3] as Color).a * a))


## The needle-up syringe in its inverted vial: stages 1 and 2.
func _paint_syringe(c: CanvasItem, debubble: bool) -> void:
	var I := ink
	var sy := seal_y()
	var bx0 := SYR_X - BARREL_HALF
	var bx1 := SYR_X + BARREL_HALF
	# The vial, upside down, with its pool at the neck end draining as you draw.
	if not debubble:
		var vbody := Rect2(cv(VIAL.position), VIAL.size * _u())
		var neck := PackedVector2Array([cv(Vector2(VIAL.position.x + 12.0, VIAL.end.y)), cv(Vector2(VIAL.end.x - 12.0, VIAL.end.y)),
			cv(Vector2(SYR_X + 16.0, VIAL_NECK_Y)), cv(Vector2(SYR_X - 16.0, VIAL_NECK_Y))])
		c.draw_rect(vbody, Color(I.paper.darkened(0.04)))
		var pool_top: float = lerpf(VIAL.end.y, VIAL.position.y + 6.0, clampf(vial, 0.0, 1.0))
		if vial > 0.002:
			c.draw_colored_polygon(neck, I.drug_pool)
			c.draw_rect(Rect2(cv(Vector2(VIAL.position.x + 2.0, pool_top)), Vector2(VIAL.size.x - 4.0, VIAL.end.y - pool_top) * _u()), I.drug_pool)
			I.seg(c, cv(Vector2(VIAL.position.x + 4.0, pool_top)), cv(Vector2(VIAL.end.x - 4.0, pool_top)), I.meniscus, I.detail, 31)
		I.rect(c, vbody, I.ink, I.outline, 32)
		I.line(c, neck, I.ink, I.outline, 33, false)
		# The crimp cap at the neck, and the label.
		I.rect(c, Rect2(cv(Vector2(SYR_X - 19.0, VIAL_NECK_Y - 6.0)), Vector2(38.0, 12.0) * _u()), I.ink, I.detail, 34, Color(I.label, 0.35))
		I.rect(c, Rect2(cv(Vector2(VIAL.position.x + 4.0, VIAL.position.y + 10.0)), Vector2(VIAL.size.x - 8.0, 24.0) * _u()), I.ink_soft, I.detail, 35, Color(I.paper, 0.9))
		I.text(c, cv(Vector2(SYR_X, VIAL.position.y + 27.0)), "SOMNUL-9", 10.5, I.ink, 1)
		if vial <= 0.002:
			I.text(c, cv(Vector2(VIAL.end.x + 14.0, VIAL.position.y + 40.0)), "vial empty", 14.0, I.deep_red)
	# The needle, up through the neck.
	var needle_top := NEEDLE_TIP_Y if not debubble else HUB_Y - 70.0
	I.seg(c, cv(Vector2(SYR_X, HUB_Y)), cv(Vector2(SYR_X, needle_top)), I.ink, I.detail, 36)
	I.seg(c, cv(Vector2(SYR_X, needle_top)), cv(Vector2(SYR_X + 4.0, needle_top + 7.0)), I.ink, I.detail * 0.8, 37)
	# The hub.
	I.rect(c, Rect2(cv(Vector2(SYR_X - 12.0, HUB_Y)), Vector2(24.0, BARREL_Y0 - HUB_Y) * _u()), I.ink, I.outline, 38, Color(I.paper.darkened(0.06)))
	# The barrel: fluid from the needle end down to the seal, the band, the ticks.
	var inner := Rect2(cv(Vector2(bx0, FLUID_TOP)), Vector2(BARREL_HALF * 2.0, sy - FLUID_TOP) * _u())
	c.draw_rect(Rect2(cv(Vector2(bx0, BARREL_Y0)), Vector2(BARREL_HALF * 2.0, BARREL_Y1 - BARREL_Y0) * _u()), Color(1, 1, 1, 0.25))
	if fluid > 0.001:
		c.draw_rect(inner, I.drug)
	var b0 := FLUID_TOP + (target - band) * TRAVEL
	var b1 := FLUID_TOP + (target + band) * TRAVEL
	c.draw_rect(Rect2(cv(Vector2(bx0, b0)), Vector2(BARREL_HALF * 2.0, b1 - b0) * _u()), I.band)
	I.seg(c, cv(Vector2(bx0 - 8.0, b0)), cv(Vector2(bx1 + 8.0, b0)), I.band_edge, I.detail, 41)
	I.seg(c, cv(Vector2(bx0 - 8.0, b1)), cv(Vector2(bx1 + 8.0, b1)), I.band_edge, I.detail, 42)
	I.halftone(c, Rect2(cv(Vector2(bx0, b0)), Vector2(BARREL_HALF * 2.0, b1 - b0) * _u()), 0.35, I.band_edge)
	var ml_px := TRAVEL / barrel_ml
	var n := int(barrel_ml)
	for i in n + 1:
		var y := FLUID_TOP + float(i) * ml_px
		var long := i % 2 == 0
		I.seg(c, cv(Vector2(bx1, y)), cv(Vector2(bx1 + (14.0 if long else 8.0), y)), I.ink, I.detail * 0.8, 50 + i)
		if long and i > 0:
			I.text(c, cv(Vector2(bx1 + 18.0, y + 5.0)), "%d mL" % i, 12.0)
	I.rect(c, Rect2(cv(Vector2(bx0, BARREL_Y0)), Vector2(BARREL_HALF * 2.0, BARREL_Y1 - BARREL_Y0) * _u()), I.ink, I.outline, 43)
	# The flange, the seal, the rod and the thumb pad.
	I.seg(c, cv(Vector2(bx0 - 26.0, BARREL_Y1)), cv(Vector2(bx1 + 26.0, BARREL_Y1)), I.ink, I.heavy, 44)
	I.rect(c, Rect2(cv(Vector2(bx0 + 2.0, sy)), Vector2(BARREL_HALF * 2.0 - 4.0, 10.0) * _u()), I.ink, I.detail, 45, Color(I.ink_soft, 0.85))
	var py := pad_y()
	I.seg(c, cv(Vector2(SYR_X, sy + 10.0)), cv(Vector2(SYR_X, py)), I.ink, I.outline, 46)
	I.rect(c, Rect2(cv(Vector2(SYR_X - 40.0, py)), Vector2(80.0, 12.0) * _u()), I.ink, I.outline, 47, Color(I.paper.darkened(0.1)))
	I.seg(c, cv(Vector2(bx0 + 4.0, FLUID_TOP)), cv(Vector2(bx1 - 4.0, FLUID_TOP)), I.meniscus, I.detail * 0.7, 48)
	# Level readout.
	I.text(c, cv(Vector2(bx0 - 16.0, sy + 5.0)), "%.1f mL" % (fluid * barrel_ml), 13.0, I.label, 2)
	if not debubble:
		if air_drawn > 0 and _t < 99999.0 and bubbles.size() > 0:
			I.text(c, cv(Vector2(bx0 - 16.0, FLUID_TOP + 30.0)), "air drawn in", 14.0, I.deep_red, 2)
		I.text(c, cv(Vector2(bx0 - 20.0, b0 - 8.0)), "the band", 12.0, I.band_edge, 2)
		_button(c, DONE_BTN, "Done", 101)
	# Bubbles.
	for i in _shown.size():
		var bv: Vector3 = _shown[i]
		var stuck: bool = i < bubbles.size() and int(bubbles[i][5]) == 1
		var at := cv(Vector2(bv.x, bv.y))
		if stuck:
			I.ellipse(c, at, Vector2(bv.z * 0.55, bv.z) * _u(), I.amber, I.detail, 200 + i, I.amber_fill)
		else:
			I.circle(c, at, bv.z * _u(), I.ink, I.detail, 200 + i, Color(1, 1, 1, 0.55))
			I.dot(c, at + Vector2(-bv.z * 0.35, -bv.z * 0.35) * _u(), bv.z * 0.22 * _u(), Color(1, 1, 1, 0.9))
	if debubble:
		_paint_legend(c)
		for rp in ripples:
			var age: float = play_t - float(rp[2])
			if age >= 0.0 and age < 0.35:
				I.circle(c, cv(Vector2(float(rp[0]), float(rp[1]))), (8.0 + age * 110.0) * _u(), Color(I.ink, 1.0 - age / 0.35), I.detail, 300)
		if fluid < target - band:
			I.text(c, cv(Vector2(bx1 + 70.0, FLUID_TOP + 20.0)), "(!) level below target band", 15.0, I.deep_red)
		# The purge target: the thumb pad, ringed.
		I.ellipse(c, cv(Vector2(SYR_X, py + 6.0)), Vector2(58.0, 20.0) * _u(), Color(I.ink, 0.35), I.detail, 49)
		I.text(c, cv(Vector2(SYR_X + 66.0, py + 12.0)), "tap to purge", 12.0)
		_button(c, DONE_BTN, "Continue", 102)


func _paint_legend(c: CanvasItem) -> void:
	var I := ink
	I.circle(c, cv(Vector2(52.0, 58.0)), 9.0 * _u(), I.ink, I.detail, 401, Color(1, 1, 1, 0.55))
	I.text(c, cv(Vector2(70.0, 63.0)), "loose: rises, flick the barrel", 13.0)
	I.ellipse(c, cv(Vector2(52.0, 88.0)), Vector2(5.0, 9.0) * _u(), I.amber, I.detail, 402, I.amber_fill)
	I.text(c, cv(Vector2(70.0, 93.0)), "stuck: flick right beside it", 13.0)


func _button(c: CanvasItem, r: Rect2, label: String, sd: int, live := true) -> void:
	var I := ink
	var rr := Rect2(cv(r.position), r.size * _u())
	I.rect(c, rr, I.ink if live else Color(I.ink, 0.35), I.outline, sd, Color(I.paper.darkened(0.05)) if live else Color(0, 0, 0, 0))
	I.text(c, rr.get_center() + Vector2(0.0, 6.0 * _u()), label, 17.0, I.ink if live else Color(I.label, 0.4), 1)


## Stage 3: the arm, the veins, the tray and the needle.
func _paint_inject(c: CanvasItem) -> void:
	var I := ink
	var tp0 := Time.get_ticks_usec()
	# The arm below its wavy top edge.
	var top := PackedVector2Array()
	var x := 0.0
	while x <= 960.0:
		top.append(cv(Vector2(x, skin_top(x))))
		x += 24.0
	var poly := top.duplicate()
	poly.append(cv(Vector2(960.0, 600.0)))
	poly.append(cv(Vector2(0.0, 600.0)))
	c.draw_colored_polygon(poly, I.hide_seal if seal else I.skin_human)
	if redness > 0.001:
		c.draw_colored_polygon(poly, Color(I.redness, I.redness.a * redness / 0.22 * 0.22))
	# The halftone shading just under the skin's edge: one polygon along the edge, 34 px deep.
	var under := top.duplicate()
	for i in range(top.size() - 1, -1, -1):
		under.append(top[i] + Vector2(0.0, cl(34.0)))
	I.halftone_poly(c, under, 0.35)
	if seal:
		for ri in 3:
			var ridge := PackedVector2Array()
			var xx := 0.0
			while xx <= 960.0:
				ridge.append(cv(Vector2(xx, skin_top(xx) + 70.0 + 80.0 * float(ri) + 6.0 * sin(xx * 0.01 + float(ri)))))
				xx += 48.0
			I.line(c, ridge, Color(I.ink, 0.45), I.detail, 500 + ri)
		for s in speckles:
			I.dot(c, cv(s), 1.6 * _u(), Color(I.ink, 0.35))
	I.line(c, top, I.ink, I.heavy, 510)
	_prof_mark("arm", tp0)
	tp0 = Time.get_ticks_usec()
	# The veins: only as visible as the last slap (or the tourniquet) leaves them.
	var vcol: Color = I.vein_seal if seal else I.vein_human
	if vis > 0.01:
		for vi in veins.size():
			var pts := PackedVector2Array()
			for q in (veins[vi] as PackedVector2Array):
				pts.append(cv(q))
			I.line(c, pts, Color(vcol, 0.35 * vis), 9.0, 520 + vi)
			I.line(c, pts, Color(vcol, 0.9 * vis), 3.2, 530 + vi)
	_prof_mark("veins", tp0)
	tp0 = Time.get_ticks_usec()
	# What went wrong on this arm stays on it.
	for br in bruises:
		var at := cv(Vector2(float(br[0]), float(br[1])))
		I.ellipse(c, at, Vector2(30.0, 18.0) * _u(), Color(0, 0, 0, 0), 0.0, 540, I.bruise)
		I.ellipse(c, at, Vector2(14.0, 9.0) * _u(), Color(I.bruise_core, 0.7), I.detail, 541, I.bruise_core)
	for pu in punctures:
		I.circle(c, cv(Vector2(float(pu[0]), float(pu[1]))), 4.5 * _u(), I.deep_red, I.detail, 550, Color(I.deep_red, 0.45))
	for rp in ripples:
		var age: float = play_t - float(rp[2])
		if age >= 0.0 and age < 0.35:
			I.circle(c, cv(Vector2(float(rp[0]), float(rp[1]))), (10.0 + age * 140.0) * _u(), Color(I.ink, 1.0 - age / 0.35), I.detail, 560)
	# The tourniquet strap round the arm, when it is on.
	if tq_on:
		var sx := 880.0
		I.rect(c, Rect2(cv(Vector2(sx, skin_top(sx) - 6.0)), Vector2(26.0, 600.0 - skin_top(sx) + 6.0) * _u()), I.ink, I.outline, 570, Color(I.ink_soft, 0.8))
		I.rect(c, Rect2(cv(TQ_BAR.position), TQ_BAR.size * _u()), I.ink, I.detail, 571)
		c.draw_rect(Rect2(cv(TQ_BAR.position), Vector2(TQ_BAR.size.x * clampf(tq_left / tq_time, 0.0, 1.0), TQ_BAR.size.y) * _u()), Color(I.deep_red, 0.7))
		I.text(c, cv(TQ_BAR.position + Vector2(TQ_BAR.size.x + 10.0, 10.0)), "tourniquet", 12.0)
	# The tourniquet button.
	if not locked:
		var live := tq_avail or tq_on
		_button(c, TQ_BTN, "Release" if tq_on else "Tourniquet", 580, live)
		if not live:
			I.text(c, cv(Vector2(TQ_BTN.get_center().x, TQ_BTN.end.y + 16.0)), "none to spare", 12.0, Color(I.label, 0.6), 1)
	# The tray and, when it is not in the hand, the syringe lying on it.
	I.ellipse(c, cv(TRAY), TRAY_R * _u(), I.ink, I.outline, 590, Color(I.paper.darkened(0.08)))
	var tray_low := PackedVector2Array()
	for i in 13:
		var ang := PI * float(i) / 12.0
		tray_low.append(cv(TRAY + Vector2(cos(ang) * TRAY_R.x, sin(ang) * TRAY_R.y) * 0.85))
	I.halftone_poly(c, tray_low, 0.3)
	_prof_mark("marks+tray", tp0)
	tp0 = Time.get_ticks_usec()
	if not held and not locked:
		_paint_assembly(c, TRAY + Vector2(-60.0, -4.0), 4.0, 0.0, false)
		I.text(c, cv(TRAY + Vector2(0.0, TRAY_R.y + 18.0)), "tray", 12.0, I.label, 1)
	elif held or locked:
		_paint_assembly(c, _shown_grip if not (inserting or locked) else entry - dir() * (ASM_TIP - sink), angle, sink if (inserting or locked) else 0.0, true)
	if locked:
		_paint_meter(c)
	if deliver_t >= 0.0:
		I.text(c, cv(Vector2(480.0, 250.0)), "dose delivered...", 18.0, I.ink, 1)


## The syringe assembly along `ang` from `g` (the grip): barrel, needle, and -- once it is in --
## the buried part as a faint dashed ghost past the entry dimple.
func _paint_assembly(c: CanvasItem, g: Vector2, ang: float, adv: float, live: bool) -> void:
	var I := ink
	var d := Vector2(cos(deg_to_rad(ang)), sin(deg_to_rad(ang)))
	var n := Vector2(-d.y, d.x)
	var hub := g + d * ASM_BARREL
	var tp := g + d * ASM_TIP
	# Rod and pad behind the grip.
	I.seg(c, cv(g - d * 22.0), cv(g), I.ink, I.outline, 600)
	I.seg(c, cv(g - d * 22.0 + n * 10.0), cv(g - d * 22.0 - n * 10.0), I.ink, I.heavy, 601)
	# The barrel with its little fluid level.
	var corners := PackedVector2Array([cv(g + n * 9.0), cv(hub + n * 9.0), cv(hub - n * 9.0), cv(g - n * 9.0)])
	var f := fluid if phase != Phase.DRAW else 0.0
	var flen := ASM_BARREL * clampf(f, 0.0, 1.0)
	if flen > 0.5:
		var fp := PackedVector2Array([cv(hub - d * flen + n * 8.0), cv(hub + n * 8.0), cv(hub - n * 8.0), cv(hub - d * flen - n * 8.0)])
		c.draw_colored_polygon(fp, I.drug)
		# The carried bubbles, riding in the barrel until the plunger sends them in.
		for bi in range(billed, carried.size()):
			var along := ASM_BARREL - flen * (float(bi - billed) + 0.5) / float(maxi(1, carried.size() - billed))
			c.draw_arc(cv(g + d * along), clampf(float(carried[bi]) * 0.3, 2.0, 6.0) * _u(), 0.0, TAU, 10, I.ink, 1.4 * _u())
	I.shape(c, corners, I.ink, I.outline, 602, Color(1, 1, 1, 0.3))
	# The plunger's seal, riding on the fluid, and its rod back to the grip.
	var sealp := hub - d * maxf(2.0, flen)
	I.seg(c, cv(sealp + n * 8.0), cv(sealp - n * 8.0), I.ink, I.outline, 607)
	I.seg(c, cv(g), cv(sealp), I.ink, I.detail, 608)
	# The hub: red when blood has flashed back (a notch too, so it is shape as well as colour).
	var hc := cv(hub + d * 4.0)
	var flash_now := flashed or locked
	I.circle(c, hc, 7.0 * _u(), I.ink, I.detail, 603, (I.flash if flash_now else Color(I.paper.darkened(0.1))))
	if flash_now:
		I.seg(c, hc - n * 6.0 * _u(), hc + n * 6.0 * _u(), I.paper, 1.4, 604)
	# The needle: visible down to the skin, then a faint dashed ghost to the tip.
	var needle_from := hub + d * 8.0
	var vis_len := maxf(4.0, ASM_NEEDLE - 8.0 - 1.05 * adv) if adv > 0.0 else ASM_NEEDLE - 8.0
	var vis_end := needle_from + d * vis_len
	I.seg(c, cv(needle_from), cv(vis_end), I.ink, I.detail, 605)
	# Half-length tick.
	var half := hub + d * (ASM_NEEDLE * 0.5)
	if adv < ASM_NEEDLE * 0.5 - 2.0:
		I.seg(c, cv(half + n * 4.0), cv(half - n * 4.0), I.ink, 1.4, 606)
	if adv > 0.0:
		I.dashed(c, cv(vis_end), cv(tp), Color(I.ink, 0.15), I.detail, 5.0, 4.0)
		# The entry dimple.
		c.draw_arc(cv(vis_end), 5.0 * _u(), 0.0, TAU, 12, Color(I.ink, 0.6), 1.4 * _u())
		var depth := clampf(1.05 * adv / ASM_NEEDLE, 0.0, 1.0)
		var red := depth > 0.65 and not flashed and not locked
		if not locked:
			I.text(c, cv(vis_end + Vector2(14.0, -12.0)), "depth %d%%" % int(round(depth * 100.0)), 13.0, I.deep_red if red else I.label)
	if live:
		I.text(c, cv(g + Vector2(-34.0, -14.0)), "%d°" % int(round(ang)), 13.0, Color(I.label, 0.55), 1)
	if flashed and not locked:
		I.text(c, cv(tp + Vector2(18.0, 26.0)), "in the vein: stop", 15.0, I.deep_red)


func _paint_meter(c: CanvasItem) -> void:
	var I := ink
	var r := Rect2(cv(METER.position), METER.size * _u())
	var green := r.size.y * 0.55
	c.draw_rect(Rect2(Vector2(r.position.x, r.end.y - green), Vector2(r.size.x, green)), Color(I.good, 0.35))
	c.draw_rect(Rect2(r.position, Vector2(r.size.x, r.size.y - green)), Color(I.deep_red, 0.3))
	I.halftone(c, Rect2(r.position, Vector2(r.size.x, r.size.y - green)), 0.6, I.deep_red)
	I.rect(c, r, I.ink, I.outline, 610)
	var y := r.end.y - r.size.y * clampf(rate / 1.0, 0.0, 1.0)
	I.seg(c, Vector2(r.position.x - 10.0, y), Vector2(r.end.x + 10.0, y), I.ink, I.heavy, 611)
	I.text(c, Vector2(r.get_center().x, r.position.y - 10.0), "PUSH", 13.0, I.ink, 1)


## Warmup (scripts/warmup.gd): draw every stage at once from now on, so the first real open of each
## one draws nothing new.
func warm_all() -> void:
	_warm = true
	vis = 1.0
	held = true
	flashed = true
	bubbles = [[SYR_X, 300.0, 9.0, 0.0, 0.0, 0, 0.0], [SYR_X - 40.0, 350.0, 7.0, 0.0, 0.0, 1, 0.0]]
	punctures = [[300.0, 420.0]]
	bruises = [[600.0, 420.0]]
	tq_on = true
	tq_left = tq_time * 0.5
	if panel != null:
		panel.redraw()


# ---------------------------------------------------------------------------- net

## What an onlooker needs. Anything that creeps (fluid, the needle, the timers) goes out raw; the
## lab round-trips this every frame and a snapped creeping value would never move.
func net_pack() -> Dictionary:
	var bs: Array = []
	for b in bubbles:
		bs.append([float(b[0]), float(b[1]), float(b[2]), float(b[3]), float(b[4]), int(b[5]), float(b[6])])
	return {
		"ph": phase, "fl": fluid, "vl": vial, "bb": bs, "ad": air_drawn, "dr": drawing,
		"hd": held, "gp": grip, "an": angle, "ins": inserting, "av": sink, "en": entry,
		"fx": flashed, "fa": flash_adv, "lk": locked, "rt": rate, "ds": dose, "ca": carried,
		"bl": billed, "vs": vis, "tq": tq_on, "tl": tq_left, "ta": tq_avail, "rd": redness,
		"br": blown_ranges, "pu": punctures, "bz": bruises, "rp": ripples, "dt": deliver_t,
		"ms": misses, "bw": blown, "fp": fast_pushes, "sl": slaps, "po": pops, "sq": squirts,
		"se": snappedf(sedation, 0.01),
	}


func net_apply(s: Dictionary) -> void:
	phase = int(s.get("ph", phase))
	fluid = float(s.get("fl", fluid))
	vial = float(s.get("vl", vial))
	var bs = s.get("bb", null)
	if bs is Array:
		var out: Array = []
		for b in bs:
			if b is Array and (b as Array).size() >= 7:
				out.append((b as Array).duplicate())
		bubbles = out
	air_drawn = int(s.get("ad", air_drawn))
	drawing = bool(s.get("dr", drawing))
	held = bool(s.get("hd", held))
	grip = s.get("gp", grip)
	angle = float(s.get("an", angle))
	inserting = bool(s.get("ins", inserting))
	sink = float(s.get("av", sink))
	entry = s.get("en", entry)
	flashed = bool(s.get("fx", flashed))
	flash_adv = float(s.get("fa", flash_adv))
	locked = bool(s.get("lk", locked))
	rate = float(s.get("rt", rate))
	dose = float(s.get("ds", dose))
	for key in ["ca", "br", "pu", "bz", "rp"]:
		var v = s.get(key, null)
		if v is Array:
			match key:
				"ca": carried = (v as Array).duplicate()
				"br": blown_ranges = (v as Array).duplicate(true)
				"pu": punctures = (v as Array).duplicate(true)
				"bz": bruises = (v as Array).duplicate(true)
				"rp": ripples = (v as Array).duplicate(true)
	billed = int(s.get("bl", billed))
	vis = float(s.get("vs", vis))
	tq_on = bool(s.get("tq", tq_on))
	tq_left = float(s.get("tl", tq_left))
	tq_avail = bool(s.get("ta", tq_avail))
	redness = float(s.get("rd", redness))
	deliver_t = float(s.get("dt", deliver_t))
	misses = int(s.get("ms", misses))
	blown = int(s.get("bw", blown))
	fast_pushes = int(s.get("fp", fast_pushes))
	slaps = int(s.get("sl", slaps))
	pops = int(s.get("po", pops))
	squirts = int(s.get("sq", squirts))
	sedation = float(s.get("se", sedation))


# ---------------------------------------------------------------------------- bot

## The bot plays all three stages with what the rules know (it reads the veins off the seed, not
## off the slap). `skill` 1.0 draws in taps and trims with the wheel, clears the bubbles, sticks at a
## good angle and pushes in pulses; 0.0 holds the plunger far too long, leaves the bubbles in, misses
## and blows the vein, and shoves the plunger down in one go. Deterministic: no random draws.
func bot_input(t: float, skill: float) -> Dictionary:
	var dt: float = clampf(t - _bt, 0.0, 0.1)
	_bt = t
	skill = clampf(skill, 0.0, 1.0)
	if _b.is_empty():
		_b = {"t": 0.0, "wait": 0.0, "st": 0, "tries": 0, "blows": 0, "aim_i": 0, "click": false, "prev_lmb": false}
	var out := {"cursor": metres_of_ref(Vector2(SYR_X, 360.0)), "buttons": 0}
	if not armed():
		_b.click = false
		return out
	_b.t = float(_b.t) + dt
	_b.wait = maxf(0.0, float(_b.wait) - dt)
	match phase:
		Phase.DRAW:
			return _bot_draw(skill, out)
		Phase.DEBUBBLE:
			return _bot_debubble(skill, out)
		Phase.INJECT:
			return _bot_inject(skill, out)
	return out


## One-frame click at `p`: the press this frame, released the next.
func _bot_click(p: Vector2, out: Dictionary) -> Dictionary:
	out.cursor = metres_of_ref(p)
	if bool(_b.click):
		_b.click = false
		return out
	_b.click = true
	out.buttons = int(out.buttons) | BUTTON_PRIMARY
	return out


func _bot_draw(skill: float, out: Dictionary) -> Dictionary:
	out.cursor = metres_of_ref(Vector2(SYR_X, 380.0))
	# A sloppy hand keeps pulling well past the line.
	var aim := target + lerpf(0.10, 0.0, skill)
	if skill < 0.5:
		if fluid < aim and vial > 0.0:
			out.buttons = BUTTON_PRIMARY
			return out
		out.buttons = BUTTON_ACTION if not bool(_b.click) else 0
		_b.click = not bool(_b.click)
		return out
	# A good hand draws in holds it lets go of before they run away, then trims with the wheel. It
	# aims into the top of the band, because purging bubbles costs a little of the dose; a shakier one
	# lands off to the side of it.
	aim = target + band * 0.45 + (1.0 - skill) * band * 1.6
	var speed := draw_base + _hold * draw_accel * k
	if fluid < aim - band * 0.35 - speed * 0.06:
		if _hold < air_hold / k - 0.4 and float(_b.wait) <= 0.0:
			out.buttons = BUTTON_PRIMARY
		elif _hold > 0.0:
			_b.wait = 0.08
		return out
	if fluid > aim + band * 0.35:
		if not bool(_b.click):
			out.buttons = BUTTON_SCROLL_UP
		_b.click = not bool(_b.click)
		return out
	if float(_b.wait) > 0.0:
		return out
	out.buttons = BUTTON_ACTION if not bool(_b.click) else 0
	_b.click = not bool(_b.click)
	return out


func _bot_debubble(skill: float, out: Dictionary) -> Dictionary:
	# How long this hand will spend on bubbles before it gives up and moves on.
	var patience := lerpf(0.0, 14.0, skill)
	var since := float(_b.t)
	if int(_b.st) != 1:
		_b.st = 1
		_b.t = 0.0
		since = 0.0
	if bubbles.is_empty() or since > patience:
		out.buttons = BUTTON_ACTION if not bool(_b.click) else 0
		_b.click = not bool(_b.click)
		return out
	if float(_b.wait) > 0.0 and not bool(_b.click):
		return out
	# Stuck first: a flick right beside it.
	for b in bubbles:
		if int(b[5]) == 1:
			_b.wait = 0.25
			return _bot_click(Vector2(float(b[0]), float(b[1])), out)
	# One at the needle end: purge it.
	for b in bubbles:
		if float(b[1]) - float(b[2]) - FLUID_TOP <= purge_reach / k * 0.8:
			_b.wait = 0.2
			return _bot_click(Vector2(SYR_X, pad_y() + 6.0), out)
	# Otherwise a flick every so often to hurry them up.
	_b.wait = 0.7
	return _bot_click(Vector2(SYR_X, BARREL_Y1 - 30.0), out)


## Where the bot means to put the needle in, and at what angle: [grip, angle, vein index, x].
func _bot_aim(skill: float) -> Array:
	var xs := [480.0, 330.0, 630.0, 220.0, 740.0, 400.0, 560.0]
	var tries := int(_b.tries)
	for n in xs.size() * veins.size():
		var xi := (int(_b.aim_i) + n) % xs.size()
		var vi := (n / xs.size()) % maxi(1, veins.size())
		var pv := _vein_at(vi, float(xs[xi]))
		if _is_blown(vi, pv.x) or pv.x < 0.0:
			continue
		var tan_deg := float(pv.z)
		var a := tan_deg + (window_lo + window_hi) * 0.5
		# The sloppy hand's first goes come in far too steep for the vein, and miss.
		var bad := int(round(lerpf(2.0, 0.0, skill)))
		if tries < bad:
			a += 26.0
		a = clampf(a, angle_min + 1.0, angle_max - 1.0)
		var d := Vector2(cos(deg_to_rad(a)), sin(deg_to_rad(a)))
		var reach := flash_min + 6.0
		var ent := Vector2(pv.x, pv.y) - d * reach
		return [ent - d * ASM_TIP, a, vi, pv.x]
	return [Vector2(480.0, 200.0), 25.0, 0, 480.0]


## The vein's point and tangent at `x`: (x, y, tangent degrees), x -1 when off its ends.
func _vein_at(vi: int, x: float) -> Vector3:
	if vi >= veins.size():
		return Vector3(-1.0, 0.0, 0.0)
	var pts: PackedVector2Array = veins[vi]
	for s in pts.size() - 1:
		var a: Vector2 = pts[s]
		var b: Vector2 = pts[s + 1]
		if x >= a.x and x <= b.x:
			var u := (x - a.x) / maxf(0.001, b.x - a.x)
			var q := a.lerp(b, u)
			return Vector3(q.x, q.y, rad_to_deg(atan2(b.y - a.y, b.x - a.x)))
	return Vector3(-1.0, 0.0, 0.0)


func _bot_inject(skill: float, out: Dictionary) -> Dictionary:
	if locked:
		if deliver_t >= 0.0:
			return out
		# Pulses, keeping the meter in the green; the sloppy hand just leans on it.
		var hi := lerpf(0.85, fast_rate / k - 0.06, skill)
		var lo := hi - 0.1
		var pushing := bool(_b.prev_lmb)
		if rate >= hi:
			pushing = false
		elif rate <= lo:
			pushing = true
		_b.prev_lmb = pushing
		if pushing:
			out.buttons = BUTTON_PRIMARY
		return out
	var st := int(_b.st)
	if st < 10:
		_b.st = 10 if skill >= 0.5 else 11
		_b.click = false
		st = int(_b.st)
	match st:
		10:
			# Slap the arm where it means to go in, bare-handed.
			var aim0 := _bot_aim(skill)
			if not bool(_b.click) and slaps == 0:
				return _bot_click(Vector2(float(aim0[3]), skin_top(float(aim0[3])) + 60.0), out)
			_b.click = false
			_b.st = 11
			_b.wait = 0.15
			return out
		11:
			if held:
				_b.st = 12
				_b.wait = 0.1
				return out
			if float(_b.wait) > 0.0:
				return out
			return _bot_click(TRAY, out)
		12:
			var aim := _bot_aim(skill)
			var g: Vector2 = aim[0]
			out.cursor = metres_of_ref(g)
			var err := float(aim[1]) - angle
			if absf(err) > scroll_deg * 0.55:
				if not bool(_b.click):
					out.buttons = BUTTON_SCROLL_UP if err > 0.0 else BUTTON_SCROLL_DOWN
				_b.click = not bool(_b.click)
				return out
			if float(_b.wait) > 0.0 or grip.distance_to(g) > 1.5:
				return out
			_b.st = 13
			_b.hold_for = 0.0
			return out
		13:
			var aim2 := _bot_aim(skill)
			out.cursor = metres_of_ref(aim2[0])
			# The sloppy hand blows the first vein it finds: it keeps pushing past the flash.
			var greedy := int(_b.blows) < int(round(lerpf(1.0, 0.0, skill)))
			if flashed and not greedy:
				_b.st = 14
				return out
			if not inserting and sink <= 0.0 and float(_b.get("hold_for", 0.0)) > push_hold + 0.3:
				# Blown or never started: it came back out. Try again somewhere else.
				if blown > int(_b.blows):
					_b.blows = blown
				_b.tries = int(_b.tries) + 1
				_b.aim_i = int(_b.aim_i) + 1
				_b.st = 12
				_b.wait = 0.3
				return out
			if inserting and sink >= insert_max - 0.5 and not flashed:
				_b.st = 15   # nothing there: let go (a miss)
				return out
			_b.hold_for = float(_b.get("hold_for", 0.0)) + 1.0 / 60.0
			out.buttons = BUTTON_PRIMARY
			return out
		14:
			# Let go at the flash: it locks in.
			_b.st = 16
			return out
		15:
			_b.tries = int(_b.tries) + 1
			_b.aim_i = int(_b.aim_i) + 1
			_b.st = 12
			_b.wait = 0.3
			return out
		16:
			return out
	return out


# ---------------------------------------------------------------------------- self-test

## Headless: `tools/minigame_lab.tscn -- --selftest=anesthetic`.
static func self_test() -> Array:
	var script: GDScript = load("res://scripts/surgery/arcade/inject_arcade.gd")
	var out := []
	var ok := true
	for pid: String in ["bob", "seal"]:
		for skill: float in [1.0, 0.5, 0.0]:
			var g = script.new()
			var tally := {"n": 0, "v": 0.0, "done": false, "sed": -1.0, "reasons": {}, "spikes": {}}
			g.botched.connect(func(a, r): tally.n += 1; tally.v += a; tally.reasons[r] = int(tally.reasons.get(r, 0)) + 1)
			g.finished.connect(func(r): tally.done = true; tally.sed = float(r.get("sedation", -1.0)))
			g.spiked.connect(func(kd): tally.spikes[kd] = int(tally.spikes.get(kd, 0)) + 1)
			g.setup(_ctx(pid, 1, 0))
			var t: float = run_bot(g, skill, 1.0, hash(pid) + int(skill * 100), 120.0)
			print("[inject self-test] %-4s skill=%.1f  %s  band=%.2f..%.2f  dose=%.3f  pops=%d squirts=%d  bubbles in=%d  missed=%d blown=%d fast=%d  time=%5.1fs  vitals=%5.1f  sedation=%.2f  quality=%.2f  spikes=%s" % [
				pid, skill, "DONE" if tally.done else "UNFINISHED", g.target - g.band, g.target + g.band, g.dose, g.pops, g.squirts,
				g.carried.size(), g.misses, g.blown, g.fast_pushes, t, tally.v, tally.sed, g.quality, str(tally.spikes)])
			out.append({"patient": pid, "skill": skill, "done": tally.done, "time": t, "vitals": tally.v, "sedation": tally.sed})
			if not tally.done:
				print("[inject self-test] MISS: every hand has to be able to finish")
				ok = false
			if skill == 1.0 and (tally.v > 2.0 or absf(tally.sed - 1.0) > 0.08 or t > 45.0):
				print("[inject self-test] MISS: skill 1.0 wants 0-2 vitals, sedation near 1.0 and under 45 s")
				ok = false
			if skill == 0.0 and (tally.v < 10.0 or (tally.sed >= 0.9 and tally.sed <= 1.1)):
				print("[inject self-test] MISS: skill 0.0 should pay for it and carry a wrong sedation")
				ok = false
			if skill == 0.0:
				for kd in ["miss", "blown", "fast_push", "bubble", "dose"]:
					if not tally.spikes.has(kd):
						print("[inject self-test] MISS: the sloppy run never hit '%s'" % kd)
						ok = false
			g.free()
	# The band follows the weight: the seal's sits clearly further down the barrel than Bob's.
	var gb = script.new()
	gb.setup(_ctx("bob", 1, 0))
	var gs = script.new()
	gs.setup(_ctx("seal", 1, 0))
	print("[inject self-test] by weight: bob's band at %.2f, the seal's at %.2f" % [gb.target, gs.target])
	if gs.target <= gb.target + 0.1:
		print("[inject self-test] MISS: the seal must need a clearly bigger dose")
		ok = false
	# Bob's dose into the seal is an underdose that stirs; the seal's into Bob an overdose that costs.
	var cross := _dose_result(script, "seal", gb.target)
	var over := _dose_result(script, "bob", gs.target)
	print("[inject self-test] bob's dose into the seal -> sedation %.2f (%.1f vitals); the seal's into bob -> %.2f (%.1f vitals)" % [cross[0], cross[1], over[0], over[1]])
	if cross[0] >= 0.75 or cross[1] <= 0.0 or over[0] <= 1.25 or over[1] <= 0.0:
		print("[inject self-test] MISS: a wrong dose must carry forward and cost")
		ok = false
	gb.free()
	gs.free()
	# Difficulty turns every knob: a harder shift has a narrower band and a narrower angle window.
	var g5 = script.new()
	g5.setup(_ctx("bob", 5, 0))
	print("[inject self-test] shift 5: band +/-%.3f (shift 1 +/-%.3f)" % [g5.band, 0.05])
	if g5.band >= 0.05:
		ok = false
	g5.free()
	# The tourniquet: greyed out with none, spends exactly one when there is one.
	var tq := _tourniquet_check(script)
	print("[inject self-test] tourniquet: none -> available %s; one -> available %s, pressed, spent %d, veins pinned %s, then %s" % [
		tq[0], tq[1], tq[2], tq[3], tq[4]])
	if tq[0] or not tq[1] or tq[2] != 1 or not tq[3] or tq[4] != "released":
		print("[inject self-test] MISS: the tourniquet button")
		ok = false
	# An onlooker sees what the operator sees.
	var drift := _net_round_trip(script)
	print("[inject self-test] spectator drift: fluid %.4f, phase %s, needle %.2f rpx" % [drift[0], "same" if drift[1] < 0.5 else "DIFFERENT", drift[2]])
	if drift[0] > 0.001 or drift[1] > 0.5 or drift[2] > 0.5:
		print("[inject self-test] MISS: a spectator does not see what the operator sees")
		ok = false
	# Walking away mid-step and somebody else picking it up.
	var hand := _hand_over(script)
	print("[inject self-test] hand-over: frozen fluid moved %.4f, running again %s, finished %s" % [hand[0], "yes" if hand[1] else "NO", "yes" if hand[2] else "NO"])
	if hand[0] > 0.0001 or not hand[1] or not hand[2]:
		ok = false
	print("[inject self-test] %s" % ("PASS" if ok else "FAIL"))
	return out


static func _ctx(pid: String, shift: int, tourniquets: int) -> Dictionary:
	var held := {"n": tourniquets}
	return {"patient_id": pid, "patient": Procedures.patient(pid), "ailment_id": "gunshot",
		"step": Procedures.step("gunshot", 0), "variant": "", "shift": shift,
		"difficulty": Procedures.difficulty(shift), "flags": {},
		"seed": hash("inject" + pid), "body": null, "operator": true, "operating": true,
		"hand_count": func(kind: String) -> int: return int(held.n) if kind == "tourniquet" else 0,
		"_held": held}


## [sedation, vitals] from locking `dose` into a fresh game for `pid` and delivering it.
static func _dose_result(script: GDScript, pid: String, d: float) -> Array:
	var g = script.new()
	var v := {"v": 0.0}
	g.botched.connect(func(a, _r): v.v += a)
	g.setup(_ctx(pid, 1, 0))
	g.dose = d
	g.fluid = 0.0
	g._complete()
	var r := [g.sedation, float(v.v)]
	g.free()
	return r


static func _tourniquet_check(script: GDScript) -> Array:
	var dt := 1.0 / 60.0
	var none = script.new()
	none.setup(_ctx("bob", 1, 0))
	none.phase = 2
	none.play_state = none.Play.RUNNING
	none.card_word = ""
	none.tick(dt)
	var avail_none: bool = none.tq_avail
	none.free()
	var g = script.new()
	var c := _ctx("bob", 1, 1)
	g.setup(c)
	var spent := {"n": 0}
	g.item_used.connect(func(kind, n):
		if kind == "tourniquet":
			spent.n += n
			c._held.n = int(c._held.n) - n)
	g.phase = 2
	g.play_state = g.Play.RUNNING
	g.card_word = ""
	g.tick(dt)
	var avail_one: bool = g.tq_avail
	# Click the button.
	var at: Vector2 = g.metres_of_ref(g.TQ_BTN.get_center())
	g.handle_cursor(at, 1, dt)
	g.tick(dt)
	g.handle_cursor(at, 0, dt)
	g.tick(dt)
	var t := 0.0
	while t < g.tq_time * 0.5:
		t += dt
		g.handle_cursor(Vector2.ZERO, 0, dt)
		g.tick(dt)
	var pinned: bool = g.vis >= 0.999 and g.tq_on
	while t < g.tq_time + 1.0:
		t += dt
		g.handle_cursor(Vector2.ZERO, 0, dt)
		g.tick(dt)
	var after := "released" if not g.tq_on else "STILL ON"
	# None left now: pressing again spends nothing.
	for i in 4:
		g.handle_cursor(at, 1 if i % 2 == 0 else 0, dt)
		g.tick(dt)
	if g.tq_on:
		after = "PRESSED WITH NONE"
	var r := [avail_none, avail_one, int(spent.n), pinned, after]
	g.free()
	return r


## Operator and onlooker side by side: one plays, the other only ever sees net_state at 20 Hz.
static func _net_round_trip(script: GDScript) -> Array:
	var op = script.new()
	var spec = script.new()
	op.setup(_ctx("bob", 1, 0))
	var sctx := _ctx("bob", 1, 0)
	sctx["operator"] = false
	spec.setup(sctx)
	var dt := 1.0 / 60.0
	var t := 0.0
	var n := 0
	while t < 60.0 and not op.done:
		t += dt
		var inp: Dictionary = op.bot_input(t, 1.0)
		op.handle_cursor(inp.get("cursor", Vector2.ZERO), int(inp.get("buttons", 0)), dt)
		op.tick(dt)
		spec.tick(dt)
		n += 1
		if n % 3 == 0:
			spec.apply_net_state(op.net_state())
	spec.apply_net_state(op.net_state())
	var r := [absf(spec.fluid - op.fluid), absf(float(spec.phase) - float(op.phase)), spec.tip().distance_to(op.tip())]
	op.free()
	spec.free()
	return r


## A draws a little and walks away; the syringe stops dead. B picks it up from the blob, gets the
## READY countdown, and the bot finishes the step for them.
static func _hand_over(script: GDScript) -> Array:
	var dt := 1.0 / 60.0
	var a = script.new()
	a.setup(_ctx("bob", 1, 0))
	var t := 0.0
	while t < 1.4:
		t += dt
		a.handle_cursor(a.metres_of_ref(Vector2(430.0, 380.0)), 1 if t > 0.6 else 0, dt)
		a.tick(dt)
	a.ctx["operating"] = false
	a.tick(dt)
	var parked: float = a.fluid
	for i in 30:
		a.handle_cursor(Vector2.ZERO, 1, dt)
		a.tick(dt)
	var drift := absf(a.fluid - parked)
	var b = script.new()
	var bctx := _ctx("bob", 1, 0)
	bctx["operating"] = false
	b.setup(bctx)
	b.apply_net_state(a.net_state())
	b.ctx["operating"] = true
	var counted := false
	var back := false
	for i in 200:
		b.handle_cursor(Vector2.ZERO, 0, dt)
		b.tick(dt)
		if b.play_state == b.Play.READY:
			counted = true
		elif counted and b.play_state == b.Play.RUNNING:
			back = true
			break
	var tt: float = run_bot(b, 1.0, 1.0, 7, 120.0)
	var r := [drift, back, bool(b.done)]
	a.free()
	b.free()
	return r
