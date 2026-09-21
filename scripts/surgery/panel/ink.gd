extends Resource
## INK / PAPER (docs/PANEL_STYLE.md, "The ink look"): the hand-inked comic look for surgery panels.
##
## The pilot is the Anesthetic Injection (scripts/surgery/arcade/inject_arcade.gd); every other panel
## is to move onto it later, so everything here is shared and knows nothing about syringes. The teal
## X-ray look (panel_style.gd) stays for the games that have not moved yet.
##
## The look, in one breath: a paper sheet on a clipboard -- brown board, steel clip, heavy ink
## outlines, a hard flat shadow on the room -- with the sheet a hair crooked. Every outline is a polyline whose vertices are nudged by seeded noise that changes
## about seven times a second, so lines "boil" like hand-inked animation but hold still inside a
## frame. Fills are flat and never wobble. No gradients; shading is a halftone dot tile; the page
## carries a few faint grime smudges.
##
## Units. Everything a caller passes is in canvas PIXELS. `unit` is how many canvas pixels one
## reference pixel is (a game laid out on a 960-wide reference drawn onto the 1200-wide panel sets it
## to 1.25), and every weight, jitter and spacing below is in reference pixels, scaled by it.
##
## Use:
##     var ink: InkScript = InkScript.new()
##     ink.unit = 1.25
##     ink.t = seconds             # every frame, before drawing: drives the boil
##     ink.content = Rect2(...)    # optional: the part of the canvas the game lays out in
##     ink.begin_page(c, size)     # shadow, board, paper; everything after is on the paper
##     ink.line(c, pts, ink.ink, ink.outline, 17)
##     ink.end_page(c, size, "SEDATE", "TABLE 1")   # outlines, the clip with its title; plain drawing again

# -- palette ------------------------------------------------------------------------------------
@export var paper := Color("efe9dc")
@export var mat := Color("e9e3d6")
@export var ink := Color("221d18")
@export var ink_soft := Color("2a241d")
@export var label := Color("3a332a")
## Sickly green anaesthetic.
@export var drug := Color(0.627, 0.686, 0.373, 0.75)
@export var drug_pool := Color(0.471, 0.549, 0.314, 0.65)
@export var meniscus := Color("5a6932")
## The target band and its edge rules.
@export var band := Color(0.353, 0.549, 0.235, 0.30)
@export var band_edge := Color("4c6b3c")
## Warnings and the flash.
@export var deep_red := Color("7c1f24")
@export var flash := Color(0.588, 0.118, 0.118, 0.85)
## Stuck-bubble amber.
@export var amber := Color("a06a1f")
@export var amber_fill := Color(0.804, 0.706, 0.471, 0.55)
@export var bruise := Color(0.373, 0.176, 0.373, 0.45)
@export var bruise_core := Color(0.235, 0.098, 0.275, 0.50)
@export var skin_human := Color("dcc7a8")
@export var hide_seal := Color("67757b")
@export var vein_human := Color("5a7268")
@export var vein_seal := Color("2e4a4a")
## A limb under a tourniquet reddens: alpha = redness x this.
@export var redness := Color(0.647, 0.176, 0.157, 0.22)
@export var good := Color("4c6b3c")
@export var grime := Color(0.42, 0.38, 0.22)

# -- the clipboard (docs/SURGERY_SHELL_AND_DODGE_SPEC.md section 1) -------------------------------
## Every step is a page on the same clipboard, held a hair crooked (`tilt_deg`, the whole clipboard):
## brown hardboard in a 3 px ink border with a faint bevel line inside it, an even 14 px of board
## round the sheet, the cream sheet running up to the board's top edge, and a steel spring clip over
## its top with a thumb loop and a dark hinge bar. Only the clip casts a shadow. Everywhere else the
## panel is transparent (SurgeryPanel.transparent), so the clipboard is the one object you see.
## Sizes are reference px, times `unit`.
@export var board := Color("8a6b45")
@export var clip_body := Color("9aa0a4")
@export var clip_loop := Color("b6bbbe")
@export var clip_hinge := Color("3d4043")
@export var clip_shadow := Color(0.0, 0.0, 0.0, 0.35)
@export var clip_shadow_offset := Vector2(5.0, 7.0)
## Where the board sits on the canvas, canvas px: clear of the sides, and down from the top by enough
## that the clip's thumb loop (and the screen's caption bar above the panel) stay clear.
@export var board_side := 22.0
@export var board_top := 58.0
@export var board_bottom := 14.0
@export_range(0.0, 40.0, 0.5) var board_radius := 10.0
@export_range(1.0, 8.0, 0.1) var board_line := 3.0
@export_range(0.0, 40.0, 0.5) var board_margin := 14.0
@export_range(0.0, 20.0, 0.5) var bevel_in := 5.0
@export_range(0.0, 4.0, 0.1) var bevel_line := 1.5
@export_range(0.0, 1.0, 0.01) var bevel_alpha := 0.30
@export_range(0.5, 4.0, 0.1) var border := 1.5
@export_range(-5.0, 5.0, 0.05) var tilt_deg := -0.65
## The clip: body, thumb loop, and how far the body stands above the board's top edge.
@export var clip_size := Vector2(186.0, 58.0)
@export var loop_size := Vector2(54.0, 20.0)
@export_range(0.0, 58.0, 0.5) var clip_above := 20.0

# -- line work ----------------------------------------------------------------------------------
@export_range(0.5, 5.0, 0.1) var detail := 2.1
@export_range(1.0, 6.0, 0.1) var outline := 3.2
@export_range(1.0, 8.0, 0.1) var heavy := 4.0
## How far a vertex may be nudged either way, reference px.
@export_range(0.0, 4.0, 0.05) var jitter := 1.3
## Boils per second. Never per rendered frame: the boil must be steppy.
@export_range(1.0, 24.0, 0.5) var boil_fps := 7.0
## Roughly how far apart the vertices of a jittered line are, reference px.
@export_range(6.0, 60.0, 1.0) var sample := 23.0
@export_range(6, 48) var circle_segments := 18

# -- halftone and grime -------------------------------------------------------------------------
@export_range(3.0, 24.0, 0.5) var halftone_tile := 8.0
@export_range(0.3, 4.0, 0.05) var halftone_dot := 1.3
@export_range(0.0, 1.0, 0.01) var halftone_alpha := 0.5

## Canvas pixels per reference pixel.
var unit := 1.0
## The part of the canvas the game lays its diagram out in; it is fitted onto the paper at one uniform
## scale (page_fit()), so a millimetre on the diagram is the same everywhere. The whole canvas unless
## the game says otherwise.
var content := Rect2()
## Seconds, for the boil. Set it every frame before drawing.
var t := 0.0
## Profiling: draw commands issued since reset (every draw_* call counts one).
var ops := 0
## Jittered outlines, kept for the rest of their boil frame: seed -> [frame, input, output]. A shape
## that has not moved is not re-jittered until the next 7 fps tick.
var _jit := {}

static var _font: Font = null
static var _font_up: Font = null
## A soft white dot (round joins, caps, speckles) and the halftone tile, built once. Every dot is a
## textured quad with the same texture, so the canvas batches them into one draw instead of one
## polygon each; the halftone is ONE textured polygon however big it is.
static var _dot_tex: ImageTexture = null
static var _tiles := {}


# ---------------------------------------------------------------------------- noise

## -1..1, stable for the same three integers. Integer hashing, no allocation: this runs for every
## vertex of every line every frame.
static func noise(a: int, b: int, c: int) -> float:
	var n: int = a * 374761393 + b * 668265263 + c * 1274126177
	n = (n ^ (n >> 13)) * 1103515245
	n = n ^ (n >> 16)
	return float(n & 0xffff) / 32767.5 - 1.0


## Which boil frame it is.
func frame() -> int:
	return int(floor(t * boil_fps))


## `p` nudged for vertex `i` of shape `shape_seed`, this boil frame.
func wob(p: Vector2, shape_seed: int, i: int) -> Vector2:
	var f := frame()
	var j := jitter * unit
	return p + Vector2(noise(shape_seed, f, i * 2), noise(shape_seed, f, i * 2 + 1)) * j


# ---------------------------------------------------------------------------- lines

## Resample `pts` so no two vertices are further apart than `sample`, then jitter each one.
func jittered(pts: PackedVector2Array, shape_seed: int, closed := false) -> PackedVector2Array:
	var out := PackedVector2Array()
	var n := pts.size()
	if n < 2:
		return pts
	var step := maxf(2.0, sample * unit)
	var segs := n if closed else n - 1
	var k := 0
	for i in segs:
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[(i + 1) % n]
		var parts: int = maxi(1, int(ceil(a.distance_to(b) / step)))
		for s in parts:
			out.append(wob(a.lerp(b, float(s) / float(parts)), shape_seed, k))
			k += 1
	if closed:
		out.append(out[0])
	else:
		out.append(wob(pts[n - 1], shape_seed, k))
	return out


## jittered(), remembered until the boil ticks or the shape moves.
func jittered_cached(pts: PackedVector2Array, shape_seed: int, closed := false) -> PackedVector2Array:
	var f := frame()
	var key := shape_seed * 2 + (1 if closed else 0)
	var rec = _jit.get(key)
	if rec != null and int(rec[0]) == f and rec[1] == pts:
		return rec[2]
	var j := jittered(pts, shape_seed, closed)
	_jit[key] = [f, pts, j]
	return j


## A hand-inked line through `pts`. Round joins and caps: a dot at every vertex.
func line(c: CanvasItem, pts: PackedVector2Array, col: Color, width: float, shape_seed: int, closed := false) -> void:
	if pts.size() < 2:
		return
	var j := jittered_cached(pts, shape_seed, closed)
	stroke(c, j, col, width)


## An already-jittered (or deliberately straight) polyline, with round joins and caps.
func stroke(c: CanvasItem, pts: PackedVector2Array, col: Color, width: float) -> void:
	var w := width * unit
	c.draw_polyline(pts, col, w)
	ops += 1
	if w >= 2.0:
		var r := w * 0.5
		var tex := dot_texture()
		for p in pts:
			c.draw_texture_rect(tex, Rect2(p.x - r, p.y - r, w, w), false, col)
		ops += 1


func seg(c: CanvasItem, a: Vector2, b: Vector2, col: Color, width: float, shape_seed: int) -> void:
	line(c, PackedVector2Array([a, b]), col, width, shape_seed)


## Four samples per edge, as the look asks, with a flat un-jittered fill under it when `fill` has any
## alpha.
func rect(c: CanvasItem, r: Rect2, col: Color, width: float, shape_seed: int, fill := Color(0, 0, 0, 0)) -> void:
	if fill.a > 0.0:
		c.draw_rect(r, fill)
	var key := PackedVector2Array([r.position, r.size])
	var f := frame()
	var rec = _jit.get(-shape_seed - 1)
	var j: PackedVector2Array
	if rec != null and int(rec[0]) == f and rec[1] == key:
		j = rec[2]
	else:
		var pts := PackedVector2Array()
		var corners := [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]
		for i in 4:
			var a: Vector2 = corners[i]
			var b: Vector2 = corners[(i + 1) % 4]
			for sg in 4:
				pts.append(a.lerp(b, float(sg) / 4.0))
		j = PackedVector2Array()
		for i in pts.size():
			j.append(wob(pts[i], shape_seed, i))
		j.append(j[0])
		_jit[-shape_seed - 1] = [f, key, j]
	stroke(c, j, col, width)


func circle(c: CanvasItem, at: Vector2, r: float, col: Color, width: float, shape_seed: int, fill := Color(0, 0, 0, 0)) -> void:
	ellipse(c, at, Vector2(r, r), col, width, shape_seed, fill)


func ellipse(c: CanvasItem, at: Vector2, radii: Vector2, col: Color, width: float, shape_seed: int, fill := Color(0, 0, 0, 0), rot := 0.0) -> void:
	var n: int = circle_segments if maxf(radii.x, radii.y) > 6.0 * unit else 10
	var key := PackedVector2Array([at, radii, Vector2(rot, float(n))])
	var f := frame()
	var ck := -shape_seed - 500000
	var rec = _jit.get(ck)
	var flat: PackedVector2Array
	var j: PackedVector2Array
	if rec != null and int(rec[0]) == f and rec[1] == key:
		flat = rec[2]
		j = rec[3]
	else:
		flat = PackedVector2Array()
		for i in n:
			var a := TAU * float(i) / float(n)
			flat.append(at + Vector2(cos(a) * radii.x, sin(a) * radii.y).rotated(rot))
		j = PackedVector2Array()
		for i in n:
			j.append(wob(flat[i], shape_seed, i))
		j.append(j[0])
		_jit[ck] = [f, key, flat, j]
	if fill.a > 0.0:
		c.draw_colored_polygon(flat, fill)
		ops += 1
	if col.a <= 0.0 or width <= 0.0:
		return
	stroke(c, j, col, width)


## A flat fill with a boiling outline round it.
func shape(c: CanvasItem, pts: PackedVector2Array, col: Color, width: float, shape_seed: int, fill := Color(0, 0, 0, 0)) -> void:
	if fill.a > 0.0 and pts.size() >= 3:
		c.draw_colored_polygon(pts, fill)
	if col.a > 0.0 and width > 0.0:
		line(c, pts, col, width, shape_seed, true)


## A dashed ink line (the buried needle, guide rays). Dashes do not boil: they are already broken up.
func dashed(c: CanvasItem, a: Vector2, b: Vector2, col: Color, width: float, dash := 7.0, gap := 5.0) -> void:
	var d := b - a
	var total := d.length()
	if total < 0.001:
		return
	var dir := d / total
	var at := 0.0
	var dl := dash * unit
	var gl := gap * unit
	while at < total:
		var to := minf(at + dl, total)
		c.draw_line(a + dir * at, a + dir * to, col, width * unit)
		at = to + gl


# ---------------------------------------------------------------------------- shading

## The halftone tile over `r`: two ink dots per `halftone_tile`, as ONE textured rectangle.
func halftone(c: CanvasItem, r: Rect2, alpha: float, col := Color(-1, 0, 0)) -> void:
	halftone_poly(c, PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]), alpha, col)


## The halftone clipped to a shape (under a wavy skin edge, the bottom of a tray): one textured
## polygon, the tile repeating in canvas space so neighbouring patches line up.
func halftone_poly(c: CanvasItem, pts: PackedVector2Array, alpha: float, col := Color(-1, 0, 0)) -> void:
	if pts.size() < 3:
		return
	var tile := halftone_tile * unit
	var tex := _tile_texture(int(round(tile)), halftone_dot * unit)
	var cc: Color = ink if col.r < 0.0 else col
	cc.a = halftone_alpha * alpha
	var uvs := PackedVector2Array()
	uvs.resize(pts.size())
	var inv := 1.0 / float(tex.get_width())
	for i in pts.size():
		uvs[i] = pts[i] * inv
	if c.texture_repeat != CanvasItem.TEXTURE_REPEAT_ENABLED:
		c.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	c.draw_colored_polygon(pts, cc, uvs, tex)
	ops += 1


## A filled round dot as a batched textured quad (speckles, droplets, highlights).
func dot(c: CanvasItem, at: Vector2, r: float, col: Color) -> void:
	c.draw_texture_rect(dot_texture(), Rect2(at.x - r, at.y - r, r * 2.0, r * 2.0), false, col)
	ops += 1


static func dot_texture() -> ImageTexture:
	if _dot_tex == null:
		var n := 32
		var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
		var c := (float(n) - 1.0) * 0.5
		for y in n:
			for x in n:
				var d := Vector2(float(x) - c, float(y) - c).length()
				img.set_pixel(x, y, Color(1, 1, 1, clampf(c + 0.5 - d, 0.0, 1.0)))
		_dot_tex = ImageTexture.create_from_image(img)
	return _dot_tex


## The halftone tile at `size` canvas px: two dots of radius `r` at a quarter and three quarters,
## anti-aliased by supersampling, so it draws 1:1 on the panel.
static func _tile_texture(size: int, r: float) -> ImageTexture:
	size = maxi(2, size)
	var key := "%d|%.2f" % [size, r]
	if _tiles.has(key):
		return _tiles[key]
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var centres := [Vector2(0.25, 0.25) * float(size), Vector2(0.75, 0.75) * float(size)]
	for y in size:
		for x in size:
			var cover := 0.0
			for sy in 4:
				for sx in 4:
					var p := Vector2(float(x) + (float(sx) + 0.5) / 4.0, float(y) + (float(sy) + 0.5) / 4.0)
					for ctr: Vector2 in centres:
						if p.distance_to(ctr) <= r:
							cover += 1.0 / 16.0
							break
			img.set_pixel(x, y, Color(1, 1, 1, clampf(cover, 0.0, 1.0)))
	var tex := ImageTexture.create_from_image(img)
	_tiles[key] = tex
	return tex


## Soft olive-brown smudges on the page. `spots` is Array of [centre, radii, alpha], made once per run
## by make_grime() so they hold still.
func draw_grime(c: CanvasItem, spots: Array) -> void:
	# One soft textured quad per smudge: they share a texture, so they batch into a single draw.
	var tex := _blob_texture()
	for sp in spots:
		var at: Vector2 = sp[0]
		var rr: Vector2 = sp[1]
		c.draw_texture_rect(tex, Rect2(at - rr, rr * 2.0), false, Color(grime, float(sp[2]) * 1.6))
	ops += 1


static var _blob: ImageTexture = null

## A round smudge that fades out to its edge.
static func _blob_texture() -> ImageTexture:
	if _blob == null:
		var n := 64
		var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
		var ctr := (float(n) - 1.0) * 0.5
		for y in n:
			for x in n:
				var d := Vector2(float(x) - ctr, float(y) - ctr).length() / ctr
				img.set_pixel(x, y, Color(1, 1, 1, clampf(1.0 - d, 0.0, 1.0) ** 0.7))
		_blob = ImageTexture.create_from_image(img)
	return _blob


## 6-8 smudges inside `area` (canvas px), from `rng`.
static func make_grime(rng: RandomNumberGenerator, area: Rect2) -> Array:
	var out := []
	for i in rng.randi_range(6, 8):
		var at := area.position + Vector2(rng.randf(), rng.randf()) * area.size
		var r := rng.randf_range(0.05, 0.16) * area.size.x
		out.append([at, Vector2(r, r * rng.randf_range(0.5, 0.9)), rng.randf_range(0.03, 0.07)])
	return out


# ---------------------------------------------------------------------------- the page

## The board, on a canvas of `size`, before the tilt.
func board_rect(size: Vector2) -> Rect2:
	return Rect2(Vector2(board_side, board_top), size - Vector2(board_side * 2.0, board_top + board_bottom))


## The sheet on the board, before the tilt: 14 px of board on three sides, up to the top edge.
func sheet_rect(size: Vector2) -> Rect2:
	var br := board_rect(size)
	var m := board_margin * unit
	var top := board_line * unit * 0.5
	return Rect2(br.position + Vector2(m, top), br.size - Vector2(m * 2.0, top + m))


func _content(size: Vector2) -> Rect2:
	return content if content.size.x > 0.0 else Rect2(Vector2.ZERO, size)


## How much the game's layout is scaled to fit the sheet (uniform, so the diagram is honest).
func page_fit(size: Vector2) -> float:
	var sh := sheet_rect(size)
	var ct := _content(size)
	return minf(sh.size.x / ct.size.x, sh.size.y / ct.size.y)


## Where the game's content lands on the sheet, before the tilt.
func page_rect(size: Vector2) -> Rect2:
	var sh := sheet_rect(size)
	var sz := _content(size).size * page_fit(size)
	return Rect2(sh.get_center() - sz * 0.5, sz)


## The clipboard's tilt, about the canvas's middle.
func board_transform(size: Vector2) -> Transform2D:
	var ctr := size * 0.5
	return Transform2D().translated(ctr) * Transform2D(deg_to_rad(tilt_deg), Vector2.ZERO) * Transform2D().translated(-ctr)


## The game's layout -> the sheet as it lies on the tilted clipboard.
func page_transform(size: Vector2) -> Transform2D:
	var ct := _content(size)
	var pr := page_rect(size)
	return board_transform(size) * Transform2D().translated(pr.get_center()) \
		* Transform2D().scaled(Vector2.ONE * page_fit(size)) * Transform2D().translated(-ct.get_center())


## Corners of a rounded rectangle, for filled and outlined shapes.
static func rounded(r: Rect2, radius: float, seg := 5) -> PackedVector2Array:
	var out := PackedVector2Array()
	var rad := minf(radius, minf(r.size.x, r.size.y) * 0.5)
	var centres := [Vector2(r.end.x - rad, r.position.y + rad), Vector2(r.end.x - rad, r.end.y - rad),
		Vector2(r.position.x + rad, r.end.y - rad), Vector2(r.position.x + rad, r.position.y + rad)]
	for ci in 4:
		var start := -PI * 0.5 + PI * 0.5 * float(ci)
		for i in seg + 1:
			var ang := start + PI * 0.5 * float(i) / float(seg)
			out.append((centres[ci] as Vector2) + Vector2(cos(ang), sin(ang)) * rad)
	return out


## The board and the sheet; everything drawn until end_page() lands on the sheet, in the game's own
## layout coordinates. `shake` nudges the whole clipboard (canvas px) for a serious mistake.
func begin_page(c: CanvasItem, size: Vector2, shake := Vector2.ZERO) -> void:
	var bx := Transform2D().translated(shake) * board_transform(size)
	c.draw_set_transform_matrix(bx)
	var br := board_rect(size)
	var shape_pts := rounded(br, board_radius * unit)
	c.draw_colored_polygon(shape_pts, board)
	# A little tooth on the hardboard, so it is board and not a flat brown slab.
	halftone_poly(c, shape_pts, 0.14, Color(ink, 1.0))
	var sh := sheet_rect(size)
	c.draw_rect(sh, paper)
	c.draw_set_transform_matrix(Transform2D().translated(shake) * page_transform(size))


## The outlines, the bevel and the clip; then back to plain drawing. `title` is stamped on the clip,
## `corner` (the table) goes small in ink on the board's bottom edge.
func end_page(c: CanvasItem, size: Vector2, title := "", corner := "", shake := Vector2.ZERO) -> void:
	var bx := Transform2D().translated(shake) * board_transform(size)
	c.draw_set_transform_matrix(bx)
	var br := board_rect(size)
	var sh := sheet_rect(size)
	line(c, PackedVector2Array([sh.position, Vector2(sh.end.x, sh.position.y), sh.end, Vector2(sh.position.x, sh.end.y)]),
		ink, border, 9001, true)
	c.draw_polyline(rounded(br.grow(-bevel_in * unit), maxf(1.0, (board_radius - bevel_in) * unit)), Color(ink, bevel_alpha), bevel_line * unit)
	line(c, rounded(br, board_radius * unit), ink, board_line, 9002, true)
	if corner != "":
		text(c, Vector2(br.end.x - 18.0 * unit, br.end.y - 3.5 * unit), corner, 9.0, Color(ink, 0.85), 2)
	_clip(c, br, title)
	c.draw_set_transform_matrix(Transform2D.IDENTITY)


## The steel spring clip over the sheet's top: its shadow on the page, the dark hinge bar across the
## page below it, the thumb loop arching above, the body with an inset shadow along its bottom, and the
## step's name stamped on it.
func _clip(c: CanvasItem, br: Rect2, title: String) -> void:
	var w := clip_size.x * unit
	var h := clip_size.y * unit
	var cx := br.get_center().x
	var body := Rect2(Vector2(cx - w * 0.5, br.position.y - clip_above * unit), Vector2(w, h))
	var lw := loop_size.x * unit
	var lh := loop_size.y * unit
	var loop_pts := PackedVector2Array()
	for i in 13:
		var ang := PI + PI * float(i) / 12.0
		loop_pts.append(Vector2(cx, body.position.y + 2.0 * unit) + Vector2(cos(ang) * lw * 0.5, sin(ang) * lh))
	var body_pts := rounded(body, 7.0 * unit, 3)
	# Only the clip casts a shadow.
	var so := clip_shadow_offset * unit
	var shadow_body := PackedVector2Array()
	for q in body_pts:
		shadow_body.append(q + so)
	c.draw_colored_polygon(shadow_body, clip_shadow)
	# The hinge bar, dark, across the page just under the body.
	var hinge := Rect2(Vector2(body.position.x + 8.0 * unit, body.end.y - 2.0 * unit), Vector2(w - 16.0 * unit, 7.0 * unit))
	c.draw_rect(hinge, clip_hinge)
	line(c, PackedVector2Array([hinge.position, Vector2(hinge.end.x, hinge.position.y), hinge.end, Vector2(hinge.position.x, hinge.end.y)]),
		ink, detail, 9105, true)
	# The thumb loop.
	line(c, loop_pts, Color(ink, 1.0), outline + 3.0, 9106)
	line(c, loop_pts, clip_loop, outline, 9107)
	# The body, with an inset shadow along its bottom.
	c.draw_colored_polygon(body_pts, clip_body)
	c.draw_rect(Rect2(Vector2(body.position.x + 6.0 * unit, body.end.y - 12.0 * unit), Vector2(w - 12.0 * unit, 8.0 * unit)),
		Color(clip_hinge, 0.35))
	line(c, body_pts, ink, outline, 9102, true)
	for sx: float in [-1.0, 1.0]:
		circle(c, Vector2(cx + sx * (w * 0.5 - 14.0 * unit), body.position.y + 14.0 * unit), 3.5 * unit, ink, detail, 9103 + int(sx), clip_hinge)
	if title != "":
		var f := font_upright()
		var px := int(round(20.0 * unit))
		var tw := f.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
		c.draw_string(f, Vector2(cx - tw * 0.5, body.get_center().y + px * 0.2), title, HORIZONTAL_ALIGNMENT_LEFT, -1.0, px, ink)
		ops += 1


## Canvas pixels as they land on the sheet -> the game's own layout. For input.
func unpage(p: Vector2, size: Vector2) -> Vector2:
	return page_transform(size).affine_inverse() * p


## The game's layout -> where it lands on the sheet (for a bot aiming in the game's layout).
func onpage(p: Vector2, size: Vector2) -> Vector2:
	return page_transform(size) * p


# ---------------------------------------------------------------------------- type

## An italic serif for in-panel labels (Lora if the machine has it, then the usual serifs).
static func font() -> Font:
	if _font == null:
		var sf := SystemFont.new()
		# Lora (the spec's body face) when it is there; Georgia is the nearest face Windows ships.
		sf.font_names = PackedStringArray(["Lora", "Georgia", "Cambria", "Times New Roman", "DejaVu Serif", "serif"])
		sf.font_italic = true
		sf.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
		_font = sf
	return _font


## Upright, heavy, for stamps and command cards.
static func font_upright() -> Font:
	if _font_up == null:
		var sf := SystemFont.new()
		# Cormorant Garamond (the spec's display face) when it is there; Palatino / Book Antiqua are the
		# nearest faces Windows ships.
		sf.font_names = PackedStringArray(["Cormorant Garamond", "Cormorant", "Palatino Linotype", "Book Antiqua", "Georgia", "serif"])
		sf.font_weight = 600
		sf.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
		_font_up = sf
	return _font_up


## A label. `size` is reference px; `align` 0 left, 1 centre, 2 right of `at`.
func text(c: CanvasItem, at: Vector2, s: String, size: float, col := Color(-1, 0, 0), align := 0) -> void:
	var f := font()
	var px := int(round(size * unit))
	var cc: Color = label if col.r < 0.0 else col
	var w := f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
	var x := at.x - (w * 0.5 if align == 1 else (w if align == 2 else 0.0))
	c.draw_string(f, Vector2(x, at.y), s, HORIZONTAL_ALIGNMENT_LEFT, -1.0, px, cc)
	ops += 1


## The command card, in ink: a paper strip with heavy rules across the page and the word stamped on
## it, turned a few degrees. `k` 0..1 is how far through the card is (for the pop), `sub` a small line
## under it (READY's countdown). Replaces the teal card for a game on the ink look.
func card(c: CanvasItem, size: Vector2, word: String, k: float, big: int, col := Color(-1, 0, 0), sub := "") -> void:
	# Across the paper only: past it is the board and then the room.
	var pr := page_rect(size)
	var band_h := pr.size.y * 0.32
	var y0 := pr.get_center().y - band_h * 0.5
	var x0 := pr.position.x
	var x1 := pr.end.x
	c.draw_rect(Rect2(Vector2(x0, y0), Vector2(x1 - x0, band_h)), Color(paper, 0.93))
	line(c, PackedVector2Array([Vector2(x0, y0), Vector2(x1, y0)]), ink, heavy, 7101)
	line(c, PackedVector2Array([Vector2(x0, y0 + band_h), Vector2(x1, y0 + band_h)]), ink, heavy, 7102)
	var pop: float = 1.0 - pow(1.0 - clampf((1.0 - k) * 6.0, 0.0, 1.0), 3.0)
	var px := int(round(big * lerpf(0.82, 1.0, pop)))
	var f := font_upright()
	var w := f.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
	var cc: Color = ink if col.r < 0.0 else col
	c.draw_set_transform(pr.get_center(), deg_to_rad(-6.0), Vector2.ONE)
	# The stamp's double border.
	var box := Rect2(Vector2(-w * 0.5 - 28.0, -px * 0.62), Vector2(w + 56.0, px * 1.05))
	rect(c, box, Color(cc, 0.9), 3.5, 7103)
	rect(c, box.grow(-9.0), Color(cc, 0.7), 1.8, 7104)
	c.draw_string(f, Vector2(-w * 0.5, px * 0.3), word, HORIZONTAL_ALIGNMENT_LEFT, -1.0, px, cc)
	if sub != "":
		var fs := int(round(26.0 * unit))
		var sw := font().get_string_size(sub, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		c.draw_string(font(), Vector2(-sw * 0.5, px * 0.3 + 40.0), sub, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs, label)
	c.draw_set_transform_matrix(Transform2D.IDENTITY)


## Warmup: draw one of everything once, so the fonts rasterise and nothing hitches on first use.
func warm(c: CanvasItem) -> void:
	text(c, Vector2(-100, -100), "0123456789 mL % abcdefghijklmnopqrstuvwxyz ABCDEFGHIJKLMNOPQRSTUVWXYZ", 14.0)
	var f := font_upright()
	c.draw_string(f, Vector2(-100, -100), "READY DRAW! FLICK! STICK! PUSH! 0123456789.", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 110, ink)
