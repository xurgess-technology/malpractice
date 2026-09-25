extends Node
## Hunts z-fighting (textures "spazzing out") in a pocket space (fix-pocket-zfighting). Two modes:
##
## The flicker probe (default, Laundromat and Natatorium spots): freezes the tree, poses the player's
## camera at each named spot, nudges it half a millimetre a frame for a dozen frames (what walking
## does to the view, only smaller) and counts the pixels that flip hard between frames. A correct
## render barely changes; two surfaces fighting for one depth flip whole patches. Prints the median
## per frame pair and writes tools/game_shots/zf_<kind>_<spot>*.png: the view, the flipping pixels
## in red (_flips), and the worst pair of frames (_wa, _wb).
##
## --scan (any kind): every pair of front faces in the pocket that share a plane, face the same way
## and overlap, drawn by different things or materials. Reads the meshes, so it catches what no
## camera happens to be pointing at. Faces resting on something (a bottom on the floor, a top in the
## ceiling) are listed too and are harmless: judge each by whether anyone can see it.
##
##   tools\zfightshot.ps1 natatorium            (minimized, never takes focus; log in .godot\zfightshot.log)
##   tools\zfightshot.ps1 chapel --scan
##   extra flags: --seed=N --tag=x --step=0 (no nudge) --no-torch --no-torch-shadow

const OUT_DIR := "res://tools/game_shots"
const FRAMES := 12
const FLIP := 0.18

var _step := 0.0005
var _torch_shadow := true
var _torch := true

var main: Node3D
var game: Game
var bot: Player
var _seed := 4242
var _pocket := "laundromat"
var _tag := ""
var _scan := false


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--seed="):
			_seed = int(a.split("=")[1])
		elif a.begins_with("--pocket="):
			_pocket = a.split("=")[1]
		elif a.begins_with("--step="):
			_step = float(a.split("=")[1])
		elif a == "--no-torch-shadow":
			_torch_shadow = false
		elif a == "--scan":
			_scan = true
		elif a == "--no-torch":
			_torch = false
		elif a.begins_with("--tag="):
			_tag = "_" + a.split("=")[1]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	get_tree().create_timer(600.0).timeout.connect(func(): get_tree().quit(2))
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	game = main.game
	if main.launching:
		await main.launched
	main.menu.hide_menu()
	Net.start_solo("Camera")
	preload("res://scripts/level/pockets/pocket_plan.gd").force_kind = _pocket
	game.start_session(_seed)
	await get_tree().process_frame
	while game.get_parent().has_node("WarmupCover"):
		await get_tree().process_frame
	bot = game.local_player()
	bot.bot_active = true
	bot.bot_invulnerable = true
	bot.bot_move = Vector2.ZERO
	game.begin_shift()
	game._clear_monsters()
	await _settle(30)
	var pk = game.pockets
	if not pk.active():
		print("[zfight] no pocket was built")
		get_tree().quit(1)
		return
	var p: Dictionary = pk.pocket
	var lay: Dictionary = p.layout
	var o := Vector3(Vector2i(p.origin).x * C.TILE, 0.0, Vector2i(p.origin).y * C.TILE)
	print("[zfight] %s origin %s (%.0f m, %.0f m)" % [_pocket, p.origin, o.x, o.z])
	var w := func(t: Vector2, y := 0.0) -> Vector3:
		return o + Vector3(t.x * C.TILE, y, t.y * C.TILE)
	var spots: Array = []
	if _pocket == "laundromat":
		var isl: Dictionary = lay.islands[mini(8, lay.islands.size() - 1)]
		var ip: Vector3 = w.call(Vector2(isl.tile) + Vector2(0.5, 0.5))
		spots.append(["washer_low", ip + Vector3(0.3, C.EYE_H, 1.9), ip + Vector3(0.0, 0.05, 0.0)])
		spots.append(["washer_side", ip + Vector3(2.2, C.EYE_H, 1.4), ip + Vector3(0.0, 0.1, 0.2)])
		var dr: Dictionary = lay.dryers[mini(6, lay.dryers.size() - 1)]
		var dp: Vector3 = w.call(Vector2(dr.tile) + Vector2(0.5, 0.5))
		spots.append(["dryer_low", dp - Vector3(dr.wall.x, 0, dr.wall.y) * 2.2 + Vector3(0.4, C.EYE_H, 0), dp + Vector3(0, 0.1, 0)])
		if lay.has("tables") and not (lay.tables as Array).is_empty():
			var tp: Vector3 = w.call(Vector2(lay.tables[0]) + Vector2(0.5, 0.5))
			spots.append(["table", tp + Vector3(1.8, C.EYE_H, 1.2), tp + Vector3(0, 0.4, 0)])
	elif _pocket == "natatorium":
		var Nat := preload("res://scripts/level/pockets/natatorium.gd")
		var bz: float = lay.blocks[4]
		var bp: Vector3 = w.call(Vector2(float(Nat.POOL.end.x) + 0.45, bz))
		spots.append(["block_front", bp + Vector3(2.5, C.EYE_H, 0.6), bp + Vector3(0, 0.2, 0)])
		spots.append(["block_pool", bp + Vector3(1.6, C.EYE_H, 1.6), bp + Vector3(0, 0.1, 0)])
		spots.append(["coping", w.call(Vector2(float(Nat.POOL.end.x) + 2.0, bz + 3.0), C.EYE_H), w.call(Vector2(float(Nat.POOL.end.x) - 1.0, bz + 1.0), 0.0)])
		var d0: Dictionary = lay.drums[0]
		var dp: Vector3 = w.call(Vector2(d0.tile) + Vector2(0.5, 0.5))
		spots.append(["drums", dp + Vector3(-2.0, C.EYE_H, -2.0), dp + Vector3(0, 0.2, 0)])
		spots.append(["bleachers", w.call(Vector2(float(Nat.BLEACHERS.end.x) + 3.0, float(Nat.BLEACHERS.position.y) + 3.0), C.EYE_H), w.call(Vector2(float(Nat.BLEACHERS.end.x), float(Nat.BLEACHERS.position.y) + 5.0), 0.3)])
		spots.append(["basin_wall", w.call(Vector2(float(Nat.POOL.end.x) + 1.0, bz), C.EYE_H), w.call(Vector2(float(Nat.POOL.end.x) - 2.0, bz), -0.4)])
	# Frozen: the fixtures' flicker and anything walking about would read as flipping pixels. Only
	# this node and the renderer keep going.
	process_mode = Node.PROCESS_MODE_ALWAYS
	bot.set_flashlight(_torch)
	bot.flashlight.shadow_enabled = _torch_shadow
	if _scan:
		var holder: Node = null
		for n in game.find_children("Pocket_" + _pocket, "", true, false):
			holder = n
		print("[zfight] scanning ", holder.get_path() if holder != null else "nothing")
		if holder != null:
			_coplanar_scan(holder)
		get_tree().quit(0)
		return
	for s in spots:
		await _probe(String(s[0]), s[1], s[2])
	print("[zfight] done")
	get_tree().quit(0)


func _settle(n: int) -> void:
	for k in n:
		await get_tree().process_frame


## The bot's own camera, posed the way tools/gameshot_pockets.gd poses it (the game draws through
## the player's camera; a stray Camera3D is not what ends up on screen).
func _pose(eye: Vector3, at: Vector3) -> void:
	bot.teleport(eye - Vector3.UP * C.EYE_H)
	var d := at - eye
	var yaw := atan2(-d.x, -d.z)
	var pitch := clampf(atan2(d.y, Vector2(d.x, d.z).length()), -1.2, 1.2)
	bot.bot_yaw = yaw
	bot._yaw = yaw
	bot.rotation.y = yaw
	bot.bot_pitch = pitch
	bot._pitch = pitch
	bot.head.rotation.x = pitch
	bot.bot_move = Vector2.ZERO


func _probe(spot: String, from: Vector3, at: Vector3) -> void:
	get_tree().paused = false
	_pose(from, at)
	await _settle(40)
	get_tree().paused = true
	_pose(from, at)
	await _settle(4)
	var eye0 := bot.camera.global_position
	var side := bot.camera.global_transform.basis.x
	var prev: Image = null
	var first: Image = null
	var mask: Image = null
	var flips := 0
	var worst := 0
	var worst_pair: Array = []
	var per_pair: Array = []
	for k in FRAMES:
		bot.global_position = from - Vector3.UP * C.EYE_H + side * _step * k
		await RenderingServer.frame_post_draw
		await get_tree().process_frame
		var img := get_viewport().get_texture().get_image()
		img.convert(Image.FORMAT_RGB8)
		if first == null:
			first = img
			mask = Image.create(img.get_width(), img.get_height(), false, Image.FORMAT_RGB8)
			mask.copy_from(img)
			mask.adjust_bcs(0.35, 1.0, 0.0)
		if prev != null:
			var n := 0
			for y in range(0, img.get_height(), 2):
				for x in range(0, img.get_width(), 2):
					var a := img.get_pixel(x, y)
					var b := prev.get_pixel(x, y)
					if absf(a.get_luminance() - b.get_luminance()) > FLIP:
						n += 1
						mask.set_pixel(x, y, Color.RED)
			flips += n
			per_pair.append(n)
			if n > worst:
				worst = n
				worst_pair = [prev, img]
		prev = img
	var base := "%s/zf_%s_%s%s" % [OUT_DIR, _pocket, spot, _tag]
	first.save_png(ProjectSettings.globalize_path(base + ".png"))
	mask.save_png(ProjectSettings.globalize_path(base + "_flips.png"))
	if not worst_pair.is_empty():
		(worst_pair[0] as Image).save_png(ProjectSettings.globalize_path(base + "_wa.png"))
		(worst_pair[1] as Image).save_png(ProjectSettings.globalize_path(base + "_wb.png"))
	# The median pair is the number to read: a single pair that flips a big share of the screen is a
	# light changing (a flickering tube, the torch settling), not two surfaces fighting.
	per_pair.sort()
	var median: int = per_pair[per_pair.size() / 2] if not per_pair.is_empty() else 0
	print("[zfight] %s: median %d flipping px per frame pair, %d in all over %d pairs (worst %d), eye %s" % [spot, median, flips, FRAMES - 1, worst, eye0])


## --scan: every pair of front faces in the level that lie in the same plane, face the same way and
## overlap, drawn by different things (or different materials of one thing). Those are the pairs
## that fight for the same pixels. Faces pointing opposite ways never fight (only one of them is a
## front face from any side), and a thing fighting itself with one material cannot be seen.
func _coplanar_scan(level: Node) -> void:
	var buckets := {}
	var owners: Array = []
	var mesh_names := {}
	var cache: Dictionary = preload("res://scripts/level/pockets/pocket_common.gd")._mesh_cache
	for k in cache.keys():
		mesh_names[cache[k]] = String(k)
	var tri_count := 0
	for n in level.find_children("*", "GeometryInstance3D", true, false):
		var gi := n as GeometryInstance3D
		if not gi.is_visible_in_tree():
			continue
		var mesh: Mesh = null
		var xfs: Array = []
		if gi is MeshInstance3D:
			mesh = (gi as MeshInstance3D).mesh
			xfs = [gi.global_transform]
		elif gi is MultiMeshInstance3D and (gi as MultiMeshInstance3D).multimesh != null:
			var mm: MultiMesh = (gi as MultiMeshInstance3D).multimesh
			mesh = mm.mesh
			for k in mm.instance_count:
				xfs.append(gi.global_transform * mm.get_instance_transform(k))
		if mesh == null or not (mesh is ArrayMesh):
			continue
		for si in mesh.get_surface_count():
			var arr: Array = mesh.surface_get_arrays(si)
			var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var idx = arr[Mesh.ARRAY_INDEX]
			var tris := PackedVector3Array()
			if idx != null and (idx as PackedInt32Array).size() > 0:
				for i in (idx as PackedInt32Array):
					tris.append(vs[i])
			else:
				tris = vs
			for xi in xfs.size():
				var xf: Transform3D = xfs[xi]
				var owner := owners.size()
				var mname := String(mesh_names.get(mesh, ""))
				var mat := mesh.surface_get_material(si)
				var mat_name := ""
				if mat != null:
					mat_name = mat.resource_name if mat.resource_name != "" else str(mat.get_instance_id())
				owners.append("%s%s#%d s%d(%s)" % [String(level.get_path_to(gi)), ("[" + mname + "]") if mname != "" else "", xi, si, mat_name])
				for t in range(0, tris.size() - 2, 3):
					var a: Vector3 = xf * tris[t]
					var b: Vector3 = xf * tris[t + 1]
					var c: Vector3 = xf * tris[t + 2]
					# Godot's front face is clockwise, so the face points along (c - a) x (b - a).
					var nn := (c - a).cross(b - a)
					if nn.length_squared() < 1e-10:
						continue
					nn = nn.normalized()
					var key := "%d,%d,%d|%d" % [roundi(nn.x * 200.0), roundi(nn.y * 200.0), roundi(nn.z * 200.0), roundi(nn.dot(a) * 400.0)]
					if not buckets.has(key):
						buckets[key] = []
					(buckets[key] as Array).append([owner, a, b, c, nn])
					tri_count += 1
	print("[zfight] scan: %d triangles, %d planes" % [tri_count, buckets.size()])
	var sizes: Array = []
	for key in buckets.keys():
		sizes.append([(buckets[key] as Array).size(), key])
	sizes.sort_custom(func(x, y): return x[0] > y[0])
	print("[zfight] biggest planes: ", sizes.slice(0, 5))
	var found := {}
	for key in buckets.keys():
		var list: Array = buckets[key]
		if list.size() < 2:
			continue
		var nn: Vector3 = list[0][4]
		var u := nn.cross(Vector3.UP if absf(nn.y) < 0.9 else Vector3.RIGHT).normalized()
		var v := nn.cross(u)
		# Each triangle flat in the plane once, and a coarse grid so only neighbours are compared.
		var flat: Array = []
		var cells := {}
		for i in list.size():
			var t2 := _tri2(list[i], u, v)
			var r := _box2(t2)
			flat.append([t2, r])
			for cx in range(floori(r.position.x), floori(r.end.x) + 1):
				for cy in range(floori(r.position.y), floori(r.end.y) + 1):
					var ck := Vector2i(cx, cy)
					if not cells.has(ck):
						cells[ck] = []
					(cells[ck] as Array).append(i)
		var seen := {}
		for ck in cells.keys():
			var ids: Array = cells[ck]
			for ii in ids.size():
				for jj in range(ii + 1, ids.size()):
					var i: int = ids[ii]
					var j: int = ids[jj]
					var p: Array = list[i]
					var q: Array = list[j]
					if int(p[0]) == int(q[0]):
						continue
					var sk := Vector2i(mini(i, j), maxi(i, j))
					if seen.has(sk):
						continue
					seen[sk] = true
					if not (flat[i][1] as Rect2).grow(-0.001).intersects(flat[j][1]):
						continue
					var ov := _overlap(flat[i][0], flat[j][0])
					if ov < 0.0004:
						continue
					var pk := Vector2i(int(p[0]), int(q[0]))
					if not found.has(pk) or float(found[pk][0]) < ov:
						found[pk] = [ov, p]
	var lines: Array = []
	for k: Vector2i in found.keys():
		var t: Array = found[k][1]
		var mid: Vector3 = ((t[1] as Vector3) + (t[2] as Vector3) + (t[3] as Vector3)) / 3.0
		lines.append("[zfight] coplanar %.4f m2: %s  <->  %s  n=%s at %s" % [found[k][0], owners[k.x], owners[k.y],
				((t[4] as Vector3) * 100.0).round() / 100.0, mid.snapped(Vector3.ONE * 0.01)])
	lines.sort()
	for l in lines:
		print(l)
	var keys := lines
	print("[zfight] scan: %d coplanar overlapping pairs" % keys.size())


func _tri2(t: Array, u: Vector3, v: Vector3) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in [1, 2, 3]:
		var p: Vector3 = t[i]
		out.append(Vector2(p.dot(u), p.dot(v)))
	return out


## Area of the overlap of two triangles (both made counter-clockwise, then clipped).
func _overlap(a: PackedVector2Array, b: PackedVector2Array) -> float:
	if _area(a) < 0.0:
		a.reverse()
	if _area(b) < 0.0:
		b.reverse()
	var poly := Geometry2D.intersect_polygons(a, b)
	var total := 0.0
	for pg in poly:
		total += absf(_area(pg))
	return total


func _area(p: PackedVector2Array) -> float:
	var s := 0.0
	for i in p.size():
		var j := (i + 1) % p.size()
		s += p[i].x * p[j].y - p[j].x * p[i].y
	return s * 0.5


func _box2(t: PackedVector2Array) -> Rect2:
	var r := Rect2(t[0], Vector2.ZERO)
	r = r.expand(t[1])
	return r.expand(t[2])
