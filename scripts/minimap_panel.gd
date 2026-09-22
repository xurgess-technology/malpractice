class_name MinimapPanel
extends Control
## The small minimap, top right of the HUD. A north-up, player-centred floor plan of St. Doe's,
## inked on dark paper, with the wards blank until the party has walked them (scripts/minimap.gd
## owns the fog; this only draws it).
##
## THREE LAYERS, SO THE EXPENSIVE ONE ALMOST NEVER RUNS. Godot keeps a Control's draw commands until
## something calls queue_redraw, and moving a Control re-transforms them without redrawing. So:
##   this   the paper (the fog itself). Redrawn only when the panel resizes.
##   _map   the explored floor, its walls and its doors. Redrawn only when the player crosses a tile
##          or the fog changes -- about three times a second while walking, never while standing
##          still. It is a tile wider than the panel on every side and its POSITION carries the
##          sub-tile offset, so the map slides smoothly at no redraw cost.
##   _over  the frame, the zone label, teammates and your own arrow. Every frame, about a dozen
##          draw calls.
## Nothing here computes geometry per frame: the tile arrays are baked once per shift by Minimap.

const MM = preload("res://scripts/minimap.gd")

const SIDE := 152.0        # the panel, square
const MARGIN := 16.0       # from the top right corner of the screen
const SCALE := 4.5         # screen pixels per 1.5 m tile: the panel shows about 50 m across

const PAPER := Color(0.043, 0.051, 0.063, 0.74)     # unexplored: the fog is just blank paper
const FRAME := Color("f0e6c8", 0.55)
const OUTDOOR := Color(0.36, 0.40, 0.38, 0.22)      # the lot outside, faint context
const CORRIDOR := Color(0.72, 0.69, 0.58, 0.20)
const ROOM := Color(0.80, 0.76, 0.62, 0.30)
const DOORWAY := Color("5ce0d0", 0.62)
const WALL := Color("f0e6c8", 0.62)
const ARROW := Color("f6efd4")
const MATE := Color("5ce0d0")

var game: Node = null
## The tile the panel is centred on, and how far past it the player is (0..1 per axis).
var centre_tile := Vector2i(0, 0)

var _map: Control = null
var _over: Control = null
var _revision := -1
var _centre := Vector2i(-99999, -99999)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	anchor_left = 1.0
	anchor_right = 1.0
	anchor_top = 0.0
	anchor_bottom = 0.0
	offset_left = -(SIDE + MARGIN)
	offset_right = -MARGIN
	offset_top = MARGIN
	offset_bottom = MARGIN + SIDE
	_map = MapLayer.new()
	_map.panel = self
	_map.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_map)
	_over = OverLayer.new()
	_over.panel = self
	_over.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_over.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_over)
	resized.connect(_on_resized)
	_on_resized()


func _on_resized() -> void:
	if _map != null:
		_map.size = size + Vector2(SCALE, SCALE) * 2.0
		_map.queue_redraw()
	queue_redraw()


func minimap() -> Node:
	return game.minimap if game != null else null


func _process(_delta: float) -> void:
	var mm := minimap()
	var me = game.driving_player() if game != null else null
	var busy: bool = game != null and game.wing_loader != null and bool(game.wing_loader.busy)
	var showing: bool = mm != null and mm.has_map() and me != null and bool(me.alive) and not busy \
			and game.phase != Game.Phase.MENU and game.surgery_camera() == null
	if showing != visible:
		visible = showing
	if not showing:
		return
	# Where the map sits: the tile under the player, plus the fraction of a tile past it carried by
	# the layer's position so walking slides rather than steps.
	var p: Vector3 = me.global_position
	var tx: float = p.x / C.TILE
	var tz: float = p.z / C.TILE
	centre_tile = Vector2i(int(floor(tx)), int(floor(tz)))
	var frac := Vector2(tx - floor(tx), tz - floor(tz))
	_map.position = -Vector2(SCALE, SCALE) - frac * SCALE
	if centre_tile != _centre or int(mm.revision) != _revision:
		_centre = centre_tile
		_revision = int(mm.revision)
		_map.queue_redraw()
	_over.queue_redraw()


## The paper the map is inked on: everything not explored yet.
func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), PAPER)


# =========================================================================

## The explored floor plan. Redrawn only on a tile step or a fog change.
class MapLayer:
	extends Control

	var panel: MinimapPanel = null

	func _draw() -> void:
		var mm = panel.minimap()
		if mm == null or not mm.has_map():
			return
		var ct: Vector2i = panel.centre_tile
		var ctr := size * 0.5
		var hx := int(ceil(size.x / (2.0 * MinimapPanel.SCALE))) + 1
		var hy := int(ceil(size.y / (2.0 * MinimapPanel.SCALE))) + 1
		var fills := [MinimapPanel.OUTDOOR, MinimapPanel.CORRIDOR, MinimapPanel.ROOM, MinimapPanel.DOORWAY]
		var walls := PackedVector2Array()
		var s: float = MinimapPanel.SCALE
		var x_from := ct.x - hx
		var x_to := ct.x + hx
		for ty in range(ct.y - hy, ct.y + hy + 1):
			if ty < 0 or ty >= mm.h:
				continue
			var base: int = ty * mm.w
			var y0: float = ctr.y + float(ty - ct.y) * s
			var run_from := 0
			var run_col := -1
			# One past the end so the last run is flushed by the same code as the others.
			for tx in range(x_from, x_to + 2):
				var col := _col_at(mm, base, tx, ty, walls, ctr, ct, s)
				if col != run_col:
					if run_col >= 0:
						draw_rect(Rect2(ctr.x + float(run_from - ct.x) * s, y0, float(tx - run_from) * s, s), fills[run_col])
					run_from = tx
					run_col = col
		if walls.size() >= 2:
			draw_multiline(walls, MinimapPanel.WALL, 1.0)

	## The fill index for a tile (-1 for nothing), collecting its wall edges on the way.
	func _col_at(mm, base: int, tx: int, ty: int, walls: PackedVector2Array, ctr: Vector2, ct: Vector2i, s: float) -> int:
		if tx < 0 or tx >= mm.w:
			return -1
		var i: int = base + tx
		var k: int = mm.kind[i]
		if k == MM.K_NONE or not mm.tile_seen(i):
			return -1
		if k == MM.K_OUTDOOR:
			return 0
		# Indoors: an edge is inked wherever the next tile is not explored floor. The outline grows
		# with the fog, which is what makes a half-walked wing read as half-walked.
		var x0: float = ctr.x + float(tx - ct.x) * s
		var y0: float = ctr.y + float(ty - ct.y) * s
		if not _inside(mm, tx, ty - 1):
			walls.append(Vector2(x0, y0))
			walls.append(Vector2(x0 + s, y0))
		if not _inside(mm, tx, ty + 1):
			walls.append(Vector2(x0, y0 + s))
			walls.append(Vector2(x0 + s, y0 + s))
		if not _inside(mm, tx - 1, ty):
			walls.append(Vector2(x0, y0))
			walls.append(Vector2(x0, y0 + s))
		if not _inside(mm, tx + 1, ty):
			walls.append(Vector2(x0 + s, y0))
			walls.append(Vector2(x0 + s, y0 + s))
		if k == MM.K_DOOR:
			return 3
		return 2 if mm.room_at[i] >= 0 else 1

	## Explored indoor floor (a wall is inked against anything else, the fog included).
	func _inside(mm, tx: int, ty: int) -> bool:
		if tx < 0 or ty < 0 or tx >= mm.w or ty >= mm.h:
			return false
		var i: int = ty * mm.w + tx
		var k: int = mm.kind[i]
		return (k == MM.K_FLOOR or k == MM.K_DOOR) and mm.tile_seen(i)


# =========================================================================

## The frame, the zone label, the team and your own arrow. Cheap enough to run every frame.
class OverLayer:
	extends Control

	var panel: MinimapPanel = null

	func _draw() -> void:
		var game: Node = panel.game
		var mm = panel.minimap()
		if game == null or mm == null:
			return
		var me = game.driving_player()
		if me == null:
			return
		var ctr := size * 0.5
		var s: float = MinimapPanel.SCALE
		# Teammates, so a party that splits up can see who is already in which wing.
		for q in game.players.values():
			if q == null or not is_instance_valid(q) or q == me or not bool(q.alive):
				continue
			var d: Vector3 = q.global_position - me.global_position
			var at := ctr + Vector2(d.x, d.z) / C.TILE * s
			if at.x < 2.0 or at.y < 2.0 or at.x > size.x - 2.0 or at.y > size.y - 2.0:
				continue
			draw_circle(at, 3.0, Color(0, 0, 0, 0.7))
			draw_circle(at, 2.0, MinimapPanel.MATE)
		# You: an arrow at the middle, pointing the way you face.
		var yaw: float = me.rotation.y
		var fwd := Vector2(-sin(yaw), -cos(yaw))
		var side := Vector2(-fwd.y, fwd.x)
		var pts := PackedVector2Array([ctr + fwd * 6.5, ctr - fwd * 4.0 + side * 4.0,
				ctr - fwd * 1.5, ctr - fwd * 4.0 - side * 4.0])
		draw_colored_polygon(pts, Color(0, 0, 0, 0.75))
		var inner := PackedVector2Array()
		for v in pts:
			inner.append(ctr + (v - ctr) * 0.76)
		draw_colored_polygon(inner, MinimapPanel.ARROW)
		# The frame, with corner ticks rather than a plain box.
		draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.8), false, 2.0)
		draw_rect(Rect2(Vector2.ONE, size - Vector2(2, 2)), MinimapPanel.FRAME, false, 1.0)
		for c in [Vector2.ZERO, Vector2(size.x, 0), Vector2(0, size.y), size]:
			var sx := 1.0 if c.x < size.x * 0.5 else -1.0
			var sy := 1.0 if c.y < size.y * 0.5 else -1.0
			draw_line(c + Vector2(sx, sy), c + Vector2(11.0 * sx, sy), MinimapPanel.FRAME, 2.0)
			draw_line(c + Vector2(sx, sy), c + Vector2(sx, 11.0 * sy), MinimapPanel.FRAME, 2.0)
		var label := _label(mm, me)
		if label != "":
			var font := ThemeDB.fallback_font
			draw_rect(Rect2(2, 2, size.x - 4, 15), Color(0, 0, 0, 0.55))
			draw_string(font, Vector2(0, 14), label, HORIZONTAL_ALIGNMENT_CENTER, size.x, 10, MinimapPanel.FRAME)

	## Where you are: the wing's name, or the hospital when you are home.
	func _label(mm, me) -> String:
		var z: String = mm.zone_name_at(me.global_position)
		if z == "" or z == "entrance" or z == "neutral":
			return "ST. DOE'S GENERAL"
		return z.replace("_", " ").to_upper()
