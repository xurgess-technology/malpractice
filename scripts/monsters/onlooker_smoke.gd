extends Node3D
## The Onlooker's smoke: the wisps it stands wreathed in, and the poof it leaves when it goes.
##
## ## The shroud and the wisps (`make_shroud`, `make_wisps`, built by onlooker_rig.gd)
## The shroud is a close, dark smoke riding the body itself, so the silhouette always sits behind a
## soft edge. The wisps are a slower smoke coming off it and climbing away, in WORLD space, so when
## it hops the last of the old wisps hang where it stood for a second or two. Together with the
## body's eroded edge (shaders/onlooker_body.gdshader) this is what makes it hard to really see: the
## outline is never clean, and there is always something dark moving round it. The eyes are left
## alone -- they are what you see first at range, and the smoke is kept below and behind them.
##
## ## The poof (`poof`, from monster.gd when it goes)
## **It no longer sinks into the floor.** When it goes -- run at it, or its mark leaves -- the body
## comes apart (the shader's dissolve) and this node is left behind in the world where it stood:
##   a burst of smoke thrown outward from the whole body, gone in about a second and a half,
##   a cloud that hangs in that spot and thins out over about five seconds,
##   and the eyes, for a quarter of a second after the rest of it has gone.
## It frees itself when the cloud is gone.
##
## **Every machine makes its own, from the same event.** monster.gd spawns it on the frame `present`
## goes from true to false, and `present` is the replicated `pr` -- so the host sees it when its
## brain decides, and every client sees it when that snapshot lands. Nothing extra on the wire.
##
## It stays SILENT like the rest of it (monster.gd `_update_sound`): the poof is purely visual.
##
## ## Cost
## Particle counts are small and fixed (SHROUD, WISPS, BURST, LINGER), the materials are built once and
## shared (`_shared`), and nothing here runs per frame but the poof's own short fade. The pocket
## spaces are where frame time is tightest, and this is there to be looked at, not to fill a room.

const SmokeShader := preload("res://shaders/onlooker_smoke.gdshader")

## Particles alive at once in the wisps round the body.
const WISPS := 18
const WISP_LIFE := 2.8
## The shroud that rides the body itself, blurring its edge.
const SHROUD := 20
const SHROUD_LIFE := 2.2
## The burst when it goes, and the cloud it leaves.
const BURST := 32
const BURST_LIFE := 1.5
const LINGER := 14
const LINGER_LIFE := 5.0
## How long the eyes outlast the body, seconds.
const EYES_LINGER := 0.28
## When the poof node frees itself.
const POOF_SECONDS := LINGER_LIFE * 1.3 + 0.2

static var _shared: Dictionary = {}

var _t := 0.0
var _eyes: Array[MeshInstance3D] = []
var _eye_mat: StandardMaterial3D = null
var _eye_energy := 0.0


## The materials and meshes every puff shares. Built once, the first time anything asks.
static func _res(key: String):
	if _shared.is_empty():
		var sm := ShaderMaterial.new()
		sm.shader = SmokeShader
		_shared["draw_mat"] = sm
		var quad := QuadMesh.new()
		quad.size = Vector2(1.0, 1.0)
		quad.material = sm
		_shared["quad"] = quad
		# The shroud's own copy: denser, and fading into what is behind it over a much shorter
		# distance -- it sits right against the body, and at the usual half metre the body itself
		# would fade it out everywhere it overlaps.
		var shm := ShaderMaterial.new()
		shm.shader = SmokeShader
		shm.set_shader_parameter(&"density", 1.0)
		shm.set_shader_parameter(&"soft_depth", 0.12)
		var squad := QuadMesh.new()
		squad.size = Vector2(1.0, 1.0)
		squad.material = shm
		_shared["shroud_quad"] = squad
		# The poof's puffs are drawn bigger: a cloud is a few big soft billows, not many small ones.
		# Its own material too: thinner and more torn, so a dozen of them overlapping make a cloud
		# you can half see through rather than a black ball.
		var cm := ShaderMaterial.new()
		cm.shader = SmokeShader
		cm.set_shader_parameter(&"density", 0.5)
		cm.set_shader_parameter(&"ragged", 1.1)
		var bquad := QuadMesh.new()
		bquad.size = Vector2(1.8, 1.8)
		bquad.material = cm
		_shared["big_quad"] = bquad

		# The fade every puff shares: in quickly, out slowly.
		var ramp := Gradient.new()
		ramp.offsets = PackedFloat32Array([0.0, 0.18, 0.6, 1.0])
		ramp.colors = PackedColorArray([Color(1, 1, 1, 0.0), Color(1, 1, 1, 0.9), Color(1, 1, 1, 0.55), Color(1, 1, 1, 0.0)])
		var ramp_tex := GradientTexture1D.new()
		ramp_tex.gradient = ramp
		var grow := Curve.new()
		grow.add_point(Vector2(0.0, 0.45))
		grow.add_point(Vector2(1.0, 1.0))
		var grow_tex := CurveTexture.new()
		grow_tex.curve = grow

		# The wisps: out of the whole body, drifting up and a little away.
		var w := ParticleProcessMaterial.new()
		w.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
		w.emission_box_extents = Vector3(0.28, 1.05, 0.2)
		w.direction = Vector3(0.0, 1.0, 0.0)
		w.spread = 70.0
		w.initial_velocity_min = 0.08
		w.initial_velocity_max = 0.3
		w.gravity = Vector3(0.0, 0.12, 0.0)
		w.damping_min = 0.05
		w.damping_max = 0.15
		w.angle_min = -180.0
		w.angle_max = 180.0
		w.angular_velocity_min = -18.0
		w.angular_velocity_max = 18.0
		w.scale_min = 1.0
		w.scale_max = 1.6
		w.scale_curve = grow_tex
		w.color_ramp = ramp_tex
		_shared["wisp_pm"] = w

		# The shroud: dense, slow, and riding the body (local coords), so the silhouette is always
		# behind a soft dark edge wherever it stands. Darker than the wisps and shorter-lived.
		var sh := ParticleProcessMaterial.new()
		sh.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
		sh.emission_box_extents = Vector3(0.34, 1.0, 0.2)
		sh.direction = Vector3(0.0, 1.0, 0.0)
		sh.spread = 90.0
		sh.initial_velocity_min = 0.03
		sh.initial_velocity_max = 0.12
		sh.gravity = Vector3(0.0, 0.05, 0.0)
		sh.angle_min = -180.0
		sh.angle_max = 180.0
		sh.angular_velocity_min = -12.0
		sh.angular_velocity_max = 12.0
		sh.scale_min = 0.85
		sh.scale_max = 1.3
		sh.scale_curve = grow_tex
		sh.color_ramp = ramp_tex
		_shared["shroud_pm"] = sh

		# The burst: thrown out of the whole body at once, fast, then braking hard.
		var b := ParticleProcessMaterial.new()
		b.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
		b.emission_box_extents = Vector3(0.3, 1.15, 0.22)
		b.direction = Vector3(0.0, 0.25, 0.0)
		b.spread = 180.0
		b.initial_velocity_min = 2.4
		b.initial_velocity_max = 4.8
		b.damping_min = 3.0
		b.damping_max = 4.5
		b.gravity = Vector3(0.0, 0.25, 0.0)
		b.angle_min = -180.0
		b.angle_max = 180.0
		b.angular_velocity_min = -60.0
		b.angular_velocity_max = 60.0
		b.scale_min = 1.0
		b.scale_max = 1.6
		var bgrow := Curve.new()
		bgrow.add_point(Vector2(0.0, 0.35))
		bgrow.add_point(Vector2(0.35, 0.85))
		bgrow.add_point(Vector2(1.0, 1.0))
		var bgrow_tex := CurveTexture.new()
		bgrow_tex.curve = bgrow
		b.scale_curve = bgrow_tex
		var bramp := Gradient.new()
		bramp.offsets = PackedFloat32Array([0.0, 0.06, 0.45, 1.0])
		bramp.colors = PackedColorArray([Color(1, 1, 1, 0.0), Color(1, 1, 1, 1.0), Color(1, 1, 1, 0.45), Color(1, 1, 1, 0.0)])
		var bramp_tex := GradientTexture1D.new()
		bramp_tex.gradient = bramp
		b.color_ramp = bramp_tex
		_shared["burst_pm"] = b

		# The cloud it leaves: big, slow, hanging where it stood, thinning out.
		var l := ParticleProcessMaterial.new()
		l.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
		l.emission_box_extents = Vector3(0.8, 1.1, 0.8)
		l.direction = Vector3(0.0, 1.0, 0.0)
		l.spread = 180.0
		l.initial_velocity_min = 0.1
		l.initial_velocity_max = 0.45
		l.damping_min = 0.1
		l.damping_max = 0.2
		l.gravity = Vector3(0.0, 0.08, 0.0)
		l.angle_min = -180.0
		l.angle_max = 180.0
		l.angular_velocity_min = -10.0
		l.angular_velocity_max = 10.0
		l.scale_min = 1.7
		l.scale_max = 2.5
		var lgrow := Curve.new()
		lgrow.add_point(Vector2(0.0, 0.6))
		lgrow.add_point(Vector2(1.0, 1.0))
		var lgrow_tex := CurveTexture.new()
		lgrow_tex.curve = lgrow
		l.scale_curve = lgrow_tex
		var lramp := Gradient.new()
		lramp.offsets = PackedFloat32Array([0.0, 0.08, 0.35, 1.0])
		lramp.colors = PackedColorArray([Color(1, 1, 1, 0.0), Color(1, 1, 1, 0.8), Color(1, 1, 1, 0.5), Color(1, 1, 1, 0.0)])
		var lramp_tex := GradientTexture1D.new()
		lramp_tex.gradient = lramp
		l.color_ramp = lramp_tex
		l.lifetime_randomness = 0.3
		_shared["linger_pm"] = l
	return _shared[key]


static func _emitter(pm: ParticleProcessMaterial, amount: int, life: float) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = life
	p.local_coords = false
	p.process_material = pm
	p.draw_pass_1 = _res("quad")
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_aabb = AABB(Vector3(-3.0, -1.5, -3.0), Vector3(6.0, 5.5, 6.0))
	return p


## The wisps round the body, for the rig. Centred on the trunk: add it at about half its height.
static func make_wisps() -> GPUParticles3D:
	var p := _emitter(_res("wisp_pm"), WISPS, WISP_LIFE)
	p.name = "Wisps"
	p.randomness = 0.4
	return p


## The shroud hugging the body, for the rig: local coords, so it goes where the body goes.
static func make_shroud() -> GPUParticles3D:
	var p := _emitter(_res("shroud_pm"), SHROUD, SHROUD_LIFE)
	p.name = "Shroud"
	p.draw_pass_1 = _res("shroud_quad")
	p.local_coords = true
	p.randomness = 0.3
	p.preprocess = SHROUD_LIFE
	return p


## It went: leave the poof in `parent` (world space) where it stood. `eye_xf` is where its eyes
## were (the head's global transform), `eye_gap` how far apart, and `energy` how bright they were.
static func poof(parent: Node, at: Vector3, yaw: float, eye_xf: Transform3D, eye_gap: float, eye_r: float,
		eye_color: Color, energy: float) -> Node3D:
	var n: Node3D = (load("res://scripts/monsters/onlooker_smoke.gd") as GDScript).new()
	n.name = "OnlookerPoof"
	parent.add_child(n)
	n.global_position = at
	n.rotation.y = yaw
	n._build(eye_xf, eye_gap, eye_r, eye_color, energy)
	return n


func _build(eye_xf: Transform3D, eye_gap: float, eye_r: float, eye_color: Color, energy: float) -> void:
	var burst := _emitter(_res("burst_pm"), BURST, BURST_LIFE)
	burst.name = "Burst"
	burst.draw_pass_1 = _res("big_quad")
	burst.one_shot = true
	burst.explosiveness = 0.92
	burst.position = Vector3(0.0, 1.3, 0.0)
	add_child(burst)
	burst.emitting = true
	var cloud := _emitter(_res("linger_pm"), LINGER, LINGER_LIFE)
	cloud.name = "Cloud"
	cloud.draw_pass_1 = _res("big_quad")
	cloud.one_shot = true
	cloud.explosiveness = 0.8
	cloud.position = Vector3(0.0, 1.1, 0.0)
	add_child(cloud)
	cloud.emitting = true
	if energy > 0.0:
		_eye_mat = StandardMaterial3D.new()
		_eye_mat.albedo_color = eye_color
		_eye_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_eye_mat.emission_enabled = true
		_eye_mat.emission = eye_color
		_eye_mat.emission_energy_multiplier = energy
		_eye_energy = energy
		var sphere := SphereMesh.new()
		sphere.radius = eye_r
		sphere.height = eye_r * 2.0
		sphere.radial_segments = 10
		sphere.rings = 6
		for side in [-1.0, 1.0]:
			var e := MeshInstance3D.new()
			e.mesh = sphere
			e.material_override = _eye_mat
			e.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(e)
			e.global_transform = eye_xf * Transform3D(Basis(), Vector3(side * eye_gap * 0.5, 0.0, -0.088))
			_eyes.append(e)


func _process(delta: float) -> void:
	_t += delta
	if not _eyes.is_empty():
		var k := 1.0 - clampf(_t / EYES_LINGER, 0.0, 1.0)
		if k <= 0.0:
			for e in _eyes:
				e.queue_free()
			_eyes.clear()
		else:
			_eye_mat.emission_energy_multiplier = _eye_energy * k * k
			for e in _eyes:
				e.scale = Vector3.ONE * lerpf(0.4, 1.0, k)
	if _t >= POOF_SECONDS:
		queue_free()
