extends RefCounted
## POCKETS: the Laundromat. A coin-op laundromat under flat fluorescent light, far longer than the
## corridor it opens off: banks of stacked dryers against the long walls, back-to-back islands of
## front-load washers down the middle, folding tables between them, a row of moulded chairs nobody
## sits in, and a change machine by the door. Every machine is running and every drum is empty.
##
## The running machines are the whole point. This is the one space that declares a real
## AMBIENT_NOISE_LEVEL (docs/POCKET_SPACES_2.md phase 4): the drone masks a walking player's
## footsteps from the Sonographer outright and shortens the reach of everything louder.
##
## layout, prepare, build_steps, build and the doorways as in factory.gd.

const Common := preload("res://scripts/level/pockets/pocket_common.gd")
const Stub := preload("res://scripts/level/pockets/stub.gd")

## POCKETS 2 phase 4: the ambient noise floor a sound-hunting monster stands in here (see
## PocketSpaces.ambient_noise_at). Every machine on this floor is running, so the room is loud.
##
## The number is taken from the footstep loudnesses it has to beat, not guessed. game.gd's
## `_tick_noise` emits 0.25 for a walking step and 0.8 for a sprinting one, and the Sonographer's
## `_hear` subtracts this floor before `loudness * HEAR_PER_LOUDNESS` (22 m). At 0.30:
##   - a walking step masks to 0.0 and carries 0 m: inside this room it is not heard at all,
##     with 0.05 of headroom over the 0.25 it has to swallow;
##   - a sprinting step masks to 0.50 and carries 11 m instead of 17.6, and drops under the
##     brain's LOUD (0.8) threshold, so it fills suspicion instead of pinning you outright;
##   - a scattered bucket of quarters (QUARTER_NOISE, 0.9) masks to 0.60 and still carries 13 m,
##     which is what keeps it usable as a noisemaker in the room it is found in.
## Outside the Laundromat the floor is 0.0 and every one of those numbers is the hospital's own.
const AMBIENT_NOISE_LEVEL := 0.30

## POCKETS 2: the item kinds this space puts into the world, as one discoverable set, beside
## AMBIENT_NOISE_LEVEL. The loot table (scripts/economy/loot_table.gd) gives each of these a weight
## for the "laundromat" and "laundromat_back" room kinds and no "*" weight, so today they are found
## here and nowhere else. A later task wants a pocket's items to bleed a little way out into the
## hospital around its entrances; this constant is what it reads rather than digging literals out of
## the layout. The name is shared with the Natatorium and the Chapel -- match it in a new space.
const POCKET_ITEMS := ["quarter_bucket", "warm_scrubs", "fabric_softener"]

const T := 1.5
const M := 10
const W := 38
const H := 20
const CEIL := 3.4
const BACK_CEIL := 2.9

const INTERIOR := Rect2i(M + 1, M + 1, W, H)        # x 11..48, y 11..30
const MAIN := Rect2i(M + 1, M + 1, W, 15)           # x 11..48, y 11..25; wall row y 26
const UTILITY := Rect2i(M + 1, M + 17, 10, 4)       # x 11..20, y 27..30
## The trough sink against the utility room's west wall. It runs from the corner rather than
## stopping short of it: a one-tile nook walled on two sides is floor the navigation bake cannot
## reach, which tools/mapcheck.gd reports as an unreachable tile on every seed.
const SINK := Rect2i(M + 1, M + 17, 1, 3)          # x 11, y 27..29
const OFFICE := Rect2i(M + 12, M + 17, 8, 4)        # x 22..29, y 27..30; wall column x 21

## The two bands of back-to-back washer islands, and the row of folding tables between them.
const ISLAND_YS := [[M + 5, M + 6], [M + 10, M + 11]]   # y 15/16 and y 20/21
const TABLE_Y := M + 8                                   # y 18
## A two-tile cross aisle every CROSS_STEP tiles, so an island is never an unbroken wall.
const CROSS_STEP := 12
const CROSS_KEEP := 10


static func layout(stubs: Array, seed: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var g := Common.new_grid(INTERIOR.end.x + M + 1, INTERIOR.end.y + M + 1)
	var main := Common.add_room(g, {"name": "main", "ceil": CEIL, "floor": "vinyl", "ceiling": "acoustic",
			"wall": "block", "wall_low": "dado", "split": 1.15, "place": "laundromat"})
	var utility := Common.add_room(g, {"name": "utility", "ceil": BACK_CEIL, "floor": "utility_floor",
			"ceiling": "acoustic", "wall": "utility_wall", "wall_low": "", "split": 0.0, "place": "laundromat_back"})
	var office := Common.add_room(g, {"name": "office", "ceil": BACK_CEIL, "floor": "office_floor",
			"ceiling": "acoustic", "wall": "office_wall", "wall_low": "dado", "split": 1.05, "place": "laundromat_back"})
	Common.carve(g, MAIN, main)
	Common.carve(g, UTILITY, utility)
	Common.carve(g, OFFICE, office)
	var doors := {
		"utility": Vector2i(UTILITY.position.x + 3, MAIN.end.y),
		"office": Vector2i(OFFICE.position.x + 3, MAIN.end.y),
	}
	Common.set_open(g, doors.utility.x, doors.utility.y, utility)
	Common.set_open(g, doors.office.x, doors.office.y, office)

	# Containers first, so no entrance opens onto one (the same reason the Restaurant fixes its bar
	# before it places ports).
	var containers := [
		{"tile": Vector2i(MAIN.end.x - 1, MAIN.position.y + 2), "wall": Vector2i(1, 0), "type": "med_fridge"},
		{"tile": Vector2i(UTILITY.position.x + 1, UTILITY.position.y), "wall": Vector2i(0, -1), "type": "drawer_unit"},
		{"tile": Vector2i(UTILITY.end.x - 1, UTILITY.position.y + 2), "wall": Vector2i(1, 0), "type": "pegboard"},
		{"tile": Vector2i(OFFICE.position.x + 1, OFFICE.position.y), "wall": Vector2i(0, -1), "type": "station_drawers"},
		{"tile": Vector2i(OFFICE.end.x - 1, OFFICE.end.y - 1), "wall": Vector2i(1, 0), "type": "trauma_bag"},
	]
	for c in containers:
		if c.type != "trauma_bag" and c.type != "pegboard":
			_block(g, Rect2i(c.tile, Vector2i.ONE))
		Common.reserve(g, Rect2i(c.tile, Vector2i.ONE))
	# The floor in front of the two back-room doorways stays clear. The dryer bank runs the length of
	# the south wall, and a bank standing across a doorway walls the whole back of the building off:
	# tools/mapcheck.gd caught exactly that (72 unreachable tiles and a door opening onto a blocked
	# tile, on every seed) once it started walking this space.
	for d: Vector2i in [doors.utility, doors.office]:
		Common.reserve(g, Rect2i(d.x - 1, MAIN.end.y - 3, 3, 3))
	# The back rooms' fixed furniture, so nothing paths through the trough sink, the water heater or
	# the desk. They are built in _back_rooms; these are the tiles they stand on.
	_block(g, SINK)                                                                 # the trough sink
	_block(g, Rect2i(UTILITY.end.x - 1, UTILITY.end.y - 1, 1, 1))                    # the water heater
	_block(g, Rect2i(OFFICE.get_center().x, OFFICE.get_center().y, 1, 1))            # the desk
	# The change machine keeps its piece of the north wall.
	var change := Vector2i(MAIN.position.x + 2, MAIN.position.y)
	_block(g, Rect2i(change, Vector2i.ONE))
	Common.reserve(g, Rect2i(change, Vector2i.ONE).grow(1))

	# Entrances go on the main hall's three outer walls; the back rooms never open onto a hallway.
	var walls := [
		{"from": Vector2i(M + 3, M), "dir": Vector2i(1, 0), "len": W - 6, "ev": Vector2i(0, -1)},
		{"from": Vector2i(M, M + 3), "dir": Vector2i(0, 1), "len": 9, "ev": Vector2i(-1, 0)},
		{"from": Vector2i(INTERIOR.end.x, M + 3), "dir": Vector2i(0, 1), "len": 9, "ev": Vector2i(1, 0)},
	]
	var ports := Common.place_ports(g, stubs, walls, rng)

	# Back-to-back washer islands down the middle, in runs broken by cross aisles.
	var islands: Array = []
	for band: Array in ISLAND_YS:
		var y0: int = band[0]
		var y1: int = band[1]
		for x in range(MAIN.position.x + 3, MAIN.end.x - 2):
			if (x - (MAIN.position.x + 3)) % CROSS_STEP >= CROSS_KEEP:
				continue
			var r := Rect2i(x, y0, 1, 2)
			if not _free(g, main, r):
				continue
			islands.append({"tile": Vector2i(x, y0), "flip": false})
			islands.append({"tile": Vector2i(x, y1), "flip": true})
			_block(g, r)
	# Stacked dryers against the long walls, facing the room.
	var dryers: Array = []
	for pair in [[MAIN.position.y, Vector2i(0, -1)], [MAIN.end.y - 1, Vector2i(0, 1)]]:
		var y: int = pair[0]
		var wall: Vector2i = pair[1]
		for x in range(MAIN.position.x + 2, MAIN.end.x - 1):
			var r := Rect2i(x, y, 1, 1)
			if not _free(g, main, r):
				continue
			dryers.append({"tile": Vector2i(x, y), "wall": wall})
			_block(g, r)
	# Folding tables down the middle aisle.
	var tables: Array = []
	for x in range(MAIN.position.x + 4, MAIN.end.x - 3, 5):
		var r := Rect2i(x, TABLE_Y, 1, 1)
		if not _free(g, main, r):
			continue
		tables.append(Vector2i(x, TABLE_Y))
		_block(g, r)
	# Moulded chairs in a row along the west wall, wherever an entrance did not land.
	var chairs: Array = []
	for y in range(MAIN.position.y + 2, MAIN.end.y - 2):
		var r := Rect2i(MAIN.position.x, y, 1, 1)
		if not _free(g, main, r):
			continue
		chairs.append(Vector2i(MAIN.position.x, y))
		_block(g, r)

	var spawns := [Vector2i(MAIN.position.x + 6, TABLE_Y), Vector2i(MAIN.end.x - 7, TABLE_Y),
			Vector2i(UTILITY.get_center().x, UTILITY.get_center().y)]
	# Tubes close enough together that the light is flat and there is nowhere dim to stand. The room
	# hides you by sound, not by darkness, so it wants to be unpleasantly well lit.
	var lamps: Array = []
	for ly in [MAIN.position.y + 2, TABLE_Y, MAIN.end.y - 3]:
		for lx in range(MAIN.position.x + 3, MAIN.end.x - 2, 5):
			lamps.append(Vector2i(lx, ly))
	return {"kind": "laundromat", "size": Vector2i(g.w, g.h), "grid": g, "rows": Common.rows(g), "ports": ports,
			"islands": islands, "dryers": dryers, "tables": tables, "chairs": chairs, "change": change,
			"containers": containers, "spawns": spawns, "lamps": lamps, "doors": doors,
			"spawn": Vector2i(MAIN.get_center().x, TABLE_Y)}


## Open floor of `room` that nothing has taken yet.
static func _free(g: Dictionary, room: int, r: Rect2i) -> bool:
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			if not Common.is_open(g, x, y):
				return false
			var i := Common.idx(g, x, y)
			if g.reserved[i] == 1 or g.nav[i] == 1 or g.stub[i] == 1 or g.room[i] != room:
				return false
	return true


static func _block(g: Dictionary, r: Rect2i) -> void:
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			if Common.inb(g, x, y):
				g.nav[Common.idx(g, x, y)] = 1


# =========================================================================
# build
# =========================================================================

## Data only (a worker thread): the grid's surfaces as mesh arrays and the navigation faces.
static func prepare(lay: Dictionary, origin: Vector2i) -> Dictionary:
	var geo := Common.Geo.new()
	var nav := PackedVector3Array()
	Common.build_surfaces(lay.grid, origin, geo, nav)
	Common.lintels(lay.grid, origin, geo, doorways(lay))
	geo.bake()
	return {"geo": geo, "nav_faces": nav}


## Everything at once (warmup, tools): the interior's root node.
static func build(lay: Dictionary, origin: Vector2i, out: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = "Laundromat"
	var prep := prepare(lay, origin)
	out.nav_faces.append_array(prep.nav_faces)
	Common.run_steps(build_steps(lay, origin, out, root, prep))
	return root


## The interior's nodes as small steps under `root` (see Common.run_steps).
static func build_steps(lay: Dictionary, origin: Vector2i, out: Dictionary, root: Node3D, prep: Dictionary) -> Array:
	var ow := Vector3(origin.x * T, 0.0, origin.y * T)
	var world := func(t: Vector2, y := 0.0) -> Vector3:
		return ow + Vector3(t.x * T, y, t.y * T)
	var ctx := {}
	var steps: Array = []
	var geo: Common.Geo = prep.geo
	var props := Common.Props.new()
	var enamel := Common.mat("laun_enamel", Color(0.90, 0.91, 0.90), 0.35)
	var chrome := Common.mat("laun_chrome", Color(0.72, 0.74, 0.76), 0.18, 0.95)
	var dark := Common.mat("laun_dark", Color(0.09, 0.10, 0.11), 0.5)
	var steel := Common.tri_mat("laun_steel", "mat/metal", Color(0.60, 0.62, 0.64), 1.2, 0.4, 0.85)

	steps.append(func():
		geo.mats["vinyl"] = _tex_mat("vinyl", _vinyl_tex(), 0.55, Vector3(0.5, 0.5, 1))
		geo.mats["acoustic"] = _tex_mat("acoustic", _acoustic_tex(), 0.95, Vector3(0.5, 0.5, 1))
		geo.mats["block"] = Common.tri_mat("laun_block", "mat/wall", Color(0.86, 0.88, 0.84), 0.4, 0.9)
		geo.mats["dado"] = Common.tri_mat("laun_dado", "mat/wall_tile", Color(0.42, 0.62, 0.70), 0.5, 0.45)
		geo.mats["utility_floor"] = Common.tri_mat("laun_ufloor", "mat/tile_floor", Color(0.48, 0.48, 0.46), 0.6, 0.7)
		geo.mats["utility_wall"] = Common.tri_mat("laun_uwall", "mat/wall", Color(0.62, 0.64, 0.60), 0.4, 0.95)
		geo.mats["office_floor"] = Common.tri_mat("laun_ofloor", "mat/tile_floor", Color(0.58, 0.54, 0.46), 0.6, 0.7)
		geo.mats["office_wall"] = Common.tri_mat("laun_owall", "mat/wall", Color(0.80, 0.78, 0.70), 0.4, 0.9)
		return geo.commit_steps(root, ctx))
	steps.append(func():
		var body: StaticBody3D = ctx.body
		var inter := Rect2(Vector2(INTERIOR.position) * T + Vector2(ow.x, ow.z), Vector2(INTERIOR.size) * T)
		Common.collider(body, Transform3D(Basis(), Vector3(inter.get_center().x, -0.2, inter.get_center().y)), Vector3(inter.size.x, 0.4, inter.size.y))
		Common.collider(body, Transform3D(Basis(), Vector3(inter.get_center().x, CEIL + 0.2, inter.get_center().y)), Vector3(inter.size.x, 0.4, inter.size.y)))
	steps.append(func(): _washers(props, ctx.body, lay, world, enamel, chrome, dark, out))
	steps.append(func(): _dryers(props, ctx.body, lay, world, enamel, chrome, dark, out))
	steps.append(func(): _tables(props, ctx.body, lay, world, steel, out))
	steps.append(func(): _chairs(props, lay, world))
	steps.append(func(): _front(root, ctx.body, lay, world, enamel, chrome, dark, out))
	steps.append(func(): _back_rooms(root, ctx.body, lay, world, steel, out))
	steps.append(func(): _signs(root, lay, world))
	steps.append(func(): _lights(root, lay, world, out))

	var cts := Node3D.new()
	cts.name = "Containers"
	steps.append(func(): root.add_child(cts))
	for c in lay.containers:
		steps.append(func():
			var t: Vector2i = c.tile
			var room := "laundromat_back" if (UTILITY.has_point(t) or OFFICE.has_point(t)) else "laundromat"
			Common.container(cts, out, origin, t, c.wall, c.type, room))
	steps.append(func():
		for s: Vector2i in lay.spawns:
			out.monster_spawns.append(world.call(Vector2(s) + Vector2(0.5, 0.5)))
		out["spawn"] = world.call(Vector2(lay.spawn) + Vector2(0.5, 0.5))
		return props.commit_steps(root))
	return steps


## The two back-room doorways. Data only.
static func doorways(lay: Dictionary) -> Array:
	var d: Dictionary = lay.doors
	return [
		{"tiles": [d.utility], "n": Vector2i(0, -1), "kind": "hinged"},
		{"tiles": [d.office], "n": Vector2i(0, -1), "kind": "hinged"},
	]


## The doorways as door plan entries in world tiles.
static func door_entries(lay: Dictionary, origin: Vector2i) -> Array:
	var out: Array = []
	for dw in doorways(lay):
		out.append(Common.door_entry(origin, dw.tiles, dw.n, dw.kind, 90.0))
	return out


# ---- materials and textures -----------------------------------------------

static func _tex_mat(key: String, tex: Texture2D, rough: float, scale: Vector3) -> Material:
	var ck := "laun_" + key
	if Common._mat_cache.has(ck):
		return Common._mat_cache[ck]
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	m.roughness = rough
	m.uv1_scale = scale
	Common._mat_cache[ck] = m
	return m


## Speckled sheet vinyl, in big squares with a scuffed seam between them.
static func _vinyl_tex() -> Texture2D:
	return Common.cached_texture("laun_vinyl", func():
		var n := 128
		var img := Image.create(n, n, true, Image.FORMAT_RGB8)
		var base := Color(0.70, 0.71, 0.67)
		for y in n:
			for x in n:
				var c := base
				var speck := sin(float(x * 41.7 + y * 17.3)) * 28461.13
				speck -= floor(speck)
				if speck > 0.86:
					c = Color(0.30, 0.42, 0.46)
				elif speck > 0.70:
					c = base.darkened(0.16)
				elif speck < 0.10:
					c = Color(0.86, 0.86, 0.82)
				if x % 64 < 2 or y % 64 < 2:
					c = base.darkened(0.28)
				img.set_pixel(x, y, c)
		img.generate_mipmaps()
		return ImageTexture.create_from_image(img))


## Perforated acoustic ceiling tile on a grid.
static func _acoustic_tex() -> Texture2D:
	return Common.cached_texture("laun_acoustic", func():
		var n := 128
		var img := Image.create(n, n, true, Image.FORMAT_RGB8)
		var tile := Color(0.83, 0.83, 0.80)
		for y in n:
			for x in n:
				var c := tile
				var hole := sin(float(x * 12.9898 + y * 78.233)) * 43758.5453
				hole -= floor(hole)
				if hole > 0.90:
					c = tile.darkened(0.22)
				if x % 64 < 2 or y % 64 < 2:
					c = Color(0.55, 0.56, 0.55)
				img.set_pixel(x, y, c)
		img.generate_mipmaps()
		return ImageTexture.create_from_image(img))


# ---- machines ---------------------------------------------------------------

## A PAIR of front-load washers filling one tile, origin on the floor at the tile centre, doors
## facing +Z. One machine per 1.5 m tile left a gap between every two of them, which reads as a row
## of separate cabinets; a laundromat's machines are bolted side by side in an unbroken bank.
static func _washer_mesh(enamel: Material, chrome: Material, dark: Material) -> Mesh:
	return Common.cached_mesh("laun_washer", func():
		var mb := Common.MeshBuilder.new()
		var glass := Common.mat("laun_glass", Color(0.16, 0.20, 0.22), 0.08, 0.2)
		var lamp := Common.mat("laun_lamp_on", Color(0.6, 0.9, 0.7), 0.3, 0.0, Color(0.35, 1.0, 0.55), 3.0)
		for sx in [-0.365, 0.365]:
			mb.box("e", enamel, Transform3D(Basis(), Vector3(sx, 0.43, 0)), Vector3(0.71, 0.86, 0.70))
			# The door: a chrome ring around dark glass, set into the front.
			mb.cylinder("c", chrome, Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(sx, 0.44, 0.345)), 0.21, 0.04, 16)
			mb.cylinder("g", glass, Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(sx, 0.44, 0.362)), 0.165, 0.012, 16)
			# Control panel, coin slide and the little green light that says it is running.
			mb.box("d", dark, Transform3D(Basis(), Vector3(sx, 0.80, 0.352)), Vector3(0.64, 0.11, 0.015))
			mb.box("c", chrome, Transform3D(Basis(), Vector3(sx + 0.21, 0.80, 0.362)), Vector3(0.13, 0.05, 0.02))
			mb.cylinder("l", lamp, Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(sx - 0.23, 0.80, 0.363)), 0.017, 0.01, 8)
		return mb.commit())


## Four dryers filling one tile against a wall -- two columns of two, stacked -- origin on the floor
## at the tile centre, doors facing +Z. Same reason as the washers: a bank, not a row of cabinets.
static func _dryer_mesh(enamel: Material, chrome: Material, dark: Material) -> Mesh:
	return Common.cached_mesh("laun_dryer", func():
		var mb := Common.MeshBuilder.new()
		var glass := Common.mat("laun_glass", Color(0.16, 0.20, 0.22), 0.08, 0.2)
		var lamp := Common.mat("laun_lamp_on", Color(0.6, 0.9, 0.7), 0.3, 0.0, Color(0.35, 1.0, 0.55), 3.0)
		mb.box("e", enamel, Transform3D(Basis(), Vector3(0, 0.90, 0)), Vector3(1.48, 1.80, 0.72))
		for sx in [-0.37, 0.37]:
			for yy in [0.50, 1.32]:
				mb.cylinder("c", chrome, Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(sx, yy, 0.365)), 0.23, 0.04, 16)
				mb.cylinder("g", glass, Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(sx, yy, 0.382)), 0.185, 0.012, 16)
				mb.box("d", dark, Transform3D(Basis(), Vector3(sx, yy + 0.32, 0.372)), Vector3(0.68, 0.10, 0.015))
				mb.cylinder("l", lamp, Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(sx - 0.25, yy + 0.32, 0.383)), 0.017, 0.01, 8)
			# The seam between the two columns.
			mb.box("d", dark, Transform3D(Basis(), Vector3(0.0, 0.90, 0.362)), Vector3(0.02, 1.76, 0.01))
		return mb.commit())


## Contiguous runs of an (unsorted) tile-x list, as inclusive [x0, x1] pairs. A doorway reserve or
## a cross aisle breaks a run; everything else in one bank collapses into one collider, the same way
## the Chapel merges a whole pew row into two boxes instead of one per tile (chapel.gd `_pews`).
static func _runs(xs: Array) -> Array:
	var sx: Array = xs.duplicate()
	sx.sort()
	var runs: Array = []
	var i := 0
	while i < sx.size():
		var j := i
		while j + 1 < sx.size() and int(sx[j + 1]) == int(sx[j]) + 1:
			j += 1
		runs.append([int(sx[i]), int(sx[j])])
		i = j + 1
	return runs


static func _washers(props: Common.Props, body: StaticBody3D, lay: Dictionary, world: Callable,
		enamel: Material, chrome: Material, dark: Material, out: Dictionary) -> void:
	var mesh := _washer_mesh(enamel, chrome, dark)
	# One StaticBody3D collider per island tile (~90 of them) measured 15-20 ms of frame time
	# against every other pocket space's 9-13, everywhere in the level, not just standing in the
	# room (docs/FAILING_TESTS.md, fix-laundromat-perf): the machines are a bank bolted together, so
	# their collision is now one box per contiguous run along a row, exactly as dense as the visible
	# geometry already reads. Meshes, anchors and the per-tile placement are unchanged.
	var rows := {}   # tile.y -> Array[tile.x]
	for e in lay.islands:
		var t: Vector2i = e.tile
		var p: Vector3 = world.call(Vector2(t) + Vector2(0.5, 0.5))
		# Back-to-back: one row faces -Z, the row behind it faces +Z.
		var yaw: float = 0.0 if bool(e.flip) else PI
		var b := Basis(Vector3.UP, yaw)
		props.add(mesh, Transform3D(b, p), 40.0)
		# The tops of the island are where people put things down.
		Common.anchor(out, p + Vector3(0.0, 0.88, 0.0), yaw, "counter", "laundromat")
		if not rows.has(t.y):
			rows[t.y] = []
		(rows[t.y] as Array).append(t.x)
	for y in rows.keys():
		for run in _runs(rows[y]):
			var x0: int = run[0]
			var x1: int = run[1]
			var cx := (float(x0) + float(x1 + 1)) * 0.5
			var p: Vector3 = world.call(Vector2(cx, float(y) + 0.5))
			var width := float(x1 - x0 + 1) * T - 0.02
			# A plain AABB box is symmetric front-to-back, so the row's yaw (0 or PI) never mattered
			# to its shape; merging front- and back-facing tiles of the same run needs no basis at all.
			Common.collider(body, Transform3D(Basis(), p + Vector3(0, 0.43, 0)), Vector3(width, 0.9, 0.72))


static func _dryers(props: Common.Props, body: StaticBody3D, lay: Dictionary, world: Callable,
		enamel: Material, chrome: Material, dark: Material, out: Dictionary) -> void:
	var mesh := _dryer_mesh(enamel, chrome, dark)
	# Same fix as the washers: one collider per contiguous run along a wall instead of one per
	# dryer tile (~62 of them).
	var rows := {}   # wall.y -> {"wall": Vector2i, "tile_y": int, "xs": Array[int]}
	for e in lay.dryers:
		var wall: Vector2i = e.wall
		var t: Vector2i = e.tile
		var p: Vector3 = world.call(Vector2(t) + Vector2(0.5, 0.5))
		# Local +Z (the doors) points away from the wall.
		var yaw := atan2(float(-wall.x), float(-wall.y))
		var b := Basis(Vector3.UP, yaw)
		var at := p + Vector3(wall.x, 0, wall.y) * (T * 0.5 - 0.37)
		props.add(mesh, Transform3D(b, at), 44.0)
		var key: int = wall.y
		if not rows.has(key):
			rows[key] = {"wall": wall, "tile_y": t.y, "xs": []}
		(rows[key].xs as Array).append(t.x)
	for key in rows.keys():
		var row: Dictionary = rows[key]
		var wall: Vector2i = row.wall
		var tile_y: int = row.tile_y
		for run in _runs(row.xs):
			var x0: int = run[0]
			var x1: int = run[1]
			var cx := (float(x0) + float(x1 + 1)) * 0.5
			var p: Vector3 = world.call(Vector2(cx, float(tile_y) + 0.5))
			var at := p + Vector3(wall.x, 0, wall.y) * (T * 0.5 - 0.37)
			var width := float(x1 - x0 + 1) * T - 0.02
			Common.collider(body, Transform3D(Basis(), at + Vector3(0, 0.9, 0)), Vector3(width, 1.8, 0.74))


static func _tables(props: Common.Props, body: StaticBody3D, lay: Dictionary, world: Callable,
		steel: Material, out: Dictionary) -> void:
	var mesh := Common.cached_mesh("laun_fold_table", func():
		var mb := Common.MeshBuilder.new()
		var top := Common.mat("laun_table_top", Color(0.78, 0.76, 0.70), 0.7)
		var leg := Common.mat("laun_table_leg", Color(0.35, 0.36, 0.38), 0.5, 0.7)
		mb.box("t", top, Transform3D(Basis(), Vector3(0, 0.86, 0)), Vector3(1.4, 0.05, 0.7))
		mb.box("s", top, Transform3D(Basis(), Vector3(0, 0.81, 0)), Vector3(1.36, 0.06, 0.66))
		for lx in [-0.60, 0.60]:
			for lz in [-0.28, 0.28]:
				mb.box("l", leg, Transform3D(Basis(), Vector3(lx, 0.42, lz)), Vector3(0.05, 0.84, 0.05))
			mb.box("l", leg, Transform3D(Basis(), Vector3(lx, 0.14, 0)), Vector3(0.04, 0.04, 0.6))
		return mb.commit())
	for t: Vector2i in lay.tables:
		var p: Vector3 = world.call(Vector2(t) + Vector2(0.5, 0.5))
		props.add(mesh, Transform3D(Basis(), p), 40.0)
		Common.collider(body, Transform3D(Basis(), p + Vector3(0, 0.45, 0)), Vector3(1.4, 0.9, 0.7))
		Common.anchor(out, p + Vector3(0.36, 0.89, 0.0), 0.0, "counter", "laundromat")
		Common.anchor(out, p + Vector3(-0.36, 0.89, 0.0), PI, "counter", "laundromat")


static func _chairs(props: Common.Props, lay: Dictionary, world: Callable) -> void:
	var mesh := Common.cached_mesh("laun_chair", func():
		var mb := Common.MeshBuilder.new()
		var shell := Common.mat("laun_chair_shell", Color(0.76, 0.58, 0.16), 0.6)
		var leg := Common.mat("laun_chair_leg", Color(0.42, 0.43, 0.45), 0.4, 0.8)
		mb.box("s", shell, Transform3D(Basis(), Vector3(0, 0.44, 0)), Vector3(0.44, 0.04, 0.42))
		mb.box("s", shell, Transform3D(Basis(Vector3.RIGHT, -0.18), Vector3(0, 0.70, -0.20)), Vector3(0.42, 0.46, 0.04))
		for lx in [-0.18, 0.18]:
			for lz in [-0.17, 0.17]:
				mb.box("l", leg, Transform3D(Basis(), Vector3(lx, 0.22, lz)), Vector3(0.03, 0.44, 0.03))
		return mb.commit())
	for i in (lay.chairs as Array).size():
		var t: Vector2i = lay.chairs[i]
		var p: Vector3 = world.call(Vector2(t) + Vector2(0.5, 0.5))
		# Against the west wall, facing the machines, each one knocked a little out of line.
		var yaw := PI * 0.5 + (0.12 if i % 3 == 0 else (-0.09 if i % 3 == 1 else 0.02))
		props.add(mesh, Transform3D(Basis(Vector3.UP, yaw), p + Vector3(-T * 0.5 + 0.34, 0, 0)), 34.0)


## The change machine and the notice board by the door.
static func _front(root: Node3D, body: StaticBody3D, lay: Dictionary, world: Callable,
		enamel: Material, chrome: Material, dark: Material, out: Dictionary) -> void:
	var mb := Common.MeshBuilder.new()
	var t: Vector2i = lay.change
	var p: Vector3 = world.call(Vector2(t) + Vector2(0.5, 0.5))
	var at := p + Vector3(0, 0, -T * 0.5 + 0.28)
	mb.box("e", enamel, Transform3D(Basis(), at + Vector3(0, 0.85, 0)), Vector3(0.8, 1.70, 0.5))
	mb.box("d", dark, Transform3D(Basis(), at + Vector3(0, 1.30, 0.255)), Vector3(0.62, 0.42, 0.02))
	mb.box("c", chrome, Transform3D(Basis(), at + Vector3(0, 0.72, 0.26)), Vector3(0.30, 0.06, 0.03))
	mb.box("c", chrome, Transform3D(Basis(), at + Vector3(0, 0.50, 0.26)), Vector3(0.34, 0.14, 0.02))
	Common.collider(body, Transform3D(Basis(), at + Vector3(0, 0.85, 0)), Vector3(0.82, 1.7, 0.52))
	Common.anchor(out, at + Vector3(0.0, 1.72, 0.0), 0.0, "counter", "laundromat")
	var mi := MeshInstance3D.new()
	mi.name = "ChangeMachine"
	mi.mesh = mb.commit()
	root.add_child(mi)


## The utility room (sinks, a lint bin, the water heater) and the attendant's office (a desk).
static func _back_rooms(root: Node3D, body: StaticBody3D, lay: Dictionary, world: Callable,
		steel: Material, out: Dictionary) -> void:
	var mb := Common.MeshBuilder.new()
	# A long steel trough sink against the utility room's west wall, over exactly the SINK tiles.
	var sink_len := float(SINK.size.y) * T
	var sink_c: Vector3 = world.call(Vector2(SINK.position) + Vector2(0.5, float(SINK.size.y) * 0.5))
	var sink_at := sink_c + Vector3(-T * 0.5 + 0.32, 0.45, 0)
	mb.box("s", steel, Transform3D(Basis(), sink_at), Vector3(0.6, 0.9, sink_len))
	Common.collider(body, Transform3D(Basis(), sink_at), Vector3(0.6, 0.9, sink_len))
	Common.anchor(out, sink_at + Vector3(0.0, 0.47, 0.4), -PI * 0.5, "counter", "laundromat_back")
	# The water heater in the utility room's far corner.
	var heater: Vector3 = world.call(Vector2(UTILITY.end.x - 0.6, UTILITY.end.y - 0.6))
	mb.cylinder("s", steel, Transform3D(Basis(), heater + Vector3(0, 0.85, 0)), 0.34, 1.7, 14)
	Common.collider(body, Transform3D(Basis(), heater + Vector3(0, 0.85, 0)), Vector3(0.7, 1.7, 0.7))
	# The office desk.
	var desk_c: Vector3 = world.call(Vector2(OFFICE.get_center()) + Vector2(0.5, 0.5))
	var wood := Common.mat("laun_desk", Color(0.44, 0.32, 0.20), 0.7)
	mb.box("w", wood, Transform3D(Basis(), desk_c + Vector3(0, 0.72, 0)), Vector3(1.6, 0.06, 0.8))
	for lx in [-0.72, 0.72]:
		mb.box("w", wood, Transform3D(Basis(), desk_c + Vector3(lx, 0.35, 0)), Vector3(0.08, 0.70, 0.76))
	Common.collider(body, Transform3D(Basis(), desk_c + Vector3(0, 0.38, 0)), Vector3(1.6, 0.76, 0.8))
	Common.anchor(out, desk_c + Vector3(0.4, 0.76, 0.0), 0.0, "counter", "laundromat_back")
	Common.anchor(out, desk_c + Vector3(-0.4, 0.76, 0.0), PI, "counter", "laundromat_back")
	var mi := MeshInstance3D.new()
	mi.name = "BackRooms"
	mi.mesh = mb.commit()
	root.add_child(mi)


static func _signs(root: Node3D, lay: Dictionary, world: Callable) -> void:
	# The price list over the change machine, and the house rules nobody reads.
	var t: Vector2i = lay.change
	var board := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(1.5, 0.5)
	board.mesh = qm
	var sm := StandardMaterial3D.new()
	var tex := Common.text_texture("WASH 2.25  *  DRY .25 / 8 MIN", Color(0.10, 0.16, 0.30), Color(0.93, 0.92, 0.86), 512, 96)
	sm.albedo_texture = tex
	sm.roughness = 0.85
	board.material_override = sm
	board.position = world.call(Vector2(t) + Vector2(0.5, 0.06), 2.25)
	root.add_child(board)
	var rules := MeshInstance3D.new()
	var rq := QuadMesh.new()
	rq.size = Vector2(1.1, 0.7)
	rules.mesh = rq
	var rm := StandardMaterial3D.new()
	rm.albedo_texture = Common.text_texture("NOT RESPONSIBLE FOR ITEMS LEFT", Color(0.20, 0.20, 0.20), Color(0.88, 0.87, 0.82), 384, 192)
	rm.roughness = 0.9
	rules.material_override = rm
	rules.position = world.call(Vector2(MAIN.position.x + 0.04, TABLE_Y + 0.5), 1.9)
	rules.rotation.y = PI * 0.5
	root.add_child(rules)
	# ATTENDANT, over the office door.
	var door: Vector2i = lay.doors.office
	var sign := MeshInstance3D.new()
	var dq := QuadMesh.new()
	dq.size = Vector2(0.8, 0.22)
	sign.mesh = dq
	var dm := StandardMaterial3D.new()
	dm.albedo_texture = Common.text_texture("ATTENDANT", Color(0.92, 0.90, 0.84), Color(0.16, 0.26, 0.34), 256, 72)
	sign.material_override = dm
	sign.position = world.call(Vector2(door.x + 0.5, door.y - 0.02), 2.55)
	sign.rotation.y = PI
	root.add_child(sign)


static func _lights(root: Node3D, lay: Dictionary, world: Callable, out: Dictionary) -> void:
	var lights := Node3D.new()
	lights.name = "Lights"
	root.add_child(lights)
	var cool := Color(0.90, 0.96, 1.0)
	var tube := Common.cached_mesh("laun_tube", func():
		var mb := Common.MeshBuilder.new()
		var housing := Common.mat("laun_housing", Color(0.80, 0.81, 0.80), 0.5, 0.3)
		var glow := Common.mat("laun_tube_glow", Color(0.92, 0.97, 1.0), 0.25, 0.0, Color(0.88, 0.96, 1.0), 3.2)
		mb.box("h", housing, Transform3D(Basis(), Vector3(0, 0.08, 0)), Vector3(0.26, 0.09, 2.3))
		mb.box("g", glow, Transform3D(Basis(), Vector3(0, 0.01, 0)), Vector3(0.20, 0.03, 2.2))
		return mb.commit())
	# Rows of twin tubes over the main floor. One in six buzzes and blinks (mode 1).
	var i := 0
	for t: Vector2i in lay.lamps:
		var p: Vector3 = world.call(Vector2(t) + Vector2(0.5, 0.5), CEIL - 0.12)
		var mode := 1 if i % 6 == 5 else 0
		var node := Common.omni(lights, p - Vector3(0, 0.1, 0), 2.1, 12.0, cool, 0.3, false, 0.9)
		var mi := MeshInstance3D.new()
		mi.mesh = tube
		mi.position = Vector3(0, 0.1, 0)
		node.add_child(mi)
		out.lights.append({"tile": t, "position": p, "mode": mode, "node": node, "pocket": "laundromat"})
		i += 1
	for r: Rect2i in [UTILITY, OFFICE]:
		var p: Vector3 = world.call(Vector2(r.get_center()) + Vector2(0.5, 0.5), BACK_CEIL - 0.12)
		var node := Common.omni(lights, p, 1.35, 8.0, Color(0.95, 0.96, 0.92), 0.35)
		var mi := MeshInstance3D.new()
		mi.mesh = tube
		mi.position = Vector3(0, 0.05, 0)
		node.add_child(mi)
		out.lights.append({"tile": r.position, "position": p, "mode": 0, "node": node, "pocket": "laundromat"})
