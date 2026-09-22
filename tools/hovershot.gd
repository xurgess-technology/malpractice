extends Node
## HOVER DROP smoke look: drop stacks on one spot and see what they do. A dropped stack should rise
## off the floor, glow softly, and hop aside when another one already owns that patch of floor.
##
##   godot --path . --resolution 1280x720 tools/hovershot.tscn -- [--seed=N]
##
## Writes tools/hover_shots/<name>.png.

const OUT_DIR := "res://tools/hover_shots"

var main: Node3D
var game: Game
var bot: Player
var _seed := 4242


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--seed="):
			_seed = int(a.split("=")[1])
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	_run.call_deferred()


func _run() -> void:
	await _start(_seed)
	game.begin_shift()
	await _frames(20)

	var base := _clear_spot()
	var fwd := Vector3(1, 0, 0)
	_look_from(base, base + fwd * 2.0 + Vector3.UP * 0.2)
	bot.set_flashlight(true)
	_clear()
	await _frames(20)
	await _shot("01_before")

	# Six stacks, every one of them dropped at the same spot two paces ahead.
	# GLOW BALL: one of every palette colour, so the shots show the orbs differing by kind.
	var kinds := ["gauze", "gold_watch", "eye_surgeon", "brain_hive", "placebo_pills", "specimen_vat"]
	for i in kinds.size():
		_clear()
		bot.selected = 0
		bot.take_into(kinds[i], 1, 0)
		game.drop_selected(bot, 0.0)
		await _frames(150)   # longer than SETTLE_MAX, so each one is hovering before the next drop
		await _shot("02_dropped_%d_%s" % [i + 1, kinds[i]])
	var loose := _loose()
	var gaps := []
	for a in loose:
		for b in loose:
			if a.item_id < b.item_id:
				gaps.append(snappedf(a.global_position.distance_to(b.global_position), 0.01))
	print("[hovershot] %d hovering: %s" % [loose.size(), str(loose.map(func(i): return "%s y=%.2f hover=%s" % [i.kind, i.global_position.y, str(i.hovering)]))])
	print("[hovershot] pair distances: %s (want none under 0.5)" % str(gaps))

	# From above, so the spacing reads.
	_look_from(base - fwd * 0.6, base + fwd * 2.0)
	bot.bot_pitch = -0.75
	await _frames(20)
	await _shot("03_spread_from_above")

	# Right up close, at the item's own height, lit and then in the dark: the glow and the gap
	# under it. A camera of its own, because the player's eyes are 1.7 m up and look straight down.
	if not loose.is_empty():
		var c: Vector3 = (loose[0] as Node3D).global_position
		# Lying down, so the view is at the stack's own height and the gap under it shows. (Moving
		# the camera node is no good: player.gd drives its height from the stance every frame.)
		bot.teleport(game._floor_at(c - fwd * 0.85))   # teleport stands you up, so go prone after it
		bot.bot_prone = true
		bot.bot_yaw = atan2(-fwd.x, -fwd.z)
		bot.bot_pitch = atan2(0.36 - C.PRONE_EYE_H, 0.85)
		await _frames(90)
		print("[hovershot] close on %s at %v, eye %.2f, glow shells %d" % [
			(loose[0] as Node).kind, c, bot.head.global_position.y, _glow_shells(loose[0])])
		await _shot("04_close_lit")
		bot.set_flashlight(false)
		await _frames(20)
		await _shot("05_close_dark")
		bot.set_flashlight(true)
		# The whole spread at once, still lying down.
		bot.teleport(game._floor_at(base - fwd * 0.5))
		bot.bot_prone = true
		bot.bot_yaw = atan2(-fwd.x, -fwd.z)
		bot.bot_pitch = -0.05
		await _frames(90)
		await _shot("04b_row_lit")
		bot.set_flashlight(false)
		await _frames(20)
		await _shot("05b_row_dark")
		bot.bot_prone = false
		# GLOW BALL: the actual use case. Standing, well back, flashlight still off: can you tell
		# there is something on the floor, and what kind of something? Only as far back as the room
		# allows -- walking backwards through a wall photographs the wall.
		var centre: Vector3 = base + fwd * 2.0
		var away := _longest_open(centre, 9.0)
		var far: float = _clear_back(centre, away, 9.0)
		for d in [minf(far, 3.5), far]:
			_look_from(centre + away * d, centre + Vector3.UP * 0.35)
			await _frames(60)
			await _shot("05c_row_dark_%.1fm" % d)
		bot.set_flashlight(true)
		await _frames(30)
		await _shot("05d_row_lit_far")
		_look_from(base - fwd * 0.6, base + fwd * 2.0)
		await _frames(30)

	# A charged throw: it should fly, tumble, then stand up into its hover wherever it lands.
	_clear()
	_look_from(base, base + fwd * 4.0 + Vector3.UP * 1.2)
	bot.selected = 0
	bot.take_into("bone_saw", 1, 0)
	game.drop_selected(bot, 1.0)
	await _frames(30)
	await _shot("06_thrown_midair")
	await _frames(180)
	await _shot("07_thrown_settled")

	# And the aim ray: stand back and look at one, the prompt should catch it easily.
	var l2 := _loose()
	if not l2.is_empty():
		var c2: Vector3 = (l2[0] as Node3D).global_position
		_look_from(c2 - fwd * 1.8, c2)
		await _frames(20)
		print("[hovershot] aiming from 1.8 m: aim_id='%s' prompt='%s'" % [bot.aim_id, bot.aim_prompt])
		await _shot("08_aim_prompt")
	await _orb_cost(base, fwd)
	print("[hovershot] done")
	get_tree().quit(0)


## GLOW BALL: what a floor full of loot costs. Fills the patch with stacks, looks at the lot, and
## times the same view with every orb drawn and with every orb hidden.
func _orb_cost(base: Vector3, fwd: Vector3) -> void:
	var kinds := ["gauze", "gold_watch", "eye_surgeon", "brain_hive", "placebo_pills", "anesthetic"]
	var side := Vector3(fwd.z, 0, -fwd.x)
	var mine: Array = []
	for i in 30:
		# Put them straight into the hover in a fixed grid, rather than dropping them: settling
		# scatters them around the room and then the camera is timing an empty wall.
		var p := base + fwd * (1.6 + float(i / 6) * 0.7) + side * (float(i % 6) - 2.5) * 0.7
		var it = game._spawn_item(kinds[i % kinds.size()], 1, Transform3D(Basis(), p), WorldItem.State.LOOSE)
		it.place(Transform3D(Basis(), game._floor_at(p) + Vector3.UP * WorldItem.HOVER_HEIGHT), WorldItem.State.LOOSE)
		it._set_hovering(true)
		mine.append(it)
	_look_from(base - fwd * 1.0, base + fwd * 3.0 + Vector3.UP * 0.3)
	bot.set_flashlight(false)
	await _frames(60)
	var orbs := []
	for it in mine:
		orbs.append_array((it as Node).find_children("HoverGlowFx", "MeshInstance3D", true, false))
	# Wall clock, vsync off: --fixed-fps would pin every delta to 1/60 and measure nothing.
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	await _frames(30)
	# Alternate on/off several times: one block each way measures the machine warming up as much
	# as it measures the orbs.
	var with_orbs := 0.0
	var without := 0.0
	var draws := [0, 0]
	for round_i in 4:
		for o in orbs:
			(o as MeshInstance3D).visible = true
		await _frames(20)
		with_orbs += await _avg_ms(120)
		draws[0] = int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		if round_i == 0:
			await _shot("09_orb_cost")
		for o in orbs:
			(o as MeshInstance3D).visible = false
		await _frames(20)
		without += await _avg_ms(120)
		draws[1] = int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	with_orbs /= 4.0
	without /= 4.0
	print("[hovershot] orb cost: %d stacks staged, %d orbs -- %.2f ms/frame with, %.2f ms/frame without (%+.2f ms); draw calls %d vs %d" % [
		mine.size(), orbs.size(), with_orbs, without, with_orbs - without, draws[0], draws[1]])


## Average wall-clock frame time in ms over `n` frames.
func _avg_ms(n: int) -> float:
	var t0 := Time.get_ticks_usec()
	for i in n:
		await RenderingServer.frame_post_draw
	return float(Time.get_ticks_usec() - t0) / float(n) / 1000.0


## How many glow orbs a stack is carrying (0 means the glow never got built, 1 is right).
func _glow_shells(it: Node) -> int:
	return it.find_children("HoverGlowFx", "MeshInstance3D", true, false).size()


func _loose() -> Array:
	var out := []
	for it in game.world_items.values():
		if it.state == WorldItem.State.LOOSE and bool(it.hovering):
			out.append(it)
	return out


func _start(seed_value: int) -> void:
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await _frames(3)
	game = main.game
	main.menu.hide_menu()
	if not Net.active:
		Net.start_solo("Camera")
	game.start_session(seed_value)
	await _frames(2)
	bot = game.local_player()
	bot.bot_active = true
	bot.bot_invulnerable = true
	while game.get_parent().has_node("WarmupCover"):
		await get_tree().process_frame
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## A lit spot with clear floor ahead and to each side, so six stacks have room to spread out.
func _clear_spot() -> Vector3:
	var spots: Array = game.level_info.get("tool_spawns", []) + game.level_info.get("monster_spawns", [])
	var space := get_viewport().world_3d.direct_space_state
	for s in spots:
		var eye: Vector3 = s + Vector3.UP * 0.6
		var clear := true
		for dir in [Vector3(4.0, 0, 0), Vector3(2.5, 0, 2.5), Vector3(2.5, 0, -2.5), Vector3(0, 0, 2.0), Vector3(0, 0, -2.0)]:
			var q := PhysicsRayQueryParameters3D.create(eye, eye + dir)
			q.collision_mask = C.L_WORLD
			if not space.intersect_ray(q).is_empty():
				clear = false
		if clear:
			return s
	return game.table_pos() + Vector3(4, 0, 0)


## The compass direction with the most open floor in it, so "from a distance" is a real distance.
func _longest_open(from: Vector3, want: float) -> Vector3:
	var best := Vector3(1, 0, 0)
	var best_d := -1.0
	for i in 16:
		var a := TAU * float(i) / 16.0
		var dir := Vector3(cos(a), 0.0, sin(a))
		var d := _clear_back(from, dir, want)
		if d > best_d:
			best_d = d
			best = dir
	return best


## How far you can stand back from `from` along `dir` before you are inside a wall.
func _clear_back(from: Vector3, dir: Vector3, want: float) -> float:
	var eye := from + Vector3.UP * 0.9
	var q := PhysicsRayQueryParameters3D.create(eye, eye + dir * want)
	q.collision_mask = C.L_WORLD
	var hit := get_viewport().world_3d.direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return want
	return maxf(1.5, eye.distance_to(hit.position) - 0.6)


func _clear() -> void:
	bot.slots = Player.empty_slots()
	bot.selected = 0


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _shot(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := "%s/%s.png" % [OUT_DIR, shot_name]
	img.save_png(ProjectSettings.globalize_path(path))
	print("[hovershot] wrote ", path)


func _look_from(pos: Vector3, at: Vector3) -> void:
	bot.teleport(game._floor_at(pos))
	var eye := bot.global_position + Vector3.UP * C.EYE_H
	var d := at - eye
	bot.bot_yaw = atan2(-d.x, -d.z)
	bot.bot_pitch = clampf(atan2(d.y, Vector2(d.x, d.z).length()), -1.2, 1.2)
