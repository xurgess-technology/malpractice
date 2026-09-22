extends Node3D
## One door in a doorway (a DoorPlan entry, scripts/level/door_plan.gd): its leaves or panels as
## AnimatableBody3Ds on C.L_WORLD (they block movement, sight rays and the flashlight's shadow like
## a wall), a frame, an occluder while closed, and for a wing gate the lock lamp.
##
## `amount` is how far it is open: hinged and double doors -1..1 (the sign is the side: + swings out
## of the face, - folds into the tunnel; 1 = 90 degrees), automatic swing doors 0..1 (into the
## tunnel), sliding doors 0..1. The game's Doors system (scripts/doors/doors.gd) sets `target` and
## `speed` and steps every moving door; nothing here decides anything by itself.
##
## Local frame: origin in the door plane at the middle of the doorway on the floor, +Z out of the
## face (the plan's `n`), +X along the doorway, +Y up.

const Plan := preload("res://scripts/level/door_plan.gd")
const Models := preload("res://scripts/doors/door_models.gd")

## Past this amount a door is open enough to walk through: its leaves keep colliding (a swung-open
## leaf stands more than a metre into the room, and anyone walking into it must be stopped by it),
## but the collider is pulled back from the hinge by OPEN_INSET so the doorway itself stays clear.
const OPEN_PASS := 0.9
## How far the open leaf's collider starts out from the hinge, metres. The leaf's end would
## otherwise sit in the doorway's mouth with its cap facing anyone coming through, and stop a body
## cutting the corner dead; past this it is out in the room, where a body slides along its face.
const OPEN_INSET := 0.25
const HALT_MASK_OPEN := C.L_PLAYER
const HALT_MASK_CLOSE := C.L_PLAYER | C.L_PICKUP

var data: Dictionary = {}
var door_id := ""
var kind := ""
## Width of the doorway, metres.
var width := 1.5
var amount := 0.0
var target := 0.0
## Amount per second toward the target.
var speed := 1.8
var locked := false
## Automatic swing doors: which way the pair opens this time (-1 into the tunnel, +1 out of the face).
var swing := -1
## Whoever set the door moving (a bot pulling it toward itself is not in its way).
var opener: Node = null
var max_out := 90.0
var max_in := 90.0
## Local X of the hinge of each leaf, and the leaf's closed direction (+1 / -1 along X).
var leaf_bodies: Array = []
var leaf_hinge: Array = []
var leaf_dir: Array = []
var leaf_len: Array = []
## Each leaf's shut collider (the whole leaf) and its open one (pulled back from the hinge), as
## [shape, local position] pairs. The halt check always sweeps with the shut one.
var leaf_shut_shape: Array = []
var leaf_shut_pos: Array = []
var leaf_open_shape: Array = []
var leaf_open_pos: Array = []
var _leaf_inset := false
var occluder: OccluderInstance3D = null
var lamp: MeshInstance3D = null
var lamp_state := ""
## World-space centre of the doorway at chest height, for sensors and sight checks.
var centre := Vector3.ZERO
var normal := Vector3.FORWARD
var along := Vector3.RIGHT
## Host bookkeeping for the Doors system.
var moving := false
var halted := false
var sensor_t := 0.0
var jam_t := 0.0
var jam_cooldown := 0.0
var last_sound_t := -10.0
var observed_t := 0.0
var observed := false

var _shape_query: PhysicsShapeQueryParameters3D = null


static func create(d: Dictionary) -> Node3D:
	var n := new()
	n.setup(d)
	return n


func setup(d: Dictionary) -> void:
	data = d
	door_id = String(d.id)
	kind = String(d.kind)
	name = "Door_" + door_id
	width = float(d.width) * C.TILE
	max_out = float(d.max_out)
	max_in = float(d.max_in)
	var nv := Vector3(float(d.n.x), 0.0, float(d.n.y))
	var xv := Vector3.UP.cross(nv)
	var plane: Vector2 = d.plane
	transform = Transform3D(Basis(xv, Vector3.UP, nv), Vector3(plane.x * C.TILE, 0.0, plane.y * C.TILE))
	normal = nv
	along = xv
	centre = transform.origin + Vector3.UP * 1.1
	set_meta("interact_id", door_id)
	add_to_group("interactable")
	add_to_group("door")
	var sv := Vector3(float(d.s.x), 0.0, float(d.s.y))
	var s_sign := 1.0 if sv.dot(xv) > 0.0 else -1.0
	var jamb := Plan.JAMB * C.TILE
	match kind:
		"hinged":
			var h := float(int(d.hinge)) * s_sign
			var hx := (width * 0.5 - jamb) * h
			_add_leaf(Models.hinged_leaf(width - 2.0 * jamb), hx, -h, width - 2.0 * jamb)
		"double":
			var l := width * 0.5 - jamb - Plan.MID_GAP * C.TILE * 0.5
			_add_leaf(Models.double_leaf(l), -(width * 0.5 - jamb), 1.0, l)
			_add_leaf(Models.double_leaf(l), width * 0.5 - jamb, -1.0, l)
		"gate", "auto":
			var l := width * 0.5 - jamb - Plan.MID_GAP * C.TILE * 0.5
			var gate := kind == "gate"
			_add_leaf(Models.heavy_leaf(l, gate), -(width * 0.5 - jamb), 1.0, l)
			_add_leaf(Models.heavy_leaf(l, gate), width * 0.5 - jamb, -1.0, l)
		"sliding":
			var pw := width * 0.25 + 0.04
			for i in 4:
				var x := -width * 0.5 + width * 0.125 + width * 0.25 * i
				_add_panel(Models.sliding_panel(pw), x, -0.13 if i == 0 or i == 3 else -0.05)
	_add_frame()
	# Like the furniture, room doors past the fog's reach are not drawn (the automatic doors, seen
	# down the long halls, a little further).
	var reach := 36.0 if is_hinged() else 60.0
	for mi in find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).visibility_range_end = reach
		(mi as MeshInstance3D).visibility_range_end_margin = 4.0
	if kind != "sliding":
		occluder = OccluderInstance3D.new()
		occluder.name = "Occluder"
		var q := QuadOccluder3D.new()
		q.size = Vector2(width, C.WALL_H)
		occluder.occluder = q
		occluder.position = Vector3(0.0, C.WALL_H * 0.5, 0.0)
		add_child(occluder)
	_apply_pose()


func _add_leaf(mesh: Mesh, hinge_x: float, dir: float, length: float) -> void:
	var body := AnimatableBody3D.new()
	body.name = "Leaf%d" % leaf_bodies.size()
	body.collision_layer = C.L_WORLD
	body.collision_mask = 0
	body.sync_to_physics = false
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	body.add_child(mi)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	# A pair's leaves collide a little past their meeting edge so no ray slips through the crack.
	var reach := length + (0.03 if kind != "hinged" else 0.0)
	bs.size = Vector3(reach, Models.LEAF_H, Models.LEAF_T + 0.02)
	cs.shape = bs
	cs.position = Vector3(reach * 0.5, Models.LEAF_H * 0.5 + 0.01, 0.0)
	body.add_child(cs)
	# The same leaf minus its first OPEN_INSET metres, used while it stands open (see OPEN_INSET).
	var open_len := maxf(reach - OPEN_INSET, 0.1)
	var obs := BoxShape3D.new()
	obs.size = Vector3(open_len, Models.LEAF_H, Models.LEAF_T + 0.02)
	leaf_shut_shape.append(bs)
	leaf_shut_pos.append(cs.position)
	leaf_open_shape.append(obs)
	leaf_open_pos.append(Vector3(reach - open_len * 0.5, Models.LEAF_H * 0.5 + 0.01, 0.0))
	# The aim target is always the whole leaf, whatever the pose's collider leaves out, so an open
	# door can still be aimed at and closed along its full length.
	var aim := Area3D.new()
	aim.name = "Aim"
	aim.collision_layer = C.L_INTERACT
	aim.collision_mask = 0
	aim.monitoring = false
	aim.monitorable = false
	var acs := CollisionShape3D.new()
	acs.shape = bs
	acs.position = cs.position
	aim.add_child(acs)
	body.add_child(aim)
	add_child(body)
	leaf_bodies.append(body)
	leaf_hinge.append(hinge_x)
	leaf_dir.append(dir)
	leaf_len.append(length)


func _add_panel(mesh: Mesh, x: float, z: float) -> void:
	var body := AnimatableBody3D.new()
	body.name = "Panel%d" % leaf_bodies.size()
	body.collision_layer = C.L_WORLD
	body.collision_mask = 0
	body.sync_to_physics = false
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body.add_child(mi)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(width * 0.25, Models.LEAF_H, 0.06)
	cs.shape = bs
	cs.position = Vector3(0.0, Models.LEAF_H * 0.5 + 0.01, 0.0)
	body.add_child(cs)
	# A sliding panel slides into the wall beside the doorway: it never needs the open-leaf inset.
	leaf_shut_shape.append(bs)
	leaf_shut_pos.append(cs.position)
	leaf_open_shape.append(bs)
	leaf_open_pos.append(cs.position)
	body.position = Vector3(x, 0.0, z)
	add_child(body)
	leaf_bodies.append(body)
	leaf_hinge.append(x)
	leaf_dir.append(-1.0 if x < 0.0 else 1.0)
	leaf_len.append(width * 0.25)


func _add_frame() -> void:
	var mi := MeshInstance3D.new()
	mi.name = "Frame"
	match kind:
		"sliding":
			mi.mesh = Models.slide_header(width)
		"gate", "auto":
			mi.mesh = Models.frame(width, true)
		_:
			mi.mesh = Models.frame(width, false)
	add_child(mi)
	if kind == "gate":
		var hd := MeshInstance3D.new()
		hd.name = "GateHeader"
		hd.mesh = Models.gate_header(width)
		add_child(hd)
		lamp = MeshInstance3D.new()
		lamp.name = "LockLamp"
		lamp.mesh = Models.lamp_lens()
		lamp.position = Vector3(0.0, 2.25 + 0.2, 0.1)
		lamp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(lamp)
		set_lamp("locked")


## "locked", "unlocking", "open", "off".
func set_lamp(state: String) -> void:
	if lamp == null or state == lamp_state:
		return
	lamp_state = state
	lamp.material_override = Models.lamp_material(state)


func is_hinged() -> bool:
	return kind == "hinged" or kind == "double"


func is_automatic() -> bool:
	return kind == "gate" or kind == "auto" or kind == "sliding"


func is_closed() -> bool:
	return absf(amount) < 0.04


## Degrees of the swing for an amount (hinged: signed; automatic pairs: toward `swing`).
func angle_for(a: float) -> float:
	if is_hinged():
		return clampf(a * 90.0, -max_in, max_out)
	if swing > 0:
		return clampf(a, 0.0, 1.0) * minf(90.0, max_out)
	return -clampf(a, 0.0, 1.0) * 90.0


## The widest amount allowed toward a side (+1 out, -1 in).
func limit(side: int) -> float:
	if not is_hinged():
		return 1.0
	return (max_out if side > 0 else max_in) / 90.0


## Automatic swing doors: may this pair open out of the face (away from someone in the tunnel)?
func can_swing_out() -> bool:
	return (kind == "gate" or kind == "auto") and max_out >= 80.0


## Leaf `i`'s local transform at an amount.
func leaf_xform(i: int, a: float) -> Transform3D:
	if kind == "sliding":
		var x0: float = leaf_hinge[i]
		var inner := absf(x0) < width * 0.25
		# Both panels of a side end up inside the wall beside the doorway (the outer one further).
		var travel := width * 0.5 + (0.0 if inner else width * 0.25) + 0.05
		if inner:
			travel = width * 0.5 + 0.05
		var dx: float = float(leaf_dir[i]) * travel * clampf(a, 0.0, 1.0)
		var z := -0.13 if (i == 0 or i == 3) else -0.05
		return Transform3D(Basis.IDENTITY, Vector3(x0 + dx, 0.0, z))
	var th := deg_to_rad(angle_for(a))
	var d := float(leaf_dir[i])
	var u := Vector3(d * cos(th), 0.0, sin(th))
	var basis := Basis(u, Vector3.UP, u.cross(Vector3.UP))
	return Transform3D(basis, Vector3(float(leaf_hinge[i]), 0.0, 0.0))


func _apply_pose() -> void:
	# A leaf swung open stands over a metre into the room, so it keeps blocking movement; only the
	# first OPEN_INSET metres of it give way, so its end does not sit in the doorway's mouth and
	# catch anyone cutting the corner through it. Sliding panels are inside the wall by then anyway.
	var inset := absf(amount) >= OPEN_PASS
	for i in leaf_bodies.size():
		var b: AnimatableBody3D = leaf_bodies[i]
		b.transform = leaf_xform(i, amount)
		if b.collision_layer != C.L_WORLD:
			b.collision_layer = C.L_WORLD
		if inset != _leaf_inset:
			var cs: CollisionShape3D = b.get_child(1)
			cs.shape = leaf_open_shape[i] if inset else leaf_shut_shape[i]
			cs.position = leaf_open_pos[i] if inset else leaf_shut_pos[i]
	_leaf_inset = inset
	if occluder != null:
		var shut := is_closed()
		if occluder.visible != shut:
			occluder.visible = shut


## Step toward the target. Host and clients both call it (clients with `check` false: they follow
## the host's replicated amount and never halt on their own). Returns true while still moving.
func step(delta: float, check: bool) -> bool:
	if is_equal_approx(amount, target):
		moving = false
		halted = false
		return false
	var next := move_toward(amount, target, speed * delta)
	if check and is_inside_tree() and _blocked_at(next):
		halted = true
		moving = false
		return false
	halted = false
	amount = next
	_apply_pose()
	moving = not is_equal_approx(amount, target)
	return moving


## Set the pose at once (a late joiner, dev "close all", a new level).
func snap_to(a: float) -> void:
	amount = a
	target = a
	moving = false
	_apply_pose()


## Would a leaf at `a` push into a player (or, closing, a dropped item)? Players stop a door; the
## door stops where it is, like a real one. Sliding panels only check while closing.
func _blocked_at(a: float) -> bool:
	var closing := absf(a) < absf(amount)
	if kind == "sliding" and not closing:
		return false
	if _shape_query == null:
		_shape_query = PhysicsShapeQueryParameters3D.new()
	var space := get_world_3d().direct_space_state
	# The side the leaves are sweeping through: only bodies on that side can be in their way (the
	# one pushing the door stands on the other side, pressed against it).
	var sweep := signf(a) if not closing else signf(amount)
	if not is_hinged():
		sweep = float(swing)
	var inv := global_transform.affine_inverse()
	for i in leaf_bodies.size():
		var body: AnimatableBody3D = leaf_bodies[i]
		# Always the whole leaf, whatever the pose is wearing: a door closing from wide open must
		# still see someone standing in the part its open collider leaves out.
		_shape_query.shape = leaf_shut_shape[i]
		_shape_query.transform = global_transform * leaf_xform(i, a) * Transform3D(Basis(), leaf_shut_pos[i])
		_shape_query.collision_mask = HALT_MASK_CLOSE if closing else HALT_MASK_OPEN
		_shape_query.exclude = [body.get_rid()]
		for hit in space.intersect_shape(_shape_query, 4):
			var col = hit.get("collider")
			if col == null:
				continue
			if col == opener:
				continue   # the one opening it (pulling a door toward themselves) steps back from it
			var lz: float = (inv * (col as Node3D).global_position).z
			if kind != "sliding" and sweep != 0.0 and lz * sweep < 0.0:
				continue
			return true
	return false


# ---------------------------------------------------------------------------
# Interaction (docs/CONTRACTS.md, "Interaction")
# ---------------------------------------------------------------------------

func _doors() -> Node:
	var g = get_tree().get_first_node_in_group("game") if is_inside_tree() else null
	return g.get("doors") if g != null else null


func interact_prompt(player) -> String:
	var ds := _doors()
	if ds == null:
		return ""
	return ds.prompt_for(self, player)


func interact_hold() -> float:
	return 0.0


func interact(player) -> void:
	var ds := _doors()
	if ds != null:
		ds.player_used(self, player)
