class_name DbRecord
extends RefCounted
## One species' record in the host's monster database (docs/CONTRACTS.md "Abilities" ->
## "The database terminal", sweep 4a chunk 4). `sighted` (seen by any player, in range, with
## line of sight), `scanned` (a player held R on it long enough) and `harvested` (a body part of
## this species was extracted on a table, or grafted into a surgeon) gate the
## terminal's three tiers. Host-only; DatabaseStore (scripts/database/database_store.gd) saves
## and loads the whole set to disk under user://, so it survives a wipe and a reload.

var kind: String = ""
var sighted: bool = false
var scanned: bool = false
var harvested: bool = false


func _init(k: String = "") -> void:
	kind = k


func to_dict() -> Dictionary:
	return {"sighted": sighted, "scanned": scanned, "harvested": harvested}


func from_dict(d: Dictionary) -> void:
	sighted = bool(d.get("sighted", false))
	scanned = bool(d.get("scanned", false))
	harvested = bool(d.get("harvested", false))
