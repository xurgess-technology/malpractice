extends Node
## The OR's gurney (2026-09-24, `or-gurney`): a player-pushed version of the paramedics' gurney
## (same model, scripts/loop/crew.gd make_gurney_model). It starts every shift parked in the OR.
## A surgeon with empty hands takes the handle (E) and pushes it at walking speed -- faster than the
## over-the-shoulder carry or the monster drag -- but has to bring it to whoever needs it: a downed
## teammate or a sedated monster within LOAD_REACH of it goes on with E. They ride it; at the OR,
## E with the gurney beside a free table puts them on the table exactly the way a carry or a drag
## does (game.lay_on_table / combat.strap_monster), so the stitches and Eyeball Extraction start as
## they always have. docs/CONTRACTS.md "The OR gurney" has the rules.
##
## Child "Gurney" of Game on every machine. Host authoritative; `net_state()` rides the snapshot as
## the global field "gu". While someone pushes it the gurney has no position of its own: every
## machine derives it from its copy of the pusher (pose()), so it never lags its pusher on any
## screen and needs nothing sent while it rolls. A downed rider has Player.on_gurney ("og") and is
## pinned by game.pinned_pose; a monster rider has `dragged_by == Combat.GURNEY_DRAGGER` and is
## pinned by combat.monster_pin, so both ride with no extra state.

const CrewScript := preload("res://scripts/loop/crew.gd")
const CombatScript := preload("res://scripts/combat/combat.gd")

## The pusher's feet to the gurney's middle (the handle is 1.02 m back from the middle; the
## pusher stands a little behind it, arms out).
const HANDLE_BACK := 1.5
## The middle to the front end: what doors sense and get pushed open by.
const NOSE := 1.05
## Walking speed: the whole point of fetching the gurney is that it beats CARRY_SPEED_K (0.6).
const SPEED_K := 1.0
## How fast a pusher can swing it round (radians a second); the mouse cannot spin a 2 m gurney.
const TURN_RATE := 2.4
## The mattress top above the floor, where a rider lies.
const TOP_Y := 0.8
## How close (to the gurney's centre line) a body must lie to be loaded from the handle.
const LOAD_REACH := 1.8
## How close the gurney's middle must be to a table's middle to unload onto it.
const TABLE_REACH := 2.8
## The gurney's solid box (the crew's blocker), raised off the floor so a lip never catches it.
const BOX_SIZE := Vector3(0.66, 0.75, 2.05)
const BOX_Y := 0.25 + 0.375
const AIM_ID := "gurney"
const RATTLE_EVERY := 1.15
const NOISE_ROLL := 0.3

var game: Node = null
## The rest pose (floor under its middle) while nobody pushes it. Host authoritative.
var pos := Vector3.ZERO
var yaw := 0.0
## Peer id of whoever pushes it, 0 for nobody.
var pusher := 0
## "" empty, "player" a downed teammate (rider_id = peer id), "monster" (rider_id = monster id).
var rider_kind := ""
var rider_id := 0
## Where it parks at the start of every shift (level_info.gurney, else beside the OR table).
var park_pos := Vector3.INF
var park_yaw := 0.0

var node: Node3D = null
var _model: Node3D = null
var _blocker: StaticBody3D = null
var _aim: Area3D = null
var _rattle := 0.0
var _last_origin := Vector3.INF
var _speed := 0.0
var _wheel := 0.0
var _noise_t := 0.0


func setup(g: Node) -> void:
	game = g


# ---------------------------------------------------------------------------
# queries (every machine)

func pusher_node() -> Node:
	if pusher == 0 or game == null:
		return null
	var q = game.players.get(pusher)
	return q if q != null and is_instance_valid(q) and q.is_inside_tree() else null


## Where the gurney is this frame: in front of its pusher, else where it was left.
func pose() -> Transform3D:
	var q := pusher_node()
	if q != null:
		var b := Basis(Vector3.UP, q.rotation.y)
		return Transform3D(b, q.global_position + b * Vector3(0.0, 0.0, -HANDLE_BACK))
	return Transform3D(Basis(Vector3.UP, yaw), pos)


func pose_yaw() -> float:
	var q := pusher_node()
	return float(q.rotation.y) if q != null else yaw


## The front end (the door sensor's point).
func nose() -> Vector3:
	var t := pose()
	return t.origin - t.basis.z * NOSE


## The table-style frame a lying player uses (game.pinned_pose, Player._update_down_pose): a table's
## long axis is its local X with the head at -X; the gurney's is its Z. The head goes at the handle
## end, so the rider looks down their own feet the way it is being pushed.
func lie_yaw() -> float:
	return pose_yaw() + PI * 0.5


func lie_top() -> Vector3:
	return pose().origin + Vector3.UP * TOP_Y


func rider_player_pose() -> Transform3D:
	var b := Basis(Vector3.UP, lie_yaw())
	return Transform3D(b, lie_top() + b * Vector3(-0.8, 0.0, 0.0))


## Where a monster rider's pin is (combat.monster_pin): lying along Z, head toward the handle.
func monster_pose() -> Transform3D:
	var t := pose()
	return Transform3D(t.basis, t.origin + Vector3.UP * (TOP_Y - 0.1))


func has_rider() -> bool:
	return rider_kind != ""


func rides(kind: String, id: int) -> bool:
	return rider_kind == kind and rider_id == id


func rider_name() -> String:
	if rider_kind == "player":
		var p = game.players.get(rider_id)
		return String(p.player_name) if p != null and is_instance_valid(p) else "them"
	if rider_kind == "monster":
		var m = game.monsters.get(rider_id)
		return "the " + CombatScript.monster_name(String(m.kind)) if m != null and is_instance_valid(m) else "it"
	return ""


## The closest thing that could go on the gurney from where it stands: {kind, id, aim, name} or {}.
func load_candidate(q: Node) -> Dictionary:
	if has_rider():
		return {}
	var t := pose()
	var best := {}
	var best_d := LOAD_REACH
	for p in game.players.values():
		if p == q or not _loadable_player(p):
			continue
		var d := _to_centre_line(t, p.global_position)
		if d < best_d:
			best_d = d
			best = {"kind": "player", "id": int(p.peer_id), "aim": "pl_%d" % int(p.peer_id), "name": String(p.player_name)}
	for m in game.monsters.values():
		if not _loadable_monster(m):
			continue
		var d := _to_centre_line(t, m.global_position)
		if d < best_d:
			best_d = d
			best = {"kind": "monster", "id": int(m.monster_id), "aim": "mo_%d" % int(m.monster_id),
				"name": "the " + CombatScript.monster_name(String(m.kind))}
	return best


func _loadable_player(p: Node) -> bool:
	return p != null and is_instance_valid(p) and p.alive and p.downed and p.carried_by == 0 and not p.on_table \
		and not p.on_gurney and int(p.held_by) < 0


func _loadable_monster(m: Node) -> bool:
	if m == null or not is_instance_valid(m) or game.combat == null:
		return false
	return game.combat.is_sedated(m) and game.combat.dragger_of(m) == null and int(m.get("dragged_by")) == 0


## Horizontal distance from a point to the gurney's long axis (a segment the length of the gurney).
static func _to_centre_line(t: Transform3D, at: Vector3) -> float:
	var local := t.affine_inverse() * at
	var z := clampf(local.z, -BOX_SIZE.z * 0.5, BOX_SIZE.z * 0.5)
	return Vector2(local.x, local.z - z).length()


## The table the rider would go onto from here: {id, index} (index -1 = the level's player table), or {}.
func table_target() -> Dictionary:
	if not has_rider() or game.phase != game.Phase.SHIFT:
		return {}
	var at := pose().origin
	var best := {}
	var best_d := TABLE_REACH
	if rider_kind == "player":
		if game.downed_any_table:
			if not game.player_table.is_empty():
				return {}   # someone is already lying on a table
			for tb in game.patient_tables:
				var ti := int(tb.index)
				if not game.case_on_table(ti).is_empty() or game.loop.table_reserved(ti):
					continue
				var d := _flat(at, game.table_position(ti))
				if d < best_d:
					best_d = d
					best = {"id": game.table_interact_id(ti), "index": ti}
		elif not game.player_table.is_empty() and game.someone_on_table() == null:
			if _flat(at, game.player_table.position) < best_d:
				best = {"id": "player_table", "index": -1}
		return best
	var m = game.monsters.get(rider_id)
	if m == null or not is_instance_valid(m) or not Procedures.is_monster(String(m.kind)):
		return {}
	for tb in game.patient_tables:
		var ti := int(tb.index)
		if game.combat.strap_problem(ti) != "":
			continue
		var d := _flat(at, game.table_position(ti))
		if d < best_d:
			best_d = d
			best = {"id": game.table_interact_id(ti), "index": ti}
	return best


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


## What the pusher sees: [aim id, prompt for E, what the drop key does ("" none)].
func pusher_aim(q: Node) -> Array:
	if has_rider():
		var off := "tip %s off" % rider_name()
		var t := table_target()
		if not t.is_empty():
			return [String(t.id), "Put %s on the table" % rider_name(), off]
		return ["", "Let go of the gurney", off]
	var c := load_candidate(q)
	if not c.is_empty():
		return [String(c.aim), "Load %s onto the gurney" % String(c.name), "let go"]
	return ["", "Let go of the gurney", ""]


## What aiming at the parked gurney offers q.
func aim_prompt(q: Node) -> String:
	if q == null or not q.alive or q.downed or q.on_table or q.on_gurney or q.carried_by != 0 or int(q.held_by) >= 0:
		return ""
	if pusher != 0:
		return ""
	if q.carrying != 0:
		if game.corpses.is_body(q.carrying):
			return ""
		if has_rider():
			return "!Someone is already on the gurney."
		var who = game.players.get(q.carrying)
		return "Place %s on the gurney" % (who.player_name if who != null else "them")
	if q.dragging_monster >= 0:
		return ""   # combat.drag_aim offers it
	if not q.hands_empty():
		return "!Empty your hands to push the gurney."
	if q.operating:
		return ""
	return "Push the gurney" if not has_rider() else "Push the gurney (%s on it)" % rider_name()


# ---------------------------------------------------------------------------
# host

func can_push(q: Node) -> bool:
	return q != null and is_instance_valid(q) and q.alive and not q.downed and q.stun <= 0.0 and q.carrying == 0 \
		and q.carried_by == 0 and not q.on_table and not q.on_gurney and int(q.held_by) < 0 and q.dragging_monster < 0 \
		and not q.operating and q.hands_empty() and not bool(q.get("puppeting"))


## E on the parked gurney.
func used(q: Node) -> void:
	if not game.is_host() or q == null:
		return
	if q.carrying != 0:
		take_from_carrier(q)
		return
	grab(q)


## Host: q takes the handle. The pusher is moved to the handle, facing along the gurney.
func grab(q: Node) -> bool:
	if not game.is_host() or pusher != 0 or not can_push(q):
		return false
	var t := pose()
	var b := t.basis
	var at: Vector3 = t.origin + b * Vector3(0.0, 0.0, HANDLE_BACK)
	var y := yaw
	if not game._point_is_clear(at):
		# Parked with its handle against something: take it from the other end.
		var flip := Basis(Vector3.UP, yaw + PI)
		var other: Vector3 = t.origin + flip * Vector3(0.0, 0.0, HANDLE_BACK)
		if not game._point_is_clear(other):
			game.tell(q, "There is no room to get behind the gurney.", 2.5)
			return false
		at = other
		y = wrapf(yaw + PI, -PI, PI)
		yaw = y
	at = game._floor_at(at)
	pusher = int(q.peer_id)
	game.end_operations(q)
	_face(q, at, y)
	game._broadcast("gu_grab", {"id": pusher, "pos": at, "y": y})
	game._sound("loop_gurney", t.origin + Vector3.UP * 0.6)
	return true


func _face(q: Node, at: Vector3, y: float) -> void:
	q.teleport(at)
	q._yaw = y
	q.rotation.y = y
	q.bot_yaw = y


## Every machine: the reliable "gu_grab" event; the pusher's own machine owns its position.
func on_grab(data: Dictionary) -> void:
	var q = game.players.get(int(data.get("id", 0)))
	if q == null or not is_instance_valid(q):
		return
	pusher = int(data.id)
	if q.is_local:
		_face(q, data.pos, float(data.y))


## Host: the pusher lets go; the gurney stays exactly where it is.
func release() -> void:
	if pusher == 0:
		return
	var t := pose()
	pos = t.origin
	yaw = t.basis.get_euler().y
	pusher = 0


func release_if_pusher(q: Node) -> void:
	if q != null and pusher != 0 and int(q.peer_id) == pusher:
		release()


## Host: the pusher pressed E. With a rider beside a free table it goes onto the table; with nothing
## on it, whoever lies within reach goes on; otherwise they let go.
func pusher_pressed(q: Node, aim: String) -> void:
	if not game.is_host() or q == null or int(q.peer_id) != pusher:
		return
	if has_rider():
		var t := table_target()
		if not t.is_empty():
			unload_to_table(q, int(t.index))
			return
		if aim.begins_with("table") or aim == "player_table":
			return   # the prompt promised a table that has just gone; keep the rider on
	else:
		var c := load_candidate(q)
		if not c.is_empty():
			if String(c.kind) == "player":
				_load_player(game.players[int(c.id)], q)
			else:
				_load_monster(game.monsters[int(c.id)], q)
			return
		if aim.begins_with("pl_") or aim.begins_with("mo_"):
			return   # they were loadable a moment ago on the pusher's screen; do not let go by surprise
	release()


## Host: the drop key while pushing: tip the rider off beside the gurney, or let go.
func pusher_drop(q: Node) -> void:
	if not game.is_host() or q == null or int(q.peer_id) != pusher:
		return
	if has_rider():
		tip_off()
	else:
		release()


## Host: a carrier puts their downed teammate on the parked gurney.
func take_from_carrier(q: Node) -> void:
	if not game.is_host() or pusher != 0 or has_rider() or q.carrying == 0 or game.corpses.is_body(q.carrying):
		return
	var p = game.players.get(q.carrying)
	if p == null or not is_instance_valid(p) or p.carried_by != q.peer_id:
		return
	q.carrying = 0
	p.carried_by = 0
	q.refresh_downed_visuals()
	_load_player(p, q)


## Host: a dragger puts the sedated monster on the parked gurney.
func take_from_dragger(q: Node) -> void:
	if not game.is_host() or pusher != 0 or has_rider() or game.combat == null:
		return
	var m = game.monsters.get(game.combat.dragging(q))
	if m == null or not is_instance_valid(m):
		return
	q.dragging_monster = -1
	m.dragged_by = 0
	_load_monster(m, q)


func _load_player(p: Node, by: Node) -> void:
	if p == null or not _loadable_player(p) or has_rider():
		return
	rider_kind = "player"
	rider_id = int(p.peer_id)
	p.on_gurney = true
	p.carry_hold = 0.0
	p.teleport(rider_player_pose().origin)
	if p.is_local or p.is_bot:
		p.look_along_gurney()
	p.refresh_downed_visuals()
	game._sound("downed_lift", lie_top())
	game.say("%s loaded %s onto the gurney." % [by.player_name, p.player_name], 3.0)


func _load_monster(m: Node, by: Node) -> void:
	if m == null or not is_instance_valid(m) or has_rider() or not game.combat.is_sedated(m):
		return
	rider_kind = "monster"
	rider_id = int(m.monster_id)
	m.dragged_by = CombatScript.GURNEY_DRAGGER
	game._sound("combat_drag", lie_top())
	game.say("%s loaded the %s onto the gurney." % [by.player_name, CombatScript.monster_name(String(m.kind))], 3.0)


## Host: the rider goes onto table `ti` (-1 the level's player table), by the same code as a carry
## or a drag, so the case starts exactly as it would have.
func unload_to_table(q: Node, ti: int) -> void:
	if rider_kind == "player":
		var p = game.players.get(rider_id)
		_clear_rider()
		if p == null or not is_instance_valid(p):
			return
		p.on_gurney = false
		game.lay_on_table(p, ti)
	elif rider_kind == "monster":
		var m = game.monsters.get(rider_id)
		_clear_rider()
		if m == null or not is_instance_valid(m):
			return
		m.dragged_by = 0
		game.combat.strap_monster(m, ti, q)


## Host: the rider comes off onto the floor beside the gurney.
func tip_off() -> void:
	if not has_rider():
		return
	var spot := _floor_beside()
	if rider_kind == "player":
		var p = game.players.get(rider_id)
		_clear_rider()
		if p == null or not is_instance_valid(p):
			return
		p.on_gurney = false
		p.teleport(spot)
		p.refresh_downed_visuals()
		game._broadcast("placed", {"id": p.peer_id, "pos": spot})
	else:
		var m = game.monsters.get(rider_id)
		_clear_rider()
		if m == null or not is_instance_valid(m):
			return
		if int(m.dragged_by) == CombatScript.GURNEY_DRAGGER:
			m.dragged_by = 0
		_set_monster_down(m, spot)
	game._sound("thud", spot)


## Host: a player rider is leaving the gurney some other way (bled out, left the game).
func drop_rider_player(p: Node) -> void:
	if rides("player", int(p.peer_id)):
		_clear_rider()
	p.on_gurney = false


func _floor_beside() -> Vector3:
	var t := pose()
	for side in [1.0, -1.0]:
		var at: Vector3 = t.origin + t.basis * Vector3(0.95 * side, 0.0, 0.0)
		if game._point_is_clear(at):
			return game._floor_at(at)
	return game._floor_at(t.origin + t.basis * Vector3(0.0, 0.0, HANDLE_BACK))


func _set_monster_down(m: Node, spot: Vector3) -> void:
	m.global_position = spot
	m.rotation.y = pose_yaw()
	if "_target_pos" in m:
		m._target_pos = spot
		m._target_yaw = m.rotation.y


func _clear_rider() -> void:
	rider_kind = ""
	rider_id = 0


## Host: back where it belongs for a new shift, empty and let go.
func park() -> void:
	if not game.is_host():
		return
	release()
	if rider_kind == "player":
		var p = game.players.get(rider_id)
		if p != null and is_instance_valid(p):
			p.on_gurney = false
	elif rider_kind == "monster":
		var m = game.monsters.get(rider_id)
		if m != null and is_instance_valid(m) and int(m.dragged_by) == CombatScript.GURNEY_DRAGGER:
			m.dragged_by = 0
	_clear_rider()
	if park_pos != Vector3.INF:
		pos = park_pos
		yaw = park_yaw


## Every physics frame on every machine (game._physics_process).
func physics_tick(delta: float) -> void:
	if game == null:
		return
	_sync_pusher_shapes()
	if not game.is_host():
		return
	if pusher != 0:
		var q := pusher_node()
		if q == null:
			pusher = 0   # gone: the gurney stays where it was last left
		elif not can_push(q):
			release()
	if rider_kind == "player":
		var p = game.players.get(rider_id)
		if p == null or not is_instance_valid(p) or not p.alive or not p.downed or not p.on_gurney:
			if p != null and is_instance_valid(p):
				p.on_gurney = false
			_clear_rider()
	elif rider_kind == "monster":
		var m = game.monsters.get(rider_id)
		if m == null or not is_instance_valid(m):
			_clear_rider()
		elif int(m.dragged_by) != CombatScript.GURNEY_DRAGGER or not game.combat.is_sedated(m):
			# It woke up (monster.wake cleared dragged_by): it rolls off and gets up.
			var spot := _floor_beside()
			_clear_rider()
			if int(m.dragged_by) == CombatScript.GURNEY_DRAGGER:
				m.dragged_by = 0
			_set_monster_down(m, spot)
			game.say("The %s woke up and rolled off the gurney!" % CombatScript.monster_name(String(m.kind)), 3.0)
	# Nobody is pinned to a gurney that does not carry them (a new level, a rider cleared elsewhere).
	for q in game.players.values():
		if q != null and is_instance_valid(q) and q.on_gurney and not rides("player", int(q.peer_id)):
			q.on_gurney = false
			q.refresh_downed_visuals()
	# A rolling gurney rattles, and the monsters that listen can hear it.
	if pusher != 0 and _speed > 0.5:
		_noise_t -= delta
		if _noise_t <= 0.0:
			_noise_t = 1.0
			game.emit_noise(pose().origin, NOISE_ROLL, "gurney")


## The pusher's own body gets the gurney's box as a second collision shape, so walls and shut doors
## stop the gurney the same way they stop the pusher. Only on the machine that moves that body.
func _sync_pusher_shapes() -> void:
	for p in game.players.values():
		if p == null or not is_instance_valid(p):
			continue
		var drives: bool = p.is_local or (bool(p.is_bot) and game.is_host())
		var want := drives and pusher == int(p.peer_id)
		var cs := p.get_node_or_null("GurneyShape") as CollisionShape3D
		if want and cs == null:
			cs = CollisionShape3D.new()
			cs.name = "GurneyShape"
			var box := BoxShape3D.new()
			box.size = BOX_SIZE
			cs.shape = box
			cs.position = Vector3(0.0, BOX_Y, -HANDLE_BACK)
			p.add_child(cs)
		elif not want and cs != null:
			cs.queue_free()
			p.remove_child(cs)


## The pusher's turn this frame, capped at TURN_RATE and refused when it would swing the gurney into
## something solid. Called from Player._local_step on the machine that drives the pusher.
func steer(q: Node, from_yaw: float, want_yaw: float, delta: float) -> float:
	var d := angle_difference(from_yaw, want_yaw)
	var lim := TURN_RATE * delta
	var to := from_yaw + clampf(d, -lim, lim)
	if absf(to - from_yaw) < 1e-5:
		return to
	if _box_hits(q, to) and not _box_hits(q, from_yaw):
		return from_yaw
	return to


func _box_hits(q: Node, y: float) -> bool:
	var space: PhysicsDirectSpaceState3D = q.get_world_3d().direct_space_state
	var qp := PhysicsShapeQueryParameters3D.new()
	var box := BoxShape3D.new()
	box.size = BOX_SIZE - Vector3(0.06, 0.06, 0.06)
	qp.shape = box
	var b := Basis(Vector3.UP, y)
	qp.transform = Transform3D(b, q.global_position + b * Vector3(0.0, BOX_Y, -HANDLE_BACK))
	qp.collision_mask = C.L_WORLD
	var ex: Array[RID] = [q.get_rid()]
	if _blocker != null and is_instance_valid(_blocker):
		ex.append(_blocker.get_rid())
	qp.exclude = ex
	return not space.intersect_shape(qp, 1).is_empty()


# ---------------------------------------------------------------------------
# the level and the local presentation

## Every machine, from game._add_landmarks: build it and put it where it parks.
func on_level_built(level: Node3D, info: Dictionary) -> void:
	node = null
	pusher = 0
	_clear_rider()
	_last_origin = Vector3.INF
	var spot: Dictionary = info.get("gurney", {})
	if not spot.is_empty():
		park_pos = spot.position
		park_yaw = float(spot.yaw)
	else:
		# Levels without the spot (the fallback ward): beside the OR table, lengthwise to it.
		var ty: float = float(info.get("table_yaw", 0.0))
		park_pos = game.table_pos() + Basis(Vector3.UP, ty) * Vector3(0.0, 0.0, 2.9)
		park_yaw = ty + PI * 0.5
	pos = park_pos
	yaw = park_yaw
	node = Node3D.new()
	node.name = "OrGurney"
	node.set_meta("light_dynamic", true)   # it rolls between rooms: lit like anyone else
	level.add_child(node)
	_model = CrewScript.make_gurney_model()
	node.add_child(_model)
	_blocker = StaticBody3D.new()
	_blocker.name = "Blocker"
	_blocker.collision_layer = C.L_WORLD
	_blocker.collision_mask = 0
	var bcs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = BOX_SIZE
	bcs.shape = bs
	bcs.position = Vector3(0.0, BOX_Y, 0.0)
	_blocker.add_child(bcs)
	node.add_child(_blocker)
	_aim = GurneyAim.new()
	_aim.name = "Aim_gurney"
	_aim.gurney = self
	_aim.collision_layer = C.L_INTERACT
	_aim.collision_mask = 0
	_aim.monitoring = false
	_aim.add_to_group("interactable")
	_aim.set_meta("interact_id", AIM_ID)
	var acs := CollisionShape3D.new()
	var ab := BoxShape3D.new()
	ab.size = BOX_SIZE + Vector3(0.14, 0.3, 0.1)
	acs.shape = ab
	acs.position = Vector3(0.0, BOX_Y + 0.1, 0.0)
	_aim.add_child(acs)
	node.add_child(_aim)
	node.global_transform = pose()


func _process(delta: float) -> void:
	if node == null or not is_instance_valid(node):
		return
	var t := pose()
	node.global_transform = t
	var pushed := pusher != 0
	# Pushed, its box rides on the pusher's body instead (_sync_pusher_shapes), and the handle is
	# taken, so nothing else can aim at it.
	if _blocker != null:
		_blocker.collision_layer = 0 if pushed else C.L_WORLD
	if _aim != null:
		_aim.collision_layer = 0 if pushed else C.L_INTERACT
	var moved := 0.0 if _last_origin == Vector3.INF else Vector2(t.origin.x - _last_origin.x, t.origin.z - _last_origin.z).length()
	_last_origin = t.origin
	_speed = lerpf(_speed, moved / maxf(delta, 1e-4), clampf(delta * 8.0, 0.0, 1.0))
	_wheel += delta * 7.5 * clampf(_speed / 2.0, 0.0, 1.2)
	if _model != null:
		# The casters jiggle on the tiles while it rolls (the crew's own trick).
		_model.position.y = absf(sin(_wheel * 2.3)) * 0.008 * clampf(_speed, 0.0, 1.0)
	_rattle -= delta
	if _rattle <= 0.0:
		_rattle = RATTLE_EVERY
		if _speed > 0.4:
			Audio.play("loop_gurney", t.origin + Vector3.UP * 0.6, -6.0, 0.06)


# ---------------------------------------------------------------------------
# network

func net_state() -> Dictionary:
	return {"p": pos.snappedf(0.01), "y": snappedf(yaw, 1.0 / 128.0), "u": pusher, "k": rider_kind, "r": rider_id}


func apply_net_state(s: Dictionary) -> void:
	if s.is_empty():
		return
	pos = s.get("p", pos)
	yaw = float(s.get("y", yaw))
	pusher = int(s.get("u", 0))
	rider_kind = String(s.get("k", ""))
	rider_id = int(s.get("r", 0))


class GurneyAim extends Area3D:
	var gurney: Node
	func interact_prompt(p) -> String: return gurney.aim_prompt(p)
	func interact_hold() -> float: return 0.0
	func interact(p) -> void: gurney.used(p)
