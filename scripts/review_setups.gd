class_name ReviewSetups
extends RefCounted
## Named review setups: `--setup=<name>` after `--` (tools/review.ps1 passes it on) opens a review
## window straight in a shift, with the player where the setup puts them and the thing to test
## already staged: no home screen, no lobby, no getting ready (RULES.md, Reviews).
##
## main.gd's launch calls requested(); when a name is given (and known) it skips the title menu, starts a
## session on the setup's seed (`--seed=N` overrides it), begins the shift and lets the world settle,
## then calls stage(name, game). An unknown name lists the known ones in the log and opens the menu.
##
## Solo or co-op. One window (`-Count 1`, the default) is a solo session, as it always was. With
## `-Count 2` (or more) tools/review.ps1 hands window 1 `--setup-role=host` and the rest
## `--setup-role=join`, plus a shared `--setup-port=N`, so the whole set lands in ONE world:
##   * the host opens an ENet server on that port, drops a lock file (mark_hosting) so the joiners
##     know it is listening, waits for them to turn up in the lobby, and only then begins the shift
##     and stages. Staging is host-authoritative world state (placing people, handing out items,
##     starting a case), so only the host ever runs a stage function.
##   * a joiner waits for that lock file, joins 127.0.0.1 on the port, and once the shift is under
##     way stands its own player beside the host's with place_beside(), looking the same way: an
##     onlooker's view of whatever the setup staged.
## The host waits for its joiners on purpose. A client that arrives after begin_shift spectates
## until the next shift's lobby instead of spawning -- and two windows that look right but are not
## actually playing together is exactly the failure this exists to prevent.
##
## To add a setup (one function, one line):
##   1. add an entry to SETUPS:  "hive_lunge": {"seed": 4242, "stage": "_hive_lunge"},
##   2. write   static func _hive_lunge(game: Game) -> void:   using the helpers below.
## `seed` is optional (default DEFAULT_SEED). Stage functions may await (use game.get_tree()).
## Then open it:  tools\review.bat 2 "HIVE: does the lunge read?" --setup=hive_lunge

const DEFAULT_SEED := 4242
const MirrorsScript := preload("res://scripts/personnel/mirrors.gd")

const SETUPS := {
	"icons": {"seed": 4242, "stage": "_icons"},
	# POCKETS 2 phase 2 (docs/POCKET_SPACES_2.md): standing on the Natatorium's deck at the water's
	# edge, a lifeguard whistle and a pool chemical drum to hand, the stocked first-aid cabinet on the
	# lifeguard stand behind you. Walk the pool and walk the deck and listen to the difference.
	"natatorium": {"seed": 4242, "pocket": "natatorium", "stage": "_natatorium"},
	# POCKETS 2 phase 4 (docs/POCKET_SPACES_2.md): inside the Laundromat with its three items in
	# hand and a Sonographer already hunting you, in a room where it cannot hear you walk.
	"laundromat": {"seed": 4242, "pocket": "laundromat", "stage": "_laundromat"},
	"chapel": {"seed": 4242, "pocket": "chapel", "stage": "_chapel"},
	# fix-pocket-zfighting: the two places the flicker was reported. On the Natatorium's east deck a
	# step from a starting block, looking at its foot; in the Laundromat between two washer islands,
	# looking down at their feet. Monsters off, torch on: walk about and watch where box meets floor.
	"zfight_pool": {"seed": 4242, "pocket": "natatorium", "stage": "_zfight_pool"},
	"zfight_laundry": {"seed": 4242, "pocket": "laundromat", "stage": "_zfight_laundry"},
	# POCKETS 2 phase 4b (docs/POCKET_SPACES_2.md): on the hospital side, in front of something from
	# the pocket that has no business being there. The seed is one whose Natatorium bleeds on shift 1.
	"bleed": {"seed": 4242, "pocket": "natatorium", "stage": "_bleed"},
	# POCKETS 2 phase 6 (docs/POCKET_SPACES_2.md): the Onlooker, in the Natatorium because its 72 m
	# hall is the longest sightline in the game. Stand at one end and it will be at the other.
	# `onlooker_chapel` is the same thing down the Chapel's 33 m nave, where the piers give it
	# things to stand behind.
	"onlooker": {"seed": 4242, "pocket": "natatorium", "stage": "_onlooker"},
	"onlooker_chapel": {"seed": 4242, "pocket": "chapel", "stage": "_onlooker"},
	# 2026-09-24: the Onlooker's shadow and its poof. It is already standing eleven metres in front of
	# you, wreathed in its smoke, waiting: run at it and it poofs. It comes back far off (a few
	# seconds rather than the real 75), so you can go at it again as often as you like.
	# `onlooker_rush_chapel` / `_factory` are the same thing in other light and other fog.
	"onlooker_rush": {"seed": 4242, "pocket": "natatorium", "stage": "_onlooker_rush"},
	"onlooker_rush_chapel": {"seed": 4242, "pocket": "chapel", "stage": "_onlooker_rush"},
	"onlooker_rush_factory": {"seed": 4242, "pocket": "factory", "stage": "_onlooker_rush"},
	"items": {"seed": 1, "stage": "_items"},
	# GRAFTING chunk C (docs/GRAFTING.md): strapped to a table with a loaded vat on its stand, as
	# Dr. Botsworth, ready to operate. `graft_back` is the same with the graft already done.
	"graft": {"seed": 4242, "stage": "_graft"},
	"graft_back": {"seed": 4242, "stage": "_graft_back"},
	# docs/SONOGRAPHER.md chunk B: make a noise, watch its neck, get pinged, and get away.
	"sono": {"seed": 4242, "stage": "_sono"},
	# 2026-09-19: both eye procedures at once -- a Hive strapped to one table with an empty vat on
	# it (Eyeball Extraction), and you strapped to another with a Hive's eye in its vat (Grafting).
	"eyes": {"seed": 4242, "stage": "_eyes"},
	# PANEL TESTBED (docs/PANEL_STYLE.md): a deep laceration on the table, a suture kit in hand.
	"panel": {"seed": 4242, "stage": "_panel"},
	# ARCADE (docs/ARCADE_SURGERY.md) phase 1: an amputation at the saw step, arcade saw switched on.
	"arcade_saw": {"seed": 4242, "stage": "_arcade_saw"},
	# ARCADE: a whole case with every arcade step that passed its checks switched on. `gw` is the
	# gunshot wound from the top (dose, dodge, whack + wrap), `am` the amputation (dose, squeeze,
	# saw, wrap) and `eyes` the two eye tables (steer, pry, nerve, grab, stitch).
	"arcade_gw": {"seed": 4242, "stage": "_arcade_gw"},
	"arcade_am": {"seed": 4242, "stage": "_arcade_am"},
	"arcade_eyes": {"seed": 4242, "stage": "_arcade_eyes"},
	# 2026-09-21 (docs/ARCADE_SURGERY.md 5.1): the Anesthetic Injection, already under way on a
	# gunshot wound. `--patient=seal` puts the seal on the table instead of Bob; `--stick` opens on
	# STICK! with the dose already drawn, so the aim is all there is to try.
	"sedate": {"seed": 4242, "stage": "_sedate"},
	# SYRINGE DRAW: the new syringe item -- three in hand, vials to load them from, some on the floor.
	"syringe": {"seed": 4242, "stage": "_syringe"},
	# SYRINGE DRAW (docs/ANESTHETIC_INJECTION_SPEC.md 9): standing in a corridor with a syringe and
	# a vial and a patient waiting on a table. Press E where you stand to load it, then carry it
	# over and operate: the step opens on STICK! instead of DRAW!. `--open` starts with the draw
	# already up (the smoke look uses it, since a screenshot cannot press E).
	"syringe_draw": {"seed": 4242, "stage": "_syringe_draw"},
	# 2026-09-21 (docs/ARCADE_SURGERY.md 5.2): DODGE!, a gunshot wound at the bullet step, sedated, and
	# you already operating. `--undersedated` makes the patient squirm; `--patient=seal` swaps in the seal.
	"dodge": {"seed": 4242, "stage": "_dodge"},
	# 2026-09-22 (docs/PACK_AND_WRAP_SPEC.md): WHACK! then WRAP!, a gunshot wound at the dressing step
	# with three tears already carried over from DODGE!, so bleeders are spurting the moment it opens.
	# `--clean` hands over no tears (the 3-bleeder floor); `--patient=seal` swaps in the seal.
	"pack_wrap": {"seed": 4242, "stage": "_pack_wrap"},
	# The same WRAP! on a stump: an amputation at the dressing step with a mediocre tourniquet, so a
	# good half of the cells are still bleeding and want two layers. `--goodtq` for a clean one.
	"wrap_stump": {"seed": 4242, "stage": "_wrap_stump"},
	# HOVER DROP (2026-09-22): open floor, four stacks in hand and two already hovering ahead.
	# Drop everything on the one spot and watch them glow, float and shove each other aside.
	"hover_drop": {"seed": 4242, "stage": "_hover_drop"},
	# 2026-09-22 (docs/SUTURE_SPEC.md): SUTURE!, a gunshot wound at the closing step, already packed
	# and dressed. `suture` opens on the deep laceration, `suture_eye` on the eye socket; the button
	# under the board swaps between them in play either way. `--solution` adds the debug overlay.
	"suture": {"seed": 4242, "stage": "_suture"},
	"suture_eye": {"seed": 4242, "stage": "_suture_eye"},
	# MIRRORS (2026-09-22): in front of the entrance's big full-length mirror, hands empty, looking
	# at your own reflection. `--dist=N` stands N metres off the glass (default 1.4).
	"mirror": {"seed": 4242, "stage": "_mirror"},
	# 2026-09-22 (playtest): a downed teammate on the floor by the OR. Carry them over your shoulder
	# to a table, stitch them up, and watch them get up: the carry pose must not come with them.
	"downed": {"seed": 4242, "stage": "_downed"},
	# DOORS (2026-09-22, the playtest's "monsters walk through doors"): a hinged door standing wide
	# open with a Hive parked behind the open leaf, hunting you. The leaf used to have no collider
	# once the door was open: everything, you included, walked straight through the door model.
	"doors": {"seed": 4242, "stage": "_doors"},
	# HIT FEEDBACK (2026-09-22): bone saws in hand, two Hives coming for you, and Dr. Botsworth
	# standing there to saw as well. A landed hit flashes its target red and knocks it back.
	"hit": {"seed": 4242, "stage": "_hit"},
	# PUPPET (2026-09-24): Puppet in slot 1 (Alt+1) and two Hives standing a few metres ahead,
	# facing away. Climb into one, look about, walk it around; your own body waits where you left it.
	# With -Count 2 every player has Puppet, and there is a Hive each.
	"puppet": {"seed": 4242, "stage": "_puppet", "join": "_puppet_join"},
	# TAB SHEET (2026-09-22): hit Tab. Both abilities at level 2, rocket boots on and a mixed
	# handful, so all three rows have something in them and the boots have an Unequip to press.
	"sheet": {"seed": 4242, "stage": "_sheet"},
	# MINIMAP (2026-09-22): an unhurried walk of the hospital with the fogged floor plan in the top
	# right. Nothing chasing you and nothing to lose, so the map is the only thing to look at.
	"minimap": {"seed": 4242, "stage": "_minimap"},
	# TRINKETS chunk B (docs/ITEMS_AND_ICONS.md): all six in hand, a Hive to tag and bonk, and a
	# teammate lying down for the defibrillator.
	"trinkets": {"seed": 4242, "stage": "_trinkets"},
	# GRAFTING (2026-09-22): standing at the lab wall's vat bench with empty hands and a loose eye
	# at your feet. The vats have always been ordinary bulky items; their bench's collider used to
	# bury them, so E never saw them at all.
	"vats": {"seed": 4242, "stage": "_vats"},
	# FLASHLIGHT POSE (2026-09-24): a teammate holding their torch, the beam coming out of it. With
	# `-Count 2` the onlooker window stands in front of the host, facing it, its own torch off; the host
	# runs a demo loop (lit and sweeping, then the blue scanner, then off) until anyone touches the
	# host window. Solo, you watch Dr. Botsworth do the same loop. `--shots` (onlooker) saves a run of
	# screenshots to tools/flashlight_shots/.
	"flashlight_pair": {"seed": 4242, "stage": "_flashlight_pair", "join": "_flashlight_pair_join"},
	# TUMBLE TUNING (2026-09-24): a stack of throwables in hand on open floor, some stairs and a
	# wall close by. Throw one at a shallow angle, a steep one and straight down, and time how long
	# each takes to stand up into its hover.
	"tumble": {"seed": 4242, "stage": "_tumble"},
	# SHOWERS (2026-09-24): standing beside a personnel shower with an empty hand. Press E.
	"showers": {"seed": 4242, "stage": "_showers"},
	# SKILL TREE (docs/SKILL_TREE.md): at the vein machine in Personnel, a step back from the hand
	# plate with a few skill points to spend. Press E. `--fresh` forgets every skill first.
	"skill_tree": {"seed": 4242, "stage": "_skill_tree"},
}


## The setup name asked for on the command line ("" for none).
static func requested() -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--setup="):
			return a.trim_prefix("--setup=").strip_edges()
	return ""


static func exists(setup: String) -> bool:
	return SETUPS.has(setup)


# ---------------------------------------------------------------------------
# co-op review windows (--setup-role / --setup-port / --setup-peers)

## The default port for a co-op review pair. Away from C.DEFAULT_PORT (7777, what a real host
## uses) and from tools/nettest_run.gd's 7790+, so a review pair and a nettest run can't collide.
## tools/review.ps1 adds the slot number, so wt-1 and wt-2 can each have a pair up at once.
const COOP_PORT := 7810

## This window's role in a co-op review set: "host", "join", or "" for the solo default.
static func role() -> String:
	return _arg("--setup-role=")


## The port the co-op set shares.
static func port() -> int:
	var v := _arg("--setup-port=")
	return int(v) if v.is_valid_int() else COOP_PORT


## Host only: how many joining windows to wait for before beginning the shift.
static func peers() -> int:
	var v := _arg("--setup-peers=")
	return int(v) if v.is_valid_int() else 0


## The host window drops this file once its server is listening; the joining windows wait for it.
## It lives in the slot's .godot folder beside the review logs, so tools/review.ps1 can clear a
## stale one before it launches the pair.
static func host_lock_path(p: int) -> String:
	return ProjectSettings.globalize_path("res://.godot/review-host-%d.lock" % p)


static func mark_hosting(p: int) -> void:
	var f := FileAccess.open(host_lock_path(p), FileAccess.WRITE)
	if f != null:
		f.store_line(str(Time.get_unix_time_from_system()))
		f.close()


static func host_listening(p: int) -> bool:
	return FileAccess.file_exists(host_lock_path(p))


static func _arg(prefix: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with(prefix):
			return a.trim_prefix(prefix).strip_edges()
	return ""


static func names() -> Array:
	return SETUPS.keys()


static func seed_of(setup: String) -> int:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--seed=") and a.trim_prefix("--seed=").is_valid_int():
			return int(a.trim_prefix("--seed="))
	return int((SETUPS.get(setup, {}) as Dictionary).get("seed", DEFAULT_SEED))


## Run the setup's stage function (the shift has begun and the world has settled).
## POCKETS 2 phase 2: anything a setup needs done BEFORE the session generates. A setup asks for a
## pocket space with `"pocket": "natatorium"` in its entry; the kind has to be forced before the map
## is rolled, so main.gd calls this just before it starts the session. Harmless for every other setup.
static func before_session(setup: String) -> void:
	var kind := String((SETUPS.get(setup, {}) as Dictionary).get("pocket", ""))
	if kind != "":
		preload("res://scripts/level/pockets/pocket_plan.gd").force_kind = kind


static func stage(setup: String, game: Game) -> void:
	if not exists(setup):
		return
	print("[review] setup '%s' (seed %d)" % [setup, seed_of(setup)])
	await Callable(ReviewSetups, String(SETUPS[setup].stage)).call(game)
	for n in game.get_tree().get_nodes_in_group("review_bar"):
		n.staged()


# ---------------------------------------------------------------------------
# helpers for setups

## Stand the local player at `pos` looking at `at`.
static func place(game: Game, pos: Vector3, at: Vector3) -> void:
	var p = game.local_player()
	p.teleport(pos)
	var d := at - (pos + Vector3.UP * 1.6)
	p._yaw = atan2(-d.x, -d.z)
	p.rotation.y = p._yaw
	p._pitch = clampf(atan2(d.y, Vector2(d.x, d.z).length()), -1.0, 1.0)
	p.head.rotation.x = p._pitch


## A joining co-op review window: stand the local player beside `other` (another player node), a
## step to its right and half a step behind, looking past its shoulder at whatever it is facing.
## The default "where do the extra players stand" -- no setup has to say anything for an onlooker
## to land somewhere useful, because every setup already points the host at the thing it staged.
static func place_beside(game: Game, other) -> void:
	var yaw: float = other.rotation.y
	var forward := Vector3(-sin(yaw), 0.0, -cos(yaw))
	var right := Vector3(cos(yaw), 0.0, -sin(yaw))
	var pos: Vector3 = other.global_position + right * 1.1 - forward * 0.6
	place(game, pos, other.global_position + forward * 2.5 + Vector3.UP * 1.2)


## A joining co-op review window finds its spot: the setup's own `join` function if it has one
## (called with the host's player), else beside the host (place_beside).
static func place_joiner(setup: String, game: Game, host_player) -> void:
	var f := String((SETUPS.get(setup, {}) as Dictionary).get("join", ""))
	if f != "":
		await Callable(ReviewSetups, f).call(game, host_player)
	else:
		place_beside(game, host_player)


## The horizontal direction (of the four axes) from `from` with the most room, so a spot beside a wall
## faces into the room.
static func open_direction(game: Game, from: Vector3, reach: float) -> Vector3:
	var space: PhysicsDirectSpaceState3D = game.get_world_3d().direct_space_state
	var best := Vector3.BACK
	var best_d := -1.0
	for d in [Vector3.BACK, Vector3.FORWARD, Vector3.LEFT, Vector3.RIGHT]:
		var q := PhysicsRayQueryParameters3D.create(from, from + d * reach)
		q.collision_mask = C.L_WORLD
		var hit := space.intersect_ray(q)
		var dist: float = reach if hit.is_empty() else from.distance_to(hit.position)
		if dist > best_d:
			best_d = dist
			best = d
	return best


## Empty the local player's hands.
static func clear_hands(game: Game) -> void:
	var p = game.local_player()
	for i in p.slots.size():
		p.slots[i] = Player.empty_slot()


## Put a stack in the local player's hands. `extra` keys go onto the stack (`bt` a spoil clock, `used`,
## `x` an owner name...). Returns the slot it landed in (-1 without room).
static func give(game: Game, kind: String, count := 1, value := 0, extra := {}) -> int:
	var p = game.local_player()
	var i: int = p.take_into(kind, count, value)
	if i >= 0:
		for k in extra.keys():
			p.slots[i][k] = extra[k]
	return i


## Both abilities (Puppet and Echo) at the given level.
static func give_abilities(game: Game, level := 2) -> void:
	var p = game.local_player()
	game.abilities.set_level(p.peer_id, "echo", level)
	game.abilities.set_level(p.peer_id, "puppet", level)
	# No "New ability" cards in the way: they are for a first play.
	var hud = game.get_tree().get_first_node_in_group("hud")
	if hud != null:
		hud._card_seen["echo"] = true
		hud._card_seen["puppet"] = true


## Drop an item on the floor at `pos` (host).
static func floor_item(game: Game, kind: String, pos: Vector3, count := 1, value := 0) -> void:
	var it = game._spawn_item(kind, count, Transform3D(Basis(), pos + Vector3.UP * 0.3), WorldItem.State.LOOSE)
	it.value = value


## HOVER DROP: let a stack fall at `pos` the way a dropped one does, so it settles into its hover
## and takes its own spot. (floor_item, above, sets things down flat and still instead.)
static func drop_at(game: Game, kind: String, pos: Vector3, count := 1, value := 0) -> void:
	var xf := Transform3D(Basis(), pos + Vector3.UP * 0.9)
	var it = game._spawn_item(kind, count, xf, WorldItem.State.LOOSE)
	it.value = value
	it.toss(xf, Vector3.ZERO)


# ---------------------------------------------------------------------------
# the setups

## ICONS (docs/ITEMS_AND_ICONS.md chunk C): in the operating room facing the table (patient, monitors,
## lamp all in view), hands holding a stack, a body part that is starting to spoil, a used-up trinket and
## a small loot item, with a heart monitor and a defibrillator on the floor in front to pick up (bulky,
## wide slot), and both abilities. Switch slots, hold Alt, pick things up; the database is in the
## break room, a walk away.
static func _icons(game: Game) -> void:
	var t: Vector3 = game.table_pos()
	place(game, t + Vector3(0.6, 0, 3.4), t + Vector3(0, 1.0, 0))
	clear_hands(game)
	give(game, "anesthetic", 3)
	give(game, "eye_hive", 1, 150, {"bt": game.world_time - 25.0})
	give(game, "laptop", 1, 120, {"used": true})
	give(game, "gold_watch", 1, 90)
	give_abilities(game)
	game.local_player().selected = 0
	floor_item(game, "heart_monitor", t + Vector3(0.1, 0, 2.3), 1, 200)
	floor_item(game, "defibrillator", t + Vector3(1.1, 0, 2.3), 1, 300)


## TAB SHEET (2026-09-22): open floor by the OR, hands part full, both abilities at level 2 and
## rocket boots already on. Press Tab: three rows of four, hover an ability for its real numbers,
## press Unequip and watch the boots land at your feet (then walk over them to put them back on).
static func _sheet(game: Game) -> void:
	var t: Vector3 = game.table_pos()
	place(game, t + Vector3(0.6, 0, 4.0), t + Vector3(0, 1.0, 0))
	clear_hands(game)
	give(game, "anesthetic", 3)
	give(game, "gold_watch", 1, 90)
	give_abilities(game, 2)
	game.local_player().put_on_boots()
	game.local_player().selected = 0


## ITEMS (docs/ITEMS_AND_ICONS.md chunk A): a normal shift; you start in the room with the most loot near
## it, an EpiPen in hand and the other trinkets (desk phone, laptop, pulse oximeter, reflex hammer,
## defibrillator) laid out on the floor in front of you. The log has the shift's loot count per kind.
## Walk the wings and see what turns up.
static func _items(game: Game) -> void:
	var loot: Array = []
	var counts := {}
	for it in game.world_items.values():
		if Items.is_loot(it.kind) and it.state == WorldItem.State.LOOSE:
			loot.append(it)
			counts[it.kind] = int(counts.get(it.kind, 0)) + 1
	print("[review] items: %d loot stacks lying out, by kind: %s" % [loot.size(), str(counts)])
	# The loose loot with the most other loot within 14 m.
	var best: Node3D = null
	var best_n := -1
	for it in loot:
		var n := 0
		for o in loot:
			if it.global_position.distance_to(o.global_position) < 14.0:
				n += 1
		if n > best_n:
			best_n = n
			best = it
	var base: Vector3 = game.clock_pos() if best == null else game._floor_at(best.global_position)
	var out := open_direction(game, base + Vector3.UP * 1.2, 3.0)
	var side := out.cross(Vector3.UP).normalized()
	place(game, base + out * 0.8, base + out * 3.0 + Vector3(0, 0.5, 0))
	clear_hands(game)
	give(game, "epipen", 1, 60)
	game.local_player().selected = 0
	var row := ["desk_phone", "laptop", "pulse_oximeter", "reflex_hammer", "defibrillator"]
	for i in row.size():
		floor_item(game, row[i], base + out * 2.0 + side * (float(i) - 2.0) * 0.55, 1, 100)
	print("[review] items: standing among %d loot stacks; trinkets on the floor ahead, an EpiPen in hand" % best_n)



## ARCADE: switch on every arcade step whose self-test passed. The morning report says which those
## are; the dev panel's "Arcade surgery" checkboxes (F1) turn any of them back off.
static func arcade_all_on() -> void:
	for key in Procedures.ARCADE_ENABLED.keys():
		var k := String(key)
		if ResourceLoader.exists(String(Procedures.ARCADE_SCRIPTS.get(k, Procedures.ARCADE_SCRIPTS.get(k.get_slice(":", 0), "")))):
			Procedures.ARCADE_ENABLED[k] = true


## ARCADE GW: a gunshot wound on the table from the first step, every arcade step on, and all three
## tools in hand. The injection, then DODGE! then WHACK! and WRAP!, and the mistakes in each one follow you
## into the next: the tract you tore shows up as bleeders, and how you packed shows up as the cells
## that soak through.
static func _arcade_gw(game: Game) -> void:
	arcade_all_on()
	var table: int = game.free_patient_table()
	if table < 0:
		table = int(game.patient_tables[0].index) if not game.patient_tables.is_empty() else 0
	game.add_case({"patient_id": "bob", "ailment_id": "gunshot", "table": table, "state": "on_table"})
	var t: Vector3 = game.table_position(table)
	place(game, t + Vector3(0.0, 0, 1.15), t + Vector3(0, 1.05, 0))
	clear_hands(game)
	give(game, "anesthetic", 3)
	give(game, "forceps", 1)
	give(game, "gauze", 3)
	game.local_player().selected = 0
	game.stock_storage("anesthetic", 3)
	game.stock_storage("gauze", 3)
	print("[review] arcade_gw: gunshot on table %d, every arcade step ON" % table)


## ARCADE AM: an amputation from the first step, every arcade step on, all four tools in hand. The
## injection, then SQUEEZE! then SAW! then WRAP!. Put a bad tourniquet on and the saw's artery will blind you,
## and the stump will bleed through the dressing.
static func _arcade_am(game: Game) -> void:
	arcade_all_on()
	var table: int = game.free_patient_table()
	if table < 0:
		table = int(game.patient_tables[0].index) if not game.patient_tables.is_empty() else 0
	game.add_case({"patient_id": "seal", "ailment_id": "amputation", "table": table, "state": "on_table"})
	var t: Vector3 = game.table_position(table)
	place(game, t + Vector3(0.0, 0, 1.15), t + Vector3(0, 1.05, 0))
	clear_hands(game)
	give(game, "anesthetic", 3)
	give(game, "tourniquet", 1)
	give(game, "bone_saw", 1)
	give(game, "gauze", 4)
	game.local_player().selected = 0
	game.stock_storage("gauze", 4)
	print("[review] arcade_am: amputation on table %d, every arcade step ON" % table)


## ARCADE EYES: the same two tables as the `eyes` setup -- a strapped Hive with its vat, and you
## strapped to the other with a Hive eye waiting -- but with every arcade eye step switched on.
## STEER! then PRY! then CUT THE RIGHT ONE! then GRAB!, and on yours GRAB! then STITCH!.
static func _arcade_eyes(game: Game) -> void:
	arcade_all_on()
	await _eyes(game)
	print("[review] arcade_eyes: both eye tables, every arcade eye step ON")


## SEDATE (docs/ARCADE_SURGERY.md 5.1): a gunshot wound on the table at the sedation step, and you
## already operating it -- the panel is up on the DRAW stage. You hold the anaesthetic, and there is
## a tourniquet in your other hand so the tourniquet button on the vein stage works (once: it spends
## it). `--patient=seal` after `--setup=sedate` puts the seal on the table; its band sits lower down
## the barrel because it weighs more. `--stick` skips DRAW! and FLICK! and opens straight on STICK!,
## dose drawn and no bubbles, for when only the aim is being looked at. E steps back from the table,
## E again starts over where you were.
## SYRINGE DRAW: syringes in hand with the fluid to load them from, plus a few lying loose and a
## stack on the shelf. For looking at the new item -- the model in the hand and on the floor, the
## icon in the bar, and what the terminal says about it.
static func _syringe(game: Game) -> void:
	clear_hands(game)
	give(game, "syringe", 3)
	give(game, "anesthetic", 3)
	game.local_player().selected = 0
	game.stock_storage("syringe", 3)
	var here: Vector3 = game.local_player().global_position
	floor_item(game, "syringe", here + Vector3(1.0, 0.0, -1.4), 2)
	floor_item(game, "syringe", here + Vector3(-0.9, 0.0, -1.6), 1)
	floor_item(game, "anesthetic", here + Vector3(0.1, 0.0, -1.9), 3)


## SYRINGE DRAW: the whole trip. A patient waits on a table; you stand a few paces off it with a
## syringe selected and a vial in the other hand. E loads the syringe where you stand (the first
## minigame that happens outside the OR), and walking it over opens the sedate step on STICK!.
static func _syringe_draw(game: Game) -> void:
	var table: int = game.free_patient_table()
	if table < 0:
		table = int(game.patient_tables[0].index) if not game.patient_tables.is_empty() else 0
	game.add_case({"patient_id": "bob", "ailment_id": "gunshot", "table": table, "state": "on_table"})
	var t: Vector3 = game.table_position(table)
	# A few paces back from the table, facing it: there is nothing to aim at from here, which is
	# exactly the state the draw is offered in.
	place(game, t + Vector3(0.0, 0.0, 3.2), t + Vector3(0.0, 1.05, 0.0))
	clear_hands(game)
	give(game, "syringe", 3)
	give(game, "anesthetic", 2)
	give(game, "tourniquet", 1)
	game.local_player().selected = 0
	game.stock_storage("syringe", 3)
	var tree := game.get_tree()
	for i in 6:
		await tree.physics_frame
	if "--open" in OS.get_cmdline_user_args() and game.syringe_stations != null:
		game.syringe_stations.hand_open(game.local_player())


static func _sedate(game: Game) -> void:
	var pid := "bob"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--patient="):
			pid = a.trim_prefix("--patient=").strip_edges()
	if not Procedures.PATIENTS.has(pid) or Procedures.is_monster(pid):
		pid = "bob"
	var table: int = game.free_patient_table()
	if table < 0:
		table = int(game.patient_tables[0].index) if not game.patient_tables.is_empty() else 0
	game.add_case({"patient_id": pid, "ailment_id": "gunshot", "table": table, "state": "on_table"})
	var t: Vector3 = game.table_position(table)
	place(game, t + Vector3(0.0, 0, 1.15), t + Vector3(0, 1.05, 0))
	clear_hands(game)
	give(game, "anesthetic", 3)
	give(game, "tourniquet", 1)
	game.local_player().selected = 0
	game.stock_storage("anesthetic", 3)
	var tree := game.get_tree()
	for i in 6:
		await tree.physics_frame
	var sys = game.surgery_for_table(table)
	if sys != null:
		var why: String = sys.can_begin(game.local_player())
		if why == "":
			sys.begin(game.local_player())
		else:
			print("[review] sedate: could not start operating: %s" % why)
	print("[review] sedate: %s on table %d at the sedation step, a tourniquet in hand" % [pid, table])


## DODGE (docs/ARCADE_SURGERY.md 5.2): a gunshot wound on the table at step 2, the bullet, already
## sedated, and you operating it with the forceps in hand: the DODGE! card is up. Space starts it and
## flaps. `--undersedated` puts the patient in at sedation 0.3 instead, so the walls squirm every so
## often (the first within 4-10 s of flying). `--patient=seal` puts the seal on the table. Gauze is in
## the other hand for the next step (WHACK! puts a bleeder on every wall you tore). E steps back.
static func _dodge(game: Game) -> void:
	var pid := "bob"
	var sed := 1.0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--patient="):
			pid = a.trim_prefix("--patient=").strip_edges()
		if a == "--undersedated":
			sed = 0.3
	if not Procedures.PATIENTS.has(pid) or Procedures.is_monster(pid):
		pid = "bob"
	var table: int = game.free_patient_table()
	if table < 0:
		table = int(game.patient_tables[0].index) if not game.patient_tables.is_empty() else 0
	game.add_case({"patient_id": pid, "ailment_id": "gunshot", "table": table, "state": "on_table",
		"step_index": 1, "flags": {"sedation": sed}})
	var t: Vector3 = game.table_position(table)
	place(game, t + Vector3(0.0, 0, 1.15), t + Vector3(0, 1.05, 0))
	clear_hands(game)
	give(game, "forceps", 1)
	give(game, "gauze", 3)
	game.local_player().selected = 0
	game.stock_storage("gauze", 3)
	var tree := game.get_tree()
	for i in 6:
		await tree.physics_frame
	var sys = game.surgery_for_table(table)
	if sys != null:
		var why: String = sys.can_begin(game.local_player())
		if why == "":
			sys.begin(game.local_player())
		else:
			print("[review] dodge: could not start operating: %s" % why)
	print("[review] dodge: %s on table %d at the bullet step, sedation %.1f" % [pid, table, sed])


## PACK & WRAP (docs/PACK_AND_WRAP_SPEC.md): a gunshot wound on the table at step 3, the dressing,
## with the bullet already out and THREE TEARS carried over from DODGE! -- so WHACK! opens with five
## bleeders on the tract and a couple of them already spurting. Hold Space on a spurting one until the
## ring closes to pack it; pack them all (or bleed him out) and it hands straight over to WRAP!, where
## WASD steers the gauze roll. `--clean` hands over no tears at all (the three-bleeder floor), so the
## wrap comes up nearly dry; `--patient=seal` puts the seal on the table. E steps back.
static func _pack_wrap(game: Game) -> void:
	arcade_all_on()
	var pid := "bob"
	var tears: Array = [0.24, 0.53, 0.79]
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--patient="):
			pid = a.trim_prefix("--patient=").strip_edges()
		if a == "--clean":
			tears = []
	if not Procedures.PATIENTS.has(pid) or Procedures.is_monster(pid):
		pid = "bob"
	var table: int = game.free_patient_table()
	if table < 0:
		table = int(game.patient_tables[0].index) if not game.patient_tables.is_empty() else 0
	game.add_case({"patient_id": pid, "ailment_id": "gunshot", "table": table, "state": "on_table",
		"step_index": 2, "flags": {"sedation": 1.0, "bullet_removed": true, "tears": tears}})
	var t: Vector3 = game.table_position(table)
	place(game, t + Vector3(0.0, 0, 1.15), t + Vector3(0, 1.05, 0))
	clear_hands(game)
	give(game, "gauze", 3)
	game.local_player().selected = 0
	game.stock_storage("gauze", 3)
	var tree := game.get_tree()
	for i in 6:
		await tree.physics_frame
	var sys = game.surgery_for_table(table)
	if sys != null:
		var why: String = sys.can_begin(game.local_player())
		if why == "":
			sys.begin(game.local_player())
		else:
			print("[review] pack_wrap: could not start operating: %s" % why)
	print("[review] pack_wrap: %s on table %d at the dressing step, %d tears carried over" % [pid, table, tears.size()])


## THE SAME WRAP! ON A STUMP (docs/PACK_AND_WRAP_SPEC.md 3): an amputation at the dressing step, limb
## already off, with a mediocre 0.45 tourniquet -- so about half the stump's cells are still bleeding
## and want two layers instead of one. `--goodtq` puts a clean 0.95 tourniquet on it instead.
static func _wrap_stump(game: Game) -> void:
	arcade_all_on()
	var tq := 0.45
	for a in OS.get_cmdline_user_args():
		if a == "--goodtq":
			tq = 0.95
	var table: int = game.free_patient_table()
	if table < 0:
		table = int(game.patient_tables[0].index) if not game.patient_tables.is_empty() else 0
	game.add_case({"patient_id": "seal", "ailment_id": "amputation", "table": table, "state": "on_table",
		"step_index": 3, "flags": {"sedation": 1.0, "tourniquet": tq, "amputated": true}})
	var t: Vector3 = game.table_position(table)
	place(game, t + Vector3(0.0, 0, 1.15), t + Vector3(0, 1.05, 0))
	clear_hands(game)
	give(game, "gauze", 4)
	game.local_player().selected = 0
	game.stock_storage("gauze", 4)
	var tree := game.get_tree()
	for i in 6:
		await tree.physics_frame
	var sys = game.surgery_for_table(table)
	if sys != null:
		var why: String = sys.can_begin(game.local_player())
		if why == "":
			sys.begin(game.local_player())
		else:
			print("[review] wrap_stump: could not start operating: %s" % why)
	print("[review] wrap_stump: amputation on table %d at the dressing step, tourniquet %.2f" % [table, tq])


## SUTURE (docs/SUTURE_SPEC.md): a gunshot wound on the table at step 4, the closing, with the bullet
## out and the wound already packed and dressed -- so the SUTURE! card is up the moment you look at
## it. Press on dot 1 and HOLD the left mouse button, then drag: the needle walks one cell at a time
## through every open cell, taking the numbered dots in order and never crossing itself. Pulling back
## along the thread undoes stitches and costs him. The button under the board swaps to the eye socket
## and back. `--patient=seal` swaps the patient; `--solution` adds the debug overlay (the dashed green
## solution, New puzzle and Clear thread). E steps back.
static func _suture(game: Game) -> void:
	await _suture_case(game, "laceration")


## The same step opened on the EYE SOCKET instead: 6x6 with the centre 2x2 blocked by an eyeball and
## a dashed DO NOT STITCH fence over it, 32 cells to thread around. The button under the board swaps
## back to the laceration.
static func _suture_eye(game: Game) -> void:
	await _suture_case(game, "eye")


static func _suture_case(game: Game, mode: String) -> void:
	arcade_all_on()
	load("res://scripts/surgery/arcade/suture_arcade.gd").force_mode = mode
	var pid := "bob"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--patient="):
			pid = a.trim_prefix("--patient=").strip_edges()
	if not Procedures.PATIENTS.has(pid) or Procedures.is_monster(pid):
		pid = "bob"
	var table: int = game.free_patient_table()
	if table < 0:
		table = int(game.patient_tables[0].index) if not game.patient_tables.is_empty() else 0
	game.add_case({"patient_id": pid, "ailment_id": "gunshot", "table": table, "state": "on_table",
		"step_index": 3, "flags": {"sedation": 1.0, "bullet_removed": true, "dressed": true,
		"pack_quality": 0.8}})
	var t: Vector3 = game.table_position(table)
	place(game, t + Vector3(0.0, 0, 1.15), t + Vector3(0, 1.05, 0))
	clear_hands(game)
	give(game, "suture_kit", 2)
	game.local_player().selected = 0
	game.stock_storage("suture_kit", 2)
	var tree := game.get_tree()
	for i in 6:
		await tree.physics_frame
	var sys = game.surgery_for_table(table)
	if sys != null:
		var why: String = sys.can_begin(game.local_player())
		if why == "":
			sys.begin(game.local_player())
		else:
			print("[review] suture: could not start operating: %s" % why)
	print("[review] suture: %s on table %d at the closing step, %s variant" % [pid, table, mode])


## ARCADE SAW (docs/ARCADE_SURGERY.md 5.5): Bob is on the table sedated with a tourniquet already
## on, at the saw step, and the arcade saw is switched on for this session. The bone saw is in your
## hand: aim at the table, press E, and alternate A and D to the pendulum. The tourniquet is a
## mediocre 0.55, so the artery WILL spray when the blade finds it and you will lose the pendulum.
## Turn it off again from the dev panel's "Arcade surgery" checkboxes (F1).
static func _arcade_saw(game: Game) -> void:
	Procedures.ARCADE_ENABLED["saw"] = true
	var table: int = game.free_patient_table()
	if table < 0:
		table = int(game.patient_tables[0].index) if not game.patient_tables.is_empty() else 0
	game.add_case({"patient_id": "bob", "ailment_id": "amputation", "table": table,
		"state": "on_table", "step_index": 2, "flags": {"sedation": 1.0, "tourniquet": 0.55}})
	var t: Vector3 = game.table_position(table)
	place(game, t + Vector3(0.0, 0, 1.15), t + Vector3(0, 1.05, 0))
	clear_hands(game)
	give(game, "bone_saw", 1)
	give(game, "gauze", 2)
	game.local_player().selected = 0
	print("[review] arcade_saw: amputation at the saw step on table %d, arcade saw ON" % table)


## PANEL (docs/PANEL_STYLE.md): Bob is on the first table with a deep laceration, already sedated,
## and you are standing over him with a suture kit in hand. Look at the wound from standing height
## first -- there should be nothing on him but the cut -- then aim at the table and press E: the
## panel pops in over the wound and you stitch on it. Press and hold left mouse where the needle
## goes in, drag across the gash, let go. E again steps back and the panel goes with you.
static func _panel(game: Game) -> void:
	var table: int = game.free_patient_table()
	if table < 0:
		table = int(game.patient_tables[0].index) if not game.patient_tables.is_empty() else 0
	game.add_case({"patient_id": "bob", "ailment_id": "laceration", "table": table, "state": "on_table"})
	var t: Vector3 = game.table_position(table)
	place(game, t + Vector3(0.0, 0, 1.15), t + Vector3(0, 1.05, 0))
	clear_hands(game)
	give(game, "suture_kit", 2)
	game.local_player().selected = 0
	game.stock_storage("suture_kit", 2)
	print("[review] panel: a deep laceration on table %d, suture kits in hand" % table)
## TRINKETS (docs/ITEMS_AND_ICONS.md, chunk B): the open floor beyond the OR with all six trinkets
## to hand. Two are in your hands (the pulse oximeter and the reflex hammer, the two reusable ones)
## and the other four lie in a row in front of you, which leaves the two free slots the bulky
## defibrillator needs. A Hive stands a few metres away, calm for the first few seconds, to shove,
## tag, bonk and run from; a teammate (a dev dummy, so it works solo; with `-Count 2` the other
## window is a real surgeon) lies downed beside you for the defibrillator. Nothing else is going
## on: no phone call, no patient, no other monsters.
static func _trinkets(game: Game) -> void:
	var tree := game.get_tree()
	var p = game.local_player()
	game.set_dev_tools(true, p)
	game.loop._end_call()
	game.loop.first_called = true
	game.loop.extra_done = true
	game.dev.request("no_game_over", {"on": true})
	game.dev.request("monsters_off", {"on": true})   # only the one staged below
	game.dev.request("clear_patient")
	# Standing in the open beyond the OR table, looking away from it down the longest clear line.
	var t: Vector3 = game.table_pos()
	var base: Vector3 = game._floor_at(t + Vector3(0.0, 0.0, 4.2))
	var out := open_direction(game, base + Vector3.UP * 1.2, 7.0)
	var side := out.cross(Vector3.UP).normalized()
	# Look low enough that the four on the floor are in shot from the first frame (they used to sit
	# under the hands), and high enough that the Hive further out is still in view.
	place(game, base, base + out * 4.0 + Vector3(0, 0.05, 0))
	clear_hands(game)
	give(game, "pulse_oximeter", 1, 40)
	give(game, "reflex_hammer", 1, 20)
	p.selected = 0
	p.flashlight_on = true
	var row := ["desk_phone", "laptop", "epipen", "defibrillator"]
	var value := [20, 80, 30, 120]
	for i in row.size():
		floor_item(game, row[i], base + out * 2.4 + side * (float(i) - 1.5) * 0.7, 1, value[i])
	await tree.physics_frame
	# A Hive, out in front. It starts idle and, once it spots you, it will come -- but `calm` means
	# it cannot land a hit for the first half minute, so you get to look at the phone and the laptop
	# before it can knock anything out of your hands. After that it is an ordinary Hive.
	var m = game._add_monster("hive", game._floor_at(base + out * 7.0 - side * 0.6))
	if m != null:
		m.calm = 35.0
		if m.brain != null and "home" in m.brain:
			m.brain.home = m.global_position
			m.brain.timer = 35.0
			m.mode = Monster.Mode.IDLE
	# A teammate on the floor beside you, waiting for the paddles. A dummy, not a bot: it has no
	# brain of its own, so it stays exactly where it is put and stays down.
	var bot_id: int = game.dev.spawn_bot("dummy", p, "Nurse Pratt", game._floor_at(base + out * 3.4 + side * 1.9))
	var downed := false
	for i in 10:
		await tree.physics_frame
	for q in game.players.values():
		if q != null and is_instance_valid(q) and String(q.player_name) == "Nurse Pratt":
			q.bot_move = Vector2.ZERO
			game.knock_down_player(q, "dev:setup")
			downed = q.downed
	print("[review] trinkets: hive=%s downed mate=%s (bot %d)" % [str(m != null), str(downed), bot_id])
	game.say("Pulse oximeter and reflex hammer in hand; phone, laptop, EpiPen and defibrillator on the floor. The Hive is yours to experiment on.", 10.0)


## GRAFT (docs/GRAFTING.md, chunk C): you are strapped to a free OR table with a vat holding a
## Hive's eyeball on its stand, and you are already Dr. Botsworth, standing beside you with the
## scalpel, the eye spoon and the suture kit. Aim at the table and press E for each of the four
## steps (hold the right tool: 1 scalpel, 2 eye spoon, 3 forceps, 4 suture kit); F1 -> "Back to my
## own body" puts you back in your own head, where you hold E to get up and
## can go and look in the Personnel mirror.
static func _graft(game: Game) -> void:
	await _graft_stage(game, "eye_hive", "", false)


## GRAFT BACK: the same table and stand, but the graft has already been done -- you have the Hive
## eyeball, and your own eyeball is the one floating in the vat, waiting to go back in.
static func _graft_back(game: Game) -> void:
	await _graft_stage(game, "eye_surgeon", String(game.local_player().player_name), true)


## SONOGRAPHER (docs/SONOGRAPHER.md chunk B): a quiet corridor, a Sonographer wandering about 12 m
## down it and nothing else in the shift. Your hands are full of things to throw, and a row more on
## the floor behind you. Throw one: the noise pulls it, its neck starts to grow (the neck IS the
## suspicion meter), and a few noises fill it -- then the charge, the violet fan out of the wand,
## your screen full of ultrasound grain and a soft squeal while everything goes muffled, and it
## comes for you. Get behind a corner, stop moving (crouch is silent) and it loses you.
static func _sono(game: Game) -> void:
	var tree := game.get_tree()
	var p = game.local_player()
	game.set_dev_tools(true, p)
	# Nothing else going on: no phone call, no patient, no other monsters.
	game.loop._end_call()
	game.loop.first_called = true
	game.loop.extra_done = true
	game.dev.request("no_game_over", {"on": true})
	# A long clear run of corridor to stand in, with the monster at the far end of it.
	var base: Vector3 = game.clock_pos()
	var spawns: Array = game.level_info.get("monster_spawns", [])
	if not spawns.is_empty():
		base = spawns[0]
	var out := open_direction(game, base + Vector3.UP * 1.2, 16.0)
	place(game, game._floor_at(base), game._floor_at(base) + out * 6.0 + Vector3.UP * 1.6)
	# Only one monster in the shift, and it is this one, down the corridor facing away.
	game._clear_monsters()
	await tree.physics_frame
	var at: Vector3 = game._floor_at(base + out * 12.0)
	var sono = game._add_monster("sonographer", at)
	sono.rotation.y = atan2(-out.x, -out.z)   # models face -Z: this has it facing away down the corridor
	# Things to throw: each one makes a noise where it lands, and pulls it there.
	clear_hands(game)
	give(game, "placebo_pills", 3)
	give(game, "gold_watch", 1, 90)
	game.local_player().selected = 0
	var side := out.cross(Vector3.UP).normalized()
	for i in 4:
		floor_item(game, "desk_phone", game._floor_at(base - out * 1.6) + side * (float(i) - 1.5) * 0.6, 1, 60)
	p.set_flashlight(true)
	await tree.physics_frame
	print("[review] sono: a Sonographer %.0f m down the corridor; throw something, watch its neck" % base.distance_to(at))
	game.say("Throw something (right click) and watch its neck. When it fills, it pings you.", 9.0)


## DOORS: a room door standing wide open, a Hive on the far face of the open leaf, coming for you.
## The leaf is the thing to test: walk into it, and watch the Hive go round it instead of through it.
static func _doors(game: Game) -> void:
	var tree := game.get_tree()
	var p = game.local_player()
	game.set_dev_tools(true, p)
	# Nothing else going on: no phone call, no patient, no other monsters, and you cannot lose.
	game.loop._end_call()
	game.loop.first_called = true
	game.loop.extra_done = true
	game.dev.request("no_game_over", {"on": true})
	game.dev.request("god", {"on": true})
	game._clear_monsters()
	await tree.physics_frame
	# A hinged door with room on both sides, nearest the clock.
	var best: Node = null
	var best_d := INF
	for d in game.doors.doors.values():
		if d.kind != "hinged" or bool(d.data.get("base", false)) or d.max_out < 80.0:
			continue
		if not game._point_is_clear(d.global_position + d.normal * 2.4) \
				or not game._point_is_clear(d.global_position - d.normal * 2.4):
			continue
		var dist: float = d.global_position.distance_to(game.clock_pos())
		if dist < best_d:
			best_d = dist
			best = d
	if best == null:
		push_warning("[review] doors setup: no hinged door with room on both sides")
		return
	# Wide open, the way it is left after someone walks through it.
	var open_amount := 1.0 if best.max_out >= 80.0 else -1.0
	best.snap_to(open_amount)
	game.doors._moving.erase(best.door_id)
	await tree.physics_frame
	var leaf: Node3D = best.leaf_bodies[0]
	var leaf_mid: Vector3 = leaf.global_transform * Vector3(float(best.leaf_len[0]) * 0.6, 0.0, 0.0)
	leaf_mid.y = best.global_position.y
	# The leaf stands out of the wall into the room, so the room's near-wall strip has a side each:
	# you back in the room looking at it, the Hive on the far side of it, the leaf between you.
	var out: Vector3 = (leaf_mid - best.global_position)
	out.y = 0.0
	out = out.normalized()                          # into the room, along the open leaf
	var hinge_side: Vector3 = (leaf.global_position - best.global_position)
	hinge_side.y = 0.0
	hinge_side = hinge_side.normalized()            # along the doorway, toward the leaf's hinge
	var you: Vector3 = game._floor_at(best.global_position + out * 4.0 - hinge_side * 1.5)
	if not game._point_is_clear(you + Vector3.UP * 1.0):
		you = game._floor_at(best.global_position + out * 2.6)
	place(game, you, leaf_mid + Vector3.UP * 1.1)
	var hive_at: Vector3 = game._floor_at(best.global_position + hinge_side * 2.2 + out * 0.9)
	if not game._point_is_clear(hive_at + Vector3.UP * 1.0):
		hive_at = game._floor_at(best.global_position + hinge_side * 2.2 + out * 2.0)
	var hive = game._add_monster("hive", hive_at)
	hive.brain._hunt(you)
	p.set_flashlight(true)
	await tree.physics_frame
	print("[review] doors: door %s wide open (%.2f), a Hive behind its leaf at %s" % [best.door_id, best.amount, str(hive.global_position.snappedf(0.1))])
	game.say("The open door is between you and the Hive. Walk into the leaf; watch it come round, not through.", 10.0)


## HIT FEEDBACK: a clear stretch of floor with three bone saws in your hands, two Hives walking in
## at you, and Dr. Botsworth standing beside you as something to swing at that is a PLAYER, not a
## monster. Hit either and it should wash red for a moment and get knocked a step back -- and the
## Hive should keep coming at you rather than going down dazed, which is what a shove (Q) does.
## Swing a Hive and then Q it back to back to see the difference. You cannot be hurt.
static func _hit(game: Game) -> void:
	var tree := game.get_tree()
	var p = game.local_player()
	game.set_dev_tools(true, p)
	# Nothing else going on, and nothing that can end the review early.
	game.loop._end_call()
	game.loop.first_called = true
	game.loop.extra_done = true
	game.dev.request("no_game_over", {"on": true})
	game.dev.request("god", {"on": true})
	game._clear_monsters()
	await tree.physics_frame
	# Somewhere with room to be knocked about in.
	var base: Vector3 = game._floor_at(game.clock_pos())
	var out := open_direction(game, base + Vector3.UP * 1.2, 8.0)
	var side := out.cross(Vector3.UP).normalized()
	place(game, base, base + out * 4.0 + Vector3.UP * 1.6)
	clear_hands(game)
	# Three saws: one snaps on about one swing in eight, and the review should outlive that.
	give(game, "bone_saw", 1)
	give(game, "bone_saw", 1)
	give(game, "bone_saw", 1)
	give(game, "anesthetic", 3)
	p.selected = 0
	p.set_flashlight(true)
	# Dr. Botsworth, standing still, close enough to saw: the PvP half.
	var bot: int = game.dev.spawn_bot("bot", p, "Dr. Botsworth", game._floor_at(base + side * 1.4))
	game.dev.order_bot(bot, "stay")
	# Two Hives walking in from ahead.
	var hives: Array = []
	for i in 2:
		var at: Vector3 = game._floor_at(base + out * 5.0 + side * (float(i) * 2.0 - 1.0))
		if not game._point_is_clear(at + Vector3.UP * 1.0):
			at = game._floor_at(base + out * 3.2)
		var h = game._add_monster("hive", at)
		h.brain._hunt(p.global_position)
		hives.append(h)
	await tree.physics_frame
	print("[review] hit: %d Hives and Dr. Botsworth within reach, %d bone saws in hand" % [hives.size(), 3])
	game.say("Saw the Hives, and saw Botsworth. Red flash, knocked back, still coming. Q shoves (that one stuns).", 10.0)


static func _puppet(game: Game) -> void:
	var tree := game.get_tree()
	var p = game.local_player()
	game.set_dev_tools(true, p)
	# Nothing else going on, and nothing that can end the review early. No god mode: a body left
	# standing while you are away in a Hive is meant to be at risk.
	game.loop._end_call()
	game.loop.first_called = true
	game.loop.extra_done = true
	game.dev.request("no_game_over", {"on": true})
	game._clear_monsters()
	await tree.physics_frame
	var base: Vector3 = game._floor_at(game.clock_pos())
	var out := open_direction(game, base + Vector3.UP * 1.2, 10.0)
	var side := out.cross(Vector3.UP).normalized()
	place(game, base, base + out * 6.0 + Vector3.UP * 1.2)
	clear_hands(game)
	p.set_flashlight(true)
	for q in game.players.values():
		if q != null and q.alive:
			game.abilities.set_level(q.peer_id, "puppet", 1)
	var hud = tree.get_first_node_in_group("hud")
	if hud != null:
		hud._card_seen["puppet"] = true   # the new-ability card is for a first play, not a review
	# Two Hives a few metres ahead, looking away from you (so they are not on you before you try it).
	var hives: Array = []
	for i in 2:
		var at: Vector3 = game._floor_at(base + out * (6.0 + i * 1.5) + side * (float(i) * 2.4 - 1.2))
		if not game._point_is_clear(at + Vector3.UP * 1.0):
			at = game._floor_at(base + out * (4.5 + i * 1.5))
		var h = game._add_monster("hive", at)
		h.rotation.y = atan2(-out.x, -out.z)
		hives.append(h)
	await tree.physics_frame
	print("[review] puppet: %d Hives ahead, Puppet 1 for %d player(s)" % [hives.size(), game.players.size()])
	game.say("Alt+1: climb into the nearest Hive. Mouse looks, move keys walk it, E or Esc comes back.", 10.0)


## A joiner stands beside the host as usual; its own HUD skips the new-ability card too.
static func _puppet_join(game: Game, host_player) -> void:
	place_beside(game, host_player)
	var hud = game.get_tree().get_first_node_in_group("hud")
	if hud != null:
		hud._card_seen["puppet"] = true


static func _graft_stage(game: Game, vat_kind: String, owner: String, already: bool) -> void:
	var tree := game.get_tree()
	var p = game.local_player()
	game.set_dev_tools(true, p)
	# Nothing else going on: no phone call, no patient wheeled onto the table, no monsters.
	game.loop._end_call()
	game.loop.first_called = true
	game.loop.extra_done = true
	game.dev.request("no_game_over", {"on": true})
	game.dev.request("monsters_off", {"on": true})
	var ti: int = game.free_patient_table()
	var si: int = game.vats.place_of_table(ti)
	if ti < 0 or si < 0:
		push_warning("[review] graft setup: no free table with a vat stand")
		return
	var yaw: float = game.table_yaw_of(ti)
	var tb := Basis(Vector3.UP, yaw)
	var table: Vector3 = game.table_position(ti)
	# The vat, already on that table's stand, with the part that goes in.
	var vat = game._spawn_item("specimen_vat", 1, Transform3D(tb, game.vats.places[si].position as Vector3), WorldItem.State.LOOSE)
	vat.x = Eyes.pack(vat_kind, owner, 0.0, 120 if vat_kind == "eye_hive" else 45)
	if already:
		game.grafts.apply(p.peer_id, "eye_hive")   # you already wear the Hive eyeball
	var hud = tree.get_first_node_in_group("hud")
	if hud != null:
		hud._card_seen["puppet"] = true   # the new-ability card is for a first play, not a review
	# You, strapped to that table, awake and looking up.
	clear_hands(game)
	p.teleport(game._floor_at(table + tb * Vector3(0.0, 0.0, 1.2)))
	await tree.physics_frame
	game.strap_in(p, ti)
	await tree.physics_frame
	# Dr. Botsworth, already yours, beside your head with the three tools.
	game.dev.control_botsworth()
	for i in 6:
		await tree.physics_frame
	var bw = game.dev.possessed_player()
	if bw == null:
		return
	bw.teleport(game._floor_at(table + tb * Vector3(-0.35, 0.0, 1.0)))
	bw.bot_move = Vector2.ZERO
	for i in bw.slots.size():
		bw.slots[i] = Player.empty_slot()
	# The four steps' tools, in the order they are used: 1 scalpel, 2 eye spoon, 3 forceps, 4 suture kit.
	bw.take_into("scalpel", 1)
	bw.take_into("eye_spoon", 1)
	bw.take_into("forceps", 1)
	bw.take_into("suture_kit", 1)
	bw.selected = 0
	bw.flashlight_on = true
	await tree.physics_frame
	# Looking down at your face on the table.
	var eye: Vector3 = bw.global_position + Vector3.UP * C.EYE_H
	var d: Vector3 = (game.player_table_top() + tb * Vector3(-0.55, 0.0, 0.0)) - eye
	bw._yaw = atan2(-d.x, -d.z)
	bw.rotation.y = bw._yaw
	bw._pitch = clampf(atan2(d.y, Vector2(d.x, d.z).length()), -1.0, 1.0)
	bw.head.rotation.x = bw._pitch
	bw.bot_yaw = bw._yaw
	bw.bot_pitch = bw._pitch
	game.say("Aim at the table and press E for each step. F1: back to your own body.", 8.0)


## BOTH EYE PROCEDURES in one window (2026-09-19): a Hive strapped to a free table with an empty vat
## standing on it -- hold the scalpel and press E to start Eyeball Extraction, four steps, the last
## one putting the eye in that vat -- and you strapped to another table with a vat holding a Hive's
## eye, as Dr. Botsworth with all four tools, for Eyeball Grafting.
static func _eyes(game: Game) -> void:
	var tree := game.get_tree()
	var hive_table: int = game.free_patient_table()
	if hive_table >= 0:
		game.dissection.dev_strap("hive", 1.0, hive_table)
		for i in 4:
			await tree.physics_frame
		var hi: int = game.vats.place_of_table(hive_table)
		if hi >= 0:
			game._spawn_item("specimen_vat", 1,
				Transform3D(Basis(Vector3.UP, float(game.table_yaw_of(hive_table))),
					game.vats.places[hi].position as Vector3), WorldItem.State.LOOSE)
	await _graft_stage(game, "eye_hive", "", false)
	game.say("Two tables: the Hive's eye comes out into its vat, yours gets swapped. F1: back to your own body.", 9.0)


## HOVER DROP (2026-09-22): a clear patch of floor near the OR, four stacks in hand and a row of
## six of every colour already hovering a couple of paces ahead (GLOW BALL: teal supply, gold loot,
## red organ, violet pharmacy stock, green vat). Tap the drop key over and over at the same spot:
## each stack should rise off the floor inside a soft ball of its own colour, and any that lands
## where one already floats hops
## aside to the nearest free spot instead of overlapping it. Charged throws go the same way once
## they stop tumbling, and the pickup ball is big enough to aim at from anywhere around it.
static func _hover_drop(game: Game) -> void:
	var t: Vector3 = game.table_pos()
	var base: Vector3 = game._floor_at(t + Vector3(0.0, 1.0, 4.2))
	var out := open_direction(game, base + Vector3.UP * 1.2, 3.5)
	place(game, base, base + out * 3.0 + Vector3(0.0, 0.5, 0.0))
	clear_hands(game)
	# GLOW BALL (2026-09-22): four hands' worth spanning four colours, so dropping them shows the
	# palette as well as the shoving-aside.
	give(game, "gauze", 2)                                      # teal, surgical
	give(game, "gold_watch", 1, 80)                             # gold, loot
	give(game, "eye_surgeon", 1, 45, {"bt": game.world_time})   # red, an organ
	give(game, "placebo_pills", 10)                             # violet, pharmacy stock
	game.local_player().selected = 0
	# And a row already hovering ahead, one of every colour, spaced so they read side by side from
	# across the room: back off, kill the flashlight, and see which is which.
	var spot: Vector3 = base + out * 2.4
	var side := Vector3(out.z, 0.0, -out.x).normalized()
	var row := ["bone_saw", "anesthetic", "laptop", "brain_hive", "rocket_boots", "specimen_vat"]
	for i in row.size():
		drop_at(game, row[i], spot + side * (float(i) - 2.5) * 0.85, 1, 60 if row[i] == "laptop" else 0)
	game.say("A colour per kind. Drop yours on one spot, then back off and kill the light.", 9.0)


## MIRRORS (2026-09-22): standing in front of the entrance's big full-length mirror, hands empty,
## looking at your own reflection. `--dist=N` stands N metres off the glass (default 1.4).
static func _mirror(game: Game) -> void:
	var pr: Dictionary = game.level_info.get("personnel", {})
	var m: Dictionary = pr.get("mirror", {})
	if m.is_empty():
		print("[review] mirror: this level has no personnel mirror")
		return
	var mp: Vector3 = m.position
	var out := (Basis(Vector3.UP, float(m.get("yaw", 0.0))) * Vector3(0, 0, -1)).normalized()
	var dist := 1.4
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--dist="):
			dist = float(a.split("=")[1])
	var glass: Vector3 = mp + Vector3(0.0, MirrorsScript.BIG_CENTRE.y, 0.0)
	place(game, game._floor_at(mp + out * dist), glass - Vector3(0.0, 0.3, 0.0))
	clear_hands(game)
	game.local_player().selected = 0
	game.say("Walk right up to the glass and press E: a real camera turns to face you, full screen, "
			+ "no black bars. Cycle your scrubs and your skin, E or Esc to come back.", 10.0)
## DOWNED (2026-09-22 playtest): a teammate bleeding on the floor of the OR, a free table beside you
## and two suture kits on the floor by it. Hands empty, hold E on them to hoist them over your
## shoulder, carry them to the table and press E to lay them down, pick a kit up and stitch them.
## What this is for: when they get up, the body must stand like anyone else's. It used to keep the
## fireman's-carry pose -- folded over a shoulder that is not there, most of it through the floor.
## The bug was never visible to the player being carried (they are behind their own eyes), so this
## setup makes you the carrier and the teammate a bot, which is exactly the body everyone else sees.
## Dev mode is on (F1) with monsters off and no game over, so nothing interrupts the look.
static func _downed(game: Game) -> void:
	var tree := game.get_tree()
	var me = game.local_player()
	game.set_dev_tools(true, me)
	var dev = game.dev
	dev.request("monsters_off", {"on": true})
	dev.request("no_game_over", {"on": true})
	# A free table to lay them on, and a clear patch of floor in front of it for the pick-up.
	var table: int = game.free_patient_table()
	if table < 0:
		table = int(game.patient_tables[0].index) if not game.patient_tables.is_empty() else 0
	var t: Vector3 = game.table_position(table)
	var b := Basis(Vector3.UP, float(game.table_yaw_of(table)))
	var side: Vector3 = b * Vector3(0.0, 0.0, 1.0)   # the side a revived player gets up on
	var mate_at: Vector3 = game._floor_at(t + side * 2.6)
	# A bot teammate, downed where you can see them from where you stand.
	var bid: int = dev.spawn_bot("bot", me, "Dr. Bled")
	for i in 4:
		await tree.physics_frame
	var mate = game.players.get(bid)
	if mate != null and is_instance_valid(mate):
		dev.brains.erase(bid)   # no orders, no wandering: it is a body to carry
		mate.teleport(mate_at)
		await tree.physics_frame
		# Down on the spot, without a step of crawling: that is how a teammate usually goes down, and
		# the body lies down for it (fixed 2026-09-22 -- it used to be staged crawling half a second, because a
		# body that went down standing still stayed drawn bolt upright).
		game.knock_down_player(mate, "review")
		for i in 30:
			await tree.physics_frame
		mate_at = mate.global_position
	place(game, game._floor_at(t + side * 4.2), mate_at + Vector3(0.0, 0.4, 0.0))
	clear_hands(game)   # a carry needs both hands free
	floor_item(game, "suture_kit", t + side * 1.2 + b * Vector3(0.5, 0.0, 0.0))
	floor_item(game, "suture_kit", t + side * 1.2 + b * Vector3(-0.5, 0.0, 0.0))
	game.say("Hands empty: hold E on Dr. Bled, carry them to a table, E anywhere at it lays them down (G drops them on the floor), then stitch.", 12.0)
	print("[review] downed: bot %d down at %s, free table %d at %s" % [bid, mate_at, table, t])


## MINIMAP: a free run of the hospital with the fogged floor plan in the top right corner. Nothing
## chasing you and nothing to lose, because the map is the whole point: walk out of the hub into a
## wing and watch the plan ink itself in behind you. The hub is drawn from the start; a ward room
## only appears once someone has actually gone into it, so walking a hallway past shut doors leaves
## those rooms blank.
static func _minimap(game: Game) -> void:
	var tree := game.get_tree()
	var p = game.local_player()
	game.set_dev_tools(true, p)
	# No phone call, no patient waiting, no losing, and nothing hunting you: an unhurried walk.
	game.loop._end_call()
	game.loop.first_called = true
	game.loop.extra_done = true
	game.dev.request("no_game_over", {"on": true})
	game.dev.request("god", {"on": true})
	game._clear_monsters()
	await tree.physics_frame
	game.say("Walk out into a wing. The hub is already on the map; the wards fill in as you go into them.", 10.0)
	print("[review] minimap: %d rooms, %d lit at the start" % [
			int(game.minimap.room_count), int(game.minimap.seen_rooms.count(0xFF))])


## GRAFTING (2026-09-22): the lab wall's vat bench, standing where you would stand to take one.
## The three vats are the ordinary bulky `specimen_vat` and always have been -- what stopped E was
## the bench, whose collider ran the piece's full 2.3 m of shelving and so swallowed its own counter
## top, sealing the vats inside a solid box no aim ray could get past. The bench now collides only
## up to the counter (PieceDefs "collide_h"), which is what puts them back out in the open.
static func _vats(game: Game) -> void:
	var tree := game.get_tree()
	game._clear_monsters()
	await tree.physics_frame
	var vats: Node = game.vats
	if vats == null or vats.spots.is_empty():
		game.say("No vat spots on this level.", 6.0)
		return
	var at: Vector3 = vats.spots[mini(1, vats.spots.size() - 1)].position
	var out := open_direction(game, at + Vector3.UP * 0.3, 2.5)
	clear_hands(game)
	place(game, game._floor_at(at + out * 1.1), at + Vector3.UP * 0.12)
	await tree.physics_frame
	floor_item(game, "eye_hive", game._floor_at(at + out * 1.6), 1, 100)
	game.say("E takes a vat off the bench (both hands). With the eye selected, E puts it in instead; V takes it back out.", 10.0)


# ---------------------------------------------------------------------------
# POCKETS 2 phase 2: the Natatorium (docs/POCKET_SPACES_2.md)

## On the deck at the water's edge, looking down the length of the pool, with the whistle and a drum
## in hand. The thing to test is the choice the room exists for: walk across the water, walk round on
## the deck, and hear how different those two are -- then decide whether the shortcut is worth it.
static func _natatorium(game: Game) -> void:
	var p = game.local_player()
	game.set_dev_tools(true, p)
	game.loop._end_call()
	game.loop.first_called = true
	game.loop.extra_done = true
	game.dev.request("no_game_over", {"on": true})
	var pk = game.pockets
	if pk == null or not pk.active():
		print("[review] natatorium: no pocket was built")
		return
	var o: Vector2i = pk.pocket.origin
	var w := func(t: Vector2, y := 0.0) -> Vector3:
		return Vector3((float(o.x) + t.x) * C.TILE, y, (float(o.y) + t.y) * C.TILE)
	var Nat := preload("res://scripts/level/pockets/natatorium.gd")
	var r: Rect2i = Nat.water_rect()
	# On the deck at the short end, looking down all fifty metres of it.
	place(game, w.call(Vector2(float(r.position.x) - 2.5, float(r.get_center().y))),
			w.call(Vector2(float(r.end.x), float(r.get_center().y)), 1.4))
	give(game, "lifeguard_whistle", 1, 15)
	give(game, "pool_chemical_drum", 1, 60)
	# One Sonographer, well away across the water, so there is something to be heard by.
	game._clear_monsters()
	await game.get_tree().physics_frame
	game._add_monster("sonographer", game._floor_at(w.call(Vector2(float(r.end.x) + 3.0, float(r.get_center().y)))))


## POCKETS 2 phase 3, the Chapel. You start at the back of the nave with a votive candle, a bottle
## of communion wine and a collection plate in hand, and a Night Nurse already walking the aisle.
## The thing to test is the candle: put it down, stand in it, and watch her stop -- with nobody
## looking at her and no light on her but the one you lit. Then wait about two minutes and watch
## the flame gutter out and her start moving again while you are still standing there.
static func _chapel(game: Game) -> void:
	var p = game.local_player()
	game.set_dev_tools(true, p)
	game.loop._end_call()
	game.loop.first_called = true
	game.loop.extra_done = true
	game.dev.request("no_game_over", {"on": true})
	var pk = game.pockets
	if pk == null or not pk.active():
		print("[review] chapel: no pocket was built")
		return
	var o: Vector2i = pk.pocket.origin
	var w := func(t: Vector2, y := 0.0) -> Vector3:
		return Vector3((float(o.x) + t.x) * C.TILE, y, (float(o.y) + t.y) * C.TILE)
	var Ch := preload("res://scripts/level/pockets/chapel.gd")
	var mid := float(Ch.MID_AISLE.position.x) + 1.0
	# In the processional aisle at the narthex end, looking the whole length of the nave.
	place(game, w.call(Vector2(mid, float(Ch.NARTHEX_END) - 1.0)), w.call(Vector2(mid, float(Ch.SANCTUARY_Y)), 1.5))
	give(game, "votive_candle", 1, 14)
	give(game, "communion_wine", 1, 0)
	give(game, "collection_plate", 1, 80)
	# One Night Nurse, up the nave, so she walks toward you and the candle has something to stop.
	game._clear_monsters()
	await game.get_tree().physics_frame
	game._add_monster("night_nurse", game._floor_at(w.call(Vector2(mid, float(Ch.SANCTUARY_Y) - 6.0))))


## POCKETS 2 phase 6 (docs/POCKET_SPACES_2.md): the Onlooker. You are standing in a pocket space
## with nothing in your hands and nothing to do, which is the point: the whole review is *look
## around*.
##
## What to look for, in the order it happens. It is already in the room, a long way off, facing
## you, and it never comes closer. Turn your back on it and it is not gone -- within about nine
## seconds it has moved into whatever you are looking at now. Keep ignoring it and it starts taking
## hearts, faster the longer you leave it. The saw, the needle and a shove do nothing at all. The
## only thing that works is running straight at it, and then it is gone for over a minute. Walking
## out through a seam ends it too.
##
## It is SILENT throughout. If you hear anything from it, that is a bug.
##
## The roll is forced on, so it is always there; in a real shift it is a coin flip per pocket.
static func _onlooker(game: Game) -> void:
	var p = game.local_player()
	game.set_dev_tools(true, p)
	game.loop._end_call()
	game.loop.first_called = true
	game.loop.extra_done = true
	game.dev.request("no_game_over", {"on": true})
	var pk = game.pockets
	if pk == null or not pk.active():
		print("[review] onlooker: no pocket was built")
		return
	game._clear_monsters()
	# Nothing else in the room: the Onlooker is the only thing to look at, and a Hive shuffling
	# about behind you would give away the one monster that never makes a sound.
	game.dev.request("monsters_off", {"on": true})
	# Stand where the room is longest, facing down it.
	var centre: Vector3 = pk.pocket.spawn
	var dir := open_direction(game, centre + Vector3.UP * 1.5, 60.0)
	place(game, centre, centre + dir * 30.0 + Vector3.UP * 1.6)
	give(game, "bone_saw", 1, 0)   # so the "it does nothing" half can actually be tried
	# Force the roll on for this pocket and let the watcher place it.
	preload("res://scripts/monsters/onlooker_watch.gd").force = "on"
	if game.onlooker_watch != null:
		game.onlooker_watch.rearm()
	await game.get_tree().physics_frame


## 2026-09-24: the Onlooker's shadow and its poof. It is standing `RUSH_AT` metres in front of you,
## in the pocket's own light and air, facing you -- look at it: the edge that will not resolve, the
## smoke coming off it. Then run at it: inside six metres it poofs, a burst of dark smoke and a cloud
## that hangs where it stood and thins out over a few seconds. With `-Count 2` the joiner, beside
## you, should see the same poof from where they stand.
##
## It holds still for the first look (no hop until you have been at it once). After a banish it
## comes back in RUSH_BACK seconds instead of the real 75, placed by its own brain (far off, in your
## view, the way it really arrives), so it can be rushed again and again.
const RUSH_AT := 11.0
const RUSH_BACK := 4.0

static func _onlooker_rush(game: Game) -> void:
	var p = game.local_player()
	game.set_dev_tools(true, p)
	game.loop._end_call()
	game.loop.first_called = true
	game.loop.extra_done = true
	game.dev.request("no_game_over", {"on": true})
	var pk = game.pockets
	if pk == null or not pk.active():
		print("[review] onlooker_rush: no pocket was built")
		return
	game._clear_monsters()
	game.dev.request("monsters_off", {"on": true})
	preload("res://scripts/monsters/onlooker_watch.gd").force = "off"
	var centre: Vector3 = pk.pocket.spawn
	var dir := open_heading(game, centre + Vector3.UP * 1.5, 40.0)
	place(game, centre, centre + dir * 30.0 + Vector3.UP * 1.6)
	await game.get_tree().physics_frame
	var o = onlooker_ahead(game, RUSH_AT)
	if o == null:
		print("[review] onlooker_rush: could not add an Onlooker")
		return
	# A small keeper: after each banish, bring it back in RUSH_BACK seconds instead of 75.
	var keeper := Node.new()
	keeper.name = "OnlookerRushKeeper"
	game.add_child(keeper)
	var tick := func() -> void:
		if not is_instance_valid(o) or o.brain == null:
			return
		if not bool(o.present) and float(o.brain.away_left) > RUSH_BACK:
			o.brain.away_left = RUSH_BACK
	game.get_tree().physics_frame.connect(tick)
	keeper.tree_exiting.connect(func(): game.get_tree().physics_frame.disconnect(tick))
	print("[review] onlooker_rush: standing %.1f m off" % o.global_position.distance_to(p.global_position))


## Of 16 headings out of `from`, the one with the longest clear run (capped at `reach`).
static func open_heading(game: Game, from: Vector3, reach: float) -> Vector3:
	var space: PhysicsDirectSpaceState3D = game.get_world_3d().direct_space_state
	var best := Vector3.FORWARD
	var best_d := -1.0
	for i in 16:
		var a := TAU * float(i) / 16.0
		var d := Vector3(sin(a), 0.0, cos(a))
		var q := PhysicsRayQueryParameters3D.create(from, from + d * reach)
		q.collision_mask = C.L_WORLD
		var hit := space.intersect_ray(q)
		var dist: float = reach if hit.is_empty() else from.distance_to(hit.position)
		if dist > best_d + 0.01:
			best_d = dist
			best = d
	return best


## Host: an Onlooker standing `dist` metres straight ahead of the local player, facing them, already
## there, marking them and holding still (no hop until it has been sent away once). For the review
## setup above and tools/gameshot_pockets.gd's onlooker shots. Null if it could not be added.
static func onlooker_ahead(game: Game, dist: float, fade_in := true) -> Node:
	var p = game.local_player()
	var fwd: Vector3 = -p.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length() > 0.01 else Vector3.FORWARD
	var at: Vector3 = game._floor_at(p.global_position + fwd * dist)
	var o = game.onlooker_watch.current() if game.onlooker_watch != null else null
	if o == null:
		for m in game.monsters.values():
			if is_instance_valid(m) and String(m.kind) == "onlooker":
				o = m
	if o == null:
		o = game.spawn_pocket_monster("onlooker", at)
	if o == null:
		return null
	var br = o.brain
	o.global_position = at
	o.velocity = Vector3.ZERO
	o.face_dir(p.global_position - at, 1.0, 1.0)
	br.space = String(game.pockets.pocket.get("kind", ""))
	br.started = true
	br.mark_peer = int(p.peer_id)
	br.placements += 1   # a client snaps to it rather than sliding in
	br.hop_left = 1.0e9   # it waits for you; the first banish puts it back on its real clock
	br.stare = 0.0
	br.ticks = 0
	o.present = true
	o.presence = 0.0 if fade_in else 1.0
	return o


## POCKETS 2 phase 4 (docs/POCKET_SPACES_2.md): the Laundromat. You start well inside the room with
## the three items in hand, and a Sonographer is already hunting a few metres away. The whole space
## is one mechanic -- its ambient noise floor is above a walking footstep -- so the review is: walk
## about in here and watch it fail to find you, sprint and watch it get interested, throw a handful
## of quarters across the room and watch it go there instead, then walk out through a seam into the
## hospital and hear it pick you straight up.
static func _laundromat(game: Game) -> void:
	var tree := game.get_tree()
	var p = game.local_player()
	game.set_dev_tools(true, p)
	game.loop._end_call()
	game.loop.first_called = true
	game.loop.extra_done = true
	game.dev.request("no_game_over", {"on": true})
	game.dev.request("monsters_off", {"on": true})   # only the one staged below
	game.dev.request("clear_patient")
	var pk = game.pockets
	if pk != null and pk.busy:
		pk.finish_now()
	if pk == null or not pk.active():
		push_warning("[review] the laundromat setup got no pocket; showing the hospital instead")
		return
	# Well inside the room, looking down its length.
	var spawn: Vector3 = pk.pocket.spawn
	var rect: Rect2 = pk.pocket.rect
	var along := Vector3(1.0, 0.0, 0.0) if rect.size.x >= rect.size.y else Vector3(0.0, 0.0, 1.0)
	place(game, game._floor_at(spawn - along * 6.0), spawn + along * 6.0 + Vector3(0, 0.05, 0))
	clear_hands(game)
	give(game, "quarter_bucket", 4, 52)
	give(game, "fabric_softener", 1, 22)
	give(game, "warm_scrubs", 1, 30)
	p.selected = 0
	p.flashlight_on = true
	await tree.physics_frame
	# A Sonographer down the room, calm for long enough that the first thing you do is look at it
	# rather than run from it. After that it hunts normally -- and in here it hunts by a sense that
	# does not work.
	var m = game._add_monster("sonographer", game._floor_at(spawn + along * 9.0))
	if m != null:
		m.calm = 20.0
	await tree.physics_frame


## POCKETS 2 phase 4b, the bleed. You are standing in an ordinary hospital room a few rooms from a
## pocket entrance, looking at one of the pocket's own items sitting there as if it belonged. The
## thing to judge is whether it reads as a *hint* -- odd enough to make you look for the way through,
## not so odd that it looks like a bug -- and whether one or two a shift is the right amount. The
## console says what it found and where; the entrance it came from is a few rooms away, so walking
## the wing from here should turn it up.
static func _bleed(game: Game) -> void:
	var p = game.local_player()
	game.set_dev_tools(true, p)
	game.loop._end_call()
	game.loop.first_called = true
	game.loop.extra_done = true
	game.dev.request("no_game_over", {"on": true})
	var PocketBleed := preload("res://scripts/economy/pocket_bleed.gd")
	var LootTable := preload("res://scripts/economy/loot_table.gd")
	var info: Dictionary = game.level_info
	var near := PocketBleed.seam_tiles(info)
	var width := int((info.get("size", Vector2i.ZERO) as Vector2i).x)
	if near.is_empty():
		print("[review] bleed: no pocket was built on this seed")
		return
	print("[review] bleed: %d rooms near a seam" % PocketBleed.seam_rooms(info).size())
	# Whatever got out: a pocket kind standing on the hospital side, in a room near a seam.
	var found = null
	for it in game.world_items.values():
		if not is_instance_valid(it) or String(LootTable.LOOT.get(it.kind, {}).get("pocket", "")) == "":
			continue
		var q: Vector3 = it.global_position
		if near.has(int(floor(q.z / C.TILE)) * width + int(floor(q.x / C.TILE))):
			found = it
			break
	if found == null:
		print("[review] bleed: nothing bled on this seed and shift -- try another --seed=N")
		return
	var at: Vector3 = found.global_position
	print("[review] bleed: a %s in the hospital at %v" % [found.kind, at])
	# Somewhere that can actually see it: the first of the four axes, at the first distance, whose
	# eye line reaches the thing without a wall or a pillar in the way. "Most open direction" is not
	# enough on its own -- it happily puts you round the corner from what you came to look at.
	var look := at + Vector3.UP * 0.35
	var space: PhysicsDirectSpaceState3D = game.get_world_3d().direct_space_state
	var spot := game._floor_at(at + Vector3.BACK * 1.5)
	for d in [Vector3.BACK, Vector3.FORWARD, Vector3.LEFT, Vector3.RIGHT]:
		var clear := false
		for dist in [2.6, 2.0, 1.5]:
			var try_at := game._floor_at(at + d * dist)
			var q := PhysicsRayQueryParameters3D.create(try_at + Vector3.UP * 1.6, look)
			q.collision_mask = C.L_WORLD
			if space.intersect_ray(q).is_empty():
				spot = try_at
				clear = true
				break
		if clear:
			break
	place(game, spot, look)
	print("[review] bleed: standing at %v, %.1f m from it" % [spot, spot.distance_to(at)])


# ---------------------------------------------------------------------------
# FLASHLIGHT POSE (2026-09-24)

## How far in front of the host the onlooker stands, and how far off to one side: about 50 degrees
## off the host's line, so the raised arm reads side on and the sweeping beam swings past you.
const TORCH_WATCH_AHEAD := 2.4
const TORCH_WATCH_SIDE := 2.6


## Somewhere with room ahead: the host faces down it. Solo, you take the onlooker's spot and Dr.
## Botsworth the host's. Either way Dr. Botsworth stands a step to the host's left running the demo, so
## there is always a teammate's torch to look at; the host runs it too until its window is touched.
static func _flashlight_pair(game: Game) -> void:
	var tree := game.get_tree()
	var p = game.local_player()
	game.set_dev_tools(true, p)
	game.loop._end_call()
	game.loop.first_called = true
	game.loop.extra_done = true
	game.dev.request("no_game_over", {"on": true})
	game.dev.request("god", {"on": true})
	game.dev.request("monsters_off", {"on": true})
	game._clear_monsters()
	await tree.physics_frame
	var base: Vector3 = game._floor_at(game.clock_pos())
	var out := open_direction(game, base + Vector3.UP * 1.2, 8.0)
	var side := out.cross(Vector3.UP).normalized()   # the host's right
	var coop := role() == "host"
	var host_at: Vector3 = base
	var bot_at: Vector3 = game._floor_at(base - side * 1.4 + out * 0.3)
	clear_hands(game)
	var bid: int = game.dev.spawn_bot("bot", p, "Dr. Botsworth", bot_at)
	for i in 4:
		await tree.physics_frame
	var bot = game.players.get(bid)
	if bot != null and is_instance_valid(bot):
		game.dev.brains.erase(bid)   # no orders, no wandering: it stands and holds its torch
		bot.teleport(bot_at)
		# A saw in the right hand, so the torch in the left is seen beside something held.
		bot.take_into("bone_saw", 1, 0)
	var yaw := atan2(-out.x, -out.z)
	if coop:
		place(game, host_at, host_at + out * 4.0 + Vector3.UP * 1.5)
	else:
		# Solo: you are the onlooker, in front of Dr. Botsworth, looking back at him.
		var watch: Vector3 = game._floor_at(bot_at + out * TORCH_WATCH_AHEAD + side * TORCH_WATCH_SIDE)
		place(game, watch, bot_at + Vector3.UP * 1.25)
		p.set_flashlight(false)
	var demo := TorchDemo.new()
	demo.name = "ReviewTorchDemo"
	demo.host = p if coop else null
	demo.bot = bot
	demo.yaw = yaw
	game.add_child(demo)
	if coop and OS.get_cmdline_user_args().has("--shots"):
		_torch_host_shots(game)
	game.say("Your teammate holds a torch now: the beam comes out of it. Lit, blue while scanning (R), dark when off (F).", 10.0)
	print("[review] flashlight_pair: host at %v facing %v, Dr. Botsworth (%d) at %v, %s" % [
			host_at, out, bid, bot_at, "co-op" if coop else "solo"])


## Smoke look, the host's own view: 15 shots in its saved camera mode, then 15 in the other (first
## person against the shoulder camera), and the saved mode put back. Your own torch must still light
## your own view, and your own body's torch must not throw a second beam.
static func _torch_host_shots(game: Game) -> void:
	var tree := game.get_tree()
	var dir := ProjectSettings.globalize_path("res://tools/flashlight_shots")
	DirAccess.make_dir_recursive_absolute(dir)
	var saved := String(Settings.get_value("camera"))
	for i in 30:
		if i == 15:
			Settings.set_value("camera", "first_person" if saved != "first_person" else "shoulder")
		await tree.create_timer(1.0).timeout
		game.get_viewport().get_texture().get_image().save_png("%s/host_%02d.png" % [dir, i])
	Settings.set_value("camera", saved)
	print("[review] host shots done, camera back to %s" % saved)


## The onlooker: in front of the host and a little to one side, facing it, with its own torch off so
## what lights the host up is the host's own beam.
static func _flashlight_pair_join(game: Game, host_player) -> void:
	var tree := game.get_tree()
	var me = game.local_player()
	# The host's own placement lands a moment after the shift starts here: read where it faces after.
	await tree.create_timer(2.5).timeout
	var yaw: float = host_player.rotation.y
	var forward := Vector3(-sin(yaw), 0.0, -cos(yaw))
	var right := Vector3(cos(yaw), 0.0, -sin(yaw))
	var hp: Vector3 = host_player.global_position
	var chest := hp + Vector3.UP * 1.25
	# The first spot, most side-on first, that is floor where it was asked for and sees the host.
	var space: PhysicsDirectSpaceState3D = game.get_world_3d().direct_space_state
	var at: Vector3 = game._floor_at(hp + forward * 3.6 + right * 1.1)
	for o in [Vector2(TORCH_WATCH_AHEAD, TORCH_WATCH_SIDE), Vector2(TORCH_WATCH_AHEAD, -TORCH_WATCH_SIDE),
			Vector2(3.0, 1.7), Vector2(3.0, -1.7), Vector2(3.6, 1.1), Vector2(3.6, -1.1), Vector2(3.0, 0.6)]:
		var want: Vector3 = hp + forward * o.x + right * o.y
		var got: Vector3 = game._floor_at(want)
		if absf(got.y - hp.y) > 0.3:
			continue   # on top of something, or no floor there
		# Both ways, so a spot inside a wall (where a ray starting in it sees nothing) is not taken.
		var eye: Vector3 = got + Vector3.UP * 1.6
		var q := PhysicsRayQueryParameters3D.create(eye, chest)
		q.collision_mask = C.L_WORLD
		var back := PhysicsRayQueryParameters3D.create(chest, eye)
		back.collision_mask = C.L_WORLD
		if space.intersect_ray(q).is_empty() and space.intersect_ray(back).is_empty():
			at = got
			break
	place(game, at, chest)
	me.set_flashlight(false)
	if not OS.get_cmdline_user_args().has("--shots"):
		return
	# Smoke look: a screenshot a second through two whole demo loops, from this (the other player's) camera.
	var dir := ProjectSettings.globalize_path("res://tools/flashlight_shots")
	DirAccess.make_dir_recursive_absolute(dir)
	for i in 30:
		await tree.create_timer(1.0).timeout
		var img := game.get_viewport().get_texture().get_image()
		var path := "%s/pair_%02d.png" % [dir, i]
		img.save_png(path)
		var fl = host_player.flashlight
		print("[review] shot %s: host torch state %d, its light %s at %v (head %v)" % [path.get_file(),
				int(host_player.torch_state()), "on" if fl.visible else "off", fl.global_position, host_player.head.global_position])


## The demo loop (host side): held still, lit and straight ahead for HOLD s (so the onlooker can read
## which way the host faces), then round and round: lit and sweeping the beam about, the scanner, off.
## Drives Dr. Botsworth always, and the host's own player until anything is pressed in the host window.
class TorchDemo extends Node:
	const HOLD := 8.0
	const LIT := 6.0
	const SCAN := 3.0
	const OFF := 2.5
	var host = null
	var bot = null
	var yaw := 0.0
	var t := 0.0

	func _process(delta: float) -> void:
		t += delta
		var run := maxf(0.0, t - HOLD)
		var phase := fmod(run, LIT + SCAN + OFF)
		var state := 1
		if run > 0.0 and phase >= LIT:
			state = 2 if phase < LIT + SCAN else 0
		var dyaw := sin(run * 0.8) * 0.5
		var pitch := sin(run * 0.55) * 0.35
		if host != null and is_instance_valid(host):
			host._yaw = yaw + dyaw
			host._pitch = pitch
			if host.flashlight_on != (state != 0):
				host.set_flashlight(state != 0)
			if state == 2 and not Input.is_action_pressed("scan"):
				Input.action_press("scan")
			elif state != 2 and Input.is_action_pressed("scan"):
				Input.action_release("scan")
		if bot != null and is_instance_valid(bot):
			bot.bot_yaw = yaw - dyaw
			bot.bot_pitch = -pitch
			if bot.flashlight_on != (state != 0):
				bot.set_flashlight(state != 0)
			bot.bot_scan = state == 2

	func _input(e: InputEvent) -> void:
		if host == null:
			return
		if (e is InputEventKey or e is InputEventMouseButton) and e.is_pressed():
			if Input.is_action_pressed("scan"):
				Input.action_release("scan")
			host = null   # someone is at the host window: it is theirs now
			print("[review] flashlight_pair: the host window was touched; the demo stops driving it")


## fix-pocket-zfighting: the pocket-space props were drawn inside out, so a box standing on the floor
## showed the inside of its own bottom face, which fought the floor for every pixel. Look at the foot
## of a starting block (`zfight_pool`) or of a bank of washers (`zfight_laundry`) and walk about.
static func _zfight_pool(game: Game) -> void:
	await _zfight_stage(game, func(lay: Dictionary, w: Callable) -> Array:
		var Nat := preload("res://scripts/level/pockets/natatorium.gd")
		var bz: float = lay.blocks[4]
		var foot: Vector3 = w.call(Vector2(float(Nat.POOL.end.x) + 0.45, bz))
		return [foot + Vector3(2.2, 0.0, 1.0), foot + Vector3(0.0, 0.1, 0.0)])


static func _zfight_laundry(game: Game) -> void:
	await _zfight_stage(game, func(lay: Dictionary, w: Callable) -> Array:
		var isl: Dictionary = lay.islands[mini(8, lay.islands.size() - 1)]
		var foot: Vector3 = w.call(Vector2(isl.tile) + Vector2(0.5, 0.5))
		# In the aisle in front of the island's other row, looking at the foot of its doors.
		return [foot + Vector3(0.3, 0.0, 3.0), foot + Vector3(0.0, 0.05, 1.9)])


static func _zfight_stage(game: Game, spot: Callable) -> void:
	var p = game.local_player()
	game.set_dev_tools(true, p)
	game.loop._end_call()
	game.loop.first_called = true
	game.loop.extra_done = true
	game.dev.request("no_game_over", {"on": true})
	game.dev.request("monsters_off", {"on": true})
	var pk = game.pockets
	if pk != null and pk.busy:
		pk.finish_now()
	if pk == null or not pk.active():
		push_warning("[review] zfight: no pocket was built")
		return
	var o: Vector2i = pk.pocket.origin
	var w := func(t: Vector2, y := 0.0) -> Vector3:
		return Vector3((float(o.x) + t.x) * C.TILE, y, (float(o.y) + t.y) * C.TILE)
	var at: Array = spot.call(pk.pocket.layout, w)
	game._clear_monsters()
	place(game, at[0], at[1])
	p.flashlight_on = true
	p.refresh_own_lights()
	await game.get_tree().physics_frame


## SHOWERS (2026-09-24, Zach: "make the showers able to be turned on and off with E"): standing a
## step back from the first personnel shower, facing it, hands empty. Press E: a stream falls off
## the head, a low mist where it hits the floor, and the water loop starts. E again turns it off.
static func _showers(game: Game) -> void:
	var pr: Dictionary = game.level_info.get("personnel", {})
	var list: Array = pr.get("showers", [])
	if list.is_empty():
		print("[review] showers: this level has no personnel showers")
		return
	var s: Dictionary = list[0]
	var sp: Vector3 = s.position
	var out := (Basis(Vector3.UP, float(s.get("yaw", 0.0))) * Vector3(0, 0, -1)).normalized()
	place(game, game._floor_at(sp + out * 1.3), sp + Vector3(0.0, 1.4, 0.0))
	clear_hands(game)
	game.local_player().selected = 0
	game.say("Aim at the shower head and press E: water on, water off. It should sound and look the same on a teammate's screen.", 9.0)
	print("[review] showers: %d showers on this level, standing in front of the first at %s" % [list.size(), str(sp.snappedf(0.1))])


## TUMBLE TUNING (2026-09-24): open floor with a wall close on one side, four throwables in hand
## (light, heavy, bulky, a stack). Right-click and hold to charge a throw, at a few angles: a flat
## toss along the floor, a lobbed arc, one straight down and one at the wall. Each should land,
## settle within about a second of coming to rest and ease up into its hover -- no sitting there
## tumbling, no jitter, nothing buried in the floor or the wall.
static func _tumble(game: Game) -> void:
	var t: Vector3 = game.table_pos()
	var base: Vector3 = game._floor_at(t + Vector3(0.0, 0.0, 4.2))
	var out := open_direction(game, base + Vector3.UP * 1.2, 4.0)
	place(game, base, base + out * 3.0 + Vector3(0.0, 0.5, 0.0))
	clear_hands(game)
	give(game, "gauze", 2)          # light
	give(game, "bone_saw", 1)       # heavy, bulky
	give(game, "gold_watch", 1, 80) # loot, small
	give(game, "placebo_pills", 6)  # a stack
	game.local_player().selected = 0
	game.say("Hold right-click to charge a throw. Try a flat toss, a high arc, straight down and one at the wall behind you.", 10.0)


## SKILL TREE (docs/SKILL_TREE.md): a step back from the vein machine's hand plate, facing it, hands
## empty, with at least 6 skill points. Press E: the reader scans your palm, the veins grow across the
## big screen, and the nodes on them are the skill tree. `--fresh` forgets every skill first (and
## the points with them, before the top-up). Skills are saved per machine, so what you buy here is
## still there next time (that is the persistence to check).
static func _skill_tree(game: Game) -> void:
	var pr: Dictionary = game.level_info.get("personnel", {})
	var sc: Dictionary = pr.get("scanner", {})
	var sr: Dictionary = pr.get("screen", {})
	if sc.is_empty() or sr.is_empty():
		print("[review] skill_tree: this level has no vein machine")
		return
	if OS.get_cmdline_user_args().has("--fresh"):
		Skills.wipe()
	Skills.top_up(6)
	var plate: Vector3 = sc.position
	var glass: Vector3 = sr.position
	var out := Vector3(plate.x - glass.x, 0.0, plate.z - glass.z).normalized()
	place(game, game._floor_at(plate + out * 1.4), plate + Vector3(0.0, 1.0, 0.0) - out * 0.4)
	clear_hands(game)
	game.local_player().selected = 0
	game.say("Put your palm on the reader (E). Watch the scan and the veins grow, click a node, INFUSE it. Esc steps away.", 9.0)
	print("[review] skill_tree: %d points, %d skills unlocked" % [Skills.points, Skills.unlocked.size()])
