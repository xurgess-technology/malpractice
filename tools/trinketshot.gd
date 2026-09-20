extends Node
## TRINKETS chunk B: the smoke look. Boots the `trinkets` review setup the way a review window does
## (main.gd reads `--setup=`), then drives each trinket once and photographs what it looks like.
## Windowed; run it minimized (tools/review.bat does that).
##
##   tools\review.bat 2 "SMOKE" -Scene res://tools/trinketshot.tscn --setup=trinkets
##
## Writes tools/trinket_shots/<name>.png:
##   bar          the item bar with four trinkets in it
##   laptop_map   the laptop's plan of the area, with its surgery blips
##   laptop_used  the same laptop a moment later: greyed, cracked, worth scrap
##   phone_down   the desk phone set down and ringing
##   defib        a teammate shocked back onto their feet where they lay
##   hive_before  the Hive as it stands, with the "[Click] Bonk it" prompt up
##   hive_after   the same Hive a moment after the bonk, turned 180 degrees
##   oximeter     the pulse oximeter clipped onto a shoved Hive
##   epipen       the EpiPen jab
##   bar_spent    the item bar afterwards, with the spent ones greyed and cracked

const OUT_DIR := "res://tools/trinket_shots"

var main: Node3D
var game: Game
var me: Player


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	get_tree().create_timer(420.0).timeout.connect(func(): get_tree().quit(2))
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await _run()
	get_tree().quit(0)


func _run() -> void:
	game = main.game
	var t := 0.0
	while t < 240.0:
		await get_tree().create_timer(1.0).timeout
		t += 1.0
		if game.phase == Game.Phase.SHIFT and game.local_player() != null:
			await get_tree().create_timer(6.0).timeout
			break
	me = game.local_player()
	# Take the bot over from where the setup left the player looking, or bot_pitch's 0.0 snaps the
	# view level and the four trinkets on the floor drop out of the bottom of the frame.
	me.bot_yaw = me._yaw
	me.bot_pitch = me._pitch
	me.bot_active = true
	me.bot_invulnerable = true
	await _frames(4)
	await _shot("bar")
	# The laptop: take it off the floor, open it, photograph the map, then the dead laptop in the bar.
	if await _take("laptop"):
		await _click()
		await _seconds(0.6)
		await _shot("laptop_map")
		await _seconds(7.0)
		await _shot("laptop_used")
		_drop()
		await _seconds(1.0)
	# The desk phone: take it and set it down again, ringing. Step away from the Hive first, or it
	# stands on top of the phone and fills the shot.
	if await _take("desk_phone"):
		_away_from_monsters(6.0)
		await _frames(4)
		await _click()
		await _seconds(1.2)
		_look_down()
		await _shot("phone_down")
		await _seconds(0.5)
	# The defibrillator (bulky, two slots): aim at the downed teammate and shock them.
	var mate := _downed_mate()
	if mate != null and await _take("defibrillator"):
		_face(mate, 1.5, 0.4)
		await _frames(8)
		await _click()
		await _seconds(1.0)
		# They are on their feet now, so look at them standing rather than at where they lay.
		_face(mate, 2.2, 1.1)
		await _frames(6)
		await _shot("defib")
		_drop()
		await _seconds(1.0)
	# The reflex hammer on the Hive.
	var hive := _nearest_monster()
	if hive != null:
		me.selected = _slot_of("reflex_hammer")
		_face(hive, 1.3, 1.2)
		await _seconds(0.6)
		await _shot("hive_before")
		await _click()
		await _seconds(0.5)
		await _shot("hive_after")
	# The pulse oximeter: shove the Hive to open the needle's window, then clip it on.
	if hive != null and is_instance_valid(hive) and me.holding("pulse_oximeter"):
		me.selected = _slot_of("pulse_oximeter")
		_face(hive, 1.6, 1.2)
		await _frames(8)
		game.player_shoved(me)
		await _frames(4)
		# The shove knocks it back out of reach, so close in again before clipping it on.
		_face(hive, 1.3, 1.2)
		await _frames(6)
		await _click()
		await _seconds(0.8)
		await _shot("oximeter")
	# The EpiPen last, because ten seconds later it puts you on the floor.
	if await _take("epipen"):
		await _click()
		await _seconds(0.7)
		await _shot("epipen")
		await _shot("bar_spent")
	print("[trinketshot] done")


# ---------------------------------------------------------------------------

func _shot(name: String) -> void:
	for i in 4:
		await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	var path := ProjectSettings.globalize_path("%s/%s.png" % [OUT_DIR, name])
	img.save_png(path)
	print("[trinketshot] wrote ", path)


## Walk up to the nearest stack of `kind` on the floor, take it and select it.
func _take(kind: String) -> bool:
	var it := _nearest(kind)
	if it == null:
		print("[trinketshot] no %s on the floor" % kind)
		return false
	game.pickup_item(me, it)
	await _frames(4)
	if not me.holding(kind):
		print("[trinketshot] could not pick up the %s (hands full?)" % kind)
		return false
	me.selected = _slot_of(kind)
	await _frames(4)
	return true


func _drop() -> void:
	game.drop_selected(me, 0.0)


func _click() -> void:
	me.bot_use += 1
	await _frames(6)


func _slot_of(kind: String) -> int:
	for i in me.slots.size():
		if String(me.slots[i].kind) == kind:
			return i
	return me.selected


func _nearest(kind: String) -> Node:
	var best: Node = null
	var best_d := 1e9
	for it in game.world_items.values():
		if it == null or not is_instance_valid(it) or String(it.kind) != kind:
			continue
		var d: float = it.global_position.distance_to(me.global_position)
		if d < best_d:
			best_d = d
			best = it
	return best


func _nearest_monster() -> Node:
	for m in game.monsters.values():
		if m != null and is_instance_valid(m):
			return m
	return null


func _downed_mate() -> Node:
	for p in game.players.values():
		if p != null and is_instance_valid(p) and p != me and p.alive and p.downed:
			return p
	return null


func _face(target: Node, dist: float, look_h: float) -> void:
	var tp: Vector3 = target.global_position
	var from: Vector3 = me.global_position - tp
	from.y = 0.0
	from = from.normalized() if from.length() > 0.2 else Vector3.BACK
	me.teleport(game._floor_at(tp + from * dist))
	var eye: Vector3 = me.global_position + Vector3.UP * C.EYE_H
	var d: Vector3 = tp + Vector3.UP * look_h - eye
	me.bot_yaw = atan2(-d.x, -d.z)
	me.bot_pitch = clampf(atan2(d.y, Vector2(d.x, d.z).length()), -1.2, 1.2)
	me.bot_move = Vector2.ZERO


func _look_down() -> void:
	me.bot_pitch = -0.7


## Put at least `want` metres between me and the nearest monster, so it stays out of the shot.
func _away_from_monsters(want: float) -> void:
	var m := _nearest_monster()
	if m == null or not is_instance_valid(m):
		return
	var d: Vector3 = me.global_position - m.global_position
	d.y = 0.0
	if d.length() >= want:
		return
	d = d.normalized() if d.length() > 0.2 else Vector3.BACK
	me.teleport(game._floor_at(m.global_position + d * want))


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _seconds(s: float) -> void:
	await get_tree().create_timer(s).timeout
