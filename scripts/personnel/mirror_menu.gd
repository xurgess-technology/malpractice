extends CanvasLayer
## CUSTOMIZATION: the beginnings of a customization menu, at the big mirror in Personnel.
##
## Aim at the mirror and press E: the shift carries on behind you, but the screen fills with your
## own reflection, head to toe, and a pair of arrows beside each thing you can change (scrubs by the
## torso, skin by the head). E or Escape puts you back.
##
## The picture is the mirror's own render (scripts/personnel/mirrors.gd), shown full screen rather
## than on the glass: the mirror already knows how to look through the glass without the wall behind
## it getting in the way, and reusing it means what you see here is exactly what you see walking
## past. While the menu is up, `Mirrors.menu_hold` hands the big mirror over to us so it draws every
## frame from your eyes whatever the render budget would otherwise have decided.
##
## The choice itself lives in scripts/personnel/customization.gd. This file only turns arrow clicks
## into `Customization.cycle`, then hands the packed result to Net (so everyone sees it) and to
## Settings (so it is still yours next shift).

const Customization := preload("res://scripts/personnel/customization.gd")
## Kept in step with Mirrors.MENU_AIM_ID by hand: mirrors.gd builds this menu, so it cannot be
## preloaded from here without a cycle.
const MENU_AIM_ID := "mirror_customize"

## Where we stand you while the menu is up: far enough back that the whole body is in the glass,
## and far enough that the reflection is properly lit.
const STAND_DIST := 1.7
## The rows, top to bottom, as a fraction of the reflection's height: skin by the head, scrubs by
## the torso, patterns below them. An axis with no entry here falls to the bottom of the list.
const ROW_Y := {"skin": 0.40, "outfit": 0.52, "pattern": 0.61, "pattern_colour": 0.69}
## How far out from the middle of the reflection the arrows sit, as a fraction of its width.
const ARROW_X := 0.26
## The glass is a tall room-height slab and the surgeon only fills the middle of it, so the picture
## is blown up and the empty ceiling cropped off the top: `ZOOM` is how much, and `BODY_Y` is where
## the middle of the body sits in the picture, which is what gets centred on screen.
const ZOOM := 1.7
const BODY_Y := 0.57

var game: Node = null
var mirrors: Node = null

var _open := false
var _player: Node = null
var _glass := Vector3.ZERO
var _out := Vector3.FORWARD
var _was_mouse := Input.MOUSE_MODE_CAPTURED
var _rows: Array = []      # [{axis, left: Button, right: Button, label: Label, value: Label}]
var _shot: TextureRect = null
var _dim: ColorRect = null
var _hint: Label = null
var _root: Control = null


func _ready() -> void:
	name = "MirrorMenu"
	layer = 40
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	game = get_tree().get_first_node_in_group("game")
	_build()


func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_dim = ColorRect.new()
	_dim.color = Color(0.02, 0.03, 0.03, 0.92)
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_dim)
	_shot = TextureRect.new()
	_shot.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_shot.stretch_mode = TextureRect.STRETCH_SCALE
	# The glass swaps left and right, and so does this.
	_shot.flip_h = true
	_shot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_shot.clip_contents = true
	_root.add_child(_shot)
	_hint = Label.new()
	_hint.text = "E  or  Esc   —   back to the ward"
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.add_theme_font_size_override("font_size", 20)
	_hint.add_theme_color_override("font_color", Color(0.75, 0.82, 0.80))
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_hint)


## One row of controls per axis. Rebuilt whenever the set of visible axes changes (the pattern
## colour only exists once a pattern does).
func _rebuild_rows(look: Dictionary) -> void:
	for r in _rows:
		(r.holder as Node).queue_free()
	_rows.clear()
	for a in Customization.visible_axes(look):
		var key := String(a.key)
		var holder := Control.new()
		holder.set_anchors_preset(Control.PRESET_FULL_RECT)
		holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_root.add_child(holder)
		var left := _arrow("<")
		var right := _arrow(">")
		holder.add_child(left)
		holder.add_child(right)
		var label := _label(18, Color(0.60, 0.72, 0.70))
		label.text = String(a.label)
		holder.add_child(label)
		var value := _label(26, Color(0.93, 0.97, 0.95))
		holder.add_child(value)
		left.pressed.connect(_cycle.bind(key, -1))
		right.pressed.connect(_cycle.bind(key, 1))
		_rows.append({"axis": key, "holder": holder, "left": left, "right": right,
				"label": label, "value": value})
	_layout()


func _arrow(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(54, 54)
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 30)
	return b


func _label(size: int, col: Color) -> Label:
	var l := Label.new()
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	# The reflection behind them is whatever the room happens to be, so they carry their own outline.
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", 6)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## Put the rows over the reflection: the arrows flank it, the label and value sit between them.
func _layout() -> void:
	var vp := get_viewport().get_visible_rect().size
	var glass := Vector2(1.58, 2.66)
	if mirrors != null and is_instance_valid(mirrors):
		var big: Dictionary = mirrors.big_mirror()
		if not big.is_empty():
			glass = big.size
	# The picture, blown up and shifted so the body's middle lands in the middle of the screen.
	var h := vp.y * ZOOM
	var w: float = h * (glass.x / maxf(glass.y, 0.01))
	var cx := vp.x * 0.5
	var top := vp.y * 0.5 - h * BODY_Y
	_shot.position = Vector2(cx - w * 0.5, top)
	_shot.size = Vector2(w, h)
	_hint.position = Vector2(0, vp.y - 46)
	_hint.size = Vector2(vp.x, 30)
	for i in _rows.size():
		var r: Dictionary = _rows[i]
		var frac: float = float(ROW_Y.get(String(r.axis), 0.61 + 0.08 * i))
		var y := top + h * frac
		var dx := w * ARROW_X
		(r.left as Button).position = Vector2(cx - dx - 27, y - 27)
		(r.right as Button).position = Vector2(cx + dx - 27, y - 27)
		(r.label as Label).position = Vector2(cx - 160, y - 30)
		(r.label as Label).size = Vector2(320, 22)
		(r.value as Label).position = Vector2(cx - 160, y - 8)
		(r.value as Label).size = Vector2(320, 32)


func _refresh_values() -> void:
	if _player == null:
		return
	for r in _rows:
		(r.value as Label).text = Customization.option_name(_player.look, String(r.axis))


# ---------------------------------------------------------------------------

func _process(_delta: float) -> void:
	if game == null or not is_instance_valid(game):
		game = get_tree().get_first_node_in_group("game")
		return
	if not _open:
		_poll_open()
		return
	if not _still_valid():
		close()
		return
	# The mirror draws for us, from the player's eyes, every frame.
	if mirrors != null and is_instance_valid(mirrors):
		mirrors.render_for_menu(_player.head.global_position if _player.head != null
				else _player.global_position + Vector3.UP * C.EYE_H)
	_player.bot_move = Vector2.ZERO
	if Input.is_action_just_pressed("interact") or Input.is_action_just_pressed("ui_cancel"):
		close()


func _still_valid() -> bool:
	return _player != null and is_instance_valid(_player) and _player.alive and not _player.downed \
			and game != null and is_instance_valid(game)


func _poll_open() -> void:
	var p = game.local_player() if game.has_method("local_player") else null
	if p == null or not p.is_local or not p.alive or p.downed:
		return
	if String(p.aim_id) != MENU_AIM_ID:
		return
	if Input.is_action_just_pressed("interact"):
		open(p)



func open(p: Node) -> void:
	if _open:
		return
	mirrors = _find_mirrors()
	if mirrors == null:
		return
	var big: Dictionary = mirrors.big_mirror()
	if big.is_empty():
		return
	var root: Node3D = big.root
	_glass = root.global_position
	_out = root.global_transform.basis.z.normalized()
	_player = p
	_open = true
	visible = true
	# Stand back far enough to be in the glass head to toe, square on and facing it.
	var feet := _glass + _out * STAND_DIST
	feet.y = _glass.y - 1.49
	if game.has_method("_floor_at"):
		feet = game._floor_at(feet + Vector3.UP)
	p.teleport(feet)
	var yaw := atan2(_out.x, _out.z)
	p._yaw = yaw
	p.rotation.y = yaw
	p._pitch = 0.0
	if p.head != null:
		p.head.rotation.x = 0.0
	# The surgeon stands still on his own while the mouse is free: player.gd works `can_move` out
	# from the mouse mode every frame, so letting the cursor go is all the freezing we need.
	_was_mouse = Input.get_mouse_mode()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	mirrors.menu_hold = true
	var big2: Dictionary = mirrors.big_mirror()
	_shot.texture = (big2.viewport as SubViewport).get_texture()
	_rebuild_rows(p.look)
	_refresh_values()


func close() -> void:
	if not _open:
		return
	_open = false
	visible = false
	if mirrors != null and is_instance_valid(mirrors):
		mirrors.menu_hold = false
	Input.set_mouse_mode(_was_mouse)
	_player = null


func _cycle(key: String, by: int) -> void:
	if _player == null or not is_instance_valid(_player):
		return
	var before := Customization.visible_axes(_player.look).size()
	var next := Customization.cycle(_player.look, key, by)
	_player.set_look_packed(Customization.pack(next))
	# Everyone else, then the save file.
	Net.set_my_look(Customization.pack(_player.look))
	Settings.set_value("look", Customization.pack(_player.look))
	if Customization.visible_axes(_player.look).size() != before:
		_rebuild_rows(_player.look)
	_refresh_values()


func _find_mirrors() -> Node:
	var lvl = game.get("level") if game != null else null
	if lvl != null and is_instance_valid(lvl):
		var n = lvl.find_child("Mirrors", true, false)
		if n != null:
			return n
	return game.find_child("Mirrors", true, false) if game != null else null


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_SIZE_CHANGED and _open:
		_layout()
