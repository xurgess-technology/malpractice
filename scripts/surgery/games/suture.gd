extends "res://scripts/surgery/minigame.gd"
## PANEL TESTBED (docs/PANEL_STYLE.md). Step "close" of the `laceration` procedure: stitch a deep
## cut shut. The first step played on a SurgeryPanel instead of on the work plane.
##
## THE PANEL IS THE INPUT SURFACE, THE BODY IS THE CONSEQUENCE SURFACE. Everything you aim at is on
## the diagram floating over the patient; everything that happens because of it -- the flinch, the
## blood on the gown, the monitor, the scar he walks out with -- is on the real body.
##
## What you do
##   A gash runs across the panel, gaping wider in some stretches than others. Faint rings sit a
##   bite's width back from each edge. Press left mouse where the needle goes in, drag across the
##   gash, let go where it comes out. The thread cinches and that section closes.
##     GOOD    both ends on their rings and square across: the section shuts.
##     SLOPPY  near enough: it holds, but it is visibly crooked, only pulls to about 60%, and that
##             stretch keeps seeping.
##     TEAR    into the gap, or too close to the edge: the thread rips through. Costs vitals.
##     MISS    did not cross, or nowhere near: nothing happens.
##   Meanwhile the wound seeps, and how fast depends on how much gape is still open: a wide stretch
##   left open costs far more than a narrow one. Let the pool fill and it gushes.
##
## Result {"closed": true, "stitch_marks": "ggsgg"} -- the marks in order along the wound, which the
## patient body draws as the stitches he walks out with.
##
## All geometry and tuning is in DIAGRAM MILLIMETRES; the panel converts to pixels. Everything
## handle_cursor receives is panel-local metres, converted straight to mm on the way in.

const PanelScript := preload("res://scripts/surgery/panel/surgery_panel.gd")
const StyleScript := preload("res://scripts/surgery/panel/panel_style.gd")

enum Stage { STITCH, TIE, DONE }
enum Grade { MISS, TEAR, SLOPPY, GOOD }

# -- the wound ---------------------------------------------------------------------------------
@export_range(20.0, 110.0, 1.0) var wound_len := 84.0          ## mm, end to end
@export_range(0.0, 20.0, 0.5) var curve_amp := 4.5             ## mm, how far the centreline bends
@export_range(1, 3) var curve_bends := 2
@export_range(3.0, 20.0, 0.5) var gape_max := 11.0             ## mm at the widest point
@export_range(0.5, 8.0, 0.1) var gape_min := 3.0               ## mm across the narrow stretches
@export_range(1, 3) var hot_stretches := 2                     ## how many wide stretches (1..this)
@export_range(0.0, 1.0, 0.01) var profile_smooth := 0.8        ## how much the gape profile is blurred
@export_range(2.0, 14.0, 0.5) var bite := 7.0                  ## mm from the wound edge to its ring

# -- grading -----------------------------------------------------------------------------------
@export_range(0.5, 8.0, 0.1) var good_radius := 3.0            ## mm at difficulty 1
@export_range(1.0, 14.0, 0.1) var ok_radius := 6.5             ## mm
@export_range(0.5, 6.0, 0.1) var min_bite := 2.5               ## mm of skin a stitch must take
@export_range(2.0, 60.0, 1.0) var good_skew_deg := 15.0
@export_range(2.0, 80.0, 1.0) var ok_skew_deg := 35.0
@export_range(0.0, 1.0, 0.01) var sloppy_closure := 0.6        ## how far a sloppy stitch pulls it shut

# -- feel --------------------------------------------------------------------------------------
@export_range(0.0, 0.5, 0.005) var tool_lag := 0.08            ## seconds the needle driver trails the cursor
@export_range(0.05, 1.0, 0.01) var pull_time := 0.25           ## the cinch after a stitch lands
@export_range(0.05, 1.5, 0.01) var tie_time := 0.4             ## the knot at the end
@export_range(0.0, 0.5, 0.01) var min_hold := 0.12             ## shorter than this is a misclick
@export_range(0.0, 2.0, 0.05) var tear_cooldown := 0.5
@export_range(0.05, 2.0, 0.05) var tear_flash_time := 0.45   ## how long the panel flashes red

# -- pressure ----------------------------------------------------------------------------------
@export_range(0.0, 0.5, 0.005) var seep_rate := 0.095          ## pool per second at difficulty 1, wound fully open
@export_range(0.1, 1.0, 0.01) var gush_at := 1.0
@export_range(0.0, 1.0, 0.01) var gush_reset := 0.6
@export_range(0.0, 1.0, 0.02) var pulse_strength := 0.5        ## how hard a wide stretch throbs
@export_range(0.2, 3.0, 0.05) var heart_hz := 1.15

# -- costs -------------------------------------------------------------------------------------
@export_range(0.0, 10.0, 0.1) var tear_botch := 2.0
@export_range(0.0, 10.0, 0.1) var gush_botch := 3.0

# -- the panel ---------------------------------------------------------------------------------
## How much of the view's height the panel fills. The rest is the real patient, table and room.
@export_range(0.3, 1.0, 0.01) var view_fill := 0.78
## How far the operator's camera is pulled back from straight over the site, in degrees.
@export_range(0.0, 60.0, 1.0) var view_tilt_deg := 21.0
@export_range(20.0, 90.0, 1.0) var view_fov := 50.0

# ---- state (all of it replicated) ----
var stage: int = Stage.STITCH
var pool := 0.0                    ## 0..1, blood on the panel
var marks: Array = []              ## per stitch: "" not placed, "g", "s"
var entries: Array = []            ## per stitch: Vector2 mm where the needle went in
var exits: Array = []              ## per stitch: Vector2 mm where it came out
var cursor := Vector2.ZERO         ## mm
var pressed := false
var drag_from := Vector2.ZERO      ## mm, where the current press started
var dragging := false
var tears := 0
var last_tear := Vector2.ZERO    ## mm, where the last thread ripped through
var gushes := 0
var stitches_done := 0
var _result: Dictionary = {}

# ---- derived from the seed (never replicated: regenerated from it) ----
var profile_seed := 0
var stitch_count := 5
var diff := 1.0
var pts: PackedVector2Array = PackedVector2Array()     ## centreline samples, mm
var nrm: PackedVector2Array = PackedVector2Array()     ## unit normal at each sample
var gap: PackedFloat32Array = PackedFloat32Array()     ## gape at each sample, mm
var stitch_at: PackedInt32Array = PackedInt32Array()   ## sample index of each stitch
var dot_a: PackedVector2Array = PackedVector2Array()   ## ring on the -normal side, per stitch
var dot_b: PackedVector2Array = PackedVector2Array()   ## ring on the +normal side, per stitch
var start_gape: PackedFloat32Array = PackedFloat32Array()  ## each section's gape before anything

const SAMPLES := 49

var _panel: PanelScript = null
var _t := 0.0
var _hold := 0.0
var _pull := 0.0                   ## seconds left of the cinch
var _pull_i := -1
var _tie := 0.0
var _finish_in := -1.0
var _cd := 0.0
var _flash := 0.0                  ## red tear flash on the panel
var _miss_hint := 0.0
var _tool := Vector2.ZERO          ## the needle driver, lagging the cursor
var _shown: PackedFloat32Array = PackedFloat32Array()  ## animated closure per section
var _prev_primary := false
var _seen_tears := 0
var _seen_gushes := 0
var _seen_stage := 0
var _seen_tie := 0
var _opened := false

# body
var _gush_fx: CPUParticles3D = null

# bot
var _bt := 0.0
var _b_target := -1
var _b_phase := 0                  ## 0 approach, 1 dragging, 2 cooling off
var _b_cd := 0.0
var _b_cursor := Vector2.ZERO
var _b_err_in := Vector2.ZERO
var _b_err_out := Vector2.ZERO
var _b_hold := 0.0
var _b_dwell := 0.0
var _b_seq := 0
## Test seam (self_test): null follows skill, true always takes the widest open section, false
## always works end to end.
var bot_order_widest = null
## Test seam (self_test): extra seconds of thinking between stitches, so the order comparison plays
## out at a person's pace instead of a bot's.
var bot_pause := 0.0


# ---------------------------------------------------------------------------- setup

func setup(context: Dictionary) -> void:
	super.setup(context)
	diff = maxf(0.5, float(ctx.get("difficulty", 1.0)))
	profile_seed = int(ctx.get("seed", 0))
	stitch_count = maxi(2, int(ceil(5.0 * sqrt(diff))))
	_build_wound()
	marks.resize(stitch_count)
	entries.resize(stitch_count)
	exits.resize(stitch_count)
	_shown.resize(stitch_count)
	for i in stitch_count:
		marks[i] = ""
		entries[i] = Vector2.ZERO
		exits[i] = Vector2.ZERO
		_shown[i] = 0.0
	cursor = Vector2(0.0, -view_mm().y * 0.3)
	_tool = cursor
	_b_cursor = cursor
	_panel = PanelScript.new()
	_panel.header = "%s / %s" % [String(Procedures.ailment(String(ctx.get("ailment_id", ""))).get("code", "LAC")),
		String(ctx.get("step", {}).get("id", "close")).to_upper()]
	_panel.painter = _paint
	add_child(_panel)
	_expose()
	_build_body_fx()


func _exit_tree() -> void:
	var body = ctx.get("body")
	if body != null and is_instance_valid(body) and body.has_method("cover_site"):
		body.cover_site()


## The gown opens over a real ~8 cm cut, and nothing else of ours ever sits on the patient.
func _expose() -> void:
	var body = ctx.get("body")
	if body == null or not is_instance_valid(body) or not body.has_method("expose_site"):
		return
	var half := wound_len * 0.0005 + 0.016
	body.expose_site(String(ctx.get("step", {}).get("site", "gunshot")), Vector2.ZERO, Vector2(half, half * 0.62))


func view_mm() -> Vector2:
	return _panel.view_mm if _panel != null else Vector2(120.0, 80.0)


# ---------------------------------------------------------------------------- the wound

## The wound is a seeded polyline with a gape PER POINT, not one almond shape: some stretches gape
## wide and bleed hard, others barely open. Closing the worst stretch first is the better play, and
## nothing in the game says so -- it is there to be read off the panel.
##
## The centreline and the gape profile are separate on purpose, so a later shape (a ragged tear, a
## curve that doubles back) only has to replace _centreline() and everything else still works.
func _build_wound() -> void:
	var rng := RandomNumberGenerator.new()
	_centreline(profile_seed)
	# Stitch positions first: the profile is re-rolled until every wide stretch has one on it.
	stitch_at.resize(stitch_count)
	for i in stitch_count:
		var t := (float(i) + 0.5) / float(stitch_count)
		stitch_at[i] = clampi(int(round(t * float(SAMPLES - 1))), 0, SAMPLES - 1)
	var best: PackedFloat32Array = PackedFloat32Array()
	for attempt in 40:
		rng.seed = profile_seed ^ (0x9e37 + attempt * 7919)
		var prof := _gape_profile(rng)
		if best.is_empty():
			best = prof
		if _profile_ok(prof):
			best = prof
			break
	gap = best
	start_gape.resize(stitch_count)
	dot_a.resize(stitch_count)
	dot_b.resize(stitch_count)
	for i in stitch_count:
		var s := stitch_at[i]
		start_gape[i] = gap[s]
		var off := gap[s] * 0.5 + bite
		dot_a[i] = pts[s] - nrm[s] * off
		dot_b[i] = pts[s] + nrm[s] * off


func _centreline(seed_v: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v ^ 0x1f35
	var bends := rng.randi_range(1, maxi(1, curve_bends))
	var f1 := 0.7 + 0.5 * float(bends)
	var f2 := f1 * 1.9
	var p1 := rng.randf() * TAU
	var p2 := rng.randf() * TAU
	var w2 := rng.randf_range(0.15, 0.4) if bends > 1 else 0.0
	pts.resize(SAMPLES)
	var raw: PackedFloat32Array = PackedFloat32Array()
	raw.resize(SAMPLES)
	var peak := 0.0001
	for i in SAMPLES:
		var t := float(i) / float(SAMPLES - 1)
		var y := sin(t * PI * f1 + p1) + w2 * sin(t * PI * f2 + p2)
		raw[i] = y
		peak = maxf(peak, absf(y))
	# Pinned at both ends so the cut reads as one clean line across the panel.
	var y0 := raw[0]
	var y1 := raw[SAMPLES - 1]
	for i in SAMPLES:
		var t := float(i) / float(SAMPLES - 1)
		var y: float = raw[i] - lerpf(y0, y1, t)
		pts[i] = Vector2(lerpf(-wound_len * 0.5, wound_len * 0.5, t), y / peak * curve_amp)
	nrm.resize(SAMPLES)
	for i in SAMPLES:
		var a: Vector2 = pts[maxi(0, i - 3)]
		var b: Vector2 = pts[mini(SAMPLES - 1, i + 3)]
		var tang := (b - a).normalized()
		nrm[i] = Vector2(-tang.y, tang.x)


## Seeded, smooth, one or two wide "hot" stretches and at least one narrow one, tapering to closed
## at both ends. Replaces "widest in the middle".
func _gape_profile(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var hots := rng.randi_range(1, maxi(1, hot_stretches))
	var centres: Array = []
	var widths: Array = []
	for k in hots:
		var c := rng.randf_range(0.18, 0.82)
		# Keep two hot stretches apart, or they merge into one fat middle.
		for other in centres:
			if absf(c - float(other)) < 0.26:
				c = clampf(float(other) + (0.3 if c >= float(other) else -0.3), 0.14, 0.86)
		centres.append(c)
		widths.append(rng.randf_range(0.085, 0.14))
	var floor_k: float = clampf(gape_min / maxf(0.5, gape_max), 0.05, 0.8)
	var out: PackedFloat32Array = PackedFloat32Array()
	out.resize(SAMPLES)
	var peak := 0.0001
	for i in SAMPLES:
		var t := float(i) / float(SAMPLES - 1)
		var v := floor_k
		for k in hots:
			var d: float = (t - float(centres[k])) / float(widths[k])
			v += (1.0 - floor_k) * exp(-d * d)
		# A little seeded wobble, so two hot stretches are never twins.
		v *= 1.0 + 0.08 * sin(t * 11.0 + float(rng.seed % 97))
		var taper := smoothstep(0.0, 0.11, t) * smoothstep(0.0, 0.11, 1.0 - t)
		out[i] = v * taper
		peak = maxf(peak, out[i])
	# Blur, then scale so the widest point is exactly gape_max.
	var passes := int(round(lerpf(0.0, 9.0, clampf(profile_smooth, 0.0, 1.0))))
	for p in passes:
		var prev: PackedFloat32Array = out.duplicate()
		for i in range(1, SAMPLES - 1):
			out[i] = (prev[i - 1] + prev[i] * 2.0 + prev[i + 1]) * 0.25
	peak = 0.0001
	for i in SAMPLES:
		peak = maxf(peak, out[i])
	for i in SAMPLES:
		out[i] = out[i] / peak * gape_max
	return out


## Reject a profile whose widest stretch no stitch can reach, or whose widest point sits within one
## stitch of an end (where the cut is nearly shut anyway and closing it proves nothing).
func _profile_ok(prof: PackedFloat32Array) -> bool:
	var widest := 0
	for i in SAMPLES:
		if prof[i] > prof[widest]:
			widest = i
	var wt := float(widest) / float(SAMPLES - 1)
	var span := 1.0 / float(stitch_count)
	if wt < span or wt > 1.0 - span:
		return false
	# Every stretch above the halfway mark between narrow and wide must contain a stitch position.
	var thresh: float = lerpf(gape_min, gape_max, 0.55)
	var i := 0
	while i < SAMPLES:
		if prof[i] < thresh:
			i += 1
			continue
		var from := i
		while i < SAMPLES and prof[i] >= thresh:
			i += 1
		var to := i - 1
		var covered := false
		for s in stitch_at:
			if s >= from and s <= to:
				covered = true
				break
		if not covered:
			return false
	return true


## How far a section has been pulled shut, 0..1.
func closure_of(i: int) -> float:
	var m := String(marks[i])
	if m == "g":
		return 1.0
	if m == "s":
		return sloppy_closure
	return 0.0


## The gape drawn at sample `i` right now: its own gape, less whatever the nearest stitches closed,
## with the heartbeat throbbing the wide stretches harder than the narrow ones.
func shown_gape(i: int, beat := 0.0) -> float:
	var t := float(i) / float(SAMPLES - 1) * float(stitch_count) - 0.5
	var a := clampi(int(floor(t)), 0, stitch_count - 1)
	var b := clampi(a + 1, 0, stitch_count - 1)
	var k: float = clampf(t - float(a), 0.0, 1.0)
	var closed: float = lerpf(_shown[a], _shown[b], k)
	var g: float = gap[i] * (1.0 - closed)
	return g * (1.0 + beat * pulse_strength * (gap[i] / maxf(0.1, gape_max)))


## The seep, normalised so a fully open wound costs exactly `seep_rate` per second: each section
## pays its own share of the gape still open, so a wide stretch left gaping costs far more.
func open_share() -> float:
	var open := 0.0
	var total := 0.0
	for i in stitch_count:
		total += start_gape[i]
		open += start_gape[i] * (1.0 - closure_of(i))
	return open / maxf(0.01, total)


# ---------------------------------------------------------------------------- the framework

func uses_panel() -> bool:
	return true


func plane_extent() -> Vector2:
	return _panel.half_size() if _panel != null else Vector2(0.21, 0.14)


func input_plane() -> Transform3D:
	return _panel.input_plane() if _panel != null else global_transform


func lamp_scale() -> float:
	return float(_panel.lamp_scale) if _panel != null else 1.0


## Framed so the panel fills `view_fill` of the view's height, leaving the real patient, the table
## and the room visible round its edges. The camera ends up square on to the panel.
func camera_pose() -> Dictionary:
	var lift: float = float(_panel.panel_lift) if _panel != null else 0.2
	var h: float = float(_panel.panel_size.y) if _panel != null else 0.28
	var d: float = (h / maxf(0.1, view_fill)) * 0.5 / tan(deg_to_rad(view_fov) * 0.5)
	var tilt := deg_to_rad(view_tilt_deg)
	return {"height": lift + d * cos(tilt), "back": d * sin(tilt), "fov": view_fov, "look": lift}


func keys() -> Array:
	if stage != Stage.STITCH:
		return []
	if dragging:
		return [["Drag across", "the gash"], ["Release", "the needle comes out"]]
	return [["Hold LMB", "the needle goes in"], ["Drag + release", "one stitch"]]


func hud_state() -> Dictionary:
	var title := String(ctx.get("step", {}).get("label", "Stitch the laceration shut"))
	var hint := ""
	if stage == Stage.DONE:
		hint = "Closed up."
	elif stage == Stage.TIE:
		hint = "Tying off."
	elif _flash > 0.0:
		hint = "The stitch tore through the edge."
	elif _miss_hint > 0.0:
		hint = "That didn't cross the wound."
	elif dragging:
		hint = "Now out the other side."
	elif stitches_done == 0:
		hint = "Press where the needle goes in, drag across the gash, let go."
	else:
		hint = "%d of %d sections holding." % [stitches_done, stitch_count]
	return {"title": title, "hint": hint, "progress": progress, "gauges": [], "keys": keys()}


# ---------------------------------------------------------------------------- input

func handle_cursor(p: Vector2, buttons: int, delta: float) -> void:
	if stage != Stage.STITCH:
		_prev_primary = false
		return
	cursor = _panel.mm_of(p) if _panel != null else p
	var primary := (buttons & BUTTON_PRIMARY) != 0
	_cd = maxf(0.0, _cd - delta)
	if _pull > 0.0:
		_prev_primary = primary
		return
	if primary and not _prev_primary and _cd <= 0.0:
		dragging = true
		pressed = true
		drag_from = cursor
		_hold = 0.0
	elif primary and dragging:
		_hold += delta
	elif not primary and _prev_primary and dragging:
		dragging = false
		pressed = false
		if _hold >= min_hold:
			_place(drag_from, cursor)
	if not primary:
		pressed = false
	_prev_primary = primary


## A jerk from an underdosed patient yanks the needle out: the drag is cancelled, and that is all it
## costs. Only reachable in the lab, since a laceration case arrives already sedated.
func on_jolt(_offset: Vector2, _strength: float, _duration: float) -> void:
	if dragging:
		dragging = false
		pressed = false
		_prev_primary = true
		_hold = 0.0
		_miss_hint = 1.4


## One stitch, from where the needle went in to where it came out.
func _place(a: Vector2, b: Vector2) -> void:
	# Into the gap, or not enough skin either side: the thread rips through.
	if _tears_at(a) or _tears_at(b):
		tears += 1
		last_tear = b if _tears_at(b) else a
		_flash = tear_flash_time
		_cd = tear_cooldown
		botch(tear_botch, "The stitch tore through the edge")
		return
	var i := _nearest_open((a + b) * 0.5)
	if i < 0:
		_miss_hint = 1.6
		return
	var s := stitch_at[i]
	var n: Vector2 = nrm[s]
	var sa := (a - pts[s]).dot(n)
	var sb := (b - pts[s]).dot(n)
	if sa * sb >= 0.0:
		_miss_hint = 1.6
		return
	# Which ring each end is measured against depends on which side it landed.
	var ring_in: Vector2 = dot_b[i] if sa > 0.0 else dot_a[i]
	var ring_out: Vector2 = dot_b[i] if sb > 0.0 else dot_a[i]
	var err_in := a.distance_to(ring_in)
	var err_out := b.distance_to(ring_out)
	var span := (b - a).normalized()
	var skew := rad_to_deg(acos(clampf(absf(span.dot(n)), 0.0, 1.0)))
	var good_r := good_radius / sqrt(diff)
	var ok_r := ok_radius
	var mark := ""
	if err_in <= good_r and err_out <= good_r and skew <= good_skew_deg:
		mark = "g"
	elif err_in <= ok_r and err_out <= ok_r and skew <= ok_skew_deg:
		mark = "s"
	else:
		_miss_hint = 1.6
		return
	marks[i] = mark
	entries[i] = a
	exits[i] = b
	stitches_done += 1
	_pull = pull_time
	_pull_i = i
	_update_progress()


## True when this point is inside the gash or leaves less than min_bite of skin to grab. Measured
## against the gape as DRAWN, so a section already pulled shut is safe to cross.
func _tears_at(p: Vector2) -> bool:
	var s := _nearest_sample(p)
	var d := absf((p - pts[s]).dot(nrm[s]))
	# Only near the wound at all: a press out in the corner is a miss, not a tear.
	if (p - pts[s]).length() > gape_max + bite * 2.5:
		return false
	return d < shown_gape(s) * 0.5 + min_bite


func _nearest_sample(p: Vector2) -> int:
	var best := 0
	var bd := INF
	for i in SAMPLES:
		var d: float = pts[i].distance_squared_to(p)
		if d < bd:
			bd = d
			best = i
	return best


## The section this attempt belongs to: the nearest one still open. Stitches may be started from
## either side and done in any order, so nothing is forced but the section itself.
func _nearest_open(p: Vector2) -> int:
	var best := -1
	var bd := INF
	for i in stitch_count:
		if String(marks[i]) != "":
			continue
		var d: float = pts[stitch_at[i]].distance_squared_to(p)
		if d < bd:
			bd = d
			best = i
	if best < 0:
		return -1
	# A section is only a candidate if the attempt is anywhere near it.
	var reach := wound_len / float(stitch_count) + gape_max + bite
	return best if sqrt(bd) <= reach else -1


func _update_progress() -> void:
	progress = clampf(float(stitches_done) / float(stitch_count), 0.0, 1.0)


func _complete() -> void:
	stage = Stage.DONE
	var out := ""
	for i in stitch_count:
		out += String(marks[i]) if String(marks[i]) != "" else "s"
	if _panel != null:
		_panel.close()
	_finish_in = 0.18
	_audio("surgery_done", _at(), -4.0)
	_result = {"closed": true, "stitch_marks": out}


# ---------------------------------------------------------------------------- frame

func tick(delta: float) -> void:
	_t += delta
	_flash = maxf(0.0, _flash - delta)
	_miss_hint = maxf(0.0, _miss_hint - delta)
	_tool = _tool.lerp(cursor, clampf(delta / maxf(0.001, tool_lag), 0.0, 1.0))
	for i in stitch_count:
		var want := closure_of(i)
		# A small bounce as the thread cinches, then it settles.
		var k := clampf(delta / maxf(0.02, pull_time) * 1.5, 0.0, 1.0)
		_shown[i] = move_toward(_shown[i], want, k)
	if _pull > 0.0:
		_pull = maxf(0.0, _pull - delta)
		if _pull <= 0.0 and _pull_i >= 0:
			_pull_i = -1
	if stage == Stage.STITCH and bool(ctx.get("operator", false)):
		_seep(delta)
		if stitches_done >= stitch_count:
			stage = Stage.TIE
			_tie = tie_time
	if stage == Stage.TIE and bool(ctx.get("operator", false)):
		_tie = maxf(0.0, _tie - delta)
		if _tie <= 0.0:
			_complete()
	if _finish_in > 0.0:
		_finish_in -= delta
		if _finish_in <= 0.0:
			_finish_in = -1.0
			finish(_result)
	_panel_state(delta)
	_react()


func _seep(delta: float) -> void:
	pool = clampf(pool + seep_rate * diff * open_share() * delta, 0.0, 2.0)
	if pool >= gush_at:
		pool = gush_reset
		gushes += 1
		botch(gush_botch, "The wound is still open: close it faster")


## The panel exists only while somebody is operating this table, on every machine.
func _panel_state(delta: float) -> void:
	if _panel == null or not is_instance_valid(_panel):
		return
	var on: bool = bool(ctx.get("operating", ctx.get("operator", false))) and stage != Stage.DONE
	if on and not _opened:
		_opened = true
		var pose := camera_pose()
		_panel.right_text = "TABLE %d" % (int(ctx.get("table", 0)) + 1)
		_panel.open(Vector3(0.0, float(pose.height), float(pose.back)))
	elif not on and _opened and _panel.is_open():
		_opened = false
		_panel.close()
	_panel.tick(delta)


## Sounds and the body's reactions, on every machine, from the replicated state.
func _react() -> void:
	var at = _at()
	var body = ctx.get("body")
	var has_body: bool = body != null and is_instance_valid(body)
	if tears > _seen_tears:
		_seen_tears = tears
		_flash = tear_flash_time
		_audio("surgery_tear", at, -3.0, 0.1)
		if has_body and body.has_method("stir"):
			body.stir(0.5)
	if gushes > _seen_gushes:
		_seen_gushes = gushes
		_audio("surgery_botch", at, -6.0)
		if _gush_fx != null and is_instance_valid(_gush_fx):
			_gush_fx.restart()
			_gush_fx.emitting = true
	if stitches_done > _seen_stage:
		_seen_stage = stitches_done
		_audio("downed_stitch", at, -3.0, 0.08)
	if stage != Stage.STITCH and _seen_tie == 0:
		_seen_tie = 1
		_audio("surgery_tourniquet_cinch", at, -6.0)
	# Blood on the gown only while somebody is at the table: with nobody operating, the only thing
	# on the patient is the body's own laceration.
	if has_body and body.has_method("set_bleeding") and bool(ctx.get("operating", ctx.get("operator", false))):
		var b: float = clampf(open_share() * 0.55 + pool * 0.3 + _flash * 0.6, 0.0, 1.0)
		body.set_bleeding(String(ctx.get("step", {}).get("site", "gunshot")), 0.05 if stage == Stage.DONE else b)


func _at():
	return global_position if is_inside_tree() else null


func _audio(cue: String, at, vol := 0.0, jitter := 0.0) -> void:
	var ml = Engine.get_main_loop()
	var a = ml.root.get_node_or_null("Audio") if ml is SceneTree else null
	if a != null:
		a.play(cue, at, vol, jitter)


## The one thing this step puts on the patient: a burst of blood when the wound gushes. It is a
## consequence, not a target, and nothing is left behind.
func _build_body_fx() -> void:
	if not is_inside_tree():
		return
	_gush_fx = CPUParticles3D.new()
	_gush_fx.name = "Gush"
	var gm := SphereMesh.new()
	gm.radius = 0.004
	gm.height = 0.008
	gm.radial_segments = 5
	gm.rings = 3
	_gush_fx.mesh = gm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.38, 0.0, 0.02)
	m.roughness = 0.25
	_gush_fx.material_override = m
	_gush_fx.amount = 36
	_gush_fx.lifetime = 0.8
	_gush_fx.one_shot = true
	_gush_fx.explosiveness = 0.9
	_gush_fx.emitting = false
	_gush_fx.direction = Vector3.UP
	_gush_fx.spread = 45.0
	_gush_fx.initial_velocity_min = 0.4
	_gush_fx.initial_velocity_max = 1.1
	_gush_fx.gravity = Vector3(0, -5.0, 0)
	_gush_fx.position = Vector3(0, 0.01, 0)
	_gush_fx.layers = OWN_LAYER
	add_child(_gush_fx)


# ---------------------------------------------------------------------------- the diagram

func _paint(c: CanvasItem) -> void:
	if _panel == null or pts.is_empty():
		return
	var st: StyleScript = _panel.style
	var beat: float = maxf(0.0, sin(_t * TAU * heart_hz))
	beat *= beat
	_paint_pool(c, st)
	_paint_wound(c, st, beat)
	_paint_dots(c, st)
	_paint_stitches(c, st)
	_paint_tool(c, st)
	if _flash > 0.0:
		var f: float = _flash / maxf(0.01, tear_flash_time)
		var px: Vector2 = _panel.tex_size()
		c.draw_rect(Rect2(Vector2.ZERO, px), Color(st.danger, f * 0.16))
		# A red rim round the whole panel, and a burst where the thread went through.
		c.draw_rect(Rect2(Vector2(6, 6), px - Vector2(12, 12)), Color(st.danger, f * 0.75), false, 14.0)
		var at: Vector2 = _panel.mm_to_px(last_tear)
		var r: float = _panel.mm_len_px(lerpf(11.0, 3.0, f))
		c.draw_circle(at, r, Color(st.danger, f * 0.45))
		for k in 8:
			var d := Vector2.RIGHT.rotated(TAU * float(k) / 8.0)
			c.draw_line(at + d * r * 0.6, at + d * r * 1.9, Color(st.danger, f * 0.9), st.outline)


## Blood welling from the open sections, spreading from the wide ones. Always behind the wound, the
## dots and the tool, and soft enough that it never hides a target.
func _paint_pool(c: CanvasItem, st: StyleScript) -> void:
	if pool <= 0.005:
		return
	for i in stitch_count:
		var open: float = 1.0 - closure_of(i)
		if open <= 0.02:
			continue
		var share: float = start_gape[i] / maxf(0.1, gape_max)
		var r: float = _panel.mm_len_px((4.0 + 30.0 * pool) * share * open)
		var at: Vector2 = _panel.mm_to_px(pts[stitch_at[i]])
		# Concentric rings, faint and falling off outward: a soft stain rather than a stack of discs.
		for ring in 7:
			var k := 1.0 - float(ring) / 7.0
			c.draw_circle(at, r * (0.18 + 0.82 * k), Color(st.blood, (0.035 + 0.05 * pool) * open))


func _paint_wound(c: CanvasItem, st: StyleScript, beat: float) -> void:
	var upper: PackedVector2Array = PackedVector2Array()
	var lower: PackedVector2Array = PackedVector2Array()
	upper.resize(SAMPLES)
	lower.resize(SAMPLES)
	for i in SAMPLES:
		var g := shown_gape(i, beat) * 0.5
		upper[i] = _panel.mm_to_px(pts[i] - nrm[i] * g)
		lower[i] = _panel.mm_to_px(pts[i] + nrm[i] * g)
	# Dark red interior, one quad per segment. A single ring polygon round the whole wound pinches
	# to a point at both ends and Godot's triangulator rejects it, once per frame, loudly.
	for i in SAMPLES - 1:
		if upper[i].distance_to(lower[i]) < 0.7 and upper[i + 1].distance_to(lower[i + 1]) < 0.7:
			continue
		c.draw_colored_polygon(PackedVector2Array([upper[i], upper[i + 1], lower[i + 1], lower[i]]), st.blood_dark)
	# Bright outline, glowing.
	st.glow_poly(c, upper, st.danger, st.outline)
	st.glow_poly(c, lower, st.danger, st.outline)
	c.draw_polyline(upper, st.danger, st.outline)
	c.draw_polyline(lower, st.danger, st.outline)


## A faint ring each side of every stitch, a bite back from the local edge. Unused pairs near the
## cursor brighten, finished ones dim. Nothing ever marks which one to do next.
func _paint_dots(c: CanvasItem, st: StyleScript) -> void:
	var r: float = _panel.mm_len_px(2.1)
	for i in stitch_count:
		var done := String(marks[i]) != ""
		var a: Vector2 = _panel.mm_to_px(dot_a[i])
		var b: Vector2 = _panel.mm_to_px(dot_b[i])
		var col: Color = st.line_dim
		var w: float = st.thin
		if done:
			col = Color(st.line_dim, 0.35)
		else:
			var near: float = 1.0 - smoothstep(6.0, 22.0, minf(cursor.distance_to(dot_a[i]), cursor.distance_to(dot_b[i])))
			col = st.line_dim.lerp(st.line, near)
			if near > 0.3:
				st.glow_circle(c, a, r, st.line, st.hair)
				st.glow_circle(c, b, r, st.line, st.hair)
				w = st.thin + near
		c.draw_arc(a, r, 0.0, TAU, 18, col, w)
		c.draw_arc(b, r, 0.0, TAU, 18, col, w)


func _paint_stitches(c: CanvasItem, st: StyleScript) -> void:
	var last: Vector2 = Vector2.ZERO
	var have_last := false
	for i in stitch_count:
		var m := String(marks[i])
		if m == "":
			continue
		var a: Vector2 = _panel.mm_to_px(entries[i])
		var b: Vector2 = _panel.mm_to_px(exits[i])
		var col: Color = st.thread if m == "g" else st.sloppy
		var k: float = _shown[i] / maxf(0.01, closure_of(i))
		# The cinch: the thread draws the two ends together as it pulls.
		var mid := (a + b) * 0.5
		var pa: Vector2 = a.lerp(mid, 0.18 * k)
		var pb: Vector2 = b.lerp(mid, 0.18 * k)
		st.glow_line(c, pa, pb, col, st.outline)
		c.draw_line(pa, pb, col, st.outline)
		# Little knots either end.
		c.draw_circle(pa, st.outline * 0.9, col)
		c.draw_circle(pb, st.outline * 0.9, col)
		last = pb
		have_last = true
	# Thread from the last finished stitch to the needle, with a little sag. Visual only.
	if have_last:
		var tip: Vector2 = _panel.mm_to_px(_tool)
		var sag := Vector2(0, _panel.mm_len_px(3.5))
		var curve: PackedVector2Array = PackedVector2Array()
		for s in 9:
			var t := float(s) / 8.0
			curve.append(last.lerp(tip, t) + sag * sin(t * PI))
		c.draw_polyline(curve, Color(st.thread, 0.55), st.thin)
	# The drag in progress: dashed from where the needle went in to the cursor.
	if dragging:
		st.dashed(c, _panel.mm_to_px(drag_from), _panel.mm_to_px(cursor), Color(st.thread, 0.8), st.thin)
		c.draw_circle(_panel.mm_to_px(drag_from), st.outline, st.thread)


## The needle driver, holding a curved needle, trailing the cursor. Drawn from the tip back, so the
## needle is at the cursor and the handle runs off up and to the right, out of the way of the wound.
func _paint_tool(c: CanvasItem, st: StyleScript) -> void:
	var tip: Vector2 = _panel.mm_to_px(_tool)
	var lean := Vector2(0.72, -0.69).normalized()
	var side := Vector2(-lean.y, lean.x)
	var mm: float = _panel.mm_len_px(1.0)
	# The needle: a bright curved hook with its point at the cursor.
	var arc: PackedVector2Array = PackedVector2Array()
	var r := 5.6 * mm
	var centre: Vector2 = tip + side * r
	for i in 13:
		var ang: float = lerpf(0.0, 2.5, float(i) / 12.0)
		arc.append(centre - (side * cos(ang) + lean * sin(ang)) * r)
	st.glow_poly(c, arc, st.line, st.outline)
	c.draw_polyline(arc, st.line, st.outline)
	c.draw_circle(tip, st.thin, st.line)
	# The jaws holding it, then the two arms and their ring handles.
	var hinge: Vector2 = tip + lean * 7.2 * mm + side * 9.6 * mm
	var jaw_a: Vector2 = arc[arc.size() - 1]
	c.draw_line(jaw_a, hinge, st.steel, st.outline * 1.7)
	c.draw_circle(hinge, st.outline * 1.3, st.steel)
	for s: float in [-1.0, 1.0]:
		var elbow: Vector2 = hinge + lean * 6.0 * mm + side * (2.0 * mm * s)
		var hand: Vector2 = hinge + lean * 14.0 * mm + side * (4.2 * mm * s)
		c.draw_line(hinge, elbow, st.steel, st.outline)
		c.draw_line(elbow, hand, st.steel, st.outline)
		c.draw_arc(hand + lean * 2.4 * mm + side * (1.0 * mm * s), 2.5 * mm, 0.0, TAU, 14, st.steel, st.thin)


# ---------------------------------------------------------------------------- net

func net_state() -> Dictionary:
	var st: Array = []
	for i in stitch_count:
		if String(marks[i]) == "":
			continue
		st.append([i, String(marks[i]), entries[i].snappedf(0.1), exits[i].snappedf(0.1)])
	var out := {
		# The pool is sent raw: it creeps up by well under a hundredth a frame, and rounding it
		# would quantise the rise away to nothing.
		"sd": profile_seed, "st": st, "pl": pool,
		"c": cursor.snappedf(0.2), "pr": pressed, "sg": stage,
		"tr": tears, "tp": last_tear.snappedf(0.2), "gu": gushes, "p": snappedf(progress, 0.01),
	}
	if dragging:
		out["dr"] = drag_from.snappedf(0.2)
	return out


func apply_net_state(s: Dictionary) -> void:
	if s.is_empty():
		return
	# The gape profile is never sent: it is regenerated from the seed it was built with.
	var sd := int(s.get("sd", profile_seed))
	if sd != profile_seed:
		profile_seed = sd
		_build_wound()
	for i in stitch_count:
		marks[i] = ""
	stitches_done = 0
	for e in s.get("st", []):
		if not (e is Array) or (e as Array).size() < 4:
			continue
		var i := int(e[0])
		if i < 0 or i >= stitch_count:
			continue
		marks[i] = String(e[1])
		entries[i] = e[2]
		exits[i] = e[3]
		stitches_done += 1
	pool = float(s.get("pl", pool))
	cursor = s.get("c", cursor)
	pressed = bool(s.get("pr", pressed))
	stage = int(s.get("sg", stage))
	tears = int(s.get("tr", tears))
	last_tear = s.get("tp", last_tear)
	gushes = int(s.get("gu", gushes))
	progress = float(s.get("p", progress))
	if s.has("dr"):
		dragging = true
		drag_from = s.dr
	else:
		dragging = false


# ---------------------------------------------------------------------------- bot

## skill 1.0 closes the widest open section next -- the play the panel is trying to teach without
## saying so. skill 0.0 works end to end and aims badly.
func bot_input(t: float, skill: float) -> Dictionary:
	var dt: float = clampf(t - _bt, 0.0, 0.1)
	_bt = t
	skill = clampf(skill, 0.0, 1.0)
	var sloppy := 1.0 - skill
	_b_cd = maxf(0.0, _b_cd - dt)
	if stage != Stage.STITCH or _pull > 0.0 or _b_cd > 0.0:
		return {"cursor": _out(_b_cursor), "buttons": 0}
	if _b_target < 0 or String(marks[_b_target]) != "":
		_b_target = _bot_pick(skill)
		_b_phase = 0
		_b_hold = 0.0
		_b_dwell = 0.0
		var spread: float = lerpf(0.1, 1.66, sloppy) * ok_radius
		_b_seq += 1
		_b_err_in = _b_wobble(_b_seq * 2 - 1, spread)
		_b_err_out = _b_wobble(_b_seq * 2, spread)
	if _b_target < 0:
		return {"cursor": _out(_b_cursor), "buttons": 0}
	var a: Vector2 = dot_a[_b_target] + _b_err_in
	var b: Vector2 = dot_b[_b_target] + _b_err_out
	var speed: float = lerpf(72.0, 46.0, skill) * dt      # mm per second
	if _b_phase == 0:
		_b_cursor = _b_cursor.move_toward(a, speed)
		if _b_cursor.distance_to(a) < 0.4:
			_b_dwell += dt
			if _b_dwell >= lerpf(0.22, 0.70, skill):
				_b_phase = 1
				_b_hold = 0.0
		return {"cursor": _out(_b_cursor), "buttons": BUTTON_PRIMARY if _b_phase == 1 else 0}
	_b_hold += dt
	_b_cursor = _b_cursor.move_toward(b, speed)
	if _b_cursor.distance_to(b) < 0.4 and _b_hold >= min_hold + 0.04:
		_b_phase = 2
		_b_cd = lerpf(0.36, 0.85, skill) + bot_pause
		_b_target = -1
		return {"cursor": _out(_b_cursor), "buttons": 0}
	return {"cursor": _out(_b_cursor), "buttons": BUTTON_PRIMARY}


## How far off a stitch lands. A golden-ratio sequence rather than a random draw: the magnitudes and
## directions are spread evenly and come out the same every run, so a bad hand is reliably bad and
## the self-test's numbers do not swing from patient to patient.
func _b_wobble(k: int, spread: float) -> Vector2:
	var m: float = fposmod(float(k) * 0.6180339887498949, 1.0)
	var a: float = fposmod(float(k) * 2.399963229728653, TAU)
	return Vector2.RIGHT.rotated(a) * m * spread


## The widest open section for a good surgeon; the leftmost for a bad one.
func _bot_pick(skill: float) -> int:
	var widest: bool = skill >= 0.5 if bot_order_widest == null else bool(bot_order_widest)
	var best := -1
	for i in stitch_count:
		if String(marks[i]) != "":
			continue
		if best < 0:
			best = i
		elif widest and start_gape[i] > start_gape[best]:
			best = i
	return best


## The bot works in millimetres like everything else; the framework wants panel metres.
func _out(mm: Vector2) -> Vector2:
	if _panel != null:
		return _panel.metres_of(mm)
	return mm


# ---------------------------------------------------------------------------- self-test

## Headless check through the lab: `tools/minigame_lab.tscn -- --selftest=suture`.
## Targets: skill 1.0 finishes in 8-20 s losing 0-2 vitals, skill 0.0 under 40 s losing 15-25.
## It also proves the point of the uneven gape: widest-first costs fewer vitals than end-to-end on
## the same wound.
static func self_test() -> Array:
	var script: GDScript = load("res://scripts/surgery/games/suture.gd")
	var out := []
	var ok := true
	for pid: String in ["bob", "seal"]:
		for cond: Dictionary in [{"skill": 1.0, "sed": 1.0}, {"skill": 0.5, "sed": 1.0},
				{"skill": 0.0, "sed": 1.0}, {"skill": 1.0, "sed": 0.4}]:
			var g = script.new()
			var tally := {"n": 0, "v": 0.0, "done": false, "marks": "", "reasons": {}}
			g.botched.connect(func(a, r): tally.n += 1; tally.v += a; tally.reasons[r] = int(tally.reasons.get(r, 0)) + 1)
			g.finished.connect(func(r): tally.done = true; tally.marks = String(r.get("stitch_marks", "")))
			g.setup({"patient_id": pid, "patient": Procedures.patient(pid), "ailment_id": "laceration",
				"step": Procedures.step("laceration", 0), "variant": "", "shift": 1, "difficulty": 1.0,
				"flags": {"sedation": cond.sed}, "seed": hash("suture" + pid), "body": null, "operator": true})
			var t: float = _run_bot(g, float(cond.skill), float(cond.sed), hash(pid + "suture"))
			print("[suture self-test] %-4s skill=%.1f sed=%.1f  %s  time=%5.1fs  marks=%-8s botches=%2d vitals=%5.1f pool=%.2f  %s" % [
				pid, cond.skill, cond.sed, "DONE" if tally.done else "UNFINISHED", t, tally.marks, tally.n, tally.v,
				g.pool, str(tally.reasons)])
			out.append({"patient": pid, "skill": cond.skill, "sed": cond.sed, "done": tally.done,
				"time": t, "vitals": tally.v, "marks": tally.marks})
			if float(cond.skill) == 1.0 and float(cond.sed) == 1.0:
				if not tally.done or t < 8.0 or t > 20.0 or tally.v > 2.0:
					print("[suture self-test] MISS: skill 1.0 wants 8-20 s and 0-2 vitals")
					ok = false
			if float(cond.skill) == 0.0 and (not tally.done or t > 40.0 or tally.v < 15.0 or tally.v > 25.0):
				print("[suture self-test] MISS: skill 0.0 wants under 40 s and 15-25 vitals")
				ok = false
			g.free()
	# The point of the uneven gape: the same hand, at a person's pace, on the same wounds, pays less
	# for closing the worst stretch first. Judged on the total: when a wound's widest stretch happens
	# to sit at the near end, the two orders are all but the same run, and that is fine.
	var wide_total := 0.0
	var ends_total := 0.0
	for seed_v: int in [3, 11, 29, 47, 58, 91]:
		var wide := _order_cost(script, seed_v, true)
		var ends := _order_cost(script, seed_v, false)
		wide_total += wide
		ends_total += ends
		print("[suture self-test] seed=%-3d widest-first vitals=%5.1f   end-to-end vitals=%5.1f" % [seed_v, wide, ends])
		out.append({"seed": seed_v, "widest_first": wide, "end_to_end": ends})
	print("[suture self-test] order totals: widest-first %.1f   end-to-end %.1f" % [wide_total, ends_total])
	out.append({"widest_first_total": wide_total, "end_to_end_total": ends_total})
	if wide_total >= ends_total:
		print("[suture self-test] MISS: closing the widest stretch first should cost less overall")
		ok = false
	print("[suture self-test] %s" % ("PASS" if ok else "FAIL"))
	return out


## The same perfect hand playing the same wound in two orders, so only the order is being measured.
static func _order_cost(script: GDScript, seed_v: int, widest_first: bool) -> float:
	var g = script.new()
	var tally := {"v": 0.0}
	g.botched.connect(func(a, _r): tally.v += a)
	g.setup({"patient_id": "bob", "patient": Procedures.patient("bob"), "ailment_id": "laceration",
		"step": Procedures.step("laceration", 0), "variant": "", "shift": 1, "difficulty": 1.0,
		"flags": {"sedation": 1.0}, "seed": seed_v, "body": null, "operator": true})
	g.set("bot_order_widest", widest_first)
	g.set("bot_pause", 2.6)
	_run_bot(g, 1.0, 1.0, seed_v)
	var v: float = tally.v
	g.free()
	return v


## Feed bot_input through handle_cursor and tick at 60 Hz, with the surgery system's stirs when
## sedation is under 0.75. Unlike the other games this step does real work in tick() -- the cinch,
## the seep, the tie-off -- so it cannot borrow gauze's runner. Returns the time taken.
static func _run_bot(g, skill: float, sed: float, seed_v: int) -> float:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var t := 0.0
	var dt := 1.0 / 60.0
	var ext: Vector2 = g.plane_extent()
	var next_stir := 2.0
	var jolt_t := 0.0
	var jolt := Vector2.ZERO
	while t < 90.0 and not g.done:
		t += dt
		var inp: Dictionary = g.bot_input(t, skill)
		var c: Vector2 = inp.get("cursor", Vector2.ZERO)
		if sed < 0.75:
			next_stir -= dt
			if next_stir <= 0.0:
				next_stir = lerpf(2.5, 11.0, sed / 0.75) * rng.randf_range(0.7, 1.3)
				var strength := clampf((0.75 - sed) / 0.75, 0.0, 1.0) * 0.8 + 0.2
				jolt = Vector2.RIGHT.rotated(rng.randf() * TAU) * strength * 0.09
				jolt_t = 0.35
				g.on_jolt(jolt, strength, 0.35)
			if jolt_t > 0.0:
				jolt_t -= dt
				c += jolt * (jolt_t / 0.35)
		c = Vector2(clampf(c.x, -ext.x, ext.x), clampf(c.y, -ext.y, ext.y))
		g.handle_cursor(c, int(inp.get("buttons", 0)), dt)
		g.tick(dt)
		g.apply_net_state(g.net_state())
	return t
