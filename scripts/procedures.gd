class_name Procedures
extends RefCounted
## Patients, ailments and the steps of each surgery, as data.
##
## Ailments never know what a patient looks like. They refer to named sites
## ("injection", "gunshot", "limb_cut") and each patient body provides a marker
## for every site. Adding a patient means placing those markers on a new model.

const SITES := ["injection", "gunshot", "limb_cut", "limb", "skull", "eye", "throat"]

const PATIENTS := {
	"bob": {
		"name": "Bob",
		"full_name": "Bob Kowalski, 52",
		"body": "bob",
		"weight_kg": 82.0,
		"limb_name": "left forearm",
		"limb_radius_m": 0.06,
		"blurbs": {
			"gunshot": "Says he was cleaning it. It was not loaded, apparently.",
			"amputation": "Scraped his arm on a fence in June. Did not get it looked at.",
		},
	},
	"seal": {
		"name": "The seal",
		"full_name": "Harbor seal, adult, unnamed",
		"body": "seal",
		"weight_kg": 130.0,
		"limb_name": "left front flipper",
		"limb_radius_m": 0.08,
		"blurbs": {
			"gunshot": "Found behind the loading dock. Nobody is admitting to anything.",
			"amputation": "Tangled in fishing line for weeks. The flipper has to go.",
		},
	},
	# GRAFTING: strapped monsters. `monster: true` keeps them out of roll(), the dev panel's patient
	# list and anything else that means a human patient (human_patients()). Their bodies are built by
	# scripts/dissection/monster_builder.gd, and the only ailment each takes is its own EXTRACTION
	# (scripts/dissection/dissection.gd): a Hive gives up an eyeball, a Sonographer its trachea.
	"hive": {
		"name": "The Hive",
		"full_name": "Hive, unregistered",
		"body": "hive",
		"monster": true,
		"weight_kg": 70.0,
		"limb_name": "",
		"limb_radius_m": 0.05,
		"blurbs": {
			"eye_extraction": "Came in through the front door and never left. Still in the gown.",
		},
	},
	"sonographer": {
		"name": "The Sonographer",
		"full_name": "Sonographer, unregistered",
		"body": "sonographer",
		"monster": true,
		"weight_kg": 88.0,
		"limb_name": "",
		"limb_radius_m": 0.05,
		"blurbs": {
			"trachea_extraction": "Walked out of the ultrasound room mid-scan. The wand is still fitted to its wrist.",
		},
	},
}

## Each step names the item it needs, how many it uses up (0 for reusable tools),
## which minigame plays it, and the patient site it happens at.
const AILMENTS := {
	"gunshot": {
		"name": "Gunshot wound",
		"code": "GW",
		"steps": [
			{"id": "sedate", "label": "Sedate the patient", "item": "anesthetic", "uses": 1, "game": "anesthetic", "site": "injection"},
			{"id": "extract", "label": "Remove the bullet", "item": "forceps", "uses": 0, "game": "forceps", "site": "gunshot"},
			{"id": "dress", "label": "Pack and dress the wound", "item": "gauze", "uses": 1, "game": "gauze", "variant": "pack", "site": "gunshot"},
		],
	},
	"amputation": {
		"name": "Amputation",
		"code": "AM",
		"steps": [
			{"id": "sedate", "label": "Sedate the patient", "item": "anesthetic", "uses": 1, "game": "anesthetic", "site": "injection"},
			{"id": "tourniquet", "label": "Apply the tourniquet", "item": "tourniquet", "uses": 0, "game": "tourniquet", "site": "limb"},
			{"id": "cut", "label": "Saw through the limb", "item": "bone_saw", "uses": 0, "game": "saw", "site": "limb_cut"},
			{"id": "dress", "label": "Dress the stump", "item": "gauze", "uses": 2, "game": "gauze", "variant": "stump", "site": "limb_cut"},
		],
	},
	# downed (sweep 2 wave 3): a downed teammate on the OR's player table. `player_only` keeps it
	# out of roll() and off the patient tables; the body is scripts/downed/player_body.gd.
	"stitches": {
		"name": "Laceration",
		"code": "LC",
		"player_only": true,
		"steps": [
			{"id": "stitch", "label": "Stitch the wound closed", "item": "suture_kit", "uses": 1, "game": "stitches", "site": "gash"},
		],
	},
	# GRAFTING chunk C (docs/GRAFTING.md): Eyeball Grafting on a surgeon who strapped themselves to a
	# table, with the vat holding the eye going in on that table's stand. `player_only` keeps it off
	# the patient tables' roll. No botches (the case sets `no_fail`), and no anesthetic: the patient
	# is awake, which is the joke. Steps 1-2 work on the eye coming out, 3-4 on the one going in.
	"eye_graft": {
		"name": "Eyeball Grafting",
		"code": "EG",
		"player_only": true,
		"steps": [
			{"id": "cut", "label": "Cut around the socket", "item": "scalpel", "uses": 0, "game": "eye", "variant": "cut", "site": "eye"},
			{"id": "scoop", "label": "Scoop the old eye out", "item": "eye_spoon", "uses": 0, "game": "eye", "variant": "scoop", "site": "eye"},
			{"id": "seat", "label": "Seat the new eye with forceps", "item": "forceps", "uses": 0, "game": "eye", "variant": "grab", "site": "eye"},
			{"id": "stitch", "label": "Stitch it in", "item": "suture_kit", "uses": 1, "game": "eye", "variant": "stitch", "site": "eye"},
		],
	},
	# GRAFTING part one (docs/GRAFTING.md): what a strapped Hive is for. `monster_only` keeps it out
	# of roll() and patient_ailments(). The three steps play the eye minigame's variants. Dissection
	# for a brain is gone with the brains (docs/GRAFTING_TRACHEA.md): taking a part out is the only
	# thing you do to a monster on a table now.
	"eye_extraction": {
		"name": "Eyeball Extraction",
		"code": "EX",
		"monster_only": true,
		"steps": [
			{"id": "cut", "label": "Cut around the eye", "item": "scalpel", "uses": 0, "game": "eye", "variant": "cut", "site": "eye"},
			{"id": "scoop", "label": "Scoop the eye out", "item": "eye_spoon", "uses": 0, "game": "eye", "variant": "scoop", "site": "eye"},
			{"id": "snip", "label": "Snip the optic nerve", "item": "scalpel", "uses": 0, "game": "eye", "variant": "snip", "site": "eye"},
			# 2026-09-19: and it goes straight into the specimen vat standing on the table, with the
			# forceps -- the seat step's game the other way round (scripts/grafting/eye_seat.gd).
			{"id": "vat", "label": "Put the eye in the vat", "item": "forceps", "uses": 0, "game": "eye", "variant": "place", "site": "eye"},
		],
	},
	# GRAFTING part two (docs/GRAFTING_TRACHEA.md): Trachea Extraction on a strapped Sonographer, the
	# eye extraction's shape on a throat. The windpipe glows through the skin, so the first cut is
	# already marked for you. The SECOND cut, the one that frees the pipe top and bottom, makes it
	# shriek -- a real noise event that can pull monsters to the OR (Dissection._host_tick's `free`
	# step). It ends in the specimen vat standing on the table, carried there with the forceps.
	"trachea_extraction": {
		"name": "Trachea Extraction",
		"code": "TX",
		"monster_only": true,
		"steps": [
			{"id": "open", "label": "Open the throat along the glowing line", "item": "scalpel", "uses": 0, "game": "eye", "variant": "cut", "site": "throat"},
			{"id": "free", "label": "Cut the windpipe free", "item": "scalpel", "uses": 0, "game": "eye", "variant": "snip", "site": "throat"},
			{"id": "vat", "label": "Put the trachea in the vat", "item": "forceps", "uses": 0, "game": "eye", "variant": "place", "site": "throat"},
		],
	},
	# GRAFTING part two: Trachea Grafting on a surgeon who strapped themselves to a table, with the
	# vat holding the trachea going in standing on that table. The eye graft's shape on a throat: no
	# botches (the case sets `no_fail`), no anesthetic, and they can get up until the old windpipe
	# is out.
	"trachea_graft": {
		"name": "Trachea Grafting",
		"code": "TG",
		"player_only": true,
		"steps": [
			{"id": "open", "label": "Open the throat", "item": "scalpel", "uses": 0, "game": "eye", "variant": "cut", "site": "throat"},
			{"id": "free", "label": "Cut the old windpipe free", "item": "scalpel", "uses": 0, "game": "eye", "variant": "snip", "site": "throat"},
			{"id": "seat", "label": "Seat the new trachea with forceps", "item": "forceps", "uses": 0, "game": "eye", "variant": "grab", "site": "throat"},
			{"id": "stitch", "label": "Stitch the throat closed", "item": "suture_kit", "uses": 1, "game": "eye", "variant": "stitch", "site": "throat"},
		],
	},
}

## Where each minigame script lives. The surgery system loads these by id.
const MINIGAME_SCRIPTS := {
	"anesthetic": "res://scripts/surgery/games/anesthetic.gd",
	"forceps": "res://scripts/surgery/games/forceps.gd",
	"tourniquet": "res://scripts/surgery/games/tourniquet.gd",
	"saw": "res://scripts/surgery/games/saw.gd",
	"gauze": "res://scripts/surgery/games/gauze.gd",
	"stitches": "res://scripts/surgery/games/stitches.gd",
	# GRAFTING: cut / scoop / snip / seat / stitch, on an eye or (part two) on a throat.
	"eye": "res://scripts/surgery/games/eye_ops.gd",
}


## One patient and one ailment per shift, chosen from the shift seed.
static func roll(seed_value: int, shift: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%d|case|%d" % [seed_value, shift])
	var patient_ids := human_patients()
	var ailment_ids := patient_ailments()
	return {
		"patient": patient_ids[rng.randi_range(0, patient_ids.size() - 1)],
		"ailment": ailment_ids[rng.randi_range(0, ailment_ids.size() - 1)],
	}


## Ailments a patient case can have, sorted (everything but the player-only ones such as stitches
## and the monster-only dissection).
static func patient_ailments() -> Array:
	var out := []
	for id in AILMENTS.keys():
		if not bool(AILMENTS[id].get("player_only", false)) and not bool(AILMENTS[id].get("monster_only", false)):
			out.append(id)
	out.sort()
	return out


static func is_player_only(ailment_id: String) -> bool:
	return bool(AILMENTS.get(ailment_id, {}).get("player_only", false))


## dissection (sweep 3): the ailment only a strapped monster has.
static func is_monster_only(ailment_id: String) -> bool:
	return bool(AILMENTS.get(ailment_id, {}).get("monster_only", false))


## dissection (sweep 3): a monster patient (hive, sonographer).
static func is_monster(patient_id: String) -> bool:
	return bool(PATIENTS.get(patient_id, {}).get("monster", false))


## The human patients a phone call can bring, sorted (bob, seal): every patient but the monsters.
static func human_patients() -> Array:
	var out := []
	for id in PATIENTS.keys():
		if not bool(PATIENTS[id].get("monster", false)):
			out.append(id)
	out.sort()
	return out


## The monster patients, sorted.
static func monster_patients() -> Array:
	var out := []
	for id in PATIENTS.keys():
		if bool(PATIENTS[id].get("monster", false)):
			out.append(id)
	out.sort()
	return out


static func patient(id: String) -> Dictionary:
	return PATIENTS.get(id, {})


static func ailment(id: String) -> Dictionary:
	return AILMENTS.get(id, {})


static func steps(ailment_id: String) -> Array:
	return AILMENTS.get(ailment_id, {}).get("steps", [])


static func step(ailment_id: String, index: int) -> Dictionary:
	var s := steps(ailment_id)
	return s[index] if index >= 0 and index < s.size() else {}


static func blurb(patient_id: String, ailment_id: String) -> String:
	return PATIENTS.get(patient_id, {}).get("blurbs", {}).get(ailment_id, "")


## Total of each item the whole procedure needs: consumables by use count, tools as 1.
static func requirements(ailment_id: String) -> Dictionary:
	var need := {}
	for s in steps(ailment_id):
		var amount: int = maxi(1, int(s.uses))
		if Items.is_consumable(s.item):
			need[s.item] = int(need.get(s.item, 0)) + amount
		else:
			need[s.item] = maxi(int(need.get(s.item, 0)), 1)
	return need


## What is still needed from here on, counting from a step index. Used by the softlock guard.
static func remaining_requirements(ailment_id: String, from_step: int) -> Dictionary:
	var need := {}
	var all := steps(ailment_id)
	for i in range(maxi(0, from_step), all.size()):
		var s: Dictionary = all[i]
		if Items.is_consumable(s.item):
			need[s.item] = int(need.get(s.item, 0)) + maxi(1, int(s.uses))
		else:
			need[s.item] = maxi(int(need.get(s.item, 0)), 1)
	return need


## Shared difficulty knob every minigame reads. 1.0 on shift one, harder after.
static func difficulty(shift: int) -> float:
	return 1.0 + 0.12 * maxf(0.0, float(shift - 1))
