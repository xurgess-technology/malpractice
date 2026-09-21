extends Resource
## PANEL TESTBED (docs/PANEL_STYLE.md): the look of every surgery panel, in one file.
##
## A panel is an openly 2D diagram -- X-ray board, not skin. Flat shapes, 2-3 px outlines, soft
## glow, no textures and no attempt to blend with the body. Readability beats atmosphere: there
## are no scanlines, no noise and no grime here on purpose.
##
## Every colour and weight a panel game draws with comes from here, so restyling the whole
## presentation is one file. Sizes are in PIXELS of the panel's SubViewport; a game works in
## diagram millimetres and converts through SurgeryPanel.px_per_mm().

# -- surface ------------------------------------------------------------------------------------
## Near-black desaturated teal.
@export var bg := Color(0.042, 0.081, 0.086)
## A shade lighter, under the frame, so the panel reads as a lit plate and not a hole.
@export var bg_inner := Color(0.058, 0.105, 0.111)
@export var frame := Color(0.62, 0.93, 0.95)
@export var frame_width := 3.0
@export var frame_inset := 10.0
@export var frame_radius := 14.0

# -- palette ------------------------------------------------------------------------------------
## Pale cyan / off-white: every outline and every neutral mark.
@export var line := Color(0.84, 0.95, 0.95)
## The same, backed off: unused targets, grid, dead weight.
@export var line_dim := Color(0.36, 0.53, 0.56)
## Danger and blood.
@export var danger := Color(0.91, 0.24, 0.26)
## Inside the wound: dark, so the bright outline is what the eye lands on.
@export var blood_dark := Color(0.29, 0.045, 0.072)
## Blood pooling on the panel.
@export var blood := Color(0.40, 0.035, 0.055)
## Good work.
@export var good := Color(0.38, 0.93, 0.55)
## Work that holds but is untidy.
@export var sloppy := Color(0.93, 0.72, 0.26)
## Thread.
@export var thread := Color(0.98, 0.95, 0.86)
## Steel: the needle and the driver.
@export var steel := Color(0.74, 0.84, 0.88)
## Bone: hard and pale, so a cross-section reads as bone and not as a hole.
@export var bone := Color(0.80, 0.80, 0.72)

# -- weights ------------------------------------------------------------------------------------
@export var outline := 3.0
@export var thin := 2.0
@export var hair := 1.0
## Soft glow behind a bright shape: how many passes and how far each one spreads, in pixels.
@export var glow_passes := 3
@export var glow_spread := 3.0
@export var glow_alpha := 0.13

# -- header -------------------------------------------------------------------------------------
@export var header_size := 22
@export var header_color := Color(0.62, 0.93, 0.95, 0.85)
@export var header_dim := Color(0.40, 0.60, 0.63, 0.75)
@export var header_margin := Vector2(34.0, 48.0)

## The light the panel throws on the patient and the operator's hands.
@export var glow_light := Color(0.45, 0.88, 0.95)


## Background, frame and header. Called by SurgeryPanel before the game paints its diagram, so a
## game never draws its own chrome.
func draw_chrome(c: CanvasItem, size: Vector2, header: String, right_text: String, font: Font) -> void:
	c.draw_rect(Rect2(Vector2.ZERO, size), bg)
	var inner := Rect2(Vector2(frame_inset, frame_inset), size - Vector2(frame_inset, frame_inset) * 2.0)
	c.draw_rect(inner, bg_inner)
	glow_rect(c, inner, frame)
	c.draw_rect(inner, frame, false, frame_width)
	# Corner ticks, so the frame reads as an instrument and not a border.
	var t := 26.0
	for corner in [[inner.position, Vector2(1, 1)], [Vector2(inner.end.x, inner.position.y), Vector2(-1, 1)],
			[inner.end, Vector2(-1, -1)], [Vector2(inner.position.x, inner.end.y), Vector2(1, -1)]]:
		var p: Vector2 = corner[0]
		var d: Vector2 = corner[1]
		var o := Vector2(d.x * 9.0, d.y * 9.0)
		c.draw_line(p + o, p + o + Vector2(d.x * t, 0), frame, thin)
		c.draw_line(p + o, p + o + Vector2(0, d.y * t), frame, thin)
	if header != "":
		c.draw_string(font, Vector2(header_margin.x, header_margin.y), header,
			HORIZONTAL_ALIGNMENT_LEFT, -1.0, header_size, header_color)
	if right_text != "":
		# draw_string only right-aligns inside a given width, so give it the whole strip.
		var w := size.x - header_margin.x * 2.0
		c.draw_string(font, Vector2(header_margin.x, header_margin.y), right_text,
			HORIZONTAL_ALIGNMENT_RIGHT, w, header_size, header_dim)


## A soft glow behind a line: the same line again, wider and faint, a few times over.
func glow_line(c: CanvasItem, a: Vector2, b: Vector2, col: Color, width: float) -> void:
	for i in glow_passes:
		var k := float(i + 1)
		c.draw_line(a, b, Color(col, glow_alpha), width + glow_spread * k)


func glow_poly(c: CanvasItem, pts: PackedVector2Array, col: Color, width: float) -> void:
	if pts.size() < 2:
		return
	for i in glow_passes:
		var k := float(i + 1)
		c.draw_polyline(pts, Color(col, glow_alpha), width + glow_spread * k)


func glow_circle(c: CanvasItem, at: Vector2, r: float, col: Color, width: float) -> void:
	for i in glow_passes:
		var k := float(i + 1)
		c.draw_arc(at, r, 0.0, TAU, 20, Color(col, glow_alpha), width + glow_spread * k)


func glow_rect(c: CanvasItem, r: Rect2, col: Color) -> void:
	for i in glow_passes:
		var k := float(i + 1)
		c.draw_rect(r, Color(col, glow_alpha * 0.6), false, frame_width + glow_spread * k)


## A dashed line, for previews.
func dashed(c: CanvasItem, a: Vector2, b: Vector2, col: Color, width: float, dash := 9.0, gap := 7.0) -> void:
	var d := b - a
	var total := d.length()
	if total < 0.001:
		return
	var dir := d / total
	var at := 0.0
	while at < total:
		var to := minf(at + dash, total)
		c.draw_line(a + dir * at, a + dir * to, col, width)
		at = to + gap
