extends Node
## GRAFTING chunk C smoke-look screenshots, into tools/graft_shots/. Run minimized (RULES.md
## "Reviews"): the shots come from the viewport, so nothing ever takes focus.
##
##   tools\review.bat 2 "SMOKE" -Scene res://tools/graftsurgeryshot.tscn
##
## The whole loop once, solo: the stand with a vat beside an OR table, you strapped down looking up
## at Dr. Botsworth working on your eye, the swapped part in third person and in the Personnel
## mirror, its glow while the ability runs, and the wash down the edge of your own view.
##
## `-- --part=throat` runs GRAFTING part two instead: a Sonographer's trachea, Trachea Grafting, the
## violet throat and Echo. The shots land in tools/graft_shots/throat_*.

const SHOT_DIR := "res://tools/graft_shots"
## "eye" (grafting part one) or "throat" (part two), from `--part=`.
var site := "eye"
var part_kind := "eye_hive"
var ability := "hive_in"
var prefix := ""
var main: Node3D
var game: Game
var dev: Node
var me: Player
var bw: Player
var t := 0.0


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("--part="):
			site = String(a).split("=")[1]
	if site != "throat":
		site = "eye"
	part_kind = String(Eyes.MONSTER_PART.get(site, "eye_hive"))
	ability = String(Grafts.PART_ABILITY.get(part_kind, "hive_in"))
	prefix = "throat_" if site == "throat" else ""
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	game = main.game
	dev = game.dev
	main.menu.hide_menu()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SHOT_DIR))
	Net.start_solo("Zach")
	game.start_session(4242)
	while game.get_parent().has_node("WarmupCover"):
		await get_tree().process_frame
	await _seconds(1.0)
	me = game.local_player()
	me.bot_active = true
	game.set_dev_tools(true, me)
	dev.request("monsters_off", {"on": true})
	dev.request("no_game_over", {"on": true})
	dev.request("god", {"on": true})
	game.clock_in()
	await _until(func(): return game.phase == Game.Phase.SHIFT, 90.0)
	game.loop._end_call()
	game.loop.first_called = true
	game.loop.extra_done = true
	dev.request("clear_patient")
	await _run()
	get_tree().quit(0)


func _physics_process(delta: float) -> void:
	t += delta


## Every Light3D within `r` of `at`, brightest first: what is actually lighting the work site.
## The graft read far brighter than the Hive's eye extraction, and this is how it was pinned down.
func _lights_near(at: Vector3, r := 3.0) -> void:
	var rows: Array = []
	for n in get_tree().root.find_children("*", "Light3D", true, false):
		var l := n as Light3D
		if not l.is_visible_in_tree() or l.light_energy <= 0.001:
			continue
		var d := l.global_position.distance_to(at)
		if d <= r:
			rows.append([l.light_energy / maxf(d * d, 0.01), String(l.get_path()), l.light_energy, d])
	rows.sort_custom(func(a, b): return a[0] > b[0])
	print("[graftshot] lights within %.1f m of the site:" % r)
	for row in rows:
		print("[graftshot]    %s  energy %.2f  at %.2f m" % [row[1], row[2], row[3]])


## The Hive's Eyeball Extraction cut, for comparison: the same eye minigame on a strapped monster.
func _hive_reference() -> void:
	dev.request("strap_monster", {"kind": "hive", "sedation": 1.0})
	await _seconds(1.0)
	var c := {}
	for cc in game.cases:
		if String(cc.get("patient_id", "")) == "hive":
			c = cc
	if c.is_empty():
		print("[graftshot] no strapped Hive for the reference shot")
		return
	var table := int(c.table)
	var hyaw: float = game.table_yaw_of(table)
	var htp: Vector3 = game.table_position(table)
	_stand(htp + Vector3(0, 0, 1.0).rotated(Vector3.UP, hyaw))
	for i in me.slots.size():
		me.slots[i] = Player.empty_slot()
	game.give_hand(me, "scalpel", 1)
	me.selected = _slot(me, "scalpel")
	await _seconds(0.6)
	game.surgery_bot_skill = 1.0
	var sys: Node = game.surgery_for_table(table)
	game._proxy_used(game.table_interact_id(table), me)
	var ok := await _until(func(): return sys.mg != null and String(sys.mg.get("variant") if sys.mg.get("variant") != null else "") == "cut", 10.0)
	print("[graftshot] hive extraction cut began=", ok)
	await _seconds(2.0)
	await _shot("40_hive_cut_operating")
	if sys.mg != null:
		_lights_near(sys.mg.global_position)
	# 2026-09-19: the whole extraction, for the new last step -- the eye into the vat on the table.
	var hv: int = game.vats.place_of_table(table)
	var hive_vat: Node = null
	if hv >= 0:
		hive_vat = game._spawn_item("specimen_vat", 1,
			Transform3D(Basis(Vector3.UP, hyaw), game.vats.places[hv].position as Vector3), WorldItem.State.LOOSE)
	await _shot("41_hive_vat_on_table")
	var n := 42
	for step in [["eye_spoon", "scoop", 1], ["scalpel", "snip", 2], ["forceps", "place", 3]]:
		for i in me.slots.size():
			me.slots[i] = Player.empty_slot()
		game.give_hand(me, String(step[0]), 1)
		me.selected = _slot(me, String(step[0]))
		_stand(htp + Vector3(0, 0, 1.0).rotated(Vector3.UP, hyaw))   # the bot drifts between steps
		_look_at(htp + Vector3(0, 1.0, 0))
		game.dissection.set_sedation(int(c.id), 1.0)   # a woken Hive thrashes the operator off
		await _seconds(0.6)
		game._proxy_used(game.table_interact_id(table), me)
		var began := await _until(func(): return sys.mg != null and String(sys.mg.get("variant") if sys.mg.get("variant") != null else "") == String(step[1]), 10.0)
		print("[graftshot] hive step %s began=%s (case step %d, prompt '%s')"
			% [String(step[1]), str(began), int(game.case_on_table(table).get("step_index", -1)),
				String(game._table_prompt(me, table))])
		if String(step[1]) == "place":
			await _seconds(0.7)
			await _shot("43b_hive_place_start")       # the loose eye, the vat's big ring, the hint
			await _until(func(): return _seat_stage(sys) >= 1, 30.0)
			await _seconds(0.35)
			await _shot("44_hive_eye_lifted_out")     # in the jaws, on its way over
			await _until(func(): return _seat_stage(sys) >= 2, 30.0)
			await _shot("45_hive_eye_into_the_vat")   # let go over the vat: it drops in
		else:
			await _seconds(2.0)
			await _shot("%d_hive_%s" % [n, String(step[1])])
		n += 1
		# Keep it sedated and keep operating: a shot's pause is long enough for a Hive to come round.
		var end := t + 90.0
		while t < end and int(game.case_on_table(table).get("step_index", -1)) == int(step[2]):
			game.dissection.set_sedation(int(c.id), 1.0)
			if not sys.is_local_operating():
				game._proxy_used(game.table_interact_id(table), me)
			await _seconds(0.5)
		await _seconds(0.8)
	print("[graftshot] hive vat holds: ", String(hive_vat.x) if hive_vat != null and is_instance_valid(hive_vat) else "no vat")
	await _seconds(1.0)
	await _shot("46_hive_done")
	if hive_vat != null and is_instance_valid(hive_vat):
		game.world_items.erase(hive_vat.item_id)
		hive_vat.queue_free()
	if sys.mg != null:
		sys.local_operator_exit()
	game.surgery_bot_skill = -1.0
	await _seconds(0.6)
	dev.request("clear_patient")
	for i in me.slots.size():
		me.slots[i] = Player.empty_slot()
	await _seconds(1.0)


func _run() -> void:
	await _hive_reference()
	var vats: Node = game.vats
	var ti: int = game.free_patient_table()
	var si: int = vats.place_of_table(ti)
	var yaw: float = game.table_yaw_of(ti)
	var tb := Basis(Vector3.UP, yaw)
	var tp: Vector3 = game.table_position(ti)
	# ---- 50: the stand beside the table, with a vat on it
	var stand_at: Vector3 = vats.places[si].position
	var vat: Node = game._spawn_item("specimen_vat", 1, Transform3D(tb, stand_at), WorldItem.State.LOOSE)
	vat.x = Eyes.pack(part_kind, "", 0.0, 160 if site == "throat" else 120)
	me.flashlight_on = true
	await _seconds(1.0)
	_stand(stand_at + tb * Vector3(0.0, 0.0, 1.3))
	_look_at(stand_at + Vector3(0, 0.1, 0))
	await _seconds(1.0)
	await _shot("50_stand_with_vat")
	_stand(tp + tb * Vector3(2.2, 0.0, 1.8))
	_look_at(tp + Vector3(0, 1.0, 0))
	await _seconds(1.0)
	await _shot("51_table_and_stand")
	# ---- 70/71: the table itself, from the side and three-quarter on, with the room around it
	_stand(tp + tb * Vector3(0.0, 0.0, 2.4))
	_look_at(tp + Vector3(0, 0.85, 0))
	await _seconds(1.0)
	await _shot("70_table_side")
	_stand(tp + tb * Vector3(2.0, 0.0, 2.0))
	_look_at(tp + Vector3(0, 0.85, 0))
	await _seconds(1.0)
	await _shot("71_table_three_quarter")

	# ---- strapped down, Dr. Botsworth operating
	me.teleport(game._floor_at(tp + tb * Vector3(0, 0, 1.2)))
	await _seconds(0.4)
	game.strap_in(me, ti)
	await _seconds(0.8)
	print("[graftshot] strapped=", me.strapped(), " table=", game.player_table.get("index", -1))
	# ---- 72: the body on the table from a standing player's eyes, beside it
	var fc0: Camera3D = main.dev_panel.free_cam
	fc0.start(game)
	fc0.set("flying", false)
	me.dev_input_held = false
	fc0.global_position = tp + tb * Vector3(0.55, C.EYE_H, 1.25)
	fc0.look_at(tp + tb * Vector3(-0.25, 0.97, 0.0), Vector3.UP)
	fc0.fov = 70.0
	await _seconds(1.0)
	await _shot("72_patient_on_table")
	fc0.global_position = tp + tb * Vector3(-1.5, C.EYE_H, 1.1)
	fc0.look_at(tp + tb * Vector3(-0.4, 0.97, 0.1), Vector3.UP)
	await _seconds(0.5)
	await _shot("73_patient_head_end")
	fc0.stop()
	await _seconds(0.5)
	dev.control_botsworth()
	await _seconds(0.8)
	bw = dev.possessed_player()
	if bw == null:
		print("[graftshot] no Botsworth")
		return
	bw.bot_active = true
	bw.teleport(game._floor_at(tp + tb * Vector3(-0.3, 0.0, 1.0)))
	bw.bot_move = Vector2.ZERO
	await _seconds(0.5)
	var ps: Node = game.player_surgery
	var sys: Node = ps.surgery
	sys.bot_skill = 1.0
	var n := 52
	var plan := []
	for st in Procedures.steps(String(Grafts.SITE_AILMENT.get(site, "eye_graft"))):
		plan.append([String(st.get("item", "")), String(st.get("variant", ""))])
	for step in plan:
		for i in bw.slots.size():
			bw.slots[i] = Player.empty_slot()
		game.give_hand(bw, String(step[0]), 1)
		bw.selected = _slot(bw, String(step[0]))
		await _seconds(0.4)
		game._proxy_used(game.table_interact_id(ti), bw)
		var ok := await _until(func(): return sys.mg != null and String(sys.mg.get("variant") if sys.mg.get("variant") != null else "") == String(step[1]), 10.0)
		print("[graftshot] step %s began=%s" % [String(step[1]), str(ok)])
		await _seconds(0.9 if String(step[1]) == "grab" else 2.0)
		await _shot("%d_%s_operating" % [n, String(step[1])])
		_still_probe(ps, String(step[1]))
		if String(step[1]) == "cut" and sys.mg != null:
			_lights_near(sys.mg.global_position)
		n += 1
		if String(step[1]) == "grab":
			# The forceps step: the eye in the vat, the drag across, and the moment it goes in.
			await _shot("56a_grab_in_the_vat")        # the eye in the vat, both rings up
			await _until(func(): return _seat_stage(sys) >= 1, 20.0)
			await _seconds(0.5)
			await _shot("56b_grab_carry")             # dragging it across
			await _until(func(): return _seat_stage(sys) >= 2, 30.0)
			await _shot("56c_grab_seating")           # let go over the socket: in it goes
			_still_probe(ps, "seat")
			await _until(func(): return sys.mg == null or bool(sys.mg.get("done")), 20.0)
			await _shot("56d_grab_seated")
			_still_probe(ps, "seated")
		# What the patient sees: their own camera, looking up, while the step plays.
		var cam: Camera3D = me.camera
		var was: Camera3D = get_viewport().get_camera_3d()
		cam.make_current()
		await _seconds(0.6)
		await _shot("%d_%s_patient_view" % [n, String(step[1])])
		n += 1
		if was != null:
			was.make_current()
		var want := String(step[1])
		await _until(func(): return ps.case.is_empty() or sys.mg == null or String(sys.mg.get("variant") if sys.mg.get("variant") != null else "") != want or bool(sys.mg.get("done")), 90.0)
		await _seconds(0.6)
	await _until(func(): return game.grafts.graft_of(me.peer_id, site) == part_kind, 20.0)
	print("[graftshot] graft=", game.grafts.graft_of(me.peer_id, site), " vat=", String(vat.x),
		" slot=", game.brains.slot_of(me.peer_id, ability))

	# ---- back on your feet, and what everyone sees
	game.get_up_from_table(me)
	dev.control_botsworth()   # back into your own body
	await _seconds(1.0)
	me.bot_active = true
	_stand(tp + tb * Vector3(0.0, 0.0, 2.0))
	me.bot_yaw = yaw + PI * 0.5
	await _seconds(6.0)   # let the new-ability card close itself
	var hum = game.grafts._human_of(me)
	var gn = GraftThroat.node_on(hum) if site == "throat" else GraftEye.node_on(hum)
	print("[graftshot] the graft on the body: ", gn)
	var wash: Control = main.graft_view.throat_wash if site == "throat" else main.graft_view.wash
	print("[graftshot] lock=", game.grafts.local_lock(site), " driving=", game.driving_player())
	await _shot("60_first_person_tint")
	print("[graftshot] tint drawn: ", wash.showing)
	await _fire(1.5)
	print("[graftshot] lock hot=", game.grafts.local_lock(site), " tint drawn: ", wash.showing)
	await _shot("63_first_person_tint_ability")
	_hive_hold = false

	# ---- third person: what a teammate sees of your throat, from Dr. Botsworth's eyes
	dev.control_botsworth()
	await _seconds(1.2)
	var b2 = dev.possessed_player()
	if b2 != null:
		b2.bot_active = true
		b2.flashlight_on = true
		var mp2 := me.global_position as Vector3
		b2.teleport(game._floor_at(mp2 + Vector3(0.0, 0.0, 1.1)))
		b2.bot_move = Vector2.ZERO
		var eye2: Vector3 = (b2.global_position as Vector3) + Vector3.UP * C.EYE_H
		var d2: Vector3 = (mp2 + Vector3(0, 1.45, 0)) - eye2
		b2.bot_yaw = atan2(-d2.x, -d2.z)
		b2.bot_pitch = clampf(atan2(d2.y, Vector2(d2.x, d2.z).length()), -1.2, 1.2)
		await _seconds(2.0)
		await _shot("67_third_person")
		b2.apply_fov(28.0)
		await _seconds(1.0)
		await _shot("68_third_person_close")
		await _fire(1.5)
		await _shot("69_third_person_glow")
		_hive_hold = false
		b2.apply_fov(75.0)
	dev.control_botsworth()
	await _seconds(1.0)

	# ---- the Personnel mirror
	var pr: Dictionary = game.level_info.get("personnel", {})
	var mirror: Dictionary = pr.get("mirror", {})
	if mirror.is_empty():
		print("[graftshot] no personnel mirror on this level")
		return
	var mp: Vector3 = mirror.position
	var myaw := float(mirror.get("yaw", 0.0))
	var out := Basis(Vector3.UP, myaw) * Vector3(0, 0, -1)
	_stand(mp + out * 0.75)
	_look_at(mp + Vector3(0, 1.62, 0))
	await _seconds(2.0)
	await _shot("64_mirror")
	me.apply_fov(24.0)   # a close look at your own face in the glass
	await _seconds(1.0)
	await _shot("65_mirror_close")
	await _fire(1.5)
	await _shot("66_mirror_close_glow")
	_hive_hold = false
	# The same close look with the torch off: the torch sits by your chin and lights your own face
	# from below (Player.refresh_own_lights), which is what bleaches it in the glass.
	me.set_flashlight(false)
	await _seconds(1.0)
	await _shot("65b_mirror_close_torch_off")
	me.apply_fov(75.0)

	# ---- the grafted face from outside your own head: the dev free camera (main.gd keeps it
	# current; a plain Camera3D loses to your own every frame) parked in front of the face, torch off.
	var fc: Camera3D = main.dev_panel.free_cam
	fc.start(game)
	fc.set("flying", false)
	me.dev_input_held = false
	var face := me.camera.global_position + Vector3.DOWN * 0.03
	var fwd := -me.camera.global_basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	fc.global_position = face + fwd * 0.55 + Vector3.UP * 0.03
	fc.look_at(face, Vector3.UP)
	fc.fov = 40.0
	await _seconds(1.0)
	await _shot("67_other_camera_face")
	# What lights the face this bright: every light near it, then the same shot with the nearest
	# ones switched off one at a time.
	_lights_near(face, 3.0)
	var own_glow: Light3D = me.get("_glow")
	if own_glow != null:
		own_glow.visible = false
		await _seconds(0.3)
		await _shot("67e_face_no_head_glow")
		own_glow.visible = true
	var near: Array = []
	for nd in get_tree().root.find_children("*", "Light3D", true, false):
		var l := nd as Light3D
		if l.is_visible_in_tree() and l != own_glow and l.global_position.distance_to(face) < 3.0 				and not me.is_ancestor_of(l):
			near.append(l)
	for l in near:
		l.visible = false
	await _seconds(0.3)
	await _shot("67f_face_no_room_lights_near")
	for l in near:
		l.visible = true
	await _seconds(0.3)
	fc.fov = 12.0   # close on the eyes
	await _seconds(0.5)
	await _shot("67b_other_camera_eyes_close")
	fc.global_position = face + (fwd * 0.5 + fwd.cross(Vector3.UP) * 0.3).normalized() * 0.55
	fc.look_at(face, Vector3.UP)
	fc.fov = 20.0   # three-quarter: does it sit in the socket or poke out of it
	await _seconds(0.5)
	await _shot("67c_other_camera_three_quarter")
	me.set_flashlight(true)
	await _seconds(0.5)
	fc.global_position = face + fwd * 0.55 + Vector3.UP * 0.03
	fc.look_at(face, Vector3.UP)
	fc.fov = 40.0
	await _seconds(0.5)
	await _shot("67d_other_camera_face_torch_on")
	fc.stop()   # (no glow shot here: Hive Eyes takes the view over from the free camera)


## Hive Eyes for the look only: the host clears `hive_view` whenever its own rules say so, so hold
## it on for a moment instead of setting it once.
var _hive_hold := false


func _fire(seconds: float) -> void:
	_hive_hold = true
	var end := t + seconds
	while t < end:
		_hold_on()
		await get_tree().physics_frame
	_hold_on()


func _hold_on() -> void:
	if me == null:
		return
	if site == "throat":
		# Echo is a half-second event, so keep the shriek window open by hand for the shots.
		game.brains._echo_pose_until[int(me.peer_id)] = float(game.world_time) + 0.5
	else:
		me.hive_view = true


func _process(_d: float) -> void:
	if _hive_hold:
		_hold_on()
	elif me != null and me.hive_view and not _hive_hold:
		me.hive_view = false


## The forceps seat step's stage (0 tray, 1 carried, 2 seating, 3 settling, 4 done), -1 for none.
func _seat_stage(sys: Node) -> int:
	if sys.mg == null:
		return -1
	var seat = sys.mg.get("_seat")
	return int(seat.get("stage")) if seat != null else -1


## The table body holding still: where its eyes' site is in the world, and where the operating view
## draws it on screen, once per step. Every step should print the same numbers.
func _still_probe(ps: Node, step: String) -> void:
	var body: Node = ps.get("patient_body")
	var site := body.find_child("Site_eyes", true, false) as Node3D if body != null else null
	var cam := get_viewport().get_camera_3d()
	if site == null or cam == null:
		print("[graftshot] still %s: no body or camera" % step)
		return
	var px := cam.unproject_position(site.global_position)
	print("[graftshot] still %-6s site %s  basis.z %s  on screen (%.1f, %.1f)  cam %s" % [step,
		str(site.global_position.snapped(Vector3.ONE * 0.0001)), str(site.global_basis.z.snapped(Vector3.ONE * 0.001)),
		px.x, px.y, str(cam.global_position.snapped(Vector3.ONE * 0.0001))])


func _slot(p, kind: String) -> int:
	for i in p.slots.size():
		if String(p.slots[i].kind) == kind:
			return i
	return 0


func _stand(pos: Vector3) -> void:
	me.teleport(game._floor_at(pos))
	me.bot_move = Vector2.ZERO


func _look_at(target: Vector3) -> void:
	var eye := me.global_position + Vector3.UP * C.EYE_H
	var d := target - eye
	me.bot_yaw = atan2(-d.x, -d.z)
	me.bot_pitch = clampf(atan2(d.y, Vector2(d.x, d.z).length()), -1.2, 1.2)


func _shot(name: String) -> void:
	# A minimized review window redraws only now and then, so waiting on frame_post_draw hands back
	# a frame from seconds ago (every shot of a step used to show the step before it). Force the
	# draw, then read the texture in the same call.
	RenderingServer.force_draw()
	var img := get_viewport().get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path("%s/%s%s.png" % [SHOT_DIR, prefix, name]))
	print("[graftshot] wrote ", prefix, name)


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
