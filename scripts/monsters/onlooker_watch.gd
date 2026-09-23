extends Node
## POCKETS 2 phase 6: the one thing that decides whether a pocket has an Onlooker in it.
## `game.onlooker_watch`, a child of Game on every machine, doing something only on the host.
##
## The brain (scripts/monsters/onlooker_brain.gd) owns everything the monster DOES. This owns only
## when it exists at all, which is a separate decision for a separate reason: the roll has to happen
## once per pocket, before anybody is inside it, and a brain cannot roll for its own existence.
##
##   a pocket appears  ->  roll SPAWN_CHANCE once. Won: add one Onlooker, away, parked at the
##                         pocket's own spawn point. Lost: this pocket has none, and nothing
##                         re-rolls it however many times you walk back in.
##   the brain finishes ->  free it (out through a seam, or the pocket went with the shift)
##
## **Host-authoritative, and replicated for free.** It uses `game.spawn_pocket_monster`, so the
## Onlooker lands in the same `monsters` dictionary as everything else and rides the ordinary
## entity snapshots: a client is never told to roll anything and never decides anything. One node
## lives for the whole encounter and toggles `present` (see Monster.present) rather than being
## freed and re-added per hop, because an id handed out twice is exactly the 0.10.26 bug where a
## client keeps driving a stale node.
##
## Never in the hospital proper: the only call site that adds one is behind `pockets.active()`, and
## the brain's own placement re-tests `pockets.space_of` on every hop.

const MonsterScript := preload("res://scripts/monster.gd")

## The tuning knob the spec calls "spawn chance per pocket". Half of them: often enough that you
## check your sightlines every time you walk in, rare enough that the empty half still pays.
const SPAWN_CHANCE := 0.5
## Seconds after the pocket is built before the roll is even made, so nothing rolls mid-build.
const SETTLE := 1.0

## Dev and tools: "" rolls, "on" forces one into every pocket, "off" forces none.
## Set by --onlooker=on|off (tools) and the dev panel.
static var force := ""

var game: Node = null
var rng := RandomNumberGenerator.new()

## Instance id of the pocket root the last roll was made for; 0 when there is no pocket.
var _rolled_for: int = 0
## Won the roll and has not put one in yet. It goes false the moment one is added and never comes
## back for this pocket, so "one per pocket" survives anything else freeing the monster -- a test
## calling _clear_monsters, the dev panel, a kill. A second one only ever comes with a new pocket.
var _armed := false
## One has been added for this pocket (it may since have ended).
var _spawned := false
var _settle := 0.0
var _monster: Node = null

## Counters for the lab and the dev panel.
var rolls := 0
var wins := 0


func setup(g: Node) -> void:
	game = g


func _physics_process(delta: float) -> void:
	if game == null or not game.is_host():
		return
	var pk = game.get("pockets")
	if pk == null or not pk.active():
		_forget()
		return
	var root = pk.pocket.get("root")
	var id: int = root.get_instance_id() if root != null and is_instance_valid(root) else 0
	if id == 0:
		return
	if id != _rolled_for:
		_forget()
		_rolled_for = id
		_settle = SETTLE
		rng.seed = hash("onlooker|%d|%d|%s" % [int(game.get("seed_value")), int(game.get("shift")), String(pk.pocket.get("kind", ""))])
		rolls += 1
		_armed = rng.randf() < SPAWN_CHANCE if force == "" else force == "on"
		if _armed:
			wins += 1
	if _spawned:
		if _monster != null and not is_instance_valid(_monster):
			_monster = null   # something else freed it (a shift clear, the dev panel)
		elif _monster != null and bool(_monster.brain.finished):
			_drop()
		return
	if not _armed:
		return
	_settle -= delta
	if _settle > 0.0:
		return
	# It is added away (present false) and parked on the pocket's own spawn point, where nothing can
	# see it; the brain places it the first moment a player inside the pocket has room in their view.
	var at: Vector3 = pk.pocket.get("spawn", Vector3.ZERO)
	_monster = game.spawn_pocket_monster(MonsterScript.ONLOOKER, at)
	_armed = false
	_spawned = _monster != null   # a failed add is not retried in a loop


## The encounter ended. The pocket keeps its "already rolled" mark, so walking back in through the
## seam does not buy a second one.
func _drop() -> void:
	if _monster != null and is_instance_valid(_monster) and game.has_method("kill_monster"):
		game.kill_monster(_monster)
	_monster = null


func _forget() -> void:
	_rolled_for = 0
	_armed = false
	_spawned = false
	_monster = null   # the shift's _clear_monsters already freed it


## Tools and the dev panel: roll this pocket again from scratch. Not used by the game.
func rearm() -> void:
	_rolled_for = 0


## The live Onlooker, or null. For the dev panel and the tests.
func current() -> Node:
	return _monster if _monster != null and is_instance_valid(_monster) else null
