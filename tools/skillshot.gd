extends Node
## SKILL TREE smoke look (docs/SKILL_TREE.md): boots into the `skill_tree` review setup, puts a palm
## on the vein machine's reader and takes shots through the scan, the growth, the grown tree, a
## picked node and a node being infused; each one twice, once as the player sees it and once as the
## bare screen texture, plus a teammate's view of the screen from across the room.
##
##   powershell -NoProfile -ExecutionPolicy Bypass -File tools\skillshot.ps1
##
## Minimized and never activated (tools/skillshot.ps1, the same WMI trick as review.ps1). Shots land
## in tools/skill_shots/. Uses a scratch save file, never the real user://skills.save.

const OUT_DIR := "res://tools/skill_shots"
const SCRATCH := "user://skillshot_skills.save"

var main: Node3D
var game: Game
var me: Player
var vm: Node


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	get_tree().create_timer(300.0).timeout.connect(func(): get_tree().quit(2))
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	game = main.game
	var waited := 0.0
	while waited < 240.0:
		await get_tree().create_timer(0.5).timeout
		waited += 0.5
		if game.phase == Game.Phase.SHIFT and game.local_player() != null:
			break
	if game.phase != Game.Phase.SHIFT or game.local_player() == null:
		print("[skillshot] never reached the shift")
		get_tree().quit(3)
		return
	await get_tree().create_timer(3.0).timeout
	me = game.local_player()
	me.bot_active = true
	me.bot_invulnerable = true
	me.bot_move = Vector2.ZERO
	vm = game.level.find_child("VeinMachine", true, false)
	if vm == null:
		print("[skillshot] no VeinMachine")
		get_tree().quit(4)
		return
	await _run()
	if FileAccess.file_exists(SCRATCH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SCRATCH))
	print("[skillshot] done")
	get_tree().quit(0)


func _run() -> void:
	Skills.use_path(SCRATCH)
	Skills.wipe()
	Skills.grant(9)
	for id in ["surg_steady", "anat_tissue_match", "anat_tolerance", "log_deep_pockets", "log_haggler"]:
		Skills.unlock(id)
	await _shot("idle_room", true)
	vm._pending = me
	Net.claim_station("veins")
	await _until(0.5)
	await _shot("scan_early")
	await _until(1.05)
	await _shot("scan_mid")
	await _until(2.3)
	await _shot("grow")
	await _until(5.5)
	await _shot("tree")
	vm.click(vm.screen.node_position("surg_quick_stitch"))
	await get_tree().create_timer(0.4).timeout
	await _shot("selected")
	vm.click(vm.screen.button_rect().get_center())
	await get_tree().create_timer(0.35).timeout
	await _shot("infusing")
	await get_tree().create_timer(1.2).timeout
	await _shot("infused")
	await _shot("onlooker", true)
	vm.click(vm.screen.node_position("surg_chief"))
	await get_tree().create_timer(0.4).timeout
	await _shot("locked_pick")
	game.vein_local_exit()
	await get_tree().create_timer(1.0).timeout
	await _shot("after", true)


func _until(t: float) -> void:
	while vm.screen.t < t:
		await get_tree().process_frame


func _shot(tag: String, room := false) -> void:
	await RenderingServer.frame_post_draw
	if room:
		await _room_shot(tag)
	else:
		var img := get_viewport().get_texture().get_image()
		img.save_png(ProjectSettings.globalize_path("%s/%s_view.png" % [OUT_DIR, tag]))
	var scr: Image = vm.viewport.get_texture().get_image()
	scr.save_png(ProjectSettings.globalize_path("%s/%s_screen.png" % [OUT_DIR, tag]))
	print("[skillshot] %s (screen t=%.2f)" % [tag, vm.screen.t])


## A teammate's view: standing back in the room, off to one side, looking at the machine.
func _room_shot(tag: String) -> void:
	var sv := SubViewport.new()
	sv.size = Vector2i(1280, 720)
	sv.world_3d = get_viewport().world_3d
	sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(sv)
	var cam := Camera3D.new()
	sv.add_child(cam)
	var centre: Vector3 = vm._centre
	var out: Vector3 = vm._out
	var side := out.cross(Vector3.UP).normalized()
	var eye := centre + out * 5.2 + side * 1.4
	eye.y = 1.65
	# A teammate sees your body and not your first-person hands.
	cam.cull_mask = (me.camera.cull_mask | (1 << 16)) & ~((1 << 17) | (1 << 18))
	me.set_mirror_self(true)
	cam.fov = 70.0
	cam.global_transform = Transform3D(Basis.looking_at(centre - Vector3(0, 0.4, 0) - eye, Vector3.UP), eye)
	cam.current = true
	for i in 4:
		await RenderingServer.frame_post_draw
	sv.get_texture().get_image().save_png(ProjectSettings.globalize_path("%s/%s_room.png" % [OUT_DIR, tag]))
	me.set_mirror_self(false)
	sv.queue_free()
