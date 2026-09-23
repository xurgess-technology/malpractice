extends Node
## SYRINGE DRAW (docs/ANESTHETIC_INJECTION_SPEC.md 9): headless checks for the handheld draw.
##
##   godot --headless --fixed-fps 60 --path . tools/syringetest.tscn
##
## What it proves, in order: the crosshair offers the draw only when it should; opening one makes a
## station whose site is frozen in front of the player; the minigame that opens is the corridor half
## (DRAW! and FLICK! only) with a rack built from the fluids in hand; finishing it writes the level
## into the syringe's `x` and spends the vial; the table then takes that loaded syringe and opens on
## STICK!; the dose spends the syringe and clears its `x`; and the OR's empty-handed fallback still
## offers all four stages. Exits 0 when every check passes.

const InjectScript := preload("res://scripts/surgery/arcade/inject_arcade.gd")

var main: Node3D
var game: Game
var me: Player
var t := 0.0
var _done := false
var _failures: Array = []


func _ready() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	game = main.game
	main.menu.hide_menu()
	Net.start_solo("Tester")
	game.start_session(12345)
	await _frames(5)
	me = game.local_player()
	game.begin_shift()
	await _frames(10)
	await _prompt()
	await _open()
	await _finish_draw()
	await _table()
	await _fallback()
	_finish()


func _physics_process(delta: float) -> void:
	t += delta
	if t > 300.0 and not _done:
		_check(false, "timed out")
		_finish()


# =========================================================================

## The crosshair only offers a draw when there is a syringe AND something to put in it.
func _prompt() -> void:
	var st = game.syringe_stations
	_check(st != null, "the game has a SyringeStations child")
	_hands({})
	_check(st.hand_prompt(me) == "", "no syringe in hand: no offer at all")
	_hands({"syringe": 3})
	_check(st.hand_prompt(me).begins_with("!"), "a syringe but no fluid: the offer says why not")
	_hands({"syringe": 3, "anesthetic": 2})
	_check(st.hand_prompt(me) == "Load the syringe", "a syringe and a vial: the draw is offered")
	me._update_aim()
	_check(me.aim_id == "syringe_hand", "aimed at nothing, the aim id is the syringe pseudo-target")
	# A syringe that is already loaded is not offered a second draw: one loaded syringe per slot.
	me.slots[_slot("syringe")]["x"] = Syringes.pack("anesthetic", 0.5, [])
	_check(st.hand_prompt(me).begins_with("!"), "an already-loaded syringe is not offered another draw")
	me.slots[_slot("syringe")]["x"] = ""


## Opening one makes a station, freezes its site in front of the player, and opens the corridor half.
func _open() -> void:
	var st = game.syringe_stations
	var before: Vector3 = me.global_position
	game.player_pressed_interact(me, "syringe_hand")
	await _frames(6)
	var s = st.peek(me.peer_id)
	_check(s != null, "pressing E made a station for that player")
	_check(int(s.operator_peer()) == me.peer_id, "its operator is the player who opened it")
	_check(not s.case.is_empty() and String(s.case.ailment_id) == "syringe_draw", "the case is the handheld one")
	var site: Transform3D = s.site_override()
	var flat: Vector3 = site.origin - before
	flat.y = 0.0
	_check(flat.length() > 0.2 and flat.length() < 1.2, "the site is pinned a step in front of the player")
	_check(site.basis.y.dot(Vector3.UP) > 0.99, "+Y out of the tray is world up, as a body site's is")
	# THE FREEZE. The site must not follow the player, or walking away could never end the draw.
	me.teleport(before + Vector3(2.0, 0.0, 0.0))
	await _frames(2)
	_check(s.site_override().origin.is_equal_approx(site.origin), "the site stays where it was: it is frozen at open")
	me.teleport(before)
	await _frames(2)
	var mg = s.surgery.mg
	_check(mg != null and mg.get_script() == InjectScript, "the minigame that opened is the injection")
	_check(bool(mg.ctx.get("draw_only", false)), "it opened in the corridor half (draw_only)")
	_check(int(mg.phase) == InjectScript.Phase.DRAW, "which starts on DRAW!")
	_check(mg.rack.size() == 1 and String(mg.rack[0].kind) == "anesthetic", "the rack holds the one fluid in hand")
	_check(absf(float(mg.syr_x) - InjectScript.SYR_X) < 0.01, "one source, so the syringe stands at the centre")
	# There is no patient in a corridor, so the band is the standard 80 kg one.
	_check(absf(float(mg.ctx.get("patient", {}).get("weight_kg", 80.0)) - Syringes.REFERENCE_WEIGHT_KG) < 0.01,
		"with no patient the dose is aimed at the standard weight")


## Finishing the draw puts the level in the syringe's `x` and spends the vial.
func _finish_draw() -> void:
	var st = game.syringe_stations
	var s = st.peek(me.peer_id)
	var vials_before: int = me.hand_count("anesthetic")
	s.surgery_step_done({"drawn": 0.62, "bubbles": [7.5, 4.0], "fluid": "anesthetic"}, me.peer_id)
	await _frames(4)
	var d := Syringes.unpack(String(me.slots[_slot("syringe")].get("x", "")))
	_check(not d.is_empty(), "the syringe came away loaded")
	_check(absf(float(d.level) - 0.62) < 0.002, "carrying the barrel level it actually reached, not a score")
	_check((d.bubbles as Array).size() == 2, "and the bubbles it was left with")
	_check(me.hand_count("anesthetic") == vials_before - 1, "the vial it was drawn out of is spent")
	_check(s.case.is_empty(), "the case closed behind it")
	_check(int(s.operator_peer()) == 0, "and nobody is operating it")


## The table takes that loaded syringe and opens on STICK!.
func _table() -> void:
	var table: int = int(game.patient_tables[0].index) if not game.patient_tables.is_empty() else 0
	game.add_case({"patient_id": "bob", "ailment_id": "gunshot", "table": table, "state": "on_table"})
	await _frames(6)
	var sys = game.surgery_for_table(table)
	_check(sys != null, "there is a surgery system for the table")
	var pos: Vector3 = game.table_position(table)
	me.teleport(pos + Vector3(0.0, 0.0, 1.0))
	await _frames(4)
	me.selected = _slot("syringe")
	_check(sys.can_begin(me) == "", "a loaded syringe is accepted where the step asks for a vial")
	sys.begin(me)
	await _frames(8)
	var mg = sys.mg
	_check(mg != null and int(mg.phase) == InjectScript.Phase.INJECT, "so the step opens on STICK!, not DRAW!")
	_check(absf(float(mg.fluid) - 0.62) < 0.002, "with the level the corridor put in the barrel")
	_check(mg.rack.is_empty(), "and no rack: the table is not a rack")
	# The stored level is absolute, so the band here is this patient's, not the corridor's.
	_check(absf(float(mg.ctx.get("patient", {}).get("weight_kg", 0.0)) - float(Procedures.patient("bob").get("weight_kg", 0.0))) < 0.01,
		"the band is worked out from the real patient, and the stored level is scored against it")
	# Delivering the dose spends the syringe and clears its `x` -- that is what makes it one-use.
	var syringes_before: int = me.hand_count("syringe")
	game.surgery_step_done({"sedation": 1.0, "quality": 0.8}, table, me.peer_id)
	await _frames(4)
	_check(me.hand_count("syringe") == syringes_before - 1, "the dose spent one syringe off the batch")
	var i := _slot("syringe")
	_check(i < 0 or String(me.slots[i].get("x", "")) == "", "and cleared the slot's contents: one use, then empty")


## THE FALLBACK. Turning up with an empty syringe (or nothing) still gets all four stages.
func _fallback() -> void:
	var table: int = int(game.patient_tables[0].index) if not game.patient_tables.is_empty() else 0
	var sys = game.surgery_for_table(table)
	sys.end(me)
	# The dose above moved the case on; put a fresh one on another table so this is a sedate step.
	var table2: int = table
	for pt in game.patient_tables:
		if int(pt.index) != table:
			table2 = int(pt.index)
			break
	if table2 == table:
		_check(false, "the level has a second patient table for the fallback check")
		return
	game.add_case({"patient_id": "bob", "ailment_id": "gunshot", "table": table2, "state": "on_table"})
	sys = game.surgery_for_table(table2)
	me.teleport(game.table_position(table2) + Vector3(0.0, 0.0, 1.0))
	await _frames(6)
	_hands({"anesthetic": 2, "syringe": 1})
	me.selected = _slot("anesthetic")
	_check(sys.can_begin(me) == "", "a plain vial still begins the step, exactly as before")
	sys.begin(me)
	await _frames(8)
	var mg = sys.mg
	_check(mg != null and int(mg.phase) == InjectScript.Phase.DRAW, "and it opens on DRAW!, all four stages")
	_check(not bool(mg.ctx.get("draw_only", false)), "not the corridor half")
	_check(not mg.ctx.has("loaded"), "and not handed a loaded syringe")
	_check(mg.rack.is_empty(), "the OR page has no rack: one vial at the centre, as it always was")


# =========================================================================

func _hands(want: Dictionary) -> void:
	for i in me.slots.size():
		me.clear_slot(i)
	for kind in want.keys():
		me.take_into(String(kind), int(want[kind]))
	me.selected = 0


func _slot(kind: String) -> int:
	for i in me.slots.size():
		if String(me.slots[i].get("kind", "")) == kind:
			return i
	return -1


func _check(ok: bool, what: String) -> void:
	print("[syringetest] t=%.1f %s  %s" % [t, "PASS" if ok else "FAIL", what])
	if not ok:
		_failures.append(what)


func _finish() -> void:
	if _done:
		return
	_done = true
	print("[syringetest] ------------------------------------------")
	print("[syringetest] result=%s failures=%d" % ["PASS" if _failures.is_empty() else "FAIL", _failures.size()])
	get_tree().quit(0 if _failures.is_empty() else 1)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame
