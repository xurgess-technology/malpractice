extends SceneTree
## POCKETS: measures how often a shift actually gets a pocket space, over many run seeds and
## several shifts each. The roll is per shift (the plan is rolled with the wings), so a run seed
## alone is not a sample: shift 1 of seed 5 and shift 3 of seed 5 roll separately.
##
##   godot --headless --path . --script tools/pocketrate.gd [-- --seeds=500 --shifts=4 --first=1]
##
## Prints the overall rate, the rate per shift number, the split by kind, and how many rolls
## wanted a pocket but found nowhere to put one (those still count as "no pocket" in the rate,
## which is what docs/POCKET_SPACES_2.md means by "shifts getting a pocket").

const MG := preload("res://scripts/mapgen.gd")
const Plan := preload("res://scripts/level/pockets/pocket_plan.gd")

var first_seed := 1
var seed_count := 500
var shift_count := 4


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		if kv.size() < 2:
			continue
		match kv[0]:
			"seeds": seed_count = int(kv[1])
			"shifts": shift_count = int(kv[1])
			"first": first_seed = int(kv[1])
	var t0 := Time.get_ticks_msec()
	Plan.force_kind = ""
	var total := 0
	var got := 0
	var kinds := {}
	var per_shift := {}
	var wanted_but_failed := 0
	for seed in range(first_seed, first_seed + seed_count):
		for gn in range(1, shift_count + 1):
			# `last_failure` is only written when a roll wanted a pocket, so clear it first or a
			# stale one from an earlier seed reads as this seed's.
			Plan.last_failure = ""
			var gen: Dictionary = MG.generate(seed, MG.wing_seed_for(seed, gn))
			var plan := Plan.of(gen)
			total += 1
			if not per_shift.has(gn):
				per_shift[gn] = [0, 0]
			per_shift[gn][1] += 1
			if plan.is_empty():
				if Plan.last_failure != "":
					wanted_but_failed += 1
				continue
			got += 1
			per_shift[gn][0] += 1
			var k := String(plan.get("kind", "?"))
			kinds[k] = int(kinds.get(k, 0)) + 1
	var pct := 100.0 * float(got) / maxf(1.0, float(total))
	print("")
	print("pocket rate: %d of %d shifts = %.1f%%  (%d seeds x %d shifts)" % [got, total, pct, seed_count, shift_count])
	print("  by kind: %s" % str(kinds))
	var shifts := per_shift.keys()
	shifts.sort()
	for gn in shifts:
		var e: Array = per_shift[gn]
		print("  shift %d: %d/%d = %.1f%%" % [gn, e[0], e[1], 100.0 * float(e[0]) / maxf(1.0, float(e[1]))])
	print("  rolls that wanted a pocket and found no room: %d" % wanted_but_failed)
	print("  in band 20-30%%: %s" % ("YES" if pct >= 20.0 and pct <= 30.0 else "NO"))
	print("took %d ms" % (Time.get_ticks_msec() - t0))
	quit(0 if pct >= 20.0 and pct <= 30.0 else 1)
