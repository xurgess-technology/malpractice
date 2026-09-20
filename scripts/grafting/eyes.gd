class_name Eyes
extends RefCounted
## BODY PARTS (docs/GRAFTING.md, docs/GRAFTING_TRACHEA.md): the things you can cut out of a monster,
## keep in a vat and graft into a surgeon. Four kinds, in two SITES:
##
##   eye     `eye_hive` (out of a strapped Hive) and `eye_surgeon` (a surgeon's own)
##   throat  `trachea_sonographer` (out of a strapped Sonographer) and `trachea_surgeon`
##
## All four are sellable loot (loot_table.gd) that SPOIL outside a vat: over about a minute or two
## they cloud over and dull, and a spoiled part can't be grafted. A vat stops the clock (vats.gd).
## This is the spoil system the brains used to own; the brains are gone (2026-09-18) and body parts
## are the only thing that rots now.
##
## A part's owner rides in the stack's/item's `x` string ("Hive" for one cut out of a Hive); the
## spoil clock is `bt`, the world time it came out.
##
## Parts are named "X's Y" everywhere: "Hive's eyeball", "Sonographer's trachea", "Zach's trachea".
## Everything here and in vats.gd works on a *part kind* string, so a vat holds one part of whatever
## kind and grafts.gd swaps two parts of one SITE. The class is still called Eyes for the sake of its
## many callers; everything it does is part-generic.

const KINDS := ["eye_hive", "eye_surgeon", "trachea_sonographer", "trachea_surgeon"]
## Part kind -> the noun in "X's <noun>". The owner comes from `x` (or the monster it came out of).
const NOUN := {"eye_hive": "eyeball", "eye_surgeon": "eyeball",
	"trachea_sonographer": "trachea", "trachea_surgeon": "trachea"}
## Part kind -> the GRAFT SITE it belongs to. A vat holds one part of any kind; a graft swaps two
## parts of the SAME site, and a surgeon can wear one graft per site (an eye and a trachea at once,
## docs/GRAFTING_TRACHEA.md). `eye` is the left socket, `throat` is the windpipe.
const SITE := {"eye_hive": "eye", "eye_surgeon": "eye",
	"trachea_sonographer": "throat", "trachea_surgeon": "throat"}
const SITES := ["eye", "throat"]
## Site -> the monster's part (the one that teaches something) and the surgeon's own.
const MONSTER_PART := {"eye": "eye_hive", "throat": "trachea_sonographer"}
const OWN_PART := {"eye": "eye_surgeon", "throat": "trachea_surgeon"}
## Site -> what a surgeon who is not grafted there has, in words, for the refusals.
const SITE_NORMAL := {"eye": "two normal eyes", "throat": "their own windpipe"}

const FRESH_SECONDS := 40.0     # no change for this long
const ROTTEN_SECONDS := 130.0   # fully clouded by here
const MIN_FACTOR := 0.15        # what a fully rotten part still fetches
const SPOILED_BELOW := 0.3      # a spoiled part can't be grafted

const SHADER := """
shader_type spatial;
render_mode cull_back;

uniform vec3 iris : source_color = vec3(0.25, 0.42, 0.62);
uniform float glow = 0.0;
uniform vec3 sclera_col : source_color = vec3(0.93, 0.90, 0.88);
uniform vec3 pupil_col : source_color = vec3(0.02, 0.02, 0.02);
uniform float pupil_glow = 0.0;
uniform float pupil_r = 0.30;
uniform float ring_r = 0.62;
instance uniform float rot = 0.0;
// GRAFTING part one C: the Hive eye material's `Lock` (art/stylized/README.md). 0 = a low pinpoint,
// 1 = the whole ball lit. Per instance, so a grafted surgeon's eye can flare while the item in a vat
// stays dim. Grafts.gd drives it; everything else leaves it at 0.
instance uniform float lock = 0.0;
varying vec3 obj;

void vertex() { obj = VERTEX; }

void fragment() {
	vec3 d = normalize(obj);
	float a = acos(clamp(-d.z, -1.0, 1.0));            // angle away from the front (-Z)
	float pupil = smoothstep(pupil_r, pupil_r - 0.04, a);
	float ring = smoothstep(ring_r, ring_r - 0.07, a);
	float vein = 0.5 + 0.5 * sin(d.x * 40.0 + d.y * 25.0) * sin(d.y * 31.0 - d.x * 12.0);
	vec3 sclera = mix(sclera_col, sclera_col * vec3(0.9, 0.6, 0.6), vein * 0.25);
	vec3 col = mix(sclera, iris * (0.75 + 0.35 * vein), ring);
	col = mix(col, pupil_col, pupil);
	// Spoiled: milky grey-yellow cloud spreads over everything and dulls it.
	float r = smoothstep(0.0, 1.0, rot);
	vec3 cloud = vec3(0.62, 0.62, 0.55);
	col = mix(col, cloud, r * (0.55 + 0.4 * ring + 0.4 * pupil));
	ALBEDO = col;
	ROUGHNESS = mix(0.12, 0.8, r);
	SPECULAR = mix(0.9, 0.2, r);
	float lit = clamp(lock, 0.0, 1.0);
	EMISSION = iris * glow * (1.0 - r) * ring * (1.0 - pupil) + pupil_col * pupil_glow * pupil * (1.0 - r);
	EMISSION += iris * (1.0 - r) * lit * 2.4 + pupil_col * pupil * lit * 2.0;
}
"""

static var _shader: Shader = null
static var _mats := {}


static func is_eye(kind: String) -> bool:
	return KINDS.has(kind)


## The graft site a part kind belongs to ("eye", "throat"), or "".
static func site_of(kind: String) -> String:
	return String(SITE.get(kind, ""))


## How much of its value an eye keeps after `age_seconds` out of a vat.
static func spoil_factor(age_seconds: float) -> float:
	if age_seconds <= FRESH_SECONDS:
		return 1.0
	var k := clampf((age_seconds - FRESH_SECONDS) / (ROTTEN_SECONDS - FRESH_SECONDS), 0.0, 1.0)
	return lerpf(1.0, MIN_FACTOR, k)


static func is_spoiled_factor(f: float) -> bool:
	return f < SPOILED_BELOW


## "fresh", "spoiling" or "spoiled".
static func condition(f: float) -> String:
	if f >= 0.999:
		return "fresh"
	return "spoiling" if f >= SPOILED_BELOW else "spoiled"


## Rot 0..1 for the model.
static func rot_of(f: float) -> float:
	return clampf(1.0 - (f - MIN_FACTOR) / (1.0 - MIN_FACTOR), 0.0, 1.0)


## "Hive's eyeball", "Sonographer's trachea", "Zach's trachea". Parts are named "X's Y" everywhere.
static func label(kind: String, owner: String) -> String:
	var noun := String(NOUN.get(kind, "part"))
	var o := owner.strip_edges()
	if kind == "eye_hive":
		return "%s's %s" % [o if o != "" else "Hive", noun]
	if kind == "trachea_sonographer":
		return "%s's %s" % [o if o != "" else "Sonographer", noun]
	return "%s's %s" % [o if o != "" else "A surgeon", noun]


# ------------------------------------------------------------------ vat contents (a string)

## What a vat holds, as the string in a vat's `x`: "kind|owner|age|value" ("" = empty).
static func pack(kind: String, owner: String, age: float, value: int) -> String:
	return "%s|%s|%d|%d" % [kind, owner.replace("|", "/"), roundi(age), value]


static func unpack(x: String) -> Dictionary:
	if x == "":
		return {}
	var p := x.split("|")
	if p.size() < 4 or not is_eye(p[0]):
		return {}
	return {"kind": p[0], "owner": p[1], "age": float(p[2]), "value": int(p[3])}


# ------------------------------------------------------------------ the model

static func material(kind: String) -> ShaderMaterial:
	if _mats.has(kind):
		return _mats[kind]
	if _shader == null:
		_shader = Shader.new()
		_shader.code = SHADER
	var m := ShaderMaterial.new()
	m.resource_name = kind
	m.shader = _shader
	if kind == "eye_hive":
		# The Hive's eye as the model has it (art/stylized/README.md): a dark ball, a lit orange-red iris and a bright
		# pinpoint in the middle. The body's eye, the minigames' copy of it, the item and the vat all read this.
		m.set_shader_parameter("iris", Color(1.0, 0.32, 0.05))
		m.set_shader_parameter("ring_r", 0.5)
		m.set_shader_parameter("sclera_col", Color(0.07, 0.02, 0.02))
		m.set_shader_parameter("pupil_col", Color(1.0, 0.85, 0.45))
		m.set_shader_parameter("pupil_glow", 1.6)
		m.set_shader_parameter("pupil_r", 0.16)
		m.set_shader_parameter("glow", 1.2)
	else:
		m.set_shader_parameter("iris", Color(0.25, 0.42, 0.62))
	_mats[kind] = m
	return m


const RADIUS := 0.017

## A body part sitting on the ground, origin at its base.
static func build(root: Node3D, kind: String) -> void:
	if String(SITE.get(kind, "eye")) == "throat":
		build_trachea(root, kind)
	else:
		build_eye(root, kind)


## An eyeball with a stub of optic nerve behind it, sitting on the ground (origin at the base),
## looking up out of the table: the pupil faces -Z of the returned node.
static func build_eye(root: Node3D, kind: String) -> void:
	var ball := MeshInstance3D.new()
	ball.name = "EyeBall"
	var sph := SphereMesh.new()
	sph.radius = RADIUS
	sph.height = RADIUS * 2.0
	sph.radial_segments = 20
	sph.rings = 10
	ball.mesh = sph
	ball.material_override = material(kind)
	ball.position = Vector3(0, RADIUS, 0)
	root.add_child(ball)
	var nerve := MeshInstance3D.new()
	nerve.name = "Nerve"
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.004
	cyl.bottom_radius = 0.005
	cyl.height = 0.03
	cyl.radial_segments = 8
	cyl.rings = 1
	nerve.mesh = cyl
	var nm := StandardMaterial3D.new()
	nm.albedo_color = Color(0.85, 0.7, 0.62)
	nm.roughness = 0.5
	nerve.material_override = nm
	nerve.rotation_degrees = Vector3(90, 0, 0)
	nerve.position = Vector3(0, RADIUS, RADIUS + 0.012)
	root.add_child(nerve)
	# Rest with the pupil toward the viewer/the sky a little.
	ball.rotation_degrees = Vector3(-50, 0, 0)


## Set the rot of every body part under `node` (a world item, a hand's holder or a model).
static func set_rot(node: Node, r: float) -> void:
	_set_param(node, "rot", r)


## The lit value on every body part under `node`. On an eye: 0 a low pinpoint, 1 the whole ball lit.
## On a trachea: 0 the low violet it always has, 1 burning while Echo fires.
static func set_lock(node: Node, v: float) -> void:
	_set_param(node, "lock", clampf(v, 0.0, 1.0))


static func _set_param(node: Node, name: String, v: float) -> void:
	if node == null or not is_instance_valid(node):
		return
	for pat in ["EyeBall*", "Windpipe*"]:
		for mi in node.find_children(pat, "MeshInstance3D", true, false):
			(mi as MeshInstance3D).set_instance_shader_parameter(name, v)


static func footprint(kind := "eye_hive") -> Vector3:
	if String(SITE.get(kind, "eye")) == "throat":
		return Vector3(0.05, 0.05, 0.1)
	return Vector3(0.036, 0.036, 0.06)


# ------------------------------------------------------------------ the trachea (part two)
## GRAFTING part two (docs/GRAFTING_TRACHEA.md). A short length of windpipe: a soft tube with a
## stack of open cartilage rings down it, matching the Sonographer's throat (art/stylized/st_char.py
## `windpipe`) and the Echolocation icon. `trachea_sonographer` is violet and lit from inside;
## `trachea_surgeon` is pale pink cartilage and lights up for nobody.

const TRACHEA_SHADER := """
shader_type spatial;
render_mode cull_back;

uniform vec3 tint : source_color = vec3(0.61, 0.42, 1.0);
uniform vec3 ring_col : source_color = vec3(0.42, 0.25, 0.84);
uniform float glow = 0.0;              // what it gives off just lying there
uniform float lit_gain = 0.0;          // how much brighter `lock` can drive it
instance uniform float rot = 0.0;
// The counterpart of the eye's `Lock`: 0 the low glow a Sonographer's trachea always has, 1 burning
// while the surgeon wearing it fires Echo. Per instance, so a grafted throat can flare while one in
// a vat stays quiet. Grafts.gd drives it; everything else leaves it at 0.
instance uniform float lock = 0.0;
varying vec3 obj;

void vertex() { obj = VERTEX; }

void fragment() {
	float band = 0.5 + 0.5 * sin(obj.y * 210.0);
	vec3 col = mix(tint, ring_col, band * 0.45);
	// Spoiled: the cartilage goes grey and slack and the light in it dies.
	float r = smoothstep(0.0, 1.0, rot);
	col = mix(col, vec3(0.50, 0.47, 0.44), r * 0.75);
	ALBEDO = col;
	ROUGHNESS = mix(0.2, 0.82, r);
	SPECULAR = mix(0.7, 0.2, r);
	float e = glow + lit_gain * clamp(lock, 0.0, 1.0);
	EMISSION = tint * e * (1.0 - r);
}
"""

static var _t_shader: Shader = null

const TRACHEA_LEN := 0.092
const TRACHEA_R := 0.0125
const TRACHEA_RINGS := 6


static func trachea_material(kind: String) -> ShaderMaterial:
	if _mats.has(kind):
		return _mats[kind]
	if _t_shader == null:
		_t_shader = Shader.new()
		_t_shader.code = TRACHEA_SHADER
	var m := ShaderMaterial.new()
	m.resource_name = kind
	m.shader = _t_shader
	if kind == "trachea_sonographer":
		# #9b6bff, the ability icon's trachea and the Sonographer's own windpipe
		# (scripts/monsters/sonographer_rig.gd GLOW).
		m.set_shader_parameter("tint", Color(0.61, 0.42, 1.0))
		m.set_shader_parameter("ring_col", Color(0.42, 0.25, 0.84))
		# Bright enough to read on a surgeon's throat under a flashlight, which blows the skin round
		# it out to white.
		m.set_shader_parameter("glow", 1.7)
		m.set_shader_parameter("lit_gain", 6.0)
	else:
		# A surgeon's own: pale pink cartilage, and nothing behind it.
		m.set_shader_parameter("tint", Color(0.82, 0.66, 0.66))
		m.set_shader_parameter("ring_col", Color(0.64, 0.46, 0.48))
		m.set_shader_parameter("glow", 0.0)
		m.set_shader_parameter("lit_gain", 0.0)
	_mats[kind] = m
	return m


## A length of windpipe standing on its cut end, origin at the base, running up +Y.
static func build_trachea(root0: Node3D, kind: String) -> void:
	# It does not stand up straight: it lolls over, because it is a piece of meat.
	var root := Node3D.new()
	root.name = "Trachea"
	root.rotation_degrees = Vector3(-14, 0, 8)
	root0.add_child(root)
	var mat := trachea_material(kind)
	var tube := MeshInstance3D.new()
	tube.name = "Windpipe"
	var cyl := CylinderMesh.new()
	cyl.top_radius = TRACHEA_R * 0.86
	cyl.bottom_radius = TRACHEA_R
	cyl.height = TRACHEA_LEN
	cyl.radial_segments = 16
	cyl.rings = 1
	tube.mesh = cyl
	tube.material_override = mat
	tube.position = Vector3(0, TRACHEA_LEN * 0.5, 0)
	root.add_child(tube)
	for i in TRACHEA_RINGS:
		var t := (float(i) + 0.5) / float(TRACHEA_RINGS)
		var ring := MeshInstance3D.new()
		ring.name = "Windpipe_Ring%d" % i
		var tor := TorusMesh.new()
		var r: float = TRACHEA_R * lerpf(1.0, 0.86, t)
		tor.inner_radius = r * 0.88
		tor.outer_radius = r * 1.30
		tor.rings = 16
		tor.ring_segments = 7
		ring.mesh = tor
		ring.material_override = mat
		ring.position = Vector3(0, TRACHEA_LEN * t, 0)
		root.add_child(ring)
	# The cut ends read as cut: a dark wet disc at the top and the bottom.
	var cut := StandardMaterial3D.new()
	cut.albedo_color = Color(0.32, 0.12, 0.15)
	cut.roughness = 0.25
	for y in [0.001, TRACHEA_LEN - 0.001]:
		var cap := MeshInstance3D.new()
		cap.name = "WindpipeCut"
		var cc := CylinderMesh.new()
		cc.top_radius = TRACHEA_R * 0.8
		cc.bottom_radius = TRACHEA_R * 0.8
		cc.height = 0.002
		cc.radial_segments = 14
		cc.rings = 1
		cap.mesh = cc
		cap.material_override = cut
		cap.position = Vector3(0, float(y), 0)
		root.add_child(cap)


## What the surgery steps draw on the work plane for a trachea: `mi` (the mesh instance the step
## drives as its "eyeball") stops drawing a sphere and carries a length of windpipe, lying along the
## throat and shrunk to eyeball scale. Every rule and animation of the step still drives `mi`.
static func as_trachea(mi: MeshInstance3D, kind: String, radius: float) -> void:
	if mi == null or not is_instance_valid(mi) or mi.has_node("TracheaPart"):
		return
	mi.mesh = null
	mi.material_override = null
	for c in mi.get_children():
		c.queue_free()
	var holder := Node3D.new()
	holder.name = "TracheaPart"
	# Built standing on its base and about 90 mm long: lay it down and shrink it to eyeball scale.
	var k: float = radius / 0.0135 * 0.5
	holder.scale = Vector3.ONE * k
	holder.position = Vector3(0, 0, TRACHEA_LEN * k * 0.5)
	holder.basis = Basis(Vector3.RIGHT, deg_to_rad(-90.0))
	mi.add_child(holder)
	build_trachea(holder, kind)
