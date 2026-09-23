extends Node3D
## The Onlooker's body (POCKETS 2 phase 6). A tall shadow with bright eyes, and nothing else.
##
## **No GLB, no skeleton, no AnimationPlayer, and that is the design rather than a shortcut.** The
## Onlooker never walks, never reaches, never falls over and never lies on a table: it pops in, it
## stands, it pops out. There is no clip for it to play, so a rig with bones would be dead weight on
## a thing that has to be legible at forty metres in the dark.
##
## Legibility at that range is the whole job, so the body is **unshaded near-black** rather than a
## lit material: a lit silhouette goes grey under the Chapel's candles and vanishes altogether in
## the Factory's fog, and the one thing that must never happen is that you cannot tell whether it is
## there. Unshaded, it is the same hole in the world under every light in the game. The eyes are
## unshaded too, at the other end: a pair of small bright discs that read before the body does.
##
## `build(model)` matches the other rigs' contract enough for MonsterModel.setup -- it parents
## itself under the model, sets `rig`, and adds a Node3D named `Head` where Monster.eye_transform
## looks for one. It sets no `skeleton` and no `anim`, so MonsterModel.play() is a no-op on it, and
## monster.gd's `_update_visual` returns early for this kind rather than asking for a shaper.
##
## CC0 assets: none. Searched for a "tall shadow figure" CC0 model and there is nothing that is not
## either a fully modelled monster or a low-poly human; a silhouette wants to be a silhouette, so
## this is primitives. Recorded in ASSETS.md.

## How tall the shadow stands, metres. Half a head above the Night Nurse, who is the tallest thing
## that walks: at a distance the only cue you have is how it scales against a door frame.
const TALL := 2.65
## Eye height as a share of TALL, and how far apart the two eyes sit.
const EYE_AT := 0.93
const EYE_GAP := 0.135
const EYE_R := 0.075
## The body's colour. Not pure black: a hair of blue keeps it from reading as a hole in the
## depth buffer when it stands against a black ceiling.
const SHADOW := Color(0.021, 0.021, 0.031)
const EYE_COLOR := Color(1.0, 0.96, 0.86)
## The glow around the eyes, and why it exists at all.
##
## **The smoke look is what put it here.** At four metres with a torch on it the body read exactly
## as intended -- a tall black silhouette, two bright eyes -- and at thirty metres in a dark
## corridor it was INVISIBLE: a pair of 3.6 cm spheres subtend about one pixel at that range, and a
## one-pixel highlight does not bloom into anything. That is not a polish problem, it is the monster
## failing at its only job, because thirty metres is where you are always meant to meet it and "the
## tell is purely visual" is the whole rule. Every headless check passed while it was true.
##
## So the eyes carry a dim emissive ball around their bright cores. **It is plain emissive geometry,
## deliberately** -- the same trick the Chapel's 350 votive flames already use, which costs no light
## and always draws. An additive billboard was tried first and was the wrong tool twice over (the
## billboard throws away the node's scale unless asked not to, and the quad sat inside the skull);
## a sphere has neither failure mode and needs no texture, no transparency and no sorting.
##
## **It fades in with distance and is not there at all up close.** Sized as a constant it was a
## white blob swallowing the whole head at four metres -- the two eyes, which are the good bit,
## disappeared inside it. It is a legibility aid for the range at which geometry stops resolving,
## so it only exists at that range: nothing inside GLOW_NEAR, full by GLOW_FAR. Close up you get
## two eyes; far off you get the glow that tells you they are there.
const GLOW_NEAR := 6.0
const GLOW_FAR := 22.0
const GLOW_R := 0.22
## Emission energies: the cores are what you see up close, the ball is what you see at range.
const EYE_ENERGY := 18.0
const GLOW_ENERGY := 1.5

## The slow sway, which is the only motion it ever has: metres of lean, and seconds per cycle.
const SWAY := 0.022
const SWAY_SECONDS := 7.3

var eyes: Array[MeshInstance3D] = []
var glow_ball: MeshInstance3D = null
var head: Node3D = null
var _t := 0.0
var _phase := 0.0


static func build(model: Node3D) -> bool:
	var r: Node3D = (load("res://scripts/monsters/onlooker_rig.gd") as GDScript).new()
	r.name = "OnlookerRig"
	model.add_child(r)
	model.rig = r
	r._make()
	return true


func _make() -> void:
	_phase = randf() * TAU
	var body := StandardMaterial3D.new()
	body.albedo_color = SHADOW
	body.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	body.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	# It is a shape, not a surface: nothing on it should ever catch a highlight or a shadow edge.
	body.disable_receive_shadows = true

	# A tapered trunk -- wide at the hem, narrow at the shoulders -- a narrow neck and a small head.
	# Three cylinders is all the shape a silhouette needs, and the taper is what stops it reading as
	# a pillar.
	_limb(body, Vector3(0.0, TALL * 0.34, 0.0), 0.40, 0.23, TALL * 0.68)
	_limb(body, Vector3(0.0, TALL * 0.755, 0.0), 0.225, 0.105, TALL * 0.18)
	_limb(body, Vector3(0.0, TALL * 0.90, 0.0), 0.115, 0.098, TALL * 0.13)

	# Arms hanging dead straight at its sides, which is what makes it read as a person who is not
	# doing anything rather than as an object.
	for side in [-1.0, 1.0]:
		_limb(body, Vector3(side * 0.225, TALL * 0.52, 0.0), 0.062, 0.05, TALL * 0.42)

	head = Node3D.new()
	head.name = "Head"   # Monster.eye_transform looks for this by name.
	head.position = Vector3(0.0, TALL * EYE_AT, 0.0)
	add_child(head)

	var glow := StandardMaterial3D.new()
	glow.albedo_color = EYE_COLOR
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.emission_enabled = true
	glow.emission = EYE_COLOR
	glow.emission_energy_multiplier = EYE_ENERGY
	glow.disable_receive_shadows = true
	var sphere := SphereMesh.new()
	sphere.radius = EYE_R
	sphere.height = EYE_R * 2.0
	sphere.radial_segments = 10
	sphere.rings = 6
	for side in [-1.0, 1.0]:
		var e := MeshInstance3D.new()
		e.mesh = sphere
		e.material_override = glow
		# Models face -Z; the eyes sit just proud of the front of the head.
		e.position = Vector3(side * EYE_GAP * 0.5, 0.0, -0.088)
		e.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		head.add_child(e)
		eyes.append(e)

	# The glow: one dim emissive ball over both eyes. Unshaded and emissive like the cores, so it
	# obeys exactly the same rules they do -- occluded by the Chapel's piers, invisible through a
	# wall, and costing no light anywhere.
	var gm := StandardMaterial3D.new()
	gm.albedo_color = EYE_COLOR
	gm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	gm.emission_enabled = true
	gm.emission = EYE_COLOR
	gm.emission_energy_multiplier = GLOW_ENERGY
	gm.disable_receive_shadows = true
	var ball := SphereMesh.new()
	ball.radius = 1.0
	ball.height = 2.0
	ball.radial_segments = 12
	ball.rings = 7
	glow_ball = MeshInstance3D.new()
	glow_ball.mesh = ball
	glow_ball.material_override = gm
	# Forward of the skull, so the head's own cylinder never eats it.
	glow_ball.position = Vector3(0.0, 0.0, -0.12)
	glow_ball.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	head.add_child(glow_ball)


func _limb(mat: Material, at: Vector3, bottom: float, top: float, tall: float) -> void:
	var m := CylinderMesh.new()
	m.bottom_radius = bottom
	m.top_radius = top
	m.height = tall
	m.radial_segments = 10
	m.rings = 1
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = mat
	mi.position = at
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


## Every machine, every frame: the sway and the eye glow's size, and nothing else. It does not breathe
## and it does not fidget -- a still thing that is looking at you is worse than a twitching one.
## `viewer` is where this machine is watching from, for the eye glow; Vector3.INF leaves it alone.
func tick(delta: float, viewer := Vector3.INF) -> void:
	_t += delta
	if glow_ball != null and viewer.is_finite():
		var d: float = glow_ball.global_position.distance_to(viewer)
		var u: float = clampf((d - GLOW_NEAR) / (GLOW_FAR - GLOW_NEAR), 0.0, 1.0)
		var t: float = u * u * (3.0 - 2.0 * u) * _presence
		glow_ball.visible = t > 0.01
		if glow_ball.visible:
			var w: float = GLOW_R * t
			glow_ball.scale = Vector3(w, w, w)
			var gmat := glow_ball.material_override as StandardMaterial3D
			if gmat != null:
				gmat.emission_energy_multiplier = GLOW_ENERGY * t
	var a := _phase + _t * TAU / SWAY_SECONDS
	position.x = sin(a) * SWAY
	position.z = sin(a * 0.61) * SWAY * 0.6
	rotation.z = sin(a) * 0.012


## How solid it is, 0 gone to 1 there. The pop in and out is a scale-and-fade rather than a cut, so
## a hop reads as a relocation rather than a dropped frame.
var _presence := 1.0

func set_presence(k: float) -> void:
	_presence = k
	visible = k > 0.002
	if not visible:
		return
	scale = Vector3(1.0, lerpf(0.55, 1.0, k), 1.0)
	for e in eyes:
		var mat := e.material_override as StandardMaterial3D
		if mat != null:
			mat.emission_energy_multiplier = EYE_ENERGY * k

