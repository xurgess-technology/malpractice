class_name GraftThroat
extends RefCounted
## GRAFTING part two (docs/GRAFTING_TRACHEA.md): the grafted throat on a surgeon's body.
##
## The surgeon model has an ordinary neck, so this is the `surgeon_graft` throat built at runtime the
## way graft_eye.gd builds the grafted eye (art/stylized/st_char.py renders the same look for review,
## but there is no such GLB in the game): a see-through pane of skin standing in the front of the
## neck, the Sonographer's violet windpipe glowing behind it, and a ring of stitches round the cut.
##
## It rides a BoneAttachment3D on the neck, so it follows the body through every clip -- standing,
## lying on the table, carried -- and shows wherever the body shows: third person, other players'
## screens, the Personnel mirrors and the carry camera.
##
## `set_lock` drives the trachea material's `lock`: 0 the low violet it always has, 1 burning. Grafts
## keeps it low normally and high while the surgeon is firing Echo.

const HumanModel := preload("res://scripts/human/human_model.gd")

const NODE_NAME := "GraftThroat"
## Where the window sits, in metres from the HEAD bone in the model's own axes: down the neck, and
## out of the front of it. Measured off the surgeon model (the skin of the throat is 48 mm in front
## of the head bone at this height).
const DOWN := 0.059
const SKIN_AT := 0.048
## Each layer, out from the head bone along the model's front (-Z). Nothing can be cut out of the
## neck mesh at runtime, so the windpipe is half sunk into the throat and the pane of skin lies over
## it, standing a few millimetres proud: at this size it reads as a panel set into the throat.
const PIPE_AT := 0.050
const PANE_AT := 0.058
const STITCH_AT := 0.061
const WINDOW_H := 0.075
const WINDOW_W := 0.040
const RINGS := 5
const STITCHES := 8


## Hang a grafted throat of `kind` on `human_root`'s neck. Returns the node (free it to take the
## graft off). Null when the model has no skeleton or no `Site_eyes` (the primitive fallback body).
##
## It hangs off the head's own BoneAttachment3D -- the one the model ships with, under `Site_eyes` --
## rather than a new one, because an attachment built at runtime does not reliably resolve its bone.
## The throat is a fixed distance down and forward from the head bone, so this tracks the head
## through every clip; the neck itself does not bend independently on a surgeon.
static func attach(human_root: Node, kind: String) -> Node3D:
	if human_root == null or not is_instance_valid(human_root):
		return null
	var skel := HumanModel.skeleton(human_root)
	var site := human_root.find_child("Site_eyes", true, false) as Node3D
	if skel == null or site == null:
		return null
	var att := site.get_parent() as BoneAttachment3D
	if att == null:
		return null
	var old := att.get_node_or_null(NODE_NAME)
	if old != null:
		return old as Node3D
	var bone := skel.find_bone(att.bone_name)
	var rest := skel.get_bone_global_rest(bone) if bone >= 0 else Transform3D()
	# In the bone's frame but with the model's own axes, so "down the neck" is -Y and "out of the
	# throat" is -Z whatever the rig did to the bone.
	var b := rest.basis.orthonormalized().inverse()
	var root := Node3D.new()
	root.name = NODE_NAME
	root.transform = Transform3D(b, b * Vector3(0.0, -DOWN, 0.0))
	att.add_child(root)
	_build(root, kind)
	# Draw like the rest of the body: the same visual layers, and no shadows of its own.
	var body := HumanModel.piece(human_root, "Human")
	if body != null:
		for mi in root.find_children("*", "GeometryInstance3D", true, false):
			(mi as VisualInstance3D).layers = body.layers
			(mi as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return root


static func _find(human_root: Node) -> Node3D:
	if human_root == null or not is_instance_valid(human_root):
		return null
	var site := human_root.find_child("Site_eyes", true, false) as Node3D
	if site == null or site.get_parent() == null:
		return null
	return site.get_parent().get_node_or_null(NODE_NAME) as Node3D


## Take the graft off `human_root`.
static func detach(human_root: Node) -> void:
	var old := _find(human_root)
	if old != null:
		old.queue_free()


## The grafted throat on `human_root`, or null.
static func node_on(human_root: Node) -> Node3D:
	return _find(human_root)


## The trachea material's `lock` on a grafted throat: 0 the low violet, 1 burning while Echo fires.
static func set_lock(node: Node, v: float) -> void:
	Eyes.set_lock(node, v)
	if node == null or not is_instance_valid(node):
		return
	var pane := node.get_node_or_null("Pane") as MeshInstance3D
	if pane != null and pane.material_override is StandardMaterial3D:
		# The skin over it thins out as the light comes up, the way the Sonographer's does.
		(pane.material_override as StandardMaterial3D).albedo_color = Color(1, 1, 1, 0.50 - 0.22 * clampf(v, 0.0, 1.0))
	var light := node.get_node_or_null("ThroatGlow") as OmniLight3D
	if light != null:
		light.light_energy = 0.3 + 1.3 * clampf(v, 0.0, 1.0)


static func _build(root: Node3D, kind: String) -> void:
	var mat := Eyes.trachea_material(kind)
	# The windpipe: a short run of rings on a tube, sitting just under the skin, running up the neck.
	var pipe := Node3D.new()
	pipe.name = "Pipe"
	pipe.position = Vector3(0, 0, -PIPE_AT)
	root.add_child(pipe)
	var tube := MeshInstance3D.new()
	tube.name = "Windpipe"
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.0105
	cyl.bottom_radius = 0.0125
	cyl.height = WINDOW_H
	cyl.radial_segments = 14
	cyl.rings = 1
	tube.mesh = cyl
	tube.material_override = mat
	pipe.add_child(tube)
	for i in RINGS:
		var t := (float(i) + 0.5) / float(RINGS)
		var ring := MeshInstance3D.new()
		ring.name = "Windpipe_Ring%d" % i
		var tor := TorusMesh.new()
		var r: float = lerpf(0.0128, 0.0108, t)
		tor.inner_radius = r * 0.86
		tor.outer_radius = r * 1.32
		tor.rings = 14
		tor.ring_segments = 6
		ring.mesh = tor
		ring.material_override = mat
		ring.position = Vector3(0, WINDOW_H * (t - 0.5), 0)
		pipe.add_child(ring)
	# The pane: the surgeon's own throat skin, left thin enough to see the light through.
	var pane := MeshInstance3D.new()
	pane.name = "Pane"
	var sph := SphereMesh.new()
	sph.radius = 0.5
	sph.height = 1.0
	sph.radial_segments = 18
	sph.rings = 12
	pane.mesh = sph
	pane.scale = Vector3(WINDOW_W, WINDOW_H * 1.05, 0.016)
	pane.position = Vector3(0, 0, -PANE_AT)
	var pm := StandardMaterial3D.new()
	# Bruised, bluish and wet, not clear glass: on pale skin under a torch a white pane disappears.
	pm.albedo_color = Color(0.46, 0.37, 0.52, 0.62)
	pm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	pm.cull_mode = BaseMaterial3D.CULL_DISABLED
	pm.roughness = 0.14
	pm.metallic_specular = 0.7
	pane.material_override = pm
	root.add_child(pane)
	# The incision itself: a dark raw ring round the pane, so the window reads as something cut into
	# the throat and not a smear of light on it.
	var cut := MeshInstance3D.new()
	cut.name = "Incision"
	var ring := TorusMesh.new()
	ring.inner_radius = 0.92
	ring.outer_radius = 1.0
	ring.rings = 24
	ring.ring_segments = 6
	cut.mesh = ring
	cut.scale = Vector3(WINDOW_W * 0.58, WINDOW_W * 0.20, WINDOW_H * 0.60)
	cut.rotation_degrees = Vector3(90, 0, 0)
	var cm := StandardMaterial3D.new()
	cm.albedo_color = Color(0.30, 0.06, 0.09)
	cm.roughness = 0.25
	cut.material_override = cm
	cut.position = Vector3(0, 0, -(PANE_AT + 0.002))
	root.add_child(cut)
	# The stitches closing it, round the edge of the pane.
	var thread := StandardMaterial3D.new()
	thread.albedo_color = Color(0.09, 0.07, 0.11)
	thread.roughness = 0.8
	for i in STITCHES:
		var a := TAU * (float(i) + 0.5) / float(STITCHES)
		var dir := Vector3(cos(a) * WINDOW_W * 0.52, sin(a) * WINDOW_H * 0.56, 0.0)
		var tick := MeshInstance3D.new()
		tick.name = "ThroatStitch%d" % i
		var box := BoxMesh.new()
		box.size = Vector3(0.0018, 0.009, 0.0018)
		tick.mesh = box
		tick.material_override = thread
		var u := dir.normalized()
		var right := u.cross(Vector3.BACK).normalized()
		tick.transform = Transform3D(Basis(right, u, right.cross(u)), dir + Vector3(0, 0, -STITCH_AT))
		root.add_child(tick)
	# A little violet spill on the collar and the jaw, so the glow is light and not just a picture.
	var light := OmniLight3D.new()
	light.name = "ThroatGlow"
	light.light_color = Color(0.61, 0.42, 1.0)
	light.omni_range = 0.7
	light.light_energy = 0.3
	light.shadow_enabled = false
	light.position = Vector3(0, 0, -(SKIN_AT + 0.03))
	root.add_child(light)
