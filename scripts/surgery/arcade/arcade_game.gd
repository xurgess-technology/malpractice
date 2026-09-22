extends "res://scripts/surgery/minigame.gd"
## ARCADE SURGERY (docs/ARCADE_SURGERY.md): the shared frame every arcade step is built on.
##
## The hospital's surgical-assist machine runs bootleg arcade software. Each step is a short
## self-contained minigame that RHYMES with the procedure rather than simulating it, played on the
## raised SurgeryPanel (docs/PANEL_STYLE.md). This class owns everything they share, so a game only
## has to write its own rules and its own diagram.
##
## THE PANEL IS THE INPUT SURFACE, THE BODY IS THE CONSEQUENCE SURFACE. Flinches, blood on the gown,
## the wound overlay, the monitor and the noise that draws monsters all stay on the real patient
## through the existing calls.
##
## What it provides
##   - the panel, its diagram-millimetre space and its palette
##   - the COMMAND CARD: a one-word order in big type when a stage begins. Play starts when it
##     clears, so nobody is ever judged on a frame they could not see.
##   - FREEZE / RESUME: step away and the game stops dead and goes into `ms`; whoever picks it up
##     gets a READY countdown before it starts again. Real-time games need this or a hand-off is a
##     free failure.
##   - the panel shake, a `quality` convention, and the audio hooks.
##
## What a game must write
##   card_word() / stage_word(), paint_game(c), play(p, buttons, edges, delta), advance(delta),
##   net_pack() / net_apply(s), react(), bot_input(), self_test().

const PanelScript := preload("res://scripts/surgery/panel/surgery_panel.gd")
const StyleScript := preload("res://scripts/surgery/panel/panel_style.gd")
const InkScript := preload("res://scripts/surgery/panel/ink.gd")
const ShellScript := preload("res://scripts/surgery/panel/shell.gd")

## A mistake on a game with the shell (see mistake()): `kind` names it for audio, co-op reactions or
## a future monitor, `word` is the burst on the page. Emitted on the operator's machine.
signal mistake_made(kind: String, word: String)

# -- the panel --------------------------------------------------------------------------------
## How much of the view's height the panel fills. The rest is the real patient, table and room.
@export_range(0.3, 1.0, 0.01) var view_fill := 0.78
## How far the operator's camera is pulled back from straight over the site, in degrees.
@export_range(0.0, 60.0, 1.0) var view_tilt_deg := 32.0
@export_range(20.0, 90.0, 1.0) var view_fov := 50.0

# -- the command card -------------------------------------------------------------------------
## The one-word order at the start of a stage. Nothing is judged until it has cleared.
@export_range(0.1, 2.0, 0.05) var card_time := 0.5
## And the countdown whoever takes the machine over gets before it unfreezes.
@export_range(0.2, 3.0, 0.05) var ready_time := 1.0
@export_range(20, 200) var card_size := 110
@export_range(14, 90) var ready_size := 64

# -- audio hooks ------------------------------------------------------------------------------
## Cue names (scripts/audio autoload). Empty means silence.
@export var card_cue := "surgery_click"
@export var ready_cue := "surgery_beep"
@export var done_cue := "surgery_done"

enum Play { CARD, RUNNING, READY, DONE }

## What the game is doing right now. CARD and READY are the two "not yet" states.
var play_state: int = Play.CARD
## Seconds left of the card or the countdown.
var card_left := 0.0
## The word on the card. Set it with `show_card()`.
var card_word := ""
## 0..1, how well the step was done. Games set it; the result usually carries it.
var quality := 1.0
## Seconds of play so far, not counting cards, countdowns or being frozen.
var play_t := 0.0
## True while nobody is at the table: the game is stopped dead and its state is in `ms`.
var frozen := false

var diff := 1.0
var panel: PanelScript = null
## The ink/paper look (scripts/surgery/panel/ink.gd), for a game whose use_ink() is true; null on the
## teal look. The page, its border and the command card come from it.
var ink: InkScript = null
var _ink_t := 0.0
## The shared surgery shell (scripts/surgery/panel/shell.gd): stamp cards, the corner HUD, bursts,
## blood and the shake. Built with the ink look; null on the teal look.
var shell: ShellScript = null
## Mistakes so far and the last one's burst (replicated, so onlookers get the same bursts and splats).
var mistakes := 0
var mistake_word := ""
var mistake_at := Vector2(-1, -1)
var mistake_serious := false
var _mistakes_seen := 0
## Bursts without blood so far (burst()), replicated the same way.
var bursts := 0
var burst_word := ""
var burst_at := Vector2(-1, -1)
var burst_serious := false
var _bursts_seen := 0
## Seconds the current stamp card has been up (for its pop).
var _card_up := 0.0

var _was_operating := false


# ---------------------------------------------------------------------------- setup

func setup(context: Dictionary) -> void:
	super.setup(context)
	diff = maxf(0.5, float(ctx.get("difficulty", 1.0)))
	panel = PanelScript.new()
	panel.painter = _paint
	panel.header = panel_header()
	if use_ink():
		ink = InkScript.new()
		ink.unit = ink_unit()
		panel.chrome = false
		panel.transparent = true
		panel.style.glow_light = ink_glow
		panel.brightness = ink_brightness
	add_child(panel)
	build_game()
	if ink != null:
		shell = ShellScript.new(ink)
		shell.area = ink._content(panel.tex_size())
		shell.seed_v = int(ctx.get("seed", 1))
	show_card(card_word_for_start())


## True for a game drawn in the ink/paper comic look (docs/PANEL_STYLE.md) instead of the teal
## diagram. Override.
func use_ink() -> bool:
	return false


## The word on the ink look's clip: the step's id ("SEDATE").
func clip_title() -> String:
	return String(ctx.get("step", {}).get("id", "")).to_upper()


## Canvas pixels per reference pixel, for a game on the ink look laid out on its own reference size.
func ink_unit() -> float:
	return 1.0


## The ink look's warm lamp on the patient, and how bright the paper is on the quad: paper at full
## brightness is the brightest thing in a dark OR.
@export var ink_glow := Color(1.0, 0.9, 0.74)
@export_range(0.2, 2.0, 0.01) var ink_brightness := 0.82


## The step's own setup, after the panel exists. Override.
func build_game() -> void:
	pass


## "AM / CUT" in the panel's top-left corner.
func panel_header() -> String:
	var code := String(Procedures.ailment(String(ctx.get("ailment_id", ""))).get("code", ""))
	return "%s / %s" % [code, String(ctx.get("step", {}).get("id", "")).to_upper()]


## The word on the first command card. Override, e.g. "SAW!".
func card_word_for_start() -> String:
	return ""


func style() -> StyleScript:
	return panel.style


# ---------------------------------------------------------------------------- the framework

func uses_panel() -> bool:
	return true


func plane_extent() -> Vector2:
	return panel.half_size() if panel != null else Vector2(0.26, 0.174)


func input_plane() -> Transform3D:
	return panel.input_plane() if panel != null else global_transform


func lamp_scale() -> float:
	return float(panel.lamp_scale) if panel != null else 1.0


func camera_pose() -> Dictionary:
	var lift: float = float(panel.panel_lift) if panel != null else 0.24
	var h: float = float(panel.panel_size.y) if panel != null else 0.3467
	var d: float = (h / maxf(0.1, view_fill)) * 0.5 / tan(deg_to_rad(view_fov) * 0.5)
	var tilt := deg_to_rad(view_tilt_deg)
	return {"height": lift + d * cos(tilt), "back": d * sin(tilt), "fov": view_fov, "look": lift}


## Diagram millimetres (origin at the panel's centre, +y down) to panel pixels.
func px(mm: Vector2) -> Vector2:
	return panel.mm_to_px(mm)


func px_len(mm: float) -> float:
	return panel.mm_len_px(mm)


## The framework's cursor (panel metres) as diagram millimetres.
func mm_of(p: Vector2) -> Vector2:
	return panel.mm_of(p)


func view_mm() -> Vector2:
	return panel.view_mm if panel != null else Vector2(120.0, 80.0)


# ---------------------------------------------------------------------------- the command card

## Put a one-word order up. Play stops until it clears.
##
## With the shell (the ink look) the card is a STAMP CARD instead: it stays up over the live game until
## the player presses the action key, Enter or a mouse button, and that press is the first action of
## the stage (Enter only dismisses). `seconds` (or the card's own "lock") is a lockout first, counted
## down on the card: an interruption the player has to take in before going on.
func show_card(word: String, seconds := -1.0) -> void:
	if word == "":
		return
	card_word = word
	play_state = Play.CARD
	_card_up = 0.0
	if shell != null:
		card_left = seconds if seconds >= 0.0 else float(stamp_for(word).get("lock", 0.0))
		return
	card_left = card_time if seconds < 0.0 else seconds


## A stamp card's text for `word`: {goal, lines: Array, prompt, color, lock, wait}. Worked out from the
## word alone, so an onlooker (who only gets the word) draws the same card. Override.
func stamp_for(_word: String) -> Dictionary:
	return {"prompt": "SPACE"}


## The stamp card to show right now, for the surgery HUD's fixed overlay (surgery_hud.gd): `{shout,
## card: Dictionary, lock_left, k}`, or `{}` when none is up. Only ever non-empty with the shell.
func stamp_card() -> Dictionary:
	if shell == null or card_word == "":
		return {}
	if play_state == Play.READY:
		return {"shout": "READY", "card": {"prompt": "", "wait": "Taking over in", "color": ink.good},
			"lock_left": card_left, "k": _card_up}
	return {"shout": card_word, "card": stamp_for(card_word), "lock_left": card_left, "k": _card_up}


## The mouse and key bits that take a stamp card down.
const DISMISS_BITS := 1 | 64 | 512   # BUTTON_PRIMARY | BUTTON_ACTION | BUTTON_ENTER


## True while a stamp card is up and waiting for its press (every machine: it is in the state blob).
func stamp_waiting() -> bool:
	return shell != null and play_state == Play.CARD


## True while the game is actually being played: not on a card, not counting down, not frozen.
func armed() -> bool:
	return play_state == Play.RUNNING and not frozen


# ---------------------------------------------------------------------------- input and frame

## The operator's input. Games override `play()`; this handles the card, the countdown and the
## freeze so no game has to.
func handle_cursor(p: Vector2, buttons: int, delta: float) -> void:
	var edges := pressed_edges(buttons)
	if stamp_waiting() and not frozen:
		if card_left > 0.0 or (edges & DISMISS_BITS) == 0:
			return
		# The press that takes the card down is the stage's first action (Enter only dismisses).
		play_state = Play.RUNNING
		card_word = ""
		edges &= ~BUTTON_ENTER
	if not armed():
		return
	play_t += delta
	play(mm_of(p), buttons, edges, delta)


## Operator only, and only while the game is really running. `p` is in diagram millimetres and
## `edges` is the bits that went down this frame. Override.
func play(_p: Vector2, _buttons: int, _edges: int, _delta: float) -> void:
	pass


## Every machine, every frame, whether or not anyone is operating: the panel, the cards, the
## countdown, then the game's own animation.
func tick(delta: float) -> void:
	var operating: bool = bool(ctx.get("operating", ctx.get("operator", false)))
	_freeze_check(operating)
	_card_up += delta
	if play_state == Play.CARD or play_state == Play.READY:
		if not frozen or play_state == Play.READY:
			card_left = maxf(0.0, card_left - delta)
		# A stamp card waits for its press; the plain card and READY clear themselves.
		if card_left <= 0.0 and not stamp_waiting():
			play_state = Play.RUNNING
			card_word = ""
	if shell != null:
		shell.tick(delta)
		# Mistakes an onlooker has only heard about through the state blob.
		while _mistakes_seen < mistakes:
			shell.mistake(mistake_word, mistake_at, mistake_serious, _mistakes_seen)
			_mistakes_seen += 1
		while _bursts_seen < bursts:
			shell.burst(burst_word, burst_at, burst_serious, _bursts_seen)
			_bursts_seen += 1
	# The operator is the authority: only their machine simulates, so a botch is never counted
	# twice. Everyone else animates from the replicated state and is corrected 20 times a second.
	if armed() and bool(ctx.get("operator", false)):
		advance(delta)
	_ink_t += delta
	animate(delta)
	react()
	_panel_frame(delta, operating)


## Time passing in the game world while it is running: countdowns, bleeding, scrolling. Runs on the
## OPERATOR'S machine only, because it is what decides botches and completion. Override.
func advance(_delta: float) -> void:
	pass


## Animation that runs even while frozen or on a card -- smoothing, spectators catching up.
## Override.
func animate(_delta: float) -> void:
	pass


## Sounds and the body's reactions, on every machine, from the replicated state. Override.
func react() -> void:
	pass


## Stepping away stops the game dead. Whoever picks it up gets a countdown first, so a hand-off in
## the middle of a real-time game is not a free failure.
func _freeze_check(operating: bool) -> void:
	# Straight off whether anybody is at the table, not off an edge: a game built while the table is
	# empty (a spectator joining mid-step) must start out frozen, not running on its own.
	frozen = not operating
	if operating == _was_operating:
		return
	_was_operating = operating
	# Arriving at a step somebody else already started: a countdown before it moves again. `play_t`
	# comes across in the state blob, so a fresh step gets no countdown and a resumed one does.
	if operating and play_state == Play.RUNNING and play_t > 0.05:
		card_word = "READY"
		card_left = ready_time
		play_state = Play.READY


func _panel_frame(delta: float, operating: bool) -> void:
	if panel == null or not is_instance_valid(panel):
		return
	var want: bool = operating and play_state != Play.DONE
	if want and not panel.is_open():
		var pose := camera_pose()
		panel.right_text = "TABLE %d" % (int(ctx.get("table", 0)) + 1)
		panel.open(Vector3(0.0, float(pose.height), float(pose.back)))
	elif not want and panel.is_open():
		panel.close()
	panel.tick(delta)


## Charge the patient for a mistake. Guarded: only the operator's machine may, so a spectator
## running the same animation never doubles the bill.
func cost(amount: float, reason: String) -> void:
	if bool(ctx.get("operator", false)) and not bool(ctx.get("no_fail", false)):
		botch(amount, reason)


## Rattle the panel (a jolt, a bound blade). 0..1.
func shake(strength: float) -> void:
	if panel != null and is_instance_valid(panel):
		panel.shake(strength)


## Clear the panel for a moment so the patient can be seen through it.
func ghost(seconds: float) -> void:
	if panel != null and is_instance_valid(panel):
		panel.ghost(seconds)


# ---------------------------------------------------------------------------- drawing

## The panel's painter: the game's diagram, then anything it queued on top, then the card.
## Profiling (the lab's --fps): microseconds spent in the painter since the last read, and how many
## paints that was. Reading resets them.
var paint_usec := 0
var paint_count := 0


func take_paint_stats() -> Array:
	var r := [paint_usec, paint_count]
	paint_usec = 0
	paint_count = 0
	return r


func _paint(c: CanvasItem) -> void:
	var t0 := Time.get_ticks_usec()
	_paint_inner(c)
	paint_usec += Time.get_ticks_usec() - t0
	paint_count += 1


func _paint_inner(c: CanvasItem) -> void:
	if panel == null:
		return
	if ink != null:
		var size: Vector2 = panel.tex_size()
		ink.t = _ink_t
		var sh: Vector2 = shell.shake_offset() if shell != null else Vector2.ZERO
		ink.begin_page(c, size, sh)
		if shell != null:
			shell._page_xf_now = Transform2D().translated(sh) * ink.page_transform(size)
			shell.draw_splats(c)
		paint_game(c)
		if shell != null:
			var hv: Array = hud_value()
			shell.draw_hud(c, hud_line(), String(hv[0]) if hv.size() > 0 else "", bool(hv[1]) if hv.size() > 1 else false)
			var ec: Dictionary = enter_cap()
			if not ec.is_empty():
				shell.draw_enter(c, ec.at, String(ec.get("label", "")), bool(ec.get("ready", false)))
			shell.draw_fx(c)
			# The stamp card itself is NOT drawn here any more (2026-09-22): it used to ride the
			# panel's own page transform, so it landed somewhere different depending on the step's
			# site. surgery_hud.gd's fixed overlay draws it instead, from stamp_card() below, always
			# in the same screen spot in front of the patient.
		# The step's name goes on the clip, the table small in the board's corner.
		ink.end_page(c, size, clip_title(), panel.right_text, sh)
		return
	paint_game(c)
	if card_word != "":
		_paint_card(c)


## The shell's corner HUD: the controls for what you are doing now (top left). Override.
func hud_line() -> String:
	return ""


## The shell's corner HUD: [the one number that decides the grade, whether it is in trouble] (top
## right). Override.
func hud_value() -> Array:
	return ["", false]


## The shell's ENTER key cap: {at: layout px, label, ready} while there is a "you may go on" moment,
## else {}. Override.
func enter_cap() -> Dictionary:
	return {}


## MISTAKES ON THE PAGE, in one call (operator only): the burst `word` at `at` (layout px, i.e. the
## panel canvas; off the page for the middle), 2-4 blood splats that stay for the rest of the step, a
## shake and a red wash if `serious`, the `mistake_made` signal, and `vitals` charged with `reason` said
## aloud (nothing when 0). Onlookers get the same bursts and splats through the state blob.
func mistake(word: String, vitals: float, reason: String, kind: String, at := Vector2(-1, -1), serious := false) -> void:
	mistakes += 1
	mistake_word = word
	mistake_at = at
	mistake_serious = serious
	if shell != null:
		shell.mistake(word, at, serious, mistakes - 1)
	_mistakes_seen = mistakes
	if serious:
		shake(0.5)
	mistake_made.emit(kind, word)
	if vitals > 0.0:
		cost(vitals, reason)


## A WARNING on the page, not a mistake (operator only): the burst `word` at `at` (layout px), a shake
## and wash if `serious`, but no blood, no bill and no mistake_made. DODGE!'s SQUIRM! is one.
## Onlookers get it through the state blob.
func burst(word: String, at := Vector2(-1, -1), serious := false) -> void:
	bursts += 1
	burst_word = word
	burst_at = at
	burst_serious = serious
	if shell != null:
		shell.burst(word, at, serious, bursts - 1)
	_bursts_seen = bursts
	if serious:
		shake(0.5)


## The step's diagram, in panel pixels. Override.
func paint_game(_c: CanvasItem) -> void:
	pass


## A one-word order slammed across the middle of the panel, with a wipe behind it. READY counts
## down under the word so a player taking over knows exactly when it starts.
func _paint_card(c: CanvasItem) -> void:
	var st := style()
	var size: Vector2 = panel.tex_size()
	var total: float = ready_time if play_state == Play.READY else card_time
	var k: float = clampf(card_left / maxf(0.01, total), 0.0, 1.0)
	var pop: float = 1.0 - pow(1.0 - clampf((1.0 - k) * 6.0, 0.0, 1.0), 3.0)
	var font := ThemeDB.fallback_font
	var big: int = int(round((ready_size if play_state == Play.READY else card_size) * lerpf(0.82, 1.0, pop)))
	var band := size.y * 0.30
	c.draw_rect(Rect2(Vector2(0, size.y * 0.5 - band * 0.5), Vector2(size.x, band)), Color(st.bg, 0.86))
	c.draw_line(Vector2(0, size.y * 0.5 - band * 0.5), Vector2(size.x, size.y * 0.5 - band * 0.5), st.frame, st.thin)
	c.draw_line(Vector2(0, size.y * 0.5 + band * 0.5), Vector2(size.x, size.y * 0.5 + band * 0.5), st.frame, st.thin)
	var col: Color = st.good if play_state == Play.READY else st.frame
	var w: float = font.get_string_size(card_word, HORIZONTAL_ALIGNMENT_LEFT, -1, big).x
	var at := Vector2((size.x - w) * 0.5, size.y * 0.5 + big * 0.35)
	for i in 3:
		c.draw_string(font, at, card_word, HORIZONTAL_ALIGNMENT_LEFT, -1.0, big, Color(col, 0.12))
	c.draw_string(font, at, card_word, HORIZONTAL_ALIGNMENT_LEFT, -1.0, big, col)
	if play_state == Play.READY:
		var secs := "%.1f" % card_left
		var sw: float = font.get_string_size(secs, HORIZONTAL_ALIGNMENT_LEFT, -1, 30).x
		c.draw_string(font, Vector2((size.x - sw) * 0.5, size.y * 0.5 + big * 0.35 + 38.0), secs,
			HORIZONTAL_ALIGNMENT_LEFT, -1.0, 30, Color(st.line_dim, 0.9))


# ---------------------------------------------------------------------------- HUD and net

func hud_state() -> Dictionary:
	return {"title": String(ctx.get("step", {}).get("label", "")), "hint": hint(), "progress": progress,
		"gauges": [], "keys": keys()}


func hint() -> String:
	if frozen:
		return "Stopped where you left it."
	if play_state == Play.READY:
		return "Picking up where they left off..."
	if play_state == Play.CARD:
		return card_word
	return ""


## The shared half of the state every arcade game replicates, plus the game's own. Spectators need
## enough to watch it live -- that is the point of the panel being a thing in the room.
##
## DO NOT snap a value that creeps up by less than its own quantum in a frame. The lab and the bot
## round-trip this dictionary through apply_net_state EVERY frame, so a countdown snapped to 0.05
## never actually counts down. Snap what jumps; send what creeps.
func net_state() -> Dictionary:
	var s: Dictionary = net_pack()
	s["ps"] = play_state
	s["cl"] = card_left
	s["cw"] = card_word
	s["fz"] = frozen
	s["pt"] = play_t
	s["q"] = snappedf(quality, 0.01)
	# The shell's keys start with "~" so they can never collide with a game's own.
	if shell != null:
		s["~mk"] = mistakes
		s["~mw"] = mistake_word
		s["~ma"] = mistake_at
		s["~mz"] = mistake_serious
		s["~bk"] = bursts
		s["~bw"] = burst_word
		s["~ba"] = burst_at
		s["~bz"] = burst_serious
	s["p"] = snappedf(progress, 0.01)
	return s


func apply_net_state(s: Dictionary) -> void:
	if s.is_empty():
		return
	play_state = int(s.get("ps", play_state))
	card_left = float(s.get("cl", card_left))
	card_word = String(s.get("cw", card_word))
	frozen = bool(s.get("fz", frozen))
	play_t = float(s.get("pt", play_t))
	quality = float(s.get("q", quality))
	if s.has("~mk"):
		mistake_word = String(s.get("~mw", mistake_word))
		mistake_at = s.get("~ma", mistake_at)
		mistake_serious = bool(s.get("~mz", mistake_serious))
		mistakes = int(s.get("~mk", mistakes))
	if s.has("~bk"):
		burst_word = String(s.get("~bw", burst_word))
		burst_at = s.get("~ba", burst_at)
		burst_serious = bool(s.get("~bz", burst_serious))
		bursts = int(s.get("~bk", bursts))
	progress = float(s.get("p", progress))
	net_apply(s)


## The game's own state. Keep it small: it goes out 20 times a second. Override.
func net_pack() -> Dictionary:
	return {}


func net_apply(_s: Dictionary) -> void:
	pass


# ---------------------------------------------------------------------------- finishing

## Wrap up: put the panel away, say the sound, and hand the result to the framework.
func arcade_finish(result: Dictionary) -> void:
	if play_state == Play.DONE:
		return
	play_state = Play.DONE
	progress = 1.0
	audio(done_cue, -4.0)
	if panel != null and is_instance_valid(panel):
		panel.close()
	# Only the operator tells the framework it is done; everyone else got here from the net state
	# and just puts their own panel away.
	if bool(ctx.get("operator", false)):
		finish(result)


func at():
	return global_position if is_inside_tree() else null


func audio(cue: String, vol := 0.0, jitter := 0.0) -> void:
	if cue == "":
		return
	var ml = Engine.get_main_loop()
	var a = ml.root.get_node_or_null("Audio") if ml is SceneTree else null
	if a != null:
		a.play(cue, at(), vol, jitter)


## The body, or null. Every consequence goes through it.
func body():
	var b = ctx.get("body")
	return b if b != null and is_instance_valid(b) else null


## Shared by the arcade self-tests: feed bot_input through handle_cursor and tick at 60 Hz, with
## the surgery system's stirs when sedation is under 0.75. Returns the time taken.
static func run_bot(g, skill: float, sed: float, seed_v: int, limit := 90.0) -> float:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var t := 0.0
	var dt := 1.0 / 60.0
	var ext: Vector2 = g.plane_extent()
	var next_stir := 2.0
	var jolt_t := 0.0
	var jolt := Vector2.ZERO
	while t < limit and not g.done:
		t += dt
		var inp: Dictionary = g.bot_input(t, skill)
		var c: Vector2 = inp.get("cursor", Vector2.ZERO)
		if sed < 0.75 and not g.stirs_itself():
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
