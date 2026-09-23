extends Node
## Dev mode: the tools behind the pharmacy fax's secret order (DEV_CODE placebo pills, game.gd
## set_dev_tools). One per game, a child of Game named "Dev" (so its RPCs have the same path on every
## machine). Idle unless `game.dev_on()`. Dev mode is for one session and for everyone in it.
##
## The host owns the truth: everything here that changes the world runs on the host; clients ask
## through request() and fire() and see the result through the "dv" block of the game snapshot
## (net_state / apply_net_state) and one-off events (tracers, fallen monsters).
##
## There is no separate dev room any more (removed 2026-09-23, "it's not needed, we can just do
## everything out in the open" -- Zach): everything the panel does happens wherever you already
## are, in the real hospital. This file used to also own a hidden room and its closet door
## (`dev_level.gd`, `dev_door.gd`, now deleted); this is what stayed once the room went, moved out
## the way `spawn_hive` moved onto `game.gd` during the brains removal (docs/backlog/ABILITIES_REMOVED.md).
##
## Contracts other code relies on are in docs/CONTRACTS.md ("Dev mode").

signal state_changed
## The panel's "phone call" button when the game has no dev_phone_call() yet (wave 2 builds it).
signal phone_call_requested
## Dev tools were turned on or off in this session (every machine).
signal dev_tools_changed(on: bool)

const KILL := "kill"
const KNOCK := "knock"
const GUN_RANGE := 80.0
const GUN_COOLDOWN := 0.16
const KNOCK_STUN := 3.0
const MONSTER_KNOCK_SECONDS := 4.0
const AUTO_REVIVE_SECONDS := 4.0
## Where the first-person gun sits on the camera: low on the right, clear of the crosshair.
const GUN_FP_POS := Vector3(0.24, -0.23, -0.46)
## Render layer 18 for the first-person gun (layer 20 is the minigames'). Also read by
## scripts/personnel/mirrors.gd, which keeps the gun's own first-person model out of the mirrors.
const GUN_FP_LAYER := 1 << 17
const ORDERS := ["follow", "stay", "carry", "operate"]
const MONSTER_KINDS := ["hive", "sonographer", "night_nurse"]  # SWEEP 3 HOOK (monsters): the Hive
## NURSE HOOK: the panel's pace choices for the Night Nurse, m/s (her hunting speed first).
const NURSE_PACES := [3.4, 1.6, 0.8]
const NURSE_PACE_NAMES := ["Hunt (3.4 m/s)", "Stalk (1.6 m/s)", "Creep (0.8 m/s)"]
## Half extents of the "walk a loop" rectangle around the player who asked, metres (along, across).
const NURSE_LOOP := Vector2(3.0, 1.75)
const BOT_NAMES :=["Dr. Botsworth", "Nurse Unit", "Intern 404", "Dr. Clank", "Orderly-9", "Dr. Servo", "Scrub Bot", "Dr. Byte"]

const BotBrain := preload("res://scripts/dev/dev_bot.gd")
const GunFx := preload("res://scripts/dev/dev_gun.gd")
const PlayerScript := preload("res://scripts/player.gd")
const WorldItemScript := preload("res://scripts/world_item.gd")
const LootTable := preload("res://scripts/economy/loot_table.gd")
const MonsterScript3 := preload("res://scripts/monster.gd")  # SWEEP 3 HOOK (monsters): display names
const Plan := preload("res://scripts/level/pockets/pocket_plan.gd")   # POCKETS HOOK (dev force)
const Stub := preload("res://scripts/level/pockets/stub.gd")          # POCKETS HOOK (dev force): the seam teleport

var game: Node = null

# ---- replicated (host authoritative) ----
var time_scale := 1.0
var freeze_vitals := false
var auto_revive := false
## Dev tools toggles: no monsters spawn (and the live ones go); nobody loses the run to everyone downed.
var monsters_off := false
var no_game_over := false
var god := {}      # peer id -> true
var noclip := {}   # peer id -> true
var gun := {}      # peer id -> true
## Bots and dummies: id (negative) -> {name, kind: "bot"|"dummy", order, item, to, owner, status, done}
var bots := {}
## NURSE HOOK (night nurse model): watching her walk. Every Night Nurse ignores being watched; how she
## walks ("" hunts as normal, "follow" the player who asked, "loop" round `nurse_loop`); her pace.
var nurse_ignore_watch := false
var nurse_walk := ""
var nurse_pace := 0
var nurse_who := 0       # host: who asked for "follow"
var nurse_loop: Array = []   # host: the loop's corners on the navigation mesh

# ---- host ----
var brains := {}   # id -> BotBrain
var _next_bot := 1
var _fire_at := {}  # peer id -> world_time of the last shot
var _dead_for := {}

# ---- local ----
var _recoil := {}   # peer id -> 0..1


func setup(g: Node) -> void:
	game = g


func active() -> bool:
	return game != null and game.dev_on() and game.phase != game.Phase.MENU


func is_host() -> bool:
	return game != null and game.is_host()


## Test tools and shots: a big, open, obstacle-free, un-fogged spot to stage things in. Not the
## parking lot itself -- it is real, playable ground, but shallow (its far quarter is the fog
## belt, scripts/level/fog_ring.gd, which also bends a bot's facing once it's deep enough in, so a
## test standing there can get silently turned round mid-check) and too small for what these tools
## expect (many stand things tens of metres apart). Past its edge instead, where the old dev room
## used to stand: a bare patch of floor and nothing else -- no walls, no pen, no dispensers, no
## door, no signage, nothing a player can walk to in a real session. Built the first time a test
## tool asks for it; torn down with the rest of dev mode's state.
const OPEN_FLOOR_SIZE := 48.0
const OPEN_FLOOR_GAP := 30.0   # how far south of the lot's far edge the floor starts
## The walled part of the floor matches the old dev room's own footprint (dev_level.gd W/D) --
## these are the numbers every `o + Vector3(x, 0, z)` in the test tools was written against, and a
## few of them (a shove's knockback, mid-swing) need a wall nearby to land the same way it used to.
const INNER_W := 24.0
const INNER_D := 18.0
const INNER_MARGIN := 6.0   # inset from the big floor's edge, so the walled part isn't flush with it
var _open_floor: Node3D = null
var _open_floor_origin := Vector3.ZERO


func open_area() -> Vector3:
	if game == null or game.level == null or not is_instance_valid(game.level):
		return Vector3.ZERO
	if _open_floor == null or not is_instance_valid(_open_floor) or _open_floor.get_parent() != game.level:
		_build_open_floor()
	return _open_floor_origin


func _build_open_floor() -> void:
	var lot: Rect2 = game.level_info.get("neutral_rect", Rect2())
	var at := Vector3(-160.0, 0.0, -160.0) if lot.size == Vector2.ZERO else Vector3(lot.position.x, 0.0, lot.end.y + OPEN_FLOOR_GAP)
	at = Vector3(snappedf(at.x, C.TILE), 0.0, snappedf(at.z, C.TILE))
	var body := StaticBody3D.new()
	body.name = "DevTestFloor"
	body.collision_layer = C.L_WORLD
	body.collision_mask = 0
	var half := Vector3(OPEN_FLOOR_SIZE * 0.5, 0.2, OPEN_FLOOR_SIZE * 0.5)
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = half * 2.0
	cs.shape = box
	cs.position = Vector3(half.x, -half.y, half.z)
	body.add_child(cs)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = box.size
	mi.mesh = bm
	mi.position = cs.position
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.32, 0.34, 0.35)
	mi.material_override = mat
	body.add_child(mi)
	var nav := NavigationRegion3D.new()
	var nm := NavigationMesh.new()
	nm.agent_radius = 0.5
	nm.agent_height = 1.75
	nm.agent_max_climb = 0.25
	nm.agent_max_slope = 45.0
	nm.cell_size = 0.25
	nm.cell_height = 0.25
	nm.set_vertices(PackedVector3Array([
		Vector3(0.0, 0.0, 0.0), Vector3(OPEN_FLOOR_SIZE, 0.0, 0.0),
		Vector3(OPEN_FLOOR_SIZE, 0.0, OPEN_FLOOR_SIZE), Vector3(0.0, 0.0, OPEN_FLOOR_SIZE)]))
	nm.add_polygon(PackedInt32Array([0, 1, 2, 3]))
	nav.navigation_mesh = nm
	body.add_child(nav)
	# The walled inner box, inset within the bigger bare floor.
	const WALL_H := 3.0
	const WALL_T := 0.4
	var ix := INNER_MARGIN
	var iz := INNER_MARGIN
	for w in [
			[Vector3(INNER_W, WALL_H, WALL_T), Vector3(ix + INNER_W * 0.5, WALL_H * 0.5, iz - WALL_T * 0.5)],
			[Vector3(INNER_W, WALL_H, WALL_T), Vector3(ix + INNER_W * 0.5, WALL_H * 0.5, iz + INNER_D + WALL_T * 0.5)],
			[Vector3(WALL_T, WALL_H, INNER_D), Vector3(ix - WALL_T * 0.5, WALL_H * 0.5, iz + INNER_D * 0.5)],
			[Vector3(WALL_T, WALL_H, INNER_D), Vector3(ix + INNER_W + WALL_T * 0.5, WALL_H * 0.5, iz + INNER_D * 0.5)]]:
		var wcs := CollisionShape3D.new()
		var wbox := BoxShape3D.new()
		wbox.size = w[0]
		wcs.shape = wbox
		wcs.position = w[1]
		body.add_child(wcs)
	body.position = at
	game.level.add_child(body)
	_open_floor = body
	_open_floor_origin = at + Vector3(ix, 0.0, iz)


# =========================================================================
# lifecycle (called from game.gd hooks)
# =========================================================================

# ---- POCKETS HOOK: force the level's own generation to include a real pocket, and jump to its seam.
# (Replaces the old "Pocket spaces" mechanism -- PocketSpaces.build_kind(), a bare standalone space
# with no hospital entrances, built for the now-deleted dev room. That one is gone: it hadn't kept up
# with the five real kinds (it only knew three), and side by side with a real forced pocket it was
# just confusing -- two "Pocket spaces" controls that don't do the same thing. build_kind() itself is
# left in pocket_spaces.gd, documented in CONTRACTS.md, in case an isolated art-review space is ever
# wanted again; nothing calls it now.)

## Host: PocketPlan.force_kind for the *next* wing build -- rebuilt now if the level already has
## wings (like "Regenerate wings now"), else it takes effect at the next one (a new run, a new shift).
## "" rolls at normal odds, "random" forces one of the five kinds (still guaranteed, just not chosen
## by the caller), anything else must be a real kind.
func _force_pocket(kind: String) -> void:
	if kind == "random":
		kind = Plan.KINDS[randi() % Plan.KINDS.size()]
	elif kind != "" and not Plan.KINDS.has(kind):
		kind = ""
	Plan.force_kind = kind
	if game.wing_loader != null and game.wing_loader.has_wings():
		game.wing_loader.regenerate(int(game.wing_loader.generation) + 1)
		game.say(("Forcing a %s pocket -- rebuilding the wings now." % kind) if kind != "" else
			"Pocket forcing off -- wings rebuilding at normal odds.", 3.0)
	else:
		game.say(("The next hospital will force a %s pocket." % kind) if kind != "" else
			"Pocket forcing off.", 3.0)


## The local player (who owns their own position) steps into the pocket or back to the start.
func pocket_go(into: bool) -> void:
	var me: Node = game.local_player()
	if me == null:
		return
	if into and game.pockets.active():
		me.teleport(game.pockets.pocket.spawn)
	elif not into:
		var spots: Array = game.spawn_points()
		me.teleport(spots[0] if not spots.is_empty() else Vector3.ZERO)


## Local: the player steps up to seam `i` of the current pocket, one tile shy of the seam itself on
## the hospital side -- close enough to cross with a step or two, not already past it. `i` indexes
## `game.pockets.seams` (see pocket_spaces.gd _make_seam); every machine computes its own copy of the
## same seam geometry from the same forced kind, so this needs no request to the host.
func go_seam(i: int) -> bool:
	if game == null or game.get("pockets") == null:
		return false
	var seams: Array = game.pockets.seams
	if i < 0 or i >= seams.size():
		return false
	var me: Node = game.local_player()
	if me == null:
		return false
	var s: Dictionary = seams[i]
	var xh: Transform3D = s.xh
	var mid: float = Stub.seam_s(int(s.w))
	var back: float = float(s.d) - float(Stub.CORRIDOR) * 0.5
	var at: Vector3 = Stub.local_point(xh, mid - 1.0, back)
	me.teleport(game._floor_at(at))
	return true


## Dev mode off or the session over: undo anything global.
func reset_state() -> void:
	release_bot()   # GRAFT HOOK: back into your own body before the bots go
	for id in bots.keys():
		_free_bot(id)
	bots.clear()
	brains.clear()
	god.clear()
	noclip.clear()
	gun.clear()
	_dead_for.clear()
	_fire_at.clear()
	time_scale = 1.0
	Engine.time_scale = 1.0
	freeze_vitals = false
	auto_revive = false
	monsters_off = false
	no_game_over = false
	nurse_ignore_watch = false
	nurse_walk = ""
	nurse_pace = 0
	Plan.force_kind = ""   # POCKETS HOOK (dev force): dev mode off leaves the odds alone
	nurse_who = 0
	nurse_loop = []
	state_changed.emit()


func has_gun(peer_id: int) -> bool:
	return gun.has(peer_id)


func is_god(p: Node) -> bool:
	return p != null and god.has(p.peer_id)


# =========================================================================
# frame
# =========================================================================

func _physics_process(delta: float) -> void:
	if not active():
		return
	if is_host():
		_host_tick(delta)


func _host_tick(delta: float) -> void:
	# Vitals: with freeze on every patient on a table waits (loop: every case, not just one).
	if game.phase == game.Phase.SHIFT and freeze_vitals:
		var drain: float = C.VITALS_DRAIN_SECONDS * pow(0.85, game.shift - 1)
		for c in game.cases:
			if String(c.get("state", "")) == "on_table" and float(c.vitals) > 0.0:
				c.vitals = minf(100.0, float(c.vitals) + delta * 100.0 / drain)
	for id in brains.keys():
		if id == possessing:
			continue   # GRAFT HOOK: a human has the wheel; the brain keeps its order for afterwards
		var b = brains[id]
		b.tick(delta)
		if bots.has(id):
			bots[id]["status"] = b.status
			bots[id]["done"] = b.completed
			bots[id]["order"] = b.order
	if auto_revive:
		for p in game.players.values():
			if p.alive or p.get("is_bot"):
				_dead_for.erase(p.peer_id)
				continue
			_dead_for[p.peer_id] = float(_dead_for.get(p.peer_id, 0.0)) + delta
			if _dead_for[p.peer_id] >= AUTO_REVIVE_SECONDS:
				_dead_for.erase(p.peer_id)
				_revive(p)


func _process(_delta: float) -> void:
	if game == null or game.phase == game.Phase.MENU:
		return
	for p in game.players.values():
		_update_gun_visual(p, _delta)
	if not game.dev_on():
		return
	if not is_equal_approx(Engine.time_scale, time_scale):
		Engine.time_scale = time_scale


# =========================================================================
# the dev gun
# =========================================================================

func _unhandled_input(event: InputEvent) -> void:
	if not active() or not (event is InputEventMouseButton) or not event.pressed:
		return
	if event.button_index != MOUSE_BUTTON_LEFT and event.button_index != MOUSE_BUTTON_RIGHT:
		return
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED or game.paused:
		return
	var me = game.local_player()
	if me == null or not me.alive or me.downed or me.operating or not has_gun(me.peer_id):
		return
	fire_local(KILL if event.button_index == MOUSE_BUTTON_LEFT else KNOCK)
	get_viewport().set_input_as_handled()


## The local player pulls the trigger along their own view.
func fire_local(mode: String) -> void:
	var me = game.local_player()
	if me == null:
		return
	var xf: Transform3D = me.camera.global_transform
	fire(me, xf.origin, -xf.basis.z, mode)


## Fire `shooter`'s dev gun from `from` along `dir`. On the host this applies the hit; on a
## client it draws the shot straight away and asks the host, which checks it and applies it.
func fire(shooter: Node, from: Vector3, dir: Vector3, mode: String) -> Dictionary:
	if shooter == null or not active():
		return {}
	dir = dir.normalized()
	if is_host():
		return _host_fire(shooter, from, dir, mode)
	var hit := _cast(shooter, from, dir)
	_shot_fx(shooter.peer_id, from, hit.get("position", from + dir * GUN_RANGE), mode, not hit.is_empty())
	_rpc_fire.rpc_id(Net.HOST_ID, from, dir, mode)
	return hit


@rpc("any_peer", "reliable", "call_remote")
func _rpc_fire(from: Vector3, dir: Vector3, mode: String) -> void:
	if not is_host():
		return
	var p = game.players.get(multiplayer.get_remote_sender_id())
	if p != null:
		_host_fire(p, from, dir.normalized(), mode)


func _host_fire(shooter: Node, from: Vector3, dir: Vector3, mode: String) -> Dictionary:
	if not shooter.alive or shooter.downed or not has_gun(shooter.peer_id) or (mode != KILL and mode != KNOCK):
		return {}
	var now: float = game.world_time
	if now - float(_fire_at.get(shooter.peer_id, -99.0)) < GUN_COOLDOWN * 0.8:
		return {}
	# The shot has to start at the shooter's eyes (a client reports its own position; allow lag).
	if from.distance_to(shooter.head.global_position) > 2.5:
		return {}
	_fire_at[shooter.peer_id] = now
	var hit := _cast(shooter, from, dir)
	var to: Vector3 = hit.get("position", from + dir * GUN_RANGE)
	var target = hit.get("target")
	if target != null:
		_apply_hit(shooter, target, mode, dir)
	game.emit_noise(from, 0.9, "gunshot")
	_shot_fx(shooter.peer_id, from, to, mode, target != null)
	if Net.active:
		_rpc_shot.rpc(shooter.peer_id, from, to, mode, target != null)
	return hit


@rpc("authority", "reliable", "call_remote")
func _rpc_shot(shooter_id: int, from: Vector3, to: Vector3, mode: String, hit: bool) -> void:
	if shooter_id == Net.my_id():
		return   # already drawn when we pulled the trigger
	_shot_fx(shooter_id, from, to, mode, hit)


## {position, target} of the first thing along the shot, or {} for a miss into nothing.
func _cast(shooter: Node, from: Vector3, dir: Vector3) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * GUN_RANGE)
	q.collision_mask = C.L_WORLD | C.L_PLAYER | C.L_MONSTER
	q.exclude = [shooter.get_rid()]
	var space: PhysicsDirectSpaceState3D = shooter.get_world_3d().direct_space_state
	var hit: Dictionary = space.intersect_ray(q)
	# downed hook: a downed player has no body collision; shots find them through their aim area.
	var aq := PhysicsRayQueryParameters3D.create(from, hit.get("position", from + dir * GUN_RANGE))
	aq.collision_mask = C.L_INTERACT
	aq.collide_with_areas = true
	aq.collide_with_bodies = false
	var ahit: Dictionary = space.intersect_ray(aq)
	if not ahit.is_empty() and ahit.collider is Area3D and ahit.collider.get_parent() is CharacterBody3D \
			and "peer_id" in ahit.collider.get_parent() and ahit.collider.get_parent() != shooter:
		return {"position": ahit.position, "target": ahit.collider.get_parent()}
	if hit.is_empty():
		return {}
	var node: Node = hit.collider
	var target: Node = null
	while node != null:
		if node.is_in_group("monster") or (node is CharacterBody3D and "peer_id" in node):
			target = node
			break
		node = node.get_parent()
	return {"position": hit.position, "target": target}


func _apply_hit(shooter: Node, target: Node, mode: String, dir: Vector3) -> void:
	var knock := Vector3(dir.x, 0.0, dir.z).normalized() * 7.0 + Vector3.UP * 2.0
	if target.is_in_group("monster"):
		if mode == KILL:
			game.kill_monster(target)
		else:
			game.knock_down_monster(target, dir, MONSTER_KNOCK_SECONDS)
		return
	if not target.alive:
		return
	# downed hook: primary kills outright (dev only), secondary downs for real.
	if mode == KILL:
		if not target.downed:
			target.apply_knock(knock)
		game.kill_player(target, "dev_gun:%s" % shooter.player_name)
	elif not target.downed:
		game.knock_down_player(target, "dev_gun:%s" % shooter.player_name, knock)


func _shot_fx(shooter_id: int, from: Vector3, to: Vector3, mode: String, hit: bool) -> void:
	var p = game.players.get(shooter_id)
	var start := from
	if p != null:
		_recoil[shooter_id] = 1.0
		var fp: Node3D = p.camera.get_node_or_null("DevGunFP") if p.is_local else p.body_visual.get_node_or_null("DevGunTP")
		if fp != null and fp.visible:
			var muzzle = fp.get_node_or_null("DevGun/Muzzle")
			if muzzle != null:
				start = muzzle.global_position
	GunFx.tracer(game.get_node("Entities"), start, to, mode, hit)
	Audio.play("dev_zap" if mode == KILL else "dev_thump", from, -2.0, 0.08)
	if hit:
		Audio.play("punch" if mode == KILL else "thud", to, -4.0, 0.1)


## First-person gun on your camera (hands hidden), third-person gun on everyone else's body.
func _update_gun_visual(p: Node, delta: float) -> void:
	var want: bool = game.dev_on() and gun.has(p.peer_id) and p.alive and not p.downed
	var fp: Node3D = p.camera.get_node_or_null("DevGunFP")
	var tp: Node3D = p.body_visual.get_node_or_null("DevGunTP")
	if not want:
		if fp != null:
			for n in [fp, tp]:
				if n != null:
					n.name = "DevGunGone"
					n.queue_free()
			if p.is_local:
				p.hands.visible = not p.downed
		return
	if fp == null:
		fp = Node3D.new()
		fp.name = "DevGunFP"
		fp.position = GUN_FP_POS
		fp.scale = Vector3.ONE * 0.75
		var g := GunFx.make_gun()
		g.rotation.y = 0.04
		fp.add_child(g)
		p.camera.add_child(fp)
		# The flashlight sits a hand's width from the gun and would bleach it white: keep the
		# first-person gun on its own render layer and out of the flashlight's cull mask.
		for mi in fp.find_children("*", "MeshInstance3D", true, false):
			(mi as MeshInstance3D).layers = GUN_FP_LAYER
		p.flashlight.light_cull_mask = p.flashlight.light_cull_mask & ~GUN_FP_LAYER
		tp = Node3D.new()
		tp.name = "DevGunTP"
		tp.position = Vector3(0.28, 1.2, -0.38)
		tp.add_child(GunFx.make_gun())
		p.body_visual.add_child(tp)
	fp.visible = p.is_local
	if tp != null:
		tp.visible = not p.is_local
	if p.is_local:
		p.hands.visible = false
	var r: float = maxf(0.0, float(_recoil.get(p.peer_id, 0.0)) - delta * 7.0)
	_recoil[p.peer_id] = r
	fp.position = GUN_FP_POS + Vector3(0.0, r * 0.02, r * 0.06)
	fp.rotation.x = r * 0.35


# =========================================================================
# requests: the panel (and tests) change the world through here
# =========================================================================

## Ask for a change. The host applies it at once; a client sends it to the host.
func request(action: String, args: Dictionary = {}) -> void:
	if game == null or not game.dev_on():
		return
	if is_host():
		_apply_request(Net.my_id(), action, args)
	elif Net.active:
		_rpc_request.rpc_id(Net.HOST_ID, action, args)


## ARCADE: the host telling everyone which steps play their arcade rebuild.
@rpc("authority", "reliable", "call_remote")
func _rpc_arcade(key: String, on: bool) -> void:
	if Procedures.ARCADE_ENABLED.has(key):
		Procedures.ARCADE_ENABLED[key] = on


@rpc("any_peer", "reliable", "call_remote")
func _rpc_request(action: String, args: Dictionary) -> void:
	if is_host() and game.dev_on():
		_apply_request(multiplayer.get_remote_sender_id(), action, args)


## DOORS HOOK: the panel's door tools.
const DOOR_ACTIONS := ["doors_all", "regen_wings"]


## Every machine: dev mode went on or off in this session (game.set_dev_tools, or the snapshot).
func on_dev_tools(on: bool) -> void:
	dev_tools_changed.emit(on)
	state_changed.emit()


func _door_request(action: String, a: Dictionary) -> void:
	match action:
		"doors_all":
			game.doors.set_all(bool(a.get("open", true)))
			game.say("Every door %s." % ("open" if bool(a.get("open", true)) else "shut"), 2.0)
		"regen_wings":
			if not game.wing_loader.has_wings():
				game.say("No wings in this level.", 3.0)
				return
			game.wing_loader.regenerate(int(game.wing_loader.generation) + 1)
			game.say("Regenerating the wings behind the gates...", 3.0)


func _apply_request(sender: int, action: String, a: Dictionary) -> void:
	var who = game.players.get(sender)
	if DOOR_ACTIONS.has(action):
		_door_request(action, a)   # DOORS HOOK
		state_changed.emit()
		return
	match action:
		"god":
			_set_flag(god, sender, bool(a.get("on", not god.has(sender))))
		"noclip":
			_set_flag(noclip, sender, bool(a.get("on", not noclip.has(sender))))
		"gun":
			_set_flag(gun, sender, bool(a.get("on", not gun.has(sender))))
		"time_scale":
			time_scale = clampf(float(a.get("v", 1.0)), 0.05, 4.0)
		"arcade":
			# ARCADE (docs/ARCADE_SURGERY.md): which steps play their arcade rebuild. Every machine
			# has to agree or they would build different minigames, so the host broadcasts it.
			var akey := String(a.get("key", ""))
			if Procedures.ARCADE_ENABLED.has(akey):
				var aon := bool(a.get("on", not bool(Procedures.ARCADE_ENABLED[akey])))
				Procedures.ARCADE_ENABLED[akey] = aon
				if Net.active:
					_rpc_arcade.rpc(akey, aon)
		"freeze":
			freeze_vitals = bool(a.get("on", not freeze_vitals))
		"auto_revive":
			auto_revive = bool(a.get("on", not auto_revive))
		"dev_off":
			game.set_dev_tools(false, who)
			return
		"monsters_off":
			monsters_off = bool(a.get("on", not monsters_off))
			if monsters_off:
				_clear_monsters_quietly()
			game.say("Monsters %s." % ("off" if monsters_off else "back on from the next shift"), 2.5)
		"no_game_over":
			no_game_over = bool(a.get("on", not no_game_over))
		"clock_in":
			if game.phase == game.Phase.LOBBY:
				game.clock_in()
			else:
				game.say("Clock in from the lobby (before a shift).", 2.5)
		"clock_out":
			if game.phase == game.Phase.SHIFT:
				game.loop.clock_out(true)
			else:
				game.say("Not on a shift.", 2.0)
		"skip_to_table":
			game.loop.dev_skip_to_table()
		"abilities":
			if game.abilities != null:
				for id in game.abilities.ABILITY_ID_TO_PATH.keys():
					game.abilities.set_level(sender, String(id), int(game.abilities.MAX_LEVEL))
				game.tell(who, "Every ability, max level. Alt+1..4 uses them.", 3.0)
		"difficulty":
			game.shift = clampi(int(a.get("shift", 1)), 1, 99)
			game.say("Difficulty: shift %d." % game.shift, 2.5)
		"spawn_item":
			_spawn_item(who, String(a.get("kind", "gauze")), int(a.get("count", 1)))
		"spawn_monster":
			spawn_monster(String(a.get("kind", "sonographer")), String(a.get("where", "front")), who)
		"kill_monsters":
			for m in game.monsters.values().duplicate():
				game.kill_monster(m)
		"patient":
			set_patient(String(a.get("patient", "bob")), String(a.get("ailment", "gunshot")), bool(a.get("dead", false)))
		"clear_patient":
			# loop: every patient, on the tables and on the way.
			for c in game.cases.duplicate():
				game.remove_case(int(c.id))
		"vitals":
			for c in game.cases:
				if String(c.get("state", "")) == "on_table":
					c.vitals = clampf(float(a.get("v", 100.0)), 1.0, 100.0)
		"nurse_ignore_watch":
			nurse_ignore_watch = bool(a.get("on", not nurse_ignore_watch))
		"nurse_walk":
			set_nurse_walk(String(a.get("mode", "")), who)
		"nurse_pace":
			nurse_pace = clampi(int(a.get("i", 0)), 0, NURSE_PACES.size() - 1)
		"force_pocket":
			_force_pocket(String(a.get("kind", "")))   # POCKETS HOOK (dev force)
		"strap_monster":
			# GRAFTING part one: a Hive strapped to a patient table.
			game.dissection.dev_strap(String(a.get("kind", "hive")), float(a.get("sedation", 1.0)), int(a.get("table", -1)))
		"extra_patient":
			game.dev_extra_patient()
		"skip_grace":
			game.dev_skip_grace()
		"stock_shelf":
			stock_shelf()
		"clear_shelf":
			game.clear_storage()   # 2026-09-18: the OR's storage shelves (the supply shelf is gone)
		"phone":
			phone_call()
		"spawn_bot":
			spawn_bot(String(a.get("kind", "bot")), who)
		"remove_bot":
			remove_bot(int(a.get("id", 0)))
		"remove_bots":
			for id in bots.keys():
				remove_bot(id)
		"order":
			order_bot(int(a.get("id", 0)), String(a.get("order", "stay")), String(a.get("item", "")), String(a.get("to", "")), sender)
		"money":
			# inventory: the panel's money buttons (amount may be negative) and "reset"
			if bool(a.get("reset", false)):
				game.reset_money()
			else:
				game.add_money(int(a.get("amount", 1000)), "dev:panel")
		"revive_all":
			for p in game.players.values():
				if not p.alive or p.downed:
					_revive(p)
		"down_me":
			# downed hook: the panel's "Down me" button (or {id} for a bot or dummy).
			var target = game.players.get(int(a.get("id", sender)))
			if target != null:
				game.knock_down_player(target, "dev:panel")
		_:
			# the abilities node's own dev requests: "ab_levels", "ab_reset".
			if action.begins_with("ab_") and game.abilities != null and game.abilities.has_method("dev_request"):
				game.abilities.dev_request(sender, action, a)
	state_changed.emit()


## Host: every monster gone, no death effects (the panel's "No monsters").
func _clear_monsters_quietly() -> void:
	for id in game.monsters.keys():
		var m = game.monsters[id]
		game.monsters.erase(id)
		if game.combat != null:
			game.combat.on_monster_removed(m)
		if m != null and is_instance_valid(m):
			m.queue_free()


func _set_flag(d: Dictionary, id: int, on: bool) -> void:
	if on:
		d[id] = true
	else:
		d.erase(id)
	var p = game.players.get(id)
	if p != null:
		p.noclip = noclip.has(id)


# =========================================================================
# host actions
# =========================================================================

func dispense(p: Node, kind: String, count: int, at: Vector3) -> void:
	if not is_host() or p == null:
		return
	if kind == "dev_gun":
		_set_flag(gun, p.peer_id, not gun.has(p.peer_id))
		game._sound("click", at)
		game.tell(p, "Dev gun: left click kills, right click knocks down." if gun.has(p.peer_id) else "Dev gun racked.", 3.0)
		state_changed.emit()
		return
	if not p.can_take(kind):
		game.tell(p, "That needs two free hands." if Items.is_bulky(kind) else "Your hands are full.")
		return
	var it = game._spawn_item(kind, maxi(1, count), Transform3D(Basis(), at), WorldItemScript.State.LOOSE)
	it.value = loot_value(kind, maxi(1, count))
	game.pickup_item(p, it)


## A dispensed or spawned stack of loot is worth what it would be one wing deep (0 otherwise).
static func loot_value(kind: String, count: int) -> int:
	if not Items.is_loot(kind):
		return 0
	var v := 0
	for i in count:
		v += LootTable.roll_value(kind, 1, 0.5)
	return v


## A bot hands the stack in `hand` to another player, straight into a free (or matching) hand.
func hand_over(from: Node, to: Node, hand: int) -> bool:
	if not is_host():
		return false
	hand = from.head_of(hand)  # inventory: a bulky stack hands over from either of its slots
	var s: Dictionary = from.slots[hand]
	if s.kind == "":
		return false
	if to.slot_for(s.kind) < 0:
		from.selected = hand
		game.drop_selected(from)
		game.tell(to, "%s put %s at your feet." % [from.player_name, Items.display_name(s.kind)], 2.5)
		return true
	var got: int = to.take_into(String(s.kind), int(s.count), int(s.get("v", 0)))
	if got >= 0 and s.has("bt"):
		to.slots[got]["bt"] = s.bt   # GRAFTING: the spoil clock goes with the eye
	from.clear_slot(hand)
	game._sound("pickup", to.global_position)
	game.tell(to, "%s handed you %s." % [from.player_name, Items.display_name(s.kind)], 2.5)
	return true


func _spawn_item(who: Node, kind: String, count: int) -> void:
	if not Items.exists(kind):
		return
	var at := _in_front_of(who, 1.4) + Vector3.UP * 1.2
	var it = game._spawn_item(kind, clampi(count, 1, 20), Transform3D(Basis(), at), WorldItemScript.State.LOOSE)
	it.value = loot_value(kind, clampi(count, 1, 20))
	it.toss(Transform3D(Basis(), at), Vector3.UP * 1.0)


## Host: a monster in front of `who` (there is no pen any more; every dev spawn happens out in
## the open). Marked "dev_spawned" so a new shift's roster doesn't sweep it away
## (see game._clear_monsters).
func spawn_monster(kind: String, _where: String, who: Node = null) -> Node:
	if not is_host() or not MONSTER_KINDS.has(kind):
		return null
	var pos: Vector3 = _in_front_of(who, 4.0)
	var m = game._add_monster(kind, pos)
	m.set_meta("dev_spawned", true)
	game.say("A %s crawls out." % MonsterScript3.display_name(kind), 2.0)  # SWEEP 3 HOOK (monsters)
	return m


## NURSE HOOK: what every Night Nurse's brain reads (Monster.dev_nurse()).
func nurse_settings() -> Dictionary:
	return {"ignore_watch": nurse_ignore_watch, "walk": nurse_walk, "who": nurse_who, "loop": nurse_loop,
		"speed": float(NURSE_PACES[clampi(nurse_pace, 0, NURSE_PACES.size() - 1)])}


## Host: "" hunts as normal, "follow" follows `who`, "loop" walks a rectangle round where `who` stands
## (corners snapped to the navigation mesh, long side along their facing).
func set_nurse_walk(mode: String, who: Node) -> void:
	if not is_host():
		return
	nurse_walk = mode if mode in ["follow", "loop"] else ""
	nurse_who = who.peer_id if who != null else 0
	nurse_loop = []
	if nurse_walk != "loop":
		return
	var centre: Vector3 = who.global_position if who != null else game.spawn_points()[0]
	var fwd: Vector3 = -who.global_transform.basis.z if who != null else Vector3.FORWARD
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length() > 0.01 else Vector3.FORWARD
	var side := fwd.cross(Vector3.UP)
	var world: World3D = who.get_world_3d() if who != null else (game as Node3D).get_world_3d()
	var map: RID = world.navigation_map
	var has_nav := NavigationServer3D.map_get_iteration_id(map) > 0
	for c in [Vector2(1, 1), Vector2(1, -1), Vector2(-1, -1), Vector2(-1, 1)]:
		var p: Vector3 = centre + fwd * c.x * NURSE_LOOP.x + side * c.y * NURSE_LOOP.y
		nurse_loop.append(NavigationServer3D.map_get_closest_point(map, p) if has_nav else p)


## `dead`: they flatline at once and stay on the table as a body (for the furnace).
func set_patient(patient_id: String, ailment_id: String, dead := false) -> void:
	if not is_host() or Procedures.patient(patient_id).is_empty() or Procedures.ailment(ailment_id).is_empty() \
			or Procedures.is_player_only(ailment_id):
		return
	# loop: the first free patient table; with both taken, the first table's patient makes room.
	var table: int = game.free_patient_table()
	if table < 0:
		table = int(game.patient_tables[0].index) if not game.patient_tables.is_empty() else 0
		var there: Dictionary = game.case_on_table(table)
		if not there.is_empty():
			game.remove_case(int(there.id))
	if game.phase == game.Phase.LOBBY:
		game.clock_in()   # a patient before clocking in: clock in first
	var id: int = game.add_case({"patient_id": patient_id, "ailment_id": ailment_id, "table": table, "state": "on_table"})
	if dead:
		game.finish_case(id, false)
		return
	game.say("%s is on the table: %s." % [Procedures.patient(patient_id).name, Procedures.ailment(ailment_id).name], 3.0)


## 2026-09-18: one of every surgical supply (and suture kits) onto the OR's storage shelves, topped
## up to what the shelf used to hold. Take them off to use them: a step's tool has to be in hand.
func stock_shelf() -> void:
	for kind in Items.SURGICAL + ["suture_kit"]:  # downed hook: suture kits too
		var want: int = 6 if Items.is_consumable(kind) else 1
		var have: int = int(game.shelf_count(kind))
		if have < want:
			game.stock_storage(kind, want - have)


func phone_call() -> void:
	if game.has_method("dev_phone_call"):
		game.dev_phone_call()
		return
	phone_call_requested.emit()
	game.say("*ring ring* (the phone call arrives with the shift loop)", 3.0)


func spawn_bot(kind: String, who: Node = null, force_name: String = "", at = null) -> int:
	if not is_host():
		return 0
	kind = "dummy" if kind == "dummy" else "bot"
	var id := -_next_bot
	_next_bot += 1
	var n_bots := 0
	var n_dummies := 0
	for b in bots.values():
		if b.kind == "dummy":
			n_dummies += 1
		else:
			n_bots += 1
	var bot_name: String = "Dummy %d" % (n_dummies + 1) if kind == "dummy" else BOT_NAMES[n_bots % BOT_NAMES.size()]
	if force_name != "":
		bot_name = force_name   # GRAFT HOOK: "Control Dr. Botsworth" always makes Dr. Botsworth
	var owner_id: int = who.peer_id if who != null else Net.my_id()
	bots[id] = {"name": bot_name, "kind": kind, "order": "stay" if kind == "dummy" else "follow",
		"item": "gauze", "to": "shelf", "owner": owner_id, "status": "", "done": 0}
	var p := _make_bot_node(id, bot_name, kind)
	var pos: Vector3 = _in_front_of(who, 3.0 if kind == "dummy" else 2.0) if who != null else game.spawn_points()[0]
	if kind == "dummy":
		p.bot_yaw = PI   # face the spawn so the target rings show
	if at != null:
		pos = at
	p.teleport(pos)
	if kind == "bot":
		var brain = BotBrain.new(self, p)
		brain.set_order("follow", "gauze", "shelf", owner_id)
		brains[id] = brain
	state_changed.emit()
	return id


# =========================================================================
# GRAFT HOOK: Dr. Botsworth, a bot you drive yourself (dev panel, "Control Dr. Botsworth")
# =========================================================================

## The bot this machine's human is driving, 0 for none. Local only, like the free camera: nothing
## here is replicated, so everyone else keeps seeing an ordinary bot with an ordinary body, and
## your own surgeon stays exactly where you left it, strapped down or not.
var possessing := 0
const BOTSWORTH := "Dr. Botsworth"


func possessed_player() -> Node:
	return game.players.get(possessing) if possessing != 0 else null


## The panel's toggle: into Dr. Botsworth, or back into your own body. Host only -- bots live on the
## host, so only the host can put a pair of hands in one.
func control_botsworth() -> void:
	if game == null or not game.dev_on():
		return
	if possessing != 0:
		release_bot()
		return
	if not is_host():
		game.say("Only the host can control Dr. Botsworth.", 3.0)
		return
	var me = game.local_player()
	if me == null:
		return
	var id := _botsworth_id()
	if id == 0:
		id = spawn_bot("bot", me, BOTSWORTH, _botsworth_spot(me))
		order_bot(id, "stay")
	possess_bot(id)


func _botsworth_id() -> int:
	for id in bots.keys():
		if String(bots[id].get("name", "")) == BOTSWORTH and String(bots[id].get("kind", "")) == "bot":
			return int(id)
	return 0


## Beside the player table when you are lying on it (in front of you is the ceiling), else in front.
func _botsworth_spot(me: Node) -> Vector3:
	if me.on_table and not game.player_table.is_empty():
		var b := Basis(Vector3.UP, game.player_table_yaw())
		return game._floor_at((game.player_table.position as Vector3) + b * Vector3(1.3, 0.0, 0.0))
	return _in_front_of(me, 2.0)


## Local: your input and camera move into `id`'s body; your own surgeon stands (or lies) still.
func possess_bot(id: int) -> void:
	var p = game.players.get(id)
	if p == null or not is_instance_valid(p) or not bool(p.get("is_bot")) or not p.alive:
		return
	release_bot()
	possessing = id
	game.possessed = id
	p.set_possessed(true)
	var me = game.local_player()
	if me != null and is_instance_valid(me):
		me.dev_input_held = true
		me.set_dev_body(true)   # so you can look at yourself, lying there, from over there
	game.say("You are %s. The same button puts you back." % p.player_name, 3.0)
	state_changed.emit()


## Local: back into your own body. Safe to call when you are already in it.
func release_bot() -> void:
	if possessing == 0:
		return
	var p = game.players.get(possessing)
	possessing = 0
	game.possessed = 0
	if p != null and is_instance_valid(p):
		p.set_possessed(false)
	var me = game.local_player()
	if me != null and is_instance_valid(me):
		me.dev_input_held = false
		me.set_dev_body(false)
		if me.camera != null:
			me.camera.current = true
	state_changed.emit()


func remove_bot(id: int) -> void:
	if id == possessing:
		release_bot()   # GRAFT HOOK: never leave the camera in a body about to be freed
	if not bots.has(id):
		return
	var p = game.players.get(id)
	if p != null and is_host():
		game.end_operations(p)
		game._drop_hands(p, false)
	_free_bot(id)
	bots.erase(id)
	brains.erase(id)
	state_changed.emit()


func order_bot(id: int, new_order: String, kind: String = "", target: String = "", owner: int = 0) -> void:
	if not ORDERS.has(new_order) or not brains.has(id):
		return
	if kind != "" and not Items.exists(kind):
		kind = ""
	brains[id].set_order(new_order, kind, target, owner)
	bots[id]["order"] = new_order
	if kind != "":
		bots[id]["item"] = kind
	if target != "":
		bots[id]["to"] = target
	state_changed.emit()


func _make_bot_node(id: int, bot_name: String, kind: String) -> Node:
	var p = PlayerScript.new_player(id, bot_name, false)
	p.is_bot = true
	p.bot_active = true
	p.set_flashlight(false)
	if kind == "dummy":
		GunFx.dress_dummy(p.body_visual)
		p.name_tag.modulate = Color(1.0, 0.85, 0.35)
	else:
		p.name_tag.modulate = Color(0.55, 1.0, 0.9)
		p.name_tag.text = "[BOT] " + bot_name
	game.players[id] = p
	game.get_node("Entities").add_child(p)
	return p


func _free_bot(id: int) -> void:
	var p = game.players.get(id)
	if p != null:
		game.players.erase(id)
		p.queue_free()


func _revive(p: Node) -> void:
	var spots: Array = game.spawn_points()
	var at: Vector3 = p.global_position if p.get("is_bot") else spots[randi() % spots.size()]
	game._release_downed_links(p)   # downed hook
	p.teleport(at)
	p.revive_full()
	p.stun = 0.0
	p.refresh_downed_visuals()
	game._broadcast("revive", {"id": p.peer_id, "pos": at, "hp": p.max_hp})


func _in_front_of(who: Node, dist: float) -> Vector3:
	if who == null:
		return game.spawn_points()[0]
	var fwd: Vector3 = -who.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length() > 0.01 else Vector3.FORWARD
	var from: Vector3 = who.global_position + Vector3.UP * 1.0
	var q := PhysicsRayQueryParameters3D.create(from, from + fwd * dist)
	q.collision_mask = C.L_WORLD
	var hit: Dictionary = who.get_world_3d().direct_space_state.intersect_ray(q)
	var d := dist if hit.is_empty() else maxf(0.3, from.distance_to(hit.position) - 0.6)
	return game._floor_at(who.global_position + fwd * d)


# =========================================================================
# noclip (player.gd calls this for a noclipping local player or bot)
# =========================================================================

func noclip_move(p: Node, input_dir: Vector2, fast: bool, delta: float) -> void:
	var basis: Basis = p.camera.global_transform.basis
	var v: Vector3 = basis * Vector3(input_dir.x, 0.0, input_dir.y)
	if p.is_local and not p.bot_active:
		if Input.is_physical_key_pressed(KEY_SPACE):
			v += Vector3.UP
		if Input.is_physical_key_pressed(KEY_CTRL) or Input.is_physical_key_pressed(KEY_C):
			v += Vector3.DOWN
	var speed := (C.SPRINT_SPEED * 3.0) if fast else (C.WALK_SPEED * 2.0)
	p.velocity = Vector3.ZERO
	p.global_position += v.limit_length(1.0) * speed * delta
	p.moving = v.length() > 0.1


# =========================================================================
# replication
# =========================================================================

func net_state() -> Dictionary:
	var stun := {}
	for p in game.players.values():
		if p.stun > 0.0:
			stun[p.peer_id] = snappedf(p.stun, 0.1)
	return {
		"ts": time_scale, "fv": freeze_vitals, "ar": auto_revive,
		"mo": monsters_off, "ng": no_game_over,
		"gd": god.keys(), "nc": noclip.keys(), "gn": gun.keys(), "bt": bots, "st": stun,
		"nn": [nurse_ignore_watch, nurse_walk, nurse_pace],   # NURSE HOOK
	}


## Client: mirror the host's dev state. Runs before the snapshot's player list is applied, so
## bot Player nodes exist by the time their entries arrive.
func apply_net_state(s: Dictionary) -> void:
	if is_host():
		return
	time_scale = float(s.get("ts", 1.0))
	freeze_vitals = bool(s.get("fv", false))
	auto_revive = bool(s.get("ar", false))
	monsters_off = bool(s.get("mo", false))
	no_game_over = bool(s.get("ng", false))
	god = _as_set(s.get("gd", []))
	noclip = _as_set(s.get("nc", []))
	gun = _as_set(s.get("gn", []))
	var nn: Array = s.get("nn", [false, "", 0])   # NURSE HOOK
	if nn.size() >= 3:
		nurse_ignore_watch = bool(nn[0])
		nurse_walk = String(nn[1])
		nurse_pace = int(nn[2])
	var remote_bots: Dictionary = s.get("bt", {})
	var changed := remote_bots.size() != bots.size()
	for id in remote_bots.keys():
		var e: Dictionary = remote_bots[id]
		if not game.players.has(id):
			_make_bot_node(int(id), String(e.get("name", "Bot")), String(e.get("kind", "bot")))
			changed = true
	for id in bots.keys():
		if not remote_bots.has(id):
			_free_bot(id)
	bots = remote_bots
	var stun: Dictionary = s.get("st", {})
	for p in game.players.values():
		p.noclip = noclip.has(p.peer_id)
		var t := float(stun.get(p.peer_id, 0.0))
		if p.is_local:
			if t > p.stun + 0.3:
				p.stun = t
		else:
			p.stun = t
	if changed:
		state_changed.emit()


static func _as_set(ids: Array) -> Dictionary:
	var out := {}
	for id in ids:
		out[int(id)] = true
	return out


## One-off events from game._event that belong to dev mode.
func on_event(kind: String, data: Dictionary) -> void:
	match kind:
		"monster_killed":
			monster_died_fx(data)


func monster_died_fx(data: Dictionary) -> void:
	GunFx.monster_corpse(game.get_node("Entities"), String(data.get("kind", "sonographer")), data.get("pos", Vector3.ZERO), float(data.get("y", 0.0)))
	# SWEEP 3 HOOK (monsters): the Hive dies with its own groan.
	var death_cue := "monsters_hive_death" if String(data.get("kind", "")) == "hive" else "monsters_shriek"
	Audio.play(death_cue, data.get("pos", Vector3.ZERO) + Vector3.UP * 1.5, -4.0, 0.15)
