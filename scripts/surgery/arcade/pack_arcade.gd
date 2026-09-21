extends "res://scripts/surgery/arcade/arcade_game.gd"
## ARCADE SURGERY (docs/ARCADE_SURGERY.md) 5.3 and 5.7 -- WHACK! then WRAP!. Step "dress" of a
## gunshot wound, `gauze` x1, variant `pack`. The arcade rebuild of scripts/surgery/games/gauze.gd's
## pack variant. ONE step, TWO stages, two command cards.
##
## Stage A, WHACK! -- whack-a-mole. Rhyme: the wound is a board and the bleeders are the moles.
##   The bullet tract is drawn from above. A bleeder sits where the slug was lying and ONE MORE SITS
##   AT EVERY WALL YOU TORE ON THE WAY OUT: `tears` comes over from DODGE! and your mistakes follow
##   you into the next step. One or two of them spurt at a time; slap a wad on one while it is up
##   and it takes two hits to plug, three for the bed it came out of. Take too long over one and it
##   soaks through five seconds later and wants another.
##   Miss, and the wad lands on the skin and stays there, which is not where gauze goes.
##   Blood rises up the panel the whole time, faster the more of them are open, and if it reaches
##   the top the wound gushes and you start again halfway up.
##
## Stage B, WRAP! -- Snake. The board and the rules are wrap_snake.gd, shared with the stump. How
##   many of the wound's cells are still BLEEDING is 1 - pack_quality: whatever you let happen in
##   stage A is the routing puzzle you get in stage B.
##
## Result {"dressed": true, "pack_quality": q, "dress_marks": "..."}.

const SnakeScript := preload("res://scripts/surgery/arcade/wrap_snake.gd")

const PHI := 0.6180339887498949

enum Stage { WHACK, WRAP }

# -- the tract --------------------------------------------------------------------------------
@export_range(20.0, 58.0, 1.0) var tract_reach := 42.0      ## mm from the centre to each end
@export_range(2.0, 20.0, 0.5) var tract_wander := 13.0      ## mm the tract may stray up and down
@export_range(2.0, 16.0, 0.5) var tract_half_mm := 6.5      ## half-width of the tract on the diagram

# -- the bleeders -----------------------------------------------------------------------------
@export_range(1, 9) var min_bleeders := 3
@export_range(1, 9) var max_bleeders := 7
## Wads an ordinary bleeder wants, seeded between the two, so they are not all the same job.
@export_range(1, 6) var hits_per_bleeder := 2
@export_range(1, 6) var hits_per_bleeder_most := 3
## The bed the slug was lying in is always the worst of them.
@export_range(1, 6) var hits_for_bed := 3
## How far apart two bleeders must sit on the diagram, and the step used to shuffle a clustered
## tear along the tract until it has that much room.
@export_range(2.0, 30.0, 0.5) var tear_spread_mm := 11.0
@export_range(0.01, 0.3, 0.005) var tear_spread_arc := 0.06
## The most wads one bleeder may want after other tears have been merged into it.
@export_range(1, 9) var merge_cap := 5
## How long one stays up, before difficulty.
@export_range(0.2, 4.0, 0.05) var up_time := 1.1
@export_range(0.0, 2.0, 0.02) var pop_min := 0.30
@export_range(0.0, 3.0, 0.02) var pop_max := 0.62
@export_range(1, 4) var up_at_once := 2
## Two are only ever up together once more than this many are still open.
@export_range(1, 8) var two_up_from := 3
## How close a click has to be, in mm.
@export_range(2.0, 20.0, 0.5) var hit_mm := 9.0
## A wad that lands within this long of one ducking still counts. Nobody has frame-perfect hands.
@export_range(0.0, 0.5, 0.01) var duck_grace := 0.12
## Longer than this from the first hit to plugged and it soaks through...
@export_range(0.5, 12.0, 0.1) var slow_seconds := 4.0
## ...this long afterwards, and wants one more wad.
@export_range(0.5, 12.0, 0.1) var soak_after := 5.0
@export_range(0.0, 10.0, 0.1) var miss_botch := 1.2

# -- the flood --------------------------------------------------------------------------------
@export_range(0.0, 1.0, 0.01) var flood_start := 0.45
## With the bullet somehow still in the wound.
@export_range(0.0, 1.0, 0.01) var flood_start_loaded := 0.65
@export_range(0.0, 0.4, 0.005) var flood_rate := 0.055
@export_range(0.0, 10.0, 0.5) var gush_botch := 3.0
@export_range(0.0, 1.0, 0.01) var gush_reset := 0.7

# -- the kidney (shift 3 and up) --------------------------------------------------------------
@export_range(1, 9) var kidney_from_shift := 3
@export_range(1.0, 30.0, 0.5) var kidney_every_min := 6.0
@export_range(1.0, 30.0, 0.5) var kidney_every_max := 10.0
@export_range(0.1, 5.0, 0.05) var kidney_up := 0.9
@export_range(0.0, 10.0, 0.5) var kidney_botch := 2.0

# -- the roll ---------------------------------------------------------------------------------
@export_range(1.0, 14.0, 0.25) var roll_speed := 5.0         ## cells a second, before difficulty
@export_range(20, 200) var roll_cells := 60                  ## cells of bandage on the roll
@export_range(1, 3) var layers_needed := 1                   ## a dry wound cell; a bleeding one wants one more
@export_range(1, 4) var layer_cap := 3
@export_range(0.5, 10.0, 0.1) var soak_seconds := 4.5
@export_range(0.1, 3.0, 0.05) var respawn_seconds := 0.6
@export_range(0.0, 10.0, 0.5) var tangle_botch := 2.0
@export_range(0.0, 10.0, 0.5) var wrap_soak_botch := 2.0
@export_range(0.0, 10.0, 0.1) var wrap_soak_cooldown := 2.0
@export_range(0.0, 10.0, 0.5) var runout_botch := 3.0

# -- a jolt -----------------------------------------------------------------------------------
@export_range(0, 10) var jolt_cells := 3
@export_range(0.0, 10.0, 0.5) var jolt_botch := 2.0
@export_range(0.0, 5.0, 0.05) var jolt_cooldown := 0.8

# -- audio ------------------------------------------------------------------------------------
@export var wad_cue := "surgery_pack"
@export var plug_cue := "surgery_forceps_squelch"
@export var miss_cue := "surgery_swish"
@export var gush_cue := "surgery_saw_squelch"
@export var tangle_cue := "surgery_tear"
@export var layer_cue := "surgery_pack"
@export var runout_cue := "surgery_forceps_clink"
@export var turn_cue := "surgery_swish"
@export_range(-40.0, 0.0, 1.0) var wad_volume := -10.0
@export_range(-40.0, 0.0, 1.0) var turn_volume := -22.0

# ---- replicated state ----
var stage: int = Stage.WHACK
var flood := 0.45
var peak_flood := 0.45
var gushes := 0
var late_soaks := 0
var pack_quality := 1.0
var cursor := Vector2.ZERO
var wads: Array = []              ## [Vector2] where a wad landed on the skin, panel mm
var kidney_at := Vector2.ZERO
var kidney_left := 0.0            ## seconds the kidney is up for -- CREEPS
var kidney_next := 0.0            ## seconds until the next one -- CREEPS
## Nothing new comes up while this is running -- the gap belongs to the BOARD, not to one bleeder,
## or the next one is always already overdue and there is never a moment with nothing to hit.
var pop_gap := 0.0                ## CREEPS
var kidneys := 0                  ## how many have been up, so the shift-3 path can be checked
var flash := 0.0
var hit_flash := 0.0
var snake: SnakeScript = null

## Per bleeder, all the same length. Index 0 is always the bullet bed.
var b_pos: Array = []             ## Vector2, panel mm
var b_arc: Array = []             ## 0..1 along the tract, for the diagram and for the carry-forward
var b_need: Array = []            ## int, wads it wants
var b_hits: Array = []            ## int
var b_up: Array = []              ## float seconds still up (0 = down) -- CREEPS
var b_next: Array = []            ## float seconds until it may pop -- CREEPS
var b_first: Array = []           ## play_t of the first hit, or -1
var b_soak: Array = []            ## play_t it soaks through at, or -1
var b_done: Array = []            ## bool, plugged
var b_bed: Array = []             ## bool, the bullet's own bed

# ---- derived from the seed ----
var tract: Array = []             ## Vector2 centreline, panel mm
var tract_len: Array = []         ## cumulative arc length, same size
var tears_in := 0

# ---- local ----
var _t := 0.0
var _rng := RandomNumberGenerator.new()
var _soak_cd := 0.0
var _jolt_cd := 0.0
var _seen_gushes := 0
var _seen_tangles := 0
var _seen_soaks := 0

# ---- bot ----
var _bt := 0.0
var _b_cur := Vector2.ZERO
var _b_target := -1
var _b_seq := 0
var _b_err := Vector2.ZERO
var _b_react := 0.0
var _b_prev := 0
var _b_cell := Vector2i(-9, -9)
var _b_want := Vector2i.ZERO


# ---------------------------------------------------------------------------- setup

func card_word_for_start() -> String:
	return "WHACK!"


func build_game() -> void:
	_rng.seed = int(ctx.get("seed", 1)) ^ 0x9ac5
	_build_tract()
	_build_bleeders()
	var flags: Dictionary = ctx.get("flags", {})
	var out = flags.get("bullet_removed", true)
	flood = flood_start if bool(out) else flood_start_loaded
	peak_flood = flood
	cursor = Vector2.ZERO
	_b_cur = Vector2.ZERO
	# The FIRST one comes sooner than the cadence: WHACK! is often over inside six seconds, so a
	# full interval up front means the shift-3 twist would hardly ever actually happen.
	kidney_next = _rng.randf_range(kidney_every_min * 0.35, kidney_every_min * 0.75)
	kidney_at = Vector2(_rng.randf_range(-40.0, 40.0), _rng.randf_range(-26.0, 26.0))
	_update_progress()


## The tract, top-down and stylised: one seeded run across the panel with a few bends in it. It is
## its own shape rather than DODGE!'s channel because each step gets its own seed, so the two would
## not line up anyway -- what actually carries over between them is the `tears`, not the geometry.
func _build_tract() -> void:
	var ctrl: Array = []
	var n := 5
	var y := _rng.randf_range(-tract_wander, tract_wander) * 0.5
	for i in n:
		var x: float = lerpf(-tract_reach, tract_reach, float(i) / float(n - 1))
		ctrl.append(Vector2(x, clampf(y, -tract_wander, tract_wander)))
		y += _rng.randf_range(-tract_wander, tract_wander) * 0.9
	tract.clear()
	var steps := 48
	for s in steps + 1:
		var u: float = float(s) / float(steps) * float(n - 1)
		var i: int = clampi(int(floor(u)), 0, n - 2)
		var f: float = u - float(i)
		var p0: Vector2 = ctrl[maxi(0, i - 1)]
		var p1: Vector2 = ctrl[i]
		var p2: Vector2 = ctrl[i + 1]
		var p3: Vector2 = ctrl[mini(n - 1, i + 2)]
		tract.append(_catmull(p0, p1, p2, p3, f))
	tract_len.clear()
	var acc := 0.0
	tract_len.append(0.0)
	for i in range(1, tract.size()):
		acc += (tract[i] as Vector2).distance_to(tract[i - 1])
		tract_len.append(acc)


func _catmull(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, t: float) -> Vector2:
	var t2 := t * t
	var t3 := t2 * t
	return 0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2
		+ (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3)


## A point on the centreline at arc position 0..1.
func at_arc(u: float) -> Vector2:
	if tract.is_empty():
		return Vector2.ZERO
	var want: float = clampf(u, 0.0, 1.0) * float(tract_len[tract_len.size() - 1])
	for i in range(1, tract_len.size()):
		if float(tract_len[i]) >= want:
			var a: float = float(tract_len[i - 1])
			var b: float = float(tract_len[i])
			var f: float = 0.0 if b - a < 0.0001 else (want - a) / (b - a)
			return (tract[i - 1] as Vector2).lerp(tract[i], f)
	return tract[tract.size() - 1]


## The bullet bed, one bleeder per recorded tear, then seeded extras up to the minimum.
##
## CARRY-FORWARD from DODGE!: `tears` is an Array of plain floats, one per wall contact in the
## order they happened, each the arc position along the wound tract -- 0 at the mouth, 1 at the
## bullet bed -- in forceps.gd's own frame of reference. A clean run emits an empty array and the
## legacy forceps step emits nothing at all, so both have to land on the seeded-extras path.
##
## Contacts CLUSTER: clipping the same bend three times in half a second gives three arcs inside
## 0.04 of each other. Stacked on the diagram they would be one unclickable blob, so each one is
## spread along the tract until it has room, and a tear with nowhere left to go is MERGED into the
## bleeder already there, which then wants another wad. Tearing the same wall twice is worse than
## tearing two, which is the right answer anyway.
func _build_bleeders() -> void:
	var flags: Dictionary = ctx.get("flags", {})
	var tears: Array = []
	var raw = flags.get("tears", [])
	if raw is Array:
		for v in raw:
			if v is float or v is int:
				tears.append(clampf(float(v), 0.0, 1.0))
	tears_in = tears.size()
	b_pos.clear(); b_arc.clear(); b_need.clear(); b_hits.clear()
	b_up.clear(); b_next.clear(); b_first.clear(); b_soak.clear(); b_done.clear(); b_bed.clear()
	_add_bleeder(1.0, true)                      # the bed, at the deep end where the slug sat
	for u: float in tears:
		_add_bleeder(clampf(u, 0.08, 0.94), false)
	var guard := 0
	while b_pos.size() < mini(min_bleeders, max_bleeders) and guard < 40:
		guard += 1
		_add_bleeder(_rng.randf_range(0.12, 0.88), false)


## Put one on the board at this arc position, shuffling it along the tract until it has room. Full
## board, or no room anywhere: the nearest one takes the damage instead.
func _add_bleeder(u: float, bed: bool) -> void:
	var here: float = clampf(u, 0.06, 1.0)
	if b_pos.size() < max_bleeders:
		for k in 9:
			var off: float = 0.0 if k == 0 else tear_spread_arc * float((k + 1) / 2) * (1.0 if k % 2 == 1 else -1.0)
			var a: float = clampf(here + off, 0.06, 1.0)
			# Off the centreline a touch, so they are not a row of dots on a wire.
			var p: Vector2 = at_arc(a) + Vector2(_rng.randf_range(-1.0, 1.0),
				_rng.randf_range(-1.0, 1.0)) * tract_half_mm * 0.55
			if not _room_for(p):
				continue
			b_arc.append(a)
			b_pos.append(p)
			b_bed.append(bed)
			b_need.append(hits_for_bed if bed else _rng.randi_range(hits_per_bleeder,
				maxi(hits_per_bleeder, hits_per_bleeder_most)))
			b_hits.append(0)
			b_up.append(0.0)
			b_next.append(_rng.randf_range(pop_min, pop_max) * float(b_pos.size()) * 0.6)
			b_first.append(-1.0)
			b_soak.append(-1.0)
			b_done.append(false)
			return
	var near := _nearest(at_arc(here))
	if near >= 0:
		b_need[near] = mini(int(b_need[near]) + 1, merge_cap)


func _room_for(p: Vector2) -> bool:
	for q: Vector2 in b_pos:
		if p.distance_to(q) < tear_spread_mm:
			return false
	return true


func _nearest(p: Vector2) -> int:
	var best := -1
	var bd := 1e9
	for i in b_pos.size():
		var d: float = p.distance_to(b_pos[i])
		if d < bd:
			bd = d
			best = i
	return best


func open_bleeders() -> int:
	var n := 0
	for i in b_done.size():
		if not bool(b_done[i]):
			n += 1
	return n


# ---------------------------------------------------------------------------- playing

func keys() -> Array:
	if play_state == Play.DONE:
		return []
	if stage == Stage.WHACK:
		return [["Mouse", "the wad"], ["LMB", "pack a bleeder"]]
	return [["WASD / arrows", "steer the roll"]]


func hint() -> String:
	var base := super.hint()
	if base != "":
		return base
	if play_state == Play.DONE:
		return "Packed and dressed."
	if stage == Stage.WHACK:
		if flood > 0.85:
			return "It is about to go over. Plug something."
		if tears_in > 0 and open_bleeders() > min_bleeders:
			return "Every wall you tore on the way out is bleeding."
		return "Hit them while they are spurting, twice each."
	if snake == null:
		return ""
	if snake.respawn > 0.0:
		return "Tangled. Cutting it and starting again."
	if snake.roll_left < 12:
		return "The roll is nearly out."
	return "Cross your own bandage only on the wound."


func play(p: Vector2, _buttons: int, edges: int, _delta: float) -> void:
	if stage == Stage.WHACK:
		cursor = p
		if edges & (BUTTON_PRIMARY | BUTTON_ACTION):
			_slap(p)
		return
	if snake == null:
		return
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


## A wad of gauze, thrown at the panel.
func _slap(p: Vector2) -> void:
	if kidney_left > 0.0 and p.distance_to(kidney_at) <= hit_mm * 1.2:
		kidney_left = 0.0
		flash = 0.6
		shake(0.8)
		cost(kidney_botch, "That was a kidney.")
		return
	var best := -1
	var bd := hit_mm
	for i in b_pos.size():
		if bool(b_done[i]) or float(b_up[i]) <= -duck_grace:
			continue
		var d: float = p.distance_to(b_pos[i])
		if d <= bd:
			bd = d
			best = i
	if best < 0:
		wads.append(p)
		while wads.size() > 8:
			wads.pop_front()
		flash = maxf(flash, 0.3)
		audio(miss_cue, -16.0, 0.15)
		cost(miss_botch, "Packed gauze onto the skin, not into the wound")
		return
	_hit(best)


func _hit(i: int) -> void:
	b_hits[i] = int(b_hits[i]) + 1
	hit_flash = 0.25
	audio(wad_cue, wad_volume, 0.12)
	if float(b_first[i]) < 0.0:
		b_first[i] = play_t
	# Straight out of the grace window as well as down, or a fast double tap lands twice.
	b_up[i] = -duck_grace
	b_next[i] = _rng.randf_range(pop_min, pop_max)
	pop_gap = maxf(pop_gap, float(b_next[i]))
	if int(b_hits[i]) < int(b_need[i]):
		return
	b_done[i] = true
	audio(plug_cue, -8.0, 0.1)
	# Slow work bleeds again from underneath. It only gets to do that once.
	if float(b_soak[i]) < 0.0 and play_t - float(b_first[i]) > slow_seconds:
		b_soak[i] = play_t + soak_after


func advance(delta: float) -> void:
	_soak_cd = maxf(0.0, _soak_cd - delta)
	_jolt_cd = maxf(0.0, _jolt_cd - delta)
	if stage == Stage.WHACK:
		_advance_whack(delta)
	else:
		_advance_wrap(delta)
	_update_progress()


func _advance_whack(delta: float) -> void:
	_moles(delta)
	_kidney(delta)
	# Blood comes up the panel like water, and how fast is how many of them are still open.
	var share: float = float(open_bleeders()) / maxf(1.0, float(b_done.size()))
	flood = clampf(flood + flood_rate * diff * share * delta, 0.0, 1.0)
	peak_flood = maxf(peak_flood, flood)
	if flood >= 1.0:
		gushes += 1
		flood = gush_reset
		flash = 0.7
		shake(1.0)
		cost(gush_botch, "The wound gushed while it was open")
	if open_bleeders() == 0:
		_to_wrap()


func _moles(delta: float) -> void:
	var up_now := 0
	pop_gap = maxf(0.0, pop_gap - delta)
	for i in b_pos.size():
		# A bleeder that was packed too slowly soaks through and wants another wad.
		if bool(b_done[i]) and float(b_soak[i]) >= 0.0 and play_t >= float(b_soak[i]):
			b_soak[i] = -1.0
			b_done[i] = false
			b_need[i] = int(b_hits[i]) + 1
			b_next[i] = 0.0
			late_soaks += 1
			flash = maxf(flash, 0.35)
			audio(gush_cue, -13.0, 0.1)
		if bool(b_done[i]):
			continue
		if float(b_up[i]) > 0.0:
			b_up[i] = float(b_up[i]) - delta
			if float(b_up[i]) <= 0.0:
				b_up[i] = 0.0
				b_next[i] = _rng.randf_range(pop_min, pop_max)
				pop_gap = maxf(pop_gap, float(b_next[i]))
			else:
				up_now += 1
		else:
			# Below zero is the grace window: a wad that lands just late still counts.
			b_next[i] = float(b_next[i]) - delta
			b_up[i] = maxf(float(b_up[i]) - delta, -duck_grace)
	# One or two up at a time: two only once the wound is properly full of them, so a three-bleeder
	# job is a tense wait on each one rather than a board that always has a target on it.
	var open: int = open_bleeders()
	var want: int = mini(up_at_once if open > two_up_from else 1, open)
	var guard := 0
	while up_now < want and guard < 8 and pop_gap <= 0.0:
		guard += 1
		var pick := -1
		var worst := 0.0
		for i in b_pos.size():
			if bool(b_done[i]) or float(b_up[i]) > 0.0 or float(b_next[i]) > 0.0:
				continue
			if pick < 0 or float(b_next[i]) < worst:
				worst = float(b_next[i])
				pick = i
		if pick < 0:
			break
		b_up[pick] = up_time / sqrt(diff)
		# They come up one at a time even when two slots are free, so the board is read, not swept.
		pop_gap = _rng.randf_range(pop_min, pop_max) * 0.45
		up_now += 1


func _kidney(delta: float) -> void:
	if int(ctx.get("shift", 1)) < kidney_from_shift:
		return
	if kidney_left > 0.0:
		kidney_left = maxf(0.0, kidney_left - delta)
		return
	kidney_next -= delta
	if kidney_next > 0.0:
		return
	kidney_next = _rng.randf_range(kidney_every_min, kidney_every_max)
	kidney_left = kidney_up
	kidneys += 1
	kidney_at = Vector2(_rng.randf_range(-44.0, 44.0), _rng.randf_range(-28.0, 28.0))


## Stage A is over. What the packing was worth decides how much of the dressing is a fight.
func _to_wrap() -> void:
	var rise: float = clampf((peak_flood - flood_start) / maxf(0.05, 1.0 - flood_start), 0.0, 1.0)
	# Snapped HERE, not on the wire, so a spectator building the same board off the replicated
	# number lays out exactly the same bleeding cells the operator did.
	pack_quality = snappedf(clampf(1.0 - 0.60 * rise - 0.10 * float(late_soaks) - 0.14 * float(gushes)
		- 0.03 * float(wads.size()), 0.05, 1.0), 0.01)
	stage = Stage.WRAP
	_build_snake()
	show_card("WRAP!")


func _build_snake() -> void:
	snake = SnakeScript.new()
	snake.base_need = layers_needed
	snake.max_layers = layer_cap
	snake.roll_max = roll_cells
	snake.speed_cells = roll_speed
	snake.soak_time = soak_seconds
	snake.respawn_time = respawn_seconds
	# The dressing goes over where the wound is, not in the middle of the panel for its own sake.
	var mid: Vector2 = at_arc(0.5)
	snake.anchor = Vector2i(
		clampi(int((mid.x + 60.0) / 7.5), 2, 13),
		clampi(int((mid.y + 40.0) / 8.0), 2, 7))
	# CARRY-FORWARD from stage A: a bad pack is a wetter, harder dressing.
	snake.build(int(ctx.get("seed", 1)) ^ 0x33, diff, "pack", clampf(1.0 - pack_quality, 0.1, 0.8),
		view_mm())


func _advance_wrap(delta: float) -> void:
	if snake == null:
		return
	pay(snake.advance(delta))
	if snake.finished and play_state != Play.DONE:
		_done()


## The board hands back what happened; this is where it is charged for.
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
					_soak_cd = wrap_soak_cooldown
					cost(wrap_soak_botch, "Blood soaked through the dressing")
			"layer":
				audio(layer_cue, -18.0, 0.12)
			_:
				pass


func animate(delta: float) -> void:
	_t += delta
	flash = maxf(0.0, flash - delta * 1.6)
	hit_flash = maxf(0.0, hit_flash - delta * 4.0)


func _update_progress() -> void:
	var a: float = 0.0
	var total := 0
	var have := 0
	for i in b_need.size():
		total += int(b_need[i])
		have += mini(int(b_hits[i]), int(b_need[i]))
	a = float(have) / maxf(1.0, float(total))
	if stage == Stage.WHACK:
		progress = 0.45 * a
	else:
		progress = 0.45 + 0.55 * (snake.frac() if snake != null else 0.0)


func _done() -> void:
	var marks: String = snake.marks() if snake != null else ""
	quality = clampf(0.5 * pack_quality + 0.5 * (snake.quality() if snake != null else 1.0), 0.05, 1.0)
	var b = body()
	if b != null:
		if b.has_method("set_bleeding"):
			b.set_bleeding(String(ctx.get("step", {}).get("site", "gunshot")), 0.0)
		if b.has_method("apply_flags"):
			var f: Dictionary = (ctx.get("flags", {}) as Dictionary).duplicate()
			f["dressed"] = true
			f["dress_marks"] = marks
			b.apply_flags(f)
	arcade_finish({"dressed": true, "pack_quality": snappedf(pack_quality, 0.01), "dress_marks": marks})


## WHACK: whatever is up ducks early, and it costs nothing. WRAP: the last of the bandage comes off.
func on_jolt(_offset: Vector2, strength: float, _duration: float) -> void:
	if stage == Stage.WHACK:
		for i in b_up.size():
			if float(b_up[i]) > 0.0:
				b_up[i] = 0.0
				b_next[i] = _rng.randf_range(pop_min, pop_max)
		shake(clampf(0.4 + strength * 0.5, 0.0, 1.0))
		return
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
	var b = body()
	if gushes > _seen_gushes:
		_seen_gushes = gushes
		audio(gush_cue, -2.0, 0.08)
		if b != null and b.has_method("stir"):
			b.stir(0.7)
	if snake != null:
		if snake.tangles > _seen_tangles:
			_seen_tangles = snake.tangles
			audio(tangle_cue, -6.0, 0.1)
			if b != null and b.has_method("stir"):
				b.stir(0.5)
		if snake.soaks > _seen_soaks:
			_seen_soaks = snake.soaks
			audio(gush_cue, -9.0, 0.1)
	if b == null or not b.has_method("set_bleeding"):
		return
	var site := String(ctx.get("step", {}).get("site", "gunshot"))
	var amount: float = 0.0
	if stage == Stage.WHACK:
		amount = clampf(0.25 + 0.6 * flood, 0.0, 1.0)
	else:
		var laid: float = snake.frac() if snake != null else 0.0
		amount = clampf(0.45 * (1.0 - pack_quality) * (1.0 - 0.7 * laid) + 0.08, 0.0, 1.0)
	b.set_bleeding(site, 0.0 if play_state == Play.DONE else amount)


# ---------------------------------------------------------------------------- the diagram

func paint_game(c: CanvasItem) -> void:
	if panel == null:
		return
	var st := style()
	if stage == Stage.WHACK:
		_paint_tract(c, st)
		_paint_wads(c, st)
		_paint_bleeders(c, st)
		_paint_kidney(c, st)
		_paint_flood(c, st)
		_paint_scoreboard(c, st)
	else:
		_paint_tract(c, st)
		snake.paint(c, self)
		snake.paint_counters(c, self)
	if flash > 0.0:
		c.draw_rect(Rect2(Vector2.ZERO, panel.tex_size()), Color(st.danger, flash * 0.18))


## The wound tract from above: a dark channel with a bright rim, the entry at the left.
func _paint_tract(c: CanvasItem, st: StyleScript) -> void:
	if tract.size() < 2:
		return
	var a := PackedVector2Array()
	var b := PackedVector2Array()
	for i in tract.size():
		var p: Vector2 = tract[i]
		var q: Vector2 = tract[mini(i + 1, tract.size() - 1)] - tract[maxi(i - 1, 0)]
		var n: Vector2 = Vector2(-q.y, q.x).normalized() * tract_half_mm
		# It narrows toward the deep end, so which end is which is never in doubt.
		var k: float = lerpf(1.0, 0.55, float(i) / float(tract.size() - 1))
		a.append(px(p + n * k))
		b.append(px(p - n * k))
	var poly := PackedVector2Array(a)
	for i in range(b.size() - 1, -1, -1):
		poly.append(b[i])
	c.draw_colored_polygon(poly, Color(st.blood_dark, 0.85 if stage == Stage.WHACK else 0.35))
	var rim: float = 1.0 if stage == Stage.WHACK else 0.35
	st.glow_poly(c, a, st.line, st.hair)
	c.draw_polyline(a, Color(st.line, 0.75 * rim), st.thin)
	c.draw_polyline(b, Color(st.line, 0.75 * rim), st.thin)
	st.dashed(c, px(tract[0]), px(tract[tract.size() - 1]), Color(st.line_dim, 0.18 * rim), st.hair, 6.0, 8.0)


## Down: a dashed ring with one pip per wad it still wants. Up: filled, with spikes. Plugged: a
## hatched wad. Nothing here is told apart by colour on its own.
func _paint_bleeders(c: CanvasItem, st: StyleScript) -> void:
	for i in b_pos.size():
		var at: Vector2 = px(b_pos[i])
		var r: float = px_len(3.2 if not bool(b_bed[i]) else 4.2)
		if bool(b_done[i]):
			c.draw_circle(at, r, Color(st.thread, 0.75))
			c.draw_arc(at, r, 0.0, TAU, 18, Color(st.good, 0.9), st.thin)
			for k in 3:
				var t: float = lerpf(-0.7, 0.7, float(k) / 2.0)
				c.draw_line(at + Vector2(-r * 0.75, r * t), at + Vector2(r * 0.75, r * t),
					Color(st.bg, 0.45), st.hair)
			continue
		var up: float = float(b_up[i])
		if up > 0.0:
			st.glow_circle(c, at, r * 1.25, st.danger, st.thin)
			c.draw_circle(at, r * 1.25, st.danger)
			# Spurting: spikes, so it reads as up even with the colour off.
			for k in 8:
				var a: float = TAU * float(k) / 8.0 + _t * 1.7
				var d := Vector2(cos(a), sin(a))
				c.draw_line(at + d * r * 1.35, at + d * r * (2.3 + 0.35 * sin(_t * 9.0 + float(k))),
					st.danger, st.thin)
			c.draw_circle(at, r * 0.45, Color(st.blood_dark, 0.9))
		else:
			c.draw_circle(at, r, Color(st.blood_dark, 0.9))
			var col: Color = Color(st.line_dim, 0.85)
			for k in 12:
				var a0: float = TAU * float(k) / 12.0
				c.draw_arc(at, r, a0, a0 + TAU / 22.0, 3, col, st.thin)
		# One pip per wad still wanted, set out round the rim.
		var want: int = maxi(0, int(b_need[i]) - int(b_hits[i]))
		for k in want:
			var a1: float = -PI * 0.5 + TAU * float(k) / float(maxi(1, int(b_need[i])))
			c.draw_circle(at + Vector2(cos(a1), sin(a1)) * r * 2.9, px_len(0.9), Color(st.line, 0.9))


func _paint_wads(c: CanvasItem, st: StyleScript) -> void:
	for w: Vector2 in wads:
		var at: Vector2 = px(w)
		var r: float = px_len(3.0)
		c.draw_circle(at, r, Color(st.thread, 0.30))
		c.draw_arc(at, r, 0.0, TAU, 16, Color(st.sloppy, 0.8), st.hair)
		c.draw_line(at + Vector2(-r, -r) * 0.7, at + Vector2(r, r) * 0.7, Color(st.sloppy, 0.7), st.hair)


func _paint_kidney(c: CanvasItem, st: StyleScript) -> void:
	if kidney_left <= 0.0:
		return
	var pts := PackedVector2Array()
	for i in 26:
		var a: float = TAU * float(i) / 26.0
		# A bean: a circle with a bite out of one side.
		var rr: float = 6.4 - 2.6 * exp(-pow((a - PI) * 1.7, 2.0))
		pts.append(px(kidney_at + Vector2(cos(a) * rr, sin(a) * rr * 0.72)))
	c.draw_colored_polygon(pts, Color(st.sloppy, 0.35))
	st.glow_poly(c, pts, st.sloppy, st.thin)
	c.draw_polyline(pts, st.sloppy, st.outline)
	c.draw_polyline(pts, st.sloppy, st.hair)


## Blood coming up the panel like water, with a line on it you can read the level off.
func _paint_flood(c: CanvasItem, st: StyleScript) -> void:
	var view := view_mm()
	var top: float = view.y * 0.5 - flood * view.y
	var size: Vector2 = panel.tex_size()
	var y: float = px(Vector2(0.0, top)).y
	c.draw_rect(Rect2(Vector2(0.0, y), Vector2(size.x, size.y - y)), Color(st.blood, 0.42))
	var wave := PackedVector2Array()
	for i in 41:
		var x: float = lerpf(0.0, size.x, float(i) / 40.0)
		wave.append(Vector2(x, y + sin(_t * 1.8 + float(i) * 0.55) * px_len(0.8)))
	c.draw_polyline(wave, Color(st.danger, 0.85 if flood > 0.8 else 0.5), st.thin)
	if flood > 0.8:
		# Close to going over: ticks along the surface as well as the brighter line.
		for i in 14:
			var x: float = lerpf(0.0, size.x, float(i) / 13.0)
			c.draw_line(Vector2(x, y), Vector2(x, y + px_len(2.0)), Color(st.danger, 0.7), st.hair)


## Where the wad is, and what is left. The cursor is drawn because the panel is a screen and the
## mouse is not on it.
func _paint_scoreboard(c: CanvasItem, st: StyleScript) -> void:
	var at := px(cursor)
	var r: float = px_len(hit_mm * (0.55 + 0.25 * hit_flash))
	c.draw_arc(at, r, 0.0, TAU, 22, Color(st.line, 0.75), st.thin)
	for k in 4:
		var a: float = TAU * float(k) / 4.0 + PI * 0.25
		var d := Vector2(cos(a), sin(a))
		c.draw_line(at + d * r * 0.55, at + d * r, Color(st.line, 0.6), st.hair)
	var font := ThemeDB.fallback_font
	var txt := "%d OPEN" % open_bleeders()
	if gushes > 0:
		txt += "    GUSHED %d" % gushes
	if wads.size() > 0:
		txt += "    ON THE SKIN %d" % wads.size()
	var w: float = font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
	var pos: Vector2 = px(Vector2(0.0, view_mm().y * 0.5 - 1.6)) + Vector2(-w * 0.5, 0.0)
	c.draw_rect(Rect2(pos - Vector2(8.0, 16.0), Vector2(w + 16.0, 22.0)), Color(st.bg, 0.72))
	c.draw_string(font, pos, txt, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 20,
		st.danger if gushes > 0 else Color(st.line_dim, 0.95))


# ---------------------------------------------------------------------------- net

## Everything a spectator needs to watch both stages. `flood`, the mole clocks and the kidney all
## CREEP by less than a snap a frame, so they go raw (see ArcadeGame.net_state).
func net_pack() -> Dictionary:
	var hits := PackedByteArray()
	var needs := PackedByteArray()
	var done := PackedByteArray()
	var up := PackedFloat32Array()
	var nxt := PackedFloat32Array()
	var sk := PackedFloat32Array()
	for i in b_pos.size():
		hits.append(int(b_hits[i]))
		needs.append(int(b_need[i]))
		done.append(1 if bool(b_done[i]) else 0)
		up.append(float(b_up[i]))
		nxt.append(float(b_next[i]))
		sk.append(float(b_soak[i]))
	var wd := PackedVector2Array()
	for w: Vector2 in wads:
		wd.append(w)
	return {
		"st": stage, "fl": flood, "pf": snappedf(peak_flood, 0.01), "gu": gushes, "ls": late_soaks,
		"pq": snappedf(pack_quality, 0.01), "cu": cursor, "wd": wd,
		"bh": hits, "bn": needs, "bd": done, "bu": up, "bx": nxt, "bs": sk,
		"ka": kidney_at, "kl": kidney_left, "pg": pop_gap, "kn": kidneys, "fa": snappedf(flash, 0.05),
		"sn": snake.pack() if snake != null else {},
	}


func net_apply(s: Dictionary) -> void:
	var was: int = stage
	stage = int(s.get("st", stage))
	flood = float(s.get("fl", flood))
	peak_flood = float(s.get("pf", peak_flood))
	gushes = int(s.get("gu", gushes))
	late_soaks = int(s.get("ls", late_soaks))
	pack_quality = float(s.get("pq", pack_quality))
	cursor = s.get("cu", cursor)
	var wd: PackedVector2Array = s.get("wd", PackedVector2Array())
	wads.clear()
	for w in wd:
		wads.append(w)
	var hits: PackedByteArray = s.get("bh", PackedByteArray())
	var needs: PackedByteArray = s.get("bn", PackedByteArray())
	var done: PackedByteArray = s.get("bd", PackedByteArray())
	var up: PackedFloat32Array = s.get("bu", PackedFloat32Array())
	var nxt: PackedFloat32Array = s.get("bx", PackedFloat32Array())
	var sk: PackedFloat32Array = s.get("bs", PackedFloat32Array())
	for i in mini(hits.size(), b_hits.size()):
		b_hits[i] = int(hits[i])
		b_need[i] = int(needs[i])
		b_done[i] = done[i] != 0
		b_up[i] = float(up[i])
		b_next[i] = float(nxt[i])
		b_soak[i] = float(sk[i])
	kidney_at = s.get("ka", kidney_at)
	kidney_left = float(s.get("kl", kidney_left))
	pop_gap = float(s.get("pg", pop_gap))
	kidneys = int(s.get("kn", kidneys))
	flash = float(s.get("fa", flash))
	# A spectator who arrived after the card has to build the same board before it can draw it.
	if stage == Stage.WRAP and snake == null:
		_build_snake()
	if snake != null:
		snake.unpack(s.get("sn", {}))
	_update_progress()


# ---------------------------------------------------------------------------- bot

func bot_input(t: float, skill: float) -> Dictionary:
	var dt: float = clampf(t - _bt, 0.0, 0.1)
	_bt = t
	skill = clampf(skill, 0.0, 1.0)
	if not armed():
		_b_prev = 0
		return {"cursor": _out(_b_cur), "buttons": 0}
	if stage == Stage.WRAP:
		return {"cursor": _out(_b_cur), "buttons": _bot_steer(skill)}
	return _bot_whack(dt, skill)


## WHACK: go to whatever is up and hit it. The error is one golden-ratio draw per attempt, so a
## given seed makes the same hand every run; a bad one is slow to move, slow to react, and its wad
## lands wide enough to end up on the skin.
func _bot_whack(dt: float, skill: float) -> Dictionary:
	var pick := -1
	var bd := 1e9
	for i in b_pos.size():
		if bool(b_done[i]) or float(b_up[i]) <= 0.0:
			continue
		var d: float = _b_cur.distance_to(b_pos[i])
		if d < bd:
			bd = d
			pick = i
	if pick != _b_target:
		_b_target = pick
		_b_seq += 1
		var u: float = fposmod(float(_b_seq) * PHI, 1.0)
		var v: float = fposmod(float(_b_seq) * PHI * 2.0, 1.0)
		var wide: float = lerpf(12.5, 0.6, skill)
		_b_err = Vector2(u - 0.5, v - 0.5) * 2.0 * wide
		_b_react = lerpf(0.50, 0.05, skill) * (0.35 + u)
	if pick < 0:
		# Nothing up: drift back over the tract and wait.
		_b_cur = _b_cur.move_toward(at_arc(0.5), lerpf(120.0, 400.0, skill) * dt)
		_b_prev = 0
		return {"cursor": _out(_b_cur), "buttons": 0}
	var aim: Vector2 = (b_pos[pick] as Vector2) + _b_err
	_b_cur = _b_cur.move_toward(aim, lerpf(160.0, 700.0, skill) * dt)
	_b_react = maxf(0.0, _b_react - dt)
	var btn := 0
	if _b_react <= 0.0 and _b_cur.distance_to(aim) < lerpf(6.0, 1.5, skill):
		btn = 0 if _b_prev != 0 else BUTTON_PRIMARY
		if btn != 0:
			# Whatever happens next, take a fresh draw before trying again.
			_b_target = -1
	_b_prev = btn
	return {"cursor": _out(_b_cur), "buttons": btn}


## WRAP: breadth-first to the nearest bare cell, with the odd wrong turning when the hand is bad.
func _bot_steer(skill: float) -> int:
	if snake == null:
		return 0
	if snake.cell != _b_cell:
		_b_cell = snake.cell
		_b_seq += 1
		var u: float = fposmod(float(_b_seq) * PHI, 1.0)
		var want: Vector2i = snake.route(snake.cell, snake.dir)
		# A blob has open ground all round it, so a wrong turning is far more survivable here than
		# on the stump's ring: the bad hand has to be correspondingly worse to cost the same.
		if u < lerpf(0.33, 0.0, skill):
			want = snake.dir            # missed the turning and carried straight on
		elif u < lerpf(0.61, 0.0, skill):
			var alt: Vector2i = Vector2i(want.y, -want.x) if u < 0.47 else Vector2i(-want.y, want.x)
			if alt != -snake.dir:
				want = alt
		_b_want = want
	var btn := 0
	if _b_want != Vector2i.ZERO and _b_want != snake.dir and _b_want != -snake.dir:
		btn = 0 if _b_prev != 0 else _dir_button(_b_want)
	_b_prev = btn
	return btn


static func _dir_button(d: Vector2i) -> int:
	if d == Vector2i(0, -1):
		return BUTTON_UP
	if d == Vector2i(0, 1):
		return BUTTON_DOWN
	if d == Vector2i(-1, 0):
		return BUTTON_LEFT
	return BUTTON_RIGHT


func _out(mm: Vector2) -> Vector2:
	return panel.metres_of(mm) if panel != null else mm


# ---------------------------------------------------------------------------- self-test

## Headless check: `tools/minigame_lab.tscn -- --selftest=gauze:pack:arcade`.
## Targets are for the STEP, both stages together: skill 1.0 finishes in 8-20 s losing 0-2 vitals;
## skill 0.0 under 40 s losing 15-25.
static func self_test() -> Array:
	var script: GDScript = load("res://scripts/surgery/arcade/pack_arcade.gd")
	var out := []
	var ok := true
	var sloppy: Array = []
	for cond: Dictionary in [{"tears": [], "sed": 1.0}, {"tears": [0.22, 0.51, 0.77], "sed": 0.4}]:
		for pid: String in ["bob", "seal"]:
			for skill: float in [1.0, 0.5, 0.0]:
				var g = script.new()
				var tally := {"n": 0, "v": 0.0, "done": false, "q": 0.0, "m": "", "reasons": {}}
				g.botched.connect(func(a, r): tally.n += 1; tally.v += a; tally.reasons[r] = int(tally.reasons.get(r, 0)) + 1)
				g.finished.connect(func(r): tally.done = true; tally.q = float(r.get("pack_quality", 0.0)); tally.m = String(r.get("dress_marks", "")))
				g.setup(_ctx(pid, cond.tears, float(cond.sed)))
				var t: float = run_bot(g, skill, float(cond.sed), hash(pid) + int(skill * 100))
				print("[pack-arcade self-test] %-4s skill=%.1f tears=%d sed=%.1f  %s  bleeders=%d gushed=%d skin=%d peak=%.2f pq=%.2f  wet=%d/%d tangles=%d  time=%5.1fs  botches=%2d vitals=%5.1f  marks=%s  %s" % [
					pid, skill, int((cond.tears as Array).size()), cond.sed, "DONE" if tally.done else "UNFINISHED",
					g.b_pos.size(), g.gushes, g.wads.size(), g.peak_flood, tally.q,
					_wet(g), (g.snake.wound.size() if g.snake != null else 0),
					(g.snake.tangles if g.snake != null else 0),
					t, tally.n, tally.v, tally.m, str(tally.reasons)])
				out.append({"patient": pid, "skill": skill, "done": tally.done, "time": t,
					"vitals": tally.v, "pack_quality": tally.q, "marks": tally.m})
				if (cond.tears as Array).is_empty() and float(cond.sed) > 0.9:
					if skill == 1.0 and (not tally.done or t < 8.0 or t > 20.0 or tally.v > 2.0):
						print("[pack-arcade self-test] MISS: skill 1.0 wants 8-20 s and 0-2 vitals")
						ok = false
					if skill == 0.0:
						sloppy.append(tally.v)
						if not tally.done or t > 40.0:
							print("[pack-arcade self-test] MISS: skill 0.0 wants to finish under 40 s")
							ok = false
				g.free()
	# The sloppy band, on the MEAN: where a seeded tract happens to put the bleeders swings one
	# patient a few vitals either side of the other on its own. saw_arcade.gd does the same.
	var mean := 0.0
	for v: float in sloppy:
		mean += v
	mean /= maxf(1.0, float(sloppy.size()))
	print("[pack-arcade self-test] skill 0.0 mean vitals %.1f across %d patients (want 15-25)" % [mean, sloppy.size()])
	if mean < 15.0 or mean > 25.0:
		print("[pack-arcade self-test] MISS: skill 0.0 wants 15-25 vitals on average")
		ok = false
	# CARRY-FORWARD in: one bleeder per tear, padded to the minimum, capped, and never two of them
	# stacked on the same spot. What has to grow with the tears is the WORK -- a clustered run puts
	# fewer pins on the board but each of them wants more wads -- so the wads are what is asserted.
	# The five-tear case is a real DODGE! sample, three of whose contacts are within 0.04.
	var last_wads := 0
	for spec: Array in [[], [0.3], [0.2, 0.4, 0.6], [0.779, 0.742, 0.740, 0.756, 0.252],
			[0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9]]:
		var g2 = script.new()
		g2.setup(_ctx("bob", spec, 1.0))
		var n: int = g2.b_pos.size()
		var wads_wanted := 0
		for i in g2.b_need.size():
			wads_wanted += int(g2.b_need[i])
		var closest := 1e9
		for i in n:
			for j in range(i + 1, n):
				closest = minf(closest, (g2.b_pos[i] as Vector2).distance_to(g2.b_pos[j]))
		print("[pack-arcade self-test] %d tears in -> %d bleeders wanting %2d wads, closest pair %.1f mm" % [
			spec.size(), n, wads_wanted, closest])
		out.append({"tears": spec.size(), "bleeders": n, "wads": wads_wanted, "closest": closest})
		if n < 3 or n > 7:
			print("[pack-arcade self-test] MISS: 3 bleeders minimum, 7 maximum, whatever comes in")
			ok = false
		if n > 1 and closest < g2.tear_spread_mm - 0.01:
			print("[pack-arcade self-test] MISS: two bleeders stacked on top of each other")
			ok = false
		if wads_wanted < last_wads:
			print("[pack-arcade self-test] MISS: more tears must never mean less work")
			ok = false
		last_wads = wads_wanted
		g2.free()
	# CARRY-FORWARD out: a worse pack has to leave a wetter dressing to route round.
	var clean := _wet_after(script, 0.9)
	var dirty := _wet_after(script, 0.2)
	print("[pack-arcade self-test] pack_quality 0.90 -> %d of %d cells bleeding;  0.20 -> %d of %d" % [
		clean[0], clean[1], dirty[0], dirty[1]])
	out.append({"wet_good_pack": clean[0], "wet_bad_pack": dirty[0]})
	if dirty[0] <= clean[0]:
		print("[pack-arcade self-test] MISS: a worse pack should leave more cells bleeding")
		ok = false
	# Shift 3 puts a kidney on the board every six to ten seconds, and difficulty is up, so the one
	# case a normal lab run never reaches gets played through here.
	var late = script.new()
	var kt := {"n": 0, "v": 0.0, "done": false, "kidney": 0}
	late.botched.connect(func(a, r): kt.n += 1; kt.v += a; kt.kidney += (1 if r.begins_with("That was a kidney") else 0))
	late.finished.connect(func(_r): kt.done = true)
	var lc: Dictionary = _ctx("bob", [0.3, 0.6], 1.0)
	lc["shift"] = 3
	lc["difficulty"] = Procedures.difficulty(3)
	late.setup(lc)
	var lt: float = run_bot(late, 0.5, 1.0, 4242)
	print("[pack-arcade self-test] shift 3 (difficulty %.2f) %s in %.1fs, %d botches / %.1f vitals, kidneys up %d, whacked %d" % [
		Procedures.difficulty(3), "DONE" if kt.done else "UNFINISHED", lt, kt.n, kt.v, late.kidneys, kt.kidney])
	out.append({"shift": 3, "done": kt.done, "time": lt, "vitals": kt.v, "kidneys": late.kidneys})
	if not kt.done or late.kidneys < 1:
		print("[pack-arcade self-test] MISS: shift 3 has to put a kidney up and still be finishable")
		ok = false
	late.free()
	# Onlookers and hand-over: a spectator tracks the operator off the replicated state alone --
	# including building the WRAP! board for itself when the card comes up -- and somebody else
	# picking the step up mid-dressing gets the READY countdown and finishes it.
	var net := _net_check(script)
	print("[pack-arcade self-test] spectator drift %.4f;  hand-over READY %s, mashed through it for %.3f progress, finished %s at %.1fs" % [
		net.drift, "yes" if net.ready else "NO", net.mashed, "yes" if net.done else "NO", net.time])
	out.append(net)
	if net.drift > 0.02 or not net.ready or net.mashed > 0.001 or not net.done:
		print("[pack-arcade self-test] MISS: a spectator must track the operator, and a hand-over must count down first")
		ok = false
	print("[pack-arcade self-test] %s" % ("PASS" if ok else "FAIL"))
	return out


## Player A packs the wound with player B watching, A walks off part way through the dressing, B
## picks it up. B must have tracked A exactly -- through the stage change, where B has to lay out
## the same Snake board for itself off the replicated pack_quality -- must get the countdown rather
## than a roll already moving, and mashing the keys during it must not steer anything.
static func _net_check(script: GDScript) -> Dictionary:
	var a = script.new()
	a.setup(_ctx("bob", [], 1.0))
	var b = script.new()
	var cb: Dictionary = _ctx("bob", [], 1.0)
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
			# Hand over after the WRAP! card, so the stage change is watched and then inherited.
			if a.stage == Stage.WRAP and a.progress > 0.62:
				phase = 1
				a.ctx["operating"] = false
				b.ctx["operating"] = false
		elif phase == 1:
			a.tick(dt)
			b.apply_net_state(a.net_state())
			b.tick(dt)
			phase = 2
			b.ctx["operating"] = true
			b.ctx["operator"] = true
			at_hand = b.progress
		else:
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


static func _ctx(pid: String, tears: Array, sed: float) -> Dictionary:
	return {"patient_id": pid, "patient": Procedures.patient(pid), "ailment_id": "gunshot",
		"step": Procedures.step("gunshot", 2), "variant": "pack", "shift": 1,
		"difficulty": Procedures.difficulty(1),
		"flags": {"sedation": sed, "bullet_removed": true, "tears": tears},
		"seed": hash("packwhack" + pid), "body": null, "operator": true, "operating": true}


static func _wet(g) -> int:
	if g.snake == null:
		return 0
	var n := 0
	for w in g.snake.wound.size():
		if g.snake.bleeding[w]:
			n += 1
	return n


static func _wet_after(script: GDScript, pq: float) -> Array:
	var g = script.new()
	g.setup(_ctx("bob", [], 1.0))
	g.pack_quality = pq
	g._build_snake()
	var r := [_wet(g), g.snake.wound.size()]
	g.free()
	return r
