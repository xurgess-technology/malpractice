extends Node
## Windowed screenshots of the OR gurney into tools/gurney_shots/ (gitignored). The smoke look:
## run it through tools\gurneyshot.ps1 so the window never takes focus.
##
##   01_start            the review setup's first view: beside the parked gurney, doors beyond
##   02_pushing_fp       hands on the handle, pushing toward the OR doors
##   03_doors_ext        from the hall: the gurney coming through the OR's double doors
##   04_load_prompt_fp   alongside Dr. Bled: "Load Dr. Bled onto the gurney"
##   05_loaded_ext       from the side: Dr. Bled lying on it, the pusher at the handle
##   06_rider_view       roughly what the rider sees: past their feet, the way it rolls
##   07_hive_loaded_ext  the sedated Hive lying on it
##   08_table_ext        Dr. Bled laid on a free OR table from the gurney, the gurney beside it
##
## Stages exactly what `--setup=gurney` stages (ReviewSetups._gurney), then drives the local player.

const SHOT_DIR := "res://tools/gurney_shots"
const GurneyScript := preload("res://scripts/gurney/gurney.gd")

var main: Node3D
var game: Game
var me: Player
var g: Node
var t := 0.0
var cam: Camera3D


func _ready() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	game = main.game
	main.menu.hide_menu()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SHOT_DIR))
	Net.start_solo("Zach")
	game.start_session(4242)
	while game.get_parent().has_node("WarmupCover") or game.local_player() == null:
		await get_tree().process_frame
	game.begin_shift()
	await _seconds(0.8)
	await ReviewSetups.stage("gurney", game)
	me = game.local_player()
	me.bot_active = true
	me.bot_yaw = me._yaw
	me.bot_pitch = me._pitch
	g = game.gurney
	await _seconds(1.0)
	await _shot("01_start")

	me.bot_aim_id = "gurney"
	await _frames(3)
	me.bot_press += 1
	await _frames(4)
	me.bot_aim_id = ""
	me.bot_pitch = -0.15
	me.bot_move = Vector2(0, -1)
	await _seconds(0.8)
	me.bot_move = Vector2.ZERO
	await _seconds(0.3)
	await _shot("02_pushing_fp")

	var ot: Vector3 = g.park_pos - Vector3(9.5, 0, 10.5) * C.TILE
	# Out through the doors, watched from the hall.
	_put_pusher(ot + Vector3(10.5, 0, 9.0) * C.TILE, -PI / 2.0)
	await _frames(3)
	me.bot_move = Vector2(0, -1)
	await _until(func(): return g.nose().x > ot.x + 14.6 * C.TILE, 5.0)
	me.bot_move = Vector2.ZERO
	await _ext(ot + Vector3(16.6, 0, 11.2) * C.TILE + Vector3.UP * 1.6, g.nose() + Vector3.UP * 0.6)
	await _shot("03_doors_ext")
	_fp()

	var mate: Player = null
	for p in game.players.values():
		if String(p.player_name) == "Dr. Bled":
			mate = p
	if mate != null:
		# Alongside them, gurney pointing down the hall (south, +Z).
		_put_pusher(mate.global_position + Vector3(0.9, 0, -0.2 - GurneyScript.HANDLE_BACK), PI)
		me.bot_pitch = -0.35
		await _seconds(0.5)
		await _shot("04_load_prompt_fp")
		me.bot_press += 1
		await _frames(4)
		me.bot_move = Vector2(0, -1)
		await _seconds(0.6)
		me.bot_move = Vector2.ZERO
		await _seconds(0.4)
		var side: Vector3 = g.pose().basis.x
		await _ext(g.pose().origin + side * 3.2 + Vector3.UP * 1.7, g.pose().origin + Vector3.UP * 0.8)
		await _shot("05_loaded_ext")
		var rp: Transform3D = g.rider_player_pose()
		var eye: Vector3 = rp.origin + Vector3.UP * 0.28
		await _ext(eye, eye - g.pose().basis.z * 4.0 + Vector3.UP * 0.3)
		await _shot("06_rider_view")
		# Back to the OR, beside a free table.
		var ti: int = game.free_patient_table()
		if ti >= 0:
			var b := Basis(Vector3.UP, game.table_yaw_of(ti))
			var s2: Vector3 = b * Vector3(0, 0, 1)
			var yaw := atan2(s2.x, s2.z)
			_put_pusher(game.table_position(ti) + s2 * 1.9 + Basis(Vector3.UP, yaw) * Vector3(0, 0, GurneyScript.HANDLE_BACK), yaw)
			_fp()
			await _seconds(0.4)
			me.bot_press += 1
			await _seconds(0.8)
			await _ext(game.table_position(ti) + s2 * 3.5 + b.x * 2.5 + Vector3.UP * 2.0, game.table_position(ti) + s2 * 1.0 + Vector3.UP * 0.8)
			await _shot("08_table_ext")
			_fp()
	# The Hive.
	var hive: Node = null
	for m in game.monsters.values():
		if m.is_sedated():
			hive = m
	if hive != null:
		_put_pusher(hive.global_position + Vector3(-0.9, 0, -0.2 - GurneyScript.HANDLE_BACK), PI)
		await _seconds(0.4)
		me.bot_press += 1
		await _seconds(0.5)
		var side2: Vector3 = g.pose().basis.x
		await _ext(g.pose().origin - side2 * 3.0 + Vector3.UP * 1.8, g.pose().origin + Vector3.UP * 0.8)
		await _shot("07_hive_loaded_ext")
		_fp()
	# A teammate pushing it, the way everyone else sees a pusher.
	me.drop_count += 1   # tip the Hive off
	await _frames(3)
	g.release()
	me.teleport(me.global_position + Vector3(0, 0, -3.0))
	await _frames(3)
	var bid: int = game.dev.spawn_bot("bot", me, "Dr. Push")
	await _frames(4)
	var bot = game.players.get(bid)
	if bot != null and g.pusher == 0:
		game.dev.brains.erase(bid)
		var gp: Transform3D = g.pose()
		bot.teleport(game._floor_at(gp.origin + gp.basis * Vector3(0.7, 0, 2.2)))
		bot.bot_aim_id = "gurney"
		await _frames(3)
		bot.bot_press += 1
		await _frames(4)
		bot.bot_aim_id = ""
		bot.bot_move = Vector2(0, -1)
		await _seconds(0.7)
		var side3: Vector3 = g.pose().basis.x
		await _ext(g.pose().origin + side3 * 1.3 + g.pose().basis.z * 4.6 + Vector3.UP * 1.7, g.pose().origin + g.pose().basis.z * 1.3 + Vector3.UP * 0.9)
		await _shot("09_bot_pushing_ext")
		bot.bot_move = Vector2.ZERO
		await _seconds(0.5)
		await _shot("09b_bot_stopped_ext")
		print("[gurneyshot] bot pusher %s, clip %s" % [str(g.pusher == bid), String(bot.body_hands.anim.current_animation) if bot.body_hands != null and bot.body_hands.anim != null else "-"])
	print("[gurneyshot] done")
	get_tree().quit(0)


func _physics_process(delta: float) -> void:
	t += delta


func _put_pusher(pos: Vector3, yaw: float) -> void:
	me.teleport(game._floor_at(pos))
	me._yaw = yaw
	me.rotation.y = yaw
	me.bot_yaw = yaw
	me.bot_move = Vector2.ZERO


func _ext(from: Vector3, at: Vector3) -> void:
	if cam == null:
		cam = Camera3D.new()
		cam.fov = 70.0
		add_child(cam)
	cam.global_position = from
	cam.look_at(at, Vector3.UP)
	main.set_process(false)   # main.gd hands the view back to the player's camera every frame
	cam.current = true
	await _frames(3)


func _fp() -> void:
	if cam != null:
		cam.current = false
	main.set_process(true)
	me.camera.current = true


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := "%s/%s.png" % [SHOT_DIR, name]
	img.save_png(ProjectSettings.globalize_path(path))
	print("[gurneyshot] wrote %s  (prompt '%s')" % [path, me.aim_prompt])


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
