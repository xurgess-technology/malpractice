class_name Items
extends RefCounted
## Every item in the game, as data. The world, the hands, the OR shelf, the spawner and the
## medical guide all read from here, so adding an item means adding one entry.

## Where an item can turn up. Container types are built by the containers system;
## "loose" means sitting on a counter, tray, gurney or floor edge.
const CONTAINER_TYPES := {
	"med_fridge": {"name": "medicine fridge", "rooms": ["pharmacy", "supply_closet", "lab"]},
	"drawer_unit": {"name": "steel drawer unit", "rooms": ["supply_closet", "janitor_closet", "lab", "morgue"]},
	"station_drawers": {"name": "nurse station drawers", "rooms": ["nurse_station"]},
	"trauma_bag": {"name": "trauma bag", "rooms": ["corridor", "nurse_station", "patient_room"]},
	"pegboard": {"name": "pegboard", "rooms": ["janitor_closet", "supply_closet", "morgue"]},
	# POCKETS 2 phase 2: the Natatorium's lifeguard stand, and nowhere in the hospital proper -- no
	# rooms, so RoomFurnish never places one. The pocket builds it directly.
	"first_aid_cabinet": {"name": "first-aid cabinet", "rooms": []},
}

const SURGICAL := ["anesthetic", "gauze", "forceps", "tourniquet", "bone_saw", "communion_wine", "tequila"]

## POCKETS 2 phase 3: what will do instead of a vial of anesthetic, and how much of a real dose it
## carries. Anything in here satisfies a step that asks for "anesthetic" and re-doses a strapped
## monster; the number multiplies what the dose ends up worth, so a substitute is a weak dose that
## wears off sooner rather than a different mechanic. The Chapel's communion wine is the first;
## phase 5's top-shelf tequila is meant to be the second, at the same strength -- and it is, below.
## This is deliberately the only place the substitution lives: the injection minigame itself is
## untouched and does not know the difference.
const ANESTHETIC_KINDS := {"anesthetic": 1.0, "communion_wine": 0.55, "tequila": 0.55}


## Does holding `held` satisfy a procedure step that asks for `want`?
static func step_accepts(want: String, held: String) -> bool:
	if want == held:
		return true
	return ANESTHETIC_KINDS.has(want) and ANESTHETIC_KINDS.has(held)


## The share of a real dose this kind delivers (1.0 for anything that is not a substitute).
static func anesthetic_strength(kind: String) -> float:
	return float(ANESTHETIC_KINDS.get(kind, 1.0))


## The kind in `p`'s hands that satisfies a step asking for `want`: the selected stack when it does,
## else any slot holding enough. "" when they have nothing that will do.
static func held_for_step(p, want: String, need := 1) -> String:
	if p == null or not ("slots" in p):
		return ""
	if p.has_method("selected_head"):
		var h: int = p.selected_head()
		if h >= 0 and h < p.slots.size() and step_accepts(want, String(p.slots[h].kind)) and int(p.slots[h].count) >= need:
			return String(p.slots[h].kind)
	for s in p.slots:
		if step_accepts(want, String(s.kind)) and int(s.count) >= need:
			return String(s.kind)
	return ""

const ITEMS := {
	"anesthetic": {
		"name": "Anesthetic",
		"short": "Anesthetic vials",
		"surgical": true,
		"consumable": true,
		"batch": [2, 3],
		"fragile": true,
		"found": {"med_fridge": 0.85, "loose": 0.15},
		"loose_surfaces": ["counter", "tray"],
		"real_use": "A general anesthetic puts a patient into a controlled, reversible unconsciousness so they feel nothing during surgery. The dose depends on body weight: too little and they can wake mid-procedure, too much and breathing and heart rate crash.",
		"where": "Almost always in the medicine fridges of pharmacies, supply closets and labs. Now and then a vial or two left out on a counter or a bedside tray.",
		"handling": "Consumable. Found in batches of 2 to 3. Glass: dropping the batch smashes some of it.",
	},
	# POCKETS 2 phase 3, the Chapel. An anesthetic substitute (ANESTHETIC_KINDS): it will put a
	# patient or a strapped monster under, but weakly, so they stir sooner. One bottle, and glass.
	"communion_wine": {
		"name": "Communion wine",
		"short": "Communion wine",
		"surgical": true,
		"consumable": true,
		"batch": [1, 1],
		"fragile": true,
		"found": {"loose": 1.0},
		"loose_surfaces": ["counter", "tray"],
		# Only ever found in the Chapel (ItemSpawner._legal). An item with no `rooms` key is found
		# anywhere, which is every other item in this table.
		"rooms": {"chapel_sacristy": 1.0, "chapel_sanctuary": 1.0, "chapel_nave": 1.0, "chapel_aisle": 1.0},
		"real_use": "Alcohol was the anesthetic before there were anesthetics, and it is a bad one: the dose that dulls pain is close to the dose that stops breathing, it wears off unevenly, and the patient can surface halfway through without ever being properly under.",
		"where": "Nowhere in the hospital. There is a case of it in the chapel sacristy, and a bottle usually left out on the credence table.",
		"handling": "Consumable. One bottle. Glass: dropping it is the end of it. Counts as anesthetic wherever a vial would, at a little over half the dose.",
	},
	# POCKETS 2 phase 5, the Restaurant. The second anesthetic substitute, and deliberately built as
	# the Chapel's wine was rather than beside it: same ANESTHETIC_KINDS entry, same strength, same
	# `rooms` fence (ItemSpawner._legal), same batch of one. The two are the same idea found in two
	# different impossible rooms, so they should be the same code.
	"tequila": {
		"name": "Tequila, top shelf",
		"short": "Bottles of tequila",
		"surgical": true,
		"consumable": true,
		"batch": [1, 1],
		"fragile": true,
		"found": {"loose": 1.0},
		"loose_surfaces": ["counter", "tray"],
		# Only ever found in the Restaurant, the way the wine is only ever found in the Chapel.
		"rooms": {"restaurant": 1.0, "restaurant_kitchen": 1.0},
		"real_use": "Spirits were what surgeons had before anesthesia, and they were never good at it: enough to dull a patient is close to enough to stop them breathing, it takes hold unevenly, and they can come up again halfway through with the wound still open.",
		"where": "Nowhere in the hospital. There is a bottle behind the bar of a restaurant that should not be there, and sometimes one left out on a table.",
		"handling": "Consumable. One bottle. Glass: dropping it is the end of it. Counts as anesthetic wherever a vial would, at a little over half the dose.",
	},
	"gauze": {
		"name": "Gauze",
		"short": "Gauze rolls",
		"surgical": true,
		"consumable": true,
		"batch": [2, 4],
		"fragile": false,
		"found": {"station_drawers": 0.7, "loose": 0.3},
		"loose_surfaces": ["counter", "tray", "gurney"],
		"real_use": "Gauze is a loose woven cotton dressing. Packed into a wound it applies pressure from the inside and helps blood clot; wrapped around a limb or stump it holds that pressure and keeps the wound covered.",
		"where": "Usually in the drawers of nurse stations and patient room counters. Often a few rolls left loose on counters, trays or gurneys.",
		"handling": "Consumable. Found in rolls of 2 to 4. Survives being dropped.",
	},
	"forceps": {
		"name": "Forceps",
		"short": "Forceps",
		"surgical": true,
		"consumable": false,
		"batch": [1, 1],
		"fragile": false,
		"found": {"drawer_unit": 0.8, "loose": 0.2},
		"loose_surfaces": ["tray", "counter"],
		"real_use": "Surgical forceps are long, hinged tweezers used to grip tissue or remove foreign objects without putting fingers into a wound. In a gunshot wound they are how a surgeon reaches in and draws out the bullet or its fragments.",
		"where": "Sealed in sterile packs inside the steel drawer units of supply closets, janitor closets, labs and the morgue. Occasionally abandoned on an instrument tray.",
		"handling": "Reusable. One pair. Stays in the OR once delivered.",
	},
	"tourniquet": {
		"name": "Tourniquet",
		"short": "Tourniquet",
		"surgical": true,
		"consumable": false,
		"batch": [1, 1],
		"fragile": false,
		"found": {"trauma_bag": 0.8, "loose": 0.2},
		"loose_surfaces": ["gurney", "floor"],
		"real_use": "A tourniquet is a strap tightened around a limb, above an injury, until it stops blood flowing past it. It is placed before an amputation so the cut does not bleed the patient out, and it has to be tight enough to work without crushing the limb.",
		"where": "In the red trauma bags hung on corridor walls and in nurse stations. Sometimes dropped on a gurney or the floor.",
		"handling": "Reusable. One. Stays in the OR once delivered.",
	},
	"bone_saw": {
		"name": "Bone saw",
		"short": "Bone saw",
		"surgical": true,
		"consumable": false,
		"batch": [1, 1],
		"fragile": false,
		"found": {"pegboard": 0.75, "loose": 0.25},
		"loose_surfaces": ["gurney", "counter", "floor"],
		"real_use": "An amputation saw cuts through bone once skin and muscle have been opened. It is worked in long, steady strokes: rushing it tears tissue and leaves a ragged edge that heals badly.",
		"where": "Hung on pegboards in janitor closets, supply closets and the morgue. Sometimes left leaning against a gurney somewhere it has no business being.",
		"handling": "Reusable. Heavy. Stays in the OR once delivered.",
	},
	# downed (sweep 2 wave 3): closes a downed teammate's wound on the OR's player table, and since
	# SUTURE! (0.10.4) it closes a gunshot case's wound too. Deliberately NOT in SURGICAL even so:
	# it is supplied every shift by ItemSpawner.LOOSE_SUPPLY (game.gd spawn_suture_kits) whether or
	# not the case wants one, instead of riding the case's own plan. tools/spawncheck.gd checks that
	# scatter against the case's requirements, so the guarantee is still measured.
	"suture_kit": {
		"name": "Suture kit",
		"short": "Suture kits",
		"surgical": true,
		"consumable": true,
		"batch": [1, 2],
		"fragile": false,
		"found": {"trauma_bag": 0.4, "station_drawers": 0.35, "drawer_unit": 0.25},
		"loose_surfaces": [],
		"real_use": "A sterile pack with a curved needle already threaded with suture. Each bite goes in on one side of a gash and out the other, and pulling the thread snug draws the edges together so the bleeding stops and the wound can heal.",
		"where": "In trauma bags on corridor walls, in nurse station drawers and in the steel drawer units of supply closets.",
		"handling": "Consumable. Found in packs of 1 or 2. Put one on the OR supply shelf, carry a downed teammate to a free OR table and stitch them up.",
	},
	# SWEEP 4A HOOK (pharmacy, chunk 3): does nothing mechanically. Only ever bought at the
	# pharmacy window (`found` empty keeps it out of the wings and the supply spawner).
	"placebo_pills": {
		"name": "Placebo pills",
		"short": "Placebo pill bottles",
		"surgical": false,
		"consumable": true,
		"batch": [10, 10],
		"fragile": false,
		"found": {},
		"loose_surfaces": [],
		"real_use": "A bottle of sugar pills. Efficacy: disputed. Side effects: optimism.",
		"where": "Only sold at the pharmacy window. Never turns up loose in the wings.",
		"handling": "Consumable, 10 to a bottle. Use to swallow one; charge a throw to lob a single pill.",
	},
	# ROCKET BOOTS: the first real thing the pharmacy sells. `wear` means taking it puts it on (it
	# never goes in a hand): player.boots, and the sprint-dive becomes a rocket dive while crouch
	# is held (player.gd "ROCKET BOOTS"). Only ever bought, like the pills.
	"rocket_boots": {
		"name": "Rocket boots",
		"short": "Rocket boots",
		"surgical": false,
		"consumable": false,
		"wear": true,
		"batch": [1, 1],
		"fragile": false,
		"found": {},
		"loose_surfaces": [],
		"real_use": "Surplus clogs with a thruster bolted to each heel. Not FDA approved.",
		"where": "Only sold at the pharmacy window.",
		"handling": "Worn, not carried: taking a pair puts them on. Hold crouch through a sprint-dive to burn fuel and fly straight ahead. Walls hurt.",
	},
	# THE SURGICAL ROBOT (scripts/robot/robot.gd): what brings the OR's robot to life. Only ever
	# bought, like the boots; carried in one hand to the robot and plugged in with E, which uses it up
	# and powers the robot for the rest of the run. `shop` puts it in the pharmacy's colour.
	"robot_core": {
		"name": "Robot core",
		"short": "Robot cores",
		"surgical": false,
		"consumable": false,
		"shop": true,
		"batch": [1, 1],
		"fragile": false,
		"found": {},
		"loose_surfaces": [],
		"real_use": "A glass power cell with something humming in it. The surgical robot beside the OR table has an empty socket exactly this shape.",
		"where": "Only sold at the pharmacy window.",
		"handling": "Carry it to the surgical robot in the OR and press E to plug it in. The robot stays on for the rest of the run.",
	},
	# GRAFTING part one (docs/GRAFTING.md): the two eye tools, and the specimen vat. `found` is empty:
	# game.gd stocks the scalpel and the eye spoon on the OR's storage shelves at the start of a run,
	# and the vats stand on the lab wall (scripts/grafting/vats.gd).
	"scalpel": {
		"name": "Scalpel",
		"short": "Scalpels",
		"surgical": true,
		"consumable": false,
		"batch": [1, 1],
		"fragile": false,
		"found": {},
		"loose_surfaces": [],
		"real_use": "A small, very sharp blade on a slim handle for the first careful cut. Where a saw takes a limb or a skull, a scalpel takes a line through skin, or around an eye, or through a nerve.",
		"where": "Starts on the OR's storage shelves.",
		"handling": "Reusable. Eyeball extraction uses it twice: to cut around the eye, and to snip the optic nerve.",
	},
	"eye_spoon": {
		"name": "Eye spoon",
		"short": "Eye spoons",
		"surgical": true,
		"consumable": false,
		"batch": [1, 1],
		"fragile": false,
		"found": {},
		"loose_surfaces": [],
		"real_use": "A small shallow spoon on a long handle, made to slide behind an eyeball and lift it out of its socket, or to seat one back in.",
		"where": "Starts on the OR's storage shelves.",
		"handling": "Reusable. Scoops the eye out of the socket.",
	},
	## SYRINGE DRAW (docs/ANESTHETIC_INJECTION_SPEC.md 9): the barrel you load anywhere and stick at
	## the table. A batch consumable like the vials: one slot is several syringes, and a syringe is
	## spent the moment its dose goes into a patient. What a LOADED one holds rides the slot's `x`
	## string (scripts/syringe/syringes.gd), so only the top syringe of a batch is ever loaded.
	"syringe": {
		"name": "Syringe",
		"short": "Syringes",
		"surgical": true,
		"consumable": true,
		"batch": [2, 3],
		"fragile": false,
		"found": {"med_fridge": 0.35, "drawer_unit": 0.4, "station_drawers": 0.15, "loose": 0.1},
		"loose_surfaces": ["counter", "tray"],
		"real_use": "A barrel, a plunger and a hollow needle. Drawn from a vial ahead of time so the drug is ready the moment it is needed; the plunger is marked so the dose can be read off the barrel.",
		"where": "Medicine fridges and steel drawer units, some in nurse station drawers, now and then a loose one on a counter or tray.",
		"handling": "Consumable. Found in batches of 2 to 3. E while holding one loads it from a fluid you are carrying; it is spent once its dose is in a patient.",
	},
	"specimen_vat": {
		"name": "Specimen vat",
		"short": "Specimen vats",
		"surgical": false,
		"consumable": false,
		"bulky": true,
		"batch": [1, 1],
		"fragile": false,
		"found": {},
		"loose_surfaces": [],
		"real_use": "A glass jar of cloudy preserving fluid. Anything floating in it stops rotting.",
		"where": "Three empty ones stand on the lab wall in the OR at the start of a run.",
		"handling": "Carried in both hands. E with an eye in hand puts it in; the vat key reaches an eye back out. E on a lab bench sets it down.",
	},
}

## Tabs the database terminal shows as locked, so it is obvious the pool will grow.
const LOCKED := ["Defibrillator", "Clamp", "IV bag", "Sedative dart", "Battery", "Retractor"]


## Sellable loot (scripts/economy/loot_table.gd). Not in ITEMS so the terminal, the supply spawner
## and the dev panel's supply list leave it alone; def() and every helper below still know it.
const LootTable := preload("res://scripts/economy/loot_table.gd")

static var _loot_defs := {}


static func exists(kind: String) -> bool:
	return ITEMS.has(kind) or LootTable.has(kind)


static func def(kind: String) -> Dictionary:
	if ITEMS.has(kind):
		return ITEMS[kind]
	if not LootTable.has(kind):
		return {}
	if not _loot_defs.has(kind):
		_loot_defs[kind] = LootTable.def(kind)
	return _loot_defs[kind]


static func display_name(kind: String) -> String:
	return def(kind).get("name", kind.capitalize())


static func is_consumable(kind: String) -> bool:
	return def(kind).get("consumable", false)


static func is_fragile(kind: String) -> bool:
	return def(kind).get("fragile", false)


static func is_surgical(kind: String) -> bool:
	return def(kind).get("surgical", false)


## Sellable loot: gold tint, goes in the sell bin, never on the shelf.
static func is_loot(kind: String) -> bool:
	return LootTable.has(kind)


## ROCKET BOOTS: taking it puts it on instead of filling a hand.
static func is_worn(kind: String) -> bool:
	return def(kind).get("wear", false)


## Takes two hand slots.
static func is_bulky(kind: String) -> bool:
	return def(kind).get("bulky", false)


## How many hand slots one stack of this kind occupies.
static func slots_needed(kind: String) -> int:
	return 2 if is_bulky(kind) else 1


## "Anesthetic vials" style label for a stack of `count`.
static func stack_label(kind: String, count: int) -> String:
	if count <= 1:
		return display_name(kind)
	return "%d %s" % [count, def(kind).get("short", display_name(kind))]


## Whether two stacks of this kind merge into one hand slot.
static func stacks(kind: String) -> bool:
	return is_consumable(kind) or bool(def(kind).get("stack", false))


## How many of a fragile stack survive a drop. Roughly a third breaks, never the whole stack.
static func survivors_after_drop(kind: String, count: int) -> int:
	if not is_fragile(kind) or count <= 1:
		return count
	var broken := maxi(1, int(floor(count / 3.0)))
	return maxi(1, count - broken)
