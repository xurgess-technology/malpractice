extends Control
## SKILL TREE: the picture on the vein machine's big screen in Personnel, drawn into a SubViewport
## (scripts/personnel/vein_machine.gd puts it on the glass). The same picture on every machine: it
## draws whoever is at the reader (Net.station_user("veins")) from their replicated skills
## (Net.skills_for), with its own clock started when this machine learned they put their palm down.
##
## The timeline (seconds after the palm goes down):
##   0.00  the screen wakes: grid, header, READING
##   0.15  the hand's outline fades in
##   0.45  the scan line sweeps up the hand, lighting it and the veins inside it as it passes
##   1.20  the veins run up the fingers
##   1.75  and out of the fingertips across the screen, forking into the skills (GROW_SPEED px/s,
##         each branch starting when its parent arrives), with little capillaries off the sides
##   then  blood runs into every vein whose skill is unlocked; labels and panels fade in; a
##         heartbeat pulses along the blood every BEAT seconds
##
## Everything is laid out once from SkillTree (scripts/skills/skill_tree.gd): each tree is a vein
## out of one finger, and each skill sits on it at its `at` (how far out, how far to the side).

const W := 1600
const H := 850
const TREE_SCRIPT := preload("res://scripts/skills/skill_tree.gd")

const T_WAKE := 0.0
const T_OUTLINE := 0.15
const T_SCAN := 0.45
const T_SCAN_END := 1.6
const T_HAND_VEINS := 1.2
const T_TREE := 1.75
const GROW_SPEED := 430.0
const FILL_SECONDS := 0.55
const BEAT := 1.15
const PULSE_SPEED := 1250.0
const SIDE_PX := 92.0
const NODE_R := 17.0
const HIT_R := 30.0

## The playfield the veins may use: off the header and clear of the two bottom panels.
const FIELD := Rect2(36, 74, W - 72, 600)
const PANEL_L := Rect2(26, 654, 520, 176)
const PANEL_R := Rect2(W - 26 - 470, 684, 470, 146)

const BG := Color(0.018, 0.03, 0.04)
const GRID := Color(0.08, 0.17, 0.2, 0.35)
const SCAN := Color(0.37, 0.9, 1.0)
const INK := Color(0.72, 0.9, 0.95)
const DIM := Color(0.42, 0.56, 0.62)
const VEIN := Color(0.14, 0.3, 0.47)
const VEIN_EDGE := Color(0.3, 0.55, 0.78)
const BLOOD := Color(0.62, 0.03, 0.06)
const BLOOD_HOT := Color(1.0, 0.2, 0.2)
const ACCENTS := {"survival": Color(0.55, 0.9, 0.6), "surgery": Color(0.45, 0.85, 1.0),
		"anatomy": Color(0.78, 0.62, 1.0), "pharmacology": Color(1.0, 0.8, 0.4), "logistics": Color(0.93, 0.9, 0.62)}

## Fingers, thumb first: base on the palm, angle off straight up (degrees, + to the right), length,
## width. Their order is SkillTree.TREES' order.
const FINGERS := [
	{"base": Vector2(706, 742), "deg": -42.0, "len": 140.0, "w": 58.0},
	{"base": Vector2(727, 640), "deg": -14.0, "len": 150.0, "w": 50.0},
	{"base": Vector2(790, 628), "deg": -3.0, "len": 170.0, "w": 52.0},
	{"base": Vector2(852, 634), "deg": 8.0, "len": 155.0, "w": 49.0},
	{"base": Vector2(898, 660), "deg": 20.0, "len": 118.0, "w": 44.0},
]
const PALM := [Vector2(702, 880), Vector2(690, 790), Vector2(686, 700), Vector2(698, 650), Vector2(724, 628),
		Vector2(800, 616), Vector2(880, 624), Vector2(914, 650), Vector2(920, 702), Vector2(908, 792), Vector2(898, 880)]
## Each tree's vein out of its fingertip: its heading (degrees off up) and how much it bends further
## out over its length.
const HEADINGS := [-60.0, -38.0, 0.0, 36.0, 64.0]
const BENDS := [-22.0, -8.0, 3.0, 8.0, 14.0]

var font: Font

## Who is at the reader (0: nobody), their name, and their replicated entry {u, p, f}.
var user := 0
var user_name := ""
var unlocked: Dictionary = {}
var points := 0
var focus := ""
## Local only: the node under this machine's cursor (only the user has one).
var hover := ""
var hover_button := false
## Seconds since the palm went down on this machine.
var t := 0.0
## Idle fade: 1 while someone is at it, falling to 0 after they leave.
var _live := 0.0

## Layout (built once).
var _tips: Array = []            # per tree: fingertip Vector2
var _hand_veins: Array = []      # per tree: {pts, cum, len}
var _pos: Dictionary = {}        # skill id -> Vector2
var _edges: Array = []           # {from ("" = fingertip), to, tree, pts, cum, len, depth, start, twigs, d0}
var _arrive: Dictionary = {}     # skill id -> seconds the vein reaches it
var _grow_end := 0.0
var _fill_at: Dictionary = {}    # edge key / "hand:<tree>" -> seconds blood starts in
var _button_rect := Rect2()


func _ready() -> void:
	font = ThemeDB.fallback_font
	size = Vector2(W, H)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layout()


# ---------------------------------------------------------------------------- state

## Someone put their palm down (or left: user 0). Starts the timeline from zero.
func begin(peer: int, display_name: String, entry: Dictionary) -> void:
	user = peer
	user_name = display_name
	t = 0.0
	hover = ""
	hover_button = false
	_fill_at.clear()
	_take_entry(entry, false)
	for id in unlocked.keys():
		_schedule_fill(String(id), -1.0)


func end() -> void:
	user = 0
	hover = ""
	hover_button = false


## The user's replicated skills changed: anything newly unlocked has blood run into it now.
func update_entry(entry: Dictionary) -> void:
	_take_entry(entry, true)


func _take_entry(entry: Dictionary, animate: bool) -> void:
	var now := {}
	for id in entry.get("u", []):
		now[String(id)] = true
	if animate:
		for id in now.keys():
			if not unlocked.has(id):
				_schedule_fill(String(id), maxf(t, _grow_end))
	unlocked = now
	points = int(entry.get("p", 0))
	focus = String(entry.get("f", ""))


## When blood runs into a skill's veins. at < 0: the intro's own fill, after its vein has grown.
func _schedule_fill(id: String, at: float) -> void:
	if not _pos.has(id):
		return
	var tree := String(TREE_SCRIPT.skill(id).tree)
	var hk := "hand:" + tree
	var edge_at := at
	if at < 0.0:
		edge_at = float(_arrive.get(id, _grow_end)) + 0.2
		var hand_at := T_TREE + 0.15
		_fill_at[hk] = minf(float(_fill_at.get(hk, hand_at)), hand_at)
	elif not _fill_at.has(hk):
		_fill_at[hk] = at
		edge_at = at + FILL_SECONDS * 0.8
	for e in _edges:
		if String(e.to) == id:
			_fill_at[_ekey(e)] = edge_at


func _ekey(e: Dictionary) -> String:
	return "%s>%s" % [e.from, e.to]


func grown() -> bool:
	return t >= _grow_end + 0.4


# ---------------------------------------------------------------------------- input (the user's machine)

func node_at(px: Vector2) -> String:
	if user == 0 or t < T_TREE:
		return ""
	var best := ""
	var best_d := HIT_R
	for id in _pos.keys():
		if t < float(_arrive.get(id, 0.0)):
			continue
		var d := px.distance_to(_pos[id])
		if d < best_d:
			best_d = d
			best = String(id)
	return best


func point_at(px: Vector2) -> void:
	hover = node_at(px)
	hover_button = _button_rect.has_area() and _button_rect.has_point(px)


## What a click at `px` asks for: "select:<id>", "unlock:<id>" or "".
func click_at(px: Vector2) -> String:
	if _button_rect.has_area() and _button_rect.has_point(px) and focus != "":
		return "unlock:" + focus
	var id := node_at(px)
	return "select:" + id if id != "" else ""


func node_position(id: String) -> Vector2:
	return _pos.get(id, Vector2(-1, -1))


func button_rect() -> Rect2:
	return _button_rect


# ---------------------------------------------------------------------------- layout

func _layout() -> void:
	_tips.clear()
	_hand_veins.clear()
	_pos.clear()
	_edges.clear()
	_arrive.clear()
	var trees: Array = TREE_SCRIPT.TREES
	for i in trees.size():
		var f: Dictionary = FINGERS[i]
		var dir := _dir(float(f.deg))
		var tip: Vector2 = f.base + dir * float(f.len)
		_tips.append(tip)
		# Inside the hand: from the wrist, spreading through the palm to the finger's base, up it.
		var wrist := Vector2(800.0 + (i - 2) * 16.0, 872.0)
		var palm: Vector2 = wrist.lerp(f.base, 0.55) + Vector2((i - 2) * 10.0, 0.0)
		var pts := _smooth([wrist, palm, f.base, f.base.lerp(tip, 0.55), tip - dir * 8.0], 10)
		_hand_veins.append(_measured(pts))
		# Out of the fingertip: the tree's trunk, bending outward, to the edge of the field.
		var trunk := _trunk(tip, float(HEADINGS[i]), float(BENDS[i]))
		var tree_id := String(trees[i].id)
		for id in TREE_SCRIPT.skills_in(tree_id):
			var at: Vector2 = TREE_SCRIPT.skill(id).at
			var p := _on_trunk(trunk, at.x)
			_pos[id] = _keep_in(p.pos + p.right * at.y * SIDE_PX)
	# Edges: requirement -> skill; a root hangs off its fingertip.
	for id in TREE_SCRIPT.SKILLS.keys():
		var s: Dictionary = TREE_SCRIPT.SKILLS[id]
		var ti := TREE_SCRIPT.tree_index(String(s.tree))
		var reqs: Array = s.requires
		if reqs.is_empty():
			_edges.append(_edge("", String(id), ti, _tips[ti], _pos[id]))
		for r in reqs:
			_edges.append(_edge(String(r), String(id), ti, _pos[String(r)], _pos[id]))
	# Timing: a vein sets off when the one before it arrives; a node arrives with its last vein.
	for id in _pos.keys():
		_arrival(String(id))
	for e in _edges:
		e.start = T_TREE + 0.07 * float(int(e.tree) % 3) if String(e.from) == "" else _arrival(String(e.from))
	_grow_end = 0.0
	for id in _arrive.keys():
		_grow_end = maxf(_grow_end, float(_arrive[id]))
	# Distance from the wrist of each edge's start, for the heartbeat pulse.
	for e in _edges:
		e.d0 = _dist_to(String(e.from), int(e.tree))


func _arrival(id: String) -> float:
	if _arrive.has(id):
		return float(_arrive[id])
	var latest := 0.0
	for e in _edges:
		if String(e.to) == id:
			var from_t := T_TREE + 0.07 * float(int(e.tree) % 3) if String(e.from) == "" else _arrival(String(e.from))
			latest = maxf(latest, from_t + float(e.len) / GROW_SPEED)
	_arrive[id] = latest
	return latest


func _dist_to(id: String, tree: int) -> float:
	var hand: float = _hand_veins[tree].len
	if id == "":
		return hand
	var best := 0.0
	for e in _edges:
		if String(e.to) == id:
			best = maxf(best, _dist_to(String(e.from), tree) + float(e.len))
	return best if best > 0.0 else hand


func _edge(from: String, to: String, tree: int, a: Vector2, b: Vector2) -> Dictionary:
	var h := _hash(from + ">" + to)
	var d := b - a
	var n := Vector2(-d.y, d.x).normalized()
	var bow := (float(h % 1000) / 1000.0 - 0.5) * 0.34 * d.length()
	var c := (a + b) * 0.5 + n * bow
	var steps := maxi(10, int(d.length() / 10.0))
	var pts := PackedVector2Array()
	var phase := float(h % 628) / 100.0
	for k in steps + 1:
		var s := float(k) / float(steps)
		var p := a.lerp(c, s).lerp(c.lerp(b, s), s)
		p += n * sin(s * 9.0 + phase) * 4.0 * sin(s * PI)
		pts.append(p)
	var e := _measured(pts)
	e.from = from
	e.to = to
	e.tree = tree
	e.depth = TREE_SCRIPT.depth(to)
	e.start = 0.0
	e.d0 = 0.0
	# Capillaries: two or three short twigs off the sides, drawn thin and dim, grown with the vein.
	var twigs := []
	var count := 2 + int(h % 2)
	for k in count:
		var hh := _hash("%s%d" % [to, k])
		var s := 0.25 + 0.55 * float(hh % 100) / 100.0
		var side := 1.0 if (hh / 7) % 2 == 0 else -1.0
		var ang := deg_to_rad(35.0 + float(hh % 40)) * side
		var at := _point_at(e, s)
		var tan := _tangent_at(e, s)
		var tw_len := 16.0 + float((hh / 13) % 28)
		var mid: Vector2 = at + tan.rotated(ang * 0.6) * tw_len * 0.55
		var end: Vector2 = at + tan.rotated(ang) * tw_len
		twigs.append({"s": s, "pts": PackedVector2Array([at, mid, end])})
	e.twigs = twigs
	return e


static func _dir(deg: float) -> Vector2:
	var r := deg_to_rad(deg)
	return Vector2(sin(r), -cos(r))


## The trunk out of a fingertip: points 4 px apart until it leaves the field.
func _trunk(tip: Vector2, heading: float, bend: float) -> PackedVector2Array:
	var pts := PackedVector2Array([tip])
	var p := tip
	var total := 0.0
	var max_len := 900.0
	while total < max_len:
		var k := total / 600.0
		p += _dir(heading + bend * k) * 4.0
		total += 4.0
		if not FIELD.has_point(p):
			break
		pts.append(p)
	return pts


## A point `frac` of the way along a trunk, with the direction to its right.
func _on_trunk(pts: PackedVector2Array, frac: float) -> Dictionary:
	var i := clampi(int(round(frac * float(pts.size() - 1))), 0, pts.size() - 1)
	var j := clampi(i + 1, 1, pts.size() - 1)
	var tan := (pts[j] - pts[j - 1]).normalized()
	return {"pos": pts[i], "right": Vector2(-tan.y, tan.x)}


func _keep_in(p: Vector2) -> Vector2:
	return Vector2(clampf(p.x, FIELD.position.x + 24, FIELD.end.x - 24), clampf(p.y, FIELD.position.y + 24, FIELD.end.y - 10))


func _smooth(ctrl: Array, per: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in ctrl.size() - 1:
		var p0: Vector2 = ctrl[maxi(i - 1, 0)]
		var p1: Vector2 = ctrl[i]
		var p2: Vector2 = ctrl[i + 1]
		var p3: Vector2 = ctrl[mini(i + 2, ctrl.size() - 1)]
		for k in per:
			var s := float(k) / float(per)
			out.append(0.5 * ((2.0 * p1) + (-p0 + p2) * s + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * s * s
					+ (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * s * s * s))
	out.append(ctrl[ctrl.size() - 1])
	return out


func _measured(pts: PackedVector2Array) -> Dictionary:
	var cum := PackedFloat32Array([0.0])
	for k in range(1, pts.size()):
		cum.append(cum[k - 1] + pts[k].distance_to(pts[k - 1]))
	return {"pts": pts, "cum": cum, "len": cum[cum.size() - 1]}


func _point_at(e: Dictionary, frac: float) -> Vector2:
	var pts: PackedVector2Array = e.pts
	var cum: PackedFloat32Array = e.cum
	var d := clampf(frac, 0.0, 1.0) * float(e.len)
	for k in range(1, pts.size()):
		if cum[k] >= d:
			var seg := cum[k] - cum[k - 1]
			return pts[k - 1].lerp(pts[k], 0.0 if seg <= 0.0 else (d - cum[k - 1]) / seg)
	return pts[pts.size() - 1]


func _tangent_at(e: Dictionary, frac: float) -> Vector2:
	var a := _point_at(e, maxf(frac - 0.02, 0.0))
	var b := _point_at(e, minf(frac + 0.02, 1.0))
	return (b - a).normalized()


## The first `frac` of a polyline (at least two points, or empty).
func _part(e: Dictionary, frac: float) -> PackedVector2Array:
	var pts: PackedVector2Array = e.pts
	if frac >= 1.0:
		return pts
	if frac <= 0.0:
		return PackedVector2Array()
	var cum: PackedFloat32Array = e.cum
	var d := frac * float(e.len)
	var out := PackedVector2Array([pts[0]])
	for k in range(1, pts.size()):
		if cum[k] >= d:
			var seg := cum[k] - cum[k - 1]
			out.append(pts[k - 1].lerp(pts[k], 0.0 if seg <= 0.0 else (d - cum[k - 1]) / seg))
			return out
		out.append(pts[k])
	return out


static func _hash(s: String) -> int:
	return absi(hash(s))


# ---------------------------------------------------------------------------- per frame

func tick(delta: float) -> void:
	if user != 0:
		t += delta
		_live = minf(1.0, _live + delta * 4.0)
	else:
		_live = maxf(0.0, _live - delta * 2.5)
		t += delta
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(0, 0, W, H), BG)
	_draw_grid()
	if user == 0 and _live <= 0.0:
		_draw_idle()
		return
	var a := _live
	var wake := clampf((t - T_WAKE) / 0.25, 0.0, 1.0) * a
	_draw_hand(a)
	_draw_hand_veins(a)
	_draw_edges(a)
	_draw_nodes(a)
	_draw_scan(a)
	_draw_header(wake)
	if t >= _grow_end - 0.3:
		var k := clampf((t - (_grow_end - 0.3)) / 0.5, 0.0, 1.0) * a
		_draw_labels(k)
		_draw_panels(k)
	else:
		_button_rect = Rect2()
	_draw_vignette()


func _draw_grid() -> void:
	for x in range(0, W + 1, 50):
		draw_line(Vector2(x, 0), Vector2(x, H), GRID, 1.0)
	for y in range(0, H + 1, 50):
		draw_line(Vector2(0, y), Vector2(W, y), GRID, 1.0)


func _draw_vignette() -> void:
	# Four soft edges, darker at the rim, like the glass is thicker there.
	for k in 6:
		var w := 14.0 + k * 12.0
		var c := Color(0, 0, 0, 0.09)
		draw_rect(Rect2(0, 0, W, w), c)
		draw_rect(Rect2(0, H - w, W, w), c)
		draw_rect(Rect2(0, 0, w, H), c)
		draw_rect(Rect2(W - w, 0, w, H), c)


## Nobody at it: the hand's outline, dim, and an invitation that blinks.
func _draw_idle() -> void:
	var blink := 0.55 + 0.45 * sin(t * 3.0)
	_hand_shape(Color(SCAN, 0.1), Color(SCAN, 0.22 + 0.12 * blink), 1.0)
	_text("PLACE PALM ON READER", Vector2(0, 360), 44, Color(SCAN, 0.5 + 0.4 * blink), W, HORIZONTAL_ALIGNMENT_CENTER)
	_text("ST. DOE'S GENERAL  ·  PERSONNEL  ·  PALM VEIN READER", Vector2(0, 410), 20, Color(DIM, 0.8), W, HORIZONTAL_ALIGNMENT_CENTER)


func _draw_header(a: float) -> void:
	if a <= 0.0:
		return
	_text("ST. DOE'S GENERAL  ·  PALM VEIN READER", Vector2(34, 44), 20, Color(DIM, a))
	var who := "DR. " + user_name.to_upper() if user_name != "" else "UNKNOWN"
	var status := ""
	if t < T_SCAN_END:
		status = "READING  %d%%" % int(clampf((t - T_SCAN) / (T_SCAN_END - T_SCAN), 0.0, 1.0) * 100.0)
	elif t < _grow_end:
		status = "MAPPING VEINS"
	else:
		status = "MATCH  ·  " + who
	var blink := 1.0 if t >= _grow_end else 0.6 + 0.4 * sin(t * 12.0)
	_text(status, Vector2(W - 34 - 700, 44), 20, Color(SCAN, a * blink), 700, HORIZONTAL_ALIGNMENT_RIGHT)
	draw_line(Vector2(34, 58), Vector2(W - 34, 58), Color(GRID, a * 1.6), 1.0)


## The hand's silhouette. Colours are flattened onto the background first, so where a finger and
## the palm overlap nothing shows through twice.
func _hand_shape(fill: Color, edge: Color, grow := 1.0) -> void:
	fill = BG.lerp(Color(fill, 1.0), fill.a)
	edge = BG.lerp(Color(edge, 1.0), edge.a)
	for f in FINGERS:
		var tip: Vector2 = f.base + _dir(float(f.deg)) * float(f.len)
		draw_line(f.base, tip, edge, float(f.w) + 5.0 * grow)
		draw_circle(tip, (float(f.w) + 5.0 * grow) * 0.5, edge)
	draw_colored_polygon(PackedVector2Array(PALM), edge)
	for f in FINGERS:
		var tip: Vector2 = f.base + _dir(float(f.deg)) * float(f.len)
		draw_line(f.base, tip, BG, float(f.w) - 1.0)
		draw_circle(tip, (float(f.w) - 1.0) * 0.5, BG)
		draw_line(f.base, tip, fill, float(f.w) - 1.0)
		draw_circle(tip, (float(f.w) - 1.0) * 0.5, fill)
	var inner := PackedVector2Array()
	var c := Vector2(800, 760)
	for p in PALM:
		inner.append(c + (p - c) * 0.975)
	draw_colored_polygon(inner, BG)
	draw_colored_polygon(inner, fill)


func _draw_hand(a: float) -> void:
	var outline := clampf((t - T_OUTLINE) / 0.3, 0.0, 1.0)
	var scanned := clampf((t - T_SCAN) / (T_SCAN_END - T_SCAN), 0.0, 1.0)
	var settled := clampf((t - T_SCAN_END) / 0.6, 0.0, 1.0)
	if outline <= 0.0:
		return
	var fill_a := lerpf(0.05, 0.1, scanned) * a
	_hand_shape(Color(SCAN, fill_a), Color(SCAN, (0.35 * outline - 0.12 * settled) * a))
	# The scan lights what it has passed over, fading once it is done.
	if scanned > 0.0 and settled < 1.0:
		var y := _scan_y()
		var lit := BG.lerp(SCAN, (fill_a + 0.16 * (1.0 - settled)) * a)
		var clip := PackedVector2Array([Vector2(0, y), Vector2(W, y), Vector2(W, H + 40), Vector2(0, H + 40)])
		for poly in Geometry2D.intersect_polygons(PackedVector2Array(PALM), clip):
			draw_colored_polygon(poly, lit)
		for f in FINGERS:
			var tip: Vector2 = f.base + _dir(float(f.deg)) * float(f.len)
			var lo: Vector2 = f.base if f.base.y > tip.y else tip
			var hi: Vector2 = tip if f.base.y > tip.y else f.base
			if lo.y <= y:
				continue
			var cut := hi if hi.y >= y else lo.lerp(hi, (lo.y - y) / maxf(lo.y - hi.y, 0.001))
			draw_line(lo, cut, lit, float(f.w) - 2.0)
			if hi.y >= y:
				draw_circle(hi, (float(f.w) - 2.0) * 0.5, lit)


func _scan_y() -> float:
	var k := clampf((t - T_SCAN) / (T_SCAN_END - T_SCAN), 0.0, 1.0)
	return lerpf(890.0, 420.0, k * k * (3.0 - 2.0 * k))


func _draw_scan(a: float) -> void:
	if t < T_SCAN or t > T_SCAN_END + 0.3:
		return
	var fade := 1.0 - clampf((t - T_SCAN_END) / 0.3, 0.0, 1.0)
	var y := _scan_y()
	for k in 8:
		var h := 6.0 + k * 9.0
		draw_rect(Rect2(420, y, 760, h), Color(SCAN, 0.035 * fade * a))
	draw_line(Vector2(420, y), Vector2(1180, y), Color(SCAN, 0.9 * fade * a), 3.0)
	draw_line(Vector2(0, y), Vector2(W, y), Color(SCAN, 0.25 * fade * a), 1.0)


## The veins inside the hand: revealed by the scan, then grown up the fingers, then filled.
func _draw_hand_veins(a: float) -> void:
	var trees: Array = TREE_SCRIPT.TREES
	for i in _hand_veins.size():
		var hv: Dictionary = _hand_veins[i]
		# Revealed as the scan line passes up over it, then (if the scan was quick) grown the rest.
		var reveal := _below_scan(hv) if t >= T_SCAN else 0.0
		var grow := clampf((t - T_HAND_VEINS - 0.05 * i) / (T_TREE - T_HAND_VEINS), 0.0, 1.0)
		var frac := maxf(reveal, grow)
		var pts := _part(hv, frac)
		if pts.size() < 2:
			continue
		_vein(pts, 10.0, a)
		var fk := _fill_frac("hand:" + String(trees[i].id), float(hv.len))
		if fk > 0.0:
			_blood(_part(hv, minf(fk, frac)), 10.0, a, 0.0)


## How much of an in-hand vein (running up from the wrist) the scan line has passed.
func _below_scan(hv: Dictionary) -> float:
	if t >= T_SCAN_END:
		return 1.0
	var y := _scan_y()
	var pts: PackedVector2Array = hv.pts
	var cum: PackedFloat32Array = hv.cum
	for k in pts.size():
		if pts[k].y < y:
			return cum[maxi(k - 1, 0)] / float(hv.len)
	return 1.0


func _draw_edges(a: float) -> void:
	var beat := _beat()
	for e in _edges:
		var g := clampf((t - float(e.start)) / maxf(float(e.len) / GROW_SPEED, 0.01), 0.0, 1.0)
		if g <= 0.0:
			continue
		var w := maxf(3.5, 9.0 - (int(e.depth) - 1) * 1.6)
		for tw in e.twigs:
			var tg := clampf((g - float(tw.s)) / 0.25, 0.0, 1.0)
			if tg > 0.0:
				var tp: PackedVector2Array = tw.pts
				draw_polyline(PackedVector2Array([tp[0], tp[0].lerp(tp[1], minf(tg * 2.0, 1.0)),
						tp[1].lerp(tp[2], clampf(tg * 2.0 - 1.0, 0.0, 1.0))]), Color(VEIN_EDGE, 0.35 * a), 1.6, true)
		var pts := _part(e, g)
		if pts.size() < 2:
			continue
		_vein(pts, w, a)
		var fk := _fill_frac(_ekey(e), float(e.len))
		if fk > 0.0:
			_blood(_part(e, minf(fk, g)), w, a, beat)
			# The heartbeat: a bright bead running out along the blood.
			if fk >= 1.0 and t > _grow_end:
				var front := fmod(t, BEAT) * PULSE_SPEED
				var local: float = front - float(e.d0)
				if local >= 0.0 and local <= float(e.len):
					var p := _point_at(e, local / float(e.len))
					draw_circle(p, w * 1.1, Color(BLOOD_HOT, 0.25 * a))
					draw_circle(p, w * 0.55, Color(1.0, 0.55, 0.5, 0.8 * a))


## 0..1: how far blood has run into the vein `key` (length `len` px).
func _fill_frac(key: String, len: float) -> float:
	if not _fill_at.has(key):
		return 0.0
	var dur := maxf(FILL_SECONDS, len / 900.0)
	return clampf((t - float(_fill_at[key])) / dur, 0.0, 1.0)


## When blood finished running into the vein `key` (-1 if it never started).
func _fill_done(key: String) -> float:
	if not _fill_at.has(key):
		return -1.0
	for e in _edges:
		if _ekey(e) == key:
			return float(_fill_at[key]) + maxf(FILL_SECONDS, float(e.len) / 900.0)
	return float(_fill_at[key]) + FILL_SECONDS


## A heartbeat envelope: a quick swell and a slower fall, every BEAT seconds.
func _beat() -> float:
	var k := fmod(t, BEAT) / BEAT
	return exp(-k * 9.0) + 0.5 * exp(-absf(k - 0.22) * 22.0)


func _vein(pts: PackedVector2Array, w: float, a: float) -> void:
	draw_polyline(pts, Color(VEIN_EDGE, 0.55 * a), w + 3.0, true)
	draw_polyline(pts, Color(VEIN, a), w, true)
	draw_polyline(pts, Color(VEIN.lightened(0.25), 0.5 * a), maxf(1.0, w * 0.25), true)


func _blood(pts: PackedVector2Array, w: float, a: float, beat: float) -> void:
	if pts.size() < 2:
		return
	draw_polyline(pts, Color(BLOOD_HOT, (0.1 + 0.12 * beat) * a), w + 10.0 + 4.0 * beat, true)
	draw_polyline(pts, Color(BLOOD, a), w, true)
	draw_polyline(pts, Color(BLOOD_HOT, (0.55 + 0.3 * beat) * a), maxf(1.2, w * 0.35), true)


func _draw_nodes(a: float) -> void:
	var beat := _beat()
	for id in _pos.keys():
		var at := float(_arrive.get(id, 0.0))
		if t < at:
			continue
		var pop := clampf((t - at) / 0.28, 0.0, 1.0)
		var sc := 1.0 + 0.35 * sin(pop * PI) * (1.0 - pop) + (0.0 if pop >= 1.0 else 0.0)
		sc *= minf(1.0, pop * 3.0)
		var p: Vector2 = _pos[id]
		var r := NODE_R * sc
		var sid := String(id)
		var is_on := unlocked.has(sid)
		var filled := is_on and _fill_frac(_node_fill_key(sid), 1.0) >= 1.0
		var ready := not is_on and TREE_SCRIPT.prereqs_met(unlocked, sid)
		var afford := ready and points >= TREE_SCRIPT.cost(sid)
		if filled:
			# The moment the blood arrives: a ring thrown off the node.
			var since := t - _fill_done(_node_fill_key(sid))
			if since >= 0.0 and since < 0.7:
				var k := since / 0.7
				draw_arc(p, r + 6.0 + 46.0 * k, 0, TAU, 40, Color(BLOOD_HOT, (1.0 - k) * 0.9 * a), 4.0 * (1.0 - k) + 1.0, true)
			draw_circle(p, r + 8.0 + 4.0 * beat, Color(BLOOD_HOT, (0.14 + 0.1 * beat) * a))
			draw_circle(p, r, Color(BLOOD, a))
			draw_circle(p, r * 0.5, Color(BLOOD_HOT, (0.7 + 0.3 * beat) * a))
			draw_arc(p, r, 0, TAU, 32, Color(1.0, 0.45, 0.4, 0.8 * a), 2.0, true)
		else:
			draw_circle(p, r, Color(BG, a))
			draw_circle(p, r * 0.72, Color(VEIN, 0.8 * a))
			var ring := Color(VEIN_EDGE, 0.8 * a)
			if ready:
				var throb := 0.5 + 0.5 * sin(t * 4.0 + float(_hash(sid) % 100))
				ring = Color(INK, (0.55 + 0.4 * throb) * a) if afford else Color(INK, 0.45 * a)
			draw_arc(p, r, 0, TAU, 32, ring, 3.0 if ready else 2.0, true)
		if sid == focus:
			var spin := t * 1.6
			for k in 4:
				var a0 := spin + k * TAU / 4.0
				draw_arc(p, r + 9.0, a0, a0 + 0.9, 8, Color(1, 1, 1, 0.95 * a), 3.0, true)
		elif sid == hover:
			draw_arc(p, r + 7.0, 0, TAU, 32, Color(1, 1, 1, 0.55 * a), 2.0, true)


## A skill's node fills when the last of its incoming veins has.
func _node_fill_key(id: String) -> String:
	var key := ""
	var latest := -1.0
	for e in _edges:
		if String(e.to) == id and _fill_at.has(_ekey(e)) and float(_fill_at[_ekey(e)]) > latest:
			latest = float(_fill_at[_ekey(e)])
			key = _ekey(e)
	return key


func _draw_labels(a: float) -> void:
	var trees: Array = TREE_SCRIPT.TREES
	for i in trees.size():
		# The tree's name written along its finger, beside the vein, reading up the finger (the thumb
		# the other way round, so no name is upside down).
		var tid := String(trees[i].id)
		var f: Dictionary = FINGERS[i]
		var dir := _dir(float(f.deg))
		var along := dir if dir.x > -0.5 else -dir
		var label := String(trees[i].name)
		var sz := 17 if label.length() < 11 else 15
		var wdt := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x
		var mid: Vector2 = f.base + dir * float(f.len) * 0.5
		var side := Vector2(-along.y, along.x)   # below the text's baseline direction
		var origin := mid - along * wdt * 0.5 - side * 7.0
		draw_set_transform(origin, along.angle(), Vector2.ONE)
		_text(label, Vector2.ZERO, sz, Color(ACCENTS.get(tid, INK), a), -1, HORIZONTAL_ALIGNMENT_LEFT, true)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	for id in _pos.keys():
		var sid := String(id)
		var p: Vector2 = _pos[id]
		var s: Dictionary = TREE_SCRIPT.skill(sid)
		var col := INK if unlocked.has(sid) or TREE_SCRIPT.prereqs_met(unlocked, sid) else DIM
		var nm := String(s.name)
		var wdt := font.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
		var lx := clampf(p.x - wdt * 0.5, 10.0, W - 10.0 - wdt)
		_text(nm, Vector2(lx, p.y + NODE_R + 20.0), 15, Color(col, (1.0 if sid == focus or sid == hover else 0.8) * a), -1, HORIZONTAL_ALIGNMENT_LEFT, true)


func _draw_panels(a: float) -> void:
	# Right: who, and what they have to spend.
	_panel(PANEL_R, a)
	var r := PANEL_R
	var who := "DR. " + user_name.to_upper() if user_name != "" else "UNKNOWN"
	_text(who, r.position + Vector2(20, 36), 22, Color(INK, a))
	_text("SKILL POINTS", r.position + Vector2(20, 76), 18, Color(DIM, a))
	_text(str(points), r.position + Vector2(r.size.x - 20 - 120, 82), 40, Color(BLOOD_HOT if points > 0 else DIM, a), 120, HORIZONTAL_ALIGNMENT_RIGHT)
	_text("+%d per shift you clock out of" % 1, r.position + Vector2(20, 104), 15, Color(DIM, a))
	_text("Click a node   ·   Esc to step away", r.position + Vector2(20, 130), 15, Color(DIM, 0.8 * a))
	# Left: the picked node.
	_panel(PANEL_L, a)
	var l := PANEL_L
	_button_rect = Rect2()
	if focus == "" or not TREE_SCRIPT.exists(focus):
		_text("YOUR VEINS ARE YOUR SKILLS", l.position + Vector2(20, 40), 22, Color(INK, a))
		_wrap("Each vein out of your palm is a specialty; every fork on it is a skill. Pick one to read it. Blood fills the ones you have.",
				l.position + Vector2(20, 72), l.size.x - 40, 16, Color(DIM, a), 4)
		return
	var s: Dictionary = TREE_SCRIPT.skill(focus)
	var tid := String(s.tree)
	_text(TREE_SCRIPT.tree_name(tid), l.position + Vector2(20, 32), 16, Color(ACCENTS.get(tid, INK), a))
	_text(String(s.name).to_upper(), l.position + Vector2(20, 64), 28, Color(INK, a))
	_wrap(String(s.desc), l.position + Vector2(20, 92), l.size.x - 40, 17, Color(DIM.lightened(0.2), a), 2)
	var cost := TREE_SCRIPT.cost(focus)
	var foot := l.position + Vector2(20, l.size.y - 22)
	if unlocked.has(focus):
		_text("IN YOUR BLOOD", foot, 20, Color(BLOOD_HOT, a))
		return
	var problem := TREE_SCRIPT.unlock_problem(unlocked, points, focus)
	_text("COST  %d PT%s" % [cost, "" if cost == 1 else "S"], foot, 20, Color(INK, a))
	if problem != "":
		_text(problem, foot + Vector2(150, 0), 16, Color(DIM, a), l.size.x - 190)
		return
	_button_rect = Rect2(l.position + Vector2(l.size.x - 200, l.size.y - 56), Vector2(180, 44))
	var pulse := 0.5 + 0.5 * sin(t * 5.0)
	draw_rect(_button_rect, Color(BLOOD, (0.75 + (0.25 if hover_button else 0.0)) * a))
	draw_rect(_button_rect, Color(BLOOD_HOT, (0.6 + 0.4 * pulse) * a), false, 2.0)
	_text("INFUSE", _button_rect.position + Vector2(0, 30), 22, Color(1, 0.92, 0.9, a), _button_rect.size.x, HORIZONTAL_ALIGNMENT_CENTER)


func _panel(r: Rect2, a: float) -> void:
	draw_rect(r, Color(0.01, 0.03, 0.04, 0.88 * a))
	draw_rect(r, Color(SCAN, 0.35 * a), false, 1.5)
	var k := 12.0
	for c in [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]:
		var sx := 1.0 if c.x == r.position.x else -1.0
		var sy := 1.0 if c.y == r.position.y else -1.0
		draw_line(c, c + Vector2(sx * k, 0), Color(SCAN, 0.9 * a), 3.0)
		draw_line(c, c + Vector2(0, sy * k), Color(SCAN, 0.9 * a), 3.0)


func _text(s: String, pos: Vector2, px: int, col: Color, width := -1.0, align := HORIZONTAL_ALIGNMENT_LEFT, shadow := false) -> void:
	if col.a <= 0.0:
		return
	if shadow:
		draw_string_outline(font, pos, s, align, width, px, 6, Color(BG, col.a * 0.9))
	draw_string(font, pos, s, align, width, px, col)


func _wrap(s: String, pos: Vector2, width: float, px: int, col: Color, max_lines: int) -> void:
	var words := s.split(" ")
	var line := ""
	var y := pos.y
	var n := 0
	for w in words:
		var tryl := w if line == "" else line + " " + w
		if font.get_string_size(tryl, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x > width and line != "":
			_text(line, Vector2(pos.x, y), px, col)
			y += px + 6
			n += 1
			line = w
			if n >= max_lines:
				return
		else:
			line = tryl
	if line != "":
		_text(line, Vector2(pos.x, y), px, col)
