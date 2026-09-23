class_name Syringes
extends RefCounted
## SYRINGE DRAW (docs/ANESTHETIC_INJECTION_SPEC.md 9): what a loaded syringe is carrying.
##
## The syringe is the ordinary consumable item `syringe`. What is IN it is the stack's / world
## item's `x` string, exactly the way a specimen vat carries its eye (scripts/grafting/vats.gd's
## header explains the trick): the string rides every existing carry / drop / shelf / snapshot path
## with no new replication, because nothing along those paths knows or cares what it means.
##
## ONE LOADED SYRINGE PER SLOT. A slot has one `x`, and a batch of three syringes shares that slot,
## so the loaded one is the top of the batch. You cannot walk around with three different doses in
## one hand; draw one, stick it, draw the next. That is also what makes a syringe "one use, then
## spent": injecting takes one off the count and clears `x`.
##
## The format is "fluid|level|bubbles" ("" = an empty syringe):
##   fluid     the item kind drawn from (`anesthetic` today; COMMUNION WINE and TEQUILA when
##             docs/POCKET_SPACES_2.md phases 3 and 5 land)
##   level     0..1 of the barrel, to three decimals. THE ABSOLUTE LEVEL, not a score.
##   bubbles   the radii (rpx, one decimal) still in the barrel when FLICK! was left, comma
##             separated; empty when it was flicked clean. These are inject_arcade's `carried`.
##
## WHY THE LEVEL AND NOT A DOSE. The green band on the barrel is placed by the PATIENT'S WEIGHT
## (inject_arcade.build_game), and a corridor has no patient. So a syringe loaded away from the
## table aims at a STANDARD DOSE -- the reference band, REFERENCE_WEIGHT_KG -- and stores the raw
## level it actually reached. At the table the real band is worked out from the real patient and
## the stored level is scored against it, unchanged. Pre-loading therefore buys time and costs
## precision: a standard dose is a little light for a heavy patient and heavy for a light one, and
## the syringe has no idea which it is about to meet. That is the trade, and it is deliberate.

## The weight the standard dose is drawn for, kg. inject_arcade uses the real patient's weight when
## there is one and this when there is not.
const REFERENCE_WEIGHT_KG := 80.0

## Item kinds that can be drawn from. All three are built now: `anesthetic`, the Chapel's
## communion wine (phase 3) and the Restaurant's tequila (phase 5). The rack needed no change for
## either alcohol -- it populates itself from what the player is carrying.
##
## HOW WEAK a substitute is does NOT live here. It is `Items.ANESTHETIC_KINDS`, applied once in
## `game.gd` where the step is completed, and this file deliberately knows nothing about it: a
## syringe drawn from wine is still wine, and reading the fluid there (before `spend_loaded` clears
## it) is what stops loading a substitute into a barrel from laundering it into a full dose.
const FLUIDS := ["anesthetic", "communion_wine", "tequila"]


## True when `kind` is something a syringe can be loaded from.
static func is_fluid(kind: String) -> bool:
	return FLUIDS.has(kind)


## Pack what a syringe is carrying. `bubbles` is inject_arcade's `carried` (radii in rpx).
static func pack(fluid: String, level: float, bubbles: Array) -> String:
	if fluid == "" or level <= 0.0:
		return ""
	var parts := PackedStringArray()
	for b in bubbles:
		parts.append("%.1f" % float(b))
	return "%s|%.3f|%s" % [fluid, clampf(level, 0.0, 1.0), ",".join(parts)]


## The other way. {} for an empty syringe or anything unreadable, else
## {fluid: String, level: float, bubbles: Array of float}.
static func unpack(x: String) -> Dictionary:
	if x == "":
		return {}
	var p := x.split("|")
	if p.size() < 3 or not is_fluid(p[0]):
		return {}
	var level := float(p[1])
	if level <= 0.0:
		return {}
	var bubbles: Array = []
	if p[2] != "":
		for s in p[2].split(","):
			bubbles.append(float(s))
	return {"fluid": p[0], "level": clampf(level, 0.0, 1.0), "bubbles": bubbles}


static func is_loaded(x: String) -> bool:
	return not unpack(x).is_empty()


## What the HUD and the crosshair call a loaded syringe: "Syringe of anesthetic (62%)".
static func label(x: String) -> String:
	var d := unpack(x)
	if d.is_empty():
		return "Empty syringe"
	return "Syringe of %s (%d%%)" % [fluid_name(String(d.fluid)), roundi(float(d.level) * 100.0)]


## ARRIVING AT THE TABLE WITH ONE ALREADY LOADED. The step still asks for `anesthetic` -- turning
## up empty-handed with a vial is the fallback and it stays exactly as it was. A loaded syringe is
## accepted INSTEAD of it: the dose is already in the barrel, so the step opens on STICK! and the
## two loading stages are simply skipped (inject_arcade's `loaded` context).
static func accepts_loaded(step: Dictionary) -> bool:
	return String(step.get("game", "")) == "anesthetic" and String(step.get("item", "")) == "anesthetic"


## The loaded syringe in `p`'s selected hand, or {}. {slot: int, fluid, level, bubbles}.
static func held_loaded(p) -> Dictionary:
	if p == null or not is_instance_valid(p) or not p.has_method("selected_stack"):
		return {}
	var s: Dictionary = p.selected_stack()
	if String(s.get("kind", "")) != "syringe" or int(s.get("count", 0)) < 1:
		return {}
	var d := unpack(String(s.get("x", "")))
	if d.is_empty():
		return {}
	d["slot"] = int(p.selected_head())
	return d


## Host: the loaded syringe `p` just emptied into a patient is spent -- one off the count, and the
## `x` cleared so the next one out of the batch is empty. That is what makes a syringe one-use.
## Does nothing (and says so) when they were not holding one.
static func spend_loaded(p) -> bool:
	var d := held_loaded(p)
	if d.is_empty():
		return false
	var i := int(d.slot)
	# Clear `x` first: a partial consume leaves the stack (and its `x`) behind.
	p.slots[i]["x"] = ""
	if p.has_method("consume_hand"):
		p.consume_hand("syringe", 1)
	return true


## The fluid's display name, lower case, for prose.
static func fluid_name(fluid: String) -> String:
	match fluid:
		"communion_wine": return "communion wine"
		"tequila": return "tequila"
	return "anesthetic"
