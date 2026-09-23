class_name WorldItem
extends RigidBody3D
## A stack of one item kind lying somewhere in the world: inside a container, or loose on a
## surface. Picking it up removes it and fills a hand slot.
##
## The host owns items. When one is dropped the host lets real physics tumble it until it
## settles; clients never simulate it, they glide toward the host's transform from the
## snapshot. That keeps drops looking physical without anything desyncing.
##
## HOVER DROP (2026-09-22): a stack that has been dropped doesn't stay lying on the floor. The
## moment its tumble ends the host lifts it upright into a hover a hand's width off the ground and
## it picks up a soft glow, so loose loot reads as "take me" from across a dark ward. Two hovering
## stacks own a visible ball of space each, so they must not overlap: when one settles where
## another already hovers the host hops it (a little arc) to the nearest free spot. The hop, the
## hover height and the free-spot choice are the host's (replicated as ordinary transforms); the
## bob and the glow's pulse are local cosmetics, run off the replicated world clock so they look
## the same on every machine.
##
## GLOW BALL (2026-09-22): that glow is a ball -- one soft additive sphere around the stack, in the
## colour its kind wears (ItemModels.glow_key), breathing once every PULSE_SECONDS. See ORB_SHADER.

const FogRingScript := preload("res://scripts/level/fog_ring.gd")   # SWEEP 4A HOOK (fog lot, chunk 2)

enum State { IN_CONTAINER, LOOSE }

const SETTLE_MAX := 3.0

## HOVER DROP: floor to the bottom of a hovering stack.
const HOVER_HEIGHT := 0.32
## How far it drifts up and down, and how long one breath takes.
const HOVER_BOB := 0.035
const HOVER_BOB_SECONDS := 2.8
## Standing up into the hover where it landed, versus hopping aside to a free spot.
const RISE_SECONDS := 0.28
const HOP_SECONDS := 0.45

## GLOW BALL (2026-09-22): the hover glow used to be copies of the model's own meshes drawn with a
## rim falloff -- up to four extra draws of a real model per stack, and it only ever reshaped the
## silhouette. It is now ONE small sphere per stack: a soft ball of light the item floats inside, in
## the kind's palette colour (ItemModels.glow_key), so a glance across a dark ward says both "there
## is something on the floor" and "it is a surgical supply / loot / somebody's eye".
##
## Additive, unlit, depth-tested but never depth-written, and brightest through the middle, falling
## to exactly zero at the silhouette -- so it has no edge of its own, and where the ball cuts the
## floor or a wall there is nothing to see.
const ORB_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back, shadows_disabled;

uniform vec3 tint : source_color = vec3(0.80, 0.86, 0.98);
uniform float strength = 0.09;
uniform float pulse = 1.0;

void fragment() {
	float facing = clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
	// Steep on purpose. A gentler curve fills the whole disc evenly and the environment's bloom
	// turns that into a milky bubble you can read a newspaper by; this keeps the light gathered
	// around the item and gone by the time it reaches the silhouette.
	float ball = pow(facing, 6.0);
	ALBEDO = tint * ball * strength * pulse;
}
"""
## How bright the ball is at its middle, per palette colour. Small numbers: the world environment
## blooms anything additive, so this is roughly a third of what looks right with the glow off.
## Gold loot and the plain white default sit lower -- those read hotter against a dark corridor
## than teal or violet do. Tune by eye.
const ORB_STRENGTH := {
	"teal": 0.095, "gold": 0.075, "organ": 0.09,
	"pharma": 0.095, "vessel": 0.09, "plain": 0.07,
}
## One slow breath, in seconds. Deliberately twice HOVER_BOB_SECONDS: the ball brightens and dims
## on exactly half the rhythm the stack floats up and down on, so the two never beat against each
## other. Tune by eye.
const PULSE_SECONDS := 5.6
## How far the brightness swings: 0.72 to 1.0 of ORB_STRENGTH.
const PULSE_DEPTH := 0.14
const _GLOW_NAME := "HoverGlowFx"

var item_id: int = 0
var kind: String = ""
var count: int = 1
var state: int = State.LOOSE
var container_id: String = ""
var slot: int = 0
var anchor: int = -1
## Sell value of the whole stack in dollars (loot only; 0 for everything else). Rolled by the
## loot spawner, carried into a hand slot as "v" and back out when dropped.
var value: int = 0
## GRAFTING: world_time a spoiling item was harvested, -1 for everything else. Carried into a hand
## slot as "bt" and back out when dropped; the furnace pays game.vats.eye_value() for an eye.
var bt: float = -1000000.0   # "no spoil clock" (a real one can be negative early in a run)
## GRAFTING part one: a small string that travels with the stack (into a hand slot as "x" and back):
## an eye's owner ("Zach"), or what a specimen vat holds (Eyes.pack). "" for everything else.
var x: String = ""

var _visual: Node3D
var _shape: CollisionShape3D
var _settle: float = 0.0
var _target: Transform3D
var _has_target := false

## HOVER DROP: floating above the floor with a glow (host decides, clients follow the snapshot).
var hovering := false
var _hop_t := -1.0
var _hop_len := RISE_SECONDS
var _hop_arc := 0.0
var _hop_from := Vector3.ZERO
var _hop_to := Vector3.ZERO
var _hop_basis_from := Basis()
var _hop_basis_to := Basis()

static var _orb_shader: Shader = null
static var _orb_mats := {}            # palette key -> ShaderMaterial (shared by every stack of that colour)
static var _orb_mesh: SphereMesh = null
static var _pulse_frame: int = -1
static var _pulse_t: float = 0.0      # the shared clock the bob and the pulse both run on


static func new_item(id: int, item_kind: String, item_count: int) -> WorldItem:
	var it := WorldItem.new()
	it.item_id = id
	it.kind = item_kind
	it.count = maxi(1, item_count)
	it.name = "Item_%d_%s" % [id, item_kind]
	it._build()
	return it


func _build() -> void:
	collision_layer = C.L_PICKUP
	collision_mask = C.L_WORLD
	freeze = true
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	continuous_cd = true
	mass = 3.0 if Items.is_bulky(kind) else 0.4
	gravity_scale = 1.0
	var mat := PhysicsMaterial.new()
	mat.friction = 0.9
	mat.bounce = 0.15
	physics_material_override = mat
	add_to_group("interactable")
	add_to_group("world_item")
	set_meta("interact_id", "it_%d" % item_id)

	_shape = CollisionShape3D.new()
	_shape.shape = BoxShape3D.new()
	add_child(_shape)
	_rebuild_visual()


func _rebuild_visual() -> void:
	if _visual != null:
		_visual.queue_free()
	_visual = ItemModels.make_tinted(kind, count)
	add_child(_visual)
	_apply_shape()
	if hovering:
		_set_glow(true)


## The body's one shape does two jobs. While a stack is tumbling it is a box roughly its own size,
## so it lands like the object it is. Once it is hovering it becomes the ball of space it owns: a
## sphere around the whole model, comfortably bigger than the box, so a look-ray finds it from any
## angle (the reason it exists: aiming at a floating scalpel used to be a needle-threading exercise).
func _apply_shape() -> void:
	var fp := ItemModels.footprint(kind)
	if hovering:
		var sphere := _shape.shape as SphereShape3D
		if sphere == null:
			sphere = SphereShape3D.new()
			_shape.shape = sphere
		sphere.radius = clampf(0.5 * maxf(maxf(fp.x, fp.y), fp.z) + 0.13, 0.28, 0.5)
		_shape.position.y = maxf(fp.y, 0.1) * 0.5
		return
	var box := _shape.shape as BoxShape3D
	if box == null:
		box = BoxShape3D.new()
		_shape.shape = box
	# A slightly generous box so the aim ray finds small things like vials easily.
	box.size = Vector3(maxf(fp.x, 0.12), maxf(fp.y, 0.08), maxf(fp.z, 0.12))
	_shape.position.y = maxf(fp.y, 0.08) * 0.5


func set_count(n: int) -> void:
	if n == count:
		return
	count = maxi(1, n)
	_rebuild_visual()


func _game() -> Node:
	return get_tree().get_first_node_in_group("game")


# ---------------------------------------------------------------------------
# HOVER DROP: the hover, the glow and the hop to a free spot

## Host: the tumble is over. Stand the stack upright in its hover; if another hovering stack
## already owns this patch of floor, hop over to the nearest free one instead of overlapping it.
func begin_hover() -> void:
	var g := _game()
	var want := global_position
	if g != null and g.has_method("hover_rest_spot"):
		want = g.hover_rest_spot(self, global_position)
	else:
		want.y += HOVER_HEIGHT
	var aside := Vector2(want.x - global_position.x, want.z - global_position.z).length()
	_hop_from = global_position
	_hop_to = want
	_hop_arc = clampf(aside * 0.4, 0.0, 0.4)
	_hop_len = HOP_SECONDS if aside > 0.05 else RISE_SECONDS
	_hop_t = 0.0
	_hop_basis_from = global_basis.orthonormalized()
	_hop_basis_to = Basis(Vector3.UP, _hop_basis_from.get_euler().y)
	_set_hovering(true)
	if OS.is_stdout_verbose():
		print("[hover] %d %s settled %v -> %v (aside %.2f)" % [item_id, kind, _hop_from, _hop_to, aside])


## Host: run the rise (or the hop aside) a frame at a time. Frozen throughout, so this is the only
## thing moving it and clients just see the transform travel.
func _step_hop(delta: float) -> void:
	_hop_t += delta
	var k := clampf(_hop_t / _hop_len, 0.0, 1.0)
	var p := _hop_from.lerp(_hop_to, k)
	p.y += sin(k * PI) * _hop_arc
	global_position = p
	global_basis = _hop_basis_from.slerp(_hop_basis_to, k)
	if k >= 1.0:
		_hop_t = -1.0


## Where this stack hovers, or is on its way to hovering: the spot it reserves against other drops.
func hover_anchor() -> Vector3:
	return _hop_to if _hop_t >= 0.0 else global_position


func _set_hovering(on: bool) -> void:
	if hovering == on:
		return
	hovering = on
	if not on:
		_hop_t = -1.0
		if _visual != null:
			_visual.position.y = 0.0
	_apply_shape()
	_set_glow(on)


## The one sphere every orb in the world draws. Coarse on purpose: a blob with no edge does not
## need silhouette detail, and this mesh is potentially on screen dozens of times.
static func orb_mesh() -> SphereMesh:
	if _orb_mesh == null:
		_orb_mesh = SphereMesh.new()
		_orb_mesh.radius = 1.0
		_orb_mesh.height = 2.0
		_orb_mesh.radial_segments = 20
		_orb_mesh.rings = 10
	return _orb_mesh


## One material per palette colour, shared by every stack of that colour: six at most, so a floor
## full of loot is a handful of materials and the pulse is a handful of uniform writes a frame.
static func orb_material(key: String) -> ShaderMaterial:
	if _orb_mats.has(key):
		return _orb_mats[key]
	if _orb_shader == null:
		_orb_shader = Shader.new()
		_orb_shader.code = ORB_SHADER
	var m := ShaderMaterial.new()
	m.shader = _orb_shader
	var col: Color = ItemModels.TINT_COLORS[key]
	m.set_shader_parameter("tint", Vector3(col.r, col.g, col.b))
	m.set_shader_parameter("strength", float(ORB_STRENGTH[key]))
	_orb_mats[key] = m
	return m


## Warmup hook (scripts/warmup.gd): draw one orb of every colour once, up front, so the first
## dropped item of a session doesn't hitch on a shader compile.
static func warm_glow(parent: Node3D) -> void:
	for key in ItemModels.TINT_COLORS.keys():
		var probe := MeshInstance3D.new()
		probe.name = "HoverGlowWarm_" + String(key)
		probe.mesh = orb_mesh()
		probe.material_override = orb_material(key)
		probe.scale = Vector3.ONE * 0.05
		parent.add_child(probe)


## GLOW BALL: one soft sphere of light around the model, in the kind's colour. It hangs off the
## visual, so it rides the hover bob with the stack, and it is sized to the model's footprint: a
## bone saw owns a bigger ball than a vial. One draw per dropped stack.
func _set_glow(on: bool) -> void:
	if _visual == null:
		return
	var orb := _visual.get_node_or_null(_GLOW_NAME)
	if not on:
		if orb != null:
			orb.queue_free()
		return
	if orb != null:
		return
	var fp := ItemModels.footprint(kind)
	var mi := MeshInstance3D.new()
	mi.name = _GLOW_NAME
	mi.mesh = orb_mesh()
	mi.material_override = orb_material(ItemModels.glow_key(kind))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Centred on the model, a comfortable margin wider than it, and never so big it lights a room.
	mi.scale = Vector3.ONE * clampf(0.5 * maxf(maxf(fp.x, fp.y), fp.z) + 0.11, 0.22, 0.38)
	mi.position.y = maxf(fp.y, 0.1) * 0.5
	_visual.add_child(mi)


## Local cosmetics on every machine: the model drifts up and down inside the body (the body itself
## stays exactly where the host put it, so nothing about the bob can desync), and every orb in the
## world breathes together.
##
## Both run off the host's `world_time`, which every machine already has from the snapshot, so the
## bob and the pulse are at the same point of their cycle on your screen and your teammate's --
## not each machine's own uptime. The first hovering stack of a frame reads the clock and writes
## the pulse; the rest reuse it, so a floor full of loot costs one lookup and a few uniforms.
func _process(_delta: float) -> void:
	if _visual == null or not hovering:
		return
	var f := Engine.get_process_frames()
	if _pulse_frame != f:
		_pulse_frame = f
		var g := _game()
		_pulse_t = float(g.world_time) if g != null else float(Time.get_ticks_msec()) * 0.001
		var p := (1.0 - PULSE_DEPTH) + PULSE_DEPTH * sin(_pulse_t * TAU / PULSE_SECONDS)
		for m in _orb_mats.values():
			(m as ShaderMaterial).set_shader_parameter("pulse", p)
	_visual.position.y = sin((_pulse_t + float(item_id) * 0.7) * TAU / HOVER_BOB_SECONDS) * HOVER_BOB


# ---------------------------------------------------------------------------

## Put the stack somewhere at rest (container slot, anchor). No physics.
func place(xf: Transform3D, new_state: int) -> void:
	state = new_state
	_set_hovering(false)
	freeze = true
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	global_transform = xf
	_target = xf
	_has_target = true


## Host only: let it fall with real physics from a hand, then settle.
func toss(from: Transform3D, velocity: Vector3) -> void:
	state = State.LOOSE
	container_id = ""
	anchor = -1
	_set_hovering(false)   # HOVER DROP: box shape and no glow while it is in the air
	global_transform = from
	freeze = false
	sleeping = false
	linear_velocity = velocity
	angular_velocity = Vector3(randf_range(-6, 6), randf_range(-6, 6), randf_range(-6, 6))
	_settle = SETTLE_MAX


var _container_node: Node = null


## The container this stack sits in, cached. Drawer slots move while a drawer slides,
## so items inside follow the slot every frame instead of trusting the snapshot.
func _container() -> Node:
	if _container_node != null and is_instance_valid(_container_node):
		return _container_node
	var g := _game()
	_container_node = g.find_interactable(container_id) if g != null and container_id != "" else null
	return _container_node


func _physics_process(delta: float) -> void:
	if state == State.IN_CONTAINER:
		var ct := _container()
		if ct != null and ct.has_method("slot_transform"):
			global_transform = ct.slot_transform(slot)
		return
	var g := _game()
	if g != null and g.is_host():
		if _hop_t >= 0.0:
			_step_hop(delta)   # HOVER DROP: rising into the hover, or hopping aside to a free spot
			return
		if not freeze:
			# SWEEP 4A HOOK (pharmacy, chunk 3): a thrown pill checks for a mid-air hit every
			# physics frame while it flies. A hit consumes it before it ever settles as a pickup.
			if kind == "placebo_pills" and get_meta("pill_thrown", false) and g.has_method("pill_check_hit") and g.pill_check_hit(self):
				g.world_items.erase(item_id)
				queue_free()
				return
			_settle -= delta
			if sleeping or _settle <= 0.0 or (linear_velocity.length() < 0.03 and _settle < SETTLE_MAX - 0.4):
				# POCKETS 2 phase 4: a scattered handful of quarters never settles as a pickup. It
				# bursts where it lands, which is the whole point of throwing it: the noise happens
				# over there and not where you are standing.
				if get_meta("quarters_thrown", false) and g.has_method("quarters_scatter"):
					g.quarters_scatter(global_position)
					g.world_items.erase(item_id)
					queue_free()
					return
				freeze = true
				linear_velocity = Vector3.ZERO
				angular_velocity = Vector3.ZERO
				# SWEEP 4A HOOK (fog lot, chunk 2): anything that settled in the lot's fog ring
				# comes back out at the edge instead of staying lost in the blind.
				if FogRingScript.on_lot(global_position, g.level_info):
					global_position = FogRingScript.pull_from_fog(global_position, g.level_info)
				begin_hover()   # HOVER DROP: up off the floor, glowing, clear of everything else
			elif global_position.y < -5.0:
				# Fell through something: put it back on the floor near where it went in.
				global_position = Vector3(global_position.x, 0.2, global_position.z)
				freeze = true
				begin_hover()
		return
	if _has_target:
		var k := clampf(delta * 14.0, 0.0, 1.0)
		if global_position.distance_squared_to(_target.origin) > 36.0:
			k = 1.0   # POCKETS HOOK: moved through a seam; never slide across the world
		global_position = global_position.lerp(_target.origin, k)
		global_basis = global_basis.slerp(_target.basis.orthonormalized(), k)


# ---------------------------------------------------------------------------
# interaction

func interact_prompt(player) -> String:
	if state == State.IN_CONTAINER:
		var g := _game()
		var ct = g.find_interactable(container_id) if g != null else null
		if ct != null and ct.has_method("is_open") and not ct.is_open():
			return ""
	# ROCKET BOOTS: worn, not carried, so full hands don't matter.
	if Items.is_worn(kind):
		if player != null and bool(player.get("boots")):
			return "!Already wearing rocket boots"
		return "Put on %s" % Items.display_name(kind)
	var label := Items.stack_label(kind, count)
	var g2 := _game()
	if kind == "specimen_vat" and g2 != null and g2.get("vats") != null:
		return g2.vats.item_prompt(player, self)   # GRAFTING: put an eye in, or take the vat
	if g2 != null and g2.get("vats") != null and Eyes.is_eye(kind):
		label = Eyes.label(kind, x)
		label += " ($%d, %s)" % [g2.vats.eye_value({"v": value, "bt": bt}), Eyes.condition(g2.vats.eye_factor(self))]
	elif value > 0:
		label += " ($%d)" % value
	if player != null and player.has_method("can_take") and not player.can_take(kind):
		return "!Needs two free hands" if Items.is_bulky(kind) else "!Hands full"
	return "Take %s" % label


func interact_hold() -> float:
	return 0.0


func interact(player) -> void:
	var g := _game()
	if g != null:
		g.pickup_item(player, self)


# ---------------------------------------------------------------------------
# networking

## Quantized (5 mm, rotation components to 0.002) so a resting stack never changes between
## snapshots and costs nothing after the client has it. Items inside a container follow the
## slot on every machine, so their transform is not sent at all.
func report() -> Dictionary:
	var d := {"id": item_id, "k": kind, "n": count, "st": state, "ct": container_id, "sl": slot}
	if value > 0:
		d["v"] = value
	if bt > -100000.0:
		d["bt"] = snappedf(bt, 0.5)   # GRAFTING: the eye spoil clock
	if x != "":
		d["x"] = x   # GRAFTING part one
	if state != State.IN_CONTAINER:
		if hovering:
			d["h"] = 1   # HOVER DROP: one byte so a client glows it too
		var q := global_basis.get_rotation_quaternion()
		d["p"] = global_position.snappedf(0.005)
		d["q"] = Quaternion(snappedf(q.x, 0.002), snappedf(q.y, 0.002), snappedf(q.z, 0.002), snappedf(q.w, 0.002))
	return d


func apply_remote(s: Dictionary) -> void:
	state = int(s.st)
	if container_id != String(s.ct):
		_container_node = null
	container_id = String(s.ct)
	slot = int(s.sl)
	value = int(s.get("v", 0))
	bt = float(s.get("bt", -1000000.0))   # GRAFTING: the eye spoil clock
	x = String(s.get("x", ""))   # GRAFTING part one
	set_count(int(s.n))
	_set_hovering(int(s.get("h", 0)) == 1)   # HOVER DROP
	if not s.has("p"):
		return   # in a container: _physics_process follows the slot
	var q := (s.get("q", Quaternion.IDENTITY) as Quaternion)
	q = q.normalized() if q.length_squared() > 0.0001 else Quaternion.IDENTITY
	_target = Transform3D(Basis(q), s.p as Vector3)
	if not _has_target:
		global_transform = _target
	_has_target = true
