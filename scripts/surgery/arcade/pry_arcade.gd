extends "res://scripts/surgery/arcade/arcade_game.gd"
## ARCADE SURGERY (docs/ARCADE_SURGERY.md) 5.9 -- PRY! Step "scoop" of an eyeball extraction or a
## graft: get the eye out of its socket. The arcade rebuild of the `scoop` variant of
## scripts/surgery/games/eye_ops.gd, played on the raised panel.
##
## Rhyme: lockpicking. Feel for the sweet spot, then lever.
##
## What you do
##   Top view: the eye sitting in its socket rim, with four to six muscle TETHERS still holding it
##   down at seeded angles. The spoon rides the rim wherever the mouse points it.
##   Come within reach of a tether and the spoon starts to SHAKE. That shake is the whole game and
##   it is felt, not read: it is worst out on the tether's flanks and it goes STILL at the one spot
##   where the spoon is under the tether instead of against it. Nothing on the panel tells you where
##   that spot is. You sweep until the shaking stops.
##   Hold the mouse there and the tether comes up taut, then lets go with a wet pop. Hold anywhere
##   else and the spoon judders, its bowl cracks open, and it slips out of the socket -- which on a
##   strapped Hive is a spoonful of eyeball and costs.
##   One tether is TOUGH: drawn with three strands instead of one, its quiet spot is half as wide,
##   and it takes two pops. After the first the eye shifts and the spot is somewhere else.
##   CARRY-FORWARD, and this is the point of it: the eye rocks looser in the socket with every
##   tether you take off, which swings the quiet spots around. On a Hive whose sedation has worn
##   under 0.35 the rocking turns into a twitch too fast to follow. Dawdle and the job gets harder
##   in front of you.
##
## Result {"eye_out": true, "pry_quality": q}, the same flag the legacy scoop finishes on.
## On a graft (`no_fail`) nothing is ever charged: the spoon still slips, the patient just yelps.

# -- the socket -------------------------------------------------------------------------------
## The eye's radius on the panel at the standard 15.5 mm eyeball; a smaller eye draws smaller.
@export_range(8.0, 30.0, 0.5) var eye_draw_mm := 15.5
## Rim clearance: how far outside the eye the socket rim (and the spoon's track) sits.
@export_range(3.0, 24.0, 0.5) var rim_gap_mm := 13.5
## How many tethers, before the seed picks one of them.
@export_range(2, 8) var tethers_min := 4
@export_range(2, 8) var tethers_max := 6
## No two tethers closer together than this, so there is always room to work between them.
@export_range(10.0, 90.0, 1.0) var tether_apart_deg := 35.0

# -- feeling for it ---------------------------------------------------------------------------
## Reach: the spoon only touches a tether, and only shakes, within this much of it.
@export_range(5.0, 60.0, 1.0) var sense_deg := 25.0
## Half-width of the quiet spot, before difficulty narrows it.
@export_range(1.0, 20.0, 0.5) var sweet_deg := 6.0
## The tough tether's quiet spot is this much of a normal one's.
@export_range(0.1, 1.0, 0.05) var tough_sweet_frac := 0.5
## How far off its tether a quiet spot may be seeded.
@export_range(0.0, 30.0, 0.5) var sweet_spread_deg := 15.0
## And how far the tough one's moves after its first pop.
@export_range(0.0, 30.0, 0.5) var tough_reroll_deg := 10.0
## How far the spoon shakes at its worst, tangentially along the rim.
@export_range(0.0, 20.0, 0.25) var wobble_mm := 6.0
@export_range(0.5, 20.0, 0.1) var wobble_hz := 7.5
## The shake starts easing off this many quiet-spot widths out: the gradient you hunt along.
@export_range(1.0, 6.0, 0.1) var feel_span := 2.2

# -- levering ---------------------------------------------------------------------------------
## Seconds in the quiet spot to bring a tether up taut and pop it.
@export_range(0.1, 4.0, 0.05) var lever_time := 0.8
## Seconds of levering anywhere else before the spoon slips out.
@export_range(0.1, 4.0, 0.05) var slip_after := 0.6
## And how long it takes to get the spoon back in the socket.
@export_range(0.1, 3.0, 0.05) var slip_time := 0.5
## However badly the tether fights, one lever always resolves inside this many seconds: it pops or
## the spoon comes out. Without it a tether the eye keeps dragging off the spoon can be leaned on
## forever, which is a stall, not a difficulty.
@export_range(0.5, 12.0, 0.1) var lever_limit := 3.2
@export_range(0.0, 10.0, 0.5) var slip_botch := 2.0

# -- the eye's own state ----------------------------------------------------------------------
## How far the loosened eye rocks in its socket, in degrees, once every tether is off.
@export_range(0.0, 30.0, 0.5) var rock_deg := 5.0
@export_range(0.05, 3.0, 0.05) var rock_hz := 0.45
## And how far it slides, so a loose eye reads as loose and not just as a turning one.
@export_range(0.0, 8.0, 0.1) var rock_slide_mm := 1.4
## Sedation at or under which a Hive's eye starts twitching on top of the rocking.
@export_range(0.0, 1.0, 0.01) var twitch_from := 0.35
## How far it twitches, too fast to follow.
@export_range(0.0, 45.0, 0.5) var twitch_deg := 18.0
@export_range(0.5, 10.0, 0.1) var twitch_hz := 3.1
## Ceiling on how far the twitch may move a quiet spot, as a fraction of the NARROWEST one on the
## eye. Under 1 by design: a Hive that has woken all the way up is a horrible job, but it is never
## an impossible one, and a hand that has found the spot keeps it.
@export_range(0.1, 1.0, 0.05) var twitch_cap := 0.9
## How much of the shake is pure twitch noise -- the part that does NOT go quiet over the sweet
## spot. This is what actually stops you feeling for it: the eye is buzzing everywhere at once.
@export_range(0.0, 2.0, 0.05) var twitch_noise := 0.85
## And how much worse a hand guesses when it cannot feel the notch any more.
@export_range(0.0, 4.0, 0.1) var bot_twitch_err := 1.6

# -- audio ------------------------------------------------------------------------------------
@export var pop_cue := "surgery_forceps_squelch"
@export var slip_cue := "surgery_forceps_scrape"
@export var yelp_cue := "surgery_stir"
@export var seat_cue := "surgery_forceps_click"
@export var taut_cue := "surgery_tear"
@export_range(-40.0, 0.0, 1.0) var seat_volume := -16.0

# -- the bot ----------------------------------------------------------------------------------
## How far out a sloppy hand thinks the quiet spot is. A good hand is near enough spot on.
@export_range(0.0, 45.0, 0.5) var bot_err_deg := 15.0
## And how fast it works its way round the rim, in degrees a second.
@export_range(10.0, 400.0, 5.0) var bot_slow_speed := 50.0
@export_range(10.0, 400.0, 5.0) var bot_fast_speed := 95.0
## How long it feels around before it commits, and how long it will chase a twitch before it
## commits anyway rather than standing there forever.
@export_range(0.0, 2.0, 0.01) var bot_feel_slow := 0.30
@export_range(0.0, 2.0, 0.01) var bot_feel_fast := 0.18
@export_range(0.5, 10.0, 0.1) var bot_patience := 2.5

# ---- replicated state ----
var spoon_a := 0.0                ## degrees round the rim; the spoon's track position
var levering := false             ## the mouse went down and has not come up
var tension := 0.0                ## 0..1, the tether coming taut
var shudder := 0.0                ## seconds of levering in the wrong place
var slip_left := 0.0              ## seconds until the spoon is back in the socket
var slips := 0
var popped: Array = []            ## per tether: how many pops it has taken
var sweet_off: Array = []         ## per tether: degrees from the cord to its quiet spot
var pop_flash := 0.0
var slip_flash := 0.0
var _t := 0.0                     ## the clock the rocking and the shake run on

# ---- derived from the seed ----
var tether_n := 5
var tether_deg: Array = []        ## where each cord sits, degrees, before the eye rocks
var tough := 0                    ## which one is the tough one
var eye_mm := 19.0
var rim_mm := 27.0
var no_fail := false

# ---- local ----
var _rng := RandomNumberGenerator.new()
var _seen_pops := 0
var _seen_slips := 0
var _wob_phase := 0.0
var _shown_wob := 0.0
var _taut := false
var _lever_t := 0.0

# ---- bot ----
var _bt := 0.0
var _b_aim := 0.0
var _b_seq := 0
var _b_err := 0.0
var _b_err_for := -1
var _b_feel := 0.0
var _b_chase := 0.0
var _b_release := 0.0
var _b_pops := -1
var _b_held := false


# ---------------------------------------------------------------------------- setup

func card_word_for_start() -> String:
	return "PRY!"


func build_game() -> void:
	no_fail = bool(ctx.get("no_fail", false))
	_rng.seed = int(ctx.get("seed", 1)) ^ 0x9e7
	var r_m := float(ctx.get("eye_radius", 0.0155))
	eye_mm = clampf(eye_draw_mm * (r_m / 0.0155), 10.0, 24.0)
	rim_mm = eye_mm + rim_gap_mm
	_seed_tethers()
	spoon_a = tether_deg[0] + sense_deg + 30.0
	_b_aim = spoon_a
	_update_progress()


## Four to six cords, spread round the eye and never closer than `tether_apart_deg`, with a quiet
## spot seeded somewhere along each one's reach. Everything here comes off the case seed, so every
## machine is prying at the same eye.
func _seed_tethers() -> void:
	tether_n = _rng.randi_range(mini(tethers_min, tethers_max), maxi(tethers_min, tethers_max))
	var step := 360.0 / float(tether_n)
	var jitter: float = maxf(0.0, (step - tether_apart_deg) * 0.5)
	var spread: float = minf(sweet_spread_deg, sense_deg - sweet_deg - 1.0)
	tether_deg.clear()
	sweet_off.clear()
	popped.clear()
	var base := _rng.randf_range(0.0, 360.0)
	for i in tether_n:
		tether_deg.append(_wrap180(base + step * float(i) + _rng.randf_range(-jitter, jitter)))
		sweet_off.append(_rng.randf_range(-spread, spread))
		popped.append(0)
	tough = _rng.randi_range(0, tether_n - 1)


## How many pops the whole eye takes: one each, and two off the tough one.
func total_pops() -> int:
	return tether_n + 1


func pops_done() -> int:
	var n := 0
	for p in popped:
		n += int(p)
	return n


func pops_needed(i: int) -> int:
	return 2 if i == tough else 1


func live(i: int) -> bool:
	return int(popped[i]) < pops_needed(i)


func tethers_left() -> int:
	var n := 0
	for i in tether_n:
		if live(i):
			n += 1
	return n


# ---------------------------------------------------------------------------- the eye's state

## 0 at the start, 1 when the last tether is off: how loose the eye is sitting.
func looseness() -> float:
	return clampf(float(pops_done()) / maxf(1.0, float(total_pops())), 0.0, 1.0)


## The patient's sedation RIGHT NOW. Read live, not cached: on the monster table it is wearing off
## under you (Dissection.SEDATION_SECONDS), and that is exactly the carry-forward this step has.
func sedation() -> float:
	if no_fail:
		return 1.0
	var flags: Dictionary = ctx.get("flags", {})
	return clampf(float(flags.get("sedation", 1.0)), 0.0, 1.0)


## How much of a twitch is on top of the rocking, 0..1. Nothing while the patient is under; worse
## as the sedation goes and worse again as the eye comes loose.
func twitch_amount() -> float:
	var k: float = clampf((twitch_from - sedation()) / maxf(0.01, twitch_from), 0.0, 1.0)
	return k * (0.3 + 0.7 * looseness())


## The readable half of the eye's movement: the slow roll of an eye sitting looser and looser in
## its socket. Slow enough to follow with a hand, which is the point -- the quiet spots swing round
## with it and you are expected to keep up.
func rock_slow() -> float:
	return sin(_t * TAU * rock_hz) * rock_deg * looseness()


## The twitch's wave: two frequencies that do not line up, so it cannot be read as a rhythm and
## ridden. -1..1.
func twitch_wave() -> float:
	return sin(_t * TAU * twitch_hz) * 0.62 + sin(_t * TAU * twitch_hz * 2.37 + 1.1) * 0.38


## How far a quiet spot may ever be dragged by the twitch: under the width of the narrowest one on
## the eye, so the twitch makes the job horrible without ever making it impossible.
func twitch_ceiling() -> float:
	return sweet_deg * tough_sweet_frac * twitch_cap / sqrt(diff)


## And the part nobody can follow: the jerk of a Hive coming round, in degrees.
func twitch_now() -> float:
	var k := twitch_amount()
	if k <= 0.0:
		return 0.0
	return twitch_wave() * minf(twitch_deg * k, twitch_ceiling())


## Where the whole eye, and every cord on it, has rocked to. Degrees.
func rock_now() -> float:
	return rock_slow() + twitch_now()


## And how far it has slid in the socket, so loose reads as loose.
func eye_centre() -> Vector2:
	var k: float = looseness() * rock_slide_mm
	var at := Vector2(sin(_t * TAU * rock_hz * 1.13), cos(_t * TAU * rock_hz)) * k
	# The judder is drawn much bigger than it is allowed to drag the quiet spots: what a waking Hive
	# looks like should be alarming, what it does to the job should stay fair.
	var tk := twitch_amount()
	if tk > 0.0:
		at += Vector2(twitch_wave(), sin(_t * TAU * twitch_hz * 1.63 + 0.7)) * rock_slide_mm * 1.9 * tk
	return at


## Where a cord is drawn, degrees, rocking included.
func tether_angle(i: int) -> float:
	return tether_deg[i] + rock_now()


## And where its quiet spot is. Never drawn: this is the thing you are feeling for.
func sweet_angle(i: int) -> float:
	return tether_deg[i] + float(sweet_off[i]) + rock_now()


## Half the width of a quiet spot. The tough one's is half as wide, and every one of them narrows
## as the shifts get harder.
func sweet_half(i: int) -> float:
	var w: float = sweet_deg * (tough_sweet_frac if i == tough else 1.0)
	return maxf(0.4, w / sqrt(diff))


## Which tether the spoon is on, or -1 for bare rim. The nearest live one inside the spoon's reach.
func engaged() -> int:
	var best := -1
	var bd := 1e9
	for i in tether_n:
		if not live(i):
			continue
		var d: float = absf(_adiff(sweet_angle(i), spoon_a))
		if d < bd:
			bd = d
			best = i
	return best if bd <= sense_deg else -1


## How far off the quiet spot the spoon is, in quiet-spot widths. 0 dead on, 1 at the edge of what
## will pop, `feel_span` and up for the full shake.
func off_sweet() -> float:
	var i := engaged()
	if i < 0:
		return 0.0
	return absf(_adiff(sweet_angle(i), spoon_a)) / sweet_half(i)


## How hard the spoon is shaking, in millimetres along the rim. THE WHOLE GAME IS THIS NUMBER: it
## is flat out on a tether's flanks and it falls away to nothing over the quiet spot.
func wobble_now() -> float:
	if engaged() < 0 or slip_left > 0.0:
		return 0.0
	var clean: float = wobble_mm * clampf(off_sweet() / feel_span, 0.0, 1.0)
	# THE CARRY-FORWARD. A twitching eye buzzes the spoon everywhere alike, sweet spot included, so
	# there is no longer a still place to feel for -- only a slightly less awful one.
	var noise: float = wobble_mm * twitch_noise * twitch_amount() * absf(twitch_wave())
	return clean + noise


# ---------------------------------------------------------------------------- playing

func keys() -> Array:
	if play_state == Play.DONE:
		return []
	if levering:
		return [["Hold LMB", "keep the pressure"], ["Mouse", "find the still spot"]]
	return [["Mouse", "ride the rim"], ["Hold LMB", "lever"]]


func hint() -> String:
	var base := super.hint()
	if base != "":
		return base
	if play_state == Play.DONE:
		return "It is out."
	if slip_left > 0.0:
		return "The spoon slipped out. Getting it back in."
	if twitch_amount() > 0.35:
		return "It is twitching. Sedate it or work faster."
	if levering:
		return "Hold it. It is still where the tether gives."
	if engaged() >= 0:
		return "On a tether. Move until the spoon stops shaking."
	return "Ride the rim until the spoon starts to shake."


## The spoon goes wherever the mouse points, round the rim. The lever is taken on the PRESS and
## given up on the release, so a pop always costs a fresh press: no mashing one button through the
## whole eye.
func play(p: Vector2, buttons: int, edges: int, _delta: float) -> void:
	if p.length() > 3.0:
		spoon_a = rad_to_deg(atan2(p.y, p.x))
	var hold := (buttons & BUTTON_PRIMARY) != 0
	if (edges & BUTTON_PRIMARY) != 0 and slip_left <= 0.0 and not levering:
		levering = true
		tension = 0.0
		shudder = 0.0
		_lever_t = 0.0
		audio(seat_cue, seat_volume, 0.1)
	if not hold:
		levering = false


func advance(delta: float) -> void:
	if slip_left > 0.0:
		slip_left = maxf(0.0, slip_left - delta)
		return
	if not levering:
		_lever_t = 0.0
		tension = move_toward(tension, 0.0, delta / maxf(0.05, lever_time) * 1.6)
		shudder = move_toward(shudder, 0.0, delta * 2.5)
		_update_progress()
		return
	_lever_t += delta
	var i := engaged()
	if _lever_t >= lever_limit:
		_slip()
		_update_progress()
		return
	if i >= 0 and off_sweet() <= 1.0:
		# Under the tether. It comes up taut, and then it lets go.
		tension += delta / maxf(0.05, lever_time)
		shudder = move_toward(shudder, 0.0, delta * 3.0)
		if tension >= 1.0:
			_pop(i)
			_update_progress()
			return
	else:
		# Against it, or against bare socket. Either way the spoon is working its way out.
		shudder += delta
		tension = move_toward(tension, 0.0, delta / maxf(0.05, lever_time) * 0.6)
		if shudder >= slip_after:
			_slip()
			_update_progress()
			return
	_update_progress()


func _pop(i: int) -> void:
	popped[i] = int(popped[i]) + 1
	tension = 0.0
	shudder = 0.0
	levering = false
	pop_flash = 0.45
	# The tough one shifts under the spoon when its first head goes: the spot is somewhere else now.
	if i == tough and int(popped[i]) == 1:
		var spread: float = minf(sweet_spread_deg, sense_deg - sweet_deg - 1.0)
		sweet_off[i] = clampf(float(sweet_off[i]) + _rng.randf_range(-tough_reroll_deg, tough_reroll_deg),
			-spread, spread)
	if tethers_left() <= 0:
		_eye_out()


func _slip() -> void:
	slips += 1
	levering = false
	tension = 0.0
	shudder = 0.0
	slip_left = slip_time
	slip_flash = 0.5
	shake(0.55)
	# Guarded and already a no-op on a graft: there, the patient just yelps (react()).
	cost(slip_botch, "The spoon squeezed the eye")


func _eye_out() -> void:
	quality = pry_quality()
	arcade_finish({"eye_out": true, "pry_quality": quality})


func pry_quality() -> float:
	return snappedf(clampf(1.0 - 0.1 * float(slips), 0.05, 1.0), 0.01)


func _update_progress() -> void:
	progress = clampf((float(pops_done()) + tension * 0.85) / maxf(1.0, float(total_pops())), 0.0, 1.0)


func animate(delta: float) -> void:
	_t += delta
	# Nobody comes back to a half-finished lever. Stepping away, or a command card, drops it, so a
	# hand-over never resumes on somebody else's shudder and slips the moment the countdown clears.
	if not armed() and levering:
		levering = false
		tension = 0.0
		shudder = 0.0
		_lever_t = 0.0
	_wob_phase += delta * wobble_hz
	pop_flash = maxf(0.0, pop_flash - delta)
	slip_flash = maxf(0.0, slip_flash - delta)
	# Ease the drawn shake so it reads as the spoon settling, not as a value snapping.
	_shown_wob = move_toward(_shown_wob, wobble_now(), delta * wobble_mm * 9.0)
	# The cord creaking as it comes up: the sound of being in the right place.
	if tension > 0.5 and not _taut:
		_taut = true
		audio(taut_cue, -15.0, 0.1)
	elif tension < 0.2:
		_taut = false


## A jerk knocks the spoon out of whatever it was doing. It costs nothing: the lever is simply lost.
func on_jolt(_offset: Vector2, strength: float, _duration: float) -> void:
	levering = false
	tension = 0.0
	shudder = 0.0
	shake(clampf(0.35 + strength * 0.5, 0.0, 1.0))
	slip_flash = maxf(slip_flash, 0.2)


# ---------------------------------------------------------------------------- the body

func react() -> void:
	var b = body()
	var pops := pops_done()
	if pops > _seen_pops:
		_seen_pops = pops
		audio(pop_cue, -3.0, 0.12)
		if b != null and b.has_method("stir"):
			b.stir(0.35)
	if slips > _seen_slips:
		_seen_slips = slips
		audio(slip_cue, -5.0, 0.1)
		if no_fail:
			# The graft is on a friend who is awake enough to complain about it.
			audio(yelp_cue, -6.0, 0.15)
		if b != null and b.has_method("stir"):
			b.stir(0.7 if no_fail else 0.5)


# ---------------------------------------------------------------------------- the socket

func paint_game(c: CanvasItem) -> void:
	if panel == null:
		return
	var st := style()
	_paint_rim(c, st)
	_paint_eye(c, st)
	_paint_tethers(c, st)
	_paint_spoon(c, st)
	_paint_tension(c, st)
	_paint_scoreboard(c, st)
	if slip_flash > 0.0:
		c.draw_rect(Rect2(Vector2.ZERO, panel.tex_size()), Color(st.danger, slip_flash * 0.18))
	if pop_flash > 0.0:
		c.draw_rect(Rect2(Vector2.ZERO, panel.tex_size()), Color(st.good, pop_flash * 0.10))


## The bone rim the spoon runs on, and the open socket inside it: a ring with hatch ticks outward,
## so it reads as the edge of a hole in a skull and not as another circle drawn round the eye.
func _paint_rim(c: CanvasItem, st: StyleScript) -> void:
	var mid := px(Vector2.ZERO)
	var wound: PackedVector2Array = PackedVector2Array()
	for i in 64:
		wound.append(px(_dir(360.0 * float(i) / 64.0) * rim_mm))
	c.draw_colored_polygon(wound, Color(st.blood_dark, 0.85))
	c.draw_arc(mid, px_len(rim_mm), 0.0, TAU, 72, Color(st.bone, 0.85), st.outline)
	st.glow_circle(c, mid, px_len(rim_mm), st.bone, st.thin)
	for i in 48:
		var a: float = 360.0 * float(i) / 48.0
		c.draw_line(px(_dir(a) * rim_mm), px(_dir(a) * (rim_mm + 2.4)), Color(st.bone, 0.45), st.hair)


## The eye itself, rocking in the socket. Its pupil looks wherever it has rocked to, so how loose it
## is sitting is visible without a number anywhere.
func _paint_eye(c: CanvasItem, st: StyleScript) -> void:
	var ec := eye_centre()
	var at := px(ec)
	var r := px_len(eye_mm)
	c.draw_circle(at, r, st.bg_inner)
	c.draw_circle(at, r, Color(st.steel, 0.17))
	st.glow_circle(c, at, r, st.line, st.thin)
	c.draw_arc(at, r, 0.0, TAU, 60, st.line, st.outline)
	# Iris and pupil, turned the way the eye has rolled.
	var look := ec.normalized() * eye_mm * 0.22 if ec.length() > 0.01 else Vector2.ZERO
	var ir := px(ec + look)
	c.draw_circle(ir, px_len(eye_mm * 0.52), Color(st.line_dim, 0.30))
	c.draw_arc(ir, px_len(eye_mm * 0.52), 0.0, TAU, 40, Color(st.line_dim, 0.95), st.thin)
	c.draw_circle(ir, px_len(eye_mm * 0.26), Color(st.bg, 0.98))
	c.draw_arc(ir, px_len(eye_mm * 0.26), 0.0, TAU, 28, Color(st.line, 0.85), st.thin)
	# Veins, so the eye is an eye and not a target.
	for k in 5:
		var a: float = 34.0 + 71.0 * float(k)
		var from: Vector2 = ec + _dir(a) * eye_mm * 0.98
		var to: Vector2 = ec + _dir(a + 11.0) * eye_mm * 0.55
		c.draw_line(px(from), px(to), Color(st.danger, 0.45), st.hair)


## The cords. A live one is taut, with rungs along it; the tough one has three strands. A popped one
## is a severed stub at each end with a gap between them -- the shape says popped, not the colour.
func _paint_tethers(c: CanvasItem, st: StyleScript) -> void:
	var ec := eye_centre()
	for i in tether_n:
		var a: float = tether_angle(i)
		var d: Vector2 = _dir(a)
		var perp := Vector2(-d.y, d.x)
		var inner: Vector2 = ec + d * eye_mm
		var outer: Vector2 = d * rim_mm
		var strands: int = 3 if i == tough else 1
		if not live(i):
			# Cut: a stub on the eye, a stub on the rim, and daylight in between. Both ends curl back
			# the way a cut muscle does, so a popped tether reads as popped and not merely as a dim one.
			for s in strands:
				var off: Vector2 = perp * (float(s) - float(strands - 1) * 0.5) * 1.5
				var a1: Vector2 = inner.lerp(outer, 0.22) + off
				var b1: Vector2 = inner.lerp(outer, 0.78) + off
				c.draw_line(px(inner + off), px(a1), Color(st.line_dim, 0.5), st.thin)
				c.draw_line(px(a1), px(a1 - d * 1.2 + perp * 2.6), Color(st.line_dim, 0.5), st.thin)
				c.draw_line(px(b1), px(outer + off), Color(st.line_dim, 0.5), st.thin)
				c.draw_line(px(b1), px(b1 + d * 1.2 - perp * 2.6), Color(st.line_dim, 0.5), st.thin)
			continue
		var on: bool = engaged() == i
		var col: Color = st.line if on else Color(st.line, 0.62)
		var wide: float = st.outline if on else st.thin
		if on:
			st.glow_line(c, px(inner), px(outer), st.line, st.thin)
		for s in strands:
			var off2: Vector2 = perp * (float(s) - float(strands - 1) * 0.5) * 1.8
			c.draw_line(px(inner + off2), px(outer + off2), col, wide)
		# Rungs across it: a cord under tension, and a second read on which ones are still on.
		var half: float = 2.0 + 1.8 * float(strands - 1)
		for k in 5:
			var t: float = 0.18 + 0.16 * float(k)
			var mid: Vector2 = inner.lerp(outer, t)
			c.draw_line(px(mid - perp * half), px(mid + perp * half), Color(col, 0.7), st.hair)


## The spoon on the rim: a handle out past the rim and a bowl tucked under it. It shakes along the
## rim by whatever `wobble_now()` says, dips in as the tether comes taut, and its bowl outline
## breaks into a jagged edge as it starts to work its way out.
func _paint_spoon(c: CanvasItem, st: StyleScript) -> void:
	if slip_left > 0.0:
		# Out of the socket and coming back: a ring closing on the rim where it will land.
		var k: float = 1.0 - slip_left / maxf(0.05, slip_time)
		var d0 := _dir(spoon_a)
		c.draw_arc(px(d0 * rim_mm), px_len(2.0 + 4.5 * (1.0 - k)), 0.0, TAU, 20,
			Color(st.danger, 0.6), st.thin)
		# The spoon itself, hauled up out of the socket and coming back down.
		var up: float = rim_mm + 7.0 * (1.0 - k)
		c.draw_line(px(d0 * up), px(d0 * (up + 8.0)), Color(st.steel, 0.5), st.thin)
		return
	var shakes: float = _shown_wob * sin(_wob_phase * TAU)
	var a: float = spoon_a + rad_to_deg(shakes / maxf(1.0, rim_mm))
	var judder: float = clampf(shudder / maxf(0.05, slip_after), 0.0, 1.0)
	a += rad_to_deg(judder * 2.2 * sin(_wob_phase * TAU * 2.6) / maxf(1.0, rim_mm))
	var d := _dir(a)
	var perp := Vector2(-d.y, d.x)
	var dip: float = tension * 3.2 + judder * 1.2
	var seat: float = rim_mm - 1.5 - dip
	var col: Color = st.danger if judder > 0.25 else st.steel
	# Handle.
	st.glow_line(c, px(d * (rim_mm + 0.5)), px(d * (rim_mm + 8.0)), col, st.thin)
	c.draw_line(px(d * (rim_mm + 0.5)), px(d * (rim_mm + 8.0)), col, st.outline)
	for k in 3:
		var at: Vector2 = d * (rim_mm + 3.4 + 1.7 * float(k))
		c.draw_line(px(at - perp * 1.3), px(at + perp * 1.3), Color(col, 0.7), st.hair)
	# Bowl: a shallow scoop facing the eye.
	var bowl: PackedVector2Array = PackedVector2Array()
	for k in 13:
		var u: float = float(k) / 12.0
		var s: float = lerpf(-1.0, 1.0, u)
		bowl.append(px(d * (seat - 3.4 * (1.0 - s * s)) + perp * s * 4.2))
	c.draw_polyline(bowl, col, st.outline)
	if judder > 0.25:
		# Cracked: the bowl's lip breaks into teeth as the spoon starts to slip. Shape, not colour.
		for k in range(0, bowl.size() - 1, 2):
			var mid: Vector2 = (bowl[k] + bowl[k + 1]) * 0.5
			c.draw_line(bowl[k], mid + (mid - px(Vector2.ZERO)).normalized() * 5.0 * judder, col, st.hair)
	else:
		var fill: PackedVector2Array = bowl.duplicate()
		fill.append(px(d * (seat + 1.2) + perp * 4.2))
		fill.append(px(d * (seat + 1.2) - perp * 4.2))
		c.draw_colored_polygon(fill, Color(col, 0.28))


## The torque bar down the left edge: how taut the tether is, and how close the spoon is to coming
## out. Two separate shapes, never one bar in two colours -- a solid column that fills upward, and a
## row of warning wedges that fills downward.
func _paint_tension(c: CanvasItem, st: StyleScript) -> void:
	var font := ThemeDB.fallback_font
	var x := -52.0
	var top := -18.0
	var bot := 18.0
	var w := 4.2
	var frame_pts: PackedVector2Array = PackedVector2Array([
		px(Vector2(x - w, top)), px(Vector2(x + w, top)), px(Vector2(x + w, bot)), px(Vector2(x - w, bot)),
		px(Vector2(x - w, top))])
	c.draw_polyline(frame_pts, Color(st.line_dim, 0.8), st.thin)
	for k in 5:
		var y: float = lerpf(bot, top, float(k) / 4.0)
		c.draw_line(px(Vector2(x - w, y)), px(Vector2(x - w + 2.0, y)), Color(st.line_dim, 0.7), st.hair)
	if tension > 0.001:
		var ty: float = lerpf(bot, top, clampf(tension, 0.0, 1.0))
		var fill: PackedVector2Array = PackedVector2Array([
			px(Vector2(x - w + 0.8, ty)), px(Vector2(x + w - 0.8, ty)),
			px(Vector2(x + w - 0.8, bot - 0.8)), px(Vector2(x - w + 0.8, bot - 0.8))])
		c.draw_colored_polygon(fill, Color(st.good, 0.75))
		st.glow_line(c, px(Vector2(x, ty)), px(Vector2(x, bot)), st.good, st.thin)
	# The slip warning: wedges stacking down from the top of the bar.
	var judder: float = clampf(shudder / maxf(0.05, slip_after), 0.0, 1.0)
	if judder > 0.0:
		var n: int = int(ceil(judder * 5.0))
		for k in n:
			var yy: float = top + 1.6 + 3.0 * float(k)
			var tri: PackedVector2Array = PackedVector2Array([
				px(Vector2(x + w + 1.6, yy)), px(Vector2(x + w + 6.2, yy - 1.5)),
				px(Vector2(x + w + 6.2, yy + 1.5))])
			c.draw_colored_polygon(tri, Color(st.danger, 0.85))
	c.draw_string(font, px(Vector2(x - 6.0, bot + 5.5)), "TENSION", HORIZONTAL_ALIGNMENT_LEFT, -1.0,
		17, Color(st.line_dim, 0.9))


## What is left, what it has cost, and whether the thing is twitching -- one line under the socket,
## numbers and words rather than another bar.
func _paint_scoreboard(c: CanvasItem, st: StyleScript) -> void:
	var font := ThemeDB.fallback_font
	var left := tethers_left()
	var extra: int = maxi(0, pops_needed(tough) - int(popped[tough]) - 1)
	var txt := "%d TETHER%s LEFT" % [left, "" if left == 1 else "S"]
	if extra > 0:
		txt += " (+1 TOUGH)"
	if slips > 0:
		txt += "    SLIPPED %d" % slips
	if twitch_amount() > 0.05:
		txt += "    TWITCHING"
	var w: float = font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x
	var col: Color = st.danger if slips > 0 or twitch_amount() > 0.05 else Color(st.line_dim, 0.95)
	c.draw_string(font, px(Vector2(0.0, minf(rim_mm + 8.5, 36.0))) + Vector2(-w * 0.5, 0), txt,
		HORIZONTAL_ALIGNMENT_LEFT, -1.0, 22, col)


# ---------------------------------------------------------------------------- helpers

func _dir(deg: float) -> Vector2:
	var r := deg_to_rad(deg)
	return Vector2(cos(r), sin(r))


## Shortest way round from `from` to `to`, in degrees, -180..180.
func _adiff(from: float, to: float) -> float:
	return rad_to_deg(angle_difference(deg_to_rad(from), deg_to_rad(to)))


func _wrap180(deg: float) -> float:
	return fposmod(deg + 180.0, 360.0) - 180.0


# ---------------------------------------------------------------------------- net

## Everything a spectator needs to watch someone else fumble this. The creeping values -- the
## tension, the shudder, the slip timer, the spoon's angle and the clock the rocking runs on -- go
## out RAW: snap a value that moves less than its own quantum in a frame and it never moves at all,
## because the lab and the bot round-trip this dictionary every single frame.
func net_pack() -> Dictionary:
	return {
		"sa": spoon_a, "lv": levering, "te": tension, "sh": shudder, "sl": slip_left,
		"sp": slips, "pk": popped.duplicate(), "sw": sweet_off.duplicate(), "tt": _t,
		"pf": pop_flash, "sf": slip_flash,
	}


func net_apply(s: Dictionary) -> void:
	spoon_a = float(s.get("sa", spoon_a))
	levering = bool(s.get("lv", levering))
	tension = float(s.get("te", tension))
	shudder = float(s.get("sh", shudder))
	slip_left = float(s.get("sl", slip_left))
	slips = int(s.get("sp", slips))
	var pk = s.get("pk")
	if pk is Array and (pk as Array).size() == tether_n:
		popped = (pk as Array).duplicate()
	var sw = s.get("sw")
	if sw is Array and (sw as Array).size() == tether_n:
		sweet_off = (sw as Array).duplicate()
	_t = float(s.get("tt", _t))
	pop_flash = float(s.get("pf", pop_flash))
	slip_flash = float(s.get("sf", slip_flash))
	_update_progress()


# ---------------------------------------------------------------------------- bot

## The bot works the tethers in the order the seed laid them down, and for each attempt it decides
## where it THINKS the quiet spot is -- spot on with a good hand, well out with a bad one. The error
## is a golden-ratio sequence, not a draw, so the same run gives the same hand every time.
## A twitching eye beats it the same way it beats a player: the spot moves faster than it can chase,
## and after `bot_patience` it commits to a guess and eats the slip.
func bot_input(t: float, skill: float) -> Dictionary:
	var dt: float = clampf(t - _bt, 0.0, 0.1)
	_bt = t
	skill = clampf(skill, 0.0, 1.0)
	if not armed() or play_state == Play.DONE:
		_b_held = false
		return {"cursor": _out(_b_aim), "buttons": 0}
	var i := _next_target()
	if i < 0:
		_b_held = false
		return {"cursor": _out(_b_aim), "buttons": 0}
	# Let go for a beat after every pop: the lever is taken on the press, so it has to press again.
	var pops := pops_done()
	if pops != _b_pops:
		_b_pops = pops
		_b_release = 0.12
		_b_feel = 0.0
		_b_chase = 0.0
	# The lever is taken on the PRESS, so anything that cancels it -- a jolt, a pop -- leaves the bot
	# holding a dead button. Notice, let go, and press again, the way a hand would.
	if _b_held and not levering and slip_left <= 0.0:
		_b_release = maxf(_b_release, 0.1)
	_b_release = maxf(0.0, _b_release - dt)
	# One guess per attempt -- a fresh one after every pop and after every slip.
	var key := pops * 1000 + slips
	if key != _b_err_for:
		_b_err_for = key
		_b_seq += 1
		var u: float = fposmod(float(_b_seq) * 0.6180339887498949, 1.0)
		_b_err = (u - 0.5) * 2.0 * lerpf(bot_err_deg, 0.8, skill)
		# It cannot feel the notch through a twitch any better than a player can.
		_b_err *= 1.0 + bot_twitch_err * twitch_amount()
		_b_feel = 0.0
		_b_chase = 0.0
	var want: float = sweet_angle(i) + _b_err
	var speed: float = lerpf(bot_slow_speed, bot_fast_speed, skill) * dt
	_b_aim = _wrap180(_b_aim + clampf(_adiff(_b_aim, want), -speed, speed))
	_b_chase += dt
	# Feel around for a moment before committing, the way a hand does.
	if absf(_adiff(_b_aim, want)) < 2.0:
		_b_feel += dt
	var ready: bool = _b_feel >= lerpf(bot_feel_slow, bot_feel_fast, skill) or _b_chase >= bot_patience
	var hold: bool = ready and slip_left <= 0.0 and _b_release <= 0.0
	_b_held = hold
	return {"cursor": _out(_b_aim), "buttons": BUTTON_PRIMARY if hold else 0}


func _next_target() -> int:
	for i in tether_n:
		if live(i):
			return i
	return -1


func _out(deg: float) -> Vector2:
	var mm := _dir(deg) * rim_mm
	return panel.metres_of(mm) if panel != null else mm


# ---------------------------------------------------------------------------- self-test

## Headless check: `tools/minigame_lab.tscn -- --selftest=eye:scoop:arcade`.
## Targets: skill 1.0 finishes in 8-20 s losing 0-2 vitals; skill 0.0 under 40 s losing 15-25. The
## graft is `no_fail`, so there are no vitals to lose there and only the clock is asserted.
static func self_test() -> Array:
	var script: GDScript = load("res://scripts/surgery/arcade/pry_arcade.gd")
	var out := []
	var ok := true
	var sloppy: Array = []
	for case: Dictionary in [
			{"tag": "hive", "sed": 1.0}, {"tag": "hive", "sed": 0.2}, {"tag": "graft", "sed": 1.0}]:
		for seed_tag: String in ["a", "b"]:
			for skill: float in [1.0, 0.5, 0.0]:
				var r := _run(script, String(case.tag), float(case.sed), seed_tag, skill)
				print("[pry-arcade self-test] %-5s seed=%s skill=%.1f sed=%.1f  %s  tethers=%d pops=%d slipped=%2d  time=%5.1fs  botches=%2d vitals=%5.1f  q=%.2f  %s" % [
					case.tag, seed_tag, skill, case.sed, "DONE" if r.done else "UNFINISHED",
					r.tethers, r.pops, r.slips, r.time, r.n, r.vitals, r.q, str(r.reasons)])
				out.append(r)
				if not r.done:
					print("[pry-arcade self-test] MISS: it has to come out")
					ok = false
				if String(case.tag) == "graft":
					# no_fail: nothing to charge, so only the clock is judged.
					if r.vitals > 0.0:
						print("[pry-arcade self-test] MISS: a graft must never cost the patient anything")
						ok = false
					if skill == 1.0 and (r.time < 8.0 or r.time > 20.0):
						print("[pry-arcade self-test] MISS: skill 1.0 wants 8-20 s")
						ok = false
					if skill == 0.0 and r.time > 40.0:
						print("[pry-arcade self-test] MISS: skill 0.0 wants to finish under 40 s")
						ok = false
				elif float(case.sed) > 0.9:
					if skill == 1.0 and (r.time < 8.0 or r.time > 20.0 or r.vitals > 2.0):
						print("[pry-arcade self-test] MISS: skill 1.0 wants 8-20 s and 0-2 vitals")
						ok = false
					if skill == 0.0:
						sloppy.append(r.vitals)
						if r.time > 40.0:
							print("[pry-arcade self-test] MISS: skill 0.0 wants to finish under 40 s")
							ok = false
	# The sloppy band, on the MEAN: the seed picks four, five or six tethers, and a six-tether eye
	# costs a sloppy hand a couple of slips more than a four-tether one all on its own.
	var mean := 0.0
	for v: float in sloppy:
		mean += v
	mean /= maxf(1.0, float(sloppy.size()))
	print("[pry-arcade self-test] skill 0.0 mean vitals %.1f across %d eyes (want 15-25)" % [mean, sloppy.size()])
	if mean < 15.0 or mean > 25.0:
		print("[pry-arcade self-test] MISS: skill 0.0 wants 15-25 vitals on average")
		ok = false
	# The carry-forward: an eye that has been left to wake up is measurably worse to work on.
	var under := 0.0
	var awake := 0.0
	for seed_tag2: String in ["a", "b"]:
		var calm := _run(script, "hive", 1.0, seed_tag2, 0.5)
		var jumpy := _run(script, "hive", 0.2, seed_tag2, 0.5)
		under += float(calm.time)
		awake += float(jumpy.time)
		print("[pry-arcade self-test] seed=%s skill=0.5  sedated %.1fs / %d slips   awake %.1fs / %d slips" % [
			seed_tag2, calm.time, calm.slips, jumpy.time, jumpy.slips])
		out.append({"case": "carry", "seed": seed_tag2, "sedated": calm.time, "awake": jumpy.time,
			"sedated_slips": calm.slips, "awake_slips": jumpy.slips})
	if awake <= under * 1.1:
		print("[pry-arcade self-test] MISS: a twitching eye must be measurably harder than a sedated one")
		ok = false
	print("[pry-arcade self-test] %s" % ("PASS" if ok else "FAIL"))
	return out


static func _run(script: GDScript, tag: String, sed: float, seed_tag: String, skill: float) -> Dictionary:
	var graft := tag == "graft"
	var g = script.new()
	var tally := {"n": 0, "v": 0.0, "done": false, "q": 0.0, "reasons": {}}
	g.botched.connect(func(a, r): tally.n += 1; tally.v += a; tally.reasons[r] = int(tally.reasons.get(r, 0)) + 1)
	g.finished.connect(func(r): tally.done = true; tally.q = float(r.get("pry_quality", 0.0)))
	var ail := "eye_graft" if graft else "eye_extraction"
	var pid := "player" if graft else "hive"
	var c := {"patient_id": pid, "patient": Procedures.patient("hive"), "ailment_id": ail,
		"step": Procedures.step(ail, 1), "variant": "scoop", "shift": 1,
		"difficulty": Procedures.difficulty(1), "flags": {"sedation": sed},
		"seed": hash("pry" + tag + seed_tag), "body": null, "operator": true, "operating": true}
	if graft:
		c["no_fail"] = true
		c["eye_kind"] = "eye_surgeon"
		c["eye_radius"] = Grafts.EYE_RADIUS
	g.setup(c)
	var t: float = run_bot(g, skill, sed, hash(seed_tag) + int(skill * 100))
	var r := {"case": tag, "seed": seed_tag, "skill": skill, "sed": sed, "done": tally.done,
		"time": t, "vitals": tally.v, "n": tally.n, "q": tally.q, "slips": g.slips,
		"tethers": g.tether_n, "pops": g.pops_done(), "reasons": tally.reasons}
	g.free()
	return r
