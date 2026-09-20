class_name Grafts
extends Node
## GRAFTING (docs/GRAFTING.md chunk C, docs/GRAFTING_TRACHEA.md): Eyeball Grafting and Trachea
## Grafting. A child "Grafts" of Game on every machine.
##
## The loop: a surgeon straps themselves to a free OR table (chunk B), somebody sets a specimen vat
## holding a body part on that table (vats.gd, `vat_on_table`), and another surgeon operates. The part in
## the vat decides which surgery it is -- an eyeball is Eyeball Grafting, a trachea is Trachea
## Grafting -- and the part that comes out goes into the same vat, so a graft is always a swap and
## never an empty socket. Nothing can be botched (the case sets `no_fail`) and the patient is awake
## the whole time, watching it happen.
##
## GRAFT SITES. A surgeon wears at most one graft per SITE (Eyes.SITE): `eye` is the left socket,
## `throat` is the windpipe. They are independent, so a surgeon can hold both grafts at once, each
## teaching its own ability at level 1 (PART_ABILITY).
##
## Authority: the host runs the case (through scripts/downed/player_surgery.gd, which already stands
## in as a game for one table's surgery system) and owns `_graft`; every machine gets `_graft` in the
## snapshot ("gf") and draws the swapped part, its glow and the first-person tint from it.

const PartScript := preload("res://scripts/grafting/graft_eye.gd")
const ThroatScript := preload("res://scripts/grafting/graft_throat.gd")
const LootTable := preload("res://scripts/economy/loot_table.gd")

## Part kind -> the ability grafting it grants at level 1. Removing the part takes the ability away.
const PART_ABILITY := {"eye_hive": "hive_in", "trachea_sonographer": "echo"}
## Graft site -> the surgery that swaps a part there.
const SITE_AILMENT := {"eye": "eye_graft", "throat": "trachea_graft"}
## The eyeball's radius on a surgeon (the minigames' work plane).
const EYE_RADIUS := 0.0135
## And on the body afterwards: the size of the eye it replaces (GraftEye.RADIUS). Bigger pokes
## through the lids.
const BODY_EYE_RADIUS := GraftEye.RADIUS
## What the eye rests at. Your own torch never lights your own face, so at a flat 0 the grafted eye
## was nothing but a pinpoint in the mirror; a low ember reads as a Hive eye without flaring.
const LOCK_IDLE := 0.22
## How fast a graft's `lock` climbs and falls as its ability starts and stops.
const LOCK_RATE := 3.0
## How long a grafted throat burns after Echo fires. Brains only keeps the half-second shriek POSE,
## so the glow rides that window out to about the length of the sweep itself.
const ECHO_BURN := 2.2

var game: Node = null

## Replicated (snapshot "gf"): peer id -> {site: part kind}, e.g. {1: {"eye": "eye_hive"}}. A site
## missing from a player's entry is their own. It lasts the run, through death, and is cleared on a
## game over.
var _graft: Dictionary = {}

## Local, per peer: {site: how lit that graft is right now}.
var _lock: Dictionary = {}
var _shown: Dictionary = {}


func setup(g: Node) -> void:
	game = g


# =============================================================================== state

## Everything grafted into this player: {site: part kind}.
func grafts_of(peer_id: int) -> Dictionary:
	var d = _graft.get(peer_id)
	return d if d is Dictionary else {}


## The part kind grafted into this player at `site`, or "".
func graft_of(peer_id: int, site := "eye") -> String:
	return String(grafts_of(peer_id).get(site, ""))


func has_graft(p) -> bool:
	return p != null and not grafts_of(int(p.peer_id)).is_empty()


## Host: game over. Grafts are lost, like the abilities they teach.
func on_reset() -> void:
	_graft.clear()
	_lock.clear()


func net_state() -> Dictionary:
	var out := {}
	for peer in _graft.keys():
		out[peer] = (_graft[peer] as Dictionary).duplicate()
	return out


func apply_net_state(s: Dictionary) -> void:
	if game != null and game.is_host():
		return
	_graft = s.duplicate(true)


# =============================================================================== the offer and its refusals

## The vat standing on the table `p` is strapped to, or null.
func vat_for(p) -> Node:
	if p == null or game == null or game.vats == null:
		return null
	var ti := int(game.player_table.get("index", -1))
	if ti >= 0:
		return game.vats.vat_on_table(ti)
	# A level with a player table of its own has no table index: go by where the table is.
	var i: int = game.vats.nearest_place(game.player_table_top())
	return game.vats.vat_at(game.vats.places[i].position as Vector3) if i >= 0 else null


## The graft site the vat on `p`'s table would operate on ("eye", "throat"), or "".
func site_for(p) -> String:
	var vat := vat_for(p)
	if vat == null:
		return ""
	var d := Eyes.unpack(String(vat.x))
	return "" if d.is_empty() else Eyes.site_of(String(d.kind))


## The tool the first step of a site's graft wants.
static func first_tool(site: String) -> String:
	var steps: Array = Procedures.steps(String(SITE_AILMENT.get(site, "eye_graft")))
	return String(steps[0].get("item", "scalpel")) if not steps.is_empty() else "scalpel"


## What the table offers `q` while a surgeon lies strapped to it: "Operate: ..." , a "!reason", or ""
## when no graft is on offer at all. A pure function of replicated state, so every machine says the
## same thing. The refusals are the ones docs/GRAFTING.md and docs/GRAFTING_TRACHEA.md list: no vat
## on the table, the part is spoiled, they already have one, nobody strapped down.
func table_prompt(q) -> String:
	if game == null or q == null or not q.alive or q.downed or q.on_table:
		return ""
	var p = game.someone_on_table()
	if p == null or not p.strapped():
		return ""
	if q == p:
		return "!You cannot operate on yourself."
	var vat := vat_for(p)
	if vat == null:
		return "!No vat on the table."
	var d := Eyes.unpack(String(vat.x))
	if d.is_empty():
		return "!The vat on the table is empty."
	var kind := String(d.kind)
	var owner := String(d.owner)
	var site := Eyes.site_of(kind)
	if site == "":
		return "!That is not a body part anyone can graft."
	var have := graft_of(int(p.peer_id), site)
	if Eyes.is_spoiled_factor(Eyes.spoil_factor(float(d.age))):
		return "!%s is spoiled." % Eyes.label(kind, owner)
	if kind == String(Eyes.MONSTER_PART.get(site, "")):
		if have != "":
			return "!%s already has one." % p.player_name
	elif have == "":
		return "!%s has %s." % [p.player_name, Eyes.SITE_NORMAL.get(site, "their own")]
	var tool := first_tool(site)
	var held := String(q.selected_stack().get("kind", "")) if q.has_method("selected_stack") else ""
	if held != tool:
		return "!Hold the %s to start the graft." % Items.display_name(tool).to_lower()
	return "Operate: graft %s into %s" % [Eyes.label(kind, owner), p.player_name]


## What a free table says to someone holding a graft tool while nobody lies on it.
func empty_table_prompt(q, table_index: int) -> String:
	if game == null or q == null or game.vats == null:
		return ""
	var kind := String(q.selected_stack().get("kind", "")) if q.has_method("selected_stack") else ""
	if not ["scalpel", "eye_spoon", "forceps", "suture_kit"].has(kind):
		return ""
	var vat: Node = game.vats.vat_on_table(table_index)
	if vat == null or String(vat.x) == "":
		return ""
	return "!Nobody is strapped to this table."


# =============================================================================== the case (host)

## Host: `q` began a graft on the strapped surgeon. Builds the case for player_surgery.
func make_case(q) -> Dictionary:
	if game == null or not game.is_host():
		return {}
	if not table_prompt(q).begins_with("Operate"):
		return {}
	var p = game.someone_on_table()
	var vat := vat_for(p)
	var d := Eyes.unpack(String(vat.x))
	var in_kind := String(d.kind)
	var site := Eyes.site_of(in_kind)
	var have := graft_of(int(p.peer_id), site)
	# What comes out is whatever is in the socket now: the monster's part they were given, or theirs.
	var out_kind := have if have != "" else String(Eyes.OWN_PART.get(site, "eye_surgeon"))
	var out_owner := "" if have != "" else String(p.player_name)
	return {
		"patient_id": "player", "player_id": int(p.peer_id),
		"ailment_id": String(SITE_AILMENT.get(site, "eye_graft")),
		"step_index": 0, "table": int(game.player_table.get("index", -1)),
		"site": site,
		"in_kind": in_kind, "in_owner": String(d.owner), "in_value": int(d.value),
		"out_kind": out_kind, "out_owner": out_owner,
		"flags": {"sedation": 1.0, "no_fail": true, "eye_kind": out_kind, "eye_kind_in": in_kind,
			"eye_radius": EYE_RADIUS, "part_site": site},
	}


## Host: a graft step finished. The seat is the moment the swap happens: the forceps have just taken
## the new part out of the vat and put it in, so the old one goes into the vat they emptied.
func on_step(case: Dictionary, result: Dictionary) -> void:
	if game == null or not game.is_host() or case.is_empty():
		return
	if not bool(result.get("eye_seated", false)) and not bool(result.get("part_seated", false)):
		return
	var p = game.players.get(int(case.get("player_id", 0)))
	var vat := vat_for(p)
	if vat == null or not is_instance_valid(vat):
		return
	var out_kind := String(case.get("out_kind", "eye_surgeon"))
	var out_owner := String(case.get("out_owner", ""))
	vat.x = Eyes.pack(out_kind, out_owner, 0.0, _value_of(out_kind))
	game._sound("items_glass", vat.global_position)
	game.say("%s is in the vat now." % Eyes.label(out_kind, out_owner), 3.0)


## Host: the last stitch went in. The graft takes.
func finish(case: Dictionary) -> void:
	if game == null or not game.is_host() or case.is_empty():
		return
	var p = game.players.get(int(case.get("player_id", 0)))
	if p == null or not is_instance_valid(p):
		return
	var in_kind := String(case.get("in_kind", ""))
	var site := String(case.get("site", Eyes.site_of(in_kind)))
	apply(int(p.peer_id), site, in_kind if PART_ABILITY.has(in_kind) else "")
	var label := Eyes.label(in_kind, String(case.get("in_owner", "")))
	game.say("%s is stitched in. %s can get up." % [label, p.player_name], 4.0)


## Host: set (or clear) `peer_id`'s graft at `site` and the ability that comes with it.
## `kind` "" puts their own part back. Call with two arguments (peer, kind) and the site is worked
## out from the kind, so the old two-argument callers still read right.
func apply(peer_id: int, site_or_kind: String, kind := "?") -> void:
	if game == null or not game.is_host():
		return
	var site := site_or_kind
	if kind == "?":
		kind = site_or_kind
		site = Eyes.site_of(kind)
		if site == "":
			site = "eye"
	var had := graft_of(peer_id, site)
	var mine: Dictionary = grafts_of(peer_id).duplicate()
	if kind == "":
		mine.erase(site)
	else:
		mine[site] = kind
	if mine.is_empty():
		_graft.erase(peer_id)
	else:
		_graft[peer_id] = mine
	var p = game.players.get(peer_id)
	# The ability the part teaches. It comes with the graft and goes with it.
	if had != "" and had != kind and PART_ABILITY.has(had):
		var gone: String = String(PART_ABILITY[had])
		game.brains.clear_ability(peer_id, gone)
		if p != null:
			game.tell(p, _lost_line(site), 4.0)
	if kind != "" and kind != had and PART_ABILITY.has(kind):
		var got: String = String(PART_ABILITY[kind])
		game.brains.set_level(peer_id, got, 1)
		# The database's third tier: a part was extracted or grafted (docs/GRAFTING_TRACHEA.md).
		var path: String = String(game.brains.ABILITY_ID_TO_PATH.get(got, ""))
		if path != "":
			game.mark_db(path, "harvested", p)
		if p != null:
			game.tell(p, _gained_line(site), 5.0)


static func _gained_line(site: String) -> String:
	if site == "throat":
		return "The windpipe knits in and starts to hum. Echo 1."
	return "The Hive eye settles in and starts to see. Hive Eyes 1."


static func _lost_line(site: String) -> String:
	if site == "throat":
		return "Your own windpipe again. The humming stops, and Echo with it."
	return "The socket is your own again. Hive Eyes is gone."


func _value_of(kind: String) -> int:
	var e: Dictionary = LootTable.LOOT.get(kind, {})
	var v = e.get("value", [40, 40])
	return int(v[0]) if v is Array and not (v as Array).is_empty() else 40


# =============================================================================== the look (every machine)

## Is this player's graft at `site` lit right now? The eye burns while they are in Hive Eyes; the
## throat burns while Echo is firing. Both come from replicated state, so every machine agrees.
func _wants_lock(p, site: String) -> bool:
	if site == "throat":
		# `_echo_pose_until` is set to world_time + 0.5 on EVERY machine from the reliable br_echo
		# event, so working back from it gives every machine the same window.
		var posed := float(game.brains._echo_pose_until.get(int(p.peer_id), -999.0))
		return float(game.world_time) < posed - 0.5 + ECHO_BURN
	return bool(p.get("hive_view"))


func _physics_process(delta: float) -> void:
	if game == null or game.get("players") == null:
		return
	for p in game.players.values():
		if p == null or not is_instance_valid(p) or p.body_visual == null:
			continue
		var peer := int(p.peer_id)
		var mine := grafts_of(peer)
		var human := _human_of(p)
		if human == null:
			# No body to hang anything on yet: a strapped surgeon's own body is hidden while the
			# lying stand-in has the table (Player.stand_in), and it comes back when they get up.
			# Leave `_shown` alone so the graft goes on the moment there is something to put it on.
			continue
		var shown: Dictionary = _shown.get(peer, {})
		var locks: Dictionary = _lock.get(peer, {})
		for site in Eyes.SITES:
			var kind := String(mine.get(site, ""))
			# The part swap on the body: third person, other players' screens and the mirrors. The
			# body's human model is thrown away and rebuilt whenever what it has to show changes
			# (getting up off the table, the mirror's own body, a new stand-in), and the graft goes
			# with it, so what is remembered carries the model instance: a rebuilt body gets its
			# graft put back on.
			var key := "%s|%d" % [kind, human.get_instance_id()]
			var on_body: bool = (ThroatScript.node_on(human) != null) if site == "throat" 					else (PartScript.node_on(human) != null)
			if String(shown.get(site, "")) != key or (kind != "" and not on_body):
				var ok := true
				if site == "throat":
					if kind == "":
						ThroatScript.detach(human)
					else:
						ok = ThroatScript.attach(human, kind) != null
				elif kind == "":
					PartScript.detach(human)
				else:
					ok = PartScript.attach(human, kind, BODY_EYE_RADIUS) != null
				# Only remember it once it actually went on: a model that is still building has no
				# skeleton yet, and the next frame should try again.
				if ok:
					shown[site] = key
			if kind == "":
				locks.erase(site)
				continue
			var want := 1.0 if _wants_lock(p, site) else 0.0
			var v := move_toward(float(locks.get(site, 0.0)), want, delta * LOCK_RATE)
			locks[site] = v
			if site == "throat":
				ThroatScript.set_lock(ThroatScript.node_on(human), v)
			else:
				# The eye never goes fully dark: LOCK_IDLE is its resting ember. The first-person
				# tint keeps reading the raw value (local_lock), so an eye you are not using still
				# looks quiet from inside.
				PartScript.set_lock(PartScript.node_on(human), maxf(v, LOCK_IDLE))
		_shown[peer] = shown
		_lock[peer] = locks


func _human_of(p) -> Node:
	if p == null or p.body_visual == null or not is_instance_valid(p.body_visual):
		return null
	for c in p.body_visual.get_children():
		if c is Node3D and (c as Node3D).has_meta("human_variant"):
			return c
	return null


## Every machine: how lit the graft at `site` of whoever you are looking out of is, for the
## first-person tint (graft_view.gd). -1 when they have no graft there. Driving Dr. Botsworth, it is
## his body you are in, so your own grafts do not tint his view.
func local_lock(site := "eye") -> float:
	var me = game.driving_player() if game != null else null
	if me == null or graft_of(int(me.peer_id), site) == "":
		return -1.0
	return float((_lock.get(int(me.peer_id), {}) as Dictionary).get(site, 0.0))
