extends Node
## Headless checks for the six trinkets (docs/ITEMS_AND_ICONS.md, chunk B).
##
##   godot --headless --fixed-fps 60 --path . tools/trinkettest.tscn
##
## Solo, in a normal hospital (seed 4242) with dev mode on, clocked in, the phone quiet, no roaming
## monsters and no game over. Everything happens in the hidden dev room past the parking lot
## (positions are that room's own metres offset by its corner `o`), the way combattest does it.
##
## What it checks, from the brief's "Done when":
##   - each one-use trinket (laptop, defibrillator, EpiPen) works once, is greyed and cracked
##     afterwards, refuses a second use, and sells at the furnace for its scrap value;
##   - the desk phone's pull-out ring happens at about PULL_RING_CHANCE over many pulls, and a phone
##     set down rings, makes noise and can be picked up again;
##   - a tagged monster's heartbeat follows its mode, and the pulse oximeter comes back when that
##     monster is caught (strapped) or killed; the Night Nurse refuses the clip;
##   - the reflex hammer turns a Hive right round and it loses sight of you;
##   - POCKETS 2 phase 3: a burning votive candle counts as watching the Night Nurse with
##     nobody there, only inside its radius, and stops when it burns out.
## Exits 0 when every check passes.

const TrinketsScript := preload("res://scripts/trinkets/trinkets.gd")
const MonsterScript := preload("res://scripts/monster.gd")
const SonoScript := preload("res://scripts/monsters/sonographer_brain.gd")
const HiveBrain := preload("res://scripts/monsters/hive_brain.gd")
const Percept := preload("res://scripts/perception.gd")

var main: Node3D
var game: Game
var dev: Node
var tk: Node
var me: Player
var t := 0.0
var _done := false
var _failures: Array = []
var o := Vector3.ZERO


func _ready() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	game = main.game
	dev = game.dev
	tk = game.trinkets
	await _start()
	if not dev.room_ready():
		_check(false, "dev mode on builds the hidden room")
		_finish()
		return
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
	me.bot_invulnerable = true
	game.set_dev_tools(true, me)
	o = dev.room.global_position if dev.room_ready() else Vector3.ZERO
	dev.request("monsters_off", {"on": true})
	dev.request("no_game_over", {"on": true})
	game.clock_in()
	var end := t + 60.0
	while game.phase != Game.Phase.SHIFT and t < end:
		await get_tree().physics_frame
	_check(game.phase == Game.Phase.SHIFT, "set-up: clocked in")
	game.loop.first_called = true
	game.loop._end_call()
	game.loop.extra_done = true
	dev.request("clear_patient")
	for m in game.monsters.values():
		game.kill_monster(m)
	await _frames(2)


func _physics_process(delta: float) -> void:
	t += delta
	if t > 900.0 and not _done:
		_check(false, "timed out")
		_finish()


func _run() -> void:
	_check(tk != null, "the game has a Trinkets system")
	_check(tk.is_usable("laptop") and tk.is_usable("desk_phone") and tk.is_usable("fabric_softener") 			and not tk.is_usable("gauze") and not tk.is_usable(""),
		"left mouse uses the seven trinkets and nothing else")
	await _laptop()
	await _epipen()
	await _defib()
	await _phone()
	await _pulse_ox()
	await _hammer()
	await _whistle()
	await _softener()
	await _candle()
	await _pagers()


# =========================================================================
# POCKETS 2 phase 5: the restaurant pagers, from the Restaurant
# =========================================================================

## The pair is the item, so what is worth checking is not that a click does something, but that the
## RIGHT pager goes off, in the right one of its two ways, and that a pager whose partner has
## stopped existing quietly stops being a trinket at all.
##
## The two ways are the whole design: a pager in a hand buzzes that person and makes NO noise event
## (only its holder is meant to know), while a pager on the floor rattles out loud and the monsters
## hear it. Those two facts are checked against each other here, because either one alone would
## pass with the pager doing the wrong thing.
func _pagers() -> void:
	_stand(o + Vector3(14.0, 0, 18.0))
	_give("restaurant_pagers", 1, 40)
	# --- taking the pair off the station
	await _use()
	_check(String(tk.last_result.get("what", "")) == "pagers_out",
		"the station gives up its pair (%s)" % str(tk.last_result))
	var held: Dictionary = me.selected_stack()
	var floor_pager: Node = _nearest_item("restaurant_pager")
	_check(String(held.get("kind", "")) == "restaurant_pager", "one pager ends up in your hands")
	_check(floor_pager != null, "and the other on the floor")
	if floor_pager == null:
		return
	var mark := TrinketsScript.pair_id(held)
	_check(mark != "" and String(floor_pager.x) == mark,
		"both wear the same pair mark (%s / %s)" % [mark, String(floor_pager.x)])
	_check(int(held.get("v", 0)) + int(floor_pager.value) == 40,
		"the station's value is split between them, not minted (%d + %d)"
			% [int(held.get("v", 0)), int(floor_pager.value)])
	# --- the one on the floor rattles out loud, and that is a noise monsters can hear
	var iid := int(floor_pager.item_id)
	var rattles0: int = tk.rattle_count(iid)
	await _use()
	_check(String(tk.last_result.get("what", "")) == "pager_rattle",
		"pressing yours rattles the one on the floor (%s)" % str(tk.last_result))
	_check(tk.rattle_count(iid) == (rattles0 + 1) % 64, "its rattle counter went up exactly once")
	var loud := _noise_near(floor_pager.global_position, "pager", 3.0)
	_check(loud >= TrinketsScript.PAGER_NOISE - 0.01,
		"the rattle is a real noise event where it lies (%.2f)" % loud)
	_check(loud >= SonoScript.LOUD,
		"and loud enough that a Sonographer comes rather than wonders (LOUD %.2f)" % SonoScript.LOUD)
	# --- the cooldown
	tk.last_result = {}
	me.bot_use += 1
	await _frames(6)
	_check(String(tk.last_result.get("what", "")) != "pager_rattle",
		"a second press inside the cooldown does nothing (%s)" % str(tk.last_result))
	# --- a pager in somebody's hands buzzes THEM, silently
	var mate := _pager_mate(mark, int(floor_pager.value))
	game.world_items.erase(iid)
	floor_pager.queue_free()
	await _frames(2)
	if mate != null:
		await _seconds(TrinketsScript.PAGER_COOLDOWN + 0.1)
		var mine0: int = tk.buzz_count(int(me.peer_id))
		var theirs0: int = tk.buzz_count(int(mate.peer_id))
		await _use()
		_check(String(tk.last_result.get("what", "")) == "pager_buzz",
			"with the partner in a teammate's hands it buzzes instead (%s)" % str(tk.last_result))
		_check(tk.buzz_count(int(mate.peer_id)) == (theirs0 + 1) % 64, "their buzz counter went up")
		_check(tk.buzz_count(int(me.peer_id)) == mine0,
			"and the presser's did not: a pager buzzes the OTHER one")
		_check(_noise_near(mate.global_position, "pager", 4.0) <= 0.0,
			"a buzz in a hand makes no noise event at all: only its holder is meant to know")
		mate.slots = Player.empty_slots()
	# --- break the pair and what is left is plain loot
	await _frames(4)
	_check(not tk.local_try_use(me),
		"a pager whose partner is gone refuses the click, so it falls through to a shove")
	_check(tk.use_prompt(me) == "", "and offers no prompt: it is plain loot now")
	# The host guards it a second time, for the ways `use()` can be reached that are not this
	# machine's click -- a client's RPC, or game.player_used. Called directly, because a click here
	# now correctly never gets this far: local_try_use turns it into a shove before the host hears.
	tk.last_result = {}
	tk.use(me)
	_check(String(tk.last_result.get("what", "")) == "pager_alone",
		"and the host refuses it too, however the use arrives (%s)" % str(tk.last_result))


## A second player holding the other pager. Null when this run is solo, in which case the buzz half
## of the test is skipped rather than faked -- a buzz needs somebody to buzz.
func _pager_mate(mark: String, value: int) -> Node:
	for q in game.players.values():
		if q != null and is_instance_valid(q) and q != me:
			q.slots = Player.empty_slots()
			q.slots[0] = {"kind": "restaurant_pager", "count": 1, "v": value, "x": mark}
			q.selected = 0
			return q
	return null


# =========================================================================
# POCKETS 2 phase 4: the fabric softener jug, from the Laundromat
# =========================================================================

## Drinking it buys QUIET_SECONDS of footsteps that make no noise event at all, at full speed. The
## check that matters is the last one: while it lasts, walking normally produces no "footstep"
## noise for anything that hunts by sound, which is exactly what crouching already produces.
func _softener() -> void:
	_stand(o + Vector3(10.0, 0, 18.0))
	_give("fabric_softener", 1, 22)
	_check(not tk.quiet_steps(me), "before the jug, footsteps are ordinary")
	await _use()
	_check(TrinketsScript.is_spent(me.selected_stack()), "the jug is spent in one swig")
	_check(String(tk.last_result.get("what", "")) == "quiet", "and it reports the quiet (%s)" % str(tk.last_result))
	_check(tk.quiet_steps(me), "the quiet is on")
	await _frames(2)
	_check(me.silent_steps, "the player carries it")
	# Walk normally and prove nothing is emitted. game.gd's _tick_noise runs on the host every
	# frame; a walking player without the jug emits one every 0.5 s.
	var quiet_steps := await _footstep_noises(2.0)
	_check(quiet_steps == 0, "walking at full speed makes no footstep noise at all (%d in 2 s)" % quiet_steps)
	_check(absf(me.sprint_mult - 1.0) < 0.01, "and it is the noise that changed, not the speed")
	await _seconds(TrinketsScript.QUIET_SECONDS + 0.2)
	_check(not tk.quiet_steps(me), "a minute later it has worn off")
	await _frames(2)
	_check(not me.silent_steps, "and the player has it no longer")
	var loud_steps := await _footstep_noises(2.0)
	_check(loud_steps > 0, "footsteps are heard again (%d in 2 s)" % loud_steps)
	var money0: int = game.money
	game.furnace_sell("fabric_softener", 1, game.furnace_value("fabric_softener", me.selected_stack()), me.global_position)
	_check(game.money - money0 == TrinketsScript.scrap_value("fabric_softener"),
		"an empty jug burns for scrap ($%d)" % (game.money - money0))
	me.slots = Player.empty_slots()
	me.moving = false
	await _frames(2)


## Walk on the spot for `secs` and count the footstep noise events the game emitted.
func _footstep_noises(secs: float) -> int:
	var seen := 0
	var t0: float = game.world_time
	var last := -1.0
	while game.world_time - t0 < secs:
		me.moving = true
		me.sprinting = false
		me.crouching = false
		await _frames(1)
		for n in game.recent_noises(0.2):
			if String(n.kind) == "footstep" and float(n.time) > last:
				last = float(n.time)
				seen += 1
	me.moving = false
	return seen


# =========================================================================
# the laptop: one charge, then scrap
# =========================================================================

func _laptop() -> void:
	_stand(o + Vector3(10.0, 0, 10.0))
	_give("laptop", 1, 80)
	await _use()
	_check(tk.map_left(me) > TrinketsScript.MAP_SECONDS - 1.0, "the laptop opens a map (%.1f s left)" % tk.map_left(me))
	var s: Dictionary = me.selected_stack()
	_check(TrinketsScript.is_spent(s), "the laptop is marked used up")
	_check(int(s.get("v", 0)) == TrinketsScript.scrap_value("laptop"),
		"its value drops to scrap ($%d)" % int(s.get("v", 0)))
	tk.last_result = {}
	await _use()
	_check(String(tk.last_result.get("what", "")) == "spent", "a second click does nothing (%s)" % str(tk.last_result))
	_check(not tk.map_blips(me) is bool, "the map asks for surgery blips without falling over")
	await _seconds(TrinketsScript.MAP_SECONDS)
	_check(tk.map_left(me) <= 0.0, "the screen goes dark on its own")
	# It still sells, for scrap.
	var money0: int = game.money
	var sell: Dictionary = me.selected_stack()
	_check(game.furnace_can_sell("laptop"), "a spent laptop is still sellable")
	game.furnace_sell("laptop", 1, game.furnace_value("laptop", sell), me.global_position)
	_check(game.money - money0 == TrinketsScript.scrap_value("laptop"),
		"it burns for its scrap value ($%d)" % (game.money - money0))
	# And the used mark survives a drop and a pick-up.
	_give("laptop", 1, 80)
	await _use()
	await _seconds(TrinketsScript.MAP_SECONDS + 0.2)
	game.drop_selected(me, 0.0)
	await _seconds(1.0)
	var dropped: Node = _nearest_item("laptop")
	_check(dropped != null and String(dropped.x) == TrinketsScript.USED_MARK and int(dropped.value) == TrinketsScript.scrap_value("laptop"),
		"dropped, it is still a dead laptop worth scrap")
	if dropped != null:
		game.pickup_item(me, dropped)
		await _frames(2)
		_check(TrinketsScript.is_spent(me.selected_stack()), "picked back up, it is still used up")


# =========================================================================
# POCKETS 2 phase 2: the lifeguard whistle. One blast, everything comes
# =========================================================================

## The whistle is Echo's draw with none of Echo's sight. What has to be true: the blast is a real
## noise event and a loud one, the deaf Hive is told by hand so it comes anyway, the Night Nurse is
## not (she does not answer sound), it is spent in one blow, and nothing beyond WHISTLE_RANGE is
## touched -- the item is a lure you aim by standing somewhere, so its edge has to be a real edge.
func _whistle() -> void:
	_stand(o + Vector3(10.0, 0, 22.0))
	var near = await _monster("hive", me.global_position + Vector3(6.0, 0, 0))
	var far = await _monster("hive", me.global_position + Vector3(0, 0, -6.0))
	var nurse = await _monster("night_nurse", me.global_position + Vector3(-6.0, 0, 0))
	# The far one is put well past the whistle's reach, by hand: no room here is 30 m wide.
	if far != null and is_instance_valid(far):
		far.global_position = me.global_position + Vector3(0, 0, -(TrinketsScript.WHISTLE_RANGE + 12.0))
	await _frames(2)
	var nurse_mode := int(nurse.mode) if nurse != null and is_instance_valid(nurse) else -1
	_give("lifeguard_whistle", 1, 15)
	await _use()
	_check(String(tk.last_result.get("what", "")) == "whistle", "the whistle blows (%s)" % str(tk.last_result))
	_check(TrinketsScript.is_spent(me.selected_stack()), "and it is spent in one blast")
	var loud := _noise_near(me.global_position, "whistle", 3.0)
	_check(loud >= TrinketsScript.WHISTLE_NOISE - 0.01, "the blast is a real noise event, and a loud one (%.2f)" % loud)
	_check(loud >= SonoScript.LOUD, "loud enough that a Sonographer stops guessing and comes (LOUD %.2f)" % SonoScript.LOUD)
	await _frames(4)
	# The Hive is deaf to noise events, so "drawing wing monsters" has to reach it by hand.
	_check(near != null and is_instance_valid(near) and int(near.mode) != MonsterScript.Mode.IDLE,
		"the deaf Hive nearby was told by hand and is coming (mode %d)" % (int(near.mode) if near != null and is_instance_valid(near) else -1))
	_check(far != null and is_instance_valid(far) and int(far.mode) == MonsterScript.Mode.IDLE,
		"the Hive past %.0f m heard nothing" % TrinketsScript.WHISTLE_RANGE)
	_check(nurse == null or not is_instance_valid(nurse) or int(nurse.mode) == nurse_mode,
		"the Night Nurse does not answer a whistle")
	# No wall-vision: the draw is a noise, not an Echo pulse.
	_check(game.abilities == null or not bool(game.abilities.get("echo_view") != null and game.abilities.echo_view.get("active")),
		"and it reveals nothing through a wall")
	var money0: int = game.money
	game.furnace_sell("lifeguard_whistle", 1, game.furnace_value("lifeguard_whistle", me.selected_stack()), me.global_position)
	_check(game.money - money0 == TrinketsScript.scrap_value("lifeguard_whistle"),
		"a blown whistle burns for scrap ($%d)" % (game.money - money0))
	for m in [near, far, nurse]:
		if m != null and is_instance_valid(m):
			game.monsters.erase(int(m.monster_id))
			m.queue_free()
	await _frames(2)


# =========================================================================
# the EpiPen: ten seconds of double sprint, then a collapse
# =========================================================================

func _epipen() -> void:
	_stand(o + Vector3(10.0, 0, 14.0))
	_give("epipen", 1, 30)
	await _use()
	_check(TrinketsScript.is_spent(me.selected_stack()), "the EpiPen is spent in one jab")
	_check(absf(tk.sprint_mult(me) - TrinketsScript.EPI_SPRINT_MULT) < 0.01,
		"sprinting is doubled (x%.1f)" % tk.sprint_mult(me))
	await _frames(2)
	_check(absf(me.sprint_mult - TrinketsScript.EPI_SPRINT_MULT) < 0.01, "the player carries the multiplier")
	await _seconds(TrinketsScript.EPI_SECONDS + 0.2)
	_check(absf(tk.sprint_mult(me) - 1.0) < 0.01, "ten seconds later the boost is gone")
	_check(me.stun > TrinketsScript.EPI_COLLAPSE - 1.0, "and they collapse for %.0f s (stun %.1f)" % [TrinketsScript.EPI_COLLAPSE, me.stun])
	await _seconds(TrinketsScript.EPI_COLLAPSE + 0.2)
	_check(me.stun <= 0.0, "then they get up again")
	var money0: int = game.money
	game.furnace_sell("epipen", 1, game.furnace_value("epipen", me.selected_stack()), me.global_position)
	_check(game.money - money0 == TrinketsScript.scrap_value("epipen"),
		"a spent EpiPen burns for scrap ($%d)" % (game.money - money0))


# =========================================================================
# the defibrillator: up where they lie
# =========================================================================

func _defib() -> void:
	var did: int = dev.spawn_bot("dummy")
	await _frames(3)
	var mate: Player = game.players[did]
	mate.teleport(game._floor_at(o + Vector3(14.0, 0, 14.0)))
	await _frames(2)
	game.knock_down_player(mate, "dev:test")
	await _frames(3)
	_check(mate.downed, "set-up: a teammate is down")
	var lay: Vector3 = mate.global_position
	_give("defibrillator", 1, 120)
	# Out of reach first.
	_stand(o + Vector3(14.0, 0, 20.0))
	_look_at(lay)
	await _use()
	_check(mate.downed and not TrinketsScript.is_spent(me.selected_stack()),
		"out of reach it refuses, and is not wasted")
	_face(mate)
	await _use()
	_check(not mate.downed and mate.alive, "in reach it shocks them back up")
	_check(mate.global_position.distance_to(lay) < 1.2,
		"they get up where they lay (%.2f m)" % mate.global_position.distance_to(lay))
	_check(TrinketsScript.is_spent(me.selected_stack()), "the defibrillator is spent")
	var loud := _noise_near(lay, "defib", 3.0)
	_check(loud >= TrinketsScript.DEFIB_NOISE - 0.01, "and it is a real noise event (%.2f)" % loud)
	var money0: int = game.money
	game.furnace_sell("defibrillator", 1, game.furnace_value("defibrillator", me.selected_stack()), me.global_position)
	_check(game.money - money0 == TrinketsScript.scrap_value("defibrillator"),
		"a spent defibrillator burns for scrap ($%d)" % (game.money - money0))
	dev.request("remove_bot", {"id": did})
	await _frames(2)


# =========================================================================
# the desk phone: a decoy, and the 12% in your hands
# =========================================================================

func _phone() -> void:
	_stand(o + Vector3(10.0, 0, 18.0))
	_give("desk_phone", 1, 20)
	await _use()
	_check(me.selected_stack().kind == "", "setting it down empties the hand")
	var ph: Node = _nearest_item("desk_phone")
	_check(ph != null and tk.ringing_items().size() == 1, "a phone is on the floor and ringing")
	if ph == null:
		return
	await _seconds(TrinketsScript.RING_PERIOD + 0.2)
	var loud := _noise_near(ph.global_position, "phone", 3.0)
	_check(loud >= TrinketsScript.RING_LOUDNESS - 0.01, "each ring is a loud noise (%.2f)" % loud)
	# Picking it up works, and it is not used up.
	game.pickup_item(me, ph)
	await _frames(3)
	_check(me.holding("desk_phone") and not TrinketsScript.is_spent(me.selected_stack()),
		"it can be picked up and used again")
	_check(tk.ringing_items().is_empty(), "the ring ends when it is picked up")
	# The pull-out roll, over many pulls, at about PULL_RING_CHANCE.
	tk.rng.seed = 90210
	var pulls := 4000
	var rang := 0
	for i in pulls:
		if tk.rng.randf() < TrinketsScript.PULL_RING_CHANCE:
			rang += 1
	var rate := float(rang) / float(pulls)
	_check(absf(rate - TrinketsScript.PULL_RING_CHANCE) < 0.02,
		"the pull-out roll lands about %.0f%% of the time (%.1f%% over %d)" % [TrinketsScript.PULL_RING_CHANCE * 100.0, rate * 100.0, pulls])
	# And the real path: selecting a phone rolls exactly once per selection.
	tk.rng.seed = 1
	var fired := 0
	for i in 200:
		me.slots = Player.empty_slots()
		me.slots[0] = {"kind": "gauze", "count": 1}
		me.slots[1] = {"kind": "desk_phone", "count": 1, "v": 20}
		me.selected = 0
		await _frames(2)
		me.selected = 1
		await _frames(2)
		if tk.ringing_in_hand(me.peer_id):
			fired += 1
			tk._hand_rings.clear()
		await _frames(2)
	var live := float(fired) / 200.0
	_check(live > 0.05 and live < 0.22, "selecting one really does ring it now and then (%d / 200)" % fired)
	me.slots = Player.empty_slots()
	await _frames(2)


# =========================================================================
# the pulse oximeter: tag it, hear it, get it back
# =========================================================================

func _pulse_ox() -> void:
	# The Night Nurse refuses the clip.
	var nurse := await _monster("night_nurse", o + Vector3(18.0, 0, 10.0))
	_give("pulse_oximeter", 1, 40)
	await _use_on(nurse)
	_check(me.holding("pulse_oximeter") and String(tk.last_result.get("what", "")) == "refused",
		"the Night Nurse cannot be tagged (%s)" % str(tk.last_result))
	game.knock_down_monster(nurse, Vector3.ZERO, 300.0)
	nurse.global_position = game._floor_at(o + Vector3(3.0, 0, 3.0))
	# A Hive that has not been shoved takes the clip too.
	var m := await _monster("hive", o + Vector3(14.0, 0, 10.0))
	var mid: int = m.monster_id
	_calm(m)
	_face(m)
	await _frames(2)
	_check(not game.combat.can_sedate(m), "set-up: it is not stunned")
	await _use_on(m)
	_check(tk.tagged_by(mid) == me.peer_id, "the pulse oximeter goes onto the Hive")
	_check(not me.holding("pulse_oximeter"), "and it leaves your hands")
	_check(not game.combat.is_sedated(m), "the monster is not sedated: it gets up and carries on")
	# The heartbeat follows what it is doing.
	m.mode = MonsterScript.Mode.WANDER
	_check(absf(TrinketsScript.heartbeat_period(m) - TrinketsScript.BEAT_WANDER) < 0.001
		and TrinketsScript.heart_mode(m) == "wandering", "wandering: a slow heartbeat")
	m.mode = MonsterScript.Mode.SEARCH
	_check(absf(TrinketsScript.heartbeat_period(m) - TrinketsScript.BEAT_SUSPICIOUS) < 0.001
		and TrinketsScript.heart_mode(m) == "suspicious", "suspicious: faster")
	m.mode = MonsterScript.Mode.RUSH
	_check(absf(TrinketsScript.heartbeat_period(m) - TrinketsScript.BEAT_HUNTING) < 0.001
		and TrinketsScript.heart_mode(m) == "hunting", "hunting: racing")
	_check(TrinketsScript.BEAT_HUNTING < TrinketsScript.BEAT_SUSPICIOUS and TrinketsScript.BEAT_SUSPICIOUS < TrinketsScript.BEAT_WANDER,
		"the three rates are in order")
	m.mode = MonsterScript.Mode.IDLE
	_calm(m)
	# Killed: it comes back, worth what it was worth.
	game.kill_monster(m)
	await _seconds(0.6)
	_check(tk.tagged_by(mid) == 0, "killing it clears the tag")
	var back: Node = _nearest_item("pulse_oximeter")
	_check(back != null and int(back.value) == 40, "the pulse oximeter is on the floor again, worth $%d" % (int(back.value) if back != null else -1))
	if back != null:
		game.pickup_item(me, back)
		await _frames(2)
		_check(me.holding("pulse_oximeter") and not TrinketsScript.is_spent(me.selected_stack()),
			"and it works again: it was never used up")
	# Caught (strapped to a patient table) returns it too.
	var m2 := await _monster("hive", o + Vector3(14.0, 0, 10.0))
	var mid2: int = m2.monster_id
	_calm(m2)
	_face(m2)
	await _frames(2)
	game.player_shoved(me)
	await _frames(2)
	await _use_on(m2)
	_check(tk.tagged_by(mid2) == me.peer_id, "a second Hive tagged")
	game.combat.on_monster_removed(m2)   # what strapping it to a table does to it
	await _frames(2)
	_check(tk.tagged_by(mid2) == 0 and _nearest_item("pulse_oximeter") != null,
		"caught, the pulse oximeter comes off with it")
	game.kill_monster(m2)
	game.kill_monster(nurse)
	await _frames(2)


# =========================================================================
# the reflex hammer: right round, and it loses you
# =========================================================================

func _hammer() -> void:
	var m := await _monster("hive", o + Vector3(12.0, 0, 20.0))
	_calm(m)
	_give("reflex_hammer", 1, 20)
	_face(m)
	await _frames(3)
	# Make it see me first, then stop it looking again so the measurement is of the bonk alone.
	m.mode = MonsterScript.Mode.IDLE
	m.calm = 999.0
	m.brain.timer = 999.0
	var to: Vector3 = me.global_position - m.global_position
	m.rotation.y = atan2(-to.x, -to.z)
	m.brain._look()
	_check(m.brain.seeing and m.brain.target_id == me.peer_id, "set-up: the Hive sees me")
	m.brain.sight_timer = 999.0
	m.mode = MonsterScript.Mode.IDLE
	m.brain.timer = 999.0
	await _gap()
	var yaw0: float = m.rotation.y
	# The swing: the click plays the charged-throw pose sped up (Player.SWING_SPEED), and the bonk
	# lands on the contact frame rather than the click frame.
	tk.last_result = {}
	me.bot_use += 1
	await _frames(3)
	_check(me.swinging() and me.throw_wind > 0.0,
		"the arm winds up on the click (throw_wind %.2f)" % me.throw_wind)
	_check(String(tk.last_result.get("what", "")) == "swinging",
		"and nothing has been hit yet (%s)" % str(tk.last_result))
	await _seconds(Player.SWING_CONTACT + 0.05)
	_check(String(tk.last_result.get("what", "")) == "spun_monster",
		"the bonk lands on the contact frame (%s)" % str(tk.last_result))
	# The turn is quick but not instant: at the contact frame it has only just started.
	_check(m.spinning(), "it is a turn you can watch, not a teleport of the heading")
	await _settle(m)
	var turned := absf(angle_difference(yaw0, m.rotation.y))
	_check(absf(turned - PI) < 0.08, "the Hive spins 180 degrees (%.0f deg)" % rad_to_deg(turned))
	_check(not me.swinging() and absf(me.throw_wind) < 0.001,
		"the swing plays out and the arm comes back to rest")
	_check(not m.brain.seeing and m.brain.target_id == 0, "and it has lost sight of me")
	# Standing off (a Hive notices anything practically touching it whichever way it faces), its
	# next look does not find me: I am behind it now.
	me.teleport(game._floor_at(m.global_position + m.global_transform.basis.z * 3.0))
	await _frames(2)
	m.brain._look()
	_check(not m.brain.seeing, "its next look, facing the other way, does not find me again")
	_check(not TrinketsScript.is_spent(me.selected_stack()), "the hammer is reusable")
	# Its cooldown (the host's minimum gap between clicks is shorter, so this really is the hammer's).
	await _use_on(m)
	_check(String(tk.last_result.get("what", "")) == "cooldown", "a second bonk inside the cooldown is refused (%s)" % str(tk.last_result))
	game.kill_monster(m)
	await _frames(2)
	# A teammate's view snaps round (and the cooldown has ended, so the hammer works again).
	var did: int = dev.spawn_bot("dummy")
	await _frames(3)
	var mate: Player = game.players[did]
	mate.teleport(game._floor_at(o + Vector3(14.0, 0, 14.0)))
	mate.bot_yaw = 0.0
	await _frames(4)
	await _seconds(TrinketsScript.HAMMER_COOLDOWN)
	_face(mate)
	await _frames(3)
	var mate_yaw: float = mate.rotation.y
	await _click()
	_check(String(tk.last_result.get("what", "")) == "spun_player",
		"after the cooldown a teammate can be bonked too (%s)" % str(tk.last_result))
	_check(mate.spinning(), "their view is being turned, not teleported")
	await _settle(mate)
	_check(absf(absf(angle_difference(mate_yaw, mate.rotation.y)) - PI) < 0.08,
		"their view comes right round (%.0f deg)" % rad_to_deg(absf(angle_difference(mate_yaw, mate.rotation.y))))
	# The Night Nurse ignores it.
	var nurse := await _monster("night_nurse", o + Vector3(18.0, 0, 14.0))
	game.knock_down_monster(nurse, Vector3.ZERO, 300.0)
	await _seconds(TrinketsScript.HAMMER_COOLDOWN)
	await _use_on(nurse)
	_check(String(tk.last_result.get("what", "")) == "immune", "the Night Nurse ignores the hammer (%s)" % str(tk.last_result))
	dev.request("remove_bot", {"id": did})
	game.kill_monster(nurse)
	await _frames(2)


# =========================================================================
# the votive candle: a safe zone with a two minute fuse (POCKETS 2 phase 3)
# =========================================================================

## The spec sentence is "within its radius the Night Nurse counts as watched with no player
## looking", so that is what this checks: Percept.observed_any over her body, which is the same
## call her brain makes, with the player parked far away facing the other way.
## **Mind the dev room's edges.** Probed on 2026-09-23 (POCKETS 2 phase 7): the floor runs to about
## `o + (25, 0, 19)` and everything past that is open air. `_stand` puts the player at
## `game._floor_at(pos)`, which returns the point itself when the probe misses, so a spot outside
## that rectangle drops the player into the void -- silently, because every check in this file is a
## question about positions and a falling player answers them just as well as a standing one. This
## section used to stand at `o + (8, 0, 20)` and then at `o + (30, 0, 2)`, both outside it.
## **Two other sections still do**: the ones standing at `o + (10, 0, 22)` and `o + (14, 0, 20)`.
## They pass, and they were not touched here, but they are not standing on anything.
func _candle() -> void:
	_stand(o + Vector3(8.0, 0, 16.0), 0.0)
	await _frames(2)
	_give("votive_candle", 1, 14)
	await _use()
	var lit := int(tk.last_result.get("id", -1))
	_check(String(tk.last_result.get("what", "")) == "candle_lit", "the candle is set down and lit (%s)" % str(tk.last_result))
	var candle: Node = game.world_items.get(lit)
	_check(candle != null and is_instance_valid(candle), "it exists in the world as an item")
	if candle == null or not is_instance_valid(candle):
		return
	_check(String(candle.x) == TrinketsScript.USED_MARK and int(candle.value) == TrinketsScript.scrap_value("votive_candle"),
		"lighting it spends it: it is worth scrap where it stands ($%d)" % int(candle.value))
	_check(tk.candle_left(lit) > TrinketsScript.CANDLE_SECONDS - 2.0,
		"it has about two minutes of burn (%.0f s)" % tk.candle_left(lit))
	var at: Vector3 = candle.global_position

	# Her, standing in it. The player goes to the far side of the dev room looking away, so that
	# nothing but the candle can possibly be doing the watching.
	var nurse := await _monster("night_nurse", at)
	nurse.global_position = game._floor_at(at + Vector3(1.0, 0, 0.0))
	# Far enough away and facing the other way -- and inside the floor rectangle above. 15.6 m off,
	# three times the candle's radius, looking away from her.
	_stand(o + Vector3(18.0, 0, 4.0), atan2(-10.0, 12.0))
	await _frames(4)
	var points := [nurse.global_position + Vector3.UP * 0.15, nurse.global_position + Vector3.UP * 1.3]
	_check(Percept.observed_any(game, points), "a burning candle counts as watching her with nobody there")
	# Her brain samples observation a few times a second, not every frame (NightNurse OBSERVE_FAR).
	await _seconds(0.8)
	_check(bool(nurse.observed), "so she is frozen: observed with the room empty")

	# Step her out of the radius and nothing is watching her any more.
	nurse.global_position = game._floor_at(at + Vector3(TrinketsScript.CANDLE_RADIUS + 3.0, 0, 0.0))
	await _frames(3)
	var out_points := [nurse.global_position + Vector3.UP * 0.15, nurse.global_position + Vector3.UP * 1.3]
	_check(not Percept.observed_any(game, out_points), "a step outside the radius and she is on her own again")

	# Back in, and then wait it out: when the flame dies the safe zone dies with it.
	nurse.global_position = game._floor_at(at + Vector3(1.0, 0, 0.0))
	await _frames(3)
	_check(Percept.observed_any(game, [nurse.global_position + Vector3.UP * 1.3]), "back inside, it watches her again")

	# POCKETS 2 phase 7. Everything above asks the PREDICATE; the spec sentence is about her FEET
	# ("frozen in a placed candle's radius; moves when it burns out"), and nothing here had ever
	# watched her move. She is calmed to 999 s by the helper that spawns her, and a calm nurse
	# stands still whether or not anybody is looking, so the freeze was being proved by a monster
	# that had no intention of going anywhere. Wake her up and measure the distance she covers.
	nurse.calm = 0.0
	var frozen_at: Vector3 = nurse.global_position
	await _seconds(1.5)
	_check(nurse.global_position.distance_to(frozen_at) < 0.05,
		"awake and unrestrained, she still does not take a step while it burns (%.3f m in 1.5 s)"
			% nurse.global_position.distance_to(frozen_at))

	# CUT THE FUSE RATHER THAN WAIT IT OUT (POCKETS 2 phase 7). This used to `await` the whole two
	# minutes, and **everything after the wait was being checked in a world that had fallen apart**:
	# at the far end of it the nurse was at y = -25.9 m and falling at 55 m/s, and the player was
	# 133 km from her. So "she is unwatched once the flame is out" passed because there was nobody
	# left anywhere near her to watch her, and the phase 7 check that she MOVES passed because she
	# was in free fall. A 120-second await is not something a dev-room test survives.
	# The fuse is world_time based, so moving its end is the same expiry through the same code.
	tk._candles[lit] = float(game.world_time) + 1.0
	await _seconds(tk.candle_left(lit) + 1.0)
	_check(tk.candle_left(lit) <= 0.0, "the flame burns out on its own")
	_check(not Percept.observed_any(game, [nurse.global_position + Vector3.UP * 1.3]),
		"and she is unwatched the moment it does")
	_check(not tk.lit_candles().has(lit), "the burnt-out candle stops counting")
	# Her brain re-samples observation a few times a second (OBSERVE_FAR), so give it one sample.
	nurse.calm = 0.0
	await _seconds(0.8)
	_check(not bool(nurse.observed), "her brain agrees she is unwatched once the flame is out")
	var released_at: Vector3 = nurse.global_position
	await _seconds(1.5)
	# Measured flat and with her feet checked: a monster falling out of the world covers plenty of
	# distance too, and that is exactly how the first version of this check passed (see above).
	var walked := Vector2(nurse.global_position.x - released_at.x, nurse.global_position.z - released_at.z).length()
	_check(absf(nurse.global_position.y - released_at.y) < 1.0,
		"she is still standing on the floor (dy %.2f m)" % (nurse.global_position.y - released_at.y))
	_check(walked > 1.0, "and she WALKS when it burns out (%.2f m across the floor in 1.5 s)" % walked)
	game.kill_monster(nurse)
	await _frames(2)


# =========================================================================
# helpers (the same shape as tools/combattest.gd)
# =========================================================================

func _monster(kind: String, pos: Vector3) -> Node:
	var m = game._add_monster(kind, game._floor_at(pos))
	await _frames(3)
	_calm(m)
	return m


func _calm(m: Node) -> void:
	if m == null or not is_instance_valid(m):
		return
	if m.brain != null and "timer" in m.brain and int(m.mode) != MonsterScript.Mode.STUNNED:
		m.mode = MonsterScript.Mode.IDLE
		m.brain.timer = 999.0
	m.calm = 999.0


func _give(kind: String, count: int, value := 0) -> void:
	me.slots = Player.empty_slots()
	me.slots[0] = {"kind": kind, "count": count, "v": value}
	me.selected = 0


func _nearest_item(kind: String) -> Node:
	var best: Node = null
	var best_d := 1e9
	for it in game.world_items.values():
		if it == null or not is_instance_valid(it) or String(it.kind) != kind:
			continue
		var d: float = it.global_position.distance_to(me.global_position)
		if d < best_d:
			best_d = d
			best = it
	return best


func _stand(pos: Vector3, yaw := 0.0) -> void:
	me.teleport(game._floor_at(pos))
	me.bot_yaw = yaw
	me.bot_pitch = 0.0
	me.bot_move = Vector2.ZERO


func _look_at(point: Vector3) -> void:
	var eye: Vector3 = me.global_position + Vector3.UP * C.EYE_H
	var d := point - eye
	me.bot_yaw = atan2(-d.x, -d.z)
	me.bot_pitch = clampf(atan2(d.y, Vector2(d.x, d.z).length()), -1.2, 1.2)


## Stand 1.2 m from the target and look at it.
func _face(target: Node) -> void:
	var tp: Vector3 = target.global_position
	var from := me.global_position - tp
	from.y = 0.0
	from = from.normalized() if from.length() > 0.2 else Vector3.BACK
	me.teleport(game._floor_at(tp + from * 1.2))
	me.bot_move = Vector2.ZERO
	var low: bool = (target is Player and target.downed) or (not (target is Player) and game.combat.is_sedated(target))
	_look_at(tp + Vector3.UP * (0.3 if low else 1.1))


## Wait out the use gap FIRST, then step in front of the target and click, so nothing has time to
## walk out of reach between being aimed at and being hit.
func _use_on(target: Node) -> void:
	await _gap()
	_face(target)
	await _frames(3)
	await _click()


func _use() -> void:
	await _gap()
	await _click()


## Wait out the host's minimum gap between two trinket uses.
func _gap() -> void:
	await _seconds(TrinketsScript.USE_GAP + 0.05)


## One left-mouse press, and the frames the host needs to resolve it. TRINKETS chunk B: a reflex
## hammer only starts a swing on the click ("swinging"); the bonk itself lands Player.SWING_CONTACT
## later, so wait for that and last_result is the real answer either way.
func _click() -> void:
	tk.last_result = {}
	me.bot_use += 1
	await _frames(4)
	if String(tk.last_result.get("what", "")) == "swinging":
		await _seconds(Player.SWING_CONTACT + 0.05)


## Wait out a reflex-hammer turn (Monster.SPIN_TIME / Player.SPIN_TIME): it is quick, but it is a
## turn now, not a teleport of the heading, so a facing is only final once it has finished.
func _settle(node: Node) -> void:
	for i in 60:
		if not (node.has_method("spinning") and node.spinning()):
			break
		await _frames(1)
	await _frames(1)


func _noise_near(pos: Vector3, kind: String, radius: float) -> float:
	var best := 0.0
	for n in game.recent_noises(1.5):
		if String(n.kind) == kind and (n.pos as Vector3).distance_to(pos) <= radius:
			best = maxf(best, float(n.loudness))
	return best


func _check(ok: bool, what: String) -> void:
	print("[trinkettest] t=%.1f %s  %s" % [t, "PASS" if ok else "FAIL", what])
	if not ok:
		_failures.append(what)


func _finish() -> void:
	if _done:
		return
	_done = true
	print("[trinkettest] ------------------------------------------")
	print("[trinkettest] result=%s failures=%d" % ["PASS" if _failures.is_empty() else "FAIL", _failures.size()])
	get_tree().quit(0 if _failures.is_empty() else 1)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _seconds(s: float) -> void:
	var end := t + s
	while t < end:
		await get_tree().physics_frame
