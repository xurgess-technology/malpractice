extends CanvasLayer
## THE SURGICAL ROBOT: what the screen looks like while you are remoted in. Local and cosmetic.
## Faint scanlines, a camera frame, and one line of text saying where you are and how to get out.
## Under the HUD (layer 1; the HUD is 2), so the prompt and the item bar draw over it. While a
## surgery step has the camera, only the corner line stays.

var robot: Node = null
var _on := false
var _slim := false
var _draw_node: Control


func _ready() -> void:
	layer = 1
	_draw_node = Control.new()
	_draw_node.name = "RobotViewDraw"
	_draw_node.set_anchors_preset(Control.PRESET_FULL_RECT)
	_draw_node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_draw_node.draw.connect(_draw_view)
	add_child(_draw_node)
	visible = false


func set_on(on: bool, slim: bool) -> void:
	if on != _on or slim != _slim:
		_on = on
		_slim = slim
		visible = on
	if on:
		_draw_node.queue_redraw()


func _draw_view() -> void:
	if not _on:
		return
	var sz := _draw_node.size
	var font := ThemeDB.fallback_font
	var teal := Color(0.35, 1.0, 0.9, 0.85)
	var t := Time.get_ticks_msec() / 1000.0
	if not _slim:
		# Scanlines and a dark frame.
		var line := Color(0.0, 0.0, 0.0, 0.10)
		var y := 0.0
		while y < sz.y:
			_draw_node.draw_line(Vector2(0, y), Vector2(sz.x, y), line, 1.0)
			y += 3.0
		_draw_node.draw_rect(Rect2(Vector2.ZERO, sz), Color(0.2, 0.9, 0.8, 0.035))
		# Corner brackets.
		var m := 36.0
		var l := 60.0
		for c in [Vector2(m, m), Vector2(sz.x - m, m), Vector2(m, sz.y - m), Vector2(sz.x - m, sz.y - m)]:
			var sx := 1.0 if c.x < sz.x * 0.5 else -1.0
			var sy := 1.0 if c.y < sz.y * 0.5 else -1.0
			_draw_node.draw_line(c, c + Vector2(l * sx, 0), teal, 2.0)
			_draw_node.draw_line(c, c + Vector2(0, l * sy), teal, 2.0)
	# The line: a blinking dot, where you are, how to leave.
	var key := "P"
	if robot != null and robot.has_method("_key_label"):
		key = String(robot._key_label())
	if fmod(t, 1.0) < 0.6:
		_draw_node.draw_circle(Vector2(56, 98), 6.0, Color(1.0, 0.25, 0.2, 0.9))
	_draw_node.draw_string(font, Vector2(70, 104), "REMOTE  ·  SURGICAL ROBOT", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, teal)
	_draw_node.draw_string(font, Vector2(70, 126), "%s / Esc: disconnect.  Your body is where you left it." % key,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(teal, 0.6))
