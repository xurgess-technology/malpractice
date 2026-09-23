extends Node
## SYRINGE DRAW (docs/ANESTHETIC_INJECTION_SPEC.md 9): every handheld draw that is open right now.
##
## HOW A PER-PLAYER HANDHELD CASE REPLICATES. A table is one shared thing, so one surgery system
## serves it and whoever walks up is the operator. A draw is not: it belongs to the syringe in your
## hand, and four players in four corridors can each have one open at the same time. So there is
## one scripts/syringe/syringe_station.gd per player, and this node is the map of them.
##
## The three things that had to be decided, and what was decided:
##
## 1. THE NODE PATH. Godot's RPCs are addressed by node path, so a per-player node created on
##    demand is a path that may not exist on the far machine yet. The stations therefore carry no
##    RPCs of their own: this manager sits at a fixed path ("SyringeStations", a child of Game on
##    every machine, created in game._ready) and is the one thing that talks. A station hands its
##    report up here and this sends it.
## 2. WHO A REPORT BELONGS TO. Nothing on the wire says which station a report is for, and nothing
##    needs to: the operator of a station is its owner, forever and by construction, so the sender
##    id IS the station. `multiplayer.get_remote_sender_id()` picks it, which also means a client
##    can only ever drive its own draw -- it cannot address anybody else's, however it lies.
## 3. HOW MANY EXIST. Host authoritative, like everything else. The host makes a station the first
##    time a player opens a draw and keeps it for the rest of the shift (freeing it the moment a
##    draw ends would cut off the surgery camera's blend back to the player's own). Clients make
##    and keep theirs from the replicated map, so an onlooker has the node a teammate's panel needs
##    to hang off -- you can watch somebody else load a syringe from across the room.
##
## Nothing else in the surgery framework needed changing for any of this. The arcade's freeze and
## hand-over key off `operating` rather than off a table, and the station freezes its site at open
## time, so the walk-away test measures a real, still world point.

const StationScript := preload("res://scripts/syringe/syringe_station.gd")

var game: Node = null
## {peer_id: station node}
var by_peer: Dictionary = {}


func setup(g: Node) -> void:
	game = g


## The station for `peer`, made if it does not exist yet.
func station(peer: int) -> Node:
	var s = by_peer.get(peer)
	if s != null and is_instance_valid(s):
		return s
	s = StationScript.new()
	s.name = "S%d" % peer
	add_child(s)
	s.setup(game, peer, self)
	by_peer[peer] = s
	return s


## The station for `peer` if there is one, else null (no side effect).
func peek(peer: int) -> Node:
	var s = by_peer.get(peer)
	return s if s != null and is_instance_valid(s) else null


# =========================================================================
# what the player and the game ask
# =========================================================================

## The crosshair line for E aimed at nothing with a syringe in hand. Local, every machine, so the
## prompt is instant; the host asks the same question again before it acts on the press.
func hand_prompt(p: Node) -> String:
	if p == null or not is_instance_valid(p) or game == null:
		return ""
	var s := peek(int(p.peer_id))
	if s != null:
		return s.hand_prompt(p)
	# No station yet: ask a throwaway the same question without making one.
	var sel: Dictionary = p.selected_stack() if p.has_method("selected_stack") else {}
	if String(sel.get("kind", "")) != "syringe":
		return ""
	if Syringes.is_loaded(String(sel.get("x", ""))):
		return "!That syringe is already loaded."
	if not _has_fluid(p):
		return "!Nothing to draw from."
	if bool(p.get("operating")):
		return "!You are operating."
	return "Load the syringe"


func _has_fluid(p: Node) -> bool:
	if not ("slots" in p):
		return false
	for s in (p.slots as Array):
		if not (s as Dictionary).has("of") and Syringes.is_fluid(String((s as Dictionary).get("kind", ""))):
			return true
	return false


## Host: E aimed at nothing with a syringe in hand.
func hand_open(p: Node) -> void:
	if game == null or not game.is_host() or p == null or not is_instance_valid(p):
		return
	var s := station(int(p.peer_id))
	var why: String = s.why_not(p)
	if why != "":
		game.tell(p, why, 2.0)
		return
	s.begin(p)


## `p` stops drawing (hit, shoved, gone, dead). Fanned out like game.end_operations.
func end(p: Node) -> void:
	if p == null:
		return
	var s := peek(int(p.peer_id))
	if s != null:
		s.end(p)


## Whoever is mid-draw right now, for game's `operating` flag.
func operator_peers() -> Array:
	var out: Array = []
	for s in by_peer.values():
		if is_instance_valid(s) and int(s.operator_peer()) != 0:
			out.append(int(s.operator_peer()))
	return out


## True when `p` has a draw open (the OR's can_begin uses it: one thing at a time).
func is_drawing(peer: int) -> bool:
	var s := peek(peer)
	return s != null and int(s.operator_peer()) == peer


# ---- the local machine's camera and mouse ----

func camera() -> Camera3D:
	for s in by_peer.values():
		if is_instance_valid(s):
			var c: Camera3D = s.surgery.camera()
			if c != null:
				return c
	return null


func wants_mouse() -> bool:
	for s in by_peer.values():
		if is_instance_valid(s) and s.surgery.wants_mouse():
			return true
	return false


func local_exit() -> void:
	for s in by_peer.values():
		if is_instance_valid(s) and s.surgery.wants_mouse():
			s.surgery.local_operator_exit()


# =========================================================================
# frame and replication
# =========================================================================

func physics_tick(delta: float) -> void:
	for s in by_peer.values():
		if is_instance_valid(s):
			s.physics_tick(delta)


func net_state() -> Dictionary:
	var out := {}
	for peer in by_peer.keys():
		var s = by_peer[peer]
		if is_instance_valid(s):
			out[int(peer)] = s.net_state()
	return out


func apply_net_state(st: Dictionary) -> void:
	if game == null or game.is_host():
		return
	for peer in st.keys():
		var s := station(int(peer))
		var v = st[peer]
		if v is Dictionary:
			s.apply_net_state(v as Dictionary)


func reset() -> void:
	for s in by_peer.values():
		if is_instance_valid(s):
			s.reset()
			s.queue_free()
	by_peer.clear()


# =========================================================================
# the one RPC path (see the header: the sender IS the station)
# =========================================================================

func report_from(s: Node, report: Dictionary) -> void:
	if game == null:
		return
	if game.is_host():
		s.surgery.receive_operator_report(game.driving_id(), report)
	elif Net.active:
		if report.has("botches") or report.has("finished") or report.has("exit") or report.has("reliable"):
			_rpc_report_reliable.rpc_id(Net.HOST_ID, report)
		else:
			_rpc_report.rpc_id(Net.HOST_ID, report)


func _deliver(from: int, report: Dictionary) -> void:
	if game == null or not game.is_host():
		return
	var s := peek(from)
	if s == null:
		return   # no draw open for that peer: nothing to drive
	s.surgery.receive_operator_report(from, report)


@rpc("any_peer", "unreliable_ordered", "call_remote")
func _rpc_report(report: Dictionary) -> void:
	_deliver(multiplayer.get_remote_sender_id(), report)


@rpc("any_peer", "reliable", "call_remote")
func _rpc_report_reliable(report: Dictionary) -> void:
	_deliver(multiplayer.get_remote_sender_id(), report)
