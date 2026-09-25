extends Node
## The two surgeon abilities and the four slots they sit in: Echo (a shriek that outlines everything
## nearby through walls) and Puppet (climb into a nearby Hive for a few seconds: see through it,
## look around in it and walk it about while your own body stands there). A child "Abilities" of
## Game on every machine.
##
## Where levels come from: **grafting**. An eye_hive graft grants Puppet at level 1 and takes it
## away when the part comes out (scripts/grafting/grafts.gd PART_ABILITY). Brains and the break-room
## blender used to be the other source and are gone (docs/backlog/ABILITIES_REMOVED.md), which is
## why a level is now simply SET rather than accumulated: there are no fractional points any more,
## `set_level()` is the whole earning path, and Echo has no source in the game yet.
##
## Authority: the host decides everything (levels, slots, cooldowns, who is driving which Hive, and
## where that Hive walks). Clients get it through `net_state()` (global snapshot field `ab`), the
## Player field `puppeting` (report key `pp`), the Hive's own Monster report, and the reliable events
## `ab_echo` and `ab_puppet`. A client puppeting sends what it wants the Hive to do in its own
## report_state (Player.puppet_move / puppet_yaw). The visuals (the Echo view, the Puppet camera) run
## on every machine from that state.

const EchoViewScript := preload("res://scripts/abilities/echo_view.gd")
const PuppetViewScript := preload("res://scripts/abilities/puppet_view.gd")

## The ability paths. The ORDER MATTERS: it indexes the per-player level array. Puppet grows on the
## "hive" path (it is the Hive's ability, whatever it is called).
const PATHS := ["hive", "sonographer"]
const ABILITY_NAME := {"hive": "Puppet", "sonographer": "Echo"}
## SWEEP 4A HOOK (controls): ability ids, and the ability-slot cap. add_ability()/set_level()/
## slot_of() are independent of how a level is earned, so slot code never reads levels directly
## except through level().
const ABILITY_ID := {"sonographer": "echo", "hive": "puppet"}
const ABILITY_ID_TO_PATH := {"echo": "sonographer", "puppet": "hive"}
const MAX_SLOTS := 4
const HIVE := "hive"   # Monster.HIVE (monsters worker); the string, so this runs without it

const MAX_LEVEL := 3

const ECHO_COOLDOWN := 20.0
const ECHO_NOISE := 1.2
const ECHO_RADIUS := 12.0
const ECHO_RADIUS_PER_LEVEL := 6.0
const ECHO_SECONDS := 2.5
const ECHO_SECONDS_PER_LEVEL := 0.75

const PUPPET_COOLDOWN := 12.0   # counted from when you come back
const PUPPET_RANGE := 20.0
const PUPPET_RANGE_PER_LEVEL := 10.0
## A couple of seconds in the Hive, counted from when you arrive in it: 4 / 5 / 6 s.
const PUPPET_SECONDS := 3.0
const PUPPET_SECONDS_PER_LEVEL := 1.0
## After a puppeting ends, slot presses from that player are ignored this long (the press that
## ended it on the client may arrive after the host already ended it).
const PUPPET_PRESS_GRACE := 0.5

var game: Node = null

## Replicated. peer id -> [hive level, sonographer level] (ints, 0..MAX_LEVEL).
var _levels: Dictionary = {}
## Replicated. peer id -> [monster id, world_time it ends].
var _puppet: Dictionary = {}
## Replicated. peer id -> Array[MAX_SLOTS] of ability id ("" empty). Host authoritative; a new
## ability goes into the first empty slot the moment set_level() takes it to 1 or more. See
## add_ability() / set_level() / slot_of() below.
var _slots: Dictionary = {}

# SWEEP 4A HOOK (Echo polish, chunk 4): peer id -> world_time the shriek pose ends. Not
# replicated: every machine sets it the same way, locally, from the reliable ab_echo event.
var _echo_pose_until: Dictionary = {}

# host only
var _puppet_hp: Dictionary = {}        # peer id -> hp when the puppeting started
var _cd: Dictionary = {}               # "echo:<peer>" / "puppet:<peer>" -> world_time it is ready
var _press_grace: Dictionary = {}      # peer id -> world_time before which slot presses are ignored
var _hint_at: Dictionary = {}          # peer id -> world_time of the last "Nothing happens."

var _level_node: Node = null

var echo_view: Node = null
var puppet_view: Node = null

## Test seams: the last Echo started on this machine and the last ability result on the host.
var last_echo := {}
var last_result := ""


func setup(g: Node) -> void:
	game = g
	echo_view = EchoViewScript.new()
	echo_view.name = "EchoView"
	add_child(echo_view)
	echo_view.setup(g)
	puppet_view = PuppetViewScript.new()
	puppet_view.name = "PuppetView"
	add_child(puppet_view)
	puppet_view.setup(g)


# =========================================================================
# levels
# =========================================================================

func level(peer_id: int, path: String) -> int:
	var i := PATHS.find(path)
	if i < 0 or not _levels.has(peer_id):
		return 0
	return mini(MAX_LEVEL, int(_levels[peer_id][i]))


# =========================================================================
# ability slots (sweep 4a, docs/SWEEP4A.md "Controls, ability slots and HUD, scanner")
# =========================================================================

## This player's 4 ability slots, ability id or "" for empty. Never call this to add an ability
## (it does not create the entry lazily on clients that should not invent one); use add_ability().
func slots_for(peer_id: int) -> Array:
	if not _slots.has(peer_id):
		_slots[peer_id] = ["", "", "", ""]
	return _slots[peer_id]


## Host: `id` goes into the first empty slot. Refuses (returns false, the slots unchanged) once
## the player already has MAX_SLOTS abilities, or if `id` is already in a slot (idempotent).
func add_ability(peer_id: int, id: String) -> bool:
	var arr: Array = slots_for(peer_id)
	if arr.has(id):
		return true
	var i := arr.find("")
	if i < 0:
		return false
	arr[i] = id
	return true


## Which slot `id` is in for this player, or -1.
func slot_of(peer_id: int, id: String) -> int:
	return slots_for(peer_id).find(id)


## GRAFTING chunk C, host: take an ability away again (its slot empties and its level goes to 0).
## Swapping a grafted Hive eye back out is the only thing that does this today.
func clear_ability(peer_id: int, id: String) -> void:
	var arr: Array = slots_for(peer_id)
	var i := arr.find(id)
	if i >= 0:
		arr[i] = ""
	var path: String = String(ABILITY_ID_TO_PATH.get(id, ""))
	var pi := PATHS.find(path)
	if pi >= 0 and _levels.has(peer_id):
		var lv: Array = (_levels[peer_id] as Array).duplicate()
		lv[pi] = 0
		_levels[peer_id] = lv
	if id == "puppet" and _puppet.has(peer_id):
		_end_puppet(peer_id, "")


## Host (grafting, dev and tests): set the level of an ability directly. `id` must be a known
## ability id (echo / puppet); a level of 1 or more also grants the slot. This is the whole
## earning path now that brains are gone -- see the note at the top of this file.
func set_level(peer_id: int, id: String, lvl: int) -> void:
	var path: String = String(ABILITY_ID_TO_PATH.get(id, ""))
	if path == "":
		return
	var i := PATHS.find(path)
	var arr: Array = _levels.get(peer_id, [0, 0]).duplicate()
	arr[i] = clampi(lvl, 0, MAX_LEVEL)
	_levels[peer_id] = arr
	if lvl >= 1:
		add_ability(peer_id, id)


func echo_radius(lvl: int) -> float:
	return ECHO_RADIUS + ECHO_RADIUS_PER_LEVEL * lvl


func echo_seconds(lvl: int) -> float:
	return ECHO_SECONDS + ECHO_SECONDS_PER_LEVEL * lvl


func puppet_range(lvl: int) -> float:
	return PUPPET_RANGE + PUPPET_RANGE_PER_LEVEL * lvl


## How long you drive the Hive once you are in it (the fly-in comes on top).
func puppet_seconds(lvl: int) -> float:
	return PUPPET_SECONDS + PUPPET_SECONDS_PER_LEVEL * lvl


## Host: seconds until an ability is ready for this player (0 = ready).
func cooldown_left(peer_id: int, path: String) -> float:
	var key := ("puppet:%d" if path == "hive" else "echo:%d") % peer_id
	return maxf(0.0, float(_cd.get(key, -1.0)) - float(game.world_time))


## Host: game over. Every ability goes with the money (grafts go at the same time, and they are
## what grants them, so nothing is left dangling).
func on_reset() -> void:
	for peer in _puppet.keys():
		_end_puppet(peer, "")
	_levels.clear()
	_cd.clear()
	_press_grace.clear()
	_hint_at.clear()
	_slots.clear()


# =========================================================================
# the ability (Alt+1..4)
# =========================================================================

## Host: p pressed Alt+(slot_idx+1). Per-slot dispatch: each slot's ability (if any) runs on its
## own cooldown (echo:/puppet: keys in _cd, unchanged by the slot it sits in). Pressing the slot again
## while its ability is active (Puppet) ends it.
func ability_slot(p: Node, slot_idx: int) -> void:
	if game == null or not game.is_host() or p == null:
		return
	var peer: int = p.peer_id
	var arr: Array = slots_for(peer)
	if slot_idx < 0 or slot_idx >= arr.size():
		return
	var id := String(arr[slot_idx])
	if id == "":
		last_result = "nothing"
		if float(game.world_time) - float(_hint_at.get(peer, -99.0)) > 1.0:
			_hint_at[peer] = game.world_time
			game.tell(p, "Nothing happens.", 1.5)
		return
	if id == "puppet" and _puppet.has(peer):
		_end_puppet(peer, "")
		last_result = "puppet_end"
		return
	if float(game.world_time) < float(_press_grace.get(peer, -1.0)):
		last_result = "grace"
		return
	if not p.alive or p.downed:
		last_result = "down"
		return
	var path: String = String(ABILITY_ID_TO_PATH.get(id, ""))
	var lvl := level(peer, path)
	var left := cooldown_left(peer, path)
	if left > 0.0:
		last_result = "cooldown"
		game.tell(p, "%s is not ready yet (%d s)." % [ABILITY_NAME[path], ceili(left)], 1.5)
		return
	if path == "sonographer":
		_echo(p, lvl)
	else:
		_start_puppet(p, lvl)


func _echo(p: Node, lvl: int) -> void:
	var pos: Vector3 = p.global_position
	_cd["echo:%d" % p.peer_id] = float(game.world_time) + ECHO_COOLDOWN
	game.emit_noise(pos + Vector3.UP * 1.5, ECHO_NOISE, "echo")
	_emit("ab_echo", {"id": p.peer_id, "pos": pos, "r": echo_radius(lvl), "s": echo_seconds(lvl)})
	last_result = "echo"


## The nearest Hive within range of p, through walls; null if none. Sedated ones do not count, nor
## one somebody else is already driving.
func nearest_hive(p: Node, range_m: float) -> Node:
	var best: Node = null
	var best_d := range_m
	for m in game.monsters.values():
		if m == null or not is_instance_valid(m) or String(m.kind) != HIVE:
			continue
		if m.has_method("is_sedated") and m.is_sedated():
			continue
		if int(m.get("puppet_by")) != 0:
			continue
		var d: float = (m.global_position as Vector3).distance_to(p.global_position)
		if d <= best_d:
			best_d = d
			best = m
	return best


func _start_puppet(p: Node, lvl: int) -> void:
	if p.carrying != 0 or p.operating:
		last_result = "busy"
		game.tell(p, "Not now: your hands are busy.", 1.5)
		return
	var m := nearest_hive(p, puppet_range(lvl))
	if m == null:
		last_result = "no_hive"
		game.tell(p, "No Hive close enough to climb into.", 2.0)
		return
	var peer: int = p.peer_id
	# The seconds only start once the local fly-in has landed, so the authoritative end time carries
	# the flight too, and the Hive stands still (already out of its own head) until then.
	var arrive := float(game.world_time) + PuppetViewScript.FLIGHT_IN
	_puppet[peer] = [int(m.monster_id), snappedf(arrive + puppet_seconds(lvl), 0.1)]
	_puppet_hp[peer] = int(p.hp)
	m.puppet_by = peer
	m.puppet_from = arrive
	p.puppeting = true
	p.puppet_move = Vector2.ZERO
	p.puppet_yaw = (m as Node3D).rotation.y
	_emit("ab_puppet", {"id": peer, "on": true})
	last_result = "puppet"


## Host: the puppeting ends; the Hive gets its own head back. `why` ("" for a quiet end) goes to
## that player.
func _end_puppet(peer: int, why: String) -> void:
	if not _puppet.has(peer):
		return
	var m = game.monsters.get(int(_puppet[peer][0]))
	if m != null and is_instance_valid(m) and int(m.get("puppet_by")) == peer:
		m.puppet_release()
	_puppet.erase(peer)
	_puppet_hp.erase(peer)
	_cd["puppet:%d" % peer] = float(game.world_time) + PUPPET_COOLDOWN
	_press_grace[peer] = float(game.world_time) + PUPPET_PRESS_GRACE
	var p = game.players.get(peer)
	if p != null and is_instance_valid(p):
		p.puppeting = false
		p.puppet_move = Vector2.ZERO
		if why != "":
			game.tell(p, why, 2.5)
	_emit("ab_puppet", {"id": peer, "on": false})


## Host, every frame. Snap back when the Hive dies, is strapped or goes under, or when your own
## body is hurt, stunned, downed, carried or grabbed; come back quietly when the time is up. A hit
## on the HIVE does not end it: it knocks the Hive about with you in it (Monster._physics_process).
func _tick_puppet() -> void:
	for peer in _puppet.keys():
		var p = game.players.get(peer)
		if p == null or not is_instance_valid(p):
			var gone = game.monsters.get(int(_puppet[peer][0]))
			if gone != null and is_instance_valid(gone) and int(gone.get("puppet_by")) == int(peer):
				gone.puppet_release()
			_puppet.erase(peer)
			_puppet_hp.erase(peer)
			continue
		var m = game.monsters.get(int(_puppet[peer][0]))
		if m == null or not is_instance_valid(m):
			_end_puppet(peer, "The Hive is gone. You snap back into your body.")
		elif m.has_method("is_sedated") and m.is_sedated():
			_end_puppet(peer, "The Hive goes under. You are back in your body.")
		elif not p.alive or p.downed or int(p.hp) < int(_puppet_hp.get(peer, p.hp)) or float(p.stun) > 0.0 or p.carried_by != 0 or int(p.held_by) >= 0:
			_end_puppet(peer, "Something hits you. You snap back into your body.")
		elif float(game.world_time) >= float(_puppet[peer][1]):
			_end_puppet(peer, "")


## Every machine: is the LOCAL player inside a Hive right now (the fly-back included)?
func local_puppet_active() -> bool:
	return puppet_view != null and puppet_view.active


## Every machine: the camera main.gd should render through (Puppet), else null.
func camera() -> Camera3D:
	if local_puppet_active() and game.monsters.has(puppet_view.monster_id):
		return puppet_view.camera
	return null


## Every machine: the local player pressed Esc while puppeting (same as pressing its slot again).
func local_exit() -> void:
	var me = game.local_player() if game != null else null
	if me == null:
		return
	var i := slot_of(me.peer_id, "puppet")
	if i >= 0:
		me.ability_slot_press[i] = int(me.ability_slot_press[i]) + 1


# =========================================================================
# frame
# =========================================================================

func physics_tick(_delta: float) -> void:
	if game == null:
		return
	# A new level means the Echo overlay from the old one is meaningless.
	if game.level != _level_node:
		_level_node = game.level
		echo_view.stop()
	if game.is_host():
		_tick_puppet()
	var me = game.local_player()
	var h = _puppet.get(me.peer_id) if me != null else null
	if h != null:
		puppet_view.set_target(int(h[0]), float(h[1]))
	else:
		puppet_view.set_target(-1, 0.0)


# =========================================================================
# networking
# =========================================================================

## Host -> clients in the global snapshot field `ab`. Copies, quantized.
func net_state() -> Dictionary:
	var lv := {}
	for peer in _levels.keys():
		var a: Array = _levels[peer]
		lv[peer] = [int(a[0]), int(a[1])]
	var pp := {}
	for peer in _puppet.keys():
		pp[peer] = [int(_puppet[peer][0]), snappedf(float(_puppet[peer][1]), 0.1)]
	var sl := {}
	for peer in _slots.keys():
		sl[peer] = (_slots[peer] as Array).duplicate()
	return {"lv": lv, "pp": pp, "sl": sl}


func apply_net_state(s: Dictionary) -> void:
	if game == null or game.is_host():
		return
	_levels = (s.get("lv", {}) as Dictionary).duplicate(true)
	_puppet = (s.get("pp", {}) as Dictionary).duplicate(true)
	_slots = (s.get("sl", {}) as Dictionary).duplicate(true)


## Host: an event everywhere, this machine included.
func _emit(kind: String, data: Dictionary) -> void:
	on_event(kind, data)
	game._broadcast(kind, data)


func on_event(kind: String, data: Dictionary) -> void:
	match kind:
		"ab_echo":
			var pos: Vector3 = data.get("pos", Vector3.ZERO)
			var shrieker := int(data.get("id", 0))
			var mine := shrieker == Net.my_id()
			# SWEEP 4A HOOK (Echo polish, chunk 4): every machine, not just the shrieker's, so the
			# shriek visibly comes from whoever used it (docs/SWEEP4A.md "Echo").
			_echo_pose_until[shrieker] = float(game.world_time) + 0.5
			_spawn_echo_pulse(pos)
			if mine:
				Audio.play("ability_shriek", null, 0.0)
				var me = game.local_player()
				if me != null:
					last_echo = {"pos": pos, "r": float(data.get("r", ECHO_RADIUS)), "s": float(data.get("s", ECHO_SECONDS)), "t": game.world_time}
					echo_view.start(me, pos, float(data.get("r", ECHO_RADIUS)), float(data.get("s", ECHO_SECONDS)))
			else:
				Audio.play("ability_shriek", pos + Vector3.UP * 1.5, 6.0)
		"ab_puppet":
			pass   # the local view follows `_puppet`; the event keeps the one-off moment ordered


## SWEEP 4A HOOK (Echo polish, chunk 4): a quick expanding ring at `pos`, on every machine, so a
## shriek is visible as well as audible, whether or not you are the one who used it.
func _spawn_echo_pulse(pos: Vector3) -> void:
	if game == null or game.level == null or not is_instance_valid(game.level):
		return
	var ring := MeshInstance3D.new()
	ring.name = "EchoPulse"
	var torus := TorusMesh.new()
	torus.inner_radius = 0.05
	torus.outer_radius = 0.3
	torus.rings = 16
	ring.mesh = torus
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(0.6, 0.85, 1.0, 0.85)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.emission_enabled = true
	m.emission = Color(0.5, 0.8, 1.0)
	m.emission_energy_multiplier = 1.6
	ring.material_override = m
	ring.position = pos + Vector3.UP * 1.2
	ring.rotation_degrees.x = 90.0
	game.level.add_child(ring)
	var tw := ring.create_tween()
	tw.tween_property(ring, "scale", Vector3.ONE * 12.0, 0.6).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(m, "albedo_color:a", 0.0, 0.6)
	tw.tween_callback(ring.queue_free)


# =========================================================================
# dev mode (scripts/dev/dev_controller.gd forwards "ab_*" requests here) and warmup
# =========================================================================

func dev_request(sender: int, action: String, a: Dictionary) -> void:
	if not game.is_host():
		return
	match action:
		"ab_levels":
			var id := int(a.get("id", sender))
			var lvl := int(a.get("level", MAX_LEVEL))
			for ability_id in ABILITY_ID_TO_PATH.keys():
				set_level(id, String(ability_id), lvl)
			game.say("Abilities: Puppet %d, Echo %d." % [level(id, "hive"), level(id, "sonographer")], 2.5)
		"ab_reset":
			on_reset()
			game.say("Abilities reset.", 2.0)


static func warm(parent: Node3D) -> void:
	EchoViewScript.warm(parent)
	PuppetViewScript.warm(parent)
