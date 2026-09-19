extends Node
## Dissection (sweep 3) + GRAFTING part two: strapped monsters on the patient tables.
##
##   godot --headless --fixed-fps 60 --path . tools/dissectiontest.tscn
##   godot --path . --resolution 1280x720 tools/dissectiontest.tscn -- --shots   # tools/dissection_shots/
##
## Headless checks, solo in a normal hospital (seed 4242) with dev mode on, clocked in with the phone
## quiet and no roaming monsters, on the entrance building's OR patient tables. The brains, the brain
## harvest and the blender are gone (docs/GRAFTING_TRACHEA.md): a strapped monster has exactly one
## plan, its own extraction. The Hive's eye is tools/grafttest's; this file is the **Sonographer's
## Trachea Extraction** and the monster-table rules around it:
##
## the procedures data (the extractions are monster_only and never roll), a Sonographer strapped
## through the dev request, its body (sites, straps, flags), sedation wearing off and replicating,
## the local surgeon driving all three throat steps through the real surgery system with bot_input,
## the SHRIEK the freeing cut makes (a real noise event), the part's condition never going up, the
## trachea handed to the operator with condition -> quality -> value, the flatline, the database's
## `harvested` tier, the body staying until it is burned; a second Sonographer stirring and awake
## (thrash botches while operated, shrieks as noise); re-dosing from hands with the tolerance math
## and vials used (also while someone operates); a ruined trachea; the OR screen's model.
##
## --shots: windowed pictures in the generated hospital's OR: a Sonographer strapped and sedated, one
## awake and thrashing, the throat opened, the windpipe lifted, the OR monitor.

const DissectionScript := preload("res://scripts/dissection/dissection.gd")
const OrModel := preload("res://scripts/orscreen/or_screen_model.gd")
const RigLookScript := preload("res://scripts/dissection/monster_rig_look.gd")
const SHOT_DIR := "res://tools/dissection_shots"

var main: Node3D
var game: Game
var dev: Node
var me: Player
var t := 0.0
var shots := false
var _done := false
var _failures: Array = []


func _ready() -> void:
	shots = OS.get_cmdline_user_args().has("--shots")
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	game = main.game
	dev = game.dev
	if main.launching:
		await main.launched
	main.menu.hide_menu()
	Net.start_solo("Tester")
	if shots:
		await _shots()
	else:
		_data_checks()
		await _dev_mode()
	_finish()


func _physics_process(delta: float) -> void:
	t += delta
	if t > 1200.0 and not _done:
		_check(false, "timed out")
		_finish()


# =========================================================================
# data
# =========================================================================

func _data_checks() -> void:
	_check(Procedures.patient_ailments() == ["amputation", "gunshot"], "patient_ailments has neither extraction (%s)" % str(Procedures.patient_ailments()))
	_check(not Procedures.AILMENTS.has("dissection"), "the brain dissection ailment is gone")
	_check(Procedures.human_patients() == ["bob", "seal"] and Procedures.monster_patients() == ["hive", "sonographer"], "human and monster patients")
	var monster_rolled := false
	for s in 400:
		var r := Procedures.roll(s * 7 + 3, 1 + s % 5)
		if Procedures.is_monster(String(r.patient)) or Procedures.is_monster_only(String(r.ailment)):
			monster_rolled = true
	_check(not monster_rolled, "roll() never picks a monster or an extraction in 400 rolls")
	_check(Procedures.roll(4242, 1) == {"patient": Procedures.roll(4242, 1).patient, "ailment": Procedures.roll(4242, 1).ailment}, "roll is deterministic")
	# One plan per species: a Hive gives up an eye, a Sonographer its windpipe.
	_check(DissectionScript.extraction_for("hive") == "eye_extraction"
		and DissectionScript.extraction_for("sonographer") == "trachea_extraction", "one extraction per monster")
	var st: Array = Procedures.steps("trachea_extraction")
	_check(st.size() == 3
		and st[0].item == "scalpel" and st[0].game == "eye" and st[0].variant == "cut" and st[0].site == "throat"
		and st[1].item == "scalpel" and st[1].game == "eye" and st[1].variant == "snip" and st[1].site == "throat"
		and st[2].item == "forceps" and st[2].game == "eye" and st[2].variant == "scoop" and st[2].site == "throat",
		"trachea extraction steps: scalpel open, scalpel free, forceps lift (%s)" % str(st))
	_check(int(DissectionScript.FREE_STEP) == 1 and st.size() > 1 and String(st[1].id) == "free", "the freeing cut is step %d" % int(DissectionScript.FREE_STEP))
	_check(Procedures.is_monster_only("trachea_extraction") and Procedures.ailment("trachea_extraction").get("monster_only", false), "trachea_extraction is monster_only")
	_check(Procedures.is_monster_only("eye_extraction") and not Procedures.patient_ailments().has("eye_extraction"), "eye_extraction is monster_only too")
	_check(Procedures.requirements("trachea_extraction") == {"scalpel": 1, "forceps": 1}, "a trachea extraction needs a scalpel and forceps (%s)" % str(Procedures.requirements("trachea_extraction")))
	_check(is_equal_approx(DissectionScript.dose_amount(0), 0.6) and is_equal_approx(DissectionScript.dose_amount(1), 0.36)
		and is_equal_approx(DissectionScript.dose_amount(2), 0.216), "dose tolerance: 0.6, 0.36, 0.216")


# =========================================================================
# dev mode, on the hospital's OR tables
# =========================================================================

## A solo session on a normal hospital with dev mode on, god mode, no game over and no roaming
## monsters; clocked in with the phone quiet, so the OR tables stay free for the dev requests.
func _start_dev_session() -> bool:
	game.start_session(4242)
	while game.get_parent().has_node("WarmupCover"):
		await get_tree().process_frame
	await _seconds(0.5)
	me = game.local_player()
	me.bot_active = true
	game.set_dev_tools(true, me)
	_check(game.dev_on(), "set-up: dev mode on")
	dev.request("god", {"on": true})
	dev.request("no_game_over", {"on": true})
	dev.request("monsters_off", {"on": true})
	game.clock_in()
	var in_shift := await _until(func(): return game.phase == Game.Phase.SHIFT, 60.0)
	_check(in_shift, "set-up: clocked in")
	game.loop.first_called = true
	game.loop._end_call()
	game.loop.extra_done = true
	dev.request("clear_patient")
	await _frames(2)
	return in_shift and game.dev_on()


func _dev_mode() -> void:
	if not await _start_dev_session():
		return
	var dx: Node = game.dissection

	# ---- strap a Sonographer through the dev request
	dev.request("strap_monster", {"kind": "sonographer", "sedation": 1.0})
	await _frames(3)
	var c := _monster_case("sonographer")
	_check(not c.is_empty() and bool(c.get("monster", false)) and String(c.state) == "on_table",
		"the dev request straps a Sonographer to a table (%s)" % str(c))
	if c.is_empty():
		return
	_check(String(c.ailment_id) == "trachea_extraction", "a strapped Sonographer is a Trachea Extraction ('%s')" % String(c.get("ailment_id", "")))
	_check(dx.ailment_for(c, me) == "trachea_extraction", "its plan is its trachea (%s)" % dx.ailment_for(c, me))
	var table := int(c.table)
	var case_id := int(c.id)
	var body = game.body_for_table(table)
	_check(body != null and body is PatientBody and body.has_site("skull") and body.has_site("throat") and body.has_site("injection")
		and not body.has_site("brain") and not body.has_site("gunshot"), "the monster body is a PatientBody with sites injection, skull and throat, and no brain")
	_check(body != null and body.find_child("Straps", true, false) != null and body.find_child("Strap", true, false) != null, "the body has straps")
	_check(body != null and not body.site_section("skull").is_empty(), "a site section for the skull")
	await _check_rig_body(body, "sonographer")
	_check(dx.owns_case(c) and dx.owns_table(table), "dissection owns the case and its table")
	_check(game.loop.pay_for(c, 1) == 0, "a monster case pays nothing")

	# ---- sedation wears off
	var s0: float = dx.sedation(c)
	await _seconds(12.0)
	var s1: float = dx.sedation(c)
	var drop := s0 - s1
	_check(absf(drop - 12.0 / DissectionScript.SEDATION_SECONDS) < 0.01, "sedation falls 1/%d per second at rest (%.3f in 12 s)" % [int(DissectionScript.SEDATION_SECONDS), drop])
	_check(absf(float(c.flags.sedation) - snappedf(s1, DissectionScript.FLAG_STEP)) < 0.001, "the case flag holds it snapped to 0.05 (%.2f vs %.3f)" % [float(c.flags.sedation), s1])
	var ns: Dictionary = dx.net_state()
	_check(ns.has("s") and absf(float(ns.s[str(case_id)]) / 100.0 - s1) <= 0.011, "dx carries it in hundredths (%s)" % str(ns))
	_check(float(c.vitals) == 100.0, "nothing drains the trachea's condition (%.1f)" % float(c.vitals))
	_check(String(game._table_prompt(me, table)).begins_with("!") or String(game._table_prompt(me, table)).contains("sedation"),
		"the table prompt shows sedation ('%s')" % game._table_prompt(me, table))

	# ---- step 1: open the throat, with the real surgery system and bot_input
	_stand_at_table(table)
	game.hand_step_item(me, table)   # 2026-09-18: a step's tool is used from your hands
	await _frames(2)
	var prompt := String(game._table_prompt(me, table))
	_check(prompt.begins_with("Operate: Open the throat along the glowing line") and prompt.contains("sedation"), "operate prompt with sedation ('%s')" % prompt)
	game.surgery_bot_skill = 1.0
	var sys = game.surgery_for_table(table)
	game.hand_step_item(me, table)   # 2026-09-18: a step's tool is used from your hands
	game._proxy_used(game.table_interact_id(table), me)
	var began := await _until(func(): return sys.is_local_operating() and sys.mg != null, 5.0)
	_check(began and String(sys.mg.get("variant")) == "cut" and String(sys.mg.get("part_site")) == "throat",
		"E with the scalpel opens the throat (variant cut on the throat)")
	var ok1 := await _until(func(): return int(c.get("step_index", 0)) >= 1, 60.0)
	_check(ok1 and bool(c.flags.get("eye_cut", false)), "the opening cut finishes (flags %s)" % str(c.flags))
	await _frames(2)
	_check(float(c.vitals) <= 100.0 and float(c.vitals) >= 99.0, "condition does not go up after the step (%.1f)" % float(c.vitals))

	# ---- the OR screen's model for a strapped monster
	_check_or_model(case_id)

	# ---- a few botches, then step 2: the cut that frees the windpipe, and its shriek
	game.surgery_botch(7.0, "test", table)
	await _frames(3)
	var cond_before := float(c.vitals)
	await _seconds(0.5)
	game.hand_step_item(me, table)
	game._proxy_used(game.table_interact_id(table), me)
	var began2 := await _until(func(): return sys.is_local_operating() and sys.mg != null and String(sys.mg.get("variant")) == "snip", 5.0)
	_check(began2, "E again cuts the windpipe free (variant snip)")
	var ok2 := await _until(func(): return int(c.get("step_index", 0)) >= 2, 60.0)
	_check(ok2 and bool(c.flags.get("eye_removed", false)), "the freeing cut finishes (flags %s)" % str(c.flags))
	await _frames(4)
	# GRAFTING part two: the last extraction cut makes a real noise, loud enough to pull monsters.
	var ls: Dictionary = dx.last_shriek
	_check(not ls.is_empty() and float(ls.get("loudness", 0.0)) >= 1.0,
		"the freeing cut shrieks (loudness %.2f)" % float(ls.get("loudness", -1.0)))
	var heard := false
	for n in game.recent_noises(5.0):
		if String(n.kind) == "shriek" and float(n.loudness) >= 1.0 and absf(float(n.time) - float(ls.get("time", -99.0))) < 0.05:
			heard = true
	_check(heard, "the shriek is a real noise event monsters can hear (%d recent noises)" % game.recent_noises(5.0).size())

	# ---- step 3: lift the trachea out, and the case is won
	await _seconds(0.5)
	game.hand_step_item(me, table)
	game._proxy_used(game.table_interact_id(table), me)
	var began3 := await _until(func(): return sys.is_local_operating() and sys.mg != null and String(sys.mg.get("variant")) == "scoop", 5.0)
	_check(began3, "then the forceps lift (variant scoop)")
	var ok3 := await _until(func(): return String(c.get("state", "")) != "on_table", 60.0)
	_check(ok3 and String(c.state) == "stable" and bool(c.flags.get("eye_out", false)), "the lift wins the case (state %s, flags %s)" % [String(c.get("state", "")), str(c.flags)])
	var lp: Dictionary = dx.last_part
	_check(not lp.is_empty() and String(lp.kind) == "trachea_sonographer" and absf(float(lp.quality) - cond_before / 100.0) < 0.011,
		"the trachea is handed over: %s quality %.2f (condition %.1f)" % [str(lp.get("kind", "")), float(lp.get("quality", -1.0)), cond_before])
	var in_hand := -1
	for i in me.slots.size():
		if String(me.slots[i].kind) == "trachea_sonographer":
			in_hand = i
	_check(in_hand >= 0, "it came out in the operator's hand (peer %d)" % int(lp.get("peer", 0)))
	var want_value := maxi(1, roundi(160.0 * clampf(cond_before / 100.0, 0.0, 1.0)))
	_check(in_hand >= 0 and me.slots[in_hand].has("bt") and absi(int(me.slots[in_hand].get("v", 0)) - want_value) <= 1,
		"a live trachea with a spoil clock, worth %d at %.0f%% (%d)" % [want_value, cond_before, int(me.slots[in_hand].get("v", 0)) if in_hand >= 0 else -1])
	_check(absf(float(c.vitals) - cond_before) < 0.01, "the finished case keeps the condition, not the step bonus (%.1f)" % float(c.vitals))
	_check(game.db_record("sonographer").harvested, "the database's third tier: the Sonographer is harvested")
	await _frames(3)
	_check(body != null and is_instance_valid(body) and bool(body.get("_flat")), "the monster flatlines on the table")
	# Patient exits: the dead monster is a body waiting for the furnace now. Lifting it takes empty
	# hands (the scalpel and forceps are still in them: tools are never used up).
	me.slots = Player.empty_slots()
	_check(String(game._table_prompt(me, table)).begins_with("Hold E: lift"), "table prompt after: '%s'" % game._table_prompt(me, table))
	var gone := await _until(func(): return game.case_by_id(case_id).is_empty(), DissectionScript.REMOVE_AFTER + 3.0)
	_check(not gone, "the finished case stays on the table as a body")
	await _burn(case_id)
	_check(game.case_by_id(case_id).is_empty(), "burned in the furnace, the case is gone")

	# ---- a second Sonographer: stirring, awake, thrashing, shrieking
	var did: int = dx.dev_strap("sonographer", 0.6, table)
	await _frames(3)
	var d := game.case_by_id(did)
	_check(not d.is_empty() and DissectionScript.sedation_state(dx.sedation(d)) == "stirring", "0.6 is stirring")
	_check(sys._stirs_now() if sys.mg != null else true, "the surgery system's stir code sees it")
	dx.set_sedation(did, 0.3)
	await _frames(2)
	_check(DissectionScript.sedation_state(dx.sedation(d)) == "awake", "0.3 is awake")
	var shrieked := await _until(func():
		for n in game.recent_noises(0.5):
			if String(n.kind) == "shriek" and float(n.loudness) >= 0.69:
				return true
		return false, 8.0)
	_check(shrieked, "an awake monster shrieks as noise 0.7")
	var v0 := float(d.vitals)
	await _seconds(4.0)
	_check(float(d.vitals) == v0, "no thrash botches while nobody operates (%.1f)" % float(d.vitals))
	var tb = game.body_for_table(table)
	await _check_rig_body(tb, "sonographer")
	_check(tb != null and float(tb.get("_sedation")) < 0.35, "the body gets the awake sedation (%.2f)" % (float(tb.get("_sedation")) if tb != null else -1.0))
	# Operate while awake: about 1.5 every 3 s from thrashing.
	game.surgery_bot_skill = -1.0   # hands off: only the thrashing botches
	_stand_at_table(table)
	game.hand_step_item(me, table)
	sys.begin(me)
	var began4 := await _until(func(): return sys.is_local_operating(), 3.0)
	var v1 := float(d.vitals)
	dx.set_sedation(did, 0.3)
	await _seconds(9.3)
	var lost := v1 - float(d.vitals)
	_check(began4 and lost >= 4.4 and lost <= 4.6, "awake and operated: 1.5 every 3 s (lost %.1f in 9.3 s)" % lost)

	# ---- re-dosing from hands, while operating
	me.take_into("anesthetic", 3)
	await _frames(1)
	var p2 := String(game._table_prompt(me, table))
	_check(p2.begins_with("Re-dose The Sonographer") and p2.contains("sedation"), "holding anesthetic: '%s'" % p2)
	dx.set_sedation(did, 0.2)
	var before: float = dx.sedation(d)
	game.hand_step_item(me, table)   # 2026-09-18: a step's tool is used from your hands
	game._proxy_used(game.table_interact_id(table), me)
	await _frames(1)
	var after: float = dx.sedation(d)
	_check(absf((after - before) - 0.6) < 0.01 and int(d.get("doses", 0)) == 1, "first dose +0.6 (%.3f -> %.3f)" % [before, after])
	_check(_vials() == 2, "one vial used (%d left)" % _vials())
	_check(sys.operator_id == me.peer_id, "re-dosing did not interrupt the operation")
	dx.set_sedation(did, 0.2)
	game.hand_step_item(me, table)   # 2026-09-18: a step's tool is used from your hands
	game._proxy_used(game.table_interact_id(table), me)
	await _frames(1)
	_check(absf(dx.sedation(d) - 0.56) < 0.01 and _vials() == 1, "second dose +0.36 (%.3f, %d vials)" % [dx.sedation(d), _vials()])
	dx.set_sedation(did, 0.9)
	game.hand_step_item(me, table)   # 2026-09-18: a step's tool is used from your hands
	game._proxy_used(game.table_interact_id(table), me)
	await _frames(1)
	_check(absf(dx.sedation(d) - 1.0) < 0.003 and _vials() == 0 and int(d.doses) == 3, "third dose caps at 1.0 and the last vial is gone (%.3f, %d vials, %d doses)" % [dx.sedation(d), _vials(), int(d.get("doses", 0))])
	_check(not String(game._table_prompt(me, table)).begins_with("Re-dose"), "no vials: back to the operate prompt")

	# ---- a ruined trachea
	sys.local_operator_exit()
	await _frames(3)
	d.vitals = 2.0
	game.surgery_botch(3.0, "test", table)
	await _frames(3)
	_check(String(d.state) == "dead", "condition 0: the case is lost (%s)" % String(d.state))
	_check(String(game.message).contains("ruined"), "'%s'" % game.message)
	await _burn(did)
	_check(game.case_by_id(did).is_empty(), "the ruined case's body burns too")
	game.surgery_bot_skill = -1.0


## The wall monitor's panel for a strapped Sonographer: the THROAT tag, the three steps with the
## first one done, and the tools the rest of the extraction needs.
func _check_or_model(case_id: int) -> void:
	var model: Dictionary = OrModel.build(game)
	var panel := {}
	for p in model.panels:
		if int(p.id) == case_id:
			panel = p
	_check(not panel.is_empty() and bool(panel.get("monster", false)), "the OR screen model marks the monster panel")
	if panel.is_empty():
		return
	_check(String(panel.part) == "THROAT" and not bool(panel.get("eye", true)), "the panel's part tag is THROAT ('%s')" % String(panel.part))
	_check(String(panel.ailment_name).begins_with("Trachea Extraction") and String(panel.code) == "TX", "the panel names the Trachea Extraction ('%s')" % String(panel.ailment_name))
	_check(panel.steps.size() == 3 and String(panel.steps[0].label) == "Open the throat along the glowing line"
		and String(panel.steps[0].state) == "done" and String(panel.steps[1].state) == "current" and String(panel.steps[2].state) == "todo",
		"the step list is the throat's, one done (%s)" % str(panel.steps))
	var kinds := []
	for sp in panel.supplies:
		kinds.append(String(sp.kind))
	_check(kinds.has("scalpel") and kinds.has("forceps"), "the supplies list the extraction's tools (%s)" % str(kinds))


## The strapped body wears the walking monster's rig (make_lying) with exactly one head, the one that
## opens, sitting where the rig's head bone is (RigLook's measured constant), and fits the table.
func _check_rig_body(body, kind: String) -> void:
	if body == null:
		_check(false, "%s: no body" % kind)
		return
	var lying := (body as Node).find_child("Lying", true, false) as Node3D
	_check(lying != null, "%s: the body is the walking monster's lying rig" % kind)
	if lying == null:
		return
	await _frames(3)
	var skel := lying.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var heads: Array = (body as Node).find_children("HeadRoot", "", true, false)
	if skel.get_node_or_null("HivePoser") != null or skel.get_node_or_null("SonoPoser") != null:
		# The stylized Hive and Sonographer (hive_rig.gd, sonographer_rig.gd): their own heads show; the dissection head is
		# built hidden, only to place the sites, and sits at the head bone.
		var own := lying.find_child("Head", true, false) as Node3D
		_check(own != null and own.is_visible_in_tree() and heads.size() == 1 and not (heads[0] as Node3D).is_visible_in_tree(),
			"%s: its own head shows, the dissection head is hidden" % kind)
		var hb := skel.find_bone("head")
		var bone_at: Vector3 = skel.global_transform * skel.get_bone_global_pose(hb).origin
		_check(heads.size() == 1 and (heads[0] as Node3D).global_position.distance_to(bone_at) < 0.2,
			"%s: the dissection sites sit at its head (%.2f m)" % [kind, (heads[0] as Node3D).global_position.distance_to(bone_at) if heads.size() == 1 else -1.0])
		for s in ["skull", "throat", "injection"]:
			_check(body.anchors.has(s), "%s: site %s" % [kind, s])
		var lo := Vector3.INF
		var hi := -Vector3.INF
		var inv := (body as Node3D).global_transform.affine_inverse()
		# The trunk and legs (the arms read back in their rest A-pose here: the poser brings them in
		# during the skeleton update, and bone poses read outside it are the unmodified ones).
		for bn in ["hips", "spine", "chest", "upperchest", "neck", "head", "thigh.L", "shin.L", "foot.L", "thigh.R", "shin.R", "foot.R"]:
			var bi := skel.find_bone(bn)
			var p: Vector3 = inv * (skel.global_transform * skel.get_bone_global_pose(bi).origin)
			lo = lo.min(p)
			hi = hi.max(p)
		_check(lo.x > -1.0 and hi.x < 1.0 and lo.z > -0.36 and hi.z < 0.36 and lo.y > -0.05 and hi.y < 0.2,
			"%s: the body lies on the table (bones %s .. %s)" % [kind, str(lo), str(hi)])
		return
	var rig_head := skel.get_node_or_null("Head") as Node3D
	_check(rig_head != null and not rig_head.visible and heads.size() == 1 and (heads[0] as Node3D).is_visible_in_tree(),
		"%s: one head (the rig's own is hidden, the openable one shows)" % kind)
	var want: Vector3 = RigLookScript.RIG[kind].head_bone
	var got := lying.global_transform.affine_inverse() * rig_head.global_position if rig_head != null else Vector3.INF
	_check(got.distance_to(want) < 0.02, "%s: the rig's head bone is where RigLook expects it (%s vs %s)" % [kind, str(got), str(want)])
	var box := AABB()
	var first := true
	for mi in (body as Node).find_children("*", "MeshInstance3D", true, false):
		var g := mi as MeshInstance3D
		if g.mesh == null or not g.is_visible_in_tree() or g.skin != null or g.get_parent().name == "Straps" or String(g.get_parent().name).begins_with("StrapAt"):
			continue
		var a: AABB = (body as Node3D).global_transform.affine_inverse() * g.global_transform * g.mesh.get_aabb()
		box = a if first else box.merge(a)
		first = false
	# Loose (rotated mesh boxes): the table top is 2.0 x 0.7 m.
	_check(box.position.x > -1.02 and box.end.x < 1.02 and box.position.z > -0.4 and box.end.z < 0.4,
		"%s: the body lies on the table (%s .. %s)" % [kind, str(box.position), str(box.end)])


func _monster_case(kind: String) -> Dictionary:
	for c in game.cases:
		if String(c.get("patient_id", "")) == kind:
			return c
	return {}


func _vials() -> int:
	var n := 0
	for s in me.slots:
		if String(s.kind) == "anesthetic":
			n += int(s.count)
	return n


func _stand_at_table(table: int) -> void:
	var tp: Vector3 = game.table_position(table)
	me.teleport(game._floor_at(tp + Vector3(0, 0, 1.0).rotated(Vector3.UP, game.table_yaw_of(table))))
	me.bot_move = Vector2.ZERO


# =========================================================================
# shots
# =========================================================================

func _shots() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SHOT_DIR))
	game.start_session(4242)
	await _seconds(2.0)
	me = game.local_player()
	me.bot_active = true
	game.begin_shift()
	await _seconds(1.0)
	for m in game.monsters.values():
		m.global_position += Vector3(0, -80, 0)
	me.invuln = 99999.0
	var dx: Node = game.dissection
	var tables: Array = game.patient_tables
	var t0 := int(tables[0].index)
	var t1 := int(tables[1].index) if tables.size() > 1 else t0
	var wid: int = dx.dev_strap("sonographer", 1.0, t0)
	dx.dev_strap("sonographer", 0.15, t1)
	await _seconds(1.5)
	# 01/02: sedated and thrashing, each from beside its table.
	for pair in [[t0, "01_sonographer_strapped"], [t1, "02_sonographer_thrashing"]]:
		var tb := int(pair[0])
		var tp: Vector3 = game.table_position(tb)
		var yaw: float = game.table_yaw_of(tb)
		me.teleport(game._floor_at(tp + Vector3(-0.6, 0, 1.35).rotated(Vector3.UP, yaw)))
		await _frames(2)
		_look_at(tp + Vector3(-0.35, 0.9, 0).rotated(Vector3.UP, yaw))
		await _seconds(1.2)
		await _shot(String(pair[1]))
		# Close on the head and throat.
		me.teleport(game._floor_at(tp + Vector3(-0.45, 0, 1.0).rotated(Vector3.UP, yaw)))
		await _frames(2)
		_look_at(tp + Vector3(-0.72, 0.95, 0).rotated(Vector3.UP, yaw))
		await _seconds(0.6)
		await _shot(String(pair[1]) + "_head")
	# 03: opening the throat, the operator's view.
	game.surgery_bot_skill = 0.6
	var sys = game.surgery_for_table(t0)
	var tp0: Vector3 = game.table_position(t0)
	me.teleport(game._floor_at(tp0 + Vector3(0, 0, 1.0).rotated(Vector3.UP, game.table_yaw_of(t0))))
	await _frames(2)
	await _operate(t0)
	await _seconds(5.0)
	await _shot("03_throat_open_mid")
	await _until(func(): return int(game.case_by_id(wid).get("step_index", 0)) >= 1, 60.0)
	await _seconds(1.2)
	# 04: the opened throat from beside the table.
	me.teleport(game._floor_at(tp0 + Vector3(-1.4, 0, 0.55).rotated(Vector3.UP, game.table_yaw_of(t0))))
	await _frames(2)
	_look_at(tp0 + Vector3(-0.72, 0.95, 0).rotated(Vector3.UP, game.table_yaw_of(t0)))
	await _seconds(1.0)
	await _shot("04_throat_cut")
	# 07: the OR monitor with both monster panels (the THROAT tag, condition, sedation).
	if game.or_screen != null and game.or_screen.mounted():
		var sc: Vector3 = game.or_screen.screen_centre()
		var nrm: Vector3 = game.or_screen.screen_normal()
		var feet := sc + nrm * 1.9
		feet.y = game.table_pos().y
		me.teleport(feet)
		me.set_flashlight(false)
		await _frames(2)
		_look_at(sc)
		game.or_screen.refresh_now()
		await _seconds(1.0)
		await _shot("07_or_screen")
		me.set_flashlight(true)
	# 05/06: the freeing cut (which shrieks), then the forceps lifting the windpipe out.
	me.teleport(game._floor_at(tp0 + Vector3(0, 0, 1.0).rotated(Vector3.UP, game.table_yaw_of(t0))))
	await _frames(2)
	await _operate(t0)
	await _seconds(2.4)
	await _shot("05_windpipe_freed")
	await _until(func(): return int(game.case_by_id(wid).get("step_index", 0)) >= 2, 60.0)
	me.teleport(game._floor_at(tp0 + Vector3(0, 0, 1.0).rotated(Vector3.UP, game.table_yaw_of(t0))))
	await _frames(2)
	await _operate(t0)
	await _seconds(2.4)
	await _shot("06_trachea_lift")
	await _until(func(): return String(game.case_by_id(wid).get("state", "")) != "on_table", 60.0)
	await _seconds(4.0)
	print("[dissectiontest] shots done")


## Shots: put the step's tool in hand and press E at the table (the press also picks the monster's
## own plan, so it goes through game._proxy_used rather than straight into the surgery system).
func _operate(table: int) -> void:
	game.hand_step_item(me, table)
	await _frames(2)
	game._proxy_used(game.table_interact_id(table), me)
	await _frames(2)
	game.hand_step_item(me, table)
	await _frames(2)
	game._proxy_used(game.table_interact_id(table), me)
	await _frames(2)


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := "%s/%s.png" % [SHOT_DIR, name]
	img.save_png(ProjectSettings.globalize_path(path))
	print("[dissectiontest] wrote %s" % path)


func _look_at(target: Vector3) -> void:
	var eye := me.global_position + Vector3.UP * C.EYE_H
	var dv := target - eye
	me.bot_yaw = atan2(-dv.x, -dv.z)
	me.bot_pitch = clampf(atan2(dv.y, Vector2(dv.x, dv.z).length()), -1.2, 1.2)


# =========================================================================
# helpers
# =========================================================================

func _check(ok: bool, what: String) -> void:
	print("[dissectiontest] t=%.1f %s  %s" % [t, "PASS" if ok else "FAIL", what])
	if not ok:
		_failures.append(what)


func _finish() -> void:
	if _done:
		return
	_done = true
	print("[dissectiontest] ------------------------------------------")
	print("[dissectiontest] result=%s failures=%d" % ["PASS" if _failures.is_empty() else "FAIL", _failures.size()])
	for f in _failures:
		print("[dissectiontest]   FAILED: ", f)
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


## Patient exits: lift a dead case's body and put it in the furnace (hands emptied for the lift).
func _burn(case_id: int) -> void:
	var kept: Array = me.slots.duplicate(true)
	me.slots = Player.empty_slots()
	game.corpses.lift(me, case_id)
	game.corpses.cremate(me)
	me.slots = kept
	await _frames(3)
