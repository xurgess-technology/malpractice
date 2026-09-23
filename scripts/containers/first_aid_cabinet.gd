extends "res://scripts/containers/container_base.gd"
## POCKETS 2 phase 2 (docs/POCKET_SPACES_2.md, the Natatorium): the first-aid cabinet bolted to the
## north lifeguard stand. A white enamel box with a red cross on its door, the door hinged down the
## left edge and swinging out flat against the wall. Three slots on one shelf.
##
## It is the only container in the game with guaranteed contents: `game.stock_first_aid_cabinets()`
## puts gauze in the first slot and a tourniquet in the second of every one of these at the start of
## each shift, so finding the Natatorium is always worth the walk to the stand. The third slot is
## left to the ordinary spawners, which is how a lifeguard whistle sometimes turns up beside them.
##
## Local frame: origin on the floor at the wall, the cabinet hangs toward -Z.

const CW := 0.46
const CH := 0.38
const CD := 0.16
const BOTTOM := 1.06
const T := 0.014
const OFF_WALL := 0.02
const DOOR_OPEN_DEG := 105.0

var _door: Node3D


static func create(id: String) -> Node3D:
	var c = new()
	c.init_container("first_aid_cabinet", id)
	c.display_name = "first-aid cabinet"
	c.sound_open = "containers_fridge_open"
	c.sound_close = "containers_thunk"
	c.open_time = 0.4
	c.close_time = 0.3
	c._build()
	return c


func _build() -> void:
	var enamel := Mats.get_mat("enamel")
	var dark := Mats.get_mat("enamel_dark")
	var z0 := -OFF_WALL
	var zc := z0 - CD * 0.5
	var zf := z0 - CD
	var yc := BOTTOM + CH * 0.5
	# The carcass: back, top, bottom, two sides, and the shelf the contents stand on.
	box(self, Vector3(CW, CH, T), Vector3(0, yc, z0 - T * 0.5), dark)
	for sy in [-1.0, 1.0]:
		box(self, Vector3(CW, T, CD), Vector3(0, yc + sy * (CH - T) * 0.5, zc), enamel)
	for sx in [-1.0, 1.0]:
		box(self, Vector3(T, CH, CD), Vector3(sx * (CW - T) * 0.5, yc, zc), enamel)
	box(self, Vector3(CW - 2 * T, 0.008, CD - T), Vector3(0, BOTTOM + T + 0.004, zc), Mats.get_mat("liner"))
	# Mounting plate and the two bolts through it into the stand's leg.
	box(self, Vector3(CW + 0.06, 0.04, 0.01), Vector3(0, BOTTOM + CH + 0.03, -0.005), Mats.get_mat("steel_dark"))
	for sx in [-1.0, 1.0]:
		cyl(self, 0.008, 0.012, Vector3(sx * 0.16, BOTTOM + CH + 0.03, -0.012), Mats.get_mat("chrome"), Vector3(90, 0, 0), 8)

	# The door, hinged down the left edge.
	_door = Node3D.new()
	_door.name = "Door"
	_door.position = Vector3(-(CW - T) * 0.5, BOTTOM, zf)
	add_child(_door)
	var dx := (CW - T) * 0.5
	box(_door, Vector3(CW, CH, T), Vector3(dx, CH * 0.5, T * 0.5), enamel)
	# The cross, and the latch on the swinging edge.
	box(_door, Vector3(0.15, 0.045, 0.004), Vector3(dx, CH * 0.55, -0.002), Mats.get_mat("white_cross"))
	box(_door, Vector3(0.045, 0.15, 0.004), Vector3(dx, CH * 0.55, -0.002), Mats.get_mat("white_cross"))
	box(_door, Vector3(0.018, 0.05, 0.016), Vector3(CW - 0.03, CH * 0.5, -0.006), Mats.get_mat("chrome"))
	collider(_door, C.L_INTERACT, Vector3(CW, CH, 0.05), Vector3(dx, CH * 0.5, 0.0), "Aim")

	for sx in [-0.14, 0.0, 0.14]:
		add_slot(self, Transform3D(Basis.IDENTITY, Vector3(sx, BOTTOM + T + 0.012, zc - 0.005)))

	collider(self, C.L_WORLD, Vector3(CW + 0.04, CH, CD), Vector3(0, yc, zc), "Body")
	bake(self)
	bake(_door)


func _apply_pose(t: float) -> void:
	if _door != null:
		_door.rotation.y = deg_to_rad(DOOR_OPEN_DEG) * t
