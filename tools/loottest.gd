extends SceneTree
## The loot kinds and where they turn up. Builds the hospital for a few seeds (no game session) and
## plans each shift's loot on it.
##
##   godot --headless --path . -s tools/loottest.gd [-- --seeds=1,2,3 --report]
##
## Checks: no cut kind is left in the loot table or its models; every kept kind has a model; every
## room kind that had loot before the cut still gets loot; trinkets are rarer than plain loot;
## every shift holds LootSpawner.LOOT_PER_SHIFT stacks; and (POCKETS 2) a pocket space's own items
## bleed into the hospital only in the rooms around one of its entrances, only when that space
## actually spawned, only the kinds flagged `may_bleed`, and only by taking a stack the hospital
## would otherwise have had.
## --report also prints each seed's total loot value and the kinds and rooms it landed in.
## Exits 0 when every check passes.

const MG := preload("res://scripts/mapgen.gd")
const HB := preload("res://scripts/hospital_builder.gd")
const LootTable := preload("res://scripts/economy/loot_table.gd")
const LootSpawner := preload("res://scripts/economy/loot_spawner.gd")
const LootModels := preload("res://scripts/economy/loot_models.gd")
const PocketBleed := preload("res://scripts/economy/pocket_bleed.gd")
const PocketPlan := preload("res://scripts/level/pockets/pocket_plan.gd")

const CUT := ["stethoscope", "thermometer", "bp_cuff", "otoscope", "patient_records", "wheelchair_wheel",
	"sample_rack", "wedding_ring", "coffee_maker", "iv_pump", "microscope"]
const KEPT := ["pill_bottle", "xray_film", "heart_monitor", "gold_watch", "ultrasound",
	"desk_phone", "laptop", "defibrillator", "reflex_hammer", "epipen", "pulse_oximeter",
	# POCKETS 2: the pocket spaces' own kinds. Unlike everything above they list no "*" room
	# weight, so they never turn up in the hospital — see POCKET_ONLY below.
	"pool_chemical_drum", "lifeguard_whistle",
	"votive_candle", "collection_plate",
	"quarter_bucket", "warm_scrubs", "fabric_softener"]
const TRINKETS := ["desk_phone", "laptop", "defibrillator", "reflex_hammer", "epipen", "pulse_oximeter",
	"lifeguard_whistle", "fabric_softener", "votive_candle"]
## POCKETS 2: kinds that belong to one pocket space, and the room kinds of the space each belongs to.
## They are exempt from the "must be findable in the hospital" rules below and checked the other way
## round instead. A new space's POCKET_ITEMS go here. (Spelt out rather than read from the layout
## scripts: this test runs with `-s`, where pulling in the pocket runtime would drag in autoloads it
## does not have.)
##
## These still say what they always said: none of them may ever *roll* in a hospital room, whatever
## the room kind and however deep. The bleed (scripts/economy/pocket_bleed.gd) does not change that
## and must not be mistaken for it -- it never touches a `rooms` weight. It is a swap made after the
## plan already exists, gated on the room being a few rooms from a seam, and it is checked on its
## own in `_bleed_checks` below.
const POCKET_ONLY := {
	"pool_chemical_drum": ["natatorium_deck", "natatorium_lockers"],
	"lifeguard_whistle": ["natatorium_deck", "natatorium_lockers"],
	"votive_candle": ["chapel_nave", "chapel_aisle", "chapel_sanctuary", "chapel_sacristy"],
	"collection_plate": ["chapel_nave", "chapel_aisle", "chapel_sanctuary", "chapel_sacristy"],
	"quarter_bucket": ["laundromat", "laundromat_back"],
	"warm_scrubs": ["laundromat", "laundromat_back"],
	"fabric_softener": ["laundromat", "laundromat_back"],
}
## POCKETS 2: which of a space's kinds may bleed out near an entrance. Spelt out here for the same
## reason as POCKET_ONLY, and checked against the table's own `may_bleed` flags.
const BLEEDS := {
	"natatorium": ["lifeguard_whistle", "pool_chemical_drum"],
	"chapel": ["collection_plate", "votive_candle"],
	# warm_scrubs is deliberately absent: it is a permanent cosmetics unlock, and finding one in a
	# corridor would devalue the space it belongs to.
	"laundromat": ["fabric_softener", "quarter_bucket"],
	# The Factory and the Restaurant contribute no loot kinds at all, so they bleed nothing.
	"factory": [],
	"restaurant": [],
}
## Room kinds the loot could turn up in before the cut (the union of the old table's `rooms`).
const OLD_ROOMS := ["ward", "patient_room", "nurse_station", "office", "corridor", "waiting_room", "pharmacy",
	"restroom", "radiology", "storage", "maintenance", "janitor", "lab", "morgue", "break_room", "cafeteria"]

var seeds: Array = [1, 2, 3]
var report := false
var failures: Array = []
var checks := 0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a == "--report":
			report = true
		elif a.begins_with("--seeds="):
			seeds = []
			for s in a.trim_prefix("--seeds=").split(","):
				seeds.append(int(s))
	_static_checks()
	var by_room := {}       # room kind -> stacks over every seed
	var places := {}        # room kind -> free locations over every seed (what the spawner could fill)
	var by_kind := {}
	var total_value := 0
	var total_stacks := 0
	var trinket_stacks := 0
	var trinket_kinds := {}
	var shift_trinkets: Array = []   # trinkets in each planned shift
	var shift_stacks: Array = []     # stacks in each planned shift
	var shift_defibs_max := 0
	var radiology_seeds := 0
	for sd in seeds:
		var info := {}
		var gen: Dictionary = MG.generate(sd)
		var level: Node3D = HB.build(gen, info)
		var seed_value := 0
		var seed_stacks := 0
		var rad_hit := false
		for shift in [1, 2, 3]:
			var rooms_of := {}
			var st := 0
			var defibs := 0
			var stacks := 0
			for loc in LootSpawner._locations(info, {}):
				places[loc.room_kind] = int(places.get(loc.room_kind, 0)) + 1
				rooms_of[loc.key] = loc.room_kind
			for e in LootSpawner.plan(sd, shift, info, {}):
				var kind := String(e.kind)
				seed_value += int(e.value)
				seed_stacks += 1
				stacks += 1
				by_kind[kind] = int(by_kind.get(kind, 0)) + 1
				if TRINKETS.has(kind):
					trinket_stacks += 1
					st += 1
					trinket_kinds[kind] = int(trinket_kinds.get(kind, 0)) + 1
				if kind == "defibrillator":
					defibs += 1
				var key := "%s:%d" % [e.container_id, int(e.slot)] if String(e.container_id) != "" else "anchor:%05d" % int(e.anchor)
				var room := String(rooms_of.get(key, "?"))
				by_room[room] = int(by_room.get(room, 0)) + 1
				if room == "radiology" and (kind == "xray_film" or kind == "ultrasound"):
					rad_hit = true
			shift_trinkets.append(st)
			shift_stacks.append(stacks)
			shift_defibs_max = maxi(shift_defibs_max, defibs)
		if rad_hit:
			radiology_seeds += 1
		total_value += seed_value
		total_stacks += seed_stacks
		if report:
			print("seed %d: %d stacks, $%d over shifts 1-3 (avg $%d a shift)" % [sd, seed_stacks, seed_value, seed_value / 3])
		level.free()
	var kinds_sorted := by_kind.keys()
	kinds_sorted.sort()
	if report:
		print("kinds: ", by_kind)
		print("rooms: ", by_room)
		print("places: ", places)
		print("trinkets per shift: ", shift_trinkets, " by kind (all shifts): ", trinket_kinds)
		print("TOTAL $%d in %d stacks over %d seeds x 3 shifts; trinkets %d" % [total_value, total_stacks, seeds.size(), trinket_stacks])
	for k in CUT:
		_check(not by_kind.has(k), "no %s in any plan" % k)
	var in_range := true
	for n in shift_trinkets:
		in_range = in_range and n >= 3 and n <= 5
	_check(in_range, "every shift has 3 to 5 trinkets in total %s" % str(shift_trinkets))
	var lo := int(LootSpawner.LOOT_PER_SHIFT[0])
	var hi := int(LootSpawner.LOOT_PER_SHIFT[1])
	var counts_ok := true
	for n in shift_stacks:
		counts_ok = counts_ok and n >= lo and n <= hi
	_check(counts_ok, "every shift holds %d to %d loot stacks %s" % [lo, hi, str(shift_stacks)])
	_check(shift_defibs_max <= 1, "at most one defibrillator a shift (%d)" % shift_defibs_max)
	_check(radiology_seeds * 2 > seeds.size(), "radiology gets X-ray film or an ultrasound on most seeds (%d of %d)" % [radiology_seeds, seeds.size()])
	for r in OLD_ROOMS:
		if int(places.get(r, 0)) > 0:
			_check(int(by_room.get(r, 0)) > 0, "room kind '%s' gets loot (%d places, %d stacks)" % [r, int(places.get(r, 0)), int(by_room.get(r, 0))])
		else:
			print("(no '%s' locations on these seeds)" % r)
	_bleed_checks()
	print("[loottest] result=%s checks=%d failures=%d" % ["PASS" if failures.is_empty() else "FAIL", checks, failures.size()])
	for f in failures:
		print("  failed: ", f)
	quit(0 if failures.is_empty() else 1)


func _static_checks() -> void:
	for k in CUT:
		_check(not LootTable.has(k), "%s is not in the loot table" % k)
	for k in KEPT:
		_check(LootTable.has(k), "%s is in the loot table" % k)
		var root := Node3D.new()
		LootModels.build(root, k, 1)
		_check(root.get_child_count() > 0 and LootModels.footprint(k) != Vector3(0.15, 0.1, 0.15), "%s has a model and a footprint" % k)
		root.free()
		# Every place a kept kind may turn up is a real room kind or the catch-all.
		_check(not (LootTable.LOOT[k].rooms as Dictionary).is_empty(), "%s has rooms" % k)
	# POCKETS 2: a pocket space's kinds are found in that space and nowhere else, which is exactly
	# "its own room kinds have a weight and there is no `*` catch-all".
	for k in POCKET_ONLY.keys():
		var rooms: Dictionary = LootTable.LOOT[k].rooms
		_check(not rooms.has("*"), "%s has no catch-all room weight, so it stays in its pocket" % k)
		var found := false
		for room in POCKET_ONLY[k]:
			found = found or float(rooms.get(room, 0.0)) > 0.0
		_check(found, "%s is found in %s" % [k, " / ".join(POCKET_ONLY[k])])
		for hospital_room in ["corridor", "office", "patient_room", "supply_closet"]:
			_check(LootTable.weight(k, hospital_room, 3) <= 0.0,
				"%s is not found in a deep hospital %s" % [k, hospital_room])
	# The table holds only the kept kinds plus the grafting parts.
	for k in LootTable.kinds():
		var d: Dictionary = LootTable.LOOT[k]
		_check(KEPT.has(k) or d.get("eye", false) or k == "specimen_vat", "%s is a kept kind" % k)


func _check(ok: bool, what: String) -> void:
	checks += 1
	if not ok:
		failures.append(what)
		print("FAIL  ", what)


## POCKETS 2: the bleed. Forces each space onto a hospital in turn and checks where its items landed.
func _bleed_checks() -> void:
	for space in PocketPlan.KINDS:
		_check(LootTable.bleeding_kinds(space) == BLEEDS[space],
			"%s bleeds %s" % [space, str(BLEEDS[space])])
	for k in POCKET_ONLY.keys():
		var owner_space := String(LootTable.LOOT[k].get("pocket", ""))
		_check(BLEEDS.has(owner_space)
				and (BLEEDS[owner_space] as Array).has(k) == bool(LootTable.LOOT[k].get("may_bleed", false)),
			"%s knows which space it belongs to (%s)" % [k, owner_space])
	var bled_total := 0
	var shifts := 0
	var near_rooms: Array = []
	for space in PocketPlan.KINDS:
		var want: Array = BLEEDS[space]
		PocketPlan.force_kind = String(space)
		for sd in seeds:
			var info := {}
			var gen: Dictionary = MG.generate(sd)
			var level: Node3D = HB.build(gen, info)
			if PocketBleed.pocket_kind(info) != String(space):
				level.free()
				continue   # this seed found nowhere to put the space; nothing to say about it
			var near := PocketBleed.seam_tiles(info)
			var width := int((info.get("size", Vector2i.ZERO) as Vector2i).x)
			_check(not near.is_empty(), "%s on seed %d has rooms near its seams" % [space, sd])
			near_rooms.append(PocketBleed.seam_rooms(info).size())
			for shift in [1, 2, 3]:
				var entries: Array = LootSpawner.plan(sd, shift, info, {})
				_check(entries == LootSpawner.plan(sd, shift, info, {}),
					"%s seed %d shift %d plans the same twice" % [space, sd, shift])
				shifts += 1
				var bled := 0
				var stacks := 0
				var trinkets := 0
				for e in entries:
					stacks += 1
					var kind := String(e.kind)
					if LootTable.is_trinket(kind):
						trinkets += 1
					if String(LootTable.LOOT[kind].get("pocket", "")) == "":
						continue
					bled += 1
					bled_total += 1
					_check(want.has(kind), "%s: %s is a kind that may bleed" % [space, kind])
					_check(bool(e.get("bled", false)), "%s: the %s that got out is marked as bled" % [space, kind])
					var pos := _pos_of(info, e)
					var tile := int(floor(pos.z / C.TILE)) * width + int(floor(pos.x / C.TILE))
					_check(near.has(tile), "%s: the %s that got out is in a room near a seam" % [space, kind])
				_check(bled <= int(PocketBleed.BLEED_PER_SHIFT[1]),
					"%s seed %d shift %d bled at most %d stacks (%d)" % [space, sd, shift, int(PocketBleed.BLEED_PER_SHIFT[1]), bled])
				# The bleed is a swap, so the shift is still exactly as big as it always was.
				_check(stacks >= int(LootSpawner.LOOT_PER_SHIFT[0]) and stacks <= int(LootSpawner.LOOT_PER_SHIFT[1]),
					"%s seed %d shift %d still holds %d stacks" % [space, sd, shift, stacks])
				_check(trinkets >= int(LootTable.TRINKETS_PER_SHIFT[0]) and trinkets <= int(LootTable.TRINKETS_PER_SHIFT[1]),
					"%s seed %d shift %d still holds %d trinkets" % [space, sd, shift, trinkets])
			level.free()
	# A shift without a pocket bleeds nothing: the 0.10.36 guard is untouched.
	PocketPlan.force_kind = "none"
	for sd in seeds:
		var info := {}
		var gen: Dictionary = MG.generate(sd)
		var level: Node3D = HB.build(gen, info)
		_check(PocketBleed.pocket_kind(info) == "", "seed %d really has no pocket" % sd)
		_check(PocketBleed.seam_tiles(info).is_empty(), "seed %d has no rooms near a seam" % sd)
		for shift in [1, 2, 3]:
			var leaked: Array = []
			for e in LootSpawner.plan(sd, shift, info, {}):
				if String(LootTable.LOOT[String(e.kind)].get("pocket", "")) != "":
					leaked.append(String(e.kind))
			_check(leaked.is_empty(), "seed %d shift %d without a pocket leaks nothing %s" % [sd, shift, str(leaked)])
		level.free()
	PocketPlan.force_kind = ""
	# If this ever reads 0 the feature is dead and every check above is passing on an empty set.
	_check(bled_total > 0, "the spaces bled at all over these seeds (%d stacks)" % bled_total)
	if report:
		print("bleed: %d stacks over %d shifts with a pocket; rooms near a seam per hospital: %s" % [bled_total, shifts, str(near_rooms)])


## Where a planned entry ended up, from the level's own containers and anchors.
func _pos_of(info: Dictionary, e: Dictionary) -> Vector3:
	if e.has("position"):
		return e.position
	if String(e.get("container_id", "")) != "":
		for c in info.get("containers", []):
			if String(c.get("id", "")) == String(e.container_id):
				return c.get("position", Vector3.ZERO)
	var anchors: Array = info.get("loose_anchors", [])
	var i := int(e.get("anchor", -1))
	return anchors[i].position if i >= 0 and i < anchors.size() else Vector3.ZERO
