extends "res://scripts/surgery/games/suture.gd"
## ARCADE SURGERY (docs/ARCADE_SURGERY.md) 5.12 -- STITCH!, the RING variant. Step "stitch" of an
## Eyeball Graft: sew the lid shut round the eye that has just gone in. EG step 4.
##
## This is not a rebuild. 5.12 says to use the panel suture game that is already approved, so that
## is exactly what this is: scripts/surgery/games/suture.gd with a different wound. Press where the
## needle goes in, drag across, let go -- the same hands, the same grading, the same thread.
##
## What the ring changes
##   THE WOUND IS CLOSED. It runs all the way round the socket instead of across the panel, so
##   there is no end to start from and no end to finish at: eight sections, in whatever order you
##   like, with the new eye sitting in the middle of them looking back at you.
##   BLOOD HIDES THE DOTS. Every vessel STEER! (5.8) opened on the way round is still bleeding, and
##   the case carries the angles it opened them at. A blot sits over each one, and the two faint
##   rings that tell you where that stitch goes are under it. You stitch those from memory. Drive
##   the first step carefully and this one is a formality; take the vessels at speed and you are
##   sewing blind at four places out of eight.
##   NOTHING COSTS ANYTHING. The graft sets `no_fail`: a stitch torn through the lid is a retry and
##   nothing more. The marks still land on the face.
##
## Result {"eye_stitched": true, "stitch_marks": "ggsgg..."} -- the marks in order round the ring,
## anticlockwise from the outside of the face, which is how they are drawn on the player afterwards.

# -- the ring ------------------------------------------------------------------------------------
## The wound's radius round the socket, in diagram millimetres.
@export_range(8.0, 34.0, 0.5) var ring_radius := 17.0
## The eight sections' own gape, widest and narrowest. The parent's numbers are a laceration's; a
## lid does not gape like a bandsaw cut.
@export_range(2.0, 16.0, 0.5) var ring_gape_max := 5.5
@export_range(0.5, 8.0, 0.1) var ring_gape_min := 2.0
## How far back from the edge the dots sit. Wider than the laceration's: the ring is a small target
## with the eye on the other side of it, and it has to stay stitchable by an unsteady hand.
@export_range(2.0, 12.0, 0.5) var ring_bite := 7.0
@export_range(2, 16) var ring_stitches := 8
## How many of the eight sections gape wide. They are placed ON sections, never between them.
@export_range(1, 4) var ring_hot := 2

# -- the blood -----------------------------------------------------------------------------------
## How much of the ring one opened vessel hides, either side of its angle. Matches STEER!'s blot.
@export_range(2.0, 60.0, 1.0) var blot_deg := 12.0
## A dot you cannot see is a dot you aim at from memory: how much wider the bot's aim goes under a
## blot. Tuning for the lab; a player just squints at it.
@export_range(1.0, 12.0, 0.1) var blind_spread := 8.0
## The worst the bot's aim gets on a ring, as a fraction of `ok_radius`. The parent's sloppiest hand
## is scaled for a gash across a forearm; thrown at a lid it never lands a stitch at all.
@export_range(0.1, 2.0, 0.05) var bot_spread_cap := 1.0

# ---- derived ----
## The angles STEER! left bleeding, in degrees round the ring, straight out of the case flags.
var blot_angles: Array = []
var socket_r := 10.0              ## the grafted eye, drawn inside the ring of stitches


# ---------------------------------------------------------------------------- the wound

## A closed ring round the socket instead of a gash across the panel. Called from the parent's
## setup() BEFORE it sizes the mark arrays, which is why the stitch count is set here.
func _build_wound() -> void:
	stitch_count = ring_stitches
	gape_max = ring_gape_max
	gape_min = ring_gape_min
	bite = ring_bite
	wound_len = TAU * ring_radius
	blot_angles.clear()
	# The legacy cut step does not write the flag at all, and the lab can only pass a number, so
	# take an absent key, one angle or a list of them.
	var bl = (ctx.get("flags", {}) as Dictionary).get("vessel_bleeds", [])
	if bl is float or bl is int:
		bl = [bl]
	for a in (bl if bl is Array else []):
		blot_angles.append(fposmod(float(a), 360.0))
	socket_r = maxf(3.0, ring_radius - (gape_max * 0.5 + bite) - 1.5)
	# Sample 0 and the last sample are the same point, so the wound closes on itself and every
	# polyline the parent draws round it meets.
	pts.resize(SAMPLES)
	nrm.resize(SAMPLES)
	for i in SAMPLES:
		var a := ring_angle(i)
		var d := Vector2(cos(a), sin(a))
		pts[i] = d * ring_radius
		nrm[i] = d                      # outward, so dot_a is the lid side and dot_b the brow side
	stitch_at.resize(stitch_count)
	for i in stitch_count:
		var t := (float(i) + 0.5) / float(stitch_count)
		stitch_at[i] = clampi(int(round(t * float(SAMPLES - 1))), 0, SAMPLES - 1)
	gap = _ring_profile()
	start_gape.resize(stitch_count)
	dot_a.resize(stitch_count)
	dot_b.resize(stitch_count)
	for i in stitch_count:
		var s := stitch_at[i]
		start_gape[i] = gap[s]
		var off := gap[s] * 0.5 + bite
		dot_a[i] = pts[s] - nrm[s] * off
		dot_b[i] = pts[s] + nrm[s] * off


## Where sample `i` sits round the ring, in radians. The same frame of reference STEER! records its
## vessels in: atan2(y, x) on the diagram, where +y is DOWN.
func ring_angle(i: int) -> float:
	return TAU * float(i) / float(SAMPLES - 1)


## Wide at a couple of seeded sections, narrow elsewhere, and it wraps: there are no ends to taper
## to. The hot stretches are centred ON sections, so the widest one always has a stitch to close it
## and the parent's rejection loop is not needed.
func _ring_profile() -> PackedFloat32Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = profile_seed ^ 0x27a1
	var hots: Array = []
	var want: int = rng.randi_range(1, maxi(1, ring_hot))
	while hots.size() < want:
		var k: int = rng.randi_range(0, stitch_count - 1)
		var ok := true
		for h in hots:
			if absf(angle_difference(ring_angle(stitch_at[int(h)]), ring_angle(stitch_at[k]))) < 1.1:
				ok = false
		if ok:
			hots.append(k)
		elif hots.size() + 1 >= want:
			break
	var floor_k: float = clampf(gape_min / maxf(0.5, gape_max), 0.05, 0.8)
	var out: PackedFloat32Array = PackedFloat32Array()
	out.resize(SAMPLES)
	for i in SAMPLES:
		var a := ring_angle(i)
		var v := floor_k
		for h in hots:
			var d: float = angle_difference(a, ring_angle(stitch_at[int(h)])) / 0.5
			v += (1.0 - floor_k) * exp(-d * d)
		# A little seeded wobble so no two sections are twins, wrapping with the ring.
		v *= 1.0 + 0.08 * sin(a * 3.0 + float(rng.seed % 97))
		out[i] = v
	var peak := 0.0001
	for i in SAMPLES:
		peak = maxf(peak, out[i])
	for i in SAMPLES:
		out[i] = out[i] / peak * gape_max
	out[SAMPLES - 1] = out[0]
	return out


## The parent interpolates a sample's closure between the two nearest stitches and clamps at the
## ends. A ring has no ends: section 0 and section 7 are neighbours, and the seam has to close like
## any other stretch or the wound visibly tears open at three o'clock.
func shown_gape(i: int, beat := 0.0) -> float:
	var t := float(i) / float(SAMPLES - 1) * float(stitch_count) - 0.5
	var a := int(floor(t))
	var k: float = clampf(t - float(a), 0.0, 1.0)
	var ia: int = posmod(a, stitch_count)
	var ib: int = posmod(a + 1, stitch_count)
	var closed: float = lerpf(_shown[ia], _shown[ib], k)
	var g: float = gap[i] * (1.0 - closed)
	return g * (1.0 + beat * pulse_strength * (gap[i] / maxf(0.1, gape_max)))


## True where an opened vessel has painted the ring out. The dots for that section are under the
## blood, and the only thing that says where they were is where the others are.
func hidden_stitch(i: int) -> bool:
	if blot_angles.is_empty() or i < 0 or i >= stitch_count:
		return false
	var deg := rad_to_deg(ring_angle(stitch_at[i]))
	for a in blot_angles:
		if absf(rad_to_deg(angle_difference(deg_to_rad(deg), deg_to_rad(float(a))))) <= blot_deg:
			return true
	return false


func hidden_count() -> int:
	var n := 0
	for i in stitch_count:
		if hidden_stitch(i):
			n += 1
	return n


# ---------------------------------------------------------------------------- the rules

## The graft sets `no_fail`: a torn stitch is a retry and costs nothing. Everything else about a
## tear -- the flash, the cooldown, the flinch on the patient -- still happens.
func botch(amount: float, reason: String) -> void:
	if bool(ctx.get("no_fail", false)):
		return
	super.botch(amount, reason)


## Nothing to open: the socket is already open and a face wears no gown.
func _expose() -> void:
	pass


## The graft's result, not the laceration's. The marks go on the PLAYER'S FACE round the new eye.
func _complete() -> void:
	stage = Stage.DONE
	var out := ""
	for i in stitch_count:
		out += String(marks[i]) if String(marks[i]) != "" else "s"
	if _panel != null and is_instance_valid(_panel):
		_panel.close()
	_finish_in = 0.18
	_audio("surgery_done", _at(), -4.0)
	_result = {"eye_stitched": true, "stitch_marks": out}


func hud_state() -> Dictionary:
	var s := super.hud_state()
	s["title"] = String(ctx.get("step", {}).get("label", "Stitch it in"))
	if stage == Stage.STITCH and hidden_count() > 0 and stitches_done < stitch_count:
		var left := 0
		for i in stitch_count:
			if String(marks[i]) == "" and hidden_stitch(i):
				left += 1
		if left > 0:
			s["hint"] = "%d of them are under the blood. You know where they should be." % left
	return s


# ---------------------------------------------------------------------------- the diagram

## The eye first, underneath everything: the graft is in and this is what the stitches are round.
func _paint(c: CanvasItem) -> void:
	if _panel == null or pts.is_empty():
		return
	_paint_socket(c, _panel.style)
	super._paint(c)


func _paint_socket(c: CanvasItem, st) -> void:
	var at: Vector2 = _panel.mm_to_px(Vector2.ZERO)
	var r: float = _panel.mm_len_px(socket_r)
	c.draw_circle(at, r, Color(st.bg_inner, 0.95))
	st.glow_circle(c, at, r, st.line, st.thin)
	c.draw_arc(at, r, 0.0, TAU, 40, st.line, st.outline)
	# The new eye, looking straight up at whoever is sewing. Round pupil, ringed iris: the same
	# drawing STEER! puts on a surgeon, so the two steps read as the same eye.
	var ir := r * 0.46
	c.draw_arc(at, ir, 0.0, TAU, 24, Color(st.line, 0.8), st.thin)
	for k in 10:
		var d := Vector2.RIGHT.rotated(TAU * float(k) / 10.0)
		c.draw_line(at + d * ir * 0.45, at + d * ir, Color(st.line, 0.45), st.hair)
	c.draw_circle(at, ir * 0.5, st.bg)


## The parent's dots, less the ones under blood. The blots go on first so they cover the wound
## itself as well, and the sections beneath them are simply not drawn: there is nothing to aim at.
func _paint_dots(c: CanvasItem, st) -> void:
	for a in blot_angles:
		_paint_blot(c, st, deg_to_rad(float(a)))
	var r: float = _panel.mm_len_px(2.1)
	for i in stitch_count:
		if hidden_stitch(i) and String(marks[i]) == "":
			continue
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


## One vessel STEER! opened, still bleeding. It covers the ring from the eye to past the brow line,
## and it is ragged rather than a neat wedge so it never reads as part of the diagram.
func _paint_blot(c: CanvasItem, st, a: float) -> void:
	var span := deg_to_rad(blot_deg)
	var r0: float = socket_r * 0.9
	var r1: float = ring_radius + gape_max * 0.5 + bite + 4.0
	var poly: PackedVector2Array = PackedVector2Array()
	for i in 15:
		var t: float = lerpf(-span, span, float(i) / 14.0)
		poly.append(_panel.mm_to_px(Vector2(cos(a + t), sin(a + t)) * r1))
	for i in 15:
		var t: float = lerpf(span, -span, float(i) / 14.0)
		poly.append(_panel.mm_to_px(Vector2(cos(a + t), sin(a + t)) * r0))
	c.draw_colored_polygon(poly, Color(st.blood, 0.95))
	var rng := RandomNumberGenerator.new()
	rng.seed = int(round(rad_to_deg(a) * 10.0)) ^ 0x51a7
	for i in 10:
		var ra: float = a + rng.randf_range(-span, span)
		var rr: float = rng.randf_range(r0, r1 + 3.0)
		c.draw_circle(_panel.mm_to_px(Vector2(cos(ra), sin(ra)) * rr),
			_panel.mm_len_px(rng.randf_range(1.4, 3.8)), Color(st.blood, 0.9))


# ---------------------------------------------------------------------------- bot

## The parent's hand, with one thing added: a section under a blot is aimed at from memory, so the
## error on it is several times what the same hand makes on a section it can see. `_b_target` is
## picked immediately before this is called for that stitch's two ends.
func _b_wobble(k: int, spread: float) -> Vector2:
	spread = minf(spread, ok_radius * bot_spread_cap)
	if _b_target < 0 or not hidden_stitch(_b_target):
		return super._b_wobble(k, spread)
	# Aimed from memory, so never quite on it: the magnitude starts well off the dot instead of at
	# nothing. The same golden-ratio sequence, so it is the same wrong guess every run.
	var m: float = fposmod(float(k) * 0.6180339887498949, 1.0)
	var ang: float = fposmod(float(k) * 2.399963229728653, TAU)
	var wide: float = clampf(spread * blind_spread, good_radius * 1.4, ok_radius)
	return Vector2.RIGHT.rotated(ang) * lerpf(0.6, 1.0, m) * wide


## A ring is sewn round, not across. The parent's "widest open section" sends the needle to the far
## side of the socket and back every stitch; on a closed wound the nearest open one is both quicker
## and what anybody actually does.
func _bot_pick(skill: float) -> int:
	if bot_order_widest != null:
		return super._bot_pick(skill)
	var best := -1
	var bd := INF
	for i in stitch_count:
		if String(marks[i]) != "":
			continue
		var d: float = _b_cursor.distance_squared_to(dot_a[i])
		# A good hand still takes the worst one first when two are equally close to hand.
		if skill >= 0.5:
			d -= start_gape[i] * start_gape[i] * 4.0
		if d < bd:
			bd = d
			best = i
	return best


# ---------------------------------------------------------------------------- self-test

## Headless check: `tools/minigame_lab.tscn -- --selftest=eye:stitch:arcade`.
## The graft always sets `no_fail`, so the real case has no vitals to lose and only the clock is
## checked there; the same ring is also run with the flag off to prove a tear still costs when it
## is allowed to. Targets: skill 1.0 finishes in 8-20 s, skill 0.0 under 40 s.
static func self_test() -> Array:
	var script: GDScript = load("res://scripts/surgery/arcade/ring_arcade.gd")
	var out := []
	var ok := true
	for cond: Dictionary in [{"nf": true, "bleeds": []}, {"nf": true, "bleeds": [22.5, 157.5]},
			{"nf": false, "bleeds": []}]:
		for skill: float in [1.0, 0.5, 0.0]:
			var g = script.new()
			var tally := {"n": 0, "v": 0.0, "done": false, "marks": "", "reasons": {}}
			g.botched.connect(func(a, r): tally.n += 1; tally.v += a; tally.reasons[r] = int(tally.reasons.get(r, 0)) + 1)
			g.finished.connect(func(r): tally.done = true; tally.marks = String(r.get("stitch_marks", "")))
			g.setup(_ring_ctx(bool(cond.nf), cond.bleeds, hash("ring")))
			var t: float = _run_bot(g, skill, 1.0, hash("ring") + int(skill * 100))
			print("[ring self-test] no_fail=%-5s bleeds=%d hidden=%d skill=%.1f  %s  time=%5.1fs  marks=%-10s tears=%d botches=%2d vitals=%5.1f  %s" % [
				str(bool(cond.nf)), (cond.bleeds as Array).size(), g.hidden_count(), skill,
				"DONE" if tally.done else "UNFINISHED", t, tally.marks, g.tears, tally.n, tally.v,
				str(tally.reasons)])
			out.append({"no_fail": cond.nf, "bleeds": cond.bleeds, "skill": skill, "done": tally.done,
				"time": t, "vitals": tally.v, "marks": tally.marks, "hidden": g.hidden_count()})
			if not tally.done:
				print("[ring self-test] MISS: the ring has to close")
				ok = false
			if skill == 1.0 and (t < 8.0 or t > 20.0):
				print("[ring self-test] MISS: skill 1.0 wants 8-20 s")
				ok = false
			if skill == 0.0 and t > 40.0:
				print("[ring self-test] MISS: skill 0.0 wants under 40 s")
				ok = false
			if bool(cond.nf) and tally.v > 0.0:
				print("[ring self-test] MISS: no_fail must cost nothing")
				ok = false
			if String(tally.marks).length() != g.stitch_count:
				print("[ring self-test] MISS: one mark per stitch, in order round the ring")
				ok = false
			g.free()
	# The carry-forward: the angles STEER! hands over are the angles the blood covers, and a hidden
	# section is visibly harder to put a stitch in than one you can see.
	var clean := _marks_for(script, [])
	var blind := _marks_for(script, [22.5, 112.5, 202.5])
	print("[ring self-test] no bleeds -> hidden=%d marks=%s   three bleeds -> hidden=%d marks=%s" % [
		clean[0], clean[1], blind[0], blind[1]])
	out.append({"clean_hidden": clean[0], "clean_marks": clean[1], "blind_hidden": blind[0], "blind_marks": blind[1]})
	if int(clean[0]) != 0:
		print("[ring self-test] MISS: nothing should be hidden with no vessel_bleeds")
		ok = false
	if int(blind[0]) != 3:
		print("[ring self-test] MISS: one hidden section per opened vessel")
		ok = false
	if String(blind[1]).count("s") <= String(clean[1]).count("s"):
		print("[ring self-test] MISS: sewing blind should leave more crooked stitches")
		ok = false
	# A missing key is the legacy cut step's result, and it must not be an error.
	var g2 = script.new()
	g2.setup({"patient_id": "player", "patient": Procedures.patient("player"), "ailment_id": "eye_graft",
		"step": Procedures.step("eye_graft", 3), "variant": "stitch", "shift": 1, "difficulty": 1.0,
		"flags": {"sedation": 1.0}, "seed": 7, "body": null, "operator": true, "operating": true})
	print("[ring self-test] no vessel_bleeds key at all -> hidden=%d, stitches=%d" % [g2.hidden_count(), g2.stitch_count])
	if g2.hidden_count() != 0 or g2.stitch_count != 8:
		print("[ring self-test] MISS: an absent vessel_bleeds must be tolerated, and the ring is 8 stitches")
		ok = false
	g2.free()
	print("[ring self-test] %s" % ("PASS" if ok else "FAIL"))
	return out


static func _ring_ctx(no_fail: bool, bleeds: Array, seed_v: int) -> Dictionary:
	var flags := {"sedation": 1.0, "vessel_bleeds": bleeds, "eye_radius": Grafts.EYE_RADIUS}
	if no_fail:
		flags["no_fail"] = true
	var c := {"patient_id": "player", "patient": Procedures.patient("player"), "ailment_id": "eye_graft",
		"step": Procedures.step("eye_graft", 3), "variant": "stitch", "shift": 1,
		"difficulty": Procedures.difficulty(1), "flags": flags, "seed": seed_v, "body": null,
		"operator": true, "operating": true}
	if no_fail:
		c["no_fail"] = true
	c["eye_radius"] = Grafts.EYE_RADIUS
	return c


## The same hand on the same ring, once in the clear and once under blood.
static func _marks_for(script: GDScript, bleeds: Array) -> Array:
	var g = script.new()
	var marks := {"m": ""}
	g.finished.connect(func(r): marks.m = String(r.get("stitch_marks", "")))
	g.setup(_ring_ctx(true, bleeds, hash("ringcarry")))
	_run_bot(g, 1.0, 1.0, 5150)
	var r := [g.hidden_count(), marks.m]
	g.free()
	return r
