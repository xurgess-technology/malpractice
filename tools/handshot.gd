extends Node3D
## BETTER HANDS: a contact sheet of every holdable item in the first-person hands.
##
## For each kind (Items.ITEMS + the loot table, minus worn things) it gives a local player the item,
## lets the lower-and-raise finish and takes two pictures: the player's own view, and a close-up from
## the side of the holding hand (the same hands, a second camera), which is where clipping shows. Then
## the action poses (jab, saw, shove, throw, bonk). Everything lands in tools/hand_shots/ with one
## contact sheet, tools/hand_shots/contact_sheet.png (and contact_actions.png).
##
##   tools\handshot.ps1                         (minimized window, never takes focus)
##   godot --path . --resolution 1280x720 res://tools/handshot.tscn -- --only=bone_saw,scalpel
##
## Also prints each kind's clip score from the bake (tools/gripbake.gd): surface points of the model
## still inside the hand after the grip is solved. 0 is clean. `--only=anatomy` shows bare hands.

const HB := preload("res://scripts/hospital_builder.gd")
const PlayerScript := preload("res://scripts/player.gd")
const StyleLab := preload("res://tools/style_lab/style_lab.gd")
const HandsFPScript := preload("res://scripts/hands/fp_hands.gd")
const LootTable := preload("res://scripts/economy/loot_table.gd")
const WindupScript := preload("res://scripts/combat/windup.gd")
const SHOT_DIR := "res://tools/hand_shots"
const THUMB := Vector2i(640, 360)
const COLS := 3

## The style lab's stand-in game, plus what a local player's own step and hands read.
class HandGame extends StyleLab.LabGame:
	enum Phase {MENU, SHIFT}
	var paused := false
	var phase := Phase.SHIFT
	var trinkets = null



class HandCombat extends StyleLab.LabCombat:
	var windup = null

	func is_winding(_p: Node) -> bool:
		return false

	func jab_prompt(_p: Node) -> String:
		return ""

	func is_usable(_kind: String) -> bool:
		return false


var game: Node
var me: Node
var lab_combat: Node
var side_cam: Camera3D
var label: Label
var only: Array = []
var cells: Array = []   # [name, fp Image, side Image]
var action_cells: Array = []
var scores := {}


func _ready() -> void:
	get_tree().create_timer(900.0).timeout.connect(func(): print("[handshot] timed out"); get_tree().quit(1))
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			only = Array(a.split("=")[1].split(","))
	game = HandGame.new()
	game.name = "LabGame"
	add_child(game)
	lab_combat = HandCombat.new()
	game.add_child(lab_combat)
	game.combat = lab_combat
	_build_level()
	add_child(Look.make_environment())
	add_child(Look.make_post_layer())
	me = PlayerScript.new_player(1, "Me", true)
	game.add_child(me)
	game.players[1] = me
	me.bot_active = true
	me.name_tag.visible = false
	me.teleport(Vector3(14.5 * C.TILE, 0.0, 3.0 * C.TILE))
	# The player's own step (input, movement) needs a whole game; the hands only need _process.
	me.set_physics_process(false)
	me.rotation.y = PI * 0.5
	me.head.rotation.x = -0.12
	me.set_flashlight(true)
	var cl := CanvasLayer.new()
	cl.layer = 50
	add_child(cl)
	label = Label.new()
	label.position = Vector2(14, 10)
	label.add_theme_font_size_override("font_size", 30)
	label.add_theme_color_override("font_color", Color(1, 1, 0.8))
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 8)
	cl.add_child(label)
	side_cam = Camera3D.new()
	side_cam.fov = 40.0
	side_cam.near = 0.02
	me.camera.add_child(side_cam)
	for i in 8:
		await get_tree().physics_frame
	await _run()


func _build_level() -> void:
	var rows := PackedStringArray([
		"#################",
		"#...............#",
		"#...............#",
		"#...............#",
		"#...............#",
		"#...............#",
		"#################",
	])
	var info := {}
	var level: Node3D = HB.build({"rows": rows, "seed": 3, "lights": [Vector2i(4, 2), Vector2i(10, 4), Vector2i(14, 3)]}, info)
	add_child(level)
	game.level_info = info


static func holdable_kinds() -> Array:
	var out: Array = []
	for k in Items.ITEMS.keys():
		if not Items.is_worn(k):
			out.append(k)
	for k in LootTable.kinds():
		if not out.has(k):
			out.append(k)
	return out


func _give(kind: String) -> void:
	for i in me.slots.size():
		me.clear_slot(i)
	if kind == "":
		return
	var n := 3 if Items.stacks(kind) else 1
	var i: int = me.take_into(kind, n, 50 if Items.is_loot(kind) else 0)
	me.selected = maxi(0, i)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _grab(crop := Rect2i()) -> Image:
	# A minimized window never draws on its own: draw this frame by hand.
	await get_tree().process_frame
	RenderingServer.force_draw()
	var img := get_viewport().get_texture().get_image()
	if crop.size != Vector2i.ZERO:
		img = img.get_region(crop)
	img.resize(THUMB.x, THUMB.y, Image.INTERPOLATE_LANCZOS)
	return img


## A close-up of the holding hand(s) from outside: to the left of and a little above the left hand
## for one-handed things, from the upper left for two-handed ones.
func _side_view(two: bool) -> Image:
	var hands: Node3D = me.hands
	var focus: Vector3
	if two:
		focus = (hands.arm_l.position + hands.arm_r.position) * 0.5
	else:
		focus = hands.arm_l.position + Vector3(0.03, 0.02, -0.05)
	var eye := focus + (Vector3(-0.3, 0.14, -0.08) if not two else Vector3(-0.55, 0.3, 0.05))
	side_cam.position = eye
	side_cam.look_at(me.camera.to_global(focus), me.camera.global_transform.basis.y)
	side_cam.current = true
	var img := await _grab()
	me.camera.current = true
	return img


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SHOT_DIR))
	var f := FileAccess.open(SHOT_DIR + "/.gdignore", FileAccess.WRITE)
	if f != null:
		f.close()
	me.camera.current = true
	if only.has("anatomy"):
		await _anatomy()
	for kind in holdable_kinds():
		if not only.is_empty() and not only.has(kind):
			continue
		lab_combat.act = {}
		_give(kind)
		label.text = kind
		await _frames(3)
		me.hands._raise = 0.0
		await _frames(26)
		var fp := await _grab()
		var two := int(ItemModels.grip(kind).hands) >= 2
		label.text = kind + "  (side)"
		var side := await _side_view(two)
		cells.append([kind, fp, side])
		var bk: Dictionary = preload("res://scripts/hands/grips.gd").GripBake.BAKE.get("%s:1" % kind, {})
		scores[kind] = bk.get("clip", "not baked")
		fp.save_png(ProjectSettings.globalize_path("%s/%s_fp.png" % [SHOT_DIR, kind]))
		side.save_png(ProjectSettings.globalize_path("%s/%s_side.png" % [SHOT_DIR, kind]))
		print("[handshot] ", kind, "  clip=", scores.get(kind, "?"))
	if only.is_empty() or only.has("actions"):
		await _actions()
	_sheet(cells, SHOT_DIR + "/contact_sheet.png")
	if not action_cells.is_empty():
		_sheet(action_cells, SHOT_DIR + "/contact_actions.png")
	print("[handshot] done")
	get_tree().quit(0)


## Bare hands in front of the camera: open, relaxed, fist, from the back and from the palm side.
func _anatomy() -> void:
	var Arms := preload("res://scripts/hands/fp_arms.gd")
	me.hands.visible = false
	me.set_flashlight(false)
	var views := [["open", 0.0], ["relaxed", 0.3], ["half", 0.6], ["fist", 1.0]]
	for v in views:
		var root := Node3D.new()
		root.position = Vector3(0, -0.02, -0.26)
		me.camera.add_child(root)
		for k in 2:
			var arm := Arms.make_arm(-1.0 if k == 0 else 1.0, me.colour)
			root.add_child(arm)
			Arms.set_curl(arm, float(v[1]), -1.0 if k == 0 else 1.0)
			# left: back of the hand to the camera, fingers up; right: palm to the camera
			var n := Vector3(0, 0, -1) if k == 0 else Vector3(0, 0, 1)
			var f := Vector3(0, 1, 0)
			var z := -f
			arm.transform = Transform3D(Basis(n.cross(z), n, z), Vector3(-0.09 if k == 0 else 0.09, 0.0, 0.0))
		label.text = "anatomy " + String(v[0])
		HandsFPScript.dress(root)
		await _frames(2)
		var a := await _grab(Rect2i(320, 100, 640, 360))
		root.rotation.y = 1.2
		var b := await _grab(Rect2i(320, 100, 640, 360))
		cells.append(["anatomy_" + String(v[0]), a, b])
		a.save_png(ProjectSettings.globalize_path("%s/anatomy_%s_a.png" % [SHOT_DIR, v[0]]))
		b.save_png(ProjectSettings.globalize_path("%s/anatomy_%s_b.png" % [SHOT_DIR, v[0]]))
		root.queue_free()
	me.hands.visible = true
	me.set_flashlight(true)


func _act(k: String, ph: int, u: float, charge := 0.0) -> Dictionary:
	return {"k": k, "ph": ph, "t": 0.0, "u": u, "charge": charge, "c": charge}


func _actions() -> void:
	var list := [
		["jab_windup", "anesthetic", _act("jab", WindupScript.WINDUP, 1.0)],
		["jab_strike", "anesthetic", _act("jab", WindupScript.STRIKE, 1.0)],
		["saw_windup", "bone_saw", _act("saw", WindupScript.WINDUP, 0.45)],
		["saw_strike", "bone_saw", _act("saw", WindupScript.STRIKE, 0.5)],
		["shove_charge", "", _act("shove", WindupScript.WINDUP, 1.0, 1.0)],
		["shove_strike", "", _act("shove", WindupScript.STRIKE, 1.0, 1.0)],
		["throw_windup_scalpel", "scalpel", {}],
		["throw_windup_monitor", "heart_monitor", {}],
		["hammer_bonk", "reflex_hammer", {}],
		["torch_off", "bone_saw", {}],
	]
	for a in list:
		lab_combat.act = {}
		me.throw_wind = 0.0
		me.set_flashlight(true)
		_give(String(a[1]))
		label.text = a[0]
		await _frames(3)
		me.hands._raise = 0.0
		await _frames(20)
		var name: String = a[0]
		if name.begins_with("throw"):
			for i in 50:
				me.throw_wind = minf(1.0, i / 35.0)
				await get_tree().process_frame
		elif name == "hammer_bonk":
			me.start_swing()
			for i in 9:
				me._tick_swing(1.0 / 60.0)
				await get_tree().process_frame
		elif name == "torch_off":
			me.set_flashlight(false)
			await _frames(4)
		else:
			lab_combat.act = a[2]
			await _frames(if_strike(a[2]))
		var fp := await _grab()
		var two := String(a[1]) != "" and int(ItemModels.grip(String(a[1])).hands) >= 2
		var side := await _side_view(two)
		action_cells.append([name, fp, side])
		fp.save_png(ProjectSettings.globalize_path("%s/act_%s_fp.png" % [SHOT_DIR, name]))
		print("[handshot] action ", name)
	me.throw_wind = 0.0
	lab_combat.act = {}


func if_strike(act: Dictionary) -> int:
	return 1 if int(act.get("ph", 0)) == WindupScript.STRIKE else 20


func _sheet(list: Array, path: String) -> void:
	var cw := THUMB.x * 2 + 8
	var ch := THUMB.y + 8
	var rows := int(ceil(list.size() / float(COLS)))
	var sheet := Image.create(cw * COLS + 8, ch * rows + 8, false, Image.FORMAT_RGB8)
	sheet.fill(Color(0.08, 0.08, 0.09))
	for i in list.size():
		var c: Array = list[i]
		var x := 8 + (i % COLS) * cw
		var y := 8 + (i / COLS) * ch
		var a: Image = c[1]
		var b: Image = c[2]
		a.convert(Image.FORMAT_RGB8)
		b.convert(Image.FORMAT_RGB8)
		sheet.blit_rect(a, Rect2i(Vector2i.ZERO, THUMB), Vector2i(x, y))
		sheet.blit_rect(b, Rect2i(Vector2i.ZERO, THUMB), Vector2i(x + THUMB.x, y))
	sheet.save_png(ProjectSettings.globalize_path(path))
	print("[handshot] wrote ", path)
