extends Node
## Windowed screenshots of the crouch pose into tools/crouch_shots/ (gitignored):
##
##   powershell -File tools/crouchshot.ps1          (minimized, never takes focus)
##   godot --path . --resolution 1280x720 tools/crouchshot.tscn
##
##   01_standing         a teammate standing, from where you stand: the height to compare against
##   02_crouching        the same teammate crouching, same camera, nothing else changed
##   03_crouching_side   the crouch from the side, where the bent knee and the flat foot show
##   04_crouch_walking   the crouch walk: the Walk clip slowed, the squat layered over it
##   05_prone            prone, for the ordering trap -- `crouching` is true here too, and it must
##                       still crawl rather than crouch
##   06_crouch_low       the crouch from low down and close, to check the feet are on the floor
##
## CROUCH POSE (2026-09-22): the whole point is that this is the view the crouching player never
## gets. `crouching` has gated sprint, jump and silent steps since SWEEP 4A, but until now the only
## thing the body did about it was a 0.3 rad torso lean, so a crouching teammate read as standing.
## 01 against 02 is the shot that shows whether that is fixed.
##
## A normal hospital (seed 4242) with dev mode on (No monsters, No game over), clocked in with the
## phone hung up, in an open corner of the parking lot.

const SHOT_DIR := "res://tools/crouch_shots"
const SEED := 4242

var main: Node3D
var game: Game
var dev: Node
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
	main.menu.hide_menu()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SHOT_DIR))
	Net.start_solo("Zach")
	game.start_session(SEED)
	while game.get_parent().has_node("WarmupCover"):
		await get_tree().process_frame
	await _seconds(1.0)
	me = game.local_player()
	me.bot_active = true
	game.set_dev_tools(true, me)
	o = dev.open_area()
	dev.request("monsters_off", {"on": true})
	dev.request("no_game_over", {"on": true})
	dev.request("god", {"on": true})
	game.clock_in()
	await _until(func(): return game.phase == Game.Phase.SHIFT, 90.0)
	game.loop._end_call()
	game.loop.first_called = true
	game.loop.extra_done = true
	await _run()
	get_tree().quit(0)


func _physics_process(delta: float) -> void:
	t += delta


func _run() -> void:
	# A bot, not a dev dummy: a dummy is a target dummy with no rig, and the rig is the whole point.
	var pid: int = dev.spawn_bot("bot", me, "Dr. Knees")
	var pal: Player = game.players[pid]
	dev.order_bot(pid, "stay")
	await _frames(4)
	# Two camera spots, and only these two. The dev room's lab floor is a navigation island in the
	# middle of the hospital, so a camera placed relative to wherever the bot has wandered to can end
	# up off the edge of it, under the floor and looking at the ceiling. The bot gets moved; the
	# camera stays where it is known to stand.
	var spot := game._floor_at(o + Vector3(15.0, 0, 15.0))
	var cam_front := game._floor_at(spot + Vector3(0, 0, 3.0))
	var cam_side := game._floor_at(spot + Vector3(2.8, 0, 0.3))
	pal.teleport(spot)
	pal.bot_yaw = PI   # facing the front camera
	await _seconds(0.8)

	# ---- 01 / 02: standing then crouching, from exactly the same place
	_stand(cam_front, 0.0)
	_look_at(spot + Vector3.UP * 0.9)
	await _seconds(0.6)
	_look_at(spot + Vector3.UP * 0.9)
	await _frames(3)
	await _shot("01_standing")
	pal.bot_crouch = true
	await _seconds(1.0)   # the crouch weight eases in at 6/s
	await _shot("02_crouching")

	# ---- 03: from the side, where the bent knee and the flat foot read
	_stand(cam_side, 0.0)
	_look_at(spot + Vector3.UP * 0.7)
	await _seconds(0.5)
	_look_at(spot + Vector3.UP * 0.7)
	await _frames(3)
	await _shot("03_crouching_side")

	# ---- 04: the crouch walk. "stay" halts a bot every tick (bot_move back to zero), so put it on
	# follow and stand it off across the room: it crouch-walks toward the camera, which does not move.
	pal.teleport(game._floor_at(spot + Vector3(0, 0, -5.0)))
	await _frames(3)
	dev.order_bot(pid, "follow")
	_stand(cam_front, 0.0)
	_look_at(spot + Vector3.UP * 0.7)
	await _seconds(2.2)
	_look_at(pal.global_position + Vector3.UP * 0.7)
	await _frames(3)
	await _shot("04_crouch_walking")
	dev.order_bot(pid, "stay")
	await _frames(3)

	# ---- 05: prone. `crouching` is still true here, so this is the ordering trap on screen.
	pal.teleport(spot)
	pal.bot_prone = true
	await _seconds(1.2)
	_stand(cam_side, 0.0)
	_look_at(spot + Vector3.UP * 0.2)
	await _seconds(0.5)
	_look_at(spot + Vector3.UP * 0.2)
	await _frames(3)
	await _shot("05_prone")
	pal.bot_prone = false
	await _seconds(1.2)

	# ---- 06: close and low, to check the feet are on the floor and not sunk into it
	pal.teleport(spot)
	await _frames(3)
	_stand(game._floor_at(spot + Vector3(1.5, 0, 1.5)), 0.0)
	_look_at(spot + Vector3.UP * 0.2)
	await _seconds(0.6)
	_look_at(spot + Vector3.UP * 0.2)
	await _frames(3)
	await _shot("06_crouch_low")


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := "%s/%s.png" % [SHOT_DIR, name]
	img.save_png(ProjectSettings.globalize_path(path))
	print("[crouchshot] wrote %s" % path)


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


func _until(cond: Callable, timeout: float) -> bool:
	var end := t + timeout
	while t < end:
		if cond.call():
			return true
		await get_tree().physics_frame
	return bool(cond.call())
