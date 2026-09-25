extends Node3D
## FLASHLIGHT POSE (2026-09-24): the torch a player's BODY holds, the one teammates see (and the local
## player's own body over the shoulder or in a mirror). body_hands.gd puts it in a hand every frame and
## aims it where the player looks; for everyone else's copy of a player it also moves that player's
## SpotLight3D onto the lens, so the beam comes out of the torch instead of out of the middle of the
## head. The first-person torch in your own hand is scripts/hands/fp_arms.gd's; this reuses its model.
##
## Three looks, one per state (Player.torch_state()), all from replicated state already on the wire:
##   OFF   a dark lens, nothing else
##   ON    a warm lens, a soft flare you see when it points your way, and a faint shaft of light
##   SCAN  the scanner's blue lens and flare (scan_fx.gd draws the laser itself), no shaft: the
##         torch's own light goes out while it is a laser, exactly as it does in first person
## Origin: the middle of the handle (the fist). The lens is at -Z.

const Arms := preload("res://scripts/hands/fp_arms.gd")

const OFF := 0
const ON := 1
const SCAN := 2

## Drawn a little bigger than the first-person one, so it reads in a hand from across a room.
const SCALE := 1.5
## The lens, from the handle's middle (fp_arms.make_torch puts it 0.151 along -Z), after SCALE.
const LENS_Z := 0.151 * SCALE
## The shaft: how long, and how wide it opens at its far end.
const SHAFT_LEN := 2.4
const SHAFT_END_R := 0.5
const WARM := Color(1.0, 0.86, 0.62)
const BLUE := Color(0.25, 0.8, 1.0)

const FLARE_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
uniform vec4 tint : source_color = vec4(1.0, 0.86, 0.62, 1.0);
varying float facing;
void vertex() {
	// Billboard: the quad turns to the camera; how much of the lens you see decides how bright.
	vec3 fwd = normalize(-MODEL_MATRIX[2].xyz);
	vec3 to_cam = normalize(CAMERA_POSITION_WORLD - MODEL_MATRIX[3].xyz);
	facing = max(dot(fwd, to_cam), 0.0);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
}
void fragment() {
	float d = length(UV - 0.5) * 2.0;
	float core = pow(clamp(1.0 - d, 0.0, 1.0), 3.0);
	float k = 0.4 + 0.6 * facing * facing;
	ALBEDO = tint.rgb * core * tint.a * k;
}
"""

const SHAFT_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;
uniform vec4 tint : source_color = vec4(1.0, 0.86, 0.62, 0.06);
uniform float len = 2.4;
varying float along;
void vertex() {
	along = clamp(0.5 - VERTEX.y / len, 0.0, 1.0);   // 0 at the lens, 1 at the far end
}
void fragment() {
	float edge = pow(abs(dot(NORMAL, VIEW)), 2.6);   // soft sides: brightest through the middle
	float fade = (1.0 - along) * (1.0 - along);
	ALBEDO = tint.rgb * tint.a * edge * fade;
}
"""

static var _flare_shader: Shader = null
static var _shaft_shader: Shader = null
static var _quad: QuadMesh = null
static var _cone: CylinderMesh = null

var lens: MeshInstance3D
var flare: MeshInstance3D
var shaft: MeshInstance3D
var state := -1
var _lens_mat: StandardMaterial3D
var _flare_mat: ShaderMaterial
var _shaft_mat: ShaderMaterial


func _init() -> void:
	name = "TorchTP"
	var model := Arms.make_torch()
	model.scale = Vector3.ONE * SCALE
	add_child(model)
	lens = model.get_node("Lens") as MeshInstance3D
	_lens_mat = StandardMaterial3D.new()
	_lens_mat.roughness = 0.2
	_lens_mat.emission_enabled = true
	lens.material_override = _lens_mat
	for mi in find_children("*", "GeometryInstance3D", true, false):
		(mi as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if _flare_shader == null:
		_flare_shader = Shader.new()
		_flare_shader.code = FLARE_SHADER
		_shaft_shader = Shader.new()
		_shaft_shader.code = SHAFT_SHADER
		_quad = QuadMesh.new()
		_quad.size = Vector2(0.4, 0.4)
		_cone = CylinderMesh.new()
		_cone.top_radius = 0.035
		_cone.bottom_radius = SHAFT_END_R
		_cone.height = SHAFT_LEN
		_cone.radial_segments = 12
		_cone.rings = 1
		_cone.cap_top = false
		_cone.cap_bottom = false
	flare = MeshInstance3D.new()
	flare.name = "Flare"
	flare.mesh = _quad
	_flare_mat = ShaderMaterial.new()
	_flare_mat.shader = _flare_shader
	flare.material_override = _flare_mat
	flare.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	flare.position = Vector3(0.0, 0.0, -LENS_Z - 0.01)
	add_child(flare)
	shaft = MeshInstance3D.new()
	shaft.name = "Shaft"
	shaft.mesh = _cone
	_shaft_mat = ShaderMaterial.new()
	_shaft_mat.shader = _shaft_shader
	_shaft_mat.set_shader_parameter("len", SHAFT_LEN)
	shaft.material_override = _shaft_mat
	shaft.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# The cylinder's narrow top (+Y) at the lens, opening out along -Z.
	shaft.transform = Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0.0, 0.0, -LENS_Z - SHAFT_LEN * 0.5))
	add_child(shaft)
	set_state(OFF, true)


## `own`: this is the local player's own body (a mirror, the shoulder camera). Its torch's light stays
## at the head, where it lights the first-person view, so no shaft here: a second one would double it.
func set_state(s: int, own: bool) -> void:
	var key := s * 2 + (1 if own else 0)
	if key == state:
		return
	state = key
	match s:
		ON:
			_lens_mat.albedo_color = Color(1.0, 0.92, 0.75)
			_lens_mat.emission = WARM
			_lens_mat.emission_energy_multiplier = 2.6
			_flare_mat.set_shader_parameter("tint", Color(WARM, 1.6))
			_shaft_mat.set_shader_parameter("tint", Color(WARM, 0.05))
		SCAN:
			_lens_mat.albedo_color = Color(0.1, 0.55, 0.62)
			_lens_mat.emission = Color(0.05, 0.6, 0.85)
			_lens_mat.emission_energy_multiplier = 2.4
			_flare_mat.set_shader_parameter("tint", Color(BLUE, 1.4))
		_:
			_lens_mat.albedo_color = Color(0.32, 0.3, 0.26)
			_lens_mat.emission = Color.BLACK
			_lens_mat.emission_energy_multiplier = 0.0
	flare.visible = s != OFF
	shaft.visible = s == ON and not own


## The lens in this node's space, just past the glass (where the light and the laser start).
static func lens_offset() -> Vector3:
	return Vector3(0.0, 0.0, -LENS_Z - 0.02)
