extends Node
## The Service Dog's smoke look: the real game on the `service_dog` review setup, played through
## once, with a screenshot at every state -- from your own eyes (the HUD's fetch clock included) and
## from a camera standing off to the side (the placeholder body's proportions).
##
##   godot --path . --resolution 1280x720 tools/dogshot.tscn
##   (no display: xvfb-run -a -s "-screen 0 1280x720x24" godot4 --rendering-driver opengl3 ...)
##
## Shots land in tools/game_shots/dog_<state>_<view>.png.

const MonsterScript := preload("res://scripts/monster.gd")
const Modes := preload("res://scripts/monsters/modes.gd")
const DogBrain := preload("res://scripts/monsters/service_dog_brain.gd")
const SHOT_DIR := "res://tools/game_shots"

var main: Node3D
var game: Game
var me: Player
var dog: Node
var t := 0.0
var shots: Array = []


func _ready() -> void:
	get_tree().create_timer(400.0).timeout.connect(func(): get_tree().quit(2))
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	game = main.game
	if main.launching:
		await main.launched
	main.menu.hide_menu()
	Net.start_solo("Tester")
	game.start_session(4242)
	while game.get_parent().has_node("WarmupCover"):
		await get_tree().process_frame
	await _seconds(0.5)
	me = game.local_player()
	me.bot_active = true
	me.bot_invulnerable = true
	game.set_dev_tools(true, me)
	game.dev.request("no_game_over", {"on": true})
	game.clock_in()
	while game.phase != Game.Phase.SHIFT:
		await get_tree().physics_frame
	await ReviewSetups._service_dog(game)
	for m in game.monsters.values():
		if String(m.kind) == MonsterScript.SERVICE_DOG:
			dog = m
	# Dim ward light can hide a pale body; a work light over the corridor for the smoke look only.
	var lamp := OmniLight3D.new()
	lamp.omni_range = 9.0
	lamp.light_energy = 1.4
	game.add_child(lamp)
	lamp.global_position = (me.global_position + dog.global_position) * 0.5 + Vector3.UP * 2.3
	# A bot's view is its bot_yaw (place() set the human one, which a bot overrides): face the dog.
	var to_dog: Vector3 = dog.global_position - me.global_position
	me.bot_yaw = atan2(-to_dog.x, -to_dog.z)
	me.bot_pitch = -0.12
	await _seconds(0.6)
	await _shoot("1_carrying")
	await _until(func(): return int(dog.mode) == Modes.Mode.DOG_OFFER, 30.0)
	await _seconds(DogBrain.OFFER_DROP_AT * 0.85)
	await _shoot("2_offer")
	await _until(func(): return int(dog.mode) == Modes.Mode.DOG_WARN, 5.0)
	await _seconds(DogBrain.GROWL_AT + 0.35)
	await _shoot("3_warn_growl")
	await _seconds(3.0)
	await _shoot("4_warn_clock")
	dog.brain.offer_left = 0.2
	await _until(func(): return int(dog.mode) == Modes.Mode.DOG_DRAIN, 3.0)
	await _seconds(DogBrain.REAR_RISE * 0.55)
	await _shoot("5_rear_up")
	await _seconds(DogBrain.REAR_RISE * 0.45 + 1.0)
	await _shoot("6_drain_start")
	# Let it go on: the drained surgeon's screen greys, their torch dims (local only).
	await _seconds(5.0)
	await _shoot("7_drain_deep")
	# Save it: a charged throw of the item it offered (a teammate would do the same).
	var it: Node = game.dog_tagged_item(int(dog.brain.offer_tag))
	if it != null:
		me.teleport(game._floor_at(it.global_position + Vector3(0.4, 0, 0.4)))
		game.pickup_item(me, it)
		await _frames(2)
		game.drop_selected(me, 0.5)
	await _seconds(0.4)
	await _shoot("8_thrown_drops")
	await _until(func(): return String(dog.dog_carry) != "", 20.0)
	await _seconds(0.3)
	await _shoot("9_retrieved")
	print("[dogshot] wrote %d shots: %s" % [shots.size(), str(shots)])
	get_tree().quit(0)


func _physics_process(delta: float) -> void:
	t += delta


## Two views of this moment: through your eyes, and from the side at about 4 m.
func _shoot(label: String) -> void:
	# Look at its head, wherever it has got to.
	var to: Vector3 = dog.eye_transform().origin - (me.global_position + Vector3.UP * C.EYE_H)
	me.bot_yaw = atan2(-to.x, -to.z)
	me.bot_pitch = clampf(atan2(to.y, Vector2(to.x, to.z).length()) - 0.15, -1.0, 1.0)
	for i in 3:
		await get_tree().process_frame
	_save("dog_%s_eyes" % label)
	# The dev free camera (main.gd hands the view to it while it is on), standing off to the side of
	# the dog and you, so the placeholder body reads against a surgeon's height.
	var fc = main.dev_panel.free_cam
	var mid: Vector3 = (dog.global_position + me.global_position) * 0.5
	if dog.global_position.distance_to(me.global_position) > 6.0:
		mid = dog.global_position
	var along: Vector3 = dog.global_position - me.global_position
	along.y = 0.0
	along = along.normalized() if along.length() > 0.1 else -dog.global_transform.basis.z
	var right := along.cross(Vector3.UP).normalized()
	var aim: Vector3 = mid + Vector3.UP * 1.1
	var best := aim + right * 3.5
	var found := false
	for r in [4.5, 3.5, 2.6]:
		for c in [right * r, -right * r, right * r * 0.7 + along * r * 0.7, -right * r * 0.7 + along * r * 0.7,
				right * r * 0.7 - along * r * 0.7, -right * r * 0.7 - along * r * 0.7]:
			var p: Vector3 = aim + c + Vector3.UP * 0.3
			# In the open (not half inside a wall), and able to see both the dog and you.
			if dog.clear_line(aim, p) and game._point_is_clear(p - Vector3.UP * 0.4) \
					and dog.clear_line(p, dog.global_position + Vector3.UP * 1.0) and dog.clear_line(p, me.global_position + Vector3.UP * 1.0):
				best = p
				found = true
				break
		if found:
			break
	fc.start(game)
	fc.flying = false
	fc.global_position = best
	var d: Vector3 = aim - best
	fc._yaw = atan2(-d.x, -d.z)
	fc._pitch = atan2(d.y, Vector2(d.x, d.z).length())
	fc._apply_look()
	for i in 3:
		await get_tree().process_frame
	_save("dog_%s_side" % label)
	fc.stop()
	await get_tree().process_frame


func _save(name: String) -> void:
	var img := get_viewport().get_texture().get_image()
	var path := ProjectSettings.globalize_path("%s/%s.png" % [SHOT_DIR, name])
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	img.save_png(path)
	shots.append(path)
	var fx = game.get_node_or_null("DogDrainFx")
	print("[dogshot] %s  mode=%d rear=%.2f glow=%.2f carry='%s' left=%.1f fx=%.2f" % [path, dog.mode, dog.model.dog.rear, dog.dog_glow, dog.dog_carry, dog.dog_left, fx.amount if fx != null else 0.0])


func _until(cond: Callable, seconds: float) -> bool:
	var end := t + seconds
	while t < end:
		if cond.call():
			return true
		await get_tree().physics_frame
	return bool(cond.call())


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _seconds(s: float) -> void:
	var end := t + s
	while t < end:
		await get_tree().physics_frame
