extends Node
## PUPPET smoke look: windowed screenshots of climbing into a Hive and walking it, into
## tools/puppet_shots/ (gitignored). Run it through tools\puppetshot.ps1, which starts the window
## minimized so it never takes focus (RULES.md, Tests that make sense).
##
##   01_before      the review setup `puppet`: first person, two Hives ahead
##   02_flying      half way through the fly-in
##   03_inside      in the Hive's head, the night-sight screen, looking where it faces
##   04_walked      a couple of metres later, looking back over its shoulder at your own body
##   05_back        come back: first person again, the Hive left where you walked it

const SHOT_DIR := "res://tools/puppet_shots"

var main: Node3D
var game: Game
var me: Player
var t := 0.0
var _home_yaw := 0.0   # a bot's body looks along bot_yaw, so it gets its own heading back for 05


func _ready() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	game = main.game
	if main.launching:
		await main.launched
	main.menu.hide_menu()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SHOT_DIR))
	Net.start_solo("Zach")
	game.start_session(4242)
	while game.get_parent().has_node("WarmupCover"):
		await get_tree().process_frame
	await _seconds(0.5)
	game.clock_in()
	var end := t + 60.0
	while game.phase != Game.Phase.SHIFT and t < end:
		await get_tree().physics_frame
	await ReviewSetups._puppet(game)
	me = game.local_player()
	me.bot_active = true
	me.bot_yaw = me._yaw
	me.bot_pitch = me._pitch
	_home_yaw = me._yaw
	await _seconds(1.0)
	await _run()
	get_tree().quit(0)


func _physics_process(delta: float) -> void:
	t += delta


func _run() -> void:
	var b: Node = game.abilities
	await _shot("01_before")
	me.bot_ability_slot = b.slot_of(me.peer_id, "puppet")
	me.bot_ability += 1
	await _seconds(0.5)
	await _shot("02_flying")
	await _seconds(0.8)
	var pv: Node = b.puppet_view
	me.bot_yaw = float(pv.look_yaw)
	await _shot("03_inside")
	me.bot_move = Vector2(0, -1)
	await _seconds(1.6)
	me.bot_move = Vector2.ZERO
	# Look back over its shoulder at the body you left.
	var to: Vector3 = me.global_position - (pv.camera as Camera3D).global_position
	pv.look_yaw = atan2(-to.x, -to.z)
	pv.look_pitch = -0.15
	me.bot_yaw = float(pv.look_yaw)
	await _seconds(0.6)
	await _shot("04_walked")
	print("[puppetshot] puppeting=%s hive_moved label=%s" % [str(me.puppeting), pv._label.text])
	me.bot_yaw = _home_yaw
	me.bot_ability += 1
	await _seconds(1.0)
	await _shot("05_back")
	print("[puppetshot] back: puppeting=%s" % str(me.puppeting))


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := "%s/%s.png" % [SHOT_DIR, name]
	img.save_png(ProjectSettings.globalize_path(path))
	print("[puppetshot] wrote %s" % path)


func _seconds(s: float) -> void:
	var end := t + s
	while t < end:
		await get_tree().physics_frame
