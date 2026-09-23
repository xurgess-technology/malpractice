extends Node
## POCKETS: headless check of pocket spaces in the real game, for both the Factory and the Restaurant.
##
##   godot --headless --fixed-fps 60 --path . tools/pockettest.tscn [-- --seed=N] [--only=factory]
##   godot --path . tools/pockettest.tscn --resolution 1280x720 -- --frames   # windowed rebuild frame times
##
## For each space (forced on the run's hospital):
##   - the pocket, its seams and links exist; entrances lead to at least two different wings; a
##     navigation path from the neutral area reaches the pocket through a seam link
##   - through every entrance, both directions, a bot walks the stub carrying a downed bot over its
##     shoulder while a second bot walks right behind it holding supplies: each crosses once, keeps its
##     offset from the seam, its speed and heading; the carried body stays on the shoulder; the
##     supplies stay in hand; everyone ends up on the far side
##   - a Night Nurse follows a player from the hospital into the pocket through a seam
##   - a Sonographer in the pocket hears a player on the hospital side of a seam and comes through
##   - a loose item dropped past a seam lands in the other copy
##   - noise near a seam is heard on the other side; nothing past a seam is reachable
##   - the next shift: whoever is in the pocket is walked out, what was left there is gone, the old
##     nodes are freed, clock-in waits, the pocket is built again under the new wings with its doors
##     and a crossing still works
##
## Exits 0 when every check passes.

const Plan := preload("res://scripts/level/pockets/pocket_plan.gd")
const Stub := preload("res://scripts/level/pockets/stub.gd")
const PocketSpaces := preload("res://scripts/level/pockets/pocket_spaces.gd")
const NatatoriumScript := preload("res://scripts/level/pockets/natatorium.gd")
const SonoScript := preload("res://scripts/monsters/sonographer_brain.gd")
const LootTableScript := preload("res://scripts/economy/loot_table.gd")
const ItemsScript := preload("res://scripts/items.gd")
const PlayerScript := preload("res://scripts/player.gd")
const PocketBleedScript := preload("res://scripts/economy/pocket_bleed.gd")

var main: Node3D
var game: Game
var bot: Player
var seed_value := 4242
var only := ""
var _failures: Array = []
var _checks := 0
var _frames_mode := false


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		if kv[0] == "frames":
			_frames_mode = true
		if kv.size() < 2:
			continue
		match kv[0]:
			"seed": seed_value = int(kv[1])
			"only": only = kv[1]
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	game = main.game
	main.menu.hide_menu()
	Net.start_solo("Bot")
	if only == "":
		_check_pocket_items()
	for kind in Plan.KINDS:
		if only != "" and only != kind:
			continue
		await _run_space(kind)
	Plan.force_kind = ""
	_finish()


## POCKETS 2 phase 5: POCKET_ITEMS, checked for every space at once rather than per space.
##
## The convention is the Natatorium's (phase 2) and the queued "items bleed out near the seam" task
## reads it from all of them, so the thing worth testing is that the spaces AGREE -- one shape, one
## meaning -- not that any one of them has a list. It needs no built shift, so it runs before the
## walk-throughs and costs nothing.
func _check_pocket_items() -> void:
	_say("==== POCKET_ITEMS")
	var seen := {}         # item kind -> the space that claimed it
	# SPACE_ROOMS is written by hand, so the first thing to check is that it has not gone stale.
	for kind: String in PocketSpaces.LAYOUTS.keys():
		_check(not _room_kinds_of(kind).is_empty(),
			"%s: pockettest's SPACE_ROOMS knows this space's room kinds" % kind)
	for kind: String in PocketSpaces.LAYOUTS.keys():
		var script: GDScript = PocketSpaces.LAYOUTS[kind]
		var items: Array = script.get("POCKET_ITEMS") if script.get("POCKET_ITEMS") != null else []
		# Every space declares one. An empty list is a space that contributes nothing, which after
		# phase 5 is no longer true of any of them -- so an empty one here means someone forgot.
		_check(not items.is_empty(), "%s: declares a non-empty POCKET_ITEMS (%s)" % [kind, str(items)])
		# The room kinds this space's own layout uses. A pocket item must live in its own space and
		# nowhere else, which is what "rooms names only my rooms, and never the wildcard" means.
		var my_rooms := _room_kinds_of(kind)
		for k: String in items:
			# A pocket item may be sellable loot (most of them) or a supply: the Chapel's communion
			# wine and the Restaurant's tequila are anesthetic substitutes, so they live in
			# Items.ITEMS and are fenced by the same `rooms` key (ItemSpawner._legal). Both tables
			# are legitimate; what matters is that the kind is real and fenced to this space.
			var rooms := _rooms_of(k)
			_check(not rooms.is_empty(), "%s: %s is a real item kind that names where it spawns" % [kind, k])
			_check(not rooms.has("*"), "%s: %s does not list \"*\", so it cannot spawn in the hospital" % [kind, k])
			for r: String in rooms.keys():
				_check(my_rooms.has(r), "%s: %s spawns in %s, which is one of this space's rooms" % [kind, k, r])
			# Two spaces claiming the same kind would make "which space is this from" unanswerable.
			_check(not seen.has(k), "%s: %s is claimed by exactly one space (also %s)" % [kind, k, String(seen.get(k, ""))])
			seen[k] = kind
	# And the other way round: any kind, from either table, whose rooms are wholly one pocket's must
	# be in that pocket's POCKET_ITEMS, or the lists silently drift as items are added.
	var every: Array = LootTableScript.kinds() + ItemsScript.ITEMS.keys()
	for k: String in every:
		var rooms := _rooms_of(k)
		if rooms.is_empty() or rooms.has("*"):
			continue
		for kind: String in PocketSpaces.LAYOUTS.keys():
			var my_rooms := _room_kinds_of(kind)
			var all_mine := true
			for r: String in rooms.keys():
				if not my_rooms.has(r):
					all_mine = false
					break
			if all_mine:
				_check(String(seen.get(k, "")) == kind,
					"%s: %s spawns only here, so POCKET_ITEMS lists it" % [kind, k])
	_bleed_agrees()


## POCKETS 2, the bleed. Each space declares what it holds as POCKET_ITEMS beside its layout, and
## LootTable says the same thing again with a per-kind `pocket` field, because the loot planner runs
## in `-s` tools that must not load the pocket runtime. The two must not drift apart.
func _bleed_agrees() -> void:
	_say("==== the bleed")
	_check(PocketBleedScript.MOUTH_TILES == Stub.CORRIDOR,
		"the bleed measures a seam's mouth the same way the stub builds it (%d / %d)"
			% [PocketBleedScript.MOUTH_TILES, Stub.CORRIDOR])
	for space: String in PocketSpaces.LAYOUTS.keys():
		var script: GDScript = PocketSpaces.LAYOUTS[space]
		var items: Array = script.get("POCKET_ITEMS") if script.get("POCKET_ITEMS") != null else []
		# Only the loot half of POCKET_ITEMS can bleed: the bleed is a swap made inside the loot plan,
		# so a kind that lives in Items.ITEMS is invisible to it. That is the Chapel's communion wine
		# and the Restaurant's tequila -- both anesthetic substitutes, both supplies, neither loot.
		var loot: Array = []
		for k in items:
			if LootTableScript.has(String(k)):
				loot.append(String(k))
		loot.sort()
		_check(LootTableScript.pocket_kinds(space) == loot,
			"%s: the loot table names the same items the space does (%s)" % [space, str(loot)])
		# A kind may only bleed out of a space that actually holds it.
		for k: String in LootTableScript.bleeding_kinds(space):
			_check(loot.has(k), "%s: %s may only bleed if the space actually holds it" % [space, k])
		# A space that holds loot has something to swap in, or the bleed is dead for that space.
		_check(loot.is_empty() or not LootTableScript.bleeding_kinds(space).is_empty(),
			"%s: a space that holds loot bleeds at least one kind" % space)


## Where a kind is allowed to spawn, from whichever table defines it. {} when it names nowhere,
## which for a supply means "anywhere" and for loot means "never" -- either way it is not a fenced
## pocket item, and the caller treats an empty result as a failure or a skip as it needs.
func _rooms_of(kind: String) -> Dictionary:
	if LootTableScript.has(kind):
		return (LootTableScript.LOOT[kind] as Dictionary).get("rooms", {})
	if ItemsScript.ITEMS.has(kind):
		return (ItemsScript.ITEMS[kind] as Dictionary).get("rooms", {})
	return {}


## The room kinds each space puts on the map. Spelt out rather than reflected out of the layout
## scripts, for the reason tools/loottest.gd gives for its own copy: building five layouts just to
## read their room names is slow and fragile, and a helper that quietly returns nothing turns every
## check below into a false failure instead of an honest one. (It did exactly that the first time
## this section ran: it asked for a `room` key that is really called `room_kind` and passed a
## Dictionary where `layout()` wants an Array of stubs, and all five spaces "failed" identically.)
##
## _check_pocket_items asserts this covers every space in LAYOUTS, so a new space cannot slip past.
const SPACE_ROOMS := {
	"factory": ["factory_floor", "factory_office", "factory_catwalk"],
	"restaurant": ["restaurant", "restaurant_kitchen", "restaurant_restroom"],
	"natatorium": ["natatorium_deck", "natatorium_pool", "natatorium_lockers"],
	"chapel": ["chapel_nave", "chapel_aisle", "chapel_sanctuary", "chapel_sacristy"],
	"laundromat": ["laundromat", "laundromat_back"],
}


func _room_kinds_of(kind: String) -> Dictionary:
	var out := {}
	for r: String in SPACE_ROOMS.get(kind, []):
		out[r] = true
	return out


func _run_space(kind: String) -> void:
	_say("==== %s (seed %d)" % [kind, seed_value])
	Plan.force_kind = kind
	game.start_session(seed_value)
	await _frames(3)
	while game.get_parent().has_node("WarmupCover"):
		await _frames(1)
	bot = game.local_player()
	bot.bot_active = true
	bot.bot_invulnerable = true
	if _frames_mode:
		await _frames(30)
		await _frame_times(kind)
		return
	game.begin_shift()
	game._clear_monsters()
	await _frames(20)
	var pk = game.pockets
	_check(pk.active() and String(pk.pocket.kind) == kind, "%s: the pocket is built" % kind)
	if not pk.active():
		return
	var wings := {}
	for s in pk.seams:
		wings[s.wing] = true
	_check(pk.seams.size() >= 2 and wings.size() >= 2, "%s: %d entrances into %d different wings" % [kind, pk.seams.size(), wings.size()])
	_check(game.level_info.get("pockets", {}).get("seams", []).size() == pk.seams.size(), "%s: level_info.pockets lists every seam" % kind)
	_doors_in_place(kind, pk, kind)
	# Seams line up: the same stub-local point through both frames and the transform agree.
	for s in pk.seams:
		var worst := 0.0
		for p in [Vector2(0.5, 0.5), Vector2(Stub.seam_s(s.w), float(s.d) - 1.0), Vector2(float(s.w) - 0.5, 0.5)]:
			var h := Stub.local_point(s.xh, p.x, p.y, 1.0)
			var q := Stub.local_point(s.xp, p.x, p.y, 1.0)
			worst = maxf(worst, ((s.t as Transform3D) * h).distance_to(q))
			worst = maxf(worst, ((s.t_inv as Transform3D) * q).distance_to(h))
		_check(worst < 0.001, "%s seam %d: both copies line up (%.5f m)" % [kind, int(s.id), worst])
	await _check_nav(kind, pk)
	_ambient_noise_floor(kind, pk)
	await _footstep_masking(kind, pk)
	_wander_fenced(kind, pk)
	if kind == "natatorium":
		_water(kind, pk)
	# Helpers: a downed bot to carry and a second bot holding supplies.
	var carried := _make_bot(-101, "Carried")
	var follower := _make_bot(-102, "Follower")
	await _frames(2)
	for s in pk.seams:
		for into in [true, false]:
			await _walk_through(kind, s, into, carried, follower)
	_remove_bot(carried)
	_remove_bot(follower)
	await _frames(2)
	await _nurse_follows(kind, pk)
	await _sonographer_hears(kind, pk)
	await _item_crosses(kind, pk)
	game._clear_monsters()
	await _rebuild_next_shift(kind)
	game._clear_monsters()


# =========================================================================
# POCKET_SPACES_2 phase 2: the Natatorium's water
# =========================================================================

## The water is the whole room, so what has to hold is the shape of the choice it offers, not just
## that a rect exists: the pool is water, the deck beside it is not, the hospital is not, and a
## footstep taken in the water is loud enough to be *certain* to a Sonographer where a dry one is
## not -- including crouched, which is the one place the water overrides the rule that crouching is
## silence. If any of that stops being true the shortcut stops costing anything.
func _water(kind: String, pk) -> void:
	var lay: Dictionary = pk.pocket.layout
	var o: Vector2i = pk.pocket.origin
	var r: Rect2i = NatatoriumScript.water_rect()
	var w := func(t: Vector2, y := 0.0) -> Vector3:
		return Vector3((float(o.x) + t.x) * C.TILE, y, (float(o.y) + t.y) * C.TILE)
	var middle: Vector3 = w.call(Vector2(r.get_center()) + Vector2(0.5, 0.5))
	var deck: Vector3 = w.call(Vector2(float(r.position.x) - 3.5, float(r.get_center().y)))
	_check(pk.water_at(middle), "%s: the middle of the pool is water" % kind)
	_check(not pk.water_at(deck), "%s: the deck three tiles off the edge is not" % kind)
	_check(not pk.water_at(bot.global_position) and not pk.in_pocket(bot.global_position),
		"%s: and neither is the hospital" % kind)
	_check(pk.in_pocket(middle) and pk.in_pocket(deck), "%s: both of those are inside the pocket" % kind)
	# The loudness, against the Sonographer's own numbers rather than against themselves.
	var wet: Array = pk.water_footstep(middle, false, false)
	var dry: Array = pk.water_footstep(deck, false, false)
	_check(dry.is_empty(), "%s: a step on the deck uses the hospital's own footstep numbers" % kind)
	_check(not wet.is_empty() and float(wet[0]) >= SonoScript.LOUD,
		"%s: wading at a walk is past LOUD, so it is certain and not merely suspicious (%.2f vs %.2f)" % [kind, float(wet[0]) if not wet.is_empty() else 0.0, SonoScript.LOUD])
	_check(not wet.is_empty() and float(wet[0]) > 0.25 * 3.0,
		"%s: ... and worth more than three dry walks (%.2f)" % [kind, float(wet[0]) if not wet.is_empty() else 0.0])
	var crouched: Array = pk.water_footstep(middle, false, true)
	_check(not crouched.is_empty() and float(crouched[0]) > 0.25,
		"%s: crouching in water is still louder than walking on tile, not silence (%.2f)" % [kind, float(crouched[0]) if not crouched.is_empty() else 0.0])
	_check(not crouched.is_empty() and float(crouched[0]) < SonoScript.LOUD,
		"%s: ... but it is the one way across that is not certain" % kind)
	var sprint: Array = pk.water_footstep(middle, true, false)
	_check(not sprint.is_empty() and float(sprint[0]) > float(wet[0]),
		"%s: running through it is louder still (%.2f)" % [kind, float(sprint[0]) if not sprint.is_empty() else 0.0])
	# The room declares no ambient floor, so none of that loudness is quietly refunded.
	_check(is_equal_approx(pk.ambient_noise_at(middle), 0.0),
		"%s: the room masks nothing, so the water's cost is real" % kind)
	# The items the space contributes are readable as a set, not scattered through the layout.
	var items: Array = NatatoriumScript.POCKET_ITEMS
	_check(items.has("pool_chemical_drum") and items.has("lifeguard_whistle"),
		"%s: POCKET_ITEMS names what the space contributes (%s)" % [kind, str(items)])
	for k: String in items:
		_check(LootTableScript.has(k), "%s: %s is a real loot kind" % [kind, k])
	# The cabinet is never empty.
	var cabinets := 0
	var stocked := {}
	for c in game.level_info.get("containers", []):
		if String(c.get("type", "")) != "first_aid_cabinet":
			continue
		cabinets += 1
		for it in game.world_items.values():
			if is_instance_valid(it) and it.state == WorldItem.State.IN_CONTAINER and String(it.container_id) == String(c.id):
				stocked[String(it.kind)] = true
	_check(cabinets >= 1, "%s: the lifeguard stand has a first-aid cabinet (%d)" % [kind, cabinets])
	_check(stocked.has("gauze") and stocked.has("tourniquet"),
		"%s: and it is stocked with gauze and a tourniquet (%s)" % [kind, str(stocked.keys())])


# =========================================================================
# POCKET_SPACES_2 phase 1
# =========================================================================

## The ambient noise floor. The Factory and the Restaurant declare 0.0, which has to mean "hearing
## is exactly what it always was": the floor is subtracted from a noise's loudness before the
## Sonographer's reach maths, so 0.0 is the identity. The Laundromat (phase 4) declares a real one.
## The checks below pin both halves for either case — the declared value, and what
## `ambient_noise_at` answers inside the space and out in the hospital.
const FLOOR_EXPECTED := {"factory": 0.0, "restaurant": 0.0, "laundromat": 0.30}

func _ambient_noise_floor(kind: String, pk) -> void:
	var want: float = float(FLOOR_EXPECTED.get(kind, 0.0))
	var declared: float = pk.ambient_noise_of(kind)
	_check(is_equal_approx(declared, want), "%s: declares an ambient noise floor of %.2f (got %.3f)" % [kind, want, declared])
	var inside: float = pk.ambient_noise_at(pk.pocket.spawn)
	_check(is_equal_approx(inside, want), "%s: the floor inside the pocket is %.2f (got %.3f)" % [kind, want, inside])
	var outside: float = pk.ambient_noise_at(bot.global_position)
	_check(is_equal_approx(outside, 0.0), "%s: the hospital has no floor (got %.3f)" % [kind, outside])
	_check(not pk.in_pocket(bot.global_position), "%s: ... and that reading was taken in the hospital" % kind)


## POCKETS 2 phase 4, and the phase 7 acceptance test for the Laundromat: the drone genuinely masks
## footsteps. Two halves, because either one alone could pass for the wrong reason.
##
## The arithmetic half checks the claim against the numbers it is made of — game.gd's own footstep
## loudnesses and the Sonographer's own reach constant, read from those files rather than retyped —
## so the day somebody retunes a footstep, this fails instead of quietly becoming false.
##
## The live half puts a real Sonographer a few metres from a real walking player, once inside the
## Laundromat and once out in the hospital, and asks the brain what it heard. Inside: nothing, ever.
## Outside, at the same distance: the footsteps.
func _footstep_masking(kind: String, pk) -> void:
	var floor_level: float = pk.ambient_noise_of(kind)
	var walk: float = game.FOOTSTEP_LOUDNESS
	var sprint: float = game.FOOTSTEP_SPRINT_LOUDNESS
	var per: float = SonoScript.HEAR_PER_LOUDNESS
	var walk_reach: float = maxf(walk - floor_level, 0.0) * per
	var sprint_reach: float = maxf(sprint - floor_level, 0.0) * per
	if kind != "laundromat":
		_check(is_equal_approx(walk_reach, walk * per), "%s: a walking footstep still carries its full %.1f m" % [kind, walk * per])
		return
	_check(floor_level > walk, "laundromat: the floor (%.2f) is above a walking footstep (%.2f), so one is masked outright" % [floor_level, walk])
	_check(is_equal_approx(walk_reach, 0.0), "laundromat: a walking footstep carries 0 m inside (got %.2f m)" % walk_reach)
	_check(walk * per > 4.0, "laundromat: ... and the same footstep carries %.1f m outside" % (walk * per))
	_check(sprint_reach > 6.0 and sprint_reach < sprint * per, 			"laundromat: a sprinting one still carries, but shorter: %.1f m in here against %.1f m outside" % [sprint_reach, sprint * per])
	var margin := sprint - floor_level
	_check(margin < SonoScript.LOUD, "laundromat: and a sprint drops under the brain's certainty threshold (%.2f < %.2f), so it fills suspicion instead" % [margin, SonoScript.LOUD])
	# The live half.
	var inside: bool = await _walk_heard(pk, true)
	_check(not inside, "laundromat: a Sonographer beside a walking player in here hears no footstep at all")
	var outside: bool = await _walk_heard(pk, false)
	_check(outside, "laundromat: the same Sonographer and the same walk out in the hospital does hear them")


## Stand the bot and a Sonographer MASK_GAP apart (inside the pocket, or out in the hospital), walk
## the bot on the spot for a few seconds, and answer whether the brain ever logged a footstep.
const MASK_GAP := 4.0
const MASK_SECONDS := 6.0

func _walk_heard(pk, in_pocket: bool) -> bool:
	var at: Vector3 = pk.pocket.spawn if in_pocket else game.level_info.get("or_table", Vector3.ZERO)
	if not in_pocket:
		at = _hospital_floor_near(bot.global_position)
	bot.teleport(at)
	await _frames(2)
	var m = game._add_monster("sonographer", at + Vector3(MASK_GAP, 0.0, 0.0))
	await _frames(2)
	# Calm it and blank what it has already heard, so only this walk counts.
	m.calm = 0.0
	var brain = m.get("brain")
	if brain != null:
		brain.last_heard = {}
	var heard := false
	var t0: float = game.world_time
	while game.world_time - t0 < MASK_SECONDS:
		# Walk on the spot: `moving` and not crouching is all _tick_noise looks at.
		bot.moving = true
		bot.sprinting = false
		bot.crouching = false
		bot.silent_steps = false
		await _frames(1)
		if brain != null and String((brain.last_heard as Dictionary).get("kind", "")) == "footstep":
			heard = true
			break
	game.kill_monster(m)
	bot.moving = false
	await _frames(2)
	return heard


## A point on the hospital's own floor near `from`, for the "and outside it is heard" half.
func _hospital_floor_near(from: Vector3) -> Vector3:
	var pk = game.pockets
	if not pk.in_pocket(from) and pk.phantom_at(from).is_empty():
		return from
	return game.level_info.get("or_table", Vector3.ZERO)


## Idle wander is fenced at the stub. A goal in the other space is refused whichever side you stand
## on, a goal in your own space is allowed, and a goal in a stub's dead half is refused — that half
## is the other copy, so walking to it is walking through the seam. Chases and spawns do not come
## through this predicate and are checked elsewhere (_nurse_follows, _sonographer_hears).
func _wander_fenced(kind: String, pk) -> void:
	# A wing hallway, not wherever the bot happens to be standing: at the start of a shift that is
	# the neutral area, which monster_may_wander_to excludes on its own account and always did.
	var here := Vector3.INF
	for sp in game.level_info.get("monster_spawns", []):
		if not pk.in_pocket(sp):
			here = sp
			break
	var there: Vector3 = pk.pocket.spawn
	_check(here.is_finite() and pk.in_pocket(there), "%s: a hospital wing point and a pocket point to test with" % kind)
	if not here.is_finite():
		return
	_check(not game.monster_may_wander_to(there, here), "%s: a monster in the hospital may not wander into the pocket" % kind)
	_check(not game.monster_may_wander_to(here, there), "%s: a monster in the pocket may not wander out into the hospital" % kind)
	_check(game.monster_may_wander_to(there, there), "%s: a monster in the pocket may still wander inside it" % kind)
	_check(game.monster_may_wander_to(here, here), "%s: a monster in the hospital may still wander the hospital" % kind)
	# The dead half of every stub, from both sides.
	for s in pk.seams:
		var mid := Stub.seam_s(s.w)
		var dead_h := Stub.local_point(s.xh, mid + (float(s.w) - mid) * 0.5, float(s.d) * 0.5, 0.1)
		var dead_p := Stub.local_point(s.xp, mid * 0.5, float(s.d) * 0.5, 0.1)
		_check(not game.monster_may_wander_to(dead_h, here), "%s seam %d: the hospital stub's dead half is not a wander goal" % [kind, int(s.id)])
		_check(not game.monster_may_wander_to(dead_p, there), "%s seam %d: the pocket stub's dead half is not a wander goal" % [kind, int(s.id)])
	# Left as it was without a `from`: the old two-argument-free behaviour still answers on zones
	# alone, so nothing that has not been taught to pass its position changes meaning.
	_check(game.monster_may_wander_to(there), "%s: with no `from` the fence stays out of it" % kind)


# =========================================================================
# walking through
# =========================================================================

func _walk_through(kind: String, s: Dictionary, into: bool, carried: Player, follower: Player) -> void:
	var pk = game.pockets
	var tag := "%s seam %d %s" % [kind, int(s.id), "into the pocket" if into else "back to the hospital"]
	var line: Array = Stub.centre_line(s.w, s.d)
	if into:
		line = [Vector2(1.0, -2.2)] + line + [Vector2(float(s.w) - 1.0, -3.6)]
	else:
		line.reverse()
		line = [Vector2(float(s.w) - 1.0, -4.2)] + line + [Vector2(1.0, -2.0)]
	var start_frame: Transform3D = s.xh if into else s.xp
	var p0: Vector2 = line[0]
	var p1: Vector2 = line[1]
	# The carrier at the start, facing along the path; the downed bot on its shoulder; the follower
	# a moment behind with gauze in hand.
	_revive(carried)
	_revive(follower)
	bot.slots = PlayerScript.empty_slots()
	var start := Stub.local_point(start_frame, p0.x, p0.y)
	var dir := (Stub.local_point(start_frame, p1.x, p1.y) - start).normalized()
	bot.teleport(start)
	follower.teleport(start)
	carried.teleport(start + Vector3(0.6, 0, 0.6))
	await _frames(2)
	game.down_player(carried, "test")
	await _frames(2)
	game.start_carry(bot, carried)
	follower.slots = PlayerScript.empty_slots()
	follower.take_into("gauze", 3)
	follower.selected = 0
	await _frames(2)
	_check(bot.carrying == carried.peer_id and carried.carried_by == bot.peer_id, "%s: carrying the downed bot" % tag)
	var crossings_before := _count_crossings("player", bot.peer_id)
	var follower_before := _count_crossings("player", follower.peer_id)
	var walkers := [{"p": bot, "i": 1, "wait": 0.0}, {"p": follower, "i": 1, "wait": 0.45}]
	var t0 := game.world_time
	var jump_worst := 0.0
	var carry_worst := 0.0
	var speed_break := 0.0
	var prev := {}
	var done := false
	while game.world_time - t0 < 40.0 and not done:
		done = true
		for w in walkers:
			var p: Player = w.p
			var i: int = w.i
			if game.world_time - t0 < float(w.wait):
				done = false
				continue
			if i >= line.size():
				p.bot_move = Vector2.ZERO
				continue
			done = false
			var frame: Transform3D = s.xp if pk.in_pocket(p.global_position) else s.xh
			var wp: Vector2 = line[i]
			var target := Stub.local_point(frame, wp.x, wp.y)
			var to := target - p.global_position
			to.y = 0.0
			if to.length() < 0.35:
				w.i = i + 1
				continue
			p.bot_yaw = atan2(-to.x, -to.z)
			p.bot_move = Vector2(0, -1)
			# Continuity in stub-local terms across the move: position and velocity.
			var l := Stub.to_local(frame, p.global_position)
			var lv := frame.basis.inverse() * p.velocity
			var key := p.peer_id
			if prev.has(key):
				var pl: Vector3 = prev[key][0]
				var plv: Vector3 = prev[key][1]
				jump_worst = maxf(jump_worst, Vector2(l.x - pl.x, l.z - pl.z).length() * Stub.T)
				if plv.length() > 1.0 and lv.length() > 1.0:
					speed_break = maxf(speed_break, (lv - plv).length())
			prev[key] = [l, lv]
		if bot.carrying == carried.peer_id:
			carry_worst = maxf(carry_worst, carried.global_position.distance_to(bot.global_position))
		await _frames(1)
	bot.bot_move = Vector2.ZERO
	follower.bot_move = Vector2.ZERO
	if not done:
		for w in walkers:
			var p: Player = w.p
			var fr: Transform3D = s.xp if pk.in_pocket(p.global_position) else s.xh
			_say("     %s stopped at waypoint %d/%d, stub-local %s, in pocket %s" % [p.player_name, int(w.i), line.size(), str(Stub.to_local(fr, p.global_position)), str(pk.in_pocket(p.global_position))])
	_check(done,"%s: both walkers reached the far end (%.1f s)" % [tag, game.world_time - t0])
	var want_pocket := into
	_check(pk.in_pocket(bot.global_position) == want_pocket and pk.in_pocket(follower.global_position) == want_pocket, "%s: carrier and follower end on the far side" % tag)
	_check(_count_crossings("player", bot.peer_id) - crossings_before == 1, "%s: the carrier crossed exactly once (%d)" % [tag, _count_crossings("player", bot.peer_id) - crossings_before])
	_check(_count_crossings("player", follower.peer_id) - follower_before == 1, "%s: the follower crossed exactly once" % tag)
	_check(jump_worst < 0.25, "%s: nobody jumped in stub-local terms (worst step %.3f m)" % [tag, jump_worst])
	_check(speed_break < 1.5, "%s: velocity carried across (worst change %.2f m/s in one frame)" % [tag, speed_break])
	_check(bot.carrying == carried.peer_id and carry_worst < 1.8, "%s: the carried bot stayed on the shoulder (worst %.2f m)" % [tag, carry_worst])
	_check(pk.in_pocket(carried.global_position) == want_pocket, "%s: the carried bot is on the far side too" % tag)
	_check(follower.holding("gauze") and int(follower.slots[follower.slot_for("gauze")].count) == 3, "%s: the follower still holds its gauze" % tag)
	_check(pk.phantom_at(bot.global_position).is_empty() and pk.phantom_at(follower.global_position).is_empty(), "%s: nobody stands in a stub's unwalked half" % tag)
	game.drop_carried(bot)
	await _frames(2)


func _count_crossings(what: String, id: int) -> int:
	var n := 0
	for c in game.pockets.crossings:
		if c.what == what and int(c.id) == id:
			n += 1
	return n


func _make_bot(id: int, nm: String) -> Player:
	var p = PlayerScript.new_player(id, nm, false)
	p.is_bot = true
	p.bot_active = true
	p.bot_invulnerable = true
	p.set_flashlight(false)
	game.players[id] = p
	game.get_node("Entities").add_child(p)
	return p


func _remove_bot(p: Player) -> void:
	if p.carried_by != 0:
		var q = game.players.get(p.carried_by)
		if q != null:
			game.drop_carried(q)
	game.players.erase(p.peer_id)
	p.queue_free()


func _revive(p: Player) -> void:
	if p.carried_by != 0:
		var q = game.players.get(p.carried_by)
		if q != null:
			game.drop_carried(q)
	p.revive_full()
	p.refresh_downed_visuals()


# =========================================================================
# navigation, monsters, items, noise
# =========================================================================

func _check_nav(kind: String, pk) -> void:
	var map := get_viewport().world_3d.navigation_map
	for i in 120:
		if NavigationServer3D.map_get_iteration_id(map) > 0:
			break
		await _frames(1)
	await _frames(4)
	var start: Vector3 = game.spawn_points()[0]
	var goal: Vector3 = pk.pocket.spawn
	var path := NavigationServer3D.map_get_path(map, start, NavigationServer3D.map_get_closest_point(map, goal), true)
	var jump := 0.0
	for i in range(1, path.size()):
		jump = maxf(jump, path[i - 1].distance_to(path[i]))
	_check(path.size() >= 2 and path[path.size() - 1].distance_to(goal) < 3.0 and jump > 200.0,
			"%s: a navigation path from the neutral area into the pocket goes through a seam link (ends %.1f m off, longest step %.0f m)" % [kind, path[path.size() - 1].distance_to(goal) if path.size() > 0 else -1.0, jump])
	# Nothing past a seam is on the navigation mesh.
	for s in pk.seams:
		var ph := Stub.local_point(s.xh, float(s.w) - 1.0, 1.0)
		var pp := Stub.local_point(s.xp, 1.0, 1.0)
		var qh := NavigationServer3D.map_get_closest_point(map, ph)
		var qp := NavigationServer3D.map_get_closest_point(map, pp)
		_check(qh.distance_to(ph) > 1.0 and qp.distance_to(pp) > 1.0, "%s seam %d: the unwalked halves are off the navigation mesh (%.1f, %.1f m)" % [kind, int(s.id), qh.distance_to(ph), qp.distance_to(pp)])
		# Through this seam both ways: from its hospital leg 1 to its pocket leg 3 and back.
		var a := NavigationServer3D.map_get_closest_point(map, Stub.local_point(s.xh, 1.0, 1.0))
		var b := NavigationServer3D.map_get_closest_point(map, Stub.local_point(s.xp, float(s.w) - 1.0, 1.0))
		for pair in [[a, b], [b, a]]:
			var pth := NavigationServer3D.map_get_path(map, pair[0], pair[1], true)
			var longest := 0.0
			var walked := 0.0
			for i in range(1, pth.size()):
				var dd: float = pth[i - 1].distance_to(pth[i])
				longest = maxf(longest, dd)
				if dd < 100.0:
					walked += dd
			_check(pth.size() >= 2 and pth[pth.size() - 1].distance_to(pair[1]) < 0.5 and longest > 100.0 and walked < float(s.w + s.d * 2) * 1.5 + 4.0,
					"%s seam %d: a path straight through its link (%d points, walks %.1f m, link %s)" % [kind, int(s.id), pth.size(), walked, str([NavigationServer3D.map_get_closest_point(map, s.link_h).distance_to(s.link_h), NavigationServer3D.map_get_closest_point(map, s.link_p).distance_to(s.link_p)])])


func _nurse_follows(kind: String, pk) -> void:
	var s: Dictionary = pk.seams[0]
	var map := get_viewport().world_3d.navigation_map
	var hall := NavigationServer3D.map_get_closest_point(map, Stub.local_point(s.xh, 1.0, -4.5))
	var stand := Stub.local_point(s.xp, float(s.w) - 1.0, -6.0)
	bot.teleport(stand)
	var away := stand - Stub.local_point(s.xp, float(s.w) - 1.0, -1.0)
	bot.bot_yaw = atan2(-away.x, -away.z)
	bot.set_flashlight(false)
	bot.bot_move = Vector2.ZERO
	var nurse = game._add_monster("night_nurse", hall)
	await _frames(2)
	var before := _count_crossings("monster", int(nurse.monster_id))
	var t0 := game.world_time
	while game.world_time - t0 < 60.0:
		if pk.in_pocket(nurse.global_position) and nurse.global_position.distance_to(bot.global_position) < 4.0:
			break
		await _frames(1)
	_check(pk.in_pocket(nurse.global_position), "%s: the Night Nurse followed the player through the seam (%.1f s, %.1f m away)" % [kind, game.world_time - t0, nurse.global_position.distance_to(bot.global_position)])
	_check(_count_crossings("monster", int(nurse.monster_id)) - before == 1, "%s: she crossed exactly once" % kind)
	bot.set_flashlight(true)
	game._clear_monsters()
	await _frames(2)


func _sonographer_hears(kind: String, pk) -> void:
	var s: Dictionary = pk.seams[pk.seams.size() - 1]
	var back := float(s.d) - 1.0
	var listener := Stub.local_point(s.xp, float(s.w) - 1.0, back)
	var speaker := Stub.local_point(s.xh, 2.6, back)
	# Mirrors: a noise at the speaker is also heard in the pocket copy, and that point means the speaker's side.
	var mirrors: Array = pk.mirror_noise(speaker, 0.8)
	var ok := false
	for m in mirrors:
		if pk.in_pocket(m) and (pk.real_point(m) as Vector3).distance_to(Stub.local_point(s.xh, 2.6, back)) < 2.5:
			ok = true
	_check(ok, "%s: a noise near a seam is mirrored into the other copy (%d mirrors)" % [kind, mirrors.size()])
	bot.teleport(speaker)
	bot.bot_move = Vector2.ZERO
	var d = game._add_monster("sonographer", listener)
	await _frames(2)
	var before := _count_crossings("monster", int(d.monster_id))
	var t0 := game.world_time
	var last_noise := -10.0
	# POCKETS 2 phase 4: the noise has to be one the listener can actually hear WHERE IT STANDS. The
	# listener is inside the pocket, and a space with an ambient noise floor (the Laundromat, 0.30)
	# subtracts that floor before the reach maths — so a flat 0.8 in there is really a 0.5, which is
	# the Laundromat doing its job rather than the seam failing. What this test is about is that
	# sound crosses a seam and a sound-hunter follows it, so clear the floor and keep the intent.
	# Factory and Restaurant declare 0.0, so for them this is the same 0.8 it always was.
	var loud: float = 0.8 + pk.ambient_noise_of(kind)
	while game.world_time - t0 < 40.0:
		if game.world_time - last_noise > 1.2:
			last_noise = game.world_time
			game.emit_noise(bot.global_position, loud, "test")
		if not pk.in_pocket(d.global_position) and d.global_position.distance_to(bot.global_position) < 3.0:
			break
		await _frames(1)
	if pk.in_pocket(d.global_position):
		_say("     Sonographer mode %d at stub-local %s, last heard %s" % [int(d.mode), str(Stub.to_local(s.xp, d.global_position)), str(d.brain.last_heard)])
	_check(not pk.in_pocket(d.global_position), "%s: the Sonographer heard the player through the seam and came through (%.1f s)" % [kind, game.world_time - t0])
	_check(_count_crossings("monster", int(d.monster_id)) - before == 1, "%s: the Sonographer crossed exactly once" % kind)
	game._clear_monsters()
	await _frames(2)


func _item_crosses(kind: String, pk) -> void:
	var s: Dictionary = pk.seams[0]
	var drop := Stub.local_point(s.xh, Stub.seam_s(s.w) + 0.35, float(s.d) - 1.0, 0.6)
	var it = game._spawn_item("gauze", 2, Transform3D(Basis(), drop), WorldItem.State.LOOSE)
	it.toss(Transform3D(Basis(), drop), Vector3(0.0, 0.5, 0.0))   # as game.drop_selected lets go of it
	await _frames(30)
	_check(is_instance_valid(it) and pk.in_pocket(it.global_position), "%s: an item dropped past the seam lands in the pocket copy" % kind)
	if is_instance_valid(it):
		var l := Stub.to_local(s.xp, it.global_position)
		_check(l.x > Stub.seam_s(s.w) - 0.2 and l.x < float(s.w) and l.z > 0.0 and l.z < float(s.d), "%s: ... at the same spot of the stub (%.2f, %.2f)" % [kind, l.x, l.z])
		game.world_items.erase(it.item_id)
		it.queue_free()


# =========================================================================
# the next shift: the pocket is torn down and built again with the wings
# =========================================================================

func _doors_in_place(kind: String, pk, tag: String) -> void:
	var lay: Dictionary = pk.pocket.layout
	var origin: Vector2i = pk.pocket.origin
	# Every space publishes its own doorways; ask it rather than knowing each one's layout keys.
	var tiles: Array = []
	for dw in PocketSpaces.script_of(kind).doorways(lay):
		for t in (dw.tiles as Array):
			tiles.append(t)
	var missing := 0
	for t: Vector2i in tiles:
		var d = game.doors.door_at_tile(origin + t)
		if d == null or not is_instance_valid(d) or not d.is_inside_tree():
			missing += 1
	_check(missing == 0 and not tiles.is_empty(), "%s: every doorway of the %s has a real door (%d doorways, %d missing)" % [tag, kind, tiles.size(), missing])


func _rebuild_next_shift(kind: String) -> void:
	var pk = game.pockets
	var tag := "%s next shift" % kind
	var old_root: Node = pk.pocket.root
	var gen_before: int = game.wing_loader.generation
	# Someone inside the pocket and an item on its floor when the shift ends.
	var inside: Vector3 = pk.pocket.spawn + Vector3(0, 0.2, 0)
	bot.teleport(inside)
	var it = game._spawn_item("gauze", 1, Transform3D(Basis(), inside + Vector3(1.0, 0.5, 0.0)), WorldItem.State.LOOSE)
	await _frames(10)
	_check(pk.in_pocket(bot.global_position), "%s: a player stands in the pocket before the shift ends" % tag)
	game._to_next_shift()
	await _frames(1)
	_check(not pk.in_pocket(bot.global_position), "%s: the player was walked out of the pocket (now %s)" % [tag, str(bot.global_position.snapped(Vector3.ONE * 0.1))])
	_check(not is_instance_valid(it) or it.is_queued_for_deletion() or not game.world_items.values().has(it), "%s: the item left in the pocket is gone" % tag)
	_check(not pk.active(), "%s: the old pocket is forgotten while the wings rebuild" % tag)
	var clocked := false
	var frames := 0
	var t0 := Time.get_ticks_msec()
	while (game.wing_loader.busy or pk.busy or not game.wing_loader.wings_ready) and Time.get_ticks_msec() - t0 < 120000:
		if not clocked and not game.wing_loader.busy and pk.busy:
			clocked = true
			game.clock_in()
			_check(game.phase == Game.Phase.LOBBY and game.clock_in_pending, "%s: clock-in waits while the pocket builds" % tag)
		await get_tree().process_frame
		frames += 1
	_check(not pk.busy and game.wing_loader.wings_ready, "%s: the wings and the pocket finished (%d frames)" % [tag, frames])
	await _frames(10)
	_check(not is_instance_valid(old_root), "%s: the old pocket's nodes are freed" % tag)
	_check(game.wing_loader.generation == gen_before + 1, "%s: wings generation %d" % [tag, game.wing_loader.generation])
	_check(pk.active() and String(pk.pocket.kind) == kind and pk.seams.size() >= 2, "%s: the pocket is built again (%d entrances)" % [tag, pk.seams.size()])
	if not pk.active():
		return
	_check(pk.pocket.root.get_parent() == game.level_info.get("wings_root"), "%s: the pocket lives under the wings root" % tag)
	_check(float(pk.stats.get("slowest_step_ms", 999.0)) < 40.0, "%s: no build step is long (slowest %.1f ms, longest frame of work %.1f ms, %d frames, %d ms on the thread)" % [
		tag, float(pk.stats.get("slowest_step_ms", 0.0)), float(pk.stats.get("max_frame_ms", 0.0)), int(pk.stats.get("frames", 0)), int(pk.stats.get("thread_ms", 0))])
	var in_info := 0
	for c in game.level_info.get("containers", []):
		if c.get("node") != null and is_instance_valid(c.node) and pk.in_pocket(c.node.global_position):
			in_info += 1
	_check(in_info > 0, "%s: level_info lists the new pocket's containers (%d)" % [tag, in_info])
	_check(game.level_info.get("pockets", {}).get("seams", []).size() == pk.seams.size(), "%s: level_info.pockets is the new pocket" % tag)
	_doors_in_place(kind, pk, tag)
	if clocked:
		await _frames(5)
		_check(game.phase == Game.Phase.SHIFT, "%s: the pending clock-in went through once the pocket was ready" % tag)
	# A crossing still works on the rebuilt pocket.
	var s: Dictionary = pk.seams[0]
	var carried := _make_bot(-101, "Carried")
	var follower := _make_bot(-102, "Follower")
	await _frames(2)
	await _walk_through(kind, s, true, carried, follower)
	_remove_bot(carried)
	_remove_bot(follower)
	await _frames(2)


## Windowed (--frames): every frame's time from the new lobby's first frame until the wings and the
## pocket are rebuilt, and a second more.
func _frame_times(kind: String) -> void:
	var pk = game.pockets
	bot.teleport(game.spawn_points()[0])
	await _frames(60)
	game._to_next_shift()
	var sum := 0.0
	var worst := 0.0
	var over := 0
	var n := 0
	var last := Time.get_ticks_usec()
	var done_ms := -1
	var worst_at := ""
	var by_phase := {}
	while done_ms < 0 or Time.get_ticks_msec() - done_ms < 1000:
		var phase := "wings" if game.wing_loader.busy else ("pocket" if pk.busy else "after")
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		var ms := float(now - last) / 1000.0
		last = now
		n += 1
		sum += ms
		by_phase[phase] = maxf(float(by_phase.get(phase, 0.0)), ms)
		if ms > worst:
			worst = ms
			worst_at = phase
		if ms > 33.0:
			over += 1
		if done_ms < 0 and not game.wing_loader.busy and not pk.busy:
			done_ms = Time.get_ticks_msec()
	_say("%s windowed rebuild: %d frames, average %.1f ms, worst %.1f ms (during %s), frames over 33 ms %d, worst by phase %s" % [kind, n, sum / maxf(1.0, n), worst, worst_at, over, str(by_phase)])
	_say("  wings %s" % str(game.wing_loader.stats))
	_say("  pocket %s, teardown %.1f ms" % [str(pk.stats), float(pk.teardown_ms)])
	_check(pk.active(), "%s: the pocket rebuilt" % kind)
	_check(worst < 50.0, "%s: no frame over 50 ms while the wings and the pocket rebuild (worst %.1f ms)" % [kind, worst])


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if ok:
		_say("ok   " + what)
	else:
		_say("FAIL " + what)
		_failures.append(what)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _say(line: String) -> void:
	print("[pockettest] " + line)


func _finish() -> void:
	if _failures.is_empty():
		_say("PASS: %d checks" % _checks)
		get_tree().quit(0)
	else:
		_say("FAILED %d of %d checks" % [_failures.size(), _checks])
		for f in _failures:
			_say("  " + f)
		get_tree().quit(1)
