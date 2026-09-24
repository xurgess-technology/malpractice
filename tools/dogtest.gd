extends Node
## Headless checks for the Service Dog (scripts/monsters/service_dog_brain.gd), in the real game on
## the review setup's own staging (ReviewSetups._service_dog: a wing corridor, the dog a few metres
## off with a heart monitor in its mouth).
##
##   godot --headless --fixed-fps 60 --path . tools/dogtest.tscn
##
## Round 1  it walks up, sets the heart monitor down at your feet, growls, the clock starts; a TAP of
##          the item does nothing; a charged throw satisfies it; it fetches the item and wanders.
## Round 2  it offers again; the full FETCH_WINDOW runs out; it rears up and hits you, more than once;
##          a TEAMMATE's charged throw of that same item stands it down, and it fetches it back.
## Round 3  it offers again and rears; its surgeon going down ends it; it fetches its item back.
## Round 4  the offered item disappears (it leaves the world with nobody holding it): it gives up.
## Plus immunity (no hurt, no sedation, no stun, no shove, no drag, no capture), the roster, and a
## client copy fed only report() showing the same carry, clock, growl and rear.
## Exits 0 when every check passes.

const MonsterScript := preload("res://scripts/monster.gd")
const Modes := preload("res://scripts/monsters/modes.gd")
const DogBrain := preload("res://scripts/monsters/service_dog_brain.gd")


## The stand-in for a client's Game: only what a monster's visual reads.
class ClientGame extends Node:
	var players: Dictionary = {}

	func is_host() -> bool:
		return false

	func viewed_player() -> Node:
		return null


var main: Node3D
var game: Game
var dev: Node
var me: Player
var dog: Node
var t := 0.0
var _done := false
var _failures: Array = []
var _modes_seen: Array = []
var client: Node = null
var client_game: ClientGame = null


func _ready() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	game = main.game
	dev = game.dev
	await _start()
	await _run()
	_finish()


func _start() -> void:
	if main.launching:
		await main.launched
	main.menu.hide_menu()
	Net.start_solo("Tester")
	game.start_session(4242)
	while game.get_parent().has_node("WarmupCover"):
		await get_tree().process_frame
	await _seconds(0.5)
	me = game.local_player()
	me.bot_active = true
	game.set_dev_tools(true, me)
	dev.request("no_game_over", {"on": true})
	game.clock_in()
	var end := t + 60.0
	while game.phase != Game.Phase.SHIFT and t < end:
		await get_tree().physics_frame
	_check(game.phase == Game.Phase.SHIFT, "set-up: clocked in")
	await ReviewSetups._service_dog(game)
	me.bot_yaw = me._yaw
	me.bot_pitch = me._pitch
	me.bot_move = Vector2.ZERO
	for m in game.monsters.values():
		if String(m.kind) == MonsterScript.SERVICE_DOG:
			dog = m
	_check(dog != null, "set-up: the review setup staged a Service Dog")


func _physics_process(delta: float) -> void:
	t += delta
	if dog != null and is_instance_valid(dog):
		if _modes_seen.is_empty() or int(_modes_seen[-1]) != int(dog.mode):
			_modes_seen.append(int(dog.mode))
		if client != null and is_instance_valid(client):
			client.apply_remote(_snapshot(dog.report()))
	if t > 900.0 and not _done:
		_check(false, "timed out")
		_finish()


## What a client would be sent: the report without the id, through a full copy (the wire).
func _snapshot(d: Dictionary) -> Dictionary:
	var c := d.duplicate(true)
	c.erase("id")
	return c


func _run() -> void:
	if dog == null:
		return
	_static_checks()
	_immunity()
	_client_mirror()
	await _frames(2)
	_check(String(dog.dog_carry) == "heart_monitor", "it starts with the heart monitor in its mouth (ck %s)" % dog.dog_carry)
	_check(client != null and String(client.dog_carry) == "heart_monitor" and client._dog_held != null,
		"the client copy shows the heart monitor in its mouth")

	# ---------------------------------------------------------------- round 1: a throw satisfies it
	print("[dogtest] --- round 1: offer, a tap does nothing, a charged throw satisfies it ---")
	me.bot_invulnerable = true
	_modes_seen.clear()
	var warned := await _until(func(): return int(dog.mode) == Modes.Mode.DOG_WARN, 30.0)
	_check(warned, "it comes up to you and settles to wait (mode %d)" % dog.mode)
	_check(_modes_seen.has(Modes.Mode.DOG_APPROACH) and _modes_seen.has(Modes.Mode.DOG_OFFER),
		"...by walking up (APPROACH) and putting it down (OFFER): %s" % str(_modes_seen))
	var it: Node = game.dog_tagged_item(int(dog.brain.offer_tag))
	_check(it != null and String(it.kind) == "heart_monitor", "the heart monitor is on the floor, tagged as its offer")
	if it != null:
		_check(_flat(it.global_position, me.global_position) < 2.6, "...at your feet (%.2f m)" % _flat(it.global_position, me.global_position))
	_check(String(dog.dog_carry) == "" and int(dog.dog_target) == int(me.peer_id), "its mouth is empty and it is looking at you")
	var gr0 := int(dog.dog_growls)
	await _seconds(DogBrain.GROWL_AT + 0.2)
	_check(int(dog.dog_growls) > gr0 - 1 and int(dog.dog_growls) >= 1, "it growls as the clock starts (%d growls)" % dog.dog_growls)
	_check(float(dog.dog_left) > 0.0 and float(dog.dog_left) < DogBrain.FETCH_WINDOW, "the fetch clock is running (%.1f s left)" % dog.dog_left)
	_check(client != null and int(client.mode) == Modes.Mode.DOG_WARN and absf(float(client.dog_left) - float(dog.dog_left)) < 0.35,
		"the client sees the clock (%.2f vs host %.2f)" % [client.dog_left if client != null else -1.0, dog.dog_left])
	_check(client != null and float(client._dog_growl) > 0.0, "the client plays the growl (its jaw is open: %.2f)" % (client._dog_growl if client != null else 0.0))
	await _frames(2)
	var hud = get_tree().get_first_node_in_group("hud")
	# 2026-09-24 (Zach): NO on-screen clock or prompt. The dog's growl, its stare and the item at
	# your feet are the only tells; the clock is real but never drawn.
	_check(hud != null and not (hud.drawn as PackedStringArray).has("dog_fetch"), "the HUD draws no fetch clock or prompt (drawn %s)" % (str(hud.drawn) if hud != null else "no hud"))
	# Pick it up (the tag goes into the hand), tap it down: nothing.
	game.pickup_item(me, it)
	await _frames(1)
	_check(int(me.selected_stack().get("dg", 0)) == int(dog.brain.offer_tag), "picking it up carries the offer's tag into the hand (dg)")
	game.drop_selected(me, 0.0)
	await _frames(3)
	_check(int(dog.mode) == Modes.Mode.DOG_WARN and not bool(dog.brain.satisfied), "a TAP (set it down) does not count")
	it = game.dog_tagged_item(int(dog.brain.offer_tag))
	_check(it != null, "the set-down item still carries the tag")
	game.pickup_item(me, it)
	await _frames(1)
	_look_along_corridor()
	var left_at_throw := float(dog.dog_left)
	game.drop_selected(me, 0.45)
	await _frames(3)
	_check(int(dog.mode) == Modes.Mode.DOG_RETRIEVE, "a partial-charge throw satisfies it with %.1f s to spare (mode %d)" % [left_at_throw, dog.mode])
	var fetched := await _until(func(): return String(dog.dog_carry) == "heart_monitor", 25.0)
	_check(fetched and int(dog.brain.fetches) == 1, "it trots after it and takes it back in its mouth (fetches %d)" % dog.brain.fetches)
	await _frames(3)
	_check(int(dog.mode) == Modes.Mode.WANDER or int(dog.mode) == Modes.Mode.IDLE, "...and goes back to wandering (mode %d)" % dog.mode)
	_check(game.dog_tagged_item(1) == null and not game.dog_tag_exists(1), "the old offer's tag is gone with the pickup")

	# ---------------------------------------------------------------- round 2: the clock runs out
	print("[dogtest] --- round 2: the clock runs out, it rears and attacks; a teammate's throw saves you ---")
	await _come_back()
	dog.brain.content = 0.0
	warned = await _until(func(): return int(dog.mode) == Modes.Mode.DOG_WARN, 40.0)
	_check(warned, "it offers again (the same heart monitor: %s)" % dog.dog_offer_kind)
	var warn_t := t
	me.bot_invulnerable = false
	me.invuln = 0.0
	var hp0: int = me.hp
	var reared := await _until(func(): return int(dog.mode) == Modes.Mode.DOG_REAR, DogBrain.FETCH_WINDOW + 3.0)
	var waited := t - warn_t
	_check(reared and absf(waited - DogBrain.FETCH_WINDOW) < 0.5, "with no throw it rears after the full %.0f s (%.1f s)" % [DogBrain.FETCH_WINDOW, waited])
	_check(int(dog.state) == Modes.State.CHASE and int(dog.dog_target) == int(me.peer_id), "...and it is after you")
	await _seconds(DogBrain.REAR_RISE + 0.1)
	_check(float(dog.model.dog.rear) > 0.95, "it is up on its hind legs (rear %.2f)" % dog.model.dog.rear)
	_check(client != null and float(client.model.dog.rear) > 0.95, "...on the client too (rear %.2f)" % (client.model.dog.rear if client != null else 0.0))
	var hit1 := await _until(func(): return me.hp < hp0, 10.0)
	_check(hit1, "it hits you (hp %d -> %d)" % [hp0, me.hp])
	me.hp = me.max_hp
	me.invuln = 0.0
	var hp1: int = me.hp
	var hit2 := await _until(func(): return me.hp < hp1, 10.0)
	_check(hit2 and int(dog.mode) == Modes.Mode.DOG_REAR, "and keeps at it (a second hit, still reared)")
	me.hp = me.max_hp
	me.bot_invulnerable = true
	# The teammate: Dr. Botsworth picks the heart monitor up off the floor and throws it.
	var bot_id: int = dev.spawn_bot("bot", me, "Dr. Botsworth", game._floor_at(me.global_position + Vector3(0.8, 0, 0.8)))
	dev.order_bot(bot_id, "stay")
	var bot: Player = game.players.get(bot_id)
	await _frames(3)
	it = game.dog_tagged_item(int(dog.brain.offer_tag))
	_check(it != null and bot != null, "set-up: the offered item is still on the floor and a teammate is here")
	if it != null and bot != null:
		bot.teleport(game._floor_at(it.global_position + Vector3(0.3, 0, 0.3)))
		game.pickup_item(bot, it)
		await _frames(1)
		_check(int(bot.selected_stack().get("dg", 0)) == int(dog.brain.offer_tag), "the teammate is holding the tagged item")
		game.drop_selected(bot, 0.3)
		await _frames(3)
	_check(int(dog.mode) == Modes.Mode.DOG_RETRIEVE, "the TEAMMATE's charged throw stands it down (mode %d)" % dog.mode)
	var hp2: int = me.hp
	me.bot_invulnerable = false
	me.invuln = 0.0
	await _seconds(1.5)
	_check(me.hp == hp2, "it stops attacking you")
	me.bot_invulnerable = true
	_check(float(dog.model.dog.rear) < 0.05, "and drops back onto all fours (rear %.2f)" % dog.model.dog.rear)
	fetched = await _until(func(): return String(dog.dog_carry) == "heart_monitor", 25.0)
	_check(fetched and int(dog.brain.fetches) == 2, "it fetches the item back again (fetches %d)" % dog.brain.fetches)
	if bot_id != 0:
		dev.remove_bot(bot_id)   # so round 3's surgeon is you
		await _frames(3)

	# ---------------------------------------------------------------- round 3: its surgeon goes down
	print("[dogtest] --- round 3: its surgeon goes down; it stops and fetches its item ---")
	await _come_back()
	dog.brain.content = 0.0
	warned = await _until(func(): return int(dog.mode) == Modes.Mode.DOG_WARN, 40.0)
	_check(warned, "it offers a third time")
	dog.brain.offer_left = 0.1
	reared = await _until(func(): return int(dog.mode) == Modes.Mode.DOG_REAR, 2.0)
	_check(reared, "set-up: it rears")
	await _seconds(DogBrain.REAR_RISE + 0.2)
	game.knock_down_player(me, "test")
	await _frames(3)
	_check(bool(me.downed) and int(dog.mode) == Modes.Mode.DOG_RETRIEVE, "its surgeon down, it drops the attack and goes to fetch (mode %d)" % dog.mode)
	fetched = await _until(func(): return String(dog.dog_carry) == "heart_monitor", 25.0)
	_check(fetched and int(dog.brain.fetches) == 3, "...and has it back in its mouth (fetches %d): the loop loops" % dog.brain.fetches)
	me.revive_full()
	await _frames(3)

	# ---------------------------------------------------------------- round 4: the item vanishes
	print("[dogtest] --- round 4: the offered item leaves the world; it gives up ---")
	await _come_back()
	dog.brain.content = 0.0
	warned = await _until(func(): return int(dog.mode) == Modes.Mode.DOG_WARN, 40.0)
	_check(warned, "it offers a fourth time")
	it = game.dog_tagged_item(int(dog.brain.offer_tag))
	if it != null:
		game.world_items.erase(it.item_id)
		it.queue_free()
	var gave_up := await _until(func(): return int(dog.mode) == Modes.Mode.WANDER or int(dog.mode) == Modes.Mode.IDLE or int(dog.mode) == Modes.Mode.DOG_SEEK, DogBrain.EXIST_INTERVAL + 1.5)
	_check(gave_up and int(dog.brain.offer_tag) == 0, "with its item gone it stands down instead of waiting for a throw that cannot come (mode %d)" % dog.mode)
	# Empty-mouthed, it goes looking for something else two-handed: the defibrillator on the floor.
	dog.brain.content = 0.0
	var defib: Node = null
	for w in game.world_items.values():
		if String(w.kind) == "defibrillator":
			defib = w
	if defib != null:
		print("[dogtest] defib at %v state %d frozen %s, dog at %v (%.1f m), may_wander %s" % [defib.global_position, defib.state, defib.freeze, dog.global_position, _flat(defib.global_position, dog.global_position), game.monster_may_wander_to(defib.global_position, dog.global_position)])
	if defib != null and _flat(defib.global_position, dog.global_position) > DogBrain.ITEM_RANGE - 2.0:
		# It wandered off out of range of it: walk it back into range (a test shortcut, not a rule).
		for i in 12:
			var c: Vector3 = game._floor_at(defib.global_position + Vector3(cos(TAU * i / 12.0), 0.0, sin(TAU * i / 12.0)) * 4.0)
			if game._point_is_clear(c + Vector3.UP * 0.5):
				dog.global_position = c
				break
	if defib != null and OS.get_cmdline_user_args().has("--verbose-dog"):
		var sp: PhysicsDirectSpaceState3D = game.get_world_3d().direct_space_state
		for hgt in [0.2, 0.6, 1.2]:
			var q := PhysicsRayQueryParameters3D.create(Vector3(defib.global_position.x, hgt, defib.global_position.z + 2.0), Vector3(defib.global_position.x, hgt, defib.global_position.z))
			q.collision_mask = C.L_WORLD
			var hit := sp.intersect_ray(q)
			print("[dogtest]   ray h%.1f -> %s" % [hgt, str(hit.get("position")) + " " + (str(hit.collider.get_path()) if not hit.is_empty() else "clear")])
	var found := await _until(func(): return String(dog.dog_carry) != "", 40.0)
	_check(found and String(dog.dog_carry) == "defibrillator", "empty-mouthed, it finds another two-handed item and takes it (%s)" % dog.dog_carry)


func _static_checks() -> void:
	print("[dogtest] --- kind, roster ---")
	_check(MonsterScript.KINDS.has("service_dog"), "service_dog is a Monster kind")
	_check(MonsterScript.roster(1, 1).count("service_dog") == 0 and MonsterScript.roster(2, 1).count("service_dog") == 1 \
			and MonsterScript.roster(6, 4).count("service_dog") == 1, "the roster: none on shift 1, one from shift 2")
	_check(MonsterScript.display_name("service_dog") == "Service Dog", "its name")
	var st: Dictionary = game._build_state()
	var mo: Dictionary = st.mo.get(int(dog.monster_id), {})
	_check(mo.has("ck") and mo.has("dt") and mo.has("ol") and mo.has("gr") and mo.has("ok"), "the snapshot's `mo` section carries its fields")
	var probe: Node = MonsterScript.new_monster(990, "hive", Vector3(0, -50, 0))
	var rep: Dictionary = {}
	add_child(probe)
	probe.process_mode = Node.PROCESS_MODE_DISABLED
	rep = probe.report()
	_check(not rep.has("ck"), "...and no other monster pays for them")
	probe.free()


func _immunity() -> void:
	print("[dogtest] --- immunity ---")
	var cb = game.combat
	_check(not dog.can_be_hurt() and dog.take_hit(Vector3.FORWARD, 5, "test") == "immune", "the saw does nothing")
	_check(not MonsterScript.is_capturable("service_dog") and not cb._capturable(dog), "not capturable (no needle, no table, no dissection)")
	var mode0 := int(dog.mode)
	dog.shoved(Vector3.FORWARD, 1.0)
	_check(int(dog.mode) == mode0 and not dog.can_sedate() and not cb.can_sedate(dog), "a shove does not stun it, so the needle is never offered")
	_check(not dog.sedate(30.0) and not dog.is_sedated(), "sedate() refuses it")
	_check(cb.dragging(me) < 0 and int(dog.dragged_by) == 0, "nobody can be dragging it")


func _client_mirror() -> void:
	client_game = ClientGame.new()
	client_game.players = game.players
	add_child(client_game)
	client = MonsterScript.new_monster(int(dog.monster_id) + 1000, "service_dog", dog.global_position + Vector3(0, -30, 0))
	add_child(client)
	client.game = client_game


## Wait for `cond` (a Callable returning bool) for at most `seconds`.
func _until(cond: Callable, seconds: float) -> bool:
	var end := t + seconds
	var next_dbg := t + 3.0
	while t < end:
		if cond.call():
			return true
		if t >= next_dbg and OS.get_cmdline_user_args().has("--verbose-dog"):
			next_dbg = t + 3.0
			var b = dog.brain
			print("[dogtest]   ... mode %d carry '%s' content %.1f target %d me %.1f m, sees me %s, goal %s, timer %.1f, pos %v" % [
				dog.mode, dog.dog_carry, b.content, b.target_id, _flat(me.global_position, dog.global_position),
				b._can_see(me), str(b.goal_item), b.timer, dog.global_position])
		await get_tree().physics_frame
	return bool(cond.call())


## Between rounds: stand a few metres from the dog, somewhere it can see you, facing it -- and turn
## the dog to face you, so a round does not wait on its wander happening to bring you into view.
func _come_back() -> void:
	var eye: Vector3 = dog.global_position + Vector3.UP * DogBrain.EYE_H
	var spot := me.global_position
	var best := INF
	for i in 16:
		var a := TAU * float(i) / 16.0
		for r in [5.0, 3.5, 7.0]:
			var c: Vector3 = game._floor_at(dog.global_position + Vector3(cos(a), 0.0, sin(a)) * r)
			if absf(c.y - dog.global_position.y) > 0.3 or not game._point_is_clear(c + Vector3.UP * 0.2):
				continue
			if not dog.clear_line(eye, c + Vector3.UP * 1.6) or not dog.clear_line(dog.global_position + Vector3.UP * 0.6, c + Vector3.UP * 0.6):
				continue
			var score := absf(r - 5.0)
			if score < best:
				best = score
				spot = c
	me.teleport(spot)
	var to: Vector3 = dog.global_position - spot
	me.bot_yaw = atan2(-to.x, -to.z)
	me.bot_pitch = 0.0
	dog.rotation.y = atan2(to.x, to.z)
	dog.brain._start_idle()   # standing, looking your way, rather than already walking off
	await _frames(2)


func _look_along_corridor() -> void:
	var to: Vector3 = dog.global_position - me.global_position
	me.bot_yaw = atan2(-to.x, -to.z) + 0.4
	me.bot_pitch = 0.1


func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _check(ok: bool, what: String) -> void:
	print("[dogtest] t=%.1f %s  %s" % [t, "PASS" if ok else "FAIL", what])
	if not ok:
		_failures.append(what)


func _finish() -> void:
	if _done:
		return
	_done = true
	print("[dogtest] ------------------------------------------")
	print("[dogtest] fetches=%d attacks=%d" % [dog.brain.fetches if dog != null else 0, dog.brain.attacks if dog != null else 0])
	print("[dogtest] result=%s failures=%d" % ["PASS" if _failures.is_empty() else "FAIL", _failures.size()])
	get_tree().quit(0 if _failures.is_empty() else 1)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _seconds(s: float) -> void:
	var end := t + s
	while t < end:
		await get_tree().physics_frame
