extends RefCounted
## What the break room's wall terminal shows (terminal redesign, chunk 2), as data: the four
## sections, the entries in each, and every entry's page. wall_terminal_ui.gd draws it.
##
##   SECTIONS                          [{id, title}] in home-grid order
##   entries(section, view) -> Array   [{key, title, known}]; unknown entries show "???" and can't open
##   page(section, key, view) -> Dict  {title, subtitle, paragraphs: [String], hint, models: [{monster} |
##                                      {item, count, link, label}], ability: {name, levels: [String]}
##                                      (monsters); a procedure's steps are a paragraph and its tools
##                                      links (link: a surgery item's key, label over it when pointed at)
##
## `view` is whose database the screen shows (wall_session.gd view()): {db: {kind: bits (1 sighted,
## 2 scanned, 4 harvested)}, peer, abilities}; nobody signed in is an empty db and peer 0.
## Known: surgery items and procedures always; a monster once scanned; any other item once picked
## up (game.mark_db(kind, "sighted", player) in pickup_item). Ability names show once harvested,
## each level's numbers once the player's ability level reaches it.

const MonsterPages := preload("res://scripts/database/monster_pages.gd")
const Pages := preload("res://scripts/database/database_pages.gd")
const ItemsDB := preload("res://scripts/items.gd")
const LootTable := preload("res://scripts/economy/loot_table.gd")
const ProceduresDB := preload("res://scripts/procedures.gd")

const SECTIONS := [
	{"id": "monsters", "title": "MONSTERS"},
	{"id": "procedures", "title": "PROCEDURES"},
	{"id": "surgery", "title": "SURGERY ITEMS"},
	{"id": "other", "title": "OTHER ITEMS"},
]

## Which ability path a monster's ability grows on, and its name.
const ABILITY := {"hive": "Hive Eyes", "sonographer": "Echo"}

const MONSTER_TEXT := {
	"hive": ["Wanders the wings until it hears something. It can't see: running, dropping things and shoving give you away.", "About 2 doses of anesthetic put it under."],
	"sonographer": ["A blind doctor with a wand for a hand. It clicks as it walks and hunts by sound: watch its neck, it grows as it gets suspicious.", "It takes about 3 doses to put it under."],
	"night_nurse": ["She only moves when nobody is looking at her. Keep your eyes on her.", "Nobody knows what happens if she reaches you."],
}

const PROCEDURE_TEXT := {
	"gunshot": "A bullet is still inside the patient. Get it out and stop the bleeding.",
	"amputation": "An infected limb that can't be saved. Take it off before the infection spreads.",
	"laceration": "A deep cut that won't close on its own. Stitch it shut.",
	"stitches": "A downed teammate with a deep gash. Stitch it shut and they get back up.",
	"eye_extraction": "A strapped Hive on the table. Hold the scalpel to start: cut round the eye, scoop it out, snip the nerve, then lift it into the specimen vat standing on the table with the forceps.",
}

const SURGERY_TEXT := {
	"anesthetic": ["Puts the patient under so they don't feel a thing. Too little and they wake up mid-surgery.", "Found in medicine fridges. Glass: dropping it breaks some."],
	"syringe": ["Load one from a vial anywhere in the hospital and the dose is ready before you reach the table.", "Found in fridges and drawer units. Spent once the dose is in a patient."],
	"gauze": ["Rolls of dressing that pack wounds and soak up bleeding.", "Found in nurse station drawers."],
	"forceps": ["Long tongs for pulling out bullets, and seating a graft.", "Found in steel drawer units. Kept after use."],
	"tourniquet": ["A strap that cuts off the blood to a limb before you saw.", "Found in trauma bags. Kept after use."],
	"bone_saw": ["Cuts through bone: infected limbs.", "Found on pegboards. Kept after use."],
	"suture_kit": ["Needle and thread for closing a downed teammate's wound.", "Found in trauma bags and drawers."],
	"scalpel": ["A small blade for the careful cuts: around an eye, and through its nerve.", "Starts on the OR's storage shelves. Kept after use."],
	"eye_spoon": ["A shallow spoon that slides behind an eye and lifts it out.", "Starts on the OR's storage shelves. Kept after use."],
}

const LOOT_BLURBS := {
	"pulse_oximeter": "A fingertip clip that reads blood oxygen. Sells, and it has a trick.",
	"epipen": "An auto-injector, yellow with a blue cap. Sells, and it has a trick.",
	"reflex_hammer": "A little rubber reflex hammer.",
	"pill_bottle": "Somebody's prescription. Stacks with others.",
	"xray_film": "An X-ray of someone's ribs.",
	"desk_phone": "A desk phone, ripped off its cord.",
	"laptop": "A hospital laptop. Fragile.",
	"gold_watch": "A patient's gold watch, still ticking.",
	# POCKETS 2 phase 2: the Natatorium.
	"pool_chemical_drum": "A sealed drum of pool chemicals. Nobody ordered it and nobody opened it. Takes both hands.",
	"lifeguard_whistle": "A lifeguard's whistle on a red lanyard. Blow it once and every monster within thirty metres comes to look at you. There is no second blast.",
	# POCKETS 2 phase 5: the Factory.
	"grease_bucket": "A pail of machine grease, half dug out. Whatever it was for, nobody got round to it.",
	"copper_wire_spool": "A drum of heavy copper wire off the line. Worth real money, and it takes both hands.",
	"foremans_clipboard": "A shift schedule with no dates on it. Every name but two has been crossed out.",
	"heart_monitor": "A bedside heart monitor. Takes both hands.",
	"defibrillator": "A portable defibrillator. Takes both hands.",
	"ultrasound": "A portable ultrasound. The best find in the wings.",
	"eye_hive": "The eyeball of a strapped Hive. It clouds over and spoils in a minute or two unless it goes in a vat.",
	# POCKETS 2 phase 5: the Restaurant.
	"cast_iron_molcajete": "A basalt mortar the size of a football, pestle and all. It weighs what a rock weighs, and it is worth what the office watches are worth.",
	"tequila": "Top shelf, barely touched. A syringe will draw from it, and it works — but it is not anesthetic, and a patient under it does not lie as still or as long.",
	"restaurant_pagers": "The station from a restaurant's front desk with two pagers still docked in it. Take them out and they stay bound to each other.",
	"restaurant_pager": "One of a bound pair. Press it and the other one goes off — quietly, if somebody is holding it; out loud on the floor, if they are not. On its own it is just a pager.",
	"eye_surgeon": "A surgeon's own eyeball, labelled with whose it is. It spoils outside a vat, too.",
}

## POCKETS 2 phase 5: SHARED TAGS. A tag is a word two or more unrelated items have in common, shown
## on each of their database entries so a player reading one is told the others exist. It is the
## database noticing a pattern the items were designed to share but which nothing in the game ever
## says out loud.
##
## "lure" is the first and, so far, the only one: things whose whole job is to make a noise somewhere
## you are not. They were built in three different pocket spaces by three different phases and would
## otherwise never be seen together.
const TAG_TEXT := {
	"lure": "LURE — makes a noise somewhere you are not standing.",
}

## Item kind -> the tags it carries.
##
## The bucket of quarters from the Laundromat (POCKET_SPACES_2 phase 4) is the third member of this
## family and is being built in parallel with this phase. It was NOT on `main` when phase 5 landed,
## so its kind name is deliberately not guessed at here: whoever merges the Laundromat adds the one
## line for it rather than phase 5 shipping a tag on a kind that may not exist.
const ITEM_TAGS := {
	"lifeguard_whistle": ["lure"],    # the Natatorium (phase 2)
	"restaurant_pager": ["lure"],     # the Restaurant (phase 5): a planted pager, not the station
}


## The tag lines for an item kind, ready to print. Empty for the great majority of items.
static func tags_for(kind: String) -> Array:
	var out: Array = []
	for t: String in ITEM_TAGS.get(kind, []):
		var line := String(TAG_TEXT.get(t, ""))
		if line != "":
			out.append(line)
	return out


## Every kind carrying `tag`. The database uses it to say "and these others"; tests use it to check
## the family is whole.
static func kinds_tagged(tag: String) -> Array:
	var out: Array = []
	for k: String in ITEM_TAGS.keys():
		if (ITEM_TAGS[k] as Array).has(tag):
			out.append(k)
	out.sort()
	return out


# ---------------------------------------------------------------------------
# entries

static func entries(section: String, view: Dictionary) -> Array:
	var out: Array = []
	match section:
		"monsters":
			for kind in MonsterPages.ORDER:
				out.append({"key": kind, "title": String(MonsterPages.entry(kind).get("name", kind)), "known": _tier(view, kind) >= 2})
		"procedures":
			for id in ProceduresDB.AILMENTS.keys():
				# SYRINGE DRAW: loading a syringe is an action, not a procedure.
				if bool(ProceduresDB.AILMENTS[id].get("handheld", false)):
					continue
				out.append({"key": id, "title": String(ProceduresDB.AILMENTS[id].get("name", id)), "known": true})
		"surgery":
			for kind in Pages.item_order():
				if ItemsDB.is_surgical(kind):
					out.append({"key": kind, "title": ItemsDB.display_name(kind), "known": true})
		"other":
			for kind in _other_kinds():
				out.append({"key": kind, "title": ItemsDB.display_name(kind), "known": _found(view, kind)})
	return out


static func _other_kinds() -> Array:
	var out: Array = []
	for kind in Pages.item_order():
		if not ItemsDB.is_surgical(kind):
			out.append(kind)
	for kind in LootTable.kinds():
		if not out.has(kind):
			out.append(kind)
	return out


# ---------------------------------------------------------------------------
# pages

static func page(section: String, key: String, view: Dictionary) -> Dictionary:
	match section:
		"monsters":
			return _monster(key, view)
		"procedures":
			return _procedure(key)
		"surgery":
			return _item(key)
		"other":
			return _other(key)
	return {}


static func _monster(kind: String, view: Dictionary) -> Dictionary:
	var e := MonsterPages.entry(kind)
	var p := {
		"title": String(e.get("name", kind)).to_upper(),
		"subtitle": "SCANNED SPECIMEN",
		"paragraphs": MONSTER_TEXT.get(kind, []),
		"models": [{"monster": kind}],
	}
	var name := "???"
	var levels: Array = ["???", "???", "???"]
	if ABILITY.has(kind):
		var lvl := _level(view, kind)
		if lvl >= 1:
			name = String(ABILITY[kind]).to_upper()
		for n in range(1, 4):
			var ab = view.get("abilities")
			if lvl >= n and ab != null:
				if kind == "hive":
					levels[n - 1] = "Reach %.0f m, watch for %.1f s" % [ab.hive_range(n), ab.hive_seconds(n)]
				else:
					levels[n - 1] = "Radius %.0f m, lasts %.1f s" % [ab.echo_radius(n), ab.echo_seconds(n)]
	p["ability"] = {"name": name, "levels": levels}
	return p


static func _procedure(id: String) -> Dictionary:
	var d := Pages.procedure_page(id)
	var steps: Array = []
	var kinds: Array = []
	for s in d.steps:
		steps.append({"label": String(s.label), "item": String(s.item), "item_name": String(s.item_name)})
		if String(s.item) != "" and not kinds.has(String(s.item)):
			kinds.append(String(s.item))
	# Each tool on the turntable is a link: point at it for its name, click it for its page.
	var models: Array = []
	for k in kinds:
		models.append({"item": k, "count": 2 if ItemsDB.is_consumable(k) else 1, "link": k, "label": ItemsDB.display_name(k)})
	var lines: Array = []
	for n in steps.size():
		lines.append("%d.  %s  (%s)" % [n + 1, steps[n].label, steps[n].item_name])
	return {
		"title": String(d.name).to_upper(),
		"subtitle": "PROCEDURE  %s" % String(d.get("code", "")),
		"paragraphs": [String(PROCEDURE_TEXT.get(id, "")), "\n".join(lines)],
		"hint": "Point at a tool for its name. Click it to look it up.",
		"models": models,
	}


static func _item(kind: String) -> Dictionary:
	var d := Pages.item_page(kind)
	return {
		"title": String(d.name).to_upper(),
		"subtitle": "SURGERY ITEM",
		"paragraphs": SURGERY_TEXT.get(kind, [String(d.real_use)]),
		"models": [{"item": kind, "count": 3 if ItemsDB.is_consumable(kind) else 1}],
	}


static func _other(kind: String) -> Dictionary:
	if kind == "placebo_pills":
		return {
			"title": "PLACEBO PILLS",
			"subtitle": "PHARMACY",
			"paragraphs": ["Sugar pills from the pharmacy. They do nothing. Probably.", "Order them on the lobby fax."],
			"models": [{"item": kind, "count": 1}],
		}
	if kind == "rocket_boots":
		return {
			"title": "ROCKET BOOTS",
			"subtitle": "PHARMACY",
			"paragraphs": ["Surplus clogs with a thruster bolted to each heel. Taking a pair puts them on.",
				"Hold crouch through a sprint-dive to burn fuel and fly straight ahead. Let go to drop. Fuel refills on the ground.",
				"Anything solid, head on, costs you a heart.", "Order them on the lobby fax."],
			"models": [{"item": kind, "count": 1}],
		}
	if kind == "specimen_vat":
		return {
			"title": "SPECIMEN VAT",
			"subtitle": "LAB",
			"paragraphs": ["A glass jar of cloudy fluid. An eye floating in it stops spoiling. Three empty ones stand on the lab wall in the OR.",
				"E with an eye in hand puts it in. V reaches an eye back out. E on a lab bench sets a carried vat down. Takes both hands."],
			"models": [{"item": kind, "count": 1}],
		}
	var def := LootTable.def(kind)
	var value: Array = def.get("value", [0, 0])
	var worth := "Sells for $%d to $%d at the furnace." % [int(value[0]), int(value[value.size() - 1])]
	if kind.begins_with("eye_"):
		worth = "Sells for less every second it spends out of a vat."
	# POCKETS 2 phase 5: a tagged item says so, and names the rest of its family, so the three lures
	# read as one idea rather than three coincidences in three different pocket spaces.
	var paras: Array = [String(LOOT_BLURBS.get(kind, "")), worth]
	for t: String in ITEM_TAGS.get(kind, []):
		var line := String(TAG_TEXT.get(t, ""))
		var family: Array = []
		for other: String in kinds_tagged(t):
			if other != kind:
				family.append(ItemsDB.display_name(other))
		if not family.is_empty():
			line += " Also: %s." % ", ".join(family)
		if line != "":
			paras.append(line)
	return {
		"title": ItemsDB.display_name(kind).to_upper(),
		"subtitle": "SALVAGE",
		"paragraphs": paras,
		"models": [{"item": kind, "count": 1}],
	}


# ---------------------------------------------------------------------------
# what this player knows

static func _tier(view: Dictionary, kind: String) -> int:
	var bits := int((view.get("db", {}) as Dictionary).get(kind, 0))
	if bits & 4:
		return 3
	if bits & 2:
		return 2
	return 1 if bits & 1 else 0


static func _found(view: Dictionary, kind: String) -> bool:
	return _tier(view, kind) >= 1


static func _level(view: Dictionary, path: String) -> int:
	var ab = view.get("abilities")
	if ab == null or int(view.get("peer", 0)) == 0:
		return 0
	return int(ab.level(int(view.peer), path))
