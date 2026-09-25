extends RefCounted
## POCKETS: gameshot's pocket space shots (tools/gameshot.gd --pocket=<a kind in PocketPlan.KINDS>).
##
##   godot --path . tools/gameshot.tscn --resolution 1280x720 -- --pocket=factory [--seed=N]
##
## Writes tools/game_shots/p_<kind>_*.png: the space from a few places, an entrance opening from
## inside, and for every seam the hallway side (the mouth, the view from the first bend down leg 2),
## the same pose in both copies of the stub on each side of the seam (the image difference is
## printed: identical copies differ only by noise), and the frames just before and just after a
## walk through the seam.

const Stub := preload("res://scripts/level/pockets/stub.gd")
const OUT_DIR := "res://tools/game_shots"

var shot: Node
var game: Game
var bot: Player
var kind := ""
var tag := ""


func run(gs: Node, pocket_kind: String) -> void:
	shot = gs
	game = gs.game
	bot = gs.bot
	kind = pocket_kind
	tag = gs._tag
	var tree := gs.get_tree()
	while game.get_parent().has_node("WarmupCover"):
		await tree.process_frame
	game.begin_shift()
	game._clear_monsters()
	await _settle(30)
	var pk = game.pockets
	if not pk.active():
		print("[gameshot] no pocket was built")
		return
	bot.set_flashlight(true)
	var p: Dictionary = pk.pocket
	var lay: Dictionary = p.layout
	var o := Vector3(Vector2i(p.origin).x * C.TILE, 0.0, Vector2i(p.origin).y * C.TILE)
	var w := func(t: Vector2, y := 0.0) -> Vector3:
		return o + Vector3(t.x * C.TILE, y, t.y * C.TILE)
	# STAND IN THE ROOM BEFORE PHOTOGRAPHING IT (POCKETS 2 phase 7). The space's own air is blended
	# in from where the camera stands, and the FIRST shot of a run was coming out in the hospital's
	# air: one run of `--pocket=chapel` produced a nave washed out cyan-green with the vault lit up,
	# and the identical pose a run later produced the cathedral. Nothing was wrong with the room --
	# the shot was simply taken before its air arrived. Ninety frames deep inside it first.
	_pose(p.spawn, p.spawn + Vector3.FORWARD * 4.0)
	await _settle(90)
	if String(gs._only) == "onlooker":
		await _onlooker_look(p)
		return
	if kind == "factory":
		bot.set_flashlight(false)
		await _shot("p_factory_1_hall", w.call(Vector2(14, 50)), w.call(Vector2(60, 16), 6.0))
		await _shot("p_factory_2_catwalk", w.call(Vector2(40, 12), 6.0), w.call(Vector2(38, 44), 1.0))
		bot.set_flashlight(true)
		await _shot("p_factory_3_line", w.call(Vector2(20, 30)), w.call(Vector2(34, 23), 1.5))
		await _shot("p_factory_4_up", w.call(Vector2(36, 32)), w.call(Vector2(40, 30), 20.0))
		await _shot("p_factory_5_offices", w.call(Vector2(24, 42)), w.call(Vector2(26, 49), 1.5))
		await _shot("p_factory_7_office_door", w.call(Vector2(27.5, 45.0)), w.call(Vector2(25.5, 48.5), 1.2))
	elif kind == "natatorium":
		# POCKETS 2 phase 2. The water is the room, so most of these are of it: along the lanes, across
		# it with the underwater lights on, standing in it looking up at the roof, and the deck.
		await _shot("p_natatorium_1_length", w.call(Vector2(14, 26), 1.6), w.call(Vector2(57, 26), 1.4))
		await _shot("p_natatorium_2_across", w.call(Vector2(34, 13), 1.6), w.call(Vector2(34, 39), 0.3))
		await _shot("p_natatorium_3_in_the_water", w.call(Vector2(30, 26), 1.6), w.call(Vector2(52, 26), 1.2))
		await _shot("p_natatorium_4_up", w.call(Vector2(34, 26), 1.6), w.call(Vector2(38, 26), 9.0))
		await _shot("p_natatorium_5_blocks", w.call(Vector2(55, 22), 1.6), w.call(Vector2(50, 27), 0.8))
		await _shot("p_natatorium_6_stand", w.call(Vector2(26, 22), 1.6), w.call(Vector2(28, 17), 2.1))
		await _shot("p_natatorium_8_bleachers", w.call(Vector2(20, 35), 1.6), w.call(Vector2(12, 20), 1.2))
		await _shot("p_natatorium_9_lockers", w.call(Vector2(15.5, 39), 1.6), w.call(Vector2(16, 46), 1.2))
		# The two new items in the hand, on the deck (the smoke look RULES.md asks for).
		bot.slots = Player.empty_slots()
		bot.slots[0] = {"kind": "lifeguard_whistle", "count": 1, "v": 15}
		bot.selected = 0
		await _settle(6)
		await _shot("p_natatorium_a_whistle", w.call(Vector2(30, 21), 1.6), w.call(Vector2(30, 26), 1.2))
		bot.slots = Player.empty_slots()
		bot.slots[0] = {"kind": "pool_chemical_drum", "count": 1, "v": 60}
		bot.slots[1] = {"kind": "pool_chemical_drum", "count": 1, "v": 60}
		bot.selected = 0
		await _settle(6)
		await _shot("p_natatorium_b_drum", w.call(Vector2(30, 21), 1.6), w.call(Vector2(30, 26), 1.2))
		bot.slots = Player.empty_slots()
		await _settle(4)
	elif kind == "laundromat":
		# POCKETS 2 phase 4. Flat fluorescent light, so the flashlight is off for the wide shots.
		bot.set_flashlight(false)
		await _shot("p_laundromat_1_length", w.call(Vector2(12.5, 18.5)), w.call(Vector2(48, 18.5), 1.6))
		await _shot("p_laundromat_2_corner", w.call(Vector2(12, 12)), w.call(Vector2(48, 25), 1.6))
		await _shot("p_laundromat_3_aisle", w.call(Vector2(15, 18.5)), w.call(Vector2(48, 18.5), 1.2))
		await _shot("p_laundromat_4_dryers", w.call(Vector2(22, 14)), w.call(Vector2(22, 11), 1.4))
		var isl: Dictionary = lay.islands[mini(8, lay.islands.size() - 1)]
		var ip: Vector3 = w.call(Vector2(isl.tile) + Vector2(0.5, 2.4))
		await _shot("p_laundromat_5_washers", ip, ip + Vector3(0, 0.6, -2.4))
		bot.set_flashlight(true)
		await _shot("p_laundromat_6_back", w.call(Vector2(16, 23)), w.call(Vector2(15, 28), 1.3))
	elif kind == "chapel":
		# Candlelight is the room's light, so the flashlight stays off for the wide shots: with it
		# on you are looking at a torch beam, not at a chapel.
		bot.set_flashlight(false)
		await _shot("p_chapel_1_nave", w.call(Vector2(21.5, 13.0)), w.call(Vector2(21.5, 52.0), 1.6))
		await _shot("p_chapel_2_reredos", w.call(Vector2(21.5, 47.0)), w.call(Vector2(21.5, 54.0), 2.0))
		await _shot("p_chapel_3_aisle", w.call(Vector2(13.0, 14.0)), w.call(Vector2(13.0, 50.0), 1.6))
		await _shot("p_chapel_4_rack", w.call(Vector2(13.0, 21.0)), w.call(Vector2(11.5, 22.0), 1.2))
		await _shot("p_chapel_5_up", w.call(Vector2(21.5, 30.0)), w.call(Vector2(21.5, 34.0), 22.0))
		bot.set_flashlight(true)
		await _shot("p_chapel_6_pews", w.call(Vector2(21.5, 26.0)), w.call(Vector2(18.0, 24.0), 1.0))
		await _shot("p_chapel_7_sacristy_door", w.call(Vector2(19.0, 46.0)), w.call(Vector2(14.5, 49.0), 1.2))
		# The three new items in the hand, at the crossing (the smoke look RULES.md asks for).
		for item in [["votive_candle", 14], ["communion_wine", 0], ["collection_plate", 80]]:
			bot.slots = Player.empty_slots()
			bot.slots[0] = {"kind": String(item[0]), "count": 1, "v": int(item[1])}
			bot.selected = 0
			await _settle(6)
			await _shot("p_chapel_a_" + String(item[0]), w.call(Vector2(21.5, 30.0)), w.call(Vector2(21.5, 36.0), 1.4))
		bot.slots = Player.empty_slots()
		await _settle(4)
	else:
		await _shot("p_restaurant_1_dining", w.call(Vector2(12.5, 25.5)), w.call(Vector2(34, 12), 1.0))
		await _shot("p_restaurant_2_host", w.call(Vector2(28, 22)), w.call(Vector2(28, 11), 1.6))
		await _shot("p_restaurant_3_bar", w.call(Vector2(33, 23)), w.call(Vector2(40, 14), 1.4))
		var t: Dictionary = lay.tables[mini(3, lay.tables.size() - 1)]
		var tp: Vector3 = w.call(Vector2(t.tile) + Vector2(0.5, 0.5))
		await _shot("p_restaurant_4_table", tp + Vector3(1.1, 0, 1.3), tp + Vector3(0, 0.8, 0))
		await _shot("p_restaurant_5_kitchen", w.call(Vector2(27, 29.5)), w.call(Vector2(40, 33), 1.2))
		await _shot("p_restaurant_7_kitchen_doors", w.call(Vector2(30.5, 22.5)), w.call(Vector2(33.0, 27.5), 1.2))
		await _shot("p_restaurant_8_restroom_doors", w.call(Vector2(22.5, 28.6)), w.call(Vector2(15.5, 30.5), 1.2))
	if kind == "factory":
		await _onlooker_shot(w)
	# An entrance from inside the space.
	var s0: Dictionary = pk.seams[0]
	await _shot("p_%s_6_opening" % kind, Stub.local_point(s0.xp, float(s0.w) - 1.0, -7.0), Stub.local_point(s0.xp, float(s0.w) - 1.0, 0.0, 1.6))
	# Every seam from the hallway side, and the two copies compared.
	LightFlicker.sync_time(3.0)
	var fx = Look.get_post_fx(game.get_tree().root)
	for s in pk.seams:
		var i := int(s.id)
		var back := float(s.d) - 1.0
		pk.crossing_enabled = true
		await _shot("p_%s_s%d_a_hallway" % [kind, i], Stub.local_point(s.xh, -3.0, -2.5), Stub.local_point(s.xh, 1.0, 1.5, 1.5))
		await _shot("p_%s_s%d_b_bend" % [kind, i], Stub.local_point(s.xh, 0.9, back - 0.6), Stub.local_point(s.xh, float(s.w), back, 1.5))
		pk.crossing_enabled = false
		if fx != null:
			fx.set_enabled(false)
		var a: Image = await _grab("p_%s_s%d_c_forward_hospital" % [kind, i], Stub.local_point(s.xh, 1.1, back), Stub.local_point(s.xh, float(s.w), back, 1.6))
		var b: Image = await _grab("p_%s_s%d_c_forward_pocket" % [kind, i], Stub.local_point(s.xp, 1.1, back), Stub.local_point(s.xp, float(s.w), back, 1.6))
		print("[gameshot] seam %d forward (from the hospital side): copies differ by %s" % [i, _diff(a, b)])
		var c: Image = await _grab("p_%s_s%d_d_back_pocket" % [kind, i], Stub.local_point(s.xp, float(s.w) - 1.1, back), Stub.local_point(s.xp, 0.0, back, 1.6))
		var d: Image = await _grab("p_%s_s%d_d_back_hospital" % [kind, i], Stub.local_point(s.xh, float(s.w) - 1.1, back), Stub.local_point(s.xh, 0.0, back, 1.6))
		print("[gameshot] seam %d back (from the pocket side): copies differ by %s" % [i, _diff(c, d)])
		if fx != null:
			fx.set_enabled(true)
		pk.crossing_enabled = true
		await _walk_shot(s, i)
	await _ghost_shot(pk.seams[0])
	LightFlicker._clock_driven = false


## POCKETS 2 phase 7: the Onlooker mid-stare, down the Factory's fogged hall.
##
## This is the one shot on phase 7's list that no headless check can stand in for, and phase 6 is
## why: every one of its 108 headless checks passed while the monster was **invisible** at the
## thirty metres it is always met at, because a headless suite cannot see a dark room. The Factory
## is the hardest case in the game for it -- the longest hall, the heaviest fog, no torch -- so the
## question this answers is simply: standing where a surgeon stands, can you see the thing looking
## at you?
##
## It uses the real spawn path (the watcher, forced on) rather than adding a monster by hand, so
## what is photographed is a placement the game would actually make. The camera is posed FIRST and
## then left alone: the brain places into the mark's frustum of the frame it runs in, so re-aiming
## afterwards would be photographing a different view than the one it aimed at.
func _onlooker_shot(w: Callable) -> void:
	var Watch := preload("res://scripts/monsters/onlooker_watch.gd")
	var was: String = Watch.force
	Watch.force = "on"
	bot.set_flashlight(false)
	_pose(w.call(Vector2(14, 50)), w.call(Vector2(60, 16), 1.6))
	game.onlooker_watch.rearm()
	# Wait on the watcher rather than on a frame count: SETTLE is a second of PHYSICS time and this
	# loop counts process frames, which at 120 fps runs out first. (That is why the first version
	# of this printed "the watcher put none in the factory".)
	var o: Node = null
	for _i in 600:
		await _settle(1)
		o = game.onlooker_watch.current()
		if o != null:
			break
	if o == null:
		print("[gameshot] onlooker: the watcher put none in the factory")
		Watch.force = was
		return
	# Turn on the spot until it finds a heading with room down it, the same way pockettest does.
	# A bot eases toward bot_yaw rather than snapping, so settle the head before judging a frame.
	var found := false
	for i in 16:
		var yaw := float(i) * TAU / 16.0
		bot.bot_yaw = yaw
		bot._yaw = yaw
		bot.rotation.y = yaw
		await _settle(20)
		if bool(o.present):
			found = true
			break
	if not found:
		print("[gameshot] onlooker: no heading in the factory had room for it")
		Watch.force = was
		game._clear_monsters()
		return
	await _settle(40)
	var d: float = o.global_position.distance_to(bot.global_position)
	await _shot_here("p_factory_c_onlooker_stare")
	print("[gameshot] onlooker: staring from %.1f m, in the fog, no torch" % d)
	Watch.force = was
	game._clear_monsters()
	await _settle(4)


## 2026-09-24: the Onlooker's shadow and its poof, in this pocket's own light and air
## (`--pocket=<kind> --only=onlooker`; tools/onlookershot.ps1 runs every space).
##
##   p_<kind>_o1_near      it at 11 m, torch on: the eroded edge and the smoke round it
##   p_<kind>_o2_dark      the same, torch off
##   p_<kind>_o3_far       it as far down the room as there is room for (up to 30 m), torch off
##   p_<kind>_o4_poof_*    running at it: the frame it goes, then 0.15, 0.5, 1.5, 3 and 5 s after,
##                         from where the runner stands
func _onlooker_look(p: Dictionary) -> void:
	var Watch := preload("res://scripts/monsters/onlooker_watch.gd")
	Watch.force = "off"
	game.onlooker_watch.rearm()
	game._clear_monsters()
	var centre: Vector3 = p.spawn
	var dir: Vector3 = ReviewSetups.open_heading(game, centre + Vector3.UP * 1.5, 40.0)
	var space := game.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(centre + Vector3.UP * 1.5, centre + Vector3.UP * 1.5 + dir * 40.0)
	q.collision_mask = C.L_WORLD
	var hit := space.intersect_ray(q)
	var room: float = 40.0 if hit.is_empty() else (centre + Vector3.UP * 1.5).distance_to(hit.position)
	print("[gameshot] onlooker: %.1f m of room down the heading" % room)
	# From behind the spawn a little, so the near shot has the whole figure in frame.
	var eye_at := func(d: float) -> Vector3:
		return centre + dir * d + Vector3.UP * 1.45
	bot.set_flashlight(true)
	_pose(centre, eye_at.call(11.0))
	await _settle(20)
	var o: Node = ReviewSetups.onlooker_ahead(game, 11.0, false)
	if o == null:
		print("[gameshot] onlooker: could not add one")
		return
	await _settle(90)
	await _shot_here("p_%s_o1_near" % kind)
	bot.set_flashlight(false)
	await _settle(30)
	await _shot_here("p_%s_o2_dark" % kind)
	var far := clampf(room - 3.0, 14.0, 30.0)
	o.global_position = game._floor_at(centre + dir * far)
	o.brain.placements += 1
	await _settle(60)
	await _shot_here("p_%s_o3_far" % kind)
	print("[gameshot] onlooker: far shot at %.1f m" % far)
	# Back to 11 m, torch on, then run at it: 5 m short, which is inside the banish range.
	o.global_position = game._floor_at(centre + dir * 11.0)
	o.brain.placements += 1
	bot.set_flashlight(true)
	await _settle(40)
	var at: Vector3 = o.global_position
	var poofs0 := int(o.poofs)
	_pose(centre + dir * 5.5, at + Vector3.UP * 1.3)
	var t0 := Time.get_ticks_msec()
	for _i in 120:
		await shot.get_tree().physics_frame
		if int(o.poofs) > poofs0:
			break
	if int(o.poofs) <= poofs0:
		print("[gameshot] onlooker: it did not poof (present=%s)" % str(o.present))
		return
	print("[gameshot] onlooker: poofed %d ms after the rush began" % (Time.get_ticks_msec() - t0))
	t0 = Time.get_ticks_msec()
	# Step back to where the rush began so the cloud is framed, the way a teammate would see it.
	_pose(centre + dir * 2.5, at + Vector3.UP * 1.2)
	var marks := [0.0, 0.15, 0.5, 1.5, 3.0, 5.0]

	for t in marks:
		# At least one fresh frame between shots: reading a shot back stalls long enough that the
		# next mark can already be due, and then two shots would be the same frame.
		await shot.get_tree().process_frame
		while float(Time.get_ticks_msec() - t0) / 1000.0 < t:
			await shot.get_tree().process_frame
		print("[gameshot] onlooker: poof +%.2f s (presence %.2f)" % [float(Time.get_ticks_msec() - t0) / 1000.0, float(o.presence)])
		await _shot_here("p_%s_o4_poof_%s" % [kind, String.num(t, 2).replace(".", "_")])
	print("[gameshot] onlooker: poofed, %d poof(s) left" % (int(o.poofs) - poofs0))
	Watch.force = ""


## A shot from exactly where the camera already stands (see _onlooker_shot: re-posing would move
## the view the monster placed itself into).
func _shot_here(name: String) -> void:
	var img := shot.get_viewport().get_texture().get_image()
	var path := "%s/%s%s.png" % [OUT_DIR, name, tag]
	img.save_png(ProjectSettings.globalize_path(path))
	print("[gameshot] wrote ", path)


## A teammate (a bot) walks ahead through the seam while we watch from the first bend: once it is past
## the seam it is really in the pocket, and its ghost must still stand where we see it.
func _ghost_shot(s: Dictionary) -> void:
	var pk = game.pockets
	var back := float(s.d) - 1.0
	var mate = preload("res://scripts/player.gd").new_player(-77, "Teammate", false)
	mate.is_bot = true
	mate.bot_active = true
	mate.bot_invulnerable = true
	game.players[-77] = mate
	game.get_node("Entities").add_child(mate)
	mate.teleport(Stub.local_point(s.xh, 2.6, back))
	_pose(Stub.local_point(s.xh, 0.8, back - 0.3), Stub.local_point(s.xh, float(s.w), back, 1.4))
	await _settle(20)
	var n0: int = pk.crossings.size()
	for k in 400:
		var frame: Transform3D = s.xp if pk.in_pocket(mate.global_position) else s.xh
		var to: Vector3 = Stub.local_point(frame, float(s.w) - 1.0, back) - mate.global_position
		to.y = 0.0
		mate.bot_yaw = atan2(-to.x, -to.z)
		mate.bot_move = Vector2(0, -1) if to.length() > 0.4 else Vector2.ZERO
		await shot.get_tree().process_frame
		var l := Stub.to_local(frame, mate.global_position)
		if pk.in_pocket(mate.global_position) and l.x > Stub.seam_s(s.w) + 0.9:
			break
	mate.bot_move = Vector2.ZERO
	await _settle(4)
	var img := shot.get_viewport().get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path("%s/p_%s_ghost%s.png" % [OUT_DIR, kind, tag]))
	print("[gameshot] teammate crossed %d time(s), in the pocket %s, ghosts %d" % [pk.crossings.size() - n0, str(pk.in_pocket(mate.global_position)), pk._mirrors.size()])
	game.players.erase(-77)
	mate.queue_free()


func _settle(n: int) -> void:
	for k in n:
		await shot.get_tree().process_frame


func _pose(from: Vector3, at: Vector3) -> void:
	bot.teleport(from)
	var d := at - (from + Vector3.UP * C.EYE_H)
	var yaw := atan2(-d.x, -d.z)
	var pitch := clampf(atan2(d.y, Vector2(d.x, d.z).length()), -1.2, 1.2)
	bot.bot_yaw = yaw
	bot._yaw = yaw
	bot.rotation.y = yaw
	bot.bot_pitch = pitch
	bot._pitch = pitch
	bot.head.rotation.x = pitch
	bot.bot_move = Vector2.ZERO


func _shot(name: String, from: Vector3, at: Vector3, settle := 34) -> void:
	await _grab(name, from, at, settle)


func _grab(name: String, from: Vector3, at: Vector3, settle := 40) -> Image:
	_pose(from, at)
	await _settle(settle)
	var img := shot.get_viewport().get_texture().get_image()
	var path := "%s/%s%s.png" % [OUT_DIR, name, tag]
	img.save_png(ProjectSettings.globalize_path(path))
	# The space's own air (PocketSpaces.AIR) is blended in by WHERE THE CAMERA STANDS: 0 within a
	# few metres of a seam opening, 1 by 14 m in. So a wide shot taken from just inside an entrance
	# draws the whole room in the HOSPITAL's air, which whites the Chapel's nave out and leaves the
	# Laundromat dark. That is not the room being wrong, and it cost phase 7 an hour to be sure of,
	# so the factor is printed with every shot now. POCKETS 2 phase 7.
	print("[gameshot] wrote %s (air %.2f)" % [path, game.pockets.air_factor(bot.global_position)])
	return img


## Mean and 99th percentile absolute difference, in % of full scale, over a downsampled image.
func _diff(a: Image, b: Image) -> String:
	var x := a.duplicate() as Image
	var y := b.duplicate() as Image
	x.resize(320, 180, Image.INTERPOLATE_BILINEAR)
	y.resize(320, 180, Image.INTERPOLATE_BILINEAR)
	var vals := PackedFloat32Array()
	var total := 0.0
	for j in 180:
		for i in 320:
			var ca := x.get_pixel(i, j)
			var cb := y.get_pixel(i, j)
			var dv := (absf(ca.r - cb.r) + absf(ca.g - cb.g) + absf(ca.b - cb.b)) / 3.0
			vals.append(dv)
			total += dv
	vals.sort()
	return "mean %.2f%%, 99th percentile %.2f%%, max %.2f%%" % [100.0 * total / vals.size(), 100.0 * vals[int(vals.size() * 0.99)], 100.0 * vals[vals.size() - 1]]


## Walk through the seam from the hospital side and keep the frame before and after the move.
func _walk_shot(s: Dictionary, i: int) -> void:
	var pk = game.pockets
	var back := float(s.d) - 1.0
	_pose(Stub.local_point(s.xh, 2.4, back), Stub.local_point(s.xh, float(s.w), back, 1.6))
	await _settle(40)
	var target_h := Stub.local_point(s.xh, float(s.w) - 1.0, back)
	var before: Image = null
	var n0: int = pk.crossings.size()
	for k in 240:
		var frame: Transform3D = s.xp if pk.in_pocket(bot.global_position) else s.xh
		var to := Stub.local_point(frame, float(s.w) - 1.0, back) - bot.global_position
		to.y = 0.0
		bot.bot_yaw = atan2(-to.x, -to.z)
		bot.bot_move = Vector2(0, -1)
		await shot.get_tree().process_frame
		if pk.crossings.size() > n0:
			var after := shot.get_viewport().get_texture().get_image()
			after.save_png(ProjectSettings.globalize_path("%s/p_%s_s%d_e_after%s.png" % [OUT_DIR, kind, i, tag]))
			if before != null:
				before.save_png(ProjectSettings.globalize_path("%s/p_%s_s%d_e_before%s.png" % [OUT_DIR, kind, i, tag]))
				print("[gameshot] seam %d walk: the frame before and after the move differ by %s" % [i, _diff(before, after)])
			break
		before = shot.get_viewport().get_texture().get_image()
	bot.bot_move = Vector2.ZERO
