# TASK: Pocket spaces sweep 2 — future plans

Read this whole document first. Save it as docs/POCKET_SPACES_2.md and
keep it updated as the source of truth. Follow docs/POCKET_SPACES.md
for how pockets, stubs and seams work — the seam system itself does
not change in this sweep.

## Hard constraints
- Do NOT modify the Factory or Restaurant scene geometry.
- New items use existing systems only (loot/sell, trinkets, sedation
  doses, footstep noise, cosmetics unlocks, charged throw). Anything
  needing a system that doesn't exist yet is marked TODO here — spawn
  and sell the item now, wire the behavior when its system lands.
- CC0 assets only, through Assets, recorded in ASSETS.md. Register
  everything in scripts/warmup.gd. Update docs/CONTRACTS.md and the
  database terminal entries.
- Hold the perf bar from POCKET_SPACES.md (60 fps, 1% lows > 50,
  Radeon 890M medium). Check with tools/perfprobe.
- Commit per phase. If a phase is blocked, skip it, note why in
  docs/MORNING_REPORT.md, and continue.

## Phase 1 — system changes — DONE 2026-09-22, branch `pockets-phase1`
1. RECONCILE THE ROLL. **Done.** PocketPlan rolled CHANCE = 0.5 flat;
   the design doc says higher odds in deeper wings. Every wing now
   rolls `BASE_CHANCE + DEPTH_STEP * (depth - 1)` and the map takes
   the chance any of them lands, capped at `MAX_CHANCE`. Those three
   are the tunables, in `pocket_plan.gd`. At 0.04 / 0.05 / 0.45 the
   usual depths 1-3 give 4% / 9% / 14%.
   **Measured, not reasoned**: `tools/pocketrate.gd` (new) generates
   many seeds x many shifts, prints the real rate, and exits non-zero
   if it leaves the band. Before the change, 300 seeds x 4 shifts
   gave **46.6%**. After, three sweeps:
   - seeds 1-300 x 4 shifts (1200 shifts): **24.5%**
   - seeds 1-500 x 4 shifts (2000 shifts): **23.9%**
   - seeds 2001-2400 x 4 shifts (1600, disjoint): **27.2%**

   **25.4% over 4800 shifts** all told, with every individual shift
   number also inside 20-30%, and not one roll that wanted a pocket
   failing to find room for it. Re-run it after any change to the
   curve.
2. NO REPEATS. **Done.** `game.pocket_seen_kind` holds the kind the
   run last saw; `_to_next_shift` copies it into
   `PocketPlan.exclude_kind` before the wings regenerate, and
   `pool()` drops it from the roll. It is replicated in the globals
   as `"px"` and applied in `_repl_apply` before anything generates —
   clients build their own copy of the map, so a client rolling from
   a different pool would build a *different hospital*. Reset in
   `start_session`. `force_kind` still overrides it, for tools.
3. AMBIENT NOISE FLOOR. **Done.** A pocket layout script may declare
   `AMBIENT_NOISE_LEVEL`; `PocketSpaces.ambient_noise_at(pos)` reads
   it. The Sonographer — the only monster that hears, the Hive being
   deaf and the Night Nurse never listening — subtracts it from each
   noise's loudness before the existing reach maths in `_hear`, so a
   loud room masks quiet noises outright and loud ones simply do not
   carry as far. No new sound system: it rides the loudness values
   that already exist. Factory and Restaurant both declare 0.0, and
   at 0.0 the subtraction is identity and the noise dictionary is not
   even copied, so their behaviour is unchanged by construction as
   well as by test.
   **This is what phase 4 is built on**: the Laundromat's drone is
   this knob and nothing else.
4. FIX: monsters wandering into pockets via random nav. **Done.**
   `game.monster_may_wander_to(p, from)` now takes where the monster
   stands and rejects a goal in another space, or in a stub's dead
   half. See "How idle wander is fenced" below.
5. Seam light-mirroring and Hive-sight stay known issues. **Done** —
   KNOWN_ISSUES now says they are properties of the seam, not of any
   one space, so they apply to five spaces once phases 2-4 land.

### How idle wander is fenced
The leak was never the seam. `Monster.random_nav_point` samples
`NavigationServer3D.map_get_random_point` over the **whole**
navigation map, and the pocket's region is part of that map, so a
hospital monster could draw a goal 800 tiles away and walk to it; the
other half of its picks come from `level_info.monster_spawns`, which
the pocket also appends to. The Night Nurse's vanish made it worse by
asking for a point up to 400 m away.

The fence is one predicate, not three patches: a wander goal must be
in the same space as the monster. `monster_may_wander_to` gained an
optional `from`, and the two samplers (`Monster.random_nav_point`,
`HiveBrain._home_point`) pass the monster's own position. Goals in a
stub's dead half are rejected too, since that half *is* the other
copy. Fencing at the predicate rather than in the samplers covers all
three brains at once, the Night Nurse's vanish included.

What deliberately still works: **spawning** inside a pocket (spawn
points do not come through this predicate) and **chasing** a player
through a seam (a chase steers at the quarry, not at a wander goal).

### What phase 1 was tested with
- `tools/pocketrate.gd` — the rates above, plus a direct no-repeats
  check: **470 pockets rolled with a kind excluded, 0 of them the
  excluded kind**.
- `tools/pockettest.tscn` — **PASS, 208 checks**, including new ones
  for the noise floor (declared 0.0, 0.0 inside the space, 0.0 in the
  hospital) and the fence (refused both ways across a seam, allowed
  within a space, refused into every stub's dead half, and unchanged
  when called without a `from`). It fails intermittently on the
  pre-existing Night Nurse check — see FAILING_TESTS 1f, which phase
  1 turned from a deterministic failure into a coin flip and did not
  fix.
- `tools/mapcheck.gd` — the pockets section passes on 300 seeds
  (341/341 forced placements). Its morgue-tray failures are the
  pre-existing ones; the seed list moves when the pocket rate moves,
  which is written up in FAILING_TESTS 2.
- **`tools/perfprobe` was not run, deliberately.** It needs a real
  window to give honest frame times, and a minimized one does not
  render. Phase 1 changes no geometry, no lights and no materials —
  the added cost is one `Rect2.has_point` plus a cached dictionary
  lookup per sound-hunting monster per tick, and one `space_of` and
  `phantom_at` per wander-goal candidate, which are picked rarely.
  Nothing there can move a frame-time percentile. **Phases 2-4 do add
  geometry and must run it.**

### Notes for the later phases
- A new space declares `AMBIENT_NOISE_LEVEL` in its layout script and
  gets a floor; declaring nothing means 0.0.
- Add its kind to `PocketPlan.KINDS` and to
  `PocketSpaces.ambient_noise_of`'s match. With five kinds the
  no-repeat exclusion costs far less variety than it does with two.
- The curve is a *per-wing* chance, so adding kinds does not need it
  retuned — the rate is how often *a* pocket appears, not which one.
  Re-run `tools/pocketrate.gd` anyway.

## Phase 2 — the Natatorium — DONE 2026-09-22, branch `pockets-natatorium`
An indoor Olympic pool that can't fit in a one-story hospital.
Underwater lights on, still water, lane ropes, tile echo. Crossing
the water is the shortcut but loud (big footstep noise while in
water); the dry deck is the long quiet way.
- POOL CHEMICAL DRUM: plain loot, bulky, two hands.
- LIFEGUARD WHISTLE: trinket, one use. A loud blast, visibly from
  the blower, drawing wing monsters to the spot (Echo's attraction
  plumbing, no wall-vision).
- LIFEGUARD STAND FIRST-AID CABINET: container with a guaranteed
  gauze + tourniquet spawn.

### What was built
`scripts/level/pockets/natatorium.gd`. A 72 x 46 m hall under a 9.5 m
ceiling: a 51 x 25.5 m pool (an actual Olympic footprint) with seven
tiles of deck all round, ten lanes of rope, backstroke flags at both
ends, ten starting blocks, three rows of bleachers down the west wall,
two lifeguard stands, a chemical store hugging the south-east walls, and
a locker room through a door in the south wall. Origin (800, 1000).

**The water is the room.** It is not a swimming system and not a volume:
the pool tiles are the same floor plane as the deck, the surface is one
still translucent plane 0.34 m above it, and you wade. `water_rect()` is
the pool in local tiles and `PocketSpaces.water_at(pos)` is the query.

### The one number that matters
Crossing the pool is the short way between two entrances and the deck is
the long way; the water is what makes that a *choice* rather than a free
shortcut. **The loudness was picked against the Sonographer's own maths,
not against itself**: reach is `loudness * HEAR_PER_LOUDNESS` (22 m), and
`LOUD` (0.8) is the line between filling the suspicion meter and dropping
everything to come at the noise.

| | loudness | reach | what it means |
| --- | --- | --- | --- |
| dry walk | 0.25 | 5.5 m | only ever suspicious |
| dry sprint | 0.8 | 17.6 m | certain |
| dry crouch | — | — | no noise event at all |
| **wading, walk** | **0.95** | **~21 m** | **certain** |
| **wading, sprint** | **1.3** | **~29 m** | louder than the Echo shriek |
| **wading, crouch** | **0.55** | **~12 m** | suspicious, never certain |

So the deck is free and slow, wading is fast and gets you found, and
crouch-wading is the negotiated middle — still more than twice a dry
walk, and, unlike dry crouching, **not silence**. You cannot sneak
through water; you can only be quieter about not sneaking. That last row
is the only place in the game where crouching does not buy silence, and
it is deliberate: `game._tick_noise`'s crouch early-out now yields to the
water, and `Player._in_water()` picks a splash cue at both footstep-audio
sites so the player can hear what they are spending.

**No new system.** These are the loudness values `emit_noise` already
carries, decided in the one place footstep loudness was already decided
(`game.gd:_tick_noise`, which held them as inline literals). Phase 1's
note said to confirm how footstep loudness is emitted before designing
around it; it is emitted host-side, once, there.

`AMBIENT_NOISE_LEVEL = 0.0`, as phase 1's notes suggested. Tile echo is
what the room sounds like, not what it hides behind — the Laundromat is
the space that masks — so the water's cost is real rather than quietly
refunded by the room it is paid in.

### The items
- **POOL CHEMICAL DRUM** — plain loot, `bulky`, $45-80. The grip table
  already gives bulky loot a two-handed hold, so it needed no entry.
- **LIFEGUARD WHISTLE** — built as one of the existing trinkets rather
  than invented beside them: in `Trinkets.KINDS` and `ONE_USE`, spent in
  one blow, greyed and cracked, $3 of scrap. One blast at **1.4** — above
  Echo's 1.2, because a whistle is one use and the Echo is not. It is
  **Echo's attraction and nothing else**: a plain `emit_noise` plus the
  `alert_to` loop for the deaf Hive, and *no* `ab_echo` event, which is
  where Echo's wall-vision actually lives (`abilities.gd:_echo` emits
  both; the two were already fully decoupled). The Night Nurse ignores
  it, because `Monster.alert_to` only forwards to brains that have it and
  hers does not — she is not a monster you can call.
- **FIRST-AID CABINET** — a new container type and **the only container
  in the game with guaranteed contents**. `game.stock_first_aid_cabinets()`
  runs each shift before `spawn_loot()` and puts gauze in slot 0 and a
  tourniquet in slot 1, so finding the pocket always pays for the walk to
  the stand. Slot 2 is left to the ordinary spawners, which is where a
  whistle sometimes turns up beside them. It has no rooms in
  `Items.CONTAINER_TYPES`, so nothing ever furnishes a wing with one.

Both loot kinds name only the Natatorium's room kinds
(`natatorium_deck`, `natatorium_pool`, `natatorium_lockers`) and neither
lists `"*"`, so they exist nowhere else in the hospital.

### POCKET_ITEMS — the convention for the bleed-out follow-up
A layout script declares `POCKET_ITEMS`, the item kinds that space
contributes, as a `const` set. **No such convention existed** — the
Factory and the Restaurant contribute no items of their own, so there was
nothing to follow. This is the smallest thing that works, it sits next to
`AMBIENT_NOISE_LEVEL` (the other per-space declaration phase 1 added),
and phases 3 and 4 and the follow-up should match it:

    const POCKET_ITEMS := ["pool_chemical_drum", "lifeguard_whistle"]

### Adding a kind is now two lines
`PocketPlan.KINDS` and the new `PocketSpaces.LAYOUTS`, which every
builder, the warmup and the ambient-noise lookup read. The
`Factory if kind == "factory" else Restaurant` pairs are gone from
`pocket_spaces.gd` and `mapcheck.gd`; `mapcheck`, `looptest`, `pockettest`
and the dev panel work off `KINDS` instead of naming kinds. **Phases 3
and 4 will meet this file at merge** — the changes there are additive
(one dict entry, one origin, one AIR entry each).

### What phase 2 was tested with
- **`tools/pocketrate.gd`** — re-run as phase 1 asked, even though the
  curve is per-wing. **23.9% of 2000 shifts** (500 seeds x 4), every
  individual shift inside 20-30%, exit 0. That is the *same* figure phase
  1 measured for the identical sweep, which is the evidence that adding a
  third kind does not move the rate. No-repeats still clean: 384 pockets
  rolled with a kind excluded, 0 were the excluded kind.
- **`tools/mapcheck.gd`** — 40 seeds forcing the natatorium, 4 built:
  **100% pocket nav coverage, every entrance walks out through its seam,
  nothing stranded**, and only the pre-existing morgue-tray failure
  (FAILING_TESTS 2) left. It earned its keep: it caught a solid row
  between the hall and the locker room, and randomly-placed drums that
  could fence off the south-east deck corner. The drums now hug the walls
  in lines (a line pressed against a wall cannot enclose anything) with
  the corner tile always taken, since that is the one tile two such lines
  can strand.
- **`tools/pockettest.tscn`** — **328 checks**, up from 208, with the
  natatorium in the kind list and a new water section: the pool is water
  and the deck three tiles off it is not, a deck step uses the hospital's
  own numbers, wading is past `LOUD`, crouch-wading is louder than a dry
  walk but not certain, sprinting is louder still, the room masks nothing,
  `POCKET_ITEMS` names two real loot kinds, and the cabinet is stocked
  with gauze and a tourniquet. The only failures are the Night Nurse
  check, **FAILING_TESTS 1f** — and phase 2 pinned down what it actually
  is. It is **not** the coin flip 1f called it: **only the space that runs
  first passes it, and every space after that fails**. Reverse the order
  and the natatorium passes while the Factory and the Restaurant fail. Each
  passes alone. A third space is what made that visible, and 1f now says
  so; it is state left behind by the previous space's shift rebuild, not
  the seam, the distance or any one room. Not phase 2's, and phase 7
  should not be surprised by it.
- **`tools/trinkettest.tscn`** — **PASS, 0 failures**, with a whistle
  section of nine checks: the blast is a real noise event at 1.4, past
  `LOUD`, the near Hive is drawn and one past `WHISTLE_RANGE` is not, the
  Night Nurse is untouched, nothing is revealed through a wall, it is
  spent in one use, and it burns for scrap.
- **`tools/perfprobe`** — run, as phase 1 said phases 2-4 must. Numbers
  below.

### The perf numbers, and why they are relative

**Read the caveat before the table.** Two other agents (phases 3 and 4) were running Godot on this
machine throughout. The size of that is not a guess: the *same* `hospital corridor` scenario measured
**90 fps avg / 58 low** on an idle machine and **24-31 fps** minutes later while they were building.
No absolute number taken in that window can be held against the 60 fps / 50 low bar, and neither the
Factory nor the hospital's own neutral area clears it in that window either.

So phase 2 measured what contention cannot fake: **the Natatorium and the Factory, back to back,
minutes apart, under the same load** (`--quality=1 --frames=180`, 1600x900, Radeon 890M).

| view | avg fps | 1% low | worst ms | draws |
| --- | --- | --- | --- | --- |
| **Factory**: map's hospital corridor | 24 | 14 | 73.2 | 436 |
| **Factory**: hall, corner to corner | 22 | 11 | 109.1 | 356 |
| **Factory**: down a production line | 25 | 14 | 77.7 | 500 |
| **Factory**: an entrance from inside | 31 | 17 | 68.5 | 145 |
| **Factory**: seam, hospital side | 22 | 12 | 97.4 | 193 |
| **Natatorium**: map's hospital corridor | 31 | 21 | 52.2 | 447 |
| **Natatorium**: down the length of the pool | 28 | 21 | 50.1 | 305 |
| **Natatorium**: across the water, lights on | 23 | 20 | 52.6 | 285 |
| **Natatorium**: standing in the pool, looking up | 27 | 21 | 51.2 | 155 |
| **Natatorium**: corner to corner over the bleachers | 27 | 20 | 50.3 | 325 |
| **Natatorium**: an entrance from inside | 34 | 24 | 45.1 | 189 |
| **Natatorium**: seam, hospital side | 34 | 24 | 43.0 | 187 |

**The Natatorium is not a regression against the heaviest space we already ship.** It matches or beats
the Factory on every comparable view, its **1% lows are half again better** (20-24 against 11-17),
its worst frames are tighter (43-53 ms against 68-109 ms) and it draws less (155-325 against 145-500).
The water plane is one mesh, the ropes, flags, trusses and drums are MultiMesh, and only 5 of its 32
lights cast shadows. The view someone will actually stand in most — in the water, looking along it —
is among its cheapest.

For reference, the **uncontended** baseline run (`--quality=1`, no pocket) on the same build:
lobby 74/51, corridor 90/58, pharmacy 93/60, OR 71/60, OR seal close-up 81/65, operating 114/73,
crematorium 54/30, neutral area 44/31, lot facing the fog 58/36. The last three are under the bar on
this machine at this resolution on `main` as well; that is not phase 2's.

**Someone should re-run this on a quiet machine before trusting an absolute number.**

### Two pre-existing things perfprobe hit, neither phase 2's
1. **`perfprobe --pockets` never prints a row on this machine.** It restarts the session once per kind
   and dies in the renderer ("BUG, indexing did not unpair geometries from light", then signal 11).
   Proved not to be the new space: with the natatorium taken out of `PocketPlan.KINDS` and
   `PocketSpaces.LAYOUTS` entirely — the pocket set identical to `main`'s — it crashes in the same
   place with a byte-identical log. Phase 2 therefore added **`--pocket=<kind>`**, which forces the
   kind before the first and only `start_session` and prints its table. (That path still hits the same
   renderer bug on the way out, *after* the numbers are printed, for the Factory as well as for the
   Natatorium.)
2. **`perfprobe` in a GUI window on the `main` checkout** floods `main.gd:673` and `main.gd:707` with
   Nil-property script errors every frame — a 110 MB log and not one measurement. It does not do this
   in a slot, so it is something about that checkout's settings rather than the code, but it is worth
   someone's eye.

### A note on running perfprobe without stealing focus
`tools/perfprobe.ps1` (new) starts it with **SW_SHOWNOACTIVATE (4)**, not
the shot tools' SW_SHOWMINNOACTIVE (7): a minimized window does not
render, and the whole point is honest frame times. The window is drawn
but never activated, so it cannot take the keyboard.

It is **not** moved offscreen. `--position 6000,6000` looked like the
tidy answer and is not — a fully offscreen window's swapchain dies
partway through the run on this Radeon ("Vulkan device was lost", TDR)
and the probe crashes before printing a number. **That reproduces on
`main`**, so it is the offscreen window and not the scenario. The window
is left where it lands and closed when the numbers are in.

## Phase 3 — the Chapel — DONE 2026-09-22, branch `pockets-chapel`
A hospital chapel that is somehow a cathedral: pews for three
hundred, vaulted dark ceiling, every votive candle lit, nobody who
lit them. Candlelight is the room's light.
- VOTIVE CANDLE: trinket, placeable light. Within its radius the
  Night Nurse counts as watched with no player looking. Burns out
  in ~2 minutes.
- COMMUNION WINE: anesthetic substitute, batch of 1, weak dose —
  shorter sedation, stirs sooner. Patients and strapped monsters.
- COLLECTION PLATE: loot, gold-watch tier.

**The space.** `scripts/level/pockets/chapel.gd`. A nave 33 m long under a vault 24 m up that
nothing ever lights, two arcades of stone piers with pointed arches between them, side aisles
ceiled much lower (9 m) so the nave reads tall, thirty-two rows of pews, a sanctuary with an altar
and a reredos of votive tiers, and a sacristy behind the one hinged door. Origin (800, 1500).

**Candlelight is the room's light, and here is how it is paid for.** Every flame in the building is
emissive geometry in a MultiMesh — about 350 votive cups and tapers — and costs no light at all.
Illumination comes from `LIGHT_BUDGET` (26) real `OmniLight3D`s, pooled one per votive rack and one
per candle stand rather than one per flame, of which `SHADOW_BUDGET` (2) cast shadows, which is the
shape the Factory's high bays already had. A build uses 19 of the 26. The sanctuary is built
**before** the racks and the stands precisely so it draws on that budget first and the altar can
never be the thing that goes dark. The lights are real and not the emissive trick 0.10.25 found in
the mirrors, because they have to be: the Night Nurse's rule asks whether a point is **lit**, and
`Perception.fixture_lit` walks `level_info.lights` looking for an `OmniLight3D` named `Bulb`.

**The votive candle satisfies the existing predicate, it does not copy it.** The check lives in
`Perception.observed_any`, ahead of the frustum work **and ahead of the "is anybody alive to look"
early-out** — that ordering is the whole feature, since the point is that a candle watches with
nobody there. Because it is in the predicate rather than in `night_nurse_brain.gd`, it holds
everywhere the predicate is asked, including her own `_vanish()`, which will now not choose a
hiding place inside somebody's candle. Lighting a candle **is** its use: it goes into the world
already spent and worth `SCRAP`, so one candle buys exactly one safe zone in exactly one place and
there is no carrying a lit one to a better spot. It burns `CANDLE_SECONDS` (120) and gutters over
the last twelve, so the thing a player sees when their safe zone dies is the light jumping and
sinking, then `trinkets_candle_out`.

**Communion wine** is `Items.ANESTHETIC_KINDS`, a dictionary of kind -> share of a real dose (wine
0.55). `surgery_system.can_begin` accepts a substitute, the consume spends what was actually held,
and the strength multiplies the sedation the arcade already reported; the strapped-monster re-dose
gets the same factor. **The injection minigame is untouched and does not know the difference** —
that was deliberate, because the syringe/fluid-rack work is happening in parallel. Phase 5's
top-shelf tequila should be one more line in that dictionary.

**Collection plate** is gold-watch tier (3) loot weighted to the Chapel's own room kinds.

**Measured, not reasoned.**
- `tools/pocketrate.gd`, 500 seeds x 4 shifts with three kinds: **23.9%**, in the 20-30% band,
  exit 0. Evenly split (factory 149 / chapel 168 / restaurant 161), every individual shift in band,
  **0 rolls that wanted a pocket and found no room**, and the no-repeat exclusion still perfect
  (384 rolled with a kind excluded, 0 were it). Adding a kind does not move the rate, as phase 1
  predicted: the curve is how often *a* pocket appears, not which one.
- `tools/mapcheck.gd --build_pocket=chapel`: **100% pocket navigation coverage**, every entrance
  walked out through its own seam, nothing unreachable and nothing resting on air. Only the
  pre-existing morgue-tray failures remain (FAILING_TESTS 2).
- `tools/pockettest.tscn`: **the Chapel alone passes 102 checks** (`--only=chapel`), her follow
  through the seam a healthy 9.2 s / 3.9 m. On the merged four-space tree the whole run is
  **FAILED 4 of 430**, and all four are the known FAILING_TESTS 1f Night Nurse check in
  `restaurant` and `natatorium` -- the Chapel and the Factory pass it. Since this phase changes
  Night Nurse behaviour, that distinction is the one to check first if 1f ever moves.
- `tools/trinkettest.tscn`: **PASS**, with eleven new candle checks — including *she is frozen,
  observed with the room empty*, that a step outside the radius ends it, and that burning out ends
  it too.
- **The smoke look mattered here more than any of the above**, and is worth a line because a
  headless suite cannot see a dark room. `tools/gameshot.tscn -- --pocket=chapel` (shots in
  `tools/game_shots/p_chapel_*.png`) caught, in order: **no votive rack had ever been placed** —
  their free-tile test was grown by one and so reached into the outer wall they stand against, and
  every rack in the building was refused without a word; the pooled lights were tuned to a single
  candle's brightness when each stands in for a bank of them, so from the narthex the nave was
  black with one orange dot 60 m away; there was no light down the nave at all, only on the aisle
  walls; and the volumetric fog was so dense that the 24 m vault, the one thing the space is meant
  to lose in the dark, was a bright olive ceiling. All four are fixed and the shots now read as a
  cathedral. **Every one of these passed every headless check while it was broken.**
- **`tools/perfprobe` was run**, and after three contended attempts across the day it was finally
  re-read on a **genuinely idle machine** (zero other Godot processes) against the **final**
  content -- the votive racks, the stronger pooled lights, all of it -- with
  `tools\perfprobe.ps1 -Extra "--pocket=chapel"`. Main's launcher is the right one and corrects a
  real mistake of mine: it uses SW_SHOWNOACTIVATE, because a **minimized window does not render**
  and the frame times it gives are meaningless. **At medium (q1) the Chapel clears the bar with
  room to spare:**

  | view (q1, medium) | avg fps | 1% low | draws |
  |---|---|---|---|
  | **chapel: the whole nave** (the designed worst frame) | **112** | **93** | 641 |
  | chapel: the reredos close up | 134 | 110 | 337 |
  | chapel: down a side aisle | 115 | 98 | 634 |
  | chapel: an entrance from inside | 139 | 101 | 270 |
  | chapel: seam, hospital side | 108 | 81 | 191 |
  | *hospital corridor on the same map (baseline)* | *86* | *30* | *445* |

  Against a bar of 60 avg and 1% lows above 50, the worst Chapel view is **112 / 93**. Every view
  in the space beats the hospital corridor it opens off, on both numbers.
  **One thing for somebody else:** that corridor baseline's 1% low of **30** is the only figure in
  the table under the bar, and it is untouched hospital, not the Chapel -- it is the first scenario
  measured and may just be the run settling, but it is worth a look by whoever owns the hospital.
  At low (q0) and high (q2) the Chapel is 108-156 and 41-55 avg respectively; q2 is below 60 across
  the board including the corridor, which is what "high" costs on this machine and not new.

**Merged with `main` at 0.10.35 (the Natatorium and the syringe), and what that changed.**
- **Origin moved to (800, 1500)**: the Natatorium had taken (800, 1000), which I had also picked.
  Two spaces at one origin would build on top of each other.
- **`script_of`, not `script_for`**: the Natatorium replaced the same ternaries independently and
  landed first, so the merge took its name and the Chapel is one more entry in `LAYOUTS`. Same for
  `perfprobe --pocket=<kind>`, which both of us added after hitting the same renderer crash.
- **The syringe was the conflict that mattered.** `Syringes.FLUIDS` already forward-declared
  `communion_wine`, so a syringe can be loaded from the wine — and `surgery_step_done` now spends
  the *syringe*, not the vial. Resolved mechanically, that would have laundered the wine into a
  full-strength dose: the hand holds a syringe, so the substitute lookup would have missed it. The
  merged version reads `Syringes.held_loaded(p).fluid` **before** `spend_loaded` clears it, so a
  dose is weakened by what it actually was however it arrived. `can_begin` accepts a substitute
  vial in the fallback path the same way.
- **The Chapel's loot went pocket-only**, dropping the small `office` / `waiting_room` / `"*"`
  weights the plate and the candle had. The Natatorium's two name only their own room kinds and no
  `"*"`, and the Laundromat is landing a `loot_spawner._can_place` fix for exactly the leak that
  causes. Matching the other spaces is worth more than a rare plate in a waiting room, and the
  bleed-out task is the right way to put pocket items in the hospital deliberately.
- **`POCKET_ITEMS`** is the agreed name (renamed from my `ITEM_KINDS`), beside `AMBIENT_NOISE_LEVEL`.
- **Review setup**: `--setup=chapel`, built on the Natatorium's `ReviewSetups.before_session` hook
  rather than a competing one. It drops you in the processional aisle with all three items in hand
  and a Night Nurse walking down the nave at you.
- FAILING_TESTS: my `suture_kit` section folded into main's `1k` (both tasks confirmed it
  independently) and my perfprobe section merged with phase 2's evidence.

**Unsure / for whoever merges.** The three sedation touch points (`surgery_system.can_begin`,
`game.surgery_step_done`, `dissection._anesthetic_slot`/`redose`) are the likeliest merge conflict
with the syringe-rack task, which is moving DRAW!/FLICK! out of the OR. Nothing here restructures
the injection, but the lines are close together.

## Phase 4 — the Laundromat — DONE 2026-09-22, branch `pockets-laundromat`
Coin-op, fluorescent, every machine running with nothing inside.
Built entirely from the phase 1 knob, as planned: the space adds no
sound system and no monster rule, only `AMBIENT_NOISE_LEVEL = 0.30`.

`scripts/level/pockets/laundromat.gd`, origin (800, 2000). A 38 x 15
hall with back-to-back washer islands down the middle (~90 of them,
broken by cross aisles), stacked dryer banks along both long walls
(62), folding tables, a row of moulded chairs, a change machine, and
a utility room and attendant's office off the back wall. 3 of 3
entrances placed on every seed tried.

### The masking, measured
The claim "tuned so the drone genuinely masks footsteps" is arithmetic
over numbers that already existed, not a guess:
- `Game.FOOTSTEP_LOUDNESS` **0.25** walking, `FOOTSTEP_SPRINT_LOUDNESS`
  **0.8** sprinting (they were inline literals in `_tick_noise`; this
  phase named them so the test reads them instead of retyping them).
- `SonographerBrain.HEAR_PER_LOUDNESS` **22 m per unit of loudness**,
  and the floor is subtracted before it (phase 1's `_hear`).

At **0.30**:
- a walking step masks to **0.0** and carries **0 m** — unheard in the
  room at any range, with 0.05 of headroom over the 0.25 it has to
  swallow (a floor of exactly 0.25 also works, but on a knife edge);
- outside, the same step is untouched and carries **5.5 m**;
- a sprint masks to 0.50 and carries **11 m** instead of 17.6, and
  drops under the brain's `LOUD` (0.8), so sprinting in here fills
  suspicion instead of pinning you outright;
- a thrown handful of quarters (`Game.QUARTER_NOISE`, 0.9) masks to
  0.60 and still carries **13 m** in the room, 19.8 m outside — which
  is what keeps it worth throwing where you found it.

Phase 7's acceptance test is written and passing already, in
`tools/pockettest.gd` `_footstep_masking`: the arithmetic above, read
from the two source files rather than retyped, **plus a live half** —
a real Sonographer 4 m from a real walking player, once inside and
once out in the hospital, asking the brain what it heard. Inside:
nothing. Outside: the footsteps.

### Perf, measured
Phase 1 skipped `tools/perfprobe` deliberately and said phases 2-4 must
run it. Run, on the Radeon 890M, medium (`--quality=1`), 180 frames a
view, in a **windowed 1600x900** run that never took focus
(`tools/perfprobe.ps1`, new: the same never-activate WMI trick as
`mirrorshot.ps1` / `vatshot.ps1`; there was no launcher for perfprobe at
all before, and a headless run renders nothing so its numbers are
worthless).

**Read the room against the hospital corridor measured in the same run,
not against the absolute 60/50.** Runs A (before the room was brightened),
B (after), C (after the machines were widened into banks) and D (after
the merge, on main's launcher). The other two phases were building on the
same machine throughout — nine Godot processes by the end — which is why
the absolute numbers fall through the floor and why only the same-run
comparison means anything:

| view | A | B | C | D |
| --- | --- | --- | --- | --- |
| **that map's hospital corridor** (the control) | **49 / 36** | **31 / 17** | **17 / 10** | **9 / 7** |
| laundromat: the length of the room | 51 / 39 | 32 / 16 | 20 / 11 | 9 / 7 |
| laundromat: corner to corner | 47 / 37 | 40 / 25 | 19 / 10 | 9 / 7 |
| laundromat: down an aisle | 45 / 35 | 39 / 29 | 23 / 11 | 9 / 7 |
| laundromat: an entrance from inside | 47 / 38 | 42 / 31 | 19 / 9 | 9 / 7 |
| laundromat: seam, hospital side | 41 / 30 | 40 / 30 | 18 / 9 | 9 / 7 |
| laundromat: seam, pocket side | 41 / 30 | 40 / 32 | 17 / 9 | — |

**Run D is not data and should not be quoted.** Every view came back at
exactly 9 / 7, the control included, with 113-131 ms of *script* time a
frame: that is the CPU contending with eight other Godot processes, not
the scene. It is in the table only as the evidence that the machine was
unusable, and because it was taken with main's launcher
(`SW_SHOWNOACTIVATE`) rather than the minimized one runs A-C used — main
found that a minimized window does not render honestly, so **A-C want
re-taking on an idle machine with that launcher before anyone trusts
their absolute values either.**

What does survive all four runs is the shape: in A, B and C every view of
the room sits at or above the hospital corridor of the map it is in, on
fewer draw calls (125-397 inside against 432-437 for the corridor), and
in D everything including the control is equally pinned. Nothing in any
run suggests the room costs more to look at than the hospital beside it,
which is the claim a new space has to be able to make. The absolute bar
(60 fps, 1% lows above 50) is not met on this machine in a windowed run
by the hospital either — the plain baseline sweep, taken when it was
quieter, gives "corridor, long sightline" 48 / 27 and "lobby clock-in
room" 31 / 17. That is pre-existing and wants its own look.

For scale, the same probe on the **Factory**, which has shipped since the
first sweep: 27-39 fps avg and **14-30** 1% lows, with its map's own
hospital corridor at 32 / 15. The Laundromat is a good deal cheaper than
the pocket space the bar was originally written against.

**`perfprobe --pockets` crashes, on `main` as much as here.** It restarts
the session once per kind, and in a windowed run that trips the Godot
renderer bug docs/KNOWN_ISSUES.md already records ("BUG, indexing did not
unpair geometries from light") and dies with signal 11 after warmup,
before it measures anything. Verified by running it on a detached
checkout of `main` (3b30969): same crash, same place. **`--pocket=<kind>`**
— one space, forced before the first session is built and never rebuilt —
is the way round it, and phases 2 and 4 arrived at it independently; the
merge kept phase 2's version. See docs/FAILING_TESTS.md 1l.

### The three items
`Laundromat.POCKET_ITEMS` declares the set (see "the item set" below).
All three give the `laundromat` / `laundromat_back` room kinds a weight
in `loot_table.gd` and **no `"*"` weight**, so they are found here and
nowhere else. All three are primitives in `loot_models.gd` (no CC0
model exists for any of them; searched, recorded in ASSETS.md).

- **BUCKET OF QUARTERS** (`quarter_bucket`): stacked loot, 3-5
  handfuls. A **charged throw** flings one handful, which bursts where
  it lands rather than settling as a pickup, and emits the noise
  *there* — the directional part. A tap sets the bucket down normally.
  It reuses the placebo-pill throw pattern exactly (a branch in
  `game.drop_selected`, a meta flag, and a resolver on `game`); the one
  new thing is a per-kind branch in `world_item.gd`'s settle block,
  which had no hook of any kind before.
- **WARM SCRUBS** (`warm_scrubs`): loot that also unlocks a scrub
  pattern. **The spec's "if the mirror isn't ready" fallback was
  obsolete but its premise was still wrong**: the mirror and its four
  patterns shipped in 0.10.12/0.10.14, but there was no *unlock*
  concept anywhere in the game — every pattern was available to
  everyone from the first shift, so there was nothing to grant. So
  this phase added the smallest one that works: a per-machine bitmask
  in `settings.cfg` (`patterns_unlocked`), a fifth pattern **Gingham**
  appended to `Customization.PATTERNS` behind it, and a branch in the
  cloth shader to draw it. Holding a set of warm scrubs grants it, on
  the holder's own machine, for good.
  **The multiplayer trap, avoided deliberately**: `sanitize()` runs on
  every *remote* player's unpacked look, so gating there would strip a
  teammate's earned pattern on a machine that had not earned it. The
  gate is in `cycle()` only, which is the sole way a look is chosen.
- **FABRIC SOFTENER JUG** (`fabric_softener`): a one-use trinket in
  the 0.10.24 system (`trinkets.gd`), scrap value 4. **The spec says
  "E from hands"; that predates the trinket system, where every
  trinket is left mouse.** It is left mouse, like the other six.
  Drinking it suppresses the footstep *noise event* for 60 s at full
  speed. "Crouch noise multiplier" turned out to be a suppression
  rather than a multiplier — `game._tick_noise` skips a crouching
  player entirely — so `Player.silent_steps` makes it skip a drinker
  the same way. That is the existing multiplier reused, not a second
  quiet mode. You still hear your own steps at -12 dB, so you can tell
  it is working; nothing that hunts by sound hears anything.

### The item set (for the "bleeding out" follow-up)
A pocket's items can also spawn in ordinary hospital rooms within a
radius of that pocket's entrance — a separate task. **No convention
for "this space's item kinds" existed**: the Factory and the
Restaurant contribute no kinds of their own, and loot is keyed by
`room_kind` in `loot_table.gd`. The smallest one that works is a
`const POCKET_ITEMS` on the layout script, next to `AMBIENT_NOISE_LEVEL`.
**Phase 2 reached the same conclusion independently and the name is now
settled across all three spaces**, so a new space declares `POCKET_ITEMS`
and the bleed-out task finds one shape everywhere.
Warm scrubs is in the set, but whether a permanent cosmetic unlock
*should* bleed into a corridor is the follow-up's call, not this one's.

### One shared-file fix, which the Natatorium needed too
`LootSpawner._draw_trinkets` drew the shift's 3-5 trinkets from every
trinket kind, knowing nothing about the level. A pocket-only trinket
has no `"*"` room weight, so on a shift without its space the draw
burned one of those few slots, and the swap pass at the end of `plan()`
then parachuted it into a hospital room it must never appear in. The
draw now only offers kinds the level has a positive-weight, fitting
location for (`_can_place`). Every hospital kind has a `"*"` weight, so
this is a no-op for everything that existed.

**This was live on `main`.** The Natatorium's `lifeguard_whistle` has the
same shape — natatorium room weights, no `"*"` — so from 0.10.35 until
this merge, a whistle could be drawn on a shift with no Natatorium and
placed in a hospital room. The Chapel's votive candle will want the same
thing. Two other things the merge caught in the same family: `loottest`
had never been told about the Natatorium's two kinds, so it was failing
its "every kind is a kept kind" check on `main`; and its pocket-only
assertions are now driven by a `POCKET_ONLY` table of kind -> its space's
room kinds, so a new space's items are checked the day they are added.

## Phase 5 — items for the existing spaces
Factory:
- GREASE BUCKET: TODO trinket. Slathered on the floor it makes a
  slip patch — monsters and teammates crossing it lose footing.
  Blocked on slide/knockdown states existing; spawns and sells now.
- COPPER WIRE SPOOL: plain loot, bulky, two hands.
- FOREMAN'S CLIPBOARD: loot, X-ray-film tier. A shift schedule with
  no dates and names crossed out.
Restaurant:
- TEQUILA, TOP SHELF: anesthetic substitute, batch of 1, same weak-
  dose rule as communion wine.
- CAST IRON MOLCAJETE: loot, gold-watch tier, heavy.
- RESTAURANT PAGERS, PAIR OF 2: trinket. Spawn as a base station
  holding two bound pagers. Pressing one silently buzzes the other
  (a sound only its holder hears, small HUD shake), anywhere in the
  hospital, short cooldown. A pager set down or dropped rattles
  audibly on the floor when buzzed — a remote noisemaker. Selling
  either breaks the pair; a lone pager is plain loot.
Database: tag whistle, quarters and a planted pager with one shared
"lure" tag so they read as a family.

## Phase 6 — the pocket monster (working name: the Onlooker)
The fourth sense rule. Hive = eyes, Sonographer = ears, Night Nurse
= being watched. The Onlooker = ATTENTION: it feeds on being seen
and ignored. It is the inverse of the Night Nurse — you get rid of
it by going TOWARD it.

- Spawns only in pocket spaces (their scale is why it fits — it
  needs long sightlines). Never in the hospital proper.
- A tall shadow with bright eyes. It pops in far away, always
  placed directly in a player's view when it appears. It does not
  approach. It stares.
- It TELEPORTS ("hops"): every so often it vanishes and reappears
  at another far point in that player's view, so it can't be
  escaped by turning around — it relocates into your new sightline.
- The counter is aggression: run AT it. Closing to within a set
  range makes it vanish for a long cooldown. Shoves, the saw and
  the needle do nothing.
- If it stays on screen too long ignored, it starts eating you: a
  slow heart tick while its stare persists, ramping the longer it
  goes. (We do not have a sanity system; use hearts. If a sanity/
  fear meter ever lands, this becomes its first user — mark that
  as an IDEA in DESIGN.md, don't build it.)
- Escaping through a seam ends the encounter.
- Sound: none. It is silent. The tell is purely visual, so the
  fear is checking your sightlines.
- No brain, no harvest, no strap — like the Night Nurse it is one
  you deal with, not one you farm. Database entry caps at tier 2.
- Tuning knobs: spawn chance per pocket, stare-time before the
  tick starts, tick rate ramp, banish range, hop interval,
  vanish cooldown.
- Tests: monster_lab scenario for spawn-in-view placement, hop
  relocation into view, banish by approach, tick after the grace
  period, and seam escape. Bot-walk each pocket with it enabled.

## Phase 7 — validation
- tools/mapcheck.gd passes many seeds with all five kinds.
- pockettest extended to the three new spaces (seams, crossings,
  carried bodies, noise mirroring, shift rebuild).
- Headless bot walk through every entrance of each new space.
- Sonographer: standing footsteps unheard inside the Laundromat at
  the tuned threshold, heard outside. **Done in phase 4** —
  `tools/pockettest.gd` `_footstep_masking`, both halves.
- Night Nurse: frozen in a placed candle radius with no player
  looking; moves when it burns out.
- Onlooker: the monster_lab scenarios above.
- tools/gameshot shots of each space, each seam from the hallway
  side, and the Onlooker mid-stare in the Factory fog.
- docs/MORNING_REPORT.md with START HERE, judgment calls, skips.
