class_name Showers
extends Node3D
## SHOWERS (2026-09-24, Zach: "make the showers able to be turned on and off with E, they dont do
## anything, just likely shower water"): the personnel locker room's six wall showers
## (scripts/level/entrance.gd, drawn by scripts/level/piece_factory.gd's "shower" case) were set
## dressing only. This node overlays the part that works: E turns one on or off, and everyone in
## the room sees and hears it -- a falling stream off the head, a low mist where it hits the floor,
## and a looping water sound.
##
## Host-authoritative, the same shape as the crematorium's hatch (scripts/economy/furnace.gd):
## `Shower.on` is toggled by `interact` (which the host alone ever calls, docs/CONTRACTS.md), and
## replicates in the game snapshot ("shw" in game.gd). Off at shift start, like everything else a
## fresh level builds.
##
## Local frame per shower, matching piece_factory.gd's "shower" case exactly (origin on the floor
## at the wall face, the room toward -Z): the head sits at (0, HEAD_Y, HEAD_Z).

const HEAD_Y := 2.17
const HEAD_Z := -0.3
const WATER_CUE := "res://audio/sfx/personnel_shower_water.wav"

var _showers: Array = []   # Array[Shower]


## One shower: the thing you aim at and press E on. The actual state lives here (`on`) so a client
## rebuilding from the snapshot has somewhere to read and write it; the falling water and the sound
## are cosmetic children `Showers._add` wires up alongside it.
class Shower extends Area3D:
	var showers: Showers
	var index: int
	var on := false
	var stream: GPUParticles3D
	var mist: GPUParticles3D
	var audio: AudioStreamPlayer3D

	func interact_prompt(_p) -> String:
		return "Turn off shower" if on else "Turn on shower"

	func interact_hold() -> float:
		return 0.0

	func interact(_p) -> void:
		showers.toggle(index)


func setup(spots: Array, to_world: Callable) -> void:
	name = "Showers"
	set_meta("light_dynamic", true)   # light_rooms.gd: leave its layers alone (no light of its own)
	for i in spots.size():
		var s: Dictionary = spots[i]
		var basis := Basis(Vector3.UP, float(s.yaw))
		var origin: Vector3 = to_world.call(s.pos, 0.0)
		_add(i, Transform3D(basis, origin))


func _add(i: int, xf: Transform3D) -> void:
	var sh := Shower.new()
	sh.showers = self
	sh.index = i
	sh.name = "Shower%d" % i
	sh.collision_layer = C.L_INTERACT
	sh.collision_mask = 0
	sh.monitoring = false
	sh.add_to_group("interactable")
	sh.set_meta("interact_id", "shower_%d" % i)
	sh.transform = xf
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.5, 1.5, 0.5)
	cs.shape = box
	cs.position = Vector3(0, 0.95 + 0.7, -0.2)   # over the riser, arm and head (piece_defs "shower")
	sh.add_child(cs)
	sh.stream = _make_stream()
	sh.stream.position = Vector3(0, HEAD_Y, HEAD_Z)
	sh.add_child(sh.stream)
	sh.mist = _make_mist()
	sh.mist.position = Vector3(0, 0.02, HEAD_Z - 0.15)
	sh.add_child(sh.mist)
	sh.audio = _make_audio()
	sh.audio.position = Vector3(0, 1.0, HEAD_Z)
	sh.add_child(sh.audio)
	add_child(sh)
	_showers.append(sh)


# ---------------------------------------------------------------------------
# on / off

## Host: E on the shower. Client presses route through the usual interact RPC (docs/CONTRACTS.md);
## this only ever runs where `interact` runs.
func toggle(i: int) -> void:
	if i < 0 or i >= _showers.size():
		return
	var sh: Shower = _showers[i]
	set_on(i, not sh.on)


## Every machine: host from `toggle`, clients from the snapshot (apply_net_state). Idempotent, like
## furnace.set_hatch, so a client re-applying the host's own unchanged state every tick costs nothing.
func set_on(i: int, val: bool) -> void:
	if i < 0 or i >= _showers.size():
		return
	var sh: Shower = _showers[i]
	if sh.on == val:
		return
	sh.on = val
	if sh.stream != null:
		sh.stream.emitting = val
	if sh.mist != null:
		sh.mist.emitting = val
	if sh.audio != null:
		if val:
			if not sh.audio.playing and sh.audio.stream != null:
				# Offset each shower's loop so a row of them running together doesn't phase.
				sh.audio.play(fmod(float(hash(sh.name) & 0xFFFF) / 1000.0, sh.audio.stream.get_length()))
		else:
			sh.audio.stop()


# ---------------------------------------------------------------------------
# networking

## Just the indices that are on (empty most of the time: off at shift start, and showers are a
## corner of the map nobody leaves running).
func net_state() -> Dictionary:
	var on_list: Array = []
	for i in _showers.size():
		if (_showers[i] as Shower).on:
			on_list.append(i)
	return {} if on_list.is_empty() else {"on": on_list}


func apply_net_state(s: Dictionary) -> void:
	var on_list: Array = s.get("on", [])
	var wanted := {}
	for v in on_list:
		wanted[int(v)] = true
	for i in _showers.size():
		set_on(i, wanted.has(i))


# ---------------------------------------------------------------------------
# cheap particles (shared meshes and materials: one draw call's worth of state per kind, however
# many showers are running)

static var _drop_mesh: QuadMesh = null
static var _drop_mat: StandardMaterial3D = null
static var _mist_mat: StandardMaterial3D = null
static var _water_stream: AudioStreamWAV = null
static var _water_load_tried := false


static func _mesh() -> QuadMesh:
	if _drop_mesh == null:
		_drop_mesh = QuadMesh.new()
		_drop_mesh.size = Vector2(0.015, 0.05)
	return _drop_mesh


static func _drop_material() -> StandardMaterial3D:
	if _drop_mat == null:
		_drop_mat = StandardMaterial3D.new()
		_drop_mat.resource_name = "shower_drop"
		_drop_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_drop_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_drop_mat.albedo_color = Color(0.75, 0.85, 0.92, 0.4)
		_drop_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		_drop_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		_drop_mat.disable_receive_shadows = true
	return _drop_mat


static func _mist_material() -> StandardMaterial3D:
	if _mist_mat == null:
		_mist_mat = StandardMaterial3D.new()
		_mist_mat.resource_name = "shower_mist"
		_mist_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_mist_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_mist_mat.albedo_color = Color(0.85, 0.9, 0.95, 0.2)
		_mist_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		_mist_mat.disable_receive_shadows = true
	return _mist_mat


## The falling stream: a handful of drops from the head, straight down with a little spread, timed
## to reach about the floor before they die (cheap: no collision, they just fade out on schedule).
static func _make_stream() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = "Stream"
	p.amount = 24
	p.lifetime = 0.55
	p.emitting = false
	p.draw_pass_1 = _mesh()
	p.material_override = _drop_material()
	p.local_coords = true
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, -1, 0)
	pm.spread = 8.0
	pm.initial_velocity_min = 1.2
	pm.initial_velocity_max = 1.9
	pm.gravity = Vector3(0, -6.0, 0)
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.07
	pm.scale_min = 0.6
	pm.scale_max = 1.1
	p.process_material = pm
	return p


## The splash: a low burst of mist where the stream hits the floor.
static func _make_mist() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = "Mist"
	p.amount = 10
	p.lifetime = 0.3
	p.emitting = false
	p.draw_pass_1 = _mesh()
	p.material_override = _mist_material()
	p.local_coords = true
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 60.0
	pm.initial_velocity_min = 0.2
	pm.initial_velocity_max = 0.6
	pm.gravity = Vector3(0, -3.0, 0)
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.12
	pm.scale_min = 0.8
	pm.scale_max = 1.4
	p.process_material = pm
	return p


static func _make_audio() -> AudioStreamPlayer3D:
	var a := AudioStreamPlayer3D.new()
	a.name = "Water"
	a.bus = "SFX" if AudioServer.get_bus_index("SFX") >= 0 else "Master"
	a.volume_db = -14.0
	a.unit_size = 1.3
	a.max_distance = 9.0
	a.stream = _loaded_stream()
	return a


## Loaded once and shared read-only by every shower's player (playback position is per-player, not
## per-stream): a `.wav` generated by tools/gen_audio_personnel.mjs, same idiom as
## scripts/containers/med_fridge.gd's hum and scripts/database/wall_terminal.gd's fan.
static func _loaded_stream() -> AudioStreamWAV:
	if _water_stream != null or _water_load_tried:
		return _water_stream
	_water_load_tried = true
	if DisplayServer.get_name() == "headless" or not ResourceLoader.exists(WATER_CUE):
		return null
	var res = load(WATER_CUE)
	if not (res is AudioStreamWAV):
		return null
	var stream := (res as AudioStreamWAV).duplicate() as AudioStreamWAV
	var frames := stream.data.size() / ((2 if stream.format == AudioStreamWAV.FORMAT_16_BITS else 1) * (2 if stream.stereo else 1))
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = frames
	_water_stream = stream
	return stream


## Warmup hook (scripts/warmup.gd): draw the stream and the mist once, up front, so the first
## shower anyone turns on doesn't hitch on the particle materials.
static func warm(parent: Node3D) -> void:
	var stream := _make_stream()
	stream.name = "ShowerWarmStream"
	stream.one_shot = true
	parent.add_child(stream)
	stream.emitting = true
	var mist := _make_mist()
	mist.name = "ShowerWarmMist"
	mist.one_shot = true
	parent.add_child(mist)
	mist.emitting = true
	_loaded_stream()   # off the critical path: load the wav now, not on the first E press
