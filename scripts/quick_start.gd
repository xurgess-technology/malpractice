class_name QuickStart
extends RefCounted
## DEBUG ONLY. A command-line shortcut into the middle of a surgery: no launch printout, no
## sign-in sheet, no lobby, no walk to the pharmacy fax, no dev panel, no stocking the shelf.
## The window opens with you leaning over the patient, the step's tool selected in your hand,
## one press of E from the step itself.
##
##   quick.bat --quick=gunshot:extract --patient=bob --shift=1
##   godot --path . -- --quick=gunshot:extract --patient=bob --shift=1
##
## Arguments (after `--`, read the way ReviewSetups.requested() reads its own):
##   --quick=<ailment>:<step_id>   the ailment and which of its steps to start at (required)
##   --patient=<patient_id>        default "bob"
##   --shift=<n>                   the difficulty knob (Procedures.difficulty), default 1
##   --seed=<n>                    optional, shared with the review windows (default 4242), so the
##                                 same command gives the same hospital every time
##
## An unknown ailment, step or patient prints what is valid and boots the title menu as usual.
##
## **Everything here is behind OS.is_debug_build().** A release build parses no arguments and
## boots exactly as it always did, and none of this touches Game.DEV_CODE or the pharmacy fax:
## the secret order is still the only way into dev mode in a real session.
##
## Where it plugs in: main.gd `_launch()` asks requested() before it builds the launch printout,
## and runs `_boot_quick()` instead when there is a spec; Warmup.run takes warmup_scope() so it
## builds only what this one case needs; stage() sets the shift up once the player exists.

## The surgeon's name on the quick-start session.
const PLAYER_NAME := "Dev"

## How far from the site you stand, and how much room a side of the table needs to be the one you
## stand on. The table's aim proxy is a 1.2 m sphere over its middle (game._add_proxy), and a ray
## that starts inside a sphere never hits it: stand any closer than this and E does nothing,
## which is why _stand() checks what you end up aiming at rather than trusting one distance.
const STAND_M := 1.35
const STAND_TRIES := [1.35, 1.6, 1.1, 1.9]
const SIDE_CLEARANCE_M := 2.5

## What each step's minigame emits when it goes perfectly (see scripts/surgery/games/*.gd). Every
## step before the one asked for is applied as if it had been done cleanly, so the body's visuals,
## the OR wall monitor and the step list all agree with where you are standing.
## Keyed by the step's `id` in Procedures.AILMENTS; only the patient ailments (gunshot, amputation)
## can be quick-started, so the player-only and monster-only steps are not in here.
const CLEAN_RESULTS := {
	"sedate": {"sedation": 1.0},
	"extract": {"bullet_removed": true},
	"dress": {"dressed": true},
	"tourniquet": {"tourniquet": 1.0},
	"cut": {"amputated": true, "cut_quality": 1.0},
}


## The quick-start asked for on the command line, or {} for none (and for every release build).
## Keys: `ailment`, `step` (its id), `step_index`, `patient`, `shift`.
static func requested() -> Dictionary:
	if not OS.is_debug_build():
		return {}
	var quick := _arg("--quick=")
	if quick == "":
		return {}
	var ailment := quick
	var step_id := ""
	var colon := quick.find(":")
	if colon >= 0:
		ailment = quick.substr(0, colon).strip_edges()
		step_id = quick.substr(colon + 1).strip_edges()
	if not _ailments().has(ailment):
		_complain("no ailment '%s'; try one of: %s" % [ailment, ", ".join(_ailments())])
		return {}
	var ids := _step_ids(ailment)
	if step_id == "":
		step_id = String(ids[0])
	var step_index := ids.find(step_id)
	if step_index < 0:
		_complain("'%s' has no step '%s'; its steps are: %s" % [ailment, step_id, ", ".join(ids)])
		return {}
	var patient := _arg("--patient=")
	if patient == "":
		patient = "bob"
	if not _patients().has(patient):
		_complain("no patient '%s'; try one of: %s" % [patient, ", ".join(_patients())])
		return {}
	var shift_arg := _arg("--shift=")
	var shift := int(shift_arg) if shift_arg.is_valid_int() else 1
	return {
		"ailment": ailment,
		"step": step_id,
		"step_index": step_index,
		"patient": patient,
		"shift": clampi(shift, 1, 99),
	}


## The hospital seed. `--seed=N` is the same argument the review windows take; without one every
## quick start builds the same hospital, so the walk from the table never moves under you.
static func seed_of(_spec: Dictionary) -> int:
	return ReviewSetups.seed_of("")


## What Warmup.run has to build for this case and nothing else (see the scope comment there).
static func warmup_scope(spec: Dictionary) -> Dictionary:
	return {"patient": String(spec.get("patient", "bob")), "ailment": String(spec.get("ailment", "gunshot"))}


## Set the shift up around the local player, who is in the world and standing at the spawn.
## Called from main.gd `_boot_quick()`; may await.
static func stage(game: Node, spec: Dictionary) -> void:
	var tree := game.get_tree()
	var p = game.local_player()
	if p == null:
		push_warning("[quick] nobody to stand at the table")
		return
	var ailment := String(spec.ailment)
	var patient := String(spec.patient)
	var step_index := int(spec.step_index)
	var step: Dictionary = Procedures.step(ailment, step_index)

	# Dev tools on the same way the pharmacy fax turns them on (F1 opens the panel), then the
	# toggles the dev room already has: no monsters, vitals frozen, no game over, and the shift
	# number as the difficulty knob. Monsters off before clocking in, or the shift spawns its own.
	game.set_dev_tools(true, p)
	game.dev.request("monsters_off", {"on": true})
	game.dev.request("freeze", {"on": true})
	game.dev.request("no_game_over", {"on": true})
	game.dev.request("difficulty", {"shift": int(spec.shift)})

	# Clocked in, with the wings and the pocket forced ready (begin_shift does the same: nothing
	# here can wait for them). The shift's phone call and its extra patient are marked dealt with,
	# so nothing rings and nobody else is wheeled in on top of this.
	game.wing_loader.finish_now()
	game.pockets.finish_now()
	game.clock_in()
	game.loop.grace_left = 0.0
	game.loop.first_called = true
	game.loop.extra_done = true
	game.loop._end_call()
	await tree.physics_frame

	# The patient on table 0 (the first free one), already at the step asked for: every earlier
	# step's clean result goes into the case's flags, so add_case builds the body with them on.
	var ti: int = game.free_patient_table()
	if ti < 0:
		push_warning("[quick] no free patient table")
		return
	var flags := {}
	var steps: Array = Procedures.steps(ailment)
	for i in step_index:
		var earlier := String((steps[i] as Dictionary).get("id", ""))
		if not CLEAN_RESULTS.has(earlier):
			push_warning("[quick] no clean result for step '%s'; the case may not look right" % earlier)
			continue
		flags.merge(CLEAN_RESULTS[earlier], true)
	var case_id: int = game.add_case({
		"patient_id": patient, "ailment_id": ailment, "table": ti,
		"step_index": step_index, "flags": flags, "state": "on_table",
	})
	if case_id < 0:
		push_warning("[quick] the table would not take the case")
		return
	await tree.physics_frame
	var body = game.body_for_table(ti)
	if body != null and is_instance_valid(body) and flags.has("sedation"):
		body.set_sedation(float(flags.sedation))

	# Standing at the site, on whichever side of the table has the room, looking down at it.
	var table: Vector3 = game.table_position(ti)
	var tb := Basis(Vector3.UP, game.table_yaw_of(ti))
	var site: Vector3 = table + Vector3.UP * 1.1
	if body != null and is_instance_valid(body) and body.has_method("site_transform"):
		site = body.site_transform(String(step.get("site", ""))).origin
	var side := _stand_side(game, table, tb)
	await _stand(game, p, site, table, side, game.table_interact_id(ti))

	# The step's item selected in your hand (SurgerySystem.can_begin wants the SELECTED stack to be
	# that item, with at least `uses` of it), and the rest of the procedure's supplies beside it so
	# the following steps work too. The step's own item goes in first: it always gets a slot.
	ReviewSetups.clear_hands(game)
	var need: Dictionary = Procedures.remaining_requirements(ailment, step_index)
	var item := String(step.get("item", ""))
	var slot: int = ReviewSetups.give(game, item, maxi(1, int(need.get(item, 1))))
	for kind in need.keys():
		if String(kind) != item:
			ReviewSetups.give(game, String(kind), int(need[kind]))
	p.selected = maxi(0, slot)
	p.set_flashlight(true)
	await tree.physics_frame

	var sys = game.surgery_for_table(ti)
	var why: String = String(sys.can_begin(p)) if sys != null else "no surgery system"
	print("[quick] %s, %s, step %d/%d '%s' -- %s in hand, aiming at '%s'%s" % [
		Procedures.patient(patient).get("name", patient), Procedures.ailment(ailment).get("name", ailment),
		step_index + 1, steps.size(), step.get("label", ""), Items.display_name(item), p.aim_id,
		"" if why == "" else (", BUT: " + why)])
	game.say("Quick start: %s. Press E." % step.get("label", ""), 6.0)


## Stand beside the site looking down at it, at the first distance from which you are actually
## aiming at the table (`want_id`). Too close and the camera is inside the table's aim proxy, which
## a ray cannot hit; too far and the site is out of INTERACT_RANGE. Where the sites sit varies by
## patient and by step, so this tries a few rather than trusting one number.
static func _stand(game: Node, p: Node, site: Vector3, table: Vector3, side: Vector3, want_id: String) -> void:
	var tree := game.get_tree()
	for d in STAND_TRIES:
		ReviewSetups.place(game, game._floor_at(Vector3(site.x, table.y, site.z) + side * float(d)), site)
		await tree.physics_frame
		await tree.physics_frame
		if String(p.aim_id) == want_id:
			return
	push_warning("[quick] stood at the table but ended up aiming at '%s', not '%s': E may do nothing" \
		% [p.aim_id, want_id])


## Which side of the table to stand on: the table's own +Z or -Z, whichever has more room. (The
## table's X runs along its length, so those are the two sides you can reach the patient from.)
static func _stand_side(game: Node, table: Vector3, tb: Basis) -> Vector3:
	var space: PhysicsDirectSpaceState3D = game.get_world_3d().direct_space_state
	var from: Vector3 = table + Vector3.UP * 1.2
	var best := tb * Vector3.BACK
	var best_d := -1.0
	for s in [tb * Vector3.BACK, tb * Vector3.FORWARD]:
		var q := PhysicsRayQueryParameters3D.create(from, from + s * SIDE_CLEARANCE_M)
		q.collision_mask = C.L_WORLD
		var hit := space.intersect_ray(q)
		var d: float = SIDE_CLEARANCE_M if hit.is_empty() else from.distance_to(hit.position)
		if d > best_d:
			best_d = d
			best = s
	return best


static func _arg(prefix: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with(prefix):
			return a.trim_prefix(prefix).strip_edges()
	return ""


## The ailments a quick start can stage: the ones a patient table takes (gunshot, amputation).
## The player-only and monster-only ones need a strapped body, which is what the review setups are
## for (--setup=graft, --setup=eyes).
static func _ailments() -> Array:
	return Procedures.patient_ailments()


static func _patients() -> Array:
	return Procedures.human_patients()


static func _step_ids(ailment: String) -> Array:
	var out := []
	for s in Procedures.steps(ailment):
		out.append(String((s as Dictionary).get("id", "")))
	return out


static func _complain(what: String) -> void:
	push_warning("[quick] %s" % what)
	print("[quick] %s" % what)
	print("[quick] starting the title menu instead.")
