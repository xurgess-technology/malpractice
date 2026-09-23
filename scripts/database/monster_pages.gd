extends RefCounted
## Static content for the database terminal's Monsters section (docs/SWEEP4A.md "Chunk 4").
## Not derived from game data (there is no shared "monster kind" registry yet), so this is the
## one place that lists every huntable species. Add a new monster kind here when one is added.
##
## Each entry: {kind, name, silhouette (a rough humanoid shape descriptor for the terminal's
## silhouette/X-ray drawing), behaviour, senses, threat, doses, brain_site, ability, growth_site}

const ENTRIES := {
	"hive": {
		"name": "The Hive",
		"height": 1.75,
		"hunch": 0.12,
		"behaviour": "Wanders the wings until it hears something. Investigates noise, loses interest if nothing follows.",
		"senses": "Hearing only. Footsteps at a walk make no noise it can pick up; running, dropped items and shoves do.",
		"threat": "Low alone. Dangerous in groups or once it has found you and closed the distance.",
		"doses": "About 2 doses of anesthetic to bring it under and keep it there for a full harvest.",
		"brain_site": "Skull, centre, just above eye level.",
		"ability": "Hive Eyes",
		"growth_site": "",
	},
	"sonographer": {
		"name": "The Sonographer",
		"height": 1.82,
		"hunch": 0.05,
		"behaviour": "A doctor who went blind and kept working. Clicks as it walks, stops dead to listen when it hears something, and rushes the spot. Its neck lengthens the more suspicious it gets.",
		"senses": "Hearing only. Standing still and stone quiet is the only way to lose it once it is close.",
		"threat": "High. Hits hard, keeps coming. Sedate it before it closes the distance.",
		"doses": "About 3 doses of anesthetic; it fights the sedative longer than a Hive.",
		"brain_site": "Skull, set slightly further back than a Hive's.",
		"ability": "Echo",
		"growth_site": "",
	},
	"night_nurse": {
		"name": "The Night Nurse",
		"height": 2.3,
		"hunch": 0.0,
		"behaviour": "Only moves while nobody is watching her. Freeze, and she freezes.",
		"senses": "Sight, in a way nothing else in the building has. Being seen is what stops her.",
		"threat": "Unknown. Nobody has gotten close enough, on purpose, to say.",
		"doses": "Unknown. She has never been strapped to a table.",
		"brain_site": "Unknown.",
		"ability": "",
		"growth_site": "unknown",
	},
	# POCKETS 2 phase 6. It caps at tier 2 and needs no special case to do it: tier 3 is `harvested`,
	# harvesting is a brain out of a strapped body, and this one is neither capturable nor
	# huntable -- so the bit is never set and the page never opens past SCANNED. Same as the Night
	# Nurse, for the same reason, which is why her entry reads like this one.
	"onlooker": {
		"name": "The Onlooker",
		"height": 2.65,
		"hunch": 0.0,
		"behaviour": "Found only in the rooms that should not fit in the building. It appears at a distance, already facing you, and does not move. Given long enough it takes something out of you. Walking at it is the only thing that has ever made it leave.",
		"senses": "Attention. Being looked at is what feeds it, which is the opposite of the Night Nurse in every way that matters.",
		"threat": "It cannot be fought. It can be sent away.",
		"doses": "None. It has never been sedated; there is nothing to sedate.",
		"brain_site": "Unknown.",
		"ability": "",
		"growth_site": "unknown",
	},
}

const ORDER := ["hive", "sonographer", "night_nurse", "onlooker"]


static func entry(kind: String) -> Dictionary:
	return ENTRIES.get(kind, {})
