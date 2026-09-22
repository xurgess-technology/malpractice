extends Node
## The two surgeon abilities and the four slots they sit in: Echo (a shriek that outlines everything
## nearby through walls) and Hive Eyes (see through a nearby Hive for a few seconds). A child
## "Abilities" of Game on every machine.
##
## Where levels come from: **grafting**. An eye_hive graft grants Hive Eyes at level 1 and takes it
## away when the part comes out (scripts/grafting/grafts.gd PART_ABILITY). Brains and the break-room
## blender used to be the other source and are gone (docs/backlog/ABILITIES_REMOVED.md), which is
## why a level is now simply SET rather than accumulated: there are no fractional points any more,
## `set_level()` is the whole earning path, and Echo has no source in the game yet.
##
## Authority: the host decides everything (levels, slots, cooldowns, who is looking through which
## Hive). Clients get it through `net_state()` (global snapshot field `ab`), the Player field
## `hive_view` (report key `hv`) and the reliable events `ab_echo` and `ab_hive`. The visuals (the
## Echo view, the Hive Eyes camera) run on every machine from that state.

const EchoViewScript := preload("res://scripts/abilities/echo_view.gd")
const HiveViewScript := preload("res://scripts/abilities/hive_view.gd")

## The ability paths. The ORDER MATTERS: it indexes the per-player level array.
const PATHS := ["hive", "sonographer"]
const ABILITY_NAME := {"hive": "Hive Eyes", "sonographer": "Echo"}
## SWEEP 4A HOOK (controls): ability ids, and the ability-slot cap. add_ability()/set_level()/
## slot_of() are independent of how a level is earned, so slot code never reads levels directly
## except through level().
const ABILITY_ID := {"sonographer": "echo", "hive": "hive_in"}
const ABILITY_ID_TO_PATH := {"echo": "sonographer", "hive_in": "hive"}
const MAX_SLOTS := 4
const HIVE := "hive"   # Monster.HIVE (monsters worker); the string, so this runs without it

const MAX_LEVEL := 3

const ECHO_COOLDOWN := 20.0
const ECHO_NOISE := 1.2
const ECHO_RADIUS := 12.0
const ECHO_RADIUS_PER_LEVEL := 6.0
const ECHO_SECONDS := 2.5
const ECHO_SECONDS_PER_LEVEL := 0.75

const HIVE_COOLDOWN := 12.0   # counted from when the view ends
const HIVE_RANGE := 20.0
const HIVE_RANGE_PER_LEVEL := 10.0
const HIVE_SECONDS := 5.0
const HIVE_SECONDS_PER_LEVEL := 2.0
## After a Hive Eyes view ends, R presses from that player are ignored this long (the press that
## ended it on the client may arrive after the host already ended it).
const HIVE_PRESS_GRACE := 0.5

var game: Node = null

## Replicated. peer id -> [hive level, sonographer level] (ints, 0..MAX_LEVEL).
var _levels: Dictionary = {}
## Replicated. peer id -> [monster id, world_time it ends].
var _hive: Dictionary = {}
## Replicated. peer id -> Array[MAX_SLOTS] of ability id ("" empty). Host authoritative; a new
## ability goes into the first empty slot the moment set_level() takes it to 1 or more. See
## add_ability() / set_level() / slot_of() below.
var _slots: Dictionary = {}

# SWEEP 4A HOOK (Echo polish, chunk 4): peer id -> world_time the shriek pose ends. Not
# replicated: every machine sets it the same way, locally, from the reliable ab_echo event.
var _echo_pose_until: Dictionary = {}

# host only
var _hive_hp: Dictionary = {}          # peer id -> hp when the view started
var _cd: Dictionary = {}               # "echo:<peer>" / "hive:<peer>" -> world_time it is ready
var _press_grace: Dictionary = {}      # peer id -> world_time before which R is ignored
var _hint_at: Dictionary = {}          # peer id -> world_time of the last "Nothing happens."

var _level_node: Node = null

var echo_view: Node = null
var hive_view: Node = null

## Test seams: the last Echo started on this machine and the last ability result on the host.
var last_echo := {}
var last_result := ""


func setup(g: Node) -> void:
	game = g
	echo_view = EchoViewScript.new()
	echo_view.name = "EchoView"
	add_child(echo_view)
	echo_view.setup(g)
	hive_view = HiveViewScript.new()
	hive_view.name = "HiveView"
	add_child(hive_view)
	hive_view.setup(g)


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
	if id == "hive_in" and _hive.has(peer_id):
		_end_hive(peer_id, "")


## Host (grafting, dev and tests): set the level of an ability directly. `id` must be a known
## ability id (echo / hive_in); a level of 1 or more also grants the slot. This is the whole
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


func hive_range(lvl: int) -> float:
	return HIVE_RANGE + HIVE_RANGE_PER_LEVEL * lvl


func hive_seconds(lvl: int) -> float:
	return HIVE_SECONDS + HIVE_SECONDS_PER_LEVEL * lvl


## Host: seconds until an ability is ready for this player (0 = ready).
func cooldown_left(peer_id: int, path: String) -> float:
	var key := ("hive:%d" if path == "hive" else "echo:%d") % peer_id
	return maxf(0.0, float(_cd.get(key, -1.0)) - float(game.world_time))


## Host: game over. Every ability goes with the money (grafts go at the same time, and they are
## what grants them, so nothing is left dangling).
func on_reset() -> void:
	for peer in _hive.keys():
		_end_hive(peer, "")
	_levels.clear()
	_cd.clear()
	_press_grace.clear()
	_hint_at.clear()
	_slots.clear()


# =========================================================================
# the ability (Alt+1..4)
# =========================================================================

## Host: p pressed Alt+(slot_idx+1). Per-slot dispatch: each slot's ability (if any) runs on its
## own cooldown (echo:/hive: keys in _cd, unchanged by the slot it sits in). Pressing the slot again
## while its ability is active (Hive Eyes) ends it.
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
	if id == "hive_in" and _hive.has(peer):
		_end_hive(peer, "")
		last_result = "hive_end"
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
		_start_hive(p, lvl)


func _echo(p: Node, lvl: int) -> void:
	var pos: Vector3 = p.global_position
	_cd["echo:%d" % p.peer_id] = float(game.world_time) + ECHO_COOLDOWN
	game.emit_noise(pos + Vector3.UP * 1.5, ECHO_NOISE, "echo")
	_emit("ab_echo", {"id": p.peer_id, "pos": pos, "r": echo_radius(lvl), "s": echo_seconds(lvl)})
	last_result = "echo"


## The nearest Hive within range of p, through walls; null if none. Sedated ones do not count.
func nearest_hive(p: Node, range_m: float) -> Node:
	var best: Node = null
	var best_d := range_m
	for m in game.monsters.values():
		if m == null or not is_instance_valid(m) or String(m.kind) != HIVE:
			continue
		if m.has_method("is_sedated") and m.is_sedated():
			continue
		var d: float = (m.global_position as Vector3).distance_to(p.global_position)
		if d <= best_d:
			best_d = d
			best = m
	return best


func _start_hive(p: Node, lvl: int) -> void:
	if p.carrying != 0 or p.operating:
		last_result = "busy"
		game.tell(p, "Not now: your hands are busy.", 1.5)
		return
	var m := nearest_hive(p, hive_range(lvl))
	if m == null:
		last_result = "no_hive"
		game.tell(p, "No Hive close enough to see through.", 2.0)
		return
	var peer: int = p.peer_id
	# SWEEP 4A HOOK (Hive Eyes fly-through, chunk 4): the duration only starts once the local
	# fly-through has landed, so the authoritative end time carries the flight time too.
	_hive[peer] = [int(m.monster_id), snappedf(float(game.world_time) + HiveViewScript.FLIGHT_IN + hive_seconds(lvl), 0.1)]
	_hive_hp[peer] = int(p.hp)
	p.hive_view = true
	_emit("ab_hive", {"id": peer, "on": true})
	last_result = "hive"


## Host: the view ends. `why` ("" for a quiet end) goes to that player.
func _end_hive(peer: int, why: String) -> void:
	if not _hive.has(peer):
		return
	_hive.erase(peer)
	_hive_hp.erase(peer)
	_cd["hive:%d" % peer] = float(game.world_time) + HIVE_COOLDOWN
	_press_grace[peer] = float(game.world_time) + HIVE_PRESS_GRACE
	var p = game.players.get(peer)
	if p != null and is_instance_valid(p):
		p.hive_view = false
		if why != "":
			game.tell(p, why, 2.5)
	_emit("ab_hive", {"id": peer, "on": false})


func _tick_hive() -> void:
	for peer in _hive.keys():
		var p = game.players.get(peer)
		if p == null or not is_instance_valid(p):
			_hive.erase(peer)
			_hive_hp.erase(peer)
			continue
		var m = game.monsters.get(int(_hive[peer][0]))
		if m == null or not is_instance_valid(m):
			_end_hive(peer, "The Hive is gone. You snap back into your body.")
		elif m.has_method("is_sedated") and m.is_sedated():
			_end_hive(peer, "The Hive goes under. You are back in your body.")
		elif not p.alive or p.downed or int(p.hp) < int(_hive_hp.get(peer, p.hp)) or float(p.stun) > 0.0 or p.carried_by != 0 or int(p.held_by) >= 0:
			_end_hive(peer, "Something hits you. You snap back into your body.")
		elif float(game.world_time) >= float(_hive[peer][1]):
			_end_hive(peer, "")


## Every machine: is the LOCAL player looking through a Hive right now?
func local_hive_active() -> bool:
	return hive_view != null and hive_view.active


## Every machine: the camera main.gd should render through (Hive Eyes), else null.
func camera() -> Camera3D:
	if local_hive_active() and game.monsters.has(hive_view.monster_id):
		return hive_view.camera
	return null


## Every machine: the local player pressed Esc during Hive Eyes (same as pressing its slot again).
func local_exit() -> void:
	var me = game.local_player() if game != null else null
	if me == null:
		return
	var i := slot_of(me.peer_id, "hive_in")
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
		_tick_hive()
	var me = game.local_player()
	var h = _hive.get(me.peer_id) if me != null else null
	if h != null:
		hive_view.set_target(int(h[0]), float(h[1]))
	else:
		hive_view.set_target(-1, 0.0)


# =========================================================================
# networking
# =========================================================================

## Host -> clients in the global snapshot field `ab`. Copies, quantized.
func net_state() -> Dictionary:
	var lv := {}
	for peer in _levels.keys():
		var a: Array = _levels[peer]
		lv[peer] = [int(a[0]), int(a[1])]
	var hv := {}
	for peer in _hive.keys():
		hv[peer] = [int(_hive[peer][0]), snappedf(float(_hive[peer][1]), 0.1)]
	var sl := {}
	for peer in _slots.keys():
		sl[peer] = (_slots[peer] as Array).duplicate()
	return {"lv": lv, "hv": hv, "sl": sl}


func apply_net_state(s: Dictionary) -> void:
	if game == null or game.is_host():
		return
	_levels = (s.get("lv", {}) as Dictionary).duplicate(true)
	_hive = (s.get("hv", {}) as Dictionary).duplicate(true)
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
		"ab_hive":
			pass   # the local view follows `_hive`; the event keeps the one-off moment ordered


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
# dev room (scripts/dev/dev_room.gd forwards "ab_*" requests here) and warmup
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
			game.say("Abilities: Hive Eyes %d, Echo %d." % [level(id, "hive"), level(id, "sonographer")], 2.5)
		"ab_reset":
			on_reset()
			game.say("Abilities reset.", 2.0)


static func warm(parent: Node3D) -> void:
	EchoViewScript.warm(parent)
	HiveViewScript.warm(parent)
