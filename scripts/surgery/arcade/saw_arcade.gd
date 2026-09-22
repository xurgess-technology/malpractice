extends "res://scripts/surgery/arcade/arcade_game.gd"
## ARCADE SURGERY -- SAW!, the amputation step. Built from docs/SAW_SPEC.md, "Addendum Four -- SAW!";
## that file wins where anything here disagrees with it. It runs on the clipboard shell
## (scripts/surgery/panel/shell.gd) that DRAW!, DODGE!, WHACK!/WRAP! and SUTURE! already use, and it
## follows SUTURE!'s HUD and keybinding standard unchanged (SUTURE_SPEC 6).
##
## PONG, WHERE THE BALL IS A BONE SAW AND THE LIMB DOES NOT BOUNCE IT BACK. The arm lies across the
## table seen from above, running the full height of the court; the blade travels left to right
## through it. Both paddles are yours and they are MIRRORED onto one input, so you are not playing an
## opponent -- you are keeping a tool in motion through a body.
##
## THE GOVERNING DECISION (spec 1): THE LIMB IS DESTRUCTIBLE MATERIAL, NOT A PROGRESS BAR. Every cell
## holds a stack of layers, the blade strips one layer from whatever it physically passes over, and
## the amputation completes when a gap opens from one side of the limb to the other. Progress and
## picture are the same object: the player reads how far along they are by looking at how much arm is
## left, and a careless run leaves a visibly chewed stump rather than a lower number. Marked zones,
## lane depths, stroke quotas, an artery, hard returns and a table-strike penalty were all tried in
## the source build and cut -- they each replaced a thing the player could see with a rule.
##
## THREE THINGS THE SPEC SINGLES OUT, because each has gone wrong once and each kills a mechanic
## silently. Every one is MEASURED by name in self_test():
##
##   1. THE CUT FOOTPRINT EQUALS THE DRAWN BLADE. BLADE_R is the radius the disc is drawn at AND the
##      radius cells are decremented in; nothing else may stand in for it. An earlier build stripped
##      a 26 px strip under the blade's centre while drawing a 52 px disc, and it read to players as
##      "the saw randomly doesn't cut". If the footprint and the drawing drift apart the game feels
##      broken in a way players cannot articulate.
##   2. BONE STATE IS SAMPLED FROM THE CELLS DIRECTLY UNDER THE BLADE, EVERY FRAME. bone_under_blade()
##      walks the same disc cut_at() walks and looks at those cells and no others. It is never
##      summarised over a row or over the limb: an order-dependent row scan silently disabled bone
##      handling for an entire build.
##   3. THE DIRTY FLAG IS SET ON THE CUTTING PATH. Every decrement and every orphan removal goes
##      through _bump(), which is what makes the baked cell-fill sheet rebuild. Miss it anywhere and
##      the arm appears to update all at once at the end.
##
## Structure (spec 8): a depth grid with a swept-disc decrement, a flood fill used three ways (orphan
## prune, left-to-right completion test, severed-piece tagging), and one ball with Pong reflection.
## No physics engine, no tilemap: `depth` is one byte per cell, and that array plus a ball, a paddle
## position and a vitals float is the whole game state.
##
## Space: the spec's 960 x 600 reference px ("rpx") laid on the paper, same as DODGE!, WHACK! and
## SUTURE!.
##
## Carry-forward out: {"amputated": true, "cut_quality": q} -- the same contract the legacy saw.gd
## finishes with, so the body still loses the limb.

const REF := Vector2(960.0, 600.0)

## THE COURT, in rpx. It starts at x 268 so the corner HUD (the rules, then the key caps) keeps the
## top-left column to itself, exactly as SUTURE!'s board does.
const COURT := Rect2(268.0, 46.0, 624.0, 500.0)

## THE GRID (spec 2): 40 across the limb's width by 100 down the court.
const COLS := 40
const ROWS := 100

## THE BLADE'S RADIUS IN RPX -- 52 px across, per spec 3. HARD REQUIREMENT 1: this single number is
## the drawn disc AND the cut footprint. self_test()'s footprint check measures the swept bite and
## insists it is 2 x this, and that the print of one sample is round.
const BLADE_R := 26.0

## Spec 3: the swept path is sampled every 6 px of travel.
const STEP_PX := 6.0

## Spec 2: on a bone column, depth 2 reads as bone and depth 1 as cracked bone, whatever the layer
## count -- "raising the layer count adds meat depth, not bone depth".
const BONE_AT := 2

## The table under the limb. Spec 3: the gap shows TABLE, not void -- so it is plainly steel and
## never the page, or a hole through the arm reads as blank paper.
const TABLE := Color("8d949a")

## Splat index ranges, kept apart so the shell never throws the same blood twice.
const JUMP_FROM := 60000
const FLAT_FROM := 61000

enum State { SERVE, CUT, PART, RESULT }

# -- the patient (spec 5) ----------------------------------------------------------------------
@export_group("Patient")
## SPEC 7 KNOB "limbType". The step's patient sets it; the toggle under the board swaps it.
@export_enum("human", "seal") var start_limb := "human"
## Spec 5: human 236 px wide, seal flipper 168 px.
@export_range(80.0, 400.0, 1.0) var human_limb_w := 236.0
@export_range(60.0, 400.0, 1.0) var seal_limb_w := 168.0
## Spec 5's phalanges, as stated: 4-5 of them, 7-10 px each. NOTE THE SPEC ARGUES WITH ITSELF HERE --
## it also calls the flipper "nearly all bone", but 5 x 8.5 px in a 168 px limb is a QUARTER of it,
## less than the arm's 92 px of 236. The stated numbers are what is built; widen this pair if the
## flipper should actually feel bonier than the arm (self_test prints both limbs' bone share, so the
## trade is visible the moment it is changed).
@export var seal_phalanx_px := Vector2(7.0, 10.0)
@export_range(2, 9) var seal_phalanges := 5

# -- the material (spec 2) ---------------------------------------------------------------------
@export_group("Material")
## SPEC 7 KNOB "layers": 4 (4-8). One pass per layer, no exceptions.
@export_range(4, 8) var layers := 4

# -- the blade and the paddles (spec 4) --------------------------------------------------------
@export_group("Blade")
## SPEC 7 KNOB "ballSpeed": 820 px/s (400-1100).
@export_range(400.0, 1100.0, 10.0) var ball_speed := 820.0
## SPEC 7 KNOB "paddleHeight": 120 px (70-190).
@export_range(70.0, 190.0, 1.0) var paddle_height := 120.0
## Spec 4: classic Pong return -- contact offset from paddle centre, +-0.5 rad.
@export_range(0.1, 1.2, 0.01) var max_return_rad := 0.5
@export_range(60.0, 900.0, 10.0) var paddle_key_speed := 420.0
## Spec 4 Breakthrough: once the gap has reached all but two columns, speed rises 15%.
@export_range(0.0, 1.0, 0.01) var breakthrough_gain := 0.15

# -- bone handling (spec 4) --------------------------------------------------------------------
@export_group("Bone")
## Above this much bone under the blade it drags and chatters.
@export_range(0.0, 1.0, 0.01) var bone_gate := 0.25
## Spec 4: it slows 6-16%, the top of the band at full coverage.
@export_range(0.0, 0.5, 0.005) var bone_slow_min := 0.06
@export_range(0.0, 0.5, 0.005) var bone_slow_max := 0.16
## SPEC 7 KNOB "chatter": 0.7 (0-1.5), radians per second of wander.
@export_range(0.0, 1.5, 0.05) var chatter := 0.7
## Spec 4: chatter SCALES DOWN as bone coverage rises, so a limb that is bone edge to edge does not
## chatter several times worse than one with meat gutters. This is the multiplier at full coverage.
@export_range(0.0, 1.0, 0.01) var chatter_at_full := 0.38
## The blade always has to make progress across the court, however hard it is chattering.
@export_range(0.05, 0.9, 0.01) var min_x_share := 0.34

# -- the only botch (spec 4) -------------------------------------------------------------------
@export_group("Jumps")
@export_range(0.0, 40.0, 0.5) var jump_bill := 8.0
@export_range(0.0, 60.0, 1.0) var flatline_bill := 18.0
@export_range(0.0, 100.0, 1.0) var vitals_trouble := 35.0

# -- parting and the card (spec 3, 7) ----------------------------------------------------------
@export_group("Results")
## Spec 3: the severed piece slides away from the cut over ~2.2 s while the scene fades to the card.
@export_range(0.4, 6.0, 0.05) var part_time := 2.2
## Far enough that the limb has plainly come apart, not so far that the piece leaves the court.
@export_range(0.0, 400.0, 5.0) var part_slide := 44.0
## SPEC 7: stump quality compares material removed against one straight full-width channel (columns x
## layers x blade diameter / cell height), allowed 1.5x for the overlap real play cannot avoid.
## CALIBRATE THIS AGAINST MEASURED PERFECT PLAY whenever the blade size, the grid or the layer count
## changes -- if flawless play cannot earn "clean", the number is wrong, not the player. self_test()
## plays a flawless run and measures it every time it is run.
@export_range(1.0, 3.0, 0.01) var overlap_allow := 1.5
@export_range(0.5, 3.0, 0.01) var clean_ratio := 1.15
@export_range(0.5, 4.0, 0.01) var ragged_ratio := 1.6
## Score = round(100 - jumps x 9 - vitalsLost x 0.5 - ragged - max(0, t - 25) x 0.7), clamped 0-100.
@export_range(0.0, 30.0, 0.5) var score_jump := 9.0
@export_range(0.0, 5.0, 0.05) var score_vitals := 0.5
@export_range(0.0, 5.0, 0.05) var score_slow := 0.7
@export_range(0.0, 120.0, 1.0) var score_grace := 25.0
## What "- ragged" is worth: the penalty at the far edge of "a little ragged", and how much more a
## properly chewed stump piles on beyond it.
@export_range(0.0, 60.0, 1.0) var ragged_penalty_mid := 14.0
@export_range(0.0, 60.0, 1.0) var ragged_penalty_far := 34.0
@export_range(0, 100) var grade_clean := 78
@export_range(0, 100) var grade_sloppy := 45
@export_range(0.0, 5.0, 0.1) var result_lock := 1.0
@export var result_card_size := Vector2(600.0, 250.0)

# -- the two drawing passes (spec 6) -----------------------------------------------------------
@export_group("Render")
## How often the CELL FILLS are rebuilt. They are the slow pass: the ink outline, the seam and the
## shadow are redrawn live every frame on ink.gd's shared 7 Hz wobble clock whatever this says.
@export_range(0.0, 0.2, 0.005) var bake_every := 0.034
## How often connectivity is re-tested while the blade is in the limb. A full flood every frame is
## 4000 cells of nothing; five times a crossing is imperceptible.
@export_range(0.0, 0.4, 0.005) var gap_every := 0.07

@export_group("Audio")
@export var soft_cue := "surgery_saw_rasp"
@export var bone_cue := "surgery_saw_grind"
@export var paddle_cue := "surgery_click"
@export var jump_cue := "surgery_tear"
@export var through_cue := "surgery_saw_thunk"
@export var flat_cue := "surgery_saw_squelch"
@export_group("")

# ---- replicated ----
var limb_type := "human"
var gen := 0                             ## bumped on every regenerate: the limb's seed salt
var state: int = State.SERVE
## THE WHOLE BOARD (spec 8): one byte of remaining depth per cell.
var depth: PackedByteArray = PackedByteArray()
var ball := Vector2.ZERO
var vel := Vector2.RIGHT                 ## unit direction
var paddle_y := 0.0
var serve_side := -1                     ## -1 the left paddle, +1 the right
var vit := 100.0                         ## THIS CREEPS. Never snap it.
var strokes := 0
var jumps := 0
var removed := 0                         ## layer-cells taken off: the stump-quality numerator
var cut_t := 0.0                         ## THIS CREEPS.
var part_left := 0.0                     ## THIS CREEPS.
var through := false
var broke := false                       ## breakthrough: the gap is all but two columns wide
var gap_cols := -1                       ## the furthest column the gap reaches
var flatlined := false
var score := 0
var _grade := ""

# ---- from the seed (rebuilt from limb_type and gen on every machine) ----
## A column is bone or it is not (spec 2: "whether its column falls inside a bone shaft").
var bone_col: Array[bool] = []
var hide_tint: PackedColorArray = PackedColorArray()   ## the seal's hide, worked out once per limb
var grime_spots: Array = []

# ---- local ----
## HARD REQUIREMENT 3: raised by EVERY decrement and EVERY orphan removal, through _bump().
var dirty := true
var _rng := RandomNumberGenerator.new()
## The touched set for the current crossing (spec 3): a stamped array, so nothing is allocated per
## pass. _touch_id is bumped on every paddle contact and every serve.
var _touch: PackedInt32Array = PackedInt32Array()
var _touch_id := 0
var _sever: PackedByteArray = PackedByteArray()   ## 1 where the cell is on the severed piece
var _tex: ImageTexture = null                     ## the baked cell fills, attached material
var _tex_cut: ImageTexture = null                 ## and the severed piece, once it has parted
var _img: Image = null
var _row_lo := 0                                  ## rows of the sheet that need repainting
var _row_hi := ROWS - 1
var _edges: Array = []                            ## [a, b, kind, severed] rpx, merged runs
var _chips: Array = []                            ## [pos, vel, life, colour]
var _bake_at := -99.0
var _gap_wait := 0.0
var _seen_removed := 0
var _seen := {}
var _bone_now := 0.0
var _cursor := Vector2(480.0, 300.0)
var _rmb_prev := false
var _card_down_frame := false
var _rle_cache: PackedByteArray = PackedByteArray()
var _rle_rev := -1
var _rev := 0                                     ## bumped with `dirty`, so the RLE cache knows
var _warm := false
var _bot := {"t": 0.0, "gate": -1.0, "up": false, "aim": 0.0}

## REVIEW / DEV OVERRIDE: the limb a fresh SAW! opens on, whatever its patient says ("" for none).
static var force_limb := ""

# ---- the toggle under the board (spec 5) ----
var _btn_limb := Rect2(COURT.position.x, 556.0, 216.0, 30.0)


# ---------------------------------------------------------------------------- setup

func use_ink() -> bool:
	return true


func ink_unit() -> float:
	return _u()


func card_word_for_start() -> String:
	return "SAW!"


func build_game() -> void:
	if ink != null:
		ink.content = Rect2(Vector2(0.0, _top()), REF * _u())
	limb_type = "seal" if String(ctx.get("patient_id", "bob")) == "seal" else start_limb
	if force_limb != "":
		limb_type = force_limb
	for a in OS.get_cmdline_user_args():
		if a == "--seal":
			limb_type = "seal"
		elif a == "--human":
			limb_type = "human"
	generate()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("saw|grime|%d" % int(ctx.get("seed", 1)))
	grime_spots = InkScript.make_grime(rng, Rect2(Vector2(40, 60), panel.tex_size() - Vector2(80, 120)))


func setup(context: Dictionary) -> void:
	super.setup(context)
	# The board is the readable surface, the rule SUTURE! set: blood stays off the court and the limb.
	if shell != null:
		shell.keep_out = Rect2(cv(COURT.position), COURT.size * _u()).grow(cl(10.0))


# ---------------------------------------------------------------------------- the limb (spec 2, 5)

## Everything about the limb comes from (seed, limb_type, gen) alone, so every machine builds the same
## one from two replicated values and the bone layout never goes over the wire.
func generate() -> void:
	_rng.seed = hash("saw|%d|%s|%d" % [int(ctx.get("seed", 1)), limb_type, gen])
	depth = PackedByteArray()
	depth.resize(COLS * ROWS)
	for i in COLS * ROWS:
		depth[i] = layers
	_sever = PackedByteArray()
	_sever.resize(COLS * ROWS)
	_touch = PackedInt32Array()
	_touch.resize(COLS * ROWS)
	_touch_id = 1
	_build_bone()
	_build_hide()
	removed = 0
	strokes = 0
	through = false
	broke = false
	gap_cols = -1
	_tex = null
	_tex_cut = null
	_img = null
	_bake_at = -99.0
	_gap_wait = 0.0
	_chips.clear()
	_seen_removed = 0
	_row_lo = 0
	_row_hi = ROWS - 1
	_bump()
	paddle_y = COURT.get_center().y
	serve_side = -1
	state = State.SERVE
	_rest_on_paddle()


## SPEC 5. Human: two bone shafts (58 px and 34 px) with meat gutters either side. Seal flipper: 4-5
## slim phalanges (7-10 px) fanned across nearly its full width. A column is bone when its centre
## falls inside a shaft -- and that per-column fact, not a silhouette, is what the blade reads.
func _build_bone() -> void:
	bone_col = []
	bone_col.resize(COLS)
	for i in COLS:
		bone_col[i] = false
	var w := limb_w()
	var shafts: Array = []
	if limb_type == "seal":
		var n := _rng.randi_range(maxi(2, seal_phalanges - 1), seal_phalanges)
		var span := w * 0.88
		var edge := w * 0.06
		for i in n:
			var width := _rng.randf_range(seal_phalanx_px.x, seal_phalanx_px.y)
			var mid := edge + span * (float(i) + 0.5) / float(n) + _rng.randf_range(-2.5, 2.5)
			shafts.append([mid - width * 0.5, width])
	else:
		# Gutter, the big shaft, gutter, the small shaft, gutter: 48 + 58 + 48 + 34 + 48 = 236.
		var gut := (w - 92.0) / 3.0
		shafts.append([gut, 58.0])
		shafts.append([gut * 2.0 + 58.0, 34.0])
	for cxi in COLS:
		var mid: float = (float(cxi) + 0.5) * cell_w()
		for s in shafts:
			if mid >= float(s[0]) and mid <= float(s[0]) + float(s[1]):
				bone_col[cxi] = true
				break


## SPEC 5: the seal's slate hide from the sedation step -- ink.hide_seal (#67757b) with dark blubber
## rolls banding across the limb, mottled speckle and a few pale sheen flecks. Drawn the way
## inject_arcade.gd draws it (pale rolls read as folds, the speckle is the dark element), not invented
## a second time. Worked out ONCE per limb into a per-cell tint, because it is baked into the sheet.
func _build_hide() -> void:
	hide_tint = PackedColorArray()
	if limb_type != "seal":
		return
	hide_tint.resize(COLS * ROWS)
	var base: Color = ink.hide_seal if ink != null else Color("67757b")
	for i in COLS * ROWS:
		hide_tint[i] = base
	var h := COURT.size.y
	# Four blubber rolls banding across the limb.
	for ri in 4:
		var y0: float = h * (0.14 + 0.23 * float(ri)) + _rng.randf_range(-14.0, 14.0)
		for cxi in COLS:
			var x: float = (float(cxi) + 0.5) * cell_w()
			var y: float = y0 + 8.0 * sin(x * 0.03 + float(ri))
			for cyi in ROWS:
				var d: float = absf((float(cyi) + 0.5) * cell_h() - y)
				if d < 10.0:
					var i := cyi * COLS + cxi
					# Pale folds, not ink: dark lines here read as veins to aim at.
					hide_tint[i] = hide_tint[i].lightened(0.16 * (1.0 - d / 10.0))
	# Mottled speckle, then a few pale sheen flecks over the top.
	for i in 140:
		var cxi := _rng.randi_range(0, COLS - 1)
		var cyi := _rng.randi_range(0, ROWS - 1)
		hide_tint[cyi * COLS + cxi] = hide_tint[cyi * COLS + cxi].darkened(_rng.randf_range(0.14, 0.3))
	for i in 16:
		var cxi := _rng.randi_range(0, COLS - 1)
		var cyi := _rng.randi_range(0, ROWS - 1)
		hide_tint[cyi * COLS + cxi] = hide_tint[cyi * COLS + cxi].lightened(_rng.randf_range(0.2, 0.36))


func limb_w() -> float:
	return seal_limb_w if limb_type == "seal" else human_limb_w


func limb_x0() -> float:
	return COURT.get_center().x - limb_w() * 0.5


func cell_w() -> float:
	return limb_w() / float(COLS)


func cell_h() -> float:
	return COURT.size.y / float(ROWS)


func limb_rect() -> Rect2:
	return Rect2(limb_x0(), COURT.position.y, limb_w(), COURT.size.y)


func cell_centre(cxi: int, cyi: int) -> Vector2:
	return Vector2(limb_x0() + (float(cxi) + 0.5) * cell_w(),
		COURT.position.y + (float(cyi) + 0.5) * cell_h())


## HARD REQUIREMENT 3: every change to the material comes through here, and nothing else raises
## `dirty`. Miss it on the cutting path and the arm updates all at once at the end.
func _bump(row := -1) -> void:
	dirty = true
	_rev += 1
	if row >= 0:
		_row_lo = mini(_row_lo, row)
		_row_hi = maxi(_row_hi, row)
	else:
		_row_lo = 0
		_row_hi = ROWS - 1


# ---------------------------------------------------------------------------- cutting (spec 3)

## THE BITE MATCHES THE BLADE (spec 3, HARD REQUIREMENT 1). Samples the blade's swept path every
## STEP_PX of travel and decrements every cell whose centre falls within BLADE_R -- a ROUND footprint
## the full 52 px width of the disc, never a strip under the centre. The touched set makes it one
## decrement per cell per crossing however slowly the blade re-enters.
func cut_sweep(from: Vector2, to: Vector2) -> void:
	var d := to - from
	var n := maxi(1, int(ceil(d.length() / STEP_PX)))
	for i in range(0, n + 1):
		cut_at(from + d * (float(i) / float(n)))


## One sample of the swept path: the round footprint at `p`, radius BLADE_R.
func cut_at(p: Vector2) -> void:
	var cw := cell_w()
	var ch := cell_h()
	var x0 := limb_x0()
	var y0 := COURT.position.y
	var c0: int = maxi(0, int(floor((p.x - BLADE_R - x0) / cw)))
	var c1: int = mini(COLS - 1, int(floor((p.x + BLADE_R - x0) / cw)))
	var r0: int = maxi(0, int(floor((p.y - BLADE_R - y0) / ch)))
	var r1: int = mini(ROWS - 1, int(floor((p.y + BLADE_R - y0) / ch)))
	if c1 < c0 or r1 < r0:
		return
	var rr := BLADE_R * BLADE_R
	for cyi in range(r0, r1 + 1):
		var dy: float = y0 + (float(cyi) + 0.5) * ch - p.y
		var dy2 := dy * dy
		var row := cyi * COLS
		for cxi in range(c0, c1 + 1):
			var dx: float = x0 + (float(cxi) + 0.5) * cw - p.x
			if dx * dx + dy2 > rr:
				continue
			var i: int = row + cxi
			if _touch[i] == _touch_id:
				continue
			_touch[i] = _touch_id
			if depth[i] == 0:
				continue
			depth[i] = int(depth[i]) - 1
			removed += 1
			_bump(cyi)


## HARD REQUIREMENT 2: BONE UNDER THE BLADE, READ FROM THE CELLS DIRECTLY UNDER IT, THIS FRAME. The
## same disc cut_at() walks, and nothing else -- never a row scan, never a whole-limb summary. Both
## of the mechanic-killing bugs in the source build came from a cheaper summary standing in for the
## actual contact. Returns the share of the LIVE material under the disc that is showing bone, and 0
## when the disc is over nothing.
func bone_under_blade() -> float:
	var cw := cell_w()
	var ch := cell_h()
	var x0 := limb_x0()
	var y0 := COURT.position.y
	var c0: int = maxi(0, int(floor((ball.x - BLADE_R - x0) / cw)))
	var c1: int = mini(COLS - 1, int(floor((ball.x + BLADE_R - x0) / cw)))
	var r0: int = maxi(0, int(floor((ball.y - BLADE_R - y0) / ch)))
	var r1: int = mini(ROWS - 1, int(floor((ball.y + BLADE_R - y0) / ch)))
	if c1 < c0 or r1 < r0:
		return 0.0
	var rr := BLADE_R * BLADE_R
	var live := 0
	var bone := 0
	for cyi in range(r0, r1 + 1):
		var dy: float = y0 + (float(cyi) + 0.5) * ch - ball.y
		var dy2 := dy * dy
		var row := cyi * COLS
		for cxi in range(c0, c1 + 1):
			var dx: float = x0 + (float(cxi) + 0.5) * cw - ball.x
			if dx * dx + dy2 > rr:
				continue
			var dv := int(depth[row + cxi])
			if dv == 0:
				continue
			live += 1
			if bone_col[cxi] and dv <= BONE_AT:
				bone += 1
	return 0.0 if live == 0 else float(bone) / float(live)


# --------------------------------------------------- the flood fill, used three ways (spec 8)

## ONE. ORPHANS FALL AWAY (spec 3). After each crossing, any material no longer connected 4-way to
## either the proximal (row 0) or the distal (row ROWS-1) end of the court is removed with a spray of
## chips. Islands do not hang in the air. Returns how many cells fell.
func prune_orphans() -> int:
	var keep := PackedByteArray()
	keep.resize(COLS * ROWS)
	var stack := PackedInt32Array()
	for cxi in COLS:
		for cyi: int in [0, ROWS - 1]:
			var i: int = cyi * COLS + cxi
			if depth[i] > 0 and keep[i] == 0:
				keep[i] = 1
				stack.append(i)
	_flood4(keep, stack)
	var fell := 0
	for i in COLS * ROWS:
		if depth[i] > 0 and keep[i] == 0:
			_chip_at(cell_centre(i % COLS, i / COLS), int(depth[i]), 1)
			depth[i] = 0
			fell += 1
			# HARD REQUIREMENT 3: an orphan falling is a change to the material like any other.
			_bump(i / COLS)
	return fell


## TWO. COMPLETION IS CONNECTIVITY, NOT GEOMETRY (spec 3). The cut is through when a path of EMPTY
## cells exists from the limb's left edge to its right edge, 8-CONNECTED: a diagonal or stepped gap
## counts, a full straight row is not required. Returns the furthest column the gap reaches, so the
## same pass answers the breakthrough rule (spec 4) as well.
func gap_reach() -> int:
	var seen := PackedByteArray()
	seen.resize(COLS * ROWS)
	var stack := PackedInt32Array()
	for cyi in ROWS:
		var i := cyi * COLS
		if depth[i] == 0:
			seen[i] = 1
			stack.append(i)
	var best := -1
	while not stack.is_empty():
		var v: int = stack[stack.size() - 1]
		stack.resize(stack.size() - 1)
		var vx := v % COLS
		var vy := v / COLS
		if vx > best:
			best = vx
		for dy in [-1, 0, 1]:
			var ny: int = vy + int(dy)
			if ny < 0 or ny >= ROWS:
				continue
			for dx in [-1, 0, 1]:
				if dx == 0 and dy == 0:
					continue
				var nx: int = vx + int(dx)
				if nx < 0 or nx >= COLS:
					continue
				var j: int = ny * COLS + nx
				if seen[j] == 1 or depth[j] > 0:
					continue
				seen[j] = 1
				stack.append(j)
	return best


## THREE. PARTING (spec 3). On completion, everything no longer connected 4-way to the PROXIMAL end
## (row 0) is flagged as the severed piece; it slides away from the cut while the scene fades.
func tag_severed() -> int:
	_sever = PackedByteArray()
	_sever.resize(COLS * ROWS)
	var keep := PackedByteArray()
	keep.resize(COLS * ROWS)
	var stack := PackedInt32Array()
	for cxi in COLS:
		if depth[cxi] > 0:
			keep[cxi] = 1
			stack.append(cxi)
	_flood4(keep, stack)
	var n := 0
	for i in COLS * ROWS:
		if depth[i] > 0 and keep[i] == 0:
			_sever[i] = 1
			n += 1
	_bump()
	return n


## The shared 4-way flood: every cell with material reachable from the seeds already on `stack`.
func _flood4(keep: PackedByteArray, stack: PackedInt32Array) -> void:
	while not stack.is_empty():
		var v: int = stack[stack.size() - 1]
		stack.resize(stack.size() - 1)
		var vx := v % COLS
		var vy := v / COLS
		for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nx: int = vx + d.x
			var ny: int = vy + d.y
			if nx < 0 or ny < 0 or nx >= COLS or ny >= ROWS:
				continue
			var j: int = ny * COLS + nx
			if keep[j] == 1 or depth[j] == 0:
				continue
			keep[j] = 1
			stack.append(j)


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


## The framework's cursor (diagram mm) -> rpx, through the page's tilt.
func ref_of_mm(mm: Vector2) -> Vector2:
	var c: Vector2 = panel.mm_to_px(mm)
	if ink != null:
		c = ink.unpage(c, panel.tex_size())
	return Vector2(c.x / _u(), (c.y - _top()) / _u())


## rpx -> the framework's cursor (panel metres), for the bot and the self-test.
func metres_of_ref(p: Vector2) -> Vector2:
	if panel == null:
		return Vector2.ZERO
	var c := cv(p)
	if ink != null:
		c = ink.onpage(c, panel.tex_size())
	var mm: Vector2 = (c - panel.tex_size() * 0.5) / panel.px_per_mm()
	return panel.metres_of(mm)


func paddle_face(side: int) -> float:
	return COURT.position.x if side < 0 else COURT.end.x


func paddle_limit() -> float:
	return COURT.size.y * 0.5 - paddle_height * 0.5


# ---------------------------------------------------------------------------- the cards and the HUD

func stamp_for(word: String) -> Dictionary:
	var I := ink
	match word:
		"SAW!":
			var lines := ["Both paddles are yours, and they move together.",
				"The limb does not bounce it back -- it keeps what the blade takes."]
			lines.append("A flipper is narrower, and bone almost all the way across." if limb_type == "seal"
				else "Two bone shafts, with meat either side of them.")
			return {"goal": "Keep the blade in motion until the limb parts.", "lines": lines,
				"prompt": "SPACE to start", "color": I.ink if I != null else Color.BLACK}
		"CLEAN", "SLOPPY", "MALPRACTICE":
			return {"goal": _flavour(word), "lines": _result_lines(),
				"prompt": "SPACE to finish   ·   RIGHT MOUSE to retry", "wait": "Look at it...",
				"color": (I.good if word == "CLEAN" else I.deep_red) if I != null else Color.BLACK}
	return {"prompt": "SPACE"}


func _result_lines() -> Array:
	return [
		"Off in %s   ·   %d strokes   ·   %d jumps" % [_clock(cut_t), strokes, jumps],
		"Stump %s (%.2fx)   ·   vitals lost %d%%" % [stump_word(), stump_ratio(), int(round(vitals_lost()))],
		"SCORE %d" % score,
	]


static func _clock(s: float) -> String:
	return "%d:%02d" % [int(s) / 60, int(s) % 60]


func _flavour(grade: String) -> String:
	if flatlined:
		return "He ran out before the limb did."
	match grade:
		"CLEAN":
			return "One channel, straight through. Textbook."
		"SLOPPY":
			return "It came off. It will want tidying."
	return "That is not an amputation. That is a mauling."


## SPEC 6 (SUTURE!'s standard, unchanged): the old one-line HUD is off here -- the rules and the key
## caps are drawn in paint_game through the shell's two-block helpers instead.
func hud_line() -> String:
	return ""


## SPEC 6: top right, ONE number. VITALS %, red under 35.
func hud_value() -> Array:
	if state == State.RESULT:
		return ["SCORE %d" % score, _grade == "MALPRACTICE"]
	return ["VITALS %d%%" % int(ceil(maxf(0.0, vit))), vit < vitals_trouble]


## SPEC 6: three short lines saying what you are trying to do -- never which key.
func rules() -> Array:
	return ["open a gap right through the limb", "never let the blade past a paddle",
		"bone drags the blade and pulls it off line"]


## SPEC 6: below them, the keybindings as boxed key caps.
func key_caps() -> Array:
	return [["MOUSE UP / DOWN", "move both paddles"], ["W / S", "the same, on keys"],
		["SPACE", "send the blade in"]]


func keys() -> Array:
	if play_state == Play.DONE:
		return []
	return [["Mouse / W S", "both paddles"], ["Space", "serve the blade"]]


func hint() -> String:
	if stamp_waiting():
		return "Take the limb off: keep the blade going until a gap opens right through." \
			if card_word == "SAW!" else "Done. Space to finish, right mouse to try again."
	var base := super.hint()
	if base != "":
		return base
	match state:
		State.SERVE:
			return "Line the paddle up and press Space."
		State.CUT:
			return "Almost through. Don't lose it now." if broke else "Keep it moving. Bone drags."
		State.PART:
			return "It's off."
	return "Space to finish."


# ---------------------------------------------------------------------------- playing

## Right mouse on the results card is RETRY, which the shell would never hand to play() -- so it is
## read here, ahead of the card.
func handle_cursor(p: Vector2, buttons: int, delta: float) -> void:
	var rmb: bool = (buttons & BUTTON_SECONDARY) != 0
	var rmb_edge: bool = rmb and not _rmb_prev
	_rmb_prev = rmb
	if rmb_edge and state == State.RESULT and stamp_waiting() and card_left <= 0.0 and not frozen:
		_retry()
		return
	# The press that takes the SAW! card down must not ALSO be the serve: the player has to see the
	# board and the aim line before the blade goes in.
	_card_down_frame = stamp_waiting()
	super.handle_cursor(p, buttons, delta)


func play(p_mm: Vector2, buttons: int, edges: int, delta: float) -> void:
	var p := ref_of_mm(p_mm)
	_cursor = p
	if state == State.RESULT:
		# The results card has been taken down and that press is the step's last action.
		_finish_step()
		return
	if _card_down_frame:
		edges &= ~(BUTTON_ACTION | BUTTON_PRIMARY | BUTTON_ENTER)
	# SPEC 5: a toggle under the board switches patient and regenerates.
	if (edges & BUTTON_PRIMARY) != 0 and _btn_limb.has_point(p):
		limb_type = "seal" if limb_type == "human" else "human"
		gen += 1
		generate()
		return
	# SPEC 4: mirrored paddles, ONE input -- mouse Y, or W / S.
	var lo := COURT.get_center().y - paddle_limit()
	var hi := COURT.get_center().y + paddle_limit()
	if (buttons & BUTTON_UP) != 0:
		paddle_y = clampf(paddle_y - paddle_key_speed * delta, lo, hi)
	elif (buttons & BUTTON_DOWN) != 0:
		paddle_y = clampf(paddle_y + paddle_key_speed * delta, lo, hi)
	else:
		paddle_y = clampf(p.y, lo, hi)
	if state == State.SERVE:
		_rest_on_paddle()
		if (edges & (BUTTON_ACTION | BUTTON_ENTER)) != 0:
			_serve()


## SPEC 4's serve: the blade RESTS ON THE PADDLE IT WILL JUMP FROM and waits. Same on the opening
## serve and after every jump, so the player always knows where the next pass starts.
func _rest_on_paddle() -> void:
	ball = Vector2(paddle_face(serve_side) + BLADE_R * float(-serve_side), paddle_y)
	vel = Vector2(float(-serve_side), 0.0)


func _serve() -> void:
	state = State.CUT
	_touch_id += 1
	vel = Vector2(float(-serve_side), 0.0)
	audio(paddle_cue, -12.0, 0.1)


func advance(delta: float) -> void:
	match state:
		State.SERVE:
			cut_t += delta
		State.CUT:
			cut_t += delta
			_gap_wait = maxf(0.0, _gap_wait - delta)
			_step_blade(delta)
		State.PART:
			part_left = maxf(0.0, part_left - delta)
			if part_left <= 0.0:
				_to_result()


func _step_blade(delta: float) -> void:
	# HARD REQUIREMENT 2: bone is read from the cells under the disc, right now, every frame.
	_bone_now = bone_under_blade()
	var slow := 0.0
	var chat := 0.0
	if _bone_now > bone_gate:
		var over: float = clampf((_bone_now - bone_gate) / maxf(0.001, 1.0 - bone_gate), 0.0, 1.0)
		slow = lerpf(bone_slow_min, bone_slow_max, over)
		# SPEC 4: chatter scales DOWN as coverage rises, so a limb that is bone edge to edge is not
		# several times worse than one with meat gutters.
		chat = chatter * lerpf(1.0, chatter_at_full, over)
	var speed: float = ball_speed * (1.0 - slow) * (1.0 + (breakthrough_gain if broke else 0.0))
	if chat > 0.0:
		var wob := sin(cut_t * 9.1) * 0.62 + sin(cut_t * 14.7 + 1.3) * 0.38
		vel = vel.rotated(wob * chat * delta).normalized()
		if absf(vel.x) < min_x_share:
			var sx: float = 1.0 if vel.x >= 0.0 else -1.0
			var sy: float = 1.0 if vel.y >= 0.0 else -1.0
			vel = Vector2(sx * min_x_share, sy * sqrt(maxf(0.0, 1.0 - min_x_share * min_x_share)))
	# Move in short hops so a fast blade can never step straight past a paddle or a wall.
	var left := speed * delta
	var guard := 0
	while left > 0.0001 and state == State.CUT and guard < 32:
		guard += 1
		var hop: float = minf(left, BLADE_R * 0.5)
		left -= hop
		var from := ball
		var to := ball + vel * hop
		if to.y - BLADE_R < COURT.position.y and vel.y < 0.0:
			to.y = COURT.position.y + BLADE_R
			vel.y = absf(vel.y)
		elif to.y + BLADE_R > COURT.end.y and vel.y > 0.0:
			to.y = COURT.end.y - BLADE_R
			vel.y = -absf(vel.y)
		ball = to
		cut_sweep(from, to)
		if vel.x < 0.0 and ball.x - BLADE_R <= COURT.position.x:
			_at_paddle(-1)
		elif vel.x > 0.0 and ball.x + BLADE_R >= COURT.end.x:
			_at_paddle(1)
	if _gap_wait <= 0.0:
		_gap_wait = gap_every
		_check_through()


## Classic Pong (spec 4): the contact offset from the paddle's centre sets the return angle, +-0.5
## rad. Miss it and the saw jumps -- the only botch in the piece.
func _at_paddle(side: int) -> void:
	var half: float = maxf(1.0, paddle_height * 0.5)
	var off: float = (ball.y - paddle_y) / half
	# The blade bites from its edge, so its edge catches the paddle's end too.
	if absf(off) > 1.0 + BLADE_R * 0.5 / half:
		_jumped(side)
		return
	strokes += 1
	# A NEW CROSSING: the touched set starts again, so the next pass may take a fresh layer.
	_touch_id += 1
	var ang: float = clampf(off, -1.0, 1.0) * max_return_rad
	var dir := 1.0 if side < 0 else -1.0
	vel = Vector2(cos(ang) * dir, sin(ang)).normalized()
	ball.x = paddle_face(side) + BLADE_R * dir
	audio(paddle_cue, -14.0, 0.15)
	# SPEC 3: orphans fall away after each crossing.
	prune_orphans()
	_gap_wait = 0.0
	_check_through()


## SPEC 4, THE ONLY BOTCH: missing the paddle. SAW JUMPED!, blood, chips, hard shake, -8 vitals, and
## the blade returns to rest on the paddle it got past.
func _jumped(side: int) -> void:
	jumps += 1
	vit = maxf(0.0, vit - jump_bill)
	_chip_at(Vector2(paddle_face(side), ball.y), layers, 10)
	if shell != null:
		shell.splat(JUMP_FROM + jumps)
	mistake("SAW JUMPED!", jump_bill, "Let the saw jump out of the cut", "saw_jump",
		cv(Vector2(paddle_face(side), ball.y)), true)
	serve_side = side
	state = State.SERVE
	_touch_id += 1
	_rest_on_paddle()
	_check_flatline()


## Vitals at zero is FLATLINE! and an automatic MALPRACTICE.
func _check_flatline() -> void:
	if flatlined or vit > 0.0 or state == State.RESULT:
		return
	flatlined = true
	mistake("FLATLINE!", flatline_bill, "Let the patient empty on the table", "flatline",
		cv(COURT.get_center()), true)
	if shell != null:
		for i in 4:
			shell.splat(FLAT_FROM + i)
	_to_result()


## SPEC 3 and 4: connectivity decides both completion and the breakthrough speed-up, in one pass.
func _check_through() -> void:
	if through:
		return
	gap_cols = gap_reach()
	if gap_cols >= COLS - 3:
		broke = true
	if gap_cols >= COLS - 1:
		through = true
		tag_severed()
		state = State.PART
		part_left = part_time
		burst("THROUGH!", cv(COURT.get_center()))
		audio(through_cue, -2.0)
	_update_progress()


# ---------------------------------------------------------------------------- results (spec 7)

## SPEC 7's reference: ONE STRAIGHT FULL-WIDTH CHANNEL -- columns x layers x blade diameter / cell
## height.
func reference_channel() -> float:
	return float(COLS) * float(layers) * (BLADE_R * 2.0 / cell_h())


## Material removed against that reference, allowed `overlap_allow` (1.5x) for the overlap real play
## cannot avoid. CALIBRATED AGAINST MEASURED PERFECT PLAY: see self_test()'s _perfect_run.
func stump_ratio() -> float:
	return float(removed) / maxf(1.0, reference_channel() * overlap_allow)


func stump_word() -> String:
	var r := stump_ratio()
	if r <= clean_ratio:
		return "clean"
	if r <= ragged_ratio:
		return "a little ragged"
	return "ragged"


## What "- ragged" is worth in the score: nothing while the stump is clean, rising through the middle
## band and on past it.
func ragged_penalty() -> float:
	var r := stump_ratio()
	if r <= clean_ratio:
		return 0.0
	if r <= ragged_ratio:
		return ragged_penalty_mid * (r - clean_ratio) / maxf(0.01, ragged_ratio - clean_ratio)
	return ragged_penalty_mid + ragged_penalty_far * minf(1.5, r - ragged_ratio)


func vitals_lost() -> float:
	return clampf(100.0 - vit, 0.0, 100.0)


func grade_score() -> int:
	if flatlined:
		return 0
	var s: float = 100.0 - float(jumps) * score_jump - vitals_lost() * score_vitals \
		- ragged_penalty() - maxf(0.0, cut_t - score_grace) * score_slow
	return clampi(int(round(s)), 0, 100)


func grade_word() -> String:
	if flatlined:
		return "MALPRACTICE"
	var s := grade_score()
	if s >= grade_clean:
		return "CLEAN"
	if s >= grade_sloppy:
		return "SLOPPY"
	return "MALPRACTICE"


func _to_result() -> void:
	score = grade_score()
	_grade = grade_word()
	state = State.RESULT
	if shell != null:
		shell.stamp_size = result_card_size
	show_card(_grade, result_lock)
	progress = 1.0


func _retry() -> void:
	card_word = ""
	play_state = Play.RUNNING
	vit = 100.0
	jumps = 0
	cut_t = 0.0
	part_left = 0.0
	flatlined = false
	score = 0
	_grade = ""
	if shell != null:
		shell.stamp_size = Vector2(516.0, 274.0)
	generate()


func _finish_step() -> void:
	quality = clampf(float(score) / 100.0, 0.05, 1.0)
	var b = body()
	if b != null:
		if b.has_method("set_bleeding"):
			b.set_bleeding(String(ctx.get("step", {}).get("site", "limb_cut")), 0.25)
		if b.has_method("apply_flags"):
			var f: Dictionary = (ctx.get("flags", {}) as Dictionary).duplicate()
			f["amputated"] = true
			b.apply_flags(f)
	arcade_finish({"amputated": true, "cut_quality": quality})


func _update_progress() -> void:
	if state == State.RESULT or through:
		progress = 1.0
		return
	progress = clampf(float(maxi(0, gap_cols + 1)) / float(COLS), 0.0, 0.97)


# ---------------------------------------------------------------------------- animation and sound

## Spec 6: chips are short-lived particles in the colour of the layer they came from.
func _chip_at(p: Vector2, layer: int, n: int) -> void:
	for i in n:
		if _chips.size() >= 90:
			_chips.remove_at(0)
		var a := randf() * TAU
		_chips.append([p + Vector2(randf_range(-6.0, 6.0), randf_range(-6.0, 6.0)),
			Vector2(cos(a), sin(a)) * randf_range(40.0, 190.0), randf_range(0.22, 0.55),
			layer_colour(maxi(1, layer), false)])


func animate(delta: float) -> void:
	for i in range(_chips.size() - 1, -1, -1):
		var ch: Array = _chips[i]
		ch[2] = float(ch[2]) - delta
		if float(ch[2]) <= 0.0:
			_chips.remove_at(i)
			continue
		ch[0] = Vector2(ch[0]) + Vector2(ch[1]) * delta
		ch[1] = Vector2(ch[1]) * maxf(0.0, 1.0 - 3.4 * delta)
	# Chips follow the REPLICATED removal count, so an onlooker sees the same spray the operator does.
	if removed > _seen_removed:
		if state == State.CUT:
			_chip_at(ball, 1 + int(_bone_now > bone_gate), 1)
		_seen_removed = removed


func react() -> void:
	var now := {"st": strokes, "sa": state, "ju": jumps, "th": through}
	if _seen.is_empty():
		_seen = now
		return
	if int(now.st) > int(_seen.st):
		audio(bone_cue if _bone_now > bone_gate else soft_cue, -13.0, 0.2)
	if int(now.ju) > int(_seen.ju):
		audio(jump_cue, -8.0, 0.1)
	if bool(now.th) and not bool(_seen.th):
		audio(through_cue, -4.0)
	if flatlined and int(_seen.sa) != State.RESULT and int(now.sa) == State.RESULT:
		audio(flat_cue, -4.0)
	_seen = now
	var b = body()
	if b != null and b.has_method("set_bleeding") and play_state != Play.DONE:
		b.set_bleeding(String(ctx.get("step", {}).get("site", "limb_cut")),
			clampf(0.12 + progress * 0.5, 0.0, 1.0))


## A jerk knocks both paddles off where you were holding them.
func on_jolt(_offset: Vector2, strength: float, _duration: float) -> void:
	var lo := COURT.get_center().y - paddle_limit()
	var hi := COURT.get_center().y + paddle_limit()
	paddle_y = clampf(paddle_y + (42.0 if randf() < 0.5 else -42.0), lo, hi)
	shake(clampf(0.5 + strength * 0.5, 0.0, 1.0))


# ---------------------------------------------------------------------------- the page (spec 6)

## SPEC 6: SPLIT THE ARM INTO TWO PASSES. The CELL FILLS go to an offscreen sheet -- a COLS x ROWS
## image drawn nearest-neighbour over the limb rect -- rebuilt only when the material changes. The
## INK OUTLINE, the RED SEAM inside every exposed edge and the SHADOW under every exposed upper face
## are redrawn LIVE each frame on ink.gd's shared 7 Hz wobble clock, so the arm breathes like the
## paddles and the blade.
##
## The page stays flat: no halftone screen, no sheet hatching, no centre line. The ink line work
## carries the drawing.
func paint_game(c: CanvasItem) -> void:
	if panel == null or ink == null:
		return
	ink.draw_grime(c, grime_spots)
	_paint_table(c)
	if _tex == null or (dirty and ink.t - _bake_at >= bake_every):
		_bake()
	_paint_material(c)
	_paint_edges(c)
	_paint_chips(c)
	_paint_paddles(c)
	_paint_blade(c)
	_paint_button(c)
	shell.draw_keycaps(c, key_caps(), shell.draw_rules(c, rules()))
	if _warm:
		ink.warm(c)
		c.draw_string(InkScript.font_upright(), Vector2(-100, -100),
			"SAW! SAW JUMPED! THROUGH! FLATLINE! CLEAN SLOPPY MALPRACTICE PATIENT HUMAN ARM SEAL FLIPPER",
			HORIZONTAL_ALIGNMENT_LEFT, -1.0, 110, ink.ink)


## Spec 3: THE GAP SHOWS TABLE, NOT VOID. It has to be plainly a steel table and not the page, or a
## hole through the arm reads as blank paper and the player cannot tell "gone" from "bone".
func _paint_table(c: CanvasItem) -> void:
	var r := limb_rect().grow(10.0)
	var dst := Rect2(cv(r.position), r.size * _u())
	c.draw_rect(dst, TABLE)
	ink.ops += 1
	# A couple of long scratches, so it is a surface rather than a grey rectangle.
	for i in 3:
		var y: float = r.position.y + r.size.y * (0.22 + 0.28 * float(i))
		c.draw_line(Vector2(dst.position.x, cv(Vector2(0.0, y)).y), Vector2(dst.end.x, cv(Vector2(0.0, y)).y),
			Color(TABLE.lightened(0.16), 0.5), cl(1.4))
	ink.ops += 3
	ink.rect(c, dst, Color(ink.ink, 0.55), 2.4, 9100)
	ink.rect(c, Rect2(cv(COURT.position), COURT.size * _u()), Color(ink.ink, 0.35), 2.0, 9101)


## SPEC 2: a cell's appearance is a PURE FUNCTION of its remaining depth and whether its column falls
## inside a bone shaft. 4 skin / 3 meat / 2 meat or bone / 1 meat or cracked bone / 0 gone.
##
## The five readings have to be tellable apart AT CELL SIZE and across the table, which is what drives
## the spread: skin is warm and pale, meat darkens as it goes down, bone is ivory and cracked bone is
## a grubbier grey, and gone is the steel underneath.
func layer_colour(d: int, bone: bool) -> Color:
	if d <= 0:
		return Color(0, 0, 0, 0)
	if d >= layers:
		return ink.hide_seal if limb_type == "seal" else ink.skin_human
	if d == 1:
		return Color("b6ae96") if bone else Color("63241f")
	if d == 2:
		return Color("ece4cc") if bone else Color("9c3a30")
	return Color("c4695a")


## The slow pass. Only the rows that changed are repainted; the whole 40 x 100 sheet is uploaded in
## one go, which is 16 KB and costs nothing.
func _bake() -> void:
	dirty = false
	_bake_at = ink.t
	if _img == null:
		_img = Image.create(COLS, ROWS, false, Image.FORMAT_RGBA8)
		_row_lo = 0
		_row_hi = ROWS - 1
	var seal: bool = limb_type == "seal" and hide_tint.size() == COLS * ROWS
	var lo: int = clampi(_row_lo, 0, ROWS - 1)
	var hi: int = clampi(_row_hi, 0, ROWS - 1)
	for cyi in range(lo, hi + 1):
		for cxi in COLS:
			var i := cyi * COLS + cxi
			var dv := int(depth[i])
			var col := layer_colour(dv, bone_col[cxi])
			if seal and dv >= layers:
				col = hide_tint[i]
			if _sever[i] == 1:
				col.a = 0.0
			_img.set_pixel(cxi, cyi, col)
	if _tex == null:
		_tex = ImageTexture.create_from_image(_img)
	else:
		_tex.update(_img)
	# The severed piece, once there is one, gets its own sheet so it can slide away on its own.
	if through:
		var im := Image.create(COLS, ROWS, false, Image.FORMAT_RGBA8)
		for cyi in ROWS:
			for cxi in COLS:
				var i := cyi * COLS + cxi
				var col := Color(0, 0, 0, 0)
				if _sever[i] == 1:
					var dv := int(depth[i])
					col = hide_tint[i] if (seal and dv >= layers) else layer_colour(dv, bone_col[cxi])
				im.set_pixel(cxi, cyi, col)
		_tex_cut = ImageTexture.create_from_image(im)
	_row_lo = ROWS - 1
	_row_hi = 0
	_build_edges()


func _part_slide() -> Vector2:
	if not through:
		return Vector2.ZERO
	var k: float = 1.0 - clampf(part_left / maxf(0.01, part_time), 0.0, 1.0)
	return Vector2(0.0, part_slide * k * k)


## The baked sheet, drawn nearest-neighbour so a cell reads as a cell.
func _paint_material(c: CanvasItem) -> void:
	if _tex == null:
		return
	var r := limb_rect()
	var dst := Rect2(cv(r.position), r.size * _u())
	var keep := c.texture_filter
	c.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	c.draw_texture_rect(_tex, dst, false)
	ink.ops += 1
	if through and _tex_cut != null:
		var k: float = 1.0 - clampf(part_left / maxf(0.01, part_time), 0.0, 1.0)
		c.draw_texture_rect(_tex_cut, Rect2(dst.position + _part_slide() * _u(), dst.size), false,
			Color(1, 1, 1, 1.0 - 0.3 * k))
		ink.ops += 1
	c.texture_filter = keep


## The live pass's geometry, rebuilt with the sheet: every boundary between material and nothing,
## MERGED INTO RUNS so an intact limb is four strokes rather than two hundred and eighty. Kind 1 is
## an exposed UPPER face (the cell above it is gone), which also earns the shadow.
func _build_edges() -> void:
	_edges = []
	var cw := cell_w()
	var ch := cell_h()
	var x0 := limb_x0()
	var y0 := COURT.position.y
	# Horizontal faces, merged along x.
	for cyi in ROWS:
		for dir: int in [-1, 1]:
			var run := -1
			var sev := false
			for cxi in range(0, COLS + 1):
				var here := false
				var s := false
				if cxi < COLS:
					var i := cyi * COLS + cxi
					if depth[i] > 0:
						var ny := cyi + dir
						here = ny < 0 or ny >= ROWS or depth[ny * COLS + cxi] == 0
						s = _sever[i] == 1
				if here and run < 0:
					run = cxi
					sev = s
				elif (not here or s != sev) and run >= 0:
					var y: float = y0 + float(cyi + (0 if dir < 0 else 1)) * ch
					_edges.append([Vector2(x0 + float(run) * cw, y), Vector2(x0 + float(cxi) * cw, y),
						1 if dir < 0 else 0, sev])
					run = cxi if here else -1
					sev = s
	# Vertical faces, merged along y.
	for cxi in COLS:
		for dir: int in [-1, 1]:
			var run := -1
			var sev := false
			for cyi in range(0, ROWS + 1):
				var here := false
				var s := false
				if cyi < ROWS:
					var i := cyi * COLS + cxi
					if depth[i] > 0:
						var nx := cxi + dir
						here = nx < 0 or nx >= COLS or depth[cyi * COLS + nx] == 0
						s = _sever[i] == 1
				if here and run < 0:
					run = cyi
					sev = s
				elif (not here or s != sev) and run >= 0:
					var x: float = x0 + float(cxi + (0 if dir < 0 else 1)) * cw
					_edges.append([Vector2(x, y0 + float(run) * ch), Vector2(x, y0 + float(cyi) * ch),
						0, sev])
					run = cyi if here else -1
					sev = s


## Redrawn EVERY frame on the shared wobble clock, whatever the sheet is doing.
func _paint_edges(c: CanvasItem) -> void:
	var slide := _part_slide()
	var seam := Color(ink.deep_red, 0.72)
	var shadow := Color(ink.ink, 0.28)
	var line := Color(ink.ink, 0.85)
	var k := 0
	for e in _edges:
		k += 1
		var a: Vector2 = e[0]
		var b: Vector2 = e[1]
		if bool(e[3]):
			a += slide
			b += slide
		# THE SHADOW UNDER AN EXPOSED UPPER FACE: a soft dark band just inside the material.
		if int(e[2]) == 1:
			c.draw_line(cv(a + Vector2(0.0, 2.4)), cv(b + Vector2(0.0, 2.4)), shadow, cl(3.2))
			ink.ops += 1
		# THE RED SEAM inside every exposed edge, then the ink line over the edge itself. Both wobble:
		# ink.seg is on the 7 Hz boil, so the arm breathes like the paddles and the blade.
		var inward := (b - a).orthogonal().normalized() * 2.0
		ink.seg(c, cv(a - inward), cv(b - inward), seam, 2.6, 9500 + k)
		ink.seg(c, cv(a), cv(b), line, 2.2, 9700 + k)


func _paint_chips(c: CanvasItem) -> void:
	for ch in _chips:
		var col: Color = ch[3]
		col.a = clampf(float(ch[2]) / 0.4, 0.0, 1.0)
		ink.dot(c, cv(Vector2(ch[0])), cl(1.8), col)


func _paint_paddles(c: CanvasItem) -> void:
	for side: int in [-1, 1]:
		var x := paddle_face(side)
		var w := 11.0
		var r := Rect2(x - (w if side > 0 else 0.0), paddle_y - paddle_height * 0.5, w, paddle_height)
		ink.rect(c, Rect2(cv(r.position), r.size * _u()), ink.ink, 3.0, 9200 + side,
			Color(ink.paper.darkened(0.07), 0.96))


## SPEC 4's serve: the blade RINGED and labelled, with a DASHED AIM LINE into the limb.
func _paint_blade(c: CanvasItem) -> void:
	if state == State.PART or state == State.RESULT:
		return
	var at := cv(ball)
	if state == State.SERVE:
		var to := Vector2(limb_x0() + (limb_w() if serve_side < 0 else 0.0), ball.y)
		ink.dashed(c, cv(ball + Vector2(BLADE_R * float(-serve_side), 0.0)), cv(to),
			Color(ink.ink, 0.45), 2.0, 9.0, 7.0)
		ink.circle(c, at, cl(BLADE_R + 7.0), Color(ink.good, 0.85), 2.0, 9301)
		ink.text(c, cv(ball + Vector2(0.0, -BLADE_R - 15.0)), "SPACE", 13.0, Color(ink.good, 0.95), 1)
	# THE DISC, drawn at exactly the radius the cut uses. HARD REQUIREMENT 1.
	ink.circle(c, at, cl(BLADE_R), ink.ink, 3.0, 9302, Color(ink.paper.darkened(0.1), 0.95))
	var spin := cut_t * 9.0
	for i in 12:
		var a: float = spin + TAU * float(i) / 12.0
		var d := Vector2(cos(a), sin(a))
		c.draw_line(cv(ball + d * (BLADE_R - 6.0)), cv(ball + d * BLADE_R), Color(ink.ink, 0.8), cl(2.0))
	ink.ops += 12
	ink.circle(c, at, cl(BLADE_R * 0.30), Color(ink.ink, 0.9), 2.0, 9303, Color(ink.ink, 0.25))


## SPEC 5: a toggle under the board switches patient and regenerates.
func _paint_button(c: CanvasItem) -> void:
	var r := Rect2(cv(_btn_limb.position), _btn_limb.size * _u())
	ink.rect(c, r, Color(ink.ink, 0.7), 2.0, 9401, Color(ink.paper.darkened(0.05), 0.95))
	ink.text(c, Vector2(r.get_center().x, r.get_center().y + cl(5.0)),
		"PATIENT: %s" % ("SEAL FLIPPER" if limb_type == "seal" else "HUMAN ARM"), 13.0,
		Color(ink.label, 0.9), 1)


# ---------------------------------------------------------------------------- net

## What an onlooker needs. The bone layout and the hide are rebuilt from `lt` and `gn` on every
## machine, but THE MATERIAL ITSELF GOES OVER, run-length encoded: it is the board, and an onlooker
## who cannot see how much arm is left is not watching the same game. An uncut limb packs to a couple
## of hundred bytes and a chewed one to a few hundred, and it is only re-encoded when it changes.
## NOTHING THAT CREEPS IS SNAPPED.
func net_pack() -> Dictionary:
	if _rle_rev != _rev:
		_rle_cache = _rle(depth)
		_rle_rev = _rev
	return {"lt": limb_type, "gn": gen, "sa": state, "dp": _rle_cache, "rv": _rev,
		"bl": ball, "vl": vel, "py": paddle_y, "ss": serve_side, "vt": vit, "sk": strokes,
		"jp": jumps, "rm": removed, "ct": cut_t, "pl": part_left, "th": through, "bk": broke,
		"gc": gap_cols, "fl": flatlined, "sc": score, "gr": _grade}


func net_apply(s: Dictionary) -> void:
	var lt := String(s.get("lt", limb_type))
	var gn := int(s.get("gn", gen))
	if lt != limb_type or gn != gen:
		limb_type = lt
		gen = gn
		generate()
	var was_through := through
	through = bool(s.get("th", through))
	var rv := int(s.get("rv", _rev))
	if rv != _rev and s.has("dp"):
		var un := _unrle(s["dp"] as PackedByteArray, COLS * ROWS)
		if un.size() == COLS * ROWS:
			depth = un
			_rev = rv
			_rle_rev = -1
			_bump()
	if through and not was_through:
		tag_severed()
	state = int(s.get("sa", state))
	ball = s.get("bl", ball)
	vel = s.get("vl", vel)
	paddle_y = float(s.get("py", paddle_y))
	serve_side = int(s.get("ss", serve_side))
	vit = float(s.get("vt", vit))
	strokes = int(s.get("sk", strokes))
	jumps = int(s.get("jp", jumps))
	removed = int(s.get("rm", removed))
	cut_t = float(s.get("ct", cut_t))
	part_left = float(s.get("pl", part_left))
	broke = bool(s.get("bk", broke))
	gap_cols = int(s.get("gc", gap_cols))
	flatlined = bool(s.get("fl", flatlined))
	score = int(s.get("sc", score))
	_grade = String(s.get("gr", _grade))


## Run-length encoding, [count, value] byte pairs. Counts over 255 are split.
static func _rle(src: PackedByteArray) -> PackedByteArray:
	var out := PackedByteArray()
	var i := 0
	while i < src.size():
		var v := src[i]
		var n := 1
		while i + n < src.size() and src[i + n] == v and n < 255:
			n += 1
		out.append(n)
		out.append(v)
		i += n
	return out


static func _unrle(src: PackedByteArray, want: int) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(want)
	var at := 0
	var i := 0
	while i + 1 < src.size() and at < want:
		var n: int = src[i]
		var v: int = src[i + 1]
		for k in n:
			if at >= want:
				break
			out[at] = v
			at += 1
		i += 2
	return out


# ---------------------------------------------------------------------------- bot

## The bot keeps the paddle on the blade's line and serves when it is asked to. At skill 1.0 it sits
## dead on it, which returns the blade straight -- that is the flawless run the stump-quality
## reference is calibrated against. Below 1.0 it lags and wanders, so returns come off the paddle at
## an angle, the channel widens, and low enough it misses altogether.
func bot_input(t: float, skill: float) -> Dictionary:
	var dt: float = clampf(t - float(_bot.t), 0.0, 0.1)
	_bot.t = t
	skill = clampf(skill, 0.0, 1.0)
	var aim: float = float(_bot.aim)
	if aim == 0.0:
		aim = COURT.get_center().y
		_bot.aim = aim
	var cur := metres_of_ref(Vector2(_cursor.x, aim))
	var none := {"cursor": cur, "buttons": 0}
	if stamp_waiting() and not frozen:
		if card_left > 0.0:
			_bot.gate = -1.0
			return none
		if float(_bot.gate) < 0.0:
			_bot.gate = lerpf(0.6, 0.18, skill)
		_bot.gate = float(_bot.gate) - dt
		if float(_bot.gate) <= 0.0:
			_bot.gate = -1.0
			_bot.up = true
			return {"cursor": cur, "buttons": BUTTON_ACTION}
		return none
	if not armed():
		return none
	if bool(_bot.up):
		_bot.up = false
		return none
	if state == State.RESULT:
		return {"cursor": cur, "buttons": BUTTON_ACTION}
	if state == State.PART:
		return none
	var want := ball.y
	if skill < 0.999:
		want += sin(t * 2.3) * lerpf(52.0, 0.0, skill) + sin(t * 0.9 + 2.0) * lerpf(26.0, 0.0, skill)
	_bot.aim = lerpf(aim, want, clampf(lerpf(6.0, 40.0, skill) * dt, 0.0, 1.0))
	cur = metres_of_ref(Vector2(_cursor.x, float(_bot.aim)))
	if state == State.SERVE and absf(float(_bot.aim) - ball.y) < 4.0:
		return {"cursor": cur, "buttons": BUTTON_ACTION}
	return {"cursor": cur, "buttons": 0}


# ---------------------------------------------------------------------------- warmup

## scripts/warmup.gd: build and draw both limbs, a chewed channel, chips and a burst once, so nothing
## compiles mid-step (CLAUDE.md: new content that draws for the first time is registered here).
func warm_all() -> void:
	_warm = true
	var keep := limb_type
	for lt: String in ["human", "seal"]:
		limb_type = lt
		generate()
		var y: float = COURT.get_center().y
		cut_sweep(Vector2(COURT.position.x, y), Vector2(COURT.end.x, y))
		_chip_at(COURT.get_center(), 2, 8)
		if shell != null:
			shell.mistake("SAW JUMPED!", shell.area.get_center(), false, 0)
		if panel != null:
			panel.redraw()
	limb_type = keep
	generate()
	if panel != null:
		panel.redraw()


# ---------------------------------------------------------------------------- self-test

## Headless: `godot --headless --path . --fixed-fps 60 tools/minigame_lab.tscn -- --selftest=saw:arcade`
##
## The first three checks are the three the spec says have already gone wrong once, and each is
## MEASURED rather than asserted: the swept footprint against the drawn blade, bone under the blade
## actually driving the slowdown, and the dirty flag on the cutting path. After them the
## stump-quality reference is CALIBRATED against a flawless run played out at 60 Hz (spec 7: if
## flawless play cannot earn "clean", the number is wrong, not the player), and a spectator is made
## to land on the same 4000 cells as the operator.
static func self_test() -> Array:
	var script: GDScript = load("res://scripts/surgery/arcade/saw_arcade.gd")
	var out := []
	var ok := true

	# ---- HARD REQUIREMENT 1: THE CUT FOOTPRINT MUST EQUAL THE DRAWN BLADE ----
	var fp := _footprint_check(script)
	print("[saw self-test] footprint: a straight crossing bit a band %.1f px tall against a %.1f px blade (%+.1f px), reaching %.1f px of a %.1f px limb; one sample alone printed %.1f x %.1f px, roundness error %.3f" % [
		float(fp.band_px), BLADE_R * 2.0, float(fp.band_px) - BLADE_R * 2.0, float(fp.span_px),
		float(fp.limb_px), float(fp.disc_w), float(fp.disc_h), float(fp.round_err)])
	if absf(float(fp.band_px) - BLADE_R * 2.0) > float(fp.cell_h) * 1.5:
		print("[saw self-test] MISS: the bite must be the full width of the disc, not a strip under its centre")
		ok = false
	if absf(float(fp.disc_h) - BLADE_R * 2.0) > float(fp.cell_h) * 1.5 \
			or absf(float(fp.disc_w) - BLADE_R * 2.0) > float(fp.cell_w) * 1.5:
		print("[saw self-test] MISS: one sample's print must be the blade's full diameter both ways")
		ok = false
	if float(fp.round_err) > 0.12:
		print("[saw self-test] MISS: the footprint must be ROUND -- it is %.3f off the disc" % float(fp.round_err))
		ok = false
	if float(fp.span_px) < float(fp.limb_px) - float(fp.cell_w) * 1.5:
		print("[saw self-test] MISS: a full crossing must reach both edges of the limb")
		ok = false

	# ---- HARD REQUIREMENT 2: BONE UNDER THE BLADE DRIVES THE SLOWDOWN ----
	var bn := _bone_check(script)
	print("[saw self-test] bone: over a meat gutter %.2f (speed x%.3f), over an exposed shaft %.2f (speed x%.3f); exposed bone only FAR from the blade read %.2f; chatter at the gate %.2f vs edge to edge %.2f" % [
		float(bn.meat), float(bn.meat_speed), float(bn.bone), float(bn.bone_speed),
		float(bn.elsewhere), float(bn.chatter_gate), float(bn.chatter_full)])
	if float(bn.meat) > 0.001 or float(bn.bone) < 0.9:
		print("[saw self-test] MISS: bone must be read from the cells UNDER the blade")
		ok = false
	if float(bn.elsewhere) > 0.001:
		print("[saw self-test] MISS: bone elsewhere in the limb must not count -- that is the row-scan bug")
		ok = false
	if float(bn.bone_speed) >= 0.999 or float(bn.meat_speed) < 0.999 \
			or float(bn.bone_speed) < 0.83 or float(bn.bone_speed) > 0.95:
		print("[saw self-test] MISS: bone under the blade must slow it 6-16%")
		ok = false
	if float(bn.chatter_full) >= float(bn.chatter_gate):
		print("[saw self-test] MISS: chatter must scale DOWN as bone coverage rises")
		ok = false

	# ---- HARD REQUIREMENT 3: THE DIRTY FLAG ON THE CUTTING PATH ----
	var dt_r := _dirty_check(script)
	print("[saw self-test] dirty flag: a decrement raised it=%s, an orphan removal raised it=%s, a sweep that bit nothing left it down=%s" % [
		"yes" if bool(dt_r.cut) else "NO", "yes" if bool(dt_r.orphan) else "NO",
		"yes" if bool(dt_r.quiet) else "NO"])
	if not bool(dt_r.cut) or not bool(dt_r.orphan) or not bool(dt_r.quiet):
		print("[saw self-test] MISS: every decrement and every orphan removal must mark the sheet dirty")
		ok = false

	# The cutting rules themselves.
	var rl := _rules_check(script)
	print("[saw self-test] rules: the same crossing again took %d more layers (must be 0), a fresh crossing took %d; a stepped diagonal gap completes=%s, two columns short does not=%s; an island of %d cells fell away=%s" % [
		int(rl.again), int(rl.fresh), "yes" if bool(rl.diagonal) else "NO",
		"yes" if bool(rl.not_yet) else "NO", int(rl.island), "yes" if bool(rl.orphaned) else "NO"])
	if int(rl.again) != 0 or int(rl.fresh) <= 0 or not bool(rl.diagonal) or not bool(rl.not_yet) \
			or not bool(rl.orphaned):
		print("[saw self-test] MISS: the cutting rules")
		ok = false

	# ---- SPEC 7'S CALIBRATION, MEASURED ----
	for lt: String in ["human", "seal"]:
		var pf := _perfect_run(script, lt)
		print("[saw self-test] flawless %-5s: %d strokes in %.1f s, removed %d against a %d-cell reference channel x%.2f allowed -> %.3f, stump '%s', score %d %s" % [
			lt, int(pf.strokes), float(pf.t), int(pf.removed), int(pf.reference), float(pf.allow),
			float(pf.ratio), String(pf.word), int(pf.score), String(pf.grade)])
		out.append({"limb": lt, "perfect_ratio": float(pf.ratio), "score": int(pf.score),
			"grade": String(pf.grade)})
		if not bool(pf.through):
			print("[saw self-test] MISS: a flawless run must take the limb off")
			ok = false
		if String(pf.word) != "clean" or String(pf.grade) != "CLEAN":
			print("[saw self-test] MISS: flawless play must earn 'clean' and grade CLEAN -- if it cannot, the reference is wrong, not the player")
			ok = false
		if float(pf.ratio) > 0.95:
			print("[saw self-test] NOTE: flawless play already sits at %.2f of the clean band -- real play has almost no headroom" % float(pf.ratio))

	# The grade bands and the score formula.
	var gr := _grade_check(script)
	print("[saw self-test] grades: flawless %d %s, one jump %d %s, three jumps %d %s, a chewed stump %d %s, flatline %d %s" % [
		int(gr.best), String(gr.best_w), int(gr.one), String(gr.one_w), int(gr.three), String(gr.three_w),
		int(gr.rag), String(gr.rag_w), int(gr.flat), String(gr.flat_w)])
	if String(gr.best_w) != "CLEAN" or String(gr.three_w) == "CLEAN" or String(gr.flat_w) != "MALPRACTICE" \
			or int(gr.flat) != 0 or int(gr.rag) >= int(gr.best):
		print("[saw self-test] MISS: the grade bands")
		ok = false
	# A stump chewed to twice the allowance must cost the grade on its own, with nothing else wrong.
	if String(gr.rag_w) == "CLEAN":
		print("[saw self-test] MISS: a ragged stump alone must lose CLEAN -- the stump IS the score here")
		ok = false

	# SPEC 5's claim about the two patients, measured: the flipper is nearly all bone and gives the
	# blade far less relief than the arm's meat gutters.
	for lt: String in ["human", "seal"]:
		var lc := _limb_check(script, lt)
		print("[saw self-test] %-5s limb: %.0f px wide, %d shafts over %d of %d columns; along one straight pass the blade sat over %.0f%% bone on average, above the gate for %.0f%% of the crossing, crossing the gate %d times" % [
			lt, float(lc.width), int(lc.shafts), int(lc.bone_cols), COLS, float(lc.mean) * 100.0,
			float(lc.over) * 100.0, int(lc.flips)])
		out.append({"limb": lt, "bone_cols": int(lc.bone_cols), "mean_bone": float(lc.mean),
			"shafts": int(lc.shafts), "flips": int(lc.flips)})
		if int(lc.bone_cols) <= 0:
			print("[saw self-test] MISS: a limb with no bone in it")
			ok = false

	# The only botch, and where it leaves the blade.
	var jm := _jump_check(script)
	print("[saw self-test] jump: missing the paddle cost %.1f vitals, threw %d blood marks, and left the blade resting on the %s paddle waiting for Space=%s" % [
		float(jm.cost), int(jm.splats), "left" if int(jm.side) < 0 else "right",
		"yes" if bool(jm.serving) else "NO"])
	if absf(float(jm.cost) - 8.0) > 0.01 or not bool(jm.serving) or int(jm.splats) < 2:
		print("[saw self-test] MISS: the only botch is missing the paddle, and it parks the blade back on it")
		ok = false

	# Both limbs, both hands, end to end.
	for lt: String in ["human", "seal"]:
		for skill: float in [1.0, 0.7, 0.35]:
			var g = script.new()
			var tally := {"done": false, "v": 0.0}
			g.botched.connect(func(a, _r): tally.v += a)
			g.finished.connect(func(_r): tally.done = true)
			g.setup(_case(lt))
			var t: float = run_bot(g, skill, 1.0, hash(lt) + int(skill * 100), 240.0)
			print("[saw self-test] %-5s skill=%.2f  %s  strokes=%3d jumps=%2d removed=%5d ratio=%.2f %-15s vitals=%5.1f score=%3d %-11s time=%5.1fs bill=%4.1f" % [
				lt, skill, "DONE" if bool(tally.done) else "UNFINISHED", g.strokes, g.jumps, g.removed,
				g.stump_ratio(), g.stump_word(), g.vit, g.score, g._grade, t, float(tally.v)])
			out.append({"limb": lt, "skill": skill, "done": bool(tally.done), "score": g.score, "time": t})
			if not bool(tally.done):
				print("[saw self-test] MISS: every hand has to be able to take the limb off")
				ok = false
			g.free()

	# ---- SPECTATOR PARITY: these games replicate, and an onlooker must see the same board ----
	var net := _net_check(script)
	print("[saw self-test] spectator: %d of %d cells differ; removed %d vs %d, vitals %.2f vs %.2f, blade %.2f px apart, limb %s vs %s; worst packed board %d bytes for %d cells" % net)
	if int(net[0]) != 0 or int(net[2]) != int(net[3]) or absf(float(net[4]) - float(net[5])) > 0.02 \
			or float(net[6]) > 1.0 or String(net[7]) != String(net[8]):
		print("[saw self-test] MISS: a spectator does not see the board the operator sees")
		ok = false

	print("[saw self-test] %s" % ("PASS" if ok else "FAIL"))
	return out


static func _case(limb: String) -> Dictionary:
	var pid := "seal" if limb == "seal" else "bob"
	return {"patient_id": pid, "patient": Procedures.patient(pid), "ailment_id": "amputation",
		"step": Procedures.step("amputation", 2), "variant": "", "shift": 1,
		"difficulty": Procedures.difficulty(1),
		"flags": {"sedation": 1.0, "tourniquet": 0.9},
		"seed": hash("saw" + limb), "body": null, "operator": true, "operating": true}


static func _armed(g) -> void:
	var dt := 1.0 / 60.0
	for i in 30:
		g.handle_cursor(Vector2.ZERO, 0, dt)
		g.tick(dt)
	g.handle_cursor(Vector2.ZERO, BUTTON_ACTION, dt)
	g.tick(dt)
	g.handle_cursor(Vector2.ZERO, 0, dt)
	g.tick(dt)


## HARD REQUIREMENT 1, MEASURED. Sweep the blade straight across a fresh limb and look at what it
## actually took: the band must be as tall as the disc is wide, a single sample's print must be the
## disc's full diameter both ways and round, and a crossing must reach both edges of the limb.
static func _footprint_check(script: GDScript) -> Dictionary:
	var g = script.new()
	g.setup(_case("human"))
	var y: float = COURT.get_center().y
	g.cut_sweep(Vector2(COURT.position.x, y), Vector2(COURT.end.x, y))
	var lo := ROWS
	var hi := -1
	var cl_ := COLS
	var ch_ := -1
	for cyi in ROWS:
		for cxi in COLS:
			if g.depth[cyi * COLS + cxi] < g.layers:
				lo = mini(lo, cyi)
				hi = maxi(hi, cyi)
				cl_ = mini(cl_, cxi)
				ch_ = maxi(ch_, cxi)
	var r := {"cell_h": g.cell_h(), "cell_w": g.cell_w(), "limb_px": g.limb_w()}
	r["band_px"] = float(hi - lo + 1) * g.cell_h()
	r["span_px"] = float(ch_ - cl_ + 1) * g.cell_w()
	# One sample on its own, on a fresh limb: the disc's own print, and how round it is.
	var h = script.new()
	h.setup(_case("human"))
	var at := Vector2(COURT.get_center().x, y)
	h.cut_at(at)
	var xs := COLS
	var xe := -1
	var ys := ROWS
	var ye := -1
	var worst := 0.0
	var bit := 0
	for cyi in ROWS:
		for cxi in COLS:
			if h.depth[cyi * COLS + cxi] >= h.layers:
				continue
			bit += 1
			xs = mini(xs, cxi)
			xe = maxi(xe, cxi)
			ys = mini(ys, cyi)
			ye = maxi(ye, cyi)
			# Every bitten cell's centre must lie inside the blade. That is what "round" means here.
			worst = maxf(worst, h.cell_centre(cxi, cyi).distance_to(at) / BLADE_R)
	r["disc_h"] = float(ye - ys + 1) * h.cell_h()
	r["disc_w"] = float(xe - xs + 1) * h.cell_w()
	r["round_err"] = absf(worst - 1.0)
	r["bit"] = bit
	g.free()
	h.free()
	return r


## HARD REQUIREMENT 2, MEASURED: bone read from the cells UNDER the disc and nowhere else.
static func _bone_check(script: GDScript) -> Dictionary:
	var g = script.new()
	g.setup(_case("human"))
	var r := {}
	var y: float = COURT.get_center().y
	# The first meat gutter, and the middle of the FIRST contiguous bone shaft.
	var meat_col := -1
	var lo := -1
	var hi := -1
	for cxi in COLS:
		if g.bone_col[cxi]:
			if lo < 0:
				lo = cxi
			if hi < 0 or cxi == hi + 1:
				hi = cxi
		elif meat_col < 0 and cxi > 1:
			meat_col = cxi
	# Expose everything down to the bone layer, the way play would.
	for i in COLS * ROWS:
		g.depth[i] = BONE_AT
	g.ball = Vector2(g.cell_centre(meat_col, ROWS / 2).x, y)
	r["meat"] = g.bone_under_blade()
	r["meat_speed"] = _speed_scale(g, float(r.meat))
	g.ball = Vector2(g.cell_centre(int((lo + hi) / 2), ROWS / 2).x, y)
	r["bone"] = g.bone_under_blade()
	r["bone_speed"] = _speed_scale(g, float(r.bone))
	# AND THE TRAP THE SPEC NAMES. Leave the bone exposed only in rows a long way from the blade and
	# put meat under it: anything summarising a row or the limb would still report bone here.
	for cyi in ROWS:
		var far: bool = absf(g.cell_centre(0, cyi).y - y) > BLADE_R * 2.0
		for cxi in COLS:
			g.depth[cyi * COLS + cxi] = BONE_AT if far else (g.layers - 1)
	r["elsewhere"] = g.bone_under_blade()
	r["chatter_gate"] = _chatter_scale(g, g.bone_gate + 0.001)
	r["chatter_full"] = _chatter_scale(g, 1.0)
	g.free()
	return r


static func _speed_scale(g, frac: float) -> float:
	if frac <= g.bone_gate:
		return 1.0
	var over: float = clampf((frac - g.bone_gate) / maxf(0.001, 1.0 - g.bone_gate), 0.0, 1.0)
	return 1.0 - lerpf(g.bone_slow_min, g.bone_slow_max, over)


static func _chatter_scale(g, frac: float) -> float:
	if frac <= g.bone_gate:
		return 0.0
	var over: float = clampf((frac - g.bone_gate) / maxf(0.001, 1.0 - g.bone_gate), 0.0, 1.0)
	return g.chatter * lerpf(1.0, g.chatter_at_full, over)


## HARD REQUIREMENT 3, MEASURED: every decrement and every orphan removal marks the sheet dirty, and
## a sweep that changed nothing does not claim it did.
static func _dirty_check(script: GDScript) -> Dictionary:
	var g = script.new()
	g.setup(_case("human"))
	var r := {}
	g.dirty = false
	g.cut_at(COURT.get_center())
	r["cut"] = g.dirty
	for i in COLS * ROWS:
		g.depth[i] = 0
	g._touch_id += 1
	g.dirty = false
	g.cut_at(COURT.get_center())
	r["quiet"] = not g.dirty
	# An island with material in it, touching neither end of the court.
	for i in COLS * ROWS:
		g.depth[i] = 0
	for cyi in range(40, 46):
		for cxi in range(10, 16):
			g.depth[cyi * COLS + cxi] = g.layers
	g.dirty = false
	var fell: int = g.prune_orphans()
	r["orphan"] = g.dirty and fell == 36
	g.free()
	return r


static func _rules_check(script: GDScript) -> Dictionary:
	var g = script.new()
	g.setup(_case("human"))
	var r := {}
	var y: float = COURT.get_center().y
	var before: int = g.removed
	g.cut_sweep(Vector2(COURT.position.x, y), Vector2(COURT.end.x, y))
	var one: int = g.removed - before
	# ONE DECREMENT PER CELL PER CROSSING: the same crossing again must take nothing.
	g.cut_sweep(Vector2(COURT.end.x, y), Vector2(COURT.position.x, y))
	r["again"] = g.removed - before - one
	# A fresh crossing may take the next layer.
	g._touch_id += 1
	before = g.removed
	g.cut_sweep(Vector2(COURT.position.x, y), Vector2(COURT.end.x, y))
	r["fresh"] = g.removed - before
	# COMPLETION IS CONNECTIVITY: a stepped diagonal gap counts; a straight row is not required.
	for i in COLS * ROWS:
		g.depth[i] = g.layers
	for cxi in COLS:
		g.depth[(20 + cxi) * COLS + cxi] = 0
	r["diagonal"] = g.gap_reach() >= COLS - 1
	for cxi in range(COLS - 2, COLS):
		g.depth[(20 + cxi) * COLS + cxi] = g.layers
	r["not_yet"] = g.gap_reach() < COLS - 1
	# ORPHANS FALL AWAY.
	for i in COLS * ROWS:
		g.depth[i] = 0
	for cyi in range(50, 55):
		for cxi in range(4, 9):
			g.depth[cyi * COLS + cxi] = 2
	r["island"] = 25
	r["orphaned"] = g.prune_orphans() == 25
	g.free()
	return r


## SPEC 5's two patients, measured: how much bone each limb is, and how much of a straight crossing
## the blade actually spends over it. The trade the toggle exists for has to show up in the numbers.
static func _limb_check(script: GDScript, limb: String) -> Dictionary:
	var g = script.new()
	g.setup(_case(limb))
	var n := 0
	for cxi in COLS:
		if g.bone_col[cxi]:
			n += 1
	# Take the limb down to the bone layer and walk the blade across it at the court's mid-height.
	for i in COLS * ROWS:
		g.depth[i] = BONE_AT
	var y: float = COURT.get_center().y
	var total := 0.0
	var over := 0
	var flips := 0
	var was := false
	var steps := 60
	for i in steps:
		g.ball = Vector2(lerpf(g.limb_x0(), g.limb_x0() + g.limb_w(), float(i) / float(steps - 1)), y)
		var f: float = g.bone_under_blade()
		total += f
		var now: bool = f > g.bone_gate
		if i > 0 and now != was:
			flips += 1
		was = now
		if now:
			over += 1
	# How many separate shafts the blade meets: the arm is two long drags, the flipper a fan of
	# short ones, which is what makes the flipper harder to hold a line through.
	var shafts := 0
	for cxi in COLS:
		if g.bone_col[cxi] and (cxi == 0 or not g.bone_col[cxi - 1]):
			shafts += 1
	var r := {"width": g.limb_w(), "bone_cols": n, "mean": total / float(steps),
		"over": float(over) / float(steps), "flips": flips, "shafts": shafts}
	g.free()
	return r


## SPEC 7'S CALIBRATION, MEASURED rather than assumed. A hand that keeps the paddle exactly on the
## blade returns it dead straight, so the cut is one channel: the very thing the reference describes.
## Whatever that run removes is what flawless costs, and it has to come out "clean" and CLEAN.
static func _perfect_run(script: GDScript, limb: String) -> Dictionary:
	var g = script.new()
	g.setup(_case(limb))
	_armed(g)
	var dt := 1.0 / 60.0
	var t := 0.0
	while t < 180.0 and g.state != State.RESULT and not g.done:
		t += dt
		var aim: Vector2 = g.metres_of_ref(Vector2(480.0, g.ball.y))
		var btn: int = BUTTON_ACTION if g.state == State.SERVE else 0
		g.handle_cursor(aim, btn, dt)
		g.tick(dt)
	var r := {"strokes": g.strokes, "t": g.cut_t, "removed": g.removed, "through": g.through,
		"jumps": g.jumps, "reference": g.reference_channel(), "allow": g.overlap_allow,
		"ratio": g.stump_ratio(), "word": g.stump_word(), "score": g.grade_score(),
		"grade": g.grade_word()}
	g.free()
	return r


static func _grade_check(script: GDScript) -> Dictionary:
	var g = script.new()
	g.setup(_case("human"))
	var r := {}
	g.cut_t = 14.0
	g.removed = int(g.reference_channel())
	g.jumps = 0
	g.vit = 100.0
	r["best"] = g.grade_score()
	r["best_w"] = g.grade_word()
	g.jumps = 1
	g.vit = 92.0
	r["one"] = g.grade_score()
	r["one_w"] = g.grade_word()
	g.jumps = 3
	g.vit = 76.0
	r["three"] = g.grade_score()
	r["three_w"] = g.grade_word()
	g.jumps = 0
	g.vit = 100.0
	g.removed = int(g.reference_channel() * g.overlap_allow * 2.0)
	r["rag"] = g.grade_score()
	r["rag_w"] = g.grade_word()
	g.flatlined = true
	g.vit = 0.0
	r["flat"] = g.grade_score()
	r["flat_w"] = g.grade_word()
	g.free()
	return r


## THE ONLY BOTCH: missing the paddle, and the blade parked back on the paddle it got past.
static func _jump_check(script: GDScript) -> Dictionary:
	var g = script.new()
	g.setup(_case("human"))
	_armed(g)
	var v0: float = g.vit
	var n0: int = g.shell._splats.size()
	g.paddle_y = COURT.position.y + 70.0
	g.ball = Vector2(COURT.position.x + BLADE_R, COURT.end.y - 60.0)
	g.vel = Vector2(-1.0, 0.0)
	g.state = State.CUT
	g._at_paddle(-1)
	var r := {"cost": v0 - g.vit, "splats": g.shell._splats.size() - n0, "side": g.serve_side,
		"serving": g.state == State.SERVE and absf(g.ball.x - (COURT.position.x + BLADE_R)) < 0.01}
	g.free()
	return r


## SPECTATOR PARITY. The operator plays; the onlooker only ever gets net_state and must land on the
## same 4000 CELLS, not merely the same numbers -- the board IS the progress bar here.
static func _net_check(script: GDScript) -> Array:
	var op = script.new()
	var spec = script.new()
	op.setup(_case("human"))
	var sctx := _case("human")
	sctx["operator"] = false
	spec.setup(sctx)
	var dt := 1.0 / 60.0
	var t := 0.0
	var k := 0
	var worst := 0
	while t < 240.0 and not op.done:
		t += dt
		var inp: Dictionary = op.bot_input(t, 0.8)
		op.handle_cursor(inp.get("cursor", Vector2.ZERO), int(inp.get("buttons", 0)), dt)
		op.tick(dt)
		spec.tick(dt)
		k += 1
		if k % 3 == 0:
			var st: Dictionary = op.net_state()
			worst = maxi(worst, (st.get("dp", PackedByteArray()) as PackedByteArray).size())
			spec.apply_net_state(st)
	spec.apply_net_state(op.net_state())
	spec.tick(dt)
	var diff := 0
	for i in COLS * ROWS:
		if op.depth[i] != spec.depth[i]:
			diff += 1
	var r := [diff, COLS * ROWS, op.removed, spec.removed, op.vit, spec.vit,
		op.ball.distance_to(spec.ball), op.limb_type, spec.limb_type, worst, COLS * ROWS]
	op.free()
	spec.free()
	return r
