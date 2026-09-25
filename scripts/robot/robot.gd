extends Node
## THE SURGICAL ROBOT (docs/CONTRACTS.md, "The surgical robot"). Child "Robot" of Game on every
## machine, so its RPCs line up.
##
## A robot stands at the head end of the OR's first patient table (scripts/robot/robot_fixture.gd,
## rebuilt with each level). It starts every run dead: an empty core socket, arms hanging to the
## floor. A **robot core** ($500 at the pharmacy, Items "robot_core") carried to it and plugged in
## with E powers it for the rest of the run (a game over switches it off again, with the money).
##
## Powered, anybody can press **P** anywhere to remote in: their view moves to the robot's camera
## over its table and they operate on whoever is on that table through the ordinary surgery flow --
## the same prompt, the same E, the same minigames, the same host checks -- with the tools in their
## own hands standing in for the robot's (the robot has arms, not a supply cupboard). Their body
## stays where they left it, and anything that hurts it throws them out. P again, or Esc, leaves.
## One operator at a time.
##
## The point is solo grafting: strap yourself to the robot's table, press P, and graft your own eye
## from the robot's camera. The surgery system lets a linked operator work on themselves and from any
## distance (surgery_system._host_tick, grafts.table_prompt, player_surgery.operate_prompt all ask
## `linked()` / `covers()`).
##
## Authority: the host owns `powered`, `remote_peer`, `boot_t` and the look (replicated as "rb" in
## the game's global fields). A client asks with _rpc_link / sends its look with _rpc_look.

const FixtureScript := preload("res://scripts/robot/robot_fixture.gd")
const ViewScript := preload("res://scripts/robot/robot_view.gd")

const CORE := "robot_core"
const PRICE := 500
## The aim id a linked player's E goes out on (game.player_pressed_interact routes it here).
const OP_AIM := "robot_op"
## Where the robot stands, in its table's frame (the head end is -X).
const OFFSET := Vector3(-1.85, 0.0, 0.0)
const BOOT_TIME := 2.6
## A surgery counts as the robot's when its table is this close to the robot's table (flat metres).
const COVER_M := 1.2
## How far the camera may turn from straight down the table (yaw) and how far it tips (pitch).
const LOOK_YAW := 1.1
const LOOK_PITCH := Vector2(-1.45, -0.25)
const REST_LOOK := Vector2(0.0, -1.15)
const LOOK_SEND := 0.1

var game: Node = null

# ---- replicated (host authoritative) ----
var powered := false
var remote_peer := 0
var boot_t := -99.0
var look := REST_LOOK

# ---- per level, every machine ----
var fixture: Node3D = null
var table_index := -1

# ---- local ----
var _cam: Camera3D
var _view: CanvasLayer
var _local_look := REST_LOOK
var _look_send_t := 0.0
var _sent_look := Vector2.INF
var _seen_peer := 0
var _seen_boot := -99.0
var _servo_t := 0.0
var _was_operating := false
var _showing_body := false


func setup(g: Node) -> void:
	game = g
	_cam = Camera3D.new()
	_cam.name = "RobotCamera"
	_cam.near = 0.03
	_cam.far = 80.0
	_cam.fov = 68.0
	_cam.current = false
	# Everything but the first-person hands layer (a local player standing near the table would
	# otherwise see their own floating forearms). Their own body shows: that is the point.
	_cam.cull_mask = 0xFFFFF & ~(1 << 18)
	add_child(_cam)
	_view = ViewScript.new()
	_view.name = "RobotView"
	add_child(_view)
	_view.robot = self


# =============================================================================== state

func linked(p) -> bool:
	return p != null and powered and remote_peer != 0 and int(p.peer_id) == remote_peer


func local_linked() -> bool:
	return game != null and linked(game.local_player())


## The camera this machine renders through while its player is remoted in, else null.
func local_camera() -> Camera3D:
	return _cam if local_linked() and fixture != null and is_instance_valid(fixture) else null


## True when a surgery at `table_pos` is the robot's own table's (either surgery system asks this).
func covers(table_pos: Vector3) -> bool:
	if fixture == null or table_index < 0:
		return false
	var t: Vector3 = game.table_position(table_index)
	return Vector2(t.x - table_pos.x, t.z - table_pos.z).length() < COVER_M


func table_pos() -> Vector3:
	return game.table_position(table_index) if table_index >= 0 else Vector3.ZERO


func booting() -> float:
	if not powered:
		return 0.0
	return clampf((float(game.world_time) - boot_t) / BOOT_TIME, 0.0, 1.0)


func net_state() -> Dictionary:
	return {"pw": powered, "rp": remote_peer, "bt": snappedf(boot_t, 0.1),
		"ly": snappedf(look.x, 0.02), "lp": snappedf(look.y, 0.02)}


func apply_net_state(s: Dictionary) -> void:
	if game == null or game.is_host():
		return
	powered = bool(s.get("pw", false))
	remote_peer = int(s.get("rp", 0))
	boot_t = float(s.get("bt", -99.0))
	look = Vector2(float(s.get("ly", REST_LOOK.x)), float(s.get("lp", REST_LOOK.y)))


## Host: game over. A new run starts with a dead robot and nobody in it.
func on_reset() -> void:
	powered = false
	remote_peer = 0
	boot_t = -99.0
	look = REST_LOOK


# =============================================================================== the level

## Every machine, after game._add_landmarks: stand the robot at the head end of the first patient
## table. The fixture goes with the level; the state above lasts the run.
func on_level_built() -> void:
	fixture = null
	table_index = -1
	if game.level == null or not is_instance_valid(game.level) or game.patient_tables.is_empty():
		return
	var t: Dictionary = game.patient_tables[0]
	table_index = int(t.index)
	var b := Basis(Vector3.UP, float(t.get("yaw", 0.0)))
	var f: Node3D = FixtureScript.new()
	f.robot = self
	game.level.add_child(f)
	f.global_transform = Transform3D(b, (t.position as Vector3) + b * OFFSET)
	fixture = f
	_seen_boot = boot_t   # a rebuilt level does not play the boot again


# =============================================================================== the fixture: plugging in

func fixture_prompt(p) -> String:
	if p == null or not p.alive or p.downed:
		return ""
	if not powered:
		if p.has_method("hand_count") and int(p.hand_count(CORE)) > 0:
			return "Plug in the robot core"
		return "!The surgical robot is dead. It needs a robot core ($%d at the pharmacy)." % PRICE
	if remote_peer != 0:
		var who = game.players.get(remote_peer)
		return "!Robot in use (%s)." % (who.player_name if who != null else "someone")
	return "!Surgical robot online. Press %s anywhere to remote in." % _key_label()


## Host: E on the robot with a core in hand plugs it in.
func fixture_used(p) -> void:
	if game == null or not game.is_host() or p == null or powered:
		return
	if int(p.hand_count(CORE)) <= 0:
		return
	p.consume_hand(CORE, 1)
	powered = true
	boot_t = float(game.world_time)
	game._sound("robot_plug", fixture.global_position + Vector3.UP * 1.0 if fixture != null else null)
	game.say("The surgical robot is online. Press %s anywhere to remote in." % _key_label(), 5.0)


# =============================================================================== linking

## Why `p` cannot remote in right now ("" when they can). Replicated state only, so a client can
## answer for itself before it asks the host, and the host asks again.
func link_block(p, boot_grace := 0.0) -> String:
	if p == null or fixture == null or not is_instance_valid(fixture):
		return "There is no surgical robot here."
	if not powered:
		return "The surgical robot has no core. The pharmacy sells them."
	if booting() < 1.0 - boot_grace:
		return "The surgical robot is still starting up."
	if remote_peer != 0 and remote_peer != int(p.peer_id):
		var who = game.players.get(remote_peer)
		return "Robot in use (%s)." % (who.player_name if who != null else "someone")
	if not p.alive or p.downed:
		return "Not while you are down."
	if p.carried_by != 0 or int(p.held_by) >= 0 or p.puppeting:
		return "Not right now."
	if p.carrying != 0 or p.dragging_monster >= 0:
		return "Put them down first."
	if p.has_method("pushing_gurney") and p.pushing_gurney():
		return "Let go of the gurney first."
	if p.operating:
		return "Step back from the operation first."
	return ""


## This machine's player pressed P.
func local_toggle() -> void:
	var p = game.local_player() if game != null else null
	if p == null:
		return
	if linked(p):
		_request(false)
		return
	var why := link_block(p)
	if why != "":
		game.tell(p, why, 2.5)
		Audio.play("robot_denied", null, -4.0)
		return
	_request(true)


func _request(on: bool) -> void:
	if game.is_host():
		set_link(game.local_player(), on)
	elif Net.active:
		_rpc_link.rpc_id(Net.HOST_ID, on)


@rpc("any_peer", "reliable", "call_remote")
func _rpc_link(on: bool) -> void:
	if game == null or not game.is_host():
		return
	set_link(game.players.get(multiplayer.get_remote_sender_id()), on)


## Host: `p` remotes in (on) or out.
func set_link(p, on: bool) -> void:
	if game == null or not game.is_host() or p == null:
		return
	if on:
		if link_block(p, 0.2) != "":   # a client's clock can run a hair ahead of ours through the boot
			return
		remote_peer = int(p.peer_id)
		look = REST_LOOK
	elif remote_peer == int(p.peer_id):
		drop(p)


## Host: whoever is in comes out (hurt, downed, gone, P). Anything they were doing through the robot
## stops, exactly as if they had walked away from the table.
func drop(p) -> void:
	if game == null or not game.is_host() or p == null or remote_peer != int(p.peer_id):
		return
	remote_peer = 0
	look = REST_LOOK
	game.end_operations(p)


## Host: E from a linked player (their aim id is OP_AIM). The table's own path decides everything.
func remote_interact(p) -> void:
	if game == null or not game.is_host() or not linked(p) or table_index < 0:
		return
	var prompt := op_prompt(p)
	if prompt == "" or prompt.begins_with("!"):
		return
	game._proxy_used(game.table_interact_id(table_index), p)


## What E does from the robot's camera: the table's own prompt, as if `p` stood at it. Never "".
func op_prompt(p) -> String:
	if game == null or table_index < 0:
		return "!No table."
	if int(game.phase) != int(Game.Phase.SHIFT):
		return "!Nothing to operate on until the shift starts."
	var s: String = game._table_prompt(p, table_index)
	# The table's own strap-in offer is for somebody standing at it, not for the robot.
	if s == "" or s.begins_with("Hold E") or s == Game.STRAP_IN_PROMPT:
		return "!Nobody is on the table."
	if s.begins_with("Place") or s.begins_with("Lift") or s.begins_with("Carry"):
		return "!Nobody is on the table."
	return s


# =============================================================================== the look

## This machine's player moved the mouse while remoted in (player.gd routes it here).
func local_look_input(rel: Vector2) -> void:
	var sens: float = 0.0022 * float(Settings.get_value("sensitivity"))
	_local_look.x = clampf(_local_look.x - rel.x * sens, -LOOK_YAW, LOOK_YAW)
	_local_look.y = clampf(_local_look.y - rel.y * sens, LOOK_PITCH.x, LOOK_PITCH.y)


@rpc("any_peer", "unreliable_ordered", "call_remote")
func _rpc_look(yaw: float, pitch: float) -> void:
	if game == null or not game.is_host():
		return
	if multiplayer.get_remote_sender_id() != remote_peer:
		return
	look = Vector2(clampf(yaw, -LOOK_YAW, LOOK_YAW), clampf(pitch, LOOK_PITCH.x, LOOK_PITCH.y))


# =============================================================================== frame

func _physics_process(delta: float) -> void:
	if game == null:
		return
	if game.is_host():
		_host_tick()
	var me_linked := local_linked()
	# A fresh link starts looking where the robot rests.
	if me_linked and _seen_peer != remote_peer:
		_local_look = REST_LOOK
	if remote_peer != _seen_peer:
		_on_peer_changed(_seen_peer, remote_peer)
		_seen_peer = remote_peer
	if me_linked:
		if game.is_host():
			look = _local_look
		else:
			_look_send_t -= delta
			if _look_send_t <= 0.0 and _local_look.distance_to(_sent_look) > 0.01:
				_look_send_t = LOOK_SEND
				_sent_look = _local_look
				_rpc_look.rpc_id(Net.HOST_ID, _local_look.x, _local_look.y)
	# Your own body is normally drawn to nobody on your own machine. From the robot's eye you look at
	# it (lying on the table, or standing wherever you left it), so show it while you are in, the way
	# driving Dr. Botsworth does.
	var me = game.local_player()
	if me != null and is_instance_valid(me):
		if me_linked and not me.dev_body_shown:
			me.set_dev_body(true)
			_showing_body = true
		elif not me_linked and _showing_body:
			_showing_body = false
			if me.dev_body_shown and int(game.possessed) == 0:
				me.set_dev_body(false)
	if powered and boot_t != _seen_boot:
		_seen_boot = boot_t
		if float(game.world_time) - boot_t < BOOT_TIME and fixture != null:
			Audio.play("robot_boot", fixture.global_position + Vector3.UP * 1.5)
	if fixture == null or not is_instance_valid(fixture):
		fixture = null
		_view.set_on(false, false)
		return
	var site = _operating_site()
	fixture.animate({
		"powered": powered,
		"boot": booting(),
		"linked": remote_peer != 0 and powered,
		"site": site,
		"look": _local_look if me_linked else look,
	}, delta)
	# An arm moving now and then while it works, on every machine.
	var operating: bool = site != null
	if operating:
		_servo_t -= delta
		if _servo_t <= 0.0:
			_servo_t = randf_range(0.5, 1.4)
			Audio.play("robot_servo", fixture.to_global(FixtureScript.HUB), -6.0, 0.08)
	elif _was_operating:
		Audio.play("robot_servo", fixture.to_global(FixtureScript.HUB), -8.0, 0.08)
	_was_operating = operating
	if me_linked:
		_cam.global_transform = fixture.eye_transform(_local_look)
	var surgery_up: bool = game.surgery_camera() != null
	_view.set_on(me_linked, surgery_up)


## Host, every frame: the operator is thrown out by anything that takes them out of play.
func _host_tick() -> void:
	if remote_peer == 0:
		return
	var p = game.players.get(remote_peer)
	if p == null or not is_instance_valid(p):
		remote_peer = 0
		look = REST_LOOK
		return
	if not powered or not p.alive or p.downed or p.carried_by != 0 or int(p.held_by) >= 0 or p.puppeting \
			or p.carrying != 0 or p.dragging_monster >= 0 \
			or (p.has_method("pushing_gurney") and p.pushing_gurney()):
		drop(p)


func _on_peer_changed(old: int, now: int) -> void:
	if fixture == null or not is_instance_valid(fixture):
		return
	var at: Vector3 = fixture.to_global(FixtureScript.EYE)
	Audio.play("robot_link" if now != 0 else "robot_unlink", at, -2.0)
	var me := Net.my_id()
	if now == me or old == me:
		Audio.play("robot_link" if now == me else "robot_unlink", null, -6.0)


## Where the robot's working arm goes: the site of the step its operator is playing at its table, on
## every machine (each one builds that minigame), or null.
func _operating_site():
	if remote_peer == 0 or not powered or table_index < 0:
		return null
	var sys = game.surgery_for_table(table_index)
	if sys != null and int(sys.operator_id) == remote_peer and sys.mg != null and is_instance_valid(sys.mg):
		return (sys.mg as Node3D).global_position
	var ps = game.player_surgery
	if ps != null and int(ps.surgery.operator_id) == remote_peer and ps.surgery.mg != null \
			and is_instance_valid(ps.surgery.mg) and covers(game.player_table_top()):
		return (ps.surgery.mg as Node3D).global_position
	return null


func _key_label() -> String:
	if InputMap.has_action("robot_remote"):
		for ev in InputMap.action_get_events("robot_remote"):
			if ev is InputEventKey and (ev as InputEventKey).physical_keycode > 0:
				return OS.get_keycode_string((ev as InputEventKey).physical_keycode).to_upper()
	return "P"


## Warmup: the fixture (every look) and the link view.
static func warm(parent: Node3D) -> void:
	FixtureScript.warm(parent)
