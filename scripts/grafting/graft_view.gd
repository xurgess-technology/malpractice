extends CanvasLayer
## GRAFTING (docs/GRAFTING.md chunk C, docs/GRAFTING_TRACHEA.md): the first-person tells. A surgeon
## with a Hive eye sees a faint orange wash down the LEFT edge of their view -- the side the eyeball
## is on -- which comes up while Hive Eyes is running. A surgeon with a Sonographer's trachea sees a
## faint VIOLET wash along the BOTTOM edge, under their own chin, which comes up while Echo fires.
## A surgeon wearing both sees both.
##
## It sits ABOVE the look pass's grain, vignette and teal grade (scripts/look.gd, canvas layer 50),
## which the HUD deliberately sits under: graded, a faint orange on a teal picture disappears
## completely. Local and cosmetic; what drives it (game.grafts.local_lock) is replicated, so it can
## never disagree with the glow everyone else sees on the eye.

const LAYER := 52

var wash: Control = null      # the eye's, kept as `wash` because the tests reach for it
var throat_wash: Control = null


## The wash itself. Its own constants: an inner class cannot see the outer script's when the script
## has no class_name (CLAUDE.md).
class Wash extends Control:
	const BANDS := 8
	## How far across the screen it reaches, at rest and while the ability runs.
	const WIDTH := Vector2(0.20, 0.30)
	## Total alpha at the very edge, at rest and while the ability runs.
	const ALPHA := Vector2(0.22, 0.6)
	## The throat's is a little narrower and a little stronger: it is under your chin, not beside
	## your eye, so it has less room and has to read anyway.
	const THROAT_WIDTH := Vector2(0.13, 0.22)
	const THROAT_ALPHA := Vector2(0.20, 0.7)

	var game: Node = null
	var site := "eye"
	var t := 0.0
	## Tests: true while the last frame drew anything.
	var showing := false

	func tint() -> Color:
		return Color(0.61, 0.42, 1.0) if site == "throat" else Color(1.0, 0.33, 0.05)

	func _process(delta: float) -> void:
		t += delta
		queue_redraw()

	func _draw() -> void:
		showing = false
		if game == null or game.grafts == null or bool(game.paused):
			return
		if int(game.phase) == 0:   # Game.Phase.MENU
			return
		var lock: float = float(game.grafts.local_lock(site))
		if lock < 0.0:
			return   # no graft at this site: nothing to see
		var k := clampf(lock, 0.0, 1.0)
		var col := tint()
		var throat := site == "throat"
		var a: float = lerpf(THROAT_ALPHA.x if throat else ALPHA.x, THROAT_ALPHA.y if throat else ALPHA.y, k) * (0.9 + 0.1 * sin(t * 2.1))
		# Soft bands: strongest and narrowest at the edge, fading out across.
		for i in BANDS:
			var f := float(i + 1) / float(BANDS)
			if throat:
				var deep: float = size.y * lerpf(THROAT_WIDTH.x, THROAT_WIDTH.y, k) * f
				draw_rect(Rect2(0.0, size.y - deep, size.x, deep), Color(col.r, col.g, col.b, a / float(BANDS)))
			else:
				var wide: float = size.x * lerpf(WIDTH.x, WIDTH.y, k) * f
				draw_rect(Rect2(0.0, 0.0, wide, size.y), Color(col.r, col.g, col.b, a / float(BANDS)))
		showing = true


static func create(game: Node) -> CanvasLayer:
	var l: CanvasLayer = (load("res://scripts/grafting/graft_view.gd") as GDScript).new()
	l.name = "GraftView"
	l.layer = LAYER
	for site in ["eye", "throat"]:
		var w := Wash.new()
		w.name = "Wash" if site == "eye" else "ThroatWash"
		w.game = game
		w.site = site
		w.mouse_filter = Control.MOUSE_FILTER_IGNORE
		w.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		l.add_child(w)
		if site == "eye":
			l.wash = w
		else:
			l.throat_wash = w
	return l
