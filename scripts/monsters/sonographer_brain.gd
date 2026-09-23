extends RefCounted
## The Sonographer, host side. Completely blind: it knows only what it hears, and what an echo
## showed it (docs/SONOGRAPHER.md, chunk B).
##
##   WANDER   drifts between corridor spots at 1.4 m/s, clicking as it goes
##   LISTEN   a noise reached it: it stops dead, cocks its head toward the sound for
##            0.8-1.2 s (the clicking stops, which is the tell). Quiet noises fill `suspicion`
##            while it listens; a loud one (>= LOUD) sends it straight there instead.
##   CHARGE   the meter is full: about CHARGE_TIME s at full stretch, the wand coming up to
##            point where it heard the noise, the glow running throat -> wand
##   ECHO     one frame: a wedge fires from the wand (ECHO_ARC wide, ECHO_RANGE long, walls and
##            closed doors block it). Everyone it catches is **imaged** and deafened. The meter
##            empties and the neck snaps back down.
##   RUSH     a fast awkward lope to where the noise was, or to where it imaged the nearest
##            player, at 5.2 m/s
##   WAIL     it is on someone: it clubs and claws, with listening pauses between bursts. It
##            follows them by sound, so sprinting keeps it there. It stops when they are downed,
##            when it loses them (LOSE_QUIET s without hearing them, past LOSE_DIST) or when
##            somebody shoves it.
##   SEARCH   picks at a spot for a few seconds, twitching, then gives up
##   STUNNED  shoved: 2 s of staggering; struck by the saw: a short stagger, then it rushes the
##            spot the blow came from (stun(dir, seconds, push, then_hunt)); woken from sedation:
##            1.2 s getting up, then it rushes the nearest player (woke(pos))
##   SEDATED  (Monster.sedate) lies still; this brain does not run at all
##   RETREAT  after landing a hit on somebody it has already downed it backs off and stays calm
##
## Hearing: a noise of loudness L is heard within L * HEAR_PER_LOUDNESS metres, halved
## when a wall is between the noise and its head. Flashlights mean nothing to it.

const M := preload("res://scripts/monsters/modes.gd")

const HEAR_PER_LOUDNESS := 22.0
const OCCLUDED_FACTOR := 0.5
const SPEED_WANDER := 1.4
const SPEED_RUSH := 5.2
const SPEED_SEARCH := 1.1
const SPEED_RETREAT := 2.6
const LISTEN_MIN := 0.8
const LISTEN_MAX := 1.2
const SEARCH_MIN := 3.0
const SEARCH_MAX := 5.0
const RUSH_GIVE_UP := 12.0
const SHOVE_STUN := 2.0
const RETREAT_TIME := 1.3
const CALM_AFTER_HIT := 5.0
const LUNGE_RANGE := 1.35

## Suspicion: quiet noises fill it, it drains slowly, and a full meter fires an echo. **The neck is
## the meter** (Monster._sono_visual feeds it to the model), so there is no HUD for it.
## A noise adds `loudness * (SUSP_NEAR_FLOOR + (1 - floor) * closeness) * SUSP_GAIN`.
const SUSP_GAIN := 1.6
const SUSP_NEAR_FLOOR := 0.35
const SUSP_DRAIN := 0.06
## At or above this a noise is loud enough to be certain: it skips the echo and goes straight there.
const LOUD := 0.8

## The charge, and the wedge the echo fires.
const CHARGE_TIME := 1.2
const ECHO_ARC := deg_to_rad(60.0)        ## the whole fan, not the half-angle
const ECHO_RANGE := 14.0
## Later shifts and deeper wings sweep the wand through an arc while it pings, so the fan covers a
## whole room. `sweep` 0..1 widens the fan by up to this much.
const SWEEP_EXTRA := deg_to_rad(110.0)
## How far off the horizontal the fan still catches you (it is a fan, not a ball).
const ECHO_PITCH := deg_to_rad(28.0)
## How long the mode stays ECHO, so every machine sees the burst and the fan.
const ECHO_SHOW := 0.35
## How long an imaged position is worth rushing to.
const IMAGE_KEEP := 12.0

## The wail: bursts of blows with a listening pause between them (the way out).
const WAIL_BURST := 1.1
const WAIL_PAUSE := 0.85
const WAIL_HIT_EVERY := 0.85
## It loses you after this long without hearing you, once you are further than LOSE_DIST.
const LOSE_QUIET := 3.0
const LOSE_DIST := 7.0
## While it is on someone it keeps up with them: it steps toward them at this speed.
const SPEED_WAIL := 3.4

var m: CharacterBody3D
var rng := RandomNumberGenerator.new()

var target := Vector3.ZERO     ## where the last noise it chased was
var timer := 0.0
var wander_goal = null
var heard_time := -1e9         ## newest noise time already considered
var retreat_from := Vector3.ZERO
var _stuck_check := 0.0
var _stuck_from := Vector3.ZERO
var _after_stun = null         ## Vector3: where to rush when the stun ends
## Last noise it reacted to, for tests and debugging.
var last_heard: Dictionary = {}

## 0..1, the meter the neck shows. Monster copies it into `sono_susp` for the wire.
var suspicion := 0.0
## 0..1 while it charges.
var charge := 0.0
## 0..1: how much the wand sweeps while it pings (later shifts, deeper wings). Set once at spawn.
var sweep := 0.0
## peer id -> {"pos": Vector3, "t": float}: where the last echo saw each player.
var imaged: Dictionary = {}
## The player it is wailing on, the last time it heard them, and where that was. It follows the
## **sound**, not the player, so going quiet is what shakes it off.
var quarry: Node = null
var _quarry_heard := 0.0
var _quarry_at := Vector3.ZERO
var _wail_phase := 0.0         ## counts up: < WAIL_BURST clubbing, then the listening pause
var _wail_hit := 0.0
## Echoes fired, for the tests.
var echoes := 0
var last_echo: Dictionary = {}
## A loud noise is certain: after the listen it goes straight there, spending no echo.
var _certain := false
## The meter reached the top. It stays latched while it listens (the meter drains all the time, so
## without this a meter that filled a moment ago would not count as full when the listen ends).
var _full := false
var _sweep_set := false


func _init(monster: CharacterBody3D) -> void:
	m = monster
	rng.seed = hash("sonographer%d" % monster.monster_id)
	m.mode = M.Mode.WANDER


## How far the wand sweeps here: nothing on the first shift in the shallow wings, the whole arc
## deep in a late one. Worked out once, when the monster first thinks.
func _set_sweep(g: Node) -> void:
	var shift := int(g.get("shift")) if g != null and "shift" in g else 1
	var s := clampf((float(shift) - 1.0) / 3.0, 0.0, 1.0)
	var info: Dictionary = g.get("level_info") if g != null and "level_info" in g else {}
	if info.has("entrance_rect"):
		var r: Rect2 = info.entrance_rect
		var p := Vector2(m.global_position.x, m.global_position.z)
		var dx := maxf(maxf(r.position.x - p.x, 0.0), p.x - r.end.x)
		var dy := maxf(maxf(r.position.y - p.y, 0.0), p.y - r.end.y)
		s += clampf((Vector2(dx, dy).length() - 20.0) / 40.0, 0.0, 0.5)
	sweep = clampf(s, 0.0, 1.0)


func think(delta: float) -> void:
	var g: Node = m.game
	if not _sweep_set:
		_sweep_set = true
		_set_sweep(g)
	m.calm = maxf(0.0, m.calm - delta)
	timer -= delta
	suspicion = clampf(suspicion - SUSP_DRAIN * delta, 0.0, 1.0)

	# Hearing runs first so a noise can interrupt anything but a stun, a retreat or the echo itself.
	var noise := _hear(g)
	if not noise.is_empty():
		_react(noise)

	match m.mode:
		M.Mode.STUNNED:
			m.state = M.State.STUNNED
			charge = 0.0
			m.stop()
			if timer <= 0.0:
				if _after_stun is Vector3:
					target = _after_stun
					_after_stun = null
					m.mode = M.Mode.RUSH
					m.state = M.State.CHASE
					timer = RUSH_GIVE_UP
					m._repath = 0.0
				else:
					_start_wander()
			return
		M.Mode.RETREAT:
			m.state = M.State.STUNNED
			var away := m.global_position - retreat_from
			away.y = 0.0
			away = away.normalized() if away.length() > 0.05 else -m.global_transform.basis.z
			m.step_toward(m.global_position + away, SPEED_RETREAT, delta)
			if timer <= 0.0:
				_start_wander()
			return
		M.Mode.LISTEN:
			m.state = M.State.CHASE
			m.stop()
			m.listen_yaw = clampf(m.yaw_to(target), -1.2, 1.2)
			# It turns its body slowly toward the sound while it listens.
			m.face_dir(target - m.global_position, delta, 1.2)
			if timer <= 0.0:
				if _certain:
					# Loud and certain: straight there, no echo spent on it.
					_certain = false
					m.mode = M.Mode.RUSH
					m.state = M.State.CHASE
					timer = RUSH_GIVE_UP
					m._repath = 0.0
				elif _full:
					_start_charge()
				else:
					# Not sure enough to spend an echo: it creeps toward the spot instead.
					_start_search()
		M.Mode.CHARGE:
			m.state = M.State.CHASE
			m.stop()
			m.listen_yaw = clampf(m.yaw_to(target), -1.2, 1.2)
			m.face_dir(target - m.global_position, delta, 3.0)
			suspicion = 1.0
			charge = clampf(1.0 - timer / CHARGE_TIME, 0.0, 1.0)
			if timer <= 0.0:
				_fire_echo(g)
		M.Mode.ECHO:
			m.state = M.State.CHASE
			m.stop()
			if timer <= 0.0:
				_after_echo()
		M.Mode.WAIL:
			_wail(g, delta)
			return
		M.Mode.RUSH:
			m.state = M.State.CHASE
			var left: float = m.nav_move(target, SPEED_RUSH, delta)
			if left < 0.9 or timer <= 0.0 or _stuck(delta, 2.5):
				_start_search()
		M.Mode.SEARCH:
			m.state = M.State.CHASE
			if wander_goal == null or m.global_position.distance_to(wander_goal) < 0.5:
				wander_goal = target + Vector3(rng.randf_range(-2.0, 2.0), 0.0, rng.randf_range(-2.0, 2.0))
			m.nav_move(wander_goal, SPEED_SEARCH, delta)
			if timer <= 0.0:
				_start_wander()
		M.Mode.IDLE:
			m.state = M.State.WANDER
			m.stop()
			if timer <= 0.0:
				_start_wander()
		_:
			m.state = M.State.WANDER
			if wander_goal == null:
				wander_goal = m.random_nav_point(m.global_position, 6.0, 22.0)
			var left2: float = m.nav_move(wander_goal, SPEED_WANDER, delta)
			if left2 < 0.8 or _stuck(delta, 3.0):
				wander_goal = null
				m.mode = M.Mode.IDLE
				timer = rng.randf_range(0.8, 2.5)

	if m.mode != M.Mode.CHARGE and m.mode != M.Mode.ECHO:
		charge = move_toward(charge, 0.0, delta * 3.0)
	if m.calm <= 0.0 and m.mode != M.Mode.CHARGE and m.mode != M.Mode.ECHO:
		m.try_contact(LUNGE_RANGE)


## The loudest new noise it can hear, or {}. Every heard noise also feeds the suspicion meter.
func _hear(g: Node) -> Dictionary:
	if not g.has_method("recent_noises"):
		return {}
	var noises: Array = g.recent_noises(1.5)
	var newest := heard_time
	var best := {}
	var best_margin := 0.0
	var deaf: bool = m.calm > 0.0 or m.mode == M.Mode.STUNNED or m.mode == M.Mode.RETREAT
	var ear: Vector3 = m.global_position + Vector3.UP * 1.55
	# POCKETS 2 phase 1: a pocket space may declare an ambient_noise_level — running machines, a
	# tiled echo. Standing in it, the floor is subtracted from every noise's loudness before the
	# existing reach maths, so quiet things (a walking footstep is 0.25) are masked outright and
	# loud ones simply do not carry as far. A space with no floor, which is every space today,
	# gives 0.0 here and the arithmetic below is untouched.
	var floor_level := 0.0
	if g.get("pockets") != null:
		floor_level = g.pockets.ambient_noise_at(m.global_position)
	for n in noises:
		var t := float(n.time)
		if t <= heard_time:
			continue
		newest = maxf(newest, t)
		if deaf:
			continue
		var pos: Vector3 = n.pos
		# `loudness` is the raw value when there is no floor, so nothing below changes at 0.
		var loudness := maxf(float(n.loudness) - floor_level, 0.0)
		var reach := loudness * HEAR_PER_LOUDNESS
		# DOORS HOOK: closed doors between the noise and its head muffle it.
		var doors = g.get("doors")
		if doors != null:
			reach *= doors.sound_factor(pos, ear)
		var d := ear.distance_to(pos + Vector3.UP * 0.5)
		if d > reach:
			continue
		if d > reach * OCCLUDED_FACTOR and not m.clear_line(ear, pos + Vector3.UP * 0.5):
			continue
		var margin := reach - d
		# Quiet noises fill the meter, scaled by loudness and how near they were; a loud one
		# needs no echo at all, so it fills nothing and makes it certain instead.
		if loudness < LOUD:
			var near := 1.0 - clampf(d / maxf(reach, 0.001), 0.0, 1.0)
			suspicion = clampf(suspicion + loudness * (SUSP_NEAR_FLOOR + (1.0 - SUSP_NEAR_FLOOR) * near) * SUSP_GAIN, 0.0, 1.0)
			if suspicion >= 1.0:
				_full = true
		_note_quarry_noise(n)
		if margin > best_margin:
			best_margin = margin
			# Under a floor the noise it reacts to is the masked one, so _react's LOUD test sees
			# what it actually heard. With no floor this is the very same dictionary as before.
			best = n if floor_level <= 0.0 else n.duplicate()
			if floor_level > 0.0:
				best["loudness"] = loudness
	heard_time = newest
	return best


## While it is on someone, hearing them is what keeps it there.
func _note_quarry_noise(n: Dictionary) -> void:
	if quarry == null or not is_instance_valid(quarry) or m.game == null:
		return
	if (n.pos as Vector3).distance_to(quarry.global_position) < 2.5:
		_quarry_heard = float(m.game.world_time)
		_quarry_at = n.pos


func _react(noise: Dictionary) -> void:
	last_heard = noise
	if m.mode == M.Mode.CHARGE or m.mode == M.Mode.ECHO or m.mode == M.Mode.WAIL:
		return   # committed: the noise still filled the meter, but it does not change course
	target = noise.pos
	var loud: bool = float(noise.loudness) >= LOUD
	match m.mode:
		M.Mode.WANDER, M.Mode.IDLE, M.Mode.SEARCH:
			m.mode = M.Mode.LISTEN
			m.stop()
			timer = rng.randf_range(LISTEN_MIN, LISTEN_MAX)
			wander_goal = null
		M.Mode.LISTEN:
			pass   # already listening: just re-aim
		M.Mode.RUSH:
			timer = RUSH_GIVE_UP
			m._repath = 0.0
	if loud:
		_certain = true


func _start_charge() -> void:
	m.mode = M.Mode.CHARGE
	m.state = M.State.CHASE
	timer = CHARGE_TIME
	charge = 0.0
	wander_goal = null
	m.stop()


# =========================================================================
# the echo
# =========================================================================

## Where the fan comes from and which way it points: the wand's tip, aimed at what it heard.
func echo_beam() -> Array:
	var origin: Vector3 = m.global_position + Vector3.UP * 1.15
	if m.model != null and m.model.has_method("echo_origin"):
		var xf: Transform3D = m.model.echo_origin()
		if xf.origin != Vector3.ZERO:
			origin = xf.origin
	var dir := target - origin
	dir.y = 0.0
	if dir.length() < 0.05:
		dir = -m.global_transform.basis.z
		dir.y = 0.0
	return [origin, dir.normalized()]


func half_arc() -> float:
	return (ECHO_ARC + SWEEP_EXTRA * sweep) * 0.5


## Is `point` inside the fan, with nothing solid in the way?
func in_echo(origin: Vector3, dir: Vector3, point: Vector3) -> bool:
	var to := point - origin
	if to.length() > ECHO_RANGE:
		return false
	var flat := Vector3(to.x, 0.0, to.z)
	if flat.length() < 0.05:
		return true
	if absf(atan2(to.y, flat.length())) > ECHO_PITCH:
		return false
	if flat.normalized().angle_to(dir) > half_arc():
		return false
	# Walls and closed doors block it (a closed door is on C.L_WORLD, an open one is not).
	return m.clear_line(origin, point)


## Fire the wedge: everyone it catches is imaged and deafened, and it rushes the nearest of them.
func _fire_echo(g: Node) -> void:
	var beam := echo_beam()
	var origin: Vector3 = beam[0]
	var dir: Vector3 = beam[1]
	var caught: Array = []
	if g != null and g.has_method("alive_players"):
		for p in g.alive_players():
			if p == null or not is_instance_valid(p):
				continue
			if in_echo(origin, dir, p.global_position + Vector3.UP * 1.1):
				caught.append(p)
				imaged[int(p.peer_id)] = {"pos": p.global_position, "t": float(g.world_time)}
	echoes += 1
	last_echo = {
		"origin": origin, "dir": dir, "half": half_arc(), "range": ECHO_RANGE,
		"sweep": sweep, "peers": caught.map(func(p): return int(p.peer_id)),
	}
	suspicion = 0.0
	_full = false
	charge = 1.0
	m.mode = M.Mode.ECHO
	m.state = M.State.CHASE
	timer = ECHO_SHOW
	# Everyone's machine draws the fan, and everyone it caught is imaged and deafened
	# (scripts/monsters/sono_echo.gd).
	var fx = g.get("sono_echo") if g != null else null
	if fx != null and fx.has_method("fire"):
		fx.fire({
			"id": int(m.monster_id), "o": origin.snappedf(0.01), "d": dir.snappedf(1.0 / 256.0),
			"h": snappedf(half_arc(), 1.0 / 256.0), "r": ECHO_RANGE,
			"pk": last_echo.peers,
		})


## The echo is over: it goes for the nearest player it imaged, or searches where it was listening.
func _after_echo() -> void:
	charge = 0.0
	var best_peer := -1
	var best_d := 1e9
	var now: float = float(m.game.world_time) if m.game != null else 0.0
	for peer in imaged.keys():
		var rec: Dictionary = imaged[peer]
		if now - float(rec.t) > IMAGE_KEEP:
			continue
		var d: float = m.global_position.distance_to(rec.pos)
		if d < best_d:
			best_d = d
			best_peer = int(peer)
	if best_peer >= 0:
		target = imaged[best_peer].pos
		m.mode = M.Mode.RUSH
		m.state = M.State.CHASE
		timer = RUSH_GIVE_UP
		m._repath = 0.0
	else:
		_start_search()


# =========================================================================
# the wail
# =========================================================================

## It has someone: bursts of clubbing with a listening pause between them. It stops at downed,
## when it loses them, or when it is shoved (stun() clears the quarry).
func _wail(g: Node, delta: float) -> void:
	m.state = M.State.CHASE
	if quarry == null or not is_instance_valid(quarry) or not quarry.alive or quarry.downed:
		_drop_quarry(true)
		return
	var now: float = float(g.world_time) if g != null else 0.0
	var d: float = m.global_position.distance_to(quarry.global_position)
	if d < LUNGE_RANGE + 1.0:
		# Right on top of them: it hears them breathe, however still they are.
		_quarry_heard = now
		_quarry_at = quarry.global_position
	if now - _quarry_heard > LOSE_QUIET:
		# They broke away during a pause, got distance and went quiet.
		_drop_quarry(false)
		return
	_wail_phase += delta
	if _wail_phase > WAIL_BURST + WAIL_PAUSE:
		_wail_phase = 0.0
	var pausing := _wail_phase > WAIL_BURST
	m.listen_yaw = clampf(m.yaw_to(quarry.global_position), -1.2, 1.2)
	if pausing:
		# The listening pause: it stands, head cocked. This is the way out.
		m.stop()
		m.lunge_t = 0.0
	else:
		if d > LUNGE_RANGE * 0.8:
			# It goes where it last HEARD them, not where they are: that is the gap you run through.
			m.nav_move(_quarry_at, SPEED_WAIL, delta)
		else:
			m.stop()
			m.face_dir(quarry.global_position - m.global_position, delta, 6.0)
		_wail_hit -= delta
		if _wail_hit <= 0.0 and d < LUNGE_RANGE + C.PLAYER_RADIUS:
			_wail_hit = WAIL_HIT_EVERY
			m.lunge_t = 0.5
			if g != null and g.has_method("monster_hit_player"):
				g.monster_hit_player(m, quarry)


func _drop_quarry(downed: bool) -> void:
	quarry = null
	m.lunge_t = 0.0
	if downed:
		# It does not finish them off: it goes back to hunting.
		suspicion = maxf(suspicion, 0.4)
		_start_search()
	else:
		target = m.global_position
		_start_search()


## Host: contact. The Sonographer does not back off after a blow -- it gets on them and wails.
func start_wail(p: Node) -> void:
	if p == null or not is_instance_valid(p) or p.downed:
		return
	if quarry == p and m.mode == M.Mode.WAIL:
		return   # already on them: a blow must not restart the burst, or the pause never comes
	quarry = p
	_quarry_heard = float(m.game.world_time) if m.game != null else 0.0
	_quarry_at = p.global_position
	_wail_phase = 0.0
	_wail_hit = WAIL_HIT_EVERY
	m.mode = M.Mode.WAIL
	m.state = M.State.CHASE
	suspicion = maxf(suspicion, 0.25)


func _start_search() -> void:
	m.mode = M.Mode.SEARCH
	m.state = M.State.CHASE
	timer = rng.randf_range(SEARCH_MIN, SEARCH_MAX)
	wander_goal = null
	_certain = false
	_full = false


func _start_wander() -> void:
	m.mode = M.Mode.WANDER
	m.state = M.State.WANDER
	m.listen_yaw = 0.0
	wander_goal = null
	_certain = false
	_full = false


func _stuck(delta: float, window: float) -> bool:
	_stuck_check += delta
	if _stuck_check < window:
		return false
	var moved: float = m.global_position.distance_to(_stuck_from)
	_stuck_check = 0.0
	_stuck_from = m.global_position
	return moved < 0.4


## Something very loud and certain (the game may still call this): treat it as a noise.
func alert_to(pos: Vector3) -> void:
	if m.calm > 0.0 or m.mode == M.Mode.STUNNED or m.mode == M.Mode.RETREAT:
		return
	_react({"pos": pos, "loudness": 1.0, "kind": "alert", "time": 0.0})


func shoved(dir: Vector3) -> void:
	stun(dir, SHOVE_STUN, 1.1)


## Knocked off balance for `seconds`, pushed `push` metres along dir. `then_hunt` (Vector3):
## when it recovers it rushes straight there (it knows where the blow came from).
func stun(dir: Vector3, seconds: float, push := 0.6, then_hunt = null) -> void:
	dir.y = 0.0
	if dir.length() > 0.01 and push > 0.0:
		m.move_and_collide(dir.normalized() * push)
	var was_stunned: bool = m.mode == M.Mode.STUNNED
	quarry = null          # a shove is what gets it off someone
	charge = 0.0
	_full = false
	m.mode = M.Mode.STUNNED
	m.state = M.State.STUNNED
	m.lunge_t = 0.0
	timer = maxf(timer, seconds) if was_stunned else seconds
	if then_hunt is Vector3:
		_after_stun = then_hunt


func sedated() -> void:
	wander_goal = null
	_after_stun = null
	quarry = null
	suspicion = 0.0
	_full = false
	charge = 0.0
	m.listen_yaw = 0.0


func woke(hunt_pos) -> void:
	stun(Vector3.ZERO, 1.2, 0.0, hunt_pos)


## It landed a blow. On someone still standing it stays on them and wails; once they are down it
## backs off and goes quiet for a while, as it always did.
func recoil_after_hit() -> void:
	var p: Node = m.nearest_player(LUNGE_RANGE + 1.2)
	if p != null and is_instance_valid(p) and p.alive and not p.downed:
		start_wail(p)
		return
	retreat_from = p.global_position if p != null else m.global_position - m.global_transform.basis.z
	quarry = null
	m.mode = M.Mode.RETREAT
	m.state = M.State.STUNNED
	m.calm = CALM_AFTER_HIT
	timer = RETREAT_TIME
