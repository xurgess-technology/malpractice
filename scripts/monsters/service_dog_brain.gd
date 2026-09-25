extends RefCounted
## The Service Dog, host side. It wants to play fetch, and it is not asking.
##
##   IDLE / WANDER  pads about the wing (random_nav_point, so the entrance and neutral fences hold
##                  for free). Carrying nothing, it keeps an eye out for a loose two-handed item.
##   DOG_SEEK       walks to an eligible item (Items.is_bulky, LOOSE, settled, somewhere it may
##                  wander) and takes it in its mouth: the WorldItem is removed, exactly like a
##                  player's pickup, and the stack rides in `carried` (and on the wire as `ck`).
##   DOG_APPROACH   carrying something, it has SEEN a surgeon (a Hive-style cone and a clear line):
##                  it walks up to them at a walk, not a run, head held a little too high.
##   DOG_OFFER      stops with its mouth OFFER_BEYOND_MOUTH short of them, lowers its head and sets the item on the floor at their
##                  feet (a fresh WorldItem, tagged with this offer's `offer_tag`).
##   DOG_WARN       stands and watches. Growls once, maybe twice. FETCH_WINDOW seconds on the clock
##                  (`offer_left`, on the wire as `ol`; never drawn -- the growls and its stare are the
##                  only tells). A charged throw of THAT
##                  item by anybody (game.dog_item_thrown -> item_thrown) satisfies it.
##   DOG_DRAIN      the clock ran out: it rises onto its hind legs (REAR_RISE), jaws wide, a glowing orb
##                  at the back of its throat, and DRAINS the surgeon it offered to (`target_id`, no
##                  one else): inside DRAIN_RANGE with a clear line, hearts go on the Onlooker's
##                  pacing (a grace, then ticks that shorten). It does not hold them -- they can walk,
##                  pick up and throw -- and it follows upright, silently, at walking pace. It ends when
##                  ANYBODY throws that same item with a charge, or when its surgeon is down or gone.
##   DOG_RETRIEVE   satisfied (or its surgeon is out): down on all fours, it trots to wherever the
##                  item ended up, takes it back in its mouth, and goes back to wandering. It stays
##                  CONTENT_TIME seconds before it will offer anything again.
##   STUNNED        a shove (on all fours only): down for SHOVE_STUN, then back to what it was doing;
##                  the fetch clock does not run while it is down. Sedated, it drops what it carries.
##
## Identity is the item, not the thrower: a pickup destroys the WorldItem node and a throw spawns a
## new one, so the offer's identity is a tag (`offer_tag`) that rides the stack through a hand slot
## ("dg") and back out onto the new WorldItem (game.gd "Service Dog"). Whoever throws it, it counts.
##
## Vulnerable on all fours, like a Hive: shove (stun), needle, drag, saw (Monster.can_be_hurt /
## capturable_now). Upright and draining it is none of those: shove, saw and needle do nothing.

const M := preload("res://scripts/monsters/modes.gd")

const SIGHT_RANGE := 14.0
const SIGHT_DEG := 120.0
const SIGHT_INTERVAL := 0.25
const EYE_H := 1.45
## How far it looks for an item to carry, and how often.
const ITEM_RANGE := 22.0
const ITEM_INTERVAL := 1.0

const SPEED_WANDER := 1.1
const SPEED_SEEK := 1.4
const SPEED_APPROACH := 1.5      ## a walk: it is not charging you, and that is the unsettling part
const SPEED_RETRIEVE := 2.6      ## a happy trot

## Where it stops to put the item down: its MOUTH this far from the surgeon (horizontal). Distances
## that depend on how far its mouth reaches ahead of its middle use Monster.dog_reach(), measured
## off whatever body it has (about 1.35 m on the placeholder's long neck, 0.8 m on the art's model),
## so neither body's proportions are baked in here.
const OFFER_BEYOND_MOUTH := 1.0
## The set-down: head lowers over OFFER_TIME, the item leaves its mouth at OFFER_DROP_AT.
const OFFER_TIME := 1.3
const OFFER_DROP_AT := 0.85
## The fetch clock, from the moment the item is on the floor.
const FETCH_WINDOW := 12.0
## Growls during the warning: the first as the clock starts, maybe a second a little later.
const GROWL_AT := 0.2
const GROWL2_AT := Vector2(2.2, 3.4)
const GROWL2_CHANCE := 0.6
## While the clock runs it stays near its surgeon: further than this and it pads after them.
const WARN_FOLLOW := 5.5
## Rising onto its hind legs (the `rear_up` clip is 0.6-0.8 s), and dropping back (`drop_down`, ~0.4 s).
const REAR_RISE := 0.7
const REAR_DROP := 0.4
## The drain: only its own surgeon, only this close (flat metres from its middle) and with a clear line
## from its throat to their face.
const DRAIN_RANGE := 4.0
## Upright it walks after them at a little under a surgeon's walk (C.WALK_SPEED 3.4): walking away
## keeps the gap, sprinting opens it. It stops this far off, standing over them.
const SPEED_DRAIN := 3.1
const DRAIN_STAND := 2.2
## The Onlooker's pacing (onlooker_brain.gd GRACE / TICK_*), shorter: the fetch clock was the grace.
## Seconds of drain in range before the first heart; then each gap is RAMP times the last, floored.
## 2.5 -> 4.5 -> 3.4 -> 2.5 -> 2.0: three hearts go in about 10 s of standing in it.
const DRAIN_GRACE := 2.5
const DRAIN_TICK_FIRST := 4.5
const DRAIN_TICK_RAMP := 0.75
const DRAIN_TICK_MIN := 2.0
## Out of range the meter bleeds back down at this many seconds per second (the Onlooker's look-away).
const DRAIN_DECAY := 0.5
## The orb's glow (replicated as `og`, 0..1): dim at rest, full while it drains someone in range.
const GLOW_REST := 0.12
const GLOW_OUT_OF_RANGE := 0.45
const GLOW_RATE := 2.0
## A shove on all fours, like the Hive's.
const SHOVE_STUN := 2.0
## After a fetch (or a give-up) it will not offer again for this long.
const CONTENT_TIME := 20.0
## Walking toward the surgeon it gives up if it has not seen them for this long.
const APPROACH_LOST := 6.0
const APPROACH_MAX := 30.0
## Taking an item in its mouth: its mouth within this of the item (and the item slow enough).
const TAKE_BEYOND_MOUTH := 0.3
## An item it could not get to is left alone this long before it tries it again.
const SKIP_TIME := 60.0
const TAKE_TIME := 0.5
const RETRIEVE_GIVE_UP := 25.0
## How often it checks the tagged item still exists somewhere (a player could sell it).
const EXIST_INTERVAL := 1.0
## The throw that counts: `charge` as game.drop_selected(p, charge) gets it, 0..1, above this. A tap
## reports charge 0 there (Player.DROP_TAP_MAX is SECONDS of hold that count as a tap, not a charge,
## and is never compared with a charge). Zach: ~0.1 for this mechanic, not a full charge. Tune here.
const THROW_MIN_CHARGE := 0.1

var m: CharacterBody3D
var rng := RandomNumberGenerator.new()

var timer := 0.0
var wander_goal = null
var sight_timer := 0.0
var item_timer := 0.0
var exist_timer := 0.0
## peer id of the surgeon it is offering to / going for, 0 none.
var target_id := 0
var last_seen := Vector3.ZERO
var lost_t := 0.0
## What it holds in its mouth: {kind, count, v, bt, x}, or {} for nothing.
var carried: Dictionary = {}
## The item it is walking to (DOG_SEEK) or fetching back (DOG_RETRIEVE): a WorldItem, or null.
var goal_item: Node = null
## This offer's tag (game.dog_new_tag), 0 when no item of ours is out in the world.
var offer_tag := 0
## Seconds left on the fetch clock (DOG_WARN).
var offer_left := 0.0
var content := 0.0
var satisfied := false
var growls := 0
var _growl2_at := -1.0
var _rise := 0.0
## The drain meter (seconds in range, bleeding down out of range), the next heart, and the orb.
var drain_t := 0.0
var tick_left := 0.0
var ticks := 0
var glow := GLOW_REST
var in_range := false
## What it goes back to when a stun ends.
var _resume := -1
var _take := 0.0
var _stuck_check := 0.0
var _stuck_from := Vector3.ZERO
## item id -> brain clock until which it will not try for that item again (could not reach it).
var _skip := {}
var _clock := 0.0
## How many fetches it has had (tests; also shows in the log).
var fetches := 0
var hearts := 0


func _init(monster: CharacterBody3D) -> void:
	m = monster
	rng.seed = hash("service_dog%d" % monster.monster_id)
	sight_timer = rng.randf_range(0.0, SIGHT_INTERVAL)
	item_timer = rng.randf_range(0.0, ITEM_INTERVAL)
	m.mode = M.Mode.IDLE
	timer = rng.randf_range(0.5, 2.0)


# =========================================================================
# the loop (host, Monster._physics_process)
# =========================================================================

func think(delta: float) -> void:
	timer -= delta
	_clock += delta
	if m.mode == M.Mode.STUNNED:
		_stunned(delta)
		_publish()
		return
	content = maxf(0.0, content - delta)
	match m.mode:
		M.Mode.DOG_SEEK:
			_seek(delta)
		M.Mode.DOG_APPROACH:
			_approach(delta)
		M.Mode.DOG_OFFER:
			_offer(delta)
		M.Mode.DOG_WARN:
			_warn(delta)
		M.Mode.DOG_DRAIN:
			_drain(delta)
		M.Mode.DOG_RETRIEVE:
			_retrieve(delta)
		M.Mode.WANDER:
			m.state = M.State.WANDER
			if wander_goal == null:
				wander_goal = m.random_nav_point(m.global_position, 4.0, 16.0)
			var left: float = m.nav_move(wander_goal, SPEED_WANDER, delta)
			if left < 0.7 or _stuck(delta, 3.0):
				_start_idle()
			_scan(delta)
		_:
			m.state = M.State.WANDER
			m.stop()
			if timer <= 0.0:
				_start_wander()
			_scan(delta)
	if m.mode != M.Mode.DOG_DRAIN:
		_rise = maxf(0.0, _rise - delta * (REAR_RISE / REAR_DROP))
		in_range = false
	glow = move_toward(glow, _glow_want(), delta * GLOW_RATE)
	_publish()


func _glow_want() -> float:
	if m.mode != M.Mode.DOG_DRAIN:
		return GLOW_REST
	if _rise < REAR_RISE:
		return lerpf(GLOW_REST, GLOW_OUT_OF_RANGE, _rise / REAR_RISE)
	return 1.0 if in_range else GLOW_OUT_OF_RANGE


## What every machine needs to see, onto the Monster (report() sends it).
func _publish() -> void:
	m.dog_carry = String(carried.get("kind", ""))
	m.dog_target = target_id if (m.mode == M.Mode.DOG_APPROACH or m.mode == M.Mode.DOG_OFFER \
			or m.mode == M.Mode.DOG_WARN or m.mode == M.Mode.DOG_DRAIN) else 0
	m.dog_left = offer_left if m.mode == M.Mode.DOG_WARN else 0.0
	m.dog_growls = growls
	m.dog_offer_kind = _last_offer_kind if offer_tag != 0 else ""
	m.dog_glow = glow


## The kind of the item it last put down (replicated as `ok`).
var _last_offer_kind := ""


## Wandering or idling: carrying something, look for a surgeon; carrying nothing, look for a thing.
func _scan(delta: float) -> void:
	if carried.is_empty():
		item_timer -= delta
		if item_timer <= 0.0:
			item_timer += ITEM_INTERVAL
			var it := _find_item()
			if it != null:
				goal_item = it
				_set_mode(M.Mode.DOG_SEEK)
		return
	if content > 0.0:
		return
	sight_timer -= delta
	if sight_timer <= 0.0:
		sight_timer += SIGHT_INTERVAL
		var p := _look()
		if p != null:
			target_id = int(p.peer_id)
			last_seen = p.global_position
			lost_t = 0.0
			_set_mode(M.Mode.DOG_APPROACH)


# =========================================================================
# the modes
# =========================================================================

func _seek(delta: float) -> void:
	m.state = M.State.WANDER
	if not _item_ok(goal_item, true):
		goal_item = null
		_start_wander()
		return
	var at: Vector3 = goal_item.global_position
	if _take > 0.0:
		# Head down over it (the rig reads SEEK + standing still as "nosing at the floor").
		m.stop()
		m.face_dir(at - m.global_position, delta, 6.0)
		_take -= delta
		if _take <= 0.0:
			_take_in_mouth(goal_item)
			goal_item = null
			content = maxf(content, 3.0)   # a beat before it goes looking for someone
			_start_wander()
		return
	var left: float = _flat(at)
	if left <= _take_reach():
		_take = TAKE_TIME
		m.stop()
		return
	m.nav_move(at, SPEED_SEEK, delta)
	if timer <= 0.0 or _stuck(delta, 4.0):
		_skip[int(goal_item.item_id)] = _clock + SKIP_TIME   # can't get to it: leave it be a while
		goal_item = null
		_start_idle()


func _approach(delta: float) -> void:
	m.state = M.State.WANDER
	var p := _target()
	if p == null or carried.is_empty():
		_give_up()
		return
	sight_timer -= delta
	var seeing := false
	if sight_timer <= 0.0:
		sight_timer += SIGHT_INTERVAL
		seeing = _can_see(p)
		if seeing:
			last_seen = p.global_position
			lost_t = 0.0
	lost_t += delta
	if lost_t > APPROACH_LOST or _flat(p.global_position) > APPROACH_MAX:
		_give_up()
		return
	var d := _flat(last_seen)
	var offer_dist: float = m.dog_reach() + OFFER_BEYOND_MOUTH
	if d <= offer_dist and _flat(p.global_position) <= offer_dist + 0.6 and m.clear_line(m.global_position + Vector3.UP * 0.6, p.global_position + Vector3.UP * 0.6):
		m.stop()
		_set_mode(M.Mode.DOG_OFFER)
		timer = OFFER_TIME
		return
	m.nav_move(last_seen, SPEED_APPROACH, delta)


func _offer(delta: float) -> void:
	m.state = M.State.WANDER
	var p := _target()
	m.stop()
	if p != null:
		m.face_dir(p.global_position - m.global_position, delta, 5.0)
	# The item leaves its mouth part way down.
	if not carried.is_empty() and timer <= OFFER_TIME - OFFER_DROP_AT:
		_put_down(p)
	if timer > 0.0:
		return
	if satisfied:
		_fetch_back()   # thrown before it had even straightened up
		return
	if offer_tag == 0:
		_give_up()   # nothing went down (it had nothing): back to wandering
		return
	if p == null:
		_fetch_back()
		return
	_set_mode(M.Mode.DOG_WARN)
	offer_left = FETCH_WINDOW
	_growl2_at = FETCH_WINDOW - rng.randf_range(GROWL2_AT.x, GROWL2_AT.y) if rng.randf() < GROWL2_CHANCE else -1.0
	timer = GROWL_AT


func _warn(delta: float) -> void:
	m.state = M.State.WANDER
	if satisfied:
		_fetch_back()
		return
	var p := _target()
	if p == null:
		_fetch_back()   # its surgeon went down or left: go and get its toy
		return
	offer_left = maxf(0.0, offer_left - delta)
	if timer <= 0.0 and growls_this_offer == 0:
		_growl()
	elif _growl2_at > 0.0 and offer_left <= _growl2_at:
		_growl2_at = -1.0
		_growl()
	var to: Vector3 = p.global_position - m.global_position
	if Vector2(to.x, to.z).length() > WARN_FOLLOW:
		m.nav_move(p.global_position, SPEED_APPROACH, delta)
	else:
		m.stop()
		m.face_dir(to, delta, 4.0)
	_check_exists(delta)
	if offer_tag == 0:
		return   # the item is gone for good (_check_exists gave up)
	if offer_left <= 0.0:
		_set_mode(M.Mode.DOG_DRAIN)
		m.state = M.State.CHASE
		_rise = 0.0
		drain_t = 0.0
		tick_left = 0.0
		ticks = 0


var growls_this_offer := 0


func _drain(delta: float) -> void:
	m.state = M.State.CHASE
	if satisfied:
		_fetch_back()
		return
	var p := _target()
	if p == null:
		_fetch_back()   # down, dead or gone: it is done with them
		return
	_check_exists(delta)
	if offer_tag == 0:
		return
	var to: Vector3 = p.global_position - m.global_position
	if _rise < REAR_RISE:
		# Up onto its hind legs in front of them, jaws opening, looking at them the whole way.
		_rise += delta
		m.stop()
		m.face_dir(to, delta, 6.0)
		return
	_drain_follow(p, delta)
	var throat: Vector3 = m.dog_mouth_world()
	var face: Vector3 = p.global_position + Vector3.UP * (C.EYE_H - 0.12)
	in_range = _flat(p.global_position) <= DRAIN_RANGE and m.clear_line(throat, face)
	if in_range:
		drain_t += delta
	else:
		drain_t = maxf(0.0, drain_t - delta * DRAIN_DECAY)
	# The Onlooker's clock: at zero below the grace line, so the FIRST heart lands the moment the
	# meter passes it; each gap after that is shorter than the last.
	if drain_t >= DRAIN_GRACE and in_range:
		tick_left -= delta
		if tick_left <= 0.0:
			tick_left = maxf(DRAIN_TICK_MIN, DRAIN_TICK_FIRST * pow(DRAIN_TICK_RAMP, float(ticks)))
			ticks += 1
			hearts += 1
			if m.game.has_method("dog_drain_heart"):
				m.game.dog_drain_heart(m, p)
	elif drain_t < DRAIN_GRACE:
		tick_left = 0.0
		ticks = 0


## Upright it keeps after them: a slow, stiff walk, never faster than a surgeon's walk, no lunge, no
## sound. Its own function so a different way of following (a glide) can replace it later.
func _drain_follow(p: Node, delta: float) -> void:
	var to: Vector3 = p.global_position - m.global_position
	if _flat(p.global_position) > DRAIN_STAND:
		m.nav_move(p.global_position, SPEED_DRAIN, delta)
		m.face_dir(to, delta, 8.0)   # the head never leaves them, even round a corner
	else:
		m.stop()
		m.face_dir(to, delta, 6.0)


## A shove put it down (only ever on all fours). Back to what it was doing when the time is up.
func _stunned(_delta: float) -> void:
	m.state = M.State.STUNNED
	m.stop()
	if timer > 0.0:
		return
	var back := _resume if _resume >= 0 else M.Mode.WANDER
	_resume = -1
	var keep_timer := timer
	m.mode = back
	m._repath = 0.0
	if back == M.Mode.DOG_RETRIEVE or back == M.Mode.DOG_SEEK:
		timer = RETRIEVE_GIVE_UP if back == M.Mode.DOG_RETRIEVE else 20.0
	elif back == M.Mode.DOG_OFFER:
		timer = 0.0   # finish the set-down at once
	elif back == M.Mode.IDLE:
		timer = rng.randf_range(0.5, 1.5)
	else:
		timer = keep_timer


func _retrieve(delta: float) -> void:
	m.state = M.State.WANDER
	if _rise > 0.0:
		# Back down onto all fours first (think() drops _rise; the `drop_down` clip).
		m.stop()
		return
	var it: Node = m.game.dog_tagged_item(offer_tag) if offer_tag != 0 else null
	if it == null:
		# Someone is holding it, or it is gone: nothing to fetch. Back to wandering, empty-mouthed.
		_forget_offer()
		content = maxf(content, CONTENT_TIME)
		_start_wander()
		return
	var at: Vector3 = it.global_position
	if _take > 0.0:
		m.stop()
		m.face_dir(at - m.global_position, delta, 6.0)
		_take -= delta
		if _take <= 0.0:
			_take_in_mouth(it)
			_forget_offer()
			fetches += 1
			content = maxf(content, CONTENT_TIME)
			_start_wander()
		return
	var flying: bool = not bool(it.freeze) and (it.linear_velocity as Vector3).length() > 1.2
	if _flat(at) <= _take_reach() and not flying and absf(at.y - m.global_position.y) < 1.4:
		_take = TAKE_TIME
		m.stop()
		return
	m.nav_move(at, SPEED_RETRIEVE, delta)
	if timer <= 0.0:
		# Could not reach it: leave it where it lies.
		_forget_offer()
		content = maxf(content, CONTENT_TIME)
		_start_wander()


# =========================================================================
# transitions and helpers
# =========================================================================

func _set_mode(mode: int) -> void:
	m.mode = mode
	m._repath = 0.0
	wander_goal = null
	_take = 0.0
	_stuck_check = 0.0
	_stuck_from = m.global_position
	match mode:
		M.Mode.DOG_SEEK:
			timer = 20.0
		M.Mode.DOG_RETRIEVE:
			timer = RETRIEVE_GIVE_UP
		M.Mode.DOG_WARN:
			growls_this_offer = 0


func _start_wander() -> void:
	_set_mode(M.Mode.WANDER)
	m.state = M.State.WANDER


func _start_idle() -> void:
	_set_mode(M.Mode.IDLE)
	m.state = M.State.WANDER
	timer = rng.randf_range(1.5, 4.0)


## Lost its surgeon before anything went down: carry on wandering with the item still in its mouth.
func _give_up() -> void:
	target_id = 0
	content = maxf(content, 6.0)
	_start_wander()


## Satisfied (a throw), or its surgeon is out of the game: drop to all fours and go and get it.
func _fetch_back() -> void:
	target_id = 0
	offer_left = 0.0
	satisfied = false
	in_range = false
	drain_t = 0.0
	m.lunge_t = 0.0
	_set_mode(M.Mode.DOG_RETRIEVE)


func _forget_offer() -> void:
	offer_tag = 0
	target_id = 0
	offer_left = 0.0
	goal_item = null


func _growl() -> void:
	growls += 1
	growls_this_offer += 1


## Put what it carries on the floor in front of `p` (or in front of itself), tagged as this offer.
func _put_down(p: Node) -> void:
	var fwd: Vector3 = -m.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length() > 0.01 else Vector3.FORWARD
	var mouth: Vector3 = m.dog_mouth_world()
	var from := Transform3D(Basis(Vector3.UP, m.rotation.y + PI * 0.5), mouth)
	var vel := fwd * 0.9 + Vector3.UP * 0.4
	if p != null:
		var to: Vector3 = p.global_position - mouth
		to.y = 0.0
		if to.length() > 0.01:
			vel = to.normalized() * clampf(to.length() - 0.7, 0.3, 1.2) + Vector3.UP * 0.5
	offer_tag = m.game.dog_new_tag()
	satisfied = false
	_last_offer_kind = String(carried.get("kind", ""))
	m.game.dog_place_item(carried, from, vel, offer_tag)
	carried = {}


func _take_in_mouth(it: Node) -> void:
	carried = m.game.dog_take_item(it)


## Every EXIST_INTERVAL: is the offered item anywhere at all (loose, or in somebody's hands)? If a
## player sold it or shelved it there is nothing left to be satisfied by, so it stands down.
func _check_exists(delta: float) -> void:
	exist_timer -= delta
	if exist_timer > 0.0:
		return
	exist_timer = EXIST_INTERVAL
	if offer_tag == 0 or not m.game.has_method("dog_tag_exists") or m.game.dog_tag_exists(offer_tag):
		return
	_forget_offer()
	content = maxf(content, CONTENT_TIME)
	_start_wander()


## An eligible item to carry: loose, two-handed, settled on something, somewhere it may wander to,
## and not already somebody's offer.
func _item_ok(it: Node, allow_moving := false) -> bool:
	if it == null or not is_instance_valid(it) or not it.is_inside_tree():
		return false
	if int(it.state) != 1:   # WorldItem.State.LOOSE
		return false
	if not Items.is_bulky(String(it.kind)):
		return false
	if int(it.get("dog_tag")) != 0:
		return false
	if not allow_moving and not bool(it.freeze):
		return false
	var at: Vector3 = it.global_position
	if absf(at.y - m.global_position.y) > 1.6:
		return false
	if m.game.has_method("monster_may_wander_to") and not m.game.monster_may_wander_to(at, m.global_position):
		return false
	return true


func _find_item() -> Node:
	var best: Node = null
	var best_d := ITEM_RANGE
	for it in (m.game.world_items as Dictionary).values():
		if float(_skip.get(int(it.item_id), -1.0)) > _clock or not _item_ok(it):
			continue
		var d := _flat(it.global_position)
		if d < best_d:
			best_d = d
			best = it
	return best


## The nearest surgeon it can see: a cone and a clear line, like the Hive.
func _look() -> Node:
	var best: Node = null
	var best_d := SIGHT_RANGE
	for p in m.game.alive_players():
		var d := _flat(p.global_position)
		if d > best_d:
			continue
		if _can_see(p):
			best = p
			best_d = d
	return best


func _can_see(p: Node) -> bool:
	var to: Vector3 = p.global_position - m.global_position
	to.y = 0.0
	var d := to.length()
	if d > SIGHT_RANGE:
		return false
	var fwd: Vector3 = -m.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	if d > 1.5 and fwd.dot(to / maxf(d, 0.001)) < cos(deg_to_rad(SIGHT_DEG * 0.5)):
		return false
	var eye: Vector3 = m.global_position + Vector3.UP * EYE_H
	return m.clear_line(eye, p.global_position + Vector3.UP * 1.6) or m.clear_line(eye, p.global_position + Vector3.UP * 1.0)


## Its surgeon, if they are still on their feet (monsters ignore the downed).
func _target() -> Node:
	if target_id == 0:
		return null
	for p in m.game.alive_players():
		if "peer_id" in p and int(p.peer_id) == target_id:
			return p
	return null


func _take_reach() -> float:
	return m.dog_reach() + TAKE_BEYOND_MOUTH


func _flat(at: Vector3) -> float:
	return Vector2(at.x - m.global_position.x, at.z - m.global_position.z).length()


func _stuck(delta: float, window: float) -> bool:
	_stuck_check += delta
	if _stuck_check < window:
		return false
	var moved: float = m.global_position.distance_to(_stuck_from)
	_stuck_check = 0.0
	_stuck_from = m.global_position
	return moved < 0.3


# =========================================================================
# events from the game (host)
# =========================================================================

## game.dog_item_thrown: a stack carrying `tag` just left somebody's hands with a charge past a tap.
## Only this dog's current offer counts, and only while it is waiting or attacking.
func item_thrown(tag: int) -> bool:
	if tag == 0 or tag != offer_tag:
		return false
	# Waiting, draining, still setting it down, or knocked down part way through any of those.
	var mode: int = _resume if m.mode == M.Mode.STUNNED else int(m.mode)
	if mode != M.Mode.DOG_WARN and mode != M.Mode.DOG_DRAIN and mode != M.Mode.DOG_OFFER:
		return false
	satisfied = true
	return true


## True while it is up on its hind legs draining: shove, saw and needle do nothing to it then.
func upright() -> bool:
	return m.mode == M.Mode.DOG_DRAIN


## It never lands a blow (the drain is its only harm), so there is nothing to recoil from.
func recoil_after_hit() -> void:
	pass


## On all fours, a shove puts it down like a Hive's; upright it does nothing.
func shoved(dir: Vector3) -> void:
	stun(dir, SHOVE_STUN, 1.0)


## Knocked off its feet for `seconds` (Monster.shoved's charged shove, the dev knock-down). Upright and
## draining it does not budge. `then_hunt` is ignored: it does not hunt.
func stun(dir: Vector3, seconds: float, push := 0.6, _then = null) -> void:
	if upright() or m.mode == M.Mode.SEDATED or seconds <= 0.0:
		return
	dir.y = 0.0
	if dir.length() > 0.01 and push > 0.0:
		m.move_and_collide(dir.normalized() * push)
	if m.mode != M.Mode.STUNNED:
		_resume = int(m.mode)
		timer = seconds
	else:
		timer = maxf(timer, seconds)
	_take = 0.0
	m.mode = M.Mode.STUNNED
	m.state = M.State.STUNNED
	m.lunge_t = 0.0


## Put under: what it carried drops where it lies, and its offer (if one is out) is nobody's now.
func sedated() -> void:
	released()


## It is being taken out of the game (killed, or asleep): nothing of it stays in anyone's hands.
func released() -> void:
	if not carried.is_empty() and m.game.has_method("dog_place_item"):
		var at := Transform3D(Basis(), m.global_position + Vector3.UP * 0.6 - m.global_transform.basis.z * 0.6)
		m.game.dog_place_item(carried, at, Vector3.UP * 0.5, 0)
	carried = {}
	if offer_tag != 0 and m.game.has_method("dog_release_tag"):
		m.game.dog_release_tag(offer_tag)
	_forget_offer()
	goal_item = null
	satisfied = false
	in_range = false
	_rise = 0.0
	_resume = -1
	_publish()


func woke(_hunt_pos) -> void:
	_resume = M.Mode.WANDER
	m.mode = M.Mode.STUNNED
	m.state = M.State.STUNNED
	timer = 1.2
	content = maxf(content, CONTENT_TIME)


func alert_to(_pos: Vector3) -> void:
	pass


## The reflex hammer turned it round: it simply turns back. Nothing is forgotten.
func spun_around() -> void:
	sight_timer = maxf(sight_timer, float(m.SPIN_TIME) + 0.05)


## Host (review setups and tests): put `stack` straight into its mouth.
func give(stack: Dictionary) -> void:
	carried = stack.duplicate()
	if not carried.has("count"):
		carried["count"] = 1
	_publish()
