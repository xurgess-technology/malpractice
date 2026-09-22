extends Node3D
## PANEL TESTBED (docs/PANEL_STYLE.md): the flat glowing diagram a panel surgery step is played on.
##
## THE PANEL IS THE INPUT SURFACE, THE BODY IS THE CONSEQUENCE SURFACE. The step's puzzle is drawn
## here as an openly 2D diagram; the real patient stays visible around the panel's edges and reacts
## to what happens on it. Nothing is left sitting on the body when the panel closes.
##
## It is a quad with an unshaded emissive material fed by a SubViewport, so it is a real object in
## the room: every machine builds its own copy and onlookers see it, and its contents, from their
## own angle. It exists only while somebody is operating.
##
## Placement: anchored at the step's site, lifted `panel_lift` along the site normal, then oriented
## ONCE at open time to face the operator's final leaned-in camera pose. It is NOT a per-frame
## billboard: once open it is a fixed object that you can look at from the side.
##
## Coordinates: a panel game works in DIAGRAM MILLIMETRES. The panel is a magnifier -- `view_mm`
## (120 x 80 mm by default) of diagram fits on `panel_size` metres of quad. mm_to_px() converts for
## drawing, mm_of() converts the framework's cursor (panel-local metres, +x right, +y DOWN) to mm.
##
## How a minigame uses it:
##     _panel = PanelScript.new()
##     _panel.header = "LAC / CLOSE"
##     _panel.painter = _paint            # func(c: CanvasItem) -> void, draws in pixels
##     add_child(_panel)                  # as a child of the minigame, i.e. at the site
##     _panel.open(camera_local)          # camera_local: the operating camera in site-local metres
##   and in the minigame:
##     func uses_panel() -> bool: return true
##     func input_plane() -> Transform3D: return _panel.input_plane()
##     func plane_extent() -> Vector2: return _panel.half_size()

const StyleScript := preload("res://scripts/surgery/panel/panel_style.gd")
## Render layer 20, the same one every minigame's own props use: decals project onto layer 1 only,
## so the patient's blood never stamps across the diagram.
const OWN_LAYER := 1 << 19

signal opened
signal closed

enum State { SHUT, OPENING, OPEN, CLOSING }

# -- size and framing ------------------------------------------------------------------------------
## Metres. 3:2, matching the SubViewport, so nothing is stretched.
@export var panel_size := Vector2(0.52, 0.3467)
## Metres along the site normal from the site marker to the panel's centre.
@export var panel_lift := 0.24
## The diagram area the panel shows, in millimetres.
@export var view_mm := Vector2(120.0, 80.0)
## SubViewport width; the height follows panel_size's aspect.
@export var texture_width := 1200
## Degrees the panel stands up PAST facing the operator square on, tipping its top back toward them.
## Square on is easiest to play but lies almost flat over the patient, which is nearly edge-on to
## anyone else in the room; a few degrees of this costs the operator nothing (cos 12 deg) and gives
## onlookers a face to read.
@export_range(0.0, 45.0, 1.0) var tilt_bias_deg := 12.0

# -- opening and closing ---------------------------------------------------------------------------
@export_range(0.05, 1.0, 0.01) var open_time := 0.20
@export_range(0.05, 1.0, 0.01) var close_time := 0.15
@export_range(0.3, 1.0, 0.01) var open_scale := 0.85
## How far past 1.0 the open animation overshoots.
@export_range(0.0, 0.3, 0.005) var overshoot := 0.055
## Empty on purpose: the panel testbed has no sound of its own yet. Assign a stream to hear one.
@export var open_sound: AudioStream
@export var close_sound: AudioStream

# -- light -----------------------------------------------------------------------------------------
## A weak light tinted to the panel, so it glows onto the patient and the operator's hands.
@export_range(0.0, 2.0, 0.01) var light_energy := 0.30
@export_range(0.1, 3.0, 0.05) var light_range := 1.15
## How much of the operating camera's work lamp a panel step wants (Minigame.lamp_scale). The
## diagram is its own light source, so the lamp comes down or it washes the frame out.
@export_range(0.0, 2.0, 0.05) var lamp_scale := 0.55
## How bright the diagram itself is on the quad.
@export_range(0.2, 3.0, 0.05) var brightness := 1.0
## The back face: a panel seen from the wrong side is a dim plate, not a mirrored diagram.
@export_range(0.0, 1.0, 0.01) var back_dim := 0.12

# -- going see-through ------------------------------------------------------------------------------
## When something goes wrong the panel clears out of the way for a moment so the patient can be seen
## through it -- the flinch, the blood, the monitor -- and then comes back. `ghost()` asks for it.
## How see-through it goes.
@export_range(0.0, 1.0, 0.01) var ghost_alpha := 0.24
## How much of the diagram is left while it is out of the way.
@export_range(0.0, 1.0, 0.01) var ghost_brightness := 0.55
## Out of the way quickly (you want to see what happened NOW), back slowly.
@export_range(0.02, 1.0, 0.01) var ghost_in := 0.09
@export_range(0.05, 2.0, 0.01) var ghost_out := 0.45

# -- shake --------------------------------------------------------------------------------------
## ARCADE (docs/ARCADE_SURGERY.md): the panel is bolted to something, and when the patient jerks or
## a tool binds it rattles. `shake()` asks for it; strength is 0..1.
@export_range(0.0, 0.05, 0.001) var shake_throw := 0.014   ## metres at full strength
@export_range(0.05, 1.5, 0.01) var shake_time := 0.3
@export_range(4.0, 80.0, 1.0) var shake_hz := 26.0

# -- contents --------------------------------------------------------------------------------------
## Small header, top-left inside the frame.
var header := ""
## Small dim text, top-right (the table number).
var right_text := ""
## func(c: CanvasItem) -> void. Draws the diagram in panel pixels, over the chrome.
var painter: Callable = Callable()
## False when the game draws its own surface (the ink/paper look, scripts/surgery/panel/ink.gd):
## the teal background, frame and header are then not drawn under it.
var chrome := true
## True when the texture has holes: where nothing is drawn the panel is see-through (the ink look's
## clipboard stands in the room with nothing round it). Set before the panel enters the tree.
var transparent := false
var style: StyleScript = null

var state: int = State.SHUT
var _k := 0.0                     # 0..1 through the current open / close
var _canvas: Control
var _vp: SubViewport
var _quad: MeshInstance3D
var _mat: ShaderMaterial
var _light: OmniLight3D
var _oriented := false
var _ghost := 0.0                 # 0..1, how far out of the way it is right now
var _ghost_hold := 0.0            # seconds still to stay there
var _shake := 0.0                 # seconds of rattle left
var _shake_k := 0.0               # 0..1 strength of the current rattle
var _rest := Vector3.ZERO         # where the panel hangs when it is not rattling

static var _shader: Shader = null


func _init() -> void:
	name = "SurgeryPanel"
	style = StyleScript.new()


func _ready() -> void:
	_build()


# ------------------------------------------------------------------------------ geometry

func half_size() -> Vector2:
	return panel_size * 0.5


## Pixels per diagram millimetre. 10.0 at the defaults.
func px_per_mm() -> Vector2:
	var px := tex_size()
	return Vector2(px.x / view_mm.x, px.y / view_mm.y)


func tex_size() -> Vector2:
	return Vector2(texture_width, roundf(texture_width * panel_size.y / panel_size.x))


## Diagram millimetres (origin at the panel's centre, +y down) to panel pixels.
func mm_to_px(mm: Vector2) -> Vector2:
	return tex_size() * 0.5 + mm * px_per_mm()


func mm_len_px(mm: float) -> float:
	return mm * px_per_mm().x


## The framework's cursor -- panel-local metres, +x right, +y down -- as diagram millimetres.
func mm_of(p: Vector2) -> Vector2:
	var h := half_size()
	return Vector2(p.x / h.x * view_mm.x * 0.5, p.y / h.y * view_mm.y * 0.5)


## Diagram millimetres back to the framework's cursor space (the bot's return value).
func metres_of(mm: Vector2) -> Vector2:
	var h := half_size()
	return Vector2(mm.x / (view_mm.x * 0.5) * h.x, mm.y / (view_mm.y * 0.5) * h.y)


## The plane the operator's mouse is projected onto, replacing the work plane: basis.y is the panel
## normal and basis.z points DOWN the panel, which is what Minigame.screen_to_plane wants.
func input_plane() -> Transform3D:
	var xf := global_transform if is_inside_tree() else transform
	var right := xf.basis.x.normalized()
	var normal := xf.basis.z.normalized()
	return Transform3D(Basis(right, normal, right.cross(normal)), xf.origin)


## Where the panel sits and faces, in the parent's (the site's) local space, given where the
## operating camera ends up. Oriented once, at open time: the panel is a fixed object, not a
## billboard. Local +Y is out of the patient, local +Z is back toward the operator.
static func local_pose(camera_local: Vector3, lift: float, bias_deg := 0.0) -> Transform3D:
	var centre := Vector3(0.0, lift, 0.0)
	var normal := camera_local - centre
	if normal.length() < 0.02:
		normal = Vector3.UP
	normal = normal.normalized()
	var right := Vector3.RIGHT
	if absf(right.dot(normal)) > 0.95:
		right = Vector3.BACK
	right = (right - normal * right.dot(normal)).normalized()
	# Stand it up past square on: about the wound axis, from +Y (flat over the patient) toward +Z
	# (facing the operator), which is the direction everyone else in the room is looking from.
	if bias_deg != 0.0:
		normal = normal.rotated(right, deg_to_rad(bias_deg)).normalized()
	return Transform3D(Basis(right, normal.cross(right), normal), centre)


# ------------------------------------------------------------------------------ lifecycle

## Orient the panel for this camera pose and play it in. `camera_local` is the operating camera in
## the parent's local metres (Vector3(0, camera_pose.height, camera_pose.back)).
func open(camera_local: Vector3) -> void:
	if state == State.OPENING or state == State.OPEN:
		return
	if not _oriented:
		transform = local_pose(camera_local, panel_lift, tilt_bias_deg)
		_oriented = true
		# Fixed in the room from here on. The site marker rides the patient's breathing and stirs;
		# a panel that bobbed with it would read as stuck to the body instead of hanging over it.
		if is_inside_tree():
			var g := global_transform
			top_level = true
			global_transform = g
			_rest = g.origin
	state = State.OPENING
	_k = 0.0
	visible = true
	_apply_anim()
	_set_updating(true)
	redraw()
	_play(open_sound)
	opened.emit()


func close() -> void:
	if state == State.SHUT or state == State.CLOSING:
		return
	state = State.CLOSING
	_k = 0.0
	_play(close_sound)
	closed.emit()


func is_open() -> bool:
	return state == State.OPENING or state == State.OPEN


## Clear out of the way for `hold` seconds so the patient can be seen through the panel: a tear, a
## gush, a jerk. Calling it again while it is already out of the way extends the stay.
func ghost(hold: float) -> void:
	_ghost_hold = maxf(_ghost_hold, hold)


## Rattle the whole panel for a moment. `strength` 0..1; calling it again while it is still going
## takes the louder of the two.
func shake(strength: float) -> void:
	_shake_k = maxf(_shake_k, clampf(strength, 0.0, 1.0))
	_shake = maxf(_shake, shake_time * _shake_k)


## Every frame, from the minigame's tick. Redraws the diagram while the panel is open.
func tick(delta: float) -> void:
	if state == State.SHUT:
		return
	if _shake > 0.0:
		_shake = maxf(0.0, _shake - delta)
		if _shake <= 0.0:
			_shake_k = 0.0
	if _ghost_hold > 0.0:
		_ghost_hold = maxf(0.0, _ghost_hold - delta)
		_ghost = move_toward(_ghost, 1.0, delta / maxf(0.01, ghost_in))
	else:
		_ghost = move_toward(_ghost, 0.0, delta / maxf(0.01, ghost_out))
	if state == State.OPENING:
		_k = minf(1.0, _k + delta / maxf(0.01, open_time))
		if _k >= 1.0:
			state = State.OPEN
	elif state == State.CLOSING:
		_k = minf(1.0, _k + delta / maxf(0.01, close_time))
	_apply_anim()
	if state == State.CLOSING and _k >= 1.0:
		state = State.SHUT
		visible = false
		_set_updating(false)
		return
	redraw()


## The colour of the light the panel throws on the patient (a paper panel glows warm, not teal).
func set_glow(col: Color) -> void:
	if _light != null:
		_light.light_color = col


## Draw the diagram again this frame.
func redraw() -> void:
	if _canvas != null and is_instance_valid(_canvas):
		_canvas.queue_redraw()
		_vp.render_target_update_mode = SubViewport.UPDATE_ONCE


func _apply_anim() -> void:
	var s := 1.0
	var fade := 1.0
	if state == State.OPENING:
		# Ease out with a little overshoot, so it pops in rather than growing.
		var e := 1.0 - pow(1.0 - _k, 3.0)
		s = lerpf(open_scale, 1.0, e) + overshoot * sin(_k * PI) * (1.0 - _k * 0.4)
		fade = clampf(_k * 1.6, 0.0, 1.0)
	elif state == State.CLOSING:
		s = lerpf(1.0, open_scale + 0.06, _k)
		fade = 1.0 - _k
	scale = Vector3(s, s, 1.0)
	if _oriented and top_level:
		if _shake > 0.0:
			var k: float = (_shake / maxf(0.01, shake_time)) * _shake_k
			var ph: float = _shake * shake_hz
			var off: Vector3 = global_basis.x * sin(ph * TAU) + global_basis.y * sin(ph * TAU * 1.37 + 1.1)
			global_position = _rest + off * shake_throw * k
		elif not global_position.is_equal_approx(_rest):
			global_position = _rest
	var clear: float = lerpf(1.0, ghost_alpha, _ghost)
	if _mat != null:
		_mat.set_shader_parameter("fade", fade * clear)
		_mat.set_shader_parameter("brightness", brightness * lerpf(1.0, ghost_brightness, _ghost))
	if _light != null:
		_light.light_energy = light_energy * fade * clear


func _play(stream: AudioStream) -> void:
	if stream == null or not is_inside_tree():
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = stream
	p.bus = "SFX" if AudioServer.get_bus_index("SFX") >= 0 else "Master"
	add_child(p)
	p.play()
	p.finished.connect(p.queue_free)


func _set_updating(on: bool) -> void:
	if _vp != null and is_instance_valid(_vp):
		_vp.render_target_update_mode = SubViewport.UPDATE_ONCE if on else SubViewport.UPDATE_DISABLED


# ------------------------------------------------------------------------------ build

func _build() -> void:
	if _quad != null:
		return
	var px := tex_size()
	_vp = SubViewport.new()
	_vp.name = "Viewport"
	_vp.size = Vector2i(int(px.x), int(px.y))
	_vp.disable_3d = true
	_vp.transparent_bg = transparent
	_vp.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_vp.gui_disable_input = true
	add_child(_vp)

	_canvas = Canvas.new()
	_canvas.name = "Canvas"
	_canvas.size = px
	_canvas.set("panel", self)
	_vp.add_child(_canvas)

	_quad = MeshInstance3D.new()
	_quad.name = "Quad"
	var qm := QuadMesh.new()
	qm.size = panel_size
	_quad.mesh = qm
	_mat = ShaderMaterial.new()
	_mat.shader = _panel_shader()
	# get_texture() only works once the SubViewport is inside the tree, which it is by now.
	_mat.set_shader_parameter("panel_tex", _vp.get_texture())
	_mat.set_shader_parameter("fade", 0.0)
	_mat.set_shader_parameter("brightness", brightness)
	_mat.set_shader_parameter("back_dim", back_dim)
	_mat.set_shader_parameter("tex_alpha", 1.0 if transparent else 0.0)
	_quad.material_override = _mat
	_quad.layers = OWN_LAYER
	_quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_quad)

	_light = OmniLight3D.new()
	_light.name = "PanelGlow"
	_light.light_color = style.glow_light
	_light.light_energy = 0.0
	_light.omni_range = light_range
	_light.omni_attenuation = 1.5
	_light.shadow_enabled = false
	_light.light_specular = 0.15
	_light.light_volumetric_fog_energy = 0.0
	_light.position = Vector3(0, 0, 0.02)
	add_child(_light)
	visible = false


static func _panel_shader() -> Shader:
	if _shader != null:
		return _shader
	_shader = Shader.new()
	_shader.code = "shader_type spatial;\n" \
		+ "render_mode unshaded, cull_disabled, shadows_disabled, fog_disabled, depth_draw_opaque;\n" \
		+ "uniform sampler2D panel_tex : source_color, filter_linear_mipmap, repeat_disable;\n" \
		+ "uniform float fade = 1.0;\n" \
		+ "uniform float brightness = 1.0;\n" \
		+ "uniform float back_dim = 0.12;\n" \
		+ "uniform float tex_alpha = 0.0;\n" \
		+ "void fragment() {\n" \
		+ "	vec4 t = texture(panel_tex, UV);\n" \
		+ "	vec3 c = t.rgb * brightness;\n" \
		+ "	// The back of the panel is a dim plate, never a mirrored diagram.\n" \
		+ "	if (!FRONT_FACING) {\n" \
		+ "		c = vec3(dot(c, vec3(0.3, 0.6, 0.1))) * back_dim + vec3(0.01, 0.03, 0.03);\n" \
		+ "	}\n" \
		+ "	ALBEDO = c;\n" \
		+ "	ALPHA = fade * mix(1.0, t.a, tex_alpha);\n" \
		+ "}\n"
	return _shader


## Warmup (scripts/warmup.gd): build one panel, open it and draw a frame, so the first real one
## does not compile its shader in the middle of a step.
static func warm(parent: Node3D) -> Node3D:
	var p = (load("res://scripts/surgery/panel/surgery_panel.gd") as GDScript).new()
	p.header = "LAC / CLOSE"
	p.right_text = "TABLE 1"
	parent.add_child(p)
	p.open(Vector3(0.0, 0.64, 0.25))
	p.tick(0.016)
	return p


## The panel's own surface: chrome from the style, then the game's diagram over it.
class Canvas extends Control:
	var panel: Node3D
	var _font: Font

	func _ready() -> void:
		_font = ThemeDB.fallback_font
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		if panel == null or not is_instance_valid(panel):
			return
		if _font == null:
			_font = ThemeDB.fallback_font
		if panel.chrome:
			panel.style.draw_chrome(self, size, panel.header, panel.right_text, _font)
		var p: Callable = panel.painter
		if p.is_valid():
			p.call(self)
