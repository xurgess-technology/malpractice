extends SceneTree
## Offline check for the minimap's shared fog of war (scripts/minimap.gd).
##
##   godot --headless --path . --script tools/minimapcheck.gd [-- --seeds=40 --first=1]
##
## Pure data: it generates hospitals and bakes the fog off `level_info`, with no 3D build and no
## game, so it is fast and says nothing about what is on screen.
##
## What it proves, per seed:
##   - the bake finds rooms, corridors and doorways, and every tile is exactly one of room /
##     corridor / outdoor / solid;
##   - the hub is visible from the start and NO ward room is;
##   - **walking past a ward room does not reveal it**: standing on the corridor tile outside its
##     doorway leaves it dark, and the corridor flood never lights a single room;
##   - stepping into the room (or standing in its doorway, which a closed door makes impossible)
##     does reveal it, all at once;
##   - the wire masks are the size they should be, and setting a bit is idempotent.
## Exits non-zero when anything fails.

const MG := preload("res://scripts/mapgen.gd")
const HB := preload("res://scripts/hospital_builder.gd")
const MM := preload("res://scripts/minimap.gd")

var failures: PackedStringArray = []
var first_seed := 1
var seed_count := 40


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		if kv.size() < 2:
			continue
		match kv[0]:
			"seeds": seed_count = int(kv[1])
			"first": first_seed = int(kv[1])
	var t0 := Time.get_ticks_msec()
	var bake_ms := 0
	for s in range(first_seed, first_seed + seed_count):
		var gen: Dictionary = MG.generate(s)
		var info := {"rows": gen.rows, "wing_gen": 0}
		HB._fill_contract(gen, info)
		var mm = MM.new()
		var b0 := Time.get_ticks_usec()
		mm.bake(info, 0)
		bake_ms += Time.get_ticks_usec() - b0
		_check_seed(s, mm, info)
		mm.free()
	print("")
	print("%d seeds in %d ms (baking: %.1f ms per map)" % [seed_count, Time.get_ticks_msec() - t0,
			float(bake_ms) / 1000.0 / float(seed_count)])
	if failures.is_empty():
		print("[minimap] result=PASS seeds=%d" % seed_count)
		quit(0)
		return
	for f in failures:
		print("  FAIL %s" % f)
	print("[minimap] result=FAIL failures=%d" % failures.size())
	quit(1)


func _fail(seed_value: int, msg: String) -> void:
	if failures.size() < 40:
		failures.append("seed %d: %s" % [seed_value, msg])


func _check_seed(s: int, mm, info: Dictionary) -> void:
	if not mm.has_map():
		_fail(s, "no map baked")
		return
	if mm.room_count <= 0 or mm.corr_count <= 0:
		_fail(s, "baked %d rooms / %d corridor tiles" % [mm.room_count, mm.corr_count])
		return
	# The masks are exactly as wide as what they index.
	if mm.seen_rooms.size() != (mm.room_count + 7) >> 3 or mm.seen_corr.size() != (mm.corr_count + 7) >> 3:
		_fail(s, "mask sizes %d/%d do not match %d rooms / %d corridor tiles" % [
				mm.seen_rooms.size(), mm.seen_corr.size(), mm.room_count, mm.corr_count])
	# A tile is a room tile or a corridor tile, never both.
	var doors := 0
	for i in mm.kind.size():
		if mm.kind[i] == MM.K_DOOR:
			doors += 1
		if mm.room_at[i] >= 0 and mm.corr_at[i] >= 0:
			_fail(s, "tile %d is in a room and a corridor at once" % i)
			break
	if doors == 0:
		_fail(s, "no doorway tiles in the bake")

	# The hub starts visible, the wards start dark.
	var rooms: Array = info.rooms
	var hub_dark := 0
	var ward_lit := 0
	var wards: Array[int] = []
	for i in rooms.size():
		var wing := String(rooms[i].get("wing", ""))
		var is_ward := wing != "" and wing != "entrance"
		if is_ward:
			wards.append(i)
			if mm.room_seen(i):
				ward_lit += 1
		elif not mm.room_seen(i):
			hub_dark += 1
	if hub_dark > 0:
		_fail(s, "%d hub rooms start fogged" % hub_dark)
	if ward_lit > 0:
		_fail(s, "%d ward rooms start revealed" % ward_lit)
	if wards.is_empty():
		_fail(s, "no ward rooms to explore")
		return

	# Walking past must not reveal. For every ward room, stand on each corridor tile just outside
	# each of its doorways and check the room -- and every other room -- stays dark.
	var lit_before := _lit_rooms(mm)
	var tried := 0
	for i in wards:
		for d in (rooms[i].get("doors", []) as Array):
			var dt: Vector2i = C.world_to_tile(d)
			for n in MM.DIRS:
				var o: Vector2i = dt + n
				if o.x < 0 or o.y < 0 or o.x >= mm.w or o.y >= mm.h:
					continue
				if mm.corr_at[o.y * mm.w + o.x] < 0:
					continue   # not a corridor tile: inside the room, or solid
				tried += 1
				mm._reveal_at(o)
	if tried == 0:
		_fail(s, "no corridor tile outside any ward doorway to test")
	if _lit_rooms(mm) != lit_before:
		_fail(s, "standing in the corridor outside a ward doorway revealed a room (%d -> %d lit)" % [
				lit_before, _lit_rooms(mm)])

	# Stepping in does reveal it, and only it.
	var target: int = -1
	var inside := Vector2i(-1, -1)
	for i in wards:
		var r: Rect2i = rooms[i].tiles
		for y in range(r.position.y + 1, r.end.y - 1):
			for x in range(r.position.x + 1, r.end.x - 1):
				if x >= 0 and y >= 0 and x < mm.w and y < mm.h and mm.kind[y * mm.w + x] == MM.K_FLOOR \
						and mm.room_at[y * mm.w + x] == i:
					target = i
					inside = Vector2i(x, y)
					break
			if target >= 0:
				break
		if target >= 0:
			break
	if target < 0:
		_fail(s, "no ward room with an interior floor tile")
		return
	var before := _lit_rooms(mm)
	mm._reveal_at(inside)
	if not mm.room_seen(target):
		_fail(s, "standing inside ward room %d did not reveal it" % target)
	if _lit_rooms(mm) != before + 1:
		_fail(s, "stepping into one room lit %d rooms" % (_lit_rooms(mm) - before))
	# Idempotent: standing there again reveals nothing new.
	var again := _lit_rooms(mm)
	mm._reveal_at(inside)
	if _lit_rooms(mm) != again:
		_fail(s, "re-entering a revealed room changed the fog")


func _lit_rooms(mm) -> int:
	var n := 0
	for i in mm.room_count:
		if mm.room_seen(i):
			n += 1
	return n
