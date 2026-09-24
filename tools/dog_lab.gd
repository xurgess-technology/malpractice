extends Node3D
## Service Dog art test viewer: builds the Blender model (monster/service_dog) directly through
## MonsterModel, with no Monster/brain in the loop (service-dog-brain owns that on its own
## branch), and screenshots its clips for review. Analogous in spirit to seal_viewer.gd and
## tools/monster_lab.gd's --shots, scoped to just this one model.
##
##   godot4 --path . --resolution 1000x750 tools/dog_lab.tscn -- --shots   # -> art/service_dog/godot_shots/
##
## Exit code 0 when the model, skeleton and every listed clip were found.

const MonsterModelScript := preload("res://scripts/monsters/monster_model.gd")
const SHOT_DIR := "res://art/service_dog/godot_shots"

var model: Node3D
var cam: Camera3D
var ok := true


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SHOT_DIR))
	get_tree().create_timer(120.0).timeout.connect(func(): get_tree().quit(2))

	var env_node := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.05, 0.05, 0.06)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.16, 0.16, 0.19)
	env.ambient_light_energy = 1.0
	env_node.environment = env
	add_child(env_node)

	var key := DirectionalLight3D.new()
	key.rotation = Vector3(-0.9, -0.5, 0.0)
	key.light_energy = 2.4
	add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation = Vector3(-0.4, 2.4, 0.0)
	fill.light_energy = 0.6
	fill.light_color = Color(0.6, 0.65, 0.8)
	add_child(fill)

	cam = Camera3D.new()
	add_child(cam)

	model = MonsterModelScript.new()
	add_child(model)
	model.setup("service_dog")
	ok = ok and model.skeleton != null and model.anim != null
	print("[dog_lab] skeleton=%s anim=%s dog_poser=%s" % [model.skeleton != null, model.anim != null, model.dog != null])
	if model.anim != null:
		print("[dog_lab] clips: ", model.anim.get_animation_list())

	await get_tree().process_frame
	if OS.get_cmdline_user_args().has("--shots"):
		await _run_shots()
	else:
		# Stay open for a review window: idle, orbiting a little.
		model.play("idle")
		_look_from(Vector3(1.6, 1.1, 2.4), Vector3(0, 1.0, 0.3))


func _look_from(pos: Vector3, at: Vector3) -> void:
	cam.global_position = pos
	cam.look_at(at, Vector3.UP)


func _frames(k: int) -> void:
	for i in k:
		await get_tree().process_frame


func _shot(name: String) -> void:
	for i in 4:
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := "%s/dog_%s.png" % [SHOT_DIR, name]
	img.save_png(ProjectSettings.globalize_path(path))
	print("[dog_lab] wrote ", path, "  ", img.get_width(), "x", img.get_height())


func _check(name: String, cond: bool) -> void:
	ok = ok and cond
	print("[dog_lab] %s  %s" % ["PASS" if cond else "FAIL", name])


func _play_and_settle(clip: String, frame_time: float) -> void:
	if model.anim == null or not model.anim.has_animation(clip):
		_check("has clip " + clip, false)
		return
	model.anim.play(clip)
	model.anim.speed_scale = 1.0
	model.anim.seek(frame_time, true)
	await get_tree().process_frame


func _run_shots() -> void:
	_look_from(Vector3(1.15, 0.85, 1.55), Vector3(0, 0.85, 0.15))
	await _play_and_settle("Idle", 0.2)
	await _shot("idle")
	_check("Idle plays", model.anim.current_animation == "Idle")

	await _play_and_settle("Walk", model.anim.get_animation("Walk").length * 0.35 if model.anim.has_animation("Walk") else 0.0)
	await _shot("walk_midstride")
	_check("Walk plays", model.anim.has_animation("Walk"))

	await _play_and_settle("Growl", 0.4)
	await _shot("growl")

	await _play_and_settle("PlaceItem", model.anim.get_animation("PlaceItem").length * 0.6 if model.anim.has_animation("PlaceItem") else 0.0)
	await _shot("place_item")

	if model.anim.has_animation("StandUp"):
		var L: float = model.anim.get_animation("StandUp").length
		_look_from(Vector3(1.55, 1.05, 1.75), Vector3(0, 1.35, 0.0))
		for i in [0.0, 0.35, 0.65, 1.0]:
			await _play_and_settle("StandUp", L * i)
			await _shot("standup_%02d" % int(i * 100))
	_check("StandUp plays", model.anim.has_animation("StandUp"))

	if model.anim.has_animation("Run"):
		_look_from(Vector3(1.6, 1.15, 1.8), Vector3(0, 1.35, 0.0))
		await _play_and_settle("Run", model.anim.get_animation("Run").length * 0.25)
		await _shot("run")
	_check("Run plays", model.anim.has_animation("Run"))

	# Two frames through the bite: jaw open mid-lunge, then snapped shut while still reaching --
	# the pair together is what makes it read as an attack instead of a static pose. Framed close
	# on the head/neck, since that is where the whole clip's point is made.
	if model.anim.has_animation("Bite"):
		var bl: float = model.anim.get_animation("Bite").length
		await _play_and_settle("Bite", bl * 0.16)
		var head_i: int = model.skeleton.find_bone("head")
		var head_world: Vector3 = model.skeleton.global_transform * model.skeleton.get_bone_global_pose(head_i).origin
		_look_from(head_world + Vector3(0.75, -0.1, 0.05), head_world + Vector3(0.0, 0.05, 0.0))
		await _shot("bite_open")
		await _play_and_settle("Bite", bl * 0.5)
		head_world = model.skeleton.global_transform * model.skeleton.get_bone_global_pose(head_i).origin
		_look_from(head_world + Vector3(0.75, -0.1, 0.05), head_world + Vector3(0.0, 0.05, 0.0))
		await _shot("bite_closed")
	_check("Bite plays", model.anim.has_animation("Bite"))

	# A close vest shot: pulled back enough to read the strap/panel silhouette and both patches.
	_look_from(Vector3(0.85, 1.15, 1.05), Vector3(0.0, 1.05, 0.20))
	await _play_and_settle("Idle", 0.2)
	await _shot("vest_closeup")

	# A top-back angle to catch the back panel's red-cross patch, aimed at the neck-base bone
	# (the patch sits just above it) rather than a guessed world point.
	var neck_bi: int = model.skeleton.find_bone("neck1")
	var neck_world: Vector3 = model.skeleton.global_transform * model.skeleton.get_bone_global_pose(neck_bi).origin if neck_bi >= 0 else Vector3(0, 1.1, 0.4)
	_look_from(neck_world + Vector3(0.5, -0.05, 0.35), neck_world + Vector3(0.0, 0.0, 0.05))
	await _shot("vest_cross_patch")

	print("[dog_lab] ------------------------------------------")
	print("[dog_lab] result: ", "PASS" if ok else "FAIL")
	get_tree().quit(0 if ok else 1)
