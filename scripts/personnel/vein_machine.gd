extends Node3D
## SKILL TREE: Personnel's palm vein machine, working. The machine itself is set dressing
## (piece_factory.gd `_vein_machine`, placed by entrance.gd); this node overlays the parts that do
## something, built by HospitalBuilder from `spots.personnel` (scanner = the hand plate, screen =
## the big screen's glass):
##
##   - the picture on the big screen (a SubViewport drawing scripts/skills/vein_screen.gd, on an
##     unshaded quad just in front of the glass), on every machine, so the whole room sees it;
##   - a glow on the hand plate that breathes while idle and flares while it reads a palm;
##   - the thing you aim at (the plate and the screen) and press E on;
##   - this machine's own session: E at the plate claims the reader (Net.claim_station("veins"),
##     host-authoritative, so two surgeons can't both be at it; the second gets "!Someone's palm is
##     on the reader."), stands you at the plate facing the screen, and a camera glides from your
##     eyes back to where the whole screen fits. Your mouse is free: hover and click the vein nodes,
##     INFUSE (or Enter) spends points. Esc, E or a movement key steps away.
##
## What the screen shows comes only from replicated state: who is at it (Net.station_users) and
## their skills (Net.skills, published by scripts/skills/skills.gd), so an onlooker sees the same
## scan, the same veins growing and the same node picked, from where they stand.

const ScreenScript := preload("res://scripts/skills/vein_screen.gd")
const LightRooms := preload("res://scripts/level/light_rooms.gd")

const STATION := "veins"
const AIM_ID := "vein_scanner"
const TEX := Vector2i(1600, 850)
## How far in front of the glass the picture floats (the glass box is 1 cm thick).
const GLASS_OUT := 0.012
## Where you stand, out from the plate, and the camera's glide from your eyes to the screen.
const STAND_OUT := 0.5
const GLIDE_SECONDS := 1.1
const CAM_FOV := 50.0
## Margin round the screen in the fitted view (1.0 = edge to edge).
const FIT_MARGIN := 1.07
## The screen renders only while a camera is this close.
const RENDER_RANGE := 18.0

var viewport: SubViewport
var screen: Control
var quad: MeshInstance3D
var aim: Area3D

var _centre := Vector3.ZERO     # the glass's centre
var _out := Vector3.BACK        # out of the glass, into the room (horizontal)
var _size := Vector2(3.2, 1.7)
var _plate := Vector3.ZERO
var _plate_mesh: MeshInstance3D
var _plate_mat: StandardMaterial3D
var _light: OmniLight3D
var _user := 0
var _grow_sound_done := false

# ---- this machine's session ----
var game: Node = null
var _open := false
var _pending: Node = null
var _player: Node = null
var _cam: Camera3D
var _glide := 0.0
var _cam_from := Transform3D()
var _hint: CanvasLayer
var _hint_label: Label


class Aim extends Area3D:
	func interact_prompt(q) -> String:
		if q == null or not q.alive or q.downed:
			return ""
		var u := Net.station_user("veins")
		if u != 0 and u != q.peer_id:
			return "!Someone's palm is on the reader."
		return "E: put your palm on the reader"

	func interact_hold() -> float:
		return 0.0

	func interact(_q) -> void:
		pass   # opening is local (VeinMachine._poll_open); the host has nothing to do


## `spots` is spots.personnel (entrance.gd): scanner and screen, grid coordinates. `to_world` turns
## (grid pos, height) into world space; `grid` is the level's LightRooms grid, for the glow's mask.
func setup(spots: Dictionary, to_world: Callable, grid: Dictionary) -> void:
	name = "VeinMachine"
	set_meta("light_dynamic", true)   # light_rooms.gd: its layers are set here
	var sc: Dictionary = spots.scanner
	var sr: Dictionary = spots.screen
	_centre = to_world.call(sr.pos, float(sr.height))
	_size = sr.size
	_plate = to_world.call(sc.pos, 1.012)
	var flat := _plate - _centre
	flat.y = 0.0
	_out = flat.normalized() if flat.length() > 0.01 else Vector3.BACK
	_build(grid)


func _build(grid: Dictionary) -> void:
	viewport = SubViewport.new()
	viewport.name = "Viewport"
	viewport.size = TEX
	viewport.disable_3d = true
	viewport.transparent_bg = false
	viewport.gui_disable_input = true
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(viewport)
	screen = ScreenScript.new()
	screen.name = "VeinScreen"
	viewport.add_child(screen)

	# The picture: +Z of the quad out into the room.
	quad = MeshInstance3D.new()
	quad.name = "Picture"
	var qm := QuadMesh.new()
	qm.size = _size
	quad.mesh = qm
	quad.material_override = make_material(viewport.get_texture())
	quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	quad.transform = Transform3D(Basis.looking_at(-_out, Vector3.UP), _centre + _out * GLASS_OUT)
	add_child(quad)

	# The plate's glow, lying on the tilted plate (piece_factory.gd: tipped 0.4 rad toward you).
	_plate_mat = StandardMaterial3D.new()
	_plate_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_plate_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_plate_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_plate_mat.albedo_color = Color(0.3, 0.8, 1.0, 0.25)
	_plate_mesh = MeshInstance3D.new()
	_plate_mesh.name = "PlateGlow"
	var pm := BoxMesh.new()
	pm.size = Vector3(0.46, 0.003, 0.32)
	_plate_mesh.mesh = pm
	_plate_mesh.material_override = _plate_mat
	_plate_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pb := Basis.looking_at(-_out, Vector3.UP) * Basis(Vector3.RIGHT, 0.4)
	_plate_mesh.transform = Transform3D(pb, _plate + pb.y * 0.006)
	add_child(_plate_mesh)

	_light = OmniLight3D.new()
	_light.name = "Glow"
	_light.light_color = Color(0.45, 0.8, 1.0)
	_light.light_energy = 0.0
	_light.omni_range = 4.5
	_light.omni_attenuation = 1.6
	_light.shadow_enabled = false
	_light.light_specular = 0.1
	var lp := _centre + _out * 0.9
	_light.position = lp
	if not grid.is_empty():
		_light.light_cull_mask = LightRooms.light_mask(grid, lp) | LightRooms.DYNAMIC
	add_child(_light)

	# What you aim at: the plate (and its pedestal's top) and the screen.
	aim = Aim.new()
	aim.name = "VeinAim"
	aim.collision_layer = C.L_INTERACT
	aim.collision_mask = 0
	aim.monitoring = false
	aim.add_to_group("interactable")
	aim.set_meta("interact_id", AIM_ID)
	add_child(aim)
	var basis := Basis.looking_at(-_out, Vector3.UP)
	var plate_cs := CollisionShape3D.new()
	var pbox := BoxShape3D.new()
	pbox.size = Vector3(0.75, 0.35, 0.6)
	plate_cs.shape = pbox
	plate_cs.transform = Transform3D(basis, _plate + Vector3(0, -0.05, 0))
	aim.add_child(plate_cs)
	var scr_cs := CollisionShape3D.new()
	var sbox := BoxShape3D.new()
	sbox.size = Vector3(_size.x, _size.y, 0.08)
	scr_cs.shape = sbox
	scr_cs.transform = Transform3D(basis, _centre + _out * 0.04)
	aim.add_child(scr_cs)

	_cam = Camera3D.new()
	_cam.name = "VeinCamera"
	_cam.near = 0.05
	_cam.far = 60.0
	_cam.fov = CAM_FOV
	_cam.current = false
	add_child(_cam)


static var _shader: Shader = null

## The glass: the picture, a little glow off the brights, faint scanlines that fade before they can
## shimmer, darker corners.
static func make_material(tex: Texture2D) -> ShaderMaterial:
	if _shader == null:
		_shader = Shader.new()
		_shader.code = """
shader_type spatial;
render_mode unshaded, cull_back, shadows_disabled, fog_disabled;
uniform sampler2D screen_tex : source_color, filter_linear_mipmap, repeat_disable;
uniform float lines = 425.0;
uniform float brightness = 1.3;
void fragment() {
	vec3 c = texture(screen_tex, UV).rgb;
	float per_px = fwidth(UV.y) * lines;
	float fade = 1.0 - smoothstep(0.18, 0.45, per_px);
	float sl = 0.5 + 0.5 * cos(UV.y * lines * 6.2831853);
	c *= 1.0 - 0.18 * sl * fade;
	vec2 d = UV - 0.5;
	c *= 1.0 - 0.4 * dot(d, d);
	c += vec3(0.002, 0.008, 0.012);
	ALBEDO = c * brightness;
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = _shader
	mat.set_shader_parameter("screen_tex", tex)
	return mat


## Warmup (scripts/warmup.gd): one small copy of the screen and its shader, drawn once.
static func warm(parent: Node3D) -> void:
	var vp := SubViewport.new()
	vp.size = Vector2i(320, 170)
	vp.disable_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	parent.add_child(vp)
	var s: Control = ScreenScript.new()
	vp.add_child(s)
	s.begin(1, "Warmup", {"u": ["surg_steady"], "p": 1, "f": "surg_steady"})
	s.t = 5.0
	var q := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(0.64, 0.34)
	q.mesh = qm
	q.material_override = make_material(vp.get_texture())
	parent.add_child(q)
	q.position = Vector3(-1.2, 0.4, 0.2)


func _ready() -> void:
	game = get_tree().get_first_node_in_group("game")
	Net.station_users_changed.connect(_on_station_users_changed)
	Net.skills_changed.connect(_on_skills_changed)
	_hint = CanvasLayer.new()
	_hint.name = "VeinHint"
	_hint.layer = 40
	_hint.visible = false
	add_child(_hint)
	_hint_label = Label.new()
	_hint_label.text = "Click a vein to read it   ·   INFUSE or Enter spends points   ·   Esc, E or a step back to leave"
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_label.add_theme_font_size_override("font_size", 18)
	_hint_label.add_theme_color_override("font_color", Color(0.75, 0.86, 0.9))
	_hint_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_hint_label.add_theme_constant_override("outline_size", 6)
	_hint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint_label.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_hint_label.offset_top = -40
	_hint_label.offset_bottom = -12
	_hint.add_child(_hint_label)
	_on_station_users_changed()


func _exit_tree() -> void:
	if _open:
		close()


# ---------------------------------------------------------------------------- everyone

func _on_station_users_changed() -> void:
	var u := Net.station_user(STATION)
	if u != _user:
		_user = u
		if u != 0:
			screen.begin(u, Net.name_for(u), Net.skills_for(u))
			_grow_sound_done = false
			if is_inside_tree():
				Audio.play("personnel_vein_scan", _plate_mesh, -3.0, 0.02)
		else:
			screen.end()
	# This machine asked for it and got it.
	if _pending != null and is_instance_valid(_pending):
		if u == _pending.peer_id:
			var p := _pending
			_pending = null
			_do_open(p)
		elif u != 0:
			_pending = null


func _on_skills_changed() -> void:
	if _user == 0:
		return
	var before: Dictionary = screen.unlocked.duplicate()
	screen.update_entry(Net.skills_for(_user))
	for id in screen.unlocked.keys():
		if not before.has(id) and is_inside_tree():
			Audio.play("personnel_vein_unlock", quad, -2.0, 0.03)
			break


func _process(delta: float) -> void:
	screen.tick(delta)
	var cam := get_viewport().get_camera_3d()
	var near := cam != null and cam.global_position.distance_to(_centre) < RENDER_RANGE
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if near or _open else SubViewport.UPDATE_DISABLED
	if _user != 0 and not _grow_sound_done and screen.t >= ScreenScript.T_HAND_VEINS:
		_grow_sound_done = true
		Audio.play("personnel_vein_grow", quad, -4.0, 0.02)
	_update_glow()
	if game == null or not is_instance_valid(game):
		game = get_tree().get_first_node_in_group("game")
		return
	if not _open:
		_poll_open()
		return
	if not _still_valid():
		close()
		return
	_player.bot_move = Vector2.ZERO
	_update_camera(delta)
	_update_pointer()
	if Input.is_action_just_pressed("interact") or Input.is_action_just_pressed("ui_cancel") \
			or Input.is_action_just_pressed("move_back") or Input.is_action_just_pressed("move_left") \
			or Input.is_action_just_pressed("move_right") or Input.is_action_just_pressed("move_forward"):
		close()
	elif Input.is_action_just_pressed("ui_accept") and Skills.focus != "":
		_unlock(Skills.focus)


func _update_glow() -> void:
	var t: float = screen.t
	var e := 0.18 + 0.1 * sin(Time.get_ticks_msec() * 0.002)   # idle: breathing
	var col := Color(0.3, 0.8, 1.0)
	if _user != 0:
		if t < ScreenScript.T_SCAN_END:
			e = 0.55 + 0.35 * absf(sin(t * 9.0))   # reading
		else:
			e = 0.3
			col = Color(0.3, 0.8, 1.0).lerp(Color(1.0, 0.25, 0.25), clampf((t - ScreenScript.T_TREE) / 1.5, 0.0, 0.6))
	_plate_mat.albedo_color = Color(col, e)
	_light.light_energy = 0.0 if _user == 0 else 0.35 * clampf(t / 0.4, 0.0, 1.0)
	_light.light_color = col


# ---------------------------------------------------------------------------- this machine's session

func is_open() -> bool:
	return _open


func active_camera() -> Camera3D:
	return _cam if _open else null


func _poll_open() -> void:
	if _pending != null and (not is_instance_valid(_pending) or not _pending.alive or _pending.downed):
		_pending = null
	if _pending != null:
		return
	var p = game.local_player() if game.has_method("local_player") else null
	if p == null or not p.is_local or not p.alive or p.downed:
		return
	if String(p.aim_id) != AIM_ID or String(p.aim_prompt).begins_with("!"):
		return
	if Input.is_action_just_pressed("interact"):
		_pending = p
		Net.claim_station(STATION)


func _still_valid() -> bool:
	return _player != null and is_instance_valid(_player) and _player.alive and not _player.downed \
			and Net.station_user(STATION) == _player.peer_id


## Stand at the plate facing the screen, and start the glide.
func _do_open(p: Node) -> void:
	if _open:
		return
	_player = p
	_open = true
	var feet := _plate + _out * STAND_OUT
	feet.y = _plate.y - 1.0
	if game.has_method("_floor_at"):
		feet = game._floor_at(feet + Vector3.UP * 0.5)
	p.teleport(feet)
	var yaw := atan2(_out.x, _out.z)
	p._yaw = yaw
	p.rotation.y = yaw
	p._pitch = -0.5
	if p.head != null:
		p.head.rotation.x = p._pitch
	_cam_from = p.camera.global_transform if p.camera != null else Transform3D(Basis.looking_at(-_out), feet + Vector3.UP * 1.6)
	# The own body is on SELF, which this camera leaves out (it stands behind you).
	_cam.cull_mask = p.camera.cull_mask & ~LightRooms.SELF if p.camera != null else 0xFFFFF
	_glide = 0.0
	_update_camera(0.0)
	_hint.visible = true
	Skills.set_focus("")


func close() -> void:
	if not _open:
		return
	_open = false
	_cam.current = false
	_hint.visible = false
	screen.hover = ""
	screen.hover_button = false
	Net.release_station(STATION)
	_player = null


## The view that fits the whole screen, at this window's aspect.
func fitted_transform() -> Transform3D:
	var vp := get_viewport().get_visible_rect().size
	var aspect := vp.x / maxf(vp.y, 1.0)
	var half_v := tan(deg_to_rad(CAM_FOV) * 0.5)
	var d := maxf(_size.y * 0.5 * FIT_MARGIN / half_v, _size.x * 0.5 * FIT_MARGIN / (half_v * aspect))
	var pos := _centre + _out * d
	return Transform3D(Basis.looking_at(-_out, Vector3.UP), pos)


func _update_camera(delta: float) -> void:
	_glide = minf(1.0, _glide + delta / GLIDE_SECONDS)
	var k := _glide * _glide * (3.0 - 2.0 * _glide)
	# A beat looking down at your hand on the plate, then back and up to the screen.
	var hold := clampf(_glide * 3.0, 0.0, 1.0)
	var to := fitted_transform()
	var from := _cam_from
	if hold < 1.0:
		k = 0.0
	else:
		var g := clampf((_glide - 0.33) / 0.67, 0.0, 1.0)
		k = g * g * (3.0 - 2.0 * g)
	_cam.global_transform = from.interpolate_with(to, k)
	_cam.fov = CAM_FOV


## The mouse on the screen: hover here; a click is handled in _input.
func _update_pointer() -> void:
	var px := _mouse_pixel()
	if px.x < 0.0:
		screen.hover = ""
		screen.hover_button = false
		return
	screen.point_at(px)


func _mouse_pixel() -> Vector2:
	if _glide < 1.0:
		return Vector2(-1, -1)
	var mouse := get_viewport().get_mouse_position()
	var from := _cam.project_ray_origin(mouse)
	var dir := _cam.project_ray_normal(mouse)
	var plane := Plane(_out, _centre + _out * GLASS_OUT)
	var hit = plane.intersects_ray(from, dir)
	if hit == null:
		return Vector2(-1, -1)
	return pixel_at(hit)


## Where a world point on the glass lands on the screen texture ((-1, -1) off it).
func pixel_at(world: Vector3) -> Vector2:
	var local := quad.global_transform.affine_inverse() * world
	var u := local.x / _size.x + 0.5
	var v := 0.5 - local.y / _size.y
	if u < 0.0 or u > 1.0 or v < 0.0 or v > 1.0:
		return Vector2(-1, -1)
	return Vector2(u * TEX.x, v * TEX.y)


func _input(event: InputEvent) -> void:
	if not _open:
		return
	var mb := event as InputEventMouseButton
	if mb == null or not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	var px := _mouse_pixel()
	if px.x < 0.0:
		return
	click(px)


## A click at a screen pixel (also the test seam).
func click(px: Vector2) -> void:
	var what: String = screen.click_at(px)
	if what.begins_with("select:"):
		Skills.set_focus(what.trim_prefix("select:"))
	elif what.begins_with("unlock:"):
		_unlock(what.trim_prefix("unlock:"))


func _unlock(id: String) -> void:
	var problem := Skills.unlock(id)
	if problem != "" and game != null and game.has_method("tell") and _player != null:
		game.tell(_player, problem, 3.0)
