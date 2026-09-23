extends RefCounted
## POCKETS 2: a pocket space bleeding into the hospital around its entrances.
##
## A pocket's own loot never *rolls* in the hospital, and that does not change: its LootTable `rooms`
## names only its own room kinds and omits "*", and LootSpawner._can_place refuses it anywhere else
## (0.10.36, the shift-without-a-pool whistle leak). This is a second, much narrower door next to
## that guard rather than a hole in it.
##
## On a shift that actually has a pocket, one or two stacks that would have spawned somewhere in the
## hospital are **replaced** by that pocket's own items, and only in the handful of rooms nearest one
## of its entrances: the rooms around the seam start showing traces of what is through it. The loot
## budget is never added to -- a bled stack is a stack the hospital did not get -- and the swap is
## like for like (a trinket for a trinket, a plain stack for a plain stack), so the shift still holds
## LootSpawner.LOOT_PER_SHIFT stacks and LootTable.TRINKETS_PER_SHIFT trinkets.
##
## "Rooms near the seam", in hospital terms. An entrance is a U-shaped hallway stub carved into one
## or two wing room slots (scripts/level/pockets/stub.gd): leg 1's *mouth* is the pair of tiles where
## it opens onto the wing hallway, and that is the seam's address in the hospital's own grid. From
## each mouth this walks the hallway outward, never stepping through a room, and takes the first
## ROOM_RADIUS rooms it reaches -- the rooms you pass walking away from the entrance, counted in
## rooms and not in metres.
##
## Determinism. Everything here is a pure function of `level_info`, which every machine builds from
## the same seed (the pocket kind itself rides the shift's globals as "px" for exactly that reason),
## and the roll runs last on the loot plan's own stream, so it perturbs nothing before it. Host and
## client that ask the same question get the same answer even though only the host asks.

## How many rooms out from each entrance mouth count as "near the seam".
const ROOM_RADIUS := 3
## Stacks a shift's pocket bleeds, in total across every entrance (inclusive range). Deliberately
## tiny against LootSpawner.LOOT_PER_SHIFT: a trace, not a shop window.
const BLEED_PER_SHIFT := [1, 2]
## Width of leg 1's mouth in tiles. This is Stub.CORRIDOR; it is spelt out rather than preloaded
## because loot planning runs under `-s` tools that must not drag in the pocket runtime, and
## tools/pockettest.gd checks the two agree.
const MOUTH_TILES := 2
## A hallway walk that has not found its rooms by here gives up (a stub walled off by a door pass).
const WALK_BUDGET := 4000

const OPEN_CHARS := ".+TMP"
const DIRS: Array[Vector2i] = [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]


## The pocket space this shift has, or "" for a shift without one (which bleeds nothing).
static func pocket_kind(info: Dictionary) -> String:
	var plan: Dictionary = info.get("pocket_plan", {})
	return String(plan.get("kind", ""))


## Hospital tiles (as `y * width + x`) of every room within ROOM_RADIUS rooms of an entrance mouth,
## walls included. {} when this shift has no pocket. A location whose tile is in here is near a seam.
static func seam_tiles(info: Dictionary) -> Dictionary:
	var out := {}
	var ids := seam_rooms(info)
	if ids.is_empty():
		return out
	var size: Vector2i = info.get("size", Vector2i.ZERO)
	var w := int(size.x)
	var h := int(size.y)
	var rows: PackedStringArray = info.get("rows", PackedStringArray())
	for r in info.get("rooms", []):
		if not ids.has(int(r.get("id", -1))):
			continue
		var t: Rect2i = r.get("tiles", Rect2i())
		for y in range(t.position.y, t.end.y):
			for x in range(t.position.x, t.end.x):
				if x < 0 or y < 0 or x >= w or y >= h:
					continue
				out[y * w + x] = true
				# A container stands against a wall and its node origin can sit on the wall tile
				# itself, which is outside the room's rect. The wall of a seam room is the seam
				# room's, so take it too -- but only when it really is wall, never a way through.
				for d in DIRS:
					var nx := x + d.x
					var ny := y + d.y
					if nx >= 0 and ny >= 0 and nx < w and ny < h and _ch(rows, nx, ny) == "#":
						out[ny * w + nx] = true
	return out


## {room id: true} for the rooms near a seam. See the header for what "near" means.
static func seam_rooms(info: Dictionary) -> Dictionary:
	var out := {}
	var plan: Dictionary = info.get("pocket_plan", {})
	if String(plan.get("kind", "")) == "":
		return out
	var rows: PackedStringArray = info.get("rows", PackedStringArray())
	var size: Vector2i = info.get("size", Vector2i.ZERO)
	var w := int(size.x)
	var h := int(size.y)
	if rows.is_empty() or w <= 0 or h <= 0:
		return out
	var room_at := _room_grid(info, w, h)
	for stub in plan.get("stubs", []):
		for id in _walk_from(stub, rows, room_at, w, h):
			out[id] = true
	return out


## Room index per tile, -1 outside every room.
static func _room_grid(info: Dictionary, w: int, h: int) -> PackedInt32Array:
	var grid := PackedInt32Array()
	grid.resize(w * h)
	grid.fill(-1)
	for r in info.get("rooms", []):
		var id := int(r.get("id", -1))
		var t: Rect2i = r.get("tiles", Rect2i())
		for y in range(maxi(0, t.position.y), mini(h, t.end.y)):
			for x in range(maxi(0, t.position.x), mini(w, t.end.x)):
				grid[y * w + x] = id
	return grid


## The ROOM_RADIUS rooms nearest one stub's mouth, by hallway steps. The walk starts on the two
## hallway tiles leg 1 opens onto (stub-local (u, -1)) and spreads over open tiles that belong to no
## room; a room is "reached" the moment the walk touches one of its tiles, and is not walked through,
## so the count is rooms passed and not tiles crossed. Ties break on room id, so two machines that
## built the same hospital pick the same rooms.
static func _walk_from(stub: Dictionary, rows: PackedStringArray, room_at: PackedInt32Array, w: int, h: int) -> Array:
	var o: Vector2i = stub.get("o", Vector2i.ZERO)
	var eu: Vector2i = stub.get("eu", Vector2i.ZERO)
	var ev: Vector2i = stub.get("ev", Vector2i.ZERO)
	var seen := {}
	var queue: Array[int] = []
	var depth: Array[int] = []
	for u in MOUTH_TILES:
		var t: Vector2i = o + eu * u - ev
		if t.x < 0 or t.y < 0 or t.x >= w or t.y >= h:
			continue
		var i := t.y * w + t.x
		if seen.has(i) or not _open(rows, t.x, t.y) or room_at[i] >= 0:
			continue
		seen[i] = true
		queue.append(i)
		depth.append(0)
	var found := {}   # room id -> steps
	var head := 0
	while head < queue.size() and head < WALK_BUDGET:
		var i: int = queue[head]
		var d: int = depth[head]
		head += 1
		var x := i % w
		var y := i / w
		for dir in DIRS:
			var nx := x + dir.x
			var ny := y + dir.y
			if nx < 0 or ny < 0 or nx >= w or ny >= h:
				continue
			var j := ny * w + nx
			if seen.has(j) or not _open(rows, nx, ny):
				continue
			seen[j] = true
			var room := room_at[j]
			if room >= 0:
				# A room is reached, not entered: the walk stops at its edge.
				if not found.has(room):
					found[room] = d + 1
				continue
			queue.append(j)
			depth.append(d + 1)
	var order: Array = found.keys()
	order.sort_custom(func(a, b):
		return int(found[a]) < int(found[b]) if int(found[a]) != int(found[b]) else int(a) < int(b))
	return order.slice(0, ROOM_RADIUS)


static func _ch(rows: PackedStringArray, x: int, y: int) -> String:
	return rows[y].substr(x, 1) if y >= 0 and y < rows.size() and x >= 0 and x < rows[y].length() else "#"


static func _open(rows: PackedStringArray, x: int, y: int) -> bool:
	return OPEN_CHARS.contains(_ch(rows, x, y))
