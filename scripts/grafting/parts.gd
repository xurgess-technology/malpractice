class_name Parts
extends RefCounted
## THE BODY PARTS you can hold, keep in a vat and graft (docs/GRAFTING.md, docs/GRAFTING_TRACHEA.md).
## Grafting part one called this `Eyes`; part two renamed it, because the spoil system the brains
## used is gone and this is what body parts use now.
##
## Four kinds, in two FAMILIES:
##   eye      `eye_hive` (out of a strapped Hive) and `eye_surgeon` (a surgeon's own)
##   trachea  `trachea_sono` (out of a strapped Sonographer) and `trachea_surgeon`
## All of them are sellable loot (loot_table.gd) that SPOIL outside a vat: over about a minute or two
## a part clouds over and dulls, and a spoiled part can't be grafted. A vat stops the clock (vats.gd).
##
## A part's owner rides in the stack's/item's `x` string ("Hive", "Sonographer", "Zach"); the spoil
## clock is `bt`, the world time it came out.
##
## Body parts are named "X's Y" everywhere (2026-09-18): "Hive's eyeball", "Sonographer's trachea",
## "Zach's trachea". Everything here and in vats.gd works on a *part kind*, not on eyes as such: a vat
## holds ONE part of any kind, and a graft (grafts.gd) only swaps parts of the same family, so an
## eyeball vat is refused for a trachea graft.

const KINDS := ["eye_hive", "eye_surgeon", "trachea_sono", "trachea_surgeon"]
## Part kind -> the noun in "X's <noun>". The owner comes from `x` (or OWNER).
const NOUN := {"eye_hive": "eyeball", "eye_surgeon": "eyeball",
	"trachea_sono": "trachea", "trachea_surgeon": "trachea"}
## Part kind -> its family. A vat holding one family is refused for a graft of the other.
const FAMILY := {"eye_hive": "eye", "eye_surgeon": "eye",
	"trachea_sono": "trachea", "trachea_surgeon": "trachea"}
## Family -> the monster's part, and the surgeon's own part of the same family.
const MONSTER_PART := {"eye": "eye_hive", "trachea": "trachea_sono"}
const SURGEON_PART := {"eye": "eye_surgeon", "trachea": "trachea_surgeon"}
## Family -> the body site the surgery happens at (Procedures step `site`).
const SITE := {"eye": "eye", "trachea": "throat"}
## A monster part's owner when nothing else says: "Hive's eyeball", "Sonographer's trachea".
const OWNER := {"eye_hive": "Hive", "trachea_sono": "Sonographer"}

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

## The trachea: a ribbed windpipe. The Sonographer's burns violet behind its rings (the Echolocation
## icon, art/icons/echolocation.svg); a surgeon's own is pale pink cartilage and does not glow.
## PLACEHOLDER: Godot primitives, the way part one's eyeball is. The `trachea-art` chunk replaces
## both with real GLBs; keep the node names (`TracheaTube`) and this material so it swaps cleanly.
const TRACHEA_SHADER := """
shader_type spatial;
render_mode cull_back;

uniform vec3 flesh : source_color = vec3(0.86, 0.66, 0.66);
uniform vec3 glow : source_color = vec3(0.61, 0.42, 1.0);
uniform float lit_base = 0.0;   // 1 for the Sonographer's, 0 for a surgeon's own
uniform float rings = 46.0;
instance uniform float rot = 0.0;
instance uniform float lock = 0.0;
varying vec3 obj;

void vertex() { obj = VERTEX; }

void fragment() {
	float band = 0.5 + 0.5 * sin(obj.y * rings);
	float ring = smoothstep(0.35, 0.75, band);
	vec3 col = mix(flesh * 0.72, flesh, ring);
	// Spoiled: the same milky grey-yellow cloud the eyeball gets.
	float r = smoothstep(0.0, 1.0, rot);
	col = mix(col, vec3(0.62, 0.62, 0.55), r * 0.75);
	ALBEDO = col;
	ROUGHNESS = mix(0.2, 0.85, r);
	SPECULAR = mix(0.85, 0.2, r);
	float lit = lit_base * (1.0 - r) * (0.35 + 2.6 * clamp(lock, 0.0, 1.0));
	EMISSION = glow * ring * lit;
}
"""

static var _shader: Shader = null
static var _trachea_shader: Shader = null
static var _mats := {}


static func is_part(kind: String) -> bool:
	return KINDS.has(kind)


## "eye" or "trachea" ("" for anything that is not a body part).
static func family(kind: String) -> String:
	return String(FAMILY.get(kind, ""))


## Is this the part a monster gives up (as opposed to a surgeon's own)?
static func is_monster_part(kind: String) -> bool:
	return OWNER.has(kind)


## The part of `kind`'s family that a surgeon carries in their own body.
static func surgeon_part(kind: String) -> String:
	return String(SURGEON_PART.get(family(kind), ""))


## The body site a graft or an extraction of this family works at ("eye" / "throat").
static func site_of(kind: String) -> String:
	return String(SITE.get(family(kind), "eye"))


## How much of its value a part keeps after `age_seconds` out of a vat.
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


## "Hive's eyeball", "Sonographer's trachea", "Zach's trachea". Body parts are named "X's Y".
static func label(kind: String, owner: String) -> String:
	var noun := String(NOUN.get(kind, "part"))
	var o := owner.strip_edges()
	if o != "":
		return "%s's %s" % [o, noun]
	return "%s's %s" % [String(OWNER.get(kind, "A surgeon")), noun]


# ------------------------------------------------------------------ vat contents (a string)

## What a vat holds, as the string in a vat's `x`: "kind|owner|age|value" ("" = empty).
static func pack(kind: String, owner: String, age: float, value: int) -> String:
	return "%s|%s|%d|%d" % [kind, owner.replace("|", "/"), roundi(age), value]


static func unpack(x: String) -> Dictionary:
	if x == "":
		return {}
	var p := x.split("|")
	if p.size() < 4 or not is_part(p[0]):
		return {}
	return {"kind": p[0], "owner": p[1], "age": float(p[2]), "value": int(p[3])}


# ------------------------------------------------------------------ the model

static func material(kind: String) -> ShaderMaterial:
	if _mats.has(kind):
		return _mats[kind]
	if family(kind) == "trachea":
		if _trachea_shader == null:
			_trachea_shader = Shader.new()
			_trachea_shader.code = TRACHEA_SHADER
		var tm := ShaderMaterial.new()
		tm.resource_name = kind
		tm.shader = _trachea_shader
		if kind == "trachea_sono":
			tm.set_shader_parameter("flesh", Color(0.44, 0.36, 0.5))
			tm.set_shader_parameter("lit_base", 1.0)
		else:
			tm.set_shader_parameter("flesh", Color(0.88, 0.7, 0.72))
			tm.set_shader_parameter("lit_base", 0.0)
		_mats[kind] = tm
		return tm
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

## An eyeball with a stub of optic nerve behind it, sitting on the ground (origin at the base),
## looking up out of the table: the pupil faces -Z of the returned node.
static func build(root: Node3D, kind: String) -> void:
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


## Set the rot of every eyeball under `node` (a world item, a hand's holder or a model).
static func set_rot(node: Node, r: float) -> void:
	if node == null or not is_instance_valid(node):
		return
	for mi in node.find_children("EyeBall*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).set_instance_shader_parameter("rot", r)


## The Hive eye material's `Lock` on every eyeball under `node`: 0 a low pinpoint, 1 the whole ball lit.
static func set_lock(node: Node, v: float) -> void:
	if node == null or not is_instance_valid(node):
		return
	for mi in node.find_children("EyeBall*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).set_instance_shader_parameter("lock", clampf(v, 0.0, 1.0))


static func footprint() -> Vector3:
	return Vector3(0.036, 0.036, 0.06)
