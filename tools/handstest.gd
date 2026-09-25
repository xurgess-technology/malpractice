extends Node3D
## BETTER HANDS: headless checks for the first-person hands and their baked grips.
##
##   godot --headless --fixed-fps 60 --path . res://tools/handstest.tscn
##
## - every holdable kind (and the torch and the jab's syringe) has a baked grip for every bundle size
##   the hand shows, with nothing left inside the hand (clip 0): a new item or a changed model needs
##   `tools/gripbake.tscn` re-run
## - the drawn bones sit exactly where fp_arms.chain() (what the solver curls) says they do
## - a held stack is placed by its bake and the fingers close to the baked shape
## - the torch lens goes dark with the light off, and lights again

const HandShot := preload("res://tools/handshot.gd")
const PlayerScript := preload("res://scripts/player.gd")
const Grips := preload("res://scripts/hands/grips.gd")
const Arms := preload("res://scripts/hands/fp_arms.gd")
const LootTable := preload("res://scripts/economy/loot_table.gd")

var fails := 0


func _check(ok: bool, what: String) -> void:
	print("[handstest] ", "PASS " if ok else "FAIL ", what)
	if not ok:
		fails += 1


func _ready() -> void:
	await get_tree().process_frame
	_check_bake()
	_check_chain()
	await _check_player()
	print("result=", "PASS" if fails == 0 else "FAIL")
	get_tree().quit(0 if fails == 0 else 1)


func _check_bake() -> void:
	var missing: Array = []
	var dirty: Array = []
	var kinds: Array = ["__torch", "__jab"] + HandShot.holdable_kinds()
	for kind in kinds:
		var top := 1 if String(kind).begins_with("__") else Grips.fp_shown_count(kind, 99)
		for n in range(1, top + 1):
			var key := "%s:%d" % [kind, n]
			if not Grips.GripBake.BAKE.has(key):
				missing.append(key)
				continue
			var e: Dictionary = Grips.GripBake.BAKE[key]
			if int(e.get("clip", 0)) > 0:
				dirty.append("%s (clip %d)" % [key, int(e.clip)])
			var h := Grips.fp_held(kind, n)
			if h.is_empty() or absf((h.xf as Transform3D).basis.determinant() - 1.0) > 0.02:
				dirty.append("%s (bad transform)" % key)
	_check(missing.is_empty(), "every holdable kind has a baked grip (missing: %s)" % str(missing))
	_check(dirty.is_empty(), "every baked grip is clean (%s)" % str(dirty))


func _check_chain() -> void:
	var arm := Arms.make_arm(-1.0, Color.TEAL)
	add_child(arm)
	var shape: Dictionary = Grips.GripBake.BAKE["bone_saw:1"].shape
	Arms.apply(arm, shape, -1.0)
	var segs := Arms.chain(shape, -1.0)
	var rig := arm.get_node("Rig") as Node3D
	var worst := 0.0
	for s in segs:
		var node: Node3D
		var f := int(s[3])
		var j := int(s[4])
		if f < 4:
			node = rig.get_node("F%d" % f)
			if j >= 1:
				node = node.get_node("J1")
			if j >= 2:
				node = node.get_node("J2")
		else:
			node = rig.get_node("Thumb")
			if j >= 1:
				node = node.get_node("T1")
			if j >= 2:
				node = node.get_node("T2")
		var at: Vector3 = rig.global_transform.affine_inverse() * node.global_position
		worst = maxf(worst, at.distance_to(s[0]))
	_check(worst < 0.0005, "the drawn bones match the solver's chain (worst %.5f m)" % worst)
	arm.queue_free()


func _check_player() -> void:
	var game = HandShot.HandGame.new()
	add_child(game)
	var lc = HandShot.HandCombat.new()
	game.add_child(lc)
	game.combat = lc
	var me: Node = PlayerScript.new_player(1, "Me", true)
	game.add_child(me)
	game.players[1] = me
	me.set_physics_process(false)
	me.set_flashlight(true)
	var i: int = me.take_into("bone_saw", 1, 0)
	me.selected = maxi(0, i)
	for f in 60:
		await get_tree().process_frame
	var held: Node3D = me._held_fp.get_node_or_null("Held")
	var bake := Grips.fp_held("bone_saw", 1)
	_check(held != null and (held.transform.origin - (bake.xf as Transform3D).origin).length() < 0.0001,
		"the held saw sits where its bake puts it")
	var want: Array = bake.shape.f[1]
	var got: Array = me.hands.shape_l.f[1]
	_check(absf(float(got[0]) - float(want[0])) < 0.02 and absf(float(got[1]) - float(want[1])) < 0.02,
		"the fingers close to the baked grip (%s vs %s)" % [str(got), str(want)])
	var lens := me.hands.torch.get_node("Lens") as MeshInstance3D
	_check(lens.material_override == Arms.lens_material(true), "the lens glows with the light on")
	me.set_flashlight(false)
	for f in 3:
		await get_tree().process_frame
	_check(lens.material_override == Arms.lens_material(false), "the lens goes dark with the light off")
	me.set_flashlight(true)
	for f in 3:
		await get_tree().process_frame
	_check(lens.material_override == Arms.lens_material(true), "and lights again")
