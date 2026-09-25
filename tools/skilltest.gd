extends Node
## SKILL TREE: headless checks (docs/SKILL_TREE.md).
##
##   godot --headless --fixed-fps 60 --path . tools/skilltest.tscn
##
## The table (SkillTree.validate), the unlock rules, the save file round trip (on a scratch file of
## its own, never the real user://skills.save), the screen's layout (every node on the screen, clear
## of the panels and of each other), and then a solo shift: the vein machine is built in Personnel,
## E at its plate claims the reader and opens the view, the screen scans and grows, a click picks a
## node and INFUSE buys it, the reader is freed on the way out, and clocking out of a shift pays a
## point. Exits 0 when every check passes.

const ScreenScript := preload("res://scripts/skills/vein_screen.gd")
const SCRATCH := "user://skilltest_skills.save"
const SEED := 4242

var main: Node3D
var game: Game
var me: Player
var fails := 0
var checks := 0


func _ready() -> void:
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	checks += 1
	if ok:
		print("[skill] ok    ", what)
	else:
		fails += 1
		print("[skill] FAIL  ", what)


## Game seconds (with --fixed-fps 60 the game runs far faster than the wall clock).
func _seconds(s: float) -> void:
	await _frames(int(ceil(s * 60.0)))


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _run() -> void:
	get_tree().create_timer(300.0).timeout.connect(func():
		print("[skill] FAIL  timed out")
		get_tree().quit(1))
	# The two halves of a real restart (two processes, one after the other):
	#   -- --restart=write   unlock a skill in a scratch file and quit
	#   -- --restart=read    a new process reads it back, then deletes it
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--restart="):
			_restart(arg.trim_prefix("--restart="))
			print("[skill] %d checks, %d failed" % [checks, fails])
			print("result=%s" % ("PASS" if fails == 0 else "FAIL"))
			get_tree().quit(0 if fails == 0 else 1)
			return
	_rules()
	_persistence()
	_layout()
	await _in_game()
	if FileAccess.file_exists(SCRATCH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SCRATCH))
	print("[skill] %d checks, %d failed" % [checks, fails])
	print("result=%s" % ("PASS" if fails == 0 else "FAIL"))
	get_tree().quit(0 if fails == 0 else 1)


const RESTART := "user://skilltest_restart.save"

func _restart(half: String) -> void:
	Skills.use_path(RESTART)
	if half == "write":
		Skills.wipe()
		Skills.grant(4)
		_check(Skills.unlock("pharm_measured") == "" and Skills.unlock("pharm_pill_counter") == "", "bought two skills")
		_check(Skills.points == 2, "two points left")
	else:
		_check(Skills.local_has("pharm_measured") and Skills.local_has("pharm_pill_counter"), "after a restart the skills are still there")
		_check(Skills.points == 2 and Skills.earned == 4, "and so are the points (%d left of %d)" % [Skills.points, Skills.earned])
		DirAccess.remove_absolute(ProjectSettings.globalize_path(RESTART))


func _rules() -> void:
	var problems := SkillTree.validate()
	_check(problems.is_empty(), "the skill table is sane %s" % str(problems))
	_check(SkillTree.TREES.size() == 5, "five trees")
	for t in SkillTree.TREES:
		var n := SkillTree.skills_in(String(t.id)).size()
		_check(n >= 4 and n <= 6, "%s has 4-6 skills (%d)" % [t.id, n])
	var u := {}
	_check(SkillTree.unlock_problem(u, 5, "surg_steady") == "", "a root skill can be bought with points")
	_check(SkillTree.unlock_problem(u, 0, "surg_steady") != "", "not without them")
	_check(SkillTree.unlock_problem(u, 9, "surg_quick_stitch").begins_with("Needs Steady Hand"), "a fork needs the skill before it on the vein")
	u["surg_steady"] = true
	u["surg_quick_stitch"] = true
	u["surg_clean_cut"] = true
	_check(SkillTree.unlock_problem(u, 9, "surg_chief").begins_with("Needs Bone Setter"), "a meeting of two veins needs both")
	_check(SkillTree.unlock_problem(u, 9, "surg_steady") != "", "an unlocked skill can't be bought twice")


func _persistence() -> void:
	if FileAccess.file_exists(SCRATCH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SCRATCH))
	Skills.use_path(SCRATCH)
	_check(Skills.points == 0 and Skills.unlocked.is_empty(), "a missing file is a fresh surgeon")
	Skills.grant(3)
	_check(Skills.unlock("anat_tissue_match") == "", "unlock spends points")
	_check(Skills.points == 2 and Skills.local_has("anat_tissue_match"), "points 3 -> %d, skill held" % Skills.points)
	_check(Skills.has_skill(Net.my_id(), "anat_tissue_match"), "has_skill answers for this machine's peer")
	_check(Skills.unlock("anat_chimera") != "" and Skills.points == 2, "a skill out of reach costs nothing")
	# "Restart": forget the in-memory state and read the file back.
	Skills.points = 0
	Skills.unlocked.clear()
	Skills.use_path(SCRATCH)
	_check(Skills.points == 2 and Skills.local_has("anat_tissue_match") and Skills.earned == 3,
			"the save file brings points, skills and points earned back (%d, %s, %d)" % [Skills.points, str(Skills.unlocked.keys()), Skills.earned])
	_check((Net.skills_for(Net.my_id()).get("u", []) as Array).has("anat_tissue_match"), "and publishes them through Net")
	Skills.wipe()
	_check(Skills.points == 0 and Skills.unlocked.is_empty(), "wipe forgets it all")


func _layout() -> void:
	var s: Control = ScreenScript.new()
	add_child(s)
	var pos: Dictionary = {}
	for id in SkillTree.SKILLS.keys():
		pos[id] = s.node_position(String(id))
	var inside := true
	var clear := true
	for id in pos.keys():
		var p: Vector2 = pos[id]
		if not ScreenScript.FIELD.grow(-10).has_point(p):
			inside = false
			print("[skill]       %s at %s is off the field" % [id, p])
		for r in [ScreenScript.PANEL_L, ScreenScript.PANEL_R]:
			if (r as Rect2).grow(ScreenScript.NODE_R + 4).has_point(p):
				clear = false
				print("[skill]       %s at %s is under a panel" % [id, p])
	_check(inside, "every node is on the screen's field")
	_check(clear, "no node under a panel")
	var worst := 1e9
	var pair := ""
	var ids := pos.keys()
	for i in ids.size():
		for j in range(i + 1, ids.size()):
			var d := (pos[ids[i]] as Vector2).distance_to(pos[ids[j]])
			if d < worst:
				worst = d
				pair = "%s / %s" % [ids[i], ids[j]]
	_check(worst > ScreenScript.NODE_R * 2.0 + 30.0, "nodes keep apart (closest %.0f px, %s)" % [worst, pair])
	s.begin(1, "Test", {"u": [], "p": 0, "f": ""})
	s.t = 0.0
	_check(not s.grown(), "the tree is not grown when the palm goes down")
	s.t = 1.0
	_check(s.node_at(pos["surg_steady"]) == "", "nothing to click mid-scan")
	s.t = 6.0
	_check(s.grown(), "grown after a few seconds")
	_check(s.node_at(pos["surg_steady"] + Vector2(5, 5)) == "surg_steady", "a node is clicked where it is drawn")
	s.queue_free()


func _in_game() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	game = main.game
	if main.launching:
		await main.launched
	main.menu.hide_menu()
	Net.start_solo("Tester")
	game.start_session(SEED)
	while game.get_parent().has_node("WarmupCover"):
		await get_tree().process_frame
	while game.level == null or game.local_player() == null:
		await get_tree().process_frame
	await _seconds(1.0)
	me = game.local_player()
	me.bot_active = true
	me.bot_invulnerable = true
	var vm: Node = game.level.find_child("VeinMachine", true, false)
	_check(vm != null, "the vein machine is built in Personnel")
	if vm == null:
		return
	Skills.use_path(SCRATCH)
	Skills.wipe()
	Skills.grant(2)
	var aim: Node = game.find_interactable("vein_scanner")
	_check(aim != null and String(aim.interact_prompt(me)).begins_with("E:"), "its plate is something to press E on")
	# Somebody else at the reader: the prompt says so and E does nothing.
	Net.station_users["veins"] = 99
	_check(String(aim.interact_prompt(me)).begins_with("!"), "a reader in use refuses you ('%s')" % aim.interact_prompt(me))
	Net.station_users.erase("veins")
	Net.station_users_changed.emit()
	# E at the plate (what _poll_open does on the key press).
	vm._pending = me
	Net.claim_station("veins")
	await _frames(2)
	_check(vm.is_open() and game.vein_open(), "E opens the reader")
	_check(Net.station_user("veins") == me.peer_id, "and claims it")
	_check(game.vein_camera() != null, "with its own camera")
	_check(vm.screen.user == me.peer_id, "the screen reads this surgeon")
	await _seconds(1.0)
	_check(not vm.screen.grown(), "still scanning at 1 s")
	await _seconds(4.0)
	_check(vm.screen.grown(), "the tree has grown by 5 s")
	vm.click(vm.screen.node_position("surg_steady"))
	await _frames(2)
	_check(Skills.focus == "surg_steady" and vm.screen.focus == "surg_steady", "a click picks a node (and the screen shows it)")
	var br: Rect2 = vm.screen.button_rect()
	_check(br.has_area(), "a node you can afford offers INFUSE")
	vm.click(br.get_center())
	await _frames(2)
	_check(Skills.local_has("surg_steady") and Skills.points == 1, "INFUSE buys it (points %d)" % Skills.points)
	_check(vm.screen.unlocked.has("surg_steady"), "and the screen fills it with blood")
	vm.click(vm.screen.node_position("surg_chief"))
	await _frames(2)
	_check(not vm.screen.button_rect().has_area(), "a node out of reach offers no button")
	game.vein_local_exit()
	await _frames(2)
	_check(not vm.is_open() and Net.station_user("veins") == 0, "stepping away frees the reader")
	# Clocking out pays a point.
	var before := Skills.points
	game.phase = Game.Phase.SHIFT
	game._set_phase(Game.Phase.WON)
	_check(Skills.points == before + 1, "clocking out of a shift pays a point (%d -> %d)" % [before, Skills.points])
	Skills.wipe()
