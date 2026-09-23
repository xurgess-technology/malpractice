extends Node
## SYRINGE DRAW (docs/ANESTHETIC_INJECTION_SPEC.md 9): ONE PLAYER'S handheld draw.
##
## The stand-in game after the model of scripts/downed/player_surgery.gd: a node that runs its own
## copy of scripts/surgery/surgery_system.gd and stands in for the game towards it, so the panel,
## the camera, the freeze and the hand-over all come for free. What it stands in for is not a table
## and not a body -- it is the `syringe_draw` "ailment" (scripts/procedures.gd, `handheld: true`),
## the one step you play standing in a corridor with a syringe in your hand.
##
## ONE OF THESE PER PLAYER. Unlike a table, which is a single shared thing, a handheld case belongs
## to whoever is holding the syringe, and several players can have one open at once. The owner is
## the operator and never changes, so this node is created for a peer and freed with its case;
## scripts/syringe/syringe_stations.gd owns the map of them and the single RPC path they report on.
##
## THE SITE IS FROZEN AT OPEN. site_override() hands back a transform worked out ONCE, when the
## case starts: a tray-top in front of where the player was standing, +Y up out of it and +Z back
## toward them, exactly the geometry of a table site. That is deliberate and it is what keeps the
## freeze honest -- surgery_system's walk-away test measures the operator against table_pos(), so a
## site that followed the player could never be walked away from. Frozen, being shoved out of a
## corridor draw ends it the same way being shoved off a table does.
##
## NOTHING IS BILLED HERE. There is no patient, so vitals sit at 100 and surgery_botch costs
## nothing; a botch only says its line. The bill comes at the table, on the dose that goes in.

const SurgeryScript := preload("res://scripts/surgery/surgery_system.gd")

## How far in front of the player, and how far below their eyes, the tray-top sits (metres).
const SITE_FORWARD_M := 0.50
const SITE_BELOW_EYES_M := 0.55

var game: Node = null          ## the real Game
var stations: Node = null      ## scripts/syringe/syringe_stations.gd, our RPC path home
var peer: int = 0              ## whose draw this is; also the only operator it will ever have
var surgery: Node = null

## {patient_id: "", ailment_id: "syringe_draw", step_index: 0, flags: {}}; {} when closed.
var case: Dictionary = {}
## The surgery system looks for one on its "game"; a corridor has no body.
var patient_body: Node3D = null

var _site := Transform3D()
var _say_timer := 0.0
var _started := false


# ---- what the surgery system reads from its "game" ----
var players: Dictionary:
	get: return game.players if game != null else {}
var world_time: float:
	get: return float(game.world_time) if game != null else 0.0
var shift: int:
	get: return int(game.shift) if game != null else 1
## Offset like the player table's (+7331) so a corridor draw does not roll the same as a table's.
var seed_value: int:
	get: return (int(game.seed_value) + 5171 + peer) if game != null else 0
var phase: int:
	get: return int(game.phase) if game != null else 0
## No patient, nothing to lose.
var vitals: float:
	get: return 100.0


func setup(g: Node, owner_peer: int, home: Node) -> void:
	game = g
	peer = owner_peer
	stations = home
	surgery = SurgeryScript.new()
	surgery.name = "Surgery"
	surgery.table_index = -1   # not a table: keeps _table_vat() from finding one
	add_child(surgery)
	surgery.setup(self)


func is_host() -> bool:
	return game.is_host()


func local_player() -> Node:
	return game.local_player()


func viewed_player() -> Node:
	return game.viewed_player()


func driving_player() -> Node:
	return game.driving_player()


func driving_id() -> int:
	return int(game.driving_id())


func shelf_count(kind: String) -> int:
	return game.shelf_count(kind)


func emit_noise(pos: Vector3, loudness: float, kind: String) -> void:
	game.emit_noise(pos, loudness, kind)


## The owner, or null.
func owner_player() -> Node:
	var p = game.players.get(peer) if game != null else null
	return p if p != null and is_instance_valid(p) else null


# =========================================================================
# the site: worked out once, then frozen and replicated
# =========================================================================

## A tray-top in front of the player: +Y out of it (the panel lifts along that), +Z back toward
## them. The same shape as a body site, which is why nothing downstream can tell the difference.
static func site_for(p: Node) -> Transform3D:
	if p == null or not is_instance_valid(p):
		return Transform3D()
	var yaw := float(p.rotation.y)
	var fwd := Vector3(-sin(yaw), 0.0, -cos(yaw))
	var eyes: Vector3 = p.global_position
	if "head" in p and p.head != null and is_instance_valid(p.head):
		eyes = (p.head as Node3D).global_position
	var origin := eyes + fwd * SITE_FORWARD_M - Vector3.UP * SITE_BELOW_EYES_M
	var basis_z := -fwd
	var basis_y := Vector3.UP
	return Transform3D(Basis(basis_y.cross(basis_z), basis_y, basis_z).orthonormalized(), origin)


## SYRINGE DRAW -- the second anchoring mode. The surgery system asks for this instead of looking
## up a marker on a body (docs/CONTRACTS.md, "A step away from a patient").
func site_override() -> Transform3D:
	return _site


## The walk-away / noise / monitor anchor. The frozen site, not the player.
func table_pos() -> Vector3:
	return _site.origin


# =========================================================================
# the rack (docs/ANESTHETIC_INJECTION_SPEC.md 9)
# =========================================================================

## Up to three fluids the owner is actually carrying, in slot order: centre, left, right. Three and
## not four because the fourth hand slot is holding the syringes. Every machine reads the same
## replicated slots in the same order, so every machine builds the same rack.
func rack() -> Array:
	var out: Array = []
	var p := owner_player()
	if p == null or not ("slots" in p):
		return out
	for i in (p.slots as Array).size():
		var s: Dictionary = p.slots[i]
		if s.has("of"):
			continue   # the second half of a bulky stack: never counted twice
		var kind := String(s.get("kind", ""))
		if not Syringes.is_fluid(kind):
			continue
		var dup := false
		for e in out:
			if String(e.kind) == kind:
				dup = true
				break
		if dup:
			continue
		out.append({"kind": kind, "name": Syringes.fluid_name(kind), "count": int(s.get("count", 0))})
		if out.size() >= 3:
			break
	return out


## Merged over the minigame's context last: this is the corridor half of inject_arcade.
func extra_ctx() -> Dictionary:
	return {"draw_only": true, "rack": rack()}


# =========================================================================
# the case (host starts and ends it; every machine applies it)
# =========================================================================

## Why `q` cannot start a draw right now ("" when they can). Host and client both ask, so the
## crosshair prompt and the host's own check are the same words.
func why_not(q: Node) -> String:
	if q == null or not is_instance_valid(q) or int(q.peer_id) != peer:
		return "Not your syringe."
	if not bool(q.alive) or bool(q.get("downed")) or bool(q.get("on_table")):
		return "Not right now."
	if bool(q.get("operating")) and surgery.operator_peer() != peer:
		return "You are operating."
	var sel: Dictionary = q.selected_stack() if q.has_method("selected_stack") else {}
	if String(sel.get("kind", "")) != "syringe" or int(sel.get("count", 0)) < 1:
		return "Hold a syringe to do this."
	if Syringes.is_loaded(String(sel.get("x", ""))):
		return "That syringe is already loaded."
	if rack().is_empty():
		return "Nothing to draw from."
	return ""


## The crosshair line for E aimed at nothing with a syringe in hand ("" = no offer, "!..." = why
## not). Modelled on Vats.hand_prompt.
func hand_prompt(q: Node) -> String:
	if q == null or not is_instance_valid(q) or int(q.peer_id) != peer:
		return ""
	var sel: Dictionary = q.selected_stack() if q.has_method("selected_stack") else {}
	if String(sel.get("kind", "")) != "syringe":
		return ""
	if not case.is_empty():
		return ""
	var why := why_not(q)
	if why != "":
		return "!" + why
	return "Load the syringe"


## Host: `q` (who must be our owner) opens a draw. The site is frozen here and nowhere else.
func begin(q: Node) -> void:
	if not is_host():
		return
	if case.is_empty():
		if why_not(q) != "":
			return
		_site = site_for(q)
		case = {"patient_id": "", "ailment_id": "syringe_draw", "step_index": 0, "flags": {}}
		_started = true
		surgery.start_case("", "syringe_draw")
	surgery.begin(q)


func end(q: Node) -> void:
	if q == null or int(q.peer_id) != peer:
		return
	surgery.end(q)


func operator_peer() -> int:
	return surgery.operator_peer()


## Host: the draw is over (finished, walked away from, dead, gone).
func clear() -> void:
	if case.is_empty():
		return
	case = {}
	_started = false
	surgery.clear_case()


## Every machine, idempotent: the surgery system follows `case`.
func apply_locally() -> void:
	var want: bool = not case.is_empty()
	if want == _started:
		return
	_started = want
	if want:
		surgery.start_case("", String(case.get("ailment_id", "syringe_draw")))
	else:
		surgery.clear_case()


# =========================================================================
# the game surface the surgery system calls
# =========================================================================

## Nothing is billed in the corridor: you have not touched a patient, so there is no patient to
## hurt. The line still gets said, because the mistake still happened.
func surgery_botch(_amount: float, reason: String) -> void:
	if not is_host():
		return
	if reason != "" and _say_timer <= 0.0:
		_say_timer = 2.0
		game.say(reason, 1.8)


## DRAW! and FLICK! are done: the barrel's level goes into the syringe's `x`, and the fluid it came
## out of is spent. `result` is inject_arcade's {drawn, bubbles, fluid}.
func surgery_step_done(result: Dictionary, operator_peer_id: int = 0) -> void:
	if not is_host() or case.is_empty():
		return
	var p = game.players.get(operator_peer_id if operator_peer_id != 0 else peer)
	var level := float(result.get("drawn", 0.0))
	var fluid := String(result.get("fluid", "anesthetic"))
	if p != null and is_instance_valid(p) and level > 0.0:
		var i: int = p.selected_head()
		if String(p.slots[i].get("kind", "")) == "syringe":
			# The contents ride the stack's `x`, the vats' trick: no new replication.
			p.slots[i]["x"] = Syringes.pack(fluid, level, result.get("bubbles", []) as Array)
			game.tell(p, "%s." % Syringes.label(String(p.slots[i]["x"])), 2.5)
		# The vial you drew out of is gone. Do this AFTER the write: consume_hand can empty a slot.
		if p.has_method("consume_hand"):
			p.consume_hand(fluid, 1)
	game._sound("step_done", table_pos())
	clear()


func send_operator_report(report: Dictionary) -> void:
	if stations != null:
		stations.report_from(self, report)


# =========================================================================
# frame and replication
# =========================================================================

func physics_tick(delta: float) -> void:
	_say_timer = maxf(0.0, _say_timer - delta)
	if is_host() and not case.is_empty():
		var p := owner_player()
		# surgery_system's own walk-away test ends the operation; this clears the case behind it.
		if p == null or not bool(p.alive) or surgery.operator_peer() == 0:
			clear()
	surgery.physics_tick(delta)


func net_state() -> Dictionary:
	return {"c": case.duplicate(true), "s": surgery.net_state().duplicate(true),
		"o": _site.origin, "y": snappedf(_site.basis.get_euler().y, 0.001)}


func apply_net_state(s: Dictionary) -> void:
	if is_host():
		return
	var c = s.get("c", {})
	case = (c as Dictionary).duplicate(true) if c is Dictionary else {}
	var o = s.get("o", Vector3.ZERO)
	_site = Transform3D(Basis(Vector3.UP, float(s.get("y", 0.0))), o if o is Vector3 else Vector3.ZERO)
	apply_locally()
	var ss = s.get("s", {})
	if ss is Dictionary:
		surgery.apply_net_state(ss)


func reset() -> void:
	case = {}
	_started = false
	surgery.clear_case()
