class_name Trinkets
extends Node
## TRINKETS (docs/ITEMS_AND_ICONS.md, chunk B). The loot items that sell but also do one thing,
## so it is always use it or sell it. A child "Trinkets" of Game on every machine.
##
##   Desk phone      left mouse sets it down and it rings for RING_SECONDS: a decoy. Pick it up and
##                   use it again. Selecting one has a PULL_RING_CHANCE of it ringing in your hands.
##   Laptop          once: MAP_SECONDS of a map of the MAP_RANGE metres around you, with blips for
##                   surgery items. Then the battery dies.
##   Defibrillator   once: aim at a downed teammate and revive them where they lie. Very loud.
##   Pulse oximeter  in the same window as the sedative jab (a shoved, stunned monster), clip it on
##                   instead of sedating. It gets up and carries on and the whole team hears its
##                   heartbeat through walls, faster the more interested it is. It comes back when
##                   that monster is caught or killed. The Night Nurse cannot be tagged.
##   Reflex hammer   a quick swing of the arm; whoever it lands on is whipped 180 degrees.
##                   Reusable, short cooldown.
##   EpiPen          once: jab yourself or a teammate for EPI_SECONDS of double sprint, then a
##                   EPI_COLLAPSE second collapse.
##   Restaurant pagers  a base station holding two pagers that know about each other. Using the
##                   station lifts the pair out. Pressing one buzzes the OTHER, anywhere in the
##                   hospital: if a person is holding it, only that person hears it; if it is lying
##                   on the floor, it rattles out loud where it lies and the monsters hear that.
##                   Break the pair (sell one, burn it, leave it behind) and what is left is loot.
##   Votive candle   POCKETS 2 phase 3 (the Chapel). Once: set it down and it burns for
##                   CANDLE_SECONDS. Inside CANDLE_RADIUS of a burning one the Night Nurse counts
##                   as watched with nobody looking at her (scripts/perception.gd), so a placed
##                   candle is a safe zone with a two minute fuse. Lighting it IS the use: it goes
##                   down already spent, worth scrap, so one candle buys one safe zone and you
##                   cannot pick it up and re-light it somewhere better.
##
## A one-use trinket that has been spent is marked `used` on its hand slot and its value drops to
## SCRAP: greyed with a crack in the item bar (hud.gd), and it still sells at the furnace. The mark
## travels with the stack when it is dropped (`x` == USED_MARK, world_item.gd).
##
## Authority: the host decides everything (uses, rings, tags, boosts) and replicates the small
## state below in the snapshot as "tk". Every machine plays the ring and the heartbeat itself from
## that state plus the monster's replicated mode, so nothing sound-related crosses the wire.

const MonsterScript := preload("res://scripts/monster.gd")
const LootTable := preload("res://scripts/economy/loot_table.gd")

## The eleven. Anything else falls through to combat.use (the saw and the needle).
const KINDS := ["desk_phone", "laptop", "defibrillator", "pulse_oximeter", "reflex_hammer", "epipen",
		"lifeguard_whistle", "restaurant_pagers", "restaurant_pager", "fabric_softener", "votive_candle"]
## Spent once and never again. The phone, the hammer and the pulse oximeter keep working.
const ONE_USE := ["laptop", "defibrillator", "epipen", "lifeguard_whistle", "fabric_softener",
		"votive_candle"]
## What a spent one-use trinket sells for: scrap, not nothing.
const SCRAP := {"laptop": 8, "defibrillator": 15, "epipen": 3, "lifeguard_whistle": 3,
		"fabric_softener": 4, "votive_candle": 3}
## The mark a spent trinket carries through a drop (WorldItem.x).
const USED_MARK := "used"
## The shortest gap the host accepts between one player's trinket uses.
const USE_GAP := 0.25

# --- the desk phone
const RING_SECONDS := 10.0
## How often it rings while it is ringing, and how loud that noise is to the monsters.
const RING_PERIOD := 1.5
const RING_LOUDNESS := 0.95
## The Hive is deaf, so a ring it could plausibly hear turns it toward the phone instead.
const RING_HIVE_RANGE := 14.0
## Every time you select a desk phone, this is the chance it goes off in your hands.
const PULL_RING_CHANCE := 0.12

# --- the laptop
const MAP_SECONDS := 7.0
const MAP_RANGE := 25.0
## The last stretch of the map is the low-battery warning: the screen stutters and a red battery blinks.
const MAP_LOW_SECONDS := 2.0

# --- the defibrillator
const DEFIB_REACH := 2.6
## Generous: you are holding the paddles over a body at your feet, and looking straight down at
## someone lying next to you is an awkward angle. Anything closer than DEFIB_CLOSE counts whichever
## way you face.
const DEFIB_CONE_DEG := 60.0
const DEFIB_CLOSE := 1.6
const DEFIB_NOISE := 1.0

# --- the pulse oximeter: the jab's window, so the same reach and cone
const TAG_REACH := 1.8
const TAG_CONE_DEG := 30.0
## Seconds between beats, by what the monster is doing.
const BEAT_WANDER := 1.05
const BEAT_SUSPICIOUS := 0.62
const BEAT_HUNTING := 0.36
const BEAT_DOWN := 1.6

# --- the reflex hammer
const HAMMER_REACH := 2.2
const HAMMER_CONE_DEG := 45.0
const HAMMER_COOLDOWN := 1.2

# --- the votive candle (POCKETS 2 phase 3)
## About two minutes of burn, as the Chapel spec asks for.
const CANDLE_SECONDS := 120.0
## How far the candle's regard reaches. Generous enough to hold a junction or a doorway, small
## enough that it is a place you stand rather than a wing you own.
const CANDLE_RADIUS := 5.0
## The last stretch of the burn, when the flame gutters and the light sinks: the tell that your
## safe zone is about to stop being one.
const CANDLE_GUTTER := 12.0
const CANDLE_ENERGY := 1.5
const CANDLE_RANGE := 8.0

# --- the EpiPen
const EPI_REACH := 2.0
const EPI_CONE_DEG := 45.0
const EPI_SECONDS := 10.0
const EPI_SPRINT_MULT := 2.0
const EPI_COLLAPSE := 3.0

# --- the lifeguard whistle (POCKETS 2 phase 2, the Natatorium)
## One blast, and it is the loudest thing a surgeon can make on purpose: louder than the Echo
## shriek (1.2), which is the yardstick, because a whistle is one use and the Echo is not. Reach is
## loudness * SonographerBrain.HEAR_PER_LOUDNESS, so 1.4 carries about 30 m and is well past LOUD
## (0.8) -- whatever hears it does not get suspicious, it comes.
const WHISTLE_NOISE := 1.4
## ... and the same distance is walked over to the deaf ones by hand. The Hive never hears a noise
## event at all, and "drawing wing monsters to the spot" is the whole item, so the noise and the
## nudge cover the same ground. This is Echo's attraction and nothing else: no ab_echo event is
## emitted, so there is no wall-vision (see scripts/abilities/abilities.gd `_echo`).
const WHISTLE_RANGE := 30.0

# --- the restaurant pagers (POCKETS 2 phase 5, the Restaurant)
## The shortest gap between one player's buzzes. Short, because the item is a conversation: long
## enough that you cannot use it as a siren, short enough to answer with.
const PAGER_COOLDOWN := 2.5
## A pager lying on the floor is a noisemaker, and this is how loud. Deliberately BELOW the desk
## phone's 0.95: the phone is a decoy you spend a whole item on and it shouts every RING_PERIOD for
## RING_SECONDS, while this is one rattle you can fire again in PAGER_COOLDOWN. It is still past
## SonographerBrain's LOUD (0.8), so what hears it comes rather than merely wondering -- the point
## of planting one is that it WORKS, just on a shorter leash than the phone.
const PAGER_NOISE := 0.85
## ... and the deaf Hive is walked over to it by hand, exactly as the phone's ring does.
const PAGER_HIVE_RANGE := 14.0
## How hard the private buzz kicks the holder's camera (CameraFX.add_shake trauma, 0..1). Small:
## it is a pager in your pocket, not a hit.
const PAGER_SHAKE := 0.1
const PAGER_SHAKE_TIME := 0.35
## The prefix of the pair id a bound pager carries in its stack's `x` (WorldItem.x). Two pagers with
## the same mark are the same pair; anything else is a lone pager, which is plain loot.
const PAIR_MARK := "pg"

var game: Node = null
## Host: the break roll for the pull-out ring. Tests seed it.
# --- POCKETS 2 phase 4: the fabric softener jug (the Laundromat)
## How long a swig keeps your footsteps quiet.
const QUIET_SECONDS := 60.0
## How much of the step sound you still hear yourself while it lasts, in decibels off the usual.
const QUIET_STEP_DB := -12.0

var rng := RandomNumberGenerator.new()
## Host: what the last use did, for tests: {what: "...", kind: ..., id: ...}.
var last_result: Dictionary = {}

# --- replicated ("tk"), host authoritative
var _rings: Dictionary = {}      ## world item id -> world_time the ring stops
var _hand_rings: Dictionary = {} ## peer id -> world_time the ring in their hands stops
var _maps: Dictionary = {}       ## peer id -> world_time the laptop map goes dark
var _tagged: Dictionary = {}     ## monster id -> the peer id whose pulse oximeter is on it
var _epi: Dictionary = {}        ## peer id -> world_time the sprint boost ends
var _quiet: Dictionary = {}      ## peer id -> world_time their quiet footsteps run out
var _candles: Dictionary = {}    ## world item id -> world_time its flame goes out
var _spins: Dictionary = {}      ## peer id -> how many times the reflex hammer has turned them (mod 64)
var _swings: Dictionary = {}     ## peer id -> how many reflex-hammer swings they have thrown (mod 64)
var _buzz: Dictionary = {}       ## peer id -> how many times the pager IN THEIR HANDS has buzzed (mod 64)
var _rattle: Dictionary = {}     ## world item id -> how many times that dropped pager has rattled (mod 64)

# --- host only
var _tag_value: Dictionary = {}  ## monster id -> the dollars the clipped-on pulse oximeter was worth
var _sel_seen: Dictionary = {}   ## peer id -> the kind their selected slot held last frame
var _hammer_cd: Dictionary = {}  ## peer id -> world_time their hammer is ready again
var _last_use: Dictionary = {}   ## peer id -> world_time of their last accepted trinket use
var _collapse: Dictionary = {}   ## peer id -> world_time their EpiPen collapse is due (0 none)
var _bonk_due: Dictionary = {}   ## peer id -> world_time their swing connects (see Player.SWING_CONTACT)

# --- every machine, local presentation only
var _beat: Dictionary = {}       ## monster id -> seconds until its next heartbeat
var _ring_at: Dictionary = {}    ## ring key -> seconds until its next ring
var _candle_lights: Dictionary = {} ## world item id -> the Node3D holding its "Bulb" (every machine)
var _spin_seen: Dictionary = {}  ## peer id -> the spin counter this machine has already acted on
var _swing_seen: Dictionary = {} ## peer id -> the swing counter this machine has already animated
var _buzz_seen: Dictionary = {}  ## peer id -> the buzz counter this machine has already felt
var _rattle_seen: Dictionary = {}## world item id -> the rattle counter this machine has already played

# --- host only, the pagers
var _pager_cd: Dictionary = {}   ## peer id -> world_time their pager may be pressed again
var _pair_next := 0              ## the next pair id to hand out


func setup(g: Node) -> void:
	game = g
	rng.randomize()


# =============================================================================== the used mark

## Is this hand slot (or world item dictionary) a spent one-use trinket?
static func is_spent(s: Dictionary) -> bool:
	return bool(s.get("used", false)) or String(s.get("x", "")) == USED_MARK


static func is_trinket(kind: String) -> bool:
	return KINDS.has(kind)


## What a spent one of this kind sells for.
static func scrap_value(kind: String) -> int:
	return int(SCRAP.get(kind, 0))


## Host: mark the stack in slot `head` as used up and drop its value to scrap.
func spend(p, head: int) -> void:
	var s: Dictionary = p.slots[head]
	s["used"] = true
	s["x"] = USED_MARK
	s["v"] = scrap_value(String(s.kind))


# =============================================================================== using one

## Every machine: does left mouse do a trinket's job with this kind in hand?
func is_usable(kind: String) -> bool:
	return KINDS.has(kind)


## The clicking machine, the moment left mouse goes down with a trinket in hand: the host does it,
## a client asks the host to. False when there is no trinket selected, so the click falls through
## to the shove, exactly as combat.local_try_use does for the saw and the needle.
func local_try_use(p) -> bool:
	if game == null or p == null or not is_instance_valid(p):
		return false
	if not is_usable(String(p.selected_stack().kind)):
		return false
	# A pager whose partner is gone is plain loot and nothing else, so the click must fall through
	# to the shove rather than being swallowed by a trinket that has no trick left. Checked on the
	# clicking machine because that is where the click is spent; the host checks again in _use_pager.
	if String(p.selected_stack().kind) == "restaurant_pager" and not _is_paired(p.selected_stack()):
		return false
	# The swing plays here the moment you click, so a melee swing feels like one even on a client
	# waiting on the host's answer. The host's `sw` counter arrives a moment later and _tick_swings
	# leaves an already-running swing alone, so it never restarts. A refused bonk (the cooldown, a
	# spent stack) simply leaves you swinging at nothing, which is what it looks like anyway.
	if String(p.selected_stack().kind) == "reflex_hammer" and p.has_method("start_swing") 			and not p.swinging():
		p.start_swing()
	if game.is_host():
		use(p)
	elif Net.active:
		_rpc_use.rpc_id(1)
	return true


@rpc("any_peer", "reliable", "call_remote")
func _rpc_use() -> void:
	if game == null or not game.is_host():
		return
	var p = game.players.get(multiplayer.get_remote_sender_id())
	if p == null or not is_instance_valid(p):
		return
	if not p.alive or p.downed or p.carrying != 0 or p.dragging_monster >= 0 or p.held_by >= 0 or p.stun > 0.0:
		return
	use(p)


## Host: left mouse with a trinket selected (the local path above, or game.player_used).
func use(p) -> void:
	if game == null or not game.is_host() or p == null or not is_instance_valid(p):
		return
	# One use per click, and never faster than a person can click: a duplicated RPC or a bot that
	# holds the button down must not fire a trinket twice.
	var now: float = game.world_time
	if now - float(_last_use.get(int(p.peer_id), -99.0)) < USE_GAP:
		return
	_last_use[int(p.peer_id)] = now
	var head: int = p.selected_head()
	if head < 0 or head >= p.slots.size():
		return
	var s: Dictionary = p.slots[head]
	var kind := String(s.kind)
	if not KINDS.has(kind):
		return
	if is_spent(s):
		last_result = {"what": "spent", "kind": kind}
		game.tell(p, "The %s is dead. Sell it." % Items.display_name(kind).to_lower(), 2.5)
		return
	match kind:
		"desk_phone": _use_phone(p, head)
		"laptop": _use_laptop(p, head)
		"defibrillator": _use_defib(p, head)
		"pulse_oximeter": _use_pulse_ox(p, head)
		"reflex_hammer": _use_hammer(p, head)
		"epipen": _use_epipen(p, head)
		"lifeguard_whistle": _use_whistle(p, head)
		"restaurant_pagers": _use_pager_station(p, head)
		"restaurant_pager": _use_pager(p, head)
		"fabric_softener": _use_fabric_softener(p, head)
		"votive_candle": _use_candle(p, head)


## Every machine (Player._update_aim, a few Hz): the crosshair line while holding a trinket that
## wants a target. "" when there is nothing to say.
func use_prompt(p) -> String:
	if game == null or p == null or not p.alive or p.downed:
		return ""
	var s: Dictionary = p.selected_stack()
	var kind := String(s.kind)
	if not KINDS.has(kind) or is_spent(s):
		return ""
	match kind:
		"desk_phone":
			return "[Click] Put it down and let it ring"
		"laptop":
			return "[Click] Open the laptop"
		"votive_candle":
			return "[Click] Light it and set it down"
		"epipen":
			var q := _downed_or_standing_mate(p, EPI_REACH, EPI_CONE_DEG, false)
			return "[Click] Jab %s" % (q.player_name if q != null else "yourself")
		"lifeguard_whistle":
			return "[Click] Blow it. Everything nearby will come."
		"restaurant_pagers":
			return "[Click] Take the two pagers off the station"
		"restaurant_pager":
			if not _is_paired(s):
				return ""        # a lone pager is loot: no prompt, and the click shoves
			var where := _partner_where(s, p)
			if where == "held":
				return "[Click] Buzz the other pager"
			if where == "floor":
				return "[Click] Buzz the other pager. You left it somewhere."
			return ""
		"fabric_softener":
			return "[Click] Drink the fabric softener"
		"defibrillator":
			var d := _downed_mate(p)
			if d == null:
				return ""
			return "[Click] Shock %s awake" % d.player_name
		"reflex_hammer":
			if float(_hammer_cd.get(int(p.peer_id), 0.0)) > float(game.world_time):
				return ""
			var t := _target(p, HAMMER_REACH, HAMMER_CONE_DEG)
			if t.is_empty():
				return ""
			return "[Click] Bonk it" if t.kind == "monster" else "[Click] Bonk %s" % t.node.player_name
		"pulse_oximeter":
			var t2 := _target(p, TAG_REACH, TAG_CONE_DEG)
			if t2.is_empty() or t2.kind != "monster":
				return ""
			var m: Node = t2.node
			if _tagged.has(int(m.monster_id)):
				return ""
			if not MonsterScript.is_capturable(String(m.kind)):
				return ""
			return "[Click] Clip the pulse oximeter on"
	return ""


# =============================================================================== the desk phone

## Set it down in front of you; it rings for RING_SECONDS and anything with ears comes to look.
func _use_phone(p, head: int) -> void:
	var s: Dictionary = p.slots[head]
	var fwd: Vector3 = -p.global_transform.basis.z
	var spot: Vector3 = game._floor_at(p.global_position + fwd * 0.7) + Vector3.UP * 0.05
	var it: Node = game._spawn_item("desk_phone", 1, Transform3D(Basis(Vector3.UP, p.rotation.y), spot), WorldItem.State.LOOSE)
	it.value = int(s.get("v", 0))
	p.clear_slot(head)
	_rings[int(it.item_id)] = float(game.world_time) + RING_SECONDS
	last_result = {"what": "phone_down", "id": int(it.item_id)}
	game._sound("trinkets_phone_pick", spot)
	game.tell(p, "It will ring for about %d seconds. Be somewhere else." % int(RING_SECONDS), 3.5)


## Host: a phone went off in somebody's hands (the pull-out roll, or a test).
func ring_in_hand(p) -> void:
	if p == null or not is_instance_valid(p):
		return
	_hand_rings[int(p.peer_id)] = float(game.world_time) + RING_SECONDS
	game.tell(p, "The phone goes off in your hands.", 3.0)


## Every machine: is something ringing right now? (tests, and the HUD could show it)
func ringing_items() -> Array:
	return _rings.keys()


func ringing_in_hand(peer_id: int) -> bool:
	return _hand_rings.has(peer_id)


## Where each ring is coming from this frame: [{key, pos}].
func _ring_sources() -> Array:
	var out: Array = []
	for id in _rings.keys():
		var it = game.world_items.get(int(id))
		if it != null and is_instance_valid(it) and it.is_inside_tree():
			out.append({"key": "i%d" % int(id), "pos": it.global_position + Vector3.UP * 0.1})
	for peer in _hand_rings.keys():
		var p = game.players.get(int(peer))
		if p != null and is_instance_valid(p) and p.is_inside_tree():
			out.append({"key": "p%d" % int(peer), "pos": p.global_position + Vector3.UP * 1.2})
	return out


## Host: one ring: a loud noise, and the deaf Hives nearby are told where it came from.
func _ring_heard(at: Vector3) -> void:
	game.emit_noise(at, RING_LOUDNESS, "phone")
	for m in game.monsters.values():
		if m == null or not is_instance_valid(m) or String(m.kind) != MonsterScript.HIVE:
			continue
		if m.global_position.distance_to(at) <= RING_HIVE_RANGE and m.has_method("alert_to"):
			m.alert_to(at)


# =============================================================================== the laptop

func _use_laptop(p, head: int) -> void:
	spend(p, head)
	_maps[int(p.peer_id)] = float(game.world_time) + MAP_SECONDS
	last_result = {"what": "map", "kind": "laptop"}
	game._sound("trinkets_laptop_open", p.global_position + Vector3.UP * 1.2)
	game.tell(p, "One charge left in it. Look while it lasts.", 3.0)


## Every machine: seconds of map left for this player (0 when the screen is dark). The HUD draws it.
func map_left(p) -> float:
	if p == null or game == null:
		return 0.0
	return maxf(0.0, float(_maps.get(int(p.peer_id), 0.0)) - float(game.world_time))


## The surgery items within MAP_RANGE of `p`, as world positions. The laptop's blips.
func map_blips(p) -> Array:
	var out: Array = []
	if p == null or game == null:
		return out
	var here: Vector3 = p.global_position
	for it in game.world_items.values():
		if it == null or not is_instance_valid(it) or not it.is_inside_tree():
			continue
		if not Items.is_surgical(String(it.kind)):
			continue
		if it.global_position.distance_to(here) <= MAP_RANGE:
			out.append(it.global_position)
	return out


# =============================================================================== the defibrillator

## The downed teammate in front of `p`, or null.
func _downed_mate(p) -> Node:
	var eye: Vector3 = p.head.global_position
	var dir: Vector3 = _aim_dir(p)
	var cos_cone := cos(deg_to_rad(DEFIB_CONE_DEG))
	var best: Node = null
	var best_d := DEFIB_REACH
	for q in game.players.values():
		if q == null or not is_instance_valid(q) or q == p or not q.alive or not q.downed:
			continue
		var to: Vector3 = (q.global_position + Vector3.UP * 0.4) - eye
		var d := to.length()
		if d > best_d or d < 0.001:
			continue
		if dir.dot(to / d) < cos_cone and d > DEFIB_CLOSE:
			continue
		best = q
		best_d = d
	return best


func _use_defib(p, head: int) -> void:
	var q := _downed_mate(p)
	if q == null:
		last_result = {"what": "no_target", "kind": "defibrillator"}
		game.tell(p, "Aim it at somebody who is down.", 2.5)
		return
	spend(p, head)
	var at: Vector3 = q.global_position + Vector3.UP * 0.5
	game._sound("trinkets_defib_zap", at)
	game.emit_noise(at, DEFIB_NOISE, "defib")
	revive_in_place(q)
	last_result = {"what": "revived", "id": int(q.peer_id)}
	game.say("%s shocked %s back onto their feet." % [p.player_name, q.player_name], 4.0)


## Host: up they get, exactly where they lie. game.revive_player scatters them to a spot beside the
## player table, which is right for a stitching and wrong for this.
func revive_in_place(q) -> void:
	if not game.is_host() or q == null or not is_instance_valid(q) or not q.alive or not q.downed:
		return
	var spot: Vector3 = q.global_position
	game._release_downed_links(q)
	q.revive(game.REVIVE_HP)
	q.refresh_downed_visuals()
	game._broadcast("revive", {"id": q.peer_id, "pos": spot, "hp": game.REVIVE_HP})
	game._sound("revive", spot)


# =============================================================================== the pulse oximeter

func _use_pulse_ox(p, head: int) -> void:
	var t := _target(p, TAG_REACH, TAG_CONE_DEG)
	if t.is_empty() or t.kind != "monster":
		last_result = {"what": "air", "kind": "pulse_oximeter"}
		return
	var m: Node = t.node
	var mid := int(m.monster_id)
	var mname := MonsterScript.display_name(String(m.kind))
	if _tagged.has(mid):
		last_result = {"what": "already", "id": mid}
		game.tell(p, "It already has one on.", 2.5)
		return
	if not MonsterScript.is_capturable(String(m.kind)):
		last_result = {"what": "refused", "id": mid}
		game.tell(p, "The clip will not stay on her.", 2.5)
		return
	# Any monster the Night Nurse rule allows takes the clip, shoved or not.
	var s: Dictionary = p.slots[head]
	_tag_value[mid] = int(s.get("v", 0))
	_tagged[mid] = int(p.peer_id)
	p.clear_slot(head)
	last_result = {"what": "tagged", "id": mid}
	game._sound("trinkets_clip_on", t.point)
	game.say("%s clipped a pulse oximeter onto the %s. Listen for it." % [p.player_name, mname], 4.0)


## Every machine: is this monster tagged, and by whom (0 nobody)?
func tagged_by(monster_id: int) -> int:
	return int(_tagged.get(monster_id, 0))


func tagged_ids() -> Array:
	return _tagged.keys()


## Every machine: what the heartbeat says this monster is doing.
static func heart_mode(m: Node) -> String:
	if m == null or not is_instance_valid(m):
		return ""
	match int(m.mode):
		MonsterScript.Mode.RUSH:
			return "hunting"
		MonsterScript.Mode.LISTEN, MonsterScript.Mode.SEARCH, MonsterScript.Mode.STALK, MonsterScript.Mode.RETREAT:
			return "suspicious"
		MonsterScript.Mode.STUNNED, MonsterScript.Mode.SEDATED:
			return "down"
	return "wandering"


## Seconds between beats for what it is doing now.
static func heartbeat_period(m: Node) -> float:
	match heart_mode(m):
		"hunting":
			return BEAT_HUNTING
		"suspicious":
			return BEAT_SUSPICIOUS
		"down":
			return BEAT_DOWN
	return BEAT_WANDER


## Host: a tagged monster is leaving the game (killed, or strapped to a table): the pulse oximeter
## drops where it stood, worth what it was worth.
func on_monster_removed(m: Node) -> void:
	if m == null or game == null or not game.is_host():
		return
	var mid := int(m.monster_id)
	if not _tagged.has(mid):
		return
	var owner_id := int(_tagged[mid])
	var value := int(_tag_value.get(mid, 0))
	_tagged.erase(mid)
	_tag_value.erase(mid)
	_beat.erase(mid)
	var spot: Vector3 = game._floor_at(m.global_position) + Vector3.UP * 0.25
	var it: Node = game._spawn_item("pulse_oximeter", 1, Transform3D(Basis(), spot), WorldItem.State.LOOSE)
	it.value = value
	var who = game.players.get(owner_id)
	var whose: String = who.player_name if who != null and is_instance_valid(who) else "Somebody"
	game.say("%s's pulse oximeter came off with it." % whose, 3.5)


## Host: every monster is going away (clock-out, a new shift). The tags go with them; nothing is
## dropped, because the level they were standing in is about to stop existing.
func on_monsters_cleared() -> void:
	_tagged.clear()
	_tag_value.clear()
	_beat.clear()


# =============================================================================== the reflex hammer

## Host: the click. The arm goes up now and the bonk lands when the swing looks like it connects
## (Player.SWING_CONTACT later, in _tick_bonks), so the hit is on the contact frame rather than the
## click frame. What the target is gets decided then, too, the way a real swing would.
func _use_hammer(p, _head: int) -> void:
	var now: float = game.world_time
	var peer := int(p.peer_id)
	if float(_hammer_cd.get(peer, 0.0)) > now:
		last_result = {"what": "cooldown", "kind": "reflex_hammer"}
		return
	_hammer_cd[peer] = now + HAMMER_COOLDOWN
	_swings[peer] = (int(_swings.get(peer, 0)) + 1) % 64
	_bonk_due[peer] = now + Player.SWING_CONTACT
	last_result = {"what": "swinging", "kind": "reflex_hammer"}


## Host: the contact frame of somebody's swing.
func _land_bonk(p) -> void:
	if p == null or not is_instance_valid(p):
		return
	var t := _target(p, HAMMER_REACH, HAMMER_CONE_DEG)
	if t.is_empty():
		last_result = {"what": "air", "kind": "reflex_hammer"}
		game._sound("trinkets_hammer_bonk", p.global_position + Vector3.UP * 1.2)
		return
	game._sound("trinkets_hammer_bonk", t.point)
	game.emit_noise(t.point, 0.35, "bonk")
	if t.kind == "player":
		var q: Node = t.node
		spin_player(q)
		last_result = {"what": "spun_player", "id": int(q.peer_id)}
		game.say("%s bonked %s on the knee." % [p.player_name, q.player_name], 2.5)
		return
	var m: Node = t.node
	if String(m.kind) == MonsterScript.NIGHT_NURSE:
		last_result = {"what": "immune", "id": int(m.monster_id)}
		game.tell(p, "She does not have reflexes.", 2.5)
		return
	spin_monster(m)
	last_result = {"what": "spun_monster", "id": int(m.monster_id)}


## Host: whoever this is, their view snaps 180 degrees. Only their own machine owns their camera, so
## what actually travels is a counter in the snapshot (`sp`): every machine watches its own player's
## and turns the view when it goes up. A counter rather than an event so a dropped or late packet
## cannot lose (or repeat) the turn.
func spin_player(q) -> void:
	if q == null or not is_instance_valid(q) or game == null or not game.is_host():
		return
	var peer := int(q.peer_id)
	_spins[peer] = (int(_spins.get(peer, 0)) + 1) % 64
	# Whoever this machine actually drives (its own surgeon, or a dev room bot the host steers)
	# turns here and now; a real remote client turns from the counter on its own machine.
	if q.has_method("spin_view") and (q.is_local or bool(q.get("is_bot"))):
		_spin_seen[peer] = _spins[peer]
		q.spin_view()
	elif q.has_method("spin_view"):
		# The host's copy of a remote player turns too, so its own view of them is not a beat
		# behind; the same eased turn, since the client will report exactly that heading.
		q.spin_view()


## Every machine: my own view turns when the host's counter for me goes up. A machine that has never
## seen the counter before (a fresh join, a keyframe) just remembers where it is.
func _tick_spins() -> void:
	var me = game.local_player()
	if me == null:
		return
	var peer := int(me.peer_id)
	var want := int(_spins.get(peer, 0))
	if not _spin_seen.has(peer):
		_spin_seen[peer] = want
		return
	if int(_spin_seen[peer]) == want:
		return
	_spin_seen[peer] = want
	if me.has_method("spin_view"):
		me.spin_view()


## Host: a swing that has reached its contact frame lands.
func _tick_bonks() -> void:
	if _bonk_due.is_empty():
		return
	var now: float = game.world_time
	for peer in _bonk_due.keys():
		if now < float(_bonk_due[peer]):
			continue
		_bonk_due.erase(peer)
		_land_bonk(game.players.get(int(peer)))


## Every machine: play the swing for anybody whose counter has gone up. Unlike the spin (which only
## the machine owning a camera may do) this is a body animation, so every machine runs it for every
## player. A machine that has never seen a counter before just remembers where it is, so a late
## joiner does not swing on arrival.
func _tick_swings() -> void:
	for peer in _swings.keys():
		var want := int(_swings[peer])
		if not _swing_seen.has(peer):
			_swing_seen[peer] = want
			continue
		if int(_swing_seen[peer]) == want:
			continue
		_swing_seen[peer] = want
		var p = game.players.get(int(peer))
		# Already swinging here means the clicking machine predicted it; let that one play out.
		if p != null and is_instance_valid(p) and p.has_method("start_swing") and not p.swinging():
			p.start_swing()


## Host: the monster turns right round, and loses whatever it was looking at.
func spin_monster(m: Node) -> void:
	if m == null or not is_instance_valid(m):
		return
	if m.has_method("spin_around"):
		m.spin_around()


# =============================================================================== the EpiPen

## The teammate in front of `p` (downed ones count only when `include_downed`), or null for yourself.
func _downed_or_standing_mate(p, reach: float, cone_deg: float, include_downed: bool) -> Node:
	var eye: Vector3 = p.head.global_position
	var dir: Vector3 = _aim_dir(p)
	var cos_cone := cos(deg_to_rad(cone_deg))
	var best: Node = null
	var best_d := reach
	for q in game.players.values():
		if q == null or not is_instance_valid(q) or q == p or not q.alive:
			continue
		if q.downed and not include_downed:
			continue
		var to: Vector3 = (q.global_position + Vector3.UP * 1.0) - eye
		var d := to.length()
		if d > best_d or d < 0.001 or dir.dot(to / d) < cos_cone:
			continue
		best = q
		best_d = d
	return best


func _use_epipen(p, head: int) -> void:
	var q := _downed_or_standing_mate(p, EPI_REACH, EPI_CONE_DEG, false)
	if q == null:
		q = p
	spend(p, head)
	jab_epipen(q)
	last_result = {"what": "epi", "id": int(q.peer_id)}
	if q == p:
		game.tell(p, "Ten seconds. Then you are going to fall over.", 3.5)
	else:
		game.say("%s jabbed %s with an EpiPen." % [p.player_name, q.player_name], 3.0)


## Host: one blast, from where the blower stands. Everything within earshot comes to that spot --
## including the Hive, which is deaf to noise events and gets told by hand. It is Echo's draw with
## none of Echo's sight: nothing is revealed through a wall, and the only thing anyone learns is
## where the noise was, which is exactly where you are standing. Spent afterwards; sells as scrap.
func _use_whistle(p, head: int) -> void:
	var at: Vector3 = p.global_position + Vector3.UP * 1.5
	spend(p, head)
	game.emit_noise(at, WHISTLE_NOISE, "whistle")
	for m in game.monsters.values():
		if m == null or not is_instance_valid(m) or not m.has_method("alert_to"):
			continue
		if m.global_position.distance_to(at) <= WHISTLE_RANGE:
			m.alert_to(at)
	game._sound("trinkets_whistle", at)
	game.say("%s blew a lifeguard whistle." % p.player_name, 3.0)
	game.tell(p, "They heard that. All of them.", 3.0)
	last_result = {"what": "whistle", "pos": at}


# =============================================================================== the pagers
#
# THE PAIR. Two pagers are bound by a pair id living in the stack's `x` -- the same small string
# field that carries a spent trinket's `used` mark and a grafted eye's owner. That is the whole
# binding, and it is deliberately not a table on this node: `x` already survives being dropped,
# thrown, shelved, scattered on death and picked up again (game.gd writes it both ways), and it is
# already replicated with the world item. A table here would have to be taught all of that.
#
# BREAKING THE PAIR is therefore not an event anyone has to remember to fire. A pager asks, at the
# moment it is pressed, whether anything else in the world still carries its mark. Sell one, burn
# one in the furnace, or simply leave one behind when the shift rebuilds, and the survivor finds
# nothing -- and a pager that finds nothing is plain loot, with no prompt and a click that falls
# through to a shove. One rule covers every way a pair can be broken, including ways we have not
# thought of.

## Is this stack one of a bound pair (as opposed to a lone pager)?
func _is_paired(s: Dictionary) -> bool:
	return String(s.get("x", "")).begins_with(PAIR_MARK)


## The pair id a stack carries, or "".
static func pair_id(s: Dictionary) -> String:
	var x := String(s.get("x", ""))
	return x if x.begins_with(PAIR_MARK) else ""


## Everything in the world wearing `mark`, as [{where, peer?, head?, item?}]. `skip_head` and
## `skip_peer` leave out the pager doing the asking, so a pager never finds itself.
func _pair_members(mark: String, skip_peer: int, skip_head: int) -> Array:
	var out: Array = []
	if mark == "" or game == null:
		return out
	for p in game.players.values():
		if p == null or not is_instance_valid(p):
			continue
		for i in p.slots.size():
			var s: Dictionary = p.slots[i]
			if String(s.get("kind", "")) != "restaurant_pager" or String(s.get("x", "")) != mark:
				continue
			if int(p.peer_id) == skip_peer and i == skip_head:
				continue
			out.append({"where": "held", "peer": int(p.peer_id), "head": i, "node": p})
	for it in game.world_items.values():
		if it == null or not is_instance_valid(it) or not it.is_inside_tree():
			continue
		if String(it.kind) != "restaurant_pager" or String(it.x) != mark:
			continue
		out.append({"where": "floor", "item": int(it.item_id), "node": it})
	return out


## Every machine (the crosshair line): where this pager's partner is -- "held", "floor" or "".
func _partner_where(s: Dictionary, p) -> String:
	var found := _pair_members(pair_id(s), int(p.peer_id), p.selected_head())
	return String(found[0].where) if not found.is_empty() else ""


## Host: lift the two pagers off the station. One ends up in your hands and one on the floor at your
## feet, which is the item stating what it is for: one of them is meant to leave with somebody else,
## or to be put somewhere on purpose.
func _use_pager_station(p, head: int) -> void:
	var s: Dictionary = p.slots[head]
	var mark := "%s%d" % [PAIR_MARK, _pair_next]
	_pair_next += 1
	var worth: int = int(s.get("v", 0))
	var each: int = maxi(1, worth / 2)
	# The station itself is consumed: what it was worth is now split between the two pagers, so
	# taking the pair out never mints or burns money.
	p.clear_slot(head)
	var fwd: Vector3 = -p.global_transform.basis.z
	var spot: Vector3 = game._floor_at(p.global_position + fwd * 0.7) + Vector3.UP * 0.05
	# One in your hands. The station's slot was just freed, so there is room -- but if something has
	# taken it in the meantime, that pager goes on the floor beside the other rather than vanishing.
	var mine: int = p.take_into("restaurant_pager", 1, each)
	if mine >= 0:
		p.slots[mine]["x"] = mark
	else:
		var spare: Node = game._spawn_item("restaurant_pager", 1, Transform3D(Basis(Vector3.UP, p.rotation.y), spot + fwd * 0.25), WorldItem.State.LOOSE)
		spare.value = each
		spare.x = mark
	# ... and one at your feet.
	var it: Node = game._spawn_item("restaurant_pager", 1, Transform3D(Basis(Vector3.UP, p.rotation.y), spot), WorldItem.State.LOOSE)
	it.value = worth - each
	it.x = mark
	last_result = {"what": "pagers_out", "kind": mark, "id": int(it.item_id)}
	game._sound("trinkets_phone_pick", spot)
	game.tell(p, "Two pagers, bound to each other. One of you takes the other.", 4.0)


## Host: press this pager and the OTHER one goes off, wherever in the hospital it is.
##
## THE PRIVATE BUZZ. When the partner is in somebody's hands, only that somebody may hear it. This
## is done the way the rest of this file does everything: a counter in the replicated state, not a
## targeted RPC. `_buzz[peer]` goes up by one, every machine receives it, and every machine then
## decides for itself whether it is the one that should render it -- which is true only on the
## machine where that peer is the LOCAL player. Privacy is enforced at the render, not at the
## delivery. The reason is the one written at the top of this file and in the reflex hammer's
## comment: a counter cannot be lost or repeated by a dropped packet, while a one-off event can,
## and a communication device that silently drops messages is a broken communication device.
## The sound is played with no position (Audio.play's 2D path), so it is in that player's ears
## rather than in the room, and it cannot be heard by standing next to them.
func _use_pager(p, head: int) -> void:
	var s: Dictionary = p.slots[head]
	var mark := pair_id(s)
	var found := _pair_members(mark, int(p.peer_id), head)
	if mark == "" or found.is_empty():
		# Sold, burnt, or left behind in a shift that has been rebuilt since.
		last_result = {"what": "pager_alone"}
		game.tell(p, "Nothing answers. The other one is gone.", 2.5)
		return
	var now: float = game.world_time
	if now < float(_pager_cd.get(int(p.peer_id), 0.0)):
		last_result = {"what": "pager_cooldown"}
		return
	_pager_cd[int(p.peer_id)] = now + PAGER_COOLDOWN
	var other: Dictionary = found[0]
	if String(other.where) == "held":
		var peer := int(other.peer)
		_buzz[peer] = (int(_buzz.get(peer, 0)) + 1) % 64
		last_result = {"what": "pager_buzz", "id": peer}
	else:
		# On the floor: nothing is damping it, so it walks around and every machine hears it where
		# it lies. This is the remote noisemaker, and it is the host that tells the monsters.
		var iid := int(other.item)
		_rattle[iid] = (int(_rattle.get(iid, 0)) + 1) % 64
		var at: Vector3 = (other.node as Node3D).global_position + Vector3.UP * 0.05
		_pager_heard(at)
		last_result = {"what": "pager_rattle", "id": iid, "pos": at}


## Host: a planted pager going off is a noise like any other, and the deaf Hive is told by hand --
## the same two lines the desk phone's ring uses, for the same reason.
func _pager_heard(at: Vector3) -> void:
	game.emit_noise(at, PAGER_NOISE, "pager")
	for m in game.monsters.values():
		if m == null or not is_instance_valid(m) or String(m.kind) != MonsterScript.HIVE:
			continue
		if m.global_position.distance_to(at) <= PAGER_HIVE_RANGE and m.has_method("alert_to"):
			m.alert_to(at)


## Every machine: act on the two pager counters. The buzz is rendered only where its owner is the
## local player; the rattle is rendered by everyone, positionally, because it really is in the room.
func _tick_pagers() -> void:
	for peer in _buzz.keys():
		var n := int(_buzz[peer])
		var seen := int(_buzz_seen.get(peer, -1))
		_buzz_seen[peer] = n
		if seen < 0 or seen == n:
			continue        # first sight of a counter is never a buzz: a late joiner must not jump
		var q = game.players.get(int(peer))
		if q == null or not is_instance_valid(q) or not q.is_local:
			continue        # everyone else received it and deliberately renders nothing
		Audio.play("trinkets_pager_buzz")     # no position: in their ears, not in the room
		if q.fx != null and q.fx.has_method("add_shake"):
			q.fx.add_shake(PAGER_SHAKE, PAGER_SHAKE_TIME)
	for peer in _buzz_seen.keys():
		if not _buzz.has(peer):
			_buzz_seen.erase(peer)
	for iid in _rattle.keys():
		var n2 := int(_rattle[iid])
		var seen2 := int(_rattle_seen.get(iid, -1))
		_rattle_seen[iid] = n2
		if seen2 < 0 or seen2 == n2:
			continue
		var it = game.world_items.get(int(iid))
		if it == null or not is_instance_valid(it) or not it.is_inside_tree():
			continue
		Audio.play("trinkets_pager_rattle", it.global_position + Vector3.UP * 0.05)
	for iid in _rattle_seen.keys():
		if not _rattle.has(iid):
			_rattle_seen.erase(iid)


## Host: the boost starts on `q` (tests call it directly).
func jab_epipen(q) -> void:
	if q == null or not is_instance_valid(q) or game == null or not game.is_host():
		return
	var now: float = game.world_time
	_epi[int(q.peer_id)] = now + EPI_SECONDS
	_collapse[int(q.peer_id)] = now + EPI_SECONDS
	game._sound("trinkets_epipen", q.global_position + Vector3.UP * 1.1)


## POCKETS 2 phase 4: drink the jug. For QUIET_SECONDS your footsteps make no noise event at all —
## the same nothing a crouching player makes (game.gd `_tick_noise`) — except that you keep walking
## and sprinting at full speed. It is the crouch multiplier, not a second quiet mode, so a monster
## that cannot hear a crouching player cannot hear you either.
func _use_fabric_softener(p, head: int) -> void:
	spend(p, head)
	drink_softener(p)
	last_result = {"what": "quiet", "id": int(p.peer_id)}
	game.tell(p, "It coats your throat. Your feet stop making any sound at all.", 3.5)


## Host: the quiet starts on `q` (tests call it directly).
func drink_softener(q) -> void:
	if q == null or not is_instance_valid(q) or game == null or not game.is_host():
		return
	_quiet[int(q.peer_id)] = float(game.world_time) + QUIET_SECONDS
	game._sound("trinkets_softener", q.global_position + Vector3.UP * 1.3)


## Every machine: whether this player's steps are making no noise right now.
func quiet_steps(p) -> bool:
	if p == null or game == null:
		return false
	return float(_quiet.get(int(p.peer_id), 0.0)) > float(game.world_time)


## Every machine: how much faster this player sprints right now (1.0 normally).
func sprint_mult(p) -> float:
	if p == null or game == null:
		return 1.0
	return EPI_SPRINT_MULT if float(_epi.get(int(p.peer_id), 0.0)) > float(game.world_time) else 1.0


func boosted(p) -> bool:
	return sprint_mult(p) > 1.0


# =============================================================================== the votive candle

## Set it down in front of you and light it. It burns for CANDLE_SECONDS, and while it burns the
## Night Nurse counts as watched anywhere within CANDLE_RADIUS of it even though nobody is looking
## (scripts/perception.gd calls candle_watches before it asks whether anyone can see the point).
##
## It goes into the world already spent. Lighting a candle is what a candle is for, so there is no
## state where you are carrying a lit one: one candle is one safe zone, in one place, and moving it
## is not on the table. What you can pick up afterwards is the stub, worth SCRAP.
func _use_candle(p, head: int) -> void:
	var fwd: Vector3 = -p.global_transform.basis.z
	var spot: Vector3 = game._floor_at(p.global_position + fwd * 0.7) + Vector3.UP * 0.05
	var it: Node = game._spawn_item("votive_candle", 1, Transform3D(Basis(Vector3.UP, p.rotation.y), spot), WorldItem.State.LOOSE)
	it.value = scrap_value("votive_candle")
	it.x = USED_MARK
	p.clear_slot(head)
	_candles[int(it.item_id)] = float(game.world_time) + CANDLE_SECONDS
	last_result = {"what": "candle_lit", "id": int(it.item_id)}
	game._sound("trinkets_candle_light", spot)
	game.tell(p, "About two minutes of light. She will not move while you are in it.", 4.0)


## Every machine: is any of `points` inside a burning candle? This is the whole of the Night Nurse
## rule the candle buys, and it is deliberately the same predicate the rest of the game uses rather
## than a second one bolted onto her brain.
func candle_watches(points: Array) -> bool:
	if _candles.is_empty() or game == null:
		return false
	var r2 := CANDLE_RADIUS * CANDLE_RADIUS
	for id in _candles.keys():
		var it = game.world_items.get(int(id))
		if it == null or not is_instance_valid(it) or not it.is_inside_tree():
			continue
		var at: Vector3 = (it as Node3D).global_position
		for p: Vector3 in points:
			if at.distance_squared_to(p) <= r2:
				return true
	return false


## Every machine (tests, the HUD): seconds of burn left on this one, 0 when it is out.
func candle_left(item_id: int) -> float:
	if game == null or not _candles.has(item_id):
		return 0.0
	return maxf(0.0, float(_candles[item_id]) - float(game.world_time))


func lit_candles() -> Array:
	return _candles.keys()


## Host: flames that have burned down. The item stays where it is, already marked spent.
func _tick_candles() -> void:
	var now: float = game.world_time
	for id in _candles.keys():
		var it = game.world_items.get(int(id))
		if it != null and is_instance_valid(it) and now < float(_candles[id]):
			continue
		_candles.erase(id)


## Every machine: the candle's own light, which is a real OmniLight3D and not an emissive fake,
## because the Night Nurse's watched rule asks whether a point is LIT and a fake would not answer.
## It is registered in level_info.lights so Perception.fixture_lit finds it exactly as it finds a
## ceiling fixture, and it guts out over the last CANDLE_GUTTER seconds so the flame visibly dies
## instead of vanishing between frames.
func _play_candles(_delta: float) -> void:
	for id in _candle_lights.keys():
		if _candles.has(id) and is_instance_valid(_candle_lights[id]):
			continue
		_drop_candle_light(int(id))
	for id in _candles.keys():
		var it = game.world_items.get(int(id))
		if it == null or not is_instance_valid(it) or not it.is_inside_tree():
			continue
		if not _candle_lights.has(int(id)):
			_make_candle_light(int(id), it)
		var node = _candle_lights.get(int(id))
		if node == null or not is_instance_valid(node):
			continue
		var left := candle_left(int(id))
		var k := clampf(left / CANDLE_GUTTER, 0.0, 1.0)
		var bulb: OmniLight3D = (node as Node3D).get_node_or_null("Bulb")
		if bulb != null:
			# A guttering flame, not a dimmer: it jumps about as it goes.
			var jump := 1.0 if k >= 1.0 else k * (0.72 + 0.28 * sin(float(game.world_time) * 11.0 + float(id)))
			bulb.light_energy = CANDLE_ENERGY * maxf(0.0, jump)


func _make_candle_light(id: int, it: Node) -> void:
	var node := Node3D.new()
	node.name = "CandleLight"
	var bulb := OmniLight3D.new()
	bulb.name = "Bulb"
	bulb.light_energy = CANDLE_ENERGY
	bulb.omni_range = CANDLE_RANGE
	bulb.omni_attenuation = 1.4
	bulb.light_color = Color(1.0, 0.66, 0.32)
	bulb.light_volumetric_fog_energy = 1.3
	bulb.shadow_enabled = false
	bulb.set_meta("base_energy", CANDLE_ENERGY)
	node.add_child(bulb)
	node.position = Vector3(0, 0.12, 0)
	(it as Node3D).add_child(node)
	_candle_lights[id] = node
	if game.level_info != null:
		(game.level_info.get("lights", []) as Array).append(
				{"tile": Vector2i.ZERO, "position": (it as Node3D).global_position, "mode": 0, "node": node, "candle": id})


func _drop_candle_light(id: int) -> void:
	var node = _candle_lights.get(id)
	_candle_lights.erase(id)
	if game != null and game.level_info != null:
		var lights: Array = game.level_info.get("lights", [])
		for i in range(lights.size() - 1, -1, -1):
			if int((lights[i] as Dictionary).get("candle", -1)) == id:
				lights.remove_at(i)
	if node != null and is_instance_valid(node):
		if game != null:
			Audio.play("trinkets_candle_out", (node as Node3D).global_position)
		(node as Node).queue_free()


# =============================================================================== targets

func _aim_dir(p) -> Vector3:
	return Basis(Vector3.UP, p.rotation.y) * Basis(Vector3.RIGHT, p.head.rotation.x) * Vector3.FORWARD


## Combat already knows how to find the nearest monster or standing player in a cone with a clear
## line; the hammer and the clip want exactly that.
func _target(p, reach: float, cone_deg: float) -> Dictionary:
	if game == null or game.combat == null:
		return {}
	return game.combat.find_target(p, reach, cone_deg)


# =============================================================================== ticking

func physics_tick(delta: float) -> void:
	if game == null or game.phase == game.Phase.MENU:
		return
	if game.is_host():
		_host_tick(delta)
	_apply_boosts()
	_tick_spins()
	_tick_swings()
	_tick_pagers()
	_play_rings(delta)
	_play_heartbeats(delta)
	_play_candles(delta)


func _host_tick(delta: float) -> void:
	var now: float = game.world_time
	# A desk phone selected: the pull-out roll, once per selection.
	for p in game.players.values():
		if p == null or not is_instance_valid(p):
			continue
		var peer := int(p.peer_id)
		var head: int = p.selected_head()
		var kind := String(p.slots[head].kind) if head >= 0 and head < p.slots.size() else ""
		var was := String(_sel_seen.get(peer, ""))
		_sel_seen[peer] = kind
		if kind == "desk_phone" and was != "desk_phone" and not _hand_rings.has(peer) and p.alive and not p.downed:
			if rng.randf() < PULL_RING_CHANCE:
				ring_in_hand(p)
	# Rings running out, and the noise each one makes.
	for id in _rings.keys():
		var it = game.world_items.get(int(id))
		if now >= float(_rings[id]) or it == null or not is_instance_valid(it):
			_rings.erase(id)
	for peer in _hand_rings.keys():
		var p2 = game.players.get(int(peer))
		if now >= float(_hand_rings[peer]) or p2 == null or not is_instance_valid(p2) or not p2.alive:
			_hand_rings.erase(peer)
	# Laptop screens going dark.
	for peer in _maps.keys():
		if now >= float(_maps[peer]):
			_maps.erase(peer)
	# The EpiPen wearing off: they drop where they stand for EPI_COLLAPSE seconds.
	for peer in _epi.keys():
		if now < float(_epi[peer]):
			continue
		_epi.erase(peer)
		if float(_collapse.get(peer, 0.0)) <= 0.0:
			continue
		_collapse.erase(peer)
		var p3 = game.players.get(int(peer))
		if p3 == null or not is_instance_valid(p3) or not p3.alive or p3.downed:
			continue
		p3.stun = EPI_COLLAPSE
		game._broadcast("stun", {"id": int(peer), "t": EPI_COLLAPSE})
		game._sound("downed_fall", p3.global_position)
		game.tell(p3, "That is the adrenaline gone.", 3.0)
	# The fabric softener wearing off: your feet come back.
	for peer in _quiet.keys():
		if now < float(_quiet[peer]):
			continue
		_quiet.erase(peer)
		var p4 = game.players.get(int(peer))
		if p4 != null and is_instance_valid(p4) and p4.alive:
			game.tell(p4, "You can hear your own footsteps again.", 3.0)
	# A tagged monster that stopped existing without going through kill_monster.
	for mid in _tagged.keys():
		var m = game.monsters.get(int(mid))
		if m == null or not is_instance_valid(m):
			_tagged.erase(mid)
			_tag_value.erase(mid)
	_tick_ring_noise(delta)
	_tick_bonks()
	_tick_candles()


## Host: each ringing phone shouts about RING_PERIOD apart. The local sound is played by
## _play_rings on every machine, from the same clock, so they land together.
var _noise_at: Dictionary = {}


func _tick_ring_noise(delta: float) -> void:
	var live := {}
	for src in _ring_sources():
		var key := String(src.key)
		live[key] = true
		var left := float(_noise_at.get(key, 0.0)) - delta
		if left <= 0.0:
			left = RING_PERIOD
			_ring_heard(src.pos)
		_noise_at[key] = left
	for key in _noise_at.keys():
		if not live.has(key):
			_noise_at.erase(key)


## Every machine: the ring itself.
func _play_rings(delta: float) -> void:
	var live := {}
	for src in _ring_sources():
		var key := String(src.key)
		live[key] = true
		var left := float(_ring_at.get(key, 0.0)) - delta
		if left <= 0.0:
			left = RING_PERIOD
			Audio.play("trinkets_phone_ring", src.pos)
		_ring_at[key] = left
	for key in _ring_at.keys():
		if not live.has(key):
			_ring_at.erase(key)


## Every machine: a tagged monster's heartbeat, positional and through walls, its rate following
## what the monster is replicated as doing.
func _play_heartbeats(delta: float) -> void:
	for mid in _tagged.keys():
		var m = game.monsters.get(int(mid))
		if m == null or not is_instance_valid(m) or not m.is_inside_tree():
			continue
		var left := float(_beat.get(mid, 0.0)) - delta
		if left <= 0.0:
			left = heartbeat_period(m)
			Audio.play("trinkets_heartbeat", m.global_position + Vector3.UP * 1.1, -3.0)
		_beat[mid] = left
	for mid in _beat.keys():
		if not _tagged.has(mid):
			_beat.erase(mid)


## Every machine: the EpiPen's double sprint, pushed onto the player every frame so a boost that
## ends (or arrives late over the wire) always agrees with the replicated state.
func _apply_boosts() -> void:
	for p in game.players.values():
		if p == null or not is_instance_valid(p):
			continue
		p.sprint_mult = sprint_mult(p)
		p.silent_steps = quiet_steps(p)


# =============================================================================== networking

func net_state() -> Dictionary:
	var s := {}
	if not _rings.is_empty():
		s["ri"] = _snapped(_rings)
	if not _hand_rings.is_empty():
		s["rh"] = _snapped(_hand_rings)
	if not _maps.is_empty():
		s["mp"] = _snapped(_maps)
	if not _tagged.is_empty():
		s["tg"] = _tagged.duplicate()
	if not _epi.is_empty():
		s["ep"] = _snapped(_epi)
	if not _quiet.is_empty():
		s["qt"] = _snapped(_quiet)
	if not _candles.is_empty():
		s["cd"] = _snapped(_candles)
	if not _spins.is_empty():
		s["sp"] = _spins.duplicate()
	if not _swings.is_empty():
		s["sw"] = _swings.duplicate()
	if not _buzz.is_empty():
		s["pb"] = _buzz.duplicate()
	if not _rattle.is_empty():
		s["pr"] = _rattle.duplicate()
	return s


static func _snapped(d: Dictionary) -> Dictionary:
	var out := {}
	for k in d.keys():
		out[k] = snappedf(float(d[k]), 0.1)
	return out


func apply_net_state(s: Dictionary) -> void:
	if game != null and game.is_host():
		return
	_rings = _ints((s.get("ri", {}) as Dictionary))
	_hand_rings = _ints((s.get("rh", {}) as Dictionary))
	_maps = _ints((s.get("mp", {}) as Dictionary))
	_tagged = _ints((s.get("tg", {}) as Dictionary))
	_epi = _ints((s.get("ep", {}) as Dictionary))
	_quiet = _ints((s.get("qt", {}) as Dictionary))
	_candles = _ints((s.get("cd", {}) as Dictionary))
	_spins = _ints((s.get("sp", {}) as Dictionary))
	_swings = _ints((s.get("sw", {}) as Dictionary))
	_buzz = _ints((s.get("pb", {}) as Dictionary))
	_rattle = _ints((s.get("pr", {}) as Dictionary))


## Dictionary keys come back off the wire as floats; every key here is an id.
static func _ints(d: Dictionary) -> Dictionary:
	var out := {}
	for k in d.keys():
		out[int(k)] = d[k]
	return out


## Reserved for the system's own reliable one-offs ("tk_*", game._event). Nothing needs one yet: the
## reflex hammer's view snap rides the snapshot counter instead (spin_player).
func on_event(_kind: String, _data: Dictionary) -> void:
	pass


## Host: a game over. Nothing survives the run.
func on_reset() -> void:
	_rings.clear()
	_hand_rings.clear()
	_maps.clear()
	_tagged.clear()
	_tag_value.clear()
	_epi.clear()
	_quiet.clear()
	_collapse.clear()
	for id in _candle_lights.keys():
		_drop_candle_light(int(id))
	_candles.clear()
	_sel_seen.clear()
	_hammer_cd.clear()
	_last_use.clear()
	_spins.clear()
	_spin_seen.clear()
	_swings.clear()
	_swing_seen.clear()
	_bonk_due.clear()
	_beat.clear()
	_ring_at.clear()
	_noise_at.clear()
	_buzz.clear()
	_buzz_seen.clear()
	_rattle.clear()
	_rattle_seen.clear()
	_pager_cd.clear()
	_pair_next = 0
