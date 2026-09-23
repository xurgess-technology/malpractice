extends RefCounted
## Primitive models for the sellable loot in loot_table.gd. Same rules as ItemModels: origin at
## the base, no collision, a stack of N shows N. Materials are cached and shared, so a hospital
## full of loot compiles a handful of materials, not one per item.
##
## ItemModels.make() calls build() for loot kinds (after checking Assets for `item/<kind>`).

static var _mats := {}


static func build(root: Node3D, kind: String, count: int) -> void:
	match kind:
		"eye_hive", "eye_surgeon": Eyes.build(root, kind)
		"reflex_hammer": _reflex_hammer(root)
		"epipen": _epipen(root)
		"pulse_oximeter": _pulse_oximeter(root)
		"pill_bottle": _pill_bottles(root, clampi(count, 1, 6))
		"xray_film": _xray_film(root)
		"desk_phone": _desk_phone(root)
		"laptop": _laptop(root)
		"gold_watch": _watch(root)
		"heart_monitor": _heart_monitor(root)
		"defibrillator": _defibrillator(root)
		"ultrasound": _ultrasound(root)
		"pool_chemical_drum": _pool_drum(root)
		"lifeguard_whistle": _whistle(root)
		"grease_bucket": _grease_bucket(root)
		"copper_wire_spool": _wire_spool(root)
		"foremans_clipboard": _clipboard(root)
		_: _add(root, _box(Vector3(0.15, 0.1, 0.15), _m("magenta", Color.MAGENTA)), Vector3(0, 0.05, 0))


## models sweep 2: what ItemModels merges into a kind's real model besides the model itself.
##   copies:   [[asset key, Transform3D]] more models next to the main one
##   parts:    [[Mesh, surface, Transform3D, Material]] small primitive details (the green trace on
##             the heart monitor's glass)
##   recolour: {material resource_name or "*": Color} albedo tint on the model's own materials
## Positions are in the model's fitted frame: base on the floor, footprint centred.
static func asset_extras(kind: String) -> Dictionary:
	match kind:
		"heart_monitor":
			var trace := _screen("ecg", Color(0.3, 1.0, 0.45))
			var parts := []
			var pts := [Vector2(-0.09, 0.0), Vector2(-0.04, 0.0), Vector2(-0.025, 0.035), Vector2(-0.01, -0.03), Vector2(0.005, 0.0), Vector2(0.07, 0.0)]
			for i in pts.size() - 1:
				var a: Vector2 = pts[i]
				var b: Vector2 = pts[i + 1]
				var seg := BoxMesh.new()
				seg.size = Vector3((b - a).length(), 0.004, 0.002)
				var xf := Transform3D(Basis(Vector3.BACK, (b - a).angle()), Vector3(HEART_SCREEN.x + (a.x + b.x) * 0.5, HEART_SCREEN.y + (a.y + b.y) * 0.5, HEART_SCREEN.z))
				parts.append([seg, 0, xf, trace])
			return {"parts": parts}
	return {}


## Where the heart monitor's trace sits on the television_02 model's glass (fitted frame).
const HEART_SCREEN := Vector3(-0.03, 0.22, 0.175)


## Rough footprint (x, height, z) so the pickup box and shelves can size themselves.
static func footprint(kind: String) -> Vector3:
	match kind:
		"eye_hive", "eye_surgeon": return Eyes.footprint()
		"epipen": return Vector3(0.16, 0.03, 0.03)
		"pulse_oximeter": return Vector3(0.07, 0.05, 0.05)
		"reflex_hammer": return Vector3(0.22, 0.04, 0.07)
		"pill_bottle": return Vector3(0.12, 0.08, 0.06)
		"xray_film": return Vector3(0.3, 0.02, 0.25)
		"desk_phone": return Vector3(0.2, 0.09, 0.2)
		"laptop": return Vector3(0.34, 0.24, 0.24)
		"gold_watch": return Vector3(0.08, 0.03, 0.1)
		"heart_monitor": return Vector3(0.38, 0.34, 0.2)
		"defibrillator": return Vector3(0.36, 0.2, 0.28)
		"ultrasound": return Vector3(0.42, 0.34, 0.32)
		"pool_chemical_drum": return Vector3(0.42, 0.62, 0.42)
		"lifeguard_whistle": return Vector3(0.1, 0.04, 0.05)
		"grease_bucket": return Vector3(0.28, 0.32, 0.28)
		"copper_wire_spool": return Vector3(0.44, 0.44, 0.44)
		"foremans_clipboard": return Vector3(0.24, 0.03, 0.33)
	return Vector3(0.15, 0.1, 0.15)


# ---------------------------------------------------------------------------
# materials and shapes

static func _m(key: String, col: Color, rough := 0.6, metal := 0.0, emit := Color.BLACK, energy := 0.0) -> StandardMaterial3D:
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.resource_name = "loot_" + key
	m.albedo_color = col
	m.roughness = rough
	m.metallic = metal
	if energy > 0.0:
		m.emission_enabled = true
		m.emission = emit
		m.emission_energy_multiplier = energy
	_mats[key] = m
	return m


static func _glass(key: String, col: Color) -> StandardMaterial3D:
	if _mats.has(key):
		return _mats[key]
	var m := _m(key, col, 0.1)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color.a = 0.5
	return m


static func _box(size: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.material_override = mat
	return mi


static func _cyl(r: float, h: float, mat: Material, sides := 12, r_top := -1.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = r if r_top < 0.0 else r_top
	c.bottom_radius = r
	c.height = h
	c.radial_segments = sides
	c.rings = 1
	mi.mesh = c
	mi.material_override = mat
	return mi


static func _torus(r_in: float, r_out: float, mat: Material, rings := 20, sides := 6) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var t := TorusMesh.new()
	t.inner_radius = r_in
	t.outer_radius = r_out
	t.rings = rings
	t.ring_segments = sides
	mi.mesh = t
	mi.material_override = mat
	return mi


static func _sphere(r: float, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = 12
	s.rings = 6
	mi.mesh = s
	mi.material_override = mat
	return mi


static func _add(root: Node3D, n: Node3D, pos: Vector3, rot_deg := Vector3.ZERO) -> Node3D:
	n.position = pos
	n.rotation_degrees = rot_deg
	root.add_child(n)
	return n


static func _steel() -> StandardMaterial3D:
	return _m("steel", Color(0.78, 0.8, 0.83), 0.3, 0.6)


static func _black_plastic() -> StandardMaterial3D:
	return _m("black_plastic", Color(0.08, 0.08, 0.09), 0.55)


static func _grey_plastic() -> StandardMaterial3D:
	return _m("grey_plastic", Color(0.72, 0.73, 0.72), 0.6)


static func _screen(key: String, col: Color) -> StandardMaterial3D:
	return _m("screen_" + key, Color(0.02, 0.03, 0.03), 0.3, 0.0, col, 1.6)


static func _gold() -> StandardMaterial3D:
	return _m("gold", Color(1.0, 0.76, 0.3), 0.22, 1.0)


# ---------------------------------------------------------------------------
# small loot

## A yellow auto-injector lying on its side: blue safety cap at -X, orange needle end at +X.
static func _epipen(root: Node3D) -> void:
	var body := _m("epi_yellow", Color(0.96, 0.82, 0.16), 0.4)
	var y := 0.016
	_add(root, _cyl(0.015, 0.11, body, 14), Vector3(0.005, y, 0), Vector3(0, 0, 90))
	_add(root, _cyl(0.0165, 0.045, _m("epi_cap", Color(0.2, 0.42, 0.85), 0.45), 14), Vector3(-0.0725, y, 0), Vector3(0, 0, 90))
	_add(root, _cyl(0.0155, 0.032, _m("epi_tip", Color(0.95, 0.42, 0.1), 0.45), 14, 0.011), Vector3(0.076, y, 0), Vector3(0, 0, -90))
	_add(root, _box(Vector3(0.05, 0.002, 0.014), _m("epi_label", Color(0.95, 0.95, 0.9), 0.7)), Vector3(0.0, y + 0.0148, 0))


static func _pulse_oximeter(root: Node3D) -> void:
	var body := _m("oxi_blue", Color(0.25, 0.42, 0.62), 0.5)
	_add(root, _box(Vector3(0.065, 0.022, 0.042), body), Vector3(0, 0.011, 0))
	_add(root, _box(Vector3(0.06, 0.018, 0.04), _grey_plastic()), Vector3(0, 0.031, 0), Vector3(0, 0, -6))
	_add(root, _box(Vector3(0.03, 0.002, 0.018), _screen("red", Color(1.0, 0.25, 0.2))), Vector3(0.004, 0.041, 0), Vector3(0, 0, -6))


static func _reflex_hammer(root: Node3D) -> void:
	_add(root, _cyl(0.005, 0.18, _steel(), 8), Vector3(-0.02, 0.012, 0), Vector3(0, 0, 90))
	var head := MeshInstance3D.new()
	var prism := PrismMesh.new()
	prism.size = Vector3(0.05, 0.06, 0.022)
	head.mesh = prism
	head.material_override = _m("rubber_orange", Color(0.9, 0.35, 0.12), 0.7)
	_add(root, head, Vector3(0.08, 0.012, 0), Vector3(90, 0, 0))


static func _pill_bottles(root: Node3D, n: int) -> void:
	var amber := _glass("amber", Color(0.95, 0.5, 0.12))
	var cap := _m("white_plastic", Color(0.93, 0.93, 0.9), 0.45)
	var label := _m("label_paper", Color(0.96, 0.95, 0.9), 0.9)
	var pills := _m("pills", Color(0.95, 0.92, 0.85), 0.8)
	for i in n:
		var b := Node3D.new()
		_add(b, _cyl(0.021, 0.07, amber, 12), Vector3(0, 0.035, 0))
		_add(b, _cyl(0.017, 0.04, pills, 8), Vector3(0, 0.022, 0))
		_add(b, _cyl(0.0215, 0.03, label, 12), Vector3(0, 0.036, 0))
		_add(b, _cyl(0.023, 0.014, cap, 12), Vector3(0, 0.077, 0))
		var x := (i % 3 - 1) * 0.05
		var z := 0.0 if i < 3 else 0.048
		_add(root, b, Vector3(x, 0, z), Vector3(0, i * 41.0, 0))


static func _xray_film(root: Node3D) -> void:
	# models sweep 2: a real chest radiograph (CC0, `mat/xray_film`) on the film when it exists.
	var real := _xray_material()
	if real != null:
		_add(root, _box(Vector3(0.24, 0.002, 0.275), _m("xray_sleeve", Color(0.05, 0.07, 0.09), 0.3)), Vector3(0, 0.001, 0))
		var mi := MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = Vector2(0.224, 0.256)
		mi.mesh = pm
		mi.material_override = real
		_add(root, mi, Vector3(0, 0.0025, 0))
		return
	var film := _m("xray_film", Color(0.08, 0.12, 0.18), 0.25, 0.0, Color(0.15, 0.25, 0.35), 0.3)
	var bone := _m("xray_bone", Color(0.5, 0.6, 0.66), 0.3, 0.0, Color(0.45, 0.6, 0.7), 0.7)
	_add(root, _box(Vector3(0.28, 0.003, 0.23), film), Vector3(0, 0.0015, 0))
	# A rib cage: a spine and a few curved-looking ribs as thin bars.
	_add(root, _box(Vector3(0.018, 0.001, 0.19), bone), Vector3(0, 0.0035, 0))
	for i in 5:
		for s in [-1.0, 1.0]:
			_add(root, _box(Vector3(0.09, 0.001, 0.008), bone), Vector3(s * 0.05, 0.0035, -0.07 + i * 0.035), Vector3(0, s * (14.0 + i * 3.0), 0))


## The radiograph as a faintly backlit film, or null when the texture is missing.
static func _xray_material() -> StandardMaterial3D:
	if _mats.has("xray_real"):
		return _mats["xray_real"]
	var loop := Engine.get_main_loop()
	var assets = (loop as SceneTree).root.get_node_or_null("Assets") if loop is SceneTree else null
	var m: StandardMaterial3D = null
	if assets != null and assets.has("mat/xray_film"):
		var src = assets.material("mat/xray_film")
		if src is StandardMaterial3D:
			m = StandardMaterial3D.new()
			m.resource_name = "loot_xray_real"
			m.albedo_texture = src.albedo_texture
			m.albedo_color = Color(0.72, 0.82, 0.9)
			m.roughness = 0.25
			m.emission_enabled = true
			m.emission_texture = src.albedo_texture
			m.emission = Color(0.45, 0.6, 0.75)
			m.emission_energy_multiplier = 0.35
	_mats["xray_real"] = m
	return m


static func _desk_phone(root: Node3D) -> void:
	var body := _m("phone_grey", Color(0.18, 0.19, 0.2), 0.5)
	_add(root, _box(Vector3(0.18, 0.05, 0.2), body), Vector3(0, 0.025, 0), Vector3(-8, 0, 0))
	_add(root, _box(Vector3(0.05, 0.028, 0.19), _black_plastic()), Vector3(-0.055, 0.064, 0), Vector3(-8, 0, 0))
	for s in [-1.0, 1.0]:
		_add(root, _box(Vector3(0.056, 0.022, 0.045), _black_plastic()), Vector3(-0.055, 0.075, s * 0.075), Vector3(-8, 0, 0))
	_add(root, _box(Vector3(0.07, 0.004, 0.1), _m("keypad", Color(0.75, 0.76, 0.74), 0.5)), Vector3(0.04, 0.056, 0.01), Vector3(-8, 0, 0))
	_add(root, _box(Vector3(0.05, 0.003, 0.025), _screen("amber", Color(1.0, 0.65, 0.2))), Vector3(0.04, 0.056, -0.065), Vector3(-8, 0, 0))


static func _laptop(root: Node3D) -> void:
	var shell := _m("laptop_shell", Color(0.24, 0.25, 0.27), 0.35, 0.5)
	_add(root, _box(Vector3(0.33, 0.018, 0.23), shell), Vector3(0, 0.009, 0))
	_add(root, _box(Vector3(0.29, 0.002, 0.1), _black_plastic()), Vector3(0, 0.019, 0.02))
	var lid := Node3D.new()
	_add(root, lid, Vector3(0, 0.018, -0.114), Vector3(-105, 0, 0))
	_add(lid, _box(Vector3(0.33, 0.012, 0.23), shell), Vector3(0, -0.006, 0.115))
	_add(lid, _box(Vector3(0.29, 0.002, 0.19), _screen("laptop", Color(0.25, 0.45, 0.8))), Vector3(0, 0.001, 0.115))


static func _watch(root: Node3D) -> void:
	var strap := _m("leather", Color(0.28, 0.16, 0.08), 0.8)
	_add(root, _box(Vector3(0.022, 0.004, 0.1), strap), Vector3(0, 0.002, 0))
	_add(root, _cyl(0.02, 0.01, _gold(), 18), Vector3(0, 0.008, 0))
	_add(root, _cyl(0.016, 0.002, _m("watch_face", Color(0.95, 0.93, 0.85), 0.3), 18), Vector3(0, 0.0135, 0))
	_add(root, _box(Vector3(0.002, 0.001, 0.012), _black_plastic()), Vector3(0, 0.015, -0.004))


# ---------------------------------------------------------------------------
# bulky loot

static func _heart_monitor(root: Node3D) -> void:
	var shell := _m("monitor_shell", Color(0.78, 0.79, 0.77), 0.5)
	_add(root, _box(Vector3(0.36, 0.26, 0.17), shell), Vector3(0, 0.13, 0))
	_add(root, _box(Vector3(0.28, 0.18, 0.004), _screen("ecg_bg", Color(0.02, 0.1, 0.08))), Vector3(-0.02, 0.14, 0.086))
	# The trace: a few bright segments making a heartbeat.
	var trace := _screen("ecg", Color(0.3, 1.0, 0.45))
	var pts := [Vector2(-0.15, 0.0), Vector2(-0.07, 0.0), Vector2(-0.05, 0.05), Vector2(-0.03, -0.04), Vector2(-0.01, 0.0), Vector2(0.11, 0.0)]
	for i in pts.size() - 1:
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[i + 1]
		var seg := _box(Vector3((b - a).length(), 0.005, 0.002), trace)
		_add(root, seg, Vector3((a.x + b.x) * 0.5 - 0.02, 0.15 + (a.y + b.y) * 0.5, 0.089), Vector3(0, 0, rad_to_deg((b - a).angle())))
	for i in 3:
		_add(root, _cyl(0.01, 0.01, _m("knob", Color(0.3, 0.3, 0.32), 0.5), 10), Vector3(0.15, 0.08 + i * 0.05, 0.088), Vector3(90, 0, 0))
	_add(root, _box(Vector3(0.2, 0.02, 0.03), _black_plastic()), Vector3(0, 0.29, 0))
	for s in [-1.0, 1.0]:
		_add(root, _box(Vector3(0.02, 0.03, 0.03), _black_plastic()), Vector3(s * 0.09, 0.27, 0))


static func _defibrillator(root: Node3D) -> void:
	var case_mat := _m("aed_case", Color(0.95, 0.72, 0.08), 0.5)
	var dark := _m("aed_dark", Color(0.12, 0.12, 0.14), 0.6)
	_add(root, _box(Vector3(0.34, 0.14, 0.26), case_mat), Vector3(0, 0.07, 0))
	_add(root, _box(Vector3(0.3, 0.012, 0.22), dark), Vector3(0, 0.146, 0))
	_add(root, _box(Vector3(0.18, 0.03, 0.03), dark), Vector3(0, 0.18, 0))
	for s in [-1.0, 1.0]:
		_add(root, _box(Vector3(0.025, 0.04, 0.03), dark), Vector3(s * 0.08, 0.16, 0))
	# A red heart with a lightning bolt, as blocks, on the lid.
	var red := _m("aed_red", Color(0.8, 0.08, 0.06), 0.5)
	_add(root, _box(Vector3(0.06, 0.004, 0.06), red), Vector3(-0.07, 0.154, 0.02), Vector3(0, 45, 0))
	_add(root, _sphere(0.022, red), Vector3(-0.089, 0.152, -0.002)).scale = Vector3(1, 0.15, 1)
	_add(root, _sphere(0.022, red), Vector3(-0.051, 0.152, -0.002)).scale = Vector3(1, 0.15, 1)
	_add(root, _box(Vector3(0.012, 0.005, 0.05), _m("aed_bolt", Color(1, 1, 1), 0.4)), Vector3(-0.07, 0.157, 0.01), Vector3(0, 25, 0))
	_add(root, _cyl(0.018, 0.006, _m("aed_button", Color(0.2, 0.7, 0.3), 0.4, 0.0, Color(0.2, 0.9, 0.3), 1.0), 12), Vector3(0.07, 0.154, 0.03))


static func _ultrasound(root: Node3D) -> void:
	var shell := _m("us_shell", Color(0.85, 0.86, 0.88), 0.45)
	_add(root, _box(Vector3(0.4, 0.07, 0.3), shell), Vector3(0, 0.035, 0))
	_add(root, _box(Vector3(0.3, 0.004, 0.14), _m("us_keys", Color(0.3, 0.32, 0.36), 0.5)), Vector3(0, 0.072, 0.06))
	_add(root, _cyl(0.02, 0.006, _m("us_ball", Color(0.25, 0.45, 0.8), 0.3), 12), Vector3(0.12, 0.076, 0.07))
	var lid := Node3D.new()
	_add(root, lid, Vector3(0, 0.07, -0.13), Vector3(-72, 0, 0))
	_add(lid, _box(Vector3(0.38, 0.02, 0.26), shell), Vector3(0, -0.01, 0.13))
	_add(lid, _box(Vector3(0.32, 0.002, 0.2), _screen("us", Color(0.55, 0.62, 0.66))), Vector3(0, 0.001, 0.13))
	_add(root, _cyl(0.014, 0.08, dark_probe(), 10, 0.02), Vector3(-0.15, 0.09, 0.1), Vector3(0, 0, 70))


static func dark_probe() -> StandardMaterial3D:
	return _m("us_probe", Color(0.2, 0.21, 0.23), 0.5)


# POCKETS 2 phase 2: the Natatorium's two loot kinds.

## A sealed drum of pool chemicals: blue plastic, white lid, two rolling ribs and a hazard label.
## Bulky, so it takes both hands and never goes in a container.
static func _pool_drum(root: Node3D) -> void:
	var blue := _m("drum_blue", Color(0.11, 0.30, 0.60), 0.5)
	var lid := _m("drum_lid", Color(0.84, 0.85, 0.83), 0.45, 0.15)
	_add(root, _cyl(0.2, 0.56, blue, 16), Vector3(0, 0.28, 0))
	for y in [0.16, 0.42]:
		_add(root, _cyl(0.212, 0.035, lid, 16), Vector3(0, y, 0))
	_add(root, _cyl(0.205, 0.03, lid, 16), Vector3(0, 0.573, 0))
	_add(root, _cyl(0.05, 0.02, _m("drum_cap", Color(0.72, 0.16, 0.10), 0.4), 10), Vector3(0.1, 0.594, 0))
	# The hazard diamond on the side.
	var label := _m("drum_label", Color(0.93, 0.90, 0.80), 0.8)
	_add(root, _box(Vector3(0.16, 0.16, 0.004), label), Vector3(0, 0.30, 0.201), Vector3(0, 0, 45))
	_add(root, _box(Vector3(0.1, 0.1, 0.004), _m("drum_hazard", Color(0.88, 0.62, 0.06), 0.7)), Vector3(0, 0.30, 0.204), Vector3(0, 0, 45))


## A lifeguard's whistle on its lanyard: a chrome barrel with the pea chamber and a mouthpiece,
## and a loop of red cord it hangs from.
static func _whistle(root: Node3D) -> void:
	var chrome := _m("whistle_chrome", Color(0.80, 0.82, 0.85), 0.2, 0.95)
	var cord := _m("whistle_cord", Color(0.72, 0.10, 0.10), 0.9)
	_add(root, _cyl(0.017, 0.045, chrome, 12), Vector3(0.0, 0.017, 0), Vector3(0, 0, 90))
	_add(root, _box(Vector3(0.038, 0.014, 0.016), chrome), Vector3(-0.038, 0.014, 0))
	_add(root, _cyl(0.007, 0.012, chrome, 8), Vector3(0.0, 0.033, 0))
	_add(root, _cyl(0.004, 0.012, chrome, 8), Vector3(0.026, 0.02, 0), Vector3(0, 0, 90))
	# The lanyard, coiled beside it.
	for i in 3:
		_add(root, _cyl(0.018, 0.004, cord, 10, 0.018), Vector3(0.036 + i * 0.002, 0.004 + i * 0.004, 0.0))


# --- POCKETS 2 phase 5: the Factory's three ----------------------------------------------------

## A pail of machine grease with the lid levered off and leaning against it: a tapered tin bucket,
## a wire handle over the top, and a dull yellow-grey surface that has been dug out of.
static func _grease_bucket(root: Node3D) -> void:
	var tin := _m("grease_tin", Color(0.38, 0.36, 0.33), 0.55, 0.65)
	var grease := _m("grease_goo", Color(0.68, 0.63, 0.44), 0.85)
	var wire := _m("grease_wire", Color(0.28, 0.27, 0.26), 0.45, 0.8)
	# The pail: narrower at the base, the way a pail is.
	_add(root, _cyl(0.115, 0.28, tin, 16, 0.14), Vector3(0, 0.14, 0))
	_add(root, _cyl(0.145, 0.018, tin, 16), Vector3(0, 0.281, 0))        # the rolled rim
	# What is left in it, sitting a little below the rim and dug out on one side.
	_add(root, _cyl(0.132, 0.03, grease, 16), Vector3(0, 0.252, 0))
	_add(root, _cyl(0.055, 0.022, grease, 12, 0.03), Vector3(0.04, 0.267, -0.03))
	# The handle, standing up off one side.
	_add(root, _cyl(0.006, 0.2, wire, 6), Vector3(-0.128, 0.36, 0), Vector3(0, 0, 18))
	_add(root, _cyl(0.006, 0.2, wire, 6), Vector3(0.128, 0.36, 0), Vector3(0, 0, -18))
	_add(root, _cyl(0.006, 0.23, wire, 6), Vector3(0, 0.452, 0), Vector3(0, 0, 90))
	# The lid, prised off and leaning on the pail.
	_add(root, _cyl(0.142, 0.012, tin, 16), Vector3(0.17, 0.11, 0.05), Vector3(0, 0, 72))


## A wooden cable drum of heavy copper wire: two flanges, and the coil filling the barrel between
## them. Bulky, and it reads as bulky -- it is the widest thing in the Factory you can pick up.
static func _wire_spool(root: Node3D) -> void:
	var wood := _m("spool_wood", Color(0.44, 0.33, 0.21), 0.85)
	var copper := _m("spool_copper", Color(0.72, 0.38, 0.16), 0.3, 0.9)
	var band := _m("spool_band", Color(0.30, 0.29, 0.28), 0.5, 0.7)
	# It lies on its side, so the flanges are vertical discs and the coil is a fat ring.
	for x in [-0.155, 0.155]:
		_add(root, _cyl(0.21, 0.022, wood, 18), Vector3(x, 0.21, 0), Vector3(0, 0, 90))
		_add(root, _cyl(0.05, 0.026, band, 12), Vector3(x, 0.21, 0), Vector3(0, 0, 90))   # the hub plate
	# The copper itself, in three visible laps so it reads as wound rather than solid.
	for i in 3:
		_add(root, _cyl(0.163 - i * 0.004, 0.27, copper, 18), Vector3(0, 0.21, 0), Vector3(0, 0, 90))
	# The loose tail, tucked back against a flange so it cannot stick out of the pickup box.
	_add(root, _cyl(0.008, 0.12, copper, 6), Vector3(0.138, 0.075, 0.135), Vector3(22, 0, 10))
	# The through-axle, poking out either end.
	_add(root, _cyl(0.016, 0.38, band, 8), Vector3(0, 0.21, 0), Vector3(0, 0, 90))


## A foreman's clipboard: a masonite board, the spring clip across the top, and a shift schedule
## under it with its rows struck through. The crossings-out are the point, so they are real geometry
## rather than a texture -- this is X-ray-film tier loot you are meant to stop and read.
static func _clipboard(root: Node3D) -> void:
	var board := _m("clip_board", Color(0.46, 0.35, 0.24), 0.9)
	var paper := _m("clip_paper", Color(0.88, 0.86, 0.79), 0.95)
	var clip := _m("clip_metal", Color(0.72, 0.73, 0.75), 0.35, 0.85)
	var ink := _m("clip_ink", Color(0.12, 0.12, 0.14), 0.9)
	_add(root, _box(Vector3(0.23, 0.012, 0.32), board), Vector3(0, 0.006, 0))
	_add(root, _box(Vector3(0.2, 0.004, 0.27), paper), Vector3(0, 0.014, 0.012))
	# The spring clip across the head of the board.
	_add(root, _box(Vector3(0.1, 0.016, 0.045), clip), Vector3(0, 0.02, -0.132))
	_add(root, _cyl(0.008, 0.088, clip, 8), Vector3(0, 0.026, -0.113), Vector3(0, 0, 90))
	# The schedule: ruled rows, and a line drawn through most of the names. No dates anywhere.
	for i in 7:
		var z := -0.1 + i * 0.031
		_add(root, _box(Vector3(0.15, 0.002, 0.0035), ink), Vector3(-0.012, 0.017, z))
		if i != 2 and i != 5:
			_add(root, _box(Vector3(0.158, 0.002, 0.0045), ink), Vector3(-0.012, 0.019, z), Vector3(0, 0, 0))
