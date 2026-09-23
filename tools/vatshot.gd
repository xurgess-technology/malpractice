extends Node
## GRAFTING smoke look: windowed screenshots of the lab wall's vat bench into tools/vat_shots/.
##
##   tools\vatshot.ps1
##
##   01_bench_wide     the vat bench from a few paces back: three vats on the counter, shelves above
##   02_at_the_vat     standing at it, crosshair on a vat ("Take the empty specimen vat")
##   03_carried        the vat in both hands after E
##   04_eye_in_vat     the eye floating in a vat standing back on the bench
##
## A normal hospital (seed 4242), dev mode on, clocked in. The point of the shots: the vats read as
## objects standing on a counter you can walk up to, and the prompt appears when you look at one.

const SHOT_DIR := "res://tools/vat_shots"
const SEED := 4242

var main: Node3D
var game: Game
var dev: Node
var me: Player
var t := 0.0


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
	dev.request("monsters_off", {"on": true})
	dev.request("no_game_over", {"on": true})
	dev.request("god", {"on": true})
	game.clock_in()
	await _until(func(): return game.phase == Game.Phase.SHIFT, 90.0)
	game.loop._end_call()
	game.loop.first_called = true
	game.loop.extra_done = true
	dev.request("clear_patient")
	# The shots are framed first person; put the setting back so the slot keeps whatever it had.
	var cam_was: String = String(Settings.get_value("camera"))
	Settings.set_value("camera", "first_person")
	await _seconds(0.6)
	await _run()
	Settings.set_value("camera", cam_was)
	get_tree().quit(0)


func _physics_process(delta: float) -> void:
	t += delta


func _look_at(target: Vector3) -> void:
	var eye := me.global_position + Vector3.UP * C.EYE_H
	var d := target - eye
	me.bot_yaw = atan2(-d.x, -d.z)
	me.bot_pitch = clampf(atan2(d.y, Vector2(d.x, d.z).length()), -1.2, 1.2)


func _stand(pos: Vector3, look: Vector3) -> void:
	me.teleport(game._floor_at(pos))
	me.bot_move = Vector2.ZERO
	await _seconds(0.4)
	var end := t + 0.8
	while t < end:
		_look_at(look)
		await get_tree().physics_frame


func _vats_on_bench() -> Array:
	var out := []
	for it in game.world_items.values():
		if is_instance_valid(it) and String(it.kind) == "specimen_vat":
			out.append(it)
	return out


func _run() -> void:
	var vats: Node = game.vats
	if vats == null or vats.spots.is_empty():
		print("[vatshot] no vat spots")
		return
	var at: Vector3 = vats.spots[1].position
	var out: Vector3 = ReviewSetups.open_direction(game, at + Vector3.UP * 0.3, 2.5)
	print("[vatshot] bench spot 1 at %s, open side %s" % [str(at.snappedf(0.01)), str(out)])

	await _stand(at + out * 2.4, at + Vector3.UP * 0.4)
	await _shot("01_bench_wide")

	await _stand(at + out * 1.1, at + Vector3.UP * 0.12)
	await _seconds(0.3)
	print("[vatshot] at the vat: aim='%s' prompt='%s'" % [me.aim_id, me.aim_prompt])
	await _shot("02_at_the_vat")

	me.bot_press += 1
	await _seconds(0.8)
	print("[vatshot] after E: held slot %d" % Vats.held_vat(me))
	await _shot("03_carried")

	# Put an eye in the carried vat, set it back on the bench, and look at it.
	game.give_hand(me, "eye_hive", 1)
	await _seconds(0.3)
	vats.hand_put(me)
	await _seconds(0.3)
	vats.set_down(me, 1)
	await _seconds(0.6)
	await _stand(at + out * 1.0, at + Vector3.UP * 0.13)
	await _seconds(0.4)
	print("[vatshot] eye in vat: aim='%s' prompt='%s'" % [me.aim_id, me.aim_prompt])
	await _shot("04_eye_in_vat")


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := "%s/%s.png" % [SHOT_DIR, name]
	img.save_png(ProjectSettings.globalize_path(path))
	print("[vatshot] wrote %s" % path)


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
