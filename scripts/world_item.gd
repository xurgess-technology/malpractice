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
## bob and the glow's breathing are local cosmetics on every machine.

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

const GLOW_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back, shadows_disabled;

uniform vec3 tint : source_color = vec3(0.72, 0.88, 0.82);
uniform float amount = 1.0;

void vertex() {
	VERTEX += NORMAL * 0.006;
}

void fragment() {
	float facing = clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
	float edge = pow(1.0 - facing, 2.2);
	ALBEDO = tint * (0.085 + 0.26 * edge) * amount;
}
"""
## Same spirit as AimHighlight.MAX_MESHES: glow the big readable shapes, not every screw.
const GLOW_MAX_MESHES := 4
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

static var _glow_mat: ShaderMaterial = null
static var _pulse_frame: int = -1


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


static func glow_material() -> ShaderMaterial:
	if _glow_mat == null:
		var sh := Shader.new()
		sh.code = GLOW_SHADER
		_glow_mat = ShaderMaterial.new()
		_glow_mat.shader = sh
	return _glow_mat


## Warmup hook (scripts/warmup.gd): compile the glow shader once, up front, so the first dropped
## item of a session doesn't hitch.
static func warm_glow(parent: Node3D) -> void:
	var probe := MeshInstance3D.new()
	probe.name = "HoverGlowWarm"
	probe.mesh = BoxMesh.new()
	probe.material_override = glow_material()
	parent.add_child(probe)


## A copy of the model's biggest meshes, added as children of them (so they inherit the transform
## for free), drawn additive and unlit with a rim falloff: the same trick as the aim highlight, a
## touch stronger and always on. One shared material, so the breathing costs one uniform a frame.
func _set_glow(on: bool) -> void:
	if _visual == null:
		return
	var parts: Array = []
	if _visual is MeshInstance3D:
		parts.append(_visual)
	parts.append_array(_visual.find_children("*", "MeshInstance3D", true, false))
	if not on:
		for mi in parts:
			if mi.has_node(_GLOW_NAME):
				mi.get_node(_GLOW_NAME).queue_free()
		return
	parts.sort_custom(func(a, b): return _aabb_vol(a) > _aabb_vol(b))
	for i in mini(parts.size(), GLOW_MAX_MESHES):
		var mi: MeshInstance3D = parts[i]
		if mi.mesh == null or mi.has_node(_GLOW_NAME):
			continue
		var shell := MeshInstance3D.new()
		shell.name = _GLOW_NAME
		shell.mesh = mi.mesh
		shell.material_override = glow_material()
		shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.add_child(shell)


static func _aabb_vol(mi: MeshInstance3D) -> float:
	if mi.mesh == null:
		return 0.0
	var s := mi.mesh.get_aabb().size * mi.scale
	return s.x * s.y + s.y * s.z + s.x * s.z


## Local cosmetics on every machine: the model drifts up and down inside the body (the body itself
## stays exactly where the host put it, so nothing about the bob can desync), and the shared glow
## breathes once for the whole world.
func _process(_delta: float) -> void:
	if _visual == null or not hovering:
		return
	var t := float(Time.get_ticks_msec()) * 0.001
	_visual.position.y = sin((t + float(item_id) * 0.7) * TAU / HOVER_BOB_SECONDS) * HOVER_BOB
	var f := Engine.get_process_frames()
	if _pulse_frame != f:
		_pulse_frame = f
		glow_material().set_shader_parameter("amount", 0.82 + 0.18 * sin(t * 1.7))


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
