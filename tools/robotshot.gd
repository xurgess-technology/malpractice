extends Node
## THE SURGICAL ROBOT smoke look: windowed screenshots of the robot dead, online, working on a Hive
## for somebody else (a dev bot remoted in, seen from the room), then your own view remoted in while
## strapped to its table, and the first graft step through it.
##
##   tools\robotshot.ps1        (minimized, never takes focus)
##
## Writes tools/robot_shots/<name>.png.

const OUT_DIR := "res://tools/robot_shots"

var main: Node3D
var game: Game
var me: Player


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	_run.call_deferred()


func _run() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await _frames(3)
	game = main.game
	main.menu.hide_menu()
	Net.start_solo("Camera")
	game.start_session(4242)
	await _frames(2)
	me = game.local_player()
	me.bot_active = true
	me.bot_invulnerable = true
	while game.get_parent().has_node("WarmupCover"):
		await get_tree().process_frame
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	game.set_dev_tools(true, me)
	game.dev.request("no_game_over", {"on": true})
	game.dev.request("monsters_off", {"on": true})
	game.clock_in()
	for i in 600:
		if game.phase == Game.Phase.SHIFT:
			break
		await get_tree().physics_frame
	game.loop.first_called = true
	game.loop._end_call()
	game.loop.extra_done = true
	game.dev.request("clear_patient")
	await _frames(20)
	var r = game.robot
	var fx: Node3D = r.fixture
	var ti: int = r.table_index
	var b := fx.global_transform.basis
	me.flashlight_on = true

	# Dead.
	_look_from(fx.global_position + b * Vector3(1.2, 0.0, 2.6), fx.global_position + b * Vector3(0.6, 1.1, 0.0))
	await _frames(40)
	await _shot("1_dead")
	_look_from(fx.global_position + b * Vector3(0.3, 0.0, 1.2), fx.global_position + Vector3.UP * 1.0)
	await _frames(20)
	await _shot("2_socket_dead")

	# Online (plugged in by the host rules, boot played out).
	game.give_hand(me, "robot_core", 1)
	r.fixture_used(me)
	await _frames(40)
	await _shot("3_booting")
	await _seconds(3.0)
	_look_from(fx.global_position + b * Vector3(1.2, 0.0, 2.6), fx.global_position + b * Vector3(0.6, 1.1, 0.0))
	await _frames(30)
	await _shot("4_online")

	# A dev bot remoted in, operating on a strapped Hive: seen from the room.
	game.dissection.dev_strap("hive", 1.0, ti)
	await _frames(6)
	var id: int = game.dev.spawn_bot("bot", me)
	game.dev.brains.erase(id)
	var bot: Player = game.players[id]
	bot.bot_move = Vector2.ZERO
	bot.teleport(game._floor_at(fx.global_position + b * Vector3(-0.6, 0.0, 3.5)))
	for i in bot.slots.size():
		bot.slots[i] = Player.empty_slot()
	bot.take_into("scalpel", 1)
	bot.selected = 0
	bot.set_meta("bot_skill", 0.6)
	r.set_link(bot, true)
	await _frames(40)
	_look_from(fx.global_position + b * Vector3(2.4, 0.0, 2.2), fx.global_position + b * Vector3(1.2, 1.2, 0.0))
	await _frames(30)
	await _shot("5_linked_poised")
	r.remote_interact(bot)
	await _seconds(2.5)
	await _shot("6_operating_room")
	_look_from(fx.global_position + b * Vector3(1.6, 0.0, 1.5), fx.global_position + b * Vector3(1.6, 1.1, 0.0))
	await _seconds(1.0)
	await _shot("7_operating_close")
	r.set_link(bot, false)
	await _frames(10)
	game.dev.remove_bot(id)
	game.dev.request("clear_patient")
	await _seconds(0.6)

	# You, strapped to the robot's table, remoted in.
	var si: int = game.vats.place_of_table(ti)
	var vat: Node = game._spawn_item("specimen_vat", 1, Transform3D(Basis(Vector3.UP, game.table_yaw_of(ti)), game.vats.places[si].position as Vector3), WorldItem.State.LOOSE)
	vat.x = Eyes.pack("eye_hive", "", 0.0, 120)
	for i in me.slots.size():
		me.slots[i] = Player.empty_slot()
	for k in ["scalpel", "eye_spoon", "forceps", "suture_kit"]:
		game.give_hand(me, k, 1)
	me.selected = 0
	game.strap_in(me, ti)
	await _frames(10)
	await _shot("8_strapped_own_eyes")
	r.local_toggle()
	await _frames(30)
	await _shot("9_robot_view")
	r._local_look = Vector2(0.35, -1.25)
	await _frames(20)
	await _shot("10_robot_view_turned")
	r._local_look = r.REST_LOOK
	game.player_surgery.surgery.bot_skill = 0.7
	me.bot_press += 1
	await _seconds(2.5)
	await _shot("11_graft_cut")
	print("[robotshot] done")
	get_tree().quit(0)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _seconds(s: float) -> void:
	await _frames(int(s * 60.0))


func _shot(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := "%s/%s.png" % [OUT_DIR, shot_name]
	img.save_png(ProjectSettings.globalize_path(path))
	print("[robotshot] wrote ", path)


func _look_from(pos: Vector3, at: Vector3) -> void:
	me.teleport(game._floor_at(pos))
	var eye := me.global_position + Vector3.UP * C.EYE_H
	var d := at - eye
	me.bot_yaw = atan2(-d.x, -d.z)
	me.bot_pitch = clampf(atan2(d.y, Vector2(d.x, d.z).length()), -1.2, 1.2)
