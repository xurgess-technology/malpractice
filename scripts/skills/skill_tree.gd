class_name SkillTree
extends RefCounted
## SKILL TREE: the data. Five trees, one per main vein of the palm the vein machine in Personnel
## reads (scripts/personnel/vein_machine.gd draws it; docs/SKILL_TREE.md is the how-to).
##
## Everything here is PLACEHOLDER: names, descriptions and costs are there so the machine has
## something to draw and the unlock flow has something to unlock. No skill does anything yet; an
## effect hooks in by asking `Skills.has_skill(peer_id, "surg_steady")` (scripts/skills/skills.gd)
## wherever the thing it changes is decided.
##
## Renaming a tree or a skill: change `name` here. Ids are what the save files keep, so an id only
## changes with a migration in Skills._load.

## The trees in finger order, thumb first (the screen draws the hand with the thumb on the left).
## `name` is what the screen prints at the tip of the vein, `blurb` its one-line subtitle.
const TREES := [
	{"id": "survival", "name": "SURVIVAL", "blurb": "monsters, stealth, staying alive"},
	{"id": "surgery", "name": "SURGERY", "blurb": "the table: cutting, closing, steady hands"},
	{"id": "anatomy", "name": "ANATOMY", "blurb": "grafting: what you take out and put in"},
	{"id": "pharmacology", "name": "PHARMACOLOGY", "blurb": "sedatives, doses, the pharmacy"},
	{"id": "logistics", "name": "LOGISTICS", "blurb": "money, supplies, what you can carry"},
]

## Every skill: id -> {tree, name, desc, cost, requires (all of them, ids in the same tree), at}.
## `at` places the node on its tree's vein: x is how far out along it (0 at the fingertip, 1 at the
## edge of the screen), y how far off to the side (-1 left of the vein, +1 right, looking out along
## it). A skill with no requirements hangs straight off the fingertip.
const SKILLS := {
	# ---- SURVIVAL (thumb) ----------------------------------------------------------------------
	"surv_light_step": {"tree": "survival", "name": "Light Step", "cost": 1, "requires": [],
			"at": Vector2(0.14, 0.0), "desc": "Placeholder. Your footsteps carry a little less far."},
	"surv_hold_breath": {"tree": "survival", "name": "Hold Breath", "cost": 1, "requires": ["surv_light_step"],
			"at": Vector2(0.3, 0.8), "desc": "Placeholder. Crouched and still, you make no sound at all."},
	"surv_second_wind": {"tree": "survival", "name": "Second Wind", "cost": 2, "requires": ["surv_light_step"],
			"at": Vector2(0.44, 0.1), "desc": "Placeholder. Sprint recovers faster once you stop running."},
	"surv_blind_spot": {"tree": "survival", "name": "Blind Spot", "cost": 2, "requires": ["surv_second_wind"],
			"at": Vector2(0.68, 0.9), "desc": "Placeholder. A Hive takes longer to notice you at the edge of its sight."},
	"surv_play_dead": {"tree": "survival", "name": "Play Dead", "cost": 2, "requires": ["surv_second_wind"],
			"at": Vector2(0.74, -0.55), "desc": "Placeholder. Downed, you are ignored by anything not already on you."},
	"surv_night_shift": {"tree": "survival", "name": "Night Shift", "cost": 3, "requires": ["surv_play_dead"],
			"at": Vector2(0.96, -0.1), "desc": "Placeholder. The dark wards stop feeling quite so dark."},

	# ---- SURGERY (index) -----------------------------------------------------------------------
	"surg_steady": {"tree": "surgery", "name": "Steady Hand", "cost": 1, "requires": [],
			"at": Vector2(0.15, 0.0), "desc": "Placeholder. Less hand shake while you operate."},
	"surg_quick_stitch": {"tree": "surgery", "name": "Quick Stitch", "cost": 1, "requires": ["surg_steady"],
			"at": Vector2(0.4, 0.0), "desc": "Placeholder. Suturing goes faster."},
	"surg_clean_cut": {"tree": "surgery", "name": "Clean Cut", "cost": 2, "requires": ["surg_quick_stitch"],
			"at": Vector2(0.62, -0.8), "desc": "Placeholder. A slip of the scalpel costs the patient less."},
	"surg_bone_setter": {"tree": "surgery", "name": "Bone Setter", "cost": 2, "requires": ["surg_quick_stitch"],
			"at": Vector2(0.68, 0.7), "desc": "Placeholder. The bone saw bites cleaner and snaps less."},
	"surg_two_hands": {"tree": "surgery", "name": "Two Hands", "cost": 2, "requires": ["surg_steady"],
			"at": Vector2(0.3, 0.95), "desc": "Placeholder. A teammate assisting at your table actually helps."},
	"surg_chief": {"tree": "surgery", "name": "Chief Surgeon", "cost": 3, "requires": ["surg_clean_cut", "surg_bone_setter"],
			"at": Vector2(0.95, 0.0), "desc": "Placeholder. Where both veins meet: every step forgives one mistake."},

	# ---- ANATOMY (middle) ----------------------------------------------------------------------
	"anat_tissue_match": {"tree": "anatomy", "name": "Tissue Match", "cost": 1, "requires": [],
			"at": Vector2(0.16, 0.0), "desc": "Placeholder. Grafts take more readily."},
	"anat_cold_storage": {"tree": "anatomy", "name": "Cold Storage", "cost": 1, "requires": ["anat_tissue_match"],
			"at": Vector2(0.34, 0.7), "desc": "Placeholder. Harvested parts spoil more slowly out of a vat."},
	"anat_tolerance": {"tree": "anatomy", "name": "Graft Tolerance", "cost": 2, "requires": ["anat_tissue_match"],
			"at": Vector2(0.45, -0.25), "desc": "Placeholder. Grafted parts wear on you less."},
	"anat_fresh_eyes": {"tree": "anatomy", "name": "Fresh Eyes", "cost": 2, "requires": ["anat_tolerance"],
			"at": Vector2(0.72, -1.0), "desc": "Placeholder. A grafted Hive eye starts one level higher."},
	"anat_spare_parts": {"tree": "anatomy", "name": "Spare Parts", "cost": 2, "requires": ["anat_tolerance"],
			"at": Vector2(0.74, 0.55), "desc": "Placeholder. One more place on you to take a graft."},
	"anat_chimera": {"tree": "anatomy", "name": "Chimera", "cost": 3, "requires": ["anat_spare_parts"],
			"at": Vector2(0.97, 0.15), "desc": "Placeholder. Two grafts from the same monster stack."},

	# ---- PHARMACOLOGY (ring) -------------------------------------------------------------------
	"pharm_measured": {"tree": "pharmacology", "name": "Measured Dose", "cost": 1, "requires": [],
			"at": Vector2(0.15, 0.0), "desc": "Placeholder. A wider sweet spot when you dose anesthetic."},
	"pharm_deep_sleep": {"tree": "pharmacology", "name": "Deep Sedation", "cost": 1, "requires": ["pharm_measured"],
			"at": Vector2(0.46, -0.15), "desc": "Placeholder. Sedated monsters stay under longer."},
	"pharm_pill_counter": {"tree": "pharmacology", "name": "Pill Counter", "cost": 1, "requires": ["pharm_measured"],
			"at": Vector2(0.3, 0.95), "desc": "Placeholder. The pharmacy sends an extra pill now and then."},
	"pharm_tolerance": {"tree": "pharmacology", "name": "Tolerance", "cost": 2, "requires": ["pharm_deep_sleep"],
			"at": Vector2(0.7, 0.9), "desc": "Placeholder. Each re-dose loses less than the last."},
	"pharm_cocktail": {"tree": "pharmacology", "name": "Cocktail", "cost": 2, "requires": ["pharm_deep_sleep"],
			"at": Vector2(0.74, -0.7), "desc": "Placeholder. One vial, two effects."},
	"pharm_pharmacist": {"tree": "pharmacology", "name": "Pharmacist", "cost": 3, "requires": ["pharm_cocktail"],
			"at": Vector2(0.96, 0.05), "desc": "Placeholder. Mix your own from what the pharmacy sells."},

	# ---- LOGISTICS (pinky) ---------------------------------------------------------------------
	"log_deep_pockets": {"tree": "logistics", "name": "Deep Pockets", "cost": 1, "requires": [],
			"at": Vector2(0.14, 0.0), "desc": "Placeholder. Stacks hold one more."},
	"log_haggler": {"tree": "logistics", "name": "Haggler", "cost": 1, "requires": ["log_deep_pockets"],
			"at": Vector2(0.4, -0.1), "desc": "Placeholder. The pharmacy charges you a little less."},
	"log_fax_priority": {"tree": "logistics", "name": "Fax Priority", "cost": 2, "requires": ["log_haggler"],
			"at": Vector2(0.64, -0.9), "desc": "Placeholder. Orders arrive faster."},
	"log_scrap_value": {"tree": "logistics", "name": "Scrap Value", "cost": 2, "requires": ["log_haggler"],
			"at": Vector2(0.62, 0.7), "desc": "Placeholder. The furnace pays more for what you burn."},
	"log_pack_mule": {"tree": "logistics", "name": "Pack Mule", "cost": 2, "requires": ["log_scrap_value"],
			"at": Vector2(0.84, 0.95), "desc": "Placeholder. Carrying a body or a monster slows you less."},
	"log_department_head": {"tree": "logistics", "name": "Department Head", "cost": 3, "requires": ["log_fax_priority", "log_scrap_value"],
			"at": Vector2(0.96, -0.2), "desc": "Placeholder. Where both veins meet: the whole team earns more per shift."},
}


static func tree_ids() -> PackedStringArray:
	var out := PackedStringArray()
	for t in TREES:
		out.append(String(t.id))
	return out


static func tree_index(tree_id: String) -> int:
	for i in TREES.size():
		if String(TREES[i].id) == tree_id:
			return i
	return -1


static func tree_name(tree_id: String) -> String:
	var i := tree_index(tree_id)
	return String(TREES[i].name) if i >= 0 else tree_id


static func exists(id: String) -> bool:
	return SKILLS.has(id)


static func skill(id: String) -> Dictionary:
	return SKILLS.get(id, {})


## A tree's skills, in table order.
static func skills_in(tree_id: String) -> PackedStringArray:
	var out := PackedStringArray()
	for id in SKILLS.keys():
		if String(SKILLS[id].tree) == tree_id:
			out.append(String(id))
	return out


static func cost(id: String) -> int:
	return int(skill(id).get("cost", 0))


static func requires(id: String) -> Array:
	return skill(id).get("requires", [])


## How many steps out from the fingertip (1 for a root skill).
static func depth(id: String) -> int:
	var best := 0
	for r in requires(id):
		best = maxi(best, depth(String(r)))
	return best + 1


## Every requirement is unlocked.
static func prereqs_met(unlocked: Dictionary, id: String) -> bool:
	for r in requires(id):
		if not unlocked.has(String(r)):
			return false
	return true


## "" when `id` can be bought now, else why not (the screen prints it).
static func unlock_problem(unlocked: Dictionary, points: int, id: String) -> String:
	if not exists(id):
		return "No such skill."
	if unlocked.has(id):
		return "Already in your blood."
	if not prereqs_met(unlocked, id):
		var names := PackedStringArray()
		for r in requires(id):
			if not unlocked.has(String(r)):
				names.append(String(skill(String(r)).name))
		return "Needs " + " and ".join(names) + "."
	if points < cost(id):
		return "Needs %d point%s, you have %d." % [cost(id), "" if cost(id) == 1 else "s", points]
	return ""


## The table is sane: every requirement exists and is in the same tree, no cycles (depth() would
## recurse forever), every tree has a root. Returns the problems, empty when fine.
static func validate() -> PackedStringArray:
	var out := PackedStringArray()
	var roots := {}
	for id in SKILLS.keys():
		var s: Dictionary = SKILLS[id]
		if tree_index(String(s.tree)) < 0:
			out.append("%s: unknown tree %s" % [id, s.tree])
		for key in ["name", "desc", "cost", "requires", "at"]:
			if not s.has(key):
				out.append("%s: no %s" % [id, key])
		for r in s.get("requires", []):
			if not SKILLS.has(String(r)):
				out.append("%s: requires unknown %s" % [id, r])
			elif String(SKILLS[String(r)].tree) != String(s.tree):
				out.append("%s: requires %s from another tree" % [id, r])
		if (s.get("requires", []) as Array).is_empty():
			roots[String(s.tree)] = true
	for t in TREES:
		if not roots.has(String(t.id)):
			out.append("tree %s has no root skill" % t.id)
	# Cycles: walk requirements with a depth limit.
	for id in SKILLS.keys():
		if _too_deep(String(id), 0):
			out.append("%s: requirement cycle" % id)
	return out


static func _too_deep(id: String, n: int) -> bool:
	if n > SKILLS.size():
		return true
	for r in requires(id):
		if SKILLS.has(String(r)) and _too_deep(String(r), n + 1):
			return true
	return false
