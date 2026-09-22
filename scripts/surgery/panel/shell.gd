extends RefCounted
## THE SURGERY SHELL (docs/SURGERY_SHELL_AND_DODGE_SPEC.md, Part One): what every step's page has in
## common, drawn with the ink look (ink.gd). The clipboard itself is ink.gd's begin_page / end_page;
## this is what goes on the sheet:
##   - STAMP CARDS (section 2): every instruction. A translucent stamped box over the live game with
##     the phase's shout, a goal line and a line or two; gameplay waits under it for a press, and that
##     press is the first action. Interruption cards have a lockout with a live countdown.
##   - THE CORNER HUD (section 3): the controls for now, top left; the one number that decides the
##     grade, top right, deep red when it is in trouble; an ENTER key cap that pulses green when you may
##     move on.
##   - MISTAKES ON THE PAGE (section 4): a comic burst with one red word, 2-4 blood splats thrown
##     anywhere on the sheet that stay for the rest of the step, and for serious ones a shake and a red
##     wash.
## ArcadeGame owns one of these for a game on the ink look and drives it (show_card -> stamp, mistake()
## -> bursts and splats, the HUD from hud_line / hud_value / enter_cap). Everything is drawn in the
## game's layout coordinates, inside ink.begin_page / end_page, so it lies on the tilted sheet.
## Splats come from a seed and the mistake's index, so every machine throws the same ones.

const InkScript := preload("res://scripts/surgery/panel/ink.gd")

const BLOOD := [Color("6e1b1b"), Color("7c1f24"), Color("5a1414"), Color("84262a")]

var ink: InkScript = null
## The game's layout rectangle (canvas px): splats land anywhere in it, the HUD sits in its corners.
var area := Rect2(0, 0, 1200, 800)
## Seed for the splats (the step's seed).
var seed_v := 1
## SPLATS NEVER LAND HERE (canvas px, the game's layout space). docs/SUTURE_SPEC.md 5: the board is
## the readable surface and staining it hides the puzzle, so SUTURE! hands over its grid rectangle
## plus a margin and every splat is rejection-sampled outside it. Empty (the default) means anywhere
## in `area` is fair game, which is what every other step wants.
var keep_out := Rect2()
var t := 0.0

# -- tuning (reference px, times ink.unit) ----------------------------------------------------------
var stamp_size := Vector2(516.0, 274.0)   ## ~20% bigger than the original 430x228 (2026-09-22)
## WHERE THE STAMP LANDS ON THE PAPER, as a fraction of `area`. `area` is the sheet's content rect
## (ink.content), NOT the step's own layout, and every shelled step lays out on the same 960x600
## reference page -- so this is the same spot, at the same size, on DRAW!, DODGE!, WHACK!, WRAP! and
## SUTURE! alike. Move this, not the call sites: a step must never place its own card (2026-09-22).
var stamp_at := Vector2(0.5, 0.5)
var stamp_tilt_deg := -6.0
var burst_life := 1.4
var burst_radii := Vector2(46.0, 72.0)
var burst_squash := Vector2(1.7, 0.75)
var splat_grow := 0.35
var shake_time := 0.3
var shake_px := 14.0
var flash_alpha := 0.5

## No blob smaller than this (reference px): tinier ones collapse into slivers the triangulator refuses.
const MIN_BLOB_R := 1.2
## Splats start growing from this share of their size, not from a point.
const GROW_FROM := 0.2

var _bursts: Array = []          # [word, at, born]
var _splats: Array = []          # [centre, polys: Array[[PackedVector2Array, Color]], born]
var _shake := 0.0
var _shake_seed := 0


func _init(ink_style: InkScript) -> void:
	ink = ink_style


func tick(delta: float) -> void:
	t += delta
	_shake = maxf(0.0, _shake - delta)
	while not _bursts.is_empty() and t - float(_bursts[0][2]) > burst_life:
		_bursts.pop_front()


# ---------------------------------------------------------------------------- mistakes

## A mistake lands on the page: the burst word at `at` (layout px; off the page means the middle), the
## splats for mistake number `index`, and for a serious one the shake and the wash.
func mistake(word: String, at: Vector2, serious: bool, index: int) -> void:
	burst(word, at, serious, index)
	_throw_splats(index)


## A burst on its own, no blood: for a warning that is not a mistake (DODGE!'s SQUIRM!). `serious`
## still shakes and washes the page; `shake_seed` just varies the shake.
func burst(word: String, at: Vector2, serious := false, shake_seed := 0) -> void:
	if not area.has_point(at):
		at = area.get_center()
	# Keep the burst on the sheet.
	var m := burst_radii.y * burst_squash.x * ink.unit * 0.6
	at = Vector2(clampf(at.x, area.position.x + m, area.end.x - m), clampf(at.y, area.position.y + m * 0.5, area.end.y - m * 0.5))
	_bursts.append([word, at, t])
	if _bursts.size() > 4:
		_bursts.pop_front()
	if serious:
		_shake = shake_time
		_shake_seed = shake_seed


## BLOOD WITH NO BURST AND NO BILL: the page getting messier on its own, as a consequence rather than
## a mistake (WHACK!'s escalating splatter while a bleeder is left open). Seeded by `index` like every
## other splat, so every machine throws the same one.
func splat(index: int) -> void:
	_throw_splats(index)


## One mark where something landed (a drip running off the wound and hitting the foot of the page),
## instead of anywhere on the sheet. Smaller than a mistake's, and seeded by `index`.
func splat_at(at: Vector2, index: int) -> void:
	_throw_splats(index, at)


## The splats of mistake `index`: 2-4, each its own shape, kind, tone and drip, at random places -- or,
## with `at` given, ONE smaller mark landing about there.
func _throw_splats(index: int, at := Vector2(INF, INF)) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(seed_v * 7919 + index * 104729)
	var here := is_finite(at.x) and is_finite(at.y)
	var n := 1 if here else rng.randi_range(2, 4)
	for i in n:
		var centre := area.position + Vector2(rng.randf(), rng.randf()) * area.size
		# Off the board: rejection-sampled, with a fall-back to the margin either side so a silly
		# keep-out (one that swallows the page) can never spin here forever.
		if not here and keep_out.size.x > 0.0:
			var tries := 0
			while keep_out.has_point(centre) and tries < 24:
				centre = area.position + Vector2(rng.randf(), rng.randf()) * area.size
				tries += 1
			if keep_out.has_point(centre):
				var left: bool = rng.randf() < 0.5
				centre.x = lerpf(area.position.x, keep_out.position.x, rng.randf()) if left \
					else lerpf(keep_out.end.x, area.end.x, rng.randf())
		if here:
			centre = at + Vector2(rng.randf_range(-7.0, 7.0), rng.randf_range(-3.0, 3.0)) * ink.unit
		var base := rng.randf_range(5.0, 12.0) * ink.unit if here else rng.randf_range(10.0, 26.0) * ink.unit
		var col: Color = BLOOD[rng.randi_range(0, BLOOD.size() - 1)]
		col.a = rng.randf_range(0.32, 0.62)
		var squash := rng.randf_range(0.6, 1.1)
		var rot := rng.randf() * TAU
		var kind := rng.randi_range(0, 2)   # 0 speckle cluster, 1 round splat, 2 streaky
		var polys: Array = []
		var blob := func(ctr: Vector2, r: float) -> PackedVector2Array:
			# Vertices at strictly rising angles round the centre, radius jittered: a star-shaped outline
			# that cannot cross itself. The squash and the turn are affine, so it stays simple.
			r = maxf(r, MIN_BLOB_R * ink.unit)
			var pts := PackedVector2Array()
			var verts := rng.randi_range(10, 14)
			for v in verts:
				var ang := TAU * (float(v) + rng.randf_range(-0.3, 0.3)) / float(verts)
				var rr := r * rng.randf_range(0.55, 1.45)
				pts.append(ctr + Vector2(cos(ang) * rr, sin(ang) * rr * squash).rotated(rot))
			if Geometry2D.triangulate_polygon(pts).is_empty():
				pts = PackedVector2Array()
				for v in 10:
					var ang2 := TAU * float(v) / 10.0
					pts.append(ctr + Vector2(cos(ang2), sin(ang2)) * r)
			return pts
		match kind:
			0:
				for j in rng.randi_range(5, 9):
					var off := Vector2(rng.randf_range(-1.6, 1.6), rng.randf_range(-1.6, 1.6)) * base
					polys.append([blob.call(centre + off, base * rng.randf_range(0.12, 0.3)), col])
			1:
				polys.append([blob.call(centre, base), col])
				for j in rng.randi_range(2, 5):
					var ang := rng.randf() * TAU
					polys.append([blob.call(centre + Vector2(cos(ang), sin(ang)) * base * rng.randf_range(1.4, 2.1), base * rng.randf_range(0.1, 0.22)), col])
			2:
				polys.append([blob.call(centre, base * 0.8), col])
				var fling := Vector2(cos(rot), sin(rot))
				for j in rng.randi_range(3, 6):
					var along := base * rng.randf_range(1.0, 3.2)
					polys.append([blob.call(centre + fling * along + fling.orthogonal() * rng.randf_range(-0.3, 0.3) * base,
						base * rng.randf_range(0.08, 0.2)), col])
		# A drip, straight down whatever the splat's own turn.
		if rng.randf() < 0.6:
			var w := base * rng.randf_range(0.12, 0.2)
			var dl := base * rng.randf_range(1.0, 2.6)
			var drip := PackedVector2Array([centre + Vector2(-w, 0.0), centre + Vector2(w, 0.0),
				centre + Vector2(w * 0.6, dl), centre + Vector2(0.0, dl + w * 1.4), centre + Vector2(-w * 0.6, dl)])
			polys.append([drip, col])
		_splats.append([centre, polys, t])


## Test hook (the self-test): throw the splats of mistakes [from, from + n) and return every polygon.
func splat_polys_for(from: int, n: int) -> Array:
	var keep := _splats.duplicate()
	_splats.clear()
	for i in range(from, from + n):
		_throw_splats(i)
	var out: Array = []
	for sp in _splats:
		for pc in sp[1]:
			out.append(pc[0])
	_splats = keep
	return out


## Profiling: polygons draw_splats() issued on its last pass, baked ones counted once each.
var splat_polys := 0

# THE BAKED SHEET. Blood stays on the page for the rest of the step and never moves again once it has
# finished growing, but draw_colored_polygon re-triangulates on the CPU every frame, so a messy page
# used to cost a millisecond per hundred polygons EVERY FRAME, on the operator's machine and on every
# onlooker's. Finished splats are triangulated ONCE into a single mesh and drawn in one call, so the
# page costs the same whether it has two splats on it or two hundred. Only the handful still growing
# (splat_grow, 0.35 s) take the old per-polygon path. The pixels are identical: the same triangles in
# the same order with the same colours.
var _baked: ArrayMesh = null
## How many entries of _splats are in _baked. They mature in the order they were thrown.
var _baked_n := 0
## Polygons the triangulator refused, drawn the slow way for the rest of the step.
var _baked_odd: Array = []


## Everything thrown so far, scaling up over splat_grow and then staying.
func draw_splats(c: CanvasItem) -> void:
	splat_polys = 0
	# Something took splats away (the self-test's splat_polys_for): start the sheet again.
	if _baked_n > _splats.size():
		_baked = null
		_baked_n = 0
		_baked_odd.clear()
	# Fold in everything that has stopped growing since last time.
	var ripe := _baked_n
	while ripe < _splats.size() and t - float(_splats[ripe][2]) >= splat_grow:
		ripe += 1
	if ripe > _baked_n:
		_bake(ripe)
	if _baked != null:
		c.draw_mesh(_baked, null)
		ink.ops += 1
		splat_polys += _baked_n
	for odd in _baked_odd:
		c.draw_colored_polygon(odd[0], odd[1])
		ink.ops += 1
	for i in range(_baked_n, _splats.size()):
		var sp: Array = _splats[i]
		var k := clampf((t - float(sp[2])) / splat_grow, 0.0, 1.0)
		k = 1.0 - pow(1.0 - k, 3.0)
		var ctr: Vector2 = sp[0]
		for pc in sp[1]:
			var pts: PackedVector2Array = pc[0]
			if k < 1.0:
				var scaled := PackedVector2Array()
				for q in pts:
					scaled.append(ctr + (q - ctr) * lerpf(GROW_FROM, 1.0, k))
				pts = scaled
			c.draw_colored_polygon(pts, pc[1])
			ink.ops += 1
			splat_polys += 1


## Rebuild the baked sheet so it holds _splats[0, upto). Rebuilt whole rather than appended to, so the
## triangles stay in throw order and the overlaps blend the way they did when each was its own call.
func _bake(upto: int) -> void:
	var verts := PackedVector2Array()
	var cols := PackedColorArray()
	_baked_odd.clear()
	for i in upto:
		for pc in (_splats[i][1] as Array):
			var pts: PackedVector2Array = pc[0]
			var col: Color = pc[1]
			var tri := Geometry2D.triangulate_polygon(pts)
			if tri.is_empty():
				# Godot's own draw_colored_polygon would refuse it too, but keep the old path so a
				# sliver that somehow gets through still looks the way it did.
				_baked_odd.append([pts, col])
				continue
			for idx in tri:
				verts.append(pts[idx])
				cols.append(col)
	_baked_n = upto
	if verts.is_empty():
		_baked = null
		return
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_COLOR] = cols
	_baked = ArrayMesh.new()
	_baked.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)


## Canvas px to nudge the whole clipboard by while a serious mistake shakes it.
func shake_offset() -> Vector2:
	if _shake <= 0.0:
		return Vector2.ZERO
	var k := _shake / shake_time
	var ph := t * 60.0
	return Vector2(sin(ph * 1.7 + float(_shake_seed)), cos(ph * 2.3)) * shake_px * ink.unit * k


## The bursts, and the red wash of a serious mistake.
func draw_fx(c: CanvasItem) -> void:
	if _shake > 0.0:
		c.draw_rect(area, Color(ink.deep_red, flash_alpha * _shake / shake_time))
	for b in _bursts:
		var age := t - float(b[2])
		var a := clampf(1.0 - age / burst_life, 0.0, 1.0)
		var pop := 1.0 - pow(1.0 - clampf(age / 0.12, 0.0, 1.0), 2.0)
		_burst(c, b[1], String(b[0]), a, lerpf(0.6, 1.0, pop))


func _burst(c: CanvasItem, at: Vector2, word: String, a: float, s: float) -> void:
	var u := ink.unit * s
	var pts := PackedVector2Array()
	for i in 32:
		var ang := TAU * float(i) / 32.0
		var r := burst_radii.y if i % 2 == 0 else burst_radii.x
		pts.append(Vector2(cos(ang) * r * burst_squash.x, sin(ang) * r * burst_squash.y) * u)
	var xf := Transform2D(deg_to_rad(7.0), at)
	var placed := PackedVector2Array()
	for q in pts:
		placed.append(xf * q)
	c.draw_colored_polygon(placed, Color(ink.paper, a))
	ink.line(c, placed, Color(ink.ink, a), 3.5, 8801, true)
	var f := InkScript.font_upright()
	var px := int(round(34.0 * u))
	var w := f.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
	c.draw_string(f, at + Vector2(-w * 0.5, px * 0.33), word, HORIZONTAL_ALIGNMENT_LEFT, -1.0, px, Color(ink.deep_red, a))
	ink.ops += 2


# ---------------------------------------------------------------------------- the corner HUD

## The control line top left, the grade number top right (deep red when `bad`).
func draw_hud(c: CanvasItem, controls: String, value: String, bad: bool) -> void:
	var u := ink.unit
	if controls != "":
		# One or two lines ("\n"), kept short: the clip stands in the middle of the top edge.
		var y := 22.0
		for ln in controls.split("\n"):
			ink.text(c, area.position + Vector2(14.0, y) * u, ln, 13.0, Color(ink.ink, 0.7))
			y += 17.0
	if value != "":
		var f := InkScript.font_upright()
		var px := int(round(22.0 * u))
		var w := f.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
		c.draw_string(f, Vector2(area.end.x - 14.0 * u - w, area.position.y + 26.0 * u), value,
			HORIZONTAL_ALIGNMENT_LEFT, -1.0, px, ink.deep_red if bad else ink.ink)
		ink.ops += 1


## THE STANDARD CORNER HUD, top left, block one (docs/SUTURE_SPEC.md 6): WHAT YOU ARE TRYING TO DO,
## three short lines at most, each behind a small red bullet -- never how to press it. Returns the y
## (reference px, from the top of `area`) the next block starts at.
##
## New in SUTURE! and meant for all four steps eventually; the older steps still draw the one-line
## draw_hud() above and are unchanged until they are retrofitted.
func draw_rules(c: CanvasItem, lines: Array, y := 20.0) -> float:
	var u := ink.unit
	for ln in lines:
		var s := String(ln)
		if s == "":
			continue
		var at := area.position + Vector2(14.0, y) * u
		c.draw_circle(at + Vector2(3.0, -3.6) * u, 2.6 * u, Color(ink.deep_red, 0.9))
		ink.text(c, at + Vector2(12.0, 0.0) * u, s, 13.0, Color(ink.ink, 0.8))
		y += 17.0
	return y


## Block two: THE KEYBINDINGS AS KEY CAPS. Each `caps` entry is [cap, result]: the cap is a boxed
## pale key in the upright face, the result an italic plain-language line beside it. The boxes are the
## point -- a player scanning the corner tells a rule from a button without reading either.
func draw_keycaps(c: CanvasItem, caps: Array, y: float) -> float:
	var u := ink.unit
	y += 8.0
	var f := InkScript.font_upright()
	var px := int(round(11.0 * u))
	for e in caps:
		if not (e is Array) or (e as Array).size() < 2:
			continue
		var cap := String(e[0])
		var what := String(e[1])
		var w: float = f.get_string_size(cap, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
		var box := Rect2(area.position + Vector2(14.0, y) * u, Vector2(w + 14.0 * u, 19.0 * u))
		ink.rect(c, box, Color(ink.ink, 0.75), 1.4, 8721 + int(y), Color(ink.paper.darkened(0.05), 0.95))
		c.draw_string(f, box.position + Vector2(7.0 * u, box.size.y * 0.5 + px * 0.36), cap,
			HORIZONTAL_ALIGNMENT_LEFT, -1.0, px, Color(ink.ink, 0.9))
		ink.text(c, Vector2(box.end.x + 7.0 * u, box.position.y + box.size.y * 0.5 + 4.0 * u), what,
			12.0, Color(ink.label, 0.85))
		y += 24.0
	return y


## The ENTER key cap at `at` (layout px, its centre) with a short italic label under it: dim while you
## are still working, brightening on a slow green pulse once you may move on.
func draw_enter(c: CanvasItem, at: Vector2, label: String, ready: bool) -> void:
	var u := ink.unit
	var pulse := 0.5 + 0.5 * sin(t * 3.2)
	var col: Color = ink.good if ready else Color(ink.ink, 0.35)
	if ready:
		col = col.lightened(0.25 * pulse)
	var cap := Rect2(at - Vector2(40.0, 17.0) * u, Vector2(80.0, 34.0) * u)
	if ready:
		c.draw_rect(cap.grow(4.0 * u * pulse), Color(ink.good, 0.15 * pulse))
	ink.rect(c, cap, col, 2.4, 8701, Color(ink.paper.darkened(0.04), 0.9))
	ink.rect(c, cap.grow(-4.0 * u), Color(col, 0.6), 1.2, 8702)
	var f := InkScript.font_upright()
	var px := int(round(15.0 * u))
	var w := f.get_string_size("ENTER", HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
	c.draw_string(f, cap.get_center() + Vector2(-w * 0.5, px * 0.35), "ENTER", HORIZONTAL_ALIGNMENT_LEFT, -1.0, px, col)
	if label != "":
		ink.text(c, Vector2(at.x, cap.end.y + 16.0 * u), label, 12.0, Color(col, 0.9) if ready else Color(ink.label, 0.55), 1)


# ---------------------------------------------------------------------------- stamp cards

## A stamp card over the live game (no scrim). `card` is {goal, lines, prompt, color}. `lock_left`
## above 0 shows the countdown instead of the prompt; `k` 0..1 is how long it has been up (the pop).
##
## THE CARD IS PART OF THE PAPER. It is drawn inside begin_page/end_page, on top of the page's own
## transform, so it lies on the tilted sheet under the clip and the border, turns with the board and
## shakes with it -- one continuous surface, not an overlay that hands you off to a separate board.
## An onlooker across the room reads it off the physical clipboard. It sits at `stamp_at` on `area`
## (the same spot and size on every step), turned about its own middle.
func draw_stamp(c: CanvasItem, shout: String, card: Dictionary, lock_left: float, k: float) -> void:
	var page_xf: Transform2D = _page_xf_now
	var at: Vector2 = area.position + area.size * stamp_at
	var u := ink.unit
	var size := stamp_size * u
	var col: Color = card.get("color", ink.ink)
	var pop := 1.0 - pow(1.0 - clampf(k * 5.0, 0.0, 1.0), 3.0)
	c.draw_set_transform_matrix(page_xf * Transform2D(deg_to_rad(stamp_tilt_deg), at)
		* Transform2D().scaled(Vector2.ONE * lerpf(0.9, 1.0, pop)))
	var box := Rect2(-size * 0.5, size)
	c.draw_rect(box, Color(ink.paper, 0.8))
	ink.rect(c, box, col, 5.0, 8601)
	ink.rect(c, box.grow(-9.0 * u), Color(col, 0.8), 2.0, 8602)
	var fu := InkScript.font_upright()
	var big := int(round(63.0 * u))
	var w := fu.get_string_size(shout, HORIZONTAL_ALIGNMENT_LEFT, -1, big).x
	var y := box.position.y + 20.0 * u + big * 0.8
	c.draw_string(fu, Vector2(-w * 0.5, y), shout, HORIZONTAL_ALIGNMENT_LEFT, -1.0, big, col)
	y += 14.0 * u
	c.draw_line(Vector2(box.position.x + 40.0 * u, y), Vector2(box.end.x - 40.0 * u, y), Color(ink.ink, 0.6), 1.0)
	y += 24.0 * u
	var goal := String(card.get("goal", ""))
	if goal != "":
		ink.text(c, Vector2(0.0, y), goal, 16.0, ink.ink, 1)
		y += 22.0 * u
	for ln in card.get("lines", []):
		ink.text(c, Vector2(0.0, y), String(ln), 13.0, Color(ink.label, 0.9), 1)
		y += 18.0 * u
	var prompt := String(card.get("prompt", ""))
	if lock_left > 0.0:
		prompt = "%s %.1f" % [String(card.get("wait", "Hold on...")), lock_left]
	if prompt != "":
		var fb := InkScript.font_upright()
		var pp := int(round(15.0 * u))
		var pw := fb.get_string_size(prompt, HORIZONTAL_ALIGNMENT_LEFT, -1, pp).x
		c.draw_string(fb, Vector2(-pw * 0.5, box.end.y - 18.0 * u), prompt, HORIZONTAL_ALIGNMENT_LEFT, -1.0, pp,
			Color(ink.ink, 0.5) if lock_left > 0.0 else ink.ink)
	ink.ops += 6
	# Back to the page's own frame, so whatever draws after this still lands on the sheet.
	c.draw_set_transform_matrix(page_xf)


## The page transform in force, set by whoever draws (so a stamp can turn about its own middle and go
## back). ArcadeGame sets it each paint.
var _page_xf_now := Transform2D.IDENTITY


## Warmup: one of everything.
func warm(c: CanvasItem) -> void:
	mistake("MISS!", area.get_center(), true, 0)
	draw_splats(c)
	draw_fx(c)
	draw_hud(c, "SPACE hold: draw", "4.1 mL", true)
	draw_enter(c, area.get_center(), "next", true)
	draw_stamp(c, "DRAW!", {"goal": "Warm", "lines": ["up"], "prompt": "SPACE"}, 0.0, 1.0)
