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

	# A visible ground plane, so the standup/run screenshots can show actual foot-to-ground
	# contact rather than the model floating in empty space.
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(6, 6)
	ground.mesh = pm
	var gmat := StandardMaterial3D.new()
	gmat.albedo_color = Color(0.11, 0.11, 0.12)
	ground.material_override = gmat
	add_child(ground)

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
		# A clean, level, straight-on side view of the final reared pose, framed on the hind
		# paws' own world position so the ground plane under them is actually in frame (Zach:
		# check the actual foot/paw contact, both feet at the same height, under the body).
		await _play_and_settle("StandUp", L)
		var toe_bi: int = model.skeleton.find_bone("htoe.L")
		var toe_world: Vector3 = model.skeleton.global_transform * model.skeleton.get_bone_global_pose(toe_bi).origin if toe_bi >= 0 else Vector3.ZERO
		var toe_r_bi: int = model.skeleton.find_bone("htoe.R")
		var toe_r_world: Vector3 = model.skeleton.global_transform * model.skeleton.get_bone_global_pose(toe_r_bi).origin if toe_r_bi >= 0 else toe_world
		_check("both hind paws on the ground and level (%.3f m, %.3f m above y = 0)" % [toe_world.y, toe_r_world.y],
			absf(toe_world.y) < 0.03 and absf(toe_r_world.y) < 0.03 and absf(toe_world.y - toe_r_world.y) < 0.01)
		var mid := (toe_world + toe_r_world) * 0.5
		_look_from(mid + Vector3(2.2, 1.0, 0.15), mid + Vector3(0.0, 0.75, 0.0))
		await _shot("standup_ground_sideon")
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

	# A close vest shot: pulled back enough to read the strap/panel silhouette, the near-side cross
	# patch, and the clearance behind the neck.
	_look_from(Vector3(0.85, 1.15, 1.05), Vector3(0.0, 1.05, 0.20))
	await _play_and_settle("Idle", 0.2)
	await _shot("vest_closeup")

	# Looking down onto the top of the vest, where the centred cross decal actually sits (Revision
	# 7: it is on TOP of the vest body, roughly chest-bone height plus the vest's own local radius,
	# not level with the chest bone itself -- framing it side-on like the old shot left it out of
	# frame, which is part of why it read as "not there" even once the colour/thickness were fixed).
	var chest_bi: int = model.skeleton.find_bone("chest")
	var chest_world: Vector3 = model.skeleton.global_transform * model.skeleton.get_bone_global_pose(chest_bi).origin if chest_bi >= 0 else Vector3(0, 1.05, 0.2)
	var cross_target: Vector3 = chest_world + Vector3(0.0, 0.16, 0.0)
	_look_from(cross_target + Vector3(0.30, 0.30, 0.14), cross_target)
	await _shot("vest_cross_patch")

	# A head-on-neck closeup: the skull volume between the neck and the jaw, the ears attached to
	# it, and the jaw/mouth line -- the piece Zach asked to see explicitly.
	var head_bi: int = model.skeleton.find_bone("head")
	var head_world2: Vector3 = model.skeleton.global_transform * model.skeleton.get_bone_global_pose(head_bi).origin if head_bi >= 0 else Vector3(0, 1.4, 0.7)
	_look_from(head_world2 + Vector3(0.32, -0.24, 0.05), head_world2 + Vector3(0.0, 0.10, 0.02))
	await _shot("head_closeup")

	# Full-body and close-up shots of the leg-to-torso junctions, from BOTH sides of the dog (Zach:
	# the ".R" bones mirror rotation, but that says nothing about whether the mesh geometry itself
	# is actually symmetric -- check both flanks, not just the one every other shot happens to
	# favour). "Left"/"right" are read off the actual mirrored bones' world positions, not guessed
	# world-space signs, so this is correct regardless of the asset's yaw/scale.
	await _play_and_settle("Idle", 0.2)
	var chest_bi2: int = model.skeleton.find_bone("chest")
	var chest_world2: Vector3 = model.skeleton.global_transform * model.skeleton.get_bone_global_pose(chest_bi2).origin
	var thigh_l: Vector3 = model.skeleton.global_transform * model.skeleton.get_bone_global_pose(model.skeleton.find_bone("thigh.L")).origin
	var thigh_r: Vector3 = model.skeleton.global_transform * model.skeleton.get_bone_global_pose(model.skeleton.find_bone("thigh.R")).origin
	var to_left: Vector3 = (thigh_l - chest_world2)
	to_left.y = 0.0
	to_left = to_left.normalized()
	var to_right: Vector3 = -to_left
	var up_a := Vector3(0, 0.55, 0.15)
	for side_name in ["left", "right"]:
		var side_dir: Vector3 = to_left if side_name == "left" else to_right
		_look_from(chest_world2 + side_dir * 1.9 + up_a, chest_world2 + Vector3(0, -0.15, 0))
		await _shot("leg_junctions_%s" % side_name)
		var shoulder_bone := "upperarm.L" if side_name == "left" else "upperarm.R"
		var shoulder_w: Vector3 = model.skeleton.global_transform * model.skeleton.get_bone_global_pose(model.skeleton.find_bone(shoulder_bone)).origin
		_look_from(shoulder_w + side_dir * 0.35 + Vector3(0, 0.05, 0.05), shoulder_w)
		await _shot("leg_junction_front_%s" % side_name)
		var thigh_bone := "thigh.L" if side_name == "left" else "thigh.R"
		var thigh_w: Vector3 = model.skeleton.global_transform * model.skeleton.get_bone_global_pose(model.skeleton.find_bone(thigh_bone)).origin
		_look_from(thigh_w + side_dir * 0.35 + Vector3(0, 0.05, 0.05), thigh_w)
		await _shot("leg_junction_hind_%s" % side_name)

	# Vest-vs-front-leg clearance, from both sides, at idle, mid-walk and the fully reared standup
	# pose (Zach: the vest now clips the leg junctions Revision 4 widened; this is exactly the kind
	# of thing that can look fine on one side/pose and not another, so check all of them).
	for side_name in ["left", "right"]:
		var side_dir: Vector3 = to_left if side_name == "left" else to_right
		var shoulder_bone := "upperarm.L" if side_name == "left" else "upperarm.R"
		var shoulder_bi: int = model.skeleton.find_bone(shoulder_bone)

		await _play_and_settle("Idle", 0.2)
		var sw: Vector3 = model.skeleton.global_transform * model.skeleton.get_bone_global_pose(shoulder_bi).origin
		_look_from(sw + side_dir * 0.4 + Vector3(0, 0.1, 0.08), sw)
		await _shot("vest_leg_clear_idle_%s" % side_name)

		await _play_and_settle("Walk", model.anim.get_animation("Walk").length * 0.35)
		sw = model.skeleton.global_transform * model.skeleton.get_bone_global_pose(shoulder_bi).origin
		_look_from(sw + side_dir * 0.4 + Vector3(0, 0.1, 0.08), sw)
		await _shot("vest_leg_clear_walk_%s" % side_name)

		if model.anim.has_animation("StandUp"):
			await _play_and_settle("StandUp", model.anim.get_animation("StandUp").length)
			sw = model.skeleton.global_transform * model.skeleton.get_bone_global_pose(shoulder_bi).origin
			_look_from(sw + side_dir * 0.4 + Vector3(0, 0.1, 0.08), sw)
			await _shot("vest_leg_clear_standup_%s" % side_name)

	# Soul-drain sequence (2026-09-24 design change: the attack is now a dementor-style drain, not
	# a chase/bite). Same naming contract as service-dog-brain: RearUp, DrainIdle, UprightWalk,
	# DropDown, plus the throat orb's `set_drain_glow` hook.
	var poser: Node = model.skeleton.get_node_or_null("DogPoser")
	_check("DogPoser found", poser != null)

	if model.anim.has_animation("RearUp"):
		var rl: float = model.anim.get_animation("RearUp").length
		_look_from(Vector3(1.55, 1.05, 1.75), Vector3(0, 1.35, 0.0))
		for i in [0.0, 0.5, 1.0]:
			await _play_and_settle("RearUp", rl * i)
			await _shot("rear_up_%02d" % int(i * 100))
	_check("RearUp plays", model.anim.has_animation("RearUp"))

	if model.anim.has_animation("DrainIdle"):
		await _play_and_settle("DrainIdle", model.anim.get_animation("DrainIdle").length * 0.25)
		if poser != null:
			poser.look_at = Vector3(0, 1.2, 2.0)
			poser.look_weight = 1.0
			poser.set_drain_glow(1.0)
		await get_tree().process_frame
		var head_bi3: int = model.skeleton.find_bone("head")
		var head_world3: Vector3 = model.skeleton.global_transform * model.skeleton.get_bone_global_pose(head_bi3).origin
		_look_from(head_world3 + Vector3(0.65, -0.05, 0.35), head_world3 + Vector3(0.0, 0.05, 0.0))
		await _shot("drain_idle")
		if poser != null:
			poser.look_weight = 0.0
	_check("DrainIdle plays", model.anim.has_animation("DrainIdle"))

	if model.anim.has_animation("UprightWalk"):
		_look_from(Vector3(1.6, 1.15, 1.8), Vector3(0, 1.35, 0.0))
		await _play_and_settle("UprightWalk", model.anim.get_animation("UprightWalk").length * 0.25)
		await _shot("upright_walk_midstride")
	_check("UprightWalk plays", model.anim.has_animation("UprightWalk"))

	if model.anim.has_animation("DropDown"):
		var dl: float = model.anim.get_animation("DropDown").length
		_look_from(Vector3(1.55, 1.05, 1.75), Vector3(0, 1.0, 0.0))
		for i in [0.0, 0.5, 1.0]:
			await _play_and_settle("DropDown", dl * i)
			await _shot("drop_down_%02d" % int(i * 100))
	_check("DropDown plays", model.anim.has_animation("DropDown"))

	# Orb glow control: a real, small, near-black-at-rest mesh, fading to a ghostly green when
	# set_drain_glow(1.0) is called, and (Zach) only meant to read from in front of the dog -- so
	# shoot it from the front AND from directly behind, at rest and while lit, four shots total.
	# "Front"/"behind" are read off the skeleton's own head/jaw bones (not a guessed world axis), so
	# this is correct regardless of the asset's registered yaw.
	if poser != null:
		var orb: Node = poser.get_node_or_null("../OrbAttach/Orb")
		_check("Orb node found", orb != null)
		await _play_and_settle("DrainIdle", 0.0)
		var head_bi4: int = model.skeleton.find_bone("head")
		var head_world4: Vector3 = model.skeleton.global_transform * model.skeleton.get_bone_global_pose(head_bi4).origin
		# "Front"/"behind" the DOG, not the head bone's own (pitched-back-when-reared) axis --
		# Assets.spawn() guarantees every monster's forward is -Z in its own root's basis
		# (assets.gd's spawn() doc comment), so this is correct regardless of the current pose.
		var fwd: Vector3 = -model.rig.global_transform.basis.z
		fwd.y = 0.0
		fwd = fwd.normalized()
		var side: Vector3 = fwd.cross(Vector3.UP).normalized()
		for glow_v in [0.0, 1.0]:
			var tag := "off" if glow_v < 0.5 else "on"
			poser.set_drain_glow(glow_v)
			_look_from(head_world4 + fwd * 0.55 + side * 0.15 + Vector3(0, 0.05, 0), head_world4)
			await get_tree().process_frame
			await _shot("orb_glow_%s" % tag)
			_look_from(head_world4 - fwd * 0.55 + side * 0.15 + Vector3(0, 0.05, 0), head_world4)
			await get_tree().process_frame
			await _shot("orb_behind_%s" % tag)
		poser.set_drain_glow(0.0)

	print("[dog_lab] ------------------------------------------")
	print("[dog_lab] result: ", "PASS" if ok else "FAIL")
	get_tree().quit(0 if ok else 1)
