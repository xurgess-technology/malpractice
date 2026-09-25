extends Node
## Headless checks for the OR gurney (scripts/gurney/gurney.gd).
##
##   godot --headless --fixed-fps 60 --path . tools/gurneytest.tscn
##
## The hub hospital with dev mode on (no monsters, no game over), clocked in: the gurney is parked
## in the OR; a surgeon takes the handle and pushes it at walking speed (no sprint, a capped turn)
## out through the OR's double doors; loads a downed teammate lying in the open, pushes them and
## puts them on a free OR table (the stitches case starts, exactly as a carry would); loads a
## sedated Hive and puts it on another table (its Eyeball Extraction case starts); tips a monster
## off with the drop key; a monster that wakes on it rolls off; a hit makes the pusher let go; a
## carrier can put a teammate on the parked gurney; the next shift parks it again. Exits 0 when
## every check passes.

const SEED := 4242
const GurneyScript := preload("res://scripts/gurney/gurney.gd")
const CombatScript := preload("res://scripts/combat/combat.gd")

var main: Node3D
var game: Game
var dev: Node
var me: Player
var g: Node
var o := Vector3.ZERO
var t := 0.0
var _done := false
var _failures: Array = []


func _ready() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	game = main.game
	dev = game.dev
	main.menu.hide_menu()
	Net.start_solo("Tester")
	game.start_session(SEED)
	while game.get_parent().has_node("WarmupCover"):
		await get_tree().process_frame
	await _seconds(0.5)
	me = game.local_player()
	me.bot_active = true
	game.set_dev_tools(true, me)
	await _frames(2)
	o = dev.open_area()
	dev.request("monsters_off", {"on": true})
	dev.request("no_game_over", {"on": true})
	game.clock_in()
	var ok := await _until(func(): return game.phase == Game.Phase.SHIFT, 90.0)
	_check(ok, "clocked in (phase %d)" % game.phase)
	game.loop._end_call()
	game.loop.first_called = true
	game.loop.extra_done = true
	g = game.gurney
	await _run()
	_finish()


func _physics_process(delta: float) -> void:
	t += delta
	if t > 600.0 and not _done:
		_check(false, "timed out")
		_finish()


func _run() -> void:
	# ---- parked in the OR
	var spot: Dictionary = game.level_info.get("gurney", {})
	_check(not spot.is_empty(), "the hub has a gurney spot (level_info.gurney)")
	_check(g.node != null and is_instance_valid(g.node) and g.pusher == 0 and not g.has_rider(), "the gurney is built, nobody pushing, nobody on it")
	_check(g.pose().origin.distance_to(spot.get("position", Vector3.INF)) < 0.05, "it starts parked on its spot")
	var mid_table: Vector3 = game.table_position(int(game.patient_tables[1].index))
	_check(_flat(g.pose().origin, mid_table) < 6.0 and _flat(g.pose().origin, mid_table) > 3.0,
		"its spot is in the OR, clear of the tables (%.1f m from the middle table)" % _flat(g.pose().origin, mid_table))
	_check(_solid_at(g.pose().origin + Vector3.UP * 0.6), "parked, it is solid (nobody walks through it)")

	# ---- walking speed, for comparison
	_stand(o + Vector3(18.5, 0, 12.5), -PI / 2.0)
	await _frames(2)
	var start := me.global_position
	me.bot_move = Vector2(0, -1)
	await _seconds(1.0)
	me.bot_move = Vector2.ZERO
	var walk := me.global_position.distance_to(start)

	# ---- taking the handle
	var gp: Transform3D = g.pose()
	_stand(gp.origin + gp.basis * Vector3(0.9, 0, 2.2), 0.0)
	me.bot_aim_id = "gurney"
	me.slots[0] = {"kind": "gauze", "count": 2}
	await _frames(3)
	_check(me.aim_prompt.begins_with("!Empty your hands"), "pushing needs empty hands ('%s')" % me.aim_prompt)
	me.slots = Player.empty_slots()
	await _frames(2)
	_check(me.aim_prompt == "Push the gurney", "aiming at the parked gurney offers to push it ('%s')" % me.aim_prompt)
	me.bot_press += 1
	await _frames(3)
	me.bot_aim_id = ""
	_check(g.pusher == me.peer_id and me.pushing_gurney(), "E takes the handle")
	var handle: Vector3 = gp.origin + gp.basis * Vector3(0, 0, GurneyScript.HANDLE_BACK)
	_check(_flat(me.global_position, handle) < 0.15, "the pusher is moved to the handle (%.2f m off)" % _flat(me.global_position, handle))
	_check(absf(angle_difference(me.rotation.y, gp.basis.get_euler().y)) < 0.05, "facing along the gurney")
	_check(_flat(g.pose().origin, gp.origin) < 0.15, "taking the handle does not move the gurney")
	await _frames(2)
	_check(me.get_node_or_null("GurneyShape") != null and not _solid_at(g.pose().origin + Vector3.UP * 0.6, me),
		"pushed, its box rides on the pusher's body instead of standing in the world")
	_check(me.aim_prompt.begins_with("Let go of the gurney"), "pushing with nothing near, E lets go ('%s')" % me.aim_prompt)

	# ---- out through the OR's doors, pushing
	var ot: Vector3 = spot.position - Vector3(9.5, 0, 10.5) * C.TILE   # the entrance building's origin
	var inside: Vector3 = game._floor_at(ot + Vector3(10.0, 0, 9.0) * C.TILE)
	_put_pusher(inside, -PI / 2.0)   # facing +X, the OR doors
	await _frames(3)
	var through := {"door": 0.0}
	me.bot_move = Vector2(0, -1)
	var out_x: float = ot.x + 15.2 * C.TILE
	var pushed_out := await _until(func():
		for d in game.doors.near(me.global_position):
			through.door = maxf(float(through.door), absf(float(d.amount)))
		return me.global_position.x > out_x, 8.0)
	me.bot_move = Vector2.ZERO
	_check(pushed_out, "pushed the gurney out through the OR's double doors (x %.1f, needs %.1f)" % [me.global_position.x, out_x])
	_check(float(through.door) > 0.6, "the doors opened for it (%.2f)" % float(through.door))

	# ---- speed and handling, in the open
	_put_pusher(o + Vector3(18.5, 0, 12.5), -PI / 2.0)
	await _frames(3)
	start = me.global_position
	me.bot_move = Vector2(0, -1)
	me.bot_sprint = true
	await _seconds(1.0)
	_check(not me.sprinting, "no sprinting with the gurney")
	me.bot_move = Vector2.ZERO
	me.bot_sprint = false
	var push := me.global_position.distance_to(start)
	_check(push > walk * 0.85 and push > walk * Player.CARRY_SPEED_K * 1.3, "pushing is walking speed, well past the carry (%.2f m vs walk %.2f)" % [push, walk])
	var ahead: Vector3 = g.pose().origin - me.global_position
	_check(absf(ahead.length() - GurneyScript.HANDLE_BACK) < 0.1 and ahead.normalized().dot(-me.global_transform.basis.z) > 0.95,
		"the gurney rolls ahead of the pusher")
	var y0 := me.rotation.y
	me.bot_yaw = y0 + PI
	await _seconds(0.25)
	var turned := absf(angle_difference(y0, me.rotation.y))
	_check(turned > 0.2 and turned < GurneyScript.TURN_RATE * 0.25 + 0.1, "it turns, slowly (%.2f rad in 0.25 s)" % turned)
	me.bot_yaw = me.rotation.y

	# ---- loading a downed teammate
	var did: int = dev.spawn_bot("dummy")
	var dummy: Player = game.players[did]
	await _frames(3)
	dummy.teleport(game._floor_at(o + Vector3(14.0, 0, 16.0)))
	await _frames(2)
	game.knock_down_player(dummy, "test")
	await _seconds(0.6)
	_check(dummy.downed, "a downed dummy lies in the open")
	_put_pusher(dummy.global_position + Vector3(1.0, 0, 6.0), 0.0)
	await _frames(3)
	_check(me.aim_prompt.begins_with("Let go"), "out of reach, nothing to load ('%s')" % me.aim_prompt)
	_put_pusher(dummy.global_position + Vector3(1.0, 0, GurneyScript.HANDLE_BACK), 0.0)
	await _frames(3)
	_check(me.aim_prompt.begins_with("Load Dummy") or me.aim_prompt.begins_with("Load "), "bring the gurney to them and it offers to load them ('%s')" % me.aim_prompt)
	_check(me.aim_id == "pl_%d" % did, "the prompt names them (aim %s)" % me.aim_id)
	me.bot_press += 1
	await _frames(3)
	_check(dummy.on_gurney and g.rides("player", did) and dummy.downed, "E loads them onto the gurney")
	_check(dummy.global_position.distance_to(g.rider_player_pose().origin) < 0.05 and dummy.global_position.y > o.y + 0.6,
		"they lie on top of it")
	_check(dummy.downed_aim.collision_layer == 0 and not game.can_pick_up(me, dummy, false), "nobody can lift them off it by hand")
	start = me.global_position
	me.bot_move = Vector2(0, -1)
	await _seconds(1.0)
	me.bot_move = Vector2.ZERO
	await _frames(1)
	_check(me.global_position.distance_to(start) > walk * 0.85, "loaded, it still rolls at walking speed")
	_check(dummy.global_position.distance_to(g.rider_player_pose().origin) < 0.05, "the rider rides along")
	var span: Dictionary = await _body_span(dummy)
	_check(float(span.top) < 0.7, "the rider's body is drawn lying, not standing (top %.2f m)" % float(span.top))

	# ---- onto an OR table
	var ti: int = game.free_patient_table()
	_check(ti >= 0, "a free table")
	_put_near_table(ti)
	await _frames(3)
	_check(me.aim_prompt.begins_with("Put Dummy on the table") or me.aim_prompt.begins_with("Put "), "beside a free table it offers the table ('%s')" % me.aim_prompt)
	_check(me.aim_id == game.table_interact_id(ti), "aimed at that table (%s)" % me.aim_id)
	me.bot_press += 1
	await _frames(3)
	_check(dummy.on_table and not dummy.on_gurney and not g.has_rider(), "E puts them on the table")
	_check(game.player_surgery.patient() == dummy and int(game.player_table.get("index", -1)) == ti,
		"the stitches case starts on that table, same as a carry")
	_check(g.pusher == me.peer_id, "the pusher keeps the handle")

	# ---- a sedated Hive
	_put_pusher(o + Vector3(18.5, 0, 12.5), -PI / 2.0)
	await _frames(2)
	var m = game._add_monster("hive", game._floor_at(o + Vector3(12.0, 0, 18.0)))
	await _frames(3)
	m.sedate(CombatScript.SEDATE_SECONDS)
	await _seconds(1.0)
	_check(m.is_sedated(), "a sedated Hive")
	_put_pusher(m.global_position + Vector3(-1.0, 0, GurneyScript.HANDLE_BACK), 0.0)
	await _frames(3)
	_check(me.aim_prompt.begins_with("Load the Hive"), "it offers to load the Hive ('%s')" % me.aim_prompt)
	me.bot_press += 1
	await _frames(3)
	var hive_id := int(m.monster_id)
	_check(g.rides("monster", hive_id) and int(m.dragged_by) == CombatScript.GURNEY_DRAGGER, "E loads the Hive")
	_check(m.global_position.distance_to(g.monster_pose().origin) < 0.05, "the Hive lies on the gurney")
	_check(not game.combat.can_drag(game.players[did], m, false) and game.combat.dragger_of(m) == null, "nobody drags it off the gurney")
	var ti2: int = game.free_patient_table()
	_check(ti2 >= 0 and ti2 != ti, "a second free table (%d)" % ti2)
	_put_near_table(ti2)
	await _frames(3)
	_check(me.aim_prompt.begins_with("Put the Hive on the table"), "beside a free table it offers to strap it down ('%s')" % me.aim_prompt)
	me.bot_press += 1
	await _frames(3)
	var c: Dictionary = game.case_on_table(ti2)
	_check(String(c.get("patient_id", "")) == "hive" and String(c.get("ailment_id", "")) == "eye_extraction" and bool(c.get("monster", false)),
		"the Hive's Eyeball Extraction case starts on that table, same as a drag (%s)" % str(c))
	_check(not g.has_rider() and not game.monsters.has(hive_id), "the Hive left the gurney for the table")

	# ---- the drop key tips a rider off
	_put_pusher(o + Vector3(18.5, 0, 12.5), -PI / 2.0)
	var m2 = game._add_monster("hive", game._floor_at(o + Vector3(12.0, 0, 18.0)))
	await _frames(3)
	m2.sedate(CombatScript.SEDATE_SECONDS)
	await _seconds(1.0)
	_put_pusher(m2.global_position + Vector3(-1.0, 0, GurneyScript.HANDLE_BACK), 0.0)
	await _frames(3)
	me.bot_press += 1
	await _frames(3)
	_check(g.rides("monster", int(m2.monster_id)), "loaded a second Hive")
	_check(me.aim_prompt.contains("tip the Hive off"), "the drop key's job is on the prompt ('%s')" % me.aim_prompt)
	me.drop_count += 1
	await _frames(3)
	_check(not g.has_rider() and int(m2.dragged_by) == 0 and m2.global_position.y < o.y + 0.4 and m2.is_sedated(),
		"the drop key tips it off onto the floor, still asleep")
	# ---- waking up on the gurney
	me.bot_press += 1
	await _frames(3)
	_check(g.rides("monster", int(m2.monster_id)), "loaded again")
	me.invuln = 60.0
	game.combat.set_sedation_left(m2, 0.1)
	await _seconds(0.5)
	_check(not g.has_rider() and int(m2.dragged_by) == 0 and not m2.is_sedated(), "a Hive that wakes on the gurney rolls off it")
	game.kill_monster(m2)
	await _frames(2)

	# ---- a hit makes the pusher let go
	me.invuln = 0.0
	var before: Vector3 = g.pose().origin
	game.damage_player(me, 1, "monster:test")
	await _frames(2)
	_check(g.pusher == 0 and not me.pushing_gurney() and _flat(g.pose().origin, before) < 0.3, "a hit makes the pusher let go; the gurney stays put")
	await _frames(2)
	_check(me.get_node_or_null("GurneyShape") == null and _solid_at(g.pose().origin + Vector3.UP * 0.6), "let go, it is solid again and off the pusher's body")
	await _seconds(3.2)
	me.revive_full()

	# ---- a carrier puts a teammate on the parked gurney
	var did2: int = dev.spawn_bot("dummy")
	var d2: Player = game.players[did2]
	await _frames(3)
	d2.teleport(game._floor_at(g.pose().origin + Vector3(3.0, 0, 0)))
	await _frames(2)
	game.knock_down_player(d2, "test")
	await _seconds(0.6)
	game.start_carry(me, d2)
	_check(me.carrying == did2, "carrying a second teammate")
	_stand(g.pose().origin + Vector3(1.2, 0, 0.3), 0.0)
	me.bot_aim_id = "gurney"
	await _frames(3)
	_check(me.aim_prompt.begins_with("Place ") and me.aim_prompt.contains("on the gurney"), "a carrier at the gurney is offered it ('%s')" % me.aim_prompt)
	me.bot_press += 1
	await _frames(3)
	me.bot_aim_id = ""
	_check(d2.on_gurney and me.carrying == 0 and d2.carried_by == 0 and g.rides("player", did2), "E puts them on the gurney")

	# ---- the network state round-trips
	var ns: Dictionary = g.net_state()
	g.apply_net_state(ns)
	_check(g.net_state() == ns and String(ns.k) == "player" and int(ns.r) == did2, "the snapshot field carries the rider")

	# ---- a new shift parks it again
	g.park()
	await _frames(2)
	_check(not g.has_rider() and not d2.on_gurney and g.pusher == 0 and g.pose().origin.distance_to(spot.position) < 0.05,
		"a new shift parks it back in the OR, empty")


# =========================================================================
# helpers
# =========================================================================

## Put the pusher (and so the gurney in front of them) at `pos`, facing `yaw`.
func _put_pusher(pos: Vector3, yaw: float) -> void:
	me.teleport(game._floor_at(pos))
	me._yaw = yaw
	me.rotation.y = yaw
	me.bot_yaw = yaw
	me.bot_pitch = 0.0
	me.bot_move = Vector2.ZERO


## The gurney's middle 1.9 m out from table `ti`'s middle on its open side, lengthwise to it.
func _put_near_table(ti: int) -> void:
	var b := Basis(Vector3.UP, game.table_yaw_of(ti))
	var side: Vector3 = b * Vector3(0, 0, 1)
	var centre: Vector3 = game.table_position(ti) + side * 1.9
	# Face across the table's long axis (-side), so the gurney runs parallel to... its nose points at it.
	var yaw := atan2(side.x, side.z)   # -Z of this basis is -side
	_put_pusher(centre + Basis(Vector3.UP, yaw) * Vector3(0, 0, GurneyScript.HANDLE_BACK), yaw)


func _solid_at(p: Vector3, skip: Node = null) -> bool:
	var q := PhysicsShapeQueryParameters3D.new()
	var s := SphereShape3D.new()
	s.radius = 0.15
	q.shape = s
	q.transform = Transform3D(Basis(), p)
	q.collision_mask = C.L_WORLD
	if skip != null:
		q.exclude = [skip.get_rid()]
	return not game.get_world_3d().direct_space_state.intersect_shape(q, 1).is_empty()


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _body_span(p: Player) -> Dictionary:
	if p.body_hands == null or p.body_hands.skeleton == null:
		return {"top": -1.0, "low": 1e9}
	var sk: Skeleton3D = p.body_hands.skeleton
	var out := {"top": -1e9, "low": 1e9}
	var grab := func() -> void:
		var to_body := p.body_visual.global_transform.affine_inverse() * sk.global_transform
		for i in sk.get_bone_count():
			var y: float = (to_body * sk.get_bone_global_pose(i).origin).y
			out.top = maxf(float(out.top), y)
			out.low = minf(float(out.low), y)
	sk.skeleton_updated.connect(grab)
	await get_tree().process_frame
	await get_tree().process_frame
	if sk.skeleton_updated.is_connected(grab):
		sk.skeleton_updated.disconnect(grab)
	return out


func _stand(pos: Vector3, yaw := 0.0) -> void:
	me.teleport(game._floor_at(pos))
	me.bot_yaw = yaw
	me.bot_pitch = 0.0
	me.bot_move = Vector2.ZERO


func _check(ok: bool, what: String) -> void:
	print("[gurneytest] t=%.1f %s  %s" % [t, "PASS" if ok else "FAIL", what])
	if not ok:
		_failures.append(what)


func _finish() -> void:
	if _done:
		return
	_done = true
	print("[gurneytest] ------------------------------------------")
	print("[gurneytest] result=%s failures=%d" % ["PASS" if _failures.is_empty() else "FAIL", _failures.size()])
	get_tree().quit(0 if _failures.is_empty() else 1)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _seconds(s: float) -> void:
	var end := t + s
	while t < end:
		await get_tree().physics_frame


func _until(cond: Callable, timeout: float) -> bool:
	var end := t + timeout
	while t < end:
		if cond.call():
			return true
		await get_tree().physics_frame
	return bool(cond.call())
