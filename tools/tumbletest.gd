extends Node
## TUMBLE TUNING (2026-09-24): headless proof that a thrown item settles into its hover quickly --
## not the old "up to 3 s of tumbling" -- for a spread of items and throw angles, and that nothing
## jitters or ends up buried once it has.
##
##   godot --headless --fixed-fps 60 --path . tools/tumbletest.tscn [-- --seed=N]
##
## Exits 0 when every check passes.

const HARD_CAP := WorldItem.SETTLE_MAX + 0.05   # a little slack for the frame the check lands on
const WANT_UNDER := 1.0                          # "well under a second" once it has actually landed

var main: Node3D
var game: Game
var me: Player
var seed_value := 4242
var _failures: Array = []
var _checks := 0


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		if kv[0] == "seed" and kv.size() > 1:
			seed_value = int(kv[1])
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	game = main.game
	main.menu.hide_menu()
	Net.start_solo("Tester")
	game.start_session(seed_value)
	await _frames(10)
	me = game.local_player()
	me.bot_active = true
	me.teleport(game.spawn_points()[0])
	await _frames(2)
	await _run()
	_finish()


func _run() -> void:
	var here: Vector3 = me.global_position + Vector3(0.0, 0.0, -3.0)
	# A wall is wherever open_direction() would stop a ray; find one within a few metres so the
	# "thrown at a wall" case actually hits one, using the same ray the review setups use.
	var wall_dir := _nearest_wall(here, 6.0)
	var wall_at: Vector3 = here + wall_dir * 1.4

	# kind, from, velocity, label. A light stack, a heavy bulky one, loot, and a stack of pills, at a
	# spread of angles: flat and fast, a high lob, straight down, and thrown at a wall close by.
	var throws := [
		{"kind": "gauze", "count": 2, "from": here, "vel": Vector3(3.0, 0.7, 0.0), "label": "gauze, flat and fast"},
		{"kind": "bone_saw", "count": 1, "from": here, "vel": Vector3(1.5, 3.2, 0.0), "label": "bone saw, high lob"},
		{"kind": "gold_watch", "count": 1, "from": here + Vector3(0, 1.2, 0), "vel": Vector3(0.0, -0.2, 0.0), "label": "gold watch, dropped straight down"},
		{"kind": "placebo_pills", "count": 6, "from": here, "vel": Vector3(0.3, 1.0, 0.0), "label": "pill bottle, lobbed gently"},
		{"kind": "gauze", "count": 1, "from": wall_at - wall_dir * 1.0, "vel": wall_dir * 4.0 + Vector3.UP * 0.3, "label": "gauze thrown straight at a wall"},
	]
	var gaps: Array = []
	for t in throws:
		var gap := await _throw_and_measure(t.kind, int(t.count), t.from as Vector3, t.vel as Vector3, String(t.label))
		if gap >= 0.0:
			gaps.append(gap)
	if not gaps.is_empty():
		var total := 0.0
		var worst := 0.0
		for g in gaps:
			total += g
			worst = maxf(worst, g)
		_say("landed-to-hover gap: avg %.2f s, worst %.2f s, over %d throws" % [total / gaps.size(), worst, gaps.size()])


## Throw one stack and follow it: the moment its own velocity drops under the settle thresholds
## ("landed"), and the moment it starts hovering ("hover"). Checks the gap is short and hard-capped,
## that it never ends up below the floor or with a broken transform, and that once it is hovering it
## stays put (no jitter) for a few more frames.
func _throw_and_measure(kind: String, count: int, from: Vector3, vel: Vector3, label: String) -> float:
	var xf := Transform3D(Basis(), from)
	var it: WorldItem = game._spawn_item(kind, count, xf, WorldItem.State.LOOSE)
	it.toss(xf, vel)
	# Simulated time, in physics frames, not wall-clock: --fixed-fps 60 gives every physics tick
	# exactly 1/60 s of simulated time regardless of how long that tick actually took to compute
	# (a slow frame -- warmup running in the background, a loaded machine -- must not read as a
	# slow settle).
	var landed_i := -1
	var hover_i := -1
	var worst_y := 1000.0
	var frames := int((HARD_CAP + 1.5) * 60.0)   # the hard cap, the rise, and slack for a bounce or two
	for i in frames:
		if not is_instance_valid(it):
			break
		worst_y = minf(worst_y, it.global_position.y)
		if landed_i < 0 and not it.freeze and it.linear_velocity.length() < WorldItem.STILL_LINEAR \
				and it.angular_velocity.length() < WorldItem.STILL_ANGULAR:
			landed_i = i
		if it.hovering:
			hover_i = i
			break
		await get_tree().physics_frame
	_check(is_instance_valid(it), "%s: still in the world" % label)
	if not is_instance_valid(it):
		return -1.0
	_check(hover_i >= 0, "%s: reached its hover within %.1f s" % [label, HARD_CAP + 1.5])
	var total := float(hover_i) / 60.0 if hover_i >= 0 else -1.0
	_check(total < 0.0 or total <= HARD_CAP, "%s: throw to hover %.2f s, under the %.2f s hard cap" % [label, total, HARD_CAP])
	var gap := -1.0
	if landed_i >= 0 and hover_i >= 0:
		gap = float(hover_i - landed_i) / 60.0
		_check(gap <= WANT_UNDER, "%s: landed to hover %.2f s, well under a second" % [label, gap])
	_check(worst_y > -1.0, "%s: never fell through the floor (lowest y %.2f)" % [label, worst_y])
	# No jitter once it is hovering: watch it for a few more frames and it should only move the way
	# begin_hover()'s own rise (or hop) moves it -- settling to a fixed anchor, not still sliding.
	var settle_pos: Vector3 = it.global_position
	for i in 20:
		await get_tree().physics_frame
		if not is_instance_valid(it):
			break
	if is_instance_valid(it):
		var drift := it.global_position.distance_to(settle_pos)
		# The hop itself can carry it a couple of metres to a free spot; once it lands it must not
		# still be creeping (the hover bob is a cosmetic Y wobble on the *visual* child, not the body).
		_check(drift <= 0.05 or (it.hovering and drift <= 3.0), "%s: settled, not still creeping (%.3f m over 20 frames)" % [label, drift])
	if is_instance_valid(it):
		game.world_items.erase(it.item_id)
		it.queue_free()
	return gap


## A wall within `reach` of `from`, so the "thrown at a wall" case has one to hit -- the same ray
## scripts/review_setups.gd's open_direction() uses, just kept to the shortest side instead of the
## longest.
func _nearest_wall(from: Vector3, reach: float) -> Vector3:
	var space: PhysicsDirectSpaceState3D = game.get_world_3d().direct_space_state
	var best := Vector3.BACK
	var best_d := reach
	for d in [Vector3.BACK, Vector3.FORWARD, Vector3.LEFT, Vector3.RIGHT]:
		var q := PhysicsRayQueryParameters3D.create(from + Vector3.UP * 1.0, from + Vector3.UP * 1.0 + d * reach)
		q.collision_mask = C.L_WORLD
		var hit := space.intersect_ray(q)
		if not hit.is_empty():
			var dist: float = from.distance_to(hit.position)
			if dist < best_d:
				best_d = dist
				best = d
	return best


func _check(ok: bool, what: String) -> void:
	_checks += 1
	_say(("PASS  " if ok else "FAIL  ") + what)
	if not ok:
		_failures.append(what)


func _say(line: String) -> void:
	print("[tumbletest] ", line)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _finish() -> void:
	_say("------------------------------------------")
	_say("result=%s checks=%d failures=%d" % ["PASS" if _failures.is_empty() else "FAIL", _checks, _failures.size()])
	for f in _failures:
		_say("  failed: " + f)
	get_tree().quit(0 if _failures.is_empty() else 1)
