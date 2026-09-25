class_name Skills
extends RefCounted
## SKILL TREE: this machine's player's own skills, and the question every future effect asks.
##
##   Skills.has_skill(peer_id, id) -> bool   does that surgeon have it (any machine, any peer)
##   Skills.local_has(id) -> bool            does this machine's player have it
##   Skills.points                           unspent skill points (this machine's player)
##   Skills.unlocked                         {skill id: true}
##   Skills.unlock(id) -> String             spend points on it; "" on success, else why not
##   Skills.award_shift()                    +POINTS_PER_SHIFT: called by game.gd at clock-out
##   Skills.set_focus(id)                    the node picked on the vein machine's screen (so
##                                           everyone watching the screen sees the same pick)
##
## Where it lives: like the monster database (scripts/database/database_store.gd), every player
## keeps their own, on their own machine, in user://skills.save (plain JSON). It survives a wipe
## (game over) and a restart: skills are the surgeon's, not the run's. Everyone else learns it
## through Net (`Net.skills`, replicated like `Net.looks`), which is what has_skill() reads for a
## peer that is not us. Co-op trust: the host takes a client's word for its own skills.
##
## Points: POINTS_PER_SHIFT for every shift you clock out of (game.gd `_set_phase`, SHIFT -> WON, on
## every machine for its own player). Money is the team's and resets on a wipe, so it is the wrong
## currency for something that is yours for good.
##
## Machine runs (headless tests, tools/*.tscn: Settings.machine_run) read and write
## user://skills_machine.save instead, so a test never touches the real one; a test that wants a
## file of its own calls use_path().

const PATH := "user://skills.save"
const MACHINE_PATH := "user://skills_machine.save"
const POINTS_PER_SHIFT := 1
const VERSION := 1

static var path := ""
static var points := 0
static var unlocked: Dictionary = {}
## Points ever earned (spent or not), for the screen and for a future respec.
static var earned := 0
static var focus := ""
## Bumped on every change, so a screen can redraw when it moves.
static var revision := 0
static var _loaded := false


## Load once (Net._ready calls it, before anyone introduces themselves).
static func ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	path = MACHINE_PATH if bool(Settings.get("machine_run")) else PATH
	_load()
	_publish()


## Test seam: switch to another file and load it (a missing file is a fresh surgeon).
static func use_path(p: String) -> void:
	_loaded = true
	path = p
	_load()
	_publish()


static func has_skill(peer_id: int, id: String) -> bool:
	if peer_id == Net.my_id():
		return unlocked.has(id)
	var entry: Dictionary = Net.skills_for(peer_id)
	return (entry.get("u", []) as Array).has(id)


static func local_has(id: String) -> bool:
	return unlocked.has(id)


static func unlock(id: String) -> String:
	ensure_loaded()
	var problem := SkillTree.unlock_problem(unlocked, points, id)
	if problem != "":
		return problem
	points -= SkillTree.cost(id)
	unlocked[id] = true
	_changed()
	return ""


static func award_shift() -> void:
	grant(POINTS_PER_SHIFT)


static func grant(n: int) -> void:
	ensure_loaded()
	points += n
	earned += n
	_changed()


## At least `n` unspent points (the review setup's top-up; never takes any away).
static func top_up(n: int) -> void:
	ensure_loaded()
	if points < n:
		grant(n - points)


## Forget everything (dev panel, tests).
static func wipe() -> void:
	ensure_loaded()
	points = 0
	earned = 0
	unlocked.clear()
	focus = ""
	_changed()


static func set_focus(id: String) -> void:
	if id == focus:
		return
	focus = id
	revision += 1
	_publish()


static func _changed() -> void:
	revision += 1
	_save()
	_publish()


static func _publish() -> void:
	Net.set_my_skills({"u": unlocked.keys(), "p": points, "f": focus})


static func _load() -> void:
	points = 0
	earned = 0
	unlocked.clear()
	focus = ""
	revision += 1
	if path == "" or not FileAccess.file_exists(path):
		return
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if not (parsed is Dictionary):
		return
	var d: Dictionary = parsed
	points = maxi(0, int(d.get("points", 0)))
	earned = maxi(points, int(d.get("earned", points)))
	for id in d.get("unlocked", []):
		# A skill that has since been removed from the table is dropped (its points are not refunded;
		# nothing does anything yet, so there is nothing to be owed).
		if SkillTree.exists(String(id)):
			unlocked[String(id)] = true


static func _save() -> void:
	if path == "":
		return
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return
	var ids := PackedStringArray()
	for id in unlocked.keys():
		ids.append(String(id))
	ids.sort()
	f.store_string(JSON.stringify({"version": VERSION, "points": points, "earned": earned, "unlocked": Array(ids)}, "\t"))
	f.close()
