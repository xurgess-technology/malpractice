extends "res://scripts/surgery/arcade/arcade_game.gd"
## ARCADE SURGERY -- WRAP!, the stump. Step "dress" of an amputation (`gauze` x2, variant `stump`,
## site `limb_cut`). THE SAME WRAP! the gunshot wound gets: the rules, the board and the drawing are
## wrap_roll.gd, shared with pack_wrap_arcade.gd and specified in docs/PACK_AND_WRAP_SPEC.md section 3.
## This file is only the stump's half of it -- what feeds the board, and what the page says.
##
## ONE VERSION PER GAME. The bespoke stump Snake that used to live here (a ring of cells round the cut
## end, a depleting ninety-cell roll, timed soak-through, a tension rule) is gone, along with
## wrap_snake.gd underneath it. There is now one WRAP!, played the same way wherever you meet it.
##
## CARRY-FORWARD IN: `flags.tourniquet` from SQUEEZE!. Whatever the tourniquet did not stop is still
## bleeding, so it decides how many cells want a SECOND layer -- exactly the slot pack quality fills on
## the gunshot wound, off the same formula the legacy stump step used:
##     bleedCells share = clamp(0.85 - 0.75 x tourniquet, 0.1, 0.8)
## A bad tourniquet is a harder routing puzzle, not just a bigger number.
## CARRY-FORWARD OUT: {"dressed": true, "dress_marks": s} -- one character a wound cell, the contract
## this step has always finished with. There is no `pack_quality`: nothing packed anything here.
##
## Space: the same 960 x 600 reference px ("rpx") the rest of the clipboard steps are laid out on.

const RollScript := preload("res://scripts/surgery/arcade/wrap_roll.gd")

const REF := Vector2(960.0, 600.0)

enum Stage { WRAP, RESULT }

@export_group("Wrap")
## SPEC 5 TUNING KNOB "snakeRate": 0.16 s per cell (0.08-0.3). Divided by the difficulty factor.
@export_range(0.08, 0.3, 0.005) var snake_rate := 0.16
## SPEC 5: gauze in hand when it begins.
@export_range(0, 6) var start_carry := 1
@export_range(4, 60) var blob_cells := 14
@export_range(0.1, 1.0, 0.01) var branch_chance := 0.62
## What a tangle costs (spec 3.2).
@export_range(0.0, 20.0, 0.5) var tangle_cost := 5.0

@export_group("Results")
## Score = tourniquet x this + coverage% x `score_cover` - tangles x `score_tangle`, clamped 0-100.
## The tourniquet stands where the gunshot wound's pack quality stands: the step before this one.
@export_range(0.0, 100.0, 1.0) var score_pack := 45.0
@export_range(0.0, 2.0, 0.01) var score_cover := 0.45
@export_range(0.0, 40.0, 0.5) var score_tangle := 6.0
@export_range(0, 100) var grade_clean := 80
@export_range(0, 100) var grade_sloppy := 48
@export_range(0.0, 5.0, 0.1) var result_lock := 1.4
## Bigger than the shell's instruction cards: it holds three lines of numbers as well as the grade.
@export var result_card_size := Vector2(600.0, 232.0)

@export_group("Difficulty")
@export_range(0.0, 2.0, 0.05) var difficulty_gain := 0.5

@export_group("Audio")
@export var tangle_cue := "surgery_tear"
@export var layer_cue := "surgery_pack"
@export var eat_cue := "surgery_click"
@export_group("")

# ---- replicated ----
var stage: int = Stage.WRAP
var roll: RollScript = null
var tourniquet := 1.0
var bleed_frac := 0.35
var score := 0
var _grade := ""

# ---- local ----
var grime_spots: Array = []
var _rng := RandomNumberGenerator.new()
var _seen := {}
var _warm := false

# ---- bot ----
var _bt := 0.0
var _b_gate := -1.0
var _b_up := false


# ---------------------------------------------------------------------------- setup

func use_ink() -> bool:
	return true


func ink_unit() -> float:
	return _u()


func card_word_for_start() -> String:
	return "WRAP!"


func build_game() -> void:
	if ink != null:
		ink.content = Rect2(Vector2(0.0, _top()), REF * _u())
	var seed_v := int(ctx.get("seed", 1))
	_rng.seed = hash("wrap_stump|%d" % seed_v)
	var flags = ctx.get("flags", {})
	var tq = (flags as Dictionary).get("tourniquet", 1.0) if flags is Dictionary else 1.0
	tourniquet = (1.0 if tq else 0.0) if tq is bool else clampf(float(tq), 0.0, 1.0)
	# CARRY-FORWARD from SQUEEZE!, on the formula the legacy stump step used.
	bleed_frac = clampf(0.85 - 0.75 * tourniquet, 0.1, 0.8)
	grime_spots = InkScript.make_grime(_rng, Rect2(Vector2(40, 60), panel.tex_size() - Vector2(80, 120)))
	_build_roll()
	_update_progress()


func dk() -> float:
	return pow(maxf(0.5, diff), difficulty_gain)


func _build_roll() -> void:
	roll = RollScript.new()
	roll.blob_cells = blob_cells
	roll.branch_chance = branch_chance
	roll.start_carry = start_carry
	roll.step_time = maxf(0.02, snake_rate / dk())
	roll.tangle_cost = tangle_cost
	roll.build(int(ctx.get("seed", 1)), "stump", bleed_frac)


# ---------------------------------------------------------------------------- space

func _u() -> float:
	return (panel.tex_size().x if panel != null else 1200.0) / REF.x


func _top() -> float:
	return ((panel.tex_size().y if panel != null else 800.0) - REF.y * _u()) * 0.5


func cv(p: Vector2) -> Vector2:
	return Vector2(p.x * _u(), p.y * _u() + _top())


func cl(v: float) -> float:
	return v * _u()


# ---------------------------------------------------------------------------- the cards and the HUD

func stamp_for(word: String) -> Dictionary:
	var I := ink
	match word:
		"WRAP!":
			var lines := ["WASD to steer. Gauze lengthens the roll; laying a layer spends it."]
			var bleed := _bleed_cells()
			if bleed > 0:
				lines.append("The tourniquet missed %d cells: they are still bleeding and want two layers." % bleed)
			else:
				lines.append("A clean tourniquet, so one layer covers it. Don't drive into your own tail.")
			return {"goal": "Dress the stump: bandage over every cell.", "lines": lines,
				"prompt": "SPACE to start", "color": I.ink if I != null else Color.BLACK}
		"CLEAN", "SLOPPY", "MALPRACTICE":
			return {"goal": _flavour(word), "lines": _result_lines(),
				"prompt": "SPACE to finish", "wait": "Look at it...",
				"color": (I.good if word == "CLEAN" else I.deep_red) if I != null else Color.BLACK}
	return {"prompt": "SPACE"}


func _result_lines() -> Array:
	return [
		"Tourniquet %d%%   ·   bleeding cells %d" % [int(round(tourniquet * 100.0)), _bleed_cells()],
		"Stump covered %d%%   ·   tangles %d   ·   vitals %d" % [
			int(round(coverage() * 100.0)), tangles(), int(round(vitals_lost()))],
		"SCORE %d" % score,
	]


func _flavour(grade: String) -> String:
	match grade:
		"CLEAN":
			return "Neat, dry, and it will still be on in the morning."
		"SLOPPY":
			return "It'll hold. Keep the limb elevated and the lights low."
	return "You have wrapped a stump the way one wraps a sandwich."


func hud_line() -> String:
	if stage == Stage.WRAP:
		return "WASD: steer the roll\nGauze lengthens it, a layer spends it"
	return ""


func hud_value() -> Array:
	if stage == Stage.WRAP:
		return ["STUMP %d%%" % int(round(coverage() * 100.0)), _bleed_open() > 0]
	return ["SCORE %d" % score, _grade == "MALPRACTICE"]


func keys() -> Array:
	if stage == Stage.WRAP:
		return [["WASD", "steer"], ["Gauze", "lengthens the roll"]]
	return []


func hint() -> String:
	if stamp_waiting():
		if card_word == "WRAP!":
			return "The limb is off. Dress what is left of it."
		return "Done. Space to finish."
	var base := super.hint()
	if base != "":
		return base
	if stage == Stage.WRAP:
		if roll != null and roll.carry() <= 0:
			return "Empty-handed. Go and pick up gauze."
		return "Lay a layer on every cell. The crossed ones want two."
	return ""


# ---------------------------------------------------------------------------- playing

func play(_p_mm: Vector2, buttons: int, _edges: int, _delta: float) -> void:
	match stage:
		Stage.WRAP:
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
		Stage.RESULT:
			# The press that took the results card down is the stage's one action.
			_finish_step()


func advance(delta: float) -> void:
	if stage != Stage.WRAP or roll == null:
		return
	for e in roll.advance(delta):
		match String(e.get("e", "")):
			"tangle":
				mistake("TANGLE!", tangle_cost, "Tangled the bandage", "tangle",
					cv(e.get("at", Vector2.ZERO)), true)
			"done":
				_to_result()
	_update_progress()


func _to_result() -> void:
	score = grade_score()
	_grade = grade_word()
	stage = Stage.RESULT
	# The last card of the step, so nothing has to be put back.
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
			b.set_bleeding(String(ctx.get("step", {}).get("site", "limb_cut")), 0.0)
		if b.has_method("apply_flags"):
			var f: Dictionary = (ctx.get("flags", {}) as Dictionary).duplicate()
			f["dressed"] = true
			f["dress_marks"] = marks
			b.apply_flags(f)
	arcade_finish({"dressed": true, "dress_marks": marks})


# ---------------------------------------------------------------------------- the grade

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


## The gunshot wound's formula with the tourniquet standing in for pack quality (spec 4).
func grade_score() -> int:
	var s: float = tourniquet * score_pack + coverage() * 100.0 * score_cover - float(tangles()) * score_tangle
	return clampi(int(round(s)), 0, 100)


func grade_word() -> String:
	var s := grade_score()
	if s >= grade_clean:
		return "CLEAN"
	if s >= grade_sloppy:
		return "SLOPPY"
	return "MALPRACTICE"


func _update_progress() -> void:
	progress = 1.0 if stage != Stage.WRAP else coverage()


# ---------------------------------------------------------------------------- sound and the body

func react() -> void:
	var now := {"lay": roll.laid if roll != null else 0, "eat": roll.eaten if roll != null else 0,
		"tg": tangles()}
	if _seen.is_empty():
		_seen = now
		return
	if int(now.lay) > int(_seen.lay):
		audio(layer_cue, -10.0, 0.15)
	if int(now.eat) > int(_seen.eat):
		audio(eat_cue, -16.0, 0.1)
	if int(now.tg) > int(_seen.tg):
		audio(tangle_cue, -6.0, 0.1)
	_seen = now
	var b = body()
	if b != null and b.has_method("set_bleeding") and play_state != Play.DONE:
		var site := String(ctx.get("step", {}).get("site", "limb_cut"))
		b.set_bleeding(site, clampf(bleed_frac * (1.0 - coverage()), 0.0, 1.0))


# ---------------------------------------------------------------------------- the page

func paint_game(c: CanvasItem) -> void:
	if panel == null or ink == null or roll == null:
		return
	ink.draw_grime(c, grime_spots)
	roll.paint(c, self)
	_paint_strip(c)
	if _warm:
		ink.warm(c)
		c.draw_string(InkScript.font_upright(), Vector2(-100, -100), "WRAP! TANGLE! CLEAN SLOPPY MALPRACTICE",
			HORIZONTAL_ALIGNMENT_LEFT, -1.0, 110, ink.ink)


func _paint_strip(c: CanvasItem) -> void:
	var txt := "covered %d%%   ·   in hand %d   ·   tangles %d   ·   tourniquet %d%%" % [
		int(round(coverage() * 100.0)), roll.carry(), tangles(), int(round(tourniquet * 100.0))]
	ink.text(c, cv(Vector2(REF.x * 0.5, REF.y - 18.0)), txt, 14.0, Color(ink.label, 0.9), 1)


func warm_all() -> void:
	_warm = true
	if roll != null and roll.wound.size() > 0:
		roll.layers[0] = 1
	score = 61
	_grade = "SLOPPY"
	if shell != null:
		shell.mistake("TANGLE!", shell.area.get_center(), true, 0)
	if panel != null:
		panel.redraw()


# ---------------------------------------------------------------------------- net

func net_pack() -> Dictionary:
	var s := {"st": stage, "tq": tourniquet, "bf": bleed_frac, "sc": score, "gr": _grade}
	if roll != null:
		s["rl"] = roll.pack()
	return s


func net_apply(s: Dictionary) -> void:
	stage = int(s.get("st", stage))
	tourniquet = float(s.get("tq", tourniquet))
	bleed_frac = float(s.get("bf", bleed_frac))
	score = int(s.get("sc", score))
	_grade = String(s.get("gr", _grade))
	if roll == null:
		_build_roll()
	if roll != null and s.has("rl"):
		roll.unpack(s.get("rl", {}))
	_update_progress()


# ---------------------------------------------------------------------------- bot

func bot_input(t: float, skill: float) -> Dictionary:
	var dt: float = clampf(t - _bt, 0.0, 0.1)
	_bt = t
	skill = clampf(skill, 0.0, 1.0)
	var none := {"cursor": Vector2.ZERO, "buttons": 0}
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
			return {"cursor": Vector2.ZERO, "buttons": BUTTON_ACTION}
		return none
	if not armed():
		return none
	if _b_up:
		_b_up = false
		return none
	if stage == Stage.RESULT:
		return {"cursor": Vector2.ZERO, "buttons": BUTTON_ACTION}
	if roll == null:
		return none
	var d: Vector2i = roll.route()
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
	return {"cursor": Vector2.ZERO, "buttons": bit}


# ---------------------------------------------------------------------------- self-test

## Headless: `godot --headless --path . --fixed-fps 60 tools/minigame_lab.tscn -- --selftest=gauze:arcade`
## with `--variant=stump`, or through the lab's `--game=gauze --variant=stump --bot=1`.
static func self_test() -> Array:
	var script: GDScript = load("res://scripts/surgery/arcade/wrap_stump_arcade.gd")
	var out := []
	var ok := true
	for tq: float in [0.95, 0.4]:
		for pid: String in ["bob", "seal"]:
			for skill: float in [1.0, 0.5, 0.0]:
				var g = script.new()
				var tally := {"n": 0, "v": 0.0, "done": false, "m": ""}
				g.botched.connect(func(a, _r): tally.n += 1; tally.v += a)
				g.finished.connect(func(r): tally.done = true; tally.m = String(r.get("dress_marks", "")))
				g.setup(_case(pid, tq))
				var t: float = run_bot(g, skill, 1.0, hash(pid) + int(skill * 100), 240.0)
				print("[wrap-stump self-test] %-4s skill=%.1f tq=%.2f  %s  cells=%d bleeding=%d cover=%.2f tangles=%d  score=%3d %-11s  time=%5.1fs vitals=%5.1f" % [
					pid, skill, tq, "DONE" if tally.done else "UNFINISHED", g.roll.wound.size(),
					g._bleed_cells(), g.coverage(), g.tangles(), g.score, g._grade, t, tally.v])
				out.append({"patient": pid, "skill": skill, "tq": tq, "done": tally.done, "time": t,
					"score": g.score, "tangles": g.tangles()})
				if not tally.done:
					print("[wrap-stump self-test] MISS: every hand has to be able to finish")
					ok = false
				elif tally.m.length() != g.roll.wound.size():
					print("[wrap-stump self-test] MISS: dress_marks is one character per wound cell")
					ok = false
				if absf(tally.v - 5.0 * float(g.tangles())) > 0.01:
					print("[wrap-stump self-test] MISS: a tangle costs 5 vitals and nothing else bills")
					ok = false
				g.free()
	# A worse tourniquet must mean more work, never less.
	var good = script.new()
	good.setup(_case("bob", 0.95))
	var bad = script.new()
	bad.setup(_case("bob", 0.2))
	print("[wrap-stump self-test] carry-forward: tourniquet 0.95 -> %d bleeding of %d (%d layers), 0.20 -> %d of %d (%d layers)" % [
		good._bleed_cells(), good.roll.wound.size(), good.roll.total_need(),
		bad._bleed_cells(), bad.roll.wound.size(), bad.roll.total_need()])
	if bad._bleed_cells() <= good._bleed_cells() or bad.roll.total_need() <= good.roll.total_need():
		print("[wrap-stump self-test] MISS: a worse tourniquet must never mean less work")
		ok = false
	good.free()
	bad.free()
	print("[wrap-stump self-test] %s" % ("PASS" if ok else "FAIL"))
	return out


static func _case(pid: String, tq: float) -> Dictionary:
	return {"patient_id": pid, "patient": Procedures.patient(pid), "ailment_id": "amputation",
		"step": Procedures.step("amputation", 3), "variant": "stump", "shift": 1,
		"difficulty": Procedures.difficulty(1),
		"flags": {"sedation": 1.0, "tourniquet": tq, "amputated": true},
		"seed": hash("wrapstump" + pid), "body": null, "operator": true, "operating": true}
