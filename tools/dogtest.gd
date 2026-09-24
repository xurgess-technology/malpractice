extends Node
## Headless checks for the Service Dog (scripts/monsters/service_dog_brain.gd), in the real game on
## the review setup's own staging (ReviewSetups._service_dog: a wing corridor, the dog a few metres
## off with a heart monitor in its mouth).
##
##   godot --headless --fixed-fps 60 --path . tools/dogtest.tscn
##
## Round 0  on all fours it is a Hive: a shove stuns it (the needle is offered), and it gets up again.
## Round 1  it walks up, sets the heart monitor down at your feet, growls, the clock starts; a TAP of
##          the item does nothing; a charged throw satisfies it; it fetches the item and wanders.
## Round 2  it offers again. The drain does NOT start before the full FETCH_WINDOW; then it stands up,
##          jaws wide, orb lit, the thread out to you (host and client), your screen going grey. It
##          takes a heart without taking your hands. Standing, shove / saw / needle do nothing. A tap,
##          and a throw under the cutoff, do not end it; a TEAMMATE's real throw does: thread gone,
##          your effects clear, down on all fours, it fetches the item.
## Round 3  it offers and drains again until your hearts run out: you go down, it drops and fetches
##          its item. Back on all fours a shove stuns it again; it can be put under, and drops what it
##          carries.
## Round 4  the offered item disappears (it leaves the world with nobody holding it): it gives up,
##          then goes and finds another two-handed item.
## Round 5  on all fours the saw kills it, it drops what it carries, and the kill pays nothing.
## Plus the roster, and a client copy fed only report() showing the carry, clock, growl, drain.
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
## The real model only (the art's GLB): every logical clip that played, and the clip sequence.
var _clips_seen: Array = []
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
		if dog.model != null and dog.model.dog != null and bool(dog.model.dog.glb):
			var c := String(dog.model.current())
			if _clips_seen.is_empty() or String(_clips_seen[-1]) != c:
				_clips_seen.append(c)
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
	_client_mirror()
	await _on_all_fours("at the start")
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

	# ---------------------------------------------------------------- round 2: the drain
	print("[dogtest] --- round 2: the clock runs out and it drains you; a teammate's throw ends it ---")
	await _come_back()
	dog.brain.content = 0.0
	warned = await _until(func(): return int(dog.mode) == Modes.Mode.DOG_WARN, 40.0)
	_check(warned, "it offers again (the same heart monitor: %s)" % dog.dog_offer_kind)
	var warn_t := t
	me.bot_invulnerable = false
	me.invuln = 0.0
	var hp0: int = me.hp
	await _seconds(DogBrain.FETCH_WINDOW - 0.5)
	_check(int(dog.mode) == Modes.Mode.DOG_WARN and me.hp == hp0, "half a second before the clock runs out it is still only waiting (mode %d)" % dog.mode)
	var drained := await _until(func(): return int(dog.mode) == Modes.Mode.DOG_DRAIN, 3.0)
	var waited := t - warn_t
	_check(drained and absf(waited - DogBrain.FETCH_WINDOW) < 0.5, "the drain starts when the full %.0f s run out (%.1f s)" % [DogBrain.FETCH_WINDOW, waited])
	_check(int(dog.dog_target) == int(me.peer_id), "...and it is draining you")
	await _seconds(DogBrain.REAR_RISE + 0.6)
	_check(float(dog.model.dog.rear) > 0.95, "it is up on its hind legs (rear %.2f)" % dog.model.dog.rear)
	var head_y: float = dog.eye_transform().origin.y - dog.global_position.y
	_check(head_y > C.EYE_H, "standing, its eyes are above yours (%.2f m vs your eyes %.2f)" % [head_y, C.EYE_H])
	_check(_jaws_open(), "jaws wide (%s)" % _body_state())
	_check(float(dog.dog_glow) > 0.9 and dog.model.dog.orb != null and String(dog.model.dog.orb.name) == "Orb",
		"the orb (its own node, `Orb`) is lit (glow %.2f)" % dog.dog_glow)
	_check(dog.dog_draining() and dog._dog_thread != null and dog._dog_thread.visible, "the thread runs from your mouth to its throat")
	_check(client != null and client.dog_draining() and client._dog_thread != null and client._dog_thread.visible and float(client.model.dog.rear) > 0.95,
		"...and the client sees it standing, lit, with the thread (glow %.2f)" % (client.dog_glow if client != null else -1.0))
	var fx: Node = game.get_node_or_null("DogDrainFx")
	await _seconds(1.0)
	_check(fx != null and float(fx.amount) > 0.05, "your own screen and ears are going (drain fx %.2f)" % (fx.amount if fx != null else -1.0))
	# Standing, it is untouchable.
	_upright_immunity()
	# It takes a heart, and leaves your hands alone.
	var hurt := await _until(func(): return me.hp < hp0, DogBrain.DRAIN_GRACE + 1.0)
	_check(hurt and me.held_by < 0, "a heart goes (hp %d -> %d) and it is not holding you" % [hp0, me.hp])
	var it2: Node = game.dog_tagged_item(int(dog.brain.offer_tag))
	if it2 != null:
		me.teleport(game._floor_at(it2.global_position + Vector3(0.4, 0, 0.4)))
		game.pickup_item(me, it2)
		await _frames(1)
	_check(me.holding("heart_monitor"), "being drained, you can still pick the item up")
	game.drop_selected(me, 0.0)
	await _frames(3)
	_check(int(dog.mode) == Modes.Mode.DOG_DRAIN, "a TAP does not end the drain")
	it2 = game.dog_tagged_item(int(dog.brain.offer_tag))
	game.pickup_item(me, it2)
	await _frames(1)
	game.drop_selected(me, DogBrain.THROW_MIN_CHARGE * 0.5)
	await _frames(3)
	_check(int(dog.mode) == Modes.Mode.DOG_DRAIN, "nor does a throw under the %.2f charge cutoff" % DogBrain.THROW_MIN_CHARGE)
	me.hp = me.max_hp
	# The teammate: Dr. Botsworth picks the heart monitor up off the floor and throws it.
	var bot_id: int = dev.spawn_bot("bot", me, "Dr. Botsworth", game._floor_at(me.global_position + Vector3(0.8, 0, 0.8)))
	dev.order_bot(bot_id, "stay")
	var bot: Player = game.players.get(bot_id)
	await _frames(3)
	it = game.dog_tagged_item(int(dog.brain.offer_tag))
	_check(it != null and bot != null, "set-up: the offered item is on the floor and a teammate is here")
	if it != null and bot != null:
		bot.teleport(game._floor_at(it.global_position + Vector3(0.3, 0, 0.3)))
		game.pickup_item(bot, it)
		await _frames(1)
		_check(int(bot.selected_stack().get("dg", 0)) == int(dog.brain.offer_tag), "the teammate is holding the tagged item")
		game.drop_selected(bot, 0.3)
		await _frames(3)
	_check(int(dog.mode) == Modes.Mode.DOG_RETRIEVE, "the TEAMMATE's real throw ends the drain (mode %d)" % dog.mode)
	await _frames(2)
	_check(not dog.dog_draining() and (dog._dog_thread == null or not dog._dog_thread.visible), "the thread snaps")
	var hp2: int = me.hp
	await _seconds(1.0)
	_check(me.hp == hp2 and fx != null and float(fx.amount) == 0.0, "no more hearts go, and your effects have cleared (fx %.2f)" % (fx.amount if fx != null else -1.0))
	_check(float(dog.model.dog.rear) < 0.05 and not _jaws_open(), "it is back on all fours, jaws shut (rear %.2f, %s)" % [dog.model.dog.rear, _body_state()])
	await _seconds(0.6)
	_check(float(dog.dog_glow) < 0.3, "the orb dims (glow %.2f)" % dog.dog_glow)
	fetched = await _until(func(): return String(dog.dog_carry) == "heart_monitor", 25.0)
	_check(fetched and int(dog.brain.fetches) == 2, "it fetches the item back again (fetches %d)" % dog.brain.fetches)
	if bot_id != 0:
		dev.remove_bot(bot_id)   # so round 3's surgeon is you
		await _frames(3)

	# ---------------------------------------------------------------- round 3: your hearts run out
	print("[dogtest] --- round 3: it drains you until you go down; it fetches; on all fours it is a Hive again ---")
	await _come_back()
	dog.brain.content = 0.0
	me.bot_invulnerable = true
	warned = await _until(func(): return int(dog.mode) == Modes.Mode.DOG_WARN, 40.0)
	_check(warned, "it offers a third time")
	dog.brain.offer_left = 0.1
	drained = await _until(func(): return int(dog.mode) == Modes.Mode.DOG_DRAIN, 2.0)
	_check(drained, "set-up: it drains")
	me.bot_invulnerable = false
	me.invuln = 0.0
	me.hp = me.max_hp
	var start := t
	var down := await _until(func(): return bool(me.downed), 30.0)
	_check(down and int(dog.brain.hearts) >= 4, "your hearts run out and you go down (%.1f s, %d hearts taken in all)" % [t - start, dog.brain.hearts])
	await _frames(3)
	_check(int(dog.mode) == Modes.Mode.DOG_RETRIEVE, "it drops the drain and goes to fetch (mode %d)" % dog.mode)
	fetched = await _until(func(): return String(dog.dog_carry) == "heart_monitor", 25.0)
	_check(fetched and int(dog.brain.fetches) == 3, "...and has it back in its mouth (fetches %d): the loop loops" % dog.brain.fetches)
	me.revive_full()
	me.bot_invulnerable = true
	await _frames(3)
	await _on_all_fours("after the drain")
	var cb = game.combat
	dog.shoved(Vector3.FORWARD, 1.0)
	_check(dog.can_sedate() and cb.can_sedate(dog) and dog.sedate(20.0) and dog.is_sedated(), "shoved on all fours, the needle puts it under")
	await _frames(2)
	_check(String(dog.dog_carry) == "" and game.world_items.values().any(func(w): return String(w.kind) == "heart_monitor" and int(w.dog_tag) == 0),
		"it drops what it was carrying where it lies")
	await _seconds(1.0)
	_check(float(dog.model.dog.lying) > 0.9, "on its side (lying %.2f)" % dog.model.dog.lying)
	dog.wake()
	await _seconds(2.5)
	_check(not dog.is_sedated() and int(dog.mode) != Modes.Mode.STUNNED, "it wakes and gets up (mode %d)" % dog.mode)

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
	_check(found and ["defibrillator", "heart_monitor"].has(String(dog.dog_carry)), "empty-mouthed, it finds another two-handed item and takes it (%s)" % dog.dog_carry)

	if dog.model.dog.glb:
		# The art's model: every clip the brain's states map to actually played at some point.
		var want := ["idle", "walk", "rear_up", "drain_idle", "upright_walk", "drop_down"]
		var missing := want.filter(func(c): return not _clips_seen.has(c))
		_check(missing.is_empty(), "the real model played every mapped clip (missing %s; sequence %s)" % [str(missing), str(_clips_seen.slice(0, 40))])
		_check(dog.model.dog.poser != null and dog.model.dog.orb != null and dog.model.dog.orb.get_parent().name == "OrbAttach",
			"it drives the art's own DogPoser and its Orb")
	else:
		print("[dogtest] (placeholder body: no GLB clips to check)")

	# ---------------------------------------------------------------- round 5: the saw
	print("[dogtest] --- round 5: on all fours the saw kills it, and pays nothing ---")
	var money0: int = game.money
	var carried := String(dog.dog_carry)
	var mid: int = dog.monster_id
	_check(dog.take_hit(Vector3.FORWARD, 1, "test") == "stagger", "a saw hit on all fours lands")
	_check(dog.take_hit(Vector3.FORWARD, 1, "test") == "killed", "the second kills it (%d hp)" % MonsterScript.max_hp_for("service_dog"))
	game.kill_monster(dog)
	await _frames(3)
	_check(not game.monsters.has(mid), "it is gone")
	_check(carried == "" or game.world_items.values().any(func(w): return String(w.kind) == carried), "what it carried (%s) is left on the floor" % carried)
	_check(game.money == money0, "the kill pays nothing ($%d -> $%d)" % [money0, game.money])
	dog = null


func _static_checks() -> void:
	print("[dogtest] --- kind, roster ---")
	_check(MonsterScript.KINDS.has("service_dog"), "service_dog is a Monster kind")
	_check(MonsterScript.roster(1, 1).count("service_dog") == 0 and MonsterScript.roster(2, 1).count("service_dog") == 1 \
			and MonsterScript.roster(6, 4).count("service_dog") == 1, "the roster: none on shift 1, one from shift 2")
	_check(MonsterScript.display_name("service_dog") == "Service Dog", "its name")
	var st: Dictionary = game._build_state()
	var mo: Dictionary = st.mo.get(int(dog.monster_id), {})
	_check(mo.has("ck") and mo.has("dt") and mo.has("ol") and mo.has("gr") and mo.has("ok") and mo.has("og"), "the snapshot's `mo` section carries its fields")
	var probe: Node = MonsterScript.new_monster(990, "hive", Vector3(0, -50, 0))
	var rep: Dictionary = {}
	add_child(probe)
	probe.process_mode = Node.PROCESS_MODE_DISABLED
	rep = probe.report()
	_check(not rep.has("ck"), "...and no other monster pays for them")
	probe.free()


## Jaws wide, whichever body it has: the placeholder's jaw pivot, or (the real model) a standing clip
## playing, whose jaws the art opens.
func _jaws_open() -> bool:
	var rg = dog.model.dog
	if bool(rg.glb):
		return ["rear_up", "drain_idle", "upright_walk"].has(String(dog.model.current()))
	return float(rg._jaw.rotation.x) > 0.8


func _body_state() -> String:
	var rg = dog.model.dog
	if bool(rg.glb):
		return "real model, clip '%s'" % dog.model.current()
	return "placeholder, jaw %.2f rad" % rg._jaw.rotation.x


## On all fours: a shove stuns it like a Hive (so the needle is offered), and it gets up again.
func _on_all_fours(when: String) -> void:
	var cb = game.combat
	_check(dog.can_be_hurt() and dog.capturable_now() and cb._capturable(dog), "%s, on all fours: hurtable and capturable" % when)
	var mode0 := int(dog.mode)
	dog.shoved(Vector3.FORWARD)
	_check(int(dog.mode) == Modes.Mode.STUNNED and dog.can_sedate() and cb.can_sedate(dog), "%s, a shove stuns it and the needle is offered" % when)
	await _seconds(DogBrain.SHOVE_STUN + 0.3)
	_check(int(dog.mode) != Modes.Mode.STUNNED, "%s, it gets up again (mode %d -> %d)" % [when, mode0, dog.mode])


## Standing and draining: shove, saw and needle do nothing.
func _upright_immunity() -> void:
	var cb = game.combat
	var hp: int = dog.hp
	_check(not dog.can_be_hurt() and dog.take_hit(Vector3.FORWARD, 5, "test") == "immune" and dog.hp == hp, "standing, the saw does nothing")
	dog.shoved(Vector3.FORWARD)
	dog.shoved(Vector3.FORWARD, 1.0)
	_check(int(dog.mode) == Modes.Mode.DOG_DRAIN, "standing, a shove (tapped or charged) does nothing")
	_check(not dog.capturable_now() and not cb._capturable(dog) and not dog.can_sedate() and not dog.sedate(30.0), "standing, the needle will not go in")


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
	print("[dogtest] result=%s failures=%d" % ["PASS" if _failures.is_empty() else "FAIL", _failures.size()])
	get_tree().quit(0 if _failures.is_empty() else 1)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _seconds(s: float) -> void:
	var end := t + s
	while t < end:
		await get_tree().physics_frame
