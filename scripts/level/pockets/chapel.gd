extends RefCounted
## POCKETS: the Chapel. A hospital chapel that is somehow a cathedral. A nave 33 m long under a
## vault whose ceiling is 24 m up and never lit, two arcades of stone piers with arches springing
## between them, side aisles behind the arcade, pews for a little over three hundred people, a
## sanctuary with an altar and a reredos of candles, and a sacristy off it behind a door.
##
## Candlelight is the room's light. There is no electric fixture anywhere in here: every bit of
## illumination comes from the votive racks in the aisles, the standing candle stands along the
## arcade and the altar's own candles. Nobody lit any of it.
##
## HOW THE LIGHT IS BUILT (the perf-critical decision in this space). Hundreds of visible flames,
## LIGHT_BUDGET real ones. Every candle is emissive geometry in a MultiMesh — a wax body and a
## flame billboard with an emissive material, which costs a draw call per chunk and no light at
## all. Illumination comes from a small number of real unshadowed OmniLight3Ds, one pooled at each
## votive rack and candle stand rather than one per flame, plus the sanctuary's. At most
## SHADOW_BUDGET of them cast shadows, exactly as the Factory's high bays do. The emissive flames
## are what you see; the pooled omnis are what you see BY. 0.10.25's mirror bulbs were emissive
## with no Light3D at all, which is the trap in the other direction: here the light has to be real,
## because the Night Nurse's watched predicate asks whether a point is lit (Perception.fixture_lit
## walks level_info.lights looking for an OmniLight3D named "Bulb", which Common.omni builds), and
## a cathedral lit by nothing would make her unfreezable.
##
## layout(stubs, seed) and prepare(layout, origin) (surface arrays, navigation faces) are pure data (a
## worker thread; tools/mapcheck.gd checks the layout); build_steps(layout, origin, out, root, prep) makes
## the nodes in world space a step at a time and fills `out` (lights, containers, loose_anchors,
## monster_spawns, spawn); build() does it all at once. doorways() / door_entries(): the real doors.

const Common := preload("res://scripts/level/pockets/pocket_common.gd")
const Stub := preload("res://scripts/level/pockets/stub.gd")

## POCKETS 2 phase 1: the ambient noise floor a sound-hunting monster stands in here (see
## PocketSpaces.ambient_noise_at). A cathedral with nobody in it is the quietest room in the game:
## nothing runs, nothing hums, and the Chapel deliberately declares no floor at all. Silence is the
## point of the space, and a floor above 0.0 would hand the player cover they have not earned.
const AMBIENT_NOISE_LEVEL := 0.0

## POCKETS 2: the item kinds this space puts into the world, as a set anything else can read
## without going digging through the layout below for string literals. The follow-up task that
## bleeds a pocket's items into the hospital rooms near its entrances reads exactly this.
## The Factory and the Restaurant contribute no items of their own (their loot comes from the
## normal wing tables through containers and anchors), so there was no convention to follow and the
## new spaces agreed on this name. Keep it beside AMBIENT_NOISE_LEVEL.
const POCKET_ITEMS := ["votive_candle", "communion_wine", "collection_plate"]

const T := 1.5
const M := 10
const W := 22
const H := 44
const CEIL := 24.0
## The aisles are ceiled much lower than the nave, which is what makes the nave read as tall.
const AISLE_CEIL := 9.0
const SACRISTY_CEIL := 3.0
const SACRISTY_TOP := 3.35
## Where the arcade arches spring from and how high they reach.
const PIER_TOP := 7.4
const ARCH_TOP := 10.6

## Interior: x 11..32, y 11..54 (local tiles). The nave runs along +y, narthex at the low end.
##
## Across the building: a side aisle five tiles wide, an arcade pier, four tiles of pews, the
## processional aisle, four more tiles of pews, the other pier, the other side aisle. The side
## aisles are five wide rather than the three this started at for a reason worth writing down:
## Common._port_fits wants about five tiles of clear, navigable floor inward from an opening
## before it will hang an entrance on that wall, so a three-tile aisle backed by an arcade pier
## made the whole west and east walls unusable and threw every entrance onto the north wall. With
## five, three of the four walls take entrances and the pocket is a real shortcut again.
const INTERIOR := Rect2i(M + 1, M + 1, W, H)
## The two arcades: piers stand on these columns of tiles.
const PIER_X_W := M + 6          # x 16
const PIER_X_E := M + 17         # x 27
## Side aisles, outside the arcades.
const AISLE_W := Rect2i(M + 1, M + 1, 5, H)      # x 11..15
const AISLE_E := Rect2i(M + 18, M + 1, 5, H)     # x 28..32
## The nave floor, which INCLUDES the two pier columns: the piers are individual blocked tiles
## standing in open floor, not a solid wall. Carving the nave short of them would wall the side
## aisles off from the nave completely, since a pier column runs the whole length of the building.
const NAVE := Rect2i(M + 6, M + 1, 12, H)        # x 16..27, piers included
const MID_AISLE := Rect2i(M + 11, M + 1, 2, H)   # x 21..22
## The two blocks of pews, between the piers and the processional aisle.
const PEW_W_X0 := M + 7                           # x 17..20
const PEW_E_X0 := M + 13                          # x 23..26
const PEW_WIDTH := 4
const NARTHEX_END := M + 6                        # y 16: pews start after this
const SANCTUARY_Y := M + 35                       # y 45: the sanctuary step
## Pews come in blocks with a cross aisle between them, never as single rows with single-tile gaps.
## A one-tile gap is open in the grid but the navigation bake erodes it away from both sides, so it
## counts against the pocket's coverage while being no use to anybody: mapcheck measures coverage
## over the tiles a layout leaves unblocked, and slivers are how you fail it. Blocks are solid and
## the aisles between them are three tiles wide, which survives the agent radius with room to spare.
const PEW_ROWS := 4
const CROSS_ROWS := 3
## The sacristy, off the sanctuary's west side, behind a hinged door.
const SACRISTY_BLOCK := Rect2i(M + 1, M + 39, 7, 6)   # x 11..17, y 49..54
const SACRISTY := Rect2i(M + 2, M + 40, 5, 4)         # x 12..16, y 50..53
const SACRISTY_DOOR := Vector2i(M + 4, M + 39)        # x 14, y 49, opening north

## Real lights. The Factory runs 23 omnis with at most 2 shadowed; the Chapel holds the same shape.
## They are POOLED -- one per rack or stand, not one per flame -- so they have to be strong and
## long-reaching to stand in for the dozen or more candles each of them represents. The first pass
## used a candle's own literal brightness (energy 1.5, range 7.5) and the result was a black
## building with a few orange dots in it: the flames read, and nothing they were supposed to be
## lighting did. A pooled light is a bank of candles, not a candle.
const LIGHT_BUDGET := 28
const SHADOW_BUDGET := 2


static func layout(stubs: Array, seed: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var g := Common.new_grid(W + 2 * M + 2, H + 2 * M + 2)
	var nave := Common.add_room(g, {"name": "nave", "ceil": CEIL, "floor": "stone", "ceiling": "vault",
			"wall": "stone_up", "wall_low": "stone_low", "split": 3.2, "uv": 2.0, "place": "chapel_nave"})
	var aisle := Common.add_room(g, {"name": "aisle", "ceil": AISLE_CEIL, "floor": "stone", "ceiling": "vault",
			"wall": "stone_up", "wall_low": "stone_low", "split": 3.2, "uv": 2.0, "place": "chapel_aisle"})
	var sacristy := Common.add_room(g, {"name": "sacristy", "ceil": SACRISTY_CEIL, "floor": "wood",
			"ceiling": "sacristy_ceiling", "wall": "sacristy_wall", "wall_low": "sacristy_wall_low",
			"split": 1.05, "place": "chapel_sacristy"})
	Common.carve(g, NAVE, nave)
	Common.carve(g, AISLE_W, aisle)
	Common.carve(g, AISLE_E, aisle)
	# The sacristy: a solid block in the sanctuary's corner, hollowed out, with one doorway.
	for y in range(SACRISTY_BLOCK.position.y, SACRISTY_BLOCK.end.y):
		for x in range(SACRISTY_BLOCK.position.x, SACRISTY_BLOCK.end.x):
			Common.set_solid(g, x, y, SACRISTY_TOP)
	Common.carve(g, SACRISTY, sacristy)
	Common.set_open(g, SACRISTY_DOOR.x, SACRISTY_DOOR.y, sacristy)
	var doors: Array = [SACRISTY_DOOR]
	# Nothing may wedge an entrance into the sanctuary or against the sacristy.
	Common.reserve(g, SACRISTY_BLOCK.grow(2))
	Common.reserve(g, Rect2i(NAVE.position.x, SANCTUARY_Y, NAVE.size.x, INTERIOR.end.y - SANCTUARY_Y))

	var walls := [
		{"from": Vector2i(M, M + 3), "dir": Vector2i(0, 1), "len": H - 4, "ev": Vector2i(-1, 0)},
		{"from": Vector2i(M + 3, M), "dir": Vector2i(1, 0), "len": W - 4, "ev": Vector2i(0, -1)},
		{"from": Vector2i(M + W + 1, M + 3), "dir": Vector2i(0, 1), "len": H - 4, "ev": Vector2i(1, 0)},
		{"from": Vector2i(M + 3, M + H + 1), "dir": Vector2i(1, 0), "len": W - 4, "ev": Vector2i(0, 1)},
	]
	var ports := Common.place_ports(g, stubs, walls, rng)

	# Pews: blocks of PEW_ROWS benches either side of the processional aisle, a CROSS_ROWS cross
	# aisle between blocks, from the narthex to the sanctuary step. Sixteen rows a side, each bench
	# six metres of oak: a little over three hundred places, and not one of them taken.
	var pews: Array = []
	var blocks: Array = []
	var by := NARTHEX_END + 1
	while by + PEW_ROWS <= SANCTUARY_Y - 1:
		for side in [0, 1]:
			var block := Rect2i(PEW_W_X0 if side == 0 else PEW_E_X0, by, PEW_WIDTH, PEW_ROWS)
			if not _free(g, block):
				continue
			blocks.append(block)
			# The whole block goes out of the navigation mesh in one piece: you walk the aisles.
			_block(g, block)
			for row in range(block.position.y, block.end.y):
				pews.append({"rect": Rect2i(block.position.x, row, block.size.x, 1), "side": side})
		by += PEW_ROWS + CROSS_ROWS

	# The arcades: piers only on rows a pew block already covers, so a pier never stands in a cross
	# aisle and pinches it, and never in front of an entrance.
	var piers: Array = []
	for b: Rect2i in blocks:
		for row in [b.position.y, b.position.y + 2]:
			var px: int = PIER_X_W if b.position.x < MID_AISLE.position.x else PIER_X_E
			var t := Vector2i(px, row)
			if Common.is_reserved(g, Rect2i(t, Vector2i.ONE)) or not Common.is_open(g, t.x, t.y):
				continue
			if piers.has(t):
				continue
			piers.append(t)
			_block(g, Rect2i(t, Vector2i.ONE))

	# Votive racks stand against the outer walls of both aisles, in the bays between the piers.
	var racks: Array = []
	for y in range(INTERIOR.position.y + 4, INTERIOR.end.y - 6, 7):
		for pair in [[AISLE_W.position.x, Vector2i(-1, 0)], [AISLE_E.end.x - 1, Vector2i(1, 0)]]:
			var t := Vector2i(int(pair[0]), y)
			# The tile only, not grown: a votive rack stands AGAINST the outer wall, and growing the
			# test by one reached into that wall and quietly refused every rack in the building.
			if not _free(g, Rect2i(t, Vector2i.ONE)):
				continue
			racks.append({"tile": t, "wall": pair[1]})
			_block(g, Rect2i(t, Vector2i.ONE))

	# Standing candle stands in pairs down the nave: one either side of the processional aisle in
	# every cross aisle, and a pair in the narthex. A cathedral only reads as a cathedral if there
	# is light the whole length of it -- the first pass hung the lights on the outer aisle walls
	# only, and from the narthex the nave was a black tunnel with one orange dot at the far end.
	var stands: Array = []
	var stand_rows: Array = [NARTHEX_END - 2]
	var cy := NARTHEX_END + 1 + PEW_ROWS + (CROSS_ROWS / 2)
	while cy < SANCTUARY_Y - 1:
		stand_rows.append(cy)
		cy += PEW_ROWS + CROSS_ROWS
	for row: int in stand_rows:
		for sx in [MID_AISLE.position.x - 1, MID_AISLE.end.x]:
			var t := Vector2i(sx, row)
			if not _free(g, Rect2i(t, Vector2i.ONE)):
				continue
			stands.append(t)
			_block(g, Rect2i(t, Vector2i.ONE))

	# The sanctuary: an altar on the centre line, a credence table beside it, a reredos of candles
	# against the end wall behind.
	var altar := Vector2i(MID_AISLE.position.x, SANCTUARY_Y + 3)
	var credence := Vector2i(MID_AISLE.end.x + 2, SANCTUARY_Y + 3)
	var reredos := Vector2i(MID_AISLE.position.x, INTERIOR.end.y - 2)
	for t in [altar, credence, reredos]:
		_block(g, Rect2i(t, Vector2i(2, 1)))

	# Containers: the sacristy's vestment press and its pegboard of small silver, and a first aid
	# cabinet in the narthex where a hospital chapel would really keep one.
	var containers: Array = []
	containers.append({"tile": Vector2i(SACRISTY.end.x - 1, SACRISTY.position.y + 1), "wall": Vector2i(1, 0), "type": "drawer_unit"})
	containers.append({"tile": Vector2i(SACRISTY.position.x, SACRISTY.position.y + 2), "wall": Vector2i(-1, 0), "type": "pegboard"})
	var bag := Vector2i(AISLE_W.position.x, INTERIOR.position.y + 1)
	if _free(g, Rect2i(bag, Vector2i.ONE)):
		containers.append({"tile": bag, "wall": Vector2i(-1, 0), "type": "trauma_bag"})
	for c in containers:
		if c.type != "trauma_bag" and c.type != "pegboard":
			_block(g, Rect2i(c.tile, Vector2i.ONE))

	# Monster spawns out on the nave floor and in the aisles, away from the entrances.
	var spawns: Array = []
	var tries := 0
	while spawns.size() < 3 and tries < 300:
		tries += 1
		var t := Vector2i(rng.randi_range(INTERIOR.position.x + 1, INTERIOR.end.x - 2),
				rng.randi_range(INTERIOR.position.y + 4, INTERIOR.end.y - 8))
		if not _free(g, Rect2i(t, Vector2i.ONE).grow(1)):
			continue
		var far := true
		for s in spawns:
			if (s as Vector2i).distance_to(t) < 12.0:
				far = false
		if far:
			spawns.append(t)
	return {"kind": "chapel", "size": Vector2i(g.w, g.h), "grid": g, "rows": Common.rows(g), "ports": ports,
			"piers": piers, "pews": pews, "racks": racks, "stands": stands, "containers": containers,
			"spawns": spawns, "doors": doors, "altar": altar, "credence": credence, "reredos": reredos,
			"spawn": Vector2i(MID_AISLE.position.x, NARTHEX_END - 1)}


static func _free(g: Dictionary, r: Rect2i) -> bool:
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			if not Common.is_open(g, x, y):
				return false
			var i := Common.idx(g, x, y)
			if g.reserved[i] == 1 or g.nav[i] == 1 or g.stub[i] == 1:
				return false
			if not INTERIOR.has_point(Vector2i(x, y)):
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
	root.name = "Chapel"
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
	var stone := Common.tri_mat("chp_stone", "mat/concrete", Color(0.40, 0.38, 0.35), 0.35, 0.92)
	var dark_stone := Common.tri_mat("chp_stone_dark", "mat/concrete", Color(0.20, 0.19, 0.18), 0.35, 0.95)
	var oak := Common.tri_mat("chp_oak", "mat/floor", Color(0.24, 0.16, 0.10), 0.9, 0.85)
	var brass := Common.tri_mat("chp_brass", "mat/metal", Color(0.42, 0.31, 0.11), 0.7, 0.45, 0.7)
	var iron := Common.mat("chp_iron", Color(0.07, 0.07, 0.07), 0.7, 0.4)
	var linen := Common.mat("chp_linen", Color(0.78, 0.75, 0.68), 0.9)

	steps.append(func():
		geo.mats["stone"] = Common.tri_mat("chp_floor", "mat/concrete", Color(0.34, 0.32, 0.30), 0.35, 0.9)
		# The vault is never lit: a near-black ceiling 24 m up that the candles cannot reach.
		geo.mats["vault"] = Common.mat("chp_vault", Color(0.035, 0.033, 0.038), 0.95)
		geo.mats["stone_low"] = Common.tri_mat("chp_wall_low", "mat/concrete", Color(0.30, 0.28, 0.26), 0.35, 0.92)
		geo.mats["stone_up"] = Common.tri_mat("chp_wall_up", "mat/wall", Color(0.26, 0.25, 0.24), 0.35, 0.93)
		geo.mats["wood"] = Common.tri_mat("chp_sac_floor", "mat/floor", Color(0.30, 0.21, 0.13), 0.7, 0.85)
		geo.mats["sacristy_ceiling"] = Common.HB.surface_mat("mat/ceiling", Color(0.22, 0.20, 0.18), 0.95)
		geo.mats["sacristy_wall"] = Common.tri_mat("chp_sac_wall", "mat/wall", Color(0.40, 0.35, 0.28), 0.5, 0.88)
		geo.mats["sacristy_wall_low"] = Common.tri_mat("chp_sac_wall_low", "mat/wall", Color(0.28, 0.23, 0.18), 0.5, 0.88)
		return geo.commit_steps(root, ctx))

	# The floor and the vault as boxes, so nothing falls through between faces, and the arcades.
	steps.append(func():
		var body: StaticBody3D = ctx.body
		var iw := Rect2(Vector2(INTERIOR.position) * T + Vector2(ow.x, ow.z), Vector2(INTERIOR.size) * T)
		Common.collider(body, Transform3D(Basis(), Vector3(iw.get_center().x, -0.2, iw.get_center().y)), Vector3(iw.size.x, 0.4, iw.size.y))
		Common.collider(body, Transform3D(Basis(), Vector3(iw.get_center().x, CEIL + 0.2, iw.get_center().y)), Vector3(iw.size.x, 0.4, iw.size.y))
		# A pier: a stone shaft on a plinth, with a moulded capital where the arches spring.
		var pier_mesh := Common.cached_mesh("chp_pier", func():
			var mb := Common.MeshBuilder.new()
			mb.box("p", stone, Transform3D(Basis(), Vector3(0, 0.22, 0)), Vector3(1.35, 0.44, 1.35))
			mb.box("s", stone, Transform3D(Basis(), Vector3(0, PIER_TOP * 0.5, 0)), Vector3(1.0, PIER_TOP, 1.0))
			for a in 4:
				var ang := TAU * a / 4.0 + PI * 0.25
				mb.cylinder("s", stone, Transform3D(Basis(), Vector3(cos(ang) * 0.5, PIER_TOP * 0.5, sin(ang) * 0.5)), 0.17, PIER_TOP, 8)
			mb.box("c", stone, Transform3D(Basis(), Vector3(0, PIER_TOP + 0.18, 0)), Vector3(1.45, 0.36, 1.45))
			# The shaft carries on up into the dark as a vaulting rib.
			mb.box("d", dark_stone, Transform3D(Basis(), Vector3(0, (CEIL + PIER_TOP) * 0.5, 0)), Vector3(0.55, CEIL - PIER_TOP, 0.55))
			return mb.commit())
		for p: Vector2i in lay.piers:
			var at: Vector3 = world.call(Vector2(p) + Vector2(0.5, 0.5))
			props.add(pier_mesh, Transform3D(Basis(), at), 0.0)
			Common.collider(body, Transform3D(Basis(), at + Vector3(0, 2.0, 0)), Vector3(1.4, 4.0, 1.4))
		_build_arches(root, lay, world, stone, dark_stone))

	steps.append(func(): _build_pews(root, ctx.body, props, lay, world, oak, out))
	# The sanctuary is built before the racks and the stands because they share one light budget
	# and it must be the first to draw on it: an altar nobody can see is not a chapel.
	steps.append(func(): _build_sanctuary(root, ctx.body, props, lay, world, stone, oak, brass, linen, out))
	steps.append(func(): _build_sacristy(root, ctx.body, props, lay, world, oak, linen, out))
	steps.append(func(): _build_racks(root, props, lay, world, iron, out))
	steps.append(func(): _build_stands(root, props, lay, world, brass, out))

	# Containers, one a step.
	var cts := Node3D.new()
	cts.name = "Containers"
	steps.append(func(): root.add_child(cts))
	for c in lay.containers:
		steps.append(func():
			var room := "chapel_sacristy" if SACRISTY_BLOCK.has_point(c.tile) else "chapel_nave"
			Common.container(cts, out, origin, c.tile, c.wall, c.type, room))
	steps.append(func():
		for s: Vector2i in lay.spawns:
			out.monster_spawns.append(world.call(Vector2(s) + Vector2(0.5, 0.5)))
		out["spawn"] = world.call(Vector2(lay.spawn) + Vector2(0.5, 0.5))
		return props.commit_steps(root))
	return steps


## The sacristy's doorway (a hinged door hung at the sanctuary face). Data only.
static func doorways(lay: Dictionary) -> Array:
	var out: Array = []
	for t: Vector2i in lay.doors:
		out.append({"tiles": [t], "n": Vector2i(0, -1), "kind": "hinged"})
	return out


## The doorways as door plan entries in world tiles.
static func door_entries(lay: Dictionary, origin: Vector2i) -> Array:
	var out: Array = []
	for dw in doorways(lay):
		out.append(Common.door_entry(origin, dw.tiles, dw.n, dw.kind, 90.0))
	return out


# =========================================================================
# the arcades
# =========================================================================

## An arch between each neighbouring pair of piers in a row, and the blind wall above it. Geometry
## only: the piers already carry the colliders, and you walk under an arch.
static func _build_arches(root: Node3D, lay: Dictionary, world: Callable, stone: Material, dark: Material) -> void:
	var mb := Common.MeshBuilder.new()
	var rows := {PIER_X_W: [], PIER_X_E: []}
	for p: Vector2i in lay.piers:
		if rows.has(p.x):
			(rows[p.x] as Array).append(p.y)
	for px in rows.keys():
		var ys: Array = rows[px]
		ys.sort()
		for i in range(ys.size() - 1):
			var y0: float = float(ys[i]) + 0.5
			var y1: float = float(ys[i + 1]) + 0.5
			# Within a pew block the piers are two rows apart; across a cross aisle they are five,
			# and that wider bay still gets its arch. Anything wider than that is a bay an entrance
			# took, and is left open.
			if y1 - y0 > 6.0:
				continue
			var a: Vector3 = world.call(Vector2(px + 0.5, y0))
			var b: Vector3 = world.call(Vector2(px + 0.5, y1))
			var span := b.z - a.z
			var mid := (a + b) * 0.5
			# A pointed arch drawn as a fan of short chords, so it reads gothic rather than round.
			var segs := 7
			for k in segs:
				var f0 := float(k) / segs
				var f1 := float(k + 1) / segs
				var p0 := _arch_point(a.z, span, f0)
				var p1 := _arch_point(a.z, span, f1)
				var c := Vector3(mid.x, (p0.y + p1.y) * 0.5, (p0.x + p1.x) * 0.5)
				var d := Vector2(p1.x - p0.x, p1.y - p0.y)
				var ang := atan2(d.y, d.x)
				mb.box("s", stone, Transform3D(Basis(Vector3.RIGHT, -ang), c), Vector3(0.75, 0.42, d.length() + 0.08))
			# The blind wall from the arch's crown up to where the clerestory would be.
			mb.box("d", dark, Transform3D(Basis(), Vector3(mid.x, (ARCH_TOP + CEIL) * 0.5, mid.z)), Vector3(0.45, CEIL - ARCH_TOP, span))
	var mi := MeshInstance3D.new()
	mi.name = "Arcades"
	mi.mesh = mb.commit()
	mi.layers = 1
	root.add_child(mi)


## A point on one arch, as (z, y), for `f` from 0 to 1 across the span.
static func _arch_point(z0: float, span: float, f: float) -> Vector2:
	var z := z0 + span * f
	# Two circular sweeps meeting in a point at the crown.
	var t := absf(f - 0.5) * 2.0
	var y := PIER_TOP + (ARCH_TOP - PIER_TOP) * sqrt(maxf(0.0, 1.0 - t * t * 0.86))
	return Vector2(z, y)


# =========================================================================
# pews
# =========================================================================

static func _build_pews(root: Node3D, body: StaticBody3D, props: Common.Props, lay: Dictionary, world: Callable,
		oak: Material, out: Dictionary) -> void:
	var pew := Common.cached_mesh("chp_pew", func():
		var mb := Common.MeshBuilder.new()
		# A bench one tile long: seat, back, kneeler and two ends. Instanced per tile of the row.
		mb.box("w", oak, Transform3D(Basis(), Vector3(0, 0.44, 0.0)), Vector3(T, 0.07, 0.42))
		mb.box("w", oak, Transform3D(Basis(Vector3.RIGHT, -0.12), Vector3(0, 0.72, -0.24)), Vector3(T, 0.52, 0.06))
		mb.box("w", oak, Transform3D(Basis(), Vector3(0, 0.10, 0.36)), Vector3(T, 0.05, 0.22))
		return mb.commit())
	var pew_end := Common.cached_mesh("chp_pew_end", func():
		var mb := Common.MeshBuilder.new()
		mb.box("w", oak, Transform3D(Basis(), Vector3(0, 0.46, 0.05)), Vector3(0.08, 0.92, 0.66))
		return mb.commit())
	var count := 0
	for pw in lay.pews:
		var r: Rect2i = pw.rect
		for x in range(r.position.x, r.end.x):
			var p: Vector3 = world.call(Vector2(x + 0.5, r.position.y + 0.5))
			props.add(pew, Transform3D(Basis(), p), 42.0)
			count += 1
		for ex in [float(r.position.x), float(r.end.x)]:
			props.add(pew_end, Transform3D(Basis(), world.call(Vector2(ex, r.position.y + 0.5))), 42.0)
		var a: Vector3 = world.call(Vector2(r.position.x, r.position.y + 0.5))
		var b: Vector3 = world.call(Vector2(r.end.x, r.position.y + 0.5))
		# Two colliders, not one tall box: the seat has to present a top face at seat height or
		# anything set down on it falls through the world, and mapcheck's resting-spot check reads
		# exactly that ray. A single 0.92 box swallows its own anchors.
		Common.collider(body, Transform3D(Basis(), (a + b) * 0.5 + Vector3(0, 0.24, 0)), Vector3(b.x - a.x, 0.48, 0.46))
		Common.collider(body, Transform3D(Basis(), (a + b) * 0.5 + Vector3(0, 0.60, -0.24)), Vector3(b.x - a.x, 0.64, 0.10))
	# A few hymn books and a forgotten handbag left on the benches: somewhere to put loot down.
	var rng := RandomNumberGenerator.new()
	rng.seed = count * 31 + lay.pews.size()
	for i in mini(6, lay.pews.size()):
		var pw: Dictionary = lay.pews[rng.randi_range(0, lay.pews.size() - 1)]
		var r: Rect2i = pw.rect
		# On the end of the bench that meets the processional aisle. A pew block is nav-blocked
		# whole, so an anchor in the middle of one is over two metres from anywhere anybody can
		# stand: reachable means the aisle end, which is where a book gets left anyway.
		var x: int = (r.end.x - 1) if int(pw.side) == 0 else r.position.x
		Common.anchor(out, world.call(Vector2(x + 0.5, r.position.y + 0.5), 0.48), 0.0, "counter", "chapel_nave")


# =========================================================================
# the candles
# =========================================================================

## A votive cup: red glass with a wax puck and a flame. The flame is emissive geometry, not a light.
static func _votive_mesh() -> Mesh:
	return Common.cached_mesh("chp_votive", func():
		var mb := Common.MeshBuilder.new()
		var glass := Common.mat("chp_votive_glass", Color(0.35, 0.05, 0.04), 0.25, 0.0, Color(0.95, 0.30, 0.12), 1.7)
		var wax := Common.mat("chp_wax", Color(0.88, 0.84, 0.72), 0.75)
		var flame := Common.mat("chp_flame", Color(1.0, 0.86, 0.55), 0.1, 0.0, Color(1.0, 0.72, 0.30), 9.0)
		mb.cylinder("g", glass, Transform3D(Basis(), Vector3(0, 0.05, 0)), 0.035, 0.10, 8)
		mb.cylinder("w", wax, Transform3D(Basis(), Vector3(0, 0.085, 0)), 0.030, 0.02, 8)
		mb.cylinder("f", flame, Transform3D(Basis(), Vector3(0, 0.115, 0)), 0.012, 0.045, 6, 0.001)
		return mb.commit())


## A tall taper for the stands and the altar.
static func _taper_mesh() -> Mesh:
	return Common.cached_mesh("chp_taper", func():
		var mb := Common.MeshBuilder.new()
		var wax := Common.mat("chp_wax", Color(0.88, 0.84, 0.72), 0.75)
		var flame := Common.mat("chp_flame", Color(1.0, 0.86, 0.55), 0.1, 0.0, Color(1.0, 0.72, 0.30), 9.0)
		mb.cylinder("w", wax, Transform3D(Basis(), Vector3(0, 0.22, 0)), 0.022, 0.44, 8)
		mb.cylinder("f", flame, Transform3D(Basis(), Vector3(0, 0.465, 0)), 0.013, 0.05, 6, 0.001)
		return mb.commit())


## Votive racks: an iron stand of stepped trays, every cup on it lit. One pooled omni per rack.
static func _build_racks(root: Node3D, props: Common.Props, lay: Dictionary, world: Callable,
		iron: Material, out: Dictionary) -> void:
	var lights := _candlelight(root)
	var stand := Common.cached_mesh("chp_rack", func():
		var mb := Common.MeshBuilder.new()
		for sx in [-0.42, 0.42]:
			mb.box("i", iron, Transform3D(Basis(), Vector3(sx, 0.36, 0.0)), Vector3(0.05, 0.72, 0.05))
			mb.box("i", iron, Transform3D(Basis(), Vector3(sx, 0.36, 0.30)), Vector3(0.05, 0.72, 0.05))
		for k in 3:
			mb.box("i", iron, Transform3D(Basis(), Vector3(0, 0.62 + k * 0.13, 0.30 - k * 0.15)), Vector3(0.94, 0.03, 0.17))
		mb.box("i", iron, Transform3D(Basis(), Vector3(0, 0.10, 0.15)), Vector3(0.94, 0.03, 0.44))
		return mb.commit())
	var votive := _votive_mesh()
	for rk in lay.racks:
		var t: Vector2i = rk.tile
		var wall: Vector2i = rk.wall
		var yaw := atan2(float(-wall.x), float(-wall.y))
		var at: Vector3 = world.call(Vector2(t) + Vector2(0.5, 0.5))
		var xf := Transform3D(Basis(Vector3.UP, yaw), at)
		props.add(stand, xf, 0.0)
		# Every cup on every tray lit, and nobody who lit them.
		for k in 3:
			for i in 7:
				var local := Vector3(-0.36 + i * 0.12, 0.65 + k * 0.13, 0.30 - k * 0.15)
				props.add(votive, Transform3D(Basis(), xf * local), 0.0, false)
		_add_light(lights, out, t, at + Vector3(0, 1.0, 0) - Vector3(wall.x, 0, wall.y) * 0.4, 4.5, 16.0)


## Standing candle stands out on the nave floor beside the arcade piers.
static func _build_stands(root: Node3D, props: Common.Props, lay: Dictionary, world: Callable,
		brass: Material, out: Dictionary) -> void:
	var lights := _candlelight(root)
	var stand := Common.cached_mesh("chp_stand", func():
		var mb := Common.MeshBuilder.new()
		mb.cylinder("b", brass, Transform3D(Basis(), Vector3(0, 0.04, 0)), 0.26, 0.08, 12)
		mb.cylinder("b", brass, Transform3D(Basis(), Vector3(0, 0.62, 0)), 0.05, 1.16, 10)
		mb.cylinder("b", brass, Transform3D(Basis(), Vector3(0, 1.22, 0)), 0.30, 0.05, 12)
		return mb.commit())
	var taper := _taper_mesh()
	for t: Vector2i in lay.stands:
		var at: Vector3 = world.call(Vector2(t) + Vector2(0.5, 0.5))
		props.add(stand, Transform3D(Basis(), at), 0.0)
		for i in 6:
			var ang := TAU * i / 6.0
			props.add(taper, Transform3D(Basis(), at + Vector3(cos(ang) * 0.21, 1.25, sin(ang) * 0.21)), 0.0, false)
		_add_light(lights, out, t, at + Vector3(0, 1.85, 0), 5.5, 19.0)


## The node every real light in the Chapel hangs under, made by whichever builder needs it first.
static func _candlelight(root: Node3D) -> Node3D:
	var n: Node3D = root.get_node_or_null("Candlelight")
	if n == null:
		n = Node3D.new()
		n.name = "Candlelight"
		root.add_child(n)
	return n


## One real light, inside the budget. Everything past LIGHT_BUDGET is emissive geometry only: the
## flames are still drawn, they simply stop contributing illumination, and the racks are placed
## from the sanctuary outward so the budget runs out at the back of the nave where it shows least.
static func _add_light(parent: Node3D, out: Dictionary, tile: Vector2i, pos: Vector3, energy: float, rng: float) -> void:
	var placed: int = int(out.get("chapel_lights", 0))
	if placed >= LIGHT_BUDGET:
		return
	out["chapel_lights"] = placed + 1
	var shadow := placed < SHADOW_BUDGET
	# Attenuation 1.0, not the 1.4 this started at: a pooled light stands in for a whole bank of
	# candles, and a steep falloff made every one of them a dot with nothing lit around it.
	var node := Common.omni(parent, pos, energy, rng, Color(1.0, 0.68, 0.34), 0.6, shadow, 1.0)
	var bulb: OmniLight3D = node.get_node("Bulb")
	bulb.distance_fade_enabled = true
	bulb.distance_fade_begin = 58.0
	bulb.distance_fade_length = 16.0
	# Candles are never steady. The flicker is the same deterministic waveform the hospital's
	# failing fixtures use, run gently so it reads as a draught rather than a dying tube.
	bulb.set_meta("mode", 1)
	bulb.set_meta("seed", hash(tile))
	var flick := LightFlicker.new()
	flick.buzz_enabled = false
	bulb.add_child(flick)
	out.lights.append({"tile": tile, "position": pos, "mode": 1, "node": node, "pocket": "chapel"})


# =========================================================================
# the sanctuary
# =========================================================================

static func _build_sanctuary(root: Node3D, body: StaticBody3D, props: Common.Props, lay: Dictionary, world: Callable,
		stone: Material, oak: Material, brass: Material, linen: Material, out: Dictionary) -> void:
	var lights := _candlelight(root)
	var mb := Common.MeshBuilder.new()
	# The step up into the sanctuary, across the full width of the nave.
	var sa: Vector3 = world.call(Vector2(NAVE.position.x, SANCTUARY_Y))
	var sb: Vector3 = world.call(Vector2(NAVE.end.x, SANCTUARY_Y + 1))
	mb.box("s", stone, Transform3D(Basis(), (sa + sb) * 0.5 + Vector3(0, 0.07, 0)), Vector3(sb.x - sa.x, 0.14, sb.z - sa.z))
	Common.collider(body, Transform3D(Basis(), (sa + sb) * 0.5 + Vector3(0, 0.07, 0)), Vector3(sb.x - sa.x, 0.14, sb.z - sa.z))
	# The altar: a stone table under a linen cloth.
	var al: Vector3 = world.call(Vector2(lay.altar) + Vector2(1.0, 0.5))
	mb.box("s", stone, Transform3D(Basis(), al + Vector3(0, 0.46, 0)), Vector3(2.8, 0.92, 1.1))
	mb.box("l", linen, Transform3D(Basis(), al + Vector3(0, 0.94, 0)), Vector3(2.9, 0.04, 1.2))
	Common.collider(body, Transform3D(Basis(), al + Vector3(0, 0.48, 0)), Vector3(2.8, 0.96, 1.15))
	Common.anchor(out, al + Vector3(-0.9, 0.97, 0.0), 0.0, "counter", "chapel_sanctuary")
	Common.anchor(out, al + Vector3(0.9, 0.97, 0.0), 0.0, "counter", "chapel_sanctuary")
	# A pair of altar candles, and the credence table beside it.
	var taper := _taper_mesh()
	for sx in [-1.05, 1.05]:
		mb.cylinder("b", brass, Transform3D(Basis(), al + Vector3(sx, 1.02, 0)), 0.09, 0.12, 10)
		props.add(taper, Transform3D(Basis().scaled(Vector3(1, 1.6, 1)), al + Vector3(sx, 1.08, 0)), 0.0, false)
	var cr: Vector3 = world.call(Vector2(lay.credence) + Vector2(1.0, 0.5))
	mb.box("w", oak, Transform3D(Basis(), cr + Vector3(0, 0.76, 0)), Vector3(1.6, 0.06, 0.6))
	for sx in [-0.72, 0.72]:
		for sz in [-0.24, 0.24]:
			mb.box("w", oak, Transform3D(Basis(), cr + Vector3(sx, 0.38, sz)), Vector3(0.07, 0.76, 0.07))
	Common.collider(body, Transform3D(Basis(), cr + Vector3(0, 0.39, 0)), Vector3(1.6, 0.78, 0.6))
	Common.anchor(out, cr + Vector3(0, 0.80, 0), 0.0, "counter", "chapel_sanctuary")
	# The reredos: a wall of votive tiers behind the altar, the brightest thing in the building.
	var rr: Vector3 = world.call(Vector2(lay.reredos) + Vector2(1.0, 0.5))
	mb.box("s", stone, Transform3D(Basis(), rr + Vector3(0, 2.2, 0.45)), Vector3(5.0, 4.4, 0.4))
	var votive := _votive_mesh()
	for k in 6:
		mb.box("b", brass, Transform3D(Basis(), rr + Vector3(0, 0.55 + k * 0.42, 0.10)), Vector3(4.4, 0.04, 0.26))
		for i in 17:
			props.add(votive, Transform3D(Basis(), rr + Vector3(-2.1 + i * 0.26, 0.58 + k * 0.42, 0.10)), 0.0, false)
	Common.collider(body, Transform3D(Basis(), rr + Vector3(0, 2.2, 0.35)), Vector3(5.0, 4.4, 0.6))
	var mi := MeshInstance3D.new()
	mi.name = "Sanctuary"
	mi.mesh = mb.commit()
	root.add_child(mi)
	# The sanctuary draws on the light budget first, so it can never leave the altar dark.
	_add_light(lights, out, lay.reredos, rr + Vector3(0, 1.9, -0.4), 7.0, 26.0)
	_add_light(lights, out, lay.altar, al + Vector3(0, 1.5, 0), 5.0, 18.0)


# =========================================================================
# the sacristy
# =========================================================================

static func _build_sacristy(root: Node3D, body: StaticBody3D, props: Common.Props, lay: Dictionary, world: Callable,
		oak: Material, linen: Material, out: Dictionary) -> void:
	var slab := Common.tri_mat("chp_slab", "mat/concrete", Color(0.24, 0.23, 0.22), 0.4, 0.92)
	var mb := Common.MeshBuilder.new()
	var a: Vector3 = world.call(Vector2(SACRISTY_BLOCK.position), SACRISTY_CEIL)
	var b: Vector3 = world.call(Vector2(SACRISTY_BLOCK.end), SACRISTY_TOP)
	mb.box("s", slab, Transform3D(Basis(), (a + b) * 0.5), b - a)
	Common.collider(body, Transform3D(Basis(), (a + b) * 0.5), b - a)
	# A vesting bench with a folded alb on it.
	var bp: Vector3 = world.call(Vector2(SACRISTY.position.x + 2.5, SACRISTY.end.y - 0.5))
	mb.box("w", oak, Transform3D(Basis(), bp + Vector3(0, 0.78, 0)), Vector3(2.0, 0.07, 0.62))
	for sx in [-0.9, 0.9]:
		mb.box("w", oak, Transform3D(Basis(), bp + Vector3(sx, 0.39, 0)), Vector3(0.08, 0.78, 0.55))
	mb.box("l", linen, Transform3D(Basis(Vector3.UP, 0.15), bp + Vector3(-0.45, 0.85, 0.02)), Vector3(0.55, 0.10, 0.38))
	Common.collider(body, Transform3D(Basis(), bp + Vector3(0, 0.40, 0)), Vector3(2.0, 0.80, 0.62))
	Common.anchor(out, bp + Vector3(0.5, 0.82, 0.0), 0.0, "counter", "chapel_sacristy")
	var mi := MeshInstance3D.new()
	mi.name = "Sacristy"
	mi.mesh = mb.commit()
	root.add_child(mi)
	# The one candle in here, on the bench: the sacristy has no window and no fixture either.
	props.add(_taper_mesh(), Transform3D(Basis(), bp + Vector3(0.75, 0.82, 0)), 0.0, false)
	_add_light(_candlelight(root), out, SACRISTY.position, bp + Vector3(0.75, 1.15, 0), 2.5, 8.0)
