extends CanvasLayer
## CUSTOMIZATION: the customization menu, at the big mirror in Personnel.
##
## Aim at the mirror and press E: the shift carries on behind you, the game hands you an ordinary
## third-person camera standing where the glass is and looking back at you, and a pair of arrows
## beside each thing you can change (scrubs by the torso, skin by the head). E or Escape puts you
## back.
##
## PLAYTEST 2026-09-23 (camera rework): this used to reuse mirrors.gd's glass-frustum SubViewport
## -- an off-axis camera fitted exactly to the physical mirror's rectangle -- and stretch that
## picture full screen. That frustum was sized to fit a pane of glass, not an arbitrary monitor's
## aspect ratio, which is why it always left the dark backdrop showing down both sides on a normal
## widescreen (the reported "black bars"). It also never actually gave you a real camera: aiming
## anywhere but dead centre skewed the off-axis frustum rather than turning your head.
## Fix: `_cam` below is a real `Camera3D`, planted where the glass is and handed to
## `game.mirror_camera()` -> main.gd's per-frame camera arbitration (the same chain
## `surgery_camera()`/Puppet already use, main.gd ~line 711) via `camera.current`-style
## takeover, `Camera3D.make_current()`. A real camera on the ordinary viewport always matches
## the screen's actual aspect ratio and FOV, so there is nothing left to stretch or letterbox.
## `Player.set_mirror_self` (already built for the old glass reflection) puts the local body on
## show for it, exactly the way `carry_camera.gd`'s `_carry_body` flag does for the over-the-
## shoulder rig -- both are "a local camera that needs to see the local player's own model".
## mirrors.gd's own SubViewport/reflection system is untouched and still serves the ordinary
## walk-by mirror; this file no longer draws through it at all. It still sets `Mirrors.menu_hold`
## while open, though, for a narrower reason than before: mirrors.gd's own walk-by loop calls
## `Player.set_mirror_self` every frame from whatever camera is current, and once this menu's camera
## is current that loop can no longer see its own glass (the camera stands right in front of it,
## facing away) and would call `set_mirror_self(false)` right under us, fighting this file's own
## call to `true`. `menu_hold` just tells that loop to stand aside while this menu owns the flag.
##
## Movement: `player.gd` already ties `can_move` to `Input.mouse_mode == MOUSE_MODE_CAPTURED`
## everywhere movement, jumping, sprinting, crouching, interacting and every weapon/item action are
## read, so freeing the mouse is the whole freeze -- see that file's `_local_step`. What actually
## used to leak the mouse back to captured mid-menu was main.gd's own `_update_mouse()`, the single
## place that arbitrates mouse mode every frame: it didn't know about this menu, so it fought this
## file's own `Input.set_mouse_mode` call back to captured within a frame or two. Fixed by adding
## `game.mirror_menu_open()` to that arbitration instead of setting the mode here at all -- "one
## place decides the mouse" (main.gd's own comment), now actually true for this menu too.
##
## Mirror lock: opening used to be purely local, so nothing told a second player -- or the host --
## that the mirror was taken. `Net.claim_mirror()`/`release_mirror()` (net.gd) add a single
## host-authoritative flag (there is only one big mirror per level: mirrors.gd's `_add_menu_aim`
## runs once, for the level's one "mirror" spot), replicated the same way `Net.set_my_look` already
## replicates a look: a client asks, the host decides and tells everyone. `mirror_aim.gd`'s
## `interact_prompt` reads it and returns the "!"-prefixed prompt idiom already used elsewhere
## (combat.gd's `strap_problem`, game.gd's "!The table is taken.") when somebody else holds it.
##
## The choice itself lives in scripts/personnel/customization.gd. This file only turns arrow clicks
## into `Customization.cycle`, then hands the packed result to Net (so everyone sees it) and to
## Settings (so it is still yours next shift).

const Customization := preload("res://scripts/personnel/customization.gd")
const LightRooms := preload("res://scripts/level/light_rooms.gd")
## Kept in step with Mirrors.MENU_AIM_ID by hand: mirrors.gd builds this menu, so it cannot be
## preloaded from here without a cycle.
const MENU_AIM_ID := "mirror_customize"

## Where we stand the surgeon: this far out from the glass, facing it, square on. It used to also
## be where the old glass-frustum reflection first read as lit rather than a black silhouette; the
## mirrors have their own bulbs now (mirrors.gd `_add_lamp`), so this is a framing choice only.
const STAND_DIST := 1.7
## The camera sits this far out from the glass along the same axis -- between the glass and the
## player, "roughly where the glass is" -- so it's a real camera standing (almost) in the mirror's
## place rather than a picture painted on it. Kept short of the glass itself so it never clips into
## the frame or the wall behind it.
const CAM_FRONT := 0.15
## The camera's height off the floor, and how far below that it looks (so it tips down to a
## flattering chest-height aim rather than staring level into the surgeon's collarbone). Both are a
## framing/feel choice -- change these and CAM_FOV together to reframe the shot.
const CAM_HEIGHT := 1.55
const CAM_LOOK_DROP := 0.48
## Vertical FOV (Camera3D's default KEEP_HEIGHT, so a wider monitor shows more width instead of
## more top-and-bottom -- this is what actually answers "no black bars", not the aspect maths the
## old glass frustum was doing). Tuned, at CAM_HEIGHT/CAM_FRONT/STAND_DIST above, to fit a surgeon
## head to toe with a little headroom and legroom to spare.
const CAM_FOV := 75.0
## The rows, top to bottom, as a fraction of the screen height: skin by the head, scrubs by the
## torso, patterns below them. An axis with no entry here falls to the bottom of the list. Carried
## over from the old glass-picture framing, which put the body in roughly the same place on screen;
## nudge these if the real camera above doesn't land exactly there.
const ROW_Y := {"skin": 0.40, "outfit": 0.52, "pattern": 0.61, "pattern_colour": 0.69}
## How far out from the middle of the screen the arrows sit, as a fraction of its width.
const ARROW_X := 0.26

var game: Node = null
var mirrors: Node = null

var _open := false
var _player: Node = null
## A local player who pressed E and is waiting for Net to confirm the mirror is theirs (host-
## authoritative: see the file header). Cleared either by the confirmation opening the menu, or by
## somebody else getting there first.
var _pending: Node = null
var _glass := Vector3.ZERO
var _out := Vector3.FORWARD
var _cam: Camera3D = null
var _rows: Array = []      # [{axis, left: Button, right: Button, label: Label, value: Label}]
var _hint: Label = null
var _root: Control = null


func _ready() -> void:
	name = "MirrorMenu"
	layer = 40
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	game = get_tree().get_first_node_in_group("game")
	_build()
	Net.mirror_user_changed.connect(_on_mirror_user_changed)


func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_hint = Label.new()
	_hint.text = "E  or  Esc   —   back to the ward"
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.add_theme_font_size_override("font_size", 20)
	_hint.add_theme_color_override("font_color", Color(0.75, 0.82, 0.80))
	_hint.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_hint.add_theme_constant_override("outline_size", 6)
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_hint)
	_cam = Camera3D.new()
	_cam.name = "MirrorMenuCamera"
	_cam.near = 0.05
	_cam.far = 60.0
	_cam.current = false
	add_child(_cam)


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
	# Point-and-click with a free cursor (ask 2): Button defaults to MOUSE_FILTER_STOP, so it takes
	# the click even though the row `holder` Controls around it are MOUSE_FILTER_IGNORE on purpose
	# (so they don't block the view of yourself between the arrows). Set explicitly rather than
	# trusted, since a stray default change elsewhere would otherwise make every arrow unclickable.
	b.mouse_filter = Control.MOUSE_FILTER_STOP
	return b


func _label(size: int, col: Color) -> Label:
	var l := Label.new()
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	# What's behind them is the real room now, not a fixed backdrop, so they carry their own outline
	# rather than a dimmer behind the whole screen (which would defeat "no black bars": ask 5 wants
	# to actually see the reflection, not a mostly-dark screen with a picture floating on it).
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", 6)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## Put the rows over the reflection: the arrows flank it, the label and value sit between them.
func _layout() -> void:
	var vp := get_viewport().get_visible_rect().size
	_hint.position = Vector2(0, vp.y - 46)
	_hint.size = Vector2(vp.x, 30)
	var cx := vp.x * 0.5
	for i in _rows.size():
		var r: Dictionary = _rows[i]
		var frac: float = float(ROW_Y.get(String(r.axis), 0.61 + 0.08 * i))
		var y := vp.y * frac
		var dx := vp.x * ARROW_X
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
	_player.bot_move = Vector2.ZERO
	if Input.is_action_just_pressed("interact") or Input.is_action_just_pressed("ui_cancel"):
		close()


func _still_valid() -> bool:
	return _player != null and is_instance_valid(_player) and _player.alive and not _player.downed \
			and game != null and is_instance_valid(game)


func _poll_open() -> void:
	if _pending != null and (not is_instance_valid(_pending) or not _pending.alive or _pending.downed):
		_pending = null   # gave up waiting on the host (died, disconnected, whatever)
	if _pending != null:
		return   # already asked Net; wait for _on_mirror_user_changed
	var p = game.local_player() if game.has_method("local_player") else null
	if p == null or not p.is_local or not p.alive or p.downed:
		return
	if String(p.aim_id) != MENU_AIM_ID:
		return
	# Mirror lock (ask 4): mirror_aim.gd's prompt is the "!"-prefixed refusal idiom once somebody
	# else is at the mirror (combat.gd's strap_problem, game.gd's "!The table is taken."); the E
	# press that opens the menu has to respect it the same way player.gd's own generic interact
	# handling already skips a "!" prompt.
	if String(p.aim_prompt).begins_with("!"):
		return
	if Input.is_action_just_pressed("interact"):
		_pending = p
		Net.claim_mirror()   # host resolves at once; a client waits for the signal below


## Host-authoritative mirror lock: Net decided who (if anyone) holds the mirror now.
func _on_mirror_user_changed() -> void:
	if _pending == null:
		return
	var p := _pending
	if Net.mirror_user == p.peer_id:
		_pending = null
		_do_open(p)
	elif Net.mirror_user != 0:
		_pending = null   # somebody else got there first


func _do_open(p: Node) -> void:
	if _open:
		return
	mirrors = _find_mirrors()
	if mirrors == null:
		Net.release_mirror()
		return
	var big: Dictionary = mirrors.big_mirror()
	if big.is_empty():
		Net.release_mirror()
		return
	var root: Node3D = big.root
	_glass = root.global_position
	_out = root.global_transform.basis.z.normalized()
	_player = p
	_open = true
	visible = true
	# Stand back far enough to be in frame head to toe, square on and facing the glass.
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
	# CUSTOMIZATION (camera rework): a real third-person camera, standing roughly where the glass
	# is and looking back at the player -- see the file header for why this replaced the old
	# glass-frustum SubViewport picture. Set once: the player can't move while the menu is up
	# (can_move gates on the mouse, which main.gd now frees for as long as this menu is open; see
	# game.mirror_menu_open()), so there's nothing to re-aim frame to frame.
	var cam_pos := _glass + _out * CAM_FRONT
	cam_pos.y = feet.y + CAM_HEIGHT
	var look_at := Vector3(feet.x, feet.y + CAM_HEIGHT - CAM_LOOK_DROP, feet.z)
	_cam.global_transform = Transform3D(Basis.looking_at(look_at - cam_pos, Vector3.UP), cam_pos)
	_cam.fov = CAM_FOV
	# Same cull mask the mirror cameras use (mirrors.gd _render): the local body only shows on a
	# camera that asks for it (LightRooms.SELF, via Player.set_mirror_self below), and first-person
	# hands / the dev gun's first-person model (bits 18 and 17) have no business floating in a
	# third-person shot of yourself.
	_cam.cull_mask = (p.camera.cull_mask & ~((1 << 18) | (1 << 17))) | LightRooms.SELF
	# `current` is not set here: main.gd's per-frame camera arbitration (~line 711, reading
	# game.mirror_camera()) is what calls `make_current()`, the same as surgery_camera()/Puppet
	# -- it's the one place that knows how to hand the viewport's current camera back afterwards.
	# Hand mirrors.gd's own walk-by loop the wheel (see the file header for why) and show the local
	# body to this camera, the same flag mirrors.gd's own reflection cameras use (and the same idea
	# as carry_camera.gd's `_carry_body`: a local camera that needs to see the local player's own
	# model).
	mirrors.menu_hold = true
	if p.has_method("set_mirror_self"):
		p.set_mirror_self(true)
	_rebuild_rows(p.look)
	_refresh_values()


func close() -> void:
	if not _open:
		return
	_open = false
	visible = false
	_cam.current = false
	if _player != null and is_instance_valid(_player) and _player.has_method("set_mirror_self"):
		_player.set_mirror_self(false)
	if mirrors != null and is_instance_valid(mirrors):
		mirrors.menu_hold = false
	Net.release_mirror()
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


## The camera main.gd's per-frame camera arbitration should be showing right now (game.gd's
## mirror_camera(), read by main.gd exactly like surgery_camera()/Puppet).
func active_camera() -> Camera3D:
	return _cam if _open else null


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
