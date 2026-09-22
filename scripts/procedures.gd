class_name Procedures
extends RefCounted
## Patients, ailments and the steps of each surgery, as data.
##
## Ailments never know what a patient looks like. They refer to named sites
## ("injection", "gunshot", "limb_cut") and each patient body provides a marker
## for every site. Adding a patient means placing those markers on a new model.

const SITES := ["injection", "gunshot", "limb_cut", "limb", "skull", "brain"]

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
			"laceration": "Lost an argument with a bandsaw. Says the bandsaw started it.",
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
			"laceration": "Came off the rocks at speed. Opened up along one side and is very calm about it.",
		},
	},
	# GRAFTING part one (docs/GRAFTING.md): a strapped Hive. `monster: true` keeps it out of roll(),
	# the dev panel's patient list and anything else that means a human patient (human_patients()).
	# Its body is built by scripts/dissection/monster_builder.gd; the only ailment it takes is
	# `eye_extraction`.
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
			# 2026-09-22 (docs/SUTURE_SPEC.md): step four, SUTURE! -- one continuous thread through
			# the wound. The `laceration` variant is the open grid; the eye socket variant is the
			# same game on a 6x6 with the eye blocked out.
			{"id": "close", "label": "Close the wound", "item": "suture_kit", "uses": 1, "game": "suture", "variant": "laceration", "site": "gunshot"},
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
	# PANEL TESTBED (docs/PANEL_STYLE.md): a one-step procedure that exists to try the panel
	# presentation out. `test_only` keeps it out of roll() -- a normal shift never brings one in --
	# while leaving it in the dev panel's ailment list and the minigame lab. `presedated` starts the
	# case's flags with sedation 1.0, so there is nothing to sedate and the patient never stirs.
	# It borrows the `gunshot` site marker (see docs/KNOWN_ISSUES.md: it wants a generic torso site).
	"laceration": {
		"name": "Deep laceration",
		"code": "LAC",
		"test_only": true,
		"presedated": true,
		"steps": [
			{"id": "close", "label": "Stitch the laceration shut", "item": "suture_kit", "uses": 1, "game": "suture", "site": "gunshot"},
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
	# GRAFTING part one (docs/GRAFTING.md): the thing a strapped Hive has done to it (Dissection is
	# the monster case system; a strapped Hive's only ailment is this one). The three steps play the
	# eye minigame's variants.
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
}

## Where each minigame script lives. The surgery system loads these by id.
const MINIGAME_SCRIPTS := {
	# 2026-09-21: the Anesthetic Injection, the only sedation game (docs/ARCADE_SURGERY.md 5.1). It is
	# an arcade panel game with no legacy twin, so it has no ARCADE_* entry and no switch.
	"anesthetic": "res://scripts/surgery/arcade/inject_arcade.gd",
	# 2026-09-21: DODGE!, the only bullet extraction (docs/ARCADE_SURGERY.md 5.2). No legacy twin and
	# no switch.
	"forceps": "res://scripts/surgery/arcade/dodge_arcade.gd",
	"tourniquet": "res://scripts/surgery/games/tourniquet.gd",
	"saw": "res://scripts/surgery/games/saw.gd",
	"gauze": "res://scripts/surgery/games/gauze.gd",
	"stitches": "res://scripts/surgery/games/stitches.gd",
	"eye": "res://scripts/surgery/games/eye_ops.gd",   # GRAFTING part one: cut / scoop / snip
	"suture": "res://scripts/surgery/games/suture.gd", # PANEL TESTBED: the deep laceration
}

## ARCADE (docs/ARCADE_SURGERY.md): the arcade rebuild of a step, played on the raised panel. Keyed
## by "<game>" or "<game>:<variant>"; the variant key wins when it exists.
const ARCADE_SCRIPTS := {
	"gauze:pack": "res://scripts/surgery/arcade/pack_wrap_arcade.gd",   # WHACK! then WRAP!
	"gauze:stump": "res://scripts/surgery/arcade/wrap_stump_arcade.gd", # WRAP! (the same one)
	"tourniquet": "res://scripts/surgery/arcade/squeeze_arcade.gd",     # SQUEEZE!
	"saw": "res://scripts/surgery/arcade/saw_arcade.gd",                # SAW!
	"eye:cut": "res://scripts/surgery/arcade/steer_arcade.gd",          # STEER!
	"eye:scoop": "res://scripts/surgery/arcade/pry_arcade.gd",          # PRY!
	"eye:snip": "res://scripts/surgery/arcade/nerve_arcade.gd",         # CUT THE RIGHT ONE!
	"eye:place": "res://scripts/surgery/arcade/grab_arcade.gd",         # GRAB! (eye into the vat)
	"eye:grab": "res://scripts/surgery/arcade/grab_arcade.gd",          # GRAB! (vat into the socket)
	"eye:stitch": "res://scripts/surgery/arcade/ring_arcade.gd",        # STITCH! the ring variant
	# SUTURE! (docs/SUTURE_SPEC.md): one script, two puzzle variants. The plain "suture" key catches
	# the `laceration` testbed procedure, whose step carries no variant of its own.
	"suture": "res://scripts/surgery/arcade/suture_arcade.gd",          # SUTURE! (deep laceration)
	"suture:laceration": "res://scripts/surgery/arcade/suture_arcade.gd",
	"suture:eye": "res://scripts/surgery/arcade/suture_arcade.gd",      # SUTURE! (eye socket)
}

## Which arcade rebuilds are live. FALSE means the legacy game still plays that step, unchanged.
## Zach flips these one at a time as he approves them; the dev panel's "Arcade surgery" checkboxes
## flip them at runtime (host-authoritative: the host broadcasts, so every machine agrees).
## A `static var` so the lab, the warmup and the headless tests can set it without a Game.
##
## A key is "<game>" or "<game>:<variant>"; the variant key wins where it exists.
static var ARCADE_ENABLED := {
	"gauze:pack": true,
	"gauze:stump": true,
	"tourniquet": true,
	"saw": false,
	"eye:cut": true,
	"eye:scoop": true,
	"eye:snip": true,
	"eye:place": true,
	"eye:grab": true,
	"eye:stitch": true,
	"suture": true,
	"suture:laceration": true,
	"suture:eye": true,
}


## True when this step's arcade rebuild should play instead of the legacy game.
static func arcade_on(game: String, variant := "") -> bool:
	var key := "%s:%s" % [game, variant]
	if variant != "" and ARCADE_ENABLED.has(key):
		return bool(ARCADE_ENABLED[key]) and (ARCADE_SCRIPTS.has(key) or ARCADE_SCRIPTS.has(game))
	return bool(ARCADE_ENABLED.get(game, false)) and ARCADE_SCRIPTS.has(game)


## The script the framework should load for a step: the arcade rebuild when it is on and exists,
## otherwise the legacy game. Everything that spawns a minigame goes through here.
static func minigame_script(game: String, variant := "") -> String:
	if arcade_on(game, variant):
		var path := String(ARCADE_SCRIPTS.get("%s:%s" % [game, variant], ARCADE_SCRIPTS.get(game, "")))
		if path != "" and ResourceLoader.exists(path):
			return path
	if variant != "" and MINIGAME_SCRIPTS.has("%s:%s" % [game, variant]):
		return String(MINIGAME_SCRIPTS["%s:%s" % [game, variant]])
	return String(MINIGAME_SCRIPTS.get(game, ""))


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


## Ailments a patient case can have, sorted (everything but the player-only ones such as stitches,
## the monster-only eye_extraction and the test-only ones a shift never rolls).
static func patient_ailments() -> Array:
	var out := []
	for id in AILMENTS.keys():
		var a: Dictionary = AILMENTS[id]
		if not bool(a.get("player_only", false)) and not bool(a.get("monster_only", false)) 				and not bool(a.get("test_only", false)):
			out.append(id)
	out.sort()
	return out


## PANEL TESTBED: what the dev panel and the warmup offer for a patient on a table, sorted: every
## rollable ailment plus the test-only ones. A shift still only ever rolls patient_ailments().
static func dev_ailments() -> Array:
	var out := patient_ailments()
	for id in AILMENTS.keys():
		if bool(AILMENTS[id].get("test_only", false)):
			out.append(id)
	out.sort()
	return out


## PANEL TESTBED: a testbed procedure, never rolled into a shift.
static func is_test_only(ailment_id: String) -> bool:
	return bool(AILMENTS.get(ailment_id, {}).get("test_only", false))


## Whether a case of this ailment arrives already sedated (nothing to inject, and no stirring).
static func is_presedated(ailment_id: String) -> bool:
	return bool(AILMENTS.get(ailment_id, {}).get("presedated", false))


static func is_player_only(ailment_id: String) -> bool:
	return bool(AILMENTS.get(ailment_id, {}).get("player_only", false))


## GRAFTING part one: the ailment only a strapped monster has.
static func is_monster_only(ailment_id: String) -> bool:
	return bool(AILMENTS.get(ailment_id, {}).get("monster_only", false))


## GRAFTING part one: a monster patient (the Hive).
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
