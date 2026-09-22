extends "res://scripts/surgery/arcade/arcade_game.gd"
## ARCADE SURGERY -- SUTURE!, step four of a gunshot wound (and the whole of the `laceration`
## testbed). Built from docs/SUTURE_SPEC.md, "Addendum Three -- SUTURE!"; that file wins where
## anything here disagrees with it. It runs on the clipboard shell (scripts/surgery/panel/shell.gd)
## the Anesthetic Injection, DODGE! and WHACK!/WRAP! already use.
##
## THE PAUSE AFTER THREE REFLEX GAMES. One continuous thread through a grid: start on dot 1, visit
## every open cell exactly once, take the numbered dots in order, never cross yourself. It is
## LinkedIn's Zip themed as suturing. The failure state is your own untidiness, not a clock: the
## patient seeps the whole time, but slowly enough that a careful 60-second solve is a good solve.
## Pulling thread back out is what actually costs.
##
## TWO VARIANTS (spec 2), by the step's `variant`, and swappable in play from the button under the
## board:
##   laceration  an open grid, 4x4 the first time and 5x5 once one has been closed, with a long
##               diagonal gash running under it.
##   eye         6x6 with the centre 2x2 blocked by an eyeball -- 32 cells to thread around it, with
##               a dashed DO NOT STITCH fence over the block.
##
## ALWAYS SOLVABLE BY CONSTRUCTION (spec 3). The solution comes first: a randomised depth-first
## Hamiltonian path (Warnsdorff ordering, random tiebreak, budgeted and retried), then the numbers are
## placed along it, then the walls are taken only from edges the solution never crosses. Nothing is
## ever generated and then tested. self_test() re-derives a solution with an independent solver over
## many puzzles of both variants and every grid size, which is the check the source spec ran by hand.
##
## THE CORNER HUD is the new standard (spec 6, cross-cutting): rules as bullets top left, keybindings
## as boxed key caps under them, and ONE number top right (VITALS %, red under 35). No monitor, no
## EKG, no beeper. Only this step draws it so far; the other three are a separate retrofit.
##
## Space: the spec's 960 x 600 reference px ("rpx") laid on the paper, same as DODGE! and WHACK!.
##
## Carry-forward out: {"closed": true, "stitch_marks": "ggsg"} -- the same contract the legacy
## suture.gd finishes with, so the body still draws the stitches he walks out with.

const REF := Vector2(960.0, 600.0)
## The grid always occupies the same square on the page, whatever size it is (spec 2).
const BOARD_AT := Vector2(264.0, 92.0)
const BOARD := 432.0
## Splat index ranges, kept apart so the shell never throws the same blood twice.
const TUG_FROM := 40000
const FLAT_FROM := 41000

enum State { PLAY, RESOLVE, RESULT }

# -- the puzzle (spec 2, 3) --------------------------------------------------------------------
@export_group("Puzzle")
## SPEC 7 KNOB "mode": which wound. The step's `variant` sets it; the button under the board swaps it.
@export_enum("laceration", "eye") var start_mode := "laceration"
## SPEC 7 KNOB "lacerationSize": "scaling" steps 4x4 up to 5x5 once one has been closed at CLEAN or
## SLOPPY; "4" and "5" pin it.
@export_enum("scaling", "4", "5") var laceration_size := "scaling"
## SPEC 7 KNOB "numberedDots": 6 max, clamped to the grid size (3-8). Count = grid size, so a 4x4 has
## four dots and the 6x6 has six.
@export_range(3, 8) var numbered_dots := 6
## SPEC 7 KNOB "wallCount": 2 (0-4), capped at n-2.
@export_range(0, 4) var wall_count := 2
## The Hamiltonian search's budget and how many fresh starts it gets (spec 3: in practice it lands
## first try, well under 5 ms).
@export_range(1000, 400000) var search_budget := 120000
@export_range(1, 24) var search_tries := 12

# -- the thread (spec 4) -----------------------------------------------------------------------
@export_group("Thread")
## How many cells one input event may walk through, so a fast drag cannot skip a wall (spec 8).
@export_range(1, 16) var walk_per_event := 8
## How long an illegal cell stays red.
@export_range(0.05, 1.5, 0.05) var flash_time := 0.4
## What one popped segment costs, and how many pulls between TUGGED! bursts.
@export_range(0.0, 10.0, 0.1) var undo_cost := 1.6
@export_range(1, 12) var tug_every := 5
## The win's stitch-tick resolve, and the beat before the card.
@export_range(0.2, 4.0, 0.05) var resolve_time := 1.1

# -- vitals (spec 4, 7) ------------------------------------------------------------------------
@export_group("Vitals")
## SPEC 7 KNOB "seepRate": 1.0x of a 0.42 %/s base (0.3-2.5).
@export_range(0.3, 2.5, 0.05) var seep_rate := 1.0
@export_range(0.0, 3.0, 0.01) var seep_base := 0.42
## The number goes red here (spec 6).
@export_range(0.0, 100.0, 1.0) var vitals_trouble := 35.0
## What the patient himself is billed: every pull-out, and the flatline. The seep is the step's own
## meter, like WHACK!'s BLOOD LOST -- it grades the step without quietly emptying the patient.
@export_range(0.0, 10.0, 0.1) var undo_bill := 1.6
@export_range(0.0, 60.0, 1.0) var flatline_bill := 18.0

# -- the results card (spec 7) -----------------------------------------------------------------
@export_group("Results")
## Score = 100 - vitalsLost x 1.1 - undos x 2.2 - max(0, t - 75) x 0.3, clamped 0-100.
@export_range(0.0, 5.0, 0.01) var score_vitals := 1.1
@export_range(0.0, 20.0, 0.1) var score_undo := 2.2
@export_range(0.0, 5.0, 0.01) var score_slow := 0.3
@export_range(0.0, 300.0, 1.0) var score_grace := 75.0
@export_range(0, 100) var grade_clean := 78
@export_range(0, 100) var grade_sloppy := 45
@export_range(0.0, 5.0, 0.1) var result_lock := 1.0
@export var result_card_size := Vector2(600.0, 250.0)

@export_group("Audio")
@export var stitch_cue := "surgery_click"
@export var tug_cue := "surgery_tear"
@export var bad_cue := "surgery_swish"
@export var closed_cue := "surgery_pack"
@export_group("")

# ---- replicated ----
var mode := "laceration"
var n := 4                              ## grid size
var gen := 0                            ## bumped on every regenerate: the board's seed salt
var state: int = State.PLAY
var path: PackedInt32Array = PackedInt32Array()
var vit := 100.0                        ## THIS CREEPS. Never snap it.
var undos := 0
var solve_t := 0.0                      ## THIS CREEPS.
var resolve := 0.0                      ## THIS CREEPS.
var flatlined := false
var score := 0
var _grade := ""
## Bumped when an illegal move is refused, with the cell it was: an onlooker flashes the same one.
var bad_seq := 0
var bad_cell := -1

# ---- from the seed (rebuilt from mode, n and gen on every machine) ----
var blocked: Array[bool] = []
var nums := {}                          ## cell -> 1..count
var num_cells: PackedInt32Array = PackedInt32Array()   ## in number order
var walls := {}                         ## edge key -> true
var sol: PackedInt32Array = PackedInt32Array()
var grime_spots: Array = []

# ---- local ----
var _rng := RandomNumberGenerator.new()
var _flash := {}                        ## cell -> seconds left
var _fence := 0.0                       ## the eye fence lighting up after a bump
var _tint := 0.0
var _closed_at := {}                    ## cell -> seconds since the skin closed over it
var _blob := {}                         ## cell -> PackedVector2Array, the closure's outline
var _cursor := Vector2(480.0, 300.0)
var _dragging := false
var _bad_seen := 0
var _seen := {}
var _warm := false
var show_solution := false

## SPEC 2: 4x4 on first play, 5x5 once a laceration has been closed at CLEAN or SLOPPY. Static so it
## outlives the step (the same run of the game), like Procedures.ARCADE_ENABLED. The size itself is
## replicated, so an onlooker never has to have seen the same cases.
static var laceration_cleared := false

## REVIEW / DEV OVERRIDE: the variant a fresh SUTURE! opens on whatever its step says ("" for none).
## scripts/review_setups.gd's `suture_eye` sets it; the operator's choice is replicated from there on,
## so an onlooker never needs it.
static var force_mode := ""

# ---- the buttons under the board ----
var _btn_variant := Rect2(BOARD_AT.x, 548.0, 196.0, 32.0)
var _btn_new := Rect2(BOARD_AT.x + 208.0, 548.0, 118.0, 32.0)
var _btn_clear := Rect2(BOARD_AT.x + 336.0, 548.0, 120.0, 32.0)

# ---- bot ----
var _bt := 0.0
var _b_gate := -1.0
var _b_up := false
var _b_aim := Vector2.ZERO
var _b_slip := 0


# ---------------------------------------------------------------------------- setup

func use_ink() -> bool:
	return true


func ink_unit() -> float:
	return _u()


func card_word_for_start() -> String:
	return "SUTURE!"


func build_game() -> void:
	if ink != null:
		ink.content = Rect2(Vector2(0.0, _top()), REF * _u())
	var v := String(ctx.get("variant", ""))
	if v == "":
		v = String(ctx.get("step", {}).get("variant", ""))
	mode = "eye" if v == "eye" else ("laceration" if v == "laceration" else start_mode)
	if force_mode != "":
		mode = force_mode
	for a in OS.get_cmdline_user_args():
		if a == "--solution":
			show_solution = true
		elif a == "--eye":
			mode = "eye"
	n = grid_size()
	generate()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("suture|grime|%d" % int(ctx.get("seed", 1)))
	grime_spots = InkScript.make_grime(rng, Rect2(Vector2(40, 60), panel.tex_size() - Vector2(80, 120)))
	_update_progress()


func setup(context: Dictionary) -> void:
	super.setup(context)
	# SPEC 5: blood never lands on the board. The shell rejection-samples outside this.
	if shell != null:
		shell.keep_out = Rect2(cv(BOARD_AT), Vector2(cl(BOARD), cl(BOARD))).grow(cl(26.0))


## SPEC 2: the eye is always 6x6; the laceration is 4x4 until one has been closed.
func grid_size() -> int:
	if mode == "eye":
		return 6
	match laceration_size:
		"4":
			return 4
		"5":
			return 5
	return 5 if laceration_cleared else 4


func cell_px() -> float:
	return BOARD / float(n)


# ---------------------------------------------------------------------------- the generator (spec 3)

## Everything about the board comes from (seed, mode, n, gen) alone, so every machine builds the same
## one from the three replicated numbers and never has to send the puzzle itself.
func generate() -> void:
	_rng.seed = hash("suture|%d|%s|%d|%d" % [int(ctx.get("seed", 1)), mode, n, gen])
	blocked = []
	blocked.resize(n * n)
	for i in n * n:
		blocked[i] = false
	# 1. BLOCKED CELLS FIRST. The eye takes the centre 2x2; the laceration blocks nothing.
	if mode == "eye":
		for c in eye_cells():
			blocked[c] = true
	# 2. A HAMILTONIAN PATH over what is left.
	sol = _hamiltonian()
	# 3. NUMBERS ALONG THAT PATH.
	_place_numbers()
	# 4. WALLS LAST, only on edges the solution never crosses.
	_place_walls()
	path = PackedInt32Array()
	_closed_at.clear()
	_blob.clear()
	_flash.clear()


## The centre 2x2 of the 6x6 (spec 2).
func eye_cells() -> PackedInt32Array:
	var out := PackedInt32Array()
	var a: int = n / 2 - 1
	for y in [a, a + 1]:
		for x in [a, a + 1]:
			out.append(int(y) * n + int(x))
	return out


func open_count() -> int:
	var k := 0
	for b in blocked:
		if not b:
			k += 1
	return k


func in_grid(x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < n and y < n


func cell_of(x: int, y: int) -> int:
	return y * n + x


func cx(c: int) -> int:
	return c % n


func cy(c: int) -> int:
	return c / n


## The four orthogonal neighbours of `c` that are on the board and not blocked. Walls are NOT applied
## here: they are derived from the solution afterwards and would not exist yet.
func _nbrs(c: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	var x := cx(c)
	var y := cy(c)
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var nx: int = x + d.x
		var ny: int = y + d.y
		if in_grid(nx, ny) and not blocked[cell_of(nx, ny)]:
			out.append(cell_of(nx, ny))
	return out


## Every open cell's open neighbours, worked out once per board. The search runs hundreds of times
## over this, and building the lists inside it was what made generation take seconds instead of
## milliseconds.
var _nb: Array = []
var _dfs_seen: Array[bool] = []
var _stack: PackedInt32Array = PackedInt32Array()
var _mark: PackedInt32Array = PackedInt32Array()
var _mark_id := 0


func _build_nbrs() -> void:
	_nb = []
	_nb.resize(n * n)
	for c in n * n:
		_nb[c] = PackedInt32Array() if blocked[c] else _nbrs(c)


## SPEC 3: randomised depth-first search from a random start, backtracking, neighbours ordered by
## fewest onward moves (Warnsdorff) with a random tiebreak, budgeted and retried. Returns the path
## over every open cell, or an empty array if every try ran out (which has not happened yet).
##
## The one addition to the spec's recipe: before recursing, everything still unvisited has to be
## reachable from where the needle is. Without that prune a bad tiebreak can burn the whole node
## budget backtracking in a corner, which is seconds rather than the spec's "well under 5 ms".
func _hamiltonian() -> PackedInt32Array:
	var want := open_count()
	# A grid is a chequerboard and a path alternates colours, so when one colour has more open cells
	# than the other (every odd grid: a 5x5 is 13 and 12) a full path can ONLY start on the bigger
	# one. Starting anywhere meant a third of the tries were hopeless and burned the entire node
	# budget before retrying -- a quarter-second hitch on a board swap. Pick from the majority colour
	# and the search lands first try.
	var col := [PackedInt32Array(), PackedInt32Array()]
	for i in n * n:
		if not blocked[i]:
			col[(cx(i) + cy(i)) % 2].append(i)
	var opens: PackedInt32Array = col[0] + col[1] if col[0].size() == col[1].size() \
		else (col[0] if col[0].size() > col[1].size() else col[1])
	if opens.is_empty():
		return PackedInt32Array()
	_build_nbrs()
	_mark = PackedInt32Array()
	_mark.resize(n * n)
	_mark_id = 0
	for attempt in search_tries:
		var start: int = opens[_rng.randi_range(0, opens.size() - 1)]
		_dfs_seen = []
		_dfs_seen.resize(n * n)
		for i in n * n:
			_dfs_seen[i] = false
		var out := PackedInt32Array()
		var budget := [search_budget]
		if _dfs(start, out, want, budget):
			return out
	return PackedInt32Array()


func _dfs(c: int, out: PackedInt32Array, want: int, budget: Array) -> bool:
	out.append(c)
	_dfs_seen[c] = true
	if out.size() >= want:
		return true
	budget[0] -= 1
	if budget[0] <= 0 or not _rest_reachable(c, want - out.size()):
		out.resize(out.size() - 1)
		_dfs_seen[c] = false
		return false
	# Warnsdorff: try the neighbour with the fewest onward moves first, random tiebreak. At most four
	# of them, so a hand-rolled insertion sort beats building objects for sort_custom.
	var ord := PackedInt32Array()
	var key := PackedFloat32Array()
	for nb in _nb[c]:
		if _dfs_seen[nb]:
			continue
		var onward := 0
		for nn in _nb[nb]:
			if not _dfs_seen[nn]:
				onward += 1
		var k: float = float(onward) + _rng.randf() * 0.5
		var at := ord.size()
		ord.append(nb)
		key.append(k)
		while at > 0 and key[at - 1] > k:
			ord[at] = ord[at - 1]
			key[at] = key[at - 1]
			ord[at - 1] = nb
			key[at - 1] = k
			at -= 1
	for nb in ord:
		if _dfs(nb, out, want, budget):
			return true
	out.resize(out.size() - 1)
	_dfs_seen[c] = false
	return false


## Every unvisited open cell still reachable from `c`. A stamped mark array, so nothing is allocated
## per visit.
func _rest_reachable(c: int, left: int) -> bool:
	if left <= 0:
		return true
	_mark_id += 1
	_stack.clear()
	var found := 0
	for nb in _nb[c]:
		if not _dfs_seen[nb] and _mark[nb] != _mark_id:
			_mark[nb] = _mark_id
			_stack.append(nb)
			found += 1
	while not _stack.is_empty():
		var v: int = _stack[_stack.size() - 1]
		_stack.resize(_stack.size() - 1)
		for nn in _nb[v]:
			if _dfs_seen[nn] or _mark[nn] == _mark_id:
				continue
			_mark[nn] = _mark_id
			_stack.append(nn)
			found += 1
	return found >= left


## SPEC 3: 1 at index 0, the last at the end, the rest at evenly spaced indices with +-1 jitter.
## Count = grid size, clamped to the knob and to what the path can hold.
func _place_numbers() -> void:
	nums = {}
	num_cells = PackedInt32Array()
	if sol.is_empty():
		return
	var count: int = clampi(mini(n, numbered_dots), 2, mini(8, sol.size()))
	var last: int = sol.size() - 1
	var idx: Array[int] = []
	for j in count:
		var at: int = int(round(float(j) * float(last) / float(count - 1)))
		if j > 0 and j < count - 1:
			at += _rng.randi_range(-1, 1)
		idx.append(at)
	idx[0] = 0
	idx[count - 1] = last
	# Keep them strictly rising: a jitter that collided just slides along.
	for j in range(1, count):
		if idx[j] <= idx[j - 1]:
			idx[j] = idx[j - 1] + 1
	for j in range(count - 2, -1, -1):
		if idx[j] >= idx[j + 1]:
			idx[j] = idx[j + 1] - 1
	for j in count:
		var at: int = clampi(idx[j], 0, last)
		nums[sol[at]] = j + 1
		num_cells.append(sol[at])


## SPEC 3: collect every adjacent open-cell pair whose shared edge the solution never crosses,
## shuffle, take up to `wall_count` (capped at n-2). Because they sit off the solution, the puzzle
## stays solvable by definition.
func _place_walls() -> void:
	walls = {}
	if sol.is_empty():
		return
	var pos := {}
	for i in sol.size():
		pos[sol[i]] = i
	var cand: Array = []
	for c in n * n:
		if blocked[c]:
			continue
		for d in [Vector2i(1, 0), Vector2i(0, 1)]:
			var nx: int = cx(c) + d.x
			var ny: int = cy(c) + d.y
			if not in_grid(nx, ny):
				continue
			var o := cell_of(nx, ny)
			if blocked[o]:
				continue
			if absi(int(pos.get(c, -9)) - int(pos.get(o, -99))) == 1:
				continue   # the solution walks this edge
			cand.append(edge_key(c, o))
	# A seeded shuffle, so every machine picks the same walls.
	for i in range(cand.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var tmp = cand[i]
		cand[i] = cand[j]
		cand[j] = tmp
	var want: int = clampi(wall_count, 0, maxi(0, n - 2))
	for i in mini(want, cand.size()):
		walls[cand[i]] = true


static func edge_key(a: int, b: int) -> int:
	return mini(a, b) * 4096 + maxi(a, b)


func walled(a: int, b: int) -> bool:
	return walls.has(edge_key(a, b))


# ---------------------------------------------------------------------------- the rules (spec 4)

## The number the thread must take next (1 until dot 1 is on, then 2...), or 0 once they are all on.
func next_number() -> int:
	var k := 0
	for c in path:
		if nums.has(c):
			k += 1
	return 0 if k >= num_cells.size() else k + 1


func in_path(c: int) -> bool:
	return path.has(c)


func head() -> int:
	return path[path.size() - 1] if not path.is_empty() else -1


## SPEC 4: a step is legal if the cell is adjacent, unblocked, not already in the path, not behind a
## wall, and -- if numbered -- carries exactly the next number.
func legal_step(from: int, to: int) -> bool:
	if from < 0 or to < 0 or to >= n * n or blocked[to]:
		return false
	if absi(cx(from) - cx(to)) + absi(cy(from) - cy(to)) != 1:
		return false
	if in_path(to) or walled(from, to):
		return false
	if nums.has(to) and int(nums[to]) != next_number():
		return false
	return true


func solved() -> bool:
	return path.size() == open_count() and next_number() == 0


func closure_frac() -> float:
	return clampf(float(path.size()) / maxf(1.0, float(open_count())), 0.0, 1.0)


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


## rpx -> the framework's cursor (panel metres), for the bot.
func metres_of_ref(p: Vector2) -> Vector2:
	if panel == null:
		return Vector2.ZERO
	var c := cv(p)
	if ink != null:
		c = ink.onpage(c, panel.tex_size())
	var mm: Vector2 = (c - panel.tex_size() * 0.5) / panel.px_per_mm()
	return panel.metres_of(mm)


## The middle of cell `c`, in rpx.
func at_of(c: int) -> Vector2:
	var s := cell_px()
	return BOARD_AT + Vector2((float(cx(c)) + 0.5) * s, (float(cy(c)) + 0.5) * s)


## The cell under `p` (rpx), or -1 off the board.
func cell_at(p: Vector2) -> int:
	var s := cell_px()
	var x := int(floor((p.x - BOARD_AT.x) / s))
	var y := int(floor((p.y - BOARD_AT.y) / s))
	return cell_of(x, y) if in_grid(x, y) else -1


# ---------------------------------------------------------------------------- the cards and the HUD

func stamp_for(word: String) -> Dictionary:
	var I := ink
	match word:
		"SUTURE!":
			var lines := ["Start on dot 1 and hold the button down: the needle walks cell by cell."]
			if mode == "eye":
				lines.append("The eye is not yours to stitch. Thread around it.")
			else:
				lines.append("Backing up pulls thread out, and that is what costs him.")
			return {"goal": "One thread. Every cell once, numbers in order.", "lines": lines,
				"prompt": "SPACE to start", "color": I.ink if I != null else Color.BLACK}
		"CLEAN", "SLOPPY", "MALPRACTICE":
			return {"goal": _flavour(word), "lines": _result_lines(),
				"prompt": "SPACE to finish   ·   RIGHT MOUSE to retry", "wait": "Look at it...",
				"color": (I.good if word == "CLEAN" else I.deep_red) if I != null else Color.BLACK}
	return {"prompt": "SPACE"}


func _result_lines() -> Array:
	return [
		"Closed in %s   ·   %d stitches laid   ·   %d pulled out" % [_clock(solve_t), path.size(), undos],
		"Vitals lost %d%%   ·   %s" % [int(round(vitals_lost())), "%s, %dx%d" % ["eye socket" if mode == "eye" else "laceration", n, n]],
		"SCORE %d" % score,
	]


static func _clock(s: float) -> String:
	return "%d:%02d" % [int(s) / 60, int(s) % 60]


func _flavour(grade: String) -> String:
	if flatlined:
		return "You were still tidying up when he stopped."
	match grade:
		"CLEAN":
			return "One thread, no backtracking. Textbook."
		"SLOPPY":
			return "It's shut. It is not straight, but it's shut."
	return "That is not a suture. That is a shoelace."


## SPEC 6: the one-line HUD the other steps use is off here -- the rules and the key caps are drawn
## in paint_game through the shell's new two-block helpers instead.
func hud_line() -> String:
	return ""


## SPEC 6: top right, ONE number. VITALS %, red under 35.
func hud_value() -> Array:
	if state == State.RESULT:
		return ["SCORE %d" % score, _grade == "MALPRACTICE"]
	return ["VITALS %d%%" % int(ceil(maxf(0.0, vit))), vit < vitals_trouble]


func keys() -> Array:
	return [["Left mouse", "lay thread"], ["Pull back", "undo a stitch"], ["Right mouse", "pull it all out"]]


func hint() -> String:
	if stamp_waiting():
		return "Close it: one thread through every cell, in order." if card_word == "SUTURE!" \
			else "Done. Space to finish, right mouse to try again."
	var base := super.hint()
	if base != "":
		return base
	match state:
		State.PLAY:
			if path.is_empty():
				return "Press on dot 1 to put the needle in."
			if next_number() > 0:
				return "Next: dot %d. Every open cell once, no crossing." % next_number()
			return "Every dot is on. Fill what is left."
		State.RESOLVE:
			return "Pulling it tight..."
	return "Space to finish."


# ---------------------------------------------------------------------------- playing

## Right mouse is the step's own key (spec 6's ESC: this build has no ESC bit on the panel, and the
## mouse is already the hand doing the work). While the results card is up it is RETRY, which the
## shell would never hand to play() -- so it is read here, ahead of the card.
func handle_cursor(p: Vector2, buttons: int, delta: float) -> void:
	var rmb: bool = (buttons & BUTTON_SECONDARY) != 0
	var rmb_edge: bool = rmb and not _rmb_prev
	_rmb_prev = rmb
	if rmb_edge and state == State.RESULT and stamp_waiting() and card_left <= 0.0 and not frozen:
		_retry()
		return
	super.handle_cursor(p, buttons, delta)


var _rmb_prev := false


func play(p_mm: Vector2, buttons: int, edges: int, _delta: float) -> void:
	var p := ref_of_mm(p_mm)
	_cursor = p
	match state:
		State.PLAY:
			_play_thread(p, buttons, edges)
		State.RESULT:
			# The results card has been taken down and that press is the step's last action.
			_finish_step()


func _play_thread(p: Vector2, buttons: int, edges: int) -> void:
	var down: bool = (buttons & (BUTTON_PRIMARY | BUTTON_ACTION)) != 0
	var pressed: bool = (edges & (BUTTON_PRIMARY | BUTTON_ACTION)) != 0
	if (edges & BUTTON_SECONDARY) != 0 and not path.is_empty():
		_pull_all_out()
		return
	if pressed and _press_button(p):
		return
	if not down:
		_dragging = false
		return
	var c := cell_at(p)
	if pressed:
		_dragging = false
		if c < 0:
			return
		if path.is_empty():
			# SPEC 4: press on dot 1. Anywhere else flashes and does nothing.
			if int(nums.get(c, 0)) == 1:
				path.append(c)
				_close_cell(c)
				_dragging = true
			else:
				_refuse(c)
			return
		var where := _index_of(c)
		if where >= 0:
			# Pressing on an earlier cell of the path unwinds to it in one gesture.
			if where < path.size() - 1:
				_unwind_to(where)
			_dragging = true
			return
		if legal_step(head(), c):
			_extend(c)
			_dragging = true
			return
		_refuse(c)
		return
	if not _dragging or c < 0:
		return
	_walk_toward(c)


## SPEC 8: the drag is WALKED cell by cell, never snapped to the cursor -- which is what makes a wall
## or the eye feel like it stops the needle instead of teleporting the thread around it.
func _walk_toward(target: int) -> void:
	for i in walk_per_event:
		var h := head()
		if h < 0 or h == target:
			return
		var dx: int = signi(cx(target) - cx(h))
		var dy: int = signi(cy(target) - cy(h))
		var order: Array = []
		if absi(cx(target) - cx(h)) >= absi(cy(target) - cy(h)):
			order = [Vector2i(dx, 0), Vector2i(0, dy)]
		else:
			order = [Vector2i(0, dy), Vector2i(dx, 0)]
		var stepped := false
		var refused := -1
		for d in order:
			if d == Vector2i.ZERO:
				continue
			var nx: int = cx(h) + d.x
			var ny: int = cy(h) + d.y
			if not in_grid(nx, ny):
				continue
			var to := cell_of(nx, ny)
			# Pulling back onto the previous cell pops the head (spec 4, Undo).
			if path.size() >= 2 and to == path[path.size() - 2]:
				_pop()
				stepped = true
				break
			if legal_step(h, to):
				_extend(to)
				stepped = true
				break
			if refused < 0:
				refused = to
		if not stepped:
			if refused >= 0:
				_refuse(refused)
			return


func _index_of(c: int) -> int:
	for i in path.size():
		if path[i] == c:
			return i
	return -1


func _extend(c: int) -> void:
	path.append(c)
	_close_cell(c)
	_update_progress()
	if solved():
		_win()


## SPEC 4: each popped segment costs 1.6 vitals, a shake, one blood splat thrown off the field, and a
## TUGGED! burst every fifth pull.
func _pop() -> void:
	if path.is_empty():
		return
	var c: int = path[path.size() - 1]
	path.resize(path.size() - 1)
	_closed_at.erase(c)
	undos += 1
	vit = maxf(0.0, vit - undo_cost)
	shake(0.35)
	if shell != null:
		shell.splat(TUG_FROM + undos)
	if undos % maxi(1, tug_every) == 0:
		mistake("TUGGED!", undo_bill, "Pulled the thread back out", "tug", cv(at_of(c)), false)
	else:
		cost(undo_bill, "Pulled the thread back out")
	_update_progress()
	_check_flatline()


## SPEC 4: pressing directly on an earlier cell of the path unwinds to it IN ONE GESTURE -- and every
## segment it pops is billed, so the shortcut is a convenience, never a discount.
func _unwind_to(index: int) -> void:
	while path.size() > index + 1:
		_pop()
		if flatlined:
			return


func _pull_all_out() -> void:
	var k := path.size()
	for i in k:
		_pop()
		if flatlined:
			return
	_dragging = false


## SPEC 4: an illegal move is INFORMATION, not a punishment -- a red cell flash and a faint page
## tint, and it costs nothing.
func _refuse(c: int) -> void:
	bad_seq += 1
	bad_cell = c
	if mode == "eye" and c >= 0 and c < blocked.size() and blocked[c]:
		_fence = flash_time


func _close_cell(c: int) -> void:
	_closed_at[c] = 0.0


func _press_button(p: Vector2) -> bool:
	if _btn_variant.has_point(p):
		mode = "eye" if mode == "laceration" else "laceration"
		_regenerate(true)
		return true
	if show_solution and _btn_new.has_point(p):
		_regenerate(true)
		return true
	if show_solution and _btn_clear.has_point(p):
		path = PackedInt32Array()
		_closed_at.clear()
		_dragging = false
		_update_progress()
		return true
	return false


## A fresh board: the variant button, the debug "New puzzle" and Retry all come through here. `bump`
## draws a different puzzle; without it the same one comes back for another go.
func _regenerate(bump: bool) -> void:
	if bump:
		gen += 1
	n = grid_size()
	generate()
	_dragging = false
	_update_progress()


func _retry() -> void:
	state = State.PLAY
	card_word = ""
	play_state = Play.RUNNING
	vit = 100.0
	undos = 0
	solve_t = 0.0
	resolve = 0.0
	flatlined = false
	score = 0
	_grade = ""
	if shell != null:
		shell.stamp_size = Vector2(516.0, 274.0)
	_regenerate(false)


func advance(delta: float) -> void:
	match state:
		State.PLAY:
			solve_t += delta
			# SPEC 1: time pressure is atmosphere, not a clock. He seeps the whole time, slowly.
			vit = maxf(0.0, vit - seep_base * seep_rate * delta)
			_check_flatline()
		State.RESOLVE:
			resolve = maxf(0.0, resolve - delta)
			if resolve <= 0.0:
				_to_result()


func _check_flatline() -> void:
	if flatlined or vit > 0.0 or state != State.PLAY:
		return
	flatlined = true
	mistake("FLATLINE!", flatline_bill, "Let the patient empty on the table", "flatline",
		cv(Vector2(REF.x * 0.5, 210.0)), true)
	if shell != null:
		for i in 4:
			shell.splat(FLAT_FROM + i)
	_to_result()


func _win() -> void:
	state = State.RESOLVE
	resolve = resolve_time
	burst("CLOSED!", cv(Vector2(REF.x * 0.5, 210.0)))


## SPEC 7: round(100 - vitalsLost x 1.1 - undos x 2.2 - max(0, t - 75) x 0.3), clamped 0-100. Undoing
## is the expensive mistake and the clock only bites after 75 seconds.
func vitals_lost() -> float:
	return clampf(100.0 - vit, 0.0, 100.0)


func grade_score() -> int:
	if flatlined:
		return 0
	var s: float = 100.0 - vitals_lost() * score_vitals - float(undos) * score_undo \
		- maxf(0.0, solve_t - score_grace) * score_slow
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
	if mode != "eye" and (_grade == "CLEAN" or _grade == "SLOPPY"):
		laceration_cleared = true
	if shell != null:
		shell.stamp_size = result_card_size
	show_card(_grade, result_lock)
	progress = 1.0


func _finish_step() -> void:
	quality = clampf(float(score) / 100.0, 0.05, 1.0)
	var marks := stitch_marks()
	var b = body()
	if b != null:
		if b.has_method("set_bleeding"):
			b.set_bleeding(String(ctx.get("step", {}).get("site", "gunshot")), 0.0)
		if b.has_method("apply_flags"):
			var f: Dictionary = (ctx.get("flags", {}) as Dictionary).duplicate()
			f["closed"] = true
			f["stitch_marks"] = marks
			b.apply_flags(f)
	arcade_finish({"closed": true, "stitch_marks": marks})


## What he walks out with: one mark per numbered dot, "g" for a tidy stitch and "s" for a crooked
## one. A pull-out makes one of them crooked, oldest first.
func stitch_marks() -> String:
	var s := ""
	for i in maxi(1, num_cells.size()):
		s += "s" if i < undos else "g"
	return s


func _update_progress() -> void:
	progress = 1.0 if state == State.RESULT else 0.95 * closure_frac()


# ---------------------------------------------------------------------------- animation and sound

func animate(delta: float) -> void:
	for c in _flash.keys():
		_flash[c] = float(_flash[c]) - delta
		if float(_flash[c]) <= 0.0:
			_flash.erase(c)
	for c in _closed_at.keys():
		_closed_at[c] = float(_closed_at[c]) + delta
	_fence = maxf(0.0, _fence - delta)
	_tint = maxf(0.0, _tint - delta)
	# Illegal moves an onlooker has only heard about through the state blob.
	while _bad_seen < bad_seq:
		if bad_cell >= 0:
			_flash[bad_cell] = flash_time
		_tint = flash_time
		_bad_seen += 1
		audio(bad_cue, -20.0, 0.2)


func react() -> void:
	var now := {"laid": path.size(), "ud": undos, "st": state}
	if _seen.is_empty():
		_seen = now
		return
	if int(now.laid) > int(_seen.laid):
		audio(stitch_cue, -14.0, 0.2)
	if int(now.ud) > int(_seen.ud):
		audio(tug_cue, -10.0, 0.15)
	if int(now.st) != int(_seen.st) and int(now.st) == State.RESOLVE:
		audio(closed_cue, -6.0, 0.1)
	_seen = now
	# The real patient seeps until the wound is shut.
	var b = body()
	if b != null and b.has_method("set_bleeding") and play_state != Play.DONE:
		b.set_bleeding(String(ctx.get("step", {}).get("site", "gunshot")),
			clampf(0.35 * (1.0 - closure_frac()), 0.0, 1.0))


# ---------------------------------------------------------------------------- the page (spec 5)

## SPEC 5 draw order: wound -> closures -> grid and dots -> thread. No ambient halftone: the page is
## flat skin with the ink line work carrying the drawing.
func paint_game(c: CanvasItem) -> void:
	if panel == null or ink == null:
		return
	ink.draw_grime(c, grime_spots)
	_paint_skin(c)
	_paint_wound(c)
	_paint_closures(c)
	_paint_grid(c)
	if mode == "eye":
		_paint_eye(c)
	if show_solution:
		_paint_solution(c)
	_paint_thread(c)
	_paint_numbers(c)
	_paint_flash(c)
	_paint_buttons(c)
	shell.draw_keycaps(c, [["LMB + PULL FORWARD", "lay thread"], ["LMB + PULL BACKWARD", "undo a stitch"],
		["RIGHT MOUSE", "pull it all out"]], shell.draw_rules(c, rules()))
	if _warm:
		ink.warm(c)
		c.draw_string(InkScript.font_upright(), Vector2(-100, -100),
			"SUTURE! TUGGED! CLOSED! FLATLINE! CLEAN SLOPPY MALPRACTICE DO NOT STITCH",
			HORIZONTAL_ALIGNMENT_LEFT, -1.0, 110, ink.ink)


## SPEC 6: three short lines saying what you are trying to do, never how to press it.
func rules() -> Array:
	return ["follow the numbers in order", "fill every open cell once", "never cross your own thread"]


func _paint_skin(c: CanvasItem) -> void:
	var r := Rect2(BOARD_AT, Vector2(BOARD, BOARD)).grow(34.0)
	c.draw_rect(Rect2(cv(r.position), r.size * _u()), Color(ink.skin_human, 0.34))


## SPEC 5: the wound matches what you are stitching. Three bands -- a retracted skin lip, an open red
## channel, a near-black depth inside it -- along the grid diagonal, or ringing the eye.
func _paint_wound(c: CanvasItem) -> void:
	var spine := _wound_spine()
	if spine.size() < 2:
		return
	var s := cell_px()
	_band(c, spine, s * 0.60, Color("c98f6f", 0.75), 7301)
	_band(c, spine, s * 0.34, Color("b8443a", 0.92), 7302)
	_band(c, spine, s * 0.13, Color("32100f", 0.95), 7303)
	ink.stroke(c, ink.jittered_cached(_cvs(_offset(spine, s * 0.60)), 7311), Color(ink.ink, 0.75), 2.2)
	ink.stroke(c, ink.jittered_cached(_cvs(_offset(spine, -s * 0.60)), 7312), Color(ink.ink, 0.75), 2.2)
	if mode == "eye":
		_paint_tears(c)


## The centreline of the wound in rpx: the board's diagonal for a laceration, a ring round the eye
## block for the socket.
func _wound_spine() -> PackedVector2Array:
	var out := PackedVector2Array()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("suture|spine|%d|%s|%d" % [int(ctx.get("seed", 1)), mode, gen])
	if mode == "eye":
		var ctr := BOARD_AT + Vector2(BOARD, BOARD) * 0.5
		var rad := cell_px() * 1.45
		for i in 33:
			var a := TAU * float(i) / 32.0
			out.append(ctr + Vector2(cos(a), sin(a)) * (rad + rng.randf_range(-5.0, 5.0)))
		return out
	var a0 := BOARD_AT + Vector2(10.0, 24.0)
	var a1 := BOARD_AT + Vector2(BOARD - 10.0, BOARD - 24.0)
	for i in 25:
		var k := float(i) / 24.0
		var p := a0.lerp(a1, k)
		var nrm := (a1 - a0).normalized().orthogonal()
		out.append(p + nrm * (sin(k * 7.0) * 9.0 + rng.randf_range(-4.0, 4.0)))
	return out


## The two sides of `spine` `half` rpx apart, as one closed polygon in canvas px.
func _band(c: CanvasItem, spine: PackedVector2Array, half: float, col: Color, _seed_v: int) -> void:
	var poly := PackedVector2Array()
	for q in _offset(spine, half):
		poly.append(cv(q))
	var back := _offset(spine, -half)
	for i in range(back.size() - 1, -1, -1):
		poly.append(cv(back[i]))
	if poly.size() >= 3:
		c.draw_colored_polygon(poly, col)
		ink.ops += 1


## `spine` pushed `d` rpx along its own normal, tapering to nothing at both ends of an open line (a
## closed ring keeps its width all the way round).
func _offset(spine: PackedVector2Array, d: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	var ring: bool = mode == "eye"
	for i in spine.size():
		var a: Vector2 = spine[maxi(0, i - 1)]
		var b: Vector2 = spine[mini(spine.size() - 1, i + 1)]
		var nrm: Vector2 = (b - a).normalized().orthogonal()
		var k := 1.0
		if not ring:
			var u := float(i) / float(maxi(1, spine.size() - 1))
			k = sin(clampf(u, 0.0, 1.0) * PI)
			k = 0.35 + 0.65 * pow(k, 0.45)
		out.append(spine[i] + nrm * d * k)
	return out


func _cvs(pts: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for q in pts:
		out.append(cv(q))
	return out


## SPEC 5: five ragged tears running outward from the torn orbit.
func _paint_tears(c: CanvasItem) -> void:
	var ctr := BOARD_AT + Vector2(BOARD, BOARD) * 0.5
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("suture|tears|%d|%d" % [int(ctx.get("seed", 1)), gen])
	for i in 5:
		var a: float = TAU * float(i) / 5.0 + rng.randf_range(-0.3, 0.3)
		var d := Vector2(cos(a), sin(a))
		var from := ctr + d * cell_px() * 1.5
		var to := ctr + d * cell_px() * rng.randf_range(2.3, 3.0)
		var w := cell_px() * 0.17
		var poly := PackedVector2Array([cv(from + d.orthogonal() * w), cv(to + d.orthogonal() * w * 0.2),
			cv(to - d.orthogonal() * w * 0.2), cv(from - d.orthogonal() * w)])
		c.draw_colored_polygon(poly, Color("8f2020", 0.7))
		ink.seg(c, cv(from), cv(to), Color("32100f", 0.7), 2.0, 7400 + i)


## SPEC 5: every cell the thread has entered gets a skin patch over the gore, ~0.62 cell radius, a
## 0.16 s grow-in and one faint seam line. Undoing pops the patch and the gore comes back.
func _paint_closures(c: CanvasItem) -> void:
	var s := cell_px()
	for i in path.size():
		var cell: int = path[i]
		var k: float = clampf(float(_closed_at.get(cell, 1.0)) / 0.16, 0.0, 1.0)
		k = 1.0 - pow(1.0 - k, 3.0)
		var at := at_of(cell)
		var poly := PackedVector2Array()
		for q in _blob_of(cell):
			poly.append(cv(at + q * s * 0.62 * k))
		if poly.size() < 3:
			continue
		c.draw_colored_polygon(poly, Color(ink.skin_human, 0.97))
		# No outline on the patch: every cell having one turned the closed half of the board into a
		# field of scallops and buried the grid. The seam line below is the whole tell.
		ink.line(c, poly, Color(ink.ink, 0.12), 1.0, 7500 + cell, true)
		var seam := s * 0.30 * k
		ink.seg(c, cv(at + Vector2(-seam, 0.0)), cv(at + Vector2(seam, 0.0)), Color(ink.ink, 0.22), 1.2, 7600 + cell)


## One cell's closure outline, as unit offsets: irregular but never self-crossing.
func _blob_of(cell: int) -> PackedVector2Array:
	if _blob.has(cell):
		return _blob[cell]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("suture|blob|%d|%d" % [int(ctx.get("seed", 1)), cell])
	var pts := PackedVector2Array()
	for i in 11:
		var a := TAU * float(i) / 11.0
		pts.append(Vector2(cos(a), sin(a)) * rng.randf_range(0.90, 1.10))
	_blob[cell] = pts
	return pts


## The board: cell lines, a dot in every open cell, a circled numeral on the numbered ones, and the
## walls as heavy bars on the edges they shut.
func _paint_grid(c: CanvasItem) -> void:
	var s := cell_px()
	var col := Color(ink.ink, 0.30)
	for i in n + 1:
		var o := float(i) * s
		ink.seg(c, cv(BOARD_AT + Vector2(o, 0.0)), cv(BOARD_AT + Vector2(o, BOARD)), col, 1.4, 7700 + i)
		ink.seg(c, cv(BOARD_AT + Vector2(0.0, o)), cv(BOARD_AT + Vector2(BOARD, o)), col, 1.4, 7740 + i)
	ink.rect(c, Rect2(cv(BOARD_AT), Vector2(cl(BOARD), cl(BOARD))), Color(ink.ink, 0.8), 3.0, 7780)
	for cell in n * n:
		if blocked[cell] or nums.has(cell):
			continue
		ink.dot(c, cv(at_of(cell)), cl(s * 0.075), Color(ink.ink, 0.5))
	for key in walls.keys():
		var a: int = int(key) / 4096
		var b: int = int(key) % 4096
		var mid := (at_of(a) + at_of(b)) * 0.5
		var along: Vector2 = (at_of(b) - at_of(a)).normalized().orthogonal() * s * 0.42
		ink.seg(c, cv(mid - along), cv(mid + along), ink.ink, 5.0, 7900 + int(key) % 97)


## The numbered dots, drawn LAST so the thread runs behind them: a circled numeral that fills in once
## the needle has taken it. The spec's draw order puts the dots under the thread, but a 4.5 px line
## straight through the middle of a numeral makes it unreadable, and the numbers are the puzzle.
func _paint_numbers(c: CanvasItem) -> void:
	var s := cell_px()
	var f := InkScript.font_upright()
	var size := int(round(s * 0.44 * _u()))
	for cell in nums.keys():
		var num := int(nums[cell])
		var on: bool = in_path(int(cell))
		var at := cv(at_of(int(cell)))
		# An OPAQUE disc: the thread runs behind it, not through the numeral.
		ink.circle(c, at, cl(s * 0.34), ink.ink, 3.2, 7800 + int(cell), Color(ink.paper, 1.0))
		if on:
			ink.circle(c, at, cl(s * 0.27), Color(ink.good, 0.9), 2.0, 7850 + int(cell),
				Color(ink.good, 0.22))
		var txt := str(num)
		var w: float = f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		# The face is a light serif at this size and a thin numeral disappears against the page, so
		# it is struck twice, half a pixel apart, for weight.
		for o in [Vector2.ZERO, Vector2(0.8, 0.0), Vector2(0.0, 0.8)]:
			c.draw_string(f, at + Vector2(-w * 0.5, float(size) * 0.35) + o, txt,
				HORIZONTAL_ALIGNMENT_LEFT, -1.0, size, ink.ink)
		ink.ops += 3


## SPEC 5: the eye is fenced -- a dashed surgeon's-marker rectangle inset in the 2x2, inward hatch
## ticks on all four edges, and a small DO NOT STITCH label. Bumping it brightens the lot.
func _paint_eye(c: CanvasItem) -> void:
	var s := cell_px()
	var a: int = n / 2 - 1
	var box := Rect2(BOARD_AT + Vector2(float(a) * s, float(a) * s), Vector2(s * 2.0, s * 2.0))
	var hot: float = _fence / maxf(0.01, flash_time)
	# The eyeball itself, under the fence.
	ink.circle(c, cv(box.get_center() - Vector2(0.0, s * 0.10)), cl(s * 0.56), Color(ink.ink, 0.8), 2.6, 8010, Color("d8cfc0", 0.95))
	ink.circle(c, cv(box.get_center() - Vector2(0.0, s * 0.10)), cl(s * 0.24), Color(ink.ink, 0.9), 2.2, 8011, Color("3a5a6a", 0.9))
	ink.dot(c, cv(box.get_center() - Vector2(0.0, s * 0.10)), cl(s * 0.10), Color(ink.ink, 0.95))
	var col: Color = ink.deep_red if hot > 0.0 else Color(ink.deep_red, 0.75)
	if hot > 0.0:
		c.draw_rect(Rect2(cv(box.position), box.size * _u()), Color(ink.deep_red, 0.18 * hot))
	var fence := box.grow(-s * 0.16)
	var p0 := cv(fence.position)
	var p1 := cv(Vector2(fence.end.x, fence.position.y))
	var p2 := cv(fence.end)
	var p3 := cv(Vector2(fence.position.x, fence.end.y))
	for e in [[p0, p1], [p1, p2], [p2, p3], [p3, p0]]:
		ink.dashed(c, e[0], e[1], col, 2.2, 8.0, 6.0)
	# Inward hatch ticks on all four edges.
	var ticks := 5
	for i in ticks:
		var k := (float(i) + 0.5) / float(ticks)
		var inw := s * 0.22 * (1.0 + 0.4 * hot)
		ink.seg(c, cv(fence.position + Vector2(fence.size.x * k, 0.0)),
			cv(fence.position + Vector2(fence.size.x * k - inw * 0.4, inw)), col, 1.6, 8100 + i)
		ink.seg(c, cv(Vector2(fence.position.x + fence.size.x * k, fence.end.y)),
			cv(Vector2(fence.position.x + fence.size.x * k + inw * 0.4, fence.end.y - inw)), col, 1.6, 8120 + i)
		ink.seg(c, cv(Vector2(fence.position.x, fence.position.y + fence.size.y * k)),
			cv(Vector2(fence.position.x + inw, fence.position.y + fence.size.y * k + inw * 0.4)), col, 1.6, 8140 + i)
		ink.seg(c, cv(Vector2(fence.end.x, fence.position.y + fence.size.y * k)),
			cv(Vector2(fence.end.x - inw, fence.position.y + fence.size.y * k - inw * 0.4)), col, 1.6, 8160 + i)
	# INSIDE the fence, under the eyeball: out on the page it landed on the torn ring, or under
	# whichever numbered dot happened to sit below the eye, and could not be read either way.
	var lab := Vector2(box.get_center().x, box.get_center().y + s * 0.66)
	c.draw_rect(Rect2(cv(lab + Vector2(-52.0, -11.0)), Vector2(cl(104.0), cl(16.0))), Color(ink.paper, 0.9))
	ink.text(c, cv(lab), "DO NOT STITCH", 11.0, col, 1)


## SPEC 4: one ink line, hand-wobbled, with a needle glyph at the head and a dashed lead to the
## cursor while dragging. One line: an earlier pass stacked shadow, core and highlight and it read as
## clutter at this cell size.
func _paint_thread(c: CanvasItem) -> void:
	if path.is_empty():
		return
	var pts := PackedVector2Array()
	for cell in path:
		pts.append(cv(at_of(cell)))
	if pts.size() >= 2:
		ink.stroke(c, ink.jittered(pts, 8200), ink.ink, 4.5)
	else:
		ink.dot(c, pts[0], cl(4.0), ink.ink)
	# SPEC 4: the win resolves the path into perpendicular stitch ticks.
	if state != State.PLAY:
		var k: float = 1.0 - clampf(resolve / maxf(0.01, resolve_time), 0.0, 1.0)
		var s := cell_px()
		for i in range(1, path.size()):
			if float(i) / float(maxi(1, path.size() - 1)) > k:
				break
			var a := at_of(path[i - 1])
			var b := at_of(path[i])
			var mid := (a + b) * 0.5
			var nrm := (b - a).normalized().orthogonal() * s * 0.20
			ink.seg(c, cv(mid - nrm), cv(mid + nrm), ink.ink, 3.0, 8300 + i)
	var h := at_of(head())
	if state == State.PLAY:
		if _dragging:
			ink.dashed(c, cv(h), cv(_cursor), Color(ink.ink, 0.45), 1.8, 6.0, 5.0)
		_paint_needle(c, h)


## The needle at the head of the thread: a short curved bite with an eye at its back end.
func _paint_needle(c: CanvasItem, at: Vector2) -> void:
	var s := cell_px()
	var a := at + Vector2(-s * 0.22, s * 0.16)
	var b := at + Vector2(s * 0.24, -s * 0.18)
	ink.seg(c, cv(a), cv(b), ink.ink, 3.2, 8400)
	ink.dot(c, cv(b), cl(3.0), ink.ink)
	ink.circle(c, cv(a), cl(s * 0.07), ink.ink, 1.6, 8401, Color(ink.paper, 0.9))


func _paint_flash(c: CanvasItem) -> void:
	var s := cell_px()
	for cell in _flash.keys():
		var k: float = clampf(float(_flash[cell]) / maxf(0.01, flash_time), 0.0, 1.0)
		var at := at_of(int(cell))
		c.draw_rect(Rect2(cv(at - Vector2(s, s) * 0.5), Vector2(s, s) * _u()), Color(ink.deep_red, 0.42 * k))
	if _tint > 0.0:
		var k2: float = clampf(_tint / maxf(0.01, flash_time), 0.0, 1.0)
		c.draw_rect(Rect2(cv(Vector2.ZERO), REF * _u()), Color(ink.deep_red, 0.05 * k2))


## SPEC 2: the variant button under the board. The debug build also gets New puzzle and Clear thread
## (`--solution` on the command line turns them and the dashed green overlay on).
func _paint_buttons(c: CanvasItem) -> void:
	_button(c, _btn_variant, "EYE SOCKET" if mode == "laceration" else "DEEP LACERATION", 8500)
	if show_solution:
		_button(c, _btn_new, "NEW PUZZLE", 8501)
		_button(c, _btn_clear, "CLEAR THREAD", 8502)
	var left: int = open_count() - path.size()
	ink.text(c, cv(Vector2(BOARD_AT.x + BOARD, 540.0)),
		"%d cells left   ·   %d pulled out" % [left, undos], 13.0, Color(ink.label, 0.9), 2)


func _button(c: CanvasItem, r: Rect2, label: String, seed_v: int) -> void:
	var box := Rect2(cv(r.position), r.size * _u())
	var over: bool = r.has_point(_cursor)
	ink.rect(c, box, Color(ink.ink, 0.85), 2.0, seed_v, Color(ink.paper.darkened(0.08 if over else 0.02), 0.95))
	ink.text(c, cv(r.get_center() + Vector2(0.0, 5.0)), label, 13.0, Color(ink.ink, 0.9), 1)


## Debug only: the solution the puzzle was built from, as a dashed green path.
func _paint_solution(c: CanvasItem) -> void:
	for i in range(1, sol.size()):
		ink.dashed(c, cv(at_of(sol[i - 1])), cv(at_of(sol[i])), Color(ink.good, 0.7), 2.0, 6.0, 5.0)


## Warmup (scripts/warmup.gd): draw both variants, a thread, a closure and the result card once, so
## nothing compiles mid-step.
func warm_all() -> void:
	_warm = true
	for i in mini(5, sol.size()):
		path.append(sol[i])
		_close_cell(sol[i])
	_flash[sol[sol.size() - 1] if not sol.is_empty() else 0] = flash_time
	_tint = flash_time
	if shell != null:
		shell.mistake("TUGGED!", shell.area.get_center(), false, 0)
	if panel != null:
		panel.redraw()
	# And the other variant's board, then put it back the way it was.
	var keep_mode := mode
	var keep_path := path
	var keep_gen := gen
	mode = "eye" if mode == "laceration" else "laceration"
	n = grid_size()
	generate()
	show_solution = true
	if panel != null:
		panel.redraw()
	show_solution = false
	mode = keep_mode
	gen = keep_gen
	n = grid_size()
	generate()
	path = keep_path
	if panel != null:
		panel.redraw()


# ---------------------------------------------------------------------------- net

## What an onlooker needs. The board itself is rebuilt from `md`, `gn` and `gg` on every machine, so
## the puzzle never goes over the wire. NOTHING THAT CREEPS IS SNAPPED (the lab round-trips this
## dictionary every frame, and a value snapped to its own quantum never moves).
func net_pack() -> Dictionary:
	return {"md": mode, "gn": n, "gg": gen, "sa": state, "pa": path, "vt": vit, "ud": undos,
		"so": solve_t, "rv": resolve, "fl": flatlined, "sc": score, "gr": _grade,
		"bq": bad_seq, "bc": bad_cell}


func net_apply(s: Dictionary) -> void:
	var md := String(s.get("md", mode))
	var gn := int(s.get("gn", n))
	var gg := int(s.get("gg", gen))
	if md != mode or gn != n or gg != gen:
		mode = md
		n = gn
		gen = gg
		generate()
	state = int(s.get("sa", state))
	var pa = s.get("pa", null)
	if pa is PackedInt32Array:
		path = pa
		# The closures follow the path: a cell an onlooker has not seen shut yet grows in here.
		for cell in path:
			if not _closed_at.has(cell):
				_closed_at[cell] = 1.0
		for cell in _closed_at.keys():
			if not path.has(int(cell)):
				_closed_at.erase(cell)
	vit = float(s.get("vt", vit))
	undos = int(s.get("ud", undos))
	solve_t = float(s.get("so", solve_t))
	resolve = float(s.get("rv", resolve))
	flatlined = bool(s.get("fl", flatlined))
	score = int(s.get("sc", score))
	_grade = String(s.get("gr", _grade))
	bad_cell = int(s.get("bc", bad_cell))
	bad_seq = int(s.get("bq", bad_seq))
	_update_progress()


# ---------------------------------------------------------------------------- bot

## The bot walks the solution it was built from, one cell at a time with the button held. A sloppy
## hand aims at the wrong neighbour now and then, which either bounces off a wall (a flash) or has to
## be pulled back out (the real cost). Cards get a press after a reaction delay.
func bot_input(t: float, skill: float) -> Dictionary:
	var dt: float = clampf(t - _bt, 0.0, 0.1)
	_bt = t
	skill = clampf(skill, 0.0, 1.0)
	var cur := metres_of_ref(_b_aim)
	var none := {"cursor": cur, "buttons": 0}
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
			return {"cursor": cur, "buttons": BUTTON_ACTION}
		return none
	if not armed():
		return none
	if _b_up:
		_b_up = false
		return none
	if state == State.RESULT:
		return {"cursor": cur, "buttons": BUTTON_ACTION}
	if state != State.PLAY or sol.is_empty():
		return none
	# Where along the solution the thread has got to.
	var i := path.size()
	if i == 0:
		_b_aim = at_of(sol[0])
		return {"cursor": metres_of_ref(_b_aim), "buttons": BUTTON_PRIMARY}
	# Off the solution (a slip): back out the way it came.
	if path[path.size() - 1] != sol[mini(i - 1, sol.size() - 1)]:
		_b_aim = at_of(path[maxi(0, path.size() - 2)])
		return {"cursor": metres_of_ref(_b_aim), "buttons": BUTTON_PRIMARY}
	if i >= sol.size():
		return none
	var want: int = sol[i]
	# A sloppy hand sometimes reaches for a neighbour that is not the next one.
	if skill < 0.99 and fposmod(_bt * 3.7 + float(_b_slip), 1.0) > lerpf(0.72, 1.0, skill):
		_b_slip += 1
		var opts := _nbrs(path[path.size() - 1])
		if not opts.is_empty():
			want = opts[_b_slip % opts.size()]
	_b_aim = at_of(want)
	return {"cursor": metres_of_ref(_b_aim), "buttons": BUTTON_PRIMARY}


# ---------------------------------------------------------------------------- self-test

## Headless: `godot --headless --path . --fixed-fps 60 tools/minigame_lab.tscn -- --selftest=suture`
static func self_test() -> Array:
	var script: GDScript = load("res://scripts/surgery/arcade/suture_arcade.gd")
	var out := []
	var ok := true
	# THE GENERATION CHECK (spec 3): many puzzles across both variants and every grid size, each one
	# re-solved by an INDEPENDENT solver that respects the numbers and the walls. This is the source
	# spec's "verified over 40 generated puzzles", done every run.
	var gen_r := _generation_check(script, 120)
	print("[suture self-test] generation: %d puzzles over %s, every one solvable=%s; numbers %d-%d, walls %d-%d, worst search %.1f ms" % [
		gen_r.n, str(gen_r.sizes), "yes" if gen_r.bad == 0 else "NO (%d failed)" % gen_r.bad,
		gen_r.num_lo, gen_r.num_hi, gen_r.wall_lo, gen_r.wall_hi, gen_r.worst_ms])
	if gen_r.bad > 0 or gen_r.n < 120 or gen_r.worst_ms > 25.0:
		print("[suture self-test] MISS: every generated puzzle must have a full-coverage solution, found in a few ms")
		ok = false
	# The rules: walls stop the needle, the eye stops the needle, numbers must come in order, and a
	# fast drag is walked cell by cell instead of snapping.
	var rules_r := _rules_check(script)
	print("[suture self-test] rules: wall refused=%s, eye refused=%s, out-of-order dot refused=%s, a drag across the board walked %d cells (never teleports), re-entering a cell refused=%s" % [
		"yes" if rules_r.wall else "NO", "yes" if rules_r.eye else "NO", "yes" if rules_r.order else "NO",
		rules_r.walked, "yes" if rules_r.revisit else "NO"])
	if not rules_r.wall or not rules_r.eye or not rules_r.order or not rules_r.revisit or rules_r.walked < 2:
		print("[suture self-test] MISS: the move rules")
		ok = false
	# Undo: backing up pops the head and bills 1.6 a segment; an illegal move bills nothing at all.
	var undo_r := _undo_check(script)
	print("[suture self-test] undo: pulling back 3 cost %.1f vitals and %d undos; 5 illegal moves cost %.1f" % [
		undo_r.cost, undo_r.undos, undo_r.illegal_cost])
	if absf(undo_r.cost - 4.8) > 0.01 or undo_r.undos != 3 or undo_r.illegal_cost > 0.0001:
		print("[suture self-test] MISS: undo costs 1.6 a segment and an illegal move costs nothing")
		ok = false
	# The grade bands (spec 7).
	var gr := _grade_check(script)
	print("[suture self-test] grades: 40 s clean run %d %s, 90 s with 6 undos %d %s, flatline %d %s" % [
		gr.best, gr.best_w, gr.mid, gr.mid_w, gr.bad, gr.bad_w])
	if gr.best_w != "CLEAN" or gr.mid_w == "CLEAN" or gr.bad_w != "MALPRACTICE" or gr.bad != 0:
		print("[suture self-test] MISS: the grade bands")
		ok = false
	# SPEC 5: blood never lands on the board.
	# SPEC 7: the results card has a Retry, and right mouse takes it -- a slow deliberate puzzle is
	# worth another go, unlike the live cases the other three steps run.
	var rt := _retry_check(script)
	print("[suture self-test] retry: from the %s card, right mouse gave back a board with %d stitches, %.0f%% vitals and %d undos (was %d, %.0f%%, %d)" % [
		rt.grade, rt.laid, rt.vit, rt.undos, rt.laid0, rt.vit0, rt.undos0])
	if rt.laid != 0 or rt.vit < 99.9 or rt.undos != 0 or not rt.playing:
		print("[suture self-test] MISS: Retry must hand back a fresh, playable board")
		ok = false
	var splat_r := _splat_check(script)
	print("[suture self-test] blood: %d splat polygons thrown, %d of them touched the board" % [splat_r[0], splat_r[1]])
	if splat_r[0] < 10 or splat_r[1] > 0:
		print("[suture self-test] MISS: splats must be rejection-sampled off the board")
		ok = false
	# A bot has to be able to close both variants, and an onlooker has to see what it sees.
	for m: String in ["laceration", "eye"]:
		for skill: float in [1.0, 0.6]:
			var g = script.new()
			var tally := {"done": false, "v": 0.0, "marks": ""}
			g.botched.connect(func(a, _r): tally.v += a)
			g.finished.connect(func(r): tally.done = true; tally.marks = String(r.get("stitch_marks", "")))
			g.setup(_case(m))
			var t: float = run_bot(g, skill, 1.0, hash(m) + int(skill * 100), 400.0)
			print("[suture self-test] %-10s skill=%.1f  %s  %dx%d  laid %d of %d  undos=%2d  vitals=%5.1f  score=%3d %-11s  time=%5.1fs  bill=%4.1f" % [
				m, skill, "DONE" if tally.done else "UNFINISHED", g.n, g.n, g.path.size(), g.open_count(),
				g.undos, g.vit, g.score, g._grade, t, tally.v])
			out.append({"mode": m, "skill": skill, "done": tally.done, "score": g.score, "time": t})
			if not tally.done:
				print("[suture self-test] MISS: every hand has to be able to finish")
				ok = false
			g.free()
	var net := _net_check(script)
	print("[suture self-test] spectator: %d stitches vs %d, vitals %.2f vs %.2f, undos %d vs %d, board %s vs %s" % net)
	if net[0] != net[1] or absf(net[2] - net[3]) > 0.02 or net[4] != net[5] or net[6] != net[7]:
		print("[suture self-test] MISS: a spectator does not see what the operator sees")
		ok = false
	print("[suture self-test] %s" % ("PASS" if ok else "FAIL"))
	return out


## Finish a run, then press right mouse on the results card: the step must be playable again.
static func _retry_check(script: GDScript) -> Dictionary:
	var dt := 1.0 / 60.0
	var g = script.new()
	g.setup(_case("laceration"))
	_armed(g)
	g.vit = 40.0
	g.undos = 7
	g.solve_t = 50.0
	for i in mini(6, g.sol.size()):
		g.path.append(g.sol[i])
	g._to_result()
	var r := {"grade": g._grade, "laid0": g.path.size(), "vit0": g.vit, "undos0": g.undos}
	for i in int(g.result_lock * 60.0) + 4:
		g.handle_cursor(Vector2.ZERO, 0, dt)
		g.tick(dt)
	g.handle_cursor(Vector2.ZERO, BUTTON_SECONDARY, dt)
	g.tick(dt)
	g.handle_cursor(Vector2.ZERO, 0, dt)
	g.tick(dt)
	r.laid = g.path.size()
	r.vit = g.vit
	r.undos = g.undos
	r.playing = g.armed() and not g.done
	g.free()
	return r


static func _case(mode_v: String) -> Dictionary:
	return {"patient_id": "bob", "patient": Procedures.patient("bob"), "ailment_id": "gunshot",
		"step": Procedures.step("gunshot", 3), "variant": mode_v, "shift": 1,
		"difficulty": Procedures.difficulty(1),
		"flags": {"sedation": 1.0, "bullet_removed": true, "dressed": true},
		"seed": hash("suture" + mode_v), "body": null, "operator": true, "operating": true}


static func _armed(g) -> void:
	var dt := 1.0 / 60.0
	for i in 30:
		g.handle_cursor(Vector2.ZERO, 0, dt)
		g.tick(dt)
	g.handle_cursor(Vector2.ZERO, BUTTON_ACTION, dt)
	g.tick(dt)
	g.handle_cursor(Vector2.ZERO, 0, dt)
	g.tick(dt)


## SPEC 3's claim, checked rather than asserted: generate many puzzles and re-solve each one with an
## independent depth-first solver that obeys the numbers and the walls (and knows nothing about the
## path it was built from).
static func _generation_check(script: GDScript, count: int) -> Dictionary:
	var r := {"n": 0, "bad": 0, "sizes": [], "num_lo": 99, "num_hi": 0, "wall_lo": 99, "wall_hi": 0,
		"worst_ms": 0.0}
	var sizes := {}
	for i in count:
		var m: String = "eye" if i % 3 == 2 else "laceration"
		var g = script.new()
		g.laceration_size = "4" if i % 2 == 0 else "5"
		var ctx_v := _case(m)
		ctx_v["seed"] = 1000 + i
		g.setup(ctx_v)
		var t0 := Time.get_ticks_usec()
		g.gen = i
		g.generate()
		r.worst_ms = maxf(r.worst_ms, float(Time.get_ticks_usec() - t0) / 1000.0)
		r.n += 1
		sizes[g.n] = true
		r.num_lo = mini(r.num_lo, g.num_cells.size())
		r.num_hi = maxi(r.num_hi, g.num_cells.size())
		r.wall_lo = mini(r.wall_lo, g.walls.size())
		r.wall_hi = maxi(r.wall_hi, g.walls.size())
		if g.sol.size() != g.open_count() or not _solvable(g):
			r.bad += 1
		g.free()
	var keys := sizes.keys()
	keys.sort()
	r.sizes = keys
	return r


## An independent solver: depth-first over the open cells from the dot-1 cell, refusing walls, cells
## already on the path and numbered cells out of turn, pruned by "everything left must still be
## reachable". True when a full-coverage solution exists.
static func _solvable(g) -> bool:
	var start := -1
	for c in g.nums.keys():
		if int(g.nums[c]) == 1:
			start = int(c)
	if start < 0:
		return false
	var seen: Array[bool] = []
	seen.resize(g.n * g.n)
	for i in g.n * g.n:
		seen[i] = false
	return _solve_from(g, start, seen, 0, g.open_count(), [400000])


static func _solve_from(g, c: int, seen: Array[bool], taken: int, want: int, budget: Array) -> bool:
	if g.nums.has(c):
		if int(g.nums[c]) != taken + 1:
			return false
		taken += 1
	seen[c] = true
	var left := 0
	for v in seen.size():
		if not seen[v] and not g.blocked[v]:
			left += 1
	if left == 0:
		seen[c] = false
		return taken == g.num_cells.size()
	budget[0] -= 1
	if budget[0] <= 0:
		seen[c] = false
		return false
	# Prune: whatever is left has to still hang together with where the needle is.
	if not _reachable_all(g, c, seen, left):
		seen[c] = false
		return false
	var ranked: Array = []
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var nx: int = g.cx(c) + d.x
		var ny: int = g.cy(c) + d.y
		if not g.in_grid(nx, ny):
			continue
		var to: int = g.cell_of(nx, ny)
		if g.blocked[to] or seen[to] or g.walled(c, to):
			continue
		var onward := 0
		for e in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var mx: int = g.cx(to) + e.x
			var my: int = g.cy(to) + e.y
			if g.in_grid(mx, my) and not g.blocked[g.cell_of(mx, my)] and not seen[g.cell_of(mx, my)] \
					and not g.walled(to, g.cell_of(mx, my)):
				onward += 1
		ranked.append([onward, to])
	ranked.sort_custom(func(a, b): return a[0] < b[0])
	for e in ranked:
		if _solve_from(g, int(e[1]), seen, taken, want, budget):
			seen[c] = false
			return true
	seen[c] = false
	return false


## Every unvisited open cell still reachable from `c` through open, unwalled, unvisited cells.
static func _reachable_all(g, c: int, seen: Array[bool], left: int) -> bool:
	var stack: Array[int] = []
	var hit := {}
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var nx: int = g.cx(c) + d.x
		var ny: int = g.cy(c) + d.y
		if g.in_grid(nx, ny):
			var to: int = g.cell_of(nx, ny)
			if not g.blocked[to] and not seen[to] and not g.walled(c, to):
				stack.append(to)
				hit[to] = true
	while not stack.is_empty():
		var v: int = stack.pop_back()
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nx: int = g.cx(v) + d.x
			var ny: int = g.cy(v) + d.y
			if not g.in_grid(nx, ny):
				continue
			var to: int = g.cell_of(nx, ny)
			if g.blocked[to] or seen[to] or hit.has(to) or g.walled(v, to):
				continue
			hit[to] = true
			stack.append(to)
	return hit.size() >= left


static func _rules_check(script: GDScript) -> Dictionary:
	var r := {"wall": false, "eye": false, "order": false, "walked": 0, "revisit": false}
	# A wall: find one and try to cross it from a head sitting on one of its cells.
	var g = script.new()
	g.wall_count = 4
	g.setup(_case("laceration"))
	_armed(g)
	for key in g.walls.keys():
		var a: int = int(key) / 4096
		var b: int = int(key) % 4096
		g.path = PackedInt32Array([a])
		r.wall = not g.legal_step(a, b)
		break
	# Numbers out of order: dot 2 is not a legal first step from dot 1's neighbours.
	var one := -1
	for c in g.nums.keys():
		if int(g.nums[c]) == 1:
			one = int(c)
	g.path = PackedInt32Array([one])
	r.order = true
	for c in g.nums.keys():
		if int(g.nums[c]) >= 3 and g.legal_step(one, int(c)):
			r.order = false
	# Re-entering a cell already on the thread.
	if g.sol.size() >= 3:
		g.path = PackedInt32Array([g.sol[0], g.sol[1], g.sol[2]])
		r.revisit = not g.legal_step(g.sol[2], g.sol[1])
	# A fast drag: one event, a cursor several cells away, and the thread must have WALKED there.
	g.path = PackedInt32Array([g.sol[0]])
	g._dragging = true
	g._walk_toward(g.sol[mini(3, g.sol.size() - 1)])
	r.walked = g.path.size()
	g.free()
	# The eye block: no step ever enters it.
	var e = script.new()
	e.setup(_case("eye"))
	_armed(e)
	r.eye = true
	for c in e.eye_cells():
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nx: int = e.cx(c) + d.x
			var ny: int = e.cy(c) + d.y
			if e.in_grid(nx, ny) and not e.blocked[e.cell_of(nx, ny)]:
				e.path = PackedInt32Array([e.cell_of(nx, ny)])
				if e.legal_step(e.cell_of(nx, ny), c):
					r.eye = false
	e.free()
	return r


static func _undo_check(script: GDScript) -> Dictionary:
	var g = script.new()
	var bill := {"v": 0.0}
	g.botched.connect(func(a, _r): bill.v += a)
	g.setup(_case("laceration"))
	_armed(g)
	g.path = PackedInt32Array()
	for i in 6:
		g.path.append(g.sol[i])
	var v0: float = g.vit
	for i in 3:
		g._pop()
	var r := {"cost": v0 - g.vit, "undos": g.undos, "illegal_cost": 0.0}
	var v1: float = g.vit
	for i in 5:
		g._refuse(g.sol[0])
	r.illegal_cost = v1 - g.vit
	g.free()
	return r


static func _grade_check(script: GDScript) -> Dictionary:
	var r := {}
	var g = script.new()
	g.setup(_case("laceration"))
	# A 40 s solve at the base seep: about 17% lost, nothing pulled out.
	g.solve_t = 40.0
	g.vit = 100.0 - 0.42 * 40.0
	g.undos = 0
	r.best = g.grade_score()
	r.best_w = g.grade_word()
	g.solve_t = 90.0
	g.vit = 100.0 - 0.42 * 90.0 - 6.0 * 1.6
	g.undos = 6
	r.mid = g.grade_score()
	r.mid_w = g.grade_word()
	g.flatlined = true
	g.vit = 0.0
	r.bad = g.grade_score()
	r.bad_w = g.grade_word()
	g.free()
	return r


## SPEC 5: every splat the shell throws for this step lands off the board.
static func _splat_check(script: GDScript) -> Array:
	var g = script.new()
	g.setup(_case("laceration"))
	var board := Rect2(g.cv(BOARD_AT), Vector2(g.cl(BOARD), g.cl(BOARD)))
	var polys: Array = g.shell.splat_polys_for(TUG_FROM, 20)
	var hit := 0
	for p in polys:
		for q in p:
			if board.has_point(q):
				hit += 1
				break
	var r := [polys.size(), hit]
	g.free()
	return r


## The operator plays; the onlooker only ever gets net_state and must land on the same board.
static func _net_check(script: GDScript) -> Array:
	var op = script.new()
	var spec = script.new()
	op.setup(_case("eye"))
	var sctx := _case("eye")
	sctx["operator"] = false
	spec.setup(sctx)
	var dt := 1.0 / 60.0
	var t := 0.0
	var k := 0
	while t < 300.0 and not op.done:
		t += dt
		var inp: Dictionary = op.bot_input(t, 0.8)
		op.handle_cursor(inp.get("cursor", Vector2.ZERO), int(inp.get("buttons", 0)), dt)
		op.tick(dt)
		spec.tick(dt)
		k += 1
		if k % 3 == 0:
			spec.apply_net_state(op.net_state())
	spec.apply_net_state(op.net_state())
	spec.tick(dt)
	var r := [op.path.size(), spec.path.size(), op.vit, spec.vit, op.undos, spec.undos,
		"%s|%d|%d" % [op.mode, op.n, op.gen], "%s|%d|%d" % [spec.mode, spec.n, spec.gen]]
	op.free()
	spec.free()
	return r
