extends CanvasLayer
## TAB SHEET: the character screen, on Tab. Three rows of four -- what is in your hands, what
## abilities you have, and what you are wearing -- over a dimmed view of the shift.
##
## What it is NOT: it does not pause, it does not blind you and it is not a safe place. The world
## keeps running behind it, monsters included; you are stood still with your nose in a chart, which
## is a worse place to be than walking. That is deliberate: a menu you can hide in is a problem in a
## co-op horror game, so this one costs you rather than shelters you.
##
## Look: the HUD's own vocabulary (dark rounded slots, category borders, cream ink text,
## circular ability icons), not the surgery clipboard. The rows show the same objects the HUD's item
## bar and ability bar show, and making them hand-inked here would read as two different games.
## The only chart-ish touches are the ruled header and the St. Doe's caption.
##
## Hover: the mouse is freed while the sheet is up (main.gd `_update_mouse`), so pointing at a slot
## opens a card beside it. An ability's card reads its numbers live off `game.abilities`, so it
## stays true as levels change instead of repeating static text.
##
## Unequipping is host-authoritative: the sheet only bumps `Player.unequip_count`, and
## `Game.player_unequip` decides (scripts/game.gd "TAB SHEET").

const SLOT := 72.0
const GAP := 16.0
## Between the bottom of one row's slots and the top of the next. Big, because a row carries a
## caption under every slot ("Alt+2", "Gloves") and its own heading above it.
const ROW_GAP := 62.0

const PAPER := Color("f0e6c8")
const DIM := Color("8a9aa0")
const SLOT_BG := Color(0.04, 0.05, 0.07)

## The worn row. Only the boots exist; the other three are placeholders so the row reads as a
## shape you will fill in later, which is what "for now" means.
const WORN := [
	{"id": "helm", "label": "Helm"},
	{"id": "boots", "label": "Boots"},
	{"id": "belt", "label": "Belt"},
	{"id": "gloves", "label": "Gloves"},
]

var game = null
var open: bool = false
## Element ids the last draw produced, for tests (tools/hudtest.gd).
var drawn: PackedStringArray = []

var _panel: Control = null
var _font: Font
var _t: float = 0.0
## What the mouse is over: {"row": "hands"|"abilities"|"worn", "i": int, "rect": Rect2}, or {}.
var _hover: Dictionary = {}
## The Unequip button's rect while one is showing, so a click can find it. Empty when there is none.
var _button: Rect2 = Rect2()
var _button_live: bool = false


static func create(g) -> CanvasLayer:
	var cs = load("res://scripts/character_sheet.gd").new()
	cs.name = "CharacterSheet"
	cs.game = g
	return cs


func _ready() -> void:
	layer = 3   # over the HUD (2), under the menu and settings faxes
	_font = ThemeDB.fallback_font
	_panel = Control.new()
	_panel.name = "Sheet"
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_panel.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_panel.draw.connect(_draw_sheet)
	add_child(_panel)
	visible = false


## Whoever we are driving, when there is a sheet to draw for them at all.
func _me():
	if game == null or game.phase == Game.Phase.MENU:
		return null
	return game.driving_player()


## Anything that owns the screen more than a chart does shuts the sheet: dying, being paused into
## the settings fax, going under for an operation, riding a Hive's eyes.
func _blocked() -> bool:
	var me = _me()
	if me == null or not me.alive:
		return true
	if game.paused or game.surgery_camera() != null:
		return true
	if bool(me.get("hive_view")):
		return true
	return false


func toggle() -> void:
	if open:
		close()
	elif not _blocked():
		open = true
		visible = true
		_hover = {}


func close() -> void:
	open = false
	visible = false
	_hover = {}
	_button = Rect2()


func _process(delta: float) -> void:
	_t += delta
	if not open:
		return
	if _blocked():
		close()
		return
	_hover = _hit(_panel.get_local_mouse_position())
	_panel.queue_redraw()


## A click while the sheet is up: the Unequip button is the only thing on it you can press. Tab and
## Esc are main.gd's (one owner for the toggle, so a single press cannot flip it twice).
func _unhandled_input(event: InputEvent) -> void:
	if not open:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if _button_live and _button.has_point(_panel.get_local_mouse_position()):
			var me = _me()
			if me != null and me.is_local:
				me.unequip_count = int(me.unequip_count) + 1
			get_viewport().set_input_as_handled()


# =========================================================================
# layout
# =========================================================================

## Where the three rows sit, so the hit test and the drawing agree (and a headless test can read
## it). `row(w, h, n)` is the nth row from the top, 0..2.
func _rows(w: float, h: float) -> Array:
	var span := SLOT * 4.0 + GAP * 3.0
	var x0 := w * 0.5 - span * 0.5
	var total := SLOT * 3.0 + ROW_GAP * 2.0
	var y0 := h * 0.5 - total * 0.5
	var out := []
	for r in 3:
		var rects := []
		for i in 4:
			rects.append(Rect2(x0 + i * (SLOT + GAP), y0 + r * (SLOT + ROW_GAP), SLOT, SLOT))
		out.append(rects)
	return out


const ROW_NAMES := ["hands", "abilities", "worn"]


func _hit(m: Vector2) -> Dictionary:
	var rows := _rows(_panel.size.x, _panel.size.y)
	for r in 3:
		for i in 4:
			var rect: Rect2 = rows[r][i]
			if rect.grow(4.0).has_point(m):
				return {"row": ROW_NAMES[r], "i": i, "rect": rect}
	return {}


# =========================================================================
# drawing
# =========================================================================

func _text(pos: Vector2, s: String, px: int, col: Color, align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0) -> void:
	_panel.draw_string(_font, pos, s, align, width, px, col)


func _draw_sheet() -> void:
	drawn = PackedStringArray()
	var me = _me()
	if me == null:
		return
	drawn.append("sheet")
	var w := _panel.size.x
	var h := _panel.size.y
	# Dimmed, not blacked: the corridor stays visible behind the chart, because what is coming down
	# it still matters while you read.
	_panel.draw_rect(Rect2(0, 0, w, h), Color(0.01, 0.015, 0.02, 0.72))
	var rows := _rows(w, h)
	var top: float = (rows[0][0] as Rect2).position.y
	var left: float = (rows[0][0] as Rect2).position.x
	var right: float = (rows[0][3] as Rect2).end.x

	# Header: a name and a ruled line, the one nod to paperwork.
	_text(Vector2(left, top - 56.0), String(me.player_name).to_upper(), 24, PAPER)
	_text(Vector2(left, top - 36.0), "ST. DOE'S GENERAL  -  PERSONNEL", 11, DIM)
	_panel.draw_line(Vector2(left, top - 26.0), Vector2(right, top - 26.0), Color(PAPER, 0.35), 1.0)

	# Up on the header line, not at the foot: the bottom of the screen is the message banner's.
	_text(Vector2(left, top - 78.0), "Tab closes. The shift does not stop for this.", 11, Color(DIM, 0.8),
		HORIZONTAL_ALIGNMENT_RIGHT, right - left)

	_draw_hands_row(me, rows[0])
	_draw_ability_row(me, rows[1])
	_draw_worn_row(me, rows[2])
	_draw_hover_card(w, h)


## The label down the left of a row.
func _row_label(rects: Array, s: String) -> void:
	var r: Rect2 = rects[0]
	_text(Vector2(r.position.x, r.position.y - 10.0), s, 13, Color(PAPER, 0.75))


## Row 1: the same four hand slots the HUD's item bar shows, at rest (no Alt blend, no selection
## lift, no bulky merging -- this is the contents, not the bar).
func _draw_hands_row(me, rects: Array) -> void:
	drawn.append("row_hands")
	_row_label(rects, "HANDS")
	var sel: int = me.selected_head()
	for i in 4:
		var r: Rect2 = rects[i]
		var s: Dictionary = me.slots[i] if i < me.slots.size() else {}
		var head: int = me.head_of(i)
		var kind := String(me.slots[head].kind) if head >= 0 and head < me.slots.size() else ""
		_slot_box(r, kind, head == sel and kind != "")
		if kind != "":
			var tex := ItemIcons.bare(kind)
			var side := SLOT - 16.0
			var box := Rect2(r.get_center() - Vector2(side, side) * 0.5, Vector2(side, side))
			if tex != null:
				_panel.draw_texture_rect(tex, box, false)
			else:
				_text(Vector2(r.position.x, r.get_center().y + 7.0), Items.display_name(kind).substr(0, 2).to_upper(),
					20, ItemIcons.border(kind), HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
			var count := int(s.get("count", 0))
			if count > 1 and not s.has("of"):
				_text(Vector2(r.position.x, r.end.y - 6.0), "x%d" % count, 12, Color(PAPER, 0.9),
					HORIZONTAL_ALIGNMENT_RIGHT, r.size.x - 6.0)
		_text(r.position + Vector2(6, 15), "%d" % (i + 1), 10, Color(DIM, 0.8))


## Row 2: the ability slots, drawn as the round slots the HUD's ability bar uses so the two agree.
func _draw_ability_row(me, rects: Array) -> void:
	drawn.append("row_abilities")
	_row_label(rects, "ABILITIES")
	var b = game.abilities
	var slots: Array = b.slots_for(me.peer_id) if b != null else ["", "", "", ""]
	for i in 4:
		var r: Rect2 = rects[i]
		var c := r.get_center()
		var rad := r.size.x * 0.5 - 2.0
		var id := String(slots[i]) if i < slots.size() else ""
		if id == "":
			_panel.draw_arc(c, rad, 0.0, TAU, 32, Color(0.5, 0.55, 0.6, 0.3), 1.5)
			_text(Vector2(r.position.x, c.y + 4.0), "-", 18, Color(DIM, 0.5), HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
		else:
			var gcol: Color = ItemIcons.ABILITY_COLOR.get(id, Color.WHITE)
			for k in 4:
				_panel.draw_circle(c, rad + 1.0 + k * 2.5, Color(gcol, 0.16 - k * 0.035))
			var icon := ItemIcons.ability(id)
			if icon != null:
				_panel.draw_texture_rect(icon, Rect2(c - Vector2(rad, rad), Vector2(rad, rad) * 2.0), false)
			else:
				_panel.draw_arc(c, rad, 0.0, TAU, 32, Color(gcol, 0.85), 2.0)
				_text(Vector2(r.position.x, c.y + 5.0), String(Hud.ABILITY_LABEL.get(id, id)).substr(0, 2).to_upper(),
					16, gcol, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
			var lvl := _level(id, me)
			for pip in lvl:
				_panel.draw_circle(c + Vector2((pip - (lvl - 1) * 0.5) * 9.0, rad + 8.0), 2.5, Color("9fe8a0"))
		_text(Vector2(r.position.x, r.end.y + 15.0), "Alt+%d" % (i + 1), 10, Color(DIM, 0.75),
			HORIZONTAL_ALIGNMENT_CENTER, r.size.x)


## Row 3: boots, and three empty places with nothing to put in them yet.
func _draw_worn_row(me, rects: Array) -> void:
	drawn.append("row_worn")
	_row_label(rects, "WORN")
	_button = Rect2()
	_button_live = false
	for i in 4:
		var r: Rect2 = rects[i]
		var entry: Dictionary = WORN[i]
		var worn: bool = String(entry.id) == "boots" and bool(me.boots)
		_slot_box(r, "rocket_boots" if worn else "", false)
		if worn:
			var tex := ItemIcons.bare("rocket_boots")
			var side := SLOT - 16.0
			var box := Rect2(r.get_center() - Vector2(side, side) * 0.5, Vector2(side, side))
			if tex != null:
				_panel.draw_texture_rect(tex, box, false)
			else:
				_text(Vector2(r.position.x, r.get_center().y + 7.0), "RB", 20, ItemIcons.border("rocket_boots"),
					HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
		_text(Vector2(r.position.x, r.end.y + 15.0), String(entry.label), 11,
			Color(PAPER, 0.85) if worn else Color(DIM, 0.55), HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
		if worn and me.is_local:
			_draw_unequip_button(r, me)


## The one button on the sheet. Greyed with a reason when the host would refuse it anyway, so the
## rule is on screen rather than discovered by pressing.
func _draw_unequip_button(r: Rect2, me) -> void:
	var reason := unequip_reason(me)
	var box := Rect2(r.position.x - 6.0, r.end.y + 24.0, r.size.x + 12.0, 22.0)
	var live := reason == ""
	var hot: bool = live and box.has_point(_panel.get_local_mouse_position())
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(4)
	sb.bg_color = Color(0.09, 0.10, 0.12, 0.95) if live else Color(0.05, 0.05, 0.06, 0.8)
	sb.border_color = Color(PAPER, 0.9 if hot else 0.5) if live else Color(DIM, 0.3)
	sb.set_border_width_all(2 if hot else 1)
	_panel.draw_style_box(sb, box)
	_text(Vector2(box.position.x, box.position.y + 15.0), "Unequip", 12,
		Color(PAPER, 1.0 if hot else 0.8) if live else Color(DIM, 0.5), HORIZONTAL_ALIGNMENT_CENTER, box.size.x)
	if not live:
		_text(Vector2(box.position.x - 30.0, box.end.y + 14.0), reason, 10, Color("e0a020", 0.9),
			HORIZONTAL_ALIGNMENT_CENTER, box.size.x + 60.0)
	_button = box
	_button_live = live
	drawn.append("unequip")


## Why the boots cannot come off this instant, "" when they can. The host checks the same thing
## (Game.player_unequip); this is the copy that puts it on screen.
static func unequip_reason(me) -> String:
	if not me.alive or me.downed:
		return "Not now"
	if bool(me.get("rocketing")) or bool(me.get("_remote_rocket")) or not me.is_on_floor():
		return "Not in mid-air"
	if me.carrying != 0 or me.operating:
		return "Hands busy"
	return ""


## A slot square in the HUD's idiom: dark, rounded, a category border when something is in it.
func _slot_box(r: Rect2, kind: String, selected: bool) -> void:
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(10)
	if kind == "":
		sb.bg_color = Color(0, 0, 0, 0.35)
		sb.border_color = Color(0.5, 0.55, 0.6, 0.22)
		sb.set_border_width_all(1)
		_panel.draw_style_box(sb, r)
		return
	sb.bg_color = Color(SLOT_BG, 0.9)
	sb.border_color = ItemIcons.border(kind)
	sb.set_border_width_all(3)
	_panel.draw_style_box(sb, r)
	if selected:
		var ob := StyleBoxFlat.new()
		ob.bg_color = Color(0, 0, 0, 0)
		ob.border_color = Color("f6efd4")
		ob.set_border_width_all(2)
		ob.set_corner_radius_all(13)
		_panel.draw_style_box(ob, r.grow(3.0))


func _level(id: String, me) -> int:
	var b = game.abilities
	if b == null or id == "":
		return 0
	return int(b.level(me.peer_id, String(b.ABILITY_ID_TO_PATH.get(id, ""))))


# =========================================================================
# the hover card
# =========================================================================

## The card beside whatever the mouse is on. The ability lines are the point of the row: they read
## the live curves out of `game.abilities`, so a level-2 Hive Eyes says 40 m and 9 s because that is
## what it will actually do, not because anyone typed it here.
func _draw_hover_card(w: float, h: float) -> void:
	if _hover.is_empty():
		return
	var me = _me()
	if me == null:
		return
	var lines := hover_lines(String(_hover.row), int(_hover.i), me, game)
	if lines.is_empty():
		return
	drawn.append("card")
	var title := String(lines[0])
	var body: Array = lines.slice(1)
	var cw := 300.0
	var ch := 40.0 + body.size() * 17.0
	# A fixed column to the right of the rows, not floating off the slot: a card that moves with the
	# pointer ends up sitting on top of the slots you were about to read.
	var at: Rect2 = _hover.rect
	var rows := _rows(w, h)
	var x := clampf((rows[0][3] as Rect2).end.x + 34.0, 8.0, w - cw - 8.0)
	var y := clampf(at.get_center().y - ch * 0.5, 8.0, h - ch - 8.0)
	var box := Rect2(x, y, cw, ch)
	# A leader from the slot to the card, so a fixed column still reads as "this one".
	_panel.draw_line(Vector2(at.end.x + 4.0, at.get_center().y), Vector2(box.position.x, box.get_center().y),
		Color(PAPER, 0.3), 1.0)
	_panel.draw_rect(box, Color(0.02, 0.03, 0.04, 0.95))
	_panel.draw_rect(box, Color(PAPER, 0.55), false, 1.5)
	_text(Vector2(box.position.x + 12.0, box.position.y + 24.0), title, 16, PAPER)
	for i in body.size():
		_text(Vector2(box.position.x + 12.0, box.position.y + 44.0 + i * 17.0), String(body[i]), 12, Color("cfd8dd"))


## What a slot's card says: the first line is its title, the rest its body. Pure and static so a
## headless test can read it without a screen.
static func hover_lines(row: String, i: int, me, g) -> Array:
	match row:
		"hands":
			var head: int = me.head_of(i)
			if head < 0 or head >= me.slots.size():
				return []
			var kind := String(me.slots[head].kind)
			if kind == "":
				return ["Empty hand", "Nothing in slot %d." % (i + 1)]
			var out := [Items.display_name(kind)]
			var count := int(me.slots[head].get("count", 1))
			if count > 1:
				out.append("%d of them." % count)
			return out
		"abilities":
			var b = g.abilities if g != null else null
			if b == null:
				return []
			var slots: Array = b.slots_for(me.peer_id)
			var id := String(slots[i]) if i < slots.size() else ""
			if id == "":
				return ["Empty ability slot", "Graft a part in to fill it."]
			var path := String(b.ABILITY_ID_TO_PATH.get(id, ""))
			var lvl: int = int(b.level(me.peer_id, path))
			var out2 := ["%s  -  level %d" % [String(Hud.ABILITY_LABEL.get(id, id)), lvl]]
			out2.append(String(Hud.ABILITY_DESC.get(id, "")))
			if id == "echo":
				out2.append("Reaches %d m, outlines hold for %.1f s." % [roundi(b.echo_radius(lvl)), b.echo_seconds(lvl)])
				out2.append("20 s cooldown. Everything nearby hears it.")
			elif id == "hive_in":
				out2.append("Finds a Hive up to %d m away, %.0f s inside it." % [roundi(b.hive_range(lvl)), b.hive_seconds(lvl)])
				out2.append("12 s cooldown. Your body stands there while you are gone.")
			if lvl < b.MAX_LEVEL:
				out2.append("Level %d would make it %s." % [lvl + 1, _next_line(b, id, lvl + 1)])
			var cd: float = b.cooldown_left(me.peer_id, path)
			if cd > 0.0:
				out2.append("Cooling down: %d s." % ceili(cd))
			out2.append("Alt+%d fires it." % (i + 1))
			return out2
		"worn":
			var entry: Dictionary = WORN[i]
			if String(entry.id) == "boots" and bool(me.boots):
				var out3 := ["Rocket boots", "Hold crouch through a sprint-dive to burn fuel and fly.",
					"Walls hurt. Fuel comes back on the ground.",
					"Fuel: %d%%." % roundi(float(me.fuel) * 100.0)]
				var why := unequip_reason(me)
				out3.append("Unequip drops them at your feet." if why == "" else why + ".")
				return out3
			return ["%s: nothing" % String(entry.label), "Nothing goes here yet."]
	return []


static func _next_line(b, id: String, lvl: int) -> String:
	if id == "echo":
		return "%d m for %.1f s" % [roundi(b.echo_radius(lvl)), b.echo_seconds(lvl)]
	return "%d m for %.0f s" % [roundi(b.hive_range(lvl)), b.hive_seconds(lvl)]
