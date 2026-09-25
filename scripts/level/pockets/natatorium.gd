extends RefCounted
## POCKETS: the Natatorium. A full Olympic pool inside a one-story hospital: fifty metres of still
## water under a ceiling nine and a half metres up, every underwater light on, lane ropes strung and
## never swum between, backstroke flags, ten starting blocks, a bank of bleachers nobody sat in and
## two lifeguard stands nobody climbed. Bare tile everywhere, so it rings.
##
## The point of the room is the water. Crossing the pool is the short way between two entrances; the
## dry deck around it is the long way. The water is the loud way: a footstep taken in it is worth
## several times a footstep on the deck (see `water_rect` and scripts/player.gd's footstep noise), so
## the shortcut is bought with the one currency the Sonographer spends. The room itself is quiet —
## AMBIENT_NOISE_LEVEL is 0.0 — because tile echo is atmosphere, not masking; the Laundromat is the
## space that masks. Nothing here is a new sound system: it is the loudness numbers that already exist.
##
## layout, prepare, build_steps, build and the doorways as in factory.gd.

const Common := preload("res://scripts/level/pockets/pocket_common.gd")
const Stub := preload("res://scripts/level/pockets/stub.gd")

## POCKETS 2 phase 1: the ambient noise floor a sound-hunting monster stands in here (see
## PocketSpaces.ambient_noise_at). Tile echo is what the room sounds like, not what it hides behind:
## the Natatorium masks nothing, so monsters hear here exactly what they hear in the hospital, and
## the water's loudness is a real cost rather than one the room quietly refunds.
const AMBIENT_NOISE_LEVEL := 0.0

## POCKETS 2: the item kinds this space contributes, as a set anything else can read without digging
## through the layout below. The follow-up task that bleeds a pocket's items into the hospital rooms
## near its entrances reads this; so does anything that wants to know what a space is worth.
const POCKET_ITEMS := ["pool_chemical_drum", "lifeguard_whistle"]

const T := 1.5
const M := 10
const RW := 48
const RH := 31
const CEIL := 9.5
const LOCKER_CEIL := 3.0
const TRUSS_Y := 8.2

## Hall interior (deck and water): x 11..58, y 11..41.
const HALL := Rect2i(M + 1, M + 1, RW, RH)
## The water: 34 x 17 tiles = 51 x 25.5 m, an Olympic pool with seven tiles of deck all round.
const POOL := Rect2i(M + 8, M + 8, 34, 17)
## Bleachers along the west deck, so entrances never open behind them.
const BLEACHERS := Rect2i(M + 1, M + 4, 3, RH - 6)
## The locker room, through a doorway in the south wall. It starts on the row directly past that
## wall (HALL.end.y is the wall row, so the room's first row is the next one): leave a gap and the
## doorway opens onto solid ground.
const LOCKERS := Rect2i(M + 3, M + RH + 2, 13, 6)
const LOCKER_DOOR := Vector2i(M + 5, M + RH + 1)

## Water surface, metres above the deck. Stays an absolute height above deck level (not above the
## basin floor) so the coping, ropes and blocks -- all built at deck height -- don't have to move.
const WATER_Y := 0.34
const LANE_W := 2.55

## The basin: real depth below the deck, not much. C.JUMP_VELOCITY (5.2) against gravity (18.0)
## gives a jump apex of v^2/(2g) = 0.75 m (matches the estimate in economy/furnace.gd's SILL
## comment) -- POOL_DEPTH sits well under half that, so climbing out from the basin floor clears
## the lip with room to spare rather than demanding a precise jump. You wade, you do not swim: the
## drop is a step down and a hop up, not a platforming challenge.
const POOL_DEPTH := 0.4


static func layout(stubs: Array, seed: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var g := Common.new_grid(HALL.end.x + M + 1, LOCKERS.end.y + M + 1)
	var deck := Common.add_room(g, {"name": "deck", "ceil": CEIL, "floor": "deck_tile", "ceiling": "roof",
			"wall": "wall_up", "wall_low": "pool_tile_wall", "split": 2.4, "uv": 2.0, "place": "natatorium_deck"})
	# No "floor" key: the shared grid pipeline (Common.build_surfaces) draws every room's floor
	# flat at y=0, and the basin's is sunk POOL_DEPTH below that, so it can't come from the grid.
	# _basin() draws it by hand, in the same "pool_floor" material this room still registers below.
	var water := Common.add_room(g, {"name": "water", "ceil": CEIL, "ceiling": "roof",
			"wall": "wall_up", "wall_low": "pool_tile_wall", "split": 2.4, "uv": LANE_W, "place": "natatorium_pool"})
	var lockers := Common.add_room(g, {"name": "lockers", "ceil": LOCKER_CEIL, "floor": "locker_floor",
			"ceiling": "locker_ceiling", "wall": "locker_wall", "wall_low": "", "split": 0.0, "place": "natatorium_lockers"})
	Common.carve(g, HALL, deck)
	Common.carve(g, POOL, water)
	Common.carve(g, LOCKERS, lockers)
	Common.set_open(g, LOCKER_DOOR.x, LOCKER_DOOR.y, lockers)
	# The bleachers are furniture, not floor: nothing walks them and no entrance opens behind them.
	_block(g, BLEACHERS)
	Common.reserve(g, BLEACHERS.grow(1))
	Common.reserve(g, Rect2i(LOCKER_DOOR.x - 2, HALL.end.y - 3, 5, 4))
	# The basin is a real drop now (build_steps/_basin): a pit nothing paths through, only the
	# player steps into, so it comes out of the navigation mesh the same way the bleachers do.
	_block(g, POOL)

	# Entrances go on the north, south and east walls; the west wall is the bleachers' back.
	var walls := [
		{"from": Vector2i(M + 4, M), "dir": Vector2i(1, 0), "len": RW - 6, "ev": Vector2i(0, -1)},
		{"from": Vector2i(HALL.end.x, M + 4), "dir": Vector2i(0, 1), "len": RH - 6, "ev": Vector2i(1, 0)},
		{"from": Vector2i(M + 4, HALL.end.y), "dir": Vector2i(1, 0), "len": RW - 6, "ev": Vector2i(0, 1)},
	]
	var ports := Common.place_ports(g, stubs, walls, rng)

	# Ten lanes across the short axis, their ropes on the nine boundaries between them.
	var lanes := 10
	var ropes: Array = []
	for i in range(1, lanes):
		ropes.append(float(POOL.position.y) + float(POOL.size.y) * float(i) / float(lanes))
	# Starting blocks on the east deck, one per lane, plus the backstroke flag lines.
	var blocks: Array = []
	for i in lanes:
		blocks.append(float(POOL.position.y) + float(POOL.size.y) * (float(i) + 0.5) / float(lanes))
	var flags := [float(POOL.position.x) + 3.4, float(POOL.end.x) - 3.4]

	# Two lifeguard stands facing the water down the long sides; the first-aid cabinet is bolted to
	# the north one's legs, which is why that stand stands where an entrance never does.
	var stands := [
		{"tile": Vector2i(POOL.get_center().x - 6, POOL.position.y - 2), "yaw": 0.0},
		{"tile": Vector2i(POOL.get_center().x + 6, POOL.end.y + 1), "yaw": PI},
	]
	for s in stands:
		_block(g, Rect2i(s.tile, Vector2i.ONE))
		Common.reserve(g, Rect2i(s.tile, Vector2i.ONE).grow(1))

	# The chemical store: drums stacked in the south-east corner of the deck. They hug the two walls
	# in single lines rather than filling the corner, because a blob of blocked tiles in a corner can
	# fence off the deck behind it and strand a slice of the room (mapcheck caught exactly that).
	# A line pressed against a wall can never enclose anything.
	var store := Rect2i(HALL.end.x - 7, HALL.end.y - 7, 6, 6)
	var drums: Array = []
	var run: Array = []
	for x in range(store.position.x, HALL.end.x):
		run.append(Vector2i(x, HALL.end.y - 1))
	for y in range(store.position.y, HALL.end.y - 1):
		run.append(Vector2i(HALL.end.x - 1, y))
	# The one tile the two lines meet at always takes a drum. Leave it to the gap roll and the corner
	# can end up open with a drum on each side of it: the only tile two wall-hugging lines can strand.
	var corner := Vector2i(HALL.end.x - 1, HALL.end.y - 1)
	for t: Vector2i in run:
		if (rng.randf() < 0.22 and t != corner) or not _free(g, Rect2i(t, Vector2i.ONE)):
			continue   # gaps, so it reads as stacked stock rather than a second wall
		drums.append({"tile": t, "stack": rng.randi_range(1, 2), "yaw": rng.randf_range(-0.4, 0.4)})
		_block(g, Rect2i(t, Vector2i.ONE))

	# Benches and lockers in the locker room.
	var benches: Array = []
	for x in range(LOCKERS.position.x + 2, LOCKERS.end.x - 2, 4):
		var r := Rect2i(x, LOCKERS.get_center().y, 2, 1)
		if _free(g, r):
			benches.append(r)
			_block(g, r)

	var containers := [
		{"tile": stands[0].tile + Vector2i(1, 0), "wall": Vector2i(0, -1), "type": "first_aid_cabinet", "room": "natatorium_deck"},
		{"tile": Vector2i(HALL.position.x + 4, HALL.position.y), "wall": Vector2i(0, -1), "type": "pegboard", "room": "natatorium_deck"},
		{"tile": Vector2i(HALL.end.x - 1, HALL.position.y + 3), "wall": Vector2i(1, 0), "type": "drawer_unit", "room": "natatorium_deck"},
		{"tile": Vector2i(LOCKERS.end.x - 1, LOCKERS.position.y + 1), "wall": Vector2i(1, 0), "type": "drawer_unit", "room": "natatorium_lockers"},
		{"tile": Vector2i(LOCKERS.position.x, LOCKERS.end.y - 2), "wall": Vector2i(-1, 0), "type": "trauma_bag", "room": "natatorium_lockers"},
	]
	for c in containers:
		if c.type != "trauma_bag" and c.type != "pegboard":
			_block(g, Rect2i(c.tile, Vector2i.ONE))
		Common.reserve(g, Rect2i(c.tile, Vector2i.ONE))

	# High bays over the deck; the water is lit from under it instead.
	var lamps: Array = []
	for ly in range(HALL.position.y + 4, HALL.end.y - 2, 9):
		for lx in range(HALL.position.x + 5, HALL.end.x - 2, 10):
			lamps.append(Vector2i(lx, ly))
	# Underwater lights, set into the pool's long walls just below the surface.
	var underwater: Array = []
	for x in range(POOL.position.x + 2, POOL.end.x - 1, 4):
		underwater.append(Vector2(float(x) + 0.5, float(POOL.position.y) + 0.6))
		underwater.append(Vector2(float(x) + 0.5, float(POOL.end.y) - 0.6))

	# The second spot used to be the pool's own centre; now that the basin is out of the nav mesh
	# (see _block(g, POOL) above) a spawn there would strand whatever spawns on it, so it sits on
	# the deck just north of the pool instead -- central to the room, same as before.
	var spawns := [Vector2i(HALL.position.x + 5, HALL.position.y + 2), Vector2i(POOL.get_center().x, POOL.position.y - 3),
			Vector2i(HALL.end.x - 3, HALL.end.y - 8), Vector2i(LOCKERS.get_center().x, LOCKERS.get_center().y)]
	return {"kind": "natatorium", "size": Vector2i(g.w, g.h), "grid": g, "rows": Common.rows(g), "ports": ports,
			"ropes": ropes, "blocks": blocks, "flags": flags, "stands": stands, "drums": drums, "store": store,
			"benches": benches, "containers": containers, "lamps": lamps, "underwater": underwater,
			"spawns": spawns, "doors": {"lockers": LOCKER_DOOR},
			"spawn": Vector2i(HALL.position.x + 4, HALL.get_center().y)}


## The water, in pocket-local tiles. The room's one mechanic hangs off this rect (PocketSpaces.
## water_at), so it lives next to the layout rather than inside the geometry.
static func water_rect() -> Rect2i:
	return POOL


static func _free(g: Dictionary, r: Rect2i) -> bool:
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			if not Common.is_open(g, x, y):
				return false
			var i := Common.idx(g, x, y)
			if g.reserved[i] == 1 or g.nav[i] == 1 or g.stub[i] == 1:
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

static func prepare(lay: Dictionary, origin: Vector2i) -> Dictionary:
	var geo := Common.Geo.new()
	var nav := PackedVector3Array()
	Common.build_surfaces(lay.grid, origin, geo, nav)
	Common.lintels(lay.grid, origin, geo, doorways(lay))
	geo.bake()
	return {"geo": geo, "nav_faces": nav}


static func build(lay: Dictionary, origin: Vector2i, out: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = "Natatorium"
	var prep := prepare(lay, origin)
	out.nav_faces.append_array(prep.nav_faces)
	Common.run_steps(build_steps(lay, origin, out, root, prep))
	return root


static func build_steps(lay: Dictionary, origin: Vector2i, out: Dictionary, root: Node3D, prep: Dictionary) -> Array:
	var ow := Vector3(origin.x * T, 0.0, origin.y * T)
	var world := func(t: Vector2, y := 0.0) -> Vector3:
		return ow + Vector3(t.x * T, y, t.y * T)
	var ctx := {}
	var steps: Array = []
	var geo: Common.Geo = prep.geo
	var props := Common.Props.new()
	var steel := Common.tri_mat("nat_steel", "mat/metal", Color(0.66, 0.68, 0.70), 1.2, 0.35, 0.9)
	var paint := Common.mat("nat_paint", Color(0.82, 0.84, 0.85), 0.55)
	var rubber := Common.mat("nat_rubber", Color(0.10, 0.11, 0.12), 0.9)

	steps.append(func():
		geo.mats["deck_tile"] = _tex_mat("deck_tile", _deck_tex(), 0.45, Vector3(0.5, 0.5, 1))
		geo.mats["pool_floor"] = _tex_mat("pool_floor", _lane_tex(), 0.25, Vector3.ONE)
		geo.mats["pool_tile_wall"] = _tex_mat("pool_wall", _wall_tile_tex(), 0.3, Vector3(0.5, 0.5, 1))
		geo.mats["wall_up"] = Common.tri_mat("nat_wall_up", "mat/wall", Color(0.70, 0.74, 0.76), 0.3, 0.9)
		geo.mats["roof"] = Common.tri_mat("nat_roof", "mat/ceiling", Color(0.22, 0.24, 0.26), 0.5, 0.95)
		geo.mats["locker_floor"] = Common.tri_mat("nat_lfloor", "mat/tile_floor", Color(0.52, 0.56, 0.58), 0.6, 0.6)
		geo.mats["locker_ceiling"] = Common.HB.surface_mat("mat/ceiling", Color(0.30, 0.32, 0.33), 0.95)
		geo.mats["locker_wall"] = Common.tri_mat("nat_lwall", "mat/wall_tile", Color(0.60, 0.70, 0.72), 0.5, 0.45)
		return geo.commit_steps(root, ctx))
	steps.append(func():
		var body: StaticBody3D = ctx.body
		var to_rect := func(r: Rect2i) -> Rect2:
			return Rect2(Vector2(r.position) * T + Vector2(ow.x, ow.z), Vector2(r.size) * T)
		var inter: Rect2 = to_rect.call(HALL)
		Common.collider(body, Transform3D(Basis(), Vector3(inter.get_center().x, CEIL + 0.2, inter.get_center().y)), Vector3(inter.size.x, 0.4, inter.size.y))
		# The deck floor as a ring around the basin (HALL minus POOL): four slabs, none overlapping,
		# each covering its own slice the way the north/south/west/east strips of a picture frame do.
		var ring := [
			Rect2i(HALL.position.x, HALL.position.y, HALL.size.x, POOL.position.y - HALL.position.y),
			Rect2i(HALL.position.x, POOL.end.y, HALL.size.x, HALL.end.y - POOL.end.y),
			Rect2i(HALL.position.x, POOL.position.y, POOL.position.x - HALL.position.x, POOL.size.y),
			Rect2i(POOL.end.x, POOL.position.y, HALL.end.x - POOL.end.x, POOL.size.y),
		]
		for r: Rect2i in ring:
			var wr: Rect2 = to_rect.call(r)
			Common.collider(body, Transform3D(Basis(), Vector3(wr.get_center().x, -0.2, wr.get_center().y)), Vector3(wr.size.x, 0.4, wr.size.y))
		# The basin floor, POOL_DEPTH below the deck.
		var pr: Rect2 = to_rect.call(POOL)
		Common.collider(body, Transform3D(Basis(), Vector3(pr.get_center().x, -POOL_DEPTH - 0.2, pr.get_center().y)), Vector3(pr.size.x, 0.4, pr.size.y))
		# The basin walls: a sheer drop all round (well past player.gd's floor_max_angle, so it
		# reads as a wall, not a slope you can walk up), flush with the deck at the top so walking
		# toward the pool never catches on a lip -- you only fall in once you're past the edge.
		var wall_t := 0.2
		for side in [-1, 1]:
			Common.collider(body, Transform3D(Basis(), Vector3(pr.get_center().x, -POOL_DEPTH * 0.5, pr.position.y if side < 0 else pr.end.y)), Vector3(pr.size.x, POOL_DEPTH, wall_t))
			Common.collider(body, Transform3D(Basis(), Vector3(pr.position.x if side < 0 else pr.end.x, -POOL_DEPTH * 0.5, pr.get_center().y)), Vector3(wall_t, POOL_DEPTH, pr.size.y)))
	steps.append(func(): _water(root, lay, world))
	steps.append(func(): _basin(root, world, geo))
	steps.append(func(): _coping(root, world, paint))
	steps.append(func(): _ropes(props, lay, world))
	steps.append(func(): _flags(root, props, lay, world, steel))
	steps.append(func(): _blocks(props, ctx.body, lay, world, out))
	steps.append(func(): _bleachers(root, ctx.body, world, paint, rubber))
	steps.append(func(): _stands(root, ctx.body, lay, world, steel, out))
	steps.append(func(): _store(props, ctx.body, lay, world, out))
	steps.append(func(): _lockers(root, ctx.body, lay, world, steel, paint, out))
	steps.append(func(): _trusses(props, world, steel))
	steps.append(func(): _signs(root, world))
	steps.append(func(): _lights(root, lay, world, out))

	var cts := Node3D.new()
	cts.name = "Containers"
	steps.append(func(): root.add_child(cts))
	for c in lay.containers:
		steps.append(func(): Common.container(cts, out, origin, c.tile, c.wall, c.type, c.room))
	steps.append(func():
		for s: Vector2i in lay.spawns:
			out.monster_spawns.append(world.call(Vector2(s) + Vector2(0.5, 0.5)))
		out["spawn"] = world.call(Vector2(lay.spawn) + Vector2(0.5, 0.5))
		return props.commit_steps(root))
	return steps


static func doorways(lay: Dictionary) -> Array:
	return [{"tiles": [lay.doors.lockers], "n": Vector2i(0, -1), "kind": "hinged"}]


static func door_entries(lay: Dictionary, origin: Vector2i) -> Array:
	var out: Array = []
	for dw in doorways(lay):
		out.append(Common.door_entry(origin, dw.tiles, dw.n, dw.kind, 90.0))
	return out


# ---- materials and textures -------------------------------------------------

static func _tex_mat(key: String, tex: Texture2D, rough: float, scale: Vector3) -> Material:
	var ck := "nat_" + key
	if Common._mat_cache.has(ck):
		return Common._mat_cache[ck]
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	m.roughness = rough
	m.metallic = 0.05
	m.uv1_scale = scale
	Common._mat_cache[ck] = m
	return m


## Small pale deck tiles, wet-looking, with darker grout.
static func _deck_tex() -> Texture2D:
	return Common.cached_texture("nat_deck", func():
		var n := 128
		var img := Image.create(n, n, true, Image.FORMAT_RGB8)
		for y in n:
			for x in n:
				var lx := x % 16
				var ly := y % 16
				var grout := lx < 2 or ly < 2
				var c := Color(0.50, 0.55, 0.56) if grout else Color(0.74, 0.78, 0.78)
				var speck := sin(float(x * 12.9898 + y * 78.233)) * 43758.5453
				img.set_pixel(x, y, c.darkened((speck - floor(speck)) * 0.08))
		img.generate_mipmaps()
		return ImageTexture.create_from_image(img))


## One lane of the pool floor: pale blue tile, the black lane line down its middle with the cross-bar
## ends, repeated every LANE_W metres across the short axis.
static func _lane_tex() -> Texture2D:
	return Common.cached_texture("nat_lane", func():
		var n := 128
		var img := Image.create(n, n, true, Image.FORMAT_RGB8)
		var tile := Color(0.62, 0.80, 0.84)
		var grout := Color(0.46, 0.62, 0.66)
		var line := Color(0.06, 0.09, 0.12)
		for y in n:
			for x in n:
				var c := grout if (x % 16 < 2 or y % 16 < 2) else tile
				if absi(y - n / 2) < 7:
					c = line
				img.set_pixel(x, y, c)
		img.generate_mipmaps()
		return ImageTexture.create_from_image(img))


static func _wall_tile_tex() -> Texture2D:
	return Common.cached_texture("nat_walltile", func():
		var n := 128
		var img := Image.create(n, n, true, Image.FORMAT_RGB8)
		for y in n:
			for x in n:
				var grout := (x % 21) < 2 or (y % 13) < 2
				var c := Color(0.48, 0.60, 0.63) if grout else Color(0.80, 0.86, 0.87)
				img.set_pixel(x, y, c)
		img.generate_mipmaps()
		return ImageTexture.create_from_image(img))


# ---- the water ---------------------------------------------------------------

## The surface: one still, translucent plane over the whole pool, lit from beneath. No collider —
## the basin underneath is what you actually stand on (see _basin); this plane is purely the look
## of the water, unmoved by how deep the basin below it is.
static func _water(root: Node3D, _lay: Dictionary, world: Callable) -> void:
	var a: Vector3 = world.call(Vector2(POOL.position), WATER_Y)
	var size := Vector2(POOL.size) * T
	var mi := MeshInstance3D.new()
	mi.name = "Water"
	var pm := PlaneMesh.new()
	pm.size = size
	pm.subdivide_width = 8
	pm.subdivide_depth = 4
	mi.mesh = pm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.14, 0.52, 0.58, 0.62)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = 0.06
	m.metallic = 0.25
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.emission_enabled = true
	m.emission = Color(0.18, 0.60, 0.66)
	m.emission_energy_multiplier = 0.35
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = a + Vector3(size.x * 0.5, 0.0, size.y * 0.5)
	root.add_child(mi)


## The basin: the pool floor sunk POOL_DEPTH below the deck, closed in on all four sides by real
## walls (their collision is built alongside the deck's own, in build_steps). Common.build_surfaces
## draws every room's floor flat at y=0 with no way to sink one room relative to its neighbours (see
## pocket_common.gd), so this is bespoke geometry layered into the water room's footprint instead of
## grid-driven -- the same kind of one-off the coping and bleachers already are. Reuses the water
## room's own floor and wall-tile materials (registered in build_steps' first step) so it reads as
## the same tile, just lower.
static func _basin(root: Node3D, world: Callable, geo: Common.Geo) -> void:
	var mb := Common.MeshBuilder.new()
	var floor_mat: Material = geo.mats.get("pool_floor")
	var wall_mat: Material = geo.mats.get("pool_tile_wall")
	var a: Vector3 = world.call(Vector2(POOL.position))
	var b: Vector3 = world.call(Vector2(POOL.end))
	var cx := (a.x + b.x) * 0.5
	var cz := (a.z + b.z) * 0.5
	var w := b.x - a.x
	var d := b.z - a.z
	# The walls stand just INSIDE the pool's edge, outer faces on it, and the floor fits between them.
	# Centred on the edge, the outer half of each wall's top lay in the deck floor's own plane at y = 0
	# and fought it for the pixels (only the coping hid it). No two faces here share a plane now.
	var t := 0.05
	mb.box("f", floor_mat, Transform3D(Basis(), Vector3(cx, -POOL_DEPTH, cz)), Vector3(w - t * 2.0, 0.02, d - t * 2.0))
	for side in [-1, 1]:
		mb.box("w", wall_mat, Transform3D(Basis(), Vector3(cx, -POOL_DEPTH * 0.5, (a.z + t * 0.5) if side < 0 else (b.z - t * 0.5))), Vector3(w, POOL_DEPTH, t))
		mb.box("w", wall_mat, Transform3D(Basis(), Vector3((a.x + t * 0.5) if side < 0 else (b.x - t * 0.5), -POOL_DEPTH * 0.5, cz)), Vector3(t, POOL_DEPTH, d - t * 2.0))
	var mi := MeshInstance3D.new()
	mi.name = "Basin"
	mi.mesh = mb.commit()
	root.add_child(mi)


## The coping: the raised tiled lip around the pool. Purely cosmetic (no collider of its own,
## unchanged since before the basin had depth) -- it sits right where the deck floor meets the top
## of the basin wall (_basin's colliders, built in build_steps), so it now caps a real ledge instead
## of just implying one.
static func _coping(root: Node3D, world: Callable, paint: Material) -> void:
	var mb := Common.MeshBuilder.new()
	var a: Vector3 = world.call(Vector2(POOL.position))
	var b: Vector3 = world.call(Vector2(POOL.end))
	var cx := (a.x + b.x) * 0.5
	var cz := (a.z + b.z) * 0.5
	# The long sides run corner to corner and the short sides fit between them: butted, not
	# overlapped, so no two faces of the lip share a plane (fix-pocket-zfighting).
	for side in [-1, 1]:
		mb.box("c", paint, Transform3D(Basis(), Vector3(cx, 0.07, a.z if side < 0 else b.z)), Vector3(b.x - a.x + 0.3, 0.14, 0.3))
		mb.box("c", paint, Transform3D(Basis(), Vector3(a.x if side < 0 else b.x, 0.07, cz)), Vector3(0.3, 0.14, b.z - a.z - 0.3))
	var mi := MeshInstance3D.new()
	mi.name = "Coping"
	mi.mesh = mb.commit()
	root.add_child(mi)


## Lane ropes: strings of floats on the nine lane boundaries, a segment per tile.
static func _ropes(props: Common.Props, lay: Dictionary, world: Callable) -> void:
	var cols := [[Color(0.78, 0.10, 0.10), "r"], [Color(0.88, 0.88, 0.86), "w"], [Color(0.10, 0.24, 0.62), "b"]]
	var seg: Array = []
	for ci in cols.size():
		seg.append(Common.cached_mesh("nat_rope_%s" % cols[ci][1], func():
			var mb := Common.MeshBuilder.new()
			var m := Common.mat("nat_float_%s" % cols[ci][1], cols[ci][0], 0.5)
			for k in 5:
				mb.cylinder("f", m, Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(0.0, 0.0, -0.6 + k * 0.3)), 0.075, 0.24, 8)
			return mb.commit()))
	var k := 0
	for rz: float in lay.ropes:
		for x in range(POOL.position.x, POOL.end.x):
			var p: Vector3 = world.call(Vector2(float(x) + 0.5, rz), WATER_Y + 0.02)
			props.add(seg[k % seg.size()], Transform3D(Basis(Vector3.UP, PI * 0.5), p), 60.0, false)
			k += 1


## Backstroke flags: two lines of pennants on poles, five metres in from each end.
static func _flags(root: Node3D, props: Common.Props, lay: Dictionary, world: Callable, steel: Material) -> void:
	var mb := Common.MeshBuilder.new()
	var cols := [Color(0.85, 0.15, 0.12), Color(0.95, 0.72, 0.10), Color(0.12, 0.40, 0.72), Color(0.90, 0.90, 0.86)]
	var pennants: Array = []
	for ci in cols.size():
		pennants.append(Common.cached_mesh("nat_pennant_%d" % ci, func():
			var pmb := Common.MeshBuilder.new()
			var m := Common.mat("nat_pennant_%d" % ci, cols[ci], 0.9)
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
			pmb.box("p", m, Transform3D(Basis(), Vector3(0, -0.13, 0)), Vector3(0.2, 0.28, 0.004))
			return pmb.commit()))
	var k := 0
	for fx: float in lay.flags:
		var z0: float = world.call(Vector2(0, POOL.position.y - 1)).z
		var z1: float = world.call(Vector2(0, POOL.end.y + 1)).z
		var x: float = world.call(Vector2(fx, 0)).x
		for z in [z0, z1]:
			mb.cylinder("s", steel, Transform3D(Basis(), Vector3(x, 1.3, z)), 0.04, 2.6, 8)
		var z := z0 + 0.4
		while z < z1 - 0.2:
			var sag := sin((z - z0) / (z1 - z0) * PI) * 0.16
			props.add(pennants[k % pennants.size()], Transform3D(Basis(), Vector3(x, 2.5 - sag, z)), 40.0, false)
			z += 0.4
			k += 1
	var mi := MeshInstance3D.new()
	mi.name = "FlagPoles"
	mi.mesh = mb.commit()
	root.add_child(mi)


## Ten starting blocks on the east deck, one squared up to each lane.
static func _blocks(props: Common.Props, body: StaticBody3D, lay: Dictionary, world: Callable, out: Dictionary) -> void:
	var block := Common.cached_mesh("nat_block", func():
		var mb := Common.MeshBuilder.new()
		var top := Common.mat("nat_block_top", Color(0.14, 0.16, 0.18), 0.85)
		var base := Common.mat("nat_block_base", Color(0.80, 0.82, 0.84), 0.5, 0.2)
		var steel := Common.mat("nat_block_steel", Color(0.68, 0.70, 0.72), 0.35, 0.9)
		mb.box("b", base, Transform3D(Basis(), Vector3(0, 0.3, 0)), Vector3(0.6, 0.6, 0.6))
		mb.box("t", top, Transform3D(Basis(Vector3.RIGHT, -0.12), Vector3(0, 0.63, 0)), Vector3(0.62, 0.05, 0.66))
		mb.cylinder("s", steel, Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(0, 0.78, -0.2)), 0.02, 0.5, 6)
		return mb.commit())
	for bz: float in lay.blocks:
		var p: Vector3 = world.call(Vector2(float(POOL.end.x) + 0.45, bz))
		var b := Basis(Vector3.UP, -PI * 0.5)
		props.add(block, Transform3D(b, p), 50.0)
		Common.collider(body, Transform3D(b, p + Vector3(0, 0.32, 0)), Vector3(0.6, 0.64, 0.6))
		Common.anchor(out, p + Vector3(0, 0.66, 0), -PI * 0.5, "counter", "natatorium_deck")


## Three rows of bleachers down the west wall, the seats folded down and empty.
static func _bleachers(root: Node3D, body: StaticBody3D, world: Callable, paint: Material, rubber: Material) -> void:
	var mb := Common.MeshBuilder.new()
	var z0: float = world.call(Vector2(0, BLEACHERS.position.y)).z
	var z1: float = world.call(Vector2(0, BLEACHERS.end.y)).z
	for k in 3:
		var x: float = world.call(Vector2(float(BLEACHERS.position.x) + 0.5 + float(k), 0)).x
		var h := 0.45 + k * 0.45
		mb.box("r", rubber, Transform3D(Basis(), Vector3(x, h * 0.5, (z0 + z1) * 0.5)), Vector3(T, h, z1 - z0))
		mb.box("p", paint, Transform3D(Basis(), Vector3(x, h + 0.03, (z0 + z1) * 0.5)), Vector3(T - 0.1, 0.06, z1 - z0 - 0.1))
		Common.collider(body, Transform3D(Basis(), Vector3(x, h * 0.5, (z0 + z1) * 0.5)), Vector3(T, h, z1 - z0))
	var mi := MeshInstance3D.new()
	mi.name = "Bleachers"
	mi.mesh = mb.commit()
	root.add_child(mi)


## The lifeguard stands: a tall chair on four legs, a ladder up one side, facing the water.
static func _stands(root: Node3D, body: StaticBody3D, lay: Dictionary, world: Callable, steel: Material, out: Dictionary) -> void:
	var stand := Common.cached_mesh("nat_stand", func():
		var mb := Common.MeshBuilder.new()
		var white := Common.mat("nat_stand_white", Color(0.88, 0.89, 0.88), 0.5, 0.6)
		var seat := Common.mat("nat_stand_seat", Color(0.80, 0.30, 0.10), 0.7)
		for sx in [-0.38, 0.38]:
			for sz in [-0.34, 0.34]:
				mb.box("w", white, Transform3D(Basis(), Vector3(sx, 1.0, sz)), Vector3(0.07, 2.0, 0.07))
		mb.box("s", seat, Transform3D(Basis(), Vector3(0, 2.02, 0)), Vector3(0.86, 0.07, 0.76))
		mb.box("s", seat, Transform3D(Basis(), Vector3(0, 2.38, -0.36)), Vector3(0.86, 0.7, 0.07))
		for sx in [-0.42, 0.42]:
			mb.box("w", white, Transform3D(Basis(), Vector3(sx, 2.3, 0.1)), Vector3(0.05, 0.5, 0.05))
		for k in 4:
			mb.box("w", white, Transform3D(Basis(), Vector3(0, 0.42 + k * 0.42, 0.36)), Vector3(0.7, 0.05, 0.05))
		return mb.commit())
	for s in lay.stands:
		var p: Vector3 = world.call(Vector2(s.tile) + Vector2(0.5, 0.5))
		var b := Basis(Vector3.UP, float(s.yaw))
		var mi := MeshInstance3D.new()
		mi.mesh = stand
		mi.transform = Transform3D(b, p)
		root.add_child(mi)
		Common.collider(body, Transform3D(b, p + Vector3(0, 1.1, 0)), Vector3(0.9, 2.2, 0.8))
		Common.anchor(out, p + b * Vector3(0.0, 2.1, 0.1), float(s.yaw), "counter", "natatorium_deck")


## The chemical store: stacked drums in the south-east corner, and the anchors on top of them.
static func _store(props: Common.Props, body: StaticBody3D, lay: Dictionary, world: Callable, out: Dictionary) -> void:
	var drum := Common.cached_mesh("nat_drum_prop", func():
		var mb := Common.MeshBuilder.new()
		var blue := Common.mat("nat_drum_blue", Color(0.12, 0.32, 0.62), 0.5)
		var lid := Common.mat("nat_drum_lid", Color(0.80, 0.80, 0.78), 0.45, 0.3)
		mb.cylinder("d", blue, Transform3D(Basis(), Vector3(0, 0.44, 0)), 0.28, 0.88, 14)
		mb.cylinder("l", lid, Transform3D(Basis(), Vector3(0, 0.89, 0)), 0.29, 0.04, 14)
		for yy in [0.24, 0.64]:
			mb.cylinder("l", lid, Transform3D(Basis(), Vector3(0, yy, 0)), 0.295, 0.05, 14)
		return mb.commit())
	for d in lay.drums:
		var p: Vector3 = world.call(Vector2(d.tile) + Vector2(0.5, 0.5))
		var b := Basis(Vector3.UP, float(d.yaw))
		for k in int(d.stack):
			props.add(drum, Transform3D(b, p + Vector3(0, k * 0.93, 0)), 45.0)
		var h := float(int(d.stack)) * 0.93
		Common.collider(body, Transform3D(b, p + Vector3(0, h * 0.5, 0)), Vector3(0.58, h, 0.58))
		Common.anchor(out, p + Vector3(0, h, 0), float(d.yaw), "counter", "natatorium_deck")


static func _lockers(root: Node3D, body: StaticBody3D, lay: Dictionary, world: Callable, steel: Material, paint: Material, out: Dictionary) -> void:
	var mb := Common.MeshBuilder.new()
	# A bank of lockers down the north wall of the room, every door shut.
	var x0: float = world.call(Vector2(float(LOCKERS.position.x) + 0.5, 0)).x
	var x1: float = world.call(Vector2(float(LOCKERS.end.x) - 1.5, 0)).x
	var z: float = world.call(Vector2(0, float(LOCKERS.position.y) + 0.5)).z - T * 0.5 + 0.28
	mb.box("s", steel, Transform3D(Basis(), Vector3((x0 + x1) * 0.5, 0.95, z)), Vector3(x1 - x0 + T, 1.9, 0.55))
	Common.collider(body, Transform3D(Basis(), Vector3((x0 + x1) * 0.5, 0.95, z)), Vector3(x1 - x0 + T, 1.9, 0.55))
	var seam := Common.mat("nat_locker_seam", Color(0.30, 0.34, 0.36), 0.6, 0.4)
	var x := x0 - T * 0.5 + 0.3
	while x < x1 + T * 0.5:
		mb.box("m", seam, Transform3D(Basis(), Vector3(x, 0.95, z + 0.29)), Vector3(0.02, 1.86, 0.02))
		x += 0.3
	for b: Rect2i in lay.benches:
		var c: Vector3 = world.call(Vector2(b.position) + Vector2(b.size) * 0.5)
		mb.box("p", paint, Transform3D(Basis(), c + Vector3(0, 0.44, 0)), Vector3(b.size.x * T - 0.3, 0.08, 0.4))
		for sx in [-0.5, 0.5]:
			mb.box("s", steel, Transform3D(Basis(), c + Vector3(sx * (b.size.x * T - 0.8), 0.2, 0)), Vector3(0.06, 0.44, 0.34))
		Common.collider(body, Transform3D(Basis(), c + Vector3(0, 0.24, 0)), Vector3(b.size.x * T - 0.3, 0.48, 0.4))
		Common.anchor(out, c + Vector3(0, 0.49, 0), 0.0, "counter", "natatorium_lockers")
	var mi := MeshInstance3D.new()
	mi.name = "Lockers"
	mi.mesh = mb.commit()
	root.add_child(mi)


## Roof trusses across the short axis, the only thing between the lamps and nine metres of nothing.
static func _trusses(props: Common.Props, world: Callable, steel: Material) -> void:
	var truss := Common.cached_mesh("nat_truss", func():
		var mb := Common.MeshBuilder.new()
		mb.box("s", steel, Transform3D(Basis(), Vector3(0, 0.3, 0)), Vector3(0.14, 0.14, 1.0))
		mb.box("s", steel, Transform3D(Basis(), Vector3(0, -0.3, 0)), Vector3(0.14, 0.14, 1.0))
		return mb.commit())
	var brace := Common.cached_mesh("nat_brace", func():
		var mb := Common.MeshBuilder.new()
		mb.box("s", steel, Transform3D(Basis(Vector3.RIGHT, 0.7), Vector3()), Vector3(0.07, 0.07, 0.95))
		return mb.commit())
	var z0: float = world.call(Vector2(0, HALL.position.y)).z
	var z1: float = world.call(Vector2(0, HALL.end.y)).z
	for tx in range(HALL.position.x + 2, HALL.end.x - 1, 5):
		var x: float = world.call(Vector2(float(tx) + 0.5, 0)).x
		var z := z0
		while z < z1:
			props.add(truss, Transform3D(Basis(), Vector3(x, TRUSS_Y, z + 0.5)), 0.0, false)
			props.add(brace, Transform3D(Basis(), Vector3(x, TRUSS_Y, z + 0.5)), 0.0, false)
			z += 1.0


static func _signs(root: Node3D, world: Callable) -> void:
	var make := func(text: String, fg: Color, bg: Color, size: Vector2, pos: Vector3, yaw: float, glow: bool) -> void:
		var mi := MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = size
		mi.mesh = qm
		var m := StandardMaterial3D.new()
		var tex := Common.text_texture(text, fg, bg, 512, 96)
		m.albedo_texture = tex
		m.roughness = 0.8
		if glow:
			m.emission_enabled = true
			m.emission_texture = tex
			# White, and gently: tinting the emission by the text colour at 1.4 blew the whole quad out
			# to a solid bar and ate the letters.
			m.emission = Color(1, 1, 1)
			m.emission_energy_multiplier = 0.55
		mi.material_override = m
		mi.position = pos
		mi.rotation.y = yaw
		root.add_child(mi)
	make.call("ST. DOE'S GENERAL  *  NATATORIUM", Color(0.90, 0.94, 0.96), Color(0.10, 0.26, 0.34),
			Vector2(7.0, 1.1), world.call(Vector2(HALL.get_center().x, HALL.position.y + 0.02), 5.2), 0.0, false)
	make.call("NO LIFEGUARD ON DUTY", Color(0.96, 0.86, 0.20), Color(0.12, 0.13, 0.14),
			Vector2(4.2, 0.8), world.call(Vector2(HALL.get_center().x - 8.0, HALL.position.y + 0.02), 2.7), 0.0, true)
	make.call("NO DIVING", Color(0.92, 0.94, 0.94), Color(0.14, 0.42, 0.50),
			Vector2(2.6, 0.5), world.call(Vector2(HALL.end.x - 0.04, HALL.get_center().y), 2.4), -PI * 0.5, false)
	make.call("SHOWER BEFORE ENTERING THE POOL", Color(0.90, 0.92, 0.92), Color(0.18, 0.34, 0.40),
			Vector2(2.4, 0.42), world.call(Vector2(LOCKER_DOOR.x + 0.5, LOCKER_DOOR.y - 0.02), 2.55), PI, false)


static func _lights(root: Node3D, lay: Dictionary, world: Callable, out: Dictionary) -> void:
	var lights := Node3D.new()
	lights.name = "Lights"
	root.add_child(lights)
	# High bays on long rods over the deck: cold, and few enough to leave the far end dim.
	var bay := Common.cached_mesh("nat_bay", func():
		var mb := Common.MeshBuilder.new()
		var shell := Common.mat("nat_bay_shell", Color(0.24, 0.26, 0.28), 0.5, 0.6)
		mb.cylinder("s", shell, Transform3D(Basis(), Vector3(0, 0.0, 0)), 0.42, 0.26, 14, 0.2, false)
		mb.cylinder("e", Common.mat("nat_bay_lamp", Color(0.92, 0.97, 1.0), 0.3, 0.0, Color(0.85, 0.95, 1.0), 4.0),
				Transform3D(Basis(), Vector3(0, -0.11, 0)), 0.2, 0.06, 12)
		mb.box("s", shell, Transform3D(Basis(), Vector3(0, 0.6, 0)), Vector3(0.05, 1.0, 0.05))
		return mb.commit())
	for i in lay.lamps.size():
		var t: Vector2i = lay.lamps[i]
		var p: Vector3 = world.call(Vector2(t) + Vector2(0.5, 0.5), TRUSS_Y - 1.1)
		var node := Common.omni(lights, p, 3.4, 16.0, Color(0.86, 0.94, 1.0), 0.5, i % 3 == 0, 1.1)
		var mi := MeshInstance3D.new()
		mi.mesh = bay
		node.add_child(mi)
		out.lights.append({"tile": t, "position": p, "mode": 0 if i % 5 != 3 else 1, "node": node, "pocket": "natatorium"})
	# The underwater lights: set into the pool walls under the surface, and the reason the room reads
	# as a pool at all. They are the strongest thing in here and they light the ceiling through the water.
	var port := Common.cached_mesh("nat_uwlight", func():
		var mb := Common.MeshBuilder.new()
		mb.cylinder("g", Common.mat("nat_uw_glass", Color(0.65, 0.92, 1.0), 0.1, 0.0, Color(0.55, 0.90, 1.0), 6.0),
				Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3()), 0.16, 0.06, 12)
		return mb.commit())
	for i in lay.underwater.size():
		var t: Vector2 = lay.underwater[i]
		var p: Vector3 = world.call(t, WATER_Y - 0.16)
		var node := Common.omni(lights, p, 2.6, 11.0, Color(0.42, 0.82, 0.95), 2.2, false, 1.6)
		var mi := MeshInstance3D.new()
		mi.mesh = port
		node.add_child(mi)
		out.lights.append({"tile": Vector2i(t), "position": p, "mode": 0, "node": node, "pocket": "natatorium"})
	# The locker room's own strip.
	var lp: Vector3 = world.call(Vector2(LOCKERS.get_center()), LOCKER_CEIL - 0.12)
	out.lights.append({"tile": LOCKERS.position, "position": lp, "mode": 1, "pocket": "natatorium",
			"node": Common.omni(lights, lp, 1.1, 7.0, Color(0.88, 0.94, 0.92), 0.6)})
