extends Node3D
## Personnel's mirrors, reflecting for real: the big full-length mirror and the one over every sink.
##
## Each mirror is a SubViewport with its own camera, reflected across the glass every frame from
## wherever the local camera is. The camera looks straight through the glass (an off-axis frustum
## fitted exactly to it, the near plane on the glass so the wall behind never shows), and the
## picture goes on a quad over the glass, flipped left to right.
##
## A mirror is a whole extra render of the scene, so not all of them run at once:
##   - the big mirror renders every frame while you can see it;
##   - of the sink mirrors you can see, the nearest renders every frame and the rest take turns,
##     one a frame, holding their last picture in between;
##   - a mirror you can't see (behind you, off screen, too far, or you're behind the wall) doesn't
##     render at all.
## While any mirror is rendering, the local player's own body is shown to the mirror cameras only
## (Player.set_mirror_self, on LightRooms.SELF, which the first-person camera leaves out), so you see
## yourself in them.
##
## The glass sizes and places below match piece_factory.gd's "full_mirror" and "vanity".

const LightRooms := preload("res://scripts/level/light_rooms.gd")

## CUSTOMIZATION: the interact id of the big mirror itself (scripts/personnel/mirror_menu.gd).
const MENU_AIM_ID := "mirror_customize"

## The big mirror's glass: size, and its centre in the piece's frame (wall-mounted: origin at the
## wall face, -Z out into the room).
const BIG_GLASS := Vector2(1.58, 2.66)
const BIG_MOUNT := 0.06
const BIG_CENTRE := Vector3(0.0, BIG_MOUNT + 1.43, -0.05)
## A sink's mirror: size, and its centre in the vanity's frame (origin at its footprint's centre).
const SINK_GLASS := Vector2(0.76, 0.92)
const SINK_CENTRE := Vector3(0.0, 1.68, 0.275 - 0.042)
## Picture resolution, pixels per metre of glass.
const BIG_PPM := 380.0
const SINK_PPM := 260.0
## Beyond these distances (metres) a mirror stops rendering.
const BIG_RANGE := 24.0
const SINK_RANGE := 14.0
## The bulbs round the glass, as actual light. piece_factory.gd has always DRAWN them -- the
## dressing-room bulbs down both sides of "full_mirror" and the light bar over "vanity"'s basin --
## but they were emissive geometry and nothing more, so no light in this hospital ever fell on the
## side of you that a mirror looks at. Every fixture hangs overhead and out in the room; stand at a
## mirror, facing a wall, and your front was lit by the 0.13 ambient alone. Dark green scrubs under
## ambient alone are black, which is why walking up to a mirror turned you into a silhouette (and
## why the sinks, which have nothing else in front of them at all, were dark at every distance).
## A little proud of the glass, so it lights you and not the wall it hangs on.
const LAMP_COLOUR := Color(1.0, 0.95, 0.82)   # piece_factory.gd's LAMP
const LAMP_OUT := 0.22
## Wide and soft rather than bright and short: a lamp only just longer than arm's reach blew the
## face out at the glass and had already fallen to nothing by the time you stepped back, which is
## the same silhouette again two metres further out.
const BIG_LAMP_RANGE := 4.2
const BIG_LAMP_ENERGY := 0.6
const SINK_LAMP_RANGE := 3.2
const SINK_LAMP_ENERGY := 0.5
## The mirror cameras see everything the first-person camera does except the first-person hands
## (fp_hands.gd HANDS_LAYER) and the dev gun's first-person model (dev_controller.gd GUN_FP_LAYER), plus
## the local player's own body. Plain numbers: piece_factory.gd preloads this script, and map
## generation runs where the autoloads those scripts need don't exist.
const HIDE_FROM_MIRRORS := (1 << 18) | (1 << 17)

class Mirror extends RefCounted:
	var big := false
	var size := Vector2.ONE
	var root: Node3D          # at the glass's centre, +Z out of the glass into the room
	var viewport: SubViewport
	var cam: Camera3D
	var shown := false        # has a picture (rendered at least once)

var _mirrors: Array[Mirror] = []
var _turn := 0
var _self_on := false
## light_rooms.gd's grid, kept for the mirror lamps' cull masks (setup).
var _grid := {}
## CUSTOMIZATION (scripts/personnel/mirror_menu.gd): while the menu is open on this machine it owns
## `set_mirror_self` itself -- its own third-person camera needs the local body shown regardless of
## what this loop would otherwise decide from whichever camera happens to be current (which, while
## the menu is up, is the menu's own camera, not this mirror's) -- so the usual per-frame
## self-visibility and render-budget management here stands aside rather than fighting it.
var menu_hold := false


## `spots` is level_info.personnel's builder form (tile-space spots; see entrance.gd), converted by
## `to_world` (tile position, height -> Vector3).
## `grid` is light_rooms.gd's area grid, for the mirror lamps' cull masks: this node carries the
## "light_dynamic" meta, so light_rooms.apply stops here and never reaches them.
func setup(spots: Dictionary, to_world: Callable, grid := {}) -> void:
	name = "Mirrors"
	set_meta("light_dynamic", true)   # light_rooms.gd: leave its layers alone
	_grid = grid
	var m: Dictionary = spots.get("mirror", {})
	if not m.is_empty():
		_add(true, BIG_GLASS, _glass_xform(m, BIG_CENTRE, to_world), BIG_PPM)
		_add_menu_aim()
		# CUSTOMIZATION: the menu the mirror opens. It lives here because it is the big mirror's,
		# and a level without one never builds it. `load`, not `preload`: mirror_menu.gd names the
		# Net and Settings autoloads, which do not exist under `godot -s` (tools/mapcheck.gd), and a
		# preload would drag it into this script's compile and fail there. See _autoloads_present.
		if _autoloads_present():
			add_child(load("res://scripts/personnel/mirror_menu.gd").new())
	for s in spots.get("sinks", []):
		_add(false, SINK_GLASS, _glass_xform(s, SINK_CENTRE, to_world), SINK_PPM)


## True in a real run and in every headless *scene* test; false under `godot -s`
## (tools/mapcheck.gd), which never instantiates the autoloads, so a script naming one cannot even
## compile. Map validation has no player and no menu to open, so the mirror menu is skipped there
## on purpose rather than throwing on every seed it builds.
static func _autoloads_present() -> bool:
	var tree := Engine.get_main_loop() as SceneTree
	return tree != null and tree.root != null and tree.root.has_node("Net")


## CUSTOMIZATION: what you aim at to open the mirror menu. A box just in front of the glass, so the
## whole mirror is clickable rather than one spot on it.
func _add_menu_aim() -> void:
	var mr := _mirrors[_mirrors.size() - 1]
	var a := Area3D.new()
	a.name = "MirrorAim"
	a.collision_layer = C.L_INTERACT
	a.collision_mask = 0
	a.monitoring = false
	a.add_to_group("interactable")
	a.set_meta("interact_id", MENU_AIM_ID)
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(mr.size.x, mr.size.y, 0.12)
	cs.shape = box
	a.add_child(cs)
	mr.root.add_child(a)
	a.position = Vector3(0, 0, 0.06)
	a.set_script(preload("res://scripts/personnel/mirror_aim.gd"))


func _glass_xform(spot: Dictionary, centre: Vector3, to_world: Callable) -> Transform3D:
	var basis := Basis(Vector3.UP, float(spot.yaw))
	var origin: Vector3 = to_world.call(spot.pos, 0.0)
	# Turned half round, so +Z points out of the glass (the piece's front is -Z).
	return Transform3D(basis * Basis(Vector3.UP, PI), origin + basis * centre)


func _add(big: bool, glass: Vector2, xf: Transform3D, ppm: float) -> void:
	var mr := Mirror.new()
	mr.big = big
	mr.size = glass
	mr.root = Node3D.new()
	mr.root.name = "BigMirror" if big else "SinkMirror%d" % _mirrors.size()
	mr.root.transform = xf   # world space: this node and the level root sit at the origin
	add_child(mr.root)
	mr.viewport = SubViewport.new()
	mr.viewport.size = Vector2i(maxi(16, int(glass.x * ppm)), maxi(16, int(glass.y * ppm)))
	mr.viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	mr.viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	mr.viewport.handle_input_locally = false
	mr.viewport.gui_disable_input = true
	mr.root.add_child(mr.viewport)
	mr.cam = Camera3D.new()
	mr.cam.projection = Camera3D.PROJECTION_FRUSTUM
	mr.cam.keep_aspect = Camera3D.KEEP_HEIGHT
	mr.viewport.add_child(mr.cam)
	var quad := MeshInstance3D.new()
	quad.name = "Glass"
	var qm := QuadMesh.new()
	qm.size = glass
	quad.mesh = qm
	quad.position = Vector3(0, 0, 0.004)   # just proud of the glass box
	quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_texture = mr.viewport.get_texture()
	mat.albedo_color = Color(0.9, 0.93, 0.94)   # a little grey, like old silvering
	mat.uv1_scale = Vector3(-1, 1, 1)           # a mirror: left and right swap
	mat.uv1_offset = Vector3(1, 0, 0)
	quad.material_override = mat
	mr.root.add_child(quad)
	_add_lamp(mr)
	_mirrors.append(mr)


## The glass's own bulbs, lighting the person in front of it (see LAMP_OUT above for why they have
## to exist at all). Shadowless like every other fixture here, so light_rooms.gd's area bits are
## what stops it lighting the room through the wall it hangs on -- which is why it needs the grid
## rather than the 0xFFFFFFFF a new OmniLight3D comes with. DYNAMIC is everything that moves, and
## SELF is your own body: the mirror is the only camera that ever sees it, so a lamp that missed
## that layer would light the room and leave the reflection exactly as black as it was.
func _add_lamp(mr: Mirror) -> void:
	var l := OmniLight3D.new()
	l.name = "Lamp"
	l.position = Vector3(0, 0, LAMP_OUT)
	l.omni_range = BIG_LAMP_RANGE if mr.big else SINK_LAMP_RANGE
	l.light_energy = BIG_LAMP_ENERGY if mr.big else SINK_LAMP_ENERGY
	l.light_color = LAMP_COLOUR
	l.shadow_enabled = false   # the flashlight is the only shadow caster
	mr.root.add_child(l)
	# mr.root.transform is already world space (see _add), and the level is still being built off the
	# tree here, so global_position would be the origin and the mask would be for the wrong room.
	var world: Vector3 = mr.root.transform.origin + mr.root.transform.basis.z.normalized() * LAMP_OUT
	l.light_cull_mask = LightRooms.light_mask(_grid, world) | LightRooms.DYNAMIC | LightRooms.SELF


func _exit_tree() -> void:
	_set_self(false)


func _process(_delta: float) -> void:
	if menu_hold:
		return
	var main := get_viewport().get_camera_3d()
	if main == null or _mirrors.is_empty():
		_set_self(false)
		return
	var eye := main.global_position
	var big_live: Mirror = null
	var sinks: Array[Mirror] = []
	for mr in _mirrors:
		if _can_see(mr, main, eye):
			if mr.big:
				big_live = mr
			else:
				sinks.append(mr)
		else:
			mr.viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	var any := big_live != null or not sinks.is_empty()
	_set_self(any)
	if not any:
		return
	var mask := (main.cull_mask & ~HIDE_FROM_MIRRORS) | LightRooms.SELF
	if big_live != null:
		_render(big_live, eye, mask, SubViewport.UPDATE_ALWAYS)
	if sinks.is_empty():
		return
	sinks.sort_custom(func(a: Mirror, b: Mirror) -> bool:
		return eye.distance_squared_to(a.root.global_position) < eye.distance_squared_to(b.root.global_position))
	_render(sinks[0], eye, mask, SubViewport.UPDATE_ALWAYS)
	if sinks.size() == 1:
		return
	# The rest take turns; one that has never had a picture goes first.
	var rest := sinks.slice(1)
	var pick: Mirror = null
	for mr in rest:
		if not mr.shown:
			pick = mr
			break
	if pick == null:
		_turn = (_turn + 1) % rest.size()
		pick = rest[_turn]
	for mr in rest:
		if mr != pick:
			mr.viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_render(pick, eye, mask, SubViewport.UPDATE_ONCE)


## CUSTOMIZATION: the big mirror's glass node, its SubViewport and its glass size, or an empty
## dictionary when this level has no big mirror.
func big_mirror() -> Dictionary:
	for mr in _mirrors:
		if mr.big:
			return {"root": mr.root, "viewport": mr.viewport, "size": mr.size}
	return {}


## In front of the glass, near enough, and some part of the glass on screen.
func _can_see(mr: Mirror, main: Camera3D, eye: Vector3) -> bool:
	var xf := mr.root.global_transform
	var n := xf.basis.z
	if (eye - xf.origin).dot(n) < 0.05:
		return false
	if eye.distance_to(xf.origin) > (BIG_RANGE if mr.big else SINK_RANGE):
		return false
	var hx := xf.basis.x * mr.size.x * 0.5
	var hy := xf.basis.y * mr.size.y * 0.5
	for p in [xf.origin, xf.origin + hx + hy, xf.origin - hx + hy, xf.origin + hx - hy, xf.origin - hx - hy]:
		if main.is_position_in_frustum(p):
			return true
	return false


## Reflect the camera across the glass and fit its frustum to the glass's edges.
func _render(mr: Mirror, eye: Vector3, mask: int, mode: int) -> void:
	var xf := mr.root.global_transform
	var n := xf.basis.z.normalized()
	var up := xf.basis.y.normalized()
	var right := xf.basis.x.normalized()
	var p := xf.origin
	var d := (eye - p).dot(n)
	var ref := eye - n * (2.0 * d)
	# Looking out of the glass (+n) from behind it: its right is the glass's left.
	mr.cam.global_transform = Transform3D(Basis(-right, up, -n), ref)
	var to_glass := p - ref
	mr.cam.set_frustum(mr.size.y, Vector2(to_glass.dot(-right), to_glass.dot(up)), maxf(0.02, d), 60.0)
	mr.cam.cull_mask = mask
	mr.viewport.render_target_update_mode = mode
	mr.shown = true


## Show the local player's body to the mirror cameras (and only them) while any mirror renders.
func _set_self(on: bool) -> void:
	var g := get_tree().get_first_node_in_group("game") if is_inside_tree() else null
	var p = g.local_player() if g != null and g.has_method("local_player") else null
	if p == null or not p.has_method("set_mirror_self"):
		_self_on = false
		return
	var want: bool = on and bool(p.alive) and not bool(p.downed)
	if want != _self_on or bool(p.get("_mirror_self")) != want:
		_self_on = want
		p.set_mirror_self(want)
