extends "res://scripts/surgery/arcade/arcade_game.gd"
## ARCADE SURGERY (docs/ARCADE_SURGERY.md) 5.7 -- WRAP!, the stump. Step "dress" of an amputation,
## `gauze` x2, variant `stump`. The arcade rebuild of the wrap half of scripts/surgery/games/gauze.gd.
##
## Rhyme: Snake. The bandage roll is the snake; the trail behind it is bandage.
##
## What you do
##   A ring of cells sits round the cut end of the limb and every one of them wants TWO turns of
##   bandage over it. The roll comes in from the left and never stops moving: WASD or the arrows
##   steer it, and it cannot be reversed. You may cross your own bandage only on the wound -- that
##   is the layering -- so the whole job is working out a route that comes back round without ever
##   running over the tail somewhere it does not belong. Run into the tail, or into the edge of the
##   panel, and the roll tangles and has to be cut and started again.
##   The roll is ninety cells long. Run it out and you are billed for the one you have to open.
##   CARRY-FORWARD: whatever the tourniquet did not stop is still bleeding. Those cells are marked
##   with a cross, they want a third turn, and a bleeding cell left too long under a single layer
##   goes red from underneath and counts as bare again. A bad tourniquet is a harder
##   puzzle, not just a bigger number.
##   The legacy game's loose / good / tight tension is gone. This is routing, and nothing else.
##
## Result {"dressed": true, "dress_marks": "..."} -- the marks are one character a wound cell, as
## messy as the path was, for the dressing on the body to be drawn from.
##
## The board, the rules and the diagram are in wrap_snake.gd, shared with WHACK!-then-WRAP!.

const SnakeScript := preload("res://scripts/surgery/arcade/wrap_snake.gd")

const PHI := 0.6180339887498949

# -- the roll ---------------------------------------------------------------------------------
## Cells a second, before difficulty. The roll never stops.
@export_range(1.0, 14.0, 0.25) var roll_speed := 5.0
## How much bandage is on the roll, in cells. Ninety is two and a bit trips round the ring.
@export_range(20, 200) var roll_cells := 90
## Turns of bandage a dry wound cell wants. A bleeding one wants one more.
@export_range(1, 3) var layers_needed := 2
@export_range(1, 4) var layer_cap := 3
## A bleeding cell under a single layer soaks through after this long and counts as bare again.
@export_range(0.5, 10.0, 0.1) var soak_seconds := 4.5
@export_range(0.1, 3.0, 0.05) var respawn_seconds := 0.6

# -- what it costs ----------------------------------------------------------------------------
@export_range(0.0, 10.0, 0.5) var tangle_botch := 2.0
@export_range(0.0, 10.0, 0.5) var soak_botch := 2.0
## Blood only soaks through so fast: at most one bill this often.
@export_range(0.0, 10.0, 0.1) var soak_cooldown := 2.0
@export_range(0.0, 10.0, 0.5) var runout_botch := 3.0

# -- a jolt -----------------------------------------------------------------------------------
@export_range(0, 10) var jolt_cells := 3
@export_range(0.0, 10.0, 0.5) var jolt_botch := 2.0
@export_range(0.0, 5.0, 0.05) var jolt_cooldown := 0.8

# -- audio ------------------------------------------------------------------------------------
@export var turn_cue := "surgery_swish"
@export var layer_cue := "surgery_pack"
@export var tangle_cue := "surgery_tear"
@export var soak_cue := "surgery_saw_squelch"
@export var runout_cue := "surgery_forceps_clink"
@export_range(-40.0, 0.0, 1.0) var turn_volume := -20.0

# ---- replicated state ----
var snake: SnakeScript = null
var tourniquet := 1.0
var bleed_frac := 0.35
var flash := 0.0                  ## the panel going red for a moment after something went wrong

# ---- local ----
var _t := 0.0
var _soak_cd := 0.0
var _jolt_cd := 0.0
var _seen_tangles := 0
var _seen_soaks := 0
var _limb := Vector2(30.0, 19.0)  ## the stump's half size on the diagram, mm

# ---- bot ----
var _b_cell := Vector2i(-9, -9)
var _b_want := Vector2i.ZERO
var _b_seq := 0
var _b_prev_btn := 0


# ---------------------------------------------------------------------------- setup

func card_word_for_start() -> String:
	return "WRAP!"


func build_game() -> void:
	var flags: Dictionary = ctx.get("flags", {})
	var tq = flags.get("tourniquet", 1.0)
	tourniquet = (1.0 if tq else 0.0) if tq is bool else clampf(float(tq), 0.0, 1.0)
	# CARRY-FORWARD from SQUEEZE!, and it is today's formula, straight off the legacy game.
	bleed_frac = clampf(0.85 - 0.75 * tourniquet, 0.1, 0.8)
	_measure_limb()
	snake = SnakeScript.new()
	snake.base_need = layers_needed
	snake.max_layers = layer_cap
	snake.roll_max = roll_cells
	snake.speed_cells = roll_speed
	snake.soak_time = soak_seconds
	snake.respawn_time = respawn_seconds
	snake.build(int(ctx.get("seed", 1)), diff, "stump", bleed_frac, view_mm())
	_update_progress()


## The stump under the ring comes off the real limb, so Bob's forearm and the seal's flipper are
## visibly different things to dress.
func _measure_limb() -> void:
	var hs := 0.05
	var hu := 0.04
	var b = ctx.get("body")
	var site := String(ctx.get("step", {}).get("site", "limb_cut"))
	if b != null and is_instance_valid(b) and b.has_method("site_section"):
		var sec: Dictionary = b.site_section(site)
		if not sec.is_empty():
			hs = clampf(float(sec.half_side), 0.008, 0.3)
			hu = clampf(maxf(float(sec.half_up), hs * 0.6), 0.008, 0.3)
	else:
		var r := float(ctx.get("patient", {}).get("limb_radius_m", 0.05))
		hs = r
		hu = r * 0.8
	var k: float = minf(30.0 / (hs * 1000.0), 19.0 / (hu * 1000.0))
	_limb = Vector2(hs * 1000.0 * k, hu * 1000.0 * k)


# ---------------------------------------------------------------------------- playing

func keys() -> Array:
	if play_state == Play.DONE:
		return []
	return [["WASD / arrows", "steer the roll"]]


func hint() -> String:
	var base := super.hint()
	if base != "":
		return base
	if play_state == Play.DONE:
		return "Dressed."
	if snake == null:
		return ""
	if snake.respawn > 0.0:
		return "Tangled. Cutting it and starting again."
	if snake.roll_left < 12:
		return "The roll is nearly out."
	if _wet_bare() > 0:
		return "The crossed cells are still bleeding: they want another turn."
	return "Cross your own bandage only on the wound."


## Bleeding wound cells that are not covered yet. What the hint and the body's bleeding read off.
func _wet_bare() -> int:
	if snake == null:
		return 0
	var n := 0
	for w in snake.wound.size():
		if snake.bleeding[w] and not snake.satisfied(w):
			n += 1
	return n


func play(_p: Vector2, _buttons: int, edges: int, _delta: float) -> void:
	if snake == null:
		return
	# The press, not the hold: the roll keeps its heading until you give it a new one.
	var was: Vector2i = snake.want_dir
	if edges & BUTTON_UP:
		snake.steer(Vector2i(0, -1))
	elif edges & BUTTON_DOWN:
		snake.steer(Vector2i(0, 1))
	elif edges & BUTTON_LEFT:
		snake.steer(Vector2i(-1, 0))
	elif edges & BUTTON_RIGHT:
		snake.steer(Vector2i(1, 0))
	if snake.want_dir != was:
		audio(turn_cue, turn_volume, 0.2)


func advance(delta: float) -> void:
	if snake == null:
		return
	_soak_cd = maxf(0.0, _soak_cd - delta)
	_jolt_cd = maxf(0.0, _jolt_cd - delta)
	pay(snake.advance(delta))
	_update_progress()
	if snake.finished and play_state != Play.DONE:
		_done()


## The board hands back what happened; this is where it is charged for. Shared word for word with
## the pack variant's WRAP stage, which is why it lives behind one name.
func pay(events: Array) -> void:
	for e: Dictionary in events:
		match String(e.get("e", "")):
			"tangle":
				flash = 0.5
				shake(0.7)
				cost(tangle_botch, "The bandage tangled")
			"runout":
				flash = 0.3
				audio(runout_cue, -12.0, 0.1)
				cost(runout_botch, "Ran out of bandage")
			"soak":
				flash = 0.4
				if _soak_cd <= 0.0:
					_soak_cd = soak_cooldown
					cost(soak_botch, "Blood soaked through the dressing")
			"layer":
				audio(layer_cue, -17.0, 0.12)
			_:
				pass


func animate(delta: float) -> void:
	_t += delta
	flash = maxf(0.0, flash - delta * 1.6)


func _update_progress() -> void:
	progress = snake.frac() if snake != null else 0.0


func _done() -> void:
	var marks := snake.marks()
	quality = snake.quality()
	var b = body()
	if b != null:
		if b.has_method("set_bleeding"):
			b.set_bleeding(String(ctx.get("step", {}).get("site", "limb_cut")), 0.0)
		if b.has_method("apply_flags"):
			var f: Dictionary = (ctx.get("flags", {}) as Dictionary).duplicate()
			f["dressed"] = true
			f["dress_marks"] = marks
			b.apply_flags(f)
	arcade_finish({"dressed": true, "dress_marks": marks})


## A jerk pulls the last of the bandage off the stump.
func on_jolt(_offset: Vector2, strength: float, _duration: float) -> void:
	if snake == null or snake.finished or _jolt_cd > 0.0:
		return
	_jolt_cd = jolt_cooldown
	if snake.jolt(jolt_cells) > 0:
		flash = maxf(flash, 0.45)
		shake(clampf(0.5 + strength * 0.5, 0.0, 1.0))
		cost(jolt_botch, "The patient jerked and pulled the dressing loose")
		_update_progress()


# ---------------------------------------------------------------------------- the body

func react() -> void:
	if snake == null:
		return
	if snake.tangles > _seen_tangles:
		_seen_tangles = snake.tangles
		audio(tangle_cue, -6.0, 0.1)
		var bt = body()
		if bt != null and bt.has_method("stir"):
			bt.stir(0.5)
	if snake.soaks > _seen_soaks:
		_seen_soaks = snake.soaks
		audio(soak_cue, -8.0, 0.1)
	var b = body()
	if b == null or not b.has_method("set_bleeding"):
		return
	var site := String(ctx.get("step", {}).get("site", "limb_cut"))
	var open: float = float(_wet_bare()) / maxf(1.0, float(snake.wound.size()))
	var amount: float = clampf(bleed_frac * (0.25 + 0.75 * open) * (1.0 - 0.6 * snake.frac()), 0.0, 1.0)
	b.set_bleeding(site, 0.0 if play_state == Play.DONE else amount)


# ---------------------------------------------------------------------------- the diagram

func paint_game(c: CanvasItem) -> void:
	if panel == null or snake == null:
		return
	var st := style()
	_paint_stump(c, st)
	snake.paint(c, self)
	snake.paint_counters(c, self)
	if flash > 0.0:
		c.draw_rect(Rect2(Vector2.ZERO, panel.tex_size()), Color(st.danger, flash * 0.18))


## The cut end of the limb, under the ring: the section, the tourniquet band above it, and the
## bone as a pale disc so the stump reads as a stump and not as a hole in the grid.
func _paint_stump(c: CanvasItem, st: StyleScript) -> void:
	var at := Vector2(0.0, 0.0)
	var pts := PackedVector2Array()
	for i in 56:
		var a: float = TAU * float(i) / 56.0
		pts.append(px(at + Vector2(cos(a) * _limb.x, sin(a) * _limb.y)))
	c.draw_colored_polygon(pts, Color(st.blood_dark, 0.55))
	st.glow_poly(c, pts, st.line, st.hair)
	c.draw_polyline(pts, Color(st.line, 0.5), st.thin)
	var br: float = minf(_limb.x, _limb.y) * 0.34
	c.draw_circle(px(at), px_len(br), Color(st.bone, 0.24))
	c.draw_arc(px(at), px_len(br), 0.0, TAU, 24, Color(st.bone, 0.7), st.thin)
	# The tourniquet, up the limb and off the top of the board, as a reminder of who did this.
	var band: float = -_limb.y - 6.0
	var wgood: bool = tourniquet >= 0.75
	var col: Color = st.good if wgood else st.sloppy
	c.draw_line(px(Vector2(-_limb.x * 0.8, band)), px(Vector2(_limb.x * 0.8, band)), col, st.outline)
	# Hatching, so a weak tourniquet is not only a different colour.
	var ticks: int = 3 if wgood else 1
	for i in ticks:
		var y: float = band - 1.4 - 1.6 * float(i)
		c.draw_line(px(Vector2(-_limb.x * 0.55, y)), px(Vector2(_limb.x * 0.55, y)), Color(col, 0.6), st.hair)


# ---------------------------------------------------------------------------- net

func net_pack() -> Dictionary:
	# `sub`, the soak clocks and the respawn all CREEP: wrap_snake sends them raw for that reason.
	return {"sn": snake.pack() if snake != null else {}, "fl": snappedf(flash, 0.05), "bf": snappedf(bleed_frac, 0.01)}


func net_apply(s: Dictionary) -> void:
	if snake != null:
		snake.unpack(s.get("sn", {}))
		_update_progress()
	flash = float(s.get("fl", flash))
	bleed_frac = float(s.get("bf", bleed_frac))


# ---------------------------------------------------------------------------- bot

## The bot routes: breadth-first to the nearest bare cell without crossing its own bandage. A
## sloppy hand takes the wrong turning now and again, from a golden-ratio sequence rather than a
## random draw, so the same seed makes the same mess every run.
func bot_input(_t_now: float, skill: float) -> Dictionary:
	if snake == null or not armed():
		_b_prev_btn = 0
		return {"cursor": Vector2.ZERO, "buttons": 0}
	return {"cursor": Vector2.ZERO, "buttons": bot_steer(snake, clampf(skill, 0.0, 1.0))}


## Shared with the pack variant's WRAP stage.
func bot_steer(s: SnakeScript, skill: float) -> int:
	if s.cell != _b_cell:
		_b_cell = s.cell
		_b_seq += 1
		var u: float = fposmod(float(_b_seq) * PHI, 1.0)
		var want: Vector2i = s.route(s.cell, s.dir)
		if u < lerpf(0.30, 0.0, skill):
			# Missed the turning altogether and carried straight on, which is how a roll tangles.
			want = s.dir
		elif u < lerpf(0.58, 0.0, skill):
			# Or took the wrong one. It still has to be a turn it could make.
			var alt: Vector2i = Vector2i(want.y, -want.x) if u < 0.44 else Vector2i(-want.y, want.x)
			if alt != -s.dir:
				want = alt
		_b_want = want
	var btn := 0
	if _b_want != Vector2i.ZERO and _b_want != s.dir and _b_want != -s.dir:
		btn = 0 if _b_prev_btn != 0 else dir_button(_b_want)
	_b_prev_btn = btn
	return btn


static func dir_button(d: Vector2i) -> int:
	if d == Vector2i(0, -1):
		return BUTTON_UP
	if d == Vector2i(0, 1):
		return BUTTON_DOWN
	if d == Vector2i(-1, 0):
		return BUTTON_LEFT
	return BUTTON_RIGHT


# ---------------------------------------------------------------------------- self-test

## Headless check: `tools/minigame_lab.tscn -- --selftest=gauze:stump:arcade`.
## Targets: skill 1.0 finishes in 8-20 s losing 0-2 vitals; skill 0.0 under 40 s losing 15-25.
static func self_test() -> Array:
	var script: GDScript = load("res://scripts/surgery/arcade/wrap_stump_arcade.gd")
	var out := []
	var ok := true
	var sloppy: Array = []
	for cond: Dictionary in [{"tq": 0.95, "sed": 1.0}, {"tq": 0.35, "sed": 0.4}]:
		for pid: String in ["bob", "seal"]:
			for skill: float in [1.0, 0.5, 0.0]:
				var g = script.new()
				var tally := {"n": 0, "v": 0.0, "done": false, "m": "", "reasons": {}}
				g.botched.connect(func(a, r): tally.n += 1; tally.v += a; tally.reasons[r] = int(tally.reasons.get(r, 0)) + 1)
				g.finished.connect(func(r): tally.done = true; tally.m = String(r.get("dress_marks", "")))
				g.setup(_ctx(pid, float(cond.tq), float(cond.sed)))
				var t: float = run_bot(g, skill, float(cond.sed), hash(pid) + int(skill * 100))
				print("[wrap-stump self-test] %-4s skill=%.1f tq=%.2f sed=%.1f  %s  cells=%2d wet=%2d laid=%3d tangles=%d soaks=%d  time=%5.1fs  botches=%2d vitals=%5.1f  marks=%s  %s" % [
					pid, skill, cond.tq, cond.sed, "DONE" if tally.done else "UNFINISHED",
					g.snake.wound.size(), _wet(g), g.snake.trail.size(), g.snake.tangles, g.snake.soaks,
					t, tally.n, tally.v, tally.m, str(tally.reasons)])
				out.append({"patient": pid, "skill": skill, "tq": cond.tq, "done": tally.done,
					"time": t, "vitals": tally.v, "marks": tally.m})
				if float(cond.tq) > 0.9 and float(cond.sed) > 0.9:
					if skill == 1.0 and (not tally.done or t < 8.0 or t > 20.0 or tally.v > 2.0):
						print("[wrap-stump self-test] MISS: skill 1.0 wants 8-20 s and 0-2 vitals")
						ok = false
					if skill == 0.0:
						sloppy.append(tally.v)
						if not tally.done or t > 40.0:
							print("[wrap-stump self-test] MISS: skill 0.0 wants to finish under 40 s")
							ok = false
				g.free()
	# The sloppy band, on the MEAN: which cells a seeded ring happens to put the bleeders in swings
	# one patient a few vitals either side of the other on its own. saw_arcade.gd does the same.
	var mean := 0.0
	for v: float in sloppy:
		mean += v
	mean /= maxf(1.0, float(sloppy.size()))
	print("[wrap-stump self-test] skill 0.0 mean vitals %.1f across %d patients (want 15-25)" % [mean, sloppy.size()])
	if mean < 15.0 or mean > 25.0:
		print("[wrap-stump self-test] MISS: skill 0.0 wants 15-25 vitals on average")
		ok = false
	# CARRY-FORWARD: a worse tourniquet has to mean more bleeding cells to get bandage over.
	for pid: String in ["bob", "seal"]:
		var good := _wet_for(script, pid, 0.95)
		var bad := _wet_for(script, pid, 0.10)
		print("[wrap-stump self-test] %-4s tourniquet 0.95 -> %d of %d cells bleeding;  0.10 -> %d of %d" % [
			pid, good[0], good[1], bad[0], bad[1]])
		out.append({"patient": pid, "wet_good_tq": good[0], "wet_bad_tq": bad[0]})
		if bad[0] <= good[0]:
			print("[wrap-stump self-test] MISS: a worse tourniquet should leave more cells bleeding")
			ok = false
	# Onlookers and hand-over: a spectator tracks the operator off the replicated state alone, and
	# somebody else picking the roll up mid-dressing gets the READY countdown and finishes it.
	var net := _net_check(script)
	print("[wrap-stump self-test] spectator drift %.4f;  hand-over READY %s, mashed through it for %.3f progress, finished %s at %.1fs" % [
		net.drift, "yes" if net.ready else "NO", net.mashed, "yes" if net.done else "NO", net.time])
	out.append(net)
	if net.drift > 0.02 or not net.ready or net.mashed > 0.001 or not net.done:
		print("[wrap-stump self-test] MISS: a spectator must track the operator, and a hand-over must count down first")
		ok = false
	print("[wrap-stump self-test] %s" % ("PASS" if ok else "FAIL"))
	return out


## Player A dresses half the stump with player B watching, A walks off, B picks it up. B must have
## tracked A exactly the whole time, must get the countdown rather than a roll already moving, and
## mashing the keys during the countdown must not steer anything.
static func _net_check(script: GDScript) -> Dictionary:
	var a = script.new()
	a.setup(_ctx("bob", 0.6, 1.0))
	var b = script.new()
	var cb: Dictionary = _ctx("bob", 0.6, 1.0)
	cb["operator"] = false
	b.setup(cb)
	var dt := 1.0 / 60.0
	var t := 0.0
	var drift := 0.0
	var ready := false
	var mashed := 0.0
	var at_hand := -1.0
	var phase := 0
	while t < 70.0 and not b.done and not a.done:
		t += dt
		if phase == 0:
			var inp: Dictionary = a.bot_input(t, 1.0)
			a.handle_cursor(inp.get("cursor", Vector2.ZERO), int(inp.get("buttons", 0)), dt)
			a.tick(dt)
			b.apply_net_state(a.net_state())
			b.tick(dt)
			drift = maxf(drift, absf(a.progress - b.progress))
			if a.progress > 0.45:
				phase = 1
				a.ctx["operating"] = false
				b.ctx["operating"] = false
		elif phase == 1:
			# Nobody at the table. Both frozen, and the board must not move.
			a.tick(dt)
			b.apply_net_state(a.net_state())
			b.tick(dt)
			if t > 0.0:
				phase = 2
				b.ctx["operating"] = true
				b.ctx["operator"] = true
				at_hand = b.progress
		else:
			# B mashes every direction through the countdown, then plays it out.
			var counting: bool = b.play_state == b.Play.READY
			if counting:
				ready = true
				b.handle_cursor(Vector2.ZERO, BUTTON_UP | BUTTON_LEFT | BUTTON_DOWN, dt)
				b.tick(dt)
				mashed = maxf(mashed, absf(b.progress - at_hand))
				continue
			var inp2: Dictionary = b.bot_input(t, 1.0)
			b.handle_cursor(inp2.get("cursor", Vector2.ZERO), int(inp2.get("buttons", 0)), dt)
			b.tick(dt)
	var r := {"drift": snappedf(drift, 0.0001), "ready": ready, "mashed": snappedf(mashed, 0.0001),
		"done": bool(b.done), "time": t}
	a.free()
	b.free()
	return r


static func _ctx(pid: String, tq: float, sed: float) -> Dictionary:
	return {"patient_id": pid, "patient": Procedures.patient(pid), "ailment_id": "amputation",
		"step": Procedures.step("amputation", 3), "variant": "stump", "shift": 1,
		"difficulty": Procedures.difficulty(1),
		"flags": {"tourniquet": tq, "sedation": sed, "amputated": true},
		"seed": hash("wrapstump" + pid), "body": null, "operator": true, "operating": true}


static func _wet(g) -> int:
	var n := 0
	for w in g.snake.wound.size():
		if g.snake.bleeding[w]:
			n += 1
	return n


static func _wet_for(script: GDScript, pid: String, tq: float) -> Array:
	var g = script.new()
	g.setup(_ctx(pid, tq, 1.0))
	var r := [_wet(g), g.snake.wound.size()]
	g.free()
	return r
