extends Node
## MINIMAP smoke look: windowed screenshots of the top-right floor plan filling in as a ward is
## walked, into tools/minimap_shots/ (gitignored). Run it through tools\minimapshot.ps1, which
## starts the window minimized so it never takes focus (RULES.md, Tests that make sense).
##
## Each step writes two files: the whole screen, and `_zoom`, the panel's own corner scaled 3x,
## because a 152 px element is unreadable in a 1280x720 shot.
##
##   01_hub          standing where you spawn: the hub inked in, every ward blank
##   02_corridor     part way down a ward corridor: a trail of hallway, rooms beside it still dark
##   03_at_door      standing in the corridor OUTSIDE a ward room's doorway: the room is STILL dark
##   04_inside       one tile further, inside that room: the whole room lights up at once
##
## 03 and 04 are the pair that matters -- they are the same room one tile apart, and the difference
## between them is the whole rule (tools/minimapcheck.gd proves it offline over 40 seeds).
##
## A solo session on the usual hospital (seed 4242). The player is teleported from spot to spot
## rather than walked, which is if anything a harder test: nothing is revealed between two spots,
## so what you see is exactly what the reveal rules granted.

const SHOT_DIR := "res://tools/minimap_shots"
## Long enough for the host's 6 Hz reveal tick to fire a few times.
const DWELL := 0.7

var main: Node3D
var game: Game
var me: Player
var mm: Node
var t := 0.0


func _ready() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	game = main.game
	if main.launching:
		await main.launched
	main.menu.hide_menu()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SHOT_DIR))
	Net.start_solo("Zach")
	game.start_session(4242)
	while game.get_parent().has_node("WarmupCover"):
		await get_tree().process_frame
	await _seconds(1.0)
	me = game.local_player()
	me.bot_active = true
	mm = game.minimap
	if mm == null or not mm.has_map():
		print("[minimapshot] NO MAP BAKED -- nothing to look at")
		get_tree().quit(1)
		return
	print("[minimapshot] palette room=%s wall=%s arrow=%s" % [
			MinimapPanel.ROOM.to_html(), MinimapPanel.WALL.to_html(), MinimapPanel.ARROW.to_html()])
	print("[minimapshot] map %dx%d, %d rooms, %d corridor tiles" % [int(mm.w), int(mm.h), int(mm.room_count), int(mm.corr_count)])
	print("[minimapshot] hub lit at bake: %d of %d rooms" % [_lit(), int(mm.room_count)])

	await _seconds(DWELL)
	await _shot("01_hub")

	var plan := _pick_room()
	if plan.is_empty():
		print("[minimapshot] found no ward room with a doorway onto a corridor")
		get_tree().quit(1)
		return
	print("[minimapshot] ward room %d (%s), door tile %s, corridor outside %s" % [
			int(plan.room), String(plan.kind), plan.door, plan.outside])

	# Walk the hallway in toward the door, so there is a real trail rather than one lit patch.
	for step in (plan.trail as Array):
		_stand(step)
		await _seconds(0.22)
	await _seconds(DWELL)
	await _shot("02_corridor")

	# The corridor tile outside the door. The room must still be dark here.
	_stand(plan.outside)
	_face(plan.inside)
	await _seconds(DWELL)
	_diag("03_at_door")
	var dark_outside: bool = not mm.room_seen(int(plan.room))
	print("[minimapshot] standing outside the doorway: room %d revealed = %s (want false)" % [
			int(plan.room), not dark_outside])
	await _shot("03_at_door")

	# One tile in. The room must light up.
	_stand(plan.inside)
	await _seconds(DWELL)
	_diag("04_inside")
	var lit_inside: bool = mm.room_seen(int(plan.room))
	print("[minimapshot] standing inside: room %d revealed = %s (want true)" % [int(plan.room), lit_inside])
	await _shot("04_inside")

	print("[minimapshot] VERDICT outside-dark=%s inside-lit=%s" % [dark_outside, lit_inside])
	print("[minimapshot] %d of %d rooms lit at the end" % [_lit(), int(mm.room_count)])
	get_tree().quit(0 if (dark_outside and lit_inside) else 1)


## A ward room with an interior floor tile one step in from a doorway that opens onto a corridor,
## plus a short hallway trail leading up to it.
func _pick_room() -> Dictionary:
	var rooms: Array = game.level_info.get("rooms", [])
	for i in rooms.size():
		var wing := String(rooms[i].get("wing", ""))
		if wing == "" or wing == "entrance":
			continue
		for d in (rooms[i].get("doors", []) as Array):
			var door: Vector2i = C.world_to_tile(d)
			for n in (mm.DIRS as Array):
				var outside: Vector2i = door + n
				var inside: Vector2i = door - n
				if not _is_corridor(outside):
					continue
				if not _is_room_floor(inside, i):
					continue
				return {"room": i, "kind": String(rooms[i].get("kind", "")), "door": door,
						"outside": outside, "inside": inside, "trail": _trail(outside)}
	return {}


func _is_corridor(t2: Vector2i) -> bool:
	var mw: int = mm.w
	if t2.x < 0 or t2.y < 0 or t2.x >= mw or t2.y >= int(mm.h):
		return false
	var corr: PackedInt32Array = mm.corr_at
	return corr[t2.y * mw + t2.x] >= 0


func _is_room_floor(t2: Vector2i, room: int) -> bool:
	var mw: int = mm.w
	if t2.x < 0 or t2.y < 0 or t2.x >= mw or t2.y >= int(mm.h):
		return false
	var i: int = t2.y * mw + t2.x
	var rooms_at: PackedInt32Array = mm.room_at
	var kinds: PackedByteArray = mm.kind
	return rooms_at[i] == room and kinds[i] == 1   # Minimap.K_FLOOR


## The corridor tiles leading up to `to`: a breadth-first walk out over corridor tiles only, then
## the chain back in from the farthest tile found. Ends one step before `to`.
func _trail(to: Vector2i) -> Array:
	var mw: int = mm.w
	var mh: int = mm.h
	var corr: PackedInt32Array = mm.corr_at
	var from: int = to.y * mw + to.x
	var parent := {from: -1}
	var q: Array[int] = [from]
	var qi := 0
	var far: int = from
	while qi < q.size() and qi < 90:
		var j: int = q[qi]
		qi += 1
		far = j
		for d in (mm.DIRS as Array):
			var nx: int = (j % mw) + int(d.x)
			var ny: int = (j / mw) + int(d.y)
			if nx < 0 or ny < 0 or nx >= mw or ny >= mh:
				continue
			var ni: int = ny * mw + nx
			if parent.has(ni) or corr[ni] < 0:
				continue
			parent[ni] = j
			q.append(ni)
	var chain: Array = []
	var cur: int = far
	while cur != -1 and chain.size() < 14:
		chain.append(Vector2i(cur % mw, cur / mw))
		cur = int(parent[cur])
	# Built from the farthest tile back down the parent chain, so it already reads
	# farthest-away-first: walking it goes up the hallway and ends beside the door.
	return chain


## Is the ground under the player actually lit, and how much is lit near them? If the panel looks
## empty where the arrow is, this says whether that is the fog, the draw, or the centring.
func _diag(tag: String) -> void:
	var mw: int = mm.w
	var t2: Vector2i = C.world_to_tile(me.global_position)
	var i: int = t2.y * mw + t2.x
	var kinds: PackedByteArray = mm.kind
	var near := 0
	for dy in range(-8, 9):
		for dx in range(-8, 9):
			var nx: int = t2.x + dx
			var ny: int = t2.y + dy
			if nx < 0 or ny < 0 or nx >= mw or ny >= int(mm.h):
				continue
			if kinds[ny * mw + nx] != 0 and mm.tile_seen(ny * mw + nx):
				near += 1
	print("[minimapshot] %s: player tile %s kind=%d seen=%s, %d lit tiles within 8" % [
			tag, t2, int(kinds[i]), mm.tile_seen(i), near])


func _lit() -> int:
	var n := 0
	for i in int(mm.room_count):
		if mm.room_seen(i):
			n += 1
	return n


func _stand(tile: Vector2i) -> void:
	me.teleport(game._floor_at(C.tile_to_world(tile.x, tile.y, 0.4)))
	me.bot_move = Vector2.ZERO


func _face(tile: Vector2i) -> void:
	var to := C.tile_to_world(tile.x, tile.y)
	var d := to - me.global_position
	me.bot_yaw = atan2(-d.x, -d.z)
	me.bot_pitch = 0.0


## The whole screen, plus the panel's own corner blown up 3x so it can actually be read.
func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path("%s/%s.png" % [SHOT_DIR, name]))
	var side := int(MinimapPanel.SIDE + MinimapPanel.MARGIN * 2.0)
	var box := Rect2i(maxi(img.get_width() - side, 0), 0, mini(side, img.get_width()), mini(side, img.get_height()))
	var zoom := img.get_region(box)
	zoom.resize(zoom.get_width() * 3, zoom.get_height() * 3, Image.INTERPOLATE_NEAREST)
	zoom.save_png(ProjectSettings.globalize_path("%s/%s_zoom.png" % [SHOT_DIR, name]))
	print("[minimapshot] wrote %s (+ _zoom)" % name)


func _process(delta: float) -> void:
	t += delta


func _seconds(s: float) -> void:
	var end := t + s
	while t < end:
		await get_tree().process_frame
