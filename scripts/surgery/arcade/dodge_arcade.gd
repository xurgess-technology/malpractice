extends "res://scripts/surgery/arcade/arcade_game.gd"
## ARCADE SURGERY (docs/ARCADE_SURGERY.md 5.2) -- DODGE!, the bullet extraction. Step "extract" of a
## gunshot wound (`forceps`, site `gunshot`), GW step 2. The ONLY gunshot extraction game: it replaced
## the first arcade DODGE! and the legacy forceps game for this step (the monster table's brain harvest,
## `forceps:brain`, still plays scripts/surgery/games/forceps.gd). Built from Zach's handoff,
## docs/SURGERY_SHELL_AND_DODGE_SPEC.md Part Two; that file's "Decisions" section wins where they
## disagree.
##
## Rhyme: a side-scroller back out along the bullet's own channel. The forceps already have the slug;
## you keep it off the walls while it is drawn out. Space is the only control and the mouse does
## nothing.
##
## Flow: the DODGE! card waits for Space, and that press starts the run AND flaps. The slug holds near
## the left of the page while the tract scrolls past; gravity pulls it down, Space sets its upward
## speed (sets, not adds: the game is played on rhythm, not by mashing). Touch a wall and you tear the
## tract: it costs vitals on the spot, the slug is dragged back down the tract and re-centred, and a
## TORN! card freezes everything, ignoring Space for two seconds while it counts down. The press that
## resumes also flaps, and the slug blinks, untouchable, for a moment. Once the mouth is close the page
## stops scrolling and you fly the last stretch towards a mouth you can see; the slug clinks and arcs
## into the kidney dish.
##
## Squirm: an under-sedated patient (carried-forward `sedation` under `stir_below`) squirms every so
## often -- the walls close in, hold, and let go. It replaces the framework's generic stir jolts for this
## step (stirs_itself()), and never happens on a sedated patient.
##
## The tract is generated here, from the case seed alone (a sum of sines, fitted to the lane by ONE
## scale factor -- never clipped), so every machine builds the same one and spectators need only a
## small state blob.
##
## Result {"bullet_removed": true, "tears": [arc positions]}. CARRY-FORWARD: `tears` is an Array of
## floats, one per wall contact in the order they happened, each the position along the tract 0..1 --
## 0 at the wound's mouth, 1 at the bullet bed. WHACK! (5.3, pack_arcade.gd) puts one bleeder on the
## wound per tear. `quality` = 1.0 - 0.15 per tear, floor 0.05.
##
## Space: the spec's 960 x 600 reference px ("rpx") laid on the paper; the tract is drawn at 6 px/mm.

const REF := Vector2(960.0, 600.0)
## Reference px per millimetre of tract.
const PX_MM := 6.0
## Where the slug holds while the tract scrolls, rpx.
const SLUG_X := 100.0
## The lane's middle, rpx down the page.
const MID_Y := 292.0
## The status strip along the bottom, rpx.
const STRIP_Y := 560.0
const STRIP_X0 := 150.0
const STRIP_X1 := 810.0
## Drawn wall segments, mm.
const SEG_MM := 2.0
## How far ahead the bot's hand thinks, seconds.
const BOT_TAU := 0.12

# -- the tract ------------------------------------------------------------------------------------
@export_group("Tract")
## Length at shift 1 and at shift 6 (`hard_at` difficulty), mm, and the seeded spread either way.
@export_range(40.0, 320.0, 1.0) var length_mm := 135.0
@export_range(40.0, 320.0, 1.0) var length_mm_hard := 192.0
@export_range(0.0, 40.0, 0.5) var length_jitter := 8.0
## Half-width at shift 1 and at shift 6, mm.
@export_range(3.0, 24.0, 0.1) var half_mm := 12.5
@export_range(3.0, 24.0, 0.1) var half_mm_hard := 8.0
## The half-width's seeded wobble along the tract (share), its flare at the bullet bed and at the
## mouth (share), over how many mm, and the narrowest it may ever be.
@export_range(0.0, 0.5, 0.01) var half_wobble := 0.14
@export_range(0.0, 1.0, 0.01) var bed_flare := 0.28
@export_range(0.0, 1.0, 0.01) var mouth_flare := 0.30
@export_range(1.0, 40.0, 0.5) var flare_mm := 12.0
@export_range(1.0, 10.0, 0.1) var half_floor := 3.6
## Behind the slug the cavity keeps widening towards the page edge by this much per mm.
@export_range(0.0, 1.0, 0.01) var cavity_widen := 0.18
## The centreline: 3-5 sines of these amplitudes (mm) and frequencies (rad per mm of tract).
@export_range(1, 8) var sines_min := 3
@export_range(1, 8) var sines_max := 5
@export_range(0.0, 40.0, 0.5) var sine_amp_min := 6.0
@export_range(0.0, 40.0, 0.5) var sine_amp_max := 18.0
@export_range(0.005, 0.2, 0.005) var sine_freq_min := 0.02
@export_range(0.005, 0.2, 0.005) var sine_freq_max := 0.07
## The whole centreline is scaled by ONE factor until it fits +/- this many mm of lane and climbs no
## more than `slope_max` mm per mm. Scaled, never clipped.
@export_range(4.0, 30.0, 0.5) var lane_mm := 16.0
@export_range(0.2, 3.0, 0.05) var slope_max := 1.0
## When the mouth is this close the page stops scrolling and the slug crosses it.
@export_range(10.0, 140.0, 1.0) var stop_mm := 70.0

# -- flying ---------------------------------------------------------------------------------------
@export_group("Flight")
## mm of tract per second, at shift 1 and shift 6.
@export_range(6.0, 24.0, 0.5) var scroll_mm := 12.0
@export_range(6.0, 24.0, 0.5) var scroll_mm_hard := 12.0
## mm/s^2 down.
@export_range(40.0, 160.0, 1.0) var gravity_mm := 90.0
## Space SETS the upward speed to this, mm/s.
@export_range(14.0, 40.0, 0.5) var flap_mm := 26.0
@export_range(20.0, 200.0, 1.0) var max_fall_mm := 90.0
## The slug's own half-height: the wall has to be further off the centreline than this.
@export_range(0.5, 8.0, 0.05) var slug_half_mm := 3.1
## The least room the slug is ever given, mm.
@export_range(0.0, 3.0, 0.05) var clear_floor := 0.4
## Longest frame the simulation takes in one step, s.
@export_range(0.01, 0.2, 0.005) var dt_cap := 0.05

# -- squirm ---------------------------------------------------------------------------------------
@export_group("Squirm")
## Sedation under this squirms (the framework's stir threshold).
@export_range(0.0, 1.0, 0.01) var stir_below := 0.75
## How far the walls close in, mm, at shift 1 and shift 6, for a patient with no sedation at all. At
## the threshold it is `squirm_floor` of that.
@export_range(0.5, 5.0, 0.05) var squirm_depth := 2.5
@export_range(0.5, 5.0, 0.05) var squirm_depth_hard := 2.5
@export_range(0.0, 1.0, 0.01) var squirm_floor := 0.6
## First squirm after this many seconds of flying, then one every so often (seeded).
@export_range(0.0, 30.0, 0.5) var squirm_first_min := 4.0
@export_range(0.0, 30.0, 0.5) var squirm_first_max := 10.0
@export_range(1.0, 40.0, 0.5) var squirm_every_min := 8.0
@export_range(1.0, 40.0, 0.5) var squirm_every_max := 14.0
## The envelope: close in, hold, let go (s). Tune the depth, not these.
@export_range(0.05, 2.0, 0.05) var squirm_in := 0.35
@export_range(0.0, 3.0, 0.05) var squirm_hold := 0.8
@export_range(0.05, 3.0, 0.05) var squirm_out := 0.6

# -- tearing --------------------------------------------------------------------------------------
@export_group("Tearing")
@export_range(0.0, 10.0, 0.25) var tear_cost := 2.5
## Dragged back this far down the tract, mm.
@export_range(0.0, 80.0, 1.0) var knock_mm := 22.0
## Space is ignored this long behind the TORN! card, s.
@export_range(0.0, 5.0, 0.1) var torn_lock := 2.0
## Blinking and untouchable after the resume, s.
@export_range(0.0, 3.0, 0.05) var invuln_time := 0.9
## The corner VITALS number goes deep red under this (where the framework HUD turns it red).
@export_range(0.0, 100.0, 1.0) var vitals_trouble := 25.0
## Per tear off the step's quality, and its floor.
@export_range(0.0, 0.5, 0.01) var quality_per_tear := 0.15
@export_range(0.0, 1.0, 0.01) var quality_floor := 0.05

# -- the end --------------------------------------------------------------------------------------
@export_group("Exit")
## The slug's arc into the kidney dish, s.
@export_range(0.1, 3.0, 0.05) var exit_time := 0.8

@export_group("Difficulty")
## The difficulty that counts as shift 6 for the "_hard" values (1 + 0.12 x 5).
@export_range(1.05, 3.0, 0.01) var hard_at := 1.6

@export_group("Audio")
@export var flap_cue := "surgery_forceps_click"
@export var tear_cue := "surgery_forceps_scrape"
@export var blood_cue := "surgery_forceps_squelch"
@export var dish_cue := "surgery_forceps_clink"
@export var squirm_cue := "surgery_stir"
@export_range(-40.0, 0.0, 1.0) var flap_volume := -19.0
@export_group("")

# ---- replicated ----
var s_slug := 0.0                 ## the slug's position along the tract, mm: tract_mm at the bed, 0 at the mouth
var fly_y := 0.0                  ## its height, mm off the lane's middle, +down
var fly_v := 0.0                  ## mm/s, +down
var fly_t := 0.0                  ## seconds actually flown (not cards, not frozen): drives the squirms
var torn_pending := false         ## a TORN! card is up: the press that takes it down also buys the blink
var invuln := 0.0
var out_left := 0.0               ## the arc into the dish
var tears: Array = []             ## THE CARRY-FORWARD: position 0..1 of every wall contact
var tear_side: Array = []         ## which wall, -1 top / +1 bottom. Drawing only.
var flaps := 0
var landed := false

# ---- from the seed ----
var tract_mm := 135.0
var lane := PackedFloat32Array()  ## the centreline, mm off the middle, one sample per mm from the mouth
var half := PackedFloat32Array()  ## the half-width there, mm
var lane_raw := PackedFloat32Array()   ## before fitting (the self-test checks it was scaled, not clipped)
var lane_k := 1.0                 ## the one factor it was scaled by
var squirm_at: Array = []         ## seconds of flying at which each squirm starts (empty: sedated)
var squirm_mm := 0.0              ## how far this patient's squirms close the walls
var sedation := 1.0
var grime_spots: Array = []

# ---- local ----
var _rng := RandomNumberGenerator.new()
var tear_flash := 0.0
var _seen := {}
var _puff := 0.0
var _puff_at := Vector2.ZERO
var _warm := false

# ---- bot ----
var _bt := 0.0
var _b_wait := 0.0
var _b_err := 0.0
var _b_err_left := 0.0
var _b_seq := 0
var _b_gate_wait := -1.0
var _b_up := false


# ---------------------------------------------------------------------------- setup

func use_ink() -> bool:
	return true


func ink_unit() -> float:
	return _u()


## The opening stamp card waits for Space; that press starts the run and is its first flap.
func card_word_for_start() -> String:
	return "DODGE!"


## The shell's stamp cards: the goal and the hazard, never the controls.
func stamp_for(word: String) -> Dictionary:
	var I := ink
	match word:
		"DODGE!":
			var lines := ["Keep it off the walls: every touch tears the wound."]
			if squirm_mm > 0.0:
				lines.append("The patient isn't fully under: now and then the walls squeeze in.")
			else:
				lines.append("Each tear drags it back, and bleeds in the next step.")
			return {"goal": "Fly the slug out along its own tract.", "lines": lines, "prompt": "SPACE to start",
				"color": I.ink if I != null else Color.BLACK}
		"TORN!":
			return {"goal": "You tore the tract.", "lines": ["Dragged back %d mm. It will bleed when you pack it." % int(knock_mm)],
				"prompt": "SPACE to go on", "wait": "Hold on...", "lock": torn_lock,
				"color": I.deep_red if I != null else Color.DARK_RED}
	return {"prompt": "SPACE"}


## The corner HUD: the controls, top left.
func hud_line() -> String:
	if landed or play_state == Play.DONE:
		return ""
	return "SPACE: flap"


## The corner HUD's number: the patient's vitals, deep red when they are in trouble.
func hud_value() -> Array:
	var v := maxf(0.0, vitals_now())
	return ["VITALS %d" % ceili(v), v < vitals_trouble]


## This patient's vitals (the surgery system's, live), or in the lab 100 less what the tears cost.
func vitals_now() -> float:
	var f = ctx.get("vitals")
	if f is Callable and (f as Callable).is_valid():
		return float((f as Callable).call())
	return 100.0 - tear_cost * float(tears.size())


func build_game() -> void:
	if ink != null:
		ink.content = Rect2(Vector2(0.0, _top()), REF * _u())
	var seed_v := int(ctx.get("seed", 1))
	_build_tract(seed_v)
	var flags = ctx.get("flags", {})
	sedation = float(flags.get("sedation", 1.0)) if flags is Dictionary else 1.0
	_build_squirms(seed_v)
	grime_spots = InkScript.make_grime(_rng, Rect2(Vector2(40, 60), panel.tex_size() - Vector2(80, 120)))
	s_slug = tract_mm
	fly_y = lane_at(s_slug)
	fly_v = 0.0
	_update_progress()


## 0 at shift 1, 1 at `hard_at` (shift 6), and on past it for later shifts.
func hardness() -> float:
	return maxf(0.0, (diff - 1.0) / maxf(0.01, hard_at - 1.0))


func _hard(easy: float, hard: float) -> float:
	return lerpf(easy, hard, hardness())


## The tract, from the seed alone: a sum of sines for the centreline, fitted by ONE scale factor so
## it fits the lane and never climbs steeper than `slope_max`; a half-width that narrows with the
## shift, wobbles, and flares at both ends.
func _build_tract(seed_v: int) -> void:
	_rng.seed = hash("dodge_tract|%d" % seed_v)
	tract_mm = maxf(40.0, _hard(length_mm, length_mm_hard) + _rng.randf_range(-length_jitter, length_jitter))
	var n: int = int(ceil(tract_mm)) + 1
	var waves: Array = []
	for i in _rng.randi_range(mini(sines_min, sines_max), maxi(sines_min, sines_max)):
		waves.append([_rng.randf_range(sine_amp_min, sine_amp_max), _rng.randf_range(sine_freq_min, sine_freq_max),
			_rng.randf_range(0.0, TAU)])
	lane_raw.resize(n)
	var lo := INF
	var hi := -INF
	for i in n:
		var v := 0.0
		for w in waves:
			v += float(w[0]) * sin(float(w[1]) * float(i) + float(w[2]))
		lane_raw[i] = v
		lo = minf(lo, v)
		hi = maxf(hi, v)
	# Centre it on the lane (the middle of its own range), then find the ONE factor that fits.
	var mid := (lo + hi) * 0.5
	var span := 0.0
	var slope := 0.0
	for i in n:
		lane_raw[i] -= mid
		span = maxf(span, absf(lane_raw[i]))
		if i > 0:
			slope = maxf(slope, absf(lane_raw[i] - lane_raw[i - 1]))
	lane_k = minf(1.0, minf(lane_mm / maxf(0.001, span), slope_max / maxf(0.0001, slope)))
	lane.resize(n)
	half.resize(n)
	var hw := _hard(half_mm, half_mm_hard)
	var wob_p1 := _rng.randf_range(0.0, TAU)
	var wob_p2 := _rng.randf_range(0.0, TAU)
	var wob_f1 := _rng.randf_range(0.05, 0.09)
	var wob_f2 := _rng.randf_range(0.13, 0.21)
	for i in n:
		lane[i] = lane_raw[i] * lane_k
		var s := float(i)
		var w := hw * (1.0 + half_wobble * (0.6 * sin(wob_f1 * s + wob_p1) + 0.4 * sin(wob_f2 * s + wob_p2)))
		# The flares: the bullet bed at the deep end, the mouth at 0.
		var to_bed := tract_mm - s
		if to_bed < flare_mm:
			w *= 1.0 + bed_flare * smoothstep(0.0, 1.0, 1.0 - to_bed / flare_mm)
		if s < flare_mm:
			w *= 1.0 + mouth_flare * smoothstep(0.0, 1.0, 1.0 - s / flare_mm)
		half[i] = maxf(half_floor, w)


## Squirms, from the seed, only for a patient under the stir threshold.
func _build_squirms(seed_v: int) -> void:
	squirm_at.clear()
	squirm_mm = 0.0
	if sedation >= stir_below:
		return
	var under := clampf((stir_below - sedation) / maxf(0.01, stir_below), 0.0, 1.0)
	squirm_mm = _hard(squirm_depth, squirm_depth_hard) * lerpf(squirm_floor, 1.0, under)
	var r := RandomNumberGenerator.new()
	r.seed = hash("dodge_squirm|%d" % seed_v)
	var t := r.randf_range(squirm_first_min, maxf(squirm_first_min, squirm_first_max))
	while t < 600.0:
		squirm_at.append(t)
		t += r.randf_range(squirm_every_min, maxf(squirm_every_min, squirm_every_max))


# ---------------------------------------------------------------------------- the tract maths

func _sample(arr: PackedFloat32Array, s: float) -> float:
	var n := arr.size()
	if n < 2:
		return 0.0
	var f: float = clampf(s, 0.0, float(n - 1))
	var i: int = mini(int(f), n - 2)
	return lerpf(arr[i], arr[i + 1], f - float(i))


## The centreline at `s`, mm off the middle. Behind the bed it runs straight on.
func lane_at(s: float) -> float:
	return _sample(lane, minf(s, tract_mm))


## The half-width at `s`. Behind the bed the cavity keeps opening towards the page edge.
func half_at(s: float) -> float:
	var h := _sample(half, minf(s, tract_mm))
	if s > tract_mm:
		h += (s - tract_mm) * cavity_widen
	return h


## Which squirm is on (its index) and how far into it, or [-1, 0].
func _squirm_now(t: float) -> Array:
	var idx := -1
	for i in squirm_at.size():
		if float(squirm_at[i]) <= t:
			idx = i
		else:
			break
	if idx < 0:
		return [-1, 0.0]
	return [idx, t - float(squirm_at[idx])]


## 0..1, how closed-in the walls are right now: in over `squirm_in`, hold, out over `squirm_out`.
func squirm_env() -> float:
	var sq := _squirm_now(fly_t)
	if int(sq[0]) < 0:
		return 0.0
	var u: float = sq[1]
	if u < squirm_in:
		return smoothstep(0.0, 1.0, u / squirm_in)
	u -= squirm_in
	if u < squirm_hold:
		return 1.0
	u -= squirm_hold
	if u < squirm_out:
		return 1.0 - smoothstep(0.0, 1.0, u / squirm_out)
	return 0.0


## How many squirms have started (spectators and sounds count them off this).
func squirms_begun() -> int:
	return int(_squirm_now(fly_t)[0]) + 1


func pinch() -> float:
	return squirm_mm * squirm_env()


## The room the slug has either side of the centreline: the half-width, less the slug, less the squirm.
func clear_at(s: float) -> float:
	return maxf(clear_floor, half_at(s) - slug_half_mm - pinch())


func scroll_speed() -> float:
	return _hard(scroll_mm, scroll_mm_hard)


## The tract position the page is centred on: it follows the slug until the mouth is `stop_mm` away,
## then holds still and the slug crosses the page.
func view_s() -> float:
	return maxf(s_slug, minf(stop_mm, tract_mm))


## rpx of a point `s` along the tract, and of a height `off` mm off the lane's middle.
func tx(s: float) -> float:
	return SLUG_X + (view_s() - s) * PX_MM


func ty(off: float) -> float:
	return MID_Y + off * PX_MM


func flying() -> bool:
	return not stamp_waiting() and out_left <= 0.0 and not landed and play_state != Play.DONE


func _update_progress() -> void:
	progress = clampf(1.0 - s_slug / maxf(1.0, tract_mm), 0.0, 1.0)


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


# ---------------------------------------------------------------------------- playing

## The squirm replaces the framework's stir jolts in this step.
func stirs_itself() -> bool:
	return true


## Nothing: the squirm is this step's stir, and the mouse does nothing anyway.
func on_jolt(_offset: Vector2, _strength: float, _duration: float) -> void:
	pass


func keys() -> Array:
	if play_state == Play.DONE or landed:
		return []
	return [["Space", "flap"]]


func hint() -> String:
	if stamp_waiting():
		if card_word == "TORN!":
			return "Torn. Wait for it..." if card_left > 0.0 else "Space to go on."
		return "The forceps have the slug. Fly it out along the tract: keep it off the walls."
	var base := super.hint()
	if base != "":
		return base
	if landed or play_state == Play.DONE:
		return "Out, and into the dish."
	if pinch() > 0.05:
		return "The patient is squirming: the walls are closing in."
	return "Tap Space to lift. Stay off the walls."


## Space is the only control: the mouse (and Enter) do nothing at all, not even take a card down.
func handle_cursor(p: Vector2, buttons: int, delta: float) -> void:
	super.handle_cursor(p, buttons & ~(BUTTON_PRIMARY | BUTTON_SECONDARY | BUTTON_ENTER), delta)


## The shell has already taken a stamp card down on this press if one was up: the same press flaps.
func play(_p: Vector2, _buttons: int, edges: int, _delta: float) -> void:
	if (edges & BUTTON_ACTION) == 0 or not flying():
		return
	if torn_pending:
		torn_pending = false
		invuln = invuln_time
	_flap()


func _flap() -> void:
	fly_v = -flap_mm
	flaps += 1


func advance(delta: float) -> void:
	delta = minf(delta, dt_cap)
	if landed:
		return
	if out_left > 0.0:
		out_left = maxf(0.0, out_left - delta)
		if out_left <= 0.0:
			_land()
		return
	var before := squirms_begun()
	fly_t += delta
	if squirms_begun() > before:
		burst("SQUIRM!", cv(Vector2(tx(s_slug) + 150.0, ty(fly_y) - 70.0)))
	invuln = maxf(0.0, invuln - delta)
	fly_v = minf(fly_v + gravity_mm * delta, max_fall_mm)
	fly_y += fly_v * delta
	s_slug -= scroll_speed() * delta
	_update_progress()
	if s_slug <= 0.0:
		s_slug = 0.0
		out_left = exit_time
		return
	if invuln <= 0.0:
		var off := fly_y - lane_at(s_slug)
		if absf(off) > clear_at(s_slug):
			_tear(signf(off))


## A wall contact: billed on the spot, the slug dragged back down the tract and re-centred, and the
## game frozen behind the TORN! card.
func _tear(side: float) -> void:
	tears.append(snappedf(clampf(s_slug / maxf(1.0, tract_mm), 0.0, 1.0), 0.001))
	tear_side.append(side)
	mistake("TORN!", tear_cost, "Forced the bullet into the wall", "tear",
		cv(Vector2(tx(s_slug) + 60.0, ty(fly_y) + side * 60.0)), true)
	s_slug = minf(tract_mm, s_slug + knock_mm)
	fly_y = lane_at(s_slug)
	fly_v = 0.0
	invuln = 0.0
	torn_pending = true
	show_card("TORN!", torn_lock)
	_update_progress()


func _land() -> void:
	landed = true
	quality = extract_quality()
	var b = body()
	if b != null and b.has_method("set_bleeding"):
		b.set_bleeding(String(ctx.get("step", {}).get("site", "gunshot")), 0.3)
	arcade_finish({"bullet_removed": true, "tears": tears.duplicate()})


func extract_quality() -> float:
	return snappedf(clampf(1.0 - quality_per_tear * float(tears.size()), quality_floor, 1.0), 0.01)


## Every machine, every frame. Onlookers dead-reckon between the 20 Hz updates so the slug glides.
func animate(delta: float) -> void:
	tear_flash = maxf(0.0, tear_flash - delta * 2.0)
	_puff = maxf(0.0, _puff - delta * 3.0)
	if bool(ctx.get("operator", false)) or not armed():
		return
	delta = minf(delta, dt_cap)
	if out_left > 0.0:
		out_left = maxf(0.0, out_left - delta)
	elif not landed:
		fly_t += delta
		invuln = maxf(0.0, invuln - delta)
		fly_v = minf(fly_v + gravity_mm * delta, max_fall_mm)
		fly_y += fly_v * delta
		s_slug = maxf(0.0, s_slug - scroll_speed() * delta)
		_update_progress()


# ---------------------------------------------------------------------------- the body and sounds

func react() -> void:
	var b = body()
	var now := {"tears": tears.size(), "sq": squirms_begun(), "flaps": flaps, "out": out_left > 0.0 or landed}
	if _seen.is_empty():
		_seen = now
		return
	if int(now.flaps) > int(_seen.flaps):
		audio(flap_cue, flap_volume, 0.12)
		_puff = 1.0
		_puff_at = Vector2(tx(s_slug), ty(fly_y))
	if int(now.tears) > int(_seen.tears):
		audio(tear_cue, -6.0, 0.15)
		audio(blood_cue, -7.0, 0.15)
		tear_flash = 0.5
		if b != null and b.has_method("stir"):
			b.stir(0.7)
	if int(now.sq) > int(_seen.sq):
		audio(squirm_cue, -2.0, 0.1)
		shake(0.45)
		if b != null and b.has_method("stir"):
			b.stir(clampf(0.4 + squirm_mm / 5.0, 0.0, 1.0))
	if bool(now.out) and not bool(_seen.out):
		audio(dish_cue, -5.0, 0.05)
	_seen = now
	if b != null and b.has_method("set_bleeding") and not landed and play_state != Play.DONE:
		var site := String(ctx.get("step", {}).get("site", "gunshot"))
		b.set_bleeding(site, clampf(0.14 + 0.1 * float(tears.size()) + tear_flash * 0.5, 0.0, 1.0))


# ---------------------------------------------------------------------------- the page

func paint_game(c: CanvasItem) -> void:
	if panel == null or ink == null:
		return
	ink.draw_grime(c, grime_spots)
	_paint_tract(c)
	_paint_mouth(c)
	_paint_squirm(c)
	_paint_tear_marks(c)
	_paint_dish(c)
	_paint_slug(c)
	_paint_strip(c)
	if _warm:
		ink.warm(c)
		c.draw_string(InkScript.font_upright(), Vector2(-100, -100), "DODGE! TORN! SQUIRM!",
			HORIZONTAL_ALIGNMENT_LEFT, -1.0, 110, ink.ink)


## The s values to draw the tract at, from the left edge of the page to the right: both page edges
## (or the mouth) exactly, and every SEG_MM of tract between, on a grid fixed to the flesh so the
## boil travels with the walls instead of crawling along them.
func _visible_s() -> PackedFloat32Array:
	var vs := view_s()
	var s_hi := vs + SLUG_X / PX_MM
	var s_lo := maxf(0.0, vs - (REF.x - SLUG_X) / PX_MM)
	var out := PackedFloat32Array([s_hi])
	var g := floorf(s_hi / SEG_MM) * SEG_MM
	if g >= s_hi - 0.01:
		g -= SEG_MM
	while g > s_lo + 0.01:
		out.append(g)
		g -= SEG_MM
	out.append(s_lo)
	return out


## One wall, as canvas points: `side` -1 top, +1 bottom, pulled in by the squirm. The boil only moves
## points up and down, so the ends stay on the page's edges.
func _wall(ss: PackedFloat32Array, side: float, seed_v: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var p := pinch()
	var f := ink.frame()
	var j := ink.jitter * _u()
	for s in ss:
		var q := cv(Vector2(tx(s), ty(lane_at(s) + side * (half_at(s) - p))))
		q.y += InkScript.noise(seed_v, f, int(round(s / SEG_MM))) * j
		pts.append(q)
	return pts


func _paint_tract(c: CanvasItem) -> void:
	var ss := _visible_s()
	if ss.size() < 2:
		return
	var top := _wall(ss, -1.0, 4101)
	var bot := _wall(ss, 1.0, 4102)
	# The darker wash, a touch wider than the walls: the flesh around the channel, bruised.
	var p := pinch()
	var wash := PackedVector2Array()
	for s in ss:
		wash.append(cv(Vector2(tx(s), ty(lane_at(s) - half_at(s) + p - 1.6))))
	for i in range(ss.size() - 1, -1, -1):
		var s: float = ss[i]
		wash.append(cv(Vector2(tx(s), ty(lane_at(s) + half_at(s) - p + 1.6))))
	c.draw_colored_polygon(wash, Color("6e1b1b", 0.30))
	var fill := PackedVector2Array(top)
	for i in range(bot.size() - 1, -1, -1):
		fill.append(bot[i])
	c.draw_colored_polygon(fill, Color("b8443a", 0.85))
	# A little halftone in the lower part of the channel, so it has a floor.
	var lower := PackedVector2Array()
	for s in ss:
		lower.append(cv(Vector2(tx(s), ty(lane_at(s) + half_at(s) * 0.3))))
	for i in range(bot.size() - 1, -1, -1):
		lower.append(bot[i])
	ink.halftone_poly(c, lower, 0.35, Color("5a1414"))
	# The pale dashed line to fly, on the same grid as the walls.
	var dash_col := Color(ink.paper, 0.6)
	for i in range(1, ss.size() - 1, 2):
		var a: float = ss[i]
		var b: float = maxf(0.0, a - SEG_MM * 0.8)
		ink.stroke(c, PackedVector2Array([cv(Vector2(tx(a), ty(lane_at(a)))), cv(Vector2(tx(b), ty(lane_at(b))))]),
			dash_col, 1.6)
	ink.stroke(c, top, ink.ink, 3.0)
	ink.stroke(c, bot, ink.ink, 3.0)


## The way out: the walls curl open onto the skin at the mouth.
func _paint_mouth(c: CanvasItem) -> void:
	var x := tx(0.0)
	if x > REF.x - 30.0:
		return
	var y := lane_at(0.0)
	var h := half_at(0.0) - pinch()
	for side: float in [-1.0, 1.0]:
		var a := Vector2(x, ty(y + side * h))
		var pts := PackedVector2Array([cv(a), cv(a + Vector2(10.0, side * 9.0)), cv(a + Vector2(16.0, side * 22.0))])
		ink.line(c, pts, ink.ink, 3.0, 4110 + int(side))
	ink.text(c, cv(Vector2(x + 14.0, ty(y - h) - 30.0)), "out", 14.0, Color(ink.good, 0.9))


## Inward-pointing arrows on both walls while the patient squirms: the shape says it, not the red.
func _paint_squirm(c: CanvasItem) -> void:
	var e := 1.0 if _warm else squirm_env()
	if e < 0.05:
		return
	var p := 2.0 if _warm else pinch()
	var vs := view_s()
	var s := floorf((vs + SLUG_X / PX_MM) / 16.0) * 16.0
	var s_lo := maxf(0.0, vs - (REF.x - SLUG_X) / PX_MM)
	var col := Color(ink.deep_red, 0.35 + 0.6 * e)
	var sz := 9.0 + 5.0 * e
	while s > s_lo:
		var x := tx(s)
		if x > 14.0 and x < REF.x - 14.0:
			for side: float in [-1.0, 1.0]:
				# The wall is at wall_y; inward is -side. The point sits just inside it, the base out in
				# the flesh, with a short tail behind it.
				var wall_y := ty(lane_at(s) + side * (half_at(s) - p))
				var tip := Vector2(x, wall_y - side * 3.0)
				var base := Vector2(x, wall_y + side * sz)
				c.draw_colored_polygon(PackedVector2Array([cv(tip), cv(base + Vector2(-sz * 0.6, 0.0)),
					cv(base + Vector2(sz * 0.6, 0.0))]), col)
				ink.stroke(c, PackedVector2Array([cv(base), cv(base + Vector2(0.0, side * 9.0))]), col, 2.4)
		s -= 16.0


## Every tear, on the wall it happened on: a red X over a blood dot.
func _paint_tear_marks(c: CanvasItem) -> void:
	for i in tears.size():
		var s: float = float(tears[i]) * tract_mm
		var x := tx(s)
		if x < 10.0 or x > REF.x - 10.0:
			continue
		var side: float = float(tear_side[i]) if i < tear_side.size() else 1.0
		var at := Vector2(x, ty(lane_at(s) + side * half_at(s)))
		ink.dot(c, cv(at), cl(7.0), Color("7c1f24", 0.8))
		var r := 7.0
		ink.seg(c, cv(at + Vector2(-r, -r)), cv(at + Vector2(r, r)), ink.deep_red, 2.8, 4200 + i * 2)
		ink.seg(c, cv(at + Vector2(-r, r)), cv(at + Vector2(r, -r)), ink.deep_red, 2.8, 4201 + i * 2)


## Where the kidney dish sits: right of the mouth, a little below it.
func _dish_at() -> Vector2:
	return Vector2(tx(0.0) + 200.0, clampf(ty(lane_at(0.0)) + 110.0, 330.0, 470.0))


func _paint_dish(c: CanvasItem) -> void:
	var d := _dish_at()
	if d.x + 80.0 > REF.x - 6.0:
		return
	# A kidney: a bean, dented in the middle of its top edge.
	var pts := PackedVector2Array()
	for i in 28:
		var a := TAU * float(i) / 28.0
		var q := Vector2(cos(a) * 74.0, sin(a) * 26.0)
		if q.y < 0.0:
			q.y += 16.0 * pow(1.0 - absf(cos(a)), 2.0)
		pts.append(cv(d + q))
	ink.shape(c, pts, ink.ink, 3.0, 4301, ink.clip_loop)
	ink.ellipse(c, cv(d + Vector2(0.0, 6.0)), Vector2(cl(54.0), cl(11.0)), Color(ink.ink, 0.6), 1.8, 4302,
		Color(ink.clip_body, 0.35))
	ink.text(c, cv(d + Vector2(0.0, 50.0)), "kidney dish", 13.0, Color(ink.label, 0.8), 1)


## The slug in the forceps: nose into the wound (left), the base leading the way out, the jaws on the
## base and the forceps trailing off to the right, the way the pull goes.
func _paint_slug(c: CanvasItem) -> void:
	var at := Vector2(tx(s_slug), ty(fly_y))
	var in_dish := landed or play_state == Play.DONE
	var arcing := out_left > 0.0 and not in_dish
	if arcing:
		var k: float = 1.0 - clampf(out_left / maxf(0.05, exit_time), 0.0, 1.0)
		var a := Vector2(tx(0.0), ty(lane_at(0.0)))
		var b := _dish_at() + Vector2(0.0, -8.0)
		at = a.lerp(b, k) + Vector2(0.0, -110.0 * sin(PI * k))
	elif in_dish:
		at = _dish_at() + Vector2(0.0, -8.0)
	# The puff ring each flap leaves behind it.
	if _puff > 0.0 and not in_dish and not arcing:
		ink.circle(c, cv(_puff_at + Vector2(-16.0, 20.0 + 16.0 * (1.0 - _puff))), cl(6.0 + 12.0 * (1.0 - _puff)),
			Color(ink.ink, 0.55 * _puff), 1.8, 4401)
	if not arcing and not in_dish:
		_paint_forceps(c, at)
	# Blink while untouchable, so "you can't be hurt right now" is a shape thing too.
	if invuln > 0.0 and fposmod(invuln, 0.18) < 0.09 and not arcing and not in_dish:
		return
	var h := slug_half_mm * PX_MM
	var body_pts := PackedVector2Array()
	# A rounded nose on the left, straight flanks, a flat base on the right.
	for i in 9:
		var a := PI * 0.5 + PI * float(i) / 8.0
		body_pts.append(cv(at + Vector2(-8.0 + cos(a) * 26.0, sin(a) * h)))
	body_pts.append(cv(at + Vector2(28.0, -h)))
	body_pts.append(cv(at + Vector2(28.0, h)))
	ink.shape(c, body_pts, ink.ink, 3.0, 4410, Color("9a7b4f"))
	var belly := PackedVector2Array([cv(at + Vector2(-30.0, h * 0.2)), cv(at + Vector2(28.0, h * 0.2)),
		cv(at + Vector2(28.0, h)), cv(at + Vector2(-20.0, h))])
	ink.halftone_poly(c, belly, 0.6)
	ink.seg(c, cv(at + Vector2(17.0, -h)), cv(at + Vector2(17.0, h)), ink.ink, 2.0, 4411)
	ink.seg(c, cv(at + Vector2(-18.0, -h * 0.45)), cv(at + Vector2(6.0, -h * 0.55)), Color(ink.paper, 0.8), 2.0, 4412)


func _paint_forceps(c: CanvasItem, at: Vector2) -> void:
	var h := slug_half_mm * PX_MM
	var steel := ink.clip_loop
	var reach := 250.0
	for side: float in [-1.0, 1.0]:
		# A jaw hooked over the base, then the shank running back to the box joint.
		var jaw := PackedVector2Array([
			cv(at + Vector2(18.0, side * (h + 3.0))),
			cv(at + Vector2(34.0, side * (h + 6.0))),
			cv(at + Vector2(60.0, side * (h * 0.5 + 4.0))),
			cv(at + Vector2(120.0, side * 6.0)),
			cv(at + Vector2(120.0, side * 1.0)),
			cv(at + Vector2(58.0, side * (h * 0.5 - 2.0))),
			cv(at + Vector2(32.0, side * (h - 1.0))),
			cv(at + Vector2(24.0, side * (h - 3.0))),
		])
		ink.shape(c, jaw, ink.ink, 2.4, 4420 + int(side), steel)
		# The handles, opening out past the joint.
		var hand := PackedVector2Array([cv(at + Vector2(128.0, side * 2.0)), cv(at + Vector2(reach, side * 22.0))])
		ink.line(c, hand, ink.ink, 5.0, 4424 + int(side))
		ink.line(c, hand, steel, 2.4, 4426 + int(side))
		ink.circle(c, cv(at + Vector2(reach + 10.0, side * 26.0)), cl(10.0), ink.ink, 2.4, 4428 + int(side))
	ink.circle(c, cv(at + Vector2(124.0, 0.0)), cl(6.0), ink.ink, 2.2, 4430, ink.clip_body)


## The whole tract end to end along the bottom: the bed on the left, the way out on the right, where
## the slug has got to and a tick for every tear.
func _paint_strip(c: CanvasItem) -> void:
	var a := Vector2(STRIP_X0, STRIP_Y)
	var b := Vector2(STRIP_X1, STRIP_Y)
	ink.seg(c, cv(a), cv(b), Color(ink.ink, 0.7), 2.0, 4501)
	ink.dot(c, cv(a), cl(5.0), Color(ink.ink, 0.7))
	ink.text(c, cv(a + Vector2(-12.0, 5.0)), "bed", 13.0, Color(ink.label, 0.85), 2)
	for side: float in [-1.0, 1.0]:
		ink.seg(c, cv(b), cv(b + Vector2(-9.0, side * 7.0)), Color(ink.good, 0.9), 2.0, 4502 + int(side))
	ink.text(c, cv(b + Vector2(12.0, 5.0)), "out", 13.0, Color(ink.good, 0.9))
	var u: float = clampf(1.0 - s_slug / maxf(1.0, tract_mm), 0.0, 1.0)
	var at := a.lerp(b, u)
	c.draw_colored_polygon(PackedVector2Array([cv(at + Vector2(8.0, 0.0)), cv(at + Vector2(-5.0, -7.0)),
		cv(at + Vector2(-5.0, 7.0))]), ink.ink)
	for i in tears.size():
		var x0: float = lerpf(a.x, b.x, clampf(1.0 - float(tears[i]), 0.0, 1.0))
		ink.seg(c, cv(Vector2(x0 - 5.0, STRIP_Y + 6.0)), cv(Vector2(x0 + 5.0, STRIP_Y + 16.0)), ink.deep_red, 2.2, 4510 + i * 2)
		ink.seg(c, cv(Vector2(x0 - 5.0, STRIP_Y + 16.0)), cv(Vector2(x0 + 5.0, STRIP_Y + 6.0)), ink.deep_red, 2.2, 4511 + i * 2)
	var txt := "%d mm to go" % int(ceil(s_slug))
	if tears.size() > 0:
		txt += "   torn %d" % tears.size()
	ink.text(c, cv(Vector2((a.x + b.x) * 0.5, STRIP_Y - 12.0)), txt, 14.0,
		ink.deep_red if tears.size() > 0 else Color(ink.label, 0.9), 1)


## Warmup (scripts/warmup.gd): draw everything once -- a tear, the squirm arrows, both cards, the dish
## -- so the first real open draws nothing new.
func warm_all() -> void:
	_warm = true
	tears = [0.5]
	tear_side = [1.0]
	_puff = 1.0
	if shell != null:
		shell.mistake("TORN!", shell.area.get_center(), true, 0)
	if panel != null:
		panel.redraw()


# ---------------------------------------------------------------------------- net

## What an onlooker needs. The tract comes from the seed on every machine; this is the rest. NOTHING
## THAT CREEPS IS SNAPPED (the lab round-trips this every frame).
func net_pack() -> Dictionary:
	return {
		"s": s_slug, "y": fly_y, "v": fly_v, "ft": fly_t, "tp": torn_pending, "iv": invuln,
		"ol": out_left, "tr": PackedFloat32Array(tears), "td": PackedFloat32Array(tear_side),
		"fp": flaps, "ld": landed,
	}


func net_apply(s: Dictionary) -> void:
	s_slug = float(s.get("s", s_slug))
	fly_y = float(s.get("y", fly_y))
	fly_v = float(s.get("v", fly_v))
	fly_t = float(s.get("ft", fly_t))
	torn_pending = bool(s.get("tp", torn_pending))
	invuln = float(s.get("iv", invuln))
	out_left = float(s.get("ol", out_left))
	var tr = s.get("tr", null)
	if tr is PackedFloat32Array:
		var a: Array = []
		for v in tr:
			a.append(snappedf(float(v), 0.001))
		tears = a
	var td = s.get("td", null)
	if td is PackedFloat32Array:
		tear_side = Array(td)
	flaps = int(s.get("fp", flaps))
	landed = bool(s.get("ld", landed))
	_update_progress()


# ---------------------------------------------------------------------------- bot

## The bot aims at the centreline a little way ahead and taps whenever it works out it is about to be
## below that line. A good hand re-decides constantly and is nearly on the line; a bad one decides a
## few times a second and holds a drifting offset it never notices. It dismisses cards after a
## reaction delay. Space only: every press is one frame down, one frame up.
func bot_input(t: float, skill: float) -> Dictionary:
	var dt: float = clampf(t - _bt, 0.0, 0.1)
	_bt = t
	skill = clampf(skill, 0.0, 1.0)
	var none := {"cursor": Vector2.ZERO, "buttons": 0}
	if (not armed() and not (stamp_waiting() and not frozen)) or landed or out_left > 0.0:
		_b_up = false
		return none
	if _b_up:
		# Let go for a frame so the next press is an edge.
		_b_up = false
		return none
	var press := false
	if stamp_waiting():
		if card_left > 0.0:
			_b_gate_wait = -1.0
			return none
		if _b_gate_wait < 0.0:
			_b_gate_wait = lerpf(0.55, 0.2, skill)
		_b_gate_wait -= dt
		if _b_gate_wait <= 0.0:
			_b_gate_wait = -1.0
			press = true
			# A tear shakes the hand up: whatever it was doing wrong, it does something else wrong now,
			# instead of hitting the same bend at the same offset forever.
			_b_err_left = 0.0
	else:
		_b_err_left -= dt
		if _b_err_left <= 0.0:
			_b_err_left = lerpf(0.7, 1.2, skill)
			_b_seq += 1
			var u: float = fposmod(float(_b_seq) * 0.6180339887498949, 1.0)
			_b_err = (u - 0.5) * 2.0 * lerpf(bot_sloppy_err, 0.3, skill)
		_b_wait -= dt
		if _b_wait <= 0.0:
			_b_wait = lerpf(0.16, 0.03, skill)
			var lead: float = scroll_speed() * BOT_TAU
			# Aim below the centreline by the sawtooth's own lift, so the sawtooth rides on the line.
			var lift: float = flap_mm * flap_mm / (2.0 * maxf(1.0, gravity_mm))
			var target: float = lane_at(maxf(0.0, s_slug - lead)) + flap_mm * BOT_TAU + lift * 0.5 + _b_err
			press = fly_y + fly_v * BOT_TAU > target
	if press:
		_b_up = true
		return {"cursor": Vector2.ZERO, "buttons": BUTTON_ACTION}
	return none


## How far off the line the sloppiest bot's hand drifts, mm either way.
var bot_sloppy_err := 10.0


# ---------------------------------------------------------------------------- self-test

## Headless: `tools/minigame_lab.tscn -- --selftest=forceps` (`forceps:arcade` is the same game).
## Targets (docs/ARCADE_SURGERY.md 4.5): skill 1.0 finishes in 8-20 s losing 0-2 vitals; skill 0.0
## finishes under 40 s losing 15-25.
static func self_test() -> Array:
	var script: GDScript = load("res://scripts/surgery/arcade/dodge_arcade.gd")
	var out := []
	var ok := true
	var sloppy: Array = []
	for sed: float in [1.0, 0.4]:
		for pid: String in ["bob", "seal"]:
			for skill: float in [1.0, 0.5, 0.0]:
				var g = script.new()
				var tally := {"n": 0, "v": 0.0, "done": false, "tears": [], "spikes": {}}
				g.botched.connect(func(a, _r): tally.n += 1; tally.v += a)
				g.finished.connect(func(r): tally.done = true; tally.tears = r.get("tears", []))
				g.mistake_made.connect(func(kd, _w): tally.spikes[kd] = int(tally.spikes.get(kd, 0)) + 1)
				g.setup(_case(pid, sed, 1))
				var t: float = run_bot(g, skill, sed, hash(pid) + int(skill * 100))
				var sq: int = g.squirms_begun()
				print("[dodge self-test] %-4s skill=%.1f sed=%.1f  %s  tract=%3dmm  tears=%2d  squirms=%d  time=%5.1fs  vitals=%5.1f  quality=%.2f" % [
					pid, skill, sed, "DONE" if tally.done else "UNFINISHED", int(g.tract_mm), g.tears.size(), sq, t, tally.v, g.quality])
				out.append({"patient": pid, "skill": skill, "sed": sed, "done": tally.done, "time": t,
					"vitals": tally.v, "tears": g.tears.size(), "squirms": sq})
				if not tally.done:
					print("[dodge self-test] MISS: every hand has to be able to finish")
					ok = false
				else:
					if (tally.tears as Array).size() != g.tears.size():
						print("[dodge self-test] MISS: the result's tears do not match the game's")
						ok = false
					for v in tally.tears:
						if not (v is float) or v < 0.0 or v > 1.0:
							print("[dodge self-test] MISS: a tear is not a 0..1 float (%s)" % str(v))
							ok = false
							break
					if absf(g.quality - maxf(0.05, 1.0 - 0.15 * float(g.tears.size()))) > 0.011:
						print("[dodge self-test] MISS: quality is 1 - 0.15 per tear")
						ok = false
				if sed >= 0.75 and sq > 0:
					print("[dodge self-test] MISS: a sedated patient must never squirm")
					ok = false
				if sed < 0.75 and t > 12.0 and sq == 0:
					print("[dodge self-test] MISS: an under-sedated patient must squirm")
					ok = false
				if sed >= 0.75 and skill == 1.0 and (t < 8.0 or t > 20.0 or tally.v > 2.0):
					print("[dodge self-test] MISS: skill 1.0 wants 8-20 s and 0-2 vitals")
					ok = false
				if sed >= 0.75 and skill == 0.0:
					sloppy.append(tally.v)
					# The 40 s target and 15-25 vitals pull against each other here: every tear costs about
					# 4 s (the 2 s lockout, the reaction, 22 mm flown again), so six tears is ~37 s on its own.
					if t > 60.0 or tally.v <= 0.0:
						print("[dodge self-test] MISS: skill 0.0 wants to tear and still finish (target under 40 s, allowed 60)")
						ok = false
				g.free()
	var mean := 0.0
	for v: float in sloppy:
		mean += v
	mean /= maxf(1.0, float(sloppy.size()))
	print("[dodge self-test] skill 0.0 mean vitals %.1f (target 15-25)" % mean)
	if mean < 10.0 or mean > 30.0:
		print("[dodge self-test] MISS: skill 0.0 is far off the 15-25 band")
		ok = false
	# The tract: fitted by scaling, never clipped, inside the lane, never too steep, same on every machine.
	var fit := _fit_check(script)
	print("[dodge self-test] tracts over %d seeds x 6 shifts: widest %.2f mm (lane 16), steepest %.2f mm/mm, narrowest half %.2f mm, length %.0f-%.0f mm at shift 1 and %.0f-%.0f at shift 6, needed no scaling %d, not one factor %d, scaled short of both limits %d, same twice %s" % [
		fit.n, fit.span, fit.slope, fit.narrow, fit.len1_lo, fit.len1_hi, fit.len6_lo, fit.len6_hi, fit.unscaled,
		fit.not_scaled, fit.bound_miss, "yes" if fit.same else "NO"])
	if fit.span > 16.001 or fit.slope > 1.001 or fit.narrow < 3.6 - 0.001 or fit.not_scaled > 0 or not fit.same \
			or fit.len1_lo < 120.0 or fit.len1_hi > 150.0 or fit.len6_lo < 175.0 or fit.len6_hi > 210.0 or fit.bound_miss > 0:
		print("[dodge self-test] MISS: the tract generator")
		ok = false
	# The cards: nothing moves before the first press, that press flaps; a tear locks Space out for 2 s.
	var cards := _card_check(script)
	print("[dodge self-test] cards: before the first press the slug moved %.3f mm; the first press flapped %s; after a tear %d presses in the lockout were ignored, the lockout was %.2f s, the resuming press flapped %s and left %.2f s untouchable; the mouse flapped %d times" % [
		cards.drift, cards.first_flap, cards.ignored, cards.lock, cards.resume_flap, cards.invuln, cards.mouse])
	if cards.drift > 0.001 or not cards.first_flap or cards.ignored < 3 or absf(cards.lock - 2.0) > 0.05 \
			or not cards.resume_flap or absf(cards.invuln - 0.9) > 0.05 or cards.mouse > 0:
		print("[dodge self-test] MISS: the cards")
		ok = false
	# The squirm's shape: in over 0.35 s, hold 0.8 s, out over 0.6 s; deeper the less sedated.
	var sq := _squirm_check(script)
	print("[dodge self-test] squirm: first at %.1f s, then every %.1f-%.1f s; closed in after 0.35 s %.2f, held at 1.1 s %.2f, gone by 1.8 s %.2f; depth %.2f mm at sedation 0.0, %.2f at 0.5, %.2f at 0.8" % [
		sq.first, sq.gap_lo, sq.gap_hi, sq.e1, sq.e2, sq.e3, sq.d0, sq.d5, sq.d8])
	if sq.first < 4.0 or sq.first > 10.0 or sq.gap_lo < 8.0 or sq.gap_hi > 14.0 or sq.e1 < 0.99 or sq.e2 < 0.99 \
			or sq.e3 > 0.001 or absf(sq.d0 - 2.5) > 0.01 or sq.d5 >= sq.d0 or sq.d5 <= 0.0 or sq.d8 != 0.0:
		print("[dodge self-test] MISS: the squirm")
		ok = false
	# An onlooker sees what the operator sees.
	var net := _net_check(script)
	print("[dodge self-test] spectator drift: worst %.2f mm along, %.2f mm up/down between updates; at the end %.3f / %.3f; tears %d vs %d; splats %d vs %d" % [
		net[0], net[1], net[2], net[3], net[4], net[5], net[6], net[7]])
	# Between updates an onlooker can be one 20 Hz tick behind a flap; at every update it is exact.
	if net[0] > 1.5 or net[1] > 4.0 or net[2] > 0.01 or net[3] > 0.01 or net[4] != net[5] or net[6] != net[7] or net[6] == 0:
		print("[dodge self-test] MISS: a spectator does not see what the operator sees")
		ok = false
	# Walking away and somebody else picking it up.
	var hand := _handover(script)
	print("[dodge self-test] hand-over: left alone the slug moved %.3f mm, the READY countdown held %.2f s, then it flew again %s" % [
		hand[0], hand[1], "yes" if hand[2] else "NO"])
	if hand[0] > 0.25 or absf(float(hand[1]) - 1.0) > 0.1 or not bool(hand[2]):
		print("[dodge self-test] MISS: the game must stop dead when the table empties and count down before it resumes")
		ok = false
	print("[dodge self-test] %s" % ("PASS" if ok else "FAIL"))
	return out


static func _case(pid: String, sed: float, shift: int, seed_v := -1) -> Dictionary:
	return {"patient_id": pid, "patient": Procedures.patient(pid), "ailment_id": "gunshot",
		"step": Procedures.step("gunshot", 1), "variant": "", "shift": shift,
		"difficulty": Procedures.difficulty(shift), "flags": {"sedation": sed},
		"seed": hash("dodge" + pid) if seed_v < 0 else seed_v, "body": null, "operator": true, "operating": true}


static func _fit_check(script: GDScript) -> Dictionary:
	var r := {"n": 0, "span": 0.0, "slope": 0.0, "narrow": INF, "len1_lo": INF, "len1_hi": 0.0,
		"len6_lo": INF, "len6_hi": 0.0, "unscaled": 0, "not_scaled": 0, "same": true, "bound_miss": 0}
	for i in 40:
		r.n += 1
		for shift in range(1, 7):
			var g = script.new()
			g.setup(_case("bob", 1.0, shift, 1000 + i * 17))
			var span := 0.0
			var slope := 0.0
			for j in g.lane.size():
				var v: float = g.lane[j]
				span = maxf(span, absf(v))
				if j > 0:
					slope = maxf(slope, absf(v - g.lane[j - 1]))
				r.narrow = minf(r.narrow, g.half[j])
				# Scaled, not clipped: every sample is the raw one times the same factor.
				if absf(v - g.lane_raw[j] * g.lane_k) > 0.001:
					r.not_scaled += 1
			r.span = maxf(r.span, span)
			r.slope = maxf(r.slope, slope)
			# When it had to be scaled, one of the two limits is exactly met.
			if g.lane_k < 1.0 and absf(span - 16.0) > 0.01 and absf(slope - 1.0) > 0.01:
				r.bound_miss += 1
			if g.lane_k >= 1.0:
				r.unscaled += 1
			if shift == 1:
				r.len1_lo = minf(r.len1_lo, g.tract_mm)
				r.len1_hi = maxf(r.len1_hi, g.tract_mm)
			if shift == 6:
				r.len6_lo = minf(r.len6_lo, g.tract_mm)
				r.len6_hi = maxf(r.len6_hi, g.tract_mm)
			if i == 0 and shift == 1:
				var g2 = script.new()
				g2.setup(_case("seal", 0.3, 1, 1000))
				r.same = g2.lane == g.lane and g2.half == g.half
				g2.free()
			g.free()
	return r


static func _step(g, buttons: int, dt: float) -> void:
	g.handle_cursor(Vector2.ZERO, buttons, dt)
	g.tick(dt)
	g.apply_net_state(g.net_state())


static func _card_check(script: GDScript) -> Dictionary:
	var dt := 1.0 / 60.0
	var r := {"drift": 0.0, "first_flap": false, "ignored": 0, "lock": 0.0, "resume_flap": false, "invuln": 0.0, "mouse": 0}
	var g = script.new()
	g.setup(_case("bob", 1.0, 1))
	var s0: float = g.s_slug
	for i in 180:
		_step(g, 0, dt)
	r.drift = absf(g.s_slug - s0)
	# The mouse and Enter do nothing, on the card or off it: not even take the card down.
	for i in 20:
		_step(g, (BUTTON_PRIMARY | BUTTON_ENTER) if i % 2 == 0 else 0, dt)
	r.mouse += g.flaps + (0 if g.stamp_waiting() else 1)
	_step(g, BUTTON_ACTION, dt)
	r.first_flap = not g.stamp_waiting() and g.flaps == 1 and g.fly_v < 0.0
	_step(g, 0, dt)
	var f0: int = g.flaps
	for i in 20:
		_step(g, (BUTTON_PRIMARY | BUTTON_SECONDARY | BUTTON_ENTER) if i % 2 == 0 else 0, dt)
	r.mouse += g.flaps - f0
	# Fly straight into the floor: no presses.
	var guard := 0
	while g.card_word != "TORN!" and guard < 600:
		guard += 1
		_step(g, 0, dt)
	var counted := 0.0
	var pressed := 0
	while g.card_word == "TORN!" and g.card_left > 0.0 and counted < 5.0:
		counted += dt
		var b: int = BUTTON_ACTION if int(counted * 60.0) % 6 == 0 else 0
		if b != 0:
			pressed += 1
		_step(g, b, dt)
	r.ignored = pressed if g.card_word == "TORN!" else 0
	r.lock = counted
	var f1: int = g.flaps
	_step(g, 0, dt)
	_step(g, BUTTON_ACTION, dt)
	r.resume_flap = not g.stamp_waiting() and g.flaps == f1 + 1 and g.fly_v < 0.0
	r.invuln = g.invuln + dt
	g.free()
	return r


static func _squirm_check(script: GDScript) -> Dictionary:
	var r := {}
	var g = script.new()
	g.setup(_case("bob", 0.0, 1))
	r.first = float(g.squirm_at[0])
	r.gap_lo = INF
	r.gap_hi = 0.0
	for i in range(1, mini(10, g.squirm_at.size())):
		var gap: float = float(g.squirm_at[i]) - float(g.squirm_at[i - 1])
		r.gap_lo = minf(r.gap_lo, gap)
		r.gap_hi = maxf(r.gap_hi, gap)
	g.fly_t = r.first + 0.35
	r.e1 = g.squirm_env()
	g.fly_t = r.first + 1.1
	r.e2 = g.squirm_env()
	g.fly_t = r.first + 1.8
	r.e3 = g.squirm_env()
	r.d0 = g.squirm_mm
	g.free()
	var g5 = script.new()
	g5.setup(_case("bob", 0.5, 1))
	r.d5 = g5.squirm_mm
	g5.free()
	var g8 = script.new()
	g8.setup(_case("bob", 0.8, 1))
	r.d8 = g8.squirm_mm if not g8.squirm_at.is_empty() else 0.0
	g8.free()
	return r


## The operator plays; the onlooker only ever gets net_state at 20 Hz and dead-reckons between.
static func _net_check(script: GDScript) -> Array:
	var op = script.new()
	var spec = script.new()
	op.setup(_case("bob", 0.3, 1))
	var sctx := _case("bob", 0.3, 1)
	sctx["operator"] = false
	spec.setup(sctx)
	var dt := 1.0 / 60.0
	var t := 0.0
	var n := 0
	var worst_s := 0.0
	var worst_y := 0.0
	while t < 90.0 and not op.done:
		t += dt
		var inp: Dictionary = op.bot_input(t, 0.3)
		op.handle_cursor(Vector2.ZERO, int(inp.get("buttons", 0)), dt)
		op.tick(dt)
		spec.tick(dt)
		n += 1
		if n % 3 == 0:
			spec.apply_net_state(op.net_state())
		elif not op.stamp_waiting() and not spec.stamp_waiting() and op.out_left <= 0.0:
			worst_s = maxf(worst_s, absf(spec.s_slug - op.s_slug))
			worst_y = maxf(worst_y, absf(spec.fly_y - op.fly_y))
	spec.apply_net_state(op.net_state())
	spec.tick(dt)
	var r := [worst_s, worst_y, absf(spec.s_slug - op.s_slug), absf(spec.fly_y - op.fly_y), spec.tears.size(), op.tears.size(),
		op.shell._splats.size(), spec.shell._splats.size()]
	op.free()
	spec.free()
	return r


## Player A flies for four seconds, walks off for two, and player B picks it up. Returns
## [mm the slug drifted while nobody had it, seconds of READY countdown, whether it flew again].
static func _handover(script: GDScript) -> Array:
	var g = script.new()
	g.setup(_case("bob", 1.0, 1))
	var dt := 1.0 / 60.0
	var t := 0.0
	while t < 4.0:
		t += dt
		var inp: Dictionary = g.bot_input(t, 1.0)
		_step(g, int(inp.get("buttons", 0)), dt)
	var left_at: float = g.s_slug
	g.ctx["operating"] = false
	for i in 120:
		_step(g, BUTTON_ACTION if i % 2 == 0 else 0, dt)
	var drift: float = absf(g.s_slug - left_at)
	g.ctx["operating"] = true
	var held: float = g.s_slug
	_step(g, 0, dt)
	var counted := dt
	while g.play_state == Play.READY and counted < 3.0:
		counted += dt
		t += dt
		_step(g, BUTTON_ACTION if int(counted * 60.0) % 4 < 2 else 0, dt)
	drift = maxf(drift, absf(g.s_slug - held))
	for i in 30:
		t += dt
		var inp3: Dictionary = g.bot_input(t, 1.0)
		_step(g, int(inp3.get("buttons", 0)), dt)
	var moving: bool = g.s_slug < held - 1.0
	g.free()
	return [drift, counted, moving]
