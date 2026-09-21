extends RefCounted
## ARCADE SURGERY (docs/ARCADE_SURGERY.md) 5.7 -- WRAP!: the board and the rules, in one file, so
## the two dressings play exactly the same game.
##
## Rhyme: Snake. The bandage roll is the snake and the trail behind it is bandage. You may cross
## your own work ONLY where the wound is -- that is how a dressing gets its layers -- and crossing
## it anywhere else, or running into the edge of the panel, tangles the roll.
##
## The two variants differ only in what the game hands build():
##   pack   a 10-14 cell blob over the packed bullet hole, one layer a cell, 60 cells of roll
##   stump  a 16-20 cell ring round the cut end, two layers a cell, 90 cells of roll
## and in how many of those cells are BLEEDING, which is the carry-forward from the step before.
## A bleeding cell wants one layer more than a dry one, and left sitting under a single layer it
## soaks through and you are back where you started. Bad earlier work is a harder routing puzzle.
##
## It owns no exports and it knows nothing about the framework: the game that owns it sets the
## tuning, calls advance(), and pays for the events it hands back. THIS FILE NEVER BOTCHES.
##
## Not registered anywhere. It is a plain helper the two WRAP games own between them.

const StyleScript := preload("res://scripts/surgery/panel/panel_style.gd")

const PHI := 0.6180339887498949

## Right, down, left, up. The grid's +y is DOWN, like the panel's.
const DIRS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1)]

## How much of the trail is drawn and replicated. The rules run off `laid`, which is sent in full,
## so forgetting the oldest bandage only means it stops being painted.
const TRAIL_DRAWN := 240

# ---- the board ---------------------------------------------------------------------------------
var cols := 16
var rows := 10
var view := Vector2(120.0, 80.0)          ## diagram millimetres the grid covers
var kind := "pack"

# ---- tuning, set by the game before build() ----------------------------------------------------
var base_need := 1                        ## layers a dry wound cell wants
var max_layers := 3
var roll_max := 60                        ## cells of bandage on the roll
var speed_cells := 5.0                    ## cells a second before difficulty
var soak_time := 3.0                      ## a bleeding cell under ONE layer soaks after this long
var respawn_time := 0.6
var anchor := Vector2i(8, 5)              ## where a pack blob grows from

# ---- replicated state --------------------------------------------------------------------------
var wound: Array[int] = []                ## cell indices, in the order they were laid out
var wound_at := {}                        ## cell index -> position in `wound`
var bleeding: Array[bool] = []            ## per wound position
var layers: Array[int] = []               ## per wound position, 0..max_layers
var soak: Array[float] = []               ## per wound position, seconds left or -1
var soaked: Array[int] = []               ## per wound position, times it has soaked through
var laid: Array[int] = []                 ## per GRID cell, how many times the trail has been through
var trail: Array[int] = []                ## grid cells in the order the bandage went down

var cell := Vector2i(0, 0)
var dir := Vector2i(1, 0)
var want_dir := Vector2i(1, 0)
var sub := 0.0                            ## 0..1 of the way into the next cell -- THIS CREEPS
var roll_left := 60
var respawn := 0.0                        ## seconds until the roll is back on the board
var finished := false

# ---- the tally the marks and the quality come off ----------------------------------------------
var turns := 0
var overlaps := 0                         ## bandage put somewhere that was already full
var tangles := 0
var runouts := 0
var soaks := 0
var cut := 0                              ## cells of tangled bandage cut off and thrown away

var speed := 5.0
var _rng := RandomNumberGenerator.new()


# ---------------------------------------------------------------------------- the layout

## Lay the board out. Everything here comes off the seed, so every machine builds the same one.
func build(seed_v: int, difficulty: float, variant: String, bleed_frac: float, view_mm: Vector2) -> void:
	kind = "stump" if variant == "stump" else "pack"
	view = view_mm
	speed = speed_cells * sqrt(maxf(0.5, difficulty))
	_rng.seed = seed_v ^ 0x7ab1
	laid.resize(cols * rows)
	laid.fill(0)
	wound.clear()
	wound_at.clear()
	if kind == "stump":
		wound = _ring()
	else:
		wound = _blob()
	for n in wound.size():
		wound_at[wound[n]] = n
	var count: int = wound.size()
	layers.resize(count)
	layers.fill(0)
	soak.resize(count)
	soak.fill(-1.0)
	soaked.resize(count)
	soaked.fill(0)
	bleeding.resize(count)
	bleeding.fill(false)
	# CARRY-FORWARD: how much of the wound is still bleeding through the last step's work.
	var wet: int = clampi(int(round(float(count) * clampf(bleed_frac, 0.0, 1.0))), 0, count - 1)
	var order: Array[int] = []
	for n in count:
		order.append(n)
	for n in range(order.size() - 1, 0, -1):
		var j: int = _rng.randi_range(0, n)
		var tmp: int = order[n]
		order[n] = order[j]
		order[j] = tmp
	for n in wet:
		bleeding[order[n]] = true
	roll_left = roll_max
	_enter_from_left()


## A 10-14 cell blob, grown out from the wound so it is a shape and not a rectangle.
func _blob() -> Array[int]:
	var want: int = _rng.randi_range(10, 14)
	var start := Vector2i(clampi(anchor.x, 2, cols - 3), clampi(anchor.y, 2, rows - 3))
	var out: Array[int] = [cell_index(start)]
	var have := {out[0]: true}
	var edge: Array[Vector2i] = [start]
	var guard := 0
	while out.size() < want and guard < 400:
		guard += 1
		var from: Vector2i = edge[_rng.randi_range(0, edge.size() - 1)]
		var d: Vector2i = DIRS[_rng.randi_range(0, 3)]
		var c: Vector2i = from + d
		# One clear cell of margin all round, so the roll can always get at the far side.
		if c.x < 1 or c.y < 1 or c.x > cols - 2 or c.y > rows - 2:
			continue
		var i: int = cell_index(c)
		if have.has(i):
			continue
		have[i] = true
		out.append(i)
		edge.append(c)
	return out


## A 16-20 cell ring round the stump. Sampled off an ellipse and then filled at every diagonal
## step, because the roll walks the ring cell by cell and a corner it cannot turn is a dead end.
func _ring() -> Array[int]:
	var ratio: float = _rng.randf_range(0.60, 0.72)
	var cx: float = float(cols) * 0.5 + _rng.randf_range(-0.3, 0.3)
	var cy: float = float(rows) * 0.5 + _rng.randf_range(-0.2, 0.2)
	var best: Array[int] = []
	for k in 30:
		var rx: float = 3.0 + 0.1 * float(k)
		var ry: float = rx * ratio
		if rx > float(cols) * 0.5 - 1.2 or ry > float(rows) * 0.5 - 1.2:
			break
		var r: Array[int] = _ellipse_ring(cx, cy, rx, ry)
		if r.size() >= 16 and r.size() <= 20:
			return r
		if best.is_empty() or absi(r.size() - 18) < absi(best.size() - 18):
			best = r
	return best


func _ellipse_ring(cx: float, cy: float, rx: float, ry: float) -> Array[int]:
	var out: Array[int] = []
	var seen := {}
	var last := Vector2i(-99, -99)
	var steps := 180
	for k in steps + 1:
		var a: float = TAU * float(k) / float(steps)
		var c := Vector2i(int(floor(cx + rx * cos(a))), int(floor(cy + ry * sin(a))))
		c.x = clampi(c.x, 1, cols - 2)
		c.y = clampi(c.y, 1, rows - 2)
		if c == last:
			continue
		if last.x > -50 and c.x != last.x and c.y != last.y:
			# The walk cut a corner. Put the corner cell in so the ring stays walkable.
			var mi: int = cell_index(Vector2i(c.x, last.y))
			if not seen.has(mi):
				seen[mi] = true
				out.append(mi)
		last = c
		var i: int = cell_index(c)
		if not seen.has(i):
			seen[i] = true
			out.append(i)
	return out


## The roll comes in from the left edge, on the row of the nearest wound cell.
func _enter_from_left() -> void:
	var row: int = rows / 2
	var bestx: int = cols
	for i in wound:
		var c: Vector2i = cell_of(i)
		if c.x < bestx:
			bestx = c.x
			row = c.y
	cell = Vector2i(0, clampi(row, 0, rows - 1))
	dir = Vector2i(1, 0)
	want_dir = dir
	sub = 0.0
	trail.clear()
	trail.append(cell_index(cell))
	laid[cell_index(cell)] = 1
	finished = false


# ---------------------------------------------------------------------------- the grid

func cell_index(c: Vector2i) -> int:
	return c.y * cols + c.x


func cell_of(i: int) -> Vector2i:
	return Vector2i(i % cols, i / cols)


func in_bounds(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < cols and c.y < rows


func cell_size() -> Vector2:
	return Vector2(view.x / float(cols), view.y / float(rows))


## The centre of a grid cell in diagram millimetres.
func mm_of(i: int) -> Vector2:
	var c := cell_of(i)
	var s := cell_size()
	return Vector2((float(c.x) + 0.5) * s.x - view.x * 0.5, (float(c.y) + 0.5) * s.y - view.y * 0.5)


## Where the roll actually is, between cells.
func roll_mm() -> Vector2:
	var here := mm_of(cell_index(cell))
	var nxt := cell + dir
	if respawn > 0.0 or not in_bounds(nxt):
		return here
	return here.lerp(mm_of(cell_index(nxt)), clampf(sub, 0.0, 1.0))


# ---------------------------------------------------------------------------- the rules

## Layers this wound cell wants. A bleeding one wants one more, because the first is going to be
## red before you are finished with it.
func need(w: int) -> int:
	return mini(max_layers, base_need + (1 if bleeding[w] else 0))


func satisfied(w: int) -> bool:
	return layers[w] >= need(w)


func left() -> int:
	var n := 0
	for w in wound.size():
		if not satisfied(w):
			n += 1
	return n


func total_need() -> int:
	var n := 0
	for w in wound.size():
		n += need(w)
	return n


func frac() -> float:
	var have := 0.0
	for w in wound.size():
		have += float(mini(layers[w], need(w)))
	return clampf(have / maxf(1.0, float(total_need())), 0.0, 1.0)


## WASD / arrows. No reversing: the roll cannot run back up its own bandage.
func steer(d: Vector2i) -> void:
	if d == Vector2i.ZERO or d == -dir:
		return
	want_dir = d


## One frame of the roll running. Returns the events the OWNING GAME has to pay for:
##   {"e": "tangle", "why": edge|trail}  {"e": "runout"}  {"e": "soak", "w": n}
##   {"e": "layer", "w": n, "n": layers} {"e": "waste", "w": n}  {"e": "cover", "w": n}
##   {"e": "respawn"}  {"e": "done"}
func advance(delta: float) -> Array:
	var ev: Array = []
	if finished:
		return ev
	_tick_soaks(delta, ev)
	if respawn > 0.0:
		respawn = maxf(0.0, respawn - delta)
		if respawn <= 0.0:
			_respawn(ev)
		return ev
	sub += speed * delta
	var guard := 0
	while sub >= 1.0 and not finished and respawn <= 0.0 and guard < 8:
		sub -= 1.0
		guard += 1
		_step(ev)
	if finished or respawn > 0.0:
		sub = 0.0
	return ev


## A bleeding cell under a single layer goes red from underneath and counts as bare again.
func _tick_soaks(delta: float, ev: Array) -> void:
	for w in wound.size():
		if soak[w] <= 0.0:
			continue
		soak[w] -= delta
		if soak[w] > 0.0:
			continue
		soak[w] = -1.0
		layers[w] = 0
		soaked[w] += 1
		soaks += 1
		ev.append({"e": "soak", "w": w})


func _step(ev: Array) -> void:
	# The steer lands on the cell boundary, never halfway across one.
	if want_dir != dir and want_dir != -dir:
		dir = want_dir
		turns += 1
	var nxt: Vector2i = cell + dir
	if not in_bounds(nxt):
		_tangle(ev, "edge")
		return
	var i: int = cell_index(nxt)
	var w: int = int(wound_at.get(i, -1))
	if laid[i] > 0 and w < 0:
		_tangle(ev, "trail")
		return
	roll_left -= 1
	if roll_left <= 0:
		roll_left = roll_max
		runouts += 1
		ev.append({"e": "runout"})
	cell = nxt
	laid[i] = laid[i] + 1
	trail.append(i)
	if w >= 0:
		if layers[w] < max_layers:
			layers[w] = layers[w] + 1
			ev.append({"e": "layer", "w": w, "n": layers[w]})
		else:
			overlaps += 1
			ev.append({"e": "waste", "w": w})
		soak[w] = soak_time if (bleeding[w] and layers[w] == 1) else -1.0
		if satisfied(w):
			ev.append({"e": "cover", "w": w})
	if left() == 0:
		finished = true
		ev.append({"e": "done"})


func _tangle(ev: Array, why: String) -> void:
	tangles += 1
	respawn = respawn_time
	sub = 0.0
	ev.append({"e": "tangle", "why": why})


## Back on the board next to whatever is still bare, pointed at it.
##
## The tangle itself is CUT OUT first. Without that the board silently fills up -- every cell that
## is not wound may only be crossed once, so a bad run eventually has nowhere legal to go, tangles
## on the spot, respawns, and tangles again for ever. Cutting the wandering back to the last turn
## that was actually on the wound frees exactly the bandage that was not doing anything, undoes no
## layers, and is what you would do with a knotted roll anyway.
func _respawn(ev: Array) -> void:
	cut += _cut_tangle()
	var target := -1
	var best := 1e9
	for w in wound.size():
		if satisfied(w):
			continue
		var d: float = Vector2(cell_of(wound[w]) - cell).length()
		if d < best:
			best = d
			target = wound[w]
	if target < 0:
		finished = true
		ev.append({"e": "done"})
		return
	var tc: Vector2i = cell_of(target)
	for d: Vector2i in DIRS:
		var c: Vector2i = tc - d
		if not in_bounds(c):
			continue
		var i: int = cell_index(c)
		if laid[i] > 0 and not wound_at.has(i):
			continue
		cell = c
		dir = d
		want_dir = d
		sub = 0.0
		ev.append({"e": "respawn"})
		return
	cell = tc
	dir = Vector2i(1, 0)
	want_dir = dir
	sub = 0.0
	ev.append({"e": "respawn"})


## Pull the loose end back to the last turn that went over the wound. If the tangle happened right
## on the wound there is nothing loose at that end, so the OLD end comes away instead -- either way
## the board gets some room back and the run can never dead-end.
func _cut_tangle() -> int:
	var n := 0
	while trail.size() > 1:
		var i: int = trail[trail.size() - 1]
		if wound_at.has(i):
			break
		trail.remove_at(trail.size() - 1)
		laid[i] = maxi(0, laid[i] - 1)
		n += 1
	if n > 0:
		return n
	var k := 0
	while k < trail.size() and n < 8:
		if wound_at.has(trail[k]):
			k += 1
			continue
		laid[trail[k]] = maxi(0, laid[trail[k]] - 1)
		trail.remove_at(k)
		n += 1
	return n


## A jerk pulls the last of the bandage back off the wound.
func jolt(n: int) -> int:
	var lost := 0
	for k in n:
		if trail.size() <= 1:
			break
		var i: int = trail[trail.size() - 1]
		trail.remove_at(trail.size() - 1)
		laid[i] = maxi(0, laid[i] - 1)
		var w: int = int(wound_at.get(i, -1))
		if w >= 0 and layers[w] > 0:
			layers[w] = layers[w] - 1
			soak[w] = soak_time if (bleeding[w] and layers[w] == 1) else -1.0
		lost += 1
	if not trail.is_empty():
		cell = cell_of(trail[trail.size() - 1])
	sub = 0.0
	return lost


# ---------------------------------------------------------------------------- how it looks after

## 0..1. How tidy the path was: bandage spent against bandage needed, how much of it was corners,
## and what went wrong along the way.
func neatness() -> float:
	var ideal: float = maxf(4.0, float(total_need()) * 1.55)
	var spent: float = maxf(1.0, float(trail.size() + cut))
	var thrift: float = clampf(ideal / spent, 0.0, 1.0)
	var corner: float = clampf(1.0 - maxf(0.0, float(turns) / spent - 0.36) / 0.44, 0.0, 1.0)
	var clean: float = clampf(1.0 - 0.11 * float(tangles) - 0.09 * float(soaks) - 0.07 * float(runouts), 0.0, 1.0)
	return clampf(0.42 * thrift + 0.18 * corner + 0.40 * clean, 0.0, 1.0)


## One character a wound cell, in layout order, for the dressing on the body: `g` neat, `l` baggy,
## `t` soaked through. A cell that actually soaked always says so; the rest of the untidiness is
## spread over the dressing by the golden ratio, so a messy path gives a messy-LOOKING dressing
## rather than one grubby patch.
func marks() -> String:
	var n: int = wound.size()
	if n <= 0:
		return ""
	var out := PackedStringArray()
	out.resize(n)
	var messy := 0
	for w in n:
		if soaked[w] > 0:
			out[w] = "t"
			messy += 1
		else:
			out[w] = "g"
	var want: int = int(round((1.0 - neatness()) * float(n)))
	var k := 0
	while messy < want and k < n * 4:
		k += 1
		var idx: int = int(fposmod(float(k) * PHI, 1.0) * float(n)) % n
		if out[idx] == "g":
			out[idx] = "l"
			messy += 1
	return String("").join(out)


func quality() -> float:
	var q: float = 1.0 - 0.09 * float(tangles) - 0.08 * float(soaks) - 0.07 * float(runouts)
	return clampf(q * lerpf(0.72, 1.0, neatness()), 0.05, 1.0)


# ---------------------------------------------------------------------------- the bot's routing

func _passable(c: Vector2i) -> bool:
	if not in_bounds(c):
		return false
	var i: int = cell_index(c)
	return wound_at.has(i) or laid[i] == 0


## The direction the roll should take next to get at the nearest bare wound cell without crossing
## its own bandage. Breadth-first over 160 cells, which is nothing, and it is the same answer on
## every machine. Shared by both games' bots.
func route(from: Vector2i, cur: Vector2i) -> Vector2i:
	var targets := {}
	for w in wound.size():
		if not satisfied(w):
			targets[wound[w]] = true
	if targets.is_empty():
		return cur
	var first := {}
	var q: Array[Vector2i] = []
	for d: Vector2i in DIRS:
		if d == -cur:
			continue
		var n: Vector2i = from + d
		if not _passable(n):
			continue
		var i: int = cell_index(n)
		if first.has(i):
			continue
		first[i] = d
		if targets.has(i):
			return d
		q.append(n)
	var head := 0
	while head < q.size():
		var c: Vector2i = q[head]
		head += 1
		var fd: Vector2i = first[cell_index(c)]
		for d: Vector2i in DIRS:
			var n2: Vector2i = c + d
			if not _passable(n2):
				continue
			var i2: int = cell_index(n2)
			if first.has(i2):
				continue
			first[i2] = fd
			if targets.has(i2):
				return fd
			q.append(n2)
	# Boxed in. Anything legal beats driving into the edge.
	for d: Vector2i in DIRS:
		if d != -cur and _passable(from + d):
			return d
	return cur


# ---------------------------------------------------------------------------- net

## Small enough to go out 20 times a second. The board itself is seeded, so only what moves goes.
## `sub`, `soak` and `respawn` CREEP: they go raw, never snapped, or they never move at all on a
## machine that round-trips its own state (see ArcadeGame.net_state).
##
## `laid` goes out in full rather than being counted back off the trail, because the trail is
## capped for drawing and rebuilding the rules from a capped trail would quietly hand the operator
## -- who round-trips this dictionary through itself every frame -- a board it is allowed to cross
## twice.
func pack() -> Dictionary:
	var t := PackedByteArray()
	var from: int = maxi(0, trail.size() - TRAIL_DRAWN)
	for n in range(from, trail.size()):
		t.append(trail[n])
	var lc := PackedByteArray()
	for i in laid.size():
		lc.append(mini(255, laid[i]))
	var lay := PackedByteArray()
	for w in layers.size():
		lay.append(layers[w])
	var sk := PackedFloat32Array()
	for w in soak.size():
		sk.append(soak[w])
	return {
		"t": t, "L": lay, "k": sk, "lc": lc,
		"c": cell_index(cell), "d": DIRS.find(dir), "s": sub, "r": roll_left,
		"rs": respawn, "tg": tangles, "sk": soaks, "ro": runouts, "ct": cut,
		"tu": turns, "ov": overlaps, "f": finished,
	}


func unpack(s: Dictionary) -> void:
	if s.is_empty():
		return
	var t: PackedByteArray = s.get("t", PackedByteArray())
	trail.clear()
	for n in t.size():
		trail.append(int(t[n]))
	var lc: PackedByteArray = s.get("lc", PackedByteArray())
	for i in mini(lc.size(), laid.size()):
		laid[i] = int(lc[i])
	var lay: PackedByteArray = s.get("L", PackedByteArray())
	for w in mini(lay.size(), layers.size()):
		layers[w] = int(lay[w])
	var sk: PackedFloat32Array = s.get("k", PackedFloat32Array())
	for w in mini(sk.size(), soak.size()):
		soak[w] = float(sk[w])
	cell = cell_of(int(s.get("c", cell_index(cell))))
	var di: int = int(s.get("d", DIRS.find(dir)))
	if di >= 0 and di < DIRS.size():
		dir = DIRS[di]
	sub = float(s.get("s", sub))
	roll_left = int(s.get("r", roll_left))
	respawn = float(s.get("rs", respawn))
	tangles = int(s.get("tg", tangles))
	soaks = int(s.get("sk", soaks))
	runouts = int(s.get("ro", runouts))
	cut = int(s.get("ct", cut))
	turns = int(s.get("tu", turns))
	overlaps = int(s.get("ov", overlaps))
	finished = bool(s.get("f", finished))


# ---------------------------------------------------------------------------- the diagram

## The whole board: grid, wound, bandage, roll. `g` is the ArcadeGame that owns it, for px() and
## the palette; nothing here knows what game it is.
func paint(c: CanvasItem, g) -> void:
	var st: StyleScript = g.style()
	_paint_grid(c, g, st)
	_paint_wound(c, g, st)
	_paint_trail(c, g, st)
	_paint_roll(c, g, st)


func _paint_grid(c: CanvasItem, g, st: StyleScript) -> void:
	var s := cell_size()
	for x in cols + 1:
		var mx: float = float(x) * s.x - view.x * 0.5
		c.draw_line(g.px(Vector2(mx, -view.y * 0.5)), g.px(Vector2(mx, view.y * 0.5)),
			Color(st.line_dim, 0.10), st.hair)
	for y in rows + 1:
		var my: float = float(y) * s.y - view.y * 0.5
		c.draw_line(g.px(Vector2(-view.x * 0.5, my)), g.px(Vector2(view.x * 0.5, my)),
			Color(st.line_dim, 0.10), st.hair)


## Wound cells. NOTHING here is told apart by colour alone: a bare cell is an open dashed box, a
## bleeding one carries a spurt cross, and every layer on top of it is one more inset box, so you
## can count the layers by eye.
func _paint_wound(c: CanvasItem, g, st: StyleScript) -> void:
	var s := cell_size()
	for w in wound.size():
		var at: Vector2 = mm_of(wound[w])
		var half: Vector2 = s * 0.5 - Vector2(0.7, 0.7)
		var done: bool = satisfied(w)
		var wet: bool = bleeding[w]
		var body: Color = st.blood_dark if not wet else Color(st.danger, 0.30)
		_box_fill(c, g, at, half, body)
		var edge: Color = st.good if done else (st.danger if wet else st.line_dim)
		if done:
			_box_line(c, g, at, half, edge, st.thin)
		else:
			_box_dashed(c, g, at, half, st, edge)
		# A bleeding cell wears a cross whatever colour the panel is set to.
		if wet and layers[w] < need(w):
			var r: float = minf(half.x, half.y) * 0.45
			c.draw_line(g.px(at + Vector2(-r, -r)), g.px(at + Vector2(r, r)), st.danger, st.thin)
			c.draw_line(g.px(at + Vector2(-r, r)), g.px(at + Vector2(r, -r)), st.danger, st.thin)
		for n in mini(layers[w], max_layers):
			var k: float = 1.0 - 0.22 * float(n + 1)
			_box_line(c, g, at, half * k, Color(st.thread, 0.85), st.hair)
		# The finished cell gets a hatch as well as the green, so it reads at a glance.
		if done:
			var hh: Vector2 = half * 0.8
			for n in 3:
				var t: float = lerpf(-0.6, 0.6, float(n) / 2.0)
				c.draw_line(g.px(at + Vector2(-hh.x, hh.y * t)), g.px(at + Vector2(hh.x * t, -hh.y)),
					Color(st.good, 0.45), st.hair)


## The bandage itself: a ribbon down the middle of every cell it went through, with a weave tick a
## cell so it reads as gauze and not as a wire. A tangle breaks the ribbon, which is the point.
func _paint_trail(c: CanvasItem, g, st: StyleScript) -> void:
	if trail.size() < 1:
		return
	var run := PackedVector2Array()
	var prev := Vector2i(-99, -99)
	for n in trail.size():
		var cc: Vector2i = cell_of(trail[n])
		if prev.x > -50 and (absi(cc.x - prev.x) + absi(cc.y - prev.y)) != 1:
			_ribbon(c, g, st, run)
			run = PackedVector2Array()
		run.append(g.px(mm_of(trail[n])))
		prev = cc
	_ribbon(c, g, st, run)


func _ribbon(c: CanvasItem, g, st: StyleScript, pts: PackedVector2Array) -> void:
	if pts.size() < 2:
		if pts.size() == 1:
			c.draw_circle(pts[0], g.px_len(2.2), Color(st.thread, 0.6))
		return
	var w: float = g.px_len(minf(cell_size().x, cell_size().y) * 0.50)
	st.glow_poly(c, pts, st.thread, w * 0.5)
	c.draw_polyline(pts, Color(st.thread, 0.55), w)
	c.draw_polyline(pts, Color(st.line, 0.85), st.thin)
	for n in range(0, pts.size() - 1):
		var a: Vector2 = pts[n]
		var b: Vector2 = pts[n + 1]
		var mid: Vector2 = (a + b) * 0.5
		var d: Vector2 = (b - a).normalized()
		var p := Vector2(-d.y, d.x) * w * 0.42
		c.draw_line(mid - p, mid + p, Color(st.line, 0.35), st.hair)


func _paint_roll(c: CanvasItem, g, st: StyleScript) -> void:
	var at: Vector2 = g.px(roll_mm())
	var r: float = g.px_len(minf(cell_size().x, cell_size().y) * 0.38)
	if respawn > 0.0:
		# Cut and being started again: a ring closing in on where it comes back.
		var k: float = clampf(respawn / maxf(0.05, respawn_time), 0.0, 1.0)
		c.draw_arc(at, r + g.px_len(9.0 * k), 0.0, TAU, 22, Color(st.danger, 0.6), st.thin)
		return
	st.glow_circle(c, at, r, st.steel, st.thin)
	c.draw_circle(at, r, Color(st.steel, 0.85))
	c.draw_circle(at, r * 0.42, st.bg)
	c.draw_arc(at, r * 0.42, 0.0, TAU, 16, Color(st.line, 0.8), st.hair)
	# A nose pointing the way it is going, so its heading is never a guess.
	var d := Vector2(float(dir.x), float(dir.y))
	c.draw_line(at, at + d * r * 1.8, st.line, st.thin)


func _box_fill(c: CanvasItem, g, at: Vector2, half: Vector2, col: Color) -> void:
	var a: Vector2 = g.px(at - half)
	var b: Vector2 = g.px(at + half)
	c.draw_rect(Rect2(a, b - a), col)


func _box_line(c: CanvasItem, g, at: Vector2, half: Vector2, col: Color, width: float) -> void:
	var a: Vector2 = g.px(at - half)
	var b: Vector2 = g.px(at + half)
	c.draw_rect(Rect2(a, b - a), col, false, width)


func _box_dashed(c: CanvasItem, g, at: Vector2, half: Vector2, st: StyleScript, col: Color) -> void:
	var a: Vector2 = g.px(at - half)
	var b: Vector2 = g.px(at + half)
	st.dashed(c, a, Vector2(b.x, a.y), col, st.thin, 7.0, 5.0)
	st.dashed(c, Vector2(b.x, a.y), b, col, st.thin, 7.0, 5.0)
	st.dashed(c, b, Vector2(a.x, b.y), col, st.thin, 7.0, 5.0)
	st.dashed(c, Vector2(a.x, b.y), a, col, st.thin, 7.0, 5.0)


## "ROLL 42   4 CELLS LEFT", along the bottom of the board. Numbers, not a bar.
func paint_counters(c: CanvasItem, g) -> void:
	var st: StyleScript = g.style()
	var font := ThemeDB.fallback_font
	var txt := "ROLL %d    %d LEFT" % [roll_left, left()]
	if tangles > 0:
		txt += "    TANGLED %d" % tangles
	var w: float = font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
	var at: Vector2 = g.px(Vector2(0.0, view.y * 0.5 - 1.6)) + Vector2(-w * 0.5, 0.0)
	c.draw_rect(Rect2(at - Vector2(8.0, 16.0), Vector2(w + 16.0, 22.0)), Color(st.bg, 0.72))
	var col: Color = st.danger if roll_left < 12 or tangles > 0 else Color(st.line_dim, 0.95)
	c.draw_string(font, at, txt, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 20, col)
