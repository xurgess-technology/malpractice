extends Node
## Headless checks for downed players, carrying, the player table and the stitches operation.
##
##   godot --headless --fixed-fps 60 --path . tools/downedtest.tscn
##
## A generated hospital first (the Re-Gen Pod is gone, suture kits spawn, the hub's patient tables
## take a downed teammate (or a level's own player table), 0 HP downs, nobody standing fails the
## shift), then a second hospital with dev mode on (No monsters, No game over, clocked in): a bot
## and dummies in an open corner of the parking lot (crawling, carrying and dropping, getting hit
## while carrying, monsters ignoring the downed), a carry into the hospital's OR onto a free patient
## table, stitches with bot skill 1.0 reviving, a kit used up, all_players_out, bleeding out to
## dead at five minutes. Exits 0 when every check passes.

## The dev-mode session's hospital (tools/devtest.gd uses the same one).
const DEV_SEED := 4242

var main: Node3D
var game: Game
var dev: Node
var me: Player
## The open test area's origin (dev_controller.gd open_area()) in world space.
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
	await _hospital()
	await _dev_room()
	_finish()


func _physics_process(delta: float) -> void:
	t += delta
	if t > 900.0 and not _done:
		_check(false, "timed out")
		_finish()


# =========================================================================
# the generated hospital
# =========================================================================

func _hospital() -> void:
	game.start_session(12345)
	await _frames(5)
	me = game.local_player()
	me.bot_active = true
	_check(not game.has_method("pod_pos") and game.find_interactable("pod") == null, "the Re-Gen Pod has no aim spot or API")
	_check(game.level.find_child("RegenPod", true, false) == null and not ("pod" in game), "no Re-Gen Pod in the level or the game state")
	_check(not game._global_fields().has("po"), "the snapshot carries no pod progress")
	game.begin_shift()
	await _frames(6)
	var kits := 0
	var stacks := 0
	var wrong := 0
	for it in game.world_items.values():
		if it.kind != "suture_kit":
			continue
		kits += int(it.count)
		stacks += 1
		if it.state == WorldItem.State.IN_CONTAINER:
			var ct := game.find_interactable(it.container_id)
			if ct == null or not ["trauma_bag", "station_drawers", "drawer_unit"].has(String(ct.container_type)):
				wrong += 1
	_check(stacks >= 3 and kits >= 3 and wrong == 0, "suture kits spawn every shift (%d kits in %d stacks, %d misplaced)" % [kits, stacks, wrong])
	_check(Items.is_surgical("suture_kit") and ItemModels.tint_material("suture_kit") != null, "suture kits are surgical and tinted teal")
	# Hub rebuild, chunk 2: the hub's OR has three patient tables and no player table of its own; a
	# downed teammate goes on whichever is free (`player_table` names it only while they lie there).
	if game.downed_any_table:
		_check(game.player_table.is_empty() and game.patient_tables.size() == 3 and game.find_interactable("player_table") == null,
			"the hub has no fixed player table: 3 patient tables take a downed teammate (%d tables)" % game.patient_tables.size())
	else:
		_check(not game.player_table.is_empty() and game.find_interactable("player_table") != null, "a player table stands in the OR (%s)" % str(game.player_table))
	if not game.player_table.is_empty():
		var entry := {}
		for tb in game.level_info.get("tables", []):
			if String(tb.get("kind", "")) == "player":
				entry = tb
		if entry.is_empty():
			var d := Vector2(game.player_table.position.x - game.table_pos().x, game.player_table.position.z - game.table_pos().z).length()
			_check(d > 2.0 and d < 4.5, "the fallback player table is beside the OR table (%.1f m)" % d)
		else:
			_check(game.player_table.position.distance_to(entry.position) < 0.01 and game.level.find_child("PlayerTable", true, false) == null,
				"the level's own player table is used, no extra model (top %.2f m)" % float(game.player_table.top))
			_check(float(game.player_table.top) > 0.7 and float(game.player_table.top) < 1.2, "the player table top was found on the level's table")
	_check(Procedures.patient_ailments() == ["amputation", "gunshot"] and not Procedures.patient_ailments().has("stitches"), "patients never roll stitches")

	# 0 HP downs.
	for m in game.monsters.values():
		m.global_position += Vector3(0, -60, 0)   # out of the way
	game.damage_player(me, me.hp, "monster:test")
	await _frames(1)
	_check(me.alive and me.downed and me.hp == 0 and me.bleed > 295.0, "damage to 0 HP downs instead of killing")
	_check(not game.alive_players().has(me), "a downed player is not among the standing players monsters hunt")
	_check(game.all_players_out(), "all_players_out when the only player is downed")
	await _frames(3)
	_check(game.phase == Game.Phase.LOST, "everyone down fails the shift (phase %d: %s)" % [game.phase, game.message])
	await _seconds(C.END_SCREEN_SECONDS + 1.0)
	# The new run builds a whole new hospital behind the loading screen first (the hub is big).
	await _until(func(): return game.phase == Game.Phase.LOBBY, 30.0)
	_check(game.phase == Game.Phase.LOBBY and me.alive and not me.downed, "the next lobby has everyone back up")
	main._back_to_menu("")
	await _frames(3)


# =========================================================================
# dev mode: an open corner of the parking lot, and the hospital's OR
# =========================================================================

func _dev_room() -> void:
	Net.start_solo("Tester")
	game.start_session(DEV_SEED)
	while game.get_parent().has_node("WarmupCover"):
		await get_tree().process_frame
	await _seconds(0.5)
	me = game.local_player()
	me.bot_active = true
	game.set_dev_tools(true, me)
	await _frames(2)
	_check(game.dev_on(), "dev mode is on")
	o = dev.open_area()
	# A normal session: no monsters and no game over while the test downs the only player; clock in
	# (the tables and carrying only work on shift) and keep the phone quiet.
	dev.request("monsters_off", {"on": true})
	dev.request("no_game_over", {"on": true})
	dev.request("clear_shelf")
	game.clock_in()
	var ok := await _until(func(): return game.phase == Game.Phase.SHIFT, 90.0)
	_check(ok, "clocked in (phase %d)" % game.phase)
	_quiet_loop()
	_check(game.downed_any_table and game.player_table.is_empty() and game.patient_tables.size() == 3,
		"the hospital has no fixed player table: its patient tables take a downed teammate (%d tables)" % game.patient_tables.size())

	# ---- crawling (in the open test area)
	_stand(o + Vector3(14.0, 0, 15.0), 0.0)
	await _frames(2)
	game.knock_down_player(me, "test")
	await _seconds(0.8)
	_stand(o + Vector3(14.0, 0, 15.0), 0.0)
	await _frames(2)
	var start := me.global_position
	me.bot_move = Vector2(0, -1)
	me.bot_sprint = true
	await _seconds(2.0)
	me.bot_move = Vector2.ZERO
	var crawled := me.global_position.distance_to(start)
	_check(me.downed and crawled > 1.0 and crawled < 1.8, "a downed player crawls slowly, sprint or not (%.2f m in 2 s)" % crawled)
	_check(me.aim_prompt == "Call for help" and me.aim_id == "", "downed, E only calls for help")
	me.bot_press += 1
	await _frames(3)
	_check(float(game._call_at.get(me.peer_id, -1.0)) > 0.0, "calling for help reaches the host")
	var m = dev.spawn_monster("sonographer", "front", me)
	await _frames(2)
	var hp0 := me.hp
	game.monster_hit_player(m, me)
	_check(me.hp == hp0 and me.downed and me.alive, "monsters do nothing to a downed player")
	game.kill_monster(m)
	dev.request("revive_all")
	await _frames(3)
	_check(me.alive and not me.downed and me.hp == me.max_hp, "revive all gets you up")
	_check(game.phase == Game.Phase.SHIFT, "No game over: the only player downed and the shift went on")

	# ---- carrying (in the open test area)
	var did: int = dev.spawn_bot("dummy")
	var dummy: Player = game.players[did]
	_stand(o + Vector3(14.0, 0, 15.0), 0.0)
	await _frames(2)
	var bid: int = dev.spawn_bot("bot", me)
	var bot: Player = game.players[bid]
	dev.order_bot(bid, "stay")
	await _frames(4)
	dummy.teleport(game._floor_at(o + Vector3(16.0, 0, 13.0)))
	await _frames(2)
	game.knock_down_player(dummy, "test")
	await _seconds(0.6)
	_check(dummy.downed and game.all_players_out() == false, "a downed dummy; others standing, so not all out")
	# Walking speed first, to compare.
	_stand(o + Vector3(18.5, 0, 12.5), -PI / 2.0)
	await _frames(2)
	start = me.global_position
	me.bot_move = Vector2(0, -1)
	await _seconds(1.0)
	me.bot_move = Vector2.ZERO
	var walk := me.global_position.distance_to(start)
	me.slots[0] = {"kind": "gauze", "count": 2}
	_stand(dummy.global_position + Vector3(0, 0, 1.6), 0.0)
	await _frames(2)
	me.bot_aim_id = "pl_%d" % did
	await _frames(2)
	_check(me.aim_prompt.begins_with("!Empty your hands"), "carrying needs empty hands ('%s')" % me.aim_prompt)
	me.slots = Player.empty_slots()
	await _frames(2)
	_check(me.aim_prompt.begins_with("Hold E: pick up"), "aiming at a downed teammate offers to pick them up ('%s')" % me.aim_prompt)
	me.bot_interact = true
	await _seconds(0.5)
	_check(me.carrying == 0 and me.carry_hold > 0.3, "picking up is a hold (%.2f s so far)" % me.carry_hold)
	await _seconds(0.7)
	me.bot_interact = false
	_check(me.carrying == did and dummy.carried_by == me.peer_id, "holding E picks the downed dummy up")
	await _frames(2)
	_check(dummy.global_position.distance_to(me.global_position + Vector3.UP * 1.35) < 0.8, "the carried body rides on the carrier's shoulder")
	_stand(o + Vector3(18.5, 0, 12.5), -PI / 2.0)
	await _frames(2)
	start = me.global_position
	me.bot_move = Vector2(0, -1)
	await _seconds(1.0)
	me.bot_move = Vector2.ZERO
	var carry_walk := me.global_position.distance_to(start)
	_check(carry_walk < walk * 0.75 and carry_walk > walk * 0.4, "carrying slows you (%.2f m vs %.2f m walking)" % [carry_walk, walk])
	_check(dummy.global_position.distance_to(me.global_position) < 1.6, "the carried body follows the carrier")
	me.bot_aim_id = ""
	me.bot_press += 1
	await _frames(3)
	_check(me.carrying == 0 and dummy.carried_by == 0 and dummy.downed and dummy.global_position.y < o.y + 0.3, "E again puts them down on the floor")
	# Getting hit drops them.
	_stand(dummy.global_position + Vector3(0, 0, 1.4), 0.0)
	me.bot_aim_id = "pl_%d" % did
	me.bot_interact = true
	await _seconds(1.3)
	me.bot_interact = false
	_check(me.carrying == did, "picked up again")
	game.damage_player(me, 1, "monster:test")
	await _frames(2)
	_check(me.carrying == 0 and dummy.carried_by == 0 and me.hp == me.max_hp - 1, "getting hit drops the carried teammate")
	await _seconds(3.2)   # the hit's invulnerability
	me.revive_full()

	# ---- a patient table in the hospital's OR (the room has no table: carry them there)
	_stand(dummy.global_position + Vector3(0, 0, 1.4), 0.0)
	me.bot_aim_id = "pl_%d" % did
	me.bot_interact = true
	await _seconds(1.3)
	me.bot_interact = false
	_check(me.carrying == did, "picked up for the trip to the OR")
	var ti: int = game.free_patient_table()
	var tid: String = game.table_interact_id(ti)
	var pt: Vector3 = game.table_position(ti)
	_stand_at_table(ti, 1.5)
	await _frames(3)
	_check(dummy.carried_by == me.peer_id and dummy.global_position.distance_to(me.global_position) < 1.6, "a teleport into the OR brings the carried body along")
	me.bot_aim_id = tid
	await _frames(3)
	_check(me.aim_prompt.begins_with("Place "), "carrying to a free patient table offers to place them ('%s' at %s)" % [me.aim_prompt, tid])
	# PLAYTEST 2026-09-22: standing at the table but aiming off it still offers the table, and the
	# drop key is what puts them down on the floor there.
	me.bot_aim_id = ""
	me.bot_pitch = 0.9   # a real miss: the camera is up at the ceiling, nowhere near the table
	await _frames(3)
	_check(me.aim_prompt.begins_with("Place "), "aiming off the table still offers to place them ('%s')" % me.aim_prompt)
	_check(me.aim_id == tid, "the near-miss prompt aims at the table itself ('%s')" % me.aim_id)
	me.drop_count += 1
	await _frames(3)
	_check(me.carrying == 0 and not dummy.on_table and dummy.global_position.y < game.player_table_top().y - 0.4,
		"the drop key still puts them down on the floor at a table (y %.2f)" % dummy.global_position.y)
	_stand(dummy.global_position + Vector3(0, 0, 1.4), 0.0)
	me.bot_aim_id = "pl_%d" % did
	me.bot_interact = true
	await _seconds(1.3)
	me.bot_interact = false
	_check(me.carrying == did, "picked up again after the deliberate floor drop")
	_stand_at_table(ti, 1.5)
	me.bot_aim_id = ""
	me.bot_pitch = 0.9
	await _frames(3)
	me.bot_press += 1
	await _frames(3)
	_check(dummy.on_table and me.carrying == 0 and dummy.carried_by == 0, "E while missing the table lays them on it, not on the floor")
	me.bot_pitch = -0.3   # back to looking at the table for the stitches below
	_check(int(game.player_table.get("index", -1)) == ti, "player_table names that table while they lie there (%s)" % str(game.player_table.get("index", -1)))
	var top := game.player_table_top()
	_check(Vector2(dummy.global_position.x - top.x, dummy.global_position.z - top.z).length() < 1.0 and absf(dummy.global_position.y - top.y) < 0.05, "the body lies on the table top")
	_check(game.player_surgery.patient() == dummy and game.player_surgery.patient_body != null and game.player_surgery.patient_body.has_site("gash"), "the stitches case starts with a lying body and a gash site")
	_check(dummy.body_visual.visible == false, "the dummy's standing body hides while the lying one shows")
	await _frames(2)
	_check(me.aim_prompt.begins_with("!") and me.aim_prompt.contains("Suture kit"), "operating needs a suture kit in hand ('%s')" % me.aim_prompt)
	var bleed_a: float = dummy.bleed
	await _seconds(2.0)
	var bled := bleed_a - dummy.bleed
	_check(bled > 0.8 and bled < 1.2, "bleeding slows to half on the table (%.2f s in 2 s)" % bled)
	game.give_hand(me, "suture_kit", 1)
	await _frames(2)
	_check(me.aim_prompt.begins_with("Operate"), "holding a kit the table offers to operate ('%s')" % me.aim_prompt)
	game.player_surgery.surgery.bot_skill = 1.0
	me.bot_press += 1
	ok = await _until(func(): return me.operating, 5.0)
	_check(ok and game.player_surgery.surgery.mg != null, "the stitches minigame starts on the table")
	var op_started := t
	ok = await _until(func(): return not dummy.downed, 40.0)
	var took := t - op_started
	_check(ok and dummy.alive and dummy.hp == Game.REVIVE_HP and not dummy.on_table, "stitches with bot 1.0 revive the dummy with partial HP (%.1f s)" % took)
	_check(took > 6.0 and took < 20.0, "stitching takes a believable time (%.1f s)" % took)
	_check(game.shelf_count("suture_kit") == 0, "the suture kit is used up")
	_check(game.player_surgery.case.is_empty() and game.player_surgery.patient_body == null and game.player_table.is_empty(), "the patient table is free again")
	_check(Vector2(dummy.global_position.x - pt.x, dummy.global_position.z - pt.z).length() < 3.5 and absf(dummy.global_position.y - pt.y) < 0.3, "the revived player stands beside the table")
	game.player_surgery.surgery.bot_skill = -1.0

	# ---- all out
	game.knock_down_player(me, "test")
	game.knock_down_player(bot, "test")
	await _frames(2)
	_check(not game.all_players_out(), "one standing dummy keeps the team in (all_players_out false)")
	game.knock_down_player(dummy, "test")
	await _frames(4)
	_check(game.all_players_out() and game.phase == Game.Phase.SHIFT, "everyone down: all_players_out (No game over keeps the shift going)")
	dev.request("revive_all")
	await _frames(2)

	# ---- going down standing still still lies the body down (KNOWN_ISSUES, sweep 2 wave 3)
	# The clip name is no use here: `play("Crawl", 0.2)` sets it the instant they go down, bug or no
	# bug. What used to be wrong was the pose -- the crossfade into Crawl was frozen at nothing by
	# speed_scale 0, so a teammate who went down without crawling a step stayed bolt upright on every
	# screen but their own. So this measures the skeleton: how high the highest bone sits over the
	# body's own feet, standing and then downed on the spot.
	await _frames(2)
	_check(bot.body_hands != null and bot.body_hands.skeleton != null, "the bot's body has a skeleton to measure")
	bot.bot_move = Vector2.ZERO
	await _seconds(0.5)
	var stand_top: float = await _body_top(bot)
	_check(stand_top > 1.2, "standing, the bot's rig reaches full height (%.2f m)" % stand_top)
	game.knock_down_player(bot, "test")
	await _seconds(0.5)   # down on the spot: never a step of crawling
	var down_top: float = await _body_top(bot)
	_check(not bot.moving, "the bot went down standing still and never crawled")
	_check(down_top < stand_top * 0.6, "downed on the spot, the body lies down instead of standing (%.2f m, standing %.2f m)" % [down_top, stand_top])
	dev.request("revive_all")
	await _seconds(0.5)
	var up_top: float = await _body_top(bot)
	_check(up_top > stand_top * 0.9, "back up, the rig stands to full height again (%.2f m)" % up_top)

	# ---- going prone of your own accord lies the body down too (Zach, 2026-09-22)
	# The same branch as the downed case above (`down` in body_hands._human_clip is
	# `downed or ... or prone`), and it hid for the same reason: the clip name says "Crawl" the
	# instant you press crouch twice, bug or no bug, so only the skeleton tells you whether the
	# blend actually ran. Voluntary prone was previously covered by reasoning alone.
	bot.bot_move = Vector2.ZERO
	bot.bot_prone = true
	await _seconds(0.5)   # prone on the spot: never a step of crawling
	var prone_top: float = await _body_top(bot)
	_check(bot.prone and not bot.downed and bot.alive, "the bot went prone on its own feet, not downed")
	_check(not bot.moving, "it went prone standing still and never crawled")
	_check(prone_top < stand_top * 0.6, "prone on the spot, the body lies down instead of standing (%.2f m, standing %.2f m)" % [prone_top, stand_top])
	# THE ORDERING TRAP: `crouching` is true while prone too (player.gd's comment at `prone`), so any
	# crouch branch added to _human_clip must lose to the prone one. If this check ever reads a
	# crouch's height instead of a crawl's, the prone pose has been stolen by the crouch.
	_check(bot.crouching, "prone also reads as crouching (so the prone branch must win)")
	bot.bot_prone = false
	await _seconds(0.6)
	var reup_top: float = await _body_top(bot)
	_check(not bot.prone and reup_top > stand_top * 0.9, "standing back up from prone reaches full height again (%.2f m)" % reup_top)

	# ---- crouching shows as a crouch, not as standing (Zach, 2026-09-22)
	# `crouching` has gated sprint, jump and silent steps since SWEEP 4A, but the only thing the
	# body did about it was body_poser.gd's 0.3 rad torso lean -- the legs stayed straight and the
	# rig stayed at full standing height, so a crouching teammate read as standing. The clip name is
	# no use here either (a crouching player is on Idle or Walk like anyone else), so this measures
	# the skeleton, the same way as prone above.
	bot.bot_crouch = true
	await _seconds(0.8)   # the crouch weight eases in at 6/s
	var crouch_top: float = await _body_top(bot)
	_check(bot.crouching and not bot.prone and not bot.downed, "the bot crouches without going prone or down")
	_check(crouch_top < stand_top * 0.88, "crouched, the body is visibly lower than standing (%.2f m, standing %.2f m)" % [crouch_top, stand_top])
	_check(crouch_top > prone_top * 1.8, "a crouch is nowhere near lying down (%.2f m, prone %.2f m)" % [crouch_top, prone_top])
	# The feet stay on the floor: the hips sink by what the bent leg lost, so the body does not
	# hover or sink into it. body_visual rides the player's own feet, so its origin is the floor.
	var crouch_low: float = float((await _body_span(bot)).low)
	_check(crouch_low > -0.12 and crouch_low < 0.12, "crouched, the feet stay on the floor (lowest bone %.2f m)" % crouch_low)
	# A crouch walk is the Walk clip slowed, not the Jog clip skating. Setting bot_move by hand is no
	# use here: this bot is under dev orders and "stay" halts it (bot_move back to zero) every tick,
	# so put it on "follow" and walk away from it instead.
	dev.order_bot(bid, "follow")
	_stand(o + Vector3(14.0, 0, 21.0), 0.0)
	await _seconds(1.5)
	_check(bot.crouching and bot.moving, "the bot is walking while crouched")
	_check(not bot.sprinting, "a crouching body never sprints, so the crouch walk is the only gait")
	_check(_clip_of(bot) == String(bot.body_hands.rig.clips.get("slow", "")), "crouch-walking plays the Walk clip, not the Jog ('%s')" % _clip_of(bot))
	var cwalk_top: float = await _body_top(bot)
	_check(cwalk_top < stand_top * 0.88, "still crouched while moving (%.2f m)" % cwalk_top)
	dev.order_bot(bid, "stay")
	await _frames(2)

	# THE ORDERING TRAP, measured: `crouching` stays true when you go prone, so a crouch branch that
	# won over the prone one would put a crouching body where a crawling one belongs -- exactly the
	# bug the prone check above proves is fixed. Go prone straight out of a crouch and check it lies.
	bot.bot_prone = true
	await _seconds(0.6)
	_check(bot.prone and bot.crouching, "prone out of a crouch: both flags are set")
	var pwins_top: float = await _body_top(bot)
	_check(pwins_top < stand_top * 0.6, "prone still wins over the crouch pose (%.2f m, crouched %.2f m)" % [pwins_top, crouch_top])
	bot.bot_prone = false
	bot.bot_crouch = false
	await _seconds(0.8)
	var cup_top: float = await _body_top(bot)
	_check(not bot.crouching and cup_top > stand_top * 0.9, "standing back up from a crouch reaches full height again (%.2f m)" % cup_top)

	# ---- the carry pose lets go once they are stitched up (playtest 2026-09-22)
	# A dev dummy is a target dummy with no rig, so this leg uses the bot: it wears the rigged human
	# body, whose crawl, carry and lying poses are animation clips. Stopping those clips freezes the
	# body in the pose it had, and the pose before the table is the fireman's carry -- so a player
	# carried there stood up still folded over an imaginary shoulder, half of them under the floor.
	await _frames(2)
	_check(bot.body_hands != null and bot.body_hands.lies_by_clip(), "a bot wears the rigged human body (lying and carried are clips)")
	game.knock_down_player(bot, "test")
	await _seconds(0.6)
	me.slots = Player.empty_slots()
	_stand(bot.global_position + Vector3(0, 0, 1.4), 0.0)
	me.bot_aim_id = "pl_%d" % bid
	me.bot_interact = true
	await _seconds(1.3)
	me.bot_interact = false
	await _frames(3)
	_check(me.carrying == bid and bot.carried_by == me.peer_id, "picked the bot up for the pose check")
	_check(_clip_of(bot) == "Carried" and _posing(bot), "over the shoulder, the body plays the Carried clip ('%s')" % _clip_of(bot))
	var ti2: int = game.free_patient_table()
	_stand_at_table(ti2, 1.5)
	await _frames(3)
	me.bot_aim_id = game.table_interact_id(ti2)
	await _frames(3)
	me.bot_press += 1
	await _frames(3)
	_check(bot.on_table and me.carrying == 0, "the bot is laid on a free table")
	game.give_hand(me, "suture_kit", 1)
	await _frames(2)
	game.player_surgery.surgery.bot_skill = 1.0
	me.bot_press += 1
	ok = await _until(func(): return me.operating, 5.0)
	ok = await _until(func(): return not bot.downed, 40.0) and ok
	await _frames(3)
	_check(ok and bot.alive and not bot.on_table and bot.body_visual.visible, "stitched up: the body is drawn again, off the table")
	_check(_posing(bot) and _clip_of(bot) != "Carried", "stitched up, the body lets go of the carry pose ('%s')" % _clip_of(bot))
	_check(bot.body_visual.position.is_equal_approx(Vector3.ZERO) and bot.body_visual.rotation.is_equal_approx(Vector3.ZERO),
		"stitched up, the body stands on the player's own feet (at %s)" % bot.body_visual.position)
	game.player_surgery.surgery.bot_skill = -1.0

	# ---- bleeding out
	var did2: int = dev.spawn_bot("dummy")
	var d2: Player = game.players[did2]
	await _frames(3)
	game.knock_down_player(d2, "test")
	var bleed_start := t
	ok = await _until(func(): return not d2.alive, 320.0)
	var lasted := t - bleed_start
	_check(ok and not d2.downed and lasted > 295.0 and lasted < 305.0, "a downed player bleeds out to dead after five minutes (%.1f s)" % lasted)
	_check(not game.alive_players().has(d2) and not d2.alive, "bled out means dead until the next shift")
	main._back_to_menu("")
	await _frames(3)


## The phone rings on clock-in: hang it up and skip the extra call so no patient arrives.
func _quiet_loop() -> void:
	game.loop._end_call()
	game.loop.first_called = true
	game.loop.extra_done = true


## Stand beside patient table `ti` (on its +Z side, where a revived player gets up), facing it.
func _stand_at_table(ti: int, dist: float) -> void:
	var b := Basis(Vector3.UP, game.table_yaw_of(ti))
	var side: Vector3 = b * Vector3(0, 0, 1)
	me.teleport(game._floor_at(game.table_position(ti) + side * dist))
	me.bot_yaw = atan2(side.x, side.z)
	me.bot_pitch = -0.3
	me.bot_move = Vector2.ZERO


# =========================================================================
# helpers
# =========================================================================

## The clip this player's body is playing right now, as everyone else's machine draws it ("" for a
## body with no rig, or one whose clips have been stopped).
func _clip_of(p: Player) -> String:
	if p.body_hands == null or p.body_hands.anim == null:
		return ""
	return String(p.body_hands.anim.current_animation)


## The highest and lowest bone of that body's rig, in metres over the body's own feet, as the rig is
## actually DRAWN: `{"top": float, "low": float}`, or top -1.0 for a body with no rig. A standing
## surgeon tops out about 1.6, a crouching one about 1.2, anything lying down well under a metre;
## `low` is about 0 on any body whose feet are on the floor. This is the pose every machine but the
## player's own draws, which is the only place a down or crouch pose shows.
##
## **It has to be sampled inside `skeleton_updated`, and that is why this is async.** Two different
## things pose these bodies. Clips (Crawl, Walk) are written by the AnimationPlayer and stay in the
## bone poses, so any old read sees them. body_poser.gd is a `SkeletonModifier3D`, and Godot reverts
## what a modifier wrote once the modification pass is over -- so the crouch squat exists only
## inside that signal, and a plain physics-frame read shows a crouching body at full standing
## height. That is indistinguishable from having no crouch pose at all, which is exactly the
## wrong verdict this file is here to avoid.
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


## Just the height, for the checks that only care how tall the drawn body is.
func _body_top(p: Player) -> float:
	var span: Dictionary = await _body_span(p)
	return float(span.top)


## True while that body's rig is still animating (a stopped one keeps the pose it froze in).
func _posing(p: Player) -> bool:
	return p.body_hands != null and p.body_hands.anim != null and p.body_hands.anim.is_playing()


func _stand(pos: Vector3, yaw := 0.0) -> void:
	me.teleport(game._floor_at(pos))
	me.bot_yaw = yaw
	me.bot_pitch = 0.0
	me.bot_move = Vector2.ZERO


func _check(ok: bool, what: String) -> void:
	print("[downedtest] t=%.1f %s  %s" % [t, "PASS" if ok else "FAIL", what])
	if not ok:
		_failures.append(what)


func _finish() -> void:
	if _done:
		return
	_done = true
	print("[downedtest] ------------------------------------------")
	print("[downedtest] result=%s failures=%d" % ["PASS" if _failures.is_empty() else "FAIL", _failures.size()])
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
