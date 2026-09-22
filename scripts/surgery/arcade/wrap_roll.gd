extends RefCounted
## WRAP! -- Snake, played straight, as a bandage going onto a wound.
## docs/PACK_AND_WRAP_SPEC.md section 3. Shared by both steps that wrap something:
##   - the gunshot wound's dressing (pack_wrap_arcade.gd), where WHACK! decides how many cells bleed
##   - the amputation's stump (wrap_stump_arcade.gd), where the tourniquet decides it
## Neither owns the rules: they build one of these, steer it, and draw it.
##
## THE GENRE, HONESTLY PLAYED. The brief's first pass bolted timed soak-through, overlap rules and a
## kidney dish onto Snake until it was bookkeeping. This is grow-by-eating, die-on-yourself, with two
## words swapped:
##   THE TAIL IS THE GAUZE IN HAND. Tail length always equals cells carried. Eat a gauze pickup and
##   the tail grows a segment; lay a layer on the wound and it loses one the same instant. An
##   empty-handed head has no tail at all, so "go fetch more" is a shape, not a number.
##   THE TRAIL IS BANDAGE ON THE WOUND. Driving onto a wound cell that still wants a layer, carrying
##   at least one, spends one and lays it. Driving over it empty-handed does nothing -- you can never
##   wipe coverage off by passing over it.
## There is no special case for crossing your own trail, because Snake does not have one: hitting a
## wall or any tail segment is a tangle, and that is the whole death rule.
##
## A tangle costs vitals and momentum, never progress: the roll respawns on the left edge still
## carrying exactly what it was carrying when it crashed, and every layer already laid stays laid.
##
## Bleeding cells (bleedCells) want TWO layers instead of one and carry a x2 tag. Their share of the
## wound is whatever the step before this one handed over.
##
## Everything is in the owner's 960 x 600 reference pixels ("rpx"); the owner's cv()/cl() put it on
## the page. `pack()` / `unpack()` are the replicated half, so an onlooker watches it live.

const DIRS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1)]

# -- the board (spec 3.1) -------------------------------------------------------------------------
var cols := 16
var rows := 10
## Reference px per cell, and where the grid's top-left corner sits on the page.
var cell_px := 52.0
var origin := Vector2(64.0, 52.0)
## Cells the flood-filled wound blob aims for, and the chance it branches into each free neighbour.
var blob_cells := 14
var branch_chance := 0.62
## Gauze pickups kept on the board at once, and what the roll starts with in hand (spec 5).
var pickups_out := 3
var start_carry := 1

# -- tuning (spec 5) ------------------------------------------------------------------------------
## Seconds per cell ("snakeRate", 0.08-0.3).
var step_time := 0.16
## Every wound cell at its required layers for this long finishes the stage.
var done_hold := 0.5
## What a tangle costs, for the owner to bill.
var tangle_cost := 5.0

# -- the wound ------------------------------------------------------------------------------------
var wound: Array[int] = []            ## grid cell indices, in lay-out order
var wound_at := {}                    ## grid cell index -> position in `wound`
var bleeding: Array[bool] = []        ## per wound position: wants two layers, tagged x2
var layers: Array[int] = []           ## per wound position: layers laid so far

# -- the roll -------------------------------------------------------------------------------------
## The snake. body[0] is the head; everything after it is tail, and tail length IS what is carried.
var body: Array[Vector2i] = []
var dir := Vector2i(1, 0)
var want_dir := Vector2i(1, 0)
## 0..1 of the way into the next cell. THIS CREEPS: never snap it in a net blob.
var sub := 0.0
var pickups: Array[int] = []
var finished := false
var hold := 0.0                       ## seconds the wound has been fully covered

# -- the tally ------------------------------------------------------------------------------------
var tangles := 0
var laid := 0                         ## layers actually put down
var eaten := 0

var _rng := RandomNumberGenerator.new()
var _spawn_n := 0                     ## how many pickups have ever been spawned (seeds the next one)


# ---------------------------------------------------------------------------- setup

## Lay out the board from the case seed. `bleed_frac` is the share of wound cells that want two
## layers: 1 - pack quality for the gunshot wound, whatever the tourniquet left for the stump.
func build(seed_v: int, variant: String, bleed_frac: float) -> void:
	_rng.seed = hash("wrap_roll|%s|%d" % [variant, seed_v])
	wound.clear()
	wound_at.clear()
	bleeding.clear()
	layers.clear()
	_flood()
	var n := wound.size()
	# The bleeders are spread through the blob rather than clumped at its start, so a bad pack is a
	# routing problem all over the wound instead of one hot corner.
	var want: int = clampi(int(round(clampf(bleed_frac, 0.0, 1.0) * float(n))), 0, n)
	var order: Array[int] = []
	for i in n:
		order.append(i)
		bleeding.append(false)
		layers.append(0)
	for i in range(order.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var t: int = order[i]
		order[i] = order[j]
		order[j] = t
	for i in want:
		bleeding[order[i]] = true
	# The roll starts on the left edge with the spec's one cell of gauze in hand.
	_place_on_left(start_carry)
	pickups.clear()
	_spawn_n = 0
	_top_up_pickups()


## A wound blob: from a seed cell near the middle, take free neighbours with `branch_chance` until it
## is `blob_cells` big. Flood-filled, so it is always one connected shape you can drive round.
func _flood() -> void:
	var start := Vector2i(_rng.randi_range(4, cols - 5), _rng.randi_range(2, rows - 3))
	var open: Array[Vector2i] = [start]
	var seen := {cell_index(start): true}
	_add_wound(start)
	var guard := 0
	while wound.size() < blob_cells and not open.is_empty() and guard < 4000:
		guard += 1
		var from: Vector2i = open[_rng.randi_range(0, open.size() - 1)]
		var grew := false
		for d in DIRS:
			if wound.size() >= blob_cells:
				break
			var c: Vector2i = from + d
			# One clear cell of margin all round, so the wound is never flush against a wall you die on.
			if c.x < 1 or c.y < 1 or c.x > cols - 2 or c.y > rows - 2:
				continue
			var idx := cell_index(c)
			if seen.has(idx) or _rng.randf() > branch_chance:
				continue
			seen[idx] = true
			_add_wound(c)
			open.append(c)
			grew = true
		if not grew and open.size() > 1:
			open.erase(from)


func _add_wound(c: Vector2i) -> void:
	var idx := cell_index(c)
	if wound_at.has(idx):
		return
	wound_at[idx] = wound.size()
	wound.append(idx)


## Put the roll on the left edge carrying `carry`, heading right, its tail stacked on the head so it
## unfurls as it goes. Used at the start and after every tangle.
func _place_on_left(carry: int) -> void:
	var row := _rng.randi_range(0, rows - 1)
	# Not straight into the wound, and not onto a row whose first cells are wound: give it a run-up.
	var tries := 0
	while tries < rows * 2 and (wound_at.has(cell_index(Vector2i(0, row))) or wound_at.has(cell_index(Vector2i(1, row)))):
		row = (row + 1) % rows
		tries += 1
	body.clear()
	for i in maxi(1, carry + 1):
		body.append(Vector2i(0, row))
	dir = Vector2i(1, 0)
	want_dir = dir
	sub = 0.0


## Keep `pickups_out` rolls of gauze on the board, never on the wound, the roll or another pickup.
func _top_up_pickups() -> void:
	var guard := 0
	while pickups.size() < pickups_out and guard < 500:
		guard += 1
		var r := RandomNumberGenerator.new()
		r.seed = hash("wrap_gauze|%d|%d" % [_rng.seed, _spawn_n])
		var c := Vector2i(r.randi_range(0, cols - 1), r.randi_range(0, rows - 1))
		_spawn_n += 1
		var idx := cell_index(c)
		if wound_at.has(idx) or pickups.has(idx) or body.has(c):
			continue
		pickups.append(idx)


# ---------------------------------------------------------------------------- the grid

func cell_index(c: Vector2i) -> int:
	return c.y * cols + c.x


func cell_of(i: int) -> Vector2i:
	return Vector2i(i % cols, i / cols)


func in_bounds(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < cols and c.y < rows


## The centre of grid cell `c`, in the owner's reference px.
func at_of(c: Vector2i) -> Vector2:
	return origin + (Vector2(c) + Vector2(0.5, 0.5)) * cell_px


## Where the head is right now, in rpx, smoothed between cells so it glides.
func head_at() -> Vector2:
	if body.is_empty():
		return origin
	return at_of(body[0]) + Vector2(dir) * cell_px * clampf(sub, 0.0, 1.0)


## How many layers wound position `w` wants: two for a bleeding cell, one for a dry one.
func need(w: int) -> int:
	return 2 if w < bleeding.size() and bleeding[w] else 1


func satisfied(w: int) -> bool:
	return w < layers.size() and layers[w] >= need(w)


## Cells of gauze in hand. The tail IS the gauze: this is just its length.
func carry() -> int:
	return maxi(0, body.size() - 1)


func total_need() -> int:
	var n := 0
	for w in wound.size():
		n += need(w)
	return n


## 0..1 of the wound covered, counting a bleeding cell's second layer.
func frac() -> float:
	var want := total_need()
	if want <= 0:
		return 1.0
	var got := 0
	for w in wound.size():
		got += mini(layers[w], need(w))
	return clampf(float(got) / float(want), 0.0, 1.0)


func all_covered() -> bool:
	for w in wound.size():
		if not satisfied(w):
			return false
	return true


## Wound cells still short a layer -- what the hint and the body's bleeding read off.
func open_cells() -> int:
	var n := 0
	for w in wound.size():
		if not satisfied(w):
			n += 1
	return n


# ---------------------------------------------------------------------------- playing

## True Snake steering: a queued turn can never reverse into the neck.
func steer(d: Vector2i) -> void:
	if d == Vector2i.ZERO or d == -dir:
		return
	want_dir = d


## Run the roll for `delta`. Returns the events the owner has to react to (sounds, bursts, the bill):
## {"e": "tangle"|"eat"|"lay"|"done", "at": rpx, ...}.
func advance(delta: float) -> Array:
	var ev: Array = []
	if finished or body.is_empty():
		return ev
	sub += delta / maxf(0.01, step_time)
	var guard := 0
	while sub >= 1.0 and not finished and guard < 32:
		guard += 1
		sub -= 1.0
		_step(ev)
	# Every cell at its layer count for done_hold finishes the stage.
	if all_covered():
		hold += delta
		if hold >= done_hold:
			finished = true
			ev.append({"e": "done", "at": head_at()})
	else:
		hold = 0.0
	return ev


func _step(ev: Array) -> void:
	dir = want_dir
	var head: Vector2i = body[0] + dir
	if not in_bounds(head):
		_tangle(ev, at_of(body[0]))
		return
	# Classic Snake: the last segment moves out of the way this step, so its cell is safe. Everything
	# else in the tail is a tangle.
	for i in range(1, body.size() - 1):
		if body[i] == head:
			_tangle(ev, at_of(head))
			return
	body.push_front(head)
	var grew := false
	var idx := cell_index(head)
	# Gauze in hand: the tail grows by one.
	if pickups.has(idx):
		pickups.erase(idx)
		eaten += 1
		grew = true
		ev.append({"e": "eat", "at": at_of(head)})
		_top_up_pickups()
	# A layer down: the tail loses one the same instant. Empty-handed, nothing happens at all.
	var spend := false
	if wound_at.has(idx):
		var w: int = int(wound_at[idx])
		if not satisfied(w) and carry() >= 1:
			layers[w] = mini(layers[w] + 1, need(w))
			laid += 1
			spend = true
			ev.append({"e": "lay", "at": at_of(head), "w": w, "full": satisfied(w)})
	# Length always equals what is carried: +1 for a pickup, -1 for a layer, otherwise it just moves.
	var want_len: int = body.size()
	if not grew:
		want_len -= 1
	if spend:
		want_len -= 1
	while body.size() > maxi(1, want_len):
		body.pop_back()


## A wall or your own tail. It costs vitals and momentum, never progress: the roll comes back on the
## left edge still holding exactly what it was holding.
func _tangle(ev: Array, at: Vector2) -> void:
	tangles += 1
	var held := carry()
	ev.append({"e": "tangle", "at": at, "carry": held})
	_place_on_left(held)


# ---------------------------------------------------------------------------- results

## One character per wound cell for the dressing the patient walks out with: `g` a covered dry cell,
## `G` a covered bleeder (two layers on), `s` a cell still short a layer.
func marks() -> String:
	var s := ""
	for w in wound.size():
		if not satisfied(w):
			s += "s"
		elif bleeding[w]:
			s += "G"
		else:
			s += "g"
	return s


# ---------------------------------------------------------------------------- the bot

## Can the roll be in `c` next step without dying there?
func _passable(c: Vector2i) -> bool:
	if not in_bounds(c):
		return false
	for i in range(1, body.size() - 1):
		if body[i] == c:
			return false
	return true


## Which way the bot should turn: towards gauze when its hands are empty, towards the nearest cell
## that still wants a layer when they are not. A breadth-first walk over the free cells, so it goes
## round its own tail instead of into it.
func route() -> Vector2i:
	if body.is_empty():
		return dir
	var targets := {}
	if carry() <= 0:
		for idx in pickups:
			targets[idx] = true
	else:
		for w in wound.size():
			if not satisfied(w):
				targets[wound[w]] = true
		# Holding gauze with nothing left to lay: go and get more anyway, so it never stalls.
		if targets.is_empty():
			for idx in pickups:
				targets[idx] = true
	if targets.is_empty():
		return dir
	var head: Vector2i = body[0]
	var from := {}
	var queue: Array[Vector2i] = []
	for d in DIRS:
		if d == -dir:
			continue
		var c: Vector2i = head + d
		if not _passable(c):
			continue
		from[cell_index(c)] = d
		queue.append(c)
		if targets.has(cell_index(c)):
			return d
	var qi := 0
	while qi < queue.size():
		var cur: Vector2i = queue[qi]
		qi += 1
		var first: Vector2i = from[cell_index(cur)]
		for d in DIRS:
			var c: Vector2i = cur + d
			if not _passable(c) or from.has(cell_index(c)):
				continue
			from[cell_index(c)] = first
			if targets.has(cell_index(c)):
				return first
			queue.append(c)
	# Boxed in: any turn that is not instant death beats driving into the wall.
	for d in DIRS:
		if d != -dir and _passable(head + d):
			return d
	return dir


# ---------------------------------------------------------------------------- net

## The replicated half. NOTHING THAT CREEPS IS SNAPPED (`sub` counts up every frame).
func pack() -> Dictionary:
	var b := PackedInt32Array()
	for c in body:
		b.append(cell_index(c))
	return {"b": b, "d": Vector2i(dir), "wd": Vector2i(want_dir), "sb": sub,
		"ly": PackedInt32Array(layers), "pk": PackedInt32Array(pickups), "tg": tangles,
		"ld": laid, "et": eaten, "fi": finished, "hd": hold}


func unpack(s: Dictionary) -> void:
	if s.is_empty():
		return
	var b = s.get("b", null)
	if b is PackedInt32Array:
		body.clear()
		for i in b:
			body.append(cell_of(int(i)))
	dir = s.get("d", dir)
	want_dir = s.get("wd", want_dir)
	sub = float(s.get("sb", sub))
	var ly = s.get("ly", null)
	if ly is PackedInt32Array:
		layers.clear()
		for v in ly:
			layers.append(int(v))
	var pk = s.get("pk", null)
	if pk is PackedInt32Array:
		pickups.clear()
		for v in pk:
			pickups.append(int(v))
	tangles = int(s.get("tg", tangles))
	laid = int(s.get("ld", laid))
	eaten = int(s.get("et", eaten))
	finished = bool(s.get("fi", finished))
	hold = float(s.get("hd", hold))


# ---------------------------------------------------------------------------- the page

## The board on bare skin, the wound, the bandage, the gauze and the roll. `g` is the owning game: its
## cv() puts reference px on the page and its `ink` does the line work.
func paint(c: CanvasItem, g) -> void:
	var ink = g.ink
	if ink == null:
		return
	var w := float(cols) * cell_px
	var h := float(rows) * cell_px
	var board := Rect2(g.cv(origin), Vector2(g.cl(w), g.cl(h)))
	# Bare skin under the grid, and the grid itself, faint.
	c.draw_rect(board, Color(ink.skin_human, 0.55))
	var grid_col := Color(ink.ink, 0.13)
	for x in cols + 1:
		var px := origin.x + float(x) * cell_px
		c.draw_line(g.cv(Vector2(px, origin.y)), g.cv(Vector2(px, origin.y + h)), grid_col, 1.0)
	for y in rows + 1:
		var py := origin.y + float(y) * cell_px
		c.draw_line(g.cv(Vector2(origin.x, py)), g.cv(Vector2(origin.x + w, py)), grid_col, 1.0)
	_paint_wound(c, g, ink)
	_paint_pickups(c, g, ink)
	_paint_roll(c, g, ink)
	ink.line(c, PackedVector2Array([board.position, Vector2(board.end.x, board.position.y), board.end,
		Vector2(board.position.x, board.end.y)]), ink.ink, 2.6, 5100, true)


## Every wound cell: raw flesh, a x2 tag on the ones that bleed, and a pale bandage patch per layer
## already laid, so "how much more does this one want" is readable at a glance.
func _paint_wound(c: CanvasItem, g, ink) -> void:
	for w in wound.size():
		var cl: Vector2i = cell_of(wound[w])
		var ctr := at_of(cl)
		var r := Rect2(g.cv(ctr - Vector2(cell_px, cell_px) * 0.5), Vector2(g.cl(cell_px), g.cl(cell_px)))
		var inner := r.grow(-g.cl(3.0))
		c.draw_rect(inner, Color("b8443a", 0.85))
		if bleeding[w]:
			c.draw_rect(inner, Color("7c1f24", 0.45))
		ink.halftone_poly(c, PackedVector2Array([inner.position, Vector2(inner.end.x, inner.position.y),
			inner.end, Vector2(inner.position.x, inner.end.y)]), 0.35, Color("5a1414"))
		# The bandage: one pale band per layer, laid across the cell.
		var lay: int = mini(layers[w], need(w))
		for i in lay:
			var t := inner.grow(-g.cl(2.0))
			var band_h := t.size.y / float(need(w))
			var strip := Rect2(t.position + Vector2(0.0, band_h * float(i)), Vector2(t.size.x, band_h))
			c.draw_rect(strip, Color(ink.paper, 0.92))
			ink.line(c, PackedVector2Array([strip.position, Vector2(strip.end.x, strip.position.y),
				strip.end, Vector2(strip.position.x, strip.end.y)]), Color(ink.ink, 0.55), 1.6, 5200 + w * 4 + i, true)
		if satisfied(w):
			continue
		# The tag COUNTS DOWN as layers go on, so it always says what this cell still wants rather
		# than what it wanted to start with -- and it never ends up printed over its own bandage.
		if bleeding[w]:
			var left: int = need(w) - mini(layers[w], need(w))
			var ty: float = ctr.y + 5.0 - cell_px * 0.25 * float(lay)
			ink.text(c, g.cv(Vector2(ctr.x, ty)), "x%d" % left, 15.0, Color(ink.paper, 0.95), 1)


## Gauze waiting to be picked up: a little rolled bandage.
func _paint_pickups(c: CanvasItem, g, ink) -> void:
	for idx in pickups:
		var ctr := at_of(cell_of(idx))
		var rr := cell_px * 0.3
		ink.circle(c, g.cv(ctr), g.cl(rr), ink.ink, 2.2, 5300 + idx, Color(ink.paper, 0.95))
		ink.circle(c, g.cv(ctr), g.cl(rr * 0.45), Color(ink.ink, 0.5), 1.6, 5400 + idx)
		ink.seg(c, g.cv(ctr + Vector2(-rr, 0.0)), g.cv(ctr + Vector2(rr, 0.0)), Color(ink.ink, 0.35), 1.4, 5500 + idx)


## The roll: the tail is the gauze in hand, so it is drawn as bandage segments, and the head carries a
## small ink triangle saying which way it is going.
func _paint_roll(c: CanvasItem, g, ink) -> void:
	if body.is_empty():
		return
	for i in range(body.size() - 1, 0, -1):
		var ctr := at_of(body[i])
		var r := Rect2(g.cv(ctr - Vector2(cell_px, cell_px) * 0.38), Vector2(g.cl(cell_px * 0.76), g.cl(cell_px * 0.76)))
		c.draw_rect(r, Color(ink.paper, 0.95))
		ink.line(c, PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end,
			Vector2(r.position.x, r.end.y)]), Color(ink.ink, 0.7), 2.0, 5600 + i, true)
	var at := head_at()
	var hr := Rect2(g.cv(at - Vector2(cell_px, cell_px) * 0.42), Vector2(g.cl(cell_px * 0.84), g.cl(cell_px * 0.84)))
	c.draw_rect(hr, Color(ink.paper, 1.0))
	ink.line(c, PackedVector2Array([hr.position, Vector2(hr.end.x, hr.position.y), hr.end,
		Vector2(hr.position.x, hr.end.y)]), ink.ink, 3.0, 5700, true)
	# The heading arrow: the head is otherwise a plain square.
	var d := Vector2(dir)
	var side := d.orthogonal()
	var tip := at + d * cell_px * 0.26
	c.draw_colored_polygon(PackedVector2Array([g.cv(tip),
		g.cv(at - d * cell_px * 0.08 + side * cell_px * 0.16),
		g.cv(at - d * cell_px * 0.08 - side * cell_px * 0.16)]), ink.ink)
