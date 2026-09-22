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


## Both abilities (Hive Eyes and Echo) at the given level.
static func give_abilities(game: Game, level := 2) -> void:
	var p = game.local_player()
	game.abilities.set_level(p.peer_id, "echo", level)
	game.abilities.set_level(p.peer_id, "hive_in", level)
	# No "New ability" cards in the way: they are for a first play.
	var hud = game.get_tree().get_first_node_in_group("hud")
	if hud != null:
		hud._card_seen["echo"] = true
		hud._card_seen["hive_in"] = true


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
		hud._card_seen["hive_in"] = true   # the new-ability card is for a first play, not a review
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
	game.say("Aim at the mirror and press E: cycle your scrubs and your skin, E again to come back.", 10.0)
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
		game.knock_down_player(mate, "review")
		# Then half a second of crawling. The rigged body only blends into its Crawl clip while it
		# moves (docs/KNOWN_ISSUES.md, "a downed player who never crawls is drawn standing"), so a
		# teammate downed on the spot would be staged bolt upright -- nothing to do with this fix.
		mate.bot_move = Vector2(0.0, -1.0)
		for i in 30:
			await tree.physics_frame
		mate.bot_move = Vector2.ZERO
		mate_at = mate.global_position
	place(game, game._floor_at(t + side * 4.2), mate_at + Vector3(0.0, 0.4, 0.0))
	clear_hands(game)   # a carry needs both hands free
	floor_item(game, "suture_kit", t + side * 1.2 + b * Vector3(0.5, 0.0, 0.0))
	floor_item(game, "suture_kit", t + side * 1.2 + b * Vector3(-0.5, 0.0, 0.0))
	game.say("Hands empty: hold E on Dr. Bled, carry them to a table, E anywhere at it lays them down (G drops them on the floor), then stitch.", 12.0)
	print("[review] downed: bot %d down at %s, free table %d at %s" % [bid, mate_at, table, t])
