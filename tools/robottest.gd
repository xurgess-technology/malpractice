extends Node
## THE SURGICAL ROBOT (scripts/robot/robot.gd), headless:
##
##   godot --headless --fixed-fps 60 --path . tools/robottest.tscn
##
## Solo in a normal hospital (seed 4242): the data (the core, its price, the P action and its rebind),
## the dead robot beside the first OR table and P refusing, buying a core at the pharmacy for $500
## and it arriving in the drawer, plugging it in with E through the real aim path, the boot, P in and
## out, E from the robot's camera starting Eyeball Extraction on a strapped Hive while the body stands
## across the OR (no walk-away), and then the point of it: strapped to the robot's table yourself,
## remoted in, grafting your own Hive eye, all four steps, with E never getting you up. Then a hit
## throws you out, and a game over switches the robot off.

var main: Node3D
var game: Game
var dev: Node
var me: Player
var robot: Node
var t := 0.0
var _done := false
var _failures: Array = []


func _ready() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	game = main.game
	dev = game.dev
	robot = game.robot
	if main.launching:
		await main.launched
	main.menu.hide_menu()
	Net.start_solo("Tester")
	_data_checks()
	await _run()
	_finish()


func _physics_process(delta: float) -> void:
	t += delta
	if t > 900.0 and not _done:
		_check(false, "timed out")
		_finish()


func _data_checks() -> void:
	_check(Items.exists("robot_core") and not Items.is_surgical("robot_core") and not Items.is_consumable("robot_core") and not Items.is_bulky("robot_core"),
		"the robot core is a one-hand, non-surgical item")
	var line := {}
	for e in Game.PHARMACY_CATALOG:
		if String(e.kind) == "robot_core":
			line = e
	_check(int(line.get("price", 0)) == 500 and int(line.get("count", 0)) == 1, "the pharmacy sells one robot core for $500 (%s)" % str(line))
	_check(InputMap.has_action("robot_remote"), "the robot_remote action exists")
	var p_bound := false
	for ev in InputMap.action_get_events("robot_remote"):
		if ev is InputEventKey and (ev as InputEventKey).physical_keycode == KEY_P:
			p_bound = true
	_check(p_bound, "it is P by default")
	_check(String(Settings.REBIND_ACTIONS.get("key_robot", "")) == "robot_remote" and int(Settings.DEFAULTS.get("key_robot", 0)) == KEY_P,
		"it is in the rebindable keys")
	_check(ItemIcons.bare("robot_core") != null, "the core has an icon")


func _run() -> void:
	game.start_session(4242)
	while game.get_parent().has_node("WarmupCover"):
		await get_tree().process_frame
	await _seconds(0.5)
	me = game.local_player()
	me.bot_active = true
	game.set_dev_tools(true, me)
	dev.request("god", {"on": true})
	dev.request("no_game_over", {"on": true})
	dev.request("monsters_off", {"on": true})
	game.clock_in()
	await _until(func(): return game.phase == Game.Phase.SHIFT, 60.0)
	game.loop.first_called = true
	game.loop._end_call()
	game.loop.extra_done = true
	dev.request("clear_patient")
	await _frames(3)

	# ---- the dead robot
	var fx: Node3D = robot.fixture
	_check(fx != null and is_instance_valid(fx), "the robot stands in the OR")
	if fx == null:
		return
	var ti: int = int(robot.table_index)
	_check(not game.patient_tables.is_empty() and ti == int(game.patient_tables[0].index), "it serves the first patient table (%d)" % ti)
	var tp: Vector3 = game.table_position(ti)
	var d := Vector2(fx.global_position.x - tp.x, fx.global_position.z - tp.z).length()
	_check(d > 1.5 and d < 2.3, "at the table's head end (%.2f m from its middle)" % d)
	_check(not robot.powered and robot.link_block(me).contains("core"), "it starts dead: '%s'" % robot.link_block(me))
	robot.local_toggle()
	await _frames(3)
	_check(not robot.local_linked(), "P does nothing without a core")
	_check(String(robot.fixture_prompt(me)).begins_with("!") and String(robot.fixture_prompt(me)).contains("$500"), "the robot says what it needs ('%s')" % robot.fixture_prompt(me))

	# ---- buying one
	game.reset_money()
	game.add_money(499, "test")
	_check(not game.order_pharmacy(me, {"robot_core": 1}), "$499 is not enough")
	game.add_money(1, "test")
	_check(game.order_pharmacy(me, {"robot_core": 1}) and game.money == 0, "$500 buys a core (money now %d)" % game.money)
	var arrived := await _until(func(): return _core_items().size() > 0, 90.0)
	_check(arrived, "the core arrives in the pharmacy's drawer")

	# ---- plugging it in, through the real aim and E
	_clear_hands()
	game.give_hand(me, "robot_core", 1)
	var aimed := await _aim_at(fx, "robot")
	_check(aimed, "the robot can be aimed at (aim '%s')" % me.aim_id)
	_check(me.aim_prompt == "Plug in the robot core", "holding a core: '%s'" % me.aim_prompt)
	me.bot_press += 1
	var plugged := await _until(func(): return robot.powered, 3.0)
	_check(plugged and me.hand_count("robot_core") == 0, "E plugs it in and uses the core up")
	_check(robot.link_block(me).contains("starting"), "it boots first ('%s')" % robot.link_block(me))
	await _seconds(float(robot.BOOT_TIME) + 0.2)
	_check(fx.core_node.visible, "the core shows in its socket")

	# ---- P in and out
	robot.local_toggle()
	await _frames(3)
	_check(robot.local_linked() and robot.remote_peer == me.peer_id, "P remotes in")
	await _frames(2)
	_check(robot.local_camera() != null and robot.local_camera().current, "the view is the robot's camera")
	_check(me.aim_id == "robot_op" and String(me.aim_prompt).begins_with("!Nobody"), "the empty table says so ('%s')" % me.aim_prompt)
	var at_before := me.global_position
	me.bot_move = Vector2(0, -1)
	await _seconds(0.5)
	me.bot_move = Vector2.ZERO
	_check(me.global_position.distance_to(at_before) < 0.05, "the body does not walk while remoted in")
	robot.local_toggle()
	await _frames(3)
	_check(not robot.local_linked() and robot.remote_peer == 0, "P again comes back")
	await _frames(2)
	_check(me.camera.current, "your own eyes again")

	# ---- operating on a Hive from across the OR
	dev.request("strap_monster", {"kind": "hive", "sedation": 1.0})
	await _frames(3)
	var c: Dictionary = game.case_on_table(ti)
	_check(not c.is_empty() and String(c.get("patient_id", "")) == "hive", "a Hive is strapped to the robot's table")
	if c.is_empty():
		return
	# Stand well away from the table: 7 m across the OR, further than any walk-away.
	me.teleport(game._floor_at(tp + Vector3(0, 0, 4.5).rotated(Vector3.UP, game.table_yaw_of(ti))))
	await _frames(3)
	_clear_hands()
	game.give_hand(me, "scalpel", 1)
	robot.local_toggle()
	await _frames(3)
	_check(String(me.aim_prompt).begins_with("Operate: Cut around the eye"), "from the robot, the Hive's table offers the cut ('%s')" % me.aim_prompt)
	game.surgery_bot_skill = 1.0
	var sys = game.surgery_for_table(ti)
	me.bot_press += 1
	var began := await _until(func(): return sys.is_local_operating() and sys.mg != null, 5.0)
	_check(began and int(sys.operator_id) == me.peer_id, "E from the robot's camera starts the step")
	var far := Vector2(me.global_position.x - tp.x, me.global_position.z - tp.z).length()
	var cut := await _until(func(): return int(c.get("step_index", 0)) >= 1, 40.0)
	_check(cut, "the cut finishes with the body %.1f m from the table" % far)
	await _frames(2)
	_check(robot._operating_site() == null or int(sys.operator_id) == me.peer_id, "the arms stand down after the step")
	robot.local_toggle()
	await _frames(3)
	dev.request("clear_patient")
	await _seconds(0.5)

	# ---- the point: grafting yourself, alone
	var si: int = game.vats.place_of_table(ti)
	var vat: Node = game._spawn_item("specimen_vat", 1, Transform3D(Basis(Vector3.UP, game.table_yaw_of(ti)), game.vats.places[si].position as Vector3), WorldItem.State.LOOSE)
	vat.x = Eyes.pack("eye_hive", "", 0.0, 120)
	_clear_hands()
	for k in ["scalpel", "eye_spoon", "forceps", "suture_kit"]:
		game.give_hand(me, k, 1)
	await _frames(3)
	game.strap_in(me, ti)
	await _frames(4)
	_check(me.strapped() and int(game.player_table.get("index", -1)) == ti, "strapped to the robot's table")
	var alone := String(game._table_prompt(me, ti))
	robot.local_toggle()
	await _frames(3)
	_check(robot.local_linked(), "P remotes in from the table")
	me.selected = _slot_of("scalpel")
	await _frames(2)
	_check(String(me.aim_prompt).begins_with("Operate: graft Hive's eyeball into"), "the robot offers the graft on yourself ('%s')" % me.aim_prompt)
	game.player_surgery.surgery.bot_skill = 1.0
	var tools := ["scalpel", "eye_spoon", "forceps", "suture_kit"]
	var names := ["cut", "scoop", "grab", "stitch"]
	var ps: Node = game.player_surgery
	var gsys: Node = ps.surgery
	for i in tools.size():
		me.selected = _slot_of(tools[i])
		await _frames(3)
		me.bot_interact = true   # E held too: remoted in, it must never start getting you up
		me.bot_press += 1
		var go := await _until(func(): return gsys.is_local_operating() and gsys.mg != null and String(gsys.mg.ctx.get("variant", "")) == names[i], 6.0)
		_check(go, "graft step %d (%s) starts from the robot (prompt '%s')" % [i + 1, names[i], me.aim_prompt])
		if not go:
			me.bot_interact = false
			break
		var fin := await _until(func(): return ps.case.is_empty() or int(ps.case.get("step_index", 0)) > i, 60.0)
		_check(fin, "the %s finishes" % names[i])
		_check(me.strapped() and me.carry_hold == 0.0, "still strapped down, and E is not a get-up hold (hold %.2f)" % me.carry_hold)
		me.bot_interact = false
		await _seconds(0.4)
	_check(game.grafts.graft_of(me.peer_id) == "eye_hive", "you grafted your own Hive eye, alone")
	_check(game.abilities.slot_of(me.peer_id, "puppet") >= 0, "and got Puppet")
	robot.local_toggle()
	await _frames(3)
	_check(not robot.local_linked(), "out of the robot")
	game.get_up_from_table(me)
	await _frames(3)

	# ---- a hit throws you out; a game over switches it off
	robot.local_toggle()
	await _frames(3)
	_check(robot.local_linked(), "in again")
	game.damage_player(me, 1, "test")
	await _frames(3)
	_check(not robot.local_linked(), "getting hurt throws you out of the robot")
	game.reset_money()
	await _frames(2)
	_check(not robot.powered, "a game over switches the robot off")
	_check(alone.begins_with("Hold E") or alone == "" or alone.begins_with("!"), "(the table on its own offered '%s')" % alone)


func _core_items() -> Array:
	var out := []
	for it in game.world_items.values():
		if is_instance_valid(it) and String(it.kind) == "robot_core":
			out.append(it)
	return out


## Stand beside `node` on the room side and look at it until the aim ray names `id`.
func _aim_at(node: Node3D, id: String) -> bool:
	var b := node.global_transform.basis
	for off in [Vector3(0.2, 0, 1.25), Vector3(-0.9, 0, 0.9), Vector3(0.2, 0, -1.25), Vector3(-1.2, 0, 0)]:
		me.teleport(game._floor_at(node.global_position + b * off))
		me.bot_move = Vector2.ZERO
		await _frames(6)
		var end := t + 1.0
		while t < end:
			var eye: Vector3 = me.global_position + Vector3.UP * C.EYE_H
			var dd: Vector3 = node.global_position + Vector3.UP * 1.0 - eye
			me.bot_yaw = atan2(-dd.x, -dd.z)
			me.bot_pitch = clampf(atan2(dd.y, Vector2(dd.x, dd.z).length()), -1.2, 1.2)
			await get_tree().physics_frame
			if me.aim_id == id:
				return true
	return false


func _slot_of(kind: String) -> int:
	for i in me.slots.size():
		if String(me.slots[i].kind) == kind:
			return i
	return 0


func _clear_hands() -> void:
	for i in me.slots.size():
		me.slots[i] = Player.empty_slot()


func _check(ok: bool, what: String) -> void:
	print("[robottest] t=%.1f %s  %s" % [t, "PASS" if ok else "FAIL", what])
	if not ok:
		_failures.append(what)


func _finish() -> void:
	if _done:
		return
	_done = true
	print("[robottest] ------------------------------------------")
	print("[robottest] result=%s failures=%d" % ["PASS" if _failures.is_empty() else "FAIL", _failures.size()])
	for f in _failures:
		print("[robottest]   FAILED: ", f)
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
