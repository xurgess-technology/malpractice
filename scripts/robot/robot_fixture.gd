extends Node3D
## THE SURGICAL ROBOT's body: the fixture at the head end of the OR's first table. Built by
## scripts/robot/robot.gd on every machine each time a level is built, and posed by it every frame
## from replicated state (animate()). It owns no rules: the prompt and E are handed straight back to
## robot.gd.
##
## Local frame: origin on the floor under the middle of the base, +X toward the table it serves (so
## the boom reaches out over the patient's head end), +Z into the room. What it looks like: a heavy
## off-white column on a dark wheeled base, a boom arching out over the table, and three long,
## spindly jointed arms hanging from a hub on the end of it, each ending in an instrument, with a
## camera "eye" on a stalk in the middle. The core socket is a window on the +Z face of the column.
## Dead, the arms hang limp to the floor like a spider's; powered they fold up under the hub; with
## somebody remoted in they rise over the table, and while that somebody operates they reach down
## to the site on every machine.

const ItemModelsScript := preload("res://scripts/item_models.gd")

const ENAMEL := Color(0.84, 0.85, 0.82)
const STEEL := Color(0.4, 0.43, 0.45)
const DARK := Color(0.08, 0.09, 0.1)
const TEAL := Color(0.25, 0.95, 0.85)
const AMBER := Color(1.0, 0.62, 0.15)
const RED := Color(1.0, 0.16, 0.1)

## The hub the arms hang from, and the camera eye (local to the fixture).
const HUB := Vector3(1.0, 2.05, 0.0)
const EYE := Vector3(0.82, 1.95, 0.0)
## The core socket's window on the +Z face of the column.
const SOCKET := Vector3(0.0, 0.98, 0.215)
const UPPER := 0.62
const FORE := 0.58
const TIP := 0.14
## Shoulder offsets round the hub and which way each arm's elbow bows out (+Z / -Z / back).
const SHOULDERS := [Vector3(0.94, 1.99, -0.2), Vector3(1.14, 1.99, 0.0), Vector3(0.94, 1.99, 0.2)]
const SIDES := [-1.0, 0.0, 1.0]
## The instrument each arm ends in: a blade, a grasper, a needle driver.
const TOOLS := ["blade", "grasper", "needle"]
const STATUS_LEDS := 6

var robot: Node = null   # scripts/robot/robot.gd, which answers the prompt and E

var arms: Array = []     # per arm: {shoulder, cur, upper, fore, elbow, wrist, tip}
var eye_mount: Node3D    # turns with the operator's look
var lens_mat: StandardMaterial3D
var led_mat: StandardMaterial3D
var led_dim: StandardMaterial3D
var leds: Array = []
var core_node: Node3D
var light: SpotLight3D
var _t := 0.0
var _seed := 0.0


func _init() -> void:
	name = "SurgicalRobot"
	add_to_group("interactable")
	set_meta("interact_id", "robot")
	_build()


func interact_prompt(p) -> String:
	return robot.fixture_prompt(p) if robot != null else ""


func interact_hold() -> float:
	return 0.0


func interact(p) -> void:
	if robot != null:
		robot.fixture_used(p)


# =============================================================================== the model

static func _mat(col: Color, rough := 0.55, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = rough
	m.metallic = metal
	return m


static func _glow(col: Color, energy: float) -> StandardMaterial3D:
	var m := _mat(col * 0.4, 0.4)
	m.emission_enabled = true
	m.emission = col
	m.emission_energy_multiplier = energy
	return m


func _box(size: Vector3, mat: Material, pos: Vector3, parent: Node3D = self) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi


func _cyl(r: float, h: float, mat: Material, pos: Vector3, rot_deg := Vector3.ZERO, parent: Node3D = self, sides := 14) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r
	c.height = h
	c.radial_segments = sides
	c.rings = 1
	mi.mesh = c
	mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees = rot_deg
	parent.add_child(mi)
	return mi


func _ball(r: float, mat: Material, pos: Vector3, parent: Node3D = self) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = 12
	s.rings = 6
	mi.mesh = s
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi


## A unit cylinder along +Y, to be stretched between two points by _span().
func _limb(r: float, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = r * 0.8
	c.bottom_radius = r
	c.height = 1.0
	c.radial_segments = 10
	c.rings = 1
	mi.mesh = c
	mi.material_override = mat
	add_child(mi)
	return mi


func _build() -> void:
	var enamel := _mat(ENAMEL, 0.45)
	var steel := _mat(STEEL, 0.35, 0.75)
	var dark := _mat(DARK, 0.7)
	lens_mat = _glow(TEAL, 0.0)
	led_mat = _glow(TEAL, 0.0)
	led_dim = _mat(Color(0.12, 0.13, 0.13), 0.5)
	# The base: a dark, heavy wheeled plinth.
	_box(Vector3(0.78, 0.16, 0.86), dark, Vector3(0, 0.13, 0))
	for x in [-0.3, 0.3]:
		for z in [-0.34, 0.34]:
			_cyl(0.05, 0.05, steel, Vector3(x, 0.05, z), Vector3(90, 0, 0))
	# The column, a little narrower toward the top, and its cap.
	_box(Vector3(0.44, 0.9, 0.44), enamel, Vector3(0, 0.66, 0))
	_box(Vector3(0.38, 0.62, 0.38), enamel, Vector3(0, 1.42, 0))
	_box(Vector3(0.46, 0.05, 0.46), steel, Vector3(0, 1.12, 0))
	_box(Vector3(0.42, 0.06, 0.42), dark, Vector3(0, 1.75, 0))
	# The boom: up out of the cap and out over the table to the hub.
	_box(Vector3(0.2, 0.34, 0.2), steel, Vector3(0.0, 1.93, 0))
	_box(Vector3(1.12, 0.14, 0.16), enamel, Vector3(0.5, 2.12, 0))
	_cyl(0.16, 0.12, enamel, HUB + Vector3(0, 0.05, 0))
	_cyl(0.13, 0.05, dark, HUB - Vector3(0, 0.03, 0))
	# A loose bundle of cable hanging from the boom back into the column.
	_cyl(0.018, 0.5, dark, Vector3(-0.19, 1.86, 0.06), Vector3(0, 0, 8))
	_cyl(0.014, 0.46, dark, Vector3(-0.2, 1.85, -0.05), Vector3(0, 0, -6))
	# The core socket: a steel frame round a black cavity on the +Z face.
	_box(Vector3(0.24, 0.36, 0.05), steel, SOCKET + Vector3(0, 0, -0.005))
	_box(Vector3(0.17, 0.29, 0.03), dark, SOCKET + Vector3(0, 0, 0.012))
	core_node = ItemModelsScript.make("robot_core")
	core_node.position = SOCKET + Vector3(0, -0.11, 0.035)
	core_node.visible = false
	add_child(core_node)
	# Status lights: a strip down the +Z face above the socket, and one on the -Z face.
	for i in STATUS_LEDS:
		var led := _box(Vector3(0.05, 0.025, 0.015), led_dim, Vector3(-0.125 + i * 0.05, 1.3, 0.198))
		leds.append(led)
	for i in STATUS_LEDS:
		var led2 := _box(Vector3(0.05, 0.025, 0.015), led_dim, Vector3(-0.125 + i * 0.05, 1.3, -0.198))
		leds.append(led2)
	# A stencilled name on the +Z face under the socket.
	var tag := Label3D.new()
	tag.text = "ST. DOE'S\nAUTOSURGEON"
	tag.font_size = 22
	tag.pixel_size = 0.0022
	tag.modulate = Color(0.2, 0.22, 0.24)
	tag.outline_size = 0
	tag.position = Vector3(0, 0.55, 0.222)
	tag.shaded = true
	add_child(tag)
	# The eye: a stalk from the hub and a lens housing that turns with the operator's look.
	_cyl(0.025, 0.12, steel, EYE + Vector3(0, 0.07, 0))
	eye_mount = Node3D.new()
	eye_mount.position = EYE
	add_child(eye_mount)
	var housing := _cyl(0.055, 0.14, dark, Vector3(0.03, 0, 0), Vector3(0, 0, 90), eye_mount)
	housing.name = "Housing"
	_cyl(0.04, 0.02, lens_mat, Vector3(0.105, 0, 0), Vector3(0, 0, 90), eye_mount)
	light = SpotLight3D.new()
	light.spot_range = 4.5
	light.spot_angle = 38.0
	light.spot_attenuation = 1.2
	light.light_energy = 0.0
	light.shadow_enabled = false
	light.light_volumetric_fog_energy = 0.0
	light.light_color = Color(0.85, 0.95, 1.0)
	light.visible = false
	# A SpotLight shines along its own -Z; the eye looks along the mount's +X.
	light.rotation_degrees = Vector3(0, -90, 0)
	light.position = Vector3(0.12, 0, 0)
	eye_mount.add_child(light)
	# The three arms: an enamel upper arm, a steel forearm, dark joints, and an instrument.
	for i in SHOULDERS.size():
		var s: Vector3 = SHOULDERS[i]
		_ball(0.045, dark, s)
		var a := {
			"shoulder": s,
			"side": float(SIDES[i]),
			"upper": _limb(0.032, enamel),
			"fore": _limb(0.022, steel),
			"elbow": _ball(0.036, dark, s),
			"wrist": _ball(0.026, dark, s),
			"tip": _limb(0.008, steel),
			"jaw": _limb(0.006, lens_mat if TOOLS[i] == "blade" else steel),
			"cur": _dead_target(i),
		}
		arms.append(a)
	# Something to bump into: the base and column (the boom and arms are overhead).
	var body := StaticBody3D.new()
	body.collision_layer = 1   # C.L_WORLD
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.78, 1.8, 0.86)
	cs.shape = box
	cs.position = Vector3(0, 0.9, 0)
	body.add_child(cs)
	add_child(body)
	_pose_arms(0.0, 1.0)


## Where each arm's wrist is while the robot is dead: hanging to the floor, splayed.
func _dead_target(i: int) -> Vector3:
	var s: Vector3 = SHOULDERS[i]
	return s + Vector3(-0.5 + 0.08 * float(i), -0.9, float(SIDES[i]) * 0.34 + 0.06)


func _folded_target(i: int, t: float) -> Vector3:
	var s: Vector3 = SHOULDERS[i]
	var breathe := sin(t * 1.3 + float(i) * 1.7) * 0.02
	return s + Vector3(-0.42, -0.42 + breathe, float(SIDES[i]) * 0.26)


## Poised over the table (the head end is about local x 1.05), a slow, uneasy sway.
func _poised_target(i: int, t: float) -> Vector3:
	var sway := Vector3(sin(t * 0.9 + float(i) * 2.1) * 0.05, sin(t * 1.4 + float(i)) * 0.04, cos(t * 0.7 + float(i) * 1.3) * 0.04)
	return Vector3(1.35 + 0.18 * float(i), 1.42, float(SIDES[i]) * 0.3) + sway


# =============================================================================== posing

## state: {powered: bool, boot: 0..1 (1 done), linked: bool, site: Vector3 (global) or null,
##         look: Vector2 (yaw, pitch), operating_live: bool}
func animate(state: Dictionary, delta: float) -> void:
	_t += delta
	var powered := bool(state.get("powered", false))
	var boot := float(state.get("boot", 1.0))
	var linked := bool(state.get("linked", false))
	var site = state.get("site")
	core_node.visible = powered
	# The arms.
	var rate := 4.0
	for i in arms.size():
		var a: Dictionary = arms[i]
		var want: Vector3
		if not powered:
			want = _dead_target(i)
			rate = 3.0
		elif boot < 1.0:
			# Waking: twitches, then the arms haul themselves up into the fold.
			var k := smoothstep(0.25, 0.9, boot)
			want = _dead_target(i).lerp(_folded_target(i, _t), k)
			if boot > 0.2 and boot < 0.7:
				want += Vector3(sin(_t * 31.0 + i), sin(_t * 23.0 + i * 2.0), cos(_t * 27.0 + i)) * 0.035
			rate = 6.0
		elif site is Vector3:
			var local_site: Vector3 = to_local(site as Vector3)
			if i == 1:
				# The working arm: down to the site, its instrument just above it, never still.
				want = local_site + Vector3(0, TIP + 0.02, 0) + Vector3(sin(_t * 5.3), 0.4 * sin(_t * 7.1), cos(_t * 4.3)) * 0.018
			else:
				want = local_site + Vector3(-0.12, 0.26, float(SIDES[i]) * 0.2) + Vector3(0, sin(_t * 2.0 + i) * 0.02, 0)
			rate = 8.0
		elif linked:
			want = _poised_target(i, _t)
			rate = 3.0
		else:
			want = _folded_target(i, _t)
			rate = 2.5
		a.cur = (a.cur as Vector3).lerp(want, 1.0 - exp(-delta * rate))
	_pose_arms(_t, 1.0)
	# The eye follows the operator's look while someone is in; otherwise it rests (dead: it droops).
	var look: Vector2 = state.get("look", Vector2(0.0, -1.0))
	var want_rot := Vector3(0, look.x, look.y) if linked else (Vector3(0, 0.0, -1.25) if powered else Vector3(0, 0.25, -1.45))
	eye_mount.rotation = eye_mount.rotation.lerp(want_rot, 1.0 - exp(-delta * (14.0 if linked else 3.0)))
	# Lights: the lens, the status strip and the core.
	var col := TEAL
	var energy := 1.6
	if not powered:
		energy = 0.0
	elif boot < 1.0:
		energy = 1.6 * (1.0 if fmod(_t * 9.0, 1.0) > 0.4 * (1.0 - boot) else 0.1)
	elif site is Vector3:
		col = RED
		energy = 2.2
	elif linked:
		col = AMBER
		energy = 1.3 + 0.5 * sin(_t * 4.0)
	lens_mat.emission = col
	lens_mat.emission_energy_multiplier = energy
	led_mat.emission = col
	led_mat.emission_energy_multiplier = energy
	var lit := 0
	if powered:
		lit = STATUS_LEDS if boot >= 1.0 else int(boot * STATUS_LEDS)
	for i in leds.size():
		var on := (i % STATUS_LEDS) < lit
		if site is Vector3 and on:
			on = fmod(_t * 6.0 + float(i % STATUS_LEDS) * 0.3, 1.0) > 0.3   # busy: the strip chatters
		var m: Material = led_mat if on else led_dim
		if (leds[i] as MeshInstance3D).material_override != m:
			(leds[i] as MeshInstance3D).material_override = m
	# The camera light is on while someone is in (so the view is not black, and everyone sees it).
	var want_light := linked and powered and boot >= 1.0
	light.visible = want_light
	light.light_energy = move_toward(light.light_energy, 1.4 if want_light else 0.0, delta * 4.0)


## Two-bone reach for each arm toward its `cur`, elbows bowed up and out like a spider's knees.
func _pose_arms(_t_now: float, _k: float) -> void:
	for a in arms:
		var s: Vector3 = a.shoulder
		var target: Vector3 = a.cur
		var to := target - s
		var d := clampf(to.length(), 0.05, UPPER + FORE - 0.002)
		var n := to.normalized() if to.length() > 0.001 else Vector3.DOWN
		var side: float = a.side
		var pole := Vector3(-0.35, 1.0, side * 0.9) if side != 0.0 else Vector3(0.45, 1.0, 0.0)
		var bend := (pole - n * pole.dot(n))
		bend = bend.normalized() if bend.length() > 0.001 else Vector3.UP
		var along := (UPPER * UPPER - FORE * FORE + d * d) / (2.0 * d)
		var h := sqrt(maxf(UPPER * UPPER - along * along, 0.0))
		var elbow := s + n * along + bend * h
		var wrist := s + n * d
		_span(a.upper, s, elbow)
		_span(a.fore, elbow, wrist)
		(a.elbow as Node3D).position = elbow
		(a.wrist as Node3D).position = wrist
		# The instrument carries on along the forearm, and a short jaw kinks off its end.
		var fdir := (wrist - elbow).normalized()
		var tip_end := wrist + fdir * TIP
		_span(a.tip, wrist, tip_end)
		var kink := fdir.cross(Vector3.UP)
		kink = kink.normalized() if kink.length() > 0.001 else Vector3.RIGHT
		_span(a.jaw, tip_end, tip_end + (fdir * 0.6 + kink * 0.5).normalized() * 0.05)


## Stretch a unit +Y cylinder from `a` to `b`.
func _span(mi: MeshInstance3D, a: Vector3, b: Vector3) -> void:
	var y := b - a
	var len := y.length()
	if len < 0.0005:
		mi.visible = false
		return
	mi.visible = true
	y /= len
	var x := y.cross(Vector3.FORWARD)
	if x.length() < 0.01:
		x = y.cross(Vector3.RIGHT)
	x = x.normalized()
	var z := x.cross(y).normalized()
	mi.transform = Transform3D(Basis(x, y * len, z), (a + b) * 0.5)


## Where the robot's camera sits and which way it looks, for a look of (yaw, pitch) about the eye.
## Global. The eye looks along its mount's +X.
func eye_transform(look: Vector2) -> Transform3D:
	var dir_local := Basis(Vector3.UP, look.x) * Vector3(cos(look.y), sin(look.y), 0.0)
	var from := to_global(EYE + dir_local * 0.13)
	var dir := (global_transform.basis * dir_local).normalized()
	var up := Vector3.UP if absf(dir.y) < 0.995 else global_transform.basis.x
	return Transform3D(Basis.looking_at(dir, up), from)


## Warmup: one fixture in each look (dead, booting, linked, operating), so none of its materials
## compiles in the middle of a shift.
static func warm(parent: Node3D) -> void:
	var script: GDScript = load("res://scripts/robot/robot_fixture.gd")
	var f: Node3D = script.new()
	parent.add_child(f)
	f.position = Vector3(2.0, -1.0, 1.0)
	f.animate({"powered": true, "boot": 1.0, "linked": true, "site": f.to_global(Vector3(1.4, 1.0, 0.0)), "look": Vector2(0, -1)}, 0.1)
	f.light.visible = true
	f.light.light_energy = 1.0
