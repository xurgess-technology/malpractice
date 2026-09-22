class_name Minimap
extends Node
## The party's shared map knowledge: what of St. Doe's has been explored this shift.
##
## THE FOG IS THE TEAM'S, NOT YOURS. One fog state for the whole party, host authoritative and
## replicated: a ward a teammate walks lights up on your minimap too, whether or not you have ever
## been there. Drawn by scripts/minimap_panel.gd.
##
## WHAT COUNTS AS EXPLORED. Proximity reveals nothing: jogging a corridor past six closed doors
## leaves all six rooms dark. Two units, two rules:
##   rooms      a whole room lights up when a player stands inside its tile rect. The rect includes
##              the room's walls, so its doorways count -- standing in an open door looking in is
##              enough. A CLOSED DOOR IS SOLID, so you cannot be in that rect without having opened
##              it: door state needs no query, the geometry already says it.
##   corridors  the tiles you walk, flooded CORR_RADIUS tiles over corridor tiles only. The flood
##              never enters a room rect, so a hallway reveals itself and nothing hanging off it.
##
## THE HUB IS NEVER FOGGED. The generator already labels every tile with a zone
## (`level_info.zones`): "entrance" is the hub building, "neutral" the lot, and every other name is
## one of this shift's wings. Entrance and neutral tiles are revealed at bake time; the wings are
## what you go and earn.
##
## ON THE WIRE. Two bitmasks (one bit per room, one per corridor tile) -- about 220 bytes for a
## whole map, so the full state is one small reliable message. The host sends it to a peer that is
## new or a generation behind, re-sends it every RESYNC_SECONDS so nothing can quietly desync, and
## pushes newly-revealed ids as they happen so a ward opening is a team event you see at once. Bits
## only ever go up, so a delta and a full state can land in any order.
##
## The wings regenerate every shift (scripts/level/wing_loader.gd), so the bake is keyed on
## `level_info.wing_gen` and the fog resets with it.

const C_ = preload("res://scripts/consts.gd")

## Tiles the corridor flood reaches from a player standing in a corridor (1 tile = 1.5 m).
const CORR_RADIUS := 2
## How often the host looks at where everyone is standing.
const REVEAL_HZ := 6.0
## The host re-sends the whole fog this often, so a dropped delta or a missed join heals itself.
const RESYNC_SECONDS := 3.0

# Tile kinds the panel draws.
const K_NONE := 0
const K_FLOOR := 1
const K_DOOR := 2
const K_OUTDOOR := 3

const DIRS: Array[Vector2i] = [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]

var game: Node = null

## The baked map, all in tile space. Empty until a level with `rows` exists.
var w: int = 0
var h: int = 0
var kind: PackedByteArray = PackedByteArray()
## Room index per tile, -1 for corridor / outdoor / solid.
var room_at: PackedInt32Array = PackedInt32Array()
## Corridor slot per tile (indexes the `seen_corr` bitmask), -1 when the tile is not a corridor.
var corr_at: PackedInt32Array = PackedInt32Array()
var corr_count: int = 0
var room_count: int = 0

## One bit per room / per corridor slot. Monotone: bits are only ever set.
var seen_rooms: PackedByteArray = PackedByteArray()
var seen_corr: PackedByteArray = PackedByteArray()

## Bumped whenever the fog or the bake changes, so the panel knows to redraw and otherwise does not.
var revision: int = 0
## The wing generation this bake belongs to; -1 when there is no map.
var generation: int = -1

var _baked_info: Dictionary = {}
## The generation the last bake ATTEMPTED, even when it found no map: without it a level with no
## `rows` (the dev room) would re-bake, and churn `revision`, every single frame.
var _baked_gen: int = -999
var _reveal_t: float = 0.0
var _resync_t: float = 0.0
## Newly revealed since the last delta went out.
var _new_rooms: PackedInt32Array = PackedInt32Array()
var _new_corr: PackedInt32Array = PackedInt32Array()
## peer id -> the generation whose full state it has been sent.
var _sent: Dictionary = {}


func setup(g: Node) -> void:
	game = g


func has_map() -> bool:
	return w > 0 and h > 0


func _process(delta: float) -> void:
	if game == null:
		return
	var info: Dictionary = game.level_info
	if info.is_empty():
		if has_map():
			_clear()
		return
	var gen := int(info.get("wing_gen", 0))
	if not is_same(_baked_info, info) or gen != _baked_gen:
		bake(info, gen)
	if not has_map() or not game.is_host():
		return
	_reveal_t += delta
	if _reveal_t >= 1.0 / REVEAL_HZ:
		_reveal_t = 0.0
		_reveal_around_players()
	_resync_t += delta
	_send()


# =========================================================================
# baking the map
# =========================================================================

func _clear() -> void:
	w = 0
	h = 0
	kind = PackedByteArray()
	room_at = PackedInt32Array()
	corr_at = PackedInt32Array()
	corr_count = 0
	room_count = 0
	seen_rooms = PackedByteArray()
	seen_corr = PackedByteArray()
	generation = -1
	_baked_info = {}
	_baked_gen = -999
	_sent.clear()
	_new_rooms = PackedInt32Array()
	_new_corr = PackedInt32Array()
	revision += 1


## Turn `level_info` into the flat tile arrays the panel draws and the fog indexes. A few
## milliseconds, once per level build and once per shift's wing regeneration -- never per frame.
func bake(info: Dictionary, gen: int) -> void:
	_clear()
	_baked_info = info
	_baked_gen = gen
	var rows: PackedStringArray = info.get("rows", PackedStringArray())
	if rows.is_empty() or rows[0].length() == 0:
		return
	w = rows[0].length()
	h = rows.size()
	generation = gen
	_baked_info = info
	var n := w * h
	kind = PackedByteArray()
	kind.resize(n)
	room_at = PackedInt32Array()
	room_at.resize(n)
	room_at.fill(-1)
	corr_at = PackedInt32Array()
	corr_at.resize(n)
	corr_at.fill(-1)
	for y in h:
		var row: String = rows[y]
		var base := y * w
		var cols: int = mini(w, row.length())
		for x in cols:
			match row.unicode_at(x):
				46, 80, 84, 77:   # '.' 'P' 'T' 'M'
					kind[base + x] = K_FLOOR
				43:               # '+'
					kind[base + x] = K_DOOR
				44:               # ',' the lot outside
					kind[base + x] = K_OUTDOOR
	# Rooms, in the generator's own order so later rooms win a shared wall the same way it does.
	var rooms: Array = info.get("rooms", [])
	room_count = rooms.size()
	for i in room_count:
		var r: Rect2i = rooms[i].get("tiles", Rect2i())
		for y in range(maxi(r.position.y, 0), mini(r.end.y, h)):
			var base := y * w
			for x in range(maxi(r.position.x, 0), mini(r.end.x, w)):
				room_at[base + x] = i
	# Every indoor tile outside a room is corridor, and gets its own bit.
	for i in n:
		if room_at[i] < 0 and (kind[i] == K_FLOOR or kind[i] == K_DOOR):
			corr_at[i] = corr_count
			corr_count += 1
	seen_rooms = PackedByteArray()
	seen_rooms.resize((room_count + 7) >> 3)
	seen_corr = PackedByteArray()
	seen_corr.resize((corr_count + 7) >> 3)
	_reveal_hub(info, rooms)
	revision += 1


## The hub is visible from the start. The zone grid names every tile: "entrance" is the hospital
## building you come back to, "neutral" the lot around it, and anything else is one of this shift's
## wings. Without a zone grid (the dev room, the fallback ward) there are no wings to earn, so
## everything is visible.
func _reveal_hub(info: Dictionary, rooms: Array) -> void:
	var zones: Dictionary = info.get("zones", {})
	if zones.is_empty():
		seen_rooms.fill(0xFF)
		seen_corr.fill(0xFF)
		return
	var grid: PackedByteArray = zones.get("grid", PackedByteArray())
	var zw := int(zones.get("width", 0))
	var names: Dictionary = zones.get("names", {})
	# A flat table rather than a dictionary: this is read once per tile of the whole map.
	var home := PackedByteArray()
	home.resize(256)
	for id in names:
		var nm := String(names[id])
		if (nm == "entrance" or nm == "neutral") and int(id) >= 0 and int(id) < 256:
			home[int(id)] = 1
	if grid.is_empty() or zw <= 0:
		return
	for i in room_count:
		var r: Rect2i = rooms[i].get("tiles", Rect2i())
		var cx: int = clampi(r.position.x + r.size.x / 2, 0, w - 1)
		var cy: int = clampi(r.position.y + r.size.y / 2, 0, h - 1)
		var gi := cy * zw + cx
		if gi < grid.size() and home[grid[gi]] != 0:
			_set_bit(seen_rooms, i)
	for y in h:
		var base := y * w
		for x in w:
			var ci := corr_at[base + x]
			if ci < 0:
				continue
			var gi := y * zw + x
			if gi < grid.size() and home[grid[gi]] != 0:
				_set_bit(seen_corr, ci)


# =========================================================================
# reading the fog (the panel)
# =========================================================================

func room_seen(i: int) -> bool:
	return _bit(seen_rooms, i)


func corr_seen(i: int) -> bool:
	return _bit(seen_corr, i)


## Is the tile at flat index `i` explored? Outdoor ground is always known.
func tile_seen(i: int) -> bool:
	if kind[i] == K_OUTDOOR:
		return true
	var r := room_at[i]
	if r >= 0:
		return _bit(seen_rooms, r)
	var c := corr_at[i]
	return c >= 0 and _bit(seen_corr, c)


## The wing (or "entrance" / "neutral") a world point is in, for the panel's label.
func zone_name_at(p: Vector3) -> String:
	var info: Dictionary = _baked_info
	var zones: Dictionary = info.get("zones", {})
	if zones.is_empty():
		return ""
	var grid: PackedByteArray = zones.get("grid", PackedByteArray())
	var zw := int(zones.get("width", 0))
	var t := C_.world_to_tile(p)
	if zw <= 0 or t.x < 0 or t.y < 0 or t.x >= zw or t.y >= int(zones.get("height", 0)):
		return ""
	var gi := t.y * zw + t.x
	if gi >= grid.size():
		return ""
	return String((zones.get("names", {}) as Dictionary).get(int(grid[gi]), ""))


# =========================================================================
# revealing (host)
# =========================================================================

func _reveal_around_players() -> void:
	for p in game.players.values():
		if p == null or not is_instance_valid(p) or not bool(p.alive):
			continue
		_reveal_at(C_.world_to_tile(p.global_position))


func _reveal_at(t: Vector2i) -> void:
	if t.x < 0 or t.y < 0 or t.x >= w or t.y >= h:
		return
	var i := t.y * w + t.x
	var r := room_at[i]
	if r >= 0:
		# Inside the room's rect: you opened it and went in (or you are standing in its open door).
		if _set_bit(seen_rooms, r):
			_new_rooms.append(r)
			revision += 1
		return
	if corr_at[i] < 0:
		return
	# A corridor: the hallway around you, and only over corridor tiles -- the flood cannot step into
	# a room, so walking past a door tells you nothing about what is behind it.
	var frontier: Array[int] = [i]
	var seen := {i: true}
	_mark_corr(i)
	for _step in CORR_RADIUS:
		var next: Array[int] = []
		for j in frontier:
			var jx := j % w
			var jy := j / w
			for d in DIRS:
				var nx := jx + d.x
				var ny := jy + d.y
				if nx < 0 or ny < 0 or nx >= w or ny >= h:
					continue
				var ni := ny * w + nx
				if seen.has(ni) or corr_at[ni] < 0:
					continue
				seen[ni] = true
				_mark_corr(ni)
				next.append(ni)
		frontier = next


func _mark_corr(i: int) -> void:
	var c := corr_at[i]
	if c >= 0 and _set_bit(seen_corr, c):
		_new_corr.append(c)
		revision += 1


# =========================================================================
# the wire
# =========================================================================

func _send() -> void:
	# Solo (or a host nobody has joined yet): nothing to tell.
	var peers: Array = multiplayer.get_peers() if multiplayer.has_multiplayer_peer() else []
	if peers.is_empty():
		_new_rooms = PackedInt32Array()
		_new_corr = PackedInt32Array()
		_sent.clear()
		return
	var resync := _resync_t >= RESYNC_SECONDS
	if resync:
		_resync_t = 0.0
	for id in peers:
		var pid := int(id)
		if resync or int(_sent.get(pid, -999)) != generation:
			_sent[pid] = generation
			game._event.rpc_id(pid, "mm_fog", {"g": generation, "r": seen_rooms, "c": seen_corr})
	for id in _sent.keys():
		if not peers.has(int(id)):
			_sent.erase(id)
	if _new_rooms.is_empty() and _new_corr.is_empty():
		return
	game._event.rpc("mm_fog+", {"g": generation, "r": _new_rooms, "c": _new_corr})
	_new_rooms = PackedInt32Array()
	_new_corr = PackedInt32Array()


## A client: the host's fog. A packet for a generation this machine has not baked yet is dropped --
## the next resync (RESYNC_SECONDS) brings it back once the wings have landed.
func on_event(kind_: String, data: Dictionary) -> void:
	if not has_map() or int(data.get("g", -1)) != generation:
		return
	if kind_ == "mm_fog":
		var r: PackedByteArray = data.get("r", PackedByteArray())
		var c: PackedByteArray = data.get("c", PackedByteArray())
		var changed := false
		for i in mini(r.size(), seen_rooms.size()):
			if seen_rooms[i] != (seen_rooms[i] | r[i]):
				seen_rooms[i] = seen_rooms[i] | r[i]
				changed = true
		for i in mini(c.size(), seen_corr.size()):
			if seen_corr[i] != (seen_corr[i] | c[i]):
				seen_corr[i] = seen_corr[i] | c[i]
				changed = true
		if changed:
			revision += 1
		return
	if kind_ == "mm_fog+":
		for i in (data.get("r", PackedInt32Array()) as PackedInt32Array):
			if _set_bit(seen_rooms, int(i)):
				revision += 1
		for i in (data.get("c", PackedInt32Array()) as PackedInt32Array):
			if _set_bit(seen_corr, int(i)):
				revision += 1


# =========================================================================
# bits
# =========================================================================

static func _bit(mask: PackedByteArray, i: int) -> bool:
	if i < 0:
		return false
	var b := i >> 3
	return b < mask.size() and (mask[b] & (1 << (i & 7))) != 0


## Sets bit `i`, returning true only when it was not already set.
static func _set_bit(mask: PackedByteArray, i: int) -> bool:
	if i < 0:
		return false
	var b := i >> 3
	if b >= mask.size():
		return false
	var m := 1 << (i & 7)
	if (mask[b] & m) != 0:
		return false
	mask[b] = mask[b] | m
	return true
