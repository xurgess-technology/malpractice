extends RefCounted
## How a strapped monster wears the walking monster's rig (`make_lying`): the fit on the OR table
## and the face of the openable head, copied from scripts/monsters/hive_look.gd so the one on
## the table is the one from the halls (the stylized Hive and Sonographer are strapped down as their own
## bodies instead: monster_builder.gd `_build_st`).
##
## Lying-root coordinates are make_lying's frame (along X, head -X, face up, unscaled). The model head
## frame is the walking look's head part: +Y up the head, +Z the face, X ear to ear, origin at the head
## bone. monster_builder.gd turns it face up onto the table: model +Y -> body -X, +Z -> +Y, +X -> -Z.

const Shapes := preload("res://scripts/monsters/shapes.gd")

## Per kind:
##   scale        the lying copy is shrunk this much to fit the 2 m table
##   offset       added after scaling (the copy's back sinks about 10 cm below its origin; legs rest at y 0)
##   head_bone    where make_lying puts the head bone (lying root, unscaled; tools/dissectiontest checks it)
##   centre       the cranium's centre in the model head frame; radii (ear to ear, up, front) of the
##                one ellipsoid that replaces the look's skull pieces and is cut open
##   spread       degrees the arms lie out from the sides (the shaper's lying_spread)
##   straps       [x, half width, top of the body] in lying root: chest over the upper arms,
##                wrists and hips, thighs, shins
##   injection    top of the upper arm, lying root
##   shoulder_x, arm_reach, hip_x   where the limbs pivot (lying root), for the straps pulled taut
const RIG := {
	"hive": {
		"scale": 1.0, "offset": Vector3(-0.01, 0.05, 0.0), "head_bone": Vector3(-0.648, 0.1204, 0.0),
		"centre": Vector3(0.0, 0.12, -0.008), "radii": Vector3(0.095, 0.11, 0.108), "spread": 2.0,
		"straps": [[-0.42, 0.29, 0.15], [0.12, 0.3, 0.27], [0.42, 0.19, 0.13], [0.68, 0.18, 0.12]],
		"injection": Vector3(-0.42, 0.1, -0.205),
		"shoulder_x": -0.57, "arm_reach": 0.75, "hip_x": -0.07,
	},
}

## Model head frame -> head-local (the dissection head: +Y face, -X crown, Z ear to ear).
const TO_HEAD := Basis(Vector3(0, 0, -1), Vector3(-1, 0, 0), Vector3(0, 1, 0))

static var _mats := {}


static func has(kind: String) -> bool:
	return RIG.has(kind)


## Head radii in the dissection head's frame (crown to chin, face to back, ear to ear), scaled.
static func head_radii(kind: String) -> Vector3:
	var d: Dictionary = RIG[kind]
	var r: Vector3 = d.radii
	return Vector3(r.y, r.z, r.x) * float(d.scale)


## The walking look's face without its skull pieces, built under a plain Node3D in the model head
## frame. The mouth sits in a `Jaw` pivot (meta `no_bake`, the builder gapes it); the ears hang from
## pivots (meta `no_bake`) at their resting turn.
static func face(kind: String, skin: Material) -> Node3D:
	var head := Node3D.new()
	head.name = "LookFace"
	_hive_face(head, skin)
	return head


static func hair_material(kind: String) -> Material:
	if kind != "hive":
		return null
	return _mat("hive_hair", func(): return Shapes.mat(Color("3a3530"), {"mottle": 0.4, "stain_scale": 60.0, "rough": 0.9, "weave": 0.4}))


## Whether a point of the head shell (head-local, scaled) has hair: the Hive's thin fringe round
## the back and sides (hive_look.gd's hair ellipsoid, a little larger so it shows on the shell).
static func has_hair(kind: String, p: Vector3) -> bool:
	if kind != "hive":
		return false
	var d: Dictionary = RIG[kind]
	var m := (d.centre as Vector3) + TO_HEAD.inverse() * (p / float(d.scale))
	var q := (m - Vector3(0, 0.125, -0.042)) / Vector3(0.1, 0.082, 0.082)
	return q.length() < 1.0


static func _mouth(head: Node3D, slit: MeshInstance3D, at: Vector3) -> void:
	var jaw := Node3D.new()
	jaw.name = "Jaw"
	jaw.position = at
	jaw.set_meta("no_bake", true)
	head.add_child(jaw)
	jaw.add_child(slit)


static func _mat(key: String, make: Callable) -> Material:
	if not _mats.has(key):
		_mats[key] = make.call()
	return _mats[key]


# ------------------------------------------------------------------------------------ Hive

static func _hive_face(head: Node3D, skin: Material) -> void:
	var dark := _mat("wi_dark", func(): return Shapes.flat(Color("120908"), 0.9))
	var lid := _mat("wi_lid", func(): return Shapes.mat(Color("7f7766"), {"mottle": 0.2, "vein": 0.5, "stain_col": Color("574a48"), "stain_amt": 0.35, "stain_scale": 40.0, "rough": 0.5}))
	var eye := _mat("wi_eye", func():
		var e := StandardMaterial3D.new()
		e.albedo_color = Color("c9c7b2")
		e.roughness = 0.12
		e.emission_enabled = true
		e.emission = Color("b8b89a")
		e.emission_energy_multiplier = 0.35
		return e)
	var pupil := _mat("wi_pupil", func(): return Shapes.flat(Color("6e6a5c"), 0.2))

	head.add_child(Shapes.cylinder(0.05, 0.16, skin, Vector3(0, -0.04, -0.01), 0.045))
	# Jowls and a double chin.
	head.add_child(Shapes.ellipsoid(Vector3(0.075, 0.05, 0.07), skin, Vector3(0, 0.035, 0.03)))
	head.add_child(Shapes.ellipsoid(Vector3(0.05, 0.035, 0.05), skin, Vector3(0, 0.0, 0.035)))
	for sx in [-1.0, 1.0]:
		# Ears: plain and small.
		head.add_child(Shapes.ellipsoid(Vector3(0.01, 0.026, 0.017), skin, Vector3(sx * 0.094, 0.11, -0.01), 8))
		# Sockets, lids heavy and dark, the eye bulging in them.
		head.add_child(Shapes.ellipsoid(Vector3(0.022, 0.016, 0.01), lid, Vector3(sx * 0.035, 0.13, 0.088), 10))
		head.add_child(Shapes.ellipsoid(Vector3(0.012, 0.01, 0.008), eye, Vector3(sx * 0.035, 0.128, 0.094), 10))
		head.add_child(Shapes.ellipsoid(Vector3(0.0045, 0.0045, 0.003), pupil, Vector3(sx * 0.034, 0.128, 0.1015), 8))
		var upper := Shapes.ellipsoid(Vector3(0.016, 0.006, 0.009), lid, Vector3(sx * 0.035, 0.137, 0.095), 8)
		upper.rotation.x = 0.3
		head.add_child(upper)
		head.add_child(Shapes.ellipsoid(Vector3(0.02, 0.008, 0.009), lid, Vector3(sx * 0.036, 0.113, 0.092), 8))
	head.add_child(Shapes.ellipsoid(Vector3(0.015, 0.022, 0.018), skin, Vector3(0, 0.1, 0.1), 8))
	# The mouth hangs open: a slack dark gap, lower lip sagging.
	_mouth(head, Shapes.ellipsoid(Vector3(0.022, 0.012, 0.008), dark, Vector3.ZERO, 10), Vector3(0, 0.052, 0.098))
	head.add_child(Shapes.ellipsoid(Vector3(0.024, 0.007, 0.01), lid, Vector3(0, 0.039, 0.098), 8))
