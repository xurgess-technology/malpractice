extends Node
## HIT FEEDBACK smoke look: windowed screenshots of the red hurt flash and the knock back, into
## tools/hit_shots/ (gitignored). Run it through tools\hitshot.ps1, which starts the window
## minimized so it never takes focus (RULES.md, Tests that make sense).
##
##   01_monster_before   a Hive standing in the open test area, its normal colour
##   02_monster_flash    the same Hive the instant a saw lands: washed red
##   03_monster_after    a moment later, the flash gone and the Hive pushed back a step
##   04_player_before    a bot surgeon, normal
##   05_player_flash     the same bot the instant a saw lands on them (the PvP half)
##
## A solo session on the usual hospital (seed 4242) with dev mode, god mode and no roaming
## monsters, staged in an open corner of the parking lot like tools/combatshot.gd.

const MonsterScript := preload("res://scripts/monster.gd")
const SHOT_DIR := "res://tools/hit_shots"

var main: Node3D
var game: Game
var dev: Node
var cb: Node
var me: Player
var t := 0.0
## The open test area's origin (dev_controller.gd open_area()) in world space.
var o := Vector3.ZERO


func _ready() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	game = main.game
	dev = game.dev
	cb = game.combat
	if main.launching:
		await main.launched
	main.menu.hide_menu()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SHOT_DIR))
	Net.start_solo("Zach")
	game.start_session(4242)
	while game.get_parent().has_node("WarmupCover"):
		await get_tree().process_frame
	await _seconds(0.5)
	me = game.local_player()
	me.bot_active = true
	game.set_dev_tools(true, me)
	if not game.dev_on():
		push_error("[hitshot] dev mode did not turn on")
		get_tree().quit(1)
		return
	o = dev.open_area()
	dev.request("god", {"on": true})
	dev.request("no_game_over", {"on": true})
	dev.request("monsters_off", {"on": true})
	game.clock_in()
	var end := t + 60.0
	while game.phase != Game.Phase.SHIFT and t < end:
		await get_tree().physics_frame
	game.loop.first_called = true
	game.loop._end_call()
	game.loop.extra_done = true
	dev.request("clear_patient")
	for m in game.monsters.values():
		game.kill_monster(m)
	await _seconds(3.5)
	await _run()
	get_tree().quit(0)


func _physics_process(delta: float) -> void:
	t += delta


func _run() -> void:
	cb.break_chance = 0.0
	# ---- the monster half: stand off to the side so the push reads as movement, not a lunge.
	var m := await _monster(o + Vector3(15.0, 0, 12.5))
	_stand(o + Vector3(17.6, 0, 14.4))
	_look_at(m.global_position + Vector3.UP * 1.0)
	await _seconds(0.8)
	await _shot("01_monster_before")
	var before: Vector3 = m.global_position
	# Pushed away from the camera's side, along +Z, so the step back is visible across the frame.
	cb.hit_feedback_monster(m, Vector3.BACK)
	await _frames(2)
	await _shot("02_monster_flash")
	await _seconds(0.8)
	await _shot("03_monster_after")
	print("[hitshot] the Hive moved %.2f m (%s -> %s)"
		% [before.distance_to(m.global_position), str(before.snappedf(0.01)), str(m.global_position.snappedf(0.01))])

	# ---- the PvP half: a bot surgeon standing still, flashed the same way.
	var bid: int = dev.spawn_bot("bot", me)
	var bot: Player = game.players[bid]
	dev.order_bot(bid, "stay")
	await _frames(3)
	bot.teleport(game._floor_at(o + Vector3(15.0, 0, 15.0)))
	bot.bot_yaw = PI
	bot.bot_pitch = 0.0
	bot.bot_move = Vector2.ZERO
	await _frames(3)
	_stand(o + Vector3(15.0, 0, 17.4))
	_look_at(bot.global_position + Vector3.UP * 1.1)
	await _seconds(0.8)
	await _shot("04_player_before")
	cb.hit_feedback_player(bot)
	await _frames(2)
	await _shot("05_player_flash")
	await _seconds(0.6)


func _monster(pos: Vector3) -> Node:
	var m = game._add_monster("hive", game._floor_at(pos))
	await _frames(3)
	m.mode = MonsterScript.Mode.IDLE
	m.brain.timer = 999.0
	m.calm = 999.0
	m.rotation.y = 0.0
	return m


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := "%s/%s.png" % [SHOT_DIR, name]
	img.save_png(ProjectSettings.globalize_path(path))
	print("[hitshot] wrote %s" % path)


func _stand(pos: Vector3, yaw := 0.0) -> void:
	me.teleport(game._floor_at(pos))
	me.bot_yaw = yaw
	me.bot_pitch = 0.0
	me.bot_move = Vector2.ZERO


func _look_at(target: Vector3) -> void:
	var eye := me.global_position + Vector3.UP * C.EYE_H
	var d := target - eye
	me.bot_yaw = atan2(-d.x, -d.z)
	me.bot_pitch = clampf(atan2(d.y, Vector2(d.x, d.z).length()), -1.2, 1.2)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _seconds(s: float) -> void:
	var end := t + s
	while t < end:
		await get_tree().physics_frame
