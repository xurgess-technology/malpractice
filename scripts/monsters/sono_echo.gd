extends Node
## The Sonographer's echo, on every machine (docs/SONOGRAPHER.md, chunk B). Child "SonoEcho" of
## Game, at the same path everywhere, so the host's one reliable event lines up with every client's.
##
## The host's brain fires the wedge (sonographer_brain.gd `_fire_echo`) and calls `fire()`; that
## plays it here and broadcasts `sn_echo`. Every machine then:
##
##   - draws **the fan**: a translucent wedge of grainy ultrasound scan lines that sweeps out of the
##     wand fast, then fades, leaving the grain hanging in the air a moment;
##   - if the local player was one of the ones it caught, **images** them (a flash of ultrasound
##     grain over the whole screen) and **deafens** them: a short, soft, volume-capped squeal with
##     the game's audio muffled under it, both coming back over about a second.
##
## **The squeal must never hurt a real player's ears.** It is capped in the mixer, ramped in and
## out, never piercing, and the setting `soft_squeal` takes it down further still.

const FAN_SECONDS := 0.38       ## the sweep out
const FAN_FADE := 0.55          ## the grain hanging in the air after it
const FAN_SEGMENTS := 24
const FAN_HEIGHT := 2.4         ## how tall the fan is at its far edge, metres

const FLASH_IN := 0.06
const FLASH_SECONDS := 0.85     ## the imaging grain over your screen
const DEAFEN_SECONDS := 1.25    ## the squeal and the muffle, in and out
const SQUEAL_DB := -9.0
const SQUEAL_SOFT_DB := -19.0

const FAN_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;
uniform vec3 tint : source_color = vec3(0.61, 0.42, 1.0);
uniform float amount = 1.0;
uniform float grain_seed = 0.0;
varying vec3 local_pos;
void vertex() { local_pos = VERTEX; }
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
void fragment() {
	float r = length(local_pos.xz);
	// scan lines running out along the fan, and ultrasound speckle over them
	float lines = 0.5 + 0.5 * sin(r * 26.0 - TIME * 22.0);
	float speckle = hash(floor(vec2(r * 30.0, local_pos.y * 24.0 + grain_seed)) + floor(TIME * 24.0));
	float edge = 1.0 - smoothstep(0.55, 1.0, r / max(0.001, abs(local_pos.y) + r));
	float a = amount * (0.16 + 0.30 * lines + 0.30 * speckle) * (0.45 + 0.55 * edge);
	ALBEDO = tint * a;
	ALPHA = clamp(a, 0.0, 0.9);
}
"""

const FLASH_SHADER := """
shader_type canvas_item;
uniform float amount = 0.0;
uniform float seed = 0.0;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
void fragment() {
	vec2 d = UV - vec2(0.5);
	float r = length(d * vec2(1.2, 1.0));
	// an ultrasound frame: a bright wash, speckle, and scan arcs sweeping across it
	float speckle = hash(floor(vec2(UV.x * 420.0, UV.y * 260.0)) + vec2(seed, floor(TIME * 30.0)));
	float arcs = 0.5 + 0.5 * sin(r * 70.0 - TIME * 16.0);
	float a = amount * (0.22 + 0.28 * speckle + 0.13 * arcs) * (1.0 - 0.45 * r);
	COLOR = vec4(vec3(0.72, 0.62, 0.98) * (0.55 + 0.45 * speckle), clamp(a, 0.0, 0.92));
}
"""

var game: Node = null

var _fans: Array = []            ## [{node, mat, t}]
var _layer: CanvasLayer
var _veil: ColorRect
var _veil_mat: ShaderMaterial
var _flash := 0.0
var _deafen := 0.0
var _rng := RandomNumberGenerator.new()
static var _fan_shader: Shader
static var _flash_shader: Shader
static var _fan_mesh: ArrayMesh
## Echoes this machine has drawn, and the last one's data: the tests read these.
var seen := 0
var last: Dictionary = {}
var imaged_count := 0            ## times the local player has been caught


func setup(g: Node) -> void:
	game = g
	_rng.randomize()
	_layer = CanvasLayer.new()
	_layer.name = "SonoImaged"
	_layer.layer = 3
	add_child(_layer)
	if _flash_shader == null:
		_flash_shader = Shader.new()
		_flash_shader.code = FLASH_SHADER
	_veil = ColorRect.new()
	_veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_veil_mat = ShaderMaterial.new()
	_veil_mat.shader = _flash_shader
	_veil.material = _veil_mat
	_layer.add_child(_veil)
	_layer.visible = false


## scripts/warmup.gd: the fan's grain shader and the imaging flash's are compiled here, once, so the
## first echo of a shift does not stutter. Everything is left on the shelf, hidden and asleep.
static func warm(shelf: Node3D) -> void:
	if _fan_shader == null:
		_fan_shader = Shader.new()
		_fan_shader.code = FAN_SHADER
	if _flash_shader == null:
		_flash_shader = Shader.new()
		_flash_shader.code = FLASH_SHADER
	var mi := MeshInstance3D.new()
	mi.name = "WarmSonoFan"
	mi.mesh = fan_mesh()
	var mat := ShaderMaterial.new()
	mat.shader = _fan_shader
	mat.set_shader_parameter("amount", 1.0)
	mat.set_shader_parameter("grain_seed", 0.0)
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.scale = Vector3(1.2, 1.0, 2.0)
	mi.position = Vector3(0.0, 0.6, -1.0)
	shelf.add_child(mi)
	# The flash is a canvas item: one full-screen rect drawn at nothing, so its shader compiles too.
	var layer := CanvasLayer.new()
	layer.name = "WarmSonoFlash"
	layer.layer = 3
	var rect := ColorRect.new()
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fm := ShaderMaterial.new()
	fm.shader = _flash_shader
	fm.set_shader_parameter("amount", 0.004)
	fm.set_shader_parameter("seed", 0.0)
	rect.material = fm
	layer.add_child(rect)
	shelf.add_child(layer)


## Host: the wedge has just gone off. Play it here and tell everyone else.
func fire(data: Dictionary) -> void:
	on_event("sn_echo", data)
	if game != null and game.has_method("_broadcast"):
		game._broadcast("sn_echo", data)


func on_event(kind: String, data: Dictionary) -> void:
	if kind != "sn_echo":
		return
	seen += 1
	last = data
	var origin: Vector3 = data.get("o", Vector3.ZERO)
	var dir: Vector3 = data.get("d", Vector3.FORWARD)
	var half: float = float(data.get("h", 0.52))
	var reach: float = float(data.get("r", 14.0))
	_spawn_fan(origin, dir, half, reach)
	var peers: Array = data.get("pk", [])
	if peers.has(_my_peer()):
		imaged_count += 1
		_imaged()


func _my_peer() -> int:
	if game != null and game.has_method("local_player"):
		var p = game.local_player()
		if p != null:
			return int(p.peer_id)
	return Net.my_id()


# ---------------------------------------------------------------- the fan

## A wedge lying flat, its point at the wand and its far edge `reach` away, `half` radians each
## side: the same shape `sonographer_brain.in_echo` tests, so what you see is what catches you.
## Five sheets stacked in Y give it body, so it reads from the side too; it tapers to nothing
## at the wand.
static func make_fan_mesh(half: float, reach: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for row: float in [-1.0, -0.5, 0.0, 0.5, 1.0]:
		var y: float = row * FAN_HEIGHT * 0.5
		for i in FAN_SEGMENTS:
			var a0 := -half + 2.0 * half * float(i) / float(FAN_SEGMENTS)
			var a1 := -half + 2.0 * half * float(i + 1) / float(FAN_SEGMENTS)
			# x across, z out: the wedge points along -Z, which is the way the wand points
			st.set_normal(Vector3.UP)
			st.add_vertex(Vector3(0.0, row * 0.02, 0.0))
			st.add_vertex(Vector3(sin(a0) * reach, y, -cos(a0) * reach))
			st.add_vertex(Vector3(sin(a1) * reach, y, -cos(a1) * reach))
	return st.commit()


## The default fan (60 degrees, 14 m), for the warmup.
static func fan_mesh() -> ArrayMesh:
	if _fan_mesh == null:
		_fan_mesh = make_fan_mesh(deg_to_rad(30.0), 14.0)
	return _fan_mesh


func _spawn_fan(origin: Vector3, dir: Vector3, half: float, reach: float) -> void:
	if game == null or not game.is_inside_tree():
		return
	if _fan_shader == null:
		_fan_shader = Shader.new()
		_fan_shader.code = FAN_SHADER
	var mi := MeshInstance3D.new()
	mi.name = "SonoFan"
	mi.mesh = make_fan_mesh(half, reach)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = reach
	var mat := ShaderMaterial.new()
	mat.shader = _fan_shader
	mat.set_shader_parameter("amount", 1.0)
	mat.set_shader_parameter("grain_seed", _rng.randf() * 100.0)
	mi.material_override = mat
	var flat := Vector3(dir.x, 0.0, dir.z)
	flat = flat.normalized() if flat.length() > 0.001 else Vector3.FORWARD
	# The mesh already has the arc and the reach in it; it only needs turning to face the way the
	# wand points (its -Z) and standing at the wand's tip.
	game.add_child(mi)
	mi.global_transform = Transform3D(Basis(Vector3.UP, atan2(-flat.x, -flat.z)), origin)
	_fans.append({"node": mi, "mat": mat, "t": 0.0})


# ---------------------------------------------------------------- imaged and deafened

## The echo caught the local player: the grain over their screen and the squeal in their ears.
func _imaged() -> void:
	_flash = 1.0
	_deafen = 1.0
	_veil_mat.set_shader_parameter("seed", _rng.randf() * 100.0)
	var soft := bool(Settings.get_value("soft_squeal"))
	# 2D and volume capped: it is the same in your ears wherever the monster is, and it is never loud.
	Audio.play("monsters_sono_squeal", null, SQUEAL_SOFT_DB if soft else SQUEAL_DB, 0.03)


func _process(delta: float) -> void:
	for i in range(_fans.size() - 1, -1, -1):
		var f: Dictionary = _fans[i]
		f.t = float(f.t) + delta
		var t: float = f.t
		var mi: MeshInstance3D = f.node
		if not is_instance_valid(mi):
			_fans.remove_at(i)
			continue
		if t >= FAN_SECONDS + FAN_FADE:
			mi.queue_free()
			_fans.remove_at(i)
			continue
		# It sweeps out fast (but slow enough to read), then the grain hangs where it swept and fades.
		var out := clampf(t / FAN_SECONDS, 0.0, 1.0)
		var grow := 0.12 + 0.88 * out * out * (3.0 - 2.0 * out)
		mi.scale = Vector3(grow, 0.4 + 0.6 * grow, grow)
		(f.mat as ShaderMaterial).set_shader_parameter("amount",
			1.0 if t < FAN_SECONDS else pow(1.0 - (t - FAN_SECONDS) / FAN_FADE, 1.6))
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta / FLASH_SECONDS)
		_layer.visible = true
		_veil_mat.set_shader_parameter("amount", _flash * _flash)
	elif _layer != null and _layer.visible:
		_layer.visible = false
	if _deafen > 0.0:
		# Everything else goes muffled under the squeal and comes back over the same time.
		_deafen = maxf(0.0, _deafen - delta / DEAFEN_SECONDS)
		Audio.set_deafen(_deafen)
	elif Audio.deafen > 0.0:
		Audio.set_deafen(0.0)


## Everything this machine is showing goes away (a new shift, a wing rebuild).
func reset() -> void:
	for f in _fans:
		if is_instance_valid(f.node):
			f.node.queue_free()
	_fans.clear()
	_flash = 0.0
	_deafen = 0.0
	if _layer != null:
		_layer.visible = false
	Audio.set_deafen(0.0)
