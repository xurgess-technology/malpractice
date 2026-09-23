extends RefCounted
## The Onlooker, host side (docs/POCKET_SPACES_2.md phase 6). The fourth sense rule: the Hive has
## eyes, the Sonographer has ears, the Night Nurse has being watched, and this one has ATTENTION.
## It feeds on being seen and ignored, which makes it the **inverse of the Night Nurse**: you get
## rid of her by looking at her, and you get rid of this by walking at it.
##
##   it pops in far away, already inside somebody's view, and stares
##   it never takes a step -- it HOPS, vanishing and reappearing at another far point in that same
##   player's view, so turning round does not lose it: it relocates into wherever you now look
##   stared at and ignored past GRACE seconds it starts eating hearts, faster the longer it goes
##   run AT it and inside BANISH_RANGE it is gone for VANISH_COOLDOWN
##   the saw, the needle and a shove do nothing at all
##   leave the pocket through a seam and the encounter is over
##
## It is **silent**. There is not one Audio.play in this file or in monster.gd's sound pass for this
## kind, and that is the mechanic rather than an omission: the tell is purely visual, so the fear is
## having to check your own sightlines.
##
## ## Whose view it places into, which is the hard part in a co-op game
##
## It **marks one player** and keeps them for the whole encounter. Everything about placement --
## where it pops in, where it hops to, whether the stare counts, whose hearts it eats -- is that one
## player's view and nobody else's. Two surgeons in the Natatorium looking opposite ways is not an
## unsolvable placement problem, because only one of them is being looked at.
##
## The mark is the player inside the pocket with the **most room in front of them** (the longest
## clear ray out of their own eyes, `_sightline`), because that is the player it can actually stand
## far away from and be seen by; ties break on peer id so every machine would agree, though only the
## host ever decides. It re-marks after every banish, so in a pair it does not fix on one of you.
##
## What the *other* players get is the co-op half, and it is deliberate both ways:
##   - they SEE it. It is an ordinary replicated monster, so your teammate watching you from the
##     bleachers sees the thing standing behind you, and can say so.
##   - they can BANISH it. Anyone closing to BANISH_RANGE sends it away, not just the mark. Running
##     at the thing staring at your teammate is the co-op play the aggression counter is for.
##   - they cannot be hurt by it. The heart tick only ever lands on the mark.
##
## ## Why the wander fence does not apply to it
## `game.monster_may_wander_to` (phase 1) fences idle *wander goals* to the monster's own space. This
## brain never wanders: it calls neither `nav_move` nor `random_nav_point`, so it never reaches that
## predicate. It is not exempt by accident -- placement runs the same test the fence runs
## (`pockets.space_of(point)` must be this pocket, and `phantom_at` must be empty), so a hop can no
## more leave the space than a wander could.

const M := preload("res://scripts/monsters/modes.gd")
const Percept := preload("res://scripts/perception.gd")

# =========================================================================
# the tuning knobs (docs/POCKET_SPACES_2.md phase 6 lists these by name)
# =========================================================================

## Seconds of being stared at, ignored, before the first heart goes. Long enough to notice it,
## cross a room and decide, which in the Chapel's 33 m nave is about a sprint and a half.
const GRACE := 9.0
## Seconds between hearts once it starts, and the ramp: each tick waits RAMP times as long as the
## last, floored at TICK_MIN. 7.0 -> 4.9 -> 3.4 -> 2.4 -> 2.0 -> 2.0...
const TICK_FIRST := 7.0
const TICK_RAMP := 0.7
const TICK_MIN := 2.0
## Walk inside this many metres of it and it is gone. Generous on purpose: the counter is meant to
## be a decision ("go at it") rather than an execution ("touch it").
const BANISH_RANGE := 6.0
## Seconds it stays away after a banish, and after it fails to find anywhere to stand.
const VANISH_COOLDOWN := 75.0
const RETRY_SECONDS := 1.5
## Seconds the space has to stay empty of living surgeons before the encounter is called over.
## Not zero, and the reason is the seam rather than politeness: a player crossing one spends frames
## in a stub copy that `space_of` does not call this space, and standing in an entrance's mouth can
## read as outside too. Two seconds swallows all of that and is invisible to somebody who really
## did walk out.
const LEAVE_GRACE := 2.0
## Seconds between hops, randomised by HOP_JITTER either way.
const HOP_INTERVAL := 9.0
const HOP_JITTER := 2.0
## How far away "far away" is. It will not place closer than MIN_DIST, it prefers the farthest
## candidate it found, and it stops looking for better once something is past PREFER_DIST.
const MIN_DIST := 14.0
const PREFER_DIST := 26.0
## Candidate points sampled per placement attempt.
const TRIES := 40
## The stare only counts while the mark can see it; looking away bleeds the meter back down at this
## share of the rate it built up. Looking away is worth something, but only until the next hop.
const LOOK_AWAY_DECAY := 0.5
## Seconds the pop in and the pop out take.
const FADE_IN := 0.45
const FADE_OUT := 0.2

## The spawn chance is rolled once per pocket by the watcher that owns this monster's existence,
## not here: scripts/monsters/onlooker_watch.gd SPAWN_CHANCE.

var m: CharacterBody3D
var rng := RandomNumberGenerator.new()

## The peer id of the player it is staring at, 0 when it is away and has not chosen one.
var mark_peer: int = 0
## Seconds of accumulated, ignored stare. Past GRACE it starts eating.
var stare := 0.0
## Seconds until the next heart, once stare has passed GRACE, and how many have gone.
var tick_left := 0.0
var ticks := 0
## Seconds until the next hop while it is standing, or until it may come back while it is away.
var hop_left := 0.0
var away_left := 0.0
## The space this encounter belongs to. Leaving it ends the encounter.
var space := ""
## Has it ever actually appeared? Before it has, an empty space is just a pocket nobody has walked
## into yet and it waits; after, an empty space means everyone left and the encounter is over.
var started := false
## Seconds the space has been empty of living surgeons.
var empty_for := 0.0
## Host-side lifetime flag: the watcher frees the monster once this is true.
var finished := false

## Counters the lab reads.
var hops := 0
var banished := 0
var hearts := 0
var placements_failed := 0


func _init(monster: CharacterBody3D) -> void:
	m = monster
	rng.seed = hash("onlooker%d" % monster.monster_id)
	m.mode = M.Mode.IDLE
	m.state = M.State.WANDER
	m.present = false
	m.presence = 0.0


func think(delta: float) -> void:
	var g: Node = m.game
	m.stop()
	m.mode = M.Mode.STALK if m.present else M.Mode.IDLE
	m.state = M.State.WANDER

	var pk = g.get("pockets") if g != null else null
	if pk == null or not pk.active():
		_end()           # the pocket went (a new shift, a teardown): so did the encounter
		return
	if space == "":
		space = String(pk.pocket.get("kind", ""))

	# **Escaping through a seam ends the encounter**, and this is the one place that decides it,
	# above the standing/away split on purpose. Deciding it inside `_standing` was wrong and the lab
	# caught it: banish the thing, walk out during its seventy-five second cooldown, and nothing was
	# running to notice you had gone -- it sat in the pocket for the rest of the shift waiting to
	# come back for somebody who had left. It is the *space* emptying that ends it, not the monster
	# happening to be looking when it does.
	empty_for = 0.0 if _anyone_here(g, pk) else empty_for + delta
	if started and empty_for >= LEAVE_GRACE:
		_end()
		return

	if m.present:
		_standing(g, pk, delta)
	else:
		away_left -= delta
		m.presence = maxf(0.0, m.presence - delta / FADE_OUT)
		if away_left <= 0.0:
			_try_appear(g, pk)


# =========================================================================
# standing there
# =========================================================================

func _standing(g: Node, pk, delta: float) -> void:
	var mark: Node = _mark(g)
	if mark == null:
		_vanish(RETRY_SECONDS)
		return
	# The mark went out through a seam. That ends it *for them*, not necessarily at all: there is
	# one Onlooker per pocket, so if a teammate is still in there it drops the mark, waits a beat
	# and turns to whoever is left. With nobody left, the empty-space rule in `think` ends it.
	if String(pk.space_of(mark.global_position)) != space:
		_vanish(RETRY_SECONDS)
		return

	m.presence = minf(1.0, m.presence + delta / FADE_IN)
	m.face_dir(mark.global_position - m.global_position, delta, 2.5)

	# The counter: ANY living player inside the banish range, not only the mark. Running at the
	# thing that is staring at your teammate is the co-op play.
	for p in g.alive_players():
		if p.global_position.distance_to(m.global_position) <= BANISH_RANGE:
			banished += 1
			_vanish(VANISH_COOLDOWN)
			return

	var seen := _sees_me(mark)
	m.observed = seen   # replicated as `ob`; for the lab and for anything that wants to know
	if seen:
		stare += delta
	else:
		stare = maxf(0.0, stare - delta * LOOK_AWAY_DECAY)

	# Eating. It only ever lands on the mark, and only while the stare is actually running.
	if stare >= GRACE and seen:
		tick_left -= delta
		if tick_left <= 0.0:
			_eat(g, mark)
	elif stare < GRACE:
		# Below the line the clock is not just paused, it is at zero: the FIRST heart lands the
		# moment the stare passes GRACE, and the ramp is the gap to the second one. "Grace, then a
		# tick" reads as one number to a player; "grace, then a further seven seconds" reads as
		# nothing happening.
		tick_left = 0.0
		ticks = 0

	# The hop. It goes whether or not you are looking: that is what makes turning round useless.
	hop_left -= delta
	if hop_left <= 0.0:
		_hop(g, pk, mark)


## One heart off the mark, then the next tick, shorter than the last.
func _eat(g: Node, mark: Node) -> void:
	# The gap to the NEXT one, measured from how many have already gone: 7.0, 4.9, 3.4, 2.4, then
	# the TICK_MIN floor. The first heart itself is free, at the grace line (see `_standing`).
	tick_left = maxf(TICK_MIN, TICK_FIRST * pow(TICK_RAMP, float(ticks)))
	ticks += 1
	hearts += 1
	if g.has_method("damage_player"):
		g.damage_player(mark, 1, "monster:onlooker")
	elif g.has_method("monster_hit_player"):
		g.monster_hit_player(m, mark)


func _hop(g: Node, pk, mark: Node) -> void:
	hop_left = HOP_INTERVAL + rng.randf_range(-HOP_JITTER, HOP_JITTER)
	var spot := _place(g, pk, mark)
	if spot == Vector3.INF:
		placements_failed += 1
		return   # nowhere to go that is still in their view: stay where it is and try again later
	hops += 1
	m.global_position = spot
	m.velocity = Vector3.ZERO
	m.face_dir(mark.global_position - spot, 1.0, 1.0)


# =========================================================================
# coming and going
# =========================================================================

## Away: pick (or re-pick) a mark and a far point in their view. Silent failure is normal -- a
## player facing a wall has nowhere far in their view, and it simply waits.
func _try_appear(g: Node, pk) -> void:
	var mark: Node = _pick_mark(g, pk)
	if mark == null:
		away_left = RETRY_SECONDS
		return
	var spot := _place(g, pk, mark)
	if spot == Vector3.INF:
		placements_failed += 1
		away_left = RETRY_SECONDS
		return
	started = true
	mark_peer = int(mark.peer_id)
	m.global_position = spot
	m.velocity = Vector3.ZERO
	m.face_dir(mark.global_position - spot, 1.0, 1.0)
	m.present = true
	m.presence = 0.0
	m.observed = false
	stare = 0.0
	ticks = 0
	tick_left = TICK_FIRST
	hop_left = HOP_INTERVAL + rng.randf_range(-HOP_JITTER, HOP_JITTER)


## Gone for `seconds`. It keeps its position (nothing can see it) so nothing has to be moved.
func _vanish(seconds: float) -> void:
	m.present = false
	m.observed = false
	mark_peer = 0
	stare = 0.0
	ticks = 0
	away_left = seconds
	m.mode = M.Mode.IDLE


## The encounter is over: out through a seam, or the pocket is gone. The watcher frees it.
func _end() -> void:
	m.present = false
	m.observed = false
	finished = true


# =========================================================================
# who, and where
# =========================================================================

## The marked player, or null if they are gone, downed or out of the pocket.
func _mark(g: Node) -> Node:
	if mark_peer == 0:
		return null
	var p = (g.players as Dictionary).get(mark_peer)
	if p == null or not is_instance_valid(p) or not p.alive or bool(p.get("downed")):
		return null
	return p


## Is there any living surgeon left in this space at all?
func _anyone_here(g: Node, pk) -> bool:
	for p in g.alive_players():
		if not bool(p.get("downed")) and String(pk.space_of(p.global_position)) == space:
			return true
	return false


## The player in the pocket with the most room in front of them. That is the one it can stand far
## away from and still be seen by, which is the only thing placement actually needs.
func _pick_mark(g: Node, pk) -> Node:
	var best: Node = null
	var best_score := -1.0
	for p in g.alive_players():
		if bool(p.get("downed")) or String(pk.space_of(p.global_position)) != space:
			continue
		var score := _sightline(p)
		# Peer id breaks a tie, so the choice does not depend on dictionary order.
		if score > best_score + 0.001 or (absf(score - best_score) <= 0.001 and best != null and int(p.peer_id) < int(best.peer_id)):
			best_score = score
			best = p
	return best


## Metres of clear air straight out of this player's eyes, capped at PREFER_DIST.
func _sightline(p: Node) -> float:
	var cam: Camera3D = p.get("camera")
	if cam == null or not cam.is_inside_tree():
		return 0.0
	var from: Vector3 = cam.global_position
	var to: Vector3 = from - cam.global_transform.basis.z * PREFER_DIST
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.collision_mask = C.L_WORLD
	var hit := m.get_world_3d().direct_space_state.intersect_ray(q)
	return PREFER_DIST if hit.is_empty() else from.distance_to(hit.position)


## A far point on the pocket's floor, inside `mark`'s view, with a clear line to their eyes, at
## least MIN_DIST away, in this space and not in a stub's dead half. Vector3.INF when there is none.
##
## **Light is deliberately not part of this.** `Perception.observed_any` wants a point to be lit
## before it counts as seen, which is right for the Night Nurse and wrong here: the Onlooker's eyes
## are their own light, and a thing you can only see in a dark room is the point of it.
func _place(g: Node, pk, mark: Node) -> Vector3:
	var rect: Rect2 = pk.pocket.get("rect", Rect2())
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return Vector3.INF
	var map: RID = m.agent.get_navigation_map()
	var map_ready := NavigationServer3D.map_get_iteration_id(map) > 0
	var here: Vector3 = mark.global_position
	var best := Vector3.INF
	var best_d := MIN_DIST
	for _i in TRIES:
		var q := Vector3(rect.position.x + rng.randf() * rect.size.x, here.y,
			rect.position.y + rng.randf() * rect.size.y)
		if map_ready:
			q = NavigationServer3D.map_get_closest_point(map, q)
		var d := Vector2(q.x - here.x, q.z - here.z).length()
		if d < best_d or d < MIN_DIST:
			continue
		if String(pk.space_of(q)) != space or not pk.phantom_at(q).is_empty():
			continue
		if absf(q.y - here.y) > 3.0:
			continue   # another storey of the same rect (the Factory's gantries): not a place to stand
		if not _visible_from(mark, q):
			continue
		best = q
		best_d = d
		if d >= PREFER_DIST:
			break
	return best


## Is a body standing at `at` inside this player's view, with a clear line to their eyes? The same
## two tests Perception runs, minus the lighting one, over chest and head rather than the feet --
## feet in a doorway's shadow are not what you see of it.
func _visible_from(p: Node, at: Vector3) -> bool:
	var cam: Camera3D = p.get("camera")
	if cam == null or not cam.is_inside_tree():
		return false
	var space_state := m.get_world_3d().direct_space_state
	var eye: Vector3 = cam.global_position
	for h: float in [1.4, float(m.height) - 0.2]:
		var point: Vector3 = at + Vector3.UP * h
		if not Percept.in_view(p, point):
			continue
		var d: Vector3 = point - eye
		var l: float = d.length()
		if l < 0.01:
			return true
		var q := PhysicsRayQueryParameters3D.create(eye, eye + d * ((l - Percept.RAY_SLACK) / l))
		q.collision_mask = C.L_WORLD
		if space_state.intersect_ray(q).is_empty():
			return true
	return false


## Is the mark looking at it right now, where it actually stands?
func _sees_me(mark: Node) -> bool:
	return _visible_from(mark, m.global_position)


# =========================================================================
# things done to it, all of which are nothing
# =========================================================================

func shoved(_dir: Vector3) -> void:
	pass   # a shove does nothing. Standing next to it to shove it has already banished it.


func recoil_after_hit() -> void:
	pass


func stun(_dir: Vector3, _seconds: float, _push: float, _from = null) -> void:
	pass


func alert_to(_pos: Vector3) -> void:
	pass   # it does not hear, and nothing can call it
